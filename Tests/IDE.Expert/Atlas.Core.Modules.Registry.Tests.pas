unit Atlas.Core.Modules.Registry.Tests;

// Modul-Registry von Base (#1455, ADR 0017 Regeln 1–5, 8, 9): Anmelden,
// Abmelden rückwärts über den Scope, Objekte nach GUID, Änderungsmeldung,
// Liste bekannter Module samt Ablage.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModuleRegistryTests = class
  public
    [Test]
    procedure RegisterListsModuleAndOpensScope;
    [Test]
    procedure RejectsEmptyAndDuplicateId;
    [Test]
    procedure UnregisterStopsThenRevokesInReverse;
    [Test]
    procedure UnregisterSkipsStopWhenInactive;
    [Test]
    procedure UnregisterContinuesAfterFailure;
    [Test]
    procedure ProvideAndFindAllByInterface;
    [Test]
    procedure ProvideRejectsObjectWithoutInterface;
    [Test]
    procedure UnregisterWithdrawsProvidedObjects;
    [Test]
    procedure OwnAfterCloseRevokesAtOnce;
    [Test]
    procedure ProvideAfterCloseRaises;
    [Test]
    procedure ListenerSeesEveryChange;
    [Test]
    procedure RevokedListenerIsNotCalledAnyMore;
    [Test]
    procedure FailingListenerDoesNotStopOthers;
    [Test]
    procedure ModuleListenerEndsWithModule;
    [Test]
    procedure KnownKeepsMissingModule;
    [Test]
    procedure KnownTakesNewNameAndVersion;
    [Test]
    procedure ForgetOnlyMissingModule;
    [Test]
    procedure UseStorageMergesAndSavesKnown;
    [Test]
    procedure KnownTextRoundTrip;
    [Test]
    procedure KnownTextSkipsBrokenLines;
    [Test]
    procedure IsModuleHandleOnlyForRegistered;
    [Test]
    procedure UnregisterDropsQueuedEntriesOfModule;
    [Test]
    procedure ShutDownUnregistersAllInReverse;
    [Test]
    procedure RegistrationSurvivesRegistry;
    [Test]
    procedure GlobalRegistryExists;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Parts;

type
  IProbeService = interface
    ['{75D390ED-2E88-4CF1-B470-EFBDDE9BBE2B}']
    function Name: string;
  end;

  IOtherService = interface
    ['{25FAB976-3061-4CA3-9167-A65BF64A2A38}']
    function Number: Integer;
  end;

  /// <summary>Gemeinsames Protokoll der Probeobjekte eines Tests.</summary>
  TLog = class
  public
    Text: string;
    procedure Add(const AEntry: string);
  end;

  TProbeService = class(TInterfacedObject, IProbeService)
  private
    FName: string;
  public
    constructor Create(const AName: string);
    function Name: string;
  end;

  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FLog: TLog;
    FInfo: TAtlasModuleInfo;
    FActive: Boolean;
    FFailStop: Boolean;
  public
    constructor Create(ALog: TLog; const AId: string); overload;
    constructor Create(ALog: TLog; const AId, AName, AVersion: string; AHandle: NativeUInt); overload;
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    property FailStop: Boolean read FFailStop write FFailStop;
  end;

  /// <summary>Anmeldung, die ihr Lösen protokolliert; FailRevoke wirft dabei.</summary>
  TLoggedRegistration = class(TInterfacedObject, IAtlasRegistration)
  private
    FLog: TLog;
    FName: string;
    FRevoked: Boolean;
    FFailRevoke: Boolean;
  public
    constructor Create(ALog: TLog; const AName: string);
    procedure Revoke;
    function IsRevoked: Boolean;
    property FailRevoke: Boolean read FFailRevoke write FFailRevoke;
  end;

  TLogListener = class(TInterfacedObject, IAtlasRegistryListener)
  private
    FLog: TLog;
    FName: string;
    FFail: Boolean;
    FRevokeOnCall: IAtlasRegistration;
  public
    constructor Create(ALog: TLog; const AName: string);
    procedure RegistryChanged(const AChange: TAtlasRegistryChange);
    property Fail: Boolean read FFail write FFail;
    /// <summary>Beim ersten Aufruf diese Anmeldung lösen (Hörer, der einen anderen abmeldet).</summary>
    property RevokeOnCall: IAtlasRegistration read FRevokeOnCall write FRevokeOnCall;
  end;

