unit Atlas.IDE.Debug.ParallelWatch;

// Ausdrücke in allen Threads auswerten (#866) in der IDE: Fenster „Parallel auswerten“ (TAtlasIdeDebugDockPanel).
//   - Ausdrücke je Projekt in %LOCALAPPDATA%\Atlas\debug-parallel-watch.json (höchstens cLimit, ältester links).
//   - Bei jedem Halt, solange das Fenster sichtbar ist: Stapel aller Threads lesen (TAtlasIdeDebugThreads, wie
//     „Parallele Aufrufstapel“ #837; unter LLDB bis zu cRetries Versuche), dann je Thread und Ausdruck auswerten, in
//     Zeitscheiben von cSliceMs, damit die IDE bedienbar bleibt. Ab TAtlasParallelWatch.cAutoLimit Threads erst
//     auf „Auswerten“.
//   - Ausgewertet wird mit IOTAThread.Evaluate des jeweiligen Threads; als Ort bekommt der Debugger Datei und Zeile
//     des obersten eigenen Rahmens (#578). Den aktuellen Thread wechselt Atlas dafür nicht; hat ihn die IDE
//     dennoch gewechselt, stellt Atlas ihn nach jeder Zeitscheibe wieder her. Alle Auswertungen laufen als eigene
//     Auswertung der Sitzung (Zustandswechsel sind kein Fortsetzen).
//   - Doppelklick bzw. Enter wechselt zum Thread und springt auf die Zeile seines Rahmens.
//   - Markierte Threads (#852, mit debug.threadsInSource) stehen oben und tragen ⚑.
// Teil „DebugParallelWatch“ (debug.parallelWatch); aus = kein Fenster, kein Menüpunkt. Nur im Hauptthread
// verwenden.

interface

uses
  System.SysUtils,
  ToolsAPI,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.ParallelWatch,
  Atlas.Core.Debug.DialogCompletion,
  Atlas.IDE.Debug.StopView,
  Atlas.IDE.Debug.DockPanel,
  Atlas.UI.Debug.ParallelWatchFrame;

type
  TAtlasIdeDebugParallelWatch = class(TAtlasIdeDebugStopView)
  public const
    cTickMs = 10;
    cSliceMs = 30;
    /// <summary>So lange wartet Atlas auf einen verzögerten Wert (LLDB).</summary>
    cValueTimeoutMs = 500;
    cRetries = 10;
    cRetryMs = 150;
    cLimit = 20;
    cFileName = 'debug-parallel-watch.json';
  private type
    {$SCOPEDENUMS ON}
    TStep = (Idle, Read, Evaluate);
    {$SCOPEDENUMS OFF}
  private class var
    FInstance: TAtlasIdeDebugParallelWatch;
  private
    FPanel: TAtlasIdeDebugDockPanel;
    FStore: TAtlasExpressionHistory;
    FLoaded: Boolean;
    FWritable: Boolean;
    FStep: TStep;
    FStacks: TAtlasDebugThreadStacks;
    FRows: TAtlasParallelRows;
    /// <summary>Nächste Zelle: Zeile * Zahl der Ausdrücke + Spalte.</summary>
    FNext: Integer;
    FRetries: Integer;
    /// <summary>„Auswerten“ gedrückt: in diesem Halt auch ab cAutoLimit Threads.</summary>
    FAsked: Boolean;
    constructor Create;
    function Frame: TAtlasDebugParallelWatchFrame;
    function Expressions: TArray<string>;
    procedure SetExpressions(const AList: TArray<string>);
    procedure Save;
    procedure Refresh;
    procedure ReadStacks;
    procedure StartValues;
    procedure EvaluateCells;
    function EvaluateCell(const AProcess: IOTAProcess; ACell: Integer): Boolean;
    procedure Show(const ANote: string);
    procedure ShowRunning;
    procedure Open(ARow: Integer);
    procedure Add(const AExpression: string);
    procedure Rename(AIndex: Integer; const AExpression: string);
    procedure Remove(AIndex: Integer);
    procedure WireFrame(AFrame: TAtlasDebugParallelWatchFrame);
  protected
    procedure SessionStopped; override;
    procedure SessionResumed; override;
    procedure SessionEnded; override;
    procedure Advance; override;
  public
    destructor Destroy; override;
    class procedure Start; static;
    class procedure Release; static;
    class function Started: Boolean; static;
    /// <summary>debug.parallelWatch an (und Atlas an)?</summary>
    class function Enabled: Boolean; static;
    /// <summary>Befehl Atlas.DebugParallelWatch: Fenster zeigen und füllen.</summary>
    class procedure ShowWindow; static;
    class procedure ThemeChanged; static;
  end;

