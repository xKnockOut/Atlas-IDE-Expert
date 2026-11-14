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
  cLB = #13#10;
  cMainFile = 'C:\P\Haupt.pas';
  cOtherFile = 'C:\P\Preise.pas';

  cUnitOther =
    'unit Preise;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TPreis = Currency;' + cLB +                      // 3
    'implementation' + cLB +
    'end.';

  cUnitMain =
    'unit Haupt;' + cLB +
    'interface' + cLB +
    'implementation' + cLB +
    'uses Preise;' + cLB +
    'procedure Probe;' + cLB +
    'const' + cLB +
    '  Zwei = 2;' + cLB +
    'var' + cLB +
    '  Price: TPreis;' + cLB +
    '  Count: Integer;' + cLB +
    'begin' + cLB +
    '  Price := Price * Count;' + cLB +                  // 11
    '  Count := Zwei * 21;' + cLB +                      // 12
    '  Count := Count + Nichts;' + cLB +                 // 13
    'end;' + cLB +
    'end.';

{ TLspExpressionTypeTests }

procedure TLspExpressionTypeTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitOther, cOtherFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitMain, cMainFile, nil));
end;

procedure TLspExpressionTypeTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

function TLspExpressionTypeTests.Run(ALine, AStart, AEnd: Integer; const ASettings: string): TJSONObject;
var
  mUri: string;
  mArguments: TJSONArray;
  mReply: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(cMainFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, cUnitMain);
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(mUri);
    mArguments.AddElement(TJSONObject.ParseJSONValue(Format(
      '{"start": {"line": %d, "character": %d}, "end": {"line": %d, "character": %d}}',
      [ALine, AStart, ALine, AEnd])));
    if ASettings <> '' then
    begin
      mArguments.AddElement(TJSONObject.ParseJSONValue(ASettings));
    end;
    mReply := TLspExpressionType.Execute(FStore, FIndex, nil, nil, mArguments);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mReply is TJSONObject);
  Result := TJSONObject(mReply);
end;

procedure TLspExpressionTypeTests.ReplyCarriesTypeConversionsAndLocation;
var
  mReply, mLocation, mConversion: TJSONObject;
begin
  // Ganze rechte Seite "Price * Count" markiert.
  mReply := Run(11, 11, 24, '');
  try
    Assert.AreEqual('Price * Count', mReply.GetValue('expression').Value);
    Assert.AreEqual('Currency', mReply.GetValue('type').Value, 'TPreis rechnet als Currency');
    Assert.IsNull(mReply.GetValue('error'));
    Assert.AreEqual('11', ((mReply.GetValue('range') as TJSONObject).GetValue('start') as TJSONObject).
      GetValue('line').Value);
    mConversion := (mReply.GetValue('conversions') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('Count', mConversion.GetValue('expression').Value);
    Assert.AreEqual('Integer', mConversion.GetValue('from').Value);
    Assert.AreEqual('widen', mConversion.GetValue('kind').Value);
  finally
    mReply.Free;
  end;
  // Cursor auf Price: der Name selbst, Alias mit Grundtyp und Fundort in der anderen Unit.
  mReply := Run(11, 13, 13, '');
  try
    Assert.AreEqual('Price', mReply.GetValue('expression').Value);
    Assert.AreEqual('TPreis', mReply.GetValue('type').Value);
    Assert.AreEqual('Currency', mReply.GetValue('base').Value);
    mLocation := mReply.GetValue('location') as TJSONObject;
    Assert.IsNotNull(mLocation);
    Assert.AreEqual(cOtherFile, mLocation.GetValue('file').Value);
    Assert.AreEqual('3', mLocation.GetValue('line').Value);
  finally
    mReply.Free;
  end;
end;

procedure TLspExpressionTypeTests.ExpandAndSwitches;
var
  mReply: TJSONObject;
begin
  // Von Count (Zeichen 19..24) eine Stufe hinaus.
  mReply := Run(11, 19, 24, '{"expand": true, "conversions": false}');
  try
    Assert.AreEqual('Price * Count', mReply.GetValue('expression').Value);
    Assert.AreEqual(0, (mReply.GetValue('conversions') as TJSONArray).Count);
  finally
    mReply.Free;
  end;
  mReply := Run(12, 11, 20, '{"constValue": false}');
  try
    Assert.IsNull(mReply.GetValue('value'));
  finally
    mReply.Free;
  end;
end;

procedure TLspExpressionTypeTests.ValueAndErrors;
var
  mReply, mError: TJSONObject;
begin
  mReply := Run(12, 11, 20, '');
  try
    Assert.AreEqual('Zwei * 21', mReply.GetValue('expression').Value);
    Assert.AreEqual('42', mReply.GetValue('value').Value);
  finally
    mReply.Free;
  end;
  mReply := Run(13, 11, 25, '');
  try
    Assert.AreEqual('', mReply.GetValue('type').Value);
    mError := mReply.GetValue('error') as TJSONObject;
    Assert.AreEqual('unknownName', mError.GetValue('kind').Value);
    Assert.AreEqual('Nichts', mError.GetValue('detail').Value);
  finally
    mReply.Free;
  end;
  // Auf "begin": kein Ausdruck.
  mReply := Run(10, 1, 1, '');
  try
    Assert.AreEqual('noExpression', (mReply.GetValue('error') as TJSONObject).GetValue('kind').Value);
  finally
    mReply.Free;
  end;
end;

procedure TLspExpressionTypeTests.UnknownDocumentGivesError;
var
  mArguments: TJSONArray;
begin
  mArguments := TJSONArray.Create;
  try
    mArguments.Add('file:///C:/P/Fehlt.pas');
    mArguments.AddElement(TJSONObject.ParseJSONValue('{"start": {"line": 0, "character": 0}, ' +
      '"end": {"line": 0, "character": 0}}'));
    Assert.WillRaise(
      procedure
      begin
        TLspExpressionType.Execute(FStore, FIndex, nil, nil, mArguments).Free;
      end, EJsonRpcError);
  finally
    mArguments.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspExpressionTypeTests);

end.
