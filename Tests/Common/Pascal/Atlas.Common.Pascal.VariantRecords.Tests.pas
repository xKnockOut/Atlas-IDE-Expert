unit Atlas.Common.Pascal.VariantRecords.Tests;

// Tests für Felder varianter Records (#846): Baum, Index mit Zweig, Cache,
// Gliederung und Vervollständigung nach "R.". Die Quelle von TRect2 ist der
// nachgestellte Fall 06 aus planung/parser-luecken-faelle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TVariantRecordsTests = class
  public
    [Test]
    procedure TreeHoldsBranchesAndFields;
    [Test]
    procedure IndexListsRectFields;
    [Test]
    procedure SelectorAndNestedVariants;
    [Test]
    procedure CacheKeepsBranch;
    [Test]
    procedure OutlineGroupsBranches;
    [Test]
    procedure CompletionAfterDotShowsLeft;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.DocumentSymbols;

const
  UnitRect =
    'unit U6;'#10'interface'#10'type'#10'  TPoint = record'#10'    X, Y: Integer;'#10'  end;'#10 +
    '  TRect2 = record'#10'    function Width: Integer;'#10'    case Integer of'#10 +
    '      0: (Left, Top, Right, Bottom: Integer);'#10'      1: (TopLeft, BottomRight: TPoint);'#10'  end;'#10 +
    'implementation'#10'function TRect2.Width: Integer;'#10'begin'#10'  Result := Right - Left;'#10'end;'#10'end.';
  UnitMessage =
    'unit Nachrichten;'#10'interface'#10'type'#10'  TKind = (mkA, mkB, mkC, mkD);'#10 +
    '  TMessage = record'#10'    Msg: Cardinal;'#10'    case Integer of'#10 +
    '      0: (WParam, LParam, Result: NativeInt);'#10 +
    '      1: (WParamLo, WParamHi: Word;'#10'          case Byte of'#10'            0: (Low: Byte);'#10 +
    '            1: (High: Byte));'#10'  end;'#10 +
    '  TMsg = record'#10'    case Kind: TKind of'#10'      mkA, mkB: (Value: Integer);'#10 +
    '      mkC: (Text: string[20]);'#10'      mkD: ();'#10'  end;'#10 +
    'implementation'#10'end.';
  MainFile = 'C:\P\Haupt.pas';
  UnitMain =
    'unit Haupt;'#10'interface'#10'uses U6;'#10'implementation'#10'procedure Zeige;'#10'var'#10 +
    '  R: TRect2;'#10'begin'#10'  R.'#10'end;'#10'end.';

function FindNode(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  Index: Integer;
begin
  if ANode.Kind = AKind then
    Exit(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindNode(ANode[Index], AKind);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

/// <summary>Felder eines Typs im Index als "Name=Zweig;" in Reihenfolge.</summary>
function Branches(const AUnit: TUnitIndex; const AContainer: string): string;
var
  Symbol: TIndexSymbol;
begin
  Result := '';
  for Symbol in AUnit.Symbols do
    if (Symbol.Container = AContainer) and (Symbol.Kind = TIndexSymbolKind.Field) then
      Result := Result + Symbol.Name + '=' + Symbol.VariantBranch + ';';
end;

/// <summary>Namen der Kinder eines Gliederungssymbols, eine Gruppe als "[Name: Kinder]".</summary>
function Names(const AChildren: TJSONValue): string;
var
  Item: TJSONValue;
  Entry: TJSONObject;
begin
  Result := '';
  if not (AChildren is TJSONArray) then
    Exit;
  for Item in TJSONArray(AChildren) do
  begin
    Entry := TJSONObject(Item);
    if Result <> '' then
      Result := Result + ' ';
    if Entry.GetValue<Integer>('kind', 0) = TLspSymbolKind.Namespace then
      Result := Result + '[' + Entry.GetValue<string>('name', '') + ': ' + Names(Entry.GetValue('children')) + ']'
    else
      Result := Result + Entry.GetValue<string>('name', '');
  end;
end;

/// <summary>Kinder des Typs ATypeName in der Gliederung (unter interface).</summary>
function TypeChildren(ASymbols: TJSONArray; const ATypeName: string): string;
var
  Root, Section, Entry: TJSONValue;
begin
  Result := '';
  for Root in ASymbols do
    for Section in TJSONArray(TJSONObject(Root).GetValue('children')) do
      if TJSONObject(Section).GetValue('children') is TJSONArray then
        for Entry in TJSONArray(TJSONObject(Section).GetValue('children')) do
          if TJSONObject(Entry).GetValue<string>('name', '') = ATypeName then
            Exit(Names(TJSONObject(Entry).GetValue('children')));
end;

{ TVariantRecordsTests }

procedure TVariantRecordsTests.TreeHoldsBranchesAndFields;
var
  Tree: TSyntaxTree;
  Part, Item: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(UnitMessage);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)));
    Part := FindNode(Tree.Root, TSyntaxKind.VariantPart);
    Assert.IsNotNull(Part);
    // case Integer of: Selektortyp, dann je Zweig ein CaseItem mit den Marken als Namen.
    Assert.IsTrue(Part[0].Kind = TSyntaxKind.TypeReference);
    Assert.AreEqual(3, Part.ChildCount);
    Assert.AreEqual('0', Part[1].Name);
    Assert.AreEqual('WParam,LParam,Result', Part[1][0].Name);
    Item := Part[2];
    Assert.AreEqual('1', Item.Name);
    // Zweig 1 enthält zwei Felder und einen verschachtelten varianten Teil.
    Assert.IsTrue(Item[0].Kind = TSyntaxKind.Field);
    Assert.IsTrue(Item[1].Kind = TSyntaxKind.VariantPart);
  finally
    Tree.Free;
  end;
