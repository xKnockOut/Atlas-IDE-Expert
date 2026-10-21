unit Setup.Core.Installer;

// Installer (#495): IDEs finden, Atlas installieren, aktualisieren und
// entfernen. Nur über ISetupSystem, ohne Windows und VCL.
// Ablage (je Benutzer, ohne Administratorrechte):
//   <InstallDir>\AtlasServer.exe, AtlasSetup.exe, LICENSE, EULA.txt, THIRD-PARTY-NOTICES.md,
//     whatsnew.json (#756), tips.json (#757)
//   <InstallDir>\Beispiele\… (#756, #757), <InstallDir>\Tipps\….png (#757),
//   <InstallDir>\Doku\….html (#766, lokale Doku für „Atlas-Doku“)
//   <InstallDir>\Win32\Atlas.IDE.Expert<Suffix>.bpl, <InstallDir>\Win64\…
// Die Quelle (SourceDir, der Ordner des Installers) hat denselben Aufbau.
// Eine IDE wird nur angeboten, wenn ihre Version unterstützt ist und die
// passende BPL in der Quelle liegt.
// Registrierung: Wert <BPL-Pfad> = „Atlas IDE Expert“ unter „Known Packages“
// (bzw. „Known Packages x64“) der IDE. Alte Atlas-Werte (auch unter früheren
// Namen) und Einträge unter „Disabled Packages“ werden vorher entfernt; so
// ersetzt eine Aktualisierung die alte Installation.
// Deinstallation über „Apps und Features“ (Eintrag unter …\Uninstall\
// AtlasIdeExpert). Benutzerdaten bleiben, außer sie werden ausgewählt.
// Jeder Schritt wird als TSetupStep gemeldet; die Oberfläche übersetzt ihn.

interface

uses
  System.SysUtils,
  Setup.Core.Contract,
  Setup.Core.Ides;

