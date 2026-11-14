unit Atlas.Common.Configuration.Features.Tests;

// Tests des Konfigurationsparsers für einzelne Funktionen (MCP, Aufgaben, Tracker, Compiler, Versionsverwaltung,
// Format).

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen einzelner Funktionen: MCP, Aufgaben, Tracker, Literale, Direktiven, Compiler,
  /// Versionsverwaltung und Format.</summary>
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
    /// <summary>#2167: Abschnitt "testLists" (Testlisten des Plugins) wird geprüft, nicht gemeldet.</summary>
    [Test]
    procedure ChecksTestLists;
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
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.ParseLayered(
    '{"serverPath": "C:\\Bin\\AtlasServer.exe", "platform": "Win32", "config": "Release", "language": "en"}',
    '{ // Datei gewinnt'#10' "platform": "Win64", "language": "de" }', mIssues);
  Assert.AreEqual('Win64', mSettings.Platform);
  Assert.AreEqual('de', mSettings.Language);
  Assert.AreEqual('Release', mSettings.Config);
  // Unbekannte Editor-Schlüssel wie serverPath erzeugen keine Meldung.
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;
procedure TConfigurationFeatureTests.MergesRulesPerId;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.ParseLayered(
    '{"rules": {"with-statement": "error", "unused-variable": "hint"}}',
    '{"rules": {"with-statement": "off"}}', mIssues);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Off, mSettings.RuleSeverity('with-statement', TRuleSeverity.Warning));
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mSettings.RuleSeverity('unused-variable', TRuleSeverity.Warning));
end;
procedure TConfigurationFeatureTests.ExcludeTestsGlobalOrProject;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.IsTrue(TConfigurationParser.ParseLayered('{"excludeTests": true}', '{"platform": "Win64"}',
    mIssues).ExcludeTests);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"excludeTests": true}', '{"excludeTests": false}',
    mIssues).ExcludeTests);
  Assert.IsTrue(TConfigurationParser.ParseLayered('', '{"excludeTests": true}', mIssues).ExcludeTests);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"platform": "Win32"}', '', mIssues).ExcludeTests);
end;
procedure TConfigurationFeatureTests.EditorOrFileAlone;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual('Win32', TConfigurationParser.ParseLayered('{"platform": "Win32"}', '', mIssues).Platform);
  Assert.AreEqual('Win64', TConfigurationParser.ParseLayered('', '{"platform": "Win64"}', mIssues).Platform);
  // Ohne Angabe entscheidet der Client (#1458).
  Assert.AreEqual('', TConfigurationParser.ParseLayered('', '', mIssues).Language);
  // Meldungen gelten nur der Datei.
  TConfigurationParser.ParseLayered('{"language": "fr"}', '{"language": "xx"}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
procedure TConfigurationFeatureTests.ReadsDefaultEncoding;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Assert.AreEqual(65001, Parse('{}', mIssues).DefaultEncoding);
  Assert.AreEqual(1250, Parse('{"encoding": "windows-1250"}', mIssues).DefaultEncoding);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(65001, Parse('{"encoding": "utf-8"}', mIssues).DefaultEncoding);
  // Unbekannte Kodierung: Meldung, es bleibt UTF-8.
  Assert.AreEqual(65001, Parse('{"encoding": "klingonisch"}', mIssues).DefaultEncoding);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // atlas.json hat Vorrang vor dem Editor.
  Assert.AreEqual(1252, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{"encoding": "cp1252"}',
    mIssues).DefaultEncoding);
  Assert.AreEqual(1250, TConfigurationParser.ParseLayered('{"encoding": "1250"}', '{}', mIssues).DefaultEncoding);
end;
{ TServerSettingsTests }

