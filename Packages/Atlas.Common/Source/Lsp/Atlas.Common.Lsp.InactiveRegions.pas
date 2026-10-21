unit Atlas.Common.Lsp.InactiveRegions;

// Inaktive Bereiche der bedingten Kompilierung ({$IFDEF} usw.) einer Datei
// für das Abblenden im Editor. Ein Bereich reicht vom Ende der Direktive,
// die den Zweig abschaltet, bis zur nächsten wirksamen Direktive. Bereiche
// aus Include-Dateien gehören nicht zur Datei selbst und entfallen.
// Mit Resolver (#264) werden $I-Dateien gelesen, sodass dort gesetzte
// Symbole wirken; fehlende Includes und Zyklen kommen als Befunde zurück.
// Regions nennt je Bereich die Bedingung des Zweigs (#476), für den Hinweis
// „Inaktiv: Bedingung WIN64 nicht erfüllt“ im Editor (#615).
// Aus einem fertigen Präprozessor-Lauf (#860, etwa dem des gemeinsamen
// Editor-Baums) entstehen die Bereiche ohne zweiten Lauf.

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Preprocessor;

type
  /// <summary>Inaktiver Bereich mit der Bedingung seines Zweigs ("WIN64", "not DEBUG",
  /// "DEBUG und WIN64"); '' wenn unbekannt, etwa bei $IFOPT.</summary>
  TLspInactiveRegion = record
    Range: TTextRange;
    Condition: string;
    class function Create(const ARange: TTextRange; const ACondition: string): TLspInactiveRegion; static;
  end;

  TLspInactiveRegions = record
  public
    /// <summary>Inaktive Zeilenbereiche in AText für die Symbole ADefines.</summary>
    class function Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>; overload; static;
    /// <summary>Wie oben mit Include-Auflösung. AIssues erhält die Include-Befunde, auch aus
    /// eingebundenen Dateien, je $I-Direktive der Datei höchstens einen (Range = RootRange).</summary>
    class function Ranges(const AText: string; const ADefines: TArray<string>; const AFileName: string;
      const AResolver: TIncludeResolver; out AIssues: TArray<TPreprocessorIssue>): TArray<TTextRange>; overload; static;
    /// <summary>Wie Ranges, je Bereich mit der Bedingung des Zweigs.</summary>
    class function Regions(const AText: string; const ADefines: TArray<string>): TArray<TLspInactiveRegion>;
      overload; static;
    class function Regions(const AText: string; const ADefines: TArray<string>; const AFileName: string;
      const AResolver: TIncludeResolver; out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>;
      overload; static;
    /// <summary>Wie oben aus dem Lauf AProcessed (#860); Include-Befunde nur mit AReportIncludes (der Lauf hatte
    /// einen Resolver; ohne wäre jedes $I "nicht gefunden").</summary>
    class function Regions(const AProcessed: TPreprocessorResult; AReportIncludes: Boolean;
      out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>; overload; static;
    /// <summary>Nur die Bereiche, etwa für die Prüfung der Sprachmerkmale.</summary>
    class function RangesOf(const ARegions: TArray<TLspInactiveRegion>): TArray<TTextRange>; static;
    /// <summary>Bereiche ohne Bedingung.</summary>
    class function FromRanges(const ARanges: TArray<TTextRange>): TArray<TLspInactiveRegion>; static;
  end;

implementation

{ TLspInactiveRegion }

class function TLspInactiveRegion.Create(const ARange: TTextRange; const ACondition: string): TLspInactiveRegion;
begin
  Result.Range := ARange;
  Result.Condition := ACondition;
end;

{ TLspInactiveRegions }

class function TLspInactiveRegions.Ranges(const AText: string; const ADefines: TArray<string>): TArray<TTextRange>;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Result := Ranges(AText, ADefines, '', nil, Issues);
end;

class function TLspInactiveRegions.Ranges(const AText: string; const ADefines: TArray<string>; const AFileName: string;
  const AResolver: TIncludeResolver; out AIssues: TArray<TPreprocessorIssue>): TArray<TTextRange>;
begin
  Result := RangesOf(Regions(AText, ADefines, AFileName, AResolver, AIssues));
end;

class function TLspInactiveRegions.Regions(const AText: string;
  const ADefines: TArray<string>): TArray<TLspInactiveRegion>;
var
  Issues: TArray<TPreprocessorIssue>;
begin
  Result := Regions(AText, ADefines, '', nil, Issues);
end;

class function TLspInactiveRegions.RangesOf(const ARegions: TArray<TLspInactiveRegion>): TArray<TTextRange>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ARegions));
  for Index := 0 to High(ARegions) do
    Result[Index] := ARegions[Index].Range;
end;

class function TLspInactiveRegions.FromRanges(const ARanges: TArray<TTextRange>): TArray<TLspInactiveRegion>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ARanges));
  for Index := 0 to High(ARanges) do
    Result[Index] := TLspInactiveRegion.Create(ARanges[Index], '');
end;

class function TLspInactiveRegions.Regions(const AText: string; const ADefines: TArray<string>;
  const AFileName: string; const AResolver: TIncludeResolver;
  out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>;
var
  Options: TPreprocessorOptions;
begin
  Options := TPreprocessorOptions.Default;
  Options.Defines := ADefines;
  Options.FileName := AFileName;
  Options.ResolveInclude := AResolver;
  Result := Regions(TPascalPreprocessor.Process(AText, Options), Assigned(AResolver), AIssues);
end;

class function TLspInactiveRegions.Regions(const AProcessed: TPreprocessorResult; AReportIncludes: Boolean;
  out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>;
var
  Inactive: TInactiveRange;
  Conditional: TConditionalRange;
  Range: TTextRange;
  Condition: string;
  Issue, Known: TPreprocessorIssue;
  Duplicate: Boolean;
begin
  Result := nil;
  AIssues := nil;
  // Ohne Resolver wäre jedes $I "nicht gefunden"; dann nichts melden.
  if AReportIncludes then
    for Issue in AProcessed.Issues do
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
            [Issue.Message, ExtractFileName(AProcessed.Files[Issue.FileIndex]), Issue.Range.StartPos.Line + 1]);
        AIssues[High(AIssues)].FileIndex := 0;
      end;
  for Inactive in AProcessed.InactiveRanges do
  begin
    if Inactive.FileIndex <> 0 then
      Continue;
    Range := Inactive.Range;
    // Leere Bereiche ({$IFDEF X}{$ENDIF}) nicht melden.
    if Range.StartPos = Range.EndPos then
      Continue;
    // Der Bereich beginnt hinter der Direktive, die den Zweig abschaltet, wie der Zweig selbst.
    Condition := '';
    for Conditional in AProcessed.Conditionals do
      if (Conditional.FileIndex = 0) and not Conditional.Active and (Conditional.Range.StartPos = Range.StartPos) then
      begin
        Condition := Conditional.Condition;
        Break;
      end;
    Result := Result + [TLspInactiveRegion.Create(Range, Condition)];
  end;
end;

end.