type
{$SCOPEDENUMS ON}
  TSetupStepKind = (FileCopied, Registered, RegistrationRemoved, UninstallEntryWritten, UninstallEntryRemoved,
    FilesRemoved, FilesRemovedLater, DataRemoved, Failed);
  /// <summary>Benutzerdaten, die die Deinstallation auf Wunsch entfernt.</summary>
  TSetupData = (Settings, IndexAndLogs, Snippets);
{$SCOPEDENUMS OFF}
  TSetupDataSet = set of TSetupData;

  TSetupStep = record
    Kind: TSetupStepKind;
    /// <summary>Datei, IDE-Name oder Fehlertext.</summary>
    Subject: string;
    class function Make(AKind: TSetupStepKind; const ASubject: string): TSetupStep; static;
  end;

  TSetupPaths = record
    /// <summary>Ordner mit den zu installierenden Dateien (Ordner des Installers).</summary>
    SourceDir: string;
    /// <summary>Ziel, üblich %LOCALAPPDATA%\Programs\Atlas.</summary>
    InstallDir: string;
    /// <summary>%APPDATA%\Atlas (Einstellungsverlauf, Paletten, Snippets).</summary>
    RoamingDataDir: string;
    /// <summary>%LOCALAPPDATA%\Atlas (Index, Protokolle, Sitzung).</summary>
    LocalDataDir: string;
  end;

  TSetupInstaller = class
  public const
    UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\AtlasIdeExpert';
    SetupKey = 'Software\Atlas\Setup';
    SettingsKey = 'Software\Atlas';
    SetupExe = 'AtlasSetup.exe';
    ServerExe = 'AtlasServer.exe';
    SnippetsFolder = 'Snippets';
    DisplayName = 'Atlas IDE Expert';
    Publisher = 'Atlas';
    /// <summary>Dateien neben den BPLs; whatsnew.json für die Karte „Neu in Atlas“ (#756), tips.json für die
    /// Karte „Atlas entdecken“ und die Tastenkürzel-Tipps (#757), EULA.txt für die Zustimmung im Installer.</summary>
    CommonFiles: array[0..6] of string = (ServerExe, SetupExe, 'LICENSE', 'EULA.txt', 'THIRD-PARTY-NOTICES.md',
      'whatsnew.json', 'tips.json');
    /// <summary>Beispieldateien für „Ausprobieren“ der Karten „Neu in Atlas“ (#756) und „Atlas entdecken“ (#757);
    /// ersetzt bei jeder Installation den ganzen Ordner.</summary>
    SamplesFolder = 'Beispiele';
    /// <summary>Bilder der Karte „Atlas entdecken“ (#757); ersetzt bei jeder Installation den ganzen Ordner.
    /// </summary>
    TipsFolder = 'Tipps';
    /// <summary>Lokale HTML-Doku für den Knopf „Atlas-Doku“ der Willkommensseite (#766, Tools/Build-Docs.ps1);
    /// ersetzt bei jeder Installation den ganzen Ordner.</summary>
    DocsFolder = 'Doku';
    /// <summary>Vorlagen für atlas.json der Einrichtung „Projekt für Atlas einrichten“ (#759); ersetzt bei jeder
    /// Installation den ganzen Ordner.</summary>
    TemplatesFolder = 'Vorlagen';
    /// <summary>Ordner, die bei jeder Installation vollständig ersetzt werden.</summary>
    DataFolders: array[0..3] of string = (SamplesFolder, TipsFolder, DocsFolder, TemplatesFolder);
  private
    FSystem: ISetupSystem;
    FPaths: TSetupPaths;
    FVersion: string;
    FOnStep: TProc<TSetupStep>;
    procedure Report(AKind: TSetupStepKind; const ASubject: string);
    function SourcePackage(const AIde: TSetupIde): string;
    function TargetPackage(const AIde: TSetupIde): string;
    function FindIdes(const AVersions: TArray<string>; const ARootOf: TFunc<string, string>): TArray<TSetupIde>;
    procedure AddIde(var AIdes: TArray<TSetupIde>; const AVersion, ARootDir: string);
    function IsKnown(const AIdes: TArray<TSetupIde>; const AVersion: string): Boolean;
    function HasAtlas(const AKey: string): Boolean;
    function RemoveAtlas(const AKey: string): Boolean;
    procedure CopyFiles(const AIdes: TArray<TSetupIde>);
    /// <summary>Ordner AFolder aus dem Paket in den Installationsordner (Beispiele, Bilder der Tipps).</summary>
    procedure CopyFolder(const AFolder: string);
    procedure Register(const AIde: TSetupIde);
    procedure WriteUninstallEntry;
    procedure RemoveRegistrations;
    procedure RemoveData(AData: TSetupDataSet);
    function InstalledSize: Int64;
  public
    constructor Create(const ASystem: ISetupSystem; const APaths: TSetupPaths; const AVersion: string);
    /// <summary>Alle gefundenen IDEs (Benutzer- und Rechner-Registry), sortiert; auch nicht angebotene.</summary>
    function Detect: TArray<TSetupIde>;
    /// <summary>Die IDEs aus AIdes, deren bds.exe gerade läuft.</summary>
    function RunningIdes(const AIdes: TArray<TSetupIde>): TArray<TSetupIde>;
    /// <summary>Dateien kopieren, die IDEs registrieren, Deinstallationseintrag schreiben.
    /// Nicht angebotene IDEs werden übergangen. False nach einem Fehler (als Schritt gemeldet).</summary>
    function Install(const AIdes: TArray<TSetupIde>): Boolean;
    /// <summary>Registrierungen in allen IDE-Versionen, Dateien und Deinstallationseintrag entfernen;
    /// ARunningFromInstallDir: der Installer läuft selbst aus dem Zielordner,
    /// der dann nach dem Ende gelöscht wird.</summary>
    function Uninstall(AData: TSetupDataSet; ARunningFromInstallDir: Boolean): Boolean;
    /// <summary>Kennung entfernter Daten im Schritt DataRemoved.</summary>
    class function DataId(AData: TSetupData): string; static;
    /// <summary>Installierte Version laut Registry, '' wenn Atlas nicht installiert ist.</summary>
    function InstalledVersion: string;
    property OnStep: TProc<TSetupStep> read FOnStep write FOnStep;
    property Paths: TSetupPaths read FPaths;
    property Version: string read FVersion;
  end;

