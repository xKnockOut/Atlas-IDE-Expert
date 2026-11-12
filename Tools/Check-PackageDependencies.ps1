<#
.SYNOPSIS
    Prüft, ob die Packages ihre erlaubten Abhängigkeiten einhalten.

.DESCRIPTION
    - Atlas.Text    : nur RTL, ohne andere Atlas-Artefakte; gemeinsamer Code
        für Server und Plugin
    - Atlas.WinBase : RTL, Winapi.*, System.Win.* und Atlas.Text; gemeinsamer
        Windows-Code für Server und Plugin (Prozessstart)
    - Atlas.Common  : frei von Windows und VCL (nur plattformunabhängige RTL,
        Atlas.Text)
    - Atlas.Windows : frei von VCL (RTL, Winapi.*, System.Win.*, Atlas.Common, Atlas.WinBase)
    - Atlas.IDE.Base (Kern des Plugins, bis #1456 Atlas.IDE.Expert): eigenständig; darin Schichten (#406):
        Atlas.Core.* ohne VCL, Open Tools API, Atlas.UI.* und Atlas.IDE.*
        Atlas.UI.*   ohne Open Tools API und Atlas.IDE.*
    - Atlas.Core.VersionControl.* (Versionsverwaltung, #571): übersetzt auch der Server
        mit; darum nur RTL, Winapi, Atlas.WinBase.* und eigene Atlas.Core.VersionControl.*-Units

    Atlas.Text und Atlas.WinBase im Plugin: Das Plugin requiret
    beide nicht, sondern übersetzt deren Units selbst mit (contains … in
    '..\Atlas.Text\Source\…' bzw. '..\Atlas.WinBase\Source\…'). Geprüft wird, dass
      - das Plugin außer eigenen Units (Source\…) nur Units dieser beiden enthält,
      - es genau die Units aus Atlas.Text.dpk und Atlas.WinBase.dpk enthält (sonst W1033),
      - Atlas.Tests.dpr und AtlasServer.dpr keine Quellen der beiden einbinden
        (sie linken die DCUs aus Dcu\Atlas.Text bzw. Dcu\Atlas.WinBase; zwei Fassungen vermeiden).

    Kopien-Sperre: Außerhalb von Packages/Atlas.Text darf im
    implementation-Teil keine Routine wie LineBreakOf, SplitLines, IndentOf,
    IsWordChar, IsIdentChar, IsUtf8, PercentDecode usw. neu entstehen. Erlaubt
    sind nur die Fassaden und Sonderfälle in $AllowedLocal, jeweils mit Grund.
    Ebenso für die Token-Helfer (#1979): Innerhalb von Packages/Atlas.Common
    definiert nur Atlas.Common.Pascal.TokenCursor Routinen wie TokenFrom,
    NextCode, PreviousCode, IsTrivia, MatchingParen, IsKeywordIn; abweichende
    Fassungen stehen mit Grund in $TokenAllowedLocal.
    Dasselbe gilt für JSON-Lesehelfer (#1969): Eine Routine TextOf, StringOf,
    NumberOf, IntOf, FlagOf, ObjectOf, ArrayOf usw. mit einem TJSONObject und
    einem Namen als Parametern gibt es nur als TJsonRead in Atlas.Text.Json;
    Ausnahmen mit eigenem Verhalten stehen in $AllowedJsonLocal.

    Rollenmatrix: Jede Unit wird nach
    Ausgabeartefakt.Feature.Rolle.Sache eingeordnet; ein uses-Eintrag muss die
    Importregeln aus docs/Architektur.md einhalten. Contract-Units deklarieren
    im interface keine Klassen außer Ausnahmen. Genehmigte
    Ausnahmen stehen als "allow" der Regeln architecture-role-import und
    architecture-contract-content in atlas.json (eine Liste für Skript und
    Linter). Die Matrix muss TArchitectureMatrix in
    Atlas.Common.Rules.Builtin.Architecture entsprechen; beide prüfen die
    Fallliste Tests/Data/Architecture/role-imports.json (-SelfTest).

    Featurerichtung Rules/Editing: Rules darf Editing
    verwenden (Korrekturen nutzen Editing-Helfer), Editing aber nicht Rules.
    Gemeinsame Wertetypen wie TTextEdit liegen in Documents.Contract.

    Plugin-Struktur: Atlas.IDE.Foundation.* verwendet aus
    der IDE-Schicht nur Atlas.IDE.Foundation.*; die Features von Atlas.Core
    und Atlas.IDE bilden keinen Zyklus (ohne Foundation, Kompositionswurzel
    und Verweise auf *.Contract).

    Modulgrenzen (#1455): Welche Unit des Plugins in welches
    Package gehört, steht als Daten in docs/adr/0017-unit-zuordnung.md
    (Ordnertabelle, Einzelzeilen je Package). Jede Unit braucht dort eine
    Zeile. Verboten sind Base -> Modul und Modul -> anderes Modul; die
    Verträge zwischen Modulen liegen in Base (Source/Contracts). Befristete
    Ausnahmen und bekannte Verstöße stehen im Abschnitt "Grenzen zwischen
    Base, Modulen und Verträgen"; bekannte Verstöße werden bei jedem Lauf
    genannt, neue sind Fehler, nicht mehr vorkommende Zeilen ebenso.
    Tools/Test-PackageDependencies.ps1 prüft das mit absichtlichen Verstößen.

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

# Plugin-Packages (#1456): Base ist Atlas.IDE.Base; jedes weitere
# Packages/Atlas.IDE.* ist ein Modul mit eigenen Quellen unter Source. Die Verträge zwischen Modulen liegen in Base.
$PluginBaseFolder = 'Atlas.IDE.Base'
$PluginFolders = @($PluginBaseFolder)
foreach ($dir in @(Get-ChildItem -Path (Join-Path $Root 'Packages') -Directory -Filter 'Atlas.IDE.*' | Sort-Object Name)) {
    if ($dir.Name -ne $PluginBaseFolder) { $PluginFolders += $dir.Name }
}

$Packages = @(
    @{
        # Wird auch als Quelltext ins Plugin übersetzt, darum nur RTL.
        Name             = 'Atlas.Text'
        Path             = 'Packages/Atlas.Text'
        AllowedRequires  = @('rtl')
        ForbiddenPrefix  = @('Winapi.', 'System.Win.', 'Vcl.', 'FMX.', 'Atlas.Common', 'Atlas.Windows',
                             'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.', 'Setup.')
        ForbiddenUnits   = $LegacyVclUnits + $LegacyWindowsUnits
        Reason           = 'nur RTL; wird auch ins Plugin übersetzt'
    },
    @{
        # Gegenstück zu Atlas.Text für Code mit Windows-API (Code-Review R-101/D-104); wie Atlas.Text auch als
        # Quelltext im Plugin, darum ohne VCL und ohne alles, was das Plugin nicht enthalten darf.
        Name             = 'Atlas.WinBase'
        Path             = 'Packages/Atlas.WinBase'
        AllowedRequires  = @('rtl', 'Atlas.Text')
        ForbiddenPrefix  = @('Vcl.', 'FMX.', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.',
                             'Setup.')
        ForbiddenUnits   = $LegacyVclUnits
        Reason           = 'nur RTL, Windows-API und Atlas.Text; wird auch ins Plugin übersetzt'
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
        AllowedRequires  = @('rtl', 'Atlas.Common', 'Atlas.Text', 'Atlas.WinBase')
        ForbiddenPrefix  = @('Vcl.', 'FMX.')
        ForbiddenUnits   = $LegacyVclUnits
        Reason           = 'frei von VCL'
    },
    @{
        # Eigenständig, damit die IDE nur ein BPL laden muss; Atlas.Text kommt als Quelltext
        # hinein (contains), nicht über requires. vclwinx (TImageCollection,
        # TVirtualImageList für das Atlas-Symbol, #751) gehört zur IDE und ist immer geladen.
        Name             = $PluginBaseFolder
        Path             = "Packages/$PluginBaseFolder"
        AllowedRequires  = @('rtl', 'vcl', 'vclwinx', 'designide')
        ForbiddenPrefix  = @('Atlas.Common', 'Atlas.Windows', 'FMX.')
        ForbiddenUnits   = @()
        Reason           = 'eigenständig ohne Atlas.Common und Atlas.Windows'
    }
)
# Module requiren nur Base, das auch die Verträge zwischen Modulen enthält (Regel 9).
foreach ($folder in $PluginFolders | Where-Object { $_ -ne $PluginBaseFolder }) {
    $requires = @('rtl', 'vcl', 'vclwinx', 'designide', $PluginBaseFolder)
    $Packages += @{
        Name             = $folder
        Path             = "Packages/$folder"
        AllowedRequires  = $requires
        ForbiddenPrefix  = @('Atlas.Common', 'Atlas.Windows', 'FMX.')
        ForbiddenUnits   = @()
        Reason           = 'ohne Atlas.Common und Atlas.Windows'
    }
}

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

# Kopien-Sperre: Namen, die nur Atlas.Text definieren soll.
$CopyLockNames = @('LineBreakOf', 'LineBreakIn', 'DetectLineBreak', 'SplitLines', 'StripCr', 'IndentOf', 'IsWordChar',
    'IsIdentChar', 'IsIdentStart', 'DecodeEntities', 'PercentDecode', 'PercentEncode', 'IsUtf8', 'CheckUtf8', 'HasPrefix')

# Erlaubte lokale Definitionen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedLocal = @{
    'Atlas.Common.Documents.FileEncoding:TFileEncoding.DetectLineBreak' = 'Fassade mit eigenem Typ TLineBreakStyle, leitet an TTextLines.DominantOf weiter'
    'Atlas.Common.Lsp.Documentation:TLspDocumentation.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Common.Editing.DataFieldNames:IsWordChar'                    = 'SQL-Bezeichner mit $, @ und #, keine Pascal-Regel'
    'Atlas.Core.Query.Model:IsWordChar'                                 = 'Wörter der Abfragesprache: Punkt, @name und Masken mit * und ? gehören zum Wort'
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

# Kopien-Sperre für JSON-Lesehelfer (#1969): Namen mit (TJSONObject/TJSONValue; const …: string) als Parametern.
$JsonLockNames = @('TextOf', 'TextIn', 'StringOf', 'NumberOf', 'NumberIn', 'IntOf', 'IntegerOf', 'Int64Of', 'FloatOf',
    'FlagOf', 'FlagIn', 'BoolOf', 'BooleanOf', 'ObjectOf', 'ObjectIn', 'ArrayOf')

# Erlaubte lokale JSON-Lesehelfer ("Unit:Routine") mit eigenem Verhalten. Die Liste soll nur schrumpfen.
$AllowedJsonLocal = @{
    'Atlas.Common.Architecture.Snapshot:TSnapshotReader.ArrayOf' = 'falscher Typ ist ein Fehler im Stand (EArchitectureSnapshot), keine Vorgabe'
    'Atlas.Common.Architecture.Snapshot:ArrayOf'                 = 'Deklaration von TSnapshotReader.ArrayOf (Klasse im implementation-Teil)'
    'Atlas.Core.Tracker.Internals.GitHubJson:TAtlasGitHubJson.IntOf' = 'nur positive Zahlen (Issue-Nummern); leitet an TJsonRead.Int weiter'
    'Atlas.Core.Query.Model:StringOf'                             = 'jeder einfache Wert als Text, auch true/false und Zahlen'
    'Atlas.Core.Editor.ClassExtraction:StringOf'                  = 'jeder Wert außer null als Text'
    'Atlas.Common.Lsp.Hotspots:IntegerOf'                         = 'prüft Parameter: falscher Typ ist ein Fehler, fehlender Wert die Vorgabe'
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


# Kopien-Sperre der Token-Helfer (#1979): Innerhalb von Packages/Atlas.Common definieren nur
# Atlas.Common.Pascal.TokenCursor (Token zu einem Offset, Code-Token, Klammern, Schlüsselwörter) und
# TRoutineSignatures.WithoutTypeParams diese Namen; ContainsText_ ersetzt System.StrUtils.MatchText.
$TokenLockNames = @('TokenAt', 'TokenFrom', 'TokenAtOffset', 'TokenExactly', 'MatchingParen', 'NextCode', 'PreviousCode',
    'IsTrivia', 'IsKeywordIn', 'WithoutTypeParams', 'ContainsText_')
$TokenLockHomes = @('Atlas.Common.Pascal.TokenCursor', 'Atlas.Common.Pascal.RoutineSignatures:TRoutineSignatures.WithoutTypeParams')

# Erlaubte abweichende Fassungen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$TokenAllowedLocal = @{
    'Atlas.Common.Editing.DocumentationCommands:NextCode'                 = 'beginnt hinter AIndex und zählt nach IsCode der Unit'
    'Atlas.Common.Editing.RoutineBody:TRoutineBody.TokenAt'               = 'öffentliche Weiterleitung an TSyntaxTree.FirstTokenOf'
    'Atlas.Common.Editing.Unwrap:NextCode'                                = 'Offset im Text statt Token-Index'
    'Atlas.Common.Editing.Unwrap:TBuilder.NextCode'                       = 'Offset im Text statt Token-Index'
    'Atlas.Common.Editing.WrapCommands:NextCode'                          = 'beginnt hinter AIndex'
    'Atlas.Common.Index.Extractor.Tokens:TIndexTokenReader.NextCode'      = 'Methode des Lesers über seinen eigenen Token-Ausschnitt'
    'Atlas.Common.Index.Extractor.Tokens:TIndexTokenReader.PreviousCode'  = 'schließt AIndex ein'
    'Atlas.Common.Lsp.Completion.Cases:TokenAt'                           = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.CompletionInherited:MatchingParen'                  = 'Klammer im Text (Zeichenindex), nicht in Token'
    'Atlas.Common.Lsp.DocumentHighlights:TokenAt'                         = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.InvertBoolean:TokenAt'                              = 'Methodendeklaration von TSourceFile, sucht nach TTextPosition'
    'Atlas.Common.Lsp.InvertBoolean:TSourceFile.TokenAt'                  = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.KeywordHighlights:TokenAt'                          = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.References:TokenAt'                                 = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.Rename:TokenAt'                                     = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Lsp.SelectionRanges:TokenAt'                            = 'Token im Syntaxbaum mit out-Parameter, sucht das umschließende Token'
    'Atlas.Common.Pascal.LanguageFeatures:NextCode'                       = 'beginnt hinter AIndex, -1 statt Length ohne Treffer'
    'Atlas.Common.Pascal.SyntaxChecks:NextCode'                           = 'Methodendeklaration von TTreeChecker'
    'Atlas.Common.Pascal.SyntaxChecks:TTreeChecker.NextCode'              = 'überspringt zusätzlich Token außerhalb aktiver Zweige'
    'Atlas.Common.Rules.ConsideredUsed:TConsideredUsed.TokenAt'           = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Rules.Builtin.Automation:NextCode'                      = 'Methodendeklaration von TAutomationCheck'
    'Atlas.Common.Rules.Builtin.Automation:TAutomationCheck.NextCode'     = 'mit Grenze AStop'
    'Atlas.Common.Rules.Builtin.Calls:TokenAt'                            = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Atlas.Common.Rules.Builtin.Constants:MatchingParen'                  = 'Klammer im Text (Zeichenindex), nicht in Token'
    'Atlas.Common.Rules.Builtin.Database:TokenAt'                         = 'Methodendeklaration von TSqlBuild'
    'Atlas.Common.Rules.Builtin.Database:TSqlBuild.TokenAt'               = 'Token eines SQL-Stücks, nicht Token-Index der Unit'
    'Atlas.Common.Rules.Builtin.Inheritance.Ancestry:TokenAt'             = 'liefert das Token mit out-Parameter über den Regelkontext'
    'Atlas.Common.Rules.Builtin.MethodDirectives:WithoutTypeParams'       = 'schneidet beim ersten < ab ("A<T>.B" ergibt "A")'
    'Atlas.Common.Rules.Builtin.TypeDeclarations:NextCode'                = 'Methodendeklaration und lokale Fassung mit Grenze AStop'
    'Atlas.Common.Rules.Builtin.TypeDeclarations:TDeclarationScan.NextCode' = 'mit Grenze AStop'
    'Atlas.Common.Rules.Builtin.Units:NextCode'                           = 'zählt nach IsCode der Unit'
    'Atlas.Common.Rules.Builtin.Visibility:TokenAt'                       = 'Methodendeklaration von TInaccessibleMemberCheck'
    'Atlas.Common.Rules.Builtin.Visibility:TInaccessibleMemberCheck.TokenAt' = 'liefert High statt Length ohne Treffer'
    'Atlas.Common.Semantics.ConstantValues:TConstantValues.TokenAt'       = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
}

# Rollenmatrix. Muss TArchitectureMatrix in Atlas.Common.Rules.Builtin.Architecture
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
    # Einordnung nach Ausgabeartefakt.Feature.Rolle.Sache; $null für externe Units (RTL, VCL, Setup, Tests).
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
            # Geteilte Units (#571): nur Atlas.Core.VersionControl.* aus dem eigenen Feature und Atlas.WinBase.*
            # (Server und Plugin haben es beide).
            if ($ownUnit.StartsWith('Atlas.Core.VersionControl.', [StringComparison]::OrdinalIgnoreCase) -and
                $unit.Name.StartsWith('Atlas.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.Core.VersionControl.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.WinBase.', [StringComparison]::OrdinalIgnoreCase)) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.Core.VersionControl.* übersetzt auch der Server mit und darf nur Atlas.Core.VersionControl.* und Atlas.WinBase.* verwenden"
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

# Atlas.Text und Atlas.WinBase im Plugin: als Quelltext, genau mit den Units ihres dpk.
$SharedSourcePackages = @('Atlas.Text', 'Atlas.WinBase')
$pluginDpkName = "Packages/$PluginBaseFolder/$PluginBaseFolder.dpk"
$pluginDpk = Join-Path $Root $pluginDpkName
if (Test-Path $pluginDpk) {
    $pluginEntries = @(Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($pluginDpk))))
    foreach ($entry in $pluginEntries) {
        $path = $entry.Path -replace '/', '\'
        $shared = $SharedSourcePackages | Where-Object { $path.StartsWith("..\$_\Source\") } | Select-Object -First 1
        if ($path -ne '' -and -not $path.StartsWith('Source\') -and -not $shared) {
            $violations += "${pluginDpkName}: contains $($entry.Name) in '$($entry.Path)' – das Plugin bindet fremde Units nur aus $($SharedSourcePackages -join ' und ') ein"
        }
        if ($shared -and -not $entry.Name.StartsWith("$shared.")) {
            $violations += "${pluginDpkName}: contains $($entry.Name) – unter $shared nur $shared.*-Units"
        }
    }
    foreach ($package in $SharedSourcePackages) {
        $sharedDpk = Join-Path $Root "Packages/$package/$package.dpk"
        if (-not (Test-Path $sharedDpk)) { continue }
        $sharedUnits = @(Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($sharedDpk))) | ForEach-Object { $_.Name })
        $pluginSharedUnits = @($pluginEntries | Where-Object { $_.Name.StartsWith("$package.") } | ForEach-Object { $_.Name })
        foreach ($name in $sharedUnits | Where-Object { $pluginSharedUnits -notcontains $_ }) {
            $violations += "${pluginDpkName}: $name fehlt unter contains (steht in $package.dpk; sonst W1033)"
        }
        foreach ($name in $pluginSharedUnits | Where-Object { $sharedUnits -notcontains $_ }) {
            $violations += "${pluginDpkName}: $name steht nicht in $package.dpk"
        }
    }
}
# Module und Verträge enthalten nur eigene Quellen; Atlas.Text und Atlas.WinBase kommen über requires Base (#1456).
foreach ($folder in $PluginFolders | Where-Object { $_ -ne $PluginBaseFolder }) {
    $dpkName = "Packages/$folder/$folder.dpk"
    $dpkPath = Join-Path $Root $dpkName
    if (-not (Test-Path $dpkPath)) {
        $violations += "${dpkName}: fehlt; jedes Plugin-Package unter Packages/Atlas.IDE.* braucht sein dpk"
        continue
    }
    foreach ($entry in Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($dpkPath)))) {
        if (-not ($entry.Path -replace '/', '\').StartsWith('Source\')) {
            $violations += "${dpkName}: contains $($entry.Name) in '$($entry.Path)' – ein Modul enthält nur Units aus seinem Ordner Source"
        }
    }
}
foreach ($program in @('Tests/Atlas.Tests.dpr', 'Application/AtlasServer.dpr')) {
    $programPath = Join-Path $Root $program
    if (-not (Test-Path $programPath)) { continue }
    foreach ($entry in Get-UsesInEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($programPath)))) {
        if (($entry.Path -replace '/', '\') -match '(?i)(Atlas\.Text|Atlas\.WinBase)\\Source\\') {
            $violations += "${program}: $($entry.Name) in '$($entry.Path)' – $($Matches[1]) kommt als DCU aus Dcu\$($Matches[1]), nicht als Quelltext"
        }
    }
}

# Rollenmatrix und Contract-Inhalt
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
            $violations += "${relative}:${line}: $typeName ist eine Klasse in einer Contract-Unit"
        }
    }
}

