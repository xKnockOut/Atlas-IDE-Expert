unit Atlas.Core.Tasks.Definitions.Tests;

// Tests für den Abschnitt "tasks" der atlas.json (#900): Felder, Vorgaben,
// verworfene Einträge, Variablen, Projekt vor global, Tasten, beforeBuild.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTaskDefinitionsTests = class
  public
    [Test]
    procedure ExampleOfTheIssueIsRead;
    [Test]
    procedure DefaultsAndCustomMatcher;
    [Test]
    procedure InvalidEntriesAreDroppedWithReason;
    [Test]
    procedure ProjectWinsOverGlobalByName;
    [Test]
    procedure VariablesAreExpanded;
    [Test]
    procedure KeysAreParsed;
    [Test]
    procedure BeforeBuildFollowsTaskThenGlobalForChecks;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Tasks.Definitions;

const
  Example =
    '{' + sLineBreak +
    '  // Kommentare sind erlaubt' + sLineBreak +
    '  "tasks": [' + sLineBreak +
    '    { "name": "Delphi-12-Prüfung", "command": "pwsh", "args": ["Tools/Check-Delphi12.ps1"],' + sLineBreak +
    '      "cwd": "${projectDir}", "group": "check", "matcher": "pwsh", "key": "Ctrl+Alt+1" },' + sLineBreak +
    '    { "name": "Konfigurationsdoku", "command": "pwsh", "args": ["Tools/Update-ConfigDoc.ps1"], ' +
    '"group": "other" }' + sLineBreak +
    '  ]' + sLineBreak +
    '}';

procedure TAtlasTaskDefinitionsTests.ExampleOfTheIssueIsRead;
var
  Tasks: TAtlasTaskDefinitions;
  Issues: TArray<string>;
begin
  Issues := nil;
  Tasks := TAtlasTasks.Parse(Example, False, Issues);
  Assert.AreEqual(2, Integer(Length(Tasks)));
  Assert.AreEqual(0, Integer(Length(Issues)), string.Join('; ', Issues));
  Assert.AreEqual('Delphi-12-Prüfung', Tasks[0].Name);
  Assert.AreEqual('pwsh', Tasks[0].Command);
  Assert.AreEqual('Tools/Check-Delphi12.ps1', string.Join('|', Tasks[0].Args));
  Assert.AreEqual('${projectDir}', Tasks[0].Cwd);
  Assert.IsTrue(Tasks[0].Group = TAtlasTaskGroup.Check);
  Assert.IsTrue(Tasks[0].Matcher.Kind = TAtlasTaskMatcherKind.Pwsh);
  Assert.AreEqual(Integer($C031), Integer(Tasks[0].Key), 'Strg+Alt+1');
  Assert.AreEqual('pwsh Tools/Check-Delphi12.ps1', Tasks[0].CommandLine);
  Assert.IsFalse(Tasks[0].Global);
  Assert.IsTrue(Tasks[1].Group = TAtlasTaskGroup.Other);
  Assert.IsTrue(Tasks[1].Matcher.Kind = TAtlasTaskMatcherKind.None, 'ohne matcher keine Befunde');
  Assert.AreEqual(0, Integer(Tasks[1].Key));
end;

procedure TAtlasTaskDefinitionsTests.DefaultsAndCustomMatcher;
var
  Tasks: TAtlasTaskDefinitions;
  Issues: TArray<string>;
begin
  Issues := nil;
  Tasks := TAtlasTasks.Parse('{"tasks":[{"name":"Lint","command":"lint.exe","timeoutSec":30,' +
    '"env":{"LINT_MODE":"strict","LEVEL":"${config}"},"beforeBuild":"block",' +
    '"matcher":{"regex":"^(?<file>[^ ]+) L(?<line>\\d+) (?<severity>\\w+): (?<message>.*)$",' +
    '"severityMap":{"BAD":"error","MEH":"warning","FYI":"info"},"severity":"warning"}},' +
    '{"name":"Ohne","command":"x"}]}', True, Issues);
  Assert.AreEqual(2, Integer(Length(Tasks)));
  Assert.AreEqual(0, Integer(Length(Issues)), string.Join('; ', Issues));
  Assert.AreEqual(30, Tasks[0].TimeoutSec);
  Assert.AreEqual('LINT_MODE|LEVEL', string.Join('|', Tasks[0].EnvNames));
  Assert.AreEqual('strict|${config}', string.Join('|', Tasks[0].EnvValues));
  Assert.IsTrue(Tasks[0].HasBeforeBuild);
  Assert.IsTrue(Tasks[0].BeforeBuild = TAtlasTaskBeforeBuild.Block);
  Assert.IsTrue(Tasks[0].Matcher.Kind = TAtlasTaskMatcherKind.Custom);
  Assert.AreEqual('bad|meh|fyi', string.Join('|', Tasks[0].Matcher.SeverityWords));
  Assert.IsTrue(Tasks[0].Matcher.SeverityValues[1] = TAtlasTaskSeverity.Warning);
  Assert.IsTrue(Tasks[0].Matcher.DefaultSeverity = TAtlasTaskSeverity.Warning);
  Assert.IsTrue(Tasks[0].Global);
  // Vorgaben.
  Assert.AreEqual(TAtlasTasks.DefaultTimeoutSec, Tasks[1].TimeoutSec);
  Assert.IsTrue(Tasks[1].Group = TAtlasTaskGroup.Other);
  Assert.IsFalse(Tasks[1].HasBeforeBuild);
  Assert.AreEqual('', Tasks[1].Cwd);
