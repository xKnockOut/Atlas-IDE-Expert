<#
.SYNOPSIS
    Prüft, ob die Packages ihre erlaubten Abhängigkeiten einhalten.

.DESCRIPTION
    - Atlas.Text    : nur RTL, ohne andere Atlas-Artefakte; gemeinsamer Code
        für Server und Plugin (ADR 0012)
    - Atlas.Common  : frei von Windows und VCL (nur plattformunabhängige RTL,
        Atlas.Text)
    - Atlas.Windows : frei von VCL (RTL, Winapi.*, System.Win.*, Atlas.Common)
    - Atlas.IDE.Expert: eigenständig; darin Schichten (#406):
        Atlas.Core.* ohne VCL, Open Tools API, Atlas.UI.* und Atlas.IDE.*
        Atlas.UI.*   ohne Open Tools API und Atlas.IDE.*
    - Setup (Installer, #495): ohne Atlas.Common und Atlas.Windows; darin
        Setup.Core.* frei von Windows, VCL, Setup.Adapters und Setup.Shell
    - Atlas.Core.Vcs.* (Versionsverwaltung, #571): übersetzt auch der Server
        mit; darum nur RTL, Winapi und eigene Atlas.Core.Vcs.*-Units

    Atlas.Text im Plugin (ADR 0012): Das Plugin requiret Atlas.Text nicht,
    sondern übersetzt dessen Units selbst mit (contains … in
    '..\Atlas.Text\Source\…'). Geprüft wird, dass
      - das Plugin außer eigenen Units (Source\…) nur Atlas.Text-Units enthält,
      - es genau die Units aus Atlas.Text.dpk enthält (sonst W1033),
      - Atlas.Tests.dpr und AtlasServer.dpr keine Atlas.Text-Quellen einbinden
        (sie linken die DCUs aus Dcu\Atlas.Text; zwei Fassungen vermeiden).

    Kopien-Sperre (D-03): Außerhalb von Packages/Atlas.Text darf im
    implementation-Teil keine Routine wie LineBreakOf, SplitLines, IndentOf,
    IsWordChar, IsIdentChar, IsUtf8, PercentDecode usw. neu entstehen. Erlaubt
    sind nur die Fassaden und Sonderfälle in $AllowedLocal, jeweils mit Grund.

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
        # ADR 0012: wird auch als Quelltext ins Plugin übersetzt, darum nur RTL.
        Name             = 'Atlas.Text'
        Path             = 'Packages/Atlas.Text'
        AllowedRequires  = @('rtl')
        ForbiddenPrefix  = @('Winapi.', 'System.Win.', 'Vcl.', 'FMX.', 'Atlas.Common', 'Atlas.Windows',
                             'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.', 'Setup.')
        ForbiddenUnits   = $LegacyVclUnits + $LegacyWindowsUnits
        Reason           = 'nur RTL; wird auch ins Plugin übersetzt (ADR 0012)'
    },
    @{
        Name             = 'Atlas.Common'
        Path             = 'Packages/Atlas.Common'
        AllowedRequires  = @('rtl', 'Atlas.Text')
        ForbiddenPrefix  = @('Winapi.', 'System.Win.', 'Vcl.', 'FMX.', 'Atlas.Windows')
        ForbiddenUnits   = $LegacyVclUnits + $LegacyWindowsUnits
        Reason           = 'frei von Windows und VCL'
    },
    @{
        Name             = 'Atlas.Windows'
        Path             = 'Packages/Atlas.Windows'
        AllowedRequires  = @('rtl', 'Atlas.Common', 'Atlas.Text')
        ForbiddenPrefix  = @('Vcl.', 'FMX.')
        ForbiddenUnits   = $LegacyVclUnits
        Reason           = 'frei von VCL'
    },
    @{
        # ADR 0012: eigenständig, damit die IDE nur ein BPL laden muss; Atlas.Text kommt als Quelltext
        # hinein (contains), nicht über requires. vclwinx (TImageCollection,
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

# Kopien-Sperre (D-03, ADR 0012): Namen, die nur Atlas.Text definieren soll.
$CopyLockNames = @('LineBreakOf', 'LineBreakIn', 'DetectLineBreak', 'SplitLines', 'StripCr', 'IndentOf', 'IsWordChar',
    'IsIdentChar', 'IsIdentStart', 'DecodeEntities', 'PercentDecode', 'PercentEncode', 'IsUtf8', 'CheckUtf8', 'HasPrefix')

# Erlaubte lokale Definitionen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedLocal = @{
    'Atlas.Common.Documents.FileEncoding:TFileEncoding.DetectLineBreak' = 'Fassade mit eigenem Typ TLineBreakStyle, leitet an TTextLines.DominantOf weiter'
    'Atlas.Common.Lsp.Documentation:TLspDocumentation.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Common.Editing.DataFieldNames:IsWordChar'                    = 'SQL-Bezeichner mit $, @ und #, keine Pascal-Regel'
    'Atlas.Common.Rules.Builtin.Unused:IsWordChar'                      = 'verschachtelt mit Index; folgt mit Block Rules'
    'Atlas.Core.InlayHints.Store:TAtlasInlayHintStore.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Core.Files.Format:TAtlasFileFormats.IsUtf8'                 = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Core.Files.Format:TAtlasFileFormats.LineBreakOf'            = 'Fassade mit eigenem Typ TAtlasLineBreak'
    'Atlas.Core.Files.TextFile:TAtlasTextFile.IsUtf8'                  = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Core.Undo.LinePatch:TAtlasLinePatch.SplitLines'             = 'öffentliche Weiterleitung an TTextLines.SplitKeepingBreaks'
    'Atlas.Core.Completion.Snippets:TAtlasSnippets.IndentOf'           = 'öffentliche Weiterleitung an TTextLines.IndentOf'
}

function Get-ContainsEntries([string] $Text) {
    # Einträge der contains-Klausel als Name und Pfad (ohne Pfad: '').
    $result = @()
    foreach ($clause in [regex]::Matches($Text, '(?is)\bcontains\b(.*?);')) {
        foreach ($entry in [regex]::Matches($clause.Groups[1].Value, "(?is)([A-Za-z_][A-Za-z0-9_.]*)(?:\s+in\s+'([^']*)')?")) {
            $result += [pscustomobject]@{ Name = $entry.Groups[1].Value; Path = $entry.Groups[2].Value }
        }
    }
    return $result
}

function Get-UsesInEntries([string] $Text) {
    # "Name in 'Pfad'" aus der uses-Klausel eines Programms (.dpr).
    $result = @()
    foreach ($entry in [regex]::Matches($Text, "(?is)([A-Za-z_][A-Za-z0-9_.]*)\s+in\s+'([^']*)'")) {
        $result += [pscustomobject]@{ Name = $entry.Groups[1].Value; Path = $entry.Groups[2].Value }
    }
    return $result
}

function Remove-PascalCommentsOnly([string] $Text) {
    # Wie Remove-PascalNoise, aber Strings bleiben (die in-Pfade stehen in Anführungszeichen).
    $pattern = '(?s)\{.*?\}|\(\*.*?\*\)|//[^\r\n]*'
    return [regex]::Replace($Text, $pattern, {
        param($m) [regex]::Replace($m.Value, '[^\r\n]', ' ')
    })
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
            # Geteilte Units (#571): nur Atlas.Core.Vcs.* aus dem eigenen Feature.
            if ($ownUnit.StartsWith('Atlas.Core.Vcs.', [StringComparison]::OrdinalIgnoreCase) -and
                $unit.Name.StartsWith('Atlas.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.Core.Vcs.', [StringComparison]::OrdinalIgnoreCase)) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.Core.Vcs.* übersetzt auch der Server mit und darf nur Atlas.Core.Vcs.* verwenden"
            }
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

# Atlas.Text im Plugin (ADR 0012)
$textDpk = Join-Path $Root 'Packages/Atlas.Text/Atlas.Text.dpk'
$pluginDpk = Join-Path $Root 'Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk'
if ((Test-Path $textDpk) -and (Test-Path $pluginDpk)) {
    $textUnits = @(Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($textDpk))) | ForEach-Object { $_.Name })
    $pluginEntries = @(Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($pluginDpk))))
    foreach ($entry in $pluginEntries) {
        $path = $entry.Path -replace '/', '\'
        if ($path -ne '' -and -not $path.StartsWith('Source\') -and -not $path.StartsWith('..\Atlas.Text\Source\')) {
            $violations += "Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk: contains $($entry.Name) in '$($entry.Path)' – das Plugin bindet fremde Units nur aus Atlas.Text ein (ADR 0012)"
        }
        if ($path.StartsWith('..\Atlas.Text\') -and -not $entry.Name.StartsWith('Atlas.Text.')) {
            $violations += "Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk: contains $($entry.Name) – unter Atlas.Text nur Atlas.Text.*-Units"
        }
    }
    $pluginTextUnits = @($pluginEntries | Where-Object { $_.Name.StartsWith('Atlas.Text.') } | ForEach-Object { $_.Name })
    foreach ($name in $textUnits | Where-Object { $pluginTextUnits -notcontains $_ }) {
        $violations += "Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk: $name fehlt unter contains (steht in Atlas.Text.dpk; sonst W1033)"
    }
    foreach ($name in $pluginTextUnits | Where-Object { $textUnits -notcontains $_ }) {
        $violations += "Packages/Atlas.IDE.Expert/Atlas.IDE.Expert.dpk: $name steht nicht in Atlas.Text.dpk"
    }
}
foreach ($program in @('Tests/Atlas.Tests.dpr', 'Application/AtlasServer.dpr')) {
    $programPath = Join-Path $Root $program
    if (-not (Test-Path $programPath)) { continue }
    foreach ($entry in Get-UsesInEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($programPath)))) {
        if (($entry.Path -replace '/', '\') -match '(?i)Atlas\.Text\\Source\\') {
            $violations += "${program}: $($entry.Name) in '$($entry.Path)' – Atlas.Text kommt als DCU aus Dcu\Atlas.Text, nicht als Quelltext (ADR 0012)"
        }
    }
}

# Kopien-Sperre (D-03)
$lockPattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?(?:' + ($CopyLockNames -join '|') + '))\b'
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages') -Recurse -File -Include '*.pas') {
    $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
    if ($relative.StartsWith('Packages/Atlas.Text/')) { continue }
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
    $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
    if (-not $implementation.Success) { continue }
    $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    foreach ($match in [regex]::Matches($text.Substring($implementation.Index), $lockPattern)) {
        $key = "${ownUnit}:$($match.Groups[1].Value)"
        if (-not $AllowedLocal.ContainsKey($key)) {
            $line = ($text.Substring(0, $implementation.Index + $match.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($match.Groups[1].Value) – gibt es in Atlas.Text (Kopien-Sperre, ADR 0012); dort verwenden oder in `$AllowedLocal begründen"
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
