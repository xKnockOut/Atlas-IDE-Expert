unit Atlas.UI.Strings;

// Oberflächentexte von Atlas auf Deutsch und Englisch (#446). Die Sprache
// setzt die IDE-Schicht beim Laden nach der Sprache der IDE (Rückfall
// Englisch). Bezeichner, Signaturen und XMLDoc-Inhalte werden nie übersetzt.
// Statt resourcestring eine Tabelle: Die Sprache wechselt ohne Ressourcen-DLL.

interface

{$SCOPEDENUMS ON}

type
  TAtlasLanguage = (German, English);

  TAtlasTextId = (FooterKeys, CountOf, NoMatchesFor, BackspaceWidens, NoSuggestions, EscCloses, NoDetails,
    Overload, DeprecatedWith, DeprecatedPlain, InheritedFrom, InheritedPlain, OptionalDefault, NoOverloadWith,
    MoreOverloads, ChipAll, ChipMethods, ChipProperties, ChipEvents, ChipTypes, ChipSnippets, TagRecent,
    TagFrequent, SettingsTitle, SettingsEnabled, SettingsRows, SettingsPanelCollapsed, SettingsParentheses, SettingsFixCase,
    SettingsChips, SettingsLearning, SettingsGroupInherited, SettingsPreview, SettingsHover, SettingsResetHistory,
    SettingsResetWidths, FitsType, OtherGroup, CountFits, CompileCancelled, SettingsHangThreshold, SettingsHangHint, HangHint, SettingsHangTest, SettingsReload, ReloadDone, ReloadKeptModified, ReloadDeleted, PaletteLog, PaletteResetHistory, SettingsPairs, SettingsCheckOnSave,
    SettingsCheckDelay, SettingsCheckMax, CheckOnSaveDisabled, PaletteCheckNow,
    HoverInheritance, HoverTargetType, HoverPinned, HoverGoTo, HoverUsages, HoverUsagesCount, HoverCopy, HoverHelp, HoverUsagesOf,
    KindClass, KindClassRef, KindObject, KindRecord, KindInterface, KindHelper, KindEnum, KindType, KindMethod, KindConstructor, KindRoutine, KindProperty, KindField, KindVariable, KindConstant, KindEnumMember, HoverKeyUsages, HoverKeyCopy,
    SettingsPairGuides, PairGuidesIdeOff, PairGuidesIdeOn,
    SettingsProblems, ProblemsGroup, ProblemsSourceAtlas, ProblemsSourceCompiler, ProblemsStale, ProblemsMore,
    ProblemsConfidence, ConfidenceHigh, ConfidenceMedium, ConfidenceLow,
    SeverityError, SeverityWarning, SeverityInformation, SeverityHint,
    SettingsServerPath, SettingsServerFound, SettingsServerMissing, SettingsServerFilter,
    HelpInsightIdeOff, HelpInsightIdeOn,
    ReloadDiffTitle,
    AccessCompletion, AccessSignature, AccessHover, AccessPosition, AccessParameter,
    ProjectSettingsMenu, ProjectSettingsTitle, ProjectSettingsFromProject, ProjectSettingsDefault,
    ProjectSettingsDefaultNone, ProjectSettingsReset, ProjectSettingsComplex, ProjectSettingsOpenFile,
    ProjectSettingsNoProject, ProjectSettingsInvalid, ProjectSettingsOk, ProjectSettingsCancel,
    ProjectSettingsBadNumber, ProjectSettingsFile,
    MenuAtlas, MenuToggleEnabled, MenuToggleHover, MenuTogglePairs, MenuToggleGuides, MenuToggleProblems, MenuOptions, MenuEnableAll,
    MenuIndexStatus, MenuIndexRebuild, MenuIndexRebuilding, MenuIndexNoServer,
    SettingsPaletteKey, SettingsCheckKey, SettingsKeyPriority, KeyConflict, ForeignCompletion,
    SettingsInactiveDim, MenuToggleInactive, DidYouMean,
    DiagExportMenu, DiagExportTitle, DiagExportHint, DiagExportSave, DiagExportFilter, DiagExportEmpty, DiagExportDone,
    SettingsIndexGroup, SettingsIndexSearch, SettingsIndexLibrary,
    SettingsXmlDocFull, SettingsXmlDocMaxLines, DocTypeParams, DocValue, DocExample, DocSeeAlso, HoverCopySelection,
    InactiveCondition, InactiveTarget, InactiveRegion, ProblemsSourceInactive,
    SettingsCompletionKey, SettingsSignatureKey, KeysTitle, KeysIntro, KeysHeaderFunction, KeysHeaderKey,
    KeysHeaderOwner, KeysHeaderChoice, KeysChoiceAtlas, KeysChoiceOther, KeysChoiceNewKey, KeysStatusFree,
    KeysStatusIdeKey, KeysStatusNone, KeysStatusAtlasWins, KeysStatusLeft, KeysForeign, KeysForeignNone, KeysInvalid,
    SettingsProviderTimeLimit, SettingsFuseTitle, SettingsFuseNone, SettingsFuseEnableSelected, SettingsFuseEnableAll,
    CompletionLimited, SettingsIndexUsages, SettingsMemoryBudget, SettingsIndexTitle, SettingsIndexRefresh, SettingsIndexRebuild, SettingsIndexClear, SettingsIndexClearConfirm,
    HidesDeclaration,
    StatusOpenLog, StatusRestartServer, SettingsStatusField, SettingsStatusSummary, SettingsStatusHidden);

  TAtlasStrings = class
  private class var
    FLanguage: TAtlasLanguage;
  public
    class function Text(AId: TAtlasTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasTextId; const AArgs: array of const): string; static;
    /// <summary>"Konfidenz: mittel" zu "high", "medium", "low" (#144); '' bei anderem Wert.</summary>
    class function Confidence(const AName: string): string; static;
    class property Language: TAtlasLanguage read FLanguage write FLanguage;
  end;

