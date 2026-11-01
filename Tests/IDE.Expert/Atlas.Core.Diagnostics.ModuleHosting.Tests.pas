unit Atlas.Core.Diagnostics.ModuleHosting.Tests;

// Tests zu TAtlasModuleHosting (#1455): Module der Registry als Teile der
// Feature-Tabelle, spätes An- und Abmelden, Mindeststufe und Modulschalter.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TModuleHostingTests = class
  public
    [Test]
    procedure RegisteredModulesBecomeParts;
    [Test]
    procedure LateModuleStartsViaOnChanged;
    [Test]
    procedure UnregisterRemovesPart;
    [Test]
    procedure MinLevelAndSwitchApply;
    [Test]
    procedure TableContainsAndRemove;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.ModuleHosting,
  Atlas.Core.Diagnostics.FeatureTable;

type
  TLog = class
  public
    Text: string;
    procedure Add(const AEntry: string);
  end;

  TFakeModule = class(TInterfacedObject, IAtlasModule)
  private
    FLog: TLog;
    FInfo: TAtlasModuleInfo;
    FActive: Boolean;
  public
    constructor Create(ALog: TLog; const AId: string; AMinLevel: TAtlasSafeLevel; const ASwitch: string);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
  end;

procedure TLog.Add(const AEntry: string);
begin
  if Text <> '' then
    Text := Text + ',';
  Text := Text + AEntry;
end;

constructor TFakeModule.Create(ALog: TLog; const AId: string; AMinLevel: TAtlasSafeLevel; const ASwitch: string);
begin
  inherited Create;
  FLog := ALog;
  FInfo := Default(TAtlasModuleInfo);
  FInfo.Id := AId;
  FInfo.Name := AId;
  FInfo.MinLevel := AMinLevel;
  FInfo.Switch := ASwitch;
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
  FActive := False;
  FLog.Add('stop:' + FInfo.Id);
end;

function TFakeModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function Module(ALog: TLog; const AId: string): IAtlasModule;
begin
  Result := TFakeModule.Create(ALog, AId, TAtlasSafeLevel.Normal, '');
end;

procedure TModuleHostingTests.RegisteredModulesBecomeParts;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(Module(mLog, 'atlas.a'));
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      Assert.AreEqual('', mLog.Text, 'Anmelden startet nichts (Regel 1)');
      Assert.IsTrue(mTable.Contains('module:atlas.a'));
      mTable.StartWanted(TAtlasSafeLevel.Normal);
      Assert.AreEqual('start:atlas.a', mLog.Text);
      mTable.StopAll;
      Assert.AreEqual('start:atlas.a,stop:atlas.a', mLog.Text);
    finally
      mHost.Free;
    end;
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

procedure TModuleHostingTests.LateModuleStartsViaOnChanged;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      mHost.OnChanged :=
        procedure
        begin
          mTable.StartWanted(TAtlasSafeLevel.Normal);
        end;
      mRegistry.RegisterModule(Module(mLog, 'atlas.late'));
      Assert.AreEqual('start:atlas.late', mLog.Text, 'spät angemeldet, gleich gestartet (Regel 2)');
      mHost.OnChanged := nil;
    finally
      mHost.Free;
    end;
    mRegistry.UnregisterModule('atlas.late');
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

procedure TModuleHostingTests.UnregisterRemovesPart;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(Module(mLog, 'atlas.a'));
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      mTable.StartWanted(TAtlasSafeLevel.Normal);
      mRegistry.UnregisterModule('atlas.a');
      Assert.AreEqual('start:atlas.a,stop:atlas.a', mLog.Text, 'die Registry stoppt beim Abmelden');
      Assert.IsFalse(mTable.Contains('module:atlas.a'));
      mTable.StopAll;
      Assert.AreEqual('start:atlas.a,stop:atlas.a', mLog.Text, 'kein zweites Stop');
    finally
      mHost.Free;
    end;
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

procedure TModuleHostingTests.MinLevelAndSwitchApply;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
  mOff: string;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mRegistry := TAtlasModuleRegistry.Create;
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.safe', TAtlasSafeLevel.Safe, '') as IAtlasModule);
    mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.dbg', TAtlasSafeLevel.Normal, 'debug') as IAtlasModule);
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      Assert.AreEqual('debug', mTable.ModuleOf('module:atlas.dbg'));
      mOff := 'debug';
      mTable.ModuleOn :=
        function(const AModule: string): Boolean
        begin
          Result := AModule <> mOff;
        end;
      mTable.StartWanted(TAtlasSafeLevel.Safe);
      Assert.AreEqual('start:atlas.safe', mLog.Text, 'Safe: nur das Modul mit Mindeststufe Safe');
      mTable.StartWanted(TAtlasSafeLevel.Normal);
      Assert.AreEqual('start:atlas.safe', mLog.Text, 'Schalter debug aus');
      mOff := '';
      mTable.StartWanted(TAtlasSafeLevel.Normal);
      Assert.AreEqual('start:atlas.safe,start:atlas.dbg', mLog.Text);
      mTable.ModuleOn := nil;
      mTable.StopAll;
    finally
      mHost.Free;
    end;
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

procedure TModuleHostingTests.TableContainsAndRemove;
var
  mTable: TAtlasFeatureTable;
begin
  mTable := TAtlasFeatureTable.Create;
  try
    mTable.Add('A', TAtlasSafeLevel.Normal,
      function: Boolean
      begin
        Result := False;
      end,
      procedure
      begin
      end,
      procedure
      begin
      end);
    Assert.IsTrue(mTable.Contains('A'));
    Assert.IsFalse(mTable.Contains('B'));
    Assert.IsTrue(mTable.Remove('A'));
    Assert.IsFalse(mTable.Remove('A'));
    Assert.AreEqual(0, Integer(Length(mTable.Names)));
  finally
    mTable.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TModuleHostingTests);

end.
