Offscreen Okular replacement fixture pixels — 2026-10-03

Four patched first-replacement cases (ASCII/Unicode x immediate/2000ms
recreation) pass. The actual packaged Okular Part/PageView opens a red one-page
synthetic PDF once. Its existing watcher automatically reopens the raw
DeleteFileW/CREATE_NEW replacement, and the viewport paints blue page-one
fixture pixels with no red pixels remaining. Only after that observation and
a two-page count does the test intentionally call goToPage(2), then observe
green page-two fixture pixels. Navigation to page two is intentional.

Four matching clean source-built controls reproduce deletion error32 and
recreation error80; the original red pixels and one-page count stay unchanged.
The checked Okular Part, Okular6Core, PDF-generator and Qt6Core DLLs are identical
across the pair. Only matching source-built Poppler 26.07.0 and KCoreAddons 6.30.0
are changed. Each receipt checks the actual loaded module paths and SHA256s.

These are actual QWidget::grab viewport captures from the packaged Part and
PageView, hosted by a small executable under asserted offscreen QPA. The probe
does not supply a decoded image or painter to Okular. It asserts at least 500
fixture-colored pixels; all candidate cases recorded 153663 blue, then 153663
green pixels, with zero original red. Because asynchronous rendering can send
partial updates, whole-page final completion and completion of every render job
are not asserted. This is a component host, not unchanged okular.exe shell or
visible desktop output. There is one replacement per process in these 8 cases.
The earlier 12 same-process metadata/reopen/render-dispatch cycles remain separate
and unchanged. No manual reload or post-initial openDocument/openUrl call occurs.

All 20 viewport PNGs are raw saved captures. Results expose relative module and
fixture filenames plus hashes, not full user paths. Raw workstation logs, SDKs,
DLLs and executables are excluded. Normal Windows QStandardPaths may write
metadata for synthetic fixtures; private profile isolation is not claimed.
Linux behavior, all drawing applications/deletion APIs and optional codec
coverage remain unclaimed. No payment or donation entitlement is asserted.

Attribution and licensing
The new test source is attributed to Gaviate under GPL-2.0-or-later, with the
existing root COPYING-original-validation.txt and LICENSE-original-validation.txt.
The existing Poppler FILE_SHARE_DELETE implementation remains credited to
hawkeye0386's prior Poppler MR2366. The existing KCoreAddons wide-stat patch and
earlier source/evidence are unchanged; this adds validation rather than a new
upstream source patch or rediscovery of the two Poppler flags.

Reproduction
Use Windows/MSVC and a disposable COPY of the packaged viewer runtime. Supply
compatible Qt6 development files, KCoreAddons source/generated headers/import
library, and the paired matching source-built Poppler/KCoreAddons DLLs. The
original run used Qt 6.11.1, Poppler 26.07.0 and KCoreAddons 6.30.0. No runtime is
bundled. From an MSVC developer PowerShell with CMake and Ninja available:

  ./build.ps1 -QtPrefix <QtSDK> -KCoreSource <KCoreSource> -KCoreBuild <KCoreBuild>

Then run in PowerShell 7, selecting only a disposable owned runtime copy:

  ./run-paired.ps1 -OwnedRuntimeDirectory <ViewerCopy/bin> `
    -BaselinePoppler <CleanPoppler.dll> -BaselineKCoreAddons <CleanKF6CoreAddons.dll> `
    -CandidatePoppler <PatchedPoppler.dll> -CandidateKCoreAddons <PatchedKF6CoreAddons.dll> `
    -Executable ./build/okular-replacement-pixels.exe -OutputDirectory <NewTaskDirectory>

Python is selected by -Python (default python); the unchanged fixture generator
is ../harness/fixture_pdf.py. The script replaces ONLY Poppler/KCoreAddons DLLs
in the supplied disposable runtime and restores the supplied candidate pair in
finally. It uses hidden owned processes and bounded waits; it does not control
desktop apps. The output contains local raw diagnostics and should not be
published without privacy review.

Source main.cpp and CMakeLists.txt are byte-identical to the executed local
probe/build input. The public build/run scripts are privacy/portability adapters
to explicit path parameters, syntactically checked but not re-executed. The 8
published receipts and 20 PNGs come from the executed local controller, not a claimed
run of these adapters. Each public case JSON retains the raw source receipt
SHA256 and adds case/Unicode/fixture-name metadata; assertion values are intact.
manifest.json records hashes and this mapping. An early local prototype launch
could not locate offscreen because its executable was outside the packaged bin;
the final controller explicitly supplies the packaged Qt plugin paths.
