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
  Atlas.Common.Lsp.Completion.Lists,
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.Completion;

const
  cBasisFile = 'C:\P\Basis.pas';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitBasis =
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

  cUnitHaupt =
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
  mResolver: TNameResolver;
  mRequest: TCompletionRequest;
  mTree: TSyntaxTree;
  mLines: TArray<string>;
  mLine: Integer;
  mPosition: TTextPosition;
  mPostfix: TPostfixOptions;
begin
  mLines := AText.Split([#10]);
  mPosition := TTextPosition.Create(0, 0);
  for mLine := 0 to High(mLines) do
  begin
    if Pos(AMarker, mLines[mLine]) > 0 then
    begin
      mPosition := TTextPosition.Create(mLine, Pos(AMarker, mLines[mLine]) - 1 + Length(AMarker));
    end;
  end;
  mTree := TPascalParser.Parse(AText);
  mResolver := TNameResolver.Create(AIndex);
  mRequest := TCompletionRequest.Create(AText, cHauptFile, mPosition);
  try
    mRequest.Tree := mTree;
    mRequest.Resolver := mResolver;
    mRequest.Index := AIndex;
    mRequest.Matching := TCompletionMatching.Prefix;
    mRequest.Settings := ASettings;
    mPostfix := Default(TPostfixOptions);
    Result := TCompletionLists.Collect(mRequest, mPostfix, nil);
  finally
    mRequest.Free;
    mResolver.Free;
    mTree.Free;
  end;
end;

function Code(const AMarker, ACode: string): string;
begin
  Result := StringReplace(cUnitHaupt, AMarker, ACode, []);
end;

{ TCompletionInheritedTests }

procedure TCompletionInheritedTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitBasis, cBasisFile, nil));
end;

procedure TCompletionInheritedTests.TearDown;
begin
  FIndex := nil;
end;

procedure TCompletionInheritedTests.ParsesHeadersOfDeclarationAndImplementation;
var
  mValue: TInheritedHeader;
begin
  mValue := Header('constructor TLogView.Create(AOwner: TComponent)');
  Assert.AreEqual('constructor', mValue.Kind);
  Assert.AreEqual('Create', mValue.Name);
  Assert.AreEqual(1, Integer(Length(mValue.Params)));
  Assert.AreEqual('AOwner', mValue.Params[0].Name);
  Assert.AreEqual('TComponent', mValue.Params[0].TypeName);
  mValue := Header('function FormatZeile(const AText, APrefix: string; ALevel: Integer = 0): string; virtual; abstract;');
  Assert.AreEqual('function', mValue.Kind);
  Assert.AreEqual(3, Integer(Length(mValue.Params)));
  Assert.AreEqual('APrefix', mValue.Params[1].Name);
  Assert.AreEqual('string', mValue.Params[1].TypeName);
  Assert.AreEqual('Integer', mValue.Params[2].TypeName);
  Assert.IsTrue(mValue.IsAbstract);
  mValue := Header('class procedure TAussen.TInnen.Lies(var Puffer)');
  Assert.AreEqual('Lies', mValue.Name);
  Assert.AreEqual('', mValue.Params[0].TypeName);
  Assert.IsFalse(mValue.IsAbstract);
  Assert.IsFalse(TInheritedHeader.Parse('property Name: string', mValue));
end;

procedure TCompletionInheritedTests.ArgumentsComeFromOwnParameters;
var
  mArgs: TArray<string>;
begin
  // Gleicher Name, dann gleicher Typ, sonst der Name der Vorfahrmethode.
  mArgs := TCompletionInherited.Arguments(Header('constructor Create(AOwner: TComponent)'),
    Header('constructor CreateNew(AOwner: TComponent; Dummy: Integer)'));
  Assert.AreEqual('AOwner, Dummy', string.Join(', ', mArgs));
  mArgs := TCompletionInherited.Arguments(Header('procedure Setze(Wert: Integer; Besitzer: TComponent)'),
    Header('procedure Setze(AOwner: TComponent; AValue: Integer)'));
  Assert.AreEqual('Besitzer, Wert', string.Join(', ', mArgs));
