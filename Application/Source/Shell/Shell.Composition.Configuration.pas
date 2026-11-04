unit Shell.Composition.Configuration;

// Internals-Rolle Shell: Einstellungsdateien (#227). Die globale settings.json und die atlas.json der Ordner
// beobachtet der Server selbst, weil die RAD-Studio-IDE keine Dateiänderungen meldet; Editor-Einstellungen aus
// didChangeConfiguration und offene Einstellungsdateien ohne Ordner kommen hier an.

interface

uses
  System.JSON,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Configuration,
  Shell.Platform,
  Shell.Composition.Workspaces,
  Shell.Composition.Settings;

type
  /// <summary>Was die Einstellungsdateien von der Komposition brauchen.</summary>
  TShellConfigurationServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    Settings: TShellSettings;
    Documents: IDocumentStore;
    Transport: IJsonRpcTransport;
    /// <summary>Beobachtete Dateien auf der Platte geändert; läuft im Thread des Beobachters.</summary>
    FilesChanged: TFileWatcherChanged;
  end;

  /// <summary>Globale Einstellungsdatei, Beobachter der Einstellungsdateien und Einstellungen ohne Ordner.</summary>
  TShellConfiguration = class
  private
    FServices: TShellConfigurationServices;
    FReplay: Boolean;
    FReplaySettingsFile: string;
    FGlobalSettingsFile: string;
    FFileWatcher: TFileWatcher;
    FLooseConfiguration: TLspConfiguration;
    /// <summary>Meldungen der globalen Datei ins Log: Projekt-Schlüssel und fehlende Delphi-Version.</summary>
    procedure LogGlobalIssues(const AText: string);
    procedure DidChangeConfiguration(const AParams: TJSONValue);
  public
    constructor Create(const AServices: TShellConfigurationServices);
    destructor Destroy; override;
    /// <summary>Meldet didChangeConfiguration am Dispatcher an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Wiedergabe eines Mitschnitts: statt settings.json des Benutzers AFileName (leer: keine).</summary>
    procedure UseReplaySettings(const AFileName: string);
    /// <summary>Liest die globale Datei und beginnt die Beobachtung; vor dem ersten Ordner.</summary>
    procedure Start;
    /// <summary>Beendet die Beobachtung; vor der Verbindung, weil der Beobachter sie über FilesChanged ruft.</summary>
    procedure StopWatching;
    /// <summary>Globale Datei neu lesen und an die Ordner geben, wenn sie sich geändert hat.</summary>
    procedure LoadGlobalSettings;
    /// <summary>Beobachtet die globale Datei und die Einstellungsdateien aller Ordner.</summary>
    procedure UpdateWatchedFiles;
    function IsGlobalSettingsFile(const AFileName: string): Boolean;
    /// <summary>atlas.json von außen geändert (#227, etwa im Dialog des Plugins): ohne Neustart übernehmen.</summary>
    procedure FileChanged(const AFileName: string);
    /// <summary>Offene Einstellungsdatei geändert: an ihren Ordner, sonst an die Einstellungen ohne Ordner.</summary>
    procedure DocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
    property GlobalSettingsFile: string read FGlobalSettingsFile;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Configuration.Scopes,
  Atlas.Common.Projects.DelphiVersions,
  Atlas.Common.Documents.Uris,
  Shell.Bootstrap,
  Shell.Workspace;

constructor TShellConfiguration.Create(const AServices: TShellConfigurationServices);
begin
  inherited Create;
  FServices := AServices;
  FLooseConfiguration := TLspConfiguration.Create(FServices.Documents, FServices.Transport,
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end);
end;

destructor TShellConfiguration.Destroy;
begin
  StopWatching;
  FreeAndNil(FLooseConfiguration);
  inherited Destroy;
end;

procedure TShellConfiguration.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterNotification(TLspConfiguration.DidChangeConfigurationMethod, DidChangeConfiguration);
end;

procedure TShellConfiguration.UseReplaySettings(const AFileName: string);
begin
  FReplay := True;
  FReplaySettingsFile := AFileName;
end;

procedure TShellConfiguration.Start;
begin
  if FReplay then
  begin
    FGlobalSettingsFile := FReplaySettingsFile;
  end
  else
  begin
    FGlobalSettingsFile := TShellBootstrap.GlobalSettingsFile;
  end;
  LoadGlobalSettings;
  FFileWatcher := TFileWatcher.Create(FServices.FilesChanged);
end;

