unit Rules.Contract.Api;

// API des Features Rules: was die Prüfregeln anderen Features anbieten. Sprachserver und MCP erreichen sie nur über
// Host-Adapter (Application/Source/Adapters), die ihre eigenen SPIs auf diese Schnittstellen abbilden; erzeugt
// werden Anbieter und Adapter in Shell.Composition.*. Argumente und Ergebnisse sind reine Werte aus den Contracts
// der Platform-Features.

interface

uses
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Findings.Contract;

type
  /// <summary>Vererbungstiefe der Klassen einer Datei wie bei der Regel metric-inheritance-depth (#980).</summary>
  IRuleInheritanceDepths = interface
    ['{7DE19472-351A-436A-B2C6-4E61D0ADEA80}']
    /// <summary>Je Klasse mit eigenen Vorfahren ein Eintrag (Kind InheritanceDepth): Vorfahren aus der Datei und
    /// AIndex (nil = nur die Datei) ohne RTL, VCL und Bibliotheken; AtLeast, wenn die Kette an einem unbekannten
    /// Vorfahren abbricht. Leer für Units der Bibliothek selbst.</summary>
    function Depths(const AFileName, AText: string; const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
  end;

  /// <summary>Antwort von atlas.server.ownership (#1877): „Wer gibt das frei?“ für jede Erzeugung T.Create(…)
  /// einer Unit; „nie freigegeben“ nur, wo die Leck-Regeln mit den Einstellungen der Datei einen Befund melden.
  /// </summary>
  IRuleOwnershipReport = interface
    ['{7E7144B8-F6F0-4748-B194-BB15BE867A7D}']
    /// <summary>{ uri, sites: [...] } zu AUri; sites leer, wenn die Datei weder geöffnet noch lesbar ist. Der
    /// Aufrufer übernimmt das Objekt.</summary>
    function Report(const AUri: string): TJSONObject;
  end;

  /// <summary>Angaben des Regelkatalogs zu einer Regel für Anzeigen (Fenster „Atlas-Prüfung“, Befund-Hover, #909).
  /// </summary>
  TRuleCatalogFacts = record
    /// <summary>Name der Kategorie.</summary>
    Category: string;
    /// <summary>Name der Gruppe, z. B. „Compiler vorab“ (#1024).</summary>
    Group: string;
    /// <summary>Compilermeldungen, die die Regel vorwegnimmt (#1024); leer ohne.</summary>
    CompilerCodes: TArray<string>;
  end;

  /// <summary>Regelkatalog für Anzeigen in anderen Features: Kennungen, Angaben je Regel, Hilfeseite.</summary>
  IRuleCatalogInfo = interface
    ['{2F7D9A31-6C4B-4E8A-B1D5-93E0C7A2F468}']
    /// <summary>Kennungen aller eingebauten Regeln, z. B. für /ignore (#293).</summary>
    function RuleIds: TArray<string>;
    /// <summary>Angaben zu ARuleId; False, wenn der Katalog die Regel nicht kennt.</summary>
    function TryDescribe(const ARuleId: string; out AFacts: TRuleCatalogFacts): Boolean;
    /// <summary>Hilfeseite zu ARuleId.</summary>
    function HelpUri(const ARuleId: string): string;
    /// <summary>Zeigt der Editor AFinding durchgestrichen (veraltetes Symbol, #38; nicht platform, library oder
    /// experimental, #1018)?</summary>
    function StruckThrough(const AFinding: TRuleFinding): Boolean;
  end;

  /// <summary>Regelkatalog zum Nachschlagen (search_atlas_docs, explain_compiler_message): alle eingebauten Regeln mit
  /// Texten in einer Sprache und ihr Zustand unter den Einstellungen eines Projekts.</summary>
  IRuleDocs = interface
    ['{9C134A43-846E-4416-8F87-EF2C24F33E2C}']
    /// <summary>Alle Regeln des Katalogs; Name, Beschreibung und Beispiele in der Sprache ALanguage ("de" oder
    /// "en" wie TAtlasLocale.Code; sonst englisch).</summary>
    function Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
    /// <summary>Wirksamer Schweregrad von ARuleId unter ASettings, woher er kommt, und die Optionen aus ASettings;
    /// eine unbekannte Regel gilt mit Schweregrad Default.</summary>
    function State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
  end;

  /// <summary>Prüfregeln für ein Dokument der Diagnose im Editor; das Umfeld (Regeln, Einstellungen, Baseline)
  /// hat der Anbieter für die Datei gebaut.</summary>
  IRuleDocumentCheck = interface
    ['{421C24F9-0C96-40DD-B81F-06396A2BA5EF}']
    /// <summary>Syntaxfehler im Baum von ADocument unter ADefines (gemeinsamer Zwischenspeicher, #845) als Treffer
    /// der Regel syntax (#1022): Schweregrad und Gruppe aus der Konfiguration, ohne Umfeld Fehler.</summary>
    function SyntaxFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    /// <summary>Sprachmerkmale, die ADelphiVersion noch nicht kennt, als Treffer der Regel language-feature
    /// (#109, #1126); nicht in AInactive.</summary>
    function LanguageFeatureFindings(const ADocument: ITextDocument; const ADefines: TArray<string>;
      const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
    /// <summary>Treffer der Prüfregeln ohne die bekannten der Baseline (#97), über den gemeinsamen Speicher der
    /// Treffer; leer ohne Regeln. Abbruch zwischen den Regeln mit ERuleCheckCancelled.</summary>
    function RuleFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    /// <summary>Zeigt der Editor ungenutzte uses (Regel unused-uses, #1135)? Ohne Umfeld ja.</summary>
    function UnusedUsesShown: Boolean;
    /// <summary>Zeigt der Editor „nur in der implementation gebraucht“ (uses-only-in-implementation, #1136)? Ohne
    /// Umfeld ja.</summary>
    function OnlyImplementationShown: Boolean;
    /// <summary>Regelkatalog für die Anzeige der Treffer (Hilfeseite, Kategorie, Gruppe); nil ohne.</summary>
    function Catalog: IRuleCatalogInfo;
  end;

  /// <summary>Prüfregeln der Diagnose je Dokument.</summary>
  IRuleDocumentChecks = interface
    ['{CEAD1EB5-00AF-46A9-973C-91E0B29E7E54}']
    /// <summary>Prüfung für AUri; ACancelled (nil = nie) bricht zwischen den Regeln ab. Nie nil: ohne Umfeld
    /// gelten die Vorgaben, und es laufen keine Regeln.</summary>
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentCheck;
  end;

  /// <summary>Prüfregeln eines Dokuments für die Code-Aktionen (Glühbirne, source.fixAll, #42, #182); das Umfeld
  /// hat der Anbieter für die Datei gebaut. Der Baum ist der gemeinsame der Datei (TSyntaxTreeCache.Get).</summary>
  IRuleDocumentActions = interface
    ['{5C0F2B8E-3D41-4F6A-9B7E-2A8D6C1E4F93}']
    /// <summary>Syntaxfehler des Baums von ADocument mit ihrer Korrektur (#1022); ohne Umfeld mit den Vorgaben.
    /// </summary>
    function SyntaxFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    /// <summary>Treffer der Prüfregeln aus dem gemeinsamen Speicher, sonst selbst gerechnet und abgelegt; leer ohne
    /// Regeln. Das Warten auf einen fremden Lauf endet mit ERuleCheckCancelled.</summary>
    function SharedRuleFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    /// <summary>Treffer der Prüfregeln nur aus dem gemeinsamen Speicher (abgelegt oder laufender Lauf am selben
    /// Text), ohne eigenen Lauf; False ohne beides. Ohne Regeln True und leer.</summary>
    function CachedRuleFindings(const ADocument: ITextDocument; out AFindings: TArray<TRuleFinding>): Boolean;
    /// <summary>Korrekturen und Unterdrückungen zu den Treffern in ARange; mit ATryFinally auch try/finally um
    /// Create-Zuweisungen der Startzeile im Formatstil AStyle.</summary>
    function Fixes(const AFindings: TArray<TRuleFinding>; const ADocument: ITextDocument; const ARange: TTextRange;
      const AStyle: TFormatStyle; ATryFinally: Boolean): TArray<TCodeAction>;
    /// <summary>Alle sicheren Korrekturen in einer Aktion; False ohne sichere Korrektur.</summary>
    function FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
    /// <summary>Befund als Auftrag für KI-Assistenten (#158, #2570), derselbe Text wie in explain_finding.</summary>
    function Prompt(const AFinding: TRuleFinding; const AFileName, AText: string): string;
    /// <summary>Index des Umfelds; nil ohne.</summary>
    function Index: ISymbolIndex;
  end;

  /// <summary>Prüfregeln der Code-Aktionen je Dokument.</summary>
  IRuleCodeActions = interface
    ['{B6E1A47D-90C2-4E35-8F1B-7D3A2C5E9046}']
    /// <summary>Aktionen für AUri; ACancelled (nil = nie) beendet das Warten auf einen fremden Lauf. Nie nil: ohne
    /// Umfeld gelten die Vorgaben, und es laufen keine Regeln.</summary>
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentActions;
  end;

  /// <summary>Eine Datei für die Sammelkorrektur (#1352).</summary>
  TRuleBulkFixInput = record
    /// <summary>Absoluter Pfad; daraus Projekt und Symbole der Datei.</summary>
    FileName: string;
    /// <summary>Pfad relativ zum Arbeitsordner wie bei der Prüfung (Ausschlüsse, Baseline) und im Diff.</summary>
    RelativePath: string;
    Text: string;
  end;

  /// <summary>Angewendete Korrekturen einer Regel in einer Datei.</summary>
  TRuleBulkFixCount = record
    RuleId: string;
    Count: Integer;
  end;

  /// <summary>Ergebnis der Sammelkorrektur für eine Datei.</summary>
  TRuleBulkFixOutput = record
    FileName: string;
    OldText: string;
    /// <summary>Text nach den Korrekturen; gleich OldText, wenn nichts geändert oder verworfen wurde.</summary>
    NewText: string;
    /// <summary>Text geändert und nicht verworfen.</summary>
    Changed: Boolean;
    /// <summary>Verworfen, weil neue Syntaxfehler entstanden wären; NewText = OldText.</summary>
    Rejected: Boolean;
    /// <summary>Anzahl der angewendeten Korrekturen.</summary>
    FixCount: Integer;
    /// <summary>Korrekturen je Regel in der Reihenfolge des ersten Auftretens.</summary>
    Applied: TArray<TRuleBulkFixCount>;
    /// <summary>Vereinigter Diff mit RelativePath (/ als Trenner); leer ohne Änderung.</summary>
    Diff: string;
  end;

  TRuleBulkFixRun = record
    Files: TArray<TRuleBulkFixOutput>;
    /// <summary>Zusammenfassung (Dateien, Korrekturen je Regel, übersprungene Treffer, verworfene Dateien) als
    /// Vorschau, Zeilen mit sLineBreak.</summary>
    PreviewSummary: string;
    /// <summary>Dieselbe Zusammenfassung nach dem Schreiben.</summary>
    WrittenSummary: string;
  end;

  /// <summary>Sammelkorrektur (#1352, fix_findings): die sicheren Korrekturen ausgewählter Regeln auf ganze Dateien;
  /// schreibt nichts. Regeln, Projekt und Symbole der Dateien hat der Anbieter.</summary>
  IRuleBulkFix = interface
    ['{1365E479-94DA-4A69-A2B7-C322663650D7}']
    /// <summary>Korrigiert AFiles mit den Regeln AFixRules ("all" = alle) ab der Konfidenz AMinConfidence ("medium",
    /// "high"; '' = fix.minConfidence aus ASettings, nur anheben). False mit Grund in AError bei ungültigem
    /// AMinConfidence.</summary>
    function Run(const AFiles: TArray<TRuleBulkFixInput>; const AFixRules: TArray<string>;
      const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TRuleBulkFixRun;
      out AError: string): Boolean;
  end;

  /// <summary>Sammelkorrektur über Dateien des Arbeitsbereichs (#1352, atlas.server.fixFindings): Text,
  /// Regeln, Einstellungen, Projekt und Baseline (#97) je Datei wie bei der Prüfung im Editor; schreibt nichts.
  /// </summary>
  IRuleWorkspaceBulkFix = interface
    ['{252AD7D1-91BB-4E13-A999-2902E620923A}']
    /// <summary>Korrigiert AFileNames wie IRuleBulkFix.Run; Untergrenze je Datei aus deren fix.minConfidence.
    /// Dateien ohne Text oder ohne Umfeld fehlen im Ergebnis.</summary>
    function Run(const AFileNames: TArray<string>; const AFixRules: TArray<string>; const AMinConfidence: string;
      out ARun: TRuleBulkFixRun; out AError: string): Boolean;
  end;

  /// <summary>Regeln für ungenutzten Code (#64, find_unused_code) über die Dateien eines Laufs; Regeln, Index,
  /// Projekte und Namensräume hat der Anbieter beim Anlegen bekommen.</summary>
  IRuleDeadCode = interface
    ['{C8069B2F-F025-4B08-9E7E-A6DE46C195C6}']
    /// <summary>Kennungen der Regeln für ungenutzten Code in der Reihenfolge des Berichts.</summary>
    function RuleIds: TArray<string>;
    /// <summary>Gibt es unter den Regeln des Anbieters welche für ungenutzten Code?</summary>
    function Available: Boolean;
    /// <summary>Alle Projekte geladen und indiziert? Sonst Grund in AReason; die projektweiten Regeln schweigen.
    /// </summary>
    function Complete(out AReason: string): Boolean;
    /// <summary>Text von AFileName, geöffnete Dokumente zuerst; False, wenn nicht lesbar.</summary>
    function ReadText(const AFileName: string; out AText: string): Boolean;
    /// <summary>Treffer der Regeln für ungenutzten Code in AText, dem Inhalt von AFileName; ARelativePath für
    /// Regeln, Optionen und deadCode.keep* aus ASettings.</summary>
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

  /// <summary>Prüfregeln über einen Text, etwa für get_diagnostics, hook_check, check_code und explain_finding:
  /// Syntaxfehler, Sprachmerkmale und die Treffer der Regeln. Regeln, Projekt (Symbolindex, Projektdienste, #1112)
  /// und Symbole samt Include-Dateien (#860) je Datei hat der Anbieter.</summary>
  IRuleTextChecks = interface
    ['{CDB52403-25B0-43A2-A3F4-9B097D36A81D}']
    /// <summary>Treffer in AText, dem Inhalt von AFileName (absoluter Pfad); ARelativePath (relativ zum
    /// Arbeitsordner) für Regeln, overrides und Ausschlüsse aus ASettings.</summary>
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
    /// <summary>Korrekturen und Unterdrückungen der Treffer in ARange samt try/finally um Create-Zuweisungen der
    /// Startzeile (#42), geprüft wie Check.</summary>
    function Actions(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings;
      const ARange: TTextRange): TArray<TCodeAction>;
  end;

  /// <summary>Projektkonventionen (#272) für Assistenten: Regelprofil, Formatstil, Benennungsregeln und aktive
  /// Prüfregeln als Markdown; die Regeln hat der Anbieter.</summary>
  IRuleConventions = interface
    ['{96DA34FA-2B2E-4949-9785-AC67FF766D65}']
    /// <summary>Konventionen nach den Einstellungen ASettings.</summary>
    function Markdown(const ASettings: TServerSettings): string;
  end;

  /// <summary>Aufträge an Assistenten als Markdown: zu einem Befund (#158, explain_finding) mit Regel, Beschreibung,
  /// Vorher/Nachher und Ausschnitt, oder aus mehreren Befunden (#2570).</summary>
  IRuleFindingPrompts = interface
    ['{311A7027-B860-4D22-8BD7-36EA64E58AE1}']
    /// <summary>Markdown zu AFinding in AText (Datei AFileName), deutscher Katalog.</summary>
    function MarkdownOf(const AFinding: TRuleFinding; const AFileName, AText: string): string;
    /// <summary>Markdown zu AItems mit dem Regelkatalog in der Sprache der Texte; über ALimit Befunden ein Hinweis
    /// auf check_code.</summary>
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    /// <summary>Höchstzahl Befunde eines Auftrags, wenn der Aufrufer keine nennt.</summary>
    function DefaultLimit: Integer;
  end;

implementation

end.