implementation

uses
  Vcl.Forms,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Evaluator,
  Atlas.IDE.Debug.EvaluateStore,
  Atlas.IDE.Debug.Threads,
  Atlas.IDE.Debug.ThreadsInSource,
  Atlas.UI.Debug.ParallelWatch.Strings;

const
  /// <summary>Für das Protokoll beim Lesen und Schreiben der Datei.</summary>
  cWhat = 'parallel watch expressions';

/// <summary>Thread mit der Kennung AThreadId in AProcess; nil ohne.</summary>
function ThreadOf(const AProcess: IOTAProcess; AThreadId: Cardinal): IOTAThread;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AProcess.ThreadCount - 1 do
  begin
    if AProcess.Threads[mIndex].GetOSThreadID = AThreadId then
    begin
      Exit(AProcess.Threads[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Markierte Threads (#852), sofern „Threads im Quelltext“ läuft.</summary>
function Flagged: TAtlasDebugThreadSet;
begin
  Result := Default(TAtlasDebugThreadSet);
  if TAtlasIdeDebugThreadsInSource.Started then
  begin
    Result := TAtlasIdeDebugThreadsInSource.Flagged;
  end;
end;

{ TAtlasIdeDebugParallelWatch }

constructor TAtlasIdeDebugParallelWatch.Create;
begin
  inherited Create;
  FStore := TAtlasExpressionHistory.Create(cLimit);
  FPanel := TAtlasIdeDebugDockPanel.Create('AtlasDebugParallelWatch', TAtlasDebugParallelWatchFrame,
    function: string
    begin
      Result := TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchCaption);
    end);
  CreateTimer(cTickMs);
end;

destructor TAtlasIdeDebugParallelWatch.Destroy;
begin
  FreeAndNil(FPanel);
  FreeAndNil(FStore);
  FStacks := nil;
  FRows := nil;
  inherited Destroy;
end;

function TAtlasIdeDebugParallelWatch.Frame: TAtlasDebugParallelWatchFrame;
begin
  Result := nil;
  if (FPanel <> nil) and FPanel.Visible and (FPanel.ExistingFrame is TAtlasDebugParallelWatchFrame) then
  begin
    Result := TAtlasDebugParallelWatchFrame(FPanel.ExistingFrame);
  end;
end;

function TAtlasIdeDebugParallelWatch.Expressions: TArray<string>;
var
  mItems: TArray<string>;
  mIndex: Integer;
begin
  if not FLoaded then
  begin
    FLoaded := True;
    FWritable := TAtlasIdeEvaluateStore.LoadFile(FStore, cFileName, cWhat);
  end;
  // Gespeichert jüngster zuerst; angezeigt ältester links.
  mItems := FStore.Items(TAtlasIdeEvaluateStore.CurrentProject);
  Result := nil;
  SetLength(Result, Length(mItems));
  for mIndex := 0 to High(mItems) do
  begin
    Result[High(mItems) - mIndex] := mItems[mIndex];
  end;
end;

procedure TAtlasIdeDebugParallelWatch.SetExpressions(const AList: TArray<string>);
var
  mProject, mExpression: string;
begin
  mProject := TAtlasIdeEvaluateStore.CurrentProject;
  for mExpression in FStore.Items(mProject) do
  begin
    FStore.Remove(mProject, mExpression);
  end;
  // Ältester zuerst hinzufügen: Der jüngste steht danach vorn.
  for mExpression in AList do
  begin
    FStore.Add(mProject, mExpression);
  end;
  Save;
end;

procedure TAtlasIdeDebugParallelWatch.Save;
begin
  TAtlasIdeEvaluateStore.SaveFile(FStore, cFileName, cWhat, FWritable);
end;

procedure TAtlasIdeDebugParallelWatch.SessionStopped;
begin
  FAsked := False;
  Refresh;
end;

procedure TAtlasIdeDebugParallelWatch.SessionResumed;
begin
  ShowRunning;
end;

procedure TAtlasIdeDebugParallelWatch.SessionEnded;
begin
  ShowRunning;
end;

procedure TAtlasIdeDebugParallelWatch.ShowRunning;
begin
  FTimer.Enabled := False;
  FStep := TStep.Idle;
  FStacks := nil;
  FRows := nil;
  Show(TAtlasParallelWatchStrings.Text(TAtlasParallelWatchTextId.ParallelWatchRunning));
end;

procedure TAtlasIdeDebugParallelWatch.Show(const ANote: string);
var
  mFrame: TAtlasDebugParallelWatchFrame;
begin
  mFrame := Frame;
  if mFrame <> nil then
  begin
    mFrame.SetTable(Expressions, FRows, ANote, (FStep = TStep.Idle) and (FRows <> nil) and (Expressions <> nil));
  end;
end;

procedure TAtlasIdeDebugParallelWatch.Refresh;
begin
  FTimer.Enabled := False;
  FStep := TStep.Idle;
  FStacks := nil;
  FRows := nil;
  if TAtlasIdeDebugSession.StoppedThread = nil then
  begin
    ShowRunning;
    Exit;
  end;
  if Frame = nil then
  begin
    Exit;
  end;
  FRetries := 0;
  FStep := TStep.Read;
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDebugParallelWatch.Advance;
begin
  FTimer.Enabled := False;
  if (TAtlasIdeDebugSession.StoppedThread = nil) or (Frame = nil) then
  begin
    FStep := TStep.Idle;
    Exit;
  end;
  if FStep = TStep.Read then
  begin
    ReadStacks;
  end
  else if FStep = TStep.Evaluate then
  begin
    EvaluateCells;
  end;
end;

procedure TAtlasIdeDebugParallelWatch.ReadStacks;
var
  mProcess: IOTAProcess;
  mStacks: TAtlasDebugThreadStacks;
begin
  mProcess := TAtlasIdeDebugSession.Process;
  if mProcess = nil then
  begin
    FStep := TStep.Idle;
    Exit;
  end;
  mStacks := nil;
  if TAtlasIdeDebugThreads.ReadRange(mProcess, 0, mProcess.ThreadCount, mStacks) and (FRetries < cRetries) then
  begin
    // Der Debugger liefert noch (LLDB): gleich noch einmal.
    Inc(FRetries);
    Show(TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchReading,
      [Length(mStacks), mProcess.ThreadCount]));
    FTimer.Interval := cRetryMs;
    FTimer.Enabled := True;
    Exit;
  end;
  FStacks := mStacks;
  StartValues;
end;

procedure TAtlasIdeDebugParallelWatch.StartValues;
begin
  FRows := TAtlasParallelWatch.Rows(FStacks, Length(Expressions), Flagged);
  FNext := 0;
  FStep := TStep.Idle;
  if (Expressions <> nil) and (TAtlasParallelWatch.Automatic(Length(FStacks)) or FAsked) then
  begin
    FStep := TStep.Evaluate;
    Show(TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchEvaluating,
      [0, Length(FRows) * Length(Expressions)]));
    FTimer.Interval := cTickMs;
    FTimer.Enabled := True;
  end
  else if Expressions <> nil then
  begin
    Show(TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchManual, [Length(FStacks)]));
  end
  else
  begin
    Show('');
  end;
