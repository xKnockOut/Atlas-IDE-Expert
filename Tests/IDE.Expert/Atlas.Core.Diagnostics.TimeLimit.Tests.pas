unit Atlas.Core.Diagnostics.TimeLimit.Tests;

// Absturzsicherheit (#493): Zeitlimit für Quellen, gemeinsames Abbruchsignal
// und Sicherung je Quelle in der zusammengeführten Vervollständigung. Eine
// Zeitüberschreitung ist kein Fehler und schaltet keine Quelle ab.

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
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Diagnostics.TimeLimit,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Composite,
  Atlas.Core.Completion.Internals.Async,
  Atlas.Core.Completion.Providers.Fixed,
  Atlas.Core.Completion.Providers.Server,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.Providers.Server,
  Atlas.Core.Lsp.Session;

type
  TSink = class(TInterfacedObject, IAtlasCompletionSink)
  private
    FLock: TCriticalSection;
    FNames: TList<string>;
    FDone: TEvent;
  public
    constructor Create;
    destructor Destroy; override;
    procedure AddItems(const AItems: TAtlasCompletionItems);
    procedure MarkIncomplete;
    procedure Complete;
    function WaitDone(ATimeoutMs: Cardinal): Boolean;
    function Names: string;
  end;

  /// <summary>Quelle, die beim Aufruf wirft bzw. hängt (wie ein kaputter SQL-Provider).</summary>
  TBrokenProvider = class(TInterfacedObject, IAtlasCompletionProvider, IAtlasNamedProvider)
  private
    FName: string;
    FHangMs: Cardinal;
  public
    Calls: Integer;
    constructor Create(const AName: string; AHangMs: Cardinal = 0);
    procedure Query(const AContext: TAtlasContext; const ASink: IAtlasCompletionSink);
    procedure Cancel;
    function ProviderName: string;
  end;

  /// <summary>Quelle, deren Fetch im Hintergrund wirft.</summary>
  TFailingFetchProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
  end;

  /// <summary>Wie eine Zeitüberschreitung in Composite: Cancel kommt, während Prepare noch läuft (A-13).</summary>
  TCancelInPrepareProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
  public
    Fetches: Integer;
  end;

  /// <summary>Merkt sich, in welchem Thread Prepare läuft (A-01, K-03).</summary>
  TThreadRecordingProvider = class(TAtlasAsyncCompletionProvider)
  protected
    function Prepare(const AContext: TAtlasContext; out AData: TObject): Boolean; override;
    function Fetch(const AContext: TAtlasContext; AData: TObject; const ACancelled: TAtlasCancelledFunc;
      const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems; override;
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
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems;
begin
  AIncomplete := False;
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
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems;
begin
  AIncomplete := False;
  Result := nil;
end;

{ TSink }

constructor TSink.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
  FNames := TList<string>.Create;
  FDone := TEvent.Create(nil, True, False, '');
end;

destructor TSink.Destroy;
begin
  FDone.Free;
  FNames.Free;
  FLock.Free;
  inherited;
end;

procedure TSink.AddItems(const AItems: TAtlasCompletionItems);
var
  Item: TAtlasCompletionItem;
begin
  FLock.Enter;
  try
    for Item in AItems do
      FNames.Add(Item.Name);
  finally
    FLock.Leave;
  end;
end;

procedure TSink.MarkIncomplete;
begin
end;

procedure TSink.Complete;
begin
  FDone.SetEvent;
end;

function TSink.WaitDone(ATimeoutMs: Cardinal): Boolean;
begin
  Result := FDone.WaitFor(ATimeoutMs) = wrSignaled;
end;

function TSink.Names: string;
begin
  FLock.Enter;
  try
    Result := string.Join(',', FNames.ToArray);
  finally
    FLock.Leave;
  end;
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
    raise EInvalidOpException.Create('SQL-Provider kaputt');
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
  const ACancelled: TAtlasCancelledFunc; const AEmit: TAtlasEmitProc; out AIncomplete: Boolean): TAtlasCompletionItems;
begin
  AIncomplete := False;
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
  TAtlasTimeLimit.LimitMs := TAtlasTimeLimit.DefaultMs;
end;

procedure TAtlasTimeLimitTests.TearDown;
begin
  TAtlasShutdown.Reset;
  TAtlasGuard.Fuse.ResetAll;
  TAtlasGuard.OnWarning := nil;
  TAtlasGuard.RotatingLog.Folder := FOldFolder;
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
  FFolder := '';
  FOldFolder := '';
