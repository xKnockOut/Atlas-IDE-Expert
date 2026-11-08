unit Atlas.Common.Compiler.Backend.Tests;

// Tests für Kompilieren ohne Kommandozeilen-Compiler (#261): Erkennen der
// Ausgabe (Starter Edition), Zwischenspeicher je Installation und Wahl des
// Wegs zum Compiler mit Grund und Ausweg. Testdaten in Tests\Data\Compiler:
// dcc32-starter.txt (Ausgabe von dcc32 der Starter Edition ohne Argumente).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCompilerEditionTests = class
  public
    [Test]
    procedure DetectsStarterFromRecordedOutput;
    [Test]
    procedure DetectsCommandLineCompiler;
    [Test]
    procedure DetectsMissingAndUnknown;
    [Test]
    procedure RecognizesGermanLicenseText;
    [Test]
    procedure CacheRoundTripPerRootAndVersion;
    [Test]
    procedure CacheIgnoresChangedCompiler;
    [Test]
    procedure CacheSurvivesBrokenText;
  end;

  [TestFixture]
  TCompilerBackendTests = class
  public
    [Test]
    procedure AutoTakesDccWhenUsable;
    [Test]
    procedure AutoWithoutDccNamesReasonAndRemedy;
    [Test]
    procedure DccSettingOnStarterIsUnavailable;
    [Test]
    procedure OffSettingIsUnavailable;
    [Test]
    procedure OnlyDccRunsOnSave;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Compiler.Backend;

/// <summary>Datei aus Tests\Data\Compiler, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function DataLines(const AName: string): TArray<string>;
var
  Directory, FileName: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    FileName := TPath.Combine(Directory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Compiler', AName))));
    if TFile.Exists(FileName) then
    begin
      Exit(TFile.ReadAllLines(FileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(Directory) = Directory then
    begin
      Break;
    end;
    Directory := ExtractFileDir(Directory);
  end;
  raise Exception.Create('Tests\Data\Compiler\' + AName + ' nicht gefunden');
end;

{ TCompilerEditionTests }

procedure TCompilerEditionTests.DetectsStarterFromRecordedOutput;
var
  Output: TArray<string>;
begin
  Output := DataLines('dcc32-starter.txt');
  Assert.IsTrue(TCompilerEditions.HasLicenseText(Output));
  Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(TCompilerEditions.Detect(True, Output)));
  Assert.IsTrue(Pos('Starter Edition', TCompilerEditions.Describe(TCompilerEdition.NoCommandLine)) > 0);
end;

procedure TCompilerEditionTests.DetectsCommandLineCompiler;
var
  Output: TArray<string>;
begin
  // Kopf ohne die Zeile mit dem Urheberrecht (siehe Check-NoEmbarcaderoSources).
  Output := TArray<string>.Create('Embarcadero Delphi for Win32 compiler version 37.0', '',
    'Syntax: dcc32 [options] filename [options]', '  -A<unit>=<alias> = Set unit alias');
  Assert.IsFalse(TCompilerEditions.HasLicenseText(Output));
  Assert.AreEqual(Ord(TCompilerEdition.CommandLine), Ord(TCompilerEditions.Detect(True, Output)));
end;

procedure TCompilerEditionTests.DetectsMissingAndUnknown;
begin
  Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(TCompilerEditions.Detect(False, nil)));
  // Lief, sagte aber nichts: unklar, der nächste Lauf prüft erneut.
  Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(TCompilerEditions.Detect(True, TArray<string>.Create('', ' '))));
  Assert.AreEqual('noCommandLine', TCompilerEditions.ToText(TCompilerEdition.NoCommandLine));
  Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(TCompilerEditions.FromText('missing')));
  Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(TCompilerEditions.FromText('anders')));
end;

procedure TCompilerEditionTests.RecognizesGermanLicenseText;
begin
  Assert.IsTrue(TCompilerEditions.IsLicenseLine(
    'Diese Version des Produkts unterstützt das Compilieren über die Befehlszeile nicht.'));
  Assert.IsTrue(TCompilerEditions.IsLicenseLine('Command line compiling is not supported in this edition'));
  Assert.IsFalse(TCompilerEditions.IsLicenseLine('Syntax: dcc32 [options] filename [options]'));
  Assert.IsFalse(TCompilerEditions.IsLicenseLine('[dcc32 Fehler] Main.pas(3): E2003 Undeklarierter Bezeichner'));
end;

function Entry(const ARoot, AVersion, AStamp: string; AEdition: TCompilerEdition): TCompilerEditionEntry;
begin
  Result := Default(TCompilerEditionEntry);
  Result.Root := ARoot;
  Result.Version := AVersion;
  Result.Stamp := AStamp;
  Result.Edition := AEdition;
  Result.Checked := '2026-10-16T10:00:00Z';
end;

