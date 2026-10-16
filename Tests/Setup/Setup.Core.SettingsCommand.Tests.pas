unit Setup.Core.SettingsCommand.Tests;

// Kommandozeile des Installers für Einstellungen (#723) gegen die Attrappe des
// Systems: Schalter lesen, exportieren ohne Benutzerpfade, importieren mit
// Sicherung, eingebaute Profile, Zurücksetzen je Bereich und alles, Fehlerfälle.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSetupSettingsCommandTests = class
  public
    [Test]
    procedure ParsesCommandsAndSwitches;
    [Test]
    procedure ReportsUsageErrors;
    [Test]
    procedure ExportWritesChangedValuesOnly;
    [Test]
    procedure ImportAppliesWithBackup;
    [Test]
    procedure ImportWithoutBackupWhenSwitchedOff;
    [Test]
    procedure ImportsBuiltInProfile;
    [Test]
    procedure ImportReportsMissingAndInvalidFile;
    [Test]
    procedure ResetPerAreaAndAll;
    [Test]
    procedure MessagesInBothLanguages;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Setup.Core.Contract,
  Setup.Core.SettingsCommand,
  Setup.Core.Installer.Tests,
  Setup.Shell.Texts,
  Atlas.Core.Settings.Transfer;

const
  Roaming = 'C:\Users\Ich\AppData\Roaming\Atlas';
  Key = TSetupSettingsCommand.PluginKey;

function Macros: TAtlasSettingsEnvironment;
begin
  Result :=
    function(const AName: string): string
    begin
      Result := '';
      if SameText(AName, 'APPDATA') then
        Result := 'C:\Users\Ich\AppData\Roaming'
      else if SameText(AName, 'LOCALAPPDATA') then
        Result := 'C:\Users\Ich\AppData\Local'
      else if SameText(AName, 'USERPROFILE') then
        Result := 'C:\Users\Ich'
      else if SameText(AName, 'USERNAME') then
        Result := 'Ich';
    end;
end;

function Moment: TDateTime;
begin
  Result := EncodeDateTime(2026, 10, 16, 14, 25, 3, 0);
end;

function Run(const ASystem: ISetupSystem; const AArgs: TArray<string>): TSetupSettingsResult;
begin
  Result := TSetupSettingsCommand.Run(ASystem, TSetupSettingsCommand.Parse(AArgs), Roaming, Macros, Moment);
end;

function Settings(const ABody: string): string;
begin
  Result := '{"format":"atlas-settings","formatVersion":1,"schemaVersion":1,"settings":{' + ABody + '}}';
end;

