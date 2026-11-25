unit Atlas.Common.Mcp.IdeBuilds.Tests;

// Tests für build_project über die laufende IDE (#261). Die Rolle des Plugins
// spielt der Warte-Rückruf: Er übernimmt den Auftrag und antwortet im Format
// von Atlas.Core.Assistants.BuildInbox.

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
    /// <summary>#2895: Projekt in keiner IDE offen, aber unter dem Arbeitsordner: nach Zustimmung die IDE mit dem
    /// aktiven Projekt unter dem Arbeitsordner und die Datei.</summary>
    [Test]
    procedure OpensProjectAfterConsent;
    [Test]
    procedure KeepsReasonWhenConsentIsMissing;
    [Test]
    procedure OpenPolicyDecides;
    [Test]
    procedure AskAsksWithProjectName;
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
  System.Generics.Collections,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.IdeBuild,
  Atlas.Common.Mcp.BuildTools,
  Atlas.Common.Mcp.IdeInbox,
  Atlas.Common.Mcp.IdeBuilds,
  Atlas.Common.Mcp.Confirm,
  Atlas.Common.Mcp.IdeInbox.Tests;

const
  /// <summary>Antwort des Plugins wie TAtlasBuildInbox.SuccessText (Zeilen und Spalten 1-basiert).</summary>
  cPluginAnswer = '{"ok":true,"build":{"project":"C:\\P\\App.dproj","kind":"make","configuration":"Debug",' +
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
  mRequest: string;
begin
  Result := False;
  if not TDirectory.Exists(AInbox) then
  begin
    Exit;
  end;
  for mRequest in TDirectory.GetFiles(AInbox, '*.json') do
  begin
    if not mRequest.EndsWith('.result.json') then
    begin
      RenameFile(mRequest, ChangeFileExt(mRequest, '.taken'));
      ARequest := TFile.ReadAllText(ChangeFileExt(mRequest, '.taken'), TEncoding.UTF8);
      if AAnswer <> '' then
      begin
        TFile.WriteAllText(ChangeFileExt(mRequest, '') + '.result.json', AAnswer, TEncoding.UTF8);
      end;
      Exit(True);
    end;
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

function Candidates(const AFiles: TArray<string>): TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := AFiles;
    end;
end;

function Consent(AValue: Boolean): TMcpMayOpenFunc;
begin
  Result :=
    function(const AProjectFile: string; out AReason: string): Boolean
    begin
      AReason := 'abgelehnt';
      Result := AValue;
    end;
end;

var
  /// <summary>Zuletzt gestellte Frage von Chooser.</summary>
  GAsked: string;

function Chooser(AChoice: Integer): TMcpChooseFunc;
begin
  GAsked := '';
  Result :=
    function(const AText: string; const AOptions: TArray<string>): Integer
    begin
      GAsked := AText;
      Result := AChoice;
    end;
end;

{ TMcpIdeBuildsTests }

procedure TMcpIdeBuildsTests.Setup;
begin
  FInbox := TMcpIdeBuilds.InboxOf(TPath.Combine(TPath.GetTempPath, 'Atlas-IdeBuilds-' + IntToStr(Random(MaxInt))),
    42);
  Now_ := 0;
end;

procedure TMcpIdeBuildsTests.TearDown;
begin
  RemoveTestInbox(FInbox);
end;

procedure TMcpIdeBuildsTests.ReadsIdeEntry;
var
  mEntry: TMcpIdeEntry;
begin
  Assert.IsTrue(TMcpIdeBuilds.ParseEntry('{"pid": 4711, "files": [], "open": [], ' +
    '"projects": ["C:\\P\\App.dproj", "C:\\P\\Lib.dproj"], "activeProject": "C:\\P\\App.dproj"}', mEntry));
  Assert.AreEqual(Cardinal(4711), mEntry.Pid);
  Assert.AreEqual(2, Integer(Length(mEntry.Projects)));
  Assert.AreEqual('C:\P\Lib.dproj', mEntry.Projects[1]);
  Assert.AreEqual('C:\P\App.dproj', mEntry.ActiveProject);
  // Älteres Plugin ohne Projekte: Eintrag ja, Projekte leer.
  Assert.IsTrue(TMcpIdeBuilds.ParseEntry('{"pid": 1, "files": []}', mEntry));
  Assert.AreEqual(0, Integer(Length(mEntry.Projects)));
  Assert.IsFalse(TMcpIdeBuilds.ParseEntry('{"files": []}', mEntry));
  Assert.IsFalse(TMcpIdeBuilds.ParseEntry('kaputt', mEntry));
end;

