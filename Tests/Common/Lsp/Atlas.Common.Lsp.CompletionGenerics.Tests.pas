unit Atlas.Common.Lsp.CompletionGenerics.Tests;

// Typargumente nach "<" (#450): Stelle, Typparameter samt Constraints, Filter nach den Constraints und
// eingesetzte Typparameter bei Mitgliedern.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionGenericsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const ACode: string): TCompletionItems;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
    function Has(const AItems: TCompletionItems; const AName: string): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsOpenAngleBracket;
    [Test]
    procedure ReadsParametersWithConstraints;
    [Test]
    procedure HintCodesFollowConstraints;
    [Test]
    procedure ClassConstraintKeepsClassesOnly;
    [Test]
    procedure RecordConstraintKeepsValueTypes;
    [Test]
    procedure ConstructorConstraintNeedsParameterlessCreate;
    [Test]
    procedure InterfaceConstraintKeepsImplementers;
    [Test]
    procedure SecondParameterUsesItsConstraint;
    [Test]
    procedure WithoutConstraintAllTypesAndBasicTypes;
    [Test]
    procedure ComparisonStaysNormalCompletion;
    [Test]
    procedure MembersShowBoundTypes;
    [Test]
    procedure SignatureShowsBoundTypes;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionGenerics,
  Atlas.Common.Lsp.CompletionJson,
  Atlas.Common.Lsp.SignatureHelp;

const
  HauptFile = 'C:\P\Haupt.pas';
  ListenFile = 'C:\P\Listen.pas';

  UnitListen =
    'unit Listen;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IVergleich = interface'#10 +
    '    function Vergleiche: Integer;'#10 +
    '  end;'#10 +
    '  IVergleichEx = interface(IVergleich)'#10 +
    '  end;'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TOhneStandard = class'#10 +
    '    constructor Create(AWert: Integer);'#10 +
    '  end;'#10 +
    '  TVergleicher = class(TInterfacedObject, IVergleichEx)'#10 +
    '    function Vergleiche: Integer;'#10 +
    '  end;'#10 +
    '  TPunkt = record'#10 +
    '    X: Integer;'#10 +
    '  end;'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  TObjektListe<T: class> = class'#10 +
    '    procedure Add(const Wert: T);'#10 +
    '    function Erster: T;'#10 +
    '  end;'#10 +
    '  TWerte<T: record> = class'#10 +
    '  end;'#10 +
    '  TFabrik<T: class, constructor> = class'#10 +
    '  end;'#10 +
    '  TSortierer<T: IVergleich> = class'#10 +
    '  end;'#10 +
    '  TPaar<K; V: class> = class'#10 +
    '  end;'#10 +
    '  TBeliebig<T> = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TOhneStandard.Create(AWert: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TVergleicher.Vergleiche: Integer;'#10 +
    'begin'#10 +
    '  Result := 0;'#10 +
    'end;'#10 +
    'procedure TObjektListe<T>.Add(const Wert: T);'#10 +
    'begin'#10 +
    'end;'#10 +
    'function TObjektListe<T>.Erster: T;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Listen;'#10 +
    'implementation'#10 +
    'procedure Frei;'#10 +
    'var'#10 +
    '  Zahl: Integer;'#10 +
    '  Kunden: TObjektListe<TKunde>;'#10 +
    '  L: { Typ };'#10 +
    'begin'#10 +
    '  { Code }'#10 +
    'end;'#10 +
    'end.';

/// <summary>Text ohne "|" und die Position des "|".</summary>
function Split(const AMarked: string; out APosition: TTextPosition): string;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  APosition := TTextPosition.Create(Line, Character);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionGenericsTests }

