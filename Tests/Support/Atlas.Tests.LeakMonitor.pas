unit Atlas.Tests.LeakMonitor;

// Speicherleck-Überwachung für DUnitX. Misst über GetMemoryManagerState des
// eingebauten Speichermanagers (FastMM-basiert), wie viele Bytes Setup, Test
// und TearDown netto belegt haben. DUnitX wertet einen Test mit Rest als
// Speicherleck. Eine Leckmeldung ist ein Befund, kein Grund zum Wiederholen
//: Tests warten auf jeden Thread, den sie starten, und leeren
// Felder im TearDown; bekannte Einmal-Belegungen legt TFirstUse
// (Atlas.Tests.FirstUse) vor dem ersten Test an, jede mit ihrem Besitzer. Ob
// eine solche Belegung wirklich bis zum Programmende lebt und dort frei wird,
// entscheidet der Speicherrest beim Beenden (TShutdownLeaks.Expect in der
// .dpr): Ein Leck der ersten Benutzung lässt dort den Lauf scheitern, auch
// wenn ein Aufwärmen es aus der Messung je Test nimmt. [IgnoreMemoryLeaks] nur, wo ein Test sein Wachstum selbst misst oder
// Speicher absichtlich über das Testende hinaus lebt, und dann mit Grund.
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
//   Task nach dem Signal). Ruhig ist es erst, wenn kein seit Beginn der Messung
//   gestarteter Thread mehr läuft. Das zählen Haken der RTL (SystemThreadFuncProc in
//   BeginThread, SystemThreadEndProc in EndThread), nicht die Threads des Prozesses:
//   Ein frisch gestarteter Thread fehlte in der Liste des Betriebssystems (Toolhelp)
//   teils noch Dutzende Millisekunden, die Anzahl lag dann nicht über dem Anfang, und
//   das Warten endete, bevor er seine Freigaben erledigt hatte.
// - Lücke nach dem Setup: Die RTL belegt die Startdaten eines Threads (BeginThread, mit dem Zählhaken zwei
//   Blöcke zu 24 Byte unter Win64) im Aufrufer, frei gibt sie der neue Thread beim Anlaufen. Fällt das zwischen
//   PostSetUp und PreTest, zählt PreTest die Freigabe zum Setup; Belegungen in der Lücke gehören DUnitX und
//   zählen nicht.
// - Ein negativer Saldo (andere Threads geben älteren Speicher frei) ist nie
//   ein Leck des Tests und wird als 0 gemeldet.
// - Anonymes Protokoll (#1478): Das gemeinsame atlas.log (TAtlasGuard.RotatingLog) nummeriert jeden neuen Namen,
//   Pfad und Text und behält die Nummern bis Programmende (höchstens MaxLabels). Jeder Wert zählte so als Leck
//   des Tests, der ihn zuerst schreibt (z. B. FailingProviderTripsOnlyItself, GuardErrorLineHidesMessage).
//   PostTest und PostTearDown vergessen die Nummern vor ihrer Messung; jeder Test beginnt mit leerer Tabelle.
// - Fixtures ohne Setup oder TearDown: DUnitX ruft PreSetup/PostSetUp und PreTearDown/PostTearDown nur, wenn die
//   Fixture die Methode hat. Was für jeden Test gelten muss (Sprache, Aufzeichnung, Vergessen der Nummern,
//   Festhalten des Stapelberichts), steht deshalb auch in PreTest und PostTest.
// Bleibt ein Leck, hängt der Bericht Thread-Anzahl und Wartezeit an. Mit ATLAS_LEAK_TRACE=1 in der Umgebung
// zeichnet TAllocationTrace (Atlas.Tests.AllocationTrace) jede Belegung des Tests mit Stapel auf, und der
// Bericht nennt die Stellen, deren Speicher übrig blieb.
//
// Der Monitor ist der einzige Haken vor jedem Setup und setzt deshalb auch den gemeinsamen Ausgangszustand:
// Jeder Test beginnt mit deutschen Texten (TAtlasLocale, #1458). Die Sprache gilt prozessweit, und Tests, die
// Einstellungen anwenden (TShellSettings.SetLoose wählt ohne language Englisch), ließen sonst nachfolgende Tests
// je nach Reihenfolge englisch prüfen.

interface

uses
  DUnitX.TestFramework;

