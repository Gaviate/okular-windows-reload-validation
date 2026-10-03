// SPDX-FileCopyrightText: 2026 Gaviate
// SPDX-License-Identifier: GPL-2.0-or-later
// Owned offscreen integration test: no desktop controls or document reload calls.
#include <QApplication>
#include <QAbstractScrollArea>
#include <QCryptographicHash>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QImage>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPluginLoader>
#include <QThread>
#include <QWidget>
#include <kpluginfactory.h>
#include <windows.h>
#include <cstdio>

struct Pixels {
    QImage image;
    int red = 0, blue = 0, green = 0;
    QJsonObject receipt() const {
        return {{"width", image.width()}, {"height", image.height()},
                {"red_pixels", red}, {"blue_pixels", blue}, {"green_pixels", green},
                {"pixel_bytes_sha256", QString::fromLatin1(QCryptographicHash::hash(
                    QByteArray(reinterpret_cast<const char *>(image.constBits()), image.sizeInBytes()),
                    QCryptographicHash::Sha256).toHex())}};
    }
};

static Pixels observe(QAbstractScrollArea *view) {
    Pixels p;
    // QWidget::grab paints the actual Okular PageView viewport into a QPixmap.
    // The test supplies no painter, decoded image, or replacement pixel buffer.
    p.image = view->viewport()->grab().toImage().convertToFormat(QImage::Format_RGB32);
    for (int y = 0; y < p.image.height(); ++y) {
        const auto *line = reinterpret_cast<const QRgb *>(p.image.constScanLine(y));
        for (int x = 0; x < p.image.width(); ++x) {
            const auto c = line[x];
            if (qRed(c) > 240 && qGreen(c) < 15 && qBlue(c) < 15) ++p.red;
            if (qBlue(c) > 240 && qRed(c) < 15 && qGreen(c) < 15) ++p.blue;
            if (qGreen(c) > 240 && qRed(c) < 15 && qBlue(c) < 15) ++p.green;
        }
    }
    return p;
}

static QJsonObject moduleReceipt(const QString &runtime, const wchar_t *name, const QString &relativePath) {
    wchar_t loadedPath[32768];
    const auto module = GetModuleHandleW(name);
    if (!module || !GetModuleFileNameW(module, loadedPath, 32768)) throw "Expected runtime module not loaded";
    const QString actual = QFileInfo(QString::fromWCharArray(loadedPath)).canonicalFilePath();
    const QString expected = QFileInfo(runtime + QStringLiteral("/") + relativePath).canonicalFilePath();
    if (actual.compare(expected, Qt::CaseInsensitive) != 0) throw "Loaded module differs from intended paired runtime";
    QFile file(actual);
    if (!file.open(QIODevice::ReadOnly)) throw "Cannot hash loaded runtime module";
    return {{"relative_path", QDir(runtime).relativeFilePath(actual)}, {"intended_runtime_path_verified", true},
            {"sha256", QString::fromLatin1(QCryptographicHash::hash(file.readAll(), QCryptographicHash::Sha256).toHex())}};
}

static void savePixels(const QImage &image, const QString &path) {
    if (!image.save(path)) throw "Actual viewport PNG save failed";
}

static uint pages(QObject *part) {
    uint result = 0;
    if (!QMetaObject::invokeMethod(part, "pages", Qt::DirectConnection, Q_RETURN_ARG(uint, result))) {
        throw "Part::pages API unavailable";
    }
    return result;
}

static Pixels awaitPixels(QObject *part, QAbstractScrollArea *view, int expectedColor, uint expectedPages, int timeoutMs) {
    QElapsedTimer timer;
    timer.start();
    Pixels result;
    while (timer.elapsed() < timeoutMs) {
        QApplication::processEvents(QEventLoop::AllEvents, 30);
        result = observe(view);
        int count = expectedColor == 0 ? result.red : expectedColor == 1 ? result.blue : result.green;
        if (pages(part) == expectedPages && count >= 500) return result;
        QThread::msleep(25);
    }
    return result;
}

