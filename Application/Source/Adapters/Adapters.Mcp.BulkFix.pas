unit Adapters.Mcp.BulkFix;

// Host-Adapter zwischen Mcp und Rules: fix_findings holt die Sammelkorrektur über IMcpBulkFix, Rules bietet sie über
// IRuleBulkFix an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Contract.BulkFix,
  Rules.Contract.Api;

type
  TMcpBulkFixAdapter = class(TInterfacedObject, IMcpBulkFix)
  private
    FBulkFix: IRuleBulkFix;
  public
    constructor Create(const ABulkFix: IRuleBulkFix);
    function Run(const AFiles: TArray<TMcpFixInput>; const AFixRules: TArray<string>; const AMinConfidence: string;
      const ASettings: TServerSettings; out ARun: TMcpFixRun; out AError: string): Boolean;
  end;

implementation

{ TMcpBulkFixAdapter }

constructor TMcpBulkFixAdapter.Create(const ABulkFix: IRuleBulkFix);
begin
  inherited Create;
  FBulkFix := ABulkFix;
end;

function TMcpBulkFixAdapter.Run(const AFiles: TArray<TMcpFixInput>; const AFixRules: TArray<string>;
  const AMinConfidence: string; const ASettings: TServerSettings; out ARun: TMcpFixRun; out AError: string): Boolean;
var
  mInputs: TArray<TRuleBulkFixInput>;
  mRun: TRuleBulkFixRun;
  mIndex: Integer;
begin
  ARun := Default(TMcpFixRun);
  mInputs := nil;
  SetLength(mInputs, Length(AFiles));
  for mIndex := 0 to High(AFiles) do
  begin
    mInputs[mIndex].FileName := AFiles[mIndex].FileName;
    mInputs[mIndex].RelativePath := AFiles[mIndex].RelativePath;
    mInputs[mIndex].Text := AFiles[mIndex].Text;
  end;
  Result := FBulkFix.Run(mInputs, AFixRules, AMinConfidence, ASettings, mRun, AError);
  if not Result then
  begin
    Exit;
  end;
  SetLength(ARun.Files, Length(mRun.Files));
  for mIndex := 0 to High(mRun.Files) do
  begin
    ARun.Files[mIndex].FileName := mRun.Files[mIndex].FileName;
    ARun.Files[mIndex].OldText := mRun.Files[mIndex].OldText;
    ARun.Files[mIndex].NewText := mRun.Files[mIndex].NewText;
    ARun.Files[mIndex].Changed := mRun.Files[mIndex].Changed;
    ARun.Files[mIndex].Diff := mRun.Files[mIndex].Diff;
  end;
  ARun.PreviewSummary := mRun.PreviewSummary;
  ARun.WrittenSummary := mRun.WrittenSummary;
end;

end.
