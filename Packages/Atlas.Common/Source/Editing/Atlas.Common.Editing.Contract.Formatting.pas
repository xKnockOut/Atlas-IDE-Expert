unit Atlas.Common.Editing.Contract.Formatting;

// Schnittstelle des Formatierers für andere Teile des Servers (#1358): Text nach einem Stil formatieren und die
// Abweichungen beschreiben. Ein Host-Adapter reicht sie an Konsumenten wie die MCP-Werkzeuge weiter
// (Adapters.Mcp.Formatting). Erzeugt in Atlas.Common.Editing.Composition.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Was formatiert werden soll.</summary>
  TEditingFormatRequest = record
    Text: string;
    Style: TFormatStyle;
    /// <summary>Datei, Symbole und Include-Suche für die Syntaxprüfung.</summary>
    Source: TPascalSource;
    /// <summary>True: ganze Datei; sonst die Zeilen FirstLine bis LastLine (0-basiert, einschließlich).</summary>
    WholeFile: Boolean;
    FirstLine: Integer;
    LastLine: Integer;
  end;

  /// <summary>Abweichung von den Formatregeln.</summary>
  TEditingFormatDeviation = record
    /// <summary>Zeile im Original, 0-basiert.</summary>
    Line: Integer;
    Message: string;
  end;

  TEditingFormatResult = record
    /// <summary>Ergebnis; bei Syntaxfehlern gleich dem Original.</summary>
    Formatted: string;
    /// <summary>Formatted weicht vom Original ab.</summary>
    Changed: Boolean;
    Deviations: TArray<TEditingFormatDeviation>;
    HasSyntaxError: Boolean;
    /// <summary>Erster Syntaxfehler, nur mit HasSyntaxError; Zeile 0-basiert.</summary>
    SyntaxErrorLine: Integer;
    SyntaxErrorMessage: string;
    /// <summary>Ein zweiter Lauf auf Formatted ändert nichts mehr.</summary>
    Stable: Boolean;
  end;

  IEditingFormatting = interface
    ['{F5430700-FD16-4D4D-B38C-F6CE4EC37F98}']
    /// <summary>Prüft auf Syntaxfehler, formatiert und beschreibt die Abweichungen.</summary>
    function Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
  end;

implementation

end.
