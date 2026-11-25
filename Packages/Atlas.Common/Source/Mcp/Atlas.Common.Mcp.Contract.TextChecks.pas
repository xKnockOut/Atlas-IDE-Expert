unit Atlas.Common.Mcp.Contract.TextChecks;

// Was get_diagnostics, hook_check, check_code, apply_code_action und explain_finding vom Server brauchen: die
// Prüfregeln über einen Text. Der Host verbindet es mit Rules (Adapters.Mcp.TextChecks) und bindet dabei Regeln,
// Projekt und Symbole je Datei; die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract;

type
  IMcpTextChecks = interface
    ['{9B069E67-971F-4FA1-BA6E-8A63DC32C7B3}']
    /// <summary>Syntaxfehler, Sprachmerkmale und Treffer der Regeln in AText, dem Inhalt von AFileName (absoluter
    /// Pfad); ARelativePath (relativ zum Arbeitsordner) für Regeln, overrides und Ausschlüsse aus ASettings.
    /// </summary>
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

implementation

end.
