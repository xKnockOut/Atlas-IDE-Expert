unit Rules.Providers.Conventions;

// Anbieter von IRuleConventions (Rules.Contract.Api): TRuleConventions mit den Regeln, die der Host
// beim Anlegen mitgibt, und dem deutschen Regelkatalog wie bisher bei der MCP-Ressource delphi://conventions.

interface

uses
  Atlas.Common.Configuration.Contract,
  Rules.Contract,
  Rules.Contract.Api;

type
  TRuleConventionsProvider = class(TInterfacedObject, IRuleConventions)
  private
    FRules: TArray<IRule>;
  public
    constructor Create(const ARules: TArray<IRule>);
    function Markdown(const ASettings: TServerSettings): string;
  end;

implementation

uses
  Rules.Catalog,
  Rules.Prompt,
  Rules.Conventions;

{ TRuleConventionsProvider }

constructor TRuleConventionsProvider.Create(const ARules: TArray<IRule>);
begin
  inherited Create;
  FRules := ARules;
end;

function TRuleConventionsProvider.Markdown(const ASettings: TServerSettings): string;
var
  mCatalog: TRuleCatalog;
begin
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    Result := TRuleConventions.Markdown(FRules, ASettings, mCatalog);
  finally
    mCatalog.Free;
  end;
end;

end.
