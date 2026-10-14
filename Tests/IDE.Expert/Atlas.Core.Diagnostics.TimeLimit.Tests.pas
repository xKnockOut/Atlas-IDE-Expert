unit Atlas.Core.Diagnostics.TimeLimit.Tests;

// Absturzsicherheit (#493): Zeitlimit für Quellen, gemeinsames Abbruchsignal
// und Sicherung je Quelle in der zusammengeführten Vervollständigung.

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
    [Test]
    procedure FetchErrorsCountPerProvider;
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
  Atlas.Core.Completion.Providers.Fixed;

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
  Assert.Contains(TFile.ReadAllText(TPath.Combine(FFolder, 'atlas.log'), TEncoding.UTF8), 'Zeitlimit von 200 ms');
  // Hängenden Arbeiter freigeben.
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasTimeLimitTests);

end.
