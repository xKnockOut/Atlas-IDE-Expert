unit Atlas.Common.Semantics.NameResolver.Core;

// Kern der Namensauflösung: legt die Teile von TNameResolver an, verbindet sie (der Typ von Inline-Variablen
// kommt aus den Ausdrücken) und gibt sie rückwärts frei. TNameResolver reicht seine Aufrufe an diese Teile weiter.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.Contract,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Semantics.NameResolver.Place,
  Atlas.Common.Semantics.NameResolver.Units,
  Atlas.Common.Semantics.NameResolver.Lookup,
  Atlas.Common.Semantics.NameResolver.Typing,
  Atlas.Common.Semantics.NameResolver.Members,
  Atlas.Common.Semantics.NameResolver.Locals,
  Atlas.Common.Semantics.NameResolver.Expressions,
  Atlas.Common.Semantics.NameResolver.Chains,
  Atlas.Common.Semantics.NameResolver.Candidates,
  Atlas.Common.Semantics.NameResolver.Queries;

type
  TResolverCore = class
  private
    FParts: TResolverParts;
    FExpressions: TResolverExpressions;
    FChains: TResolverChains;
    FCandidates: TResolverCandidates;
    FQueries: TResolverQueries;
    /// <summary>Typ eines Ausdrucks für TResolverTyping (Inline-Variablen ohne Typangabe).</summary>
    function InferFunc: TResolverInferFunc;
  public
    constructor Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc; const ATreeUnits: ITreeUnits);
    destructor Destroy; override;
    property Place: TResolverPlace read FParts.Place;
    property Units: TResolverUnits read FParts.Units;
    property Lookup: TResolverLookup read FParts.Lookup;
    property Typing: TResolverTyping read FParts.Typing;
    property Members: TResolverMembers read FParts.Members;
    property Locals: TResolverLocals read FParts.Locals;
    property Expressions: TResolverExpressions read FExpressions;
    property Chains: TResolverChains read FChains;
    property Candidates: TResolverCandidates read FCandidates;
    property Queries: TResolverQueries read FQueries;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree;

constructor TResolverCore.Create(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const ATreeUnits: ITreeUnits);
begin
  inherited Create;
  FParts.Place := TResolverPlace.Create(AIndex, ATreeUnits);
  FParts.Units := TResolverUnits.Create(FParts.Place, AEnsureUnit);
  FParts.Lookup := TResolverLookup.Create(FParts.Place, FParts.Units);
  FParts.Typing := TResolverTyping.Create(FParts.Place, FParts.Units, FParts.Lookup);
  FParts.Members := TResolverMembers.Create(FParts.Place, FParts.Units, FParts.Typing);
  FParts.Locals := TResolverLocals.Create(FParts.Place, FParts.Units, FParts.Lookup);
  FExpressions := TResolverExpressions.Create(FParts);
  FChains := TResolverChains.Create(FParts, FExpressions);
  FCandidates := TResolverCandidates.Create(FParts, FExpressions, FChains);
  FQueries := TResolverQueries.Create(FParts, FExpressions, FChains);
  FParts.Typing.Infer := InferFunc();
end;

destructor TResolverCore.Destroy;
begin
  if FParts.Typing <> nil then
  begin
    FParts.Typing.Infer := nil;
  end;
  FQueries.Free;
  FCandidates.Free;
  FChains.Free;
  FExpressions.Free;
  FParts.Locals.Free;
  FParts.Members.Free;
  FParts.Typing.Free;
  FParts.Lookup.Free;
  FParts.Units.Free;
  FParts.Place.Free;
  inherited;
end;

function TResolverCore.InferFunc: TResolverInferFunc;
var
  mExpressions: TResolverExpressions;
begin
  // Eigene Routine, damit die Methodenreferenz nur diese Variable einfängt (kein Kreis über Self).
  mExpressions := FExpressions;
  Result :=
    function(ANode: TSyntaxNode; out AResult: TResolvedSymbol): Boolean
    begin
      Result := mExpressions.ExprSymbol(ANode, AResult);
    end;
end;

end.
