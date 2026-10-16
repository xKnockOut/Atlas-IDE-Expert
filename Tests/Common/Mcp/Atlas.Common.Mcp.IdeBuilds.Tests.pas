unit Atlas.Common.Mcp.IdeBuilds.Tests;

// Tests für build_project über die laufende IDE (#261). Die Rolle des Plugins
// spielt der Warte-Rückruf: Er übernimmt den Auftrag und antwortet im Format
// von Atlas.Core.Build.Inbox.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpIdeBuildsTests = class
  private
    FInbox: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReadsIdeEntry;
    [Test]
    procedure PicksActiveProjectUnderRoot;
    [Test]
    procedure PicksProjectByName;
    [Test]
    procedure ExplainsWhenNoIdeHasTheProject;
    [Test]
    procedure ReportsBuildOfThePlugin;
    [Test]
    procedure ReportsRefusal;
    [Test]
    procedure WithdrawsWhenNobodyTakesTheRequest;
    [Test]
    procedure TimesOutWhenTakenButNeverAnswered;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.IOUtils,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Lsp.IdeBuild,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.IdeBuilds;

const
  /// <summary>Antwort des Plugins wie TAtlasBuildInbox.SuccessText (Zeilen und Spalten 1-basiert).</summary>
  PluginAnswer = '{"ok":true,"build":{"project":"C:\\P\\App.dproj","kind":"make","configuration":"Debug",' +
    '"platform":"Win32","success":false,"durationMs":1200,"finishedAt":"2026-10-16T10:00:00.000+02:00",' +
    '"requestedBy":"mcp","messages":[{"file":"C:\\P\\Main.pas","line":12,"column":3,"severity":"error",' +
    '"code":"E2003","text":"Undeklarierter Bezeichner: ''Foo''"}]}}';

var
  Now_: Int64;

function Clock: Int64;
begin
  Result := Now_;
end;

/// <summary>Wie das Plugin: Auftrag übernehmen (umbenennen), lesen und mit AAnswer beantworten.</summary>
function Plugin(const AInbox, AAnswer: string; out ARequest: string): Boolean;
var
  Request: string;
begin
  Result := False;
  if not TDirectory.Exists(AInbox) then
    Exit;
  for Request in TDirectory.GetFiles(AInbox, '*.json') do
    if not Request.EndsWith('.result.json') then
    begin
      RenameFile(Request, ChangeFileExt(Request, '.taken'));
      ARequest := TFile.ReadAllText(ChangeFileExt(Request, '.taken'), TEncoding.UTF8);
      if AAnswer <> '' then
        TFile.WriteAllText(ChangeFileExt(Request, '') + '.result.json', AAnswer, TEncoding.UTF8);
      Exit(True);
    end;
end;

function Ide(APid: Cardinal; const AProjects: TArray<string>; const AActive: string): TMcpIdeEntry;
begin
  Result := Default(TMcpIdeEntry);
  Result.Pid := APid;
  Result.Projects := AProjects;
  Result.ActiveProject := AActive;
end;

function Request(const AProject, AMode: string): TMcpIdeBuildRequest;
begin
  Result := Default(TMcpIdeBuildRequest);
  Result.Project := AProject;
  Result.Mode := AMode;
end;

procedure TMcpIdeBuildsTests.Setup;
begin
  FInbox := TMcpIdeBuilds.InboxOf(TPath.Combine(TPath.GetTempPath, 'Atlas-IdeBuilds-' + IntToStr(Random(MaxInt))),
    42);
  Now_ := 0;
end;

procedure TMcpIdeBuildsTests.TearDown;
begin
  if TDirectory.Exists(FInbox) then
    TDirectory.Delete(FInbox, True);
  FInbox := '';
end;

procedure TMcpIdeBuildsTests.ReadsIdeEntry;
var
  Entry: TMcpIdeEntry;
begin
  Assert.IsTrue(TMcpIdeBuilds.ParseEntry('{"pid": 4711, "files": [], "open": [], ' +
    '"projects": ["C:\\P\\App.dproj", "C:\\P\\Lib.dproj"], "activeProject": "C:\\P\\App.dproj"}', Entry));
  Assert.AreEqual(Cardinal(4711), Entry.Pid);
  Assert.AreEqual(2, Integer(Length(Entry.Projects)));
  Assert.AreEqual('C:\P\Lib.dproj', Entry.Projects[1]);
  Assert.AreEqual('C:\P\App.dproj', Entry.ActiveProject);
  // Älteres Plugin ohne Projekte: Eintrag ja, Projekte leer.
  Assert.IsTrue(TMcpIdeBuilds.ParseEntry('{"pid": 1, "files": []}', Entry));
  Assert.AreEqual(0, Integer(Length(Entry.Projects)));
  Assert.IsFalse(TMcpIdeBuilds.ParseEntry('{"files": []}', Entry));
  Assert.IsFalse(TMcpIdeBuilds.ParseEntry('kaputt', Entry));
end;

