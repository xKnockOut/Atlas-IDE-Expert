unit Argus.Core.Settings.Tests;

// Tests für die Einstellungen des Plugins (#227, Teil Vervollständigung).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TArgusPluginSettingsTests = class
  public
    [Test]
    procedure EmptyStoreGivesDefaults;
    [Test]
    procedure SaveAndLoadRoundTrip;
    [Test]
    procedure ClampsOutOfRangeValues;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Argus.Core.Settings.Plugin;

type
  TMemoryStore = class(TInterfacedObject, IArgusSettingsStore)
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

{ TArgusPluginSettingsTests }

procedure TArgusPluginSettingsTests.EmptyStoreGivesDefaults;
var
  Store: IArgusSettingsStore;
  Settings: TArgusPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := Default(TArgusPluginSettings);
  Settings.Load(Store);
  Assert.IsTrue(Settings.Enabled);
  Assert.AreEqual(9, Settings.VisibleRows);
  Assert.AreEqual(0, Settings.ListWidth, 'Liste automatisch');
  Assert.AreEqual(320, Settings.PanelWidth);
  Assert.IsTrue(Settings.AutoParentheses);
  Assert.IsFalse(Settings.Preview, 'Vorschau standardmäßig aus (#434)');
end;

procedure TArgusPluginSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IArgusSettingsStore;
  Settings, Loaded: TArgusPluginSettings;
begin
  Store := TMemoryStore.Create;
  Settings := TArgusPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 14;
  Settings.ListWidth := 500;
  Settings.PanelWidth := 400;
  Settings.PanelCollapsed := True;
  Settings.Learning := False;
  Settings.Preview := True;
  Settings.ServerPath := '  D:\Argus\ArgusServer.exe ';
  Settings.Save(Store);
  Loaded := Default(TArgusPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Enabled);
  Assert.AreEqual(14, Loaded.VisibleRows);
  Assert.AreEqual(500, Loaded.ListWidth);
  Assert.AreEqual(400, Loaded.PanelWidth);
  Assert.IsTrue(Loaded.PanelCollapsed);
  Assert.IsFalse(Loaded.Learning);
  Assert.IsTrue(Loaded.Preview);
  Assert.AreEqual('D:\Argus\ArgusServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual('', TArgusPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;

procedure TArgusPluginSettingsTests.ClampsOutOfRangeValues;
var
  Store: IArgusSettingsStore;
  Settings: TArgusPluginSettings;
begin
  Store := TMemoryStore.Create;
  Store.WriteInteger('VisibleRows', 99);
  Store.WriteInteger('ListWidth', 50);
  Store.WriteInteger('PanelWidth', 5000);
  Settings := Default(TArgusPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TArgusPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TArgusPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TArgusPluginSettings.MaxPanelWidth, Settings.PanelWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TArgusPluginSettingsTests);

end.
