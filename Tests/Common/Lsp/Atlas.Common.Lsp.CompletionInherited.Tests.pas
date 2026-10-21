unit Atlas.Common.Lsp.CompletionInherited.Tests;

// Vollständiger inherited-Aufruf (#482): Methodenköpfe, Argumente, Reihenfolge, abstrakte Methoden,
// "Result := " und die Einträge der Vervollständigung samt Schalter.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.CompletionInherited;

type
  [TestFixture]
  TCompletionInheritedTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesHeadersOfDeclarationAndImplementation;
    [Test]
    procedure ArgumentsComeFromOwnParameters;
    [Test]
    procedure CallsOrderSameOverloadOther;
    [Test]
    procedure AbstractMethodsAreLeftOut;
    [Test]
    procedure ResultOnlyInFunctionsOnEmptyLine;
    [Test]
    procedure HeaderTextEndsAtSemicolon;
    [Test]
    procedure CompletionOffersFullCallFirst;
    [Test]
    procedure CompletionAddsResultInFunctions;
    [Test]
    procedure CompletionSkipsAbstractAndFollowsSetting;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.Completion;

const
  BasisFile = 'C:\P\Basis.pas';
  HauptFile = 'C:\P\Haupt.pas';

  UnitBasis =
    'unit Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TComponent = class'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); virtual;'#10 +
    '  end;'#10 +
    '  TBaseView = class(TComponent)'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); virtual;'#10 +
    '    function FormatZeile(const AText: string; ALevel: Integer): string; overload; virtual;'#10 +
    '    function FormatZeile(const AText: string): string; overload; virtual;'#10 +
    '    procedure Zeichnen; virtual; abstract;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'uses Basis;'#10 +
    'type'#10 +
    '  TLogView = class(TBaseView)'#10 +
    '  public'#10 +
    '    constructor Create(AOwner: TComponent); override;'#10 +
    '    function FormatZeile(const AText: string; ALevel: Integer): string; override;'#10 +
    '    procedure Zeichnen; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'constructor TLogView.Create(AOwner: TComponent);'#10 +
    'begin'#10 +
    '  { Create }'#10 +
    'end;'#10 +
    'function TLogView.FormatZeile(const AText: string; ALevel: Integer): string;'#10 +
    'begin'#10 +
    '  { Format }'#10 +
    'end;'#10 +
    'procedure TLogView.Zeichnen;'#10 +
    'begin'#10 +
    '  { Zeichnen }'#10 +
    'end;'#10 +
    'end.';

function Header(const AText: string): TInheritedHeader;
begin
  Assert.IsTrue(TInheritedHeader.Parse(AText, Result), AText);
end;

function Method(const AText, AContainer: string; ADepth: Integer): TInheritedMethod;
begin
  Result.Header := Header(AText);
  Result.Container := AContainer;
  Result.Depth := ADepth;
end;

function ItemsAt(const AIndex: ISymbolIndex; const AText, AMarker: string;
  const ASettings: TCompletionSettings): TCompletionItems;
var
  Resolver: TNameResolver;
  Request: TCompletionRequest;
  Tree: TSyntaxTree;
  Lines: TArray<string>;
  Line: Integer;
  Position: TTextPosition;
  Postfix: TPostfixOptions;
begin
  Lines := AText.Split([#10]);
  Position := TTextPosition.Create(0, 0);
  for Line := 0 to High(Lines) do
    if Pos(AMarker, Lines[Line]) > 0 then
      Position := TTextPosition.Create(Line, Pos(AMarker, Lines[Line]) - 1 + Length(AMarker));
  Tree := TPascalParser.Parse(AText);
  Resolver := TNameResolver.Create(AIndex);
  Request := TCompletionRequest.Create(AText, HauptFile, Position);
  try
    Request.Tree := Tree;
    Request.Resolver := Resolver;
    Request.Index := AIndex;
    Request.Matching := TCompletionMatching.Prefix;
    Request.Settings := ASettings;
    Postfix := Default(TPostfixOptions);
    Result := TLspCompletion.Collect(Request, Postfix, nil);
  finally
    Request.Free;
    Resolver.Free;
    Tree.Free;
  end;
end;

function Code(const AMarker, ACode: string): string;
begin
  Result := StringReplace(UnitHaupt, AMarker, ACode, []);
end;

{ TCompletionInheritedTests }

procedure TCompletionInheritedTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitBasis, BasisFile, nil));
end;

procedure TCompletionInheritedTests.TearDown;
begin
  FIndex := nil;
end;

procedure TCompletionInheritedTests.ParsesHeadersOfDeclarationAndImplementation;
var
  Value: TInheritedHeader;
