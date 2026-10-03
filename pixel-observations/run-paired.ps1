# SPDX-FileCopyrightText: 2026 Gaviate
# SPDX-License-Identifier: GPL-2.0-or-later
# Public explicit-path adapter. Only use a disposable owned viewer runtime COPY.
param(
    [Parameter(Mandatory=$true)][string]$OwnedRuntimeDirectory,
    [Parameter(Mandatory=$true)][string]$BaselinePoppler,
    [Parameter(Mandatory=$true)][string]$BaselineKCoreAddons,
    [Parameter(Mandatory=$true)][string]$CandidatePoppler,
    [Parameter(Mandatory=$true)][string]$CandidateKCoreAddons,
    [Parameter(Mandatory=$true)][string]$Executable,
    [Parameter(Mandatory=$true)][string]$OutputDirectory,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'
$taskRuntime = (Resolve-Path -LiteralPath $OwnedRuntimeDirectory).Path
$taskBaselinePoppler = (Resolve-Path -LiteralPath $BaselinePoppler).Path
$taskBaselineKCore = (Resolve-Path -LiteralPath $BaselineKCoreAddons).Path
$taskCandidatePoppler = (Resolve-Path -LiteralPath $CandidatePoppler).Path
$taskCandidateKCore = (Resolve-Path -LiteralPath $CandidateKCoreAddons).Path
$taskExecutable = (Resolve-Path -LiteralPath $Executable).Path
$taskOutput = [IO.Path]::GetFullPath($OutputDirectory)
$null = New-Item -ItemType Directory -Path $taskOutput -Force
$taskFixtureGenerator = Join-Path (Split-Path -Parent $PSScriptRoot) 'harness/fixture_pdf.py'
$env:PATH = $taskRuntime + ';' + $env:PATH
$env:QT_QPA_PLATFORM = 'offscreen'
$env:QT_PLUGIN_PATH = $taskRuntime
$env:QT_QPA_PLATFORM_PLUGIN_PATH = Join-Path $taskRuntime 'platforms'
$env:QT_LOGGING_RULES = 'org.kde.okular.core.debug=true'
$env:QT_FORCE_STDERR_LOGGING = '1'
$taskCases = @()
try {
    foreach ($taskVariant in @('baseline', 'candidate')) {
        $taskPopplerSource = if ($taskVariant -eq 'baseline') { $taskBaselinePoppler } else { $taskCandidatePoppler }
        $taskKCoreSource = if ($taskVariant -eq 'baseline') { $taskBaselineKCore } else { $taskCandidateKCore }
        Copy-Item -LiteralPath $taskPopplerSource -Destination (Join-Path $taskRuntime 'poppler.dll') -Force
        Copy-Item -LiteralPath $taskKCoreSource -Destination (Join-Path $taskRuntime 'KF6CoreAddons.dll') -Force
        foreach ($taskUnicode in @($false, $true)) {
            foreach ($taskDelay in @(0, 2000)) {
                $taskCase = $taskVariant + '-' + $(if ($taskUnicode) { 'unicode' } else { 'ascii' }) + '-' + $taskDelay
                $taskStem = Join-Path $taskOutput $taskCase
                $taskFixture = Join-Path $taskOutput ('fixture-' + $taskCase + $(if ($taskUnicode) { '-資料-é' } else { '' }) + '.pdf')
                $taskReplacement = Join-Path $taskOutput ('replacement-' + $taskCase + '.pdf')
                & $Python $taskFixtureGenerator $taskFixture 1
                if ($LASTEXITCODE -ne 0) { throw 'Initial fixture generation failed' }
                & $Python $taskFixtureGenerator $taskReplacement 2
                if ($LASTEXITCODE -ne 0) { throw 'Replacement fixture generation failed' }
                $taskText = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($taskReplacement))
                $taskIndex = $taskText.LastIndexOf('0 0 1 rg')
                if ($taskIndex -lt 0) { throw 'Replacement page2 fixture color missing' }
                $taskText = $taskText.Remove($taskIndex, 8).Insert($taskIndex, '0 1 0 rg')
                [IO.File]::WriteAllBytes($taskReplacement, [Text.Encoding]::Latin1.GetBytes($taskText))
                $taskArguments = @($taskRuntime, $taskFixture, $taskReplacement, $taskStem, $(if ($taskVariant -eq 'candidate') { 'true' } else { 'false' }), [string]$taskDelay)
                $taskQuotedArguments = @($taskArguments | ForEach-Object { '"' + $_ + '"' })
                $taskProcess = Start-Process -FilePath $taskExecutable -ArgumentList $taskQuotedArguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($taskStem + '-stdout.log') -RedirectStandardError ($taskStem + '-stderr.log')
                try {
                    if (-not $taskProcess.WaitForExit(45000)) { throw 'Owned pixel test exceeded bounded case timeout' }
                    $taskProcess.Refresh()
                    if ($taskProcess.ExitCode -ne 0) { throw ('Pixel test failed: ' + $taskCase + ' exit ' + $taskProcess.ExitCode) }
                } finally {
                    $taskProcess.Refresh()
                    if (-not $taskProcess.HasExited) { Stop-Process -Id $taskProcess.Id; $null = $taskProcess.WaitForExit(10000) }
                }
                $taskResult = Get-Content -LiteralPath ($taskStem + '-result.json') -Raw | ConvertFrom-Json
                if (-not $taskResult.passed) { throw ('Pixel result false: ' + $taskCase) }
                $taskPngs = @(Get-ChildItem -LiteralPath $taskOutput -File -Filter ($taskCase + '-*.png') | Get-FileHash -Algorithm SHA256 | ForEach-Object { @{file=[IO.Path]::GetFileName($_.Path);sha256=$_.Hash} })
                $taskExpectedPngs = if ($taskVariant -eq 'candidate') { 3 } else { 2 }
                if ($taskPngs.Count -ne $taskExpectedPngs) { throw 'Actual viewport PNG count mismatch' }
                $taskCases += [ordered]@{case=$taskCase;unicode_path=$taskUnicode;exit_code=$taskProcess.ExitCode;result_file=$taskCase+'-result.json';result_sha256=(Get-FileHash -LiteralPath ($taskStem+'-result.json') -Algorithm SHA256).Hash;viewport_pngs=$taskPngs;passed=$taskResult.passed}
                Write-Output ($taskCase + ': PASS actual viewer component pixels/control')
            }
        }
    }
    [ordered]@{created_at_utc=[DateTime]::UtcNow.ToString('o');case_count=$taskCases.Count;cases=$taskCases;probe_source_sha256=(Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'main.cpp') -Algorithm SHA256).Hash;probe_executable_sha256=(Get-FileHash -LiteralPath $taskExecutable -Algorithm SHA256).Hash;scope='Four matched negative controls and four candidate first-replacement cases. Offscreen Part/PageView fixture-colored regions, automatic page1 refresh then intentional page2 navigation. Whole-page final completion and desktop output are not asserted.'} | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $taskOutput 'paired-results.json') -Encoding utf8
} finally {
    Copy-Item -LiteralPath $taskCandidatePoppler -Destination (Join-Path $taskRuntime 'poppler.dll') -Force
    Copy-Item -LiteralPath $taskCandidateKCore -Destination (Join-Path $taskRuntime 'KF6CoreAddons.dll') -Force
}
