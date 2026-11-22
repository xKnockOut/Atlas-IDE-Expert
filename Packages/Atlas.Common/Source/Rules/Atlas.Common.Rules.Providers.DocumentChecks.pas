unit Atlas.Common.Rules.Providers.DocumentChecks;

// Anbieter von IRuleDocumentChecks (Atlas.Common.Rules.Contract.Api) für die Diagnose im Editor: Das Umfeld je
// Datei liefert die Komposition (TRuleContextProvider); daraus kommen Syntaxfehler und Sprachmerkmale als Treffer
// (TFileChecker), die Treffer der Prüfregeln über den gemeinsamen Speicher ohne die Baseline (#97) und die
// Schalter für die Darstellung auffälliger uses (#1135, #1136).

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Findings.Contract,
  Atlas.Common.Rules.Contract.Api,
  Atlas.Common.Rules.CheckContext;

type
  TRuleDocumentChecks = class(TInterfacedObject, IRuleDocumentChecks)
  private
    FProvider: TRuleContextProvider;
  public
    /// <summary>AProvider nil = nie ein Umfeld.</summary>
    constructor Create(const AProvider: TRuleContextProvider);
    function ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentCheck;
  end;

  /// <summary>Prüfung eines Dokuments über das Umfeld AContext.</summary>
  TRuleDocumentCheck = class(TInterfacedObject, IRuleDocumentCheck)
  private
    FContext: TRuleCheckContext;
    FHasContext: Boolean;
    function RuleOn(const ARuleId: string): Boolean;
  public
    /// <summary>AHasContext False: Vorgaben, keine Regeln.</summary>
    constructor Create(const AContext: TRuleCheckContext; AHasContext: Boolean);
    function SyntaxFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    function LanguageFeatureFindings(const ADocument: ITextDocument; const ADefines: TArray<string>;
      const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
    function RuleFindings(const ADocument: ITextDocument; const ADefines: TArray<string>): TArray<TRuleFinding>;
    function UnusedUsesShown: Boolean;
    function OnlyImplementationShown: Boolean;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Rules.Engine,
  Atlas.Common.Rules.Checker,
  Atlas.Common.Findings.Scopes,
  Atlas.Common.Rules.Builtin.DeadCode;

{ TRuleDocumentChecks }

constructor TRuleDocumentChecks.Create(const AProvider: TRuleContextProvider);
begin
  inherited Create;
  FProvider := AProvider;
end;

function TRuleDocumentChecks.ForDocument(const AUri: string; const ACancelled: TRuleCancelled): IRuleDocumentCheck;
var
  mContext: TRuleCheckContext;
  mHasContext: Boolean;
begin
  mContext := Default(TRuleCheckContext);
  mHasContext := Assigned(FProvider) and FProvider(AUri, mContext);
  if not mHasContext then
  begin
    mContext := Default(TRuleCheckContext);
  end;
  mContext.Cancelled := ACancelled;
  Result := TRuleDocumentCheck.Create(mContext, mHasContext);
end;

{ TRuleDocumentCheck }

constructor TRuleDocumentCheck.Create(const AContext: TRuleCheckContext; AHasContext: Boolean);
begin
  inherited Create;
  FContext := AContext;
  FHasContext := AHasContext;
end;

function TRuleDocumentCheck.SyntaxFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>): TArray<TRuleFinding>;
begin
  Result := TFileChecker.SyntaxFindings(TSyntaxTreeCache.GetFor(ADocument, ADefines).Tree.Diagnostics,
    FContext.Settings);
end;

function TRuleDocumentCheck.LanguageFeatureFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>; const ADelphiVersion: string; const AInactive: TArray<TTextRange>): TArray<TRuleFinding>;
var
  mTree: ISharedSyntaxTree;
begin
  mTree := TSyntaxTreeCache.GetFor(ADocument, ADefines);
  Result := TFileChecker.LanguageFeatureFindings(mTree.Tree, FContext.Settings, ADelphiVersion, AInactive);
end;

function TRuleDocumentCheck.RuleFindings(const ADocument: ITextDocument;
  const ADefines: TArray<string>): TArray<TRuleFinding>;
var
  mTree: ISharedSyntaxTree;
  mText: string;
begin
  if Length(FContext.Rules) = 0 then
  begin
    Exit(nil);
  end;
  // Derselbe Baum wie bei der Diagnose (nur aktive Zweige, #845): aus dem gemeinsamen Zwischenspeicher.
  mTree := TSyntaxTreeCache.GetFor(ADocument, ADefines);
  mText := ADocument.Text;
  Result := FContext.SharedFindings(mText, mTree.Tree, FContext.Cancelled);
  // Routinen aus demselben Baum: Die Baseline braucht sie für ihren Schlüssel.
  if FContext.Baseline <> nil then
  begin
    Result := FContext.Baseline.Filter(FContext.RelativePath, mText, TFindingScopes.FromTree(mTree.Tree), Result);
  end;
end;

/// <summary>Ist die Regel ARuleId für die Datei an (Einstellungen, exclude, Gruppen)? Ohne Umfeld ja.</summary>
function TRuleDocumentCheck.RuleOn(const ARuleId: string): Boolean;
begin
  Result := not FHasContext or TRuleEngine.RuleOn(ARuleId, FContext.Settings, FContext.RelativePath,
    ChangeFileExt(ExtractFileName(FContext.FileName), ''));
end;

function TRuleDocumentCheck.UnusedUsesShown: Boolean;
begin
  Result := RuleOn(cUnusedUsesRuleId);
end;

function TRuleDocumentCheck.OnlyImplementationShown: Boolean;
begin
  Result := RuleOn(cUsesOnlyInImplementationRuleId);
end;

end.
