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
    // Der anonyme Thread legt Verwaltungsdaten an, die erst nach dem Test freigegeben werden.
    [IgnoreMemoryLeaks]
    procedure ReloadOutsideLoopThreadRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Shell.Workspace;

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

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceTests);

end.
