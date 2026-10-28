unit Shell.Workspace.Tests;

// Reload nur im Thread der Nachrichtenschleife (Code-Review A-03); Bereitschaft für
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
    /// <summary>Einheitliche Wahl des Arbeitsbereichs (S-02): Treffer, sonst der einzige, sonst keiner.</summary>
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
  Shell.Workspace;

function NewWorkspace(const AName: string): TShellWorkspace;
begin
  Result := TShellWorkspace.Create('', AName, TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index');
end;

{ TShellWorkspaceTests }

procedure TShellWorkspaceTests.ReloadOutsideLoopThreadRaises;
var
  Workspace: TShellWorkspace;
  Worker: TThread;
  Raised: string;
begin
  Raised := '';
  Workspace := TShellWorkspace.Create('', 'Test', TDocumentStore.Create,
    TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True), TLogger.Create, TSymbolIndex.Create,
    'atlas-test-index');
  try
    Workspace.LoopThreadId := TThread.Current.ThreadID;
    Worker := TThread.CreateAnonymousThread(
      procedure
      begin
        try
          Workspace.Reload;
        except
          on E: Exception do
            Raised := E.ClassName;
        end;
      end);
    Worker.FreeOnTerminate := False;
    try
      Worker.Start;
      Worker.WaitFor;
    finally
      Worker.Free;
    end;
    Assert.AreEqual('EInvalidOpException', Raised);
  finally
    Workspace.Free;
  end;
end;

procedure TShellWorkspaceTests.ChooseFallsBackToSingleWorkspace;
var
  All: TObjectList<TShellWorkspace>;
  A, B: TShellWorkspace;
begin
  All := TObjectList<TShellWorkspace>.Create(True);
  try
    Assert.IsNull(TShellWorkspace.Choose(nil, All), 'Ohne Arbeitsbereich keiner');
    Assert.IsNull(TShellWorkspace.Choose(nil, nil));
    A := NewWorkspace('A');
    All.Add(A);
    Assert.AreSame(A, TShellWorkspace.Choose(nil, All), 'Einziger Arbeitsbereich als Rückfall');
    B := NewWorkspace('B');
    All.Add(B);
    Assert.IsNull(TShellWorkspace.Choose(nil, All), 'Bei mehreren kein Rückfall');
    Assert.AreSame(B, TShellWorkspace.Choose(B, All), 'Treffer geht vor');
  finally
    All.Free;
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
  Outside, Merged: TCheckProject;
begin
  Outside := Default(TCheckProject);
  Merged := TShellWorkspace.MergeRuleProjects(nil, 'U.pas');
  Assert.AreEqual('U.pas', Merged.FileName);
  Assert.IsTrue(Merged.Application = TRuleApplicationKind.Unknown, 'Ohne Projekt unbekannt');
  Merged := TShellWorkspace.MergeRuleProjects([Outside, Member('Tests', TRuleApplicationKind.Console)], 'U.pas');
  Assert.IsTrue(Merged.Application = TRuleApplicationKind.Console, 'Projekt ohne die Datei zählt nicht');
  Assert.AreEqual('Tests', Merged.Name);
  Assert.AreEqual('U.pas', Merged.FileName);
  Merged := TShellWorkspace.MergeRuleProjects([Member('A', TRuleApplicationKind.Gui),
    Member('B', TRuleApplicationKind.Gui)], 'U.pas');
  Assert.IsTrue(Merged.Application = TRuleApplicationKind.Gui, 'Gleiche Art bleibt');
  Assert.AreEqual('A', Merged.Name, 'Das erste Projekt liefert den Namen');
  Merged := TShellWorkspace.MergeRuleProjects([Member('Tests', TRuleApplicationKind.Console),
    Member('Plugin', TRuleApplicationKind.Package), Member('Noch', TRuleApplicationKind.Console)], 'U.pas');
  Assert.IsTrue(Merged.Application = TRuleApplicationKind.Unknown, 'Verschiedene Arten ergeben Unknown');
  Assert.AreEqual('Tests', Merged.Name);
end;

procedure TShellWorkspaceTests.WorkspaceWithoutProjectIsRuleReady;
var
  mWorkspace: TShellWorkspace;
  mReason: string;
begin
  mWorkspace := NewWorkspace('Ohne');
  try
    mWorkspace.LoopThreadId := TThread.Current.ThreadID;
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
