unit Atlas.Core.Welcome.ContinueWork.Tests;

// Ablauf von „Weiterarbeiten“ (#755) ohne IDE: Mitschreiben nur bei
// eingeschalteter Seite, Schreiben beim Schließen samt HEAD-Nachtrag,
// Fortsetzen mit fehlenden Dateien, Meldungen und nach Stop keine Antwort
// mehr. Die IDE ersetzt ein Host mit festen Werten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasContinueWorkTests = class
  public
    [Test]
    procedure RecordsChangesOnlyWithWelcomePage;
    [Test]
    procedure ClosingProjectWritesStateAndReportsIt;
    [Test]
    procedure HeadArrivesInWrittenState;
    [Test]
    procedure NoAnswerAfterStop;
    [Test]
    procedure StopWritesOpenProjectWithoutQuery;
    [Test]
    procedure ResumeOpensTabsAndNamesMissingFiles;
    [Test]
    procedure ResumeLatestWhenDisabledSaysSo;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Plugin.Projects.Contract.Summary,
  Atlas.Core.Welcome.Contract,
  Atlas.Core.Welcome.Continue,
  Atlas.Core.Welcome.ContinueWork;

const
  cProject = 'C:\Repo\Kasse.dproj';
  cUnit = 'C:\Repo\Main.pas';
  cOther = 'C:\Repo\Gone.pas';

type
  TFakeHost = class(TInterfacedObject, IAtlasContinueHost)
  public
    Options: TAtlasContinueSettings;
    Clock: UInt64;
    Target: string;
    Snapshot: TAtlasContinueSnapshot;
    Summaries: TDictionary<string, string>;
    Existing: TArray<string>;
    Recent: TArray<string>;
    HeadDone: TAtlasContinueHeadDone;
    HeadQueries: Integer;
    Opened: TArray<string>;
    Ensured: string;
    Said: TArray<string>;
    ChangedCount: Integer;
    constructor Create;
    destructor Destroy; override;
    function Settings: TAtlasContinueSettings;
    function Ticks: UInt64;
    function NowUtc: TDateTime;
    function CurrentTarget: string;
    function TargetOf(const AFileName: string): string;
    function TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
    function RecentProjects: TArray<string>;
    function LoadSummary(const ATarget: string; out ASummary: TAtlasProjectSummary): Boolean;
    procedure UpdateSummary(const ATarget: string; const AChange: TAtlasContinueSummaryChange);
    function QueryHead(const AFolder: string; const ADone: TAtlasContinueHeadDone): Boolean;
    function QueryIncoming(const ARequest: TAtlasContinueIncomingRequest;
      const ADone: TAtlasContinueIncomingDone): Boolean;
    function MainBranchOf(const AProject: string): string;
    function FileExists(const AFileName: string): Boolean;
    procedure EnsureProject(const AProject: string);
    procedure OpenTab(const ATab: TAtlasWorkTab);
    function Text(AText: TAtlasContinueText; const AArgument: string): string;
    procedure Say(const AText: string);
    procedure Changed;
    function Stored(const ATarget: string; out AState: TAtlasWorkState): Boolean;
  end;

constructor TFakeHost.Create;
begin
  inherited Create;
  Options.WelcomePage := True;
  Options.Continue := True;
  Options.Incoming := True;
  Options.Count := 5;
  Clock := 100000;
  Summaries := TDictionary<string, string>.Create;
end;

destructor TFakeHost.Destroy;
begin
  Summaries.Free;
  inherited Destroy;
end;

function TFakeHost.Settings: TAtlasContinueSettings;
begin
  Result := Options;
end;

function TFakeHost.Ticks: UInt64;
begin
  Result := Clock;
end;

function TFakeHost.NowUtc: TDateTime;
begin
  Result := EncodeDate(2026, 11, 19) + EncodeTime(12, 0, 0, 0);
end;

function TFakeHost.CurrentTarget: string;
begin
  Result := Target;
end;

function TFakeHost.TargetOf(const AFileName: string): string;
begin
  Result := AFileName;
end;

function TFakeHost.TakeSnapshot(AChanges: TDictionary<string, TAtlasWorkTab>): TAtlasContinueSnapshot;
begin
  Result := Snapshot;
end;

function TFakeHost.RecentProjects: TArray<string>;
begin
  Result := Recent;
end;

function TFakeHost.LoadSummary(const ATarget: string; out ASummary: TAtlasProjectSummary): Boolean;
var
  mRaw: string;
begin
  ASummary := TAtlasProjectSummary.Create(ATarget);
  Result := Summaries.TryGetValue(ATarget, mRaw);
  if Result then
  begin
    ASummary.Raw := mRaw;
  end;
end;

