unit Atlas.Core.Outline.StickyScroll.Tests;

// Mitlaufender Kopf (#506): Kopf einer langen Methode, äußerer und innerer
// Kopf untereinander, nach inneren Routinen nur der äußere, Zusammenfassung
// bei vier Ebenen, gekürzte mehrzeilige Köpfe, Klasse im interface,
// Sprungziel, Arten im Kopf, Beginn und Einblenden der Blocklinien im Kopf.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStickyScrollTests = class
  public
    [Test]
    procedure HeaderOfLongMethodStaysOnTop;
    [Test]
    procedure InnerFunctionStacksBelowOuter;
    [Test]
    procedure OuterBodyAfterInnerRoutinesShowsOnlyOuter;
    [Test]
    procedure FourLevelsShowAtMostThreeRows;
    [Test]
    procedure OneRowSummarizesAllLevels;
    [Test]
    procedure MultiLineHeaderIsShortened;
    [Test]
    procedure ClassInInterfaceIsABlock;
    [Test]
    procedure NothingWhileTheHeaderIsVisible;
    [Test]
    procedure RowsJumpToTheName;
    [Test]
    procedure IndentCountsTabs;
    /// <summary>#1229: procedure im Kopf in der Tiefenfarbe ihres Blocks, Klammer bis vor „…“.</summary>
    [Test]
    procedure HeaderKeywordsTakeTheirDepthColor;
    /// <summary>#1230: Große if/else-Blöcke stehen als eigene Zeile im Kopf, nach ihrer Lage eingereiht.</summary>
    [Test]
    procedure BranchBlocksJoinTheHeader;
    /// <summary>Kopfzeile wie im Editor hervorgehoben: reservierte Wörter, Bezeichner, Strings, Zahlen, Kommentare.
    /// </summary>
    [Test]
    procedure SyntaxLikeTheEditor;
    /// <summary>Blocklinie beginnt in der Kopfzeile ihres Elements; ohne Kopfzeile (Art aus, zusammengefasst)
    /// blendet sie in der letzten Kopfzeile ein statt ohne Anfang darunter.</summary>
    [Test]
    procedure GuideStartsAtItsRowOrFadesIn;
    /// <summary>Einblenden: unten volle Deckkraft, oben fast keine, dazwischen steigend.</summary>
    [Test]
    procedure FadeRisesToTheBottom;
    /// <summary>Besitzerwort ordnet den Block seiner Art zu: if/else, Schleifen, try, case, with; sonst keine.
    /// </summary>
    [Test]
    procedure OwnerWordsHaveTheirKind;
    /// <summary>Nur die eingestellten Arten der Gliederung (Klassen, Routinen) bekommen eine Kopfzeile.</summary>
    [Test]
    procedure OutlineKindsCanBeSwitchedOff;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.Outline.StickyScroll,
  Atlas.Core.Editor.Pairs;

type
  /// <summary>Zeilen (0-basiert) im erzeugten Quelltext.</summary>
  TMarks = record
    FormClass: Integer;
    Laden: Integer;
    Eins: Integer;
    EinsBody: Integer;
    Zwei: Integer;
    LadenBody: Integer;
    Tief: Integer;
    Lokal: Integer;
    Pruefe: Integer;
    Innen: Integer;
    InnenBody: Integer;
    Lang: Integer;
    LangBody: Integer;
  end;

  TSource = record
    Lines: TArray<string>;
    Nodes: TAtlasOutlineNodes;
    Marks: TMarks;
  end;

procedure Add(var ALines: TArray<string>; const ALine: string);
begin
  ALines := ALines + [ALine];
end;

procedure Fill(var ALines: TArray<string>; const AIndent: string; ACount: Integer);
var
  Index: Integer;
begin
  for Index := 1 to ACount do
    Add(ALines, AIndent + 'X := ' + IntToStr(Index) + ';');
end;

