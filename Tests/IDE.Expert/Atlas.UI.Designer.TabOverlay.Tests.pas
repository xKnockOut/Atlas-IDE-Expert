unit Atlas.UI.Designer.TabOverlay.Tests;

// Tab-Reihenfolge im Designer (#1442, #603): Marken oben rechts am
// Steuerelement, breiter mit mehr Zeichen (Pfad), Treffer auf der obersten
// Marke; Klicks melden sich nur mit Clickable (Modus „Reihenfolge klicken“);
// Farbgruppen färben normale Marken, Zustände gehen vor; Rahmen der Container.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Designer.TabOverlay;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasTabOrderOverlayTests = class
  private
    FOverlay: TAtlasTabOrderOverlay;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BadgesSitTopRight;
    [Test]
    procedure ClicksOnlyWhenClickable;
    [Test]
    procedure GroupColorsNormalBadges;
    [Test]
    procedure FramesKeepGroups;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Tests.RecordText;

type
  TOverlayAccess = class(TAtlasTabOrderOverlay);

procedure TAtlasTabOrderOverlayTests.SetUp;
begin
  FOverlay := TAtlasTabOrderOverlay.CreateOverlay(nil, 0, TAtlasColors.Light);
  FOverlay.SetBadges(TArray<TAtlasTabBadge>.Create(
    TAtlasTabBadge.Create('edtName', '0', TAtlasTabBadgeStyle.Normal, Point(100, 20)),
    TAtlasTabBadge.Create('btnOK', '12.3', TAtlasTabBadgeStyle.Warn, Point(300, 20)),
    TAtlasTabBadge.Create('edtOben', '1', TAtlasTabBadgeStyle.Muted, Point(102, 22))));
end;

procedure TAtlasTabOrderOverlayTests.TearDown;
begin
  FreeAndNil(FOverlay);
end;

procedure TAtlasTabOrderOverlayTests.BadgesSitTopRight;
var
  mFirst, mWide: TRect;
begin
  mFirst := FOverlay.BadgeRect(0);
  mWide := FOverlay.BadgeRect(1);
  Assert.IsTrue(mFirst.Contains(Point(96, 24)), 'oben rechts am Steuerelement');
  Assert.IsTrue(mFirst.Right <= 100, 'nicht über den rechten Rand');
  Assert.IsTrue(mWide.Width > mFirst.Width, 'Pfad breiter');
  Assert.IsTrue(mWide.Right <= 300);
  Assert.AreEqual(-1, FOverlay.BadgeAt(150, 100), 'daneben keine');
  Assert.AreEqual(1, FOverlay.BadgeAt(mWide.CenterPoint.X, mWide.CenterPoint.Y));
  Assert.AreEqual(2, FOverlay.BadgeAt(98, 26), 'überdeckt: die oberste Marke');
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

procedure TAtlasTabOrderOverlayTests.GroupColorsNormalBadges;
var
  mColors: TAtlasColors;
  mBadge: TAtlasTabBadge;
begin
  mColors := TAtlasColors.Light;
  mBadge := TAtlasTabBadge.Create('edtName', '0', TAtlasTabBadgeStyle.Normal, Point(100, 20));
  Assert.AreEqual(-1, mBadge.Group, 'ohne Gruppe');
  Assert.AreEqual(Integer(mColors.Accent), Integer(TOverlayAccess(FOverlay).BadgeColor(mBadge)), 'Akzent');
  mBadge.Group := 2;
  Assert.AreEqual(Integer(mColors.Placeholders[2]), Integer(TOverlayAccess(FOverlay).BadgeColor(mBadge)));
  mBadge.Group := 2 + TAtlasTabOrderOverlay.GroupCount;
  Assert.AreEqual(Integer(mColors.Placeholders[2]), Integer(TOverlayAccess(FOverlay).BadgeColor(mBadge)),
    'zyklisch');
  mBadge.Style := TAtlasTabBadgeStyle.Warn;
  Assert.AreEqual(Integer(mColors.Error), Integer(TOverlayAccess(FOverlay).BadgeColor(mBadge)), 'Befund geht vor');
  Assert.IsFalse(mBadge.SameAs(TAtlasTabBadge.Create('edtName', '0', TAtlasTabBadgeStyle.Warn, Point(100, 20))),
    'andere Gruppe zeichnet neu');
  Assert.AreEqual(6, TAtlasTabOrderOverlay.GroupCount);
end;

procedure TAtlasTabOrderOverlayTests.FramesKeepGroups;
begin
  Assert.AreEqual(0, Integer(Length(FOverlay.Frames)), 'ohne Farben keine Rahmen');
  FOverlay.SetFrames(TArray<TAtlasTabFrame>.Create(TAtlasTabFrame.Create(Rect(10, 10, 200, 100), 1),
    TAtlasTabFrame.Create(Rect(20, 20, 100, 90), 2)));
  Assert.AreEqual(2, Integer(Length(FOverlay.Frames)));
  Assert.AreEqual(2, FOverlay.Frames[1].Group);
  Assert.AreEqual(TRecordText.Rect(TRect.Create(10, 10, 200, 100)), TRecordText.Rect(FOverlay.Frames[0].Bounds));
  FOverlay.SetFrames(nil);
  Assert.AreEqual(0, Integer(Length(FOverlay.Frames)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTabOrderOverlayTests);

end.
