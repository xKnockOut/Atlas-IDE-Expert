<#
.SYNOPSIS
    Erzeugt vor einem Kandidaten eine Liste zum Abhaken: jede neue oder geänderte Funktion einmal aufrufen.

.DESCRIPTION
    Ein Kandidat findet nur, was jemand aufruft (docs/Release.md, Abschnitt „Kandidaten“). Quelle ist
    CHANGELOG.md samt den Fragmenten in changelog.d/ (Update-Changelog.ps1 -Preview): alle Einträge unter
    „Neu“, „Experimentell“ und „Geändert“ von „## [Unveröffentlicht]“ abwärts bis zur Version -Since
    (ohne sie). Vorgabe für -Since ist die jüngste stabile Version im Changelog; so stehen vor rc.2 auch
    die Einträge von rc.1 auf der Liste, denn die stabile Version enthält beide.

    Je Eintrag eine Zeile mit Kästchen: Titel (Text vor dem ersten Doppelpunkt) und, wo vorhanden,
    Befehl, Einstellung und Tastenkürzel aus der Markierung <!-- whatsnew … --> (Felder command,
    setting, key; siehe Update-WhatsNew.ps1). Einstellungen in `…` stehen schon im Titel.

.PARAMETER Since
    Version, deren Einträge schon geprüft sind (z. B. 2.3.0-rc.1 für nur das Neue seit rc.1).

.PARAMETER IncludeFixes
    Auch die Einträge unter „Behoben“ aufnehmen.

.PARAMETER SelfTest
    Prüft das Auslesen an einem festen Beispiel.

.EXAMPLE
    pwsh Tools/New-CandidateChecklist.ps1
    pwsh Tools/New-CandidateChecklist.ps1 -Since 2.3.0-rc.1 -OutFile Output/rc2-abhaken.md
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $OutFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Output/Kandidat-Abhaken.md'),
    [string] $Since = '',
    [switch] $IncludeFixes,
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$cMarker = '<!--\s*whatsnew\b(.*?)-->'
$cMarkerFields = [ordered]@{ command = 'Befehl'; setting = 'Einstellung'; key = 'Tastenkürzel' }

# Felder der whatsnew-Markierung, die für das Aufrufen zählen (Befehl, Einstellung, Taste).
function Get-MarkerHints([string] $Line) {
    $mHints = [System.Collections.Generic.List[string]]::new()
    $mMarker = [regex]::Match($Line, $cMarker)
    if (-not $mMarker.Success) { return , $mHints }
    foreach ($mField in [regex]::Matches($mMarker.Groups[1].Value, '(\w+)=(?:"([^"]*)"|(\S+))')) {
        $mName = $mField.Groups[1].Value
        if (-not $cMarkerFields.Contains($mName)) { continue }
        $mValue = $mField.Groups[3].Value
        if ($mField.Groups[2].Success) { $mValue = $mField.Groups[2].Value }
        $mHints.Add("$($cMarkerFields[$mName]) ``$mValue``")
    }
    return , $mHints
}

# Eine Zeile der Liste aus einem Eintrag „- Titel (#123, `einstellung`): Text <!-- whatsnew … -->“.
function ConvertTo-ChecklistLine([string] $Entry, [string] $Version) {
    $mHints = Get-MarkerHints $Entry
    $mText = ([regex]::Replace($Entry, $cMarker, '') -replace '^\s*-\s+', '').Trim()
    $mHead = $mText
    $mColon = $mText.IndexOf(': ')
    if ($mColon -gt 0) { $mHead = $mText.Substring(0, $mColon) }
    if ($mHead.Length -gt 160) { $mHead = $mHead.Substring(0, 157).TrimEnd() + '…' }
    $mLine = "- [ ] $mHead"
    if ($mHints.Count -gt 0) { $mLine += ' · ' + ($mHints -join ' · ') }
    if ($Version -ne 'Unveröffentlicht') { $mLine += " · seit $Version" }
    return $mLine
}

# Liest die Einträge je Überschrift von oben bis vor die Version ASince (leer: erste stabile Version).
function Get-ChecklistEntries([string[]] $Lines, [string] $ASince, [string[]] $Headings) {
    $mResult = [ordered]@{}
    foreach ($mHeading in $Headings) { $mResult[$mHeading] = [System.Collections.Generic.List[string]]::new() }
    $mVersion = ''
    $mHeading = ''
    foreach ($mLine in $Lines) {
        if ($mLine -match '^## \[([^\]]+)\]') {
            $mName = $Matches[1]
            if ($ASince -and $mName -eq $ASince) { break }
            if (-not $ASince -and $mName -match '^\d+\.\d+\.\d+$') { break }
            $mVersion = $mName
            $mHeading = ''
            continue
        }
        if ($mLine -match '^###\s+(.*?)\s*$') { $mHeading = $Matches[1]; continue }
        if (-not $mVersion -or -not $mResult.Contains($mHeading) -or $mLine -notmatch '^-\s') { continue }
        $mResult[$mHeading].Add((ConvertTo-ChecklistLine $mLine $mVersion))
    }
    return $mResult
}

