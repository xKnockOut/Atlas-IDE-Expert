unit Atlas.Core.Settings.History;

// Gemerkte Stände der Plugin-Einstellungen (#722): Vor jeder gespeicherten
// Änderung kommt der alte Stand in die Liste (neuester zuerst, höchstens
// safeMode.keepSettingsHistory Einträge). Im abgesicherten Start lässt sich
// so „Einstellungen auf den Stand vor … zurücksetzen“ anbieten, und die
// zuletzt geänderten Einstellungen sind bekannt (Vorschlag, womit man beim
// Wiedereinschalten anfängt). Ohne VCL und ohne Registry; die IDE-Schicht
// legt die Liste als JSON unter %APPDATA%\Atlas ab.
// TAtlasMemorySettingsStore hält Einstellungen im Arbeitsspeicher, mit den
// Namen, die TAtlasPluginSettings.Save schreibt.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin;

type
  /// <summary>Einstellungen im Arbeitsspeicher; Namen ohne Groß-/Kleinschreibung wie in der Registry.</summary>
  IAtlasMemorySettingsStore = interface(IAtlasSettingsStore)
    ['{8E1F4C62-3A7D-4B95-9C20-5D6E7F8A1B34}']
    function HasInteger(const AName: string): Boolean;
    /// <summary>Alle Namen in der Reihenfolge des ersten Schreibens.</summary>
    function Names: TArray<string>;
    /// <summary>Wert als Text (Zahl bzw. String) für Vergleiche; '' ohne.</summary>
    function Text(const AName: string): string;
    /// <summary>{"Name": Zahl | "Text", …}; der Aufrufer gibt es frei.</summary>
    function ToJson: TJSONObject;
    /// <summary>Werte aus ToJson; Unbekanntes wird übersprungen.</summary>
    procedure FromJson(AValues: TJSONObject);
  end;

  TAtlasMemorySettingsStore = class(TInterfacedObject, IAtlasSettingsStore, IAtlasMemorySettingsStore,
    IAtlasSettingsNames)
  private
    FIntegers: TDictionary<string, Integer>;
    FStrings: TDictionary<string, string>;
    FNames: TList<string>;
    procedure Remember(const AName: string);
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    function HasInteger(const AName: string): Boolean;
    function Names: TArray<string>;
    function Text(const AName: string): string;
    function ToJson: TJSONObject;
    procedure FromJson(AValues: TJSONObject);
    function Contains(const AName: string): Boolean;
    procedure Remove(const AName: string);
    /// <summary>Speicher mit den Werten von ASettings.</summary>
    class function FromSettings(const ASettings: TAtlasPluginSettings): IAtlasMemorySettingsStore; static;
  end;

  TAtlasSettingsSnapshot = record
    /// <summary>Zeitpunkt der Änderung, die diesen Stand abgelöst hat (UTC).</summary>
    ChangedAt: TDateTime;
    Settings: TAtlasPluginSettings;
  end;

  TAtlasSettingsHistory = class
  public const
    MaxKeep = 50;
  private
    FSnapshots: TList<TAtlasSettingsSnapshot>;
    function GetCount: Integer;
    function GetSnapshot(AIndex: Integer): TAtlasSettingsSnapshot;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>ABefore merken, bevor AAfter gespeichert wird; nichts, wenn sich nichts ändert oder AKeep 0
    /// ist. Danach höchstens AKeep Stände.</summary>
    procedure Push(const ABefore, AAfter: TAtlasPluginSettings; AChangedAt: TDateTime; AKeep: Integer);
    /// <summary>Namen der Einstellungen, die sich zwischen Stand AIndex und ACurrent unterscheiden.</summary>
    function ChangedKeys(AIndex: Integer; const ACurrent: TAtlasPluginSettings): TArray<string>;
    /// <summary>Namen, die die letzte Änderung (Stand 0 gegen ACurrent) betraf; leer ohne Stand.</summary>
    function LastChangedKeys(const ACurrent: TAtlasPluginSettings): TArray<string>;
    procedure Clear;
    function ToJson: string;
    /// <summary>Liste aus ToJson; ungültige Einträge fallen weg. False (und leer), wenn AText keine Liste ist.
    /// </summary>
    function LoadJson(const AText: string): Boolean;
    property Count: Integer read GetCount;
    /// <summary>0 = neuester Stand.</summary>
    property Snapshots[AIndex: Integer]: TAtlasSettingsSnapshot read GetSnapshot; default;
    /// <summary>Unterschiedliche Namen zwischen zwei Ständen.</summary>
    class function Differences(const ALeft, ARight: TAtlasPluginSettings): TArray<string>; static;
  end;

