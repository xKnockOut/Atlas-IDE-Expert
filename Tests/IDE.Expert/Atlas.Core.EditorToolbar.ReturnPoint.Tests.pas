unit Atlas.Core.EditorToolbar.ReturnPoint.Tests;

// Atlas-Editorleiste (#1101): Rücksprung „Zurück zu Zeile …“. Erster
// Ausgangspunkt bleibt, Zeilen oberhalb verschieben ihn, Rückkehr auf die
// Zeile erledigt ihn, je Datei getrennt, geschlossene Dateien vergessen;
// Methode der Ausgangszeile für den Tooltip.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasReturnPointsTests = class
  private
    FPoints: TObject;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FirstOriginStays;
    [Test]
    procedure LinesAboveMoveThePoint;
    [Test]
    procedure ReturningToTheLineFinishes;
    [Test]
    procedure PerFileAndClosedFiles;
    [Test]
    procedure ContextIsTheEnclosingMethod;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.EditorToolbar.ReturnPoint;

const
  FileA = 'C:\Projekt\uKundeForm.pas';
  FileB = 'C:\Projekt\uKundeDaten.pas';

function Points(ATests: TAtlasReturnPointsTests): TAtlasReturnPoints;
begin
  Result := TAtlasReturnPoints(ATests.FPoints);
end;

procedure TAtlasReturnPointsTests.Setup;
begin
  FPoints := TAtlasReturnPoints.Create;
end;

procedure TAtlasReturnPointsTests.TearDown;
begin
  FreeAndNil(FPoints);
end;

procedure TAtlasReturnPointsTests.FirstOriginStays;
var
  Point: TAtlasReturnPoint;
begin
  Assert.IsFalse(Points(Self).Find(FileA, Point));
  // Abschnittssprung von Zeile 213 (Editor 214) zum interface, dann zum implementation-Teil.
  Points(Self).Jumped(FileA, 213, 2, 'TfrmKunde.btnSpeichernClick');
  Points(Self).Jumped(FileA, 2, 40, '');
  Assert.IsTrue(Points(Self).Find(FileA, Point));
  Assert.AreEqual(213, Point.Line, 'erster Ausgangspunkt');
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', Point.Context);
  Assert.AreEqual(FileA, Point.FileName);
  // Sprung auf dieselbe Zeile: nichts zu merken.
  Points(Self).Jumped(FileB, 5, 5, '');
  Assert.IsFalse(Points(Self).Find(FileB, Point));
  Points(Self).Jumped('', 1, 2, '');
  Assert.AreEqual(1, Points(Self).Count);
end;

procedure TAtlasReturnPointsTests.LinesAboveMoveThePoint;
var
  Point: TAtlasReturnPoint;
begin
  Points(Self).Jumped(FileA, 213, 2, '');
  // Zwei Zeilen im interface eingefügt: Die Zeilennummer wandert mit.
  Points(Self).LinesChanged(FileA, 4, 2);
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(215, Point.Line);
  // Darunter eingefügt: bleibt.
  Points(Self).LinesChanged(FileA, 300, 5);
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(215, Point.Line);
  // Andere Datei: bleibt.
  Points(Self).LinesChanged(FileB, 0, 10);
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(215, Point.Line);
  // Darüber gelöscht.
  Points(Self).LinesChanged(FileA, 10, -5);
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(210, Point.Line);
  // Die Zeile selbst gelöscht: an die Stelle der Löschung.
  Points(Self).LinesChanged(FileA, 205, -10);
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(205, Point.Line);
end;

procedure TAtlasReturnPointsTests.ReturningToTheLineFinishes;
var
  Point: TAtlasReturnPoint;
begin
  Points(Self).Jumped(FileA, 213, 2, '');
  Assert.IsFalse(Points(Self).Caret(FileA, 2), 'am Ziel');
  Assert.IsFalse(Points(Self).Caret(FileA, 3), 'Tippen am Ziel');
  Assert.IsFalse(Points(Self).Caret(FileB, 213), 'andere Datei');
  Assert.IsTrue(Points(Self).Caret(FileA, 213), 'zurück (Klick oder Alt+←)');
  Assert.IsFalse(Points(Self).Find(FileA, Point), 'Knopf verschwindet');
  Assert.IsFalse(Points(Self).Caret(FileA, 213), 'nichts mehr zu erledigen');
  // Nach dem Rücksprung beginnt ein neuer Abschnittssprung wieder vorn.
  Points(Self).Jumped(FileA, 100, 2, '');
  Points(Self).Find(FileA, Point);
  Assert.AreEqual(100, Point.Line);
end;

procedure TAtlasReturnPointsTests.PerFileAndClosedFiles;
var
  Point: TAtlasReturnPoint;
begin
  Points(Self).Jumped(FileA, 213, 2, '');
  Points(Self).Jumped(FileB, 50, 3, '');
  Assert.AreEqual(2, Points(Self).Count);
  Assert.IsTrue(Points(Self).Find(UpperCase(FileB), Point), 'Dateiname ohne Groß-/Kleinschreibung');
  Assert.AreEqual(50, Point.Line);
  Points(Self).KeepOnly([FileA]);
  Assert.IsFalse(Points(Self).Find(FileB, Point), 'Datei geschlossen');
  Assert.IsTrue(Points(Self).Find(FileA, Point));
  Points(Self).Forget(FileA);
  Assert.AreEqual(0, Points(Self).Count);
  Points(Self).Jumped(FileA, 9, 2, '');
  Points(Self).Clear;
  Assert.AreEqual(0, Points(Self).Count);
end;

procedure TAtlasReturnPointsTests.ContextIsTheEnclosingMethod;
const
  Code =
    'unit U;'#10 +                                            // 0
    'interface'#10 +                                          // 1
    'type'#10 +                                               // 2
    '  TfrmKunde = class'#10 +                                // 3
    '    procedure btnSpeichernClick(Sender: TObject);'#10 +  // 4
    '  end;'#10 +                                             // 5
    'implementation'#10 +                                     // 6
    'procedure TfrmKunde.btnSpeichernClick(Sender: TObject);'#10 + // 7
    '  procedure Pruefe;'#10 +                                // 8
    '  begin'#10 +                                            // 9
    '  end;'#10 +                                             // 10
    'begin'#10 +                                              // 11
    '  Pruefe;'#10 +                                          // 12
    'end;'#10 +                                               // 13
    'procedure Hilfe;'#10 +                                   // 14
    'begin'#10 +                                              // 15
    'end;'#10 +                                               // 16
    'end.';
var
  Tree: TSyntaxTree;
  Symbols: TJSONArray;
  Nodes: TAtlasOutlineNodes;
begin
  Tree := TPascalParser.Parse(Code);
  try
    Symbols := TLspDocumentSymbols.BuildSymbols(Tree, Code);
  finally
    Tree.Free;
  end;
  try
    Nodes := TAtlasOutline.FromJson(Symbols);
  finally
    Symbols.Free;
  end;
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', TAtlasReturnPoints.ContextAt(Nodes, 12));
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', TAtlasReturnPoints.ContextAt(Nodes, 4), 'Deklaration');
  Assert.AreEqual('Hilfe', TAtlasReturnPoints.ContextAt(Nodes, 15));
  Assert.AreEqual('', TAtlasReturnPoints.ContextAt(Nodes, 1));
  Assert.AreEqual('', TAtlasReturnPoints.ContextAt(nil, 12));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReturnPointsTests);

end.
