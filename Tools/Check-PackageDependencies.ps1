<#
.SYNOPSIS
    Prüft, ob die Packages ihre erlaubten Abhängigkeiten einhalten.

.DESCRIPTION
    - Atlas.Common  : frei von Windows und VCL (nur plattformunabhängige RTL)
    - Atlas.Windows : frei von VCL (RTL, Winapi.*, System.Win.*, Atlas.Common)
    - Atlas.IDE.Expert: eigenständig; darin Schichten (#406):
        Atlas.Core.* ohne VCL, Open Tools API, Atlas.UI.* und Atlas.IDE.*
        Atlas.UI.*   ohne Open Tools API und Atlas.IDE.*
    - Setup (Installer, #495): ohne Atlas.Common und Atlas.Windows; darin
        Setup.Core.* frei von Windows, VCL, Setup.Adapters und Setup.Shell

    Ausgewertet werden alle uses-Klauseln der .pas-Dateien und die
    requires-Klausel der .dpk-Datei jedes Packages. Kommentare, Strings und
    Compiler-Direktiven werden vorher entfernt.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.EXAMPLE
    pwsh Tools/Check-PackageDependencies.ps1
#>
[CmdletBinding()]
param(
    [string] $Root = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Windows PowerShell 5.1 kennt $PSScriptRoot im param-Block nicht.
if ($Root -eq '') {
    $Root = Split-Path -Parent $PSScriptRoot
}

# Unit-Namen der VCL bzw. FireMonkey ohne Namespace (Altcode ohne Unit-Scope-Namen)
$LegacyVclUnits = @(
    'Forms', 'Controls', 'Graphics', 'Dialogs', 'StdCtrls', 'ExtCtrls', 'ComCtrls', 'Menus',
    'Buttons', 'ImgList', 'Themes', 'Clipbrd', 'ActnList', 'Grids', 'Mask', 'CheckLst',
    'Printers', 'OleCtrls', 'ToolWin', 'DBCtrls', 'DBGrids', 'Tabs', 'FileCtrl', 'GraphUtil'
)

# Windows-spezifische Unit-Namen ohne Namespace
$LegacyWindowsUnits = @(
    'Windows', 'Messages', 'Registry', 'ShellAPI', 'ShlObj', 'ActiveX', 'ComObj', 'ComServ',
    'CommCtrl', 'MMSystem', 'WinSock', 'WinSock2', 'TlHelp32', 'PsAPI', 'UxTheme', 'Dwmapi',
    'WinInet', 'IniFiles'
)

$Packages = @(
    @{
        Name             = 'Atlas.Common'
        Path             = 'Packages/Atlas.Common'
        AllowedRequires  = @('rtl')
        ForbiddenPrefix  = @('Winapi.', 'System.Win.', 'Vcl.', 'FMX.', 'Atlas.Windows')
        ForbiddenUnits   = $LegacyVclUnits + $LegacyWindowsUnits
        Reason           = 'frei von Windows und VCL'
    },
    @{
        Name             = 'Atlas.Windows'
        Path             = 'Packages/Atlas.Windows'
        AllowedRequires  = @('rtl', 'Atlas.Common')
        ForbiddenPrefix  = @('Vcl.', 'FMX.')
        ForbiddenUnits   = $LegacyVclUnits
        Reason           = 'frei von VCL'
    },
    @{
        # ADR 0006: eigenständig, damit die IDE nur ein BPL laden muss. vclwinx (TImageCollection,
        # TVirtualImageList für das Atlas-Symbol, #751) gehört zur IDE und ist immer geladen.
        Name             = 'Atlas.IDE.Expert'
        Path             = 'Packages/Atlas.IDE.Expert'
        AllowedRequires  = @('rtl', 'vcl', 'vclwinx', 'designide')
        ForbiddenPrefix  = @('Atlas.Common', 'Atlas.Windows', 'FMX.')
        ForbiddenUnits   = @()
        Reason           = 'eigenständig ohne Atlas.Common und Atlas.Windows'
    },
    @{
        # Installer (#495, ADR 0009): eigene VCL-Anwendung, teilt mit dem Plugin nur die Versionsangabe.
        Name             = 'AtlasSetup'
        Path             = 'Setup'
        AllowedRequires  = @()
        ForbiddenPrefix  = @('Atlas.Common', 'Atlas.Windows', 'FMX.')
        ForbiddenUnits   = @()
        Reason           = 'ohne Atlas.Common und Atlas.Windows'
    }
)

# Units der Open Tools API und des Designers (designide)
$OpenToolsPrefix = @('ToolsAPI', 'DesignIntf', 'DesignEditors', 'DesignMenus', 'DesignWindows', 'PropInspAPI', 'DockForm')

# Schichten im Plugin (#406): gelten zusätzlich je nach Präfix der Unit selbst.
$Layers = @(
    @{
        UnitPrefix      = 'Atlas.Core.'
        ForbiddenPrefix = @('Vcl.', 'Atlas.UI.', 'Atlas.IDE.') + $OpenToolsPrefix
        ForbiddenUnits  = $LegacyVclUnits
        Reason          = 'frei von VCL, Open Tools API, Atlas.UI und Atlas.IDE'
    },
    @{
        UnitPrefix      = 'Atlas.UI.'
        ForbiddenPrefix = @('Atlas.IDE.') + $OpenToolsPrefix
        ForbiddenUnits  = @()
        Reason          = 'frei von Open Tools API und Atlas.IDE'
    },
    @{
        # Kern des Installers: nur über ISetupSystem, damit er mit einer Attrappe testbar ist.
        UnitPrefix      = 'Setup.Core.'
        ForbiddenPrefix = @('Winapi.', 'System.Win.', 'Vcl.', 'FMX.', 'Setup.Adapters.', 'Setup.Shell.')
        ForbiddenUnits  = $LegacyVclUnits + $LegacyWindowsUnits
        Reason          = 'frei von Windows, VCL, Setup.Adapters und Setup.Shell'
    }
)

function Remove-PascalNoise([string] $Text) {
    # Ersetzt Kommentare, Direktiven und Strings durch Leerzeichen und behält
    # Zeilenumbrüche bei, damit Zeilennummern stimmen.
    $pattern = '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*|''(?:[^'']|'''')*'''
    return [regex]::Replace($Text, $pattern, {
        param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ')
    })
}

function Get-ClauseEntries([string] $Text, [string] $Keyword) {
    # Liefert alle Einträge der Klauseln "uses ...;" bzw. "requires ...;" mit Zeilennummer.
    $result = @()
    foreach ($clause in [regex]::Matches($Text, "(?is)\b$Keyword\b(.*?);")) {
        $offset = $clause.Groups[1].Index
        foreach ($entry in [regex]::Matches($clause.Groups[1].Value, '[A-Za-z_][A-Za-z0-9_.]*(?:\s+in\b)?')) {
            $name = ($entry.Value -replace '\s+in$', '').Trim()
            if ($name -ieq 'in') { continue }
            $line = ($Text.Substring(0, $offset + $entry.Index) -split "`n").Count
            $result += [pscustomobject]@{ Name = $name; Line = $line }
        }
    }
    return $result
}

$violations = @()

foreach ($package in $Packages) {
    $packageDir = Join-Path $Root $package.Path
    if (-not (Test-Path $packageDir)) {
        $violations += "$($package.Path): Package-Verzeichnis fehlt"
        continue
    }

    foreach ($file in Get-ChildItem -Path $packageDir -Recurse -File -Include '*.pas', '*.dpk', '*.inc') {
        # Ohne [IO.Path]::GetRelativePath, damit das Skript auch unter Windows PowerShell 5.1 läuft.
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1)
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $layer = $Layers | Where-Object { $ownUnit.StartsWith($_.UnitPrefix, [StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1

        foreach ($unit in Get-ClauseEntries $text 'uses') {
            $prefixHit = $package.ForbiddenPrefix | Where-Object { $unit.Name.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
            $unitHit = $package.ForbiddenUnits | Where-Object { $unit.Name -ieq $_ }
            if ($prefixHit -or $unitHit) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – $($package.Name) muss $($package.Reason) sein"
            }
            if ($layer) {
                $prefixHit = $layer.ForbiddenPrefix | Where-Object { $unit.Name.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
                $unitHit = $layer.ForbiddenUnits | Where-Object { $unit.Name -ieq $_ }
                if ($prefixHit -or $unitHit) {
                    $violations += "${relative}:$($unit.Line): uses $($unit.Name) – $($layer.UnitPrefix)* muss $($layer.Reason) sein"
                }
            }
        }

        if ($file.Extension -ieq '.dpk') {
            foreach ($required in Get-ClauseEntries $text 'requires') {
                if ($package.AllowedRequires -notcontains $required.Name) {
                    $violations += "${relative}:$($required.Line): requires $($required.Name) – erlaubt sind nur: $($package.AllowedRequires -join ', ')"
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Host "Verstöße gegen die Package-Abhängigkeiten:" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Package-Abhängigkeiten in Ordnung.' -ForegroundColor Green
exit 0
