unit Atlas.Common.Lsp.DocumentSymbols.Tests;

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDocumentSymbolsTests = class
  public
    [Test]
    procedure BuildsUnitOutline;
    [Test]
    procedure ListsClassMembers;
    [Test]
    procedure ListsEnumMembersAndRecordFields;
    [Test]
    procedure ListsImplementationRoutinesWithLocals;
    [Test]
    procedure SelectionRangePointsAtName;
    [Test]
    procedure ProgramDeclarationsUnderRoot;
    [Test]
    procedure BrokenCodeStillHasOutline;
    [Test]
    procedure HandlesRequestThroughDispatcher;
    [Test]
    procedure ReturnsNullForUnknownDocument;
    [Test]
    procedure MarksVisibilityAndMethodFlags;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols;

const
  UnitCode =
    'unit U;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TColor = (Red, Green);'#13#10 +
    '  TPoint = record X, Y: Integer; end;'#13#10 +
    '  TFoo = class'#13#10 +
    '  private'#13#10 +
    '    FValue: Integer;'#13#10 +
    '  public'#13#10 +
    '    constructor Create;'#13#10 +
    '    class function Make: TFoo;'#13#10 +
    '    property Value: Integer read FValue;'#13#10 +
    '  end;'#13#10 +
    '  IBar = interface procedure Run; end;'#13#10 +
    'const Limit = 10;'#13#10 +
    'var Global: Integer;'#13#10 +
    'procedure Run;'#13#10 +
    'implementation'#13#10 +
    'constructor TFoo.Create;'#13#10 +
    'begin end;'#13#10 +
    'class function TFoo.Make: TFoo;'#13#10 +
    '  procedure Helper; begin end;'#13#10 +
    'begin end;'#13#10 +
    'procedure Run; begin end;'#13#10 +
    'end.';

// Gliederung als Text, z. B. "U(interface(TFoo(...)))"; Kinder in Klammern.
function Outline(const ASymbols: TJSONArray): string;
var
  Index: Integer;
  Symbol: TJSONObject;
  Children: TJSONArray;
begin
  Result := '';
  for Index := 0 to ASymbols.Count - 1 do
  begin
    Symbol := ASymbols.Items[Index] as TJSONObject;
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Symbol.GetValue<string>('name') + ':' + IntToStr(Symbol.GetValue<Integer>('kind'));
    Children := Symbol.GetValue('children') as TJSONArray;
    if Children <> nil then
      Result := Result + '(' + Outline(Children) + ')';
  end;
end;

// Symbol über Namenspfad, z. B. ['U', 'interface', 'TFoo'].
function FindSymbol(const ASymbols: TJSONArray; const APath: array of string): TJSONObject;
var
  Current: TJSONArray;
  Name: string;
  Index: Integer;
begin
  Result := nil;
  Current := ASymbols;
  for Name in APath do
  begin
    if Current = nil then
      Exit(nil);
    Result := nil;
    for Index := 0 to Current.Count - 1 do
      if (Current.Items[Index] as TJSONObject).GetValue<string>('name') = Name then
        Result := Current.Items[Index] as TJSONObject;
    if Result = nil then
      Exit;
    Current := Result.GetValue('children') as TJSONArray;
  end;
end;

function SymbolsOf(const AText: string): TJSONArray;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspDocumentSymbols.BuildSymbols(Tree);
  finally
    Tree.Free;
  end;
end;

{ TLspDocumentSymbolsTests }

procedure TLspDocumentSymbolsTests.BuildsUnitOutline;
var
  Symbols: TJSONArray;
begin
  Symbols := SymbolsOf(UnitCode);
  try
    Assert.AreEqual(1, Integer(Symbols.Count));
    Assert.AreEqual(
      'U:2(interface:3(TColor:10(Red:22,Green:22),TPoint:23(X:8,Y:8),' +
      'TFoo:5(FValue:8,Create:9,Make:6,Value:7),IBar:11(Run:6),Limit:14,Global:13,Run:12),' +
      'implementation:3(TFoo.Create:9,TFoo.Make:6(Helper:12),Run:12))',
      Outline(Symbols));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsClassMembers;
var
  Symbols: TJSONArray;
  Foo: TJSONObject;
