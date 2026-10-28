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

    Rollenmatrix (Konzept 8.1/8.3, Code-Review A-12): Jede Unit wird nach
    Ausgabeartefakt.Feature.Rolle.Sache eingeordnet; ein uses-Eintrag muss die
    Importregeln aus docs/Architektur.md einhalten. Contract-Units deklarieren
    im interface keine Klassen außer Ausnahmen (Konzept 7.1). Genehmigte
    Ausnahmen stehen als "allow" der Regeln architecture-role-import und
    architecture-contract-content in atlas.json (eine Liste für Skript und
    Linter). Die Matrix muss TArchitectureMatrix in
    Atlas.Common.Rules.Builtin.Architecture entsprechen; beide prüfen die
    Fallliste Tests/Data/Architecture/role-imports.json (-SelfTest).

    Featurerichtung Rules/Editing (Code-Review A-11): Rules darf Editing
    verwenden (Korrekturen nutzen Editing-Helfer), Editing aber nicht Rules.
    Gemeinsame Wertetypen wie TTextEdit liegen in Documents.Contract.

    Plugin-Struktur (Code-Review A-09): Atlas.IDE.Foundation.* verwendet aus
    der IDE-Schicht nur Atlas.IDE.Foundation.*; die Features von Atlas.Core
    und Atlas.IDE bilden keinen Zyklus (ohne Foundation, Kompositionswurzel
    und Verweise auf *.Contract).

    Ausgewertet werden alle uses-Klauseln der .pas-Dateien und die
    requires-Klausel der .dpk-Datei jedes Packages. Kommentare, Strings und
    Compiler-Direktiven werden vorher entfernt.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.PARAMETER SelfTest
    Prüft nur die Rollenmatrix gegen Tests/Data/Architecture/role-imports.json.

.EXAMPLE
    pwsh Tools/Check-PackageDependencies.ps1

.EXAMPLE
    pwsh Tools/Check-PackageDependencies.ps1 -SelfTest
