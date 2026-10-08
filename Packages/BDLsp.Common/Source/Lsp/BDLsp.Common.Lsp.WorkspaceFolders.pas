unit BDLsp.Common.Lsp.WorkspaceFolders;

// Mehrere Projektordner in einem Editorfenster (Multi-Root-Workspaces).
//
// Die Ordner kommen aus workspaceFolders in initialize (sonst rootUri bzw.
// rootPath als einziger Ordner) und ändern sich über
// workspace/didChangeWorkspaceFolders. FolderOf ordnet einer Datei den
// innersten Ordner zu, der sie enthält.

interface

uses
  System.SysUtils,
  System.JSON,
  BDLsp.Common.JsonRpc.Contract,
  BDLsp.Common.JsonRpc.Dispatcher;

type
  TWorkspaceFolder = record
    Path: string;
    Name: string;
    constructor Create(const APath, AName: string);
  end;

  TWorkspaceFoldersChangedEvent = reference to procedure(const AAdded, ARemoved: TArray<TWorkspaceFolder>);

  TLspWorkspaceFolders = class
  public const
    DidChangeMethod = 'workspace/didChangeWorkspaceFolders';
  private
    FOnChanged: TWorkspaceFoldersChangedEvent;
    procedure HandleDidChange(const AParams: TJSONValue);
  public
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Ordner aus den initialize-Parametern; leer ohne Arbeitsbereich.</summary>
    class function FromInitialize(const AParams: TJSONObject): TArray<TWorkspaceFolder>; static;
    /// <summary>Hinzugefügte und entfernte Ordner aus didChangeWorkspaceFolders.</summary>
    class procedure ParseChange(const AParams: TJSONValue; out AAdded, ARemoved: TArray<TWorkspaceFolder>); static;
    /// <summary>Index des innersten Ordners, der AFileName enthält; -1 wenn keiner.</summary>
    class function FolderOf(const AFolders: TArray<TWorkspaceFolder>; const AFileName: string): Integer; static;
    /// <summary>Capability workspace.workspaceFolders. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    property OnChanged: TWorkspaceFoldersChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  BDLsp.Common.Documents.Uris;

function ReadFolders(const AValue: TJSONValue): TArray<TWorkspaceFolder>;
var
  Item: TJSONValue;
  Uri, Name, Path: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Item in TJSONArray(AValue) do
  begin
    if not Item.TryGetValue<string>('uri', Uri) then
      Continue;
    Path := TDocumentUris.ToPath(Uri);
    if Path = '' then
      Continue;
    if not Item.TryGetValue<string>('name', Name) then
      Name := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
    Result := Result + [TWorkspaceFolder.Create(Path, Name)];
  end;
end;

function WithSeparator(const APath: string): string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

{ TWorkspaceFolder }

constructor TWorkspaceFolder.Create(const APath, AName: string);
begin
  Path := APath;
  Name := AName;
end;

{ TLspWorkspaceFolders }

procedure TLspWorkspaceFolders.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(DidChangeMethod, HandleDidChange);
end;

class function TLspWorkspaceFolders.FromInitialize(const AParams: TJSONObject): TArray<TWorkspaceFolder>;
var
  Value: TJSONValue;
  Path: string;
begin
  Result := nil;
  if AParams = nil then
    Exit;
  Result := ReadFolders(AParams.GetValue('workspaceFolders'));
  if Length(Result) > 0 then
    Exit;
  // Ältere Clients: nur ein Wurzelordner.
  Path := '';
  Value := AParams.GetValue('rootUri');
  if (Value is TJSONString) and (Value.Value <> '') then
    Path := TDocumentUris.ToPath(Value.Value)
  else
  begin
    Value := AParams.GetValue('rootPath');
    if Value is TJSONString then
      Path := Value.Value;
  end;
  if Path <> '' then
    Result := [TWorkspaceFolder.Create(Path, ExtractFileName(ExcludeTrailingPathDelimiter(Path)))];
end;

class procedure TLspWorkspaceFolders.ParseChange(const AParams: TJSONValue;
  out AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  Event: TJSONValue;
begin
  AAdded := nil;
  ARemoved := nil;
  if not (AParams is TJSONObject) then
    Exit;
  Event := TJSONObject(AParams).GetValue('event');
  if not (Event is TJSONObject) then
    Exit;
  AAdded := ReadFolders(TJSONObject(Event).GetValue('added'));
  ARemoved := ReadFolders(TJSONObject(Event).GetValue('removed'));
end;

class function TLspWorkspaceFolders.FolderOf(const AFolders: TArray<TWorkspaceFolder>;
  const AFileName: string): Integer;
var
  Index, BestLength: Integer;
  FileName, Folder: string;
begin
  Result := -1;
  BestLength := -1;
  FileName := StringReplace(AFileName, '/', '\', [rfReplaceAll]);
  for Index := 0 to High(AFolders) do
  begin
    Folder := WithSeparator(AFolders[Index].Path);
    if (Length(Folder) > BestLength) and SameText(Copy(FileName, 1, Length(Folder)), Folder) then
    begin
      Result := Index;
      BestLength := Length(Folder);
    end;
  end;
end;

class function TLspWorkspaceFolders.Capability: TJSONObject;
var
  Folders: TJSONObject;
begin
  Folders := TJSONObject.Create;
  Folders.AddPair('supported', TJSONBool.Create(True));
  Folders.AddPair('changeNotifications', TJSONBool.Create(True));
  Result := TJSONObject.Create;
  Result.AddPair('workspaceFolders', Folders);
end;

procedure TLspWorkspaceFolders.HandleDidChange(const AParams: TJSONValue);
var
  Added, Removed: TArray<TWorkspaceFolder>;
begin
  ParseChange(AParams, Added, Removed);
  if ((Length(Added) > 0) or (Length(Removed) > 0)) and Assigned(FOnChanged) then
    FOnChanged(Added, Removed);
end;

end.
