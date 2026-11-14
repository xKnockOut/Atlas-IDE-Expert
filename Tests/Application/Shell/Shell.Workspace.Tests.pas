unit Shell.Workspace.Tests;

// Reload nur im Thread der Nachrichtenschleife; Bereitschaft für
// Prüfungen ohne Projekt (#1220).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellWorkspaceTests = class
  public
    [Test]
    procedure ReloadOutsideLoopThreadRaises;
    /// <summary>Einheitliche Wahl des Arbeitsbereichs: Treffer, sonst der einzige, sonst keiner.</summary>
    [Test]
    procedure ChooseFallsBackToSingleWorkspace;
    /// <summary>Unit in mehreren Projekten (#1112): Gleiche Art bleibt, verschiedene Arten ergeben Unknown,
    /// Projekte ohne die Datei zählen nicht.</summary>
    [Test]
    procedure MergeRuleProjectsKeepsOnlyUnambiguousKind;
    /// <summary>Ordner ohne Projekt (#1220): Nach dem Aufbau wartet keine Prüfung mehr auf ein Projekt, vorher
    /// schon.</summary>
    [Test]
    procedure WorkspaceWithoutProjectIsRuleReady;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.Generics.Collections,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker,
  Shell.Workspace.Setup,
  Shell.Workspace.RuleProjects,
  Shell.Workspace;

function NewWorkspace(const AName: string): TShellWorkspace;
begin
  Result := TShellWorkspace.Create('', AName, TShellWorkspaceServices.Create(TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index'));
end;

{ TShellWorkspaceTests }

procedure TShellWorkspaceTests.ReloadOutsideLoopThreadRaises;
var
  mWorkspace: TShellWorkspace;
  mWorker: TThread;
  mRaised: string;
begin
  mRaised := '';
  mWorkspace := NewWorkspace('Test');
  try
    mWorkspace.Setup.LoopThreadId := TThread.Current.ThreadID;
    mWorker := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          mWorkspace.Reload;
        except
          on E: Exception do
            mRaised := E.ClassName;
        end;
      end);
    mWorker.FreeOnTerminate := False;
    try
      mWorker.Start;
      mWorker.WaitFor;
    finally
      mWorker.Free;
    end;
    Assert.AreEqual('EInvalidOpException', mRaised);
  finally
    mWorkspace.Free;
  end;
end;

procedure TShellWorkspaceTests.ChooseFallsBackToSingleWorkspace;
var
  mAll: TObjectList<TShellWorkspace>;
  A, B: TShellWorkspace;
begin
  mAll := TObjectList<TShellWorkspace>.Create(True);
  try
    Assert.IsNull(TShellWorkspaces.Choose(nil, mAll), 'Ohne Arbeitsbereich keiner');
    Assert.IsNull(TShellWorkspaces.Choose(nil, nil));
    A := NewWorkspace('A');
    mAll.Add(A);
    Assert.AreSame(A, TShellWorkspaces.Choose(nil, mAll), 'Einziger Arbeitsbereich als Rückfall');
    B := NewWorkspace('B');
    mAll.Add(B);
    Assert.IsNull(TShellWorkspaces.Choose(nil, mAll), 'Bei mehreren kein Rückfall');
    Assert.AreSame(B, TShellWorkspaces.Choose(B, mAll), 'Treffer geht vor');
  finally
    mAll.Free;
  end;
end;

function Member(const AName: string; AKind: TRuleApplicationKind): TCheckProject;
begin
  Result := Default(TCheckProject);
  Result.Application := AKind;
  Result.Name := AName;
  Result.ProjectMainSource := AName + '.dpr';
end;

procedure TShellWorkspaceTests.MergeRuleProjectsKeepsOnlyUnambiguousKind;
var
  mOutside, mMerged: TCheckProject;
begin
  mOutside := Default(TCheckProject);
  mMerged := TShellRuleProjects.MergeRuleProjects(nil, 'U.pas');
  Assert.AreEqual('U.pas', mMerged.FileName);
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Unknown, mMerged.Application, 'Ohne Projekt unbekannt');
  mMerged := TShellRuleProjects.MergeRuleProjects([mOutside, Member('Tests', TRuleApplicationKind.Console)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Console,
    mMerged.Application, 'Projekt ohne die Datei zählt nicht');
  Assert.AreEqual('Tests', mMerged.Name);
  Assert.AreEqual('U.pas', mMerged.FileName);
  mMerged := TShellRuleProjects.MergeRuleProjects([Member('A', TRuleApplicationKind.Gui),
    Member('B', TRuleApplicationKind.Gui)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Gui, mMerged.Application, 'Gleiche Art bleibt');
  Assert.AreEqual('A', mMerged.Name, 'Das erste Projekt liefert den Namen');
  mMerged := TShellRuleProjects.MergeRuleProjects([Member('Tests', TRuleApplicationKind.Console),
    Member('Plugin', TRuleApplicationKind.Package), Member('Noch', TRuleApplicationKind.Console)], 'U.pas');
  Assert.AreEqual<TRuleApplicationKind>(TRuleApplicationKind.Unknown,
    mMerged.Application, 'Verschiedene Arten ergeben Unknown');
  Assert.AreEqual('Tests', mMerged.Name);
end;

procedure TShellWorkspaceTests.WorkspaceWithoutProjectIsRuleReady;
var
  mWorkspace: TShellWorkspace;
  mReason: string;
begin
  mWorkspace := NewWorkspace('Ohne');
  try
    mWorkspace.Setup.LoopThreadId := TThread.Current.ThreadID;
    Assert.IsFalse(mWorkspace.RuleReady(mReason), 'Vor dem ersten Aufbau ist offen, ob ein Projekt kommt');
    Assert.AreEqual('Projekte werden geladen', mReason);
    mWorkspace.Reload;
    Assert.IsTrue(mWorkspace.RuleReady(mReason), mReason);
    Assert.AreEqual('', mReason);
  finally
    mWorkspace.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceTests);

end.
