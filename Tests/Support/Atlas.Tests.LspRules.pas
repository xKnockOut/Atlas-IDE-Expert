unit Atlas.Tests.LspRules;

// Prüfregeln für die Diagnose des Sprachservers in Tests: dieselbe Verdrahtung wie in der Komposition
// (TRuleDocumentChecks über den Host-Adapter), mit einem Umfeld aus dem Test.

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
  end;

implementation

uses
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.Providers.DocumentChecks,
  Adapters.Lsp.RuleDiagnostics;

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

end.
