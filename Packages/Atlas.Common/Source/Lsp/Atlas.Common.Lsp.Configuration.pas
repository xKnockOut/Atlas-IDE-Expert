unit Atlas.Common.Lsp.Configuration;

// Konfigurationsdatei atlas.json im Arbeitsbereich.
//
// - LoadWorkspace liest die Datei aus dem Wurzelordner (nach initialized).
//   Fehlt sie, gilt die frühere delphi-lsp.json (#403).
// - Ist eine atlas.json im Editor geöffnet, werden ihre Fehler als
//   publishDiagnostics gemeldet, schon beim Tippen.
// - Ändert sich die Datei des Arbeitsbereichs im Editor, gelten die neuen
//   Einstellungen sofort; nach dem Schließen gilt wieder der Stand auf der
//   Platte. Änderungen außerhalb des Editors meldet FileChanged (Dateibeobachter
//   des Servers bzw. didChangeWatchedFiles, #227).
// - Jeder Schlüssel hat genau einen Ort (TConfigurationScopes): atlas.json
//   gilt nur für Projekt-Schlüssel, die globale Benutzerdatei
//   (%APPDATA%\Atlas\settings.json, #227, über SetGlobalSettings) nur für
//   globale. Ein Schlüssel am falschen Ort wirkt nicht und wird in atlas.json
//   als Warnung gemeldet.
// - Einstellungen aus dem Editor kommen über workspace/didChangeConfiguration
//   und initializationOptions (Abschnitt "atlas") und zählen wie global; das
//   IDE-Plugin nutzt diesen Weg nicht mehr. Reihenfolge: global < Editor <
//   atlas.json (TConfigurationScopes.Effective).
// - Meldungen, die den Index brauchen (unbekannte Klasse oder Property einer
//   Eigenschaftsregel, #309), liefert ExtraIssues; nach dem Indexaufbau sendet
//   Revalidate die Meldungen der Datei neu.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract;

