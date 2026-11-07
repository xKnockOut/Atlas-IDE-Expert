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
    cMaxKeep = 50;
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
  begin
    FNames.Add(AName);
  end;
end;

function TAtlasMemorySettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
begin
  if not FIntegers.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TAtlasMemorySettingsStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FIntegers.AddOrSetValue(LowerCase(AName), AValue);
  Remember(AName);
end;

function TAtlasMemorySettingsStore.ReadString(const AName, ADefault: string): string;
begin
  if not FStrings.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := ADefault;
  end;
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
  mValue: Integer;
begin
  if FIntegers.TryGetValue(LowerCase(AName), mValue) then
  begin
    Result := IntToStr(mValue);
  end
  else if not FStrings.TryGetValue(LowerCase(AName), Result) then
  begin
    Result := '';
  end;
end;

function TAtlasMemorySettingsStore.ToJson: TJSONObject;
var
  mName: string;
  mValue: Integer;
begin
  Result := TJSONObject.Create;
  for mName in FNames do
  begin
    if FIntegers.TryGetValue(LowerCase(mName), mValue) then
    begin
      Result.AddPair(mName, TJSONNumber.Create(mValue));
    end
    else
    begin
      Result.AddPair(mName, TJSONString.Create(ReadString(mName, '')));
    end;
  end;
end;

procedure TAtlasMemorySettingsStore.FromJson(AValues: TJSONObject);
var
  mPair: TJSONPair;
begin
  if AValues = nil then
  begin
    Exit;
  end;
  for mPair in AValues do
  begin
    if mPair.JsonValue is TJSONNumber then
    begin
      WriteInteger(mPair.JsonString.Value, TJSONNumber(mPair.JsonValue).AsInt);
    end
    else if mPair.JsonValue is TJSONString then
    begin
      WriteString(mPair.JsonString.Value, TJSONString(mPair.JsonValue).Value);
    end;
  end;
end;

function TAtlasMemorySettingsStore.Contains(const AName: string): Boolean;
begin
  Result := FIntegers.ContainsKey(LowerCase(AName)) or FStrings.ContainsKey(LowerCase(AName));
end;

procedure TAtlasMemorySettingsStore.Remove(const AName: string);
var
  mIndex: Integer;
begin
  FIntegers.Remove(LowerCase(AName));
  FStrings.Remove(LowerCase(AName));
  for mIndex := FNames.Count - 1 downto 0 do
  begin
    if SameText(FNames[mIndex], AName) then
    begin
      FNames.Delete(mIndex);
    end;
  end;
end;

class function TAtlasMemorySettingsStore.FromSettings(
  const ASettings: TAtlasPluginSettings): IAtlasMemorySettingsStore;
var
  mCopy_: TAtlasPluginSettings;
begin
  Result := TAtlasMemorySettingsStore.Create;
  mCopy_ := ASettings;
  mCopy_.Save(Result);
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
  mLeft, mRight: IAtlasMemorySettingsStore;
  mName: string;
begin
  mLeft := TAtlasMemorySettingsStore.FromSettings(ALeft);
  mRight := TAtlasMemorySettingsStore.FromSettings(ARight);
  Result := nil;
  for mName in mLeft.Names do
  begin
    if mLeft.Text(mName) <> mRight.Text(mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

procedure TAtlasSettingsHistory.Push(const ABefore, AAfter: TAtlasPluginSettings; AChangedAt: TDateTime;
  AKeep: Integer);
var
  mSnapshot: TAtlasSettingsSnapshot;
begin
  if Length(Differences(ABefore, AAfter)) = 0 then
  begin
    Exit;
  end;
  mSnapshot.ChangedAt := AChangedAt;
  mSnapshot.Settings := ABefore;
  FSnapshots.Insert(0, mSnapshot);
  if AKeep < 0 then
  begin
    AKeep := 0;
  end;
  if AKeep > cMaxKeep then
  begin
    AKeep := cMaxKeep;
  end;
  while FSnapshots.Count > AKeep do
  begin
    FSnapshots.Delete(FSnapshots.Count - 1);
  end;
end;

function TAtlasSettingsHistory.ChangedKeys(AIndex: Integer; const ACurrent: TAtlasPluginSettings): TArray<string>;
begin
  Result := Differences(FSnapshots[AIndex].Settings, ACurrent);
end;

function TAtlasSettingsHistory.LastChangedKeys(const ACurrent: TAtlasPluginSettings): TArray<string>;
begin
  Result := nil;
  if FSnapshots.Count > 0 then
  begin
    Result := ChangedKeys(0, ACurrent);
  end;
end;

procedure TAtlasSettingsHistory.Clear;
begin
  FSnapshots.Clear;
end;

function TAtlasSettingsHistory.ToJson: string;
var
  mRoot: TJSONArray;
  mItem: TJSONObject;
  mSnapshot: TAtlasSettingsSnapshot;
  mStore: IAtlasMemorySettingsStore;
begin
  mRoot := TJSONArray.Create;
  try
    for mSnapshot in FSnapshots do
    begin
      mStore := TAtlasMemorySettingsStore.FromSettings(mSnapshot.Settings);
      mItem := TJSONObject.Create;
      mItem.AddPair('changedAt', TJSONString.Create(DateToISO8601(mSnapshot.ChangedAt, True)));
      mItem.AddPair('settings', mStore.ToJson);
      mRoot.AddElement(mItem);
    end;
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TAtlasSettingsHistory.LoadJson(const AText: string): Boolean;
var
  mRoot, mValues: TJSONValue;
  mElement: TJSONValue;
  mSnapshot: TAtlasSettingsSnapshot;
  mStore: IAtlasMemorySettingsStore;
  mStamp: string;
  mCatalog: TAtlasSettingsCatalog;
begin
  FSnapshots.Clear;
  mCatalog := nil;
  mRoot := TJSONObject.ParseJSONValue(AText);
  try
    Result := mRoot is TJSONArray;
    if not Result then
    begin
      Exit;
    end;
    for mElement in TJSONArray(mRoot) do
    begin
      if not (mElement is TJSONObject) then
      begin
        Continue;
      end;
      mValues := TJSONObject(mElement).GetValue('settings');
      mStamp := TJSONObject(mElement).GetValue<string>('changedAt', '');
      if not (mValues is TJSONObject) or (mStamp = '') then
      begin
        Continue;
      end;
      mStore := TAtlasMemorySettingsStore.Create;
      mStore.FromJson(TJSONObject(mValues));
      // Stände von vor einer Umbenennung (#1280): frühere Namen wie beim Start übernehmen.
      if mCatalog = nil then
      begin
        mCatalog := TAtlasSettingsCatalog.CreateDefault;
      end;
      TAtlasSettingsRenames.Apply(mStore, mStore as IAtlasSettingsNames, mCatalog);
      // Einzelne Abfrage von vor #1262: als „Standard“ in die Liste der Abfragen.
      TAtlasSettingsQueryMigrations.Migrate(mStore, mStore as IAtlasSettingsNames, mStore);
      TAtlasSettingsQueryMigrations.RemoveLegacy(mStore as IAtlasSettingsNames);
      mSnapshot.Settings := TAtlasPluginSettings.Defaults;
      mSnapshot.Settings.Load(mStore);
      try
        mSnapshot.ChangedAt := ISO8601ToDate(mStamp, True);
      except
        on EConvertError do
          Continue;
      end;
      FSnapshots.Add(mSnapshot);
    end;
  finally
    mCatalog.Free;
    mRoot.Free;
  end;
end;

end.
