<#
.SYNOPSIS
    Findet doppelte XML-Doku-Kommentare (Code-Review K-04).

.DESCRIPTION
    Sucht in Packages/, Application/ und Setup/ jeden zusammenhängenden Block aus
    "///"-Zeilen, der mehr als ein <summary> enthält. Solche Blöcke entstehen, wenn
    beim Einfügen einer Deklaration der Kommentar der Nachbarin verrutscht: Die IDE
    zeigt dann nur einen der Texte, der andere hängt an der falschen Deklaration.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-DocComments.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$SourceDirs = @('Packages', 'Application', 'Setup')
$problems = @()

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
    Write-Host 'Doppelte XML-Doku-Kommentare (der Text gehört vermutlich zu einer anderen Deklaration):' -ForegroundColor Red
    $problems | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Keine doppelten XML-Doku-Kommentare.' -ForegroundColor Green
exit 0
