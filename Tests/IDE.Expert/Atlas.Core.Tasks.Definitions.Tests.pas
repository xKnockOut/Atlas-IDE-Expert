unit Atlas.Core.Tasks.Definitions.Tests;

// Tests für den Abschnitt "tasks" der atlas.json (#900): Felder, Vorgaben,
// verworfene Einträge, Variablen, Projekt vor global, Tasten, beforeBuild.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskDefinitionsTests = class
  public
    /// <summary>Der Optionsdialog (Base) kennt das Modul Build nicht und nimmt TasksBeforeBuildNames (#1455).
    /// </summary>
    [Test]
    procedure BeforeBuildNamesMatchSettings;
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
  System.TypInfo,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.Core.Tasks.Definitions;

const
  cExample =
    '{' + sLineBreak +
    '  // Kommentare sind erlaubt' + sLineBreak +
    '  "tasks": [' + sLineBreak +
    '    { "name": "Delphi-12-Prüfung", "command": "pwsh", "args": ["Tools/Check-Delphi12.ps1"],' + sLineBreak +
    '      "cwd": "${projectDir}", "group": "check", "matcher": "pwsh", "key": "Ctrl+Alt+1" },' + sLineBreak +
    '    { "name": "Konfigurationsdoku", "command": "pwsh", "args": ["Tools/Update-ConfigDoc.ps1"], ' +
    '"group": "other" }' + sLineBreak +
    '  ]' + sLineBreak +
    '}';

/// <summary>„Stelle Art Wert“ je verworfenem Eintrag, getrennt durch „|“.</summary>
function IssueList(const AIssues: TAtlasTaskIssues): string;
var
  mIssue: TAtlasTaskIssue;
  mText: string;
begin
  Result := '';
  for mIssue in AIssues do
  begin
    mText := mIssue.Where + ' ' + GetEnumName(TypeInfo(TAtlasTaskIssueKind), Ord(mIssue.Kind));
    if mIssue.Value <> '' then
    begin
      mText := mText + ' ' + mIssue.Value;
    end;
    if Result <> '' then
    begin
      Result := Result + '|';
    end;
    Result := Result + mText;
  end;
end;

procedure TAtlasTaskDefinitionsTests.BeforeBuildNamesMatchSettings;
var
  mMode: TAtlasTaskBeforeBuild;
begin
  Assert.AreEqual(Integer(Length(cTasksBeforeBuildNames)), Ord(High(TAtlasTaskBeforeBuild)) + 1);
  for mMode := Low(TAtlasTaskBeforeBuild) to High(TAtlasTaskBeforeBuild) do
  begin
    Assert.AreEqual(TAtlasTasks.cBeforeBuildNames[mMode], cTasksBeforeBuildNames[Ord(mMode)]);
  end;
end;

procedure TAtlasTaskDefinitionsTests.ExampleOfTheIssueIsRead;
var
  mTasks: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
begin
  mIssues := nil;
  mTasks := TAtlasTasks.Parse(cExample, False, mIssues);
  Assert.AreEqual(2, Integer(Length(mTasks)));
  Assert.AreEqual(0, Integer(Length(mIssues)), IssueList(mIssues));
  Assert.AreEqual('Delphi-12-Prüfung', mTasks[0].Name);
  Assert.AreEqual('pwsh', mTasks[0].Command);
  Assert.AreEqual('Tools/Check-Delphi12.ps1', string.Join('|', mTasks[0].Args));
  Assert.AreEqual('${projectDir}', mTasks[0].Cwd);
  Assert.IsTrue(mTasks[0].Group = TAtlasTaskGroup.Check);
  Assert.IsTrue(mTasks[0].Matcher.Kind = TAtlasTaskMatcherKind.Pwsh);
  Assert.AreEqual(Integer($C031), Integer(mTasks[0].Key), 'Strg+Alt+1');
  Assert.AreEqual('pwsh Tools/Check-Delphi12.ps1', mTasks[0].CommandLine);
  Assert.IsFalse(mTasks[0].Global);
  Assert.IsTrue(mTasks[1].Group = TAtlasTaskGroup.Other);
  Assert.IsTrue(mTasks[1].Matcher.Kind = TAtlasTaskMatcherKind.None, 'ohne matcher keine Befunde');
  Assert.AreEqual(0, Integer(mTasks[1].Key));
end;

procedure TAtlasTaskDefinitionsTests.DefaultsAndCustomMatcher;
var
  mTasks: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
