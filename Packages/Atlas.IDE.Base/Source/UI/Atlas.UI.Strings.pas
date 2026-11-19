unit Atlas.UI.Strings;

// Oberflächentexte von Atlas auf Deutsch und Englisch (#446). Die Sprache
// setzt die IDE-Schicht beim Laden nach der Sprache der IDE (Rückfall
// Englisch). Bezeichner, Signaturen und XMLDoc-Inhalte werden nie übersetzt.
// Statt resourcestring eine Tabelle: Die Sprache wechselt ohne Ressourcen-DLL.

interface

uses
  Atlas.Core.Documentation.Layout,
  Atlas.Core.Localization.Language,
  Atlas.Core.Signature.Format;

{$SCOPEDENUMS ON}

type
  /// <summary>Sprache der Oberfläche; dieselbe für Core (Atlas.Core.Localization.Language, #1458).</summary>
  TAtlasLanguage = Atlas.Core.Localization.Language.TAtlasLanguage;

  TAtlasTextId = (
    OptionalDefault, NoOverloadWith, MoreOverloads, ChipAll, ChipMethods, ChipProperties, ChipEvents, ChipTypes,
    ChipSnippets, CompileCancelled, SettingsHangTest, ReloadDone, ReloadKeptModified, ReloadDeleted, PaletteLog,
    PaletteResetHistory, CheckOnSaveDisabled, PaletteCheckNow, KindClass, KindClassRef, KindObject, KindRecord,
    KindInterface, KindHelper, KindEnum, KindType, KindMethod, KindConstructor, KindRoutine, KindProperty,
    KindField, KindVariable, KindConstant, KindEnumMember, PairGuidesIdeOff, PairGuidesIdeOn, ProblemsConfidence,
    ConfidenceHigh, ConfidenceMedium, ConfidenceLow, SettingsServerFilter, HelpInsightIdeOff, HelpInsightIdeOn,
    TooltipWatchesIdeOff, TooltipWatchesIdeOn, ReloadDiffTitle, AccessSignature, AccessParameter,
    ProjectSettingsTitle, ProjectSettingsNoProject, ProjectSettingsInvalid, ProjectSettingsCancel,
    MenuToggleEnabled, MenuToggleHover, MenuTogglePairs, MenuToggleGuides, MenuToggleProblems, MenuIndexStatus,
    MenuIndexRebuild, MenuIndexRebuilding, MenuIndexNoServer, MenuGroupNavigation, MenuGroupSearch, MenuGroupCopy,
    MenuGroupChanges, MenuGroupView, MenuGroupIndex, MenuGroupHelp, SettingsPaletteKey, SettingsCheckKey,
    MenuToggleInactive, DiagExportMenu, RenameMenu, EditWritten, EditFailed, EditUnsupported, MenuToggleInlayHints,
    ResultsNothing, MenuReferences,
    MenuImplementations, MenuSymbolSearch, MenuIncoming, MenuOutgoing, MenuSupertypes, MenuSubtypes,
    MenuResultsWindow, EditorActions, EditorExpand, EditorShrink, EditorTypeDefinition, EditorCopyQualified,
    EditorCopyQualifiedParams, EditorFailed, DocTypeParams, DocValue, DocExample, DocSeeAlso, DocParams, DocReturns,
    DocExceptions, DocRemarks, DocUndocumented, DocMore, DocLess, DocCountParam, DocCountParams, DocCountTypeParam,
    DocCountTypeParams, DocCountException, DocCountExceptions, DocItemReturns, DocItemValue, DocItemRemarks,
    DocItemExample, DocItemSeeAlso, SettingsCompletionKey, SettingsSignatureKey, KeysTitle,
    StatusOpenLog, StatusRestartServer, SettingsQuickToggleKey, UndoMenu,
    RedoMenu, UndoListMenu,
    BugReportMenu, GlobalSettingsInvalid,
    MenuToggleOwners,
    EditorMethodToggle, SettingsMethodToggleDown, EditorTestUnit,
    TestUnitLensCreate, UnitSearchTitle, SettingsWelcomeSearchKey, SettingsDiagnosticModeKey,
    SetupMenu,
    KeyMapMenu, KeyMapUnitSearchIde, BookmarksMenuAdd,
    MetricsReportCommand, GenerateMenuCommand,
    WelcomeSetupNewNoProject,
    TeamFileCommand, TestsNoBuildRunner, StartProfilesNotOpen, StartProfilesWriteFailed,
    StartProfilesSaveFailed, StartProfilesDebuggerRunning, StartProfilesNoRunAction, TestsRunOff,
    NotificationsCommand, NotificationsModeShow, NotificationsModeCollect, NotificationsModeOff,
    NotificationsCheckDisabled, NotificationsCompare, NotificationsReloaded, NotificationsReloadKept,
    NotificationsReloadKeptText, NotificationsReloadDeleted, WelcomeQuickPull, WelcomeQuickMsgPullBlocked,
    SettingsWelcomeQuickActionsBuildKey, SettingsWelcomeQuickActionsTestKey, SettingsIssuesConnectionRemove,
    SettingsIssuesProjectMatch, SettingsIssuesProjectSource, SettingsIssuesProjectAddCurrent,
    SettingsIssuesProjectAdd, SettingsIssuesProjectAddFile, SettingsIssuesProjectAddFolder,
    SettingsIssuesProjectPersonal, SettingsIssuesProjectTeam, SettingsIssuesProjectCovered,
    SettingsIssuesProjectMatchTaken, SettingsIssuesProjectNoProject, SettingsIssuesProjectReadOnly,
    SettingsIssuesProjectFileFilter, CreateIssueCommand, NewIssueCreatedTitle, HideElementCommand,
    SettingsExportCommand, SettingsImportCommand, SettingsProfileCommand, SettingsResetCommand, SigWarning,
    SigFailed, UsesUnusedHint, UsesInitializationHint,
    UsesAllowlistHint, UsesImplementationHint, ProblemNextCommand, ProblemPreviousCommand,
    TypeArgHeader,
    TypeArgHeaderPlain, TypeArgOnlyClasses, TypeArgOnlyValues, TypeArgOnlyConstructible, TypeArgImplements,
    TypeArgDescends, TypeArgHiddenFooter, TypeArgKindClasses, TypeArgKindRecords, TypeArgKindInterfaces,
    TypeArgKindEnums, TypeArgKindBasic, QuickOpenTitle,
    NavBackCommand, NavForwardCommand, NavLastEditCommand, NavListCommand, PeekDefinitionCommand,
    PeekReferencesCommand, OutlineCommand,
    BreadcrumbsCommand,
    JumpToMatchCommand, JumpToMatchSelectCommand, NextChangeCommand, PreviousChangeCommand, ChangeAddedTitle,
    MoveLinesUpCommand,
    MoveLinesDownCommand, DuplicateLinesUpCommand, DuplicateLinesDownCommand, CompleteStatementCommand,
    CompleteStatementTryFinally, CompleteStatementTryExcept,
    MultiCursorNextCommand, MultiCursorSkipCommand, MultiCursorLineEndsCommand, MultiCursorAboveCommand,
    MultiCursorBelowCommand, MoveClassTitle, MoveClassPrompt, MoveClassFailed, MoveClassWarning, UnitRenameTitle,
    UnitRenameFailed, MinimapNoticeTitle, SearchCommand, SearchNextCommand, SearchPreviousCommand,
    SearchInMethodCommand, FormatCodeCommand, ProcessesMenu,
    UsesHiddenOne, UsesHiddenFew, UsesHiddenMore, UsesCycleDirect, UsesCycleChain,
    InheritedAbstractOne, InheritedAbstractMore, PropertyAccessorsFailed, PropertyAccessorsWarning,
    InvertBooleanTitle, InvertBooleanPrompt, InvertBooleanFailed, InvertBooleanNothing, InvertBooleanPreviewHint,
    InvertBooleanApply, InvertBooleanDone, InvertBooleanWarning, PromoteVariableTitle, PromoteVariablePrompt,
    PromoteVariableFailed, PromoteVariableNothing, PromoteVariablePreviewHint, PromoteVariableApply,
    PromoteVariableDone, PromoteVariableWarning, AnonymousMethodTitle, AnonymousMethodPrompt, AnonymousMethodFailed,
    AnonymousMethodNothing, AnonymousMethodPreviewHint, AnonymousMethodApply, AnonymousMethodDone,
    AnonymousMethodWarning,
    ToggleBlockCommentCommand, NewLineBelowCommand, NewLineAboveCommand,
    UnwrapCommand,
    ProblemsWindowCaption, ProblemsWindowCommand, ProblemsScopeFile, ProblemsScopeProject,
    ProblemsScopeGroup, ProblemsKindError, ProblemsKindWarning, ProblemsKindInfo, ProblemsGroupNone,
    ProblemsGroupFile, ProblemsGroupRule, ProblemsGroupCategory, ProblemsColumnCategory, ProblemsStatusProject,
    ProblemsMenuSuppress, ProblemsMenuConfigure, ProblemsExplainBad, ProblemsExplainGood, ProblemsNoServer,
    ProblemsExperimental, ProblemsCompilerConfirmed, ProblemsCompilerConfirmedCode,
    InlayDefinesLabel,
    GotoInterfaceCommand, GotoImplementationCommand, GotoUsesCommand,
    GotoInitializationCommand, ReturnFromSectionCommand, FindMethodCommand, EditorToolbarCustomizeCommand,
    EditorToolbarLabels, EditorToolbarPosition, EditorToolbarPositionBelow, EditorToolbarPositionAbove,
    EditorToolbarPositionInline, QuickBookmarkToggleCommand, NextBookmarkCommand, PreviousBookmarkCommand,
    QuickBookmarkSetCommand, QuickBookmarkJumpCommand,
    // Platzhalter im Parameter-Hint (#451).
    FormatPlaceholder, FormatWidth, FormatPrecision, FormatUnused, FormatInvalid, FormatTooMany, FormatConflict,
    FormatKindInteger, FormatKindUnsigned, FormatKindHex, FormatKindFloat, FormatKindMoney, FormatKindString,
    FormatKindPointer, FormatLiteralString, FormatLiteralChar, FormatLiteralInteger, FormatLiteralFloat,
    FormatLiteralBoolean, FormatLiteralOther,
    // Aufrufdiagramm (#1122).
    CallDiagramCommand,
    // Auswirkungsanalyse (#1120).
    ImpactCommand,
    // Suchleiste: Ersetzen, Regex, Verlauf, Bereiche über Dateien (#893).
    SearchReplaceCommand,
    // Schranke für Hinweise und Warnungen (#530).
    BuildCountWarning, BuildCountWarnings, BuildCountHint, BuildCountHints, BuildCountJoin,
    // Eigene Wertdarstellung beim Debuggen (#854).
    StepIntoTargetCommand,
    // Datenfluss „Woher kommt der Wert?“ / „Wohin geht der Wert?“ (#690)
    MenuDataFlowSources, MenuDataFlowTargets,
    // Methode ohne Self (#686): Marke und Code-Aktion.
    InlayMethodWithoutSelf, MethodKindTitle,
    MethodKindFailed, MethodKindNothing, MethodKindPreviewHint, MethodKindApply, MethodKindDone, MethodKindWarning,
    // Typ-Alias einführen und auflösen (#681).
    TypeAliasTitle, TypeAliasPrompt, TypeAliasFailed, TypeAliasNothing, TypeAliasPreviewHint, TypeAliasApply,
    TypeAliasDone, TypeAliasWarning, InlineTypeAliasTitle, InlineTypeAliasFailed, InlineTypeAliasNothing,
    InlineTypeAliasApply, InlineTypeAliasDone,
    // Aufzählung mit Namenstabelle (#667).
    EnumTableTitle, EnumTablePrompt, EnumTableFailed, EnumTableNothing, EnumTablesPreviewHint, EnumTableApply,
    EnumTableDone, EnumTablesWarning, EnumTablesSyncTitle, EnumTablesSyncFailed, EnumTablesSyncNothing,
    EnumTablesSyncApply, EnumTablesSyncDone,
    // Überladung anlegen (#674).
    OverloadFailed,
    // Typ des markierten Ausdrucks (#689): Befehl, Optionsseite, Tooltip.
    ExpressionTypeCommand,
    // Methodenrümpfe in Deklarationsreihenfolge (#660): Befehl, Vorschau, Meldungen, Optionsseite.
    MethodOrderCommand,
    // Dialog „Mitglieder herauslösen“ und „Interface herauslösen“ (#664).
    ExtractIntfFailed, ExtractIntfWarning,
    // „Basisklasse herauslösen“ (#713) im selben Dialog.
    ExtractSuperFailed,
    // „Mitglied in Vorfahr/Nachfahren verschieben“ (#675) im selben Dialog.
    MoveMemberFailed,
    // „Zugriffsmethode durch Feld ersetzen“ (#717).
    InlineAccessorFailed, InlineAccessorWarning,
    // „Sicher löschen“ (#716).
    SafeDeleteCommand, SafeDeleteFailed, SafeDeleteAskOverrides, SafeDeleteAskCascade, SafeDeleteWarning,
    // Serverzugang der Versionsverwaltung (#1287)
    WelcomeQuickMsgPullLogin,
    // Git-Optionen fürs Branch-Anlegen (#1289)
    VcsBranchPushFailed, VcsBranchWorktreeCreated, VcsBranchFolderTaken,
    // Fenster „Atlas-Server“ (#1356).
    ServerWindowCommand,
    // Designer-Leiste im Formular-Designer (#1442).
    DesignerBarSearchHint,
    // Aktualisierung der Prüfung (problems.update, problems.liveDelayMs).
    ProblemsCheckFileCommand,
    // Sprungmenü am Sichtbarkeitsglied (#1768).
    SectionAppendCommand,
    // Auswahlsätze im Designer: Taste in der Übersicht (#739).
    DesignerSelectionSetsSaveCommand,
    // Im Designer zeigen (#511): Taste in der Übersicht.
    DesignerShowComponentCommand,
    // Text im Designer bearbeiten (#748): Taste in der Übersicht.
    DesignerInlineCaptionCommand,
    // Auswahlleiste und Lupe im Designer: Tasten in der Übersicht.
    DesignerSelectionBarCommand, DesignerMagnifierCommand, DesignerUsagesCommand,
    // Texte von Smart Paste und Editorleiste, deren Units schon an der Grenze der uses-Liste stehen.
    SmartPasteDone, SmartPasteFailed, SmartPasteImplementation, SmartPasteUsesTitle, CommandPaletteCommand,
    EditorToolbarFindings, EditorToolbarMore, EditorToolbarNoParts, EditorToolbarNoReturn, EditorToolbarNoSection,
    EditorToolbarReturnLine, EditorToolbarReturnLineIn, GotoUsesToward, TestsCompareValues,
    // Zuletzt benutzte Testliste ausführen (#2167): Taste in der Übersicht.
    TestsListsRunCommand,
    // Erneut anhängen (Debugger): Taste in der Übersicht.
    DebugReattachCommand);

  TAtlasStrings = class
  private
    class function GetLanguage: TAtlasLanguage; static;
    class procedure SetLanguage(AValue: TAtlasLanguage); static;
  public
    class function Text(AId: TAtlasTextId): string; static;
    /// <summary>Text mit Platzhaltern wie Format.</summary>
    class function Fmt(AId: TAtlasTextId; const AArgs: array of const): string; static;
    /// <summary>"Konfidenz: mittel" zu "high", "medium", "low" (#144); '' bei anderem Wert.</summary>
    class function Confidence(const AName: string): string; static;
    /// <summary>Überschrift über Typargumenten (#450): „T: class · nur Klassen“, ohne Constraint „Typargument T“.
    /// AHint ist der Code des Servers (classes, values, constructible, implements:X, descends:X).</summary>
    class function TypeArgHeading(const AParam, AConstraint, AHint: string): string; static;
    /// <summary>Fußzeile „Ausgeblendet: Records, Aufzählungen“ zu den Codes "records,enums"; '' ohne.</summary>
    class function TypeArgHidden(const AKinds: string): string; static;
    /// <summary>Fußzeile im uses-Abschnitt (#469) zu den schon eingebundenen Units: „X ist schon eingebunden und
    /// fehlt hier“, bis drei Namen aufgezählt, sonst „X, Y und n weitere …“; '' ohne.</summary>
    class function UsesHidden(const AUnits: TArray<string>): string; static;
    /// <summary>Zirkelbezug (#469) zur Kette "uA → uB → Haupt": „uA bindet diese Unit über uB im interface-Teil
    /// ein“; '' ohne.</summary>
    class function UsesCycle(const AChain: string): string; static;
    /// <summary>Zählung eines Builds (#530): „2 Warnungen, 1 Hinweis“, Einzahl bei 1; '' ohne beides.</summary>
    class function BuildCounts(AWarnings, AHints: Integer): string; static;
    /// <summary>Fußzeile nach "inherited " (#482) zu den ausgelassenen abstrakten Vorfahrmethoden
    /// ("TBasis.Zeichnen"): eine mit Namen, mehrere aufgezählt (höchstens drei, dann „…“); '' ohne.</summary>
    class function InheritedAbstract(const AMethods: TArray<string>): string; static;
    /// <summary>„vom Compiler bestätigt (E2035)“ (#1024); ohne AShowCode bzw. ohne Code nur „vom Compiler
    /// bestätigt“.</summary>
    class function CompilerConfirmed(const ACode: string; AShowCode: Boolean): string; static;
    /// <summary>Überschriften der XMLDoc-Abschnitte in der Sprache der Oberfläche; eine Stelle für Hover und
    /// Detailpanel.</summary>
    class function DocLabels: TAtlasDocLabels; static;
    /// <summary>Zeile der Platzhalter im Parameter-Hint (#451); '' ohne.</summary>
    class function SignatureFormatLine(const ALine: TAtlasFormatLine): string; static;
    /// <summary>Art eines Typbuchstabens (d → ganzzahlig, s → String …).</summary>
    class function FormatKind(AType: Char): string; static;
    /// <summary>Sprache aller Plugin-Texte (TAtlasTextLanguage.Current).</summary>
    class property Language: TAtlasLanguage read GetLanguage write SetLanguage;
  end;

