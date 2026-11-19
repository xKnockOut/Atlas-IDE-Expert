unit Atlas.Core.Designer.GridSnap;

// Einrasten am Raster des Designers, ohne VCL und Windows. Gemeinsam für
// „Platz einfügen“ und das Ziehen mehrerer Steuerelemente.

interface

type
  TAtlasGridSnap = class
  public
    /// <summary>AValue auf das nächste Vielfache von AGrid gerundet; mit AGrid bis 1 unverändert.</summary>
    class function Snap(AValue, AGrid: Integer): Integer; static;
  end;

implementation

{ TAtlasGridSnap }

class function TAtlasGridSnap.Snap(AValue, AGrid: Integer): Integer;
begin
  Result := AValue;
  if AGrid > 1 then
  begin
    Result := Round(AValue / AGrid) * AGrid;
  end;
end;

end.
