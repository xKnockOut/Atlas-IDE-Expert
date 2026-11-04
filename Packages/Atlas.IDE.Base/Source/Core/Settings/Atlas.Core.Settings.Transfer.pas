unit Atlas.Core.Settings.Transfer;

// Einstellungen exportieren, importieren und zurücksetzen (#723), ohne VCL und
// ohne Open Tools API. Grundlage ist TAtlasSettingsCatalog (beide Schemata):
// - Stand: TAtlasPluginSettings (Registry samt umgeleiteter Werte) und der Text
//   von %APPDATA%\Atlas\settings.json. Projekt- und Teamwerte (atlas.json,
//   .atlas) gehören nie dazu und werden nie geschrieben.
// - Export (atlas-settings.json): nur geänderte Werte der gewählten Bereiche,
//   mit Format-, Schema- und Atlas-Version. Ohne Zustände und Rechnerwerte,
//   Zugangsdaten ausgelassen oder als Platzhalter, Benutzerordner als
//   Pfadmakro ($(LOCALAPPDATA), $(APPDATA), $(USERPROFILE)); enthält ein Wert
//   danach noch den Benutzernamen, bleibt er weg. Eine Sicherung (Backup)
//   enthält alles unverändert und dient nur zum Zurückholen auf diesem Rechner.
// - Import: Vorschau „aktuell → neu“ je Schlüssel. Zusammenführen übernimmt
//   die gewählten Werte, Ersetzen setzt zusätzlich alle übrigen Werte der
//   gewählten Bereiche auf den Standard. Unbekannte Schlüssel (neuere Version)
//   werden gemeldet und übersprungen; Registry-Namen älterer Dateien, frühere
//   Schlüssel (x-formerKeys) und 0/1 für Wahrheitswerte rechnet die Migration
//   um. Projektwerte in der Datei werden übersprungen; überdeckt ein Wert aus
//   atlas.json oder .atlas eine Einstellung, zeigt die Vorschau das.
// - Zurücksetzen je Schlüssel, je Bereich oder alles; Zustände und
//   Rechnerwerte bleiben.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog;