type
  TLeakMonitor = class(TInterfacedObject, IMemoryLeakMonitor, IMemoryLeakMonitor2)
  private
    FSetUpBefore: Int64;
    FSetUpAllocated: Int64;
    /// <summary>Stand am Ende des Setups; 0 = keins gemessen.</summary>
    FSetUpEnd: Int64;
    FTestBefore: Int64;
    FTestAllocated: Int64;
    FTearDownBefore: Int64;
    FTearDownAllocated: Int64;
    FStarted: Boolean;
    FThreadsAtStart: Integer;
    FThreadsAtEnd: Integer;
    /// <summary>Nummer des ersten Threads, den die RTL nach dem Start der Messung beginnt (StartedThreads).</summary>
    FFirstThread: Int64;
    FWaitedMs: UInt64;
    /// <summary>Stapelbericht, festgehalten am Ende des Tests (ATLAS_LEAK_TRACE=1). DUnitX fragt GetReport erst
    /// später ab, wenn die Aufzeichnung schon dem nächsten Test gehört.</summary>
    FTraceReport: string;
    procedure Start;
    procedure CaptureTrace;
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

/// <summary>Zählhaken für BeginThread und EndThread setzen (einmal, vor dem ersten Thread der Tests).</summary>
procedure InstallThreadCounting;

/// <summary>Anzahl der Threads, die BeginThread seit InstallThreadCounting begonnen hat.</summary>
function StartedThreads: Int64;

/// <summary>True, solange ein Thread mit Nummer ab AFirst (siehe StartedThreads) noch läuft.</summary>
function ThreadsRunningSince(AFirst: Int64): Boolean;

/// <summary>Löst Einmal-Belegungen der RTL aus, die sonst in fremden Tests auffallen.</summary>
procedure PrewarmRuntime;

/// <summary>Wärmt die RTL und die bekannten Einmal-Belegungen (TFirstUse) vor und meldet TLeakMonitor als
/// Überwachung bei DUnitX an.</summary>
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
  DUnitX.ServiceLocator,
  Atlas.Tests.AllocationTrace,
  Atlas.Tests.FirstUse,
  Atlas.Common.Localization.Texts,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.TimeLimit;

const
  /// <summary>Höchstens so lange wartet der Monitor auf Freigaben anderer Threads.</summary>
  cSettleTimeoutMs: UInt64 = 250;
  cSettleStepMs = 2;
  /// <summary>So viele gleiche Messungen hintereinander gelten als ruhig.</summary>
  cStableSamples = 3;
  /// <summary>Mindestzahl gleichzeitig wartender Threads beim Vorwärmen.</summary>
  cMinPrewarmWaiters = 64;
  /// <summary>So viele Stapel mit Atlas-Rahmen nennt der Bericht eines Lecks mit ATLAS_LEAK_TRACE=1; Stapel nur
  /// aus RTL, VCL und DUnitX zählt er nur.</summary>
  cTraceGroups = 20;

  /// <summary>So viele Threads hält die Tabelle laufender Threads; liegen mehr Starts seit Beginn der Messung
  /// zurück, gilt noch einer als laufend (dann endet das Warten mit der Zeitgrenze).</summary>
  cThreadSlots = 4096;

var
  /// <summary>Belegungen je Test mit Stapel aufzeichnen (ATLAS_LEAK_TRACE=1, TAllocationTrace).</summary>
  TraceLeaks: Boolean;
  /// <summary>Nummer des zuletzt über BeginThread begonnenen Threads.</summary>
  ThreadsBegun: Int64;
  /// <summary>1, solange der Thread mit dieser Nummer (modulo cThreadSlots) läuft. Feste Tabelle: Die Haken
  /// belegen dafür nichts.</summary>
  ThreadRunning: array[0..cThreadSlots - 1] of Integer;

threadvar
  /// <summary>Nummer des eigenen Threads; 0 bei Threads, die vor den Haken begannen.</summary>
  ThreadNumber: Int64;

type
  /// <summary>Startdaten, wie ThreadWrapper (System) sie liest: Funktion und Parameter; ThreadWrapper gibt den
  /// Block vor dem Aufruf frei.</summary>
  PRtlThreadStart = ^TRtlThreadStart;
  TRtlThreadStart = record
    Func: TThreadFunc;
    Parameter: Pointer;
  end;

  /// <summary>Eigentliche Funktion und Parameter samt Nummer; gibt CountedThreadFunc beim Anlaufen frei.</summary>
  PCountedStart = ^TCountedStart;
  TCountedStart = record
    Func: TThreadFunc;
    Parameter: Pointer;
    Number: Int64;
  end;

