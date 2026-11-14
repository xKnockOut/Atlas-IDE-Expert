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
    function Describe(const AMarker: string): string; overload;
    function Describe(const AMarker: string; AOccurrence: Integer): string; overload;
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
    /// <summary>Mit vom Aufrufer gepinntem Baum dasselbe Ergebnis; der Pin bleibt danach.</summary>
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
  cSource =
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
  mIndex, mFound, mLine, mLineStart: Integer;
begin
  mFound := 0;
  mIndex := 0;
  repeat
    mIndex := Pos(AMarker, AText, mIndex + 1);
    if mIndex = 0 then
    begin
      raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
    end;
    Inc(mFound);
  until mFound = AOccurrence;
  mLine := 0;
  mLineStart := 1;
  for mFound := 1 to mIndex - 1 do
  begin
    if AText[mFound] = #10 then
    begin
      Inc(mLine);
      mLineStart := mFound + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
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
function TLspDocumentHighlightsTests.Describe(const AMarker: string): string;
begin
  Result := Describe(AMarker, 1);
end;

function TLspDocumentHighlightsTests.Describe(const AMarker: string; AOccurrence: Integer): string;
const
  cKinds: array[THighlightKind] of string = ('T', 'R', 'W');
var
  mTree: TSyntaxTree;
  mHighlight: TDocumentHighlight;
begin
  Result := '';
  mTree := TPascalParser.Parse(cSource);
  try
    for mHighlight in TLspDocumentHighlights.Highlights(FResolver, FIndex, mTree, 'C:\P\Haupt.pas',
      PositionOf(cSource, AMarker, AOccurrence)) do
    begin
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + Format('%d:%d/%s', [mHighlight.Range.StartPos.Line, mHighlight.Range.StartPos.Character,
        cKinds[mHighlight.Kind]]);
    end;
  finally
    mTree.Free;
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
  mTree: TSyntaxTree;
  mPinned: TUnitIndex;
  mFound: TArray<TDocumentHighlight>;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    FResolver.PinTree(mTree, 'C:\P\Haupt.pas');
    try
      mPinned := FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas');
      mFound := TLspDocumentHighlights.Highlights(FResolver, FIndex, mTree, 'C:\P\Haupt.pas',
        PositionOf(cSource, 'Wert;', 1));
      Assert.AreEqual(3, Integer(Length(mFound)));
      Assert.AreEqual(7, mFound[0].Range.StartPos.Line);
      Assert.AreEqual<THighlightKind>(THighlightKind.Text, mFound[0].Kind);
      Assert.AreEqual(12, mFound[1].Range.StartPos.Line);
      Assert.AreEqual<THighlightKind>(THighlightKind.Read, mFound[1].Kind);
      Assert.AreEqual(13, mFound[2].Range.StartPos.Line);
      Assert.AreEqual<THighlightKind>(THighlightKind.Write, mFound[2].Kind);
      Assert.AreEqual<Pointer>(Pointer(FResolver.ExtractedUnit(mTree, 'C:\P\Haupt.pas').Symbols),
        Pointer(mPinned.Symbols));
    finally
      FResolver.UnpinTree;
    end;
  finally
    mTree.Free;
  end;
  // Ohne äußeren Pin unverändert.
  Assert.AreEqual('7:4/T 12:10/R 13:2/W', Describe('Wert;'));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDocumentHighlightsTests);

end.
