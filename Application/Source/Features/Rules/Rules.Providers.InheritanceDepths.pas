unit Rules.Providers.InheritanceDepths;

// Anbieter von IRuleInheritanceDepths (Rules.Contract.Api): dieselbe Rechnung wie die Regel
// metric-inheritance-depth (TMetricRules.InheritanceDepths) über den Syntaxbaum aus dem Zwischenspeicher.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Rules.Contract.Api;

type
  TRuleInheritanceDepths = class(TInterfacedObject, IRuleInheritanceDepths)
  public
    function Depths(const AFileName, AText: string; const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Rules.Builtin.Metrics;

{ TRuleInheritanceDepths }

function TRuleInheritanceDepths.Depths(const AFileName, AText: string;
  const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TMetricRules.InheritanceDepths(mTree, AIndex, TIndexExtractor.Extract(mTree, AFileName));
  finally
    mTree.Free;
  end;
end;

end.
