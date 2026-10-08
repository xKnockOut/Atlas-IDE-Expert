unit BDLsp.Windows.Projects.DelphiInstallation;

// Bibliothekspfade einer Delphi-Installation aus der Registry.
//
//   HKCU\Software\Embarcadero\BDS\<Version>\Library\<Plattform>\Search Path
//   HKCU\Software\Embarcadero\BDS\<Version>\Library\<Plattform>\Browsing Path
//   HKCU\Software\Embarcadero\BDS\<Version>\Environment Variables
//   HKLM\SOFTWARE\(WOW6432Node\)Embarcadero\BDS\<Version>\RootDir
//
// Verweise wie $(BDSLIB) und $(Platform) werden aufgelöst. Variablen aus
// "Environment Variables" haben Vorrang vor den eingebauten, die
// Umgebungsvariablen des Prozesses gelten zuletzt.
// Beispiele für Versionen: 23.0 = Delphi 12, 37.0 = Delphi 13.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  BDLsp.Common.Projects.Contract;

type
  TDelphiInstallation = class(TInterfacedObject, ILibraryPathProvider)
  private
    FVersion: string;
    FRootDir: string;
    FVariables: TArray<TPair<string, string>>;
    function ReadPaths(const APlatform, AValueName: string): TArray<string>;
    function ExpandFor(const AText, APlatform: string): string;
    procedure LoadVariables;
  public
    /// <summary>Installierte Versionen (z. B. "37.0"), aufsteigend sortiert.</summary>
    class function Versions: TArray<string>; static;
    /// <summary>Neueste Installation oder nil, wenn keine gefunden wurde.</summary>
    class function Latest: ILibraryPathProvider; static;
    /// <summary>EProjectError, wenn die Version nicht installiert ist.</summary>
    constructor Create(const AVersion: string);
    { ILibraryPathProvider }
    function LibraryPaths(const APlatform: string): TArray<string>;
    function BrowsingPaths(const APlatform: string): TArray<string>;
    function Variables: TArray<TPair<string, string>>;
    property Version: string read FVersion;
    property RootDir: string read FRootDir;
  end;

implementation

uses
  System.Classes,
  System.Generics.Defaults,
  System.Win.Registry,
  Winapi.Windows,
  Winapi.ShlObj,
  BDLsp.Common.Projects.Paths;

const
  BdsKey = 'Software\Embarcadero\BDS';
  // Die IDE ist eine 32-Bit-Anwendung; ihre HKLM-Einträge liegen je nach Version in einer der Ansichten.
  RegistryViews: array[0..1] of LongWord = (KEY_READ, KEY_READ or KEY_WOW64_32KEY);
  EnvironmentNames: array[0..4] of string = ('PUBLIC', 'USERPROFILE', 'APPDATA', 'ProgramFiles', 'ProgramFiles(x86)');

function OpenRead(ARoot: HKEY; const AKey: string; AAccess: LongWord = KEY_READ): TRegistry;
begin
  Result := TRegistry.Create(AAccess);
  Result.RootKey := ARoot;
  if not Result.OpenKeyReadOnly(AKey) then
    FreeAndNil(Result);
end;

function FolderPath(AFolder: Integer): string;
var
  Buffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, AFolder, 0, SHGFP_TYPE_CURRENT, Buffer) = S_OK then
    Result := Buffer
  else
    Result := '';
end;

function CompareVersions(const A, B: string): Integer;
var
  NumberA: Double;
  NumberB: Double;
begin
  NumberA := StrToFloatDef(A, 0, TFormatSettings.Invariant);
  NumberB := StrToFloatDef(B, 0, TFormatSettings.Invariant);
  if NumberA < NumberB then
    Result := -1
  else if NumberA > NumberB then
    Result := 1
  else
    Result := 0;
end;

function ReadRootDir(const AVersion: string): string;
var
  Registry: TRegistry;
  Access: LongWord;
