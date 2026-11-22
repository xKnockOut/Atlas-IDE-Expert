unit Core.Workspace.Indexing.Tests;

// Indexaufbau des Arbeitsbereichs: Ein neuer Aufbau läuft noch nicht, der Bericht der Kodierungen ohne Dateien
// meldet nichts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCoreWorkspaceIndexingTests = class
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
  Core.Workspace.Setup,
  Core.Workspace.State,
  Core.Workspace.Cache,
  Core.Workspace.Encodings,
  Core.Workspace.Indexing,
  Shell.Composition.Platform;

{ TCoreWorkspaceIndexingTests }

procedure TCoreWorkspaceIndexingTests.IndexingStartsIdle;
var
  mParts: TCoreIndexingParts;
  mIndexing: TCoreWorkspaceIndexing;
  mReport: TCoreEncodingReport;
  mIndex: ISymbolIndex;
  mLogger: ILogger;
begin
  mIndex := TSymbolIndex.Create;
  mLogger := TLogger.Create;
  mParts := Default(TCoreIndexingParts);
  mParts.Name := 'Test';
  mParts.Logger := mLogger;
  mParts.Transport := TJsonRpcStreamTransport.Create(nil, TBytesStream.Create, True);
  mParts.Index := mIndex;
  mParts.ProgressToken := 'atlas-test-index';
  mParts.Setup := TCoreWorkspaceSetup.Create;
  mParts.Setup.Factories := TShellPlatformAdapters.WorkspaceFactories;
  mParts.Events := TCoreWorkspaceEvents.Create;
  mParts.State := TCoreProjectState.Create(mParts.Setup);
  mParts.Cache := TCoreWorkspaceCache.Create('Test', mLogger, mParts.Setup, mParts.Events);
  mIndexing := nil;
  mReport := nil;
  try
    mIndexing := TCoreWorkspaceIndexing.Create(mParts);
    mReport := TCoreEncodingReport.Create('Test', TPath.GetTempPath, mLogger, nil, mIndex);
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
    mParts := Default(TCoreIndexingParts);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCoreWorkspaceIndexingTests);

end.
