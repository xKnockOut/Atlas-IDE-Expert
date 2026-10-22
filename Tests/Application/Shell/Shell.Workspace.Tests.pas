unit Shell.Workspace.Tests;

// Reload nur im Thread der Nachrichtenschleife (Code-Review A-03).

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

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceTests);

end.
