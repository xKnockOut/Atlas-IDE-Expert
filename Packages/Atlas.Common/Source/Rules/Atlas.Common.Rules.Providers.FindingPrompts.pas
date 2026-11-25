unit Atlas.Common.Rules.Providers.FindingPrompts;

// Anbieter von IRuleFindingPrompts (Atlas.Common.Rules.Contract.Api): TFindingPrompt.Markdown mit dem deutschen
// Regelkatalog wie bisher bei explain_finding.

interface

uses
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  TRuleFindingPromptsProvider = class(TInterfacedObject, IRuleFindingPrompts)
  public
    function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
  end;

implementation

uses
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt;

{ TRuleFindingPromptsProvider }

function TRuleFindingPromptsProvider.Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
var
  mCatalog: TRuleCatalog;
begin
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    Result := TFindingPrompt.Markdown(AFinding, AFileName, AText, mCatalog);
  finally
    mCatalog.Free;
  end;
end;

end.
