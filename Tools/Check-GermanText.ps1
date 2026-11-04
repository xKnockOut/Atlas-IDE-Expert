<#
.SYNOPSIS
    Meldet deutsche Literale außerhalb der Texttabellen (#1458).

.DESCRIPTION
    Mit englischer IDE soll Atlas englisch sprechen. Benutzertexte stehen deshalb in
    Texttabellen (array[…] of TAtlasText mit De und En, im Plugin Atlas.UI.Strings).
    Dieses Werkzeug sucht in Packages/ und Application/ String-Literale, die nach
    deutschem Text aussehen: Umlaute oder ß, oder ein häufiges deutsches Wort
    (und, nicht, oder, der, die, das, ist, mit, für, kein, wird, …).

    Ausgenommen sind:
    - Kommentare und Direktiven,
    - die Einträge von Texttabellen "array[…] of TAtlasText = (" bis zum Ende ");",
    - Zeilen mit dem Kommentar "// german-ok" (Text, der deutsch bleiben muss,
      etwa Schlüsselwörter der deutschen YouTrack-Oberfläche),
    - Atlas.UI.Strings (Texttabelle des Plugins) und die erzeugten Units
      (*SchemaData.pas, *ProfileData.pas, *Catalog.Data.pas und ihre Teile *Catalog.Data.*.pas).

    Den Altbestand hält Tools/GermanText.baseline.json je Datei fest. Eine Datei darf
    nicht mehr Funde haben als dort eingetragen; neue Dateien haben 0. Sinkt die Zahl,
    meldet das Werkzeug das als Hinweis: mit -Update die Altliste nachziehen, damit
    sie nur schrumpft.

    Exit-Code 0: nicht mehr als in der Altliste, 1: neue deutsche Literale.

.EXAMPLE
    pwsh Tools/Check-GermanText.ps1

.EXAMPLE
    pwsh Tools/Check-GermanText.ps1 -Update

.EXAMPLE
    pwsh Tools/Check-GermanText.ps1 -SelfTest

.EXAMPLE
    pwsh Tools/Check-GermanText.ps1 -List Packages/Atlas.Common/Source/Rules/Atlas.Common.Rules.Engine.pas
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [switch] $Update,
    # Funde dieser Dateien einzeln ausgeben (Pfade relativ zur Wurzel).
    [string[]] $List = @(),
    # Nur zum Test des Werkzeugs: eigene Altliste.
    [string] $BaselinePath = '',
    # Prüft die Erkennung an einem kleinen Beispiel (CI).
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($BaselinePath -eq '') { $BaselinePath = Join-Path $Root 'Tools/GermanText.baseline.json' }
$SourceDirs = @('Packages', 'Application')
$SkipNames = '^(Atlas\.UI\.Strings\.pas|.*SchemaData\.pas|.*ProfileData\.pas|.*Catalog\.Data(\.\w+)?\.pas)$'
$GermanWords = '(?i)(?<![\w%])(und|nicht|oder|der|die|das|dem|den|des|ist|sind|mit|für|kein|keine|keinen|wird|werden|wurde|nach|beim|vom|zum|zur|eine|einen|einer|bitte|Datei|Fehler|Einstellung|gefunden|fehlt|ungültig|unbekannt)(?![\w])'
$Umlaut = '[äöüÄÖÜß]'
$TableStart = '(?i)\bof\s+TAtlasText\s*=\s*\('

function Test-German([string] $Literal) {
    if ($Literal -match $Umlaut) { return $true }
    # Ein einzelnes Wort ohne Leerzeichen ist meist ein Bezeichner oder Schlüssel ('die', 'das').
    if (-not $Literal.Contains(' ')) { return $false }
    return $Literal -match $GermanWords
}

# Funde einer Datei: Zeilennummer und Literal. Ein regulärer Ausdruck über den ganzen Text trennt Kommentare,
# Direktiven und Literale (wie Check-Delphi12); zeichenweise wäre es in PowerShell zu langsam.
$Noise = [regex]::new('(?s)\{.*?\}|\(\*.*?\*\)|//[^\n]*|''(?:[^''\n]|'''')*''', 'Compiled')
$TableRegex = [regex]::new('(?i)\bof\s+TAtlasText\s*=\s*\(', 'Compiled')
function Get-Findings([string] $Text) {
    $Findings = New-Object System.Collections.Generic.List[object]
    $Text = $Text.Replace("`r`n", "`n")
    $Lines = $Text.Split("`n")
    # Anfang jeder Zeile, um Fundstellen Zeilen zuzuordnen.
    $Starts = New-Object System.Collections.Generic.List[int]
    $Starts.Add(0)
    $At = $Text.IndexOf("`n")
    while ($At -ge 0) { $Starts.Add($At + 1); $At = $Text.IndexOf("`n", $At + 1) }
    $Found = $Noise.Matches($Text)
    # Code ohne Kommentare und Literale je Zeile, für die Grenzen der Texttabellen.
    $Code = $Noise.Replace($Text, { param($m) [regex]::Replace($m.Value, '[^\n]', ' ') })
    $CodeLines = $Code.Split("`n")
    $Skip = New-Object 'bool[]' ($Lines.Count + 1)
    $InTable = $false
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        if ($Lines[$Index].Contains('german-ok') -and ($Lines[$Index] -match '//\s*german-ok')) { $Skip[$Index] = $true }
        if (-not $InTable -and $CodeLines[$Index].Contains('TAtlasText') -and $TableRegex.IsMatch($CodeLines[$Index])) { $InTable = $true }
        if ($InTable) {
            $Skip[$Index] = $true
            if ($CodeLines[$Index] -match '\)\s*;\s*$') { $InTable = $false }
        }
    }
    foreach ($Match in $Found) {
        if ($Match.Value[0] -ne "'") { continue }
        $Literal = $Match.Value.Substring(1, $Match.Value.Length - 2).Replace("''", "'")
        if (-not (Test-German $Literal)) { continue }
        $Line = $Starts.BinarySearch($Match.Index)
        if ($Line -lt 0) { $Line = (-bnot $Line) - 1 }
        if ($Skip[$Line]) { continue }
        $Findings.Add([pscustomobject]@{ Line = $Line + 1; Text = $Literal })
    }
    return , $Findings
}

