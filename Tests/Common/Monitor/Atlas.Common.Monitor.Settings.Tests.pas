unit Atlas.Common.Monitor.Settings.Tests;

// Tests für die Einstellungen von AtlasMonitor (#1901): Vorgaben, nachsichtiges Lesen, Schreiben mit Erhalt
// fremder Schlüssel, Speichern und Laden, Wahl der Sprache.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMonitorSettingsTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure DefaultsShowIconWithoutAutostart;
    [Test]
    procedure ReadsValuesLeniently;
    [Test]
    procedure WritingKeepsOtherKeys;
    [Test]
    procedure SavesAndLoads;
    [Test]
    procedure MissingFileGivesDefaults;
    [Test]
    procedure ChoosesLanguage;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Monitor.Settings;

procedure TMonitorSettingsTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'Atlas-MonitorSettings-' + IntToStr(Random(MaxInt)));
end;

procedure TMonitorSettingsTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  FFolder := '';
end;

procedure TMonitorSettingsTests.DefaultsShowIconWithoutAutostart;
var
  mSettings: TMonitorSettings;
begin
  mSettings := TMonitorSettings.Defaults;
  Assert.IsTrue(mSettings.TrayIcon);
  Assert.IsFalse(mSettings.StartWithWindows);
end;

procedure TMonitorSettingsTests.ReadsValuesLeniently;
var
  mSettings: TMonitorSettings;
begin
  mSettings := TMonitorSettings.FromText('{"monitor": {"trayIcon": false, "startWithWindows": true}}');
  Assert.IsFalse(mSettings.TrayIcon);
  Assert.IsTrue(mSettings.StartWithWindows);
  mSettings := TMonitorSettings.FromText('{"monitor": {"trayIcon": "nein"}}');
  Assert.IsTrue(mSettings.TrayIcon, 'kein Wahrheitswert: Vorgabe');
  mSettings := TMonitorSettings.FromText('kaputt');
  Assert.IsTrue(mSettings.TrayIcon);
  Assert.IsFalse(mSettings.StartWithWindows);
end;

procedure TMonitorSettingsTests.WritingKeepsOtherKeys;
var
  mSettings: TMonitorSettings;
  mText: string;
begin
  mSettings := TMonitorSettings.Defaults;
  mSettings.StartWithWindows := True;
  mText := mSettings.ToText('{"targets": ["C:\\A"], "monitor": {"trayIcon": false, "later": 1}}');
  Assert.IsTrue(mText.Contains('"targets"'), mText);
  Assert.IsTrue(mText.Contains('"later"'), mText);
  mSettings := TMonitorSettings.FromText(mText);
  Assert.IsTrue(mSettings.TrayIcon);
  Assert.IsTrue(mSettings.StartWithWindows);
  mSettings := TMonitorSettings.FromText(TMonitorSettings.Defaults.ToText('[1, 2]'));
  Assert.IsTrue(mSettings.TrayIcon, 'kein Objekt: neu angelegt');
end;

procedure TMonitorSettingsTests.SavesAndLoads;
var
  mSettings: TMonitorSettings;
  mFile: string;
begin
  mFile := TMonitorSettings.FileIn(FFolder);
  Assert.AreEqual(TPath.Combine(TPath.Combine(FFolder, 'Atlas'), 'monitor.json'), mFile);
  mSettings := TMonitorSettings.Defaults;
  mSettings.TrayIcon := False;
  Assert.IsTrue(mSettings.Save(mFile));
  mSettings := TMonitorSettings.Load(mFile);
  Assert.IsFalse(mSettings.TrayIcon);
  Assert.IsFalse(TFile.Exists(mFile + '.tmp'));
  Assert.IsFalse(TMonitorSettings.Defaults.Save(''));
end;

procedure TMonitorSettingsTests.MissingFileGivesDefaults;
begin
  Assert.AreEqual('', TMonitorSettings.FileIn(''));
  Assert.IsTrue(TMonitorSettings.Load(TPath.Combine(FFolder, 'fehlt.json')).TrayIcon);
  Assert.IsTrue(TMonitorSettings.Load('').TrayIcon);
end;

procedure TMonitorSettingsTests.ChoosesLanguage;
begin
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English,
    TMonitorSettings.LanguageOf('en', '{"language": "de"}', 'de-DE'),
    '--locale zuerst');
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TMonitorSettings.LanguageOf('', '{"language": "en"}', 'de-DE'),
    'dann settings.json');
  Assert.AreEqual<TTextLanguage>(TTextLanguage.German, TMonitorSettings.LanguageOf('', '{}', 'de-DE'), 'dann Windows');
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TMonitorSettings.LanguageOf('', '', 'fr'), 'sonst Englisch');
  Assert.AreEqual<TTextLanguage>(TTextLanguage.English, TMonitorSettings.LanguageOf('xx', 'kaputt', ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TMonitorSettingsTests);

end.
