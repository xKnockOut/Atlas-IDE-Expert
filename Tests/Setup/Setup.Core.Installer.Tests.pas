unit Setup.Core.Installer.Tests;

// Installer (#495) gegen eine Attrappe des Systems (Registry und Dateien im
// Speicher): IDEs finden, nicht unterstützte zeigen, installieren,
// aktualisieren, laufende IDEs erkennen, deinstallieren ohne Rest unter
// „Known Packages“, Benutzerdaten nur auf Wunsch entfernen, Zustimmung zur
// Lizenzvereinbarung; dazu die Texte.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSetupInstallerTests = class
  public
    [Test]
    procedure RecognisesVersionsAndPackages;
    [Test]
    procedure DetectsSupportedUnsupportedAndMissingPackage;
    [Test]
    procedure DetectsMachineOnlyInstallations;
    [Test]
    procedure InstallCopiesAndRegisters;
    [Test]
    procedure UpdateReplacesOldRegistration;
    [Test]
    procedure InstallSkipsUnavailableIdes;
    [Test]
    procedure InstallReportsLockedFile;
    [Test]
    procedure FindsRunningIdes;
    [Test]
    procedure UninstallLeavesNoKnownPackages;
    [Test]
    procedure UninstallKeepsDataUnlessChosen;
    [Test]
    procedure UninstallRemovesChosenData;
    [Test]
    procedure UninstallFromInstallDirDeletesLater;
    [Test]
    procedure TextsCoverEveryStepInBothLanguages;
    [Test]
    procedure LicenseNormalizesBomAndLineBreaks;
    [Test]
    procedure LicenseAskedUntilAccepted;
    [Test]
    procedure LicenseAskedAgainAfterChangeOrUninstall;
    [Test]
    procedure InstallCopiesLicense;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Setup.Core.Contract,
  Setup.Core.Ides,
  Setup.Core.Installer,
  Setup.Core.License,
  Setup.Shell.Texts;

type
  /// <summary>Registry als Tabelle „SCHLÜSSEL|WERT“ → Inhalt, Dateien als Liste von Pfaden;
  /// Groß-/Kleinschreibung egal.</summary>
  TFakeSystem = class(TInterfacedObject, ISetupSystem)
  public
    User: TDictionary<string, string>;
    Machine: TDictionary<string, string>;
    Files: TStringList;
    Running: TArray<string>;
    LaterDeleted: string;
    LockedFile: string;
    constructor Create;
    destructor Destroy; override;
    procedure AddKey(AStore: TDictionary<string, string>; const AKey: string);
    function SubKeys(const AKey: string): TArray<string>;
    function MachineSubKeys(const AKey: string): TArray<string>;
    function ReadString(const AKey, AName: string): string;
    function MachineReadString(const AKey, AName: string): string;
    function ValueNames(const AKey: string): TArray<string>;
    procedure WriteString(const AKey, AName, AValue: string);
    procedure WriteInteger(const AKey, AName: string; AValue: Integer);
    procedure DeleteValue(const AKey, AName: string);
    procedure DeleteKey(const AKey: string);
    function FileExists(const AFileName: string): Boolean;
    function DirectoryExists(const ADirectory: string): Boolean;
    procedure CopyFile(const ASource, ATarget: string);
    procedure DeleteFile(const AFileName: string);
    procedure DeleteDirectory(const ADirectory: string);
    procedure DeleteDirectoryLater(const ADirectory: string);
    function FileSize(const AFileName: string): Int64;
    function FilesIn(const ADirectory: string): TArray<string>;
    function RunningExecutables: TArray<string>;
    function HasFileUnder(const ADirectory: string): Boolean;
  end;

const
  // Schlüssel ohne Wert stehen als „Schlüssel|“ in der Liste.
  KeyMark = '|';

function Up(const AText: string): string;
begin
  Result := AnsiUpperCase(AText);
end;

constructor TFakeSystem.Create;
begin
  inherited Create;
  User := TDictionary<string, string>.Create;
  Machine := TDictionary<string, string>.Create;
  Files := TStringList.Create;
  Files.CaseSensitive := False;
end;

destructor TFakeSystem.Destroy;
begin
  User.Free;
  Machine.Free;
  Files.Free;
  inherited;
end;

procedure TFakeSystem.AddKey(AStore: TDictionary<string, string>; const AKey: string);
begin
  AStore.AddOrSetValue(Up(AKey) + KeyMark, '');
end;

