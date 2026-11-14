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
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Compiler', AName))));
    if TFile.Exists(mFileName) then
    begin
      Exit(TFile.ReadAllLines(mFileName, TEncoding.UTF8));
    end;
    if ExtractFileDir(mDirectory) = mDirectory then
    begin
      Break;
    end;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\Compiler\' + AName + ' nicht gefunden');
end;

{ TCompilerEditionTests }

procedure TCompilerEditionTests.DetectsStarterFromRecordedOutput;
var
  mOutput: TArray<string>;
begin
  mOutput := DataLines('dcc32-starter.txt');
  Assert.IsTrue(TCompilerEditions.HasLicenseText(mOutput));
  Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(TCompilerEditions.Detect(True, mOutput)));
  Assert.IsTrue(Pos('Starter Edition', TCompilerEditions.Describe(TCompilerEdition.NoCommandLine)) > 0);
end;

procedure TCompilerEditionTests.DetectsCommandLineCompiler;
var
  mOutput: TArray<string>;
begin
  // Kopf ohne die Zeile mit dem Urheberrecht (siehe Check-NoEmbarcaderoSources).
  mOutput := TArray<string>.Create('Embarcadero Delphi for Win32 compiler version 37.0', '',
    'Syntax: dcc32 [options] filename [options]', '  -A<unit>=<alias> = Set unit alias');
  Assert.IsFalse(TCompilerEditions.HasLicenseText(mOutput));
  Assert.AreEqual(Ord(TCompilerEdition.CommandLine), Ord(TCompilerEditions.Detect(True, mOutput)));
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
  mCache, mLoaded: TCompilerEditionCache;
begin
  mCache := TCompilerEditionCache.Create;
  mLoaded := TCompilerEditionCache.Create;
  try
    mCache.Store(Entry('C:\Delphi\23.0', '23.0', '100-a', TCompilerEdition.NoCommandLine));
    mCache.Store(Entry('C:\Delphi\37.0', '37.0', '200-b', TCompilerEdition.CommandLine));
    // Gleiche Installation ersetzt den Eintrag.
    mCache.Store(Entry('c:\delphi\37.0', '37.0', '200-b', TCompilerEdition.Missing));
    Assert.AreEqual(2, Integer(mCache.Count));
    mLoaded.Load(mCache.ToJson);
    Assert.AreEqual(2, Integer(mLoaded.Count));
    Assert.AreEqual(Ord(TCompilerEdition.NoCommandLine), Ord(mLoaded.Find('C:\Delphi\23.0', '23.0', '100-a')));
    Assert.AreEqual(Ord(TCompilerEdition.Missing), Ord(mLoaded.Find('C:\Delphi\37.0', '37.0', '200-b')));
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(mLoaded.Find('C:\Delphi\12.0', '12.0', '1-x')));
  finally
    mLoaded.Free;
    mCache.Free;
  end;
end;

procedure TCompilerEditionTests.CacheIgnoresChangedCompiler;
var
  mCache: TCompilerEditionCache;
begin
  mCache := TCompilerEditionCache.Create;
  try
    mCache.Store(Entry('C:\Delphi\23.0', '23.0', '100-a', TCompilerEdition.NoCommandLine));
    // Neu installiert (z. B. Professional statt Starter): dcc hat einen anderen Fingerabdruck.
    Assert.AreEqual(Ord(TCompilerEdition.Unknown), Ord(mCache.Find('C:\Delphi\23.0', '23.0', '999-z')));
  finally
    mCache.Free;
  end;
end;

procedure TCompilerEditionTests.CacheSurvivesBrokenText;
var
  mCache: TCompilerEditionCache;
begin
  mCache := TCompilerEditionCache.Create;
  try
    mCache.Load('kein JSON');
    Assert.AreEqual(0, Integer(mCache.Count));
    // Ohne Wurzel, ohne bekannte Ausgabe oder kein Objekt: übergangen.
    mCache.Load('{"format": 1, "entries": [{"root": "", "edition": "missing"}, ' +
      '{"root": "C:\\D", "version": "23.0", "edition": "anders"}, 5]}');
    Assert.AreEqual(0, Integer(mCache.Count));
  finally
    mCache.Free;
  end;
end;

{ TCompilerBackendTests }

procedure TCompilerBackendTests.AutoTakesDccWhenUsable;
var
  mChoice: TCompilerBackendChoice;
begin
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.CommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(mChoice.Backend));
  Assert.AreEqual('Compiler: dcc (Kommandozeile)', mChoice.StatusText);
  Assert.AreEqual('', mChoice.MessageText);
  // Noch nicht geprüft: dcc versuchen; zeigt dcc den Lizenztext, merkt sich das der Server.
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Unknown);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(mChoice.Backend));
end;

procedure TCompilerBackendTests.AutoWithoutDccNamesReasonAndRemedy;
var
  mChoice: TCompilerBackendChoice;
begin
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.NoCommandLine);
  Assert.IsFalse(mChoice.Usable);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(mChoice.Backend));
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', mChoice.StatusText);
  Assert.IsTrue(mChoice.MessageText.StartsWith('Atlas kann nicht kompilieren: '), mChoice.MessageText);
  Assert.IsTrue(Pos('Starter Edition', mChoice.MessageText) > 0, mChoice.MessageText);
  // Ausweg: laufende RAD Studio mit Atlas (build_project) oder ein Kommandozeilen-Compiler (#1904).
  Assert.IsTrue(Pos('build_project', mChoice.Remedy) > 0, 'Ausweg fehlt: ' + mChoice.Remedy);
  Assert.IsTrue(Pos('Kommandozeilen-Compiler', mChoice.Remedy) > 0, mChoice.Remedy);
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Missing);
  Assert.IsFalse(mChoice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', mChoice.StatusText);
end;

procedure TCompilerBackendTests.DccSettingOnStarterIsUnavailable;
var
  mChoice: TCompilerBackendChoice;
begin
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.NoCommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(mChoice.Backend), 'dcc heißt nur dcc');
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', mChoice.StatusText);
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.CommandLine);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(mChoice.Backend));
end;

procedure TCompilerBackendTests.OffSettingIsUnavailable;
var
  mChoice: TCompilerBackendChoice;
begin
  mChoice := TCompilerBackends.Choose(TCompilerBackendSetting.Off, TCompilerEdition.CommandLine);
  Assert.IsFalse(mChoice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (abgeschaltet)', mChoice.StatusText);
  Assert.AreEqual('off', TCompilerBackends.BackendText(mChoice.Backend));
  Assert.AreEqual('auto', TCompilerBackends.SettingText(TCompilerBackendSetting.Auto));
  mChoice := TCompilerBackendChoice.Unavailable('Kein Projekt geladen', '');
  Assert.AreEqual('Atlas kann nicht kompilieren: Kein Projekt geladen.', mChoice.MessageText);
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
