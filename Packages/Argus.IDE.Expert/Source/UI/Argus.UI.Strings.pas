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
    SettingsResetWidths, FitsType, OtherGroup, CountFits, CompileCancelled, SettingsHangThreshold, SettingsHangHint, HangHint, SettingsHangTest, SettingsReload, ReloadDone, ReloadKeptModified, ReloadDeleted, PaletteLog, PaletteResetHistory, SettingsPairs, SettingsCheckOnSave,
    SettingsCheckDelay, SettingsCheckMax, CheckOnSaveDisabled, PaletteCheckNow,
    HoverInheritance, HoverTargetType, HoverPinned, HoverGoTo, HoverUsages, HoverUsagesCount, HoverCopy, HoverHelp, HoverUsagesOf,
    KindClass, KindClassRef, KindObject, KindRecord, KindInterface, KindHelper, KindEnum, KindType, KindMethod, KindConstructor, KindRoutine, KindProperty, KindField, KindVariable, KindConstant, KindEnumMember, HoverKeyUsages, HoverKeyCopy,
    SettingsPairGuides, PairGuidesIdeOff, PairGuidesIdeOn);

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
     'Eigener Tooltip beim Verweilen über Bezeichnern', 'Verlauf zurücksetzen', 'Breiten zurücksetzen',
     'Passt zu %s', 'Weitere', '%d passend · %d gesamt', 'Argus: Compile abgebrochen – %s', 'Als Hänger melden ab (ms):',
     'Hinweis im Meldungsfenster nach langen Hängern (ab 2 s)', 'Argus: Die IDE hat %d ms nicht reagiert%s', 'Wächter testen (1 s)',
     'Außerhalb geänderte Dateien ohne Rückfrage neu laden (nur ohne ungespeicherte Änderungen)',
     'Argus: %d Dateien neu geladen', 'Argus: %s wurde außerhalb geändert und hat ungespeicherte Änderungen; die IDE fragt nach.',
     'Argus: %s existiert nicht mehr.', 'Protokoll öffnen', 'Verlauf der Vervollständigung zurücksetzen',
     'Klammern und Blockpaare (begin/end …) nach Tiefe färben', 'Compiler prüft nach dem Speichern (Syntaxprüfung)',
     'Wartezeit nach dem Speichern (ms):', 'Höchstdauer der Prüfung (ms):',
     'Argus: Compilerprüfung nach dem Speichern für %s abgeschaltet (%d ms > %d ms); Strg+Alt+F9 prüft von Hand.',
     'Compiler prüfen (Syntaxprüfung)',
     'Vererbung', 'Zieltyp %s', 'angeheftet', 'Gehe zu %s', 'Verwendungen', 'Verwendungen (%d)', 'Deklaration kopieren', 'Hilfe', 'Argus: %d Verwendungen von %s',
     'Klasse', 'Klassenreferenz', 'Objekttyp', 'Record', 'Interface', 'Helfer', 'Aufzählung', 'Typ', 'Methode', 'Konstruktor', 'Routine', 'Property', 'Feld', 'Variable', 'Konstante', 'Aufzählungswert', 'Umschalt+F12', 'Strg+C',
     'Blocklinien in den Paarfarben (schaltet die Strukturhervorhebung der IDE ab)',
     'Argus zeichnet die Blocklinien selbst und hat die Strukturhervorhebung der IDE abgeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Argus hat die Strukturhervorhebung der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.'),
    ('Enter to accept · Esc to close', '%d of %d', 'No matches for “%s”', 'Backspace widens the search',
     'No suggestions here', 'Esc closes', 'No details for this entry', 'Overload', 'Deprecated: %s', 'Deprecated.',
     'Inherited from %s', 'Inherited', 'optional, default %s', 'No overload with %d parameters.', '… %d more',
     'All', 'Methods', 'Properties', 'Events', 'Types', 'Snippets', 'recent', 'frequent',
     'Completion, parameter hint and tooltip by Argus', 'Argus active (off: built-in Code Insight of the IDE)',
     'Visible rows of the list:', 'Detail panel collapsed (Ctrl+Q toggles in the popup)',
     'Add parentheses when accepting methods', 'Filter chips above the list (Alt+1 … Alt+6)',
     'Frequently and recently chosen entries first', 'Inherited members ranked lower and grouped by class',
     'Preview of the selected entry in the editor', 'Own tooltip when hovering identifiers', 'Reset history',
     'Reset widths', 'Matches %s', 'Other', '%d matching · %d total', 'Argus: compile cancelled – %s', 'Report a hang after (ms):',
     'Message after long hangs (2 s and more)', 'Argus: the IDE did not respond for %d ms%s', 'Test watchdog (1 s)',
     'Reload files changed outside the IDE without asking (only without unsaved changes)',
     'Argus: %d files reloaded', 'Argus: %s was changed outside and has unsaved changes; the IDE will ask.',
     'Argus: %s no longer exists.', 'Open log', 'Reset completion history',
     'Colour brackets and block pairs (begin/end …) by depth', 'Compiler checks after saving (syntax check)',
     'Delay after saving (ms):', 'Maximum check duration (ms):',
     'Argus: compiler check after saving switched off for %s (%d ms > %d ms); Ctrl+Alt+F9 checks manually.',
     'Check with compiler (syntax check)',
     'Inheritance', 'Target type %s', 'pinned', 'Go to %s', 'Usages', 'Usages (%d)', 'Copy declaration', 'Help', 'Argus: %d usages of %s',
     'Class', 'Class reference', 'Object type', 'Record', 'Interface', 'Helper', 'Enumeration', 'Type', 'Method', 'Constructor', 'Routine', 'Property', 'Field', 'Variable', 'Constant', 'Enumeration value', 'Shift+F12', 'Ctrl+C',
     'Block lines in the pair colours (switches off the IDE''s structural highlighting)',
     'Argus draws the block lines itself and switched off the IDE''s structural highlighting; takes effect after the next start of Delphi.',
     'Argus switched the IDE''s structural highlighting back on; takes effect after the next start of Delphi.'));

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