if ($SelfTest) {
    $Sample = @(
        "  // 'Kommentar für niemanden'",
        "  { 'auch kein Fund für die Prüfung' }",
        "  Log('Datei fehlt');",
        "  Log('Größe');",
        "  Log('File missing'); Log('die');",
        "  Log('Übersetzung bleibt'); // german-ok",
        "  cTexts: array[TX] of TAtlasText = (",
        "    (De: 'Datei fehlt'; En: 'File missing'),",
        "    (De: 'Größe'; En: 'Size'));",
        "  Log('nach der Tabelle');") -join "`r`n"
    $Result = Get-Findings $Sample
    $Got = @($Result | ForEach-Object { "$($_.Line):$($_.Text)" }) -join '|'
    $Expected = '3:Datei fehlt|4:Größe|10:nach der Tabelle'
    if ($Got -cne $Expected) { Write-Host "Selbsttest fehlgeschlagen: erwartet $Expected, erhalten $Got"; exit 1 }
    Write-Host 'Selbsttest bestanden.'
    exit 0
}

$Counts = [ordered]@{}
$Details = @{}
foreach ($Dir in $SourceDirs) {
    $Path = Join-Path $Root $Dir
    if (-not (Test-Path $Path)) { continue }
    foreach ($File in Get-ChildItem -Path $Path -Recurse -File -Include '*.pas', '*.dpr', '*.dpk' | Sort-Object FullName) {
        if ($File.Name -match $SkipNames) { continue }
        $Relative = [IO.Path]::GetRelativePath($Root, $File.FullName).Replace('\', '/')
        if ($Relative -match '(^|/)(Output|__history|__recovery)/') { continue }
        $Findings = Get-Findings ([IO.File]::ReadAllText($File.FullName))
        if ($Findings.Count -gt 0) { $Counts[$Relative] = $Findings.Count; $Details[$Relative] = $Findings }
    }
}

foreach ($Wanted in $List) {
    $Key = $Wanted.Replace('\', '/')
    if ($Details.ContainsKey($Key)) { foreach ($Finding in $Details[$Key]) { Write-Host "${Key}:$($Finding.Line): '$($Finding.Text)'" } }
}

$Total = 0
foreach ($Value in $Counts.Values) { $Total += $Value }
if ($Update) {
    $Json = ($Counts | ConvertTo-Json -Depth 2).Replace("`r`n", "`n") + "`n"
    [IO.File]::WriteAllText($BaselinePath, $Json, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Altliste geschrieben: $($Counts.Count) Dateien, $Total deutsche Literale."
    exit 0
}

$Baseline = @{}
if (Test-Path $BaselinePath) { $Baseline = Get-Content -Raw -Encoding utf8 $BaselinePath | ConvertFrom-Json -AsHashtable }
$Failed = $false
foreach ($Key in $Counts.Keys) {
    $Allowed = 0
    if ($Baseline.ContainsKey($Key)) { $Allowed = [int]$Baseline[$Key] }
    if ($Counts[$Key] -gt $Allowed) {
        $Failed = $true
        Write-Host "${Key}: $($Counts[$Key]) deutsche Literale, erlaubt $Allowed. Texte in eine Texttabelle (TAtlasText) stellen oder mit // german-ok begründen:"
        foreach ($Finding in $Details[$Key]) { Write-Host "  Zeile $($Finding.Line): '$($Finding.Text)'" }
    }
}
$Shrunk = @($Baseline.Keys | Where-Object { (-not $Counts.Contains($_)) -or ($Counts[$_] -lt [int]$Baseline[$_]) })
if ($Shrunk.Count -gt 0) { Write-Host "Hinweis: weniger deutsche Literale in $($Shrunk.Count) Dateien; pwsh Tools/Check-GermanText.ps1 -Update zieht die Altliste nach." }
if ($Failed) { exit 1 }
Write-Host "Keine neuen deutschen Literale ($Total im Altbestand)."
exit 0