type
  /// <summary>Liest eine Datei; False, wenn sie nicht existiert.</summary>
  TConfigurationFileReader = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>Weitere Meldungen zu den Einstellungen einer atlas.json, z. B. über den Index (#309).</summary>
  TConfigurationExtraIssues = reference to function(const ASettings: TServerSettings): TArray<TConfigurationIssue>;

  /// <summary>Konfigurationsdateien eines Arbeitsbereichs.</summary>
  TConfigurationFiles = record
    /// <summary>Gelesene Datei: atlas.json oder die frühere; '' ohne.</summary>
    Read: string;
    /// <summary>atlas.json und die frühere Datei, auch wenn es sie nicht gibt; für den Dateibeobachter (#227).
    /// </summary>
    Primary: string;
    Legacy: string;
  end;

  /// <summary>Texte, aus denen die Einstellungen entstehen (unterste Ebene zuerst); nur im Thread der
  /// Nachrichtenschleife.</summary>
  TConfigurationTexts = record
    /// <summary>Globale Benutzerdatei (#227).</summary>
    Global: string;
    /// <summary>Abschnitt der Editor-Einstellungen.</summary>
    Editor: string;
    /// <summary>atlas.json des Arbeitsbereichs.</summary>
    Workspace: string;
  end;

  TLspConfiguration = class
  public const
    DidChangeConfigurationMethod = 'workspace/didChangeConfiguration';
    /// <summary>Abschnitt der Editor-Einstellungen, z. B. atlas.project in VS Code.</summary>
    EditorSection = 'atlas';
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FReadFile: TConfigurationFileReader;
    FLock: TObject;
    FSettings: TServerSettings;
    FRootPath: string;
    FConfigRoot: string;
    FFiles: TConfigurationFiles;
    FOnChanged: TConfigurationChangedEvent;
    FExtraIssues: TConfigurationExtraIssues;
    // Nur im Thread der Nachrichtenschleife benutzt.
    FTexts: TConfigurationTexts;
    procedure Recompute;
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure Apply(const ASettings: TServerSettings);
    procedure Publish(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>);
    procedure LoadFromDisk;
    /// <summary>Meldungen zu atlas.json: Parser, Schlüssel, die nicht ins Projekt gehören, und ExtraIssues.</summary>
    function FileIssues(const AText: string): TArray<TConfigurationIssue>;
    function IsWorkspaceFile(const AUri: string): Boolean;
    function GetSettings: TServerSettings;
  public
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const AReadFile: TConfigurationFileReader);
    destructor Destroy; override;
    /// <summary>Meldet sich am Dokumentspeicher und, falls angegeben, für Editor-Einstellungen am Dispatcher an.
    /// Bei mehreren Arbeitsbereichsordnern verteilt die Komposition die Ereignisse selbst
    /// (DocumentEvent, SetEditorSettings) und ruft Attach nicht auf.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher); overload;
    /// <summary>Wie oben ohne Dispatcher (ADispatcher = nil).</summary>
    procedure Attach; overload;
    /// <summary>Verarbeitet ein Dokumentereignis wie nach Attach.</summary>
    procedure DocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    /// <summary>Übernimmt Editor-Einstellungen (JSON des Abschnitts, '' = keine).</summary>
    procedure SetEditorSettings(const AText: string);
    /// <summary>Übernimmt die globale Benutzerdatei (#227, Text im Format von atlas.json, '' = keine) als
    /// unterste Ebene.</summary>
    procedure SetGlobalSettings(const AText: string);
    /// <summary>Eine Datei hat sich außerhalb des Editors geändert: Ist es die Konfigurationsdatei dieses
    /// Arbeitsbereichs und nicht im Editor geöffnet, wird sie neu gelesen (True).</summary>
    function FileChanged(const AFileName: string): Boolean;
    /// <summary>Sendet die Meldungen der gelesenen Datei neu, etwa wenn der Index fertig ist (#309). Nur im
    /// Thread der Nachrichtenschleife.</summary>
    procedure Revalidate;
    /// <summary>Liest atlas.json aus ARootPath; ohne Datei gelten die Vorgaben.</summary>
    procedure LoadWorkspace(const ARootPath: string); overload;
    /// <summary>Wie LoadWorkspace(ARootPath), setzt vorher die globale Datei AGlobalText ohne eigene
    /// Neuberechnung; OnChanged kommt so nur einmal (MCP-Modus, D-08).</summary>
    procedure LoadWorkspace(const ARootPath, AGlobalText: string); overload;
    /// <summary>Wurzelordner aus den initialize-Parametern (rootUri, workspaceFolders, rootPath); sonst ''.</summary>
    class function RootPathFromInitialize(const AParams: TJSONObject): string; static;
    /// <summary>Abschnitt atlas aus den Parametern von didChangeConfiguration als JSON; sonst ''.</summary>
    class function EditorSettingsFromParams(const AParams: TJSONValue): string; static;
    /// <summary>Diagnostics zu den Fehlern; der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const AUri: string; AVersion: Integer;
      const AIssues: TArray<TConfigurationIssue>): TJSONObject; static;
    /// <summary>Aktuelle Einstellungen (Kopie, threadsicher).</summary>
    property Settings: TServerSettings read GetSettings;
    property RootPath: string read FRootPath;
    /// <summary>Ordner der atlas.json, sonst die Wurzel: Basis der Pfade aus "exclude". Projekte einer Gruppe haben
    /// ihren Ordner als Wurzel, die Datei liegt oft darüber.</summary>
    property ConfigRoot: string read FConfigRoot;
    /// <summary>Gelesene Datei sowie atlas.json und die frühere des Arbeitsbereichs; für den Fehlerbericht (#108)
    /// und den Dateibeobachter (#227).</summary>
    property Files: TConfigurationFiles read FFiles;
    /// <summary>Texte, aus denen Settings entsteht; nur im Thread der Nachrichtenschleife lesen.</summary>
    property Texts: TConfigurationTexts read FTexts;
    /// <summary>Weitere Meldungen in atlas.json; ohne Zuweisung keine.</summary>
    property ExtraIssues: TConfigurationExtraIssues read FExtraIssues write FExtraIssues;
    /// <summary>Wird nach jeder Übernahme neuer Einstellungen aufgerufen.</summary>
    property OnChanged: TConfigurationChangedEvent read FOnChanged write FOnChanged;
  end;

  /// <summary>Sprache des Clients aus den initialize-Parametern (#1458).</summary>
  TLspClientLocale = record
  public
    /// <summary>initializationOptions.locale (IDE-Plugin), sonst locale (LSP 3.16); '' ohne Angabe. Gewählt wird
    /// mit TAtlasLocale.Resolve.</summary>
    class function FromInitialize(const AParams: TJSONValue): string; static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes;

