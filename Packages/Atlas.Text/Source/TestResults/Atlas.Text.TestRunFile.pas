unit Atlas.Text.TestRunFile;

// Letzter Testlauf der IDE für KI-Assistenten (#2409, MCP-Werkzeug get_last_tests), gemeinsam für Plugin und
// Server. Nach jedem gemeldeten Lauf (auch Teilläufe und Serien) legt das Modul Tests im Plugin den Lauf je
// Testprojekt ab, der MCP-Server liest ihn, ohne die Tests erneut auszuführen:
//   %LOCALAPPDATA%\Atlas\last-tests\<Schlüssel des Projekts>.json   (UTF-8, atomar ersetzt)
//   {"format": 1, "project": .dproj, "configuration": …, "platform": …,
//    "finishedAt": ISO 8601 in UTC, "durationMs": …, "filter": [Namen für --run; leer = alle Tests],
//    "units": [{"name": Unit, "file": Pfad der Testunit}],
//    "tests": [{"name": voller Name, "unit": …, "outcome": "passed"|"failed"|"error"|"skipped",
//               "durationMs": …, dazu nur, wenn vorhanden: "message", "expected"/"actual" (Werte aus der
//               Meldung), "file"/"line" (Fundstelle, Zeile 1-basiert), "leakBytes", "flakyFailed"/"flakyRuns"
//               (wackelt: rote von allen gemerkten Läufen), "change": "newFailure"|"fixed", "log": [Zeilen]}]}
// Ein Test mit Leck, den das Plugin als bestanden mit Leck zeigt (tests.leaks), steht als "passed" mit
// "leakBytes". "change" vergleicht mit dem Lauf davor desselben Projekts (MarkChanges): neu rot bzw. wieder
// grün; nur für Tests, die in beiden Läufen vorkommen.

interface

{$SCOPEDENUMS ON}

uses
  Atlas.Text.TestResults;

type
  /// <summary>Unterschied eines Tests zum Lauf davor.</summary>
  TTestRunChange = (None, NewFailure, Fixed);

  TTestRunFileCase = record
    Test: TTestCaseResult;
    /// <summary>Datei der Testunit; '' ohne Fundstelle.</summary>
    FileName: string;
    /// <summary>Zeile der fehlgeschlagenen Anweisung bzw. des Methodenkopfs, 1-basiert; 0 ohne.</summary>
    Line: Integer;
    /// <summary>Wackelt: rote unter allen gemerkten Läufen mit unverändertem Rumpf; FlakyRuns = 0 wackelt nicht.
    /// </summary>
    FlakyFailed: Integer;
    FlakyRuns: Integer;
    Change: TTestRunChange;
    /// <summary>Auszug aus dem Protokoll je Test (#2168).</summary>
    Log: TArray<string>;
    function IsFlaky: Boolean;
  end;

  /// <summary>Testunit des Laufs mit ihrer Datei (veraltete Ergebnisse erkennt der Server an Änderungen).</summary>
  TTestRunUnit = record
    Name: string;
    FileName: string;
  end;

  TTestRunFile = record
    Project: string;
    Configuration: string;
    Platform: string;
    FinishedAtUtc: TDateTime;
    /// <summary>Dasselbe in Ortszeit; nur Parse setzt es (ToJson schreibt UTC).</summary>
    FinishedAtLocal: TDateTime;
    DurationMs: Int64;
    /// <summary>Namen, auf die der Lauf beschränkt war; leer = alle Tests.</summary>
    Filter: TArray<string>;
    Cases: TArray<TTestRunFileCase>;
    Units: TArray<TTestRunUnit>;
    function Count(AOutcome: TTestOutcome): Integer;
    function Total: Integer;
    /// <summary>Fehlgeschlagene und abgebrochene Tests.</summary>
    function Failed: Integer;
    /// <summary>Index des Tests mit dem vollen Namen AName (Groß- und Kleinschreibung egal); -1 ohne.</summary>
    function IndexOf(const AName: string): Integer;
    /// <summary>Datei der Unit AUnitName; '' unbekannt.</summary>
    function UnitFileOf(const AUnitName: string): string;
  end;

  TTestRunFiles = class
  public const
    cFormat = 1;
    cFolderName = 'last-tests';
  public
    /// <summary>Ablage unter ABase (%LOCALAPPDATA%\Atlas).</summary>
    class function Folder(const ABase: string): string; static;
    class function OutcomeText(AOutcome: TTestOutcome): string; static;
    /// <summary>Wert von change im JSON; '' für None.</summary>
    class function ChangeText(AChange: TTestRunChange): string; static;
    /// <summary>Inhalt der Datei (kompaktes JSON).</summary>
    class function ToJson(const ARun: TTestRunFile): string; static;
    /// <summary>Liest ToJson; False bei kaputtem Inhalt oder höherem Format.</summary>
    class function Parse(const AText: string; out ARun: TTestRunFile): Boolean; static;
    /// <summary>Setzt Change in ACurrent gegenüber dem Lauf APrevious desselben Projekts.</summary>
    class procedure MarkChanges(const APrevious: TTestRunFile; var ACurrent: TTestRunFile); static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.JSON,
  System.DateUtils,
  Atlas.Text.Json,
  Atlas.Text.Timestamps;

