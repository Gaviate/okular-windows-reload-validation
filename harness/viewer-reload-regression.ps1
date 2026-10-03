# Original ordinary functional regression controller. No user documents or UI control.
param(
    [Parameter(Mandatory=$true)][string]$ViewerDirectory,
    [Parameter(Mandatory=$true)][string]$Variant,
    [Parameter(Mandatory=$true)][bool]$ExpectDeletion,
    [ValidateSet(0,2000)][int]$RecreationDelayMs = 0,
    [bool]$UnicodePath = $false,
    [bool]$WatchDiagnostics = $false,
    [ValidateRange(1,3)][int]$ReplacementCycles = 1,
    [string]$PythonExecutable = 'python'
)
$ErrorActionPreference = 'Stop'
$taskRoot = $PSScriptRoot
$taskViewerRoot = [IO.Path]::GetFullPath((Join-Path $taskRoot $ViewerDirectory))
if (-not $taskViewerRoot.StartsWith($taskRoot + [IO.Path]::DirectorySeparatorChar)) { throw 'Viewer escaped task workspace' }
$taskCase = $Variant + '-' + $(if ($UnicodePath) { 'unicode' } else { 'ascii' }) + '-' + $RecreationDelayMs
if ($ReplacementCycles -gt 1) { $taskCase += '-cycles' + $ReplacementCycles }
$taskSuffix = if ($UnicodePath) { '-資料-é' } else { '' }
$taskFixture = Join-Path $taskRoot ('viewer-fixtures/synthetic-' + $taskCase + $taskSuffix + '.pdf')
$taskReplacement = Join-Path $taskRoot ('viewer-fixtures/replacement-' + $taskCase + '.pdf')
$taskPython = $PythonExecutable
& $taskPython (Join-Path $taskRoot 'fixture_pdf.py') $taskFixture 1
if ($LASTEXITCODE -ne 0) { throw 'Initial PDF fixture creation failed' }
& $taskPython (Join-Path $taskRoot 'fixture_pdf.py') $taskReplacement 2
if ($LASTEXITCODE -ne 0) { throw 'Replacement PDF fixture creation failed' }
$taskInitialBytes = [IO.File]::ReadAllBytes($taskFixture)
$taskReplacementBytes = [IO.File]::ReadAllBytes($taskReplacement)
function Read-TaskViewerLog([string]$taskPath) {
    $taskStream = [IO.File]::Open($taskPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    $taskReader = [IO.StreamReader]::new($taskStream)
    try { return $taskReader.ReadToEnd() } finally { $taskReader.Dispose() }
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class OkularReloadFixtureDelete {
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  [return: MarshalAs(UnmanagedType.Bool)]
  public static extern bool DeleteFileW(string path);
}
'@
$env:QT_QPA_PLATFORM = 'offscreen'
$env:QT_LOGGING_RULES = 'org.kde.okular.core.debug=true'
if ($WatchDiagnostics) {
    $env:QT_LOGGING_RULES += ';kf.coreaddons.kdirwatch.debug=true'
    $env:KDIRWATCH_VERBOSE = '1'
}
$env:QT_FORCE_STDERR_LOGGING = '1'
$env:QT_MESSAGE_PATTERN = '[%{time process} %{type} %{category}] %{message}'
$env:PATH = (Join-Path $taskViewerRoot 'bin') + ';' + $env:PATH
$taskStdout = Join-Path $taskRoot ('viewer-' + $taskCase + '-stdout.log')
$taskStderr = Join-Path $taskRoot ('viewer-' + $taskCase + '-stderr.log')
$taskProcess = Start-Process -FilePath (Join-Path $taskViewerRoot 'bin/okular.exe') -ArgumentList ('"' + $taskFixture + '"') -WindowStyle Hidden -PassThru -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr
$taskResult = $null
try {
    $taskTimer = [Diagnostics.Stopwatch]::StartNew()
    $taskInitialRendered = $false
    while ($taskTimer.ElapsedMilliseconds -lt 5000) {
        Start-Sleep -Milliseconds 200
        $taskProcess.Refresh()
        if ($taskProcess.HasExited) { throw ('Viewer exited before initial read: ' + $taskProcess.ExitCode) }
        $taskLog = Read-TaskViewerLog $taskStderr
        if ($taskLog -match 'sending request observer=.*@0 async') { $taskInitialRendered = $true; break }
    }
    if (-not $taskInitialRendered) { throw 'Initial PDF page0 did not reach rendering generator' }
    if ($taskLog -match 'sending request observer=.*@1 async') { throw 'Initial single-page fixture unexpectedly requested page1' }
    $taskLoadedPoppler = @($taskProcess.Modules | Where-Object { $_.ModuleName -eq 'poppler.dll' } | ForEach-Object { $_.FileName })
    if ($taskLoadedPoppler.Count -ne 1 -or [IO.Path]::GetFullPath($taskLoadedPoppler[0]) -ne [IO.Path]::GetFullPath((Join-Path $taskViewerRoot 'bin/poppler.dll'))) { throw 'Loaded Poppler module does not match the intended viewer copy' }
    $taskLoadedPopplerHash = (Get-FileHash -LiteralPath $taskLoadedPoppler[0] -Algorithm SHA256).Hash
    $taskLoadedKCore = @($taskProcess.Modules | Where-Object { $_.ModuleName -eq 'KF6CoreAddons.dll' } | ForEach-Object { $_.FileName })
    if ($taskLoadedKCore.Count -ne 1 -or [IO.Path]::GetFullPath($taskLoadedKCore[0]) -ne [IO.Path]::GetFullPath((Join-Path $taskViewerRoot 'bin/KF6CoreAddons.dll'))) { throw 'Loaded KCoreAddons module does not match the intended viewer copy' }
    $taskLoadedKCoreHash = (Get-FileHash -LiteralPath $taskLoadedKCore[0] -Algorithm SHA256).Hash
    $taskBaseReplacementBytes = $taskReplacementBytes
    $taskCurrentExpectedBytes = $taskInitialBytes
    $taskCycleResults = @()
    for ($taskCycle = 1; $taskCycle -le $ReplacementCycles; $taskCycle++) {
        if ($ReplacementCycles -gt 1) {
            # Color changes have equal byte length, preserving all original PDF offsets.
            # A trailing PDF comment gives each cycle a distinct length/reopen log marker.
            $taskReplacementText = [Text.Encoding]::Latin1.GetString($taskBaseReplacementBytes)
            if ($taskCycle % 2 -eq 0) { $taskReplacementText = $taskReplacementText.Replace('0 0 1 rg', '0 1 0 rg') }
            $taskReplacementText += "`n% ordinary refresh cycle " + ('x' * $taskCycle) + "`n"
            $taskReplacementBytes = [Text.Encoding]::Latin1.GetBytes($taskReplacementText)
        }
        $taskLog = Read-TaskViewerLog $taskStderr
        $taskInitialLogLength = $taskLog.Length
        $taskDeleteAtMs = $taskTimer.ElapsedMilliseconds
        $taskDeleted = [OkularReloadFixtureDelete]::DeleteFileW($taskFixture)
        $taskDeleteError = if ($taskDeleted) { 0 } else { [Runtime.InteropServices.Marshal]::GetLastWin32Error() }
        if ($RecreationDelayMs) { Start-Sleep -Milliseconds $RecreationDelayMs }
        $taskRecreated = $false
        $taskRecreateError = 0
        try {
            # CreateNew cannot overwrite a baseline fixture that remained locked.
            $taskWriter = [IO.File]::Open($taskFixture, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
            try { $taskWriter.Write($taskReplacementBytes, 0, $taskReplacementBytes.Length) } finally { $taskWriter.Dispose() }
            $taskRecreated = $true
        } catch [IO.IOException] { $taskRecreateError = $_.Exception.HResult -band 0xFFFF }
        $taskRecreateAtMs = $taskTimer.ElapsedMilliseconds
        $taskAutoLoadedSecondPage = $false
        $taskReplacementMetadataOpened = $false
        $taskObserveUntil = $taskTimer.ElapsedMilliseconds + 10000
        while ($taskTimer.ElapsedMilliseconds -lt $taskObserveUntil) {
            Start-Sleep -Milliseconds 200
            $taskProcess.Refresh()
            if ($taskProcess.HasExited) { throw ('Viewer exited during reload: ' + $taskProcess.ExitCode) }
            $taskLog = Read-TaskViewerLog $taskStderr
            $taskAfterLog = $taskLog.Substring($taskInitialLogLength)
            $taskMetadataMatch = [regex]::Match($taskAfterLog, ('Metadata file is now: .*[/\\]' + $taskReplacementBytes.Length + '\.'))
            if ($taskMetadataMatch.Success) {
                $taskReplacementMetadataOpened = $true
                $taskAfterReopen = $taskAfterLog.Substring($taskMetadataMatch.Index + $taskMetadataMatch.Length)
                if ($taskAfterReopen -match 'sending request observer=.*@1 async') { $taskAutoLoadedSecondPage = $true; break }
            }
            if (-not $ExpectDeletion -and $taskTimer.ElapsedMilliseconds -gt ($taskRecreateAtMs + 2000)) { break }
        }
        $taskDiskBytes = [IO.File]::ReadAllBytes($taskFixture)
        $taskExpectedBytes = if ($taskRecreated) { $taskReplacementBytes } else { $taskCurrentExpectedBytes }
        $taskDiskExpected = [Convert]::ToBase64String($taskDiskBytes) -eq [Convert]::ToBase64String($taskExpectedBytes)
        $taskCyclePass = if ($ExpectDeletion) { $taskDeleted -and $taskRecreated -and $taskReplacementMetadataOpened -and $taskAutoLoadedSecondPage -and $taskDiskExpected } else { (-not $taskDeleted) -and $taskDeleteError -eq 32 -and (-not $taskRecreated) -and (-not $taskAutoLoadedSecondPage) -and $taskDiskExpected }
        $taskCycleResults += [ordered]@{cycle=$taskCycle;deleted=$taskDeleted;delete_error=$taskDeleteError;delete_at_ms=$taskDeleteAtMs;recreated=$taskRecreated;recreate_error=$taskRecreateError;recreate_at_ms=$taskRecreateAtMs;replacement_pdf_bytes=$taskReplacementBytes.Length;replacement_metadata_reopened=$taskReplacementMetadataOpened;automatic_second_page_reached_rendering_generator=$taskAutoLoadedSecondPage;pathname_bytes_match_expected=$taskDiskExpected;observed_until_ms=$taskTimer.ElapsedMilliseconds;passed=$taskCyclePass}
        $taskCurrentExpectedBytes = $taskExpectedBytes
        if (-not $taskCyclePass) { break }
    }
    $taskPass = $taskCycleResults.Count -eq $ReplacementCycles -and @($taskCycleResults | Where-Object { -not $_.passed }).Count -eq 0
    $taskResult = [ordered]@{
        case=$taskCase; pid=$taskProcess.Id; qpa_platform=$env:QT_QPA_PLATFORM
        watch_debug_logging=$WatchDiagnostics
        expected_deletion=$ExpectDeletion; unicode_path=$UnicodePath; recreation_delay_ms=$RecreationDelayMs
        initial_page0_reached_rendering_generator=$taskInitialRendered
        deleted=$taskDeleted; delete_error=$taskDeleteError; delete_at_ms=$taskDeleteAtMs
        recreated=$taskRecreated; recreate_error=$taskRecreateError; recreate_at_ms=$taskRecreateAtMs
        automatic_second_page_reached_rendering_generator=$taskAutoLoadedSecondPage
        pathname_bytes_match_expected=$taskDiskExpected
        initial_pdf_bytes=$taskInitialBytes.Length; replacement_pdf_bytes=$taskReplacementBytes.Length
        observed_until_ms=$taskTimer.ElapsedMilliseconds; passed=$taskPass
        replacement_cycles_requested=$ReplacementCycles
        replacement_cycles=$taskCycleResults
        observation='Existing validated Okular core sending-request @1 after reopening each replacement with its distinct byte-length metadata marker. Initial PDF has one page; replacements have two. No manual reload, UI control or injected code; completed pixels are not asserted.'
        profile_limit='Qt Windows uses normal QStandardPaths for synthetic-fixture metadata; no private profile isolation claimed.'
        okular_sha256=(Get-FileHash -LiteralPath (Join-Path $taskViewerRoot 'bin/okular.exe') -Algorithm SHA256).Hash
        poppler_sha256=(Get-FileHash -LiteralPath (Join-Path $taskViewerRoot 'bin/poppler.dll') -Algorithm SHA256).Hash
        generator_sha256=(Get-FileHash -LiteralPath (Join-Path $taskViewerRoot 'bin/okular_generators/okularGenerator_poppler.dll') -Algorithm SHA256).Hash
        loaded_poppler_path=$taskLoadedPoppler[0]
        loaded_poppler_sha256=$taskLoadedPopplerHash
        loaded_kcoreaddons_path=$taskLoadedKCore[0]
        loaded_kcoreaddons_sha256=$taskLoadedKCoreHash
        log='viewer-' + $taskCase + '-stderr.log'
    }
    $taskResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $taskRoot ('viewer-' + $taskCase + '-result.json')) -Encoding utf8
    $taskResult | ConvertTo-Json -Depth 6
    if (-not $taskPass) { throw 'Viewer regression expected outcomes failed; see result and log' }
} finally {
    $taskProcess.Refresh()
    if (-not $taskProcess.HasExited) { Stop-Process -Id $taskProcess.Id }
    if (-not $taskProcess.WaitForExit(10000)) { throw 'Owned synthetic viewer did not finish exiting' }
}
