unit Shell.Composition.FileChanges;

// Internals-Rolle Shell: Dateiänderungen. Meldungen des Clients und des eigenen Beobachters (workspace/
// didChangeWatchedFiles) ordnet es ein: Einstellungsdateien lesen neu, Projektdateien laden ihren Ordner neu,
// Quelltexte aktualisieren den Index (#500, #264). Ungespeicherte Stände gehen nach der Tipp-Pause in den Index
// (#492), geänderte uses prüfen offene Units neu (#896).

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.WatchedFiles,
  Atlas.Common.Lsp.IndexRefresh,
  Shell.Workspace,
  Shell.Composition.Workspaces,
  Shell.Composition.Configuration;

type
  TShellFileChangesProc = reference to procedure;
  TShellFileChangesFilesProc = reference to procedure(const AFiles: TArray<string>);

  /// <summary>Was die Dateiänderungen von der Komposition brauchen.</summary>
  TShellFileChangesServices = record
    Logger: ILogger;
    Workspaces: TShellWorkspaceRegistry;
    Transport: IJsonRpcTransport;
    Configuration: TShellConfiguration;
    /// <summary>Offene Dateien gebündelt neu prüfen.</summary>
    RefreshLater: TShellFileChangesProc;
    /// <summary>Im Editor getippt: Die Projektprüfung macht Platz (#1247).</summary>
    Typed: TShellFileChangesProc;
    /// <summary>Gespeichert oder von außen geändert: die Dateien und ihre Nutzer neu prüfen (#1247).</summary>
    Affected: TShellFileChangesFilesProc;
  end;

  /// <summary>Dateiänderungen von außen und aus dem Editor für Index, Ordner und Einstellungen.</summary>
  TShellFileChanges = class
  private
    FServices: TShellFileChangesServices;
    FWatchedFiles: TLspWatchedFiles;
    FIndexRefresh: TLspIndexRefresh;
    FUsesChanges: TLspUsesChanges;
    /// <summary>Nach der Tipp-Pause: ungespeicherten Stand in alle Ordner, die die Datei kennen.</summary>
    procedure ApplyTypedText(const AFileName, AText: string);
    procedure RefreshFailed(E: Exception);
    /// <summary>Ordnet eine Änderung ein: Einstellungen, Projektdatei (AReload) oder Quelltext (ASources).
    /// </summary>
    procedure Classify(const AChange: TFileChange; AReload: TList<TShellWorkspace>;
      var ASources: TArray<TFileChange>);
    /// <summary>Lädt die Ordner mit geänderter Projektdatei neu.</summary>
    procedure ReloadWorkspaces(AReload: TList<TShellWorkspace>);
    /// <summary>Geänderte Quelltexte in den Index und in die Projektprüfung.</summary>
    procedure ApplySources(const ASources: TArray<TFileChange>);
  public
    constructor Create(const AServices: TShellFileChangesServices);
    destructor Destroy; override;
    /// <summary>Meldet didChangeWatchedFiles am Dispatcher an.</summary>
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Meldet die Beobachtung beim Client an, sofern er sie kann.</summary>
    procedure RegisterWatchers(const AInitializeParams: TJSONObject);
    /// <summary>Beendet die Tipp-Pause; zuerst beim Beenden, weil eine laufende Übernahme die Ordner nutzt.
    /// </summary>
    procedure StopRefresh;
    /// <summary>Dateiänderungen von außen: Projektdateien laden neu, Quelltexte aktualisieren den Index.</summary>
    procedure Handle(const AChanges: TArray<TFileChange>);
    /// <summary>Dokument im Editor geändert oder geschlossen: Tipp-Pause bzw. Stand der Platte (#492).</summary>
    procedure DocumentEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
  end;

implementation

uses
  System.StrUtils,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.TreeCache;

constructor TShellFileChanges.Create(const AServices: TShellFileChangesServices);
begin
  inherited Create;
  FServices := AServices;
  FWatchedFiles := TLspWatchedFiles.Create(FServices.Transport);
  FWatchedFiles.OnChanged := Handle;
  FUsesChanges := TLspUsesChanges.Create;
  FIndexRefresh := TLspIndexRefresh.Create(TLspIndexRefresh.DefaultDelayMs, ApplyTypedText);
  FIndexRefresh.OnError := RefreshFailed;
end;

destructor TShellFileChanges.Destroy;
begin
  StopRefresh;
  FreeAndNil(FWatchedFiles);
  inherited Destroy;
end;

procedure TShellFileChanges.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  FWatchedFiles.Attach(ADispatcher);
end;

procedure TShellFileChanges.RegisterWatchers(const AInitializeParams: TJSONObject);
begin
  FWatchedFiles.RegisterWatchers(AInitializeParams);
end;

procedure TShellFileChanges.StopRefresh;
begin
  FreeAndNil(FIndexRefresh);
  FreeAndNil(FUsesChanges);
end;

procedure TShellFileChanges.ApplyTypedText(const AFileName, AText: string);
var
  mWorkspace: TShellWorkspace;
  mTargets: TArray<TShellWorkspace>;
  mUpdated: Boolean;
