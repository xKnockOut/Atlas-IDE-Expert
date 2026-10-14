<#
.SYNOPSIS
  Prüft (#77), dass Tests/ keine Dateien mit Copyright-Kopf von
  Embarcadero, CodeGear oder Borland enthalten. Exit-Code 1 bei einem Fund.
#>
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
# Kopf einer RTL-/VCL-Datei: "Copyright(c) 1995-2025 Embarcadero Technologies, Inc."
$Pattern = 'Copyright\s*(\(c\)|©)?[^\r\n]{0,40}(Embarcadero|CodeGear|Borland)'
$Found = [System.Collections.Generic.List[string]]::new()

function Test-Text([string]$Name, [string]$Text) {
  # Nur der Dateikopf zählt; Hinweise im Fließtext (z. B. Doku) sind keine Quellen.
  $Head = if ($Text.Length -gt 4000) { $Text.Substring(0, 4000) } else { $Text }
  if ($Head -match $Pattern) { $Found.Add($Name) }
}

foreach ($File in Get-ChildItem (Join-Path $Root 'Tests') -Recurse -File) {
  Test-Text $File.FullName ([System.IO.File]::ReadAllText($File.FullName))
}
if ($Found.Count -gt 0) {
  foreach ($Name in $Found) { [Console]::Error.WriteLine("Embarcadero-Quelltext gefunden: $Name") }
  exit 1
}
Write-Output 'Keine Embarcadero-Quellen gefunden.'