procedure TMcpIdeBuildsTests.PicksActiveProjectUnderRoot;
var
  Pid: Cardinal;
  Project, Reason: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(1, ['C:\Other\X.dproj'], 'C:\Other\X.dproj'),
    Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', '', Pid, Project, Reason));
  Assert.AreEqual(Cardinal(2), Pid);
  Assert.AreEqual('C:\P\App.dproj', Project);
  Assert.IsFalse(TMcpIdeBuilds.Pick([Ide(1, ['C:\Other\X.dproj'], 'C:\Other\X.dproj')], 'C:\P', '', Pid, Project,
    Reason));
  Assert.IsTrue(Pos('aktives Projekt', Reason) > 0, Reason);
end;

procedure TMcpIdeBuildsTests.PicksProjectByName;
var
  Pid: Cardinal;
  Project, Reason: string;
begin
  // Dateiname, Name ohne Endung und voller Pfad; nicht aktive Projekte zählen auch.
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj', 'C:\P\Lib\Lib.dproj'], 'C:\P\App.dproj')], 'C:\P',
    'Lib.dproj', Pid, Project, Reason));
  Assert.AreEqual('C:\P\Lib\Lib.dproj', Project);
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'app', Pid, Project, Reason));
  Assert.AreEqual('C:\P\App.dproj', Project);
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'C:\P\App.dproj', Pid, Project, Reason));
  Assert.AreEqual(Cardinal(7), Pid);
end;

procedure TMcpIdeBuildsTests.ExplainsWhenNoIdeHasTheProject;
var
  Pid: Cardinal;
  Project, Reason: string;
begin
  Assert.IsFalse(TMcpIdeBuilds.Pick(nil, 'C:\P', 'App', Pid, Project, Reason));
  Assert.IsTrue(Pos('Keine RAD-Studio-IDE', Reason) > 0, Reason);
  Assert.IsFalse(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'Kasse', Pid, Project, Reason));
  Assert.IsTrue(Pos('Kasse', Reason) > 0, Reason);
  Assert.AreEqual(Cardinal(0), Pid);
end;

procedure TMcpIdeBuildsTests.ReportsBuildOfThePlugin;
var
  BuildText, Reason, Seen: string;
  Json: TJSONValue;
  Build: TIdeBuild;
  Wanted: TMcpIdeBuildRequest;
begin
  Wanted := Request('C:\P\App.dproj', 'Build');
  Wanted.Configuration := 'Release';
  Assert.IsTrue(TMcpIdeBuilds.Send(FInbox, Wanted,
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, PluginAnswer, Seen);
    end, Clock, BuildText, Reason) = TMcpIdeBuildOutcome.Done, Reason);
  Json := TJSONObject.ParseJSONValue(Seen);
  try
    Assert.AreEqual('C:\P\App.dproj', Json.GetValue<string>('project'));
    Assert.AreEqual('build', Json.GetValue<string>('mode'), 'klein geschrieben');
    Assert.AreEqual('Release', Json.GetValue<string>('configuration'));
    Assert.AreEqual('', Json.GetValue<string>('platform'));
  finally
    Json.Free;
  end;
  // Das Ergebnis hat das Format von get_last_build.
  Assert.IsTrue(TMcpBuildTools.FromFileText(BuildText, Build));
  Assert.AreEqual('mcp', Build.RequestedBy);
  Assert.AreEqual(1, Integer(Length(Build.Messages)));
  Assert.AreEqual(11, Build.Messages[0].Line);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Build.Messages[0].Severity));
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox, '*.result.json'))), 'Antwort gelesen und gelöscht');
end;

procedure TMcpIdeBuildsTests.ReportsRefusal;
var
  BuildText, Reason, Seen: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'make'),
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"ok":false,"reason":"In der IDE läuft der Debugger"}', Seen);
    end, Clock, BuildText, Reason) = TMcpIdeBuildOutcome.Refused);
  Assert.AreEqual('In der IDE läuft der Debugger', Reason);
  Assert.AreEqual('', BuildText);
end;

procedure TMcpIdeBuildsTests.WithdrawsWhenNobodyTakesTheRequest;
var
  BuildText, Reason: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'make'),
    procedure
    begin
      Inc(Now_, 100);
    end, Clock, BuildText, Reason) = TMcpIdeBuildOutcome.NotTaken);
  Assert.IsNotEmpty(Reason);
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox))), 'Auftrag zurückgezogen');
end;

procedure TMcpIdeBuildsTests.TimesOutWhenTakenButNeverAnswered;
var
  BuildText, Reason, Seen: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'check'),
    procedure
    begin
      Inc(Now_, 1000);
      Plugin(FInbox, '', Seen);
    end, Clock, 5000, 3000, BuildText, Reason) = TMcpIdeBuildOutcome.TimedOut);
  Assert.IsNotEmpty(Reason);
  Assert.IsTrue(TMcpIdeBuilds.ModeValid('Check'));
  Assert.IsFalse(TMcpIdeBuilds.ModeValid('clean'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeBuildsTests);

end.
