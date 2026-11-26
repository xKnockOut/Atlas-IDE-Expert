unit Atlas.Common.Editing.Providers.BoundaryCases;

// IEditingBoundaryCases über TBoundaryCaseReports.Report.

interface

uses
  Atlas.Common.Editing.Contract.BoundaryCases;

type
  TEditingBoundaryCasesProvider = class(TInterfacedObject, IEditingBoundaryCases)
  public
    function Report(const ARequest: TEditingBoundaryRequest; out AReport: string): Boolean;
  end;

implementation

uses
  Atlas.Common.Editing.BoundaryCases.Report;

{ TEditingBoundaryCasesProvider }

function TEditingBoundaryCasesProvider.Report(const ARequest: TEditingBoundaryRequest; out AReport: string): Boolean;
var
  mRequest: TBoundaryCaseRequest;
begin
  mRequest := Default(TBoundaryCaseRequest);
  mRequest.FileName := ARequest.FileName;
  mRequest.Line := ARequest.Line;
  mRequest.Routine := ARequest.Routine;
  mRequest.Max := ARequest.Max;
  mRequest.Json := ARequest.Json;
  Result := TBoundaryCaseReports.Report(ARequest.Text, mRequest, AReport);
end;

end.
