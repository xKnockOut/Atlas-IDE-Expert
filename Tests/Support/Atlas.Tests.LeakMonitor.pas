unit Atlas.Tests.LeakMonitor;

// Speicherleck-Überwachung für DUnitX. Misst über GetMemoryManagerState des
// eingebauten Speichermanagers (FastMM-basiert), wie viele Bytes Setup, Test
// und TearDown netto belegt haben. DUnitX wertet einen Test mit Rest als
// Speicherleck; Tests mit gewollten Caches tragen [IgnoreMemoryLeaks].
//
// Die Messung ist prozessweit und sieht deshalb auch andere Threads. Damit
// sie nur Lecks des Tests meldet:
// - Vorwärmen (RegisterLeakMonitor): Die RTL hält Warteobjekte von TMonitor
//   (Wait, TLightweightEvent, Thread-Pool) in einem Zwischenspeicher, dessen
//   Verwaltungsknoten bis Programmende bleiben. Er wächst, sobald erstmals
//   mehr Threads gleichzeitig warten als je zuvor, und zwar in dem Thread, der
//   gerade fertig wird – oft ein Thread-Pool- oder Überwachungs-Thread
//   früherer Tests mitten in einem fremden Test (24 Byte je Knoten unter
//   Win64). Ebenso legt der erste TTask den Standard-Thread-Pool an.
// - Nachwarten: Bleibt nach Test oder TearDown ein Rest, wartet der Monitor
//   kurz, bis Threads des Tests ihre letzten Freigaben erledigt haben (z. B.
//   der Lese-Thread einer JSON-RPC-Verbindung nach ReaderDone oder ein
//   Task nach dem Signal).
// - Ein negativer Saldo (andere Threads geben älteren Speicher frei) ist nie
//   ein Leck des Tests und wird als 0 gemeldet.
// Bleibt ein Leck, hängt der Bericht Thread-Anzahl und Wartezeit an.

interface

uses
  DUnitX.TestFramework;

type
  TLeakMonitor = class(TInterfacedObject, IMemoryLeakMonitor, IMemoryLeakMonitor2)
  private
    FSetUpBefore: Int64;
    FSetUpAllocated: Int64;
    FTestBefore: Int64;
    FTestAllocated: Int64;
    FTearDownBefore: Int64;
    FTearDownAllocated: Int64;
    FStarted: Boolean;
    FThreadsAtStart: Integer;
    FThreadsAtEnd: Integer;
    FWaitedMs: UInt64;
    procedure Start;
    function RawTotal: Int64;
    function Reported(AValue: Int64): Int64;
    procedure Settle(ABefore: Int64; var AAllocated: Int64; AOthers: Int64);
  public
    procedure PreSetup;
    procedure PostSetUp;
    procedure PreTest;
    procedure PostTest;
    procedure PreTearDown;
    procedure PostTearDown;
    function SetUpMemoryAllocated: Int64;
    function TearDownMemoryAllocated: Int64;
    function TestMemoryAllocated: Int64;
    function GetReport: string;
  end;

/// <summary>Aktuell belegte Bytes laut Speichermanager.</summary>
function AllocatedBytes: Int64;

/// <summary>Anzahl der Threads dieses Prozesses (Toolhelp; belegt keinen Delphi-Speicher).</summary>
function ProcessThreadCount: Integer;

/// <summary>Löst Einmal-Belegungen der RTL aus, die sonst in fremden Tests auffallen.</summary>
procedure PrewarmRuntime;

/// <summary>Wärmt die RTL vor und meldet TLeakMonitor als Überwachung bei DUnitX an.</summary>
procedure RegisterLeakMonitor;

implementation

// Delphi 13 liefert DUnitX mit DUnitX.ServiceLocator (TDUnitXServiceLocator)
// statt des früheren DUnitX.IoC (TDUnitXIoC); die Schnittstelle ist gleich.
uses
  Winapi.Windows,
  Winapi.MMSystem,
  Winapi.TlHelp32,
  System.SysUtils,
  System.Classes,
  System.Threading,
  System.DateUtils,
  System.JSON,
  DUnitX.ServiceLocator,
  Atlas.Common.Editing.SlashCommands,
  Atlas.Core.Diagnostics.TimeLimit;

const
  /// <summary>Höchstens so lange wartet der Monitor auf Freigaben anderer Threads.</summary>
  SettleTimeoutMs: UInt64 = 250;
  SettleStepMs = 2;
  /// <summary>So viele gleiche Messungen hintereinander gelten als ruhig.</summary>
  StableSamples = 3;
  /// <summary>Mindestzahl gleichzeitig wartender Threads beim Vorwärmen.</summary>
  MinPrewarmWaiters = 64;