end;

procedure TAtlasIdeDebugParallelWatch.EvaluateCells;
var
  mProcess: IOTAProcess;
  mCurrent: IOTAThread;
  mTotal: Integer;
  mUntil: UInt64;
begin
  mProcess := TAtlasIdeDebugSession.Process;
  mTotal := Length(FRows) * Length(Expressions);
  if mProcess = nil then
  begin
    FStep := TStep.Idle;
    Exit;
  end;
  mCurrent := mProcess.CurrentThread;
  mUntil := TThread.GetTickCount64 + cSliceMs;
  TAtlasIdeDebugSession.BeginInternal;
  try
    while (FNext < mTotal) and (TThread.GetTickCount64 < mUntil) and EvaluateCell(mProcess, FNext) do
    begin
      Inc(FNext);
    end;
  finally
    // Der Thread des Halts bleibt der aktuelle.
    if (mCurrent <> nil) and (mProcess.CurrentThread <> nil) and
      (mProcess.CurrentThread.GetOSThreadID <> mCurrent.GetOSThreadID) then
    begin
      mProcess.CurrentThread := mCurrent;
    end;
    TAtlasIdeDebugSession.EndInternal;
  end;
  if FNext >= mTotal then
  begin
    FStep := TStep.Idle;
    Show('');
    Exit;
  end;
  Show(TAtlasParallelWatchStrings.Fmt(TAtlasParallelWatchTextId.ParallelWatchEvaluating, [FNext, mTotal]));
  FTimer.Interval := cTickMs;
  FTimer.Enabled := True;