implementation

uses
  System.DateUtils,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Settings.Renames,
  Atlas.Core.Settings.QueryMigration;

{ TAtlasMemorySettingsStore }

constructor TAtlasMemorySettingsStore.Create;
begin
  inherited Create;
  FIntegers := TDictionary<string, Integer>.Create;
  FStrings := TDictionary<string, string>.Create;
  FNames := TList<string>.Create;
end;

destructor TAtlasMemorySettingsStore.Destroy;
begin
  FNames.Free;
  FStrings.Free;
  FIntegers.Free;
  inherited;
end;

procedure TAtlasMemorySettingsStore.Remember(const AName: string);
begin
  if FNames.IndexOf(AName) < 0 then
    FNames.Add(AName);
end;

function TAtlasMemorySettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FIntegers.TryGetValue(LowerCase(AName), Result) then
    Result := ADefault;
end;

procedure TAtlasMemorySettingsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FIntegers.AddOrSetValue(LowerCase(AName), AValue);
  Remember(AName);
end;

function TAtlasMemorySettingsStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(LowerCase(AName), Result) then
    Result := ADefault;
end;

procedure TAtlasMemorySettingsStore.WriteString(const AName, AValue: string);
begin
  FStrings.AddOrSetValue(LowerCase(AName), AValue);
  Remember(AName);
end;

function TAtlasMemorySettingsStore.HasInteger(const AName: string): Boolean;
begin
  Result := FIntegers.ContainsKey(LowerCase(AName));
end;

function TAtlasMemorySettingsStore.Names: TArray<string>;
begin
  Result := FNames.ToArray;
end;

function TAtlasMemorySettingsStore.Text(const AName: string): string;
var
  Value: Integer;
begin
  if FIntegers.TryGetValue(LowerCase(AName), Value) then
    Result := IntToStr(Value)
  else if not FStrings.TryGetValue(LowerCase(AName), Result) then
    Result := '';
end;

function TAtlasMemorySettingsStore.ToJson: TJSONObject;
var
  Name: string;
  Value: Integer;
begin
  Result := TJSONObject.Create;
  for Name in FNames do
    if FIntegers.TryGetValue(LowerCase(Name), Value) then
      Result.AddPair(Name, TJSONNumber.Create(Value))
    else
      Result.AddPair(Name, TJSONString.Create(ReadString(Name, '')));
end;

procedure TAtlasMemorySettingsStore.FromJson(AValues: TJSONObject);
var
  Pair: TJSONPair;
begin
  if AValues = nil then
    Exit;
  for Pair in AValues do
    if Pair.JsonValue is TJSONNumber then
      WriteInteger(Pair.JsonString.Value, TJSONNumber(Pair.JsonValue).AsInt)
    else if Pair.JsonValue is TJSONString then
      WriteString(Pair.JsonString.Value, TJSONString(Pair.JsonValue).Value);
end;

function TAtlasMemorySettingsStore.Contains(const AName: string): Boolean;
begin
  Result := FIntegers.ContainsKey(LowerCase(AName)) or FStrings.ContainsKey(LowerCase(AName));
end;

procedure TAtlasMemorySettingsStore.Remove(const AName: string);
var
  Index: Integer;
begin
  FIntegers.Remove(LowerCase(AName));
  FStrings.Remove(LowerCase(AName));
  for Index := FNames.Count - 1 downto 0 do
    if SameText(FNames[Index], AName) then
      FNames.Delete(Index);
end;

class function TAtlasMemorySettingsStore.FromSettings(
  const ASettings: TAtlasPluginSettings): IAtlasMemorySettingsStore;
var
  Copy_: TAtlasPluginSettings;
begin
  Result := TAtlasMemorySettingsStore.Create;
  Copy_ := ASettings;
  Copy_.Save(Result);
end;

{ TAtlasSettingsHistory }

constructor TAtlasSettingsHistory.Create;
begin
  inherited Create;
  FSnapshots := TList<TAtlasSettingsSnapshot>.Create;
end;

destructor TAtlasSettingsHistory.Destroy;
begin
  FSnapshots.Free;
  inherited;
end;

function TAtlasSettingsHistory.GetCount: Integer;
begin
  Result := FSnapshots.Count;
end;

function TAtlasSettingsHistory.GetSnapshot(AIndex: Integer): TAtlasSettingsSnapshot;
begin
  Result := FSnapshots[AIndex];
end;

