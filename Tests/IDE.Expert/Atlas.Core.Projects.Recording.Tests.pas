unit Atlas.Core.Projects.Recording.Tests;

// Stand eines Projekts in seine Zusammenfassung (#528, #571, #97): Übernahme eines
// Compiles, Abfrage der Versionsverwaltung mit Ersatz-Umsetzung (geänderte Dateien nur im Projektordner, Ende
// einer hängenden Abfrage) und Regeltreffer aus den Problemen des Servers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasProjectRecordingTests = class
  public
    [Test]
    procedure RecordsBuildAndCheck;
    [Test]
    procedure ProbeReadsHeadAndChanges;
    [Test]
    procedure ProbeWithoutWorkingCopyIsNone;
    [Test]
    procedure ProbeFailureKeepsStoredState;
    [Test]
    procedure ProbeCountsChangesBelowProjectFolder;
    [Test]
    procedure InFolderIgnoresCaseAndSeparators;
    [Test]
    procedure QueryEndsAfterLimit;
    [Test]
    procedure CountsRuleHitsBelowProjectFolder;
    [Test]
    procedure RuleHitsUnknownWithoutCheckedFiles;
    [Test]
    procedure RecordsRuleHits;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Build.Messages,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Store,
  Atlas.Core.Projects.Recording,
  Atlas.Core.Welcome.Projects;

type
  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl)
  public
    FKind: TAtlasVcsKind;
    FHeadOutcome: TAtlasVcsOutcome;
    FChangesOutcome: TAtlasVcsOutcome;
    FHead: TAtlasVcsHead;
    FChanges: TArray<TAtlasVcsChange>;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
  end;

function VcsChange(const APath, AOldPath: string): TAtlasVcsChange;
begin
  Result := Default(TAtlasVcsChange);
  Result.Path := APath;
  Result.OldPath := AOldPath;
end;

function Entry(const ASummary: TAtlasProjectSummary): TAtlasProjectEntry;
begin
  Result := Default(TAtlasProjectEntry);
  Result.Summary := ASummary;
  Result.HasSummary := True;
end;

function OnMain: TAtlasProjectSummary;
begin
  Result := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Result.Vcs.Known := True;
  Result.Vcs.Kind := 'git';
  Result.Vcs.Branch := 'main';
  Result.Vcs.Revision := 'abcdef0123456789';
  Result.Vcs.Changed := 0;
  Result.Vcs.Ahead := 0;
  Result.Vcs.Behind := 0;
end;


function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := FKind;
end;

function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result := TAtlasVcsWorkingCopy.Empty;
  Result.Kind := FKind;
end;

function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := FHead;
  Result := FHeadOutcome;
end;

function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := FChanges;
  Result := FChangesOutcome;
end;

function TFakeVcs.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.ChangeMarker: string;
begin
  Result := '';
end;

function Message(ASeverity: TAtlasCompilerSeverity; const AFileName: string; ALine: Integer;
  const ACode: string): TAtlasCompilerMessage;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.Severity := ASeverity;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := 3;
  Result.Code := ACode;
  Result.Text := 'Text';
end;

function Problem(const ACode, ASource: string; AUnnecessary: Boolean): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.Code := ACode;
  Result.Source := ASource;
  Result.Message := 'Meldung ' + ACode;
  Result.Unnecessary := AUnnecessary;
end;

{ TAtlasProjectRecordingTests }

procedure TAtlasProjectRecordingTests.RecordsBuildAndCheck;
var
  Summary: TAtlasProjectSummary;
  Now_: TDateTime;
