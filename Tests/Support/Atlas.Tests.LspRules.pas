unit Atlas.Tests.LspRules;

// Prüfregeln für Diagnose und Code-Aktionen des Sprachservers in Tests: dieselbe Verdrahtung wie in der Komposition
// (TRuleDocumentChecks bzw. TRuleCodeActionsProvider über den Host-Adapter), mit einem Umfeld aus dem Test.

interface

uses
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Rules.CheckContext;

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
  end;

implementation

uses
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.DocumentChecks,
  Atlas.Common.Rules.Providers.DocumentActions,
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
begin
  mChecks := TRuleDocumentChecks.Create(AProvider);
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

end.
