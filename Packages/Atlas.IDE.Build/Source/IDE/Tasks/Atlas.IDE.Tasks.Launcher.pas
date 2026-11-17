unit Atlas.IDE.Tasks.Launcher;

// IAtlasTaskLauncher der IDE: ein Thread je Lauf. Er setzt die Variablen des
// Projekts ein, liest die Ausgabe Zeile für Zeile, erkennt Fundstellen und
// gibt beides gesammelt (alle 100 ms) an die Ausgabeansicht; das Ende geht
// über TAtlasMainThread an den Rückruf. Beim Freigeben werden alle Läufe
// abgebrochen und ihre Threads abgewartet.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Matchers,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.RunFlow,
  Atlas.IDE.Tasks.Output;

type
  /// <summary>Lauf AId ist mit ARun zu Ende (im Hauptthread).</summary>
  TAtlasTaskRunEnded = reference to procedure(AId: Integer; const ARun: TAtlasTaskRun);

  TAtlasIdeTaskLauncher = class(TInterfacedObject, IAtlasTaskLauncher)
  private type
    /// <summary>Abbruch eines Laufs; der Thread fragt Cancelled im Takt.</summary>
    TFlag = class(TInterfacedObject)
    public
      Cancelled: Boolean;
    end;

    /// <summary>Was ein Lauf an die Hauptseite gibt: Ausgabe, Ende, und ob der Empfänger noch lebt.</summary>
    TSink = record
      Output: TAtlasIdeTaskOutput;
      OnEnded: TAtlasTaskRunEnded;
      Alive: TFunc<Boolean>;
    end;

    TWorker = class(TThread)
    private
      FSink: TSink;
      FFlag: TFlag;
      FFlagRef: IInterface;
      FId: Integer;
      FTask: TAtlasTaskDefinition;
      FProcess: TAtlasTaskProcessRun;
      FProjectFiles: TArray<string>;
      FSearchPath: TArray<string>;
      FPendingLines: TArray<string>;
      FPendingFindings: TAtlasTaskFindings;
      // Stand des Laufs im Thread.
      FRun: TAtlasTaskRun;
      FLineCount: Integer;
      FLastFlush: UInt64;
      FExists: TAtlasTaskFileExists;
      procedure Deliver;
      procedure Finish(const ARun: TAtlasTaskRun);
      /// <summary>Zeile der Ausgabe: Fundstelle erkennen, merken und gesammelt weitergeben.</summary>
      procedure TakeLine(AMatcher: TAtlasTaskLineMatcher; const ALine: string);
      function RunProcess: TAtlasTaskProcessResult;
    protected
      procedure Execute; override;
    public
      constructor Create(const ASink: TSink; const AProcess: TAtlasTaskProcessRun; AId: Integer;
        const ATask: TAtlasTaskDefinition; const AProjectFiles, ASearchPath: TArray<string>);
      destructor Destroy; override;
      procedure Cancel;
    end;
  private
    FProcess: TAtlasTaskProcessRun;
    FSink: TSink;
    FWorkers: TObjectDictionary<Integer, TWorker>;
  public
    /// <summary>AProcess startet den Prozess; AOutput zeigt die Ausgabe (gehört dem Aufrufer und lebt länger);
    /// AOnEnded bekommt das Ende, solange AAlive True liefert.</summary>
    constructor Create(const AProcess: TAtlasTaskProcessRun; AOutput: TAtlasIdeTaskOutput;
      const AOnEnded: TAtlasTaskRunEnded; const AAlive: TFunc<Boolean>);
    /// <summary>Bricht alle Läufe ab und wartet auf ihre Threads.</summary>
    destructor Destroy; override;
    /// <summary>Braucht ATask einen Kommandozeilen-Compiler, den diese Edition nicht hat (#1822)? AReason nennt den
    /// Grund. Aufgaben, die dcc über ein Skript starten, erkennt das nicht.</summary>
    class function NeedsMissingCompiler(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean; static;
    { IAtlasTaskLauncher }
    function Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
    procedure Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition; AShow: Boolean);
    procedure Cancel(AId: Integer);
    procedure Release(AId: Integer);
  end;

implementation

uses
  Atlas.Core.Diagnostics.Edition,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.UI.Build.Strings,
  Atlas.IDE.Diagnostics.Edition,
  Atlas.IDE.Tasks.Projects;