begin
  Value := Header('constructor TLogView.Create(AOwner: TComponent)');
  Assert.AreEqual('constructor', Value.Kind);
  Assert.AreEqual('Create', Value.Name);
  Assert.AreEqual(1, Integer(Length(Value.Params)));
  Assert.AreEqual('AOwner', Value.Params[0].Name);
  Assert.AreEqual('TComponent', Value.Params[0].TypeName);
  Value := Header('function FormatZeile(const AText, APrefix: string; ALevel: Integer = 0): string; virtual; abstract;');
  Assert.AreEqual('function', Value.Kind);
  Assert.AreEqual(3, Integer(Length(Value.Params)));
  Assert.AreEqual('APrefix', Value.Params[1].Name);
  Assert.AreEqual('string', Value.Params[1].TypeName);
  Assert.AreEqual('Integer', Value.Params[2].TypeName);
  Assert.IsTrue(Value.IsAbstract);
  Value := Header('class procedure TAussen.TInnen.Lies(var Puffer)');
  Assert.AreEqual('Lies', Value.Name);
  Assert.AreEqual('', Value.Params[0].TypeName);
  Assert.IsFalse(Value.IsAbstract);
  Assert.IsFalse(TInheritedHeader.Parse('property Name: string', Value));
end;

procedure TCompletionInheritedTests.ArgumentsComeFromOwnParameters;
var
  Args: TArray<string>;
begin
  // Gleicher Name, dann gleicher Typ, sonst der Name der Vorfahrmethode.
  Args := TCompletionInherited.Arguments(Header('constructor Create(AOwner: TComponent)'),
    Header('constructor CreateNew(AOwner: TComponent; Dummy: Integer)'));
  Assert.AreEqual('AOwner, Dummy', string.Join(', ', Args));
  Args := TCompletionInherited.Arguments(Header('procedure Setze(Wert: Integer; Besitzer: TComponent)'),
    Header('procedure Setze(AOwner: TComponent; AValue: Integer)'));
  Assert.AreEqual('Besitzer, Wert', string.Join(', ', Args));
end;

procedure TCompletionInheritedTests.CallsOrderSameOverloadOther;
var
  Calls: TArray<TInheritedCall>;
  Abstract_: TArray<string>;
begin
  Calls := TCompletionInherited.Calls(Header('constructor TLogView.Create(AOwner: TComponent)'), [
    Method('constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); virtual;', 'TBaseView', 1),
    Method('function FormatZeile(const AText: string): string;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent); override;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent); virtual;', 'TComponent', 2),
    Method('constructor CreateParented(ParentWindow: THandle);', 'TWinControl', 2)], Abstract_);
  Assert.AreEqual(3, Integer(Length(Calls)));
  Assert.AreEqual('Create(AOwner)', Calls[0].Text);
  Assert.IsTrue(Calls[0].Match = TInheritedMatch.Same);
  Assert.AreEqual('TBaseView', Calls[0].Container);
  Assert.AreEqual('CreateNew(AOwner, Dummy)', Calls[1].Text);
  Assert.IsTrue(Calls[1].Match = TInheritedMatch.Sibling);
  Assert.AreEqual('CreateParented(ParentWindow)', Calls[2].Text);
  // Funktion: die passende Überladung zuerst, keine Konstruktoren.
  Calls := TCompletionInherited.Calls(Header('function TLogView.FormatZeile(const AText: string; ALevel: Integer): string'), [
    Method('function FormatZeile(const AText: string): string; overload;', 'TBaseView', 1),
    Method('function FormatZeile(const AText: string; ALevel: Integer): string; overload;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent);', 'TBaseView', 1)], Abstract_);
  Assert.AreEqual(2, Integer(Length(Calls)));
  Assert.AreEqual('FormatZeile(AText, ALevel)', Calls[0].Text);
  Assert.AreEqual('FormatZeile(AText)', Calls[1].Text);
  Assert.IsTrue(Calls[1].Match = TInheritedMatch.Overload);
  Assert.AreEqual(0, Integer(Length(Abstract_)));
end;

procedure TCompletionInheritedTests.AbstractMethodsAreLeftOut;
var
  Calls: TArray<TInheritedCall>;
  Abstract_: TArray<string>;
