unit Lsp.ConfigurationProtocol;

// LSP-Seite der Konfiguration des Arbeitsbereichs (TWorkspaceConfiguration): Fehler in atlas.json als
// textDocument/publishDiagnostics, Editor-Einstellungen aus workspace/didChangeConfiguration und
// initializationOptions (Abschnitt "atlas"), Wurzelordner und Sprache aus den initialize-Parametern (#1458).

interface

uses
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Workspace;

type
  TLspConfigurationProtocol = class
  public const
    cDidChangeConfigurationMethod = 'workspace/didChangeConfiguration';
    /// <summary>Abschnitt der Editor-Einstellungen, z. B. atlas.project in VS Code.</summary>
    cEditorSection = 'atlas';
  public
    /// <summary>Meldet die Fehler einer Konfigurationsdatei als textDocument/publishDiagnostics über ATransport.
    /// </summary>
    class function Publisher(const ATransport: IJsonRpcTransport): TConfigurationIssuesPublisher; static;
    /// <summary>Wurzelordner aus den initialize-Parametern (rootUri, workspaceFolders, rootPath); sonst ''.</summary>
    class function RootPathFromInitialize(const AParams: TJSONObject): string; static;
    /// <summary>Abschnitt atlas aus den Parametern von didChangeConfiguration als JSON; sonst ''.</summary>
    class function EditorSettingsFromParams(const AParams: TJSONValue): string; static;
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
  System.SysUtils,
  Atlas.Common.JsonRpc.Messages,
  Atlas.Common.JsonRpc.Positions,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Lsp.Contract;

const
  cDiagnosticSource = 'Atlas';

/// <summary>Diagnostics zu den Fehlern; der Aufrufer übernimmt das Objekt.</summary>
function PublishParams(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>): TJSONObject;
var
  mItems: TJSONArray;
  mItem: TJSONObject;
  mIssue: TConfigurationIssue;
begin
  mItems := TJSONArray.Create;
  for mIssue in AIssues do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('range', TLspPositions.RangeToJson(mIssue.Range));
    if mIssue.IsError then
    begin
      mItem.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cError));
    end
    else
    begin
      mItem.AddPair('severity', TJSONNumber.Create(TLspDiagnosticSeverity.cWarning));
    end;
    mItem.AddPair('source', cDiagnosticSource);
    mItem.AddPair('message', mIssue.Message);
    mItems.AddElement(mItem);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('uri', AUri);
  if AVersion >= 0 then
  begin
    Result.AddPair('version', TJSONNumber.Create(AVersion));
  end;
  Result.AddPair('diagnostics', mItems);
end;

{ TLspConfigurationProtocol }

class function TLspConfigurationProtocol.Publisher(const ATransport: IJsonRpcTransport): TConfigurationIssuesPublisher;
begin
  Result :=
    procedure(const AUri: string; AVersion: Integer; const AIssues: TArray<TConfigurationIssue>)
    var
      mNotification: TJSONObject;
    begin
      mNotification := TJsonRpcMessages.Notification(TLspTextDocumentMethod.cPublishDiagnostics,
        PublishParams(AUri, AVersion, AIssues));
      try
        ATransport.WriteMessage(mNotification);
      finally
        mNotification.Free;
      end;
    end;
end;

class function TLspConfigurationProtocol.RootPathFromInitialize(const AParams: TJSONObject): string;
var
  mValue: TJSONValue;
  mFolders: TJSONArray;
begin
  Result := '';
  if AParams = nil then
  begin
    Exit;
  end;
  mValue := AParams.GetValue('rootUri');
  if (mValue is TJSONString) and (mValue.Value <> '') then
  begin
    Exit(TDocumentUris.ToPath(mValue.Value));
  end;
  mValue := AParams.GetValue('workspaceFolders');
  if mValue is TJSONArray then
  begin
    mFolders := TJSONArray(mValue);
    if (mFolders.Count > 0) and (mFolders.Items[0] is TJSONObject) then
    begin
      mValue := TJSONObject(mFolders.Items[0]).GetValue('uri');
      if mValue is TJSONString then
      begin
        Exit(TDocumentUris.ToPath(mValue.Value));
      end;
    end;
  end;
  mValue := AParams.GetValue('rootPath');
  if mValue is TJSONString then
  begin
    Result := mValue.Value;
  end;
end;

class function TLspConfigurationProtocol.EditorSettingsFromParams(const AParams: TJSONValue): string;
var
  mSection: TJSONValue;
begin
  Result := '';
  if not (AParams is TJSONObject) then
  begin
    Exit;
  end;
  mSection := TJSONObject(AParams).FindValue('settings.' + cEditorSection);
  if mSection is TJSONObject then
  begin
    Result := mSection.ToJSON;
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

end.
