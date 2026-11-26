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
    - Atlas.Plugin  : Platform-Package des Plugins ohne host-spezifisches Framework (RTL, Winapi.*, Atlas.Text,
        Atlas.WinBase); nur Quelltext unter Packages/Atlas.Plugin/Source, den Base mitübersetzt (kein dpk)
    - Atlas.Vcl     : Platform-Package des Plugins, das VCL kapselt (Steuerelemente, Dialoge, Thema, Popups); RTL,
        Winapi.*, VCL, Atlas.Text, Atlas.WinBase, Atlas.Plugin; ohne Open Tools API und Fachcode von Base;
        Quelltext unter Packages/Atlas.Vcl/Source wie Atlas.Plugin
    - Atlas.ToolsApi: Platform-Package des Plugins, das die Open Tools API kapselt (Editorpuffer, Andockfenster,
        Editorleisten, Neuzeichnen, Tasten, Gutter, Dateien der IDE); RTL, Winapi.*, VCL, Open Tools API, Atlas.Text,
        Atlas.WinBase, Atlas.Plugin, Atlas.Vcl; ohne Fachcode von Base; Quelltext unter Packages/Atlas.ToolsApi/Source
    - Atlas.VersionControl: Platform-Package der Versionsverwaltung (#571), Quelltext unter
        Packages/Atlas.VersionControl/Source, den Base und der Server mitübersetzen; darum nur RTL, Winapi,
        Atlas.Text und Atlas.WinBase
    - Atlas.Core.VersionControl.* (Pläne des Moduls Versionsverwaltung): nur RTL, Winapi, Atlas.Text.*,
        Atlas.WinBase.*, Atlas.VersionControl.* und eigene Atlas.Core.VersionControl.*-Units

    Atlas.Text und Atlas.WinBase im Plugin: Das Plugin requiret
    beide nicht, sondern übersetzt deren Units selbst mit (contains … in
    '..\Atlas.Text\Source\…' bzw. '..\Atlas.WinBase\Source\…'). Geprüft wird, dass
      - das Plugin außer eigenen Units (Source\…) nur Units dieser beiden enthält,
      - es genau die Units aus Atlas.Text.dpk und Atlas.WinBase.dpk enthält (sonst W1033),
      - es jede Unit unter Packages/Atlas.Plugin/Source, Packages/Atlas.Vcl/Source und
        Packages/Atlas.ToolsApi/Source enthält (ohne eigenes dpk),
      - Atlas.Tests.dpr und AtlasServer.dpr keine Quellen der beiden einbinden
        (sie linken die DCUs aus Dcu\Atlas.Text bzw. Dcu\Atlas.WinBase; zwei Fassungen vermeiden).

    Kopien-Sperre: Außerhalb von Packages/Atlas.Text darf im
    implementation-Teil keine Routine wie LineBreakOf, SplitLines, IndentOf,
    IsWordChar, IsIdentChar, IsUtf8, PercentDecode, QuoteArgument (Befehlszeilen:
    TTextCommandLine) usw. neu entstehen. Erlaubt
    sind nur die Fassaden und Sonderfälle in $AllowedLocal, jeweils mit Grund.
    Ebenso für die Token-Helfer (#1979): Innerhalb von Packages/Atlas.Common
    definiert nur Atlas.Common.Pascal.TokenCursor Routinen wie TokenFrom,
    NextCode, PreviousCode, IsTrivia, MatchingParen, IsKeywordIn; abweichende
    Fassungen stehen mit Grund in $TokenAllowedLocal. Dazu gehören auch die
    alten Namen für PreviousCode (Prev, PreviousToken, PreviousIndex …), für
    NextCode/NextCodeAfter/FollowingCode (NextToken, NextSignificant,
    NextSolid, SkipTrivia), IsCode und ClosingParen (MatchingParen).
    JSON aus Text lesen (ParseObject, ParseValue, ParseJson mit einem string als
    Parameter und TJSONObject/TJSONValue als Ergebnis) gibt es nur als
    TJsonRead.Parse/ParseObject/ParseObjectOrEmpty in Atlas.Text.Json; eigene
    Fassungen mit Grund in $AllowedJsonParseLocal.
    Im Plugin gibt es manche Helfer nur an einer Stelle ($PluginLock): die
    Editorschrift (TAtlasEditorFont), die Auswahl im Designer
    (TAtlasDesignerAccess), Meldungszeilen der Module (TAtlasMessageSink.Say
    statt eigener Report), wartende Aufträge der Assistenten-Eingänge
    (TAtlasFileInbox.Pending), die oberste Editoransicht
    (TAtlasEditorBuffer.TopView/TopSourceView); ebenso in Atlas.Common der
    Dateiname für die Namensauflösung (TRuleContext.ResolverFileName),
    Knoten in Baumreihenfolge und Vorkommen eines Bezeichners (TSyntaxNode)
    und das Teilen außerhalb von Klammern (TRoutineSignatures.SplitTopLevel).
    Wortgleiche Kopien beliebiger Routinen findet AtlasServer --check-duplicates
    (Baseline atlas-duplicates.json).
    Module melden sich nur über TAtlasModuleHost
    an und ab: UnregisterModule und TAtlasContractHandshake.Check ruft nur
    Atlas.IDE.Base.Core.ModuleHost.
    Dasselbe gilt für JSON-Lesehelfer (#1969): Eine Routine TextOf, StringOf,
    NumberOf, IntOf, FlagOf, ObjectOf, ArrayOf usw. mit einem TJSONObject und
    einem Namen als Parametern gibt es nur als TJsonRead in Atlas.Text.Json;
    Ausnahmen mit eigenem Verhalten stehen in $AllowedJsonLocal. Zusätzlich nach
    Form, damit neue Namen derselben Kopie auffallen: Eine kurze Funktion mit
    genau einem JSON-Objekt und einem Namen als Parametern und einfachem Ergebnis
    (Text, Zahl, Wahrheitswert, Zeitpunkt, JSON-Wert), die den Wert selbst über
    GetValue/Values/TryGetValue/FindValue holt, ist eine Kopie von TJsonRead
    (Packages, Application, Tests); Ausnahmen mit Grund in $AllowedJsonFormLocal.
    JSON schreiben prüft die Form, nicht den Namen: Eine Routine mit einer
    Liste von Strings als einzigem Parameter und TJSONArray als Ergebnis gibt es
    nur als TJsonBuild.Strings, und kein Rumpf maskiert einen String über
    TJSONString.Create(…).ToJSON (dafür TJsonText.Quote, beide in
    Atlas.Text.Json). Geprüft werden Packages, Application und Tests; Ausnahmen
    mit Grund in $AllowedJsonWriteLocal.

    Kopien-Sperre für JSON lesen (nach Form): Keine Routine mit einer Liste von
    Strings als Ergebnis hängt die Werte eines TJSONArray einzeln an
    (Result := Result + [Element.Value], Result[I] := Liste.Items[I].Value,
    Liste.Add(Element.Value)); dafür TJsonRead.Strings/TrimmedStrings in
    Atlas.Text.Json. Ausnahmen mit Grund in $AllowedJsonReadLocal.

    Kopien-Sperre für Zeitstempel: "yyyy-mm-dd hh:nn:ss" liest nur
    TTextTimestamp in Atlas.Text.Timestamps; außerhalb dieser Unit ruft kein
    Quelltext in Packages und Application TryEncodeDate, TryEncodeTime oder
    TryEncodeDateTime auf. Ausnahmen mit Grund in $AllowedTimestampLocal.
    Ebenso ruft dort niemand ISO8601ToDate auf (wirft je nach Text und Compiler
    verschiedene Klassen); ISO 8601 liest TTextTimestamp.TryParseIso/IsoOrZero.

    Rollenmatrix: Jede Unit wird nach
    Ausgabeartefakt.Feature.Rolle.Sache eingeordnet; ein uses-Eintrag muss die
    Importregeln aus docs/Architektur.md einhalten. Contract-Units deklarieren
    im interface keine Klassen außer Ausnahmen. Genehmigte
    Ausnahmen stehen als "allow" der Regeln architecture-role-import und
    architecture-contract-content in atlas.json (eine Liste für Skript und
    Linter). Die Matrix muss TArchitectureMatrix in
    Rules.Builtin.Architecture entsprechen; beide prüfen die
    Fallliste Tests/Data/Architecture/role-imports.json (-SelfTest).

    Plugin-Struktur: Atlas.IDE.Foundation.* verwendet aus
    der IDE-Schicht nur Atlas.IDE.Foundation.*. Zyklen und Richtungen
    zwischen Features prüft Tools/Check-FeatureCycles.ps1.

    Modulgrenzen (#1455): Welche Unit des Plugins in welches
    Package gehört, steht als Daten in Tools/UnitAssignment.tsv (eine Zeile
    je Unit, sortiert nach Package und Unit) und
    Tools/UnitAssignment.Folders.tsv (Ordner -> Package). Jede Unit braucht
    eine Zeile. Verboten sind Base -> Modul und Modul -> anderes Modul; die
    Verträge zwischen Modulen liegen in Base (Source/Foundation). Befristete
    Ausnahmen und bekannte Verstöße stehen in
    Tools/UnitAssignment.Boundaries.tsv; bekannte Verstöße werden bei jedem
    Lauf genannt, neue sind Fehler, nicht mehr vorkommende Zeilen ebenso.
    Die Entscheidung dazu steht in docs/adr/0017-unit-zuordnung.md.
    Tools/Test-PackageDependencies.ps1 prüft das mit absichtlichen Verstößen.

    Ausgewertet werden alle uses-Klauseln der .pas-Dateien und die
    requires-Klausel der .dpk-Datei jedes Packages. Kommentare, Strings und
    Compiler-Direktiven werden vorher entfernt.

    Exit-Code 0: keine Verstöße, 1: mindestens ein Verstoß.

.PARAMETER UpdateAdapterRoles
    Schreibt die bekannten Altfälle der Rollen Adapters und Providers neu
    (Tools/AdapterRoles.known.txt); nur zum Kürzen der Liste verwenden.

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
    [switch] $SelfTest,
    [switch] $UpdateAdapterRoles
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
        # Gegenstück zu Atlas.Text für Code mit Windows-API; wie Atlas.Text auch als
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
# Platform-Packages des Plugins ohne eigenes dpk: Base übersetzt ihre Quellen mit (contains).
$Packages += @{
    Name             = 'Atlas.Plugin'
    Path             = 'Packages/Atlas.Plugin'
    AllowedRequires  = @()
    ForbiddenPrefix  = @('Vcl.', 'FMX.', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.',
                         'Atlas.Vcl.', 'Atlas.ToolsApi.', 'Setup.', 'ToolsAPI', 'DesignIntf', 'DesignEditors', 'DesignMenus', 'DesignWindows',
                         'PropInspAPI', 'DockForm')
    ForbiddenUnits   = $LegacyVclUnits
    Reason           = 'frei von VCL, Open Tools API und Fachcode von Base (nur RTL, Windows-API, Atlas.Text, Atlas.WinBase)'
}
$Packages += @{
    Name             = 'Atlas.Vcl'
    Path             = 'Packages/Atlas.Vcl'
    AllowedRequires  = @()
    ForbiddenPrefix  = @('FMX.', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.',
                         'Atlas.ToolsApi.', 'Setup.', 'ToolsAPI', 'DesignIntf', 'DesignEditors', 'DesignMenus',
                         'DesignWindows', 'PropInspAPI', 'DockForm')
    ForbiddenUnits   = @()
    Reason           = 'frei von Open Tools API und Fachcode von Base (nur RTL, Windows-API, VCL, Atlas.Text, Atlas.WinBase, Atlas.Plugin)'
}
$Packages += @{
    Name             = 'Atlas.ToolsApi'
    Path             = 'Packages/Atlas.ToolsApi'
    AllowedRequires  = @()
    ForbiddenPrefix  = @('FMX.', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.', 'Setup.')
    ForbiddenUnits   = @()
    Reason           = 'frei von Fachcode von Base (nur RTL, Windows-API, VCL, Open Tools API, Atlas.Text, Atlas.WinBase, Atlas.Plugin, Atlas.Vcl)'
}
# Versionsverwaltung: übersetzt auch der Server mit (AtlasServer.dpr), darum ohne jedes Package des Plugins.
$Packages += @{
    Name             = 'Atlas.VersionControl'
    Path             = 'Packages/Atlas.VersionControl'
    AllowedRequires  = @()
    ForbiddenPrefix  = @('Vcl.', 'FMX.', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Core.', 'Atlas.UI.', 'Atlas.IDE.',
                         'Atlas.Plugin.', 'Atlas.Vcl.', 'Atlas.ToolsApi.', 'Setup.', 'ToolsAPI', 'DesignIntf',
                         'DesignEditors', 'DesignMenus', 'DesignWindows', 'PropInspAPI', 'DockForm')
    ForbiddenUnits   = $LegacyVclUnits
    Reason           = 'übersetzt auch der Server mit (nur RTL, Windows-API, Atlas.Text, Atlas.WinBase)'
}
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

# Schichten im Plugin (#406): gelten zusätzlich je nach Präfix der Unit selbst. Die Foundation von Base
# (Atlas.IDE.Base.Foundation.*, nur Verträge ohne Framework) sehen nach Konzept 8.1 alle Features von Base, auch die
# Schichten Core und UI; Core, Shell und Adapters von Base nicht.
$BaseFoundationPrefix = 'Atlas.IDE.Base.Foundation.'
$Layers = @(
    @{
        UnitPrefix      = 'Atlas.Core.'
        ForbiddenPrefix = @('Vcl.', 'Atlas.UI.', 'Atlas.IDE.', 'Atlas.Vcl.', 'Atlas.ToolsApi.') + $OpenToolsPrefix
        AllowedPrefix   = @($BaseFoundationPrefix)
        ForbiddenUnits  = $LegacyVclUnits
        Reason          = 'frei von VCL, Open Tools API, Atlas.UI, Atlas.IDE (außer der Foundation von Base), Atlas.Vcl und Atlas.ToolsApi'
    },
    @{
        UnitPrefix      = 'Atlas.UI.'
        ForbiddenPrefix = @('Atlas.IDE.', 'Atlas.ToolsApi.') + $OpenToolsPrefix
        AllowedPrefix   = @($BaseFoundationPrefix)
        ForbiddenUnits  = @()
        Reason          = 'frei von Open Tools API, Atlas.IDE (außer der Foundation von Base) und Atlas.ToolsApi'
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
    'IsIdentChar', 'IsIdentStart', 'DecodeEntities', 'PercentDecode', 'PercentEncode', 'IsUtf8', 'CheckUtf8',
    'HasPrefix', 'QuoteArgument', 'Collapse', 'CollapseSpace')

# Erlaubte lokale Definitionen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedLocal = @{
    'Atlas.Common.Documents.FileEncoding:TFileEncoding.DetectLineBreak' = 'Fassade mit eigenem Typ TLineBreakStyle, leitet an TTextLines.DominantOf weiter'
    'Atlas.Common.Lsp.Documentation:TLspDocumentation.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Common.History.Commits:IsWordChar'                           = 'Issue-Kennungen in Commit-Nachrichten: Buchstaben ab #128 gehören zum Wort, Satzzeichen ab #128 („, “, –) nicht (gegen IsIdentChar)'
    'Atlas.Common.Dfm.DataFieldNames:IsWordChar'                    = 'SQL-Bezeichner mit $, @ und #, keine Pascal-Regel'
    'Atlas.Core.Query.Model:IsWordChar'                                 = 'Wörter der Abfragesprache: Punkt, @name und Masken mit * und ? gehören zum Wort'
    'Atlas.Core.Tracker.CodeLinks:IsWordChar'                           = 'Issue-Kennungen: Buchstaben ab #128 gehören zum Wort (äATL-1 ist keine Kennung, gegen IsAsciiIdentChar), Satzzeichen ab #128 („, “, –) nicht (gegen IsIdentChar)'
    'Rules.Builtin.Unused:IsWordChar'                      = 'verschachtelt mit Index; folgt mit Block Rules'
    'Atlas.Core.InlayHints.Store:TAtlasInlayHintStore.SplitLines'      = 'öffentliche Weiterleitung an TTextLines.SplitLines'
    'Atlas.Plugin.Files.Format:TAtlasFileFormats.IsUtf8'                 = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Plugin.Files.Format:TAtlasFileFormats.LineBreakOf'            = 'Fassade mit eigenem Typ TAtlasLineBreak'
    'Atlas.Plugin.Files.TextFile:TAtlasTextFile.IsUtf8'                  = 'Fassade, leitet an TTextEncodingProbe weiter'
    'Atlas.Core.Undo.LinePatch:TAtlasLinePatch.SplitLines'             = 'öffentliche Weiterleitung an TTextLines.SplitKeepingBreaks'
    'Atlas.Core.Completion.Snippets:TAtlasSnippets.IndentOf'           = 'öffentliche Weiterleitung an TTextLines.IndentOf'
    'Atlas.Core.Editor.MultiCursor:TAtlasMultiCursor.LineBreakOf'      = 'öffentliche Weiterleitung an TTextLines.LineBreakOf'
    'Atlas.Core.Outline.Overloads:Collapse'                            = 'TTextLines.CollapseSpace und dazu kein Leerraum innen an Klammern'
    'Atlas.Common.Testing.AffectedTests:TAffectedTests.Collapse'       = 'fasst Tests zusammen, kein Leerraum'
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
# Atlas.Common.Pascal.TokenCursor (Token zu einem Offset oder einer Position, Bezeichner unter dem Cursor,
# Code-Token, Klammern in Token und im Text, Schlüsselwörter) und
# TRoutineSignatures.WithoutTypeParams diese Namen; ContainsText_ ersetzt System.StrUtils.MatchText.
$TokenLockNames = @('TokenAt', 'TokenFrom', 'TokenAtOffset', 'TokenExactly', 'MatchingParen', 'NextCode', 'PreviousCode',
    'IsTrivia', 'IsKeywordIn', 'WithoutTypeParams', 'ContainsText_',
    # Suche nach Zeile und Spalte, Bezeichner unter dem Cursor.
    'TokenFromPosition', 'TokenUpToPosition', 'TokenTouching', 'IdentifierAt', 'NameTokenAt',
    # Alte Namen für PreviousCode.
    'PreviousToken', 'PreviousIndex', 'PreviousSignificant', 'PreviousSolid', 'PreviousCodeToken', 'PrevCode', 'Prev',
    # Alte Namen für NextCode, NextCodeAfter, FollowingCode, IsCode und MatchingParen.
    'NextCodeAfter', 'FollowingCode', 'NextToken', 'NextSignificant', 'NextSolid', 'SkipTrivia', 'IsCode',
    'ClosingParen')
$TokenLockHomes = @('Atlas.Common.Pascal.TokenCursor', 'Atlas.Common.Pascal.RoutineSignatures:TRoutineSignatures.WithoutTypeParams')

# Erlaubte abweichende Fassungen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$TokenAllowedLocal = @{
    'Editing.Formatter.Indent:PreviousSignificant'           = 'Methodendeklaration von TIndentTokens'
    'Editing.Formatter.Indent:TIndentTokens.PreviousSignificant' = 'Methode über die eigenen Token des Formatierers, leitet an PreviousCode weiter'
    'Editing.Formatter.Indent:NextSignificant'               = 'Methodendeklaration von TIndentTokens'
    'Editing.Formatter.Indent:TIndentTokens.NextSignificant' = 'Methode über die eigenen Token des Formatierers, leitet an NextCodeAfter weiter'
    'Editing.Unwrap:IsCode'                                  = 'Methodendeklaration von TBuilder'
    'Editing.Unwrap:TBuilder.IsCode'                         = 'Token-Index statt Token, außerhalb des Arrays False'
    'Rules.Builtin.Capture:NextToken'                        = 'sucht ab einem Offset über den Regelkontext und liefert das Token mit out-Parameter'
    'Rules.Builtin.Todos:IsCode'                             = 'prüft Kommentarzeilen auf auskommentierten Code, keine Token'
    'Editing.SafeDelete:PreviousSolid'                       = 'schließt AIndex ein'
    'Editing.Unwrap:PrevCode'                                = 'Offset im Text statt Token-Index'
    'Editing.Unwrap:TBuilder.PrevCode'                       = 'Offset im Text statt Token-Index'
    'Atlas.Common.Lsp.Completion.TypeGuards:Prev'                         = 'Methodendeklaration von TGuardScan'
    'Atlas.Common.Lsp.Completion.TypeGuards:TGuardScan.Prev'              = 'Methode über die eigenen Token, leitet an PreviousCode weiter'
    'Atlas.Common.Lsp.SignatureHelp:PreviousCodeToken'                    = 'überspringt nach IsSkipped der Unit'
    'Atlas.Common.Pascal.RoutineBody:TRoutineBody.TokenAt'               = 'öffentliche Weiterleitung an TSyntaxTree.FirstTokenOf'
    'Editing.Unwrap:NextCode'                                = 'Offset im Text statt Token-Index'
    'Editing.Unwrap:TBuilder.NextCode'                       = 'Offset im Text statt Token-Index'
    'Atlas.Common.Index.Extractor.Tokens:TIndexTokenReader.NextCode'      = 'Methode des Lesers über seinen eigenen Token-Ausschnitt'
    'Atlas.Common.Index.Extractor.Tokens:TIndexTokenReader.PreviousCode'  = 'schließt AIndex ein'
    'Atlas.Common.Lsp.Completion.Cases:TokenAt'                           = 'sucht nach Zeile und Spalte (TTextPosition), nicht nach Offset'
    'Editing.InvertBoolean.Protocol:TokenAt'               = 'Methodendeklaration von TSourceFile, sucht nach TTextPosition'
    'Editing.InvertBoolean.Protocol:TSourceFile.TokenAt'   = 'Methode der Unit-Sicht: rechnet die Position in den Offset um und leitet an TokenExactly weiter'
    'Atlas.Common.Lsp.SelectionRanges:TokenAt'                            = 'Token im Syntaxbaum mit out-Parameter, sucht das umschließende Token'
    'Atlas.Common.Pascal.SyntaxTree:TSyntaxTree.IdentifierAt'             = 'Methode des Baums: ein #13-Teil einer Zeichenkonstante (IsControlCharPart) gilt nicht als Bezeichner'
    'Editing.InvertBoolean:IdentifierAt'                     = 'Methodendeklaration von TSourceTokens'
    'Editing.InvertBoolean:TSourceTokens.IdentifierAt'       = 'Bezeichner, der genau bei einem Offset beginnt, nicht nach Zeile und Spalte'
    'Atlas.Common.Pascal.SyntaxChecks:NextCode'                           = 'Methodendeklaration von TTreeChecker'
    'Atlas.Common.Pascal.SyntaxChecks:TTreeChecker.NextCode'              = 'überspringt zusätzlich Token außerhalb aktiver Zweige'
    'Rules.Builtin.Database:TokenAt'                         = 'Methodendeklaration von TSqlBuild'
    'Rules.Builtin.Database:TSqlBuild.TokenAt'               = 'Token eines SQL-Stücks, nicht Token-Index der Unit'
    'Rules.Builtin.Inheritance.Ancestry:TokenAt'             = 'liefert das Token mit out-Parameter über den Regelkontext'
    'Rules.Builtin.Visibility:TokenAt'                       = 'Methodendeklaration von TInaccessibleMemberCheck'
    'Rules.Builtin.Visibility:TInaccessibleMemberCheck.TokenAt' = 'liefert High statt Length ohne Treffer'
}

# Kopien-Sperre für JSON-Lesehelfer nach Form (#1969): erlaubte eigene Fassungen ("Unit:Routine") mit Grund.
# Die Liste soll nur schrumpfen.
$AllowedJsonFormLocal = @{
    'Atlas.Core.Query.Model:StringOf'                                    = 'jeder einfache Wert als Text, auch true/false und Zahlen'
    'Atlas.Core.Editor.ClassExtraction:StringOf'                         = 'jeder Wert außer null als Text'
    'Mcp.Server:TMcpArgs.OptionalString'                    = 'Argument eines MCP-Clients: jeder einfache Wert als Text, auch Wahrheitswerte'
    'Shell.Composition.Refactorings.Services:TShellRefactoringPart.Number' = 'Antwort des eigenen Servers: fehlender Wert ist ein Fehler (Ausnahme), keine Vorgabe'
    'Shell.Composition.Refactorings.Services:TShellRefactoringPart.Count'  = 'Antwort des eigenen Servers: fehlender Wert ist ein Fehler (Ausnahme), keine Vorgabe'
    'Atlas.Common.Lsp.Baseline.Tests:NumberAt'                           = 'Pfad mit Punkten (FindValue), prüft den Typ mit Assert'
    'Atlas.Common.Lsp.Baseline.Tests:TextAt'                             = 'Pfad mit Punkten (FindValue), prüft den Typ mit Assert'
    'Editing.BoundaryCases.Protocol.Tests:Count'                         = 'Test: fehlendes Array soll als Ausnahme auffallen'
    'Editing.SlashMenu.Protocol.Tests:Field'                             = 'Test: fehlender Wert soll als Ausnahme auffallen'
    'Editing.SlashMenu.Protocol.Tests:Flag'                              = 'Test: fehlender Wert soll als Ausnahme auffallen'
    'Editing.SlashMenu.Protocol.Tests:List'                              = 'Test: fehlender Wert soll als Ausnahme auffallen'
    'Editing.SafeDelete.Protocol.Tests:Items'                            = 'Test: setzt die Einträge eines Arrays zu einer Vergleichszeile zusammen'
}

# Kopien-Sperre für JSON aus Text: nur TJsonRead.Parse/ParseObject/ParseObjectOrEmpty in Atlas.Text.Json.
$JsonParseLockNames = @('ParseObject', 'ParseValue', 'ParseJson', 'Parse', 'ParseOrNil', 'ParseOrNilText', 'Parsed',
    'ParsedObject', 'ParsedRoot', 'ParsedSchema', 'ParseRules', 'ObjectOf')

# Erlaubte eigene Fassungen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedJsonParseLocal = @{
    'Atlas.Plugin.Settings.JsonText:Parse'                   = 'Deklaration von TAtlasJsonText.Parse'
    'Atlas.Plugin.Settings.JsonText:TAtlasJsonText.Parse'    = 'entfernt Kommentare (JSONC), leitet an TJsonRead.ParseObject weiter'
    'Atlas.Plugin.Settings.Catalog:Parse'                    = 'Deklaration von TAtlasJsonValues.Parse'
    'Atlas.Plugin.Settings.Catalog:TAtlasJsonValues.Parse'   = 'liest auch einzelne Zahlen, Strings und Wahrheitswerte (über ein Hüllobjekt)'
}

# Kopien-Sperre für JSON schreiben: nach Form statt nach Namen, damit neue Namen derselben Kopie auffallen.
# Erlaubte eigene Fassungen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedJsonWriteLocal = @{
    'Atlas.Plugin.Lsp.Session.Json:TLspSessionJson.ProjectFolders' = 'baut Objekte mit uri und name, keine Liste von Strings'
}

# Kopien-Sperre für JSON lesen (Array -> Liste von Strings): nach Form wie beim Schreiben.
# Erlaubte eigene Fassungen ("Unit:Routine") mit Grund. Die Liste soll nur schrumpfen.
$AllowedJsonReadLocal = @{
    'Rules.Catalog:CompilerCodesOf' = 'prüft jeden Eintrag und bricht mit Fehlermeldung ab'
    'Rules.Catalog:OverriddenByOf'  = 'prüft jeden Eintrag und bricht mit Fehlermeldung ab'
}

# Kopien-Sperre nach Namen (Plugin und Atlas.Common): Name, Ordner, wo es ihn gibt, und erlaubte Fassungen
# ("Unit:Routine") mit Grund.
# Die Listen sollen nur schrumpfen.
$PluginLock = @(
    [pscustomobject]@{
        Name    = 'EnsureFont'
        Folder  = 'Packages'
        Home    = 'TAtlasEditorFont in Atlas.Vcl.Theme.EditorFont'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'SelectedControls'
        Folder  = 'Packages/Atlas.IDE.Designer'
        Home    = 'TAtlasDesignerAccess.Siblings/SelectedSiblings in Atlas.IDE.Designer.Access'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'Report'
        Folder  = 'Packages/Atlas.IDE.Welcome'
        Home    = 'TAtlasMessageSink.Say in Atlas.Plugin.Notifications.MessageSink'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'Report'
        Folder  = 'Packages/Atlas.IDE.Tracker'
        Home    = 'TAtlasMessageSink.Say in Atlas.Plugin.Notifications.MessageSink'
        Allowed = @{
            'Atlas.IDE.Tracker.IssuesServices:Report'                   = 'Methodendeklaration von TAtlasIssuesLink'
            'Atlas.IDE.Tracker.IssuesServices:TAtlasIssuesLink.Report'  = 'meldet nur, solange der Kontext lebt (Keep)'
            'Atlas.IDE.Tracker.LinkedStart:TAtlasIdeLinkedStart.Report' = 'baut den Text einer Meldung, meldet nicht selbst'
        }
    }
    [pscustomobject]@{
        Name    = 'Report'
        Folder  = 'Packages/Atlas.IDE.Debugger'
        Home    = 'TAtlasMessageSink.Say in Atlas.Plugin.Notifications.MessageSink'
        Allowed = @{
            'Atlas.IDE.Debug.AsyncOrigin:TAtlasIdeDebugAsyncOrigin.Report'  = 'zeigt den Ursprung als Meldung oder in der Ergebnisliste'
            'Atlas.IDE.Debug.ReattachWait:TAtlasIdeReattachWaiter.Report'   = 'meldet einen gefundenen Prozess, keine Textzeile'
        }
    }
    [pscustomobject]@{
        Name    = 'Pending'
        Folder  = 'Packages/Atlas.IDE.Assistants'
        Home    = 'TAtlasFileInbox.Pending in Atlas.Core.Assistants.Inbox'
        Allowed = @{
            'Atlas.Core.Assistants.Inbox:TAtlasFileInbox.Pending' = 'die eine Fassung'
        }
    }
    # Dateiname für die Namensauflösung der Prüfregeln: nur TRuleContext.ResolverFileName.
    [pscustomobject]@{
        Name    = 'ResolverFileName'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TRuleContext.ResolverFileName in Rules.Contract'
        Allowed = @{
            'Rules.Contract:TRuleContext.ResolverFileName' = 'die eine Fassung'
        }
    }
    [pscustomobject]@{
        Name    = 'RuleFileName'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TRuleContext.ResolverFileName in Rules.Contract'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'CheckedFileName'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TRuleContext.ResolverFileName in Rules.Contract'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'ContextFileName'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TRuleContext.ResolverFileName in Rules.Contract'
        Allowed = @{}
    }
    # Oberste Editoransicht: nur TAtlasEditorBuffer.TopView/TopSourceView.
    [pscustomobject]@{
        Name    = 'TopView'
        Folder  = 'Packages'
        Home    = 'TAtlasEditorBuffer.TopView/TopSourceView in Atlas.ToolsApi.Editor.Buffer'
        Allowed = @{
            'Atlas.ToolsApi.Editor.Buffer:TAtlasEditorBuffer.TopView' = 'die eine Fassung'
            'Atlas.IDE.Search.Editor:TAtlasIdeSearchEditor.TopView'        = 'out-Fassung für Bedingungen, leitet weiter'
        }
    }
    [pscustomobject]@{
        Name    = 'TopSourceView'
        Folder  = 'Packages'
        Home    = 'TAtlasEditorBuffer.TopSourceView in Atlas.ToolsApi.Editor.Buffer'
        Allowed = @{
            'Atlas.ToolsApi.Editor.Buffer:TAtlasEditorBuffer.TopSourceView' = 'die eine Fassung'
        }
    }
    # Syntaxbaum: Knoten in Baumreihenfolge und Vorkommen eines Bezeichners nur an TSyntaxNode.
    [pscustomobject]@{
        Name    = 'PreOrder'
        Folder  = 'Packages/Atlas.Common'
        Home    = 'TSyntaxNode.PreOrder in Atlas.Common.Pascal.SyntaxTree'
        Allowed = @{
            'Atlas.Common.Pascal.SyntaxTree:TSyntaxNode.PreOrder' = 'die eine Fassung'
        }
    }
    [pscustomobject]@{
        Name    = 'Occurrences'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TSyntaxNode.IdentifierUses und UsedInNestedRoutine in Atlas.Common.Pascal.SyntaxTree'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'MentionedInLocalRoutine'
        Folder  = 'Application/Source/Features/Rules'
        Home    = 'TSyntaxNode.IdentifierUses und UsedInNestedRoutine in Atlas.Common.Pascal.SyntaxTree'
        Allowed = @{}
    }
    # Teile einer Parameter- oder Namensliste außerhalb von Klammern: nur TRoutineSignatures.SplitTopLevel.
    [pscustomobject]@{
        Name    = 'SplitTopLevel'
        Folder  = 'Packages/Atlas.Common'
        Home    = 'TRoutineSignatures.SplitTopLevel in Atlas.Common.Pascal.RoutineSignatures'
        Allowed = @{
            'Atlas.Common.Pascal.RoutineSignatures:TRoutineSignatures.SplitTopLevel' = 'die eine Fassung'
        }
    }
    [pscustomobject]@{
        Name    = 'MessageLine'
        Folder  = 'Packages'
        Home    = 'TAtlasIdeHost.Message/Messages() in Atlas.IDE.Foundation.Host'
        Allowed = @{}
    }
    [pscustomobject]@{
        Name    = 'ActiveProject(?:File)?'
        Folder  = 'Packages'
        Home    = 'GetActiveProject (ToolsAPI) bzw. TAtlasIdeFiles.ActiveProjectFile in Atlas.ToolsApi.Files.Service'
        Allowed = @{
            'Atlas.ToolsApi.Files.Service:TAtlasIdeFiles.ActiveProjectFile'             = 'die eine Fassung'
            'Atlas.IDE.Foundation.StartOptions:TAtlasIdeStartOptions.ActiveProject'   = 'nur .dproj (Startoptionen)'
            'Atlas.IDE.Debug.MethodBreakpoints:TAtlasIdeMethodBreakpoints.ActiveProject' = 'Projekt der Projektgruppe zur aktiven Datei'
            'Atlas.Common.Index.IdeProject:TIdeProjects.ActiveProject'             = 'Server: gemeldetes Projekt der IDE, kein ToolsAPI'
        }
    }
    [pscustomobject]@{
        Name    = 'ReadLines(?:Of)?'
        Folder  = 'Packages'
        Home    = 'TAtlasIdeFiles.ReadLines/LineReader() in Atlas.ToolsApi.Files.Service'
        Allowed = @{
            'Atlas.ToolsApi.Files.Service:TAtlasIdeFiles.ReadLines'       = 'die eine Fassung'
            'Atlas.IDE.Welcome.Adapters.QuickActions:ReadLines'         = 'nur von der Platte (Projektdateien, nie ein offener Puffer)'
            'Atlas.Common.Lsp.SignatureHelp:THelpRun.ReadLines'         = 'Server: Zeilen der Hilfeanfrage, keine Datei'
            'Atlas.Common.Lsp.SignatureHelp:ReadLines'                  = 'Deklaration von THelpRun.ReadLines'
        }
    }
)

# An- und Abmelden der Module nur über TAtlasModuleHost: Aufrufe, die nur diese Units enthalten dürfen.
$ModuleHostCalls = @('\.UnregisterModule\s*\(', '\bTAtlasContractHandshake\.Check\s*\(')
$ModuleHostHomes = @('Atlas.IDE.Base.Core.ModuleHost', 'Atlas.IDE.Base.Core.Modules.Registry', 'Atlas.IDE.Base.Core.Modules.Handshake')

# Rollenmatrix. Muss TArchitectureMatrix in Rules.Builtin.Architecture
# entsprechen; beide prüfen Tests/Data/Architecture/role-imports.json. Präfixe und Hosted-Features stehen gleich in
# "prefixes" und "hostedFeatures" beider Architekturregeln in atlas.json (wird geprüft); Fachcode-Packages,
# Schichtpräfixe, noch nicht umgestellte Packages und Frameworks liest das Skript von dort.
$RolePrefixes = @('Atlas.Text', 'Atlas.WinBase', 'Atlas.Common', 'Atlas.Windows', 'Atlas.Linux', 'Atlas.Plugin', 'Atlas.Vcl',
    'Atlas.ToolsApi', 'Atlas.VersionControl', 'Atlas.IDE.Base', 'Atlas.IDE.Analysis', 'Atlas.IDE.Assistants', 'Atlas.IDE.Bookmarks',
    'Atlas.IDE.Build', 'Atlas.IDE.BuildPipeline', 'Atlas.IDE.Debugger', 'Atlas.IDE.Designer', 'Atlas.IDE.Editor', 'Atlas.IDE.Help',
    'Atlas.IDE.Rules', 'Atlas.IDE.Search', 'Atlas.IDE.Tests', 'Atlas.IDE.Tracker', 'Atlas.IDE.VersionControl',
    'Atlas.IDE.Welcome')
$HostRoles    = @('Foundation', 'Core', 'Shell', 'Adapters', 'Platform')
# Hosted-Features der Anwendung (Konzept 8.2): erstes Segment eines Namens ohne Präfix; wie "hostedFeatures" in atlas.json.
$HostedFeatures = @('Replay', 'Monitor', 'Update', 'Rules', 'Mcp', 'Editing')
$FeatureRoles = @('Contract', 'Internals', 'Providers', 'Adapters', 'Composition', 'Hosting')
# Eigenes Feature (bzw. innerhalb einer Struktur relativ zum Träger): Rolle der Quelle -> erlaubte Rollen des Ziels
$OwnAllowed = @{
    Contract    = @('Contract')
    Internals   = @('Contract', 'Internals')
    Providers   = @('Contract', 'Internals', 'Root')
    Adapters    = @('Contract', 'Internals', 'Root')
    Root        = @('Contract', 'Internals', 'Root')
    Composition = @('Contract', 'Providers', 'Adapters', 'Root', 'Composition', 'Hosting')
    Hosting     = @('Contract', 'Hosting')
}
# Fremdes Feature: Contract nur Contract, alle anderen Rollen Contract und Root.
# Host-Rollen (Konzept 8.1): erlaubte Rollen fremder Features und erlaubte Host-Rollen. Die Shell setzt
# zusammen und sieht alles außer Internals; Host-Adapters implementieren Sub-Contracts.
$HostAllowed = @{
    Foundation = @('Contract')
    Core       = @('Contract', 'Root')
    Shell      = @('Contract', 'Root', 'Providers', 'Adapters', 'Composition', 'Hosting', 'SubContract', 'Nested')
    Adapters   = @('Contract', 'Root', 'SubContract')
    Platform   = @('Contract', 'Root')
}
$HostHostAllowed = @{
    Foundation = @('Foundation')
    Core       = @('Foundation', 'Core', 'Platform')
    Shell      = @('Foundation', 'Core', 'Shell', 'Adapters', 'Platform')
    Adapters   = @('Foundation', 'Core', 'Adapters', 'Platform')
    Platform   = @('Platform')
}

function Get-OptionList($Options, [string] $Name) {
    # Liste aus einem JSON-Objekt (atlas.json bzw. Fallliste); leer, wenn der Schlüssel fehlt. Aufrufer fassen in @().
    if ($null -ne $Options -and $Options.PSObject.Properties[$Name]) { return @($Options.$Name | Where-Object { $_ -ne '' }) }
    return @()
}

function New-RoleScheme([string[]] $Prefixes, [string[]] $Hosts, [string[]] $Hosted, $Options) {
    # Einordnungsschema wie TRoleImportOptions: Präfixe, Host-Rollen, Hosted-Features der Anwendung und aus $Options
    # domainPackages, basePackage, layerPrefixes, layerPackages, frameworks. Active nennt je Umfang die Präfixe:
    # Switched = Fachcode-Packages außer layerPackages (deren Units tragen noch Schichtnamen, auch Atlas.IDE.Editor.* in
    # Base), Target = dazu basePackage (Base bekommt Foundation vor der Umstellung), None = keines (Ziele einer Unit
    # mit Schichtnamen).
    $domain = @(Get-OptionList $Options 'domainPackages')
    $layerPackages = @(Get-OptionList $Options 'layerPackages')
    $base = ''
    if ($null -ne $Options -and $Options.PSObject.Properties['basePackage']) { $base = [string] $Options.basePackage }
    $scheme = [pscustomobject]@{
        Prefixes = @($Prefixes); HostRoles = @($Hosts); HostedFeatures = @($Hosted); DomainPackages = $domain
        BasePackage = $base.ToLowerInvariant(); BaseName = $base; LayerPrefixes = @(Get-OptionList $Options 'layerPrefixes')
        LayerPackages = $layerPackages; Frameworks = @(Get-OptionList $Options 'frameworks'); Active = @{}
    }
    foreach ($scope in 'Switched', 'Target', 'None') {
        $active = @()
        foreach ($prefix in @($scheme.Prefixes) + @($scheme.LayerPrefixes) + @($domain)) {
            $isDomain = @($domain | Where-Object { $_ -ieq $prefix }).Count -gt 0
            $isLayer = @($layerPackages | Where-Object { $_ -ieq $prefix }).Count -gt 0
            if (-not $isDomain -or ($scope -ne 'None' -and -not $isLayer) -or ($scope -eq 'Target' -and $prefix -ieq $base)) {
                $active += $prefix
            }
        }
        $scheme.Active[$scope] = $active
    }
    return $scheme
}

function New-RoleUnit([string] $Artefact, [string[]] $Rest, [bool] $Hosted) {
    # Feature-Unit aus den Segmenten nach dem Präfix: Rolle ist der erste Rollenbezeichner nach dem Feature; jeder
    # weitere eröffnet eine Verschachtelung (Konzept 7.4). Positions nennt die Stellen der Rollenbezeichner in
    # Segments (Segments[0] = Feature), ein Bezeichner gleich dem vorigen zählt als Sache ("Keine Wiederholung").
    $positions = @()
    $roles = @()
    for ($index = 1; $index -lt $Rest.Count; $index++) {
        $hit = $FeatureRoles | Where-Object { $_ -ieq $Rest[$index] } | Select-Object -First 1
        if ($hit -and ($roles.Count -eq 0 -or $roles[-1] -ne $hit)) {
            $positions += $index
            $roles += $hit
        }
    }
    $role = 'Root'
    if ($roles.Count -gt 0) { $role = $roles[0] }
    return [pscustomobject]@{ Artefact = $Artefact; Feature = $Rest[0]; Role = $role; Segments = $Rest
        Positions = $positions; Roles = $roles; HostRole = ''; Hosted = $Hosted; Package = ''; BasePackage = ''
        Layer = $false; Framework = $false; Display = ''; PackageName = '' }
}

function Get-UnitRole([string] $Name, $Scheme, [string] $Scope = 'Switched') {
    # Einordnung nach Ausgabeartefakt.Feature.Rolle.Sache; $null für externe Units (RTL, VCL, Setup, Tests),
    # Framework = $true für Units aus "frameworks".
    foreach ($framework in $Scheme.Frameworks) {
        if ($Name -ieq $framework -or $Name.StartsWith("$framework.", [StringComparison]::OrdinalIgnoreCase)) {
            return [pscustomobject]@{ Artefact = ''; Feature = ''; Role = 'None'; Segments = @(); Positions = @()
                Roles = @(); HostRole = ''; Hosted = $false; Package = ''; BasePackage = ''; Layer = $false; Framework = $true
                Display = $Name; PackageName = '' }
        }
    }
    $first = $Name.Split('.')[0]
    $hostedName = $Scheme.HostedFeatures | Where-Object { $_ -ieq $first } | Select-Object -First 1
    if ($hostedName -and $Name.Contains('.')) {
        # Hosted-Feature der Anwendung: kein Präfix, das erste Segment ist das Feature.
        $unit = New-RoleUnit '' @($Name.ToLowerInvariant().Split('.')) $true
        $unit.Display = $first
        return $unit
    }
    $best = ''
    foreach ($prefix in $Scheme.Active[$Scope]) {
        if ($Name.StartsWith("$prefix.", [StringComparison]::OrdinalIgnoreCase) -and $prefix.Length -gt $best.Length) {
            $best = $prefix
        }
    }
    if ($best -ne '') {
        $rest = @($Name.Substring($best.Length + 1).ToLowerInvariant().Split('.'))
        $artefact = $best.ToLowerInvariant()
        $display = $Name.Substring(0, [Math]::Min($Name.Length, $best.Length + 1 + $rest[0].Length))
        if (@($Scheme.DomainPackages | Where-Object { $_ -ieq $best }).Count -eq 0) {
            $unit = New-RoleUnit $artefact $rest $false
            $unit.Layer = @($Scheme.LayerPrefixes | Where-Object { $_ -ieq $best }).Count -gt 0
            $unit.Display = $display
            return $unit
        }
        if ($rest[0] -eq '') { return $null }
        # Fachcode-Package (Konzept 6.2): Host-Rollen im Package (8.1), sonst Hosted-Features des Packages (8.2).
        $hostRole = $Scheme.HostRoles | Where-Object { $_ -ieq $rest[0] } | Select-Object -First 1
        if ($hostRole) {
            $unit = [pscustomobject]@{ Artefact = $artefact; Feature = $hostRole.ToLowerInvariant(); Role = 'Host'
                HostRole = $hostRole; Segments = @(); Positions = @(); Roles = @(); Hosted = $false; Package = $artefact
                BasePackage = $Scheme.BasePackage; Layer = $false; Framework = $false; Display = $display
                PackageName = $Name.Substring(0, $best.Length) }
            return $unit
        }
        $unit = New-RoleUnit $artefact $rest $true
        $unit.Package = $artefact
        $unit.BasePackage = $Scheme.BasePackage
        $unit.Display = $display
        $unit.PackageName = $Name.Substring(0, $best.Length)
        return $unit
    }
    $hostRole = $Scheme.HostRoles | Where-Object { $_ -ieq $first } | Select-Object -First 1
    if ($hostRole -and $Name.Contains('.')) {
        return [pscustomobject]@{ Artefact = ''; Feature = $hostRole.ToLowerInvariant(); Role = 'Host'; HostRole = $hostRole
            Segments = @(); Positions = @(); Roles = @(); Hosted = $false; Package = ''; BasePackage = ''; Layer = $false
            Framework = $false; Display = $first; PackageName = '' }
    }
    return $null
}

function Get-TargetRole($Source, [string] $Name, $Scheme) {
    # Ziel von $Source: Von einer Unit mit Schichtnamen aus alles nach Schichtnamen (alte Regel), sonst jedes
    # Fachcode-Package nach seinem Präfix; aus einem Fachcode-Package ist ein Schichtname eine Unit von Base.
    $scope = 'Target'
    if ($null -ne $Source -and $Source.Layer) { $scope = 'None' }
    $target = Get-UnitRole $Name $Scheme $scope
    if ($null -ne $Source -and $Source.Package -ne '' -and $null -ne $target -and $target.Layer -and $Scheme.BasePackage -ne '') {
        $target.Package = $Scheme.BasePackage
        $target.BasePackage = $Scheme.BasePackage
        $target.PackageName = $Scheme.BaseName
        $target.Hosted = $true
    }
    return $target
}

function Test-Within($Unit, [int] $Length, $Carrier) {
    # True, wenn die ersten $Length Segmente von $Unit denen von $Carrier gleichen.
    if ($Unit.Segments.Count -lt $Length) { return $false }
    for ($index = 0; $index -lt $Length; $index++) {
        if ($Unit.Segments[$index] -ne $Carrier.Segments[$index]) { return $false }
    }
    return $true
}

function Get-CarrierLength($Source, $Target) {
    # Länge des tiefsten gemeinsamen Trägers (Segmente bis vor einen verschachtelten Rollenbezeichner);
    # 1 = nur das Feature.
    # Kandidaten: jede Stelle eines verschachtelten Rollenbezeichners und der ganze Name einer Unit mit Rolle
    # und Sache (Cache ist Träger von Cache.Store). Zwei Root-Fragmente einer Struktur (Cache.Store,
    # Cache.Index) verraten ihren Träger nicht im Namen und gelten als Geschwister der äußeren Rolle.
    $best = 1
    foreach ($unit in @($Source, $Target)) {
        $candidates = @($unit.Positions | Select-Object -Skip 1)
        if ($unit.Positions.Count -gt 0 -and $unit.Segments.Count -gt $unit.Positions[-1] + 1) {
            $candidates += $unit.Segments.Count
        }
        foreach ($length in $candidates) {
            if ($length -gt $best -and [Math]::Max($Source.Segments.Count, $Target.Segments.Count) -gt $length -and
                (Test-Within $Source $length $unit) -and (Test-Within $Target $length $unit)) {
                $best = $length
            }
        }
    }
    return $best
}

function Get-LevelRoles($Unit, [int] $Length) {
    # Rollenbezeichner hinter dem Träger der Länge $Length.
    $result = @()
    for ($index = 0; $index -lt $Unit.Positions.Count; $index++) {
        if ($Unit.Positions[$index] -ge $Length) { $result += $Unit.Roles[$index] }
    }
    return ,$result
}

function Get-SourceRights($Unit, [int] $Length) {
    # Importrechte relativ zum Träger: Struktur erbt die Rechte des Trägers, ein Sub-Contract nur Contract-Rechte.
    $roles = Get-LevelRoles $Unit $Length
    if ($roles.Count -eq 0) { return 'Root' }
    if ($roles -contains 'Contract') { return 'Contract' }
    return $roles[0]
}

function Get-TargetView($Unit, [int] $Length) {
    # Was von außerhalb einer Struktur sichtbar ist: Internals nie, Sub-Contract, sonst die Rolle des Trägers
    # (Nested: nur Composition und Shell).
    $roles = Get-LevelRoles $Unit $Length
    if ($roles.Count -eq 0) { return [pscustomobject]@{ Kind = 'Root'; Outer = 'Root' } }
    if ($roles.Count -eq 1) { return [pscustomobject]@{ Kind = $roles[0]; Outer = $roles[0] } }
    $kind = 'Nested'
    if ($roles -contains 'Internals') { $kind = 'NestedInternals' }
    elseif ($roles[1] -eq 'Contract') { $kind = 'SubContract' }
    return [pscustomobject]@{ Kind = $kind; Outer = $roles[0] }
}

function Test-OwnImport($Source, $Target) {
    # Gleiches Feature: Matrix relativ zum tiefsten gemeinsamen Träger.
    $length = Get-CarrierLength $Source $Target
    $rights = Get-SourceRights $Source $length
    $view = Get-TargetView $Target $length
    switch ($view.Kind) {
        'SubContract' { return $rights -eq 'Composition' -or ((Get-TargetView $Source $length).Outer -eq $view.Outer) }
        'Nested'      { return $rights -eq 'Composition' }
        default       { return $OwnAllowed[$rights] -contains $view.Kind }
    }
}

function Test-HostToHosted($Source, $Target) {
    # 8.1, Zeilen Hosted-Feature: Shell alles außer Internals, Host-Adapters nur Contract und Sub-Contract.
    $kind = (Get-TargetView $Target 1).Kind
    switch ($Source.HostRole) {
        'Shell'    { return $HostAllowed.Shell -contains $kind }
        'Adapters' { return $kind -in @('Contract', 'SubContract') }
        default    { return $false }
    }
}

function Test-ForeignImport($Source, $Target) {
    # Fremdes Platform-Feature: Contract nur Contract, alle anderen Rollen Contract und Root.
    $view = (Get-TargetView $Target 1).Kind
    if ((Get-SourceRights $Source 1) -eq 'Contract') { return $view -eq 'Contract' }
    return $view -in @('Contract', 'Root')
}

function Test-SameHost($Source, $Target) {
    # Konzept 8.1: Der Inhalt eines Packages zählt zum Host, der es aufnimmt; Base also zum Host jedes Moduls.
    return $Target.Package -ne '' -and ($Target.Package -eq $Source.Package -or $Target.Package -eq $Source.BasePackage)
}

function Test-FrameworkAllowed($Source) {
    # Konzept 6.1: In einem Fachcode-Package binden nur Hosting und die Host-Rollen ein Framework des Hosts ein.
    return $null -eq $Source -or $Source.Package -eq '' -or $Source.Role -eq 'Host' -or $Source.Roles -contains 'Hosting'
}

function Test-DomainImport($Source, $Target) {
    # Platform-Features und die Anwendung importieren kein Fachcode-Package, Fachcode-Packages einander nicht.
    if ($Source.Package -eq '' -or ($Target.Package -ne '' -and -not (Test-SameHost $Source $Target))) { return $false }
    if ($Target.Package -eq '') {
        # Platform-Feature; Host und Hosted-Features der Anwendung sind ein anderer Host.
        if ($Target.Role -eq 'Host' -or $Target.Hosted) { return $false }
        if ($Source.Role -eq 'Host') { return $HostAllowed[$Source.HostRole] -contains (Get-TargetView $Target 1).Kind }
        return Test-ForeignImport $Source $Target
    }
    if ($Target.Role -eq 'Host') {
        if ($Source.Hosted) { return $Target.HostRole -eq 'Foundation' }
        return $HostHostAllowed[$Source.HostRole] -contains $Target.HostRole
    }
    if ($Source.Role -eq 'Host') { return Test-HostToHosted $Source $Target }
    # Hosted-Features importieren einander nie (8.2), innen gilt die Matrix des Features.
    if ($Source.Artefact -ne $Target.Artefact -or $Source.Feature -ne $Target.Feature) { return $false }
    return Test-OwnImport $Source $Target
}

function Test-RoleImport($Source, $Target) {
    if ($null -ne $Target -and $Target.Framework) { return Test-FrameworkAllowed $Source }
    if ($null -eq $Source -or $null -eq $Target) { return $true }
    if ($Source.Package -ne '' -or $Target.Package -ne '') { return Test-DomainImport $Source $Target }
    # Platform-Features importieren nie den Host (8.3), Hosted-Features nur die Foundation (8.2).
    if ($Target.Role -eq 'Host') {
        if ($Source.Hosted) { return $Target.HostRole -eq 'Foundation' }
        return $Source.Role -eq 'Host' -and $HostHostAllowed[$Source.HostRole] -contains $Target.HostRole
    }
    if ($Source.Role -eq 'Host') {
        if ($Target.Hosted) { return Test-HostToHosted $Source $Target }
        return $HostAllowed[$Source.HostRole] -contains (Get-TargetView $Target 1).Kind
    }
    $same = $Source.Artefact -eq $Target.Artefact -and $Source.Feature -eq $Target.Feature
    # Platform-Features importieren keine Hosted-Features (8.3), Hosted-Features einander nie (8.2).
    if ($Target.Hosted -and -not $same) { return $false }
    if (-not $same) { return Test-ForeignImport $Source $Target }
    return Test-OwnImport $Source $Target
}

function Get-RoleName($Unit) {
    if ($Unit.Role -eq 'Host') { return "Host-$($Unit.HostRole)" }
    return $Unit.Role
}

function Get-RoleDescription($Source, $Target) {
    # Kurztext wie TArchitectureMatrix.Describe, z. B. "fremde Adapters aus Root".
    if ($Target.Framework) { return "Framework aus $(Get-RoleName $Source); nur Hosting und Host-Rollen binden es ein" }
    if ($Target.Package -ne '' -and -not ($Source.Package -ne '' -and (Test-SameHost $Source $Target))) {
        return "Fachcode-Package $($Target.PackageName) aus $(Get-RoleName $Source)"
    }
    if ($Target.Hosted -and $Source.Role -ne 'Host' -and -not ($Source.Artefact -eq $Target.Artefact -and $Source.Feature -eq $Target.Feature)) {
        return "fremdes Hosted-Feature $($Target.Display) aus $(Get-RoleName $Source)"
    }
    $kind = 'fremde'
    $length = 1
    $sourceRole = $Source.Role
    if ($Source.Role -eq 'Host') { $sourceRole = "Host-$($Source.HostRole)" }
    elseif ($Target.Role -ne 'Host' -and $Source.Artefact -eq $Target.Artefact -and $Source.Feature -eq $Target.Feature) {
        $kind = 'eigene'
        $length = Get-CarrierLength $Source $Target
        $sourceRole = Get-SourceRights $Source $length
    }
    $targetRole = "Host-$($Target.HostRole)"
    if ($Target.Role -ne 'Host') {
        $view = Get-TargetView $Target $length
        $targetRole = switch ($view.Kind) {
            'SubContract'     { 'Sub-Contract' }
            'Nested'          { "verschachtelte $($view.Outer)" }
            'NestedInternals' { 'Internals einer Struktur' }
            default           { $view.Kind }
        }
    }
    return "$kind $targetRole aus $sourceRole"
}

function Test-ContractRole($Unit) {
    # Contract oder Sub-Contract: der letzte Rollenbezeichner ist Contract.
    return $null -ne $Unit -and $Unit.Role -ne 'Host' -and $Unit.Roles.Count -gt 0 -and $Unit.Roles[-1] -eq 'Contract'
}

if ($SelfTest) {
    $data = Get-Content -Raw -Encoding UTF8 (Join-Path $Root 'Tests/Data/Architecture/role-imports.json') | ConvertFrom-Json
    $failures = @()
    $scheme = New-RoleScheme @($data.prefixes) @($data.hostRoles) @(Get-OptionList $data 'hostedFeatures') $data
    foreach ($case in $data.cases) {
        $from = Get-UnitRole $case.from $scheme
        $actual = Test-RoleImport $from (Get-TargetRole $from $case.to $scheme)
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

# Genehmigte Ausnahmen und Einordnung der Fachcode-Packages aus atlas.json (dieselben Listen liest der Linter).
$RoleImportAllow = @()
$ContractContentAllow = @()
$RoleOptions = $null
$SchemeProblems = @()
$atlasJson = Join-Path $Root 'atlas.json'
if (Test-Path $atlasJson) {
    $config = Get-Content -Raw -Encoding UTF8 $atlasJson | ConvertFrom-Json
    if ($config.PSObject.Properties['rules']) {
        $rule = $config.rules.PSObject.Properties['architecture-role-import']
        if ($rule) { $RoleOptions = $rule.Value }
        if ($rule -and $rule.Value.PSObject.Properties['allow']) { $RoleImportAllow = @($rule.Value.allow) }
        $contentRule = $config.rules.PSObject.Properties['architecture-contract-content']
        if ($contentRule -and $contentRule.Value.PSObject.Properties['allow']) { $ContractContentAllow = @($contentRule.Value.allow) }
        # Beide Regeln ordnen gleich ein, und die Präfixe gleichen denen dieses Skripts.
        $expected = @{ prefixes = $RolePrefixes; hostedFeatures = $HostedFeatures }
        foreach ($key in 'prefixes', 'hostedFeatures', 'domainPackages', 'basePackage', 'layerPrefixes', 'layerPackages', 'frameworks') {
            $left = @(Get-OptionList $RoleOptions $key) -join ', '
            $right = ''
            if ($contentRule) {
                $right = @(Get-OptionList $contentRule.Value $key) -join ', '
            }
            if ($left -ne $right) {
                $SchemeProblems += "atlas.json: ""$key"" von architecture-role-import ($left) und architecture-contract-content ($right) weichen ab"
            }
            if ($expected.ContainsKey($key) -and $left -ne ($expected[$key] -join ', ')) {
                $SchemeProblems += "atlas.json: ""$key"" von architecture-role-import muss lauten wie in Check-PackageDependencies.ps1: $($expected[$key] -join ', ')"
            }
        }
    }
}
$RoleScheme = New-RoleScheme $RolePrefixes $HostRoles $HostedFeatures $RoleOptions
# Fachcode-Packages sind die Plugin-Packages und geplante Module ohne Ordner (nur in "layerPackages", z. B.
# Atlas.IDE.Editor, dessen Namen heute als Schichtnamen in Base stehen); Base nimmt die anderen auf.
# "layerPackages" ist der Geltungsbereich der alten Schichtregel (keine Befund-Liste) und schrumpft je
# umgestelltem Package.
foreach ($folder in $PluginFolders | Where-Object { $RoleScheme.DomainPackages -notcontains $_ }) {
    $SchemeProblems += "atlas.json: ""domainPackages"" nennt das Plugin-Package $folder nicht"
}
foreach ($name in $RoleScheme.DomainPackages | Where-Object { $PluginFolders -notcontains $_ -and $RoleScheme.LayerPackages -notcontains $_ }) {
    $SchemeProblems += "atlas.json: ""domainPackages"" nennt $name ohne Ordner Packages/$name; ein geplantes Modul steht bis zu seinem Ordner in ""layerPackages"""
}
if ($RoleScheme.BasePackage -ne $PluginBaseFolder.ToLowerInvariant()) {
    $SchemeProblems += "atlas.json: ""basePackage"" muss $PluginBaseFolder sein"
}
foreach ($name in $RoleScheme.LayerPackages | Where-Object { $RoleScheme.DomainPackages -notcontains $_ }) {
    $SchemeProblems += "atlas.json: ""layerPackages"" nennt $name, das ist kein Fachcode-Package aus ""domainPackages"""
}

# Frameworks im Contract (Konzept 7.1): Ein Vertrag legt seine Konsumenten nicht auf VCL, FMX, Windows-API oder
# Open Tools API fest. Genehmigte Einzelausnahme (docs/Architektur.md, „Genehmigte Ausnahmen“): Atlas.UI.Settings.Contract
# reicht die Steuerelemente einer Optionsseite, die Base und Module mit derselben VCL bauen (Vcl.Controls).
$ContractFrameworks = '^(?i)(Vcl|FMX|Winapi|System\.Win|ToolsAPI|DesignIntf|DesignEditors|PaletteAPI)(\.|$)'
$ContractFrameworkAllow = @(@{ Unit = 'Atlas.UI.Settings.Contract'; Uses = 'Vcl.Controls' })

function Test-RoleApproved([string] $Source, [string] $Target) {
    foreach ($entry in $RoleImportAllow) {
        $parts = $entry -split '->', 2
        if ($parts.Count -eq 2 -and $Source -like $parts[0].Trim() -and $Target -like $parts[1].Trim()) { return $true }
    }
    return $false
}

$violations = @($SchemeProblems)

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
            # Pläne der Versionsverwaltung (#571): nur Atlas.Core.VersionControl.* aus dem eigenen Feature,
            # Atlas.VersionControl.*, Atlas.Text.* und Atlas.WinBase.*.
            if ($ownUnit.StartsWith('Atlas.Core.VersionControl.', [StringComparison]::OrdinalIgnoreCase) -and
                $unit.Name.StartsWith('Atlas.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.Core.VersionControl.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.VersionControl.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.Text.', [StringComparison]::OrdinalIgnoreCase) -and
                -not $unit.Name.StartsWith('Atlas.WinBase.', [StringComparison]::OrdinalIgnoreCase)) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.Core.VersionControl.* darf nur Atlas.Core.VersionControl.*, Atlas.VersionControl.*, Atlas.Text.* und Atlas.WinBase.* verwenden"
            }
            $prefixHit = $package.ForbiddenPrefix | Where-Object { $unit.Name.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
            $unitHit = $package.ForbiddenUnits | Where-Object { $unit.Name -ieq $_ }
            if ($prefixHit -or $unitHit) {
                $violations += "${relative}:$($unit.Line): uses $($unit.Name) – $($package.Name) muss $($package.Reason) sein"
            }
            if ($layer) {
                $prefixHit = $layer.ForbiddenPrefix | Where-Object { $unit.Name.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }
                if ($layer.AllowedPrefix | Where-Object { $unit.Name.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }) {
                    $prefixHit = $null
                }
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

# Atlas.Text und Atlas.WinBase im Plugin: als Quelltext, genau mit den Units ihres dpk. Platform-Packages ohne dpk
# (Atlas.Plugin, Atlas.Vcl, Atlas.ToolsApi): genau mit allen Units unter ihrem Ordner Source.
$SharedSourcePackages = @('Atlas.Text', 'Atlas.WinBase', 'Atlas.Plugin', 'Atlas.Vcl', 'Atlas.ToolsApi', 'Atlas.VersionControl')
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
        $sharedSource = Join-Path $Root "Packages/$package/Source"
        if (Test-Path $sharedDpk) {
            $sharedUnits = @(Get-ContainsEntries (Remove-PascalCommentsOnly ([IO.File]::ReadAllText($sharedDpk))) |
                ForEach-Object { $_.Name })
        } elseif (Test-Path $sharedSource) {
            $sharedUnits = @(Get-ChildItem -Path $sharedSource -Recurse -File -Filter '*.pas' |
                ForEach-Object { [IO.Path]::GetFileNameWithoutExtension($_.Name) })
        } else { continue }
        $pluginSharedUnits = @($pluginEntries | Where-Object { $_.Name.StartsWith("$package.") } | ForEach-Object { $_.Name })
        foreach ($name in $sharedUnits | Where-Object { $pluginSharedUnits -notcontains $_ }) {
            $violations += "${pluginDpkName}: $name fehlt unter contains (steht in $package; sonst W1033)"
        }
        foreach ($name in $pluginSharedUnits | Where-Object { $sharedUnits -notcontains $_ }) {
            $violations += "${pluginDpkName}: $name gibt es in $package nicht"
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
        $source = Get-UnitRole $ownUnit $RoleScheme
        if ($null -eq $source) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            $target = Get-TargetRole $source $unit.Name $RoleScheme
            # Genehmigte Ausnahmen gelten nie für Internals: Ein Platzhalter wie Atlas.Core.* gibt sie nicht frei.
            $internals = $null -ne $target -and $target.Role -ne 'Host' -and $target.Roles -contains 'Internals'
            if ((Test-RoleImport $source $target) -or ((Test-RoleApproved $ownUnit $unit.Name) -and -not $internals)) { continue }
            $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Rollenmatrix: $(Get-RoleDescription $source $target)"
        }
        if (-not (Test-ContractRole $source)) { continue }
        foreach ($unit in Get-ClauseEntries $text 'uses') {
            if ($unit.Name -notmatch $ContractFrameworks) { continue }
            if ($ContractFrameworkAllow | Where-Object { $ownUnit -like $_.Unit -and $unit.Name -like $_.Uses }) { continue }
            $violations += "${relative}:$($unit.Line): uses $($unit.Name) – ein Contract bindet kein Framework ein (VCL, FMX, Windows, Open Tools API); Ausnahmen mit Grund in `$ContractFrameworkAllow"
        }
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

# Grundbausteine des Plugins: Atlas.IDE.Foundation.* (Einstellungen, Editorpuffer, Tasten, Ergebnisfenster …) sind
# die Basis aller IDE-Features und verwenden selbst kein anderes Atlas.IDE.* außer Foundation und Core von Base
# (Atlas.IDE.Base.Foundation.*, Atlas.IDE.Base.Core.*: Verträge, Registry und Modul-Host). Zyklen zwischen Features
# prüft Tools/Check-FeatureCycles.ps1.
$PluginSources = @($PluginFolders | ForEach-Object { Join-Path $Root "Packages/$_/Source" } | Where-Object { Test-Path $_ })
foreach ($file in Get-ChildItem -Path $PluginSources -Recurse -File -Include 'Atlas.IDE.Foundation.*.pas') {
    $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
    foreach ($unit in Get-ClauseEntries $text 'uses') {
        if ($unit.Name -match '^(?i)Atlas\.IDE\.' -and $unit.Name -notmatch '^(?i)Atlas\.IDE\.(Foundation|Base\.Foundation|Base\.Core)\.') {
            $violations += "${relative}:$($unit.Line): uses $($unit.Name) – Atlas.IDE.Foundation.* verwendet aus der IDE-Schicht nur Atlas.IDE.Foundation.*, Atlas.IDE.Base.Foundation.* und Atlas.IDE.Base.Core.*"
        }
    }
}

# Modulgrenzen (#1455): Die Zuordnung der Units zu Packages steht als Daten in drei TSV-Dateien neben diesem Skript:
# Tools/UnitAssignment.tsv (eine Zeile je Unit), Tools/UnitAssignment.Folders.tsv (Ordner -> Package) und
# Tools/UnitAssignment.Boundaries.tsv (befristete Ausnahmen und bekannte Verstöße). Die Entscheidung dazu steht in
# docs/adr/0017-unit-zuordnung.md.
# Verboten: Base -> Modul, Modul -> anderes Modul. Erlaubt: Modul -> Base (auch die Verträge zwischen
# Modulen unter Source/Foundation von Base) und alles innerhalb eines Packages.
$BasePackage = 'Atlas.IDE.Base'
$AssignmentFile = 'Tools/UnitAssignment.tsv'
$FolderFile = 'Tools/UnitAssignment.Folders.tsv'
$BoundaryFile = 'Tools/UnitAssignment.Boundaries.tsv'
$KnownReport = @()

function Read-AssignmentTable([string] $Relative, [string[]] $Columns, $Problems) {
    # Liest eine TSV-Datei der Zuordnung: erste Zeile die Spaltenköpfe, Zeilen mit # und Leerzeilen zählen nicht.
    $rows = @()
    $path = Join-Path $Root $Relative
    $lineNo = 0
    foreach ($line in [IO.File]::ReadAllLines($path)) {
        $lineNo++
        if ($lineNo -eq 1) {
            if ($line.TrimStart([char]0xFEFF) -ne ($Columns -join "`t")) {
                $Problems.Add("${Relative}:1: Kopfzeile muss lauten: $($Columns -join ' <Tab> ')")
            }
            continue
        }
        if ($line.Trim() -eq '' -or $line.StartsWith('#')) { continue }
        $cells = $line.Split("`t")
        if ($cells.Count -ne $Columns.Count -or @($cells | Where-Object { $_.Trim() -eq '' }).Count -gt 0) {
            $Problems.Add("${Relative}:${lineNo}: erwartet $($Columns.Count) Spalten getrennt durch Tab ($($Columns -join ', ')), keine leer")
            continue
        }
        $row = [ordered]@{ Line = $lineNo }
        for ($i = 0; $i -lt $Columns.Count; $i++) { $row[$Columns[$i]] = $cells[$i].Trim() }
        $rows += [pscustomobject]$row
    }
    return $rows
}

function Read-ModuleAssignment {
    $problems = [Collections.Generic.List[string]]::new()
    $result = [pscustomobject]@{
        Folders = @{}; Default = ''; Rows = @{}; Allowed = @(); Known = @(); Problems = $problems; Packages = @()
    }
    foreach ($entry in Read-AssignmentTable $FolderFile @('Ordner', 'Package') $problems) {
        if ($entry.Package -notmatch '^Atlas\.IDE\.\w+$') {
            $problems.Add("${FolderFile}:$($entry.Line): $($entry.Package) ist kein Plugin-Package")
            continue
        }
        if ($entry.Ordner -eq '*') { $result.Default = $entry.Package }
        else { $result.Folders[$entry.Ordner] = $entry.Package }
    }
    $previous = $null
    foreach ($entry in Read-AssignmentTable $AssignmentFile @('Package', 'Unit', 'Datei', 'Grund') $problems) {
        if ($entry.Package -notmatch '^Atlas\.IDE\.\w+$' -or $entry.Unit -notmatch '^[\w.]+$') {
            $problems.Add("${AssignmentFile}:$($entry.Line): Package oder Unit ist kein Name ($($entry.Package), $($entry.Unit))")
            continue
        }
        if ($result.Rows.ContainsKey($entry.Unit)) {
            $problems.Add("${AssignmentFile}:$($entry.Line): $($entry.Unit) steht doppelt in der Zuordnung (auch Zeile $($result.Rows[$entry.Unit].Line))")
            continue
        }
        # Sortiert nach Package und Unit: Neue Zeilen beider Seiten landen beim Mergen an verschiedenen Stellen.
        $key = "$($entry.Package)`t$($entry.Unit)"
        if ($null -ne $previous -and [StringComparer]::OrdinalIgnoreCase.Compare($previous, $key) -gt 0) {
            $problems.Add("${AssignmentFile}:$($entry.Line): $($entry.Unit) steht nicht sortiert; Zeilen nach Package und Unit ordnen")
        }
        $previous = $key
        if ($result.Packages -notcontains $entry.Package) { $result.Packages += $entry.Package }
        $result.Rows[$entry.Unit] = [pscustomobject]@{
            Package = $entry.Package; File = $entry.Datei; Reason = $entry.Grund; Line = $entry.Line
        }
    }
    foreach ($entry in Read-AssignmentTable $BoundaryFile @('Art', 'Von', 'Nach', 'Grund') $problems) {
        $boundary = [pscustomobject]@{ From = $entry.Von; To = $entry.Nach; Note = $entry.Grund; Line = $entry.Line; Uses = 0 }
        if ($entry.Art -eq 'Ausnahme') { $result.Allowed += $boundary }
        elseif ($entry.Art -eq 'Verstoß') { $result.Known += $boundary }
        else { $problems.Add("${BoundaryFile}:$($entry.Line): Art ist Ausnahme oder Verstoß, nicht $($entry.Art)") }
    }
    if ($result.Default -eq '') { $problems.Add("${FolderFile}: Zeile * für alle übrigen Ordner fehlt") }
    foreach ($name in @($BasePackage)) {
        if ($result.Packages -notcontains $name) { $problems.Add("${AssignmentFile}: keine Zeile für $name") }
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

$PluginSource = Join-Path $Root "Packages/$PluginBaseFolder/Source"
$assignmentMissing = @($AssignmentFile, $FolderFile, $BoundaryFile | Where-Object { -not (Test-Path (Join-Path $Root $_)) })
if ((Test-Path $PluginSource) -and $assignmentMissing.Count -gt 0) {
    $violations += "$($assignmentMissing -join ', '): fehlt; die Modulgrenzen (#1455) lassen sich ohne Zuordnung nicht prüfen"
}
elseif (Test-Path $PluginSource) {
    $map = Read-ModuleAssignment
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

    # Umgestellte Fachcode-Packages (nicht mehr in "layerPackages"): Jede Unit trägt das Package im Namen und
    # braucht darum keine Zeile der Zuordnung; ein Schichtname ist ein Fehler.
    function Test-SwitchedPackage([string] $Folder) {
        return $RoleScheme.DomainPackages -contains $Folder -and $RoleScheme.LayerPackages -notcontains $Folder
    }
    function Test-NamedByPackage([string] $Name, [string] $Folder) {
        return (Test-SwitchedPackage $Folder) -and $Name.StartsWith("$Folder.", [StringComparison]::OrdinalIgnoreCase)
    }
    foreach ($name in @($pluginUnits.Keys | Sort-Object)) {
        $folder = $pluginUnits[$name].Folder
        if ((Test-SwitchedPackage $folder) -and -not (Test-NamedByPackage $name $folder)) {
            $violations += "Packages/$folder/Source/$($pluginUnits[$name].File): $name trägt einen Schichtnamen; $folder steht nicht mehr in ""layerPackages"" (atlas.json), darum heißen seine Units $folder.*"
        }
    }

    # Vollständigkeit und Abweichungen von der Ordnertabelle
    foreach ($name in @($pluginUnits.Keys | Sort-Object)) {
        if (Test-NamedByPackage $name $pluginUnits[$name].Folder) { continue }
        if (-not $map.Rows.ContainsKey($name)) {
            $violations += "${AssignmentFile}: $name ($($pluginUnits[$name].File)) fehlt in der Zuordnung; Zeile mit Package $(Get-FolderPackage $map $pluginUnits[$name].File $pluginUnits[$name].Folder) sortiert eintragen"
        }
    }
    foreach ($name in @($map.Rows.Keys | Sort-Object)) {
        $row = $map.Rows[$name]
        if (-not $pluginUnits.ContainsKey($name)) {
            $violations += "${AssignmentFile}:$($row.Line): $name gibt es nicht mehr in den Plugin-Packages (Packages/Atlas.IDE.*/Source); Zeile streichen oder nachziehen"
            continue
        }
        if (Test-NamedByPackage $name $pluginUnits[$name].Folder) {
            $violations += "${AssignmentFile}:$($row.Line): $name trägt sein Package im Namen ($($pluginUnits[$name].Folder) ist umgestellt); Zeile streichen"
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
            $violations += "${AssignmentFile}:$($row.Line): $name liegt unter Packages/$($pluginUnits[$name].Folder)/Source und gehört darum zu $($pluginUnits[$name].Folder), nicht zu $($row.Package)"
        }
        if ($row.Package -ne $folderPackage -and $row.Reason -match '^Ordner\s') {
            $violations += "${AssignmentFile}:$($row.Line): $name steht unter $($row.Package), die Ordnertabelle sagt $folderPackage; eine Ausnahme braucht eine eigene Begründung"
        }
    }

    function Get-AssignedPackage([string] $Name) {
        if (Test-NamedByPackage $Name $pluginUnits[$Name].Folder) { return $pluginUnits[$Name].Folder }
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
                $reason = "Modul $from verwendet kein anderes Modul ($to); Querbezug über einen Vertrag in Base (Source/Foundation)"
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
            $violations += "${BoundaryFile}:$($entry.Line): $($entry.From) -> $($entry.To) kommt nicht mehr vor; Zeile streichen"
        }
    }
}

# Kopien-Sperre
$lockPattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?(?:' + ($CopyLockNames -join '|') + '))\b'
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages'), (Join-Path $Root 'Application/Source/Features') -Recurse -File -Include '*.pas') {
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
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages/Atlas.Common'), (Join-Path $Root 'Application/Source/Features') -Recurse -File -Include '*.pas') {
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
    $found = @(Get-ChildItem -Path (Join-Path $Root 'Packages/Atlas.Common'), (Join-Path $Root 'Application/Source/Features') -Recurse -File -Filter "$unitName.pas")
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

# Kopien-Sperre für JSON-Lesehelfer nach Form (#1969): kurze Funktion (Objekt, Name) mit einfachem Ergebnis, die
# den Wert selbst holt.
$jsonFormFound = @{}
# Units, die es im geprüften Baum gibt (der Selbsttest prüft eine Kopie ohne Tests/).
$jsonFormUnits = @{}
$jsonFormPattern = '(?ims)^(?:class\s+)?function\s+((?:\w+\.)?\w+)\s*\(\s*(?:const\s+)?(\w+)\s*:\s*' +
    'TJSON(?:Object|Value)\s*;\s*(?:const\s+)?(\w+)\s*:\s*string\s*\)\s*:\s*' +
    '(string|Integer|Int64|Cardinal|Boolean|Double|Extended|TDateTime|TJSONObject|TJSONArray|TJSONValue|' +
    'TArray\s*<\s*(?:Integer|string)\s*>)\s*;(.*?)^end\s*;'
$jsonFormMaxLines = 18
foreach ($folder in @('Packages', 'Application', 'Tests')) {
    $folderPath = Join-Path $Root $folder
    if (-not (Test-Path $folderPath)) { continue }
    foreach ($file in Get-ChildItem -Path $folderPath -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if ($relative.StartsWith('Packages/Atlas.Text/Source/Json/')) { continue }
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $jsonFormUnits[$ownUnit] = $true
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        if ($text -notmatch '(?i)\bTJSON(?:Object|Value)\b') { continue }
        $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
        if (-not $implementation.Success) { continue }
        $body = $text.Substring($implementation.Index)
        foreach ($routine in [regex]::Matches($body, $jsonFormPattern)) {
            $inner = $routine.Groups[5].Value
            if (($inner -split "`n").Count -gt $jsonFormMaxLines) { continue }
            $object = [regex]::Escape($routine.Groups[2].Value)
            $name = [regex]::Escape($routine.Groups[3].Value)
            $reads = '(?i)\b' + $object + '\s*\.\s*(?:(?:GetValue|TryGetValue|FindValue)\s*(?:<[^>]+>)?\s*\(\s*' +
                $name + '\b|Values\s*\[\s*' + $name + '\s*\])'
            if (-not [regex]::IsMatch($inner, $reads)) { continue }
            $key = "${ownUnit}:$($routine.Groups[1].Value)"
            $jsonFormFound[$key] = $true
            if ($AllowedJsonFormLocal.ContainsKey($key)) { continue }
            $line = ($text.Substring(0, $implementation.Index + $routine.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($routine.Groups[1].Value) – liest einen JSON-Wert wie TJsonRead in Atlas.Text.Json (Kopien-Sperre nach Form, #1969); dort verwenden oder in `$AllowedJsonFormLocal begründen"
        }
    }
}
foreach ($key in $AllowedJsonFormLocal.Keys) {
    if ($jsonFormUnits.ContainsKey($key.Split(':')[0]) -and -not $jsonFormFound.ContainsKey($key)) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$AllowedJsonFormLocal nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
    }
}

# Kopien-Sperre für JSON aus Text
$jsonParseFound = @{}
$jsonParsePattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?(?:' + ($JsonParseLockNames -join '|') +
    '))\s*\(\s*const\s+\w+\s*:\s*string\s*\)\s*:\s*TJSON(?:Object|Value)\b'
foreach ($folder in @('Packages', 'Application')) {
    $folderPath = Join-Path $Root $folder
    if (-not (Test-Path $folderPath)) { continue }
    foreach ($file in Get-ChildItem -Path $folderPath -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if ($relative.StartsWith('Packages/Atlas.Text/Source/Json/')) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        foreach ($match in [regex]::Matches($text, $jsonParsePattern)) {
            $key = "${ownUnit}:$($match.Groups[1].Value)"
            $jsonParseFound[$key] = $true
            if ($AllowedJsonParseLocal.ContainsKey($key)) { continue }
            $line = ($text.Substring(0, $match.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($match.Groups[1].Value) – JSON aus Text gibt es als TJsonRead.Parse/ParseObject/ParseObjectOrEmpty in Atlas.Text.Json (Kopien-Sperre); dort verwenden oder in `$AllowedJsonParseLocal begründen"
        }
    }
}

foreach ($key in $AllowedJsonParseLocal.Keys) {
    if (-not $jsonParseFound.ContainsKey($key)) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$AllowedJsonParseLocal nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
    }
}

# Kopien-Sperre für JSON schreiben (Form statt Name)
$jsonWriteFound = @{}
$stringsArrayPattern = '(?im)^\s*(?:class\s+)?function\s+((?:\w+\.)?\w+)\s*\(\s*(?:const\s+)?\w+\s*:\s*' +
    '(?:TArray\s*<\s*string\s*>|array\s+of\s+string|TStringDynArray)\s*\)\s*:\s*TJSONArray\b'
$routinePattern = '(?ims)^(?:class\s+)?(?:function|procedure)\s+((?:\w+\.)?\w+)[^\r\n]*\r?\n(.*?)^end\s*;'
foreach ($folder in @('Packages', 'Application', 'Tests')) {
    $folderPath = Join-Path $Root $folder
    if (-not (Test-Path $folderPath)) { continue }
    foreach ($file in Get-ChildItem -Path $folderPath -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if ($relative.StartsWith('Packages/Atlas.Text/Source/Json/')) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
        if (-not $implementation.Success) { continue }
        $body = $text.Substring($implementation.Index)
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $hits = @()
        foreach ($match in [regex]::Matches($body, $stringsArrayPattern)) {
            $hits += [pscustomobject]@{ Match = $match; Message = 'Liste von Strings als JSON gibt es als TJsonBuild.Strings' }
        }
        foreach ($routine in [regex]::Matches($body, $routinePattern)) {
            $inner = $routine.Groups[2].Value
            $quotes = [regex]::IsMatch($inner, '(?i)\bTJSONString\.Create\s*\([^;]*\)\s*\.\s*ToJSON\b')
            foreach ($created in [regex]::Matches($inner, '(?i)\b(\w+)\s*:=\s*TJSONString\.Create\s*\(')) {
                if ([regex]::IsMatch($inner, '(?i)\b' + $created.Groups[1].Value + '\s*\.\s*ToJSON\b')) { $quotes = $true }
            }
            if ($quotes) {
                $hits += [pscustomobject]@{ Match = $routine; Message = 'String als JSON-Text gibt es als TJsonText.Quote' }
            }
        }
        foreach ($hit in $hits) {
            $key = "${ownUnit}:$($hit.Match.Groups[1].Value)"
            $jsonWriteFound[$key] = $true
            if ($AllowedJsonWriteLocal.ContainsKey($key)) { continue }
            $line = ($text.Substring(0, $implementation.Index + $hit.Match.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($hit.Match.Groups[1].Value) – $($hit.Message) in Atlas.Text.Json (Kopien-Sperre); dort verwenden oder in `$AllowedJsonWriteLocal begründen"
        }
    }
}
foreach ($key in $AllowedJsonWriteLocal.Keys) {
    if (-not $jsonWriteFound.ContainsKey($key)) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$AllowedJsonWriteLocal nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
    }
}

# Kopien-Sperre für JSON lesen (Form statt Name): Routine mit Liste von Strings als Ergebnis, die Werte eines
# TJSONArray einzeln anhängt.
$jsonReadFound = @{}
$stringsResultPattern = '(?ims)^(?:class\s+)?function\s+((?:\w+\.)?\w+)\s*(?:\([^)]*\))?\s*:\s*' +
    '(?:TArray\s*<\s*string\s*>|TStringDynArray)\s*;(.*?)^end\s*;'
$elementValue = '(?:TJSON\w+\s*\(\s*[\w.]+(?:\s*\[[^\]]+\])?\s*\)|\w+)(?:\s*\.\s*Items\s*\[[^\]]+\])?\s*\.\s*Value\b'
$elementPatterns = @(
    ('(?i)\b(\w+)\s*:=\s*\1\s*\+\s*\[\s*(?:Trim\s*\(\s*)?' + $elementValue),
    ('(?i)\bResult\s*\[\s*\w+\s*\]\s*:=\s*(?:Trim\s*\(\s*)?' + $elementValue),
    ('(?i)\.\s*Add\s*\(\s*(?:Trim\s*\(\s*)?' + $elementValue)
)
foreach ($folder in @('Packages', 'Application', 'Tests')) {
    $folderPath = Join-Path $Root $folder
    if (-not (Test-Path $folderPath)) { continue }
    foreach ($file in Get-ChildItem -Path $folderPath -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        if ($relative.StartsWith('Packages/Atlas.Text/Source/Json/')) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        if ($text -notmatch '(?i)\bTJSONArray\b') { continue }
        $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
        if (-not $implementation.Success) { continue }
        $body = $text.Substring($implementation.Index)
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        foreach ($routine in [regex]::Matches($body, $stringsResultPattern)) {
            if ($routine.Value -notmatch '(?i)\bTJSONArray\b') { continue }
            $inner = $routine.Groups[2].Value
            $copies = $false
            foreach ($elementPattern in $elementPatterns) {
                if ([regex]::IsMatch($inner, $elementPattern)) { $copies = $true }
            }
            if (-not $copies) { continue }
            $key = "${ownUnit}:$($routine.Groups[1].Value)"
            $jsonReadFound[$key] = $true
            if ($AllowedJsonReadLocal.ContainsKey($key)) { continue }
            $line = ($text.Substring(0, $implementation.Index + $routine.Index) -split "`n").Count
            $violations += "${relative}:${line}: $($routine.Groups[1].Value) – JSON-Array als Liste von Strings gibt es als TJsonRead.Strings/TrimmedStrings in Atlas.Text.Json (Kopien-Sperre); dort verwenden oder in `$AllowedJsonReadLocal begründen"
        }
    }
}
foreach ($key in $AllowedJsonReadLocal.Keys) {
    if (-not $jsonReadFound.ContainsKey($key)) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$AllowedJsonReadLocal nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
    }
}

# Kopien-Sperre im Plugin
foreach ($lock in $PluginLock) {
    $pattern = '(?im)^\s*(?:class\s+)?(?:procedure|function)\s+((?:\w+\.)?' + $lock.Name + ')\s*[(;:]'
    $found = @{}
    foreach ($file in Get-ChildItem -Path (Join-Path $Root $lock.Folder) -Recurse -File -Include '*.pas') {
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        $implementation = [regex]::Match($text, '(?im)^\s*implementation\b')
        if (-not $implementation.Success) { continue }
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        foreach ($match in [regex]::Matches($text.Substring($implementation.Index), $pattern)) {
            $key = "${ownUnit}:$($match.Groups[1].Value)"
            $found[$key] = $true
            if (-not $lock.Allowed.ContainsKey($key)) {
                $line = ($text.Substring(0, $implementation.Index + $match.Index) -split "`n").Count
                $violations += "${relative}:${line}: $($match.Groups[1].Value) – gibt es als $($lock.Home) (Kopien-Sperre); dort verwenden oder in `$PluginLock begründen"
            }
        }
    }
    foreach ($key in $lock.Allowed.Keys) {
        if (-not $found.ContainsKey($key)) {
            $violations += "Tools/Check-PackageDependencies.ps1: `$PluginLock ($($lock.Name)) nennt $key, die Routine gibt es nicht mehr; Zeile streichen"
        }
    }
}

# Kopien-Sperre für Schreiben in den Editorpuffer (#1973): Einen Rückgängig-Schritt mit Byte-Versatz,
# Löschen und Einfügen legt nur TAtlasEditorSnapshots.WriteEdits/ReplaceText/WriteDifference an
# (Atlas.IDE.Foundation.EditorSnapshot). Erlaubte Units mit Grund. Die Liste soll nur schrumpfen.
$WriterHome = 'Atlas.IDE.Foundation.EditorSnapshot'
$AllowedWriterLocal = @{
    'Atlas.IDE.Completion.EditorCommit' = 'Änderungen der Vervollständigung kommen schon als Byte-Versatz'
}
$writerFound = @{}
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages') -Recurse -File -Include '*.pas') {
    $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($ownUnit -eq $WriterHome) { continue }
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
    foreach ($match in [regex]::Matches($text, '(?i)\.\s*CreateUndoableWriter\b')) {
        $writerFound[$ownUnit] = $true
        if ($AllowedWriterLocal.ContainsKey($ownUnit)) { continue }
        $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
        $line = ($text.Substring(0, $match.Index) -split "`n").Count
        $violations += "${relative}:${line}: CreateUndoableWriter – in den Editorpuffer schreibt TAtlasEditorSnapshots.WriteEdits/ReplaceText/WriteDifference in $WriterHome (Kopien-Sperre, #1973); dort verwenden oder in `$AllowedWriterLocal begründen"
    }
}
foreach ($key in $AllowedWriterLocal.Keys) {
    if (-not $writerFound.ContainsKey($key)) {
        $violations += "Tools/Check-PackageDependencies.ps1: `$AllowedWriterLocal nennt $key, dort gibt es keinen Schreiber mehr; Zeile streichen"
    }
}

# Kopien-Sperre für Zeitstempel: Datum und Zeit aus Ziffern setzt nur Atlas.Text.Timestamps zusammen.
# Erlaubte Units mit Grund. Die Liste soll nur schrumpfen.
$TimestampHome = 'Atlas.Text.Timestamps'
$AllowedTimestampLocal = @{}
foreach ($folder in @('Packages', 'Application')) {
    $path = Join-Path $Root $folder
    if (-not (Test-Path $path)) { continue }
    foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas') {
        $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        if ($ownUnit -eq $TimestampHome -or $AllowedTimestampLocal.ContainsKey($ownUnit)) { continue }
        $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
        foreach ($match in [regex]::Matches($text, '(?i)\b(?:TryEncode(?:DateTime|Date|Time)|ISO8601ToDate)\s*\(')) {
            $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
            $line = ($text.Substring(0, $match.Index) -split "`n").Count
            $call = ($match.Value -replace '[\s(]', '')
            $violations += "${relative}:${line}: ${call} – Zeitstempel liest TTextTimestamp in Atlas.Text.Timestamps (Kopien-Sperre); dort verwenden oder in `$AllowedTimestampLocal begründen"
        }
    }
}

# Module nur über TAtlasModuleHost an- und abmelden
foreach ($file in Get-ChildItem -Path (Join-Path $Root 'Packages') -Recurse -File -Include '*.pas') {
    $ownUnit = [IO.Path]::GetFileNameWithoutExtension($file.Name)
    if ($ModuleHostHomes -contains $ownUnit) { continue }
    $relative = $file.FullName.Substring((Resolve-Path $Root).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
    $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
    foreach ($call in $ModuleHostCalls) {
        foreach ($match in [regex]::Matches($text, '(?i)' + $call)) {
            $line = ($text.Substring(0, $match.Index) -split "`n").Count
            $violations += "${relative}:${line}: Module melden sich nur über TAtlasModuleHost (Atlas.IDE.Base.Core.ModuleHost) an und ab"
        }
    }
}

if ($KnownReport.Count -gt 0) {
    Write-Host "Bekannte Verstöße gegen die Modulgrenzen ($($KnownReport.Count), offen laut $BoundaryFile):" -ForegroundColor Yellow
    $KnownReport | ForEach-Object { Write-Host "  $_" }
}

# Rollen Adapters und Providers (#1443): Wer ein Interface eines anderen Features implementiert, ist ein Adapter
# und nimmt es aus dessen Contract; Providers implementieren den eigenen Contract. Verträge zwischen Modulen
# (Atlas.IDE.Base.Foundation.*) zählen als fremder Contract jedes Moduls, auch für die Composition: Modulklassen stehen in
# Atlas.IDE.<Modul>.Adapters.Module. Hosting und Host-Units (Shell, Foundation …) setzen zusammen und sind
# ausgenommen, Regel 4 (Interface im Contract) gilt auch für sie.
# Bekannte Altfälle stehen in Tools/AdapterRoles.known.txt; neue sind Fehler, behobene müssen dort raus.
$AdapterRolesFile = Join-Path $Root 'Tools/AdapterRoles.known.txt'

function Get-FeatureName([string] $Name) {
    # Ausgabeartefakt.Feature in der Schreibweise der Unit, z. B. "Atlas.IDE.Welcome".
    $best = ''
    foreach ($prefix in $RoleScheme.Active['Switched']) {
        if ($Name.StartsWith("$prefix.", [StringComparison]::OrdinalIgnoreCase) -and $prefix.Length -gt $best.Length) { $best = $prefix }
    }
    if ($best -eq '') { return $Name.Split('.')[0] }
    return "$best." + $Name.Substring($best.Length + 1).Split('.')[0]
}

function Test-ContractUnit([string] $Name) {
    # Contract, Verträge zwischen Modulen und die Host-Rolle Foundation eines Fachcode-Packages (nur Verträge).
    $named = Get-UnitRole $Name $RoleScheme 'Target'
    return (Test-ContractRole (Get-UnitRole $Name $RoleScheme)) -or $Name -match '^(?i)Atlas\.IDE\.Base\.Foundation\.' -or
        ($null -ne $named -and $named.Package -ne '' -and $named.HostRole -eq 'Foundation')
}

function Get-AdapterRoleFindings([string] $BaseDir) {
    # Liefert je Verstoß Key (ohne Zeile, für die Altfallliste) und Text (mit Datei und Zeile).
    $sources = @()
    foreach ($dir in @('Packages', 'Application')) {
        $path = Join-Path $BaseDir $dir
        if (-not (Test-Path $path)) { continue }
        foreach ($file in Get-ChildItem -Path $path -Recurse -File -Include '*.pas') {
            $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            $role = Get-UnitRole $name $RoleScheme
            if ($null -eq $role) { continue }
            $relative = $file.FullName.Substring((Resolve-Path $BaseDir).Path.TrimEnd('\', '/').Length + 1) -replace '\\', '/'
            $text = Remove-PascalNoise ([IO.File]::ReadAllText($file.FullName))
            $sources += [pscustomobject]@{ Name = $name; Relative = $relative; Text = $text; Role = $role }
        }
    }
    $homes = @{}
    foreach ($unit in $sources) {
        foreach ($match in [regex]::Matches($unit.Text, '(?im)^\s*(I\w+)(?:\s*<[^>]*>)?\s*=\s*(?:disp)?interface\b(?!\s*;)')) {
            $key = $match.Groups[1].Value.ToLowerInvariant()
            if (-not $homes.ContainsKey($key)) { $homes[$key] = [Collections.Generic.List[string]]::new() }
            $homes[$key].Add($unit.Name)
        }
    }
    # Aliase (IAtlasIdeX = IAtlasX;) zählen wie das Interface, auf das sie zeigen.
    $aliases = @{}
    foreach ($unit in $sources) {
        foreach ($match in [regex]::Matches($unit.Text, '(?im)^\s*(I\w+)\s*=\s*(I\w+)\s*;')) {
            $aliases[$match.Groups[1].Value.ToLowerInvariant()] = $match.Groups[2].Value
        }
    }
    # Erster Durchgang: Klassen mit Vorfahr und den Interfaces aus anderen Units, die sie direkt implementieren.
    $classes = @()
    $byName = @{}
    $pattern = '(?is)(?<![\w.])(T\w+)(?:\s*<[^>]*>)?\s*=\s*class\s*(?:abstract\s*|sealed\s*)?\(([^)]*)\)'
    foreach ($unit in $sources) {
        $used = @{}
        foreach ($entry in Get-ClauseEntries $unit.Text 'uses') { $used[$entry.Name.ToLowerInvariant()] = $true }
        foreach ($match in [regex]::Matches($unit.Text, $pattern)) {
            $parts = @($match.Groups[2].Value -split ',' | ForEach-Object { ($_ -replace '<.*$', '').Trim() })
            $implemented = @()
            foreach ($part in $parts) {
                $interfaceName = $part
                for ($depth = 0; $depth -lt 5 -and -not $homes.ContainsKey($interfaceName.ToLowerInvariant()) -and
                    $aliases.ContainsKey($interfaceName.ToLowerInvariant()); $depth++) {
                    $interfaceName = $aliases[$interfaceName.ToLowerInvariant()]
                }
                $key = $interfaceName.ToLowerInvariant()
                if (-not $homes.ContainsKey($key) -or $homes[$key].Contains($unit.Name)) { continue }
                # Bei gleichnamigen Interfaces zählt die Unit, die die implementierende Unit verwendet; ein
                # eindeutiger Name gilt auch, wenn er über einen Alias in einer anderen Unit ankommt.
                $homeUnit = $homes[$key] | Where-Object { $used.ContainsKey($_.ToLowerInvariant()) } | Select-Object -First 1
                if (-not $homeUnit -and $homes[$key].Count -eq 1) { $homeUnit = $homes[$key][0] }
                if ($homeUnit) { $implemented += [pscustomobject]@{ Name = $interfaceName; Home = $homeUnit } }
            }
            $class = [pscustomobject]@{ Name = $match.Groups[1].Value; Unit = $unit; Ancestor = $parts[0]
                Line = ($unit.Text.Substring(0, $match.Index) -split "`n").Count; Implemented = $implemented }
            $classes += $class
            $key = $class.Name.ToLowerInvariant()
            if (-not $byName.ContainsKey($key)) { $byName[$key] = $class }
        }
    }
    $findings = @()
    $fitting = @{}
    foreach ($class in $classes) {
        $unit = $class.Unit
        $own = $unit.Role
        $ownFeature = Get-FeatureName $unit.Name
        if (-not $fitting.ContainsKey($unit.Name)) { $fitting[$unit.Name] = 0 }
        # Geerbte Interfaces zählen nur dafür, dass Adapters und Providers überhaupt etwas implementieren.
        $chain = @($class.Implemented)
        $ancestor = $class.Ancestor
        for ($depth = 0; $depth -lt 10 -and $byName.ContainsKey($ancestor.ToLowerInvariant()); $depth++) {
            $base = $byName[$ancestor.ToLowerInvariant()]
            $chain += $base.Implemented
            $ancestor = $base.Ancestor
        }
        foreach ($item in $chain) {
            $homeRole = Get-UnitRole $item.Home $RoleScheme
            $same = $own.Artefact -eq $homeRole.Artefact -and $own.Feature -eq $homeRole.Feature
            if ((Test-ContractUnit $item.Home) -and (($own.Role -eq 'Adapters' -and -not $same) -or ($own.Role -eq 'Providers' -and $same))) {
                $fitting[$unit.Name]++
            }
        }
        foreach ($item in $class.Implemented) {
            $homeRole = Get-UnitRole $item.Home $RoleScheme
            $same = $own.Role -ne 'Host' -and $homeRole.Role -ne 'Host' -and
                $own.Artefact -eq $homeRole.Artefact -and $own.Feature -eq $homeRole.Feature
            $where = "$($unit.Relative):$($class.Line)"
            $what = "$($class.Name) implementiert $($item.Name) aus $($item.Home)"
            $suffix = "$($unit.Name) $($class.Name) $($item.Name)"
            if (-not $same -and -not (Test-ContractUnit $item.Home)) {
                $findings += [pscustomobject]@{ Key = "contract $suffix"
                    Text = "${where}: $what – Interface eines Features, das andere implementieren, gehört in den Contract von $(Get-FeatureName $item.Home)" }
            }
            if ($own.Role -eq 'Adapters' -and $same) {
                $findings += [pscustomobject]@{ Key = "adapters-own $suffix"
                    Text = "${where}: $what – eigener Contract, das ist die Rolle Providers ($ownFeature.Providers.*)" }
            }
            elseif ($own.Role -eq 'Providers' -and -not $same) {
                $findings += [pscustomobject]@{ Key = "providers-foreign $suffix"
                    Text = "${where}: $what – fremdes Feature, das ist die Rolle Adapters ($ownFeature.Adapters.*)" }
            }
            elseif ($own.Role -in @('Root', 'Internals', 'Contract', 'Composition') -and -not $same) {
                $findings += [pscustomobject]@{ Key = "adapter-name $suffix"
                    Text = "${where}: $what – fremdes Feature, gehört in eine Unit $ownFeature.Adapters.*" }
            }
        }
    }
    foreach ($unit in $sources | Where-Object { $_.Role.Role -in @('Adapters', 'Providers') }) {
        if ($fitting.ContainsKey($unit.Name) -and $fitting[$unit.Name] -gt 0) { continue }
        $kind = 'einem fremden Contract'
        if ($unit.Role.Role -eq 'Providers') { $kind = 'dem eigenen Contract' }
        $findings += [pscustomobject]@{ Key = "empty $($unit.Name)"
            Text = "$($unit.Relative): $($unit.Role.Role) ohne Interface aus $kind" }
    }
    return $findings
}

$AdapterFindings = @(Get-AdapterRoleFindings $Root)
if ($UpdateAdapterRoles) {
    $keys = @($AdapterFindings | ForEach-Object { $_.Key } | Sort-Object -Unique)
    $header = "# Bekannte Altfälle der Rollen Adapters und Providers (#1443), geschrieben von`n" +
        "# pwsh Tools/Check-PackageDependencies.ps1 -UpdateAdapterRoles. Die Liste darf nur kürzer werden.`n"
    [IO.File]::WriteAllText($AdapterRolesFile, $header + (($keys | ForEach-Object { "$_`n" }) -join ''), [Text.UTF8Encoding]::new($false))
    Write-Host "Altfälle Adapters/Providers geschrieben: $($keys.Count)." -ForegroundColor Green
}
$AdapterKnown = @{}
if (Test-Path $AdapterRolesFile) {
    foreach ($entry in [IO.File]::ReadAllLines($AdapterRolesFile)) {
        if ($entry.Trim() -eq '' -or $entry.StartsWith('#')) { continue }
        $AdapterKnown[$entry.Trim()] = $false
    }
}
foreach ($finding in $AdapterFindings) {
    if ($AdapterKnown.ContainsKey($finding.Key)) { $AdapterKnown[$finding.Key] = $true; continue }
    $violations += $finding.Text
}
foreach ($entry in @($AdapterKnown.Keys | Where-Object { -not $AdapterKnown[$_] } | Sort-Object)) {
    $violations += "Tools/AdapterRoles.known.txt: $entry kommt nicht mehr vor; Zeile streichen"
}
if ($AdapterKnown.Count -gt 0) {
    Write-Host "Rollen Adapters/Providers: $($AdapterKnown.Count) bekannte Altfälle (Tools/AdapterRoles.known.txt)." -ForegroundColor Yellow
}

if ($violations.Count -gt 0) {
    Write-Host "Verstöße gegen die Package-Abhängigkeiten:" -ForegroundColor Red
    $violations | ForEach-Object { Write-Host "  $_" }
    exit 1
}

Write-Host 'Package-Abhängigkeiten in Ordnung.' -ForegroundColor Green
exit 0
