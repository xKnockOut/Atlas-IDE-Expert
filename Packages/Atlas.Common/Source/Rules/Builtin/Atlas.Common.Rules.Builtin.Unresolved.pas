unit Atlas.Common.Rules.Builtin.Unresolved;

// Nicht auflösbare Bezeichner beim Tippen (#178), wie Compilerfehler E2003,
// aber ohne Compiler (Community Edition, Prüfung in der IDE aus). Nutzt die
// vorsichtige Prüfung aus TUnresolvedNames: nur der erste Name einer Kette in
// Anweisungen, with/asm/anonyme Methoden übersprungen, ohne Unit System im
// Index keine Aussage. Ohne Index (Linter) schweigt die Regel.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.UnresolvedNames;

type
  TUnresolvedIdentifierRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

function TUnresolvedIdentifierRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('unresolved-identifier', TRuleSeverity.Warning,
    'Bezeichner ist im Projekt und seinen Units nicht deklariert (wie Compilerfehler E2003).');
end;

procedure TUnresolvedIdentifierRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Resolver: TNameResolver;
  Name: TUnresolvedName;
begin
  if (AContext.Tree = nil) or not TUnresolvedNames.Available(AContext.Index) then
    Exit;
  Resolver := TNameResolver.Create(AContext.Index, AContext.EnsureUnit);
  try
    Resolver.Namespaces := AContext.Namespaces;
    for Name in TUnresolvedNames.Find(Resolver, AContext.Tree, AContext.RelativePath) do
      AReport.Add(Name.Range, Format('"%s" ist nicht deklariert', [Name.Name]), TRuleConfidence.Medium);
  finally
    Resolver.Free;
  end;
end;

procedure RegisterUnresolvedRules(ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TUnresolvedIdentifierRule.Create);
end;

end.
