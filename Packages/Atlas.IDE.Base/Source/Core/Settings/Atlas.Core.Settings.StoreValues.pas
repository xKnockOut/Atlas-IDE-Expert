unit Atlas.Core.Settings.StoreValues;

// Werte der Plugin-Einstellungen nach Schlüssel (#1455): IAtlasSettingsValues
// über einen Speicher mit den Werten von TAtlasPluginSettings. Die Optionsseite
// gibt damit den Abschnitten der Module (IAtlasSettingsSection) die Werte, die
// noch im zentralen Record stehen: Schlüssel (x-key) und Art kommen aus dem
// Katalog, der Wert steht unter dem Registry-Namen im Speicher. Wahrheitswerte
// stehen dort als Zahl 0/1 (wie TAtlasPluginSettings.Save), Listen und
// Objekte (issues.connections …) als JSON-Text: ReadString und WriteString
// gelten für Text und JSON.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.History;

type
  TAtlasSettingsStoreValues = class(TInterfacedObject, IAtlasSettingsValues)
  private
    FCatalog: TAtlasSettingsCatalog;
    FStore: IAtlasMemorySettingsStore;
    FDefaults: IAtlasMemorySettingsStore;
    /// <summary>Registry-Name zu AKey in der Art AKind; sonst EAtlasSettingsKey.</summary>
    function NameOf(const AKey: string; AKind: TAtlasSettingKind): string;
    /// <summary>Wie NameOf für Text: Text oder JSON (als Text gespeichert).</summary>
    function TextNameOf(const AKey: string): string;
  public
    /// <summary>ACatalog gehört weiter dem Aufrufer und muss länger leben. ADefaults: Speicher mit den Vorgaben
    /// (Reset).</summary>
    constructor Create(ACatalog: TAtlasSettingsCatalog; const AStore, ADefaults: IAtlasMemorySettingsStore);
    function Contains(const AKey: string): Boolean;
    function ReadBoolean(const AKey: string): Boolean;
    function ReadInteger(const AKey: string): Integer;
    function ReadString(const AKey: string): string;
    procedure WriteBoolean(const AKey: string; AValue: Boolean);
    procedure WriteInteger(const AKey: string; AValue: Integer);
    procedure WriteString(const AKey, AValue: string);
    procedure Reset(const AKey: string);
    function StoredKeys: TArray<string>;
    /// <summary>Registry-Name zu AKey (Plugin-Einstellung); '' ohne.</summary>
    class function PluginName(ACatalog: TAtlasSettingsCatalog; const AKey: string): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Core.Settings.Plugin;

constructor TAtlasSettingsStoreValues.Create(ACatalog: TAtlasSettingsCatalog;
  const AStore, ADefaults: IAtlasMemorySettingsStore);
begin
  inherited Create;
  FCatalog := ACatalog;
  FStore := AStore;
  FDefaults := ADefaults;
end;

class function TAtlasSettingsStoreValues.PluginName(ACatalog: TAtlasSettingsCatalog; const AKey: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := ACatalog.IndexOfKey(AKey);
  if (mIndex >= 0) and (ACatalog[mIndex].Source = asPlugin) then
    Result := ACatalog[mIndex].Name;
end;

function TAtlasSettingsStoreValues.NameOf(const AKey: string; AKind: TAtlasSettingKind): string;
var
  mIndex: Integer;
begin
  mIndex := FCatalog.IndexOfKey(AKey);
  if (mIndex < 0) or (FCatalog[mIndex].Source <> asPlugin) then
    raise EAtlasSettingsKey.CreateFmt('Einstellung %s ist keine Plugin-Einstellung', [AKey]);
  if FCatalog[mIndex].Kind <> AKind then
    raise EAtlasSettingsKey.CreateFmt('Einstellung %s hat eine andere Art', [AKey]);
  Result := FCatalog[mIndex].Name;
end;

function TAtlasSettingsStoreValues.TextNameOf(const AKey: string): string;
var
  mIndex: Integer;
begin
  mIndex := FCatalog.IndexOfKey(AKey);
  if (mIndex >= 0) and (FCatalog[mIndex].Kind = akJson) then
    Exit(NameOf(AKey, akJson));
  Result := NameOf(AKey, akString);
end;

function TAtlasSettingsStoreValues.Contains(const AKey: string): Boolean;
var
  mName: string;
begin
  mName := PluginName(FCatalog, AKey);
  Result := (mName <> '') and (FStore as IAtlasSettingsNames).Contains(mName);
end;

function TAtlasSettingsStoreValues.ReadBoolean(const AKey: string): Boolean;
var
  mName: string;
begin
  mName := NameOf(AKey, akBoolean);
  Result := FStore.ReadInteger(mName, FDefaults.ReadInteger(mName, 0)) <> 0;
end;

function TAtlasSettingsStoreValues.ReadInteger(const AKey: string): Integer;
var
  mName: string;
begin
  mName := NameOf(AKey, akInteger);
  Result := FStore.ReadInteger(mName, FDefaults.ReadInteger(mName, 0));
end;

function TAtlasSettingsStoreValues.ReadString(const AKey: string): string;
var
  mName: string;
begin
  mName := TextNameOf(AKey);
  Result := FStore.ReadString(mName, FDefaults.ReadString(mName, ''));
end;

procedure TAtlasSettingsStoreValues.WriteBoolean(const AKey: string; AValue: Boolean);
begin
  if AValue then
    FStore.WriteInteger(NameOf(AKey, akBoolean), 1)
  else
    FStore.WriteInteger(NameOf(AKey, akBoolean), 0);
end;

procedure TAtlasSettingsStoreValues.WriteInteger(const AKey: string; AValue: Integer);
begin
  FStore.WriteInteger(NameOf(AKey, akInteger), AValue);
end;

procedure TAtlasSettingsStoreValues.WriteString(const AKey, AValue: string);
begin
  FStore.WriteString(TextNameOf(AKey), AValue);
end;

procedure TAtlasSettingsStoreValues.Reset(const AKey: string);
var
  mName: string;
begin
  mName := PluginName(FCatalog, AKey);
  if mName = '' then
    raise EAtlasSettingsKey.CreateFmt('Einstellung %s ist keine Plugin-Einstellung', [AKey]);
  if FDefaults.HasInteger(mName) then
    FStore.WriteInteger(mName, FDefaults.ReadInteger(mName, 0))
  else
    FStore.WriteString(mName, FDefaults.ReadString(mName, ''));
end;

function TAtlasSettingsStoreValues.StoredKeys: TArray<string>;
var
  mName: string;
  mIndex: Integer;
  mKeys: TList<string>;
begin
  mKeys := TList<string>.Create;
  try
    for mName in FStore.Names do
    begin
      mIndex := FCatalog.IndexOfName(mName);
      if mIndex >= 0 then
        mKeys.Add(FCatalog[mIndex].Key);
    end;
    mKeys.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareStr(ALeft, ARight);
      end));
    Result := mKeys.ToArray;
  finally
    mKeys.Free;
  end;
end;

end.
