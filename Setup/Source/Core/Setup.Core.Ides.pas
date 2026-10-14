unit Setup.Core.Ides;

// Installer (#495): bekannte Delphi-Versionen und die gefundenen IDEs.
// - Katalog: BDS-Version (Registry), Produktname, Package-Version (Endung der
//   BPL über {$LIBSUFFIX AUTO}, #281) und ob Atlas sie unterstützt
//   (Delphi 12 und 13). Unbekannte Versionen erscheinen, werden aber nicht
//   angeboten.
// - Je Version gibt es die klassische 32-Bit-IDE (bin\bds.exe) und ab
//   Delphi 12.3 die 64-Bit-IDE (bin64\bds.exe); sie laden verschiedene BPLs
//   (Win32 bzw. Win64) und führen getrennte Listen „Known Packages“ bzw.
//   „Known Packages x64“ unter HKCU\Software\Embarcadero\BDS\<Version>.

interface

uses
  System.SysUtils;

type
{$SCOPEDENUMS ON}
  TSetupPlatform = (Win32, Win64);
  /// <summary>Warum eine gefundene IDE nicht angeboten wird.</summary>
  TSetupUnavailable = (None, VersionUnsupported, PackageMissing);
{$SCOPEDENUMS OFF}

  TSetupVersionInfo = record
    BdsVersion: string;
    ProductName: string;
    PackageSuffix: string;
    Supported: Boolean;
  end;

  TSetupIde = record
    Info: TSetupVersionInfo;
    Platform: TSetupPlatform;
    RootDir: string;
    /// <summary>bin\bds.exe bzw. bin64\bds.exe.</summary>
    Executable: string;
    Unavailable: TSetupUnavailable;
    /// <summary>Atlas steht in „Known Packages“ dieser IDE.</summary>
    Installed: Boolean;
    function Available: Boolean;
    /// <summary>Eindeutig je IDE, z. B. „37.0-Win64“.</summary>
    function Id: string;
    function PackageFileName: string;
    function KnownPackagesKey: string;
    function DisabledPackagesKey: string;
  end;

  TSetupIdes = class
  public const
    BdsKey = 'Software\Embarcadero\BDS';
    MachineBdsKeys: array[0..1] of string = ('Software\Embarcadero\BDS', 'Software\WOW6432Node\Embarcadero\BDS');
    PackagePrefix = 'Atlas.IDE.Expert';
    PackageDescription = 'Atlas IDE Expert';
  public
    /// <summary>Bekannte Version oder ein unbekannter, nicht unterstützter Eintrag
    /// „RAD Studio &lt;Version&gt;“.</summary>
    class function Lookup(const ABdsVersion: string): TSetupVersionInfo; static;
    /// <summary>Unterschlüssel wie „37.0“ (Ziffern, Punkt, Ziffer).</summary>
    class function IsVersionKey(const AName: string): Boolean; static;
    /// <summary>Wert unter „Known Packages“, der Atlas (auch unter altem Namen) lädt.</summary>
    class function IsAtlasPackage(const AValueName: string): Boolean; static;
    class function PlatformFolder(APlatform: TSetupPlatform): string; static;
    /// <summary>Absteigend nach Version, je Version 32-Bit vor 64-Bit.</summary>
    class procedure Sort(var AIdes: TArray<TSetupIde>); static;
    /// <summary>Die Versionen, für die es eine Atlas-BPL gibt.</summary>
    class function SupportedVersions: TArray<TSetupVersionInfo>; static;
    /// <summary>Numerischer Vergleich zweier BDS-Versionen.</summary>
    class function CompareVersions(const A, B: string): Integer; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults;

const
  Catalog: array[0..8] of TSetupVersionInfo = (
    (BdsVersion: '37.0'; ProductName: 'Delphi 13 Florence'; PackageSuffix: '370'; Supported: True),
    (BdsVersion: '23.0'; ProductName: 'Delphi 12 Athens'; PackageSuffix: '290'; Supported: True),
    (BdsVersion: '22.0'; ProductName: 'Delphi 11 Alexandria'; PackageSuffix: '280'; Supported: False),
    (BdsVersion: '21.0'; ProductName: 'Delphi 10.4 Sydney'; PackageSuffix: '270'; Supported: False),
    (BdsVersion: '20.0'; ProductName: 'Delphi 10.3 Rio'; PackageSuffix: '260'; Supported: False),
    (BdsVersion: '19.0'; ProductName: 'Delphi 10.2 Tokyo'; PackageSuffix: '250'; Supported: False),
    (BdsVersion: '18.0'; ProductName: 'Delphi 10.1 Berlin'; PackageSuffix: '240'; Supported: False),
    (BdsVersion: '17.0'; ProductName: 'Delphi 10 Seattle'; PackageSuffix: '230'; Supported: False),
    (BdsVersion: '16.0'; ProductName: 'Delphi XE8'; PackageSuffix: '220'; Supported: False));
  // Frühere Namen des Plugins: Eine alte Registrierung wird beim Installieren ersetzt.
  LegacyPrefixes: array[0..1] of string = ('Argus.IDE.Expert', 'BetterDelphiLSP');

