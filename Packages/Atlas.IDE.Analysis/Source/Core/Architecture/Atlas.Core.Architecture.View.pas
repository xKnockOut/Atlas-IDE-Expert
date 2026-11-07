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
    cMinScale = 0.05;
    cMaxScale = 8.0;
    /// <summary>Rand beim Einpassen in Bildpunkten.</summary>
    cMargin = 20;
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
  mSubsystem: TAtlasArchSubsystem;
  mLeft, mTop, mRight, mBottom: Double;
begin
  Scale := 1;
  OffsetX := AWidth / 2;
  OffsetY := AHeight / 2;
  if Length(AModel.Subsystems) = 0 then
  begin
    Exit;
  end;
  mLeft := MaxDouble;
  mTop := MaxDouble;
  mRight := -MaxDouble;
  mBottom := -MaxDouble;
  for mSubsystem in AModel.Subsystems do
  begin
    mLeft := Min(mLeft, mSubsystem.X - mSubsystem.R);
    mTop := Min(mTop, mSubsystem.Y - mSubsystem.R);
    mRight := Max(mRight, mSubsystem.X + mSubsystem.R);
    mBottom := Max(mBottom, mSubsystem.Y + mSubsystem.R);
  end;
  Scale := Min(Min((AWidth - 2 * cMargin) / Max(1, mRight - mLeft), (AHeight - 2 * cMargin) / Max(1, mBottom - mTop)),
    2);
  Scale := EnsureRange(Scale, cMinScale, cMaxScale);
  OffsetX := AWidth / 2 - (mLeft + mRight) / 2 * Scale;
  OffsetY := AHeight / 2 - (mTop + mBottom) / 2 * Scale;
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
  mNext: Double;
begin
  mNext := EnsureRange(Scale * AFactor, cMinScale, cMaxScale);
  OffsetX := AX - (AX - OffsetX) * mNext / Scale;
  OffsetY := AY - (AY - OffsetY) * mNext / Scale;
  Scale := mNext;
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
  mIndex: Integer;
  X, Y, mRadius: Double;
begin
  X := WorldX(AX);
  Y := WorldY(AY);
  // Rückwärts: Später gezeichnete Units liegen oben.
  for mIndex := High(AModel.Units) downto 0 do
  begin
    if AModel.IsHidden(mIndex, AHidden) then
    begin
      Continue;
    end;
    // Mindestens 4 Bildpunkte, damit kleine Units weit herausgezoomt treffbar bleiben.
    mRadius := Max(AModel.NodeRadius(mIndex), 4 / Scale);
    if Sqr(AModel.Units[mIndex].X - X) + Sqr(AModel.Units[mIndex].Y - Y) <= Sqr(mRadius) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

end.
