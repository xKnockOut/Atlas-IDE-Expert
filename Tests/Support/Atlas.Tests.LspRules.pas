unit Atlas.Tests.LspRules;

// Prüfregeln für Diagnose und Code-Aktionen des Sprachservers in Tests: dieselbe Verdrahtung wie in der Komposition
// (TRuleDocumentChecks bzw. TRuleCodeActionsProvider über den Host-Adapter), mit einem Umfeld aus dem Test.

interface

uses
  Atlas.Common.Documents.Contract,
  Lsp.Contract,
  Rules.CheckContext;

type
  TTestLspRules = class
  public
    /// <summary>Anbieter, der immer AContext liefert.</summary>
    class function Fixed(const AContext: TRuleCheckContext): TRuleContextProvider; static;
    /// <summary>Prüfregeln je Dokument aus AProvider (nil = ohne Umfeld: Vorgaben, keine Regeln).</summary>
    class function From(const AProvider: TRuleContextProvider): ILspRuleDiagnostics; static;
    /// <summary>Ohne Umfeld: Syntaxfehler und Sprachmerkmale mit den Vorgaben, keine Regeln.</summary>
    class function Plain: ILspRuleDiagnostics; static;
    /// <summary>Prüfung eines Dokuments mit dem Umfeld AContext.</summary>
    class function Document(const AContext: TRuleCheckContext): ILspDocumentRules; static;
    /// <summary>Prüfung eines Dokuments ohne Umfeld.</summary>
    class function PlainDocument: ILspDocumentRules; static;
    /// <summary>Prüfregeln der Code-Aktionen aus AProvider (nil = ohne Umfeld).</summary>
    class function Actions(const AProvider: TRuleContextProvider): ILspRuleActions; static;
    /// <summary>Code-Aktionen ohne Umfeld: Syntaxfehler mit Korrektur, keine Regeln.</summary>
    class function PlainActions: ILspRuleActions; static;
    /// <summary>Regelkatalog wie in der Komposition.</summary>
    class function Catalog: ILspRuleCatalog; static;
    /// <summary>Auftrag an KI-Assistenten wie in der Komposition.</summary>
    class function FindingsPrompt: ILspFindingsPrompt; static;
    /// <summary>Sammelkorrektur wie in der Komposition: Umfeld aus AContexts, Text aus ARead.</summary>
    class function BulkFix(const AContexts: TRuleContextProvider; const ARead: TDocumentReadText): ILspBulkFix;
      static;
  end;

implementation

uses
  Rules.Contract.Api,
  Rules.Providers.DocumentChecks,
  Rules.Providers.DocumentActions,
  Rules.Providers.CatalogInfo,
  Rules.Providers.FindingPrompts,
  Rules.Providers.BulkFix,
  Adapters.Lsp.RuleCatalog,
  Adapters.Lsp.FindingsPrompt,
  Adapters.Lsp.BulkFix,
  Adapters.Lsp.RuleDiagnostics,
  Adapters.Lsp.RuleActions;

class function TTestLspRules.Fixed(const AContext: TRuleCheckContext): TRuleContextProvider;
begin
  Result :=
    function(const AUri: string; out AResult: TRuleCheckContext): Boolean
    begin
      AResult := AContext;
      Result := True;
    end;
end;

class function TTestLspRules.From(const AProvider: TRuleContextProvider): ILspRuleDiagnostics;
var
  mChecks: IRuleDocumentChecks;
  mCatalog: IRuleCatalogInfo;
begin
  mCatalog := TRuleCatalogInfo.Create;
  mChecks := TRuleDocumentChecks.Create(AProvider, mCatalog);
  Result := TLspRuleDiagnosticsAdapter.Wrap(mChecks);
end;

class function TTestLspRules.Plain: ILspRuleDiagnostics;
begin
  Result := From(nil);
end;

class function TTestLspRules.Document(const AContext: TRuleCheckContext): ILspDocumentRules;
begin
  Result := From(Fixed(AContext)).ForDocument('', AContext.Cancelled);
end;

class function TTestLspRules.PlainDocument: ILspDocumentRules;
begin
  Result := Plain.ForDocument('', nil);
end;

class function TTestLspRules.Actions(const AProvider: TRuleContextProvider): ILspRuleActions;
var
  mActions: IRuleCodeActions;
begin
  mActions := TRuleCodeActionsProvider.Create(AProvider);
  Result := TLspRuleActionsAdapter.Wrap(mActions);
end;

class function TTestLspRules.PlainActions: ILspRuleActions;
begin
  Result := Actions(nil);
end;

class function TTestLspRules.Catalog: ILspRuleCatalog;
var
  mCatalog: IRuleCatalogInfo;
begin
  mCatalog := TRuleCatalogInfo.Create;
  Result := TLspRuleCatalogAdapter.Wrap(mCatalog);
end;

class function TTestLspRules.FindingsPrompt: ILspFindingsPrompt;
var
  mPrompts: IRuleFindingPrompts;
begin
  mPrompts := TRuleFindingPromptsProvider.Create;
  Result := TLspFindingsPromptAdapter.Wrap(mPrompts);
end;

class function TTestLspRules.BulkFix(const AContexts: TRuleContextProvider;
  const ARead: TDocumentReadText): ILspBulkFix;
var
  mBulkFix: IRuleWorkspaceBulkFix;
begin
  mBulkFix := TRuleBulkFixProvider.CreateForWorkspace(AContexts, ARead, nil);
  Result := TLspBulkFixAdapter.Wrap(mBulkFix);
end;

end.
