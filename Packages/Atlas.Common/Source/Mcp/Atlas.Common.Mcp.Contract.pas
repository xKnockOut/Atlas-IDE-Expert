unit Atlas.Common.Mcp.Contract;

// Gemeinsame Typen der MCP-Werkzeuge, die mit den Prüfregeln arbeiten
// (find_unused_code, get_diagnostics, check_code, apply_code_action,
// fix_findings): welche Regeln mit welchen Einstellungen in welchem
// Arbeitsordner gelten.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract;

type
  /// <summary>Regeln, wirksame Einstellungen und Arbeitsordner, mit denen ein Werkzeug prüft.</summary>
  TMcpRuleScope = record
    Rules: TArray<IRule>;
    Settings: TServerSettings;
    /// <summary>Arbeitsordner; Pfade im Bericht stehen relativ dazu.</summary>
    Root: string;
    class function Create(const ARules: TArray<IRule>; const ASettings: TServerSettings;
      const ARoot: string): TMcpRuleScope; static;
  end;

implementation

class function TMcpRuleScope.Create(const ARules: TArray<IRule>; const ASettings: TServerSettings;
  const ARoot: string): TMcpRuleScope;
begin
  Result.Rules := ARules;
  Result.Settings := ASettings;
  Result.Root := ARoot;
end;

end.