const
  cOutcomes: array[TTestOutcome] of string = ('passed', 'failed', 'error', 'skipped');
  cChanges: array[TTestRunChange] of string = ('', 'newFailure', 'fixed');

{ TTestRunFileCase }

function TTestRunFileCase.IsFlaky: Boolean;
begin
  Result := FlakyRuns > 0;
end;

{ TTestRunFile }

function TTestRunFile.Count(AOutcome: TTestOutcome): Integer;
var
  mItem: TTestRunFileCase;
begin
  Result := 0;
  for mItem in Cases do
  begin
    if mItem.Test.Outcome = AOutcome then
    begin
      Inc(Result);
    end;
  end;
end;

function TTestRunFile.Total: Integer;
begin
  Result := Length(Cases);
end;

function TTestRunFile.Failed: Integer;
begin
  Result := Count(TTestOutcome.Failed) + Count(TTestOutcome.Error);
end;

function TTestRunFile.IndexOf(const AName: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Cases) do
  begin
    if SameText(Cases[mIndex].Test.FullName, AName) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TTestRunFile.UnitFileOf(const AUnitName: string): string;
var
  mUnit: TTestRunUnit;
begin
  for mUnit in Units do
  begin
    if SameText(mUnit.Name, AUnitName) then
    begin
      Exit(mUnit.FileName);
    end;
  end;
  Result := '';
end;

{ TTestRunFiles }

class function TTestRunFiles.Folder(const ABase: string): string;
begin
  Result := IncludeTrailingPathDelimiter(ABase) + cFolderName;
end;

class function TTestRunFiles.ChangeText(AChange: TTestRunChange): string;
begin
  Result := cChanges[AChange];
end;

class function TTestRunFiles.OutcomeText(AOutcome: TTestOutcome): string;
begin
  Result := cOutcomes[AOutcome];
end;

function OutcomeOf(const AText: string): TTestOutcome;
var
  mOutcome: TTestOutcome;
begin
  for mOutcome := Low(TTestOutcome) to High(TTestOutcome) do
  begin
    if SameText(cOutcomes[mOutcome], AText) then
    begin
      Exit(mOutcome);
    end;
  end;
  Result := TTestOutcome.Skipped;
end;

function ChangeOf(const AText: string): TTestRunChange;
var
  mChange: TTestRunChange;
begin
  for mChange := Succ(Low(TTestRunChange)) to High(TTestRunChange) do
  begin
    if SameText(cChanges[mChange], AText) then
    begin
      Exit(mChange);
    end;
  end;
  Result := TTestRunChange.None;
