unit Atlas.Core.Settings.Scopes;

// Jeder Schlüssel hat genau einen Ort, wie im Server (TConfigurationScopes):
// globale Schlüssel in %APPDATA%\Atlas\settings.json, Projekt-Schlüssel in
// atlas.json (x-scope im Schema).
// Ein Teil der globalen Server-Einstellungen steht auf den Reitern der
// Optionsseite: Index, Speicher, XMLDoc, Inlay-Hints, Code-Metriken, Schnellbefehle,
// Kompilieren nach dem Speichern, die Treffersicherheit der Verwendungen, der Weg
// zwischen Symbolen und die Auswirkungsanalyse. Sie gehören zu TAtlasPluginSettings, liegen
// aber in settings.json statt in der Registry; TAtlasRoutedSettingsStore leitet
// sie dorthin um. So lesen Plugin und Server denselben Wert, und der Dialog
// „Weitere globale Einstellungen“ blendet sie aus (IdeManagedPaths).
// Werte aus der Registry (bis zu dieser Änderung lagen sie dort) übernimmt
// Migrate einmal; danach gilt nur noch settings.json.
// Listen wie issues.connections (#1260) stehen als JSON in settings.json; das
// Plugin liest und schreibt sie als JSON-Text (ReadString/WriteString). Eine
// leere Liste wird nicht eigens eingetragen.
// delphiVersion bestimmt in der IDE die laufende IDE selbst (Projektkontext,
// #396); der Dialog zeigt den Schlüssel deshalb nicht.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
  TAtlasRoutedSetting = record
    /// <summary>Name in TAtlasPluginSettings.Load/Save, z. B. "IndexUsages".</summary>
    Name: string;
    /// <summary>Pfad in settings.json, z. B. "index.usages".</summary>
    Path: string;
    /// <summary>Wahrheitswert (true/false); sonst ganze Zahl.</summary>
    Flag: Boolean;
    /// <summary>Zeichenkette (ReadString/WriteString), z. B. "XmlDocExpand".</summary>
    Text: Boolean;
    /// <summary>Liste oder Objekt als JSON-Text (ReadString/WriteString), z. B. "IssuesConnections" (#1260).
    /// </summary>
    Json: Boolean;
    /// <summary>Früherer Schlüssel: nur noch gelesen (Übernahme in den neuen), nie geschrieben oder migriert.
    /// </summary>
    Legacy: Boolean;
  end;

  TAtlasSettingsScopes = class
  public const
    DelphiVersionPath = 'delphiVersion';
  public
    /// <summary>Plugin-Einstellungen, die in settings.json liegen.</summary>
    class function Routed: TArray<TAtlasRoutedSetting>; static;
    class function TryRouted(const AName: string; out ASetting: TAtlasRoutedSetting): Boolean; static;
    /// <summary>Pfade, die in der IDE anderswo eingestellt werden (Reiter der Optionsseite) oder die die IDE
    /// selbst bestimmt (delphiVersion); der Dialog der globalen Einstellungen zeigt sie nicht.</summary>
    class function IdeManagedPaths: TArray<string>; static;
  end;

  /// <summary>Speicher für TAtlasPluginSettings: umgeleitete Namen in den Text von settings.json, alle übrigen
  /// in AInner (Registry). Text ist danach der neue Inhalt der Datei.</summary>
  TAtlasRoutedSettingsStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FInner: IAtlasSettingsStore;
    FText: string;
    function JsonValue(const APath: string): string;
    function Writable: Boolean;
    procedure WriteJson(const APath, AValue: string);
    procedure MigrateOne(const ARouted: TAtlasRoutedSetting);
  public
    constructor Create(const AInner: IAtlasSettingsStore; const AGlobalText: string);
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
    /// <summary>Werte aus AInner übernehmen, die settings.json noch nicht hat; True, wenn sich Text ändert.</summary>
    function Migrate: Boolean;
    property Text: string read FText;
  end;

implementation

uses
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Settings.JsonText;

function Setting(const AName, APath: string; AFlag: Boolean): TAtlasRoutedSetting;
begin
  Result := Default(TAtlasRoutedSetting);
  Result.Name := AName;
  Result.Path := APath;
  Result.Flag := AFlag;