function ChildKeys(AStore: TDictionary<string, string>; const AKey: string): TArray<string>;
var
  Item, Prefix, Rest, Name: string;
  Names: TStringList;
begin
  Prefix := Up(AKey) + '\';
  Names := TStringList.Create;
  try
    Names.Sorted := True;
    Names.Duplicates := dupIgnore;
    for Item in AStore.Keys do
      if Item.StartsWith(Prefix) then
      begin
        Rest := Item.Substring(Length(Prefix));
        Rest := Rest.Substring(0, Rest.IndexOfAny(['\', KeyMark]));
        if Rest <> '' then
          Names.Add(Rest);
      end;
    Result := nil;
    for Name in Names do
      Result := Result + [Name];
  finally
    Names.Free;
  end;
end;

function TFakeSystem.SubKeys(const AKey: string): TArray<string>;
begin
  Result := ChildKeys(User, AKey);
end;

function TFakeSystem.MachineSubKeys(const AKey: string): TArray<string>;
begin
  Result := ChildKeys(Machine, AKey);
end;

function TFakeSystem.ReadString(const AKey, AName: string): string;
begin
  if not User.TryGetValue(Up(AKey) + KeyMark + Up(AName), Result) then
    Result := '';
end;

function TFakeSystem.MachineReadString(const AKey, AName: string): string;
begin
  if not Machine.TryGetValue(Up(AKey) + KeyMark + Up(AName), Result) then
    Result := '';
end;

function TFakeSystem.ValueNames(const AKey: string): TArray<string>;
var
  Item, Prefix: string;
begin
  Result := nil;
  Prefix := Up(AKey) + KeyMark;
  for Item in User.Keys do
    if Item.StartsWith(Prefix) and (Length(Item) > Length(Prefix)) then
      Result := Result + [Item.Substring(Length(Prefix))];
end;

procedure TFakeSystem.WriteString(const AKey, AName, AValue: string);
begin
  User.AddOrSetValue(Up(AKey) + KeyMark + Up(AName), AValue);
end;

procedure TFakeSystem.WriteInteger(const AKey, AName: string; AValue: Integer);
begin
  WriteString(AKey, AName, IntToStr(AValue));
end;

procedure TFakeSystem.DeleteValue(const AKey, AName: string);
begin
  User.Remove(Up(AKey) + KeyMark + Up(AName));
end;

procedure TFakeSystem.DeleteKey(const AKey: string);
var
  Item: string;
  Doomed: TList<string>;
begin
  Doomed := TList<string>.Create;
  try
    for Item in User.Keys do
      if Item.StartsWith(Up(AKey) + KeyMark) or Item.StartsWith(Up(AKey) + '\') then
        Doomed.Add(Item);
    for Item in Doomed do
      User.Remove(Item);
  finally
    Doomed.Free;
  end;
end;

function TFakeSystem.FileExists(const AFileName: string): Boolean;
begin
  Result := Files.IndexOf(AFileName) >= 0;
end;

function TFakeSystem.HasFileUnder(const ADirectory: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in Files do
    if Up(Item).StartsWith(Up(ADirectory) + '\') then
      Exit(True);
end;

function TFakeSystem.DirectoryExists(const ADirectory: string): Boolean;
begin
  Result := HasFileUnder(ADirectory);
end;

procedure TFakeSystem.CopyFile(const ASource, ATarget: string);
begin
  if not FileExists(ASource) then
    raise EFileNotFoundException.Create(ASource);
  if SameText(ATarget, LockedFile) then
    raise EInOutError.Create('gesperrt: ' + ATarget);
  if not FileExists(ATarget) then
    Files.Add(ATarget);
end;

procedure TFakeSystem.DeleteFile(const AFileName: string);
var
  Index: Integer;
begin
  Index := Files.IndexOf(AFileName);
  if Index >= 0 then
    Files.Delete(Index);
end;

procedure TFakeSystem.DeleteDirectory(const ADirectory: string);
var
  Index: Integer;
begin
  for Index := Files.Count - 1 downto 0 do
    if Up(Files[Index]).StartsWith(Up(ADirectory) + '\') then
      Files.Delete(Index);
end;

procedure TFakeSystem.DeleteDirectoryLater(const ADirectory: string);
begin
  LaterDeleted := ADirectory;
end;

function TFakeSystem.FileSize(const AFileName: string): Int64;
begin
  Result := 2048;
end;

function TFakeSystem.FilesIn(const ADirectory: string): TArray<string>;
var
  Item, Rest: string;
begin
  Result := nil;
  for Item in Files do
    if Up(Item).StartsWith(Up(ADirectory) + '\') then
    begin
      Rest := Copy(Item, Length(ADirectory) + 2, MaxInt);
      if Pos('\', Rest) = 0 then
        Result := Result + [Rest];
    end;
end;

function TFakeSystem.RunningExecutables: TArray<string>;
begin
  Result := Running;
end;

const
  Source = 'D:\Download\Atlas';
  Target = 'C:\Users\Ich\AppData\Local\Programs\Atlas';
  Roaming = 'C:\Users\Ich\AppData\Roaming\Atlas';
  Local = 'C:\Users\Ich\AppData\Local\Atlas';
  D12 = 'C:\Program Files (x86)\Embarcadero\Studio\23.0';
  D13 = 'C:\Program Files (x86)\Embarcadero\Studio\37.0';
  D11 = 'C:\Program Files (x86)\Embarcadero\Studio\22.0';

function Paths: TSetupPaths;
begin
  Result.SourceDir := Source;
  Result.InstallDir := Target;
  Result.RoamingDataDir := Roaming;
  Result.LocalDataDir := Local;
end;

/// <summary>Delphi 12 (32 und 64 Bit), Delphi 13 (32 Bit), Delphi 11;
/// Download mit BPLs für 12 und 13 (Win32) und 12 (Win64).</summary>
function Prepared: TFakeSystem;
var
  Name: string;
begin
  Result := TFakeSystem.Create;
  Result.WriteString('Software\Embarcadero\BDS\23.0', 'RootDir', D12 + '\');
  Result.WriteString('Software\Embarcadero\BDS\37.0', 'RootDir', D13);
  Result.WriteString('Software\Embarcadero\BDS\22.0', 'RootDir', D11);
  Result.AddKey(Result.User, 'Software\Embarcadero\BDS\Globals');
  Result.Files.Add(D12 + '\bin\bds.exe');
  Result.Files.Add(D12 + '\bin64\bds.exe');
  Result.Files.Add(D13 + '\bin\bds.exe');
  Result.Files.Add(D11 + '\bin\bds.exe');
  for Name in TSetupInstaller.CommonFiles do
    Result.Files.Add(Source + '\' + Name);
  Result.Files.Add(Source + '\Win32\Atlas.IDE.Expert290.bpl');
  Result.Files.Add(Source + '\Win64\Atlas.IDE.Expert290.bpl');
  Result.Files.Add(Source + '\Win32\Atlas.IDE.Expert370.bpl');
  Result.Files.Add(Source + '\Beispiele\Suchfeld.pas');
  Result.Files.Add(Source + '\Beispiele\Karte.pas');
  Result.Files.Add(Source + '\Tipps\code-aktionen.png');
  Result.Files.Add(Source + '\Doku\index.html');
  Result.Files.Add(Source + '\Doku\Einstellungen.html');
  Result.Files.Add(Source + '\Vorlagen\atlas-existing.json');
  Result.Files.Add(Source + '\Vorlagen\atlas-strict.json');
end;

function Find(const AIdes: TArray<TSetupIde>; const AId: string): TSetupIde;
var
  Ide: TSetupIde;
begin
  for Ide in AIdes do
    if Ide.Id = AId then
      Exit(Ide);
  raise Exception.Create('IDE fehlt: ' + AId);
end;

function KnownPackages(const ASystem: TFakeSystem): Integer;
var
  Item: string;
begin
  Result := 0;
  for Item in ASystem.User.Keys do
    if Item.Contains('\KNOWN PACKAGES') and
      TSetupIdes.IsAtlasPackage(Item.Substring(Item.IndexOf(KeyMark) + 1)) then
      Inc(Result);
end;

{ TSetupInstallerTests }

procedure TSetupInstallerTests.RecognisesVersionsAndPackages;
var
  Ides: TArray<TSetupIde>;
begin
  Assert.IsTrue(TSetupIdes.IsVersionKey('37.0'));
  Assert.IsFalse(TSetupIdes.IsVersionKey('Globals'));
  Assert.IsFalse(TSetupIdes.IsVersionKey('37'));
  Assert.IsFalse(TSetupIdes.IsVersionKey('37.'));
  Assert.IsTrue(TSetupIdes.IsAtlasPackage('C:\x\Win32\Atlas.IDE.Expert370.bpl'));
  Assert.IsTrue(TSetupIdes.IsAtlasPackage('C:\alt\Argus.IDE.Expert.bpl'));
  Assert.IsTrue(TSetupIdes.IsAtlasPackage('BetterDelphiLSP290.bpl'));
  Assert.IsFalse(TSetupIdes.IsAtlasPackage('C:\x\dclcore370.bpl'));
  Assert.IsTrue(TSetupIdes.CompareVersions('37.0', '23.0') > 0);
  Assert.IsTrue(TSetupIdes.CompareVersions('9.0', '23.0') < 0);
  Assert.AreEqual('Delphi 12 Athens', TSetupIdes.Lookup('23.0').ProductName);
  Assert.IsFalse(TSetupIdes.Lookup('99.0').Supported);
  Assert.AreEqual(2, Integer(Length(TSetupIdes.SupportedVersions)));
  SetLength(Ides, 3);
  Ides[0].Info := TSetupIdes.Lookup('23.0');
  Ides[0].Platform := TSetupPlatform.Win64;
  Ides[1].Info := TSetupIdes.Lookup('37.0');
  Ides[2].Info := TSetupIdes.Lookup('23.0');
  TSetupIdes.Sort(Ides);
  Assert.AreEqual('37.0-Win32', Ides[0].Id);
  Assert.AreEqual('23.0-Win32', Ides[1].Id);
  Assert.AreEqual('23.0-Win64', Ides[2].Id);
  Assert.AreEqual('Software\Embarcadero\BDS\23.0\Known Packages x64', Ides[2].KnownPackagesKey);
  Assert.AreEqual('Atlas.IDE.Expert290.bpl', Ides[2].PackageFileName);
end;

procedure TSetupInstallerTests.DetectsSupportedUnsupportedAndMissingPackage;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Ides: TArray<TSetupIde>;
begin
  Sys := Prepared;
  Keep := Sys;
  Sys.Files.Delete(Sys.Files.IndexOf(Source + '\Win32\Atlas.IDE.Expert370.bpl'));
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Ides := Installer.Detect;
    Assert.AreEqual(4, Integer(Length(Ides)));
    Assert.AreEqual('37.0-Win32', Ides[0].Id);
    Assert.IsTrue(Find(Ides, '23.0-Win32').Available);
    Assert.IsTrue(Find(Ides, '23.0-Win64').Available);
    Assert.AreEqual(D12 + '\bin64\bds.exe', Find(Ides, '23.0-Win64').Executable);
    Assert.IsTrue(Find(Ides, '37.0-Win32').Unavailable = TSetupUnavailable.PackageMissing);
    Assert.IsTrue(Find(Ides, '22.0-Win32').Unavailable = TSetupUnavailable.VersionUnsupported);
    Assert.IsFalse(Find(Ides, '23.0-Win32').Installed);
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.DetectsMachineOnlyInstallations;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Ides: TArray<TSetupIde>;
begin
  // Noch nie gestartet: nur unter HKLM (hier im WOW6432Node-Zweig) eingetragen.
  Sys := TFakeSystem.Create;
  Keep := Sys;
  Sys.Machine.AddOrSetValue(Up('Software\WOW6432Node\Embarcadero\BDS\37.0') + KeyMark + 'ROOTDIR', D13);
  Sys.Files.Add(D13 + '\bin\bds.exe');
  Sys.Files.Add(Source + '\Win32\Atlas.IDE.Expert370.bpl');
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Ides := Installer.Detect;
    Assert.AreEqual(1, Integer(Length(Ides)));
    Assert.IsTrue(Ides[0].Available);
    Assert.AreEqual('Delphi 13 Florence', Ides[0].Info.ProductName);
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.InstallCopiesAndRegisters;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Steps: TList<TSetupStep>;
begin
  Sys := Prepared;
  Keep := Sys;
  Steps := TList<TSetupStep>.Create;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Installer.OnStep :=
      procedure(AStep: TSetupStep)
      begin
        Steps.Add(AStep);
      end;
    Assert.IsTrue(Installer.Install(Installer.Detect));
    Assert.IsTrue(Sys.FileExists(Target + '\AtlasServer.exe'));
    Assert.IsTrue(Sys.FileExists(Target + '\AtlasSetup.exe'));
    Assert.IsTrue(Sys.FileExists(Target + '\Win32\Atlas.IDE.Expert290.bpl'));
    Assert.IsTrue(Sys.FileExists(Target + '\Win64\Atlas.IDE.Expert290.bpl'));
    Assert.IsTrue(Sys.FileExists(Target + '\Win32\Atlas.IDE.Expert370.bpl'));
    // Karte „Neu in Atlas“ (#756): whatsnew.json und Beispiele neben den BPL-Ordnern.
    Assert.IsTrue(Sys.FileExists(Target + '\whatsnew.json'));
    Assert.IsTrue(Sys.FileExists(Target + '\Beispiele\Suchfeld.pas'));
    Assert.IsTrue(Sys.FileExists(Target + '\Beispiele\Karte.pas'));
    // Karte „Atlas entdecken“ (#757): tips.json und die Bilder im Ordner Tipps.
    Assert.IsTrue(Sys.FileExists(Target + '\tips.json'));
    Assert.IsTrue(Sys.FileExists(Target + '\Tipps\code-aktionen.png'));
    // „Atlas-Doku“ der Willkommensseite (#766): lokale HTML-Doku im Ordner Doku.
    Assert.IsTrue(Sys.FileExists(Target + '\Doku\index.html'));
    Assert.IsTrue(Sys.FileExists(Target + '\Doku\Einstellungen.html'));
    // Einrichtung „Projekt für Atlas einrichten“ (#759): Vorlagen für atlas.json im Ordner Vorlagen.
    Assert.IsTrue(Sys.FileExists(Target + '\Vorlagen\atlas-existing.json'));
    Assert.IsTrue(Sys.FileExists(Target + '\Vorlagen\atlas-strict.json'));
    Assert.AreEqual(TSetupIdes.PackageDescription, Sys.ReadString('Software\Embarcadero\BDS\23.0\Known Packages',
      Target + '\Win32\Atlas.IDE.Expert290.bpl'));
    Assert.AreEqual(TSetupIdes.PackageDescription, Sys.ReadString(
      'Software\Embarcadero\BDS\23.0\Known Packages x64', Target + '\Win64\Atlas.IDE.Expert290.bpl'));
    Assert.AreEqual(TSetupIdes.PackageDescription, Sys.ReadString('Software\Embarcadero\BDS\37.0\Known Packages',
      Target + '\Win32\Atlas.IDE.Expert370.bpl'));
    // Nicht unterstützt: keine Registrierung in Delphi 11.
    Assert.AreEqual(0, Integer(Length(Sys.ValueNames('Software\Embarcadero\BDS\22.0\Known Packages'))));
    Assert.AreEqual('"' + Target + '\AtlasSetup.exe" /uninstall',
      Sys.ReadString(TSetupInstaller.UninstallKey, 'UninstallString'));
    Assert.AreEqual('1.0.0', Sys.ReadString(TSetupInstaller.UninstallKey, 'DisplayVersion'));
    Assert.AreEqual('1.0.0', Installer.InstalledVersion);
    Assert.AreEqual(Target, Sys.ReadString(TSetupInstaller.SetupKey, 'InstallDir'));
    Assert.AreEqual(3, KnownPackages(Sys));
    Assert.IsTrue(Find(Installer.Detect, '23.0-Win64').Installed);
    Assert.IsTrue(Steps.Last.Kind = TSetupStepKind.UninstallEntryWritten);
  finally
    Installer.Free;
    Steps.Free;
  end;
end;

procedure TSetupInstallerTests.UpdateReplacesOldRegistration;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Key: string;
begin
  Sys := Prepared;
  Keep := Sys;
  Key := 'Software\Embarcadero\BDS\23.0\Known Packages';
  // Frühere Hand-Installation unter altem Namen, von der IDE abgeschaltet; dazu ein fremdes Package.
  Sys.WriteString(Key, 'C:\Alt\Argus.IDE.Expert290.bpl', 'Argus');
  Sys.WriteString(Key, 'C:\Fremd\Other290.bpl', 'Other');
  Sys.WriteString('Software\Embarcadero\BDS\23.0\Disabled Packages', 'C:\Alt\Argus.IDE.Expert290.bpl', 'Argus');
  // Einstellungen und Favoriten liegen unter Software\Atlas und bleiben unberührt.
  Sys.WriteString('Software\Atlas\IdePlugin', 'Favorites', 'x');
  // Gesehene Version der Karte „Neu in Atlas“ (#756) bleibt, damit die Karte die neue Version meldet.
  Sys.WriteString('Software\Atlas\IdePlugin', 'WhatsNewSeen', '1.0.0');
  // Beispiel der alten Version, das es nicht mehr gibt.
  Sys.Files.Add(Target + '\Beispiele\Alt.pas');
  Sys.Files.Add(Target + '\Tipps\alt.png');
  Sys.Files.Add(Target + '\Doku\Alt.html');
  Sys.Files.Add(Target + '\Vorlagen\atlas-alt.json');
  Installer := TSetupInstaller.Create(Keep, Paths, '1.1.0');
  try
    Assert.IsTrue(Installer.Install([Find(Installer.Detect, '23.0-Win32')]));
    Assert.AreEqual(2, Integer(Length(Sys.ValueNames(Key))));
    Assert.AreEqual('', Sys.ReadString(Key, 'C:\Alt\Argus.IDE.Expert290.bpl'));
    Assert.AreEqual('Other', Sys.ReadString(Key, 'C:\Fremd\Other290.bpl'));
    Assert.AreEqual(0, Integer(Length(Sys.ValueNames('Software\Embarcadero\BDS\23.0\Disabled Packages'))));
    Assert.AreEqual('x', Sys.ReadString('Software\Atlas\IdePlugin', 'Favorites'));
    Assert.AreEqual('1.0.0', Sys.ReadString('Software\Atlas\IdePlugin', 'WhatsNewSeen'));
    Assert.IsFalse(Sys.FileExists(Target + '\Beispiele\Alt.pas'), 'Beispiele gelten je Version');
    Assert.IsTrue(Sys.FileExists(Target + '\Beispiele\Karte.pas'));
    Assert.IsFalse(Sys.FileExists(Target + '\Tipps\alt.png'), 'Bilder der Tipps gelten je Version (#757)');
    Assert.IsTrue(Sys.FileExists(Target + '\Tipps\code-aktionen.png'));
    Assert.IsFalse(Sys.FileExists(Target + '\Doku\Alt.html'), 'Doku gilt je Version (#766)');
    Assert.IsTrue(Sys.FileExists(Target + '\Doku\index.html'));
    Assert.IsFalse(Sys.FileExists(Target + '\Vorlagen\atlas-alt.json'), 'Vorlagen gelten je Version (#759)');
    Assert.IsTrue(Sys.FileExists(Target + '\Vorlagen\atlas-strict.json'));
    // Zweiter Lauf (Aktualisierung): weiterhin genau eine Registrierung.
    Assert.IsTrue(Installer.Install([Find(Installer.Detect, '23.0-Win32')]));
    Assert.AreEqual(2, Integer(Length(Sys.ValueNames(Key))));
    Assert.AreEqual('1.1.0', Installer.InstalledVersion);
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.InstallSkipsUnavailableIdes;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install([Find(Installer.Detect, '22.0-Win32')]));
    Assert.AreEqual(0, KnownPackages(Sys));
    Assert.IsFalse(Sys.HasFileUnder(Target + '\Win32'));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.InstallReportsLockedFile;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Failure: string;
begin
  Sys := Prepared;
  Keep := Sys;
  Sys.LockedFile := Target + '\Win32\Atlas.IDE.Expert290.bpl';
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Installer.OnStep :=
      procedure(AStep: TSetupStep)
      begin
        if AStep.Kind = TSetupStepKind.Failed then
          Failure := AStep.Subject;
      end;
    Assert.IsFalse(Installer.Install([Find(Installer.Detect, '23.0-Win32')]));
    Assert.Contains(Failure, 'gesperrt');
    // Abbruch vor der Registrierung: keine halbe Installation in der IDE.
    Assert.AreEqual(0, KnownPackages(Sys));
    Assert.AreEqual('', Installer.InstalledVersion);
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.FindsRunningIdes;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
  Running: TArray<TSetupIde>;
begin
  Sys := Prepared;
  Keep := Sys;
  Sys.Running := [UpperCase(D12) + '\BIN64\BDS.EXE', 'C:\Andere\bds.exe', 'C:\Windows\explorer.exe'];
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Running := Installer.RunningIdes(Installer.Detect);
    Assert.AreEqual(1, Integer(Length(Running)));
    Assert.AreEqual('23.0-Win64', Running[0].Id);
    Sys.Running := nil;
    Assert.AreEqual(0, Integer(Length(Installer.RunningIdes(Installer.Detect))));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.UninstallLeavesNoKnownPackages;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install(Installer.Detect));
    // Auch eine Hand-Installation in einer nicht unterstützten Version und eine abgeschaltete verschwinden.
    Sys.WriteString('Software\Embarcadero\BDS\22.0\Known Packages', 'C:\x\Atlas.IDE.Expert280.bpl', 'Atlas');
    Sys.WriteString('Software\Embarcadero\BDS\37.0\Disabled Packages x64', 'C:\x\Atlas.IDE.Expert370.bpl', 'A');
    Assert.IsTrue(Installer.Uninstall([], False));
    Assert.AreEqual(0, KnownPackages(Sys));
    Assert.AreEqual(0, Integer(Length(Sys.ValueNames('Software\Embarcadero\BDS\37.0\Disabled Packages x64'))));
    Assert.IsFalse(Sys.HasFileUnder(Target));
    Assert.AreEqual('', Sys.ReadString(TSetupInstaller.UninstallKey, 'DisplayName'));
    Assert.AreEqual('', Installer.InstalledVersion);
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.UninstallKeepsDataUnlessChosen;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Sys.WriteString('Software\Atlas\IdePlugin', 'Mode', '1');
  Sys.Files.Add(Roaming + '\settings-history.json');
  Sys.Files.Add(Roaming + '\Snippets\mein.json');
  Sys.Files.Add(Local + '\Index\a.idx');
  Sys.Files.Add(Local + '\Logs\atlas.log');
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install(Installer.Detect));
    Assert.IsTrue(Installer.Uninstall([], False));
    Assert.AreEqual('1', Sys.ReadString('Software\Atlas\IdePlugin', 'Mode'));
    Assert.IsTrue(Sys.FileExists(Roaming + '\settings-history.json'));
    Assert.IsTrue(Sys.FileExists(Roaming + '\Snippets\mein.json'));
    Assert.IsTrue(Sys.FileExists(Local + '\Index\a.idx'));
    Assert.IsTrue(Sys.FileExists(Local + '\Logs\atlas.log'));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.UninstallRemovesChosenData;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Sys.WriteString('Software\Atlas\IdePlugin', 'Mode', '1');
  Sys.Files.Add(Roaming + '\settings-history.json');
  Sys.Files.Add(Roaming + '\palette.json');
  Sys.Files.Add(Roaming + '\Snippets\mein.json');
  Sys.Files.Add(Local + '\Index\a.idx');
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    // Nur Einstellungen: Snippets und Index bleiben.
    Assert.IsTrue(Installer.Uninstall([TSetupData.Settings], False));
    Assert.AreEqual('', Sys.ReadString('Software\Atlas\IdePlugin', 'Mode'));
    Assert.IsFalse(Sys.FileExists(Roaming + '\settings-history.json'));
    Assert.IsFalse(Sys.FileExists(Roaming + '\palette.json'));
    Assert.IsTrue(Sys.FileExists(Roaming + '\Snippets\mein.json'));
    Assert.IsTrue(Sys.FileExists(Local + '\Index\a.idx'));
    // Dann Index und Snippets.
    Assert.IsTrue(Installer.Uninstall([TSetupData.IndexAndLogs, TSetupData.Snippets], False));
    Assert.IsFalse(Sys.FileExists(Roaming + '\Snippets\mein.json'));
    Assert.IsFalse(Sys.FileExists(Local + '\Index\a.idx'));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.UninstallFromInstallDirDeletesLater;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install(Installer.Detect));
    Assert.IsTrue(Installer.Uninstall([], True));
    Assert.AreEqual(Target, Sys.LaterDeleted);
    Assert.AreEqual(0, KnownPackages(Sys));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.TextsCoverEveryStepInBothLanguages;
var
  Language: TSetupLanguage;
  Id: TSetupTextId;
  Kind: TSetupStepKind;
  Ide: TSetupIde;
begin
  for Language := Low(TSetupLanguage) to High(TSetupLanguage) do
  begin
    TSetupTexts.Language := Language;
    for Id := Low(TSetupTextId) to High(TSetupTextId) do
      Assert.IsTrue(TSetupTexts.Get(Id) <> '');
    for Kind := Low(TSetupStepKind) to High(TSetupStepKind) do
      Assert.IsTrue(TSetupTexts.StepText(TSetupStep.Make(Kind, 'X')) <> '');
  end;
  TSetupTexts.Language := TSetupLanguage.German;
  Assert.AreEqual('Entfernt: Eigene Snippets', TSetupTexts.StepText(TSetupStep.Make(TSetupStepKind.DataRemoved,
    TSetupInstaller.DataId(TSetupData.Snippets))));
  Ide := Default(TSetupIde);
  Ide.Info := TSetupIdes.Lookup('22.0');
  Ide.Unavailable := TSetupUnavailable.VersionUnsupported;
  Assert.AreEqual('Delphi 11 Alexandria (Win32) – nicht unterstützt', TSetupTexts.IdeCaption(Ide));
  Ide.Info := TSetupIdes.Lookup('23.0');
  Ide.Platform := TSetupPlatform.Win64;
  Ide.Unavailable := TSetupUnavailable.None;
  Ide.Installed := True;
  Assert.AreEqual('Delphi 12 Athens (Win64) – installiert', TSetupTexts.IdeCaption(Ide));
  TSetupTexts.Language := TSetupLanguage.English;
  Assert.AreEqual('Registered in D', TSetupTexts.StepText(TSetupStep.Make(TSetupStepKind.Registered, 'D')));
  TSetupTexts.Language := TSetupLanguage.German;
end;

procedure TSetupInstallerTests.LicenseNormalizesBomAndLineBreaks;
begin
  Assert.AreEqual('A'#13#10'B'#13#10#13#10'C', TSetupLicense.Normalize(#$FEFF'A'#10'B'#13#13#10'C'#10#10'  '));
  Assert.AreEqual('', TSetupLicense.Normalize(#$FEFF#13#10));
  // Gleicher Text mit anderen Zeilenumbrüchen gibt denselben Fingerabdruck.
  Assert.AreEqual(TSetupLicense.Fingerprint('A'#13#10'B'), TSetupLicense.Fingerprint('A'#10'B'#10));
  Assert.AreNotEqual(TSetupLicense.Fingerprint('A'#13#10'B'), TSetupLicense.Fingerprint('A'#13#10'C'));
  Assert.AreEqual(64, Length(TSetupLicense.Fingerprint('A')));
end;

procedure TSetupInstallerTests.LicenseAskedUntilAccepted;
var
  Keep: ISetupSystem;
begin
  Keep := TFakeSystem.Create;
  // Ohne EULA.txt (Entwicklerbuild) gibt es nichts zu bestätigen.
  Assert.IsFalse(TSetupLicense.NeedsAcceptance(Keep, ''));
  Assert.IsFalse(TSetupLicense.NeedsAcceptance(Keep, #13#10));
  Assert.IsTrue(TSetupLicense.NeedsAcceptance(Keep, 'MIT'));
  TSetupLicense.Accept(Keep, 'MIT');
  Assert.IsFalse(TSetupLicense.NeedsAcceptance(Keep, 'MIT'#13#10));
  Assert.AreEqual(TSetupLicense.Fingerprint('MIT'), Keep.ReadString(TSetupInstaller.SetupKey,
    TSetupLicense.AcceptedValue));
end;

procedure TSetupInstallerTests.LicenseAskedAgainAfterChangeOrUninstall;
var
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Keep := Prepared;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install(Installer.Detect));
    TSetupLicense.Accept(Keep, 'Fassung 1');
    Assert.IsFalse(TSetupLicense.NeedsAcceptance(Keep, 'Fassung 1'));
    Assert.IsTrue(TSetupLicense.NeedsAcceptance(Keep, 'Fassung 2'));
    // Die Deinstallation entfernt Software\Atlas\Setup und damit die Zustimmung.
    Assert.IsTrue(Installer.Uninstall([], False));
    Assert.IsTrue(TSetupLicense.NeedsAcceptance(Keep, 'Fassung 1'));
  finally
    Installer.Free;
  end;
end;

procedure TSetupInstallerTests.InstallCopiesLicense;
var
  Sys: TFakeSystem;
  Keep: ISetupSystem;
  Installer: TSetupInstaller;
begin
  Sys := Prepared;
  Keep := Sys;
  Installer := TSetupInstaller.Create(Keep, Paths, '1.0.0');
  try
    Assert.IsTrue(Installer.Install(Installer.Detect));
    Assert.IsTrue(Sys.FileExists(Target + '\' + TSetupLicense.FileName));
    Assert.IsTrue(Sys.FileExists(Target + '\LICENSE'));
    Assert.IsTrue(Installer.Uninstall([], False));
    Assert.IsFalse(Sys.FileExists(Target + '\' + TSetupLicense.FileName));
  finally
    Installer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TSetupInstallerTests);

end.