procedure MarkThreadEnded;
var
  mNumber: Int64;
begin
  mNumber := ThreadNumber;
  if mNumber > 0 then
  begin
    ThreadNumber := 0;
    AtomicExchange(ThreadRunning[Integer(mNumber mod cThreadSlots)], 0);
  end;
end;

function CountedThreadFunc(AParameter: Pointer): Integer;
var
  mStart: TCountedStart;
begin
  mStart := PCountedStart(AParameter)^;
  Dispose(PCountedStart(AParameter));
  ThreadNumber := mStart.Number;
  try
    Result := mStart.Func(mStart.Parameter);
  finally
    // Ohne EndThread (Funktion kehrt zurück, z. B. roher BeginThread): hier als beendet zählen.
    MarkThreadEnded;
  end;
end;

function CountingThreadFuncProc(AThreadFunc: TThreadFunc; AParameter: Pointer): Pointer;
var
  mInner: PCountedStart;
  mOuter: PRtlThreadStart;
begin
  // Im startenden Thread, noch vor CreateThread: Der neue Thread läuft ab hier, nicht erst, wenn er anläuft.
  New(mInner);
  mInner.Func := AThreadFunc;
  mInner.Parameter := AParameter;
  mInner.Number := AtomicIncrement(ThreadsBegun);
  AtomicExchange(ThreadRunning[Integer(mInner.Number mod cThreadSlots)], 1);
  New(mOuter);
  mOuter.Func := CountedThreadFunc;
  mOuter.Parameter := mInner;
  Result := mOuter;
end;

procedure CountingThreadEndProc(AExitCode: Integer);
begin
  // TThread.ThreadProc ruft EndThread erst nach dem Freigeben des Objekts (FreeOnTerminate).
  MarkThreadEnded;
end;

procedure InstallThreadCounting;
begin
  // Nur ohne fremde Haken (C++Builder setzt eigene); ohne Haken bleibt ThreadsRunningSince immer False.
  if Assigned(SystemThreadFuncProc) or Assigned(SystemThreadEndProc) then
  begin
    Exit;
  end;
  SystemThreadFuncProc := CountingThreadFuncProc;
  SystemThreadEndProc := CountingThreadEndProc;
end;

function StartedThreads: Int64;
begin
  Result := AtomicCmpExchange(ThreadsBegun, 0, 0);
end;

function ThreadsRunningSince(AFirst: Int64): Boolean;
var
  mLast: Int64;
  mNumber: Int64;
begin
  mLast := StartedThreads;
  if mLast - AFirst >= cThreadSlots then
  begin
    Exit(True);
  end;
  mNumber := AFirst;
  while mNumber <= mLast do
  begin
    if ThreadRunning[Integer(mNumber mod cThreadSlots)] <> 0 then
    begin
      Exit(True);
    end;
    Inc(mNumber);
  end;
  Result := False;
end;

function AllocatedBytes: Int64;
var
  mState: TMemoryManagerState;
  I: Integer;
begin
  {$WARN SYMBOL_PLATFORM OFF}
  GetMemoryManagerState(mState);
  {$WARN SYMBOL_PLATFORM DEFAULT}
  Result := Int64(mState.TotalAllocatedMediumBlockSize) + Int64(mState.TotalAllocatedLargeBlockSize);
  for I := Low(mState.SmallBlockTypeStates) to High(mState.SmallBlockTypeStates) do
  begin
    Inc(Result, Int64(mState.SmallBlockTypeStates[I].AllocatedBlockCount) *
      mState.SmallBlockTypeStates[I].UseableBlockSize);
  end;
end;

function ProcessThreadCount: Integer;
var
  mSnapshot: THandle;
  mEntry: TThreadEntry32;
  mProcessId: DWORD;
