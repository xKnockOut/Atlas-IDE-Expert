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
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
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
  cHauptFile = 'C:\P\Haupt.pas';
  cListenFile = 'C:\P\Listen.pas';

  cUnitListen =
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

  cUnitHaupt =
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
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  APosition := TTextPosition.Create(mLine, mCharacter);
  Result := StringReplace(AMarked, '|', '', []);
end;

{ TCompletionGenericsTests }

procedure TCompletionGenericsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitListen, cListenFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionGenericsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionGenericsTests.ItemsAt(const ACode: string): TCompletionItems;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  // ACode steht im var-Abschnitt (Typ) oder im Rumpf (Code), je nachdem, ob es mit ":" beginnt.
  if ACode.StartsWith(':') then
  begin
    mText := StringReplace(cUnitHaupt, '  L: { Typ };', '  L' + ACode, []);
  end
  else
  begin
    mText := StringReplace(StringReplace(cUnitHaupt, '  L: { Typ };'#10, '', []), '  { Code }', ACode, []);
  end;
  mText := Split(mText, mPosition);
  mTree := TPascalParser.Parse(mText);
  mRequest := TCompletionRequest.Create(mText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.ReadText :=
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitListen;
        Result := SameText(AFileName, cListenFile);
      end;
    Result := TCompletionLists.Collect(mRequest, Default(TPostfixOptions), nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TCompletionGenericsTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if SameText(mItem.Name, AName) then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

function TCompletionGenericsTests.Has(const AItems: TCompletionItems; const AName: string): Boolean;
var
  mItem: TCompletionItem;
begin
  Result := Find(AItems, AName, mItem);
end;

procedure TCompletionGenericsTests.FindsOpenAngleBracket;

  function SiteOf(const AMarked: string; out ASite: TGenericArgSite): Boolean;
  var
    mPosition: TTextPosition;
    mTokens: TArray<TPascalToken>;
    mIndex, mLast: Integer;
  begin
    mTokens := TPascalLexer.Tokenize(Split(AMarked, mPosition));
    mLast := -1;
    for mIndex := 0 to High(mTokens) do
    begin
      if (mTokens[mIndex].StartPos.Line < mPosition.Line) or (mTokens[mIndex].StartPos.Line = mPosition.Line) and
        (mTokens[mIndex].EndPos.Character <= mPosition.Character) then
      begin
        mLast := mIndex;
      end;
    end;
    ASite := TCompletionGenerics.SiteAt(mTokens, mLast);
    Result := ASite.Found;
  end;

var
  mSite: TGenericArgSite;
begin
  Assert.IsTrue(SiteOf('L: TObjektListe<|', mSite));
  Assert.AreEqual(0, mSite.Parameter);
  Assert.AreEqual(3, mSite.OwnerPosition.Character);
  Assert.IsTrue(SiteOf('D: TDictionary<string, |', mSite));
  Assert.AreEqual(1, mSite.Parameter);
  Assert.IsTrue(SiteOf('D: TDictionary<TList<Integer>, |', mSite), 'verschachtelt');
  Assert.AreEqual(1, mSite.Parameter);
  Assert.AreEqual(3, mSite.OwnerPosition.Character);
  Assert.IsTrue(SiteOf('D: TDictionary<string, TList<|', mSite), 'innere Liste');
  Assert.AreEqual(0, mSite.Parameter);
  Assert.AreEqual(23, mSite.OwnerPosition.Character);
  Assert.IsFalse(SiteOf('if (A + 1) < |', mSite), 'Vergleich nach Klammer');
  Assert.IsFalse(SiteOf('X := Foo(1, |', mSite), 'Aufruf');
end;

procedure TCompletionGenericsTests.ReadsParametersWithConstraints;
var
  mParams: TArray<TGenericParam>;
begin
  mParams := TCompletionGenerics.Params(['  TPaar<K; V: class, constructor> = class'], 0, 2);
  Assert.AreEqual(2, Integer(Length(mParams)));
  Assert.AreEqual('K', mParams[0].Name);
  Assert.AreEqual(0, Integer(Length(mParams[0].Constraints)));
  Assert.AreEqual('V', mParams[1].Name);
  Assert.AreEqual('class|constructor', string.Join('|', mParams[1].Constraints));
  mParams := TCompletionGenerics.Params(['  TDictionary<TKey,', '    TValue> = class'], 0, 2);
  Assert.AreEqual(2, Integer(Length(mParams)), 'über zwei Zeilen');
  Assert.AreEqual('TValue', mParams[1].Name);
  mParams := TCompletionGenerics.Params(['  TKunde = class'], 0, 2);
  Assert.AreEqual(0, Integer(Length(mParams)), 'nicht generisch');
end;

procedure TCompletionGenericsTests.HintCodesFollowConstraints;
var
  mNever: TFunc<string, Boolean>;
  mAlways: TFunc<Boolean>;
begin
  Assert.AreEqual('classes', TCompletionGenerics.HintCode(['class'], False));
  Assert.AreEqual('values', TCompletionGenerics.HintCode(['record'], False));
  Assert.AreEqual('constructible', TCompletionGenerics.HintCode(['class', 'constructor'], False));
  Assert.AreEqual('implements:IVergleich', TCompletionGenerics.HintCode(['IVergleich'], True));
  Assert.AreEqual('descends:TBasis', TCompletionGenerics.HintCode(['TBasis'], False));
  Assert.AreEqual('', TCompletionGenerics.HintCode(nil, False));
  mNever :=
    function(AName: string): Boolean
    begin
      Result := False;
    end;
  mAlways :=
    function: Boolean
    begin
      Result := True;
    end;
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Class_, ['class'], mNever, mAlways));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Record_, ['class'], mNever, mAlways));
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Basic, ['record'], mNever, mAlways));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Interface_, ['record'], mNever, mAlways));
  Assert.IsFalse(TCompletionGenerics.Allowed(TTypeArgKind.Class_, ['IVergleich'], mNever, mAlways));
  Assert.IsTrue(TCompletionGenerics.Allowed(TTypeArgKind.Record_, nil, mNever, mAlways));
