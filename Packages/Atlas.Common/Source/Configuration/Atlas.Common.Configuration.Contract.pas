unit Atlas.Common.Configuration.Contract;

// Contract des Platform-Features Configuration: die Einstellungen aus
// atlas.json im Projektordner.
//
// Beispiel:
//   {
//     "delphiVersion": "37.0",
//     "language": "de",
//     "project": "App.dproj", "config": "Debug", "platform": "Win64",
//     "rules": { "unused-variable": "warning", "with-statement": { "severity": "off" } },
//     "exclude": ["ThirdParty/**", "Generated/*.pas"],
//     "format": { "indent": 2 }
//   }

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

const
  /// <summary>Eingebaute Regelprofile (#146).</summary>
  BuiltinProfileNames: array[0..4] of string = ('standard', 'fast', 'strict', 'security', 'style');

type
  /// <summary>Schweregrad einer Prüfregel; Default = Vorgabe der Regel.</summary>
  TRuleSeverity = (Default, Off, Hint, Information, Warning, Error);

  /// <summary>Beweislage eines Regeltreffers; begrenzt den Schweregrad.</summary>
  TRuleConfidence = (Low, Medium, High);

  /// <summary>Umbenannte Regelkennungen (#910): Konfiguration und Unterdrückungen mit der
  /// früheren Kennung wirken weiter auf die Regel unter ihrer neuen.</summary>
  TRuleIdAliases = record
  public const
    FormerIds: array[0..1] of string = ('recursive-property-accessor', 'owned-field-not-freed');
    CurrentIds: array[0..1] of string = ('setter-recursion', 'field-not-freed');
  public
    /// <summary>Heutige Kennung zu AId; AId selbst, wenn sie nicht umbenannt wurde.</summary>
    class function Current(const AId: string): string; static;
  end;

  TRuleSetting = record
    Id: string;
    Severity: TRuleSeverity;
    /// <summary>Weitere Optionen der Regel als JSON-Objekt (Text), sonst ''.</summary>
    Options: string;
  end;

  /// <summary>Regelprofil (#146): eingebaut (standard, fast, strict, security, style) oder
  /// eigenes aus "profiles", das ein eingebautes erweitern kann.</summary>
  TRuleProfile = record
    Name: string;
    /// <summary>Eingebautes oder eigenes Profil als Grundlage, '' = standard.</summary>
    Extends: string;
    /// <summary>Nur Regeln dieser Kategorien (bug, vulnerability, code-smell, security-hotspot); leer = alle.</summary>
    Categories: TArray<string>;
    Rules: TArray<TRuleSetting>;
  end;

  /// <summary>Pfadregel (#146): Schweregrade für Dateien, die eines der Muster treffen.
  /// Die Regel-ID "*" steht für alle Regeln.</summary>
  TPathOverride = record
    Files: TArray<string>;
    Rules: TArray<TRuleSetting>;
  end;

  /// <summary>Inlay Hints im Editor (#35).</summary>
  TInlayHintSettings = record
    /// <summary>Parameternamen vor Argumenten.</summary>
    ParameterNames: Boolean;
    /// <summary>Abgeleiteter Typ bei var X := ….</summary>
    InferredTypes: Boolean;
    /// <summary>Hinter dem end langer Blöcke anzeigen, was dort endet.</summary>
    EndMarkers: Boolean;
    /// <summary>Mindestlänge eines Blocks in Zeilen für eine Endmarkierung.</summary>
    EndMarkerMinLines: Integer;
    /// <summary>Hinter {$I datei.inc} die dort gesetzten Symbole, die die Unit prüft (#860).</summary>
    IncludeDefines: Boolean;
    /// <summary>Hinter Steuerzeichen wie ^C in Konstanten der Code (#3, #862).</summary>
    ControlChars: Boolean;
    /// <summary>Marke „ohne Self“ hinter Methoden, die Self nicht brauchen (#686). Kein Schlüssel unter
    /// inlayHints: Die Komposition setzt sie aus refactoring.methodKind und refactoring.methodKindMarker; in
    /// Default aus.</summary>
    MethodWithoutSelf: Boolean;
    class function Default: TInlayHintSettings; static;
  end;

  /// <summary>Code Lens im Editor ("codeLens").</summary>
  TCodeLensSettings = record
    /// <summary>Kennzahlen über jeder Methode (#66): Länge, Tiefe, zyklomatische und kognitive Komplexität,
    /// Parameter.</summary>
    Metrics: Boolean;
    class function Default: TCodeLensSettings; static;
  end;

  /// <summary>Treffersicherheit der Verwendungen ("references", #1119).</summary>
  TReferenceSettings = record
    /// <summary>Erschlossene Treffer zeigen (über ein Interface, eine überschriebene Methode, nicht eindeutige
    /// Überladung, unbekannter Typ, inaktiver Zweig); aus = nur sichere, wie vor #1119.</summary>
    Inferred: Boolean;
    /// <summary>Auch Namen in String-Literalen als erschlossen melden (RTTI, MethodAddress).</summary>
    TextMatches: Boolean;
    class function Default: TReferenceSettings; static;
    /// <summary>Nur sichere Treffer wie vor #1119, für Umbauten, die nur eindeutige Stellen ändern.</summary>
    class function SureOnly: TReferenceSettings; static;
  end;

  /// <summary>Navigation über den Code ("navigation"): Weg zwischen Symbolen (#1117) und Auswirkungsanalyse
  /// (#1120).</summary>
  TNavigationSettings = record
    /// <summary>IDE-Befehl „Weg zwischen Symbolen…“ mit Menü- und Kontextmenüeintrag.</summary>
    SymbolPath: Boolean;
    /// <summary>Befehl „Auswirkungen anzeigen“ im Plugin mit seinen Menüeinträgen.</summary>
    Impact: Boolean;
    /// <summary>Vorgabe der Tiefe der Auswirkungsanalyse in IDE und MCP (1–5).</summary>
    ImpactDepth: Integer;
    class function Default: TNavigationSettings; static;
  end;

  /// <summary>Anzeige von XMLDoc in Hover und Detailpanel des Plugins (#654, #770). Der Server bereitet die Doku
  /// immer vollständig auf und gibt die Werte nur weiter.</summary>
  THintSettings = record
  public const
    MaxXmlDocLines = 50;
    ExpandCollapsed = 'collapsed';
    ExpandLast = 'last';
    ExpandExpanded = 'expanded';
  public
    /// <summary>XMLDoc beim Öffnen (#770): ExpandCollapsed nur Summary mit „Mehr anzeigen“, ExpandLast wie
    /// zuletzt in der Sitzung, ExpandExpanded alle Abschnitte. Ersetzt xmlDocFull aus #654.</summary>
    XmlDocExpand: string;
    /// <summary>Doku-Zeilen, ab denen der Inhalt scrollt; 0 = unbegrenzt.</summary>
    XmlDocMaxLines: Integer;
    /// <summary>Hover über Komponentenklassen (#110): published-Properties und Ereignisse samt geerbter.</summary>
    PublishedMembers: Boolean;
    /// <summary>Begründungen (// WHY: …, #1123) im Hover und in get_declaration.</summary>
    Rationale: Boolean;
    /// <summary>Marken der Begründungen; nil = Vorgabe (TRationale.DefaultMarkers).</summary>
    RationaleMarkers: TArray<string>;
    /// <summary>Ordner der Architekturentscheidungen für ADR-Verweise, relativ zum Projekt; '' = Vorgabe
    /// (TRationale.DefaultAdrFolder).</summary>
    AdrFolder: string;
    class function Default: THintSettings; static;
  end;

  /// <summary>Hilfen in Compiler-Direktiven (#102).</summary>
  TDirectiveSettings = record
    /// <summary>Vervollständigung: Direktivennamen, {$WARN}-Bezeichner und bedingte Symbole mit Herkunft.</summary>
    Completion: Boolean;
    /// <summary>Hover über Schaltern ({$R+}) und Symbolen ({$IFDEF DEBUG}: Zustand und Herkunft).</summary>
    Hover: Boolean;
    class function Default: TDirectiveSettings; static;
  end;

  /// <summary>Hervorheben zusammengehöriger Schlüsselwörter (#307).</summary>
  THighlightSettings = record
    /// <summary>Blockpaare (begin/end, try/finally …) und Routinen.</summary>
    BlockPairs: Boolean;
    /// <summary>Zusammengehörige {$IF…}/{$ELSE}/{$ENDIF} und Regionen.</summary>
    Directives: Boolean;
    /// <summary>Ausstiegspunkte einer Routine und Schleifenziele von Break/Continue.</summary>
    ExitPoints: Boolean;
    /// <summary>Was als Ausstiegspunkt gilt, z. B. Exit, raise, Abort, Halt.</summary>
    ExitKeywords: TArray<string>;
    class function Default: THighlightSettings; static;
  end;

  {$SCOPEDENUMS ON}
  TKeywordCase = (Preserve, Lower, Upper);
  /// <summary>Schlüssel im Block "format", die ausdrücklich gesetzt sind.</summary>
  TFormatKey = (IndentSize, UseTabs, KeywordCase, TrimTrailingWhitespace, InsertFinalNewline,
    SpaceAroundAssignment, SpaceAfterComma, EndOfLine, MaxLineLength);
  /// <summary>Stellung von begin bzw. else (#43): wie vorhanden, in eigener Zeile oder in der Zeile davor.</summary>
  TBlockPlacement = (Preserve, NewLine, SameLine);
  /// <summary>"stringLiteral.style" (#312).</summary>
  TStringLiteralStyle = (Auto, Multiline, Concat);
  /// <summary>"stringLiteral.lineBreak": Trenner zwischen verketteten Zeilen (#312).</summary>
  TStringLiteralBreak = (SLineBreak, CrLf, Lf, Space, None);
  {$SCOPEDENUMS OFF}
  TFormatKeys = set of TFormatKey;

  /// <summary>Klartext als String-Literal (#312).</summary>
  TStringLiteralSettings = record
    Style: TStringLiteralStyle;
    LineBreak: TStringLiteralBreak;
    /// <summary>Bei Verkettung lange Zeilen zusätzlich umbrechen; 0 = nicht umbrechen.</summary>
    MaxLineLength: Integer;
    class function Default: TStringLiteralSettings; static;
  end;

  /// <summary>Klassenmitglieder ordnen (#89).</summary>
  TMemberOrderSettings = record
    /// <summary>Sichtbarkeiten in Zielreihenfolge, z. B. 'strict private', 'private', 'public'.</summary>
    Sections: TArray<string>;
    /// <summary>Arten in Zielreihenfolge: field, constructor, destructor, method, property.</summary>
    Members: TArray<string>;
    /// <summary>Abschnitte mit Feldern dürfen die Reihenfolge der Felder (Speicherlayout) ändern.</summary>
    SortFields: Boolean;
    /// <summary>published-Abschnitte umsortieren (Streaming, Objektinspektor).</summary>
    SortPublished: Boolean;
    class function Default: TMemberOrderSettings; static;
  end;

  /// <summary>Testunits (#274, #189): Namensmuster, Ordner neuer Testunits und Testprojekt.</summary>
  TTestUnitSettings = record
    /// <summary>Name der Testunit; {unit} steht für den Namen der getesteten Unit.</summary>
    Pattern: string;
    /// <summary>Ordner neuer Testunits relativ zur Wurzel; leer = Ordner des Testprojekts.</summary>
    Folder: string;
    /// <summary>Testprojekt (.dproj oder .dpr) relativ zur Wurzel; leer = automatisch erkennen.</summary>
    Project: string;
    class function Default: TTestUnitSettings; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Bedingung einer Eigenschaftsregel für Formulardateien (#309).</summary>
  TDfmCondition = (Equal, NotEqual, Contains, NotContains, Empty, NotEmpty);

  /// <summary>Korrektur: auto gilt als sicher (source.fixAll), prompt nur als Code-Aktion, none gar nicht.</summary>
  TDfmFixMode = (Prompt, Auto, None);
  {$SCOPEDENUMS OFF}

  /// <summary>Eigenschaftsregel aus dfmPropertyRules (#309).</summary>
  TDfmPropertyRule = record
    ClassName: string;
    /// <summary>Property-Pfad, auch Font.Name.</summary>
    PropertyPath: string;
    Condition: TDfmCondition;
    Value: string;
    /// <summary>Meldung; '' = aus Klasse, Property, Bedingung und Wert gebildet.</summary>
    Message: string;
    Severity: TRuleSeverity;
    IncludeDescendants: Boolean;
    Fix: TDfmFixMode;
    /// <summary>Glob-Muster für Dateien, die die Regel nicht prüft.</summary>
    Exclude: TArray<string>;
    /// <summary>Stellen von "class" und "property" in atlas.json für Meldungen mit Index (#309).</summary>
    ClassRange: TTextRange;
    PropertyRange: TTextRange;
  end;

  /// <summary>Formatierung (#43). Given sagt, welche Werte aus atlas.json bzw. dem
  /// Editor stammen; nur die haben Vorrang vor .editorconfig.</summary>
  TFormatStyle = record
    IndentSize: Integer;
    UseTabs: Boolean;
    KeywordCase: TKeywordCase;
    TrimTrailingWhitespace: Boolean;
    InsertFinalNewline: Boolean;
    /// <summary>Genau ein Leerzeichen vor und nach :=.</summary>
    SpaceAroundAssignment: Boolean;
    /// <summary>Genau ein Leerzeichen nach Kommas.</summary>
    SpaceAfterComma: Boolean;
    /// <summary>'' = beibehalten, sonst #10 oder #13#10.</summary>
    EndOfLine: string;
    /// <summary>Einrückung aus der Blockstruktur statt aus der vorhandenen Zeile (#43).</summary>
    Reindent: Boolean;
    /// <summary>begin nach then, else und do (#43).</summary>
    BeginPlacement: TBlockPlacement;
    /// <summary>else nach end (#43).</summary>
    ElsePlacement: TBlockPlacement;
    /// <summary>Längere Zeilen umbrechen (#43); 0 = nie.</summary>
    MaxLineLength: Integer;
    /// <summary>:= untereinander stehender Zuweisungen ausrichten (#43).</summary>
    AlignAssignments: Boolean;
    /// <summary>Typen bzw. = untereinander stehender Deklarationen ausrichten (#43).</summary>
    AlignDeclarations: Boolean;
    /// <summary>Kommentare am Zeilenende untereinander stehender Zeilen ausrichten (#43).</summary>
    AlignComments: Boolean;
    Given: TFormatKeys;
    class function Default: TFormatStyle; static;
  end;

  /// <summary>Weg zum Compiler (#261): auto wählt nach der erkannten Ausgabe, dcc = Kommandozeilen-Compiler,
  /// ide = über eine eigene IDE (cc.ps1), off = nie kompilieren.</summary>
  {$SCOPEDENUMS ON}
  TCompilerBackendSetting = (Auto, Dcc, Ide, Off);
  {$SCOPEDENUMS OFF}

  /// <summary>Compiler-Anbindung (#40, #261).</summary>
  TCompilerSettings = record
    /// <summary>Nach dem Speichern einer Quelldatei im Hintergrund kompilieren; Vorgabe aus, weil das
    /// IDE-Plugin selbst prüfen kann (eine Auswahl „Nach dem Speichern“ in den Delphi-Optionen).
    /// Gilt nur für den Kommandozeilen-Compiler, nie für den Weg über die IDE (#261).</summary>
    OnSave: Boolean;
    /// <summary>compiler.backend (#261); Vorgabe Auto.</summary>
    Backend: TCompilerBackendSetting;
    /// <summary>compiler.ideCommand (#261): Pfad zu cc.ps1 für den Weg über die IDE; '' = nicht eingerichtet.</summary>
    IdeCommand: string;
    class function Default: TCompilerSettings; static;
  end;

  /// <summary>Auswahl der Vervollständigung (#229): unscharf oder nur nach Präfix.</summary>
  TCompletionMatching = (Fuzzy, Prefix);

  /// <summary>Abschnitt, in den „Interface implementieren“ die Deklarationen schreibt (#466).</summary>
  {$SCOPEDENUMS ON}
  TCompletionInterfaceSection = (Private, Protected, Public);
  /// <summary>Typumwandlung von Sender (#480): "(Sender as TButton)" oder "TButton(Sender)".</summary>
  TCompletionSenderCast = (AsOperator, HardCast);
  /// <summary>Freigabe im finally von „Freigabe absichern“ (#489): "List.Free" oder "FreeAndNil(List)".</summary>
  TCompletionFreeStyle = (Free, FreeAndNil);
  /// <summary>Abschnitt der Zugriffsmethoden, die die Vervollständigung nach read/write anlegt (#467).</summary>
  TCompletionAccessorSection = (Private, Protected);
  /// <summary>Typkonvertierung vorschlagen (#490): aus, Helper-Stil (Count.ToString) oder Funktionsstil
  /// (IntToStr(Count)).</summary>
  TCompletionTypeConversion = (Off, Helper, Function_);

  /// <summary>Übernahme einer nicht aktiven gleichnamigen Variante (#475): Unit-Präfix davor oder uses ergänzen
  /// bzw. umstellen.</summary>
  TCompletionSameNameInsert = (Prefix, Uses_);
  {$SCOPEDENUMS OFF}

  TCompletionSettings = record
    Matching: TCompletionMatching;
    InterfaceSection: TCompletionInterfaceSection;
    SenderCast: TCompletionSenderCast;
    /// <summary>Nach Übernahme eines Konstruktors try…finally anbieten (#489).</summary>
    OfferTryFinally: Boolean;
    FreeStyle: TCompletionFreeStyle;
    /// <summary>Schlüsselwörter passend zur Stelle vorschlagen (#31).</summary>
    Keywords: Boolean;
    /// <summary>Postfix-Vorlagen (.for, .notnil …) hinter Ausdrücken anbieten (#188).</summary>
    PostfixTemplates: Boolean;
    /// <summary>Nach "TFoo&lt;" nur Typen, die die Constraints erfüllen, mit Überschrift und Fußzeile (#450).
    /// </summary>
    GenericConstraints: Boolean;
    /// <summary>Namensvorschläge aus dem Typ an Namenspositionen von Deklarationen (#452).</summary>
    NameSuggestions: Boolean;
    /// <summary>Nach read/write einer Eigenschaft Feld, Getter und Setter anlegen (#467).</summary>
    CreateAccessors: Boolean;
    AccessorSection: TCompletionAccessorSection;
    /// <summary>Im String-Literal mit Strg+Leer „Als resourcestring auslagern“ anbieten (#473).</summary>
    ResourceStrings: Boolean;
    /// <summary>Unit für ausgelagerte resourcestrings (interface-Teil); '' = implementation der eigenen Unit.
    /// </summary>
    ResourceStringUnit: string;
    /// <summary>Passt ein Eintrag nicht zum erwarteten Typ, die übliche Umwandlung als weiteren Eintrag (#490).
    /// </summary>
    TypeConversion: TCompletionTypeConversion;
    /// <summary>Hinter "Ausdruck." am Anweisungsanfang „Alle Felder zuweisen (n)“ für Records und Klassen
    /// (#491).</summary>
    AssignAllFields: Boolean;
    /// <summary>Im uses-Abschnitt Gruppen, Hinweise auf den anderen Abschnitt, Zirkelbezüge und Details;
    /// eingebundene Units fehlen (#469). Aus: alle Units des Index als schlichte Liste.</summary>
    UsesDetails: Boolean;
    /// <summary>Nach "inherited " zuerst der vollständige Aufruf der Vorfahrmethode mit den eigenen Parametern,
    /// in Konstruktoren und Destruktoren auch die übrigen; abstrakte fehlen (#482). Aus: nur die Namen.</summary>
    InheritedCall: Boolean;
    /// <summary>Nach "[" vor einer Deklaration nur Attributklassen ohne Endung Attribute, bekannte zuerst, dazu
    /// die Compiler-Attribute (#465). Aus: die gewöhnliche Liste.</summary>
    Attributes: Boolean;
    /// <summary>Erwartet ein Argument oder eine Zuweisung einen Methodenreferenztyp, oben ein Gerüst
    /// "procedure(…) begin end" bzw. "function(…): T" mit passender Signatur (#468). Aus: kein Gerüst.</summary>
    AnonymousMethods: Boolean;
    /// <summary>In with-Blöcken Mitglieder des with-Objekts mit „aus Ausdruck“ und der Warnung „verdeckt Self.Name“
    /// bzw. „verdeckt lokale Variable Name“ (#481). Aus: ohne Herkunft.</summary>
    WithOrigin: Boolean;
    /// <summary>Nach "raise " und "on E: " nur Exception-Klassen; nach raise mit Create('') bzw. CreateFmt, nach on
    /// zuerst die aus dem try-Block (XMLDoc), ohne schon behandelte, mit Warnung bei unerreichbaren Zweigen (#483).
    /// Aus: die gewöhnliche Liste.</summary>
    ExceptionClasses: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457): Steht vor dem Cursor in der aktuellen Routine bzw.
    /// Klassendeklaration ein Syntaxfehler, meldet die Antwort „eingeschränkt“ samt Fehlerzeile (ohne Einträge
    /// „unbekannt“). Aus: kein Hinweis.</summary>
    SyntaxNotice: Boolean;
    /// <summary>Gleichnamige Bezeichner aus verschiedenen Units als Varianten mit ihrer Unit; die vom Compiler
    /// gewählte zuerst mit „aktiv“ (#475). Aus: nur die aktive.</summary>
    SameNameVariants: Boolean;
    SameNameInsert: TCompletionSameNameInsert;
    /// <summary>Varianten aus FireMonkey-Units (FMX.*) zeigen; aus: die Fußzeile nennt sie als ausgeblendet.
    /// </summary>
    ShowFmxUnits: Boolean;
    class function Default: TCompletionSettings; static;
  end;

  /// <summary>Gemeinsame Einstellungen für Code, den Atlas erzeugt (#50, #188).</summary>
  TRefactoringSettings = record
    /// <summary>Inline-Variablen (var X := …) erzeugen, wenn die Sprachversion sie kennt; sonst Eintrag im
    /// var-Abschnitt.</summary>
    InlineVar: Boolean;
    /// <summary>Code-Aktion „Signatur ändern …“ (#100).</summary>
    ChangeSignature: Boolean;
    /// <summary>Neue Parameter: alte Signatur als Überladung behalten (True) oder alle Aufrufer anpassen.</summary>
    NewParameterOverload: Boolean;
    /// <summary>Die Überladung bei virtuellen Methoden ebenfalls virtual machen.</summary>
    VirtualOverload: Boolean;
    /// <summary>Aktionen, die Deklaration und Implementierung angleichen.</summary>
    SyncSignatures: Boolean;
    /// <summary>Forward-Deklarationen prüfen und ergänzen (#685).</summary>
    ForwardDeclaration: Boolean;
    /// <summary>Code-Aktion „try/finally ergänzen“ nach einer Create-Zuweisung (#42).</summary>
    TryFinally: Boolean;
    /// <summary>Klassen-Aktionen: Getter/Setter/Feld, Interface-Methoden, Überschreiben (#42).</summary>
    ClassActions: Boolean;
    /// <summary>Code-Aktion „Typ ausschreiben“ für var X := … ohne Typangabe (#453).</summary>
    ExplicitType: Boolean;
    /// <summary>Schnellkorrekturen an Compilermeldungen, Teil 2 (#549).</summary>
    CompilerFixes: Boolean;
    /// <summary>Code-Aktionen zu „Unit nicht gefunden“ (F2613, F1026): Suchpfad ergänzen (#550).</summary>
    MissingUnit: Boolean;
    /// <summary>Code-Aktionen „Warnung hier abschalten“ auf Compilermeldungen (#531).</summary>
    DisableWarning: Boolean;
    /// <summary>Beim Abschalten einer Warnung nach einer Begründung fragen (#531).</summary>
    DisableWarningReason: Boolean;
    /// <summary>Code-Aktionen „Methode extrahieren“, „Variable einführen“ und „Konstante extrahieren“ (#50).</summary>
    Extract: Boolean;
    /// <summary>Code-Aktion „case vervollständigen“ (#50).</summary>
    CompleteCase: Boolean;
    /// <summary>Code-Aktion „with auflösen“ (#50).</summary>
    ResolveWith: Boolean;
    /// <summary>Code-Aktionen „Variable einbetten“ und „Methode einbetten“ (#103, experimentell).</summary>
    InlineCode: Boolean;
    /// <summary>Code-Aktion „Klasse in eigene Unit verschieben“ (#103, experimentell).</summary>
    MoveClass: Boolean;
    /// <summary>Nach dem Umbenennen einer Unit anbieten, uses und qualifizierte Bezeichner nachzuziehen (#512,
    /// experimentell); "ask" = True, "off" = False.</summary>
    UnitRenameFollowUp: Boolean;
    /// <summary>Methode aus Aufruf anlegen (#472).</summary>
    CreateMethod: Boolean;
    /// <summary>Abschnitt der neuen Methode in der eigenen Unit: private, protected oder public (#472).</summary>
    CreateMethodSection: string;
    /// <summary>Nach dem Anlegen steht der Cursor im Rumpf statt an der Aufrufstelle (#472).</summary>
    CreateMethodCaretInBody: Boolean;
    /// <summary>Erzeugte Parameter für Strings, Records und Interfaces mit const (#472).</summary>
    ConstParameters: Boolean;
    /// <summary>Code-Aktionen „Property X anlegen“ und „Fehlende Properties anlegen“ (#682).</summary>
    PropertyFromAccessors: Boolean;
    /// <summary>Präfixe der Zugriffsmethoden (#682).</summary>
    PropertyFromAccessorsPrefixes: TArray<string>;
    /// <summary>Aufrufe umstellen: ask, always oder never (#682).</summary>
    PropertyFromAccessorsReplaceCalls: string;
    /// <summary>Abschnitt der Property: accessor, public oder published (#682).</summary>
    PropertyFromAccessorsSection: string;
    /// <summary>Zugriffsmethoden verbergen: off, private oder protected (#682).</summary>
    PropertyFromAccessorsHideAccessors: string;
    /// <summary>Im Konstruktor erzeugte, nicht freigegebene Felder melden und im Destruktor freigeben (#666).</summary>
    FreeFields: Boolean;
    /// <summary>Form der Freigabe: free (FFeld.Free) oder freeAndNil (#666).</summary>
    FreeFieldsStyle: string;
    /// <summary>Glühbirne „Als Konstante deklarieren“ für Variablen, die genau einmal zugewiesen und nie geändert
    /// werden (#712); nur, wenn die Sprachversion Inline-Konstanten kennt.</summary>
    SuggestConst: Boolean;
    /// <summary>Code-Aktion „Bedeutung umkehren“ für Boolean-Symbole (#715).</summary>
    InvertBoolean: Boolean;
    /// <summary>Eigene Gegensatzpaare als "A=B", vor den eingebauten (#715).</summary>
    InvertBooleanAntonyms: TArray<string>;
    /// <summary>Präfix, wenn kein Gegensatzpaar passt (#715).</summary>
    InvertBooleanFallbackPrefix: string;
    /// <summary>Published Properties auch in den Formularen umkehren (#715).</summary>
    InvertBooleanIncludeDfm: Boolean;
    /// <summary>Code-Aktionen „In case umwandeln“ und „In if-Kette umwandeln“ (#646).</summary>
    IfCase: Boolean;
    /// <summary>Code-Aktionen zum Umformen von Bedingungen (#656).</summary>
    Conditions: Boolean;
    /// <summary>Code-Aktionen zwischen if-Anweisung und Bedingungsausdruck, IfThen ersetzen (#684).</summary>
    ConditionalExpression: Boolean;
    /// <summary>Code-Aktionen zwischen lokaler Routine und Methode bzw. Routine der Unit (#663).</summary>
    NestedRoutine: Boolean;
    /// <summary>Code-Aktionen zwischen lokaler Variable und Feld (#668).</summary>
    PromoteVariable: Boolean;
    /// <summary>Code-Aktionen zwischen anonymer Methode und Methode (#680).</summary>
    AnonymousMethod: Boolean;
    /// <summary>Später laufende anonyme Methode mit erfassten Variablen: forward (Weiterleitung bleibt) oder fields
    /// (Werte als Felder) (#680).</summary>
    AnonymousMethodDeferredCapture: string;
    /// <summary>Erkennung und Code-Aktionen für Methoden ohne Self (#686): class-Methode, freie Routine,
    /// Record-Helper.</summary>
    MethodKind: Boolean;
    /// <summary>Marke „ohne Self“ am Kopf solcher Methoden (#686); aus = nur über Strg+.</summary>
    MethodKindMarker: Boolean;
    /// <summary>class-Methoden mit static erzeugen (#686).</summary>
    MethodKindStatic: Boolean;
    /// <summary>Code-Aktionen „Typ-Alias einführen“ und „Alias auflösen“ (#681).</summary>
    TypeAlias: Boolean;
    /// <summary>Reichweite der ersten Aktion „Typ-Alias einführen“: here, unit oder project (#681).</summary>
    TypeAliasScope: string;
    /// <summary>Namenstabelle anlegen und Tabellen über Aufzählungen nachziehen (#667).</summary>
    EnumTables: Boolean;
    /// <summary>Texte der Namenstabelle als resourcestring je Element (#667).</summary>
    EnumTablesResourceStrings: Boolean;
    /// <summary>Code-Aktionen „In Inline-Variable umwandeln“, „In var-Block verschieben“ und „var-Block
    /// aufräumen“ (#644).</summary>
    VarBlock: Boolean;
    /// <summary>Beim Aufräumen gleiche Typen zusammenfassen; False trennt sie (#644).</summary>
    VarBlockMerge: Boolean;
    /// <summary>Reihenfolge beim Aufräumen: usage, alpha oder none (#644).</summary>
    VarBlockSort: string;
    /// <summary>Code-Aktion „Interface aus Klasse herauslösen“ (#664).</summary>
    ExtractInterface: Boolean;
    /// <summary>Code-Aktion „Basisklasse herauslösen“ (#713).</summary>
    ExtractSuperclass: Boolean;
    /// <summary>Vorgabe für das Ziel: sameUnit oder newUnit (#713).</summary>
    ExtractSuperclassTarget: string;
    /// <summary>Endung des vorgeschlagenen Namens; Custom als Präfix TCustom… (#713).</summary>
    ExtractSuperclassNameSuffix: string;
    /// <summary>Vorgabe je Methode: move oder abstract (#713).</summary>
    ExtractSuperclassMethodMode: string;
    /// <summary>Sichtbarkeit gehobener private-Mitglieder: protected oder strictProtected (#713).</summary>
    ExtractSuperclassRaiseVisibility: string;
    /// <summary>Code-Aktionen „In Vorfahr/Nachfahren verschieben“ (#675).</summary>
    MoveMember: Boolean;
    /// <summary>Code-Aktion „Zugriffsmethode durch Feld ersetzen“ (#717).</summary>
    InlineAccessor: Boolean;
    /// <summary>Setter mit Gleichheitsprüfung als trivial behandeln (#717).</summary>
    InlineAccessorEqualityCheck: Boolean;
    /// <summary>Sammelaktionen für Unit und Projekt (#717).</summary>
    InlineAccessorBulk: Boolean;
    /// <summary>Hinweis-Diagnose trivial-accessor an trivialen Zugriffsmethoden (#717).</summary>
    InlineAccessorDiagnostic: Boolean;
    /// <summary>„Sicher löschen“ (#716).</summary>
    SafeDelete: Boolean;
    /// <summary>Auch ohne Verwendungen erst die Vorschau zeigen (#716).</summary>
    SafeDeletePreviewWhenUnused: Boolean;
    /// <summary>Freigewordenes mitlöschen: ask, always oder never (#716).</summary>
    SafeDeleteCascade: string;
    /// <summary>Überschreibungen einer virtuellen Methode mitlöschen: ask, always oder never (#716).</summary>
    SafeDeleteIncludeOverrides: string;
    class function Default: TRefactoringSettings; static;
  end;

  TServerSettings = record
    /// <summary>Delphi-Version als BDS-Version der Registry, z. B. "37.0" (Produktnummern wie "12" werden
    /// beim Lesen umgerechnet, siehe BdsVersionOf); '' = passend zur ProjectVersion der .dproj, sonst neueste installierte (#47).</summary>
    DelphiVersion: string;
    /// <summary>Stelle des Werts von "delphiVersion" in der gelesenen Datei, für die Warnung, wenn diese
    /// Version nicht installiert ist (#47); leer ohne Angabe.</summary>
    DelphiVersionRange: TTextRange;
    /// <summary>Älteste Delphi-Version, mit der das Projekt übersetzen muss, als BDS-Version wie DelphiVersion
    /// (#1126); '' = keine. Sprachmerkmale neuerer Versionen meldet die Regel language-feature, und Code-Aktionen
    /// erzeugen sie nicht (TLanguageFeatures.LanguageLevel).</summary>
    MinDelphiVersion: string;
    /// <summary>Sprache der Meldungen, "de" oder "en".</summary>
    Language: string;
    /// <summary>Vorgabe-Codepage für Dateien ohne BOM, wenn die Erkennung nicht entscheidet (#121);
    /// 65001 = UTF-8 (Standard), sonst eine ANSI-Codepage wie 1250.</summary>
    DefaultEncoding: Integer;
    /// <summary>Projektdatei relativ zum Ordner der Konfiguration; '' = automatisch suchen.</summary>
    Project: string;
    Config: string;
    Platform: string;
    Rules: TArray<TRuleSetting>;
    /// <summary>Aktives Regelprofil im Editor, '' = standard (#146).</summary>
    Profile: string;
    /// <summary>Regelprofil der Kommandozeile, '' = wie Profile.</summary>
    CliProfile: string;
    /// <summary>Eigene Profile aus "profiles".</summary>
    Profiles: TArray<TRuleProfile>;
    /// <summary>Pfadregeln aus "overrides"; spätere Einträge haben Vorrang.</summary>
    Overrides: TArray<TPathOverride>;
    /// <summary>Test-Units und Testprojekte (DUnit, DUnitX) nicht prüfen.</summary>
    ExcludeTests: Boolean;
    /// <summary>Regelprofil für Test-Units und Testprojekte, '' = wie Profile.</summary>
    TestProfile: string;
    /// <summary>Treffer unter dieser Konfidenz werden ausgeblendet; Vorgabe Medium.</summary>
    MinConfidence: TRuleConfidence;
    /// <summary>"minConfidence" steht ausdrücklich in der Konfiguration und geht dem Profil vor (#146).</summary>
    MinConfidenceGiven: Boolean;
    /// <summary>Glob-Muster relativ zum Ordner der Konfiguration (*, **, ?).</summary>
    Exclude: TArray<string>;
    /// <summary>MCP-Werkzeuge, die der Server nicht anbietet (mcp.disabledTools, #99).</summary>
    McpDisabledTools: TArray<string>;
    /// <summary>MCP-Modus liest die globale settings.json (mcp.globalSettings, D-08); Vorgabe True.</summary>
    McpGlobalSettings: Boolean;
    /// <summary>Formatierungsstil als JSON-Objekt (Text), sonst ''.</summary>
    Format: string;
    /// <summary>Projektaufgaben (#900) als JSON-Liste (Text), sonst ''. Ausführen tut sie das Plugin; der Server
    /// prüft nur die Datei.</summary>
    Tasks: string;
    /// <summary>Persönliche Tracker-Verbindungen (issues.connections, #1260) als JSON-Liste (Text), sonst ''.
    /// Nutzen tut sie das Plugin; der Server prüft nur die Datei.</summary>
    IssueConnections: string;
    /// <summary>Persönliche Zuordnung Delphi-Projekt → Tracker-Projekt (issues.projects, #1261) als JSON-Liste
    /// (Text), sonst ''. Nutzen tut sie das Plugin; der Server prüft nur die Datei.</summary>
    IssueProjects: string;
    /// <summary>Ausgewerteter Block "format" (#43).</summary>
    Formatting: TFormatStyle;
    InlayHints: TInlayHintSettings;
    CodeLens: TCodeLensSettings;
    References: TReferenceSettings;
    Navigation: TNavigationSettings;
    Hints: THintSettings;
    Directives: TDirectiveSettings;
    Highlight: THighlightSettings;
    Compiler: TCompilerSettings;
    Completion: TCompletionSettings;
    Refactoring: TRefactoringSettings;
    /// <summary>Schnellbefehl "/uses Unit" nach Enter auswerten (#254); false wirkt wie "uses" in
    /// SlashCommandsDisabled.</summary>
    UsesCommand: Boolean;
    /// <summary>Gerüst des Dokumentationskommentars nach dem dritten "/" und die Code-Aktionen dazu
    /// ("completeBlocks.docComment", #88).</summary>
    CompleteBlocksDocComment: Boolean;
    /// <summary>Hauptschalter der experimentellen Funktionen ("experimental.enabled", global, #834). Aus: Die
    /// Schlüssel mit x-experimental fallen schon beim Zusammensetzen der Ebenen weg
    /// (TConfigurationScopes.Effective), es gelten ihre Vorgaben.</summary>
    ExperimentalEnabled: Boolean;
    /// <summary>Kennzahlen überhaupt ("metrics", global): false schaltet die Code Lens der Kennzahlen und
    /// alle Regeln metric-* ab. Eine Regel, die das Projekt unter "rules" ausdrücklich setzt, gilt trotzdem.</summary>
    Metrics: Boolean;
    /// <summary>Schnellbefehle mit "/" überhaupt auswerten (#293).</summary>
    SlashCommands: Boolean;
    /// <summary>Abgeschaltete Schnellbefehle ohne "/", z. B. uses.</summary>
    SlashCommandsDisabled: TArray<string>;
    /// <summary>Vorlage für /header mit {unit}, {jahr}, {autor} (#306); '' = Vorlage der Regel file-header.</summary>
    SlashHeaderTemplate: string;
    /// <summary>Protokollaufruf für /log, /except und /measure (#304): Routinenname oder Vorlage mit {text};
    /// '' = OutputDebugString.</summary>
    SlashLogCall: string;
    /// <summary>Palettenseite für /component (#299).</summary>
    SlashComponentPalette: string;
    /// <summary>Name hinter -o für /todo (#297); '' = git config user.name.</summary>
    SlashTodoOwner: string;
    /// <summary>Kategorie hinter -c für /todo (#297); '' = keine.</summary>
    SlashTodoCategory: string;
    /// <summary>/sortuses streicht ungenutzte Units (#297, #284).</summary>
    SlashSortUsesRemoveUnused: Boolean;
    /// <summary>/helper für Aufzählungen mit cNames, ToString und FromString (#875).</summary>
    SlashEnumHelper: Boolean;
    /// <summary>/helper für Mengen mit Contains, ToText, Toggle und All (#875).</summary>
    SlashSetHelper: Boolean;
    /// <summary>"uses aufräumen" (source.organizeImports) sortiert alphabetisch; Vorgabe aus,
    /// weil die Reihenfolge die Initialisierung bestimmt (#182).</summary>
    SortUses: Boolean;
    /// <summary>Mit SortUses: nach Namespace gruppiert statt rein alphabetisch (#284).</summary>
    SortUsesByNamespace: Boolean;
    /// <summary>Units, die "ungenutzte uses entfernen" nie entfernt (#284).</summary>
    UsesKeep: TArray<string>;
    /// <summary>Toter Code (#64): Attribute (z. B. JsonName) und Namensmuster (z. B. *Handler), deren Elemente als
    /// verwendet gelten (deadCode.keepAttributes, deadCode.keepPatterns); für unused-private-member,
    /// unused-public-member und unused-declaration.</summary>
    DeadCodeKeepAttributes: TArray<string>;
    DeadCodeKeepPatterns: TArray<string>;
    /// <summary>Klartext als String-Literal (#312).</summary>
    StringLiteral: TStringLiteralSettings;
    /// <summary>Klassenmitglieder ordnen (#89).</summary>
    MemberOrder: TMemberOrderSettings;
    /// <summary>Testunits anlegen und wechseln (#274, #189).</summary>
    TestUnits: TTestUnitSettings;
    /// <summary>Eigenschaftsregeln für Formulardateien (#309).</summary>
    DfmPropertyRules: TArray<TDfmPropertyRule>;
    /// <summary>Obergrenze für den Symbolindex in MB; 0 = unbegrenzt (#185).</summary>
    MemoryBudgetMb: Integer;
    /// <summary>Zeitlimit für Anfragen in ms (#283); länger laufende werden abgebrochen.</summary>
    RequestTimeoutMs: Integer;
    /// <summary>Anonymisiertes Diagnoselog (#647): schreiben, Aufbewahrung in Tagen und lokale
    /// Zuordnung Kurz-ID → Name (nur für die eigene Analyse).</summary>
    DiagnosticsLog: Boolean;
    DiagnosticsLogDays: Integer;
    DiagnosticsLogMapFile: Boolean;
    /// <summary>Unit-Zyklen beim Tippen melden (#896, diagnostics.usesCycleLive): uses-cycle in den Diagnosen des
    /// Editors; die projektweite Prüfung (#64) bleibt davon unberührt.</summary>
    DiagnosticsUsesCycleLive: Boolean;
    /// <summary>Im Editor auch Zyklen mit implementation-Kante, als Hinweis (#896,
    /// diagnostics.usesCycleImplementation).</summary>
    DiagnosticsUsesCycleImplementation: Boolean;
    /// <summary>Umfang des Index (#648): alle Projekte der Projektgruppe, alle Units der Projekt-Suchpfade und
    /// der Bibliotheks- und Suchpfade der Installation; False = nur über uses erreichbare (bisher).</summary>
    IndexProjectGroup: Boolean;
    IndexSearchPaths: Boolean;
    IndexLibraryPaths: Boolean;
    /// <summary>Verwendungen der Bezeichner in Projekt-Units mit indizieren (#492, für #470).</summary>
    IndexUsages: Boolean;
    /// <summary>Glob-Muster gegen den vollen Pfad ("/" oder ""), die nicht indiziert werden, z. B. **/Demos/**.</summary>
    IndexExclude: TArray<string>;
    /// <summary>Aufräumen des Cache-Ordners (#905): Caches gelöschter Projekte löschen, Caches nach so vielen
    /// Tagen ohne Benutzung löschen (0 = aus) und Höchstgröße in MB (0 = ohne Grenze).</summary>
    IndexRemoveOrphans: Boolean;
    IndexCacheMaxAgeDays: Integer;
    IndexCacheMaxMb: Integer;
    /// <summary>Architekturübersicht (#1118): Hauptschalter (aus = kein Fenster, kein Bericht, kein
    /// get_architecture), Umfang ("project" oder "projectGroup"), Bibliotheks-Units mitzählen, Länge der Liste
    /// zentraler Units (5..100) und Glob-Muster für Units, die nicht eingehen (Unit-Name oder Pfad relativ zum
    /// Projekt).</summary>
    ArchitectureEnabled: Boolean;
    ArchitectureScope: string;
    ArchitectureIncludeLibraryUnits: Boolean;
    ArchitectureCentralUnits: Integer;
    ArchitectureExclude: TArray<string>;
    /// <summary>Architekturvergleich (#1121): gespeicherter Stand (Pfad relativ zum Projekt, '' = keiner), mit dem
    /// Fenster und Bericht automatisch vergleichen, und die Abweichungen, die --compare als Fehler meldet
    /// (newCycle, newCrossLink, subsystemChange, centralGrowth; Vorgabe newCycle).</summary>
    ArchitectureBaseline: string;
    ArchitectureFailOn: TArray<string>;
    /// <summary>Protokoll (#265): Stufe (debug/info/warning/error), Logdatei und Mitschnitt.
    /// Der Server übernimmt sie nicht zur Laufzeit; der Client übergibt sie beim Start als
    /// --log-level, --log und --trace.</summary>
    LogLevel: string;
    LogFile: string;
    TraceFile: string;
    /// <summary>Versionsverwaltung (vcs.provider, #571): "auto", "git", "svn" oder "off".</summary>
    VcsProvider: string;
    /// <summary>Eigener Pfad zu git bzw. svn (vcs.git.path, vcs.svn.path, #1285); '' = automatisch suchen.</summary>
    VcsGitPath: string;
    VcsSvnPath: string;
    /// <summary>Zeitlimit je Aufruf von git bzw. svn in Sekunden (vcs.timeoutSeconds, #1285, 1–300).</summary>
    VcsTimeoutSeconds: Integer;
    /// <summary>Persönliche Art und Hauptbranch je Delphi-Projekt (vcs.projects, #1286) als JSON-Liste (Text),
    /// sonst ''. Nutzen tut sie das Plugin; der Server prüft nur die Datei.</summary>
    VcsProjects: string;
    /// <summary>True, wenn AFileName unter ein Muster aus IndexExclude fällt.</summary>
    function IsIndexExcluded(const AFileName: string): Boolean;
    /// <summary>Vorgaben, wenn keine Konfigurationsdatei existiert.</summary>
    class function Default: TServerSettings; static;
    /// <summary>Schweregrad aus der Konfiguration oder ADefault.</summary>
    function RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
    /// <summary>True, wenn der Pfad (relativ zum Ordner der Konfiguration, "/" oder "\") ausgeschlossen ist.</summary>
    function IsExcluded(const ARelativePath: string): Boolean;
    /// <summary>True, wenn die Regel in "rules" steht und nicht abgeschaltet ist.</summary>
    function IsRuleEnabledExplicitly(const ARuleId: string): Boolean;
    /// <summary>True für '', eingebaute Profile und Profile aus "profiles".</summary>
    function IsKnownProfile(const AName: string): Boolean;
    /// <summary>Eigenes Profil aus "profiles".</summary>
    function TryFindProfile(const AName: string; out AProfile: TRuleProfile): Boolean;
  end;

  /// <summary>Fehler oder Warnung beim Lesen der Konfiguration, mit Position in der Datei.</summary>
  TConfigurationIssue = record
    Range: TTextRange;
    Message: string;
    IsError: Boolean;
  end;

  TConfigurationChangedEvent = reference to procedure(const ASettings: TServerSettings);

