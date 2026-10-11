<#
.SYNOPSIS
    Prüft, dass Server und VS-Code-Erweiterung dieselbe SemVer-Version tragen (#83).

.DESCRIPTION
    Quellen: TProductVersion.Version in Atlas.Common.Product.Version.pas und
    "version" in Editors/VSCode/package.json. Mit -Expected (z. B. aus dem
    Release-Tag) muss auch diese übereinstimmen. CHANGELOG.md braucht einen
    Abschnitt "## [<Version>]".

    Exit-Code 0: in Ordnung, 1: Abweichung.

.EXAMPLE
    pwsh Tools/Check-Version.ps1 -Expected 0.2.0
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $Expected = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SemVer = '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$'
$Unit = Join-Path $Root 'Packages/Atlas.Common/Source/Product/Atlas.Common.Product.Version.pas'
$Server = [regex]::Match((Get-Content -Raw $Unit), "Version\s*=\s*'([^']+)'").Groups[1].Value
$Extension = (Get-Content -Raw (Join-Path $Root 'Editors/VSCode/package.json') | ConvertFrom-Json).version
$Changelog = Get-Content -Raw (Join-Path $Root 'CHANGELOG.md')
$Plugin = (Get-Content -Raw (Join-Path $Root 'Editors/ClaudeCode/atlas/.claude-plugin/plugin.json') | ConvertFrom-Json).version
$Marketplace = (Get-Content -Raw (Join-Path $Root '.claude-plugin/marketplace.json') | ConvertFrom-Json).plugins[0].version

$Errors = @()
if ($Server -notmatch $SemVer) { $Errors += "Server-Version '$Server' ist keine SemVer-Version" }
if ($Server -ne $Extension) { $Errors += "Server $Server und Erweiterung $Extension weichen ab" }
if ($Server -ne $Plugin) { $Errors += "Server $Server und Claude-Code-Plugin $Plugin weichen ab" }
if ($Server -ne $Marketplace) { $Errors += "Server $Server und Marketplace-Eintrag $Marketplace weichen ab" }
if ($Expected -ne '' -and $Expected -ne $Server) { $Errors += "Erwartet $Expected, Server hat $Server" }
if ($Changelog -notmatch "(?m)^## \[$([regex]::Escape($Server))\]") { $Errors += "CHANGELOG.md hat keinen Abschnitt [$Server]" }

if ($Errors.Count -gt 0) {
    $Errors | ForEach-Object { Write-Host "Fehler: $_" }
    exit 1
}
Write-Host "Version $Server in Ordnung."