const
  cKindNames: array[TAtlasRegistryChangeKind] of string = ('added', 'removed', 'provided', 'revoked', 'known');

{ TLog }

procedure TLog.Add(const AEntry: string);
begin
  if Text <> '' then
  begin
    Text := Text + ' ';
  end;
  Text := Text + AEntry;
end;

{ TProbeService }

constructor TProbeService.Create(const AName: string);
begin
  inherited Create;
  FName := AName;
end;

function TProbeService.Name: string;
begin
  Result := FName;
end;

{ TFakeModule }

constructor TFakeModule.Create(ALog: TLog; const AId: string);
begin
  Create(ALog, AId, 'Modul ' + AId, '2.0.0', 0);
end;

constructor TFakeModule.Create(ALog: TLog; const AId, AName, AVersion: string; AHandle: NativeUInt);
begin
  inherited Create;
  FLog := ALog;
  FInfo.Id := AId;
  FInfo.Name := AName;
  FInfo.Version := AVersion;
  FInfo.Handle := AHandle;
end;

function TFakeModule.Info: TAtlasModuleInfo;
begin
  Result := FInfo;
end;

procedure TFakeModule.Start;
begin
  FActive := True;
  FLog.Add('start:' + FInfo.Id);
end;

procedure TFakeModule.Stop;
begin
  FLog.Add('stop:' + FInfo.Id);
  if FFailStop then
  begin
    raise EInvalidOp.Create('Stop gescheitert');
  end;
  FActive := False;
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := FActive;
end;

{ TLoggedRegistration }

constructor TLoggedRegistration.Create(ALog: TLog; const AName: string);
begin
  inherited Create;
  FLog := ALog;
  FName := AName;
end;

procedure TLoggedRegistration.Revoke;
begin
  if FRevoked then
  begin
    Exit;
  end;
  FRevoked := True;
  FLog.Add('revoke:' + FName);
  if FFailRevoke then
  begin
    raise EInvalidOp.Create('Lösen gescheitert');
  end;
end;

function TLoggedRegistration.IsRevoked: Boolean;
begin
  Result := FRevoked;
end;

{ TLogListener }

constructor TLogListener.Create(ALog: TLog; const AName: string);
begin
  inherited Create;
  FLog := ALog;
  FName := AName;
end;

procedure TLogListener.RegistryChanged(const AChange: TAtlasRegistryChange);
begin
  FLog.Add(FName + ':' + cKindNames[AChange.Kind] + ':' + AChange.ModuleId);
  if FRevokeOnCall <> nil then
  begin
    FRevokeOnCall.Revoke;
    FRevokeOnCall := nil;
  end;
  if FFail then
  begin
    raise EInvalidOp.Create('Hörer gescheitert');
  end;
end;

{ TModuleRegistryTests }

