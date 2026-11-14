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
    function ItemsAt(const ACode: string; AInlineVar: Boolean): TCompletionItems; overload;
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
  Atlas.Common.Lsp.Completion.Postfix,
  Atlas.Common.Lsp.Completion.Lists,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cKindSnippet = 15;

  cUnitHaupt =
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
  cCodeLine = 17;

  // Funktion für .exit; Cursorzeile 6.
  cUnitFunktion =
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
  mOptions: TPostfixOptions;
begin
  mOptions := TPostfixOptions.Default;
  mOptions.InlineVar := AInlineVar;
  Result := ItemsAt(ACode, mOptions);
end;

function TPostfixCompletionTests.ItemsAt(const ACode: string; const AOptions: TPostfixOptions): TCompletionItems;
begin
  // Cursor am Ende des Codes.
  Result := ItemsIn(StringReplace(cUnitHaupt, '|', ACode, []), cCodeLine, Length(ACode), AOptions);
end;

function TPostfixCompletionTests.ItemsIn(const AText: string; ALine: Integer; ACharacter: Integer;
  const AOptions: TPostfixOptions): TCompletionItems;
var
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mTree := TPascalParser.Parse(AText);
  mRequest := TCompletionRequest.Create(AText, cHauptFile, TTextPosition.Create(ALine, ACharacter));
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    Result := TCompletionLists.Collect(mRequest, AOptions, nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TPostfixCompletionTests.Find(const AItems: TCompletionItems; const AName: string; AKind: Integer;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) and (mItem.Kind = AKind) then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TPostfixCompletionTests.ForOverArray;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.for', True), 'for', cKindSnippet, mItem));
  // Der Cursor steht danach eingerückt in der Folgezeile.
  Assert.AreEqual('for var Item in Liste do'#10'    ', mItem.TextEdit.NewText);
  Assert.AreEqual('postfix', mItem.Action);
  Assert.AreEqual('Liste.for', mItem.FilterText);
  Assert.AreEqual(2, mItem.TextEdit.Range.StartPos.Character);
  Assert.AreEqual(11, mItem.TextEdit.Range.EndPos.Character);
  // Nach "Liste.fo" greift der Filter ebenso.
  Assert.IsTrue(Find(ItemsAt('  Liste.fo', True), 'for', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.ForClassicAddsVariable;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.for', False), 'for', cKindSnippet, mItem));
  Assert.AreEqual('for Item in Liste do'#10'    ', mItem.TextEdit.NewText);
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
  Assert.Contains(mItem.AdditionalEdits[0].NewText, 'Item: Integer;');
end;

procedure TPostfixCompletionTests.TryFinallyAfterMember;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mIndex, mMember, mPostfix: Integer;
begin
  mItems := ItemsAt('  Wert.tryf', True);
  Assert.IsTrue(Find(mItems, 'tryf', cKindSnippet, mItem));
  Assert.AreEqual('try'#10'    '#10'  finally'#10'    Wert.Free;'#10'  end;', mItem.TextEdit.NewText);
  // Das Feld tryf steht vor dem Postfix-Eintrag.
  mMember := -1;
  mPostfix := -1;
  for mIndex := 0 to High(mItems.Items) do
  begin
    if SameText(mItems.Items[mIndex].Name, 'tryf') then
    begin
      if mItems.Items[mIndex].Kind = cKindSnippet then
      begin
        mPostfix := mIndex;
      end
      else
      begin
        mMember := mIndex;
      end;
    end;
  end;
  Assert.IsTrue((mMember >= 0) and (mMember < mPostfix));
end;

procedure TPostfixCompletionTests.IfAssigned;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Wert.ifa', True), 'ifa', cKindSnippet, mItem));
  Assert.AreEqual('if Assigned(Wert) then'#10'    ', mItem.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Wert.for', True), 'for', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.FormatOnString;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Name := Name.fmt', True), 'fmt', cKindSnippet, mItem));
  Assert.AreEqual('Format(Name, [])', mItem.TextEdit.NewText);
  Assert.AreEqual(10, mItem.TextEdit.Range.StartPos.Character);
end;

procedure TPostfixCompletionTests.NothingForIntegerOrUnknown;
var
  mItem: TCompletionItem;
begin
  Assert.IsFalse(Find(ItemsAt('  Anzahl.for', True), 'for', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Unbekannt.ifa', True), 'ifa', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  TFoo.ifa', True), 'ifa', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.StatementsOnlyAtLineStart;
var
  mItem: TCompletionItem;
begin
  Assert.IsFalse(Find(ItemsAt('  Wert := Wert.ifa', True), 'ifa', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Name := Liste.for', True), 'for', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.WritesTextEdit;
var
  mJson: TJSONObject;
  mEntry: TJSONObject;
  mItems: TCompletionItems;
  mIndex: Integer;
begin
  mItems := ItemsAt('  Wert.ifa', True);
  mJson := TLspCompletion.ToJson(mItems);
  try
    mEntry := nil;
    for mIndex := 0 to TJSONArray(mJson.GetValue('items')).Count - 1 do
    begin
      if TJSONArray(mJson.GetValue('items')).Items[mIndex].GetValue<Integer>('kind') = cKindSnippet then
      begin
        mEntry := TJSONObject(TJSONArray(mJson.GetValue('items')).Items[mIndex]);
      end;
    end;
    Assert.IsNotNull(mEntry);
    Assert.AreEqual('if Assigned(Wert) then'#10'    ', mEntry.GetValue<string>('textEdit.newText'));
    Assert.AreEqual('Wert.ifa', mEntry.GetValue<string>('filterText'));
    Assert.AreEqual('postfix', mEntry.GetValue<string>('data.action'));
  finally
    mJson.Free;
  end;
end;

procedure TPostfixCompletionTests.ReferenceTemplates;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Wert.notnil', True), 'notnil', cKindSnippet, mItem));
  Assert.AreEqual('if Assigned(Wert) then'#10'    ', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.nil', True), 'nil', cKindSnippet, mItem));
  Assert.AreEqual('if not Assigned(Wert) then'#10'    ', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.free', True), 'free', cKindSnippet, mItem));
  Assert.AreEqual('FreeAndNil(Wert);', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.var', True), 'var', cKindSnippet, mItem));
  Assert.AreEqual('var Foo := Wert;', mItem.TextEdit.NewText);
  // Nicht bei Strings oder Booleans.
  Assert.IsFalse(Find(ItemsAt('  Name.notnil', True), 'notnil', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Fertig.free', True), 'free', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.BooleanTemplates;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Fertig := Fertig.not', True), 'not', cKindSnippet, mItem));
  Assert.AreEqual('not Fertig', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Fertig.if', True), 'if', cKindSnippet, mItem));
  Assert.AreEqual('if Fertig then'#10'    ', mItem.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Wert.not', True), 'not', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Name.if', True), 'if', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.ForInOnEnumerableOnly;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  Liste.forin', True), 'forin', cKindSnippet, mItem));
  Assert.AreEqual('for var Item in Liste do'#10'    ', mItem.TextEdit.NewText);
  Assert.IsFalse(Find(ItemsAt('  Anzahl.forin', True), 'forin', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.TryAfterConstructorCall;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try', True), 'try', cKindSnippet, mItem));
  Assert.AreEqual('var Foo := TFoo.Create;'#10'  try'#10'    '#10'  finally'#10'    Foo.Free;'#10'  end;',
    mItem.TextEdit.NewText);
  // Nur hinter einem Konstruktoraufruf.
  Assert.IsFalse(Find(ItemsAt('  Wert.try', True), 'try', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.TryClassicDeclaresVariable;
var
  mItem: TCompletionItem;
begin
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try', False), 'try', cKindSnippet, mItem));
  Assert.IsTrue(mItem.TextEdit.NewText.StartsWith('Foo := TFoo.Create;'#10'  try'));
  Assert.AreEqual(1, Integer(Length(mItem.AdditionalEdits)));
  Assert.Contains(mItem.AdditionalEdits[0].NewText, 'Foo: TFoo;');
end;

procedure TPostfixCompletionTests.VarNeedsKnownTypeWithoutInlineVar;
var
  mItem: TCompletionItem;
begin
  // refactoring.inlineVar aus bzw. Delphi vor 10.3: Zuweisung und Eintrag im var-Abschnitt.
  Assert.IsTrue(Find(ItemsAt('  Wert.var', False), 'var', cKindSnippet, mItem));
  Assert.AreEqual('Foo := Wert;', mItem.TextEdit.NewText);
  Assert.Contains(mItem.AdditionalEdits[0].NewText, 'Foo: TFoo;');
end;

procedure TPostfixCompletionTests.ExitOnlyInFunction;
var
  mItem: TCompletionItem;
begin
  // Bar ist eine Prozedur.
  Assert.IsFalse(Find(ItemsAt('  Wert.exit', True), 'exit', cKindSnippet, mItem));
  Assert.IsTrue(Find(ItemsIn(StringReplace(cUnitFunktion, '|', '  Wert.exit', []), 6, 11,
    TPostfixOptions.Default), 'exit', cKindSnippet, mItem));
  Assert.AreEqual('Exit(Wert);', mItem.TextEdit.NewText);
end;

procedure TPostfixCompletionTests.SnippetPlacesCaretOnNextLine;
var
  mOptions: TPostfixOptions;
  mItem: TCompletionItem;
begin
  // FCustomer.notnil + Enter: if Assigned(FCustomer) then, Cursor eingerückt in der Folgezeile.
  mOptions := TPostfixOptions.Default;
  mOptions.Snippet := True;
  Assert.IsTrue(Find(ItemsAt('  Wert.notnil', mOptions), 'notnil', cKindSnippet, mItem));
  Assert.IsTrue(mItem.Snippet);
  Assert.AreEqual('if Assigned(Wert) then'#10'    $0', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.var', mOptions), 'var', cKindSnippet, mItem));
  Assert.AreEqual('var ${1:Foo} := Wert;$0', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  Wert.tryf', mOptions), 'tryf', cKindSnippet, mItem));
  Assert.AreEqual('try'#10'    $0'#10'  finally'#10'    Wert.Free;'#10'  end;', mItem.TextEdit.NewText);
  Assert.IsTrue(Find(ItemsAt('  TFoo.Create.try', mOptions), 'try', cKindSnippet, mItem));
  Assert.IsTrue(mItem.TextEdit.NewText.StartsWith('var ${1:Foo} := TFoo.Create;'));
  Assert.Contains(mItem.TextEdit.NewText, '$1.Free;');
end;

procedure TPostfixCompletionTests.DisabledOffersNothing;
var
  mOptions: TPostfixOptions;
  mItem: TCompletionItem;
begin
  // completion.postfixTemplates: false
  mOptions := TPostfixOptions.Default;
  mOptions.Enabled := False;
  Assert.IsFalse(Find(ItemsAt('  Wert.notnil', mOptions), 'notnil', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Liste.for', mOptions), 'for', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.CustomTemplatesWithCondition;
var
  mOptions: TPostfixOptions;
  mItem: TCompletionItem;
begin
  mOptions := TPostfixOptions.Default;
  mOptions.Custom := [TPostfixTemplate.Custom('log', 'Protokoll', 'Log(''%s'', [$expr]);', 'class'),
    TPostfixTemplate.Custom('foo', 'Nur TFoo', 'Pruefe($expr);', 'TFoo'),
    TPostfixTemplate.Custom('bar', 'Nur TBar', 'Pruefe($expr);', 'TBar')];
  Assert.IsTrue(Find(ItemsAt('  Wert.log', mOptions), 'log', cKindSnippet, mItem));
  Assert.AreEqual('Log(''%s'', [Wert]);', mItem.TextEdit.NewText);
  Assert.AreEqual('Protokoll', mItem.Detail);
  Assert.IsFalse(Find(ItemsAt('  Name.log', mOptions), 'log', cKindSnippet, mItem));
  Assert.IsTrue(Find(ItemsAt('  Wert.foo', mOptions), 'foo', cKindSnippet, mItem));
  Assert.IsFalse(Find(ItemsAt('  Wert.bar', mOptions), 'bar', cKindSnippet, mItem));
  // Als Snippet bleiben die Platzhalter der Vorlage, der Ausdruck wird maskiert.
  mOptions.Custom := [TPostfixTemplate.Custom('chk', '', 'if ${1:Ok}($expr) then'#10'  $0', '')];
  mOptions.Snippet := True;
  Assert.IsTrue(Find(ItemsAt('  Wert.chk', mOptions), 'chk', cKindSnippet, mItem));
  Assert.AreEqual('if ${1:Ok}(Wert) then'#10'    $0', mItem.TextEdit.NewText);
end;

procedure TPostfixCompletionTests.CallsAndCastsBeforeTheDot;
var
  mItem: TCompletionItem;
begin
  // Ausdruck bis zum Anweisungsanfang, auch mit Aufruf oder Typumwandlung.
  Assert.IsTrue(Find(ItemsAt('  Clone(1).notnil', True), 'notnil', cKindSnippet, mItem));
  Assert.AreEqual('if Assigned(Clone(1)) then'#10'    ', mItem.TextEdit.NewText);
  Assert.AreEqual('Clone(1).notnil', mItem.FilterText);
  Assert.IsTrue(Find(ItemsAt('  TFoo(Wert).free', True), 'free', cKindSnippet, mItem));
  Assert.AreEqual('FreeAndNil(TFoo(Wert));', mItem.TextEdit.NewText);
  // Nach einer offenen Klammer beginnt der Ausdruck dahinter.
  Assert.IsFalse(Find(ItemsAt('  Bar(Liste.fo', True), 'for', cKindSnippet, mItem));
  Assert.IsTrue(Find(ItemsAt('  Name := Name.fmt', True), 'fmt', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.NothingForMultiLineExpression;
var
  mText: string;
  mItem: TCompletionItem;
begin
  mText := StringReplace(cUnitHaupt, '|', '  Clone('#10'    1).notnil', []);
  Assert.IsFalse(Find(ItemsIn(mText, cCodeLine + 1, 13, TPostfixOptions.Default), 'notnil', cKindSnippet, mItem));
end;

procedure TPostfixCompletionTests.ParsesCustomTemplatesFromPlugin;
var
  mParams: TJSONObject;
  mTemplates: TArray<TPostfixTemplate>;
begin
  mParams := TJSONObject.ParseJSONValue('{"templates": [{"key": "log", "description": "Protokoll", ' +
    '"body": "Log($expr);", "type": "class"}, {"key": "a b", "body": "x"}, {"key": "leer"}]}') as TJSONObject;
  try
    mTemplates := TCompletionPostfix.ParseTemplates(mParams);
  finally
    mParams.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mTemplates)));
  Assert.AreEqual('log', mTemplates[0].Key);
  Assert.AreEqual('class', mTemplates[0].Condition);
  Assert.IsTrue(mTemplates[0].IsCustom);
end;

initialization
  TDUnitX.RegisterTestFixture(TPostfixCompletionTests);

end.