{ TSetupIde }

function TSetupIde.Available: Boolean;
begin
  Result := Unavailable = TSetupUnavailable.None;
end;

function TSetupIde.Id: string;
begin
  Result := Info.BdsVersion + '-' + TSetupIdes.PlatformFolder(Platform);
end;

function TSetupIde.PackageFileName: string;
begin
  Result := TSetupIdes.PackagePrefix + Info.PackageSuffix + '.bpl';
end;

function TSetupIde.KnownPackagesKey: string;
begin
  Result := TSetupIdes.BdsKey + '\' + Info.BdsVersion + '\Known Packages';
  if Platform = TSetupPlatform.Win64 then
    Result := Result + ' x64';
end;

function TSetupIde.DisabledPackagesKey: string;
begin
  Result := TSetupIdes.BdsKey + '\' + Info.BdsVersion + '\Disabled Packages';
  if Platform = TSetupPlatform.Win64 then
    Result := Result + ' x64';
end;

{ TSetupIdes }

class function TSetupIdes.Lookup(const ABdsVersion: string): TSetupVersionInfo;
var
  Info: TSetupVersionInfo;
begin
  for Info in Catalog do
    if Info.BdsVersion = ABdsVersion then
      Exit(Info);
  Result := Default(TSetupVersionInfo);
  Result.BdsVersion := ABdsVersion;
  Result.ProductName := 'RAD Studio ' + ABdsVersion;
end;

class function TSetupIdes.SupportedVersions: TArray<TSetupVersionInfo>;
var
  Info: TSetupVersionInfo;
begin
  Result := nil;
  for Info in Catalog do
    if Info.Supported then
      Result := Result + [Info];
end;

class function TSetupIdes.IsVersionKey(const AName: string): Boolean;
var
  Parts: TArray<string>;
  Part: string;
  C: Char;
begin
  Parts := AName.Split(['.']);
  Result := Length(Parts) = 2;
  for Part in Parts do
  begin
    if Part = '' then
      Exit(False);
    for C in Part do
      if not CharInSet(C, ['0'..'9']) then
        Exit(False);
  end;
end;

class function TSetupIdes.IsAtlasPackage(const AValueName: string): Boolean;
var
  Name, Prefix: string;
begin
  // Werte sind Windows-Pfade; nur der Dateiname zählt.
  Name := AValueName.Substring(AValueName.LastDelimiter('\/') + 1);
  Result := Name.StartsWith(PackagePrefix, True) and Name.EndsWith('.bpl', True);
  for Prefix in LegacyPrefixes do
    if Name.StartsWith(Prefix, True) and Name.EndsWith('.bpl', True) then
      Result := True;
end;

class function TSetupIdes.PlatformFolder(APlatform: TSetupPlatform): string;
begin
  if APlatform = TSetupPlatform.Win64 then
    Result := 'Win64'
  else
    Result := 'Win32';
end;

class function TSetupIdes.CompareVersions(const A, B: string): Integer;
var
  PartsA, PartsB: TArray<string>;
  Index: Integer;
begin
  PartsA := A.Split(['.']);
  PartsB := B.Split(['.']);
  Index := 0;
  while (Index < Length(PartsA)) and (Index < Length(PartsB)) do
  begin
    Result := StrToIntDef(PartsA[Index], 0) - StrToIntDef(PartsB[Index], 0);
    if Result <> 0 then
      Exit;
    Inc(Index);
  end;
  Result := Length(PartsA) - Length(PartsB);
end;

class procedure TSetupIdes.Sort(var AIdes: TArray<TSetupIde>);
begin
  TArray.Sort<TSetupIde>(AIdes, TComparer<TSetupIde>.Construct(
    function(const A, B: TSetupIde): Integer
    begin
      Result := -CompareVersions(A.Info.BdsVersion, B.Info.BdsVersion);
      if Result = 0 then
        Result := Ord(A.Platform) - Ord(B.Platform);
    end));
end;

end.
