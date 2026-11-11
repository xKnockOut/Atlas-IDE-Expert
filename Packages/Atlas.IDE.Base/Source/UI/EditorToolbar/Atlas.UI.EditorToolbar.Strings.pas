unit Atlas.UI.EditorToolbar.Strings;

// Oberflächentexte des Features Editorleiste auf Deutsch und Englisch. Die Sprache bestimmt
// `TAtlasStrings.Language`; jeder Aufruf liest sie neu. Eigene Unit, damit ein neuer Text des Features nicht
// `Atlas.UI.Strings` ändert, die fast der ganze Kern verwendet; dort bleiben gemeinsame Texte.

interface

{$SCOPEDENUMS ON}

type
  TAtlasEditorToolbarTextId = (
    FindMethodPrompt, FindMethodNoOutline, EditorToolbarCustomizeTitle, EditorToolbarAvailable,
    EditorToolbarCurrent, EditorToolbarSeparator, EditorToolbarAddHint, EditorToolbarRemoveHint,
    EditorToolbarUpHint, EditorToolbarDownHint, EditorToolbarRestoreDefault, EditorToolbarOk, EditorToolbarCancel);

  TAtlasEditorToolbarStrings = class
  public
    class function Text(AId: TAtlasEditorToolbarTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasEditorToolbarTextId; const AArgs: array of const): string; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings;

const
  cTexts: array[TAtlasLanguage, TAtlasEditorToolbarTextId] of string = (
    (
     'Methode in %s',
     'Atlas: Die Gliederung dieser Datei ist noch nicht da; gleich noch einmal versuchen.',
     'Atlas-Editorleiste anpassen',
     'Verfügbare Befehle (Befehlspalette)',
     'In der Leiste',
     '— Trennstrich —',
     'Hinzufügen',
     'Entfernen',
     'Nach oben',
     'Nach unten',
     'Standard wiederherstellen',
     'OK',
     'Abbrechen'),
    (
     'Method in %s',
     'Atlas: The outline of this file is not ready yet; try again in a moment.',
     'Customize Atlas editor toolbar',
     'Available commands (command palette)',
     'In the toolbar',
     '— Separator —',
     'Add',
     'Remove',
     'Move up',
     'Move down',
     'Restore default',
     'OK',
     'Cancel'));

{ TAtlasEditorToolbarStrings }

class function TAtlasEditorToolbarStrings.Text(AId: TAtlasEditorToolbarTextId): string;
begin
  Result := cTexts[TAtlasStrings.Language, AId];
end;

class function TAtlasEditorToolbarStrings.Fmt(AId: TAtlasEditorToolbarTextId; const AArgs: array of const): string;
begin
  Result := Format(Text(AId), AArgs);
end;

end.
