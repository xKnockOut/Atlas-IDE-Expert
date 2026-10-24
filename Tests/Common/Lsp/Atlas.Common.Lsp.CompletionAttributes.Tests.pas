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
  HauptFile = 'C:\P\Haupt.pas';
  AttributesFile = 'C:\P\DUnitX.Attributes.pas';
  FrameworkFile = 'C:\P\DUnitX.TestFramework.pas';

  UnitAttributes =
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

  UnitFramework =
    'unit DUnitX.TestFramework;'#10 +
    'interface'#10 +
    'uses DUnitX.Attributes;'#10 +
    'type'#10 +
    '  TestAttribute = DUnitX.Attributes.TestAttribute;'#10 +
    '  TestCaseAttribute = DUnitX.Attributes.TestCaseAttribute;'#10 +
    '  TearDownAttribute = DUnitX.Attributes.TearDownAttribute;'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
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

/// <summary>AMarked ersetzt "{ Attr }" (beginnt es mit "C:", "{ Code }"; mit "U:" kommt "uses DUnitX.TestFramework;"
/// dazu).</summary>
function Source(const AMarked: string): string;
var
  Text, Marked: string;
begin
  Text := UnitHaupt;
  Marked := AMarked;
  if Marked.StartsWith('U:') then
  begin
    Text := StringReplace(Text, '{ Uses }', 'uses DUnitX.TestFramework;', []);
    Marked := Copy(Marked, 3, MaxInt);
  end;
  if Marked.StartsWith('C:') then
    Result := StringReplace(Text, '{ Code }', Copy(Marked, 3, MaxInt), [])
  else
    Result := StringReplace(Text, '{ Attr }', Marked, []);
end;

function ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := True;
  if SameText(AFileName, AttributesFile) then
    AText := UnitAttributes
  else if SameText(AFileName, FrameworkFile) then
    AText := UnitFramework
  else
    Result := False;
end;

{ TCompletionAttributesTests }

procedure TCompletionAttributesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitAttributes, AttributesFile, nil));
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitFramework, FrameworkFile, nil));
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
  Text: string;
  Position: TTextPosition;
  Tree: TSyntaxTree;
  Request: TCompletionRequest;
