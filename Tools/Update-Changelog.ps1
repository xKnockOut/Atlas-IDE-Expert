<#
.SYNOPSIS
    Führt die Changelog-Fragmente aus changelog.d/ in CHANGELOG.md zusammen.

.DESCRIPTION
    Ein Pull Request ändert CHANGELOG.md nicht, sondern legt seine Einträge als eigene Datei
    changelog.d/<Issue>-<Stichwort>.md an. Parallele Pull Requests schrieben sonst alle an dieselbe
    Stelle unter „## [Unveröffentlicht]“, und jeder Merge machte die übrigen konfliktbehaftet.
    Aufbau eines Fragments wie ein Abschnitt in CHANGELOG.md:

      ### Neu
      - Eintrag (#1234, `einstellung`, Vorgabe an): …

    Erlaubte Überschriften: Neu, Experimentell, Geändert, Behoben, Entfernt, Tests. Ein Eintrag ist eine
    Zeile „- …“; eingerückte Folgezeilen gehören zum Eintrag davor. changelog.d/README.md ist kein Fragment.

    Ohne Schalter: Einträge unter „## [Unveröffentlicht]“ einsortieren (je Überschrift vor die vorhandenen,
    Fragmente nach Dateinamen) und die Fragmente löschen. Set-Version.ps1 ruft das beim Release auf.
    -Check: nur den Aufbau der Fragmente prüfen, nichts schreiben.
    -Preview: CHANGELOG.md mit eingefügten Fragmenten ausgeben, nichts schreiben (Update-WhatsNew.ps1 -Unreleased).
    -Base <Ref> (mit -Check, Ziel des Pull Requests): Fehler, wenn CHANGELOG.md gegenüber dem Ziel neue Einträge
    bekommt, außer beim Release (Atlas.Text.Product.Version geändert). Berichtigen und Löschen bleibt erlaubt.

.EXAMPLE
    pwsh Tools/Update-Changelog.ps1 -Check
    pwsh Tools/Update-Changelog.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Check,
    [switch] $Preview,
    [string] $Base = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Headings = @('Neu', 'Experimentell', 'Geändert', 'Behoben', 'Entfernt', 'Tests')
$FragmentDir = Join-Path $Root 'changelog.d'
$ChangelogPath = Join-Path $Root 'CHANGELOG.md'
$Problems = [System.Collections.Generic.List[string]]::new()

# Einträge je Überschrift in Reihenfolge der Fragmente; Folgezeilen hängen mit Zeilenumbruch am Eintrag.
$Entries = [ordered]@{}
foreach ($Heading in $Headings) { $Entries[$Heading] = [System.Collections.Generic.List[string]]::new() }

