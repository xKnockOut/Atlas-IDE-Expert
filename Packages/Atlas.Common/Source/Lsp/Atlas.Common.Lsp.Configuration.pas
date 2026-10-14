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
// - Einstellungen aus dem Editor kommen über workspace/didChangeConfiguration
//   (Abschnitt "atlas"). atlas.json hat je Schlüssel Vorrang
//   (TConfigurationParser.ParseLayered).
// - Darunter liegt die globale Benutzerdatei (%APPDATA%\Atlas\settings.json,
//   #227), die die Komposition über SetGlobalSettings übergibt: global <
//   Editor < atlas.json.

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
    /// <summary>Gelesene Datei des Arbeitsbereichs: atlas.json oder die frühere.</summary>
    FFileName: string;
    FPrimaryFileName: string;
    FLegacyFileName: string;
    FOnChanged: TConfigurationChangedEvent;
    // Nur im Thread der Nachrichtenschleife benutzt.
    FFileText: string;
    FEditorText: string;
    FGlobalText: string;
    procedure Recompute;
    procedure HandleDidChangeConfiguration(const AParams: TJSONValue);
    procedure HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    procedure Apply(const ASettings: TServerSettings);
    procedure Publish(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>);
    procedure LoadFromDisk;
    function IsWorkspaceFile(const AUri: string): Boolean;
    function GetSettings: TServerSettings;
  public
    constructor Create(const AStore: IDocumentStore; const ATransport: IJsonRpcTransport;
      const AReadFile: TConfigurationFileReader);
    destructor Destroy; override;
    /// <summary>Meldet sich am Dokumentspeicher und, falls angegeben, für Editor-Einstellungen am Dispatcher an.
    /// Bei mehreren Arbeitsbereichsordnern verteilt die Komposition die Ereignisse selbst
    /// (DocumentEvent, SetEditorSettings) und ruft Attach nicht auf.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher = nil);
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
    /// <summary>Liest atlas.json aus ARootPath; ohne Datei gelten die Vorgaben.</summary>
    procedure LoadWorkspace(const ARootPath: string);
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
    /// <summary>Gelesene Datei (atlas.json oder die frühere), '' ohne; für den Fehlerbericht (#108).</summary>
    property FileName: string read FFileName;
    /// <summary>atlas.json und die frühere Datei des Arbeitsbereichs, auch wenn es sie nicht gibt; für den
    /// Dateibeobachter (#227).</summary>
    property PrimaryFileName: string read FPrimaryFileName;
    property LegacyFileName: string read FLegacyFileName;
    /// <summary>Text der Datei bzw. des Editor-Abschnitts, aus dem Settings entsteht; nur im Thread der
    /// Nachrichtenschleife lesen.</summary>
    property FileText: string read FFileText;
    property EditorText: string read FEditorText;
    property GlobalText: string read FGlobalText;
    /// <summary>Wird nach jeder Übernahme neuer Einstellungen aufgerufen.</summary>
    property OnChanged: TConfigurationChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Parser;

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

procedure TLspConfiguration.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FStore.Subscribe(HandleDocumentEvent);
  if ADispatcher <> nil then
    ADispatcher.RegisterNotification(DidChangeConfigurationMethod, HandleDidChangeConfiguration);
end;

procedure TLspConfiguration.Recompute;
var
  Ignored: TArray<TConfigurationIssue>;
begin
  // Die Meldungen zur Datei sind schon veröffentlicht.
  Apply(TConfigurationParser.ParseLayered(TConfigurationParser.MergeText(FGlobalText, FEditorText), FFileText,
    Ignored));
end;

procedure TLspConfiguration.HandleDidChangeConfiguration(const AParams: TJSONValue);
begin
  SetEditorSettings(EditorSettingsFromParams(AParams));
end;

procedure TLspConfiguration.SetEditorSettings(const AText: string);
begin
  if AText = FEditorText then
    Exit;
  FEditorText := AText;
  Recompute;
end;

procedure TLspConfiguration.SetGlobalSettings(const AText: string);
begin
  if AText = FGlobalText then
    Exit;
  FGlobalText := AText;
  Recompute;
