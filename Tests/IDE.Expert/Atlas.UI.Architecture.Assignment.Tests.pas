unit Atlas.UI.Architecture.Assignment.Tests;

// Zuordnung einer Unit im Fenster „Atlas-Architektur“ (#1368): Kopf, Zeilen,
// Knapp-Zeile und -Markierung, „zählt nicht“ beim Fundament, Erklärung mit
// den Einstellungen, Messen und Zeichnen, Hinweis über der Karte.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  TAtlasArchitectureAssignmentTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TextsOfCloseUnit;
    [Test]
    procedure FoundationRowDoesNotCount;
    [Test]
    procedure ExplanationNamesSettings;
    [Test]
    procedure MeasuresAndDraws;
    [Test]
    procedure MapShowsHoverAssignment;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Architecture.Model,
  Atlas.Core.Architecture.Model.Tests,
  Atlas.UI.Architecture.Map,
  Atlas.UI.Architecture.Assignment;

type
  /// <summary>Zugang zu den geschützten Mausmethoden der Karte.</summary>
  TMapAccess = class(TAtlasArchitectureMap);

function ModelOf(const AAnswer: string): TAtlasArchitectureModel;
var
  mEnabled: Boolean;
begin
  Assert.IsTrue(TAtlasArchitectureModel.Parse(AAnswer, Result, mEnabled));
end;

procedure TAtlasArchitectureAssignmentTests.SetUp;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasArchitectureAssignmentTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasArchitectureAssignmentTests.TextsOfCloseUnit;
var
  mModel: TAtlasArchitectureModel;
  mMid, mU1: Integer;
  mCells: TArray<string>;
begin
  mModel := ModelOf(SampleAssignmentAnswer);
  mMid := mModel.IndexOf('Z.Own.Mid');
  Assert.IsTrue(TAtlasArchitectureAssignment.Available(mModel, mMid));
  Assert.AreEqual('Teilsystem Own, weil die meisten Kanten dorthin gehen:', TAtlasArchitectureAssignment.Head(mModel,
    mMid));
  mCells := TAtlasArchitectureAssignment.Cells(mModel, mMid, 0);
  Assert.AreEqual('Own|3 × interface|2 × impl.|= 8', string.Join('|', mCells));
  mCells := TAtlasArchitectureAssignment.Cells(mModel, mMid, 1);
  Assert.AreEqual('Oth|2 × interface|2 × impl.|= 6', string.Join('|', mCells));
  Assert.AreEqual(0, Integer(Length(TAtlasArchitectureAssignment.Cells(mModel, mMid, 2))));
  Assert.AreEqual('Knapp: Mit 3 weiteren Kanten zu Oth läge sie dort.', TAtlasArchitectureAssignment.CloseLine(mModel,
    mMid));
  Assert.AreEqual('knapp, 3 Kanten fehlen zu Oth', TAtlasArchitectureAssignment.CloseMark(mModel, mMid));
  // Klar zugeordnet: keine Knapp-Zeile.
  mU1 := mModel.IndexOf('Z.Own.U1');
  Assert.AreEqual('', TAtlasArchitectureAssignment.CloseLine(mModel, mU1));
  Assert.AreEqual('', TAtlasArchitectureAssignment.CloseMark(mModel, mU1));
  // Eine fehlende Kante und Gleichstand.
  mModel.Units[mMid].Missing := 1;
  Assert.AreEqual('Knapp: Mit einer weiteren Kante zu Oth läge sie dort.',
    TAtlasArchitectureAssignment.CloseLine(mModel, mMid));
  Assert.AreEqual('knapp, 1 Kante fehlt zu Oth', TAtlasArchitectureAssignment.CloseMark(mModel, mMid));
  mModel.Units[mMid].Missing := 0;
  Assert.AreEqual('Knapp: Oth hat schon 6 gewichtete Kanten, das eigene Teilsystem 8.',
    TAtlasArchitectureAssignment.CloseLine(mModel, mMid));
  Assert.AreEqual('Teilsystem Own, Kanten je Teilsystem:', TAtlasArchitectureAssignment.Head(mModel, mMid));
  // Ohne Zuordnung vom Server: nichts.
  mModel := ModelOf(SampleAnswer);
  Assert.IsFalse(TAtlasArchitectureAssignment.Available(mModel, 0));
  Assert.AreEqual('', TAtlasArchitectureAssignment.Head(mModel, 0));
  Assert.AreEqual('', TAtlasArchitectureAssignment.CloseMark(mModel, 0));
  Assert.IsFalse(TAtlasArchitectureAssignment.Available(mModel, -1));
end;

procedure TAtlasArchitectureAssignmentTests.FoundationRowDoesNotCount;
var
  mModel: TAtlasArchitectureModel;
  mU2, mRow: Integer;
  mFound: Boolean;
begin
  mModel := ModelOf(SampleAssignmentFoundationAnswer);
  mU2 := mModel.IndexOf('App.Ui.U2');
  mFound := False;
  for mRow := 0 to High(mModel.Units[mU2].Assignment) do
    if not mModel.Units[mU2].Assignment[mRow].Counts then
    begin
      mFound := True;
      Assert.AreEqual('Fundament|1 × interface|0 × impl.|zählt nicht',
        string.Join('|', TAtlasArchitectureAssignment.Cells(mModel, mU2, mRow)));
    end;
  Assert.IsTrue(mFound);