procedure TCompletionGenericsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitListen, ListenFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionGenericsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionGenericsTests.ItemsAt(const ACode: string): TCompletionItems;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
begin
  // ACode steht im var-Abschnitt (Typ) oder im Rumpf (Code), je nachdem, ob es mit ":" beginnt.
  if ACode.StartsWith(':') then
    Text := StringReplace(UnitHaupt, '  L: { Typ };', '  L' + ACode, [])
  else
    Text := StringReplace(StringReplace(UnitHaupt, '  L: { Typ };'#10, '', []), '  { Code }', ACode, []);
  Text := Split(Text, Position);
  Tree := TPascalParser.Parse(Text);
  Request := TCompletionRequest.Create(Text, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitListen;
        Result := SameText(AFileName, ListenFile);
      end;
    Result := TLspCompletion.Collect(Request, Default(TPostfixOptions), nil);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionGenericsTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if SameText(Item.Name, AName) then
    begin
      AItem := Item;
      Exit(True);
    end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function TCompletionGenericsTests.Has(const AItems: TCompletionItems; const AName: string): Boolean;
var
  Item: TCompletionItem;
begin
  Result := Find(AItems, AName, Item);
end;

procedure TCompletionGenericsTests.FindsOpenAngleBracket;

  function SiteOf(const AMarked: string; out ASite: TGenericArgSite): Boolean;
  var
    Position: TTextPosition;
    Tokens: TArray<TPascalToken>;
    Index, Last: Integer;
  begin
    Tokens := TPascalLexer.Tokenize(Split(AMarked, Position));
    Last := -1;
    for Index := 0 to High(Tokens) do
      if (Tokens[Index].StartPos.Line < Position.Line) or (Tokens[Index].StartPos.Line = Position.Line) and
        (Tokens[Index].EndPos.Character <= Position.Character) then
        Last := Index;
    ASite := TCompletionGenerics.SiteAt(Tokens, Last);
    Result := ASite.Found;
  end;

var
  Site: TGenericArgSite;
begin
  Assert.IsTrue(SiteOf('L: TObjektListe<|', Site));
  Assert.AreEqual(0, Site.Parameter);
  Assert.AreEqual(3, Site.OwnerPosition.Character);
  Assert.IsTrue(SiteOf('D: TDictionary<string, |', Site));
  Assert.AreEqual(1, Site.Parameter);
  Assert.IsTrue(SiteOf('D: TDictionary<TList<Integer>, |', Site), 'verschachtelt');
  Assert.AreEqual(1, Site.Parameter);
  Assert.AreEqual(3, Site.OwnerPosition.Character);
  Assert.IsTrue(SiteOf('D: TDictionary<string, TList<|', Site), 'innere Liste');
  Assert.AreEqual(0, Site.Parameter);
  Assert.AreEqual(23, Site.OwnerPosition.Character);
  Assert.IsFalse(SiteOf('if (A + 1) < |', Site), 'Vergleich nach Klammer');
  Assert.IsFalse(SiteOf('X := Foo(1, |', Site), 'Aufruf');
end;

procedure TCompletionGenericsTests.ReadsParametersWithConstraints;
var
  Params: TArray<TGenericParam>;
begin
  Params := TCompletionGenerics.Params(['  TPaar<K; V: class, constructor> = class'], 0, 2);
  Assert.AreEqual(2, Integer(Length(Params)));
  Assert.AreEqual('K', Params[0].Name);
  Assert.AreEqual(0, Integer(Length(Params[0].Constraints)));
  Assert.AreEqual('V', Params[1].Name);
  Assert.AreEqual('class|constructor', string.Join('|', Params[1].Constraints));
  Params := TCompletionGenerics.Params(['  TDictionary<TKey,', '    TValue> = class'], 0, 2);
  Assert.AreEqual(2, Integer(Length(Params)), 'über zwei Zeilen');
  Assert.AreEqual('TValue', Params[1].Name);
  Params := TCompletionGenerics.Params(['  TKunde = class'], 0, 2);
  Assert.AreEqual(0, Integer(Length(Params)), 'nicht generisch');
end;

procedure TCompletionGenericsTests.HintCodesFollowConstraints;
var
  Never: TFunc<string, Boolean>;
  Always: TFunc<Boolean>;
begin
  Assert.AreEqual('classes', TCompletionGenerics.HintCode(['class'], False));
  Assert.AreEqual('values', TCompletionGenerics.HintCode(['record'], False));
  Assert.AreEqual('constructible', TCompletionGenerics.HintCode(['class', 'constructor'], False));
  Assert.AreEqual('implements:IVergleich', TCompletionGenerics.HintCode(['IVergleich'], True));
  Assert.AreEqual('descends:TBasis', TCompletionGenerics.HintCode(['TBasis'], False));
  Assert.AreEqual('', TCompletionGenerics.HintCode(nil, False));
  Never :=
    function(AName: string): Boolean
    begin
      Result := False;
    end;
  Always :=
    function: Boolean
    begin
      Result := True;
    end;
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Class_, ['class'], Never, Always));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Record_, ['class'], Never, Always));
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Basic, ['record'], Never, Always));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Interface_, ['record'], Never, Always));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Class_, ['IVergleich'], Never, Always));
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Record_, nil, Never, Always));
end;

procedure TCompletionGenericsTests.ClassConstraintKeepsClassesOnly;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(': TObjektListe<T|');
  Assert.IsTrue(Find(Items, 'TKunde', Item), 'Klasse');
  Assert.AreEqual('T', Item.TypeParam);
  Assert.AreEqual('class', Item.Constraint);
  Assert.AreEqual('classes', Item.ConstraintHint);
  Assert.IsTrue(Item.HiddenKinds.Contains('records'), Item.HiddenKinds);
  Assert.IsTrue(Item.HiddenKinds.Contains('enums'), Item.HiddenKinds);
  Assert.IsFalse(Item.HiddenKinds.Contains('classes'), Item.HiddenKinds);
  Assert.IsFalse(Has(Items, 'TPunkt'), 'Record');
  Assert.IsFalse(Has(Items, 'TFarbe'), 'Aufzählung');
  Assert.IsFalse(Has(Items, 'TDateTime'), 'Grundtyp');
  // Auch mit "<>" dahinter, das der Lexer als ein Token liest.
  Items := ItemsAt(': TObjektListe<|>;');
  Assert.IsTrue(Find(Items, 'TKunde', Item), 'vor >');
  Assert.AreEqual('T', Item.TypeParam);
  Assert.IsFalse(Has(Items, 'IVergleich'), 'Interface vor >');
