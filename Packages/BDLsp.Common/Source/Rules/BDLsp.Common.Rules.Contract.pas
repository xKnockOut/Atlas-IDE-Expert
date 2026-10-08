unit BDLsp.Common.Rules.Contract;

// Gemeinsame Grundlage aller Prüfregeln: Beschreibung, Kontext einer Prüfung,
// Treffer mit optionalen Korrekturen und die Schnittstelle einer Regel.
// Regeln melden lieber zu wenig als zu viel (Spezifikation, Abschnitt 11).
// Jeder Treffer trägt eine Konfidenz; sie begrenzt den Schweregrad (#144).

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

type
  /// <summary>Feste Angaben einer Regel.</summary>
  TRuleDescriptor = record
    /// <summary>Kennung in Kleinbuchstaben mit Bindestrich, z. B. "empty-except".</summary>
    Id: string;
    /// <summary>Schweregrad ohne Konfiguration; nie Default.</summary>
    DefaultSeverity: TRuleSeverity;
    Description: string;
    /// <summary>
    /// Ohne gemessene Fehlalarmquote: läuft nur, wenn die Regel in
    /// delphi-lsp.json unter "rules" eingeschaltet ist.
    /// </summary>
    Experimental: Boolean;
    constructor Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string;
      AExperimental: Boolean = False);
  end;

  /// <summary>Eine Textersetzung einer Korrektur.</summary>
  TRuleEdit = record
    Range: TTextRange;
    NewText: string;
    constructor Create(const ARange: TTextRange; const ANewText: string);
  end;

  /// <summary>Code-Aktion zu einem Treffer.</summary>
  TRuleFix = record
    Title: string;
    Edits: TArray<TRuleEdit>;
    /// <summary>Sicher ohne Rückfrage anwendbar, z. B. beim Speichern über source.fixAll (#182).
    /// Jede Regel entscheidet das für ihre Korrekturen selbst.</summary>
    Safe: Boolean;
    /// <summary>Eine von mehreren gleichwertigen Korrekturen (#125): keine wird als bevorzugt angeboten.</summary>
    Alternative: Boolean;
    constructor Create(const ATitle: string; const AEdits: TArray<TRuleEdit>; ASafe: Boolean = False);
  end;

  /// <summary>Ein Treffer einer Regel. Severity setzt die Engine.</summary>
  TRuleFinding = record
    RuleId: string;
    Range: TTextRange;
    Message: string;
    Severity: TRuleSeverity;
    Confidence: TRuleConfidence;
    Fixes: TArray<TRuleFix>;
    /// <summary>Meldung mit Konfidenz-Zusatz unterhalb von High, für Hover und Kommandozeile.</summary>
    function DisplayMessage: string;
  end;

  /// <summary>Alles, was eine Regel über die geprüfte Datei wissen darf.</summary>
  TRuleContext = record
    /// <summary>Pfad relativ zum Ordner der Konfiguration, '' wenn unbekannt.</summary>
    RelativePath: string;
    UnitName: string;
    Text: string;
    /// <summary>Syntaxbaum des Textes; gehört dem Aufrufer.</summary>
    Tree: TSyntaxTree;
    /// <summary>Optionen der Regel aus delphi-lsp.json als JSON-Text, sonst ''.</summary>
    Options: string;
    /// <summary>Symbolindex für Vorfahren aus anderen Units (#125); nil ohne Index (z. B. Linter).
    /// Regeln treffen dann keine Aussage, die ihn bräuchte.</summary>
    Index: ISymbolIndex;
    /// <summary>Inhalt der Formulardatei (.dfm/.fmx) neben der Unit (#123); '' ohne.</summary>
    FormText: string;
  end;

  /// <summary>Sammelt die Treffer einer Regel.</summary>
  /// <summary>Sammelt die Treffer einer Regel. Ohne Angabe gilt Konfidenz High.</summary>
  IRuleReport = interface
    ['{6E0D7E61-0B7B-4C4A-9C7F-3B0E5B6E2A11}']
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; AConfidence: TRuleConfidence;
      const AFixes: TArray<TRuleFix>); overload;
  end;

  IRule = interface
    ['{2C4A1F3E-8D5B-4E7A-A1C2-7F9E0B3D4C55}']
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Kennwort der Konfidenz: "hoch", "mittel", "niedrig".</summary>
function ConfidenceText(AConfidence: TRuleConfidence): string;

implementation

function ConfidenceText(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'niedrig';
    TRuleConfidence.Medium:
      Result := 'mittel';
  else
    Result := 'hoch';
  end;
end;

{ TRuleDescriptor }

constructor TRuleDescriptor.Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string;
  AExperimental: Boolean);
begin
  Id := AId;
  DefaultSeverity := ADefaultSeverity;
  Description := ADescription;
  Experimental := AExperimental;
end;

{ TRuleFinding }

function TRuleFinding.DisplayMessage: string;
begin
  if Confidence = TRuleConfidence.High then
    Result := Message
  else
    Result := Message + ' (Konfidenz: ' + ConfidenceText(Confidence) + ')';
end;

{ TRuleEdit }

constructor TRuleEdit.Create(const ARange: TTextRange; const ANewText: string);
begin
  Range := ARange;
  NewText := ANewText;
end;

{ TRuleFix }

constructor TRuleFix.Create(const ATitle: string; const AEdits: TArray<TRuleEdit>; ASafe: Boolean);
begin
  Title := ATitle;
  Edits := AEdits;
  Safe := ASafe;
  Alternative := False;
end;

end.