procedure TShellConfiguration.StopWatching;
begin
  FreeAndNil(FFileWatcher);
end;

procedure TShellConfiguration.DidChangeConfiguration(const AParams: TJSONValue);
var
  mWorkspace: TShellWorkspace;
begin
  FServices.Settings.SetEditorSettings(TLspConfiguration.EditorSettingsFromParams(AParams));
  for mWorkspace in FServices.Workspaces.Items.ToArray do
  begin
    mWorkspace.Configuration.SetEditorSettings(FServices.Settings.EditorSettings);
  end;
end;

procedure TShellConfiguration.LoadGlobalSettings;
var
  mText: string;
  mWorkspace: TShellWorkspace;
begin
  // Nicht lesbar (gerade geschrieben oder gesperrt): Warnung im Log, der Beobachter meldet die Datei erneut.
  mText := TShellBootstrap.LoadGlobalSettings(FGlobalSettingsFile, FServices.Logger);
  if not FServices.Settings.SetGlobalSettings(mText) then
  begin
    Exit;
  end;
  if mText <> '' then
  begin
    LogGlobalIssues(mText);
  end;
  for mWorkspace in FServices.Workspaces.Items.ToArray do
  begin
    mWorkspace.Configuration.SetGlobalSettings(FServices.Settings.GlobalSettings);
  end;
end;

procedure TShellConfiguration.LogGlobalIssues(const AText: string);
var
  mSettings: TServerSettings;
  mIssues, mMisplaced: TArray<TConfigurationIssue>;
  mIssue: TConfigurationIssue;
begin
  mSettings := TConfigurationParser.Parse(AText, mIssues);
  // Projekt-Schlüssel in der globalen Datei wirken nicht; das Log nennt sie.
  TConfigurationScopes.Filter(AText, TConfigurationScope.Global, mMisplaced);
  // "delphiVersion" ist global: Fehlt die Version, steht die Warnung mit Stelle in settings.json im Log
  // (#47); die Projekte nehmen dann die automatisch gewählte Version.
  mMisplaced := mMisplaced + TDelphiVersions.ConfigurationIssues(mSettings, TDelphiInstallation.Versions);
  FServices.Logger.Info(Format('Globale Einstellungen gelesen (%d Meldungen)', [Length(mIssues) + Length(mMisplaced)]));
  for mIssue in mMisplaced do
  begin
    FServices.Logger.Warning(Format('%s(%d,%d): %s', [ExtractFileName(FGlobalSettingsFile),
      mIssue.Range.StartPos.Line + 1, mIssue.Range.StartPos.Character + 1, mIssue.Message]));
  end;
end;

procedure TShellConfiguration.UpdateWatchedFiles;
var
  mFiles: TArray<string>;
  mWorkspace: TShellWorkspace;
begin
  if FFileWatcher = nil then
  begin
    Exit;
  end;
  mFiles := TArray<string>.Create(FGlobalSettingsFile);
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    for mWorkspace in FServices.Workspaces.Items do
    begin
      mFiles := mFiles + [mWorkspace.Configuration.Files.Primary, mWorkspace.Configuration.Files.Legacy];
    end;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  FFileWatcher.SetFiles(mFiles);
end;

function TShellConfiguration.IsGlobalSettingsFile(const AFileName: string): Boolean;
begin
  Result := (FGlobalSettingsFile <> '') and SameText(AFileName, FGlobalSettingsFile);
end;

procedure TShellConfiguration.FileChanged(const AFileName: string);
var
  mWorkspace: TShellWorkspace;
begin
  for mWorkspace in FServices.Workspaces.Items.ToArray do
  begin
    if mWorkspace.Configuration.FileChanged(AFileName) then
    begin
      FServices.Logger.Info(Format('Einstellungen von %s neu gelesen', [mWorkspace.Root]));
    end;
  end;
end;

procedure TShellConfiguration.DocumentEvent(AKind: TDocumentEventKind; const ADocument: ITextDocument);
var
  mWorkspace: TShellWorkspace;
begin
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mWorkspace := FServices.Workspaces.WorkspaceOf(TDocumentUris.ToPath(ADocument.Uri));
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  // Nur der Thread der Nachrichtenschleife entfernt Ordner; mWorkspace bleibt gültig.
  if mWorkspace <> nil then
  begin
    mWorkspace.Configuration.DocumentEvent(AKind, ADocument);
  end
  else
  begin
    FLooseConfiguration.DocumentEvent(AKind, ADocument);
  end;
end;

end.
