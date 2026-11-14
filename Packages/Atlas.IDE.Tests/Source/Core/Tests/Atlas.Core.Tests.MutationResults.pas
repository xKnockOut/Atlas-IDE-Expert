unit Atlas.Core.Tests.MutationResults;

// Ergebnisse des Mutationslaufs (#1460), ohne VCL und Open Tools API:
// - Je Routine einer Unit merkt sich das Modul die Prüfsumme ihres Texts
//   (TAtlasMutants.RoutineBody) und je Mutant den Ausgang. Ein Mutant ist
//   bestimmt durch Routine, Nummer in der Routine, Operator und Ersatz; die
//   Zeile steht relativ zum Kopf der Routine, damit Symbole in der Rinne
//   mitwandern, wenn darüber Code dazukommt.
// - Marken für die Rinne (MarksOf): je Zeile die Ausgänge der Mutanten, nur
//   für Routinen, deren Prüfsumme an den gemerkten Zeilen noch stimmt.
// - Ändert sich die Prüfsumme, ist das Ergebnis der Routine veraltet: Die
//   Rinne zeigt es nicht mehr, der Befehl „geänderte Routinen“ nimmt sie neu.
// - Ausgang: erkannt (ein Test schlug fehl), überlebt (alle grün), Zeit
//   überschritten (zählt als erkannt), nicht übersetzbar und nicht anwendbar
//   (beide zählen nicht mit).
// - Ablage: je Testprojekt .atlas-local\mutation\results.json (Format 1,
//   UTF-8 ohne BOM, Zeiten in UTC):
//     {"format": 1, "project": "C:\\P\\Demo.Tests.dproj",
//      "files": [{"file": "C:\\P\\Preise.pas", "routines": [{"routine": "Satz",
//        "body": "…", "line": 3, "endLine": 9, "at": "…", "mutants": [{"index": 0,
//        "operator": "boundary", "original": ">=", "replacement": ">", "line": 2,
//        "description": "…", "status": "survived", "by": "", "ms": 120}]}]}]}

interface

uses
  System.Generics.Collections,
  Atlas.Core.Tests.Mutants;