begin
  Text := Split(Source(AMarked), Position);
  Tree := TPascalParser.Parse(Text);
  Request := TCompletionRequest.Create(Text, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := FResolver;
    Request.Index := FIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Request.ReadText := ReadText;
    Result := TLspCompletion.Collect(Request, Default(TPostfixOptions), nil);
  finally
    Request.Free;
    Tree.Free;
  end;
end;

function TCompletionAttributesTests.ItemsAt(const AMarked: string): TCompletionItems;
begin
  Result := ItemsAt(AMarked, TCompletionSettings.Default);
end;

function TCompletionAttributesTests.Names(const AItems: TCompletionItems): string;
var
  Item: TCompletionItem;
begin
  Result := '';
  for Item in AItems.Items do
    Result := Result + Item.Name + ' ';
  Result := TrimRight(Result);
end;

function TCompletionAttributesTests.Find(const AItems: TCompletionItems; const AName: string;
  out AItem: TCompletionItem): Boolean;
var
  Item: TCompletionItem;
begin
  for Item in AItems.Items do
    if Item.Name = AName then
    begin
      AItem := Item;
      Exit(True);
    end;
  AItem := Default(TCompletionItem);
  Result := False;
end;

procedure TCompletionAttributesTests.FindsAttributeBrackets;

  function InBracket(const AMarked: string): Boolean;
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
    Result := TCompletionAttributes.SiteAt(Tokens, Last);
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
  Items: TCompletionItems;
  Item: TCompletionItem;
  Count: Integer;
begin
  Items := ItemsAt('[Te|');
  Assert.AreEqual('Test TestCase TearDown', Names(Items));
  Assert.IsTrue(Find(Items, 'Test', Item));
  Assert.IsTrue(Item.Attribute);
  Assert.AreEqual('Test', Item.InsertText);
  // Der Alias der Fassade geht dem Original vor.
  Count := Length(Item.AdditionalEdits);
  Assert.AreEqual(1, Count);
  Assert.IsTrue(Item.AdditionalEdits[0].NewText.Contains('DUnitX.TestFramework'), Item.AdditionalEdits[0].NewText);
  // Eingebunden: ohne uses-Eintrag.
  Items := ItemsAt('U:[Te|');
  Assert.AreEqual('Test TestCase TearDown', Names(Items));
  Assert.IsTrue(Find(Items, 'TestCase', Item));
  Assert.AreEqual(0, Integer(Length(Item.AdditionalEdits)));
end;

procedure TCompletionAttributesTests.KnownFirstWithoutPrefix;
begin
  // Ohne Eingabe: bekannte (mit uses-Eintrag), Compiler-Attribute, dann die eigenen; keine anderen Klassen.
  Assert.AreEqual('Test TestCase TearDown weak unsafe volatile Ref Marke', Names(ItemsAt('[|')));
end;

procedure TCompletionAttributesTests.DetailShowsConstructor;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('U:[|');
  Assert.IsTrue(Find(Items, 'TestCase', Item));
  Assert.AreEqual('(const ACaseName: string; const AValues: string)', Item.Detail);
  Assert.IsTrue(Find(Items, 'TearDown', Item));
  Assert.AreEqual('DUnitX.Attributes', Item.Detail, 'ohne Konstruktor die Unit');
  Assert.IsTrue(Find(Items, 'Marke', Item));
  Assert.AreEqual('(const AText: string)', Item.Detail);
  Assert.IsTrue(Find(Items, 'weak', Item));
  Assert.AreEqual('Compiler', Item.Detail);
  Assert.IsTrue(Item.Attribute);
end;

procedure TCompletionAttributesTests.AfterCommaAndInParameters;
begin
  Assert.AreEqual('Test TestCase TearDown', Names(ItemsAt('U:[Marke(''x''), Te|')));
  Assert.AreEqual('Marke', Names(ItemsAt('procedure Lies([Ma|')));
end;

procedure TCompletionAttributesTests.SetsAndIndexesStayNormal;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Items := ItemsAt('C:A := [A|');
  Assert.IsTrue(Find(Items, 'A', Item), Names(Items));
  Assert.IsFalse(Item.Attribute);
  Items := ItemsAt('C:A[Le|');
  Assert.IsFalse(Find(Items, 'Test', Item));
end;

procedure TCompletionAttributesTests.SwitchOff;
var
  Settings: TCompletionSettings;
  Items: TCompletionItems;
  Item: TCompletionItem;
begin
  Settings := TCompletionSettings.Default;
  Settings.Attributes := False;
  Items := ItemsAt('[Ma|', Settings);
  Assert.IsTrue(Find(Items, 'MarkeAttribute', Item), Names(Items));
  Assert.IsFalse(Item.Attribute);
  Assert.IsFalse(Find(Items, 'Marke', Item));
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
    Text: string;
    Position: TTextPosition;
    Tree: TSyntaxTree;
  begin
    Text := Split(Source(AMarked), Position);
    Tree := TPascalParser.Parse(Text);
    try
      Result := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, Text, HauptFile, Position, ReadText);
    finally
      Tree.Free;
    end;
  end;

var
  Help: TSignatureHelp;
begin
  Help := HelpAt('[Marke(|');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.IsTrue(Help.Signatures[0].Text.Contains('const AText: string'), Help.Signatures[0].Text);
  Help := HelpAt('U:[TestCase(''Name'', |');
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.IsTrue(Help.Signatures[0].Text.Contains('ACaseName'), Help.Signatures[0].Text);
  Assert.AreEqual(1, Help.ActiveParameter);
  Help := HelpAt('U:[Test(|');
  Assert.AreEqual(2, Integer(Length(Help.Signatures)), 'beide Konstruktoren');
end;

end.
