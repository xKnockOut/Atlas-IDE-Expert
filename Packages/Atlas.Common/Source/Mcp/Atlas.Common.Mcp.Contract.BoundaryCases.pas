unit Atlas.Common.Mcp.Contract.BoundaryCases;

// Was das Werkzeug suggest_test_cases (#2173) vom Server braucht: die Grenzfälle einer Routine als Bericht. Der Host
// verbindet es mit Editing (Adapters.Mcp.BoundaryCases); die MCP-Werkzeuge kennen nur diese Unit.

interface

type
  TMcpBoundaryRequest = record
    /// <summary>Datei für die Überschrift bzw. uri, relativ zum Arbeitsbereich.</summary>
    FileName: string;
    /// <summary>Zeile (0-basiert) in der Routine; kleiner 0: Routine nach Namen.</summary>
    Line: Integer;
    /// <summary>"TFoo.Bar" oder "Bar".</summary>
    Routine: string;
    /// <summary>Höchstzahl der Fälle; 0 die Vorgabe.</summary>
    Max: Integer;
    /// <summary>True: JSON, sonst Markdown.</summary>
    Json: Boolean;
  end;

  IMcpBoundaryCases = interface
    ['{E3FEFF09-F275-4CA2-B2BE-C54017E2E255}']
    /// <summary>Bericht über die Routine der Anfrage im Quelltext AText; False ohne passende Routine.</summary>
    function Report(const AText: string; const ARequest: TMcpBoundaryRequest; out AReport: string): Boolean;
  end;

implementation

end.
