unit Atlas.Plugin.Diagnostics.TimeLimit.Tests;

// Absturzsicherheit (#493): Zeitlimit für Quellen, gemeinsames Abbruchsignal
// und Sicherung je Quelle in der zusammengeführten Vervollständigung. Eine
// Zeitüberschreitung ist kein Fehler und schaltet keine Quelle ab. Hängende
// Arbeiter gehen beim Beenden und beim Abmelden des Moduls ihrer Quelle an
// TAtlasOverdueThreads; festgehalten wird dabei nie wirklich (ResetForTests).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTimeLimitTests = class
  private
    FFolder: string;
    FOldFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure RunsAndReportsErrors;
    [Test]
    procedure HangingCallReturnsAfterLimit;
    [Test]
    procedure ShutdownEndsWaitsAndWorkers;
    [Test]
    procedure ClientRequestEndsOnShutdown;
    [Test]
    procedure FailingProviderTripsOnlyItself;
    [Test]
    procedure HangingProviderBlocksAtMostLimit;
    /// <summary>Langsame Quelle: keine Sicherung, und solange ihr voriger Aufruf läuft, kein weiterer Arbeiter.
    /// </summary>
    [Test]
    procedure SlowProviderNeverTripsAndRunsOnce;
    [Test]
    procedure FetchErrorsCountPerProvider;
    [Test]
    procedure WaitIdleWaitsForAbandonedWorker;
    /// <summary>StopAll übergibt einen hängenden Arbeiter an TAtlasOverdueThreads; er zählt für das Package,
    /// bis er zurückkehrt, und wird dann freigegeben.</summary>
    [Test]
    procedure StopAllHandsHangingWorkerOver;
    /// <summary>Hängt ein Aufruf mit Code eines Modul-Packages, zählt er nach StopAll für dieses Package.</summary>
    [Test]
    procedure StopAllKeepsModuleOfHangingCall;
    /// <summary>Abmelden eines Moduls: aufgegebene Arbeiter mit seinem Code gehen sofort über, andere nicht.
    /// </summary>
    [Test]
    procedure ReleaseModuleHandsOverAbandonedWorkers;
    /// <summary>Wartet ein Aufrufer noch, geht der Arbeiter erst über, wenn dieser aufgibt.</summary>
    [Test]
    procedure ReleaseModuleWaitsForWaitingCaller;
    /// <summary>Die zusammengeführte Vervollständigung führt das Package jeder Quelle mit.</summary>
    [Test]
    procedure HangingProviderCountsForItsPackage;
    [Test]
    procedure StaleQueryAfterPrepareFetchesNothing;
    [Test]
    procedure PrepareRunsInWorkerThread;
    [Test]
    procedure ServerSessionFuncRunsInWorker;
    [Test]
    procedure SignatureSyncsInCallingThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  System.IOUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Diagnostics.Shutdown,
  Atlas.Plugin.Diagnostics.TimeLimit,
  Atlas.Plugin.Diagnostics.MainThread,
  Atlas.Plugin.Diagnostics.UnloadSafety,
  Atlas.Plugin.Diagnostics.WorkerSlot,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Internals.Async,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Providers.Server,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Completion.TestSupport;

const
  /// <summary>Handle eines Modul-Packages, das es nicht gibt.</summary>
  cModule = $5A5B0000;
  /// <summary>Ein zweites, an dem nichts hängt.</summary>
  cOtherModule = $5A5C0000;
  cHangMs = 5000;

type
  /// <summary>Quelle, die beim Aufruf wirft bzw. hängt (wie ein kaputter SQL-Provider).</summary>
  TBrokenProvider = class(TInterfacedObject, IAtlasCompletionProvider, IAtlasNamedProvider)
  private
    FName: string;
    FHangMs: Cardinal;
  public
    Calls: Integer;
    constructor Create(const AName: string; AHangMs: Cardinal);
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
    function ProviderName: string;
  end;

  /// <summary>Quelle, deren Fetch im Hintergrund wirft.</summary>
  TFailingFetchProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  end;

  /// <summary>Wie eine Zeitüberschreitung in Composite: Cancel kommt, während Prepare noch läuft.</summary>
  TCancelInPrepareProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  public
    Fetches: Integer;
  end;

  /// <summary>Merkt sich, in welchem Thread Prepare läuft.</summary>
  TThreadRecordingProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AState: TAtlasFetchState): TAtlasCompletionItems; override;
  public
    PrepareThread: TThreadID;
  end;

