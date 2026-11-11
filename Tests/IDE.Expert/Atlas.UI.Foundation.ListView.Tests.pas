unit Atlas.UI.Foundation.ListView.Tests;

// Liste der Atlas-Fenster (#2063): Spaltenbreiten in logischen Pixeln, nach
// einem DPI-Wechsel genau einmal skaliert (nicht doppelt), Sonderbreiten
// unverändert, Berichtsansicht ohne eigene Farben.

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
  FForm.Width := 600;
  FForm.Height := 300;
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
  Assert.IsTrue(mColumn.Alignment = taRightJustify);
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
  Assert.IsTrue(FList.ViewStyle = vsReport);
  Assert.AreEqual(Integer(clWindow), Integer(FList.Color));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasListViewTests);

end.
