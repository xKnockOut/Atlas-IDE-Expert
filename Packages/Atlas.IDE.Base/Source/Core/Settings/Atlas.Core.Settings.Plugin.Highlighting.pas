unit Atlas.Core.Settings.Plugin.Highlighting;

// Einstellungen des IDE-Plugins, Bereich Hervorhebung (highlight.*) (#227, ADR 0017):
// Felder, Vorgaben, Grenzen, Lesen und Schreiben. TAtlasPluginSettings (Atlas.Core.Settings.Plugin)
// fasst die Bereiche zusammen und reicht die Felder als Eigenschaften durch.

interface

uses
  Atlas.Core.Settings.Plugin.Store;

const
  /// <summary>Grenzen für highlight.selectionMatches.minLength und .maxMatches (#709).</summary>
  MinSelectionMatchLength = 1;
  MaxSelectionMatchLength = 100;
  MinSelectionMatches = 1;
  MaxSelectionMatches = 100000;
  MinPairGuideWidth = 1;
  MaxPairGuideWidth = 3;
  MinPairGuideOpacity = 10;
  MaxPairGuideOpacity = 100;

type
  /// <summary>Plugin-Einstellungen: Hervorhebungen im Editor und Farben.</summary>
  TAtlasPluginHighlightingSettings = record
    /// <summary>Klammer- und Blockpaare nach Tiefe färben (#514).</summary>
    PairColors: Boolean;
    /// <summary>Inaktive {$IFDEF}-Zweige im Editor ausgrauen (#615).</summary>
    InactiveDim: Boolean;
    /// <summary>Blocklinien in den Paarfarben statt der Strukturhervorhebung der IDE (#514).</summary>
    PairGuides: Boolean;
    /// <summary>Schlüsselwörter der Anweisung (if, then, else, for, do, procedure …) in der Farbe ihres
    /// Blocks; Blocklinien beginnen an der Anweisung (#653). Wirkt nur mit PairColors.</summary>
    PairOwners: Boolean;
    /// <summary>Breite der Blocklinien in Pixeln bei 100 % (1–3, #653).</summary>
    PairGuideWidth: Integer;
    /// <summary>Deckkraft der Blocklinien in Prozent; der Rest ist Hintergrund.</summary>
    PairGuideOpacity: Integer;
    /// <summary>Eigene Paarfarben je Thema („#RRGGBB,…“, fünf Stück); leer = Standardpalette.</summary>
    PairColorsLight: string;
    PairColorsDark: string;
    /// <summary>Lokale Routinen färben (#1788): outer (wie die äußere Routine), deeper (eine Stufe tiefer) oder
    /// color (eigene Farbe, Blocklinie gestrichelt).</summary>
    NestedRoutines: string;
    /// <summary>Zeilen lokaler Routinen schwach in ihrer Farbe hinterlegen (#1788).</summary>
    NestedRoutineBand: Boolean;
    /// <summary>Eigene Farbe lokaler Routinen je Thema („#RRGGBB“); leer = Palette (#1788).</summary>
    NestedRoutineColorLight: string;
    NestedRoutineColorDark: string;
    /// <summary>Gleichen Text wie die Markierung hervorheben (#709, highlight.selectionMatches).</summary>
    SelectionMatches: Boolean;
    /// <summary>Mindestlänge der Markierung, MinMinLength bis MaxMinLength von TAtlasSelectionMatches (#709).
    /// </summary>
    SelectionMatchesMinLength: Integer;
    /// <summary>Groß-/Kleinschreibung beachten (#709).</summary>
    SelectionMatchesCaseSensitive: Boolean;
    /// <summary>Nur ganze Wörter (#709).</summary>
    SelectionMatchesWholeWord: Boolean;
    /// <summary>F3/Umschalt+F3 springt zwischen den Treffern, solange die Markierung steht (#709).</summary>
    SelectionMatchesNavigateF3: Boolean;
    /// <summary>Höchstzahl der Treffer (#709).</summary>
    SelectionMatchesMaxMatches: Integer;
    /// <summary>Austrittspunkte hervorheben (#698, editor.exitPoints).</summary>
    ExitPoints: Boolean;
    /// <summary>Auf except bzw. on die auslösenden Aufrufe zeigen (#698).</summary>
    ExitPointsExceptions: Boolean;
    /// <summary>Auf Break bzw. Continue die Schleife zeigen (#698).</summary>
    ExitPointsLoops: Boolean;
    /// <summary>Marke mit der Anzahl am Routinenkopf (#698).</summary>
    ExitPointsBadge: Boolean;
    /// <summary>Neu zugewiesene Variablen unterstreichen (#712, highlight.reassigned).</summary>
    Reassigned: Boolean;
    /// <summary>Arten, kommagetrennt: locals, loopVars, valueParams, varParams, fields (#712), siehe
    /// TAtlasReassignedNames.</summary>
    ReassignedTargets: string;
    /// <summary>Linie: dotted, solid oder wavy (#712).</summary>
    ReassignedStyle: string;
    /// <summary>Farbe: theme oder #RRGGBB (#712).</summary>
    ReassignedColor: string;
    /// <summary>Vorgaben.</summary>
    class function Defaults: TAtlasPluginHighlightingSettings; static;
    /// <summary>Werte in ihre Grenzen bringen.</summary>
    procedure Normalize;
    /// <summary>Werte über AIo lesen bzw. schreiben, jeden unter seinem Namen.</summary>
    procedure Exchange(const AIo: TAtlasSettingsExchange);
  end;

implementation

