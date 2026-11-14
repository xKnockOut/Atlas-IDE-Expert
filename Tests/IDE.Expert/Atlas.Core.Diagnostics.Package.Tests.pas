unit Atlas.Core.Diagnostics.Package.Tests;

// „Problem melden“ (#766): Zusammenstellung des Diagnosepakets (nur die
// gewählten Teile, feste Reihenfolge, fehlende Dateien fallen weg),
// Anonymisierung (Projektpfade, andere Pfade, Benutzer-, Rechner- und
// Domänenname in jeder Datei, Einstellungen ohne Pfade), Name und Ziel der
// ZIP, Inhalt der ZIP, Issue-Vorlage und Prüfung der Zieladresse; Ziel des
// Knopfs „Atlas-Doku“ (#766).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasDiagnosticPackageTests = class
  private
    FFolder: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BuildTakesOnlySelectedParts;
    [Test]
    procedure BuildSkipsMissingFiles;
    [Test]
    procedure PackageHasNoUserMachineOrProjectPath;
    [Test]
    procedure PluginLogKeepsLastLines;
    [Test]
    procedure SettingsLoseEveryPath;
    [Test]
    procedure PathsAreRecognized;
    [Test]
    procedure ZipNameAndFreeTarget;
    [Test]
    procedure ZipHoldsExactlyThePreview;
    [Test]
    procedure IssueTemplateFollowsSelection;
    [Test]
    procedure OnlyWebAddressesAreAccepted;
    [Test]
    procedure DocsPreferInstalledHtml;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.Zip,
  Atlas.Core.Diagnostics.Package,
  Atlas.Core.Welcome.Help;

const
  cRoot = 'C:\Projekte\Kunde';
  cUser = 'marco';
  cMachine = 'WS-MARCO42';
  cDomain = 'BUERO';

function Joined(const AFiles: TAtlasPackageFiles): string;
var
  mItem: TAtlasPackageFile;
begin
  Result := '';
  for mItem in AFiles do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + mItem.Name;
  end;
end;

function Find(const AFiles: TAtlasPackageFiles; const AName: string; out AFile: TAtlasPackageFile): Boolean;
var
  mItem: TAtlasPackageFile;
begin
  for mItem in AFiles do
  begin
    if mItem.Name = AName then
    begin
      AFile := mItem;
      Exit(True);
    end;
  end;
  AFile := Default(TAtlasPackageFile);
  Result := False;
end;

{ TAtlasDiagnosticPackageTests }

procedure TAtlasDiagnosticPackageTests.Setup;
begin
  FFolder := TPath.Combine(TPath.GetTempPath, 'AtlasPackage' + IntToStr(Random(1000000)));
  ForceDirectories(FFolder);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.log'),
    '2026-10-15 09:00:00.000 Start' + sLineBreak +
    '2026-10-15 09:00:01.000 Datei ' + cRoot + '\Main.pas geöffnet' + sLineBreak +
    '2026-10-15 09:00:02.000 Fehler in "TKundeForm" bei C:\Users\' + cUser + '\AppData\Local\Atlas\cache' + sLineBreak +
    '2026-10-15 09:00:03.000 Rechner ' + cMachine + ', Domäne ' + cDomain + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'diag-20261015-4711.log'),
    '{"t":"2026-10-15T09:00:00","m":"hover","doc":"doc#4","ms":12}' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas-diagnosemodus.txt'),
    '# Diagnosemodus' + sLineBreak + 'Einstellungen: {"ServerPath": "C:\\Users\\' + cUser + '\\Atlas.exe"}' +
    sLineBreak, TEncoding.UTF8);
end;

procedure TAtlasDiagnosticPackageTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
  begin
    TDirectory.Delete(FFolder, True);
  end;
  // Der Leckmonitor misst den Saldo von Setup und TearDown: Zeichenkette freigeben.
  FFolder := '';
end;

