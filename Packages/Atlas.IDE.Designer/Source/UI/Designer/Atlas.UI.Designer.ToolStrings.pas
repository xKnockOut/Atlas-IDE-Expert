unit Atlas.UI.Designer.ToolStrings;

// Oberflächentexte der Designer-Werkzeuge mit eigenem Knopf in der
// Designer-Leiste (Abstandsgriffe #734, gemeinsame Größengriffe #737,
// Schnellleiste #735) auf Deutsch und Englisch. Die Sprache bestimmt Base (`TAtlasStrings.Language`) wie bei
// `Atlas.UI.Designer.Strings`.

interface

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasDesignerToolTextId = (
    GapHint, GapShow, GapSetCmd, GapUndo, GapUndone, GapSetTitle, GapSetPrompt, GapInvalid, GapOutsideConfirm,
    GapDone, GapNeeds, SettingsGapHandles, SettingsGapSnap, SettingsGapAnchor, SettingsGapCenter, SettingsGapFirst,
    SettingsGapLast, ResizeHint, ResizeShow, ResizeUndo, ResizeUndone, ResizeLabel, ResizeLabelBoth, ResizeDone,
    SettingsResize, SettingsResizeMode, SettingsResizeDelta, SettingsResizeAlign, SettingsResizeLeftTop,
    BarHint, BarShow, BarUndo, BarUndone, BarDone, BarPartial, BarFontSmaller, BarFontSize, BarFontLarger, BarBold,
    BarBoldShort, BarItalic, BarItalicShort, BarFontColor, BarColorMore, BarSizeTitle, BarSizePrompt, BarSizeInvalid,
    BarFlag, BarAnchor, BarSameWidth, BarSameHeight, BarAlignLeft, BarAlignCenter, BarAlignRight, BarFitText,
    SettingsBar, SettingsBarMode, SettingsBarAuto, SettingsBarShortcut, SettingsBarDelay, SettingsBarItems,
    SettingsBarKey);

{$SCOPEDENUMS OFF}

  TAtlasDesignerToolStrings = class
  public
    class function Text(AId: TAtlasDesignerToolTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDesignerToolTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDesignerToolTextId] of string = (
    ('Abstandsgriffe bei Mehrfachauswahl in Reihe oder Spalte ein- oder ausblenden',
     'Abstandsgriffe zeigen',
     'Abstände setzen …',
     'Abstände rückgängig',
     'Abstände zurückgesetzt.',
     'Abstände setzen',
     'Abstand in Pixeln:',
     'Abstand „%s“ ungültig: erlaubt sind 0 bis %d Pixel.',
     'Mindestens ein Steuerelement ragt dann aus seinem Elternelement (rot umrandet). Trotzdem übernehmen?',
     'Abstände: %d × %d px.',
     'Abstände: Mindestens zwei Steuerelemente im selben Elternelement in einer Reihe oder Spalte markieren.',
     'Abstandsgriffe bei Mehrfachauswahl',
     'Rastwerte beim Ziehen (px, durch Komma getrennt)',
     'Fester Punkt ohne Zusatztaste',
     'Mitte der Gruppe',
     'Erste Komponente',
     'Letzte Komponente',
     'Gemeinsame Größengriffe bei Mehrfachauswahl ein- oder ausblenden',
     'Gemeinsame Größengriffe zeigen',
     'Größen rückgängig',
     'Größen zurückgesetzt.',
     '%d → %d px (%d×)',
     '%d×%d → %d×%d px (%d×)',
     'Größe von %d Steuerelementen geändert.',
     'Gemeinsame Größengriffe bei Mehrfachauswahl',
     'Ziehen ändert',
     'Alle um denselben Betrag',
     'Alle auf dieselbe Kante',
     'Eigene Griffe auch an linker und oberer Kante',
     'Schnellleiste über einer Mehrfachauswahl ein- oder ausblenden',
     'Schnellleiste zeigen',
     'Letzte Änderung der Schnellleiste rückgängig',
     'Schnellleiste: Änderung zurückgenommen.',
     'Schnellleiste: %s bei %d Steuerelementen.',
     '%s (für %d von %d)',
     'Schrift kleiner (alle um einen Punkt)',
     'Schriftgröße; Klick: für alle eingeben',
     'Schrift größer (alle um einen Punkt)',
     'Fett',
     'F',
     'Kursiv',
     'K',
     'Schriftfarbe',
     'Weitere Farben …',
     'Schriftgröße',
     'Größe in Punkt:',
     'Schriftgröße „%s“ ungültig: erlaubt sind %d bis %d.',
     '%s ein/aus',
     'Anchors: %s ein/aus',
     'Gleiche Breite wie %s',
     'Gleiche Höhe wie %s',
     'Text links (Alignment)',
     'Text mittig (Alignment)',
     'Text rechts (Alignment)',
     'Breite nach Text',
     'Schnellleiste über einer Mehrfachauswahl',
     'Einblenden',
     'Automatisch nach kurzer Verzögerung',
     'Nur auf Tastendruck',
     'Verzögerung bis zum Einblenden (ms)',
     'Knöpfe und Reihenfolge (durch Komma getrennt)',
     'Taste zum Einblenden'),
    ('Show or hide gap handles for a multiple selection in a row or column',
     'Show gap handles',
     'Set gaps …',
     'Undo gaps',
     'Gaps restored.',
     'Set gaps',
     'Gap in pixels:',
     'Gap “%s” is invalid: 0 to %d pixels are allowed.',
     'At least one control would stick out of its parent (red frame). Apply anyway?',
     'Gaps: %d × %d px.',
     'Gaps: select at least two controls with the same parent in a row or column.',
     'Gap handles for a multiple selection',
     'Snap values while dragging (px, comma separated)',
     'Fixed point without modifier key',
     'Centre of the group',
     'First component',
     'Last component',
     'Show or hide shared resize handles for a multiple selection',
     'Show shared resize handles',
     'Undo sizes',
     'Sizes restored.',
     '%d → %d px (%d×)',
     '%d×%d → %d×%d px (%d×)',
     'Resized %d controls.',
     'Shared resize handles for a multiple selection',
     'Dragging changes',
     'All by the same amount',
     'All to the same edge',
     'Own handles on the left and top edges too',
     'Show or hide the quick bar for a multiple selection',
     'Show quick bar',
     'Undo last quick bar change',
     'Quick bar: change undone.',
     'Quick bar: %s on %d controls.',
     '%s (for %d of %d)',
     'Smaller font (all by one point)',
     'Font size; click: enter for all',
     'Larger font (all by one point)',
     'Bold',
     'B',
     'Italic',
     'I',
     'Font colour',
     'More colours …',
     'Font size',
     'Size in points:',
     'Font size “%s” is invalid: %d to %d are allowed.',
     'Toggle %s',
     'Toggle anchor %s',
     'Same width as %s',
     'Same height as %s',
     'Align text left (Alignment)',
     'Centre text (Alignment)',
     'Align text right (Alignment)',
     'Width to text',
     'Quick bar for a multiple selection',
     'Appearance',
     'Automatically after a short delay',
     'Only on key press',
     'Delay before it appears (ms)',
     'Buttons and order (comma separated)',
     'Key to show it'));

{ TAtlasDesignerToolStrings }

class function TAtlasDesignerToolStrings.Text(AId: TAtlasDesignerToolTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDesignerToolStrings.Fmt(AId: TAtlasDesignerToolTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
