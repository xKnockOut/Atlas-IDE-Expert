<#
.SYNOPSIS
    Prüft, dass das IDE-Plugin nur über TAtlasMainThread in den Hauptthread einreiht (Code-Review A-02).

.DESCRIPTION
    TThread.Queue(nil, …) und TThread.ForceQueue(nil, …) gehören keinem Thread:
    Beim Entladen des Packages räumt niemand die Einträge weg, und
    CheckSynchronize ruft sie danach in nicht mehr geladenem Code auf. Im Plugin
    reiht deshalb nur TAtlasMainThread (Atlas.Core.Diagnostics.MainThread) ein;
    dessen Besitzer-Thread hält die Komposition beim Entladen an.

    Geprüft werden alle Quelltexte unter Packages/Atlas.IDE.Expert/Source/.
    Server und Atlas.Common sind ausgenommen; dort liegt kein entladbarer Code.
    Threads mit eigener Lebensdauer reihen an sich selbst ein
    (TThread.Queue(Self, …) bzw. Instanz-Queue mit RemoveQueuedEvents) und sind
    davon nicht betroffen.

    Kommentare und Strings werden übergangen. Eine einzelne Zeile lässt sich
    mit dem Kommentar "// mainthread-ok" oder "// lsp-ignore: forbidden-symbol"
    freigeben. Dasselbe Verbot steht als Regel forbidden-symbol in atlas.json
    (#1133).

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-MainThreadQueue.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Freigabe je Zeile: "// mainthread-ok" oder wie bei der Atlas-Regel forbidden-symbol (#1133)
# "// lsp-ignore: forbidden-symbol" in derselben Zeile.
$Exempt = '//\s*(mainthread-ok|lsp-ignore:[^\r\n]*\bforbidden-symbol\b)'

$SourceDirs = @('Packages/Atlas.IDE.Expert/Source')

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

$Pattern = '(?i)\bTThread\s*\.\s*(Force)?Queue\s*\(\s*nil\b'
$Message = 'Einreihen ohne Besitzer überlebt das Entladen; TAtlasMainThread.Queue bzw. ForceQueue verwenden'

$violations = @()

foreach ($dir in $SourceDirs) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }

    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas', '*.dpr', '*.dpk', '*.inc') {
        $relative = [IO.Path]::GetRelativePath($Root, $file.FullName)
        $original = [IO.File]::ReadAllText($file.FullName)
        $originalLines = $original -split "`n"
        $text = Remove-PascalNoise $original

        foreach ($match in [regex]::Matches($text, $Pattern)) {
            $line = Get-LineNumber $text $match.Index
            if ($originalLines[$line - 1] -match $Exempt) { continue }
            $violations += "${relative}:${line}: $Message"
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host 'Einreihen in den Hauptthread ohne TAtlasMainThread:' -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Einreihen in den Hauptthread nur über TAtlasMainThread.' -ForegroundColor Green
exit 0
