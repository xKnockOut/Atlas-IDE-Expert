unit Atlas.Common.Mcp.LastTests;

// Letzter Testlauf aus der IDE für KI-Assistenten (MCP-Werkzeug get_last_tests, #2409): liest, was das Plugin nach
// jedem Lauf ablegt (Atlas.Text.TestRunFile, je Testprojekt eine Datei), ohne die Tests erneut auszuführen. Wählt den
// Lauf (Projekt oder der neueste, bevorzugt unter dem Arbeitsordner), filtert nach only (failed, flaky, slow,
// leaks, stale, all), zeigt höchstens max Tests und den Rest als Zahl, als Text oder JSON. Veraltet ist ein
// Ergebnis, wenn die Testunit nach dem Lauf gespeichert wurde oder in der IDE ungespeichert geändert ist
// (StaleUnits). Die Dateien liest die Shell; hier nur Auswahl, Auswertung und Ausgabe, damit es ohne Dateisystem
// testbar bleibt.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.TestRunFile;

type
{$SCOPEDENUMS ON}
  TMcpLastTestsFilter = (Failed, Flaky, Slow, Leaks, Stale, All);
{$SCOPEDENUMS OFF}

  TMcpLastTestsRequest = record
  public const
    cDefaultMax = 20;
    cMaxMax = 500;
  public
    Project: string;
    Only: TMcpLastTestsFilter;
    Max: Integer;
    AsJson: Boolean;
    /// <summary>Argumente von get_last_tests; EMcpToolError bei ungültigen Werten.</summary>
    class function FromArguments(const AArguments: TJSONObject): TMcpLastTestsRequest; static;
  end;

  /// <summary>Letzte Schreibzeit einer Datei in UTC; 0, wenn sie fehlt.</summary>
  TMcpFileTimeFunc = reference to function(const AFileName: string): TDateTime;

  TMcpLastTests = class
  public
    /// <summary>Lauf zu AProject (voller Pfad, Dateiname oder Name ohne Endung); ohne AProject der neueste,
    /// bevorzugt einer unter ARoot. -1 mit Grund in AReason, wenn keiner passt.</summary>
    class function Pick(const ARuns: TArray<TTestRunFile>; const ARoot, AProject: string;
      out AReason: string): Integer; static;
    /// <summary>Units von ARun, deren Datei nach dem Lauf geschrieben wurde (AFileTime) oder unter ADirty
    /// (ungespeichert in der IDE) steht.</summary>
    class function StaleUnits(const ARun: TTestRunFile; const AFileTime: TMcpFileTimeFunc;
      const ADirty: TArray<string>): TArray<string>; static;
    /// <summary>Ergebnis von get_last_tests; AStaleUnits aus StaleUnits.</summary>
    class function Report(const ARun: TTestRunFile; const AStaleUnits: TArray<string>;
      const ARequest: TMcpLastTestsRequest): string; static;
    /// <summary>Antwort, solange unter AFolder kein Lauf liegt.</summary>
    class function NoRuns(const AFolder: string): string; static;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.StrUtils,
  System.DateUtils,
  Atlas.Text.TestResults,
  Atlas.Text.Json,
  Atlas.Common.Projects.Paths,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  TLastTestsText = (NoRuns, UnknownProject, OnlyInvalid, MaxInvalid, FormatInvalid, Header, Partial, Failed,
    Flaky, Leaks, StaleCount, Fixed, NoneMatch, NewFailure, FlakyMark, LeakMark, StaleMark, Values, Log, More,
    SkippedMark, ErrorMark, Slow);