function AllocatedBytes: Int64;
var
  State: TMemoryManagerState;
  I: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(State);
  {$WARN SYMBOL_PLATFORM DEFAULT}
  Result := Int64(State.TotalAllocatedMediumBlockSize) + Int64(State.TotalAllocatedLargeBlockSize);
  for I := Low(State.SmallBlockTypeStates) to High(State.SmallBlockTypeStates) do
    Inc(Result, Int64(State.SmallBlockTypeStates[I].AllocatedBlockCount) *
      State.SmallBlockTypeStates[I].UseableBlockSize);
end;

function ProcessThreadCount: Integer;
var
  Snapshot: THandle;
  Entry: TThreadEntry32;
  ProcessId: DWORD;
begin
  Result := 0;
  Snapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if Snapshot = INVALID_HANDLE_VALUE then
    Exit;
  try
    ProcessId := GetCurrentProcessId;
    FillChar(Entry, SizeOf(Entry), 0);
    Entry.dwSize := SizeOf(Entry);
    if Thread32First(Snapshot, Entry) then
      repeat
        if Entry.th32OwnerProcessID = ProcessId then
          Inc(Result);
        Entry.dwSize := SizeOf(Entry);
      until not Thread32Next(Snapshot, Entry);
  finally
    CloseHandle(Snapshot);
  end;
end;

type
  /// <summary>Lässt viele Threads gleichzeitig in TMonitor.Wait stehen.</summary>
  TWaitGate = class
  private
    FWaiting: Integer;
  public
    procedure Wait;
    function Waiting: Integer;
  end;

procedure TWaitGate.Wait;
begin
  TMonitor.Enter(Self);
  try
    Inc(FWaiting);
    TMonitor.Wait(Self, 10000);
  finally
    TMonitor.Exit(Self);
  end;
end;

function TWaitGate.Waiting: Integer;
begin
  TMonitor.Enter(Self);
  try
    Result := FWaiting;
  finally
    TMonitor.Exit(Self);
  end;
end;

function StartWaiter(AGate: TWaitGate): TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      AGate.Wait;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure PrewarmWaitObjects;
var
  Gate: TWaitGate;
  Waiters: TArray<TThread>;
  Index: Integer;
  Deadline: UInt64;
begin
  // Jeder Thread in TMonitor.Wait hält ein Warteobjekt der RTL; beim Freigeben
  // legt die RTL für jedes über den bisherigen Höchststand hinaus einen
  // Verwaltungsknoten an, der bis Programmende bleibt. Einmal viele Threads
  // gleichzeitig warten lassen, dann wächst der Zwischenspeicher in den Tests nicht mehr.
  Gate := TWaitGate.Create;
  try
    SetLength(Waiters, 4 * TThread.ProcessorCount);
    if Length(Waiters) < MinPrewarmWaiters then
      SetLength(Waiters, MinPrewarmWaiters);
    for Index := 0 to High(Waiters) do
      Waiters[Index] := StartWaiter(Gate);
    // Inc steht unter der Sperre vor Wait; wer gezählt ist, wartet also schon.
    Deadline := TThread.GetTickCount64 + 5000;
    while (Gate.Waiting < Length(Waiters)) and (TThread.GetTickCount64 < Deadline) do
      TThread.Sleep(1);
    TMonitor.Enter(Gate);
    try
      TMonitor.PulseAll(Gate);
    finally
      TMonitor.Exit(Gate);
    end;
    for Index := 0 to High(Waiters) do
    begin
      Waiters[Index].WaitFor;
      Waiters[Index].Free;
    end;
  finally
    Gate.Free;
  end;
end;

procedure PrewarmRuntime;
var
  Task: ITask;
  Current: TThread;
  Json: TJSONValue;
begin
  PrewarmWaitObjects;
  // Gemeinsame Befehlsliste: entsteht beim ersten Zugriff und bleibt; sonst trifft das je nach
  // Reihenfolge (paralleler Lauf) einen anderen Test als Leck.
  TSlashCommandRegistry.Shared;
  // Legt den Standard-Thread-Pool und seinen Überwachungs-Thread an (bleiben bis Programmende).
  Task := TTask.Run(
    procedure
    begin
    end);
  Task.Wait;
  // Hauptthread: TExternalThread für TThread.CurrentThread (bleibt bis Programmende).
  Current := TThread.CurrentThread;
  if Current = nil then
    raise EInvalidOperation.Create('Kein aktueller Thread');
  // Lokale Zeitzone (ISO-8601-Zeitstempel) und JSON-Pfade legen beim ersten Gebrauch Daten an,
  // die bis Programmende bleiben.
  if DateToISO8601(Now, False) = '' then
    raise EInvalidOperation.Create('Keine Zeitzone');
  Json := TJSONObject.ParseJSONValue('{"a":{"b":true}}');
  try
    if not Json.GetValue<Boolean>('a.b') then
      raise EInvalidOperation.Create('JSON-Pfad');
  finally
    Json.Free;
  end;