$Fragments = @()
if (Test-Path $FragmentDir) {
    $Fragments = @(Get-ChildItem -Path $FragmentDir -Filter '*.md' -File |
        Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
}
foreach ($Fragment in $Fragments) {
    $Current = ''
    $HasEntry = $false
    $Count = 0
    $LineNo = 0
    foreach ($Raw in [IO.File]::ReadAllLines($Fragment.FullName)) {
        $LineNo++
        $Line = $Raw.TrimEnd().TrimStart([char]0xFEFF)
        if ($Line -eq '') { continue }
        $Where = "changelog.d/$($Fragment.Name):$LineNo"
        if ($Line -match '^###\s+(.+)$') {
            $Name = $Matches[1].Trim()
            $HasEntry = $false
            if ($Headings -cnotcontains $Name) {
                $Problems.Add("${Where}: unbekannte Überschrift „$Name“ (erlaubt: $($Headings -join ', '))")
                $Current = ''
                continue
            }
            $Current = $Name
            continue
        }
        if ($Line -match '^#') {
            $Problems.Add("${Where}: nur Überschriften „### …“ erlaubt")
            continue
        }
        if ($Current -eq '') {
            $Problems.Add("${Where}: Eintrag ohne Überschrift „### …“ davor")
            continue
        }
        if ($Line -match '^- \S') {
            $Entries[$Current].Add($Line)
            $HasEntry = $true
            $Count++
            continue
        }
        if ($HasEntry -and $Line -match '^\s+\S') {
            $Last = $Entries[$Current].Count - 1
            $Entries[$Current][$Last] = $Entries[$Current][$Last] + "`n" + $Line
            continue
        }
        $Problems.Add("${Where}: erwartet „### Überschrift“ oder „- Eintrag“")
    }
    if ($Count -eq 0) {
        $Problems.Add("changelog.d/$($Fragment.Name): keine Einträge")
    }
}

$Bytes = [IO.File]::ReadAllBytes($ChangelogPath)
$HasBom = $Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF
$Text = [IO.File]::ReadAllText($ChangelogPath)
$Newline = "`n"
if ($Text.Contains("`r`n")) { $Newline = "`r`n" }
$Lines = [System.Collections.Generic.List[string]]::new()
foreach ($Line in ($Text -split '\r?\n')) { $Lines.Add($Line) }
$Start = $Lines.IndexOf('## [Unveröffentlicht]')
if ($Start -lt 0) {
    $Problems.Add('CHANGELOG.md: Abschnitt „## [Unveröffentlicht]“ fehlt')
}

if ($Base) {
    $VersionUnit = 'Packages/Atlas.Text/Source/Product/Atlas.Text.Product.Version.pas'
    & git -C $Root diff --quiet $Base -- $VersionUnit
    $IsRelease = $LASTEXITCODE -ne 0
    # Geänderte Einträge erscheinen als - und +; nur ein Überschuss an + sind neue Einträge.
    $Diff = @(& git -C $Root diff -U0 $Base -- 'CHANGELOG.md')
    $Added = @($Diff | Where-Object { $_ -match '^\+- ' }).Count - @($Diff | Where-Object { $_ -match '^-- ' }).Count
    if ($Added -gt 0 -and -not $IsRelease) {
        $Problems.Add("CHANGELOG.md hat $Added neue Einträge; Einträge als Fragment nach changelog.d/ (siehe changelog.d/README.md)")
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
if ($Check) {
    Write-Host "Changelog-Fragmente in Ordnung ($($Fragments.Count))."
    exit 0
}

# Ende des Abschnitts: nächste Versionsüberschrift oder Dateiende.
function Get-SectionEnd {
    for ($i = $Start + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].StartsWith('## ')) { return $i }
    }
    return $Lines.Count
}

# Rückwärts einsortieren, damit eine neu angelegte Überschrift vor den späteren landet.
for ($h = $Headings.Count - 1; $h -ge 0; $h--) {
    $Heading = $Headings[$h]
    if ($Entries[$Heading].Count -eq 0) { continue }
    $New = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in $Entries[$Heading]) {
        foreach ($Part in ($Entry -split "`n")) { $New.Add($Part) }
    }
    $End = Get-SectionEnd
    $At = -1
    for ($i = $Start + 1; $i -lt $End; $i++) {
        if ($Lines[$i] -ceq "### $Heading") { $At = $i + 1; break }
    }
    if ($At -lt 0) {
        # Überschrift fehlt: vor die erste spätere Überschrift des Abschnitts, sonst ans Ende des Abschnitts.
        $At = $End
        for ($i = $Start + 1; $i -lt $End; $i++) {
            if ($Lines[$i] -match '^### (.+)$' -and $Headings.IndexOf($Matches[1].Trim()) -gt $h) { $At = $i; break }
        }
        if ($At -eq $End) {
            while ($At -gt $Start + 1 -and $Lines[$At - 1] -eq '') { $At-- }
            $New.Insert(0, "### $Heading")
            $New.Insert(0, '')
        }
        else {
            $New.Insert(0, "### $Heading")
            $New.Add('')
        }
    }
    $Lines.InsertRange($At, $New)
}

$Result = $Lines -join $Newline
if ($Preview) {
    Write-Output $Result
    exit 0
}
[IO.File]::WriteAllText($ChangelogPath, $Result, (New-Object System.Text.UTF8Encoding($HasBom)))
foreach ($Fragment in $Fragments) { Remove-Item -LiteralPath $Fragment.FullName }
Write-Host "CHANGELOG.md: $($Fragments.Count) Fragmente übernommen."
exit 0