const
  ConfigurationFileName = 'atlas.json';
  /// <summary>Name vor der Umbenennung in Atlas (#403); gilt, solange atlas.json fehlt.</summary>
  LegacyConfigurationFileName = 'delphi-lsp.json';

/// <summary>True für atlas.json und den früheren Namen (ohne Pfad, ohne Groß-/Kleinschreibung).</summary>
function IsConfigurationFileName(const AFileName: string): Boolean;

/// <summary>Pfad von AFileName im Ordner ADirectory. Fehlt die Datei und existiert nur
/// ALegacyFileName, dann dessen Pfad (Abwärtskompatibilität, #403).</summary>
function ExistingOrLegacyFile(const ADirectory, AFileName, ALegacyFileName: string): string;

/// <summary>Glob-Vergleich: * ohne Trenner, ** über Ordner, ? ein Zeichen; ohne Groß-/Kleinschreibung.</summary>
function MatchesGlob(const APattern, APath: string): Boolean;

/// <summary>
/// "delphiVersion" als BDS-Version der Registry: Produktnummern ("10.3", "11", "12", "13")
/// werden umgerechnet ("12" -> "23.0"), BDS-Versionen ab 14 bleiben. '' für ungültige Angaben.
/// </summary>
function BdsVersionOf(const AText: string): string;

