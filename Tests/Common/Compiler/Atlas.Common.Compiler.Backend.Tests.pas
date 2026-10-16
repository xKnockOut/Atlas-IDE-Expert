unit Atlas.Common.Compiler.Backend.Tests;

// Tests für Kompilieren ohne Kommandozeilen-Compiler (#261): Erkennen der
// Ausgabe (Starter Edition), Zwischenspeicher je Installation, Wahl des Wegs
// zum Compiler mit Grund und Ausweg, Aufrufe von cc.ps1 und Meldungen aus
// dessen logFile. Testdaten in Tests\Data\Compiler: dcc32-starter.txt (Ausgabe
// von dcc32 der Starter Edition ohne Argumente) und cc-build.log (logFile von
// cc.ps1 build).

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
    procedure AutoFallsBackToIde;
    [Test]
    procedure AutoWithoutIdeNamesReasonAndRemedy;
    [Test]
    procedure DccSettingOnStarterIsUnavailable;
    [Test]
    procedure IdeSettingNeedsScript;
    [Test]
    procedure OffSettingIsUnavailable;
    [Test]
    procedure OnlyDccRunsOnSave;
  end;

  [TestFixture]
  TCompilerIdeCommandTests = class
  public
    [Test]
    procedure BuildsArgumentsWithInstance;
    [Test]
    procedure ReadsPidOfStartedIde;
    [Test]
    procedure ReadsBuildAnswer;
    [Test]
    procedure RejectsAnswerWithoutJson;
    [Test]
    procedure ReadsMessagesFromRecordedLog;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Compiler.Edition,
  Atlas.Common.Compiler.Backend,
  Atlas.Common.Compiler.IdeCommand;

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
      Exit(TFile.ReadAllLines(FileName, TEncoding.UTF8));
    if ExtractFileDir(Directory) = Directory then
      Break;
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
    Assert.AreEqual(2, Cache.Count);
    Loaded.Load(Cache.ToJson);
    Assert.AreEqual(2, Loaded.Count);
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
    Assert.AreEqual(0, Cache.Count);
    // Ohne Wurzel, ohne bekannte Ausgabe oder kein Objekt: übergangen.
    Cache.Load('{"format": 1, "entries": [{"root": "", "edition": "missing"}, ' +
      '{"root": "C:\\D", "version": "23.0", "edition": "anders"}, 5]}');
    Assert.AreEqual(0, Cache.Count);
  finally
    Cache.Free;
  end;
end;

{ TCompilerBackendTests }

procedure TCompilerBackendTests.AutoTakesDccWhenUsable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.CommandLine, '', False);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
  Assert.AreEqual('Compiler: dcc (Kommandozeile)', Choice.StatusText);
  Assert.AreEqual('', Choice.MessageText);
  // Noch nicht geprüft: dcc versuchen; zeigt dcc den Lizenztext, merkt sich das der Server.
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Unknown, 'C:\cc.ps1', True);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
end;

procedure TCompilerBackendTests.AutoFallsBackToIde;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.NoCommandLine, 'C:\cc.ps1', True);
  Assert.AreEqual(Ord(TCompilerBackend.Ide), Ord(Choice.Backend));
  Assert.IsTrue(Choice.Usable);
  Assert.IsTrue(Pos('cc.ps1', Choice.StatusText) > 0, Choice.StatusText);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Missing, 'C:\cc.ps1', True);
  Assert.AreEqual(Ord(TCompilerBackend.Ide), Ord(Choice.Backend));
end;

procedure TCompilerBackendTests.AutoWithoutIdeNamesReasonAndRemedy;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.NoCommandLine, '', False);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Assert.IsTrue(Choice.MessageText.StartsWith('Atlas kann nicht kompilieren: '), Choice.MessageText);
  Assert.IsTrue(Pos('Starter Edition', Choice.MessageText) > 0, Choice.MessageText);
  Assert.IsTrue(Pos('compiler.ideCommand', Choice.MessageText) > 0, 'Ausweg fehlt: ' + Choice.MessageText);
  // cc.ps1 eingetragen, aber nicht da: beide Gründe.
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Auto, TCompilerEdition.Missing, 'C:\fehlt.ps1', False);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Assert.IsTrue(Pos('keine vorhandene Datei', Choice.Reason) > 0, Choice.Reason);
end;