function PackageInput(const AFolder: string): TAtlasPackageInput;
begin
  Result := Default(TAtlasPackageInput);
  Result.AtlasVersion := '0.1.0';
  Result.IdeVersion := 'Delphi 13 (37.0)';
  Result.WindowsVersion := 'Windows 11 (Version 10.0, Build 26100, 64-bit Edition)';
  Result.Platform := 'Win32';
  Result.PluginLog := TPath.Combine(AFolder, 'atlas.log');
  Result.ServerLogs := [TPath.Combine(AFolder, 'diag-20261015-4711.log')];
  Result.SettingsJson := '{' + sLineBreak +
    '  "ServerPath": "C:\\Users\\' + cUser + '\\Atlas\\AtlasServer.exe",' + sLineBreak +
    '  "WelcomePageHelpReportFolder": "' + 'C:\\Projekte\\Kunde\\Ablage' + '",' + sLineBreak +
    '  "WelcomePageHelpReportUrl": "https://example.org/' + cUser + '/issues/new",' + sLineBreak +
    '  "WelcomePageWhatsNew": "afterUpdate",' + sLineBreak +
    '  "VisibleRows": 10' + sLineBreak + '}';
  Result.LastDataFile := TPath.Combine(AFolder, 'atlas-diagnosemodus.txt');
  Result.Roots := [cRoot];
  Result.Identity := [cUser, cMachine, cDomain];
  Result.Created := EncodeDate(2026, 10, 15) + EncodeTime(12, 30, 0, 0);
end;

procedure TAtlasDiagnosticPackageTests.BuildTakesOnlySelectedParts;
var
  mInput: TAtlasPackageInput;
  mFiles: TAtlasPackageFiles;
  mItem: TAtlasPackageFile;
begin
  mInput := PackageInput(FFolder);
  Assert.AreEqual('', Joined(TAtlasDiagnosticPackage.Build(mInput, [])), 'nichts gewählt');
  Assert.AreEqual('atlas-info.txt', Joined(TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.Versions])));
  Assert.AreEqual('einstellungen.json',
    Joined(TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.Settings])));
  Assert.AreEqual('plugin/atlas.log,server/diag-20261015-4711.log',
    Joined(TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.Logs])));
  Assert.AreEqual('atlas-diagnosemodus.txt',
    Joined(TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.LastData])));
  mFiles := TAtlasDiagnosticPackage.Build(mInput, TAtlasDiagnosticPackage.cAllParts);
  Assert.AreEqual('atlas-info.txt,einstellungen.json,plugin/atlas.log,server/diag-20261015-4711.log,' +
    'atlas-diagnosemodus.txt', Joined(mFiles), 'feste Reihenfolge');
  Assert.IsTrue(Find(mFiles, 'atlas-info.txt', mItem));
  Assert.Contains(mItem.Text, 'Atlas 0.1.0');
  Assert.Contains(mItem.Text, 'RAD Studio Delphi 13 (37.0)');
  Assert.Contains(mItem.Text, 'Windows Windows 11');
  Assert.Contains(mItem.Text, 'Plattform Win32');
  Assert.AreEqual(Integer(Length(TEncoding.UTF8.GetBytes(mItem.Text))), Integer(mItem.Size), 'Größe = Inhalt');
  Assert.IsTrue(TAtlasDiagnosticPackage.TotalSize(mFiles) > mItem.Size);
  // Versionen ohne Logs: keine Logdatei, auch wenn sie da ist.
  mFiles := TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.Versions, TAtlasPackagePart.Settings]);
  Assert.IsFalse(Find(mFiles, 'plugin/atlas.log', mItem));
  Assert.IsFalse(Find(mFiles, 'atlas-diagnosemodus.txt', mItem));
end;

procedure TAtlasDiagnosticPackageTests.BuildSkipsMissingFiles;
var
  mInput: TAtlasPackageInput;
begin
  mInput := PackageInput(FFolder);
  mInput.PluginLog := TPath.Combine(FFolder, 'fehlt.log');
  mInput.ServerLogs := [TPath.Combine(FFolder, 'diag-fehlt.log'), TPath.Combine(FFolder, 'diag-20261015-4711.log')];
  mInput.LastDataFile := '';
  Assert.AreEqual('server/diag-20261015-4711.log',
    Joined(TAtlasDiagnosticPackage.Build(mInput, TAtlasDiagnosticPackage.cAllParts - [TAtlasPackagePart.Versions,
    TAtlasPackagePart.Settings])), 'nur vorhandene Dateien');
end;

procedure TAtlasDiagnosticPackageTests.PackageHasNoUserMachineOrProjectPath;
var
  mInput: TAtlasPackageInput;
  mFiles: TAtlasPackageFiles;
  mItem: TAtlasPackageFile;
  mText: string;
