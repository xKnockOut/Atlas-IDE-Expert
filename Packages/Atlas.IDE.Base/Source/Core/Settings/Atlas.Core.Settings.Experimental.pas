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
    cMasterKey = 'experimental.enabled';
    /// <summary>Name des Hauptschalters in TAtlasPluginSettings.Load/Save.</summary>
    cMasterName = 'ExperimentalEnabled';
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
  begin
    if Result = '0' then
    begin
      Result := 'false';
    end
    else if Result <> '' then
    begin
      Result := 'true';
    end;
  end;
  if AEntry.Kind = akString then
  begin
    Result := TJSONString.Create(Result).ToJSON;
  end;
end;

procedure WriteDefault(const AStore: IAtlasMemorySettingsStore; const AEntry: TAtlasCatalogEntry);
var
  mValue: TJSONValue;
begin
  mValue := TAtlasJsonValues.Parse(AEntry.DefaultJson);
  try
    if mValue is TJSONBool then
    begin
      if TJSONBool(mValue).AsBoolean then
      begin
        AStore.WriteInteger(AEntry.Name, 1);
      end
      else
      begin
        AStore.WriteInteger(AEntry.Name, 0);
      end;
    end
    else if mValue is TJSONNumber then
    begin
      AStore.WriteInteger(AEntry.Name, TJSONNumber(mValue).AsInt);
    end
    else if mValue is TJSONString then
    begin
      AStore.WriteString(AEntry.Name, TJSONString(mValue).Value);
    end
    else if AEntry.Kind = akBoolean then
    begin
      AStore.WriteInteger(AEntry.Name, 0);
    end;
  finally
    mValue.Free;
  end;
end;

{ TAtlasExperimental }

class function TAtlasExperimental.IsExperimental(ACatalog: TAtlasSettingsCatalog; const AKey: string): Boolean;
var
  mIndex: Integer;
begin
  mIndex := ACatalog.IndexOfKey(AKey);
  if mIndex < 0 then
  begin
    mIndex := ACatalog.IndexOfName(AKey);
  end;
  Result := (mIndex >= 0) and ACatalog[mIndex].Experimental;
end;

class function TAtlasExperimental.Keys(ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    if ACatalog[mIndex].Experimental then
    begin
      Result := Result + [ACatalog[mIndex].Key];
    end;
  end;
end;

class function TAtlasExperimental.PluginEntries(ACatalog: TAtlasSettingsCatalog): TArray<TAtlasCatalogEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    if ACatalog[mIndex].Experimental and (ACatalog[mIndex].Source = asPlugin) then
    begin
      Result := Result + [ACatalog[mIndex]];
    end;
  end;
end;

class function TAtlasExperimental.PluginNames(ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  mEntry: TAtlasCatalogEntry;
begin
  Result := nil;
  for mEntry in PluginEntries(ACatalog) do
  begin
    Result := Result + [mEntry.Name];
  end;
end;

class function TAtlasExperimental.Apply(const ASettings: TAtlasPluginSettings;
  ACatalog: TAtlasSettingsCatalog): TAtlasPluginSettings;
begin
  Result := Apply(ASettings, PluginEntries(ACatalog));
end;

class function TAtlasExperimental.Apply(const ASettings: TAtlasPluginSettings;
  const AEntries: TArray<TAtlasCatalogEntry>): TAtlasPluginSettings;
var
  mStore: IAtlasMemorySettingsStore;
  mEntry: TAtlasCatalogEntry;
begin
  Result := ASettings;
  if ASettings.ExperimentalEnabled or (Length(AEntries) = 0) then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  for mEntry in AEntries do
  begin
    WriteDefault(mStore, mEntry);
  end;
  Result.Load(mStore);
end;

class function TAtlasExperimental.Active(const ASettings: TAtlasPluginSettings; const AGlobalText: string;
  ACatalog: TAtlasSettingsCatalog): TArray<string>;
var
  mStore: IAtlasMemorySettingsStore;
  mRoot: TJSONObject;
  mIndex: Integer;
  mEntry: TAtlasCatalogEntry;
  mValue: string;
begin
  Result := nil;
  if not ASettings.ExperimentalEnabled then
  begin
    Exit;
  end;
  mStore := TAtlasMemorySettingsStore.FromSettings(ASettings);
  mRoot := TAtlasJsonText.Parse(AGlobalText);
  try
    for mIndex := 0 to ACatalog.Count - 1 do
    begin
      mEntry := ACatalog[mIndex];
      if not mEntry.Experimental then
      begin
        Continue;
      end;
      if mEntry.Source = asPlugin then
      begin
        mValue := StoredText(mStore, mEntry);
      end
      else if mRoot <> nil then
      begin
        mValue := TAtlasJsonText.ValueAt(mRoot, mEntry.Key);
      end
      else
      begin
        mValue := '';
      end;
      if (mValue <> '') and not TAtlasJsonValues.Same(mValue, mEntry.DefaultJson) then
      begin
        Result := Result + [mEntry.Key];
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasExperimental.Summary(const AKeys: TArray<string>; AEnglish: Boolean): string;
begin
  Result := '';
  if Length(AKeys) = 0 then
  begin
    Exit;
  end;
  if AEnglish then
  begin
    Result := 'Experimental on: ' + string.Join(', ', AKeys);
  end
  else
  begin
    Result := 'Experimentell an: ' + string.Join(', ', AKeys);
  end;
end;

end.
