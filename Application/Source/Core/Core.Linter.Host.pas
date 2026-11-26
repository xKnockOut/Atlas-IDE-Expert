unit Core.Linter.Host;

// Host-Rolle Core: was der Linter-Modus (--check und verwandte Befehle) von außen braucht, als Host-Core aber nicht
// selbst erzeugt (Konzept 8.1): installierte Delphi-Versionen, Zugriff auf git und svn, die Gruppe der Arbeitsbereiche
// samt Dokumenten und Protokoll sowie das Schreiben der Anweisungsdateien. Die Shell setzt es zusammen (TLinterShell).

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Checks.Contract,
  Atlas.Common.Formatting.Outcome,
  Core.VersionControlChanges,
  Core.WorkspaceGroup;

type
  /// <summary>Gruppe der Arbeitsbereiche über AConfigRoot, die in AIndex indiziert.</summary>
  TCoreLinterGroupFactory = reference to function(const AConfigRoot: string; const AIndex: ISymbolIndex):
    TCoreWorkspaceGroup;

{$SCOPEDENUMS ON}
  /// <summary>Stand des Atlas-Abschnitts in einer Anweisungsdatei.</summary>
  TCoreInstructionsState = (Current, Stale, Missing);
{$SCOPEDENUMS OFF}

  /// <summary>Ergebnis je Anweisungsdatei.</summary>
  TCoreInstructionsFile = record
    /// <summary>Wie in atlas.json angegeben.</summary>
    FileName: string;
    State: TCoreInstructionsState;
    Written: Boolean;
    /// <summary>Grund, wenn Schreiben scheiterte; sonst ''.</summary>
    Error: string;
  end;

  /// <summary>Anweisungsdateien für KI-Assistenten unter ARoot prüfen bzw. mit AWrite schreiben (#2615).</summary>
  TCoreLinterInstructions = reference to function(const ARoot: string; const ASettings: TServerSettings;
    AWrite: Boolean): TArray<TCoreInstructionsFile>;

  /// <summary>Prüft AText (Datei ARelativePath) mit Projekt und Symbolen; AScopes für die Baseline.</summary>
  TCoreLinterCheckText = reference to function(const ASettings: TServerSettings; const ARelativePath, AText: string;
    const AProject: TCheckProject; const ASource: TPascalSource; out AScopes: TFindingScopes): TArray<TRuleFinding>;

  /// <summary>Prüfung mit den Regeln für die Durchgänge von --fix mit den Kennungen AFixRules ("all" bzw. eine
  /// Kennung, die nur im Checker oder in der Engine entsteht: alle).</summary>
  TCoreLinterFixCheck = reference to function(const AFixRules: TArray<string>): TCoreLinterCheckText;

  /// <summary>Beschreibung aller Regeln für SARIF und den Standard-Schweregrad: syntax, Sprachstand, die
  /// eingebauten Regeln und mit AWithIndex die gespeicherten Abfragen mit failIfAny aus ASettings (#1351) als Regeln
  /// query:&lt;name&gt;.</summary>
  TCoreLinterRuleInfos = reference to function(const ASettings: TServerSettings; AWithIndex: Boolean):
    TArray<TFindingRuleInfo>;

  /// <summary>Die eingebauten Prüfregeln für --check und --fix.</summary>
  TCoreLinterRules = record
    /// <summary>Prüfung mit allen Regeln.</summary>
    CheckAll: TCoreLinterCheckText;
    FixCheck: TCoreLinterFixCheck;
    /// <summary>Kennungen (klein) der Regeln mit sicherer Korrektur im Katalog.</summary>
    SafeFixRules: TFunc<TArray<string>>;
    Infos: TCoreLinterRuleInfos;
  end;

  /// <summary>Formatiert AScope von AText nach AStyle wie „Dokument formatieren“, prüft vorher mit Datei und Symbolen
  /// aus ASource auf Syntaxfehler und beschreibt die Abweichungen (--format-check, --format-write).</summary>
  TCoreLinterFormat = reference to function(const AText: string; const AStyle: TFormatStyle;
    const AScope: TFormatScope; const ASource: TPascalSource): TFormatOutcome;

  TCoreLinterHost = record
    /// <summary>Installierte Delphi-Versionen (BDS-Nummern).</summary>
    InstalledVersions: TFunc<TArray<string>>;
    /// <summary>Neuer Zugriff auf git und svn für die Kommandozeile.</summary>
    Vcs: TFunc<TCoreVcsAccess>;
    NewGroup: TCoreLinterGroupFactory;
    Instructions: TCoreLinterInstructions;
    Rules: TCoreLinterRules;
    Formatter: TCoreLinterFormat;
  end;

implementation

end.