procedure TMcpIdeBuildsTests.PicksActiveProjectUnderRoot;
var
  mPid: Cardinal;
  mProject, mReason: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(1, ['C:\Other\X.dproj'], 'C:\Other\X.dproj'),
    Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', '', mPid, mProject, mReason));
  Assert.AreEqual(Cardinal(2), mPid);
  Assert.AreEqual('C:\P\App.dproj', mProject);
  Assert.IsFalse(TMcpIdeBuilds.Pick([Ide(1, ['C:\Other\X.dproj'], 'C:\Other\X.dproj')], 'C:\P', '', mPid, mProject,
    mReason));
  Assert.IsTrue(Pos('aktives Projekt', mReason) > 0, mReason);
end;

procedure TMcpIdeBuildsTests.PicksProjectByName;
var
  mPid: Cardinal;
  mProject, mReason: string;
begin
  // Dateiname, Name ohne Endung und voller Pfad; nicht aktive Projekte zählen auch.
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj', 'C:\P\Lib\Lib.dproj'], 'C:\P\App.dproj')], 'C:\P',
    'Lib.dproj', mPid, mProject, mReason));
  Assert.AreEqual('C:\P\Lib\Lib.dproj', mProject);
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'app', mPid, mProject, mReason));
  Assert.AreEqual('C:\P\App.dproj', mProject);
  Assert.IsTrue(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'C:\P\App.dproj', mPid, mProject, mReason));
  Assert.AreEqual(Cardinal(7), mPid);
end;

procedure TMcpIdeBuildsTests.ExplainsWhenNoIdeHasTheProject;
var
  mPid: Cardinal;
  mProject, mReason: string;
begin
  Assert.IsFalse(TMcpIdeBuilds.Pick(nil, 'C:\P', 'App', mPid, mProject, mReason));
  Assert.IsTrue(Pos('Keine RAD-Studio-IDE', mReason) > 0, mReason);
  Assert.IsFalse(TMcpIdeBuilds.Pick([Ide(7, ['C:\P\App.dproj'], '')], 'C:\P', 'Kasse', mPid, mProject, mReason));
  Assert.IsTrue(Pos('Kasse', mReason) > 0, mReason);
  Assert.AreEqual(Cardinal(0), mPid);
end;

procedure TMcpIdeBuildsTests.OpensProjectAfterConsent;
var
  mPid: Cardinal;
  mProject, mReason: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.PickOrOpen([Ide(1, ['C:\Other\X.dproj'], 'C:\Other\X.dproj'),
    Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', 'AppTests',
    Candidates(TArray<string>.Create('C:\P\App.dproj', 'C:\P\Tests\AppTests.dproj')), Consent(True), mPid,
    mProject, mReason), mReason);
  Assert.AreEqual(Cardinal(2), mPid);
  Assert.AreEqual('C:\P\Tests\AppTests.dproj', mProject);
  // Offen ist offen: Pick gewinnt, ohne zu fragen.
  Assert.IsTrue(TMcpIdeBuilds.PickOrOpen([Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', 'App',
    Candidates(nil), Consent(False), mPid, mProject, mReason));
  Assert.AreEqual('C:\P\App.dproj', mProject);
end;

procedure TMcpIdeBuildsTests.KeepsReasonWhenConsentIsMissing;
var
  mPid: Cardinal;
  mProject, mReason: string;
begin
  Assert.IsFalse(TMcpIdeBuilds.PickOrOpen([Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', 'AppTests',
    Candidates(TArray<string>.Create('C:\P\Tests\AppTests.dproj')), Consent(False), mPid, mProject, mReason));
  Assert.AreEqual('abgelehnt', mReason);
  // Ohne Zustimmungsweg wie bisher: nur Pick.
  Assert.IsFalse(TMcpIdeBuilds.PickOrOpen([Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', 'AppTests',
    Candidates(TArray<string>.Create('C:\P\Tests\AppTests.dproj')), nil, mPid, mProject, mReason));
  Assert.IsTrue(Pos('AppTests', mReason) > 0, mReason);
  // Datei gibt es nicht: Grund von Pick.
  Assert.IsFalse(TMcpIdeBuilds.PickOrOpen([Ide(2, ['C:\P\App.dproj'], 'C:\P\App.dproj')], 'C:\P', 'Kasse',
    Candidates(TArray<string>.Create('C:\P\Tests\AppTests.dproj')), Consent(True), mPid, mProject, mReason));
  Assert.IsTrue(Pos('Kasse', mReason) > 0, mReason);
end;

procedure TMcpIdeBuildsTests.OpenPolicyDecides;
var
  mReason: string;
begin
  Assert.AreEqual(Ord(TMcpOpenProjects.Always), Ord(TMcpIdeBuilds.OpenPolicyOf('always')));
  Assert.AreEqual(Ord(TMcpOpenProjects.Never), Ord(TMcpIdeBuilds.OpenPolicyOf('never')));
  Assert.AreEqual(Ord(TMcpOpenProjects.Ask), Ord(TMcpIdeBuilds.OpenPolicyOf('')));
  Assert.IsTrue(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Always, 'C:\P\A.dproj', Chooser(1), mReason));
  Assert.AreEqual('', GAsked, 'always fragt nicht');
  Assert.IsFalse(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Never, 'C:\P\A.dproj', Chooser(0), mReason));
  Assert.IsTrue(Pos('never', mReason) > 0, mReason);
  Assert.AreEqual('', GAsked, 'never fragt nicht');
  Assert.IsFalse(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Ask, 'C:\P\A.dproj', nil, mReason));
  Assert.IsTrue(Pos('always', mReason) > 0, mReason);
