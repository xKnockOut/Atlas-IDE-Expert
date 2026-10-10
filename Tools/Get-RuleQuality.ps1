<#
.SYNOPSIS
    Berechnet die Fehlalarmquote je Regel aus den Bewertungen (#152).

.DESCRIPTION
    Liest Tests/Referenzprojekt/bewertungen.csv (Spalten Regel-ID, Datei,
    Zeile, Bewertung, Datum; Bewertung "richtig" oder "falsch") und gibt je
    Regel die Anzahl richtiger und falscher Treffer sowie die Fehlalarmquote
    aus. Dieselbe Rechnung steckt in TGoldenCorpus.Rates.

    Exit-Code 0: in Ordnung. 1: ungültige Bewertung in der Datei.

.EXAMPLE
    pwsh Tools/Get-RuleQuality.ps1
    pwsh Tools/Get-RuleQuality.ps1 -Path andere.csv
#>
[CmdletBinding()]
param(
    [string] $Path = (Join-Path (Split-Path -Parent $PSScriptRoot) 'Tests/Referenzprojekt/bewertungen.csv')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$rows = @(Import-Csv -Path $Path -Encoding utf8)
$invalid = @($rows | Where-Object { $_.Bewertung -notin @('richtig', 'falsch') })
if ($invalid.Count -gt 0) {
    foreach ($row in $invalid) {
        Write-Error "Ungültige Bewertung '$($row.Bewertung)' für $($row.'Regel-ID') in $($row.Datei):$($row.Zeile)" -ErrorAction Continue
    }
    exit 1
}

if ($rows.Count -eq 0) {
    Write-Host 'Noch keine Bewertungen.'
    exit 0
}

$rows | Group-Object -Property 'Regel-ID' | Sort-Object Name | ForEach-Object {
    $correct = @($_.Group | Where-Object Bewertung -eq 'richtig').Count
    $wrong = @($_.Group | Where-Object Bewertung -eq 'falsch').Count
    [pscustomobject]@{
        Regel = $_.Name
        Richtig = $correct
        Falsch = $wrong
        Fehlalarmquote = '{0:P1}' -f ($wrong / ($correct + $wrong))
    }
} | Format-Table -AutoSize | Out-String -Width 200
