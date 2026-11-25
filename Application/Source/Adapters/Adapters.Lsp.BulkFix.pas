unit Adapters.Lsp.BulkFix;

// Host-Adapter zwischen Rules und Lsp: atlas.server.fixFindings fragt ILspBulkFix; die Sammelkorrektur liefern die
// Prüfregeln über IRuleWorkspaceBulkFix. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Rules.Contract.Api;

type
  /// <summary>ILspBulkFix über die API der Prüfregeln.</summary>
  TLspBulkFixAdapter = class(TInterfacedObject, ILspBulkFix)
  private
    FBulkFix: IRuleWorkspaceBulkFix;
  public
    constructor Create(const ABulkFix: IRuleWorkspaceBulkFix);
    function Run(const AFileNames: TArray<string>; const AFixRules: TArray<string>; const AMinConfidence: string;
      out ARun: TLspBulkFixRun; out AError: string): Boolean;
    /// <summary>Adapter über ABulkFix; nil ohne.</summary>
    class function Wrap(const ABulkFix: IRuleWorkspaceBulkFix): ILspBulkFix; static;
  end;

implementation

/// <summary>Ergebnis einer Datei für den Sprachserver.</summary>
function FileOf(const AOutput: TRuleBulkFixOutput): TLspBulkFixFile;
var
  mIndex: Integer;
begin
  Result := Default(TLspBulkFixFile);
  Result.FileName := AOutput.FileName;
  Result.OldText := AOutput.OldText;
  Result.NewText := AOutput.NewText;
  Result.Changed := AOutput.Changed;
  Result.Rejected := AOutput.Rejected;
  Result.FixCount := AOutput.FixCount;
  SetLength(Result.Applied, Length(AOutput.Applied));
  for mIndex := 0 to High(AOutput.Applied) do
  begin
    Result.Applied[mIndex].RuleId := AOutput.Applied[mIndex].RuleId;
    Result.Applied[mIndex].Count := AOutput.Applied[mIndex].Count;
  end;
  Result.Diff := AOutput.Diff;
end;

constructor TLspBulkFixAdapter.Create(const ABulkFix: IRuleWorkspaceBulkFix);
begin
  inherited Create;
  FBulkFix := ABulkFix;
end;

function TLspBulkFixAdapter.Run(const AFileNames: TArray<string>; const AFixRules: TArray<string>;
  const AMinConfidence: string; out ARun: TLspBulkFixRun; out AError: string): Boolean;
var
  mRun: TRuleBulkFixRun;
  mIndex: Integer;
begin
  ARun := Default(TLspBulkFixRun);
  Result := FBulkFix.Run(AFileNames, AFixRules, AMinConfidence, mRun, AError);
  if not Result then
  begin
    Exit;
  end;
  SetLength(ARun.Files, Length(mRun.Files));
  for mIndex := 0 to High(mRun.Files) do
  begin
    ARun.Files[mIndex] := FileOf(mRun.Files[mIndex]);
  end;
  ARun.Summary := mRun.PreviewSummary;
end;

class function TLspBulkFixAdapter.Wrap(const ABulkFix: IRuleWorkspaceBulkFix): ILspBulkFix;
begin
  Result := nil;
  if ABulkFix <> nil then
  begin
    Result := TLspBulkFixAdapter.Create(ABulkFix);
  end;
end;

end.
