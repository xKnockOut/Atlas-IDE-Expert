unit Atlas.Core.Problems.Switches;

// Zusammengesetzte Schalter aus den wirksamen Einstellungen des Plugins (#1967), für Atlas.IDE.Foundation.Settings:
// - Inline-Diagnosen: nur mit Hauptschalter und Problemen an, sonst Off; die Stufe aus der Einstellung
//   InlineDiagnostics.
// - Zähler der Befunde in der Statusleiste der IDE: nur, wenn die eigene Statusleiste des Editors die Befunde nicht
//   schon zeigt (sonst stünden sie doppelt da).

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Problems.InlineHints;

type
  TAtlasProblemSwitches = class
  public
    /// <summary>Stufe der Inline-Diagnosen; Off ohne Hauptschalter oder ohne Problemmarkierungen.</summary>
    class function InlineDiagnostics(const ASettings: TAtlasPluginSettings): TAtlasInlineDiagnosticsMode; static;
    /// <summary>Befundzähler in der Statusleiste der IDE zeigen?</summary>
    class function ProblemsStatusCounter(const ASettings: TAtlasPluginSettings): Boolean; static;
  end;

implementation

uses
  Atlas.Core.Settings.StatusBarItems;

{ TAtlasProblemSwitches }

class function TAtlasProblemSwitches.InlineDiagnostics(
  const ASettings: TAtlasPluginSettings): TAtlasInlineDiagnosticsMode;
begin
  Result := TAtlasInlineDiagnosticsMode.Off;
  if ASettings.Enabled and ASettings.Problems then
  begin
    Result := TAtlasInlineDiagnostics.ModeOf(ASettings.InlineDiagnostics);
  end;
end;

class function TAtlasProblemSwitches.ProblemsStatusCounter(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.Enabled and ASettings.Problems and ASettings.ProblemsStatusCounter and
    not (ASettings.EditorStatusBar and TAtlasStatusBarItems.Contains(
    TAtlasStatusBarItems.Parse(ASettings.EditorStatusBarItems), TAtlasStatusBarItems.cFindings));
end;

end.
