unit Shell.SlashHost;

// Host-Rolle Shell: Projekt- und Editorzugriff für Schnellbefehle wie
// /define, /config und /dfm (#301). Schreibt die .dproj in ihrer Kodierung
// zurück, lädt den Ordner neu und schickt window/showDocument an den Editor.

interface

uses
  System.SysUtils,
  BDLsp.Common.Logging.Contract,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Projects.Contract,
  BDLsp.Common.Editing.SlashCommands,
  Shell.Workspace;

type
  /// <summary>Ordner zur Datei AUri; nil ohne.</summary>
  TWorkspaceOfFunc = reference to function(const AUri: string): TShellWorkspace;
  TReadTextFunc = reference to function(const AFileName: string; out AText: string): Boolean;

  TShellSlashHost = class(TInterfacedObject, ISlashHost)
  private
    FWorkspaceOf: TWorkspaceOfFunc;
    FReadText: TReadTextFunc;
    FTransport: IJsonRpcTransport;
    FLogger: ILogger;
    FRequestId: Integer;
  public
    constructor Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
      const ATransport: IJsonRpcTransport; const ALogger: ILogger);
    function Project(const AUri: string; out AProject: TProjectInfo): Boolean;
    function ReadFile(const AFileName: string; out AText: string): Boolean;
    function DirectoryExists(const APath: string): Boolean;
    procedure WriteProject(const AUri, AText: string);
    procedure SelectBuild(const AUri, AConfig, APlatform: string);
    procedure ShowDocument(const AFileName: string; const ASelection: TTextRange);
  end;

implementation

uses
  System.JSON,
  BDLsp.Common.Documents.Uris,
  BDLsp.Common.Documents.FileEncoding,
  BDLsp.Common.Lsp.Positions;

constructor TShellSlashHost.Create(const AWorkspaceOf: TWorkspaceOfFunc; const AReadText: TReadTextFunc;
  const ATransport: IJsonRpcTransport; const ALogger: ILogger);
begin
  inherited Create;
  FWorkspaceOf := AWorkspaceOf;
  FReadText := AReadText;
  FTransport := ATransport;
  FLogger := ALogger;
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

procedure TShellSlashHost.WriteProject(const AUri, AText: string);
var
  Workspace: TShellWorkspace;
  Info: TProjectInfo;
  FileFormat: TFileFormat;
begin
  Workspace := FWorkspaceOf(AUri);
  if (Workspace = nil) or not Workspace.Project(Info) then
    Exit;
  try
    // Kodierung und Zeilenumbrüche der vorhandenen Datei beibehalten.
    TFileEncoding.LoadFromFile(Info.FileName, FileFormat);
    TFileEncoding.SaveToFile(Info.FileName, AText, FileFormat);
    FLogger.Info(Format('%s geändert (Schnellbefehl)', [Info.FileName]));
    Workspace.Reload;
  except
    on E: Exception do
      FLogger.Error(Format('%s ließ sich nicht schreiben: %s', [Info.FileName, E.Message]));
  end;
end;

procedure TShellSlashHost.SelectBuild(const AUri, AConfig, APlatform: string);
var
  Workspace: TShellWorkspace;
  Error: string;
begin
  Workspace := FWorkspaceOf(AUri);
  if (Workspace <> nil) and not Workspace.SelectBuild(AConfig, APlatform, Error) then
    FLogger.Warning(Error);
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
    Request.AddPair('id', Format('bdlsp/showDocument/%d', [AtomicIncrement(FRequestId)]));
    Request.AddPair('method', 'window/showDocument');
    Request.AddPair('params', Params);
    FTransport.WriteMessage(Request);
  finally
    Request.Free;
  end;
end;

end.
