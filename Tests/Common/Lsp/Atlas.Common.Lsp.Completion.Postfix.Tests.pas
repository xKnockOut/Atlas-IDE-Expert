unit Atlas.Common.Lsp.Completion.Postfix.Tests;

// Tests für die Postfix-Vorlagen in der Vervollständigung (#188).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TPostfixCompletionTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const ACode: string; AInlineVar: Boolean = True): TCompletionItems; overload;
    function ItemsAt(const ACode: string; const AOptions: TPostfixOptions): TCompletionItems; overload;
    function ItemsIn(const AText: string; ALine: Integer; ACharacter: Integer;
      const AOptions: TPostfixOptions): TCompletionItems;
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
    [Test]
    procedure ReferenceTemplates;
    [Test]
    procedure BooleanTemplates;
    [Test]
    procedure ForInOnEnumerableOnly;
    [Test]
    procedure TryAfterConstructorCall;
    [Test]
    procedure TryClassicDeclaresVariable;
    [Test]
    procedure VarNeedsKnownTypeWithoutInlineVar;
    [Test]
    procedure ExitOnlyInFunction;
    [Test]
    procedure SnippetPlacesCaretOnNextLine;
    [Test]
    procedure DisabledOffersNothing;
    [Test]
    procedure CustomTemplatesWithCondition;
    [Test]
    procedure CallsAndCastsBeforeTheDot;
    [Test]
    procedure NothingForMultiLineExpression;
    [Test]
    procedure ParsesCustomTemplatesFromPlugin;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.PostfixTemplates,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';
  KindSnippet = 15;

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    Name: string;'#10 +
    '    Fertig: Boolean;'#10 +
    '    tryf: Integer;'#10 +
    '    constructor Create;'#10 +
    '    function Clone(Tiefe: Integer): TFoo;'#10 +
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
  CodeLine = 17;

  // Funktion für .exit; Cursorzeile 6.
  UnitFunktion =
    'unit Funktion;'#10 +
    'interface'#10 +
    'type TFoo = class end;'#10 +
    'implementation'#10 +
    'function Liefere(Wert: TFoo): TFoo;'#10 +
    'begin'#10 +
    '|'#10 +
    'end;'#10 +
    'end.';

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
  Options: TPostfixOptions;
begin
  Options := TPostfixOptions.Default;
  Options.InlineVar := AInlineVar;
  Result := ItemsAt(ACode, Options);
end;

function TPostfixCompletionTests.ItemsAt(const ACode: string; const AOptions: TPostfixOptions): TCompletionItems;
begin
  // Cursor am Ende des Codes.
  Result := ItemsIn(StringReplace(UnitHaupt, '|', ACode, []), CodeLine, Length(ACode), AOptions);
end;

