unit Shell.Composition.CoreWiring.Tests;

// Verdrahtung von Kern, Index und Sitzung nach Protokoll, Dokumenten und Bearbeiten: Teile bestehen, der Index
// ist gemeinsam.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellCoreWiringTests = class
  private
    FParts: TShellParts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Kern, Teilwurzel Index und Sitzung bestehen.</summary>
    [Test]
    procedure CreatesCoreIndexAndSession;
    /// <summary>Die Teile liefern den Index der Teilwurzel Index.</summary>
    [Test]
    procedure IndexIsShared;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Shell.Composition.ProtocolWiring,
  Shell.Composition.FeatureWiring,
  Shell.Composition.CoreWiring;

function NewParts: TShellParts;
begin
  Result := TShellParts.Create;
  Result.Channel.Logger := TLogger.Create;
  Result.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

procedure TShellCoreWiringTests.Setup;
begin
  FParts := NewParts;
  TShellProtocolWiring.Protocol(FParts);
  TShellProtocolWiring.Documents(FParts);
  TShellFeatureWiring.Editing(FParts);
  TShellCoreWiring.Workspaces(FParts);
  TShellCoreWiring.Index(FParts);
end;

procedure TShellCoreWiringTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellCoreWiringTests.CreatesCoreIndexAndSession;
begin
  Assert.IsNotNull(FParts.Core);
  Assert.IsNotNull(FParts.IndexArea);
  Assert.IsNotNull(FParts.Session);
end;

procedure TShellCoreWiringTests.IndexIsShared;
begin
  Assert.IsTrue(FParts.Index <> nil);
  Assert.IsTrue(FParts.Index = FParts.IndexArea.Index);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellCoreWiringTests);

end.