end;

procedure RegisterLeakMonitor;
begin
  // Sleep(2) beim Warten auf andere Threads schliefe sonst eine ganze Zeitscheibe (rund 16 ms)
  // und verdreifachte die Laufzeit der Tests.
  timeBeginPeriod(1);
  PrewarmRuntime;
  TDUnitXServiceLocator.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function: IMemoryLeakMonitor
    begin
      Result := TLeakMonitor.Create;
    end);
end;

{ TLeakMonitor }

procedure TLeakMonitor.Start;
begin
  if FStarted then
    Exit;
  FStarted := True;
  FThreadsAtStart := ProcessThreadCount;
  FThreadsAtEnd := FThreadsAtStart;
end;

function TLeakMonitor.RawTotal: Int64;
begin
  Result := FSetUpAllocated + FTestAllocated + FTearDownAllocated;
end;

function TLeakMonitor.Reported(AValue: Int64): Int64;
begin
  // Mehr freigegeben als belegt: Freigaben anderer Threads, kein Leck.
  if RawTotal <= 0 then
    Result := 0
  else
    Result := AValue;
end;

procedure TLeakMonitor.Settle(ABefore: Int64; var AAllocated: Int64; AOthers: Int64);
var
  Started: UInt64;
  Last: Int64;
  Stable: Integer;
begin
  // AOthers: Saldo der übrigen Abschnitte; gewartet wird, solange die Summe positiv ist.
  Started := TThread.GetTickCount64;
  Last := AAllocated;
  Stable := 0;
  while (AOthers + AAllocated > 0) and (TThread.GetTickCount64 - Started < SettleTimeoutMs) do
  begin
    TThread.Sleep(SettleStepMs);
    AAllocated := AllocatedBytes - ABefore;
    if AAllocated = Last then
      Inc(Stable)
    else
    begin
      Stable := 0;
      Last := AAllocated;
    end;
    // Ruhig und keine zusätzlichen Threads mehr: weiteres Warten bringt nichts.
    if (Stable >= StableSamples) and (ProcessThreadCount <= FThreadsAtStart) then
      Break;
  end;
  Inc(FWaitedMs, TThread.GetTickCount64 - Started);
  FThreadsAtEnd := ProcessThreadCount;
end;

procedure TLeakMonitor.PreSetup;
begin
  Start;
  FSetUpBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostSetUp;
begin
  FSetUpAllocated := AllocatedBytes - FSetUpBefore;
end;

procedure TLeakMonitor.PreTest;
begin
  Start;
  // Arbeiter früherer Tests vor der Messung beenden, damit ihre Freigabe in PostTest kein Leck verdeckt.
  TAtlasTimeLimit.StopAll(1000);
  FTestBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTest;
begin
  // Arbeiter des Zeitlimits (#493) bleiben für den nächsten Aufruf stehen; ihr Speicher gehört zu keinem
  // Test. Vor dem Messen beenden, der nächste Aufruf legt neue an.
  TAtlasTimeLimit.StopAll(1000);
  FTestAllocated := AllocatedBytes - FTestBefore;
  // Nur der Test selbst: Was das Setup belegt, gibt meist erst das TearDown frei.
  if FTestAllocated > 0 then
    Settle(FTestBefore, FTestAllocated, 0)
  else
    FThreadsAtEnd := ProcessThreadCount;
end;

procedure TLeakMonitor.PreTearDown;
begin
  FTearDownBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTearDown;
begin
  FTearDownAllocated := AllocatedBytes - FTearDownBefore;
  if RawTotal > 0 then
    Settle(FTearDownBefore, FTearDownAllocated, FSetUpAllocated + FTestAllocated);
end;

function TLeakMonitor.SetUpMemoryAllocated: Int64;
begin
  Result := Reported(FSetUpAllocated);
end;

function TLeakMonitor.TearDownMemoryAllocated: Int64;
begin
  Result := Reported(FTearDownAllocated);
end;

function TLeakMonitor.TestMemoryAllocated: Int64;
begin
  Result := Reported(FTestAllocated);
end;

function TLeakMonitor.GetReport: string;
begin
  Result := Format(' (Setup %d, Test %d, TearDown %d Byte; Threads am Anfang %d, am Ende %d; ' +
    '%d ms auf andere Threads gewartet)', [FSetUpAllocated, FTestAllocated, FTearDownAllocated,
    FThreadsAtStart, FThreadsAtEnd, FWaitedMs]);
end;

end.
