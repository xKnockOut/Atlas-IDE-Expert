unit Adapters.Checks.IdeTypes;

// Host-Adapter zwischen Lsp und Rules: Die Prüfregeln fragen über ICheckIdeTypes, in welchen Units die laufende
// IDE einen Typ kennt; der Sprachserver hält diese Typen (atlas/ideTypes) und bietet sie über ILspIdeTypes an.
// Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Lsp.Contract,
  Atlas.Common.Checks.Contract;

type
  /// <summary>ICheckIdeTypes über die Typen der IDE aus dem Sprachserver.</summary>
  TCheckIdeTypesAdapter = class(TInterfacedObject, ICheckIdeTypes)
  private
    FTypes: ILspIdeTypes;
  public
    /// <summary>ATypes: Typen der IDE; nil = keine bekannt.</summary>
    constructor Create(const ATypes: ILspIdeTypes);
    function UnitsOf(const ATypeName: string): TArray<string>;
    /// <summary>Adapter über ATypes; nil ohne Typen.</summary>
    class function Wrap(const ATypes: ILspIdeTypes): ICheckIdeTypes; static;
  end;

implementation

{ TCheckIdeTypesAdapter }

constructor TCheckIdeTypesAdapter.Create(const ATypes: ILspIdeTypes);
begin
  inherited Create;
  FTypes := ATypes;
end;

function TCheckIdeTypesAdapter.UnitsOf(const ATypeName: string): TArray<string>;
begin
  Result := nil;
  if FTypes <> nil then
  begin
    Result := FTypes.UnitsOf(ATypeName);
  end;
end;

class function TCheckIdeTypesAdapter.Wrap(const ATypes: ILspIdeTypes): ICheckIdeTypes;
begin
  Result := nil;
  if ATypes <> nil then
  begin
    Result := TCheckIdeTypesAdapter.Create(ATypes);
  end;
end;

end.