function TPostfixCompletionTests.ItemsIn(const AText: string; ALine: Integer; ACharacter: Integer;
  const AOptions: TPostfixOptions): TCompletionItems;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, AText,
      TTextPosition.Create(ALine, ACharacter), TCompletionMatching.Prefix, AOptions);
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
  // Der Cursor steht danach eingerückt in der Folgezeile.
  Assert.AreEqual('for var Item in Liste do'#10'    ', Item.TextEdit.NewText);
  Assert.AreEqual('postfix', Item.Action);
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
  Assert.AreEqual('for Item in Liste do'#10'    ', Item.TextEdit.NewText);
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
  Assert.AreEqual('if Assigned(Wert) then'#10'    ', Item.TextEdit.NewText);
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
    Assert.AreEqual('if Assigned(Wert) then'#10'    ', Entry.GetValue<string>('textEdit.newText'));
    Assert.AreEqual('Wert.ifa', Entry.GetValue<string>('filterText'));
    Assert.AreEqual('postfix', Entry.GetValue<string>('data.action'));
  finally
    Json.Free;
  end;
end;

procedure TPostfixCompletionTests.ReferenceTemplates;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Wert.notnil'), 'notnil', KindSnippet, Item));
  Assert.AreEqual('if Assigned(Wert) then'#10'    ', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.nil'), 'nil', KindSnippet, Item));
  Assert.AreEqual('if not Assigned(Wert) then'#10'    ', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.free'), 'free', KindSnippet, Item));
  Assert.AreEqual('FreeAndNil(Wert);', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.var'), 'var', KindSnippet, Item));
  Assert.AreEqual('var Foo := Wert;', Item.TextEdit.NewText);
  // Nicht bei Strings oder Booleans.
  Assert.IsFalse(Find(ItemsAt('  Name.notnil'), 'notnil', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Fertig.free'), 'free', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.BooleanTemplates;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Fertig := Fertig.not'), 'not', KindSnippet, Item));
  Assert.AreEqual('not Fertig', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Fertig.if'), 'if', KindSnippet, Item));
  Assert.AreEqual('if Fertig then'#10'    ', Item.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Wert.not'), 'not', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Name.if'), 'if', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.ForInOnEnumerableOnly;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.forin'), 'forin', KindSnippet, Item));
  Assert.AreEqual('for var Item in Liste do'#10'    ', Item.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Anzahl.forin'), 'forin', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.TryAfterConstructorCall;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try'), 'try', KindSnippet, Item));
  Assert.AreEqual('var Foo := TFoo.Create;'#10'  try'#10'    '#10'  finally'#10'    Foo.Free;'#10'  end;',
    Item.TextEdit.NewText);
  // Nur hinter einem Konstruktoraufruf.
  Assert.IsFalse(Find(ItemsAt('  Wert.try'), 'try', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.TryClassicDeclaresVariable;
var
  Item: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try', False), 'try', KindSnippet, Item));
  Assert.IsTrue(Item.TextEdit.NewText.StartsWith('Foo := TFoo.Create;'#10'  try'));
  Assert.AreEqual(1, Integer(Length(Item.AdditionalEdits)));
  Assert.Contains(Item.AdditionalEdits[0].NewText, 'Foo: TFoo;');
end;

procedure TPostfixCompletionTests.VarNeedsKnownTypeWithoutInlineVar;
var
  Item: TCompletionItem;
begin
  // refactoring.inlineVar aus bzw. Delphi vor 10.3: Zuweisung und Eintrag im var-Abschnitt.
  Assert.IsTrue(Find(ItemsAt('  Wert.var', False), 'var', KindSnippet, Item));
  Assert.AreEqual('Foo := Wert;', Item.TextEdit.NewText);
  Assert.Contains(Item.AdditionalEdits[0].NewText, 'Foo: TFoo;');
end;

procedure TPostfixCompletionTests.ExitOnlyInFunction;
var
  Item: TCompletionItem;
begin
  // Bar ist eine Prozedur.
  Assert.IsFalse(Find(ItemsAt('  Wert.exit'), 'exit', KindSnippet, Item));
  Assert.IsTrue(Find(ItemsIn(StringReplace(UnitFunktion, '|', '  Wert.exit', []), 6, 11,
    TPostfixOptions.Default), 'exit', KindSnippet, Item));
  Assert.AreEqual('Exit(Wert);', Item.TextEdit.NewText);
end;

procedure TPostfixCompletionTests.SnippetPlacesCaretOnNextLine;
var
  Options: TPostfixOptions;
  Item: TCompletionItem;
begin
  // FCustomer.notnil + Enter: if Assigned(FCustomer) then, Cursor eingerückt in der Folgezeile.
  Options := TPostfixOptions.Default;
  Options.Snippet := True;
  Assert.IsTrue(Find(ItemsAt('  Wert.notnil', Options), 'notnil', KindSnippet, Item));
  Assert.IsTrue(Item.Snippet);
  Assert.AreEqual('if Assigned(Wert) then'#10'    $0', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.var', Options), 'var', KindSnippet, Item));
  Assert.AreEqual('var ${1:Foo} := Wert;$0', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.tryf', Options), 'tryf', KindSnippet, Item));
  Assert.AreEqual('try'#10'    $0'#10'  finally'#10'    Wert.Free;'#10'  end;', Item.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try', Options), 'try', KindSnippet, Item));
  Assert.IsTrue(Item.TextEdit.NewText.StartsWith('var ${1:Foo} := TFoo.Create;'));
  Assert.Contains(Item.TextEdit.NewText, '$1.Free;');
end;

procedure TPostfixCompletionTests.DisabledOffersNothing;
var
  Options: TPostfixOptions;
  Item: TCompletionItem;
begin
  // completion.postfixTemplates: false
  Options := TPostfixOptions.Default;
  Options.Enabled := False;
  Assert.IsFalse(Find(ItemsAt('  Wert.notnil', Options), 'notnil', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Liste.for', Options), 'for', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.CustomTemplatesWithCondition;
var
  Options: TPostfixOptions;
  Item: TCompletionItem;
begin
  Options := TPostfixOptions.Default;
  Options.Custom := [TPostfixTemplate.Custom('log', 'Protokoll', 'Log(''%s'', [$expr]);', 'class'),
    TPostfixTemplate.Custom('foo', 'Nur TFoo', 'Pruefe($expr);', 'TFoo'),
    TPostfixTemplate.Custom('bar', 'Nur TBar', 'Pruefe($expr);', 'TBar')];
  Assert.IsTrue(Find(ItemsAt('  Wert.log', Options), 'log', KindSnippet, Item));
  Assert.AreEqual('Log(''%s'', [Wert]);', Item.TextEdit.NewText);
  Assert.AreEqual('Protokoll', Item.Detail);
  Assert.IsFalse(Find(ItemsAt('  Name.log', Options), 'log', KindSnippet, Item));
  Assert.IsTrue(Find(ItemsAt('  Wert.foo', Options), 'foo', KindSnippet, Item));
  Assert.IsFalse(Find(ItemsAt('  Wert.bar', Options), 'bar', KindSnippet, Item));
  // Als Snippet bleiben die Platzhalter der Vorlage, der Ausdruck wird maskiert.
  Options.Custom := [TPostfixTemplate.Custom('chk', '', 'if ${1:Ok}($expr) then'#10'  $0', '')];
  Options.Snippet := True;
  Assert.IsTrue(Find(ItemsAt('  Wert.chk', Options), 'chk', KindSnippet, Item));
  Assert.AreEqual('if ${1:Ok}(Wert) then'#10'    $0', Item.TextEdit.NewText);
end;

procedure TPostfixCompletionTests.CallsAndCastsBeforeTheDot;
var
  Item: TCompletionItem;
begin
  // Ausdruck bis zum Anweisungsanfang, auch mit Aufruf oder Typumwandlung.
  Assert.IsTrue(Find(ItemsAt('  Clone(1).notnil'), 'notnil', KindSnippet, Item));
  Assert.AreEqual('if Assigned(Clone(1)) then'#10'    ', Item.TextEdit.NewText);
  Assert.AreEqual('Clone(1).notnil', Item.FilterText);
  Assert.IsTrue(Find(ItemsAt('  TFoo(Wert).free'), 'free', KindSnippet, Item));
  Assert.AreEqual('FreeAndNil(TFoo(Wert));', Item.TextEdit.NewText);
  // Nach einer offenen Klammer beginnt der Ausdruck dahinter.
  Assert.IsTrue(Find(ItemsAt('  Bar(Liste.fo'), 'for', KindSnippet, Item) = False);
  Assert.IsTrue(Find(ItemsAt('  Name := Name.fmt'), 'fmt', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.NothingForMultiLineExpression;
var
  Text: string;
  Item: TCompletionItem;
begin
  Text := StringReplace(UnitHaupt, '|', '  Clone('#10'    1).notnil', []);
  Assert.IsFalse(Find(ItemsIn(Text, CodeLine + 1, 13, TPostfixOptions.Default), 'notnil', KindSnippet, Item));
end;

procedure TPostfixCompletionTests.ParsesCustomTemplatesFromPlugin;
var
  Params: TJSONObject;
  Templates: TArray<TPostfixTemplate>;
begin
  Params := TJSONObject.ParseJSONValue('{"templates": [{"key": "log", "description": "Protokoll", ' +
    '"body": "Log($expr);", "type": "class"}, {"key": "a b", "body": "x"}, {"key": "leer"}]}') as TJSONObject;
  try
    Templates := TLspCompletion.ParsePostfixTemplates(Params);
  finally
    Params.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Templates)));
  Assert.AreEqual('log', Templates[0].Key);
  Assert.AreEqual('class', Templates[0].Condition);
  Assert.IsTrue(Templates[0].IsCustom);
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixCompletionTests);

end.