end;

function TextSetting(const AName, APath: string): TAtlasRoutedSetting;
begin
  Result := Setting(AName, APath, False);
  Result.Text := True;
end;

function JsonSetting(const AName, APath: string): TAtlasRoutedSetting;
begin
  Result := Setting(AName, APath, False);
  Result.Json := True;
end;

function LegacySetting(const AName, APath: string; AFlag: Boolean): TAtlasRoutedSetting;
begin
  Result := Setting(AName, APath, AFlag);
  Result.Legacy := True;
end;

{ TAtlasSettingsScopes }

class function TAtlasSettingsScopes.Routed: TArray<TAtlasRoutedSetting>;
begin
  Result := [
    Setting('IndexProjectGroup', 'index.projectGroup', True),
    Setting('IndexSearchPaths', 'index.searchPaths', True),
    Setting('IndexLibraryPaths', 'index.libraryPaths', True),
    Setting('IndexUsages', 'index.usages', True),
    Setting('MemoryBudgetMb', 'memoryBudgetMb', False),
    TextSetting('XmlDocExpand', 'hints.xmlDocExpand'),
    // Vor #770: XmlDocFull liest TAtlasPluginSettings.Load nur noch, um XmlDocExpand zu übernehmen.
    LegacySetting('XmlDocFull', 'hints.xmlDocFull', True),
    Setting('XmlDocMaxLines', 'hints.xmlDocMaxLines', False),
    Setting('SlashCommands', 'slashCommands.enabled', True),
    // Das Plugin zeigt nur Parameternamen; die übrigen Inlay-Hints betreffen es nicht.
    Setting('InlayHints', 'inlayHints.parameterNames', True),
    Setting('CodeLensMetrics', 'codeLens.metrics', True),
    Setting('Metrics', 'metrics', True),
    Setting('ExperimentalEnabled', 'experimental.enabled', True),
    Setting('CompileOnSave', 'compiler.onSave', True),
    // Architekturübersicht (#1118): Server (Fenster, Bericht, get_architecture) und Plugin lesen denselben Wert.
    Setting('ArchitectureEnabled', 'architecture.enabled', True),
    TextSetting('ArchitectureScope', 'architecture.scope'),
    Setting('ArchitectureIncludeLibraryUnits', 'architecture.includeLibraryUnits', True),
    Setting('ArchitectureCentralUnits', 'architecture.centralUnits', False),
    // Code-Abfragen (#1351): Server (query_code, --query, Regeln query:<name>) und Plugin lesen denselben Wert.
    Setting('QueryEnabled', 'query.enabled', True),
    // Modul-Schalter Prüfregeln (#1454): Der Server prüft in der LSP-Sitzung nur damit Regeln.
    Setting('RuleChecksEnabled', 'ruleChecks.enabled', True),
    // Hotspots (#1354): Server (Bericht, get_hotspots, atlas/hotspots) und Plugin lesen dieselben Werte.
    Setting('HotspotsEnabled', 'hotspots.enabled', True),
    Setting('HotspotsMonths', 'hotspots.months', False),
    Setting('HotspotsCouplingMinCommits', 'hotspots.coupling.minCommits', False),
    // Treffersicherheit der Verwendungen (#1119).
    Setting('ReferencesInferred', 'references.inferred', True),
    Setting('ReferencesTextMatches', 'references.textMatches', True),
    // Weg zwischen Symbolen (#1117).
    Setting('SymbolPath', 'navigation.symbolPath', True),
    // Auswirkungsanalyse (#1120).
    Setting('Impact', 'navigation.impact', True),
    Setting('ImpactDepth', 'navigation.impactDepth', False),
    // Betroffene Tests (#1353): Plugin-Befehl und Server (--affected-tests, get_affected_tests) lesen denselben Wert.
    Setting('TestsAffected', 'tests.affected', True),
    Setting('TestsAffectedDepth', 'tests.affectedDepth', False),
    // Tracker-Verbindungen (#1260): persönlich, der Server prüft sie nur.
    JsonSetting('IssuesConnections', 'issues.connections'),
    // Zuordnung Delphi-Projekt → Tracker-Projekt (#1261): persönlich wie die Verbindungen.
    JsonSetting('IssuesProjects', 'issues.projects'),
    // Benannte Abfragen für „Meine Issues“ (#1262).
    JsonSetting('IssuesQueries', 'issues.queries'),
    // Versionsverwaltung (#571, #1285): Plugin und Server (--changed) verwenden dieselbe Art, dieselben Programme
    // und dasselbe Zeitlimit.
    TextSetting('VcsProvider', 'vcs.provider'),
    TextSetting('VcsGitPath', 'vcs.git.path'),
    TextSetting('VcsSvnPath', 'vcs.svn.path'),
    Setting('VcsTimeoutSeconds', 'vcs.timeoutSeconds', False),
    // #1286: Art und Hauptbranch je Projekt, gelesen auch vom Server (Prüfung der Datei).
    JsonSetting('VcsProjects', 'vcs.projects')];
