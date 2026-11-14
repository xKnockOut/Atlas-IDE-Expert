unit Atlas.Core.Outline.StickyScroll.Tests;

// Mitlaufender Kopf (#506): Kopf einer langen Methode, äußerer und innerer
// Kopf untereinander, nach inneren Routinen nur der äußere, Zusammenfassung
// bei vier Ebenen, gekürzte mehrzeilige Köpfe, Klasse im interface,
// Sprungziel, Arten im Kopf, Beginn und Einblenden der Blocklinien im Kopf,
// Zeichen im Kopf als Stelle im Quelltext (Hover).

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
    /// <summary>Hover über dem Kopf: Ein Zeichen der Kopfzeile ist die Stelle in ihrer Quellzeile; gekürzte
    /// Parameterliste, Einrückung, Zusammenfassung, Tabulator und geänderte Zeile haben keine.</summary>
    [Test]
    procedure HeaderCharactersMapToTheSource;
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
  mIndex: Integer;
begin
  for mIndex := 1 to ACount do
  begin
    Add(ALines, AIndent + 'X := ' + IntToStr(mIndex) + ';');
  end;
end;

/// <summary>Zwei lange innere Funktionen, dann der Rumpf der äußeren Routine.</summary>
procedure AddLaden(var ALines: TArray<string>; var AMarks: TMarks);
begin
  AMarks.Laden := Length(ALines);
  Add(ALines, 'procedure TForm1.Laden;');
  AMarks.Eins := Length(ALines);
  Add(ALines, '  function Eins: Integer;');
  Add(ALines, '  var X: Integer;');
  Add(ALines, '  begin');
  AMarks.EinsBody := Length(ALines);
  Fill(ALines, '    ', 20);
  Add(ALines, '    Result := X;');
  Add(ALines, '  end;');
  AMarks.Zwei := Length(ALines);
  Add(ALines, '  function Zwei: Integer;');
  Add(ALines, '  var X: Integer;');
  Add(ALines, '  begin');
  Fill(ALines, '    ', 20);
  Add(ALines, '    Result := X;');
  Add(ALines, '  end;');
  Add(ALines, 'var X: Integer;');
  Add(ALines, 'begin');
  AMarks.LadenBody := Length(ALines);
  Fill(ALines, '  ', 20);
  Add(ALines, 'end;');
end;

/// <summary>Vier Ebenen, die dritte mit mehrzeiligem Kopf.</summary>
procedure AddTief(var ALines: TArray<string>; var AMarks: TMarks);
begin
  AMarks.Tief := Length(ALines);
  Add(ALines, 'procedure TForm1.Tief;');
  AMarks.Lokal := Length(ALines);
  Add(ALines, '  procedure Lokal;');
  AMarks.Pruefe := Length(ALines);
  Add(ALines, '    function Pruefe(const S: string;');
  Add(ALines, '      N: Integer): Boolean;');
  AMarks.Innen := Length(ALines);
  Add(ALines, '      procedure Innen;');
  Add(ALines, '      var X: Integer;');
  Add(ALines, '      begin');
  AMarks.InnenBody := Length(ALines);
  Fill(ALines, '        ', 10);
  Add(ALines, '      end;');
  Add(ALines, '    begin');
  Add(ALines, '      Result := S <> '''';');
  Add(ALines, '    end;');
  Add(ALines, '  begin');
  Add(ALines, '    Pruefe('''', 1);');
  Add(ALines, '  end;');
  Add(ALines, 'begin');
  Add(ALines, '  Lokal;');
  Add(ALines, 'end;');
end;