const
  DiagnosticSource = 'Atlas';

function IsConfigurationUri(const AUri: string): Boolean;
var
  Path: string;
begin
  Path := StringReplace(TDocumentUris.ToPath(AUri), '\', '/', [rfReplaceAll]);
  Result := IsConfigurationFileName(Copy(Path, LastDelimiter('/', Path) + 1, MaxInt));
end;

{ TLspConfiguration }

constructor TLspConfiguration.Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
  const AReadFile: TConfigurationFileReader);
begin
  inherited Create;
  FStore := AStore;
  FTransport := ATransport;
  FReadFile := AReadFile;
  FLock := TObject.Create;
  FSettings := TServerSettings.Default;
end;

destructor TLspConfiguration.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TLspConfiguration.Attach;
begin
  Attach(nil);
end;

procedure TLspConfiguration.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FStore.Subscribe(HandleDocumentEvent);
  if ADispatcher <> nil then
  begin
    ADispatcher.RegisterNotification(DidChangeConfigurationMethod, HandleDidChangeConfiguration);
  end;
end;

procedure TLspConfiguration.Recompute;
var
  Ignored: TArray<TConfigurationIssue>;
begin
  // Die Meldungen zur Datei sind schon veröffentlicht.
  Apply(TConfigurationParser.Parse(TConfigurationScopes.Effective(FTexts.Global, FTexts.Editor, FTexts.Workspace), Ignored));
end;

function TLspConfiguration.FileIssues(const AText: string): TArray<TConfigurationIssue>;
var
  Misplaced: TArray<TConfigurationIssue>;
  mSettings: TServerSettings;
begin
  mSettings := TConfigurationParser.Parse(AText, Result);
  TConfigurationScopes.Filter(AText, TConfigurationScope.Project, Misplaced);
  Result := Result + Misplaced;
  if Assigned(FExtraIssues) then
  begin
    Result := Result + FExtraIssues(mSettings);
  end;
end;

procedure TLspConfiguration.Revalidate;
var
  Uri: string;
  Document: ITextDocument;
begin
  if FFiles.Read = '' then
  begin
    Exit;
  end;
  Uri := TDocumentUris.FromPath(FFiles.Read);
  if (FStore <> nil) and FStore.TryGet(Uri, Document) then
  begin
    Publish(Uri, Document.Version, FileIssues(Document.Text));
  end
  else if FTexts.Workspace <> '' then
  begin
    Publish(Uri, -1, FileIssues(FTexts.Workspace));
  end;
end;

procedure TLspConfiguration.HandleDidChangeConfiguration(const AParams: TJSONValue);
begin
  SetEditorSettings(EditorSettingsFromParams(AParams));
end;

procedure TLspConfiguration.SetEditorSettings(const AText: string);
begin
  if AText = FTexts.Editor then
  begin
    Exit;
  end;
  FTexts.Editor := AText;
  Recompute;
end;

procedure TLspConfiguration.SetGlobalSettings(const AText: string);
begin
  if AText = FTexts.Global then
  begin
    Exit;
  end;
  FTexts.Global := AText;
  Recompute;
end;

function TLspConfiguration.FileChanged(const AFileName: string): Boolean;
var
  Document: ITextDocument;
begin
  Result := (AFileName <> '') and (SameText(AFileName, FFiles.Primary) or SameText(AFileName, FFiles.Legacy));
  if not Result then
  begin
    Exit;
  end;
  // Im Editor geöffnet: Dort gilt der Text des Editors, bis er schließt.
  if (FFiles.Read <> '') and FStore.TryGet(TDocumentUris.FromPath(FFiles.Read), Document) then
  begin
    Exit(False);
  end;
  LoadFromDisk;
