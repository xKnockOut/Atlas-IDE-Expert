unit Atlas.Core.VersionControl.Pull.Tests;

// Tests des Holens einer Arbeitskopie ohne Prozess (#764, #1292, nach Base
// gezogen mit #1456): Pull prüft vor dem Holen die Änderungen (versionierte
// sperren, unversionierte nicht), meldet geholt bzw. aktuell, holt unter SVN
// auf Wunsch ohne Externals und nennt bei Fehlern den Grund.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasVcsPullTests = class
  public
    [Test]
    procedure PullChecksChangesBeforeFetching;
    [Test]
    procedure PullReportsUpdatedAndUpToDate;
    /// <summary>#1292: ohne Externals über IAtlasVcsSvnExternals.Update(True), sonst Pull.</summary>
    [Test]
    procedure PullWithAndWithoutExternals;
    [Test]
    procedure PullFailuresAndNoWorkingCopy;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Pull;

type
  /// <summary>Ersatz für Git bzw. SVN: festgelegte Ergebnisse ohne Prozess; Pull setzt die Revision weiter.
  /// </summary>
  TFakeVcs = class(TInterfacedObject, IAtlasVersionControl, IAtlasVcsUpdate)
  public
    FHead: TAtlasVcsHead;
    FHeadOutcome: TAtlasVcsOutcome;
    FChanges: TArray<TAtlasVcsChange>;
    FChangesOutcome: TAtlasVcsOutcome;
    FPullOutcome: TAtlasVcsOutcome;
    /// <summary>Revision nach Pull; '' = unverändert.</summary>
    FPulledRevision: string;
    Calls: TArray<string>;
    constructor Create;
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
    function Pull: TAtlasVcsOutcome;
    function Called(const AName: string): Boolean;
  end;

  /// <summary>SVN mit Externals (#1292): Update protokolliert, ob ohne Externals.</summary>
  TFakeSvnExternals = class(TFakeVcs, IAtlasVcsSvnExternals)
  public
    function StatusXml(out AText: string): TAtlasVcsOutcome;
    function Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
    function CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
    function SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
  end;

  /// <summary>Ohne IAtlasVcsUpdate (z. B. eine fremde Umsetzung): Pull schlägt fehl.</summary>
  TFakeVcsWithoutUpdate = class(TInterfacedObject, IAtlasVersionControl)
  public
    function Kind: TAtlasVcsKind;
    function WorkingCopy: TAtlasVcsWorkingCopy;
    function Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
    function Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
    function FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
    function Blame(const AFileName: string; out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
    function ChangeMarker: string;
  end;

function Change(const APath: string; AKind: TAtlasVcsChangeKind): TAtlasVcsChange;
begin
  Result := Default(TAtlasVcsChange);
  Result.Path := APath;
  Result.Kind := AKind;
end;

{ TFakeVcs }

constructor TFakeVcs.Create;
begin
  inherited Create;
  FHead := TAtlasVcsHead.Empty;
  FHead.Branch := 'main';
  FHead.Revision := 'aaaa';
  FHeadOutcome := TAtlasVcsOutcome.Ok;
  FChangesOutcome := TAtlasVcsOutcome.Ok;
  FPullOutcome := TAtlasVcsOutcome.Ok;
end;

function TFakeVcs.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TFakeVcs.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := 'C:\Repo';
end;

function TFakeVcs.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  Calls := Calls + ['head'];
  AHead := FHead;
  Result := FHeadOutcome;
end;

function TFakeVcs.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  Calls := Calls + ['changes'];
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
  Result := FHead.Revision;
end;

function TFakeVcs.Pull: TAtlasVcsOutcome;
begin
  Calls := Calls + ['pull'];
  Result := FPullOutcome;
  if (Result = TAtlasVcsOutcome.Ok) and (FPulledRevision <> '') then
  begin
    FHead.Revision := FPulledRevision;
  end;
end;

{ TFakeSvnExternals }

function TFakeSvnExternals.StatusXml(out AText: string): TAtlasVcsOutcome;
begin
  AText := '';
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvnExternals.Update(AIgnoreExternals: Boolean): TAtlasVcsOutcome;
begin
  Calls := Calls + ['update ' + BoolToStr(AIgnoreExternals, True)];
  Result := FPullOutcome;
  if (Result = TAtlasVcsOutcome.Ok) and (FPulledRevision <> '') then
  begin
    FHead.Revision := FPulledRevision;
  end;
end;

function TFakeSvnExternals.CommitsSince(const APath, ARevision: string; out ACount: Integer): TAtlasVcsOutcome;
begin
  ACount := 0;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeSvnExternals.SetExternals(const AOwner, AText: string): TAtlasVcsOutcome;
begin
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcs.Called(const AName: string): Boolean;
var
  mCall: string;
begin
  Result := False;
  for mCall in Calls do
  begin
    if mCall = AName then
    begin
      Exit(True);
    end;
  end;
end;

{ TFakeVcsWithoutUpdate }

function TFakeVcsWithoutUpdate.Kind: TAtlasVcsKind;
begin
  Result := TAtlasVcsKind.Git;
end;

function TFakeVcsWithoutUpdate.WorkingCopy: TAtlasVcsWorkingCopy;
begin
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := 'C:\Repo';
end;

function TFakeVcsWithoutUpdate.Head(out AHead: TAtlasVcsHead): TAtlasVcsOutcome;
begin
  AHead := TAtlasVcsHead.Empty;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcsWithoutUpdate.Changes(out AChanges: TArray<TAtlasVcsChange>): TAtlasVcsOutcome;
begin
  AChanges := nil;
  Result := TAtlasVcsOutcome.Ok;
end;

function TFakeVcsWithoutUpdate.FileAt(const AFileName, ARevision: string; out AContent: TBytes): TAtlasVcsOutcome;
begin
  AContent := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcsWithoutUpdate.Blame(const AFileName: string;
  out ALines: TArray<TAtlasVcsBlameLine>): TAtlasVcsOutcome;
begin
  ALines := nil;
  Result := TAtlasVcsOutcome.Failed;
end;

function TFakeVcsWithoutUpdate.ChangeMarker: string;
begin
  Result := '';
end;

{ TAtlasVcsPullTests }

procedure TAtlasVcsPullTests.PullChecksChangesBeforeFetching;
var
  Fake: TFakeVcs;
  Ref: IAtlasVersionControl;
begin
  Fake := TFakeVcs.Create;
  Ref := Fake;
  Fake.FChanges := [Change('C:\Repo\a.pas', TAtlasVcsChangeKind.Modified)];
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Blocked);
  Assert.IsFalse(Fake.Called('pull'), 'lokale Änderung: nichts holen');
  // Unversionierte Dateien sperren nicht.
  Fake.FChanges := [Change('C:\Repo\neu.pas', TAtlasVcsChangeKind.Untracked)];
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.UpToDate);
  Assert.IsTrue(Fake.Called('pull'));
  Assert.IsTrue(TAtlasVcsPull.ChangesBlockPull([Change('x', TAtlasVcsChangeKind.Untracked),
    Change('y', TAtlasVcsChangeKind.Conflicted)]));
  Assert.IsFalse(TAtlasVcsPull.ChangesBlockPull(nil));
