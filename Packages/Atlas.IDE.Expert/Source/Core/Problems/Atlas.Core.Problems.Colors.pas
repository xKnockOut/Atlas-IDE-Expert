unit Atlas.Core.Problems.Colors;

// Farbe eines Problems (D-07): eine Stelle für Wellenlinie im Editor und
// Problemzeile im Hover-Tooltip. Fehler, Warnung, Info nach Schweregrad,
// Hinweise gedämpft; blasse Probleme (Text seither geändert) mit AtlasMixFaded
// über der Fläche gemischt. Eigene Unit, damit Contract frei von Style bleibt.
// Fenster „Atlas-Prüfung“ (#1108): Text und Symbole nicht geöffneter Units
// ausgegraut (Text mit mindestens 4,5 : 1 Kontrast, Symbole aufgehellt in
// derselben Form), Zeilen der aktiven Unit leicht in Akzentfarbe hinterlegt.

interface

uses
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Problems.Contract;

/// <summary>Farbe von AProblem in den Rollen AColors; blasse Probleme abgeschwächt.</summary>
function ProblemColor(const AColors: TAtlasColors; const AProblem: TAtlasProblem): TAtlasColor;

const
  /// <summary>Mindestkontrast ausgegrauter Zeilen (WCAG AA).</summary>
  AtlasDimmedMinContrast = 4.5;
  /// <summary>Anteil des Textes über der Fläche für ausgegraute Zeilen, bevor der Kontrast nachgezogen wird.</summary>
  AtlasMixDimmedText = 0.55;
  /// <summary>Anteil der Symbolfarbe über der Fläche für ausgegraute Symbole.</summary>
  AtlasMixDimmedIcon = 0.45;
  /// <summary>Anteil des Akzents über der Fläche für die angepinnte aktive Unit (hell etwa #EEF4FB).</summary>
  AtlasMixPinned = 0.07;

/// <summary>Text einer ausgegrauten Zeile: AText zur Fläche ABack hin gemischt, aber mit mindestens 4,5 : 1
/// Kontrast.</summary>
function DimmedTextColor(AText, ABack: TAtlasColor): TAtlasColor;
/// <summary>Symbol einer ausgegrauten Zeile: AIcon zur Fläche hin aufgehellt bzw. abgedunkelt.</summary>
function DimmedIconColor(AIcon, ABack: TAtlasColor): TAtlasColor;
/// <summary>Hintergrund der angepinnten aktiven Unit auf der Fläche ABack.</summary>
function PinnedBackColor(ABack: TAtlasColor): TAtlasColor;

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

function DimmedTextColor(AText, ABack: TAtlasColor): TAtlasColor;
var
  Alpha: Double;
  Steps: Integer;
begin
  Alpha := AtlasMixDimmedText;
  Result := TAtlasColorMath.Mix(AText, ABack, Alpha);
  // Schrittweise zurück zum vollen Text, bis der Kontrast reicht; der volle Text ist die Untergrenze.
  while (TAtlasColorMath.Contrast(Result, ABack) < AtlasDimmedMinContrast) and (Alpha < 1) do
  begin
    Alpha := Alpha + 0.05;
    if Alpha > 1 then
      Alpha := 1;
    Result := TAtlasColorMath.Mix(AText, ABack, Alpha);
  end;
  // Schon der volle Text ist zu blass (manche Themen): vom Hintergrund weg verstärken.
  Steps := 0;
  while (TAtlasColorMath.Contrast(Result, ABack) < AtlasDimmedMinContrast) and (Steps < 20) do
  begin
    if TAtlasColorMath.IsDark(ABack) then
      Result := TAtlasColorMath.Lighten(Result, 0.05)
    else
      Result := TAtlasColorMath.Darken(Result, 0.05);
    Inc(Steps);
  end;
end;

function DimmedIconColor(AIcon, ABack: TAtlasColor): TAtlasColor;
begin
  Result := TAtlasColorMath.Mix(AIcon, ABack, AtlasMixDimmedIcon);
end;

function PinnedBackColor(ABack: TAtlasColor): TAtlasColor;
begin
  Result := TAtlasColorMath.Mix(TAtlasColors.ForBackground(ABack).Accent, ABack, AtlasMixPinned);
end;

end.