#>
[CmdletBinding()]
param(
    [string] $Root = '',
    [switch] $SelfTest
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
    'Atlas.Core.Tracker.CodeLinks:IsWordChar'                           = 'Issue-Kennungen: Buchstaben ab #128 gehören zum Wort (äATL-1 ist keine Kennung, gegen IsAsciiIdentChar), Satzzeichen ab #128 („, “, –) nicht (gegen IsIdentChar)'
    'Atlas.Common.Rules.Builtin.Unused:IsWordChar'                      = 'verschachtelt mit Index; folgt mit Block Rules'
    'Atlas.Core.InlayHints.Store:TAtlasInlayHintStore.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Core.Files.Format:TAtlasFileFormats.IsUtf8'                 = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Core.Files.Format:TAtlasFileFormats.LineBreakOf'            = 'Fassade mit eigenem Typ TAtlasLineBreak'
    'Atlas.Core.Files.TextFile:TAtlasTextFile.IsUtf8'                  = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Core.Undo.LinePatch:TAtlasLinePatch.SplitLines'             = 'öffentliche Weiterleitung an TTextLines.SplitKeepingBreaks'
    'Atlas.Core.Completion.Snippets:TAtlasSnippets.IndentOf'           = 'öffentliche Weiterleitung an TTextLines.IndentOf'
    'Atlas.Core.Editor.MultiCursor:TAtlasMultiCursor.LineBreakOf'      = 'öffentliche Weiterleitung an TTextLines.LineBreakOf'
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

# Rollenmatrix (Konzept 8.1/8.3). Muss TArchitectureMatrix in Atlas.Common.Rules.Builtin.Architecture
# entsprechen; beide prüfen Tests/Data/Architecture/role-imports.json.
$RolePrefixes = @('Atlas.Text', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core', 'Atlas.UI', 'Atlas.IDE')
$HostRoles    = @('Foundation', 'Core', 'Shell', 'Adapters', 'Platform')
$FeatureRoles = @('Contract', 'Internals', 'Providers', 'Adapters', 'Composition', 'Hosting')
# Eigenes Feature: Rolle der Quelle -> erlaubte Rollen des Ziels
$OwnAllowed = @{
    Contract    = @('Contract')
    Internals   = @('Contract', 'Internals')
    Providers   = @('Contract', 'Internals', 'Root')
    Adapters    = @('Contract', 'Internals', 'Root')
    Root        = @('Contract', 'Internals', 'Root')
    Composition = @('Contract', 'Providers', 'Adapters', 'Root', 'Composition')
    Hosting     = @('Contract', 'Providers', 'Adapters', 'Root', 'Composition', 'Hosting')
}
# Fremdes Feature; alle nicht genannten Rollen: Contract und Root.
# Host (8.1, Annahme bis zur Bestätigung des Konzepts): alles außer Internals.
$ForeignAllowed = @{
    Contract = @('Contract')
    Host     = @('Contract', 'Root', 'Providers', 'Adapters', 'Composition', 'Hosting')
}

function Get-UnitRole([string] $Name, [string[]] $Prefixes, [string[]] $Hosts) {
    # Einordnung nach Konzept 6.3; $null für externe Units (RTL, VCL, Setup, Tests).
    $best = ''
    foreach ($prefix in $Prefixes) {
        if ($Name.StartsWith("$prefix.", [StringComparison]::OrdinalIgnoreCase) -and $prefix.Length -gt $best.Length) {
            $best = $prefix
        }
    }
    if ($best -ne '') {
        $rest = $Name.Substring($best.Length + 1).Split('.')
        $role = 'Root'
        if ($rest.Count -ge 2) {
            $hit = $FeatureRoles | Where-Object { $_ -ieq $rest[1] } | Select-Object -First 1
            if ($hit) { $role = $hit }
        }
        return [pscustomobject]@{ Artefact = $best.ToLowerInvariant(); Feature = $rest[0].ToLowerInvariant(); Role = $role }
    }
    $first = $Name.Split('.')[0]
    $hostRole = $Hosts | Where-Object { $_ -ieq $first } | Select-Object -First 1
    if ($hostRole -and $Name.Contains('.')) {
        return [pscustomobject]@{ Artefact = ''; Feature = $hostRole.ToLowerInvariant(); Role = 'Host' }
    }
    return $null
}

function Test-RoleImport($Source, $Target) {
    if ($null -eq $Source -or $null -eq $Target) { return $true }
    if ($Target.Role -eq 'Host') { return $Source.Role -eq 'Host' }
    if ($Source.Role -ne 'Host' -and $Source.Artefact -eq $Target.Artefact -and $Source.Feature -eq $Target.Feature) {
        return $OwnAllowed[$Source.Role] -contains $Target.Role
    }
    $allowed = @('Contract', 'Root')
    if ($ForeignAllowed.ContainsKey($Source.Role)) { $allowed = $ForeignAllowed[$Source.Role] }
    return $allowed -contains $Target.Role
}

function Get-RoleDescription($Source, $Target) {
    # Kurztext wie TArchitectureMatrix.Describe, z. B. "fremde Adapters aus Root".
    $kind = 'fremde'
    if ($Source.Role -ne 'Host' -and $Source.Artefact -eq $Target.Artefact -and $Source.Feature -eq $Target.Feature) {
        $kind = 'eigene'
    }
    return "$kind $($Target.Role) aus $($Source.Role)"
}

if ($SelfTest) {
    $data = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'Tests/Data/Architecture/role-imports.json') | ConvertFrom-Json
    $failures = @()
    foreach ($case in $data.cases) {
        $actual = Test-RoleImport (Get-UnitRole $case.from $data.prefixes $data.hostRoles) (Get-UnitRole $case.to $data.prefixes $data.hostRoles)
        if ($actual -ne [bool] $case.allowed) {
            $failures += "$($case.from) -> $($case.to): erwartet $($case.allowed), erhalten $actual"
        }
    }
    if ($failures.Count -gt 0) {
        Write-Host 'Rollenmatrix weicht von der Fallliste ab:' -ForegroundColor Red
        $failures | ForEach-Object { Write-Host "  $_" }
        exit 1
    }
    Write-Host "Rollenmatrix: $(@($data.cases).Count) Fälle wie erwartet." -ForegroundColor Green
    exit 0
}

# Genehmigte Ausnahmen aus atlas.json (dieselbe Liste liest der Linter).
$RoleImportAllow = @()
$ContractContentAllow = @()
$atlasJson = Join-Path $Root 'atlas.json'
if (Test-Path $atlasJson) {
    $config = Get-Content -Raw -Encoding UTF8 $atlasJson | ConvertFrom-Json
    if ($config.PSObject.Properties['rules']) {
        $rule = $config.rules.PSObject.Properties['architecture-role-import']
        if ($rule -and $rule.Value.PSObject.Properties['allow']) { $RoleImportAllow = @($rule.Value.allow) }
        $rule = $config.rules.PSObject.Properties['architecture-contract-content']
        if ($rule -and $rule.Value.PSObject.Properties['allow']) { $ContractContentAllow = @($rule.Value.allow) }
    }
}

function Test-RoleApproved([string] $Source, [string] $Target) {
    foreach ($entry in $RoleImportAllow) {
        $parts = $entry -split '->', 2
        if ($parts.Count -eq 2 -and $Source -like $parts[0].Trim() -and $Target -like $parts[1].Trim()) { return $true }
    }
    return $false
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

# Rollenmatrix und Contract-Inhalt (Code-Review A-12)
foreach ($dir in @('Packages', 'Application')) {
    $path = Join-Path $Root $dir
    if (-not (Test-Path $path)) { continue }
    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $source = Get-UnitRole $ownUnit $RolePrefixes $HostRoles
        if ($null -eq $source) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            $target = Get-UnitRole $unit.Name $RolePrefixes $HostRoles
            if ((Test-RoleImport $source $target) -or (Test-RoleApproved $ownUnit $unit.Name)) { continue }
            $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Rollenmatrix: $(Get-RoleDescription $source $target)"
        }
        if ($source.Role -ne 'Contract') { continue }
        $interface = [regex]::Match($text, '(?im)^\s*implementation\b')
        $head = $text
        if ($interface.Success) { $head = $text.Substring(0, $interface.Index) }
        foreach ($match in [regex]::Matches($head, '(?im)^\s*(\w+)\s*=\s*class\b(?!\s*of\b)(?!\s*;)(?:\s*\(\s*([\w.]+))?')) {
            $typeName = $match.Groups[1].Value
            $ancestor = $match.Groups[2].Value
            if ($ancestor -ieq 'Exception' -or $ancestor -cmatch '^E[A-Z]' -or $ancestor -match '\.E[A-Z]\w*$') { continue }
            if ($ContractContentAllow | Where-Object { "$ownUnit.$typeName" -like $_ }) { continue }
            $line = ($head.Substring(0, $match.Index + $match.Value.Length - $match.Value.TrimStart().Length) -split "`n").Count
            $violations += "${relative}:${line}: $typeName ist eine Klasse in einer Contract-Unit (Konzept 7.1)"
        }
    }
}

