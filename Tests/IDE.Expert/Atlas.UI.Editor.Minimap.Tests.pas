unit Atlas.UI.Editor.Minimap.Tests;

// Minimap (#873), Darstellung: Breite aus der Einstellung, Klick springt oder
// scrollt nur, Ziehen am Schieber scrollt, Schieber nur beim Überfahren,
// Zeichnen in beiden Darstellungen, Farben je Token.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Editor.Minimap;

type
  [TestFixture]
  TAtlasMinimapViewTests = class
  private
    FForm: TForm;
    FView: TAtlasMinimapView;
    procedure Fill(ALineCount: Integer);
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure WidthFollowsSetting;
    [Test]
    procedure ClickJumpsOrScrolls;
    [Test]
    procedure DragScrollsTheEditor;
    /// <summary>Mausrad über der Minimap scrollt den Editor.</summary>
    [Test]
    procedure WheelScrollsTheEditor;
    [Test]
    procedure SliderOnlyOnMouseOver;
    [Test]
    procedure PaintsBothRenderings;
    [Test]
    procedure ColorsDifferByToken;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Syntax,
  Atlas.Core.Editor.Overview,
  Atlas.Core.Editor.Minimap,
  Atlas.UI.Editor.MinimapLayers;

type
  TViewAccess = class(TAtlasMinimapView);

procedure TAtlasMinimapViewTests.WarmUpFirstUse;
begin
  SetUp;
  try
    WidthFollowsSetting;
  finally
    TearDown;
  end;
end;

procedure TAtlasMinimapViewTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 600;
  FForm.Height := 600;
  FView := TAtlasMinimapView.Create(FForm);
  FView.Parent := FForm;
  FView.Align := alRight;
  FView.HandleNeeded;
end;

procedure TAtlasMinimapViewTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FView := nil;
end;

procedure TAtlasMinimapViewTests.Fill(ALineCount: Integer);
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  SetLength(mLines, ALineCount);
  for mIndex := 0 to High(mLines) do
  begin
    mLines[mIndex] := '  if Value > ' + IntToStr(mIndex) + ' then // Zeile';
  end;
  FView.SetContent(mLines, TAtlasMinimap.Runs(mLines, 120, 4), 4);
end;

procedure TAtlasMinimapViewTests.WidthFollowsSetting;
var
  mOptions: TAtlasMinimapOptions;
begin
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, FView.CurrentPPI), FView.Width);
  mOptions := TAtlasMinimap.Defaults;
  mOptions.Width := 60;
  FView.SetOptions(mOptions);
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(mOptions, FView.CurrentPPI), FView.Width);
  FView.Width := 300;
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(mOptions, FView.CurrentPPI), FView.Width, 'feste Breite');
  Assert.AreEqual(120, TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, 96));
  Assert.AreEqual(240, TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, 192));
end;

procedure TAtlasMinimapViewTests.ClickJumpsOrScrolls;
var
  mJumped, mScrolled, Y: Integer;
  mOptions: TAtlasMinimapOptions;
begin
  mJumped := -1;
  mScrolled := -1;
  FView.OnJump :=
    procedure(ALine: Integer)
    begin
      mJumped := ALine;
    end;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      mScrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(0, 19, 0);
  Y := FView.Map.PixelOfLine(60);
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, Y);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, Y);
  Assert.AreEqual(60, mJumped, 'Klick springt zur Zeile');
  Assert.AreEqual(-1, mScrolled, 'ohne Ziehen kein Bildlauf');
  // Nur scrollen: die Zeile steht in der Mitte.
  mOptions := TAtlasMinimap.Defaults;
  mOptions.ClickJumps := False;
  FView.SetOptions(mOptions);
  mJumped := -1;
  Y := FView.Map.PixelOfLine(60);
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, Y);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, Y);
  Assert.AreEqual(-1, mJumped);
  Assert.AreEqual(50, mScrolled);
  TViewAccess(FView).MouseDown(mbRight, [ssRight], 5, 0);
  Assert.AreEqual(50, mScrolled, 'nur links');
end;

procedure TAtlasMinimapViewTests.DragScrollsTheEditor;
var
  mScrolled: Integer;
  mSpan: TAtlasMinimapSpan;