implementation

uses
  Atlas.Core.Signature.Contract,
  System.StrUtils,
  System.SysUtils;

const
  /// <summary>Bis zu so viele Namen stehen ausgeschrieben in einem Hinweis, darüber nur die ersten und die Anzahl.
  /// </summary>
  cMaxNamesListed = 3;
  /// <summary>Arten von Literalen, wie der Server sie nennt, und ihre Beschriftung.</summary>
  cLiteralKinds: array[0..4] of string = ('string', 'char', 'integer', 'float', 'boolean');
  cLiteralKindTexts: array[0..4] of TAtlasTextId = (TAtlasTextId.FormatLiteralString,
    TAtlasTextId.FormatLiteralChar, TAtlasTextId.FormatLiteralInteger, TAtlasTextId.FormatLiteralFloat,
    TAtlasTextId.FormatLiteralBoolean);
  /// <summary>Arten von Typen, die der Server für ein Typargument ausblendet, und ihre Beschriftung.</summary>
  cTypeArgKinds: array[0..4] of string = ('classes', 'records', 'interfaces', 'enums', 'basic');
  cTypeArgKindTexts: array[0..4] of TAtlasTextId = (TAtlasTextId.TypeArgKindClasses,
    TAtlasTextId.TypeArgKindRecords, TAtlasTextId.TypeArgKindInterfaces, TAtlasTextId.TypeArgKindEnums,
    TAtlasTextId.TypeArgKindBasic);
  cTexts: array[TAtlasLanguage, TAtlasTextId] of string = (
    ( 'optional, Standard %s',
     'Keine Überladung mit %d Parametern.', '… %d weitere', 'Alle', 'Methoden', 'Eigenschaften', 'Ereignisse',
     'Typen', 'Snippets', 'Atlas: Compile abgebrochen – %s', 'Wächter testen (1 s)',
     'Atlas: %d Dateien neu geladen', 'Atlas: %s wurde außerhalb geändert und hat ungespeicherte Änderungen; die IDE fragt nach.',
     'Atlas: %s existiert nicht mehr.', 'Protokoll öffnen', 'Verlauf der Vervollständigung zurücksetzen',
     'Atlas: Compilerprüfung nach dem Speichern für %s abgeschaltet (%d ms > %d ms); Strg+Alt+F9 prüft von Hand.',
     'Compiler prüfen (Syntaxprüfung)',
     'Klasse', 'Klassenreferenz', 'Objekttyp', 'Record', 'Interface', 'Helfer', 'Aufzählung', 'Typ', 'Methode', 'Konstruktor', 'Routine', 'Property', 'Feld', 'Variable', 'Konstante', 'Aufzählungswert',
     'Atlas zeichnet die Blocklinien selbst und hat die Strukturhervorhebung der IDE abgeschaltet; ' +
       'wirkt nach dem nächsten Start von Delphi.',
     'Atlas hat die Strukturhervorhebung der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Konfidenz: %s', 'hoch', 'mittel', 'niedrig',
     'Atlas-Server|AtlasServer.exe|Programme (*.exe)|*.exe',
     'Atlas zeigt den Tooltip selbst und hat Help Insight der IDE abgeschaltet; wirkt nach dem ' +
       'nächsten Start von Delphi.',
     'Atlas hat Help Insight der IDE wieder eingeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Atlas zeigt Werte beim Debuggen im eigenen Tooltip und hat die Ausdrucksauswertung im Kurzhinweis der IDE ' +
       'abgeschaltet; wirkt nach dem nächsten Start von Delphi.',
     'Atlas hat die Ausdrucksauswertung im Kurzhinweis der IDE wieder eingeschaltet; wirkt nach dem nächsten ' +
       'Start von Delphi.',
     'Atlas: Unterschied in %s (- Editor, + Platte):', 'Atlas Parameterhilfe', 'Parameter %d: %s', 'Atlas-Einstellungen des Projekts',
     'Kein Projekt geöffnet.', 'atlas.json ist kein gültiges JSON; bitte zuerst dort korrigieren.', 'Abbrechen', 'Code Insight von Atlas', 'Eigener Tooltip', 'Klammerpaare färben', 'Blocklinien',
     'Probleme anzeigen',
     'Index-Status', 'Index neu aufbauen', 'Atlas: Index wird ohne Cache neu aufgebaut; der Fortschritt steht im Menütitel.',
     'Atlas: Server nicht erreichbar.',
     'Navigation', 'Suchen', 'Kopieren', 'Änderungen', 'Anzeige', 'Index', 'Hilfe und Diagnose',
     'Befehlspalette:', 'Syntaxprüfung jetzt:', 'Inaktive {$IFDEF}-Zweige ausgrauen',
     'Diagnoselog exportieren…',
     'Symbol umbenennen…',
     'Atlas: %d nicht geöffnete Dateien direkt auf der Platte geändert.',
     'Atlas: Änderungen nicht (vollständig) übernommen: %s',
     'Atlas: %d Dateioperationen (anlegen, umbenennen, löschen) nicht ausgeführt.', 'Inlay-Hints',
     'Atlas: Zum Symbol am Cursor gibt es keine Ergebnisse.',
     'Referenzen suchen',
     'Implementierungen suchen',
     'Symbol im Projekt suchen…',
     'Aufrufer anzeigen',
     'Aufrufe anzeigen',
     'Vorfahren anzeigen',
     'Nachfahren anzeigen',
     'Ergebnisfenster',
     'Code-Aktionen…',
     'Auswahl erweitern',
     'Auswahl verkleinern',
     'Gehe zu Typdefinition',
     'Qualifizierten Namen kopieren',
     'Qualifizierten Namen mit Parametern kopieren',
     'Atlas: Anfrage an den Server fehlgeschlagen: %s',
     'TYPPARAMETER',
     'WERT',
     'BEISPIEL',
     'SIEHE AUCH',
     'PARAMETER',
     'RÜCKGABE',
     'AUSNAHMEN',
     'HINWEISE',
     'nicht dokumentiert',
     'Mehr anzeigen ▾',
     'Weniger anzeigen ▴',
     '%d Parameter',
     '%d Parameter',
     '%d Typparameter',
     '%d Typparameter',
     '%d Ausnahme',
     '%d Ausnahmen',
     'Rückgabe',
     'Wert',
     'Hinweis',
     'Beispiel',
     'Siehe auch',
     'Vervollständigung:',
     'Parameter-Hint:',
     'Tastenkonflikte',
     'Protokoll öffnen',
     'Server neu starten',
     'Schnellschalter',
     'Letzte Atlas-Änderung zurücknehmen',
     'Letzte Atlas-Änderung wiederherstellen',
     'Atlas-Änderungen',
     'Fehlerbericht erstellen…',
     'settings.json ist kein gültiges JSON; bitte zuerst dort korrigieren.', 'Anweisungen mitfärben',
     'Deklaration/Implementierung wechseln', 'Deklaration/Implementierung wechseln (Taste 2)',
     'Zwischen Unit und Testunit wechseln', '+ Testunit %s anlegen',
     'Units suchen',
     'Suchfeld der Willkommensseite', 'Diagnosemodus ein/aus', 'Einrichtung prüfen…',
     'Tastenkürzel-Übersicht…',
     'Units suchen über Strg+F12 (statt IDE-Dialog)',
     'Lesezeichen setzen…', 'Metrikbericht des Projekts',
     'Erzeugen…', 'Neu mit Atlas: Kein Projekt geöffnet.',
     'Projektdatei .atlas öffnen', 'die Builds auf Auftrag laufen nicht (Compile-Ereignisse aus)',
     'Atlas: Das Projekt %s ist nicht geöffnet.',
     'Atlas: Die Startoptionen ließen sich nicht setzen (%s).',
     'Atlas: Die Startprofile ließen sich nicht speichern.',
     'Atlas: Der Debugger läuft; erst beenden.', 'Atlas: Der Befehl „Start“ der IDE ist gerade nicht verfügbar.',
     'Tests: „DUnitX-Tests ausführen“ ist ausgeschaltet (Tools › Optionen › Atlas › Compiler).',
     'Benachrichtigungen', 'Einblenden und sammeln', 'Nur sammeln',
     'Aus',
     'Prüfung nach dem Speichern abgeschaltet', 'Vergleichen', 'Dateien neu geladen: %d',
     'Eigene Änderungen behalten: %s',
     '%s wurde außerhalb geändert und hat ungespeicherte Änderungen; die IDE fragt nach.', 'Datei gelöscht: %s',
     'Pull',
     'Schnellaktion: Pull für %s gesperrt: Erst lokale Änderungen sichern.',
     'Schnellaktion „Öffnen und bauen“',
     'Schnellaktion „Tests“',
     'Entfernen',
     'Gilt für', 'Quelle', 'Aktuelles Projekt hinzufügen', 'Hinzufügen …',
     'Projekt oder Projektgruppe …', 'Ordner …', 'persönlich', 'aus .atlas', 'persönlich · von .atlas überdeckt',
     'Für diesen Pfad gibt es schon eine Zeile.', 'Es ist kein Projekt geöffnet.',
     'Aus der .atlas des Projekts; ändern lässt sie sich nur dort.',
     'Delphi-Projekte (*.dproj, *.groupproj)|*.dproj;*.groupproj',
     'Issue anlegen …',
     'Issue angelegt', 'Element ausblenden …',
     'Einstellungen exportieren…', 'Einstellungen importieren…',
     'Einstellungsprofil laden…', 'Alle Einstellungen zurücksetzen…', 'Hinweis: %s',
     'Signatur ändern fehlgeschlagen: %s', 'Aus %s wird nichts verwendet', '%s wird wegen initialization nicht als ungenutzt gezeigt',
     '%s steht in usesKeep (atlas.json) und wird nicht als ungenutzt gezeigt',
     '%s wird nur in der implementation gebraucht', 'Nächster Befund', 'Vorheriger Befund', '%s: %s · %s', 'Typargument %s', 'nur Klassen',
     'nur Records und Grundtypen', 'nur Klassen mit parameterlosem Konstruktor', 'nur Typen, die %s implementieren',
     'nur Typen, die von %s abgeleitet sind', 'Ausgeblendet: %s', 'Klassen', 'Records', 'Interfaces',
     'Aufzählungen', 'Grundtypen',
     'Schnell öffnen', 'Zurück (Navigationsverlauf)', 'Vor (Navigationsverlauf)',
     'Letzte Bearbeitungsstelle', 'Navigationsverlauf …',
     'Definition einblenden', 'Referenzen einblenden', 'Gliederung …', 'Brotkrumenleiste', 'Zum Gegenstück springen',
     'Bis zum Gegenstück markieren',
     'Nächste Änderung', 'Vorherige Änderung', 'Neu seit dem letzten Commit',
     'Zeilen nach oben verschieben', 'Zeilen nach unten verschieben', 'Zeilen darüber duplizieren',
     'Zeilen darunter duplizieren',
     'Anweisung vervollständigen', 'try … finally … end;',
     'try … except … end;',
     'Wort bzw. nächstes Vorkommen markieren (Mehrfachmarken)', 'Vorkommen überspringen (Mehrfachmarken)',
     'Marken an die Zeilenenden setzen', 'Marke in der Zeile darüber', 'Marke in der Zeile darunter',
     'Klasse in eigene Unit verschieben', 'Name der neuen Unit:', 'Klasse verschieben fehlgeschlagen: %s', 'Hinweis: %s',
     'Unit umbenannt',
     'uses nachziehen fehlgeschlagen: %s',
     'Zwei Minimaps sichtbar',
     'Suchen (Atlas) …', 'Weitersuchen (Atlas)', 'Rückwärts weitersuchen (Atlas)', 'In Methode suchen …', 'Formatieren',
     'Prozesse am Projekt…',
     '%s ist schon eingebunden und fehlt hier',
     '%s sind schon eingebunden und fehlen hier',
     '%s und %d weitere sind schon eingebunden und fehlen hier',
     '%s bindet diese Unit im interface-Teil ein',
     '%s bindet diese Unit über %s im interface-Teil ein',
     '%s ist abstrakt und fehlt',
     'Abstrakte Vorfahrmethoden fehlen: %s',
     'Property anlegen fehlgeschlagen: %s',
     'Hinweis: %s',
     'Boolean umkehren',
     'Neuer Name mit der Gegenbedeutung:',
     'Boolean umkehren fehlgeschlagen: %s',
     'Boolean umkehren: nichts zu ändern.',
     '%d Stellen in %d Dateien werden umbenannt und verneint',
     'Umkehren',
     'Boolean umgekehrt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Lokale Variable und Feld umwandeln',
     'Neuer Name:',
     'Umwandeln fehlgeschlagen: %s',
     'Umwandeln: nichts zu ändern.',
     '%d Stellen in %d Datei werden umgestellt',
     'Umwandeln',
     'Umgewandelt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Anonyme Methode in Methode umwandeln',
     'Name der neuen Methode:',
     'Umwandeln fehlgeschlagen: %s',
     'Umwandeln: nichts zu ändern.',
     '%d Änderungen in %d Datei',
     'Umwandeln',
     'Umgewandelt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Blockkommentar umschalten',
     'Neue Zeile darunter',
     'Neue Zeile darüber',
     'Umschließung entfernen',
     'Atlas-Prüfung',
     'Fenster „Atlas-Prüfung“',
     'Aktuelle Datei',
     'Aktuelles Projekt',
     'Projektgruppe',
     'Error',
     'Warnung',
     'Info',
     'Nicht gruppieren',
     'Nach Datei',
     'Nach Regel',
     'Nach Kategorie',
     'Kategorie',
     'Projekt: %d von %d Units geprüft',
     'Für diese Zeile unterdrücken',
     'Regel einstellen…',
     'Falsch:',
     'Richtig:',
     'Atlas-Prüfung: Der Server läuft nicht.',
     'Experimentell',
     'vom Compiler bestätigt',
     'vom Compiler bestätigt (%s)',
     'definiert %s',
     'Zum interface-Teil',
     'Zum implementation-Teil',
     'Zur uses-Klausel',
     'Zu initialization',
     'Zurück zum Ausgangspunkt des Abschnittssprungs',
     'Methode suchen …',
     'Editorleiste anpassen …',
     'Text neben den Symbolen',
     'Position:',
     'unter der Brotkrumenleiste',
     'über der Brotkrumenleiste',
     'in der Brotkrumenzeile',
     'Unnummeriertes Lesezeichen setzen/entfernen',
     'Nächstes Lesezeichen',
     'Voriges Lesezeichen',
     'Lesezeichen 1–9 setzen',
     'Zu Lesezeichen 1–9 springen',
     'Platzhalter %d von %d erwartet %s',
     'Breite für Platzhalter %d von %d (%s), ganzzahlig',
     'Genauigkeit für Platzhalter %d von %d (%s), ganzzahlig',
     'Argument %d kommt im Formatstring nicht vor (%d Platzhalter).',
     'Ungültiger Platzhalter %s: EConvertError zur Laufzeit.',
     'Mehr Argumente als Platzhalter: Argument %d wird nicht ausgegeben.',
     'Platzhalter %d (%s) erwartet %s, Argument %d ist %s: EConvertError zur Laufzeit.',
     'ganzzahlig', 'ganzzahlig ohne Vorzeichen', 'ganzzahlig (hexadezimal)', 'Gleitkomma', 'Gleitkomma (Währung)',
     'String', 'Zeiger', 'ein String', 'ein Zeichen', 'eine Ganzzahl', 'eine Gleitkommazahl', 'ein Wahrheitswert',
     'ein anderer Typ',
     'Aufrufdiagramm',
     'Auswirkungen anzeigen',
     'Suchen und ersetzen …',
     '1 Warnung',
     '%d Warnungen',
     '1 Hinweis',
     '%d Hinweise',
     '%s, %s',
     'Gezielt hineinspringen', 'Woher kommt der Wert?', 'Wohin geht der Wert?',
     'braucht kein Self',
     'Methode ohne Self umwandeln',
     'Umwandeln fehlgeschlagen: %s',
     'Umwandeln: nichts zu ändern.',
     '%d Änderungen in %d Datei',
     'Umwandeln',
     'Umgewandelt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Typ-Alias einführen',
     'Name des Alias:',
     'Typ-Alias einführen fehlgeschlagen: %s',
     'Typ-Alias einführen: nichts zu ändern.',
     '%d Änderungen in %d Dateien',
     'Einführen',
     'Typ-Alias eingeführt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Alias auflösen',
     'Alias auflösen fehlgeschlagen: %s',
     'Alias auflösen: nichts zu ändern.',
     'Auflösen',
     'Alias aufgelöst: %d Änderungen in %d Dateien',
     'Namenstabelle anlegen',
     'Name der Tabelle:',
     'Namenstabelle anlegen fehlgeschlagen: %s',
     'Namenstabelle anlegen: nichts zu ändern.',
     '%d Änderungen in %d Dateien',
     'Anlegen',
     'Namenstabelle angelegt: %d Änderungen in %d Dateien',
     'Warnung: %s',
     'Tabellen nachziehen',
     'Tabellen nachziehen fehlgeschlagen: %s',
     'Tabellen nachziehen: Alle Tabellen und case-Anweisungen passen schon.',
     'Nachziehen',
     'Tabellen nachgezogen: %d Änderungen in %d Dateien',
     'Überladung anlegen fehlgeschlagen: %s',
     'Typ des Ausdrucks',
     'implementation wie Klasse ordnen',
     'Interface herauslösen fehlgeschlagen: %s',
     'Hinweis: %s',
     'Basisklasse herauslösen fehlgeschlagen: %s',
     'Mitglied verschieben fehlgeschlagen: %s',
     'Zugriffsmethode durch Feld ersetzen fehlgeschlagen: %s',
     'Hinweis: %s',
     'Sicher löschen',
     'Sicher löschen fehlgeschlagen: %s',
     '„%s“ wird in %d Nachfahren überschrieben:%s%s%sÜberschreibungen mitlöschen?',
     'Danach unbenutzt:%s%s%sMitlöschen?',
     'Hinweis: %s',
     'Schnellaktion: Pull für %s – Anmeldung am Server nötig (Tools › Optionen › Atlas › Versionsverwaltung › Server).',
     'Branch %s angelegt, aber nicht auf den Server gepusht (%s); der lokale Branch bleibt.',
     'Branch %s von %s im Ordner %s angelegt.',
     'Branch anlegen: Den Ordner %s gibt es schon; nichts angelegt.',
     'Atlas-Server: Speicher und Laufzeiten',
     'Komponenten suchen',
     'Datei jetzt prüfen',
     'Neue Zeile am Ende des Abschnitts',
     'Designer: Auswahl speichern …',
     'Im Designer zeigen',
     'Designer: Text bearbeiten',
     'Designer: Auswahlleiste',
     'Designer: Lupe',
     'Designer: Verwendungen im Code',
     'Ergänzt: %s',
     'uses ergänzen fehlgeschlagen: %s',
     'Wegen Zirkelbezug im implementation-Teil: %s',
     'uses ergänzen',
     'Befehlspalette',
     '%s · %d Befunde',
     'Weitere Befehle',
     'Diese Datei hat keinen interface-/implementation-Teil',
     'Atlas: Kein Abschnittssprung, zu dem es zurückgeht.',
     'Atlas: „%s“ – diese Datei hat keinen solchen Abschnitt.',
     'Zurück zu Zeile %d',
     'Zurück zu Zeile %d · %s',
     'Zur uses-Klausel (%s)',
     'Vergleichen',
     'Tests: zuletzt benutzte Testliste ausführen',
     'Debugger: erneut an Prozess anhängen'),
    ( 'optional, default %s', 'No overload with %d parameters.', '… %d more',
     'All', 'Methods', 'Properties', 'Events', 'Types', 'Snippets', 'Atlas: compile cancelled – %s', 'Test watchdog (1 s)',
     'Atlas: %d files reloaded', 'Atlas: %s was changed outside and has unsaved changes; the IDE will ask.',
     'Atlas: %s no longer exists.', 'Open log', 'Reset completion history',
     'Atlas: compiler check after saving switched off for %s (%d ms > %d ms); Ctrl+Alt+F9 checks manually.',
     'Check with compiler (syntax check)',
     'Class', 'Class reference', 'Object type', 'Record', 'Interface', 'Helper', 'Enumeration', 'Type', 'Method', 'Constructor', 'Routine', 'Property', 'Field', 'Variable', 'Constant', 'Enumeration value',
     'Atlas draws the block lines itself and switched off the IDE''s structural highlighting; takes ' +
       'effect after the next start of Delphi.',
     'Atlas switched the IDE''s structural highlighting back on; takes effect after the next start of Delphi.',
     'Confidence: %s', 'high', 'medium', 'low',
     'Atlas server|AtlasServer.exe|Programs (*.exe)|*.exe',
     'Atlas shows the tooltip itself and switched off the IDE''s Help Insight; takes effect after ' +
       'the next start of Delphi.',
     'Atlas switched the IDE''s Help Insight back on; takes effect after the next start of Delphi.',
     'Atlas shows values while debugging in its own tooltip and switched off the IDE''s tooltip expression ' +
       'evaluation; takes effect after the next start of Delphi.',
     'Atlas switched the IDE''s tooltip expression evaluation back on; takes effect after the next start of ' +
       'Delphi.',
     'Atlas: difference in %s (- editor, + disk):', 'Atlas parameter info', 'Parameter %d: %s', 'Atlas project settings',
     'No project open.', 'atlas.json is not valid JSON; please fix it there first.', 'Cancel', 'Atlas Code Insight', 'Own tooltip', 'Colour bracket pairs', 'Block guides',
     'Show problems',
     'Index status', 'Rebuild index', 'Atlas: rebuilding the index without cache; progress shows in the menu title.',
     'Atlas: server not reachable.',
     'Navigation', 'Search', 'Copy', 'Changes', 'View', 'Index', 'Help and diagnostics',
     'Command palette:', 'Syntax check now:', 'Grey out inactive {$IFDEF} branches',
     'Export diagnostic log…',
     'Rename symbol…',
     'Atlas: %d files that were not open changed on disk.',
     'Atlas: changes not (fully) applied: %s',
     'Atlas: %d file operations (create, rename, delete) not performed.', 'Inlay hints',
     'Atlas: No results for the symbol at the cursor.',
     'Find references',
     'Find implementations',
     'Find symbol in project…',
     'Show callers',
     'Show calls',
     'Show supertypes',
     'Show subtypes',
     'Results window',
     'Code actions…',
     'Expand selection',
     'Shrink selection',
     'Go to type definition',
     'Copy qualified name',
     'Copy qualified name with parameters',
     'Atlas: Server request failed: %s',
     'TYPE PARAMETERS',
     'VALUE',
     'EXAMPLE',
     'SEE ALSO',
     'PARAMETERS',
     'RETURNS',
     'EXCEPTIONS',
     'REMARKS',
     'not documented',
     'Show more ▾',
     'Show less ▴',
     '%d parameter',
     '%d parameters',
     '%d type parameter',
     '%d type parameters',
     '%d exception',
     '%d exceptions',
     'Returns',
     'Value',
     'Remarks',
     'Example',
     'See also',
     'Code completion:',
     'Parameter hint:',
     'Key conflicts',
     'Open log',
     'Restart server',
     'Quick switches',
     'Undo last Atlas change',
     'Redo last Atlas change',
     'Atlas changes',
     'Create bug report…',
     'settings.json is not valid JSON; please fix it there first.', 'Colour statements',
     'Switch between declaration and implementation', 'Switch declaration/implementation (key 2)',
     'Switch between unit and test unit', '+ Create test unit %s',
     'Search units',
     'Welcome page search field', 'Diagnostic mode on/off', 'Check setup…', 'Keyboard shortcuts…',
     'Search units via Ctrl+F12 (instead of IDE dialog)',
     'Set bookmark…', 'Project metrics report',
     'Generate…', 'New with Atlas: no project open.',
     'Open project file .atlas', 'builds on request are not running (compile events off)',
     'Atlas: The project %s is not open.',
     'Atlas: The run options could not be set (%s).', 'Atlas: The start profiles could not be saved.',
     'Atlas: The debugger is running; stop it first.',
     'Atlas: The IDE''s Run command is not available right now.',
     'Tests: “Run DUnitX tests” is switched off (Tools › Options › Atlas › Compiler).',
     'Notifications', 'Show and collect', 'Collect only', 'Off', 'Check on save switched off', 'Compare',
     'Files reloaded: %d', 'Own changes kept: %s', '%s was changed outside and has unsaved changes; the IDE asks.',
     'File deleted: %s',
     'Pull',
     'Quick action: pull for %s blocked: save local changes first.',
     'Quick action “Open and build”',
     'Quick action “Tests”',
     'Remove',
     'Applies to', 'Source', 'Add current project', 'Add …',
     'Project or project group …', 'Folder …', 'personal', 'from .atlas', 'personal · overridden by .atlas',
     'There already is a row for this path.', 'No project is open.',
     'From the project’s .atlas; it can only be changed there.',
     'Delphi projects (*.dproj, *.groupproj)|*.dproj;*.groupproj',
     'Create issue …',
     'Issue created',
     'Hide element…', 'Export settings…', 'Import settings…', 'Load settings profile…', 'Reset all settings…',
     'Note: %s',
     'Changing the signature failed: %s', 'Nothing from %s is used', '%s is not shown as unused because of its initialization',
     '%s is listed in usesKeep (atlas.json) and not shown as unused',
     '%s is only needed in the implementation', 'Next finding', 'Previous finding', '%s: %s · %s',
     'Type argument %s', 'classes only', 'records and basic types only',
     'only classes with a parameterless constructor', 'only types implementing %s', 'only types descending from %s',
     'Hidden: %s', 'classes', 'records', 'interfaces', 'enumerations', 'basic types', 'Quick open', 'Back (navigation history)',
     'Forward (navigation history)', 'Last edit location', 'Navigation history …',
     'Peek definition', 'Peek references', 'Outline …', 'Breadcrumbs',
     'Jump to match', 'Select to match', 'Next change',
     'Previous change', 'New since the last commit', 'Move lines up', 'Move lines down', 'Duplicate lines above', 'Duplicate lines below',
     'Complete statement', 'try … finally … end;',
     'try … except … end;',
     'Select word or next occurrence (multiple cursors)', 'Skip occurrence (multiple cursors)',
     'Add cursors at line ends', 'Add cursor on the line above', 'Add cursor on the line below',
     'Move class to its own unit', 'Name of the new unit:', 'Moving the class failed: %s', 'Note: %s',
     'Unit renamed',
     'Updating uses failed: %s', 'Two minimaps visible',
     'Find (Atlas) …', 'Find next (Atlas)', 'Find previous (Atlas)', 'Find in method …', 'Format',
     'Processes on the project…',
     '%s is already used and not listed',
     '%s are already used and not listed',
     '%s and %d more are already used and not listed',
     '%s uses this unit in its interface section',
     '%s uses this unit via %s in its interface section',
     '%s is abstract and not listed',
     'Abstract ancestor methods not listed: %s',
     'Creating the property failed: %s',
     'Note: %s',
     'Invert Boolean',
     'New name with the opposite meaning:',
     'Inverting the Boolean failed: %s',
     'Invert Boolean: nothing to change.',
     '%d places in %d files will be renamed and negated',
     'Invert',
     'Boolean inverted: %d changes in %d files',
     'Warning: %s',
     'Convert local variable and field',
     'New name:',
     'Converting failed: %s',
     'Convert: nothing to change.',
     '%d places in %d file will be changed',
     'Convert',
     'Converted: %d changes in %d files',
     'Warning: %s',
     'Convert anonymous method to method',
     'Name of the new method:',
     'Converting failed: %s',
     'Convert: nothing to change.',
     '%d changes in %d file',
     'Convert',
     'Converted: %d changes in %d files',
     'Warning: %s',
     'Toggle block comment',
     'New line below',
     'New line above',
     'Remove surrounding construct',
     'Atlas Findings',
     '"Atlas Findings" window',
     'Current file',
     'Current project',
     'Project group',
     'Error',
     'Warning',
     'Info',
     'No grouping',
     'By file',
     'By rule',
     'By category',
     'Category',
     'Project: %d of %d units checked',
     'Suppress for this line',
     'Configure rule…',
     'Wrong:',
     'Right:',
     'Atlas Findings: the server is not running.',
     'Experimental',
     'confirmed by the compiler',
     'confirmed by the compiler (%s)',
     'defines %s',
     'Go to interface section',
     'Go to implementation section',
     'Go to uses clause',
     'Go to initialization',
     'Back to where the section jump started',
     'Find method …',
     'Customize editor toolbar …',
     'Text next to the icons',
     'Position:',
     'below the breadcrumb bar',
     'above the breadcrumb bar',
     'in the breadcrumb row',
     'Set/remove unnumbered bookmark',
     'Next bookmark',
     'Previous bookmark',
     'Set bookmark 1–9',
     'Go to bookmark 1–9',
     'Placeholder %d of %d expects %s',
     'Width for placeholder %d of %d (%s), integer',
     'Precision for placeholder %d of %d (%s), integer',
     'Argument %d does not occur in the format string (%d placeholders).',
     'Invalid placeholder %s: EConvertError at run time.',
     'More arguments than placeholders: argument %d is not printed.',
     'Placeholder %d (%s) expects %s, argument %d is %s: EConvertError at run time.',
     'integer', 'unsigned integer', 'integer (hexadecimal)', 'floating point', 'floating point (currency)',
     'string', 'pointer', 'a string', 'a character', 'an integer', 'a floating-point number', 'a Boolean',
     'another type',
     'Call diagram',
     'Show impact',
     'Find and replace …',
     '1 warning',
     '%d warnings',
     '1 hint',
     '%d hints',
     '%s, %s',
     'Step into specific call', 'Where does the value come from?', 'Where does the value go?',
     'Self unused',
     'Convert method without Self',
     'Converting failed: %s',
     'Convert: nothing to change.',
     '%d changes in %d file',
     'Convert',
     'Converted: %d changes in %d files',
     'Warning: %s',
     'Introduce type alias',
     'Alias name:',
     'Introducing the type alias failed: %s',
     'Introduce type alias: nothing to change.',
     '%d changes in %d files',
     'Introduce',
     'Type alias introduced: %d changes in %d files',
     'Warning: %s',
     'Inline alias',
     'Inlining the alias failed: %s',
     'Inline alias: nothing to change.',
     'Inline',
     'Alias inlined: %d changes in %d files',
     'Create name table',
     'Table name:',
     'Creating the name table failed: %s',
     'Create name table: nothing to change.',
     '%d changes in %d files',
     'Create',
     'Name table created: %d changes in %d files',
     'Warning: %s',
     'Update tables',
     'Updating the tables failed: %s',
     'Update tables: all tables and case statements already match.',
     'Update',
     'Tables updated: %d changes in %d files',
     'Creating the overload failed: %s',
     'Expression type',
     'Order implementation like class',
     'Extract interface failed: %s',
     'Note: %s',
     'Extract superclass failed: %s',
     'Move member failed: %s',
     'Replace accessor with field failed: %s',
     'Note: %s',
     'Safe delete',
     'Safe delete failed: %s',
     '“%s” is overridden in %d descendants:%s%s%sDelete the overrides too?',
     'Unused afterwards:%s%s%sDelete these too?',
     'Note: %s',
     'Quick action: pull for %s – server sign-in needed (Tools › Options › Atlas › Version control › Servers).',
     'Branch %s created but not pushed to the server (%s); the local branch stays.',
     'Branch %s created from %s in folder %s.',
     'Create branch: the folder %s already exists; nothing created.',
     'Atlas server: memory and timings',
     'Find components',
     'Check file now',
     'New line at the end of the section',
     'Designer: Save selection …',
     'Show in designer',
     'Designer: Edit text',
     'Designer: Selection bar',
     'Designer: Magnifier',
     'Designer: Usages in code',
     'Added: %s',
     'Adding uses failed: %s',
     'Because of a circular reference in the implementation section: %s',
     'Add uses',
     'Command palette',
     '%s · %d findings',
     'More commands',
     'This file has no interface/implementation section',
     'Atlas: No section jump to return from.',
     'Atlas: “%s” – this file has no such section.',
     'Back to line %d',
     'Back to line %d · %s',
     'Go to uses clause (%s)',
     'Compare',
     'Tests: run last used test list',
     'Debugger: reattach to process'));

