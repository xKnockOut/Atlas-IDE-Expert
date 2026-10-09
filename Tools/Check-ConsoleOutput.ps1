<#
.SYNOPSIS
    Prüft, dass Server-Code nicht auf die Konsole (stdout) schreibt.

.DESCRIPTION
    stdout gehört ausschließlich dem LSP-Protokoll (Spezifikation, Abschnitt 9).
    Geprüft werden alle Quelltexte unter Packages/ und Application/:

    - Write/Writeln ohne Dateiangabe (erlaubt ist nur ErrOutput als erstes Argument)
    - GetStdHandle(STD_OUTPUT_HANDLE) außerhalb von Argus.Windows.Console.StdStreams

    Das Testprojekt ist ausgenommen, der DUnitX-Runner schreibt bewusst auf die Konsole.
    Eine einzelne Zeile lässt sich mit dem Kommentar "// console-ok" freigeben.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-ConsoleOutput.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDirs = @('Packages', 'Application')
$StdHandleOwner = 'Argus.Windows.Console.StdStreams.pas'

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

$violations = @()

foreach ($dir in $SourceDirs) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }

    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas', '*.dpr', '*.dpk', '*.inc') {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        $original = [IO.File]::ReadAllText($file.FullName)
        $originalLines = $original -split "`n"
        $text = Remove-PascalNoise $original

        # Write/Writeln als Aufruf, nicht als Methode (".Write") oder Deklaration ("procedure Write").
        foreach ($match in [regex]::Matches($text, '(?i)(?<![\w.])(?<!procedure\s+)(?<!function\s+)\b(write|writeln)\b\s*(?<rest>\(|;|\bend\b|\belse\b)')) {
            $line = Get-LineNumber $text $match.Index
            if ($originalLines[$line - 1] -match '//\s*console-ok') { continue }
            if ($match.Groups['rest'].Value -eq '(') {
                $after = $text.Substring($match.Index + $match.Length)
                if ($after -match '^\s*ErrOutput\s*[,)]') { continue }
            }
            $violations += "${relative}:${line}: $($match.Groups[1].Value) ohne Dateiangabe schreibt auf stdout"
        }

        if ($file.Name -ne $StdHandleOwner) {
            foreach ($match in [regex]::Matches($text, '(?i)GetStdHandle\s*\(\s*STD_OUTPUT_HANDLE\s*\)')) {
                $line = Get-LineNumber $text $match.Index
                if ($originalLines[$line - 1] -match '//\s*console-ok') { continue }
                $violations += "${relative}:${line}: stdout-Handle nur über TStdStreams verwenden"
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Mögliche Ausgaben auf stdout:' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Keine Ausgaben auf stdout gefunden.' -ForegroundColor Green
exit 0