end;

class function TAtlasSettingsScopes.TryRouted(const AName: string; out ASetting: TAtlasRoutedSetting): Boolean;
var
  mItem: TAtlasRoutedSetting;
begin
  for mItem in Routed do
  begin
    if SameText(mItem.Name, AName) then
    begin
      ASetting := mItem;
      Exit(True);
    end;
  end;
  ASetting := Default(TAtlasRoutedSetting);
  Result := False;
end;

class function TAtlasSettingsScopes.IdeManagedPaths: TArray<string>;
var
  mItem: TAtlasRoutedSetting;
begin
  Result := [DelphiVersionPath];
  for mItem in Routed do
  begin
    Result := Result + [mItem.Path];
  end;
end;

/// <summary>JSON-Einstellung: nur Liste oder Objekt; ein Wert der falschen Art gilt als Standard (der Server
/// meldet ihn).</summary>
function ListOrObject(const AJson, ADefault: string): string;
begin
  Result := ADefault;
  if CharInSet(AJson[1], ['[', '{']) then
  begin
    Result := AJson;
  end;
end;

/// <summary>Text eines JSON-Strings, sonst ADefault.</summary>
function StringValue(const AJson, ADefault: string): string;
var
  mValue: TJSONValue;
begin
  Result := ADefault;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if mValue is TJSONString then
    begin
      Result := TJSONString(mValue).Value;
    end;
  finally
    mValue.Free;
  end;
end;
{ TAtlasRoutedSettingsStore }

constructor TAtlasRoutedSettingsStore.Create(const AInner: IAtlasSettingsStore; const AGlobalText: string);
begin
  inherited Create;
  FInner := AInner;
  FText := AGlobalText;
end;

function TAtlasRoutedSettingsStore.JsonValue(const APath: string): string;
var
  mRoot: TJSONObject;
begin
  Result := '';
  mRoot := TAtlasJsonText.Parse(FText);
  try
    if mRoot <> nil then
    begin
      Result := TAtlasJsonText.ValueAt(mRoot, APath);
    end;
  finally
    mRoot.Free;
  end;
end;

function TAtlasRoutedSettingsStore.Writable: Boolean;
var
  mRoot: TJSONObject;
begin
  // Eine kaputte Datei wird nicht angefasst; die Werte bleiben dann für diese Sitzung.
  if Trim(FText) = '' then
  begin
    Exit(True);
  end;
  mRoot := TAtlasJsonText.Parse(FText);
  Result := mRoot <> nil;
  mRoot.Free;
end;

procedure TAtlasRoutedSettingsStore.WriteJson(const APath, AValue: string);
var
  mValue: TJSONValue;
  mJson: string;
begin
  mValue := TJSONObject.ParseJSONValue(Trim(AValue));
  try
    // Nur Liste oder Objekt; kaputter Text wird nie in die Datei geschrieben.
    if not ((mValue is TJSONArray) or (mValue is TJSONObject)) then
    begin
      Exit;
    end;
    mJson := mValue.ToJSON;
    if JsonValue(APath) = mJson then
    begin
      Exit;
    end;
    // Eine leere Liste ist der Standard und steht nur in der Datei, wenn dort schon eine Liste stand.
    if (mJson = '[]') and (JsonValue(APath) = '') then
    begin
      Exit;
    end;
    FText := TAtlasJsonText.SetValue(FText, APath, Trim(AValue));
  finally
    mValue.Free;
  end;
