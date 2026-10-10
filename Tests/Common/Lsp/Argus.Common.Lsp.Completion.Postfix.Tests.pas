unit Argus.Common.Lsp.Completion.Postfix.Tests;

// Tests für die Postfix-Vorlagen in der Vervollständigung (#188).

interface

uses
  DUnitX.TestFramework,
  Argus.Common.Index.Contract,
  Argus.Common.Semantics.NameResolver,
  Argus.Common.Lsp.Completion;

type
  [TestFixture]
  TPostfixCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const ACode: string; AInlineVar: Boolean = True): TCompletionItems;
    function Find(const AItems: TCompletionItems; const AName: string; AKind: Integer;
      out AItem: TCompletionItem): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ForOverArray;
    [Test]
    procedure ForClassicAddsVariable;
    [Test]
    procedure TryFinallyAfterMember;
    [Test]
    procedure IfAssigned;
    [Test]
    procedure FormatOnString;
    [Test]
    procedure NothingForIntegerOrUnknown;
    [Test]
    procedure StatementsOnlyAtLineStart;
    [Test]
    procedure WritesTextEdit;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Argus.Common.Documents.Contract,
  Argus.Common.Configuration.Contract,
  Argus.Common.Pascal.SyntaxTree,
  Argus.Common.Pascal.Parser,
  Argus.Common.Index.SymbolIndex,
  Argus.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';
  KindSnippet = 15;

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    Name: string;'#10 +
    '    tryf: Integer;'#10 +
    '    procedure Bar(Anzahl: Integer);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Bar(Anzahl: Integer);'#10 +
    'var'#10 +
    '  Wert: TFoo;'#10 +
    '  Liste: TArray<Integer>;'#10 +
    'begin'#10 +
    '|'#10 +
    'end;'#10 +
    'end.';

  // Zeile, in der der Code steht (ab 0).
  CodeLine = 14;

procedure TPostfixCompletionTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TPostfixCompletionTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TPostfixCompletionTests.ItemsAt(const ACode: string; AInlineVar: Boolean): TCompletionItems;
var
  Text: string;
  Tree: TSyntaxTree;
  Options: TPostfixOptions;
begin
  // Cursor am Ende des Codes.
  Text := StringReplace(UnitHaupt, '|', ACode, []);
  Options := TPostfixOptions.Default;
  Options.InlineVar := AInlineVar;
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, Text,
      TTextPosition.Create(CodeLine, Length(ACode)), TCompletionMatching.Prefix, Options);
  finally
    Tree.Free;
  end;
end;

function TPostfixCompletionTests.Find(const AItems: TCompletionItems; const AName: string; AKind: Integer;
  out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if SameText(Item.Name, AName) and (Item.Kind = AKind) then
    begin
      AItem := Item;
      Exit(True);
    end;
  Result := False;
end;

procedure TPostfixCompletionTests.ForOverArray;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.for'), 'for', KindSnippet, Item));
  Assert.AreEqual('for var Item in Liste do', Item.TextEdit.NewText);
  Assert.AreEqual('Liste.for', Item.FilterText);
  Assert.AreEqual(2, Item.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(11, Item.TextEdit.Range.EndPos.Character);
  // Nach "Liste.fo" greift der Filter ebenso.
  Assert.IsTrue(Find(ItemsAt('  Liste.fo'), 'for', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.ForClassicAddsVariable;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.for', False), 'for', KindSnippet, Item));
  Assert.AreEqual('for Item in Liste do', Item.TextEdit.NewText);
  Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
  Assert.Contains(Item.AdditionalEdits[0].NewText, 'Item: Integer;');
end;

procedure TPostfixCompletionTests.TryFinallyAfterMember;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Index, Member, Postfix: Integer;
begin
  Items := ItemsAt('  Wert.tryf');
  Assert.IsTrue(Find(Items, 'tryf', KindSnippet, Item));
  Assert.AreEqual('try'#10'    '#10'  finally'#10'    Wert.Free;'#10'  end;', Item.TextEdit.NewText);
  // Das Feld tryf steht vor dem Postfix-Eintrag.
  Member := -1;
  Postfix := -1;
  for Index := 0 to High(Items.Items) do
    if SameText(Items.Items[Index].Name, 'tryf') then
      if Items.Items[Index].Kind = KindSnippet then
        Postfix := Index
      else
        Member := Index;
  Assert.IsTrue((Member >= 0) and (Member < Postfix));
end;

procedure TPostfixCompletionTests.IfAssigned;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Wert.ifa'), 'ifa', KindSnippet, Item));
  Assert.AreEqual('if Assigned(Wert) then', Item.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Wert.for'), 'for', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.FormatOnString;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Name := Name.fmt'), 'fmt', KindSnippet, Item));
  Assert.AreEqual('Format(Name, [])', Item.TextEdit.NewText);
  Assert.AreEqual(10, Item.TextEdit.Range.StartPos.Character);
end;

procedure TPostfixCompletionTests.NothingForIntegerOrUnknown;
var
  Item: TCompletionItem;
begin
  Assert.IsFalse(Find(ItemsAt('  Anzahl.for'), 'for', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Unbekannt.ifa'), 'ifa', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  TFoo.ifa'), 'ifa', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.StatementsOnlyAtLineStart;
var
  Item: TCompletionItem;
begin
  Assert.IsFalse(Find(ItemsAt('  Wert := Wert.ifa'), 'ifa', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Name := Liste.for'), 'for', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.WritesTextEdit;
var
  Json: TJSONObject;
  Entry: TJSONObject;
  Items: TCompletionItems;
  Index: Integer;
begin
  Items := ItemsAt('  Wert.ifa');
  Json := TLspCompletion.ToJson(Items);
  try
    Entry := nil;
    for Index := 0 to TJSONArray(Json.GetValue('items')).Count - 1 do
      if TJSONArray(Json.GetValue('items')).Items[Index].GetValue<Integer>('kind') = KindSnippet then
        Entry := TJSONObject(TJSONArray(Json.GetValue('items')).Items[Index]);
    Assert.IsNotNull(Entry);
    Assert.AreEqual('if Assigned(Wert) then', Entry.GetValue<string>('textEdit.newText'));
    Assert.AreEqual('Wert.ifa', Entry.GetValue<string>('filterText'));
  finally
    Json.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixCompletionTests);

end.