end;

procedure AddNumber(AObject: TJSONObject; const AName: string; AValue: Int64);
begin
  if AValue <> 0 then
  begin
    AObject.AddPair(AName, TJSONNumber.Create(AValue));
  end;
end;

function CaseJson(const ACase: TTestRunFileCase): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ACase.Test.FullName);
  TJsonBuild.AddText(Result, 'unit', ACase.Test.UnitName);
  Result.AddPair('outcome', cOutcomes[ACase.Test.Outcome]);
  Result.AddPair('durationMs', TJSONNumber.Create(ACase.Test.DurationMs));
  TJsonBuild.AddText(Result, 'message', ACase.Test.Message);
  if ACase.Test.HasValues then
  begin
    Result.AddPair('expected', ACase.Test.Expected);
    Result.AddPair('actual', ACase.Test.Actual);
  end;
  TJsonBuild.AddText(Result, 'file', ACase.FileName);
  AddNumber(Result, 'line', ACase.Line);
  AddNumber(Result, 'leakBytes', ACase.Test.LeakBytes);
  if ACase.IsFlaky then
  begin
    Result.AddPair('flakyFailed', TJSONNumber.Create(ACase.FlakyFailed));
    Result.AddPair('flakyRuns', TJSONNumber.Create(ACase.FlakyRuns));
  end;
  TJsonBuild.AddText(Result, 'change', TTestRunFiles.ChangeText(ACase.Change));
  if Length(ACase.Log) > 0 then
  begin
    Result.AddPair('log', TJsonBuild.Strings(ACase.Log));
  end;
end;

function UnitsJson(const AUnits: TArray<TTestRunUnit>): TJSONArray;
var
  mUnit: TTestRunUnit;
  mItem: TJSONObject;
begin
  Result := TJSONArray.Create;
  for mUnit in AUnits do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mUnit.Name);
    mItem.AddPair('file', mUnit.FileName);
    Result.AddElement(mItem);
  end;
end;

class function TTestRunFiles.ToJson(const ARun: TTestRunFile): string;
var
  mRoot: TJSONObject;
  mTests: TJSONArray;
  mCase: TTestRunFileCase;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', ARun.Project);
    mRoot.AddPair('configuration', ARun.Configuration);
    mRoot.AddPair('platform', ARun.Platform);
    mRoot.AddPair('finishedAt', DateToISO8601(ARun.FinishedAtUtc, True));
    mRoot.AddPair('durationMs', TJSONNumber.Create(ARun.DurationMs));
    mRoot.AddPair('filter', TJsonBuild.Strings(ARun.Filter));
    mRoot.AddPair('units', UnitsJson(ARun.Units));
    mTests := TJSONArray.Create;
    mRoot.AddPair('tests', mTests);
    for mCase in ARun.Cases do
    begin
      mTests.AddElement(CaseJson(mCase));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

function CaseOf(AItem: TJSONObject): TTestRunFileCase;
begin
  Result := Default(TTestRunFileCase);
  Result.Test.FullName := TJsonRead.Text(AItem, 'name');
  Result.Test.UnitName := TJsonRead.Text(AItem, 'unit');
  Result.Test.Outcome := OutcomeOf(TJsonRead.Text(AItem, 'outcome'));
  Result.Test.DurationMs := TJsonRead.Int64Or(AItem, 'durationMs', 0);
  Result.Test.Message := TJsonRead.Text(AItem, 'message');
  Result.Test.HasValues := TJsonRead.TryText(AItem, 'expected', Result.Test.Expected) and
    TJsonRead.TryText(AItem, 'actual', Result.Test.Actual);
  Result.Test.LeakBytes := TJsonRead.Int64Or(AItem, 'leakBytes', 0);
  Result.FileName := TJsonRead.Text(AItem, 'file');
  Result.Line := TJsonRead.IntOr(AItem, 'line', 0);
  Result.FlakyFailed := TJsonRead.IntOr(AItem, 'flakyFailed', 0);
  Result.FlakyRuns := TJsonRead.IntOr(AItem, 'flakyRuns', 0);
  Result.Change := ChangeOf(TJsonRead.Text(AItem, 'change'));
  Result.Log := TJsonRead.Strings(AItem, 'log');
