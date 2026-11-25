unit Adapters.Mcp.Conventions;

// Host-Adapter zwischen Mcp und Rules: delphi://conventions holt die Konventionen über IMcpConventions,
// explain_finding den Auftrag zu einem Befund über IMcpFindingPrompts; Rules bietet sie über IRuleConventions und
// IRuleFindingPrompts an. Erzeugt nur in Shell.Composition.*; kennt nur die Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Rules.Contract.Api;

type
  TMcpConventionsAdapter = class(TInterfacedObject, IMcpConventions)
  private
    FConventions: IRuleConventions;
  public
    constructor Create(const AConventions: IRuleConventions);
    function Markdown(const ASettings: TServerSettings): string;
  end;

  TMcpFindingPromptsAdapter = class(TInterfacedObject, IMcpFindingPrompts)
  private
    FPrompts: IRuleFindingPrompts;
  public
    constructor Create(const APrompts: IRuleFindingPrompts);
    function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
  end;

implementation

{ TMcpConventionsAdapter }

constructor TMcpConventionsAdapter.Create(const AConventions: IRuleConventions);
begin
  inherited Create;
  FConventions := AConventions;
end;

function TMcpConventionsAdapter.Markdown(const ASettings: TServerSettings): string;
begin
  Result := FConventions.Markdown(ASettings);
end;

{ TMcpFindingPromptsAdapter }

constructor TMcpFindingPromptsAdapter.Create(const APrompts: IRuleFindingPrompts);
begin
  inherited Create;
  FPrompts := APrompts;
end;

function TMcpFindingPromptsAdapter.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
begin
  Result := FPrompts.MarkdownOf(AFinding, AFileName, AText);
end;

end.
