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
  Assert.IsTrue(Settings.PairOwners, 'Anweisungen mitfärben standardmäßig an (#653)');
  Assert.AreEqual(1, Settings.PairGuideWidth, 'Blocklinien 1 px');
  Assert.AreEqual(50, Settings.PairGuideOpacity, 'Blocklinien 50 % Deckkraft');
  Assert.IsTrue(Settings.ProblemsList, 'Liste „Atlas-Probleme“ standardmäßig an');
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
  Settings.ProblemsList := False;
  Settings.ServerPath := '  D:\Atlas\AtlasServer.exe ';
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 80;
  Settings.PairColorsDark := '#112233, #445566,#778899,#aabbcc,#DDEEFF';
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
  Assert.IsFalse(Loaded.PairOwners);
  Assert.AreEqual(3, Loaded.PairGuideWidth);
  Assert.AreEqual(80, Loaded.PairGuideOpacity);
  Assert.AreEqual('#112233,#445566,#778899,#AABBCC,#DDEEFF', Loaded.PairColorsDark, 'einheitlich geschrieben');
  Assert.IsFalse(Loaded.ProblemsList, 'Liste „Atlas-Probleme“ abgeschaltet');
  Assert.IsTrue(Loaded.Problems, 'Wellenlinien bleiben an');
  Assert.AreEqual('D:\Atlas\AtlasServer.exe', Loaded.ServerPath, 'Serverpfad ohne Leerraum');
  Assert.AreEqual('', TAtlasPluginSettings.Defaults.ServerPath, 'Standard: leer');
end;

procedure TAtlasPluginSettingsTests.IndexOptionsGoToServer;
var
  Store: IAtlasSettingsStore;
  Settings, Loaded: TAtlasPluginSettings;
begin
  // Vorgaben wie im Schema; atlas.json-Format für den Server (#652).
  Settings := TAtlasPluginSettings.Defaults;
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":true,"libraryPaths":false}}',
    Settings.ServerSettingsJson);
  Store := TMemoryStore.Create;
  Settings.IndexSearchPaths := False;
  Settings.IndexLibraryPaths := True;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.IndexProjectGroup);
  Assert.IsFalse(Loaded.IndexSearchPaths);
  Assert.IsTrue(Loaded.IndexLibraryPaths);
  Assert.AreEqual('{"index":{"projectGroup":true,"searchPaths":false,"libraryPaths":true}}',
    Loaded.ServerSettingsJson);
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
  Store.WriteInteger('PairGuideWidth', 7);
  Store.WriteInteger('PairGuideOpacity', 0);
  Store.WriteString('PairColorsLight', '#123456,blau');
  Settings := Default(TAtlasPluginSettings);
  Settings.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.MaxPairGuideWidth, Settings.PairGuideWidth);
  Assert.AreEqual(TAtlasPluginSettings.MinPairGuideOpacity, Settings.PairGuideOpacity);
  Assert.AreEqual('', Settings.PairColorsLight, 'ungültige Farben = Standard');
  Assert.AreEqual(TAtlasPluginSettings.MaxVisibleRows, Settings.VisibleRows);
  Assert.AreEqual(TAtlasPluginSettings.MinListWidth, Settings.ListWidth);
  Assert.AreEqual(TAtlasPluginSettings.MaxPanelWidth, Settings.PanelWidth);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginSettingsTests);

end.
