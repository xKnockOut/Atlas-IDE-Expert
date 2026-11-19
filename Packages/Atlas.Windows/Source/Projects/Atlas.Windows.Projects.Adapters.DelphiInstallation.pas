unit Atlas.Windows.Projects.Adapters.DelphiInstallation;

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
  Atlas.Common.Projects.Contract;

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
  System.Win.Registry,
  Winapi.Windows,
  Winapi.ShlObj,
  Atlas.Common.Projects.Paths,
  Atlas.Windows.Projects.DelphiRegistry;

const
  cEnvironmentNames: array[0..4] of string = ('PUBLIC', 'USERPROFILE', 'APPDATA', 'ProgramFiles', 'ProgramFiles(x86)');

function FolderPath(AFolder: Integer): string;
var
  mBuffer: array[0..MAX_PATH] of Char;
begin
  if SHGetFolderPath(0, AFolder, 0, SHGFP_TYPE_CURRENT, mBuffer) = S_OK then
  begin
    Result := mBuffer;
  end
  else
  begin
    Result := '';
  end;
end;

{ TDelphiInstallation }

constructor TDelphiInstallation.Create(const AVersion: string);
begin
  inherited Create;
  FVersion := AVersion;
  FRootDir := TDelphiRegistry.RootDirOf(AVersion);
  if FRootDir = '' then
  begin
    raise EProjectError.CreateFmt('Delphi-Version %s ist nicht installiert', [AVersion]);
  end;
  LoadVariables;
end;

function TDelphiInstallation.ReadPaths(const APlatform, AValueName: string): TArray<string>;
var
  mRegistry: TRegistry;
  mItem: string;
begin
  Result := nil;
  mRegistry := TDelphiRegistry.OpenRead(HKEY_CURRENT_USER,
    TDelphiRegistry.cBdsKey + '\' + FVersion + '\Library\' + APlatform);
  if mRegistry = nil then
  begin
    Exit;
  end;
  try
    if not mRegistry.ValueExists(AValueName) then
    begin
      Exit;
    end;
    for mItem in TProjectPaths.SplitList(mRegistry.ReadString(AValueName)) do
    begin
      Result := Result + [TProjectPaths.Normalize(ExpandFor(mItem, APlatform))];
    end;
  finally
    mRegistry.Free;
  end;
end;

function TDelphiInstallation.ExpandFor(const AText, APlatform: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  // Variablen dürfen auf andere verweisen; drei Durchgänge genügen in der Praxis.
  for mIndex := 1 to 3 do
  begin
    Result := TProjectPaths.ExpandVariables(Result,
      FVariables + [TPair<string, string>.Create('Platform', APlatform)]);
    if Pos('$(', Result) = 0 then
    begin
      Break;
    end;
  end;
end;

procedure TDelphiInstallation.LoadVariables;
var
  mValues: TList<TPair<string, string>>;
  mRegistry: TRegistry;
  mNames: TStringList;
  mName: string;
  mStudioFolder: string;
begin
  mValues := TList<TPair<string, string>>.Create;
  mNames := TStringList.Create;
  try
    // Benutzerdefinierte Variablen der IDE zuerst, damit sie Vorrang haben.
    mRegistry := TDelphiRegistry.OpenRead(HKEY_CURRENT_USER,
      TDelphiRegistry.cBdsKey + '\' + FVersion + '\Environment Variables');
    if mRegistry <> nil then
      try
        mRegistry.GetValueNames(mNames);
        for mName in mNames do
        begin
          mValues.Add(TPair<string, string>.Create(mName, mRegistry.ReadString(mName)));
        end;
      finally
        mRegistry.Free;
      end;
    mStudioFolder := 'Embarcadero\Studio\' + FVersion;
    mValues.Add(TPair<string, string>.Create('BDS', FRootDir));
    mValues.Add(TPair<string, string>.Create('BDSBIN', FRootDir + '\bin'));
    mValues.Add(TPair<string, string>.Create('BDSLIB', FRootDir + '\lib'));
    mValues.Add(TPair<string, string>.Create('BDSINCLUDE', FRootDir + '\include'));
    mValues.Add(TPair<string, string>.Create('BDSCOMMONDIR',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_COMMON_DOCUMENTS)) + mStudioFolder));
    mValues.Add(TPair<string, string>.Create('BDSUSERDIR',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + mStudioFolder));
    mValues.Add(TPair<string, string>.Create('BDSCatalogRepository',
      IncludeTrailingPathDelimiter(FolderPath(CSIDL_PERSONAL)) + mStudioFolder + '\CatalogRepository'));
    for mName in cEnvironmentNames do
    begin
      if GetEnvironmentVariable(mName) <> '' then
      begin
        mValues.Add(TPair<string, string>.Create(mName, GetEnvironmentVariable(mName)));
      end;
    end;
    FVariables := mValues.ToArray;
  finally
    mNames.Free;
    mValues.Free;
  end;
end;

class function TDelphiInstallation.Versions: TArray<string>;
begin
  Result := TDelphiRegistry.Versions;
end;

class function TDelphiInstallation.Latest: ILibraryPathProvider;
var
  mInstalled: TArray<string>;
begin
  mInstalled := Versions;
  if Length(mInstalled) = 0 then
  begin
    Result := nil;
  end
  else
  begin
    Result := TDelphiInstallation.Create(mInstalled[High(mInstalled)]);
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