procedure TConfigurationFeatureTests.ReadsFormatSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(2, mSettings.Formatting.IndentSize);
  Assert.AreEqual<TFormatKeys>([], mSettings.Formatting.Given);
  mSettings := Parse('{"format": {"useTabs": true, "keywordCase": "lower", "endOfLine": "crlf", ' +
    '"spaceAfterComma": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.Formatting.UseTabs);
  Assert.AreEqual<TKeywordCase>(TKeywordCase.Lower, mSettings.Formatting.KeywordCase);
  Assert.AreEqual(#13#10, mSettings.Formatting.EndOfLine);
  Assert.IsFalse(mSettings.Formatting.SpaceAfterComma);
  Assert.AreEqual<TFormatKeys>([TFormatKey.UseTabs, TFormatKey.KeywordCase, TFormatKey.EndOfLine,
    TFormatKey.SpaceAfterComma], mSettings.Formatting.Given);
  mSettings := Parse('{"format": {"indentSize": 0, "keywordCase": "camel", "x": 1}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.AreEqual<TFormatKeys>([], mSettings.Formatting.Given);
  // Blockstruktur, Stellung, Umbruch und Ausrichtung (#43).
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Formatting.Reindent);
  Assert.AreEqual<TBlockPlacement>(TBlockPlacement.Preserve, mSettings.Formatting.BeginPlacement);
  Assert.AreEqual(0, mSettings.Formatting.MaxLineLength);
  mSettings := Parse('{"format": {"reindent": false, "beginPlacement": "newLine", "elsePlacement": "sameLine", ' +
    '"maxLineLength": 100, "alignAssignments": true, "alignDeclarations": true, "alignComments": true}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Formatting.Reindent);
  Assert.AreEqual<TBlockPlacement>(TBlockPlacement.NewLine, mSettings.Formatting.BeginPlacement);
  Assert.AreEqual<TBlockPlacement>(TBlockPlacement.SameLine, mSettings.Formatting.ElsePlacement);
  Assert.AreEqual(100, mSettings.Formatting.MaxLineLength);
  Assert.IsTrue(mSettings.Formatting.AlignAssignments);
  Assert.IsTrue(mSettings.Formatting.AlignDeclarations);
  Assert.IsTrue(mSettings.Formatting.AlignComments);
  Assert.AreEqual<TFormatKeys>([TFormatKey.MaxLineLength], mSettings.Formatting.Given);
  Parse('{"format": {"beginPlacement": "below", "maxLineLength": -1}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;
procedure TConfigurationFeatureTests.ReadsVcsProvider;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Versionsverwaltung (#571): Vorgabe auto.
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual('auto', mSettings.VcsProvider);
  mSettings := Parse('{"vcs": {"provider": "svn"}}', mIssues);
  Assert.AreEqual('svn', mSettings.VcsProvider);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := Parse('{"vcs": {"provider": "cvs", "x": 1}}', mIssues);
  Assert.AreEqual('auto', mSettings.VcsProvider, 'unbekannter Wert bleibt bei der Vorgabe');
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Parse('{"vcs": "git"}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'vcs muss ein Objekt sein');
  mSettings := TConfigurationParser.ParseLayered('{"vcs": {"provider": "git"}}', '{"vcs": {"provider": "off"}}',
    mIssues);
  Assert.AreEqual('off', mSettings.VcsProvider, 'Datei vor Editor');
  mSettings := TConfigurationParser.ParseLayered('', '{"vcs": {"provider": "git"}}', mIssues);
  Assert.AreEqual('git', mSettings.VcsProvider);
end;
procedure TConfigurationFeatureTests.ReadsVcsToolPathsAndTimeout;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual('', mSettings.VcsGitPath, 'leer = automatisch suchen');
  Assert.AreEqual('', mSettings.VcsSvnPath);
  Assert.AreEqual(15, mSettings.VcsTimeoutSeconds);
  mSettings := Parse('{"vcs": {"git": {"path": "D:\\Portable\\Git\\cmd\\git.exe"}, ' +
    '"svn": {"path": "C:\\Programme\\TortoiseSVN\\bin\\svn.exe"}, "timeoutSeconds": 60}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('D:\Portable\Git\cmd\git.exe', mSettings.VcsGitPath);
  Assert.AreEqual('C:\Programme\TortoiseSVN\bin\svn.exe', mSettings.VcsSvnPath);
  Assert.AreEqual(60, mSettings.VcsTimeoutSeconds);
  mSettings := Parse('{"vcs": {"timeoutSeconds": 0}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'unter 1');
  Assert.AreEqual(15, mSettings.VcsTimeoutSeconds, 'ungültig: Vorgabe');
  Parse('{"vcs": {"timeoutSeconds": 301}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'über 300');
  Parse('{"vcs": {"timeoutSeconds": "30"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'Text statt Zahl');
  mSettings := Parse('{"vcs": {"git": "git.exe", "svn": {"pfad": "svn.exe"}}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)), 'git muss ein Objekt sein, svn.pfad unbekannt');
  Assert.AreEqual('', mSettings.VcsGitPath);
  Assert.AreEqual('', mSettings.VcsSvnPath);
  mSettings := TConfigurationParser.ParseLayered('{"vcs": {"timeoutSeconds": 30}}',
    '{"vcs": {"provider": "svn", "svn": {"path": "s.exe"}}}', mIssues);
  Assert.AreEqual('svn', mSettings.VcsProvider, 'Datei vor Editor');
  Assert.AreEqual('s.exe', mSettings.VcsSvnPath);
  Assert.AreEqual(15, mSettings.VcsTimeoutSeconds, 'die Datei bestimmt den ganzen Abschnitt vcs');
  // #1286: vcs.projects wird geprüft und als Text weitergegeben.
  mSettings := Parse('{"vcs": {"projects": [{"match": "C:\\Kasse", "provider": "svn"}, ' +
    '{"match": "C:\\Kasse\\Lib", "provider": "git", "mainBranch": "develop"}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.Contains(mSettings.VcsProjects, '"develop"');
  Parse('{"vcs": {"projects": [{"match": "c:/kasse/"}, {"match": "C:\\Kasse"}, {"provider": "cvs"}, 3, ' +
    '{"match": "C:\\X", "mainBranch": "mein branch", "y": 1}]}}', mIssues);
  Assert.AreEqual(6, Integer(Length(mIssues)),
    'doppelter Pfad, unbekannte Art, ohne match, kein Objekt, Leerzeichen im Branch, unbekannte Angabe');
  Parse('{"vcs": {"projects": {}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
end;
/// <summary>Einstellungen ab „Vorgabe aus: Das Plugin wählt „Nach dem Speichern“ selbst“.</summary>
procedure ReadsCompilerOnSaveAndSlashCommands;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Vorgabe aus: Das Plugin wählt „Nach dem Speichern“ selbst.
  mSettings := Parse('{}', mIssues);
  Assert.IsFalse(mSettings.Compiler.OnSave);
  mSettings := Parse('{"compiler": {"onSave": true}}', mIssues);
  Assert.IsTrue(mSettings.Compiler.OnSave);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := Parse('{"compiler": {"onSave": "nein", "x": 1}}', mIssues);
  Assert.IsFalse(mSettings.Compiler.OnSave);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"compiler": {"onSave": true}}', '{}', mIssues);
  Assert.IsTrue(mSettings.Compiler.OnSave);
  // Weg zum Compiler (#261): Vorgabe auto.
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(mSettings.Compiler.Backend));
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := Parse('{"compiler": {"backend": "off"}}', mIssues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Off), Ord(mSettings.Compiler.Backend));
  mSettings := Parse('{"compiler": {"backend": "dcc"}}', mIssues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Dcc), Ord(mSettings.Compiler.Backend));
  mSettings := Parse('{"compiler": {"backend": "msbuild"}}', mIssues);
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(mSettings.Compiler.Backend), 'ungültig = Vorgabe');
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Schnellbefehle (#293)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.SlashCommands);
  Assert.AreEqual(0, Integer(Length(mSettings.SlashCommandsDisabled)));
  mSettings := Parse('{"slashCommands": {"enabled": false, "disabled": ["uses", "var"]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.SlashCommands);
  Assert.AreEqual('var', mSettings.SlashCommandsDisabled[1]);
  Parse('{"slashCommands": {"disabled": "uses", "x": 1}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"slashCommands": {"disabled": ["uses"]}}', '{}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.SlashCommandsDisabled)));
  // Alias usesCommand aus #254: Vorgabe an, false schaltet /uses ab, atlas.json überdeckt den Editor.
  Assert.IsTrue(Parse('{}', mIssues).UsesCommand);
  mSettings := Parse('{"usesCommand": false}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.UsesCommand);
  Parse('{"usesCommand": "nein"}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"usesCommand": true}', '{"usesCommand": false}', mIssues);
  Assert.IsFalse(mSettings.UsesCommand, 'atlas.json gilt vor den Editor-Einstellungen');
end;
/// <summary>Einstellungen ab „Gerüst des Dokumentationskommentars (#88)“.</summary>
procedure ReadsDocCommentAndCompletion;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Gerüst des Dokumentationskommentars (#88)
  Assert.IsTrue(Parse('{}', mIssues).CompleteBlocksDocComment);
  mSettings := Parse('{"completeBlocks": {"docComment": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.CompleteBlocksDocComment);
  Parse('{"completeBlocks": {"docComment": 1, "x": true}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Parse('{"completeBlocks": true}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"completeBlocks": {"docComment": false}}', '{}', mIssues);
  Assert.IsFalse(mSettings.CompleteBlocksDocComment);
  // Protokollaufruf für /log und /except (#304)
  Assert.AreEqual('', Parse('{}', mIssues).SlashLogCall);
  mSettings := Parse('{"slashCommands": {"logCall": "Log.Debug"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('Log.Debug', mSettings.SlashLogCall);
  mSettings := Parse('{"slashCommands": {"logCall": 3}}', mIssues);
  Assert.AreEqual('', mSettings.SlashLogCall);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"slashCommands": {"logCall": "Log.Debug"}}', '{}', mIssues);
  Assert.AreEqual('Log.Debug', mSettings.SlashLogCall);
  // Palettenseite für /component (#299)
  Assert.AreEqual('Eigene', Parse('{}', mIssues).SlashComponentPalette);
  Assert.AreEqual('Firma', Parse('{"slashCommands": {"componentPalette": "Firma"}}', mIssues).SlashComponentPalette);
  // #297: Name und Kategorie für /todo, ungenutzte uses bei /sortuses.
  mSettings := Parse('{"slashCommands": {"todoOwner": "Marco", "todoCategory": "Review", ' +
    '"sortUsesRemoveUnused": false}}', mIssues);
  Assert.AreEqual('Marco', mSettings.SlashTodoOwner);
  Assert.AreEqual('Review', mSettings.SlashTodoCategory);
  Assert.IsFalse(mSettings.SlashSortUsesRemoveUnused);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsTrue(Parse('{}', mIssues).SlashSortUsesRemoveUnused);
  Assert.AreEqual('', Parse('{}', mIssues).SlashTodoOwner);
  // #875: /helper für Aufzählungen
  Assert.IsTrue(Parse('{}', mIssues).SlashEnumHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"enumHelper": false}}', mIssues).SlashEnumHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"enumHelper": false}}', '{}',
    mIssues).SlashEnumHelper);
  Assert.IsTrue(Parse('{}', mIssues).SlashSetHelper);
  Assert.IsFalse(Parse('{"slashCommands": {"setHelper": false}}', mIssues).SlashSetHelper);
  Assert.IsFalse(TConfigurationParser.ParseLayered('{"slashCommands": {"setHelper": false}}', '{}',
    mIssues).SlashSetHelper);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Vervollständigung (#229)
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Fuzzy, Parse('{}', mIssues).Completion.Matching);
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Prefix,
    Parse('{"completion": {"matching": "prefix"}}', mIssues).Completion.Matching);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual<TCompletionMatching>(TCompletionMatching.Fuzzy,
    Parse('{"completion": {"matching": "egal", "x": 1}}', mIssues).Completion.Matching);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen ab „Abschnitt für Interface-Methoden (#466)“.</summary>
procedure ReadsInterfaceSectionAndConversions;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Abschnitt für Interface-Methoden (#466)
  Assert.AreEqual<TCompletionInterfaceSection>(TCompletionInterfaceSection.Public,
    Parse('{}', mIssues).Completion.InterfaceSection);
  Assert.AreEqual<TCompletionInterfaceSection>(TCompletionInterfaceSection.Protected,
    Parse('{"completion": {"interfaceSection": "protected"}}', mIssues).Completion.InterfaceSection);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual<TCompletionInterfaceSection>(TCompletionInterfaceSection.Public,
    Parse('{"completion": {"interfaceSection": "strict"}}', mIssues).Completion.InterfaceSection);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Typumwandlung von Sender (#480)
  Assert.AreEqual<TCompletionSenderCast>(TCompletionSenderCast.AsOperator, Parse('{}', mIssues).Completion.SenderCast);
  Assert.AreEqual<TCompletionSenderCast>(TCompletionSenderCast.HardCast,
    Parse('{"completion": {"senderCast": "cast"}}', mIssues).Completion.SenderCast);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual<TCompletionSenderCast>(TCompletionSenderCast.AsOperator,
    Parse('{"completion": {"senderCast": "hart"}}', mIssues).Completion.SenderCast);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Typkonvertierung vorschlagen (#490, experimentell)
  Assert.AreEqual<TCompletionTypeConversion>(TCompletionTypeConversion.Off,
    Parse('{}', mIssues).Completion.TypeConversion);
  Assert.AreEqual<TCompletionTypeConversion>(TCompletionTypeConversion.Helper,
    Parse('{"completion": {"typeConversion": "helper"}}', mIssues).Completion.TypeConversion);
  Assert.AreEqual<TCompletionTypeConversion>(TCompletionTypeConversion.Function_,
    Parse('{"completion": {"typeConversion": "function"}}', mIssues).Completion.TypeConversion);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual<TCompletionTypeConversion>(TCompletionTypeConversion.Off,
    Parse('{"completion": {"typeConversion": "immer"}}', mIssues).Completion.TypeConversion);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Alle Felder zuweisen (#491, experimentell)
  Assert.IsFalse(Parse('{}', mIssues).Completion.AssignAllFields);
  Assert.IsTrue(Parse('{"completion": {"assignAllFields": true}}', mIssues).Completion.AssignAllFields);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"assignAllFields": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // uses-Vervollständigung mit Gruppen und Hinweisen (#469)
  Assert.IsTrue(Parse('{}', mIssues).Completion.UsesDetails);
  Assert.IsFalse(Parse('{"completion": {"usesDetails": false}}', mIssues).Completion.UsesDetails);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"usesDetails": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Vollständiger inherited-Aufruf (#482)
  Assert.IsTrue(Parse('{}', mIssues).Completion.InheritedCall);
  Assert.IsFalse(Parse('{"completion": {"inheritedCall": false}}', mIssues).Completion.InheritedCall);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"inheritedCall": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Attribute nach "[" (#465)
  Assert.IsTrue(Parse('{}', mIssues).Completion.Attributes);
  Assert.IsFalse(Parse('{"completion": {"attributes": false}}', mIssues).Completion.Attributes);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"attributes": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
/// <summary>Liest Freigabe-Stil, Schlüsselwörter, Postfix-Vorlagen und Constraints der Vervollständigung.</summary>
procedure ReadsFreeStyleAndTemplates;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Freigabe absichern (#489)
  Assert.IsTrue(Parse('{}', mIssues).Completion.OfferTryFinally);
  Assert.AreEqual<TCompletionFreeStyle>(TCompletionFreeStyle.Free, Parse('{}', mIssues).Completion.FreeStyle);
  Assert.IsFalse(Parse('{"completion": {"offerTryFinally": false}}', mIssues).Completion.OfferTryFinally);
  Assert.AreEqual<TCompletionFreeStyle>(TCompletionFreeStyle.FreeAndNil,
    Parse('{"completion": {"freeStyle": "freeAndNil"}}', mIssues).Completion.FreeStyle);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"freeStyle": "nil"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Schlüsselwörter (#31)
  Assert.IsTrue(Parse('{}', mIssues).Completion.Keywords);
  Assert.IsFalse(Parse('{"completion": {"keywords": false}}', mIssues).Completion.Keywords);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Postfix-Vorlagen und Inline-Variablen (#188)
  Assert.IsTrue(Parse('{}', mIssues).Completion.PostfixTemplates);
  Assert.IsFalse(Parse('{"completion": {"postfixTemplates": false}}', mIssues).Completion.PostfixTemplates);
  // Typargumente nach den Constraints (#450)
  Assert.IsTrue(Parse('{}', mIssues).Completion.GenericConstraints);
  Assert.IsFalse(Parse('{"completion": {"genericConstraints": false}}', mIssues).Completion.GenericConstraints);
end;

/// <summary>Einstellungen ab „Anonyme Methoden (#468)“.</summary>
procedure ReadsAnonymousMethodsAndKeywords;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Anonyme Methoden (#468)
  Assert.IsTrue(Parse('{}', mIssues).Completion.AnonymousMethods);
  Assert.IsFalse(Parse('{"completion": {"anonymousMethods": false}}', mIssues).Completion.AnonymousMethods);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"anonymousMethods": 0}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Herkunft in with-Blöcken (#481)
  Assert.IsTrue(Parse('{}', mIssues).Completion.WithOrigin);
  Assert.IsFalse(Parse('{"completion": {"withOrigin": false}}', mIssues).Completion.WithOrigin);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"withOrigin": "nein"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Exception-Klassen (#483)
  Assert.IsTrue(Parse('{}', mIssues).Completion.ExceptionClasses);
  Assert.IsFalse(Parse('{"completion": {"exceptionClasses": false}}', mIssues).Completion.ExceptionClasses);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"exceptionClasses": []}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Hinweis bei unvollständigem Code (#457)
  Assert.IsTrue(Parse('{}', mIssues).Completion.SyntaxNotice);
  Assert.IsFalse(Parse('{"completion": {"syntaxNotice": false}}', mIssues).Completion.SyntaxNotice);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"syntaxNotice": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Gleiche Namen aus verschiedenen Units (#475)
  Assert.IsTrue(Parse('{}', mIssues).Completion.SameNameVariants);
  Assert.AreEqual<TCompletionSameNameInsert>(TCompletionSameNameInsert.Prefix,
    Parse('{}', mIssues).Completion.SameNameInsert);
  Assert.IsFalse(Parse('{}', mIssues).Completion.ShowFmxUnits);
  Assert.IsFalse(Parse('{"completion": {"sameNameVariants": false}}', mIssues).Completion.SameNameVariants);
  Assert.AreEqual<TCompletionSameNameInsert>(TCompletionSameNameInsert.Uses_,
    Parse('{"completion": {"sameNameInsert": "uses"}}', mIssues).Completion.SameNameInsert);
  Assert.IsTrue(Parse('{"completion": {"showFmxUnits": true}}', mIssues).Completion.ShowFmxUnits);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"sameNameInsert": "move"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Typprüfungen (#2107)
  Assert.IsTrue(Parse('{}', mIssues).Completion.TypeGuards);
  Assert.IsFalse(Parse('{"completion": {"typeGuards": false}}', mIssues).Completion.TypeGuards);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"completion": {"typeGuards": "aus"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Nicht sichtbare Mitglieder (#2108)
  Assert.IsTrue(Parse('{}', mIssues).Completion.HiddenMembers);
  Assert.IsFalse(Parse('{"completion": {"hiddenMembers": false}}', mIssues).Completion.HiddenMembers);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Rangfolge aus der Verwendung im Projekt (#2109)
  Assert.IsTrue(Parse('{}', mIssues).Completion.ProjectFrequency);
  Assert.IsFalse(Parse('{"completion": {"projectFrequency": false}}', mIssues).Completion.ProjectFrequency);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  ReadsFreeStyleAndTemplates;
end;
/// <summary>Einstellungen ab „Namensvorschläge (#452)“.</summary>
procedure ReadsNameSuggestionsAndRefactorings;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Namensvorschläge (#452)
  Assert.IsTrue(Parse('{}', mIssues).Completion.NameSuggestions);
  Assert.IsFalse(Parse('{"completion": {"nameSuggestions": false}}', mIssues).Completion.NameSuggestions);
  // Feld und Zugriffsmethoden nach read/write (#467)
  Assert.IsTrue(Parse('{}', mIssues).Completion.CreateAccessors);
  Assert.IsFalse(Parse('{"completion": {"createAccessors": false}}', mIssues).Completion.CreateAccessors);
  Assert.AreEqual<TCompletionAccessorSection>(TCompletionAccessorSection.Private,
    Parse('{}', mIssues).Completion.AccessorSection);
  Assert.AreEqual<TCompletionAccessorSection>(TCompletionAccessorSection.Protected,
    Parse('{"completion": {"accessorSection": "protected"}}', mIssues).Completion.AccessorSection);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual<TCompletionAccessorSection>(TCompletionAccessorSection.Private,
    Parse('{"completion": {"accessorSection": "public"}}', mIssues).Completion.AccessorSection);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // String als resourcestring auslagern (#473)
  Assert.IsTrue(Parse('{}', mIssues).Completion.ResourceStrings);
  Assert.IsFalse(Parse('{"completion": {"resourceStrings": false}}', mIssues).Completion.ResourceStrings);
  Assert.AreEqual('', Parse('{}', mIssues).Completion.ResourceStringUnit);
  Assert.AreEqual('App.Texte', Parse('{"completion": {"resourceStringUnit": "App.Texte"}}',
    mIssues).Completion.ResourceStringUnit);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('', Parse('{"completion": {"resourceStringUnit": "App Texte"}}',
    mIssues).Completion.ResourceStringUnit);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.InlineVar);
  Assert.IsFalse(Parse('{"refactoring": {"inlineVar": false}}', mIssues).Refactoring.InlineVar);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"refactoring": {"inlineVars": false}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Signatur ändern (#100)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ChangeSignature);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.NewParameterOverload);
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.VirtualOverload);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.SyncSignatures);
  Assert.IsFalse(Parse('{"refactoring": {"changeSignature": false}}', mIssues).Refactoring.ChangeSignature);
  Assert.IsFalse(Parse('{"refactoring": {"newParameter": "updateCallers"}}', mIssues).Refactoring.NewParameterOverload);
  Assert.IsTrue(Parse('{"refactoring": {"virtualOverload": true}}', mIssues).Refactoring.VirtualOverload);
  Assert.IsFalse(Parse('{"refactoring": {"syncSignatures": false}}', mIssues).Refactoring.SyncSignatures);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ForwardDeclaration);
  Assert.IsFalse(Parse('{"refactoring": {"forwardDeclaration": false}}', mIssues).Refactoring.ForwardDeclaration);
  // try/finally und Klassen-Aktionen (#42)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.TryFinally);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ClassActions);
  Assert.IsFalse(Parse('{"refactoring": {"tryFinally": false}}', mIssues).Refactoring.TryFinally);
  Assert.IsFalse(Parse('{"refactoring": {"classActions": false}}', mIssues).Refactoring.ClassActions);
  // Typ ausschreiben (#453)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ExplicitType);
  Assert.IsFalse(Parse('{"refactoring": {"explicitType": false}}', mIssues).Refactoring.ExplicitType);
  // Schnellkorrekturen an Compilermeldungen (#549)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.CompilerFixes);
  Assert.IsFalse(Parse('{"refactoring": {"compilerFixes": false}}', mIssues).Refactoring.CompilerFixes);
  // Unit nicht gefunden: Suchpfad ergänzen (#550)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.MissingUnit);
  Assert.IsFalse(Parse('{"refactoring": {"missingUnit": false}}', mIssues).Refactoring.MissingUnit);
end;
/// <summary>Einstellungen ab „Warnung gezielt abschalten (#531)“.</summary>
procedure ReadsWarningsAndCodeActions;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // Warnung gezielt abschalten (#531)
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.DisableWarning);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.DisableWarningReason);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarning": false}}', mIssues).Refactoring.DisableWarning);
  Assert.IsFalse(Parse('{"refactoring": {"disableWarningReason": false}}', mIssues).Refactoring.DisableWarningReason);
  // #50: Extrahieren, case vervollständigen und with auflösen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.Extract);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.CompleteCase);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ResolveWith);
  Assert.IsFalse(Parse('{"refactoring": {"extract": false}}', mIssues).Refactoring.Extract);
  Assert.IsFalse(Parse('{"refactoring": {"completeCase": false}}', mIssues).Refactoring.CompleteCase);
  Assert.IsFalse(Parse('{"refactoring": {"resolveWith": false}}', mIssues).Refactoring.ResolveWith);
  // #103: Einbetten, experimentell und daher aus.
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.InlineCode);
  Assert.IsTrue(Parse('{"refactoring": {"inline": true}}', mIssues).Refactoring.InlineCode);
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.MoveClass);
  Assert.IsTrue(Parse('{"refactoring": {"moveClass": true}}', mIssues).Refactoring.MoveClass);
  // #512: uses nachziehen, experimentell und daher "off".
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.UnitRenameFollowUp);
  Assert.IsTrue(Parse('{"refactoring": {"unitRenameFollowUp": "ask"}}', mIssues).Refactoring.UnitRenameFollowUp);
  Assert.IsFalse(Parse('{"refactoring": {"unitRenameFollowUp": "off"}}', mIssues).Refactoring.UnitRenameFollowUp);
  Parse('{"refactoring": {"unitRenameFollowUp": "yes"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #472: Methode aus Aufruf anlegen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.CreateMethod);
  Assert.AreEqual('private', Parse('{}', mIssues).Refactoring.CreateMethodSection);
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.CreateMethodCaretInBody);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ConstParameters);
  Assert.IsFalse(Parse('{"refactoring": {"createMethod": false}}', mIssues).Refactoring.CreateMethod);
  Assert.AreEqual('protected', Parse('{"refactoring": {"createMethodSection": "Protected"}}',
    mIssues).Refactoring.CreateMethodSection);
  Assert.IsTrue(Parse('{"refactoring": {"createMethodCaret": "body"}}', mIssues).Refactoring.CreateMethodCaretInBody);
  Assert.IsFalse(Parse('{"refactoring": {"constParameters": false}}', mIssues).Refactoring.ConstParameters);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"refactoring": {"newParameter": "default"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"refactoring": {"createMethodSection": "published", "createMethodCaret": "ende"}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  // #682: Property aus Getter und Setter.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Get|Set|Is|Has', string.Join('|', Parse('{}', mIssues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('ask', Parse('{}', mIssues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('accessor', Parse('{}', mIssues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('off', Parse('{}', mIssues).Refactoring.PropertyFromAccessorsHideAccessors);
  Assert.IsFalse(Parse('{"refactoring": {"propertyFromAccessors": false}}', mIssues).Refactoring.PropertyFromAccessors);
  Assert.AreEqual('Read|Write', string.Join('|', Parse('{"refactoring": {"propertyFromAccessorsPrefixes": ' +
    '["Read", " Write ", ""]}}', mIssues).Refactoring.PropertyFromAccessorsPrefixes));
  Assert.AreEqual('always', Parse('{"refactoring": {"propertyFromAccessorsReplaceCalls": "Always"}}',
    mIssues).Refactoring.PropertyFromAccessorsReplaceCalls);
  Assert.AreEqual('published', Parse('{"refactoring": {"propertyFromAccessorsSection": "published"}}',
    mIssues).Refactoring.PropertyFromAccessorsSection);
  Assert.AreEqual('protected', Parse('{"refactoring": {"propertyFromAccessorsHideAccessors": "protected"}}',
    mIssues).Refactoring.PropertyFromAccessorsHideAccessors);
end;
/// <summary>Einstellungen ab „#666: Felder im Destruktor freigeben“.</summary>
procedure ReadsFreeFieldsAndConditions;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // #666: Felder im Destruktor freigeben.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.FreeFields);
  Assert.AreEqual('free', Parse('{}', mIssues).Refactoring.FreeFieldsStyle);
  Assert.IsFalse(Parse('{"refactoring": {"freeFields": false}}', mIssues).Refactoring.FreeFields);
  Assert.AreEqual('freeAndNil', Parse('{"refactoring": {"freeFieldsStyle": "FreeAndNil"}}',
    mIssues).Refactoring.FreeFieldsStyle);
  // #712: Als Konstante deklarieren.
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.SuggestConst);
  Assert.IsTrue(Parse('{"refactoring": {"suggestConst": true}}', mIssues).Refactoring.SuggestConst);
  // #644: var-Block pflegen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.VarBlock);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.VarBlockMerge);
  Assert.AreEqual('usage', Parse('{}', mIssues).Refactoring.VarBlockSort);
  Assert.IsFalse(Parse('{"refactoring": {"varBlock": false}}', mIssues).Refactoring.VarBlock);
  Assert.IsFalse(Parse('{"refactoring": {"varBlockMerge": false}}', mIssues).Refactoring.VarBlockMerge);
  Assert.AreEqual('alpha', Parse('{"refactoring": {"varBlockSort": "Alpha"}}', mIssues).Refactoring.VarBlockSort);
  Assert.AreEqual('usage', Parse('{"refactoring": {"varBlockSort": "quer"}}', mIssues).Refactoring.VarBlockSort);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #715: Boolean umkehren.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.InvertBoolean);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('Not', Parse('{}', mIssues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual(0, Integer(Length(Parse('{}', mIssues).Refactoring.InvertBooleanAntonyms)));
  Assert.IsFalse(Parse('{"refactoring": {"invertBoolean": false}}', mIssues).Refactoring.InvertBoolean);
  Assert.IsFalse(Parse('{"refactoring": {"invertBooleanIncludeDfm": false}}',
    mIssues).Refactoring.InvertBooleanIncludeDfm);
  Assert.AreEqual('No', Parse('{"refactoring": {"invertBooleanFallbackPrefix": "No"}}',
    mIssues).Refactoring.InvertBooleanFallbackPrefix);
  Assert.AreEqual('Verbose=Silent', string.Join(',', Parse('{"refactoring": {"invertBooleanAntonyms": ' +
    '{"Verbose": "Silent"}}}', mIssues).Refactoring.InvertBooleanAntonyms));
  // #646: if-Kette und case.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.IfCase);
  Assert.IsFalse(Parse('{"refactoring": {"ifCase": false}}', mIssues).Refactoring.IfCase);
  // #656: Bedingungen umformen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.Conditions);
  Assert.IsFalse(Parse('{"refactoring": {"conditions": false}}', mIssues).Refactoring.Conditions);
  // #684: if-Anweisung und Bedingungsausdruck.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ConditionalExpression);
  Assert.IsFalse(Parse('{"refactoring": {"conditionalExpression": false}}', mIssues).Refactoring.ConditionalExpression);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.NestedRoutine);
  Assert.IsFalse(Parse('{"refactoring": {"nestedRoutine": false}}', mIssues).Refactoring.NestedRoutine);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.PromoteVariable);
  Assert.IsFalse(Parse('{"refactoring": {"promoteVariable": false}}', mIssues).Refactoring.PromoteVariable);
  // #680: anonyme Methode und Methode.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.AnonymousMethod);
  Assert.IsFalse(Parse('{"refactoring": {"anonymousMethod": false}}', mIssues).Refactoring.AnonymousMethod);
  Assert.AreEqual('forward', Parse('{}', mIssues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual('fields', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "Fields"}}',
    mIssues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('forward', Parse('{"refactoring": {"anonymousMethodDeferredCapture": "felder"}}',
    mIssues).Refactoring.AnonymousMethodDeferredCapture);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen ab „#686: Methode ohne Self“.</summary>
procedure ReadsMethodWithoutSelfAndTypes;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  // #686: Methode ohne Self.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.MethodKind);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.MethodKindMarker);
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.MethodKindStatic);
  Assert.IsFalse(Parse('{"refactoring": {"methodKind": false}}', mIssues).Refactoring.MethodKind);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindMarker": false}}', mIssues).Refactoring.MethodKindMarker);
  Assert.IsFalse(Parse('{"refactoring": {"methodKindStatic": false}}', mIssues).Refactoring.MethodKindStatic);
  // #681: Typ-Alias.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.TypeAlias);
  Assert.IsFalse(Parse('{"refactoring": {"typeAlias": false}}', mIssues).Refactoring.TypeAlias);
  Assert.AreEqual('unit', Parse('{}', mIssues).Refactoring.TypeAliasScope);
  Assert.AreEqual('project', Parse('{"refactoring": {"typeAliasScope": "Project"}}', mIssues).Refactoring.TypeAliasScope);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('unit', Parse('{"refactoring": {"typeAliasScope": "datei"}}', mIssues).Refactoring.TypeAliasScope);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #667: Aufzählung mit Namenstabelle.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.EnumTables);
  Assert.IsFalse(Parse('{}', mIssues).Refactoring.EnumTablesResourceStrings);
  Assert.IsFalse(Parse('{"refactoring": {"enumTables": false}}', mIssues).Refactoring.EnumTables);
  Assert.IsTrue(Parse('{"refactoring": {"enumTablesResourceStrings": true}}',
    mIssues).Refactoring.EnumTablesResourceStrings);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // #674: Überladung anlegen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.Overloads);
  Assert.IsFalse(Parse('{"refactoring": {"overloads": false}}', mIssues).Refactoring.Overloads);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"refactoring": {"propertyFromAccessorsPrefixes": "Get", "propertyFromAccessorsReplaceCalls": "ja", ' +
    '"propertyFromAccessorsSection": "private", "propertyFromAccessorsHideAccessors": "public"}}', mIssues);
  Assert.AreEqual(4, Integer(Length(mIssues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": ["Hidden"], "invertBooleanFallbackPrefix": "nicht gut"}}',
    mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Parse('{"refactoring": {"invertBooleanAntonyms": {"Hidden": "1x"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #664: Interface aus Klasse herauslösen.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.ExtractInterface);
  Assert.IsFalse(Parse('{"refactoring": {"extractInterface": false}}', mIssues).Refactoring.ExtractInterface);
  Parse('{"refactoring": {"extractInterface": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen der Umbauten an Mitgliedern: verschieben (#675), Zugriffsmethode durch Feld ersetzen (#717),
/// Sichtbarkeit anheben (#2108).</summary>
procedure ReadsMemberRefactorings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // #675: Mitglied verschieben.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.MoveMember);
  Assert.IsFalse(Parse('{"refactoring": {"moveMember": false}}', mIssues).Refactoring.MoveMember);
  Parse('{"refactoring": {"moveMember": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #717: Zugriffsmethode durch Feld ersetzen.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Refactoring.InlineAccessor);
  Assert.IsTrue(mSettings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsTrue(mSettings.Refactoring.InlineAccessorBulk);
  Assert.IsFalse(mSettings.Refactoring.InlineAccessorDiagnostic);
  mSettings := Parse('{"refactoring": {"inlineAccessor": false, "inlineAccessorEqualityCheck": false, ' +
    '"inlineAccessorBulk": false, "inlineAccessorDiagnostic": true}}', mIssues);
  Assert.IsFalse(mSettings.Refactoring.InlineAccessor);
  Assert.IsFalse(mSettings.Refactoring.InlineAccessorEqualityCheck);
  Assert.IsFalse(mSettings.Refactoring.InlineAccessorBulk);
  Assert.IsTrue(mSettings.Refactoring.InlineAccessorDiagnostic);
  Parse('{"refactoring": {"inlineAccessorBulk": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // #2108: Sichtbarkeit anheben.
  Assert.IsTrue(Parse('{}', mIssues).Refactoring.RaiseVisibility);
  Assert.IsFalse(Parse('{"refactoring": {"raiseVisibility": false}}', mIssues).Refactoring.RaiseVisibility);
  Parse('{"refactoring": {"raiseVisibility": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;

/// <summary>Einstellungen ab „#713: Basisklasse herauslösen“.</summary>
procedure ReadsExtractBaseClassAndDelete;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // #713: Basisklasse herauslösen.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('sameUnit', mSettings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Base', mSettings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('move', mSettings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('protected', mSettings.Refactoring.ExtractSuperclassRaiseVisibility);
  mSettings := Parse('{"refactoring": {"extractSuperclass": false, "extractSuperclassTarget": "newunit", ' +
    '"extractSuperclassNameSuffix": "Custom", "extractSuperclassMethodMode": "Abstract", ' +
    '"extractSuperclassRaiseVisibility": "strictprotected"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Refactoring.ExtractSuperclass);
  Assert.AreEqual('newUnit', mSettings.Refactoring.ExtractSuperclassTarget);
  Assert.AreEqual('Custom', mSettings.Refactoring.ExtractSuperclassNameSuffix);
  Assert.AreEqual('abstract', mSettings.Refactoring.ExtractSuperclassMethodMode);
  Assert.AreEqual('strictProtected', mSettings.Refactoring.ExtractSuperclassRaiseVisibility);
  Parse('{"refactoring": {"extractSuperclassTarget": "otherUnit", "extractSuperclassNameSuffix": "1x", ' +
    '"extractSuperclassMethodMode": "copy", "extractSuperclassRaiseVisibility": "public"}}', mIssues);
  Assert.AreEqual(4, Integer(Length(mIssues)));
  // #716: Sicher löschen.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Refactoring.SafeDelete);
  Assert.IsFalse(mSettings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('ask', mSettings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('ask', mSettings.Refactoring.SafeDeleteIncludeOverrides);
  mSettings := Parse('{"refactoring": {"safeDelete": false, "safeDeletePreviewWhenUnused": true, ' +
    '"safeDeleteCascade": "Always", "safeDeleteIncludeOverrides": "never"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Refactoring.SafeDelete);
  Assert.IsTrue(mSettings.Refactoring.SafeDeletePreviewWhenUnused);
  Assert.AreEqual('always', mSettings.Refactoring.SafeDeleteCascade);
  Assert.AreEqual('never', mSettings.Refactoring.SafeDeleteIncludeOverrides);
  mSettings := Parse('{"refactoring": {"safeDeleteCascade": "manchmal"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual('ask', mSettings.Refactoring.SafeDeleteCascade);
  // #2054: Methode extrahieren mit gleichen Stellen.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Refactoring.ExtractMethodDuplicates);
  mSettings := Parse('{"refactoring": {"extractMethodDuplicates": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Refactoring.ExtractMethodDuplicates);
  Parse('{"refactoring": {"extractMethodDuplicates": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen ab „Speicherbudget (#185)“.</summary>
procedure ReadsBudgetAndTimeLimits;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Speicherbudget (#185)
  Assert.AreEqual(768, Parse('{}', mIssues).MemoryBudgetMb, 'Vorgabe 768 MB (Rückmeldung 15.10.2026)');
  Assert.AreEqual(0, Parse('{"memoryBudgetMb": 0}', mIssues).MemoryBudgetMb, '0 = unbegrenzt');
  Assert.AreEqual(512, Parse('{"memoryBudgetMb": 512}', mIssues).MemoryBudgetMb);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(768, Parse('{"memoryBudgetMb": -1}', mIssues).MemoryBudgetMb);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"memoryBudgetMb": 100}', '{"memoryBudgetMb": 200}', mIssues);
  Assert.AreEqual(200, mSettings.MemoryBudgetMb);
  // Zeitlimit für Anfragen (#283)
  Assert.AreEqual(10000, Parse('{}', mIssues).RequestTimeoutMs);
  Assert.AreEqual(30000, Parse('{"requestTimeoutMs": 30000}', mIssues).RequestTimeoutMs);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(10000, Parse('{"requestTimeoutMs": 10}', mIssues).RequestTimeoutMs);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Absturzfälle und Sicherheitsnetz (#1355)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.ServerCrashCases and mSettings.ServerCrashSkip);
  mSettings := Parse('{"server": {"crashCases": false, "crashSkip": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.ServerCrashCases or mSettings.ServerCrashSkip);
  mSettings := Parse('{"server": {"crashSkip": 1, "gibts": true}}', mIssues);
  Assert.IsTrue(mSettings.ServerCrashSkip);
  Assert.AreEqual(2, Integer(Length(mIssues)), 'kein Wahrheitswert und unbekannter Schlüssel');
  // Statusdatei je Server (#1901)
  Assert.IsTrue(Parse('{}', mIssues).ServerStatusFile);
  Assert.IsFalse(Parse('{"server": {"statusFile": false}}', mIssues).ServerStatusFile);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Diagnoselog (#647)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.DiagnosticsLog);
  Assert.AreEqual(7, mSettings.DiagnosticsLogDays);
  Assert.IsFalse(mSettings.DiagnosticsLogMapFile);
  mSettings := Parse('{"diagnostics": {"log": false, "logDays": 3, "logMapFile": true}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.DiagnosticsLog);
  Assert.AreEqual(3, mSettings.DiagnosticsLogDays);
  Assert.IsTrue(mSettings.DiagnosticsLogMapFile);
  Assert.AreEqual(7, Parse('{"diagnostics": {"logDays": 0, "x": 1}}', mIssues).DiagnosticsLogDays);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"diagnostics": {"log": false}}', '{"diagnostics": {"logDays": 2}}', mIssues);
  Assert.IsTrue(mSettings.DiagnosticsLog, 'atlas.json ersetzt den ganzen Abschnitt');
  Assert.AreEqual(2, mSettings.DiagnosticsLogDays);
  // Fremde Quellen im Editor (diagnostics.librarySources)
  Assert.IsFalse(Parse('{}', mIssues).DiagnosticsLibrarySources);
  Assert.IsTrue(Parse('{"diagnostics": {"librarySources": true}}', mIssues).DiagnosticsLibrarySources);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(Parse('{"diagnostics": {"librarySources": "ja"}}', mIssues).DiagnosticsLibrarySources);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen ab „Umfang des Index (#648)“.</summary>
procedure ReadsIndexScope;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Umfang des Index (#648)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.IndexProjectGroup and mSettings.IndexSearchPaths);
  Assert.IsFalse(mSettings.IndexLibraryPaths, 'Bibliothekspfade nur auf Wunsch (Dauer)');
  Assert.IsTrue(mSettings.IndexUsages, 'Verwendungen standardmäßig an (#492)');
  Assert.AreEqual<NativeInt>(0, Length(mSettings.IndexExclude));
  mSettings := Parse('{"index": {"projectGroup": false, "searchPaths": false, "libraryPaths": false, ' +
    '"usages": false, "exclude": ["**/Demos/**"]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.IndexProjectGroup or mSettings.IndexSearchPaths or mSettings.IndexLibraryPaths);
  Assert.IsFalse(mSettings.IndexUsages);
  Parse('{"index": {"usages": "ja"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.IsIndexExcluded('C:\Komponenten\Demos\Main.pas'));
  Assert.IsFalse(mSettings.IsIndexExcluded('C:\Komponenten\Source\Main.pas'));
  Parse('{"index": {"exclude": "Demos", "x": true}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"index": {"searchPaths": false}}', '{"index": {"exclude": []}}', mIssues);
  Assert.IsTrue(mSettings.IndexSearchPaths, 'atlas.json ersetzt den ganzen Abschnitt');
  // Aufräumen des Cache-Ordners (#905)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.IndexRemoveOrphans, 'verwaiste Caches standardmäßig löschen');
  Assert.AreEqual(14, mSettings.IndexCacheMaxAgeDays);
  Assert.AreEqual(1024, mSettings.IndexCacheMaxMb);
  mSettings := Parse('{"index": {"removeOrphans": false, "cacheMaxAgeDays": 0, "cacheMaxMb": 2048}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.IndexRemoveOrphans);
  Assert.AreEqual(0, mSettings.IndexCacheMaxAgeDays);
  Assert.AreEqual(2048, mSettings.IndexCacheMaxMb);
  mSettings := Parse('{"index": {"removeOrphans": 1, "cacheMaxAgeDays": -1, "cacheMaxMb": "viel"}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.IndexRemoveOrphans);
  Assert.AreEqual(14, mSettings.IndexCacheMaxAgeDays);
  Assert.AreEqual(1024, mSettings.IndexCacheMaxMb);
  mSettings := TConfigurationParser.ParseLayered('{"index": {"cacheMaxAgeDays": 30}}', '{}', mIssues);
  Assert.AreEqual(30, mSettings.IndexCacheMaxAgeDays);
  // Schlüsselworthervorhebung (#307)
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Highlight.BlockPairs and mSettings.Highlight.Directives and mSettings.Highlight.ExitPoints);
  Assert.AreEqual(4, Integer(Length(mSettings.Highlight.ExitKeywords)));
  mSettings := Parse('{"highlight": {"exitPoints": false, "exitKeywords": ["Exit", "Fail"]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Highlight.ExitPoints);
  Assert.IsTrue(mSettings.Highlight.BlockPairs);
  Assert.AreEqual('Fail', mSettings.Highlight.ExitKeywords[1]);
  Parse('{"highlight": {"blockPairs": 1, "foo": true}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;
/// <summary>Einstellungen ab „Protokoll (#265)“.</summary>
procedure ReadsProtocolSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  // Protokoll (#265)
  Assert.AreEqual('info', Parse('{}', mIssues).LogLevel);
  mSettings := Parse('{"logLevel": "debug", "logFile": "C:\\Log\\lsp.log", "traceFile": "t.json"}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('debug', mSettings.LogLevel);
  Assert.AreEqual('C:\Log\lsp.log', mSettings.LogFile);
  Assert.AreEqual('t.json', mSettings.TraceFile);
  Assert.AreEqual('info', Parse('{"logLevel": "laut"}', mIssues).LogLevel);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"logLevel": "error"}', '{"logLevel": "warning"}', mIssues);
  Assert.AreEqual('warning', mSettings.LogLevel);
end;

procedure TConfigurationFeatureTests.IgnoresRemovedIdeBackend;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"compiler": {"backend": "ide", "ideCommand": "C:\\Werkzeug\\bau.ps1"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'alter Wert ohne Meldung');
  Assert.AreEqual(Ord(TCompilerBackendSetting.Off), Ord(mSettings.Compiler.Backend));
  // Auch ein Eintrag falschen Typs wird übergangen.
  mSettings := Parse('{"compiler": {"ideCommand": 3}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(TCompilerBackendSetting.Auto), Ord(mSettings.Compiler.Backend));
  mIssues := nil;
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
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(mSettings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.SLineBreak), Ord(mSettings.StringLiteral.LineBreak));
  Assert.AreEqual(0, mSettings.StringLiteral.MaxLineLength);
  mSettings := Parse('{"stringLiteral": {"style": "concat", "lineBreak": "#13#10", "maxLineLength": 100}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(TStringLiteralStyle.Concat), Ord(mSettings.StringLiteral.Style));
  Assert.AreEqual(Ord(TStringLiteralBreak.CrLf), Ord(mSettings.StringLiteral.LineBreak));
  Assert.AreEqual(100, mSettings.StringLiteral.MaxLineLength);
  mSettings := Parse('{"stringLiteral": {"style": "kurz", "lineBreak": "space", "maxLineLength": -1, "x": 1}}', mIssues);
  // Ungültiger Stil und negative Länge (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.AreEqual(Ord(TStringLiteralBreak.Space), Ord(mSettings.StringLiteral.LineBreak));
  Assert.AreEqual(Ord(TStringLiteralStyle.Auto), Ord(mSettings.StringLiteral.Style));
end;
procedure TConfigurationFeatureTests.ReadsDirectives;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Directives.Completion);
  Assert.IsTrue(mSettings.Directives.Hover);
  mSettings := Parse('{"directives": {"completion": false, "hover": false}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Directives.Completion);
  Assert.IsFalse(mSettings.Directives.Hover);
  Parse('{"directives": {"x": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Parse('{"directives": 1}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
end;
procedure TConfigurationFeatureTests.ReadsDfmPropertyRules;
var
  mIssues: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  Assert.AreEqual(0, Integer(Length(Parse('{}', mIssues).DfmPropertyRules)));
  mSettings := Parse('{"dfmPropertyRules": [' +
    '{"class": "TLabel", "property": "Transparent", "condition": "=", "value": "True", "fix": "auto"},' +
    '{"class": "TForm", "property": "Position", "condition": "<>", "value": "poDesigned", "message": "Zentriert",' +
    ' "severity": "hint", "includeDescendants": false, "exclude": ["**/Alt/*.dfm"]},' +
    '{"class": "TEdit", "property": "Hint", "condition": "notEmpty", "fix": "none"}]}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual(3, Integer(Length(mSettings.DfmPropertyRules)));
  Assert.AreEqual('TLabel', mSettings.DfmPropertyRules[0].ClassName);
  Assert.AreEqual('Transparent', mSettings.DfmPropertyRules[0].PropertyPath);
  Assert.AreEqual<TDfmCondition>(TDfmCondition.Equal, mSettings.DfmPropertyRules[0].Condition);
  Assert.AreEqual<TDfmFixMode>(TDfmFixMode.Auto, mSettings.DfmPropertyRules[0].Fix);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Warning, mSettings.DfmPropertyRules[0].Severity);
  Assert.IsTrue(mSettings.DfmPropertyRules[0].IncludeDescendants);
  Assert.AreEqual<TDfmCondition>(TDfmCondition.NotEqual, mSettings.DfmPropertyRules[1].Condition);
  Assert.AreEqual<TRuleSeverity>(TRuleSeverity.Hint, mSettings.DfmPropertyRules[1].Severity);
  Assert.IsFalse(mSettings.DfmPropertyRules[1].IncludeDescendants);
  Assert.AreEqual('Zentriert', mSettings.DfmPropertyRules[1].Message);
  Assert.AreEqual('**/Alt/*.dfm', mSettings.DfmPropertyRules[1].Exclude[0]);
  Assert.AreEqual<TDfmCondition>(TDfmCondition.NotEmpty, mSettings.DfmPropertyRules[2].Condition);
  Assert.AreEqual<TDfmFixMode>(TDfmFixMode.None, mSettings.DfmPropertyRules[2].Fix);
  // Fehlerhafte Regeln: ohne property, = ohne value, unbekannte Bedingung, unbekannter Schlüssel.
  mSettings := Parse('{"dfmPropertyRules": [{"class": "TLabel"}, {"class": "TA", "property": "B", "condition": "="},' +
    ' {"class": "TA", "property": "B", "condition": "gleich", "value": "1", "x": 1}, 5]}', mIssues);
  Assert.AreEqual(5, Integer(Length(mIssues)));
  Assert.AreEqual(1, Integer(Length(mSettings.DfmPropertyRules)));
  Parse('{"dfmPropertyRules": {}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Editor zuerst, die Datei hat Vorrang.
  mSettings := TConfigurationParser.ParseLayered('{"dfmPropertyRules": []}',
    '{"dfmPropertyRules": [{"class": "TA", "property": "B", "value": "1"}]}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.DfmPropertyRules)));
end;
procedure TConfigurationFeatureTests.ReadsMemberOrder;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(6, Integer(Length(mSettings.MemberOrder.Sections)));
  Assert.AreEqual('field', mSettings.MemberOrder.Members[0]);
  Assert.IsFalse(mSettings.MemberOrder.SortFields);
  mSettings := Parse('{"memberOrder": {"sections": ["public", "private"], "members": ["method", "field"], ' +
    '"sortFields": true, "sortPublished": true}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('public', mSettings.MemberOrder.Sections[0]);
  Assert.AreEqual('method', mSettings.MemberOrder.Members[0]);
  Assert.IsTrue(mSettings.MemberOrder.SortFields);
  Assert.IsTrue(mSettings.MemberOrder.SortPublished);
  Parse('{"memberOrder": {"sections": ["intern"], "x": 1}}', mIssues);
  // Unbekannte Sichtbarkeit (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(2, Integer(Length(mIssues)));
end;
procedure TConfigurationFeatureTests.ReadsTestUnits;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual('{unit}.Tests', mSettings.TestUnits.Pattern);
  Assert.AreEqual('', mSettings.TestUnits.Folder);
  Assert.AreEqual('', mSettings.TestUnits.Project);
  mSettings := Parse('{"testUnits": {"pattern": "Test.{unit}", "folder": "Tests/Unit", ' +
    '"project": "Tests/Tests.dproj"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.AreEqual('Test.{unit}', mSettings.TestUnits.Pattern);
  Assert.AreEqual('Tests/Unit', mSettings.TestUnits.Folder);
  Assert.AreEqual('Tests/Tests.dproj', mSettings.TestUnits.Project);
  mSettings := Parse('{"testUnits": {"pattern": "Tests", "project": "Tests.exe", "x": 1}}', mIssues);
  // Muster ohne {unit} und Projekt ohne .dproj/.dpr (Fehler), "x" unbekannt (Warnung).
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.AreEqual('{unit}.Tests', mSettings.TestUnits.Pattern, 'ungültiges Muster bleibt bei der Vorgabe');
end;
procedure TConfigurationFeatureTests.ReadsMcpGlobalSettings;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.McpGlobalSettings, 'Vorgabe: globale Datei lesen');
  mSettings := Parse('{"mcp": {"globalSettings": false}}', mIssues);
  Assert.IsFalse(mSettings.McpGlobalSettings);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  mSettings := Parse('{"mcp": {"globalSettings": "nein"}}', mIssues);
  Assert.IsTrue(mSettings.McpGlobalSettings, 'Ungültiger Wert lässt die Vorgabe');
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := TConfigurationParser.ParseLayered('{"mcp": {"globalSettings": true}}',
    '{"mcp": {"globalSettings": false}}', mIssues);
  Assert.IsFalse(mSettings.McpGlobalSettings, 'Datei vor Editor');
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
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"tasks": [{"name": "Delphi-12-Prüfung", "command": "pwsh", "args": ["Tools/Check-Delphi12.ps1"],' +
    ' "cwd": "${projectDir}", "group": "check", "matcher": "pwsh", "key": "Ctrl+Alt+1", "timeoutSec": 300,' +
    ' "beforeBuild": "block", "env": {"NO_COLOR": "1"}},' +
    ' {"name": "Fremd", "command": "lint.exe", "matcher": {"regex": "^(?<file>[^:]+):(?<line>\\d+) (?<message>.*)$",' +
    ' "severity": "warning", "severityMap": {"SCHLIMM": "error"}}}]}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(mSettings.Tasks.StartsWith('['), mSettings.Tasks);
  Parse('{"tasks": [{"name": "A", "command": "x", "group": "lint", "matcher": "eslint", "timeoutSec": -1,' +
    ' "beforeBuild": "stop", "foo": 1}, {"name": "a", "command": ""}, {"command": "y"}, 3,' +
    ' {"name": "M", "command": "z", "matcher": {"severityMap": {"X": "fatal"}}}]}', mIssues);
  // group, matcher, timeoutSec, beforeBuild, foo; Doppelname a und leerer command; ohne name; 3; Muster ohne regex
  // und severityMap-Wert.
  Assert.AreEqual(11, Integer(Length(mIssues)));
  Parse('{"tasks": {"name": "A"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
  mSettings := TConfigurationParser.ParseLayered('{"tasks": []}', '{"tasks": [{"name": "B", "command": "b"}]}',
    mIssues);
  Assert.IsTrue(mSettings.Tasks.Contains('"B"'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksTestLists;
var
  mIssues: TArray<TConfigurationIssue>;
begin
  Parse('{"testLists": [{"name": "Vor dem Commit", "rules": [{"category": "Benchmark", "exclude": true},' +
    ' {"unit": "*.Slow.*", "exclude": true}, {"state": "failed"}]}, {"name": "Parser",' +
    ' "tests": ["Atlas.Common.Pascal.Tests"]}]}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Beispiel aus dem Issue ohne Meldung');
  Parse('{"testLists": [{"name": "A", "rules": [{"state": "gelb"}, {"category": "K", "unit": "U"}, {},' +
    ' {"category": 3, "exclude": "ja", "foo": 1}, 7], "tests": [1], "bar": true}, {"name": "a"}, {"tests": []},' +
    ' 3]}', mIssues);
  // state; zwei Arten; keine Art; category kein Text, exclude kein Wahrheitswert, foo unbekannt; 7; tests mit Zahl;
  // bar unbekannt; Doppelname a; ohne name; 3.
  Assert.AreEqual(12, Integer(Length(mIssues)));
  Parse('{"testLists": {"name": "A"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
end;

procedure TConfigurationFeatureTests.ChecksIssueConnections;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"issues": {"connections": [{"name": "Firma", "provider": "youtrack",' +
    ' "url": "https://youtrack.firma.local"}, {"name": "GitHub", "provider": "github", "url": "https://github.com"}]}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Beispiel aus dem Issue ohne Meldung');
  Assert.IsTrue(mSettings.IssueConnections.StartsWith('['), mSettings.IssueConnections);
  Assert.IsTrue(mSettings.IssueConnections.Contains('"Firma"'), mSettings.IssueConnections);
  Parse('{"issues": {"connections": [{"name": "A", "provider": "youtrack", "url": "http://yt.local"},' +
    ' {"name": "a", "provider": "github", "url": "https://user@github.com"}, {"provider": "", "url": 3, "token": "x"},' +
    ' 3], "queries": []}}', mIssues);
  // http; Doppelname a und Benutzer in der Adresse; url kein String, token unbekannt, ohne name, ohne provider (leer)
  // und ohne url; 3. queries ist seit #1262 bekannt.
  Assert.AreEqual(9, Integer(Length(mIssues)));
  // Sprache der Oberfläche (#1263): de oder en.
  Parse('{"issues": {"connections": [{"name": "A", "provider": "youtrack", "url": "https://yt.local",' +
    ' "language": "de"}, {"name": "B", "provider": "youtrack", "url": "https://yt2.local", "language": "fr"}]}}',
    mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'nur "fr"');
  Parse('{"issues": {"connections": {"name": "A"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
  Parse('{"issues": []}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'kein Objekt');
  mSettings := TConfigurationParser.ParseLayered('{}', '{"issues": {"connections": [{"name": "B", "provider": "github",' +
    ' "url": "https://github.com"}]}}', mIssues);
  Assert.IsTrue(mSettings.IssueConnections.Contains('"B"'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueProjects;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"issues": {"projects": [{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", ' +
    '"connection": "Firma", "project": "KASSE"}, {"match": "C:\\Projekte\\Atlas", "connection": "GitHub"}]}}',
    mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'Beispiel aus dem Issue ohne Meldung; project darf fehlen');
  Assert.IsTrue(mSettings.IssueProjects.StartsWith('['), mSettings.IssueProjects);
  Assert.IsTrue(mSettings.IssueProjects.Contains('"KASSE"'), mSettings.IssueProjects);
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma"}, ' +
    '{"match": "c:/a/", "connection": "GitHub"}, {"connection": 3, "project": 4, "x": 1}, 3]}}', mIssues);
  // Pfad doppelt; connection kein String, project kein String, x unbekannt, ohne match, ohne connection; 3.
  Assert.AreEqual(7, Integer(Length(mIssues)));
  Parse('{"issues": {"projects": {"match": "C:\\A"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
  // Arbeitskopien (#1926): Liste von Ordnern; anderes meldet der Server einmal.
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma", ' +
    '"paths": ["D:\\SVN\\A\\trunk", "D:\\SVN\\B"]}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'paths als Liste ohne Meldung');
  Parse('{"issues": {"projects": [{"match": "C:\\A", "connection": "Firma", "paths": "D:\\SVN"}]}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'paths keine Liste');
  mSettings := TConfigurationParser.ParseLayered('{}', '{"issues": {"projects": [{"match": "C:\\B", ' +
    '"connection": "Firma"}]}}', mIssues);
  Assert.IsTrue(mSettings.IssueProjects.Contains('Firma'), 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ChecksIssueQueries;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{"issues": {"queries": [{"name": "Mir zugewiesen", "query": "assignee: meine #Ungelöst"}, ' +
    '{"name": "Sprint", "query": "#{Aktueller Sprint}", "connection": "Firma", "project": "KASSE"}]}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)), 'connection und project dürfen fehlen');
  Assert.IsTrue(mSettings.IssueQueries.StartsWith('['), mSettings.IssueQueries);
  Assert.IsTrue(mSettings.IssueQueries.Contains('"Sprint"'), mSettings.IssueQueries);
  Parse('{"issues": {"queries": [{"name": "A", "query": "x"}, {"name": "a", "query": ""}, ' +
    '{"connection": 3, "x": 1}, 3]}}', mIssues);
  // Name doppelt, query leer; connection kein String, x unbekannt, ohne name, ohne query; 3.
  Assert.AreEqual(7, Integer(Length(mIssues)));
  Parse('{"issues": {"queries": {"name": "A"}}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)), 'keine Liste');
  mSettings := TConfigurationParser.ParseLayered('{}', '{"issues": {"queries": [{"name": "B", "query": "y"}]}}',
    mIssues);
  Assert.IsTrue(mSettings.IssueQueries.Contains('"B"'), 'Datei vor Editor');
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
  // #2134: githubStateTarget nur project oder label, githubProject ein Text.
  Parse('{"issues": {"connections": [{"name": "A", "provider": "github", "url": "https://github.com",' +
    ' "githubStateTarget": "label", "githubProject": "beispiel/4"}, {"name": "B", "provider": "github",' +
    ' "url": "https://github.example.com", "githubStateTarget": "beides", "githubProject": 4}]}}', mIssues);
  Assert.AreEqual(2, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].Message.Contains('githubStateTarget'), mIssues[0].Message);
end;
procedure TConfigurationFeatureTests.ReadsMcpDisabledTools;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(0, Integer(Length(mSettings.McpDisabledTools)));
  mSettings := Parse('{"mcp": {"disabledTools": ["rename_symbol", 3], "x": 1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mSettings.McpDisabledTools)));
  Assert.AreEqual('rename_symbol', mSettings.McpDisabledTools[0]);
  Assert.AreEqual(2, Integer(Length(mIssues)), 'Zahl in der Liste und unbekannter Schlüssel');
  mSettings := TConfigurationParser.ParseLayered('{"mcp": {"disabledTools": ["a"]}}',
    '{"mcp": {"disabledTools": ["b"]}}', mIssues);
  Assert.AreEqual('b', mSettings.McpDisabledTools[0], 'Datei vor Editor');
end;
procedure TConfigurationFeatureTests.ReadsHints;
var
  mSettings: TServerSettings;
  mIssues: TArray<TConfigurationIssue>;
begin
  mSettings := Parse('{}', mIssues);
  Assert.AreEqual(THintSettings.cExpandLast, mSettings.Hints.XmlDocExpand);
  Assert.AreEqual(0, mSettings.Hints.XmlDocMaxLines);
  // published-Mitglieder im Hover (#110).
  Assert.IsTrue(mSettings.Hints.PublishedMembers);
  Assert.IsFalse(Parse('{"hints": {"publishedMembers": false}}', mIssues).Hints.PublishedMembers);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Parse('{"hints": {"publishedMembers": 0}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  mSettings := Parse('{"hints": {"xmlDocExpand": "collapsed", "xmlDocMaxLines": 10}}', mIssues);
  Assert.AreEqual(THintSettings.cExpandCollapsed, mSettings.Hints.XmlDocExpand);
  Assert.AreEqual(10, mSettings.Hints.XmlDocMaxLines);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  // Außerhalb 0–50 bzw. falsch getypt (Fehler), unbekannter Schlüssel (Warnung); Vorgaben bleiben.
  mSettings := Parse('{"hints": {"xmlDocMaxLines": 51, "xmlDocExpand": "auf", "x": 1}}', mIssues);
  Assert.AreEqual(0, mSettings.Hints.XmlDocMaxLines);
  Assert.AreEqual(THintSettings.cExpandLast, mSettings.Hints.XmlDocExpand);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.IsTrue(mIssues[0].IsError);
  Assert.IsTrue(mIssues[1].IsError);
  Assert.IsFalse(mIssues[2].IsError);
  Parse('{"hints": {"xmlDocMaxLines": -1}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  // Veraltetes xmlDocFull (#770): true = expanded, false = collapsed, mit Warnung; xmlDocExpand gewinnt.
  mSettings := Parse('{"hints": {"xmlDocFull": false}}', mIssues);
  Assert.AreEqual(THintSettings.cExpandCollapsed, mSettings.Hints.XmlDocExpand);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.IsFalse(mIssues[0].IsError);
  mSettings := Parse('{"hints": {"xmlDocFull": true}}', mIssues);
  Assert.AreEqual(THintSettings.cExpandExpanded, mSettings.Hints.XmlDocExpand);
  mSettings := Parse('{"hints": {"xmlDocExpand": "last", "xmlDocFull": false}}', mIssues);
  Assert.AreEqual(THintSettings.cExpandLast, mSettings.Hints.XmlDocExpand);
  // Die Datei ersetzt den Block aus dem Editor (IDE-Plugin).
  mSettings := TConfigurationParser.ParseLayered('{"hints": {"xmlDocExpand": "collapsed"}}',
    '{"hints": {"xmlDocMaxLines": 5}}', mIssues);
  Assert.AreEqual(THintSettings.cExpandLast, mSettings.Hints.XmlDocExpand);
  Assert.AreEqual(5, mSettings.Hints.XmlDocMaxLines);
  // Begründungen (#1123): Schalter, Marken, ADR-Ordner.
  mSettings := Parse('{}', mIssues);
  Assert.IsTrue(mSettings.Hints.Rationale);
  Assert.AreEqual(0, Integer(Length(mSettings.Hints.RationaleMarkers)));
  Assert.AreEqual('', mSettings.Hints.AdrFolder);
  mSettings := Parse('{"hints": {"rationale": false, "rationaleMarkers": ["WHY", " PERF "], ' +
    '"adrFolder": "doc/decisions"}}', mIssues);
  Assert.AreEqual(0, Integer(Length(mIssues)));
  Assert.IsFalse(mSettings.Hints.Rationale);
  Assert.AreEqual('WHY PERF', string.Join(' ', mSettings.Hints.RationaleMarkers));
  Assert.AreEqual('doc/decisions', mSettings.Hints.AdrFolder);
  mSettings := Parse('{"hints": {"rationale": "ja", "rationaleMarkers": ["WHY", ""], "adrFolder": 3}}', mIssues);
  Assert.AreEqual(3, Integer(Length(mIssues)));
  Assert.IsTrue(mSettings.Hints.Rationale);
  mSettings := Parse('{"hints": {"rationaleMarkers": "WHY"}}', mIssues);
  Assert.AreEqual(1, Integer(Length(mIssues)));
  Assert.AreEqual(0, Integer(Length(mSettings.Hints.RationaleMarkers)));
end;

initialization
  TDUnitX.RegisterTestFixture(TConfigurationFeatureTests);

end.