end;

procedure TAtlasArchitectureAssignmentTests.ExplanationNamesSettings;
var
  mModel: TAtlasArchitectureModel;
  mText: string;
begin
  mModel := ModelOf(SampleAssignmentAnswer);
  mText := TAtlasArchitectureAssignment.Explanation(mModel);
  Assert.Contains(mText, 'Louvain');
  Assert.Contains(mText, 'Einstellungen: Feinheit ' + TAtlasArchResolution.Text(1, FormatSettings) +
    ' · nachteilen nach Größe ab 25 Prozent der Units · nach Zusammenhalt unter ' +
    TAtlasArchResolution.Text(0.3, FormatSettings) + ' · Fundamente getrennt.');
  mModel := ModelOf(SampleAssignmentFoundationAnswer);
  mModel.Foundations := 'attach';
  mText := TAtlasArchitectureAssignment.Explanation(mModel);
  Assert.Contains(mText, '· nachteilen nach Größe aus · nach Zusammenhalt aus · Fundamente angehängt.');
  mModel.Foundations := 'group';
  Assert.Contains(TAtlasArchitectureAssignment.Explanation(mModel), 'Fundamente mitgruppiert.');
  // Englisch.
  TAtlasStrings.Language := TAtlasLanguage.English;
  Assert.Contains(TAtlasArchitectureAssignment.Explanation(mModel), 'foundations grouped.');
end;

procedure TAtlasArchitectureAssignmentTests.MeasuresAndDraws;
var
  mModel: TAtlasArchitectureModel;
  mBitmap: TBitmap;
  mSize: TSize;
  mMid, mLine: Integer;
  mColors: TAtlasColors;
begin
  mModel := ModelOf(SampleAssignmentAnswer);
  mMid := mModel.IndexOf('Z.Own.Mid');
  mColors := TAtlasColors.Light;
  mBitmap := TBitmap.Create;
  try
    mBitmap.SetSize(800, 400);
    mBitmap.Canvas.Brush.Color := clFuchsia;
    mBitmap.Canvas.FillRect(Rect(0, 0, 800, 400));
    mSize := TAtlasArchitectureAssignment.Measure(mBitmap.Canvas, mModel, mMid, 96);
    mLine := mBitmap.Canvas.TextHeight('Ag') + 2;
    // Name, Kopf, zwei Zeilen, Knapp-Zeile.
    Assert.AreEqual(2 * TAtlasArchitectureAssignment.cPadding + 5 * mLine, Integer(mSize.cy));
    Assert.IsTrue(mSize.cx > mBitmap.Canvas.TextWidth(TAtlasArchitectureAssignment.CloseLine(mModel, mMid)));
    TAtlasArchitectureAssignment.Draw(mBitmap.Canvas, Rect(10, 10, 10 + mSize.cx, 10 + mSize.cy), mModel, mMid, 96,
      mColors);
    // Rand in Linienfarbe, innen die Fläche.
    Assert.AreEqual(Integer(TColor(mColors.Line)), Integer(mBitmap.Canvas.Pixels[10, 10]));
    Assert.AreEqual(Integer(TColor(mColors.Surface)), Integer(mBitmap.Canvas.Pixels[12, 10 + mSize.cy - 2]));
    Assert.AreEqual(Integer(clFuchsia), Integer(mBitmap.Canvas.Pixels[11 + mSize.cx, 11 + mSize.cy]));
    // Ohne Zuordnung: nichts zu messen und zu zeichnen.
    mModel := ModelOf(SampleAnswer);
    mSize := TAtlasArchitectureAssignment.Measure(mBitmap.Canvas, mModel, 0, 96);
    Assert.AreEqual(0, Integer(mSize.cx));
    TAtlasArchitectureAssignment.Draw(mBitmap.Canvas, Rect(500, 300, 600, 380), mModel, 0, 96, mColors);
    Assert.AreEqual(Integer(clFuchsia), Integer(mBitmap.Canvas.Pixels[500, 300]));
  finally
    mBitmap.Free;
  end;
end;

procedure TAtlasArchitectureAssignmentTests.MapShowsHoverAssignment;
var
  mForm: TForm;
  mMap: TMapAccess;
  mMid: Integer;
begin
  mForm := TForm.CreateNew(nil);
  try
    mForm.Width := 900;
    mForm.Height := 600;
    mMap := TMapAccess.Create(mForm);
    mMap.Parent := mForm;
    mMap.SetBounds(0, 0, 800, 500);
    mMap.SetModel(ModelOf(SampleAssignmentAnswer));
    mMap.FitView;
    mMid := mMap.Model.IndexOf('Z.Own.Mid');
    Assert.IsTrue(mMap.ShowAssignment);
    Assert.AreEqual(-1, mMap.Hover);
    mMap.MouseMove([], Round(mMap.View.ScreenX(mMap.Model.Units[mMid].X)),
      Round(mMap.View.ScreenY(mMap.Model.Units[mMid].Y)));
    Assert.AreEqual(mMid, mMap.Hover);
    // Zeichnen mit Hinweis wirft nicht.
    mMap.Repaint;
    mMap.Perform(CM_MOUSELEAVE, 0, 0);
    Assert.AreEqual(-1, mMap.Hover);
    mMap.ShowAssignment := False;
    Assert.IsFalse(mMap.ShowAssignment);
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasArchitectureAssignmentTests);

end.
