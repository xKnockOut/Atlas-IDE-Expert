unit Atlas.Core.Diagnostics.ModuleHost.Tests;

// Tests zu TAtlasModuleHost (#1455): Beschreibung eines Moduls, Zulassung und die
// gemeinsame Abmeldung mit ihrer Reihenfolge (stoppen und Anmeldungen lösen,
// dann die Schritte des Moduls, zuletzt überfällige Threads des Packages).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModuleHostTests = class
  public
    [Test]
    procedure InfoCarriesAllFields;
    [Test]
    procedure AdmitOnlyWithMatchingContract;
    [Test]
    procedure AdmitNotTwiceNorWithoutBase;
    [Test]
    procedure UnregisterStopsBeforeRelease;
    [Test]
    procedure UnregisterWithoutScopeDoesNothing;
    [Test]
    procedure UnregisterWithoutRegistryStillReleases;
    [Test]
    procedure UnregisterLogsFailures;
    /// <summary>Auch ohne Scope: Läuft im Package des Moduls noch ein überfälliger Thread, hält die Abmeldung das
    /// Package fest, bevor es entladen wird (Code-Review T-103).</summary>
    [Test]
    procedure UnregisterPinsPackageWithOverdueThread;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.SyncObjs,
  Atlas.Core.Diagnostics.UnloadSafety,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Diagnostics.ModuleHost;

type
  TLog = class
  public
    Text: string;
    procedure Add(AEntry: string);
  end;

  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FLog: TLog;
    FActive: Boolean;
    FFailStop: Boolean;
  public
    constructor Create(ALog: TLog; AFailStop: Boolean);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

const
  cId = 'test.host';
  /// <summary>Erfundenes Package: Der Test entlädt nichts und hält nichts im Speicher fest.</summary>
  cInstance = $5A5B0000;

procedure TLog.Add(AEntry: string);
begin
  if Text <> '' then
  begin
    Text := Text + ',';
  end;
  Text := Text + AEntry;
end;

constructor TFakeModule.Create(ALog: TLog; AFailStop: Boolean);
begin
  inherited Create;
  FLog := ALog;
  FFailStop := AFailStop;
end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := TAtlasModuleHost.Info(cId, 'Test', '1.0', 0, TAtlasSafeLevel.Normal, '');
end;

procedure TFakeModule.Start;
begin
  FActive := True;
end;

procedure TFakeModule.Stop;
begin
  FActive := False;
  FLog.Add('stop');
  if FFailStop then
  begin
    raise EInvalidOp.Create('Stop gescheitert');
  end;
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := FActive;
end;

/// <summary>Rückruf, der AName in ALog schreibt.</summary>
function Logged(ALog: TLog; const AName: string): TProc;
begin
  Result :=
    procedure
    begin
      ALog.Add(AName);
    end;
end;

/// <summary>Protokoll des Abbaus in ALog, mit Vorsilbe „log:“.</summary>
function LogSink(ALog: TLog): TProc<string>;
begin
  Result :=
    procedure(AText: string)
    begin
      ALog.Add('log:' + AText);
    end;
end;

/// <summary>Registriert ein aktives Testmodul in ARegistry und liefert seinen Scope.</summary>
function RegisterActive(const ARegistry: IAtlasModuleRegistry; ALog: TLog; AFailStop: Boolean): IAtlasModuleScope;
var
  mModule: IAtlasModule;
begin
  mModule := TFakeModule.Create(ALog, AFailStop);
  mModule.Start;
  Result := ARegistry.RegisterModule(mModule);
end;

{ TModuleHostTests }

procedure TModuleHostTests.InfoCarriesAllFields;
var
  mInfo: TAtlasModuleInfo;
begin
  mInfo := TAtlasModuleHost.Info('a.b', 'Name', '2.1.0', 42, TAtlasSafeLevel.Safe, 'schalter');
  Assert.AreEqual('a.b', mInfo.Id);
  Assert.AreEqual('Name', mInfo.Name);
  Assert.AreEqual('2.1.0', mInfo.Version);
  Assert.AreEqual(UInt64(42), UInt64(mInfo.Handle));
  Assert.AreEqual<TAtlasSafeLevel>(TAtlasSafeLevel.Safe, mInfo.MinLevel);
  Assert.AreEqual('schalter', mInfo.Switch);
end;

