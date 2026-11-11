unit Atlas.Core.Tasks.Runs;

// Läufe von Projektaufgaben (#900), ohne VCL und Open Tools API:
// - TAtlasTaskLines zerlegt die Ausgabe eines Prozesses in Zeilen, sobald
//   ein Zeilenende da ist: je Zeile UTF-8, wenn die Bytes gültiges UTF-8
//   sind, sonst die Codepage der Konsole (pwsh und cmd schreiben umgeleitet
//   in der OEM-Codepage); CR und Farbfolgen (ESC [ … m) fallen weg.
// - TAtlasTaskRun: Ergebnis eines Laufs mit Ausgabe, Befunden, Exit-Code,
//   Dauer und Ausgang (fertig, Programm fehlt, Start fehlgeschlagen,
//   Zeitlimit, abgebrochen).
// - TAtlasTaskGate: Entscheidung vor dem Build. warn bricht nie ab; block
//   bricht ab, wenn eine Aufgabe nicht sauber endet (Exit-Code ≠ 0, nicht
//   gestartet, Zeitlimit, abgebrochen) oder Befunde der Schwere error hat.
// - TAtlasTaskHistory: letzter Lauf je Aufgabe und ausgeblendete Aufgaben je
//   Projekt, als JSON für %APPDATA%\Atlas\tasks.json (Statusfeld #591,
//   Auswahl „Aufgabe ausführen …“, Problemliste).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers;

type
{$SCOPEDENUMS ON}
  TAtlasTaskOutcome = (Finished, ProgramMissing, StartFailed, TimedOut, Cancelled);
{$SCOPEDENUMS OFF}

  TAtlasTaskLineProc = reference to procedure(const ALine: string);

  /// <summary>Ergebnis des Prozesses einer Aufgabe (Atlas.Core.Tasks.Adapters.Process).</summary>
  TAtlasTaskProcessResult = record
    Outcome: TAtlasTaskOutcome;
    ExitCode: Integer;
    /// <summary>StartFailed: Grund oder fehlender Arbeitsordner; ProgramMissing: der Befehl.</summary>
    Error: string;
  end;

  TAtlasTaskLines = class
  private
    FPending: TBytes;
    FCodePage: Integer;
    function Decode(const ABytes: TBytes; AStart, ACount: Integer): string;
  public
    /// <summary>ACodePage: Codepage für Zeilen, die kein gültiges UTF-8 sind (GetOEMCP; 0 = nur UTF-8).</summary>
    constructor Create(ACodePage: Integer);
    /// <summary>Neue Bytes; liefert die Zeilen, die damit fertig sind.</summary>
    function Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
    /// <summary>Rest ohne Zeilenende am Schluss; leer, wenn nichts mehr da ist.</summary>
    function Flush: TArray<string>;
    /// <summary>Zeile ohne CR und ohne Farbfolgen.</summary>
    class function Clean(const ALine: string): string; static;
  end;

  TAtlasTaskCounts = record
    Errors: Integer;
    Warnings: Integer;
    Infos: Integer;
    function Total: Integer;
  end;

  TAtlasTaskRun = record
    Name: string;
    CommandLine: string;
    Cwd: string;
    Outcome: TAtlasTaskOutcome;
    ExitCode: Integer;
    DurationMs: Int64;
    /// <summary>Ende des Laufs in Ortszeit.</summary>
    FinishedAt: TDateTime;
    Lines: TArray<string>;
    Findings: TAtlasTaskFindings;
    /// <summary>Grund, wenn der Prozess nicht lief (fehlendes Programm mit Pfad, Fehler von CreateProcess).</summary>
    Error: string;
    function Counts: TAtlasTaskCounts;
    /// <summary>Lief und endete mit 0.</summary>
    function ExitedCleanly: Boolean;
    /// <summary>Kurzform für Statusfeld und Auswahl: Ausgang, Exit-Code, Befunde.</summary>
    function Passed: Boolean;
  end;

  TAtlasTaskGateEntry = record
    Mode: TAtlasTaskBeforeBuild;
    Run: TAtlasTaskRun;
  end;

  TAtlasTaskGateDecision = record
    /// <summary>Build abbrechen.</summary>
    Block: Boolean;
    /// <summary>Läufe, die mit block den Abbruch verursachen.</summary>
    Blocking: TArray<TAtlasTaskRun>;
    /// <summary>Läufe mit warn, die nicht sauber enden oder Befunde haben (nur Meldung).</summary>
    Warnings: TArray<TAtlasTaskRun>;
  end;

  TAtlasTaskGate = class
  public
    /// <summary>Verursacht ARun bei block einen Abbruch?</summary>
    class function Fails(const ARun: TAtlasTaskRun): Boolean; static;
    class function Decide(const AEntries: TArray<TAtlasTaskGateEntry>): TAtlasTaskGateDecision; static;
  end;

  /// <summary>Letzter Lauf einer Aufgabe ohne Ausgabe (für Statusfeld und Auswahl).</summary>
  TAtlasTaskLastRun = record
    Name: string;
    Outcome: TAtlasTaskOutcome;
    ExitCode: Integer;
    Counts: TAtlasTaskCounts;
    DurationMs: Int64;
    FinishedAt: TDateTime;
    class function From(const ARun: TAtlasTaskRun): TAtlasTaskLastRun; static;
    function Passed: Boolean;
  end;

  TAtlasTaskHistory = class
  public const
    cFileName = 'tasks.json';
    cFormatVersion = 1;
    cMaxProjects = 50;
  private type
    TProject = class
      FKey: string;
      FLast: TArray<TAtlasTaskLastRun>;
      FHidden: TArray<string>;
      FUsed: TDateTime;
    end;
  private
    FProjects: TObjectList<TProject>;
    function Find(const AProject: string): TProject;
    function Ensure(const AProject: string): TProject;
  public
    constructor Create;
    destructor Destroy; override;
    class function Key(const AProject: string): string; static;
    procedure Clear;
    /// <summary>Letzter Lauf von ARun.Name im Projekt AProject merken.</summary>
    procedure Remember(const AProject: string; const ARun: TAtlasTaskRun);
    function LastRun(const AProject, AName: string; out ARun: TAtlasTaskLastRun): Boolean;
    function LastRuns(const AProject: string): TArray<TAtlasTaskLastRun>;
    function IsHidden(const AProject, AName: string): Boolean;
    procedure SetHidden(const AProject, AName: string; AHidden: Boolean);
    function HiddenNames(const AProject: string): TArray<string>;
    function ToJson: string;
    /// <summary>Übernimmt AText; False bei ungültigem Text (die Ablage bleibt leer).</summary>
    function FromJson(const AText: string): Boolean;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Text.Encoding,
  Atlas.Text.Json;

