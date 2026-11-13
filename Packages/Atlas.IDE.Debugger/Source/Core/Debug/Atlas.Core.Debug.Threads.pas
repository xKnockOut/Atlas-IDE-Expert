unit Atlas.Core.Debug.Threads;

// Aufrufstapel aller Threads eines angehaltenen Programms (#587, #837), ohne VCL und Open Tools API:
//   - TAtlasDebugThreadStack: Kennung, Name, Rahmen (oberster zuerst, eigener Code markiert).
//   - TAtlasDebugWaits: Wartepunkt eines Threads. Atlas sucht im Stapel oberhalb des ersten eigenen Rahmens die
//     tiefste bekannte Warte-Routine: Im Stapel „NtWaitForSingleObject ← WaitForSingleObjectEx ← TThread.WaitFor ←
//     TForm1.FormDestroy“ ist das TThread.WaitFor, nicht der Kernaufruf darüber. Ohne eigenen Rahmen zählt der ganze
//     Stapel. Routinen vergleicht Atlas mit dem Ende des Namens an einer Punktgrenze („TMonitor.Enter“ passt auf
//     „System.TMonitor.Enter“), ohne Groß-/Kleinschreibung.
//   - Hauptthread: der Thread, dessen Stapel in der Projektdatei (.dpr) beginnt; sonst der erste der Liste.
// Was sich nicht lesen lässt: welcher Thread eine Sperre (TMonitor, Critical Section) hält. Die IDE nennt nur Rahmen;
// den Besitzer müsste Atlas aus dem Speicher des Programms auswerten.

interface

uses
  Atlas.Core.Debug.CallStack;

type
  /// <summary>Woran ein Thread wartet.</summary>
  {$SCOPEDENUMS ON}
  TAtlasDebugWaitKind = (None, Idle, ThreadWaitFor, Synchronize, MonitorEnter, MonitorWait, CriticalSection,
    EventWait, Sleep, Handle);
  {$SCOPEDENUMS OFF}

  TAtlasDebugThreadStack = record
    ThreadId: Cardinal;
    /// <summary>Name aus TThread.NameThreadForDebugging; '' ohne.</summary>
    Name: string;
    /// <summary>False, wenn die IDE den Stapel nicht liefern konnte.</summary>
    Readable: Boolean;
    Frames: TAtlasDebugFrames;
    class function Create(AThreadId: Cardinal; const AName: string;
      const AFrames: TAtlasDebugFrames): TAtlasDebugThreadStack; static;
    /// <summary>Index des obersten eigenen Rahmens mit Quelltext; -1 ohne.</summary>
    function FirstOwn: Integer;
    /// <summary>Rahmen zum Springen: der oberste eigene, sonst der oberste mit Quelltext; -1 ohne.</summary>
    function JumpFrame: Integer;
  end;

  TAtlasDebugThreadStacks = TArray<TAtlasDebugThreadStack>;

  /// <summary>Wartepunkt eines Threads.</summary>
  TAtlasDebugWait = record
    Kind: TAtlasDebugWaitKind;
    /// <summary>Index des Rahmens der Warte-Routine; -1 ohne.</summary>
    Frame: Integer;
    /// <summary>Routine des Wartepunkts („System.Classes.TThread.WaitFor“).</summary>
    Routine: string;
    /// <summary>Wartet der Thread (nicht leer laufend in der Nachrichtenschleife)?</summary>
    function Blocked: Boolean;
  end;

  TAtlasDebugWaits = record
  public
    /// <summary>Vorgabe der Warte-Routinen, je „Art=Routine“ (Art: Name aus TAtlasDebugWaitKind).</summary>
    class function DefaultRoutines: TArray<string>; static;
    /// <summary>Art der Warte-Routine ARoutine; None, wenn sie keine ist.</summary>
    class function KindOf(const ARoutine: string): TAtlasDebugWaitKind; static;
    /// <summary>Wartepunkt von AStack (siehe Kopf).</summary>
    class function Find(const AStack: TAtlasDebugThreadStack): TAtlasDebugWait; static;
    /// <summary>Endet ARoutine an einer Punktgrenze mit APattern?</summary>
    class function Matches(const ARoutine, APattern: string): Boolean; static;
    /// <summary>Index des Hauptthreads in AStacks (siehe Kopf); -1 bei leerer Liste.</summary>
    class function MainIndex(const AStacks: TAtlasDebugThreadStacks): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo;

