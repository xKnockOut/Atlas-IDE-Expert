unit Atlas.UI.Designer.TabOverlay.Tests;

// Tab-Reihenfolge im Designer (#1442): Marken oben links am Steuerelement,
// breiter mit mehr Stellen, Treffer auf der obersten Marke; Klicks melden
// sich nur mit Clickable (experimentell).

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Designer.TabOverlay;

type
  [TestFixture]
  TAtlasTabOrderOverlayTests = class
  private
    FOverlay: TAtlasTabOrderOverlay;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BadgesSitTopLeft;
    [Test]
    procedure ClicksOnlyWhenClickable;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette;

type
  TOverlayAccess = class(TAtlasTabOrderOverlay);

procedure TAtlasTabOrderOverlayTests.SetUp;
begin
  FOverlay := TAtlasTabOrderOverlay.CreateOverlay(nil, 0, TAtlasColors.Light);
  FOverlay.SetBadges(TArray<TAtlasTabBadge>.Create(TAtlasTabBadge.Create('edtName', 0, False, Point(10, 20)),
    TAtlasTabBadge.Create('btnOK', 12, True, Point(200, 20)), TAtlasTabBadge.Create('edtOben', 1, False,
    Point(12, 22))));
end;

procedure TAtlasTabOrderOverlayTests.TearDown;
begin
  FreeAndNil(FOverlay);
end;

procedure TAtlasTabOrderOverlayTests.BadgesSitTopLeft;
var
  mFirst, mWide: TRect;
begin
  mFirst := FOverlay.BadgeRect(0);
  mWide := FOverlay.BadgeRect(1);
  Assert.IsTrue(mFirst.Contains(Point(14, 24)), 'oben links am Steuerelement');
  Assert.IsTrue(mFirst.Left >= 10);
  Assert.IsTrue(mWide.Width >= mFirst.Width, 'zwei Stellen nicht schmaler');
  Assert.AreEqual(-1, FOverlay.BadgeAt(150, 100), 'daneben keine');
  Assert.AreEqual(1, FOverlay.BadgeAt(mWide.CenterPoint.X, mWide.CenterPoint.Y));
  Assert.AreEqual(2, FOverlay.BadgeAt(16, 26), 'überdeckt: die oberste Marke');
end;

procedure TAtlasTabOrderOverlayTests.ClicksOnlyWhenClickable;
var
  mClicked: string;
  mCenter: TPoint;
begin
  mClicked := '';
  FOverlay.OnBadgeClick :=
    procedure(AName: string)
    begin
      mClicked := AName;
    end;
  mCenter := FOverlay.BadgeRect(1).CenterPoint;
  TOverlayAccess(FOverlay).MouseDown(mbLeft, [], mCenter.X, mCenter.Y);
  Assert.AreEqual('', mClicked, 'ohne Klicken nur Anzeige');
  FOverlay.Clickable := True;
  TOverlayAccess(FOverlay).MouseDown(mbLeft, [], mCenter.X, mCenter.Y);
  Assert.AreEqual('btnOK', mClicked);
  mClicked := '';
  TOverlayAccess(FOverlay).MouseDown(mbLeft, [], 150, 100);
  Assert.AreEqual('', mClicked, 'daneben nichts');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTabOrderOverlayTests);

end.
