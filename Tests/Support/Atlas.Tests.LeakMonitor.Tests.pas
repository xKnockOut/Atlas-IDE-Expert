unit Atlas.Tests.LeakMonitor.Tests;

// Prüft die Speicherleck-Überwachung selbst und spielt die
// Protokollaufzeichnungen im Dauerlauf ab. Ein zweiter Dauerlauf (#177) geht
// über die echte TJsonRpcConnection mit Streams im Speicher: Worker-Anfragen,
// $/cancelRequest, Zeitlimit (TJsonRpcWatchdog), Benachrichtigungen über den
// Debouncer und ungültiges JSON laufen mit. Gemessen wird erst in Ruhe: alle
// Worker beendet, Debouncer leer.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLeakMonitorTests = class
  public
    [Test]
    procedure DetectsDeliberateLeak;
    [Test]
    procedure BalancedAllocationIsNoLeak;
    [Test]
    procedure NegativeBalanceIsNoLeak;
    [Test]
    procedure FreeOnOtherThreadIsNoLeak;
    [Test]
    procedure FreeBetweenSetupAndTestIsNoLeak;
    [Test]
    procedure ReportNamesThreads;
    [Test]
    // Ausnahme mit Grund: Misst das Wachstum selbst über viele Runden; die Aufwärmrunde füllt gewollte Caches
    // (RTTI, JSON), die der Monitor sonst diesem Test anlastete.
    [IgnoreMemoryLeaks]
    procedure ReplayDoesNotGrowMemory;
    [Test]
    // Ausnahme mit Grund: Misst das Wachstum selbst über viele Runden. Er läuft absichtlich über den
    // Thread-Pool der RTL wie der Server; dessen Worker bleiben über den Test hinaus bestehen.
    [IgnoreMemoryLeaks]
    procedure ConnectionSoakDoesNotGrowMemory;
    [Test]
    // Ausnahme mit Grund: leckt absichtlich im Worker-Pfad und prüft selbst, dass der Dauerlauf das erkennt.
    [IgnoreMemoryLeaks]
    procedure ConnectionSoakDetectsWorkerLeak;
  end;

implementation

uses
  System.Math,
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.JSON,
  System.Generics.Collections,
  System.SyncObjs,
  System.Diagnostics,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.JsonRpc.Connection,
  Atlas.Common.JsonRpc.StreamTransport,
  Atlas.Common.JsonRpc.TestSupport,
  Atlas.Common.JsonRpc.Watchdog,
  Atlas.Common.Lsp.Internals.Debouncer,
  Atlas.Common.Lsp.ProtocolReplay,
  Atlas.Tests.LeakMonitor;

const
  // Anzahl der Durchläufe aller Aufzeichnungen im Dauerlauf.
  cReplayRounds = 500;
  // Toleranz für Schwankungen des Speichermanagers.
  cAllowedGrowth = 64 * 1024;
  // Dauerlauf über TJsonRpcConnection: Runden zu je SoakGroups Gruppen aus echo,
  // Worker-Anfrage, abgebrochener Worker-Anfrage, Anfrage über dem Zeitlimit,
  // Benachrichtigung, Änderung über den Debouncer und ungültigem JSON.
  cSoakRounds = 50;
  cSoakGroups = 20;
  // Zeitlimit des Watchdogs im Dauerlauf; "stuck" läuft bis dahin.
  cSoakTimeoutMs = 100;
  // Verzögerung des Debouncers im Dauerlauf.
  cSoakDebounceMs = 5;

type
  /// <summary>Absichtliches Leck im Worker-Pfad: Plätze werden vor der Messung angelegt, damit nur die
  /// Objekte selbst zählen; freigegeben wird nach der Messung.</summary>
  TWorkerLeak = class
  private
    FSlots: TArray<TObject>;
    FCount: Integer;
  public
    constructor Create(ACapacity: Integer);
    destructor Destroy; override;
    procedure Leak;
  end;

