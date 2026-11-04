unit Atlas.Core.Architecture.View;

// Fenster „Atlas-Architektur“ (#1118): TAtlasArchitectureView rechnet die
// Karte zwischen Lage (Koordinaten des Servers, TAtlasArchitectureModel) und
// Bildpunkten um: Einpassen, Zoomen um einen Punkt, Verschieben, Treffer
// einer Unit. Ohne VCL und OTA.

interface

uses
  Atlas.Core.Architecture.Model;

type
  TAtlasArchitectureView = record
  public const
    MinScale = 0.05;
    MaxScale = 8.0;
    /// <summary>Rand beim Einpassen in Bildpunkten.</summary>
    Margin = 20;
  public
    Scale: Double;
    OffsetX: Double;
    OffsetY: Double;
    /// <summary>Alle Teilsysteme in AWidth × AHeight einpassen, höchstens doppelt vergrößert.</summary>
    procedure Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
    function ScreenX(AX: Double): Double;
    function ScreenY(AY: Double): Double;
    function WorldX(AX: Double): Double;
    function WorldY(AY: Double): Double;
    /// <summary>Um AFactor zoomen; der Punkt unter (AX, AY) bleibt stehen.</summary>
    procedure ZoomAt(AFactor: Double; AX, AY: Double);
    procedure Pan(ADX, ADY: Double);
    /// <summary>Unit unter dem Bildpunkt (AX, AY), bei Überlappung die zuletzt gezeichnete; -1 ohne.</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer; overload;
    /// <summary>Wie oben, ohne Units ausgeblendeter Teilsysteme (AHidden je Teilsystem).</summary>
    function UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
      const AHidden: TArray<Boolean>): Integer; overload;
  end;

implementation

uses
  System.Math;

{ TAtlasArchitectureView }

procedure TAtlasArchitectureView.Fit(const AModel: TAtlasArchitectureModel; AWidth, AHeight: Integer);
var
  Subsystem: TAtlasArchSubsystem;
  Left, Top, Right, Bottom: Double;
begin
  Scale := 1;
  OffsetX := AWidth / 2;
  OffsetY := AHeight / 2;
  if Length(AModel.Subsystems) = 0 then
  begin
    Exit;
  end;
  Left := MaxDouble;
  Top := MaxDouble;
  Right := -MaxDouble;
  Bottom := -MaxDouble;
  for Subsystem in AModel.Subsystems do
  begin
    Left := Min(Left, Subsystem.X - Subsystem.R);
    Top := Min(Top, Subsystem.Y - Subsystem.R);
    Right := Max(Right, Subsystem.X + Subsystem.R);
    Bottom := Max(Bottom, Subsystem.Y + Subsystem.R);
  end;
  Scale := Min(Min((AWidth - 2 * Margin) / Max(1, Right - Left), (AHeight - 2 * Margin) / Max(1, Bottom - Top)), 2);
  Scale := EnsureRange(Scale, MinScale, MaxScale);
  OffsetX := AWidth / 2 - (Left + Right) / 2 * Scale;
  OffsetY := AHeight / 2 - (Top + Bottom) / 2 * Scale;
end;

function TAtlasArchitectureView.ScreenX(AX: Double): Double;
begin
  Result := AX * Scale + OffsetX;
end;

function TAtlasArchitectureView.ScreenY(AY: Double): Double;
begin
  Result := AY * Scale + OffsetY;
end;

function TAtlasArchitectureView.WorldX(AX: Double): Double;
begin
  Result := (AX - OffsetX) / Scale;
end;

function TAtlasArchitectureView.WorldY(AY: Double): Double;
begin
  Result := (AY - OffsetY) / Scale;
end;

procedure TAtlasArchitectureView.ZoomAt(AFactor: Double; AX, AY: Double);
var
  Next: Double;
begin
  Next := EnsureRange(Scale * AFactor, MinScale, MaxScale);
  OffsetX := AX - (AX - OffsetX) * Next / Scale;
  OffsetY := AY - (AY - OffsetY) * Next / Scale;
  Scale := Next;
end;

procedure TAtlasArchitectureView.Pan(ADX, ADY: Double);
begin
  OffsetX := OffsetX + ADX;
  OffsetY := OffsetY + ADY;
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double): Integer;
begin
  Result := UnitAt(AModel, AX, AY, nil);
end;

function TAtlasArchitectureView.UnitAt(const AModel: TAtlasArchitectureModel; AX, AY: Double;
  const AHidden: TArray<Boolean>): Integer;
var
  Index: Integer;
  X, Y, Radius: Double;
begin
  X := WorldX(AX);
  Y := WorldY(AY);
  // Rückwärts: Später gezeichnete Units liegen oben.
  for Index := High(AModel.Units) downto 0 do
  begin
    if AModel.IsHidden(Index, AHidden) then
    begin
      Continue;
    end;
    // Mindestens 4 Bildpunkte, damit kleine Units weit herausgezoomt treffbar bleiben.
    Radius := Max(AModel.NodeRadius(Index), 4 / Scale);
    if Sqr(AModel.Units[Index].X - X) + Sqr(AModel.Units[Index].Y - Y) <= Sqr(Radius) then
    begin
      Exit(Index);
    end;
  end;
  Result := -1;
end;

end.
