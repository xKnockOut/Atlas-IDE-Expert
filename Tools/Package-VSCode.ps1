<#
.SYNOPSIS
    Baut die VS-Code-Erweiterung als .vsix mit mitgelieferter Server-EXE (#49).

.DESCRIPTION
    Kopiert BetterDelphiLSP.exe nach Editors/VSCode/server, installiert die
    npm-Abhängigkeiten und packt die Erweiterung mit vsce. Die .vsix liegt
    danach in Editors/VSCode und lässt sich mit
    "code --install-extension betterdelphilsp-<Version>.vsix" installieren.

.PARAMETER ServerExe
    Pfad zur gebauten EXE; Standard: Output/Win64/Release/Bin, sonst Debug.

.EXAMPLE
    pwsh Tools/Package-VSCode.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $ServerExe = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ServerExe -eq '') {
    foreach ($Config in 'Release', 'Debug') {
        $Candidate = Join-Path $Root "Output/Win64/$Config/Bin/BetterDelphiLSP.exe"
        if (Test-Path $Candidate) {
            $ServerExe = $Candidate
            break
        }
    }
}
if ($ServerExe -eq '' -or -not (Test-Path $ServerExe)) {
    Write-Error 'BetterDelphiLSP.exe nicht gefunden; Server bauen oder -ServerExe angeben.'
}

$Extension = Join-Path $Root 'Editors/VSCode'
$ServerDir = Join-Path $Extension 'server'
New-Item -ItemType Directory -Force -Path $ServerDir | Out-Null
Copy-Item -Force $ServerExe (Join-Path $ServerDir 'BetterDelphiLSP.exe')

Push-Location $Extension
try {
    npm ci --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    npx vsce package
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}