begin
  Summary := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  Now_ := EncodeDate(2026, 10, 15) + EncodeTime(11, 0, 0, 0);
  TAtlasProjectRecording.RecordCompile(Summary, [
    Message(TAtlasCompilerSeverity.Hint, 'C:\Projekte\A.pas', 1, 'H2077'),
    Message(TAtlasCompilerSeverity.Error, '', 0, 'F2613'),
    Message(TAtlasCompilerSeverity.Error, 'C:\Projekte\B.pas', 12, 'E2003'),
    Message(TAtlasCompilerSeverity.Fatal, 'C:\Projekte\C.pas', 1, 'F1026'),
    Message(TAtlasCompilerSeverity.Warning, 'C:\Projekte\A.pas', 4, 'W1000'),
    Message(TAtlasCompilerSeverity.Info, '', 0, '')],
    TAtlasProjectCompileRun.Create(False, False, 'build', 'Debug', 'Win32'), Now_);
  Assert.IsTrue(Summary.Build.Known);
  Assert.AreEqual(3, Summary.Build.Errors, 'Fatal zählt als Fehler');
  Assert.AreEqual(1, Summary.Build.Warnings);
  Assert.AreEqual(1, Summary.Build.Hints);
  Assert.IsFalse(Summary.Build.Succeeded);
  Assert.AreEqual('build', Summary.Build.Kind);
  Assert.AreEqual('Debug', Summary.Build.Configuration);
  Assert.AreEqual('Win32', Summary.Build.Platform);
  Assert.AreEqual('C:\Projekte\B.pas', Summary.Build.First.FileName, 'erste Fehlermeldung mit Datei');
  Assert.AreEqual(12, Summary.Build.First.Line);
  Assert.AreEqual(3, Summary.Build.First.Column);
  Assert.AreEqual('E2003', Summary.Build.First.Code);
  Assert.AreEqual<TDateTime>(Now_, Summary.Build.At);
  Assert.IsFalse(Summary.Check.Known, 'Build ist keine Prüfung');
  // Hintergrundprüfung (#548): nur "check", der Build bleibt.
  TAtlasProjectRecording.RecordCompile(Summary, [], TAtlasProjectCompileRun.Create(True, True, 'check', 'Debug', 'Win32'),
    Now_ + 1 / 24);
  Assert.IsTrue(Summary.Check.Known);
  Assert.AreEqual(0, Summary.Check.Errors);
  Assert.IsTrue(Summary.Check.First.IsEmpty);
  Assert.AreEqual(3, Summary.Build.Errors);
  // Neuer fehlerfreier Build ersetzt das Sprungziel.
  TAtlasProjectRecording.RecordCompile(Summary, [], TAtlasProjectCompileRun.Create(False, True, 'make', 'Debug', 'Win32'),
    Now_ + 2 / 24);
  Assert.AreEqual(0, Summary.Build.Errors);
  Assert.IsTrue(Summary.Build.First.IsEmpty);
  Assert.IsTrue(Summary.Build.Succeeded);
end;

procedure TAtlasProjectRecordingTests.ProbeReadsHeadAndChanges;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
  Change: TAtlasVcsChange;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FHead := TAtlasVcsHead.Empty;
  Fake.FHead.Branch := 'main';
  Fake.FHead.Revision := '0123456789';
  Fake.FHead.Ahead := 1;
  Fake.FHead.Behind := 2;
  Change := Default(TAtlasVcsChange);
  Fake.FChanges := [Change, Change, Change];
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State));
  Assert.IsTrue(State.Known);
  Assert.IsTrue(State.InWorkingCopy);
  Assert.AreEqual('git', State.Kind);
  Assert.AreEqual('main', State.Branch);
  Assert.AreEqual('0123456789', State.Revision);
  Assert.AreEqual(3, State.Changed);
  Assert.AreEqual(1, State.Ahead);
  Assert.AreEqual(2, State.Behind);
  Assert.AreEqual<TDateTime>(46000, State.At);
  // Änderungen nicht lesbar (Zeitlimit): Branch gilt, Anzahl unbekannt.
  Fake.FChangesOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State));
  Assert.AreEqual(-1, State.Changed);
  Fake.FKind := TAtlasVcsKind.Svn;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State));
  Assert.AreEqual('svn', State.Kind);
