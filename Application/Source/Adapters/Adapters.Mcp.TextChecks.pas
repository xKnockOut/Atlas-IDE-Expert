unit Adapters.Mcp.TextChecks;

// Host-Adapter zwischen Mcp und Rules: Die MCP-Werkzeuge prüfen Texte über IMcpTextChecks, Rules bietet die
// Prüfung über IRuleTextChecks an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.TextChecks,
  Atlas.Common.Rules.Contract.Api;

type
  TMcpTextChecksAdapter = class(TInterfacedObject, IMcpTextChecks)
  private
    FChecks: IRuleTextChecks;
  public
    constructor Create(const AChecks: IRuleTextChecks);
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

implementation

{ TMcpTextChecksAdapter }

constructor TMcpTextChecksAdapter.Create(const AChecks: IRuleTextChecks);
begin
  inherited Create;
  FChecks := AChecks;
end;

function TMcpTextChecksAdapter.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
begin
  Result := FChecks.Check(AFileName, ARelativePath, AText, ASettings);
end;

end.
