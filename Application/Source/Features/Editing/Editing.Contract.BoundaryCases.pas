unit Editing.Contract.BoundaryCases;

// Grenzfälle einer Routine als Bericht (#2173) für andere Teile des Servers. Ein Host-Adapter reicht ihn an die
// MCP-Werkzeuge weiter (Adapters.Mcp.BoundaryCases). Erzeugt in Editing.Composition.

interface

type
  TEditingBoundaryRequest = record
    /// <summary>Quelltext der Unit.</summary>
    Text: string;
    /// <summary>Datei für Überschrift bzw. uri.</summary>
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

  IEditingBoundaryCases = interface
    ['{4C0C7A32-7A92-42B8-AFEB-502C4828D5F4}']
    /// <summary>Bericht über die Routine der Anfrage; False ohne passende Routine.</summary>
    function Report(const ARequest: TEditingBoundaryRequest; out AReport: string): Boolean;
  end;

implementation

end.