end;

function UnitsOf(AItems: TJSONArray): TArray<TTestRunUnit>;
var
  mItem: TJSONValue;
  mUnit: TTestRunUnit;
begin
  Result := nil;
  if AItems = nil then
  begin
    Exit;
  end;
  for mItem in AItems do
  begin
    if mItem is TJSONObject then
    begin
      mUnit.Name := TJsonRead.Text(TJSONObject(mItem), 'name');
      mUnit.FileName := TJsonRead.Text(TJSONObject(mItem), 'file');
      Result := Result + [mUnit];
    end;
  end;
end;

class function TTestRunFiles.Parse(const AText: string; out ARun: TTestRunFile): Boolean;
var
  mRoot: TJSONObject;
  mTests: TJSONArray;
  mItem: TJSONValue;
  mFormat: Integer;
begin
  ARun := Default(TTestRunFile);
  mRoot := TJsonRead.ParseObject(AText);
  if mRoot = nil then
  begin
    Exit(False);
  end;
  try
    mFormat := TJsonRead.IntOr(mRoot, 'format', 0);
    Result := (mFormat >= 1) and (mFormat <= cFormat) and (TJsonRead.Text(mRoot, 'project') <> '');
    if not Result then
    begin
      Exit;
    end;
    ARun.Project := TJsonRead.Text(mRoot, 'project');
    ARun.Configuration := TJsonRead.Text(mRoot, 'configuration');
    ARun.Platform := TJsonRead.Text(mRoot, 'platform');
    ARun.FinishedAtUtc := TTextTimestamp.IsoOrZero(TJsonRead.Text(mRoot, 'finishedAt'), True);
    ARun.FinishedAtLocal := TTextTimestamp.IsoOrZero(TJsonRead.Text(mRoot, 'finishedAt'), False);
    ARun.DurationMs := TJsonRead.Int64Or(mRoot, 'durationMs', 0);
    ARun.Filter := TJsonRead.Strings(mRoot, 'filter');
    ARun.Units := UnitsOf(TJsonRead.Items(mRoot, 'units'));
    mTests := TJsonRead.Items(mRoot, 'tests');
    if mTests = nil then
    begin
      Exit;
    end;
    for mItem in mTests do
    begin
      if mItem is TJSONObject then
      begin
        ARun.Cases := ARun.Cases + [CaseOf(TJSONObject(mItem))];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class procedure TTestRunFiles.MarkChanges(const APrevious: TTestRunFile; var ACurrent: TTestRunFile);
var
  mIndex, mBefore: Integer;
  mWasRed, mIsRed: Boolean;
begin
  for mIndex := 0 to High(ACurrent.Cases) do
  begin
    ACurrent.Cases[mIndex].Change := TTestRunChange.None;
    mBefore := APrevious.IndexOf(ACurrent.Cases[mIndex].Test.FullName);
    if (mBefore < 0) or (APrevious.Cases[mBefore].Test.Outcome = TTestOutcome.Skipped) then
    begin
      Continue;
    end;
    mWasRed := APrevious.Cases[mBefore].Test.IsFailure;
    mIsRed := ACurrent.Cases[mIndex].Test.IsFailure;
    if mIsRed and not mWasRed then
    begin
      ACurrent.Cases[mIndex].Change := TTestRunChange.NewFailure;
    end
    else if mWasRed and (ACurrent.Cases[mIndex].Test.Outcome = TTestOutcome.Passed) then
    begin
      ACurrent.Cases[mIndex].Change := TTestRunChange.Fixed;
    end;
  end;
end;

end.
