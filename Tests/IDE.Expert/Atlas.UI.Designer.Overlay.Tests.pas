unit Atlas.UI.Designer.Overlay.Tests;

// Basis der Fenster über dem Designer: Art des Fensters je Option (Popup,
// Schlüsselfarbe, Klicks durchlassen), nie aktivierbar, Besitzer und Farben.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Designer')]
  TAtlasDesignerOverlayTests = class
  public
    [Test]
    procedure PopupWithKeyColorLetsClicksThrough;
    [Test]
    procedure PlainWindowKeepsFrameAndClicks;
    [Test]
    procedure ApplyColorsReplacesColors;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Plugin.Style.Palette,
  Atlas.UI.Designer.Overlay;

type
  TOverlayAccess = class(TAtlasDesignerOverlay);

const
  /// <summary>Beliebiger Besitzer; das Fenster entsteht im Test nicht.</summary>
  cOwnerWindow = HWND(42);

function ParamsOf(AOverlay: TAtlasDesignerOverlay): TCreateParams;
begin
  Result := Default(TCreateParams);
  TOverlayAccess(AOverlay).CreateParams(Result);
end;

{ TAtlasDesignerOverlayTests }

procedure TAtlasDesignerOverlayTests.PopupWithKeyColorLetsClicksThrough;
var
  mOverlay: TAtlasDesignerOverlay;
  mParams: TCreateParams;
begin
  mOverlay := TAtlasDesignerOverlay.CreateOverlayWindow(nil, cOwnerWindow, TAtlasColors.Light,
    [TAtlasOverlayOption.Popup, TAtlasOverlayOption.KeyColor, TAtlasOverlayOption.ClickThrough]);
  try
    Assert.AreEqual<TFormBorderStyle>(bsNone, mOverlay.BorderStyle, 'rahmenlos');
    Assert.IsTrue(mOverlay.TransparentColor, 'Schlüsselfarbe durchsichtig');
    Assert.IsTrue(mOverlay.DoubleBuffered);
    mParams := ParamsOf(mOverlay);
    Assert.AreEqual<Cardinal>(WS_POPUP, mParams.Style, 'Popup');
    Assert.AreNotEqual<Cardinal>(0, mParams.ExStyle and WS_EX_NOACTIVATE, 'nie aktiv');
    Assert.AreNotEqual<Cardinal>(0, mParams.ExStyle and WS_EX_TOOLWINDOW, 'nicht in der Taskleiste');
    Assert.AreNotEqual<Cardinal>(0, mParams.ExStyle and WS_EX_TRANSPARENT, 'Klicks gehen durch');
    Assert.AreEqual<HWND>(cOwnerWindow, mParams.WndParent, 'gehört dem Hauptfenster');
  finally
    mOverlay.Free;
  end;
end;

procedure TAtlasDesignerOverlayTests.PlainWindowKeepsFrameAndClicks;
var
  mOverlay: TAtlasDesignerOverlay;
  mParams: TCreateParams;
begin
  mOverlay := TAtlasDesignerOverlay.CreateOverlayWindow(nil, 0, TAtlasColors.Light, []);
  try
    Assert.AreNotEqual<TFormBorderStyle>(bsNone, mOverlay.BorderStyle, 'mit Rahmen');
    Assert.IsFalse(mOverlay.TransparentColor);
    mParams := ParamsOf(mOverlay);
    Assert.AreNotEqual<Cardinal>(WS_POPUP, mParams.Style);
    Assert.AreNotEqual<Cardinal>(0, mParams.ExStyle and WS_EX_NOACTIVATE, 'nie aktiv');
    Assert.AreEqual<Cardinal>(0, mParams.ExStyle and WS_EX_TRANSPARENT, 'nimmt Klicks an');
  finally
    mOverlay.Free;
  end;
end;

procedure TAtlasDesignerOverlayTests.ApplyColorsReplacesColors;
var
  mOverlay: TAtlasDesignerOverlay;
begin
  mOverlay := TAtlasDesignerOverlay.CreateOverlayWindow(nil, 0, TAtlasColors.Light, [TAtlasOverlayOption.Popup]);
  try
    Assert.AreEqual(Int64(TAtlasColors.Light.Accent), Int64(TOverlayAccess(mOverlay).Colors.Accent));
    mOverlay.ApplyColors(TAtlasColors.Dark);
    Assert.AreEqual(Int64(TAtlasColors.Dark.Accent), Int64(TOverlayAccess(mOverlay).Colors.Accent));
    Assert.AreEqual(MulDiv(10, Screen.PixelsPerInch, 96), mOverlay.ScalePx(10), 'ScalePx skaliert wie der Bildschirm');
  finally
    mOverlay.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDesignerOverlayTests);

end.
