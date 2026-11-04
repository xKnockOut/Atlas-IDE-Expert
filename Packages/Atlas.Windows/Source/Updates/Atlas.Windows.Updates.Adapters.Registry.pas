unit Atlas.Windows.Updates.Adapters.Registry;

// Platform-Feature "Updates" (#1519), Adapter: IUpdateRegistry über
// TRegistry. Schreiben nur unter HKEY_CURRENT_USER; den Installationsordner
// einer Delphi-Version liest TDelphiInstallation (HKLM in beiden Ansichten).
// Werte kommen in der Reihenfolge der Registry.

interface

uses
  System.SysUtils,
  Atlas.Common.Updates.Contract;

type
  TUpdateWindowsRegistry = class(TInterfacedObject, IUpdateRegistry)
  public
    function SubKeys(const AKey: string): TArray<string>;
    function Values(const AKey: string): TArray<TUpdateRegistryValue>;
    procedure WriteValue(const AKey, AName, AData: string);
    procedure DeleteValue(const AKey, AName: string);
    function RootDir(const ABdsVersion: string): string;
  end;

implementation

uses
  Winapi.Windows,
  System.Classes,
  System.Win.Registry,
  Atlas.Windows.Projects.DelphiInstallation;

function OpenUser(AWrite: Boolean; const AKey: string): TRegistry;
var
  mOpened: Boolean;
begin
  if AWrite then
  begin
    Result := TRegistry.Create(KEY_READ or KEY_WRITE);
  end
  else
  begin
    Result := TRegistry.Create(KEY_READ);
  end;
  Result.RootKey := HKEY_CURRENT_USER;
  if AWrite then
  begin
    mOpened := Result.OpenKey(AKey, True);
  end
  else
  begin
    mOpened := Result.OpenKeyReadOnly(AKey);
  end;
  if not mOpened then
  begin
    FreeAndNil(Result);
  end;
end;

{ TUpdateWindowsRegistry }

function TUpdateWindowsRegistry.SubKeys(const AKey: string): TArray<string>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
begin
  Result := nil;
  mRegistry := OpenUser(False, AKey);
  if mRegistry = nil then
  begin
    Exit;
  end;
  mNames := TStringList.Create;
  try
    mRegistry.GetKeyNames(mNames);
    Result := mNames.ToStringArray;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

function TUpdateWindowsRegistry.Values(const AKey: string): TArray<TUpdateRegistryValue>;
var
  mRegistry: TRegistry;
  mNames: TStringList;
  mIndex: Integer;
begin
  Result := nil;
  mRegistry := OpenUser(False, AKey);
  if mRegistry = nil then
  begin
    Exit;
  end;
  mNames := TStringList.Create;
  try
    mRegistry.GetValueNames(mNames);
    SetLength(Result, mNames.Count);
    for mIndex := 0 to mNames.Count - 1 do
    begin
      Result[mIndex].Name := mNames[mIndex];
      Result[mIndex].Data := '';
      if mRegistry.GetDataType(mNames[mIndex]) in [rdString, rdExpandString] then
      begin
        Result[mIndex].Data := mRegistry.ReadString(mNames[mIndex]);
      end;
    end;
  finally
    mNames.Free;
    mRegistry.Free;
  end;
end;

procedure TUpdateWindowsRegistry.WriteValue(const AKey, AName, AData: string);
var
  mRegistry: TRegistry;
begin
  mRegistry := OpenUser(True, AKey);
  if mRegistry = nil then
  begin
    raise ERegistryException.Create(AKey);
  end;
  try
    mRegistry.WriteString(AName, AData);
  finally
    mRegistry.Free;
  end;
end;

procedure TUpdateWindowsRegistry.DeleteValue(const AKey, AName: string);
var
  mRegistry: TRegistry;
begin
  mRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  try
    mRegistry.RootKey := HKEY_CURRENT_USER;
    if mRegistry.OpenKey(AKey, False) and mRegistry.ValueExists(AName) and not mRegistry.DeleteValue(AName) then
    begin
      raise ERegistryException.Create(AKey + '\' + AName);
    end;
  finally
    mRegistry.Free;
  end;
end;

function TUpdateWindowsRegistry.RootDir(const ABdsVersion: string): string;
begin
  Result := TDelphiInstallation.RootDirOf(ABdsVersion);
end;

end.
