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
    constructor Create(const APath, AName, AProjectFile: string); overload;
    /// <summary>Wie oben ohne Projektdatei (AProjectFile = '').</summary>
    constructor Create(const APath, AName: string); overload;
    /// <summary>Schlüssel zum Wiederfinden beim Entfernen: die Datei, sonst der Ordner.</summary>
    function Key: string;
  end;

  TWorkspaceFoldersChangedEvent = reference to procedure(const AAdded, ARemoved: TArray<TWorkspaceFolder>);
  /// <summary>True, wenn im Ordner AFolder eine Projektdatei liegt.</summary>
  THasProjectFileFunc = reference to function(const AFolder: string): Boolean;

  TLspWorkspaceFolders = class
  public const
    cDidChangeMethod = 'workspace/didChangeWorkspaceFolders';
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
    class function ProjectFolderFor(const AFileName: string;
      const AHasProjectFile: THasProjectFileFunc): string; static;
    /// <summary>Capability workspace.workspaceFolders. Der Aufrufer übernimmt das Objekt.</summary>
    class function Capability: TJSONObject; static;
    property OnChanged: TWorkspaceFoldersChangedEvent read FOnChanged write FOnChanged;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Uris;

function ReadFolders(const AValue: TJSONValue): TArray<TWorkspaceFolder>;
var
  mItem: TJSONValue;
  mUri, mName, mPath, mProjectFile: string;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if not mItem.TryGetValue<string>('uri', mUri) then
    begin
      Continue;
    end;
    mPath := TDocumentUris.ToPath(mUri);
    mProjectFile := '';
    if TLspWorkspaceFolders.IsProjectFile(mPath) then
    begin
      mProjectFile := mPath;
      mPath := ExtractFileDir(mProjectFile);
    end;
    if not TLspWorkspaceFolders.IsUsableRoot(mPath) then
    begin
      Continue;
    end;
    if not mItem.TryGetValue<string>('name', mName) then
    begin
      if mProjectFile <> '' then
      begin
        mName := ChangeFileExt(ExtractFileName(mProjectFile), '');
      end
      else
      begin
        mName := ExtractFileName(ExcludeTrailingPathDelimiter(mPath));
      end;
    end;
    Result := Result + [TWorkspaceFolder.Create(mPath, mName, mProjectFile)];
  end;
end;

