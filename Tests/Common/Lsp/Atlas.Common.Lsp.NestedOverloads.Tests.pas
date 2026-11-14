unit Atlas.Common.Lsp.NestedOverloads.Tests;

// #881: Überladene Routinen, die in einer Methode verschachtelt sind, in Vervollständigung, Parameter-Hinweis
// und Auflösung: Überladungen vor und hinter dem Aufruf, mehrere Ebenen, gleichnamige Methode der Klasse.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.CompletionRequest,
  Atlas.Common.Lsp.SignatureHelp;

type
  [TestFixture]
  TNestedOverloadsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function HelpAt(const AMarker: string): TSignatureHelp;
    function ItemsAt(const ACode, AMarker: string): TCompletionItems;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SignatureHelpListsOverloadsBeforeAndAfterCall;
    [Test]
    procedure SignatureHelpInDeeperLevel;
    [Test]
    procedure SignatureHelpFromInnerRoutineSeesOuterOverloads;
    [Test]
    procedure ResolvesOverloadByArguments;
    [Test]
    procedure CompletionShowsNestedRoutineOnceWithOverloads;
    [Test]
    procedure CompletionInDeeperLevel;
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
  Atlas.Common.Lsp.Completion;

const
  cHauptFile = 'C:\P\Haupt.pas';

  // Hilf gibt es als Methode der Klasse und zweimal verschachtelt in Bar: vor Rufe und dahinter.
  cUnitHaupt =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFoo = class'#10 +
    '    procedure Bar;'#10 +
    '    procedure Hilf(const A, B: string);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFoo.Hilf(const A, B: string);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TFoo.Bar;'#10 +
    '  procedure Hilf(Wert: Integer); overload;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    '  procedure Rufe;'#10 +
    '    procedure Tief(A: Integer); overload;'#10 +
    '    begin'#10 +
    '    end;'#10 +
    '    procedure Tief(A, B: Integer); overload;'#10 +
    '    begin'#10 +
    '    end;'#10 +
    '  begin'#10 +
    '    Tief(1, 2);'#10 +
    '    Hilf(2);'#10 +
    '  end;'#10 +
    '  procedure Hilf(const Text: string; Anzahl: Integer); overload;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'begin'#10 +
    '  Hilf(''x'', 3);'#10 +
    '  Hilf(4);'#10 +
    '  |'#10 +
    'end;'#10 +
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, mScan: Integer;
begin
  // Cursor hinter AMarker.
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  Inc(mIndex, Length(AMarker));
  mLine := 0;
  mLineStart := 1;
  for mScan := 1 to mIndex - 1 do
  begin
    if AText[mScan] = #10 then
    begin
      Inc(mLine);
      mLineStart := mScan + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function SignatureTexts(const AHelp: TSignatureHelp): string;
var
  mSignature: TSignature;
begin
  Result := '';
  for mSignature in AHelp.Signatures do
  begin
    Result := Result + mSignature.Text + '|';
  end;
end;

{ TNestedOverloadsTests }

procedure TNestedOverloadsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TNestedOverloadsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TNestedOverloadsTests.HelpAt(const AMarker: string): TSignatureHelp;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspSignatureHelp.HelpAt(TSignatureHelpRequest.Create(FResolver, FIndex, mTree, cUnitHaupt, cHauptFile,
      NoText), PositionOf(cUnitHaupt, AMarker));
  finally
    mTree.Free;
  end;
end;

function TNestedOverloadsTests.ItemsAt(const ACode, AMarker: string): TCompletionItems;
var
  mText: string;
  mTree: TSyntaxTree;
begin
  mText := StringReplace(cUnitHaupt, '  |', ACode, []);
  mTree := TPascalParser.Parse(mText);
  try
    Result := TCompletionLists.Collect(FResolver, FIndex, mTree, cHauptFile, PositionOf(mText, AMarker),
      TCompletionMatching.Prefix);
  finally
    mTree.Free;
  end;
end;

