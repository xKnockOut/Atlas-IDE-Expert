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
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.TestSupport;

{ TAtlasPluginTimingsSettingsTests }

procedure TAtlasPluginTimingsSettingsTests.DefaultsOnAnd16;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := Default(TAtlasPluginSettings);
  mSettings.Load(TMemoryStore.Create);
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
  mStore := TMemoryStore.Create;
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
  Assert.AreEqual(TAtlasPluginSettings.cMinSlowThreshold, mSettings.DiagnosticSlowMs);
  mSettings.DiagnosticSlowMs := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxSlowThreshold, mSettings.DiagnosticSlowMs);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasPluginTimingsSettingsTests);

end.
