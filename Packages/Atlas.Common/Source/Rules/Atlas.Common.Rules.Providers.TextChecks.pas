unit Atlas.Common.Rules.Providers.TextChecks;

// Anbieter von IRuleTextChecks (Atlas.Common.Rules.Contract.Api): TFileChecker.CheckText je Datei mit den Regeln,
// Projekten und Symbolen, die der Host beim Anlegen mitgibt, wie bisher bei den Prüfungen der MCP-Werkzeuge.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.Contract.Api;

type
  /// <summary>Regeln, Projekt und Symbole aus dem Konstruktor von TBoundRuleProvider.</summary>
  TRuleTextChecksProvider = class(TBoundRuleProvider, IRuleTextChecks)
  public
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
  end;

implementation

uses
  Atlas.Common.Findings.Scopes;

{ TRuleTextChecksProvider }

function TRuleTextChecksProvider.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := TFileChecker.CheckText(FRules, ASettings, ARelativePath, AText,
    TCheckOrigin.ForFile(FProject, FSource, AFileName), mScopes);
end;

end.