{ TAtlasStrings }

class function TAtlasStrings.GetLanguage: TAtlasLanguage;
begin
  Result := TAtlasTextLanguage.Current;
end;

class procedure TAtlasStrings.SetLanguage(AValue: TAtlasLanguage);
begin
  TAtlasTextLanguage.Current := AValue;
end;

class function TAtlasStrings.Text(AId: TAtlasTextId): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

class function TAtlasStrings.Fmt(AId: TAtlasTextId; const AArgs: array of const): string;
begin
  Result := Format(cTexts[TAtlasTextLanguage.Current, AId], AArgs);
end;

class function TAtlasStrings.Confidence(const AName: string): string;
var
  mLevel: TAtlasTextId;
begin
  if SameText(AName, 'high') then
  begin
    mLevel := TAtlasTextId.ConfidenceHigh;
  end
  else if SameText(AName, 'medium') then
  begin
    mLevel := TAtlasTextId.ConfidenceMedium;
  end
  else if SameText(AName, 'low') then
  begin
    mLevel := TAtlasTextId.ConfidenceLow;
  end
  else
  begin
    Exit('');
  end;
  Result := Fmt(TAtlasTextId.ProblemsConfidence, [Text(mLevel)]);
end;

function LiteralKind(const AKind: string): string;
var
  mIndex: Integer;
