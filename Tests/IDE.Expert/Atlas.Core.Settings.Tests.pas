unit Atlas.Core.Settings.Tests;

// Tests für die Einstellungen des Plugins (#227, Teil Vervollständigung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginSettingsTests = class
  public
    [Test]
    procedure EmptyStoreGivesDefaults;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
    [Test]
    procedure IndexOptionsGoToServer;
    [Test]
    procedure XmlDocOptionsGoToServer;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin;

type
  TMemoryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TMemoryStore }

constructor TMemoryStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TMemoryStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TMemoryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TMemoryStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TMemoryStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginSettingsTests }

procedure TAtlasPluginSettingsTests.EmptyStoreGivesDefaults;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.IsTrue(Settings.Enabled);
  Assert.AreEqual(9, Settings.VisibleRows);
  Assert.AreEqual(0, Settings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, Settings.PanelWidth);
  Assert.IsTrue(Settings.AutoParentheses);
  Assert.IsFalse(Settings.Preview, 'Vorschau standardmäßig aus (#434)');
  // Vervollständigung und Parameter-Hint über die Tasten der IDE, ohne eigene Belegung (#494).
  Assert.AreEqual(0, Settings.CompletionKey);
  Assert.AreEqual(0, Settings.SignatureKey);
  Assert.IsFalse(Settings.SignatureKeyPriority);
  Assert.AreEqual(200, Settings.ProviderTimeLimitMs, 'Zeitlimit für Quellen (#493)');
  Assert.AreEqual($E041, Settings.QuickToggleKey, 'Schnellschalter: Strg+Umschalt+Alt+A (#604)');
  Assert.IsFalse(Settings.QuickToggleKeyPriority);
  // Abgesicherter Start (#722).
  Assert.IsTrue(Settings.SafeAskAfterCrash);
  Assert.IsTrue(Settings.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('shift', Settings.SafeStartupKey);
  Assert.AreEqual(10000, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(5, Settings.SafeKeepSettingsHistory);
end;

procedure TAtlasPluginSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 14;
  Settings.ListWidth := 500;
  Settings.PanelWidth := 400;
  Settings.PanelCollapsed := True;
  Settings.Learning := False;
  Settings.Preview := True;
  Settings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  Settings.SignatureKey := $6048; // Strg+Umschalt+H
  Settings.SignatureKeyPriority := True;
  Settings.CompletionKey := $4020; // Strg+Leer
  Settings.ProviderTimeLimitMs := 350;
  Settings.QuickToggleKey := $6051;
  Settings.QuickToggleKeyPriority := True;
  Settings.SafeAskAfterCrash := False;
  Settings.SafeAutoAfterRepeatedCrash := False;
  Settings.SafeStartupKey := 'none';
  Settings.SafeStartupTimeoutMs := 30000;
  Settings.SafeKeepSettingsHistory := 0;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Enabled);
  Assert.AreEqual(14, Loaded.VisibleRows);
  Assert.AreEqual(500, Loaded.ListWidth);
  Assert.AreEqual(400, Loaded.PanelWidth);
  Assert.IsTrue(Loaded.PanelCollapsed);
  Assert.IsFalse(Loaded.Learning);
  Assert.IsTrue(Loaded.Preview);
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual($6048, Loaded.SignatureKey);
  Assert.IsTrue(Loaded.SignatureKeyPriority);
  Assert.AreEqual($4020, Loaded.CompletionKey);
  Assert.IsFalse(Loaded.CompletionKeyPriority);
  Assert.AreEqual(350, Loaded.ProviderTimeLimitMs);
  Assert.AreEqual($6051, Loaded.QuickToggleKey);
  Assert.IsTrue(Loaded.QuickToggleKeyPriority);
  Assert.IsFalse(Loaded.SafeAskAfterCrash);
  Assert.IsFalse(Loaded.SafeAutoAfterRepeatedCrash);
  Assert.AreEqual('none', Loaded.SafeStartupKey);
  Assert.AreEqual(30000, Loaded.SafeStartupTimeoutMs);
  Assert.AreEqual(0, Loaded.SafeKeepSettingsHistory);
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;

procedure TAtlasPluginSettingsTests.IndexOptionsGoToServer;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Vorgaben wie im Schema; atlas.json-Format für den Server (#652).
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":true,"libraryPaths":false,"usages":true},' +
    '"memoryBudgetMb":256,"hints":{"xmlDocFull":true,"xmlDocMaxLines":0}}', Settings.ServerSettingsJson);
  Store := TMemoryStore.Create;
  Settings.IndexSearchPaths := False;
  Settings.IndexLibraryPaths := True;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.IndexProjectGroup);
  Assert.IsFalse(Loaded.IndexSearchPaths);
  Assert.IsTrue(Loaded.IndexLibraryPaths);
  Assert.IsFalse(Loaded.IndexUsages);
  Assert.AreEqual(512, Loaded.MemoryBudgetMb);
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":false,"libraryPaths":true,"usages":false},' +
    '"memoryBudgetMb":512,"hints":{"xmlDocFull":true,"xmlDocMaxLines":0}}', Loaded.ServerSettingsJson);
  // Speichergrenze (#492): 0 = unbegrenzt, nicht negativ, höchstens 64 GB.
  Store.WriteInteger('MemoryBudgetMb', -5);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.MemoryBudgetMb);
  Store.WriteInteger('MemoryBudgetMb', 999999);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxMemoryBudgetMb, Loaded.MemoryBudgetMb);
