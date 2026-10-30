unit Atlas.UI.Designer.Bar.Tests;

// Designer-Leiste (#1442), Darstellung: feste Höhe, Knöpfe von links in ihrer
// Reihenfolge, Trennstrich vor einer Gruppe, Pfeil nur bei Knöpfen mit Menü,
// Tooltips, Klicks auf Symbol und Pfeil erreichen ihre Ereignisse, gesperrte
// Knöpfe nicht.

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
    procedure ButtonsInOrder;
    [Test]
    procedure HintsPerButton;
    [Test]
    procedure ClicksReachEvents;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.EditorToolbar.Icons;

function Middle(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

procedure TAtlasDesignerBarTests.SetUp;
var
  mButtons: TArray<TAtlasDesignerButton>;
  mButton: TAtlasDesignerButton;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 900;
  FForm.Height := 300;
  FBar := TAtlasDesignerBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
  mButtons := TArray<TAtlasDesignerButton>.Create(TAtlasDesignerButton.Create('search',
    TAtlasToolbarIcon.ComponentSearch, 'Komponenten suchen (Alt+^)'));
  mButton := TAtlasDesignerButton.Create('nonVisual', TAtlasToolbarIcon.NonVisual, 'Nichtvisuelle');
  mButton.Pressed := True;
  mButtons := mButtons + [mButton];
  mButton := TAtlasDesignerButton.Create('parent', TAtlasToolbarIcon.SelectParent, 'Elternelement');
  mButton.GapBefore := True;
  mButton.Enabled := False;
  mButtons := mButtons + [mButton];
  mButton := TAtlasDesignerButton.Create('align', TAtlasToolbarIcon.AlignControls, 'Ausrichten');
  mButton.Menu := True;
  mButtons := mButtons + [mButton];
  FBar.SetButtons(mButtons);
end;

procedure TAtlasDesignerBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasDesignerBarTests.ButtonsInOrder;
var
  mHeight: Integer;
  mSearch, mNonVisual, mParent, mAlign, mArrow: TRect;
begin
  mHeight := FBar.Height;
  Assert.AreEqual(TAtlasDesignerBar.BarHeight(FBar.CurrentPPI), mHeight, 'eine Zeile');
  mSearch := FBar.ButtonRect('search');
  mNonVisual := FBar.ButtonRect('nonVisual');
  mParent := FBar.ButtonRect('parent');
  mAlign := FBar.ButtonRect('align');
  Assert.IsFalse(mSearch.IsEmpty, 'Suchen');
  Assert.IsTrue(mSearch.Right <= mNonVisual.Left, 'Nichtvisuelle rechts von Suchen');
  Assert.IsTrue(mParent.Left - mNonVisual.Right > mNonVisual.Left - mSearch.Right, 'Lücke vor der Gruppe');
  Assert.IsTrue(mParent.Right <= mAlign.Left);
  Assert.IsTrue(FBar.ArrowRect('search').IsEmpty, 'ohne Menü kein Pfeil');
  mArrow := FBar.ArrowRect('align');
  Assert.IsFalse(mArrow.IsEmpty, 'Pfeil am Menüknopf');
  Assert.AreEqual(mAlign.Right, mArrow.Left, 'Pfeil direkt rechts');
  Assert.IsTrue(FBar.ButtonRect('fehlt').IsEmpty);
  Assert.IsTrue(FBar.Buttons[1].Pressed, 'Zustand bleibt');
  FBar.Height := mHeight * 2;
  Assert.AreEqual(mHeight, FBar.Height, 'nie höher');
end;

procedure TAtlasDesignerBarTests.HintsPerButton;
var
  mPoint: TPoint;
begin
  mPoint := Middle(FBar.ButtonRect('search'));
  Assert.AreEqual('Komponenten suchen (Alt+^)', FBar.HintAt(mPoint.X, mPoint.Y));
  mPoint := Middle(FBar.ArrowRect('align'));
  Assert.AreEqual('Ausrichten', FBar.HintAt(mPoint.X, mPoint.Y), 'Pfeil mit dem Tooltip des Knopfs');
  Assert.AreEqual('', FBar.HintAt(FBar.ClientWidth - 2, 2), 'rechts frei');
end;

procedure TAtlasDesignerBarTests.ClicksReachEvents;
var
  mCommands: string;
  mMenuId: string;
  mMenuAt, mPoint: TPoint;
begin
  mCommands := '';
  mMenuId := '';
  mMenuAt := Point(-1, -1);
  FBar.OnCommand :=
    procedure(AId: string)
    begin
      mCommands := mCommands + AId + ';';
    end;
  FBar.OnMenu :=
    procedure(AId: string; APoint: TPoint)
    begin
      mMenuId := AId;
      mMenuAt := APoint;
    end;
  mPoint := Middle(FBar.ButtonRect('search'));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  mPoint := Middle(FBar.ButtonRect('parent'));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  mPoint := Middle(FBar.ButtonRect('align'));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual('search;align;', mCommands, 'gesperrter Knopf meldet nichts');
  Assert.AreEqual('', mMenuId, 'Symbol öffnet kein Menü');
  mPoint := Middle(FBar.ArrowRect('align'));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual('align', mMenuId);
  Assert.AreEqual(FBar.ClientToScreen(Point(FBar.ButtonRect('align').Left, 0)).X, mMenuAt.X, 'Menü unter dem Knopf');
  Assert.AreEqual('search;align;', mCommands, 'Pfeil führt nichts aus');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerBarTests);

end.