function Build: TSource;
var
  Lines: TArray<string>;
  Code: string;
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
begin
  Lines := nil;
  Add(Lines, 'unit uForm;');
  Add(Lines, 'interface');
  Add(Lines, 'type');
  Result.Marks.FormClass := Length(Lines);
  Add(Lines, '  TForm1 = class(TObject)');
  Add(Lines, '    procedure Laden;');
  Add(Lines, '    procedure Tief;');
  Add(Lines, '    procedure Lang;');
  Add(Lines, '    procedure Vier;');
  Add(Lines, '    procedure Fuenf;');
  Add(Lines, '  end;');
  Add(Lines, 'implementation');
  // Zwei lange innere Funktionen, dann der Rumpf der äußeren Routine.
  Result.Marks.Laden := Length(Lines);
  Add(Lines, 'procedure TForm1.Laden;');
  Result.Marks.Eins := Length(Lines);
  Add(Lines, '  function Eins: Integer;');
  Add(Lines, '  var X: Integer;');
  Add(Lines, '  begin');
  Result.Marks.EinsBody := Length(Lines);
  Fill(Lines, '    ', 20);
  Add(Lines, '    Result := X;');
  Add(Lines, '  end;');
  Result.Marks.Zwei := Length(Lines);
  Add(Lines, '  function Zwei: Integer;');
  Add(Lines, '  var X: Integer;');
  Add(Lines, '  begin');
  Fill(Lines, '    ', 20);
  Add(Lines, '    Result := X;');
  Add(Lines, '  end;');
  Add(Lines, 'var X: Integer;');
  Add(Lines, 'begin');
  Result.Marks.LadenBody := Length(Lines);
  Fill(Lines, '  ', 20);
  Add(Lines, 'end;');
  // Vier Ebenen, die dritte mit mehrzeiligem Kopf.
  Result.Marks.Tief := Length(Lines);
  Add(Lines, 'procedure TForm1.Tief;');
  Result.Marks.Lokal := Length(Lines);
  Add(Lines, '  procedure Lokal;');
  Result.Marks.Pruefe := Length(Lines);
  Add(Lines, '    function Pruefe(const S: string;');
  Add(Lines, '      N: Integer): Boolean;');
  Result.Marks.Innen := Length(Lines);
  Add(Lines, '      procedure Innen;');
  Add(Lines, '      var X: Integer;');
  Add(Lines, '      begin');
  Result.Marks.InnenBody := Length(Lines);
  Fill(Lines, '        ', 10);
  Add(Lines, '      end;');
  Add(Lines, '    begin');
  Add(Lines, '      Result := S <> '''';');
  Add(Lines, '    end;');
  Add(Lines, '  begin');
  Add(Lines, '    Pruefe('''', 1);');
  Add(Lines, '  end;');
  Add(Lines, 'begin');
  Add(Lines, '  Lokal;');
  Add(Lines, 'end;');
  // Eine Methode mit 300 Zeilen.
  Result.Marks.Lang := Length(Lines);
  Add(Lines, 'procedure TForm1.Lang;');
  Add(Lines, 'var X: Integer;');
  Add(Lines, 'begin');
  Result.Marks.LangBody := Length(Lines);
  Fill(Lines, '  ', 300);
  Add(Lines, 'end;');
  Add(Lines, 'procedure TForm1.Vier; begin end;');
  Add(Lines, 'procedure TForm1.Fuenf; begin end;');
  Add(Lines, 'end.');
  Result.Lines := Lines;
  Code := string.Join(#13#10, Lines);
  Tree := TPascalParser.Parse(Code);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, Code);
  finally
    Tree.Free;
  end;
  try
    Result.Nodes := TAtlasOutline.FromJson(Symbols);
  finally
    Symbols.Free;
  end;
end;

function Texts(const ARows: TAtlasStickyRows): string;
var
  Row: TAtlasStickyRow;
begin
  Result := '';
  for Row in ARows do
  begin
    if Result <> '' then
      Result := Result + ' | ';
    Result := Result + Row.Text;
  end;