function Build: TSource;
var
  mLines: TArray<string>;
  mCode: string;
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
begin
  mLines := nil;
  Add(mLines, 'unit uForm;');
  Add(mLines, 'interface');
  Add(mLines, 'type');
  Result.Marks.FormClass := Length(mLines);
  Add(mLines, '  TForm1 = class(TObject)');
  Add(mLines, '    procedure Laden;');
  Add(mLines, '    procedure Tief;');
  Add(mLines, '    procedure Lang;');
  Add(mLines, '    procedure Vier;');
  Add(mLines, '    procedure Fuenf;');
  Add(mLines, '  end;');
  Add(mLines, 'implementation');
  AddLaden(mLines, Result.Marks);
  AddTief(mLines, Result.Marks);
  // Eine Methode mit 300 Zeilen.
  Result.Marks.Lang := Length(mLines);
  Add(mLines, 'procedure TForm1.Lang;');
  Add(mLines, 'var X: Integer;');
  Add(mLines, 'begin');
  Result.Marks.LangBody := Length(mLines);
  Fill(mLines, '  ', 300);
  Add(mLines, 'end;');
  Add(mLines, 'procedure TForm1.Vier; begin end;');
  Add(mLines, 'procedure TForm1.Fuenf; begin end;');
  Add(mLines, 'end.');
  Result.Lines := mLines;
  mCode := string.Join(#13#10, mLines);
  mTree := TPascalParser.Parse(mCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, mCode);
  finally
    mTree.Free;
  end;
  try
    Result.Nodes := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
end;

function Texts(const ARows: TAtlasStickyRows): string;
var
  mRow: TAtlasStickyRow;
begin
  Result := '';
  for mRow in ARows do
  begin
    if Result <> '' then
    begin
      Result := Result + ' | ';
    end;
    Result := Result + mRow.Text;
  end;
end;

procedure TAtlasStickyScrollTests.HeaderOfLongMethodStaysOnTop;
var
  mSource: TSource;
begin
  mSource := Build;
  Assert.AreEqual('procedure TForm1.Lang;', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.Lang + 200, 3)));
  Assert.AreEqual('procedure TForm1.Lang;', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.LangBody + 298, 3)), 'kurz vor dem Ende');
end;

procedure TAtlasStickyScrollTests.InnerFunctionStacksBelowOuter;
var
  mSource: TSource;
begin
  mSource := Build;
  Assert.AreEqual('procedure TForm1.Laden; | function Eins: Integer;', Texts(TAtlasStickyScroll.Rows(mSource.Nodes,
    mSource.Lines, mSource.Marks.EinsBody + 5, 3)));
end;

procedure TAtlasStickyScrollTests.OuterBodyAfterInnerRoutinesShowsOnlyOuter;
var
  mSource: TSource;
begin
  mSource := Build;
  Assert.AreEqual('procedure TForm1.Laden;', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.LadenBody + 5, 3)));
end;

procedure TAtlasStickyScrollTests.FourLevelsShowAtMostThreeRows;
var
  mSource: TSource;
  mRows: TAtlasStickyRows;
begin
  mSource := Build;
  mRows := TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, mSource.Marks.InnenBody + 3, 3);
  Assert.AreEqual(3, Integer(Length(mRows)));
  Assert.AreEqual('TForm1.Tief › Lokal | function Pruefe(…): Boolean; | procedure Innen;', Texts(mRows));
  Assert.IsTrue(mRows[0].Summary);
  Assert.IsFalse(mRows[2].Summary);
  // Mit vier Zeilen jede Ebene für sich.
  Assert.AreEqual(4, Integer(Length(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.InnenBody + 3, 4))));
end;

procedure TAtlasStickyScrollTests.OneRowSummarizesAllLevels;
var
  mSource: TSource;
  mRows: TAtlasStickyRows;
begin
  mSource := Build;
  mRows := TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, mSource.Marks.InnenBody + 3, 1);
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('TForm1.Tief › Lokal › Pruefe › Innen', mRows[0].Text);
  Assert.AreEqual(mSource.Marks.Innen, mRows[0].Line, 'springt zur innersten Ebene');
  // Untergrenze: 0 Zeilen gilt als eine.
  Assert.AreEqual(1, Integer(Length(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.InnenBody + 3, 0))));
end;

procedure TAtlasStickyScrollTests.MultiLineHeaderIsShortened;
var
  mSource: TSource;
  mNode: TAtlasOutlineNode;
begin
  mSource := Build;
  for mNode in mSource.Nodes do
  begin
    if mNode.Name = 'Pruefe' then
    begin
      Assert.AreEqual('function Pruefe(…): Boolean;', TAtlasStickyScroll.Header(mSource.Lines, mNode));
    end;
  end;
  mNode := Default(TAtlasOutlineNode);
  mNode.NameLine := 0;
  mNode.EndLine := 0;
  Assert.AreEqual('procedure A(…)', TAtlasStickyScroll.Header(['  procedure A(B: Integer'], mNode),
    'ohne schließende Klammer');
  Assert.AreEqual('procedure A(const S: string = ''('');', TAtlasStickyScroll.Header(
    ['procedure A(const S: string = ''('');'], mNode), 'Klammer in der Zeichenkette');
end;

