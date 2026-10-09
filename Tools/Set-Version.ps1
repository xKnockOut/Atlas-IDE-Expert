<#
.SYNOPSIS
    Setzt die Version von Server und VS-Code-Erweiterung (#83).

.DESCRIPTION
    Schreibt die Version in TProductVersion und package.json/package-lock.json
    und benennt den Abschnitt "## [Unveröffentlicht]" in CHANGELOG.md in
    "## [<Version>] - <Datum>" um, mit neuem leeren Abschnitt darüber.
    Danach committen und das Tag v<Version> pushen; den Rest erledigt
    .github/workflows/release.yml.

.EXAMPLE
    pwsh Tools/Set-Version.ps1 -Version 0.2.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Version,
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Version -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$') {
    Write-Error "'$Version' ist keine SemVer-Version"
}
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$Unit = Join-Path $Root 'Packages/Argus.Common/Source/Product/Argus.Common.Product.Version.pas'
$Text = [IO.File]::ReadAllText($Unit) -replace "(Version\s*=\s*')[^']+(')", "`${1}$Version`${2}"
[IO.File]::WriteAllText($Unit, $Text, $Utf8Bom)

Push-Location (Join-Path $Root 'Editors/VSCode')
try {
    npm version $Version --no-git-tag-version --allow-same-version | Out-Null
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}
finally {
    Pop-Location
}

$Changelog = Join-Path $Root 'CHANGELOG.md'
$Text = [IO.File]::ReadAllText($Changelog)
$Date = Get-Date -Format 'yyyy-MM-dd'
$Text = $Text -replace '(?m)^## \[Unveröffentlicht\]', "## [Unveröffentlicht]`n`n## [$Version] - $Date"
[IO.File]::WriteAllText($Changelog, $Text, $Utf8)

& (Join-Path $PSScriptRoot 'Check-Version.ps1') -Root $Root -Expected $Version
