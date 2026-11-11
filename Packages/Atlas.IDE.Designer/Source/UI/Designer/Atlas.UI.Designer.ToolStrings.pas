unit Atlas.UI.Designer.ToolStrings;

// Oberflächentexte der eigenen Knöpfe der Designer-Leiste (#605 ff.: Abstände
// messen, Probegröße, Vorschau in Skalierungen, sprechende Namen, Leiste der
// nichtvisuellen Komponenten, Datenbindungen, In Frame auslagern,
// Ereignis-Karte) auf Deutsch und Englisch. Eigene Tabelle neben
// Atlas.UI.Designer.Strings, damit die Befehle im Menü „Anordnen“ und diese
// Funktionen sich nicht in die Quere kommen. Die Sprache bestimmt Base
// (`TAtlasStrings.Language`); jeder Aufruf liest sie neu.

interface

uses
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  TAtlasDesignerToolTextId = (
    MeasureHint, MeasureAbove, MeasureBelow, MeasureLeftOf, MeasureRightOf, MeasureSameWidth, MeasureSameHeight,
    SettingsMeasureDistances, SettingsMeasureAltKey, ResizeHint, ResizeTitle, ResizeSize, ResizeMinimum, ResizeDesign,
    ResizeNoMinimum, ResizeNone, ResizeCount, ResizeKeys, LayoutTooSmall, LayoutOutRight, LayoutOutBottom,
    LayoutOutLeft, LayoutOutTop, LayoutOverlap, LayoutTwoClient, LayoutAnchorsAlign, LayoutAnchored,
    SettingsResizePreview, SettingsResizeSizes, SettingsResizeAnchors, ToolNoForm);

{$SCOPEDENUMS OFF}

  TAtlasDesignerToolStrings = class
  public
    /// <summary>Text in der Sprache der Oberfläche.</summary>
    class function Text(AId: TAtlasDesignerToolTextId): string; static;
    /// <summary>Text in ALanguage, unabhängig von der Sprache der Oberfläche.</summary>
    class function TextIn(ALanguage: TAtlasLanguage; AId: TAtlasDesignerToolTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDesignerToolTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDesignerToolTextId] of string = (
    ('Abstände messen: Maßlinien beim Ziehen, mit Alt zur Komponente unter der Maus',
     'wie oben',
     'wie unten',
     'wie links',
     'wie rechts',
     'Breite wie %s',
     'Höhe wie %s',
     'Maßlinien beim Verschieben und bei Größenänderung zeigen',
     'Maße mit gedrückter Alt-Taste zur Komponente unter der Maus zeigen',
     'Größe ausprobieren: Vorschau des Formulars in anderer Größe, die DFM bleibt unverändert',
     'Größe ausprobieren – %s',
     'Größe:',
     'Minimum',
     'Design',
     'Das Formular hat keine Constraints.MinWidth/MinHeight.',
     'Keine Befunde bei %d × %d.',
     '%d Befunde bei %d × %d (Maus über einer roten Komponente zeigt die Ursache)',
     'Ziehgriff rechts unten ändert die Größe · Esc schließt · die DFM bleibt unverändert',
     'wird %d px groß (Breite oder Höhe ≤ 0)',
     'ragt %d px rechts heraus',
     'ragt %d px unten heraus',
     'ragt %d px links heraus',
     'ragt %d px oben heraus',
     'überlappt %s',
     'zweites alClient im selben Parent wie %s',
     'Anchors auf allen Seiten bei Align',
     'nur %s verankert',
     'Knopf „Größe ausprobieren“ (Probegröße ohne Änderung der DFM)',
     'Schnellwerte der Probegröße (Breite x Höhe, durch Komma getrennt)',
     'Anchors als Nadeln und Align-Bereiche als Flächen zeigen',
     'Kein Formular im Designer.'),
    ('Measure distances: guide lines while dragging, with Alt to the component under the mouse',
     'as above',
     'as below',
     'as on the left',
     'as on the right',
     'width as %s',
     'height as %s',
     'Show distance lines while moving and resizing',
     'Show distances to the component under the mouse while Alt is held',
     'Try size: preview the form at another size, the DFM stays unchanged',
     'Try size – %s',
     'Size:',
     'Minimum',
     'Design',
     'The form has no Constraints.MinWidth/MinHeight.',
     'No findings at %d × %d.',
     '%d findings at %d × %d (hover a red component for the cause)',
     'Drag the grip at the bottom right to resize · Esc closes · the DFM stays unchanged',
     'gets %d px (width or height ≤ 0)',
     'sticks out %d px on the right',
     'sticks out %d px at the bottom',
     'sticks out %d px on the left',
     'sticks out %d px at the top',
     'overlaps %s',
     'second alClient in the same parent as %s',
     'anchors on all sides with Align',
     'only %s anchored',
     '“Try size” button (preview size without changing the DFM)',
     'Quick sizes of the preview (width x height, comma separated)',
     'Show anchors as pins and Align areas as tinted areas',
     'No form in the designer.'));

{ TAtlasDesignerToolStrings }

class function TAtlasDesignerToolStrings.Text(AId: TAtlasDesignerToolTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDesignerToolStrings.TextIn(ALanguage: TAtlasLanguage; AId: TAtlasDesignerToolTextId): string;
begin
  Result := cTexts[ALanguage, AId];
end;

class function TAtlasDesignerToolStrings.Fmt(AId: TAtlasDesignerToolTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
