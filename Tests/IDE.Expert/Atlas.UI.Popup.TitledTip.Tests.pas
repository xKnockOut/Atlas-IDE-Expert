unit Atlas.UI.Popup.TitledTip.Tests;

// Tests für den Tooltip mit Titel und Text (#545, #623, #1281).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTitledTipTests = class
  public
    [Test]
    procedure MeasuresWrappedText;
    /// <summary>#623: Links unter dem Text machen den Tooltip höher; ohne Zeichnen gibt es kein Klickziel.</summary>
    [Test]
    procedure LinksAddLines;
    /// <summary>#1281: Der Bereich des Textes ist beim Zeichnen so hoch wie gemessen (vorher zwei Pixel zu
    /// wenig, die letzte Zeile wurde unten abgeschnitten).</summary>
    [Test]
    procedure BodyAreaHoldsMeasuredText;
    /// <summary>Ohne eigene Farben nimmt der Tooltip beim Zeigen die des Themendienstes (in der IDE deren
    /// Thema), nicht die des globalen VCL-Stils: sonst hell im dunklen Editor.</summary>
    [Test]
    procedure FollowsThemeWithoutOwnColors;
    /// <summary>Gesetzte Farben bleiben beim Zeigen, auch wenn der Themendienst andere liefert.</summary>
    [Test]
    procedure KeepsOwnColors;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Popup.TitledTip;

function DarkColors: TAtlasColors;
begin
  Result := TAtlasColors.Dark;
end;

{ TAtlasTitledTipTests }

procedure TAtlasTitledTipTests.FollowsThemeWithoutOwnColors;
var
  mTip: TAtlasTitledTip;
begin
  mTip := TAtlasTitledTip.Create(nil);
  try
    mTip.SetScaling(96, 1, 'Segoe UI', 9);
    Assert.AreEqual(Int64(TAtlasColors.Light.Surface), Int64(mTip.Colors.Surface), 'ohne Themendienst hell');
    TAtlasUiTheme.Install(DarkColors, nil, nil);
    try
      mTip.ShowNote('Wer gibt das frei?', 'Text', Point(10, 10));
    finally
      TAtlasUiTheme.Uninstall;
    end;
    Assert.AreEqual(Int64(TAtlasColors.Dark.Surface), Int64(mTip.Colors.Surface), 'Fläche im Thema');
    Assert.AreEqual(Int64(TAtlasColors.Dark.Accent), Int64(mTip.BorderColor), 'Rahmen im Thema');
    mTip.HidePopup;
  finally
    mTip.Free;
  end;
end;

procedure TAtlasTitledTipTests.KeepsOwnColors;
var
  mTip: TAtlasTitledTip;
begin
  mTip := TAtlasTitledTip.Create(nil);
  try
    mTip.Colors := TAtlasColors.Light;
    mTip.SetScaling(96, 1, 'Segoe UI', 9);
    TAtlasUiTheme.Install(DarkColors, nil, nil);
    try
      mTip.ShowNote('Notiz', 'Text', Point(10, 10));
    finally
      TAtlasUiTheme.Uninstall;
    end;
    Assert.AreEqual(Int64(TAtlasColors.Light.Surface), Int64(mTip.Colors.Surface));
    mTip.HidePopup;
  finally
    mTip.Free;
  end;
end;

procedure TAtlasTitledTipTests.MeasuresWrappedText;
var
  mTip: TAtlasTitledTip;
  mOne, mTwo, mLong: TSize;
begin
  mTip := TAtlasTitledTip.Create(nil);
  try
    mTip.Colors := TAtlasColors.Light;
    mTip.SetScaling(96, 1, 'Segoe UI', 9);
    mOne := mTip.Measure('Notiz vom 15.10.2026', 'Eine Zeile');
    mTwo := mTip.Measure('Notiz vom 15.10.2026', 'Eine Zeile' + #10 + 'Noch eine');
    Assert.IsTrue(mTwo.cy > mOne.cy, 'zweite Zeile macht den Tooltip höher');
    Assert.AreEqual('Eine Zeile' + #13#10 + 'Noch eine', mTip.Text);
    mLong := mTip.Measure('Notiz', StringOfChar('x', 20) + ' ' + StringOfChar('y', 400));
    Assert.IsTrue(mLong.cx <= TAtlasTitledTip.cMaxWidth + 2 * TAtlasTitledTip.cPadding, 'Breite begrenzt');
  finally
    mTip.Free;
  end;
end;

procedure TAtlasTitledTipTests.LinksAddLines;
var
  mTip: TAtlasTitledTip;
  mPlain, mLinked: TSize;
begin
  mTip := TAtlasTitledTip.Create(nil);
  try
    mTip.Colors := TAtlasColors.Light;
    mTip.SetScaling(96, 1, 'Segoe UI', 9);
    mPlain := mTip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern');
    mLinked := mTip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern',
      ['TFoo.Speichern', 'TFoo.Pruefen']);
    Assert.IsTrue(mLinked.cy > mPlain.cy, 'zwei Zeilen mehr');
    Assert.AreEqual(2, Integer(Length(mTip.Links)));
    Assert.AreEqual(-1, mTip.LinkAt(1, 1), 'noch nicht gezeichnet');
    mTip.Measure('Notiz', 'Text');
    Assert.AreEqual(0, Integer(Length(mTip.Links)), 'ohne Links wieder leer');
  finally
    mTip.Free;
  end;
end;

procedure TAtlasTitledTipTests.BodyAreaHoldsMeasuredText;
var
  mTip: TAtlasTitledTip;
  mSize: TSize;
  mPpi: Integer;
begin
  mTip := TAtlasTitledTip.Create(nil);
  try
    mTip.Colors := TAtlasColors.Light;
    for mPpi in TArray<Integer>.Create(96, 144, 192) do
    begin
      mTip.SetScaling(mPpi, 1, 'Segoe UI', 9);
      mSize := mTip.Measure('Lesezeichen 1', 'Klick setzt ein Lesezeichen' + #10 + 'Zweite Zeile mit Unterlängen gpy');
      Assert.IsTrue(mTip.BodyArea(mSize).Height >= mTip.BodyHeight, Format('Text passt bei %d dpi', [mPpi]));
      Assert.IsTrue(mTip.BodyArea(mSize).Width > 0, Format('Breite bei %d dpi', [mPpi]));
    end;
  finally
    mTip.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTitledTipTests);

end.