begin
  mInput := PackageInput(FFolder);
  mFiles := TAtlasDiagnosticPackage.Build(mInput, TAtlasDiagnosticPackage.cAllParts);
  Assert.AreEqual(0, Integer(Length(TAtlasDiagnosticPackage.Leaks(mFiles, mInput.Roots, mInput.Identity))),
    'kein Projektpfad, Benutzer-, Rechner- oder Domänenname');
  for mItem in mFiles do
  begin
    mText := LowerCase(mItem.Text);
    Assert.IsFalse(mText.Contains(LowerCase(cUser)), mItem.Name + ': Benutzername');
    Assert.IsFalse(mText.Contains(LowerCase(cMachine)), mItem.Name + ': Rechnername');
    Assert.IsFalse(mText.Contains(LowerCase(cRoot)), mItem.Name + ': Projektpfad');
    Assert.IsFalse(mText.Contains('c:\users'), mItem.Name + ': Benutzerordner');
  end;
  Assert.IsTrue(Find(mFiles, 'plugin/atlas.log', mItem));
  Assert.Contains(mItem.Text, '<ws>/<datei>.pas', 'Projektpfad gekürzt');
  Assert.Contains(mItem.Text, '<pfad>', 'anderer Pfad ersetzt');
  Assert.Contains(mItem.Text, '<benutzer>', 'Rechnername ersetzt');
  Assert.Contains(mItem.Text, '"<wert>"', 'Text in Anführungszeichen');
  Assert.IsTrue(Find(mFiles, 'atlas-diagnosemodus.txt', mItem));
  Assert.Contains(mItem.Text, '# Diagnosemodus');
  Assert.IsTrue(Find(mFiles, 'server/diag-20261015-4711.log', mItem));
  Assert.Contains(mItem.Text, '"doc":"doc#4"', 'Diagnoselog unverändert');
  // Gegenprobe: Ohne Anonymisierung würde Leaks anschlagen.
  mFiles := [TAtlasPackageFile.Create('roh.txt', TAtlasPackagePart.Logs, 'C:\Projekte\Kunde\Main.pas')];
  Assert.AreEqual('roh.txt', TAtlasDiagnosticPackage.Leaks(mFiles, mInput.Roots, mInput.Identity)[0]);
end;

procedure TAtlasDiagnosticPackageTests.PluginLogKeepsLastLines;
var
  mInput: TAtlasPackageInput;
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mFiles: TAtlasPackageFiles;
  mLines: TArray<string>;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 1 to TAtlasDiagnosticPackage.cPluginLogLines + 5 do
    begin
      mBuilder.Append('Zeile ').Append(mIndex).Append(sLineBreak);
    end;
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.log'), mBuilder.ToString, TEncoding.UTF8);
  finally
    mBuilder.Free;
  end;
  mInput := PackageInput(FFolder);
  mInput.ServerLogs := nil;
  mFiles := TAtlasDiagnosticPackage.Build(mInput, [TAtlasPackagePart.Logs]);
  Assert.AreEqual(1, Integer(Length(mFiles)));
  mLines := mFiles[0].Text.TrimRight.Split([sLineBreak]);
  Assert.AreEqual(TAtlasDiagnosticPackage.cPluginLogLines, Integer(Length(mLines)));
  Assert.AreEqual('Zeile 6', mLines[0], 'die letzten Zeilen');
  Assert.AreEqual('Zeile ' + IntToStr(TAtlasDiagnosticPackage.cPluginLogLines + 5), mLines[High(mLines)]);
end;

procedure TAtlasDiagnosticPackageTests.SettingsLoseEveryPath;
var
  mText: string;
begin
  mText := TAtlasDiagnosticPackage.SettingsWithoutPaths(PackageInput(FFolder).SettingsJson);
  Assert.Contains(mText, '"ServerPath": "<pfad>"');
  Assert.Contains(mText, '"WelcomePageHelpReportFolder": "<pfad>"');
  Assert.Contains(mText, '"WelcomePageWhatsNew": "afterUpdate"', 'kein Pfad');
  Assert.Contains(mText, '"VisibleRows": 10', 'Zahlen bleiben');
  Assert.Contains(mText, '"WelcomePageHelpReportUrl": "https://example.org/', 'Webadresse ist kein Pfad');
  Assert.IsFalse(mText.Contains('Users'), 'Benutzerordner');
  // Escapes, Schlüssel mit Pfadzeichen, UNC und Laufwerk mit Schrägstrich.
  mText := TAtlasDiagnosticPackage.SettingsWithoutPaths(
    '{"a\\b": "x", "Q": "sagt \"hallo\"", "U": "\\\\server\\share", "D": "D:/Ablage", "E": ""}');
  Assert.AreEqual('{"a\\b": "x", "Q": "sagt \"hallo\"", "U": "<pfad>", "D": "<pfad>", "E": ""}', mText);
  // Die Datei im Paket: auch Benutzername in einer Webadresse ersetzt.
  mText := TAtlasDiagnosticPackage.Build(PackageInput(FFolder), [TAtlasPackagePart.Settings])[0].Text;
  Assert.Contains(mText, '"WelcomePageHelpReportUrl": "<wert>"');