constructor TWorkerLeak.Create(ACapacity: Integer);
begin
  inherited Create;
  SetLength(FSlots, ACapacity);
end;

destructor TWorkerLeak.Destroy;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FSlots) do
  begin
    FSlots[mIndex].Free;
  end;
  inherited;
end;

procedure TWorkerLeak.Leak;
var
  mSlot: Integer;
begin
  mSlot := TInterlocked.Increment(FCount) - 1;
  if mSlot <= High(FSlots) then
  begin
    FSlots[mSlot] := TStringBuilder.Create(256);
  end;
end;

type
  /// <summary>Dispatcher des Dauerlaufs mit Watchdog und Debouncer.</summary>
  TSoak = class
  private
    FDispatcher: TJsonRpcDispatcher;
    FDebouncer: TDebouncer;
    FTimeouts: Integer;
    FDebounced: Integer;
  public
    constructor Create(ALeak: TWorkerLeak);
    destructor Destroy; override;
    /// <summary>Wartet, bis der Debouncer nichts mehr geplant hat und keine Aktion läuft.</summary>
    procedure WaitIdle;
    property Dispatcher: TJsonRpcDispatcher read FDispatcher;
    property Timeouts: Integer read FTimeouts;
    property Debounced: Integer read FDebounced;
  end;

/// <summary>Anfragen, die bis zum Abbruch oder zum Zeitlimit des Watchdogs laufen (höchstens 10 s).</summary>
procedure RegisterSoakWaiters(const ADispatcher: TJsonRpcDispatcher);
begin
  // Läuft, bis $/cancelRequest eintrifft (höchstens 10 s).
  ADispatcher.RegisterConcurrentRequest('slow',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    var
      Watch: TStopwatch;
    begin
      Watch := TStopwatch.StartNew;
      while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
      begin
        TThread.Sleep(1);
      end;
      ACancellation.ThrowIfCancellationRequested;
      Result := TJSONString.Create('nicht abgebrochen');
    end);
  // Läuft, bis das Zeitlimit des Watchdogs sie abbricht (höchstens 10 s).
  ADispatcher.RegisterConcurrentRequest('stuck',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    var
      Watch: TStopwatch;
    begin
      Watch := TStopwatch.StartNew;
      while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
      begin
        TThread.Sleep(1);
      end;
      ACancellation.ThrowIfCancellationRequested;
      Result := TJSONString.Create('kein Zeitlimit');
    end);
end;

/// <summary>Entprellte Änderungen wie didChange und das Warten auf alle Worker.</summary>
procedure RegisterSoakChangeAndAwait(const ADispatcher: TJsonRpcDispatcher; const ASoak: TSoak);
begin
  // Wie didChange: je Schlüssel nur die letzte Änderung, ausgewertet im Thread des Debouncers.
  ADispatcher.RegisterNotification('change',
    procedure(const AParams: TJSONValue)
    var
      Text: string;
    begin
      Text := AParams.GetValue<string>('text', '');
      ASoak.FDebouncer.Schedule(AParams.GetValue<string>('key', ''),
        procedure
        var
          Parsed: TJSONValue;
        begin
          Parsed := TJSONObject.ParseJSONValue(Text);
          Parsed.Free;
          TInterlocked.Increment(ASoak.FDebounced);
        end);
    end);
  // Wartet in der Nachrichtenschleife, bis alle Worker fertig sind.
  ADispatcher.RegisterRequest('await',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONBool.Create(ADispatcher.PendingRequests.WaitForWork(10000));
    end);
end;

function CreateSoakDispatcher(ALeak: TWorkerLeak; ASoak: TSoak): TJsonRpcDispatcher;
var
  mDispatcher: TJsonRpcDispatcher;
begin
  mDispatcher := TJsonRpcDispatcher.Create;
  mDispatcher.RegisterRequest('echo',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end);
  mDispatcher.RegisterConcurrentRequest('parallel',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      if Assigned(ALeak) then
      begin
        ALeak.Leak;
      end;
      Result := TJSONString.Create('aus dem Worker');
    end);
  RegisterSoakWaiters(mDispatcher);
  mDispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
    end);
  RegisterSoakChangeAndAwait(mDispatcher, ASoak);
  Result := mDispatcher;