begin
  mIssues := nil;
  mTasks := TAtlasTasks.Parse('{"tasks":[{"name":"Lint","command":"lint.exe","timeoutSec":30,' +
    '"env":{"LINT_MODE":"strict","LEVEL":"${config}"},"beforeBuild":"block",' +
    '"matcher":{"regex":"^(?<file>[^ ]+) L(?<line>\\d+) (?<severity>\\w+): (?<message>.*)$",' +
    '"severityMap":{"BAD":"error","MEH":"warning","FYI":"info"},"severity":"warning"}},' +
    '{"name":"Ohne","command":"x"}]}', True, mIssues);
  Assert.AreEqual(2, Integer(Length(mTasks)));
  Assert.AreEqual(0, Integer(Length(mIssues)), IssueList(mIssues));
  Assert.AreEqual(30, mTasks[0].TimeoutSec);
  Assert.AreEqual('LINT_MODE|LEVEL', string.Join('|', mTasks[0].EnvNames));
  Assert.AreEqual('strict|${config}', string.Join('|', mTasks[0].EnvValues));
  Assert.IsTrue(mTasks[0].HasBeforeBuild);
  Assert.IsTrue(mTasks[0].BeforeBuild = TAtlasTaskBeforeBuild.Block);
  Assert.IsTrue(mTasks[0].Matcher.Kind = TAtlasTaskMatcherKind.Custom);
  Assert.AreEqual('bad|meh|fyi', string.Join('|', mTasks[0].Matcher.SeverityWords));
  Assert.IsTrue(mTasks[0].Matcher.SeverityValues[1] = TAtlasTaskSeverity.Warning);
  Assert.IsTrue(mTasks[0].Matcher.DefaultSeverity = TAtlasTaskSeverity.Warning);
  Assert.IsTrue(mTasks[0].Global);
  // Vorgaben.
  Assert.AreEqual(TAtlasTasks.cDefaultTimeoutSec, mTasks[1].TimeoutSec);
  Assert.IsTrue(mTasks[1].Group = TAtlasTaskGroup.Other);
  Assert.IsFalse(mTasks[1].HasBeforeBuild);
  Assert.AreEqual('', mTasks[1].Cwd);
end;

procedure TAtlasTaskDefinitionsTests.InvalidEntriesAreDroppedWithReason;
var
  mTasks: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
begin
  mIssues := nil;
  mTasks := TAtlasTasks.Parse('{"tasks":[{"command":"a"},{"name":"B"},42,' +
    '{"name":"C","command":"c","group":"lint","matcher":"gcc","key":"Q","timeoutSec":-1,"beforeBuild":"stop"},' +
    '{"name":"c","command":"zweite"},{"name":"D","command":"d","matcher":{"severity":"error"}}]}', False, mIssues);
  Assert.AreEqual(2, Integer(Length(mTasks)), 'C und D bleiben');
  Assert.AreEqual('C', mTasks[0].Name);
  Assert.AreEqual('c', mTasks[0].Command, 'doppelter Name: die erste gilt');
  Assert.IsTrue(mTasks[0].Group = TAtlasTaskGroup.Other);
  Assert.IsTrue(mTasks[0].Matcher.Kind = TAtlasTaskMatcherKind.None);
  Assert.AreEqual(0, Integer(mTasks[0].Key), 'Q ohne Strg/Alt stört das Tippen');
  Assert.AreEqual(TAtlasTasks.cDefaultTimeoutSec, mTasks[0].TimeoutSec);
  Assert.IsFalse(mTasks[0].HasBeforeBuild);
  Assert.IsTrue(mTasks[1].Matcher.Kind = TAtlasTaskMatcherKind.None, 'Objekt ohne regex');
  // ohne name, ohne command, kein Objekt, group, matcher, key, timeoutSec, beforeBuild, doppelt, regex.
  Assert.AreEqual('tasks[0] MissingName|B MissingCommand|tasks[2] TaskType|C UnknownGroup lint|' +
    'C UnknownMatcher gcc|C KeyUnreadable Q|C TimeoutValue|C BeforeBuildValue stop|c DuplicateName|' +
    'D MatcherWithoutRegex', IssueList(mIssues));
  // Kein Array, ungültiger Text.
  mIssues := nil;
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('{"tasks":{}}', False, mIssues))));
  Assert.AreEqual(' TasksType', IssueList(mIssues));
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('{ kaputt', False, mIssues))));
  Assert.AreEqual(0, Integer(Length(TAtlasTasks.Parse('', False, mIssues))));
end;

procedure TAtlasTaskDefinitionsTests.ProjectWinsOverGlobalByName;
var
  mProject, mGlobal, mMerged: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
