unit Atlas.Common.Rules.Contract.Api;

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

  /// <summary>Auftrag an einen KI-Assistenten aus mehreren Befunden (#2570) wie bei explain_finding.</summary>
  IRuleFindingPrompts = interface
    ['{43854D46-1F10-4A72-99AD-3DD884310EA6}']
    /// <summary>Markdown zu AItems mit dem Regelkatalog in der Sprache der Texte; über ALimit Befunden ein Hinweis
    /// auf check_code.</summary>
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    /// <summary>Höchstzahl Befunde eines Auftrags, wenn der Aufrufer keine nennt.</summary>
    function DefaultLimit: Integer;
  end;

implementation

end.
