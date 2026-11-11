unit Atlas.UI.Designer.ToolStrings;

// Oberflächentexte der Designer-Werkzeuge mit eigenem Knopf in der
// Designer-Leiste (Abstandsgriffe #734) auf Deutsch und Englisch. Die
// Sprache bestimmt Base (`TAtlasStrings.Language`) wie bei
// `Atlas.UI.Designer.Strings`.

interface

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasDesignerToolTextId = (
    GapHint, GapShow, GapSetCmd, GapUndo, GapUndone, GapSetTitle, GapSetPrompt, GapInvalid, GapOutsideConfirm,
    GapDone, GapNeeds, SettingsGapHandles, SettingsGapSnap, SettingsGapAnchor, SettingsGapCenter, SettingsGapFirst,
    SettingsGapLast);

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
     'Letzte Komponente'),
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
     'Last component'));

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
