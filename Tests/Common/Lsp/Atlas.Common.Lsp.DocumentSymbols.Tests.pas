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
    [Test]
    procedure ActiveBranchesWithCondition;
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
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.DocumentSymbols;

const
  cUnitCode =
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
  mIndex: Integer;
  mSymbol: TJSONObject;
  mChildren: TJSONArray;
begin
  Result := '';
  for mIndex := 0 to ASymbols.Count - 1 do
  begin
    mSymbol := ASymbols.Items[mIndex] as TJSONObject;
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mSymbol.GetValue<string>('name') + ':' + IntToStr(mSymbol.GetValue<Integer>('kind'));
    mChildren := mSymbol.GetValue('children') as TJSONArray;
    if mChildren <> nil then
    begin
      Result := Result + '(' + Outline(mChildren) + ')';
    end;
  end;
end;

// Symbol über Namenspfad, z. B. ['U', 'interface', 'TFoo'].
function FindSymbol(const ASymbols: TJSONArray; const APath: array of string): TJSONObject;
var
  mCurrent: TJSONArray;
  mName: string;
  mIndex: Integer;
begin
  Result := nil;
  mCurrent := ASymbols;
  for mName in APath do
  begin
    if mCurrent = nil then
    begin
      Exit(nil);
    end;
    Result := nil;
    for mIndex := 0 to mCurrent.Count - 1 do
    begin
      if (mCurrent.Items[mIndex] as TJSONObject).GetValue<string>('name') = mName then
      begin
        Result := mCurrent.Items[mIndex] as TJSONObject;
      end;
    end;
    if Result = nil then
    begin
      Exit;
    end;
    mCurrent := Result.GetValue('children') as TJSONArray;
  end;
end;

function SymbolsOf(const AText: string): TJSONArray;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Result := TLspDocumentSymbols.BuildSymbols(mTree);
  finally
    mTree.Free;
  end;
end;

{ TLspDocumentSymbolsTests }

procedure TLspDocumentSymbolsTests.BuildsUnitOutline;
var
  mSymbols: TJSONArray;
begin
  mSymbols := SymbolsOf(cUnitCode);
  try
    Assert.AreEqual(1, Integer(mSymbols.Count));
    Assert.AreEqual(
      'U:2(interface:3(TColor:10(Red:22,Green:22),TPoint:23(X:8,Y:8),' +
      'TFoo:5(FValue:8,Create:9,Make:6,Value:7),IBar:11(Run:6),Limit:14,Global:13,Run:12),' +
      'implementation:3(TFoo.Create:9,TFoo.Make:6(Helper:12),Run:12))',
      Outline(mSymbols));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsClassMembers;
var
  mSymbols: TJSONArray;
  mFoo: TJSONObject;
begin
  mSymbols := SymbolsOf(cUnitCode);
  try
    mFoo := FindSymbol(mSymbols, ['U', 'interface', 'TFoo']);
    Assert.IsNotNull(mFoo);
    Assert.AreEqual('class', mFoo.GetValue<string>('detail'));
    Assert.AreEqual(TLspSymbolKind.cConstructor_, FindSymbol(mSymbols, ['U', 'interface', 'TFoo', 'Create']).GetValue<Integer>('kind'));
    Assert.AreEqual(TLspSymbolKind.cProperty_, FindSymbol(mSymbols, ['U', 'interface', 'TFoo', 'Value']).GetValue<Integer>('kind'));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsEnumMembersAndRecordFields;
var
  mSymbols: TJSONArray;
begin
  mSymbols := SymbolsOf(cUnitCode);
  try
    Assert.IsNotNull(FindSymbol(mSymbols, ['U', 'interface', 'TColor', 'Green']));
    Assert.AreEqual('record', FindSymbol(mSymbols, ['U', 'interface', 'TPoint']).GetValue<string>('detail'));
    Assert.IsNotNull(FindSymbol(mSymbols, ['U', 'interface', 'TPoint', 'Y']));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ListsImplementationRoutinesWithLocals;
var
  mSymbols: TJSONArray;
begin
  mSymbols := SymbolsOf(cUnitCode);
  try
    Assert.IsNotNull(FindSymbol(mSymbols, ['U', 'implementation', 'TFoo.Make', 'Helper']));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.SelectionRangePointsAtName;
var
  mSymbols: TJSONArray;
  mMake: TJSONObject;
