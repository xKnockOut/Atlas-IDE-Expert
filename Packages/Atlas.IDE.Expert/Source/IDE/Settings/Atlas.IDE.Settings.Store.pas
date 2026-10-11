unit Atlas.IDE.Settings.Store;

// Einstellungen des Plugins in der Registry (HKCU\Software\Atlas\IdePlugin,
// #227) und der aktuelle Stand für alle Teile des Plugins. Gelesen wird
// einmal beim ersten Zugriff, geschrieben über Update (Optionsseite, gezogene
// Breiten, eingeklapptes Panel).

interface

uses
  Atlas.Core.Settings.Plugin;

type
  TAtlasIdeSettings = class
  private class var
    FCurrent: TAtlasPluginSettings;
    FLoaded: Boolean;
  public
    class function Current: TAtlasPluginSettings; static;
    /// <summary>Übernimmt und speichert ASettings.</summary>
    class procedure Update(const ASettings: TAtlasPluginSettings); static;
    /// <summary>Für Diagnose und Tests: beim nächsten Zugriff neu lesen.</summary>
    class procedure Reload; static;
  end;

const
  AtlasRegistryKey = 'Software\Atlas\IdePlugin';

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Win.Registry;

type
  TRegistryStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FRegistry: TRegistry;
    FWritable: Boolean;
  public
    constructor Create(AWrite: Boolean);
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

{ TRegistryStore }

constructor TRegistryStore.Create(AWrite: Boolean);
begin
  inherited Create;
  if AWrite then
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE)
  else
    FRegistry := TRegistry.Create(KEY_READ);
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if AWrite then
    FWritable := FRegistry.OpenKey(AtlasRegistryKey, True)
  else
    FRegistry.OpenKeyReadOnly(AtlasRegistryKey);
end;

destructor TRegistryStore.Destroy;
begin
  FRegistry.Free;
  inherited Destroy;
end;

function TRegistryStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) = rdInteger) then
      Result := FRegistry.ReadInteger(AName);
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FWritable then
    Exit;
  try
    FRegistry.WriteInteger(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TRegistryStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) in [rdString, rdExpandString]) then
      Result := FRegistry.ReadString(AName);
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TRegistryStore.WriteString(const AName, AValue: string);
begin
  if not FWritable then
    Exit;
  try
    FRegistry.WriteString(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

{ TAtlasIdeSettings }

class function TAtlasIdeSettings.Current: TAtlasPluginSettings;
var
  Store: IAtlasSettingsStore;
begin
  if not FLoaded then
  begin
    FCurrent := TAtlasPluginSettings.Defaults;
    Store := TRegistryStore.Create(False);
    FCurrent.Load(Store);
    FLoaded := True;
  end;
  Result := FCurrent;
end;

class procedure TAtlasIdeSettings.Update(const ASettings: TAtlasPluginSettings);
var
  Store: IAtlasSettingsStore;
begin
  FCurrent := ASettings;
  FCurrent.Normalize;
  FLoaded := True;
  Store := TRegistryStore.Create(True);
  FCurrent.Save(Store);
end;

class procedure TAtlasIdeSettings.Reload;
begin
  FLoaded := False;
end;

end.
