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
  mSummary: TAtlasProjectSummary;
  mNow_: TDateTime;
begin
  mSummary := TAtlasProjectSummary.Create('C:\Projekte\Demo.dproj');
  mNow_ := EncodeDate(2026, 10, 15) + EncodeTime(11, 0, 0, 0);
  TAtlasProjectRecording.RecordCompile(mSummary, [
    Message(TAtlasCompilerSeverity.Hint, 'C:\Projekte\A.pas', 1, 'H2077'),
    Message(TAtlasCompilerSeverity.Error, '', 0, 'F2613'),
    Message(TAtlasCompilerSeverity.Error, 'C:\Projekte\B.pas', 12, 'E2003'),
    Message(TAtlasCompilerSeverity.Fatal, 'C:\Projekte\C.pas', 1, 'F1026'),
    Message(TAtlasCompilerSeverity.Warning, 'C:\Projekte\A.pas', 4, 'W1000'),
    Message(TAtlasCompilerSeverity.Info, '', 0, '')],
    TAtlasProjectCompileRun.Create(False, False, 'build', 'Debug', 'Win32'), mNow_);
  Assert.IsTrue(mSummary.Build.Known);
  Assert.AreEqual(3, mSummary.Build.Errors, 'Fatal zählt als Fehler');
  Assert.AreEqual(1, mSummary.Build.Warnings);
  Assert.AreEqual(1, mSummary.Build.Hints);
  Assert.IsFalse(mSummary.Build.Succeeded);
  Assert.AreEqual('build', mSummary.Build.Kind);
  Assert.AreEqual('Debug', mSummary.Build.Configuration);
  Assert.AreEqual('Win32', mSummary.Build.Platform);
  Assert.AreEqual('C:\Projekte\B.pas', mSummary.Build.First.FileName, 'erste Fehlermeldung mit Datei');
  Assert.AreEqual(12, mSummary.Build.First.Line);
  Assert.AreEqual(3, mSummary.Build.First.Column);
  Assert.AreEqual('E2003', mSummary.Build.First.Code);
  Assert.AreEqual<TDateTime>(mNow_, mSummary.Build.At);
  Assert.IsFalse(mSummary.Check.Known, 'Build ist keine Prüfung');
  // Hintergrundprüfung (#548): nur "check", der Build bleibt.
  TAtlasProjectRecording.RecordCompile(mSummary, [], TAtlasProjectCompileRun.Create(True, True, 'check', 'Debug', 'Win32'),
    mNow_ + 1 / 24);
  Assert.IsTrue(mSummary.Check.Known);
  Assert.AreEqual(0, mSummary.Check.Errors);
  Assert.IsTrue(mSummary.Check.First.IsEmpty);
  Assert.AreEqual(3, mSummary.Build.Errors);
  // Neuer fehlerfreier Build ersetzt das Sprungziel.
  TAtlasProjectRecording.RecordCompile(mSummary, [], TAtlasProjectCompileRun.Create(False, True, 'make', 'Debug', 'Win32'),
    mNow_ + 2 / 24);
  Assert.AreEqual(0, mSummary.Build.Errors);
  Assert.IsTrue(mSummary.Build.First.IsEmpty);
  Assert.IsTrue(mSummary.Build.Succeeded);
end;

procedure TAtlasProjectRecordingTests.ProbeReadsHeadAndChanges;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasProjectVcs;
  mChange: TAtlasVcsChange;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mFake.FHead := TAtlasVcsHead.Empty;
  mFake.FHead.Branch := 'main';
  mFake.FHead.Revision := '0123456789';
  mFake.FHead.Ahead := 1;
  mFake.FHead.Behind := 2;
  mChange := Default(TAtlasVcsChange);
  mFake.FChanges := [mChange, mChange, mChange];
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState));
  Assert.IsTrue(mState.Known);
  Assert.IsTrue(mState.InWorkingCopy);
  Assert.AreEqual('git', mState.Kind);
  Assert.AreEqual('main', mState.Branch);
  Assert.AreEqual('0123456789', mState.Revision);
  Assert.AreEqual(3, mState.Changed);
  Assert.AreEqual(1, mState.Ahead);
  Assert.AreEqual(2, mState.Behind);
  Assert.AreEqual<TDateTime>(46000, mState.At);
  // Änderungen nicht lesbar (Zeitlimit): Branch gilt, Anzahl unbekannt.
  mFake.FChangesOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState));
  Assert.AreEqual(-1, mState.Changed);
  mFake.FKind := TAtlasVcsKind.Svn;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState));
  Assert.AreEqual('svn', mState.Kind);
end;

procedure TAtlasProjectRecordingTests.ProbeWithoutWorkingCopyIsNone;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasProjectVcs;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.None;
  mFake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState));
  Assert.AreEqual('none', mState.Kind);
  Assert.IsFalse(mState.InWorkingCopy);
  mFake.FHeadOutcome := TAtlasVcsOutcome.Disabled;
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState), 'vcs.provider = off');
  Assert.AreEqual('none', mState.Kind);
end;

procedure TAtlasProjectRecordingTests.ProbeFailureKeepsStoredState;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasProjectVcs;
  mOutcome: TAtlasVcsOutcome;
