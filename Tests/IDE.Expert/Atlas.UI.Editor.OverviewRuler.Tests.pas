unit Atlas.UI.Editor.OverviewRuler.Tests;

// Übersichtsleiste (#519), Darstellung: feste Breite, Klick auf eine Marke
// springt zu ihrer Zeile, daneben zur Zeile an der Stelle, Überfahren meldet
// Zeile und Marke, Farben je Art.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Editor.OverviewRuler;

type
  [TestFixture]
  TAtlasOverviewRulerTests = class
  private
    FForm: TForm;
    FRuler: TAtlasOverviewRuler;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsWidth;
    [Test]
    procedure ClickJumpsToMarkOrLine;
    [Test]
    procedure HoverReportsLineAndMark;
    [Test]
    procedure ColorsDifferByKind;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Editor.Overview;

type
  TRulerAccess = class(TAtlasOverviewRuler);

procedure TAtlasOverviewRulerTests.WarmUpFirstUse;
begin
  SetUp;
  try
    KeepsWidth;
  finally
    TearDown;
  end;
end;

procedure TAtlasOverviewRulerTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 400;
  FForm.Height := 600;
  FRuler := TAtlasOverviewRuler.Create(FForm);
  FRuler.Parent := FForm;
  FRuler.Align := alRight;
  FRuler.HandleNeeded;
end;

procedure TAtlasOverviewRulerTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FRuler := nil;
end;

procedure TAtlasOverviewRulerTests.KeepsWidth;
var
  Width_: Integer;
begin
  Width_ := FRuler.Width;
  Assert.AreEqual(TAtlasOverviewRuler.RulerWidth(FRuler.CurrentPPI), Width_);
  FRuler.Width := Width_ * 4;
  Assert.AreEqual(Width_, FRuler.Width, 'schmal, nie breiter');
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 3, 1)], 10, 0, 4);
  FRuler.Repaint;
end;

procedure TAtlasOverviewRulerTests.ClickJumpsToMarkOrLine;
var
  Jumped, Y: Integer;
begin
  Jumped := -1;
  FRuler.OnJump :=
    procedure(ALine: Integer)
    begin
      Jumped := ALine;
    end;
  // Fehler in Zeile 900 von 1000: unten im Streifen (Akzeptanzkriterium).
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 899, 1, 'E2003')], 1000, 0, 50);
  Y := TAtlasOverview.PixelOf(899, 1000, FRuler.ClientHeight);
  Assert.IsTrue(Y > FRuler.ClientHeight * 8 div 10, 'unten');
  Assert.AreEqual(0, FRuler.MarkAtY(Y + 1));
  TRulerAccess(FRuler).MouseDown(mbLeft, [], 2, Y + 1);
  Assert.AreEqual(899, Jumped, 'zur Zeile der Marke');
  TRulerAccess(FRuler).MouseDown(mbLeft, [], 2, 0);
  Assert.AreEqual(0, Jumped, 'ohne Marke zur Zeile an der Stelle');
  TRulerAccess(FRuler).MouseDown(mbRight, [], 2, Y);
  Assert.AreEqual(0, Jumped, 'nur links');
end;

procedure TAtlasOverviewRulerTests.HoverReportsLineAndMark;
var
  Line, Mark, Ended: Integer;
  Y: Integer;
begin
  Line := -1;
  Mark := -2;
  Ended := 0;
  FRuler.OnHover :=
    procedure(ALine, AMark: Integer; const APoint: TPoint)
    begin
      Line := ALine;
      Mark := AMark;
    end;
  FRuler.OnHoverEnd :=
    procedure
    begin
      Inc(Ended);
    end;
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 50, 1, 'Treffer')], 100, 0, 10);
  Y := TAtlasOverview.PixelOf(50, 100, FRuler.ClientHeight);
  TRulerAccess(FRuler).MouseMove([], 2, Y);
  Assert.AreEqual(50, Line);
  Assert.AreEqual(0, Mark);
  TRulerAccess(FRuler).MouseMove([], 2, 0);
  Assert.AreEqual(0, Line);
  Assert.AreEqual(-1, Mark);
  TRulerAccess(FRuler).Perform(CM_MOUSELEAVE, 0, 0);
  Assert.AreEqual(1, Ended);
end;

procedure TAtlasOverviewRulerTests.ColorsDifferByKind;
var
  Colors: TAtlasColors;
begin
  Colors := TAtlasColors.Dark;
  Assert.AreNotEqual(Integer(TAtlasOverviewRuler.ColorOf(Colors, TAtlasOverviewMarkKind.Error)),
    Integer(TAtlasOverviewRuler.ColorOf(Colors, TAtlasOverviewMarkKind.Warning)));
  Assert.AreNotEqual(Integer(TAtlasOverviewRuler.ColorOf(Colors, TAtlasOverviewMarkKind.Added)),
    Integer(TAtlasOverviewRuler.ColorOf(Colors, TAtlasOverviewMarkKind.Modified)));
  Assert.AreEqual(Integer(Colors.Error), Integer(TAtlasOverviewRuler.ColorOf(Colors, TAtlasOverviewMarkKind.Error)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverviewRulerTests);

end.
