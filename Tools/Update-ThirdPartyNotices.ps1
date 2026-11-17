<#
.SYNOPSIS
  Erzeugt THIRD-PARTY-NOTICES.md (#77) aus den festen Einträgen (WebView2, Free Pascal, DUnitX).
  Den Stand von Free Pascal liest es aus FPC_COMMIT in Tools/Linux/Build-AtlasServer.sh.
  Mit -Check nur prüfen, ob die Datei aktuell ist (Exit-Code 1 sonst).
#>
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Target = Join-Path $Root 'THIRD-PARTY-NOTICES.md'

$BuildScript = Get-Content (Join-Path $PSScriptRoot 'Linux/Build-AtlasServer.sh')
$FpcCommit = ($BuildScript | Select-String -Pattern '^FPC_COMMIT=([0-9a-f]+)$' | Select-Object -First 1).Matches[0].Groups[1].Value
$Copies = @(Get-ChildItem (Join-Path $PSScriptRoot 'Linux/Compat') -Recurse -Filter '*.pp' |
  ForEach-Object { 'Tools/Linux/Compat/' + $_.Directory.Name + '/' + $_.Name } | Sort-Object)

$Lines = [System.Collections.Generic.List[string]]::new()
$Lines.Add('# Hinweise zu Drittanbieter-Komponenten')
$Lines.Add('')
$Lines.Add('Erzeugt von `Tools/Update-ThirdPartyNotices.ps1`; nicht von Hand ändern.')
$Lines.Add('')
$Lines.Add('Atlas selbst steht unter der MIT-Lizenz (`LICENSE`). Es enthält keine Quelltexte von Embarcadero;')
$Lines.Add('RTL- und VCL-Quellen werden nur lokal aus der Delphi-Installation gelesen und nie weitergegeben.')
$Lines.Add('')
$Lines.Add('## In Releases enthalten')
$Lines.Add('')
$Lines.Add('### WebView2Loader.dll (Microsoft Edge WebView2)')
$Lines.Add('')
$Lines.Add('- Zweck: eingebetteter Browser im Reiter „Bericht“ von AtlasMonitor.exe (#1900)')
$Lines.Add('- Quelle: Ordner `Redist` von RAD Studio (weitergebbare Datei), ursprünglich aus dem WebView2-SDK von Microsoft')
$Lines.Add('- Lizenz: https://www.nuget.org/packages/Microsoft.Web.WebView2 (Lizenz des SDK)')
$Lines.Add('')
$Lines.Add('## Nur für den Linux-Server (nicht in Releases enthalten)')
$Lines.Add('')
$Lines.Add('Der Linux-Server (`Tools/Linux/Build-AtlasServer.sh`) und der FPC-Testlauf (`Tools/Linux/Test-Fpc.sh`) werden mit')
$Lines.Add('Free Pascal übersetzt. Das Ergebnis liegt im Vorab-Release `cloud-linux` und ist für Cloud-Sitzungen gedacht,')
$Lines.Add('nicht für Anwender.')
$Lines.Add('')
$Lines.Add('### Free Pascal (RTL, FCL, Paket vcl-compat)')
$Lines.Add('')
$Lines.Add('- Zweck: Compiler und Laufzeitbibliotheken des Linux-Servers; in die ausführbare Datei gelinkt')
$Lines.Add("- Quelle: https://gitlab.com/freepascal.org/fpc/source, Stand ``$FpcCommit`` (``FPC_COMMIT`` in ``Tools/Linux/Build-AtlasServer.sh``)")
$Lines.Add('- Lizenz: LGPL-2.1 mit der Ausnahme für statisches Linken von Free Pascal (`COPYING.FPC` im FPC-Quelltext)')
$Lines.Add('- Im Repository liegen Kopien einzelner Units aus vcl-compat, teils geändert; was geändert ist und warum, steht im')
$Lines.Add('  `LIESMICH.md` des jeweiligen Ordners:')
foreach ($Copy in $Copies) { $Lines.Add("  - ``$Copy``") }
$Lines.Add('')
$Lines.Add('### PCRE2 (libpcre2-16)')
$Lines.Add('')
$Lines.Add('- Zweck: reguläre Ausdrücke der Regex-Units von vcl-compat; zur Laufzeit aus dem System geladen, nicht mitgeliefert')
$Lines.Add('- Quelle: https://github.com/PCRE2Project/pcre2 (Paket `libpcre2-16-0` der Distribution)')
$Lines.Add('- Lizenz: BSD-3-Clause WITH PCRE2-exception')
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