class function TAtlasSettingsHistory.Differences(const ALeft, ARight: TAtlasPluginSettings): TArray<string>;
var
  Left, Right: IAtlasMemorySettingsStore;
  Name: string;
begin
  Left := TAtlasMemorySettingsStore.FromSettings(ALeft);
  Right := TAtlasMemorySettingsStore.FromSettings(ARight);
  Result := nil;
  for Name in Left.Names do
    if Left.Text(Name) <> Right.Text(Name) then
      Result := Result + [Name];
end;

procedure TAtlasSettingsHistory.Push(const ABefore, AAfter: TAtlasPluginSettings; AChangedAt: TDateTime;
  AKeep: Integer);
var
  Snapshot: TAtlasSettingsSnapshot;
begin
  if Length(Differences(ABefore, AAfter)) = 0 then
    Exit;
  Snapshot.ChangedAt := AChangedAt;
  Snapshot.Settings := ABefore;
  FSnapshots.Insert(0, Snapshot);
  if AKeep < 0 then
    AKeep := 0;
  if AKeep > MaxKeep then
    AKeep := MaxKeep;
  while FSnapshots.Count > AKeep do
    FSnapshots.Delete(FSnapshots.Count - 1);
end;

function TAtlasSettingsHistory.ChangedKeys(AIndex: Integer; const ACurrent: TAtlasPluginSettings): TArray<string>;
begin
  Result := Differences(FSnapshots[AIndex].Settings, ACurrent);
end;

function TAtlasSettingsHistory.LastChangedKeys(const ACurrent: TAtlasPluginSettings): TArray<string>;
begin
  Result := nil;
  if FSnapshots.Count > 0 then
    Result := ChangedKeys(0, ACurrent);
end;

procedure TAtlasSettingsHistory.Clear;
begin
  FSnapshots.Clear;
end;

function TAtlasSettingsHistory.ToJson: string;
var
  Root: TJSONArray;
  Item: TJSONObject;
  Snapshot: TAtlasSettingsSnapshot;
  Store: IAtlasMemorySettingsStore;
begin
  Root := TJSONArray.Create;
  try
    for Snapshot in FSnapshots do
    begin
      Store := TAtlasMemorySettingsStore.FromSettings(Snapshot.Settings);
      Item := TJSONObject.Create;
      Item.AddPair('changedAt', TJSONString.Create(DateToISO8601(Snapshot.ChangedAt, True)));
      Item.AddPair('settings', Store.ToJson);
      Root.AddElement(Item);
    end;
    Result := Root.ToJSON;
  finally
    Root.Free;
  end;
end;

function TAtlasSettingsHistory.LoadJson(const AText: string): Boolean;
var
  Root, Values: TJSONValue;
  Element: TJSONValue;
  Snapshot: TAtlasSettingsSnapshot;
  Store: IAtlasMemorySettingsStore;
  Stamp: string;
  Catalog: TAtlasSettingsCatalog;
begin
  FSnapshots.Clear;
  Catalog := nil;
  Root := TJSONObject.ParseJSONValue(AText);
  try
    Result := Root is TJSONArray;
    if not Result then
      Exit;
    for Element in TJSONArray(Root) do
    begin
      if not (Element is TJSONObject) then
        Continue;
      Values := TJSONObject(Element).GetValue('settings');
      Stamp := TJSONObject(Element).GetValue<string>('changedAt', '');
      if not (Values is TJSONObject) or (Stamp = '') then
        Continue;
      Store := TAtlasMemorySettingsStore.Create;
      Store.FromJson(TJSONObject(Values));
      // Stände von vor einer Umbenennung (#1280): frühere Namen wie beim Start übernehmen.
      if Catalog = nil then
        Catalog := TAtlasSettingsCatalog.CreateDefault;
      TAtlasSettingsRenames.Apply(Store, Store as IAtlasSettingsNames, Catalog);
      // Einzelne Abfrage von vor #1262: als „Standard“ in die Liste der Abfragen.
      TAtlasSettingsQueryMigrations.Migrate(Store, Store as IAtlasSettingsNames, Store);
      TAtlasSettingsQueryMigrations.RemoveLegacy(Store as IAtlasSettingsNames);
      Snapshot.Settings := TAtlasPluginSettings.Defaults;
      Snapshot.Settings.Load(Store);
      try
        Snapshot.ChangedAt := ISO8601ToDate(Stamp, True);
      except
        on EConvertError do
          Continue;
      end;
      FSnapshots.Add(Snapshot);
    end;
  finally
    Catalog.Free;
    Root.Free;
  end;
end;

end.
