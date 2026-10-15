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
  Root = 'C:\Projekte\Kunde';
  User = 'marco';
  Machine = 'WS-MARCO42';
  Domain = 'BUERO';

function Joined(const AFiles: TAtlasPackageFiles): string;
var
  Item: TAtlasPackageFile;
begin
  Result := '';
  for Item in AFiles do
  begin
    if Result <> '' then
      Result := Result + ',';
    Result := Result + Item.Name;
  end;
end;

function Find(const AFiles: TAtlasPackageFiles; const AName: string; out AFile: TAtlasPackageFile): Boolean;
var
  Item: TAtlasPackageFile;
begin
  for Item in AFiles do
    if Item.Name = AName then
    begin
      AFile := Item;
      Exit(True);
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
    '2026-10-15 09:00:01.000 Datei ' + Root + '\Main.pas geöffnet' + sLineBreak +
    '2026-10-15 09:00:02.000 Fehler in "TKundeForm" bei C:\Users\' + User + '\AppData\Local\Atlas\cache' + sLineBreak +
    '2026-10-15 09:00:03.000 Rechner ' + Machine + ', Domäne ' + Domain + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'diag-20261015-4711.log'),
    '{"t":"2026-10-15T09:00:00","m":"hover","doc":"doc#4","ms":12}' + sLineBreak, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(FFolder, 'atlas-diagnosemodus.txt'),
    '# Diagnosemodus' + sLineBreak + 'Einstellungen: {"ServerPath": "C:\\Users\\' + User + '\\Atlas.exe"}' +
    sLineBreak, TEncoding.UTF8);
end;

procedure TAtlasDiagnosticPackageTests.TearDown;
begin
  if TDirectory.Exists(FFolder) then
    TDirectory.Delete(FFolder, True);
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
    '  "ServerPath": "C:\\Users\\' + User + '\\Atlas\\AtlasServer.exe",' + sLineBreak +
    '  "WelcomePageHelpReportFolder": "' + 'C:\\Projekte\\Kunde\\Ablage' + '",' + sLineBreak +
    '  "WelcomePageHelpReportUrl": "https://example.org/' + User + '/issues/new",' + sLineBreak +
    '  "WelcomePageHost": "dockWindow",' + sLineBreak +
    '  "VisibleRows": 10' + sLineBreak + '}';
  Result.LastDataFile := TPath.Combine(AFolder, 'atlas-diagnosemodus.txt');
  Result.Roots := [Root];
  Result.Identity := [User, Machine, Domain];
  Result.Created := EncodeDate(2026, 10, 15) + EncodeTime(12, 30, 0, 0);
end;

procedure TAtlasDiagnosticPackageTests.BuildTakesOnlySelectedParts;
var
  Input: TAtlasPackageInput;
  Files: TAtlasPackageFiles;
  Item: TAtlasPackageFile;
begin
  Input := PackageInput(FFolder);
  Assert.AreEqual('', Joined(TAtlasDiagnosticPackage.Build(Input, [])), 'nichts gewählt');
  Assert.AreEqual('atlas-info.txt', Joined(TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.Versions])));
  Assert.AreEqual('einstellungen.json',
    Joined(TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.Settings])));
  Assert.AreEqual('plugin/atlas.log,server/diag-20261015-4711.log',
    Joined(TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.Logs])));
  Assert.AreEqual('atlas-diagnosemodus.txt',
    Joined(TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.LastData])));
  Files := TAtlasDiagnosticPackage.Build(Input, TAtlasDiagnosticPackage.AllParts);
  Assert.AreEqual('atlas-info.txt,einstellungen.json,plugin/atlas.log,server/diag-20261015-4711.log,' +
    'atlas-diagnosemodus.txt', Joined(Files), 'feste Reihenfolge');
  Assert.IsTrue(Find(Files, 'atlas-info.txt', Item));
  Assert.Contains(Item.Text, 'Atlas 0.1.0');
  Assert.Contains(Item.Text, 'RAD Studio Delphi 13 (37.0)');
  Assert.Contains(Item.Text, 'Windows Windows 11');
  Assert.Contains(Item.Text, 'Plattform Win32');
  Assert.AreEqual(Integer(Length(TEncoding.UTF8.GetBytes(Item.Text))), Integer(Item.Size), 'Größe = Inhalt');
  Assert.IsTrue(TAtlasDiagnosticPackage.TotalSize(Files) > Item.Size);
  // Versionen ohne Logs: keine Logdatei, auch wenn sie da ist.
  Files := TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.Versions, TAtlasPackagePart.Settings]);
  Assert.IsFalse(Find(Files, 'plugin/atlas.log', Item));
  Assert.IsFalse(Find(Files, 'atlas-diagnosemodus.txt', Item));
