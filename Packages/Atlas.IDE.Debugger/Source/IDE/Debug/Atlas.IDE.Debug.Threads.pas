unit Atlas.IDE.Debug.Threads;

// Threads eines angehaltenen Programms lesen (#587, #837): Aufrufstapel je Thread über IOTAProcess.Threads und
// IOTAThread (wie im Fenster Aufrufstack), eigener Code markiert (#578), Name aus TThread.NameThreadForDebugging.
// Den aktuellen Thread wechseln für den Sprung zu einer Zeile. Nur im Hauptthread verwenden.

interface

uses
  ToolsAPI,
  Atlas.Core.Debug.Threads;

type
  TAtlasIdeDebugThreads = class
  public
    /// <summary>Höchstens ACount Threads ab AFrom an AStacks anhängen. Result: Liefert der Debugger einen der Stapel
    /// erst später (Win64, LLDB)? Solche Threads stehen als nicht lesbar in der Liste.</summary>
    class function ReadRange(const AProcess: IOTAProcess; AFrom, ACount: Integer;
      var AStacks: TAtlasDebugThreadStacks): Boolean; static;
    /// <summary>Index des aktuellen Threads in AStacks; -1 ohne.</summary>
    class function CurrentIndex(const AProcess: IOTAProcess; const AStacks: TAtlasDebugThreadStacks): Integer;
      static;
    /// <summary>Thread mit der Kennung AThreadId zum aktuellen Thread machen, solange das Programm steht.</summary>
    class procedure Select(AThreadId: Cardinal); static;
  end;

implementation

uses
  Atlas.Core.Debug.CallStack,
  Atlas.IDE.Debug.Session,
  Atlas.IDE.Debug.Sources;

{ TAtlasIdeDebugThreads }

class function TAtlasIdeDebugThreads.ReadRange(const AProcess: IOTAProcess; AFrom, ACount: Integer;
  var AStacks: TAtlasDebugThreadStacks): Boolean;
var
  mThread: IOTAThread;
  mIndex, mLast: Integer;
  mFrames: TAtlasDebugFrames;
  mStack: TAtlasDebugThreadStack;
begin
  Result := False;
  mLast := AFrom + ACount - 1;
  if mLast > AProcess.ThreadCount - 1 then
  begin
    mLast := AProcess.ThreadCount - 1;
  end;
  for mIndex := AFrom to mLast do
  begin
    mThread := AProcess.Threads[mIndex];
    case TAtlasIdeDebugSession.ReadStack(mThread, TAtlasDebugCallStack.cMaxFrames, mFrames) of
      TAtlasDebugStackRead.Ready:
        TAtlasIdeDebugSources.MarkFrames(mFrames);
      TAtlasDebugStackRead.Wait:
        Result := True;
    end;
    mStack := TAtlasDebugThreadStack.Create(mThread.GetOSThreadID, TAtlasIdeDebugSession.ThreadName(mThread),
      mFrames);
    mStack.Readable := mFrames <> nil;
    AStacks := AStacks + [mStack];
  end;
end;

class function TAtlasIdeDebugThreads.CurrentIndex(const AProcess: IOTAProcess;
  const AStacks: TAtlasDebugThreadStacks): Integer;
var
  mCurrent: IOTAThread;
  mIndex: Integer;
begin
  Result := -1;
  mCurrent := AProcess.CurrentThread;
  if mCurrent = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AStacks) do
  begin
    if AStacks[mIndex].ThreadId = mCurrent.GetOSThreadID then
    begin
      Exit(mIndex);
    end;
  end;
end;

class procedure TAtlasIdeDebugThreads.Select(AThreadId: Cardinal);
var
  mProcess: IOTAProcess;
  mIndex: Integer;
begin
  mProcess := TAtlasIdeDebugSession.Process;
  if (mProcess = nil) or (TAtlasIdeDebugSession.StoppedThread = nil) then
  begin
    Exit;
  end;
  for mIndex := 0 to mProcess.ThreadCount - 1 do
  begin
    if mProcess.Threads[mIndex].GetOSThreadID = AThreadId then
    begin
      mProcess.CurrentThread := mProcess.Threads[mIndex];
      Exit;
    end;
  end;
end;

end.