const
  cRoutines: array[0..27] of string = (
    'Idle=GetMessage', 'Idle=GetMessageW', 'Idle=NtUserGetMessage', 'Idle=WaitMessage', 'Idle=NtUserWaitMessage',
    'ThreadWaitFor=TThread.WaitFor',
    'Synchronize=TThread.Synchronize',
    'MonitorEnter=TMonitor.Enter', 'MonitorWait=TMonitor.Wait',
    'CriticalSection=TCriticalSection.Enter', 'CriticalSection=TCriticalSection.Acquire',
    'CriticalSection=EnterCriticalSection', 'CriticalSection=RtlEnterCriticalSection',
    'EventWait=TEvent.WaitFor', 'EventWait=THandleObject.WaitFor', 'EventWait=TLightweightEvent.WaitFor',
    'Sleep=Sleep', 'Sleep=SleepEx', 'Sleep=NtDelayExecution',
    'Handle=WaitForSingleObject', 'Handle=WaitForSingleObjectEx', 'Handle=NtWaitForSingleObject',
    'Handle=ZwWaitForSingleObject', 'Handle=WaitForMultipleObjects', 'Handle=WaitForMultipleObjectsEx',
    'Handle=NtWaitForMultipleObjects', 'Handle=MsgWaitForMultipleObjects', 'Handle=MsgWaitForMultipleObjectsEx');

{ TAtlasDebugThreadStack }

class function TAtlasDebugThreadStack.Create(AThreadId: Cardinal; const AName: string;
  const AFrames: TAtlasDebugFrames): TAtlasDebugThreadStack;
begin
  Result.ThreadId := AThreadId;
  Result.Name := AName;
  Result.Readable := True;
  Result.Frames := AFrames;
end;

function TAtlasDebugThreadStack.FirstOwn: Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Frames) do
  begin
    if Frames[mIndex].Own and Frames[mIndex].HasSource then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasDebugThreadStack.JumpFrame: Integer;
begin
  Result := FirstOwn;
  if Result < 0 then
  begin
    Result := TAtlasDebugCallStack.FirstWithSource(Frames);
  end;
end;

{ TAtlasDebugWait }

function TAtlasDebugWait.Blocked: Boolean;
begin
  Result := (Kind <> TAtlasDebugWaitKind.None) and (Kind <> TAtlasDebugWaitKind.Idle);
end;

{ TAtlasDebugWaits }

class function TAtlasDebugWaits.DefaultRoutines: TArray<string>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(cRoutines));
  for mIndex := 0 to High(cRoutines) do
  begin
    Result[mIndex] := cRoutines[mIndex];
  end;
end;

class function TAtlasDebugWaits.Matches(const ARoutine, APattern: string): Boolean;
var
  mStart: Integer;
begin
  if (APattern = '') or (Length(ARoutine) < Length(APattern)) then
  begin
    Exit(False);
  end;
  mStart := Length(ARoutine) - Length(APattern) + 1;
  Result := SameText(Copy(ARoutine, mStart, Length(APattern)), APattern) and
    ((mStart = 1) or (ARoutine[mStart - 1] = '.'));
end;

class function TAtlasDebugWaits.KindOf(const ARoutine: string): TAtlasDebugWaitKind;
var
  mEntry: string;
  mSplit: Integer;
begin
  for mEntry in cRoutines do
  begin
    mSplit := Pos('=', mEntry);
    if Matches(ARoutine, Copy(mEntry, mSplit + 1, MaxInt)) then
    begin
      Exit(TAtlasDebugWaitKind(GetEnumValue(TypeInfo(TAtlasDebugWaitKind), Copy(mEntry, 1, mSplit - 1))));
    end;
  end;
  Result := TAtlasDebugWaitKind.None;
end;

class function TAtlasDebugWaits.Find(const AStack: TAtlasDebugThreadStack): TAtlasDebugWait;
var
  mIndex, mLast: Integer;
  mKind: TAtlasDebugWaitKind;
begin
  Result := Default(TAtlasDebugWait);
  Result.Frame := -1;
  mLast := AStack.FirstOwn;
  if mLast < 0 then
  begin
    mLast := Length(AStack.Frames);
  end;
  for mIndex := 0 to mLast - 1 do
  begin
    mKind := KindOf(AStack.Frames[mIndex].Routine);
    if mKind <> TAtlasDebugWaitKind.None then
    begin
      Result.Kind := mKind;
      Result.Frame := mIndex;
      Result.Routine := AStack.Frames[mIndex].Routine;
    end;
  end;
end;

class function TAtlasDebugWaits.MainIndex(const AStacks: TAtlasDebugThreadStacks): Integer;
var
  mIndex: Integer;
  mFrame: TAtlasDebugFrame;
begin
  for mIndex := 0 to High(AStacks) do
  begin
    for mFrame in AStacks[mIndex].Frames do
    begin
      if SameText(ExtractFileExt(mFrame.FileName), '.dpr') then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  Result := High(AStacks);
  if Result > 0 then
  begin
    Result := 0;
  end;
end;

end.