begin
  Result := 0;
  mSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if mSnapshot = INVALID_HANDLE_VALUE then
  begin
    Exit;
  end;
  try
    mProcessId := GetCurrentProcessId;
    FillChar(mEntry, SizeOf(mEntry), 0);
    mEntry.dwSize := SizeOf(mEntry);
    if Thread32First(mSnapshot, mEntry) then
      repeat
        if mEntry.th32OwnerProcessID = mProcessId then
        begin
          Inc(Result);
        end;
        mEntry.dwSize := SizeOf(mEntry);
      until not Thread32Next(mSnapshot, mEntry);
  finally
    CloseHandle(mSnapshot);
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

{ TWaitGate }

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
  mGate: TWaitGate;
  mWaiters: TArray<TThread>;
  mIndex: Integer;
  mDeadline: UInt64;
begin
  // Jeder Thread in TMonitor.Wait hält ein Warteobjekt der RTL; beim Freigeben
  // legt die RTL für jedes über den bisherigen Höchststand hinaus einen
  // Verwaltungsknoten an, der bis Programmende bleibt. Einmal viele Threads
  // gleichzeitig warten lassen, dann wächst der Zwischenspeicher in den Tests nicht mehr.
  mGate := TWaitGate.Create;
  try
    SetLength(mWaiters, 4 * TThread.ProcessorCount);
    if Length(mWaiters) < cMinPrewarmWaiters then
    begin
      SetLength(mWaiters, cMinPrewarmWaiters);
    end;
    for mIndex := 0 to High(mWaiters) do
    begin
      mWaiters[mIndex] := StartWaiter(mGate);
    end;
    // Inc steht unter der Sperre vor Wait; wer gezählt ist, wartet also schon.
    mDeadline := TThread.GetTickCount64 + 5000;
    while (mGate.Waiting < Length(mWaiters)) and (TThread.GetTickCount64 < mDeadline) do
    begin
      TThread.Sleep(1);
    end;
    TMonitor.Enter(mGate);
    try
      TMonitor.PulseAll(mGate);
    finally
      TMonitor.Exit(mGate);
    end;
    for mIndex := 0 to High(mWaiters) do
    begin
      mWaiters[mIndex].WaitFor;
      mWaiters[mIndex].Free;
    end;
  finally
    mGate.Free;
  end;
end;

procedure PrewarmRuntime;
var
  mTask: ITask;
  mCurrent: TThread;
begin
  PrewarmWaitObjects;
  // Legt den Standard-Thread-Pool und seinen Überwachungs-Thread an (bleiben bis Programmende).
  mTask := TTask.Run(
    procedure
    begin
    end);
  mTask.Wait;
  // Hauptthread: TExternalThread für TThread.CurrentThread (bleibt bis Programmende).
  mCurrent := TThread.CurrentThread;
  if mCurrent = nil then
  begin
    raise EInvalidOperation.Create('Kein aktueller Thread');
  end;
end;

procedure RegisterLeakMonitor;
begin
  // Sleep(2) beim Warten auf andere Threads schliefe sonst eine ganze Zeitscheibe (rund 16 ms)
  // und verdreifachte die Laufzeit der Tests.
  timeBeginPeriod(1);
  InstallThreadCounting;
  PrewarmRuntime;
  TFirstUse.WarmUp;
  TraceLeaks := TAllocationTrace.Requested;
  if TraceLeaks then
  begin
    TAllocationTrace.Install;
  end;
  TDUnitXServiceLocator.DefaultContainer.RegisterType<IMemoryLeakMonitor>(
    function: IMemoryLeakMonitor
    begin
      Result := TLeakMonitor.Create;
    end);
end;

{ TLeakMonitor }

procedure TLeakMonitor.Start;
begin
  // Aus PreSetup oder, bei einer Fixture ohne Setup, aus PreTest: nur beim ersten Aufruf.
  if FStarted then
  begin
    Exit;
  end;
  FStarted := True;
  TAtlasLocale.Use(TTextLanguage.German);
  FThreadsAtStart := ProcessThreadCount;
  FThreadsAtEnd := FThreadsAtStart;
  FFirstThread := StartedThreads + 1;
  // Vor der Messung freigeben: Der Bericht des vorigen Tests gehört nicht zu diesem.
  FTraceReport := '';
  if TraceLeaks then
  begin
    TAllocationTrace.Start;
  end;
end;

procedure TLeakMonitor.CaptureTrace;
begin
  // Gleich festhalten, solange die Tabelle noch diesem Test gehört; nur bei einem Leck, der Bericht kostet Zeit.
  // Ohne TearDown ist PostTest der letzte Haken, mit TearDown ersetzt PostTearDown den Bericht.
  if TraceLeaks and (RawTotal > 0) then
  begin
    FTraceReport := TAllocationTrace.Report(cTraceGroups);
  end;