type
  /// <summary>Wert einer Umgebungsvariablen (APPDATA, LOCALAPPDATA, USERPROFILE, USERNAME); '' = unbekannt. Wie
  /// TAtlasPathVariable (#759), hier eigen: Atlas.Core.Settings darf nicht von Atlas.Core.Projects abhängen
  /// (Feature-Zyklus, A-09).</summary>
  TAtlasSettingsEnvironment = reference to function(const AName: string): string;

  /// <summary>Persönliche Einstellungen: Plugin und Text von settings.json.</summary>
  TAtlasSettingsState = record
    Plugin: TAtlasPluginSettings;
    GlobalText: string;
    class function Create(const APlugin: TAtlasPluginSettings; const AGlobalText: string): TAtlasSettingsState; static;
  end;

  TAtlasSecretMode = (smOmit, smPlaceholder);

  TAtlasExportOptions = record
    /// <summary>Bereiche; leer = alle.</summary>
    Areas: TArray<string>;
    Secrets: TAtlasSecretMode;
    /// <summary>Sicherung vor dem Import: alle Werte unverändert, auch Zustände und Rechnerwerte.</summary>
    Backup: Boolean;
    class function Create(const AAreas: TArray<string>; ASecrets: TAtlasSecretMode): TAtlasExportOptions; static;
    class function ForBackup: TAtlasExportOptions; static;
  end;

  TAtlasOmitReason = (orSecret, orUserPath);

  TAtlasExportOmission = record
    Key: string;
    Reason: TAtlasOmitReason;
  end;

  TAtlasExportResult = record
    /// <summary>Inhalt von atlas-settings.json (UTF-8 ohne BOM, Zeilenende #10).</summary>
    Text: string;
    /// <summary>Zahl der geschriebenen Werte.</summary>
    Count: Integer;
    /// <summary>Werte mit Platzhalter für Zugangsdaten.</summary>
    Placeholders: TArray<string>;
    Omitted: TArray<TAtlasExportOmission>;
  end;

  /// <summary>Gelesene Exportdatei.</summary>
  TAtlasSettingsFile = record
    Valid: Boolean;
    /// <summary>Grund, wenn Valid False ist.</summary>
    Error: string;
    FormatVersion: Integer;
    /// <summary>0 = ältere Datei ohne Schemaversion (flache Registry-Namen).</summary>
    SchemaVersion: Integer;
    AtlasVersion: string;
    Name: string;
    NameEn: string;
    Description: string;
    DescriptionEn: string;
    /// <summary>"merge", "replace" oder ''.</summary>
    Mode: string;
    Backup: Boolean;
    Areas: TArray<string>;
    Keys: TArray<string>;
    /// <summary>JSON-Text je Schlüssel.</summary>
    Values: TArray<string>;
  end;

  TAtlasImportMode = (imMerge, imReplace);

  TAtlasImportStatus = (
    /// <summary>Neuer Wert.</summary>
    isChange,
    /// <summary>Schon so eingestellt.</summary>
    isSame,
    /// <summary>Ersetzen: fehlt in der Datei, zurück auf den Standard.</summary>
    isReset,
    /// <summary>Unbekannter Schlüssel (z. B. aus einer neueren Version): übersprungen.</summary>
    isUnknown,
    /// <summary>Wert passt nicht zum Schema: übersprungen.</summary>
    isInvalid,
    /// <summary>Platzhalter für Zugangsdaten: übersprungen.</summary>
    isSecret,
    /// <summary>Projektwert, Zustand oder Rechnerwert: übersprungen.</summary>
    isSkipped);

  TAtlasImportItem = record
    /// <summary>Schlüssel im Katalog; bei Unbekanntem der aus der Datei.</summary>
    Key: string;
    /// <summary>Schlüssel, wie er in der Datei steht.</summary>
    SourceKey: string;
    /// <summary>Index im Katalog; -1 ohne Eintrag.</summary>
    Entry: Integer;
    Area: string;
    /// <summary>Aktueller Wert als JSON; '' = nicht gesetzt (Standard).</summary>
    CurrentJson: string;
    /// <summary>Neuer Wert als JSON; '' = Standard (Schlüssel entfällt).</summary>
    NewJson: string;
    Status: TAtlasImportStatus;
    Selected: Boolean;
    /// <summary>Über die Migration umgerechnet (Registry-Name, früherer Schlüssel, 0/1).</summary>
    Migrated: Boolean;
    /// <summary>Projektwert, der die Einstellung überdeckt: "atlas.json: pfad = wert" bzw. ".atlas: …".</summary>
    Covered: string;
    /// <summary>Meldungen der Schemaprüfung bei isInvalid.</summary>
    Issues: TArray<string>;
    /// <summary>Lässt sich anwählen (neuer Wert oder Zurücksetzen).</summary>
    function Selectable: Boolean;
  end;

  TAtlasImportPreview = record
    Source: TAtlasSettingsFile;
    Mode: TAtlasImportMode;
    /// <summary>Bereiche, für die die Vorschau gilt.</summary>
    Areas: TArray<string>;
    Items: TArray<TAtlasImportItem>;
    /// <summary>Datei aus einer neueren Atlas-Version (Schemaversion größer als die des Katalogs).</summary>
    Newer: Boolean;
    function SelectedCount: Integer;
    function CountOf(AStatus: TAtlasImportStatus): Integer;
  end;

  TAtlasSettingsTransfer = class
  public const
    FormatName = 'atlas-settings';
    FormatVersion = 1;
    FileName = 'atlas-settings.json';
    SecretPlaceholder = '<secret>';
    /// <summary>So viele Sicherungen bleiben in %APPDATA%\Atlas\Backups.</summary>
    KeepBackups = 10;
    BackupPrefix = 'atlas-settings-';
  public
    /// <summary>Aktueller Wert als JSON; '' = nicht gesetzt (nur settings.json).</summary>
    class function CurrentJson(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      AIndex: Integer): string; static;
    /// <summary>Standardwert als JSON; '' = Schlüssel entfällt (nur settings.json).</summary>
    class function DefaultJson(ACatalog: TAtlasSettingsCatalog; AIndex: Integer): string; static;
    /// <summary>Weicht der Wert vom Standard ab? Zustände und Rechnerwerte zählen nicht.</summary>
    class function IsModified(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      AIndex: Integer): Boolean; static;
    /// <summary>Schlüssel aller geänderten Werte (ohne Zustände und Rechnerwerte).</summary>
    class function ModifiedKeys(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState): TArray<string>;
      static;
    /// <summary>Registry-Namen der geänderten Plugin-Einstellungen: für den Punkt am Feld.</summary>
    class function ModifiedNames(ACatalog: TAtlasSettingsCatalog; const ASettings: TAtlasPluginSettings): TArray<string>;
      static;
    /// <summary>Setzt die Plugin-Einstellungen ANames (Registry-Namen) auf den Standard; Zustände und
    /// Rechnerwerte bleiben.</summary>
    class function ResetNames(ACatalog: TAtlasSettingsCatalog; const ASettings: TAtlasPluginSettings;
      const ANames: TArray<string>): TAtlasPluginSettings; static;
    class function ResetKeys(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const AKeys: TArray<string>): TAtlasSettingsState; static;
    class function ResetAreas(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const AAreas: TArray<string>): TAtlasSettingsState; static;
    class function ResetAll(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState): TAtlasSettingsState;
      static;
    /// <summary>Exportdatei; AEnvironment liefert APPDATA, LOCALAPPDATA, USERPROFILE und USERNAME.</summary>
    class function ExportSettings(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const AOptions: TAtlasExportOptions; const AEnvironment: TAtlasSettingsEnvironment): TAtlasExportResult; static;
    /// <summary>Liest eine Exportdatei; ältere Dateien ohne "settings" gelten als flache Liste.</summary>
    class function ParseFile(const AText: string): TAtlasSettingsFile; static;
    /// <summary>Vorschau des Imports. AAreas leer = Bereiche der Datei (sonst alle). AProjectText und
    /// ATeamText: atlas.json und .atlas des aktiven Projekts ('' ohne).</summary>
    class function Preview(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const AFile: TAtlasSettingsFile; AMode: TAtlasImportMode; const AAreas: TArray<string>;
      const AEnvironment: TAtlasSettingsEnvironment; const AProjectText, ATeamText: string): TAtlasImportPreview; static;
    /// <summary>Übernimmt die gewählten Einträge der Vorschau.</summary>
    class function Apply(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const APreview: TAtlasImportPreview): TAtlasSettingsState; static;
    /// <summary>Prüft eine Datei (eingebaute Profile): Format, Bereiche, Modus, bekannte Schlüssel ohne
    /// Migration und Werte gegen das Schema.</summary>
    class function Validate(ACatalog: TAtlasSettingsCatalog; const AText: string; out AIssues: TArray<string>): Boolean;
      static;
    /// <summary>Import-Modus aus "mode" der Datei.</summary>
    class function ModeOf(const AFile: TAtlasSettingsFile): TAtlasImportMode; static;
    /// <summary>Name der Sicherung: atlas-settings-JJJJMMTT-HHMMSS.json.</summary>
    class function BackupFileName(ANow: TDateTime): string; static;
    /// <summary>Sicherungen aus AFiles (Dateinamen), die über AKeep hinaus wegfallen: die ältesten.</summary>
    class function BackupsToDelete(const AFiles: TArray<string>; AKeep: Integer): TArray<string>; static;
  end;

implementation

uses
  System.Generics.Defaults,
  Atlas.Text.Checkin,
  Atlas.Core.Product.Version,
  Atlas.Core.Settings.History,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Settings.QueryMigration;

const
  /// <summary>Benutzerordner für Pfadmakros, der längste zuerst.</summary>
  UserMacros: array[0..2] of string = ('LOCALAPPDATA', 'APPDATA', 'USERPROFILE');

function IsText(AValue: TJSONValue): Boolean;
begin
  // TJSONNumber erbt von TJSONString.
  Result := (AValue is TJSONString) and not (AValue is TJSONNumber);
end;

function IsTrue(AValue: TJSONValue): Boolean;
begin
  Result := (AValue is TJSONBool) and TJSONBool(AValue).AsBoolean;
end;

function BoolJson(AValue: Boolean): string;
begin
  if AValue then
  begin
    Result := 'true';
  end
  else
  begin
    Result := 'false';
  end;
end;

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  Result := False;
  for Item in AList do
  begin
    if SameText(Item, AValue) then
    begin
      Exit(True);
    end;
  end;