begin
  mIndex := IndexStr(AKind, cLiteralKinds);
  if mIndex < 0 then
  begin
    Exit(TAtlasStrings.Text(TAtlasTextId.FormatLiteralOther));
  end;
  Result := TAtlasStrings.Text(cLiteralKindTexts[mIndex]);
end;

class function TAtlasStrings.TypeArgHeading(const AParam, AConstraint, AHint: string): string;
var
  mExplanation: string;
begin
  if AHint = 'classes' then
  begin
    mExplanation := Text(TAtlasTextId.TypeArgOnlyClasses);
  end
  else if AHint = 'values' then
  begin
    mExplanation := Text(TAtlasTextId.TypeArgOnlyValues);
  end
  else if AHint = 'constructible' then
  begin
    mExplanation := Text(TAtlasTextId.TypeArgOnlyConstructible);
  end
  else if AHint.StartsWith('implements:') then
  begin
    mExplanation := Fmt(TAtlasTextId.TypeArgImplements, [Copy(AHint, Length('implements:') + 1, MaxInt)]);
  end
  else if AHint.StartsWith('descends:') then
  begin
    mExplanation := Fmt(TAtlasTextId.TypeArgDescends, [Copy(AHint, Length('descends:') + 1, MaxInt)]);
  end
  else
  begin
    mExplanation := '';
  end;
  if (AConstraint = '') or (mExplanation = '') then
  begin
    Exit(Fmt(TAtlasTextId.TypeArgHeaderPlain, [AParam]));
  end;
  Result := Fmt(TAtlasTextId.TypeArgHeader, [AParam, AConstraint, mExplanation]);
