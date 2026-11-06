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
    [Test]
    procedure ProvidedPartsFollowTheModule;
    [Test]
    procedure LatePartStartsViaOnChanged;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.FeatureParts,
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
  begin
    Text := Text + ',';
  end;
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

/// <summary>Teil, das sein Starten und Stoppen in ALog schreibt; AActive hält den Zustand.</summary>
function LoggedPart(ALog: TLog; const AName: string; AActive: PBoolean): IAtlasFeaturePart;
begin
  Result := TAtlasFeaturePart.AtLevel(AName, TAtlasSafeLevel.Normal,
    function: Boolean
    begin
      Result := AActive^;
    end,
    procedure
    begin
      AActive^ := True;
      ALog.Add('start:' + AName);
    end,
    procedure
    begin
      AActive^ := False;
      ALog.Add('stop:' + AName);
    end);
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

procedure TModuleHostingTests.ProvidedPartsFollowTheModule;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
  mScope: IAtlasModuleScope;
  mActive: array[0..1] of Boolean;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mActive[0] := False;
    mActive[1] := False;
    mRegistry := TAtlasModuleRegistry.Create;
    mScope := mRegistry.RegisterModule(TFakeModule.Create(mLog, 'atlas.dbg', TAtlasSafeLevel.Normal, 'debug')
      as IAtlasModule);
    mScope.Provide(IAtlasFeaturePart, LoggedPart(mLog, 'Visualizers', @mActive[0]));
    mScope.Provide(IAtlasFeaturePart, LoggedPart(mLog, 'DisplayRules', @mActive[1]));
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      Assert.AreEqual('module:atlas.dbg,Visualizers,DisplayRules', string.Join(',', mTable.Names));
      Assert.AreEqual('debug', mTable.ModuleOf('Visualizers'), 'Schalter des Besitzers');
      mTable.StartWanted(TAtlasSafeLevel.Normal);
      Assert.AreEqual('start:atlas.dbg,start:Visualizers,start:DisplayRules', mLog.Text);
      mLog.Text := '';
      mScope := nil;
      mRegistry.UnregisterModule('atlas.dbg');
      Assert.AreEqual('stop:atlas.dbg,stop:DisplayRules,stop:Visualizers', mLog.Text, 'Teile rückwärts');
      Assert.AreEqual(0, Integer(Length(mTable.Names)));
      Assert.AreEqual(0, Integer(Length(mHost.TakeFailures)));
    finally
      mHost.Free;
    end;
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

procedure TModuleHostingTests.LatePartStartsViaOnChanged;
var
  mLog: TLog;
  mRegistry: IAtlasModuleRegistry;
  mTable: TAtlasFeatureTable;
  mHost: TAtlasModuleHosting;
  mScope: IAtlasModuleScope;
  mActive: Boolean;
begin
  mLog := TLog.Create;
  mTable := TAtlasFeatureTable.Create;
  try
    mActive := False;
    mRegistry := TAtlasModuleRegistry.Create;
    mHost := TAtlasModuleHosting.Create(mRegistry, mTable);
    try
      mHost.OnChanged :=
        procedure
        begin
          mTable.StartWanted(TAtlasSafeLevel.Normal);
        end;
      mScope := mRegistry.RegisterModule(Module(mLog, 'atlas.late'));
      mScope.Provide(IAtlasFeaturePart, LoggedPart(mLog, 'Late', @mActive));
      Assert.AreEqual('start:atlas.late,start:Late', mLog.Text);
      mHost.OnChanged := nil;
      mScope := nil;
      mRegistry.UnregisterModule('atlas.late');
      Assert.IsFalse(mActive);
    finally
      mHost.Free;
    end;
    mRegistry := nil;
  finally
    mTable.Free;
    mLog.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TModuleHostingTests);

end.
