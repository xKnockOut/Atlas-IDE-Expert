unit Adapters.Lsp.FindingsPrompt;

// Host-Adapter zwischen Rules und Lsp: atlas.server.findingsPrompt fragt ILspFindingsPrompt; den Text liefern die
// Prüfregeln über IRuleFindingPrompts. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Findings.Contract,
  Lsp.Contract,
  Rules.Contract.Api;

type
  /// <summary>ILspFindingsPrompt über die API der Prüfregeln.</summary>
  TLspFindingsPromptAdapter = class(TInterfacedObject, ILspFindingsPrompt)
  private
    FPrompts: IRuleFindingPrompts;
  public
    constructor Create(const APrompts: IRuleFindingPrompts);
    function Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
    function DefaultLimit: Integer;
    /// <summary>Adapter über APrompts; nil ohne.</summary>
    class function Wrap(const APrompts: IRuleFindingPrompts): ILspFindingsPrompt; static;
  end;

implementation

constructor TLspFindingsPromptAdapter.Create(const APrompts: IRuleFindingPrompts);
begin
  inherited Create;
  FPrompts := APrompts;
end;

function TLspFindingsPromptAdapter.Markdown(const AItems: TArray<TFindingPromptItem>; ALimit: Integer): string;
begin
  Result := FPrompts.Markdown(AItems, ALimit);
end;

function TLspFindingsPromptAdapter.DefaultLimit: Integer;
begin
  Result := FPrompts.DefaultLimit;
end;

class function TLspFindingsPromptAdapter.Wrap(const APrompts: IRuleFindingPrompts): ILspFindingsPrompt;
begin
  Result := nil;
  if APrompts <> nil then
  begin
    Result := TLspFindingsPromptAdapter.Create(APrompts);
  end;
end;

end.
