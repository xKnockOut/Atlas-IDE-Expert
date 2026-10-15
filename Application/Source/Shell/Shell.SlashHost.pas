unit Shell.SlashHost;

// Host-Rolle Shell: Projekt- und Editorzugriff für Schnellbefehle wie
// /define, /config und /dfm (#301). Schreibt die .dproj in ihrer Kodierung
// zurück, lädt den Ordner neu und schickt window/showDocument an den Editor.
// Kann der Client workspace/applyEdit (das Plugin, #397), geht die Änderung
// an ihn statt auf die Platte, damit die IDE sie nicht beim Speichern des
// Projekts überschreibt; neu geladen wird nach seiner Antwort. Lehnt er ab,
// bleibt die Datei unverändert und der Editor zeigt den Grund.
//
// Schnellbefehle laufen in einem Worker-Thread (onTypeFormatting). Neu geladen
// wird nur im Thread der Nachrichtenschleife (Code-Review A-03): WriteProject
// und SelectBuild stellen das über RunInLoop dorthin.

interface

uses
  System.SysUtils,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Editing.SlashCommands,
  Shell.Workspace;

type
  /// <summary>Ordner zur Datei AUri; nil ohne.</summary>
  TWorkspaceOfFunc = reference to function(const AUri: string): TShellWorkspace;
  TReadTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;
  THeaderTemplateFunc = reference to function(const AUri: string): string;

  TShellSlashHost = class(TInterfacedObject, ISlashHost)
  private
    FWorkspaceOf: TWorkspaceOfFunc;
    FReadText: TReadTextFunc;
    FHeaderTemplate: THeaderTemplateFunc;
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FRequestId: Integer;
    FDispatcher: TJsonRpcDispatcher;
    FClientAppliesEdits: TFunc<Boolean>;
    FRunInLoop: TJsonRpcScheduler;
    function WriteThroughClient(const AUri, AFileName, AText: string): Boolean;
    /// <summary>Führt AWork im Thread der Nachrichtenschleife aus (über RunInLoop), sonst sofort.</summary>
    procedure InLoop(const AWork: TProc);
  public
    /// <summary>ADispatcher und AClientAppliesEdits dürfen nil sein; dann schreibt der Host selbst.</summary>
    constructor Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
      const AHeaderTemplate: THeaderTemplateFunc; const ATransport: IJsonRpcTransport; const ALogger: ILogger;
      ADispatcher: TJsonRpcDispatcher = nil; const AClientAppliesEdits: TFunc<Boolean> = nil);
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
    function HeaderTemplate(const AUri: string): string;
    /// <summary>Stellt Arbeit in die Nachrichtenschleife (TJsonRpcConnection.Queue). Reload und SelectBuild
    /// laufen nur dort (Code-Review A-03); ohne Zuweisung (Tests) sofort.</summary>
    property RunInLoop: TJsonRpcScheduler read FRunInLoop write FRunInLoop;
  end;

implementation

uses
  System.JSON,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Documents.FileEncoding,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.ApplyEdit;

constructor TShellSlashHost.Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
  const AHeaderTemplate: THeaderTemplateFunc; const ATransport: IJsonRpcTransport; const ALogger: ILogger;
  ADispatcher: TJsonRpcDispatcher; const AClientAppliesEdits: TFunc<Boolean>);
begin
  inherited Create;
  FWorkspaceOf := AWorkspaceOf;
  FReadText := AReadText;
  FHeaderTemplate := AHeaderTemplate;
  FTransport := ATransport;
  FLogger := ALogger;
  FDispatcher := ADispatcher;
  FClientAppliesEdits := AClientAppliesEdits;
end;

function TShellSlashHost.Project(const AUri: string; out AProject: TProjectInfo): Boolean;
var
  Workspace: TShellWorkspace;
begin
  Workspace := FWorkspaceOf(AUri);
  Result := (Workspace <> nil) and Workspace.Project(AProject);
end;

function TShellSlashHost.ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  Result := FReadText(AFileName, AText);
end;

function TShellSlashHost.DirectoryExists(const APath: string): Boolean;
begin
  Result := System.SysUtils.DirectoryExists(APath);
end;

function TShellSlashHost.WriteThroughClient(const AUri, AFileName, AText: string): Boolean;
var
  OldText, Id: string;
  FileFormat: TFileFormat;
  Request: TJSONObject;
  Logger: ILogger;
  Transport: IJsonRpcTransport;
  WorkspaceOf: TWorkspaceOfFunc;
