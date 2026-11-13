<#
.SYNOPSIS
    Prüft, dass die Vertragsversion von Base höchstens einmal je Release steigt.

.DESCRIPTION
    cAtlasCoreContractVersion (Atlas.Core.Modules.Contract) schützt Module vor einem Base aus einem anderen
    Stand (Modulregel 7). Base und Module werden immer gemeinsam gebaut und ausgeliefert; eine neue Nummer je
    Release genügt deshalb. Erhöhte dagegen jeder Pull Request, der einen Vertrag ändert, um eins, änderten
    parallele Pull Requests dieselbe Zeile verschieden, und jeder Merge erzeugte einen Konflikt.

    Verglichen wird mit dem neuesten Release-Tag (v*):
    - Hat sich unter Packages/Atlas.IDE.Base/Source seit dem Tag etwas geändert, muss die Version größer als
      im Tag sein. Sonst ist sie auf Tag + 1 zu setzen.
    - Mit -Base <Ref> (Ziel des Pull Requests): Steht die Version im Ziel schon über der des Tags, darf der
      Pull Request sie nicht ändern. Steht sie noch auf der des Tags, darf er sie nur auf Tag + 1 setzen.
      Parallele Pull Requests ändern die Zeile so gleich oder gar nicht, und Git führt sie ohne Konflikt
      zusammen.

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

$RelPath = 'Packages/Atlas.IDE.Base/Source/Core/Modules/Atlas.Core.Modules.Contract.pas'
$Pattern = 'cAtlasCoreContractVersion\s*=\s*(\d+)\s*;'

function Get-ContractVersion([string] $Text, [string] $Where) {
    $Match = [regex]::Match($Text, $Pattern)
    if (-not $Match.Success) { throw "cAtlasCoreContractVersion nicht gefunden ($Where)" }
    return [int]$Match.Groups[1].Value
}

function Get-VersionAt([string] $Ref) {
    $Text = (& git -C $Root show "${Ref}:$RelPath" 2>$null) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "$RelPath im Stand $Ref nicht lesbar" }
    return Get-ContractVersion $Text $Ref
}

$Tag = @(& git -C $Root tag --list 'v[0-9]*' --sort=-version:refname) | Select-Object -First 1
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

if ($Base) {
    $Target = Get-VersionAt $Base
    if ($Head -ne $Target) {
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