procedure TNestedOverloadsTests.SignatureHelpListsOverloadsBeforeAndAfterCall;
var
  mHelp: TSignatureHelp;
begin
  // Beide verschachtelten Überladungen, nicht die gleichnamige Methode der Klasse.
  mHelp := HelpAt('  Hilf(''x'', ');
  Assert.AreEqual('procedure Hilf(Wert: Integer)|procedure Hilf(const Text: string; Anzahl: Integer)|',
    SignatureTexts(mHelp));
  Assert.AreEqual(1, mHelp.ActiveParameter);
  Assert.AreEqual(1, mHelp.ActiveSignature);
end;

procedure TNestedOverloadsTests.SignatureHelpInDeeperLevel;
var
  mHelp: TSignatureHelp;
begin
  mHelp := HelpAt('    Tief(1, ');
  Assert.AreEqual('procedure Tief(A: Integer)|procedure Tief(A, B: Integer)|', SignatureTexts(mHelp));
  Assert.AreEqual(1, mHelp.ActiveSignature);
end;

procedure TNestedOverloadsTests.SignatureHelpFromInnerRoutineSeesOuterOverloads;
begin
  // Aus Rufe heraus: die Überladungen der umgebenden Routine Bar, auch die hinter Rufe.
  Assert.AreEqual('procedure Hilf(Wert: Integer)|procedure Hilf(const Text: string; Anzahl: Integer)|',
    SignatureTexts(HelpAt('    Hilf(')));
end;

procedure TNestedOverloadsTests.ResolvesOverloadByArguments;
var
  mTree: TSyntaxTree;
  mResolved: TResolvedSymbol;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    // Hilf('x', 3) ist die Überladung hinter Rufe (Zeile 26), Hilf(4) die vor Rufe (Zeile 12).
    mResolved := FResolver.Resolve(mTree, cHauptFile, PositionOf(cUnitHaupt, #10'  Hil'));
    Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, mResolved.Kind);
    Assert.AreEqual(26, mResolved.SelectionRange.StartPos.Line);
    mResolved := FResolver.Resolve(mTree, cHauptFile, PositionOf(cUnitHaupt, '3);'#10'  Hil'));
    Assert.AreEqual<TResolvedKind>(TResolvedKind.Local, mResolved.Kind);
    Assert.AreEqual(12, mResolved.SelectionRange.StartPos.Line);
  finally
    mTree.Free;
  end;
end;

procedure TNestedOverloadsTests.CompletionShowsNestedRoutineOnceWithOverloads;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mCount: Integer;
begin
  mItems := ItemsAt('  Hil', 'Hilf(4);'#10'  Hil');
  mCount := 0;
  for mItem in mItems.Items do
  begin
    if SameText(mItem.Name, 'Hilf') then
    begin
      Inc(mCount);
      // Der verschachtelte Eintrag verdeckt die Methode der Klasse und kennt seine zweite Überladung.
      Assert.AreEqual(1, mItem.Scope);
      Assert.AreEqual(1, Integer(Length(mItem.Overloads)));
      Assert.IsTrue(mItem.HasParameters);
    end;
  end;
  Assert.AreEqual(1, mCount);
end;

procedure TNestedOverloadsTests.CompletionInDeeperLevel;
var
  mItems: TCompletionItems;
  mItem: TCompletionItem;
  mNames: string;
begin
  // In Rufe: Tief aus Rufe und Hilf aus Bar.
  mItems := ItemsAt('  ', #10'  begin'#10'    T');
  mNames := '';
  for mItem in mItems.Items do
  begin
    mNames := mNames + mItem.Name + ' ';
  end;
  Assert.IsTrue(Pos('Tief ', mNames) > 0, mNames);
  mItems := ItemsAt('  ', #10'    Hil');
  mNames := '';
  for mItem in mItems.Items do
  begin
    mNames := mNames + mItem.Name + ' ';
  end;
  Assert.IsTrue(Pos('Hilf ', mNames) > 0, mNames);
end;

initialization
  TDUnitX.RegisterTestFixture(TNestedOverloadsTests);

end.