int main(int argc, char **argv) {
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("okular-replacement-pixels"));
    try {
        const auto args = app.arguments();
        if (args.size() != 7) throw "Arguments: runtime initial replacement output expectDeletion delayMs";
        const QString runtime = args[1], path = args[2], replacement = args[3], output = args[4];
        const bool expectedDeletion = args[5] == QStringLiteral("true");
        const int delayMs = args[6].toInt();
        if (QApplication::platformName() != QStringLiteral("offscreen")) throw "This owned test requires offscreen QPA";
        QCoreApplication::addLibraryPath(runtime);
        QPluginLoader loader(runtime + QStringLiteral("/kf6/parts/okularpart.dll"));
        auto *factory = qobject_cast<KPluginFactory *>(loader.instance());
        if (!factory) {
            qCritical("Plugin load failed: %s", qPrintable(loader.errorString()));
            throw "Actual packaged Okular part could not be loaded";
        }
        QObject owner;
        QObject *part = factory->create<QObject>(&owner);
        if (!part) throw "Actual Okular Part creation failed";
        QAbstractScrollArea *view = nullptr;
        for (auto *widget : QApplication::allWidgets()) {
            if (QString::fromLatin1(widget->metaObject()->className()) == QStringLiteral("PageView")) {
                if (view) throw "Multiple PageViews found";
                view = qobject_cast<QAbstractScrollArea *>(widget);
            }
        }
        if (!view) throw "Actual PageView widget missing";
        view->window()->resize(800, 1200);
        view->window()->show(); // Offscreen QPA only; this test controls its own Qt widgets.
        if (!QMetaObject::invokeMethod(part, "openDocument", Qt::DirectConnection, Q_ARG(QString, path))) {
            throw "Part::openDocument API unavailable";
        }
        Pixels initial = awaitPixels(part, view, 0, 1, 10000);
        const bool initialPass = pages(part) == 1 && initial.red >= 500 && initial.blue == 0 && initial.green == 0;
        if (!initialPass) throw "Initial actual viewer pixels are not the red one-page fixture";
        savePixels(initial.image, output + QStringLiteral("-initial.png"));
        const QJsonObject modules{{"poppler", moduleReceipt(runtime, L"poppler.dll", QStringLiteral("poppler.dll"))},
            {"kcoreaddons", moduleReceipt(runtime, L"KF6CoreAddons.dll", QStringLiteral("KF6CoreAddons.dll"))},
            {"okularcore", moduleReceipt(runtime, L"Okular6Core.dll", QStringLiteral("Okular6Core.dll"))},
            {"okularpart", moduleReceipt(runtime, L"okularpart.dll", QStringLiteral("kf6/parts/okularpart.dll"))},
            {"pdf_generator", moduleReceipt(runtime, L"okularGenerator_poppler.dll", QStringLiteral("okular_generators/okularGenerator_poppler.dll"))},
            {"qtcore", moduleReceipt(runtime, L"Qt6Core.dll", QStringLiteral("Qt6Core.dll"))}};
        QFile replacementFile(replacement);
        if (!replacementFile.open(QIODevice::ReadOnly)) throw "Cannot read synthetic replacement";
        const QByteArray bytes = replacementFile.readAll();
        const bool deleted = DeleteFileW(reinterpret_cast<LPCWSTR>(path.utf16()));
        const DWORD deleteError = deleted ? 0 : GetLastError();
        QElapsedTimer delay;
        delay.start();
        while (delay.elapsed() < delayMs) {
            QApplication::processEvents(QEventLoop::AllEvents, 30);
            QThread::msleep(25);
        }
        HANDLE file = CreateFileW(reinterpret_cast<LPCWSTR>(path.utf16()), GENERIC_WRITE,
                                  FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, CREATE_NEW,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
        const bool recreated = file != INVALID_HANDLE_VALUE;
        const DWORD recreateError = recreated ? 0 : GetLastError();
        if (recreated) {
            DWORD written = 0;
            const bool wrote = WriteFile(file, bytes.constData(), DWORD(bytes.size()), &written, nullptr);
            CloseHandle(file);
            if (!wrote || written != DWORD(bytes.size())) throw "Synthetic replacement write failed";
        }
        if (!expectedDeletion) {
            QElapsedTimer controlObservation;
            controlObservation.start();
            while (controlObservation.elapsed() < 2000) {
                QApplication::processEvents(QEventLoop::AllEvents, 30);
                QThread::msleep(25);
            }
        }
        // Watcher owns all reopen/reload behavior. No further openDocument, reload,
        // openUrl or watcher signal calls occur after the initial fixture open.
        Pixels replacementPixels = awaitPixels(part, view, expectedDeletion ? 1 : 0, expectedDeletion ? 2 : 1, 10000);
        const uint resultingPages = pages(part);
        bool firstReplacementPage = expectedDeletion && resultingPages == 2 && replacementPixels.blue >= 500 && replacementPixels.red == 0;
        Pixels secondPage;
        bool secondReplacementPage = false;
        if (firstReplacementPage) {
            // Ordinary documented viewer navigation after an already verified
            // automatic reopen; page 2 has a distinct green fixture rectangle.
            if (!QMetaObject::invokeMethod(part, "goToPage", Qt::DirectConnection, Q_ARG(uint, 2u))) throw "Part::goToPage API unavailable";
            secondPage = awaitPixels(part, view, 2, 2, 10000);
            secondReplacementPage = secondPage.green >= 500 && secondPage.red == 0;
            savePixels(secondPage.image, output + QStringLiteral("-replacement-page2.png"));
        }
        savePixels(replacementPixels.image, output + QStringLiteral("-after.png"));
        const bool baselineRetained = !expectedDeletion && resultingPages == 1 && replacementPixels.red >= 500 && replacementPixels.blue == 0 && replacementPixels.green == 0;
        const bool passed = expectedDeletion ? deleted && recreated && firstReplacementPage && secondReplacementPage
                                             : !deleted && deleteError == ERROR_SHARING_VIOLATION && !recreated && recreateError == ERROR_FILE_EXISTS && baselineRetained;
        QJsonObject result{{"qpa_platform", QApplication::platformName()}, {"loaded_modules", modules},
            {"expected_deletion", expectedDeletion}, {"recreation_delay_ms", delayMs},
            {"initial_rendered_pixels_passed", initialPass}, {"deleted", deleted}, {"delete_error", int(deleteError)},
            {"recreated", recreated}, {"recreate_error", int(recreateError)}, {"pages_after_replacement", int(resultingPages)},
            {"automatic_replacement_page1_pixels_passed", firstReplacementPage},
            {"replacement_page2_pixels_after_navigation_passed", secondReplacementPage},
            {"baseline_original_pixels_retained", baselineRetained}, {"initial_pixels", initial.receipt()},
            {"after_pixels", replacementPixels.receipt()}, {"second_page_pixels", secondPage.receipt()}, {"passed", passed},
            {"control_extra_observation_ms", expectedDeletion ? 0 : 2000},
            {"observation", "Actual packaged Okular Part/PageView offscreen fixture-colored viewport pixels (threshold 500). Opened once; watcher automatically reopens. Page2 navigation occurs only after automatic page count and blue page1 pixels pass. Whole-page final generator completion is not asserted."},
            {"profile_limit", "Qt Windows normal QStandardPaths may store metadata for synthetic fixtures; private profile isolation is not claimed."}};
        QFile receipt(output + QStringLiteral("-result.json"));
        if (!receipt.open(QIODevice::WriteOnly)) throw "Cannot save result";
        receipt.write(QJsonDocument(result).toJson());
        std::puts(QJsonDocument(result).toJson(QJsonDocument::Compact).constData());
        delete part;
        return passed ? 0 : 1;
    } catch (const char *error) {
        std::fprintf(stderr, "TEST LIMIT/FAILURE: %s\n", error);
        return 2;
    }
}