procedure TModuleRegistryTests.RegisterListsModuleAndOpensScope;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mFound: IAtlasModule;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    Assert.IsTrue(mScope.IsOpen);
    Assert.AreEqual('atlas.a', mScope.ModuleId);
    Assert.AreEqual(1, Integer(Length(mRegistry.Modules)));
    Assert.IsTrue(mRegistry.FindModule('atlas.a', mFound));
    Assert.AreEqual('atlas.a', mFound.Info.Id);
    Assert.IsFalse(mRegistry.FindModule('atlas.b', mFound));
    // Anmelden startet nichts (Regel 1).
    Assert.AreEqual('', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.RejectsEmptyAndDuplicateId;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mEmpty: Boolean;
  mDuplicate: Boolean;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mEmpty := False;
    try
      mRegistry.RegisterModule(TFakeModule.Create(mLog, '  ') as IAtlasModule);
    except
      on EAtlasModuleRegistry do
        mEmpty := True;
    end;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mDuplicate := False;
    try
      mRegistry.RegisterModule(TFakeModule.Create(mLog, 'ATLAS.A') as IAtlasModule);
    except
      on EAtlasModuleRegistry do
        mDuplicate := True;
    end;
    Assert.IsTrue(mEmpty, 'leere Id');
    Assert.IsTrue(mDuplicate, 'doppelte Id');
    Assert.AreEqual(1, Integer(Length(mRegistry.Modules)));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.UnregisterStopsThenRevokesInReverse;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mModule: IAtlasModule;
  mScope: IAtlasModuleScope;
  mFailures: TArray<string>;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mModule := TFakeModule.Create(mLog, 'atlas.a');
    mScope := mRegistry.RegisterModule(mModule);
    mScope.Own(TLoggedRegistration.Create(mLog, '1') as IAtlasRegistration);
    mScope.Own(TLoggedRegistration.Create(mLog, '2') as IAtlasRegistration);
    mScope.Own(TLoggedRegistration.Create(mLog, '3') as IAtlasRegistration);
    mModule.Start;
    mFailures := mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual(0, Integer(Length(mFailures)));
    Assert.AreEqual('start:atlas.a stop:atlas.a revoke:3 revoke:2 revoke:1', mLog.Text);
    Assert.IsFalse(mScope.IsOpen);
    Assert.AreEqual(0, Integer(Length(mRegistry.Modules)));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.UnregisterSkipsStopWhenInactive;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mScope.Own(TLoggedRegistration.Create(mLog, '1') as IAtlasRegistration);
    mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual('revoke:1', mLog.Text);
    // Unbekannte Id: nichts zu tun.
    Assert.AreEqual(0, Integer(Length(mRegistry.UnregisterModule('atlas.a'))));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.UnregisterContinuesAfterFailure;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mModule: TFakeModule;
  mModuleRef: IAtlasModule;
  mScope: IAtlasModuleScope;
  mFailing: TLoggedRegistration;
  mFailures: TArray<string>;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mModule := TFakeModule.Create(mLog, 'atlas.a');
    mModuleRef := mModule;
    mModule.FailStop := True;
    mScope := mRegistry.RegisterModule(mModuleRef);
    mScope.Own(TLoggedRegistration.Create(mLog, '1') as IAtlasRegistration);
    mFailing := TLoggedRegistration.Create(mLog, '2');
    mFailing.FailRevoke := True;
    mScope.Own(mFailing as IAtlasRegistration);
    mModuleRef.Start;
    mFailures := mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual('start:atlas.a stop:atlas.a revoke:2 revoke:1', mLog.Text);
    Assert.AreEqual(2, Integer(Length(mFailures)));
    Assert.IsTrue(mFailures[0].StartsWith('atlas.a Stop: EInvalidOp'), mFailures[0]);
    Assert.IsTrue(mFailures[1].StartsWith('atlas.a Anmeldung 2: EInvalidOp'), mFailures[1]);
    Assert.AreEqual(0, Integer(Length(mRegistry.Modules)));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ProvideAndFindAllByInterface;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mFound: TArray<IInterface>;
  mProbe: IProbeService;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mRegistry.Provide(IProbeService, TProbeService.Create('base') as IProbeService);
    mScope.Provide(IProbeService, TProbeService.Create('modul') as IProbeService);
    mFound := mRegistry.FindAll(IProbeService);
    Assert.AreEqual(2, Integer(Length(mFound)));
    Assert.IsTrue(Supports(mFound[0], IProbeService, mProbe));
    Assert.AreEqual('base', mProbe.Name);
    Assert.IsTrue(Supports(mFound[1], IProbeService, mProbe));
    Assert.AreEqual('modul', mProbe.Name);
    Assert.AreEqual(0, Integer(Length(mRegistry.FindAll(IOtherService))));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ProvideRejectsObjectWithoutInterface;
var
  mRegistry: IAtlasModuleRegistry;
  mRaised: Boolean;
begin
  mRegistry := TAtlasModuleRegistry.Create;
  mRaised := False;
  try
    mRegistry.Provide(IOtherService, TProbeService.Create('x') as IProbeService);
  except
    on EAtlasModuleRegistry do
      mRaised := True;
  end;
  Assert.IsTrue(mRaised);
  Assert.AreEqual(0, Integer(Length(mRegistry.FindAll(IOtherService))));
end;

procedure TModuleRegistryTests.UnregisterWithdrawsProvidedObjects;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mBase: IAtlasRegistration;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mScope.Provide(IProbeService, TProbeService.Create('modul') as IProbeService);
    mBase := mRegistry.Provide(IProbeService, TProbeService.Create('base') as IProbeService);
    mRegistry.UnregisterModule('atlas.a');
    Assert.AreEqual(1, Integer(Length(mRegistry.FindAll(IProbeService))));
    mBase.Revoke;
    Assert.IsTrue(mBase.IsRevoked);
    Assert.AreEqual(0, Integer(Length(mRegistry.FindAll(IProbeService))));
    // Zweites Lösen: nichts.
    mBase.Revoke;
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.OwnAfterCloseRevokesAtOnce;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mRegistry.UnregisterModule('atlas.a');
    mScope.Own(TLoggedRegistration.Create(mLog, 'spaet') as IAtlasRegistration);
    Assert.AreEqual('revoke:spaet', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ProvideAfterCloseRaises;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mRaised: Boolean;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mRegistry.UnregisterModule('atlas.a');
    mRaised := False;
    try
      mScope.Provide(IProbeService, TProbeService.Create('x') as IProbeService);
    except
      on EAtlasModuleRegistry do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
    Assert.AreEqual(0, Integer(Length(mRegistry.FindAll(IProbeService))));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ListenerSeesEveryChange;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.Subscribe(TLogListener.Create(mLog, 'L') as IAtlasRegistryListener);
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mScope.Provide(IProbeService, TProbeService.Create('x') as IProbeService);
    mRegistry.UnregisterModule('atlas.a');
    mRegistry.ForgetModule('atlas.a');
    Assert.AreEqual('L:added:atlas.a L:provided:atlas.a L:revoked:atlas.a L:removed:atlas.a L:known:atlas.a',
      mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.RevokedListenerIsNotCalledAnyMore;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mFirst: TLogListener;
  mSecond: IAtlasRegistration;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mFirst := TLogListener.Create(mLog, 'A');
    mRegistry.Subscribe(mFirst as IAtlasRegistryListener);
    mSecond := mRegistry.Subscribe(TLogListener.Create(mLog, 'B') as IAtlasRegistryListener);
    // A löst B mitten in der Meldung: B erfährt sie nicht mehr (Regel 3).
    mFirst.RevokeOnCall := mSecond;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.b') as IAtlasModule);
    Assert.AreEqual('A:added:atlas.a A:added:atlas.b', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.FailingListenerDoesNotStopOthers;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mFailing: TLogListener;
  mRaised: Boolean;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mFailing := TLogListener.Create(mLog, 'A');
    mFailing.Fail := True;
    mRegistry.Subscribe(mFailing as IAtlasRegistryListener);
    mRegistry.Subscribe(TLogListener.Create(mLog, 'B') as IAtlasRegistryListener);
    mRaised := False;
    try
      mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    except
      on EAtlasModuleRegistry do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised);
    Assert.AreEqual('A:added:atlas.a B:added:atlas.a', mLog.Text);
    // Die Anmeldung selbst gilt.
    Assert.AreEqual(1, Integer(Length(mRegistry.Modules)));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ModuleListenerEndsWithModule;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mScope.Subscribe(TLogListener.Create(mLog, 'A') as IAtlasRegistryListener);
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.b') as IAtlasModule);
    mRegistry.UnregisterModule('atlas.a');
    mRegistry.UnregisterModule('atlas.b');
    Assert.AreEqual('A:added:atlas.b', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.KnownKeepsMissingModule;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mKnown: TArray<TAtlasKnownModule>;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'Debugger', '2.0.0', 77) as IAtlasModule);
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'fremd.b') as IAtlasModule);
    mRegistry.UnregisterModule('atlas.a');
    mKnown := mRegistry.Known;
    Assert.AreEqual(2, Integer(Length(mKnown)));
    Assert.AreEqual('atlas.a', mKnown[0].Info.Id);
    Assert.AreEqual('Debugger', mKnown[0].Info.Name);
    Assert.AreEqual('2.0.0', mKnown[0].Info.Version);
    Assert.IsFalse(mKnown[0].Installed);
    Assert.IsTrue(mKnown[0].Info.Handle = 0, 'ohne Handle');
    Assert.AreEqual('fremd.b', mKnown[1].Info.Id);
    Assert.IsTrue(mKnown[1].Installed);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.KnownTakesNewNameAndVersion;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mKnown: TArray<TAtlasKnownModule>;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'Alt', '2.0.0', 0) as IAtlasModule);
    mRegistry.UnregisterModule('atlas.a');
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'Neu', '2.0.1', 0) as IAtlasModule);
    mKnown := mRegistry.Known;
    Assert.AreEqual(1, Integer(Length(mKnown)));
    Assert.AreEqual('Neu', mKnown[0].Info.Name);
    Assert.AreEqual('2.0.1', mKnown[0].Info.Version);
    Assert.IsTrue(mKnown[0].Installed);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ForgetOnlyMissingModule;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    Assert.IsFalse(mRegistry.ForgetModule('atlas.a'), 'angemeldet');
    Assert.IsFalse(mRegistry.ForgetModule('atlas.x'), 'unbekannt');
    mRegistry.UnregisterModule('atlas.a');
    Assert.IsTrue(mRegistry.ForgetModule('atlas.a'));
    Assert.AreEqual(0, Integer(Length(mRegistry.Known)));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.UseStorageMergesAndSavesKnown;