# Featurerichtung: keine Unit unter Source/Editing importiert Atlas.Common.Rules.*
$editingDir = Join-Path $Root 'Packages/Atlas.Common/Source/Editing'
if (Test-Path $editingDir) {
    foreach ($file in Get-ChildItem -Path $editingDir -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            if ($unit.Name.StartsWith('Atlas.Common.Rules.', [StringComparison]::OrdinalIgnoreCase)) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Editing darf Rules nicht verwenden; gemeinsame Typen nach Documents.Contract oder Pascal verschieben"
            }
        }
    }
}

# Grundbausteine und Feature-Zyklen des Plugins
# - Atlas.IDE.Foundation.* (Einstellungen, Editorpuffer, Tasten, Ergebnisfenster …) sind die Basis aller
#   IDE-Features und verwenden selbst kein anderes Atlas.IDE.*.
# - Die Features von Atlas.Core und Atlas.IDE bilden keinen Zyklus (Tarjan über die uses aller Units).
#   Nicht mitgezählt: Atlas.IDE.Foundation.*, die Kompositionswurzel und Verweise auf *.Contract (Contracts
#   verwenden nur Contracts und schließen darum keinen Zyklus).
$PluginSource = Join-Path $Root "Packages/$PluginBaseFolder/Source"
$PluginSources = @($PluginFolders | ForEach-Object { Join-Path $Root "Packages/$_/Source" } | Where-Object { Test-Path $_ })
$CompositionRoots = @('Atlas.IDE.CodeInsight.Composition')
if (Test-Path $PluginSource) {
    $featureEdges = @{}
    function Get-PluginFeature([string] $Name) {
        if ($Name -match '^(?i)Atlas\.IDE\.Foundation\.') { return $null }
        $match = [regex]::Match($Name, '^(?i)Atlas\.(Core|IDE)\.(\w+)\.')
        if (-not $match.Success) { return $null }
        return "Atlas.$($match.Groups[1].Value).$($match.Groups[2].Value)"
    }
    foreach ($file in Get-ChildItem -Path $PluginSources -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $entries = @(Get-ClauseEntries $text 'uses')
        if ($ownUnit -match '^(?i)Atlas\.IDE\.Foundation\.') {
            foreach ($unit in $entries) {
                if ($unit.Name -match '^(?i)Atlas\.IDE\.' -and $unit.Name -notmatch '^(?i)Atlas\.IDE\.Foundation\.') {
                    $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.IDE.Foundation.* verwendet nur Atlas.IDE.Foundation.* aus der IDE-Schicht"
                }
            }
            continue
        }
        # Die Wurzel und ihre Teile Atlas.IDE.CodeInsight.Composition.<Teil> verbinden alle Features.
        if (@($CompositionRoots | Where-Object { $ownUnit -eq $_ -or $ownUnit -like "$_.*" }).Count -gt 0) { continue }
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
        $violations += "Feature-Zyklus: $($members -join ', ') – $($examples -join '; ')"
    }
}

