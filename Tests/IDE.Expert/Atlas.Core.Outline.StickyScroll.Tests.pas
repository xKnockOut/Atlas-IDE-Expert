unit Atlas.Core.Outline.StickyScroll.Tests;

// Mitlaufender Kopf (#506): Kopf einer langen Methode, äußerer und innerer
// Kopf untereinander, nach inneren Routinen nur der äußere, Zusammenfassung
// bei vier Ebenen, gekürzte mehrzeilige Köpfe, Klasse im interface,
// Sprungziel.

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
  Atlas.Core.Outline.StickyScroll;

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

initialization
  TDUnitX.RegisterTestFixture(TAtlasStickyScrollTests);

end.
