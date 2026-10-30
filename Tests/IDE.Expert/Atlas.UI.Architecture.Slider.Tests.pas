unit Atlas.UI.Architecture.Slider.Tests;

// Regler „Feinheit“ (#1366): Stellung und Wert, Meldung erst beim Loslassen,
// Doppelklick auf 1,0, Tasten, Ziehen mit der Maus.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Architecture.Slider;

type
  [TestFixture]
  TAtlasResolutionSliderTests = class
  private
    FForm: TForm;
    FSlider: TAtlasResolutionSlider;
    FChanged: TArray<Double>;
    FTracked: Integer;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure StartsAtOneInTheMiddle;
    [Test]
    procedure ValueSetterIsSilent;
    [Test]
    procedure ReportsOnlyOnRelease;
    [Test]
    procedure KeysMoveAndReport;
    [Test]
    procedure MouseDragReportsOnMouseUp;
    [Test]
    procedure DoubleClickResets;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Winapi.Windows,
  Vcl.Controls,
  Atlas.Core.Architecture.Model;

type
  /// <summary>Zugang zu den geschützten Maus- und Tastenmethoden.</summary>
  TSliderAccess = class(TAtlasResolutionSlider);

procedure TAtlasResolutionSliderTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 400;
  FForm.Height := 100;
  FSlider := TAtlasResolutionSlider.Create(FForm);
  FSlider.Parent := FForm;
  FSlider.SetBounds(0, 0, 216, 22);
  FChanged := nil;
  FTracked := 0;
  FSlider.OnChange :=
    procedure(AValue: Double)
    begin
      FChanged := FChanged + [AValue];
    end;
  FSlider.OnTracking :=
    procedure(AValue: Double)
    begin
      Inc(FTracked);
    end;
end;

procedure TAtlasResolutionSliderTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FSlider := nil;
  FChanged := nil;
end;

procedure TAtlasResolutionSliderTests.StartsAtOneInTheMiddle;
begin
  Assert.AreEqual(TAtlasArchResolution.Steps div 2, FSlider.Position);
  Assert.AreEqual(Double(1), FSlider.Value, 1E-9);
end;

procedure TAtlasResolutionSliderTests.ValueSetterIsSilent;
begin
  FSlider.Value := 5;
  Assert.AreEqual(TAtlasArchResolution.Steps, FSlider.Position);
  FSlider.Value := 0.01;
  Assert.AreEqual(0, FSlider.Position);
  Assert.AreEqual(0, Integer(Length(FChanged)));
  Assert.AreEqual(0, FTracked);
  // Danach meldet erst eine echte Änderung.
  FSlider.MoveTo(0, True);
  Assert.AreEqual(0, Integer(Length(FChanged)));
end;

procedure TAtlasResolutionSliderTests.ReportsOnlyOnRelease;
begin
  FSlider.MoveTo(60, False);
  FSlider.MoveTo(80, False);
  Assert.AreEqual(2, FTracked);
  Assert.AreEqual(0, Integer(Length(FChanged)));
  FSlider.MoveTo(80, True);
  Assert.AreEqual(1, Integer(Length(FChanged)));
  Assert.AreEqual(TAtlasArchResolution.ValueAt(80), FChanged[0], 1E-9);
  // Begrenzt auf die Enden.
  FSlider.MoveTo(500, True);
  Assert.AreEqual(TAtlasArchResolution.Steps, FSlider.Position);
  Assert.AreEqual(Double(5), FChanged[1], 1E-9);
end;

procedure TAtlasResolutionSliderTests.KeysMoveAndReport;
var
  mKey: Word;
begin
  mKey := VK_RIGHT;
  TSliderAccess(FSlider).KeyDown(mKey, []);
  Assert.AreEqual(0, Integer(mKey), 'Taste verbraucht');
  Assert.AreEqual(51, FSlider.Position);
  mKey := VK_NEXT;
  TSliderAccess(FSlider).KeyDown(mKey, []);
  Assert.AreEqual(41, FSlider.Position);
  mKey := VK_HOME;
  TSliderAccess(FSlider).KeyDown(mKey, []);
  Assert.AreEqual(0, FSlider.Position);
  mKey := VK_END;
  TSliderAccess(FSlider).KeyDown(mKey, []);
  Assert.AreEqual(TAtlasArchResolution.Steps, FSlider.Position);
  Assert.AreEqual(4, Integer(Length(FChanged)));
  // Andere Tasten bleiben unberührt.
  mKey := VK_RETURN;
  TSliderAccess(FSlider).KeyDown(mKey, []);
  Assert.AreEqual(Integer(VK_RETURN), Integer(mKey));
end;

procedure TAtlasResolutionSliderTests.MouseDragReportsOnMouseUp;
begin
  // Ganz rechts drücken, nach links ziehen, loslassen: eine Meldung mit dem Wert am Ende.
  TSliderAccess(FSlider).MouseDown(mbLeft, [ssLeft], FSlider.ClientWidth, 10);
  Assert.AreEqual(TAtlasArchResolution.Steps, FSlider.Position);
  TSliderAccess(FSlider).MouseMove([ssLeft], 0, 10);
  Assert.AreEqual(0, FSlider.Position);
  Assert.AreEqual(0, Integer(Length(FChanged)));
  TSliderAccess(FSlider).MouseUp(mbLeft, [], 0, 10);
  Assert.AreEqual(1, Integer(Length(FChanged)));
  Assert.AreEqual(Double(0.2), FChanged[0], 1E-9);
  // Ohne gedrückte Taste bewegt sich nichts.
  TSliderAccess(FSlider).MouseMove([], FSlider.ClientWidth, 10);
  Assert.AreEqual(0, FSlider.Position);
end;

procedure TAtlasResolutionSliderTests.DoubleClickResets;
begin
  FSlider.MoveTo(10, True);
  TSliderAccess(FSlider).DblClick;
  Assert.AreEqual(Double(1), FSlider.Value, 1E-9);
  Assert.AreEqual(2, Integer(Length(FChanged)));
  Assert.AreEqual(Double(1), FChanged[1], 1E-9);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasResolutionSliderTests);

end.