begin
  Calls := TCompletionInherited.Calls(Header('procedure TLogView.Zeichnen'), [
    Method('procedure Zeichnen; virtual; abstract;', 'TBaseView', 1)], Abstract_);
  Assert.AreEqual(0, Integer(Length(Calls)));
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', Abstract_));
  // Ein näherer Vorfahr überschreibt die abstrakte Methode: seine Fassung gilt.
  Calls := TCompletionInherited.Calls(Header('procedure TLogView.Zeichnen'), [
    Method('procedure Zeichnen; override;', 'TMitte', 1),
    Method('procedure Zeichnen; virtual; abstract;', 'TBaseView', 2)], Abstract_);
  Assert.AreEqual(1, Integer(Length(Calls)));
  Assert.AreEqual('Zeichnen', Calls[0].Text);
  Assert.AreEqual(0, Integer(Length(Abstract_)));
end;

procedure TCompletionInheritedTests.ResultOnlyInFunctionsOnEmptyLine;
var
  Fn, Proc: TInheritedHeader;
begin
  Fn := Header('function TLogView.FormatZeile(const AText: string): string');
  Proc := Header('procedure TLogView.Zeichnen');
  Assert.IsTrue(TCompletionInherited.NeedsResult(Fn, '  inherited '));
  Assert.IsTrue(TCompletionInherited.NeedsResult(Fn, '  inherited Form'));
  Assert.IsFalse(TCompletionInherited.NeedsResult(Fn, '  S := inherited '));
  Assert.IsFalse(TCompletionInherited.NeedsResult(Fn, '  if inherited '));
  Assert.IsFalse(TCompletionInherited.NeedsResult(Proc, '  inherited '));
end;

procedure TCompletionInheritedTests.HeaderTextEndsAtSemicolon;
const
  Text = 'function TFoo.Bar(A: Integer;'#13#10'  B: string): string;'#13#10'begin';
begin
  Assert.AreEqual('function TFoo.Bar(A: Integer;    B: string): string', TCompletionInherited.HeaderText(Text, 1));
end;

procedure TCompletionInheritedTests.CompletionOffersFullCallFirst;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(FIndex, Code('  { Create }', '  inherited '), 'inherited ', TCompletionSettings.Default);
  Assert.IsTrue(Length(Items.Items) >= 2);
  Assert.AreEqual('Create(AOwner)', Items.Items[0].Name);
  Assert.AreEqual('same', Items.Items[0].InheritedMatch);
  Assert.AreEqual('Create', Items.Items[0].FilterText);
  Assert.IsTrue(Items.Items[0].HasTextEdit);
  Assert.AreEqual('Create(AOwner);', Items.Items[0].TextEdit.NewText);
  Assert.AreEqual('CreateNew(AOwner, Dummy)', Items.Items[1].Name);
  Assert.AreEqual('other', Items.Items[1].InheritedMatch);
  // Zeichnen ist abstrakt: weder als Aufruf noch als Name, die Fußzeile nennt es.
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', Items.Items[0].InheritedAbstract));
end;

procedure TCompletionInheritedTests.CompletionAddsResultInFunctions;
var
  Items: TCompletionItems;
begin
  Items := ItemsAt(FIndex, Code('  { Format }', '  inherited Form'), 'inherited Form', TCompletionSettings.Default);
  Assert.IsTrue(Length(Items.Items) >= 2);
  Assert.AreEqual('FormatZeile(AText, ALevel)', Items.Items[0].Name);
  Assert.AreEqual('Result := inherited FormatZeile(AText, ALevel);', Items.Items[0].TextEdit.NewText);
  Assert.AreEqual(2, Items.Items[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('FormatZeile(AText)', Items.Items[1].Name);
  Assert.AreEqual('overload', Items.Items[1].InheritedMatch);
  // Mit Text dahinter kein Semikolon und mit Zuweisung davor kein Result.
  Items := ItemsAt(FIndex, Code('  { Format }', '  S := inherited Form + ''x'';'), 'inherited Form',
    TCompletionSettings.Default);
  Assert.AreEqual('FormatZeile(AText, ALevel)', Items.Items[0].TextEdit.NewText);
end;

procedure TCompletionInheritedTests.CompletionSkipsAbstractAndFollowsSetting;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Settings: TCompletionSettings;
begin
  Items := ItemsAt(FIndex, Code('  { Zeichnen }', '  inherited '), 'inherited ', TCompletionSettings.Default);
  for Item in Items.Items do
  begin
    Assert.AreNotEqual('Zeichnen', Item.Name);
    Assert.AreEqual('', Item.InheritedMatch, Item.Name);
  end;
  // Aus: nur die Namen der Vorfahrmethoden wie bisher.
  Settings := TCompletionSettings.Default;
  Settings.InheritedCall := False;
  Items := ItemsAt(FIndex, Code('  { Create }', '  inherited '), 'inherited ', Settings);
  for Item in Items.Items do
    Assert.AreEqual('', Item.InheritedMatch, Item.Name);
  Assert.AreEqual('Create', Items.Items[0].Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionInheritedTests);

end.
