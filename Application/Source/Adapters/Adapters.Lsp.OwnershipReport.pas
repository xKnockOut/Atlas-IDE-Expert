unit Adapters.Lsp.OwnershipReport;

// Host-Adapter zwischen Rules und Lsp: Der Befehl atlas.server.ownership (#1877) fragt ILspOwnershipReport; die
// Antwort rechnen die Prüfregeln über IRuleOwnershipReport. Erzeugt nur in Shell.Composition.*; kennt nur die
// beiden Contracts.

interface

uses
  System.JSON,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  /// <summary>ILspOwnershipReport über die API der Prüfregeln.</summary>
  TLspOwnershipReportAdapter = class(TInterfacedObject, ILspOwnershipReport)
  private
    FReport: IRuleOwnershipReport;
  public
    constructor Create(const AReport: IRuleOwnershipReport);
    function Report(const AUri: string): TJSONObject;
    /// <summary>Adapter über AReport; nil ohne.</summary>
    class function Wrap(const AReport: IRuleOwnershipReport): ILspOwnershipReport; static;
  end;

implementation

{ TLspOwnershipReportAdapter }

constructor TLspOwnershipReportAdapter.Create(const AReport: IRuleOwnershipReport);
begin
  inherited Create;
  FReport := AReport;
end;

function TLspOwnershipReportAdapter.Report(const AUri: string): TJSONObject;
begin
  Result := FReport.Report(AUri);
end;

class function TLspOwnershipReportAdapter.Wrap(const AReport: IRuleOwnershipReport): ILspOwnershipReport;
begin
  Result := nil;
  if AReport <> nil then
  begin
    Result := TLspOwnershipReportAdapter.Create(AReport);
  end;
end;

end.
