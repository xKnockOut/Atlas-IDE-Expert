<#
.SYNOPSIS
    Prüft die Baselines der Selbstprüfung: keine toten Einträge, und sie wachsen nicht.

.DESCRIPTION
    Für jede eingecheckte atlas-baseline.json unter Packages/ und im Wurzelordner (dort nur
    die Metrikregeln für Atlas.Common, Atlas.Windows, Application und Tests):
    1. Jeder Eintrag zeigt auf eine vorhandene Datei (Pfad relativ zum Ordner der
       Baseline). Eine verschobene oder gelöschte Datei hinterlässt sonst Ballast,
       und ihre Treffer erscheinen am neuen Ort unbemerkt als neu.
    2. Die Zahl der Einträge je Regel, summiert über alle Packages, steigt gegenüber
       -BaseRef nicht. Neue Treffer gehören behoben, nicht in die Baseline. Summiert
       wird, damit eine Unit samt ihren Einträgen in ein anderes Package umziehen
       kann. Nicht mitgezählt wird ein Package, dessen atlas.json sich gegenüber
       -BaseRef geändert hat oder dort fehlt (anderes Profil, andere Regeln): Dann ist
       seine Baseline neu gemessen, und die Änderung steht im Diff.
    3. Die Baseline wortgleicher Rümpfe (atlas-duplicates.json im Wurzelordner) wächst
       gegenüber -BaseRef nicht, solange minLines gleich bleibt: weder in der Summe der
       Fassungen noch in einer einzelnen Gruppe. Je Gruppe gilt als Befund:
       - eine Gruppe, die -BaseRef nicht kennt (weder ihren Fingerabdruck noch eine ihrer
         Fassungen), also eine neue Kopie;
       - eine Gruppe mit mehr Fassungen als ihre Gruppe unter -BaseRef.
       Wiedererkannt wird eine Gruppe am Fingerabdruck, sonst an einer gemeinsamen Fassung
       (Datei:Routine); so zählt ein Rumpf, der in beiden Kopien gleich geändert wurde, nicht
       als neu. Ohne den Vergleich je Gruppe kämen neue Kopien durch, sobald im selben Stand
       mehr alte entfernt werden.
       Neue Kopien gehören in eine gemeinsame Routine, nicht in die Baseline. Gibt es einen
       Grund, sie zu behalten, steht er im Pull Request in einer Zeile „Neue Kopien: …“; die
       CI reicht den Text als -DuplicatesReason weiter, und die Befunde je Gruppe werden zu
       Warnungen. Die Summe bleibt auch dann eine Grenze.

    Fehlt -BaseRef im Repository (flacher Klon), bricht das Skript mit einer Meldung
    ab; in CI vorher den Zielbranch holen.

    Exit-Code 0: alles in Ordnung, 1: mindestens ein Verstoß.

.PARAMETER DuplicatesReason
    Begründung für neue oder gewachsene Gruppen in atlas-duplicates.json (Text nach
    „Neue Kopien:“ im Pull Request). Leer: Diese Befunde sind Fehler.

.PARAMETER SelfTest
    Prüft nur den Vergleich je Gruppe an festen Beispielen.

.EXAMPLE
    pwsh Tools/Check-Baselines.ps1 -BaseRef origin/main-merging
