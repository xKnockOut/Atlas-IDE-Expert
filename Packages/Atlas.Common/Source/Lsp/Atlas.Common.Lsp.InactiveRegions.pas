unit Atlas.Common.Lsp.InactiveRegions;

// Inaktive Bereiche der bedingten Kompilierung ({$IFDEF} usw.) einer Datei
// für das Abblenden im Editor. Ein Bereich reicht vom Ende der Direktive,
// die den Zweig abschaltet, bis zur nächsten wirksamen Direktive. Bereiche
// aus Include-Dateien gehören nicht zur Datei selbst und entfallen.
// Mit Resolver (#264) werden $I-Dateien gelesen, sodass dort gesetzte
// Symbole wirken; fehlende Includes und Zyklen kommen als Befunde zurück.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor;

type
  TLspInactiveRegions = record
  public
    /// <summary>Inaktive Zeilenbereiche in AText für die Symbole ADefines.</summary>
    class function Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>; overload; static;
    /// <summary>Wie oben mit Include-Auflösung. AIssues erhält die Include-Befunde, auch aus
    /// eingebundenen Dateien, je $I-Direktive der Datei höchstens einen (Range = RootRange).</summary>
    class function Ranges(const AText: string; const ADefines: TArray<string>; const AFileName: string;
      const AResolver: TIncludeResolver; out AIssues: TArray<TPreprocessorIssue>): TArray<TTextRange>; overload; static;
  end;

implementation

class function TLspInactiveRegions.Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Result := Ranges(AText, ADefines, '', nil, Issues);
end;

class function TLspInactiveRegions.Ranges(const AText: string; const ADefines: TArray<string>; const AFileName: string;
  const AResolver: TIncludeResolver; out AIssues: TArray<TPreprocessorIssue>): TArray<TTextRange>;
var
  Options: TPreprocessorOptions;
  Processed: TPreprocessorResult;
  Inactive: TInactiveRange;
  Range: TTextRange;
  Issue, Known: TPreprocessorIssue;
  Duplicate: Boolean;
begin
  Result := nil;
  AIssues := nil;
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Options.FileName := AFileName;
  Options.ResolveInclude := AResolver;
  Processed := TPascalPreprocessor.Process(AText, Options);
  // Ohne Resolver wäre jedes $I "nicht gefunden"; dann nichts melden.
  if Assigned(AResolver) then
    for Issue in Processed.Issues do
      if Issue.Kind <> TPreprocessorIssueKind.General then
      begin
        Duplicate := False;
        for Known in AIssues do
          Duplicate := Duplicate or (Known.Range.StartPos = Issue.RootRange.StartPos);
        if Duplicate then
          Continue;
        AIssues := AIssues + [Issue];
        AIssues[High(AIssues)].Range := Issue.RootRange;
        // Befund aus einer eingebundenen Datei: Ort in der .inc nennen.
        if Issue.FileIndex <> 0 then
          AIssues[High(AIssues)].Message := Format('%s (in %s, Zeile %d)',
            [Issue.Message, ExtractFileName(Processed.Files[Issue.FileIndex]), Issue.Range.StartPos.Line + 1]);
        AIssues[High(AIssues)].FileIndex := 0;
      end;
  for Inactive in Processed.InactiveRanges do
  begin
    if Inactive.FileIndex <> 0 then
      Continue;
    Range := Inactive.Range;
    // Leere Bereiche ({$IFDEF X}{$ENDIF}) nicht melden.
    if Range.StartPos = Range.EndPos then
      Continue;
    Result := Result + [Range];
  end;
end;

end.
