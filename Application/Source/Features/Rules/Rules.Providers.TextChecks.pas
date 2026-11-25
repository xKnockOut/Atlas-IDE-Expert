unit Rules.Providers.TextChecks;

// Anbieter von IRuleTextChecks (Rules.Contract.Api): TFileChecker.CheckText je Datei mit den Regeln,
// Projekten und Symbolen, die der Host beim Anlegen mitgibt, wie bisher bei den Prüfungen der MCP-Werkzeuge.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Findings.Contract,
  Rules.Checker,
  Rules.Contract.Api;

type
  /// <summary>Regeln, Projekt und Symbole aus dem Konstruktor von TBoundRuleProvider.</summary>
  TRuleTextChecksProvider = class(TBoundRuleProvider, IRuleTextChecks)
  public
    function Check(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings):
      TArray<TRuleFinding>;
    function Actions(const AFileName, ARelativePath, AText: string; const ASettings: TServerSettings;
      const ARange: TTextRange): TArray<TCodeAction>;
  end;

implementation

uses
  Atlas.Common.Findings.Scopes,
  Rules.CodeActions;

{ TRuleTextChecksProvider }

function TRuleTextChecksProvider.Check(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings): TArray<TRuleFinding>;
var
  mScopes: TFindingScopes;
begin
  Result := TFileChecker.CheckText(FRules, ASettings, ARelativePath, AText,
    TCheckOrigin.ForFile(FProject, FSource, AFileName), mScopes);
end;

function TRuleTextChecksProvider.Actions(const AFileName, ARelativePath, AText: string;
  const ASettings: TServerSettings; const ARange: TTextRange): TArray<TCodeAction>;
begin
  Result := TRuleCodeActions.ForRange(Check(AFileName, ARelativePath, AText, ASettings), AText, ARange);
end;

end.