procedure TAtlasStickyScrollTests.ClassInInterfaceIsABlock;
var
  mSource: TSource;
begin
  mSource := Build;
  Assert.AreEqual('TForm1 = class(TObject)', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines,
    mSource.Marks.FormClass + 2, 3)));
end;

procedure TAtlasStickyScrollTests.NothingWhileTheHeaderIsVisible;
var
  mSource: TSource;
begin
  mSource := Build;
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, mSource.Marks.Lang, 3)));
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, 0, 3)));
  // Letzte Zeile der Methode unter dem Kopf: der Block ist zu Ende, kein Kopf mehr.
  Assert.AreEqual('', Texts(TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, mSource.Marks.LangBody + 300, 3)));
end;

procedure TAtlasStickyScrollTests.RowsJumpToTheName;
var
  mSource: TSource;
  mRows: TAtlasStickyRows;
begin
  mSource := Build;
  mRows := TAtlasStickyScroll.Rows(mSource.Nodes, mSource.Lines, mSource.Marks.EinsBody + 5, 3);
  Assert.AreEqual(mSource.Marks.Laden, mRows[0].Line);
  Assert.AreEqual(mSource.Marks.Eins, mRows[1].Line);
  Assert.AreEqual(11, mRows[1].Character, 'Name hinter „function “');
  Assert.AreEqual(2, mRows[1].Indent);
  Assert.AreEqual(0, mRows[0].Indent);
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
  mToken: TAtlasPairToken;
begin
  Result := nil;
  for mToken in ATokens do
  begin
    if mToken.Line = ALine then
    begin
      Result := Result + [mToken];
    end;
  end;
end;

/// <summary>„Art:Text“ je Stück ohne Lücken, durch | getrennt.</summary>
function Described(const AText: string): string;
const
  cNames: array[TAtlasStickySyntax] of string = ('_', 'R', 'I', 'N', 'S', 'C', 'K', 'Y', 'P');
var
  mToken: TAtlasStickyToken;
begin
  Result := '';
  for mToken in TAtlasStickyScroll.Syntax(AText) do
  begin
    if mToken.Kind <> TAtlasStickySyntax.Plain then
    begin
      Result := Result + cNames[mToken.Kind] + ':' + Copy(AText, mToken.Start, mToken.Length) + '|';
    end;
  end;
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
  mLines: TArray<string>;
  mIndex: Integer;
  mBlocks: TArray<TAtlasStickyBlock>;
  mRows: TAtlasStickyRows;
begin
  SetLength(mLines, 60);
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := '      Tue;';
  end;
  mLines[2] := '  if Gueltig then';
  mLines[3] := '  begin';
  mLines[10] := '    else if Leer then';
  mLines[11] := '    begin';
  mLines[40] := '    end;';
  mLines[50] := '  end;';
  mBlocks := TArray<TAtlasStickyBlock>.Create(TAtlasStickyBlock.Create(10, 4, 40), TAtlasStickyBlock.Create(2, 2, 50));
  // Mitten im inneren Block: beide, der äußere zuerst, ohne Einrückung im Text.
  mRows := TAtlasStickyScroll.Rows(nil, mLines, mBlocks, 20, 3, 8);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('if Gueltig then', mRows[0].Text);
  Assert.AreEqual(2, mRows[0].Indent);
  Assert.AreEqual('else if Leer then', mRows[1].Text);
  Assert.AreEqual(10, mRows[1].Line, 'Sprung zum else');
  // Nach dem inneren Block nur noch der äußere; nach dem äußeren keiner.
  Assert.AreEqual(1, Integer(Length(TAtlasStickyScroll.Rows(nil, mLines, mBlocks, 44, 3, 8))));
  Assert.AreEqual(0, Integer(Length(TAtlasStickyScroll.Rows(nil, mLines, mBlocks, 55, 3, 8))));
  // Eine Zeile: Zusammenfassung mit gekürzten Köpfen.
  mRows := TAtlasStickyScroll.Rows(nil, mLines, mBlocks, 20, 1, 8);
  Assert.AreEqual(1, Integer(Length(mRows)));
  Assert.AreEqual('if Gueltig then › else if Leer then', mRows[0].Text);
end;

procedure TAtlasStickyScrollTests.HeaderKeywordsTakeTheirDepthColor;
const
  cLines: array[0..5] of string = ('procedure Aussen;', '  procedure Innen(A,', '    B: Integer);', '  begin',
    '  end;', 'begin');
