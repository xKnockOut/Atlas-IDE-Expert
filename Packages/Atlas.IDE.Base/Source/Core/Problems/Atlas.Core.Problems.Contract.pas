unit Atlas.Core.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.
// TAtlasIdeError (#1819): ein Fehler aus Error Insight der IDE, roh wie in
// TOTAError; das Modul Prüfregeln liefert ihn über IAtlasIdeErrors
// (Atlas.IDE.Contracts.Rules), umgerechnet wird in Atlas.Core.Problems.IdeErrors.

interface

uses
  Atlas.Core.Lsp.Contract;

type
  /// <summary>Liegt im Lsp-Feature (die Protokollschicht liegt unten); Alias für bestehende Nutzer.</summary>
  TAtlasProblemSeverity = Atlas.Core.Lsp.Contract.TAtlasProblemSeverity;
  TAtlasProblem = Atlas.Core.Lsp.Contract.TAtlasProblem;
  TAtlasProblemRelated = Atlas.Core.Lsp.Contract.TAtlasProblemRelated;

  /// <summary>Ein Fehler aus Error Insight der IDE (#1819), Werte wie in TOTAError: Zeilen 1-basiert, Spalten
  /// (CharIndex) wie geliefert, Severity roh.</summary>
  TAtlasIdeError = record
    Text: string;
    StartLine: Integer;
    StartCharIndex: Integer;
    StopLine: Integer;
    StopCharIndex: Integer;
    Severity: Integer;
  end;

implementation

end.