end;

procedure TAtlasTimeLimitTests.RunsAndReportsErrors;
var
  Error: string;
  Ran: Boolean;
begin
  Ran := False;
  Assert.IsTrue(TAtlasTimeLimit.Run(
    procedure
    begin
      Ran := True;
    end, Error) = TAtlasTimedOutcome.Done);
  Assert.IsTrue(Ran);
  Assert.AreEqual('', Error);
  Assert.IsTrue(TAtlasTimeLimit.Run(
    procedure
    begin
      raise EInvalidOpException.Create('kaputt');
    end, Error) = TAtlasTimedOutcome.Failed);
  Assert.AreEqual('EInvalidOpException: kaputt', Error);
end;

procedure TAtlasTimeLimitTests.HangingCallReturnsAfterLimit;
var
  Watch: TStopwatch;
  Error: string;
  Release: TEvent;
begin
  Release := TEvent.Create(nil, True, False, '');
  try
    Watch := TStopwatch.StartNew;
    Assert.IsTrue(TAtlasTimeLimit.Run(
      procedure
      begin
        Release.WaitFor(5000);
      end, Error, 200) = TAtlasTimedOutcome.TimedOut);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 450, Format('blockiert %d ms', [Watch.ElapsedMilliseconds]));
    // Der nächste Aufruf bekommt einen anderen Arbeiter und läuft sofort.
    Assert.IsTrue(TAtlasTimeLimit.Run(
      procedure
      begin
      end, Error) = TAtlasTimedOutcome.Done);
    Release.SetEvent;
  finally
    // Erst freigeben, wenn der hängende Arbeiter zurück ist.
    Sleep(50);
    Release.Free;
  end;
end;

procedure TAtlasTimeLimitTests.ShutdownEndsWaitsAndWorkers;
var
  Watch: TStopwatch;
  Event: TEvent;
  Error: string;
begin
  Event := TEvent.Create(nil, True, False, '');
  try
    Assert.IsTrue(TAtlasShutdown.WaitFor(Event, 30) = wrTimeout);
    Event.SetEvent;
    Assert.IsTrue(TAtlasShutdown.WaitFor(Event, 30) = wrSignaled);
    Event.ResetEvent;
    // Ein Arbeiter hängt in einer Quelle, die auf das Signal hört.
    Assert.IsTrue(TAtlasTimeLimit.Run(
      procedure
      begin
        TAtlasShutdown.Wait(10000);
      end, Error, 50) = TAtlasTimedOutcome.TimedOut);
    TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(50);
        TAtlasShutdown.Signal;
      end).Start;
    Watch := TStopwatch.StartNew;
    Assert.IsTrue(TAtlasShutdown.WaitFor(Event, 10000) = wrAbandoned);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 500);
    Watch := TStopwatch.StartNew;
    Assert.IsTrue(TAtlasTimeLimit.StopAll(TAtlasShutdown.StopMs), 'alle Arbeiter beendet');
    Assert.IsTrue(Watch.ElapsedMilliseconds < TAtlasShutdown.StopMs);
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
    Assert.IsTrue(TAtlasTimeLimit.Run(
      procedure
      begin
      end, Error) = TAtlasTimedOutcome.Failed, 'nach dem Signal startet nichts mehr');
  finally
    Event.Free;
  end;
  TAtlasShutdown.Reset;
  Assert.IsTrue(TAtlasTimeLimit.Run(
    procedure
    begin
    end, Error) = TAtlasTimedOutcome.Done, 'nach Reset wieder bereit');
end;

procedure TAtlasTimeLimitTests.ClientRequestEndsOnShutdown;
var
  Client: TLspClient;
  Watch: TStopwatch;
begin
  Client := TLspClient.Create(
    procedure(const ABytes: TBytes)
    begin
    end);
  try
    TThread.CreateAnonymousThread(
      procedure
      begin
        Sleep(50);
        TAtlasShutdown.Signal;
      end).Start;
    Watch := TStopwatch.StartNew;
    Assert.WillRaise(
      procedure
      begin
        Client.Request('textDocument/hover', nil, 10000).Free;
      end, ELspClientError);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 500, Format('wartete %d ms', [Watch.ElapsedMilliseconds]));
  finally
    Client.Free;
  end;
end;

procedure TAtlasTimeLimitTests.FailingProviderTripsOnlyItself;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Broken: TBrokenProvider;
  BrokenRef: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
  Index: Integer;
  Warning: string;