begin
  mIssues := nil;
  mProject := TAtlasTasks.Parse('{"tasks":[{"name":"Prüfen","command":"projekt"}]}', False, mIssues);
  mGlobal := TAtlasTasks.Parse('{"tasks":[{"name":"prüfen","command":"global"},{"name":"Format",' +
    '"command":"fmt"}]}', True, mIssues);
  mMerged := TAtlasTasks.Merge(mProject, mGlobal);
  Assert.AreEqual(2, Integer(Length(mMerged)));
  Assert.AreEqual('projekt', mMerged[0].Command);
  Assert.AreEqual('Format', mMerged[1].Name);
  Assert.IsTrue(mMerged[1].Global);
  Assert.AreEqual(1, TAtlasTasks.IndexOf(mMerged, 'FORMAT'));
  Assert.AreEqual(-1, TAtlasTasks.IndexOf(mMerged, 'fehlt'));
end;

procedure TAtlasTaskDefinitionsTests.VariablesAreExpanded;
var
  mTasks: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
  mVariables: TAtlasTaskVariables;
  mTask: TAtlasTaskDefinition;
begin
  mIssues := nil;
  mTasks := TAtlasTasks.Parse('{"tasks":[{"name":"A","command":"${BDS}\\bin\\dcc32.exe",' +
    '"args":["${file}","-E${fileDir}","${config}/${platform}","${groupDir}","${unbekannt}"],' +
    '"env":{"OUT":"${projectDir}\\out"}},{"name":"B","command":"b","cwd":"Tools"},' +
    '{"name":"C","command":"c"}]}', False, mIssues);
  mVariables := Default(TAtlasTaskVariables);
  mVariables.ProjectDir := 'C:\Projekt';
  mVariables.GroupDir := 'C:\Gruppe';
  mVariables.FileName := 'C:\Projekt\Source\Kunde.pas';
  mVariables.Config := 'Debug';
  mVariables.Platform := 'Win64';
  mVariables.Bds := 'C:\RAD\23.0';
  mTask := TAtlasTasks.Expand(mTasks[0], mVariables);
  Assert.AreEqual('C:\RAD\23.0\bin\dcc32.exe', mTask.Command);
  Assert.AreEqual('C:\Projekt\Source\Kunde.pas|-EC:\Projekt\Source|Debug/Win64|C:\Gruppe|${unbekannt}',
    string.Join('|', mTask.Args));
  Assert.AreEqual('C:\Projekt\out', mTask.EnvValues[0]);
  Assert.AreEqual('C:\Projekt', mTask.Cwd, 'ohne cwd: Projektordner');
  Assert.AreEqual('${file}', mTasks[0].Args[0], 'die Definition bleibt unverändert');
  Assert.AreEqual('C:\Projekt\Tools', TAtlasTasks.Expand(mTasks[1], mVariables).Cwd, 'relativ zum Projekt');
  mVariables.ProjectDir := '';
  Assert.AreEqual('', TAtlasTasks.Expand(mTasks[2], mVariables).Cwd);
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
  mTasks, mBefore: TAtlasTaskDefinitions;
  mIssues: TAtlasTaskIssues;
begin
  mIssues := nil;
  mTasks := TAtlasTasks.Parse('{"tasks":[{"name":"Prüfung","command":"a","group":"check"},' +
    '{"name":"Aus","command":"b","group":"check","beforeBuild":"off"},' +
    '{"name":"Test","command":"c","group":"test","beforeBuild":"warn"},' +
    '{"name":"Doku","command":"d"}]}', False, mIssues);
  Assert.IsTrue(mTasks[0].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Block);
  Assert.IsTrue(mTasks[0].BeforeBuildFor(TAtlasTaskBeforeBuild.Off) = TAtlasTaskBeforeBuild.Off);
  Assert.IsTrue(mTasks[1].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Off, 'eigener Wert');
  Assert.IsTrue(mTasks[2].BeforeBuildFor(TAtlasTaskBeforeBuild.Off) = TAtlasTaskBeforeBuild.Warn,
    'eigener Wert auch außerhalb von check');
  Assert.IsTrue(mTasks[3].BeforeBuildFor(TAtlasTaskBeforeBuild.Block) = TAtlasTaskBeforeBuild.Off);
  mBefore := TAtlasTasks.BeforeBuild(mTasks, TAtlasTaskBeforeBuild.Warn);
  Assert.AreEqual(2, Integer(Length(mBefore)));
  Assert.AreEqual('Prüfung', mBefore[0].Name);
  Assert.AreEqual('Test', mBefore[1].Name);
  Assert.AreEqual(2, Integer(Length(TAtlasTasks.OfGroup(mTasks, TAtlasTaskGroup.Check))));
  Assert.AreEqual('block', TAtlasTasks.NormalizedBeforeBuild(' BLOCK '));
  Assert.AreEqual('off', TAtlasTasks.NormalizedBeforeBuild('streng'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskDefinitionsTests);

end.