begin
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  for mOutcome in [TAtlasVcsOutcome.ToolMissing, TAtlasVcsOutcome.Failed, TAtlasVcsOutcome.TimedOut,
    TAtlasVcsOutcome.Cancelled, TAtlasVcsOutcome.MainThread] do
  begin
    mFake.FHeadOutcome := mOutcome;
    Assert.IsFalse(TAtlasProjectRecording.Probe(mVcs, 46000, mState), AtlasVcsOutcomeName(mOutcome));
    Assert.IsFalse(mState.Known);
  end;
  Assert.IsFalse(TAtlasProjectRecording.Probe(nil, 46000, mState));
end;

procedure TAtlasProjectRecordingTests.ProbeCountsChangesBelowProjectFolder;
var
  mFake: TFakeVcs;
  mVcs: IAtlasVersionControl;
  mState: TAtlasProjectVcs;
begin
  // Eine Arbeitskopie mit zwei Projekten: Je Projekt zählen nur seine Dateien.
  mFake := TFakeVcs.Create;
  mVcs := mFake;
  mFake.FKind := TAtlasVcsKind.Git;
  mFake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  mFake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  mFake.FHead := TAtlasVcsHead.Empty;
  mFake.FHead.Branch := 'main';
  mFake.FChanges := [VcsChange('C:\Repo\App\Main.pas', ''), VcsChange('C:/Repo/App/Sub/Neu.pas', ''),
    VcsChange('C:\Repo\Lib\Util.pas', ''), VcsChange('C:\Repo\Approved.txt', ''),
    VcsChange('C:\Repo\App\Umbenannt.pas', 'C:\Repo\Lib\Alt.pas'),
    VcsChange('C:\Repo\Lib\Weg.pas', 'C:\Repo\App\Weg.pas')];
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 'C:\Repo\App', 46000, mState));
  Assert.AreEqual(4, mState.Changed);
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 'c:\repo\lib\', 46000, mState));
  Assert.AreEqual(3, mState.Changed);
  Assert.IsTrue(TAtlasProjectRecording.Probe(mVcs, 46000, mState));
  Assert.AreEqual(6, mState.Changed, 'ohne Ordner alle');
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
  mStore: TAtlasProblemStore;
  mHits: Integer;
begin
  mStore := TAtlasProblemStore.Create;
  try
    // Regeltreffer zählen; Compilermeldungen, Syntaxfehler (ohne Code) und inaktive Zweige nicht.
    mStore.Update('C:\Repo\App\Main.pas', '', False, [Problem('with-statement', 'Atlas', False),
      Problem('E2003', TAtlasProblem.cCompilerSource, False), Problem('', 'Atlas', False),
      Problem('unused-variable', 'Atlas', False)], '', True);
    mStore.Update('C:\Repo\App\Sub\Daten.pas', '', False, [Problem('empty-except', 'Atlas', False),
      Problem('inactive', 'Atlas', True)], '', True);
    mStore.Update('C:\Repo\App\Sauber.pas', '', False, [], '', True);
    mStore.Update('C:\Repo\Lib\Util.pas', '', False, [Problem('with-statement', 'Atlas', False)], '', True);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo\App', mHits));
    Assert.AreEqual(3, mHits);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo\Lib', mHits));
    Assert.AreEqual(1, mHits);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo', mHits));
    Assert.AreEqual(4, mHits);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProjectRecordingTests.RuleHitsUnknownWithoutCheckedFiles;
var
  mStore: TAtlasProblemStore;
  mHits: Integer;
begin
  Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(nil, 'C:\Repo\App', mHits));
  mStore := TAtlasProblemStore.Create;
  try
    Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo\App', mHits), 'leer');
    mStore.Update('C:\Anders\Main.pas', '', False, [Problem('with-statement', 'Atlas', False)], '', True);
    Assert.IsFalse(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo\App', mHits), 'nur fremde Dateien');
    Assert.AreEqual(0, mHits);
    // Eine geprüfte Datei ohne Treffer: bekannt, 0.
    mStore.Update('C:\Repo\App\Main.pas', '', False, [], '', True);
    Assert.IsTrue(TAtlasProjectRecording.CountRuleHits(mStore, 'C:\Repo\App', mHits));
    Assert.AreEqual(0, mHits);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasProjectRecordingTests.RecordsRuleHits;
var
  mSummary: TAtlasProjectSummary;
  mPill: TAtlasProjectPill;
  mFound: Boolean;
begin
  mSummary := OnMain;
  TAtlasProjectRecording.RecordRules(mSummary, 4, 46000);
  Assert.IsTrue(mSummary.Rules.Known);
  Assert.AreEqual(4, mSummary.Rules.NewHits);
  Assert.AreEqual<TDateTime>(46000, mSummary.Rules.At);
  mFound := False;
  for mPill in TAtlasWelcomeProjects.Pills(Entry(mSummary)) do
  begin
    if mPill.Kind = TAtlasProjectPillKind.Rules then
    begin
      mFound := True;
      Assert.AreEqual(4, mPill.A);
    end;
  end;
  Assert.IsTrue(mFound);
  // 0 neue Treffer: bekannt, aber keine Marke.
  TAtlasProjectRecording.RecordRules(mSummary, 0, 46001);
  Assert.IsTrue(mSummary.Rules.Known);
  for mPill in TAtlasWelcomeProjects.Pills(Entry(mSummary)) do
  begin
    Assert.AreNotEqual<TAtlasProjectPillKind>(TAtlasProjectPillKind.Rules, mPill.Kind);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProjectRecordingTests);

end.
