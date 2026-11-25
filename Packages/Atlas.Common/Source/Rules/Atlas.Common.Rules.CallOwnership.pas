unit Atlas.Common.Rules.CallOwnership;

// Besitz über Unit-Grenzen für Prüfregeln und die Marke „Wer gibt das frei?“:
// Was eine gerufene Routine mit einem Objekt macht, das als Argument an sie geht
// (Atlas.Common.Semantics.CallOwnership). Die Namensauflösung des Laufs wird erst
// beim ersten Aufruf geholt und gepinnt, weil die meisten Routinen kein Objekt
// weitergeben; Destroy löst sie wieder.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.CallOwnership,
  Atlas.Common.Rules.Contract;

type
  TRuleCallOwnership = class
  private
    FContext: TRuleContext;
    FCache: IRuleDerivedCache;
    FResolver: TNameResolver;
    FCalls: TCallOwnership;
  public
    /// <summary>AContext muss gelten, solange das Objekt lebt (Baum des Aufrufers).</summary>
    constructor Create(const AContext: TRuleContext);
    destructor Destroy; override;
    /// <summary>Was der Aufruf ACall mit seinem Argument AArgument (ab 0) macht.</summary>
    function EffectOf(ACall: TSyntaxNode; AArgument: Integer): TCallEffect;
  end;

implementation

uses
  Atlas.Common.Rules.Derived;

constructor TRuleCallOwnership.Create(const AContext: TRuleContext);
begin
  inherited Create;
  FContext := AContext;
end;

destructor TRuleCallOwnership.Destroy;
begin
  FCalls.Free;
  if FResolver <> nil then
  begin
    FResolver.UnpinTree;
  end;
  inherited Destroy;
end;

function TRuleCallOwnership.EffectOf(ACall: TSyntaxNode; AArgument: Integer): TCallEffect;
begin
  if FCalls = nil then
  begin
    TRuleDerived.EnsurePinnedResolver(FCache, FResolver, FContext, FContext.ResolverFileName);
    FCalls := TCallOwnership.Create(FResolver, FContext.Tree, FContext.ResolverFileName, FContext.Index,
      FContext.EnsureUnit, FContext.Namespaces);
  end;
  Result := FCalls.EffectOf(ACall, AArgument);
end;

end.