implementation

const
  // Der Installer läuft unter Windows; der Kern trennt Pfade selbst, damit er überall gleich rechnet.
  Delim = '\';
  RoamingFiles: array[0..2] of string = ('settings-history.json', 'palette.json', 'usage.json');
  PackageListSuffixes: array[0..1] of string = ('', ' x64');

function Join(const ADir, AName: string): string;
begin
  Result := ADir;
  if (Result <> '') and not CharInSet(Result[Length(Result)], ['\', '/']) then
    Result := Result + Delim;
  Result := Result + AName;
end;

function TrimDelim(const ADir: string): string;
begin
  Result := ADir;
  while (Length(Result) > 3) and CharInSet(Result[Length(Result)], ['\', '/']) do
    SetLength(Result, Length(Result) - 1);
end;

{ TSetupStep }

class function TSetupStep.Make(AKind: TSetupStepKind; const ASubject: string): TSetupStep;
begin
  Result.Kind := AKind;
  Result.Subject := ASubject;
end;

{ TSetupInstaller }

constructor TSetupInstaller.Create(const ASystem: ISetupSystem; const APaths: TSetupPaths;
  const AVersion: string);
begin
  inherited Create;
  FSystem := ASystem;
  FPaths := APaths;
  FVersion := AVersion;
end;

procedure TSetupInstaller.Report(AKind: TSetupStepKind; const ASubject: string);
begin
  if Assigned(FOnStep) then
    FOnStep(TSetupStep.Make(AKind, ASubject));
end;

function TSetupInstaller.SourcePackage(const AIde: TSetupIde): string;
begin
  Result := Join(Join(FPaths.SourceDir, TSetupIdes.PlatformFolder(AIde.Platform)), AIde.PackageFileName);
end;

function TSetupInstaller.TargetPackage(const AIde: TSetupIde): string;
begin
  Result := Join(Join(FPaths.InstallDir, TSetupIdes.PlatformFolder(AIde.Platform)), AIde.PackageFileName);
end;

function TSetupInstaller.HasAtlas(const AKey: string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in FSystem.ValueNames(AKey) do
    if TSetupIdes.IsAtlasPackage(Name) then
      Exit(True);
end;

function TSetupInstaller.RemoveAtlas(const AKey: string): Boolean;
var
  Name: string;
begin
  Result := False;
  for Name in FSystem.ValueNames(AKey) do
    if TSetupIdes.IsAtlasPackage(Name) then
    begin
      FSystem.DeleteValue(AKey, Name);
      Result := True;
    end;
end;

function TSetupInstaller.IsKnown(const AIdes: TArray<TSetupIde>; const AVersion: string): Boolean;
var
  Ide: TSetupIde;
begin
  Result := False;
  for Ide in AIdes do
    if Ide.Info.BdsVersion = AVersion then
      Exit(True);
end;

procedure TSetupInstaller.AddIde(var AIdes: TArray<TSetupIde>; const AVersion, ARootDir: string);
const
  BinFolders: array[TSetupPlatform] of string = ('bin', 'bin64');
var
  Platform: TSetupPlatform;
  Ide: TSetupIde;
begin
  for Platform := Low(TSetupPlatform) to High(TSetupPlatform) do
  begin
    Ide := Default(TSetupIde);
    Ide.Info := TSetupIdes.Lookup(AVersion);
    Ide.Platform := Platform;
    Ide.RootDir := TrimDelim(ARootDir);
    Ide.Executable := Join(Join(Ide.RootDir, BinFolders[Platform]), 'bds.exe');
    if not FSystem.FileExists(Ide.Executable) then
      Continue;
    if not Ide.Info.Supported then
      Ide.Unavailable := TSetupUnavailable.VersionUnsupported
    else if not FSystem.FileExists(SourcePackage(Ide)) then
      Ide.Unavailable := TSetupUnavailable.PackageMissing;
    Ide.Installed := HasAtlas(Ide.KnownPackagesKey);
    AIdes := AIdes + [Ide];
  end;
end;

function TSetupInstaller.FindIdes(const AVersions: TArray<string>;
  const ARootOf: TFunc<string, string>): TArray<TSetupIde>;
var
  Version, Root: string;
begin
  Result := nil;
  for Version in AVersions do
  begin
    if not TSetupIdes.IsVersionKey(Version) then
      Continue;
    Root := ARootOf(Version);
    if Root <> '' then
      AddIde(Result, Version, Root);
  end;
end;

function TSetupInstaller.Detect: TArray<TSetupIde>;
var
  MachineKey, Version, Root: string;
  Ide: TSetupIde;
  Found: TArray<TSetupIde>;
begin
  // Zuerst der Benutzerzweig (dort liest die IDE Known Packages), dann ergänzend der Rechnerzweig.
  Result := FindIdes(FSystem.SubKeys(TSetupIdes.BdsKey),
    function(AVersion: string): string
    begin
      Result := FSystem.ReadString(TSetupIdes.BdsKey + '\' + AVersion, 'RootDir');
    end);
  for MachineKey in TSetupIdes.MachineBdsKeys do
    for Version in FSystem.MachineSubKeys(MachineKey) do
    begin
      if not TSetupIdes.IsVersionKey(Version) or IsKnown(Result, Version) then
        Continue;
      Root := FSystem.MachineReadString(MachineKey + '\' + Version, 'RootDir');
      if Root = '' then
        Continue;
      Found := nil;
      AddIde(Found, Version, Root);
      for Ide in Found do
        Result := Result + [Ide];
    end;
  TSetupIdes.Sort(Result);
end;

function TSetupInstaller.RunningIdes(const AIdes: TArray<TSetupIde>): TArray<TSetupIde>;
var
  Running: TArray<string>;
  Ide: TSetupIde;
  Exe: string;
begin
  Result := nil;
  Running := FSystem.RunningExecutables;
  for Ide in AIdes do
    for Exe in Running do
      if SameText(Exe, Ide.Executable) then
      begin
        Result := Result + [Ide];
        Break;
      end;
end;

procedure TSetupInstaller.CopyFiles(const AIdes: TArray<TSetupIde>);
var
  Name, Source, Target: string;
  Ide: TSetupIde;
begin
  for Name in CommonFiles do
  begin
    Source := Join(FPaths.SourceDir, Name);
    Target := Join(FPaths.InstallDir, Name);
    // Startet der Installer schon aus dem Zielordner (Reparatur), ist nichts zu kopieren.
    if not FSystem.FileExists(Source) or SameText(Source, Target) then
      Continue;
    FSystem.CopyFile(Source, Target);
    Report(TSetupStepKind.FileCopied, Name);
  end;
  for Name in DataFolders do
    CopyFolder(Name);
  for Ide in AIdes do
  begin
    if not Ide.Available then
      Continue;
    Source := SourcePackage(Ide);
    Target := TargetPackage(Ide);
    if SameText(Source, Target) then
      Continue;
    FSystem.CopyFile(Source, Target);
    Report(TSetupStepKind.FileCopied, Join(TSetupIdes.PlatformFolder(Ide.Platform), Ide.PackageFileName));
  end;
end;

procedure TSetupInstaller.CopyFolder(const AFolder: string);
var
  Source, Target, Name: string;
  Names: TArray<string>;
begin
  Source := Join(FPaths.SourceDir, AFolder);
  Target := Join(FPaths.InstallDir, AFolder);
  if SameText(Source, Target) then
    Exit;
  Names := FSystem.FilesIn(Source);
  // Ohne den Ordner im Paket bleibt ein vorhandener, sonst gelten genau die neuen Dateien.
  if Length(Names) = 0 then
    Exit;
  FSystem.DeleteDirectory(Target);
  for Name in Names do
  begin
    FSystem.CopyFile(Join(Source, Name), Join(Target, Name));
    Report(TSetupStepKind.FileCopied, Join(AFolder, Name));
  end;
end;

procedure TSetupInstaller.Register(const AIde: TSetupIde);
begin
  // Alte Registrierungen (andere Pfade, frühere Namen) und eine Abschaltung durch die IDE entfernen.
  RemoveAtlas(AIde.KnownPackagesKey);
  RemoveAtlas(AIde.DisabledPackagesKey);
  FSystem.WriteString(AIde.KnownPackagesKey, TargetPackage(AIde), TSetupIdes.PackageDescription);
  Report(TSetupStepKind.Registered, AIde.Info.ProductName + ' (' + TSetupIdes.PlatformFolder(AIde.Platform) + ')');
end;

function TSetupInstaller.InstalledSize: Int64;
var
  Name, Folder: string;
  Path: string;
  Platform: TSetupPlatform;
  Info: TSetupVersionInfo;
  Ide: TSetupIde;
begin
  Result := 0;
  for Name in CommonFiles do
  begin
    Path := Join(FPaths.InstallDir, Name);
    if FSystem.FileExists(Path) then
      Inc(Result, FSystem.FileSize(Path));
  end;
  for Folder in DataFolders do
    for Name in FSystem.FilesIn(Join(FPaths.InstallDir, Folder)) do
      Inc(Result, FSystem.FileSize(Join(Join(FPaths.InstallDir, Folder), Name)));
  for Info in TSetupIdes.SupportedVersions do
    for Platform := Low(TSetupPlatform) to High(TSetupPlatform) do
    begin
      Ide := Default(TSetupIde);
      Ide.Info := Info;
      Ide.Platform := Platform;
      Path := TargetPackage(Ide);
      if FSystem.FileExists(Path) then
        Inc(Result, FSystem.FileSize(Path));
    end;
end;

procedure TSetupInstaller.WriteUninstallEntry;
var
  Dir: string;
begin
  Dir := TrimDelim(FPaths.InstallDir);
  FSystem.WriteString(UninstallKey, 'DisplayName', DisplayName);
  FSystem.WriteString(UninstallKey, 'DisplayVersion', FVersion);
  FSystem.WriteString(UninstallKey, 'Publisher', Publisher);
  FSystem.WriteString(UninstallKey, 'InstallLocation', Dir);
  FSystem.WriteString(UninstallKey, 'DisplayIcon', Join(Dir, SetupExe));
  FSystem.WriteString(UninstallKey, 'UninstallString', '"' + Join(Dir, SetupExe) + '" /uninstall');
  FSystem.WriteInteger(UninstallKey, 'NoModify', 1);
  FSystem.WriteInteger(UninstallKey, 'NoRepair', 1);
  // In KB, wie „Apps und Features“ es erwartet.
  FSystem.WriteInteger(UninstallKey, 'EstimatedSize', Integer(InstalledSize div 1024));
  FSystem.WriteString(SetupKey, 'InstallDir', Dir);
  FSystem.WriteString(SetupKey, 'Version', FVersion);
  Report(TSetupStepKind.UninstallEntryWritten, DisplayName);
end;

function TSetupInstaller.Install(const AIdes: TArray<TSetupIde>): Boolean;
var
  Ide: TSetupIde;
begin
  Result := False;
  try
    CopyFiles(AIdes);
    for Ide in AIdes do
      if Ide.Available then
        Register(Ide);
    WriteUninstallEntry;
    Result := True;
  except
    on E: Exception do
      Report(TSetupStepKind.Failed, E.Message);
  end;
end;

procedure TSetupInstaller.RemoveRegistrations;
var
  Version, Key, Suffix: string;
  Removed: Boolean;
begin
  // Alle Versionen, auch nicht unterstützte: dort könnte eine Hand-Installation stehen.
  for Version in FSystem.SubKeys(TSetupIdes.BdsKey) do
  begin
    if not TSetupIdes.IsVersionKey(Version) then
      Continue;
    Key := TSetupIdes.BdsKey + '\' + Version;
    Removed := False;
    for Suffix in PackageListSuffixes do
    begin
      if RemoveAtlas(Key + '\Known Packages' + Suffix) then
        Removed := True;
      if RemoveAtlas(Key + '\Disabled Packages' + Suffix) then
        Removed := True;
    end;
    if Removed then
      Report(TSetupStepKind.RegistrationRemoved, TSetupIdes.Lookup(Version).ProductName);
  end;
end;

procedure TSetupInstaller.RemoveData(AData: TSetupDataSet);
var
  Name: string;
  Snippets: string;
begin
  Snippets := Join(FPaths.RoamingDataDir, SnippetsFolder);
  if TSetupData.Settings in AData then
  begin
    FSystem.DeleteKey(SettingsKey);
    if FSystem.DirectoryExists(FPaths.RoamingDataDir) then
    begin
      // Die Snippets gehören dem Benutzer und haben ein eigenes Kästchen.
      if TSetupData.Snippets in AData then
        FSystem.DeleteDirectory(FPaths.RoamingDataDir)
      else
        for Name in RoamingFiles do
          if FSystem.FileExists(Join(FPaths.RoamingDataDir, Name)) then
            FSystem.DeleteFile(Join(FPaths.RoamingDataDir, Name));
    end;
    Report(TSetupStepKind.DataRemoved, DataId(TSetupData.Settings));
  end;
  if TSetupData.IndexAndLogs in AData then
  begin
    FSystem.DeleteDirectory(FPaths.LocalDataDir);
    Report(TSetupStepKind.DataRemoved, DataId(TSetupData.IndexAndLogs));
  end;
  if TSetupData.Snippets in AData then
  begin
    FSystem.DeleteDirectory(Snippets);
    Report(TSetupStepKind.DataRemoved, DataId(TSetupData.Snippets));
  end;
end;

function TSetupInstaller.Uninstall(AData: TSetupDataSet; ARunningFromInstallDir: Boolean): Boolean;
begin
  Result := False;
  try
    RemoveRegistrations;
    if ARunningFromInstallDir then
    begin
      FSystem.DeleteDirectoryLater(FPaths.InstallDir);
      Report(TSetupStepKind.FilesRemovedLater, TrimDelim(FPaths.InstallDir));
    end
    else
    begin
      FSystem.DeleteDirectory(FPaths.InstallDir);
      Report(TSetupStepKind.FilesRemoved, TrimDelim(FPaths.InstallDir));
    end;
    FSystem.DeleteKey(UninstallKey);
    FSystem.DeleteKey(SetupKey);
    Report(TSetupStepKind.UninstallEntryRemoved, DisplayName);
    RemoveData(AData);
    Result := True;
  except
    on E: Exception do
      Report(TSetupStepKind.Failed, E.Message);
  end;
end;

class function TSetupInstaller.DataId(AData: TSetupData): string;
const
  Ids: array[TSetupData] of string = ('Settings', 'IndexAndLogs', 'Snippets');
begin
  Result := Ids[AData];
end;

function TSetupInstaller.InstalledVersion: string;
begin
  Result := FSystem.ReadString(SetupKey, 'Version');
end;

end.
