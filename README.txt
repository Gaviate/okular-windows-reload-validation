Windows Okular deletion/recreation and automatic reload: source review package
Attribution: Gaviate. Prepared 2026-10-03. No public submission or acceptance yet.

Scope and changes
-----------------
The actual official Windows Okular EXE/PDF generator running offscreen with
source-built matching Poppler26.07.0 and KCoreAddons6.30.0 successfully handles
raw DeleteFileW followed by CREATE_NEW of a benign PDF at the same pathname.
It automatically reopens the replacement and dispatches its second page for
rendering. The four ASCII/Unicode x immediate/2000ms cases each passed three
replacements within the same process (12 cycles). Three further Unicode
cycles verified the final cleanup wait. Completed pixels/visible GUI were
not asserted. No manual reload or injected watcher event was used.

Poppler's two FILE_SHARE_DELETE additions are the prior implementation and
discovery of hawkeye0386, MR !2366, closed/unmerged with unknown closing reason:
https://gitlab.freedesktop.org/poppler/poppler/-/merge_requests/2366
They must retain this credit. No prior GitHub validation harness was copied.

The new KCoreAddons repair uses Windows wide stat calls at three existing
sites, matching QT_STATBUF, preserving the non-Windows implementation. It
extends the existing lifecycle test to ASCII, Unicode filename and Unicode
directory rows (five cycles each). Poppler-only Unicode auto-reload failures
were preserved; its flags alone pass ASCII but cannot fix this watcher issue.

Both clean source-built matching libraries reproduce the locking failure in
all four viewer controls: deletion error32, recreation error80, no reopen.
Both patched watcher backends pass all three functional rows on matched6.30
and current6.32 (five checks including init/cleanup, exit0). Clean6.30 controls
fail exactly the two Unicode rows (exit2). Both source versions build all63
selected steps. Redacted receipts preserve exact outcomes and binary hashes.

Patches and versions
--------------------
kcoreaddons-wide-stat-current-master.patch
  current master c4ad4b9a28bc462df71df10f7b8f306d7b089f2a / 6.32.0
kcoreaddons-wide-stat-6.30.0.patch
  matching tag d89bd6cba6b6e8c7eb476960948e9fbbbc304c46
poppler-share-delete-current-master-credited.patch
  current master 26e53b60bb099e2598a2a72a0d280d9cac9e5774
poppler-share-delete-26.07.0-credited.patch
  matching tag b7989c187daee307b782ac4592cddb1ae0677b76

Official viewer snapshot:
https://cdn.kde.org/ci-builds/graphics/okular/master/windows/okular-master-8118-windows-cl-msvc2022-x86_64.7z
archive SHA256919e044e36da4493af78a3f8ac161da34844b5daf8a81bdff8abec31414e2b17
Qt6.11.1; MSVC19.37; Windows11/NTFS. Exact source patch and included artifact
hashes are in public-manifest.json. Upstream copyright/license headers remain
unchanged. Public receipt hashes also identify the full original local
receipts without exposing their local paths or process IDs.

Portable original harness
-------------------------
harness/fixture_pdf.py uses only Python's standard library to create benign
one-page and two-page PDFs. The Windows PowerShell controller launches an
offscreen viewer, observes existing Okular logs, holds to the actual raw
deletion/recreation sequence, verifies pathname contents, and checks loaded
library paths/hashes. Each repeated cycle requires a new byte-length metadata
reopen before subsequent page1 render dispatch, so stale events cannot pass.
The public copy changes only Python executable configuration (default python,
optional -PythonExecutable) and an attribution comment. Test logic is the
tested local controller; no additional runtime verification is claimed for
these packaging changes.

Place a matching Windows viewer tree as harness/viewer (this package includes
no runtime) and invoke, for example:

  ./harness/viewer-reload-regression.ps1 -ViewerDirectory viewer -Variant local -ExpectDeletion $true -UnicodePath $true -RecreationDelayMs 0 -ReplacementCycles 3 -PythonExecutable python

Use your locally built candidate DLLs with matching dependencies for a
candidate run; a clean baseline uses -ExpectDeletion $false and one cycle.
Use ASCII/Unicode and0/2000ms for the full matrix. Apply the KCoreAddons patch
to the corresponding checkout, build the existing kdirwatch_qfswatch_unittest
and kdirwatch_stat_unittest targets, and select only testDeleteAndRecreateFile
for the described unit scope. component/regression.cpp is the independent
Windows GooFile deletion/held-reader diagnostic, built against actual gfile.cc.
Its original CMake/support configuration is included. In an MSVC developer
shell, configure with -DGOO_SOURCE_DIR pointing to the selected Poppler goo
directory, build, and run delete_recreate.exe with a synthetic output
directory as the first argument and baseline or patched as the second. No SDK or
upstream source is bundled.

Limits and licensing
--------------------
This package contains source and minimal redacted outcomes only: no DLLs,
SDKs, credentials, user profile data, absolute user paths or raw viewer logs.
The measured scope is Windows11/NTFS and benign fixture PDFs. MinGW/Linux,
other filesystems, atomic rename, the sponsor's private drawing application,
completed rendering and full codec compatibility remain untested here.
Optional JPEG/PNG/TIFF/OpenJPEG/CURL/Boost features were disabled identically
in the Poppler A/B builds; required poppler-qt6 imports resolve but poppler-cpp
imagewriter exports remain absent. These test builds are not a production
distribution. Current6.32 KCoreAddons was unit tested only; the actual viewer
uses matching6.30. Normal Qt standard metadata locations were used for the
synthetic fixtures; no isolated-profile claim is made.

The Poppler flags are GPL-2.0-or-later; KCoreAddons source is LGPL-2.0-only
and its existing autotest LGPL-2.0-or-later. Their existing headers are
preserved. Original validation source is GPL-2.0-or-later, as explained in
LICENSE-original-validation.txt; full GPLv2 text is included. No SDK or
third-party runtime redistribution occurs here.

Prospective delivery is through official KDE Invent for the new KCoreAddons
contribution and a credited follow-up to the existing Poppler proposal. This
package does not imply maintainer approval, account availability or payment.
The public request at
https://discuss.kde.org/t/paid-request-okular-don-t-lock-file-for-overwrite/49519
expresses EUR20 willingness to donate to KDE OR the fixer; its payment rail,
reservation and acceptance are unknown. Cash received0; cash owed0.


Additional pixel observations — 2026-10-03
------------------------------------------
A separate offscreen packaged Part/PageView test now observes actual blue
first-page fixture pixels after automatic delete/recreate reload in four
ASCII/Unicode x immediate/2000ms cases. Only afterward, intentional goToPage(2)
shows green second-page fixture pixels. Four clean matched controls retain
original red pixels with deletion error32/recreation error80. The assertion
is fixture-colored viewport regions, not whole-page final render completion
or unchanged-shell desktop output. The earlier 12 same-process dispatch cycles
and all contributor attribution remain unchanged. See pixel-observations/README.txt
for the source, 8 case receipts, 20 raw viewport PNGs, hashes and limits.