begin
  Symbols := SymbolsOf(UnitCode);
  try
    Foo := FindSymbol(Symbols, ['U', 'interface', 'TFoo']);
    Assert.IsNotNull(Foo);
    Assert.AreEqual('class', Foo.GetValue<string>('detail'));
    Assert.AreEqual(TLspSymbolKind.Constructor_, FindSymbol(Symbols, ['U', 'interface', 'TFoo', 'Create']).GetValue<Integer>('kind'));
    Assert.AreEqual(TLspSymbolKind.Property_, FindSymbol(Symbols, ['U', 'interface', 'TFoo', 'Value']).GetValue<Integer>('kind'));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsEnumMembersAndRecordFields;
var
  Symbols: TJSONArray;
begin
  Symbols := SymbolsOf(UnitCode);
  try
    Assert.IsNotNull(FindSymbol(Symbols, ['U', 'interface', 'TColor', 'Green']));
    Assert.AreEqual('record', FindSymbol(Symbols, ['U', 'interface', 'TPoint']).GetValue<string>('detail'));
    Assert.IsNotNull(FindSymbol(Symbols, ['U', 'interface', 'TPoint', 'Y']));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsImplementationRoutinesWithLocals;
var
  Symbols: TJSONArray;
begin
  Symbols := SymbolsOf(UnitCode);
  try
    Assert.IsNotNull(FindSymbol(Symbols, ['U', 'implementation', 'TFoo.Make', 'Helper']));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.SelectionRangePointsAtName;
var
  Symbols: TJSONArray;
  Make: TJSONObject;