end;

class function TAtlasStrings.TypeArgHidden(const AKinds: string): string;
var
  mKind: string;
  mNames: TArray<string>;
  mIndex: Integer;
begin
  mNames := nil;
  for mKind in AKinds.Split([',']) do
  begin
    mIndex := IndexStr(mKind, cTypeArgKinds);
    if mIndex >= 0 then
    begin
      mNames := mNames + [Text(cTypeArgKindTexts[mIndex])];
    end;
  end;
  if Length(mNames) = 0 then
  begin
    Exit('');
  end;
  Result := Fmt(TAtlasTextId.TypeArgHiddenFooter, [string.Join(', ', mNames)]);
end;

class function TAtlasStrings.UsesHidden(const AUnits: TArray<string>): string;
begin
  case Length(AUnits) of
    0: Result := '';
    1: Result := Fmt(TAtlasTextId.UsesHiddenOne, [AUnits[0]]);
    2..cMaxNamesListed: Result := Fmt(TAtlasTextId.UsesHiddenFew, [string.Join(', ', AUnits)]);
  else
    Result := Fmt(TAtlasTextId.UsesHiddenMore, [string.Join(', ', Copy(AUnits, 0, 2)), Length(AUnits) - 2]);
  end;
end;

class function TAtlasStrings.UsesCycle(const AChain: string): string;
var
  mParts: TArray<string>;