{ TCancelInPrepareProvider }

function TCancelInPrepareProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
begin
  AData := nil;
  Cancel;
  Result := True;
end;

function TCancelInPrepareProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc;
    out AState: TAtlasFetchState): TAtlasCompletionItems;
begin
  AState := Default(TAtlasFetchState);
  TInterlocked.Increment(Fetches);
  Result := nil;
end;

{ TThreadRecordingProvider }

function TThreadRecordingProvider.Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean;
begin
  AData := nil;
  PrepareThread := TThread.CurrentThread.ThreadID;
  Result := False;
end;

function TThreadRecordingProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc;
    out AState: TAtlasFetchState): TAtlasCompletionItems;
begin
  AState := Default(TAtlasFetchState);
  Result := nil;
end;

{ TBrokenProvider }

constructor TBrokenProvider.Create(const AName: string; AHangMs: Cardinal);
begin
  inherited Create;
  FName := AName;
  FHangMs := AHangMs;
end;

procedure TBrokenProvider.Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
begin
  TInterlocked.Increment(Calls);
  if FHangMs = 0 then
  begin
    raise EInvalidOpException.Create('SQL-Provider kaputt');
  end;
  // Hängt, endet aber beim Abbruchsignal (wie jeder Thread von Atlas).
  TAtlasShutdown.Wait(FHangMs);
  ASink.Complete;
end;

procedure TBrokenProvider.Cancel;
begin
end;

function TBrokenProvider.ProviderName: string;
begin
  Result := FName;
end;

{ TFailingFetchProvider }

function TFailingFetchProvider.Fetch(const AContext: TAtlasContext; AData: TObject;
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc;
    out AState: TAtlasFetchState): TAtlasCompletionItems;
begin
  AState := Default(TAtlasFetchState);
  raise EInvalidOpException.Create('Fetch kaputt');
end;

function Item(const AName: string): TAtlasCompletionItem;
begin
  Result := Default(TAtlasCompletionItem);
  Result.Name := AName;
end;

function Context: TAtlasContext;
begin
  Result := Default(TAtlasContext);
  Result.FileName := 'C:\Projekt\Unit1.pas';
end;

{ TAtlasTimeLimitTests }

procedure TAtlasTimeLimitTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasTimeLimitTests' + TGUID.NewGuid.ToString);
  FOldFolder := TAtlasGuard.RotatingLog.Folder;
  TAtlasGuard.RotatingLog.Folder := FFolder;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasShutdown.Reset;
  TAtlasTimeLimit.LimitMs := TAtlasTimeLimit.cDefaultMs;
  // Festhalten nur zählen, nie das Testprogramm wirklich festhalten.
  TAtlasUnloadSafety.ResetForTests(
    procedure(AModule: HMODULE)
    begin
    end);
end;

procedure TAtlasTimeLimitTests.TearDown;
begin
  TAtlasUnloadSafety.ResetForTests(nil);
  TAtlasShutdown.Reset;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasTimeLimitTests.RunsAndReportsErrors;
var
  mError: string;
  mRan: Boolean;
begin
  mRan := False;
  Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Done, TAtlasTimeLimit.Run(
    procedure
    begin
      mRan := True;
    end, mError));
  Assert.IsTrue(mRan);
  Assert.AreEqual('', mError);
  Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Failed, TAtlasTimeLimit.Run(
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end, mError));
  Assert.AreEqual('EInvalidOpException: kaputt', mError);
end;

procedure TAtlasTimeLimitTests.HangingCallReturnsAfterLimit;
var
  mWatch: TStopwatch;
  mError: string;
  mRelease: TEvent;
