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
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Lsp.Completion;

const
  HauptFile = 'C:\P\Haupt.pas';

  // Hilf gibt es als Methode der Klasse und zweimal verschachtelt in Bar: vor Rufe und dahinter.
  UnitHaupt =
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
  Index, Line, LineStart, Scan: Integer;
begin
  // Cursor hinter AMarker.
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Inc(Index, Length(AMarker));
  Line := 0;
  LineStart := 1;
  for Scan := 1 to Index - 1 do
    if AText[Scan] = #10 then
    begin
      Inc(Line);
      LineStart := Scan + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

function NoText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
end;

function SignatureTexts(const AHelp: TSignatureHelp): string;
var
  Signature: TSignature;
begin
  Result := '';
  for Signature in AHelp.Signatures do
    Result := Result + Signature.Text + '|';
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
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspSignatureHelp.HelpAt(FResolver, FIndex, Tree, UnitHaupt, HauptFile, PositionOf(UnitHaupt, AMarker),
      NoText);
  finally
    Tree.Free;
  end;
end;

function TNestedOverloadsTests.ItemsAt(const ACode, AMarker: string): TCompletionItems;
var
  Text: string;
  Tree: TSyntaxTree;
begin
  Text := StringReplace(UnitHaupt, '  |', ACode, []);
  Tree := TPascalParser.Parse(Text);
  try
    Result := TLspCompletion.Collect(FResolver, FIndex, Tree, HauptFile, PositionOf(Text, AMarker),
      TCompletionMatching.Prefix);
  finally
    Tree.Free;
  end;
end;

procedure TNestedOverloadsTests.SignatureHelpListsOverloadsBeforeAndAfterCall;
var
  Help: TSignatureHelp;
begin
  // Beide verschachtelten Überladungen, nicht die gleichnamige Methode der Klasse.
  Help := HelpAt('  Hilf(''x'', ');
  Assert.AreEqual('procedure Hilf(Wert: Integer)|procedure Hilf(const Text: string; Anzahl: Integer)|',
    SignatureTexts(Help));
  Assert.AreEqual(1, Help.ActiveParameter);
  Assert.AreEqual(1, Help.ActiveSignature);
end;

procedure TNestedOverloadsTests.SignatureHelpInDeeperLevel;
var
  Help: TSignatureHelp;
begin
  Help := HelpAt('    Tief(1, ');
  Assert.AreEqual('procedure Tief(A: Integer)|procedure Tief(A, B: Integer)|', SignatureTexts(Help));
  Assert.AreEqual(1, Help.ActiveSignature);
end;

procedure TNestedOverloadsTests.SignatureHelpFromInnerRoutineSeesOuterOverloads;
begin
  // Aus Rufe heraus: die Überladungen der umgebenden Routine Bar, auch die hinter Rufe.
  Assert.AreEqual('procedure Hilf(Wert: Integer)|procedure Hilf(const Text: string; Anzahl: Integer)|',
    SignatureTexts(HelpAt('    Hilf(')));
end;

procedure TNestedOverloadsTests.ResolvesOverloadByArguments;
var
  Tree: TSyntaxTree;
  Resolved: TResolvedSymbol;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Hilf('x', 3) ist die Überladung hinter Rufe (Zeile 26), Hilf(4) die vor Rufe (Zeile 12).
    Resolved := FResolver.Resolve(Tree, HauptFile, PositionOf(UnitHaupt, #10'  Hil'));
    Assert.IsTrue(Resolved.Kind = TResolvedKind.Local);
    Assert.AreEqual(26, Resolved.SelectionRange.StartPos.Line);
    Resolved := FResolver.Resolve(Tree, HauptFile, PositionOf(UnitHaupt, '3);'#10'  Hil'));
    Assert.IsTrue(Resolved.Kind = TResolvedKind.Local);
    Assert.AreEqual(12, Resolved.SelectionRange.StartPos.Line);
  finally
    Tree.Free;
  end;
end;

procedure TNestedOverloadsTests.CompletionShowsNestedRoutineOnceWithOverloads;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Count: Integer;
begin
  Items := ItemsAt('  Hil', 'Hilf(4);'#10'  Hil');
  Count := 0;
  for Item in Items.Items do
    if SameText(Item.Name, 'Hilf') then
    begin
      Inc(Count);
      // Der verschachtelte Eintrag verdeckt die Methode der Klasse und kennt seine zweite Überladung.
      Assert.AreEqual(1, Item.Scope);
      Assert.AreEqual(1, Integer(Length(Item.Overloads)));
      Assert.IsTrue(Item.HasParameters);
    end;
  Assert.AreEqual(1, Count);
end;

procedure TNestedOverloadsTests.CompletionInDeeperLevel;
var
  Items: TCompletionItems;
  Item: TCompletionItem;
  Names: string;
begin
  // In Rufe: Tief aus Rufe und Hilf aus Bar.
  Items := ItemsAt('  ', #10'  begin'#10'    T');
  Names := '';
  for Item in Items.Items do
    Names := Names + Item.Name + ' ';
  Assert.IsTrue(Pos('Tief ', Names) > 0, Names);
  Items := ItemsAt('  ', #10'    Hil');
  Names := '';
  for Item in Items.Items do
    Names := Names + Item.Name + ' ';
  Assert.IsTrue(Pos('Hilf ', Names) > 0, Names);
end;

initialization
  TDUnitX.RegisterTestFixture(TNestedOverloadsTests);

end.
