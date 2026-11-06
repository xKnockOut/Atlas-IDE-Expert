unit Atlas.Core.Settings.PluginTimings.Tests;

// Einstellungen des Diagnose-Fensters für die Zeiten des Plugins:
// diagnosticMode.pluginTimings (Vorgabe an) und diagnosticMode.slowThresholdMs
// (Vorgabe 16, 1 bis 1000), mit Speichern und Laden. Eigene Testunit, weil
// TAtlasPluginSettingsTests die Grenze der Klassengröße schon überschreitet.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasPluginTimingsSettingsTests = class
  public
    [Test]
    procedure DefaultsOnAnd16;
    [Test]
    procedure SaveAndLoad;
    [Test]
    procedure ThresholdIsClamped;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin;

type
  TValueStore = class(TInterfacedObject, IAtlasSettingsStore)
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

{ TValueStore }

constructor TValueStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
end;

destructor TValueStore.Destroy;
begin
  FStrings.Free;
  FValues.Free;
  inherited Destroy;
end;

function TValueStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TValueStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

function TValueStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TValueStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(AName, AValue);
end;

{ TAtlasPluginTimingsSettingsTests }

procedure TAtlasPluginTimingsSettingsTests.DefaultsOnAnd16;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Load(TValueStore.Create);
  Assert.IsTrue(mSettings.DiagnosticPluginTimings);
  Assert.AreEqual(16, mSettings.DiagnosticSlowMs);
end;

procedure TAtlasPluginTimingsSettingsTests.SaveAndLoad;
var
  mStore: IAtlasSettingsStore;
  mSettings, mLoaded: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.DiagnosticPluginTimings := False;
  mSettings.DiagnosticSlowMs := 40;
  mStore := TValueStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DiagnosticPluginTimings);
  Assert.AreEqual(40, mLoaded.DiagnosticSlowMs);
end;

procedure TAtlasPluginTimingsSettingsTests.ThresholdIsClamped;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.DiagnosticSlowMs := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinSlowThreshold, mSettings.DiagnosticSlowMs);
  mSettings.DiagnosticSlowMs := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxSlowThreshold, mSettings.DiagnosticSlowMs);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginTimingsSettingsTests);

end.