end;

function LastSegment(const AKey: string): string;
var
  Index: Integer;
begin
  Result := AKey;
  for Index := Length(AKey) downto 1 do
  begin
    if AKey[Index] = '.' then
    begin
      Exit(Copy(AKey, Index + 1, MaxInt));
    end;
  end;
end;

function TrimSlash(const APath: string): string;
begin
  Result := APath;
  while (Result <> '') and ((Result[Length(Result)] = '\') or (Result[Length(Result)] = '/')) do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

/// <summary>Endet ein Pfadstück an APos (Trenner, Ende, Anführungszeichen, Leerraum, ;)?</summary>
function AtBoundary(const AText: string; APos: Integer): Boolean;
begin
  Result := (APos > Length(AText)) or CharInSet(AText[APos], ['\', '/', '"', '''', ' ', #9, ';', ',', '|']);
end;

/// <summary>Ersetzt AFolder (ohne Groß-/Kleinschreibung, nur an Pfadgrenzen) durch AMacro.</summary>
function ReplaceFolder(const AText, AFolder, AMacro: string): string;
var
  Lower, Needle: string;
  Start, Found: Integer;
begin
  Result := '';
  Lower := LowerCase(AText);
  Needle := LowerCase(AFolder);
  Start := 1;
  repeat
    Found := Pos(Needle, Copy(Lower, Start, MaxInt));
    if Found = 0 then
    begin
      Break;
    end;
    Found := Found + Start - 1;
    if AtBoundary(AText, Found + Length(Needle)) then
    begin
      Result := Result + Copy(AText, Start, Found - Start) + AMacro;
      Start := Found + Length(Needle);
    end
    else
    begin
      Result := Result + Copy(AText, Start, Found - Start + Length(Needle));
      Start := Found + Length(Needle);
    end;
  until False;
  Result := Result + Copy(AText, Start, MaxInt);
end;

/// <summary>Enthält AText den Benutzernamen als Pfadstück (…\name\… oder …\name am Ende)?</summary>
function HasUserName(const AText, AUser: string): Boolean;
var
  Lower, Needle: string;
  Start, Found: Integer;
begin
  Result := False;
  if AUser = '' then
  begin
    Exit;
  end;
  Lower := LowerCase(AText);
  Needle := LowerCase(AUser);
  Start := 1;
  repeat
    Found := Pos(Needle, Copy(Lower, Start, MaxInt));
    if Found = 0 then
    begin
      Exit;
    end;
    Found := Found + Start - 1;
    if (Found > 1) and CharInSet(AText[Found - 1], ['\', '/']) and AtBoundary(AText, Found + Length(Needle)) then
    begin
      Exit(True);
    end;
    Start := Found + 1;
  until False;
end;

type
  /// <summary>Benutzerordner und -name aus den Pfadmakros.</summary>
  TUserFolders = record
    Macros: TArray<string>;
    Folders: TArray<string>;
    User: string;
    class function From(const AEnvironment: TAtlasSettingsEnvironment): TUserFolders; static;
    function Shorten(const AText: string; var AHasUser: Boolean): string;
    function Expand(const AText: string): string;
  end;

function EnvironmentValue(const AEnvironment: TAtlasSettingsEnvironment; const AName: string): string;
begin
  Result := '';
  if Assigned(AEnvironment) then
  begin
    Result := AEnvironment(AName);
  end;
end;

class function TUserFolders.From(const AEnvironment: TAtlasSettingsEnvironment): TUserFolders;
var
  Name, Folder: string;
begin
  Result.Macros := nil;
  Result.Folders := nil;
  for Name in UserMacros do
  begin
    Folder := TrimSlash(EnvironmentValue(AEnvironment, Name));
    if Folder <> '' then
    begin
      Result.Macros := Result.Macros + [Name];
      Result.Folders := Result.Folders + [Folder];
    end;
  end;
  Result.User := EnvironmentValue(AEnvironment, 'USERNAME');
  if Result.User = '' then
  begin
    Folder := TrimSlash(EnvironmentValue(AEnvironment, 'USERPROFILE'));
    Result.User := LastSegment(StringReplace(StringReplace(Folder, '\', '.', [rfReplaceAll]), '/', '.',
      [rfReplaceAll]));
  end;
end;

function TUserFolders.Shorten(const AText: string; var AHasUser: Boolean): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := 0 to High(Folders) do
  begin
    Result := ReplaceFolder(Result, Folders[Index], '$(' + Macros[Index] + ')');
  end;
  if HasUserName(Result, User) then
  begin
    AHasUser := True;
  end;
end;

function TUserFolders.Expand(const AText: string): string;
var
  Index: Integer;
begin
  Result := AText;
  for Index := 0 to High(Folders) do
  begin
    Result := StringReplace(Result, '$(' + Macros[Index] + ')', Folders[Index], [rfReplaceAll, rfIgnoreCase]);
  end;
end;

/// <summary>Kopie von AValue mit allen Strings über AFolders gekürzt (AExpand False) bzw. ausgeschrieben.</summary>
function MapStrings(AValue: TJSONValue; const AFolders: TUserFolders; AExpand: Boolean;
  var AHasUser: Boolean): TJSONValue;
var
  Pair: TJSONPair;
  Item: TJSONValue;
  Obj: TJSONObject;
  List: TJSONArray;
begin
  if IsText(AValue) then
  begin
    if AExpand then
    begin
      Result := TJSONString.Create(AFolders.Expand(TJSONString(AValue).Value));
    end
    else
    begin
      Result := TJSONString.Create(AFolders.Shorten(TJSONString(AValue).Value, AHasUser));
    end;
  end
  else if AValue is TJSONObject then
  begin
    Obj := TJSONObject.Create;
    for Pair in TJSONObject(AValue) do
    begin
      Obj.AddPair(Pair.JsonString.Value, MapStrings(Pair.JsonValue, AFolders, AExpand, AHasUser));
    end;
    Result := Obj;
  end
  else if AValue is TJSONArray then
  begin
    List := TJSONArray.Create;
    for Item in TJSONArray(AValue) do
    begin
      List.AddElement(MapStrings(Item, AFolders, AExpand, AHasUser));
    end;
    Result := List;
  end
  else
  begin
    Result := AValue.Clone as TJSONValue;
  end;
end;

/// <summary>Trägt AValue Zugangsdaten? Strings unter einem Schlüssel wie token/password, Adressen mit
/// Benutzer oder Token; Wahrheitswerte und Zahlen nie.</summary>
function HasSecret(AValue: TJSONValue; const AKey: string; AMarked: Boolean): Boolean;
var
  Pair: TJSONPair;
  Item: TJSONValue;
begin
  Result := False;
  if IsText(AValue) then
  begin
    Result := (TJSONString(AValue).Value <> '') and
      (AMarked or TTextCheckin.IsCredentialKey(AKey) or TTextCheckin.HasUrlCredentials(TJSONString(AValue).Value));
  end
  else if AValue is TJSONObject then
  begin
    for Pair in TJSONObject(AValue) do
    begin
      if HasSecret(Pair.JsonValue, Pair.JsonString.Value, AMarked) then
      begin
        Exit(True);
      end;
    end;
  end
  else if AValue is TJSONArray then
  begin
    for Item in TJSONArray(AValue) do
    begin
      if HasSecret(Item, AKey, AMarked) then
      begin
        Exit(True);
      end;
    end;
  end;
end;

/// <summary>Werte des Stands lesen und schreiben (Plugin über einen Speicher, global über den Text).</summary>
type
  TStateValues = class
  private
    FCatalog: TAtlasSettingsCatalog;
    FStore: IAtlasMemorySettingsStore;
    FText: string;
    FRoot: TJSONObject;
    function Root: TJSONObject;
  public
    constructor Create(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState);
    destructor Destroy; override;
    function Get(AIndex: Integer): string;
    procedure Put(AIndex: Integer; const AJson: string);
    function State: TAtlasSettingsState;
  end;

var
  DefaultStore: IAtlasMemorySettingsStore;

function DefaultValues: IAtlasMemorySettingsStore;
begin
  if DefaultStore = nil then
  begin
    DefaultStore := TAtlasMemorySettingsStore.FromSettings(TAtlasPluginSettings.Defaults);
  end;
  Result := DefaultStore;
end;

function PluginJson(const AStore: IAtlasSettingsStore; const AEntry: TAtlasCatalogEntry): string;
var
  Value: TJSONValue;
begin
  case AEntry.Kind of
    akBoolean:
      Result := BoolJson(AStore.ReadInteger(AEntry.Name, 0) <> 0);
    akInteger:
      Result := IntToStr(AStore.ReadInteger(AEntry.Name, 0));
    akJson:
      begin
        // Liste oder Objekt als JSON-Text (issues.connections, #1260); Ungültiges wie der Standard.
        Result := AEntry.DefaultJson;
        Value := TAtlasJsonValues.Parse(AStore.ReadString(AEntry.Name, ''));
        try
          if (Value is TJSONArray) or (Value is TJSONObject) then
          begin
            Result := Value.ToJSON;
          end;
        finally
          Value.Free;
        end;
      end;
  else
    Result := TAtlasJsonText.Quote(AStore.ReadString(AEntry.Name, ''));
  end;
end;

constructor TStateValues.Create(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState);
begin
  inherited Create;
  FCatalog := ACatalog;
  FStore := TAtlasMemorySettingsStore.FromSettings(AState.Plugin);
  FText := AState.GlobalText;
end;

destructor TStateValues.Destroy;
begin
  FRoot.Free;
  inherited;
end;

function TStateValues.Root: TJSONObject;
begin
  if FRoot = nil then
  begin
    FRoot := TAtlasJsonText.Parse(FText);
  end;
  Result := FRoot;
end;

function TStateValues.Get(AIndex: Integer): string;
var
  Entry: TAtlasCatalogEntry;
begin
  Entry := FCatalog[AIndex];
  if Entry.Source = asPlugin then
  begin
    Exit(PluginJson(FStore, Entry));
  end;
  Result := '';
  if Root <> nil then
  begin
    Result := TAtlasJsonText.ValueAt(Root, Entry.Key);
  end;
end;

procedure TStateValues.Put(AIndex: Integer; const AJson: string);
var
  Entry: TAtlasCatalogEntry;
  Value: TJSONValue;
begin
  Entry := FCatalog[AIndex];
  if Entry.Source = asGlobal then
  begin
    if AJson = '' then
    begin
      FText := TAtlasJsonText.Remove(FText, Entry.Key);
    end
    else
    begin
      FText := TAtlasJsonText.SetValue(FText, Entry.Key, AJson);
    end;
    FreeAndNil(FRoot);
    Exit;
  end;
  // Plugin: '' = Standard.
  if AJson = '' then
  begin
    if Entry.Kind in [akString, akJson] then
    begin
      FStore.WriteString(Entry.Name, DefaultValues.ReadString(Entry.Name, ''));
    end
    else
    begin
      FStore.WriteInteger(Entry.Name, DefaultValues.ReadInteger(Entry.Name, 0));
    end;
    Exit;
  end;
  Value := TAtlasJsonValues.Parse(AJson);
  try
    if Value = nil then
    begin
      Exit;
    end;
    case Entry.Kind of
      akBoolean:
        FStore.WriteInteger(Entry.Name, Ord((Value is TJSONBool) and TJSONBool(Value).AsBoolean));
      akInteger:
        if Value is TJSONNumber then
        begin
          FStore.WriteInteger(Entry.Name, TJSONNumber(Value).AsInt);
        end;
      akJson:
        if (Value is TJSONArray) or (Value is TJSONObject) then
        begin
          FStore.WriteString(Entry.Name, Value.ToJSON);
        end;
    else
      if IsText(Value) then
      begin
        FStore.WriteString(Entry.Name, TJSONString(Value).Value);
      end;
    end;
  finally
    Value.Free;
  end;
end;

function TStateValues.State: TAtlasSettingsState;
begin
  Result.Plugin := TAtlasPluginSettings.Defaults;
  Result.Plugin.Load(FStore);
  Result.GlobalText := FText;
end;

{ TAtlasSettingsState }

class function TAtlasSettingsState.Create(const APlugin: TAtlasPluginSettings;
  const AGlobalText: string): TAtlasSettingsState;
begin
  Result.Plugin := APlugin;
  Result.GlobalText := AGlobalText;
end;

{ TAtlasExportOptions }

class function TAtlasExportOptions.Create(const AAreas: TArray<string>;
  ASecrets: TAtlasSecretMode): TAtlasExportOptions;
begin
  Result.Areas := AAreas;
  Result.Secrets := ASecrets;
  Result.Backup := False;
end;

class function TAtlasExportOptions.ForBackup: TAtlasExportOptions;
begin
  Result.Areas := nil;
  Result.Secrets := smOmit;
  Result.Backup := True;
end;

{ TAtlasImportItem }

function TAtlasImportItem.Selectable: Boolean;
begin
  Result := Status in [isChange, isReset];
end;

{ TAtlasImportPreview }

function TAtlasImportPreview.SelectedCount: Integer;
var
  Item: TAtlasImportItem;
begin
  Result := 0;
  for Item in Items do
  begin
    if Item.Selected and Item.Selectable then
    begin
      Inc(Result);
    end;
  end;
end;

function TAtlasImportPreview.CountOf(AStatus: TAtlasImportStatus): Integer;
var
  Item: TAtlasImportItem;
begin
  Result := 0;
  for Item in Items do
  begin
    if Item.Status = AStatus then
    begin
      Inc(Result);
    end;
  end;
end;

{ TAtlasSettingsTransfer }

class function TAtlasSettingsTransfer.CurrentJson(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; AIndex: Integer): string;
var
  Values: TStateValues;
begin
  Values := TStateValues.Create(ACatalog, AState);
  try
    Result := Values.Get(AIndex);
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.DefaultJson(ACatalog: TAtlasSettingsCatalog; AIndex: Integer): string;
begin
  if ACatalog[AIndex].Source = asPlugin then
  begin
    Result := PluginJson(DefaultValues, ACatalog[AIndex]);
  end
  else
  begin
    Result := ACatalog[AIndex].DefaultJson;
  end;
end;

function Modified(ACatalog: TAtlasSettingsCatalog; AValues: TStateValues; AIndex: Integer): Boolean;
var
  Current, Default: string;
begin
  Result := False;
  if not ACatalog[AIndex].Transferable then
  begin
    Exit;
  end;
  Current := AValues.Get(AIndex);
  // settings.json: ein fehlender Schlüssel ist der Standard.
  if Current = '' then
  begin
    Exit;
  end;
  Default := TAtlasSettingsTransfer.DefaultJson(ACatalog, AIndex);
  Result := (Default = '') or ((Current <> Default) and not TAtlasJsonValues.Same(Current, Default));
end;

class function TAtlasSettingsTransfer.IsModified(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; AIndex: Integer): Boolean;
var
  Values: TStateValues;
begin
  Values := TStateValues.Create(ACatalog, AState);
  try
    Result := Modified(ACatalog, Values, AIndex);
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ModifiedKeys(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState): TArray<string>;
var
  Values: TStateValues;
  Index: Integer;
begin
  Result := nil;
  Values := TStateValues.Create(ACatalog, AState);
  try
    for Index := 0 to ACatalog.Count - 1 do
    begin
      if Modified(ACatalog, Values, Index) then
      begin
        Result := Result + [ACatalog[Index].Key];
      end;
    end;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ModifiedNames(ACatalog: TAtlasSettingsCatalog;
  const ASettings: TAtlasPluginSettings): TArray<string>;
var
  Values: TStateValues;
  Index: Integer;
begin
  Result := nil;
  Values := TStateValues.Create(ACatalog, TAtlasSettingsState.Create(ASettings, ''));
  try
    for Index := 0 to ACatalog.Count - 1 do
    begin
      if (ACatalog[Index].Source = asPlugin) and Modified(ACatalog, Values, Index) then
      begin
        Result := Result + [ACatalog[Index].Name];
      end;
    end;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ResetNames(ACatalog: TAtlasSettingsCatalog;
  const ASettings: TAtlasPluginSettings; const ANames: TArray<string>): TAtlasPluginSettings;
var
  Values: TStateValues;
  Name: string;
  Index: Integer;
begin
  Values := TStateValues.Create(ACatalog, TAtlasSettingsState.Create(ASettings, ''));
  try
    for Name in ANames do
    begin
      Index := ACatalog.IndexOfName(Name);
      if (Index >= 0) and ACatalog[Index].Transferable then
      begin
        Values.Put(Index, '');
      end;
    end;
    Result := Values.State.Plugin;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ResetKeys(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; const AKeys: TArray<string>): TAtlasSettingsState;
var
  Values: TStateValues;
  Key: string;
  Index: Integer;
begin
  Values := TStateValues.Create(ACatalog, AState);
  try
    for Key in AKeys do
    begin
      Index := ACatalog.IndexOfKey(Key);
      if (Index >= 0) and ACatalog[Index].Transferable then
      begin
        Values.Put(Index, '');
      end;
    end;
    Result := Values.State;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ResetAreas(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; const AAreas: TArray<string>): TAtlasSettingsState;
var
  Values: TStateValues;
  Index: Integer;
begin
  Values := TStateValues.Create(ACatalog, AState);
  try
    for Index := 0 to ACatalog.Count - 1 do
    begin
      if ACatalog[Index].Transferable and Contains(AAreas, ACatalog[Index].Area) and
        Modified(ACatalog, Values, Index) then
      begin
        Values.Put(Index, '');
      end;
    end;
    Result := Values.State;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.ResetAll(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState): TAtlasSettingsState;
begin
  Result := ResetAreas(ACatalog, AState, ACatalog.AreaIds);
end;

function JsonList(const AItems: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '[';
  for Index := 0 to High(AItems) do
  begin
    if Index > 0 then
    begin
      Result := Result + ', ';
    end;
    Result := Result + TAtlasJsonText.Quote(AItems[Index]);
  end;
  Result := Result + ']';
end;

/// <summary>JSON-Text eines Werts; Strings über Quote (Umlaute bleiben lesbar).</summary>
function ValueText(AValue: TJSONValue): string;
begin
  if IsText(AValue) then
  begin
    Result := TAtlasJsonText.Quote(TJSONString(AValue).Value);
  end
  else
  begin
    Result := AValue.ToJSON;
  end;
end;

class function TAtlasSettingsTransfer.ExportSettings(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; const AOptions: TAtlasExportOptions;
  const AEnvironment: TAtlasSettingsEnvironment): TAtlasExportResult;
var
  Values: TStateValues;
  Folders: TUserFolders;
  Areas, Lines: TArray<string>;
  Index: Integer;
  Entry: TAtlasCatalogEntry;
  Current: string;
  Value, Mapped: TJSONValue;
  HasUser: Boolean;
  Omission: TAtlasExportOmission;
  Text: string;
begin
  Result := Default(TAtlasExportResult);
  Folders := TUserFolders.From(AEnvironment);
  Areas := nil;
  for Text in ACatalog.AreaIds do
  begin
    if (Length(AOptions.Areas) = 0) or Contains(AOptions.Areas, Text) then
    begin
      Areas := Areas + [Text];
    end;
  end;
  Lines := nil;
  Values := TStateValues.Create(ACatalog, AState);
  try
    for Index := 0 to ACatalog.Count - 1 do
    begin
      Entry := ACatalog[Index];
      if not Contains(Areas, Entry.Area) then
      begin
        Continue;
      end;
      if AOptions.Backup then
      begin
        Current := Values.Get(Index);
        if Current = '' then
        begin
          Continue;
        end;
      end
      else
      begin
        if not Modified(ACatalog, Values, Index) then
        begin
          Continue;
        end;
        Current := Values.Get(Index);
      end;
      Value := TAtlasJsonValues.Parse(Current);
      if Value = nil then
      begin
        Continue;
      end;
      try
        if AOptions.Backup then
        begin
          Lines := Lines + ['    ' + TAtlasJsonText.Quote(Entry.Key) + ': ' + ValueText(Value)];
          Continue;
        end;
        if HasSecret(Value, LastSegment(Entry.Key), Entry.Secret) then
        begin
          if AOptions.Secrets = smOmit then
          begin
            Omission.Key := Entry.Key;
            Omission.Reason := orSecret;
            Result.Omitted := Result.Omitted + [Omission];
          end
          else
          begin
            Lines := Lines + ['    ' + TAtlasJsonText.Quote(Entry.Key) + ': ' + TAtlasJsonText.Quote(SecretPlaceholder)];
            Result.Placeholders := Result.Placeholders + [Entry.Key];
          end;
          Continue;
        end;
        HasUser := False;
        Mapped := MapStrings(Value, Folders, False, HasUser);
        try
          if HasUser then
          begin
            Omission.Key := Entry.Key;
            Omission.Reason := orUserPath;
            Result.Omitted := Result.Omitted + [Omission];
            Continue;
          end;
          Lines := Lines + ['    ' + TAtlasJsonText.Quote(Entry.Key) + ': ' + ValueText(Mapped)];
        finally
          Mapped.Free;
        end;
      finally
        Value.Free;
      end;
    end;
  finally
    Values.Free;
  end;
  Result.Count := Length(Lines);
  Text := '{' + #10 +
    '  "format": ' + TAtlasJsonText.Quote(FormatName) + ',' + #10 +
    '  "formatVersion": ' + IntToStr(FormatVersion) + ',' + #10 +
    '  "schemaVersion": ' + IntToStr(ACatalog.Version) + ',' + #10 +
    '  "atlasVersion": ' + TAtlasJsonText.Quote(TAtlasPluginVersion.Version) + ',' + #10;
  if AOptions.Backup then
  begin
    Text := Text + '  "backup": true,' + #10;
  end;
  Text := Text + '  "areas": ' + JsonList(Areas) + ',' + #10 + '  "settings": {';
  for Index := 0 to High(Lines) do
  begin
    if Index > 0 then
    begin
      Text := Text + ',';
    end;
    Text := Text + #10 + Lines[Index];
  end;
  if Length(Lines) > 0 then
  begin
    Text := Text + #10 + '  ';
  end;
  Result.Text := Text + '}' + #10 + '}' + #10;
end;

function StringField(ARoot: TJSONObject; const AName: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := ARoot.GetValue(AName);
  if IsText(Value) then
  begin
    Result := TJSONString(Value).Value;
  end;
end;

function IntegerField(ARoot: TJSONObject; const AName: string): Integer;
var
  Value: TJSONValue;
begin
  Result := 0;
  Value := ARoot.GetValue(AName);
  if Value is TJSONNumber then
  begin
    Result := TJSONNumber(Value).AsInt;
  end;
end;

class function TAtlasSettingsTransfer.ParseFile(const AText: string): TAtlasSettingsFile;
var
  Root: TJSONObject;
  Settings, Areas, Item: TJSONValue;
  Pair: TJSONPair;
begin
  Result := Default(TAtlasSettingsFile);
  Root := TAtlasJsonText.Parse(AText);
  if Root = nil then
  begin
    Result.Error := 'kein JSON-Objekt';
    Exit;
  end;
  try
    Settings := Root.GetValue('settings');
    if Settings = nil then
    begin
      // Ältere Datei: flache Liste von Registry-Namen (Werte 0/1, Zahlen, Text).
      if Root.GetValue('format') <> nil then
      begin
        Result.Error := 'ohne "settings"';
        Exit;
      end;
      for Pair in Root do
      begin
        Result.Keys := Result.Keys + [Pair.JsonString.Value];
        Result.Values := Result.Values + [ValueText(Pair.JsonValue)];
      end;
      Result.Valid := True;
      Exit;
    end;
    if not (Settings is TJSONObject) then
    begin
      Result.Error := '"settings" ist kein Objekt';
      Exit;
    end;
    if (Root.GetValue('format') <> nil) and (StringField(Root, 'format') <> FormatName) then
    begin
      Result.Error := 'anderes Format: ' + StringField(Root, 'format');
      Exit;
    end;
    Result.FormatVersion := IntegerField(Root, 'formatVersion');
    Result.SchemaVersion := IntegerField(Root, 'schemaVersion');
    Result.AtlasVersion := StringField(Root, 'atlasVersion');
    Result.Name := StringField(Root, 'name');
    Result.NameEn := StringField(Root, 'nameEn');
    Result.Description := StringField(Root, 'description');
    Result.DescriptionEn := StringField(Root, 'descriptionEn');
    Result.Mode := StringField(Root, 'mode');
    Result.Backup := IsTrue(Root.GetValue('backup'));
    Areas := Root.GetValue('areas');
    if Areas is TJSONArray then
    begin
      for Item in TJSONArray(Areas) do
      begin
        if IsText(Item) then
        begin
          Result.Areas := Result.Areas + [TJSONString(Item).Value];
        end;
      end;
    end;
    for Pair in TJSONObject(Settings) do
    begin
      Result.Keys := Result.Keys + [Pair.JsonString.Value];
      Result.Values := Result.Values + [ValueText(Pair.JsonValue)];
    end;
    Result.Valid := True;
  finally
    Root.Free;
  end;
end;

class function TAtlasSettingsTransfer.ModeOf(const AFile: TAtlasSettingsFile): TAtlasImportMode;
begin
  if SameText(AFile.Mode, 'replace') then
  begin
    Result := imReplace;
  end
  else
  begin
    Result := imMerge;
  end;
end;

/// <summary>Wert an APath in AText (JSON mit Kommentaren) als Anzeige; '' ohne.</summary>
function ProjectValue(ARoot: TJSONObject; const APath: string): string;
begin
  Result := '';
  if (ARoot = nil) or (APath = '') then
  begin
    Exit;
  end;
  Result := TAtlasJsonText.ValueAt(ARoot, APath);
  if Result <> '' then
  begin
    Result := TAtlasJsonValues.Display(Result);
  end;
end;

/// <summary>Wert für AEntry umrechnen: 0/1 für Wahrheitswerte, Pfadmakros ausschreiben.</summary>
function Migrate(const AEntry: TAtlasCatalogEntry; const AJson: string; const AFolders: TUserFolders;
  var AMigrated: Boolean): string;
var
  Value, Mapped: TJSONValue;
  Dummy: Boolean;
begin
  Result := AJson;
  Value := TAtlasJsonValues.Parse(AJson);
  if Value = nil then
  begin
    Exit;
  end;
  try
    if (AEntry.Kind = akBoolean) and (Value is TJSONNumber) then
    begin
      AMigrated := True;
      Exit(BoolJson(TJSONNumber(Value).AsInt <> 0));
    end;
    // hints.xmlDocFull (#654) war ein Wahrheitswert (in alten Dateien 0/1); hints.xmlDocExpand (#770) ist
    // eine Auswahl.
    if (AEntry.Name = 'XmlDocExpand') and ((Value is TJSONBool) or (Value is TJSONNumber)) then
    begin
      AMigrated := True;
      if ((Value is TJSONBool) and TJSONBool(Value).AsBoolean) or
        ((Value is TJSONNumber) and (TJSONNumber(Value).AsInt <> 0)) then
      begin
        Exit('"expanded"');
      end;
      Exit('"collapsed"');
    end;
    // issues.query (#765, #1280) war eine einzelne Abfrage; issues.queries (#1262) ist eine Liste, in die sie als
    // „Standard“ kommt.
    if (AEntry.Name = TAtlasSettingsQueryMigrations.SettingName) and (Value is TJSONString) then
    begin
      AMigrated := True;
      Exit(TAtlasSettingsQueryMigrations.WithLegacy('[]', TJSONString(Value).Value));
    end;
    Dummy := False;
    Mapped := MapStrings(Value, AFolders, True, Dummy);
    try
      Result := ValueText(Mapped);
    finally
      Mapped.Free;
    end;
  finally
    Value.Free;
  end;
end;

class function TAtlasSettingsTransfer.Preview(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; const AFile: TAtlasSettingsFile; AMode: TAtlasImportMode;
  const AAreas: TArray<string>; const AEnvironment: TAtlasSettingsEnvironment;
  const AProjectText, ATeamText: string): TAtlasImportPreview;
var
  Values: TStateValues;
  Folders: TUserFolders;
  Project, Team: TJSONObject;
  Seen: TArray<Boolean>;
  KeyIndex, Index: Integer;
  Item: TAtlasImportItem;
  Entry: TAtlasCatalogEntry;
  Migrated: Boolean;
  Area, Value, Covered: string;
begin
  Result := Default(TAtlasImportPreview);
  Result.Source := AFile;
  Result.Mode := AMode;
  Result.Newer := AFile.SchemaVersion > ACatalog.Version;
  // Bereiche: gewählt, sonst die der Datei, sonst alle.
  for Area in ACatalog.AreaIds do
  begin
    if Contains(AAreas, Area) or ((Length(AAreas) = 0) and
      ((Length(AFile.Areas) = 0) or Contains(AFile.Areas, Area))) then
    begin
      Result.Areas := Result.Areas + [Area];
    end;
  end;
  Folders := TUserFolders.From(AEnvironment);
  SetLength(Seen, ACatalog.Count);
  Project := TAtlasJsonText.Parse(AProjectText);
  Team := TAtlasJsonText.Parse(ATeamText);
  Values := TStateValues.Create(ACatalog, AState);
  try
    for KeyIndex := 0 to High(AFile.Keys) do
    begin
      Item := Default(TAtlasImportItem);
      Item.SourceKey := AFile.Keys[KeyIndex];
      Item.Key := Item.SourceKey;
      Item.NewJson := AFile.Values[KeyIndex];
      Migrated := False;
      Item.Entry := ACatalog.Resolve(Item.SourceKey, Migrated);
      if Item.Entry < 0 then
      begin
        if ACatalog.IsProjectPath(Item.SourceKey) then
        begin
          Item.Status := isSkipped;
        end
        else
        begin
          Item.Status := isUnknown;
        end;
        Result.Items := Result.Items + [Item];
        Continue;
      end;
      Entry := ACatalog[Item.Entry];
      if not Contains(Result.Areas, Entry.Area) then
      begin
        Continue;
      end;
      Seen[Item.Entry] := True;
      Item.Key := Entry.Key;
      Item.Area := Entry.Area;
      Item.Migrated := Migrated;
      Item.CurrentJson := Values.Get(Item.Entry);
      if not Entry.Transferable and not AFile.Backup then
      begin
        Item.Status := isSkipped;
      end
      else if TAtlasJsonValues.Same(Item.NewJson, TAtlasJsonText.Quote(SecretPlaceholder)) then
      begin
        Item.Status := isSecret;
      end
      else
      begin
        Item.NewJson := Migrate(Entry, Item.NewJson, Folders, Item.Migrated);
        if not ACatalog.ValidValue(Entry, Item.NewJson, Item.Issues) then
        begin
          Item.Status := isInvalid;
        end
        else if (Item.CurrentJson <> '') and TAtlasJsonValues.Same(Item.CurrentJson, Item.NewJson) then
        begin
          Item.Status := isSame;
        end
        else if (Item.CurrentJson = '') and (Entry.DefaultJson <> '') and
          TAtlasJsonValues.Same(Entry.DefaultJson, Item.NewJson) then
        begin
          Item.Status := isSame;
        end
        else
        begin
          Item.Status := isChange;
        end;
      end;
      Result.Items := Result.Items + [Item];
    end;
    // Ersetzen: was in den Bereichen fehlt, geht auf den Standard.
    if AMode = imReplace then
    begin
      for Index := 0 to ACatalog.Count - 1 do
      begin
        if not Seen[Index] and ACatalog[Index].Transferable and Contains(Result.Areas, ACatalog[Index].Area) and
          Modified(ACatalog, Values, Index) then
        begin
          Item := Default(TAtlasImportItem);
          Item.Entry := Index;
          Item.Key := ACatalog[Index].Key;
          Item.Area := ACatalog[Index].Area;
          Item.CurrentJson := Values.Get(Index);
          if ACatalog[Index].Source = asPlugin then
          begin
            Item.NewJson := DefaultJson(ACatalog, Index);
          end;
          Item.Status := isReset;
          Result.Items := Result.Items + [Item];
        end;
      end;
    end;
    // Projektwerte, die die Einstellung überdecken; Vorauswahl.
    for Index := 0 to High(Result.Items) do
    begin
      Item := Result.Items[Index];
      if Item.Entry >= 0 then
      begin
        Entry := ACatalog[Item.Entry];
        Covered := '';
        Value := ProjectValue(Project, Entry.ProjectPath);
        if Value <> '' then
        begin
          Covered := 'atlas.json: ' + Entry.ProjectPath + ' = ' + Value;
        end;
        Value := ProjectValue(Team, Entry.TeamPath);
        if Value <> '' then
        begin
          if Covered <> '' then
          begin
            Covered := Covered + '; ';
          end;
          Covered := Covered + '.atlas: ' + Entry.TeamPath + ' = ' + Value;
        end;
        Item.Covered := Covered;
      end;
      Item.Selected := Item.Selectable;
      Result.Items[Index] := Item;
    end;
  finally
    Values.Free;
    Team.Free;
    Project.Free;
  end;
end;

class function TAtlasSettingsTransfer.Apply(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
  const APreview: TAtlasImportPreview): TAtlasSettingsState;
var
  Values: TStateValues;
  Item: TAtlasImportItem;
begin
  Values := TStateValues.Create(ACatalog, AState);
  try
    for Item in APreview.Items do
    begin
      if Item.Selected and Item.Selectable and (Item.Entry >= 0) then
      begin
        if Item.Status = isReset then
        begin
          Values.Put(Item.Entry, '');
        end
        else
        begin
          Values.Put(Item.Entry, Item.NewJson);
        end;
      end;
    end;
    Result := Values.State;
  finally
    Values.Free;
  end;
end;

class function TAtlasSettingsTransfer.Validate(ACatalog: TAtlasSettingsCatalog; const AText: string;
  out AIssues: TArray<string>): Boolean;
var
  Source: TAtlasSettingsFile;
  Index, Entry: Integer;
  Migrated: Boolean;
  Issues: TArray<string>;
  Area: string;
begin
  AIssues := nil;
  Source := ParseFile(AText);
  if not Source.Valid then
  begin
    AIssues := AIssues + ['Datei: ' + Source.Error];
  end
  else
  begin
    if Source.FormatVersion <> FormatVersion then
    begin
      AIssues := AIssues + ['formatVersion: erwartet ' + IntToStr(FormatVersion)];
    end;
    if Source.SchemaVersion <> ACatalog.Version then
    begin
      AIssues := AIssues + ['schemaVersion: erwartet ' + IntToStr(ACatalog.Version)];
    end;
    if (Source.Mode <> '') and (Source.Mode <> 'merge') and (Source.Mode <> 'replace') then
    begin
      AIssues := AIssues + ['mode: merge oder replace'];
    end;
    for Area in Source.Areas do
    begin
      if not ACatalog.HasArea(Area) then
      begin
        AIssues := AIssues + ['areas: unbekannter Bereich ' + Area];
      end;
    end;
    for Index := 0 to High(Source.Keys) do
    begin
      Entry := ACatalog.Resolve(Source.Keys[Index], Migrated);
      if Entry < 0 then
      begin
        AIssues := AIssues + [Source.Keys[Index] + ': unbekannter Schlüssel'];
      end
      else if Migrated then
      begin
        AIssues := AIssues + [Source.Keys[Index] + ': veralteter Schlüssel, richtig ist ' + ACatalog[Entry].Key];
      end
      else if not ACatalog[Entry].Transferable then
      begin
        AIssues := AIssues + [Source.Keys[Index] + ': wird nicht übertragen'];
      end
      else if not ACatalog.ValidValue(ACatalog[Entry], Source.Values[Index], Issues) then
      begin
        AIssues := AIssues + Issues;
      end;
    end;
  end;
  Result := Length(AIssues) = 0;
end;

class function TAtlasSettingsTransfer.BackupFileName(ANow: TDateTime): string;
begin
  Result := BackupPrefix + FormatDateTime('yyyymmdd"-"hhnnss', ANow) + '.json';
end;

class function TAtlasSettingsTransfer.BackupsToDelete(const AFiles: TArray<string>; AKeep: Integer): TArray<string>;
var
  Backups: TList<string>;
  Name: string;
  Index: Integer;
begin
  Result := nil;
  Backups := TList<string>.Create;
  try
    for Name in AFiles do
    begin
      if SameText(Copy(Name, 1, Length(BackupPrefix)), BackupPrefix) and SameText(ExtractFileExt(Name), '.json') then
      begin
        Backups.Add(Name);
      end;
    end;
    // Der Name enthält Datum und Uhrzeit: alphabetisch = zeitlich.
    Backups.Sort(TComparer<string>.Construct(
      function(const ALeft, ARight: string): Integer
      begin
        Result := CompareText(ALeft, ARight);
      end));
    for Index := 0 to Backups.Count - 1 - AKeep do
    begin
      Result := Result + [Backups[Index]];
    end;
  finally
    Backups.Free;
  end;
end;

end.
