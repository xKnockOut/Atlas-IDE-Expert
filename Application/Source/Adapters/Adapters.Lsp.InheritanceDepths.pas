unit Adapters.Lsp.InheritanceDepths;

// Host-Adapter zwischen Rules und Lsp: Code Lens und atlas.server.metrics zeigen die Vererbungstiefe (#980) über
// ILspInheritanceDepths; gerechnet wird sie wie bei der Regel metric-inheritance-depth über IRuleInheritanceDepths.
// Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Index.Contract,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Lsp.Contract,
  Rules.Contract.Api;

type
  /// <summary>ILspInheritanceDepths über die API der Prüfregeln.</summary>
  TLspInheritanceDepthsAdapter = class(TInterfacedObject, ILspInheritanceDepths)
  private
    FDepths: IRuleInheritanceDepths;
  public
    constructor Create(const ADepths: IRuleInheritanceDepths);
    function Depths(const AFileName, AText: string; const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
    /// <summary>Adapter über ADepths; nil ohne.</summary>
    class function Wrap(const ADepths: IRuleInheritanceDepths): ILspInheritanceDepths; static;
  end;

implementation

{ TLspInheritanceDepthsAdapter }

constructor TLspInheritanceDepthsAdapter.Create(const ADepths: IRuleInheritanceDepths);
begin
  inherited Create;
  FDepths := ADepths;
end;

function TLspInheritanceDepthsAdapter.Depths(const AFileName, AText: string;
  const AIndex: ISymbolIndex): TArray<TStructureMetrics>;
begin
  Result := nil;
  if FDepths <> nil then
  begin
    Result := FDepths.Depths(AFileName, AText, AIndex);
  end;
end;

class function TLspInheritanceDepthsAdapter.Wrap(const ADepths: IRuleInheritanceDepths): ILspInheritanceDepths;
begin
  Result := nil;
  if ADepths <> nil then
  begin
    Result := TLspInheritanceDepthsAdapter.Create(ADepths);
  end;
end;

end.