begin
  mParts := AChain.Split([' → ']);
  if Length(mParts) < 2 then
  begin
    Exit('');
  end;
  if Length(mParts) = 2 then
  begin
    Exit(Fmt(TAtlasTextId.UsesCycleDirect, [mParts[0]]));
  end;
  Result := Fmt(TAtlasTextId.UsesCycleChain, [mParts[0], string.Join(', ', Copy(mParts, 1, Length(mParts) - 2))]);
end;

class function TAtlasStrings.BuildCounts(AWarnings, AHints: Integer): string;
var
  mWarnings, mHints: string;
begin
  mWarnings := '';
  mHints := '';
  if AWarnings = 1 then
  begin
    mWarnings := Text(TAtlasTextId.BuildCountWarning);
  end
  else if AWarnings > 1 then
  begin
    mWarnings := Fmt(TAtlasTextId.BuildCountWarnings, [AWarnings]);
  end;
  if AHints = 1 then
  begin
    mHints := Text(TAtlasTextId.BuildCountHint);
  end
  else if AHints > 1 then
  begin
    mHints := Fmt(TAtlasTextId.BuildCountHints, [AHints]);
  end;
  if (mWarnings <> '') and (mHints <> '') then
  begin
    Result := Fmt(TAtlasTextId.BuildCountJoin, [mWarnings, mHints]);
  end
  else
  begin
    Result := mWarnings + mHints;
  end;
