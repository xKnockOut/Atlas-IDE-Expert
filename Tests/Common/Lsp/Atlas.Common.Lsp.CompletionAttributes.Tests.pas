unit Atlas.Common.Lsp.CompletionAttributes.Tests;

// Attribute nach "[" (#465): Stelle, nur Attributklassen ohne Endung, bekannte zuerst, uses-Eintrag über die
// Fassade, Konstruktor im Parameter-Hint und der Schalter completion.attributes.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

type
  [TestFixture]
  TCompletionAttributesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function ItemsAt(const AMarked: string; const ASettings: TCompletionSettings): TCompletionItems; overload;
    function ItemsAt(const AMarked: string): TCompletionItems; overload;
    function Names(const AItems: TCompletionItems): string;
    function Find(const AItems: TCompletionItems; const AName: string; out AItem: TCompletionItem): Boolean;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsAttributeBrackets;
    [Test]
    procedure ShortNamesFromFacade;
    [Test]
    procedure KnownFirstWithoutPrefix;
    [Test]
    procedure DetailShowsConstructor;
    [Test]
    procedure AfterCommaAndInParameters;
    [Test]
    procedure SetsAndIndexesStayNormal;
    [Test]
    procedure SwitchOff;
    [Test]
    procedure ParameterText;
    [Test]
    procedure SignatureShowsConstructor;
  end;

implementation

uses
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.CompletionAttributes,
  Atlas.Common.Lsp.SignatureHelp;

const
  cHauptFile = 'C:\P\Haupt.pas';
  cAttributesFile = 'C:\P\DUnitX.Attributes.pas';
  cFrameworkFile = 'C:\P\DUnitX.TestFramework.pas';

  cUnitAttributes =
    'unit DUnitX.Attributes;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TestAttribute = class(TCustomAttribute)'#10 +
    '  public'#10 +
    '    constructor Create; overload;'#10 +
    '    constructor Create(const AEnabled: Boolean); overload;'#10 +
    '  end;'#10 +
    '  TestCaseAttribute = class(TCustomAttribute)'#10 +
    '  public'#10 +
    '    constructor Create(const ACaseName: string; const AValues: string);'#10 +
    '  end;'#10 +
    '  TearDownAttribute = class(TCustomAttribute)'#10 +
    '  end;'#10 +
    '  TestHelper = class'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TestAttribute.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    'constructor TestAttribute.Create(const AEnabled: Boolean);'#10 +
    'begin'#10 +
    'end;'#10 +
    'constructor TestCaseAttribute.Create(const ACaseName: string; const AValues: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  cUnitFramework =
    'unit DUnitX.TestFramework;'#10 +
    'interface'#10 +
    'uses DUnitX.Attributes;'#10 +
    'type'#10 +
    '  TestAttribute = DUnitX.Attributes.TestAttribute;'#10 +
    '  TestCaseAttribute = DUnitX.Attributes.TestCaseAttribute;'#10 +
    '  TearDownAttribute = DUnitX.Attributes.TearDownAttribute;'#10 +
    'implementation'#10 +
    'end.';

  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    '{ Uses }'#10 +
    'type'#10 +
    '  MarkeAttribute = class(TCustomAttribute)'#10 +
    '  public'#10 +
    '    constructor Create(const AText: string);'#10 +
    '  end;'#10 +
    '  TKunde = class'#10 +
    '  end;'#10 +
    '  TTests = class'#10 +
    '  public'#10 +
    '    { Attr }'#10 +
    '    procedure Pruefe;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor MarkeAttribute.Create(const AText: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TTests.Pruefe;'#10 +
    'var'#10 +
    '  A: array of Integer;'#10 +
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

/// <summary>AMarked ersetzt "{ Attr }" (beginnt es mit "C:", "{ Code }"; mit "U:" kommt "uses DUnitX.TestFramework;"
/// dazu).</summary>
function Source(const AMarked: string): string;
var
  mText, mMarked: string;
begin
  mText := cUnitHaupt;
  mMarked := AMarked;
  if mMarked.StartsWith('U:') then
  begin
    mText := StringReplace(mText, '{ Uses }', 'uses DUnitX.TestFramework;', []);
    mMarked := Copy(mMarked, 3, MaxInt);
  end;
  if mMarked.StartsWith('C:') then
  begin
    Result := StringReplace(mText, '{ Code }', Copy(mMarked, 3, MaxInt), []);
  end
  else
  begin
    Result := StringReplace(mText, '{ Attr }', mMarked, []);
  end;
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, cAttributesFile) then
  begin
    AText := cUnitAttributes;
  end
  else if SameText(AFileName, cFrameworkFile) then
  begin
    AText := cUnitFramework;
  end
  else
  begin
    Result := False;
  end;
