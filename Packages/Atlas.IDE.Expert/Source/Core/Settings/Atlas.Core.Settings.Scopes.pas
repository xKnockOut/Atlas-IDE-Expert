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
  Item: TAtlasRoutedSetting;
begin
  for Item in Routed do
    if SameText(Item.Name, AName) then
    begin
      ASetting := Item;
      Exit(True);
    end;
  ASetting := Default(TAtlasRoutedSetting);
  Result := False;
end;

class function TAtlasSettingsScopes.IdeManagedPaths: TArray<string>;
var
  Item: TAtlasRoutedSetting;
begin
  Result := [DelphiVersionPath];
  for Item in Routed do
    Result := Result + [Item.Path];
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
  Root: TJSONObject;
begin
  Result := '';
  Root := TAtlasJsonText.Parse(FText);
  try
    if Root <> nil then
      Result := TAtlasJsonText.ValueAt(Root, APath);
  finally
    Root.Free;
  end;
end;

function TAtlasRoutedSettingsStore.Writable: Boolean;
var
  Root: TJSONObject;
begin
  // Eine kaputte Datei wird nicht angefasst; die Werte bleiben dann für diese Sitzung.
  if Trim(FText) = '' then
    Exit(True);
  Root := TAtlasJsonText.Parse(FText);
  Result := Root <> nil;
  Root.Free;
end;

procedure TAtlasRoutedSettingsStore.WriteJson(const APath, AValue: string);
var
  Value: TJSONValue;
  Json: string;
begin
  Value := TJSONObject.ParseJSONValue(Trim(AValue));
  try
    // Nur Liste oder Objekt; kaputter Text wird nie in die Datei geschrieben.
    if not ((Value is TJSONArray) or (Value is TJSONObject)) then
      Exit;
    Json := Value.ToJSON;
    if JsonValue(APath) = Json then
      Exit;
    // Eine leere Liste ist der Standard und steht nur in der Datei, wenn dort schon eine Liste stand.
    if (Json = '[]') and (JsonValue(APath) = '') then
      Exit;
    FText := TAtlasJsonText.SetValue(FText, APath, Trim(AValue));
  finally
    Value.Free;
  end;
end;

function TAtlasRoutedSettingsStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  Routed: TAtlasRoutedSetting;
  Value: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, Routed) then
    Exit(FInner.ReadInteger(AName, ADefault));
  Value := JsonValue(Routed.Path);
  if Value = 'true' then
    Result := 1
  else if Value = 'false' then
    Result := 0
  else if Value <> '' then
    Result := StrToIntDef(Value, ADefault)
  else
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Result := FInner.ReadInteger(AName, ADefault);
end;

procedure TAtlasRoutedSettingsStore.WriteInteger(const AName: string; AValue: Integer);
var
  Routed: TAtlasRoutedSetting;
  Json: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, Routed) or not Writable then
  begin
    FInner.WriteInteger(AName, AValue);
    Exit;
  end;
  if Routed.Legacy then
    Exit;
  if not Routed.Flag then
    Json := IntToStr(AValue)
  else if AValue <> 0 then
    Json := 'true'
  else
    Json := 'false';
  if JsonValue(Routed.Path) <> Json then
    FText := TAtlasJsonText.SetValue(FText, Routed.Path, Json);
end;

function TAtlasRoutedSettingsStore.ReadString(const AName, ADefault: string): string;
var
  Routed: TAtlasRoutedSetting;
  Value: TJSONValue;
  Json: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, Routed) or not (Routed.Text or Routed.Json) then
    Exit(FInner.ReadString(AName, ADefault));
  Json := JsonValue(Routed.Path);
  if Routed.Json then
  begin
    if Json = '' then
      Exit(FInner.ReadString(AName, ADefault));
    // Nur Liste oder Objekt; ein Wert der falschen Art gilt als Standard (der Server meldet ihn).
    if CharInSet(Json[1], ['[', '{']) then
      Exit(Json);
    Exit(ADefault);
  end;
  if Json = '' then
    // Noch nicht in settings.json: alter Wert aus der Registry, sonst die Vorgabe.
    Exit(FInner.ReadString(AName, ADefault));
  Result := ADefault;
  Value := TJSONObject.ParseJSONValue(Json);
  try
    if Value is TJSONString then
      Result := TJSONString(Value).Value;
  finally
    Value.Free;
  end;
end;

procedure TAtlasRoutedSettingsStore.WriteString(const AName, AValue: string);
var
  Routed: TAtlasRoutedSetting;
  Json: string;
begin
  if not TAtlasSettingsScopes.TryRouted(AName, Routed) or not (Routed.Text or Routed.Json) or not Writable then
  begin
    FInner.WriteString(AName, AValue);
    Exit;
  end;
  if Routed.Legacy then
    Exit;
  if Routed.Json then
  begin
    WriteJson(Routed.Path, AValue);
    Exit;
  end;
  Json := TAtlasJsonText.Quote(AValue);
  if JsonValue(Routed.Path) <> Json then
    FText := TAtlasJsonText.SetValue(FText, Routed.Path, Json);
end;

function TAtlasRoutedSettingsStore.Migrate: Boolean;
const
  Missing = Low(Integer);
var
  Routed: TAtlasRoutedSetting;
  Value: Integer;
  mText: string;
  Before: string;
begin
  Before := FText;
  if Writable then
    for Routed in TAtlasSettingsScopes.Routed do
      // JSON-Listen lagen nie in der Registry.
      if not Routed.Legacy and not Routed.Json and (JsonValue(Routed.Path) = '') then
        if Routed.Text then
        begin
          mText := FInner.ReadString(Routed.Name, '');
          if mText <> '' then
            WriteString(Routed.Name, mText);
        end
        else
        begin
          Value := FInner.ReadInteger(Routed.Name, Missing);
          if Value <> Missing then
            WriteInteger(Routed.Name, Value);
        end;
  Result := FText <> Before;
end;

end.