end;

class function TAtlasStrings.InheritedAbstract(const AMethods: TArray<string>): string;
begin
  case Length(AMethods) of
    0: Result := '';
    1: Result := Fmt(TAtlasTextId.InheritedAbstractOne, [AMethods[0]]);
    2..cMaxNamesListed: Result := Fmt(TAtlasTextId.InheritedAbstractMore, [string.Join(', ', AMethods)]);
  else
    Result := Fmt(TAtlasTextId.InheritedAbstractMore, [string.Join(', ', Copy(AMethods, 0, cMaxNamesListed)) + ', …']);
  end;
end;

class function TAtlasStrings.CompilerConfirmed(const ACode: string; AShowCode: Boolean): string;
begin
  if AShowCode and (ACode <> '') then
  begin
    Result := Fmt(TAtlasTextId.ProblemsCompilerConfirmedCode, [ACode]);
  end
  else
  begin
    Result := Text(TAtlasTextId.ProblemsCompilerConfirmed);
  end;
end;

class function TAtlasStrings.DocLabels: TAtlasDocLabels;
begin
  // Begründung (Rationale) steht nur in der Grundtabelle; die übrigen Beschriftungen kommen aus Texts.
  Result := TAtlasDocLabels.Current;
  Result.Params := Text(TAtlasTextId.DocParams);
  Result.TypeParams := Text(TAtlasTextId.DocTypeParams);
  Result.Returns := Text(TAtlasTextId.DocReturns);
  Result.Value := Text(TAtlasTextId.DocValue);
  Result.Exceptions := Text(TAtlasTextId.DocExceptions);
  Result.Remarks := Text(TAtlasTextId.DocRemarks);
  Result.Example := Text(TAtlasTextId.DocExample);
  Result.SeeAlso := Text(TAtlasTextId.DocSeeAlso);
  Result.Undocumented := Text(TAtlasTextId.DocUndocumented);
  Result.More := Text(TAtlasTextId.DocMore);
  Result.Less := Text(TAtlasTextId.DocLess);
  Result.CountParam := Text(TAtlasTextId.DocCountParam);
  Result.CountParams := Text(TAtlasTextId.DocCountParams);
  Result.CountTypeParam := Text(TAtlasTextId.DocCountTypeParam);
  Result.CountTypeParams := Text(TAtlasTextId.DocCountTypeParams);
  Result.CountException := Text(TAtlasTextId.DocCountException);
  Result.CountExceptions := Text(TAtlasTextId.DocCountExceptions);
  Result.ItemReturns := Text(TAtlasTextId.DocItemReturns);
  Result.ItemValue := Text(TAtlasTextId.DocItemValue);
  Result.ItemRemarks := Text(TAtlasTextId.DocItemRemarks);
  Result.ItemExample := Text(TAtlasTextId.DocItemExample);
  Result.ItemSeeAlso := Text(TAtlasTextId.DocItemSeeAlso);