procedure TCompilerEditionTests.CacheRoundTripPerRootAndVersion;
var
  Cache, Loaded: TCompilerEditionCache;
begin
  Cache := TCompilerEditionCache.Create;
  Loaded := TCompilerEditionCache.Create;
  try
    Cache.Store(Entry('C:\Delphi\23.0', '23.0', '100-a', TCompilerEdition.NoCommandLine));
    Cache.Store(Entry('C:\Delphi\37.0', '37.0', '200-b', TCompilerEdition.CommandLine));
    // Gleiche Installation ersetzt den Eintrag.
    Cache.Store(Entry('c:\delphi\37.0', '37.0', '200-b', TCompilerEdition.Missing));
    Assert.AreEqual(2, Integer(Cache.Count));
    Loaded.Load(Cache.ToJson);
    Assert.AreEqual(2, Integer(Loaded.Count));
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(Loaded.Find('C:\Delphi\23.0', '23.0', '100-a')));
    Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(Loaded.Find('C:\Delphi\37.0', '37.0', '200-b')));
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(Loaded.Find('C:\Delphi\12.0', '12.0', '1-x')));
  finally
    Loaded.Free;
    Cache.Free;
  end;
end;

procedure TCompilerEditionTests.CacheIgnoresChangedCompiler;
var
  Cache: TCompilerEditionCache;
begin
  Cache := TCompilerEditionCache.Create;
  try
    Cache.Store(Entry('C:\Delphi\23.0', '23.0', '100-a', TCompilerEdition.NoCommandLine));
    // Neu installiert (z. B. Professional statt Starter): dcc hat einen anderen Fingerabdruck.
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(Cache.Find('C:\Delphi\23.0', '23.0', '999-z')));
  finally
    Cache.Free;
  end;
end;

procedure TCompilerEditionTests.CacheSurvivesBrokenText;
var
  Cache: TCompilerEditionCache;
begin
  Cache := TCompilerEditionCache.Create;
  try
    Cache.Load('kein JSON');
    Assert.AreEqual(0, Integer(Cache.Count));
    // Ohne Wurzel, ohne bekannte Ausgabe oder kein Objekt: übergangen.
    Cache.Load('{"format": 1, "entries": [{"root": "", "edition": "missing"}, ' +
      '{"root": "C:\\D", "version": "23.0", "edition": "anders"}, 5]}');
    Assert.AreEqual(0, Integer(Cache.Count));
  finally
    Cache.Free;
  end;
end;

{ TCompilerBackendTests }

procedure TCompilerBackendTests.AutoTakesDccWhenUsable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.CommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
  Assert.AreEqual('Compiler: dcc (Kommandozeile)', Choice.StatusText);
  Assert.AreEqual('', Choice.MessageText);
  // Noch nicht geprüft: dcc versuchen; zeigt dcc den Lizenztext, merkt sich das der Server.
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Unknown);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
end;

procedure TCompilerBackendTests.AutoWithoutDccNamesReasonAndRemedy;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.NoCommandLine);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(Choice.Backend));
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Assert.IsTrue(Choice.MessageText.StartsWith('Atlas kann nicht kompilieren: '), Choice.MessageText);
  Assert.IsTrue(Pos('Starter Edition', Choice.MessageText) > 0, Choice.MessageText);
  // Ausweg: laufende RAD Studio mit Atlas (build_project) oder ein Kommandozeilen-Compiler (#1904).
  Assert.IsTrue(Pos('build_project', Choice.Remedy) > 0, 'Ausweg fehlt: ' + Choice.Remedy);
  Assert.IsTrue(Pos('Kommandozeilen-Compiler', Choice.Remedy) > 0, Choice.Remedy);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Missing);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
end;

procedure TCompilerBackendTests.DccSettingOnStarterIsUnavailable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.NoCommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(Choice.Backend), 'dcc heißt nur dcc');
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.CommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
end;

procedure TCompilerBackendTests.OffSettingIsUnavailable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Off, TCompilerEdition.CommandLine);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (abgeschaltet)', Choice.StatusText);
  Assert.AreEqual('off', TCompilerBackends.BackendText(Choice.Backend));
  Assert.AreEqual('auto', TCompilerBackends.SettingText(TCompilerBackendSetting.Auto));
  Choice := TCompilerBackendChoice.Unavailable('Kein Projekt geladen', '');
  Assert.AreEqual('Atlas kann nicht kompilieren: Kein Projekt geladen.', Choice.MessageText);
end;

procedure TCompilerBackendTests.OnlyDccRunsOnSave;
begin
  Assert.IsTrue(TCompilerBackends.RunsOnSave(TCompilerBackend.Dcc));
  Assert.IsFalse(TCompilerBackends.RunsOnSave(TCompilerBackend.Off));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerEditionTests);
  TDUnitX.RegisterTestFixture(TCompilerBackendTests);

end.