end;

procedure TAtlasProjectRecordingTests.ProbeWithoutWorkingCopyIsNone;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.None;
  Fake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State));
  Assert.AreEqual('none', State.Kind);
  Assert.IsFalse(State.InWorkingCopy);
  Fake.FHeadOutcome := TAtlasVcsOutcome.Disabled;
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State), 'vcs.provider = off');
  Assert.AreEqual('none', State.Kind);
end;

procedure TAtlasProjectRecordingTests.ProbeFailureKeepsStoredState;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
  Outcome: TAtlasVcsOutcome;
begin
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  for Outcome in [TAtlasVcsOutcome.ToolMissing, TAtlasVcsOutcome.Failed, TAtlasVcsOutcome.TimedOut,
    TAtlasVcsOutcome.Cancelled, TAtlasVcsOutcome.MainThread] do
  begin
    Fake.FHeadOutcome := Outcome;
    Assert.IsFalse(TAtlasProjectRecording.Probe(Vcs, 46000, State), AtlasVcsOutcomeName(Outcome));
    Assert.IsFalse(State.Known);
  end;
  Assert.IsFalse(TAtlasProjectRecording.Probe(nil, 46000, State));
end;

procedure TAtlasProjectRecordingTests.ProbeCountsChangesBelowProjectFolder;
var
  Fake: TFakeVcs;
  Vcs: IAtlasVersionControl;
  State: TAtlasProjectVcs;
begin
  // Eine Arbeitskopie mit zwei Projekten: Je Projekt zählen nur seine Dateien.
  Fake := TFakeVcs.Create;
  Vcs := Fake;
  Fake.FKind := TAtlasVcsKind.Git;
  Fake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FHead := TAtlasVcsHead.Empty;
  Fake.FHead.Branch := 'main';
  Fake.FChanges := [VcsChange('C:\Repo\App\Main.pas', ''), VcsChange('C:/Repo/App/Sub/Neu.pas', ''),
    VcsChange('C:\Repo\Lib\Util.pas', ''), VcsChange('C:\Repo\Approved.txt', ''),
    VcsChange('C:\Repo\App\Umbenannt.pas', 'C:\Repo\Lib\Alt.pas'),
    VcsChange('C:\Repo\Lib\Weg.pas', 'C:\Repo\App\Weg.pas')];
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 'C:\Repo\App', 46000, State));
  Assert.AreEqual(4, State.Changed);
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 'c:\repo\lib\', 46000, State));
  Assert.AreEqual(3, State.Changed);
  Assert.IsTrue(TAtlasProjectRecording.Probe(Vcs, 46000, State));
  Assert.AreEqual(6, State.Changed, 'ohne Ordner alle');
end;