# Modulgrenzen (#1455): Die Zuordnung der Units zu Packages steht als Daten in
# docs/adr/0017-unit-zuordnung.md (Ordnertabelle, Einzelzeilen je Package, Ausnahmen und bekannte Verstöße).
# Verboten: Base -> Modul, Modul -> anderes Modul. Erlaubt: Modul -> Base (auch die Verträge zwischen
# Modulen unter Source/Contracts von Base) und alles innerhalb eines Packages.
$BasePackage = 'Atlas.IDE.Base'
$AssignmentFile = 'docs/adr/0017-unit-zuordnung.md'
$BoundarySection = 'Grenzen zwischen Base, Modulen und Verträgen'
$KnownReport = @()

function Read-ModuleAssignment([string] $Path) {
    # Liest die Tabellen der Zuordnung. Zellen mit Namen stehen in Backticks.
    $result = [pscustomobject]@{
        Folders = @{}; Default = ''; Rows = @{}; Allowed = @(); Known = @(); Problems = @(); Packages = @()
    }
    $section = ''
    $subsection = ''
    $lineNo = 0
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        $lineNo++
        if ($line -match '^###\s+(.+?)\s*$') { $subsection = $Matches[1]; continue }
        if ($line -match '^##\s+(.+?)\s*$') {
            $section = $Matches[1]
            $subsection = ''
            if ($section -match '^Atlas\.IDE\.\w+$') { $result.Packages += $section }
            continue
        }
        if (-not $line.StartsWith('|') -or $line -match '^\|\s*-') { continue }
        $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
        if ($section -eq '') {
            # Ordnertabelle: | `Debug` | `Atlas.IDE.Debugger` |, "alle übrigen" ohne Backticks ist die Vorgabe.
            if ($cells.Count -ne 2 -or $cells[1] -notmatch '^`(Atlas\.IDE\.\w+)`$') { continue }
            $package = $Matches[1]
            $folders = @([regex]::Matches($cells[0], '`(\w+)`') | ForEach-Object { $_.Groups[1].Value })
            if ($folders.Count -eq 0) { $result.Default = $package }
            foreach ($folder in $folders) { $result.Folders[$folder] = $package }
            continue
        }
        if ($cells.Count -lt 3 -or $cells[0] -notmatch '^`([\w.]+)`$') { continue }
        $first = $Matches[1]
        if ($cells[1] -notmatch '^`([^`]+)`$') { continue }
        $second = $Matches[1]
        if ($section -match '^Atlas\.IDE\.\w+$') {
            if ($result.Rows.ContainsKey($first)) {
                $result.Problems += "${AssignmentFile}:${lineNo}: $first steht doppelt in der Zuordnung (auch Zeile $($result.Rows[$first].Line))"
                continue
            }
            $result.Rows[$first] = [pscustomobject]@{ Package = $section; File = $second; Reason = $cells[2]; Line = $lineNo }
        }
        elseif ($section -eq $BoundarySection) {
            $entry = [pscustomobject]@{ From = $first; To = $second; Note = $cells[2]; Line = $lineNo; Uses = 0 }
            if ($subsection -eq 'Befristete Ausnahmen') { $result.Allowed += $entry }
            elseif ($subsection -eq 'Bekannte Verstöße') { $result.Known += $entry }
        }
    }
    if ($result.Default -eq '') { $result.Problems += "${AssignmentFile}: Ordnertabelle ohne Zeile für alle übrigen Ordner" }
    foreach ($name in @($BasePackage)) {
        if ($result.Packages -notcontains $name) { $result.Problems += "${AssignmentFile}: Abschnitt ## $name fehlt" }
    }
    return $result
}

