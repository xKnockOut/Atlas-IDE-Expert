unit Atlas.Common.Mcp.Contract.RuleDocs;

// Was search_atlas_docs und explain_compiler_message vom Server brauchen: die Regeln des Katalogs als reine Werte und
// ihren Zustand im Projekt. Der Host verbindet es mit Rules (Adapters.Mcp.RuleDocs); die MCP-Werkzeuge kennen nur
// diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract;

type
  IMcpRuleDocs = interface
    ['{9222888D-9AC7-4A46-8656-074124F70597}']
    /// <summary>Alle Regeln des Katalogs; Name, Beschreibung und Beispiele in der Sprache ALanguage ("de" oder
    /// "en" wie TAtlasLocale.Code; sonst englisch).</summary>
    function Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
    /// <summary>Wirksamer Schweregrad von ARuleId unter ASettings, Herkunft und Optionen aus ASettings.</summary>
    function State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
  end;

implementation

end.