const
  cTexts: array[TLastTestsText] of TAtlasText = (
    (De: 'Noch kein Testlauf aus der IDE abgelegt. In der IDE Tests mit Atlas ausführen (Atlas-Menü, Testlinse, ' +
      'Fenster „Atlas-Tests“); die Läufe liegen unter %s. Neu laufen lassen: run_tests.';
     En: 'No test run from the IDE stored yet. Run tests with Atlas in the IDE (Atlas menu, test lens, window ' +
      '"Atlas tests"); the runs are stored under %s. To run again: run_tests.'),
    (De: 'Kein abgelegter Testlauf für „%s“. Vorhanden: %s'; En: 'No stored test run for "%s". Available: %s'),
    (De: '"only" ist failed, flaky, slow, leaks, stale oder all';
     En: '"only" is failed, flaky, slow, leaks, stale or all'),
    (De: '"max" ist eine ganze Zahl von 1 bis %d'; En: '"max" is a whole number from 1 to %d'),
    (De: '"format" ist text oder json'; En: '"format" is text or json'),
    (De: '%s · %s %s · %s · %d Tests, %d rot, %d übersprungen · %s';
     En: '%s · %s %s · %s · %d tests, %d red, %d skipped · %s'),
    (De: 'Teillauf: %s'; En: 'Partial run: %s'),
    (De: '%d rot'; En: '%d red'),
    (De: '%d wackelig'; En: '%d flaky'),
    (De: '%d mit Leck'; En: '%d with leak'),
    (De: '%d veraltet'; En: '%d stale'),
    (De: 'Wieder grün: %s'; En: 'Green again: %s'),
    (De: 'Keine Tests für only=%s.'; En: 'No tests for only=%s.'),
    (De: 'neu rot'; En: 'newly red'),
    (De: 'wackelig (%d von %d rot)'; En: 'flaky (%d of %d red)'),
    (De: 'Leck %d Byte'; En: 'leak %d bytes'),
    (De: 'veraltet (Unit seit dem Lauf geändert)'; En: 'stale (unit changed since the run)'),
    (De: 'Erwartet %s, erhalten %s'; En: 'Expected %s, actual %s'),
    (De: 'Protokoll: %s'; En: 'Log: %s'),
    (De: '… %d weitere (max)'; En: '… %d more (max)'),
    (De: 'übersprungen'; En: 'skipped'),
    (De: 'Fehler'; En: 'error'),
    (De: 'Langsamste Tests:'; En: 'Slowest tests:'));

  cFilterNames: array[TMcpLastTestsFilter] of string = ('failed', 'flaky', 'slow', 'leaks', 'stale', 'all');
  /// <summary>Höchstens so viele Namen in „Wieder grün“.</summary>
  cMaxFixedNames = 5;

{$SCOPEDENUMS OFF}

{ TMcpLastTestsRequest }

class function TMcpLastTestsRequest.FromArguments(const AArguments: TJSONObject): TMcpLastTestsRequest;
var
  mOnly, mFormat: string;
  mMax: Integer;
  mFilter: TMcpLastTestsFilter;
  mKnown: Boolean;
begin
  Result := Default(TMcpLastTestsRequest);
  Result.Max := cDefaultMax;
  // Über eine eigene Variable: Delphis TryGetValue setzt den out-Wert auch ohne Schlüssel.
  if (AArguments <> nil) and AArguments.TryGetValue<Integer>('max', mMax) then
  begin
    Result.Max := mMax;
  end;
  if (Result.Max < 1) or (Result.Max > cMaxMax) then
  begin
    raise EMcpToolError.Create(cTexts[TLastTestsText.MaxInvalid].Fmt([cMaxMax]));
  end;
  Result.Project := Trim(TMcpArgs.OptionalString(AArguments, 'project'));
  mOnly := Trim(TMcpArgs.OptionalString(AArguments, 'only'));
  Result.Only := TMcpLastTestsFilter.Failed;
  mKnown := mOnly = '';
  for mFilter := Low(TMcpLastTestsFilter) to High(TMcpLastTestsFilter) do
  begin
    if SameText(mOnly, cFilterNames[mFilter]) then
    begin
      Result.Only := mFilter;
      mKnown := True;
    end;
  end;
  if not mKnown then
  begin
    raise EMcpToolError.Create(cTexts[TLastTestsText.OnlyInvalid].Text);
  end;
  mFormat := Trim(TMcpArgs.OptionalString(AArguments, 'format'));
  if (mFormat <> '') and not SameText(mFormat, 'text') and not SameText(mFormat, 'json') then
  begin
    raise EMcpToolError.Create(cTexts[TLastTestsText.FormatInvalid].Text);
  end;
  Result.AsJson := SameText(mFormat, 'json');
end;

{ TMcpLastTests }

function MatchesProject(const AProjectFile, AWanted: string): Boolean;
var
  mName: string;