end;

procedure TLspConfiguration.DocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
begin
  HandleDocumentEvent(AKind, ADocument);
end;

class function TLspConfiguration.EditorSettingsFromParams(const AParams: TJSONValue): string;
var
  Section: TJSONValue;
begin
  Result := '';
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  Section := TJSONObject(AParams).FindValue('settings.' + EditorSection);
  if Section is TJSONObject then
  begin
    Result := Section.ToJSON;
  end;
end;

{ TLspClientLocale }

class function TLspClientLocale.FromInitialize(const AParams: TJSONValue): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mValue := TJSONObject(AParams).FindValue('initializationOptions.locale');
  if (mValue is TJSONString) and (Trim(TJSONString(mValue).Value) <> '') then
  begin
    Exit(Trim(TJSONString(mValue).Value));
  end;
  mValue := TJSONObject(AParams).GetValue('locale');
  if mValue is TJSONString then
  begin
    Result := Trim(TJSONString(mValue).Value);
  end;
end;

function TLspConfiguration.GetSettings: TServerSettings;
begin
  TMonitor.Enter(FLock);
  try
    Result := FSettings;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TLspConfiguration.Apply(const ASettings: TServerSettings);
begin
  TMonitor.Enter(FLock);
  try
    FSettings := ASettings;
  finally
    TMonitor.Exit(FLock);
  end;
  if Assigned(FOnChanged) then
  begin
    FOnChanged(ASettings);
  end;
end;

function TLspConfiguration.IsWorkspaceFile(const AUri: string): Boolean;
begin
  Result := (FFiles.Read <> '') and SameText(TDocumentUris.ToPath(AUri), FFiles.Read);
end;

class function TLspConfiguration.BuildParams(const AUri: string; AVersion: Integer;
  const AIssues: TArray<TConfigurationIssue>): TJSONObject;
var
  Items: TJSONArray;
  Item: TJSONObject;
  Issue: TConfigurationIssue;
begin
  Items := TJSONArray.Create;
  for Issue in AIssues do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('range', TLspPositions.RangeToJson(Issue.Range));
    if Issue.IsError then
    begin
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Error));
    end
    else
    begin
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Warning));
    end;
    Item.AddPair('source', DiagnosticSource);
    Item.AddPair('message', Issue.Message);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  if AVersion >= 0 then
  begin
    Result.AddPair('version', TJSONNumber.Create(AVersion));
  end;
  Result.AddPair('diagnostics', Items);
end;

procedure TLspConfiguration.Publish(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>);
var
  Notification: TJSONObject;
begin
  Notification := TJsonRpcMessages.Notification(TLspTextDocumentMethod.PublishDiagnostics,
    BuildParams(AUri, AVersion, AIssues));
  try
    FTransport.WriteMessage(Notification);
  finally
    Notification.Free;
  end;
end;

procedure TLspConfiguration.LoadFromDisk;
var
  Text: string;
  Issues: TArray<TConfigurationIssue>;
  Found: Boolean;
begin
  FFiles.Read := FFiles.Primary;
  Found := (FFiles.Read <> '') and FReadFile(FFiles.Read, Text);
  if not Found and (FFiles.Legacy <> '') and FReadFile(FFiles.Legacy, Text) then
  begin
    FFiles.Read := FFiles.Legacy;
    Found := True;
  end;
  if Found then
  begin
    Issues := FileIssues(Text);
    Publish(TDocumentUris.FromPath(FFiles.Read), -1, Issues);
    FTexts.Workspace := Text;
  end
  else
  begin
    FTexts.Workspace := '';
  end;
  Recompute;
end;

procedure TLspConfiguration.LoadWorkspace(const ARootPath, AGlobalText: string);
begin
  FTexts.Global := AGlobalText;
  LoadWorkspace(ARootPath);
end;

/// <summary>ARootPath mit Trennzeichen am Ende, \ oder / wie im Pfad.</summary>
function DirOf(const ARootPath: string): string;
var
  mSeparator: string;