const
  cFlushMs = 100;

{ TAtlasIdeTaskLauncher.TWorker }

constructor TAtlasIdeTaskLauncher.TWorker.Create(const ASink: TSink; const AProcess: TAtlasTaskProcessRun;
  AId: Integer; const ATask: TAtlasTaskDefinition; const AProjectFiles, ASearchPath: TArray<string>);
begin
  inherited Create(True);
  FreeOnTerminate := False;
  FSink := ASink;
  FFlag := TFlag.Create;
  FFlagRef := FFlag;
  FId := AId;
  FTask := ATask;
  FProcess := AProcess;
  FProjectFiles := AProjectFiles;
  FSearchPath := ASearchPath;
end;

destructor TAtlasIdeTaskLauncher.TWorker.Destroy;
begin
  FFlagRef := nil;
  FSink := Default(TSink);
  FProcess := nil;
  FExists := nil;
  inherited Destroy;
end;

procedure TAtlasIdeTaskLauncher.TWorker.Execute;
var
  mOutcome: TAtlasTaskProcessResult;
  mStarted: UInt64;
begin
  FRun := Default(TAtlasTaskRun);
  FRun.Name := FTask.Name;
  FRun.CommandLine := FTask.CommandLine;
  FRun.Cwd := FTask.Cwd;
  mStarted := TThread.GetTickCount64;
  FLastFlush := mStarted;
  FExists := TAtlasTaskPaths.OnDisk();
  FLineCount := 0;
  try
    mOutcome := RunProcess;
    Deliver;
    FRun.Outcome := mOutcome.Outcome;
    FRun.ExitCode := mOutcome.ExitCode;
    FRun.Error := mOutcome.Error;
  except
    on E: Exception do
    begin
      FRun.Outcome := TAtlasTaskOutcome.StartFailed;
      FRun.ExitCode := -1;
      FRun.Error := E.Message;
    end;
  end;
  FRun.DurationMs := Int64(TThread.GetTickCount64 - mStarted);
  FRun.FinishedAt := Now;
  Finish(FRun);
end;

procedure TAtlasIdeTaskLauncher.TWorker.Deliver;
var
  mLines: TArray<string>;
  mFindings: TAtlasTaskFindings;
  mSink: TSink;
  mId: Integer;
begin
  if (Length(FPendingLines) = 0) and (Length(FPendingFindings) = 0) then
  begin
    Exit;
  end;
  mLines := FPendingLines;
  mFindings := FPendingFindings;
  FPendingLines := nil;
  FPendingFindings := nil;
  mSink := FSink;
  mId := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if mSink.Alive() then
      begin
        mSink.Output.Lines(mId, mLines, mFindings);
      end;
    end);
end;

procedure TAtlasIdeTaskLauncher.TWorker.Finish(const ARun: TAtlasTaskRun);
var
  mRun: TAtlasTaskRun;
  mSink: TSink;
  mId: Integer;
begin
  mRun := ARun;
  mSink := FSink;
  mId := FId;
  TAtlasMainThread.Queue(TAtlasFeature.Tasks,
    procedure
    begin
      if mSink.Alive() then
      begin
        mSink.OnEnded(mId, mRun);
      end;
    end);
end;

procedure TAtlasIdeTaskLauncher.TWorker.TakeLine(AMatcher: TAtlasTaskLineMatcher; const ALine: string);
var
  mFinding: TAtlasTaskFinding;
begin
  if AMatcher.Match(ALine, mFinding) then
  begin
    mFinding.OutputLine := FLineCount;
    if mFinding.FileName <> '' then
    begin
      mFinding.FileName := TAtlasTaskPaths.Resolve(mFinding.FileName, FTask.Cwd, FProjectFiles, FSearchPath,
        FExists);
    end;
    FRun.Findings := FRun.Findings + [mFinding];
    FPendingFindings := FPendingFindings + [mFinding];
  end;
  // Die Anzeige kappt selbst; gemerkt werden höchstens so viele Zeilen wie dort.
  if FLineCount < TAtlasIdeTaskOutput.cMaxLines then
  begin
    FRun.Lines := FRun.Lines + [ALine];
  end;
  Inc(FLineCount);
  FPendingLines := FPendingLines + [ALine];
  if TThread.GetTickCount64 - FLastFlush >= cFlushMs then
  begin
    Deliver;
    FLastFlush := TThread.GetTickCount64;
  end;
