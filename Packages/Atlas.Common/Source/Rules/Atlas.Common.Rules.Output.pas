unit Atlas.Common.Rules.Output;

// Ausgabe des Kommandozeilen-Linters als Text, JSON oder SARIF 2.1.0 und
// Exit-Code nach dem höchsten Schweregrad. Positionen in Text und SARIF
// beginnen bei 1, im JSON wie im LSP bei 0.

interface

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Checker;

type
  TFindingsFormat = (Text, Json, Sarif);

  TFindingsOutput = class
  public const
    ExitClean = 0;
    ExitWarnings = 1;
    ExitErrors = 2;
    /// <summary>Aufruf- oder Lesefehler, vergibt der Aufrufer.</summary>
    ExitFailure = 3;
  public
    class function TryParseFormat(const AText: string; out AFormat: TFindingsFormat): Boolean; static;
    class function Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
      const ARules: TArray<TRuleDescriptor>): string; static;
    /// <summary>2 bei Fehlern, 1 bei Warnungen, sonst 0.</summary>
    class function ExitCode(const AFiles: TArray<TCheckedFile>): Integer; static;
    class function SeverityName(ASeverity: TRuleSeverity): string; static;
    class function JsonString(const AText: string): string; static;
  end;

implementation

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Product.Version,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Catalog.Data;

class function TFindingsOutput.TryParseFormat(const AText: string; out AFormat: TFindingsFormat): Boolean;
var
  Value: string;
begin
  Value := LowerCase(Trim(AText));
  Result := True;
  if Value = 'text' then
    AFormat := TFindingsFormat.Text
  else if Value = 'json' then
    AFormat := TFindingsFormat.Json
  else if Value = 'sarif' then
    AFormat := TFindingsFormat.Sarif
  else
  begin
    AFormat := TFindingsFormat.Text;
    Result := False;
  end;
end;

class function TFindingsOutput.SeverityName(ASeverity: TRuleSeverity): string;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := 'error';
    TRuleSeverity.Warning:
      Result := 'warning';
    TRuleSeverity.Information:
      Result := 'info';
  else
    Result := 'hint';
  end;
end;

function SarifLevel(ASeverity: TRuleSeverity): string;
begin
  case ASeverity of
    TRuleSeverity.Error:
      Result := 'error';
    TRuleSeverity.Warning:
      Result := 'warning';
  else
    Result := 'note';
  end;
end;

function ConfidenceName(AConfidence: TRuleConfidence): string;
begin
  case AConfidence of
    TRuleConfidence.Low:
      Result := 'low';
    TRuleConfidence.Medium:
      Result := 'medium';
  else
    Result := 'high';
  end;
end;

class function TFindingsOutput.JsonString(const AText: string): string;
var
  Builder: TStringBuilder;
  C: Char;
begin
  Builder := TStringBuilder.Create;
  try
    Builder.Append('"');
    for C in AText do
      case C of
        '"':
          Builder.Append('\"');
        '\':
          Builder.Append('\\');
        #8:
          Builder.Append('\b');
        #9:
          Builder.Append('\t');
        #10:
          Builder.Append('\n');
        #12:
          Builder.Append('\f');
        #13:
          Builder.Append('\r');
      else
        if Ord(C) < 32 then
          Builder.Append('\u' + IntToHex(Ord(C), 4))
        else
          Builder.Append(C);
      end;
    Builder.Append('"');
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function UriPath(const APath: string): string;
begin
  Result := StringReplace(APath, '\', '/', [rfReplaceAll]);
end;

function RenderText(const AFiles: TArray<TCheckedFile>): string;
var
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  Count, FilesWithFindings: Integer;
begin
  Builder := TStringBuilder.Create;
  try
    Count := 0;
    FilesWithFindings := 0;
    for CheckedFile in AFiles do
    begin
      if Length(CheckedFile.Findings) > 0 then
        Inc(FilesWithFindings);
      for Finding in CheckedFile.Findings do
      begin
        Inc(Count);
        Builder.Append(Format('%s(%d,%d): %s %s: %s', [CheckedFile.Path, Finding.Range.StartPos.Line + 1,
          Finding.Range.StartPos.Character + 1, TFindingsOutput.SeverityName(Finding.Severity), Finding.RuleId,
          Finding.DisplayMessage]));
        Builder.Append(sLineBreak);
      end;
    end;
    Builder.Append(Format('%d Treffer in %d von %d Dateien', [Count, FilesWithFindings, Length(AFiles)]));
    Builder.Append(sLineBreak);
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function JsonPosition(const APos: TTextPosition): string;
begin
  Result := Format('{"line":%d,"character":%d}', [APos.Line, APos.Character]);
end;

function RenderJson(const AFiles: TArray<TCheckedFile>): string;
var
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  FirstFile, FirstFinding: Boolean;
  Counts: array[TRuleSeverity] of Integer;
  Severity: TRuleSeverity;
begin
  for Severity := Low(TRuleSeverity) to High(TRuleSeverity) do
    Counts[Severity] := 0;
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"files":[');
    FirstFile := True;
    for CheckedFile in AFiles do
    begin
      if not FirstFile then
        Builder.Append(',');
      FirstFile := False;
      Builder.Append('{"path":').Append(TFindingsOutput.JsonString(UriPath(CheckedFile.Path))).Append(',"findings":[');
      FirstFinding := True;
      for Finding in CheckedFile.Findings do
      begin
        Inc(Counts[Finding.Severity]);
        if not FirstFinding then
          Builder.Append(',');
        FirstFinding := False;
        Builder.Append('{"rule":').Append(TFindingsOutput.JsonString(Finding.RuleId));
        Builder.Append(',"severity":').Append(TFindingsOutput.JsonString(TFindingsOutput.SeverityName(Finding.Severity)));
        Builder.Append(',"confidence":').Append(TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence)));
        Builder.Append(',"message":').Append(TFindingsOutput.JsonString(Finding.Message));
        Builder.Append(',"range":{"start":').Append(JsonPosition(Finding.Range.StartPos));
        Builder.Append(',"end":').Append(JsonPosition(Finding.Range.EndPos)).Append('}}');
      end;
      Builder.Append(']}');
    end;
    Builder.Append(Format('],"summary":{"files":%d,"errors":%d,"warnings":%d,"information":%d,"hints":%d}}',
      [Length(AFiles), Counts[TRuleSeverity.Error], Counts[TRuleSeverity.Warning],
      Counts[TRuleSeverity.Information], Counts[TRuleSeverity.Hint]]));
    Result := Builder.ToString;
  finally
    Builder.Free;
  end;
