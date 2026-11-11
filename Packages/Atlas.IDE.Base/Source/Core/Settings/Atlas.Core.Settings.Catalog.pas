unit Atlas.Core.Settings.Catalog;

// Katalog aller persönlichen Einstellungen für Export, Import und Zurücksetzen
// (#723), ohne VCL und ohne Open Tools API. Quellen sind die beiden Schemata:
// - schemas/atlas-plugin.schema.json (AtlasPluginSchemaJson): jede Einstellung
//   aus TAtlasPluginSettings.Load/Save; Name = Registry-Name, x-key = Schlüssel
//   in der Exportdatei, x-area = Bereich, x-page = Seite, x-parent = Hauptschalter
//   und x-node = Unterpunkt im Baum der Optionsseite (#890, ausgewertet in
//   Atlas.Core.Settings.Groups); die Unterpunkte selbst stehen in x-nodes.
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
// Beschreibung, Synonyme (x-keywords) und Schnellschalter trägt der Katalog für die Suche über die Einstellungen
// (#1884, Atlas.Core.Settings.Search).

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
    /// <summary>Gilt nur für diesen Rechner (Serverpfad, Delphi-Version): nicht exportiert, nicht
    /// zurückgesetzt.</summary>
    Machine: Boolean;
    /// <summary>Pfad: Benutzerordner werden beim Export zu Pfadmakros.</summary>
    IsPath: Boolean;
    /// <summary>Zugangsdaten (x-secret).</summary>
    Secret: Boolean;
    /// <summary>"shortcut" für Tastenkürzel (TShortCut), sonst ''.</summary>
    Format: string;
    /// <summary>Frühere Schlüssel, die der Import auf Key umrechnet.</summary>
    FormerKeys: TArray<string>;
    /// <summary>Frühere Registry-Namen derselben Einstellung mit unverändertem Wert (x-renamedFrom, #1280): die
    /// Übernahme beim Start (TAtlasSettingsRenames) und der Import älterer Dateien rechnen sie um.</summary>
    RenamedFrom: TArray<string>;
    /// <summary>Pfad in atlas.json, dessen Wert die Einstellung im Projekt überdeckt; '' = keiner.</summary>
    ProjectPath: string;
    /// <summary>Pfad in der Projektdatei .atlas (#486), deren Wert die Einstellung überdeckt; '' = keiner.</summary>
    TeamPath: string;
    /// <summary>Teilschema für die Prüfung eines Werts.</summary>
    SchemaJson: string;
    /// <summary>Experimentelle Funktion (x-experimental, #834): Vorgabe aus, wirkt nur mit experimental.enabled.
    /// </summary>
    Experimental: Boolean;
    /// <summary>x-parent (#890): x-key des Hauptschalters; nur mit HasParent gesetzt ('' = ausdrücklich keiner).
    /// </summary>
    Parent: string;
    HasParent: Boolean;
    /// <summary>x-node (#890): Unterpunkt der Optionsseite; nur mit HasNode gesetzt ('' = Hauptknoten).</summary>
    Node: string;
    HasNode: Boolean;
    /// <summary>x-module (#1454): Kennung des Moduls, wenn die Einstellung dessen Modul-Schalter ist; sonst ''.
    /// Alles unter dem Schalter (x-parent bzw. Präfixregel) gehört zum Modul.</summary>
    Module: string;
    /// <summary>x-offValue als JSON-Text: Wert für „aus“ einer nicht booleschen Einstellung; '' ohne.</summary>
    OffJson: string;
    /// <summary>Beschreibung aus "description" (Plugin) in voller Länge; '' ohne. Für die Suche (#1884).</summary>
    Description: string;
    /// <summary>Synonyme aus x-keywords (#1884), z. B. „Tooltip“ an der Hover-Einstellung; gelten abgeschwächt
    /// auch für die Unteroptionen.</summary>
    Keywords: TArray<string>;
    /// <summary>Schnellschalter (x-quickToggle, #604): in der Befehlspalette direkt umschaltbar (#1884).</summary>
    QuickToggle: Boolean;
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
    FNodes: TArray<TAtlasCatalogArea>;
    FProjectPaths: TArray<string>;
    FVersion: Integer;
    procedure ReadPlugin(const AText: string);
    procedure ReadServer(const AText: string);
    procedure AddServerEntry(const AKey: string; ASchema, AParent: TJSONObject);
    procedure SetProjectPath(AIndex: Integer; const APath: string);
    /// <summary>Ein Schlüssel aus atlas.schema.json nach seinem x-scope einordnen.</summary>
    procedure AddServerKey(const AKey, AScope: string; ASchema, AParent: TJSONObject);
    procedure AddServerMembers(const AName: string; ASchema, AMembers: TJSONObject; const AScope: string);
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
    /// <summary>Wie IndexOfKey, dazu Registry-Namen, x-formerKeys und x-renamedFrom (AMigrated True); -1
    /// ohne.</summary>
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
    /// <summary>Unterpunkte der Optionsseite aus x-nodes (#890) in Schemareihenfolge.</summary>
    property Nodes: TArray<TAtlasCatalogArea> read FNodes;
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
  System.StrUtils,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.SchemaCheck,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.PluginSchemaData,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TCatalogText = (NotAValidJSONValue);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TCatalogText] of string = (
    (': kein gültiger JSON-Wert'),
    (': not a valid JSON value'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TCatalogText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function KindOf(ASchema: TJSONObject): TAtlasSettingKind;
var
  mValue: TJSONValue;
  mTypeName: string;
begin
  Result := akJson;
  mValue := ASchema.GetValue('type');
  if not (mValue is TJSONString) then
  begin
    Exit;
  end;
  mTypeName := TJSONString(mValue).Value;
  if mTypeName = 'boolean' then
  begin
    Result := akBoolean;
  end
  else if mTypeName = 'integer' then
  begin
    Result := akInteger;
  end
  else if mTypeName = 'string' then
  begin
    Result := akString;
  end;
end;

function Flag(ASchema: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := nil;
  if ASchema <> nil then
  begin
    mValue := ASchema.GetValue(AName);
  end;
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function TextOf(ASchema: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := nil;
  if ASchema <> nil then
  begin
    mValue := ASchema.GetValue(AName);
  end;
  if mValue is TJSONString then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function StringsOf(ASchema: TJSONObject; const AName: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := ASchema.GetValue(AName);
  if mValue is TJSONArray then
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [TJSONString(mItem).Value];
      end;
    end;
  end;
end;

/// <summary>Text des Schlüssels AName; AFound False, wenn er fehlt (oder kein String ist).</summary>
function OptionalText(ASchema: TJSONObject; const AName: string; out AFound: Boolean): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := ASchema.GetValue(AName);
  AFound := mValue is TJSONString;
  if AFound then
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function ReadAreas(ARoot: TJSONObject; const AName: string): TArray<TAtlasCatalogArea>;
var
  mTable: TJSONObject;
  mPair: TJSONPair;
  mArea: TAtlasCatalogArea;
begin
  Result := nil;
  if not ARoot.TryGetValue<TJSONObject>(AName, mTable) then
  begin
    Exit;
  end;
  for mPair in mTable do
  begin
    mArea := Default(TAtlasCatalogArea);
    mArea.Id := mPair.JsonString.Value;
    if mPair.JsonValue is TJSONObject then
    begin
      mArea.Caption := TextOf(TJSONObject(mPair.JsonValue), 'caption');
      mArea.CaptionEn := TextOf(TJSONObject(mPair.JsonValue), 'captionEn');
    end;
    Result := Result + [mArea];
  end;
end;

/// <summary>Wert des Schlüssels AName als JSON-Text ('default', 'x-offValue'); '' ohne.</summary>
function JsonOf(ASchema: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := ASchema.GetValue(AName);
  if mValue <> nil then
  begin
    Result := mValue.ToJSON;
  end;
end;

{ TAtlasCatalogEntry }

/// <summary>Eintrag der Plugin-Einstellung AName aus ihrem Schema.</summary>
function PluginEntry(const AName: string; ASchema: TJSONObject): TAtlasCatalogEntry;
begin
  Result := Default(TAtlasCatalogEntry);
  Result.Name := AName;
  Result.Key := TextOf(ASchema, 'x-key');
  if Result.Key = '' then
  begin
    Result.Key := AName;
  end;
  Result.Source := asPlugin;
  Result.Kind := KindOf(ASchema);
  Result.Area := TextOf(ASchema, 'x-area');
  Result.Page := TextOf(ASchema, 'x-page');
  Result.Caption := TextOf(ASchema, 'x-caption');
  Result.CaptionEn := TextOf(ASchema, 'x-captionEn');
  Result.DefaultJson := JsonOf(ASchema, 'default');
  Result.State := Flag(ASchema, 'x-state');
  Result.Machine := Flag(ASchema, 'x-machine');
  Result.IsPath := Flag(ASchema, 'x-path');
  Result.Secret := Flag(ASchema, 'x-secret');
  Result.Format := TextOf(ASchema, 'x-format');
  Result.FormerKeys := StringsOf(ASchema, 'x-formerKeys');
  Result.RenamedFrom := StringsOf(ASchema, 'x-renamedFrom');
  Result.ProjectPath := TextOf(ASchema, 'x-project');
  Result.TeamPath := TextOf(ASchema, 'x-team');
  Result.SchemaJson := ASchema.ToJSON;
  Result.Experimental := Flag(ASchema, 'x-experimental');
  Result.Parent := OptionalText(ASchema, 'x-parent', Result.HasParent);
  Result.Node := OptionalText(ASchema, 'x-node', Result.HasNode);
  Result.Module := TextOf(ASchema, 'x-module');
  Result.OffJson := JsonOf(ASchema, 'x-offValue');
  Result.Description := TextOf(ASchema, 'description');
  Result.Keywords := StringsOf(ASchema, 'x-keywords');
  Result.QuickToggle := Flag(ASchema, 'x-quickToggle');
end;

/// <summary>Text von AName aus ASchema, sonst aus AParent (darf nil sein).</summary>
function InheritedText(ASchema, AParent: TJSONObject; const AName: string): string;
begin
  Result := TextOf(ASchema, AName);
  if Result = '' then
  begin
    Result := TextOf(AParent, AName);
  end;
end;

/// <summary>Lange Beschreibungen nur bis zum ersten Satzende als Beschriftung.</summary>
function FirstSentence(const AText: string): string;
var
  mIndex: Integer;
begin
  Result := AText;
  mIndex := Pos('. ', Result);
  if mIndex > 0 then
  begin
    Result := Copy(Result, 1, mIndex);
  end;
end;

/// <summary>Eintrag der globalen Server-Einstellung AKey; AParent ist das Schema des Objekts darüber (darf
/// nil sein).</summary>
function ServerEntry(const AKey: string; ASchema, AParent: TJSONObject): TAtlasCatalogEntry;
begin
  Result := Default(TAtlasCatalogEntry);
  Result.Key := AKey;
  Result.Name := AKey;
  Result.Source := asGlobal;
  Result.Kind := KindOf(ASchema);
  Result.Area := InheritedText(ASchema, AParent, 'x-area');
  Result.Page := InheritedText(ASchema, AParent, 'x-page');
  Result.Caption := FirstSentence(TextOf(ASchema, 'description'));
  // Englisch aus x-description-en (#1458), ebenso gekürzt.
  Result.CaptionEn := FirstSentence(TextOf(ASchema, 'x-description-en'));
  Result.DefaultJson := JsonOf(ASchema, 'default');
  Result.Machine := Flag(ASchema, 'x-machine') or Flag(AParent, 'x-machine');
  Result.State := Flag(ASchema, 'x-state');
  Result.IsPath := Flag(ASchema, 'x-path');
  Result.Secret := Flag(ASchema, 'x-secret');
  Result.FormerKeys := StringsOf(ASchema, 'x-formerKeys');
  Result.SchemaJson := ASchema.ToJSON;
  Result.Experimental := Flag(ASchema, 'x-experimental');
end;

/// <summary>AKey ist ein früherer Schlüssel eines Eintrags in AEntries.</summary>
function IsFormerKey(AEntries: TList<TAtlasCatalogEntry>; const AKey: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to AEntries.Count - 1 do
  begin
    if MatchText(AKey, AEntries[mIndex].FormerKeys) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasCatalogEntry.Transferable: Boolean;
begin
  Result := not State and not Machine;
end;

{ TAtlasJsonValues }

class function TAtlasJsonValues.Parse(const AJson: string): TJSONValue;
var
  mRoot, mValue: TJSONValue;
begin
  Result := nil;
  if Trim(AJson) = '' then
  begin
    Exit;
  end;
  // Über ein Hüllobjekt, damit auch einzelne Zahlen, Strings und Wahrheitswerte gelesen werden.
  mRoot := TJSONObject.ParseJSONValue('{"v":' + AJson + '}');
  try
    if not (mRoot is TJSONObject) then
    begin
      Exit;
    end;
    mValue := TJSONObject(mRoot).GetValue('v');
    if mValue = nil then
    begin
      Exit;
    end;
    Result := mValue.Clone as TJSONValue;
  finally
    mRoot.Free;
  end;
end;

class function TAtlasJsonValues.Canonical(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := Parse(AJson);
  try
    if mValue <> nil then
    begin
      Result := mValue.ToJSON;
    end;
  finally
    mValue.Free;
  end;
end;

class function TAtlasJsonValues.Same(const ALeft, ARight: string): Boolean;
begin
  Result := Canonical(ALeft) = Canonical(ARight);
end;

class function TAtlasJsonValues.Display(const AJson: string): string;
var
  mValue: TJSONValue;
begin
  Result := AJson;
  mValue := Parse(AJson);
  try
    if mValue is TJSONString then
    begin
      Result := TJSONString(mValue).Value;
    end;
  finally
    mValue.Free;
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
  mRoot, mProperties: TJSONObject;
  mPair: TJSONPair;
begin
  FVersion := 0;
  FAreas := nil;
  FNodes := nil;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    FVersion := mRoot.GetValue<Integer>('x-version', 0);
    FAreas := ReadAreas(mRoot, 'x-areas');
    FNodes := ReadAreas(mRoot, 'x-nodes');
    if not mRoot.TryGetValue<TJSONObject>('properties', mProperties) then
    begin
      Exit;
    end;
    for mPair in mProperties do
    begin
      if mPair.JsonValue is TJSONObject then
      begin
        FEntries.Add(PluginEntry(mPair.JsonString.Value, TJSONObject(mPair.JsonValue)));
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

procedure TAtlasSettingsCatalog.AddServerEntry(const AKey: string; ASchema, AParent: TJSONObject);
var
  mEntry: TAtlasCatalogEntry;
  mPlugin: Integer;
begin
  // Früherer Schlüssel einer Plugin-Einstellung (z. B. hints.xmlDocFull, #770): Ältere Dateien übernimmt der
  // neue Eintrag.
  if IsFormerKey(FEntries, AKey) then
  begin
    Exit;
  end;
  // Pfad mit Plugin-Einstellung (umgeleitet, x-plugin): nur einmal, als Plugin-Einstellung; x-experimental
  // gilt an beiden Stellen.
  mPlugin := IndexOfKey(AKey);
  if (mPlugin < 0) and (TextOf(ASchema, 'x-plugin') <> '') then
  begin
    mPlugin := IndexOfName(TextOf(ASchema, 'x-plugin'));
  end;
  if mPlugin < 0 then
  begin
    FEntries.Add(ServerEntry(AKey, ASchema, AParent));
  end
  else if Flag(ASchema, 'x-experimental') then
  begin
    mEntry := FEntries[mPlugin];
    mEntry.Experimental := True;
    FEntries[mPlugin] := mEntry;
  end;
end;

procedure TAtlasSettingsCatalog.SetProjectPath(AIndex: Integer; const APath: string);
var
  mEntry: TAtlasCatalogEntry;
begin
  mEntry := FEntries[AIndex];
  if mEntry.ProjectPath <> '' then
  begin
    Exit;
  end;
  mEntry.ProjectPath := APath;
  FEntries[AIndex] := mEntry;
end;

procedure TAtlasSettingsCatalog.AddServerKey(const AKey, AScope: string; ASchema, AParent: TJSONObject);
var
  mPlugin: string;
  mIndex: Integer;
begin
  if (AScope = 'global') or (AScope = 'both') then
  begin
    AddServerEntry(AKey, ASchema, AParent);
  end;
  if AScope = 'global' then
  begin
    Exit;
  end;
  FProjectPaths := FProjectPaths + [AKey];
  // Projektwert mit Plugin-Einstellung bzw. globaler Wert mit Projektwert ("both"): atlas.json überdeckt ihn.
  mIndex := -1;
  if AScope = 'both' then
  begin
    mIndex := IndexOfKey(AKey);
  end
  else
  begin
    mPlugin := TextOf(ASchema, 'x-plugin');
    if mPlugin <> '' then
    begin
      mIndex := IndexOfName(mPlugin);
    end;
  end;
  if mIndex >= 0 then
  begin
    SetProjectPath(mIndex, AKey);
  end;
end;

procedure TAtlasSettingsCatalog.AddServerMembers(const AName: string; ASchema, AMembers: TJSONObject;
  const AScope: string);
var
  mMember: TJSONPair;
  mSchema: TJSONObject;
  mScope: string;
begin
  for mMember in AMembers do
  begin
    if not (mMember.JsonValue is TJSONObject) then
    begin
      Continue;
    end;
    mSchema := TJSONObject(mMember.JsonValue);
    mScope := TextOf(mSchema, 'x-scope');
    if mScope = '' then
    begin
      mScope := AScope;
    end;
    AddServerKey(AName + '.' + mMember.JsonString.Value, mScope, mSchema, ASchema);
  end;
end;

procedure TAtlasSettingsCatalog.ReadServer(const AText: string);
var
  mRoot, mProperties, mMembers, mSchema: TJSONObject;
  mPair: TJSONPair;
begin
  FProjectPaths := nil;
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Exit;
  end;
  try
    if not mRoot.TryGetValue<TJSONObject>('properties', mProperties) then
    begin
      Exit;
    end;
    for mPair in mProperties do
    begin
      if not (mPair.JsonValue is TJSONObject) or (mPair.JsonString.Value = '$schema') then
      begin
        Continue;
      end;
      mSchema := TJSONObject(mPair.JsonValue);
      if mSchema.TryGetValue<TJSONObject>('properties', mMembers) then
      begin
        AddServerMembers(mPair.JsonString.Value, mSchema, mMembers, TextOf(mSchema, 'x-scope'));
      end
      else
      begin
        AddServerKey(mPair.JsonString.Value, TextOf(mSchema, 'x-scope'), mSchema, nil);
      end;
    end;
  finally
    mRoot.Free;
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
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if SameText(FEntries[mIndex].Key, AKey) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasSettingsCatalog.IndexOfName(const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    if (FEntries[mIndex].Source = asPlugin) and SameText(FEntries[mIndex].Name, AName) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TAtlasSettingsCatalog.Resolve(const AKey: string; out AMigrated: Boolean): Integer;
var
  mIndex: Integer;
  mFormer: string;
begin
  AMigrated := False;
  Result := IndexOfKey(AKey);
  if Result >= 0 then
  begin
    Exit;
  end;
  // Ältere Dateien: Registry-Namen (flache Liste ohne Schlüssel), frühere Schlüssel und frühere Registry-Namen.
  AMigrated := True;
  Result := IndexOfName(AKey);
  if Result >= 0 then
  begin
    Exit;
  end;
  for mIndex := 0 to FEntries.Count - 1 do
  begin
    for mFormer in FEntries[mIndex].FormerKeys do
    begin
      if SameText(mFormer, AKey) then
      begin
        Exit(mIndex);
      end;
    end;
    for mFormer in FEntries[mIndex].RenamedFrom do
    begin
      if SameText(mFormer, AKey) then
      begin
        Exit(mIndex);
      end;
    end;
  end;
  AMigrated := False;
end;

function TAtlasSettingsCatalog.HasArea(const AArea: string): Boolean;
var
  mArea: TAtlasCatalogArea;
begin
  Result := False;
  for mArea in FAreas do
  begin
    if SameText(mArea.Id, AArea) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasSettingsCatalog.AreaCaption(const AArea: string; AEnglish: Boolean): string;
var
  mArea: TAtlasCatalogArea;
begin
  Result := AArea;
  for mArea in FAreas do
  begin
    if SameText(mArea.Id, AArea) then
    begin
      Result := mArea.Caption;
      if AEnglish and (mArea.CaptionEn <> '') then
      begin
        Result := mArea.CaptionEn;
      end;
      Exit;
    end;
  end;
end;

function TAtlasSettingsCatalog.AreaIds: TArray<string>;
var
  mArea: TAtlasCatalogArea;
begin
  Result := nil;
  for mArea in FAreas do
  begin
    Result := Result + [mArea.Id];
  end;
end;

function TAtlasSettingsCatalog.IsProjectPath(const APath: string): Boolean;
var
  mPath: string;
begin
  Result := False;
  for mPath in FProjectPaths do
  begin
    if SameText(mPath, APath) or SameText(mPath + '.', Copy(APath, 1, Length(mPath) + 1)) then
    begin
      Exit(True);
    end;
  end;
end;

function TAtlasSettingsCatalog.ValidValue(const AEntry: TAtlasCatalogEntry; const AJson: string;
  out AIssues: TArray<string>): Boolean;
var
  mValue, mSchema: TJSONValue;
begin
  AIssues := nil;
  mValue := TAtlasJsonValues.Parse(AJson);
  mSchema := TJSONObject.ParseJSONValue(AEntry.SchemaJson);
  try
    if mValue = nil then
    begin
      AIssues := AIssues + [AEntry.Key + UiText(TCatalogText.NotAValidJSONValue)];
    end
    else if mSchema is TJSONObject then
    begin
      TAtlasSchemaCheck.Check(mValue, TJSONObject(mSchema), AEntry.Key, AIssues);
    end;
  finally
    mSchema.Free;
    mValue.Free;
  end;
  Result := Length(AIssues) = 0;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Settings.Catalog', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