type
{$SCOPEDENUMS ON}
  TAtlasMutationStatus = (Killed, Survived, TimedOut, BuildFailed, Invalid);
{$SCOPEDENUMS OFF}

  /// <summary>Ausgang eines Mutanten.</summary>
  TAtlasMutationOutcome = record
    /// <summary>Der wievielte Mutant seiner Routine (ab 0).</summary>
    Index: Integer;
    OperatorId: string;
    Original: string;
    Replacement: string;
    /// <summary>Beschreibung wie vom Server ("&gt;= durch &gt;").</summary>
    Description: string;
    /// <summary>Zeile relativ zum Kopf der Routine (ab 0).</summary>
    Line: Integer;
    Status: TAtlasMutationStatus;
    /// <summary>Erkannt: der erste fehlgeschlagene Test; sonst eine Meldung oder ''.</summary>
    By: string;
    Milliseconds: Integer;
  end;

  /// <summary>Ergebnisse einer Routine.</summary>
  TAtlasMutationRoutineResult = record
    FileName: string;
    Routine: string;
    Body: string;
    /// <summary>Zeilen der Routine beim Lauf (ab 0, Kopf bis end).</summary>
    Line: Integer;
    EndLine: Integer;
    AtUtc: TDateTime;
    Outcomes: TArray<TAtlasMutationOutcome>;
  end;

  /// <summary>Ausgänge der Mutanten einer Zeile (ab 0) für die Rinne.</summary>
  TAtlasMutationLineMark = record
    Line: Integer;
    Outcomes: TArray<TAtlasMutationOutcome>;
    /// <summary>Überlebt mindestens einer?</summary>
    function AnySurvived: Boolean;
    /// <summary>Erkannt mindestens einer (auch Zeitüberschreitung)?</summary>
    function AnyKilled: Boolean;
  end;

  /// <summary>Zahlen über Ergebnisse.</summary>
  TAtlasMutationTotals = record
    Killed: Integer;
    Survived: Integer;
    TimedOut: Integer;
    BuildFailed: Integer;
    Invalid: Integer;
    procedure Add(AStatus: TAtlasMutationStatus);
    /// <summary>Erkannte (auch Zeitüberschreitung) unter den bewerteten Mutanten in Prozent, abgerundet; -1 ohne
    /// bewertete.</summary>
    function Score: Integer;
  end;

  TAtlasMutationResults = class
  public const
    cFormat = 1;
    cFileName = 'results.json';
  private
    FRoutines: TDictionary<string, TAtlasMutationRoutineResult>;
    class function KeyOf(const AFileName, ARoutine: string): string; static;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Kennung des Ausgangs im JSON ("killed", …).</summary>
    class function StatusId(AStatus: TAtlasMutationStatus): string; static;
    class function TryParseStatus(const AId: string; out AStatus: TAtlasMutationStatus): Boolean; static;
    /// <summary>Ergebnisse einer Routine merken; ersetzt frühere derselben Routine.</summary>
    procedure Put(const AResult: TAtlasMutationRoutineResult);
    /// <summary>Ergebnisse der Routine ARoutine in AFileName mit der Prüfsumme ABody; False ohne oder veraltet.
    /// </summary>
    function Lookup(const AFileName, ARoutine, ABody: string; out AResult: TAtlasMutationRoutineResult): Boolean;
    /// <summary>Gibt es Ergebnisse der Routine, aber mit anderer Prüfsumme?</summary>
    function IsStale(const AFileName, ARoutine, ABody: string): Boolean;
    /// <summary>Alle Routinen von AFileName mit Ergebnissen (auch veraltete), nach Routine sortiert.</summary>
    function RoutinesOf(const AFileName: string): TArray<TAtlasMutationRoutineResult>;
    /// <summary>Marken je Zeile für AFileName mit dem Text ALines, nach Zeile sortiert; nur Routinen, deren
    /// Prüfsumme an den gemerkten Zeilen stimmt.</summary>
    function MarksOf(const AFileName: string; const ALines: TArray<string>): TArray<TAtlasMutationLineMark>;
    /// <summary>Zahlen über die Ergebnisse von AFileName ('' = alle Dateien).</summary>
    function Totals(const AFileName: string): TAtlasMutationTotals;
    /// <summary>Ergebnisse von AFileName vergessen ('' = alle).</summary>
    procedure Forget(const AFileName: string);
    function Count: Integer;
    /// <summary>Ergebnisse als JSON (Format oben), Dateien und Routinen sortiert.</summary>
    function ToJson(const AProject: string): string;
    /// <summary>Liest AJson und ersetzt die Ergebnisse. False bei ungültigem Inhalt oder anderem Format; die
    /// Ergebnisse sind dann leer. Unbrauchbare Einträge fallen weg.</summary>
    function LoadJson(const AJson: string): Boolean;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Json,
  Atlas.Core.Projects.Summary.Json;

const
  cStatusIds: array[TAtlasMutationStatus] of string = ('killed', 'survived', 'timeout', 'buildFailed', 'invalid');
  cPercent = 100;

{ TAtlasMutationLineMark }

function TAtlasMutationLineMark.AnySurvived: Boolean;
var
  mOutcome: TAtlasMutationOutcome;
begin
  for mOutcome in Outcomes do
  begin
    if mOutcome.Status = TAtlasMutationStatus.Survived then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasMutationLineMark.AnyKilled: Boolean;
var
  mOutcome: TAtlasMutationOutcome;
begin
  for mOutcome in Outcomes do
  begin
    if mOutcome.Status in [TAtlasMutationStatus.Killed, TAtlasMutationStatus.TimedOut] then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasMutationTotals }

procedure TAtlasMutationTotals.Add(AStatus: TAtlasMutationStatus);
begin
  case AStatus of
    TAtlasMutationStatus.Killed:
      Inc(Killed);
    TAtlasMutationStatus.Survived:
      Inc(Survived);
    TAtlasMutationStatus.TimedOut:
      Inc(TimedOut);
    TAtlasMutationStatus.BuildFailed:
      Inc(BuildFailed);
    TAtlasMutationStatus.Invalid:
      Inc(Invalid);
  end;
end;

function TAtlasMutationTotals.Score: Integer;
var
  mDetected: Integer;
begin
  mDetected := Killed + TimedOut;
  Result := -1;
  if mDetected + Survived > 0 then
  begin
    Result := mDetected * cPercent div (mDetected + Survived);
  end;
end;

{ TAtlasMutationResults }

constructor TAtlasMutationResults.Create;
begin
  inherited Create;
  FRoutines := TDictionary<string, TAtlasMutationRoutineResult>.Create;
end;