begin
  Symbols := SymbolsOf(UnitCode);
  try
    // Zeile 20: "class function TFoo.Make: TFoo;" – Auswahl auf "Make".
    Make := FindSymbol(Symbols, ['U', 'implementation', 'TFoo.Make']);
    Assert.AreEqual(20, Make.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(0, Make.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(20, Make.GetValue<Integer>('selectionRange.start.line'));
    Assert.AreEqual(20, Make.GetValue<Integer>('selectionRange.start.character'));
    Assert.AreEqual(24, Make.GetValue<Integer>('selectionRange.end.character'));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ProgramDeclarationsUnderRoot;
var
  Symbols: TJSONArray;
begin
  Symbols := SymbolsOf('program P;'#13#10'const A = 1;'#13#10'procedure X; begin end;'#13#10'begin end.');
  try
    Assert.AreEqual('P:2(A:14,X:12)', Outline(Symbols));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.BrokenCodeStillHasOutline;
var
  Symbols: TJSONArray;
begin
  Symbols := SymbolsOf('unit U;'#13#10'interface'#13#10'type'#13#10'  T = class'#13#10'    procedure A(;'#13#10 +
    'implementation'#13#10'procedure B;'#13#10'begin'#13#10'  X := ;'#13#10'end;'#13#10'end.');
  try
    Assert.IsNotNull(FindSymbol(Symbols, ['U', 'interface', 'T', 'A']));
    Assert.IsNotNull(FindSymbol(Symbols, ['U', 'implementation', 'B']));
  finally
    Symbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.HandlesRequestThroughDispatcher;
var
  Store: IDocumentStore;
  Feature: TLspDocumentSymbols;
  Dispatcher: TJsonRpcDispatcher;
  Request: TJSONObject;
  Response: TJSONObject;
begin
  Store := TDocumentStore.Create;
  Store.Open('file:///u.pas', 'objectpascal', 1, UnitCode);
  Dispatcher := TJsonRpcDispatcher.Create;
  Feature := TLspDocumentSymbols.Create(Store);
  try
    Feature.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol",' +
      '"params":{"textDocument":{"uri":"file:///u.pas"}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Assert.IsNotNull(Response);
        Assert.AreEqual('U', Response.GetValue<string>('result[0].name'));
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  finally
    Feature.Free;
    Dispatcher.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ReturnsNullForUnknownDocument;
var
  Store: IDocumentStore;
  Feature: TLspDocumentSymbols;
  Dispatcher: TJsonRpcDispatcher;
  Request: TJSONObject;
  Response: TJSONObject;
begin
  Store := TDocumentStore.Create;
  Dispatcher := TJsonRpcDispatcher.Create;
  Feature := TLspDocumentSymbols.Create(Store);
  try
    Feature.Attach(Dispatcher);
    Request := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol",' +
      '"params":{"textDocument":{"uri":"file:///fehlt.pas"}}}') as TJSONObject;
    try
      Response := Dispatcher.DispatchMessage(Request);
      try
        Assert.IsTrue(Response.GetValue('result') is TJSONNull);
      finally
        Response.Free;
      end;
    finally
      Request.Free;
    end;
  finally
    Feature.Free;
    Dispatcher.Free;
  end;
end;

const
  FormCode =
    'unit F;'#13#10 +
    'interface'#13#10 +
    'type'#13#10 +
    '  TForm1 = class(TForm)'#13#10 +
    '    Button1: TButton;'#13#10 +
    '    procedure Button1Click(Sender: TObject);'#13#10 +
    '  private'#13#10 +
    '    FCount: Integer;'#13#10 +
    '    procedure Missing;'#13#10 +
    '  strict protected'#13#10 +
    '    procedure Paint; override;'#13#10 +
    '    procedure Draw; virtual; abstract;'#13#10 +
    '  public'#13#10 +
    '    class function Make: TForm1;'#13#10 +
    '    class property Count: Integer read FCount;'#13#10 +
    '  end;'#13#10 +
    '  TPlain = class'#13#10 +
    '    X: Integer;'#13#10 +
    '  end;'#13#10 +
    'implementation'#13#10 +
    'procedure TForm1.Button1Click(Sender: TObject); begin end;'#13#10 +
    'procedure TForm1.Paint; begin end;'#13#10 +
    'class function TForm1.Make: TForm1; begin Result := nil; end;'#13#10 +
    'end.';

function Extra(const ASymbols: TJSONArray; const APath: array of string; const AKey: string): string;
var
  Symbol, Extras: TJSONObject;
  Value: TJSONValue;
begin
  Result := '';
  Symbol := FindSymbol(ASymbols, APath);
  Assert.IsNotNull(Symbol, APath[High(APath)]);
  Extras := Symbol.GetValue('atlas') as TJSONObject;
  if Extras = nil then
    Exit;
  Value := Extras.GetValue(AKey);
  if Value <> nil then
    Result := Value.Value;
end;

procedure TLspDocumentSymbolsTests.MarksVisibilityAndMethodFlags;
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(FormCode);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, FormCode);
  finally
    Tree.Free;
  end;
  try
    // Ohne Angabe bei Klassen mit Vorfahr: published (Formularfelder und Ereignis-Handler).
    Assert.AreEqual('published', Extra(Symbols, ['F', 'interface', 'TForm1', 'Button1'], 'visibility'));
    Assert.AreEqual('published', Extra(Symbols, ['F', 'interface', 'TForm1', 'Button1Click'], 'visibility'));
    Assert.AreEqual('private', Extra(Symbols, ['F', 'interface', 'TForm1', 'FCount'], 'visibility'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Missing'], 'unimplemented'));
    Assert.AreEqual('', Extra(Symbols, ['F', 'interface', 'TForm1', 'Paint'], 'unimplemented'));
    Assert.AreEqual('strict protected', Extra(Symbols, ['F', 'interface', 'TForm1', 'Paint'], 'visibility'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Paint'], 'override'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Draw'], 'virtual'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Draw'], 'abstract'));
    // Abstrakte Methoden brauchen keinen Rumpf.
    Assert.AreEqual('', Extra(Symbols, ['F', 'interface', 'TForm1', 'Draw'], 'unimplemented'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Make'], 'classMember'));
    Assert.AreEqual('public', Extra(Symbols, ['F', 'interface', 'TForm1', 'Make'], 'visibility'));
    Assert.AreEqual('true', Extra(Symbols, ['F', 'interface', 'TForm1', 'Count'], 'classMember'));
    Assert.AreEqual('', Extra(Symbols, ['F', 'interface', 'TForm1', 'Button1Click'], 'classMember'));
    // Ohne Vorfahr: public.
    Assert.AreEqual('public', Extra(Symbols, ['F', 'interface', 'TPlain', 'X'], 'visibility'));
    // Rümpfe im implementation-Abschnitt tragen nichts.
    Assert.IsNull(FindSymbol(Symbols, ['F', 'implementation', 'TForm1.Paint']).GetValue('atlas'));
  finally
    Symbols.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentSymbolsTests);

end.
