unit Atlas.Core.Settings.Catalog;

// Katalog aller persönlichen Einstellungen für Export, Import und Zurücksetzen
// (#723), ohne VCL und ohne Open Tools API. Quellen sind die beiden Schemata:
// - schemas/atlas-plugin.schema.json (AtlasPluginSchemaJson): jede Einstellung
//   aus TAtlasPluginSettings.Load/Save; Name = Registry-Name, x-key = Schlüssel
//   in der Exportdatei, x-area = Bereich, x-page = Seite.
// - schemas/atlas.schema.json (AtlasSchemaJson): jeder globale Schlüssel der
//   settings.json (x-scope "global" oder "both"); Objekte zerfallen eine Ebene
//   tief in ihre globalen Glieder, der Bereich kommt aus x-area des Glieds oder
//   des Objekts. Bei "both" (z. B. rules) gilt der Pfad zugleich als
//   Projektpfad: Der globale Wert ist übertragbar, atlas.json überdeckt ihn.
//   Ein Pfad, den schon eine Plugin-Einstellung trägt (umgeleitet, z. B.
//   index.usages), steht nur einmal im Katalog: als Plugin-Einstellung.
// Projektwerte (x-scope "project", atlas.json) und die Projektdatei .atlas
// gehören nie dazu; ihre Pfade kennt der Katalog nur, um sie beim Import zu
// erkennen und zu melden. Neue Einstellungen kommen damit ohne feste Liste in
// Export, Import und Zurücksetzen (Voraussetzung für #767).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
  /// <summary>Ablage einer Einstellung: Plugin (Registry bzw. umgeleitet) oder settings.json.</summary>
  TAtlasSettingSource = (asPlugin, asGlobal);

  /// <summary>Werteart aus "type"; Json = Zahl, Liste, Objekt oder mehrere Typen.</summary>
  TAtlasSettingKind = (akBoolean, akInteger, akString, akJson);

  TAtlasCatalogEntry = record
    /// <summary>Schlüssel in der Exportdatei: x-key bzw. Pfad in settings.json.</summary>
    Key: string;
    /// <summary>Name in TAtlasPluginSettings.Load/Save bzw. Pfad in settings.json.</summary>
    Name: string;
    Source: TAtlasSettingSource;
    Kind: TAtlasSettingKind;
    Area: string;
    Page: string;
    Caption: string;
    CaptionEn: string;
    /// <summary>Vorgabe als JSON-Text; '' = keine (fehlender Schlüssel gilt als Vorgabe).</summary>
    DefaultJson: string;
    /// <summary>Interner Zustand (Breiten, „gesehen“): nicht exportiert, nicht zurückgesetzt, nicht markiert.</summary>
    State: Boolean;
    /// <summary>Gilt nur für diesen Rechner (Serverpfad, Delphi-Version): nicht exportiert, nicht zurückgesetzt.</summary>
    Machine: Boolean;
    /// <summary>Pfad: Benutzerordner werden beim Export zu Pfadmakros.</summary>
    IsPath: Boolean;
    /// <summary>Zugangsdaten (x-secret).</summary>
    Secret: Boolean;
    /// <summary>"shortcut" für Tastenkürzel (TShortCut), sonst ''.</summary>
    Format: string;
    /// <summary>Frühere Schlüssel, die der Import auf Key umrechnet.</summary>
    FormerKeys: TArray<string>;
    /// <summary>Pfad in atlas.json, dessen Wert die Einstellung im Projekt überdeckt; '' = keiner.</summary>
    ProjectPath: string;
    /// <summary>Pfad in der Projektdatei .atlas (#486), deren Wert die Einstellung überdeckt; '' = keiner.</summary>
    TeamPath: string;
    /// <summary>Teilschema für die Prüfung eines Werts.</summary>
    SchemaJson: string;
    /// <summary>Wird exportiert, importiert und zurückgesetzt (weder Zustand noch Rechnerwert).</summary>
    function Transferable: Boolean;
  end;

  TAtlasCatalogArea = record
    Id: string;
    Caption: string;
    CaptionEn: string;
  end;

  TAtlasSettingsCatalog = class
  private
    FEntries: TList<TAtlasCatalogEntry>;
    FAreas: TArray<TAtlasCatalogArea>;
    FProjectPaths: TArray<string>;
    FVersion: Integer;
    procedure ReadPlugin(const AText: string);
    procedure ReadServer(const AText: string);
    procedure AddServerEntry(const AKey: string; ASchema, AParent: TJSONObject);
    procedure SetProjectPath(AIndex: Integer; const APath: string);
    /// <summary>Ein Schlüssel aus atlas.schema.json nach seinem x-scope einordnen.</summary>
    procedure AddServerKey(const AKey, AScope: string; ASchema, AParent: TJSONObject);
    function GetCount: Integer;
    function GetEntry(AIndex: Integer): TAtlasCatalogEntry;
  public
    /// <summary>Katalog aus dem Text beider Schemata (APluginSchema darf x-areas und x-version tragen).</summary>
    constructor Create(const APluginSchema, AServerSchema: string);
    destructor Destroy; override;
    /// <summary>Katalog aus den eingebauten Schemata (AtlasPluginSchemaJson, AtlasSchemaJson).</summary>
    class function CreateDefault: TAtlasSettingsCatalog; static;
    /// <summary>Eintrag mit Schlüssel AKey (ohne Groß-/Kleinschreibung); -1 ohne.</summary>
    function IndexOfKey(const AKey: string): Integer;
    /// <summary>Plugin-Eintrag mit Registry-Name AName; -1 ohne.</summary>
    function IndexOfName(const AName: string): Integer;
    /// <summary>Wie IndexOfKey, dazu Registry-Namen und x-formerKeys (AMigrated True); -1 ohne.</summary>
    function Resolve(const AKey: string; out AMigrated: Boolean): Integer;
    /// <summary>Gibt es den Bereich?</summary>
    function HasArea(const AArea: string): Boolean;
    /// <summary>Beschriftung des Bereichs; AArea selbst, wenn unbekannt.</summary>
    function AreaCaption(const AArea: string; AEnglish: Boolean): string;
    /// <summary>Alle Bereich-Kennungen in Katalogreihenfolge.</summary>
    function AreaIds: TArray<string>;
    /// <summary>Ist APath ein Projektschlüssel von atlas.json (oder liegt darunter)?</summary>
    function IsProjectPath(const APath: string): Boolean;
    /// <summary>Prüft AJson gegen das Schema von AEntry; AIssues: Meldungen.</summary>
    function ValidValue(const AEntry: TAtlasCatalogEntry; const AJson: string; out AIssues: TArray<string>): Boolean;
    property Count: Integer read GetCount;
    property Entries[AIndex: Integer]: TAtlasCatalogEntry read GetEntry; default;
    property Areas: TArray<TAtlasCatalogArea> read FAreas;
    /// <summary>x-version des Plugin-Katalogs (schemaVersion der Exportdatei).</summary>
    property Version: Integer read FVersion;
  end;

  /// <summary>Kleine Helfer für JSON-Werte als Text.</summary>
  TAtlasJsonValues = class
  public
    /// <summary>Wert aus AJson (beliebiger JSON-Wert) oder nil; der Aufrufer gibt ihn frei.</summary>
    class function Parse(const AJson: string): TJSONValue; static;
    /// <summary>Einheitliche Schreibweise für Vergleiche; '' bei ungültigem Text.</summary>
    class function Canonical(const AJson: string): string; static;
    /// <summary>Gleiche Werte (nach Canonical)?</summary>
    class function Same(const ALeft, ARight: string): Boolean; static;
    /// <summary>String-Inhalt bei einem JSON-String, sonst der Text selbst.</summary>
    class function Display(const AJson: string): string; static;
  end;

