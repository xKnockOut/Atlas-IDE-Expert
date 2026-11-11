<#
.SYNOPSIS
    Prüft die Modulgrenzen in Check-PackageDependencies.ps1 mit absichtlichen
    Verstößen (#1455).

.DESCRIPTION
    Legt eine Kopie von Packages, Application, atlas.json, Tests-Programm und
    ADR-Doku in einem temporären Ordner an. Der unveränderte Stand muss die
    Prüfung bestehen. Danach baut jeder Fall einen Verstoß ein (neue Unit mit
    verbotenem uses, fehlende oder veraltete Zeile der Zuordnung, Abweichung
    ohne Begründung, behobener bekannter Verstoß) und erwartet, dass das
    Skript scheitert und den Verstoß nennt. Erlaubte Verweise (Modul -> Base,
    auch auf die Verträge in Base) müssen bestehen. Nach jedem Fall wird die Kopie
    zurückgesetzt.

.EXAMPLE
    pwsh Tools/Test-PackageDependencies.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script = Join-Path $PSScriptRoot 'Check-PackageDependencies.ps1'
$Assignment = 'docs/adr/0017-unit-zuordnung.md'
$Source = 'Packages/Atlas.IDE.Base/Source'
$Failures = [System.Collections.Generic.List[string]]::new()
$Touched = @{}

$CopyRoot = Join-Path ([IO.Path]::GetTempPath()) ('atlas-modules-' + [Guid]::NewGuid().ToString('N'))
foreach ($Item in 'Packages', 'Application', 'Tests/Atlas.Tests.dpr', 'Tests/Data/Architecture', $Assignment, 'atlas.json') {
    $From = Join-Path $Root $Item
    if (-not (Test-Path $From)) { continue }
    $To = Join-Path $CopyRoot $Item
    New-Item -ItemType Directory -Force (Split-Path -Parent $To) | Out-Null
    Copy-Item -Recurse $From $To
}

function Set-CopyText([string] $Relative, [string] $Text) {
    # Schreibt eine Datei der Kopie und merkt sich den alten Stand für Reset-Copy.
    $Path = Join-Path $CopyRoot $Relative
    if (-not $Touched.ContainsKey($Path)) {
        $Old = $null
        if (Test-Path $Path) { $Old = [IO.File]::ReadAllText($Path) }
        $Touched[$Path] = $Old
    }
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($true))
}

function Reset-Copy {
    foreach ($Path in @($Touched.Keys)) {
        if ($null -eq $Touched[$Path]) { Remove-Item -Force $Path }
        else { [IO.File]::WriteAllText($Path, $Touched[$Path], [Text.UTF8Encoding]::new($false)) }
    }
    $Touched.Clear()
}

function Add-Unit([string] $Folder, [string] $Name, [string[]] $Uses) {
    Add-UnitIn $Source $Folder $Name $Uses
}

function Add-UnitIn([string] $Base, [string] $Folder, [string] $Name, [string[]] $Uses) {
    # Neue Unit unter <Base>/<Folder> mit den angegebenen uses-Einträgen.
    $Clause = ''
    if ($Uses.Count -gt 0) { $Clause = "uses`r`n  " + ($Uses -join ",`r`n  ") + ";`r`n`r`n" }
    Set-CopyText "$Base/$Folder/$Name.pas" "unit $Name;`r`n`r`ninterface`r`n`r`n${Clause}implementation`r`n`r`nend.`r`n"
}

function Add-TableRow([string] $Heading, [string] $Row) {
    # Fügt eine Zeile direkt unter der Trennzeile der ersten Tabelle nach der Überschrift ein.
    $Path = Join-Path $CopyRoot $Assignment
    $Lines = [Collections.Generic.List[string]]::new([IO.File]::ReadAllLines($Path))
    $Start = $Lines.IndexOf($Heading)
    if ($Start -lt 0) { throw "Überschrift fehlt in ${Assignment}: $Heading" }
    $Index = $Start + 1
    while ($Index -lt $Lines.Count -and $Lines[$Index] -notmatch '^\|\s*-') { $Index++ }
    $Lines.Insert($Index + 1, $Row)
    Set-CopyText $Assignment (($Lines -join "`n") + "`n")
}

function Add-Assigned([string] $Package, [string] $Folder, [string] $Name, [string[]] $Uses) {
    # Ein Modul mit eigenem Package-Ordner (#1456) hat seine Quellen dort, sonst liegen sie noch im Kern.
    $Base = $Source
    if (Test-Path (Join-Path $CopyRoot "Packages/$Package/Source")) { $Base = "Packages/$Package/Source" }
    Add-UnitIn $Base $Folder $Name $Uses
    Add-TableRow "## $Package" "| ``$Name`` | ``$Folder/$Name.pas`` | Probe für Test-PackageDependencies |"
}

