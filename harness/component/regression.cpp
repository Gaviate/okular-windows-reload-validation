// SPDX-License-Identifier: GPL-2.0-or-later
// Original diagnostic attributed to Gaviate.
// The proposed GooFile sharing change was already published by hawkeye0386
// in Poppler MR !2366; this original diagnostic holds GooFile open through deletion.
#include "gfile.h"
#include <cstring>
#include <filesystem>
#include <iostream>
#include <string>
#include <windows.h>

static bool writeFixture(const std::wstring &path, const char *payload, DWORD &error)
{
    HANDLE handle = CreateFileW(path.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (handle == INVALID_HANDLE_VALUE) {
        error = GetLastError();
        return false;
    }
    DWORD written = 0;
    const DWORD length = static_cast<DWORD>(strlen(payload));
    const bool success = WriteFile(handle, payload, length, &written, nullptr) && written == length;
    error = success ? 0 : GetLastError();
    CloseHandle(handle);
    return success;
}

static int inspect(const std::wstring &directory, const char *variant, bool wide, bool filesystemDelete)
{
    const std::wstring name = wide ? L"unicode-\u4e2d\u6587.pdf" : L"ascii.pdf";
    const std::wstring path = directory + L"\\" + name;
    DWORD error = 0;
    if (!writeFixture(path, "original harmless fixture\n", error)) {
        std::cerr << "fixture creation failed " << error << '\n';
        return 1;
    }
    auto reader = wide ? GooFile::open(path.c_str()) : GooFile::open(std::filesystem::path(path).string());
    if (!reader) return 2;
    bool deleted = false;
    DWORD deleteError = 0;
    if (filesystemDelete) {
        std::error_code ec;
        deleted = std::filesystem::remove(path, ec);
        deleteError = ec.value();
    } else {
        deleted = DeleteFileW(path.c_str());
        if (!deleted) deleteError = GetLastError();
    }
    DWORD recreateError = 0;
    const bool recreatedWhileOpen = writeFixture(path, "replacement harmless fixture\n", recreateError);
    auto reopenedReader = GooFile::open(path.c_str());
    char currentContents[64] = {};
    const int currentBytes = reopenedReader ? reopenedReader->read(currentContents, 63, 0) : -1;
    const std::string expectedCurrent = recreatedWhileOpen ? "replacement harmless fixture\n" : "original harmless fixture\n";
    const bool reopenedReaderCorrect = currentBytes > 0 && std::string(currentContents, currentBytes) == expectedCurrent;
    reopenedReader.reset();
    char oldContents[64] = {};
    const int oldBytes = reader->read(oldContents, 63, 0);
    const bool oldReaderPreserved = oldBytes > 0 && std::string(oldContents, oldBytes) == "original harmless fixture\n";
    reader.reset();
    DWORD afterCloseError = 0;
    bool recreatedAfterClose = recreatedWhileOpen;
    if (!recreatedWhileOpen && deleted) recreatedAfterClose = writeFixture(path, "replacement harmless fixture\n", afterCloseError);
    std::cout << "{\"variant\":\"" << variant << "\",\"path_kind\":\"" << (wide ? "unicode" : "ascii")
              << "\",\"delete_api\":\"" << (filesystemDelete ? "std::filesystem::remove" : "DeleteFileW")
              << "\",\"deleted\":" << (deleted ? "true" : "false") << ",\"delete_error\":" << deleteError
              << ",\"recreated_while_reader_open\":" << (recreatedWhileOpen ? "true" : "false") << ",\"recreate_error\":" << recreateError
              << ",\"old_reader_preserved\":" << (oldReaderPreserved ? "true" : "false")
              << ",\"reopened_reader_has_expected_contents\":" << (reopenedReaderCorrect ? "true" : "false")
              << ",\"recreated_after_reader_closed\":" << (recreatedAfterClose ? "true" : "false") << ",\"after_close_error\":" << afterCloseError << "}\n";
    DeleteFileW(path.c_str());
    const bool baseline = std::string(variant) == "baseline";
    const bool sharingExpected = baseline ? (!deleted && deleteError == ERROR_SHARING_VIOLATION && !recreatedWhileOpen)
                                         : (deleted && deleteError == 0 && recreatedWhileOpen && recreateError == 0);
    return oldReaderPreserved && reopenedReaderCorrect && sharingExpected ? 0 : 3;
}

int wmain(int argc, wchar_t **argv)
{
    if (argc != 3) return 10;
    const std::wstring root = argv[1];
    const std::string variant = std::filesystem::path(argv[2]).string();
    int failures = 0;
    for (bool wide : {false, true}) {
        for (bool fs : {false, true}) {
            const auto directory = root + L"\\" + (wide ? L"wide" : L"narrow") + (fs ? L"-filesystem" : L"-win32");
            std::filesystem::create_directories(directory);
            failures += inspect(directory, variant.c_str(), wide, fs);
        }
    }
    return failures ? 1 : 0;
}