end;

{ TSoak }

constructor TSoak.Create(ALeak: TWorkerLeak);
var
  mSoak: TSoak;
begin
  inherited Create;
  mSoak := Self;
  FDebouncer := TDebouncer.Create(cSoakDebounceMs);
  FDispatcher := CreateSoakDispatcher(ALeak, Self);
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, cSoakTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      TInterlocked.Increment(mSoak.FTimeouts);
    end);
end;

destructor TSoak.Destroy;
begin
  FDispatcher.Watchdog := nil;
  FDebouncer.Free;
  FDispatcher.Free;
  inherited;
end;

procedure TSoak.WaitIdle;
begin
  Assert.IsTrue(FDebouncer.WaitIdle(10000), 'Debouncer wird nicht ruhig');
end;

/// <summary>Eine Runde: eine Verbindung, SoakGroups Gruppen, am Ende "await". Liefert die Antworten.</summary>
function RunSoakRound(ADispatcher: TJsonRpcDispatcher): TObjectList<TJSONObject>;
var
  mMessages: TList<string>;
  mOutput: TBytesStream;
  mInput: TBytesStream;
  mConnection: TJsonRpcConnection;
  mGroup, mId: Integer;
begin
  mMessages := TList<string>.Create;
  try
    mId := 0;
    for mGroup := 1 to cSoakGroups do
    begin
      mMessages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"echo","params":{"n":%d}}', [mId + 1, mGroup]));
      mMessages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"parallel"}', [mId + 2]));
      mMessages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"slow"}', [mId + 3]));
      mMessages.Add(Format('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":%d}}', [mId + 3]));
      mMessages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"stuck"}', [mId + 4]));
      mMessages.Add('{"jsonrpc":"2.0","method":"note","params":{}}');
      mMessages.Add(Format('{"jsonrpc":"2.0","method":"change","params":{"key":"k%d","text":"{\"n\":%d}"}}',
        [mGroup mod 3, mGroup]));
      mMessages.Add('{kein json');
      Inc(mId, 4);
    end;
    mMessages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"await"}', [mId + 1]));
    mInput := TJsonRpcTestSupport.InputOf(mMessages.ToArray);
  finally
    mMessages.Free;
  end;
  mOutput := TBytesStream.Create;
  try
    try
      mConnection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(mInput, mOutput, False), ADispatcher);
      try
        mConnection.Run;
      finally
        mConnection.Free;
      end;
    finally
      mInput.Free;
    end;
    Result := TJsonRpcTestSupport.ReadMessages(mOutput);
  finally
    mOutput.Free;
  end;
end;

/// <summary>Speicherwachstum über SoakRounds Runden nach einer Aufwärmrunde.</summary>
function SoakGrowth(ALeak: TWorkerLeak): Int64;
var
  mSoak: TSoak;
  mResponses: TObjectList<TJSONObject>;
  mBefore: Int64;
  mRound, mWindow: Integer;