begin
  mRelease := TEvent.Create(nil, True, False, '');
  try
    mWatch := TStopwatch.StartNew;
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut, TAtlasTimeLimit.Run(
      procedure
      begin
        mRelease.WaitFor(5000);
      end, mError, 200));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 450, Format('blockiert %d ms', [mWatch.ElapsedMilliseconds]));
    // Der nächste Aufruf bekommt einen anderen Arbeiter und läuft sofort.
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Done, TAtlasTimeLimit.Run(
      procedure
      begin
      end, mError));
    mRelease.SetEvent;
  finally
    // Erst freigeben, wenn der hängende Arbeiter zurück ist.
    Sleep(50);
    mRelease.Free;
  end;
end;

/// <summary>Löst nach 50 ms das Signal zum Beenden aus. Der Test wartet am Ende auf den Thread, statt dass er
/// sich irgendwann selbst freigibt.</summary>
function SignalShutdownSoon: TThread;
begin
  Result := TThread.CreateAnonymousThread(
    procedure
    begin
      Sleep(50);
      TAtlasShutdown.Signal;
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure JoinThread(AThread: TThread);
begin
  if AThread = nil then
  begin
    Exit;
  end;
  AThread.WaitFor;
  AThread.Free;
end;

procedure TAtlasTimeLimitTests.ShutdownEndsWaitsAndWorkers;
var
  mWatch: TStopwatch;
  mEvent: TEvent;
  mError: string;
  mSignaller: TThread;
begin
  mSignaller := nil;
  mEvent := TEvent.Create(nil, True, False, '');
  try
    Assert.AreEqual<TWaitResult>(wrTimeout, TAtlasShutdown.WaitFor(mEvent, 30));
    mEvent.SetEvent;
    Assert.AreEqual<TWaitResult>(wrSignaled, TAtlasShutdown.WaitFor(mEvent, 30));
    mEvent.ResetEvent;
    // Ein Arbeiter hängt in einer Quelle, die auf das Signal hört.
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut, TAtlasTimeLimit.Run(
      procedure
      begin
        TAtlasShutdown.Wait(10000);
      end, mError, 50));
    mSignaller := SignalShutdownSoon;
    mWatch := TStopwatch.StartNew;
    Assert.AreEqual<TWaitResult>(wrAbandoned, TAtlasShutdown.WaitFor(mEvent, 10000));
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 500);
    mWatch := TStopwatch.StartNew;
    Assert.IsTrue(TAtlasTimeLimit.StopAll(TAtlasShutdown.cStopMs), 'alle Arbeiter beendet');
    Assert.IsTrue(mWatch.ElapsedMilliseconds < TAtlasShutdown.cStopMs);
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Failed, TAtlasTimeLimit.Run(
      procedure
      begin
      end, mError), 'nach dem Signal startet nichts mehr');
  finally
    JoinThread(mSignaller);
    mEvent.Free;
  end;
  TAtlasShutdown.Reset;
  Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Done, TAtlasTimeLimit.Run(
    procedure
    begin
    end, mError), 'nach Reset wieder bereit');
end;

procedure TAtlasTimeLimitTests.ClientRequestEndsOnShutdown;
var
  mClient: TLspClient;
  mWatch: TStopwatch;
  mSignaller: TThread;
begin
  mSignaller := nil;
  mClient := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    mSignaller := SignalShutdownSoon;
    mWatch := TStopwatch.StartNew;
    Assert.WillRaise(
      procedure
      begin
        mClient.Request('textDocument/hover', nil, 10000).Free;
      end, ELspClientError);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 500, Format('wartete %d ms', [mWatch.ElapsedMilliseconds]));
  finally
    JoinThread(mSignaller);
    mClient.Free;
  end;
end;