{ TAtlasTaskLines }

constructor TAtlasTaskLines.Create(ACodePage: Integer);
begin
  inherited Create;
  FCodePage := ACodePage;
end;

/// <summary>Letztes Zeichen der Steuerfolge, die bei AIndex mit ESC beginnt: CSI „ESC [ … Buchstabe“,
/// OSC „ESC ] … BEL“ bzw. „… ESC \“, sonst ESC mit einem Zeichen.</summary>
function EscapeEnd(const AText: string; AIndex: Integer): Integer;
begin
  Result := AIndex + 1;
  if (Result <= Length(AText)) and (AText[Result] = '[') then
  begin
    Inc(Result);
    while (Result <= Length(AText)) and not CharInSet(AText[Result], ['@'..'~']) do
    begin
      Inc(Result);
    end;
  end
  else if (Result <= Length(AText)) and (AText[Result] = ']') then
  begin
    while (Result <= Length(AText)) and (AText[Result] <> #7) and not ((AText[Result] = '\') and
      (AText[Result - 1] = #27)) do
    begin
      Inc(Result);
    end;
  end;
end;

class function TAtlasTaskLines.Clean(const ALine: string): string;
var
  mIndex: Integer;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
  begin
    SetLength(Result, Length(Result) - 1);
  end;
  // Steuerfolgen der Konsole (pwsh färbt Fehler).
  mIndex := Pos(#27, Result);
  while mIndex > 0 do
  begin
    Delete(Result, mIndex, EscapeEnd(Result, mIndex) - mIndex + 1);
    mIndex := Pos(#27, Result);
  end;
end;

function TAtlasTaskLines.Decode(const ABytes: TBytes; AStart, ACount: Integer): string;
var
  mEncoding: TEncoding;
begin
  if ACount <= 0 then
  begin
    Exit('');
  end;
  // Gültiges UTF-8 (ohne überlange Formen, Atlas.Text) geht vor der Codepage.
  if (FCodePage = 0) or TTextEncodingProbe.IsValidUtf8(Copy(ABytes, AStart, ACount), 0) then
  begin
    Exit(Clean(TEncoding.UTF8.GetString(ABytes, AStart, ACount)));
  end;
  try
    mEncoding := TEncoding.GetEncoding(FCodePage);
    try
      Result := Clean(mEncoding.GetString(ABytes, AStart, ACount));
    finally
      mEncoding.Free;
    end;
  except
    on Exception do
      Result := Clean(TEncoding.ANSI.GetString(ABytes, AStart, ACount));
  end;
end;

function TAtlasTaskLines.Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
var
  mData: TBytes;
  mIndex, mStart: Integer;
begin
  Result := nil;
  if ACount <= 0 then
  begin
    Exit;
  end;
  mData := FPending;
  SetLength(mData, Length(FPending) + ACount);
  Move(ABytes[0], mData[Length(FPending)], ACount);
  mStart := 0;
  for mIndex := 0 to High(mData) do
  begin
    if mData[mIndex] = 10 then
    begin
      Result := Result + [Decode(mData, mStart, mIndex - mStart)];
      mStart := mIndex + 1;
    end;
  end;
  FPending := Copy(mData, mStart, Length(mData) - mStart);
end;

function TAtlasTaskLines.Flush: TArray<string>;
begin
  Result := nil;
  if Length(FPending) > 0 then
  begin
    Result := [Decode(FPending, 0, Length(FPending))];
  end;
  FPending := nil;
end;

{ TAtlasTaskCounts }

function TAtlasTaskCounts.Total: Integer;
begin
  Result := Errors + Warnings + Infos;
end;

{ TAtlasTaskRun }

function TAtlasTaskRun.Counts: TAtlasTaskCounts;
var
  mFinding: TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskCounts);
  for mFinding in Findings do
    case mFinding.Severity of
      TAtlasTaskSeverity.Error:
        Inc(Result.Errors);
      TAtlasTaskSeverity.Warning:
        Inc(Result.Warnings);
    else
      Inc(Result.Infos);
    end;
end;

function TAtlasTaskRun.ExitedCleanly: Boolean;
begin
  Result := (Outcome = TAtlasTaskOutcome.Finished) and (ExitCode = 0);
end;

function TAtlasTaskRun.Passed: Boolean;
begin
  Result := ExitedCleanly and (Counts.Errors = 0);
end;

{ TAtlasTaskGate }

class function TAtlasTaskGate.Fails(const ARun: TAtlasTaskRun): Boolean;
begin
  Result := not ARun.Passed;
end;

class function TAtlasTaskGate.Decide(const AEntries: TArray<TAtlasTaskGateEntry>): TAtlasTaskGateDecision;
var
  mEntry: TAtlasTaskGateEntry;
begin
  Result := Default(TAtlasTaskGateDecision);
  for mEntry in AEntries do
    case mEntry.Mode of
      TAtlasTaskBeforeBuild.Block:
        if Fails(mEntry.Run) then
        begin
          Result.Blocking := Result.Blocking + [mEntry.Run];
        end;
      TAtlasTaskBeforeBuild.Warn:
        if Fails(mEntry.Run) or (mEntry.Run.Counts.Total > 0) then
        begin
          Result.Warnings := Result.Warnings + [mEntry.Run];
        end;
      TAtlasTaskBeforeBuild.Off: ;
    end;
  Result.Block := Length(Result.Blocking) > 0;
end;

{ TAtlasTaskLastRun }

class function TAtlasTaskLastRun.From(const ARun: TAtlasTaskRun): TAtlasTaskLastRun;
begin
  Result.Name := ARun.Name;
  Result.Outcome := ARun.Outcome;
  Result.ExitCode := ARun.ExitCode;
  Result.Counts := ARun.Counts;
  Result.DurationMs := ARun.DurationMs;
  Result.FinishedAt := ARun.FinishedAt;
end;

function TAtlasTaskLastRun.Passed: Boolean;
begin
  Result := (Outcome = TAtlasTaskOutcome.Finished) and (ExitCode = 0) and (Counts.Errors = 0);
end;

{ TAtlasTaskHistory }

const
  cOutcomeNames: array[TAtlasTaskOutcome] of string = ('finished', 'programMissing', 'startFailed', 'timedOut',
    'cancelled');

constructor TAtlasTaskHistory.Create;
begin
  inherited Create;
  FProjects := TObjectList<TProject>.Create(True);
end;

destructor TAtlasTaskHistory.Destroy;
begin
  FProjects.Free;
  inherited Destroy;
end;

class function TAtlasTaskHistory.Key(const AProject: string): string;
begin
  Result := AnsiLowerCase(StringReplace(Trim(AProject), '/', '\', [rfReplaceAll]));
end;

procedure TAtlasTaskHistory.Clear;
begin
  FProjects.Clear;
end;

function TAtlasTaskHistory.Find(const AProject: string): TProject;
var
  mProject: TProject;
  mWanted: string;
begin
  mWanted := Key(AProject);
  for mProject in FProjects do
  begin
    if mProject.FKey = mWanted then
    begin
      Exit(mProject);
    end;
  end;
  Result := nil;
end;

function TAtlasTaskHistory.Ensure(const AProject: string): TProject;
var
  mOldest, mIndex: Integer;
begin
  Result := Find(AProject);
  if Result <> nil then
  begin
    Exit;
  end;
  // Höchstens MaxProjects: das am längsten nicht benutzte fällt weg.
  if FProjects.Count >= cMaxProjects then
  begin
    mOldest := 0;
    for mIndex := 1 to FProjects.Count - 1 do
    begin
      if FProjects[mIndex].FUsed < FProjects[mOldest].FUsed then
      begin
        mOldest := mIndex;
      end;
    end;
    FProjects.Delete(mOldest);
  end;
  Result := TProject.Create;
  Result.FKey := Key(AProject);
  FProjects.Add(Result);
end;

procedure TAtlasTaskHistory.Remember(const AProject: string; const ARun: TAtlasTaskRun);
var
  mProject: TProject;
  mIndex: Integer;
begin
  mProject := Ensure(AProject);
  mProject.FUsed := ARun.FinishedAt;
  for mIndex := 0 to High(mProject.FLast) do
  begin
    if SameText(mProject.FLast[mIndex].Name, ARun.Name) then
    begin
      mProject.FLast[mIndex] := TAtlasTaskLastRun.From(ARun);
      Exit;
    end;
  end;
  mProject.FLast := mProject.FLast + [TAtlasTaskLastRun.From(ARun)];
end;

function TAtlasTaskHistory.LastRun(const AProject, AName: string; out ARun: TAtlasTaskLastRun): Boolean;
var
  mProject: TProject;
  mRun: TAtlasTaskLastRun;
begin
  ARun := Default(TAtlasTaskLastRun);
  mProject := Find(AProject);
  if mProject <> nil then
  begin
    for mRun in mProject.FLast do
    begin
      if SameText(mRun.Name, AName) then
      begin
        ARun := mRun;
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TAtlasTaskHistory.LastRuns(const AProject: string): TArray<TAtlasTaskLastRun>;
var
  mProject: TProject;
begin
  Result := nil;
  mProject := Find(AProject);
  if mProject <> nil then
  begin
    Result := Copy(mProject.FLast);
  end;
end;

function TAtlasTaskHistory.IsHidden(const AProject, AName: string): Boolean;
var
  mName: string;
begin
  for mName in HiddenNames(AProject) do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure TAtlasTaskHistory.SetHidden(const AProject, AName: string; AHidden: Boolean);
var
  mProject: TProject;
  mKept: TArray<string>;
  mName: string;
begin
  if IsHidden(AProject, AName) = AHidden then
  begin
    Exit;
  end;
  mProject := Ensure(AProject);
  if AHidden then
  begin
    mProject.FHidden := mProject.FHidden + [AName];
    Exit;
  end;
  mKept := nil;
  for mName in mProject.FHidden do
  begin
    if not SameText(mName, AName) then
    begin
      mKept := mKept + [mName];
    end;
  end;
  mProject.FHidden := mKept;
end;

function TAtlasTaskHistory.HiddenNames(const AProject: string): TArray<string>;
var
  mProject: TProject;
begin
  Result := nil;
  mProject := Find(AProject);
  if mProject <> nil then
  begin
    Result := Copy(mProject.FHidden);
  end;
end;

function TAtlasTaskHistory.ToJson: string;
var
  mRoot, mProjects, mItem, mLast, mRunObject: TJSONObject;
  mHidden: TJSONArray;
  mProject: TProject;
  mRun: TAtlasTaskLastRun;
  mName: string;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('format', TJSONNumber.Create(cFormatVersion));
    mProjects := TJSONObject.Create;
    mRoot.AddPair('projects', mProjects);
    for mProject in FProjects do
    begin
      mItem := TJSONObject.Create;
      mProjects.AddPair(mProject.FKey, mItem);
      mItem.AddPair('used', DateToISO8601(mProject.FUsed, False));
      mHidden := TJSONArray.Create;
      for mName in mProject.FHidden do
      begin
        mHidden.Add(mName);
      end;
      mItem.AddPair('hidden', mHidden);
      mLast := TJSONObject.Create;
      mItem.AddPair('last', mLast);
      for mRun in mProject.FLast do
      begin
        mRunObject := TJSONObject.Create;
        mRunObject.AddPair('outcome', cOutcomeNames[mRun.Outcome]);
        mRunObject.AddPair('exitCode', TJSONNumber.Create(mRun.ExitCode));
        mRunObject.AddPair('errors', TJSONNumber.Create(mRun.Counts.Errors));
        mRunObject.AddPair('warnings', TJSONNumber.Create(mRun.Counts.Warnings));
        mRunObject.AddPair('infos', TJSONNumber.Create(mRun.Counts.Infos));
        mRunObject.AddPair('durationMs', TJSONNumber.Create(mRun.DurationMs));
        mRunObject.AddPair('finished', DateToISO8601(mRun.FinishedAt, False));
        mLast.AddPair(mRun.Name, mRunObject);
      end;
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function DateOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  mValue: TJSONValue;
begin
  mValue := AObject.GetValue(AName);
  if not (mValue is TJSONString) or not TryISO8601ToDate(mValue.Value, Result, False) then
  begin
    Result := 0;
  end;
end;

function ReadHidden(AValue: TJSONValue): TArray<string>;
var
  mElement: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mElement in TJSONArray(AValue) do
  begin
    if mElement is TJSONString then
    begin
      Result := Result + [mElement.Value];
    end;
  end;
end;

function ReadOutcome(AValue: TJSONValue): TAtlasTaskOutcome;
var
  mOutcome: TAtlasTaskOutcome;
begin
  Result := TAtlasTaskOutcome.Finished;
  if not (AValue is TJSONString) then
  begin
    Exit;
  end;
  for mOutcome := Low(TAtlasTaskOutcome) to High(TAtlasTaskOutcome) do
  begin
    if SameText(AValue.Value, cOutcomeNames[mOutcome]) then
    begin
      Result := mOutcome;
    end;
  end;
end;

function ReadRun(const AName: string; AObject: TJSONObject): TAtlasTaskLastRun;
begin
  Result := Default(TAtlasTaskLastRun);
  Result.Name := AName;
  Result.Outcome := ReadOutcome(AObject.GetValue('outcome'));
  Result.ExitCode := Integer(TJsonRead.Int64Or(AObject, 'exitCode', 0));
  Result.Counts.Errors := Integer(TJsonRead.Int64Or(AObject, 'errors', 0));
  Result.Counts.Warnings := Integer(TJsonRead.Int64Or(AObject, 'warnings', 0));
  Result.Counts.Infos := Integer(TJsonRead.Int64Or(AObject, 'infos', 0));
  Result.DurationMs := TJsonRead.Int64Or(AObject, 'durationMs', 0);
  Result.FinishedAt := DateOf(AObject, 'finished');
end;

function ReadRuns(AValue: TJSONValue): TArray<TAtlasTaskLastRun>;
var
  mPair: TJSONPair;
begin
  Result := nil;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  for mPair in TJSONObject(AValue) do
  begin
    if mPair.JsonValue is TJSONObject then
    begin
      Result := Result + [ReadRun(mPair.JsonString.Value, TJSONObject(mPair.JsonValue))];
    end;
  end;
end;

function TAtlasTaskHistory.FromJson(const AText: string): Boolean;
var
  mParsed, mProjects: TJSONValue;
  mPair: TJSONPair;
  mItem: TJSONObject;
  mProject: TProject;
begin
  Clear;
  mParsed := TJSONObject.ParseJSONValue(AText);
  try
    Result := mParsed is TJSONObject;
    if not Result then
    begin
      Exit;
    end;
    mProjects := TJSONObject(mParsed).GetValue('projects');
    if not (mProjects is TJSONObject) then
    begin
      Exit;
    end;
    for mPair in TJSONObject(mProjects) do
    begin
      if not (mPair.JsonValue is TJSONObject) or (FProjects.Count >= cMaxProjects) then
      begin
        Continue;
      end;
      mItem := TJSONObject(mPair.JsonValue);
      mProject := TProject.Create;
      FProjects.Add(mProject);
      mProject.FKey := Key(mPair.JsonString.Value);
      mProject.FUsed := DateOf(mItem, 'used');
      mProject.FHidden := ReadHidden(mItem.GetValue('hidden'));
      mProject.FLast := ReadRuns(mItem.GetValue('last'));
    end;
  finally
    mParsed.Free;
  end;
end;

end.