function WithSeparator(const APath: string): string;
begin
  Result := StringReplace(APath, '/', '\', [rfReplaceAll]);
  if (Result <> '') and (Result[Length(Result)] <> '\') then
  begin
    Result := Result + '\';
  end;
end;

{ TWorkspaceFolder }

constructor TWorkspaceFolder.Create(const APath, AName: string);
begin
  Self := TWorkspaceFolder.Create(APath, AName, '');
end;

constructor TWorkspaceFolder.Create(const APath, AName, AProjectFile: string);
begin
  Path := APath;
  Name := AName;
  ProjectFile := AProjectFile;
end;

function TWorkspaceFolder.Key: string;
begin
  if ProjectFile <> '' then
  begin
    Result := AnsiUpperCase(ProjectFile);
  end
  else
  begin
    Result := AnsiUpperCase(ExcludeTrailingPathDelimiter(StringReplace(Path, '/', '\', [rfReplaceAll])));
  end;
end;

{ TLspWorkspaceFolders }

procedure TLspWorkspaceFolders.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(cDidChangeMethod, HandleDidChange);
end;

class function TLspWorkspaceFolders.FromInitialize(const AParams: TJSONObject): TArray<TWorkspaceFolder>;
var
  mValue: TJSONValue;
  mPath: string;
begin
  Result := nil;
  if AParams = nil then
  begin
    Exit;
  end;
  Result := ReadFolders(AParams.GetValue('workspaceFolders'));
  if Length(Result) > 0 then
  begin
    Exit;
  end;
  // Ältere Clients: nur ein Wurzelordner.
  mPath := '';
  mValue := AParams.GetValue('rootUri');
  if (mValue is TJSONString) and (mValue.Value <> '') then
  begin
    mPath := TDocumentUris.ToPath(mValue.Value);
  end
  else
  begin
    mValue := AParams.GetValue('rootPath');
    if mValue is TJSONString then
    begin
      mPath := mValue.Value;
    end;
  end;
  if IsUsableRoot(mPath) then
  begin
    Result := [TWorkspaceFolder.Create(mPath, ExtractFileName(ExcludeTrailingPathDelimiter(mPath)))];
  end;
end;

class procedure TLspWorkspaceFolders.ParseChange(const AParams: TJSONValue;
  out AAdded, ARemoved: TArray<TWorkspaceFolder>);
var
  mEvent: TJSONValue;
begin
  AAdded := nil;
  ARemoved := nil;
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mEvent := TJSONObject(AParams).GetValue('event');
  if not (mEvent is TJSONObject) then
  begin
    Exit;
  end;
  AAdded := ReadFolders(TJSONObject(mEvent).GetValue('added'));
  ARemoved := ReadFolders(TJSONObject(mEvent).GetValue('removed'));
end;

class function TLspWorkspaceFolders.FolderOf(const AFolders: TArray<TWorkspaceFolder>;
  const AFileName: string): Integer;
var
  mIndex, mBestLength: Integer;
  mFileName, mFolder: string;
begin
  Result := -1;
  mBestLength := -1;
  mFileName := StringReplace(AFileName, '/', '\', [rfReplaceAll]);
  for mIndex := 0 to High(AFolders) do
  begin
    mFolder := WithSeparator(AFolders[mIndex].Path);
    if (Length(mFolder) > mBestLength) and SameText(Copy(mFileName, 1, Length(mFolder)), mFolder) then
    begin
      Result := mIndex;
      mBestLength := Length(mFolder);
    end;
  end;
end;

class function TLspWorkspaceFolders.IsProjectFile(const APath: string): Boolean;
begin
  Result := SameText(ExtractFileExt(APath), '.dproj') or SameText(ExtractFileExt(APath), '.groupproj');
end;

class function TLspWorkspaceFolders.IsUsableRoot(const APath: string): Boolean;
var
  mPath: string;
begin
  mPath := StringReplace(Trim(APath), '/', '\', [rfReplaceAll]);
  while (mPath <> '') and (mPath[Length(mPath)] = '\') do
  begin
    SetLength(mPath, Length(mPath) - 1);
  end;
  // Übrig bleibt bei "/" nichts, bei "C:\" nur "C:".
  Result := (mPath <> '') and not ((Length(mPath) = 2) and (mPath[2] = ':'));
end;

class function TLspWorkspaceFolders.ProjectFolderFor(const AFileName: string;
  const AHasProjectFile: THasProjectFileFunc): string;
var
  mFolder, mParent: string;
begin
  Result := '';
  mFolder := ExcludeTrailingPathDelimiter(ExtractFileDir(StringReplace(AFileName, '/', '\', [rfReplaceAll])));
  while IsUsableRoot(mFolder) do
  begin
    if AHasProjectFile(mFolder) then
    begin
      Exit(mFolder);
    end;
    mParent := ExcludeTrailingPathDelimiter(ExtractFileDir(mFolder));
    if SameText(mParent, mFolder) then
    begin
      Break;
    end;
    mFolder := mParent;
  end;
end;

class function TLspWorkspaceFolders.Capability: TJSONObject;
var
  mFolders: TJSONObject;
begin
  mFolders := TJSONObject.Create;
  mFolders.AddPair('supported', TJSONBool.Create(True));
  mFolders.AddPair('changeNotifications', TJSONBool.Create(True));
  Result := TJSONObject.Create;
  Result.AddPair('workspaceFolders', mFolders);
end;

procedure TLspWorkspaceFolders.HandleDidChange(const AParams: TJSONValue);
var
  mAdded, mRemoved: TArray<TWorkspaceFolder>;
begin
  ParseChange(AParams, mAdded, mRemoved);
  if ((Length(mAdded) > 0) or (Length(mRemoved) > 0)) and Assigned(FOnChanged) then
  begin
    FOnChanged(mAdded, mRemoved);
  end;
end;

end.