begin
  mSoak := TSoak.Create(ALeak);
  try
    // Zwei Aufwärmrunden: Pool-Threads, RTTI und JSON-Caches. Nach nur einer Runde maß die erste Messung
    // bis zu 87 KB, weitere Messungen und doppelt so viele Runden blieben unter 5 KB (kein Leck).
    RunSoakRound(mSoak.Dispatcher).Free;
    mSoak.WaitIdle;
    RunSoakRound(mSoak.Dispatcher).Free;
    mSoak.WaitIdle;
    // Bis zu zwei Messabschnitte: Liegt der erste über der Toleranz, zählt der kleinere. Einmaliger Speicher
    // nach den Aufwärmrunden (gemessen bis 82 KB) fällt so heraus; ein echtes Leck wächst in beiden Abschnitten.
    Result := High(Int64);
    for mWindow := 1 to 2 do
    begin
      mBefore := AllocatedBytes;
      for mRound := 1 to cSoakRounds do
      begin
        mResponses := RunSoakRound(mSoak.Dispatcher);
        try
          // echo, parallel, slow, stuck und Parse-Fehler je Gruppe, dazu "await".
          Assert.AreEqual<NativeInt>(5 * cSoakGroups + 1, mResponses.Count, Format('Runde %d', [mRound]));
        finally
          mResponses.Free;
        end;
      end;
      // Messung erst in Ruhe: Worker sind durch "await" beendet, der Debouncer muss leer sein.
      mSoak.WaitIdle;
      Result := Min(Result, AllocatedBytes - mBefore);
      if Result <= cAllowedGrowth then
      begin
        Break;
      end;
    end;
    // Jede "stuck"-Anfrage lief ins Zeitlimit, jede Änderungsrunde lief durch den Debouncer.
    Assert.IsTrue(mSoak.Timeouts >= (cSoakRounds + 2) * cSoakGroups, Format('nur %d Zeitlimits', [mSoak.Timeouts]));
    Assert.IsTrue(mSoak.Debounced > 0, 'Debouncer lief nicht');
  finally
    mSoak.Free;
  end;
end;


procedure TLeakMonitorTests.DetectsDeliberateLeak;
var
  mMonitor: IMemoryLeakMonitor;
  mLeak: TObject;
begin
  mMonitor := TLeakMonitor.Create;
  mMonitor.PreTest;
  // Absichtliches Leck: wird erst nach der Messung freigegeben.
  mLeak := TStringBuilder.Create(1024);
  mMonitor.PostTest;
  mLeak.Free;
  Assert.IsTrue(mMonitor.TestMemoryAllocated > 0, 'Leck nicht erkannt');
end;

procedure TLeakMonitorTests.BalancedAllocationIsNoLeak;
var
  mMonitor: IMemoryLeakMonitor;
  mTemp: TObject;