destructor TAtlasMutationResults.Destroy;
begin
  FRoutines.Free;
  inherited Destroy;
end;

class function TAtlasMutationResults.KeyOf(const AFileName, ARoutine: string): string;
begin
  Result := AnsiLowerCase(AFileName) + #0 + ARoutine;
end;

class function TAtlasMutationResults.StatusId(AStatus: TAtlasMutationStatus): string;
begin
  Result := cStatusIds[AStatus];
end;

class function TAtlasMutationResults.TryParseStatus(const AId: string; out AStatus: TAtlasMutationStatus): Boolean;
var
  mStatus: TAtlasMutationStatus;
begin
  for mStatus := Low(TAtlasMutationStatus) to High(TAtlasMutationStatus) do
  begin
    if SameText(cStatusIds[mStatus], AId) then
    begin
      AStatus := mStatus;
      Exit(True);
    end;
  end;
  AStatus := TAtlasMutationStatus.Invalid;
  Result := False;
end;

procedure TAtlasMutationResults.Put(const AResult: TAtlasMutationRoutineResult);
begin
  FRoutines.AddOrSetValue(KeyOf(AResult.FileName, AResult.Routine), AResult);
end;

function TAtlasMutationResults.Lookup(const AFileName, ARoutine, ABody: string;
  out AResult: TAtlasMutationRoutineResult): Boolean;
begin
  Result := FRoutines.TryGetValue(KeyOf(AFileName, ARoutine), AResult) and (AResult.Body = ABody);
  if not Result then
  begin
    AResult := Default(TAtlasMutationRoutineResult);
  end;
end;

function TAtlasMutationResults.IsStale(const AFileName, ARoutine, ABody: string): Boolean;
var
  mResult: TAtlasMutationRoutineResult;
begin
  Result := FRoutines.TryGetValue(KeyOf(AFileName, ARoutine), mResult) and (mResult.Body <> ABody);
end;

/// <summary>Sortiert ARoutines nach Datei und Routine (Schlüssel sind eindeutig: Reihenfolge fest).</summary>
procedure SortRoutines(var ARoutines: TArray<TAtlasMutationRoutineResult>);
var
  mIndex, mOther: Integer;
  mSwap: TAtlasMutationRoutineResult;
