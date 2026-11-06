unit Atlas.Common.Updates.KnownPackages;

// Platform-Feature "Updates" (#1519), Root: Einträge unter „Known Packages“.
// - Ein Wert heißt wie der Pfad der BPL, sein Inhalt ist die Beschreibung.
//   Atlas-Werte erkennt der Dateiname (Atlas.IDE.<Teil><Endung>.bpl); frühere
//   Namen des Plugins (Atlas.IDE.Expert aus 1.x, Argus, BetterDelphiLSP)
//   ersetzt eine Installation.
// - Geändert wird nur, was zu Atlas gehört: gewählte Packages aus dem
//   Atlas-Ordner eintragen, abgewählte und doppelte (gleicher Name aus einem
//   anderen Ordner) austragen, ihre Einträge unter „Disabled Packages“
//   entfernen. Fremde Experten bleiben unberührt.
// - Jede Änderung trägt den alten Wert, damit der Rückfall sie genau umkehrt.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
{$SCOPEDENUMS ON}
  TUpdateRegistryChangeKind = (Add, Delete);
{$SCOPEDENUMS OFF}

  TUpdateRegistryChange = record
    Kind: TUpdateRegistryChangeKind;
    Key: string;
    Name: string;
    /// <summary>Neuer Inhalt (Add) bzw. bisheriger Inhalt (Delete).</summary>
    Data: string;
  end;

  /// <summary>Wo die Packages einer IDE liegen und wie sie heißen.</summary>
  TUpdatePackageTarget = record
    /// <summary>Registry-Basis des Profils, z. B. Software\Embarcadero\BDS\37.0.</summary>
    RegistryKey: string;
    Platform: string;
    /// <summary>Ordner der BPLs, z. B. C:\Tools\Atlas\Win32.</summary>
    PackageDir: string;
    /// <summary>Versionsendung der BPLs, z. B. 370.</summary>
    Suffix: string;
    function KnownKey: string;
    function DisabledKey: string;
    function PackageFile(const AName: string): string;
  end;

  TUpdateKnownPackages = class
  public
    /// <summary>Pfade gleich (Groß-/Kleinschreibung, / und \, abschließender Trenner egal).</summary>
    class function SamePath(const A, B: string): Boolean; static;
    class function FolderOf(const APath: string): string; static;
    class function IsAtlasPackage(const AValueName: string): Boolean; static;
    class function IsLegacyPackage(const AValueName: string): Boolean; static;
    /// <summary>Beschreibung eines neuen Eintrags, z. B. „Atlas Debugger“.</summary>
    class function Description(const AName: string): string; static;
    /// <summary>Namen der Packages, die das Profil aus ATarget.PackageDir lädt.</summary>
    class function Registered(const ARegistry: IUpdateRegistry; const ATarget: TUpdatePackageTarget): TArray<string>;
      static;
    /// <summary>Änderungen, damit das Profil genau ASelected aus ATarget.PackageDir lädt.</summary>
    class function Plan(const ARegistry: IUpdateRegistry; const ATarget: TUpdatePackageTarget;
      const ASelected: TArray<string>): TArray<TUpdateRegistryChange>; static;
    /// <summary>Ein anderes Profil (jede Version, beide Listen) außer AExceptKey lädt AFileName.</summary>
    class function UsedElsewhere(const ARegistry: IUpdateRegistry; const AFileName, AExceptKey: string): Boolean;
      static;
    class procedure Apply(const ARegistry: IUpdateRegistry; const AChanges: TArray<TUpdateRegistryChange>); static;
    /// <summary>Macht AChanges rückwärts rückgängig.</summary>
    class procedure Revert(const ARegistry: IUpdateRegistry; const AChanges: TArray<TUpdateRegistryChange>); static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Updates,
  Atlas.Common.Updates.Ides;

const
  cLegacyPrefixes: array[0..2] of string = ('Atlas.IDE.Expert', 'Argus.IDE.Expert', 'BetterDelphiLSP');
  cPackageLists: array[0..3] of string = ('Known Packages', 'Known Packages x64', 'Disabled Packages',
    'Disabled Packages x64');

{ TUpdatePackageTarget }

function TUpdatePackageTarget.KnownKey: string;
begin
  Result := TUpdateIdes.KnownPackagesKey(RegistryKey, Platform);
end;

function TUpdatePackageTarget.DisabledKey: string;
begin
  Result := TUpdateIdes.DisabledPackagesKey(RegistryKey, Platform);
end;