begin
  mScrolled := -1;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      mScrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(10, 29, 12);
  mSpan := FView.SliderSpan;
  // Im Schieber greifen: kein Sprung; ziehen um 20 Pixel = 10 Zeilen bei 2 Pixeln je Zeile.
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, mSpan.Top + 2);
  Assert.IsTrue(FView.SliderDragging);
  Assert.AreEqual(-1, mScrolled);
  TViewAccess(FView).MouseMove([ssLeft], 5, mSpan.Top + 2 + 20 * FView.Map.RowHeight div 2);
  Assert.AreEqual(20, mScrolled);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, 0);
  Assert.IsFalse(FView.SliderDragging);
end;

procedure TAtlasMinimapViewTests.WheelScrollsTheEditor;
var
  mScrolled: Integer;
begin
  mScrolled := -1;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      mScrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(10, 29, 12);
  // Eine Raste nach unten bzw. oben: Zeilen je Raste aus Windows.
  Assert.IsTrue(TViewAccess(FView).DoMouseWheel([], -WHEEL_DELTA, Point(5, 5)));
  Assert.AreEqual(10 + Mouse.WheelScrollLines, mScrolled);
  TViewAccess(FView).DoMouseWheel([], WHEEL_DELTA, Point(5, 5));
  Assert.AreEqual(10 - Mouse.WheelScrollLines, mScrolled);
  // Ganz oben: nicht unter Zeile 0.
  mScrolled := -1;
  FView.SetView(0, 19, 0);
  TViewAccess(FView).DoMouseWheel([], WHEEL_DELTA, Point(5, 5));
  Assert.AreEqual(-1, mScrolled, 'oben bleibt oben');
end;

procedure TAtlasMinimapViewTests.SliderOnlyOnMouseOver;
var
  mOptions: TAtlasMinimapOptions;
begin
  Fill(50);
  Assert.IsTrue(FView.SliderVisible, 'Vorgabe: immer');
  mOptions := TAtlasMinimap.Defaults;
  mOptions.Slider := TAtlasMinimapSlider.MouseOver;
  FView.SetOptions(mOptions);
  Assert.IsFalse(FView.SliderVisible);
  FView.Perform(CM_MOUSEENTER, 0, 0);
  Assert.IsTrue(FView.SliderVisible);
  FView.Perform(CM_MOUSELEAVE, 0, 0);
  Assert.IsFalse(FView.SliderVisible);
end;

procedure TAtlasMinimapViewTests.PaintsBothRenderings;
var
  mOptions: TAtlasMinimapOptions;
begin
  Fill(10000);
  FView.SetView(5000, 5050, 5010);
  FView.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 5005, 1),
    TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Added, 10, 2)]);
  FView.SetFolds([TAtlasMinimapFold.Create(100, 50)]);
  Assert.IsFalse(FView.Map.Compressed, '10 000 Zeilen werden nicht gestaucht');
  Assert.IsTrue(FView.Map.Offset > 0, 'die Minimap scrollt mit zur Mitte');
  Assert.AreEqual(9950, FView.Map.RowCount);
  FView.Repaint;
  mOptions := TAtlasMinimap.Defaults;
  mOptions.Render := TAtlasMinimapRender.Characters;
  mOptions.Scale := 3;
  FView.SetOptions(mOptions);
  Fill(20);
  FView.Repaint;
  // Nur eine Zeile geändert: zeichnet ohne Fehler nach.
  Fill(20);
  FView.Repaint;
  Assert.AreEqual(20, FView.Map.LineCount);
end;

procedure TAtlasMinimapViewTests.ColorsDifferByToken;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasColors.Dark;
  Assert.AreNotEqual(Integer(TAtlasMinimapCode.TokenColor(mColors, TAtlasTokenKind.Keyword)),
    Integer(TAtlasMinimapCode.TokenColor(mColors, TAtlasTokenKind.Comment)));
  Assert.AreNotEqual(Integer(TAtlasMinimapCode.TokenColor(mColors, TAtlasTokenKind.Plain)),
    Integer(TAtlasMinimapCode.TokenColor(mColors, TAtlasTokenKind.StringLiteral)));
  Assert.AreNotEqual(Integer(TAtlasMinimapCode.TokenColor(TAtlasColors.Light, TAtlasTokenKind.Plain)),
    Integer(TAtlasMinimapCode.TokenColor(mColors, TAtlasTokenKind.Plain)), 'helles und dunkles Thema');
end;

end.
