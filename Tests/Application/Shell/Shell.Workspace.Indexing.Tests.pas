unit Shell.Workspace.Indexing.Tests;

// Indexaufbau des Arbeitsbereichs: Ein neuer Aufbau läuft noch nicht, der Bericht der Kodierungen ohne Dateien
// meldet nichts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TShellWorkspaceIndexingTests = class
  public
    /// <summary>Ein neuer Aufbau läuft noch nicht; Kodierungen ohne Dateien melden nichts.</summary>
    [Test]
    procedure IndexingStartsIdle;
  end;

implementation

uses
  System.Classes,
  System.IOUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Shell.Workspace.Setup,
  Shell.Workspace.State,
  Shell.Workspace.Cache,
  Shell.Workspace.Encodings,
  Shell.Workspace.Indexing;

procedure TShellWorkspaceIndexingTests.IndexingStartsIdle;
var
  mParts: TShellIndexingParts;
  mIndexing: TShellWorkspaceIndexing;
  mReport: TShellEncodingReport;
  mIndex: ISymbolIndex;
  mLogger: ILogger;
begin
  mIndex := TSymbolIndex.Create;
  mLogger := TLogger.Create;
  mParts := Default(TShellIndexingParts);
  mParts.Name := 'Test';
  mParts.Logger := mLogger;
  mParts.Transport := TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True);
  mParts.Index := mIndex;
  mParts.ProgressToken := 'atlas-test-index';
  mParts.Setup := TShellWorkspaceSetup.Create;
  mParts.Events := TShellWorkspaceEvents.Create;
  mParts.State := TShellProjectState.Create(mParts.Setup);
  mParts.Cache := TShellWorkspaceCache.Create('Test', mLogger, mParts.Setup, mParts.Events);
  mIndexing := TShellWorkspaceIndexing.Create(mParts);
  mReport := TShellEncodingReport.Create('Test', TPath.GetTempPath, mLogger, nil, mIndex);
  try
    Assert.AreEqual(-1, mIndexing.Loading, 'Kein Aufbau läuft');
    Assert.AreSame(mIndex, mIndexing.Index);
    mReport.Report(nil);
  finally
    mReport.Free;
    mIndexing.Free;
    mParts.Cache.Free;
    mParts.State.Free;
    mParts.Events.Free;
    mParts.Setup.Free;
    mParts := Default(TShellIndexingParts);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TShellWorkspaceIndexingTests);

end.