function TUpdatePackageTarget.PackageFile(const AName: string): string;
begin
  Result := PackageDir;
  if not Result.EndsWith('\') then
  begin
    Result := Result + '\';
  end;
  Result := Result + AName + Suffix + '.bpl';
end;

{ TUpdateKnownPackages }

function NormalPath(const APath: string): string;
begin
  Result := LowerCase(APath.Replace('/', '\'));
  while Result.EndsWith('\') do
  begin
    Result := Result.Substring(0, Length(Result) - 1);
  end;
end;

class function TUpdateKnownPackages.SamePath(const A, B: string): Boolean;
begin
  Result := NormalPath(A) = NormalPath(B);
end;

class function TUpdateKnownPackages.FolderOf(const APath: string): string;
var
  mText: string;
begin
  mText := APath.Replace('/', '\');
  Result := mText.Substring(0, mText.LastDelimiter('\'));
end;

function FileNameOf(const APath: string): string;
begin
  Result := APath.Substring(APath.LastDelimiter('\/') + 1);
end;

class function TUpdateKnownPackages.IsAtlasPackage(const AValueName: string): Boolean;
var
  mName: string;
begin
  mName := FileNameOf(AValueName);
  Result := mName.StartsWith(TUpdateVersions.PackagePrefix, True) and mName.EndsWith('.bpl', True) and
    not IsLegacyPackage(AValueName);
end;

class function TUpdateKnownPackages.IsLegacyPackage(const AValueName: string): Boolean;
var
  mName, mPrefix: string;
begin
  mName := FileNameOf(AValueName);
  Result := False;
  for mPrefix in cLegacyPrefixes do
  begin
    if mName.StartsWith(mPrefix, True) and mName.EndsWith('.bpl', True) then
    begin
      Result := True;
    end;
  end;
end;

class function TUpdateKnownPackages.Description(const AName: string): string;
begin
  Result := 'Atlas ' + AName.Substring(Length(TUpdateVersions.PackagePrefix));
end;

class function TUpdateKnownPackages.Registered(const ARegistry: IUpdateRegistry;
  const ATarget: TUpdatePackageTarget): TArray<string>;
var
  mValue: TUpdateRegistryValue;
  mList: TList<string>;
begin
  mList := TList<string>.Create;
  try
    for mValue in ARegistry.Values(ATarget.KnownKey) do
    begin
      if IsAtlasPackage(mValue.Name) and SamePath(FolderOf(mValue.Name), ATarget.PackageDir) then
      begin
        mList.Add(TUpdateVersions.PackageName(mValue.Name));
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function Change(AKind: TUpdateRegistryChangeKind; const AKey, AName, AData: string): TUpdateRegistryChange;
begin
  Result := Default(TUpdateRegistryChange);
  Result.Kind := AKind;
  Result.Key := AKey;
  Result.Name := AName;
  Result.Data := AData;
end;

function IsSelected(const ASelected: TArray<string>; const AName: string): Boolean;
begin
  Result := IndexText(AName, ASelected) >= 0;
end;

/// <summary>Ein Atlas-Wert, der nach der Installation nicht bleiben soll.</summary>
function IsObsolete(const AValue: TUpdateRegistryValue; const ATarget: TUpdatePackageTarget;
  const ASelected: TArray<string>): Boolean;
var
  mName: string;
begin
  if TUpdateKnownPackages.IsLegacyPackage(AValue.Name) then
  begin
    Exit(True);
  end;
  if not TUpdateKnownPackages.IsAtlasPackage(AValue.Name) then
  begin
    Exit(False);
  end;
  mName := TUpdateVersions.PackageName(AValue.Name);
  // Abgewählt (aus dem Atlas-Ordner) oder gewählt, aber aus einem anderen Ordner bzw. mit anderer Endung.
  if TUpdateKnownPackages.SamePath(TUpdateKnownPackages.FolderOf(AValue.Name), ATarget.PackageDir) then
  begin
    Result := not IsSelected(ASelected, mName) or not TUpdateKnownPackages.SamePath(AValue.Name,
      ATarget.PackageFile(mName));
  end
  else
  begin
    Result := IsSelected(ASelected, mName);
  end;
end;

procedure PlanKnown(AList: TList<TUpdateRegistryChange>; const ARegistry: IUpdateRegistry;
  const ATarget: TUpdatePackageTarget; const ASelected: TArray<string>);
var
  mValue: TUpdateRegistryValue;
  mName: string;
  mPresent: TList<string>;
begin
  mPresent := TList<string>.Create;
  try
    for mValue in ARegistry.Values(ATarget.KnownKey) do
    begin
      if IsObsolete(mValue, ATarget, ASelected) then
      begin
        AList.Add(Change(TUpdateRegistryChangeKind.Delete, ATarget.KnownKey, mValue.Name, mValue.Data));
      end
      else if TUpdateKnownPackages.IsAtlasPackage(mValue.Name) then
      begin
        mPresent.Add(LowerCase(mValue.Name));
      end;
    end;
    for mName in ASelected do
    begin
      if not mPresent.Contains(LowerCase(ATarget.PackageFile(mName))) then
      begin
        AList.Add(Change(TUpdateRegistryChangeKind.Add, ATarget.KnownKey, ATarget.PackageFile(mName),
          TUpdateKnownPackages.Description(mName)));
      end;
    end;
  finally
    mPresent.Free;
  end;
end;

procedure PlanDisabled(AList: TList<TUpdateRegistryChange>; const ARegistry: IUpdateRegistry;
  const ATarget: TUpdatePackageTarget; const ASelected: TArray<string>);
var
  mValue: TUpdateRegistryValue;
begin
  for mValue in ARegistry.Values(ATarget.DisabledKey) do
  begin
    if TUpdateKnownPackages.IsLegacyPackage(mValue.Name) or (TUpdateKnownPackages.IsAtlasPackage(mValue.Name) and
      IsSelected(ASelected, TUpdateVersions.PackageName(mValue.Name))) then
    begin
      AList.Add(Change(TUpdateRegistryChangeKind.Delete, ATarget.DisabledKey, mValue.Name, mValue.Data));
    end;
  end;
end;

/// <summary>Kern und Verträge zuerst, damit die IDE sie vor den Modulen findet (Registry-Reihenfolge).</summary>
function Ordered(const ASelected: TArray<string>): TArray<string>;
var
  mList: TList<string>;
  mName: string;
begin
  mList := TList<string>.Create;
  try
    for mName in [TUpdateVersions.BasePackage, TUpdateVersions.ContractsPackage] do
    begin
      if IsSelected(ASelected, mName) then
      begin
        mList.Add(mName);
      end;
    end;
    for mName in ASelected do
    begin
      if not TUpdateVersions.IsRequiredPackage(mName) and (mList.IndexOf(mName) < 0) then
      begin
        mList.Add(mName);
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TUpdateKnownPackages.Plan(const ARegistry: IUpdateRegistry; const ATarget: TUpdatePackageTarget;
  const ASelected: TArray<string>): TArray<TUpdateRegistryChange>;
var
  mList: TList<TUpdateRegistryChange>;
  mSelected: TArray<string>;
begin
  mSelected := Ordered(ASelected);
  mList := TList<TUpdateRegistryChange>.Create;
  try
    PlanKnown(mList, ARegistry, ATarget, mSelected);
    PlanDisabled(mList, ARegistry, ATarget, mSelected);
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

function ListUses(const ARegistry: IUpdateRegistry; const AKey, AFileName: string): Boolean;
var
  mValue: TUpdateRegistryValue;
begin
  for mValue in ARegistry.Values(AKey) do
  begin
    if TUpdateKnownPackages.SamePath(mValue.Name, AFileName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TUpdateKnownPackages.UsedElsewhere(const ARegistry: IUpdateRegistry; const AFileName,
  AExceptKey: string): Boolean;
var
  mProfile, mVersion, mBase: string;
  mIndex: Integer;
begin
  for mProfile in ARegistry.SubKeys(TUpdateIdes.cEmbarcaderoKey) do
  begin
    for mVersion in ARegistry.SubKeys(TUpdateIdes.cEmbarcaderoKey + '\' + mProfile) do
    begin
      mBase := TUpdateIdes.cEmbarcaderoKey + '\' + mProfile + '\' + mVersion;
      // Nur „Known Packages“ und „Known Packages x64“ laden ein Package.
      for mIndex := 0 to 1 do
      begin
        if not SamePath(mBase, AExceptKey) and ListUses(ARegistry, mBase + '\' + cPackageLists[mIndex],
          AFileName) then
        begin
          Exit(True);
        end;
      end;
    end;
  end;
  Result := False;
end;

class procedure TUpdateKnownPackages.Apply(const ARegistry: IUpdateRegistry;
  const AChanges: TArray<TUpdateRegistryChange>);
var
  mChange: TUpdateRegistryChange;
begin
  for mChange in AChanges do
  begin
    if mChange.Kind = TUpdateRegistryChangeKind.Add then
    begin
      ARegistry.WriteValue(mChange.Key, mChange.Name, mChange.Data);
    end
    else
    begin
      ARegistry.DeleteValue(mChange.Key, mChange.Name);
    end;
  end;
end;

class procedure TUpdateKnownPackages.Revert(const ARegistry: IUpdateRegistry;
  const AChanges: TArray<TUpdateRegistryChange>);
var
  mIndex: Integer;
begin
  for mIndex := High(AChanges) downto 0 do
  begin
    if AChanges[mIndex].Kind = TUpdateRegistryChangeKind.Add then
    begin
      ARegistry.DeleteValue(AChanges[mIndex].Key, AChanges[mIndex].Name);
    end
    else
    begin
      ARegistry.WriteValue(AChanges[mIndex].Key, AChanges[mIndex].Name, AChanges[mIndex].Data);
    end;
  end;
end;

end.