end;

function TAtlasIdeDebugParallelWatch.EvaluateCell(const AProcess: IOTAProcess; ACell: Integer): Boolean;
var
  mExpressions: TArray<string>;
  mRow, mColumn: Integer;
  mThread: IOTAThread;
  mText: string;
  mOk: Boolean;
begin
  mExpressions := Expressions;
  Result := mExpressions <> nil;
  if not Result then
  begin
    Exit;
  end;
  mRow := ACell div Length(mExpressions);
  mColumn := ACell mod Length(mExpressions);
  if (mRow > High(FRows)) or (mColumn > High(FRows[mRow].Cells)) then
  begin
    Exit;
  end;
  mThread := ThreadOf(AProcess, FRows[mRow].ThreadId);
  mText := '';
  mOk := (mThread <> nil) and TAtlasIdeDebugEvaluator.EvaluateIn(mThread, mExpressions[mColumn],
    TAtlasIdeEvaluatePlace.Create(FRows[mRow].FileName, FRows[mRow].Line), TAtlasVisualizerEvaluation.Properties,
    cValueTimeoutMs, mText);
  FRows[mRow].Cells[mColumn] := TAtlasParallelCell.Create(mOk, mText);
end;

procedure TAtlasIdeDebugParallelWatch.Open(ARow: Integer);
begin
  if (ARow < 0) or (ARow > High(FRows)) then
  begin
    Exit;
  end;
  TAtlasIdeDebugThreads.Select(FRows[ARow].ThreadId);
  if (FRows[ARow].FileName <> '') and (FRows[ARow].Line > 0) then
  begin
    TAtlasIdeNavigation.MarkLine(FRows[ARow].FileName, FRows[ARow].Line - 1);
  end;
end;

procedure TAtlasIdeDebugParallelWatch.Add(const AExpression: string);
var
  mList: TArray<string>;
  mExpression: string;
begin
  mList := nil;
  // Schon da: nach rechts (jüngster).
  for mExpression in Expressions do
  begin
    if mExpression <> AExpression then
    begin
      mList := mList + [mExpression];
    end;
  end;
  SetExpressions(mList + [AExpression]);
  Refresh;