function Get-FolderPackage($Map, [string] $Relative, [string] $Folder = '') {
    # Package nach dem Ordner unter Packages (#1456, package-first), in Base nach der Ordnertabelle:
    # <Schicht>/<Ordner>/… oder direkt unter Source/ (Contracts von Base).
    if ($Folder -ne '' -and $Folder -ne $PluginBaseFolder) { return $Folder }
    $parts = $Relative.Split('/')
    if ($parts.Count -ge 3 -and @('Core', 'IDE', 'UI') -contains $parts[0] -and $Map.Folders.ContainsKey($parts[1])) {
        return $Map.Folders[$parts[1]]
    }
    if ($parts.Count -eq 2 -and $Map.Folders.ContainsKey($parts[0])) { return $Map.Folders[$parts[0]] }
    return $Map.Default
}

function Find-BoundaryEntry($Entries, [string] $Source, [string] $Target, [string] $TargetPackage) {
    foreach ($entry in $Entries) {
        if ($entry.From -ieq $Source -and ($entry.To -ieq $TargetPackage -or $entry.To -ieq $Target)) { return $entry }
    }
    return $null
}

$assignmentPath = Join-Path $Root $AssignmentFile
if ((Test-Path $PluginSource) -and -not (Test-Path $assignmentPath)) {
    $violations += "${AssignmentFile}: fehlt; die Modulgrenzen (#1455) lassen sich ohne Zuordnung nicht prüfen"
}
elseif (Test-Path $PluginSource) {
    $map = Read-ModuleAssignment $assignmentPath
    $violations += $map.Problems
    $pluginUnits = @{}
    foreach ($folder in $PluginFolders) {
        $sourceDir = Join-Path $Root "Packages/$folder/Source"
        if (-not (Test-Path $sourceDir)) { continue }
        $sourceRoot = (Resolve-Path $sourceDir).Path.TrimEnd('\', '/')
        foreach ($file in Get-ChildItem -Path $sourceDir -Recurse -File -Include '*.pas') {
            $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            $file = [pscustomobject]@{
                File   = $file.FullName.Substring($sourceRoot.Length + 1) -replace '\\', '/'
                Path   = $file.FullName
                Folder = $folder
            }
            if ($pluginUnits.ContainsKey($name)) {
                $violations += "Packages/$folder/Source/$($file.File): $name gibt es auch in Packages/$($pluginUnits[$name].Folder)/Source"
                continue
            }
            $pluginUnits[$name] = $file
        }
    }

    # Vollständigkeit und Abweichungen von der Ordnertabelle
    foreach ($name in @($pluginUnits.Keys | Sort-Object)) {
        if (-not $map.Rows.ContainsKey($name)) {
            $violations += "${AssignmentFile}: $name ($($pluginUnits[$name].File)) fehlt in der Zuordnung; Zeile unter ## $(Get-FolderPackage $map $pluginUnits[$name].File $pluginUnits[$name].Folder) eintragen"
        }
    }
    foreach ($name in @($map.Rows.Keys | Sort-Object)) {
        $row = $map.Rows[$name]
        if (-not $pluginUnits.ContainsKey($name)) {
            $violations += "${AssignmentFile}:$($row.Line): $name gibt es nicht mehr in den Plugin-Packages (Packages/Atlas.IDE.*/Source); Zeile streichen oder nachziehen"
            continue
        }
        $actual = $pluginUnits[$name].File
        if ($row.File -ne $actual) {
            $violations += "${AssignmentFile}:$($row.Line): $name liegt in $actual, nicht in $($row.File)"
        }
        $folderPackage = Get-FolderPackage $map $actual $pluginUnits[$name].Folder
        # Package-first (#1456): Hat das Package schon einen eigenen Ordner, liegen seine Units dort.
        if ($row.Package -ne $pluginUnits[$name].Folder -and $PluginFolders -contains $row.Package) {
            $violations += "${AssignmentFile}:$($row.Line): $name gehört zu $($row.Package) und liegt darum unter Packages/$($row.Package)/Source, nicht unter Packages/$($pluginUnits[$name].Folder)/Source"
        }
        elseif ($pluginUnits[$name].Folder -ne $PluginBaseFolder -and $row.Package -ne $pluginUnits[$name].Folder) {
            $violations += "${AssignmentFile}:$($row.Line): $name liegt unter Packages/$($pluginUnits[$name].Folder)/Source und steht darum unter ## $($pluginUnits[$name].Folder), nicht unter ## $($row.Package)"
        }
        if ($row.Package -ne $folderPackage -and $row.Reason -match '^Ordner\s') {
            $violations += "${AssignmentFile}:$($row.Line): $name steht unter $($row.Package), die Ordnertabelle sagt $folderPackage; eine Ausnahme braucht eine eigene Begründung"
        }
    }

    function Get-AssignedPackage([string] $Name) {
        if ($map.Rows.ContainsKey($Name)) { return $map.Rows[$Name].Package }
        return Get-FolderPackage $map $pluginUnits[$Name].File $pluginUnits[$Name].Folder
    }

    # Grenzen
    foreach ($name in @($pluginUnits.Keys | Sort-Object)) {
        $from = Get-AssignedPackage $name
        $relative = "Packages/$($pluginUnits[$name].Folder)/Source/$($pluginUnits[$name].File)"
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($pluginUnits[$name].Path))
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            if (-not $pluginUnits.ContainsKey($unit.Name)) { continue }
            $to = Get-AssignedPackage $unit.Name
            if ($to -eq $from) { continue }
            $reason = ''
            if ($from -eq $BasePackage) {
                $reason = "Base verwendet kein Modul ($to); über einen Vertrag oder eine Anmeldung lösen"
            }
            elseif ($to -ne $BasePackage) {
                $reason = "Modul $from verwendet kein anderes Modul ($to); Querbezug über einen Vertrag in Base (Source/Contracts)"
            }
            if ($reason -eq '') { continue }
            $entry = Find-BoundaryEntry $map.Allowed $name $unit.Name $to
            if ($entry) { $entry.Uses++; continue }
            $entry = Find-BoundaryEntry $map.Known $name $unit.Name $to
            if ($entry) {
                $entry.Uses++
                $KnownReport += "${relative}:$($unit.Line): uses $($unit.Name) – $reason"
                continue
            }
            $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Modulgrenze: $reason"
        }
    }
    foreach ($entry in @($map.Allowed) + @($map.Known)) {
        if ($entry.Uses -eq 0) {
            $violations += "${AssignmentFile}:$($entry.Line): $($entry.From) -> $($entry.To) kommt nicht mehr vor; Zeile streichen"
        }
    }
}

