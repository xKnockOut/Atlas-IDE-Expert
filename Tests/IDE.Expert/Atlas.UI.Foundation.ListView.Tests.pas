unit Atlas.UI.Foundation.ListView.Tests;

// Liste der Atlas-Fenster (#2063): Spaltenbreiten in logischen Pixeln, nach
// einem DPI-Wechsel genau einmal skaliert (nicht doppelt), Sonderbreiten
// unverändert, Berichtsansicht ohne eigene Farben; die füllende Spalte nimmt
// die übrige Breite und wächst mit der Liste; Spalten nach Inhalt, Sortieren
// per Spaltenkopf mit Zahlen als Zahlen.

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
    procedure AddRow(const ACells: array of string; AData: Integer);
    /// <summary>Texte der Spalte AColumn in der Reihenfolge der Liste, mit Komma getrennt.</summary>
    function Column(AColumn: Integer): string;
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
    [Test]
    procedure ContentWidthFitsLongestCell;
    [Test]
    procedure FitToContentCapsAndLeavesFillColumn;
    [Test]
    procedure CompareNaturalTreatsDigitsAsNumbers;
    [Test]
    procedure ColumnClickSortsAndSecondClickReverses;
    [Test]
    procedure SortTieKeepsDataOrder;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.ComCtrls,
  Atlas.Core.Style.Scaling;

type
  /// <summary>Zugriff auf ColClick (Klick auf den Spaltenkopf).</summary>
  TListViewAccess = class(TAtlasListView);

{ TAtlasListViewTests }

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

procedure TAtlasListViewTests.AddRow(const ACells: array of string; AData: Integer);
var
  mItem: TListItem;
  mIndex: Integer;
begin
  mItem := FList.Items.Add;
  mItem.Caption := ACells[0];
  for mIndex := 1 to High(ACells) do
  begin
    mItem.SubItems.Add(ACells[mIndex]);
  end;
  mItem.Data := Pointer(AData);
end;

function TAtlasListViewTests.Column(AColumn: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to FList.Items.Count - 1 do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    if AColumn = 0 then
    begin
      Result := Result + FList.Items[mIndex].Caption;
    end
    else
    begin
      Result := Result + FList.Items[mIndex].SubItems[AColumn - 1];
    end;
  end;
end;

procedure TAtlasListViewTests.ContentWidthFitsLongestCell;
var
  mShort, mLong: Integer;
begin
  FList.AddColumn('Stellen', 20);
  mShort := FList.ContentWidth(0);
  AddRow(['2533 / 16000 und noch viel mehr Text'], 0);
  mLong := FList.ContentWidth(0);
  Assert.IsTrue(mLong > mShort, 'längster Eintrag zählt');
  Assert.IsTrue(mLong > FList.Canvas.TextWidth('2533 / 16000 und noch viel mehr Text'), 'mit Rand');
end;

procedure TAtlasListViewTests.FitToContentCapsAndLeavesFillColumn;
begin
  FList.AddColumn('A', 10);
  FList.AddColumn('Folge', 10);
  FList.AddColumn('B', 10);
  AddRow(['kurz', 'egal', StringOfChar('x', 400)], 0);
  FList.FillColumn(1, 50);
  FList.FitColumnsToContent(150);
  Assert.AreEqual(FList.ContentWidth(0), Integer(FList.Columns[0].Width), 'nach Inhalt');
  Assert.AreEqual(TAtlasScaling.ToDevice(150, FList.CurrentPPI), Integer(FList.Columns[2].Width), 'Obergrenze');
  Assert.AreEqual(FList.ClientWidth - FList.Columns[0].Width - FList.Columns[2].Width,
    Integer(FList.Columns[1].Width), 'füllende Spalte nimmt den Rest');
end;

procedure TAtlasListViewTests.CompareNaturalTreatsDigitsAsNumbers;
begin
  Assert.IsTrue(TAtlasListView.CompareNatural('9 %', '15 %') < 0, '9 vor 15');
  Assert.IsTrue(TAtlasListView.CompareNatural('2533 / 16000', '1245 / 16000') > 0, '2533 nach 1245');
  Assert.IsTrue(TAtlasListView.CompareNatural('Datei2', 'datei10') < 0, 'ohne Groß-/Kleinschreibung');
  Assert.AreEqual(0, TAtlasListView.CompareNatural('007', '7'), 'führende Nullen');
  Assert.IsTrue(TAtlasListView.CompareNatural('abc', 'abcd') < 0, 'kürzer zuerst');
  Assert.IsTrue(TAtlasListView.CompareNatural('', 'a') < 0, 'leer zuerst');
end;

procedure TAtlasListViewTests.ColumnClickSortsAndSecondClickReverses;
begin
  FList.AddColumn('Auslöser', 100);
  FList.AddColumn('Anteil', 60);
  AddRow(['b', '15 %'], 0);
  AddRow(['a', '9 %'], 1);
  AddRow(['c', '100 %'], 2);
  FList.Sortable := True;
  TListViewAccess(FList).ColClick(FList.Columns[1]);
  Assert.AreEqual('9 %,15 %,100 %', Column(1), 'aufsteigend');
  Assert.AreEqual(1, FList.SortColumn);
  Assert.IsFalse(FList.SortDescending);
  TListViewAccess(FList).ColClick(FList.Columns[1]);
  Assert.AreEqual('100 %,15 %,9 %', Column(1), 'zweiter Klick kehrt um');
  Assert.IsTrue(FList.SortDescending);
  TListViewAccess(FList).ColClick(FList.Columns[0]);
  Assert.AreEqual('a,b,c', Column(0), 'andere Spalte wieder aufsteigend');
end;

procedure TAtlasListViewTests.SortTieKeepsDataOrder;
begin
  FList.AddColumn('Name', 100);
  AddRow(['x'], 2);
  AddRow(['x'], 0);
  AddRow(['x'], 1);
  FList.SortBy(0, False);
  Assert.AreEqual(0, Integer(NativeInt(FList.Items[0].Data)));
  Assert.AreEqual(1, Integer(NativeInt(FList.Items[1].Data)));
  Assert.AreEqual(2, Integer(NativeInt(FList.Items[2].Data)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasListViewTests);

end.