end;

procedure TAtlasDiagnosticPackageTests.PathsAreRecognized;
begin
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('C:\Users\marco'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('C:'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('d:/Ablage'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('\\server\share'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('..\Bibliothek'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('/home/marco'));
  Assert.IsTrue(TAtlasDiagnosticPackage.LooksLikePath('file:///C:/x'));
  Assert.IsFalse(TAtlasDiagnosticPackage.LooksLikePath('https://github.com/x'));
  Assert.IsFalse(TAtlasDiagnosticPackage.LooksLikePath('dockWindow'));
  Assert.IsFalse(TAtlasDiagnosticPackage.LooksLikePath(''));
  Assert.IsFalse(TAtlasDiagnosticPackage.LooksLikePath('Ctrl+Shift+A'));
end;

procedure TAtlasDiagnosticPackageTests.ZipNameAndFreeTarget;
var
  mTaken: TArray<string>;
  mTarget: string;
begin
  Assert.AreEqual('Atlas-Diagnose-2026-10-15.zip', TAtlasDiagnosticPackage.ZipName(EncodeDate(2026, 10, 15)));
  mTaken := [IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15.zip',
    IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15-2.zip'];
  mTarget := TAtlasDiagnosticPackage.ZipTarget(FFolder, EncodeDate(2026, 10, 15),
    function(AFileName: string): Boolean
    var
      Name: string;
    begin
      Result := False;
      for Name in mTaken do
      begin
        Result := Result or SameText(Name, AFileName);
      end;
    end);
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15-3.zip', mTarget,
    'vorhandene ZIP wird nicht überschrieben');
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15.zip',
    TAtlasDiagnosticPackage.ZipTarget(FFolder, EncodeDate(2026, 10, 15), nil));
end;

procedure TAtlasDiagnosticPackageTests.ZipHoldsExactlyThePreview;
var
  mFiles: TAtlasPackageFiles;
  mTarget, mName: string;
  mZip: TZipFile;
  mBytes: TBytes;
  mItem: TAtlasPackageFile;
  mNames: TArray<string>;
begin
  mFiles := TAtlasDiagnosticPackage.Build(PackageInput(FFolder), [TAtlasPackagePart.Versions,
    TAtlasPackagePart.Logs]);
  mTarget := TPath.Combine(FFolder, 'paket.zip');
  TAtlasDiagnosticPackage.WriteZip(mFiles, mTarget);
  Assert.IsTrue(FileExists(mTarget));
  mZip := TZipFile.Create;
  try
    mZip.Open(mTarget, TZipMode.zmRead);
    mNames := mZip.FileNames;
    Assert.AreEqual(Integer(Length(mFiles)), Integer(Length(mNames)), 'nur die gewählten Teile');
    for mItem in mFiles do
    begin
      mZip.Read(mItem.Name, mBytes);
      Assert.AreEqual(mItem.Text, TEncoding.UTF8.GetString(mBytes), mItem.Name);
    end;
    for mName in mNames do
    begin
      Assert.IsFalse(mName.Contains('einstellungen') or mName.Contains('diagnosemodus'), mName);
    end;
    mZip.Close;
  finally
    mZip.Free;
  end;
  // Eine vorhandene Datei wird ersetzt, nicht ergänzt.
  TAtlasDiagnosticPackage.WriteZip([mFiles[0]], mTarget);
  mZip := TZipFile.Create;
  try
    mZip.Open(mTarget, TZipMode.zmRead);
    Assert.AreEqual(1, Integer(Length(mZip.FileNames)));
    mZip.Close;
  finally
    mZip.Free;
  end;
end;

procedure TAtlasDiagnosticPackageTests.IssueTemplateFollowsSelection;
var
  mInput: TAtlasPackageInput;
  mText: string;
begin
  mInput := PackageInput(FFolder);
  mText := TAtlasDiagnosticPackage.IssueTemplate('Vervollständigung hängt in ' + cRoot + '\Main.pas', mInput,
    TAtlasDiagnosticPackage.cAllParts, TPath.Combine(FFolder, 'Atlas-Diagnose-2026-10-15.zip'), False);
  Assert.Contains(mText, '## Beschreibung');
  Assert.Contains(mText, 'Vervollständigung hängt in <ws>/<datei>.pas', 'Beschreibung ohne Projektpfad');
  Assert.Contains(mText, '- Atlas: 0.1.0');
  Assert.Contains(mText, '- RAD Studio: Delphi 13 (37.0), Win32');
  Assert.Contains(mText, '- Windows: Windows 11');
  Assert.Contains(mText, '`Atlas-Diagnose-2026-10-15.zip`', 'Hinweis auf das ZIP');
  Assert.IsFalse(mText.Contains(FFolder), 'nur der Dateiname');
  // Ohne Versionen und ohne ZIP.
  mText := TAtlasDiagnosticPackage.IssueTemplate('', mInput, [TAtlasPackagePart.Logs], '', False);
  Assert.Contains(mText, '(nicht angegeben)');
  Assert.IsFalse(mText.Contains('Delphi 13'), 'Versionen nur mit Häkchen');
  Assert.Contains(mText, 'Kein Diagnosepaket angelegt.');
  Assert.Contains(mText, '(Was ist passiert?', 'Platzhalter für die Beschreibung');
  // Englisch.
  mText := TAtlasDiagnosticPackage.IssueTemplate('Hangs', mInput, TAtlasDiagnosticPackage.cAllParts,
    'Atlas-Diagnose-2026-10-15.zip', True);
  Assert.Contains(mText, '## Description');
  Assert.Contains(mText, '## Versions');
  Assert.Contains(mText, 'please attach it to this issue');
end;

procedure TAtlasDiagnosticPackageTests.OnlyWebAddressesAreAccepted;
begin
  Assert.IsTrue(TAtlasDiagnosticPackage.IsWebUrl('https://github.com/xKnockOut/Atlas-IDE-Expert/issues/new'));
  Assert.IsTrue(TAtlasDiagnosticPackage.IsWebUrl('http://youtrack.firma.local/newIssue?project=ATL'));
  Assert.IsTrue(TAtlasDiagnosticPackage.IsWebUrl('HTTPS://example.org'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('https://'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('https:///pfad'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('https://example.org/a b'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('file:///C:/Windows/System32/cmd.exe'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('C:\Windows\System32\cmd.exe'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('javascript:alert(1)'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl('https://example.org/"&calc'));
  Assert.IsFalse(TAtlasDiagnosticPackage.IsWebUrl(''));
end;

procedure TAtlasDiagnosticPackageTests.DocsPreferInstalledHtml;
var
  mInstall, mPlugin, mLocal: string;
  mExists: TFunc<string, Boolean>;
begin
  mInstall := IncludeTrailingPathDelimiter(FFolder);
  mPlugin := mInstall + 'Win32' + PathDelim;
  mLocal := mInstall + TAtlasHelp.cDocsFolder + PathDelim + TAtlasHelp.cDocsIndex;
  mExists :=
    function(AFileName: string): Boolean
    begin
      Result := SameText(AFileName, mLocal);
    end;
  // BPL in Win32\, Doku eine Ebene darüber.
  Assert.AreEqual(mLocal, TAtlasHelp.DocsTarget(mPlugin, mExists));
  // BPL direkt im Installationsordner.
  Assert.AreEqual(mLocal, TAtlasHelp.DocsTarget(mInstall, mExists));
  // Ohne Installation: Doku-Seite des Repositorys.
  Assert.AreEqual(TAtlasHelp.cDocsUrl, TAtlasHelp.DocsTarget(mPlugin,
    function(AFileName: string): Boolean
    begin
      Result := False;
    end));
  Assert.AreEqual(TAtlasHelp.cDocsUrl, TAtlasHelp.DocsTarget('', mExists));
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Docs, False));
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Report, False));
  Assert.IsFalse(TAtlasHelp.Enabled(TAtlasHelpButton.Keys, False), 'ohne Übersicht (#520)');
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Keys, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDiagnosticPackageTests);

end.
