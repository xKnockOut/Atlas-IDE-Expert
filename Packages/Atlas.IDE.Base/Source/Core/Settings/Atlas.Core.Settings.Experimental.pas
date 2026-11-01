unit Atlas.Core.Settings.Experimental;

// Experimentelle Funktionen (#834), ohne VCL und ohne Open Tools API. Eine
// Einstellung mit "x-experimental": true (Plugin-Katalog oder atlas.schema.json)
// ist eine experimentelle Funktion: Vorgabe aus, Kennzeichen „Experimentell“ auf
// der Optionsseite und im Schnellschalter. Sie wirkt nur, wenn der Hauptschalter
// experimental.enabled an ist; sonst gilt ihre Vorgabe, der gespeicherte Wert
// bleibt (Optionsseite und Export sehen ihn weiter). Der Server macht dasselbe
// für seine Schlüssel beim Zusammensetzen der Ebenen
// (TConfigurationScopes.WithoutExperimental).

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog;

type
  TAtlasExperimental = class
  public const
    /// <summary>Schlüssel des Hauptschalters in settings.json und in der Exportdatei.</summary>
    MasterKey = 'experimental.enabled';
    /// <summary>Name des Hauptschalters in TAtlasPluginSettings.Load/Save.</summary>
    MasterName = 'ExperimentalEnabled';
  public
    /// <summary>Ist der Eintrag mit Schlüssel oder Plugin-Namen AKey experimentell?</summary>
    class function IsExperimental(ACatalog: TAtlasSettingsCatalog; const AKey: string): Boolean; static;
    /// <summary>Schlüssel aller experimentellen Einstellungen in Katalogreihenfolge.</summary>
    class function Keys(ACatalog: TAtlasSettingsCatalog): TArray<string>; static;
    /// <summary>Experimentelle Plugin-Einstellungen (Quelle Plugin) in Katalogreihenfolge.</summary>
    class function PluginEntries(ACatalog: TAtlasSettingsCatalog): TArray<TAtlasCatalogEntry>; static;
    /// <summary>Namen (TAtlasPluginSettings.Load/Save) der experimentellen Plugin-Einstellungen.</summary>
    class function PluginNames(ACatalog: TAtlasSettingsCatalog): TArray<string>; static;
    /// <summary>Wirksame Plugin-Werte: ohne Hauptschalter in ASettings bekommen alle experimentellen
    /// Plugin-Einstellungen ihre Vorgabe; mit Hauptschalter genau ASettings.</summary>
    class function Apply(const ASettings: TAtlasPluginSettings;
      ACatalog: TAtlasSettingsCatalog): TAtlasPluginSettings; overload; static;
    /// <summary>Wie oben mit den Einträgen aus PluginEntries (ohne Katalog, für den Hauptthread der IDE).</summary>
    class function Apply(const ASettings: TAtlasPluginSettings;
      const AEntries: TArray<TAtlasCatalogEntry>): TAtlasPluginSettings; overload; static;
    /// <summary>Experimentelle Einstellungen, die gerade wirken (Wert ungleich der Vorgabe), als Schlüssel:
    /// Plugin-Werte aus ASettings, Server-Werte aus dem Text von settings.json. Leer ohne Hauptschalter.
    /// Für Statusfeld, Fehlerbericht und Diagnoselog (nur Schlüssel, keine Werte).</summary>
    class function Active(const ASettings: TAtlasPluginSettings; const AGlobalText: string;
      ACatalog: TAtlasSettingsCatalog): TArray<string>; static;
    /// <summary>Eine Zeile für Tooltip und Bericht, z. B. "Experimentell an: a, b"; '' ohne.</summary>
    class function Summary(const AKeys: TArray<string>; AEnglish: Boolean): string; static;
  end;

implementation

uses
  System.JSON,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.JsonText;

function StoredText(const AStore: IAtlasMemorySettingsStore; const AEntry: TAtlasCatalogEntry): string;
begin
  // Wahrheitswerte stehen im Speicher als 0/1, im Katalog als false/true.
  Result := AStore.Text(AEntry.Name);
  if AEntry.Kind = akBoolean then
    if Result = '0' then
      Result := 'false'
    else if Result <> '' then
      Result := 'true';
  if AEntry.Kind = akString then
    Result := TJSONString.Create(Result).ToJSON;
