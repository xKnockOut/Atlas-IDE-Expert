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
  end;

  /// <summary>Prüfregeln der Diagnose je Dokument.</summary>
  IRuleDocumentChecks = interface
    ['{CEAD1EB5-00AF-46A9-973C-91E0B29E7E54}']
    /// <summary>Prüfung für AUri; ACancelled (nil = nie) bricht zwischen den Regeln ab. Nie nil: ohne Umfeld
    /// gelten die Vorgaben, und es laufen keine Regeln.</summary>
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentCheck;
  end;

implementation

end.