procedure TModuleHostTests.AdmitOnlyWithMatchingContract;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    Assert.IsTrue(TAtlasModuleHost.AdmitTo(mRegistry, cId, ccMatch, nil, LogSink(mLog)));
    Assert.AreEqual('', mLog.Text);
    Assert.IsFalse(TAtlasModuleHost.AdmitTo(mRegistry, cId, ccMismatch, nil, LogSink(mLog)));
    Assert.AreEqual('log:Module ' + cId + ': contract version of Base does not match, not registered', mLog.Text);
    mLog.Text := '';
    Assert.IsFalse(TAtlasModuleHost.AdmitTo(mRegistry, cId, ccMissing, nil, LogSink(mLog)));
    Assert.AreNotEqual('', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.AdmitNotTwiceNorWithoutBase;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    // Regel 5: Ohne Registry ist Base abgebaut; das Modul meldet sich nicht an und protokolliert nichts.
    Assert.IsFalse(TAtlasModuleHost.AdmitTo(nil, cId, ccMatch, nil, LogSink(mLog)));
    mScope := RegisterActive(mRegistry, mLog, False);
    Assert.IsFalse(TAtlasModuleHost.AdmitTo(mRegistry, cId, ccMatch, mScope, LogSink(mLog)));
    Assert.AreEqual('', mLog.Text);
    TAtlasModuleHost.UnregisterFrom(mRegistry, mScope, cId, 0, nil, LogSink(mLog));
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.UnregisterStopsBeforeRelease;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mModule: IAtlasModule;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := RegisterActive(mRegistry, mLog, False);
    TAtlasModuleHost.UnregisterFrom(mRegistry, mScope, cId, 0, Logged(mLog, 'release'), LogSink(mLog));
    Assert.IsNull(mScope);
    Assert.AreEqual('stop,release', mLog.Text);
    Assert.IsFalse(mRegistry.FindModule(cId, mModule));
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.UnregisterWithoutScopeDoesNothing;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mModule: IAtlasModule;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    RegisterActive(mRegistry, mLog, False);
    mScope := nil;
    TAtlasModuleHost.UnregisterFrom(mRegistry, mScope, cId, 0, Logged(mLog, 'release'), LogSink(mLog));
    Assert.AreEqual('', mLog.Text);
    Assert.IsTrue(mRegistry.FindModule(cId, mModule));
    mModule := nil;
    mRegistry.UnregisterModule(cId);
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.UnregisterWithoutRegistryStillReleases;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := RegisterActive(mRegistry, mLog, False);
    // Regel 5: Base hat das Modul schon abgemeldet und die Registry abgebaut.
    mRegistry.UnregisterModule(cId);
    mLog.Text := '';
    TAtlasModuleHost.UnregisterFrom(nil, mScope, cId, 0, Logged(mLog, 'release'), LogSink(mLog));
    Assert.IsNull(mScope);
    Assert.AreEqual('release', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.UnregisterLogsFailures;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := RegisterActive(mRegistry, mLog, True);
    TAtlasModuleHost.UnregisterFrom(mRegistry, mScope, cId, 0, nil, LogSink(mLog));
    Assert.StartsWith('stop,log:Module ' + cId + ' not unregistered cleanly: ', mLog.Text);
    Assert.Contains(mLog.Text, 'Stop gescheitert');
  finally
    mLog.Free;
  end;
end;

procedure TModuleHostTests.UnregisterPinsPackageWithOverdueThread;
var
  mRelease: TEvent;
  mPinned: TArray<HMODULE>;
  mSlot: TAtlasWorkerSlot;
  mScope: IAtlasModuleScope;
  mLog: TLog;
begin
  mPinned := nil;
  mScope := nil;
  mLog := TLog.Create;
  mRelease := TEvent.Create(nil, True, False, '');
  mSlot := TAtlasWorkerSlot.Create(cInstance);
  try
    TAtlasUnloadSafety.ResetForTests(
      procedure(AModule: HMODULE)
      begin
        mPinned := mPinned + [AModule];
      end);
    mSlot.Start(TThread.CreateAnonymousThread(
      procedure
      begin
        mRelease.WaitFor(10000);
      end));
    mSlot.Stop(20);
    TAtlasModuleHost.UnregisterFrom(nil, mScope, cId, cInstance, Logged(mLog, 'release'), LogSink(mLog));
    Assert.AreEqual('', mLog.Text, 'Ohne Scope keine Schritte 1 bis 3');
    Assert.IsFalse(TAtlasUnloadSafety.IsSafe(cInstance));
    Assert.AreEqual(1, Integer(Length(mPinned)));
  finally
    mRelease.SetEvent;
    TAtlasOverdueThreads.Settle(cInstance, 2000);
    TAtlasUnloadSafety.ResetForTests(nil);
    mSlot.Free;
    mRelease.Free;
    mLog.Free;
    mPinned := nil;
  end;
end;

end.