begin
  TAtlasGuard.OnWarning :=
    procedure(const AText: string)
    begin
      Warning := AText;
    end;
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Broken := TBrokenProvider.Create('SQL');
  BrokenRef := Broken;
  Providers.Add(BrokenRef);
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Alpha')]));
  for Index := 1 to 3 do
  begin
    Sink := TSink.Create;
    SinkRef := Sink;
    Provider.Query(Context, SinkRef);
    Assert.IsTrue(Sink.WaitDone(3000), 'Complete trotz kaputter Quelle');
    Assert.AreEqual('Alpha', Sink.Names, 'die übrigen Quellen liefern weiter');
  end;
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('SQL'), 'nach dem dritten Fehler abgeschaltet');
  Assert.Contains(Warning, 'SQL');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Vervollständigung (fest)'));
  Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Completion), 'nur die Quelle, nicht die Vervollständigung');
  Sink := TSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000));
  Assert.AreEqual('Alpha', Sink.Names);
  Assert.AreEqual(3, Broken.Calls, 'abgeschaltete Quelle wird nicht mehr gefragt');
  TAtlasGuard.EnableProvider('SQL');
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('SQL'));
end;

procedure TAtlasTimeLimitTests.HangingProviderBlocksAtMostLimit;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
  Watch: TStopwatch;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TBrokenProvider.Create('Hängt', 5000));
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Beta')]));
  Sink := TSink.Create;
  SinkRef := Sink;
  Watch := TStopwatch.StartNew;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Watch.ElapsedMilliseconds < 450, Format('Query blockierte %d ms', [Watch.ElapsedMilliseconds]));
  Assert.IsTrue(Sink.WaitDone(3000));
  Assert.AreEqual('Beta', Sink.Names);
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8),
    'Quelle Hängt langsam: keine Antwort innerhalb von 200 ms; zählt nicht als Fehler');
  // Hängenden Arbeiter freigeben.
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.StopAll;
end;

procedure TAtlasTimeLimitTests.SlowProviderNeverTripsAndRunsOnce;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Slow: TBrokenProvider;
  SlowRef: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
  Watch: TStopwatch;
  Index: Integer;
  Text: string;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Slow := TBrokenProvider.Create('Langsam', 5000);
  SlowRef := Slow;
  Providers.Add(SlowRef);
  Providers.Add(TAtlasFixedCompletionProvider.Create([Item('Gamma')]));
  for Index := 1 to 4 do
  begin
    Sink := TSink.Create;
    SinkRef := Sink;
    Watch := TStopwatch.StartNew;
    Provider.Query(Context, SinkRef);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 450, Format('Query blockierte %d ms', [Watch.ElapsedMilliseconds]));
    Assert.IsTrue(Sink.WaitDone(3000));
    Assert.AreEqual('Gamma', Sink.Names, 'die übrigen Quellen liefern weiter');
  end;
  Assert.IsFalse(TAtlasGuard.ProviderDisabled('Langsam'), 'langsam ist kein Fehler');
  Assert.AreEqual(1, Slow.Calls, 'solange der erste Aufruf läuft, kein weiterer Arbeiter');
  Text := TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8);
  Assert.Contains(Text, 'Quelle Langsam langsam: keine Antwort innerhalb von 200 ms; zählt nicht als Fehler');
  Assert.AreEqual(1, Integer(Length(Text.Trim.Split([sLineBreak]))), 'eine Zeile je Quelle und Minute');
  Assert.IsFalse(Text.Contains('Fehler in Quelle'), 'keine Fehlerzeile');
  // Hängenden Arbeiter freigeben; danach fragt die Quelle wieder.
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.WaitIdle(2000);
  TAtlasShutdown.Reset;
  Sink := TSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000));
  Assert.AreEqual(2, Slow.Calls, 'nach seiner Rückkehr läuft die Quelle wieder');
  TAtlasShutdown.Signal;
  TAtlasTimeLimit.StopAll;
end;

procedure TAtlasTimeLimitTests.FetchErrorsCountPerProvider;
var
  Failing: TFailingFetchProvider;
  Provider: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
  Index: Integer;
