unit Adapters.Lsp.RuleActions;

// Host-Adapter zwischen Rules und Lsp: Die Code-Aktionen im Editor fragen je Dokument ILspDocumentRuleActions;
// Treffer, Korrekturen und Auftrag für KI-Assistenten liefern die Prüfregeln über IRuleDocumentActions. Erzeugt nur
// in Shell.Composition.* und im MCP-Lauf (Shell.Mcp.RefactorHost); kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Findings.Contract,
  Lsp.Contract,
  Rules.Contract.Api;

type
  /// <summary>ILspRuleActions über die API der Prüfregeln.</summary>
  TLspRuleActionsAdapter = class(TInterfacedObject, ILspRuleActions)
  private
    FActions: IRuleCodeActions;
  public
    constructor Create(const AActions: IRuleCodeActions);
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): ILspDocumentRuleActions;
    /// <summary>Adapter über AActions; nil ohne.</summary>
    class function Wrap(const AActions: IRuleCodeActions): ILspRuleActions; static;
  end;

  /// <summary>ILspDocumentRuleActions über IRuleDocumentActions.</summary>
  TLspDocumentRuleActionsAdapter = class(TInterfacedObject, ILspDocumentRuleActions)
  private
    FActions: IRuleDocumentActions;
  public
    constructor Create(const AActions: IRuleDocumentActions);
    function SyntaxFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    function SharedRuleFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
    function CachedRuleFindings(const ADocument: ITextDocument; out AFindings: TArray<TRuleFinding>): Boolean;
    function Fixes(const AFindings: TArray<TRuleFinding>; const ADocument: ITextDocument; const ARange: TTextRange;
      const AStyle: TFormatStyle; ATryFinally: Boolean): TArray<TCodeAction>;
    function FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
    function Prompt(const AFinding: TRuleFinding; const AFileName, AText: string): string;
    function Index: ISymbolIndex;
  end;

implementation

{ TLspRuleActionsAdapter }

constructor TLspRuleActionsAdapter.Create(const AActions: IRuleCodeActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TLspRuleActionsAdapter.ForDocument(const AUri: string;
  const ACancelled: TRuleCancelled): ILspDocumentRuleActions;
begin
  Result := TLspDocumentRuleActionsAdapter.Create(FActions.ForDocument(AUri, ACancelled));
end;

class function TLspRuleActionsAdapter.Wrap(const AActions: IRuleCodeActions): ILspRuleActions;
begin
  Result := nil;
  if AActions <> nil then
  begin
    Result := TLspRuleActionsAdapter.Create(AActions);
  end;
end;

{ TLspDocumentRuleActionsAdapter }

constructor TLspDocumentRuleActionsAdapter.Create(const AActions: IRuleDocumentActions);
begin
  inherited Create;
  FActions := AActions;
end;

function TLspDocumentRuleActionsAdapter.SyntaxFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
begin
  Result := FActions.SyntaxFindings(ADocument);
end;

function TLspDocumentRuleActionsAdapter.SharedRuleFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
begin
  Result := FActions.SharedRuleFindings(ADocument);
end;

function TLspDocumentRuleActionsAdapter.CachedRuleFindings(const ADocument: ITextDocument;
  out AFindings: TArray<TRuleFinding>): Boolean;
begin
  Result := FActions.CachedRuleFindings(ADocument, AFindings);
end;

function TLspDocumentRuleActionsAdapter.Fixes(const AFindings: TArray<TRuleFinding>; const ADocument: ITextDocument;
  const ARange: TTextRange; const AStyle: TFormatStyle; ATryFinally: Boolean): TArray<TCodeAction>;
begin
  Result := FActions.Fixes(AFindings, ADocument, ARange, AStyle, ATryFinally);
end;

function TLspDocumentRuleActionsAdapter.FixAll(const AFindings: TArray<TRuleFinding>;
  out AAction: TCodeAction): Boolean;
begin
  Result := FActions.FixAll(AFindings, AAction);
end;

function TLspDocumentRuleActionsAdapter.Prompt(const AFinding: TRuleFinding; const AFileName, AText: string): string;
begin
  Result := FActions.Prompt(AFinding, AFileName, AText);
end;

function TLspDocumentRuleActionsAdapter.Index: ISymbolIndex;
begin
  Result := FActions.Index;
end;

end.
