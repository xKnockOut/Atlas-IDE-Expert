unit Atlas.Common.Rules.Providers.DocumentActions;

// Anbieter von IRuleCodeActions (Atlas.Common.Rules.Contract.Api) für die Code-Aktionen im Editor: Das Umfeld je
// Datei liefert die Komposition (TRuleContextProvider) wie bei der Diagnose. Daraus kommen die Syntaxfehler mit
// Korrektur (#1022), die Treffer der Prüfregeln aus dem gemeinsamen Speicher (#1761, #2008), ihre Korrekturen
// (TRuleCodeActions) und der Auftrag für KI-Assistenten (TFindingPrompt).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.CheckContext;

type
  TRuleCodeActionsProvider = class(TInterfacedObject, IRuleCodeActions)
  private
    FProvider: TRuleContextProvider;
  public
    /// <summary>AProvider nil = nie ein Umfeld.</summary>
    constructor Create(const AProvider: TRuleContextProvider);
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentActions;
  end;

  /// <summary>Aktionen eines Dokuments über das Umfeld AContext.</summary>
  TRuleDocumentActions = class(TInterfacedObject, IRuleDocumentActions)
  private
    FContext: TRuleCheckContext;
    FWaitCancelled: TRuleCancelled;
  public
    /// <summary>AWaitCancelled beendet nur das Warten auf einen fremden Lauf, nicht den eigenen.</summary>
    constructor Create(const AContext: TRuleCheckContext; const AWaitCancelled: TRuleCancelled);
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

uses
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Rules.CodeActions,
  Atlas.Common.Rules.Prompt;

{ TRuleCodeActionsProvider }

constructor TRuleCodeActionsProvider.Create(const AProvider: TRuleContextProvider);
begin
  inherited Create;
  FProvider := AProvider;
end;

function TRuleCodeActionsProvider.ForDocument(const AUri: string;
  const ACancelled: TRuleCancelled): IRuleDocumentActions;
var
  mContext: TRuleCheckContext;
begin
  TRuleContexts.Lookup(FProvider, AUri, mContext);
  Result := TRuleDocumentActions.Create(mContext, ACancelled);
end;

{ TRuleDocumentActions }

constructor TRuleDocumentActions.Create(const AContext: TRuleCheckContext; const AWaitCancelled: TRuleCancelled);
begin
  inherited Create;
  FContext := AContext;
  FWaitCancelled := AWaitCancelled;
end;

function TRuleDocumentActions.SyntaxFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
begin
  Result := TFileChecker.SyntaxFindings(TSyntaxTreeCache.Get(ADocument).Tree.Diagnostics, FContext.Settings);
end;

function TRuleDocumentActions.SharedRuleFindings(const ADocument: ITextDocument): TArray<TRuleFinding>;
begin
  if Length(FContext.Rules) = 0 then
  begin
    Exit(nil);
  end;
  Result := FContext.SharedFindings(ADocument.Text, TSyntaxTreeCache.Get(ADocument).Tree, FWaitCancelled);
end;

function TRuleDocumentActions.CachedRuleFindings(const ADocument: ITextDocument;
  out AFindings: TArray<TRuleFinding>): Boolean;
begin
  AFindings := nil;
  if Length(FContext.Rules) = 0 then
  begin
    Exit(True);
  end;
  Result := FContext.CachedFindings(ADocument.Text, TSyntaxTreeCache.Get(ADocument).Tree, FWaitCancelled,
    AFindings);
end;

function TRuleDocumentActions.Fixes(const AFindings: TArray<TRuleFinding>; const ADocument: ITextDocument;
  const ARange: TTextRange; const AStyle: TFormatStyle; ATryFinally: Boolean): TArray<TCodeAction>;
begin
  if ATryFinally then
  begin
    Result := TRuleCodeActions.ForRange(AFindings, ADocument.Text, TSyntaxTreeCache.Get(ADocument).Tree, ARange,
      AStyle);
  end
  else
  begin
    Result := TRuleCodeActions.ForFindings(AFindings, ADocument.Text, ARange);
  end;
end;

function TRuleDocumentActions.FixAll(const AFindings: TArray<TRuleFinding>; out AAction: TCodeAction): Boolean;
begin
  Result := TRuleCodeActions.FixAll(AFindings, AAction);
end;

function TRuleDocumentActions.Prompt(const AFinding: TRuleFinding; const AFileName, AText: string): string;
begin
  Result := TFindingPrompt.Markdown(AFinding, AFileName, AText, TFindingPrompt.SharedCatalog);
end;

function TRuleDocumentActions.Index: ISymbolIndex;
begin
  Result := FContext.Services.Index;
end;

end.