end;

procedure TAtlasTaskDefinitionsTests.InvalidEntriesAreDroppedWithReason;
var
  Tasks: TAtlasTaskDefinitions;
  Issues: TArray<string>;
begin
  Issues := nil;
  Tasks := TAtlasTasks.Parse('{"tasks":[{"command":"a"},{"name":"B"},42,' +
    '{"name":"C","command":"c","group":"lint","matcher":"gcc","key":"Q","timeoutSec":-1,"beforeBuild":"stop"},' +
    '{"name":"c","command":"zweite"},{"name":"D","command":"d","matcher":{"severity":"error"}}]}', False, Issues);
  Assert.AreEqual(2, Integer(Length(Tasks)), 'C und D bleiben');
  Assert.AreEqual('C', Tasks[0].Name);
  Assert.AreEqual('c', Tasks[0].Command, 'doppelter Name: die erste gilt');
  Assert.IsTrue(Tasks[0].Group = TAtlasTaskGroup.Other);
  Assert.IsTrue(Tasks[0].Matcher.Kind = TAtlasTaskMatcherKind.None);
  Assert.AreEqual(0, Integer(Tasks[0].Key), 'Q ohne Strg/Alt stört das Tippen');
  Assert.AreEqual(TAtlasTasks.DefaultTimeoutSec, Tasks[0].TimeoutSec);
  Assert.IsFalse(Tasks[0].HasBeforeBuild);
  Assert.IsTrue(Tasks[1].Matcher.Kind = TAtlasTaskMatcherKind.None, 'Objekt ohne regex');
  // ohne name, ohne command, kein Objekt, group, matcher, key, timeoutSec, beforeBuild, doppelt, regex.
  Assert.AreEqual(10, Integer(Length(Issues)), string.Join('; ', Issues));
  Assert.AreEqual('tasks[0]: ohne name', Issues[0]);
  Assert.AreEqual('B: ohne command', Issues[1]);
  // Kein Array, ungültiger Text.
  Issues := nil;
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('{"tasks":{}}', False, Issues))));
  Assert.AreEqual('tasks muss eine Liste sein', Issues[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('{ kaputt', False, Issues))));
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('', False, Issues))));
end;

procedure TAtlasTaskDefinitionsTests.ProjectWinsOverGlobalByName;
var
  Project, Global, Merged: TAtlasTaskDefinitions;
  Issues: TArray<string>;
begin
  Issues := nil;
  Project := TAtlasTasks.Parse('{"tasks":[{"name":"Prüfen","command":"projekt"}]}', False, Issues);
  Global := TAtlasTasks.Parse('{"tasks":[{"name":"prüfen","command":"global"},{"name":"Format",' +
    '"command":"fmt"}]}', True, Issues);
  Merged := TAtlasTasks.Merge(Project, Global);
  Assert.AreEqual(2, Integer(Length(Merged)));
  Assert.AreEqual('projekt', Merged[0].Command);
  Assert.AreEqual('Format', Merged[1].Name);
  Assert.IsTrue(Merged[1].Global);
  Assert.AreEqual(1, TAtlasTasks.IndexOf(Merged, 'FORMAT'));
  Assert.AreEqual(-1, TAtlasTasks.IndexOf(Merged, 'fehlt'));
end;

procedure TAtlasTaskDefinitionsTests.VariablesAreExpanded;
var
  Tasks: TAtlasTaskDefinitions;
  Issues: TArray<string>;
  Variables: TAtlasTaskVariables;
  Task: TAtlasTaskDefinition;
