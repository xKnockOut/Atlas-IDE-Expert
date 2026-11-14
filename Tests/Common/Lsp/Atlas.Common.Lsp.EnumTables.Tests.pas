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
  cOrdersFile = 'C:\P\Orders.pas';
  cShopFile = 'C:\P\Shop.pas';
  cOtherFile = 'C:\P\Other.pas';
  cOrders =
    'unit Orders;'#10 +                                                   // 0
    'interface'#10 +                                                      // 1
    'type'#10 +                                                           // 2
    '  TOrderState = (osNew, osPaid, osPaymentDue);'#10 +                 // 3
    'const'#10 +                                                          // 4
    '  CCodes: array[TOrderState] of Integer = (1, 3);'#10 +              // 5
    'implementation'#10 +                                                 // 6
    'end.'#10;

  cShop =
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
  cOther =
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
  if SameText(AFileName, cOrdersFile) then
  begin
    AText := cOrders;
  end
  else if SameText(AFileName, cShopFile) then
  begin
    AText := cShop;
  end
  else if SameText(AFileName, cOtherFile) then
  begin
    AText := cOther;
  end
  else
  begin
    Result := False;
  end;
end;

procedure TLspEnumTablesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOrders, cOrdersFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cShop, cShopFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cOther, cOtherFile, nil));
end;

procedure TLspEnumTablesTests.TearDown;
begin
  FIndex := nil;
end;

function Context(const AIndex: ISymbolIndex): TEnumTablesContext;
begin
  Result := Default(TEnumTablesContext);
  Result.Index := AIndex;
  Result.Files := [cOrdersFile, cShopFile, cOtherFile];
  Result.ReadText := ReadFile;
end;

/// <summary>Orders mit dem Baum ATree, Stelle auf TOrderState.</summary>
function OrdersDocument(ATree: TSyntaxTree): TEnumTablesDocument;
begin
  Result := TEnumTablesDocument.Create(ATree, cOrdersFile, cOrders, TTextPosition.Create(3, 5));
end;

function ActionsAt(const AIndex: ISymbolIndex; const AText, AFileName: string; ALine,
  ACharacter: Integer): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  mTree := TPascalParser.Parse(AText);
  mResolver := TNameResolver.Create(AIndex);
  try
    mResolver.PinTree(mTree, AFileName);
    try
      Result := TLspEnumTables.Actions(mResolver, AIndex, mTree, AText, TDocumentUris.FromPath(AFileName),
        TTextPosition.Create(ALine, ACharacter));
    finally
      mResolver.UnpinTree;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  mAction: TJSONObject;
begin
  for mAction in AActions do
  begin
    mAction.Free;
  end;
end;

procedure TLspEnumTablesTests.ActionsOnType;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsAt(FIndex, cOrders, cOrdersFile, 3, 5);
  try
    Assert.AreEqual(3, Integer(Length(mActions)));
    Assert.AreEqual('Namenstabelle anlegen (TOrderState)', mActions[0].GetValue<string>('title'));
    Assert.AreEqual('Namenstabelle anlegen, im implementation-Teil (TOrderState)',
      mActions[1].GetValue<string>('title'));
    Assert.AreEqual('Tabellen von TOrderState nachziehen', mActions[2].GetValue<string>('title'));
    Assert.AreEqual(TLspEnumTables.cClientCommand, mActions[0].GetValue<string>('command.command'));
    mArguments := mActions[0].GetValue<TJSONArray>('command.arguments');
    Assert.AreEqual(4, mArguments.Count);
    Assert.AreEqual('COrderStateNames', mArguments.Items[2].Value);
    Assert.AreEqual('afterType', mArguments.Items[3].Value);
    Assert.AreEqual('implementation', mActions[1].GetValue<TJSONArray>('command.arguments').Items[3].Value);
    Assert.AreEqual(TLspEnumTables.cSyncClientCommand, mActions[2].GetValue<string>('command.command'));
    Assert.AreEqual(2, mActions[2].GetValue<TJSONArray>('command.arguments').Count);
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspEnumTablesTests.RepairActionOnTable;
var
  mActions: TArray<TJSONObject>;
begin
  mActions := ActionsAt(FIndex, cShop, cShopFile, 4, 10);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Fehlenden Eintrag ergänzen (osPaid)', mActions[0].GetValue<string>('title'));
    Assert.AreEqual('quickfix', mActions[0].GetValue<string>('kind'));
    Assert.IsTrue(Pos('"newText":", ''Paid''"', mActions[0].ToJSON) > 0, mActions[0].ToJSON);
  finally
    FreeAll(mActions);
  end;
  // Der eigene Typ von Other hat zwei Werte: dort fehlt osB.
  mActions := ActionsAt(FIndex, cOther, cOtherFile, 5, 10);
  try
    Assert.AreEqual(1, Integer(Length(mActions)));
    Assert.AreEqual('Fehlenden Eintrag ergänzen (osB)', mActions[0].GetValue<string>('title'));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspEnumTablesTests.ExecuteCreatesTable;
var
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
begin
  mTree := TPascalParser.Parse(cOrders);
  try
    mAnswer := TLspEnumTables.Execute(OrdersDocument(mTree), 'COrderStateNames', 'afterType', Context(FIndex));
    try
      Assert.IsTrue(Pos('COrderStateNames: array[TOrderState] of string = (''New'', ''Paid'', ''Payment due'');',
        mAnswer.ToJSON) > 0, mAnswer.ToJSON);
      Assert.AreEqual(1, mAnswer.GetValue<Integer>('files'));
    finally
      mAnswer.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspEnumTablesTests.SyncChangesTablesAndCases;
var
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
  mAnswer: TJSONObject;
  mJson: string;
begin
  mTree := TPascalParser.Parse(cOrders);
  mResolver := TNameResolver.Create(FIndex);
  try
    mAnswer := TLspEnumTables.Sync(mResolver, OrdersDocument(mTree), Context(FIndex));
    try
      mJson := mAnswer.ToJSON;
      Assert.AreEqual(2, mAnswer.GetValue<Integer>('files'), mJson);
      Assert.IsTrue(Pos(TDocumentUris.FromPath(cShopFile), mJson) > 0, mJson);
      Assert.IsFalse(Pos('Other', mJson) > 0, mJson);
      // CCodes ohne Hinweis: hinten ergänzt, mit Warnung.
      Assert.AreEqual(1, mAnswer.GetValue<TJSONArray>('warnings').Count, mJson);
      Assert.IsTrue(Pos('"newText":", ''Paid''"', mJson) > 0, mJson);
      Assert.IsTrue(Pos('osPaid: ;', mJson) > 0, mJson);
      Assert.IsTrue(mAnswer.GetValue<string>('preview').StartsWith(
        'TOrderState: 2 Tabellen und 1 case-Anweisungen in 2 Dateien.'), mJson);
    finally
      mAnswer.Free;
    end;
  finally
    mResolver.Free;
    mTree.Free;
  end;
end;

procedure TLspEnumTablesTests.ErrorsCarryReason;
begin
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(cOrders);
      try
        TLspEnumTables.Execute(OrdersDocument(Tree), 'TOrderState', 'afterType', Context(FIndex)).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
  Assert.WillRaise(
    procedure
    var
      Tree: TSyntaxTree;
    begin
      Tree := TPascalParser.Parse(cOrders);
      try
        TLspEnumTables.Execute(OrdersDocument(Tree), 'CNames', 'irgendwo', Context(FIndex)).Free;
      finally
        Tree.Free;
      end;
    end, EJsonRpcError);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspEnumTablesTests);

end.
