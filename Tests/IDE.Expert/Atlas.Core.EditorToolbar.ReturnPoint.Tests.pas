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
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DocumentSymbols,
  Atlas.Core.Outline.Model,
  Atlas.Core.EditorToolbar.ReturnPoint;

const
  cFileA = 'C:\Projekt\uKundeForm.pas';
  cFileB = 'C:\Projekt\uKundeDaten.pas';

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
  mPoint: TAtlasReturnPoint;
begin
  Assert.IsFalse(Points(Self).Find(cFileA, mPoint));
  // Abschnittssprung von Zeile 213 (Editor 214) zum interface, dann zum implementation-Teil.
  Points(Self).Jumped(cFileA, 213, 2, 'TfrmKunde.btnSpeichernClick');
  Points(Self).Jumped(cFileA, 2, 40, '');
  Assert.IsTrue(Points(Self).Find(cFileA, mPoint));
  Assert.AreEqual(213, mPoint.Line, 'erster Ausgangspunkt');
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', mPoint.Context);
  Assert.AreEqual(cFileA, mPoint.FileName);
  // Sprung auf dieselbe Zeile: nichts zu merken.
  Points(Self).Jumped(cFileB, 5, 5, '');
  Assert.IsFalse(Points(Self).Find(cFileB, mPoint));
  Points(Self).Jumped('', 1, 2, '');
  Assert.AreEqual(1, Integer(Points(Self).Count));
end;

procedure TAtlasReturnPointsTests.LinesAboveMoveThePoint;
var
  mPoint: TAtlasReturnPoint;
begin
  Points(Self).Jumped(cFileA, 213, 2, '');
  // Zwei Zeilen im interface eingefügt: Die Zeilennummer wandert mit.
  Points(Self).LinesChanged(cFileA, 4, 2);
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(215, mPoint.Line);
  // Darunter eingefügt: bleibt.
  Points(Self).LinesChanged(cFileA, 300, 5);
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(215, mPoint.Line);
  // Andere Datei: bleibt.
  Points(Self).LinesChanged(cFileB, 0, 10);
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(215, mPoint.Line);
  // Darüber gelöscht.
  Points(Self).LinesChanged(cFileA, 10, -5);
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(210, mPoint.Line);
  // Die Zeile selbst gelöscht: an die Stelle der Löschung.
  Points(Self).LinesChanged(cFileA, 205, -10);
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(205, mPoint.Line);
end;

procedure TAtlasReturnPointsTests.ReturningToTheLineFinishes;
var
  mPoint: TAtlasReturnPoint;
begin
  Points(Self).Jumped(cFileA, 213, 2, '');
  Assert.IsFalse(Points(Self).Caret(cFileA, 2), 'am Ziel');
  Assert.IsFalse(Points(Self).Caret(cFileA, 3), 'Tippen am Ziel');
  Assert.IsFalse(Points(Self).Caret(cFileB, 213), 'andere Datei');
  Assert.IsTrue(Points(Self).Caret(cFileA, 213), 'zurück (Klick oder Alt+←)');
  Assert.IsFalse(Points(Self).Find(cFileA, mPoint), 'Knopf verschwindet');
  Assert.IsFalse(Points(Self).Caret(cFileA, 213), 'nichts mehr zu erledigen');
  // Nach dem Rücksprung beginnt ein neuer Abschnittssprung wieder vorn.
  Points(Self).Jumped(cFileA, 100, 2, '');
  Points(Self).Find(cFileA, mPoint);
  Assert.AreEqual(100, mPoint.Line);
end;

procedure TAtlasReturnPointsTests.PerFileAndClosedFiles;
var
  mPoint: TAtlasReturnPoint;
begin
  Points(Self).Jumped(cFileA, 213, 2, '');
  Points(Self).Jumped(cFileB, 50, 3, '');
  Assert.AreEqual(2, Integer(Points(Self).Count));
  Assert.IsTrue(Points(Self).Find(UpperCase(cFileB), mPoint), 'Dateiname ohne Groß-/Kleinschreibung');
  Assert.AreEqual(50, mPoint.Line);
  Points(Self).KeepOnly([cFileA]);
  Assert.IsFalse(Points(Self).Find(cFileB, mPoint), 'Datei geschlossen');
  Assert.IsTrue(Points(Self).Find(cFileA, mPoint));
  Points(Self).Forget(cFileA);
  Assert.AreEqual(0, Integer(Points(Self).Count));
  Points(Self).Jumped(cFileA, 9, 2, '');
  Points(Self).Clear;
  Assert.AreEqual(0, Integer(Points(Self).Count));
end;

procedure TAtlasReturnPointsTests.ContextIsTheEnclosingMethod;
const
  cCode =
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
  mTree: TSyntaxTree;
  mSymbols: TJSONArray;
  mNodes: TAtlasOutlineNodes;
begin
  mTree := TPascalParser.Parse(cCode);
  try
    mSymbols := TLspDocumentSymbols.BuildSymbols(mTree, cCode);
  finally
    mTree.Free;
  end;
  try
    mNodes := TAtlasOutline.FromJson(mSymbols);
  finally
    mSymbols.Free;
  end;
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', TAtlasReturnPoints.ContextAt(mNodes, 12));
  Assert.AreEqual('TfrmKunde.btnSpeichernClick', TAtlasReturnPoints.ContextAt(mNodes, 4), 'Deklaration');
  Assert.AreEqual('Hilfe', TAtlasReturnPoints.ContextAt(mNodes, 15));
  Assert.AreEqual('', TAtlasReturnPoints.ContextAt(mNodes, 1));
  Assert.AreEqual('', TAtlasReturnPoints.ContextAt(nil, 12));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReturnPointsTests);

end.