procedure TAtlasTimeLimitTests.FailingProviderTripsOnlyItself;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mBroken: TBrokenProvider;
  mBrokenRef: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mIndex: Integer;
  mWarning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      mWarning := AText;
    end;
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mBroken := TBrokenProvider.Create('SQL', 0);
  mBrokenRef := mBroken;
  mProviders.Add(mBrokenRef);
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Alpha')]));
  for mIndex := 1 to 3 do
  begin
    mSink := TCollectingSink.Create;
    mSinkRef := mSink;
    mProvider.Query(Context, mSinkRef);
    Assert.IsTrue(mSink.WaitDone(3000), 'Complete trotz kaputter Quelle');
    Assert.AreEqual('Alpha', mSink.Names, 'die übrigen Quellen liefern weiter');
  end;
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('SQL'), 'nach dem dritten Fehler abgeschaltet');
  Assert.Contains(mWarning, 'SQL');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Vervollständigung (fest)'));
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Completion), 'nur die Quelle, nicht die Vervollständigung');
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000));
  Assert.AreEqual('Alpha', mSink.Names);
  Assert.AreEqual(3, mBroken.Calls, 'abgeschaltete Quelle wird nicht mehr gefragt');
  TAtlasGuard.EnableProvider('SQL');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
end;

procedure TAtlasTimeLimitTests.HangingProviderBlocksAtMostLimit;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mWatch: TStopwatch;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.Add(TBrokenProvider.Create('Hängt', 5000));
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Beta')]));
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mWatch := TStopwatch.StartNew;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mWatch.ElapsedMilliseconds < 450, Format('Query blockierte %d ms', [mWatch.ElapsedMilliseconds]));
  Assert.IsTrue(mSink.WaitDone(3000));
  Assert.AreEqual('Beta', mSink.Names);
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8),
    'Quelle Hängt langsam: text#');
  // Hängenden Arbeiter freigeben.
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.StopAll;
end;

procedure TAtlasTimeLimitTests.SlowProviderNeverTripsAndRunsOnce;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mSlow: TBrokenProvider;
  mSlowRef: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mWatch: TStopwatch;
  mIndex: Integer;
  mText: string;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mSlow := TBrokenProvider.Create('Langsam', 5000);
  mSlowRef := mSlow;
  mProviders.Add(mSlowRef);
  mProviders.Add(TAtlasFixedCompletionProvider.Create([Item('Gamma')]));
  for mIndex := 1 to 4 do
  begin
    mSink := TCollectingSink.Create;
    mSinkRef := mSink;
    mWatch := TStopwatch.StartNew;
    mProvider.Query(Context, mSinkRef);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 450, Format('Query blockierte %d ms', [mWatch.ElapsedMilliseconds]));
    Assert.IsTrue(mSink.WaitDone(3000));
    Assert.AreEqual('Gamma', mSink.Names, 'die übrigen Quellen liefern weiter');
  end;
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Langsam'), 'langsam ist kein Fehler');
  Assert.AreEqual(1, mSlow.Calls, 'solange der erste Aufruf läuft, kein weiterer Arbeiter');
  mText := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(mText, 'Quelle Langsam langsam: text#');
  Assert.AreEqual(1, Integer(Length(mText.Trim.Split([sLineBreak]))), 'eine Zeile je Quelle und Minute');
  Assert.IsFalse(mText.Contains('Fehler in Quelle'), 'keine Fehlerzeile');
  // Hängenden Arbeiter freigeben; danach fragt die Quelle wieder.
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.WaitIdle(2000);
  TAtlasShutdown.Reset;
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000));
  Assert.AreEqual(2, mSlow.Calls, 'nach seiner Rückkehr läuft die Quelle wieder');
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.StopAll;
end;

procedure TAtlasTimeLimitTests.FetchErrorsCountPerProvider;
var
  mFailing: TFailingFetchProvider;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mIndex: Integer;
begin
  mFailing := TFailingFetchProvider.Create;
  mFailing.Name := 'Kaputt';
  mProvider := mFailing;
  for mIndex := 1 to 3 do
  begin
    mSink := TCollectingSink.Create;
    mSinkRef := mSink;
    mProvider.Query(Context, mSinkRef);
    Assert.IsTrue(mSink.WaitDone(3000), 'leeres Ergebnis statt Exception');
  end;
  mFailing.Shutdown;
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('Kaputt'));
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('kaputt'), 'Name ohne Groß-/Kleinschreibung');
end;