procedure TCompilerBackendTests.DccSettingOnStarterIsUnavailable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.NoCommandLine, 'C:\cc.ps1', True);
  Assert.AreEqual(Ord(TCompilerBackend.Off), Ord(Choice.Backend), 'dcc heißt nur dcc, auch mit cc.ps1');
  Assert.AreEqual('Compiler: nicht verfügbar (Starter Edition)', Choice.StatusText);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Dcc, TCompilerEdition.CommandLine, '', False);
  Assert.AreEqual(Ord(TCompilerBackend.Dcc), Ord(Choice.Backend));
end;

procedure TCompilerBackendTests.IdeSettingNeedsScript;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Ide, TCompilerEdition.CommandLine, '', False);
  Assert.IsFalse(Choice.Usable);
  Assert.AreEqual('Compiler: nicht verfügbar (compiler.ideCommand fehlt)', Choice.StatusText);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Ide, TCompilerEdition.CommandLine, 'C:\x.ps1', False);
  Assert.AreEqual('Compiler: nicht verfügbar (cc.ps1 nicht gefunden)', Choice.StatusText);
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Ide, TCompilerEdition.CommandLine, 'C:\cc.ps1', True);
  Assert.AreEqual(Ord(TCompilerBackend.Ide), Ord(Choice.Backend), 'ide auch mit dcc');
end;

procedure TCompilerBackendTests.OffSettingIsUnavailable;
var
  Choice: TCompilerBackendChoice;
begin
  Choice := TCompilerBackends.Choose(TCompilerBackendSetting.Off, TCompilerEdition.CommandLine, 'C:\cc.ps1', True);
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
  // Die eigene IDE ist langsam: nur auf den Befehl „Projekt kompilieren“.
  Assert.IsFalse(TCompilerBackends.RunsOnSave(TCompilerBackend.Ide));
  Assert.IsFalse(TCompilerBackends.RunsOnSave(TCompilerBackend.Off));
end;

{ TCompilerIdeCommandTests }

procedure TCompilerIdeCommandTests.BuildsArgumentsWithInstance;
var
  Request: TCompilerRequest;
  Arguments: TArray<string>;
begin
  Arguments := TCompilerIdeCommand.StartArguments('C:\P\App.dproj');
  Assert.AreEqual('start', Arguments[0]);
  Assert.AreEqual('C:\P\App.dproj', Arguments[2]);
  Assert.AreEqual('180', Arguments[4]);
  Arguments := TCompilerIdeCommand.BuildArguments(4711, 'C:\P\App.dproj', 'Win64');
  Assert.AreEqual('build -Instance 4711 -Project C:\P\App.dproj -Platform Win64 -Json', string.Join(' ', Arguments));
  Arguments := TCompilerIdeCommand.BuildArguments(4711, 'C:\P\App.dproj', '');
  Assert.AreEqual('build -Instance 4711 -Project C:\P\App.dproj -Json', string.Join(' ', Arguments));
  Assert.AreEqual('quit -Instance 4711', string.Join(' ', TCompilerIdeCommand.QuitArguments(4711)));
  Request := TCompilerIdeCommand.Request('C:\pwsh.exe', 'C:\T\cc.ps1', TCompilerIdeCommand.QuitArguments(1), 'C:\P');
  Assert.AreEqual('C:\pwsh.exe', Request.Executable);
  Assert.AreEqual('C:\P', Request.WorkingDir);
  Assert.AreEqual('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File C:\T\cc.ps1 quit -Instance 1',
    string.Join(' ', Request.Arguments));
end;

procedure TCompilerIdeCommandTests.ReadsPidOfStartedIde;
var
  Pid: Cardinal;