end;

procedure TAtlasVcsPullTests.PullReportsUpdatedAndUpToDate;
var
  Fake: TFakeVcs;
  Ref: IAtlasVersionControl;
begin
  Fake := TFakeVcs.Create;
  Ref := Fake;
  Fake.FPulledRevision := 'bbbb';
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Updated);
  Assert.AreEqual('head', Fake.Calls[0]);
  Assert.AreEqual('changes', Fake.Calls[1]);
  Assert.AreEqual('pull', Fake.Calls[2]);
  Assert.AreEqual('head', Fake.Calls[3]);
  Fake.FPulledRevision := '';
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.UpToDate);
end;

procedure TAtlasVcsPullTests.PullWithAndWithoutExternals;
var
  mFake: TFakeSvnExternals;
  mPlain: TFakeVcs;
  mRef, mPlainRef: IAtlasVersionControl;
  mReason: TAtlasVcsOutcome;
begin
  mFake := TFakeSvnExternals.Create;
  mRef := mFake;
  mFake.FPulledRevision := '48300';
  Assert.IsTrue(TAtlasVcsPull.Pull(mRef, True, mReason) = TAtlasPullOutcome.Updated);
  Assert.IsTrue(mReason = TAtlasVcsOutcome.Ok);
  Assert.IsTrue(mFake.Called('update True'));
  Assert.IsFalse(mFake.Called('pull'));
  mFake.Calls := nil;
  Assert.IsTrue(TAtlasVcsPull.Pull(mRef, False, mReason) = TAtlasPullOutcome.UpToDate);
  Assert.IsTrue(mFake.Called('pull'), 'mit Externals = Pull des Providers');
  // Ohne lokale Änderungen weiterhin gesperrt, auch ohne Externals.
  mFake.Calls := nil;
  mFake.FChanges := TArray<TAtlasVcsChange>.Create(Change('C:\Repo\Packages\Basis\A.pas',
    TAtlasVcsChangeKind.Modified));
  Assert.IsTrue(TAtlasVcsPull.Pull(mRef, True, mReason) = TAtlasPullOutcome.Blocked);
  Assert.IsFalse(mFake.Called('update True'));
  mFake.FChanges := nil;
  mFake.FPullOutcome := TAtlasVcsOutcome.LoginNeeded;
  Assert.IsTrue(TAtlasVcsPull.Pull(mRef, True, mReason) = TAtlasPullOutcome.Failed);
  Assert.IsTrue(mReason = TAtlasVcsOutcome.LoginNeeded);
  // Git kennt keine Externals: holt wie immer.
  mPlain := TFakeVcs.Create;
  mPlainRef := mPlain;
  Assert.IsTrue(TAtlasVcsPull.Pull(mPlainRef, True, mReason) = TAtlasPullOutcome.UpToDate);
  Assert.IsTrue(mPlain.Called('pull'));
  mFake.Calls := nil;
  mPlain.Calls := nil;
