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
  cMainFile = 'C:\P\Reihe.pas';
  cKopf =
    'unit Reihe;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure A;'#10 +
    '    procedure B;'#10 +
    '  end;'#10 +
    'implementation'#10;
  cRumpfA = #10'procedure TFoo.A;'#10'begin'#10'end;'#10;
  cRumpfB = #10'procedure TFoo.B;'#10'begin'#10'end;'#10;
  cEnde = #10'end.';

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
  mUri: string;
  mArguments: TJSONArray;
  mReply: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(cMainFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, AText);
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(mUri);
    if AOptions <> '' then
    begin
      mArguments.AddElement(TJSONObject.ParseJSONValue(AOptions));
    end;
    mReply := TLspMethodOrder.Execute(FStore, mArguments);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mReply is TJSONObject);
  Result := TJSONObject(mReply);
end;

procedure TLspMethodOrderTests.ArrangesWholeUnit;
var
  mReply: TJSONObject;
  mMove: TJSONObject;
begin
  mReply := Run(cKopf + cRumpfB + cRumpfA + cEnde, '');
  try
    Assert.AreEqual(1, (mReply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(2, (mReply.GetValue('moves') as TJSONArray).Count);
    mMove := (mReply.GetValue('moves') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('TFoo', mMove.GetValue<string>('type'));
    Assert.AreEqual('A', mMove.GetValue<string>('name'));
    Assert.AreEqual(13, (mMove.GetValue('line') as TJSONNumber).AsInt);
    Assert.AreEqual(-1, (mMove.GetValue('delta') as TJSONNumber).AsInt);
    Assert.IsFalse(mMove.GetValue<Boolean>('fixed'));
    Assert.AreEqual('', mMove.GetValue<string>('reason'));
  finally
    mReply.Free;
  end;
end;

procedure TLspMethodOrderTests.PlacesNewBody;
var
  mReply, mOptions: TJSONObject;
begin
  mOptions := TJSONObject.Create;
  try
    mOptions.AddPair('mode', 'declaration');
    mOptions.AddPair('scope', 'new');
    mOptions.AddPair('before', cKopf + cRumpfB + cEnde);
    mReply := Run(cKopf + cRumpfB + cRumpfA + cEnde, mOptions.ToJSON);
  finally
    mOptions.Free;
  end;
  try
    Assert.AreEqual(1, (mReply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(1, (mReply.GetValue('moves') as TJSONArray).Count);
  finally
    mReply.Free;
  end;
  // Ohne Vorher-Text ist alles neu: Die Rümpfe ordnen sich untereinander (#1834).
  mReply := Run(cKopf + cRumpfB + cRumpfA + cEnde, '{"scope": "new", "before": ""}');
  try
    Assert.AreEqual(1, (mReply.GetValue('edits') as TJSONArray).Count, 'leerer Vorher-Text');
  finally
    mReply.Free;
  end;
end;

procedure TLspMethodOrderTests.OffGivesNothing;
var
  mReply: TJSONObject;
begin
  mReply := Run(cKopf + cRumpfB + cRumpfA + cEnde, '{"mode": "off"}');
  try
    Assert.AreEqual(0, (mReply.GetValue('edits') as TJSONArray).Count);
    Assert.AreEqual(0, (mReply.GetValue('moves') as TJSONArray).Count);
  finally
    mReply.Free;
  end;
end;

procedure TLspMethodOrderTests.UnknownDocumentGivesError;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONObject.ParseJSONValue('["file:///C:/P/Fehlt.pas"]') as TJSONArray;
  try
    Assert.WillRaise(
      procedure
      begin
        TLspMethodOrder.Execute(FStore, mArguments).Free;
      end,
      EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodOrderTests);

end.