# Featurerichtung (A-11): keine Unit unter Source/Editing importiert Atlas.Common.Rules.*
$editingDir = Join-Path $Root 'Packages/Atlas.Common/Source/Editing'
if (Test-Path $editingDir) {
    foreach ($file in Get-ChildItem -Path $editingDir -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            if ($unit.Name.StartsWith('Atlas.Common.Rules.', [StringComparison]::OrdinalIgnoreCase)) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Editing darf Rules nicht verwenden (A-11); gemeinsame Typen nach Documents.Contract oder Pascal verschieben"
            }
        }
    }
}

# Grundbausteine und Feature-Zyklen des Plugins (Code-Review A-09)
# - Atlas.IDE.Foundation.* (Einstellungen, Editorpuffer, Tasten, Ergebnisfenster …) sind die Basis aller
#   IDE-Features und verwenden selbst kein anderes Atlas.IDE.*.
# - Die Features von Atlas.Core und Atlas.IDE bilden keinen Zyklus (Tarjan über die uses aller Units).
#   Nicht mitgezählt: Atlas.IDE.Foundation.*, die Kompositionswurzel und Verweise auf *.Contract (Contracts
#   verwenden nur Contracts und schließen darum keinen Zyklus).
$PluginSource = Join-Path $Root 'Packages/Atlas.IDE.Expert/Source'
$CompositionRoots = @('Atlas.IDE.CodeInsight.Composition')
if (Test-Path $PluginSource) {
    $featureEdges = @{}
    function Get-PluginFeature([string] $Name) {
        if ($Name -match '^(?i)Atlas\.IDE\.Foundation\.') { return $null }
        $match = [regex]::Match($Name, '^(?i)Atlas\.(Core|IDE)\.(\w+)\.')
        if (-not $match.Success) { return $null }
        return "Atlas.$($match.Groups[1].Value).$($match.Groups[2].Value)"
    }
    foreach ($file in Get-ChildItem -Path $PluginSource -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $entries = @(Get-ClauseEntries $text 'uses')
        if ($ownUnit -match '^(?i)Atlas\.IDE\.Foundation\.') {
            foreach ($unit in $entries) {
                if ($unit.Name -match '^(?i)Atlas\.IDE\.' -and $unit.Name -notmatch '^(?i)Atlas\.IDE\.Foundation\.') {
                    $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.IDE.Foundation.* verwendet nur Atlas.IDE.Foundation.* aus der IDE-Schicht (A-09)"
                }
            }
            continue
        }
        if ($CompositionRoots -contains $ownUnit) { continue }
        $from = Get-PluginFeature $ownUnit
        if ($null -eq $from) { continue }
        foreach ($unit in $entries) {
            if ($unit.Name -match '\.Contract$') { continue }
            $to = Get-PluginFeature $unit.Name
            if ($null -eq $to -or $to -eq $from) { continue }
            if (-not $featureEdges.ContainsKey($from)) { $featureEdges[$from] = @{} }
            if (-not $featureEdges[$from].ContainsKey($to)) { $featureEdges[$from][$to] = "$ownUnit -> $($unit.Name)" }
        }
    }
    # Tarjan, starke Zusammenhangskomponenten mit mehr als einem Feature sind Zyklen.
    $script:tarjanIndex = 0
    $script:tarjanStack = [Collections.Generic.Stack[string]]::new()
    $script:tarjanOn = @{}
    $script:tarjanNumber = @{}
    $script:tarjanLow = @{}
    $script:tarjanComponents = @()
    function Invoke-Tarjan([string] $Node) {
        $script:tarjanNumber[$Node] = $script:tarjanIndex
        $script:tarjanLow[$Node] = $script:tarjanIndex
        $script:tarjanIndex++
        $script:tarjanStack.Push($Node)
        $script:tarjanOn[$Node] = $true
        if ($featureEdges.ContainsKey($Node)) {
            foreach ($next in @($featureEdges[$Node].Keys)) {
                if (-not $script:tarjanNumber.ContainsKey($next)) {
                    Invoke-Tarjan $next
                    $script:tarjanLow[$Node] = [Math]::Min($script:tarjanLow[$Node], $script:tarjanLow[$next])
                }
                elseif ($script:tarjanOn[$next]) {
                    $script:tarjanLow[$Node] = [Math]::Min($script:tarjanLow[$Node], $script:tarjanNumber[$next])
                }
            }
        }
        if ($script:tarjanLow[$Node] -eq $script:tarjanNumber[$Node]) {
            $component = @()
            do {
                $member = $script:tarjanStack.Pop()
                $script:tarjanOn[$member] = $false
                $component += $member
            } while ($member -ne $Node)
            if ($component.Count -gt 1) { $script:tarjanComponents += , $component }
        }
    }
    foreach ($node in @($featureEdges.Keys | Sort-Object)) {
        if (-not $script:tarjanNumber.ContainsKey($node)) { Invoke-Tarjan $node }
    }
    foreach ($component in $script:tarjanComponents) {
        $members = @($component | Sort-Object)
        $examples = @()
        foreach ($from in $members) {
            if (-not $featureEdges.ContainsKey($from)) { continue }
            foreach ($to in @($featureEdges[$from].Keys | Sort-Object)) {
                if ($members -contains $to) { $examples += $featureEdges[$from][$to] }
            }
        }
        $violations += "Feature-Zyklus (A-09): $($members -join ', ') – $($examples -join '; ')"
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
