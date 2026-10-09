unit Argus.Core.Style.Scaling;

// Zoom des Editors für die Argus-Fenster (#445). Die Open Tools API meldet
// den Zoom (Strg+Mausrad) nicht; die Editorschrift bleibt gleich groß
// eingestellt. Der Caret aber ist so hoch wie eine Editorzeile und wächst mit.
// Aus seiner Höhe und der Höhe der Schrift bei 100 % ergibt sich der Faktor.
// Kleine Abweichungen (Zeilenabstand des Editors) gelten als 100 %.

interface

type
  TArgusScaling = class
  public const
    MinZoom = 0.5;
    MaxZoom = 4.0;
    /// <summary>Bis zu dieser Abweichung nach oben gilt der Zoom als 100 % (Zeilenabstand).</summary>
    Tolerance = 0.25;
  public
    /// <summary>Zoomfaktor aus der Caret-Höhe und der Texthöhe der Editorschrift bei 100 % (beide in
    /// Gerätepixeln); 1 ohne brauchbare Werte.</summary>
    class function ZoomFromCaret(ACaretHeight, ATextHeight: Integer): Double; static;
  end;

implementation

uses
  System.Math;

{ TArgusScaling }

class function TArgusScaling.ZoomFromCaret(ACaretHeight, ATextHeight: Integer): Double;
begin
  if (ACaretHeight <= 0) or (ATextHeight <= 0) then
    Exit(1);
  Result := ACaretHeight / ATextHeight;
  // Der Caret ist bei 100 % etwas höher als der Text (Zeilenabstand), nie kleiner.
  if (Result >= 1 - 0.1) and (Result <= 1 + Tolerance) then
    Exit(1);
  // Oberhalb: den Zeilenabstand wieder herausrechnen, damit 150 % nicht zu 160 % wird.
  if Result > 1 then
    Result := Result / (1 + Tolerance / 2);
  Result := EnsureRange(Result, MinZoom, MaxZoom);
end;

end.
