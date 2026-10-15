unit Atlas.Common.Lsp.DocumentHighlights.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.DocumentHighlights;

type
  [TestFixture]
  TLspDocumentHighlightsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AMarker: string; AOccurrence: Integer = 1): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarksReadsWritesAndDeclaration;
    [Test]
    procedure SeparatesScopes;
    [Test]
    procedure MarksMethodDeclarationAndImplementation;
    [Test]
    procedure NothingOutsideIdentifiers;
    /// <summary>Code-Review P-01: Mit vom Aufrufer gepinntem Baum dasselbe Ergebnis; der Pin bleibt danach.</summary>
    [Test]
    procedure HighlightsWithPinnedResolver;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex;

const
  Source =
    'unit Haupt;'#10 +                  // 0
    'interface'#10 +                    // 1
    'type'#10 +                         // 2
    '  TFoo = class'#10 +               // 3
    '    procedure Bar;'#10 +           // 4
    '  end;'#10 +                       // 5
    'implementation'#10 +               // 6
    'var Wert: Integer;'#10 +           // 7
    'procedure TFoo.Bar;'#10 +          // 8
    'var'#10 +                          // 9
    '  Zahl: Integer;'#10 +             // 10
    'begin'#10 +                        // 11
    '  Zahl := Wert;'#10 +              // 12
    '  Wert := Zahl + 1;'#10 +          // 13
    '  Bar;'#10 +                       // 14
    'end;'#10 +                         // 15
    'procedure Andere;'#10 +            // 16
    'var'#10 +                          // 17
    '  Zahl: Integer;'#10 +             // 18
    'begin'#10 +                        // 19
    '  Zahl := 2;'#10 +                 // 20
    'end;'#10 +                         // 21
    'end.';

function PositionOf(const AText, AMarker: string; AOccurrence: Integer): TTextPosition;
var
  Index, Found, Line, LineStart: Integer;
begin
  Found := 0;
  Index := 0;
  repeat
    Index := Pos(AMarker, AText, Index + 1);
    if Index = 0 then
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    Inc(Found);
  until Found = AOccurrence;
  Line := 0;
  LineStart := 1;
  for Found := 1 to Index - 1 do
    if AText[Found] = #10 then
    begin
      Inc(Line);
      LineStart := Found + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TLspDocumentHighlightsTests }

procedure TLspDocumentHighlightsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspDocumentHighlightsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

// "Zeile:Spalte/Art" je Vorkommen, z. B. "7:4/T 12:10/R"; Art T, R oder W.
function TLspDocumentHighlightsTests.Describe(const AMarker: string; AOccurrence: Integer): string;
const
  Kinds: array[THighlightKind] of string = ('T', 'R', 'W');
var
  Tree: TSyntaxTree;
  Highlight: TDocumentHighlight;
begin
  Result := '';
  Tree := TPascalParser.Parse(Source);
  try
    for Highlight in TLspDocumentHighlights.Highlights(FResolver, FIndex, Tree, 'C:\P\Haupt.pas',
      PositionOf(Source, AMarker, AOccurrence)) do
    begin
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Format('%d:%d/%s', [Highlight.Range.StartPos.Line, Highlight.Range.StartPos.Character,
        Kinds[Highlight.Kind]]);
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspDocumentHighlightsTests.MarksReadsWritesAndDeclaration;
begin
  Assert.AreEqual('7:4/T 12:10/R 13:2/W', Describe('Wert;'));
end;

procedure TLspDocumentHighlightsTests.SeparatesScopes;
begin
  Assert.AreEqual('10:2/T 12:2/W 13:10/R', Describe('Zahl := Wert'));
  Assert.AreEqual('18:2/T 20:2/W', Describe('Zahl := 2'));
end;

procedure TLspDocumentHighlightsTests.MarksMethodDeclarationAndImplementation;
begin
  Assert.AreEqual('4:14/T 8:15/R 14:2/R', Describe('Bar;', 3));
end;

procedure TLspDocumentHighlightsTests.NothingOutsideIdentifiers;
begin
  Assert.AreEqual('', Describe('begin'));
end;

procedure TLspDocumentHighlightsTests.HighlightsWithPinnedResolver;
var
  Tree: TSyntaxTree;
  Pinned: TUnitIndex;
  Found: TArray<TDocumentHighlight>;
begin
  Tree := TPascalParser.Parse(Source);
  try
    FResolver.PinTree(Tree, 'C:\P\Haupt.pas');
    try
      Pinned := FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas');
      Found := TLspDocumentHighlights.Highlights(FResolver, FIndex, Tree, 'C:\P\Haupt.pas',
        PositionOf(Source, 'Wert;', 1));
      Assert.AreEqual(3, Integer(Length(Found)));
      Assert.AreEqual(7, Found[0].Range.StartPos.Line);
      Assert.IsTrue(Found[0].Kind = THighlightKind.Text);
      Assert.AreEqual(12, Found[1].Range.StartPos.Line);
      Assert.IsTrue(Found[1].Kind = THighlightKind.Read);
      Assert.AreEqual(13, Found[2].Range.StartPos.Line);
      Assert.IsTrue(Found[2].Kind = THighlightKind.Write);
      Assert.IsTrue(Pointer(Pinned.Symbols) = Pointer(FResolver.ExtractedUnit(Tree, 'C:\P\Haupt.pas').Symbols));
    finally
      FResolver.UnpinTree;
    end;
  finally
    Tree.Free;
  end;
  // Ohne äußeren Pin unverändert.
  Assert.AreEqual('7:4/T 12:10/R 13:2/W', Describe('Wert;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentHighlightsTests);

end.
