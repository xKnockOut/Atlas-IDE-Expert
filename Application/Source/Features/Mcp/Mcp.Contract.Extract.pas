unit Mcp.Contract.Extract;

// Was das Werkzeug extract_method (#2054) vom Server braucht: „Methode extrahieren“ auf einem Text. Der Host
// verbindet es mit Editing (Adapters.Mcp.Extract); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract;

type
  /// <summary>Wünsche an die neue Methode.</summary>
  TMcpExtractWish = record
    /// <summary>Name der neuen Methode; '' = ExtractedMethod.</summary>
    MethodName: string;
    /// <summary>Auch textgleiche Stellen der Unit ersetzen (replaceDuplicates).</summary>
    Duplicates: Boolean;
    InlineVar: Boolean;
    Style: TFormatStyle;
  end;

  /// <summary>Geplante Extraktion.</summary>
  TMcpExtractPlan = record
    /// <summary>False: nicht extrahierbar, Grund in Reason.</summary>
    Extracted: Boolean;
    Action: TCodeAction;
    Reason: string;
    /// <summary>Gleiche Stellen gewünscht, aber keine gefunden: warum nicht.</summary>
    DuplicatesReason: string;
  end;

  IMcpExtract = interface
    ['{802E09F6-7BF8-4EEF-84FD-2D85F6568554}']
    /// <summary>Plant „Methode extrahieren“ für ARange in AText.</summary>
    function ExtractMethod(const AText: string; const ARange: TTextRange; const AWish: TMcpExtractWish):
      TMcpExtractPlan;
  end;

implementation

end.