end;

procedure TAtlasDiagnosticPackageTests.BuildSkipsMissingFiles;
var
  Input: TAtlasPackageInput;
begin
  Input := PackageInput(FFolder);
  Input.PluginLog := TPath.Combine(FFolder, 'fehlt.log');
  Input.ServerLogs := [TPath.Combine(FFolder, 'diag-fehlt.log'), TPath.Combine(FFolder, 'diag-20261015-4711.log')];
  Input.LastDataFile := '';
  Assert.AreEqual('server/diag-20261015-4711.log',
    Joined(TAtlasDiagnosticPackage.Build(Input, TAtlasDiagnosticPackage.AllParts - [TAtlasPackagePart.Versions,
    TAtlasPackagePart.Settings])), 'nur vorhandene Dateien');
end;

procedure TAtlasDiagnosticPackageTests.PackageHasNoUserMachineOrProjectPath;
var
  Input: TAtlasPackageInput;
  Files: TAtlasPackageFiles;
  Item: TAtlasPackageFile;
  Text: string;
begin
  Input := PackageInput(FFolder);
  Files := TAtlasDiagnosticPackage.Build(Input, TAtlasDiagnosticPackage.AllParts);
  Assert.AreEqual(0, Integer(Length(TAtlasDiagnosticPackage.Leaks(Files, Input.Roots, Input.Identity))),
    'kein Projektpfad, Benutzer-, Rechner- oder Domänenname');
  for Item in Files do
  begin
    Text := LowerCase(Item.Text);
    Assert.IsFalse(Text.Contains(LowerCase(User)), Item.Name + ': Benutzername');
    Assert.IsFalse(Text.Contains(LowerCase(Machine)), Item.Name + ': Rechnername');
    Assert.IsFalse(Text.Contains(LowerCase(Root)), Item.Name + ': Projektpfad');
    Assert.IsFalse(Text.Contains('c:\users'), Item.Name + ': Benutzerordner');
  end;
  Assert.IsTrue(Find(Files, 'plugin/atlas.log', Item));
  Assert.Contains(Item.Text, '<ws>\Main.pas', 'Projektpfad gekürzt');
  Assert.Contains(Item.Text, '<pfad>', 'anderer Pfad ersetzt');
  Assert.Contains(Item.Text, '<benutzer>', 'Rechnername ersetzt');
  Assert.Contains(Item.Text, '"<wert>"', 'Text in Anführungszeichen');
  Assert.IsTrue(Find(Files, 'atlas-diagnosemodus.txt', Item));
  Assert.Contains(Item.Text, '# Diagnosemodus');
  Assert.IsTrue(Find(Files, 'server/diag-20261015-4711.log', Item));
  Assert.Contains(Item.Text, '"doc":"doc#4"', 'Diagnoselog unverändert');
  // Gegenprobe: Ohne Anonymisierung würde Leaks anschlagen.
  Files := [TAtlasPackageFile.Create('roh.txt', TAtlasPackagePart.Logs, 'C:\Projekte\Kunde\Main.pas')];
  Assert.AreEqual('roh.txt', TAtlasDiagnosticPackage.Leaks(Files, Input.Roots, Input.Identity)[0]);
end;

procedure TAtlasDiagnosticPackageTests.PluginLogKeepsLastLines;
var
  Input: TAtlasPackageInput;
  Builder: TStringBuilder;
  Index: Integer;
  Files: TAtlasPackageFiles;
  Lines: TArray<string>;