end;

procedure TAtlasStickyScrollTests.HeaderOfLongMethodStaysOnTop;
var
  Source: TSource;
begin
  Source := Build;
  Assert.AreEqual('procedure TForm1.Lang;', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.Lang + 200, 3)));
  Assert.AreEqual('procedure TForm1.Lang;', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.LangBody + 298, 3)), 'kurz vor dem Ende');
end;

procedure TAtlasStickyScrollTests.InnerFunctionStacksBelowOuter;
var
  Source: TSource;
begin
  Source := Build;
  Assert.AreEqual('procedure TForm1.Laden; | function Eins: Integer;', Texts(TAtlasStickyScroll.Rows(Source.Nodes,
    Source.Lines, Source.Marks.EinsBody + 5, 3)));
end;

procedure TAtlasStickyScrollTests.OuterBodyAfterInnerRoutinesShowsOnlyOuter;
var
  Source: TSource;
begin
  Source := Build;
  Assert.AreEqual('procedure TForm1.Laden;', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.LadenBody + 5, 3)));
end;

procedure TAtlasStickyScrollTests.FourLevelsShowAtMostThreeRows;
var
  Source: TSource;
  Rows: TAtlasStickyRows;
begin
  Source := Build;
  Rows := TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, Source.Marks.InnenBody + 3, 3);
  Assert.AreEqual(3, Integer(Length(Rows)));
  Assert.AreEqual('TForm1.Tief › Lokal | function Pruefe(…): Boolean; | procedure Innen;', Texts(Rows));
  Assert.IsTrue(Rows[0].Summary);
  Assert.IsFalse(Rows[2].Summary);
  // Mit vier Zeilen jede Ebene für sich.
  Assert.AreEqual(4, Integer(Length(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.InnenBody + 3, 4))));
end;

procedure TAtlasStickyScrollTests.OneRowSummarizesAllLevels;
var
  Source: TSource;
  Rows: TAtlasStickyRows;
begin
  Source := Build;
  Rows := TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, Source.Marks.InnenBody + 3, 1);
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.AreEqual('TForm1.Tief › Lokal › Pruefe › Innen', Rows[0].Text);
  Assert.AreEqual(Source.Marks.Innen, Rows[0].Line, 'springt zur innersten Ebene');
  // Untergrenze: 0 Zeilen gilt als eine.
  Assert.AreEqual(1, Integer(Length(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.InnenBody + 3, 0))));
end;

procedure TAtlasStickyScrollTests.MultiLineHeaderIsShortened;
var
  Source: TSource;
  Node: TAtlasOutlineNode;
begin
  Source := Build;
  for Node in Source.Nodes do
    if Node.Name = 'Pruefe' then
      Assert.AreEqual('function Pruefe(…): Boolean;', TAtlasStickyScroll.Header(Source.Lines, Node));
  Node := Default(TAtlasOutlineNode);
  Node.NameLine := 0;
  Node.EndLine := 0;
  Assert.AreEqual('procedure A(…)', TAtlasStickyScroll.Header(['  procedure A(B: Integer'], Node),
    'ohne schließende Klammer');
  Assert.AreEqual('procedure A(const S: string = ''('');', TAtlasStickyScroll.Header(
    ['procedure A(const S: string = ''('');'], Node), 'Klammer in der Zeichenkette');
end;

procedure TAtlasStickyScrollTests.ClassInInterfaceIsABlock;
var
  Source: TSource;
begin
  Source := Build;
  Assert.AreEqual('TForm1 = class(TObject)', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines,
    Source.Marks.FormClass + 2, 3)));
end;

procedure TAtlasStickyScrollTests.NothingWhileTheHeaderIsVisible;
var
  Source: TSource;
begin
  Source := Build;
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, Source.Marks.Lang, 3)));
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, 0, 3)));
  // Letzte Zeile der Methode unter dem Kopf: der Block ist zu Ende, kein Kopf mehr.
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, Source.Marks.LangBody + 300, 3)));
end;

