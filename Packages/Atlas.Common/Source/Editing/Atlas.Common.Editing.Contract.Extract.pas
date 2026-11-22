unit Atlas.Common.Editing.Contract.Extract;

// Schnittstelle von „Methode extrahieren“ (#2054) für andere Teile des Servers: Ein Host-Adapter reicht sie an
// Konsumenten wie die MCP-Werkzeuge weiter (Adapters.Mcp.Extract). Erzeugt in Atlas.Common.Editing.Composition.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract;

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

  IEditingExtract = interface
    ['{9944A273-C19B-4267-8E03-A7FDAF10E407}']
    /// <summary>„Methode extrahieren“ für ARange in AText (ganze Anweisungen).</summary>
    function ExtractMethod(const AText: string; const ARange: TTextRange;
      const AWish: TEditingExtractWish): TEditingExtractResult;
  end;

implementation

end.
