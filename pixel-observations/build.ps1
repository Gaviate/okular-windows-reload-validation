# SPDX-FileCopyrightText: 2026 Gaviate
# SPDX-License-Identifier: GPL-2.0-or-later
# Public path-parameter adapter. Run from an MSVC developer PowerShell.
param(
    [Parameter(Mandatory=$true)][string]$QtPrefix,
    [Parameter(Mandatory=$true)][string]$KCoreSource,
    [Parameter(Mandatory=$true)][string]$KCoreBuild,
    [string]$Cmake = 'cmake'
)
$ErrorActionPreference = 'Stop'
$taskQt = (Resolve-Path -LiteralPath $QtPrefix).Path
$taskKCoreSource = (Resolve-Path -LiteralPath $KCoreSource).Path
$taskKCoreBuild = (Resolve-Path -LiteralPath $KCoreBuild).Path
& $Cmake -S $PSScriptRoot -B (Join-Path $PSScriptRoot 'build') -G Ninja -DCMAKE_BUILD_TYPE=Release ('-DCMAKE_PREFIX_PATH=' + $taskQt) ('-DKCOREADDONS_SOURCE=' + $taskKCoreSource) ('-DKCOREADDONS_BUILD=' + $taskKCoreBuild)
if ($LASTEXITCODE -ne 0) { throw 'Pixel integration probe configure failed' }
& $Cmake --build (Join-Path $PSScriptRoot 'build') --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Pixel integration probe build failed' }
