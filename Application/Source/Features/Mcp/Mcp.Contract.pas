unit Mcp.Contract;

// Gemeinsame Typen der MCP-Werkzeuge, die mit den Prüfregeln arbeiten
// (find_unused_code, get_diagnostics, check_code, apply_code_action,
// fix_findings): welche Regeln mit welchen Einstellungen in welchem
// Arbeitsordner gelten.

interface

uses
  Atlas.Common.Configuration.Contract,
  Mcp.Contract.TextChecks;

type
  /// <summary>Regeln, wirksame Einstellungen und Arbeitsordner, mit denen ein Werkzeug prüft.</summary>
  TMcpRuleScope = record
    /// <summary>Prüfung von Texten (get_diagnostics, hook_check, check_code, apply_code_action); Regeln, Projekt und
    /// Symbole hat der Host gebunden.</summary>
    Checks: IMcpTextChecks;
    Settings: TServerSettings;
    /// <summary>Arbeitsordner; Pfade im Bericht stehen relativ dazu.</summary>
    Root: string;
    /// <summary>Scope, der über AChecks prüft; nil für Werkzeuge, die keine Texte prüfen (find_unused_code).
    /// </summary>
    class function Checking(const AChecks: IMcpTextChecks; const ASettings: TServerSettings;
      const ARoot: string): TMcpRuleScope; static;
  end;

implementation

{ TMcpRuleScope }

class function TMcpRuleScope.Checking(const AChecks: IMcpTextChecks; const ASettings: TServerSettings;
  const ARoot: string): TMcpRuleScope;
begin
  Result := Default(TMcpRuleScope);
  Result.Checks := AChecks;
  Result.Settings := ASettings;
  Result.Root := ARoot;
end;

end.