begin
  Failing := TFailingFetchProvider.Create;
  Failing.Name := 'Kaputt';
  Provider := Failing;
  for Index := 1 to 3 do
  begin
    Sink := TSink.Create;
    SinkRef := Sink;
    Provider.Query(Context, SinkRef);
    Assert.IsTrue(Sink.WaitDone(3000), 'leeres Ergebnis statt Exception');
  end;
  Failing.Shutdown;
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('Kaputt'));
  Assert.IsTrue(TAtlasGuard.ProviderDisabled('kaputt'), 'Name ohne Groß-/Kleinschreibung');
end;

procedure TAtlasTimeLimitTests.WaitIdleWaitsForAbandonedWorker;
var
  Error: string;
  Release: TEvent;
begin
  Release := TEvent.Create(nil, True, False, '');
  try
    Assert.IsTrue(TAtlasTimeLimit.Run(
      procedure
      begin
        Release.WaitFor(5000);
      end, Error, 50) = TAtlasTimedOutcome.TimedOut);
    Assert.IsFalse(TAtlasTimeLimit.WaitIdle(30), 'der aufgegebene Arbeiter läuft noch');
    Release.SetEvent;
    Assert.IsTrue(TAtlasTimeLimit.WaitIdle(2000), 'nach seiner Rückkehr frei');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
  finally
    Release.SetEvent;
    TAtlasTimeLimit.WaitIdle(2000);
    Release.Free;
  end;
end;

procedure TAtlasTimeLimitTests.StaleQueryAfterPrepareFetchesNothing;
var
  Stale: TCancelInPrepareProvider;
  Provider: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
begin
  Stale := TCancelInPrepareProvider.Create;
  Provider := Stale;
  Sink := TSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(1000), 'die Senke schließt trotzdem ab');
  Stale.Shutdown;
  Assert.AreEqual(0, Stale.Fetches, 'eine nach Prepare überholte Anfrage fragt nicht mehr an (A-13)');
end;

procedure TAtlasTimeLimitTests.PrepareRunsInWorkerThread;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Recording: TThreadRecordingProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
begin
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Recording := TThreadRecordingProvider.Create;
  Providers.Add(Recording);
  Sink := TSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000));
  Assert.IsTrue(Recording.PrepareThread <> 0, 'Prepare lief');
  Assert.IsTrue(Recording.PrepareThread <> MainThreadID,
    'Prepare läuft im Zeitlimit-Arbeiter: weder VCL noch Open Tools API, kein Serverstart (A-01, K-03)');
end;

procedure TAtlasTimeLimitTests.ServerSessionFuncRunsInWorker;
var
  Providers: TAtlasCompletionProviders;
  Provider: IAtlasCompletionProvider;
  Sink: TSink;
  SinkRef: IAtlasCompletionSink;
  SessionThread: TThreadID;
begin
  SessionThread := 0;
  Providers := TAtlasCompletionProviders.Create;
  Provider := Providers;
  Providers.Add(TAtlasServerCompletionProvider.Create(
    function: TLspSession
    begin
      SessionThread := TThread.CurrentThread.ThreadID;
      Result := nil;
    end));
  Sink := TSink.Create;
  SinkRef := Sink;
  Provider.Query(Context, SinkRef);
  Assert.IsTrue(Sink.WaitDone(3000));
  Assert.IsTrue(SessionThread <> 0, 'Sitzungsfunktion gerufen');
  Assert.IsTrue(SessionThread <> MainThreadID,
    'Die Sitzungsfunktion läuft im Zeitlimit-Arbeiter und darf keinen Server starten (A-01)');
end;

procedure TAtlasTimeLimitTests.SignatureSyncsInCallingThread;
var
  Signatures: TAtlasServerSignatureProvider;
  SessionThread: TThreadID;
begin
  SessionThread := 0;
  Signatures := TAtlasServerSignatureProvider.Create(
    function: TLspSession
    begin
      SessionThread := TThread.CurrentThread.ThreadID;
      Result := nil;
    end);
  try
    Assert.IsFalse(Signatures.Query('C:\Projekt\Unit1.pas', 'unit Unit1;', 0, 0,
      procedure(const AHelp: TAtlasSignatureHelp)
      begin
      end), 'ohne Sitzung keine Anfrage');
    Assert.IsTrue(SessionThread = TThread.CurrentThread.ThreadID,
      'Sitzung und Abgleich im aufrufenden Thread: Sync wartet nicht auf den Server, kein Zeitlimit-Arbeiter');
    Assert.AreEqual(0, TAtlasTimeLimit.BusyCount);
    Signatures.Shutdown;
  finally
    Signatures.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimeLimitTests);

end.