procedure TAtlasTimeLimitTests.WaitIdleWaitsForAbandonedWorker;
var
  mError: string;
  mRelease: TEvent;
begin
  mRelease := TEvent.Create(nil, True, False, '');
  try
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut, TAtlasTimeLimit.Run(
      procedure
      begin
        mRelease.WaitFor(5000);
      end, mError, 50));
    Assert.IsFalse(TAtlasTimeLimit.WaitIdle(30), 'der aufgegebene Arbeiter läuft noch');
    mRelease.SetEvent;
    Assert.IsTrue(TAtlasTimeLimit.WaitIdle(2000), 'nach seiner Rückkehr frei');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
  finally
    mRelease.SetEvent;
    TAtlasTimeLimit.WaitIdle(2000);
    mRelease.Free;
  end;
end;

/// <summary>Wartet auf AEvent, höchstens cHangMs: ein Aufruf, der in nicht abbrechbarem Code steckt.</summary>
function HangOn(AEvent: TEvent): TProc;
begin
  Result :=
    procedure
    begin
      AEvent.WaitFor(cHangMs);
    end;
end;

/// <summary>Gibt AEvent frei und wartet, bis kein überfälliger Arbeiter von AModule mehr läuft.</summary>
function ReleaseAndSettle(AEvent: TEvent; AModule: HMODULE): Boolean;
const
  cSettleMs = 2000;
begin
  AEvent.SetEvent;
  Result := TAtlasOverdueThreads.SettleBeforeUnload(AModule, cSettleMs);
end;

procedure TAtlasTimeLimitTests.StopAllHandsHangingWorkerOver;
var
  mError: string;
  mRelease: TEvent;
  mBefore: Integer;
begin
  mRelease := TEvent.Create(nil, True, False, '');
  try
    mBefore := TAtlasOverdueThreads.Pending(HInstance);
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut,
      TAtlasTimeLimit.Run(HangOn(mRelease), mError, 50));
    Assert.IsFalse(TAtlasTimeLimit.StopAll(50), 'der Arbeiter steckt noch im Aufruf');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount, 'nicht mehr im Vorrat');
    Assert.AreEqual(mBefore + 1, TAtlasOverdueThreads.Pending(HInstance),
      'überfällig: SettleBeforeUnload wartet auf ihn und hält das Package sonst fest');
    Assert.IsTrue(ReleaseAndSettle(mRelease, HInstance), 'nach seiner Rückkehr beendet');
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(HInstance), 'und freigegeben');
    Assert.IsTrue(TAtlasUnloadSafety.IsSafe(HInstance));
  finally
    ReleaseAndSettle(mRelease, HInstance);
    mRelease.Free;
  end;
end;

procedure TAtlasTimeLimitTests.StopAllKeepsModuleOfHangingCall;
var
  mError: string;
  mRelease: TEvent;
begin
  mRelease := TEvent.Create(nil, True, False, '');
  try
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut,
      TAtlasTimeLimit.Run(HangOn(mRelease), mError, 50, cModule));
    Assert.IsFalse(TAtlasTimeLimit.StopAll(50));
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule), 'das Package der Quelle, nicht nur das eigene');
    Assert.IsTrue(ReleaseAndSettle(mRelease, cModule));
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cModule));
  finally
    ReleaseAndSettle(mRelease, cModule);
    mRelease.Free;
  end;
end;

procedure TAtlasTimeLimitTests.ReleaseModuleHandsOverAbandonedWorkers;
var
  mError: string;
  mRelease: TEvent;
  mOther: TEvent;