end;

procedure TCompletionGenericsTests.ClassConstraintKeepsClassesOnly;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(': TObjektListe<T|');
  Assert.IsTrue(Find(mItems, 'TKunde', mItem), 'Klasse');
  Assert.AreEqual('T', mItem.TypeParam);
  Assert.AreEqual('class', mItem.Constraint);
  Assert.AreEqual('classes', mItem.ConstraintHint);
  Assert.IsTrue(mItem.HiddenKinds.Contains('records'), mItem.HiddenKinds);
  Assert.IsTrue(mItem.HiddenKinds.Contains('enums'), mItem.HiddenKinds);
  Assert.IsFalse(mItem.HiddenKinds.Contains('classes'), mItem.HiddenKinds);
  Assert.IsFalse(Has(mItems, 'TPunkt'), 'Record');
  Assert.IsFalse(Has(mItems, 'TFarbe'), 'Aufzählung');
  Assert.IsFalse(Has(mItems, 'TDateTime'), 'Grundtyp');
  // Auch mit "<>" dahinter, das der Lexer als ein Token liest.
  mItems := ItemsAt(': TObjektListe<|>;');
  Assert.IsTrue(Find(mItems, 'TKunde', mItem), 'vor >');
  Assert.AreEqual('T', mItem.TypeParam);
  Assert.IsFalse(Has(mItems, 'IVergleich'), 'Interface vor >');
end;

procedure TCompletionGenericsTests.RecordConstraintKeepsValueTypes;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(': TWerte<|');
  Assert.IsTrue(Find(mItems, 'TPunkt', mItem), 'Record');
  Assert.AreEqual('values', mItem.ConstraintHint);
  Assert.IsTrue(Has(mItems, 'TFarbe'), 'Aufzählung');
  Assert.IsTrue(Has(mItems, 'Integer'), 'Grundtyp');
  Assert.IsFalse(Has(mItems, 'TKunde'), 'Klasse');
  Assert.IsFalse(Has(mItems, 'string'), 'string ist kein Werttyp');
  Assert.IsTrue(mItem.HiddenKinds.Contains('classes'), mItem.HiddenKinds);
end;

procedure TCompletionGenericsTests.ConstructorConstraintNeedsParameterlessCreate;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(': TFabrik<T|');
  Assert.IsTrue(Find(mItems, 'TKunde', mItem), 'ohne eigenen Konstruktor');
  Assert.AreEqual('constructible', mItem.ConstraintHint);
  Assert.AreEqual('class, constructor', mItem.Constraint);
  Assert.IsFalse(Has(mItems, 'TOhneStandard'), 'Create mit Parameter');
