unit Atlas.Vcl.Controls.ZoomView.Tests;

// Zoombare Ansicht: Das Mausrad zoomt um den Mauszeiger in Client-Koordinaten, nach oben vergrößernd, nach unten
// verkleinernd, und gilt als verarbeitet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasZoomViewTests = class
  public
    [Test]
    procedure WheelUpZoomsInAtMouse;
    [Test]
    procedure WheelDownZoomsOut;
  end;

implementation

uses
  System.Classes,
  System.Types,
  System.Math,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Vcl.Controls.ZoomView;

const
  cLeft = 30;
  cTop = 20;
  cWheelStep = 120;
  cMouseX = 15;
  cMouseY = 25;

type
  /// <summary>Merkt sich den letzten Zoom statt eine Ansicht umzurechnen.</summary>
  TRecordingView = class(TAtlasZoomView)
  private
    FFactor: Double;
    FX: Double;
    FY: Double;
  protected
    procedure ZoomAround(AFactor, AX, AY: Double); override;
  public
    function Wheel(ADelta: Integer; const AClient: TPoint): Boolean;
    property Factor: Double read FFactor;
    property X: Double read FX;
    property Y: Double read FY;
  end;

procedure TRecordingView.ZoomAround(AFactor, AX, AY: Double);
begin
  FFactor := AFactor;
  FX := AX;
  FY := AY;
end;

function TRecordingView.Wheel(ADelta: Integer; const AClient: TPoint): Boolean;
begin
  Result := DoMouseWheel([], ADelta, ClientToScreen(AClient));
end;

/// <summary>Ansicht mit Fenster auf AForm, damit ClientToScreen gilt.</summary>
function NewView(AForm: TForm): TRecordingView;
begin
  Result := TRecordingView.Create(AForm);
  Result.Parent := AForm;
  Result.SetBounds(cLeft, cTop, AForm.ClientWidth div 2, AForm.ClientHeight div 2);
  Result.HandleNeeded;
end;

{ TAtlasZoomViewTests }

procedure TAtlasZoomViewTests.WheelUpZoomsInAtMouse;
var
  mForm: TForm;
  mView: TRecordingView;
begin
  mForm := TForm.CreateNew(nil);
  try
    mView := NewView(mForm);
    Assert.IsTrue(mView.Wheel(cWheelStep, Point(cMouseX, cMouseY)));
    Assert.IsTrue(SameValue(TAtlasZoomView.cWheelZoom, mView.Factor), 'Faktor');
    Assert.IsTrue(SameValue(Double(cMouseX), mView.X), 'X in Client-Koordinaten');
    Assert.IsTrue(SameValue(Double(cMouseY), mView.Y), 'Y in Client-Koordinaten');
  finally
    mForm.Free;
  end;
end;

procedure TAtlasZoomViewTests.WheelDownZoomsOut;
var
  mForm: TForm;
  mView: TRecordingView;
begin
  mForm := TForm.CreateNew(nil);
  try
    mView := NewView(mForm);
    Assert.IsTrue(mView.Wheel(-cWheelStep, Point(cMouseX, cMouseY)));
    Assert.IsTrue(SameValue(1 / TAtlasZoomView.cWheelZoom, mView.Factor));
  finally
    mForm.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasZoomViewTests);

end.
