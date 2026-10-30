unit Atlas.UI.Designer.Bar.Tests;

// Designer-Leiste (#1442), Darstellung: feste Höhe, Suchfeld links, Zähler und
// Pfeile nur mit Suchwort, „Alle einblenden“ nur mit Ausgeblendeten, Klicks
// und Tasten im Suchfeld erreichen ihre Ereignisse.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Designer.Bar;

type
  [TestFixture]
  TAtlasDesignerBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasDesignerBar;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure PartsFollowSearchAndHidden;
    [Test]
    procedure SearchAndKeysReachEvents;
    [Test]
    procedure ClicksReachEvents;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls;

function Middle(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

procedure TAtlasDesignerBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 300;
  FBar := TAtlasDesignerBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
  FBar.SetTexts('Komponente suchen …', '%d/%d', 'kein Treffer', 'Ausblenden ▾', 'Alle einblenden (%d)',
    'Voriger Treffer', 'Nächster Treffer', 'Nur im Designer');
end;

procedure TAtlasDesignerBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasDesignerBarTests.PartsFollowSearchAndHidden;
var
  mHeight: Integer;
begin
  mHeight := FBar.Height;
  Assert.AreEqual(TAtlasDesignerBar.BarHeight(FBar.CurrentPPI), mHeight, 'eine Zeile');
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartPrevious).IsEmpty, 'ohne Suchwort keine Pfeile');
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartNext).IsEmpty);
  Assert.IsFalse(FBar.PartRect(TAtlasDesignerBar.PartHide).IsEmpty, 'Ausblenden immer');
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartShowAll).IsEmpty, 'nichts ausgeblendet');
  Assert.IsTrue(FBar.Search.Left + FBar.Search.Width <= FBar.PartRect(TAtlasDesignerBar.PartHide).Left,
    'Suchfeld links');
  FBar.Search.Text := 'btn';
  Assert.IsFalse(FBar.PartRect(TAtlasDesignerBar.PartPrevious).IsEmpty, 'mit Suchwort Pfeile');
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartPrevious).Right <= FBar.PartRect(TAtlasDesignerBar.PartNext).Left);
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartNext).Right <= FBar.PartRect(TAtlasDesignerBar.PartHide).Left);
  FBar.SetHiddenCount(3);
  Assert.IsFalse(FBar.PartRect(TAtlasDesignerBar.PartShowAll).IsEmpty, 'mit Ausgeblendeten');
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartHide).Right <= FBar.PartRect(TAtlasDesignerBar.PartShowAll).Left);
  FBar.SetHiddenCount(0);
  Assert.IsTrue(FBar.PartRect(TAtlasDesignerBar.PartShowAll).IsEmpty);
  FBar.Height := mHeight * 2;
  Assert.AreEqual(mHeight, FBar.Height, 'nie höher');
end;

procedure TAtlasDesignerBarTests.SearchAndKeysReachEvents;
var
  mSearched: string;
  mSteps: TArray<Integer>;
  mKey: Word;
  mChar: Char;
begin
  mSearched := '#';
  mSteps := nil;
  FBar.OnSearch :=
    procedure(AText: string)
    begin
      mSearched := AText;
    end;
  FBar.OnStep :=
    procedure(ADelta: Integer)
    begin
      mSteps := mSteps + [ADelta];
    end;
  FBar.Search.Text := ' lbl ';
  Assert.AreEqual('lbl', mSearched, 'ohne Leerzeichen am Rand');
  mKey := VK_RETURN;
  FBar.Search.OnKeyDown(FBar.Search, mKey, []);
  Assert.AreEqual(0, Integer(mKey), 'Enter verbraucht');
  mKey := VK_RETURN;
  FBar.Search.OnKeyDown(FBar.Search, mKey, [ssShift]);
  mKey := VK_DOWN;
  FBar.Search.OnKeyDown(FBar.Search, mKey, []);
  mKey := VK_UP;
  FBar.Search.OnKeyDown(FBar.Search, mKey, []);
  Assert.AreEqual(4, Integer(Length(mSteps)));
  Assert.AreEqual(1, mSteps[0]);
  Assert.AreEqual(-1, mSteps[1]);
  Assert.AreEqual(1, mSteps[2]);
  Assert.AreEqual(-1, mSteps[3]);
  mKey := Ord('A');
  FBar.Search.OnKeyDown(FBar.Search, mKey, []);
  Assert.AreEqual(Ord('A'), Integer(mKey), 'andere Tasten bleiben im Feld');
  mKey := VK_ESCAPE;
  FBar.Search.OnKeyDown(FBar.Search, mKey, []);
  Assert.AreEqual('', FBar.Search.Text, 'Esc leert das Feld');
  Assert.AreEqual('', mSearched);
  mChar := #13;
  FBar.Search.OnKeyPress(FBar.Search, mChar);
  Assert.AreEqual(Ord(#0), Ord(mChar), 'kein Signalton');
end;

procedure TAtlasDesignerBarTests.ClicksReachEvents;
var
  mSteps, mShowAll: Integer;
  mMenuAt: TPoint;
  mPoint: TPoint;
begin
  mSteps := 0;
  mShowAll := 0;
  mMenuAt := Point(-1, -1);
  FBar.OnStep :=
    procedure(ADelta: Integer)
    begin
      Inc(mSteps, ADelta);
    end;
  FBar.OnHideMenu :=
    procedure(APoint: TPoint)
    begin
      mMenuAt := APoint;
    end;
  FBar.OnShowAll :=
    procedure
    begin
      Inc(mShowAll);
    end;
  FBar.Search.Text := 'btn';
  FBar.SetHits(0, 1);
  mPoint := Middle(FBar.PartRect(TAtlasDesignerBar.PartNext));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(0, mSteps, 'ein Treffer: nichts weiterzuschalten');
  FBar.SetHits(1, 3);
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, mSteps);
  mPoint := Middle(FBar.PartRect(TAtlasDesignerBar.PartPrevious));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(0, mSteps, 'zurück');
  mPoint := Middle(FBar.PartRect(TAtlasDesignerBar.PartHide));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(FBar.ClientToScreen(Point(FBar.PartRect(TAtlasDesignerBar.PartHide).Left, FBar.ClientHeight)).X,
    mMenuAt.X, 'Menü unter dem Knopf');
  FBar.SetHiddenCount(2);
  mPoint := Middle(FBar.PartRect(TAtlasDesignerBar.PartShowAll));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, mShowAll);
end;

end.