end;

procedure TCompletionGenericsTests.InterfaceConstraintKeepsImplementers;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(': TSortierer<|');
  Assert.IsTrue(Find(mItems, 'TVergleicher', mItem), 'über IVergleichEx');
  Assert.AreEqual('implements:IVergleich', mItem.ConstraintHint);
  Assert.IsTrue(Has(mItems, 'IVergleich'), 'das Interface selbst');
  Assert.IsTrue(Has(mItems, 'IVergleichEx'), 'abgeleitetes Interface');
  Assert.IsFalse(Has(mItems, 'TKunde'), 'Klasse ohne Interface');
  Assert.IsFalse(Has(mItems, 'TPunkt'), 'Record');
end;

procedure TCompletionGenericsTests.SecondParameterUsesItsConstraint;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt(': TPaar<TPunkt, T|');
  Assert.IsTrue(Find(mItems, 'TKunde', mItem));
  Assert.AreEqual('V', mItem.TypeParam);
  Assert.IsFalse(Has(mItems, 'TPunkt'), 'V: class');
  mItems := ItemsAt(': TPaar<T|');
  Assert.IsTrue(Find(mItems, 'TPunkt', mItem), 'K ohne Constraint');
  Assert.AreEqual('K', mItem.TypeParam);
end;

procedure TCompletionGenericsTests.WithoutConstraintAllTypesAndBasicTypes;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mJson: TJSONArray;
  mData: TJSONObject;
begin
  mItems := ItemsAt(': TBeliebig<|');
  Assert.IsTrue(Find(mItems, 'TKunde', mItem));
  Assert.AreEqual('T', mItem.TypeParam);
  Assert.AreEqual('', mItem.Constraint);
  Assert.AreEqual('', mItem.ConstraintHint);
  Assert.AreEqual('', mItem.HiddenKinds);
  Assert.IsTrue(Has(mItems, 'TPunkt'));
  Assert.IsTrue(Has(mItems, 'IVergleich'));
  Assert.IsTrue(Has(mItems, 'string'));
  Assert.IsTrue(Has(mItems, 'Integer'));
  Assert.IsFalse(Has(mItems, 'Zahl'), 'keine Variablen');
  Assert.IsFalse(Has(mItems, 'Rot'), 'keine Werte');
  // Im JSON unter data.typeParam.
  mJson := CompletionItemsToJson([mItem], 0);
  try
    mData := (mJson.Items[0] as TJSONObject).GetValue('data') as TJSONObject;
    Assert.AreEqual('T', mData.GetValue('typeParam').Value);
  finally
    mJson.Free;
  end;
end;

procedure TCompletionGenericsTests.ComparisonStaysNormalCompletion;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('  if Zahl < Z|');
  Assert.IsTrue(Find(mItems, 'Zahl', mItem), 'Variable im Vergleich');
  Assert.AreEqual('', mItem.TypeParam);
end;

procedure TCompletionGenericsTests.MembersShowBoundTypes;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('  Kunden.Ers|');
  Assert.IsTrue(Find(mItems, 'Erster', mItem));
  Assert.AreEqual('TKunde', mItem.Detail, 'T eingesetzt');
  Assert.AreEqual('T=TKunde', string.Join('|', mItem.Bindings));
end;

procedure TCompletionGenericsTests.SignatureShowsBoundTypes;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mHelp: TSignatureHelp;
begin
  mText := Split(StringReplace(StringReplace(cUnitHaupt, '  L: { Typ };'#10, '', []), '  { Code }',
    '  Kunden.Add(|);', []), mPosition);
  mTree := TPascalParser.Parse(mText);
  try
    mHelp := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile,
      function(const AFileName: string; out AText: string): Boolean
      begin
        AText := cUnitListen;
        Result := SameText(AFileName, cListenFile);
      end), mPosition);
  finally
    mTree.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
  Assert.IsTrue(mHelp.Signatures[0].Text.Contains('Wert: TKunde'), mHelp.Signatures[0].Text);
  Assert.AreEqual('TKunde', mHelp.Signatures[0].Parameters[0].TypeName);
end;

end.