implementation

{ TRuleIdAliases }

class function TRuleIdAliases.Current(const AId: string): string;
var
  Index: Integer;
begin
  for Index := Low(FormerIds) to High(FormerIds) do
    if SameText(AId, FormerIds[Index]) then
      Exit(CurrentIds[Index]);
  Result := AId;
end;

function IsConfigurationFileName(const AFileName: string): Boolean;
begin
  Result := SameText(AFileName, ConfigurationFileName) or SameText(AFileName, LegacyConfigurationFileName);
end;

function ExistingOrLegacyFile(const ADirectory, AFileName, ALegacyFileName: string): string;
var
  Legacy: string;
begin
  Result := IncludeTrailingPathDelimiter(ADirectory) + AFileName;
  if FileExists(Result) then
    Exit;
  Legacy := IncludeTrailingPathDelimiter(ADirectory) + ALegacyFileName;
  if FileExists(Legacy) then
    Result := Legacy;
end;

function BdsVersionOf(const AText: string): string;
const
  // Produktnummer -> BDS-Version; 10.x über die Nachkommastelle.
  Products: array[0..7] of array[0..1] of string = (
    ('10', '17.0'), ('10.1', '18.0'), ('10.2', '19.0'), ('10.3', '20.0'), ('10.4', '21.0'),
    ('11', '22.0'), ('12', '23.0'), ('13', '37.0'));
