unit BDLsp.Common.Rules.Contract;

// Gemeinsame Grundlage aller Prüfregeln: Beschreibung, Kontext einer Prüfung,
// Treffer mit optionalen Korrekturen und die Schnittstelle einer Regel.
// Regeln melden lieber zu wenig als zu viel (Spezifikation, Abschnitt 11).

interface

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Pascal.SyntaxTree;

type
  /// <summary>Feste Angaben einer Regel.</summary>
  TRuleDescriptor = record
    /// <summary>Kennung in Kleinbuchstaben mit Bindestrich, z. B. "empty-except".</summary>
    Id: string;
    /// <summary>Schweregrad ohne Konfiguration; nie Default.</summary>
    DefaultSeverity: TRuleSeverity;
    Description: string;
    constructor Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string);
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
    constructor Create(const ATitle: string; const AEdits: TArray<TRuleEdit>);
  end;

  /// <summary>Ein Treffer einer Regel. Severity setzt die Engine.</summary>
  TRuleFinding = record
    RuleId: string;
    Range: TTextRange;
    Message: string;
    Severity: TRuleSeverity;
    Fixes: TArray<TRuleFix>;
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
  end;

  /// <summary>Sammelt die Treffer einer Regel.</summary>
  IRuleReport = interface
    ['{6E0D7E61-0B7B-4C4A-9C7F-3B0E5B6E2A11}']
    procedure Add(const ARange: TTextRange; const AMessage: string); overload;
    procedure Add(const ARange: TTextRange; const AMessage: string; const AFixes: TArray<TRuleFix>); overload;
  end;

  IRule = interface
    ['{2C4A1F3E-8D5B-4E7A-A1C2-7F9E0B3D4C55}']
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

{ TRuleDescriptor }

constructor TRuleDescriptor.Create(const AId: string; ADefaultSeverity: TRuleSeverity; const ADescription: string);
begin
  Id := AId;
  DefaultSeverity := ADefaultSeverity;
  Description := ADescription;
end;

{ TRuleEdit }

constructor TRuleEdit.Create(const ARange: TTextRange; const ANewText: string);
begin
  Range := ARange;
  NewText := ANewText;
end;

{ TRuleFix }

constructor TRuleFix.Create(const ATitle: string; const AEdits: TArray<TRuleEdit>);
begin
  Title := ATitle;
  Edits := AEdits;
end;

end.