procedure TAtlasStickyScrollTests.RowsJumpToTheName;
var
  Source: TSource;
  Rows: TAtlasStickyRows;
begin
  Source := Build;
  Rows := TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, Source.Marks.EinsBody + 5, 3);
  Assert.AreEqual(Source.Marks.Laden, Rows[0].Line);
  Assert.AreEqual(Source.Marks.Eins, Rows[1].Line);
  Assert.AreEqual(11, Rows[1].Character, 'Name hinter „function “');
  Assert.AreEqual(2, Rows[1].Indent);
  Assert.AreEqual(0, Rows[0].Indent);
end;

procedure TAtlasStickyScrollTests.IndentCountsTabs;
begin
  Assert.AreEqual(4, TAtlasStickyScroll.IndentColumns(#9'x', 4));
  Assert.AreEqual(4, TAtlasStickyScroll.IndentColumns('  '#9'x', 4));
  Assert.AreEqual(6, TAtlasStickyScroll.IndentColumns(#9'  x', 4));
  Assert.AreEqual(0, TAtlasStickyScroll.IndentColumns('x', 4));
end;

function TokensOfLine(const ATokens: TArray<TAtlasPairToken>; ALine: Integer): TArray<TAtlasPairToken>;
var
  Token: TAtlasPairToken;
begin
  Result := nil;
  for Token in ATokens do
    if Token.Line = ALine then
      Result := Result + [Token];
end;

/// <summary>„Art:Text“ je Stück ohne Lücken, durch | getrennt.</summary>
function Described(const AText: string): string;
const
  Names: array[TAtlasStickySyntax] of string = ('_', 'R', 'I', 'N', 'S', 'C', 'K', 'Y', 'P');
var
  Token: TAtlasStickyToken;
begin
  Result := '';
  for Token in TAtlasStickyScroll.Syntax(AText) do
    if Token.Kind <> TAtlasStickySyntax.Plain then
      Result := Result + Names[Token.Kind] + ':' + Copy(AText, Token.Start, Token.Length) + '|';
end;

procedure TAtlasStickyScrollTests.SyntaxLikeTheEditor;
begin
  Assert.AreEqual('R:class|R:function|I:TCompilerEditions|Y:.|I:Detect|Y:(|I:AExists|Y::|I:Boolean|Y:;|R:const|' +
    'I:AOutput|Y::|I:TArray|Y:<|R:string|Y:>|Y:)|Y::|I:TCompilerEdition|Y:;|',
    Described('class function TCompilerEditions.Detect(AExists: Boolean; const AOutput: TArray<string>): ' +
    'TCompilerEdition;'));
  Assert.AreEqual('R:if|I:A|Y:=|S:''It''''s''|R:then|K:{ Kommentar }|', Described('if A = ''It''''s'' then { Kommentar }'));
  Assert.AreEqual('I:X|Y::|Y:=|N:$FF|Y:+|N:1.5E-3|Y:+|C:#13|Y:;|K:// Rest|',
    Described('X := $FF + 1.5E-3 + #13; // Rest'));
  // Mitglied hinter "." und escapte Namen sind keine Schlüsselwörter; Direktiven schon.
  Assert.AreEqual('I:Self|Y:.|I:Free|Y:;|I:&begin|Y:;|R:override|Y:;|P:{$IFDEF X}|',
    Described('Self.Free; &begin; override; {$IFDEF X}'));
end;

procedure TAtlasStickyScrollTests.BranchBlocksJoinTheHeader;
var
  Lines: TArray<string>;
  Index: Integer;
  Blocks: TArray<TAtlasStickyBlock>;
  Rows: TAtlasStickyRows;
begin
  SetLength(Lines, 60);
  for Index := 0 to High(Lines) do
    Lines[Index] := '      Tue;';
  Lines[2] := '  if Gueltig then';
  Lines[3] := '  begin';
  Lines[10] := '    else if Leer then';
  Lines[11] := '    begin';
  Lines[40] := '    end;';
  Lines[50] := '  end;';
  Blocks := TArray<TAtlasStickyBlock>.Create(TAtlasStickyBlock.Create(10, 4, 40), TAtlasStickyBlock.Create(2, 2, 50));
  // Mitten im inneren Block: beide, der äußere zuerst, ohne Einrückung im Text.
  Rows := TAtlasStickyScroll.Rows(nil, Lines, Blocks, 20, 3, 8);
  Assert.AreEqual(2, Integer(Length(Rows)));
  Assert.AreEqual('if Gueltig then', Rows[0].Text);
  Assert.AreEqual(2, Rows[0].Indent);
  Assert.AreEqual('else if Leer then', Rows[1].Text);
  Assert.AreEqual(10, Rows[1].Line, 'Sprung zum else');
  // Nach dem inneren Block nur noch der äußere; nach dem äußeren keiner.
  Assert.AreEqual(1, Integer(Length(TAtlasStickyScroll.Rows(nil, Lines, Blocks, 44, 3, 8))));
  Assert.AreEqual(0, Integer(Length(TAtlasStickyScroll.Rows(nil, Lines, Blocks, 55, 3, 8))));
  // Eine Zeile: Zusammenfassung mit gekürzten Köpfen.
  Rows := TAtlasStickyScroll.Rows(nil, Lines, Blocks, 20, 1, 8);
  Assert.AreEqual(1, Integer(Length(Rows)));
  Assert.AreEqual('if Gueltig then › else if Leer then', Rows[0].Text);
end;

procedure TAtlasStickyScrollTests.HeaderKeywordsTakeTheirDepthColor;
const
  Lines: array[0..5] of string = ('procedure Aussen;', '  procedure Innen(A,', '    B: Integer);', '  begin',
    '  end;', 'begin');
var
  Tokens, Line1: TArray<TAtlasPairToken>;
  Spans: TArray<TAtlasPairSpan>;
begin
  Tokens := TAtlasPairs.Analyze(string.Join(#10, Lines) + #10'end;');
  Line1 := TokensOfLine(Tokens, 1);
  // Kopf der inneren Routine ohne Einrückung, Parameterliste gekürzt: procedure in der Farbe ihres begin.
  Spans := TAtlasPairs.Spans('procedure Innen(…): Boolean;', Lines[1], Line1, True);
  Assert.IsTrue(Length(Spans) >= 1, 'procedure gefärbt');
  Assert.AreEqual(1, Spans[0].Start);
  Assert.AreEqual(9, Spans[0].Length);
  Assert.AreEqual(TokensOfLine(Tokens, 3)[0].Depth, Spans[0].Depth, 'Tiefe des eigenen begin');
  Assert.AreEqual('(', Copy('procedure Innen(…): Boolean;', Spans[High(Spans)].Start, 1), 'Klammer vor „…“');
  // Ohne Besitzer (PairOwners aus) bleibt procedure ungefärbt wie im Editor.
  for var Span in TAtlasPairs.Spans('procedure Innen(…): Boolean;', Lines[1], Line1, False) do
    Assert.AreNotEqual(1, Span.Start);
end;

function Row(ALine: Integer; ASummary: Boolean): TAtlasStickyRow;
begin
  Result := Default(TAtlasStickyRow);
  Result.Text := 'Kopf';
  Result.Line := ALine;
  Result.Summary := ASummary;
end;

procedure TAtlasStickyScrollTests.GuideStartsAtItsRowOrFadesIn;
var
  Rows: TAtlasStickyRows;
  Start: TAtlasStickyGuideStart;
begin
  // Zusammenfassung mit Sprungziel 3, procedure in 10, if in 14.
  Rows := [Row(3, True), Row(10, False), Row(14, False)];
  Start := TAtlasStickyScroll.GuideStart(Rows, 10);
  Assert.AreEqual(1, Start.Row);
  Assert.IsFalse(Start.FadeIn);
  Start := TAtlasStickyScroll.GuideStart(Rows, 14);
  Assert.AreEqual(2, Start.Row);
  Assert.IsFalse(Start.FadeIn);
  // for in 12 ohne Kopfzeile: in der letzten Zeile eingeblendet.
  Start := TAtlasStickyScroll.GuideStart(Rows, 12);
  Assert.AreEqual(2, Start.Row);
  Assert.IsTrue(Start.FadeIn);
  // Die Zusammenfassung ist nicht das Element der Linie.
  Start := TAtlasStickyScroll.GuideStart(Rows, 3);
  Assert.AreEqual(2, Start.Row);
  Assert.IsTrue(Start.FadeIn);
  // Ohne Kopf keine Linie im Kopf.
  Rows := nil;
  Start := TAtlasStickyScroll.GuideStart(Rows, 12);
  Assert.AreEqual(-1, Start.Row);
  Assert.IsFalse(Start.FadeIn);
end;

procedure TAtlasStickyScrollTests.FadeRisesToTheBottom;
var
  Offset: Integer;
begin
  Assert.AreEqual(1.0, TAtlasStickyScroll.FadeWeight(19, 20), 1e-9, 'unterste Pixelzeile voll');
  Assert.IsTrue(TAtlasStickyScroll.FadeWeight(0, 20) < 0.01, 'oben fast unsichtbar');
  for Offset := 1 to 19 do
    Assert.IsTrue(TAtlasStickyScroll.FadeWeight(Offset, 20) > TAtlasStickyScroll.FadeWeight(Offset - 1, 20));
  // Weich: in der Mitte noch unter der Hälfte.
  Assert.IsTrue(TAtlasStickyScroll.FadeWeight(9, 20) < 0.5);
  Assert.AreEqual(1.0, TAtlasStickyScroll.FadeWeight(0, 1), 1e-9, 'eine Pixelzeile');
end;

procedure TAtlasStickyScrollTests.OwnerWordsHaveTheirKind;
var
  Kind: TAtlasStickyKind;
begin
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('if', Kind) and (Kind = TAtlasStickyKind.Branches));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('else', Kind) and (Kind = TAtlasStickyKind.Branches));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('for', Kind) and (Kind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('while', Kind) and (Kind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('repeat', Kind) and (Kind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('try', Kind) and (Kind = TAtlasStickyKind.TryBlocks));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('case', Kind) and (Kind = TAtlasStickyKind.CaseBlocks));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('with', Kind) and (Kind = TAtlasStickyKind.WithBlocks));
  // Ohne Anweisung davor (begin, asm) und Ausnahmezweige (on) bekommen keine eigene Zeile.
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('begin', Kind));
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('asm', Kind));
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('on', Kind));
end;

procedure TAtlasStickyScrollTests.OutlineKindsCanBeSwitchedOff;
var
  Source: TSource;
begin
  Source := Build;
  // Klasse: nur mit Types.
  Assert.AreEqual('TForm1 = class(TObject)', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, nil,
    [TAtlasStickyKind.Types], Source.Marks.FormClass + 2, 3, 8)));
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, nil, [TAtlasStickyKind.Routines],
    Source.Marks.FormClass + 2, 3, 8)));
  // Routinen: nur mit Routines; ohne beide bleibt der Kopf leer.
  Assert.AreEqual('procedure TForm1.Laden; | function Eins: Integer;', Texts(TAtlasStickyScroll.Rows(Source.Nodes,
    Source.Lines, nil, [TAtlasStickyKind.Routines], Source.Marks.EinsBody + 5, 3, 8)));
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, nil, [TAtlasStickyKind.Types],
    Source.Marks.EinsBody + 5, 3, 8)));
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(Source.Nodes, Source.Lines, nil, [], Source.Marks.EinsBody + 5,
    3, 8)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStickyScrollTests);

end.
