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
    procedure ReportNamesThreads;
    [Test]
    // Misst das Wachstum selbst über viele Runden; die Aufwärmrunde füllt gewollte Caches (RTTI, JSON).
    [IgnoreMemoryLeaks]
    procedure ReplayDoesNotGrowMemory;
    [Test]
    // Misst das Wachstum selbst über viele Runden; Pool-Threads behalten Verwaltungsdaten.
    [IgnoreMemoryLeaks]
    procedure ConnectionSoakDoesNotGrowMemory;
    [Test]
    // Wie oben, mit absichtlichem Leck im Worker-Pfad.
    [IgnoreMemoryLeaks]
    procedure ConnectionSoakDetectsWorkerLeak;
  end;

implementation

uses
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
  ReplayRounds = 500;
  // Toleranz für Schwankungen des Speichermanagers.
  AllowedGrowth = 64 * 1024;
  // Dauerlauf über TJsonRpcConnection: Runden zu je SoakGroups Gruppen aus echo,
  // Worker-Anfrage, abgebrochener Worker-Anfrage, Anfrage über dem Zeitlimit,
  // Benachrichtigung, Änderung über den Debouncer und ungültigem JSON.
  SoakRounds = 50;
  SoakGroups = 20;
  // Zeitlimit des Watchdogs im Dauerlauf; "stuck" läuft bis dahin.
  SoakTimeoutMs = 100;
  // Verzögerung des Debouncers im Dauerlauf.
  SoakDebounceMs = 5;

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
  Index: Integer;
begin
  for Index := 0 to High(FSlots) do
    FSlots[Index].Free;
  inherited;
end;

procedure TWorkerLeak.Leak;
var
  Slot: Integer;
begin
  Slot := TInterlocked.Increment(FCount) - 1;
  if Slot <= High(FSlots) then
    FSlots[Slot] := TStringBuilder.Create(256);
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

function CreateSoakDispatcher(ALeak: TWorkerLeak; ASoak: TSoak): TJsonRpcDispatcher;
var
  Dispatcher: TJsonRpcDispatcher;
begin
  Dispatcher := TJsonRpcDispatcher.Create;
  Dispatcher.RegisterRequest('echo',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONValue(AParams.Clone);
    end);
  Dispatcher.RegisterConcurrentRequest('parallel',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    begin
      if Assigned(ALeak) then
        ALeak.Leak;
      Result := TJSONString.Create('aus dem Worker');
    end);
  // Läuft, bis $/cancelRequest eintrifft (höchstens 10 s).
  Dispatcher.RegisterConcurrentRequest('slow',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    var
      Watch: TStopwatch;
    begin
      Watch := TStopwatch.StartNew;
      while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
        TThread.Sleep(1);
      ACancellation.ThrowIfCancellationRequested;
      Result := TJSONString.Create('nicht abgebrochen');
    end);
  // Läuft, bis das Zeitlimit des Watchdogs sie abbricht (höchstens 10 s).
  Dispatcher.RegisterConcurrentRequest('stuck',
    function(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue
    var
      Watch: TStopwatch;
    begin
      Watch := TStopwatch.StartNew;
      while not ACancellation.IsCancellationRequested and (Watch.ElapsedMilliseconds < 10000) do
        TThread.Sleep(1);
      ACancellation.ThrowIfCancellationRequested;
      Result := TJSONString.Create('kein Zeitlimit');
    end);
  Dispatcher.RegisterNotification('note',
    procedure(const AParams: TJSONValue)
    begin
    end);
  // Wie didChange: je Schlüssel nur die letzte Änderung, ausgewertet im Thread des Debouncers.
  Dispatcher.RegisterNotification('change',
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
  Dispatcher.RegisterRequest('await',
    function(const AParams: TJSONValue): TJSONValue
    begin
      Result := TJSONBool.Create(Dispatcher.PendingRequests.WaitForWork(10000));
    end);
  Result := Dispatcher;
end;

{ TSoak }

constructor TSoak.Create(ALeak: TWorkerLeak);
var
  Soak: TSoak;
begin
  inherited Create;
  Soak := Self;
  FDebouncer := TDebouncer.Create(SoakDebounceMs);
  FDispatcher := CreateSoakDispatcher(ALeak, Self);
  FDispatcher.Watchdog := TJsonRpcWatchdog.Create(FDispatcher.PendingRequests, SoakTimeoutMs,
    procedure(const AMethod: string; ATimeoutMs: Cardinal; AAnswered: Boolean)
    begin
      TInterlocked.Increment(Soak.FTimeouts);
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
  Messages: TList<string>;
  Output: TBytesStream;
  Input: TBytesStream;
  Connection: TJsonRpcConnection;
  Group, Id: Integer;
begin
  Messages := TList<string>.Create;
  try
    Id := 0;
    for Group := 1 to SoakGroups do
    begin
      Messages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"echo","params":{"n":%d}}', [Id + 1, Group]));
      Messages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"parallel"}', [Id + 2]));
      Messages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"slow"}', [Id + 3]));
      Messages.Add(Format('{"jsonrpc":"2.0","method":"$/cancelRequest","params":{"id":%d}}', [Id + 3]));
      Messages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"stuck"}', [Id + 4]));
      Messages.Add('{"jsonrpc":"2.0","method":"note","params":{}}');
      Messages.Add(Format('{"jsonrpc":"2.0","method":"change","params":{"key":"k%d","text":"{\"n\":%d}"}}',
        [Group mod 3, Group]));
      Messages.Add('{kein json');
      Inc(Id, 4);
    end;
    Messages.Add(Format('{"jsonrpc":"2.0","id":%d,"method":"await"}', [Id + 1]));
    Input := TJsonRpcTestSupport.InputOf(Messages.ToArray);
  finally
    Messages.Free;
  end;
  Output := TBytesStream.Create;
  try
    try
      Connection := TJsonRpcConnection.Create(TJsonRpcStreamTransport.Create(Input, Output, False), ADispatcher);
      try
        Connection.Run;
      finally
        Connection.Free;
      end;
    finally
      Input.Free;
    end;
    Result := TJsonRpcTestSupport.ReadMessages(Output);
  finally
    Output.Free;
  end;