end;

procedure TAtlasVcsPullTests.PullFailuresAndNoWorkingCopy;
var
  Fake: TFakeVcs;
  Ref: IAtlasVersionControl;
  Reason: TAtlasVcsOutcome;
begin
  Assert.IsTrue(TAtlasVcsPull.Pull(nil) = TAtlasPullOutcome.NoWorkingCopy);
  Fake := TFakeVcs.Create;
  Ref := Fake;
  Fake.FHeadOutcome := TAtlasVcsOutcome.NoWorkingCopy;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.NoWorkingCopy);
  Fake.FHeadOutcome := TAtlasVcsOutcome.ToolMissing;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Failed);
  Fake.FHeadOutcome := TAtlasVcsOutcome.Ok;
  Fake.FChangesOutcome := TAtlasVcsOutcome.TimedOut;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Failed, 'Stand unklar: nicht holen');
  Assert.IsFalse(Fake.Called('pull'));
  // Grund für die Meldung: das Ergebnis des gescheiterten Aufrufs.
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref, Reason) = TAtlasPullOutcome.Failed);
  Assert.IsTrue(Reason = TAtlasVcsOutcome.TimedOut);
  Fake.FChangesOutcome := TAtlasVcsOutcome.Ok;
  Fake.FPullOutcome := TAtlasVcsOutcome.Failed;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Failed, 'z. B. abweichender Branch');
  Fake.FPullOutcome := TAtlasVcsOutcome.ToolMissing;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref, Reason) = TAtlasPullOutcome.Failed);
  Assert.IsTrue(Reason = TAtlasVcsOutcome.ToolMissing);
  Fake.FPullOutcome := TAtlasVcsOutcome.Ok;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref, Reason) = TAtlasPullOutcome.UpToDate);
  Assert.IsTrue(Reason = TAtlasVcsOutcome.Ok);
  Ref := TFakeVcsWithoutUpdate.Create;
  Assert.IsTrue(TAtlasVcsPull.Pull(Ref) = TAtlasPullOutcome.Failed);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasVcsPullTests);

end.