function Invoke-Check {
    $Output = & pwsh -NoProfile -File $Script -Root $CopyRoot 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $Output }
}

function Test-Fails([string] $Name, [string] $Expected, [scriptblock] $Break) {
    try {
        & $Break
        $Result = Invoke-Check
        if ($Result.Code -eq 0) { $Failures.Add("${Name}: Prüfung bestand trotz Verstoß") }
        elseif ($Result.Output -notlike "*$Expected*") { $Failures.Add("${Name}: erwartet [$Expected], erhalten:`n$($Result.Output)") }
        else { Write-Host "ok: $Name" }
    }
    finally { Reset-Copy }
}

function Test-Passes([string] $Name, [scriptblock] $Change) {
    try {
        & $Change
        $Result = Invoke-Check
        if ($Result.Code -ne 0) { $Failures.Add("${Name}: Prüfung schlug fehl:`n$($Result.Output)") }
        else { Write-Host "ok: $Name" }
    }
    finally { Reset-Copy }
}

try {
    Test-Passes 'Unveränderter Stand' {}

    Test-Passes 'Modul verwendet Base und einen Vertrag aus Base' {
        Add-Assigned 'Atlas.IDE.Debugger' 'IDE/Debug' 'Atlas.IDE.Debug.Probe' @('Atlas.Core.Projects.VersionControl', 'Atlas.IDE.Contracts.Rules')
    }

    Test-Fails 'Base verwendet ein Modul' 'Base verwendet kein Modul (Atlas.IDE.Tracker)' {
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.Probe' @('Atlas.Core.Tracker.Contract')
    }

    Test-Passes 'Base verwendet einen eigenen Vertrag' {
        Add-Assigned 'Atlas.IDE.Base' 'IDE/Settings' 'Atlas.IDE.Settings.Probe' @('Atlas.IDE.Contracts.Rules')
    }

    Test-Fails 'Modul verwendet ein anderes Modul' 'Modul Atlas.IDE.Debugger verwendet kein anderes Modul (Atlas.IDE.Tracker)' {
        Add-Assigned 'Atlas.IDE.Debugger' 'Core/Debug' 'Atlas.Core.Debug.Probe' @('Atlas.Core.Tracker.Contract')
    }

    Test-Fails 'Ausnahme der Kompositionswurzel gilt nur für sie' 'Base verwendet kein Modul (Atlas.IDE.Welcome)' {
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.Probe' @('Atlas.Core.Welcome.Sections')
    }

    Test-Fails 'Unit fehlt in der Zuordnung' 'Atlas.Core.Projects.Probe (Core/Projects/Atlas.Core.Projects.Probe.pas) fehlt in der Zuordnung' {
        Add-Unit 'Core/Projects' 'Atlas.Core.Projects.Probe' @()
    }

    Test-Fails 'Zeile ohne Unit' 'Atlas.Core.Projects.Gone gibt es nicht mehr' {
        Add-TableRow '## Atlas.IDE.Base' '| `Atlas.Core.Projects.Gone` | `Core/Projects/Atlas.Core.Projects.Gone.pas` | Ordner `Core/Projects` |'
    }

    Test-Fails 'Abweichung von der Ordnertabelle ohne Begründung' 'die Ordnertabelle sagt Atlas.IDE.Base' {
        Add-Unit 'Core/Projects' 'Atlas.Core.Projects.Probe' @()
        Add-TableRow '## Atlas.IDE.Tracker' '| `Atlas.Core.Projects.Probe` | `Core/Projects/Atlas.Core.Projects.Probe.pas` | Ordner `Core/Projects` |'
    }

    Test-Fails 'Behobener bekannter Verstoß bleibt stehen' 'Atlas.Core.Projects.VersionControl -> Atlas.IDE.Tracker kommt nicht mehr vor' {
        Add-TableRow '### Bekannte Verstöße' '| `Atlas.Core.Projects.VersionControl` | `Atlas.IDE.Tracker` | Probe |'
    }
}
finally {
    Remove-Item -Recurse -Force $CopyRoot
}

if ($Failures.Count -gt 0) {
    Write-Host 'Modulgrenzen: Selbsttest fehlgeschlagen:' -ForegroundColor Red
    $Failures | ForEach-Object { Write-Host "  $_" }
    exit 1
}
Write-Host 'Modulgrenzen: alle Fälle wie erwartet.' -ForegroundColor Green
exit 0
