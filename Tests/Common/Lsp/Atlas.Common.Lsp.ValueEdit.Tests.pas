unit Atlas.Common.Lsp.ValueEdit.Tests;

// Befehl atlas.server.valueEdit (#868): Art der Eingabe je Typ (Ganzzahl mit
// Grenzen, Gleitkomma, Boolean, Zeichen, String, Aufzählung mit Präfix, Menge,
// Farbe), Setter und nur lesbare Eigenschaften, Ausdruck nicht in der Zeile.

interface

uses
  DUnitX.TestFramework,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspValueEditTests = class
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    function Run(ALine: Integer; const AExpression: string): TJSONObject;
    function Kind(ALine: Integer; const AExpression: string): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BuiltinKinds;
    [Test]
    procedure IntegerRanges;
    [Test]
    procedure EnumSetAndColor;
    [Test]
    procedure SetterAndReadOnly;
    [Test]
    procedure ExpressionNotInLine;
    [Test]
    procedure FindExpressionAsWholeWord;
    [Test]
    procedure WriterOfDeclaration;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Text.Json,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.ValueEdit;

const
  LB = #13#10;
  MainFile = 'C:\P\Kasse.pas';

  UnitMain =
    'unit Kasse;' + LB +
    'interface' + LB +
    'type' + LB +
    '  TColor = -$7FFFFFFF-1..$7FFFFFFF;' + LB +
    '  TModus = (mdAuto, mdHand, mdAus);' + LB +
    '  {$SCOPEDENUMS ON}' + LB +
    '  TArt = (Bar, Karte);' + LB +
    '  {$SCOPEDENUMS OFF}' + LB +
    '  TModi = set of TModus;' + LB +
    '  TKasse = class' + LB +
    '  private' + LB +
    '    FBetrag: Currency;' + LB +
    '    FName: string;' + LB +
    '    procedure SetBetrag(AValue: Currency);' + LB +
    '  public' + LB +
    '    property Betrag: Currency read FBetrag write SetBetrag;' + LB +
    '    property Name: string read FName write FName;' + LB +
    '    property Laenge: Integer read GetLaenge;' + LB +
    '  end;' + LB +
    'implementation' + LB +                                       // 19
    'procedure Probe(K: TKasse);' + LB +
    'var' + LB +
    '  N: Integer; B: Byte; W: Word; U: UInt64; D: Double; F: Boolean; C: Char; S: string;' + LB +
    '  M: TModus; A: TArt; Mm: TModi; Farbe: TColor;' + LB +
    'begin' + LB +
    '  N := B + W; D := 1.5; F := not F; C := ''x''; S := S + ''y'';' + LB +   // 25
    '  M := mdHand; A := TArt.Bar; Mm := [mdAuto]; Farbe := 0; U := 1;' + LB + // 26
    '  K.Betrag := K.Betrag + 1; K.Name := ''a''; N := K.Laenge;' + LB +       // 27
    'end;' + LB +
    'end.';

{ TLspValueEditTests }

procedure TLspValueEditTests.Setup;
begin
  FStore := TDocumentStore.Create;
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitMain, MainFile, nil));
end;

procedure TLspValueEditTests.TearDown;
begin
  FStore := nil;
  FIndex := nil;
end;

function TLspValueEditTests.Run(ALine: Integer; const AExpression: string): TJSONObject;
var
  mUri: string;
  mArguments: TJSONArray;
  mReply: TJSONValue;
begin
  mUri := TDocumentUris.FromPath(MainFile);
  FStore.Close(mUri);
  FStore.Open(mUri, 'delphi', 1, UnitMain);
  mArguments := TJSONArray.Create;
  try
    mArguments.Add(mUri);
    mArguments.Add(ALine);
    mArguments.Add(AExpression);
    mReply := TLspValueEdit.Execute(FStore, FIndex, nil, nil, nil, mArguments);
  finally
    mArguments.Free;
  end;
  Assert.IsTrue(mReply is TJSONObject);
  Result := TJSONObject(mReply);
end;

function TLspValueEditTests.Kind(ALine: Integer; const AExpression: string): string;
var
  mReply: TJSONObject;
begin
  mReply := Run(ALine, AExpression);
  try
    Result := TJsonRead.Text(mReply, 'kind');
  finally
    mReply.Free;
  end;
end;