begin
  mName := ExtractFileName(AProjectFile.Replace('\', PathDelim).Replace('/', PathDelim));
  Result := SameText(TProjectPaths.Normalize(AProjectFile), TProjectPaths.Normalize(AWanted)) or
    SameText(mName, AWanted) or SameText(ChangeFileExt(mName, ''), AWanted) or
    SameText(ChangeFileExt(mName, ''), ChangeFileExt(ExtractFileName(AWanted.Replace('\', PathDelim)), ''));
end;

function Inside(const ARoot, AFileName: string): Boolean;
var
  mRoot, mFile: string;
begin
  if ARoot = '' then
  begin
    Exit(False);
  end;
  mRoot := TProjectPaths.Normalize(ARoot).Replace('\', '/');
  mFile := TProjectPaths.Normalize(AFileName).Replace('\', '/');
  Result := SameText(Copy(mFile, 1, Length(mRoot) + 1), mRoot + '/');
end;

/// <summary>Neuester Lauf aus ARuns, mit AOnlyInside nur unter ARoot; -1 ohne.</summary>
function Newest(const ARuns: TArray<TTestRunFile>; const ARoot: string; AOnlyInside: Boolean): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(ARuns) do
  begin
    if AOnlyInside and not Inside(ARoot, ARuns[mIndex].Project) then
    begin
      Continue;
    end;
    if (Result < 0) or (ARuns[mIndex].FinishedAtUtc > ARuns[Result].FinishedAtUtc) then
    begin
      Result := mIndex;
    end;
  end;
end;

function ProjectNames(const ARuns: TArray<TTestRunFile>): string;
var
  mRun: TTestRunFile;
begin
  Result := '';
  for mRun in ARuns do
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + ExtractFileName(mRun.Project.Replace('\', PathDelim).Replace('/', PathDelim));
  end;
end;

class function TMcpLastTests.Pick(const ARuns: TArray<TTestRunFile>; const ARoot, AProject: string;
  out AReason: string): Integer;
var
  mIndex: Integer;
begin
  AReason := '';
  if AProject = '' then
  begin
    Result := Newest(ARuns, ARoot, True);
    if Result < 0 then
    begin
      Result := Newest(ARuns, ARoot, False);
    end;
    Exit;
  end;
  Result := -1;
  for mIndex := 0 to High(ARuns) do
  begin
    if MatchesProject(ARuns[mIndex].Project, AProject) and
      ((Result < 0) or (ARuns[mIndex].FinishedAtUtc > ARuns[Result].FinishedAtUtc)) then
    begin
      Result := mIndex;
    end;
  end;
  if Result < 0 then
  begin
    AReason := cTexts[TLastTestsText.UnknownProject].Fmt([AProject, ProjectNames(ARuns)]);
  end;
end;

function InList(const AFileName: string; const AFiles: TArray<string>): Boolean;
var
  mFile: string;
begin
  for mFile in AFiles do
  begin
    if SameText(TProjectPaths.Normalize(mFile), TProjectPaths.Normalize(AFileName)) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TMcpLastTests.StaleUnits(const ARun: TTestRunFile; const AFileTime: TMcpFileTimeFunc;
  const ADirty: TArray<string>): TArray<string>;
var
  mUnit: TTestRunUnit;
  mWritten: TDateTime;
begin
  Result := nil;
  for mUnit in ARun.Units do
  begin
    if mUnit.FileName = '' then
    begin
      Continue;
    end;
    mWritten := AFileTime(mUnit.FileName);
    if InList(mUnit.FileName, ADirty) or ((mWritten > 0) and (mWritten > ARun.FinishedAtUtc)) then
    begin
      Result := Result + [mUnit.Name];
    end;
  end;
end;

function IsStale(const ACase: TTestRunFileCase; const AStaleUnits: TArray<string>): Boolean;
begin
  Result := (ACase.Test.UnitName <> '') and MatchText(ACase.Test.UnitName, AStaleUnits);
end;

/// <summary>Index der Tests aus ARun für AFilter in Anzeigereihenfolge (langsamste zuerst bei Slow).</summary>
function Selected(const ARun: TTestRunFile; const AStaleUnits: TArray<string>;
  AFilter: TMcpLastTestsFilter): TArray<Integer>;
var
  mIndex: Integer;
  mTake: Boolean;
  mSlowest: TArray<TTestCaseResult>;
  mCases: TArray<TTestCaseResult>;
  mCase: TTestCaseResult;
begin
  Result := nil;
  if AFilter = TMcpLastTestsFilter.Slow then
  begin
    SetLength(mCases, Length(ARun.Cases));
    for mIndex := 0 to High(ARun.Cases) do
    begin
      mCases[mIndex] := ARun.Cases[mIndex].Test;
    end;
    mSlowest := TTestResults.Slowest(mCases, Length(mCases));
    for mCase in mSlowest do
    begin
      Result := Result + [ARun.IndexOf(mCase.FullName)];
    end;
    Exit;
  end;
  for mIndex := 0 to High(ARun.Cases) do
  begin
    case AFilter of
      TMcpLastTestsFilter.Failed:
        mTake := ARun.Cases[mIndex].Test.IsFailure;
      TMcpLastTestsFilter.Flaky:
        mTake := ARun.Cases[mIndex].IsFlaky;
      TMcpLastTestsFilter.Leaks:
        mTake := ARun.Cases[mIndex].Test.IsLeak;
      TMcpLastTestsFilter.Stale:
        mTake := IsStale(ARun.Cases[mIndex], AStaleUnits);
    else
      mTake := True;
    end;
    if mTake then
    begin
      Result := Result + [mIndex];
    end;
  end;
end;

function DurationText(AMs: Int64): string;
begin
  Result := TTestResults.DurationText(AMs, FormatSettings.DecimalSeparator);
end;

function ShortName(const ACase: TTestCaseResult): string;
begin
  Result := ACase.FullName;
  if (ACase.UnitName <> '') and StartsText(ACase.UnitName + '.', Result) then
  begin
    Result := Copy(Result, Length(ACase.UnitName) + 2, MaxInt);
  end;
end;

function Marks(const ACase: TTestRunFileCase; AStale: Boolean): string;

  procedure Add(const AText: string);
  begin
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + AText;
  end;

begin
  Result := '';
  if ACase.Change = TTestRunChange.NewFailure then
  begin
    Add(cTexts[TLastTestsText.NewFailure].Text);
  end;
  if ACase.Test.Outcome = TTestOutcome.Error then
  begin
    Add(cTexts[TLastTestsText.ErrorMark].Text);
  end;
  if ACase.Test.Outcome = TTestOutcome.Skipped then
  begin
    Add(cTexts[TLastTestsText.SkippedMark].Text);
  end;
  if ACase.IsFlaky then
  begin
    Add(cTexts[TLastTestsText.FlakyMark].Fmt([ACase.FlakyFailed, ACase.FlakyRuns]));
  end;
  if ACase.Test.IsLeak then
  begin
    Add(cTexts[TLastTestsText.LeakMark].Fmt([ACase.Test.LeakBytes]));
  end;
  if AStale then
  begin
    Add(cTexts[TLastTestsText.StaleMark].Text);
  end;
end;

function Symbol(const ACase: TTestCaseResult): string;
begin
  case ACase.Outcome of
    TTestOutcome.Passed:
      Result := '✔';
    TTestOutcome.Skipped:
      Result := '–';
  else
    Result := '✖';
  end;
end;

/// <summary>Erste Zeile der Meldung (ohne Stacktrace).</summary>
function FirstLine(const AText: string): string;
var
  mEnd: Integer;
begin
  Result := AText.Replace(#13#10, #10).Replace(#13, #10);
  mEnd := Pos(#10, Result);
  if mEnd > 0 then
  begin
    Result := Copy(Result, 1, mEnd - 1);
  end;
end;

procedure AddCaseText(ABuilder: TStringBuilder; const ACase: TTestRunFileCase; AStale: Boolean);
var
  mMarks, mLine: string;
begin
  mMarks := Marks(ACase, AStale);
  ABuilder.Append(Symbol(ACase.Test)).Append(' ').Append(ShortName(ACase.Test)).Append('  ')
    .Append(DurationText(ACase.Test.DurationMs));
  if mMarks <> '' then
  begin
    ABuilder.Append('  ').Append(mMarks);
  end;
  ABuilder.AppendLine;
  if ACase.FileName <> '' then
  begin
    ABuilder.Append('  ').Append(ExtractFileName(ACase.FileName.Replace('\', PathDelim).Replace('/', PathDelim)));
    if ACase.Line > 0 then
    begin
      ABuilder.Append(':').Append(ACase.Line);
    end;
    ABuilder.AppendLine;
  end;
  if ACase.Test.HasValues then
  begin
    ABuilder.Append('  ').AppendLine(cTexts[TLastTestsText.Values].Fmt([ACase.Test.Expected, ACase.Test.Actual]));
  end
  else if (ACase.Test.Message <> '') and not ACase.Test.IsLeak then
  begin
    ABuilder.Append('  ').AppendLine(FirstLine(ACase.Test.Message));
  end;
  for mLine in ACase.Log do
  begin
    ABuilder.Append('  ').AppendLine(cTexts[TLastTestsText.Log].Fmt([mLine]));
  end;
end;

function CountIf(const ARun: TTestRunFile; const AStaleUnits: TArray<string>; AFilter: TMcpLastTestsFilter): Integer;
begin
  Result := Length(Selected(ARun, AStaleUnits, AFilter));
end;

function FixedNames(const ARun: TTestRunFile): TArray<string>;
var
  mCase: TTestRunFileCase;
begin
  Result := nil;
  for mCase in ARun.Cases do
  begin
    if mCase.Change = TTestRunChange.Fixed then
    begin
      Result := Result + [ShortName(mCase.Test)];
    end;
  end;
end;

function LocalTimeText(ALocal: TDateTime): string;
begin
  if ALocal = 0 then
  begin
    Exit('?');
  end;
  Result := FormatDateTime('dd"."mm"."yyyy hh":"nn', ALocal, TFormatSettings.Invariant);
end;

function HeaderText(const ARun: TTestRunFile; const AStaleUnits: TArray<string>): string;
var
  mExtra: string;
  mCount: Integer;

  procedure Add(const AText: string);
  begin
    mExtra := mExtra + ', ' + AText;
  end;

begin
  Result := cTexts[TLastTestsText.Header].Fmt([ExtractFileName(ARun.Project.Replace('\', PathDelim)
    .Replace('/', PathDelim)), ARun.Platform, ARun.Configuration, LocalTimeText(ARun.FinishedAtLocal), ARun.Total,
    ARun.Failed, ARun.Count(TTestOutcome.Skipped), DurationText(ARun.DurationMs)]);
  mExtra := '';
  mCount := CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Flaky);
  if mCount > 0 then
  begin
    Add(cTexts[TLastTestsText.Flaky].Fmt([mCount]));
  end;
  mCount := CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Leaks);
  if mCount > 0 then
  begin
    Add(cTexts[TLastTestsText.Leaks].Fmt([mCount]));
  end;
  mCount := CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Stale);
  if mCount > 0 then
  begin
    Add(cTexts[TLastTestsText.StaleCount].Fmt([mCount]));
  end;
  Result := Result + mExtra;
end;

function TextReport(const ARun: TTestRunFile; const AStaleUnits: TArray<string>;
  const ARequest: TMcpLastTestsRequest): string;
var
  mBuilder: TStringBuilder;
  mIndexes: TArray<Integer>;
  mIndex, mShown: Integer;
  mFixed: TArray<string>;
begin
  mBuilder := TStringBuilder.Create;
  try
    mBuilder.AppendLine(HeaderText(ARun, AStaleUnits));
    if Length(ARun.Filter) > 0 then
    begin
      mBuilder.AppendLine(cTexts[TLastTestsText.Partial].Fmt([string.Join(', ', ARun.Filter)]));
    end;
    mFixed := FixedNames(ARun);
    if Length(mFixed) > cMaxFixedNames then
    begin
      mFixed := Copy(mFixed, 0, cMaxFixedNames) + ['…'];
    end;
    if Length(mFixed) > 0 then
    begin
      mBuilder.AppendLine(cTexts[TLastTestsText.Fixed].Fmt([string.Join(', ', mFixed)]));
    end;
    mIndexes := Selected(ARun, AStaleUnits, ARequest.Only);
    if Length(mIndexes) = 0 then
    begin
      mBuilder.AppendLine(cTexts[TLastTestsText.NoneMatch].Fmt([cFilterNames[ARequest.Only]]));
    end
    else if ARequest.Only = TMcpLastTestsFilter.Slow then
    begin
      mBuilder.AppendLine(cTexts[TLastTestsText.Slow].Text);
    end;
    mShown := 0;
    for mIndex in mIndexes do
    begin
      if mShown >= ARequest.Max then
      begin
        Break;
      end;
      AddCaseText(mBuilder, ARun.Cases[mIndex], IsStale(ARun.Cases[mIndex], AStaleUnits));
      Inc(mShown);
    end;
    if Length(mIndexes) > mShown then
    begin
      mBuilder.AppendLine(cTexts[TLastTestsText.More].Fmt([Length(mIndexes) - mShown]));
    end;
    Result := mBuilder.ToString.TrimRight;
  finally
    mBuilder.Free;
  end;
end;

function CaseJson(const ACase: TTestRunFileCase; AStale: Boolean): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ACase.Test.FullName);
  Result.AddPair('outcome', TTestRunFiles.OutcomeText(ACase.Test.Outcome));
  Result.AddPair('durationMs', TJSONNumber.Create(ACase.Test.DurationMs));
  if ACase.Test.Message <> '' then
  begin
    Result.AddPair('message', ACase.Test.Message);
  end;
  if ACase.Test.HasValues then
  begin
    Result.AddPair('expected', ACase.Test.Expected);
    Result.AddPair('actual', ACase.Test.Actual);
  end;
  if ACase.FileName <> '' then
  begin
    Result.AddPair('file', ACase.FileName);
    Result.AddPair('line', TJSONNumber.Create(ACase.Line));
  end;
  if ACase.Test.IsLeak then
  begin
    Result.AddPair('leakBytes', TJSONNumber.Create(ACase.Test.LeakBytes));
  end;
  if ACase.IsFlaky then
  begin
    Result.AddPair('flakyFailed', TJSONNumber.Create(ACase.FlakyFailed));
    Result.AddPair('flakyRuns', TJSONNumber.Create(ACase.FlakyRuns));
  end;
  TJsonBuild.AddText(Result, 'change', TTestRunFiles.ChangeText(ACase.Change));
  if AStale then
  begin
    Result.AddPair('stale', TJSONBool.Create(True));
  end;
  if Length(ACase.Log) > 0 then
  begin
    Result.AddPair('log', TJsonBuild.Strings(ACase.Log));
  end;
end;

function JsonReport(const ARun: TTestRunFile; const AStaleUnits: TArray<string>;
  const ARequest: TMcpLastTestsRequest): string;
var
  mRoot: TJSONObject;
  mTests: TJSONArray;
  mIndexes: TArray<Integer>;
  mIndex, mShown: Integer;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('project', ARun.Project);
    mRoot.AddPair('configuration', ARun.Configuration);
    mRoot.AddPair('platform', ARun.Platform);
    mRoot.AddPair('finishedAt', DateToISO8601(ARun.FinishedAtUtc, True));
    mRoot.AddPair('durationMs', TJSONNumber.Create(ARun.DurationMs));
    mRoot.AddPair('filter', TJsonBuild.Strings(ARun.Filter));
    mRoot.AddPair('total', TJSONNumber.Create(ARun.Total));
    mRoot.AddPair('passed', TJSONNumber.Create(ARun.Count(TTestOutcome.Passed)));
    mRoot.AddPair('failed', TJSONNumber.Create(ARun.Count(TTestOutcome.Failed)));
    mRoot.AddPair('errors', TJSONNumber.Create(ARun.Count(TTestOutcome.Error)));
    mRoot.AddPair('skipped', TJSONNumber.Create(ARun.Count(TTestOutcome.Skipped)));
    mRoot.AddPair('flaky', TJSONNumber.Create(CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Flaky)));
    mRoot.AddPair('leaks', TJSONNumber.Create(CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Leaks)));
    mRoot.AddPair('stale', TJSONNumber.Create(CountIf(ARun, AStaleUnits, TMcpLastTestsFilter.Stale)));
    mRoot.AddPair('fixed', TJsonBuild.Strings(FixedNames(ARun)));
    mRoot.AddPair('only', cFilterNames[ARequest.Only]);
    mTests := TJSONArray.Create;
    mRoot.AddPair('tests', mTests);
    mIndexes := Selected(ARun, AStaleUnits, ARequest.Only);
    mShown := 0;
    for mIndex in mIndexes do
    begin
      if mShown >= ARequest.Max then
      begin
        Break;
      end;
      mTests.AddElement(CaseJson(ARun.Cases[mIndex], IsStale(ARun.Cases[mIndex], AStaleUnits)));
      Inc(mShown);
    end;
    mRoot.AddPair('omitted', TJSONNumber.Create(Length(mIndexes) - mShown));
    Result := mRoot.Format(2);
  finally
    mRoot.Free;
  end;
end;

class function TMcpLastTests.Report(const ARun: TTestRunFile; const AStaleUnits: TArray<string>;
  const ARequest: TMcpLastTestsRequest): string;
begin
  if ARequest.AsJson then
  begin
    Result := JsonReport(ARun, AStaleUnits, ARequest);
  end
  else
  begin
    Result := TextReport(ARun, AStaleUnits, ARequest);
  end;
end;

class function TMcpLastTests.NoRuns(const AFolder: string): string;
begin
  Result := cTexts[TLastTestsText.NoRuns].Fmt([AFolder]);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.LastTests', cTexts);

end.
