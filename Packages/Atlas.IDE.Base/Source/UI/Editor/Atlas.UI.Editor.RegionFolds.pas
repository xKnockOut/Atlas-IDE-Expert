unit Atlas.UI.Editor.RegionFolds;

// Texte zu „Regionen beim Öffnen“ (#1814, editor.regionFolds): Befehle zum Zu- und Aufklappen aller Regionen und
// die Auswahl auf der Optionsseite, deutsch und englisch. Dazu „Große Blöcke einklappen“ (#2795, editor.blockFolds):
// Befehle, Einstellungen und Meldungen. Eigene Tabelle, weil Atlas.Plugin.Localization.Strings über der Grenze
// der Unitlänge liegt.

interface

uses
  Atlas.Plugin.Localization.Language;

type
{$SCOPEDENUMS ON}
  TAtlasRegionFoldsText = (CollapseCommand, ExpandCommand, Setting, ChoiceKeep, ChoiceCollapse, ChoiceExpand,
    ChoiceOff, FoldBlockCommand, FoldLargeBlocksCommand, UnfoldBlocksCommand, BlockSetting, BlockMinLines,
    NoBlockAtCursor, NoLargeBlocks, NoFoldedBlocks);
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
      'alle zuklappen', 'alle aufklappen', 'aus (auch keine Befehle)', 'Block einklappen',
      'Große Blöcke einklappen', 'Blöcke aufklappen', 'Große Blöcke einklappbar', 'Ab Zeilen:',
      'Kein Block ab %d Zeilen an der Schreibmarke.', 'Keine Blöcke ab %d Zeilen in dieser Datei.',
      'Keine eingeklappten Blöcke in dieser Datei.'),
    ('Collapse all regions', 'Expand all regions', 'Regions when a file opens:', 'leave unchanged',
      'collapse all', 'expand all', 'off (no commands either)', 'Collapse block', 'Collapse large blocks',
      'Expand blocks', 'Large blocks can be collapsed', 'From lines:', 'No block of %d lines or more at the cursor.',
      'No blocks of %d lines or more in this file.', 'No collapsed blocks in this file.'));

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
