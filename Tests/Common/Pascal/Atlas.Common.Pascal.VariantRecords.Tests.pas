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
  Atlas.Common.Lsp.Completion.Lists,
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
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.Completion,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.DocumentSymbols;

const
  cUnitRect =
    'unit U6;'#10'interface'#10'type'#10'  TPoint = record'#10'    X, Y: Integer;'#10'  end;'#10 +
    '  TRect2 = record'#10'    function Width: Integer;'#10'    case Integer of'#10 +
    '      0: (Left, Top, Right, Bottom: Integer);'#10'      1: (TopLeft, BottomRight: TPoint);'#10'  end;'#10 +
    'implementation'#10'function TRect2.Width: Integer;'#10'begin'#10'  Result := Right - Left;'#10'end;'#10'end.';
  cUnitMessage =
    'unit Nachrichten;'#10'interface'#10'type'#10'  TKind = (mkA, mkB, mkC, mkD);'#10 +
    '  TMessage = record'#10'    Msg: Cardinal;'#10'    case Integer of'#10 +
    '      0: (WParam, LParam, Result: NativeInt);'#10 +
    '      1: (WParamLo, WParamHi: Word;'#10'          case Byte of'#10'            0: (Low: Byte);'#10 +
    '            1: (High: Byte));'#10'  end;'#10 +
    '  TMsg = record'#10'    case Kind: TKind of'#10'      mkA, mkB: (Value: Integer);'#10 +
    '      mkC: (Text: string[20]);'#10'      mkD: ();'#10'  end;'#10 +
    'implementation'#10'end.';
  cMainFile = 'C:\P\Haupt.pas';
  cUnitMain =
    'unit Haupt;'#10'interface'#10'uses U6;'#10'implementation'#10'procedure Zeige;'#10'var'#10 +
    '  R: TRect2;'#10'begin'#10'  R.'#10'end;'#10'end.';

function FindNode(ANode: TSyntaxNode; AKind: TSyntaxKind): TSyntaxNode;
var
  mIndex: Integer;
begin
  if ANode.Kind = AKind then
  begin
    Exit(ANode);
  end;
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FindNode(ANode[mIndex], AKind);
    if Result <> nil then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

/// <summary>Felder eines Typs im Index als "Name=Zweig;" in Reihenfolge.</summary>
function Branches(const AUnit: TUnitIndex; const AContainer: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.Symbols do
  begin
    if (mSymbol.Container = AContainer) and (mSymbol.Kind = TIndexSymbolKind.Field) then
    begin
      Result := Result + mSymbol.Name + '=' + mSymbol.VariantBranch + ';';
    end;
  end;
end;

/// <summary>Namen der Kinder eines Gliederungssymbols, eine Gruppe als "[Name: Kinder]".</summary>
function Names(const AChildren: TJSONValue): string;
var
  mItem: TJSONValue;
  mEntry: TJSONObject;
begin
  Result := '';
  if not (AChildren is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AChildren) do
  begin
    mEntry := TJSONObject(mItem);
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    if mEntry.GetValue<Integer>('kind', 0) = TLspSymbolKind.cNamespace then
    begin
      Result := Result + '[' + mEntry.GetValue<string>('name', '') + ': ' + Names(mEntry.GetValue('children')) + ']';
    end
    else
    begin
      Result := Result + mEntry.GetValue<string>('name', '');
    end;
  end;
end;

/// <summary>Eintrag ATypeName unter den Kindern von ASection.</summary>
function FindTypeEntry(ASection: TJSONValue; const ATypeName: string; out AEntry: TJSONObject): Boolean;
var
  mEntry: TJSONValue;
begin
  Result := False;
  AEntry := nil;
  if not (TJSONObject(ASection).GetValue('children') is TJSONArray) then
  begin
    Exit;
  end;
  for mEntry in TJSONArray(TJSONObject(ASection).GetValue('children')) do
  begin
    if TJSONObject(mEntry).GetValue<string>('name', '') = ATypeName then
    begin
      AEntry := TJSONObject(mEntry);
      Exit(True);
    end;
  end;
end;

/// <summary>Kinder des Typs ATypeName in der Gliederung (unter interface).</summary>
function TypeChildren(ASymbols: TJSONArray; const ATypeName: string): string;
var
  mRoot, mSection: TJSONValue;
  mEntry: TJSONObject;
begin
  Result := '';
  for mRoot in ASymbols do
  begin
    for mSection in TJSONArray(TJSONObject(mRoot).GetValue('children')) do
    begin
      if FindTypeEntry(mSection, ATypeName, mEntry) then
      begin
        Exit(Names(mEntry.GetValue('children')));
      end;
    end;
  end;
end;

{ TVariantRecordsTests }

procedure TVariantRecordsTests.TreeHoldsBranchesAndFields;
var
  mTree: TSyntaxTree;
  mPart, mItem: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cUnitMessage);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)));
    mPart := FindNode(mTree.Root, TSyntaxKind.VariantPart);
    Assert.IsNotNull(mPart);
    // case Integer of: Selektortyp, dann je Zweig ein CaseItem mit den Marken als Namen.
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.TypeReference, mPart[0].Kind);
    Assert.AreEqual(3, mPart.ChildCount);
    Assert.AreEqual('0', mPart[1].Name);
    Assert.AreEqual('WParam,LParam,Result', mPart[1][0].Name);
    mItem := mPart[2];
    Assert.AreEqual('1', mItem.Name);
    // Zweig 1 enthält zwei Felder und einen verschachtelten varianten Teil.
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.Field, mItem[0].Kind);
    Assert.AreEqual<TSyntaxKind>(TSyntaxKind.VariantPart, mItem[1].Kind);
  finally
    mTree.Free;
  end;
