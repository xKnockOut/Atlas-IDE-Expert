unit Atlas.Common.Configuration.Features.Tests;

// Tests des Konfigurationsparsers für einzelne Funktionen (MCP, Aufgaben, Tracker, Compiler, Versionsverwaltung, Format).

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen einzelner Funktionen: MCP, Aufgaben, Tracker, Literale, Direktiven, Compiler, Versionsverwaltung und Format.</summary>
  [TestFixture]
  TConfigurationFeatureTests = class
  public
    [Test]
    procedure ReadsHints;
    [Test]
    procedure ReadsMcpDisabledTools;
    [Test]
    procedure ReadsMcpGlobalSettings;
    /// <summary>#1357: mcp.prompts, mcp.promptLanguage und eigene Prompts aus mcp.customPrompts.</summary>
    [Test]
    procedure ReadsMcpPrompts;
    /// <summary>#1357: Fehler in eigenen Prompts (Name, Text, include, Platzhalter) werden gemeldet.</summary>
    [Test]
    procedure ChecksMcpCustomPrompts;
    /// <summary>#1357: atlas.json mit nur mcp.customPrompts lässt das globale mcp.prompts stehen.</summary>
    [Test]
    procedure LayersMcpMembersSeparately;
    /// <summary>#900: Abschnitt "tasks" (Projektaufgaben des Plugins) wird geprüft, nicht gemeldet.</summary>
    [Test]
    procedure ChecksTasks;
    /// <summary>#1260: issues.connections (Tracker-Verbindungen des Plugins) wird geprüft: nur https, ohne
    /// Benutzer, eindeutige Namen.</summary>
    [Test]
    procedure ChecksIssueConnections;
    /// <summary>#1261: issues.projects (Zuordnung Delphi-Projekt → Tracker-Projekt) wird geprüft: match und
    /// connection nötig, ein Pfad nur einmal (ohne Groß-/Kleinschreibung, „/“ wie „\“).</summary>
    [Test]
    procedure ChecksIssueProjects;
    /// <summary>#1262: issues.queries mit Name und Abfrage, doppelte Namen und fehlende Angaben gemeldet.</summary>
    [Test]
    procedure ChecksIssueQueries;
    /// <summary>#1266: Zustand je Verbindung (stateField, assigneeField, startState, endStates) ohne Meldung;
    /// falsche Typen werden gemeldet.</summary>
    [Test]
    procedure ChecksIssueConnectionStates;
    [Test]
    procedure ReadsStringLiteral;
    [Test]
    procedure ReadsDirectives;
    [Test]
    procedure ReadsMemberOrder;
    [Test]
    procedure ReadsTestUnits;
    [Test]
    procedure ReadsDfmPropertyRules;
    [Test]
    procedure ReadsCompilerSettings;
    /// <summary>#1904: Alte Einträge "backend": "ide" und "ideCommand" melden keinen Fehler; ide gilt als off.
    /// </summary>
    [Test]
    procedure IgnoresRemovedIdeBackend;
    [Test]
    procedure ReadsVcsProvider;
    /// <summary>#1285: vcs.git.path, vcs.svn.path und vcs.timeoutSeconds (1 bis 300).</summary>
    [Test]
    procedure ReadsVcsToolPathsAndTimeout;
    [Test]
    procedure ReadsFormatSettings;
    [Test]
    procedure FileOverridesEditorPerKey;
    [Test]
    procedure MergesRulesPerId;
    /// <summary>excludeTests global für alle Projekte; eine atlas.json, die den Schlüssel nennt, geht vor.</summary>
    [Test]
    procedure ExcludeTestsGlobalOrProject;
    [Test]
    procedure EditorOrFileAlone;
    [Test]
    procedure ReadsDefaultEncoding;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.TestSupport;

{ TConfigurationParserTests }

procedure TConfigurationFeatureTests.FileOverridesEditorPerKey;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.ParseLayered(
    '{"serverPath": "C:\\Bin\\AtlasServer.exe", "platform": "Win32", "config": "Release", "language": "en"}',
    '{ // Datei gewinnt'#10' "platform": "Win64", "language": "de" }', Issues);
  Assert.AreEqual('Win64', Settings.Platform);
  Assert.AreEqual('de', Settings.Language);
  Assert.AreEqual('Release', Settings.Config);
  // Unbekannte Editor-Schlüssel wie serverPath erzeugen keine Meldung.
  Assert.AreEqual(0, Integer(Length(Issues)));
end;
procedure TConfigurationFeatureTests.MergesRulesPerId;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Settings := TConfigurationParser.ParseLayered(
    '{"rules": {"with-statement": "error", "unused-variable": "hint"}}',
    '{"rules": {"with-statement": "off"}}', Issues);
  Assert.IsTrue(Settings.RuleSeverity('with-statement', TRuleSeverity.Warning) = TRuleSeverity.Off);
  Assert.IsTrue(Settings.RuleSeverity('unused-variable', TRuleSeverity.Warning) = TRuleSeverity.Hint);
end;
procedure TConfigurationFeatureTests.ExcludeTestsGlobalOrProject;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.IsTrue(TConfigurationParser.ParseLayered('{"excludeTests": true}', '{"platform": "Win64"}',
    Issues).ExcludeTests);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"excludeTests": true}', '{"excludeTests": false}',
    Issues).ExcludeTests);
  Assert.IsTrue(TConfigurationParser.ParseLayered('', '{"excludeTests": true}', Issues).ExcludeTests);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"platform": "Win32"}', '', Issues).ExcludeTests);
