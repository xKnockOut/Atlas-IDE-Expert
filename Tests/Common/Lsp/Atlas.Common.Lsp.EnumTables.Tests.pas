unit Atlas.Common.Lsp.EnumTables.Tests;

// Aufzählung mit Namenstabelle über das Protokoll (#667): Aktionen auf dem
// Typ mit Client-Befehlen, Korrektur an einer Tabelle über die
// Namensauflösung, Antwort beim Anlegen und beim Nachziehen über mehrere
// Units samt case-Anweisung; ein gleichnamiger Typ einer anderen Unit bleibt.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TLspEnumTablesTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ActionsOnType;
    [Test]
    procedure RepairActionOnTable;
    [Test]
    procedure ExecuteCreatesTable;
    [Test]
    procedure SyncChangesTablesAndCases;
    [Test]
    procedure ErrorsCarryReason;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.EnumTables;

const
  OrdersFile = 'C:\P\Orders.pas';
  ShopFile = 'C:\P\Shop.pas';
  OtherFile = 'C:\P\Other.pas';
  Orders =
    'unit Orders;'#10 +                                                   // 0
    'interface'#10 +                                                      // 1
    'type'#10 +                                                           // 2
    '  TOrderState = (osNew, osPaid, osPaymentDue);'#10 +                 // 3
    'const'#10 +                                                          // 4
    '  CCodes: array[TOrderState] of Integer = (1, 3);'#10 +              // 5
    'implementation'#10 +                                                 // 6
    'end.'#10;

  Shop =
    'unit Shop;'#10 +
    'interface'#10 +
    'uses Orders;'#10 +
    'const'#10 +
    '  CTexts: array[TOrderState] of string = (''New'', ''Payment due'');'#10 +
    'implementation'#10 +
    'procedure Show(S: TOrderState);'#10 +
    'begin'#10 +
    '  case S of'#10 +
    '    osNew: ;'#10 +
    '    osPaymentDue: ;'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.'#10;

  // Eigenes TOrderState: bleibt unberührt.
  Other =
    'unit Other;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TOrderState = (osA, osB);'#10 +
    'const'#10 +
    '  CTexts: array[TOrderState] of string = (''A'');'#10 +
    'implementation'#10 +
    'end.'#10;

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, OrdersFile) then
    AText := Orders
  else if SameText(AFileName, ShopFile) then
    AText := Shop
  else if SameText(AFileName, OtherFile) then
    AText := Other
  else
    Result := False;
end;

procedure TLspEnumTablesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(Orders, OrdersFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Shop, ShopFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(Other, OtherFile, nil));
end;

procedure TLspEnumTablesTests.TearDown;
begin
  FIndex := nil;
end;

function Context(const AIndex: ISymbolIndex): TEnumTablesContext;
begin
  Result := Default(TEnumTablesContext);
  Result.Index := AIndex;
  Result.Files := [OrdersFile, ShopFile, OtherFile];
  Result.ReadText := ReadFile;
end;

function ActionsAt(const AIndex: ISymbolIndex; const AText, AFileName: string; ALine,
  ACharacter: Integer): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
begin
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(AIndex);
  try
    Resolver.PinTree(Tree, AFileName);
    try
      Result := TLspEnumTables.Actions(Resolver, AIndex, Tree, AText, TDocumentUris.FromPath(AFileName),
        TTextPosition.Create(ALine, ACharacter));
    finally
      Resolver.UnpinTree;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  Action: TJSONObject;
begin
  for Action in AActions do
    Action.Free;
end;