procedure TLspValueEditTests.BuiltinKinds;
begin
  Assert.AreEqual('integer', Kind(25, 'N'));
  Assert.AreEqual('float', Kind(25, 'D'));
  Assert.AreEqual('boolean', Kind(25, 'F'));
  Assert.AreEqual('char', Kind(25, 'C'));
  Assert.AreEqual('string', Kind(25, 'S'));
end;

procedure TLspValueEditTests.IntegerRanges;
var
  mReply: TJSONObject;
begin
  mReply := Run(25, 'B');
  try
    Assert.AreEqual('0', TJsonRead.Text(mReply, 'low'));
    Assert.AreEqual('255', TJsonRead.Text(mReply, 'high'));
  finally
    mReply.Free;
  end;
  mReply := Run(25, 'N');
  try
    Assert.AreEqual('-2147483648', TJsonRead.Text(mReply, 'low'));
    Assert.AreEqual('2147483647', TJsonRead.Text(mReply, 'high'));
  finally
    mReply.Free;
  end;
  mReply := Run(26, 'U');
  try
    Assert.AreEqual('18446744073709551615', TJsonRead.Text(mReply, 'high'));
  finally
    mReply.Free;
  end;
end;

procedure TLspValueEditTests.EnumSetAndColor;
var
  mReply: TJSONObject;
begin
  mReply := Run(26, 'M');
  try
    Assert.AreEqual('enum', TJsonRead.Text(mReply, 'kind'));
    Assert.AreEqual('["mdAuto","mdHand","mdAus"]', TJsonRead.Items(mReply, 'values').ToJSON);
    Assert.AreEqual('', TJsonRead.Text(mReply, 'prefix'));
  finally
    mReply.Free;
  end;
  mReply := Run(26, 'A');
  try
    Assert.AreEqual('enum', TJsonRead.Text(mReply, 'kind'));
    Assert.AreEqual('TArt.', TJsonRead.Text(mReply, 'prefix'));
  finally
    mReply.Free;
  end;
  mReply := Run(26, 'Mm');
  try
    Assert.AreEqual('set', TJsonRead.Text(mReply, 'kind'));
    Assert.AreEqual(3, TJsonRead.Items(mReply, 'values').Count);
  finally
    mReply.Free;
  end;
  Assert.AreEqual('color', Kind(26, 'Farbe'));
end;

procedure TLspValueEditTests.SetterAndReadOnly;
var
  mReply: TJSONObject;
begin
  mReply := Run(27, 'K.Betrag');
  try
    Assert.AreEqual('float', TJsonRead.Text(mReply, 'kind'));
    Assert.AreEqual('SetBetrag', TJsonRead.Text(mReply, 'setter'));
    Assert.IsFalse(TJsonRead.Flag(mReply, 'readOnly'));
  finally
    mReply.Free;
  end;
  mReply := Run(27, 'K.Name');
  try
    Assert.AreEqual('', TJsonRead.Text(mReply, 'setter'), 'write FName ist kein Aufruf');
    Assert.IsFalse(TJsonRead.Flag(mReply, 'readOnly'));
  finally
    mReply.Free;
  end;
  mReply := Run(27, 'K.Laenge');
  try
    Assert.IsTrue(TJsonRead.Flag(mReply, 'readOnly'));
  finally
    mReply.Free;
  end;
end;

procedure TLspValueEditTests.ExpressionNotInLine;
var
  mReply: TJSONObject;
begin
  mReply := Run(25, 'Gibts');
  try
    Assert.AreEqual('other', TJsonRead.Text(mReply, 'kind'));
    Assert.AreEqual('', TJsonRead.Text(mReply, 'type'));
  finally
    mReply.Free;
  end;
end;

procedure TLspValueEditTests.FindExpressionAsWholeWord;
begin
  Assert.AreEqual(8, TLspValueEdit.FindExpression('  NN := N + 1;', 'N'));
  Assert.AreEqual(-1, TLspValueEdit.FindExpression('  NN := X.N;', 'N'), 'nicht hinter einem Punkt');
  Assert.AreEqual(2, TLspValueEdit.FindExpression('  K.Betrag := 1;', 'K.Betrag'));
  Assert.AreEqual(-1, TLspValueEdit.FindExpression('abc', ''));
end;

procedure TLspValueEditTests.WriterOfDeclaration;
begin
  Assert.AreEqual('SetBetrag', TLspValueEdit.WriterOf('property Betrag: Currency read FBetrag write SetBetrag;'));
  Assert.AreEqual('', TLspValueEdit.WriterOf('property Laenge: Integer read GetLaenge;'));
end;

end.
