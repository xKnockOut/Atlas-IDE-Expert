<#
.SYNOPSIS
    Prüft, dass der eigene Quelltext auch mit Delphi 12 übersetzt (#281).

.DESCRIPTION
    Atlas soll mit Delphi 12 und 13 gebaut werden. Geprüft werden alle
    Quelltexte unter Packages/, Application/, Setup/ und Tests/ auf Syntax, die erst
    Delphi 13 kennt:

    - Bedingungsausdruck "if … then … else" als Ausdruck (nach :=, (, [ oder ,)
    - "is not" und "not in"

    In Packages/, Application/ und Setup/ außerdem Code mit fester Zeigergröße, der
    in der 64-Bit-IDE und im Win64-Server bricht (#281):

    - GetWindowLong/SetWindowLong/GetClassLong/SetClassLong statt …LongPtr
    - Zeiger, @X oder Self in Integer/Cardinal/LongInt/DWORD umgewandelt
      oder umgekehrt; NativeInt/NativeUInt verwenden

    Außerdem müssen alle .dproj-Dateien eine ProjectVersion haben, die
    Delphi 12 öffnet (bis 20.3; 20.3 ist RAD Studio 13, Delphi 12 aktualisiert
    die Datei beim Öffnen ohne Datenverlust).

    Kommentare und Strings werden übergangen. Eine einzelne Zeile lässt sich
    mit dem Kommentar "// delphi13-ok" freigeben.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-Delphi12.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDirs = @('Packages', 'Application', 'Setup', 'Tests')
$MaxProjectVersion = [version]'20.3'

function Remove-PascalNoise([string] $Text) {
    # Ersetzt Kommentare, Direktiven und Strings durch Leerzeichen und behält
    # Zeilenumbrüche bei, damit Zeilennummern stimmen.
    $pattern = '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*|''(?:[^'']|'''')*'''
    return [regex]::Replace($Text, $pattern, {
        param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ')
    })
}

function Get-LineNumber([string] $Text, [int] $Index) {
    return ($Text.Substring(0, $Index) -split "`n").Count
}

$Checks = @(
    @{ Pattern = '(?i)(:=|\(|\[|,)\s*if\b'; Message = 'Bedingungsausdruck "if … then … else" gibt es erst ab Delphi 13' },
    @{ Pattern = '(?i)\bis\s+not\b'; Message = '"is not" gibt es erst ab Delphi 13; "not (X is T)" verwenden' },
    @{ Pattern = '(?i)\bnot\s+in\b'; Message = '"not in" gibt es erst ab Delphi 13; "not (X in M)" verwenden' }
)

$PointerDirs = @('Packages', 'Application', 'Setup')
$PointerChecks = @(
    @{ Pattern = '(?i)\b(Get|Set)(Window|Class)Long[AW]?\s*\('; Message = '…Long schneidet Zeiger in 64 Bit ab; …LongPtr verwenden' },
    @{ Pattern = '(?i)\b(Integer|Cardinal|LongInt|LongWord|DWORD|UInt32|Int32)\s*\(\s*(Pointer\b|@|Self\b|Addr\s*\()'; Message = 'Zeiger in 32-Bit-Ganzzahl umgewandelt; NativeInt oder NativeUInt verwenden' },
    @{ Pattern = '(?i)\bPointer\s*\(\s*(Integer|Cardinal|LongInt|LongWord|DWORD|UInt32|Int32)\s*\('; Message = '32-Bit-Ganzzahl in Zeiger umgewandelt; NativeInt oder NativeUInt verwenden' }
)

$violations = @()

foreach ($dir in $SourceDirs) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }

    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas', '*.dpr', '*.dpk', '*.inc') {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        $original = [IO.File]::ReadAllText($file.FullName)
        $originalLines = $original -split "`n"
        $text = Remove-PascalNoise $original

        $active = $Checks
        if ($PointerDirs -contains $dir) { $active = $Checks + $PointerChecks }
        foreach ($check in $active) {
            foreach ($match in [regex]::Matches($text, $check.Pattern)) {
                $line = Get-LineNumber $text $match.Index
                if ($originalLines[$line - 1] -match '//\s*delphi13-ok') { continue }
                $violations += "${relative}:${line}: $($check.Message)"
            }
        }
    }
}

foreach ($project in Get-ChildItem -Path $Root -Recurse -File -Filter '*.dproj') {
    $relative = [IO.Path]::GetRelativePath($Root, $project.FullName)
    $content = [IO.File]::ReadAllText($project.FullName)
    if ($content -match '<ProjectVersion>([^<]+)</ProjectVersion>') {
        $version = [version]$Matches[1]
        if ($version -gt $MaxProjectVersion) {
            $violations += "${relative}: ProjectVersion $version ist neuer als $MaxProjectVersion"
        }
    } else {
        $violations += "${relative}: ProjectVersion fehlt"
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Nicht mit Delphi 12 oder Win64 verträglich:' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Quelltext ist mit Delphi 12 und Win64 verträglich.' -ForegroundColor Green
exit 0
