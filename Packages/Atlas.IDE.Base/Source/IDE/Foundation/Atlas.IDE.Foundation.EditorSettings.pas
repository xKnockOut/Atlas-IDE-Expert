unit Atlas.IDE.Foundation.EditorSettings;

// Schalter des Editors aus den wirksamen Einstellungen (TAtlasIdeSettings),
// für häufige Abfragen beim Zeichnen und bei jedem Tastendruck: Inlay-Hints,
// Blockende, ungenutzte uses, Rekursion, Atlas-Spalte, gleicher Text,
// Austrittspunkte, neu zugewiesene Variablen und Problem-Markierungen. Jeder
// Schalter gilt nur mit eingeschaltetem Plugin; gelesen wird ohne Kopie des
// Einstellungsrecords (TAtlasIdeSettings.CurrentRef). Nur im Hauptthread.

interface

uses
  Atlas.Core.Problems.InlineHints,
  Atlas.Core.Editor.SelectionMatches;

type
  TAtlasIdeEditorSettings = class
  public
    /// <summary>Plugin eingeschaltet und Inlay-Hints an; ohne Kopie des Einstellungsrecords.</summary>
    class function InlayHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Typmarken an (#453); ohne Kopie des Einstellungsrecords.</summary>
    class function InlayTypeHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Include-Symbole hinter {$I} an (#860); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function InlayDefineHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Codes von Steuerzeichen an (#862).</summary>
    class function InlayCharHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Marken „braucht kein Self“ an (#686).</summary>
    class function InlayMethodHintsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Blockende-Beschriftungen an (#620); ohne Kopie des Einstellungsrecords.
    /// </summary>
    class function BlockEndLabelsOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und ungenutzte uses abblenden an (#621); ohne Kopie des Einstellungsrecords.
    /// </summary>
    class function DimUnusedUsesOn: Boolean; static;
    /// <summary>editor.blockEndLabels.minLines (#620): Blöcke ab so vielen Zeilen bekommen eine Beschriftung.
    /// </summary>
    class function BlockEndLabelsMinLines: Integer; static;
    /// <summary>Plugin eingeschaltet und Rekursionssymbole an (#623); ohne Kopie des Einstellungsrecords.</summary>
    class function RecursionMarkersOn: Boolean; static;
    /// <summary>editor.recursionMarkers.depth (#623).</summary>
    class function RecursionMarkersDepth: Integer; static;
    /// <summary>Plugin eingeschaltet und Atlas-Spalte in der Zeilenleiste an (#768); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function GutterColumnOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und gleichen Text hervorheben an (#709); AOptions und ANavigateF3 aus
    /// highlight.selectionMatches.*, ohne Kopie des Einstellungsrecords.</summary>
    class function SelectionMatchesOn(out AOptions: TAtlasSelectionMatchOptions; out ANavigateF3: Boolean): Boolean;
      static;
    /// <summary>Plugin eingeschaltet und Austrittspunkte hervorheben an (#698); die Schalter aus
    /// editor.exitPoints.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean; static;
    /// <summary>Plugin eingeschaltet und neu zugewiesene Variablen unterstreichen an (#712); Arten, Linie und Farbe
    /// aus highlight.reassigned.*, ohne Kopie des Einstellungsrecords.</summary>
    class function ReassignedOn(out ATargets, AStyle, AColor: string): Boolean; static;
    /// <summary>Plugin eingeschaltet und Problem-Markierungen an; ohne Kopie des Einstellungsrecords.</summary>
    class function ProblemMarksOn: Boolean; static;
    /// <summary>Plugin eingeschaltet und Marken folgen ihrer Zeile sofort (#1818, editor.trackLines); ohne Kopie des
    /// Einstellungsrecords.</summary>
    class function TrackLinesOn: Boolean; static;
    /// <summary>Fehlertext am Zeilenende (#509); Off, wenn das Plugin oder die Problem-Markierungen aus sind.
    /// </summary>
    class function InlineDiagnosticsMode: TAtlasInlineDiagnosticsMode; static;
    /// <summary>Plugin, Probleme und Zähler in der Statusleiste an (#509), außer die Atlas-Statusleiste am Editor
    /// zeigt ihre Befundzähler (#1155): Dann stünden Zahlen doppelt.</summary>
    class function ProblemsStatusCounterOn: Boolean; static;
  end;

implementation

uses
  Atlas.Core.Problems.Switches,
  Atlas.IDE.Foundation.Settings;

class function TAtlasIdeEditorSettings.InlayHintsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.InlayHints;
end;

class function TAtlasIdeEditorSettings.InlayTypeHintsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.InlayTypeHints;
end;

class function TAtlasIdeEditorSettings.InlayDefineHintsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.InlayDefineHints;
end;

class function TAtlasIdeEditorSettings.InlayCharHintsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.InlayCharHints;
end;

class function TAtlasIdeEditorSettings.InlayMethodHintsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.InlayMethodHints;
end;

class function TAtlasIdeEditorSettings.BlockEndLabelsOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.BlockEndLabels;
end;

class function TAtlasIdeEditorSettings.BlockEndLabelsMinLines: Integer;
begin
  Result := TAtlasIdeSettings.CurrentRef.BlockEndLabelsMinLines;
end;

class function TAtlasIdeEditorSettings.DimUnusedUsesOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.DimUnusedUses;
end;

class function TAtlasIdeEditorSettings.RecursionMarkersOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.RecursionMarkers;
end;

class function TAtlasIdeEditorSettings.RecursionMarkersDepth: Integer;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.RecursionMarkersDepth;
end;

class function TAtlasIdeEditorSettings.GutterColumnOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.GutterColumn;
end;

class function TAtlasIdeEditorSettings.SelectionMatchesOn(out AOptions: TAtlasSelectionMatchOptions;
  out ANavigateF3: Boolean): Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  AOptions.MinLength := mSettings.SelectionMatchesMinLength;
  AOptions.CaseSensitive := mSettings.SelectionMatchesCaseSensitive;
  AOptions.WholeWord := mSettings.SelectionMatchesWholeWord;
  AOptions.MaxMatches := mSettings.SelectionMatchesMaxMatches;
  ANavigateF3 := mSettings.SelectionMatchesNavigateF3;
  Result := mSettings.Enabled and mSettings.SelectionMatches;
end;

class function TAtlasIdeEditorSettings.ExitPointsOn(out AExceptions, ALoops, ABadge: Boolean): Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  AExceptions := mSettings.ExitPointsExceptions;
  ALoops := mSettings.ExitPointsLoops;
  ABadge := mSettings.ExitPointsBadge;
  Result := mSettings.Enabled and mSettings.ExitPoints;
end;

class function TAtlasIdeEditorSettings.ReassignedOn(out ATargets, AStyle, AColor: string): Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  ATargets := mSettings.ReassignedTargets;
  AStyle := mSettings.ReassignedStyle;
  AColor := mSettings.ReassignedColor;
  Result := mSettings.Enabled and mSettings.Reassigned;
end;

class function TAtlasIdeEditorSettings.ProblemMarksOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.Problems;
end;

class function TAtlasIdeEditorSettings.TrackLinesOn: Boolean;
var
  mSettings: PAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.CurrentRef;
  Result := mSettings.Enabled and mSettings.TrackLines;
end;

class function TAtlasIdeEditorSettings.InlineDiagnosticsMode: TAtlasInlineDiagnosticsMode;
begin
  Result := TAtlasProblemSwitches.InlineDiagnostics(TAtlasIdeSettings.CurrentRef^);
end;

class function TAtlasIdeEditorSettings.ProblemsStatusCounterOn: Boolean;
begin
  Result := TAtlasProblemSwitches.ProblemsStatusCounter(TAtlasIdeSettings.CurrentRef^);
end;

end.