end;

function TLspConfiguration.FileChanged(const AFileName: string): Boolean;
var
  Document: ITextDocument;
begin
  Result := (AFileName <> '') and (SameText(AFileName, FPrimaryFileName) or SameText(AFileName, FLegacyFileName));
  if not Result then
    Exit;
  // Im Editor geöffnet: Dort gilt der Text des Editors, bis er schließt.
  if (FFileName <> '') and FStore.TryGet(TDocumentUris.FromPath(FFileName), Document) then
    Exit(False);
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
    Exit;
  Section := TJSONObject(AParams).FindValue('settings.' + EditorSection);
  if Section is TJSONObject then
    Result := Section.ToJSON;
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
    FOnChanged(ASettings);
end;

function TLspConfiguration.IsWorkspaceFile(const AUri: string): Boolean;
begin
  Result := (FFileName <> '') and SameText(TDocumentUris.ToPath(AUri), FFileName);
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
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Error))
    else
      Item.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.Warning));
    Item.AddPair('source', DiagnosticSource);
    Item.AddPair('message', Issue.Message);
    Items.AddElement(Item);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  if AVersion >= 0 then
    Result.AddPair('version', TJSONNumber.Create(AVersion));
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
  FFileName := FPrimaryFileName;
  Found := (FFileName <> '') and FReadFile(FFileName, Text);
  if not Found and (FLegacyFileName <> '') and FReadFile(FLegacyFileName, Text) then
  begin
    FFileName := FLegacyFileName;
    Found := True;
  end;
  if Found then
  begin
    TConfigurationParser.Parse(Text, Issues);
    Publish(TDocumentUris.FromPath(FFileName), -1, Issues);
    FFileText := Text;
  end
  else
    FFileText := '';
  Recompute;
end;

procedure TLspConfiguration.LoadWorkspace(const ARootPath: string);
var
  Separator, Dir: string;
begin
  FRootPath := ARootPath;
  if ARootPath = '' then
  begin
    FPrimaryFileName := '';
    FLegacyFileName := '';
  end
  else
  begin
    if Pos('\', ARootPath) > 0 then
      Separator := '\'
    else
      Separator := '/';
    if ARootPath[Length(ARootPath)] = Separator then
      Dir := ARootPath
    else
      Dir := ARootPath + Separator;
    FPrimaryFileName := Dir + ConfigurationFileName;
    FLegacyFileName := Dir + LegacyConfigurationFileName;
  end;
  LoadFromDisk;
end;

procedure TLspConfiguration.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Issues: TArray<TConfigurationIssue>;
begin
  if not IsConfigurationUri(ADocument.Uri) then
    Exit;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      begin
        TConfigurationParser.Parse(ADocument.Text, Issues);
        Publish(ADocument.Uri, ADocument.Version, Issues);
        if IsWorkspaceFile(ADocument.Uri) then
        begin
          FFileText := ADocument.Text;
          Recompute;
        end;
      end;
    TDocumentEventKind.Closed:
      if IsWorkspaceFile(ADocument.Uri) then
        LoadFromDisk
      else
        Publish(ADocument.Uri, -1, nil);
  end;
end;

class function TLspConfiguration.RootPathFromInitialize(const AParams: TJSONObject): string;
var
  Value: TJSONValue;
  Folders: TJSONArray;
begin
  Result := '';
  if AParams = nil then
    Exit;
  Value := AParams.GetValue('rootUri');
  if (Value is TJSONString) and (Value.Value <> '') then
    Exit(TDocumentUris.ToPath(Value.Value));
  Value := AParams.GetValue('workspaceFolders');
  if Value is TJSONArray then
  begin
    Folders := TJSONArray(Value);
    if (Folders.Count > 0) and (Folders.Items[0] is TJSONObject) then
    begin
      Value := TJSONObject(Folders.Items[0]).GetValue('uri');
      if Value is TJSONString then
        Exit(TDocumentUris.ToPath(Value.Value));
    end;
  end;
  Value := AParams.GetValue('rootPath');
  if Value is TJSONString then
    Result := Value.Value;
end;

end.