end;

procedure TAtlasPluginSettingsTests.XmlDocOptionsGoToServer;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // #654: Registry XmlDocFull/XmlDocMaxLines, an den Server als hints.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.XmlDocFull);
  Assert.AreEqual(0, Settings.XmlDocMaxLines);
  Store := TMemoryStore.Create;
  Settings.XmlDocFull := False;
  Settings.XmlDocMaxLines := 12;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('XmlDocFull', 1));
  Assert.AreEqual(12, Store.ReadInteger('XmlDocMaxLines', 0));
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.XmlDocFull);
  Assert.AreEqual(12, Loaded.XmlDocMaxLines);
  Assert.IsTrue(Pos('"hints":{"xmlDocFull":false,"xmlDocMaxLines":12}', Loaded.ServerSettingsJson) > 0);
  // Grenzen 0..50.
  Store.WriteInteger('XmlDocMaxLines', 99);
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxXmlDocLines, Loaded.XmlDocMaxLines);
  Store.WriteInteger('XmlDocMaxLines', -3);
  Loaded.Load(Store);
  Assert.AreEqual(0, Loaded.XmlDocMaxLines);
end;

procedure TAtlasPluginSettingsTests.ClampsOutOfRangeValues;
var
  Store: IAtlasSettingsStore;
  Settings: TAtlasPluginSettings;
begin
  Store := TMemoryStore.Create;
  Store.WriteInteger('VisibleRows', 99);
  Store.WriteInteger('ListWidth', 50);
  Store.WriteInteger('PanelWidth', 5000);
  Store.WriteInteger('SignatureKey', -3);
  Store.WriteInteger('ProviderTimeLimitMs', 10);
  Store.WriteInteger('SafeStartupTimeoutMs', 5);
  Store.WriteInteger('SafeKeepSettingsHistory', 1000);
  Store.WriteString('SafeStartupKey', ' Alt ');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MinProviderTimeLimit, Settings.ProviderTimeLimitMs);
  Assert.AreEqual(0, Settings.SignatureKey, 'kein gültiges Kürzel');
  Assert.AreEqual(TAtlasPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxPanelWidth, Settings.PanelWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinSafeStartupTimeout, Settings.SafeStartupTimeoutMs);
  Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Settings.SafeKeepSettingsHistory);
  Assert.AreEqual('shift', Settings.SafeStartupKey, 'unbekannte Taste: Umschalt');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);

end.