end;

/// <summary>Speicherwachstum über SoakRounds Runden nach einer Aufwärmrunde.</summary>
function SoakGrowth(ALeak: TWorkerLeak): Int64;
var
  Soak: TSoak;
  Responses: TObjectList<TJSONObject>;
  Before: Int64;
  Round: Integer;
begin
  Soak := TSoak.Create(ALeak);
  try
    // Zwei Aufwärmrunden: Pool-Threads, RTTI und JSON-Caches. Nach nur einer Runde maß die erste Messung
    // bis zu 87 KB, weitere Messungen und doppelt so viele Runden blieben unter 5 KB (kein Leck).
    RunSoakRound(Soak.Dispatcher).Free;
    Soak.WaitIdle;
    RunSoakRound(Soak.Dispatcher).Free;
    Soak.WaitIdle;
    Before := AllocatedBytes;
    for Round := 1 to SoakRounds do
    begin
      Responses := RunSoakRound(Soak.Dispatcher);
      try
        // echo, parallel, slow, stuck und Parse-Fehler je Gruppe, dazu "await".
        Assert.AreEqual<NativeInt>(5 * SoakGroups + 1, Responses.Count, Format('Runde %d', [Round]));
      finally
        Responses.Free;
      end;
    end;
    // Messung erst in Ruhe: Worker sind durch "await" beendet, der Debouncer muss leer sein.
    Soak.WaitIdle;
    Result := AllocatedBytes - Before;
    // Jede "stuck"-Anfrage lief ins Zeitlimit, jede Änderungsrunde lief durch den Debouncer.
    Assert.IsTrue(Soak.Timeouts >= (SoakRounds + 2) * SoakGroups, Format('nur %d Zeitlimits', [Soak.Timeouts]));
    Assert.IsTrue(Soak.Debounced > 0, 'Debouncer lief nicht');
  finally
    Soak.Free;
  end;
end;


procedure TLeakMonitorTests.DetectsDeliberateLeak;
var
  Monitor: IMemoryLeakMonitor;
  Leak: TObject;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  // Absichtliches Leck: wird erst nach der Messung freigegeben.
  Leak := TStringBuilder.Create(1024);
  Monitor.PostTest;
  Leak.Free;
  Assert.IsTrue(Monitor.TestMemoryAllocated > 0, 'Leck nicht erkannt');
end;

procedure TLeakMonitorTests.BalancedAllocationIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Temp: TObject;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  Temp := TStringBuilder.Create(1024);
  Temp.Free;
  Monitor.PostTest;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.NegativeBalanceIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Old: TObject;
