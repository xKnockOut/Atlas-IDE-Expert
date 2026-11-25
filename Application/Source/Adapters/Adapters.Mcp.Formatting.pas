unit Adapters.Mcp.Formatting;

// Host-Adapter zwischen Mcp und Editing: format_code formatiert über IMcpFormatting, Editing bietet den
// Formatierer über IEditingFormatting an. Erzeugt nur in Shell.Composition.*; kennt nur die beiden Contracts.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Mcp.Contract.Formatting,
  Atlas.Common.Editing.Contract.Formatting;

type
  TMcpFormattingAdapter = class(TInterfacedObject, IMcpFormatting)
  private
    FFormatting: IEditingFormatting;
  public
    constructor Create(const AFormatting: IEditingFormatting);
    function Format(const AText: string; const AStyle: TFormatStyle; const ALines: TMcpFormatLines;
      const ASource: TPascalSource): TMcpFormatOutcome;
  end;

implementation

{ TMcpFormattingAdapter }

constructor TMcpFormattingAdapter.Create(const AFormatting: IEditingFormatting);
begin
  inherited Create;
  FFormatting := AFormatting;
end;

function TMcpFormattingAdapter.Format(const AText: string; const AStyle: TFormatStyle;
  const ALines: TMcpFormatLines; const ASource: TPascalSource): TMcpFormatOutcome;
var
  mRequest: TEditingFormatRequest;
  mResult: TEditingFormatResult;
  mIndex: Integer;
begin
  mRequest := Default(TEditingFormatRequest);
  mRequest.Text := AText;
  mRequest.Style := AStyle;
  mRequest.Source := ASource;
  mRequest.WholeFile := ALines.WholeFile;
  mRequest.FirstLine := ALines.FirstLine;
  mRequest.LastLine := ALines.LastLine;
  mResult := FFormatting.Check(mRequest);
  Result := Default(TMcpFormatOutcome);
  Result.Formatted := mResult.Formatted;
  Result.Changed := mResult.Changed;
  Result.HasSyntaxError := mResult.HasSyntaxError;
  Result.SyntaxErrorLine := mResult.SyntaxErrorLine;
  Result.SyntaxErrorMessage := mResult.SyntaxErrorMessage;
  Result.Stable := mResult.Stable;
  SetLength(Result.Deviations, Length(mResult.Deviations));
  for mIndex := 0 to High(mResult.Deviations) do
  begin
    Result.Deviations[mIndex].Line := mResult.Deviations[mIndex].Line;
    Result.Deviations[mIndex].Message := mResult.Deviations[mIndex].Message;
  end;
end;

end.