begin
  // Einfügesortierung: wenige Routinen je Datei.
  for mIndex := 1 to High(ARoutines) do
  begin
    mSwap := ARoutines[mIndex];
    mOther := mIndex - 1;
    while (mOther >= 0) and (CompareText(ARoutines[mOther].FileName + #0 + ARoutines[mOther].Routine,
      mSwap.FileName + #0 + mSwap.Routine) > 0) do
    begin
      ARoutines[mOther + 1] := ARoutines[mOther];
      Dec(mOther);
    end;
    ARoutines[mOther + 1] := mSwap;
  end;
end;

function TAtlasMutationResults.RoutinesOf(const AFileName: string): TArray<TAtlasMutationRoutineResult>;
var
  mResult: TAtlasMutationRoutineResult;
begin
  Result := nil;
  for mResult in FRoutines.Values do
  begin
    if (AFileName = '') or SameText(mResult.FileName, AFileName) then
    begin
      Result := Result + [mResult];
    end;
  end;
  SortRoutines(Result);
end;

/// <summary>Index der Marke für ALine in AMarks; neu angehängt, wenn es keine gibt.</summary>
function MarkIndex(var AMarks: TArray<TAtlasMutationLineMark>; ALine: Integer): Integer;
var
  mMark: TAtlasMutationLineMark;
  mIndex: Integer;
begin
  for mIndex := 0 to High(AMarks) do
  begin
    if AMarks[mIndex].Line = ALine then
    begin
      Exit(mIndex);
    end;
  end;
  mMark := Default(TAtlasMutationLineMark);
  mMark.Line := ALine;
  AMarks := AMarks + [mMark];
  Result := High(AMarks);
end;

/// <summary>Sortiert AMarks nach Zeile (Zeilen sind eindeutig).</summary>
procedure SortMarks(var AMarks: TArray<TAtlasMutationLineMark>);
var
  mIndex, mOther: Integer;
  mSwap: TAtlasMutationLineMark;
begin
  for mIndex := 1 to High(AMarks) do
  begin
    mSwap := AMarks[mIndex];
    mOther := mIndex - 1;
    while (mOther >= 0) and (AMarks[mOther].Line > mSwap.Line) do
    begin
      AMarks[mOther + 1] := AMarks[mOther];
      Dec(mOther);
    end;
    AMarks[mOther + 1] := mSwap;
  end;
end;

function TAtlasMutationResults.MarksOf(const AFileName: string;
  const ALines: TArray<string>): TArray<TAtlasMutationLineMark>;
var
  mResult: TAtlasMutationRoutineResult;
  mRoutine: TAtlasMutantRoutine;
  mOutcome: TAtlasMutationOutcome;
  mIndex: Integer;
begin
  Result := nil;
  for mResult in RoutinesOf(AFileName) do
  begin
    mRoutine := Default(TAtlasMutantRoutine);
    mRoutine.Name := mResult.Routine;
    mRoutine.Line := mResult.Line;
    mRoutine.EndLine := mResult.EndLine;
    if (mResult.Body = '') or (TAtlasMutants.RoutineBody(ALines, mRoutine) <> mResult.Body) then
    begin
      Continue;
    end;
    for mOutcome in mResult.Outcomes do
    begin
      mIndex := MarkIndex(Result, mResult.Line + mOutcome.Line);
      Result[mIndex].Outcomes := Result[mIndex].Outcomes + [mOutcome];
    end;
  end;
  SortMarks(Result);
end;

function TAtlasMutationResults.Totals(const AFileName: string): TAtlasMutationTotals;
var
  mResult: TAtlasMutationRoutineResult;
  mOutcome: TAtlasMutationOutcome;
begin
  Result := Default(TAtlasMutationTotals);
  for mResult in RoutinesOf(AFileName) do
  begin
    for mOutcome in mResult.Outcomes do
    begin
      Result.Add(mOutcome.Status);
    end;
  end;
end;

procedure TAtlasMutationResults.Forget(const AFileName: string);
var
  mResult: TAtlasMutationRoutineResult;
begin
  if AFileName = '' then
  begin
    FRoutines.Clear;
    Exit;
  end;
  for mResult in RoutinesOf(AFileName) do
  begin
    FRoutines.Remove(KeyOf(mResult.FileName, mResult.Routine));
  end;
end;

function TAtlasMutationResults.Count: Integer;
begin
  Result := FRoutines.Count;
end;

/// <summary>Ein Ausgang als JSON-Objekt.</summary>
function OutcomeJson(const AOutcome: TAtlasMutationOutcome): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('index', TJSONNumber.Create(AOutcome.Index));
  Result.AddPair('operator', AOutcome.OperatorId);
  Result.AddPair('original', AOutcome.Original);
  Result.AddPair('replacement', AOutcome.Replacement);
  Result.AddPair('line', TJSONNumber.Create(AOutcome.Line));
  Result.AddPair('description', AOutcome.Description);
  Result.AddPair('status', TAtlasMutationResults.StatusId(AOutcome.Status));
  Result.AddPair('by', AOutcome.By);
  Result.AddPair('ms', TJSONNumber.Create(AOutcome.Milliseconds));
end;

/// <summary>Eine Routine als JSON-Objekt.</summary>
function RoutineJson(const AResult: TAtlasMutationRoutineResult): TJSONObject;
var
  mOutcomes: TJSONArray;
  mOutcome: TAtlasMutationOutcome;
begin
  Result := TJSONObject.Create;
  Result.AddPair('routine', AResult.Routine);
  Result.AddPair('body', AResult.Body);
  Result.AddPair('line', TJSONNumber.Create(AResult.Line));
  Result.AddPair('endLine', TJSONNumber.Create(AResult.EndLine));
  AddTime(Result, 'at', AResult.AtUtc);
  mOutcomes := TJSONArray.Create;
  Result.AddPair('mutants', mOutcomes);
  for mOutcome in AResult.Outcomes do
  begin
    mOutcomes.AddElement(OutcomeJson(mOutcome));
  end;
end;

function TAtlasMutationResults.ToJson(const AProject: string): string;
var
  mRoot, mFile: TJSONObject;
  mFiles, mRoutines: TJSONArray;
  mResult: TAtlasMutationRoutineResult;
  mLastFile: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormat));
    mRoot.AddPair('project', AProject);
    mFiles := TJSONArray.Create;
    mRoot.AddPair('files', mFiles);
    mRoutines := nil;
    mLastFile := '';
    // Sortiert nach Datei: Ein Wechsel des Dateinamens beginnt einen neuen Eintrag.
    for mResult in RoutinesOf('') do
    begin
      if (mRoutines = nil) or not SameText(mResult.FileName, mLastFile) then
      begin
        mFile := TJSONObject.Create;
        mFiles.AddElement(mFile);
        mFile.AddPair('file', mResult.FileName);
        mRoutines := TJSONArray.Create;
        mFile.AddPair('routines', mRoutines);
        mLastFile := mResult.FileName;
      end;
      mRoutines.AddElement(RoutineJson(mResult));
    end;
    Result := mRoot.ToJSON([]);
  finally
    mRoot.Free;
  end;