var
  mTokens, mLine1: TArray<TAtlasPairToken>;
  mSpans: TArray<TAtlasPairSpan>;
begin
  mTokens := TAtlasPairs.Analyze(string.Join(#10, cLines) + #10'end;');
  mLine1 := TokensOfLine(mTokens, 1);
  // Kopf der inneren Routine ohne Einrückung, Parameterliste gekürzt: procedure in der Farbe ihres begin.
  mSpans := TAtlasPairs.Spans('procedure Innen(…): Boolean;', cLines[1], mLine1, True);
  Assert.IsTrue(Length(mSpans) >= 1, 'procedure gefärbt');
  Assert.AreEqual(1, mSpans[0].Start);
  Assert.AreEqual(9, mSpans[0].Length);
  Assert.AreEqual(TokensOfLine(mTokens, 3)[0].Depth, mSpans[0].Depth, 'Tiefe des eigenen begin');
  Assert.AreEqual('(', Copy('procedure Innen(…): Boolean;', mSpans[High(mSpans)].Start, 1), 'Klammer vor „…“');
  // Ohne Besitzer (PairOwners aus) bleibt procedure ungefärbt wie im Editor.
  for var mSpan in TAtlasPairs.Spans('procedure Innen(…): Boolean;', cLines[1], mLine1, False) do
  begin
    Assert.AreNotEqual(1, mSpan.Start);
  end;
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
  mRows: TAtlasStickyRows;
  mStart: TAtlasStickyGuideStart;
begin
  // Zusammenfassung mit Sprungziel 3, procedure in 10, if in 14.
  mRows := [Row(3, True), Row(10, False), Row(14, False)];
  mStart := TAtlasStickyScroll.GuideStart(mRows, 10);
  Assert.AreEqual(1, mStart.Row);
  Assert.IsFalse(mStart.FadeIn);
  mStart := TAtlasStickyScroll.GuideStart(mRows, 14);
  Assert.AreEqual(2, mStart.Row);
  Assert.IsFalse(mStart.FadeIn);
  // for in 12 ohne Kopfzeile: in der letzten Zeile eingeblendet.
  mStart := TAtlasStickyScroll.GuideStart(mRows, 12);
  Assert.AreEqual(2, mStart.Row);
  Assert.IsTrue(mStart.FadeIn);
  // Die Zusammenfassung ist nicht das Element der Linie.
  mStart := TAtlasStickyScroll.GuideStart(mRows, 3);
  Assert.AreEqual(2, mStart.Row);
  Assert.IsTrue(mStart.FadeIn);
  // Ohne Kopf keine Linie im Kopf.
  mRows := nil;
  mStart := TAtlasStickyScroll.GuideStart(mRows, 12);
  Assert.AreEqual(-1, mStart.Row);
  Assert.IsFalse(mStart.FadeIn);
end;

procedure TAtlasStickyScrollTests.FadeRisesToTheBottom;
var
  mOffset: Integer;
begin
  Assert.AreEqual(1.0, TAtlasStickyScroll.FadeWeight(19, 20), 1e-9, 'unterste Pixelzeile voll');
  Assert.IsTrue(TAtlasStickyScroll.FadeWeight(0, 20) < 0.01, 'oben fast unsichtbar');
  for mOffset := 1 to 19 do
  begin
    Assert.IsTrue(TAtlasStickyScroll.FadeWeight(mOffset, 20) > TAtlasStickyScroll.FadeWeight(mOffset - 1, 20));
  end;
  // Weich: in der Mitte noch unter der Hälfte.
  Assert.IsTrue(TAtlasStickyScroll.FadeWeight(9, 20) < 0.5);
  Assert.AreEqual(1.0, TAtlasStickyScroll.FadeWeight(0, 1), 1e-9, 'eine Pixelzeile');
end;

procedure TAtlasStickyScrollTests.OwnerWordsHaveTheirKind;
var
  mKind: TAtlasStickyKind;
begin
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('if', mKind) and (mKind = TAtlasStickyKind.Branches));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('else', mKind) and (mKind = TAtlasStickyKind.Branches));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('for', mKind) and (mKind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('while', mKind) and (mKind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('repeat', mKind) and (mKind = TAtlasStickyKind.Loops));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('try', mKind) and (mKind = TAtlasStickyKind.TryBlocks));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('case', mKind) and (mKind = TAtlasStickyKind.CaseBlocks));
  Assert.IsTrue(TAtlasStickyScroll.OwnerKind('with', mKind) and (mKind = TAtlasStickyKind.WithBlocks));
  // Ohne Anweisung davor (begin, asm) und Ausnahmezweige (on) bekommen keine eigene Zeile.
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('begin', mKind));
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('asm', mKind));
  Assert.IsFalse(TAtlasStickyScroll.OwnerKind('on', mKind));
