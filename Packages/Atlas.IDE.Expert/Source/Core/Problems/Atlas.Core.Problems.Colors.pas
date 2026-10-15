unit Atlas.Core.Problems.Colors;

// Farbe eines Problems (D-07): eine Stelle für Wellenlinie im Editor und
// Problemzeile im Hover-Tooltip. Fehler, Warnung, Info nach Schweregrad,
// Hinweise gedämpft; blasse Probleme (Text seither geändert) mit AtlasMixFaded
// über der Fläche gemischt. Eigene Unit, damit Contract frei von Style bleibt.

interface

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract;

/// <summary>Farbe von AProblem in den Rollen AColors; blasse Probleme abgeschwächt.</summary>
function ProblemColor(const AColors: TAtlasColors; const AProblem: TAtlasProblem): TAtlasColor;

implementation

function ProblemColor(const AColors: TAtlasColors; const AProblem: TAtlasProblem): TAtlasColor;
begin
  case AProblem.Severity of
    TAtlasProblemSeverity.Error:
      Result := AColors.Error;
    TAtlasProblemSeverity.Warning:
      Result := AColors.Warn;
    TAtlasProblemSeverity.Information:
      Result := AColors.Accent;
  else
    Result := AColors.Muted;
  end;
  if AProblem.Stale then
    Result := TAtlasColorMath.Mix(Result, AColors.Surface, AtlasMixFaded);
end;

end.
