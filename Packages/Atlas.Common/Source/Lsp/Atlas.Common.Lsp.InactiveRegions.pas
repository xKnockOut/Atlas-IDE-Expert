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

uses
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TInactiveRegionsText = (InLineText);

const
  cTexts: array[TInactiveRegionsText] of TAtlasText = (
    (De: '%s (in %s, Zeile %d)'; En: '%s (in %s, line %d)'));

{$SCOPEDENUMS OFF}

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
  begin
    Result[Index] := ARegions[Index].Range;
  end;
end;

class function TLspInactiveRegions.FromRanges(const ARanges: TArray<TTextRange>): TArray<TLspInactiveRegion>;
var
  Index: Integer;
begin
  SetLength(Result, Length(ARanges));
  for Index := 0 to High(ARanges) do
  begin
    Result[Index] := TLspInactiveRegion.Create(ARanges[Index], '');
  end;
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

/// <summary>Bedingung des abgeschalteten Zweigs, der bei AStart beginnt; leer, wenn keiner passt.</summary>
function ConditionAt(const AProcessed: TPreprocessorResult; const AStart: TTextPosition): string;
var
  mConditional: TConditionalRange;
begin
  Result := '';
  for mConditional in AProcessed.Conditionals do
  begin
    if (mConditional.FileIndex = 0) and not mConditional.Active and (mConditional.Range.StartPos = AStart) then
    begin
      Exit(mConditional.Condition);
    end;
  end;
end;

/// <summary>True, wenn AIssues schon einen Befund an der Stelle von AIssue hat.</summary>
function HasIssueAt(const AIssues: TArray<TPreprocessorIssue>; const AIssue: TPreprocessorIssue): Boolean;
var
  mKnown: TPreprocessorIssue;
begin
  Result := False;
  for mKnown in AIssues do
  begin
    Result := Result or (mKnown.Range.StartPos = AIssue.RootRange.StartPos);
  end;
end;

/// <summary>Befunde zu eingebundenen Dateien, je Stelle einmal, am Ort in der Hauptdatei.</summary>
function IncludeIssues(const AProcessed: TPreprocessorResult): TArray<TPreprocessorIssue>;
var
  mIssue: TPreprocessorIssue;
begin
  Result := nil;
  for mIssue in AProcessed.Issues do
  begin
    if (mIssue.Kind = TPreprocessorIssueKind.General) or HasIssueAt(Result, mIssue) then
    begin
      Continue;
    end;
    Result := Result + [mIssue];
    Result[High(Result)].Range := mIssue.RootRange;
    // Befund aus einer eingebundenen Datei: Ort in der .inc nennen.
    if mIssue.FileIndex <> 0 then
    begin
      Result[High(Result)].Message := cTexts[TInactiveRegionsText.InLineText].Fmt([mIssue.Message,
        ExtractFileName(AProcessed.Files[mIssue.FileIndex]), mIssue.Range.StartPos.Line + 1]);
    end;
    Result[High(Result)].FileIndex := 0;
  end;
end;

class function TLspInactiveRegions.Regions(const AProcessed: TPreprocessorResult; AReportIncludes: Boolean;
  out AIssues: TArray<TPreprocessorIssue>): TArray<TLspInactiveRegion>;
var
  mInactive: TInactiveRange;
  mRange: TTextRange;
begin
  Result := nil;
  AIssues := nil;
  // Ohne Resolver wäre jedes $I "nicht gefunden"; dann nichts melden.
  if AReportIncludes then
  begin
    AIssues := IncludeIssues(AProcessed);
  end;
  for mInactive in AProcessed.InactiveRanges do
  begin
    mRange := mInactive.Range;
    // Leere Bereiche ({$IFDEF X}{$ENDIF}) und Bereiche in eingebundenen Dateien nicht melden.
    if (mInactive.FileIndex <> 0) or (mRange.StartPos = mRange.EndPos) then
    begin
      Continue;
    end;
    // Der Bereich beginnt hinter der Direktive, die den Zweig abschaltet, wie der Zweig selbst.
    Result := Result + [TLspInactiveRegion.Create(mRange, ConditionAt(AProcessed, mRange.StartPos))];
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.InactiveRegions', cTexts);

end.