end;

procedure WriteDefault(const AStore: IAtlasMemorySettingsStore; const AEntry: TAtlasCatalogEntry);
var
  Value: TJSONValue;
begin
  Value := TAtlasJsonValues.Parse(AEntry.DefaultJson);
  try
    if Value is TJSONBool then
    begin
      if TJSONBool(Value).AsBoolean then
        AStore.WriteInteger(AEntry.Name, 1)
      else
        AStore.WriteInteger(AEntry.Name, 0);
    end
    else if Value is TJSONNumber then
      AStore.WriteInteger(AEntry.Name, TJSONNumber(Value).AsInt)
    else if Value is TJSONString then
      AStore.WriteString(AEntry.Name, TJSONString(Value).Value)
    else if AEntry.Kind = akBoolean then
      AStore.WriteInteger(AEntry.Name, 0);
  finally
    Value.Free;
  end;
end;

{ TAtlasExperimental }

class function TAtlasExperimental.IsExperimental(ACatalog: TAtlasSettingsCatalog; const AKey: string): Boolean;
var
  Index: Integer;
begin
  Index := ACatalog.IndexOfKey(AKey);
  if Index < 0 then
    Index := ACatalog.IndexOfName(AKey);
  Result := (Index >= 0) and ACatalog[Index].Experimental;
end;

class function TAtlasExperimental.Keys(ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ACatalog.Count - 1 do
    if ACatalog[Index].Experimental then
      Result := Result + [ACatalog[Index].Key];
end;

class function TAtlasExperimental.PluginEntries(ACatalog: TAtlasSettingsCatalog): TArray<TAtlasCatalogEntry>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to ACatalog.Count - 1 do
    if ACatalog[Index].Experimental and (ACatalog[Index].Source = asPlugin) then
      Result := Result + [ACatalog[Index]];
end;

class function TAtlasExperimental.PluginNames(ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  Entry: TAtlasCatalogEntry;
begin
  Result := nil;
  for Entry in PluginEntries(ACatalog) do
    Result := Result + [Entry.Name];
end;

class function TAtlasExperimental.Apply(const ASettings: TAtlasPluginSettings;
  ACatalog: TAtlasSettingsCatalog): TAtlasPluginSettings;
begin
  Result := Apply(ASettings, PluginEntries(ACatalog));
end;

class function TAtlasExperimental.Apply(const ASettings: TAtlasPluginSettings;
  const AEntries: TArray<TAtlasCatalogEntry>): TAtlasPluginSettings;
var
  Store: IAtlasMemorySettingsStore;
  Entry: TAtlasCatalogEntry;
begin
  Result := ASettings;
  if ASettings.ExperimentalEnabled or (Length(AEntries) = 0) then
    Exit;
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for Entry in AEntries do
    WriteDefault(Store, Entry);
  Result.Load(Store);
end;

class function TAtlasExperimental.Active(const ASettings: TAtlasPluginSettings; const AGlobalText: string;
  ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  Store: IAtlasMemorySettingsStore;
  Root: TJSONObject;
  Index: Integer;
  Entry: TAtlasCatalogEntry;
  Value: string;
begin
  Result := nil;
  if not ASettings.ExperimentalEnabled then
    Exit;
  Store := TAtlasMemorySettingsStore.FromSettings(ASettings);
  Root := TAtlasJsonText.Parse(AGlobalText);
  try
    for Index := 0 to ACatalog.Count - 1 do
    begin
      Entry := ACatalog[Index];
      if not Entry.Experimental then
        Continue;
      if Entry.Source = asPlugin then
        Value := StoredText(Store, Entry)
      else if Root <> nil then
        Value := TAtlasJsonText.ValueAt(Root, Entry.Key)
      else
        Value := '';
      if (Value <> '') and not TAtlasJsonValues.Same(Value, Entry.DefaultJson) then
        Result := Result + [Entry.Key];
    end;
  finally
    Root.Free;
  end;
end;

class function TAtlasExperimental.Summary(const AKeys: TArray<string>; AEnglish: Boolean): string;
begin
  Result := '';
  if Length(AKeys) = 0 then
    Exit;
  if AEnglish then
    Result := 'Experimental on: ' + string.Join(', ', AKeys)
  else
    Result := 'Experimentell an: ' + string.Join(', ', AKeys);
end;

end.