uses
  System.Math,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette;

/// <summary>Eigene Paarfarben einheitlich schreiben; ungültig = leer (Standardpalette).</summary>
function NormalPairs(const AText: string): string;
var
  Pairs: TAtlasPairColors;
begin
  if TAtlasColors.ParsePairs(AText, Pairs) then
  begin
    Result := TAtlasColors.PairsText(Pairs);
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Eine Farbe einheitlich schreiben; ungültig = leer (Palette, #1788).</summary>
function NormalColor(const AText: string): string;
var
  mColor: TAtlasColor;
begin
  Result := '';
  if TAtlasColors.ParseColor(AText, mColor) then
  begin
    Result := TAtlasColorMath.ToHex(mColor);
  end;
end;

{ TAtlasPluginHighlightingSettings }

class function TAtlasPluginHighlightingSettings.Defaults: TAtlasPluginHighlightingSettings;
begin
  Result.PairColors := True;
  Result.InactiveDim := True;
  Result.PairGuides := True;
  Result.PairOwners := True;
  Result.PairGuideWidth := 1;
  Result.PairGuideOpacity := 75;
  Result.PairColorsLight := '';
  Result.PairColorsDark := '';
  Result.NestedRoutines := 'deeper';
  Result.NestedRoutineBand := False;
  Result.NestedRoutineColorLight := '';
  Result.NestedRoutineColorDark := '';
  Result.SelectionMatches := True;
  Result.SelectionMatchesMinLength := 3;
  Result.SelectionMatchesCaseSensitive := False;
  Result.SelectionMatchesWholeWord := False;
  Result.SelectionMatchesNavigateF3 := True;
  Result.SelectionMatchesMaxMatches := 1000;
  Result.ExitPoints := True;
  Result.ExitPointsExceptions := True;
  Result.ExitPointsLoops := True;
  Result.ExitPointsBadge := True;
  Result.Reassigned := True;
  Result.ReassignedTargets := TAtlasReassignedNames.TargetsText(TAtlasReassignedNames.DefaultTargets);
  Result.ReassignedStyle := 'dotted';
  Result.ReassignedColor := TAtlasReassignedNames.ThemeColor;
end;

procedure TAtlasPluginHighlightingSettings.Normalize;
begin
  PairGuideWidth := EnsureRange(PairGuideWidth, MinPairGuideWidth, MaxPairGuideWidth);
  PairGuideOpacity := EnsureRange(PairGuideOpacity, MinPairGuideOpacity, MaxPairGuideOpacity);
  PairColorsLight := NormalPairs(PairColorsLight);
  PairColorsDark := NormalPairs(PairColorsDark);
  NestedRoutines := Choice(NestedRoutines, ['deeper', 'outer', 'color']);
  NestedRoutineColorLight := NormalColor(NestedRoutineColorLight);
  NestedRoutineColorDark := NormalColor(NestedRoutineColorDark);
  SelectionMatchesMinLength := EnsureRange(SelectionMatchesMinLength, MinSelectionMatchLength,
    MaxSelectionMatchLength);
  SelectionMatchesMaxMatches := EnsureRange(SelectionMatchesMaxMatches, MinSelectionMatches, MaxSelectionMatches);
  ReassignedTargets := TAtlasReassignedNames.NormalizeTargets(ReassignedTargets);
  ReassignedStyle := Choice(ReassignedStyle, TAtlasReassignedNames.Styles);
  ReassignedColor := TAtlasReassignedNames.NormalizeColor(ReassignedColor);
end;

procedure TAtlasPluginHighlightingSettings.Exchange(const AIo: TAtlasSettingsExchange);
begin
  AIo.Flag('PairColors', PairColors);
  AIo.Flag('InactiveDim', InactiveDim);
  AIo.Flag('PairGuides', PairGuides);
  AIo.Flag('PairOwners', PairOwners);
  AIo.Number('PairGuideWidth', PairGuideWidth);
  AIo.Number('PairGuideOpacity', PairGuideOpacity);
  AIo.Text('PairColorsLight', PairColorsLight);
  AIo.Text('PairColorsDark', PairColorsDark);
  AIo.Text('NestedRoutines', NestedRoutines);
  AIo.Flag('NestedRoutineBand', NestedRoutineBand);
  AIo.Text('NestedRoutineColorLight', NestedRoutineColorLight);
  AIo.Text('NestedRoutineColorDark', NestedRoutineColorDark);
  AIo.Flag('SelectionMatches', SelectionMatches);
  AIo.Number('SelectionMatchesMinLength', SelectionMatchesMinLength);
  AIo.Flag('SelectionMatchesCaseSensitive', SelectionMatchesCaseSensitive);
  AIo.Flag('SelectionMatchesWholeWord', SelectionMatchesWholeWord);
  AIo.Flag('SelectionMatchesNavigateF3', SelectionMatchesNavigateF3);
  AIo.Number('SelectionMatchesMaxMatches', SelectionMatchesMaxMatches);
  AIo.Flag('ExitPoints', ExitPoints);
  AIo.Flag('ExitPointsExceptions', ExitPointsExceptions);
  AIo.Flag('ExitPointsLoops', ExitPointsLoops);
  AIo.Flag('ExitPointsBadge', ExitPointsBadge);
  AIo.Flag('Reassigned', Reassigned);
  AIo.Text('ReassignedTargets', ReassignedTargets);
  AIo.Text('ReassignedStyle', ReassignedStyle);
  AIo.Text('ReassignedColor', ReassignedColor);
end;

end.