function Contains(const AList: TArray<string>; const AText: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in AList do
    if SameText(Item, AText) then
      Exit(True);
end;

procedure TSetupSettingsCommandTests.ParsesCommandsAndSwitches;
var
  Request: TSetupSettingsRequest;
begin
  Assert.IsFalse(TSetupSettingsCommand.Requested(['/uninstall']));
  Assert.IsTrue(TSetupSettingsCommand.Requested(['/EXPORTSETTINGS', 'a.json']), 'ohne Groß-/Kleinschreibung');
  Request := TSetupSettingsCommand.Parse(['/exportSettings', 'D:\a.json', '/areas:editor, build', '/secrets:placeholder',
    '/quiet']);
  Assert.IsTrue(Request.Action = TSetupSettingsAction.ExportSettings);
  Assert.AreEqual('D:\a.json', Request.FileName);
  Assert.AreEqual(2, Integer(Length(Request.Areas)));
  Assert.AreEqual('build', Request.Areas[1]);
  Assert.AreEqual('placeholder', Request.Secrets);
  Assert.IsTrue(Request.Quiet);
  Assert.AreEqual('', Request.Error);
  Request := TSetupSettingsCommand.Parse(['/importSettings', 'minimal', '/replace']);
  Assert.IsTrue(Request.Action = TSetupSettingsAction.ImportSettings);
  Assert.AreEqual('minimal', Request.FileName);
  Assert.IsTrue(Request.Replace);
  Request := TSetupSettingsCommand.Parse(['/resetSettings']);
  Assert.IsTrue(Request.Action = TSetupSettingsAction.ResetSettings);
  Assert.AreEqual('', Request.Error);
end;

procedure TSetupSettingsCommandTests.ReportsUsageErrors;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Assert.AreEqual('/exportSettings', TSetupSettingsCommand.Parse(['/exportSettings']).Error, 'Datei fehlt');
  Assert.AreEqual('/importSettings', TSetupSettingsCommand.Parse(['/importSettings', '/replace']).Error);
  Assert.AreEqual('/bunt', TSetupSettingsCommand.Parse(['/resetSettings', '/bunt']).Error);
  Assert.AreEqual('/secrets:immer', TSetupSettingsCommand.Parse(['/exportSettings', 'a', '/secrets:immer']).Error);
  Assert.AreEqual('/replace /merge', TSetupSettingsCommand.Parse(['/importSettings', 'a', '/replace', '/merge']).Error);
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Result_ := Run(System_, ['/resetSettings', '/bunt']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Usage);
  Assert.AreEqual(1, Result_.ExitCode);
  Result_ := Run(System_, ['/resetSettings', '/areas:mond']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Usage, 'unbekannter Bereich');
  Assert.AreEqual('/areas:mond', Result_.Detail);
end;

procedure TSetupSettingsCommandTests.ExportWritesChangedValuesOnly;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
  Text: string;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Sys.WriteInteger(Key, 'Notes', 0);
  Sys.WriteInteger(Key, 'TestsAfterBuild', 0);
  Result_ := Run(System_, ['/exportSettings', 'D:\Team\atlas-settings.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual(0, Result_.ExitCode);
  Text := Sys.ReadText('D:\Team\atlas-settings.json');
  Assert.IsTrue(Text.Contains('"notes.enabled": false'), Text);
  Assert.IsFalse(Text.Contains('tests.afterBuild'), 'Standardwert fehlt');
  Assert.IsTrue(Text.Contains('"atlasVersion"'));
  Assert.IsTrue(Text.Contains('"schemaVersion"'));
  Assert.IsFalse(Text.Contains('C:\\Users\\Ich'), 'kein Benutzerpfad');
  Assert.IsTrue(Text.Contains(#13#10), 'CRLF');
  Assert.IsTrue(Result_.Count >= 1);
  // Nur gewählte Bereiche.
  Result_ := Run(System_, ['/exportSettings', 'D:\Team\build.json', '/areas:build']);
  Assert.IsFalse(Sys.ReadText('D:\Team\build.json').Contains('notes.enabled'));
end;

procedure TSetupSettingsCommandTests.ImportAppliesWithBackup;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Sys.WriteText('D:\a.json', Settings('"notes.enabled": false, "tests.afterBuild": true, "gibt.esNicht": 1'));
  Result_ := Run(System_, ['/importSettings', 'D:\a.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual(2, Result_.Count);
  Assert.AreEqual('0', Sys.ReadString(Key, 'Notes'));
  Assert.AreEqual('1', Sys.ReadString(Key, 'TestsAfterBuild'));
  Assert.IsTrue(Contains(Result_.Skipped, 'gibt.esNicht'), 'Unbekanntes gemeldet und übersprungen');
  Assert.AreEqual(Roaming + '\Backups\atlas-settings-20261016-142503.json', Result_.BackupFile);
  Assert.IsTrue(Sys.FileExists(Result_.BackupFile), 'Sicherung vor dem Import');
  // Ersetzen: was in der Datei fehlt, geht auf den Standard.
  Sys.WriteText('D:\b.json', Settings('"tests.afterBuild": true'));
  Result_ := Run(System_, ['/importSettings', 'D:\b.json', '/replace']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual('1', Sys.ReadString(Key, 'Notes'), 'zurück auf den Standard');
  // Nochmals dasselbe: nichts zu tun.
  Result_ := Run(System_, ['/importSettings', 'D:\b.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Nothing);
  Assert.AreEqual(0, Result_.ExitCode);
end;

procedure TSetupSettingsCommandTests.ImportWithoutBackupWhenSwitchedOff;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Sys.WriteInteger(Key, 'SettingsBackupBeforeImport', 0);
  Sys.WriteText('D:\a.json', Settings('"notes.enabled": false'));
  Result_ := Run(System_, ['/importSettings', 'D:\a.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual('', Result_.BackupFile);
  Assert.AreEqual(0, Integer(Length(Sys.FilesIn(Roaming + '\Backups'))));
end;

procedure TSetupSettingsCommandTests.ImportsBuiltInProfile;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Result_ := Run(System_, ['/importSettings', 'minimal']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual('0', Sys.ReadString(Key, 'Notes'), 'Minimal schaltet Notizen ab');
  Result_ := Run(System_, ['/importSettings', 'atlas-standard']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual('1', Sys.ReadString(Key, 'Notes'), 'Atlas-Standard setzt alles zurück');
end;

procedure TSetupSettingsCommandTests.ImportReportsMissingAndInvalidFile;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Result_ := Run(System_, ['/importSettings', 'D:\fehlt.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.FileMissing);
  Assert.AreEqual(2, Result_.ExitCode);
  Sys.WriteText('D:\kaputt.json', '{"format":"anderes"}');
  Result_ := Run(System_, ['/importSettings', 'D:\kaputt.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.FileInvalid);
  Assert.IsTrue(Result_.Detail <> '');
  Assert.AreEqual(0, Integer(Length(Sys.ValueNames(Key))), 'nichts geschrieben');
  // Gesperrtes Ziel: Fehler mit Grund.
  Sys.LockedFile := 'D:\gesperrt.json';
  Result_ := Run(System_, ['/exportSettings', 'D:\gesperrt.json']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Failed);
  Assert.AreEqual(3, Result_.ExitCode);
end;

procedure TSetupSettingsCommandTests.ResetPerAreaAndAll;
var
  Sys: TFakeSystem;
  System_: ISetupSystem;
  Result_: TSetupSettingsResult;
begin
  Sys := TFakeSystem.Create;
  System_ := Sys;
  Sys.WriteInteger(Key, 'Notes', 0);
  Sys.WriteInteger(Key, 'TestsAfterBuild', 1);
  Result_ := Run(System_, ['/resetSettings', '/areas:build']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual(1, Result_.Count);
  Assert.AreEqual('0', Sys.ReadString(Key, 'TestsAfterBuild'), 'Bereich Build zurückgesetzt');
  Assert.AreEqual('0', Sys.ReadString(Key, 'Notes'), 'Editor bleibt');
  Assert.IsTrue(Sys.FileExists(Result_.BackupFile));
  Result_ := Run(System_, ['/resetSettings']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Done, Result_.Detail);
  Assert.AreEqual('1', Sys.ReadString(Key, 'Notes'), 'alles zurückgesetzt');
  Result_ := Run(System_, ['/resetSettings']);
  Assert.IsTrue(Result_.Outcome = TSetupSettingsOutcome.Nothing, 'schon Standard');
end;

procedure TSetupSettingsCommandTests.MessagesInBothLanguages;
var
  Language: TSetupLanguage;
  Result_: TSetupSettingsResult;
  Outcome: TSetupSettingsOutcome;
  Action: TSetupSettingsAction;
begin
  for Language := Low(TSetupLanguage) to High(TSetupLanguage) do
  begin
    TSetupTexts.Language := Language;
    for Action := TSetupSettingsAction.ExportSettings to High(TSetupSettingsAction) do
      for Outcome := Low(TSetupSettingsOutcome) to High(TSetupSettingsOutcome) do
      begin
        Result_ := Default(TSetupSettingsResult);
        Result_.Action := Action;
        Result_.Outcome := Outcome;
        Assert.IsTrue(TSetupTexts.SettingsMessage(Result_) <> '');
      end;
  end;
  TSetupTexts.Language := TSetupLanguage.German;
  Result_ := Default(TSetupSettingsResult);
  Result_.Action := TSetupSettingsAction.ImportSettings;
  Result_.Outcome := TSetupSettingsOutcome.Done;
  Result_.Count := 3;
  Result_.Skipped := ['gibt.esNicht'];
  Result_.BackupFile := 'B.json';
  Assert.AreEqual('3 Einstellungen importiert.' + sLineBreak +
    'Übersprungen (unbekannt, ungültig oder Zugangsdaten): gibt.esNicht' + sLineBreak + 'Sicherung: B.json' +
    sLineBreak + 'Eine laufende IDE übernimmt die Werte erst beim nächsten Start.', TSetupTexts.SettingsMessage(Result_));
end;

initialization
  TDUnitX.RegisterTestFixture(TSetupSettingsCommandTests);

end.
