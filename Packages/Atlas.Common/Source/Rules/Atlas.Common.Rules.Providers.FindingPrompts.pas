unit Atlas.Common.Rules.Providers.FindingPrompts;

// Anbieter von IRuleFindingPrompts (Atlas.Common.Rules.Contract.Api): Auftrag an einen KI-Assistenten aus mehreren
// Befunden über TFindingPrompt.Many mit dem gemeinsamen Regelkatalog und dem üblichen Ausschnitt.

interface

uses
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  TRuleFindingPrompts = class(TInterfacedObject, IRuleFindingPrompts)
  public
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    function DefaultLimit: Integer;
  end;

implementation

uses
  Atlas.Common.Rules.Prompt;

function TRuleFindingPrompts.Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
begin
  Result := TFindingPrompt.Many(AItems, TFindingPrompt.SharedCatalog, TFindingPrompt.cDefaultContext, ALimit);
end;

function TRuleFindingPrompts.DefaultLimit: Integer;
begin
  Result := TFindingPrompt.cDefaultLimit;
end;

end.