implementation

uses
  System.SysUtils;

const
  Texts: array[TAtlasLanguage, TAtlasTextId] of string = (
    ('Enter übernehmen · Esc schließen', '%d von %d', 'Keine Treffer für „%s“', 'Rücktaste erweitert die Suche',
     'Keine Vorschläge an dieser Stelle', 'Esc schließt', 'Keine Details zu diesem Eintrag', 'Überladung',
     'Veraltet: %s', 'Veraltet.', 'Geerbt von %s', 'Geerbt', 'optional, Standard %s',
     'Keine Überladung mit %d Parametern.', '… %d weitere', 'Alle', 'Methoden', 'Eigenschaften', 'Ereignisse',
     'Typen', 'Snippets', 'zuletzt', 'häufig', 'Vervollständigung, Parameter-Hint und Tooltip von Atlas',
     'Atlas aktiv (aus: eingebaute Code Insight der IDE)', 'Sichtbare Zeilen der Liste:',
     'Detailpanel eingeklappt (Strg+Q schaltet im Popup um)', 'Klammern beim Übernehmen von Methoden ergänzen',
     'Schreibweise beim Übernehmen korrigieren (showmessage → ShowMessage)',
     'Filter-Chips über der Liste (Alt+1 … Alt+6)', 'Häufig und zuletzt gewählte Einträge nach oben',
     'Geerbte Member nachrangig und nach Klasse gruppiert', 'Vorschau des gewählten Eintrags im Editor',
     'Eigener Tooltip beim Verweilen über Bezeichnern', 'Verlauf zurücksetzen', 'Breiten zurücksetzen',
     'Passt zu %s', 'Weitere', '%d passend · %d gesamt', 'Atlas: Compile abgebrochen – %s', 'Als Hänger melden ab (ms):',
     'Hinweis im Meldungsfenster nach langen Hängern (ab 2 s)', 'Atlas: Die IDE hat %d ms nicht reagiert%s', 'Wächter testen (1 s)',
     'Außerhalb geänderte Dateien ohne Rückfrage neu laden (nur ohne ungespeicherte Änderungen)',
     'Atlas: %d Dateien neu geladen', 'Atlas: %s wurde außerhalb geändert und hat ungespeicherte Änderungen; die IDE fragt nach.',
     'Atlas: %s existiert nicht mehr.', 'Protokoll öffnen', 'Verlauf der Vervollständigung zurücksetzen',
     'Klammern und Blockpaare (begin/end …) nach Tiefe färben', 'Compiler prüft nach dem Speichern (Syntaxprüfung)',
     'Wartezeit nach dem Speichern (ms):', 'Höchstdauer der Prüfung (ms):',
     'Atlas: Compilerprüfung nach dem Speichern für %s abgeschaltet (%d ms > %d ms); Strg+Alt+F9 prüft von Hand.',
     'Compiler prüfen (Syntaxprüfung)',
     'Vererbung', 'Zieltyp %s', 'angeheftet', 'Gehe zu %s', 'Verwendungen', 'Verwendungen (%d)', 'Deklaration kopieren', 'Hilfe', 'Atlas: %d Verwendungen von %s',
     'Klasse', 'Klassenreferenz', 'Objekttyp', 'Record', 'Interface', 'Helfer', 'Aufzählung', 'Typ', 'Methode', 'Konstruktor', 'Routine', 'Property', 'Feld', 'Variable', 'Konstante', 'Aufzählungswert', 'Umschalt+F12', 'Strg+C',
     'Blocklinien in den Paarfarben (schaltet die Strukturhervorhebung der IDE ab)',
     'Atlas zeichnet die Blocklinien selbst und hat die Strukturhervorhebung der IDE abgeschaltet; ' +
       'wirkt nach dem nächsten Start von Delphi.',
     'Atlas hat die Strukturhervorhebung der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Probleme im Editor unterstreichen und im Meldungsfenster auflisten (Syntax, Regeln, Compiler)',
     'Atlas-Probleme', 'Atlas', 'Compiler', 'seit dem letzten Prüfen geändert', '… %d weitere Probleme',
     'Konfidenz: %s', 'hoch', 'mittel', 'niedrig',
     'Fehler', 'Warnung', 'Info', 'Hinweis',
     'Atlas-Server (AtlasServer.exe), leer = Standard:', 'Verwendet: %s (gefunden)',
     'Verwendet: %s (nicht gefunden; ohne Server bleibt die Code Insight der IDE aktiv)',
     'Atlas-Server|AtlasServer.exe|Programme (*.exe)|*.exe',
     'Atlas zeigt den Tooltip selbst und hat Help Insight der IDE abgeschaltet; wirkt nach dem ' +
       'nächsten Start von Delphi.',
     'Atlas hat Help Insight der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Atlas: Unterschied in %s (- Editor, + Platte):',
     'Atlas Vervollständigung', 'Atlas Parameterhilfe', 'Atlas Tooltip', '%d von %d', 'Parameter %d: %s',
     'Projekt-Einstellungen (atlas.json)…', 'Atlas-Einstellungen des Projekts', 'aus dem Projekt', 'Standard: %s',
     'Standard', 'Zurücksetzen', 'Nur direkt in atlas.json bearbeitbar', 'atlas.json öffnen',
     'Kein Projekt geöffnet.', 'atlas.json ist kein gültiges JSON; bitte zuerst dort korrigieren.', 'OK', 'Abbrechen',
     '%s: "%s" ist keine ganze Zahl.', 'Datei: %s',
     'Atlas', 'Code Insight von Atlas', 'Eigener Tooltip', 'Klammerpaare färben', 'Blocklinien',
     'Probleme anzeigen', 'Optionen…', 'Abgeschaltete Funktionen einschalten (%s)',
     'Index-Status', 'Index neu aufbauen', 'Atlas: Index wird ohne Cache neu aufgebaut; der Fortschritt steht im Menütitel.',
     'Atlas: Server nicht erreichbar.',
     'Befehlspalette:', 'Syntaxprüfung jetzt:', 'Vorrang vor anderer Belegung',
     'Atlas: %0:s ist schon belegt (%1:s); Atlas überlässt die Taste und belegt sie nicht für %2:s. ' +
       'Entscheidung unter Tools > Optionen > Drittanbieter > Atlas > Tastenkonflikte.',
     'Atlas: %s bringt eine eigene Vervollständigung mit. Laufen beide, stören sie sich; ' +
       'eine davon abschalten (Atlas: Menü Atlas > Code Insight von Atlas). Atlas ändert fremde Erweiterungen nicht.',
     'Inaktive {$IFDEF}-Zweige ausgrauen', 'Inaktive {$IFDEF}-Zweige ausgrauen', 'Meintest du',
     'Diagnoselog exportieren…', 'Diagnoselog exportieren – Vorschau',
     'Genau diese Zeilen kommen in die ZIP-Datei (Logs der letzten %d Tage). Pfade, Projekt- und Bezeichnernamen ' +
       'sind durch Kurz-IDs ersetzt; die Zuordnung ID → Name wird nie mitgegeben.',
     'Speichern…', 'ZIP-Dateien (*.zip)|*.zip', 'Atlas: Keine Diagnoselogs der letzten %d Tage gefunden.',
     'Atlas: Diagnoselog gespeichert: %s',
     'Index: alle Projekte der Projektgruppe', 'Index: alle Units der Projekt-Suchpfade',
     'Index: alle Units der Delphi-Bibliothek (RTL, VCL, FMX, Komponenten)',
     'XMLDoc im Tooltip vollständig zeigen (aus: Kurzform)',
     'XMLDoc: höchstens Zeilen ohne Scrollen (0 = Bildschirm)',
     'Typparameter',
     'Wert',
     'Beispiel',
     'Siehe auch:',
     'Markierung kopieren',
     'Inaktiv: Bedingung %s nicht erfüllt',
     ' (Zielplattform %s · %s)',
     'Inaktiver Bereich (bedingte Kompilierung)',
     'Bedingte Kompilierung',
     'Vervollständigung:',
     'Parameter-Hint:',
     'Tastenkonflikte',
     'Ist eine Taste schon belegt (IDE oder andere Erweiterung), belegt Atlas sie erst nach deiner ' +
       'Entscheidung; bis dahin bleibt die andere Belegung aktiv. Taste als Text wie im Menü ' +
       '(Strg+Umschalt+P), leer = keine bzw. bei Vervollständigung und Parameter-Hint die Taste der ' +
       'IDE.',
     'Funktion',
     'Taste',
     'Belegt von',
     'Entscheidung',
     'Atlas verwenden',
     'Anderer Belegung überlassen',
     'Andere Taste für Atlas',
     'frei',
     'Taste der IDE (%s) über Code Insight',
     'keine Taste',
     '%s; Atlas hat Vorrang',
     '%s; bleibt aktiv',
     'Erweiterungen mit eigener Vervollständigung: %s. Laufen beide, stören sie sich; eine davon ' +
       'abschalten (Atlas: Menü Atlas > Code Insight von Atlas). Atlas ändert fremde Erweiterungen ' +
       'nicht.',
     'Keine Erweiterung mit eigener Vervollständigung erkannt.',
     'Unbekannte Taste: %s',
     'Zeitlimit für Datenquellen (ms):',
     'Nach wiederholten Fehlern abgeschaltet:',
     'Keine Funktion abgeschaltet.',
     'Ausgewählte einschalten',
     'Alle einschalten',
     'eingeschränkt (Index wird aufgebaut)',
     'Verwendungen der Bezeichner mit indizieren',
     'Speichergrenze des Index (MB, 0 = keine)',
     'Symbolindex',
     'Kennzahlen aktualisieren',
     'Index neu aufbauen',
     'Index löschen',
     'Alle Index-Caches auf der Platte löschen? Der Index wird danach neu aufgebaut.',
     'Verdeckt: %s',
     'Protokoll öffnen',
     'Server neu starten',
     'Atlas-Feld in der Statusleiste des Editors',
     'Kurztext neben „Atlas“ zeigen',
     'Ausgeblendete Zeilen (Kennungen):'),
    ('Enter to accept · Esc to close', '%d of %d', 'No matches for “%s”', 'Backspace widens the search',
     'No suggestions here', 'Esc closes', 'No details for this entry', 'Overload', 'Deprecated: %s', 'Deprecated.',
     'Inherited from %s', 'Inherited', 'optional, default %s', 'No overload with %d parameters.', '… %d more',
     'All', 'Methods', 'Properties', 'Events', 'Types', 'Snippets', 'recent', 'frequent',
     'Completion, parameter hint and tooltip by Atlas', 'Atlas active (off: built-in Code Insight of the IDE)',
     'Visible rows of the list:', 'Detail panel collapsed (Ctrl+Q toggles in the popup)',
     'Add parentheses when accepting methods',
     'Fix the case when accepting (showmessage → ShowMessage)', 'Filter chips above the list (Alt+1 … Alt+6)',
     'Frequently and recently chosen entries first', 'Inherited members ranked lower and grouped by class',
     'Preview of the selected entry in the editor', 'Own tooltip when hovering identifiers', 'Reset history',
     'Reset widths', 'Matches %s', 'Other', '%d matching · %d total', 'Atlas: compile cancelled – %s', 'Report a hang after (ms):',
     'Message after long hangs (2 s and more)', 'Atlas: the IDE did not respond for %d ms%s', 'Test watchdog (1 s)',
     'Reload files changed outside the IDE without asking (only without unsaved changes)',
     'Atlas: %d files reloaded', 'Atlas: %s was changed outside and has unsaved changes; the IDE will ask.',
     'Atlas: %s no longer exists.', 'Open log', 'Reset completion history',
     'Colour brackets and block pairs (begin/end …) by depth', 'Compiler checks after saving (syntax check)',
     'Delay after saving (ms):', 'Maximum check duration (ms):',
     'Atlas: compiler check after saving switched off for %s (%d ms > %d ms); Ctrl+Alt+F9 checks manually.',
     'Check with compiler (syntax check)',
     'Inheritance', 'Target type %s', 'pinned', 'Go to %s', 'Usages', 'Usages (%d)', 'Copy declaration', 'Help', 'Atlas: %d usages of %s',
     'Class', 'Class reference', 'Object type', 'Record', 'Interface', 'Helper', 'Enumeration', 'Type', 'Method', 'Constructor', 'Routine', 'Property', 'Field', 'Variable', 'Constant', 'Enumeration value', 'Shift+F12', 'Ctrl+C',
     'Block lines in the pair colours (switches off the IDE''s structural highlighting)',
     'Atlas draws the block lines itself and switched off the IDE''s structural highlighting; takes ' +
       'effect after the next start of Delphi.',
     'Atlas switched the IDE''s structural highlighting back on; takes effect after the next start of Delphi.',
     'Underline problems in the editor and list them in the message view (syntax, rules, compiler)',
     'Atlas problems', 'Atlas', 'Compiler', 'changed since the last check', '… %d more problems',
     'Confidence: %s', 'high', 'medium', 'low',
     'Error', 'Warning', 'Info', 'Hint',
     'Atlas server (AtlasServer.exe), empty = default:', 'In use: %s (found)',
     'In use: %s (not found; without a server the IDE''s Code Insight stays active)',
     'Atlas server|AtlasServer.exe|Programs (*.exe)|*.exe',
     'Atlas shows the tooltip itself and switched off the IDE''s Help Insight; takes effect after ' +
       'the next start of Delphi.',
     'Atlas switched the IDE''s Help Insight back on; takes effect after the next start of Delphi.',
     'Atlas: difference in %s (- editor, + disk):',
     'Atlas completion', 'Atlas parameter info', 'Atlas tooltip', '%d of %d', 'Parameter %d: %s',
     'Project settings (atlas.json)…', 'Atlas project settings', 'from the project', 'Default: %s',
     'Default', 'Reset', 'Edit directly in atlas.json only', 'Open atlas.json',
     'No project open.', 'atlas.json is not valid JSON; please fix it there first.', 'OK', 'Cancel',
     '%s: "%s" is not a whole number.', 'File: %s',
     'Atlas', 'Atlas Code Insight', 'Own tooltip', 'Colour bracket pairs', 'Block guides',
     'Show problems', 'Options…', 'Re-enable switched-off features (%s)',
     'Index status', 'Rebuild index', 'Atlas: rebuilding the index without cache; progress shows in the menu title.',
     'Atlas: server not reachable.',
     'Command palette:', 'Syntax check now:', 'Take precedence over other assignment',
     'Atlas: %0:s is already assigned (%1:s); Atlas leaves the key and does not use it for %2:s. ' +
       'Decide under Tools > Options > Third Party > Atlas > Key conflicts.',
     'Atlas: %s brings its own code completion. Running both interferes; ' +
       'switch one off (Atlas: menu Atlas > Atlas Code Insight). Atlas does not change other extensions.',
     'Grey out inactive {$IFDEF} branches', 'Grey out inactive {$IFDEF} branches', 'Did you mean',
     'Export diagnostic log…', 'Export diagnostic log – preview',
     'Exactly these lines go into the ZIP file (logs of the last %d days). Paths, project and identifier names ' +
       'are replaced by short IDs; the mapping ID → name is never included.',
     'Save…', 'ZIP files (*.zip)|*.zip', 'Atlas: no diagnostic logs found for the last %d days.',
     'Atlas: diagnostic log saved: %s',
     'Index: all projects of the project group', 'Index: all units of the project search paths',
     'Index: all units of the Delphi library (RTL, VCL, FMX, components)',
     'Show full XMLDoc in tooltips (off: short form)',
     'XMLDoc: max. lines before scrolling (0 = screen)',
     'Type parameters',
     'Value',
     'Example',
     'See also:',
     'Copy selection',
     'Inactive: condition %s not met',
     ' (target platform %s · %s)',
     'Inactive region (conditional compilation)',
     'Conditional compilation',
     'Code completion:',
     'Parameter hint:',
     'Key conflicts',
     'If a key is already assigned (IDE or another extension), Atlas uses it only after you decide; ' +
       'until then the other assignment stays active. Key as text like in menus (Ctrl+Shift+P); empty ' +
       '= none, or for completion and parameter hint the IDE key.',
     'Function',
     'Key',
     'Assigned to',
     'Decision',
     'Use Atlas',
     'Leave to other assignment',
     'Other key for Atlas',
     'free',
     'IDE key (%s) via Code Insight',
     'no key',
     '%s; Atlas takes precedence',
     '%s; stays active',
     'Extensions with their own code completion: %s. Running both interferes; switch one off (Atlas: ' +
       'menu Atlas > Atlas Code Insight). Atlas does not change other extensions.',
     'No extension with its own code completion detected.',
     'Unknown key: %s',
     'Time limit for data sources (ms):',
     'Turned off after repeated errors:',
     'No feature turned off.',
     'Turn selected on',
     'Turn all on',
     'limited (index is being built)',
     'Index identifier usages',
     'Index memory limit (MB, 0 = none)',
     'Symbol index',
     'Refresh figures',
     'Rebuild index',
     'Delete index',
     'Delete all index caches on disk? The index is rebuilt afterwards.',
     'Hides: %s',
     'Open log',
     'Restart server',
     'Atlas field in the editor status bar',
     'Show short text next to "Atlas"',
     'Hidden lines (ids):'));

{ TAtlasStrings }

class function TAtlasStrings.Text(AId: TAtlasTextId): string;
begin
  Result := Texts[FLanguage, AId];
end;

class function TAtlasStrings.Fmt(AId: TAtlasTextId; const AArgs: array of const): string;
begin
  Result := Format(Texts[FLanguage, AId], AArgs);
end;

class function TAtlasStrings.Confidence(const AName: string): string;
var
  Level: TAtlasTextId;
begin
  if SameText(AName, 'high') then
    Level := TAtlasTextId.ConfidenceHigh
  else if SameText(AName, 'medium') then
    Level := TAtlasTextId.ConfidenceMedium
  else if SameText(AName, 'low') then
    Level := TAtlasTextId.ConfidenceLow
  else
    Exit('');
  Result := Fmt(TAtlasTextId.ProblemsConfidence, [Text(Level)]);
end;

initialization
  TAtlasStrings.Language := TAtlasLanguage.German;

end.
