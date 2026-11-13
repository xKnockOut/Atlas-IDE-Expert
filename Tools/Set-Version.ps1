<#
.SYNOPSIS
    Setzt die Version von Server und Claude-Code-Plugin (#83).

.DESCRIPTION
    Schreibt die Version in TAtlasVersion (Atlas.Text.Product.Version, gemeinsam für Server und IDE-Plugin),
    plugin.json und marketplace.json
    übernimmt die Changelog-Fragmente aus changelog.d/ (Update-Changelog.ps1),
    benennt den Abschnitt "## [Unveröffentlicht]" in CHANGELOG.md in
    "## [<Version>] - <Datum>" um, mit neuem leeren Abschnitt darüber, und
    erneuert die Spalte Units der Pakettabelle in README.md und README_DE.md
    (Zahl der Units im contains der .dpk, Stand <Major.Minor>). Pull Requests
    lassen diese Spalte unverändert.
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

# Eine Angabe für Server und IDE-Plugin; TProductVersion und
# TAtlasPluginVersion verweisen auf TAtlasVersion.
$Unit = Join-Path $Root 'Packages/Atlas.Text/Source/Product/Atlas.Text.Product.Version.pas'
$Text = [IO.File]::ReadAllText($Unit) -replace "(Version\s*=\s*')[^']+(')", "`${1}$Version`${2}"
[IO.File]::WriteAllText($Unit, $Text, $Utf8Bom)

# Claude-Code-Plugin und Marketplace-Eintrag (#101).
foreach ($Json in @('Editors/ClaudeCode/atlas/.claude-plugin/plugin.json', '.claude-plugin/marketplace.json')) {
    $Path = Join-Path $Root $Json
    $Text = [IO.File]::ReadAllText($Path) -replace '("version"\s*:\s*")[^"]+(")', "`${1}$Version`${2}"
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
}

& (Join-Path $PSScriptRoot 'Update-Changelog.ps1') -Root $Root
if ($LASTEXITCODE -ne 0) { Write-Error 'Changelog-Fragmente fehlerhaft (pwsh Tools/Update-Changelog.ps1 -Check)' }

$Changelog = Join-Path $Root 'CHANGELOG.md'
$Text = [IO.File]::ReadAllText($Changelog)
$Date = Get-Date -Format 'yyyy-MM-dd'
$Text = $Text -replace '(?m)^## \[Unveröffentlicht\]', "## [Unveröffentlicht]`n`n## [$Version] - $Date"
[IO.File]::WriteAllText($Changelog, $Text, $Utf8)

# Pakettabelle im README: Units je Package aus dem contains der .dpk.
$Units = @{}
foreach ($Dpk in Get-ChildItem -Path (Join-Path $Root 'Packages') -Filter 'Atlas.IDE.*.dpk' -Recurse -File) {
    $Contains = ([IO.File]::ReadAllText($Dpk.FullName) -split '(?m)^contains\s*$', 2)
    if ($Contains.Count -lt 2) { continue }
    $Units[$Dpk.BaseName] = [regex]::Matches($Contains[1], "(?m)^\s+[\w.]+\s+in\s+'").Count
}
$Short = ($Version -replace '^(\d+\.\d+).*$', '$1')
foreach ($Readme in @('README.md', 'README_DE.md')) {
    $Path = Join-Path $Root $Readme
    $Text = [IO.File]::ReadAllText($Path)
    foreach ($Name in $Units.Keys) {
        $Pattern = '(?m)^(\| `' + [regex]::Escape($Name) + '` \|.*\| )\d+( \| [^|]+ \|\r?)$'
        $Count = $Units[$Name]
        $Text = [regex]::Replace($Text, $Pattern, { param($Match) $Match.Groups[1].Value + $Count + $Match.Groups[2].Value })
    }
    $Text = $Text -replace '\(as of \d+\.\d+\)', "(as of $Short)" -replace '\(Stand \d+\.\d+\)', "(Stand $Short)"
    [IO.File]::WriteAllText($Path, $Text, $Utf8)
}

& (Join-Path $PSScriptRoot 'Check-Version.ps1') -Root $Root -Expected $Version