end;

{ TCompletionAttributesTests }

procedure TCompletionAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitAttributes, cAttributesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitFramework, cFrameworkFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TCompletionAttributesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TCompletionAttributesTests.ItemsAt(const AMarked: string;
  const ASettings: TCompletionSettings): TCompletionItems;
var
  mText: string;
  mPosition: TTextPosition;
  mTree: TSyntaxTree;
  mRequest: TCompletionRequest;
begin
  mText := Split(Source(AMarked), mPosition);
  mTree := TPascalParser.Parse(mText);
  mRequest := TCompletionRequest.Create(mText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := FResolver;
    mRequest.Index := FIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    mRequest.ReadText := ReadText;
    Result := TCompletionLists.Collect(mRequest, Default(TPostfixOptions), nil);
  finally
    mRequest.Free;
    mTree.Free;
  end;
end;

function TCompletionAttributesTests.ItemsAt(const AMarked: string): TCompletionItems;
begin
  Result := ItemsAt(AMarked, TCompletionSettings.Default);
end;

function TCompletionAttributesTests.Names(const AItems: TCompletionItems): string;
var
  mItem: TCompletionItem;
begin
  Result := '';
  for mItem in AItems.Items do
  begin
    Result := Result + mItem.Name + ' ';
  end;
  Result := TrimRight(Result);
end;

function TCompletionAttributesTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  mItem: TCompletionItem;
begin
  for mItem in AItems.Items do
  begin
    if mItem.Name = AName then
    begin
      AItem := mItem;
      Exit(True);
    end;
  end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

procedure TCompletionAttributesTests.FindsAttributeBrackets;

  function InBracket(const AMarked: string): Boolean;
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
    Result := TCompletionAttributes.SiteAt(mTokens, mLast);
  end;

begin
  Assert.IsTrue(InBracket('type'#10'  [|'), 'nach type');
  Assert.IsTrue(InBracket('  TFoo = class'#10'    [|'), 'Klassenrumpf');
  Assert.IsTrue(InBracket('  TFoo = class(TBasis)'#10'    [|'), 'nach Vorfahren');
  Assert.IsTrue(InBracket('  public'#10'    [|'), 'nach Sichtbarkeit');
  Assert.IsTrue(InBracket('    procedure A;'#10'    [|'), 'nach Methode');
  Assert.IsTrue(InBracket('    [Test]'#10'    [|'), 'zweites Attribut');
  Assert.IsTrue(InBracket('    [Test, |'), 'nach Komma');
  Assert.IsTrue(InBracket('    [TestCase(''a'', ''1''), |'), 'nach Attribut mit Argumenten');
  Assert.IsTrue(InBracket('  procedure Foo([|'), 'Parameter');
  Assert.IsTrue(InBracket('  procedure Foo(A: Integer; [|'), 'zweiter Parameter');
  Assert.IsFalse(InBracket('  X := [|'), 'Menge');
  Assert.IsFalse(InBracket('  if A in [|'), 'in');
  Assert.IsFalse(InBracket('  X := A[|'), 'Index');
  Assert.IsFalse(InBracket('  X := A[1][|'), 'zweiter Index');
  Assert.IsFalse(InBracket('  Foo([|'), 'offenes Array im Aufruf');
  Assert.IsFalse(InBracket('  IFoo = interface'#10'    [|'), 'GUID');
  Assert.IsFalse(InBracket('  IFoo = interface(IBasis)'#10'    [|'), 'GUID nach Vorfahr');
  Assert.IsFalse(InBracket('    [TestCase(|'), 'Argumente');
  Assert.IsFalse(InBracket('    [TestCase(''a'', |'), 'zweites Argument');
end;

procedure TCompletionAttributesTests.ShortNamesFromFacade;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mCount: Integer;
begin
  mItems := ItemsAt('[Te|');
  Assert.AreEqual('Test TestCase TearDown', Names(mItems));
  Assert.IsTrue(Find(mItems, 'Test', mItem));
  Assert.IsTrue(mItem.Attribute);
  Assert.AreEqual('Test', mItem.InsertText);
  // Der Alias der Fassade geht dem Original vor.
  mCount := Length(mItem.AdditionalEdits);
  Assert.AreEqual(1, mCount);
  Assert.IsTrue(mItem.AdditionalEdits[0].NewText.Contains('DUnitX.TestFramework'), mItem.AdditionalEdits[0].NewText);
  // Eingebunden: ohne uses-Eintrag.
  mItems := ItemsAt('U:[Te|');
  Assert.AreEqual('Test TestCase TearDown', Names(mItems));
  Assert.IsTrue(Find(mItems, 'TestCase', mItem));
  Assert.AreEqual(0, Integer(Length(mItem.AdditionalEdits)));
end;

procedure TCompletionAttributesTests.KnownFirstWithoutPrefix;
begin
  // Ohne Eingabe: bekannte (mit uses-Eintrag), Compiler-Attribute, dann die eigenen; keine anderen Klassen.
  Assert.AreEqual('Test TestCase TearDown weak unsafe volatile Ref Marke', Names(ItemsAt('[|')));
end;

procedure TCompletionAttributesTests.DetailShowsConstructor;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('U:[|');
  Assert.IsTrue(Find(mItems, 'TestCase', mItem));
  Assert.AreEqual('(const ACaseName: string; const AValues: string)', mItem.Detail);
  Assert.IsTrue(Find(mItems, 'TearDown', mItem));
  Assert.AreEqual('DUnitX.Attributes', mItem.Detail, 'ohne Konstruktor die Unit');
  Assert.IsTrue(Find(mItems, 'Marke', mItem));
  Assert.AreEqual('(const AText: string)', mItem.Detail);
  Assert.IsTrue(Find(mItems, 'weak', mItem));
  Assert.AreEqual('Compiler', mItem.Detail);
  Assert.IsTrue(mItem.Attribute);
end;

procedure TCompletionAttributesTests.AfterCommaAndInParameters;
begin
  Assert.AreEqual('Test TestCase TearDown', Names(ItemsAt('U:[Marke(''x''), Te|')));
  Assert.AreEqual('Marke', Names(ItemsAt('procedure Lies([Ma|')));
end;

procedure TCompletionAttributesTests.SetsAndIndexesStayNormal;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mItems := ItemsAt('C:A := [A|');
  Assert.IsTrue(Find(mItems, 'A', mItem), Names(mItems));
  Assert.IsFalse(mItem.Attribute);
  mItems := ItemsAt('C:A[Le|');
  Assert.IsFalse(Find(mItems, 'Test', mItem));
end;

procedure TCompletionAttributesTests.SwitchOff;
var
  mSettings: TCompletionSettings;
  mItems: TCompletionItems;
  mItem: TCompletionItem;
begin
  mSettings := TCompletionSettings.Default;
  mSettings.Attributes := False;
  mItems := ItemsAt('[Ma|', mSettings);
  Assert.IsTrue(Find(mItems, 'MarkeAttribute', mItem), Names(mItems));
  Assert.IsFalse(mItem.Attribute);
  Assert.IsFalse(Find(mItems, 'Marke', mItem));
end;

procedure TCompletionAttributesTests.ParameterText;
begin
  Assert.AreEqual('(const A: string)', TCompletionAttributes.ParameterText('constructor Create(const A: string);'));
  Assert.AreEqual('(A: TArray<string>; B: TFunc<Integer>)',
    TCompletionAttributes.ParameterText('constructor Create(A: TArray<string>; B: TFunc<Integer>)'));
  Assert.AreEqual('', TCompletionAttributes.ParameterText('constructor Create;'));
end;

procedure TCompletionAttributesTests.SignatureShowsConstructor;

  function HelpAt(const AMarked: string): TSignatureHelp;
  var
    mText: string;
    mPosition: TTextPosition;
    mTree: TSyntaxTree;
  begin
    mText := Split(Source(AMarked), mPosition);
    mTree := TPascalParser.Parse(mText);
    try
      Result := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, mText, cHauptFile,
        ReadText), mPosition);
    finally
      mTree.Free;
    end;
  end;

var
  mHelp: TSignatureHelp;
begin
  mHelp := HelpAt('[Marke(|');
  Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
  Assert.IsTrue(mHelp.Signatures[0].Text.Contains('const AText: string'), mHelp.Signatures[0].Text);
  mHelp := HelpAt('U:[TestCase(''Name'', |');
  Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
  Assert.IsTrue(mHelp.Signatures[0].Text.Contains('ACaseName'), mHelp.Signatures[0].Text);
  Assert.AreEqual(1, mHelp.ActiveParameter);
  mHelp := HelpAt('U:[Test(|');
  Assert.AreEqual(2, Integer(Length(mHelp.Signatures)), 'beide Konstruktoren');
end;

end.