begin
  Assert.IsTrue(TCompilerIdeCommand.ParsePid(TArray<string>.Create('Starte IDE …', 'IDE started : pid 1234'), Pid));
  Assert.AreEqual(Cardinal(1234), Pid);
  Assert.IsTrue(TCompilerIdeCommand.ParsePid(TArray<string>.Create('PID: 77'), Pid));
  Assert.AreEqual(Cardinal(77), Pid);
  Assert.IsTrue(TCompilerIdeCommand.ParsePid(TArray<string>.Create('pid=5'), Pid));
  Assert.AreEqual(Cardinal(5), Pid);
  Assert.IsFalse(TCompilerIdeCommand.ParsePid(TArray<string>.Create('IDE start failed', 'pid unbekannt'), Pid));
  Assert.AreEqual(Cardinal(0), Pid);
end;

procedure TCompilerIdeCommandTests.ReadsBuildAnswer;
var
  Report: TIdeBuildReport;
begin
  Assert.IsTrue(TCompilerIdeCommand.ParseBuild(TArray<string>.Create('Baue App.dproj …',
    '{', '  "ok": false,', '  "outputWritten": false,', '  "logFile": "C:\\Temp\\cc\\build.log"', '}'), Report));
  Assert.IsFalse(Report.Ok);
  Assert.IsFalse(Report.OutputWritten);
  Assert.AreEqual('C:\Temp\cc\build.log', Report.LogFile);
  Assert.IsTrue(TCompilerIdeCommand.ParseBuild(TArray<string>.Create(
    '{"ok": true, "outputWritten": true, "logFile": ""}'), Report));
  Assert.IsTrue(Report.Ok);
  Assert.IsTrue(Report.OutputWritten);
  Assert.IsTrue(TCompilerIdeCommand.ParseBuild(TArray<string>.Create('{"ok": false, "message": "Instanz weg"}'), Report));
  Assert.AreEqual('Instanz weg', Report.Error);
end;

procedure TCompilerIdeCommandTests.RejectsAnswerWithoutJson;
var
  Report: TIdeBuildReport;
begin
  Assert.IsFalse(TCompilerIdeCommand.ParseBuild(TArray<string>.Create('Fehler: keine IDE'), Report));
  Assert.IsFalse(TCompilerIdeCommand.ParseBuild(nil, Report));
  Assert.IsFalse(TCompilerIdeCommand.ParseBuild(TArray<string>.Create('{kaputt'), Report));
end;

procedure TCompilerIdeCommandTests.ReadsMessagesFromRecordedLog;
var
  Messages: TArray<TCompilerMessage>;
begin
  // Erwartet: Datei (relativ zum Projektordner), Zeile und Spalte (0-basiert), Code, Schweregrad.
  Messages := TCompilerIdeCommand.Messages(DataLines('cc-build.log'), 'C:\Projekte\App\App.dproj');
  Assert.AreEqual(4, Integer(Length(Messages)));
  Assert.AreEqual('C:\Projekte\App\Main.pas', Messages[0].FileName);
  Assert.AreEqual(11, Messages[0].Line);
  Assert.AreEqual('E2003', Messages[0].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Error), Ord(Messages[0].Severity));
  Assert.AreEqual('Undeklarierter Bezeichner: ''Foo''', Messages[0].Text);
  Assert.AreEqual(19, Messages[1].Line);
  Assert.AreEqual(6, Messages[1].Column);
  Assert.AreEqual('W1036', Messages[1].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Warning), Ord(Messages[1].Severity));
  Assert.AreEqual('C:\Projekte\App\Lib\Hilfe.pas', Messages[2].FileName);
  Assert.AreEqual(Ord(TCompilerSeverity.Hint), Ord(Messages[2].Severity));
  Assert.AreEqual('C:\Projekte\App\App.dpr', Messages[3].FileName);
  Assert.AreEqual('F2063', Messages[3].Code);
  Assert.AreEqual(Ord(TCompilerSeverity.Fatal), Ord(Messages[3].Severity));
end;

initialization
  TDUnitX.RegisterTestFixture(TCompilerEditionTests);
  TDUnitX.RegisterTestFixture(TCompilerBackendTests);
  TDUnitX.RegisterTestFixture(TCompilerIdeCommandTests);

end.
