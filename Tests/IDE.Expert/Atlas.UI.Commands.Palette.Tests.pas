unit Atlas.UI.Commands.Palette.Tests;

// Fenster der Befehlspalette: Basis TAtlasPopupForm (Dialogschrift eine Stufe
// größer, Farben folgen dem Themenwechsel).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPaletteWindowTests = class
  public
    /// <summary>Schrift aus dem Themendienst, eine Stufe größer; ein Themenwechsel holt die neuen Farben.</summary>
    [Test]
    procedure FollowsIdeTheme;
  end;

implementation

uses
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Commands.Palette;

{ TAtlasPaletteWindowTests }

procedure TAtlasPaletteWindowTests.FollowsIdeTheme;
var
  mWindow: TAtlasPaletteWindow;
  mDark: TAtlasColors;
begin
  mDark := TAtlasColors.Dark;
  mWindow := TAtlasPaletteWindow.CreatePalette(nil, nil, nil, TAtlasColors.Light);
  try
    Assert.AreEqual(TAtlasUiTheme.cFontName, string(mWindow.Font.Name));
    Assert.AreEqual(TAtlasUiTheme.cFontSize + 1, mWindow.Font.Size, 'eine Stufe größer als die Dialogschrift');
    Assert.IsTrue(TAtlasUiTheme.Subscribed(mWindow), 'meldet sich beim Themendienst an');
    TAtlasUiTheme.Install(
      function: TAtlasColors
      begin
        Result := TAtlasColors.Dark;
      end, nil, nil);
    try
      TAtlasUiTheme.Changed;
    finally
      TAtlasUiTheme.Uninstall;
    end;
    Assert.AreEqual(Integer(TColor(mDark.Surface)), Integer(mWindow.Color), 'Fläche im neuen Thema');
    Assert.AreEqual(Int64(mDark.Accent), Int64(mWindow.Colors.Accent), 'Farben zum Zeichnen im neuen Thema');
  finally
    mWindow.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPaletteWindowTests);

end.
