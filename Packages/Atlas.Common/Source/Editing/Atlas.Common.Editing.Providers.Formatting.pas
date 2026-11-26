unit Atlas.Common.Editing.Providers.Formatting;

// IEditingFormatting über TFormatCheck.Run und TFormatStyles.Resolve.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Editing.Contract.Formatting;

type
  TEditingFormattingProvider = class(TInterfacedObject, IEditingFormatting)
  public
    function Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
    function StyleOf(const AFileName: string; const AConfigured: TFormatStyle): TFormatStyle;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Projects.EditorConfig,
  Atlas.Common.Formatting.Outcome,
  Atlas.Common.Editing.FormatCheck;

/// <summary>.editorconfig von der Platte; False, wenn es die Datei nicht gibt oder sie nicht lesbar ist.</summary>
function ReadConfigFile: TEditorConfigReadFile;
begin
  Result :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := FileExists(AFileName) and TFileEncoding.TryLoadText(AFileName, AText);
    end;
end;

function ScopeOf(const ARequest: TEditingFormatRequest): TFormatScope;
begin
  if ARequest.WholeFile then
  begin
    Exit(TFormatScope.All);
  end;
  Result := TFormatScope.Lines([TFormatLineSpan.Create(ARequest.FirstLine, ARequest.LastLine)]);
end;

{ TEditingFormattingProvider }

function TEditingFormattingProvider.Check(const ARequest: TEditingFormatRequest): TEditingFormatResult;
var
  mOutcome: TFormatOutcome;
  mIndex: Integer;
begin
  mOutcome := TFormatCheck.Run(ARequest.Text, ARequest.Style, ScopeOf(ARequest),
    TPascalPreprocessor.SourceOptions(ARequest.Source));
  Result := Default(TEditingFormatResult);
  Result.Formatted := mOutcome.Formatted;
  Result.Changed := mOutcome.Changed;
  Result.HasSyntaxError := mOutcome.HasSyntaxError;
  Result.SyntaxErrorLine := mOutcome.SyntaxError.StartPos.Line;
  Result.SyntaxErrorMessage := mOutcome.SyntaxError.Message;
  Result.Stable := mOutcome.Stable;
  SetLength(Result.Deviations, Length(mOutcome.Deviations));
  for mIndex := 0 to High(mOutcome.Deviations) do
  begin
    Result.Deviations[mIndex].Line := mOutcome.Deviations[mIndex].Line;
    Result.Deviations[mIndex].Message := mOutcome.Deviations[mIndex].Message;
  end;
end;

function TEditingFormattingProvider.StyleOf(const AFileName: string; const AConfigured: TFormatStyle): TFormatStyle;
begin
  Result := TFormatStyles.Resolve(nil, AFileName, AConfigured, ReadConfigFile());
end;

end.