end;

class function TAtlasStrings.SignatureFormatLine(const ALine: TAtlasFormatLine): string;
begin
  case ALine.Kind of
    TAtlasFormatLineKind.Placeholder:
      Result := Fmt(TAtlasTextId.FormatPlaceholder, [ALine.Placeholder + 1, ALine.Count, FormatKind(ALine.TypeChar)]);
    TAtlasFormatLineKind.Width:
      Result := Fmt(TAtlasTextId.FormatWidth, [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TAtlasFormatLineKind.Precision:
      Result := Fmt(TAtlasTextId.FormatPrecision, [ALine.Placeholder + 1, ALine.Count, ALine.PlaceholderText]);
    TAtlasFormatLineKind.Unused:
      Result := Fmt(TAtlasTextId.FormatUnused, [ALine.Argument + 1, ALine.Count]);
    TAtlasFormatLineKind.Problem:
      case ALine.Problem of
        TAtlasFormatProblem.Invalid:
          Result := Fmt(TAtlasTextId.FormatInvalid, [ALine.PlaceholderText]);
        TAtlasFormatProblem.TooManyArguments:
          Result := Fmt(TAtlasTextId.FormatTooMany, [ALine.Argument + 1]);
        TAtlasFormatProblem.TypeConflict:
          Result := Fmt(TAtlasTextId.FormatConflict, [ALine.Placeholder + 1, ALine.PlaceholderText,
            FormatKind(ALine.TypeChar), ALine.Argument + 1, LiteralKind(ALine.ProblemKind)]);
      else
        Result := '';
      end;
  else
    Result := '';
  end;
end;

class function TAtlasStrings.FormatKind(AType: Char): string;
begin
  case AType of
    'd':
      Result := Text(TAtlasTextId.FormatKindInteger);
    'u':
      Result := Text(TAtlasTextId.FormatKindUnsigned);
    'x':
      Result := Text(TAtlasTextId.FormatKindHex);
    'e', 'f', 'g', 'n':
      Result := Text(TAtlasTextId.FormatKindFloat);
    'm':
      Result := Text(TAtlasTextId.FormatKindMoney);
    's':
      Result := Text(TAtlasTextId.FormatKindString);
    'p':
      Result := Text(TAtlasTextId.FormatKindPointer);
  else
    Result := Text(TAtlasTextId.FormatKindInteger);
  end;
end;

initialization
  TAtlasStrings.Language := TAtlasLanguage.German;

end.
