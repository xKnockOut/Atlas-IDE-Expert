<#
.SYNOPSIS
    Prüft die Modulgrenzen in Check-PackageDependencies.ps1 mit absichtlichen
    Verstößen (#1455).

.DESCRIPTION
    Legt eine Kopie von Packages, Application, atlas.json, Tests-Programm und
    Zuordnung (Tools/UnitAssignment*.tsv) in einem temporären Ordner an. Der unveränderte Stand muss die
    Prüfung bestehen. Danach baut jeder Fall einen Verstoß ein (neue Unit mit
    verbotenem uses, fehlende oder veraltete Zeile der Zuordnung, Abweichung
    ohne Begründung, unsortierte Zeile, behobener bekannter Verstoß) und erwartet, dass das
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
$Assignment = 'Tools/UnitAssignment.tsv'
$Boundaries = 'Tools/UnitAssignment.Boundaries.tsv'
$Source = 'Packages/Atlas.IDE.Base/Source'
$Failures = [System.Collections.Generic.List[string]]::new()
$Touched = @{}

$CopyRoot = Join-Path ([IO.Path]::GetTempPath()) ('atlas-modules-' + [Guid]::NewGuid().ToString('N'))
foreach ($Item in 'Packages', 'Application', 'Tests/Atlas.Tests.dpr', 'Tests/Data/Architecture', 'Tools/AdapterRoles.known.txt', $Assignment, 'Tools/UnitAssignment.Folders.tsv', $Boundaries, 'atlas.json') {
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

function Add-AssignmentRow([string] $Package, [string] $Name, [string] $File, [string] $Reason, [switch] $Unsorted) {
    # Fügt eine Zeile der Zuordnung an ihrer sortierten Stelle ein (nach Package und Unit), mit -Unsorted ans Ende.
    $Path = Join-Path $CopyRoot $Assignment
    $Lines = [Collections.Generic.List[string]]::new([IO.File]::ReadAllLines($Path))
    $Key = "$Package`t$Name"
    $Index = $Lines.Count
    if (-not $Unsorted) {
        $Index = 1
        while ($Index -lt $Lines.Count -and
            [StringComparer]::OrdinalIgnoreCase.Compare(($Lines[$Index].Split("`t")[0..1] -join "`t"), $Key) -lt 0) { $Index++ }
    }
    $Lines.Insert($Index, "$Package`t$Name`t$File`t$Reason")
    Set-CopyText $Assignment (($Lines -join "`n") + "`n")
}

function Add-BoundaryRow([string] $Kind, [string] $From, [string] $To, [string] $Reason) {
    $Text = [IO.File]::ReadAllText((Join-Path $CopyRoot $Boundaries))
    Set-CopyText $Boundaries ($Text + "$Kind`t$From`t$To`t$Reason`n")
}

function Add-Assigned([string] $Package, [string] $Folder, [string] $Name, [string[]] $Uses) {
    # Ein Modul mit eigenem Package-Ordner (#1456) hat seine Quellen dort, sonst liegen sie noch im Kern.
    $Base = $Source
    if (Test-Path (Join-Path $CopyRoot "Packages/$Package/Source")) { $Base = "Packages/$Package/Source" }
    Add-UnitIn $Base $Folder $Name $Uses
    Add-AssignmentRow $Package $Name "$Folder/$Name.pas" 'Probe für Test-PackageDependencies'
}

function Add-Implementer([string] $Package, [string] $Folder, [string] $Name, [string] $Uses, [string] $Interface) {
    # Unit mit einer Klasse, die $Interface aus der Unit $Uses implementiert (Rollen Adapters und Providers, #1443).
    Add-Assigned $Package $Folder $Name @()
    $Base = $Source
    if (Test-Path (Join-Path $CopyRoot "Packages/$Package/Source")) { $Base = "Packages/$Package/Source" }
    Set-CopyText "$Base/$Folder/$Name.pas" ("unit $Name;`r`n`r`ninterface`r`n`r`nuses`r`n  $Uses;`r`n`r`ntype`r`n" +
        "  TProbe = class(TInterfacedObject, $Interface)`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n")
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
        Add-AssignmentRow 'Atlas.IDE.Base' 'Atlas.Core.Projects.Gone' 'Core/Projects/Atlas.Core.Projects.Gone.pas' 'Ordner `Core/Projects`'
    }

    Test-Fails 'Abweichung von der Ordnertabelle ohne Begründung' 'die Ordnertabelle sagt Atlas.IDE.Base' {
        Add-Unit 'Core/Projects' 'Atlas.Core.Projects.Probe' @()
        Add-AssignmentRow 'Atlas.IDE.Tracker' 'Atlas.Core.Projects.Probe' 'Core/Projects/Atlas.Core.Projects.Probe.pas' 'Ordner `Core/Projects`'
    }

    Test-Fails 'Unsortierte Zeile der Zuordnung' 'Atlas.Core.Projects.Probe steht nicht sortiert' {
        Add-Unit 'Core/Projects' 'Atlas.Core.Projects.Probe' @()
        Add-AssignmentRow 'Atlas.IDE.Base' 'Atlas.Core.Projects.Probe' 'Core/Projects/Atlas.Core.Projects.Probe.pas' 'Ordner `Core/Projects`' -Unsorted
    }

    Test-Fails 'Zeile mit fehlender Spalte' 'erwartet 4 Spalten' {
        $Text = [IO.File]::ReadAllText((Join-Path $CopyRoot $Assignment))
        Set-CopyText $Assignment ($Text + "Atlas.IDE.Base`tAtlas.Core.Projects.Probe`n")
    }

    Test-Fails 'JSON-Lesehelfer als lokale Kopie' 'TextOf – JSON-Lesehelfer gibt es als TJsonRead' {
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.Probe' @()
        Set-CopyText "$Source/Core/Projects/Atlas.Core.Projects.Probe.pas" ("unit Atlas.Core.Projects.Probe;`r`n`r`ninterface`r`n`r`n" +
            "implementation`r`n`r`nuses`r`n  System.JSON;`r`n`r`n" +
            "function TextOf(AObject: TJSONObject; const AName: string): string;`r`nbegin`r`n  Result := '';`r`nend;`r`n`r`nend.`r`n")
    }

    Test-Fails 'Behobener bekannter Verstoß bleibt stehen' 'Atlas.Core.Projects.VersionControl -> Atlas.IDE.Tracker kommt nicht mehr vor' {
        Add-BoundaryRow 'Verstoß' 'Atlas.Core.Projects.VersionControl' 'Atlas.IDE.Tracker' 'Probe'
    }
    Test-Passes 'Adapter implementiert einen fremden Contract' {
        Add-Implementer 'Atlas.IDE.Base' 'IDE/Undo' 'Atlas.IDE.Undo.Adapters.Probe' 'Atlas.Core.Undo.Contract' 'IAtlasUndoTarget'
    }

    Test-Passes 'Provider implementiert den eigenen Contract' {
        Add-Implementer 'Atlas.IDE.Base' 'Core/Undo' 'Atlas.Core.Undo.Providers.Probe' 'Atlas.Core.Undo.Contract' 'IAtlasUndoTarget'
    }

    Test-Fails 'Adapter implementiert den eigenen Contract' 'eigener Contract, das ist die Rolle Providers' {
        Add-Implementer 'Atlas.IDE.Base' 'Core/Undo' 'Atlas.Core.Undo.Adapters.Probe' 'Atlas.Core.Undo.Contract' 'IAtlasUndoTarget'
    }

    Test-Fails 'Provider implementiert einen fremden Contract' 'fremdes Feature, das ist die Rolle Adapters' {
        Add-Implementer 'Atlas.IDE.Base' 'Core/Files' 'Atlas.Core.Files.Providers.Probe' 'Atlas.Core.Undo.Contract' 'IAtlasUndoTarget'
    }

    Test-Fails 'Unit ohne Rolle implementiert einen fremden Contract' 'gehört in eine Unit Atlas.IDE.Undo.Adapters.*' {
        Add-Implementer 'Atlas.IDE.Base' 'IDE/Undo' 'Atlas.IDE.Undo.Probe' 'Atlas.Core.Undo.Contract' 'IAtlasUndoTarget'
    }

    Test-Fails 'Unit ohne Rolle implementiert einen fremden Contract über einen Alias' 'gehört in eine Unit Atlas.IDE.Undo.Adapters.*' {
        Add-Assigned 'Atlas.IDE.Base' 'IDE/Undo' 'Atlas.IDE.Undo.Probe' @()
        Set-CopyText "$Source/IDE/Undo/Atlas.IDE.Undo.Probe.pas" ("unit Atlas.IDE.Undo.Probe;`r`n`r`ninterface`r`n`r`n" +
            "uses`r`n  Atlas.Core.Undo.Contract;`r`n`r`ntype`r`n  IAtlasUndoProbe = IAtlasUndoTarget;`r`n`r`n" +
            "  TProbe = class(TInterfacedObject, IAtlasUndoProbe)`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n")
    }

    Test-Fails 'Fremd implementiertes Interface liegt nicht im Contract' 'gehört in den Contract von Atlas.Core.Projects' {
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.ProbeSpi' @()
        Set-CopyText "$Source/Core/Projects/Atlas.Core.Projects.ProbeSpi.pas" ("unit Atlas.Core.Projects.ProbeSpi;`r`n`r`ninterface`r`n`r`n" +
            "type`r`n  IAtlasProbeSpi = interface`r`n  end;`r`n`r`nimplementation`r`n`r`nend.`r`n")
        Add-Implementer 'Atlas.IDE.Base' 'IDE/Undo' 'Atlas.IDE.Undo.Adapters.Probe' 'Atlas.Core.Projects.ProbeSpi' 'IAtlasProbeSpi'
    }

    Test-Fails 'Adapter ohne Interface' 'Adapters ohne Interface aus einem fremden Contract' {
        Add-Assigned 'Atlas.IDE.Base' 'IDE/Undo' 'Atlas.IDE.Undo.Adapters.Probe' @()
    }

    Test-Fails 'Contract bindet ein Framework ein' 'ein Contract bindet kein Framework ein' {
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.Probe.Contract' @('Vcl.Controls')
    }

    Test-Fails 'Vertrag der UI-Schicht verwendet VCL ohne Einzelausnahme' 'ein Contract bindet kein Framework ein' {
        Add-Assigned 'Atlas.IDE.Base' 'UI/Settings' 'Atlas.UI.Settings.Probe.Contract' @('Vcl.Controls')
    }

    Test-Fails 'Genehmigte Ausnahme gibt keine Internals frei' 'Rollenmatrix: fremde Internals aus Composition' {
        Add-Assigned 'Atlas.IDE.Tracker' 'IDE/Tracker' 'Atlas.IDE.Tracker.Composition.Probe' @()
        Add-Assigned 'Atlas.IDE.Base' 'Core/Projects' 'Atlas.Core.Projects.Internals.Probe' @()
        $Json = [IO.File]::ReadAllText((Join-Path $CopyRoot 'atlas.json'))
        Set-CopyText 'atlas.json' ($Json.Replace('"Atlas.IDE.Tracker.Composition -> Atlas.Core.*.Providers.*"',
            '"Atlas.IDE.Tracker.Composition -> Atlas.Core.*.Providers.*", "Atlas.IDE.Tracker.Composition.Probe -> Atlas.Core.*"'))
        $Base = 'Packages/Atlas.IDE.Tracker/Source/IDE/Tracker'
        Set-CopyText "$Base/Atlas.IDE.Tracker.Composition.Probe.pas" ("unit Atlas.IDE.Tracker.Composition.Probe;`r`n`r`n" +
            "interface`r`n`r`nuses`r`n  Atlas.Core.Projects.Internals.Probe;`r`n`r`nimplementation`r`n`r`nend.`r`n")
    }

    Test-Fails 'Behobener Altfall der Adapter-Rollen bleibt stehen' 'adapter-name Atlas.IDE.Undo.Gone TGone IAtlasUndoTarget kommt nicht mehr vor' {
        $Known = [IO.File]::ReadAllText((Join-Path $CopyRoot 'Tools/AdapterRoles.known.txt'))
        Set-CopyText 'Tools/AdapterRoles.known.txt' ($Known + "adapter-name Atlas.IDE.Undo.Gone TGone IAtlasUndoTarget`r`n")
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