begin
  Result := '';
  for Access in RegistryViews do
  begin
    Registry := OpenRead(HKEY_LOCAL_MACHINE, BdsKey + '\' + AVersion, Access);
    if Registry <> nil then
      try
        if Registry.ValueExists('RootDir') then
          Result := ExcludeTrailingPathDelimiter(Registry.ReadString('RootDir'));
      finally
        Registry.Free;
      end;
    if Result <> '' then
      Exit;
  end;
  Registry := OpenRead(HKEY_CURRENT_USER, BdsKey + '\' + AVersion);
  if Registry <> nil then
    try
      if Registry.ValueExists('RootDir') then
        Result := ExcludeTrailingPathDelimiter(Registry.ReadString('RootDir'));
    finally
      Registry.Free;
    end;
end;

{ TDelphiInstallation }

class function TDelphiInstallation.Versions: TArray<string>;
var
  Registry: TRegistry;
  Names: TStringList;
  Found: TList<string>;
  Name: string;
begin
  Found := TList<string>.Create;
  Names := TStringList.Create;
  try
    Registry := OpenRead(HKEY_CURRENT_USER, BdsKey);
    if Registry <> nil then
      try
        Registry.GetKeyNames(Names);
      finally
        Registry.Free;
      end;
    for Name in Names do
      if (StrToFloatDef(Name, 0, TFormatSettings.Invariant) > 0) and (ReadRootDir(Name) <> '') then
        Found.Add(Name);
    Found.Sort(TComparer<string>.Construct(CompareVersions));
    Result := Found.ToArray;
  finally
    Names.Free;
    Found.Free;
  end;
end;

class function TDelphiInstallation.Latest: ILibraryPathProvider;
var
  Installed: TArray<string>;
begin
  Installed := Versions;
  if Length(Installed) = 0 then
    Result := nil
  else
    Result := TDelphiInstallation.Create(Installed[High(Installed)]);
end;

constructor TDelphiInstallation.Create(const AVersion: string);
begin
  inherited Create;
  FVersion := AVersion;
  FRootDir := ReadRootDir(AVersion);
  if FRootDir = '' then
    raise EProjectError.CreateFmt('Delphi-Version %s ist nicht installiert', [AVersion]);
  LoadVariables;
end;

procedure TDelphiInstallation.LoadVariables;
var
  Values: TList<TPair<string, string>>;
  Registry: TRegistry;
  Names: TStringList;
  Name: string;
  StudioFolder: string;
begin
  Values := TList<TPair<string, string>>.Create;
  Names := TStringList.Create;
  try
    // Benutzerdefinierte Variablen der IDE zuerst, damit sie Vorrang haben.
    Registry := OpenRead(HKEY_CURRENT_USER, BdsKey + '\' + FVersion + '\Environment Variables');
    if Registry <> nil then
      try
        Registry.GetValueNames(Names);
        for Name in Names do
          Values.Add(TPair<string, string>.Create(Name, Registry.ReadString(Name)));
      finally
        Registry.Free;
      end;
    StudioFolder := 'Embarcadero\Studio\' + FVersion;
    Values.Add(TPair<string, string>.Create('BDS', FRootDir));
    Values.Add(TPair<string, string>.Create('BDSBIN', FRootDir + '\bin'));
    Values.Add(TPair<string, string>.Create('BDSLIB', FRootDir + '\lib'));
    Values.Add(TPair<string, string>.Create('BDSINCLUDE', FRootDir + '\include'));
    Values.Add(TPair<string, string>.Create('BDSCOMMONDIR', IncludeTrailingPathDelimiter(FolderPath(CSIDL_COMMON_DOCUMENTS)) + StudioFolder));
    Values.Add(TPair<string, string>.Create('BDSUSERDIR', IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + StudioFolder));
    Values.Add(TPair<string, string>.Create('BDSCatalogRepository', IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + StudioFolder + '\CatalogRepository'));
    for Name in EnvironmentNames do
      if GetEnvironmentVariable(Name) <> '' then
        Values.Add(TPair<string, string>.Create(Name, GetEnvironmentVariable(Name)));
    FVariables := Values.ToArray;
  finally
    Names.Free;
    Values.Free;
  end;
end;

function TDelphiInstallation.ExpandFor(const AText, APlatform: string): string;
var
  Index: Integer;
begin
  Result := AText;
  // Variablen dürfen auf andere verweisen; drei Durchgänge genügen in der Praxis.
  for Index := 1 to 3 do
  begin
    Result := TProjectPaths.ExpandVariables(Result,
      FVariables + [TPair<string, string>.Create('Platform', APlatform)]);
    if Pos('$(', Result) = 0 then
      Break;
  end;
end;

function TDelphiInstallation.ReadPaths(const APlatform, AValueName: string): TArray<string>;
var
  Registry: TRegistry;
  Items: TList<string>;
  Item: string;
begin
  Items := TList<string>.Create;
  try
    Registry := OpenRead(HKEY_CURRENT_USER, BdsKey + '\' + FVersion + '\Library\' + APlatform);
    if Registry <> nil then
      try
        if Registry.ValueExists(AValueName) then
          for Item in TProjectPaths.SplitList(Registry.ReadString(AValueName)) do
            Items.Add(TProjectPaths.Normalize(ExpandFor(Item, APlatform)));
      finally
        Registry.Free;
      end;
    Result := Items.ToArray;
  finally
    Items.Free;
  end;
end;

function TDelphiInstallation.LibraryPaths(const APlatform: string): TArray<string>;
begin
  Result := ReadPaths(APlatform, 'Search Path');
end;

function TDelphiInstallation.BrowsingPaths(const APlatform: string): TArray<string>;
begin
  Result := ReadPaths(APlatform, 'Browsing Path');
end;

function TDelphiInstallation.Variables: TArray<TPair<string, string>>;
begin
  Result := FVariables;
end;

end.