end;

procedure TCompletionInheritedTests.CallsOrderSameOverloadOther;
var
  mCalls: TArray<TInheritedCall>;
  mAbstract_: TArray<string>;
begin
  mCalls := TCompletionInherited.Calls(Header('constructor TLogView.Create(AOwner: TComponent)'), [
    Method('constructor CreateNew(AOwner: TComponent; Dummy: Integer = 0); virtual;', 'TBaseView', 1),
    Method('function FormatZeile(const AText: string): string;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent); override;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent); virtual;', 'TComponent', 2),
    Method('constructor CreateParented(ParentWindow: THandle);', 'TWinControl', 2)], mAbstract_);
  Assert.AreEqual(3, Integer(Length(mCalls)));
  Assert.AreEqual('Create(AOwner)', mCalls[0].Text);
  Assert.AreEqual<TInheritedMatch>(TInheritedMatch.Same, mCalls[0].Match);
  Assert.AreEqual('TBaseView', mCalls[0].Container);
  Assert.AreEqual('CreateNew(AOwner, Dummy)', mCalls[1].Text);
  Assert.AreEqual<TInheritedMatch>(TInheritedMatch.Sibling, mCalls[1].Match);
  Assert.AreEqual('CreateParented(ParentWindow)', mCalls[2].Text);
  // Funktion: die passende Überladung zuerst, keine Konstruktoren.
  mCalls := TCompletionInherited.Calls(Header('function TLogView.FormatZeile(const AText: string; ALevel: Integer): string'), [
    Method('function FormatZeile(const AText: string): string; overload;', 'TBaseView', 1),
    Method('function FormatZeile(const AText: string; ALevel: Integer): string; overload;', 'TBaseView', 1),
    Method('constructor Create(AOwner: TComponent);', 'TBaseView', 1)], mAbstract_);
  Assert.AreEqual(2, Integer(Length(mCalls)));
  Assert.AreEqual('FormatZeile(AText, ALevel)', mCalls[0].Text);
  Assert.AreEqual('FormatZeile(AText)', mCalls[1].Text);
  Assert.AreEqual<TInheritedMatch>(TInheritedMatch.Overload, mCalls[1].Match);
  Assert.AreEqual(0, Integer(Length(mAbstract_)));
end;

procedure TCompletionInheritedTests.AbstractMethodsAreLeftOut;
var
  mCalls: TArray<TInheritedCall>;
  mAbstract_: TArray<string>;
begin
  mCalls := TCompletionInherited.Calls(Header('procedure TLogView.Zeichnen'), [
    Method('procedure Zeichnen; virtual; abstract;', 'TBaseView', 1)], mAbstract_);
  Assert.AreEqual(0, Integer(Length(mCalls)));
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', mAbstract_));
  // Ein näherer Vorfahr überschreibt die abstrakte Methode: seine Fassung gilt.
  mCalls := TCompletionInherited.Calls(Header('procedure TLogView.Zeichnen'), [
    Method('procedure Zeichnen; override;', 'TMitte', 1),
    Method('procedure Zeichnen; virtual; abstract;', 'TBaseView', 2)], mAbstract_);
  Assert.AreEqual(1, Integer(Length(mCalls)));
  Assert.AreEqual('Zeichnen', mCalls[0].Text);
  Assert.AreEqual(0, Integer(Length(mAbstract_)));
end;

procedure TCompletionInheritedTests.ResultOnlyInFunctionsOnEmptyLine;
var
  mFn, mProc: TInheritedHeader;
begin
  mFn := Header('function TLogView.FormatZeile(const AText: string): string');
  mProc := Header('procedure TLogView.Zeichnen');
  Assert.IsTrue(TCompletionInherited.NeedsResult(mFn, '  inherited '));
  Assert.IsTrue(TCompletionInherited.NeedsResult(mFn, '  inherited Form'));
  Assert.IsFalse(TCompletionInherited.NeedsResult(mFn, '  S := inherited '));
  Assert.IsFalse(TCompletionInherited.NeedsResult(mFn, '  if inherited '));
  Assert.IsFalse(TCompletionInherited.NeedsResult(mProc, '  inherited '));