procedure TLspEnumTablesTests.ActionsOnType;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsAt(FIndex, Orders, OrdersFile, 3, 5);
  try
    Assert.AreEqual(3, Integer(Length(Actions)));
    Assert.AreEqual('Namenstabelle anlegen (TOrderState)', Actions[0].GetValue<string>('title'));
    Assert.AreEqual('Namenstabelle anlegen, im implementation-Teil (TOrderState)',
      Actions[1].GetValue<string>('title'));
    Assert.AreEqual('Tabellen von TOrderState nachziehen', Actions[2].GetValue<string>('title'));
    Assert.AreEqual(TLspEnumTables.ClientCommand, Actions[0].GetValue<string>('command.command'));
    Arguments := Actions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(4, Arguments.Count);
    Assert.AreEqual('COrderStateNames', Arguments.Items[2].Value);
    Assert.AreEqual('afterType', Arguments.Items[3].Value);
    Assert.AreEqual('implementation', Actions[1].GetValue<TJSONArray>('command.arguments').Items[3].Value);
    Assert.AreEqual(TLspEnumTables.SyncClientCommand, Actions[2].GetValue<string>('command.command'));
    Assert.AreEqual(2, Actions[2].GetValue<TJSONArray>('command.arguments').Count);
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspEnumTablesTests.RepairActionOnTable;
var
  Actions: TArray<TJSONObject>;
begin
  Actions := ActionsAt(FIndex, Shop, ShopFile, 4, 10);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('Fehlenden Eintrag ergänzen (osPaid)', Actions[0].GetValue<string>('title'));
    Assert.AreEqual('quickfix', Actions[0].GetValue<string>('kind'));
    Assert.IsTrue(Pos('"newText":", ''Paid''"', Actions[0].ToJSON) > 0, Actions[0].ToJSON);
  finally
    FreeAll(Actions);
  end;
  // Der eigene Typ von Other hat zwei Werte: dort fehlt osB.
  Actions := ActionsAt(FIndex, Other, OtherFile, 5, 10);
  try
    Assert.AreEqual(1, Integer(Length(Actions)));
    Assert.AreEqual('Fehlenden Eintrag ergänzen (osB)', Actions[0].GetValue<string>('title'));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspEnumTablesTests.ExecuteCreatesTable;
var
  Tree: TSyntaxTree;
  Answer: TJSONObject;
begin
  Tree := TPascalParser.Parse(Orders);
  try
    Answer := TLspEnumTables.Execute(Tree, OrdersFile, Orders, TTextPosition.Create(3, 5), 'COrderStateNames',
      'afterType', Context(FIndex));
    try
      Assert.IsTrue(Pos('COrderStateNames: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');',
        Answer.ToJSON) > 0, Answer.ToJSON);
      Assert.AreEqual(1, Answer.GetValue<Integer>('files'));
    finally
      Answer.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspEnumTablesTests.SyncChangesTablesAndCases;
var
  Tree: TSyntaxTree;
  Resolver: TNameResolver;
  Answer: TJSONObject;
  Json: string;
begin
  Tree := TPascalParser.Parse(Orders);
  Resolver := TNameResolver.Create(FIndex);
  try
    Answer := TLspEnumTables.Sync(Resolver, Tree, OrdersFile, Orders, TTextPosition.Create(3, 5), Context(FIndex));
    try
      Json := Answer.ToJSON;
      Assert.AreEqual(2, Answer.GetValue<Integer>('files'), Json);
      Assert.IsTrue(Pos(TDocumentUris.FromPath(ShopFile), Json) > 0, Json);
      Assert.IsFalse(Pos('Other', Json) > 0, Json);
      // CCodes ohne Hinweis: hinten ergänzt, mit Warnung.
      Assert.AreEqual(1, Answer.GetValue<TJSONArray>('warnings').Count, Json);
      Assert.IsTrue(Pos('"newText":", ''Paid''"', Json) > 0, Json);
      Assert.IsTrue(Pos('osPaid: ;', Json) > 0, Json);
      Assert.IsTrue(Answer.GetValue<string>('preview').StartsWith(
        'TOrderState: 2 Tabellen und 1 case-Anweisungen in 2 Dateien.'), Json);
    finally
      Answer.Free;
    end;
  finally
    Resolver.Free;
    Tree.Free;
  end;
end;

procedure TLspEnumTablesTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(Orders);
      try
        TLspEnumTables.Execute(Tree, OrdersFile, Orders, TTextPosition.Create(3, 5), 'TOrderState', 'afterType',
          Context(FIndex)).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(Orders);
      try
        TLspEnumTables.Execute(Tree, OrdersFile, Orders, TTextPosition.Create(3, 5), 'CNames', 'irgendwo',
          Context(FIndex)).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspEnumTablesTests);

end.
