unit Adapters.Mcp.BoundaryCases;

// Host-Adapter zwischen Mcp und Editing: suggest_test_cases fragt über IMcpBoundaryCases, Editing bietet den
// Bericht über IEditingBoundaryCases an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Mcp.Contract.BoundaryCases,
  Atlas.Common.Editing.Contract.BoundaryCases;

type
  TMcpBoundaryCasesAdapter = class(TInterfacedObject, IMcpBoundaryCases)
  private
    FBoundaryCases: IEditingBoundaryCases;
  public
    constructor Create(const ABoundaryCases: IEditingBoundaryCases);
    function Report(const AText: string; const ARequest: TMcpBoundaryRequest; out AReport: string): Boolean;
  end;

implementation

{ TMcpBoundaryCasesAdapter }

constructor TMcpBoundaryCasesAdapter.Create(const ABoundaryCases: IEditingBoundaryCases);
begin
  inherited Create;
  FBoundaryCases := ABoundaryCases;
end;

function TMcpBoundaryCasesAdapter.Report(const AText: string; const ARequest: TMcpBoundaryRequest;
  out AReport: string): Boolean;
var
  mRequest: TEditingBoundaryRequest;
begin
  mRequest := Default(TEditingBoundaryRequest);
  mRequest.Text := AText;
  mRequest.FileName := ARequest.FileName;
  mRequest.Line := ARequest.Line;
  mRequest.Routine := ARequest.Routine;
  mRequest.Max := ARequest.Max;
  mRequest.Json := ARequest.Json;
  Result := FBoundaryCases.Report(mRequest, AReport);
end;

end.
