<#
.SYNOPSIS
    Findet doppelte XML-Doku-Kommentare und Kennungen aus Code-Reviews.

.DESCRIPTION
    Sucht in Packages/, Application/ und Setup/ jeden zusammenhängenden Block aus
    "///"-Zeilen, der mehr als ein <summary> enthält. Solche Blöcke entstehen, wenn
    beim Einfügen einer Deklaration der Kommentar der Nachbarin verrutscht: Die IDE
    zeigt dann nur einen der Texte, der andere hängt an der falschen Deklaration.

    Außerdem lehnt es Befundkennungen aus Code-Reviews ab ("Code-Review X-nnn" oder nur "(X-nnn)", X ein Großbuchstabe, nnn drei Ziffern) in Quelltext,
    Tests, Skripten, Workflows und Doku. Die Berichte liegen nicht im Repository, eine Kennung führt den Leser
    also ins Leere. Der Kommentar soll den Grund selbst nennen.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-DocComments.ps1

.EXAMPLE
    pwsh Tools/Check-DocComments.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    # Prüft die Erkennung der Review-Kennungen an kleinen Beispielen (CI).
    [switch] $SelfTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDirs = @('Packages', 'Application', 'Setup')
$problems = @()

# Kennung eines Review-Befunds: Kategoriebuchstabe, Bindestrich, drei Ziffern. Erkannt wird sie nach
# "Code-Review" oder "Befund" (auch über einen Zeilenumbruch im Kommentar) oder allein in Klammern, auch
# mehrere mit "/" oder "," getrennt, oder als letzter Eintrag einer Klammer nach Komma. Die Beispiele im Selbsttest sind zusammengesetzt, sonst fände sich das
# Skript selbst.
$ReviewIdDirs = @('Packages', 'Application', 'Setup', 'Tests', 'Tools', 'Editors', 'schemas', 'docs',
    'changelog.d', '.github')
$ReviewIdFiles = @('README.md', 'README_DE.md', 'atlas.json')
$ReviewIdTypes = @('*.pas', '*.dpr', '*.dpk', '*.inc', '*.pp', '*.dfm', '*.ps1', '*.py', '*.sh', '*.mjs', '*.yml',
    '*.md', '*.json', '*.txt')
$ReviewId = '[A-Z]-\d{3}'
$ReviewIdRegex = [regex]::new(
    "(?i:code-?(?:\s|//|\#|\*)*review|befund)[\s:(]{1,4}$ReviewId\b|\(\s*$ReviewId(?:\s*[/,]\s*$ReviewId)*\s*\)|[,;]\s*$ReviewId\s*\)",
    'Compiled')

function Find-ReviewIds([string] $Text) {
    $Lines = New-Object 'System.Collections.Generic.List[int]'
    foreach ($Match in $ReviewIdRegex.Matches($Text)) {
        $Lines.Add($Text.Substring(0, $Match.Index).Split("`n").Count)
    }
    return , $Lines.ToArray()
}

if ($SelfTest) {
    $Id = 'T' + '-103'
    $Pair = 'R' + '-101/D' + '-104'
    $Hits = @(
        "// Vor FreeLibrary (Code-Review $Id).",
        "// Vor FreeLibrary (Code-`r`n// Review $Id).",
        "/// <summary>Code-Review ${Id}: Text</summary>",
        "# Gegenstück ($Pair); weiter",
        "- name: Selbstprüfung (Befund $Id)",
        "/// (Antwort des Plugins, $Id): Text"
    )
    $Misses = @(
        "// Führe ein Code-Review der Unit durch.",
        "Result := 'UTF-8';",
        "// Siehe #1233 und ISO-8601.",
        "// Werte (1-100) und (A-Z)"
    )
    $Failed = @()
    foreach ($Sample in $Hits) { if ((Find-ReviewIds $Sample).Count -eq 0) { $Failed += "nicht erkannt: $Sample" } }
    foreach ($Sample in $Misses) { if ((Find-ReviewIds $Sample).Count -gt 0) { $Failed += "falsch erkannt: $Sample" } }
    if ($Failed.Count -gt 0) {
        Write-Host 'Selbsttest der Review-Kennungen fehlgeschlagen:' -ForegroundColor Red
        $Failed | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host 'Selbsttest der Review-Kennungen bestanden.' -ForegroundColor Green
    exit 0
}

$ReviewIdPaths = @()
foreach ($dir in $ReviewIdDirs) {
    $path = Join-Path $Root $dir
    if (Test-Path $path) {
        $ReviewIdPaths += Get-ChildItem -Path $path -Recurse -File -Include $ReviewIdTypes |
            Where-Object { $_.FullName -notmatch '[\\/](Output|__pycache__)[\\/]' }
    }
}
foreach ($name in $ReviewIdFiles) {
    $path = Join-Path $Root $name
    if (Test-Path $path) { $ReviewIdPaths += Get-Item $path }
}
foreach ($file in $ReviewIdPaths) {
    $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
    foreach ($line in (Find-ReviewIds ([IO.File]::ReadAllText($file.FullName)))) {
        $problems += "${relative}:${line}: Kennung aus einem Code-Review (den Grund selbst nennen)"
    }
}

foreach ($dir in $SourceDirs) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }

    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas', '*.dpr', '*.dpk', '*.inc') {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        $lines = [IO.File]::ReadAllLines($file.FullName)
        $i = 0
        while ($i -lt $lines.Count) {
            if ($lines[$i].TrimStart().StartsWith('///')) {
                $start = $i
                while (($i + 1 -lt $lines.Count) -and $lines[$i + 1].TrimStart().StartsWith('///')) { $i++ }
                $count = ([regex]::Matches(($lines[$start..$i] -join ' '), '<summary>')).Count
                if ($count -gt 1) {
                    $problems += "${relative}:$($start + 1): $count <summary> hintereinander"
                }
            }
            $i++
        }
    }
}

if ($problems.Count -gt 0) {
    Write-Host 'Doppelte XML-Doku-Kommentare (der Text gehört vermutlich zu einer anderen Deklaration) oder' `
        'Kennungen aus Code-Reviews:' -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Keine doppelten XML-Doku-Kommentare und keine Review-Kennungen.' -ForegroundColor Green
exit 0
