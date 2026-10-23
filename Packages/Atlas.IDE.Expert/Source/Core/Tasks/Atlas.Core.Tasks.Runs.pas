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
    FileName = 'tasks.json';
    FormatVersion = 1;
    MaxProjects = 50;
  private type
    TProject = class
      Key: string;
      Last: TArray<TAtlasTaskLastRun>;
      Hidden: TArray<string>;
      Used: TDateTime;
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
  Atlas.Text.Encoding;

{ TAtlasTaskLines }

constructor TAtlasTaskLines.Create(ACodePage: Integer);
begin
  inherited Create;
  FCodePage := ACodePage;
end;

class function TAtlasTaskLines.Clean(const ALine: string): string;
var
  Index, Stop: Integer;
begin
  Result := ALine;
  if (Result <> '') and (Result[Length(Result)] = #13) then
    SetLength(Result, Length(Result) - 1);
  if Pos(#27, Result) = 0 then
    Exit;
  // Steuerfolgen der Konsole (pwsh färbt Fehler): CSI „ESC [ … Buchstabe“,
  // OSC „ESC ] … BEL“ bzw. „… ESC \“, sonst ESC mit einem Zeichen.
  Index := Pos(#27, Result);
  while Index > 0 do
  begin
    Stop := Index + 1;
    if (Stop <= Length(Result)) and (Result[Stop] = '[') then
    begin
      Inc(Stop);
      while (Stop <= Length(Result)) and not CharInSet(Result[Stop], ['@'..'~']) do
        Inc(Stop);
    end
    else if (Stop <= Length(Result)) and (Result[Stop] = ']') then
    begin
      while (Stop <= Length(Result)) and (Result[Stop] <> #7) and not ((Result[Stop] = '\') and
        (Result[Stop - 1] = #27)) do
        Inc(Stop);
    end;
    Delete(Result, Index, Stop - Index + 1);
    Index := Pos(#27, Result);
  end;
end;

function TAtlasTaskLines.Decode(const ABytes: TBytes; AStart, ACount: Integer): string;
var
  Encoding: TEncoding;
begin
  if ACount <= 0 then
    Exit('');
  // Gültiges UTF-8 (ohne überlange Formen, Atlas.Text) geht vor der Codepage.
  if (FCodePage = 0) or TTextEncodingProbe.IsValidUtf8(Copy(ABytes, AStart, ACount), 0) then
    Exit(Clean(TEncoding.UTF8.GetString(ABytes, AStart, ACount)));
  try
    Encoding := TEncoding.GetEncoding(FCodePage);
    try
      Result := Clean(Encoding.GetString(ABytes, AStart, ACount));
    finally
      Encoding.Free;
    end;
  except
    on Exception do
      Result := Clean(TEncoding.ANSI.GetString(ABytes, AStart, ACount));
  end;
end;

function TAtlasTaskLines.Feed(const ABytes: TBytes; ACount: Integer): TArray<string>;
var
  Data: TBytes;
  Index, Start: Integer;
begin
  Result := nil;
  if ACount <= 0 then
    Exit;
  Data := FPending;
  SetLength(Data, Length(FPending) + ACount);
  Move(ABytes[0], Data[Length(FPending)], ACount);
  Start := 0;
  for Index := 0 to High(Data) do
    if Data[Index] = 10 then
    begin
      Result := Result + [Decode(Data, Start, Index - Start)];
      Start := Index + 1;
    end;
  FPending := Copy(Data, Start, Length(Data) - Start);
end;

function TAtlasTaskLines.Flush: TArray<string>;
begin
  Result := nil;
  if Length(FPending) > 0 then
    Result := [Decode(FPending, 0, Length(FPending))];
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
  Finding: TAtlasTaskFinding;
begin
  Result := Default(TAtlasTaskCounts);
  for Finding in Findings do
    case Finding.Severity of
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
  Entry: TAtlasTaskGateEntry;
begin
  Result := Default(TAtlasTaskGateDecision);
  for Entry in AEntries do
    case Entry.Mode of
      TAtlasTaskBeforeBuild.Block:
        if Fails(Entry.Run) then
          Result.Blocking := Result.Blocking + [Entry.Run];
      TAtlasTaskBeforeBuild.Warn:
        if Fails(Entry.Run) or (Entry.Run.Counts.Total > 0) then
          Result.Warnings := Result.Warnings + [Entry.Run];
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
  OutcomeNames: array[TAtlasTaskOutcome] of string = ('finished', 'programMissing', 'startFailed', 'timedOut',
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
  Project: TProject;
  Wanted: string;
begin
  Wanted := Key(AProject);
  for Project in FProjects do
    if Project.Key = Wanted then
      Exit(Project);
  Result := nil;
end;

function TAtlasTaskHistory.Ensure(const AProject: string): TProject;
var
  Oldest, Index: Integer;
begin
  Result := Find(AProject);
  if Result <> nil then
    Exit;
  // Höchstens MaxProjects: das am längsten nicht benutzte fällt weg.
  if FProjects.Count >= MaxProjects then
  begin
    Oldest := 0;
    for Index := 1 to FProjects.Count - 1 do
      if FProjects[Index].Used < FProjects[Oldest].Used then
        Oldest := Index;
    FProjects.Delete(Oldest);
  end;
  Result := TProject.Create;
  Result.Key := Key(AProject);
  FProjects.Add(Result);
end;

procedure TAtlasTaskHistory.Remember(const AProject: string; const ARun: TAtlasTaskRun);
var
  Project: TProject;
  Index: Integer;
begin
  Project := Ensure(AProject);
  Project.Used := ARun.FinishedAt;
  for Index := 0 to High(Project.Last) do
    if SameText(Project.Last[Index].Name, ARun.Name) then
    begin
      Project.Last[Index] := TAtlasTaskLastRun.From(ARun);
      Exit;
    end;
  Project.Last := Project.Last + [TAtlasTaskLastRun.From(ARun)];
end;

function TAtlasTaskHistory.LastRun(const AProject, AName: string; out ARun: TAtlasTaskLastRun): Boolean;
var
  Project: TProject;
  Run: TAtlasTaskLastRun;
begin
  ARun := Default(TAtlasTaskLastRun);
  Project := Find(AProject);
  if Project <> nil then
    for Run in Project.Last do
      if SameText(Run.Name, AName) then
      begin
        ARun := Run;
        Exit(True);
      end;
  Result := False;
end;

function TAtlasTaskHistory.LastRuns(const AProject: string): TArray<TAtlasTaskLastRun>;
var
  Project: TProject;
begin
  Result := nil;
  Project := Find(AProject);
  if Project <> nil then
    Result := Copy(Project.Last);
end;

function TAtlasTaskHistory.IsHidden(const AProject, AName: string): Boolean;
var
  Name: string;
begin
  for Name in HiddenNames(AProject) do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

procedure TAtlasTaskHistory.SetHidden(const AProject, AName: string; AHidden: Boolean);
var
  Project: TProject;
  Kept: TArray<string>;
  Name: string;
begin
  if IsHidden(AProject, AName) = AHidden then
    Exit;
  Project := Ensure(AProject);
  if AHidden then
  begin
    Project.Hidden := Project.Hidden + [AName];
    Exit;
  end;
  Kept := nil;
  for Name in Project.Hidden do
    if not SameText(Name, AName) then
      Kept := Kept + [Name];
  Project.Hidden := Kept;
end;

function TAtlasTaskHistory.HiddenNames(const AProject: string): TArray<string>;
var
  Project: TProject;
begin
  Result := nil;
  Project := Find(AProject);
  if Project <> nil then
    Result := Copy(Project.Hidden);
end;

function TAtlasTaskHistory.ToJson: string;
var
  Root, Projects, Item, Last, RunObject: TJSONObject;
  Hidden: TJSONArray;
  Project: TProject;
  Run: TAtlasTaskLastRun;
  Name: string;
begin
  Root := TJSONObject.Create;
  try
    Root.AddPair('format', TJSONNumber.Create(FormatVersion));
    Projects := TJSONObject.Create;
    Root.AddPair('projects', Projects);
    for Project in FProjects do
    begin
      Item := TJSONObject.Create;
      Projects.AddPair(Project.Key, Item);
      Item.AddPair('used', DateToISO8601(Project.Used, False));
      Hidden := TJSONArray.Create;
      for Name in Project.Hidden do
        Hidden.Add(Name);
      Item.AddPair('hidden', Hidden);
      Last := TJSONObject.Create;
      Item.AddPair('last', Last);
      for Run in Project.Last do
      begin
        RunObject := TJSONObject.Create;
        RunObject.AddPair('outcome', OutcomeNames[Run.Outcome]);
        RunObject.AddPair('exitCode', TJSONNumber.Create(Run.ExitCode));
        RunObject.AddPair('errors', TJSONNumber.Create(Run.Counts.Errors));
        RunObject.AddPair('warnings', TJSONNumber.Create(Run.Counts.Warnings));
        RunObject.AddPair('infos', TJSONNumber.Create(Run.Counts.Infos));
        RunObject.AddPair('durationMs', TJSONNumber.Create(Run.DurationMs));
        RunObject.AddPair('finished', DateToISO8601(Run.FinishedAt, False));
        Last.AddPair(Run.Name, RunObject);
      end;
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function IntOf(AObject: TJSONObject; const AName: string): Int64;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if not (Value is TJSONNumber) or not TryStrToInt64(Value.ToString, Result) then
    Result := 0;
end;

function DateOf(AObject: TJSONObject; const AName: string): TDateTime;
var
  Value: TJSONValue;
begin
  Value := AObject.GetValue(AName);
  if not (Value is TJSONString) or not TryISO8601ToDate(Value.Value, Result, False) then
    Result := 0;
end;

function TAtlasTaskHistory.FromJson(const AText: string): Boolean;
var
  Parsed, Projects, Hidden, Last, Element: TJSONValue;
  Pair, RunPair: TJSONPair;
  Project: TProject;
  Run: TAtlasTaskLastRun;
  Outcome: TAtlasTaskOutcome;
  RunObject: TJSONObject;
begin
  Clear;
  Parsed := TJSONObject.ParseJSONValue(AText);
  try
    Result := Parsed is TJSONObject;
    if not Result then
      Exit;
    Projects := TJSONObject(Parsed).GetValue('projects');
    if not (Projects is TJSONObject) then
      Exit;
    for Pair in TJSONObject(Projects) do
    begin
      if not (Pair.JsonValue is TJSONObject) or (FProjects.Count >= MaxProjects) then
        Continue;
      Project := TProject.Create;
      FProjects.Add(Project);
      Project.Key := Key(Pair.JsonString.Value);
      Project.Used := DateOf(TJSONObject(Pair.JsonValue), 'used');
      Hidden := TJSONObject(Pair.JsonValue).GetValue('hidden');
      if Hidden is TJSONArray then
        for Element in TJSONArray(Hidden) do
          if Element is TJSONString then
            Project.Hidden := Project.Hidden + [Element.Value];
      Last := TJSONObject(Pair.JsonValue).GetValue('last');
      if Last is TJSONObject then
        for RunPair in TJSONObject(Last) do
        begin
          if not (RunPair.JsonValue is TJSONObject) then
            Continue;
          RunObject := TJSONObject(RunPair.JsonValue);
          Run := Default(TAtlasTaskLastRun);
          Run.Name := RunPair.JsonString.Value;
          Run.Outcome := TAtlasTaskOutcome.Finished;
          Element := RunObject.GetValue('outcome');
          if Element is TJSONString then
            for Outcome := Low(TAtlasTaskOutcome) to High(TAtlasTaskOutcome) do
              if SameText(Element.Value, OutcomeNames[Outcome]) then
                Run.Outcome := Outcome;
          Run.ExitCode := Integer(IntOf(RunObject, 'exitCode'));
          Run.Counts.Errors := Integer(IntOf(RunObject, 'errors'));
          Run.Counts.Warnings := Integer(IntOf(RunObject, 'warnings'));
          Run.Counts.Infos := Integer(IntOf(RunObject, 'infos'));
          Run.DurationMs := IntOf(RunObject, 'durationMs');
          Run.FinishedAt := DateOf(RunObject, 'finished');
          Project.Last := Project.Last + [Run];
        end;
    end;
  finally
    Parsed.Free;
  end;
end;

end.
