unit Adapters.Rules.IdeTypes;

// Host-Adapter zwischen Lsp und Rules: Die Prüfregeln fragen über IRuleIdeTypes, in welchen Units die laufende
// IDE einen Typ kennt; der Sprachserver hält diese Typen (atlas/ideTypes) und bietet sie über ILspIdeTypes an.
// Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Lsp.Contract;

type
  /// <summary>IRuleIdeTypes über die Typen der IDE aus dem Sprachserver.</summary>
  TRuleIdeTypesAdapter = class(TInterfacedObject, IRuleIdeTypes)
  private
    FTypes: ILspIdeTypes;
  public
    /// <summary>ATypes: Typen der IDE; nil = keine bekannt.</summary>
    constructor Create(const ATypes: ILspIdeTypes);
    function UnitsOf(const ATypeName: string): TArray<string>;
    /// <summary>Adapter über ATypes; nil ohne Typen.</summary>
    class function Wrap(const ATypes: ILspIdeTypes): IRuleIdeTypes; static;
  end;

implementation

{ TRuleIdeTypesAdapter }

constructor TRuleIdeTypesAdapter.Create(const ATypes: ILspIdeTypes);
begin
  inherited Create;
  FTypes := ATypes;
end;

function TRuleIdeTypesAdapter.UnitsOf(const ATypeName: string): TArray<string>;
begin
  Result := nil;
  if FTypes <> nil then
  begin
    Result := FTypes.UnitsOf(ATypeName);
  end;
end;

class function TRuleIdeTypesAdapter.Wrap(const ATypes: ILspIdeTypes): IRuleIdeTypes;
begin
  Result := nil;
  if ATypes <> nil then
  begin
    Result := TRuleIdeTypesAdapter.Create(ATypes);
  end;
end;

end.
