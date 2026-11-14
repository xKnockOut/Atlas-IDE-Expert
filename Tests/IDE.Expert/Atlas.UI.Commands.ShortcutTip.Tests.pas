unit Atlas.UI.Commands.ShortcutTip.Tests;

// Popup der Tastenkürzel-Tipps (#600): unten rechts in der Fläche, Links
// „Nicht mehr zeigen“ und „Alle Kürzel“ (nur mit Übersicht), Klick löst das
// Ereignis aus und blendet aus, 4 s Anzeigedauer, Kürzel mit zwei Schritten
// in der Sprachausgabe.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasShortcutTipWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsBottomRightWithTimer;
    [Test]
    procedure LinksRaiseEventsAndHide;
    [Test]
    procedure AllKeysOnlyWithOverview;
    [Test]
    procedure SpeaksBothStepsOfTwoStepShortCut;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Commands.ShortcutTips,
  Atlas.UI.Strings,
  Atlas.UI.Commands.ShortcutTip;

type
  /// <summary>Zählt die Ereignisse der Links (TNotifyEvent braucht eine Methode).</summary>
  TLinkCounter = class
  public
    Never: Integer;
    AllKeys: Integer;
    procedure NeverClick(Sender: TObject);
    procedure AllKeysClick(Sender: TObject);
  end;

var
  Language: TAtlasLanguage;

procedure TLinkCounter.NeverClick(Sender: TObject);
begin
  Inc(Never);
end;

procedure TLinkCounter.AllKeysClick(Sender: TObject);
begin
  Inc(AllKeys);
end;

function NewWindow: TAtlasShortcutTipWindow;
begin
  Result := TAtlasShortcutTipWindow.Create(nil);
  Result.Colors := TAtlasColors.Light;
  Result.SetScaling(96, 1, 'Segoe UI', 9);
end;

procedure TAtlasShortcutTipWindowTests.WarmUpFirstUse;
begin
  Setup;
  try
    ShowsBottomRightWithTimer;
  finally
    TearDown;
  end;
end;

procedure TAtlasShortcutTipWindowTests.Setup;
begin
  Language := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasShortcutTipWindowTests.TearDown;
begin
  TAtlasStrings.Language := Language;
end;

procedure TAtlasShortcutTipWindowTests.ShowsBottomRightWithTimer;
var
  mWindow: TAtlasShortcutTipWindow;
  mArea, mBounds: TRect;
begin
  mArea := Rect(100, 100, 900, 700);
  mWindow := NewWindow;
  try
    mWindow.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse beim Cursor vervollständigen', True), mArea);
    try
      Assert.IsTrue(mWindow.IsShown);
      mBounds := mWindow.BoundsRect;
      Assert.AreEqual(mArea.Right - TAtlasShortcutTipWindow.cMargin, mBounds.Right, 'rechts mit Abstand');
      Assert.AreEqual(mArea.Bottom - TAtlasShortcutTipWindow.cMargin, mBounds.Bottom, 'unten mit Abstand');
      Assert.IsTrue(mBounds.Width > 0);
      Assert.IsTrue(mWindow.Timer.Enabled);
      Assert.AreEqual(Integer(TAtlasShortcutTips.cVisibleMs), Integer(mWindow.Timer.Interval), '4 s');
      Assert.AreEqual(4000, Integer(mWindow.Timer.Interval));
    finally
      mWindow.Dismiss;
    end;
    Assert.IsFalse(mWindow.IsShown);
    Assert.IsFalse(mWindow.Timer.Enabled);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.LinksRaiseEventsAndHide;
var
  mWindow: TAtlasShortcutTipWindow;
  mCounter: TLinkCounter;
  mLink: TRect;
begin
  mCounter := TLinkCounter.Create;
  mWindow := NewWindow;
  try
    mWindow.OnNever := mCounter.NeverClick;
    mWindow.OnAllKeys := mCounter.AllKeysClick;
    mWindow.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse vervollständigen', True),
      Rect(0, 0, 1200, 800));
    mLink := mWindow.LinkRect(TAtlasShortcutTipLink.Never);
    Assert.IsFalse(mLink.IsEmpty, '„Nicht mehr zeigen“ ist da');
    Assert.AreEqual<TAtlasShortcutTipLink>(TAtlasShortcutTipLink.Never,
      mWindow.LinkAt(mLink.CenterPoint.X, mLink.CenterPoint.Y));
    Assert.AreEqual<TAtlasShortcutTipLink>(TAtlasShortcutTipLink.None, mWindow.LinkAt(0, 0), 'Rand ist kein Link');
    mWindow.ClickLink(TAtlasShortcutTipLink.Never);
    Assert.AreEqual(1, mCounter.Never);
    Assert.AreEqual(0, mCounter.AllKeys);
    Assert.IsFalse(mWindow.IsShown, 'Klick blendet aus');
    mWindow.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse vervollständigen', True),
      Rect(0, 0, 1200, 800));
    mWindow.ClickLink(TAtlasShortcutTipLink.AllKeys);
    Assert.AreEqual(1, mCounter.AllKeys);
    Assert.IsFalse(mWindow.IsShown);
  finally
    mWindow.Free;
    mCounter.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.AllKeysOnlyWithOverview;
var
  mWindow: TAtlasShortcutTipWindow;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowTip(TAtlasShortcutTipView.Create('F12', 'Formular/Unit umschalten', False), Rect(0, 0, 1200, 800));
    try
      Assert.IsFalse(mWindow.LinkRect(TAtlasShortcutTipLink.Never).IsEmpty);
      Assert.IsTrue(mWindow.LinkRect(TAtlasShortcutTipLink.AllKeys).IsEmpty, 'ohne keys.overview kein Link');
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.SpeaksBothStepsOfTwoStepShortCut;
var
  mWindow: TAtlasShortcutTipWindow;
begin
  mWindow := NewWindow;
  try
    mWindow.ShowTip(TAtlasShortcutTipView.Create('Strg+K, Strg+D', 'Zeile duplizieren', True), Rect(0, 0, 1200, 800));
    try
      Assert.AreEqual(2, Integer(Length(mWindow.View.Steps)));
      Assert.AreEqual('Tipp: Strg+K, Strg+D für Zeile duplizieren', mWindow.SpokenText);
    finally
      mWindow.Dismiss;
    end;
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTipWindowTests);

end.