begin
  Builder := TStringBuilder.Create;
  try
    for Index := 1 to TAtlasDiagnosticPackage.PluginLogLines + 5 do
      Builder.Append('Zeile ').Append(Index).Append(sLineBreak);
    TFile.WriteAllText(TPath.Combine(FFolder, 'atlas.log'), Builder.ToString, TEncoding.UTF8);
  finally
    Builder.Free;
  end;
  Input := PackageInput(FFolder);
  Input.ServerLogs := nil;
  Files := TAtlasDiagnosticPackage.Build(Input, [TAtlasPackagePart.Logs]);
  Assert.AreEqual(1, Integer(Length(Files)));
  Lines := Files[0].Text.TrimRight.Split([sLineBreak]);
  Assert.AreEqual(TAtlasDiagnosticPackage.PluginLogLines, Integer(Length(Lines)));
  Assert.AreEqual('Zeile 6', Lines[0], 'die letzten Zeilen');
  Assert.AreEqual('Zeile ' + IntToStr(TAtlasDiagnosticPackage.PluginLogLines + 5), Lines[High(Lines)]);
end;

procedure TAtlasDiagnosticPackageTests.SettingsLoseEveryPath;
var
  Text: string;
begin
  Text := TAtlasDiagnosticPackage.SettingsWithoutPaths(PackageInput(FFolder).SettingsJson);
  Assert.Contains(Text, '"ServerPath": "<pfad>"');
  Assert.Contains(Text, '"WelcomePageHelpReportFolder": "<pfad>"');
  Assert.Contains(Text, '"WelcomePageHost": "dockWindow"', 'kein Pfad');
  Assert.Contains(Text, '"VisibleRows": 10', 'Zahlen bleiben');
  Assert.Contains(Text, '"WelcomePageHelpReportUrl": "https://example.org/', 'Webadresse ist kein Pfad');
  Assert.IsFalse(Text.Contains('Users'), 'Benutzerordner');
  // Escapes, Schlüssel mit Pfadzeichen, UNC und Laufwerk mit Schrägstrich.
  Text := TAtlasDiagnosticPackage.SettingsWithoutPaths(
    '{"a\\b": "x", "Q": "sagt \"hallo\"", "U": "\\\\server\\share", "D": "D:/Ablage", "E": ""}');
  Assert.AreEqual('{"a\\b": "x", "Q": "sagt \"hallo\"", "U": "<pfad>", "D": "<pfad>", "E": ""}', Text);
  // Die Datei im Paket: auch Benutzername in einer Webadresse ersetzt.
  Text := TAtlasDiagnosticPackage.Build(PackageInput(FFolder), [TAtlasPackagePart.Settings])[0].Text;
  Assert.Contains(Text, 'https://example.org/<benutzer>/issues/new');
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
  Taken: TArray<string>;
  Target: string;
begin
  Assert.AreEqual('Atlas-Diagnose-2026-10-15.zip', TAtlasDiagnosticPackage.ZipName(EncodeDate(2026, 10, 15)));
  Taken := [IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15.zip',
    IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15-2.zip'];
  Target := TAtlasDiagnosticPackage.ZipTarget(FFolder, EncodeDate(2026, 10, 15),
    function(AFileName: string): Boolean
    var
      Name: string;
    begin
      Result := False;
      for Name in Taken do
        Result := Result or SameText(Name, AFileName);
    end);
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15-3.zip', Target,
    'vorhandene ZIP wird nicht überschrieben');
  Assert.AreEqual(IncludeTrailingPathDelimiter(FFolder) + 'Atlas-Diagnose-2026-10-15.zip',
    TAtlasDiagnosticPackage.ZipTarget(FFolder, EncodeDate(2026, 10, 15), nil));
end;

procedure TAtlasDiagnosticPackageTests.ZipHoldsExactlyThePreview;
var
  Files: TAtlasPackageFiles;
  Target, Name: string;
  Zip: TZipFile;
  Bytes: TBytes;
  Item: TAtlasPackageFile;
  Names: TArray<string>;
