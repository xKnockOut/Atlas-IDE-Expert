unit Adapters.Mcp.DeadCode;

// Host-Adapter zwischen Mcp und Rules: find_unused_code holt die Regeln für ungenutzten Code über IMcpDeadCode, Rules
// bietet sie über IRuleDeadCode an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.DeadCode,
  Rules.Contract.Api;

type
  TMcpDeadCodeAdapter = class(TInterfacedObject, IMcpDeadCode)
  private
    FDeadCode: IRuleDeadCode;
  public
    constructor Create(const ADeadCode: IRuleDeadCode);
    function RuleIds: TArray<string>;
    function Available: Boolean;
    function Complete(out AReason: string): Boolean;
    function ReadText(const AFileName: string; out AText: string): Boolean;
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

implementation

{ TMcpDeadCodeAdapter }

constructor TMcpDeadCodeAdapter.Create(const ADeadCode: IRuleDeadCode);
begin
  inherited Create;
  FDeadCode := ADeadCode;
end;

function TMcpDeadCodeAdapter.RuleIds: TArray<string>;
begin
  Result := FDeadCode.RuleIds;
end;

function TMcpDeadCodeAdapter.Available: Boolean;
begin
  Result := FDeadCode.Available;
end;

function TMcpDeadCodeAdapter.Complete(out AReason: string): Boolean;
begin
  Result := FDeadCode.Complete(AReason);
end;

function TMcpDeadCodeAdapter.ReadText(const AFileName: string; out AText: string): Boolean;
begin
  Result := FDeadCode.ReadText(AFileName, AText);
end;

function TMcpDeadCodeAdapter.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
begin
  Result := FDeadCode.Check(AFileName, ARelativePath, AText, ASettings);
end;

end.