end;
procedure TConfigurationFeatureTests.EditorOrFileAlone;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual('Win32', TConfigurationParser.ParseLayered('{"platform": "Win32"}', '', Issues).Platform);
  Assert.AreEqual('Win64', TConfigurationParser.ParseLayered('', '{"platform": "Win64"}', Issues).Platform);
  // Ohne Angabe entscheidet der Client (#1458).
  Assert.AreEqual('', TConfigurationParser.ParseLayered('', '', Issues).Language);
  // Meldungen gelten nur der Datei.
  TConfigurationParser.ParseLayered('{"language": "fr"}', '{"language": "xx"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
procedure TConfigurationFeatureTests.ReadsDefaultEncoding;
var
  Issues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(65001, Parse('{}', Issues).DefaultEncoding);
  Assert.AreEqual(1250, Parse('{"encoding": "windows-1250"}', Issues).DefaultEncoding);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(65001, Parse('{"encoding": "utf-8"}', Issues).DefaultEncoding);
  // Unbekannte Kodierung: Meldung, es bleibt UTF-8.
  Assert.AreEqual(65001, Parse('{"encoding": "klingonisch"}', Issues).DefaultEncoding);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // atlas.json hat Vorrang vor dem Editor.
  Assert.AreEqual(1252, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{"encoding": "cp1252"}',
    Issues).DefaultEncoding);
  Assert.AreEqual(1250, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{}', Issues).DefaultEncoding);
end;
{ TServerSettingsTests }

procedure TConfigurationFeatureTests.ReadsFormatSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(2, Settings.Formatting.IndentSize);
  Assert.IsTrue(Settings.Formatting.Given = []);
  Settings := Parse('{"format": {"useTabs": true, "keywordCase": "lower", "endOfLine": "crlf", ' +
    '"spaceAfterComma": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Formatting.UseTabs);
  Assert.IsTrue(Settings.Formatting.KeywordCase = TKeywordCase.Lower);
  Assert.AreEqual(#13#10, Settings.Formatting.EndOfLine);
  Assert.IsFalse(Settings.Formatting.SpaceAfterComma);
  Assert.IsTrue(Settings.Formatting.Given = [TFormatKey.UseTabs, TFormatKey.KeywordCase, TFormatKey.EndOfLine,
    TFormatKey.SpaceAfterComma]);
  Settings := Parse('{"format": {"indentSize": 0, "keywordCase": "camel", "x": 1}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Formatting.Given = []);
  // Blockstruktur, Stellung, Umbruch und Ausrichtung (#43).
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Formatting.Reindent);
  Assert.IsTrue(Settings.Formatting.BeginPlacement = TBlockPlacement.Preserve);
  Assert.AreEqual(0, Settings.Formatting.MaxLineLength);
  Settings := Parse('{"format": {"reindent": false, "beginPlacement": "newLine", "elsePlacement": "sameLine", ' +
    '"maxLineLength": 100, "alignAssignments": true, "alignDeclarations": true, "alignComments": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Formatting.Reindent);
  Assert.IsTrue(Settings.Formatting.BeginPlacement = TBlockPlacement.NewLine);
  Assert.IsTrue(Settings.Formatting.ElsePlacement = TBlockPlacement.SameLine);
  Assert.AreEqual(100, Settings.Formatting.MaxLineLength);
  Assert.IsTrue(Settings.Formatting.AlignAssignments);
  Assert.IsTrue(Settings.Formatting.AlignDeclarations);
  Assert.IsTrue(Settings.Formatting.AlignComments);
  Assert.IsTrue(Settings.Formatting.Given = [TFormatKey.MaxLineLength]);
  Parse('{"format": {"beginPlacement": "below", "maxLineLength": -1}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;
procedure TConfigurationFeatureTests.ReadsVcsProvider;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Versionsverwaltung (#571): Vorgabe auto.
  Settings := Parse('{}', Issues);
  Assert.AreEqual('auto', Settings.VcsProvider);
  Settings := Parse('{"vcs": {"provider": "svn"}}', Issues);
  Assert.AreEqual('svn', Settings.VcsProvider);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"vcs": {"provider": "cvs", "x": 1}}', Issues);
  Assert.AreEqual('auto', Settings.VcsProvider, 'unbekannter Wert bleibt bei der Vorgabe');
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"vcs": "git"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'vcs muss ein Objekt sein');
  Settings := TConfigurationParser.ParseLayered('{"vcs": {"provider": "git"}}', '{"vcs": {"provider": "off"}}',
    Issues);
  Assert.AreEqual('off', Settings.VcsProvider, 'Datei vor Editor');
  Settings := TConfigurationParser.ParseLayered('', '{"vcs": {"provider": "git"}}', Issues);
  Assert.AreEqual('git', Settings.VcsProvider);
end;
procedure TConfigurationFeatureTests.ReadsVcsToolPathsAndTimeout;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual('', Settings.VcsGitPath, 'leer = automatisch suchen');
  Assert.AreEqual('', Settings.VcsSvnPath);
  Assert.AreEqual(15, Settings.VcsTimeoutSeconds);
  Settings := Parse('{"vcs": {"git": {"path": "D:\\Portable\\Git\\cmd\\git.exe"}, ' +
    '"svn": {"path": "C:\\Programme\\TortoiseSVN\\bin\\svn.exe"}, "timeoutSeconds": 60}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('D:\Portable\Git\cmd\git.exe', Settings.VcsGitPath);
  Assert.AreEqual('C:\Programme\TortoiseSVN\bin\svn.exe', Settings.VcsSvnPath);
  Assert.AreEqual(60, Settings.VcsTimeoutSeconds);
  Settings := Parse('{"vcs": {"timeoutSeconds": 0}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'unter 1');
  Assert.AreEqual(15, Settings.VcsTimeoutSeconds, 'ungültig: Vorgabe');
  Parse('{"vcs": {"timeoutSeconds": 301}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'über 300');
  Parse('{"vcs": {"timeoutSeconds": "30"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'Text statt Zahl');
  Settings := Parse('{"vcs": {"git": "git.exe", "svn": {"pfad": "svn.exe"}}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)), 'git muss ein Objekt sein, svn.pfad unbekannt');
  Assert.AreEqual('', Settings.VcsGitPath);
  Assert.AreEqual('', Settings.VcsSvnPath);
  Settings := TConfigurationParser.ParseLayered('{"vcs": {"timeoutSeconds": 30}}',
    '{"vcs": {"provider": "svn", "svn": {"path": "s.exe"}}}', Issues);
  Assert.AreEqual('svn', Settings.VcsProvider, 'Datei vor Editor');
  Assert.AreEqual('s.exe', Settings.VcsSvnPath);
  Assert.AreEqual(15, Settings.VcsTimeoutSeconds, 'die Datei bestimmt den ganzen Abschnitt vcs');
  // #1286: vcs.projects wird geprüft und als Text weitergegeben.
  Settings := Parse('{"vcs": {"projects": [{"match": "C:\\Kasse", "provider": "svn"}, ' +
    '{"match": "C:\\Kasse\\Lib", "provider": "git", "mainBranch": "develop"}]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.Contains(Settings.VcsProjects, '"develop"');
  Parse('{"vcs": {"projects": [{"match": "c:/kasse/"}, {"match": "C:\\Kasse"}, {"provider": "cvs"}, 3, ' +
    '{"match": "C:\\X", "mainBranch": "mein branch", "y": 1}]}}', Issues);
  Assert.AreEqual(6, Integer(Length(Issues)),
    'doppelter Pfad, unbekannte Art, ohne match, kein Objekt, Leerzeichen im Branch, unbekannte Angabe');
  Parse('{"vcs": {"projects": {}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
end;
/// <summary>Einstellungen ab „Vorgabe aus: Das Plugin wählt „Nach dem Speichern“ selbst“.</summary>
procedure ReadsCompilerOnSaveAndSlashCommands;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Vorgabe aus: Das Plugin wählt „Nach dem Speichern“ selbst.
  Settings := Parse('{}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
  Settings := Parse('{"compiler": {"onSave": true}}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"compiler": {"onSave": "nein", "x": 1}}', Issues);
  Assert.IsFalse(Settings.Compiler.OnSave);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"compiler": {"onSave": true}}', '{}', Issues);
  Assert.IsTrue(Settings.Compiler.OnSave);
  // Weg zum Compiler (#261): Vorgabe auto.
  Settings := Parse('{}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(Settings.Compiler.Backend));
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"compiler": {"backend": "off"}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Off), Ord(Settings.Compiler.Backend));
  Settings := Parse('{"compiler": {"backend": "dcc"}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Dcc), Ord(Settings.Compiler.Backend));
  Settings := Parse('{"compiler": {"backend": "msbuild"}}', Issues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(Settings.Compiler.Backend), 'ungültig = Vorgabe');
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Schnellbefehle (#293)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.SlashCommands);
  Assert.AreEqual(0, Integer(Length(Settings.SlashCommandsDisabled)));
  Settings := Parse('{"slashCommands": {"enabled": false, "disabled": ["uses", "var"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.SlashCommands);
  Assert.AreEqual('var', Settings.SlashCommandsDisabled[1]);
  Parse('{"slashCommands": {"disabled": "uses", "x": 1}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"slashCommands": {"disabled": ["uses"]}}', '{}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.SlashCommandsDisabled)));
  // Alias usesCommand aus #254: Vorgabe an, false schaltet /uses ab, atlas.json überdeckt den Editor.
  Assert.IsTrue(Parse('{}', Issues).UsesCommand);
  Settings := Parse('{"usesCommand": false}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.UsesCommand);
  Parse('{"usesCommand": "nein"}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"usesCommand": true}', '{"usesCommand": false}', Issues);
  Assert.IsFalse(Settings.UsesCommand, 'atlas.json gilt vor den Editor-Einstellungen');
end;
/// <summary>Einstellungen ab „Gerüst des Dokumentationskommentars (#88)“.</summary>
procedure ReadsDocCommentAndCompletion;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Gerüst des Dokumentationskommentars (#88)
  Assert.IsTrue(Parse('{}', Issues).CompleteBlocksDocComment);
  Settings := Parse('{"completeBlocks": {"docComment": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.CompleteBlocksDocComment);
  Parse('{"completeBlocks": {"docComment": 1, "x": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"completeBlocks": true}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"completeBlocks": {"docComment": false}}', '{}', Issues);
  Assert.IsFalse(Settings.CompleteBlocksDocComment);
  // Protokollaufruf für /log und /except (#304)
  Assert.AreEqual('', Parse('{}', Issues).SlashLogCall);
  Settings := Parse('{"slashCommands": {"logCall": "Log.Debug"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Log.Debug', Settings.SlashLogCall);
  Settings := Parse('{"slashCommands": {"logCall": 3}}', Issues);
  Assert.AreEqual('', Settings.SlashLogCall);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"slashCommands": {"logCall": "Log.Debug"}}', '{}', Issues);
  Assert.AreEqual('Log.Debug', Settings.SlashLogCall);
  // Palettenseite für /component (#299)
  Assert.AreEqual('Eigene', Parse('{}', Issues).SlashComponentPalette);
  Assert.AreEqual('Firma', Parse('{"slashCommands": {"componentPalette": "Firma"}}', Issues).SlashComponentPalette);
  // #297: Name und Kategorie für /todo, ungenutzte uses bei /sortuses.
  Settings := Parse('{"slashCommands": {"todoOwner": "Marco", "todoCategory": "Review", ' +
    '"sortUsesRemoveUnused": false}}', Issues);
  Assert.AreEqual('Marco', Settings.SlashTodoOwner);
  Assert.AreEqual('Review', Settings.SlashTodoCategory);
  Assert.IsFalse(Settings.SlashSortUsesRemoveUnused);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{}', Issues).SlashSortUsesRemoveUnused);
  Assert.AreEqual('', Parse('{}', Issues).SlashTodoOwner);
  // #875: /helper für Aufzählungen
  Assert.IsTrue(Parse('{}', Issues).SlashEnumHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"enumHelper": false}}', Issues).SlashEnumHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"enumHelper": false}}', '{}',
    Issues).SlashEnumHelper);
  Assert.IsTrue(Parse('{}', Issues).SlashSetHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"setHelper": false}}', Issues).SlashSetHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"setHelper": false}}', '{}',
    Issues).SlashSetHelper);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Vervollständigung (#229)
  Assert.IsTrue(Parse('{}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.IsTrue(Parse('{"completion": {"matching": "prefix"}}', Issues).Completion.Matching = TCompletionMatching.Prefix);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"matching": "egal", "x": 1}}', Issues).Completion.Matching = TCompletionMatching.Fuzzy);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „Abschnitt für Interface-Methoden (#466)“.</summary>
procedure ReadsInterfaceSectionAndConversions;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Abschnitt für Interface-Methoden (#466)
  Assert.IsTrue(Parse('{}', Issues).Completion.InterfaceSection = TCompletionInterfaceSection.Public);
  Assert.IsTrue(Parse('{"completion": {"interfaceSection": "protected"}}', Issues).Completion.InterfaceSection =
    TCompletionInterfaceSection.Protected);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"interfaceSection": "strict"}}', Issues).Completion.InterfaceSection =
    TCompletionInterfaceSection.Public);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Typumwandlung von Sender (#480)
  Assert.IsTrue(Parse('{}', Issues).Completion.SenderCast = TCompletionSenderCast.AsOperator);
  Assert.IsTrue(Parse('{"completion": {"senderCast": "cast"}}', Issues).Completion.SenderCast =
    TCompletionSenderCast.HardCast);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"senderCast": "hart"}}', Issues).Completion.SenderCast =
    TCompletionSenderCast.AsOperator);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Typkonvertierung vorschlagen (#490, experimentell)
  Assert.IsTrue(Parse('{}', Issues).Completion.TypeConversion = TCompletionTypeConversion.Off);
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "helper"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Helper);
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "function"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Function_);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"typeConversion": "immer"}}', Issues).Completion.TypeConversion =
    TCompletionTypeConversion.Off);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Alle Felder zuweisen (#491, experimentell)
  Assert.IsFalse(Parse('{}', Issues).Completion.AssignAllFields);
  Assert.IsTrue(Parse('{"completion": {"assignAllFields": true}}', Issues).Completion.AssignAllFields);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"assignAllFields": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // uses-Vervollständigung mit Gruppen und Hinweisen (#469)
  Assert.IsTrue(Parse('{}', Issues).Completion.UsesDetails);
  Assert.IsFalse(Parse('{"completion": {"usesDetails": false}}', Issues).Completion.UsesDetails);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"usesDetails": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Vollständiger inherited-Aufruf (#482)
  Assert.IsTrue(Parse('{}', Issues).Completion.InheritedCall);
  Assert.IsFalse(Parse('{"completion": {"inheritedCall": false}}', Issues).Completion.InheritedCall);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"inheritedCall": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Attribute nach "[" (#465)
  Assert.IsTrue(Parse('{}', Issues).Completion.Attributes);
  Assert.IsFalse(Parse('{"completion": {"attributes": false}}', Issues).Completion.Attributes);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"attributes": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „Anonyme Methoden (#468)“.</summary>
procedure ReadsAnonymousMethodsAndKeywords;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Anonyme Methoden (#468)
  Assert.IsTrue(Parse('{}', Issues).Completion.AnonymousMethods);
  Assert.IsFalse(Parse('{"completion": {"anonymousMethods": false}}', Issues).Completion.AnonymousMethods);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"anonymousMethods": 0}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Herkunft in with-Blöcken (#481)
  Assert.IsTrue(Parse('{}', Issues).Completion.WithOrigin);
  Assert.IsFalse(Parse('{"completion": {"withOrigin": false}}', Issues).Completion.WithOrigin);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"withOrigin": "nein"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Exception-Klassen (#483)
  Assert.IsTrue(Parse('{}', Issues).Completion.ExceptionClasses);
  Assert.IsFalse(Parse('{"completion": {"exceptionClasses": false}}', Issues).Completion.ExceptionClasses);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"exceptionClasses": []}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Hinweis bei unvollständigem Code (#457)
  Assert.IsTrue(Parse('{}', Issues).Completion.SyntaxNotice);
  Assert.IsFalse(Parse('{"completion": {"syntaxNotice": false}}', Issues).Completion.SyntaxNotice);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"syntaxNotice": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Gleiche Namen aus verschiedenen Units (#475)
  Assert.IsTrue(Parse('{}', Issues).Completion.SameNameVariants);
  Assert.IsTrue(Parse('{}', Issues).Completion.SameNameInsert = TCompletionSameNameInsert.Prefix);
  Assert.IsFalse(Parse('{}', Issues).Completion.ShowFmxUnits);
  Assert.IsFalse(Parse('{"completion": {"sameNameVariants": false}}', Issues).Completion.SameNameVariants);
  Assert.IsTrue(Parse('{"completion": {"sameNameInsert": "uses"}}', Issues).Completion.SameNameInsert =
    TCompletionSameNameInsert.Uses_);
  Assert.IsTrue(Parse('{"completion": {"showFmxUnits": true}}', Issues).Completion.ShowFmxUnits);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"sameNameInsert": "move"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Typprüfungen (#2107)
  Assert.IsTrue(Parse('{}', Issues).Completion.TypeGuards);
  Assert.IsFalse(Parse('{"completion": {"typeGuards": false}}', Issues).Completion.TypeGuards);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"typeGuards": "aus"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Nicht sichtbare Mitglieder (#2108)
  Assert.IsTrue(Parse('{}', Issues).Completion.HiddenMembers);
  Assert.IsFalse(Parse('{"completion": {"hiddenMembers": false}}', Issues).Completion.HiddenMembers);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Freigabe absichern (#489)
  Assert.IsTrue(Parse('{}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{}', Issues).Completion.FreeStyle = TCompletionFreeStyle.Free);
  Assert.IsFalse(Parse('{"completion": {"offerTryFinally": false}}', Issues).Completion.OfferTryFinally);
  Assert.IsTrue(Parse('{"completion": {"freeStyle": "freeAndNil"}}', Issues).Completion.FreeStyle =
    TCompletionFreeStyle.FreeAndNil);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"completion": {"freeStyle": "nil"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Schlüsselwörter (#31)
  Assert.IsTrue(Parse('{}', Issues).Completion.Keywords);
  Assert.IsFalse(Parse('{"completion": {"keywords": false}}', Issues).Completion.Keywords);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Postfix-Vorlagen und Inline-Variablen (#188)
  Assert.IsTrue(Parse('{}', Issues).Completion.PostfixTemplates);
  Assert.IsFalse(Parse('{"completion": {"postfixTemplates": false}}', Issues).Completion.PostfixTemplates);
  // Typargumente nach den Constraints (#450)
  Assert.IsTrue(Parse('{}', Issues).Completion.GenericConstraints);
  Assert.IsFalse(Parse('{"completion": {"genericConstraints": false}}', Issues).Completion.GenericConstraints);
end;
/// <summary>Einstellungen ab „Namensvorschläge (#452)“.</summary>
procedure ReadsNameSuggestionsAndRefactorings;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Namensvorschläge (#452)
  Assert.IsTrue(Parse('{}', Issues).Completion.NameSuggestions);
  Assert.IsFalse(Parse('{"completion": {"nameSuggestions": false}}', Issues).Completion.NameSuggestions);
  // Feld und Zugriffsmethoden nach read/write (#467)
  Assert.IsTrue(Parse('{}', Issues).Completion.CreateAccessors);
  Assert.IsFalse(Parse('{"completion": {"createAccessors": false}}', Issues).Completion.CreateAccessors);
  Assert.IsTrue(Parse('{}', Issues).Completion.AccessorSection = TCompletionAccessorSection.Private);
  Assert.IsTrue(Parse('{"completion": {"accessorSection": "protected"}}', Issues).Completion.AccessorSection =
    TCompletionAccessorSection.Protected);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{"completion": {"accessorSection": "public"}}', Issues).Completion.AccessorSection =
    TCompletionAccessorSection.Private);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // String als resourcestring auslagern (#473)
  Assert.IsTrue(Parse('{}', Issues).Completion.ResourceStrings);
  Assert.IsFalse(Parse('{"completion": {"resourceStrings": false}}', Issues).Completion.ResourceStrings);
  Assert.AreEqual('', Parse('{}', Issues).Completion.ResourceStringUnit);
  Assert.AreEqual('App.Texte', Parse('{"completion": {"resourceStringUnit": "App.Texte"}}',
    Issues).Completion.ResourceStringUnit);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('', Parse('{"completion": {"resourceStringUnit": "App Texte"}}',
    Issues).Completion.ResourceStringUnit);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InlineVar);
  Assert.IsFalse(Parse('{"refactoring": {"inlineVar": false}}', Issues).Refactoring.InlineVar);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"inlineVars": false}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Signatur ändern (#100)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ChangeSignature);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.NewParameterOverload);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.VirtualOverload);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.SyncSignatures);
  Assert.IsFalse(Parse('{"refactoring": {"changeSignature": false}}', Issues).Refactoring.ChangeSignature);
  Assert.IsFalse(Parse('{"refactoring": {"newParameter": "updateCallers"}}', Issues).Refactoring.NewParameterOverload);
  Assert.IsTrue(Parse('{"refactoring": {"virtualOverload": true}}', Issues).Refactoring.VirtualOverload);
  Assert.IsFalse(Parse('{"refactoring": {"syncSignatures": false}}', Issues).Refactoring.SyncSignatures);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ForwardDeclaration);
  Assert.IsFalse(Parse('{"refactoring": {"forwardDeclaration": false}}', Issues).Refactoring.ForwardDeclaration);
  // try/finally und Klassen-Aktionen (#42)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.TryFinally);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ClassActions);
  Assert.IsFalse(Parse('{"refactoring": {"tryFinally": false}}', Issues).Refactoring.TryFinally);
  Assert.IsFalse(Parse('{"refactoring": {"classActions": false}}', Issues).Refactoring.ClassActions);
  // Typ ausschreiben (#453)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ExplicitType);
  Assert.IsFalse(Parse('{"refactoring": {"explicitType": false}}', Issues).Refactoring.ExplicitType);
  // Schnellkorrekturen an Compilermeldungen (#549)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CompilerFixes);
  Assert.IsFalse(Parse('{"refactoring": {"compilerFixes": false}}', Issues).Refactoring.CompilerFixes);
  // Unit nicht gefunden: Suchpfad ergänzen (#550)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MissingUnit);
  Assert.IsFalse(Parse('{"refactoring": {"missingUnit": false}}', Issues).Refactoring.MissingUnit);
end;
/// <summary>Einstellungen ab „Warnung gezielt abschalten (#531)“.</summary>
procedure ReadsWarningsAndCodeActions;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // Warnung gezielt abschalten (#531)
  Assert.IsTrue(Parse('{}', Issues).Refactoring.DisableWarning);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.DisableWarningReason);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarning": false}}', Issues).Refactoring.DisableWarning);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarningReason": false}}', Issues).Refactoring.DisableWarningReason);
  // #50: Extrahieren, case vervollständigen und with auflösen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.Extract);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CompleteCase);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ResolveWith);
  Assert.IsFalse(Parse('{"refactoring": {"extract": false}}', Issues).Refactoring.Extract);
  Assert.IsFalse(Parse('{"refactoring": {"completeCase": false}}', Issues).Refactoring.CompleteCase);
  Assert.IsFalse(Parse('{"refactoring": {"resolveWith": false}}', Issues).Refactoring.ResolveWith);
  // #103: Einbetten, experimentell und daher aus.
  Assert.IsFalse(Parse('{}', Issues).Refactoring.InlineCode);
  Assert.IsTrue(Parse('{"refactoring": {"inline": true}}', Issues).Refactoring.InlineCode);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.MoveClass);
  Assert.IsTrue(Parse('{"refactoring": {"moveClass": true}}', Issues).Refactoring.MoveClass);
  // #512: uses nachziehen, experimentell und daher "off".
  Assert.IsFalse(Parse('{}', Issues).Refactoring.UnitRenameFollowUp);
  Assert.IsTrue(Parse('{"refactoring": {"unitRenameFollowUp": "ask"}}', Issues).Refactoring.UnitRenameFollowUp);
  Assert.IsFalse(Parse('{"refactoring": {"unitRenameFollowUp": "off"}}', Issues).Refactoring.UnitRenameFollowUp);
  Parse('{"refactoring": {"unitRenameFollowUp": "yes"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #472: Methode aus Aufruf anlegen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.CreateMethod);
  Assert.AreEqual('private', Parse('{}', Issues).Refactoring.CreateMethodSection);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.CreateMethodCaretInBody);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ConstParameters);
  Assert.IsFalse(Parse('{"refactoring": {"createMethod": false}}', Issues).Refactoring.CreateMethod);
  Assert.AreEqual('protected', Parse('{"refactoring": {"createMethodSection": "Protected"}}',
    Issues).Refactoring.CreateMethodSection);
  Assert.IsTrue(Parse('{"refactoring": {"createMethodCaret": "body"}}', Issues).Refactoring.CreateMethodCaretInBody);
  Assert.IsFalse(Parse('{"refactoring": {"constParameters": false}}', Issues).Refactoring.ConstParameters);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"newParameter": "default"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"refactoring": {"createMethodSection": "published", "createMethodCaret": "ende"}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  // #682: Property aus Getter und Setter.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Get|Set|Is|Has', string.Join('|', Parse('{}', Issues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('ask', Parse('{}', Issues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('accessor', Parse('{}', Issues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('off', Parse('{}', Issues).Refactoring.PropertyFromAccessorsHideAccessors);
  Assert.IsFalse(Parse('{"refactoring": {"propertyFromAccessors": false}}', Issues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Read|Write', string.Join('|', Parse('{"refactoring": {"propertyFromAccessorsPrefixes": ' +
    '["Read", " Write ", ""]}}', Issues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('always', Parse('{"refactoring": {"propertyFromAccessorsReplaceCalls": "Always"}}',
    Issues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('published', Parse('{"refactoring": {"propertyFromAccessorsSection": "published"}}',
    Issues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('protected', Parse('{"refactoring": {"propertyFromAccessorsHideAccessors": "protected"}}',
    Issues).Refactoring.PropertyFromAccessorsHideAccessors);
end;
/// <summary>Einstellungen ab „#666: Felder im Destruktor freigeben“.</summary>
procedure ReadsFreeFieldsAndConditions;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // #666: Felder im Destruktor freigeben.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.FreeFields);
  Assert.AreEqual('free', Parse('{}', Issues).Refactoring.FreeFieldsStyle);
  Assert.IsFalse(Parse('{"refactoring": {"freeFields": false}}', Issues).Refactoring.FreeFields);
  Assert.AreEqual('freeAndNil', Parse('{"refactoring": {"freeFieldsStyle": "FreeAndNil"}}',
    Issues).Refactoring.FreeFieldsStyle);
  // #712: Als Konstante deklarieren.
  Assert.IsFalse(Parse('{}', Issues).Refactoring.SuggestConst);
  Assert.IsTrue(Parse('{"refactoring": {"suggestConst": true}}', Issues).Refactoring.SuggestConst);
  // #644: var-Block pflegen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.VarBlock);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.VarBlockMerge);
  Assert.AreEqual('usage', Parse('{}', Issues).Refactoring.VarBlockSort);
  Assert.IsFalse(Parse('{"refactoring": {"varBlock": false}}', Issues).Refactoring.VarBlock);
  Assert.IsFalse(Parse('{"refactoring": {"varBlockMerge": false}}', Issues).Refactoring.VarBlockMerge);
  Assert.AreEqual('alpha', Parse('{"refactoring": {"varBlockSort": "Alpha"}}', Issues).Refactoring.VarBlockSort);
  Assert.AreEqual('usage', Parse('{"refactoring": {"varBlockSort": "quer"}}', Issues).Refactoring.VarBlockSort);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #715: Boolean umkehren.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InvertBoolean);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('Not', Parse('{}', Issues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual(0, Integer(Length(Parse('{}', Issues).Refactoring.InvertBooleanAntonyms)));
  Assert.IsFalse(Parse('{"refactoring": {"invertBoolean": false}}', Issues).Refactoring.InvertBoolean);
  Assert.IsFalse(Parse('{"refactoring": {"invertBooleanIncludeDfm": false}}',
    Issues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('No', Parse('{"refactoring": {"invertBooleanFallbackPrefix": "No"}}',
    Issues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual('Verbose=Silent', string.Join(',', Parse('{"refactoring": {"invertBooleanAntonyms": ' +
    '{"Verbose": "Silent"}}}', Issues).Refactoring.InvertBooleanAntonyms));
  // #646: if-Kette und case.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.IfCase);
  Assert.IsFalse(Parse('{"refactoring": {"ifCase": false}}', Issues).Refactoring.IfCase);
  // #656: Bedingungen umformen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.Conditions);
  Assert.IsFalse(Parse('{"refactoring": {"conditions": false}}', Issues).Refactoring.Conditions);
  // #684: if-Anweisung und Bedingungsausdruck.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ConditionalExpression);
  Assert.IsFalse(Parse('{"refactoring": {"conditionalExpression": false}}', Issues).Refactoring.ConditionalExpression);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.NestedRoutine);
  Assert.IsFalse(Parse('{"refactoring": {"nestedRoutine": false}}', Issues).Refactoring.NestedRoutine);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.PromoteVariable);
  Assert.IsFalse(Parse('{"refactoring": {"promoteVariable": false}}', Issues).Refactoring.PromoteVariable);
  // #680: anonyme Methode und Methode.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.AnonymousMethod);
  Assert.IsFalse(Parse('{"refactoring": {"anonymousMethod": false}}', Issues).Refactoring.AnonymousMethod);
  Assert.AreEqual('forward', Parse('{}', Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual('fields', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "Fields"}}',
    Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('forward', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "felder"}}',
    Issues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „#686: Methode ohne Self“.</summary>
procedure ReadsMethodWithoutSelfAndTypes;
var
  Issues: TArray<TConfigurationIssue>;
begin
  // #686: Methode ohne Self.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKind);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKindMarker);
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MethodKindStatic);
  Assert.IsFalse(Parse('{"refactoring": {"methodKind": false}}', Issues).Refactoring.MethodKind);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindMarker": false}}', Issues).Refactoring.MethodKindMarker);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindStatic": false}}', Issues).Refactoring.MethodKindStatic);
  // #681: Typ-Alias.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.TypeAlias);
  Assert.IsFalse(Parse('{"refactoring": {"typeAlias": false}}', Issues).Refactoring.TypeAlias);
  Assert.AreEqual('unit', Parse('{}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual('project', Parse('{"refactoring": {"typeAliasScope": "Project"}}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('unit', Parse('{"refactoring": {"typeAliasScope": "datei"}}', Issues).Refactoring.TypeAliasScope);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #667: Aufzählung mit Namenstabelle.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.EnumTables);
  Assert.IsFalse(Parse('{}', Issues).Refactoring.EnumTablesResourceStrings);
  Assert.IsFalse(Parse('{"refactoring": {"enumTables": false}}', Issues).Refactoring.EnumTables);
  Assert.IsTrue(Parse('{"refactoring": {"enumTablesResourceStrings": true}}',
    Issues).Refactoring.EnumTablesResourceStrings);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // #674: Überladung anlegen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.Overloads);
  Assert.IsFalse(Parse('{"refactoring": {"overloads": false}}', Issues).Refactoring.Overloads);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"refactoring": {"propertyFromAccessorsPrefixes": "Get", "propertyFromAccessorsReplaceCalls": "ja", ' +
    '"propertyFromAccessorsSection": "private", "propertyFromAccessorsHideAccessors": "public"}}', Issues);
  Assert.AreEqual(4, Integer(Length(Issues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": ["Hidden"], "invertBooleanFallbackPrefix": "nicht gut"}}',
    Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": {"Hidden": "1x"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #664: Interface aus Klasse herauslösen.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.ExtractInterface);
  Assert.IsFalse(Parse('{"refactoring": {"extractInterface": false}}', Issues).Refactoring.ExtractInterface);
  Parse('{"refactoring": {"extractInterface": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
/// <summary>Einstellungen der Umbauten an Mitgliedern: verschieben (#675), Zugriffsmethode durch Feld ersetzen (#717),
/// Sichtbarkeit anheben (#2108).</summary>
procedure ReadsMemberRefactorings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // #675: Mitglied verschieben.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.MoveMember);
  Assert.IsFalse(Parse('{"refactoring": {"moveMember": false}}', Issues).Refactoring.MoveMember);
  Parse('{"refactoring": {"moveMember": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #717: Zugriffsmethode durch Feld ersetzen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.InlineAccessor);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorBulk);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorDiagnostic);
  Settings := Parse('{"refactoring": {"inlineAccessor": false, "inlineAccessorEqualityCheck": false, ' +
    '"inlineAccessorBulk": false, "inlineAccessorDiagnostic": true}}', Issues);
  Assert.IsFalse(Settings.Refactoring.InlineAccessor);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsFalse(Settings.Refactoring.InlineAccessorBulk);
  Assert.IsTrue(Settings.Refactoring.InlineAccessorDiagnostic);
  Parse('{"refactoring": {"inlineAccessorBulk": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // #2108: Sichtbarkeit anheben.
  Assert.IsTrue(Parse('{}', Issues).Refactoring.RaiseVisibility);
  Assert.IsFalse(Parse('{"refactoring": {"raiseVisibility": false}}', Issues).Refactoring.RaiseVisibility);
  Parse('{"refactoring": {"raiseVisibility": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;

/// <summary>Einstellungen ab „#713: Basisklasse herauslösen“.</summary>
procedure ReadsExtractBaseClassAndDelete;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // #713: Basisklasse herauslösen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('sameUnit', Settings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Base', Settings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('move', Settings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('protected', Settings.Refactoring.ExtractSuperclassRaiseVisibility);
  Settings := Parse('{"refactoring": {"extractSuperclass": false, "extractSuperclassTarget": "newunit", ' +
    '"extractSuperclassNameSuffix": "Custom", "extractSuperclassMethodMode": "Abstract", ' +
    '"extractSuperclassRaiseVisibility": "strictprotected"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('newUnit', Settings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Custom', Settings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('abstract', Settings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('strictProtected', Settings.Refactoring.ExtractSuperclassRaiseVisibility);
  Parse('{"refactoring": {"extractSuperclassTarget": "otherUnit", "extractSuperclassNameSuffix": "1x", ' +
    '"extractSuperclassMethodMode": "copy", "extractSuperclassRaiseVisibility": "public"}}', Issues);
  Assert.AreEqual(4, Integer(Length(Issues)));
  // #716: Sicher löschen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.SafeDelete);
  Assert.IsFalse(Settings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteIncludeOverrides);
  Settings := Parse('{"refactoring": {"safeDelete": false, "safeDeletePreviewWhenUnused": true, ' +
    '"safeDeleteCascade": "Always", "safeDeleteIncludeOverrides": "never"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Refactoring.SafeDelete);
  Assert.IsTrue(Settings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('always', Settings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('never', Settings.Refactoring.SafeDeleteIncludeOverrides);
  Settings := Parse('{"refactoring": {"safeDeleteCascade": "manchmal"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual('ask', Settings.Refactoring.SafeDeleteCascade);
  // #2054: Methode extrahieren mit gleichen Stellen.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Refactoring.ExtractMethodDuplicates);
  Settings := Parse('{"refactoring": {"extractMethodDuplicates": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Refactoring.ExtractMethodDuplicates);
  Parse('{"refactoring": {"extractMethodDuplicates": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „Speicherbudget (#185)“.</summary>
procedure ReadsBudgetAndTimeLimits;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Speicherbudget (#185)
  Assert.AreEqual(768, Parse('{}', Issues).MemoryBudgetMb, 'Vorgabe 768 MB (Rückmeldung 15.10.2026)');
  Assert.AreEqual(0, Parse('{"memoryBudgetMb": 0}', Issues).MemoryBudgetMb, '0 = unbegrenzt');
  Assert.AreEqual(512, Parse('{"memoryBudgetMb": 512}', Issues).MemoryBudgetMb);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(768, Parse('{"memoryBudgetMb": -1}', Issues).MemoryBudgetMb);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"memoryBudgetMb": 100}', '{"memoryBudgetMb": 200}', Issues);
  Assert.AreEqual(200, Settings.MemoryBudgetMb);
  // Zeitlimit für Anfragen (#283)
  Assert.AreEqual(10000, Parse('{}', Issues).RequestTimeoutMs);
  Assert.AreEqual(30000, Parse('{"requestTimeoutMs": 30000}', Issues).RequestTimeoutMs);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(10000, Parse('{"requestTimeoutMs": 10}', Issues).RequestTimeoutMs);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Absturzfälle und Sicherheitsnetz (#1355)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.ServerCrashCases and Settings.ServerCrashSkip);
  Settings := Parse('{"server": {"crashCases": false, "crashSkip": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.ServerCrashCases or Settings.ServerCrashSkip);
  Settings := Parse('{"server": {"crashSkip": 1, "gibts": true}}', Issues);
  Assert.IsTrue(Settings.ServerCrashSkip);
  Assert.AreEqual(2, Integer(Length(Issues)), 'kein Wahrheitswert und unbekannter Schlüssel');
  // Statusdatei je Server (#1901)
  Assert.IsTrue(Parse('{}', Issues).ServerStatusFile);
  Assert.IsFalse(Parse('{"server": {"statusFile": false}}', Issues).ServerStatusFile);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Diagnoselog (#647)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.DiagnosticsLog);
  Assert.AreEqual(7, Settings.DiagnosticsLogDays);
  Assert.IsFalse(Settings.DiagnosticsLogMapFile);
  Settings := Parse('{"diagnostics": {"log": false, "logDays": 3, "logMapFile": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.DiagnosticsLog);
  Assert.AreEqual(3, Settings.DiagnosticsLogDays);
  Assert.IsTrue(Settings.DiagnosticsLogMapFile);
  Assert.AreEqual(7, Parse('{"diagnostics": {"logDays": 0, "x": 1}}', Issues).DiagnosticsLogDays);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"diagnostics": {"log": false}}', '{"diagnostics": {"logDays": 2}}', Issues);
  Assert.IsTrue(Settings.DiagnosticsLog, 'atlas.json ersetzt den ganzen Abschnitt');
  Assert.AreEqual(2, Settings.DiagnosticsLogDays);
  // Fremde Quellen im Editor (diagnostics.librarySources)
  Assert.IsFalse(Parse('{}', Issues).DiagnosticsLibrarySources);
  Assert.IsTrue(Parse('{"diagnostics": {"librarySources": true}}', Issues).DiagnosticsLibrarySources);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Parse('{"diagnostics": {"librarySources": "ja"}}', Issues).DiagnosticsLibrarySources);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „Umfang des Index (#648)“.</summary>
procedure ReadsIndexScope;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Umfang des Index (#648)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.IndexProjectGroup and Settings.IndexSearchPaths);
  Assert.IsFalse(Settings.IndexLibraryPaths, 'Bibliothekspfade nur auf Wunsch (Dauer)');
  Assert.IsTrue(Settings.IndexUsages, 'Verwendungen standardmäßig an (#492)');
  Assert.AreEqual<NativeInt>(0, Length(Settings.IndexExclude));
  Settings := Parse('{"index": {"projectGroup": false, "searchPaths": false, "libraryPaths": false, ' +
    '"usages": false, "exclude": ["**/Demos/**"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.IndexProjectGroup or Settings.IndexSearchPaths or Settings.IndexLibraryPaths);
  Assert.IsFalse(Settings.IndexUsages);
  Parse('{"index": {"usages": "ja"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsTrue(Settings.IsIndexExcluded('C:\Komponenten\Demos\Main.pas'));
  Assert.IsFalse(Settings.IsIndexExcluded('C:\Komponenten\Source\Main.pas'));
  Parse('{"index": {"exclude": "Demos", "x": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"index": {"searchPaths": false}}', '{"index": {"exclude": []}}', Issues);
  Assert.IsTrue(Settings.IndexSearchPaths, 'atlas.json ersetzt den ganzen Abschnitt');
  // Aufräumen des Cache-Ordners (#905)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.IndexRemoveOrphans, 'verwaiste Caches standardmäßig löschen');
  Assert.AreEqual(14, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(1024, Settings.IndexCacheMaxMb);
  Settings := Parse('{"index": {"removeOrphans": false, "cacheMaxAgeDays": 0, "cacheMaxMb": 2048}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.IndexRemoveOrphans);
  Assert.AreEqual(0, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(2048, Settings.IndexCacheMaxMb);
  Settings := Parse('{"index": {"removeOrphans": 1, "cacheMaxAgeDays": -1, "cacheMaxMb": "viel"}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.IndexRemoveOrphans);
  Assert.AreEqual(14, Settings.IndexCacheMaxAgeDays);
  Assert.AreEqual(1024, Settings.IndexCacheMaxMb);
  Settings := TConfigurationParser.ParseLayered('{"index": {"cacheMaxAgeDays": 30}}', '{}', Issues);
  Assert.AreEqual(30, Settings.IndexCacheMaxAgeDays);
  // Schlüsselworthervorhebung (#307)
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Highlight.BlockPairs and Settings.Highlight.Directives and Settings.Highlight.ExitPoints);
  Assert.AreEqual(4, Integer(Length(Settings.Highlight.ExitKeywords)));
  Settings := Parse('{"highlight": {"exitPoints": false, "exitKeywords": ["Exit", "Fail"]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Highlight.ExitPoints);
  Assert.IsTrue(Settings.Highlight.BlockPairs);
  Assert.AreEqual('Fail', Settings.Highlight.ExitKeywords[1]);
  Parse('{"highlight": {"blockPairs": 1, "foo": true}}', Issues);
  Assert.AreEqual(2, Integer(Length(Issues)));
end;
/// <summary>Einstellungen ab „Protokoll (#265)“.</summary>
procedure ReadsProtocolSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  // Protokoll (#265)
  Assert.AreEqual('info', Parse('{}', Issues).LogLevel);
  Settings := Parse('{"logLevel": "debug", "logFile": "C:\\Log\\lsp.log", "traceFile": "t.json"}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('debug', Settings.LogLevel);
  Assert.AreEqual('C:\Log\lsp.log', Settings.LogFile);
  Assert.AreEqual('t.json', Settings.TraceFile);
  Assert.AreEqual('info', Parse('{"logLevel": "laut"}', Issues).LogLevel);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"logLevel": "error"}', '{"logLevel": "warning"}', Issues);
  Assert.AreEqual('warning', Settings.LogLevel);
end;

procedure TConfigurationFeatureTests.IgnoresRemovedIdeBackend;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"compiler": {"backend": "ide", "ideCommand": "C:\\Werkzeug\\bau.ps1"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'alter Wert ohne Meldung');
  Assert.AreEqual(Ord(TCompilerBackendSetting.Off), Ord(Settings.Compiler.Backend));
  // Auch ein Eintrag falschen Typs wird übergangen.
  Settings := Parse('{"compiler": {"ideCommand": 3}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(Settings.Compiler.Backend));
  Issues := nil;
end;

procedure TConfigurationFeatureTests.ReadsCompilerSettings;
begin
  ReadsCompilerOnSaveAndSlashCommands;
  ReadsDocCommentAndCompletion;
  ReadsInterfaceSectionAndConversions;
  ReadsAnonymousMethodsAndKeywords;
  ReadsNameSuggestionsAndRefactorings;
  ReadsWarningsAndCodeActions;
  ReadsFreeFieldsAndConditions;
  ReadsMethodWithoutSelfAndTypes;
  ReadsExtractBaseClassAndDelete;
  ReadsMemberRefactorings;
  ReadsBudgetAndTimeLimits;
  ReadsIndexScope;
  ReadsProtocolSettings;
end;
procedure TConfigurationFeatureTests.ReadsStringLiteral;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(Settings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.SLineBreak), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(0, Settings.StringLiteral.MaxLineLength);
  Settings := Parse('{"stringLiteral": {"style": "concat", "lineBreak": "#13#10", "maxLineLength": 100}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TStringLiteralStyle.Concat), Ord(Settings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.CrLf), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(100, Settings.StringLiteral.MaxLineLength);
  Settings := Parse('{"stringLiteral": {"style": "kurz", "lineBreak": "space", "maxLineLength": -1, "x": 1}}', Issues);
  // Ungültiger Stil und negative Länge (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.AreEqual(Ord(TStringLiteralBreak.Space), Ord(Settings.StringLiteral.LineBreak));
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(Settings.StringLiteral.Style));
end;
procedure TConfigurationFeatureTests.ReadsDirectives;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Directives.Completion);
  Assert.IsTrue(Settings.Directives.Hover);
  Settings := Parse('{"directives": {"completion": false, "hover": false}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Directives.Completion);
  Assert.IsFalse(Settings.Directives.Hover);
  Parse('{"directives": {"x": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Parse('{"directives": 1}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
end;
procedure TConfigurationFeatureTests.ReadsDfmPropertyRules;
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  Assert.AreEqual(0, Integer(Length(Parse('{}', Issues).DfmPropertyRules)));
  Settings := Parse('{"dfmPropertyRules": [' +
    '{"class": "TLabel", "property": "Transparent", "condition": "=", "value": "True", "fix": "auto"},' +
    '{"class": "TForm", "property": "Position", "condition": "<>", "value": "poDesigned", "message": "Zentriert",' +
    ' "severity": "hint", "includeDescendants": false, "exclude": ["**/Alt/*.dfm"]},' +
    '{"class": "TEdit", "property": "Hint", "condition": "notEmpty", "fix": "none"}]}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual(3, Integer(Length(Settings.DfmPropertyRules)));
  Assert.AreEqual('TLabel', Settings.DfmPropertyRules[0].ClassName);
  Assert.AreEqual('Transparent', Settings.DfmPropertyRules[0].PropertyPath);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Condition = TDfmCondition.Equal);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Fix = TDfmFixMode.Auto);
  Assert.IsTrue(Settings.DfmPropertyRules[0].Severity = TRuleSeverity.Warning);
  Assert.IsTrue(Settings.DfmPropertyRules[0].IncludeDescendants);
  Assert.IsTrue(Settings.DfmPropertyRules[1].Condition = TDfmCondition.NotEqual);
  Assert.IsTrue(Settings.DfmPropertyRules[1].Severity = TRuleSeverity.Hint);
  Assert.IsFalse(Settings.DfmPropertyRules[1].IncludeDescendants);
  Assert.AreEqual('Zentriert', Settings.DfmPropertyRules[1].Message);
  Assert.AreEqual('**/Alt/*.dfm', Settings.DfmPropertyRules[1].Exclude[0]);
  Assert.IsTrue(Settings.DfmPropertyRules[2].Condition = TDfmCondition.NotEmpty);
  Assert.IsTrue(Settings.DfmPropertyRules[2].Fix = TDfmFixMode.None);
  // Fehlerhafte Regeln: ohne property, = ohne value, unbekannte Bedingung, unbekannter Schlüssel.
  Settings := Parse('{"dfmPropertyRules": [{"class": "TLabel"}, {"class": "TA", "property": "B", "condition": "="},' +
    ' {"class": "TA", "property": "B", "condition": "gleich", "value": "1", "x": 1}, 5]}', Issues);
  Assert.AreEqual(5, Integer(Length(Issues)));
  Assert.AreEqual(1, Integer(Length(Settings.DfmPropertyRules)));
  Parse('{"dfmPropertyRules": {}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Editor zuerst, die Datei hat Vorrang.
  Settings := TConfigurationParser.ParseLayered('{"dfmPropertyRules": []}',
    '{"dfmPropertyRules": [{"class": "TA", "property": "B", "value": "1"}]}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.DfmPropertyRules)));
end;
procedure TConfigurationFeatureTests.ReadsMemberOrder;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(6, Integer(Length(Settings.MemberOrder.Sections)));
  Assert.AreEqual('field', Settings.MemberOrder.Members[0]);
  Assert.IsFalse(Settings.MemberOrder.SortFields);
  Settings := Parse('{"memberOrder": {"sections": ["public", "private"], "members": ["method", "field"], ' +
    '"sortFields": true, "sortPublished": true}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('public', Settings.MemberOrder.Sections[0]);
  Assert.AreEqual('method', Settings.MemberOrder.Members[0]);
  Assert.IsTrue(Settings.MemberOrder.SortFields);
  Assert.IsTrue(Settings.MemberOrder.SortPublished);
  Parse('{"memberOrder": {"sections": ["intern"], "x": 1}}', Issues);
  // Unbekannte Sichtbarkeit (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(2, Integer(Length(Issues)));
end;
procedure TConfigurationFeatureTests.ReadsTestUnits;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual('{unit}.Tests', Settings.TestUnits.Pattern);
  Assert.AreEqual('', Settings.TestUnits.Folder);
  Assert.AreEqual('', Settings.TestUnits.Project);
  Settings := Parse('{"testUnits": {"pattern": "Test.{unit}", "folder": "Tests/Unit", ' +
    '"project": "Tests/Tests.dproj"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.AreEqual('Test.{unit}', Settings.TestUnits.Pattern);
  Assert.AreEqual('Tests/Unit', Settings.TestUnits.Folder);
  Assert.AreEqual('Tests/Tests.dproj', Settings.TestUnits.Project);
  Settings := Parse('{"testUnits": {"pattern": "Tests", "project": "Tests.exe", "x": 1}}', Issues);
  // Muster ohne {unit} und Projekt ohne .dproj/.dpr (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.AreEqual('{unit}.Tests', Settings.TestUnits.Pattern, 'ungültiges Muster bleibt bei der Vorgabe');
end;
procedure TConfigurationFeatureTests.ReadsMcpGlobalSettings;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.McpGlobalSettings, 'Vorgabe: globale Datei lesen');
  Settings := Parse('{"mcp": {"globalSettings": false}}', Issues);
  Assert.IsFalse(Settings.McpGlobalSettings);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Settings := Parse('{"mcp": {"globalSettings": "nein"}}', Issues);
  Assert.IsTrue(Settings.McpGlobalSettings, 'Ungültiger Wert lässt die Vorgabe');
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := TConfigurationParser.ParseLayered('{"mcp": {"globalSettings": true}}',
    '{"mcp": {"globalSettings": false}}', Issues);
  Assert.IsFalse(Settings.McpGlobalSettings, 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ReadsMcpPrompts;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.McpPrompts, 'Vorgabe: Prompts an');
  Assert.AreEqual('de', mSettings.McpPromptLanguage);
  Assert.AreEqual(0, Integer(Length(mSettings.McpCustomPrompts)));
  mSettings := Parse('{"mcp": {"prompts": false, "promptLanguage": "en", "customPrompts": [' +
    '{"name": "check_unit", "description": "Unit prüfen", "arguments": [{"name": "unit", "description": "Unit", ' +
    '"required": true}, {"name": "focus"}], "text": "Prüfe {unit} mit Blick auf {focus}.", ' +
    '"include": ["diagnostics", "metrics"]}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.McpPrompts);
  Assert.AreEqual('en', mSettings.McpPromptLanguage);
  Assert.AreEqual(1, Integer(Length(mSettings.McpCustomPrompts)));
  Assert.AreEqual('check_unit', mSettings.McpCustomPrompts[0].Name);
  Assert.AreEqual('Unit prüfen', mSettings.McpCustomPrompts[0].Description);
  Assert.AreEqual(2, Integer(Length(mSettings.McpCustomPrompts[0].Arguments)));
  Assert.IsTrue(mSettings.McpCustomPrompts[0].Arguments[0].Required);
  Assert.IsFalse(mSettings.McpCustomPrompts[0].Arguments[1].Required, 'Vorgabe: kein Pflichtargument');
  Assert.AreEqual('Prüfe {unit} mit Blick auf {focus}.', mSettings.McpCustomPrompts[0].Text);
  Assert.AreEqual(2, Integer(Length(mSettings.McpCustomPrompts[0].Include)));
  Assert.AreEqual('metrics', mSettings.McpCustomPrompts[0].Include[1]);
end;
procedure TConfigurationFeatureTests.ChecksMcpCustomPrompts;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"mcp": {"promptLanguage": "fr"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'nur de oder en');
  Assert.AreEqual('de', mSettings.McpPromptLanguage, 'ungültige Sprache lässt die Vorgabe');
  Parse('{"mcp": {"customPrompts": {"name": "a"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
  // Ohne Text, Name mit Leerzeichen, unbekannter Inhalt, doppelter Name.
  mSettings := Parse('{"mcp": {"customPrompts": [{"name": "ohne_text"}, {"name": "mit leer", "text": "x"}, ' +
    '{"name": "a", "text": "x", "include": ["metrics", "wetter"]}, {"name": "A", "text": "y"}]}}', mIssues);
  Assert.AreEqual(4, Integer(Length(mIssues)), 'ohne Text, ungültiger Name, unbekannter Inhalt, doppelter Name');
  Assert.AreEqual(1, Integer(Length(mSettings.McpCustomPrompts)), 'nur der gültige Prompt a');
  Assert.AreEqual(1, Integer(Length(mSettings.McpCustomPrompts[0].Include)), 'unbekannter Inhalt fällt weg');
  // Platzhalter ohne Argument: nur eine Warnung, der Prompt gilt.
  mSettings := Parse('{"mcp": {"customPrompts": [{"name": "b", "text": "Prüfe {unit}."}]}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError, 'Platzhalter ohne Argument ist eine Warnung');
  Assert.AreEqual(1, Integer(Length(mSettings.McpCustomPrompts)));
end;
procedure TConfigurationFeatureTests.LayersMcpMembersSeparately;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := TConfigurationParser.ParseLayered('{"mcp": {"prompts": false, "disabledTools": ["a"]}}',
    '{"mcp": {"customPrompts": [{"name": "c", "text": "x"}]}}', mIssues);
  Assert.IsFalse(mSettings.McpPrompts, 'mcp.prompts aus der globalen Ebene bleibt');
  Assert.AreEqual(1, Integer(Length(mSettings.McpDisabledTools)), 'mcp.disabledTools aus der globalen Ebene bleibt');
  Assert.AreEqual(1, Integer(Length(mSettings.McpCustomPrompts)), 'mcp.customPrompts aus der Datei');
  mSettings := TConfigurationParser.ParseLayered('{"mcp": {"promptLanguage": "en"}}',
    '{"mcp": {"promptLanguage": "de"}}', mIssues);
  Assert.AreEqual('de', mSettings.McpPromptLanguage, 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksTasks;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"tasks": [{"name": "Delphi-12-Prüfung", "command": "pwsh", "args": ["Tools/Check-Delphi12.ps1"],' +
    ' "cwd": "${projectDir}", "group": "check", "matcher": "pwsh", "key": "Ctrl+Alt+1", "timeoutSec": 300,' +
    ' "beforeBuild": "block", "env": {"NO_COLOR": "1"}},' +
    ' {"name": "Fremd", "command": "lint.exe", "matcher": {"regex": "^(?<file>[^:]+):(?<line>\\d+) (?<message>.*)$",' +
    ' "severity": "warning", "severityMap": {"SCHLIMM": "error"}}}]}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(Settings.Tasks.StartsWith('['), Settings.Tasks);
  Parse('{"tasks": [{"name": "A", "command": "x", "group": "lint", "matcher": "eslint", "timeoutSec": -1,' +
    ' "beforeBuild": "stop", "foo": 1}, {"name": "a", "command": ""}, {"command": "y"}, 3,' +
    ' {"name": "M", "command": "z", "matcher": {"severityMap": {"X": "fatal"}}}]}', Issues);
  // group, matcher, timeoutSec, beforeBuild, foo; Doppelname a und leerer command; ohne name; 3; Muster ohne regex
  // und severityMap-Wert.
  Assert.AreEqual(11, Integer(Length(Issues)));
  Parse('{"tasks": {"name": "A"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Settings := TConfigurationParser.ParseLayered('{"tasks": []}', '{"tasks": [{"name": "B", "command": "b"}]}',
    Issues);
  Assert.IsTrue(Settings.Tasks.Contains('"B"'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueConnections;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack",' +
    ' "url": "https://youtrack.firma.local"}, {"name": "GitHub", "provider": "github", "url": "https://github.com"}]}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(Settings.IssueConnections.StartsWith('['), Settings.IssueConnections);
  Assert.IsTrue(Settings.IssueConnections.Contains('"Firma"'), Settings.IssueConnections);
  Parse('{"issues": {"connections": [{"name": "A", "provider": "youtrack", "url": "http://yt.local"},' +
    ' {"name": "a", "provider": "github", "url": "https://user@github.com"}, {"provider": "", "url": 3, "token": "x"},' +
    ' 3], "queries": []}}', Issues);
  // http; Doppelname a und Benutzer in der Adresse; url kein String, token unbekannt, ohne name, ohne provider (leer)
  // und ohne url; 3. queries ist seit #1262 bekannt.
  Assert.AreEqual(9, Integer(Length(Issues)));
  // Sprache der Oberfläche (#1263): de oder en.
  Parse('{"issues": {"connections": [{"name": "A", "provider": "youtrack", "url": "https://yt.local",' +
    ' "language": "de"}, {"name": "B", "provider": "youtrack", "url": "https://yt2.local", "language": "fr"}]}}',
    Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'nur "fr"');
  Parse('{"issues": {"connections": {"name": "A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Parse('{"issues": []}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'kein Objekt');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"connections": [{"name": "B", "provider": "github",' +
    ' "url": "https://github.com"}]}}', Issues);
  Assert.IsTrue(Settings.IssueConnections.Contains('"B"'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueProjects;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"projects": [{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", ' +
    '"connection": "Firma", "project": "KASSE"}, {"match": "C:\\Projekte\\Atlas", "connection": "GitHub"}]}}',
    Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'Beispiel aus dem Issue ohne Meldung; project darf fehlen');
  Assert.IsTrue(Settings.IssueProjects.StartsWith('['), Settings.IssueProjects);
  Assert.IsTrue(Settings.IssueProjects.Contains('"KASSE"'), Settings.IssueProjects);
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma"}, ' +
    '{"match": "c:/a/", "connection": "GitHub"}, {"connection": 3, "project": 4, "x": 1}, 3]}}', Issues);
  // Pfad doppelt; connection kein String, project kein String, x unbekannt, ohne match, ohne connection; 3.
  Assert.AreEqual(7, Integer(Length(Issues)));
  Parse('{"issues": {"projects": {"match": "C:\\A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  // Arbeitskopien (#1926): Liste von Ordnern; anderes meldet der Server einmal.
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma", ' +
    '"paths": ["D:\\SVN\\A\\trunk", "D:\\SVN\\B"]}]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'paths als Liste ohne Meldung');
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma", "paths": "D:\\SVN"}]}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'paths keine Liste');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"projects": [{"match": "C:\\B", ' +
    '"connection": "Firma"}]}}', Issues);
  Assert.IsTrue(Settings.IssueProjects.Contains('Firma'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueQueries;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{"issues": {"queries": [{"name": "Mir zugewiesen", "query": "assignee: meine #Ungelöst"}, ' +
    '{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)), 'connection und project dürfen fehlen');
  Assert.IsTrue(Settings.IssueQueries.StartsWith('['), Settings.IssueQueries);
  Assert.IsTrue(Settings.IssueQueries.Contains('"Sprint"'), Settings.IssueQueries);
  Parse('{"issues": {"queries": [{"name": "A", "query": "x"}, {"name": "a", "query": ""}, ' +
    '{"connection": 3, "x": 1}, 3]}}', Issues);
  // Name doppelt, query leer; connection kein String, x unbekannt, ohne name, ohne query; 3.
  Assert.AreEqual(7, Integer(Length(Issues)));
  Parse('{"issues": {"queries": {"name": "A"}}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)), 'keine Liste');
  Settings := TConfigurationParser.ParseLayered('{}', '{"issues": {"queries": [{"name": "B", "query": "y"}]}}',
    Issues);
  Assert.IsTrue(Settings.IssueQueries.Contains('"B"'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueConnectionStates;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack",' +
    ' "url": "https://youtrack.firma.local", "stateField": "Status", "assigneeField": "Zuständig",' +
    ' "startState": "In Arbeit", "endStates": ["Zur Prüfung", "Erledigt"]}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Felder aus #1266 ohne Meldung');
  Assert.IsTrue(mSettings.IssueConnections.Contains('"endStates"'), mSettings.IssueConnections);
  Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack", "url": "https://yt.local",' +
    ' "stateField": 3, "endStates": "Erledigt"}, {"name": "B", "provider": "github", "url": "https://github.com",' +
    ' "endStates": ["Erledigt", 4]}]}}', mIssues);
  // stateField keine Zeichenkette, endStates keine Liste, 4 kein Text.
  Assert.AreEqual(3, Integer(Length(mIssues)));
  // #2126: reviewStates wie endStates.
  Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack", "url": "https://yt.local",' +
    ' "reviewStates": ["Zur Prüfung"]}, {"name": "B", "provider": "github", "url": "https://github.com",' +
    ' "reviewStates": "QA"}]}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].Message.Contains('reviewStates'), mIssues[0].Message);
end;
procedure TConfigurationFeatureTests.ReadsMcpDisabledTools;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(0, Integer(Length(Settings.McpDisabledTools)));
  Settings := Parse('{"mcp": {"disabledTools": ["rename_symbol", 3], "x": 1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Settings.McpDisabledTools)));
  Assert.AreEqual('rename_symbol', Settings.McpDisabledTools[0]);
  Assert.AreEqual(2, Integer(Length(Issues)), 'Zahl in der Liste und unbekannter Schlüssel');
  Settings := TConfigurationParser.ParseLayered('{"mcp": {"disabledTools": ["a"]}}',
    '{"mcp": {"disabledTools": ["b"]}}', Issues);
  Assert.AreEqual('b', Settings.McpDisabledTools[0], 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ReadsHints;
var
  Settings: TServerSettings;
  Issues: TArray<TConfigurationIssue>;
begin
  Settings := Parse('{}', Issues);
  Assert.AreEqual(THintSettings.cExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  // published-Mitglieder im Hover (#110).
  Assert.IsTrue(Settings.Hints.PublishedMembers);
  Assert.IsFalse(Parse('{"hints": {"publishedMembers": false}}', Issues).Hints.PublishedMembers);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Parse('{"hints": {"publishedMembers": 0}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Settings := Parse('{"hints": {"xmlDocExpand": "collapsed", "xmlDocMaxLines": 10}}', Issues);
  Assert.AreEqual(THintSettings.cExpandCollapsed, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(10, Settings.Hints.XmlDocMaxLines);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Außerhalb 0–50 bzw. falsch getypt (Fehler), unbekannter Schlüssel (Warnung); Vorgaben bleiben.
  Settings := Parse('{"hints": {"xmlDocMaxLines": 51, "xmlDocExpand": "auf", "x": 1}}', Issues);
  Assert.AreEqual(0, Settings.Hints.XmlDocMaxLines);
  Assert.AreEqual(THintSettings.cExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Issues[0].IsError);
  Assert.IsTrue(Issues[1].IsError);
  Assert.IsFalse(Issues[2].IsError);
  Parse('{"hints": {"xmlDocMaxLines": -1}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  // Veraltetes xmlDocFull (#770): true = expanded, false = collapsed, mit Warnung; xmlDocExpand gewinnt.
  Settings := Parse('{"hints": {"xmlDocFull": false}}', Issues);
  Assert.AreEqual(THintSettings.cExpandCollapsed, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.IsFalse(Issues[0].IsError);
  Settings := Parse('{"hints": {"xmlDocFull": true}}', Issues);
  Assert.AreEqual(THintSettings.cExpandExpanded, Settings.Hints.XmlDocExpand);
  Settings := Parse('{"hints": {"xmlDocExpand": "last", "xmlDocFull": false}}', Issues);
  Assert.AreEqual(THintSettings.cExpandLast, Settings.Hints.XmlDocExpand);
  // Die Datei ersetzt den Block aus dem Editor (IDE-Plugin).
  Settings := TConfigurationParser.ParseLayered('{"hints": {"xmlDocExpand": "collapsed"}}',
    '{"hints": {"xmlDocMaxLines": 5}}', Issues);
  Assert.AreEqual(THintSettings.cExpandLast, Settings.Hints.XmlDocExpand);
  Assert.AreEqual(5, Settings.Hints.XmlDocMaxLines);
  // Begründungen (#1123): Schalter, Marken, ADR-Ordner.
  Settings := Parse('{}', Issues);
  Assert.IsTrue(Settings.Hints.Rationale);
  Assert.AreEqual(0, Integer(Length(Settings.Hints.RationaleMarkers)));
  Assert.AreEqual('', Settings.Hints.AdrFolder);
  Settings := Parse('{"hints": {"rationale": false, "rationaleMarkers": ["WHY", " PERF "], ' +
    '"adrFolder": "doc/decisions"}}', Issues);
  Assert.AreEqual(0, Integer(Length(Issues)));
  Assert.IsFalse(Settings.Hints.Rationale);
  Assert.AreEqual('WHY PERF', string.Join(' ', Settings.Hints.RationaleMarkers));
  Assert.AreEqual('doc/decisions', Settings.Hints.AdrFolder);
  Settings := Parse('{"hints": {"rationale": "ja", "rationaleMarkers": ["WHY", ""], "adrFolder": 3}}', Issues);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.IsTrue(Settings.Hints.Rationale);
  Settings := Parse('{"hints": {"rationaleMarkers": "WHY"}}', Issues);
  Assert.AreEqual(1, Integer(Length(Issues)));
  Assert.AreEqual(0, Integer(Length(Settings.Hints.RationaleMarkers)));
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigurationFeatureTests);

end.
