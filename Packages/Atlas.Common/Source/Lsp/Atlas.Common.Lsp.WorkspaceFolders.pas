unit Atlas.Common.Lsp.WorkspaceFolders;

// Mehrere Projektordner in einem Editorfenster (Multi-Root-Workspaces).
//
// Die Ordner kommen aus workspaceFolders in initialize (sonst rootUri bzw.
// rootPath als einziger Ordner) und ändern sich über
// workspace/didChangeWorkspaceFolders. FolderOf ordnet einer Datei den
// innersten Ordner zu, der sie enthält.
//
// Manche Clients melden keinen brauchbaren Ordner: RAD Studio schickt
// rootUri "file:///" und keine workspaceFolders. Laufwerkswurzeln und "/"
// gelten deshalb nicht als Ordner; der Server leitet ihn dann aus der
// geöffneten Datei ab (ProjectFolderFor, #175).
//
// Projektgruppen (#648): Das Atlas-Plugin meldet die Projekte der Gruppe als
// Einträge, deren uri auf die .dproj (oder .groupproj) zeigt. Path ist dann
// der Ordner der Datei, ProjectFile die Datei selbst.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher;

type
  TWorkspaceFolder = record
    Path: string;
    Name: string;
    /// <summary>Projekt- oder Gruppendatei, wenn der Eintrag eine Datei nennt (#648); sonst ''.</summary>
    ProjectFile: string;
    constructor Create(const APath, AName: string; const AProjectFile: string = '');
    /// <summary>Schlüssel zum Wiederfinden beim Entfernen: die Datei, sonst der Ordner.</summary>
    function Key: string;
  end;

  TWorkspaceFoldersChangedEvent = reference to procedure(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
  /// <summary>True, wenn im Ordner AFolder eine Projektdatei liegt.</summary>
  THasProjectFileFunc = reference to function(const AFolder: string): Boolean;

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
    /// <summary>True für Dateinamen mit .dproj oder .groupproj (Einträge des Plugins, #648).</summary>
    class function IsProjectFile(const APath: string): Boolean; static;
    /// <summary>False für '', "/" und Laufwerkswurzeln: Dort zu indizieren hieße, die ganze Platte zu lesen.</summary>
    class function IsUsableRoot(const APath: string): Boolean; static;
    /// <summary>Nächster Ordner ab dem Ordner von AFileName aufwärts, für den AHasProjectFile
    /// True liefert; Laufwerkswurzeln ausgenommen. '' wenn keiner.</summary>
    class function ProjectFolderFor(const AFileName: string; const AHasProjectFile: THasProjectFileFunc): string; static;
    /// <summary>Capability workspace.workspaceFolders. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    property OnChanged: TWorkspaceFoldersChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  Atlas.Common.Documents.Uris;

function ReadFolders(const AValue: TJSONValue): TArray<TWorkspaceFolder>;
var
  Item: TJSONValue;
  Uri, Name, Path, ProjectFile: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
    Exit;
  for Item in TJSONArray(AValue) do
  begin
    if not Item.TryGetValue<string>('uri', Uri) then
      Continue;
    Path := TDocumentUris.ToPath(Uri);
    ProjectFile := '';
    if TLspWorkspaceFolders.IsProjectFile(Path) then
    begin
      ProjectFile := Path;
      Path := ExtractFileDir(ProjectFile);
    end;
    if not TLspWorkspaceFolders.IsUsableRoot(Path) then
      Continue;
    if not Item.TryGetValue<string>('name', Name) then
    begin
      if ProjectFile <> '' then
        Name := ChangeFileExt(ExtractFileName(ProjectFile), '')
      else
        Name := ExtractFileName(ExcludeTrailingPathDelimiter(Path));
    end;
    Result := Result + [TWorkspaceFolder.Create(Path, Name, ProjectFile)];
  end;
end;

function WithSeparator(const APath: string): string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  if (Result <> '') and (Result[Length(Result)] <> '\') then
    Result := Result + '\';
end;

{ TWorkspaceFolder }

constructor TWorkspaceFolder.Create(const APath, AName, AProjectFile: string);
begin
  Path := APath;
  Name := AName;
  ProjectFile := AProjectFile;
end;

function TWorkspaceFolder.Key: string;
begin
  if ProjectFile <> '' then
    Result := AnsiUpperCase(ProjectFile)
  else
    Result := AnsiUpperCase(ExcludeTrailingPathDelimiter(StringReplace(Path, '/', '\', [rfReplaceAll])));
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
  if IsUsableRoot(Path) then
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

class function TLspWorkspaceFolders.IsProjectFile(const APath: string): Boolean;
begin
  Result := SameText(ExtractFileExt(APath), '.dproj') or SameText(ExtractFileExt(APath), '.groupproj');
end;

class function TLspWorkspaceFolders.IsUsableRoot(const APath: string): Boolean;
var
  Path: string;
begin
  Path := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
  while (Path <> '') and (Path[Length(Path)] = '\') do
    SetLength(Path, Length(Path) - 1);
  // Übrig bleibt bei "/" nichts, bei "C:\" nur "C:".
  Result := (Path <> '') and not ((Length(Path) = 2) and (Path[2] = ':'));
end;

class function TLspWorkspaceFolders.ProjectFolderFor(const AFileName: string;
  const AHasProjectFile: THasProjectFileFunc): string;
var
  Folder, Parent: string;
begin
  Result := '';
  Folder := ExcludeTrailingPathDelimiter(ExtractFileDir(StringReplace(AFileName, '/', '\', [rfReplaceAll])));
  while IsUsableRoot(Folder) do
  begin
    if AHasProjectFile(Folder) then
      Exit(Folder);
    Parent := ExcludeTrailingPathDelimiter(ExtractFileDir(Folder));
    if SameText(Parent, Folder) then
      Break;
    Folder := Parent;
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