begin
  Files := TAtlasDiagnosticPackage.Build(PackageInput(FFolder), [TAtlasPackagePart.Versions,
    TAtlasPackagePart.Logs]);
  Target := TPath.Combine(FFolder, 'paket.zip');
  TAtlasDiagnosticPackage.WriteZip(Files, Target);
  Assert.IsTrue(FileExists(Target));
  Zip := TZipFile.Create;
  try
    Zip.Open(Target, TZipMode.zmRead);
    Names := Zip.FileNames;
    Assert.AreEqual(Integer(Length(Files)), Integer(Length(Names)), 'nur die gewählten Teile');
    for Item in Files do
    begin
      Zip.Read(Item.Name, Bytes);
      Assert.AreEqual(Item.Text, TEncoding.UTF8.GetString(Bytes), Item.Name);
    end;
    for Name in Names do
      Assert.IsFalse(Name.Contains('einstellungen') or Name.Contains('diagnosemodus'), Name);
    Zip.Close;
  finally
    Zip.Free;
  end;
  // Eine vorhandene Datei wird ersetzt, nicht ergänzt.
  TAtlasDiagnosticPackage.WriteZip([Files[0]], Target);
  Zip := TZipFile.Create;
  try
    Zip.Open(Target, TZipMode.zmRead);
    Assert.AreEqual(1, Integer(Length(Zip.FileNames)));
    Zip.Close;
  finally
    Zip.Free;
  end;
end;

procedure TAtlasDiagnosticPackageTests.IssueTemplateFollowsSelection;
var
  Input: TAtlasPackageInput;
  Text: string;
begin
  Input := PackageInput(FFolder);
  Text := TAtlasDiagnosticPackage.IssueTemplate('Vervollständigung hängt in ' + Root + '\Main.pas', Input,
    TAtlasDiagnosticPackage.AllParts, TPath.Combine(FFolder, 'Atlas-Diagnose-2026-10-15.zip'), False);
  Assert.Contains(Text, '## Beschreibung');
  Assert.Contains(Text, 'Vervollständigung hängt in <ws>\Main.pas', 'Beschreibung ohne Projektpfad');
  Assert.Contains(Text, '- Atlas: 0.1.0');
  Assert.Contains(Text, '- RAD Studio: Delphi 13 (37.0), Win32');
  Assert.Contains(Text, '- Windows: Windows 11');
  Assert.Contains(Text, '`Atlas-Diagnose-2026-10-15.zip`', 'Hinweis auf das ZIP');
  Assert.IsFalse(Text.Contains(FFolder), 'nur der Dateiname');
  // Ohne Versionen und ohne ZIP.
  Text := TAtlasDiagnosticPackage.IssueTemplate('', Input, [TAtlasPackagePart.Logs], '', False);
  Assert.Contains(Text, '(nicht angegeben)');
  Assert.IsFalse(Text.Contains('Delphi 13'), 'Versionen nur mit Häkchen');
  Assert.Contains(Text, 'Kein Diagnosepaket angelegt.');
  Assert.Contains(Text, '(Was ist passiert?', 'Platzhalter für die Beschreibung');
  // Englisch.
  Text := TAtlasDiagnosticPackage.IssueTemplate('Hangs', Input, TAtlasDiagnosticPackage.AllParts,
    'Atlas-Diagnose-2026-10-15.zip', True);
  Assert.Contains(Text, '## Description');
  Assert.Contains(Text, '## Versions');
  Assert.Contains(Text, 'please attach it to this issue');
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
  Install, Plugin, Local: string;
  Exists: TFunc<string, Boolean>;
begin
  Install := IncludeTrailingPathDelimiter(FFolder);
  Plugin := Install + 'Win32' + PathDelim;
  Local := Install + TAtlasHelp.DocsFolder + PathDelim + TAtlasHelp.DocsIndex;
  Exists :=
    function(AFileName: string): Boolean
    begin
      Result := SameText(AFileName, Local);
    end;
  // BPL in Win32\, Doku eine Ebene darüber.
  Assert.AreEqual(Local, TAtlasHelp.DocsTarget(Plugin, Exists));
  // BPL direkt im Installationsordner.
  Assert.AreEqual(Local, TAtlasHelp.DocsTarget(Install, Exists));
  // Ohne Installation: Doku-Seite des Repositorys.
  Assert.AreEqual(TAtlasHelp.DocsUrl, TAtlasHelp.DocsTarget(Plugin,
    function(AFileName: string): Boolean
    begin
      Result := False;
    end));
  Assert.AreEqual(TAtlasHelp.DocsUrl, TAtlasHelp.DocsTarget('', Exists));
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Docs, False));
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Report, False));
  Assert.IsFalse(TAtlasHelp.Enabled(TAtlasHelpButton.Keys, False), 'ohne Übersicht (#520)');
  Assert.IsTrue(TAtlasHelp.Enabled(TAtlasHelpButton.Keys, True));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDiagnosticPackageTests);

end.