function Invoke-SelfTest {
    $mLines = @(
        '# Changelog', '', '## [Unveröffentlicht]', '', '### Neu',
        '- Bedingungen vorausschauen (#2169, `debug.predictConditions`, Vorgabe an): Text. <!-- whatsnew command=Atlas.Predict titleEn=x textEn=y -->',
        '  Folgezeile', '### Behoben', '- Absturz behoben (#1): Text.', '',
        '## [2.3.0-rc.1] - 2026-11-20', '### Geändert', '- Fenster heißt anders: Text.',
        '## [2.2.0] - 2026-11-18', '### Neu', '- Alt: schon geprüft.')
    $mCases = @(
        @{ Name = 'Vorgabe bis zur stabilen Version'; Since = ''; Fixes = $false; Count = 2 },
        @{ Name = 'mit Korrekturen'; Since = ''; Fixes = $true; Count = 3 },
        @{ Name = 'nur seit rc.1'; Since = '2.3.0-rc.1'; Fixes = $false; Count = 1 })
    $mFailed = 0
    foreach ($mCase in $mCases) {
        $mHeadings = @('Neu', 'Experimentell', 'Geändert')
        if ($mCase.Fixes) { $mHeadings += 'Behoben' }
        $mFound = Get-ChecklistEntries $mLines $mCase.Since $mHeadings
        $mCount = ($mFound.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        if ($mCount -ne $mCase.Count) {
            Write-Host "::error::Selbsttest '$($mCase.Name)': $mCount Einträge statt $($mCase.Count)"
            $mFailed++
        }
    }
    $mExpected = '- [ ] Bedingungen vorausschauen (#2169, `debug.predictConditions`, Vorgabe an) · Befehl `Atlas.Predict`'
    $mLine = (Get-ChecklistEntries $mLines '' @('Neu'))['Neu'][0]
    if ($mLine -cne $mExpected) {
        Write-Host "::error::Selbsttest Zeile: '$mLine' statt '$mExpected'"
        $mFailed++
    }
    if ($mFailed -gt 0) { exit 1 }
    Write-Host "Selbsttest: $($mCases.Count + 1) Fälle zur Liste vor dem Kandidaten bestanden."
    exit 0
}

if ($SelfTest) { Invoke-SelfTest }

$Text = & (Join-Path $PSScriptRoot 'Update-Changelog.ps1') -Root $Root -Preview | Out-String
if ($LASTEXITCODE -ne 0) { throw 'Changelog-Fragmente fehlerhaft: pwsh Tools/Update-Changelog.ps1 -Check' }
$Headings = @('Neu', 'Experimentell', 'Geändert')
if ($IncludeFixes) { $Headings += 'Behoben' }
$Entries = Get-ChecklistEntries ($Text -split '\r?\n') $Since $Headings

$SinceText = $Since
if (-not $SinceText) { $SinceText = 'der letzten stabilen Version' }
$Out = [System.Collections.Generic.List[string]]::new()
$Out.Add("# Vor dem Kandidaten aufrufen: Neues seit $SinceText")
$Out.Add('')
$Out.Add('Jeden Punkt einmal in der IDE aufrufen (Befehl, Einstellung umschalten, Fenster öffnen) und abhaken. ' +
    'Was nicht wie beschrieben geht, ist ein Fehler für diesen Kandidaten, nicht für den nächsten.')
$Total = 0
foreach ($Heading in $Entries.Keys) {
    if ($Entries[$Heading].Count -eq 0) { continue }
    $Out.Add('')
    $Out.Add("## $Heading")
    $Out.Add('')
    foreach ($Line in $Entries[$Heading]) { $Out.Add($Line) }
    $Total += $Entries[$Heading].Count
}
$Folder = Split-Path -Parent $OutFile
if ($Folder -and -not (Test-Path $Folder)) { New-Item -ItemType Directory -Force $Folder | Out-Null }
[IO.File]::WriteAllText($OutFile, ($Out -join "`n") + "`n", [Text.UTF8Encoding]::new($false))
Write-Host "Liste vor dem Kandidaten: $Total Einträge -> $OutFile"
