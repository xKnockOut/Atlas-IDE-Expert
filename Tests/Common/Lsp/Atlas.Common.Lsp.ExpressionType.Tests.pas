unit Atlas.Common.Lsp.ExpressionType.Tests;

// Befehl atlas.server.expressionType (#689): Antwort im JSON, Erweitern auf
// den umschließenden Ausdruck, Schalter aus den Argumenten, Fundort aus
// anderen Units und Fehler.

interface

uses
  DUnitX.TestFramework,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspExpressionTypeTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    function Run(ALine, AStart, AEnd: Integer; const ASettings: string): TJSONObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ReplyCarriesTypeConversionsAndLocation;
    [Test]
    procedure ExpandAndSwitches;
    [Test]
    procedure ValueAndErrors;
    [Test]
    procedure UnknownDocumentGivesError;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ExpressionType;

const
  LB = #13#10;
  MainFile = 'C:\P\Haupt.pas';
  OtherFile = 'C:\P\Preise.pas';

  UnitOther =
    'unit Preise;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TPreis = Currency;' + LB +                      // 3
    'implementation' + LB +
    'end.';

  UnitMain =
    'unit Haupt;' + LB +
    'interface' + LB +
    'implementation' + LB +
    'uses Preise;' + LB +
    'procedure Probe;' + LB +
    'const' + LB +
    '  Zwei = 2;' + LB +
    'var' + LB +
    '  Price: TPreis;' + LB +
    '  Count: Integer;' + LB +
    'begin' + LB +
    '  Price := Price * Count;' + LB +                  // 11
    '  Count := Zwei * 21;' + LB +                      // 12
    '  Count := Count + Nichts;' + LB +                 // 13
    'end;' + LB +
    'end.';

{ TLspExpressionTypeTests }

procedure TLspExpressionTypeTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitOther, OtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspExpressionTypeTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

function TLspExpressionTypeTests.Run(ALine, AStart, AEnd: Integer; const ASettings: string): TJSONObject;
var
  Uri: string;
  Arguments: TJSONArray;
  Reply: TJSONValue;
begin
  Uri := TDocumentUris.FromPath(MainFile);
  FStore.Close(Uri);
  FStore.Open(Uri, 'delphi', 1, UnitMain);
  Arguments := TJSONArray.Create;
  try
    Arguments.Add(Uri);
    Arguments.AddElement(TJSONObject.ParseJSONValue(Format(
      '{"start": {"line": %d, "character": %d}, "end": {"line": %d, "character": %d}}',
      [ALine, AStart, ALine, AEnd])));
    if ASettings <> '' then
      Arguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    Reply := TLspExpressionType.Execute(FStore, FIndex, nil, nil, Arguments);
  finally
    Arguments.Free;
  end;
  Assert.IsTrue(Reply is TJSONObject);
  Result := TJSONObject(Reply);
end;

procedure TLspExpressionTypeTests.ReplyCarriesTypeConversionsAndLocation;
var
  Reply, Location, Conversion: TJSONObject;
begin
  // Ganze rechte Seite "Price * Count" markiert.
  Reply := Run(11, 11, 24, '');
  try
    Assert.AreEqual('Price * Count', Reply.GetValue('expression').Value);
    Assert.AreEqual('Currency', Reply.GetValue('type').Value, 'TPreis rechnet als Currency');
    Assert.IsNull(Reply.GetValue('error'));
    Assert.AreEqual('11', ((Reply.GetValue('range') as TJSONObject).GetValue('start') as TJSONObject).
      GetValue('line').Value);
    Conversion := (Reply.GetValue('conversions') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('Count', Conversion.GetValue('expression').Value);
    Assert.AreEqual('Integer', Conversion.GetValue('from').Value);
    Assert.AreEqual('widen', Conversion.GetValue('kind').Value);
  finally
    Reply.Free;
  end;
  // Cursor auf Price: der Name selbst, Alias mit Grundtyp und Fundort in der anderen Unit.
  Reply := Run(11, 13, 13, '');
  try
    Assert.AreEqual('Price', Reply.GetValue('expression').Value);
    Assert.AreEqual('TPreis', Reply.GetValue('type').Value);
    Assert.AreEqual('Currency', Reply.GetValue('base').Value);
    Location := Reply.GetValue('location') as TJSONObject;
    Assert.IsNotNull(Location);
    Assert.AreEqual(OtherFile, Location.GetValue('file').Value);
    Assert.AreEqual('3', Location.GetValue('line').Value);
  finally
    Reply.Free;
  end;
end;

procedure TLspExpressionTypeTests.ExpandAndSwitches;
var
  Reply: TJSONObject;
begin
  // Von Count (Zeichen 19..24) eine Stufe hinaus.
  Reply := Run(11, 19, 24, '{"expand": true, "conversions": false}');
  try
    Assert.AreEqual('Price * Count', Reply.GetValue('expression').Value);
    Assert.AreEqual(0, (Reply.GetValue('conversions') as TJSONArray).Count);
  finally
    Reply.Free;
  end;
  Reply := Run(12, 11, 20, '{"constValue": false}');
  try
    Assert.IsNull(Reply.GetValue('value'));
  finally
    Reply.Free;
  end;
end;

procedure TLspExpressionTypeTests.ValueAndErrors;
var
  Reply, Error: TJSONObject;
begin
  Reply := Run(12, 11, 20, '');
  try
    Assert.AreEqual('Zwei * 21', Reply.GetValue('expression').Value);
    Assert.AreEqual('42', Reply.GetValue('value').Value);
  finally
    Reply.Free;
  end;
  Reply := Run(13, 11, 25, '');
  try
    Assert.AreEqual('', Reply.GetValue('type').Value);
    Error := Reply.GetValue('error') as TJSONObject;
    Assert.AreEqual('unknownName', Error.GetValue('kind').Value);
    Assert.AreEqual('Nichts', Error.GetValue('detail').Value);
  finally
    Reply.Free;
  end;
  // Auf "begin": kein Ausdruck.
  Reply := Run(10, 1, 1, '');
  try
    Assert.AreEqual('noExpression', (Reply.GetValue('error') as TJSONObject).GetValue('kind').Value);
  finally
    Reply.Free;
  end;
end;

procedure TLspExpressionTypeTests.UnknownDocumentGivesError;
var
  Arguments: TJSONArray;
begin
  Arguments := TJSONArray.Create;
  try
    Arguments.Add('file:///C:/P/Fehlt.pas');
    Arguments.AddElement(TJSONObject.ParseJSONValue('{"start": {"line": 0, "character": 0}, ' +
      '"end": {"line": 0, "character": 0}}'));
    Assert.WillRaise(
      procedure
      begin
        TLspExpressionType.Execute(FStore, FIndex, nil, nil, Arguments).Free;
      end, EJsonRpcError);
  finally
    Arguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspExpressionTypeTests);

end.
