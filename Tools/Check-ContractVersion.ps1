<#
.SYNOPSIS
    Prüft, dass die Vertragsversion von Base höchstens einmal je Release steigt.

.DESCRIPTION
    cAtlasCoreContractVersion (Atlas.IDE.Base.Foundation.Modules) schützt Module vor einem Base aus einem anderen
    Stand (Modulregel 7). Base und Module werden immer gemeinsam gebaut und ausgeliefert; eine neue Nummer je
    Release genügt deshalb. Erhöhte dagegen jeder Pull Request, der einen Vertrag ändert, um eins, änderten
    parallele Pull Requests dieselbe Zeile verschieden, und jeder Merge erzeugte einen Konflikt.

    Verglichen wird mit dem neuesten Release-Tag (v*), der im Stand enthalten ist (auf einem Wartungszweig wie
    Release/v2.2.4 also v2.2.3, nicht ein jüngeres v2.3.0-rc.1 aus main):
    - Hat sich unter Packages/Atlas.IDE.Base/Source seit dem Tag etwas geändert, muss die Version größer als
      im Tag sein. Sonst ist sie auf Tag + 1 zu setzen.
    - Mit -Base <Ref> (Ziel des Pull Requests): Steht die Version im Ziel schon über der des Tags, darf der
      Pull Request sie nicht ändern. Steht sie noch auf der des Tags, darf er sie nur auf Tag + 1 setzen.
      Parallele Pull Requests ändern die Zeile so gleich oder gar nicht, und Git führt sie ohne Konflikt
      zusammen.
    - Ausnahme: Hat ein Wartungszweig (origin/Release/*) eine höhere Vertragsversion als das Ziel, weil dort
      Base für ein Patch-Release geändert wurde, darf der Pull Request das Ziel auf diese Version heben. Der
      Hauptzweig fällt so nicht hinter den Wartungszweig zurück, und dieselbe Nummer bezeichnet nicht zwei
      verschiedene Stände von Base.

    Braucht die Release-Tags (git fetch --tags) und den Stand des Tags.

.EXAMPLE
    pwsh Tools/Check-ContractVersion.ps1 -Base origin/main-merging
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot),
    [string] $Base = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RelPath = 'Packages/Atlas.IDE.Base/Source/Foundation/Atlas.IDE.Base.Foundation.Modules.pas'
# Frühere Orte der Unit: Release-Tags und Ziel-Branches vor dem Umzug lesen sie dort.
$OlderPaths = @('Packages/Atlas.IDE.Base/Source/Core/Modules/Atlas.Core.Modules.Contract.pas')
$Pattern = 'cAtlasCoreContractVersion\s*=\s*(\d+)\s*;'

function Get-ContractVersion([string] $Text, [string] $Where) {
    $Match = [regex]::Match($Text, $Pattern)
    if (-not $Match.Success) { throw "cAtlasCoreContractVersion nicht gefunden ($Where)" }
    return [int]$Match.Groups[1].Value
}

function Get-VersionAt([string] $Ref) {
    foreach ($path in @($RelPath) + $OlderPaths) {
        $Text = (& git -C $Root show "${Ref}:$path" 2>$null) -join "`n"
        if ($LASTEXITCODE -eq 0) { return Get-ContractVersion $Text $Ref }
    }
    throw "$RelPath im Stand $Ref nicht lesbar (auch nicht unter $($OlderPaths -join ', '))"
}

# versionsort.suffix: Vorabversionen (v2.2.0-rc.2) vor dem Release (v2.2.0) einordnen; ohne die Einstellung sortiert
# Git sie dahinter, und nach dem Release galt weiter der Stand des letzten Vorab-Tags.
$Tag = @(& git -C $Root -c versionsort.suffix=- tag --list 'v[0-9]*' --merged HEAD --sort=-version:refname) | Select-Object -First 1
if (-not $Tag) {
    Write-Host 'FEHLER: kein Release-Tag v* gefunden; git fetch --tags ausführen (in der CI: fetch-depth 0)'
    exit 1
}

$Problems = [System.Collections.Generic.List[string]]::new()
$Head = Get-ContractVersion ([IO.File]::ReadAllText((Join-Path $Root $RelPath))) 'Arbeitskopie'
$Tagged = Get-VersionAt $Tag

& git -C $Root diff --quiet $Tag -- 'Packages/Atlas.IDE.Base/Source'
$BaseChanged = $LASTEXITCODE -ne 0
if ($BaseChanged -and $Head -le $Tagged) {
    $Problems.Add("Base hat sich seit $Tag geändert, die Vertragsversion steht noch auf $Head; auf $($Tagged + 1) setzen")
}

function Get-MaintenanceVersion {
    # Höchste Vertragsversion der Wartungszweige origin/Release/*; 0 ohne. Der Pfad der Unit war dort teils ein
    # anderer, deshalb über den Namen der Konstante im Quelltext von Base.
    $mResult = 0
    $mRefs = @(& git -C $Root for-each-ref --format='%(refname)' 'refs/remotes/origin/Release/')
    foreach ($mRef in $mRefs) {
        $mLines = @(& git -C $Root grep -h -E 'cAtlasCoreContractVersion\s*=\s*[0-9]+\s*;' $mRef -- 'Packages/Atlas.IDE.Base/Source' 2>$null)
        foreach ($mLine in $mLines) {
            $mMatch = [regex]::Match($mLine, $Pattern)
            if ($mMatch.Success -and [int]$mMatch.Groups[1].Value -gt $mResult) { $mResult = [int]$mMatch.Groups[1].Value }
        }
    }
    return $mResult
}

if ($Base) {
    $Target = Get-VersionAt $Base
    $Maintenance = Get-MaintenanceVersion
    if ($Head -ne $Target -and -not ($Head -eq $Maintenance -and $Maintenance -gt $Target)) {
        if ($Target -gt $Tagged) {
            $Problems.Add("Vertragsversion ist seit $Tag schon erhöht ($Target in $Base); nicht ändern (hier $Head)")
        }
        elseif ($Head -ne $Tagged + 1) {
            $Problems.Add("Vertragsversion nur auf $($Tagged + 1) erhöhen (Release $Tag hat $Tagged, hier $Head)")
        }
    }
}

if ($Problems.Count -gt 0) {
    $Problems | ForEach-Object { Write-Host "FEHLER: $_" }
    exit 1
}
Write-Host "Vertragsversion in Ordnung: $Head (Release ${Tag}: $Tagged)."
exit 0