begin
  Issues := nil;
  Tasks := TAtlasTasks.Parse('{"tasks":[{"name":"A","command":"${BDS}\\bin\\dcc32.exe",' +
    '"args":["${file}","-E${fileDir}","${config}/${platform}","${groupDir}","${unbekannt}"],' +
    '"env":{"OUT":"${projectDir}\\out"}},{"name":"B","command":"b","cwd":"Tools"},' +
    '{"name":"C","command":"c"}]}', False, Issues);
  Variables := Default(TAtlasTaskVariables);
  Variables.ProjectDir := 'C:\Projekt';
  Variables.GroupDir := 'C:\Gruppe';
  Variables.FileName := 'C:\Projekt\Source\Kunde.pas';
  Variables.Config := 'Debug';
  Variables.Platform := 'Win64';
  Variables.Bds := 'C:\RAD\23.0';
  Task := TAtlasTasks.Expand(Tasks[0], Variables);
  Assert.AreEqual('C:\RAD\23.0\bin\dcc32.exe', Task.Command);
  Assert.AreEqual('C:\Projekt\Source\Kunde.pas|-EC:\Projekt\Source|Debug/Win64|C:\Gruppe|${unbekannt}',
    string.Join('|', Task.Args));
  Assert.AreEqual('C:\Projekt\out', Task.EnvValues[0]);
  Assert.AreEqual('C:\Projekt', Task.Cwd, 'ohne cwd: Projektordner');
  Assert.AreEqual('${file}', Tasks[0].Args[0], 'die Definition bleibt unverändert');
  Assert.AreEqual('C:\Projekt\Tools', TAtlasTasks.Expand(Tasks[1], Variables).Cwd, 'relativ zum Projekt');
  Variables.ProjectDir := '';
  Assert.AreEqual('', TAtlasTasks.Expand(Tasks[2], Variables).Cwd);
end;

procedure TAtlasTaskDefinitionsTests.KeysAreParsed;
begin
  Assert.AreEqual(Integer($C031), Integer(TAtlasTasks.ParseKey('Ctrl+Alt+1')));
  Assert.AreEqual(Integer($C031), Integer(TAtlasTasks.ParseKey('Strg + Alt + 1')));
  Assert.AreEqual(Integer($6041), Integer(TAtlasTasks.ParseKey('Strg+Umschalt+a')));
  Assert.AreEqual(Integer($0074), Integer(TAtlasTasks.ParseKey('F5')), 'Funktionstaste allein');
  Assert.AreEqual(Integer($2087), Integer(TAtlasTasks.ParseKey('Shift+F24')));
  Assert.AreEqual(0, Integer(TAtlasTasks.ParseKey('Ctrl+Space')));
  Assert.AreEqual(0, Integer(TAtlasTasks.ParseKey('Hyper+1')));
  Assert.AreEqual(0, Integer(TAtlasTasks.ParseKey('Shift+A')));
  Assert.AreEqual(0, Integer(TAtlasTasks.ParseKey('')));
  Assert.AreEqual(0, Integer(TAtlasTasks.ParseKey('F25')));
end;

procedure TAtlasTaskDefinitionsTests.BeforeBuildFollowsTaskThenGlobalForChecks;
var
  Tasks, Before: TAtlasTaskDefinitions;
  Issues: TArray<string>;
begin
  Issues := nil;
  Tasks := TAtlasTasks.Parse('{"tasks":[{"name":"Prüfung","command":"a","group":"check"},' +
    '{"name":"Aus","command":"b","group":"check","beforeBuild":"off"},' +
    '{"name":"Test","command":"c","group":"test","beforeBuild":"warn"},' +
    '{"name":"Doku","command":"d"}]}', False, Issues);
  Assert.IsTrue(Tasks[0].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Block);
  Assert.IsTrue(Tasks[0].BeforeBuildFor(TAtlasTaskBeforeBuild.Off) = TAtlasTaskBeforeBuild.Off);
  Assert.IsTrue(Tasks[1].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Off, 'eigener Wert');
  Assert.IsTrue(Tasks[2].BeforeBuildFor(TAtlasTaskBeforeBuild.Off) = TAtlasTaskBeforeBuild.Warn,
    'eigener Wert auch außerhalb von check');
  Assert.IsTrue(Tasks[3].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Off);
  Before := TAtlasTasks.BeforeBuild(Tasks, TAtlasTaskBeforeBuild.Warn);
  Assert.AreEqual(2, Integer(Length(Before)));
  Assert.AreEqual('Prüfung', Before[0].Name);
  Assert.AreEqual('Test', Before[1].Name);
  Assert.AreEqual(2, Integer(Length(TAtlasTasks.OfGroup(Tasks, TAtlasTaskGroup.Check))));
  Assert.AreEqual('block', TAtlasTasks.NormalizedBeforeBuild(' BLOCK '));
  Assert.AreEqual('off', TAtlasTasks.NormalizedBeforeBuild('streng'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskDefinitionsTests);

end.
