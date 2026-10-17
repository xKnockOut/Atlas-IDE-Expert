<#
.SYNOPSIS
    Erzeugt whatsnew.json für die Karte „Neu in Atlas“ (#756) aus CHANGELOG.md.

.DESCRIPTION
    Quelle sind die Einträge der veröffentlichten Versionen ("## [1.1.0] - …")
    mit einer Markierung am Ende der Zeile:

      - Suchfeld der Willkommensseite (#760): … <!-- whatsnew setting=WelcomePageSearch key=WelcomePageSearchKey command=Atlas.WelcomeStart -->

    Felder der Markierung (alle freiwillig, Werte mit Leerzeichen in "…"):
      title    Titel; sonst der Text vor „(#nnn):“ bzw. vor dem ersten Doppelpunkt
      text     ein Satz Erklärung; sonst der erste Satz nach dem Doppelpunkt
      setting  Name der Plugin-Einstellung (wie in der Registry) für den Schalter
      key      Plugin-Einstellung mit dem Tastenkürzel, das die Karte zeigt
      command  Atlas-Befehl der Befehlspalette für „Ausprobieren“
      sample   Beispieldatei relativ zum Installationsordner (Setup/Beispiele -> Beispiele\…)
      line     Zeile in der Beispieldatei ab 1
      experimental  true, wenn die Funktion experimentell ist (#834); ebenso alle
               Einträge unter einer Überschrift „### Experimentell“ der Version

    Experimentelle Einträge zeigt die Karte in einem eigenen Abschnitt
    „Experimentell“ mit dem Hinweis auf den Hauptschalter.

    Ohne Markierung kommt ein Eintrag nicht auf die Karte. Markdown (`code`,
    *kursiv*, **fett**, Links) wird zu Text. Mit -Unreleased zählt der
    Abschnitt [Unveröffentlicht] als Version -Unreleased (für Testbauten).
    Get-ChangelogSection.ps1 entfernt die Markierungen aus den Release-Notizen.

.EXAMPLE
    pwsh Tools/Update-WhatsNew.ps1 -OutFile dist/whatsnew.json
    pwsh Tools/Update-WhatsNew.ps1 -Unreleased 1.1.0 -OutFile Output/whatsnew.json
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $OutFile = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Output/whatsnew.json'),
    [string] $Unreleased = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Fields = 'title', 'text', 'setting', 'key', 'command', 'sample', 'line', 'experimental'

function ConvertFrom-Markdown([string] $Text) {
    $Text = [regex]::Replace($Text, '\[([^\]]*)\]\([^)]*\)', '$1')
    $Text = [regex]::Replace($Text, '\*\*([^*]+)\*\*', '$1')
    $Text = [regex]::Replace($Text, '\*([^*]+)\*', '$1')
    $Text = $Text.Replace('`', '')
    return ($Text -replace '\s+', ' ').Trim()
}

function Get-Marker([string] $Body) {
    $Result = [ordered]@{}
    foreach ($Match in [regex]::Matches($Body, '(\w+)=(?:"([^"]*)"|(\S+))')) {
        $Name = $Match.Groups[1].Value
        if ($Fields -notcontains $Name) { throw "Unbekanntes Feld '$Name' in der whatsnew-Markierung: $Body" }
        $Value = $Match.Groups[2].Value
        if (-not $Match.Groups[2].Success) { $Value = $Match.Groups[3].Value }
        $Result[$Name] = $Value
    }
    return $Result
}

function ConvertTo-WhatsNewItem([string] $Line) {
    $Marker = [regex]::Match($Line, '<!--\s*whatsnew\b(.*?)-->')
    if (-not $Marker.Success) { return $null }
    $Values = Get-Marker $Marker.Groups[1].Value
    $Entry = $Line.Remove($Marker.Index, $Marker.Length) -replace '^\s*-\s+', ''
    # Titel: vor „(#nnn):“ bzw. vor dem ersten Doppelpunkt; Text: erster Satz danach.
    $Head = [regex]::Match($Entry, '^(.*?)(?:\s*\((?:#\d+(?:,\s*)?)+\))?:\s+(.*)$')
    $Title = ''
    $Rest = $Entry
    if ($Head.Success) {
        $Title = ConvertFrom-Markdown $Head.Groups[1].Value
        $Rest = $Head.Groups[2].Value
    }
    $Sentence = [regex]::Match((ConvertFrom-Markdown $Rest), '^.*?[.!?](?=\s|$)')
    $Text = ConvertFrom-Markdown $Rest
    if ($Sentence.Success) { $Text = $Sentence.Value }
    $Item = [ordered]@{ title = $Title; text = $Text }
    foreach ($Name in $Values.Keys) {
        if ($Name -eq 'line') { $Item.line = [int] $Values[$Name] }
        elseif ($Name -eq 'experimental') {
            if ($Values[$Name] -notin 'true', 'false') { throw "experimental muss true oder false sein: $Line" }
            if ($Values[$Name] -eq 'true') { $Item.experimental = $true }
        }
        elseif ($Name -eq 'sample') { $Item.sample = $Values[$Name].Replace('/', '\') }
        else { $Item[$Name] = $Values[$Name] }
    }
    if (-not $Item.title) { throw "whatsnew-Eintrag ohne Titel: $Line" }
    if ($Item.Contains('sample') -and -not (Test-Path (Join-Path $Root ('Setup/' + $Item.sample.Replace('\', '/'))))) {
        throw "Beispieldatei fehlt: Setup/$($Item.sample)"
    }
    return $Item
}

$Versions = [System.Collections.Generic.List[object]]::new()
$Current = $null
$InExperimental = $false
foreach ($Line in Get-Content -Encoding utf8 (Join-Path $Root 'CHANGELOG.md')) {
    if ($Line -match '^###\s+(.*?)\s*$') {
        $InExperimental = $Matches[1] -eq 'Experimentell'
        continue
    }
    if ($Line -match '^## \[([^\]]+)\]') {
        $Name = $Matches[1]
        $Current = $null
        $InExperimental = $false
        if ($Name -eq 'Unveröffentlicht') {
            if (-not $Unreleased) { continue }
            $Name = $Unreleased
        }
        $Current = [ordered]@{ version = $Name; items = [System.Collections.Generic.List[object]]::new() }
        $Versions.Add($Current)
        continue
    }
    if ($null -eq $Current -or $Line -notmatch '^\s*-\s') { continue }
    $Item = ConvertTo-WhatsNewItem $Line
    if ($null -eq $Item) { continue }
    if ($InExperimental) { $Item.experimental = $true }
    $Current.items.Add($Item)
}

$Result = [ordered]@{ versions = @($Versions | Where-Object { $_.items.Count -gt 0 } | ForEach-Object {
    [ordered]@{ version = $_.version; items = @($_.items) }
}) }
$Json = $Result | ConvertTo-Json -Depth 6
$Folder = Split-Path -Parent $OutFile
if ($Folder -and -not (Test-Path $Folder)) { New-Item -ItemType Directory -Force $Folder | Out-Null }
# UTF-8 ohne BOM; das Plugin liest beides.
[System.IO.File]::WriteAllText($OutFile, $Json + "`n", [System.Text.UTF8Encoding]::new($false))
$Count = ($Result.versions | ForEach-Object { $_.items.Count } | Measure-Object -Sum).Sum
Write-Host "whatsnew.json: $($Result.versions.Count) Versionen, $Count Einträge -> $OutFile"
