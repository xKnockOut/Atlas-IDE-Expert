unit Atlas.UI.Foundation.Scaling.Tests;

// Ränder, Innenabstände und Lage in logischen Pixeln (#2675): bei 96 dpi unverändert, bei höherer Pixeldichte
// des Steuerelements skaliert.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Vcl.ExtCtrls;

type
  [TestFixture]
  TAtlasControlScalingTests = class
  private
    FForm: TForm;
    FPanel: TPanel;
    function Device(AValue: Integer): Integer;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure MarginsAreScaled;
    [Test]
    procedure MarginsAllUseOneValue;
    [Test]
    procedure PaddingIsScaled;
    [Test]
    procedure PlaceScalesBounds;
    [Test]
    procedure HigherDensityScalesUp;
  end;

implementation

uses
  Atlas.Core.Style.Scaling,
  Atlas.UI.Foundation.Scaling;

const
  cDoubleDensity = 2;

{ TAtlasControlScalingTests }

procedure TAtlasControlScalingTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TPanel.Create(FForm);
  FPanel.Parent := FForm;
end;

procedure TAtlasControlScalingTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FPanel := nil;
end;

function TAtlasControlScalingTests.Device(AValue: Integer): Integer;
begin
  Result := TAtlasScaling.ToDevice(AValue, FPanel.CurrentPPI);
end;

procedure TAtlasControlScalingTests.MarginsAreScaled;
begin
  TAtlasControlScaling.SetMargins(FPanel, 4, 6, 8, 10);
  Assert.AreEqual(Device(4), FPanel.Margins.Left);
  Assert.AreEqual(Device(6), FPanel.Margins.Top);
  Assert.AreEqual(Device(8), FPanel.Margins.Right);
  Assert.AreEqual(Device(10), FPanel.Margins.Bottom);
end;

procedure TAtlasControlScalingTests.MarginsAllUseOneValue;
begin
  TAtlasControlScaling.SetMarginsAll(FPanel, 12);
  Assert.AreEqual(Device(12), FPanel.Margins.Left);
  Assert.AreEqual(Device(12), FPanel.Margins.Top);
  Assert.AreEqual(Device(12), FPanel.Margins.Right);
  Assert.AreEqual(Device(12), FPanel.Margins.Bottom);
end;

procedure TAtlasControlScalingTests.PaddingIsScaled;
begin
  TAtlasControlScaling.SetPadding(FPanel, 2, 3, 5, 7);
  Assert.AreEqual(Device(2), FPanel.Padding.Left);
  Assert.AreEqual(Device(3), FPanel.Padding.Top);
  Assert.AreEqual(Device(5), FPanel.Padding.Right);
  Assert.AreEqual(Device(7), FPanel.Padding.Bottom);
end;

procedure TAtlasControlScalingTests.PlaceScalesBounds;
begin
  TAtlasControlScaling.Place(FPanel, 10, 20, 100, 50);
  Assert.AreEqual(Device(10), FPanel.Left);
  Assert.AreEqual(Device(20), FPanel.Top);
  Assert.AreEqual(Device(100), FPanel.Width);
  Assert.AreEqual(Device(50), FPanel.Height);
end;

procedure TAtlasControlScalingTests.HigherDensityScalesUp;
begin
  FForm.ScaleForPPI(FForm.CurrentPPI * cDoubleDensity);
  TAtlasControlScaling.SetMargins(FPanel, 5, 5, 5, 5);
  Assert.AreEqual(Device(5), FPanel.Margins.Left);
  Assert.IsTrue(FPanel.Margins.Left >= 5 * cDoubleDensity, 'Rand wächst mit der Pixeldichte');
end;

end.