end;

procedure TCompletionGenericsTests.RecordConstraintKeepsValueTypes;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(': TWerte<|');
  Assert.IsTrue(Find(Items, 'TPunkt', Item), 'Record');
  Assert.AreEqual('values', Item.ConstraintHint);
  Assert.IsTrue(Has(Items, 'TFarbe'), 'Aufzählung');
  Assert.IsTrue(Has(Items, 'Integer'), 'Grundtyp');
  Assert.IsFalse(Has(Items, 'TKunde'), 'Klasse');
  Assert.IsFalse(Has(Items, 'string'), 'string ist kein Werttyp');
  Assert.IsTrue(Item.HiddenKinds.Contains('classes'), Item.HiddenKinds);
end;

procedure TCompletionGenericsTests.ConstructorConstraintNeedsParameterlessCreate;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(': TFabrik<T|');
  Assert.IsTrue(Find(Items, 'TKunde', Item), 'ohne eigenen Konstruktor');
  Assert.AreEqual('constructible', Item.ConstraintHint);
  Assert.AreEqual('class, constructor', Item.Constraint);
  Assert.IsFalse(Has(Items, 'TOhneStandard'), 'Create mit Parameter');
end;

procedure TCompletionGenericsTests.InterfaceConstraintKeepsImplementers;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(': TSortierer<|');
  Assert.IsTrue(Find(Items, 'TVergleicher', Item), 'über IVergleichEx');
  Assert.AreEqual('implements:IVergleich', Item.ConstraintHint);
  Assert.IsTrue(Has(Items, 'IVergleich'), 'das Interface selbst');
  Assert.IsTrue(Has(Items, 'IVergleichEx'), 'abgeleitetes Interface');
  Assert.IsFalse(Has(Items, 'TKunde'), 'Klasse ohne Interface');
  Assert.IsFalse(Has(Items, 'TPunkt'), 'Record');
end;

procedure TCompletionGenericsTests.SecondParameterUsesItsConstraint;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt(': TPaar<TPunkt, T|');
  Assert.IsTrue(Find(Items, 'TKunde', Item));
  Assert.AreEqual('V', Item.TypeParam);
  Assert.IsFalse(Has(Items, 'TPunkt'), 'V: class');
  Items := ItemsAt(': TPaar<T|');
  Assert.IsTrue(Find(Items, 'TPunkt', Item), 'K ohne Constraint');
  Assert.AreEqual('K', Item.TypeParam);
end;

procedure TCompletionGenericsTests.WithoutConstraintAllTypesAndBasicTypes;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Json: TJSONArray;
  Data: TJSONObject;
begin
  Items := ItemsAt(': TBeliebig<|');
  Assert.IsTrue(Find(Items, 'TKunde', Item));
  Assert.AreEqual('T', Item.TypeParam);
  Assert.AreEqual('', Item.Constraint);
  Assert.AreEqual('', Item.ConstraintHint);
  Assert.AreEqual('', Item.HiddenKinds);
  Assert.IsTrue(Has(Items, 'TPunkt'));
  Assert.IsTrue(Has(Items, 'IVergleich'));
  Assert.IsTrue(Has(Items, 'string'));
  Assert.IsTrue(Has(Items, 'Integer'));
  Assert.IsFalse(Has(Items, 'Zahl'), 'keine Variablen');
  Assert.IsFalse(Has(Items, 'Rot'), 'keine Werte');
  // Im JSON unter data.typeParam.
  Json := CompletionItemsToJson([Item], 0);
  try
    Data := (Json.Items[0] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('T', Data.GetValue('typeParam').Value);
  finally
    Json.Free;
  end;
end;

procedure TCompletionGenericsTests.ComparisonStaysNormalCompletion;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('  if Zahl < Z|');
  Assert.IsTrue(Find(Items, 'Zahl', Item), 'Variable im Vergleich');
  Assert.AreEqual('', Item.TypeParam);
end;

procedure TCompletionGenericsTests.MembersShowBoundTypes;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('  Kunden.Ers|');
  Assert.IsTrue(Find(Items, 'Erster', Item));
  Assert.AreEqual('TKunde', Item.Detail, 'T eingesetzt');
  Assert.AreEqual('T=TKunde', string.Join('|', Item.Bindings));
end;

procedure TCompletionGenericsTests.SignatureShowsBoundTypes;
var
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Help: TSignatureHelp;
begin
  Text := Split(StringReplace(StringReplace(UnitHaupt, '  L: { Typ };'#10, '', []), '  { Code }',
    '  Kunden.Add(|);', []), Position);
  Tree := TPascalParser.Parse(Text);
  try
    Help := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, Position,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := UnitListen;
        Result := SameText(AFileName, ListenFile);
      end);
  finally
    Tree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.IsTrue(Help.Signatures[0].Text.Contains('Wert: TKunde'), Help.Signatures[0].Text);
  Assert.AreEqual('TKunde', Help.Signatures[0].Parameters[0].TypeName);
end;

end.
