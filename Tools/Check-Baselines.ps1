<#
.SYNOPSIS
    Prüft die Baselines der Selbstprüfung: keine toten Einträge, und sie wachsen nicht (Code-Review A-101).

.DESCRIPTION
    Für jede eingecheckte atlas-baseline.json unter Packages/:
    1. Jeder Eintrag zeigt auf eine vorhandene Datei (Pfad relativ zum Ordner der
       Baseline). Eine verschobene oder gelöschte Datei hinterlässt sonst Ballast,
       und ihre Treffer erscheinen am neuen Ort unbemerkt als neu.
    2. Die Zahl der Einträge je Regel, summiert über alle Packages, steigt gegenüber
       -BaseRef nicht. Neue Treffer gehören behoben, nicht in die Baseline. Summiert
       wird, damit eine Unit samt ihren Einträgen in ein anderes Package umziehen
       kann. Nicht mitgezählt wird ein Package, dessen atlas.json sich gegenüber
       -BaseRef geändert hat oder dort fehlt (anderes Profil, andere Regeln): Dann ist
       seine Baseline neu gemessen, und die Änderung steht im Diff.

    Fehlt -BaseRef im Repository (flacher Klon), bricht das Skript mit einer Meldung
    ab; in CI vorher den Zielbranch holen.

    Exit-Code 0: alles in Ordnung, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-Baselines.ps1 -BaseRef origin/main-merging
#>
[CmdletBinding()]
param(
    [string] $BaseRef = 'origin/main',
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RuleCounts($Json) {
    $mCounts = @{}
    foreach ($mEntry in @($Json.findings)) {
        $mCount = 1
        if ($mEntry.PSObject.Properties['count']) { $mCount = [int]$mEntry.count }
        $mCounts[$mEntry.rule] = [int]$mCounts[$mEntry.rule] + $mCount
    }
    return $mCounts
}

function Get-BaseText([string] $RelativePath) {
    $mText = & git -C $Root show "${BaseRef}:$RelativePath" 2>$null
    if ($LASTEXITCODE -ne 0) { return $null }
    return ($mText -join "`n")
}

& git -C $Root rev-parse --verify --quiet "$BaseRef^{commit}" *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Host "::error::Vergleichsstand '$BaseRef' fehlt (git fetch origin <Branch>)."
    exit 1
}

$Problems = [System.Collections.Generic.List[string]]::new()
$Before = @{}
$After = @{}
$Baselines = @(@(& git -C $Root ls-files -- 'Packages/*atlas-baseline.json') +
    @(& git -C $Root ls-tree -r --name-only $BaseRef -- Packages | Where-Object { $_ -like '*atlas-baseline.json' }) |
    Sort-Object -Unique)
foreach ($mRelative in $Baselines) {
    $mFile = Join-Path $Root $mRelative
    $mJson = $null
    if (Test-Path -LiteralPath $mFile) {
        $mJson = Get-Content -LiteralPath $mFile -Raw -Encoding utf8 | ConvertFrom-Json
        $mFolder = Split-Path -Parent $mFile
        $mDead = @{}
        foreach ($mEntry in @($mJson.findings)) {
            if (-not (Test-Path -LiteralPath (Join-Path $mFolder $mEntry.path))) { $mDead[$mEntry.path] = [int]$mDead[$mEntry.path] + 1 }
        }
        foreach ($mPath in ($mDead.Keys | Sort-Object)) {
            $Problems.Add("${mRelative}: $($mDead[$mPath]) Einträge für fehlende Datei $mPath")
        }
    }

    $mConfig = (Split-Path -Parent $mRelative).Replace('\', '/') + '/atlas.json'
    $mConfigPath = Join-Path $Root $mConfig
    $mConfigBase = Get-BaseText $mConfig
    if ($null -eq $mConfigBase -or -not (Test-Path -LiteralPath $mConfigPath)) { continue }
    $mConfigNow = (Get-Content -LiteralPath $mConfigPath -Raw -Encoding utf8) -replace "`r`n", "`n"
    if ($mConfigBase.TrimEnd() -cne $mConfigNow.TrimEnd()) { continue }

    $mBaseText = Get-BaseText $mRelative
    if ($null -ne $mBaseText) {
        $mCounts = Get-RuleCounts ($mBaseText | ConvertFrom-Json)
        foreach ($mRule in $mCounts.Keys) { $Before[$mRule] = [int]$Before[$mRule] + $mCounts[$mRule] }
    }
    if ($null -ne $mJson) {
        $mCounts = Get-RuleCounts $mJson
        foreach ($mRule in $mCounts.Keys) { $After[$mRule] = [int]$After[$mRule] + $mCounts[$mRule] }
    }
}
foreach ($mRule in ($After.Keys | Sort-Object)) {
    if ($After[$mRule] -gt [int]$Before[$mRule]) {
        $Problems.Add("Regel $mRule wächst in den Baselines von $([int]$Before[$mRule]) auf $($After[$mRule]); neue Treffer beheben statt in die Baseline aufnehmen")
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "::error::$_" }
    exit 1
}
Write-Host "$($Baselines.Count) Baselines geprüft: keine toten Einträge, keine Regel wächst gegenüber $BaseRef."
exit 0
