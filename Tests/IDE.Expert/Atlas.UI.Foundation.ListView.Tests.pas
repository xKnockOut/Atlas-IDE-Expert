unit Atlas.UI.Foundation.ListView.Tests;

// Liste der Atlas-Fenster (#2063): Spaltenbreiten in logischen Pixeln, nach
// einem DPI-Wechsel genau einmal skaliert (nicht doppelt), Sonderbreiten
// unverändert, Berichtsansicht ohne eigene Farben; die füllende Spalte nimmt
// die übrige Breite und wächst mit der Liste.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Foundation.ListView;

type
  [TestFixture]
  TAtlasListViewTests = class
  private
    FForm: TForm;
    FList: TAtlasListView;
  public
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ColumnWidthIsLogical;
    [Test]
    procedure DpiChangeScalesColumnsOnce;
    [Test]
    procedure AutoSizeWidthsStay;
    [Test]
    procedure ReportViewWithoutOwnColors;
    [Test]
    procedure FillColumnTakesRestAndKeepsMinimum;
  end;

implementation

uses
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ComCtrls,
  Atlas.Core.Style.Scaling;

procedure TAtlasListViewTests.WarmUpFirstUse;
begin
  // Erste Benutzung (Liste mit Fenster, DPI-Wechsel) nicht dem ersten Test anrechnen.
  SetUp;
  try
    FList.AddColumn('Name', 100);
    FForm.ScaleForPPI(FForm.CurrentPPI * 3 div 2);
    FForm.ScaleForPPI(FForm.CurrentPPI * 2 div 3);
  finally
    TearDown;
  end;
end;

procedure TAtlasListViewTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := FForm.ScaleValue(600);
  FForm.Height := FForm.ScaleValue(300);
  FList := TAtlasListView.Create(FForm);
  FList.Parent := FForm;
  FList.Align := alClient;
end;

procedure TAtlasListViewTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FList := nil;
end;

procedure TAtlasListViewTests.ColumnWidthIsLogical;
var
  mColumn: TListColumn;
begin
  // Windows richtet die erste Spalte immer links aus: Ausrichtung an der zweiten prüfen.
  FList.AddColumn('Erste', 50);
  mColumn := FList.AddColumn('Name', 120, taRightJustify);
  Assert.AreEqual(TAtlasScaling.ToDevice(120, FList.CurrentPPI), Integer(mColumn.Width));
  Assert.AreEqual('Name', string(mColumn.Caption));
  Assert.AreEqual<TAlignment>(taRightJustify, mColumn.Alignment);
end;

procedure TAtlasListViewTests.DpiChangeScalesColumnsOnce;
var
  mBefore, mPPI: Integer;
begin
  FList.AddColumn('Name', 100);
  mBefore := FList.Columns[0].Width;
  mPPI := FForm.CurrentPPI;
  FForm.ScaleForPPI(mPPI * 3 div 2);
  Assert.AreEqual((mBefore * 3 + 1) div 2, Integer(FList.Columns[0].Width));
  // Zurück: wieder die alte Breite.
  FForm.ScaleForPPI(mPPI);
  Assert.AreEqual(mBefore, Integer(FList.Columns[0].Width));
end;

procedure TAtlasListViewTests.AutoSizeWidthsStay;
begin
  FList.AddColumn('Rest', -2);
  Assert.AreEqual(-2, Integer(FList.Columns[0].Width));
end;

procedure TAtlasListViewTests.ReportViewWithoutOwnColors;
begin
  Assert.AreEqual<TViewStyle>(vsReport, FList.ViewStyle);
  Assert.AreEqual(Integer(clWindow), Integer(FList.Color));
end;

procedure TAtlasListViewTests.FillColumnTakesRestAndKeepsMinimum;
var
  mFixed: Integer;
begin
  FList.AddColumn('Taste', 100);
  FList.AddColumn('Befehl', 120);
  FList.AddColumn('Hinweis', 50);
  mFixed := FList.Columns[0].Width + FList.Columns[1].Width;
  FList.FillColumn(2, 80);
  Assert.AreEqual(FList.ClientWidth - mFixed, Integer(FList.Columns[2].Width), 'übrige Breite');
  // Breiter: die Spalte wächst mit.
  FForm.Width := FForm.ScaleValue(900);
  Assert.AreEqual(FList.ClientWidth - mFixed, Integer(FList.Columns[2].Width), 'wächst mit dem Fenster');
  // Zu schmal: Mindestbreite, die anderen Spalten bleiben.
  FForm.Width := FForm.ScaleValue(200);
  Assert.AreEqual(TAtlasScaling.ToDevice(80, FList.CurrentPPI), Integer(FList.Columns[2].Width), 'Mindestbreite');
  Assert.AreEqual(TAtlasScaling.ToDevice(100, FList.CurrentPPI), Integer(FList.Columns[0].Width));
  // Abgeschaltet: Breite bleibt beim Größenwechsel.
  FList.FillColumn(-1, 0);
  FForm.Width := FForm.ScaleValue(700);
  Assert.AreEqual(TAtlasScaling.ToDevice(80, FList.CurrentPPI), Integer(FList.Columns[2].Width), 'ohne Füllen fest');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasListViewTests);

end.