#>
[CmdletBinding()]
param(
    [string] $BaseRef = 'origin/main',
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $DuplicatesReason = '',
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DuplicateGroupText($Group) {
    $mMembers = @($Group.members)
    $mFirst = ''
    if ($mMembers.Count -gt 0) { $mFirst = ($mMembers[0] -split ':')[-1] }
    return "$mFirst ($($mMembers.Count) Fassungen, $([int]$Group.lines) Zeilen, $($Group.hash))"
}

# Vergleicht die Gruppen zweier Stände von atlas-duplicates.json und liefert je neue oder
# gewachsene Gruppe eine Zeile. Wiedererkannt wird eine Gruppe am Fingerabdruck, sonst an einer
# Fassung, die sie mit einer Gruppe des alten Stands teilt (Rumpf in beiden Kopien gleich geändert).
function Compare-DuplicateGroups($Base, $Now) {
    $mByHash = @{}
    $mByMember = @{}
    foreach ($mGroup in @($Base.groups)) {
        $mCount = @($mGroup.members).Count
        $mByHash[[string]$mGroup.hash] = $mCount
        foreach ($mMember in @($mGroup.members)) {
            $mByMember[[string]$mMember] = [Math]::Max([int]$mByMember[[string]$mMember], $mCount)
        }
    }
    $mFindings = [System.Collections.Generic.List[string]]::new()
    foreach ($mGroup in @($Now.groups)) {
        $mCount = @($mGroup.members).Count
        $mKnown = -1
        if ($mByHash.ContainsKey([string]$mGroup.hash)) { $mKnown = [int]$mByHash[[string]$mGroup.hash] }
        foreach ($mMember in @($mGroup.members)) {
            if ($mByMember.ContainsKey([string]$mMember)) { $mKnown = [Math]::Max($mKnown, [int]$mByMember[[string]$mMember]) }
        }
        if ($mKnown -lt 0) {
            $mFindings.Add("neue Gruppe $(Get-DuplicateGroupText $mGroup): $(@($mGroup.members) -join ', ')")
        } elseif ($mCount -gt $mKnown) {
            $mFindings.Add("Gruppe $(Get-DuplicateGroupText $mGroup) hatte $mKnown Fassungen")
        }
    }
    return , $mFindings
}

function Invoke-SelfTest {
    $mBase = [pscustomobject]@{ minLines = 6; groups = @(
            [pscustomobject]@{ hash = 'a1'; lines = 6; members = @('A.pas:TA.Show', 'B.pas:TB.Show') },
            [pscustomobject]@{ hash = 'b2'; lines = 8; members = @('C.pas:Eins', 'D.pas:Eins', 'E.pas:Eins') }) }
    $mCases = @(
        @{ Name = 'unverändert'; Groups = $mBase.groups; Expected = 0 },
        @{ Name = 'Gruppe entfernt'; Groups = @($mBase.groups[0]); Expected = 0 },
        @{ Name = 'Datei umbenannt, gleicher Fingerabdruck'
            Groups = @([pscustomobject]@{ hash = 'a1'; lines = 6; members = @('A2.pas:TA.Show', 'B.pas:TB.Show') }); Expected = 0 },
        @{ Name = 'Rumpf in beiden Kopien gleich geändert'
            Groups = @([pscustomobject]@{ hash = 'c3'; lines = 7; members = @('A.pas:TA.Show', 'B.pas:TB.Show') }); Expected = 0 },
        @{ Name = 'Gruppe wächst'
            Groups = @([pscustomobject]@{ hash = 'a1'; lines = 6; members = @('A.pas:TA.Show', 'B.pas:TB.Show', 'F.pas:TF.Show') }); Expected = 1 },
        @{ Name = 'neue Gruppe, Summe sinkt'
            Groups = @([pscustomobject]@{ hash = 'd4'; lines = 9; members = @('G.pas:Neu', 'H.pas:Neu') }); Expected = 1 })
    $mFailed = 0
    foreach ($mCase in $mCases) {
        $mNow = [pscustomobject]@{ minLines = 6; groups = @($mCase.Groups) }
        $mFound = (Compare-DuplicateGroups $mBase $mNow).Count
        if ($mFound -ne $mCase.Expected) {
            Write-Host "::error::Selbsttest '$($mCase.Name)': $mFound Befunde statt $($mCase.Expected)"
            $mFailed++
        }
    }
    if ($mFailed -gt 0) { exit 1 }
    Write-Host "Selbsttest: $($mCases.Count) Fälle zum Vergleich je Gruppe bestanden."
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

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
$Baselines = @(@(& git -C $Root ls-files -- 'Packages/*atlas-baseline.json' 'atlas-baseline.json') +
    @(& git -C $Root ls-tree -r --name-only $BaseRef -- Packages | Where-Object { $_ -like '*atlas-baseline.json' }) +
    @(& git -C $Root ls-tree --name-only $BaseRef -- 'atlas-baseline.json') |
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

    $mConfig = 'atlas.json'
    $mParent = (Split-Path -Parent $mRelative).Replace('\', '/')
    if ($mParent) { $mConfig = "$mParent/atlas.json" }
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
$DuplicatesName = 'atlas-duplicates.json'
$DuplicatesFile = Join-Path $Root $DuplicatesName
$DuplicatesBase = Get-BaseText $DuplicatesName
if ((Test-Path -LiteralPath $DuplicatesFile) -and $null -ne $DuplicatesBase) {
    $mNow = Get-Content -LiteralPath $DuplicatesFile -Raw -Encoding utf8 | ConvertFrom-Json
    $mBase = $DuplicatesBase | ConvertFrom-Json
    $mCountNow = (@($mNow.groups) | ForEach-Object { @($_.members).Count } | Measure-Object -Sum).Sum
    $mCountBase = (@($mBase.groups) | ForEach-Object { @($_.members).Count } | Measure-Object -Sum).Sum
    if ([int]$mNow.minLines -eq [int]$mBase.minLines) {
        if ([int]$mCountNow -gt [int]$mCountBase) {
            $Problems.Add("$DuplicatesName wächst von $([int]$mCountBase) auf $([int]$mCountNow) Fassungen; Kopien zusammenlegen statt in die Baseline aufnehmen")
        }
        foreach ($mFinding in (Compare-DuplicateGroups $mBase $mNow)) {
            if ($DuplicatesReason.Trim()) {
                Write-Host "::warning::${DuplicatesName}: $mFinding (begründet: $($DuplicatesReason.Trim()))"
            } else {
                $Problems.Add("${DuplicatesName}: $mFinding; Kopien zusammenlegen oder im Pull Request mit 'Neue Kopien: …' begründen")
            }
        }
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
Write-Host "$($Baselines.Count) Baselines geprüft: keine toten Einträge, keine Regel und keine Kopie wächst gegenüber $BaseRef."
exit 0