begin
  mSymbols := SymbolsOf(cUnitCode);
  try
    // Zeile 20: "class function TFoo.Make: TFoo;" – Auswahl auf "Make".
    mMake := FindSymbol(mSymbols, ['U', 'implementation', 'TFoo.Make']);
    Assert.AreEqual(20, mMake.GetValue<Integer>('range.start.line'));
    Assert.AreEqual(0, mMake.GetValue<Integer>('range.start.character'));
    Assert.AreEqual(20, mMake.GetValue<Integer>('selectionRange.start.line'));
    Assert.AreEqual(20, mMake.GetValue<Integer>('selectionRange.start.character'));
    Assert.AreEqual(24, mMake.GetValue<Integer>('selectionRange.end.character'));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ProgramDeclarationsUnderRoot;
var
  mSymbols: TJSONArray;
begin
  mSymbols := SymbolsOf('program P;'#13#10'const A = 1;'#13#10'procedure X; begin end;'#13#10'begin end.');
  try
    Assert.AreEqual('P:2(A:14,X:12)', Outline(mSymbols));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.BrokenCodeStillHasOutline;
var
  mSymbols: TJSONArray;
begin
  mSymbols := SymbolsOf('unit U;'#13#10'interface'#13#10'type'#13#10'  T = class'#13#10'    procedure A(;'#13#10 +
    'implementation'#13#10'procedure B;'#13#10'begin'#13#10'  X := ;'#13#10'end;'#13#10'end.');
  try
    Assert.IsNotNull(FindSymbol(mSymbols, ['U', 'interface', 'T', 'A']));
    Assert.IsNotNull(FindSymbol(mSymbols, ['U', 'implementation', 'B']));
  finally
    mSymbols.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.HandlesRequestThroughDispatcher;
var
  mStore: IDocumentStore;
  mFeature: TLspDocumentSymbols;
  mDispatcher: TJsonRpcDispatcher;
  mRequest: TJSONObject;
  mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mStore.Open('file:///u.pas', 'objectpascal', 1, cUnitCode);
  mDispatcher := TJsonRpcDispatcher.Create;
  mFeature := TLspDocumentSymbols.Create(mStore);
  try
    mFeature.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol",' +
      '"params":{"textDocument":{"uri":"file:///u.pas"}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        Assert.IsNotNull(mResponse);
        Assert.AreEqual('U', mResponse.GetValue<string>('result[0].name'));
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  finally
    mFeature.Free;
    mDispatcher.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ActiveBranchesWithCondition;
const
  cCode =
    'unit U;'#10'interface'#10'type'#10'  TLog = class'#10'  {$IFDEF MSWINDOWS}'#10'    FHandle: THandle;'#10 +
    '    FFile: Integer;'#10'  {$ENDIF}'#10'  {$IFDEF DEBUG}'#10'    FTrace: Integer;'#10'  {$ENDIF}'#10 +
    '  end;'#10'function Foo: Integer;'#10'procedure Bar;'#10'implementation'#10'function Foo: Integer;'#10 +
    '{$IFDEF MSWINDOWS}'#10'begin'#10'  Result := 1;'#10'end;'#10'{$ELSE}'#10'begin'#10'  Result := 2;'#10 +
    'end;'#10'{$ENDIF}'#10'procedure Bar;'#10'begin'#10'end;'#10'end.';
var
  mStore: IDocumentStore;
  mFeature: TLspDocumentSymbols;
  mDispatcher: TJsonRpcDispatcher;
  mRequest: TJSONObject;
  mResponse: TJSONObject;
  mSymbols: TJSONArray;

  function ConditionAt(const APath: array of string): string;
  var
    mSymbol: TJSONObject;
  begin
    mSymbol := FindSymbol(mSymbols, APath);
    Assert.IsNotNull(mSymbol);
    Result := mSymbol.GetValue<string>('atlas.condition', '');
  end;

begin
  // #845: Ohne Projekt gelten die Vordefinitionen (Win32, MSWINDOWS); DEBUG ist nicht gesetzt.
  mStore := TDocumentStore.Create;
  mStore.Open('file:///u.pas', 'objectpascal', 1, cCode);
  mDispatcher := TJsonRpcDispatcher.Create;
  mFeature := TLspDocumentSymbols.Create(mStore);
  try
    mFeature.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol",' +
      '"params":{"textDocument":{"uri":"file:///u.pas"}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        mSymbols := mResponse.GetValue('result') as TJSONArray;
        // Bar steht im Baum, FTrace (DEBUG) nicht.
        Assert.AreEqual('U:2(interface:3(TLog:5(FHandle:8,FFile:8),Foo:12,Bar:12),' +
          'implementation:3(Foo:12,Bar:12))', Outline(mSymbols));
        // Nur das erste Symbol im Zweig trägt die Bedingung, die Klasse nicht.
        Assert.AreEqual('MSWINDOWS', ConditionAt(['U', 'interface', 'TLog', 'FHandle']));
        Assert.AreEqual('', ConditionAt(['U', 'interface', 'TLog']));
        // Der Rumpf von Foo steht im Zweig, die Routine davor.
        Assert.AreEqual('MSWINDOWS', ConditionAt(['U', 'implementation', 'Foo']));
        Assert.AreEqual('', ConditionAt(['U', 'implementation', 'Bar']));
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  finally
    mFeature.Free;
    mDispatcher.Free;
  end;
end;

procedure TLspDocumentSymbolsTests.ReturnsNullForUnknownDocument;
var
  mStore: IDocumentStore;
  mFeature: TLspDocumentSymbols;
  mDispatcher: TJsonRpcDispatcher;
  mRequest: TJSONObject;
  mResponse: TJSONObject;
begin
  mStore := TDocumentStore.Create;
  mDispatcher := TJsonRpcDispatcher.Create;
  mFeature := TLspDocumentSymbols.Create(mStore);
  try
    mFeature.Attach(mDispatcher);
    mRequest := TJSONObject.ParseJSONValue(
      '{"jsonrpc":"2.0","id":1,"method":"textDocument/documentSymbol",' +
      '"params":{"textDocument":{"uri":"file:///fehlt.pas"}}}') as TJSONObject;
    try
      mResponse := mDispatcher.DispatchMessage(mRequest);
      try
        Assert.IsTrue(mResponse.GetValue('result') is TJSONNull);
      finally
        mResponse.Free;
      end;
    finally
      mRequest.Free;
    end;
  finally
    mFeature.Free;
    mDispatcher.Free;
  end;
end;

const
  cFormCode =
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
  mSymbol, mExtras: TJSONObject;
  mValue: TJSONValue;
begin
  Result := '';
  mSymbol := FindSymbol(ASymbols, APath);
  Assert.IsNotNull(mSymbol, APath[High(APath)]);
  mExtras := mSymbol.GetValue('atlas') as TJSONObject;
  if mExtras = nil then
  begin
    Exit;
  end;
  mValue := mExtras.GetValue(AKey);
  if mValue <> nil then
  begin
    Result := mValue.Value;
  end;
end;

procedure TLspDocumentSymbolsTests.MarksVisibilityAndMethodFlags;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cFormCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cFormCode);
  finally
    mTree.Free;
  end;
  try
    // Ohne Angabe bei Klassen mit Vorfahr: published (Formularfelder und Ereignis-Handler).
    Assert.AreEqual('published', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Button1'], 'visibility'));
    Assert.AreEqual('published', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Button1Click'], 'visibility'));
    Assert.AreEqual('private', Extra(mSymbols, ['F', 'interface', 'TForm1', 'FCount'], 'visibility'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Missing'], 'unimplemented'));
    Assert.AreEqual('', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Paint'], 'unimplemented'));
    Assert.AreEqual('strict protected', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Paint'], 'visibility'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Paint'], 'override'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Draw'], 'virtual'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Draw'], 'abstract'));
    // Abstrakte Methoden brauchen keinen Rumpf.
    Assert.AreEqual('', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Draw'], 'unimplemented'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Make'], 'classMember'));
    Assert.AreEqual('public', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Make'], 'visibility'));
    Assert.AreEqual('true', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Count'], 'classMember'));
    Assert.AreEqual('', Extra(mSymbols, ['F', 'interface', 'TForm1', 'Button1Click'], 'classMember'));
    // Ohne Vorfahr: public.
    Assert.AreEqual('public', Extra(mSymbols, ['F', 'interface', 'TPlain', 'X'], 'visibility'));
    // Rümpfe im implementation-Abschnitt tragen nichts.
    Assert.IsNull(FindSymbol(mSymbols, ['F', 'implementation', 'TForm1.Paint']).GetValue('atlas'));
  finally
    mSymbols.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentSymbolsTests);

end.