begin
  // Freigaben älteren Speichers (z. B. durch Threads früherer Tests) sind kein Leck.
  Monitor := TLeakMonitor.Create;
  Old := TStringBuilder.Create(1024);
  Monitor.PreTest;
  Old.Free;
  Monitor.PostTest;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.FreeOnOtherThreadIsNoLeak;
var
  Monitor: IMemoryLeakMonitor;
  Shared: TObject;
  Worker: TThread;
begin
  // Ein Thread des Tests gibt Speicher frei, während der Test schon endet: Der
  // Monitor wartet die Freigabe ab, statt ein Leck zu melden.
  Monitor := TLeakMonitor.Create;
  Worker := TThread.CreateAnonymousThread(
    procedure
    begin
      FreeAndNil(Shared);
    end);
  Worker.FreeOnTerminate := False;
  try
    Monitor.PreTest;
    Shared := TStringBuilder.Create(1024);
    Worker.Start;
    Monitor.PostTest;
    Worker.WaitFor;
  finally
    Worker.Free;
  end;
  Assert.AreEqual(Int64(0), Monitor.TestMemoryAllocated);
end;

procedure TLeakMonitorTests.ReportNamesThreads;
var
  Monitor: IMemoryLeakMonitor;
  Report: IMemoryLeakMonitor2;
begin
  Monitor := TLeakMonitor.Create;
  Monitor.PreTest;
  Monitor.PostTest;
  Assert.IsTrue(Supports(Monitor, IMemoryLeakMonitor2, Report));
  Assert.Contains(Report.GetReport, 'Threads am Anfang');
  Assert.IsTrue(ProcessThreadCount > 0);
end;

procedure TLeakMonitorTests.ReplayDoesNotGrowMemory;
var
  Recordings: TObjectList<TJSONObject>;
  FileName: string;
  Value: TJSONValue;

  procedure ReplayAll;
  var
    Recording: TJSONObject;
    Replay: TProtocolReplay;
  begin
    for Recording in Recordings do
    begin
      Replay := TProtocolReplay.Create;
      try
        Replay.Run(Recording);
      finally
        Replay.Free;
      end;
    end;
  end;

var
  Before: Int64;
  Pass: Integer;
begin
  Recordings := TObjectList<TJSONObject>.Create(True);
  try
    for FileName in TDirectory.GetFiles(TProtocolReplay.DataDirectory, '*.json') do
    begin
      Value := TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName, TEncoding.UTF8));
      if Value is TJSONObject then
        Recordings.Add(TJSONObject(Value))
      else
        Value.Free;
    end;
    Assert.IsTrue(Recordings.Count > 0, 'Keine Aufzeichnungen gefunden');

    // Aufwärmrunde füllt Caches, die bewusst bestehen bleiben.
    ReplayAll;
    Before := AllocatedBytes;
    for Pass := 1 to ReplayRounds do
      ReplayAll;
    Assert.IsTrue(AllocatedBytes - Before <= AllowedGrowth,
      Format('Speicher nach %d Durchläufen um %d Bytes gewachsen',
        [ReplayRounds, AllocatedBytes - Before]));
  finally
    Recordings.Free;
  end;
end;

procedure TLeakMonitorTests.ConnectionSoakDoesNotGrowMemory;
var
  Growth: Int64;
begin
  Growth := SoakGrowth(nil);
  Assert.IsTrue(Growth <= AllowedGrowth, Format('Speicher nach %d Anfragen um %d Bytes gewachsen',
    [SoakRounds * (SoakGroups * 4 + 1), Growth]));
end;

procedure TLeakMonitorTests.ConnectionSoakDetectsWorkerLeak;
var
  Leak: TWorkerLeak;
  Growth: Int64;
begin
  // Ein TStringBuilder je Worker-Anfrage: weit über der Toleranz.
  Leak := TWorkerLeak.Create((SoakRounds + 2) * SoakGroups);
  try
    Growth := SoakGrowth(Leak);
  finally
    Leak.Free;
  end;
  Assert.IsTrue(Growth > AllowedGrowth, Format('Leck im Worker-Pfad nicht erkannt (%d Bytes)', [Growth]));
end;

initialization
  TDUnitX.RegisterTestFixture(TLeakMonitorTests);

end.