begin
  mMonitor := TLeakMonitor.Create;
  mMonitor.PreTest;
  mTemp := TStringBuilder.Create(1024);
  mTemp.Free;
  mMonitor.PostTest;
  Assert.AreEqual(Int64(0), mMonitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.NegativeBalanceIsNoLeak;
var
  mMonitor: IMemoryLeakMonitor;
  mOld: TObject;
begin
  // Freigaben älteren Speichers (z. B. durch Threads früherer Tests) sind kein Leck.
  mMonitor := TLeakMonitor.Create;
  mOld := TStringBuilder.Create(1024);
  mMonitor.PreTest;
  mOld.Free;
  mMonitor.PostTest;
  Assert.AreEqual(Int64(0), mMonitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.FreeOnOtherThreadIsNoLeak;
var
  mMonitor: IMemoryLeakMonitor;
  mShared: TObject;
  mWorker: TThread;
begin
  // Ein Thread des Tests gibt Speicher frei, während der Test schon endet: Der
  // Monitor wartet die Freigabe ab, statt ein Leck zu melden.
  mMonitor := TLeakMonitor.Create;
  mWorker := TThread.CreateAnonymousThread(
    procedure
    begin
      FreeAndNil(mShared); // lsp-ignore: captured-loop-variable -- Absicht: der Thread gibt das Objekt später frei
    end);
  mWorker.FreeOnTerminate := False;
  try
    mMonitor.PreTest;
    mShared := TStringBuilder.Create(1024);
    mWorker.Start;
    mMonitor.PostTest;
    mWorker.WaitFor;
  finally
    mWorker.Free;
  end;
  Assert.AreEqual(Int64(0), mMonitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.FreeBetweenSetupAndTestIsNoLeak;
var
  mMonitor: TLeakMonitor;
  mBlock: Pointer;
begin
  mMonitor := TLeakMonitor.Create;
  try
    mMonitor.PreSetup;
    GetMem(mBlock, 4096);
    try
      mMonitor.PostSetUp;
    finally
      // Wie die Startdaten eines Threads: im Setup belegt, vor PreTest frei.
      FreeMem(mBlock);
    end;
    mMonitor.PreTest;
    mMonitor.PostTest;
    mMonitor.PreTearDown;
    mMonitor.PostTearDown;
    Assert.IsTrue(mMonitor.SetUpMemoryAllocated + mMonitor.TestMemoryAllocated + mMonitor.TearDownMemoryAllocated <= 0,
      mMonitor.GetReport);
  finally
    mMonitor.Free;
  end;
end;

procedure TLeakMonitorTests.ReportNamesThreads;
var
  mMonitor: IMemoryLeakMonitor;
  mReport: IMemoryLeakMonitor2;
begin
  mMonitor := TLeakMonitor.Create;
  mMonitor.PreTest;
  mMonitor.PostTest;
  Assert.IsTrue(Supports(mMonitor, IMemoryLeakMonitor2, mReport));
  Assert.Contains(mReport.GetReport, 'Threads am Anfang');
  Assert.IsTrue(ProcessThreadCount > 0);
end;

procedure TLeakMonitorTests.ReplayDoesNotGrowMemory;
var
  mRecordings: TObjectList<TJSONObject>;
  mFileName: string;
  mValue: TJSONValue;

  procedure ReplayAll;
  var
    mRecording: TJSONObject;
    mReplay: TProtocolReplay;
  begin
    for mRecording in mRecordings do
    begin
      mReplay := TProtocolReplay.Create;
      try
        mReplay.Run(mRecording);
      finally
        mReplay.Free;
      end;
    end;
  end;

var
  mBefore: Int64;
  mPass: Integer;
begin
  mRecordings := TObjectList<TJSONObject>.Create(True);
  try
    for mFileName in TDirectory.GetFiles(TProtocolReplay.DataDirectory, '*.json') do
    begin
      mValue := TJSONObject.ParseJSONValue(TFile.ReadAllText(mFileName, TEncoding.UTF8));
      if mValue is TJSONObject then
      begin
        mRecordings.Add(TJSONObject(mValue));
      end
      else
      begin
        mValue.Free;
      end;
    end;
    Assert.IsTrue(mRecordings.Count > 0, 'Keine Aufzeichnungen gefunden');

    // Aufwärmrunde füllt Caches, die bewusst bestehen bleiben.
    ReplayAll;
    mBefore := AllocatedBytes;
    for mPass := 1 to cReplayRounds do
    begin
      ReplayAll;
    end;
    Assert.IsTrue(AllocatedBytes - mBefore <= cAllowedGrowth,
      Format('Speicher nach %d Durchläufen um %d Bytes gewachsen',
        [cReplayRounds, AllocatedBytes - mBefore]));
  finally
    mRecordings.Free;
  end;
end;

procedure TLeakMonitorTests.ConnectionSoakDoesNotGrowMemory;
var
  mGrowth: Int64;
begin
  mGrowth := SoakGrowth(nil);
  Assert.IsTrue(mGrowth <= cAllowedGrowth, Format('Speicher nach %d Anfragen um %d Bytes gewachsen',
    [cSoakRounds * (cSoakGroups * 4 + 1), mGrowth]));
end;

procedure TLeakMonitorTests.ConnectionSoakDetectsWorkerLeak;
var
  mLeak: TWorkerLeak;
  mGrowth: Int64;
begin
  // Ein TStringBuilder je Worker-Anfrage: weit über der Toleranz.
  // Zwei Aufwärmrunden und bis zu zwei Messabschnitte.
  mLeak := TWorkerLeak.Create((2 * cSoakRounds + 2) * cSoakGroups);
  try
    mGrowth := SoakGrowth(mLeak);
  finally
    mLeak.Free;
  end;
  Assert.IsTrue(mGrowth > cAllowedGrowth, Format('Leck im Worker-Pfad nicht erkannt (%d Bytes)', [mGrowth]));
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakMonitorTests);

end.
