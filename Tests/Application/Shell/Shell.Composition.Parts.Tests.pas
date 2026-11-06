unit Shell.Composition.Parts.Tests;

// Teile der Komposition ohne Verdrahtung und nach einem abgebrochenen Aufbau: Vorgaben, Benachrichtigung an
// den Client und Freigeben.

interface

uses
  DUnitX.TestFramework,
  Shell.Composition.Parts;

type
  [TestFixture]
  TShellPartsTests = class
  private
    FParts: TShellParts;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Ohne Teilwurzeln: kein Index, Zeitlimit der Vorgabe, keine Testunits und kein uses-Kontext.</summary>
    [Test]
    procedure EmptyPartsHaveDefaults;
    /// <summary>Eine Benachrichtigung geht über den Transport hinaus.</summary>
    [Test]
    procedure NotifyClientWritesToTransport;
    /// <summary>Nach einem abgebrochenen Aufbau mit nur Protokoll und Dokumenten gibt Destroy alles frei.</summary>
    [Test]
    procedure FreesPartlyBuiltParts;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.JSON,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.Lsp.TestUnits,
  Atlas.Common.Editing.Contract,
  Shell.Composition.ProtocolWiring;


procedure TShellPartsTests.Setup;
begin
  FParts := TShellParts.Create;
  FParts.Channel.Logger := TLogger.Create;
  FParts.Channel.Transport := TJsonRpcStreamTransport.Create(TMemoryStream.Create, TMemoryStream.Create, True);
end;

procedure TShellPartsTests.TearDown;
begin
  FreeAndNil(FParts);
end;

procedure TShellPartsTests.EmptyPartsHaveDefaults;
var
  mTestContext: TTestUnitContext;
  mUsesContext: TUsesContext;
begin
  Assert.IsNull(FParts.Index);
  Assert.AreEqual(Cardinal(TShellParts.RequestTimeoutMs), FParts.CurrentRequestTimeout);
  Assert.IsFalse(FParts.TestUnitContextFor('file:///C:/Projekt/A.pas', mTestContext));
  Assert.IsFalse(FParts.UsesContextFor('file:///C:/Projekt/A.pas', mUsesContext));
end;

procedure TShellPartsTests.NotifyClientWritesToTransport;
var
  mOutput: TMemoryStream;
begin
  mOutput := TMemoryStream.Create;
  try
    FParts.Channel.Transport := TJsonRpcStreamTransport.Create(nil, mOutput, False);
    FParts.NotifyClient('atlas/test', TJSONObject.Create);
    Assert.IsTrue(mOutput.Size > 0);
  finally
    FParts.Channel.Transport := nil;
    mOutput.Free;
  end;
end;

procedure TShellPartsTests.FreesPartlyBuiltParts;
begin
  TShellProtocolWiring.Protocol(FParts);
  TShellProtocolWiring.Documents(FParts);
  Assert.WillNotRaise(
    procedure
    begin
      FreeAndNil(FParts);
    end);
end;

initialization
  TDUnitX.RegisterTestFixture(TShellPartsTests);

end.
