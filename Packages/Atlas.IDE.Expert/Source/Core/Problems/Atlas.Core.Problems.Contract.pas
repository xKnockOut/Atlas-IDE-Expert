unit Atlas.Core.Problems.Contract;

// Probleme im Editor (#398): Diagnosen des Servers (Syntaxfehler, Regeltreffer,
// Compilermeldungen mit source "dcc") als Datensatz des Plugins. Positionen
// sind 0-basiert in UTF-16-Einheiten wie im LSP.

interface

uses
  Atlas.Core.Lsp.Contract;

type
  /// <summary>Seit A-09 im Lsp-Feature (die Protokollschicht liegt unten); Alias für bestehende Nutzer.</summary>
  TAtlasProblemSeverity = Atlas.Core.Lsp.Contract.TAtlasProblemSeverity;
  TAtlasProblem = Atlas.Core.Lsp.Contract.TAtlasProblem;

implementation

end.