end;

function TLeakMonitor.RawTotal: Int64;
begin
  Result := FSetUpAllocated + FTestAllocated + FTearDownAllocated;
end;

function TLeakMonitor.Reported(AValue: Int64): Int64;
begin
  // Mehr freigegeben als belegt: Freigaben anderer Threads, kein Leck.
  if RawTotal <= 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := AValue;
  end;
end;

procedure TLeakMonitor.Settle(ABefore: Int64; var AAllocated: Int64; AOthers: Int64);
var
  mStarted: UInt64;
  mLast: Int64;
  mStable: Integer;
begin
  // AOthers: Saldo der übrigen Abschnitte; gewartet wird, solange die Summe positiv ist.
  mStarted := TThread.GetTickCount64;
  mLast := AAllocated;
  mStable := 0;
  while (AOthers + AAllocated > 0) and (TThread.GetTickCount64 - mStarted < cSettleTimeoutMs) do
  begin
    TThread.Sleep(cSettleStepMs);
    AAllocated := AllocatedBytes - ABefore;
    if AAllocated = mLast then
    begin
      Inc(mStable);
    end
    else
    begin
      mStable := 0;
      mLast := AAllocated;
    end;
    // Ruhig und kein Thread des Tests läuft mehr: weiteres Warten bringt nichts.
    if (mStable >= cStableSamples) and not ThreadsRunningSince(FFirstThread) then
    begin
      Break;
    end;
  end;
  Inc(FWaitedMs, TThread.GetTickCount64 - mStarted);
  FThreadsAtEnd := ProcessThreadCount;
end;

procedure TLeakMonitor.PreSetup;
begin
  Start;
  FSetUpBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostSetUp;
begin
  FSetUpEnd := AllocatedBytes;
  FSetUpAllocated := FSetUpEnd - FSetUpBefore;
end;

procedure TLeakMonitor.PreTest;
var
  mGap: Int64;
begin
  Start;
  if FSetUpEnd <> 0 then
  begin
    mGap := AllocatedBytes - FSetUpEnd;
    FSetUpEnd := 0;
    if mGap < 0 then
    begin
      Inc(FSetUpAllocated, mGap);
    end;
  end;
  // Arbeiter früherer Tests vor der Messung beenden, damit ihre Freigabe in PostTest kein Leck verdeckt.
  TAtlasTimeLimit.StopAll(1000);
  FTestBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTest;
begin
  // Arbeiter des Zeitlimits (#493) bleiben für den nächsten Aufruf stehen; ihr Speicher gehört zu keinem
  // Test. Vor dem Messen beenden, der nächste Aufruf legt neue an.
  TAtlasTimeLimit.StopAll(1000);
  // Nummern des anonymen Protokolls (siehe Kopf); ohne TearDown gibt es keinen späteren Haken dafür.
  TAtlasGuard.RotatingLog.Redactor.Forget;
  FTestAllocated := AllocatedBytes - FTestBefore;
  // Nur der Test selbst: Was das Setup belegt, gibt meist erst das TearDown frei.
  if FTestAllocated > 0 then
  begin
    Settle(FTestBefore, FTestAllocated, 0);
  end
  else
  begin
    FThreadsAtEnd := ProcessThreadCount;
  end;
  CaptureTrace;
end;

procedure TLeakMonitor.PreTearDown;
begin
  FTearDownBefore := AllocatedBytes;
end;

procedure TLeakMonitor.PostTearDown;
begin
  // Nummern des anonymen Protokolls gehören keinem Test (siehe Kopf); vor der Messung vergessen.
  TAtlasGuard.RotatingLog.Redactor.Forget;
  FTearDownAllocated := AllocatedBytes - FTearDownBefore;
  if RawTotal > 0 then
  begin
    Settle(FTearDownBefore, FTearDownAllocated, FSetUpAllocated + FTestAllocated);
  end;
  if TraceLeaks then
  begin
    TAllocationTrace.Stop;
  end;
  CaptureTrace;
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
  if TraceLeaks then
  begin
    Result := Result + sLineBreak + FTraceReport;
  end;
end;

end.