begin
  mSeparator := '/';
  if Pos('\', ARootPath) > 0 then
  begin
    mSeparator := '\';
  end;
  Result := ARootPath;
  if ARootPath[Length(ARootPath)] <> mSeparator then
  begin
    Result := ARootPath + mSeparator;
  end;
end;

/// <summary>Gibt es in ADir atlas.json oder die frühere Datei?</summary>
function HasConfiguration(const AReadFile: TConfigurationFileReader; const ADir: string): Boolean;
var
  mText: string;
begin
  Result := AReadFile(ADir + ConfigurationFileName, mText) or AReadFile(ADir + LegacyConfigurationFileName, mText);
end;

/// <summary>Ordner mit atlas.json ab ADir nach oben, bis zum Stamm des Repositorys (.git/.svn) bzw. des Laufwerks;
/// '' ohne Fund.</summary>
function ConfigurationDir(const AReadFile: TConfigurationFileReader; const ADir: string): string;
var
  mParent: string;
begin
  Result := ADir;
  while not HasConfiguration(AReadFile, Result) do
  begin
    mParent := ExtractFilePath(ExcludeTrailingPathDelimiter(Result));
    if DirectoryExists(Result + '.git') or DirectoryExists(Result + '.svn') or FileExists(Result + '.git') or
      (mParent = '') or SameText(mParent, Result) then
    begin
      Exit('');
    end;
    Result := mParent;
  end;
end;

procedure TLspConfiguration.LoadWorkspace(const ARootPath: string);
var
  mDir, mFound: string;
begin
  FRootPath := ARootPath;
  FConfigRoot := ARootPath;
  FFiles.Primary := '';
  FFiles.Legacy := '';
  if ARootPath <> '' then
  begin
    // Projekte einer Gruppe liegen oft in Unterordnern (Packages\X\X.dproj), atlas.json im Stamm: nach oben
    // suchen. Ohne Fund gilt die Wurzel selbst (dort legt "atlas.json anlegen" die Datei an).
    mDir := DirOf(ARootPath);
    mFound := ConfigurationDir(FReadFile, mDir);
    if mFound <> '' then
    begin
      mDir := mFound;
      FConfigRoot := mFound;
    end;
    FFiles.Primary := mDir + ConfigurationFileName;
    FFiles.Legacy := mDir + LegacyConfigurationFileName;
  end;
  LoadFromDisk;
end;

procedure TLspConfiguration.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Issues: TArray<TConfigurationIssue>;
begin
  if not IsConfigurationUri(ADocument.Uri) then
  begin
    Exit;
  end;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      begin
        Issues := FileIssues(ADocument.Text);
        Publish(ADocument.Uri, ADocument.Version, Issues);
        if IsWorkspaceFile(ADocument.Uri) then
        begin
          FTexts.Workspace := ADocument.Text;
          Recompute;
        end;
      end;
    TDocumentEventKind.Closed:
      if IsWorkspaceFile(ADocument.Uri) then
      begin
        LoadFromDisk;
      end
      else
      begin
        Publish(ADocument.Uri, -1, nil);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

class function TLspConfiguration.RootPathFromInitialize(const AParams: TJSONObject): string;
var
  Value: TJSONValue;
  Folders: TJSONArray;
begin
  Result := '';
  if AParams = nil then
  begin
    Exit;
  end;
  Value := AParams.GetValue('rootUri');
  if (Value is TJSONString) and (Value.Value <> '') then
  begin
    Exit(TDocumentUris.ToPath(Value.Value));
  end;
  Value := AParams.GetValue('workspaceFolders');
  if Value is TJSONArray then
  begin
    Folders := TJSONArray(Value);
    if (Folders.Count > 0) and (Folders.Items[0] is TJSONObject) then
    begin
      Value := TJSONObject(Folders.Items[0]).GetValue('uri');
      if Value is TJSONString then
      begin
        Exit(TDocumentUris.ToPath(Value.Value));
      end;
    end;
  end;
  Value := AParams.GetValue('rootPath');
  if Value is TJSONString then
  begin
    Result := Value.Value;
  end;
end;

end.
