unit BDLsp.Common.Lsp.Configuration;

// Konfigurationsdatei delphi-lsp.json im Arbeitsbereich.
//
// - LoadWorkspace liest die Datei aus dem Wurzelordner (nach initialized).
// - Ist eine delphi-lsp.json im Editor geöffnet, werden ihre Fehler als
//   publishDiagnostics gemeldet, schon beim Tippen.
// - Ändert sich die Datei des Arbeitsbereichs im Editor, gelten die neuen
//   Einstellungen sofort; nach dem Schließen gilt wieder der Stand auf der
//   Platte. Änderungen außerhalb des Editors folgen mit #22.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract;

type
  /// <summary>Liest eine Datei; False, wenn sie nicht existiert.</summary>
  TConfigurationFileReader = reference to function(const AFileName: string; out AText: string): Boolean;

  TLspConfiguration = class
  private
    FStore: IDocumentStore;
    FTransport: IJsonRpcTransport;
    FReadFile: TConfigurationFileReader;
    FLock: TObject;
    FSettings: TServerSettings;
    FRootPath: string;
    FFileName: string;
    FOnChanged: TConfigurationChangedEvent;
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
    /// <summary>Meldet sich am Dokumentspeicher an.</summary>
    procedure Attach;
    /// <summary>Liest delphi-lsp.json aus ARootPath; ohne Datei gelten die Vorgaben.</summary>
    procedure LoadWorkspace(const ARootPath: string);
    /// <summary>Wurzelordner aus den initialize-Parametern (rootUri, workspaceFolders, rootPath); sonst ''.</summary>
    class function RootPathFromInitialize(const AParams: TJSONObject): string; static;
    /// <summary>Diagnostics zu den Fehlern; der Aufrufer übernimmt das Objekt.</summary>
    class function BuildParams(const AUri: string; AVersion: Integer;
      const AIssues: TArray<TConfigurationIssue>): TJSONObject; static;
    /// <summary>Aktuelle Einstellungen (Kopie, threadsicher).</summary>
    property Settings: TServerSettings read GetSettings;
    property RootPath: string read FRootPath;
    /// <summary>Wird nach jeder Übernahme neuer Einstellungen aufgerufen.</summary>
    property OnChanged: TConfigurationChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  BDLsp.Common.JsonRpc.Messages,
  BDLsp.Common.Lsp.Contract,
  BDLsp.Common.Lsp.Positions,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Configuration.Parser;

const
  DiagnosticSource = 'BetterDelphiLSP';

function IsConfigurationUri(const AUri: string): Boolean;
var
  Path: string;
begin
  Path := StringReplace(TDocumentUris.ToPath(AUri), '\', '/', [rfReplaceAll]);
  Result := SameText(Copy(Path, LastDelimiter('/', Path) + 1, MaxInt), ConfigurationFileName);
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
  FStore.Subscribe(HandleDocumentEvent);
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
  Settings: TServerSettings;
begin
  if (FFileName <> '') and FReadFile(FFileName, Text) then
  begin
    Settings := TConfigurationParser.Parse(Text, Issues);
    Publish(TDocumentUris.FromPath(FFileName), -1, Issues);
  end
  else
    Settings := TServerSettings.Default;
  Apply(Settings);
end;

procedure TLspConfiguration.LoadWorkspace(const ARootPath: string);
var
  Separator: string;
begin
  FRootPath := ARootPath;
  if ARootPath = '' then
    FFileName := ''
  else
  begin
    if Pos('\', ARootPath) > 0 then
      Separator := '\'
    else
      Separator := '/';
    if ARootPath[Length(ARootPath)] = Separator then
      FFileName := ARootPath + ConfigurationFileName
    else
      FFileName := ARootPath + Separator + ConfigurationFileName;
  end;
  LoadFromDisk;
end;

procedure TLspConfiguration.HandleDocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  Issues: TArray<TConfigurationIssue>;
  Settings: TServerSettings;
begin
  if not IsConfigurationUri(ADocument.Uri) then
    Exit;
  case AKind of
    TDocumentEventKind.Opened, TDocumentEventKind.Changed:
      begin
        Settings := TConfigurationParser.Parse(ADocument.Text, Issues);
        Publish(ADocument.Uri, ADocument.Version, Issues);
        if IsWorkspaceFile(ADocument.Uri) then
          Apply(Settings);
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
