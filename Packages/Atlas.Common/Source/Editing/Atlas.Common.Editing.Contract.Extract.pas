unit Atlas.Common.Editing.Contract.Extract;

// Schnittstelle von „Methode extrahieren“ (#2054) für andere Teile des Servers: Ein Host-Adapter reicht sie an
// Konsumenten wie die MCP-Werkzeuge (Adapters.Mcp.Extract) und die Korrekturen der Prüfregeln
// (Adapters.Rules.Refactorings) weiter. Erzeugt in Atlas.Common.Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Wünsche an die neue Methode.</summary>
  TEditingExtractWish = record
    /// <summary>Name der neuen Methode; '' = ExtractedMethod.</summary>
    MethodName: string;
    /// <summary>Auch textgleiche Stellen der Unit ersetzen.</summary>
    Duplicates: Boolean;
    /// <summary>Inline-Variablen erzeugen.</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
  end;

  /// <summary>Ergebnis von ExtractMethod.</summary>
  TEditingExtractResult = record
    /// <summary>False: nicht extrahierbar, Grund in Reason.</summary>
    Extracted: Boolean;
    Action: TCodeAction;
    Reason: string;
    /// <summary>Mit Duplicates, aber ohne gleiche Stelle: warum nicht; die Aktion gilt dann nur der Auswahl.</summary>
    DuplicatesReason: string;
  end;

  /// <summary>„Konstante extrahieren“ für viele Literale desselben Textes; der Text wird einmal ausgewertet.
  /// </summary>
  IEditingConstantExtraction = interface
    ['{D859C228-AD67-43C1-BEA0-46AF8B443F91}']
    /// <summary>Konstante für das Literal in ARange, im const-Abschnitt der Routine; False, wenn dort keins
    /// steht.</summary>
    function Run(const ARange: TTextRange; out AAction: TCodeAction): Boolean;
  end;

  IEditingExtract = interface
    ['{9944A273-C19B-4267-8E03-A7FDAF10E407}']
    /// <summary>„Methode extrahieren“ für ARange in AText (ganze Anweisungen).</summary>
    function ExtractMethod(const AText: string; const ARange: TTextRange;
      const AWish: TEditingExtractWish): TEditingExtractResult;
  end;

  /// <summary>Extrahieren an einzelnen Stellen, wie es die Korrekturen der Prüfregeln brauchen.</summary>
  IEditingExtractFixes = interface
    ['{E03588AA-0FC6-476B-85AE-00615841B99E}']
    /// <summary>„Bedingung in Funktion auslagern“ für die ganze Bedingung in ARange (#980); ATree ist der Baum
    /// zu AText, ohne ihn False.</summary>
    function ExtractCondition(const AText: string; const ATree: IPascalSyntaxTree; const ARange: TTextRange;
      const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
    /// <summary>„Konstante extrahieren“ für AText; neue Namen mit den Präfixen ANames (Namensregel);
    /// gilt, solange der Baum hinter ATree lebt; nil ohne Baum.</summary>
    function ConstantExtraction(const AText: string; const ATree: IPascalSyntaxTree;
      const ANames: TPascalNamePrefixes): IEditingConstantExtraction;
  end;

implementation

end.
