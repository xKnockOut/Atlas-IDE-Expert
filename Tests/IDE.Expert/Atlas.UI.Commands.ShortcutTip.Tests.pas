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
  Window: TAtlasShortcutTipWindow;
  Area, Bounds: TRect;
begin
  Area := Rect(100, 100, 900, 700);
  Window := NewWindow;
  try
    Window.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse beim Cursor vervollständigen', True), Area);
    try
      Assert.IsTrue(Window.IsShown);
      Bounds := Window.BoundsRect;
      Assert.AreEqual(Area.Right - TAtlasShortcutTipWindow.Margin, Bounds.Right, 'rechts mit Abstand');
      Assert.AreEqual(Area.Bottom - TAtlasShortcutTipWindow.Margin, Bounds.Bottom, 'unten mit Abstand');
      Assert.IsTrue(Bounds.Width > 0);
      Assert.IsTrue(Window.Timer.Enabled);
      Assert.AreEqual(Integer(TAtlasShortcutTips.VisibleMs), Integer(Window.Timer.Interval), '4 s');
      Assert.AreEqual(4000, Integer(Window.Timer.Interval));
    finally
      Window.Dismiss;
    end;
    Assert.IsFalse(Window.IsShown);
    Assert.IsFalse(Window.Timer.Enabled);
  finally
    Window.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.LinksRaiseEventsAndHide;
var
  Window: TAtlasShortcutTipWindow;
  Counter: TLinkCounter;
  Link: TRect;
begin
  Counter := TLinkCounter.Create;
  Window := NewWindow;
  try
    Window.OnNever := Counter.NeverClick;
    Window.OnAllKeys := Counter.AllKeysClick;
    Window.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse vervollständigen', True),
      Rect(0, 0, 1200, 800));
    Link := Window.LinkRect(TAtlasShortcutTipLink.Never);
    Assert.IsFalse(Link.IsEmpty, '„Nicht mehr zeigen“ ist da');
    Assert.IsTrue(Window.LinkAt(Link.CenterPoint.X, Link.CenterPoint.Y) = TAtlasShortcutTipLink.Never);
    Assert.IsTrue(Window.LinkAt(0, 0) = TAtlasShortcutTipLink.None, 'Rand ist kein Link');
    Window.ClickLink(TAtlasShortcutTipLink.Never);
    Assert.AreEqual(1, Counter.Never);
    Assert.AreEqual(0, Counter.AllKeys);
    Assert.IsFalse(Window.IsShown, 'Klick blendet aus');
    Window.ShowTip(TAtlasShortcutTipView.Create('Strg+Umschalt+C', 'Klasse vervollständigen', True),
      Rect(0, 0, 1200, 800));
    Window.ClickLink(TAtlasShortcutTipLink.AllKeys);
    Assert.AreEqual(1, Counter.AllKeys);
    Assert.IsFalse(Window.IsShown);
  finally
    Window.Free;
    Counter.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.AllKeysOnlyWithOverview;
var
  Window: TAtlasShortcutTipWindow;
begin
  Window := NewWindow;
  try
    Window.ShowTip(TAtlasShortcutTipView.Create('F12', 'Formular/Unit umschalten', False), Rect(0, 0, 1200, 800));
    try
      Assert.IsFalse(Window.LinkRect(TAtlasShortcutTipLink.Never).IsEmpty);
      Assert.IsTrue(Window.LinkRect(TAtlasShortcutTipLink.AllKeys).IsEmpty, 'ohne keys.overview kein Link');
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

procedure TAtlasShortcutTipWindowTests.SpeaksBothStepsOfTwoStepShortCut;
var
  Window: TAtlasShortcutTipWindow;
begin
  Window := NewWindow;
  try
    Window.ShowTip(TAtlasShortcutTipView.Create('Strg+K, Strg+D', 'Zeile duplizieren', True), Rect(0, 0, 1200, 800));
    try
      Assert.AreEqual(2, Integer(Length(Window.View.Steps)));
      Assert.AreEqual('Tipp: Strg+K, Strg+D für Zeile duplizieren', Window.SpokenText);
    finally
      Window.Dismiss;
    end;
  finally
    Window.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasShortcutTipWindowTests);

end.
