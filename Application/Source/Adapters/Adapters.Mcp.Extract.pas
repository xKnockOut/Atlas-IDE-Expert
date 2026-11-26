unit Adapters.Mcp.Extract;

// Host-Adapter zwischen Mcp und Editing: extract_method plant über IMcpExtract, Editing bietet „Methode
// extrahieren“ über IEditingExtract an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Documents.Contract,
  Mcp.Contract.Extract,
  Atlas.Common.Editing.Contract.Extract;

type
  TMcpExtractAdapter = class(TInterfacedObject, IMcpExtract)
  private
    FExtract: IEditingExtract;
  public
    constructor Create(const AExtract: IEditingExtract);
    function ExtractMethod(const AText: string; const ARange: TTextRange; const AWish: TMcpExtractWish):
      TMcpExtractPlan;
  end;

implementation

{ TMcpExtractAdapter }

constructor TMcpExtractAdapter.Create(const AExtract: IEditingExtract);
begin
  inherited Create;
  FExtract := AExtract;
end;

function TMcpExtractAdapter.ExtractMethod(const AText: string; const ARange: TTextRange;
  const AWish: TMcpExtractWish): TMcpExtractPlan;
var
  mWish: TEditingExtractWish;
  mResult: TEditingExtractResult;
begin
  mWish := Default(TEditingExtractWish);
  mWish.MethodName := AWish.MethodName;
  mWish.Duplicates := AWish.Duplicates;
  mWish.InlineVar := AWish.InlineVar;
  mWish.Style := AWish.Style;
  mResult := FExtract.ExtractMethod(AText, ARange, mWish);
  Result.Extracted := mResult.Extracted;
  Result.Action := mResult.Action;
  Result.Reason := mResult.Reason;
  Result.DuplicatesReason := mResult.DuplicatesReason;
end;

end.