end;

procedure TCompletionInheritedTests.HeaderTextEndsAtSemicolon;
const
  cText = 'function TFoo.Bar(A: Integer;'#13#10'  B: string): string;'#13#10'begin';
begin
  Assert.AreEqual('function TFoo.Bar(A: Integer;    B: string): string', TCompletionInherited.HeaderText(cText, 1));
end;

procedure TCompletionInheritedTests.CompletionOffersFullCallFirst;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt(FIndex, Code('  { Create }', '  inherited '), 'inherited ', TCompletionSettings.Default);
  Assert.IsTrue(Length(mItems.Items) >= 2);
  Assert.AreEqual('Create(AOwner)', mItems.Items[0].Name);
  Assert.AreEqual('same', mItems.Items[0].InheritedMatch);
  Assert.AreEqual('Create', mItems.Items[0].FilterText);
  Assert.IsTrue(mItems.Items[0].HasTextEdit);
  Assert.AreEqual('Create(AOwner);', mItems.Items[0].TextEdit.NewText);
  Assert.AreEqual('CreateNew(AOwner, Dummy)', mItems.Items[1].Name);
  Assert.AreEqual('other', mItems.Items[1].InheritedMatch);
  // Zeichnen ist abstrakt: weder als Aufruf noch als Name, die Fußzeile nennt es.
  Assert.AreEqual('TBaseView.Zeichnen', string.Join(',', mItems.Items[0].InheritedAbstract));
end;

procedure TCompletionInheritedTests.CompletionAddsResultInFunctions;
var
  mItems: TCompletionItems;
begin
  mItems := ItemsAt(FIndex, Code('  { Format }', '  inherited Form'), 'inherited Form', TCompletionSettings.Default);
  Assert.IsTrue(Length(mItems.Items) >= 2);
  Assert.AreEqual('FormatZeile(AText, ALevel)', mItems.Items[0].Name);
  Assert.AreEqual('Result := inherited FormatZeile(AText, ALevel);', mItems.Items[0].TextEdit.NewText);
  Assert.AreEqual(2, mItems.Items[0].TextEdit.Range.StartPos.Character);
  Assert.AreEqual('FormatZeile(AText)', mItems.Items[1].Name);
  Assert.AreEqual('overload', mItems.Items[1].InheritedMatch);
  // Mit Text dahinter kein Semikolon und mit Zuweisung davor kein Result.
  mItems := ItemsAt(FIndex, Code('  { Format }', '  S := inherited Form + ''x'';'), 'inherited Form',
    TCompletionSettings.Default);
  Assert.AreEqual('FormatZeile(AText, ALevel)', mItems.Items[0].TextEdit.NewText);
end;

procedure TCompletionInheritedTests.CompletionSkipsAbstractAndFollowsSetting;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mSettings: TCompletionSettings;
begin
  mItems := ItemsAt(FIndex, Code('  { Zeichnen }', '  inherited '), 'inherited ', TCompletionSettings.Default);
  for mItem in mItems.Items do
  begin
    Assert.AreNotEqual('Zeichnen', mItem.Name);
    Assert.AreEqual('', mItem.InheritedMatch, mItem.Name);
  end;
  // Aus: nur die Namen der Vorfahrmethoden wie bisher.
  mSettings := TCompletionSettings.Default;
  mSettings.InheritedCall := False;
  mItems := ItemsAt(FIndex, Code('  { Create }', '  inherited '), 'inherited ', mSettings);
  for mItem in mItems.Items do
  begin
    Assert.AreEqual('', mItem.InheritedMatch, mItem.Name);
  end;
  Assert.AreEqual('Create', mItems.Items[0].Name);
end;

initialization
  TDUnitX.RegisterTestFixture(TCompletionInheritedTests);

end.