end;

/// <summary>Kopf über ATopLine mit den Gliederungsarten AKinds (3 Zeilen, Tabulator 8).</summary>
function KindRows(const ANodes: TAtlasOutlineNodes; const ALines: TArray<string>; AKinds: TAtlasStickyKinds;
  ATopLine: Integer): TAtlasStickyRows;
begin
  Result := TAtlasStickyScroll.Rows(TAtlasStickySource.Create(ANodes, ALines, nil, AKinds), ATopLine, 3, 8);
end;

procedure TAtlasStickyScrollTests.OutlineKindsCanBeSwitchedOff;
var
  mSource: TSource;
begin
  mSource := Build;
  // Klasse: nur mit Types.
  Assert.AreEqual('TForm1 = class(TObject)', Texts(KindRows(mSource.Nodes, mSource.Lines, [TAtlasStickyKind.Types],
    mSource.Marks.FormClass + 2)));
  Assert.AreEqual('', Texts(KindRows(mSource.Nodes, mSource.Lines, [TAtlasStickyKind.Routines],
    mSource.Marks.FormClass + 2)));
  // Routinen: nur mit Routines; ohne beide bleibt der Kopf leer.
  Assert.AreEqual('procedure TForm1.Laden; | function Eins: Integer;', Texts(KindRows(mSource.Nodes, mSource.Lines,
    [TAtlasStickyKind.Routines], mSource.Marks.EinsBody + 5)));
  Assert.AreEqual('', Texts(KindRows(mSource.Nodes, mSource.Lines, [TAtlasStickyKind.Types],
    mSource.Marks.EinsBody + 5)));
  Assert.AreEqual('', Texts(KindRows(mSource.Nodes, mSource.Lines, [], mSource.Marks.EinsBody + 5)));
end;

procedure TAtlasStickyScrollTests.HeaderCharactersMapToTheSource;
const
  cLine = '    function Pruefe(const A: Integer;';
var
  mRow: TAtlasStickyRow;
  mIndex: Integer;
begin
  mRow := Default(TAtlasStickyRow);
  mRow.Text := 'function Pruefe(…): Boolean;';
  mRow.Indent := 4;
  // Name und Klammer im Kopf stehen hinter der Einrückung in der Zeile.
  Assert.IsTrue(TAtlasStickyScroll.SourceIndex(mRow, cLine, 9, mIndex), 'Name');
  Assert.AreEqual(13, mIndex, 'Name');
  Assert.IsTrue(TAtlasStickyScroll.SourceIndex(mRow, cLine, 15, mIndex), 'Klammer');
  Assert.AreEqual(19, mIndex, 'Klammer');
  // „…“ und was dahinter steht, zeigt die Zeile so nicht.
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, cLine, 16, mIndex), '…');
  Assert.AreEqual(-1, mIndex, '…');
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, cLine, 20, mIndex), 'Ergebnistyp');
  // Vor und hinter dem Text des Kopfs.
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, cLine, -1, mIndex), 'Einrückung');
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, cLine, Length(mRow.Text), mIndex), 'dahinter');
  // Zeile inzwischen geändert.
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, '    procedure Pruefe(', 9, mIndex), 'geändert');
  // Tabulator im Text: Danach passen die Spalten nicht mehr.
  mRow.Text := 'a'#9'b';
  Assert.IsTrue(TAtlasStickyScroll.SourceIndex(mRow, #9'a'#9'b', 0, mIndex), 'vor dem Tabulator');
  Assert.AreEqual(1, mIndex, 'vor dem Tabulator');
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, #9'a'#9'b', 2, mIndex), 'hinter dem Tabulator');
  // Zusammenfassung „A › B“ zeigt keine Quellzeile.
  mRow.Text := 'TForm1 › Laden';
  mRow.Summary := True;
  Assert.IsFalse(TAtlasStickyScroll.SourceIndex(mRow, 'TForm1 › Laden', 0, mIndex), 'Zusammenfassung');
  mRow.Text := '';
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStickyScrollTests);

end.
