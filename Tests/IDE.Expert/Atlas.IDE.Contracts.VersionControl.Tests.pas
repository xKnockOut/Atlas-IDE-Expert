unit Atlas.IDE.Contracts.VersionControl.Tests;

// Zugang zur Versionsverwaltung (#1891): Ohne Modul antwortet TAtlasIdeVcs mit
// dem Null-Objekt (keine Arbeitskopie, nichts im Hintergrund, keine Dialoge);
// mit Bind gehen die Aufrufe an die Dienste des Moduls, nach Unbind wieder an
// das Null-Objekt.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIdeVcsAccessTests = class
  public
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WithoutModuleThereIsNoWorkingCopy;
    [Test]
    procedure WithoutModuleNothingRunsInBackground;
    [Test]
    procedure WithoutModuleDialogsAskNothing;
    [Test]
    procedure BoundServiceAnswersUntilUnbind;
    [Test]
    procedure AtLeastKeepsTheLargerTimeout;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.BranchPlan,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Projects.Vcs,
  Atlas.IDE.Contracts.VersionControl;

type
  /// <summary>Dienst eines gedachten Moduls: zählt Aufrufe, Hauptbranch „main“, Zeitlimit 5 s.</summary>
  TFakeVcsService = class(TAtlasNullVcsService, IAtlasVcsService)
  public
    Runs: Integer;
    function TimeoutMs: Cardinal;
    function MainBranchOf(const AProjectFile, AGroupFile: string): string;
    function Run(const AWork, ADone: TProc): Boolean;
  end;

function TFakeVcsService.TimeoutMs: Cardinal;
begin
  Result := 5000;
end;

function TFakeVcsService.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := 'main';
end;

function TFakeVcsService.Run(const AWork, ADone: TProc): Boolean;
begin
  Inc(Runs);
  Result := True;
end;

{ TAtlasIdeVcsAccessTests }

procedure TAtlasIdeVcsAccessTests.TearDown;
begin
  TAtlasIdeVcs.Unbind;
end;

procedure TAtlasIdeVcsAccessTests.WithoutModuleThereIsNoWorkingCopy;
var
  mVcs: IAtlasVersionControl;
  mHead: TAtlasVcsHead;
begin
  Assert.IsFalse(TAtlasIdeVcs.Available);
  mVcs := TAtlasIdeVcs.ForFolder('C:\Projekt');
  Assert.IsNotNull(mVcs, 'Null-Objekt statt nil');
  Assert.AreNotEqual(TAtlasVcsOutcome.Ok, mVcs.Head(mHead));
  Assert.AreEqual('', TAtlasIdeVcs.MainBranchOf('C:\Projekt\A.dproj', ''));
  Assert.AreEqual(TAtlasVcsProvider.Off, TAtlasIdeVcs.Provider);
end;

procedure TAtlasIdeVcsAccessTests.WithoutModuleNothingRunsInBackground;
var
  mRan: Boolean;
begin
  mRan := False;
  Assert.IsFalse(TAtlasIdeVcs.Run(
    procedure
    begin
      mRan := True;
    end, nil));
  Assert.IsFalse(mRan);
end;

procedure TAtlasIdeVcsAccessTests.WithoutModuleDialogsAskNothing;
var
  mRequest: TAtlasVcsBranchRequest;
  mNeverAsk, mStash: Boolean;
begin
  Assert.IsFalse(TAtlasIdeVcs.Dialogs.AskBranch('C:\Projekt', TAtlasVcsBranchFacts.Empty, 'feature/1', '', '1',
    TAtlasVcsSvnBranchOptions.Default, True, mRequest, mNeverAsk));
  Assert.IsFalse(mNeverAsk);
  Assert.IsFalse(TAtlasIdeVcs.Dialogs.AskUncommitted(3, 'feature/1', mStash));
  Assert.AreEqual('', TAtlasIdeVcs.Dialogs.WorktreeProject('A.dproj', 'C:\', 'C:\B'));
end;

procedure TAtlasIdeVcsAccessTests.BoundServiceAnswersUntilUnbind;
var
  mFake: TFakeVcsService;
  mService: IAtlasVcsService;
begin
  mFake := TFakeVcsService.Create;
  mService := mFake;
  TAtlasIdeVcs.Bind(mService, nil);
  Assert.IsTrue(TAtlasIdeVcs.Available);
  Assert.AreEqual('main', TAtlasIdeVcs.MainBranchOf('A.dproj', ''));
  Assert.IsTrue(TAtlasIdeVcs.Run(nil, nil));
  Assert.AreEqual(1, mFake.Runs);
  // Ohne Dialoge des Moduls antworten die Dialoge des Null-Objekts.
  Assert.AreEqual('', TAtlasIdeVcs.Dialogs.FailureText(TAtlasVcsKind.Git, nil, Default(TAtlasVcsBranchRun)));
  TAtlasIdeVcs.Unbind;
  Assert.IsFalse(TAtlasIdeVcs.Available);
  Assert.AreEqual('', TAtlasIdeVcs.MainBranchOf('A.dproj', ''));
  Assert.IsFalse(TAtlasIdeVcs.Run(nil, nil));
  Assert.AreEqual(1, mFake.Runs, 'nach Unbind erreicht nichts mehr das Modul');
end;

procedure TAtlasIdeVcsAccessTests.AtLeastKeepsTheLargerTimeout;
begin
  Assert.AreEqual(Cardinal(TAtlasIdeVcs.cDefaultTimeoutMs), TAtlasIdeVcs.AtLeast(1000));
  Assert.AreEqual(Cardinal(90000), TAtlasIdeVcs.AtLeast(90000));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIdeVcsAccessTests);

end.
