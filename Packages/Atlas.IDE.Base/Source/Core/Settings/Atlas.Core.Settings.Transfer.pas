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

  /// <summary>Wie importiert wird: Modus, Bereiche (leer = die der Datei, sonst alle), Umgebung für die
  /// Pfadmakros und atlas.json bzw. .atlas des aktiven Projekts ('' ohne).</summary>
  TAtlasImportOptions = record
    Mode: TAtlasImportMode;
    Areas: TArray<string>;
    Environment: TAtlasSettingsEnvironment;
    ProjectText: string;
    TeamText: string;
    /// <summary>Ohne Projekt.</summary>
    class function Create(AMode: TAtlasImportMode; const AAreas: TArray<string>;
      const AEnvironment: TAtlasSettingsEnvironment): TAtlasImportOptions; overload; static;
    class function Create(AMode: TAtlasImportMode; const AAreas: TArray<string>;
      const AEnvironment: TAtlasSettingsEnvironment; const AProjectText, ATeamText: string): TAtlasImportOptions;
      overload; static;
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
    /// <summary>Vorschau des Imports mit AOptions.</summary>
    class function Preview(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
      const AFile: TAtlasSettingsFile; const AOptions: TAtlasImportOptions): TAtlasImportPreview; static;
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
    procedure PutGlobal(const AEntry: TAtlasCatalogEntry; const AJson: string);
    procedure PutDefault(const AEntry: TAtlasCatalogEntry);
    procedure PutPlugin(const AEntry: TAtlasCatalogEntry; AValue: TJSONValue);
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

procedure TStateValues.PutGlobal(const AEntry: TAtlasCatalogEntry; const AJson: string);
begin
  if AJson = '' then
  begin
    FText := TAtlasJsonText.Remove(FText, AEntry.Key);
  end
  else
  begin
    FText := TAtlasJsonText.SetValue(FText, AEntry.Key, AJson);
  end;
  FreeAndNil(FRoot);
end;

procedure TStateValues.PutDefault(const AEntry: TAtlasCatalogEntry);
begin
  if AEntry.Kind in [akString, akJson] then
  begin
    FStore.WriteString(AEntry.Name, DefaultValues.ReadString(AEntry.Name, ''));
  end
  else
  begin
    FStore.WriteInteger(AEntry.Name, DefaultValues.ReadInteger(AEntry.Name, 0));
  end;
end;

procedure TStateValues.PutPlugin(const AEntry: TAtlasCatalogEntry; AValue: TJSONValue);
begin
  case AEntry.Kind of
    akBoolean:
      FStore.WriteInteger(AEntry.Name, Ord(IsTrue(AValue)));
    akInteger:
      if AValue is TJSONNumber then
      begin
        FStore.WriteInteger(AEntry.Name, TJSONNumber(AValue).AsInt);
      end;
    akJson:
      if (AValue is TJSONArray) or (AValue is TJSONObject) then
      begin
        FStore.WriteString(AEntry.Name, AValue.ToJSON);
      end;
  else
    if IsText(AValue) then
    begin
      FStore.WriteString(AEntry.Name, TJSONString(AValue).Value);
    end;
  end;
end;

procedure TStateValues.Put(AIndex: Integer; const AJson: string);
var
  mEntry: TAtlasCatalogEntry;
  mValue: TJSONValue;
begin
  mEntry := FCatalog[AIndex];
  if mEntry.Source = asGlobal then
  begin
    PutGlobal(mEntry, AJson);
  end
  // Plugin: '' = Standard.
  else if AJson = '' then
  begin
    PutDefault(mEntry);
  end
  else
  begin
    mValue := TAtlasJsonValues.Parse(AJson);
    try
      if mValue <> nil then
      begin
        PutPlugin(mEntry, mValue);
      end;
    finally
      mValue.Free;
    end;
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

{ TAtlasImportOptions }