end;

procedure TMcpIdeBuildsTests.AskAsksWithProjectName;
var
  mReason: string;
begin
  Assert.IsTrue(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Ask, 'C:\P\A.dproj', Chooser(0), mReason));
  Assert.IsTrue(Pos('A.dproj', GAsked) > 0, GAsked);
  Assert.IsFalse(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Ask, 'C:\P\A.dproj', Chooser(1), mReason));
  Assert.IsTrue(Pos('A.dproj', mReason) > 0, mReason);
  Assert.IsFalse(TMcpIdeBuilds.MayOpen(TMcpOpenProjects.Ask, 'C:\P\A.dproj', Chooser(TMcpConfirm.cNoAnswer),
    mReason));
  GAsked := '';
end;

procedure TMcpIdeBuildsTests.ReportsBuildOfThePlugin;
var
  mBuildText, mReason, mSeen: string;
  mJson: TJSONValue;
  mBuild: TIdeBuild;
  mWanted: TMcpIdeBuildRequest;
begin
  mWanted := Request('C:\P\App.dproj', 'Build');
  mWanted.Configuration := 'Release';
  Assert.AreEqual<TMcpIdeBuildOutcome>(TMcpIdeBuildOutcome.Done, TMcpIdeBuilds.Send(FInbox, mWanted,
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, cPluginAnswer, mSeen);
    end, Clock, mBuildText, mReason), mReason);
  mJson := TJSONObject.ParseJSONValue(mSeen);
  try
    Assert.AreEqual('C:\P\App.dproj', mJson.GetValue<string>('project'));
    Assert.AreEqual('build', mJson.GetValue<string>('mode'), 'klein geschrieben');
    Assert.AreEqual('Release', mJson.GetValue<string>('configuration'));
    Assert.AreEqual('', mJson.GetValue<string>('platform'));
  finally
    mJson.Free;
  end;
  // Das Ergebnis hat das Format von get_last_build.
  Assert.IsTrue(TMcpBuildTools.FromFileText(mBuildText, mBuild));
  Assert.AreEqual('mcp', mBuild.RequestedBy);
  Assert.AreEqual(1, Integer(Length(mBuild.Messages)));
  Assert.AreEqual(11, mBuild.Messages[0].Line);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(mBuild.Messages[0].Severity));
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox, '*.result.json'))), 'Antwort gelesen und gelöscht');
end;

procedure TMcpIdeBuildsTests.ReportsRefusal;
var
  mBuildText, mReason, mSeen: string;
begin
  Assert.AreEqual<TMcpIdeBuildOutcome>(TMcpIdeBuildOutcome.Refused,
    TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'make'),
    procedure
    begin
      Inc(Now_, 100);
      Plugin(FInbox, '{"ok":false,"reason":"In der IDE läuft der Debugger"}', mSeen);
    end, Clock, mBuildText, mReason));
  Assert.AreEqual('In der IDE läuft der Debugger', mReason);
  Assert.AreEqual('', mBuildText);
end;

procedure TMcpIdeBuildsTests.WithdrawsWhenNobodyTakesTheRequest;
var
  mBuildText, mReason: string;
begin
  Assert.AreEqual<TMcpIdeBuildOutcome>(TMcpIdeBuildOutcome.NotTaken,
    TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'make'),
    procedure
    begin
      Inc(Now_, 100);
    end, Clock, mBuildText, mReason));
  Assert.IsNotEmpty(mReason);
  Assert.AreEqual(0, Integer(Length(TDirectory.GetFiles(FInbox))), 'Auftrag zurückgezogen');
end;

procedure TMcpIdeBuildsTests.TimesOutWhenTakenButNeverAnswered;
var
  mBuildText, mReason, mSeen: string;
begin
  Assert.AreEqual<TMcpIdeBuildOutcome>(TMcpIdeBuildOutcome.TimedOut,
    TMcpIdeBuilds.Send(FInbox, Request('C:\P\App.dproj', 'check'), TMcpIdeWaiting.Make(
    procedure
    begin
      Inc(Now_, 1000);
      Plugin(FInbox, '', mSeen);
    end, Clock, 5000, 3000), mBuildText, mReason));
  Assert.IsNotEmpty(mReason);
  Assert.IsTrue(TMcpIdeBuilds.ModeValid('Check'));
  Assert.IsFalse(TMcpIdeBuilds.ModeValid('clean'));
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpIdeBuildsTests);

end.