end;

function RenderSarif(const AFiles: TArray<TCheckedFile>; const ARules: TArray<TRuleDescriptor>): string;
var
  Builder: TStringBuilder;
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
  Rule: TRuleDescriptor;
  Entry: TRuleCatalogEntry;
  Catalog: TRuleCatalog;
  First: Boolean;
begin
  // Immer der englische Katalog: stabile Texte für GitHub Code Scanning.
  Catalog := TRuleCatalog.Create(RuleCatalogBaseJson);
  Builder := TStringBuilder.Create;
  try
    Builder.Append('{"$schema":"https://json.schemastore.org/sarif-2.1.0.json","version":"2.1.0","runs":[{');
    Builder.Append('"tool":{"driver":{"name":').Append(TFindingsOutput.JsonString(TProductVersion.Name));
    Builder.Append(',"version":').Append(TFindingsOutput.JsonString(TProductVersion.Version));
    Builder.Append(',"informationUri":"https://github.com/xKnockOut/Atlas-IDE-Expert","rules":[');
    First := True;
    for Rule in ARules do
    begin
      if not First then
        Builder.Append(',');
      First := False;
      Builder.Append('{"id":').Append(TFindingsOutput.JsonString(Rule.Id));
      if Catalog.TryFind(Rule.Id, Entry) then
      begin
        Builder.Append(',"name":').Append(TFindingsOutput.JsonString(Entry.Name));
        Builder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(Entry.Name));
        Builder.Append('},"fullDescription":{"text":').Append(TFindingsOutput.JsonString(Entry.Description));
        Builder.Append('},"properties":{"tags":[').Append(TFindingsOutput.JsonString(TRuleCatalog.CategoryName(Entry.Category)));
        Builder.Append(']}');
      end
      else
        Builder.Append(',"shortDescription":{"text":').Append(TFindingsOutput.JsonString(Rule.Description)).Append('}');
      Builder.Append(',"helpUri":').Append(TFindingsOutput.JsonString(TRuleCatalog.HelpUri(Rule.Id)));
      Builder.Append(',"defaultConfiguration":{"level":').Append(TFindingsOutput.JsonString(SarifLevel(Rule.DefaultSeverity)));
      Builder.Append('}}');
    end;
    Builder.Append(']}},"results":[');
    First := True;
    for CheckedFile in AFiles do
      for Finding in CheckedFile.Findings do
      begin
        if not First then
          Builder.Append(',');
        First := False;
        Builder.Append('{"ruleId":').Append(TFindingsOutput.JsonString(Finding.RuleId));
        Builder.Append(',"level":').Append(TFindingsOutput.JsonString(SarifLevel(Finding.Severity)));
        Builder.Append(',"message":{"text":').Append(TFindingsOutput.JsonString(Finding.DisplayMessage));
        Builder.Append('},"locations":[{"physicalLocation":{"artifactLocation":{"uri":');
        Builder.Append(TFindingsOutput.JsonString(UriPath(CheckedFile.Path)));
        Builder.Append(Format('},"region":{"startLine":%d,"startColumn":%d,"endLine":%d,"endColumn":%d}}}]',
          [Finding.Range.StartPos.Line + 1, Finding.Range.StartPos.Character + 1,
          Finding.Range.EndPos.Line + 1, Finding.Range.EndPos.Character + 1]));
        Builder.Append(',"properties":{"confidence":').Append(TFindingsOutput.JsonString(ConfidenceName(Finding.Confidence)));
        Builder.Append('}}');
      end;
    Builder.Append(']}]}');
    Result := Builder.ToString;
  finally
    Builder.Free;
    Catalog.Free;
  end;
end;

class function TFindingsOutput.Render(const AFiles: TArray<TCheckedFile>; AFormat: TFindingsFormat;
  const ARules: TArray<TRuleDescriptor>): string;
begin
  case AFormat of
    TFindingsFormat.Json:
      Result := RenderJson(AFiles);
    TFindingsFormat.Sarif:
      Result := RenderSarif(AFiles, ARules);
  else
    Result := RenderText(AFiles);
  end;
end;

class function TFindingsOutput.ExitCode(const AFiles: TArray<TCheckedFile>): Integer;
var
  CheckedFile: TCheckedFile;
  Finding: TRuleFinding;
begin
  Result := ExitClean;
  for CheckedFile in AFiles do
    for Finding in CheckedFile.Findings do
      if Finding.Severity = TRuleSeverity.Error then
        Exit(ExitErrors)
      else if Finding.Severity = TRuleSeverity.Warning then
        Result := ExitWarnings;
end;

end.