class function TAtlasImportOptions.Create(AMode: TAtlasImportMode; const AAreas: TArray<string>;
  const AEnvironment: TAtlasSettingsEnvironment): TAtlasImportOptions;
begin
  Result := Create(AMode, AAreas, AEnvironment, '', '');
end;

class function TAtlasImportOptions.Create(AMode: TAtlasImportMode; const AAreas: TArray<string>;
  const AEnvironment: TAtlasSettingsEnvironment; const AProjectText, ATeamText: string): TAtlasImportOptions;
begin
  Result.Mode := AMode;
  Result.Areas := AAreas;
  Result.Environment := AEnvironment;
  Result.ProjectText := AProjectText;
  Result.TeamText := ATeamText;
end;

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

function ExportAreas(ACatalog: TAtlasSettingsCatalog; const AOptions: TAtlasExportOptions): TArray<string>;
var
  mArea: string;
begin
  Result := nil;
  for mArea in ACatalog.AreaIds do
  begin
    if (Length(AOptions.Areas) = 0) or Contains(AOptions.Areas, mArea) then
    begin
      Result := Result + [mArea];
    end;
  end;
end;

/// <summary>Wert für den Export: in der Sicherung jeder gesetzte, sonst nur geänderte.</summary>
function ExportCurrent(ACatalog: TAtlasSettingsCatalog; AValues: TStateValues; AIndex: Integer; ABackup: Boolean;
  out ACurrent: string): Boolean;
begin
  ACurrent := '';
  if not ABackup and not Modified(ACatalog, AValues, AIndex) then
  begin
    Exit(False);
  end;
  ACurrent := AValues.Get(AIndex);
  Result := ACurrent <> '';
end;

procedure AddOmission(var AResult: TAtlasExportResult; const AKey: string; AReason: TAtlasOmitReason);
var
  mOmission: TAtlasExportOmission;
begin
  mOmission.Key := AKey;
  mOmission.Reason := AReason;
  AResult.Omitted := AResult.Omitted + [mOmission];
end;

/// <summary>Zeile "key": wert der Exportdatei; False, wenn der Wert ausgelassen wird (in AResult vermerkt).
/// </summary>
function ExportLine(const AEntry: TAtlasCatalogEntry; AValue: TJSONValue; const AOptions: TAtlasExportOptions;
  const AFolders: TUserFolders; var AResult: TAtlasExportResult; out ALine: string): Boolean;
var
  mMapped: TJSONValue;
  mHasUser: Boolean;
begin
  ALine := '    ' + TAtlasJsonText.Quote(AEntry.Key) + ': ';
  if AOptions.Backup then
  begin
    ALine := ALine + ValueText(AValue);
    Exit(True);
  end;
  if HasSecret(AValue, LastSegment(AEntry.Key), AEntry.Secret) then
  begin
    Result := AOptions.Secrets <> smOmit;
    if Result then
    begin
      ALine := ALine + TAtlasJsonText.Quote(TAtlasSettingsTransfer.SecretPlaceholder);
      AResult.Placeholders := AResult.Placeholders + [AEntry.Key];
    end
    else
    begin
      AddOmission(AResult, AEntry.Key, orSecret);
    end;
    Exit;
  end;
  mHasUser := False;
  mMapped := MapStrings(AValue, AFolders, False, mHasUser);
  try
    Result := not mHasUser;
    if Result then
    begin
      ALine := ALine + ValueText(mMapped);
    end
    else
    begin
      AddOmission(AResult, AEntry.Key, orUserPath);
    end;
  finally
    mMapped.Free;
  end;
end;