end;

function TAtlasIdeTaskLauncher.TWorker.RunProcess: TAtlasTaskProcessResult;
var
  mMatcher: TAtlasTaskLineMatcher;
  mFlag: TFlag;
begin
  mFlag := FFlag;
  mMatcher := TAtlasTaskLineMatcher.Create(FTask.Matcher);
  try
    Result := FProcess(FTask, 0,
      function: Boolean
      begin
        Result := mFlag.Cancelled or TAtlasShutdown.Signalled;
      end,
      procedure(const ALine: string)
      begin
        TakeLine(mMatcher, ALine);
      end);
    // Ungültiges eigenes Muster: Die Ausgabe läuft ohne Befunde, der Grund steht darunter.
    if mMatcher.Error <> '' then
    begin
      FPendingLines := FPendingLines + [mMatcher.Error];
    end;
  finally
    mMatcher.Free;
  end;
end;

procedure TAtlasIdeTaskLauncher.TWorker.Cancel;
begin
  FFlag.Cancelled := True;
  Terminate;
end;

{ TAtlasIdeTaskLauncher }

constructor TAtlasIdeTaskLauncher.Create(const AProcess: TAtlasTaskProcessRun; AOutput: TAtlasIdeTaskOutput;
  const AOnEnded: TAtlasTaskRunEnded; const AAlive: TFunc<Boolean>);
begin
  inherited Create;
  FProcess := AProcess;
  FSink.Output := AOutput;
  FSink.OnEnded := AOnEnded;
  FSink.Alive := AAlive;
  FWorkers := TObjectDictionary<Integer, TWorker>.Create([doOwnsValues]);
end;

destructor TAtlasIdeTaskLauncher.Destroy;
var
  mWorker: TWorker;
begin
  if FWorkers <> nil then
  begin
    for mWorker in FWorkers.Values do
    begin
      mWorker.Cancel;
    end;
    for mWorker in FWorkers.Values do
    begin
      mWorker.WaitFor;
    end;
  end;
  FreeAndNil(FWorkers);
  FSink := Default(TSink);
  FProcess := nil;
  inherited Destroy;
end;

class function TAtlasIdeTaskLauncher.NeedsMissingCompiler(const ATask: TAtlasTaskDefinition;
  out AReason: string): Boolean;
begin
  AReason := '';
  Result := TAtlasEdition.NeedsCommandLine(ATask.Command) and TAtlasIdeEdition.CommandLineMissing;
  if Result then
  begin
    AReason := TAtlasBuildStrings.Fmt(TAtlasBuildTextId.TasksNeedsCommandLine,
      [ATask.Name, ExtractFileName(ATask.Command)]);
  end;
end;

function TAtlasIdeTaskLauncher.Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
begin
  Result := NeedsMissingCompiler(ATask, AReason);
end;

procedure TAtlasIdeTaskLauncher.Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition;
  AShow: Boolean);
var
  mTask: TAtlasTaskDefinition;
  mProjectFiles, mSearchPath: TArray<string>;
  mWorker: TWorker;
begin
  mTask := TAtlasTasks.Expand(ATask, TAtlasIdeTaskProjects.VariablesOf(AProject));
  mProjectFiles := TAtlasIdeTaskProjects.ProjectFilesOf(AProject, mSearchPath);
  FSink.Output.Started(AId, mTask.Name, mTask.CommandLine, mTask.TimeoutSec, AShow);
  mWorker := TWorker.Create(FSink, FProcess, AId, mTask, mProjectFiles, mSearchPath);
  FWorkers.Add(AId, mWorker);
  mWorker.Start;
end;

procedure TAtlasIdeTaskLauncher.Cancel(AId: Integer);
var
  mWorker: TWorker;
begin
  if FWorkers.TryGetValue(AId, mWorker) then
  begin
    mWorker.Cancel;
  end;
end;

procedure TAtlasIdeTaskLauncher.Release(AId: Integer);
var
  mWorker: TWorker;
begin
  // Der Thread hat nach seinem Ende-Eintrag nichts mehr zu tun.
  if FWorkers.TryGetValue(AId, mWorker) then
  begin
    mWorker.WaitFor;
    FWorkers.Remove(AId);
  end;
end;

end.
