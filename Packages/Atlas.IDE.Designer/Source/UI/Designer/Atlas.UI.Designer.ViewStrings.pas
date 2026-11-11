unit Atlas.UI.Designer.ViewStrings;

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
  TAtlasDesignerViewTextId = (
    MeasureHint, MeasureAbove, MeasureBelow, MeasureLeftOf, MeasureRightOf, MeasureSameWidth, MeasureSameHeight,
    SettingsMeasureDistances, SettingsMeasureAltKey, ResizeHint, ResizeTitle, ResizeSize, ResizeMinimum, ResizeDesign,
    ResizeNoMinimum, ResizeNone, ResizeCount, ResizeKeys, LayoutTooSmall, LayoutOutRight, LayoutOutBottom,
    LayoutOutLeft, LayoutOutTop, LayoutOverlap, LayoutTwoClient, LayoutAnchorsAlign, LayoutAnchored,
    SettingsResizePreview, SettingsResizeSizes, SettingsResizeAnchors, ToolNoForm, ScaleHint, ScaleTitle, ScaleLevel,
    ScaleScreen, ScaleNoLimit, ScaleTexts, ScaleOriginal, ScaleLong, ScaleNone, ScaleCount, ScaleKeys, ScaleNotScaled,
    ScaleUsable, ScaleClipped, ScaleScreenWidth, ScaleScreenHeight, SettingsScalePreview, SettingsScaleLevels,
    SettingsScaleScreens, SettingsLongTextFactor, NameHint, NameTitle, NameColComponent, NameColClass, NameColSource,
    NameColProposal, NameColNote, NameEdit, NameApply, NameCancel, NameUndo, NameSourceCaption, NameSourceLabel,
    NameSourceHandler, NameSourceDataField, NameNoSource, NameCollision, NameInvalid, NameNone, NameDone, NameUndone,
    NameFailed, NameCodeFailed, NameAction, SettingsNameSuggest, SettingsNameSources, SettingsNameUmlauts,
    SettingsNameReplace, SettingsNameRemove, SettingsNameHandlers, SettingsNamePrefixes);

{$SCOPEDENUMS OFF}

  TAtlasDesignerViewStrings = class
  public
    /// <summary>Text in der Sprache der Oberfläche.</summary>
    class function Text(AId: TAtlasDesignerViewTextId): string; static;
    /// <summary>Text in ALanguage, unabhängig von der Sprache der Oberfläche.</summary>
    class function TextIn(ALanguage: TAtlasLanguage; AId: TAtlasDesignerViewTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasDesignerViewTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasDesignerViewTextId] of string = (
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
     'Kein Formular im Designer.',
     'Skalierung und Texte: Vorschau des Formulars bei 125 bis 200 %, auf kleineren Bildschirmen und mit langen Texten, die DFM bleibt unverändert',
     'Skalierung und Texte – %s',
     'Skalierung:',
     'Bildschirm:',
     'Kein Limit',
     'Texte:',
     'Original',
     'Lange Texte (+%d %%)',
     'Keine Befunde bei %d %%.',
     '%d Befunde bei %d %% (Klick in der Liste wählt die Komponente im Designer)',
     'Esc schließt · die DFM bleibt unverändert',
     'Scaled = False: die VCL skaliert das Formular nicht',
     'nutzbare Fläche des Bildschirms',
     'Text %d px breiter als die Komponente (abgeschnitten)',
     'Formular samt Rahmen %d px breiter als der Bildschirm',
     'Formular samt Rahmen und Taskleiste %d px höher als der Bildschirm',
     'Knopf „Skalierung und Texte“ (Vorschau ohne Änderung der DFM)',
     'Angebotene Skalierungen in Prozent (durch Komma getrennt)',
     'Angebotene Bildschirmgrößen (Breite x Höhe, durch Komma getrennt)',
     'Verlängerung der Texte bei „Lange Texte“ in Prozent',
     'Sprechende Namen: Vorschläge für Button1, Edit3 … aus Beschriftung, Label, Handler oder DataField',
     'Sprechende Namen – %s',
     'Komponente',
     'Klasse',
     'Quelle',
     'Vorschlag',
     'Hinweis',
     'Vorschlag:',
     'Übernehmen',
     'Abbrechen',
     'Letzte Umbenennung rückgängig',
     'Beschriftung',
     'Label',
     'Handler',
     'DataField',
     'kein Vorschlag (keine passende Quelle)',
     'Name vergeben, Nummer angehängt',
     'kein gültiger Bezeichner',
     'Keine Komponente mit Standardnamen im Formular %s.',
     '%d Komponenten umbenannt, %d Handler, %d Stellen im Code.',
     'Umbenennung zurückgenommen: %d Komponenten.',
     '%s konnte nicht umbenannt werden: %s',
     'Verwendungen im Code nicht geändert: %s',
     'Sprechende Namen',
     'Knopf „Sprechende Namen“ (Komponenten mit Standardnamen umbenennen)',
     'Quellen der Vorschläge in ihrer Reihenfolge (caption, label, handler, dataField)',
     'Umlaute im Vorschlag',
     'ersetzen (ä → ae)',
     'entfernen',
     'Handler mit Standardnamen mit umbenennen',
     'Eigene Präfixe (TKlasse=präfix, durch Komma getrennt)'),
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
     'No form in the designer.',
     'Scaling and texts: preview the form at 125 to 200 %, on smaller screens and with long texts, the DFM stays unchanged',
     'Scaling and texts – %s',
     'Scaling:',
     'Screen:',
     'No limit',
     'Texts:',
     'Original',
     'Long texts (+%d %%)',
     'No findings at %d %%.',
     '%d findings at %d %% (click in the list selects the component in the designer)',
     'Esc closes · the DFM stays unchanged',
     'Scaled = False: the VCL does not scale the form',
     'usable area of the screen',
     'text %d px wider than the component (clipped)',
     'form including frame %d px wider than the screen',
     'form including frame and taskbar %d px taller than the screen',
     '“Scaling and texts” button (preview without changing the DFM)',
     'Offered scalings in percent (comma separated)',
     'Offered screen sizes (width x height, comma separated)',
     'Lengthening of texts with “Long texts” in percent',
     'Meaningful names: suggestions for Button1, Edit3 … from caption, label, handler or DataField',
     'Meaningful names – %s',
     'Component',
     'Class',
     'Source',
     'Proposal',
     'Note',
     'Proposal:',
     'Apply',
     'Cancel',
     'Undo last renaming',
     'Caption',
     'Label',
     'Handler',
     'DataField',
     'no proposal (no matching source)',
     'name taken, number appended',
     'not a valid identifier',
     'No component with a default name in form %s.',
     '%d components renamed, %d handlers, %d places in code.',
     'Renaming undone: %d components.',
     '%s could not be renamed: %s',
     'Usages in code not changed: %s',
     'Meaningful names',
     '“Meaningful names” button (rename components with default names)',
     'Sources of proposals in order (caption, label, handler, dataField)',
     'Umlauts in proposals',
     'replace with ae, oe, ue, ss',
     'remove',
     'Rename handlers with default names too',
     'Own prefixes (TClass=prefix, comma separated)'));

{ TAtlasDesignerViewStrings }

class function TAtlasDesignerViewStrings.Text(AId: TAtlasDesignerViewTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasDesignerViewStrings.TextIn(ALanguage: TAtlasLanguage; AId: TAtlasDesignerViewTextId): string;
begin
  Result := cTexts[ALanguage, AId];
end;

class function TAtlasDesignerViewStrings.Fmt(AId: TAtlasDesignerViewTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasStrings.Language, AId], AArgs);
end;

end.