begin
  Result := False;
  if (FDispatcher = nil) or not Assigned(FClientAppliesEdits) or not FClientAppliesEdits() then
    Exit;
  OldText := TFileEncoding.LoadFromFile(AFileName, FileFormat);
  Id := Format('atlas/applyEdit/%d', [AtomicIncrement(FRequestId)]);
  // Nur lokale Werte einfangen: Die Antwort kommt in der Nachrichtenschleife (ExpectResponse).
  Logger := FLogger;
  Transport := FTransport;
  WorkspaceOf := FWorkspaceOf;
  FDispatcher.ExpectResponse(Id,
    procedure(const AResponse: TJSONObject)
    var
      Reason: string;
      Target: TShellWorkspace;
      Message: TJSONObject;
    begin
      if TLspApplyEdit.ReadResult(AResponse, Reason) then
      begin
        Logger.Info(Format('%s geändert (Schnellbefehl, über den Editor)', [AFileName]));
        Target := WorkspaceOf(AUri);
        if Target <> nil then
          Target.Reload;
        Exit;
      end;
      Logger.Warning(Format('%s nicht geändert: %s', [AFileName, Reason]));
      Message := TJSONObject.Create;
      try
        Message.AddPair('jsonrpc', '2.0');
        Message.AddPair('method', 'window/showMessage');
        Message.AddPair('params', TJSONObject.Create.AddPair('type', TJSONNumber.Create(2))
          .AddPair('message', Format('Atlas: %s wurde nicht geändert (%s).', [ExtractFileName(AFileName), Reason])));
        Transport.WriteMessage(Message);
      finally
        Message.Free;
      end;
    end);
  Request := TLspApplyEdit.Request(Id, 'Atlas: Schnellbefehl', TLspApplyEdit.ReplaceAll(AFileName, OldText, AText));
  try
    try
      FTransport.WriteMessage(Request);
    except
      FDispatcher.ForgetResponse(Id);
      raise;
    end;
  finally
    Request.Free;
  end;
  Result := True;
end;

procedure TShellSlashHost.InLoop(const AWork: TProc);
begin
  if Assigned(FRunInLoop) then
    FRunInLoop(AWork)
  else
    AWork();
end;

procedure TShellSlashHost.WriteProject(const AUri, AText: string);
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  FileFormat: TFileFormat;
  WorkspaceOf: TWorkspaceOfFunc;
  Uri: string;
begin
  Workspace := FWorkspaceOf(AUri);
  if (Workspace = nil) or not Workspace.Project(Info) then
    Exit;
  try
    // In der IDE über das Plugin, nicht auf die Platte (#397).
    if WriteThroughClient(AUri, Info.FileName, AText) then
      Exit;
    // Kodierung und Zeilenumbrüche der vorhandenen Datei beibehalten.
    TFileEncoding.LoadFromFile(Info.FileName, FileFormat);
    TFileEncoding.SaveToFile(Info.FileName, AText, FileFormat);
    FLogger.Info(Format('%s geändert (Schnellbefehl)', [Info.FileName]));
  except
    on E: Exception do
    begin
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [Info.FileName, E.Message]));
      Exit;
    end;
  end;
  // const-Parameter lassen sich nicht einfangen.
  WorkspaceOf := FWorkspaceOf;
  Uri := AUri;
  InLoop(
    procedure
    var
      Target: TShellWorkspace;
    begin
      // In der Schleife neu suchen: Bis dahin kann der Ordner geschlossen worden sein.
      Target := WorkspaceOf(Uri);
      if Target <> nil then
        Target.Reload;
    end);
end;

procedure TShellSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
var
  WorkspaceOf: TWorkspaceOfFunc;
  Logger: ILogger;
  Uri, Config, PlatformName: string;
begin
  // const-Parameter lassen sich nicht einfangen; Self auch nicht (der Host kann vorher frei werden).
  WorkspaceOf := FWorkspaceOf;
  Logger := FLogger;
  Uri := AUri;
  Config := AConfig;
  PlatformName := APlatform;
  InLoop(
    procedure
    var
      Workspace: TShellWorkspace;
      Error: string;
    begin
      // Wählt Konfiguration und Plattform und lädt neu: nur in der Schleife (A-03).
      Workspace := WorkspaceOf(Uri);
      if (Workspace <> nil) and not Workspace.SelectBuild(Config, PlatformName, Error) then
        Logger.Warning(Error);
    end);
end;

procedure TShellSlashHost.ShowDocument(const AFileName: string; const ASelection: TTextRange);
var
  Request, Params: TJSONObject;
begin
  Params := TJSONObject.Create;
  Params.AddPair('uri', TDocumentUris.FromPath(AFileName));
  Params.AddPair('takeFocus', TJSONBool.Create(True));
  Params.AddPair('selection', TLspPositions.RangeToJson(ASelection));
  Request := TJSONObject.Create;
  try
    Request.AddPair('jsonrpc', '2.0');
    Request.AddPair('id', Format('atlas/showDocument/%d', [AtomicIncrement(FRequestId)]));
    Request.AddPair('method', 'window/showDocument');
    Request.AddPair('params', Params);
    FTransport.WriteMessage(Request);
  finally
    Request.Free;
  end;
end;

function TShellSlashHost.HeaderTemplate(const AUri: string): string;
begin
  Result := FHeaderTemplate(AUri);
end;

end.
