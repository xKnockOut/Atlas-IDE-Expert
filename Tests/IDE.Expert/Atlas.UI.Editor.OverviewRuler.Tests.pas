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
  mWidth_: Integer;
begin
  mWidth_ := FRuler.Width;
  Assert.AreEqual(TAtlasOverviewRuler.RulerWidth(FRuler.CurrentPPI), mWidth_);
  FRuler.Width := mWidth_ * 4;
  Assert.AreEqual(mWidth_, FRuler.Width, 'schmal, nie breiter');
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 3, 1)], 10, 0, 4);
  FRuler.Repaint;
end;

procedure TAtlasOverviewRulerTests.ClickJumpsToMarkOrLine;
var
  mJumped, Y: Integer;
begin
  mJumped := -1;
  FRuler.OnJump :=
    procedure(ALine: Integer)
    begin
      mJumped := ALine;
    end;
  // Fehler in Zeile 900 von 1000: unten im Streifen (Akzeptanzkriterium).
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Error, 899, 1, 'E2003')], 1000, 0, 50);
  Y := TAtlasOverview.PixelOf(899, 1000, FRuler.ClientHeight);
  Assert.IsTrue(Y > FRuler.ClientHeight * 8 div 10, 'unten');
  Assert.AreEqual(0, FRuler.MarkAtY(Y + 1));
  TRulerAccess(FRuler).MouseDown(mbLeft, [], 2, Y + 1);
  Assert.AreEqual(899, mJumped, 'zur Zeile der Marke');
  TRulerAccess(FRuler).MouseDown(mbLeft, [], 2, 0);
  Assert.AreEqual(0, mJumped, 'ohne Marke zur Zeile an der Stelle');
  TRulerAccess(FRuler).MouseDown(mbRight, [], 2, Y);
  Assert.AreEqual(0, mJumped, 'nur links');
end;

procedure TAtlasOverviewRulerTests.HoverReportsLineAndMark;
var
  mLine, mMark, mEnded: Integer;
  Y: Integer;
begin
  mLine := -1;
  mMark := -2;
  mEnded := 0;
  FRuler.OnHover :=
    procedure(ALine, AMark: Integer; const APoint: TPoint)
    begin
      mLine := ALine;
      mMark := AMark;
    end;
  FRuler.OnHoverEnd :=
    procedure
    begin
      Inc(mEnded);
    end;
  FRuler.SetMarks([TAtlasOverviewMark.Create(TAtlasOverviewMarkKind.Search, 50, 1, 'Treffer')], 100, 0, 10);
  Y := TAtlasOverview.PixelOf(50, 100, FRuler.ClientHeight);
  TRulerAccess(FRuler).MouseMove([], 2, Y);
  Assert.AreEqual(50, mLine);
  Assert.AreEqual(0, mMark);
  TRulerAccess(FRuler).MouseMove([], 2, 0);
  Assert.AreEqual(0, mLine);
  Assert.AreEqual(-1, mMark);
  TRulerAccess(FRuler).Perform(CM_MOUSELEAVE, 0, 0);
  Assert.AreEqual(1, mEnded);
end;

procedure TAtlasOverviewRulerTests.ColorsDifferByKind;
var
  mColors: TAtlasColors;
begin
  mColors := TAtlasColors.Dark;
  Assert.AreNotEqual(Integer(TAtlasOverviewRuler.ColorOf(mColors, TAtlasOverviewMarkKind.Error)),
    Integer(TAtlasOverviewRuler.ColorOf(mColors, TAtlasOverviewMarkKind.Warning)));
  Assert.AreNotEqual(Integer(TAtlasOverviewRuler.ColorOf(mColors, TAtlasOverviewMarkKind.Added)),
    Integer(TAtlasOverviewRuler.ColorOf(mColors, TAtlasOverviewMarkKind.Modified)));
  Assert.AreEqual(Integer(mColors.Error), Integer(TAtlasOverviewRuler.ColorOf(mColors, TAtlasOverviewMarkKind.Error)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOverviewRulerTests);

end.
