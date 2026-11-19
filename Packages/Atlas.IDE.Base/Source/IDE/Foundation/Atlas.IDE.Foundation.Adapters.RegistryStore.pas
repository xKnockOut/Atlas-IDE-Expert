unit Atlas.IDE.Foundation.Adapters.RegistryStore;

// Ablage der Plugin-Einstellungen in der Registry (HKCU\Software\Atlas\IdePlugin, #227) für
// TAtlasIdeSettings. Erzeugt nur die Kompositionswurzel (TAtlasIdeSettings.StoreFactory); was gelesen und
// geschrieben wird, entscheidet Atlas.IDE.Foundation.Settings. Ohne Schreibrecht bleiben Werte nur für diese
// Sitzung bestehen.

interface

uses
  System.Win.Registry,
  Atlas.Core.Settings.Plugin;

type
  TAtlasRegistrySettingsStore = class(TInterfacedObject, IAtlasSettingsStore, IAtlasSettingsNames)
  private
    FRegistry: TRegistry;
    FWritable: Boolean;
  public
    /// <summary>AWrite: Schlüssel zum Schreiben öffnen (und anlegen), sonst nur lesen.</summary>
    constructor Create(AWrite: Boolean);
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    function Contains(const AName: string): Boolean;
    procedure Remove(const AName: string);
  end;

implementation

uses
  Winapi.Windows,
  Atlas.IDE.Foundation.Settings;

{ TAtlasRegistrySettingsStore }

constructor TAtlasRegistrySettingsStore.Create(AWrite: Boolean);
begin
  inherited Create;
  if AWrite then
  begin
    FRegistry := TRegistry.Create(KEY_READ or KEY_WRITE);
  end
  else
  begin
    FRegistry := TRegistry.Create(KEY_READ);
  end;
  FRegistry.RootKey := HKEY_CURRENT_USER;
  if AWrite then
  begin
    FWritable := FRegistry.OpenKey(cAtlasRegistryKey, True);
  end
  else
  begin
    FRegistry.OpenKeyReadOnly(cAtlasRegistryKey);
  end;
end;

destructor TAtlasRegistrySettingsStore.Destroy;
begin
  FRegistry.Free;
  inherited Destroy;
end;

function TAtlasRegistrySettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) = rdInteger) then
    begin
      Result := FRegistry.ReadInteger(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TAtlasRegistrySettingsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteInteger(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TAtlasRegistrySettingsStore.ReadString(const AName, ADefault: string): string;
begin
  Result := ADefault;
  try
    if (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName) and
      (FRegistry.GetDataType(AName) in [rdString, rdExpandString]) then
    begin
      Result := FRegistry.ReadString(AName);
    end;
  except
    on ERegistryException do
      Result := ADefault;
  end;
end;

procedure TAtlasRegistrySettingsStore.WriteString(const AName, AValue: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    FRegistry.WriteString(AName, AValue);
  except
    // Ohne Schreibrecht bleiben die Werte für diese Sitzung bestehen.
    on ERegistryException do
      ;
  end;
end;

function TAtlasRegistrySettingsStore.Contains(const AName: string): Boolean;
begin
  try
    Result := (FRegistry.CurrentKey <> 0) and FRegistry.ValueExists(AName);
  except
    on ERegistryException do
      Result := False;
  end;
end;

procedure TAtlasRegistrySettingsStore.Remove(const AName: string);
begin
  if not FWritable then
  begin
    Exit;
  end;
  try
    if FRegistry.ValueExists(AName) then
    begin
      FRegistry.DeleteValue(AName);
    end;
  except
    // Ohne Schreibrecht bleibt der alte Wert; die Übernahme versucht es beim nächsten Start erneut.
    on ERegistryException do
      ;
  end;
end;

end.
