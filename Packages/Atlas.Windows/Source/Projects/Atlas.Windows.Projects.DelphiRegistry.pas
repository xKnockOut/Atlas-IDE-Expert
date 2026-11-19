unit Atlas.Windows.Projects.DelphiRegistry;

// Delphi-Installationen in der Registry: installierte Versionen (HKCU\Software\Embarcadero\BDS\<Version>) und
// Installationsordner (RootDir unter HKLM in beiden Ansichten, sonst HKCU). Gemeinsame Grundlage der Bibliothekspfade
// (Atlas.Windows.Projects.Adapters.DelphiInstallation) und des Updates (Known Packages, Bauen aus dem Quelltext).

interface

uses
  System.Win.Registry,
  Winapi.Windows;

type
  TDelphiRegistry = record
  public const
    cBdsKey = 'Software\Embarcadero\BDS';
  public
    /// <summary>Schlüssel AKey nur lesend geöffnet; nil, wenn es ihn nicht gibt. Der Aufrufer gibt frei.</summary>
    class function OpenRead(ARoot: HKEY; const AKey: string; AAccess: LongWord): TRegistry; overload; static;
    /// <summary>Wie oben mit KEY_READ.</summary>
    class function OpenRead(ARoot: HKEY; const AKey: string): TRegistry; overload; static;
    /// <summary>Installierte Versionen (z. B. "37.0"), aufsteigend sortiert.</summary>
    class function Versions: TArray<string>; static;
    /// <summary>Installationsordner der Version (z. B. "37.0") ohne abschließenden Trenner; '' ohne Installation.
    /// </summary>
    class function RootDirOf(const AVersion: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  System.Generics.Defaults;

const
  // Die IDE ist eine 32-Bit-Anwendung; ihre HKLM-Einträge liegen je nach Version in einer der Ansichten.
  cRegistryViews: array[0..1] of LongWord = (KEY_READ, KEY_READ or KEY_WOW64_32KEY);

function CompareVersions(const A, B: string): Integer;
var
  mNumberA: Double;
  mNumberB: Double;
begin
  mNumberA := StrToFloatDef(A, 0, TFormatSettings.Invariant);
  mNumberB := StrToFloatDef(B, 0, TFormatSettings.Invariant);
  if mNumberA < mNumberB then
  begin
    Result := -1;
  end
  else if mNumberA > mNumberB then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

{ TDelphiRegistry }

class function TDelphiRegistry.OpenRead(ARoot: HKEY; const AKey: string; AAccess: LongWord): TRegistry;
begin
  Result := TRegistry.Create(AAccess);
  Result.RootKey := ARoot;
  if not Result.OpenKeyReadOnly(AKey) then
  begin
    FreeAndNil(Result);
  end;
end;

class function TDelphiRegistry.OpenRead(ARoot: HKEY; const AKey: string): TRegistry;
begin
  Result := OpenRead(ARoot, AKey, KEY_READ);
end;

class function TDelphiRegistry.RootDirOf(const AVersion: string): string;
var
  mRegistry: TRegistry;
  mAccess: LongWord;
begin
  Result := '';
  for mAccess in cRegistryViews do
  begin
    mRegistry := OpenRead(HKEY_LOCAL_MACHINE, cBdsKey + '\' + AVersion, mAccess);
    if mRegistry <> nil then
      try
        if mRegistry.ValueExists('RootDir') then
        begin
          Result := ExcludeTrailingPathDelimiter(mRegistry.ReadString('RootDir'));
        end;
      finally
        mRegistry.Free;
      end;
    if Result <> '' then
    begin
      Exit;
    end;
  end;
  mRegistry := OpenRead(HKEY_CURRENT_USER, cBdsKey + '\' + AVersion);
  if mRegistry <> nil then
    try
      if mRegistry.ValueExists('RootDir') then
      begin
        Result := ExcludeTrailingPathDelimiter(mRegistry.ReadString('RootDir'));
      end;
    finally
      mRegistry.Free;
    end;
end;

class function TDelphiRegistry.Versions: TArray<string>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mFound: TList<string>;
  mName: string;
begin
  mFound := TList<string>.Create;
  mNames := TStringList.Create;
  try
    mRegistry := OpenRead(HKEY_CURRENT_USER, cBdsKey);
    if mRegistry <> nil then
      try
        mRegistry.GetKeyNames(mNames);
      finally
        mRegistry.Free;
      end;
    for mName in mNames do
    begin
      if (StrToFloatDef(mName, 0, TFormatSettings.Invariant) > 0) and (RootDirOf(mName) <> '') then
      begin
        mFound.Add(mName);
      end;
    end;
    mFound.Sort(TComparer<string>.Construct(CompareVersions));
    Result := mFound.ToArray;
  finally
    mNames.Free;
    mFound.Free;
  end;
end;

end.
