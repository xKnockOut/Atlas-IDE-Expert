unit Atlas.Common.Rules.Providers.FindingPrompts;

// Anbieter von IRuleFindingPrompts (Atlas.Common.Rules.Contract.Api): Auftrag zu einem Befund über
// TFindingPrompt.Markdown mit dem deutschen Regelkatalog wie bisher bei explain_finding, Auftrag aus mehreren Befunden
// über TFindingPrompt.Many mit dem gemeinsamen Regelkatalog und dem üblichen Ausschnitt.

interface

uses
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  TRuleFindingPromptsProvider = class(TInterfacedObject, IRuleFindingPrompts)
  public
    function MarkdownOf(const AFinding: TRuleFinding; const AFileName, AText: string): string;
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    function DefaultLimit: Integer;
  end;

implementation

uses
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt;

{ TRuleFindingPromptsProvider }

function TRuleFindingPromptsProvider.MarkdownOf(const AFinding: TRuleFinding; const AFileName, AText: string): string;
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

function TRuleFindingPromptsProvider.Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
begin
  Result := TFindingPrompt.Many(AItems, TFindingPrompt.SharedCatalog, TFindingPrompt.cDefaultContext, ALimit);
end;

function TRuleFindingPromptsProvider.DefaultLimit: Integer;
begin
  Result := TFindingPrompt.cDefaultLimit;
end;

end.
