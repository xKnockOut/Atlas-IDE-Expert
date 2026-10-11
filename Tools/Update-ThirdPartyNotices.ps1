<#
.SYNOPSIS
  Erzeugt THIRD-PARTY-NOTICES.md (#77) aus den Laufzeitpaketen der VS-Code-Erweiterung
  (package-lock.json ohne dev) samt Lizenztexten aus node_modules und den festen Einträgen
  (DUnitX). Mit -Check nur prüfen, ob die Datei aktuell ist (Exit-Code 1 sonst).
  Vorher in Editors/VSCode "npm ci" ausführen.
#>
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Extension = Join-Path $Root 'Editors/VSCode'
$Target = Join-Path $Root 'THIRD-PARTY-NOTICES.md'

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('# Hinweise zu Drittanbieter-Komponenten')
$Lines.Add('')
$Lines.Add('Erzeugt von `Tools/Update-ThirdPartyNotices.ps1`; nicht von Hand ändern.')
$Lines.Add('')
$Lines.Add('Atlas selbst steht unter der MIT-Lizenz (`LICENSE`). Es enthält keine Quelltexte von Embarcadero;')
$Lines.Add('RTL- und VCL-Quellen werden nur lokal aus der Delphi-Installation gelesen und nie weitergegeben.')
$Lines.Add('')
$Lines.Add('## Nur zum Testen (nicht in Releases enthalten)')
$Lines.Add('')
$Lines.Add('### DUnitX')
$Lines.Add('')
$Lines.Add('- Quelle: https://github.com/VSoftTechnologies/DUnitX')
$Lines.Add('- Lizenz: Apache-2.0')
$Lines.Add('')
$Lines.Add('```')
foreach ($Line in (Get-Content (Join-Path $PSScriptRoot 'Licenses/Apache-2.0.txt'))) { $Lines.Add($Line.TrimEnd()) }
$Lines.Add('```')
$Lines.Add('')
$Lines.Add('## In der VS-Code-Erweiterung (.vsix) enthalten')
$Lines.Add('')

$Lock = Get-Content (Join-Path $Extension 'package-lock.json') -Raw | ConvertFrom-Json -AsHashtable
foreach ($Key in ($Lock.packages.Keys | Sort-Object)) {
  $Property = [pscustomobject]@{ Name = $Key; Value = [pscustomobject]$Lock.packages[$Key] }
  if ($Key -eq '' -or $Property.Value.dev) { continue }
  $Name = $Property.Name -replace '^.*node_modules/', ''
  $Dir = Join-Path $Extension $Property.Name
  $File = Get-ChildItem $Dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^licen[cs]e' } | Select-Object -First 1
  if (-not $File) { throw "Lizenztext für $Name fehlt in $Dir (npm ci ausgeführt?)" }
  $Lines.Add("### $Name $($Property.Value.version)")
  $Lines.Add('')
  $Lines.Add("- Lizenz: $($Property.Value.license)")
  $Lines.Add('')
  $Lines.Add('```')
  foreach ($Line in (Get-Content $File.FullName)) { $Lines.Add($Line.TrimEnd()) }
  $Lines.Add('```')
  $Lines.Add('')
}
$Text = ($Lines -join "`n").TrimEnd() + "`n"

if ($Check) {
  $Current = if (Test-Path $Target) { (Get-Content $Target -Raw) -replace "`r`n", "`n" } else { '' }
  if ($Current -ne $Text) {
    [Console]::Error.WriteLine('THIRD-PARTY-NOTICES.md ist veraltet; Tools/Update-ThirdPartyNotices.ps1 ausführen.')
    exit 1
  }
  Write-Output 'THIRD-PARTY-NOTICES.md ist aktuell.'
  exit 0
}
[System.IO.File]::WriteAllText($Target, $Text, [System.Text.UTF8Encoding]::new($false))
Write-Output "Geschrieben: $Target"
