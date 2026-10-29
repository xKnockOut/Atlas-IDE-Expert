unit Atlas.Common.Lsp.MethodOrder.Tests;

// Befehl atlas.server.methodOrder (#660): Argumente, Antwort und Fehler.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract;

type
  [TestFixture]
  TLspMethodOrderTests = class
  private
    FStore: IDocumentStore;
    function Run(const AText, AOptions: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ArrangesWholeUnit;
    [Test]
    procedure PlacesNewBody;
    [Test]
    procedure OffGivesNothing;
    [Test]
    procedure UnknownDocumentGivesError;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.MethodOrder;

const
  MainFile = 'C:\P\Reihe.pas';
  Kopf =
    'unit Reihe;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '  end;'#10 +
    'implementation'#10;
  RumpfA = #10'procedure TFoo.A;'#10'begin'#10'end;'#10;
  RumpfB = #10'procedure TFoo.B;'#10'begin'#10'end;'#10;
  Ende = #10'end.';

procedure TLspMethodOrderTests.Setup;
begin
  FStore := TDocumentStore.Create;
end;

procedure TLspMethodOrderTests.TearDown;
begin
  FStore := nil;
end;

function TLspMethodOrderTests.Run(const AText, AOptions: string): TJSONObject;
var
  Uri: string;
  Arguments: TJSONArray;
  Reply: TJSONValue;
begin
  Uri := TDocumentUris.FromPath(MainFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, AText);
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(Uri);
    if AOptions <> '' then
      Arguments.AddElement(TJSONObject.ParseJSONValue(AOptions));
    Reply := TLspMethodOrder.Execute(FStore, Arguments);
  finally
    Arguments.Free;
  end;
  Assert.IsTrue(Reply is TJSONObject);
  Result := TJSONObject(Reply);
end;

procedure TLspMethodOrderTests.ArrangesWholeUnit;
var
  Reply: TJSONObject;
  Move: TJSONObject;
begin
  Reply := Run(Kopf + RumpfB + RumpfA + Ende, '');
  try
    Assert.AreEqual(1, (Reply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(2, (Reply.GetValue('moves') as TJSONArray).Count);
    Move := (Reply.GetValue('moves') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('TFoo', Move.GetValue<string>('type'));
    Assert.AreEqual('A', Move.GetValue<string>('name'));
    Assert.AreEqual(13, (Move.GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual(-1, (Move.GetValue('delta') as TJSONNumber).AsInt);
    Assert.IsFalse(Move.GetValue<Boolean>('fixed'));
    Assert.AreEqual('', Move.GetValue<string>('reason'));
  finally
    Reply.Free;
  end;
end;

procedure TLspMethodOrderTests.PlacesNewBody;
var
  Reply, Options: TJSONObject;
begin
  Options := TJSONObject.Create;
  try
    Options.AddPair('mode', 'declaration');
    Options.AddPair('scope', 'new');
    Options.AddPair('before', Kopf + RumpfB + Ende);
    Reply := Run(Kopf + RumpfB + RumpfA + Ende, Options.ToJSON);
  finally
    Options.Free;
  end;
  try
    Assert.AreEqual(1, (Reply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(1, (Reply.GetValue('moves') as TJSONArray).Count);
  finally
    Reply.Free;
  end;
  // Ohne Vorher-Text ist alles neu, aber kein Rumpf ein Ziel.
  Reply := Run(Kopf + RumpfB + RumpfA + Ende, '{"scope": "new", "before": ""}');
  try
    Assert.AreEqual(0, (Reply.GetValue('edits') as TJSONArray).Count, 'leerer Vorher-Text');
  finally
    Reply.Free;
  end;
end;

procedure TLspMethodOrderTests.OffGivesNothing;
var
  Reply: TJSONObject;
begin
  Reply := Run(Kopf + RumpfB + RumpfA + Ende, '{"mode": "off"}');
  try
    Assert.AreEqual(0, (Reply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(0, (Reply.GetValue('moves') as TJSONArray).Count);
  finally
    Reply.Free;
  end;
end;

procedure TLspMethodOrderTests.UnknownDocumentGivesError;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas"]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspMethodOrder.Execute(FStore, Arguments).Free;
      end,
      EJsonRpcError);
  finally
    Arguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodOrderTests);

end.
