unit Atlas.UI.Editor.RegionFolds;

// Texte zu „Regionen beim Öffnen“ (#1814, editor.regionFolds): Befehle zum Zu- und Aufklappen aller Regionen und
// die Auswahl auf der Optionsseite, deutsch und englisch. Eigene Tabelle, weil Atlas.UI.Strings über der Grenze
// der Unitlänge liegt.

interface

uses
  Atlas.Core.Localization.Language;

type
{$SCOPEDENUMS ON}
  TAtlasRegionFoldsText = (CollapseCommand, ExpandCommand, Setting, ChoiceKeep, ChoiceCollapse, ChoiceExpand,
    ChoiceOff);
{$SCOPEDENUMS OFF}

  TAtlasRegionFoldsTexts = class
  public
    /// <summary>Text AId in der Sprache der Oberfläche.</summary>
    class function Text(AId: TAtlasRegionFoldsText): string; static;
    /// <summary>Einträge der Auswahl in der Reihenfolge von AtlasRegionFoldModes.</summary>
    class function Choices: TArray<string>; static;
  end;

implementation

const
  cTexts: array[TAtlasLanguage, TAtlasRegionFoldsText] of string = (
    ('Alle Regionen zuklappen', 'Alle Regionen aufklappen', 'Regionen beim Öffnen:', 'unverändert lassen',
      'alle zuklappen', 'alle aufklappen', 'aus (auch keine Befehle)'),
    ('Collapse all regions', 'Expand all regions', 'Regions when a file opens:', 'leave unchanged',
      'collapse all', 'expand all', 'off (no commands either)'));

{ TAtlasRegionFoldsTexts }

class function TAtlasRegionFoldsTexts.Text(AId: TAtlasRegionFoldsText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

class function TAtlasRegionFoldsTexts.Choices: TArray<string>;
begin
  Result := TArray<string>.Create(Text(TAtlasRegionFoldsText.ChoiceKeep), Text(TAtlasRegionFoldsText.ChoiceCollapse),
    Text(TAtlasRegionFoldsText.ChoiceExpand), Text(TAtlasRegionFoldsText.ChoiceOff));
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.UI.Editor.RegionFolds', cTexts[TAtlasLanguage.German],
    cTexts[TAtlasLanguage.English]);

end.