end;

procedure TVariantRecordsTests.IndexListsRectFields;
var
  U: TUnitIndex;
  Symbol: TIndexSymbol;
  Found: Boolean;
begin
  U := TIndexExtractor.ExtractText(UnitRect, 'C:\P\U6.pas', nil);
  Assert.AreEqual('Left=0;Top=0;Right=0;Bottom=0;TopLeft=1;BottomRight=1;', Branches(U, 'TRect2'));
  Found := False;
  for Symbol in U.Symbols do
    if (Symbol.Container = 'TRect2') and (Symbol.Name = 'TopLeft') then
    begin
      Found := True;
      Assert.AreEqual('TPoint', Symbol.TypeName);
    end;
  Assert.IsTrue(Found);
  // Gewöhnliche Felder haben keinen Zweig.
  Assert.AreEqual('X=;Y=;', Branches(U, 'TPoint'));
end;

procedure TVariantRecordsTests.SelectorAndNestedVariants;
var
  U: TUnitIndex;
begin
  U := TIndexExtractor.ExtractText(UnitMessage, 'C:\P\Nachrichten.pas', nil);
  Assert.AreEqual('Msg=;WParam=0;LParam=0;Result=0;WParamLo=1;WParamHi=1;Low=1 › 0;High=1 › 1;',
    Branches(U, 'TMessage'));
  // Das benannte Selektorfeld ist ein gewöhnliches Feld; der leere Zweig mkD stört nicht.
  Assert.AreEqual('Kind=;Value=mkA, mkB;Text=mkC;', Branches(U, 'TMsg'));
end;

procedure TVariantRecordsTests.CacheKeepsBranch;
var
  Loaded: TArray<TUnitIndex>;
begin
  Loaded := TIndexCache.Deserialize(TIndexCache.Serialize([TIndexExtractor.ExtractText(UnitMessage,
    'C:\P\Nachrichten.pas', nil)]));
  Assert.AreEqual(1, Integer(Length(Loaded)));
  Assert.AreEqual('Msg=;WParam=0;LParam=0;Result=0;WParamLo=1;WParamHi=1;Low=1 › 0;High=1 › 1;',
    Branches(Loaded[0], 'TMessage'));
end;

procedure TVariantRecordsTests.OutlineGroupsBranches;
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Tree := TPascalParser.Parse(UnitMessage);
  Symbols := TLspDocumentSymbols.BuildSymbols(Tree);
  try
    Assert.AreEqual('Msg [case Integer of: WParam LParam Result WParamLo WParamHi [case Byte of: Low High]]',
      TypeChildren(Symbols, 'TMessage'));
    Assert.AreEqual('Kind [case Kind: TKind of: Value Text]', TypeChildren(Symbols, 'TMsg'));
  finally
    Symbols.Free;
    Tree.Free;
  end;
end;

procedure TVariantRecordsTests.CompletionAfterDotShowsLeft;
var
  Index: ISymbolIndex;
  Resolver: TNameResolver;
  Request: TCompletionRequest;
  Tree: TSyntaxTree;
  Items: TCompletionItems;
  Item: TCompletionItem;
  Json: TJSONArray;
  Data: TJSONObject;
  Listed: string;
  Position: Integer;
begin
  Index := TSymbolIndex.Create;
  Index.AddUnit(TIndexExtractor.ExtractText(UnitRect, 'C:\P\U6.pas', nil));
  Tree := TPascalParser.Parse(UnitMain);
  Resolver := TNameResolver.Create(Index);
  Request := TCompletionRequest.Create(UnitMain, MainFile, TTextPosition.Create(8, 4));
  try
    Request.Tree := Tree;
    Request.Resolver := Resolver;
    Request.Index := Index;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := TCompletionSettings.Default;
    Items := TLspCompletion.Collect(Request, TPostfixOptions.Default, nil);
  finally
    Request.Free;
    Resolver.Free;
    Tree.Free;
  end;
  Listed := '';
  Position := -1;
  for Item in Items.Items do
  begin
    Listed := Listed + Item.Name + ' ';
    if Item.Name = 'Left' then
      Position := Length(Listed);
  end;
  Assert.IsTrue(Position > 0, Listed);
  Assert.Contains(Listed, 'BottomRight ');
  Assert.Contains(Listed, 'Width ');
  // Der Zweig geht als data.variant ans Plugin („Zweig 0“).
  Json := CompletionItemsToJson(Items.Items, 0);
  try
    Data := nil;
    for Position := 0 to Json.Count - 1 do
      if TJSONObject(Json.Items[Position]).GetValue<string>('label', '') = 'TopLeft' then
        Data := TJSONObject(TJSONObject(Json.Items[Position]).GetValue('data'));
    Assert.IsNotNull(Data);
    Assert.AreEqual('1', Data.GetValue<string>('variant', ''));
  finally
    Json.Free;
  end;
  Index := nil;
end;

end.