begin
  mUpdated := False;
  System.TMonitor.Enter(FServices.Workspaces.Lock);
  try
    mTargets := FServices.Workspaces.Items.ToArray;
  finally
    System.TMonitor.Exit(FServices.Workspaces.Lock);
  end;
  for mWorkspace in mTargets do
  begin
    if mWorkspace.ApplyText(AFileName, AText) then
    begin
      mUpdated := True;
    end;
  end;
  if mUpdated then
  begin
    FServices.Logger.Debug(Format('Index nach Tipp-Pause aktualisiert: %s', [ExtractFileName(AFileName)]));
  end;
  // Geänderte uses (#896): Ein Unit-Zyklus anderer offener Units kann über diese Unit laufen; der Graph
  // folgt dem Index, die Neuprüfung ist gebündelt.
  if mUpdated and FUsesChanges.Changed(AFileName, AText) then
  begin
    FServices.RefreshLater();
  end;
end;

procedure TShellFileChanges.RefreshFailed(E: Exception);
begin
  FServices.Logger.Warning('Index nach Tipp-Pause: ' + E.Message);
end;

procedure TShellFileChanges.DocumentEvent(AKind: TDocumentEventKind; const AFileName, AText: string);
begin
  if FIndexRefresh = nil then
  begin
    Exit;
  end;
  case AKind of
    TDocumentEventKind.Changed:
      begin
        FIndexRefresh.Changed(AFileName, AText);
        FServices.Typed();
      end;
    TDocumentEventKind.Closed:
      if TLspIndexRefresh.Applies(AFileName) then
      begin
        FIndexRefresh.Closed(AFileName);
        FUsesChanges.Forget(AFileName);
        Handle(TArray<TFileChange>.Create(TFileChange.Create(AFileName, TFileChangeKind.Changed)));
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TShellFileChanges.Handle(const AChanges: TArray<TFileChange>);
var
  mChange: TFileChange;
  mSources: TArray<TFileChange>;
  mReload: TList<TShellWorkspace>;
begin
  mSources := nil;
  mReload := TList<TShellWorkspace>.Create;
  try
    for mChange in AChanges do
    begin
      Classify(mChange, mReload, mSources);
    end;
    ReloadWorkspaces(mReload);
  finally
    mReload.Free;
  end;
  if Length(mSources) > 0 then
  begin
    ApplySources(mSources);
  end;
end;

procedure TShellFileChanges.Classify(const AChange: TFileChange; AReload: TList<TShellWorkspace>;
  var ASources: TArray<TFileChange>);
var
  mWorkspace: TShellWorkspace;
begin
  if FServices.Configuration.IsGlobalSettingsFile(AChange.FileName) then
  begin
    FServices.Configuration.LoadGlobalSettings;
  end
  else if IsConfigurationFileName(ExtractFileName(AChange.FileName)) then
  begin
    FServices.Configuration.FileChanged(AChange.FileName);
  end
  else if TLspWatchedFiles.IsProjectFile(AChange.FileName) then
  begin
    System.TMonitor.Enter(FServices.Workspaces.Lock);
    try
      mWorkspace := FServices.Workspaces.WorkspaceOf(AChange.FileName);
    finally
      System.TMonitor.Exit(FServices.Workspaces.Lock);
    end;
    // Nur der Thread der Nachrichtenschleife entfernt Ordner; mWorkspace bleibt gültig.
    if (mWorkspace <> nil) and not AReload.Contains(mWorkspace) then
    begin
      AReload.Add(mWorkspace);
    end;
  end
  // .inc (#264): der Index liest die einbindenden Units neu ein.
  else if MatchText(ExtractFileExt(AChange.FileName), ['.pas', '.dpr', '.inc']) then
  begin
    ASources := ASources + [AChange];
    // Editor-Bäume mit $I neu lesen (#860): Die Symbole der .inc wählen ihre Zweige.
    if SameText(ExtractFileExt(AChange.FileName), '.inc') then
    begin
      TSyntaxTreeCache.IncludesChanged;
      FServices.RefreshLater();
    end;
  end;
end;

procedure TShellFileChanges.ReloadWorkspaces(AReload: TList<TShellWorkspace>);
var
  mWorkspace: TShellWorkspace;
begin
  // Neu aufbauen: Suchpfade, Defines oder Units können sich geändert haben.
  for mWorkspace in AReload do
  begin
    FServices.Logger.Info(Format('Projektdatei in %s geändert, Symbolindex wird neu aufgebaut', [mWorkspace.Root]));
    mWorkspace.Reload;
  end;
end;

procedure TShellFileChanges.ApplySources(const ASources: TArray<TFileChange>);
var
  mWorkspace: TShellWorkspace;
  mChange: TFileChange;
  mUpdated: Integer;
  mNames: TArray<string>;
begin
  // Jeder Ordner aktualisiert die Units, die sein Aufbau kennt.
  mUpdated := 0;
  for mWorkspace in FServices.Workspaces.Items.ToArray do
  begin
    Inc(mUpdated, mWorkspace.ApplyChanges(ASources));
  end;
  FServices.Logger.Debug(Format('%d Dateiänderungen von außen, %d Units im Index aktualisiert',
    [Length(ASources), mUpdated]));
  mNames := nil;
  for mChange in ASources do
  begin
    mNames := mNames + [mChange.FileName];
  end;
  FServices.Affected(mNames);
end;

end.