var
  Text: string;
  Value: Double;
  Index: Integer;
begin
  Result := '';
  Text := Trim(AText);
  if not TryStrToFloat(Text, Value, TFormatSettings.Invariant) or (Value <= 0) then
    Exit;
  // BDS-Nummern nur bekannter Versionen: 14.0 (XE6) bis 23.0 (Delphi 12) und 37.0 (Delphi 13).
  // Andere Werte wie "99" sind ein Tippfehler und erzeugen eine Konfigurationswarnung (#109).
  if Value >= 14 then
  begin
    if ((Trunc(Value) >= 14) and (Trunc(Value) <= 23)) or (Trunc(Value) = 37) then
      Result := Text;
    Exit;
  end;
  // "12.0", "12.3" usw. meinen Delphi 12; nur bei 10 zählt die Nachkommastelle.
  if Trunc(Value) <> 10 then
    Text := IntToStr(Trunc(Value))
  else if Pos('.', Text) > 0 then
    Text := '10.' + Copy(Text, Pos('.', Text) + 1, 1);
  if Text = '10.0' then
    Text := '10';
  for Index := Low(Products) to High(Products) do
    if Products[Index][0] = Text then
      Exit(Products[Index][1]);
end;

function NormalizeSlashes(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
  while (Result <> '') and (Result[1] = '/') do
    Delete(Result, 1, 1);
  if Copy(Result, 1, 2) = './' then
    Delete(Result, 1, 2);
end;

function MatchAt(const APattern: string; APatternIndex: Integer; const APath: string; APathIndex: Integer): Boolean;
var
  Index: Integer;
begin
  while APatternIndex <= Length(APattern) do
  begin
    case APattern[APatternIndex] of
      '*':
        begin
          if (APatternIndex < Length(APattern)) and (APattern[APatternIndex + 1] = '*') then
          begin
            // "**/" passt auch auf keinen Ordner.
            Inc(APatternIndex, 2);
            if (APatternIndex <= Length(APattern)) and (APattern[APatternIndex] = '/') then
            begin
              if MatchAt(APattern, APatternIndex + 1, APath, APathIndex) then
                Exit(True);
            end;
            for Index := APathIndex to Length(APath) + 1 do
              if MatchAt(APattern, APatternIndex, APath, Index) then
                Exit(True);
            Exit(False);
          end;
          Inc(APatternIndex);
          for Index := APathIndex to Length(APath) + 1 do
          begin
            if MatchAt(APattern, APatternIndex, APath, Index) then
              Exit(True);
            if (Index <= Length(APath)) and (APath[Index] = '/') then
              Exit(False);
          end;
          Exit(False);
        end;
      '?':
        begin
          if (APathIndex > Length(APath)) or (APath[APathIndex] = '/') then
            Exit(False);
          Inc(APatternIndex);
          Inc(APathIndex);
        end;
    else
      if (APathIndex > Length(APath)) or (APattern[APatternIndex] <> APath[APathIndex]) then
        Exit(False);
      Inc(APatternIndex);
      Inc(APathIndex);
    end;
  end;
  Result := APathIndex > Length(APath);
end;

function MatchesGlob(const APattern, APath: string): Boolean;
var
  Pattern: string;
begin
  Pattern := NormalizeSlashes(APattern);
  // Ein Ordnername ohne Platzhalter schließt alles darunter aus.
  if (Pattern <> '') and (Pattern[Length(Pattern)] = '/') then
    Pattern := Pattern + '**';
  Result := MatchAt(Pattern, 1, NormalizeSlashes(APath), 1) or
    ((Pos('*', Pattern) = 0) and (Pos('?', Pattern) = 0) and MatchAt(Pattern + '/**', 1, NormalizeSlashes(APath), 1));
end;

{ TInlayHintSettings }

class function TInlayHintSettings.Default: TInlayHintSettings;
begin
  Result.ParameterNames := True;
  Result.InferredTypes := True;
  Result.EndMarkers := True;
  Result.EndMarkerMinLines := 20;
  Result.IncludeDefines := True;
  Result.ControlChars := True;
end;

{ TReferenceSettings }

class function TReferenceSettings.Default: TReferenceSettings;
begin
  Result.Inferred := True;
  Result.TextMatches := False;
end;

class function TReferenceSettings.SureOnly: TReferenceSettings;
begin
  Result.Inferred := False;
  Result.TextMatches := False;
end;

{ TNavigationSettings }

class function TNavigationSettings.Default: TNavigationSettings;
begin
  Result.SymbolPath := True;
  Result.Impact := True;
  Result.ImpactDepth := 2;
end;

{ TCodeLensSettings }

class function TCodeLensSettings.Default: TCodeLensSettings;
begin
  Result.Metrics := True;
end;

{ TStringLiteralSettings }

class function TStringLiteralSettings.Default: TStringLiteralSettings;
begin
  Result.Style := TStringLiteralStyle.Auto;
  Result.LineBreak := TStringLiteralBreak.SLineBreak;
  Result.MaxLineLength := 0;
end;

{ TMemberOrderSettings }

class function TMemberOrderSettings.Default: TMemberOrderSettings;
begin
  Result.Sections := ['strict private', 'private', 'strict protected', 'protected', 'public', 'published'];
  Result.Members := ['field', 'constructor', 'destructor', 'method', 'property'];
  Result.SortFields := False;
  Result.SortPublished := False;
end;

{ TTestUnitSettings }

class function TTestUnitSettings.Default: TTestUnitSettings;
begin
  Result.Pattern := '{unit}.Tests';
  Result.Folder := '';
  Result.Project := '';
end;

{ TDirectiveSettings }

class function TDirectiveSettings.Default: TDirectiveSettings;
begin
  Result.Completion := True;
  Result.Hover := True;
end;

{ THintSettings }

class function THintSettings.Default: THintSettings;
begin
  Result.XmlDocExpand := ExpandLast;
  Result.XmlDocMaxLines := 0;
  Result.PublishedMembers := True;
  Result.Rationale := True;
  Result.RationaleMarkers := nil;
  Result.AdrFolder := '';
end;

{ THighlightSettings }

class function THighlightSettings.Default: THighlightSettings;
begin
  Result.BlockPairs := True;
  Result.Directives := True;
  Result.ExitPoints := True;
  Result.ExitKeywords := ['Exit', 'raise', 'Abort', 'Halt'];
end;

{ TFormatStyle }

class function TFormatStyle.Default: TFormatStyle;
begin
  Result.IndentSize := 2;
  Result.UseTabs := False;
  Result.KeywordCase := TKeywordCase.Preserve;
  Result.TrimTrailingWhitespace := True;
  Result.InsertFinalNewline := False;
  Result.SpaceAroundAssignment := True;
  Result.SpaceAfterComma := True;
  Result.EndOfLine := '';
  Result.Reindent := True;
  Result.BeginPlacement := TBlockPlacement.Preserve;
  Result.ElsePlacement := TBlockPlacement.Preserve;
  Result.MaxLineLength := 0;
  Result.AlignAssignments := False;
  Result.AlignDeclarations := False;
  Result.AlignComments := False;
  Result.Given := [];
end;

{ TCompilerSettings }

class function TCompilerSettings.Default: TCompilerSettings;
begin
  Result.OnSave := False;
  Result.Backend := TCompilerBackendSetting.Auto;
  Result.IdeCommand := '';
end;

{ TRefactoringSettings }

class function TRefactoringSettings.Default: TRefactoringSettings;
begin
  Result.InlineVar := True;
  Result.ChangeSignature := True;
  Result.NewParameterOverload := True;
  Result.VirtualOverload := False;
  Result.SyncSignatures := True;
  Result.ForwardDeclaration := True;
  Result.TryFinally := True;
  Result.ClassActions := True;
  Result.ExplicitType := True;
  Result.CompilerFixes := True;
  Result.MissingUnit := True;
  Result.DisableWarning := True;
  Result.DisableWarningReason := True;
  Result.Extract := True;
  Result.CompleteCase := True;
  Result.ResolveWith := True;
  Result.InlineCode := False;
  Result.MoveClass := False;
  Result.UnitRenameFollowUp := False;
  Result.CreateMethod := True;
  Result.CreateMethodSection := 'private';
  Result.CreateMethodCaretInBody := False;
  Result.ConstParameters := True;
  Result.PropertyFromAccessors := True;
  Result.PropertyFromAccessorsPrefixes := ['Get', 'Set', 'Is', 'Has'];
  Result.PropertyFromAccessorsReplaceCalls := 'ask';
  Result.PropertyFromAccessorsSection := 'accessor';
  Result.PropertyFromAccessorsHideAccessors := 'off';
  Result.FreeFields := True;
  Result.FreeFieldsStyle := 'free';
  Result.SuggestConst := False;
  Result.InvertBoolean := True;
  Result.InvertBooleanAntonyms := nil;
  Result.InvertBooleanFallbackPrefix := 'Not';
  Result.InvertBooleanIncludeDfm := True;
  Result.IfCase := True;
  Result.Conditions := True;
  Result.ConditionalExpression := True;
  Result.NestedRoutine := True;
  Result.PromoteVariable := True;
  Result.AnonymousMethod := True;
  Result.AnonymousMethodDeferredCapture := 'forward';
  Result.MethodKind := True;
  Result.MethodKindMarker := True;
  Result.MethodKindStatic := True;
  Result.TypeAlias := True;
  Result.TypeAliasScope := 'unit';
  Result.EnumTables := True;
  Result.EnumTablesResourceStrings := False;
  Result.VarBlock := True;
  Result.VarBlockMerge := True;
  Result.VarBlockSort := 'usage';
  Result.ExtractInterface := True;
  Result.ExtractSuperclass := True;
  Result.ExtractSuperclassTarget := 'sameUnit';
  Result.ExtractSuperclassNameSuffix := 'Base';
  Result.ExtractSuperclassMethodMode := 'move';
  Result.ExtractSuperclassRaiseVisibility := 'protected';
  Result.MoveMember := True;
  Result.InlineAccessor := True;
  Result.InlineAccessorEqualityCheck := True;
  Result.InlineAccessorBulk := True;
  Result.InlineAccessorDiagnostic := False;
  Result.SafeDelete := True;
  Result.SafeDeletePreviewWhenUnused := False;
  Result.SafeDeleteCascade := 'ask';
  Result.SafeDeleteIncludeOverrides := 'ask';
end;

{ TCompletionSettings }

class function TCompletionSettings.Default: TCompletionSettings;
begin
  Result.Matching := TCompletionMatching.Fuzzy;
  Result.InterfaceSection := TCompletionInterfaceSection.Public;
  Result.SenderCast := TCompletionSenderCast.AsOperator;
  Result.OfferTryFinally := True;
  Result.FreeStyle := TCompletionFreeStyle.Free;
  Result.Keywords := True;
  Result.PostfixTemplates := True;
  Result.GenericConstraints := True;
  Result.NameSuggestions := True;
  Result.CreateAccessors := True;
  Result.AccessorSection := TCompletionAccessorSection.Private;
  Result.ResourceStrings := True;
  Result.ResourceStringUnit := '';
  Result.TypeConversion := TCompletionTypeConversion.Off;
  Result.AssignAllFields := False;
  Result.UsesDetails := True;
  Result.InheritedCall := True;
  Result.Attributes := True;
  Result.AnonymousMethods := True;
  Result.WithOrigin := True;
  Result.ExceptionClasses := True;
  Result.SyntaxNotice := True;
  Result.SameNameVariants := True;
  Result.SameNameInsert := TCompletionSameNameInsert.Prefix;
  Result.ShowFmxUnits := False;
end;

{ TServerSettings }

class function TServerSettings.Default: TServerSettings;
begin
  Result.DelphiVersion := '';
  Result.MinDelphiVersion := '';
  Result.Language := 'de';
  Result.DefaultEncoding := 65001;
  Result.Project := '';
  Result.Config := '';
  Result.Platform := '';
  Result.Rules := nil;
  Result.Profile := '';
  Result.CliProfile := '';
  Result.Profiles := nil;
  Result.Overrides := nil;
  Result.ExcludeTests := False;
  Result.TestProfile := '';
  Result.MinConfidenceGiven := False;
  Result.MinConfidence := TRuleConfidence.Medium;
  Result.Exclude := nil;
  Result.Format := '';
  Result.Formatting := TFormatStyle.Default;
  Result.InlayHints := TInlayHintSettings.Default;
  Result.CodeLens := TCodeLensSettings.Default;
  Result.References := TReferenceSettings.Default;
  Result.Navigation := TNavigationSettings.Default;
  Result.Hints := THintSettings.Default;
  Result.Directives := TDirectiveSettings.Default;
  Result.Highlight := THighlightSettings.Default;
  Result.Compiler := TCompilerSettings.Default;
  Result.Completion := TCompletionSettings.Default;
  Result.Refactoring := TRefactoringSettings.Default;
  Result.UsesCommand := True;
  Result.CompleteBlocksDocComment := True;
  Result.ExperimentalEnabled := False;
  Result.Metrics := True;
  Result.SlashCommands := True;
  Result.SlashCommandsDisabled := nil;
  Result.SlashHeaderTemplate := '';
  Result.SlashLogCall := '';
  Result.SlashComponentPalette := 'Eigene';
  Result.SlashTodoOwner := '';
  Result.SlashTodoCategory := '';
  Result.SlashSortUsesRemoveUnused := True;
  Result.SlashEnumHelper := True;
  Result.SlashSetHelper := True;
  Result.SortUses := False;
  Result.SortUsesByNamespace := False;
  Result.UsesKeep := nil;
  Result.DeadCodeKeepAttributes := nil;
  Result.DeadCodeKeepPatterns := nil;
  Result.StringLiteral := TStringLiteralSettings.Default;
  Result.MemberOrder := TMemberOrderSettings.Default;
  Result.TestUnits := TTestUnitSettings.Default;
  Result.DfmPropertyRules := nil;
  // Wie die Vorgabe des Plugins (#492): darüber zuerst Verwendungen auslagern.
  Result.MemoryBudgetMb := 768;
  Result.RequestTimeoutMs := 10000;
  Result.DiagnosticsLog := True;
  Result.DiagnosticsLogDays := 7;
  Result.DiagnosticsLogMapFile := False;
  Result.DiagnosticsUsesCycleLive := True;
  Result.DiagnosticsUsesCycleImplementation := False;
  Result.IndexProjectGroup := True;
  Result.McpGlobalSettings := True;
  Result.IndexSearchPaths := True;
  // Bibliothekspfade ganz zu indizieren dauert bei großen Installationen Minuten; nur auf Wunsch.
  Result.IndexLibraryPaths := False;
  Result.IndexUsages := True;
  Result.IndexExclude := nil;
  Result.IndexRemoveOrphans := True;
  Result.IndexCacheMaxAgeDays := 14;
  Result.IndexCacheMaxMb := 256;
  Result.ArchitectureEnabled := True;
  Result.ArchitectureScope := 'projectGroup';
  Result.ArchitectureIncludeLibraryUnits := False;
  Result.ArchitectureCentralUnits := 15;
  Result.ArchitectureExclude := nil;
  Result.ArchitectureBaseline := '';
  Result.ArchitectureFailOn := ['newCycle'];
  Result.LogLevel := 'info';
  Result.LogFile := '';
  Result.TraceFile := '';
  Result.VcsProvider := 'auto';
  Result.VcsGitPath := '';
  Result.VcsSvnPath := '';
  Result.VcsTimeoutSeconds := 15;
  Result.VcsProjects := '';
end;

function TServerSettings.IsRuleEnabledExplicitly(const ARuleId: string): Boolean;
var
  Rule: TRuleSetting;
begin
  for Rule in Rules do
    if SameText(Rule.Id, ARuleId) then
      Exit(Rule.Severity <> TRuleSeverity.Off);
  Result := False;
end;

function TServerSettings.RuleSeverity(const ARuleId: string; ADefault: TRuleSeverity): TRuleSeverity;
var
  Rule: TRuleSetting;
begin
  for Rule in Rules do
    if SameText(Rule.Id, ARuleId) and (Rule.Severity <> TRuleSeverity.Default) then
      Exit(Rule.Severity);
  Result := ADefault;
end;

function TServerSettings.TryFindProfile(const AName: string; out AProfile: TRuleProfile): Boolean;
var
  Profile: TRuleProfile;
begin
  for Profile in Profiles do
    if SameText(Profile.Name, AName) then
    begin
      AProfile := Profile;
      Exit(True);
    end;
  // Nicht Default(…): innerhalb von TServerSettings träfe das die gleichnamige Klassenfunktion.
  AProfile.Name := '';
  AProfile.Extends := '';
  AProfile.Categories := nil;
  AProfile.Rules := nil;
  Result := False;
end;

function TServerSettings.IsKnownProfile(const AName: string): Boolean;
var
  Name: string;
  Profile: TRuleProfile;
begin
  if AName = '' then
    Exit(True);
  for Name in BuiltinProfileNames do
    if SameText(Name, AName) then
      Exit(True);
  Result := TryFindProfile(AName, Profile);
end;

function TServerSettings.IsIndexExcluded(const AFileName: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in IndexExclude do
    if MatchesGlob(Pattern, AFileName) then
      Exit(True);
  Result := False;
end;

function TServerSettings.IsExcluded(const ARelativePath: string): Boolean;
var
  Pattern: string;
begin
  for Pattern in Exclude do
    if MatchesGlob(Pattern, ARelativePath) then
      Exit(True);
  Result := False;
end;

end.
