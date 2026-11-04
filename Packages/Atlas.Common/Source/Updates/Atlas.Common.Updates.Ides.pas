unit Atlas.Common.Updates.Ides;

// Platform-Feature "Updates" (#1519), Root: Delphi-Versionen und ihre
// Registry-Profile.
// - CompilerVersion (so nennt das Plugin seine IDE, z. B. „36.0“) und
//   BDS-Version der Registry (Delphi 12: 23.0) sind verschieden; ab Delphi 13
//   sind beide 37.0.
// - Ein Profil ist ein Schlüssel HKCU\Software\Embarcadero\<Profil>\<BDS>;
//   das Standardprofil heißt BDS, eigene entstehen mit bds -r <Profil>.
// - Die BPLs tragen die Package-Version als Endung (Delphi 12: 290, 13: 370).
// - Die klassische IDE (Win32-BPLs) liest „Known Packages“, die 64-Bit-IDE
//   (Win64-BPLs, ab Delphi 12.3) „Known Packages x64“.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateIdeVersion = record
    CompilerVersion: string;
    BdsVersion: string;
    ProductName: string;
    /// <summary>Versionsendung der BPLs (LIBSUFFIX AUTO), z. B. 370.</summary>
    Suffix: string;
  end;

  /// <summary>Ein Profil einer IDE: Registry-Basis und Plattform.</summary>
  TUpdateIdeProfile = record
    /// <summary>z. B. Software\Embarcadero\BDS\37.0.</summary>
    RegistryKey: string;
    BdsVersion: string;
    /// <summary>BDS für das Standardprofil, sonst der Name aus bds -r.</summary>
    Profile: string;
    function Caption: string;
  end;

  TUpdateIdes = class
  public const
    EmbarcaderoKey = 'Software\Embarcadero';
    DefaultProfile = 'BDS';
    Win32 = 'Win32';
    Win64 = 'Win64';
  public
    /// <summary>Bekannte Version zu ACompilerVersion; False für unbekannte.</summary>
    class function ByCompilerVersion(const ACompilerVersion: string; out AVersion: TUpdateIdeVersion): Boolean;
      static;
    class function ByBdsVersion(const ABdsVersion: string; out AVersion: TUpdateIdeVersion): Boolean; static;
    /// <summary>BDS-Version am Ende von ARegistryKey („…\37.0“); '' ohne.</summary>
    class function BdsVersionOf(const ARegistryKey: string): string; static;
    class function KnownPackagesKey(const ARegistryKey, APlatform: string): string; static;
    class function DisabledPackagesKey(const ARegistryKey, APlatform: string): string; static;
    /// <summary>Alle Profile von ABdsVersion unter HKCU (das Standardprofil zuerst).</summary>
    class function Profiles(const ARegistry: IUpdateRegistry; const ABdsVersion: string): TArray<TUpdateIdeProfile>;
      static;
    class function IsPlatform(const APlatform: string): Boolean; static;
    /// <summary>Versionsendung der BPLs zur CompilerVersion („37.0“ → 370, „36.0“ → 290); unbekannte Versionen
    /// ohne Punkt („38.0“ → 380).</summary>
    class function PackageSuffix(const ACompilerVersion: string): string; static;
  end;

implementation

uses
  System.Generics.Collections;

const
  cCatalog: array[0..1] of TUpdateIdeVersion = (
    (CompilerVersion: '37.0'; BdsVersion: '37.0'; ProductName: 'Delphi 13 Florence'; Suffix: '370'),
    (CompilerVersion: '36.0'; BdsVersion: '23.0'; ProductName: 'Delphi 12 Athens'; Suffix: '290'));

{ TUpdateIdeProfile }

function TUpdateIdeProfile.Caption: string;
var
  mVersion: TUpdateIdeVersion;
begin
  if TUpdateIdes.ByBdsVersion(BdsVersion, mVersion) then
  begin
    Result := mVersion.ProductName;
  end
  else
  begin
    Result := 'RAD Studio ' + BdsVersion;
  end;
  if not SameText(Profile, TUpdateIdes.DefaultProfile) then
  begin
    Result := Result + ' (' + Profile + ')';
  end;
end;

{ TUpdateIdes }

class function TUpdateIdes.ByCompilerVersion(const ACompilerVersion: string; out AVersion: TUpdateIdeVersion): Boolean;
var
  mEntry: TUpdateIdeVersion;
begin
  AVersion := Default(TUpdateIdeVersion);
  for mEntry in cCatalog do
  begin
    if mEntry.CompilerVersion = ACompilerVersion then
    begin
      AVersion := mEntry;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUpdateIdes.ByBdsVersion(const ABdsVersion: string; out AVersion: TUpdateIdeVersion): Boolean;
var
  mEntry: TUpdateIdeVersion;
begin
  AVersion := Default(TUpdateIdeVersion);
  for mEntry in cCatalog do
  begin
    if mEntry.BdsVersion = ABdsVersion then
    begin
      AVersion := mEntry;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUpdateIdes.BdsVersionOf(const ARegistryKey: string): string;
begin
  Result := ARegistryKey.Replace('/', '\');
  while Result.EndsWith('\') do
  begin
    Result := Result.Substring(0, Length(Result) - 1);
  end;
  Result := Result.Substring(Result.LastDelimiter('\') + 1);
  if (Result = '') or not CharInSet(Result[1], ['0'..'9']) then
  begin
    Result := '';
  end;
end;

class function TUpdateIdes.KnownPackagesKey(const ARegistryKey, APlatform: string): string;
begin
  Result := ARegistryKey + '\Known Packages';
  if SameText(APlatform, Win64) then
  begin
    Result := Result + ' x64';
  end;
end;

class function TUpdateIdes.DisabledPackagesKey(const ARegistryKey, APlatform: string): string;
begin
  Result := ARegistryKey + '\Disabled Packages';
  if SameText(APlatform, Win64) then
  begin
    Result := Result + ' x64';
  end;
end;

class function TUpdateIdes.Profiles(const ARegistry: IUpdateRegistry;
  const ABdsVersion: string): TArray<TUpdateIdeProfile>;
var
  mList: TList<TUpdateIdeProfile>;
  mName, mVersion: string;
  mProfile: TUpdateIdeProfile;
begin
  mList := TList<TUpdateIdeProfile>.Create;
  try
    for mName in ARegistry.SubKeys(EmbarcaderoKey) do
    begin
      for mVersion in ARegistry.SubKeys(EmbarcaderoKey + '\' + mName) do
      begin
        if mVersion <> ABdsVersion then
        begin
          Continue;
        end;
        mProfile := Default(TUpdateIdeProfile);
        mProfile.Profile := mName;
        mProfile.BdsVersion := mVersion;
        mProfile.RegistryKey := EmbarcaderoKey + '\' + mName + '\' + mVersion;
        if SameText(mName, DefaultProfile) then
        begin
          mList.Insert(0, mProfile);
        end
        else
        begin
          mList.Add(mProfile);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateIdes.PackageSuffix(const ACompilerVersion: string): string;
var
  mVersion: TUpdateIdeVersion;
begin
  if ByCompilerVersion(ACompilerVersion, mVersion) then
  begin
    Result := mVersion.Suffix;
  end
  else
  begin
    Result := ACompilerVersion.Replace('.', '');
  end;
end;

class function TUpdateIdes.IsPlatform(const APlatform: string): Boolean;
begin
  Result := SameText(APlatform, Win32) or SameText(APlatform, Win64);
end;

end.
