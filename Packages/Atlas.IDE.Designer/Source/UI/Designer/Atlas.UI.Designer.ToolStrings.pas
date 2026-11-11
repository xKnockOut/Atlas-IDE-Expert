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
    SettingsMeasureDistances, SettingsMeasureAltKey);

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
     'Maße mit gedrückter Alt-Taste zur Komponente unter der Maus zeigen'),
    ('Measure distances: guide lines while dragging, with Alt to the component under the mouse',
     'as above',
     'as below',
     'as on the left',
     'as on the right',
     'width as %s',
     'height as %s',
     'Show distance lines while moving and resizing',
     'Show distances to the component under the mouse while Alt is held'));

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