end;

procedure TAtlasIdeDebugParallelWatch.Rename(AIndex: Integer; const AExpression: string);
var
  mList: TArray<string>;
begin
  mList := Expressions;
  if (AIndex < 0) or (AIndex > High(mList)) or (mList[AIndex] = AExpression) then
  begin
    Exit;
  end;
  mList[AIndex] := AExpression;
  SetExpressions(mList);
  Refresh;
end;

procedure TAtlasIdeDebugParallelWatch.Remove(AIndex: Integer);
var
  mList: TArray<string>;
begin
  mList := Expressions;
  if (AIndex < 0) or (AIndex > High(mList)) then
  begin
    Exit;
  end;
  FStore.Remove(TAtlasIdeEvaluateStore.CurrentProject, mList[AIndex]);
  Save;
  // Die übrigen Werte bleiben; eine laufende Auswertung beginnt neu.
  FTimer.Enabled := False;
  TAtlasParallelWatch.DeleteColumn(FRows, AIndex);
  if FStep = TStep.Evaluate then
  begin
    StartValues;
  end
  else
  begin
    Show('');
  end;
end;

procedure TAtlasIdeDebugParallelWatch.WireFrame(AFrame: TAtlasDebugParallelWatchFrame);
var
  mEvents: TAtlasParallelWatchEvents;
begin
  mEvents := Default(TAtlasParallelWatchEvents);
  mEvents.OnAdd :=
    procedure(AExpression: string)
    begin
      Add(AExpression);
    end;
  mEvents.OnRename :=
    procedure(AIndex: Integer; const AExpression: string)
    begin
      Rename(AIndex, AExpression);
    end;
  mEvents.OnRemove :=
    procedure(AIndex: Integer; const AExpression: string)
    begin
      Remove(AIndex);
    end;
  mEvents.OnOpen :=
    procedure(ARow: Integer)
    begin
      Open(ARow);
    end;
  mEvents.OnEvaluate :=
    procedure
    begin
      FAsked := True;
      if FStacks <> nil then
      begin
        StartValues;
      end;
    end;
  AFrame.Events := mEvents;
end;


class procedure TAtlasIdeDebugParallelWatch.Start;
begin
  if FInstance <> nil then
  begin
    Exit;
  end;
  FInstance := TAtlasIdeDebugParallelWatch.Create;
  FInstance.FPanel.OnFrame :=
    procedure(AFrame: TCustomFrame)
    begin
      if (FInstance <> nil) and (AFrame is TAtlasDebugParallelWatchFrame) then
      begin
        FInstance.WireFrame(TAtlasDebugParallelWatchFrame(AFrame));
      end;
    end;
  // Früh anmelden, damit der Desktop das Fenster speichert und wiederherstellt (#879).
  FInstance.FPanel.Prepare;
  FInstance.Listen;
  TAtlasIdeDebugSession.Start;
end;

class procedure TAtlasIdeDebugParallelWatch.Release;
begin
  FreeAndNil(FInstance);
end;

class function TAtlasIdeDebugParallelWatch.Started: Boolean;
begin
  Result := FInstance <> nil;
end;

class function TAtlasIdeDebugParallelWatch.Enabled: Boolean;
begin
  Result := TAtlasIdeSettings.Current.Enabled and TAtlasIdeSettings.Current.DebugParallelWatch;
end;

class procedure TAtlasIdeDebugParallelWatch.ShowWindow;
begin
  if FInstance = nil then
  begin
    Exit;
  end;
  FInstance.FPanel.Show;
  FInstance.Refresh;
end;

class procedure TAtlasIdeDebugParallelWatch.ThemeChanged;
begin
  if Started then
  begin
    FInstance.FPanel.ApplyTheme;
  end;
end;

end.
