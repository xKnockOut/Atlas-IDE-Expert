unit Shell.Composition.FeatureWiring.Tests;

// Verdrahtung der Features auf allen Teilen: Teilwurzeln bestehen und hängen am Verteiler.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellFeatureWiringTests = class
  private
    FParts: TShellParts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Bearbeiten, Code, Analyse und IDE bestehen.</summary>
    [Test]
    procedure CreatesFeatureAreas;
    /// <summary>Die Teilwurzel Code meldet textDocument/hover am Verteiler an.</summary>
    [Test]
    procedure HoverReachesDispatcher;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  System.StrUtils,
  Shell.Composition.ProtocolWiring,
  Shell.Composition.FeatureWiring,
  Shell.Composition.CoreWiring,
  Shell.Composition.CommandWiring;

function NewParts: TShellParts;
begin
  Result := TShellParts.Create;
  Result.Channel.Logger := TLogger.Create;
  Result.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

/// <summary>Alle Teile in der Reihenfolge von TServerComposition.Create.</summary>
procedure WireAll(AParts: TShellParts);
begin
  TShellProtocolWiring.Protocol(AParts);
  TShellProtocolWiring.Documents(AParts);
  TShellFeatureWiring.Editing(AParts);
  TShellCoreWiring.Workspaces(AParts);
  TShellCoreWiring.Index(AParts);
  TShellFeatureWiring.Code(AParts);
  TShellFeatureWiring.Analysis(AParts);
  TShellCommandWiring.Commands(AParts);
  TShellFeatureWiring.Ide(AParts);
end;

procedure TShellFeatureWiringTests.Setup;
begin
  FParts := NewParts;
  WireAll(FParts);
end;

procedure TShellFeatureWiringTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellFeatureWiringTests.CreatesFeatureAreas;
begin
  Assert.IsNotNull(FParts.EditingArea);
  Assert.IsNotNull(FParts.CodeArea);
  Assert.IsNotNull(FParts.AnalysisArea);
  Assert.IsNotNull(FParts.IdeArea);
end;

procedure TShellFeatureWiringTests.HoverReachesDispatcher;
begin
  Assert.IsTrue(IndexStr('textDocument/hover', FParts.Protocol.Dispatcher.Methods) >= 0);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellFeatureWiringTests);

end.
