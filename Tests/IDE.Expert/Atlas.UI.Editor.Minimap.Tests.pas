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
  Atlas.Core.Editor.Minimap;

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
  Lines: TArray<string>;
  Index: Integer;
begin
  SetLength(Lines, ALineCount);
  for Index := 0 to High(Lines) do
    Lines[Index] := '  if Value > ' + IntToStr(Index) + ' then // Zeile';
  FView.SetContent(Lines, TAtlasMinimap.Runs(Lines, 120, 4), 4);
end;

procedure TAtlasMinimapViewTests.WidthFollowsSetting;
var
  Options: TAtlasMinimapOptions;
begin
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, FView.CurrentPPI), FView.Width);
  Options := TAtlasMinimap.Defaults;
  Options.Width := 60;
  FView.SetOptions(Options);
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(Options, FView.CurrentPPI), FView.Width);
  FView.Width := 300;
  Assert.AreEqual(TAtlasMinimapView.ViewWidth(Options, FView.CurrentPPI), FView.Width, 'feste Breite');
  Assert.AreEqual(120, TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, 96));
  Assert.AreEqual(240, TAtlasMinimapView.ViewWidth(TAtlasMinimap.Defaults, 192));
end;

procedure TAtlasMinimapViewTests.ClickJumpsOrScrolls;
var
  Jumped, Scrolled, Y: Integer;
  Options: TAtlasMinimapOptions;
begin
  Jumped := -1;
  Scrolled := -1;
  FView.OnJump :=
    procedure(ALine: Integer)
    begin
      Jumped := ALine;
    end;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      Scrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(0, 19, 0);
  Y := FView.Map.PixelOfLine(60);
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, Y);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, Y);
  Assert.AreEqual(60, Jumped, 'Klick springt zur Zeile');
  Assert.AreEqual(-1, Scrolled, 'ohne Ziehen kein Bildlauf');
  // Nur scrollen: die Zeile steht in der Mitte.
  Options := TAtlasMinimap.Defaults;
  Options.ClickJumps := False;
  FView.SetOptions(Options);
  Jumped := -1;
  Y := FView.Map.PixelOfLine(60);
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, Y);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, Y);
  Assert.AreEqual(-1, Jumped);
  Assert.AreEqual(50, Scrolled);
  TViewAccess(FView).MouseDown(mbRight, [ssRight], 5, 0);
  Assert.AreEqual(50, Scrolled, 'nur links');
end;

procedure TAtlasMinimapViewTests.DragScrollsTheEditor;
var
  Scrolled: Integer;
  Span: TAtlasMinimapSpan;
begin
  Scrolled := -1;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      Scrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(10, 29, 12);
  Span := FView.SliderSpan;
  // Im Schieber greifen: kein Sprung; ziehen um 20 Pixel = 10 Zeilen bei 2 Pixeln je Zeile.
  TViewAccess(FView).MouseDown(mbLeft, [ssLeft], 5, Span.Top + 2);
  Assert.IsTrue(FView.SliderDragging);
  Assert.AreEqual(-1, Scrolled);
  TViewAccess(FView).MouseMove([ssLeft], 5, Span.Top + 2 + 20 * FView.Map.RowHeight div 2);
  Assert.AreEqual(20, Scrolled);
  TViewAccess(FView).MouseUp(mbLeft, [], 5, 0);
  Assert.IsFalse(FView.SliderDragging);
end;

procedure TAtlasMinimapViewTests.WheelScrollsTheEditor;
var
  Scrolled: Integer;
begin
  Scrolled := -1;
  FView.OnScroll :=
    procedure(ATopLine: Integer)
    begin
      Scrolled := ATopLine;
    end;
  Fill(100);
  FView.SetView(10, 29, 12);
  // Eine Raste nach unten bzw. oben: Zeilen je Raste aus Windows.
  Assert.IsTrue(TViewAccess(FView).DoMouseWheel([], -WHEEL_DELTA, Point(5, 5)));
  Assert.AreEqual(10 + Mouse.WheelScrollLines, Scrolled);
  TViewAccess(FView).DoMouseWheel([], WHEEL_DELTA, Point(5, 5));
  Assert.AreEqual(10 - Mouse.WheelScrollLines, Scrolled);
  // Ganz oben: nicht unter Zeile 0.
  Scrolled := -1;
  FView.SetView(0, 19, 0);
  TViewAccess(FView).DoMouseWheel([], WHEEL_DELTA, Point(5, 5));
  Assert.AreEqual(-1, Scrolled, 'oben bleibt oben');
end;

procedure TAtlasMinimapViewTests.SliderOnlyOnMouseOver;
var
  Options: TAtlasMinimapOptions;
begin
  Fill(50);
  Assert.IsTrue(FView.SliderVisible, 'Vorgabe: immer');
  Options := TAtlasMinimap.Defaults;
  Options.Slider := TAtlasMinimapSlider.MouseOver;
  FView.SetOptions(Options);
  Assert.IsFalse(FView.SliderVisible);
  FView.Perform(CM_MOUSEENTER, 0, 0);
  Assert.IsTrue(FView.SliderVisible);
  FView.Perform(CM_MOUSELEAVE, 0, 0);
  Assert.IsFalse(FView.SliderVisible);
end;

procedure TAtlasMinimapViewTests.PaintsBothRenderings;
var
  Options: TAtlasMinimapOptions;
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
  Options := TAtlasMinimap.Defaults;
  Options.Render := TAtlasMinimapRender.Characters;
  Options.Scale := 3;
  FView.SetOptions(Options);
  Fill(20);
  FView.Repaint;
  // Nur eine Zeile geändert: zeichnet ohne Fehler nach.
  Fill(20);
  FView.Repaint;
  Assert.AreEqual(20, FView.Map.LineCount);
end;

procedure TAtlasMinimapViewTests.ColorsDifferByToken;
var
  Colors: TAtlasColors;
begin
  Colors := TAtlasColors.Dark;
  Assert.AreNotEqual(Integer(TAtlasMinimapView.TokenColor(Colors, TAtlasTokenKind.Keyword)),
    Integer(TAtlasMinimapView.TokenColor(Colors, TAtlasTokenKind.Comment)));
  Assert.AreNotEqual(Integer(TAtlasMinimapView.TokenColor(Colors, TAtlasTokenKind.Plain)),
    Integer(TAtlasMinimapView.TokenColor(Colors, TAtlasTokenKind.StringLiteral)));
  Assert.AreNotEqual(Integer(TAtlasMinimapView.TokenColor(TAtlasColors.Light, TAtlasTokenKind.Plain)),
    Integer(TAtlasMinimapView.TokenColor(Colors, TAtlasTokenKind.Plain)), 'helles und dunkles Thema');
end;

end.
