unit Argus.UI.Strings;

// Oberflächentexte von Argus auf Deutsch und Englisch (#446). Die Sprache
// setzt die IDE-Schicht beim Laden nach der Sprache der IDE (Rückfall
// Englisch). Bezeichner, Signaturen und XMLDoc-Inhalte werden nie übersetzt.
// Statt resourcestring eine Tabelle: Die Sprache wechselt ohne Ressourcen-DLL.

interface

{$SCOPEDENUMS ON}

type
  TArgusLanguage = (German, English);

  TArgusTextId = (FooterKeys, CountOf, NoMatchesFor, BackspaceWidens, NoSuggestions, EscCloses, NoDetails,
    Overload, DeprecatedWith, DeprecatedPlain, InheritedFrom, InheritedPlain, OptionalDefault, NoOverloadWith,
    MoreOverloads, ChipAll, ChipMethods, ChipProperties, ChipEvents, ChipTypes, ChipSnippets, TagRecent,
    TagFrequent, SettingsTitle, SettingsEnabled, SettingsRows, SettingsPanelCollapsed, SettingsParentheses,
    SettingsChips, SettingsLearning, SettingsGroupInherited, SettingsPreview, SettingsHover, SettingsResetHistory,
    SettingsResetWidths);

  TArgusStrings = class
  private class var
    FLanguage: TArgusLanguage;
  public
    class function Text(AId: TArgusTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TArgusTextId; const AArgs: array of const): string; static;
    class property Language: TArgusLanguage read FLanguage write FLanguage;
  end;

implementation

uses
  System.SysUtils;

const
  Texts: array[TArgusLanguage, TArgusTextId] of string = (
    ('Enter übernehmen · Esc schließen', '%d von %d', 'Keine Treffer für „%s“', 'Rücktaste erweitert die Suche',
     'Keine Vorschläge an dieser Stelle', 'Esc schließt', 'Keine Details zu diesem Eintrag', 'Überladung',
     'Veraltet: %s', 'Veraltet.', 'Geerbt von %s', 'Geerbt', 'optional, Standard %s',
     'Keine Überladung mit %d Parametern.', '… %d weitere', 'Alle', 'Methoden', 'Eigenschaften', 'Ereignisse',
     'Typen', 'Snippets', 'zuletzt', 'häufig', 'Vervollständigung, Parameter-Hint und Tooltip von Argus',
     'Argus aktiv (aus: eingebaute Code Insight der IDE)', 'Sichtbare Zeilen der Liste:',
     'Detailpanel eingeklappt (Strg+Q schaltet im Popup um)', 'Klammern beim Übernehmen von Methoden ergänzen',
     'Filter-Chips über der Liste (Alt+1 … Alt+6)', 'Häufig und zuletzt gewählte Einträge nach oben',
     'Geerbte Member nachrangig und nach Klasse gruppiert', 'Vorschau des gewählten Eintrags im Editor',
     'Eigener Tooltip beim Verweilen über Bezeichnern', 'Verlauf zurücksetzen', 'Breiten zurücksetzen'),
    ('Enter to accept · Esc to close', '%d of %d', 'No matches for “%s”', 'Backspace widens the search',
     'No suggestions here', 'Esc closes', 'No details for this entry', 'Overload', 'Deprecated: %s', 'Deprecated.',
     'Inherited from %s', 'Inherited', 'optional, default %s', 'No overload with %d parameters.', '… %d more',
     'All', 'Methods', 'Properties', 'Events', 'Types', 'Snippets', 'recent', 'frequent',
     'Completion, parameter hint and tooltip by Argus', 'Argus active (off: built-in Code Insight of the IDE)',
     'Visible rows of the list:', 'Detail panel collapsed (Ctrl+Q toggles in the popup)',
     'Add parentheses when accepting methods', 'Filter chips above the list (Alt+1 … Alt+6)',
     'Frequently and recently chosen entries first', 'Inherited members ranked lower and grouped by class',
     'Preview of the selected entry in the editor', 'Own tooltip when hovering identifiers', 'Reset history',
     'Reset widths'));

{ TArgusStrings }

class function TArgusStrings.Text(AId: TArgusTextId): string;
begin
  Result := Texts[FLanguage, AId];
end;

class function TArgusStrings.Fmt(AId: TArgusTextId; const AArgs: array of const): string;
begin
  Result := Format(Texts[FLanguage, AId], AArgs);
end;

initialization
  TArgusStrings.Language := TArgusLanguage.German;

end.