procedure TFakeHost.UpdateSummary(const ATarget: string; const AChange: TAtlasContinueSummaryChange);
var
  mSummary: TAtlasProjectSummary;
begin
  LoadSummary(ATarget, mSummary);
  AChange(mSummary);
  Summaries.AddOrSetValue(ATarget, mSummary.Raw);
end;

function TFakeHost.QueryHead(const AFolder: string; const ADone: TAtlasContinueHeadDone): Boolean;
begin
  Inc(HeadQueries);
  HeadDone := ADone;
  Result := True;
end;

function TFakeHost.QueryIncoming(const ARequest: TAtlasContinueIncomingRequest;
  const ADone: TAtlasContinueIncomingDone): Boolean;
begin
  Result := False;
end;

function TFakeHost.MainBranchOf(const AProject: string): string;
begin
  Result := 'main';
end;

function TFakeHost.FileExists(const AFileName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in Existing do
  begin
    Result := Result or SameText(mName, AFileName);
  end;
end;

procedure TFakeHost.EnsureProject(const AProject: string);
begin
  Ensured := AProject;
end;

procedure TFakeHost.OpenTab(const ATab: TAtlasWorkTab);
begin
  Opened := Opened + [ATab.FileName];
end;

function TFakeHost.Text(AText: TAtlasContinueText; const AArgument: string): string;
begin
  Result := Format('%d:%s', [Ord(AText), AArgument]);
end;

procedure TFakeHost.Say(const AText: string);
begin
  Said := Said + [AText];
end;

procedure TFakeHost.Changed;
begin
  Inc(ChangedCount);
end;

function TFakeHost.Stored(const ATarget: string; out AState: TAtlasWorkState): Boolean;
var
  mSummary: TAtlasProjectSummary;
begin
  AState := TAtlasWorkState.Empty;
  Result := LoadSummary(ATarget, mSummary) and TAtlasWelcomeContinue.Read(mSummary, AState);
end;

/// <summary>Reiter cUnit offen und aktiv.</summary>
function OneTab: TAtlasContinueSnapshot;
begin
  Result := Default(TAtlasContinueSnapshot);
  Result.Tabs := TArray<TAtlasWorkTab>.Create(TAtlasWorkTab.Create(cUnit, 12, 3));
  Result.Active := cUnit;
end;

{ TAtlasContinueWorkTests }

procedure TAtlasContinueWorkTests.RecordsChangesOnlyWithWelcomePage;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mHost.Options.WelcomePage := False;
  mWork.Modified(cUnit, 4, 2);
  Assert.AreEqual(0, Integer(mWork.Changes.Count), 'ohne Willkommensseite nichts mitschreiben');
  mHost.Options.WelcomePage := True;
  mWork.Modified(cUnit, 4, 2);
  mWork.Modified(cUnit, 9, 1);
  Assert.AreEqual(1, Integer(mWork.Changes.Count), 'je Datei die letzte Stelle');
  Assert.AreEqual(9, mWork.Changes[AnsiUpperCase(cUnit)].Line);
  Assert.IsTrue(mWork.Changes[AnsiUpperCase(cUnit)].Changed);
end;

procedure TAtlasContinueWorkTests.ClosingProjectWritesStateAndReportsIt;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
  mState: TAtlasWorkState;
  mWritten: string;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mWritten := '';
  mWork.OnWritten :=
    procedure(ATarget: string; ASnapshot: TAtlasContinueSnapshot)
    begin
      mWritten := ATarget;
    end;
  mHost.Snapshot := OneTab;
  mWork.Modified(cUnit, 12, 3);
  mWork.ProjectClosing(cProject);
  Assert.IsTrue(mHost.Stored(cProject, mState), 'Abschnitt "continue" geschrieben');
  Assert.AreEqual(1, mState.TabCount);
  Assert.AreEqual(cUnit, mState.Tabs[0].FileName);
  Assert.AreEqual(cProject, mWritten, 'Reiter „Issues“ bekommt denselben Stand');
  Assert.AreEqual(0, Integer(mWork.Changes.Count), 'neue Sitzung');
  Assert.AreEqual(1, mHost.HeadQueries, 'HEAD frisch abfragen');
  Assert.AreEqual(1, mHost.ChangedCount);
  // Das Projekt einer Gruppe meldet sich gleich danach noch einmal: nicht noch einmal schreiben.
  mHost.Clock := mHost.Clock + 100;
  mWork.ProjectClosing(cProject);
  Assert.AreEqual(1, mHost.HeadQueries);
  mWork.OnWritten := nil;
  // Der gemerkte Rückruf der HEAD-Abfrage hält die Arbeit, die Arbeit den Host: Ring lösen, sonst Leck.
  mHost.HeadDone := nil;
end;

procedure TAtlasContinueWorkTests.HeadArrivesInWrittenState;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
  mHead, mState: TAtlasWorkState;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mHost.Snapshot := OneTab;
  mWork.ProjectClosing(cProject);
  mHead := TAtlasWorkState.Empty;
  mHead.VcsKind := 'git';
  mHead.Head := 'abc123';
  mHead.Upstream := 'origin/main';
  mHost.HeadDone(True, mHead);
  Assert.IsTrue(mHost.Stored(cProject, mState));
  Assert.AreEqual('abc123', mState.Head, 'HEAD nachgetragen');
  Assert.AreEqual('origin/main', mState.Upstream);
  Assert.AreEqual(2, mHost.ChangedCount);
  // Der gemerkte Rückruf der HEAD-Abfrage hält die Arbeit, die Arbeit den Host: Ring lösen, sonst Leck.
  mHost.HeadDone := nil;
end;

procedure TAtlasContinueWorkTests.NoAnswerAfterStop;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
  mHead, mState: TAtlasWorkState;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mHost.Snapshot := OneTab;
  mWork.ProjectClosing(cProject);
  mWork.Stop;
  mHead := TAtlasWorkState.Empty;
  mHead.Head := 'abc123';
  mHost.HeadDone(True, mHead);
  Assert.IsTrue(mHost.Stored(cProject, mState));
  Assert.AreEqual('', mState.Head, 'nach Stop kommt nichts mehr an');
  Assert.AreEqual(1, mHost.ChangedCount);
  Assert.IsFalse(mWork.Enabled);
  // Der gemerkte Rückruf der HEAD-Abfrage hält die Arbeit, die Arbeit den Host: Ring lösen, sonst Leck.
  mHost.HeadDone := nil;
end;

procedure TAtlasContinueWorkTests.StopWritesOpenProjectWithoutQuery;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
  mState: TAtlasWorkState;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mHost.Snapshot := OneTab;
  mHost.Target := cProject;
  mWork.Stop;
  Assert.IsTrue(mHost.Stored(cProject, mState), 'Beenden der IDE schreibt das offene Projekt');
  Assert.AreEqual(1, mState.TabCount);
  Assert.AreEqual(0, mHost.HeadQueries, 'beim Beenden keine Abfrage');
  Assert.AreEqual(0, mHost.ChangedCount, 'und kein Zeichnen');
end;

procedure TAtlasContinueWorkTests.ResumeOpensTabsAndNamesMissingFiles;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
  mState: TAtlasWorkState;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mState := TAtlasWorkState.Empty;
  mState.Known := True;
  mState.Tabs := TArray<TAtlasWorkTab>.Create(TAtlasWorkTab.Create(cUnit, 3, 1), TAtlasWorkTab.Create(cOther, 5, 1));
  mState.Active := 0;
  mHost.UpdateSummary(cProject,
    procedure(var ASummary: TAtlasProjectSummary)
    begin
      TAtlasWelcomeContinue.Write(ASummary, mState);
    end);
  mHost.Existing := TArray<string>.Create(cProject, cUnit);
  mWork.Resume(cProject);
  Assert.AreEqual(cProject, mHost.Ensured, 'Projekt geöffnet');
  Assert.AreEqual(2, Integer(Length(mHost.Opened)), 'vorhandener Reiter, danach der aktive noch einmal');
  Assert.AreEqual(cUnit, mHost.Opened[0]);
  Assert.AreEqual(Format('%d:%s', [Ord(TAtlasContinueText.FilesMissing),
    TAtlasContinueSession.MissingNames(TArray<string>.Create(cOther))]), mWork.Notice);
  Assert.AreEqual(1, Integer(Length(mHost.Said)));
end;

procedure TAtlasContinueWorkTests.ResumeLatestWhenDisabledSaysSo;
var
  mHost: TFakeHost;
  mHostRef: IAtlasContinueHost;
  mWork: TAtlasContinueWork;
  mWorkRef: IInterface;
begin
  mHost := TFakeHost.Create;
  mHostRef := mHost;
  mWork := TAtlasContinueWork.Create(mHostRef);
  mWorkRef := mWork;
  mHost.Options.Continue := False;
  mWork.ResumeLatest;
  Assert.AreEqual(1, Integer(Length(mHost.Said)));
  Assert.AreEqual(Format('%d:', [Ord(TAtlasContinueText.Disabled)]), mHost.Said[0]);
  mHost.Options.Continue := True;
  mWork.ResumeLatest;
  Assert.AreEqual(Format('%d:', [Ord(TAtlasContinueText.Nothing)]), mHost.Said[1], 'ohne Eintrag');
  Assert.AreEqual(0, Integer(Length(mHost.Opened)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasContinueWorkTests);

end.