end;

procedure TVariantRecordsTests.IndexListsRectFields;
var
  U: TUnitIndex;
  mSymbol: TIndexSymbol;
  mFound: Boolean;
begin
  U := TIndexExtractor.ExtractText(cUnitRect, 'C:\P\U6.pas', nil);
  Assert.AreEqual('Left=0;Top=0;Right=0;Bottom=0;TopLeft=1;BottomRight=1;', Branches(U, 'TRect2'));
  mFound := False;
  for mSymbol in U.Symbols do
  begin
    if (mSymbol.Container = 'TRect2') and (mSymbol.Name = 'TopLeft') then
    begin
      mFound := True;
      Assert.AreEqual('TPoint', mSymbol.TypeName);
    end;
  end;
  Assert.IsTrue(mFound);
  // Gewöhnliche Felder haben keinen Zweig.
  Assert.AreEqual('X=;Y=;', Branches(U, 'TPoint'));
end;

procedure TVariantRecordsTests.SelectorAndNestedVariants;
var
  U: TUnitIndex;
begin
  U := TIndexExtractor.ExtractText(cUnitMessage, 'C:\P\Nachrichten.pas', nil);
  Assert.AreEqual('Msg=;WParam=0;LParam=0;Result=0;WParamLo=1;WParamHi=1;Low=1 › 0;High=1 › 1;',
    Branches(U, 'TMessage'));
  // Das benannte Selektorfeld ist ein gewöhnliches Feld; der leere Zweig mkD stört nicht.
  Assert.AreEqual('Kind=;Value=mkA, mkB;Text=mkC;', Branches(U, 'TMsg'));
end;

procedure TVariantRecordsTests.CacheKeepsBranch;
var
  mLoaded: TArray<TUnitIndex>;
begin
  mLoaded := TIndexCache.Deserialize(TIndexCache.Serialize([TIndexExtractor.ExtractText(cUnitMessage,
    'C:\P\Nachrichten.pas', nil)]));
  Assert.AreEqual(1, Integer(Length(mLoaded)));
  Assert.AreEqual('Msg=;WParam=0;LParam=0;Result=0;WParamLo=1;WParamHi=1;Low=1 › 0;High=1 › 1;',
    Branches(mLoaded[0], 'TMessage'));
end;

procedure TVariantRecordsTests.OutlineGroupsBranches;
var
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mTree := TPascalParser.Parse(cUnitMessage);
  mSymbols := TLspDocumentSymbols.BuildSymbols(mTree);
  try
    Assert.AreEqual('Msg [case Integer of: WParam LParam Result WParamLo WParamHi [case Byte of: Low High]]',
      TypeChildren(mSymbols, 'TMessage'));
    Assert.AreEqual('Kind [case Kind: TKind of: Value Text]', TypeChildren(mSymbols, 'TMsg'));
  finally
    mSymbols.Free;
    mTree.Free;
  end;
end;

procedure TVariantRecordsTests.CompletionAfterDotShowsLeft;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mRequest: TCompletionRequest;
  mTree: TSyntaxTree;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mJson: TJSONArray;
  mData: TJSONObject;
  mListed: string;
  mPosition: Integer;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitRect, 'C:\P\U6.pas', nil));
  mTree := TPascalParser.Parse(cUnitMain);
  mResolver := TNameResolver.Create(mIndex);
  mRequest := TCompletionRequest.Create(cUnitMain, cMainFile, TTextPosition.Create(8, 4));
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := mResolver;
    mRequest.Index := mIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := TCompletionSettings.Default;
    mItems := TCompletionLists.Collect(mRequest, TPostfixOptions.Default, nil);
  finally
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
  mListed := '';
  mPosition := -1;
  for mItem in mItems.Items do
  begin
    mListed := mListed + mItem.Name + ' ';
    if mItem.Name = 'Left' then
    begin
      mPosition := Length(mListed);
    end;
  end;
  Assert.IsTrue(mPosition > 0, mListed);
  Assert.Contains(mListed, 'BottomRight ');
  Assert.Contains(mListed, 'Width ');
  // Der Zweig geht als data.variant ans Plugin („Zweig 0“).
  mJson := CompletionItemsToJson(mItems.Items, 0);
  try
    mData := nil;
    for mPosition := 0 to mJson.Count - 1 do
    begin
      if TJSONObject(mJson.Items[mPosition]).GetValue<string>('label', '') = 'TopLeft' then
      begin
        mData := TJSONObject(TJSONObject(mJson.Items[mPosition]).GetValue('data'));
      end;
    end;
    Assert.IsNotNull(mData);
    Assert.AreEqual('1', mData.GetValue<string>('variant', ''));
  finally
    mJson.Free;
  end;
  mIndex := nil;
end;

end.