begin
  mOther := nil;
  mRelease := TEvent.Create(nil, True, False, '');
  try
    mOther := TEvent.Create(nil, True, False, '');
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut,
      TAtlasTimeLimit.Run(HangOn(mRelease), mError, 50, cModule));
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.TimedOut,
      TAtlasTimeLimit.Run(HangOn(mOther), mError, 50, cOtherModule));
    Assert.AreEqual(0, TAtlasTimeLimit.ReleaseModule(0), '0 wird übergangen');
    Assert.AreEqual(1, TAtlasTimeLimit.ReleaseModule(cModule), 'nur der Arbeiter im Code des Moduls');
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule));
    Assert.AreEqual(0, TAtlasOverdueThreads.Pending(cOtherModule), 'der andere bleibt im Vorrat');
    Assert.AreEqual(1, TAtlasTimeLimit.BusyCount);
    Assert.AreEqual(0, TAtlasTimeLimit.ReleaseModule(cModule), 'schon übergeben');
    Assert.IsTrue(ReleaseAndSettle(mRelease, cModule));
    mOther.SetEvent;
    Assert.IsTrue(TAtlasTimeLimit.WaitIdle(2000), 'der andere kehrt in den Vorrat zurück');
    Assert.AreEqual<TAtlasTimedOutcome>(TAtlasTimedOutcome.Done, TAtlasTimeLimit.Run(
      procedure
      begin
      end, mError), 'der Vorrat arbeitet weiter');
  finally
    ReleaseAndSettle(mRelease, cModule);
    if mOther <> nil then
    begin
      mOther.SetEvent;
      TAtlasTimeLimit.WaitIdle(2000);
    end;
    mOther.Free;
    mRelease.Free;
  end;
end;

/// <summary>Führt in einem eigenen Thread Run mit ALimitMs für AModule aus; AOutcome bekommt das Ergebnis.
/// </summary>
function RunInThread(AEvent: TEvent; ALimitMs: Integer; AModule: HMODULE;
  AOutcome: PInteger): TThread;
var
  mEvent: TEvent;
begin
  mEvent := AEvent;
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mError: string;
    begin
      AOutcome^ := Ord(TAtlasTimeLimit.Run(HangOn(mEvent), mError, ALimitMs, AModule));
    end);
  Result.FreeOnTerminate := False;
  Result.Start;
end;

procedure TAtlasTimeLimitTests.ReleaseModuleWaitsForWaitingCaller;
const
  cCallerLimitMs = 400;
var
  mRelease: TEvent;
  mCaller: TThread;
  mOutcome: Integer;
  mWatch: TStopwatch;
begin
  mCaller := nil;
  mOutcome := -1;
  mRelease := TEvent.Create(nil, True, False, '');
  try
    mCaller := RunInThread(mRelease, cCallerLimitMs, cModule, @mOutcome);
    mWatch := TStopwatch.StartNew;
    while (TAtlasTimeLimit.BusyCount = 0) and (mWatch.ElapsedMilliseconds < 2000) do
    begin
      TThread.Yield;
    end;
    Assert.AreEqual(1, TAtlasTimeLimit.BusyCount, 'der Aufruf läuft');
    Assert.AreEqual(0, TAtlasTimeLimit.ReleaseModule(cModule), 'der Aufrufer wartet noch auf den Arbeiter');
    JoinThread(mCaller);
    mCaller := nil;
    Assert.AreEqual(Ord(TAtlasTimedOutcome.TimedOut), mOutcome);
    Assert.AreEqual(1, TAtlasOverdueThreads.Pending(cModule), 'übergeben, als der Aufrufer aufgab');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
    Assert.IsTrue(ReleaseAndSettle(mRelease, cModule));
  finally
    mRelease.SetEvent;
    JoinThread(mCaller);
    ReleaseAndSettle(mRelease, cModule);
    mRelease.Free;
  end;
end;