end;

/// <summary>Ausgang aus einem Eintrag von "mutants"; False ohne bekannten Status.</summary>
function OutcomeOf(AObject: TJSONObject; out AOutcome: TAtlasMutationOutcome): Boolean;
begin
  AOutcome := Default(TAtlasMutationOutcome);
  AOutcome.Index := TJsonRead.IntOr(AObject, 'index', -1);
  AOutcome.OperatorId := TJsonRead.Text(AObject, 'operator');
  AOutcome.Original := TJsonRead.Text(AObject, 'original');
  AOutcome.Replacement := TJsonRead.Text(AObject, 'replacement');
  AOutcome.Line := TJsonRead.IntOr(AObject, 'line', -1);
  AOutcome.Description := TJsonRead.Text(AObject, 'description');
  AOutcome.By := TJsonRead.Text(AObject, 'by');
  AOutcome.Milliseconds := TJsonRead.IntOr(AObject, 'ms', 0);
  Result := TAtlasMutationResults.TryParseStatus(TJsonRead.Text(AObject, 'status'), AOutcome.Status) and
    (AOutcome.Index >= 0) and (AOutcome.Line >= 0);
end;

/// <summary>Routine aus einem Eintrag von "routines"; False ohne Namen.</summary>
function RoutineOf(AObject: TJSONObject; const AFileName: string; out AResult: TAtlasMutationRoutineResult): Boolean;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mObject: TJSONObject;
  mOutcome: TAtlasMutationOutcome;
begin
  AResult := Default(TAtlasMutationRoutineResult);
  AResult.FileName := AFileName;
  AResult.Routine := TJsonRead.Text(AObject, 'routine');
  AResult.Body := TJsonRead.Text(AObject, 'body');
  AResult.Line := TJsonRead.IntOr(AObject, 'line', -1);
  AResult.EndLine := TJsonRead.IntOr(AObject, 'endLine', -1);
  AResult.AtUtc := SummaryTimeOf(TJsonRead.Text(AObject, 'at'));
  mItems := TJsonRead.Items(AObject, 'mutants');
  if mItems <> nil then
  begin
    for mItem in mItems do
    begin
      mObject := TJsonRead.AsObject(mItem);
      if (mObject <> nil) and OutcomeOf(mObject, mOutcome) then
      begin
        AResult.Outcomes := AResult.Outcomes + [mOutcome];
      end;
    end;
  end;
  Result := AResult.Routine <> '';
end;

/// <summary>Routinen eines Eintrags von "files" in AResults.</summary>
procedure LoadFile(AObject: TJSONObject; AResults: TAtlasMutationResults);
var
  mFileName: string;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mObject: TJSONObject;
  mResult: TAtlasMutationRoutineResult;
begin
  mFileName := TJsonRead.Text(AObject, 'file');
  mItems := TJsonRead.Items(AObject, 'routines');
  if (mFileName = '') or (mItems = nil) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    mObject := TJsonRead.AsObject(mItem);
    if (mObject <> nil) and RoutineOf(mObject, mFileName, mResult) then
    begin
      AResults.Put(mResult);
    end;
  end;
end;

function TAtlasMutationResults.LoadJson(const AJson: string): Boolean;
var
  mRoot, mObject: TJSONObject;
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  FRoutines.Clear;
  mRoot := TJsonRead.ParseObject(AJson);
  if mRoot = nil then
  begin
    Exit(False);
  end;
  try
    Result := TJsonRead.IntOr(mRoot, 'format', 0) = cFormat;
    if not Result then
    begin
      Exit;
    end;
    mItems := TJsonRead.Items(mRoot, 'files');
    if mItems = nil then
    begin
      Exit;
    end;
    for mItem in mItems do
    begin
      mObject := TJsonRead.AsObject(mItem);
      if mObject <> nil then
      begin
        LoadFile(mObject, Self);
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

end.