var
  mLog: TLog;
  mRegistry: TAtlasModuleRegistry;
  mRegistryRef: IAtlasModuleRegistry;
  mStorage: IAtlasSettingsStorage;
  mKnown: TArray<TAtlasKnownModule>;
begin
  mLog := TLog.Create;
  try
    mStorage := TAtlasMemorySettingsStorage.Create;
    mStorage.WriteText(cAtlasKnownModulesName, 'atlas.alt'#9'Alt'#9'2.0.0'#10'atlas.b'#9'B alt'#9'1.9');
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistryRef := mRegistry;
    mRegistryRef.RegisterModule(TFakeModule.Create(mLog, 'atlas.b', 'B', '2.0.0', 0) as IAtlasModule);
    mRegistry.UseStorage(mStorage);
    mKnown := mRegistryRef.Known;
    Assert.AreEqual(2, Integer(Length(mKnown)));
    Assert.AreEqual('atlas.alt', mKnown[0].Info.Id);
    Assert.IsFalse(mKnown[0].Installed);
    Assert.AreEqual('B', mKnown[1].Info.Name);
    Assert.AreEqual('atlas.alt'#9'Alt'#9'2.0.0'#10'atlas.b'#9'B'#9'2.0.0', mStorage.ReadText(cAtlasKnownModulesName));
    mRegistryRef.RegisterModule(TFakeModule.Create(mLog, 'atlas.c', 'C', '2.0.0', 0) as IAtlasModule);
    Assert.IsTrue(mStorage.ReadText(cAtlasKnownModulesName).EndsWith(#10'atlas.c'#9'C'#9'2.0.0'));
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.KnownTextRoundTrip;
var
  mInfos: TArray<TAtlasModuleInfo>;
  mBack: TArray<TAtlasModuleInfo>;
begin
  SetLength(mInfos, 2);
  mInfos[0].Id := 'atlas.a';
  mInfos[0].Name := 'Mit'#9'Tab';
  mInfos[0].Version := '2.0.0';
  mInfos[1].Id := 'fremd.b';
  mInfos[1].Name := 'Zwei'#13#10'Zeilen';
  mInfos[1].Version := '';
  mBack := TAtlasKnownModulesText.Decode(TAtlasKnownModulesText.Encode(mInfos));
  Assert.AreEqual(2, Integer(Length(mBack)));
  Assert.AreEqual('atlas.a', mBack[0].Id);
  Assert.AreEqual('Mit Tab', mBack[0].Name);
  Assert.AreEqual('2.0.0', mBack[0].Version);
  Assert.AreEqual('fremd.b', mBack[1].Id);
  Assert.AreEqual('Zwei  Zeilen', mBack[1].Name);
  Assert.AreEqual('', mBack[1].Version);
end;

procedure TModuleRegistryTests.KnownTextSkipsBrokenLines;
var
  mBack: TArray<TAtlasModuleInfo>;
begin
  mBack := TAtlasKnownModulesText.Decode(#9'ohne Id'#10#10'atlas.a'#13#10'atlas.a'#9'doppelt');
  Assert.AreEqual(1, Integer(Length(mBack)));
  Assert.AreEqual('atlas.a', mBack[0].Id);
  Assert.AreEqual('', mBack[0].Name);
  Assert.AreEqual(0, Integer(Length(TAtlasKnownModulesText.Decode(''))));
end;

procedure TModuleRegistryTests.IsModuleHandleOnlyForRegistered;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'A', '2.0.0', 4711) as IAtlasModule);
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.b') as IAtlasModule);
    Assert.IsTrue(mRegistry.IsModuleHandle(4711));
    Assert.IsFalse(mRegistry.IsModuleHandle(4712));
    Assert.IsFalse(mRegistry.IsModuleHandle(0), 'ohne Handle');
    mRegistry.UnregisterModule('atlas.a');
    Assert.IsFalse(mRegistry.IsModuleHandle(4711));
  finally
    mLog.Free;
  end;
end;

/// <summary>Setzt ARan; eigene Routine, damit der Code sicher im Testprogramm liegt.</summary>
function Marker(var ARan: Boolean): TThreadProcedure;
var
  mRan: PBoolean;
begin
  mRan := @ARan;
  Result :=
    procedure
    begin
      mRan^ := True;
    end;
end;

procedure TModuleRegistryTests.UnregisterDropsQueuedEntriesOfModule;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mRan: Boolean;
  mProc: TThreadProcedure;
  mModule: NativeUInt;
begin
  mRan := False;
  mProc := Marker(mRan);
  // Das Testprogramm spielt das Package des Moduls: Info.Handle = Modul des eingereihten Codes.
  mModule := TAtlasMainThread.ModuleOf(mProc);
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'A', '2.0.0', mModule) as IAtlasModule);
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mProc);
    mRegistry.UnregisterModule('atlas.a');
    CheckSynchronize;
    Assert.IsFalse(mRan, 'Eintrag des abgemeldeten Moduls läuft nicht nach seinem Entladen');
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a', 'A', '2.0.0', mModule) as IAtlasModule);
    TAtlasMainThread.ForceQueue(TAtlasFeature.Completion, mProc);
    CheckSynchronize;
    Assert.IsTrue(mRan, 'nach erneutem Anmelden wieder angenommen');
    mRegistry.UnregisterModule('atlas.a');
  finally
    TAtlasMainThread.OpenModule(mModule);
    mRegistry := nil;
    mProc := nil;
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.ShutDownUnregistersAllInReverse;
var
  mLog: TLog;
  mRegistry: TAtlasModuleRegistry;
  mRegistryRef: IAtlasModuleRegistry;
  mFirst: IAtlasModule;
  mSecond: IAtlasModule;
  mRaised: Boolean;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistryRef := mRegistry;
    mFirst := TFakeModule.Create(mLog, 'atlas.a');
    mSecond := TFakeModule.Create(mLog, 'atlas.b');
    mRegistryRef.RegisterModule(mFirst);
    mRegistryRef.RegisterModule(mSecond);
    mFirst.Start;
    mSecond.Start;
    Assert.AreEqual(0, Integer(Length(mRegistry.ShutDown)));
    Assert.AreEqual('start:atlas.a start:atlas.b stop:atlas.b stop:atlas.a', mLog.Text);
    mRaised := False;
    try
      mRegistryRef.RegisterModule(TFakeModule.Create(mLog, 'atlas.c') as IAtlasModule);
    except
      on EAtlasModuleRegistry do
        mRaised := True;
    end;
    Assert.IsTrue(mRaised, 'nach dem Abbau keine Anmeldung');
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.RegistrationSurvivesRegistry;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mScope: IAtlasModuleScope;
  mProvided: IAtlasRegistration;
begin
  mLog := TLog.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.a') as IAtlasModule);
    mProvided := mRegistry.Provide(IProbeService, TProbeService.Create('x') as IProbeService);
    mRegistry := nil;
    // Die Registry ist frei: Lösen und Scope gehen ins Leere statt in freigegebenen Speicher.
    Assert.IsTrue(mProvided.IsRevoked);
    mProvided.Revoke;
    Assert.IsFalse(mScope.IsOpen);
    mScope.Own(TLoggedRegistration.Create(mLog, 'spaet') as IAtlasRegistration);
    Assert.AreEqual('revoke:spaet', mLog.Text);
  finally
    mLog.Free;
  end;
end;

procedure TModuleRegistryTests.GlobalRegistryExists;
var
  mFirst, mSecond: IAtlasModuleRegistry;
begin
  mFirst := AtlasModuleRegistry;
  mSecond := AtlasModuleRegistry;
  Assert.IsTrue(mFirst <> nil);
  Assert.IsTrue(mFirst = mSecond, 'jeder Aufruf liefert dieselbe Instanz');
  Assert.IsTrue(AtlasModuleRegistryInstance <> nil);
end;

initialization
  TDUnitX.RegisterTestFixture(TModuleRegistryTests);

end.