procedure TAtlasTimeLimitTests.HangingProviderCountsForItsPackage;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mHanging: IAtlasCompletionProvider;
  mSink: TSink;
  mSinkRef: IAtlasCompletionSink;
  mModule: HMODULE;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mHanging := TBrokenProvider.Create('Hängt', cHangMs);
  // Das Testprogramm spielt das Modul-Package der Quelle.
  mModule := TAtlasMainThread.CodeModuleOf(mHanging);
  Assert.AreEqual<HMODULE>(HInstance, mModule, 'Package mit dem Code der Quelle');
  mProviders.Add(mHanging);
  mSink := TSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000), 'Complete trotz hängender Quelle');
  Assert.AreEqual(1, TAtlasTimeLimit.ReleaseModule(mModule), 'Abmelden des Moduls übergibt den Arbeiter');
  // Die Quelle hört auf das Abbruchsignal.
  TAtlasShutdown.Signal;
  Assert.IsTrue(TAtlasOverdueThreads.SettleBeforeUnload(mModule, 2000));
  Assert.AreEqual(0, TAtlasOverdueThreads.Pending(mModule));
end;

procedure TAtlasTimeLimitTests.StaleQueryAfterPrepareFetchesNothing;
var
  mStale: TCancelInPrepareProvider;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
begin
  mStale := TCancelInPrepareProvider.Create;
  mProvider := mStale;
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(1000), 'die Senke schließt trotzdem ab');
  mStale.Shutdown;
  Assert.AreEqual(0, mStale.Fetches, 'eine nach Prepare überholte Anfrage fragt nicht mehr an');
end;

procedure TAtlasTimeLimitTests.PrepareRunsInWorkerThread;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mRecording: TThreadRecordingProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
begin
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mRecording := TThreadRecordingProvider.Create;
  mProviders.Add(mRecording);
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000));
  Assert.AreNotEqual<TThreadID>(0, mRecording.PrepareThread, 'Prepare lief');
  Assert.AreNotEqual<TThreadID>(MainThreadID, mRecording.PrepareThread,
    'Prepare läuft im Zeitlimit-Arbeiter: weder VCL noch Open Tools API, kein Serverstart');
end;

procedure TAtlasTimeLimitTests.ServerSessionFuncRunsInWorker;
var
  mProviders: TAtlasCompletionProviders;
  mProvider: IAtlasCompletionProvider;
  mSink: TCollectingSink;
  mSinkRef: IAtlasCompletionSink;
  mSessionThread: TThreadID;
begin
  mSessionThread := 0;
  mProviders := TAtlasCompletionProviders.Create;
  mProvider := mProviders;
  mProviders.Add(TAtlasServerCompletionProvider.Create(
    function: TLspSession
    begin
      mSessionThread := TThread.CurrentThread.ThreadID;
      Result := nil;
    end));
  mSink := TCollectingSink.Create;
  mSinkRef := mSink;
  mProvider.Query(Context, mSinkRef);
  Assert.IsTrue(mSink.WaitDone(3000));
  Assert.AreNotEqual<TThreadID>(0, mSessionThread, 'Sitzungsfunktion gerufen');
  Assert.AreNotEqual<TThreadID>(MainThreadID, mSessionThread,
    'Die Sitzungsfunktion läuft im Zeitlimit-Arbeiter und darf keinen Server starten');
end;

procedure TAtlasTimeLimitTests.SignatureSyncsInCallingThread;
var
  mSignatures: TAtlasServerSignatureProvider;
  mSessionThread: TThreadID;
begin
  mSessionThread := 0;
  mSignatures := TAtlasServerSignatureProvider.Create(
    function: TLspSession
    begin
      mSessionThread := TThread.CurrentThread.ThreadID;
      Result := nil;
    end);
  try
    Assert.IsFalse(mSignatures.Query('C:\Projekt\Unit1.pas', 'unit Unit1;', 0, 0,
      procedure(const AHelp: TAtlasSignatureHelp)
      begin
      end), 'ohne Sitzung keine Anfrage');
    Assert.AreEqual<TThreadID>(TThread.CurrentThread.ThreadID, mSessionThread,
      'Sitzung und Abgleich im aufrufenden Thread: Sync wartet nicht auf den Server, kein Zeitlimit-Arbeiter');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
    mSignatures.Shutdown;
  finally
    mSignatures.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimeLimitTests);

end.