implementation

uses
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.SchemaCheck,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.PluginSchemaData;

function KindOf(ASchema: TJSONObject): TAtlasSettingKind;
var
  Value: TJSONValue;
  TypeName: string;
begin
  Result := akJson;
  Value := ASchema.GetValue('type');
  if not (Value is TJSONString) then
    Exit;
  TypeName := TJSONString(Value).Value;
  if TypeName = 'boolean' then
    Result := akBoolean
  else if TypeName = 'integer' then
    Result := akInteger
  else if TypeName = 'string' then
    Result := akString;
end;

function Flag(ASchema: TJSONObject; const AName: string): Boolean;
var
  Value: TJSONValue;
begin
  Value := nil;
  if ASchema <> nil then
    Value := ASchema.GetValue(AName);
  Result := (Value is TJSONBool) and TJSONBool(Value).AsBoolean;
end;

function TextOf(ASchema: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := nil;
  if ASchema <> nil then
    Value := ASchema.GetValue(AName);
  if Value is TJSONString then
    Result := TJSONString(Value).Value;
end;

function StringsOf(ASchema: TJSONObject; const AName: string): TArray<string>;
var
  Value, Item: TJSONValue;
begin
  Result := nil;
  Value := ASchema.GetValue(AName);
  if Value is TJSONArray then
    for Item in TJSONArray(Value) do
      if Item is TJSONString then
        Result := Result + [TJSONString(Item).Value];
end;

function DefaultOf(ASchema: TJSONObject): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := ASchema.GetValue('default');
  if Value <> nil then
    Result := Value.ToJSON;
end;

{ TAtlasCatalogEntry }

function TAtlasCatalogEntry.Transferable: Boolean;
begin
  Result := not State and not Machine;
end;

{ TAtlasJsonValues }

class function TAtlasJsonValues.Parse(const AJson: string): TJSONValue;
var
  Root, Value: TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
    Exit;
  // Über ein Hüllobjekt, damit auch einzelne Zahlen, Strings und Wahrheitswerte gelesen werden.
  Root := TJSONObject.ParseJSONValue('{"v":' + AJson + '}');
  try
    if not (Root is TJSONObject) then
      Exit;
    Value := TJSONObject(Root).GetValue('v');
    if Value = nil then
      Exit;
    Result := Value.Clone as TJSONValue;
  finally
    Root.Free;
  end;
end;

class function TAtlasJsonValues.Canonical(const AJson: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := Parse(AJson);
  try
    if Value <> nil then
      Result := Value.ToJSON;
  finally
    Value.Free;
  end;
end;

class function TAtlasJsonValues.Same(const ALeft, ARight: string): Boolean;
begin
  Result := Canonical(ALeft) = Canonical(ARight);
end;

class function TAtlasJsonValues.Display(const AJson: string): string;
var
  Value: TJSONValue;
begin
  Result := AJson;
  Value := Parse(AJson);
  try
    if Value is TJSONString then
      Result := TJSONString(Value).Value;
  finally
    Value.Free;
  end;
end;

{ TAtlasSettingsCatalog }

constructor TAtlasSettingsCatalog.Create(const APluginSchema, AServerSchema: string);
begin
  inherited Create;
  FEntries := TList<TAtlasCatalogEntry>.Create;
  ReadPlugin(APluginSchema);
  ReadServer(AServerSchema);
end;

destructor TAtlasSettingsCatalog.Destroy;
begin
  FEntries.Free;
  inherited;
end;

class function TAtlasSettingsCatalog.CreateDefault: TAtlasSettingsCatalog;
begin
  Result := TAtlasSettingsCatalog.Create(AtlasPluginSchemaJson, AtlasSchemaJson);
end;

procedure TAtlasSettingsCatalog.ReadPlugin(const AText: string);
var
  Root: TJSONObject;
  Areas, Properties: TJSONObject;
  Pair: TJSONPair;
  Schema: TJSONObject;
  Entry: TAtlasCatalogEntry;
  Area: TAtlasCatalogArea;
begin
  FVersion := 0;
  FAreas := nil;
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
    Exit;
  try
    FVersion := Root.GetValue<Integer>('x-version', 0);
    if Root.TryGetValue<TJSONObject>('x-areas', Areas) then
      for Pair in Areas do
      begin
        Area := Default(TAtlasCatalogArea);
        Area.Id := Pair.JsonString.Value;
        if Pair.JsonValue is TJSONObject then
        begin
          Area.Caption := TextOf(TJSONObject(Pair.JsonValue), 'caption');
          Area.CaptionEn := TextOf(TJSONObject(Pair.JsonValue), 'captionEn');
        end;
        FAreas := FAreas + [Area];
      end;
    if not Root.TryGetValue<TJSONObject>('properties', Properties) then
      Exit;
    for Pair in Properties do
    begin
      if not (Pair.JsonValue is TJSONObject) then
        Continue;
      Schema := TJSONObject(Pair.JsonValue);
      Entry := Default(TAtlasCatalogEntry);
      Entry.Name := Pair.JsonString.Value;
      Entry.Key := TextOf(Schema, 'x-key');
      if Entry.Key = '' then
        Entry.Key := Entry.Name;
      Entry.Source := asPlugin;
      Entry.Kind := KindOf(Schema);
      Entry.Area := TextOf(Schema, 'x-area');
      Entry.Page := TextOf(Schema, 'x-page');
      Entry.Caption := TextOf(Schema, 'x-caption');
      Entry.CaptionEn := TextOf(Schema, 'x-captionEn');
      Entry.DefaultJson := DefaultOf(Schema);
      Entry.State := Flag(Schema, 'x-state');
      Entry.Machine := Flag(Schema, 'x-machine');
      Entry.IsPath := Flag(Schema, 'x-path');
      Entry.Secret := Flag(Schema, 'x-secret');
      Entry.Format := TextOf(Schema, 'x-format');
      Entry.FormerKeys := StringsOf(Schema, 'x-formerKeys');
      Entry.ProjectPath := TextOf(Schema, 'x-project');
      Entry.TeamPath := TextOf(Schema, 'x-team');
      Entry.SchemaJson := Schema.ToJSON;
      FEntries.Add(Entry);
    end;
  finally
    Root.Free;
  end;
end;

procedure TAtlasSettingsCatalog.AddServerEntry(const AKey: string; ASchema, AParent: TJSONObject);
var
  Entry: TAtlasCatalogEntry;
  Plugin, Index: Integer;
begin
  // Pfad mit Plugin-Einstellung (umgeleitet, x-plugin): nur einmal, als Plugin-Einstellung.
  if IndexOfKey(AKey) >= 0 then
    Exit;
  Plugin := -1;
  if TextOf(ASchema, 'x-plugin') <> '' then
    Plugin := IndexOfName(TextOf(ASchema, 'x-plugin'));
  if Plugin >= 0 then
    Exit;
  Entry := Default(TAtlasCatalogEntry);
  Entry.Key := AKey;
  Entry.Name := AKey;
  Entry.Source := asGlobal;
  Entry.Kind := KindOf(ASchema);
  Entry.Area := TextOf(ASchema, 'x-area');
  if Entry.Area = '' then
    Entry.Area := TextOf(AParent, 'x-area');
  Entry.Page := TextOf(ASchema, 'x-page');
  if Entry.Page = '' then
    Entry.Page := TextOf(AParent, 'x-page');
  Entry.Caption := TextOf(ASchema, 'description');
  // Lange Beschreibungen nur bis zum ersten Satzende als Beschriftung.
  Index := Pos('. ', Entry.Caption);
  if Index > 0 then
    Entry.Caption := Copy(Entry.Caption, 1, Index);
  Entry.DefaultJson := DefaultOf(ASchema);
  Entry.Machine := Flag(ASchema, 'x-machine') or Flag(AParent, 'x-machine');
  Entry.State := Flag(ASchema, 'x-state');
  Entry.IsPath := Flag(ASchema, 'x-path');
  Entry.Secret := Flag(ASchema, 'x-secret');
  Entry.FormerKeys := StringsOf(ASchema, 'x-formerKeys');
  Entry.SchemaJson := ASchema.ToJSON;
  FEntries.Add(Entry);
end;

procedure TAtlasSettingsCatalog.SetProjectPath(AIndex: Integer; const APath: string);
var
  Entry: TAtlasCatalogEntry;
begin
  Entry := FEntries[AIndex];
  if Entry.ProjectPath <> '' then
    Exit;
  Entry.ProjectPath := APath;
  FEntries[AIndex] := Entry;
end;

procedure TAtlasSettingsCatalog.AddServerKey(const AKey, AScope: string; ASchema, AParent: TJSONObject);
var
  Plugin: string;
  Index: Integer;
begin
  if (AScope = 'global') or (AScope = 'both') then
    AddServerEntry(AKey, ASchema, AParent);
  if AScope = 'global' then
    Exit;
  FProjectPaths := FProjectPaths + [AKey];
  // Projektwert mit Plugin-Einstellung bzw. globaler Wert mit Projektwert ("both"): atlas.json überdeckt ihn.
  Index := -1;
  if AScope = 'both' then
    Index := IndexOfKey(AKey)
  else
  begin
    Plugin := TextOf(ASchema, 'x-plugin');
    if Plugin <> '' then
      Index := IndexOfName(Plugin);
  end;
  if Index >= 0 then
    SetProjectPath(Index, AKey);
end;

procedure TAtlasSettingsCatalog.ReadServer(const AText: string);
var
  Root, Properties, Members: TJSONObject;
  Pair, Member: TJSONPair;
  Schema, MemberSchema: TJSONObject;
  Scope, MemberScope: string;
begin
  FProjectPaths := nil;
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
    Exit;
  try
    if not Root.TryGetValue<TJSONObject>('properties', Properties) then
      Exit;
    for Pair in Properties do
    begin
      if not (Pair.JsonValue is TJSONObject) or (Pair.JsonString.Value = '$schema') then
        Continue;
      Schema := TJSONObject(Pair.JsonValue);
      Scope := TextOf(Schema, 'x-scope');
      if Schema.TryGetValue<TJSONObject>('properties', Members) then
      begin
        for Member in Members do
        begin
          if not (Member.JsonValue is TJSONObject) then
            Continue;
          MemberSchema := TJSONObject(Member.JsonValue);
          MemberScope := TextOf(MemberSchema, 'x-scope');
          if MemberScope = '' then
            MemberScope := Scope;
          AddServerKey(Pair.JsonString.Value + '.' + Member.JsonString.Value, MemberScope, MemberSchema, Schema);
        end;
      end
      else
        AddServerKey(Pair.JsonString.Value, Scope, Schema, nil);
    end;
  finally
    Root.Free;
  end;
end;

function TAtlasSettingsCatalog.GetCount: Integer;
begin
  Result := FEntries.Count;
end;

function TAtlasSettingsCatalog.GetEntry(AIndex: Integer): TAtlasCatalogEntry;
begin
  Result := FEntries[AIndex];
end;

function TAtlasSettingsCatalog.IndexOfKey(const AKey: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to FEntries.Count - 1 do
    if SameText(FEntries[Index].Key, AKey) then
      Exit(Index);
end;

function TAtlasSettingsCatalog.IndexOfName(const AName: string): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index := 0 to FEntries.Count - 1 do
    if (FEntries[Index].Source = asPlugin) and SameText(FEntries[Index].Name, AName) then
      Exit(Index);
end;

function TAtlasSettingsCatalog.Resolve(const AKey: string; out AMigrated: Boolean): Integer;
var
  Index: Integer;
  Former: string;
begin
  AMigrated := False;
  Result := IndexOfKey(AKey);
  if Result >= 0 then
    Exit;
  // Ältere Dateien: Registry-Namen (flache Liste ohne Schlüssel) und frühere Schlüssel.
  AMigrated := True;
  Result := IndexOfName(AKey);
  if Result >= 0 then
    Exit;
  for Index := 0 to FEntries.Count - 1 do
    for Former in FEntries[Index].FormerKeys do
      if SameText(Former, AKey) then
        Exit(Index);
  AMigrated := False;
end;

function TAtlasSettingsCatalog.HasArea(const AArea: string): Boolean;
var
  Area: TAtlasCatalogArea;
begin
  Result := False;
  for Area in FAreas do
    if SameText(Area.Id, AArea) then
      Exit(True);
end;

function TAtlasSettingsCatalog.AreaCaption(const AArea: string; AEnglish: Boolean): string;
var
  Area: TAtlasCatalogArea;
begin
  Result := AArea;
  for Area in FAreas do
    if SameText(Area.Id, AArea) then
    begin
      Result := Area.Caption;
      if AEnglish and (Area.CaptionEn <> '') then
        Result := Area.CaptionEn;
      Exit;
    end;
end;

function TAtlasSettingsCatalog.AreaIds: TArray<string>;
var
  Area: TAtlasCatalogArea;
begin
  Result := nil;
  for Area in FAreas do
    Result := Result + [Area.Id];
end;

function TAtlasSettingsCatalog.IsProjectPath(const APath: string): Boolean;
var
  Path: string;
begin
  Result := False;
  for Path in FProjectPaths do
    if SameText(Path, APath) or SameText(Path + '.', Copy(APath, 1, Length(Path) + 1)) then
      Exit(True);
end;

function TAtlasSettingsCatalog.ValidValue(const AEntry: TAtlasCatalogEntry; const AJson: string;
  out AIssues: TArray<string>): Boolean;
var
  Value, Schema: TJSONValue;
begin
  AIssues := nil;
  Value := TAtlasJsonValues.Parse(AJson);
  Schema := TJSONObject.ParseJSONValue(AEntry.SchemaJson);
  try
    if Value = nil then
      AIssues := AIssues + [AEntry.Key + ': kein gültiger JSON-Wert']
    else if Schema is TJSONObject then
      TAtlasSchemaCheck.Check(Value, TJSONObject(Schema), AEntry.Key, AIssues);
  finally
    Schema.Free;
    Value.Free;
  end;
  Result := Length(AIssues) = 0;
end;

end.