/// <summary>Inhalt der Exportdatei aus Kopf und Zeilen.</summary>
function ExportText(ACatalog: TAtlasSettingsCatalog; const AAreas, ALines: TArray<string>; ABackup: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '{' + #10 +
    '  "format": ' + TAtlasJsonText.Quote(TAtlasSettingsTransfer.FormatName) + ',' + #10 +
    '  "formatVersion": ' + IntToStr(TAtlasSettingsTransfer.FormatVersion) + ',' + #10 +
    '  "schemaVersion": ' + IntToStr(ACatalog.Version) + ',' + #10 +
    '  "atlasVersion": ' + TAtlasJsonText.Quote(TAtlasPluginVersion.Version) + ',' + #10;
  if ABackup then
  begin
    Result := Result + '  "backup": true,' + #10;
  end;
  Result := Result + '  "areas": ' + JsonList(AAreas) + ',' + #10 + '  "settings": {';
  for mIndex := 0 to High(ALines) do
  begin
    if mIndex > 0 then
    begin
      Result := Result + ',';
    end;
    Result := Result + #10 + ALines[mIndex];
  end;
  if Length(ALines) > 0 then
  begin
    Result := Result + #10 + '  ';
  end;
  Result := Result + '}' + #10 + '}' + #10;
end;

class function TAtlasSettingsTransfer.ExportSettings(ACatalog: TAtlasSettingsCatalog;
  const AState: TAtlasSettingsState; const AOptions: TAtlasExportOptions;
  const AEnvironment: TAtlasSettingsEnvironment): TAtlasExportResult;
var
  mValues: TStateValues;
  mFolders: TUserFolders;
  mAreas, mLines: TArray<string>;
  mIndex: Integer;
  mCurrent, mLine: string;
  mValue: TJSONValue;
begin
  Result := Default(TAtlasExportResult);
  mFolders := TUserFolders.From(AEnvironment);
  mAreas := ExportAreas(ACatalog, AOptions);
  mLines := nil;
  mValues := TStateValues.Create(ACatalog, AState);
  try
    for mIndex := 0 to ACatalog.Count - 1 do
    begin
      if not Contains(mAreas, ACatalog[mIndex].Area) or
        not ExportCurrent(ACatalog, mValues, mIndex, AOptions.Backup, mCurrent) then
      begin
        Continue;
      end;
      mValue := TAtlasJsonValues.Parse(mCurrent);
      try
        if (mValue <> nil) and ExportLine(ACatalog[mIndex], mValue, AOptions, mFolders, Result, mLine) then
        begin
          mLines := mLines + [mLine];
        end;
      finally
        mValue.Free;
      end;
    end;
  finally
    mValues.Free;
  end;
  Result.Count := Length(mLines);
  Result.Text := ExportText(ACatalog, mAreas, mLines, AOptions.Backup);
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

procedure AddSettingPairs(ASettings: TJSONObject; var AFile: TAtlasSettingsFile);
var
  mPair: TJSONPair;
begin
  for mPair in ASettings do
  begin
    AFile.Keys := AFile.Keys + [mPair.JsonString.Value];
    AFile.Values := AFile.Values + [ValueText(mPair.JsonValue)];
  end;
end;

function TextItems(AValue: TJSONValue): TArray<string>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if IsText(mItem) then
    begin
      Result := Result + [TJSONString(mItem).Value];
    end;
  end;
end;

procedure ReadFileHeader(ARoot: TJSONObject; var AFile: TAtlasSettingsFile);
begin
  AFile.FormatVersion := IntegerField(ARoot, 'formatVersion');
  AFile.SchemaVersion := IntegerField(ARoot, 'schemaVersion');
  AFile.AtlasVersion := StringField(ARoot, 'atlasVersion');
  AFile.Name := StringField(ARoot, 'name');
  AFile.NameEn := StringField(ARoot, 'nameEn');
  AFile.Description := StringField(ARoot, 'description');
  AFile.DescriptionEn := StringField(ARoot, 'descriptionEn');
  AFile.Mode := StringField(ARoot, 'mode');
  AFile.Backup := IsTrue(ARoot.GetValue('backup'));
  AFile.Areas := TextItems(ARoot.GetValue('areas'));
end;

/// <summary>Grund, warum ARoot keine Exportdatei ist; '' wenn sie eine ist.</summary>
function FileError(ARoot: TJSONObject; ASettings: TJSONValue): string;
begin
  Result := '';
  if ASettings = nil then
  begin
    // Ältere Datei: flache Liste von Registry-Namen (Werte 0/1, Zahlen, Text); mit "format" fehlt "settings".
    if ARoot.GetValue('format') <> nil then
    begin
      Result := 'ohne "settings"';
    end;
  end
  else if not (ASettings is TJSONObject) then
  begin
    Result := '"settings" ist kein Objekt';
  end
  else if (ARoot.GetValue('format') <> nil) and (StringField(ARoot, 'format') <> TAtlasSettingsTransfer.FormatName) then
  begin
    Result := 'anderes Format: ' + StringField(ARoot, 'format');
  end;
end;

class function TAtlasSettingsTransfer.ParseFile(const AText: string): TAtlasSettingsFile;
var
  mRoot: TJSONObject;
  mSettings: TJSONValue;
begin
  Result := Default(TAtlasSettingsFile);
  mRoot := TAtlasJsonText.Parse(AText);
  if mRoot = nil then
  begin
    Result.Error := 'kein JSON-Objekt';
    Exit;
  end;
  try
    mSettings := mRoot.GetValue('settings');
    Result.Error := FileError(mRoot, mSettings);
    if Result.Error <> '' then
    begin
      Exit;
    end;
    if mSettings = nil then
    begin
      AddSettingPairs(mRoot, Result);
    end
    else
    begin
      ReadFileHeader(mRoot, Result);
      AddSettingPairs(TJSONObject(mSettings), Result);
    end;
    Result.Valid := True;
  finally
    mRoot.Free;
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

/// <summary>Umrechnung älterer Werte; False, wenn AValue keine braucht.</summary>
function MigratedValue(const AEntry: TAtlasCatalogEntry; AValue: TJSONValue; out AJson: string): Boolean;
begin
  Result := True;
  if (AEntry.Kind = akBoolean) and (AValue is TJSONNumber) then
  begin
    AJson := BoolJson(TJSONNumber(AValue).AsInt <> 0);
  end
  // hints.xmlDocFull (#654) war ein Wahrheitswert (in alten Dateien 0/1); hints.xmlDocExpand (#770) ist
  // eine Auswahl.
  else if (AEntry.Name = 'XmlDocExpand') and ((AValue is TJSONBool) or (AValue is TJSONNumber)) then
  begin
    AJson := '"collapsed"';
    if IsTrue(AValue) or ((AValue is TJSONNumber) and (TJSONNumber(AValue).AsInt <> 0)) then
    begin
      AJson := '"expanded"';
    end;
  end
  // issues.query (#765, #1280) war eine einzelne Abfrage; issues.queries (#1262) ist eine Liste, in die sie als
  // „Standard“ kommt.
  else if (AEntry.Name = TAtlasSettingsQueryMigrations.SettingName) and (AValue is TJSONString) then
  begin
    AJson := TAtlasSettingsQueryMigrations.WithLegacy('[]', TJSONString(AValue).Value);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Wert für AEntry umrechnen: 0/1 für Wahrheitswerte, Pfadmakros ausschreiben.</summary>
function Migrate(const AEntry: TAtlasCatalogEntry; const AJson: string; const AFolders: TUserFolders;
  var AMigrated: Boolean): string;
var
  mValue, mMapped: TJSONValue;
  mUnused: Boolean;
begin
  Result := AJson;
  mValue := TAtlasJsonValues.Parse(AJson);
  if mValue = nil then
  begin
    Exit;
  end;
  try
    if MigratedValue(AEntry, mValue, Result) then
    begin
      AMigrated := True;
      Exit;
    end;
    mUnused := False;
    mMapped := MapStrings(mValue, AFolders, True, mUnused);
    try
      Result := ValueText(mMapped);
    finally
      mMapped.Free;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Bereiche der Vorschau: gewählt, sonst die der Datei, sonst alle.</summary>
function PreviewAreas(ACatalog: TAtlasSettingsCatalog; const AFile: TAtlasSettingsFile;
  const AAreas: TArray<string>): TArray<string>;
var
  mArea: string;
begin
  Result := nil;
  for mArea in ACatalog.AreaIds do
  begin
    if Contains(AAreas, mArea) or ((Length(AAreas) = 0) and
      ((Length(AFile.Areas) = 0) or Contains(AFile.Areas, mArea))) then
    begin
      Result := Result + [mArea];
    end;
  end;
end;

/// <summary>Status eines bekannten, übertragbaren Werts nach der Migration.</summary>
function ValueStatus(ACatalog: TAtlasSettingsCatalog; const AEntry: TAtlasCatalogEntry;
  var AItem: TAtlasImportItem): TAtlasImportStatus;
begin
  if not ACatalog.ValidValue(AEntry, AItem.NewJson, AItem.Issues) then
  begin
    Result := isInvalid;
  end
  else if (AItem.CurrentJson <> '') and TAtlasJsonValues.Same(AItem.CurrentJson, AItem.NewJson) then
  begin
    Result := isSame;
  end
  else if (AItem.CurrentJson = '') and (AEntry.DefaultJson <> '') and
    TAtlasJsonValues.Same(AEntry.DefaultJson, AItem.NewJson) then
  begin
    Result := isSame;
  end
  else
  begin
    Result := isChange;
  end;
end;

/// <summary>Status eines Werts im Katalog: übersprungen, Platzhalter oder nach Migration und Prüfung.</summary>
procedure ResolveItem(ACatalog: TAtlasSettingsCatalog; const AEntry: TAtlasCatalogEntry; ABackup: Boolean;
  const AFolders: TUserFolders; var AItem: TAtlasImportItem);
begin
  if not AEntry.Transferable and not ABackup then
  begin
    AItem.Status := isSkipped;
  end
  else if TAtlasJsonValues.Same(AItem.NewJson, TAtlasJsonText.Quote(TAtlasSettingsTransfer.SecretPlaceholder)) then
  begin
    AItem.Status := isSecret;
  end
  else
  begin
    AItem.NewJson := Migrate(AEntry, AItem.NewJson, AFolders, AItem.Migrated);
    AItem.Status := ValueStatus(ACatalog, AEntry, AItem);
  end;
end;

type
  /// <summary>Was die Vorschau für jeden Schlüssel braucht.</summary>
  TPreviewContext = record
    Catalog: TAtlasSettingsCatalog;
    Values: TStateValues;
    Areas: TArray<string>;
    Folders: TUserFolders;
  end;

/// <summary>Eintrag zu Schlüssel AKeyIndex der Datei; False, wenn er außerhalb der Bereiche liegt. AItem.Entry:
/// Index im Katalog bzw. -1.</summary>
function FileItem(const AContext: TPreviewContext; const AFile: TAtlasSettingsFile; AKeyIndex: Integer;
  out AItem: TAtlasImportItem): Boolean;
var
  mEntry: TAtlasCatalogEntry;
  mMigrated: Boolean;
begin
  AItem := Default(TAtlasImportItem);
  AItem.SourceKey := AFile.Keys[AKeyIndex];
  AItem.Key := AItem.SourceKey;
  AItem.NewJson := AFile.Values[AKeyIndex];
  mMigrated := False;
  AItem.Entry := AContext.Catalog.Resolve(AItem.SourceKey, mMigrated);
  if AItem.Entry < 0 then
  begin
    AItem.Status := isUnknown;
    if AContext.Catalog.IsProjectPath(AItem.SourceKey) then
    begin
      AItem.Status := isSkipped;
    end;
    Exit(True);
  end;
  mEntry := AContext.Catalog[AItem.Entry];
  Result := Contains(AContext.Areas, mEntry.Area);
  if not Result then
  begin
    Exit;
  end;
  AItem.Key := mEntry.Key;
  AItem.Area := mEntry.Area;
  AItem.Migrated := mMigrated;
  AItem.CurrentJson := AContext.Values.Get(AItem.Entry);
  ResolveItem(AContext.Catalog, mEntry, AFile.Backup, AContext.Folders, AItem);
end;

/// <summary>Ersetzen: was in den Bereichen fehlt und geändert ist, geht auf den Standard.</summary>
function ResetItems(ACatalog: TAtlasSettingsCatalog; AValues: TStateValues; const ASeen: TArray<Boolean>;
  const AAreas: TArray<string>): TArray<TAtlasImportItem>;
var
  mIndex: Integer;
  mItem: TAtlasImportItem;
begin
  Result := nil;
  for mIndex := 0 to ACatalog.Count - 1 do
  begin
    if ASeen[mIndex] or not ACatalog[mIndex].Transferable or not Contains(AAreas, ACatalog[mIndex].Area) or
      not Modified(ACatalog, AValues, mIndex) then
    begin
      Continue;
    end;
    mItem := Default(TAtlasImportItem);
    mItem.Entry := mIndex;
    mItem.Key := ACatalog[mIndex].Key;
    mItem.Area := ACatalog[mIndex].Area;
    mItem.CurrentJson := AValues.Get(mIndex);
    if ACatalog[mIndex].Source = asPlugin then
    begin
      mItem.NewJson := TAtlasSettingsTransfer.DefaultJson(ACatalog, mIndex);
    end;
    mItem.Status := isReset;
    Result := Result + [mItem];
  end;
end;

/// <summary>Projektwerte, die die Einstellung überdecken: "atlas.json: pfad = wert; .atlas: …".</summary>
function CoveredText(const AEntry: TAtlasCatalogEntry; AProject, ATeam: TJSONObject): string;
var
  mValue: string;
begin
  Result := '';
  mValue := ProjectValue(AProject, AEntry.ProjectPath);
  if mValue <> '' then
  begin
    Result := 'atlas.json: ' + AEntry.ProjectPath + ' = ' + mValue;
  end;
  mValue := ProjectValue(ATeam, AEntry.TeamPath);
  if mValue = '' then
  begin
    Exit;
  end;
  if Result <> '' then
  begin
    Result := Result + '; ';
  end;
  Result := Result + '.atlas: ' + AEntry.TeamPath + ' = ' + mValue;
end;

/// <summary>Überdeckung aus atlas.json und .atlas und die Vorauswahl.</summary>
procedure MarkCovered(ACatalog: TAtlasSettingsCatalog; const AProjectText, ATeamText: string;
  var AItems: TArray<TAtlasImportItem>);
var
  mProject, mTeam: TJSONObject;
  mIndex: Integer;
begin
  mProject := TAtlasJsonText.Parse(AProjectText);
  mTeam := TAtlasJsonText.Parse(ATeamText);
  try
    for mIndex := 0 to High(AItems) do
    begin
      if AItems[mIndex].Entry >= 0 then
      begin
        AItems[mIndex].Covered := CoveredText(ACatalog[AItems[mIndex].Entry], mProject, mTeam);
      end;
      AItems[mIndex].Selected := AItems[mIndex].Selectable;
    end;
  finally
    mTeam.Free;
    mProject.Free;
  end;
end;

class function TAtlasSettingsTransfer.Preview(ACatalog: TAtlasSettingsCatalog; const AState: TAtlasSettingsState;
  const AFile: TAtlasSettingsFile; const AOptions: TAtlasImportOptions): TAtlasImportPreview;
var
  mContext: TPreviewContext;
  mSeen: TArray<Boolean>;
  mKeyIndex: Integer;
  mItem: TAtlasImportItem;
begin
  Result := Default(TAtlasImportPreview);
  Result.Source := AFile;
  Result.Mode := AOptions.Mode;
  Result.Newer := AFile.SchemaVersion > ACatalog.Version;
  Result.Areas := PreviewAreas(ACatalog, AFile, AOptions.Areas);
  mContext.Catalog := ACatalog;
  mContext.Areas := Result.Areas;
  mContext.Folders := TUserFolders.From(AOptions.Environment);
  SetLength(mSeen, ACatalog.Count);
  mContext.Values := TStateValues.Create(ACatalog, AState);
  try
    for mKeyIndex := 0 to High(AFile.Keys) do
    begin
      if FileItem(mContext, AFile, mKeyIndex, mItem) then
      begin
        if mItem.Entry >= 0 then
        begin
          mSeen[mItem.Entry] := True;
        end;
        Result.Items := Result.Items + [mItem];
      end;
    end;
    if AOptions.Mode = imReplace then
    begin
      Result.Items := Result.Items + ResetItems(ACatalog, mContext.Values, mSeen, Result.Areas);
    end;
  finally
    mContext.Values.Free;
  end;
  MarkCovered(ACatalog, AOptions.ProjectText, AOptions.TeamText, Result.Items);
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

/// <summary>Kopf der Datei: Versionen, Modus und Bereiche.</summary>
function HeaderIssues(ACatalog: TAtlasSettingsCatalog; const ASource: TAtlasSettingsFile): TArray<string>;
var
  mArea: string;
begin
  Result := nil;
  if ASource.FormatVersion <> TAtlasSettingsTransfer.FormatVersion then
  begin
    Result := Result + ['formatVersion: erwartet ' + IntToStr(TAtlasSettingsTransfer.FormatVersion)];
  end;
  if ASource.SchemaVersion <> ACatalog.Version then
  begin
    Result := Result + ['schemaVersion: erwartet ' + IntToStr(ACatalog.Version)];
  end;
  if (ASource.Mode <> '') and (ASource.Mode <> 'merge') and (ASource.Mode <> 'replace') then
  begin
    Result := Result + ['mode: merge oder replace'];
  end;
  for mArea in ASource.Areas do
  begin
    if not ACatalog.HasArea(mArea) then
    begin
      Result := Result + ['areas: unbekannter Bereich ' + mArea];
    end;
  end;
end;

/// <summary>Ein Schlüssel der Datei: bekannt, aktuell, übertragbar und mit gültigem Wert.</summary>
function KeyIssues(ACatalog: TAtlasSettingsCatalog; const AKey, AValue: string): TArray<string>;
var
  mEntry: Integer;
  mMigrated: Boolean;
begin
  Result := nil;
  mEntry := ACatalog.Resolve(AKey, mMigrated);
  if mEntry < 0 then
  begin
    Result := [AKey + ': unbekannter Schlüssel'];
  end
  else if mMigrated then
  begin
    Result := [AKey + ': veralteter Schlüssel, richtig ist ' + ACatalog[mEntry].Key];
  end
  else if not ACatalog[mEntry].Transferable then
  begin
    Result := [AKey + ': wird nicht übertragen'];
  end
  // Ungültig: die Meldungen der Schemaprüfung.
  else if ACatalog.ValidValue(ACatalog[mEntry], AValue, Result) then
  begin
    Result := nil;
  end;
end;

class function TAtlasSettingsTransfer.Validate(ACatalog: TAtlasSettingsCatalog; const AText: string;
  out AIssues: TArray<string>): Boolean;
var
  mSource: TAtlasSettingsFile;
  mIndex: Integer;
begin
  mSource := ParseFile(AText);
  if not mSource.Valid then
  begin
    AIssues := ['Datei: ' + mSource.Error];
  end
  else
  begin
    AIssues := HeaderIssues(ACatalog, mSource);
    for mIndex := 0 to High(mSource.Keys) do
    begin
      AIssues := AIssues + KeyIssues(ACatalog, mSource.Keys[mIndex], mSource.Values[mIndex]);
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
