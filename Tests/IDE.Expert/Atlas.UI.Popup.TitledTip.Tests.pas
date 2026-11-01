unit Atlas.UI.Popup.TitledTip.Tests;

// Tests für den Tooltip mit Titel und Text (#545, #623, #1281; bis #1455 in
// Atlas.UI.Notes.Tests).

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
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.UI.Popup.TitledTip;

procedure TAtlasTitledTipTests.MeasuresWrappedText;
var
  Tip: TAtlasTitledTip;
  One, Two, Long: TSize;
begin
  Tip := TAtlasTitledTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    Tip.SetScaling(96, 1, 'Segoe UI', 9);
    One := Tip.Measure('Notiz vom 15.10.2026', 'Eine Zeile');
    Two := Tip.Measure('Notiz vom 15.10.2026', 'Eine Zeile' + #10 + 'Noch eine');
    Assert.IsTrue(Two.cy > One.cy, 'zweite Zeile macht den Tooltip höher');
    Assert.AreEqual('Eine Zeile' + #13#10 + 'Noch eine', Tip.Text);
    Long := Tip.Measure('Notiz', StringOfChar('x', 20) + ' ' + StringOfChar('y', 400));
    Assert.IsTrue(Long.cx <= TAtlasTitledTip.MaxWidth + 2 * TAtlasTitledTip.Padding, 'Breite begrenzt');
  finally
    Tip.Free;
  end;
end;

procedure TAtlasTitledTipTests.LinksAddLines;
var
  Tip: TAtlasTitledTip;
  Plain, Linked: TSize;
begin
  Tip := TAtlasTitledTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    Tip.SetScaling(96, 1, 'Segoe UI', 9);
    Plain := Tip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern');
    Linked := Tip.Measure('Rekursion über 2 Methoden', 'Speichern → Pruefen → Speichern',
      ['TFoo.Speichern', 'TFoo.Pruefen']);
    Assert.IsTrue(Linked.cy > Plain.cy, 'zwei Zeilen mehr');
    Assert.AreEqual(2, Integer(Length(Tip.Links)));
    Assert.AreEqual(-1, Tip.LinkAt(1, 1), 'noch nicht gezeichnet');
    Tip.Measure('Notiz', 'Text');
    Assert.AreEqual(0, Integer(Length(Tip.Links)), 'ohne Links wieder leer');
  finally
    Tip.Free;
  end;
end;

procedure TAtlasTitledTipTests.BodyAreaHoldsMeasuredText;
var
  Tip: TAtlasTitledTip;
  Size: TSize;
  Ppi: Integer;
begin
  Tip := TAtlasTitledTip.Create(nil);
  try
    Tip.Colors := TAtlasColors.Light;
    for Ppi in TArray<Integer>.Create(96, 144, 192) do
    begin
      Tip.SetScaling(Ppi, 1, 'Segoe UI', 9);
      Size := Tip.Measure('Lesezeichen 1', 'Klick setzt ein Lesezeichen' + #10 + 'Zweite Zeile mit Unterlängen gpy');
      Assert.IsTrue(Tip.BodyArea(Size).Height >= Tip.BodyHeight, Format('Text passt bei %d dpi', [Ppi]));
      Assert.IsTrue(Tip.BodyArea(Size).Width > 0, Format('Breite bei %d dpi', [Ppi]));
    end;
  finally
    Tip.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTitledTipTests);

end.