end;

function TAtlasRoutedSettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  mRouted: TAtlasRoutedSetting;
  mValue: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, mRouted) then
  begin
    Exit(FInner.ReadInteger(AName, ADefault));
  end;
  mValue := JsonValue(mRouted.Path);
  if mValue = 'true' then
  begin
    Result := 1;
  end
  else if mValue = 'false' then
  begin
    Result := 0;
  end
  else if mValue <> '' then
  begin
    Result := StrToIntDef(mValue, ADefault);
  end
  else
  begin
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Result := FInner.ReadInteger(AName, ADefault);
  end;
end;

procedure TAtlasRoutedSettingsStore.WriteInteger(const AName: string; AValue: Integer);
var
  mRouted: TAtlasRoutedSetting;
  mJson: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, mRouted) or not Writable then
  begin
    FInner.WriteInteger(AName, AValue);
    Exit;
  end;
  if mRouted.Legacy then
  begin
    Exit;
  end;
  if not mRouted.Flag then
  begin
    mJson := IntToStr(AValue);
  end
  else if AValue <> 0 then
  begin
    mJson := 'true';
  end
  else
  begin
    mJson := 'false';
  end;
  if JsonValue(mRouted.Path) <> mJson then
  begin
    FText := TAtlasJsonText.SetValue(FText, mRouted.Path, mJson);
  end;
end;

function TAtlasRoutedSettingsStore.ReadString(const AName, ADefault: string): string;
var
  mRouted: TAtlasRoutedSetting;
  mJson: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, mRouted) or not (mRouted.Text or mRouted.Json) then
  begin
    Exit(FInner.ReadString(AName, ADefault));
  end;
  mJson := JsonValue(mRouted.Path);
  if mJson = '' then
  begin
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Result := FInner.ReadString(AName, ADefault);
  end
  else if mRouted.Json then
  begin
    Result := ListOrObject(mJson, ADefault);
  end
  else
  begin
    Result := StringValue(mJson, ADefault);
  end;
end;

procedure TAtlasRoutedSettingsStore.WriteString(const AName, AValue: string);
var
  mRouted: TAtlasRoutedSetting;
  mJson: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, mRouted) or not (mRouted.Text or mRouted.Json) or not Writable then
  begin
    FInner.WriteString(AName, AValue);
    Exit;
  end;
  if mRouted.Legacy then
  begin
    Exit;
  end;
  if mRouted.Json then
  begin
    WriteJson(mRouted.Path, AValue);
    Exit;
  end;
  mJson := TAtlasJsonText.Quote(AValue);
  if JsonValue(mRouted.Path) <> mJson then
  begin
    FText := TAtlasJsonText.SetValue(FText, mRouted.Path, mJson);
  end;
end;

procedure TAtlasRoutedSettingsStore.MigrateOne(const ARouted: TAtlasRoutedSetting);
const
  cMissing = Low(Integer);
var
  mValue: Integer;
  mText: string;
begin
  if ARouted.Text then
  begin
    mText := FInner.ReadString(ARouted.Name, '');
    if mText <> '' then
    begin
      WriteString(ARouted.Name, mText);
    end;
  end
  else
  begin
    mValue := FInner.ReadInteger(ARouted.Name, cMissing);
    if mValue <> cMissing then
    begin
      WriteInteger(ARouted.Name, mValue);
    end;
  end;
end;

function TAtlasRoutedSettingsStore.Migrate: Boolean;
var
  mRouted: TAtlasRoutedSetting;
  mBefore: string;
begin
  mBefore := FText;
  if Writable then
  begin
    for mRouted in TAtlasSettingsScopes.Routed do
    begin
      // JSON-Listen lagen nie in der Registry.
      if not mRouted.Legacy and not mRouted.Json and (JsonValue(mRouted.Path) = '') then
      begin
        MigrateOne(mRouted);
      end;
    end;
  end;
  Result := FText <> mBefore;
end;

end.
