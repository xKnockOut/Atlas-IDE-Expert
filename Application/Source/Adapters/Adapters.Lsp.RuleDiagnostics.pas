unit Adapters.Lsp.RuleDiagnostics;

// Host-Adapter zwischen Rules und Lsp: Die Diagnose im Editor fragt je Dokument ILspDocumentRules; Syntaxfehler,
// Sprachmerkmale und Treffer rechnen die Prüfregeln über IRuleDocumentCheck. Erzeugt nur in Shell.Composition.*;
// kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api;

type
  /// <summary>ILspRuleDiagnostics über die API der Prüfregeln.</summary>
  TLspRuleDiagnosticsAdapter = class(TInterfacedObject, ILspRuleDiagnostics)
  private
    FChecks: IRuleDocumentChecks;
  public
    constructor Create(const AChecks: IRuleDocumentChecks);
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): ILspDocumentRules;
    /// <summary>Adapter über AChecks; nil ohne.</summary>
    class function Wrap(const AChecks: IRuleDocumentChecks): ILspRuleDiagnostics; static;
  end;

  /// <summary>ILspDocumentRules über IRuleDocumentCheck.</summary>
  TLspDocumentRulesAdapter = class(TInterfacedObject, ILspDocumentRules)
  private
    FCheck: IRuleDocumentCheck;
    FCatalog: ILspRuleCatalog;
  public
    constructor Create(const ACheck: IRuleDocumentCheck);
    function SyntaxFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    function LanguageFeatureFindings(const ADocument: ITextDocument; const ADefines: TArray<string>;
      const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
    function RuleFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    function UnusedUsesShown: Boolean;
    function OnlyImplementationShown: Boolean;
    function Catalog: ILspRuleCatalog;
  end;

implementation

uses
  Adapters.Lsp.RuleCatalog;

{ TLspRuleDiagnosticsAdapter }

constructor TLspRuleDiagnosticsAdapter.Create(const AChecks: IRuleDocumentChecks);
begin
  inherited Create;
  FChecks := AChecks;
end;

function TLspRuleDiagnosticsAdapter.ForDocument(const AUri: string;
  const ACancelled: TRuleCancelled): ILspDocumentRules;
begin
  Result := TLspDocumentRulesAdapter.Create(FChecks.ForDocument(AUri, ACancelled));
end;

class function TLspRuleDiagnosticsAdapter.Wrap(const AChecks: IRuleDocumentChecks): ILspRuleDiagnostics;
begin
  Result := nil;
  if AChecks <> nil then
  begin
    Result := TLspRuleDiagnosticsAdapter.Create(AChecks);
  end;
end;

{ TLspDocumentRulesAdapter }

constructor TLspDocumentRulesAdapter.Create(const ACheck: IRuleDocumentCheck);
begin
  inherited Create;
  FCheck := ACheck;
  FCatalog := TLspRuleCatalogAdapter.Wrap(ACheck.Catalog);
end;

function TLspDocumentRulesAdapter.SyntaxFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>): TArray<TRuleFinding>;
begin
  Result := FCheck.SyntaxFindings(ADocument, ADefines);
end;

function TLspDocumentRulesAdapter.LanguageFeatureFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>; const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
begin
  Result := FCheck.LanguageFeatureFindings(ADocument, ADefines, ADelphiVersion, AInactive);
end;

function TLspDocumentRulesAdapter.RuleFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>): TArray<TRuleFinding>;
begin
  Result := FCheck.RuleFindings(ADocument, ADefines);
end;

function TLspDocumentRulesAdapter.UnusedUsesShown: Boolean;
begin
  Result := FCheck.UnusedUsesShown;
end;

function TLspDocumentRulesAdapter.OnlyImplementationShown: Boolean;
begin
  Result := FCheck.OnlyImplementationShown;
end;

function TLspDocumentRulesAdapter.Catalog: ILspRuleCatalog;
begin
  Result := FCatalog;
end;

end.
