unit Adapters.Mcp.RuleDocs;

// Host-Adapter zwischen Mcp und Rules: search_atlas_docs und explain_compiler_message lesen den Regelkatalog über
// IMcpRuleDocs, Rules bietet ihn über IRuleDocs an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden
// Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.RuleDocs,
  Rules.Contract.Api;

type
  TMcpRuleDocsAdapter = class(TInterfacedObject, IMcpRuleDocs)
  private
    FDocs: IRuleDocs;
  public
    constructor Create(const ADocs: IRuleDocs);
    function Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
    function State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
  end;

implementation

{ TMcpRuleDocsAdapter }

constructor TMcpRuleDocsAdapter.Create(const ADocs: IRuleDocs);
begin
  inherited Create;
  FDocs := ADocs;
end;

function TMcpRuleDocsAdapter.Rules(const ALanguage: string): TArray<TFindingRuleInfo>;
begin
  Result := FDocs.Rules(ALanguage);
end;

function TMcpRuleDocsAdapter.State(const ARuleId: string; const ASettings: TServerSettings): TFindingRuleState;
begin
  Result := FDocs.State(ARuleId, ASettings);
end;

end.