# Kopien-Sperre
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
            $violations += "${relative}:${line}: $($match.Groups[1].Value) – gibt es in Atlas.Text (Kopien-Sperre); dort verwenden oder in `$AllowedLocal begründen"
        }
    }
}

# Kopien-Sperre für JSON-Lesehelfer (#1969)
$jsonLockPattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?(?:' + ($JsonLockNames -join '|') +
    '))\s*\(\s*(?:const\s+)?\w+\s*:\s*TJSON(?:Object|Value)\s*;\s*const\s+\w+\s*:\s*string\b'
foreach ($folder in @('Packages', 'Application')) {
    $folderPath = Join-Path $Root $folder
    if (-not (Test-Path $folderPath)) { continue }
    foreach ($file in Get-ChildItem -Path $folderPath -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if ($relative.StartsWith('Packages/Atlas.Text/')) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
        if (-not $implementation.Success) { continue }
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        foreach ($match in [regex]::Matches($text.Substring($implementation.Index), $jsonLockPattern)) {
            $key = "${ownUnit}:$($match.Groups[1].Value)"
            if (-not $AllowedJsonLocal.ContainsKey($key)) {
                $line = ($text.Substring(0, $implementation.Index + $match.Index) -split "`n").Count
                $violations += "${relative}:${line}: $($match.Groups[1].Value) – JSON-Lesehelfer gibt es als TJsonRead in Atlas.Text.Json (Kopien-Sperre, #1969); dort verwenden oder in `$AllowedJsonLocal begründen"
            }
        }
    }
}

# Kopien-Sperre der Token-Helfer (#1979)
$tokenLockPattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?(?:' + ($TokenLockNames -join '|') + '))\b'
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages/Atlas.Common') -Recurse -File -Include '*.pas') {
    $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
    $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($TokenLockHomes -contains $ownUnit) { continue }
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
    $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
    if (-not $implementation.Success) { continue }
    foreach ($match in [regex]::Matches($text.Substring($implementation.Index), $tokenLockPattern)) {
        $key = "${ownUnit}:$($match.Groups[1].Value)"
        if (-not $TokenAllowedLocal.ContainsKey($key) -and -not ($TokenLockHomes -contains $key)) {
            $line = ($text.Substring(0, $implementation.Index + $match.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($match.Groups[1].Value) – gibt es in Atlas.Common.Pascal.TokenCursor (Kopien-Sperre #1979); dort verwenden oder in `$TokenAllowedLocal begründen"
        }
    }
}
foreach ($key in $TokenAllowedLocal.Keys) {
    $unitName = $key.Split(':')[0]
    $found = @(Get-ChildItem -Path (Join-Path $Root 'Packages/Atlas.Common') -Recurse -File -Filter "$unitName.pas")
    if ($found.Count -eq 0) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$TokenAllowedLocal nennt $key, die Unit gibt es nicht mehr; Zeile streichen"
        continue
    }
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($found[0].FullName))
    $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
    $routine = [regex]::Escape($key.Substring($unitName.Length + 1))
    if (-not $implementation.Success -or -not [regex]::IsMatch($text.Substring($implementation.Index), '(?im)^\s*(?:class\s+)?function\s+' + $routine + '\b')) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$TokenAllowedLocal nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
    }
}

if ($KnownReport.Count -gt 0) {
    Write-Host "Bekannte Verstöße gegen die Modulgrenzen ($($KnownReport.Count), offen laut $AssignmentFile):" -ForegroundColor Yellow
    $KnownReport | ForEach-Object { Write-Host "  $_" }
}

if ($violations.Count -gt 0) {
    Write-Host "Verstöße gegen die Package-Abhängigkeiten:" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Package-Abhängigkeiten in Ordnung.' -ForegroundColor Green
exit 0