procedure TAtlasProjectRecordingTests.InFolderIgnoresCaseAndSeparators;
begin
  Assert.IsTrue(TAtlasProjectRecording.InFolder('C:\Repo\App\Main.pas', 'c:/repo/app'));
  Assert.IsTrue(TAtlasProjectRecording.InFolder('c:/repo/app/sub/x.pas', 'C:\Repo\App\'));
  Assert.IsFalse(TAtlasProjectRecording.InFolder('C:\Repo\Apps\Main.pas', 'C:\Repo\App'), 'Nachbarordner');
  Assert.IsFalse(TAtlasProjectRecording.InFolder('C:\Repo\Main.pas', 'C:\Repo\App'));
  Assert.IsFalse(TAtlasProjectRecording.InFolder('', 'C:\Repo'));
  Assert.IsFalse(TAtlasProjectRecording.InFolder('C:\Repo\Main.pas', ''));
end;

procedure TAtlasProjectRecordingTests.QueryEndsAfterLimit;
begin
  Assert.IsTrue(TAtlasProjectRecording.QueryRunning(1000, 1000));
  Assert.IsTrue(TAtlasProjectRecording.QueryRunning(1000, 1000 + TAtlasProjectRecording.cVcsQueryLimitMs - 1));
  Assert.IsFalse(TAtlasProjectRecording.QueryRunning(1000, 1000 + TAtlasProjectRecording.cVcsQueryLimitMs));
  Assert.IsFalse(TAtlasProjectRecording.QueryRunning(5000, 1000), 'Uhr zurück');
end;

procedure TAtlasProjectRecordingTests.CountsRuleHitsBelowProjectFolder;
var
  Store: TAtlasProblemStore;
  Hits: Integer;
begin
  Store := TAtlasProblemStore.Create;
  try
    // Regeltreffer zählen; Compilermeldungen, Syntaxfehler (ohne Code) und inaktive Zweige nicht.
    Store.Update('C:\Repo\App\Main.pas', '', False, [Problem('with-statement', 'Atlas', False),
      Problem('E2003', TAtlasProblem.cCompilerSource, False), Problem('', 'Atlas', False),
      Problem('unused-variable', 'Atlas', False)], '', True);
    Store.Update('C:\Repo\App\Sub\Daten.pas', '', False, [Problem('empty-except', 'Atlas', False),
      Problem('inactive', 'Atlas', True)], '', True);
    Store.Update('C:\Repo\App\Sauber.pas', '', False, [], '', True);
    Store.Update('C:\Repo\Lib\Util.pas', '', False, [Problem('with-statement', 'Atlas', False)], '', True);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo\App', Hits));
    Assert.AreEqual(3, Hits);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo\Lib', Hits));
    Assert.AreEqual(1, Hits);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo', Hits));
    Assert.AreEqual(4, Hits);
  finally
    Store.Free;
  end;
end;

procedure TAtlasProjectRecordingTests.RuleHitsUnknownWithoutCheckedFiles;
var
  Store: TAtlasProblemStore;
  Hits: Integer;
begin
  Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(nil, 'C:\Repo\App', Hits));
  Store := TAtlasProblemStore.Create;
  try
    Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo\App', Hits), 'leer');
    Store.Update('C:\Anders\Main.pas', '', False, [Problem('with-statement', 'Atlas', False)], '', True);
    Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo\App', Hits), 'nur fremde Dateien');
    Assert.AreEqual(0, Hits);
    // Eine geprüfte Datei ohne Treffer: bekannt, 0.
    Store.Update('C:\Repo\App\Main.pas', '', False, [], '', True);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(Store, 'C:\Repo\App', Hits));
    Assert.AreEqual(0, Hits);
  finally
    Store.Free;
  end;
end;

procedure TAtlasProjectRecordingTests.RecordsRuleHits;
var
  Summary: TAtlasProjectSummary;
  Pill: TAtlasProjectPill;
  Found: Boolean;
begin
  Summary := OnMain;
  TAtlasProjectRecording.RecordRules(Summary, 4, 46000);
  Assert.IsTrue(Summary.Rules.Known);
  Assert.AreEqual(4, Summary.Rules.NewHits);
  Assert.AreEqual<TDateTime>(46000, Summary.Rules.At);
  Found := False;
  for Pill in TAtlasWelcomeProjects.Pills(Entry(Summary)) do
  begin
    if Pill.Kind = TAtlasProjectPillKind.Rules then
    begin
      Found := True;
      Assert.AreEqual(4, Pill.A);
    end;
  end;
  Assert.IsTrue(Found);
  // 0 neue Treffer: bekannt, aber keine Marke.
  TAtlasProjectRecording.RecordRules(Summary, 0, 46001);
  Assert.IsTrue(Summary.Rules.Known);
  for Pill in TAtlasWelcomeProjects.Pills(Entry(Summary)) do
  begin
    Assert.AreNotEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Rules, Pill.Kind);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectRecordingTests);

end.
