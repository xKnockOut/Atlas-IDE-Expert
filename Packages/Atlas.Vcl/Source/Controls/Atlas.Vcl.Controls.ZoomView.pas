unit Atlas.Vcl.Controls.ZoomView;

// Gemeinsamer Vorfahr der selbst gezeichneten, zoombaren Ansichten (Aufrufdiagramm, Architekturkarte): Das Mausrad
// zoomt um den Mauszeiger, Tasten zoomen in festen Schritten. Die Ansicht selbst rechnet nur ihre Koordinaten um
// (ZoomAround); neu zeichnen übernimmt der Vorfahr.

interface

uses
  System.Classes,
  System.Types,
  Vcl.Controls;

type
  TAtlasZoomView = class(TCustomControl)
  public const
    /// <summary>Vergrößerung je Taste (+/-) und je Schritt des Mausrads.</summary>
    cKeyZoom = 1.25;
    cWheelZoom = 1.15;
  protected
    /// <summary>Um den Punkt (AX, AY) in Client-Koordinaten um AFactor vergrößern (kleiner 1: verkleinern).
    /// </summary>
    procedure ZoomAround(AFactor, AX, AY: Double); virtual; abstract;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  end;

implementation

{ TAtlasZoomView }

function TAtlasZoomView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mLocal: TPoint;
begin
  Result := True;
  mLocal := ScreenToClient(MousePos);
  if WheelDelta > 0 then
  begin
    ZoomAround(cWheelZoom, mLocal.X, mLocal.Y);
  end
  else
  begin
    ZoomAround(1 / cWheelZoom, mLocal.X, mLocal.Y);
  end;
  Invalidate;
end;

end.
