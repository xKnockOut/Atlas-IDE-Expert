unit Shell.Workspace.Cache;

// Internals-Rolle Shell: Index-Cache eines Arbeitsbereichs. Sperre des eigenen Caches (#184), Anmeldung des
// Prozesses daran (#62), Aufräumen des Cache-Ordners (#905, #616) und Verwerfen beim Neuaufbau (#49).

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Logging.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.Adapters.Processes,
  Shell.Workspace.Setup;

type
  /// <summary>Cache-Dateien eines Aufbaus: Projekt, gemeinsame Bibliothek (#647) und Suchpfade ('' ohne).</summary>
  TShellCacheFiles = record
    ProjectFile: string;
    LibraryFile: string;
    SearchFile: string;
    class function Create(const AProject, ALibrary, ASearch: string): TShellCacheFiles; static;
  end;

  TShellWorkspaceCache = class
  private
    FName: string;
    FLogger: ILogger;
    FSetup: TShellWorkspaceSetup;
    FEvents: TShellWorkspaceEvents;
    // Schützt Anmeldung und Dateien, die Anfrage-Threads lesen.
    FLock: TObject;
    /// <summary>Sperre des eigenen Index-Caches (#184); nil, wenn eine andere Instanz ihn hält.</summary>
    FCacheLock: TStream;
    FCacheLockFile: string;
    /// <summary>Cache-Dateien des laufenden Aufbaus (#492).</summary>
    FFiles: TShellCacheFiles;
    /// <summary>Anmeldung am eigenen Index-Cache für „Prozesse am Projekt“ (#62).</summary>
    FProcessEntry: TIndexProcessEntry;
    /// <summary>Löscht verwaiste, ungenutzte und zu viele Caches; AKeep bleibt stehen (#616).</summary>
    procedure Housekeep(const AKeep: TArray<string>; const ASettings: TServerSettings);
    procedure LogRemoved(ARemoved: Integer; const AText: string);
  public
    constructor Create(const AName: string; const ALogger: ILogger; ASetup: TShellWorkspaceSetup;
      AEvents: TShellWorkspaceEvents);
    destructor Destroy; override;
    /// <summary>Sperrt AFiles.ProjectFile, gibt eine alte Sperre frei; False = nur lesen. Vermerkt Herkunft (AOrigin)
    /// und Benutzung und räumt den Cache-Ordner nach ASettings auf (#905); dabei bleiben die Dateien von AFiles
    /// stehen (#616).</summary>
    function Lock(const AFiles: TShellCacheFiles; const AOrigin: string; const ASettings: TServerSettings): Boolean;
    /// <summary>Gibt die Sperre frei, damit „Index löschen“ (#492) den Cache entfernen kann.</summary>
    procedure Release;
    /// <summary>Meldet den eigenen Prozess am Cache an bzw. um (#62) und hält Zustand und Ereignis fest.</summary>
    procedure Report(const ACacheFile, AState: string; AWriter: Boolean; const AEvent: string); overload;
    /// <summary>Nur ein Ereignis am angemeldeten Cache; ohne Anmeldung nichts.</summary>
    procedure Report(const AState: string; AWriter: Boolean; const AEvent: string); overload;
    /// <summary>Name des Clients für die Anmeldung, auch nachträglich (#1883).</summary>
    procedure SetClient(const AClient: string);
    /// <summary>Hält dieser Arbeitsbereich die Sperre seines Caches (laut Anmeldung, #62)?</summary>
    function Writes: Boolean;
    /// <summary>Cache-Dateien des laufenden Aufbaus. Threadsicher.</summary>
    function Files: TShellCacheFiles;
    procedure SetFiles(const AFiles: TShellCacheFiles);
    /// <summary>Eigener Index-Cache und die daran angemeldeten Prozesse (#62); False ohne Cache. Threadsicher.
    /// </summary>
    function Processes(out ACacheFile: string; out AProcesses: TArray<TIndexProcessInfo>): Boolean;
    /// <summary>Löscht die Dateien von AFiles; läuft als TIndexRequest.Prepare im Index-Thread.</summary>
    class function DiscardFiles(const AFiles: TShellCacheFiles; const ALogger: ILogger): TProc; static;
  end;

implementation

uses
  System.IOUtils,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.CacheHousekeeping,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TWorkspaceCacheText = (Released, Updating, Locked, ReadOnly);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TWorkspaceCacheText] of TAtlasText = (
    (De: 'Sperre freigegeben (Index löschen)'; En: 'Lock released (clear index)'),
    (De: 'Index wird aktualisiert'; En: 'Index is being updated'),
    (De: 'Cache-Sperre erhalten, Index wird aufgebaut'; En: 'Cache lock acquired, index is being built'),
    (De: 'Sperre belegt, lade Cache nur lesend'; En: 'Lock taken, loading the cache read-only'));

{ TShellCacheFiles }

class function TShellCacheFiles.Create(const AProject, ALibrary, ASearch: string): TShellCacheFiles;
begin
  Result.ProjectFile := AProject;
  Result.LibraryFile := ALibrary;
  Result.SearchFile := ASearch;
end;

{ TShellWorkspaceCache }

constructor TShellWorkspaceCache.Create(const AName: string; const ALogger: ILogger; ASetup: TShellWorkspaceSetup;
  AEvents: TShellWorkspaceEvents);
begin
  inherited Create;
  FName := AName;
  FLogger := ALogger;
  FSetup := ASetup;
  FEvents := AEvents;
  FLock := TObject.Create;
end;

destructor TShellWorkspaceCache.Destroy;
begin
  FCacheLock.Free;
  FProcessEntry.Free;
  FLock.Free;
  FLogger := nil;
  inherited;
end;

procedure TShellWorkspaceCache.Report(const ACacheFile, AState: string; AWriter: Boolean; const AEvent: string);
var
  mIdentity: TIndexProcessInfo;
begin
  TMonitor.Enter(FLock);
  try
    if (FProcessEntry = nil) or not SameText(FProcessEntry.CacheFile, ACacheFile) then
    begin
      FreeAndNil(FProcessEntry);
      mIdentity := FSetup.ProcessIdentity;
      mIdentity.Workspace := FName;
      if mIdentity.Kind = '' then
      begin
        mIdentity.Kind := TIndexProcessInfo.cKindLsp;
      end;
      FProcessEntry := TIndexProcessEntry.Create(ACacheFile, mIdentity);
    end;
    FProcessEntry.Update(AState, AWriter, AEvent);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspaceCache.SetClient(const AClient: string);
var
  mIdentity: TIndexProcessInfo;
begin
  TMonitor.Enter(FLock);
  try
    mIdentity := FSetup.ProcessIdentity;
    mIdentity.Client := AClient;
    FSetup.ProcessIdentity := mIdentity;
    if FProcessEntry <> nil then
    begin
      FProcessEntry.SetClient(AClient);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspaceCache.Report(const AState: string; AWriter: Boolean; const AEvent: string);
begin
  TMonitor.Enter(FLock);
  try
    if FProcessEntry <> nil then
    begin
      FProcessEntry.Update(AState, AWriter, AEvent);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceCache.Writes: Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := (FProcessEntry <> nil) and FProcessEntry.Info.Writer;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceCache.Files: TShellCacheFiles;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TShellWorkspaceCache.SetFiles(const AFiles: TShellCacheFiles);
begin
  TMonitor.Enter(FLock);
  try
    FFiles := AFiles;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TShellWorkspaceCache.Processes(out ACacheFile: string; out AProcesses: TArray<TIndexProcessInfo>): Boolean;
begin
  ACacheFile := Files.ProjectFile;
  AProcesses := nil;
  Result := ACacheFile <> '';
  if Result then
  begin
    AProcesses := TIndexProcesses.List(ACacheFile);
  end;
end;

procedure TShellWorkspaceCache.Release;
begin
  FreeAndNil(FCacheLock);
  FCacheLockFile := '';
  Report(TIndexProcessInfo.cStateReady, False, cTexts[TWorkspaceCacheText.Released].Text);
end;

function TShellWorkspaceCache.Lock(const AFiles: TShellCacheFiles; const AOrigin: string;
  const ASettings: TServerSettings): Boolean;
begin
  if SameText(AFiles.ProjectFile, FCacheLockFile) and (FCacheLock <> nil) then
  begin
    Report(AFiles.ProjectFile, TIndexProcessInfo.cStateBuilding, True, cTexts[TWorkspaceCacheText.Updating].Text);
    Exit(True);
  end;
  FreeAndNil(FCacheLock);
  FCacheLockFile := AFiles.ProjectFile;
  FCacheLock := TIndexCacheDirectory.TryLock(AFiles.ProjectFile);
  Result := FCacheLock <> nil;
  // Für „Prozesse am Projekt“ (#62): wer schreibt, wer nur liest.
  if Result then
  begin
    Report(AFiles.ProjectFile, TIndexProcessInfo.cStateBuilding, True, cTexts[TWorkspaceCacheText.Locked].Text);
  end
  else
  begin
    Report(AFiles.ProjectFile, TIndexProcessInfo.cStateReading, False, cTexts[TWorkspaceCacheText.ReadOnly].Text);
  end;
  try
    // Herkunft und Benutzung vermerken (#905): Danach erkennt jede Instanz verwaiste und ungenutzte Caches.
    if Result then
    begin
      TIndexCacheDirectory.WriteOrigin(AFiles.ProjectFile, AOrigin);
    end;
    TIndexCacheDirectory.TouchUse(AFiles.ProjectFile);
    TIndexCacheDirectory.TouchUse(AFiles.LibraryFile);
    TIndexCacheDirectory.TouchUse(AFiles.SearchFile);
    // Der gemeinsame Bibliotheks-Cache ist nicht gesperrt; ohne ihn hier zu nennen, löschte das Aufräumen
    // ihn bei jedem Start, sobald der Ordner über der Höchstgröße lag (#616: "0 aus dem Cache").
    Housekeep(TArray<string>.Create(AFiles.ProjectFile, AFiles.LibraryFile, AFiles.SearchFile), ASettings);
  except
    on E: Exception do
      FLogger.Warning(Format('Aufräumen des Cache-Ordners fehlgeschlagen: %s', [TLogMarks.Text(E.Message)]));
  end;
end;

procedure TShellWorkspaceCache.LogRemoved(ARemoved: Integer; const AText: string);
begin
  if ARemoved > 0 then
  begin
    FLogger.Info(Format(AText, [ARemoved]));
  end;
end;

procedure TShellWorkspaceCache.Housekeep(const AKeep: TArray<string>; const ASettings: TServerSettings);
var
  mRemoved: Integer;
begin
  // Im Log nur Anzahlen, keine Pfade (anonymes Server-Log).
  if ASettings.IndexRemoveOrphans then
  begin
    LogRemoved(TIndexCacheDirectory.RemoveOrphans(FSetup.CacheRoot, AKeep),
      '%d verwaiste Index-Caches gelöscht (Projekt nicht mehr vorhanden)');
  end;
  LogRemoved(TIndexCacheDirectory.RemoveUnused(FSetup.CacheRoot, ASettings.IndexCacheMaxAgeDays, AKeep),
    '%d Index-Caches gelöscht (länger als ' + IntToStr(ASettings.IndexCacheMaxAgeDays) + ' Tage nicht benutzt)');
  mRemoved := TIndexCacheDirectory.Cleanup(FSetup.CacheRoot,
    TIndexCacheHousekeeping.MaxBytesOf(ASettings.IndexCacheMaxMb), AKeep);
  if mRemoved > 0 then
  begin
    FLogger.Info(Format('%d alte Index-Caches gelöscht (Höchstgröße %d MB)', [mRemoved, ASettings.IndexCacheMaxMb]));
    // Auch ins Diagnose-Log: Ohne --log stand es nirgends, und gelöschte Caches anderer Projektgruppen sahen
    // aus wie ein Cache, der nicht greift (29.10.2026).
    FEvents.IndexEvent(Format('index project#%d cacheCleanup removed %d limit %d MB', [FSetup.Priority, mRemoved,
      ASettings.IndexCacheMaxMb]));
  end;
end;

/// <summary>Löscht AFileName, falls vorhanden.</summary>
procedure DeleteIfExists(const AFileName: string);
begin
  if (AFileName <> '') and TFile.Exists(AFileName) then
  begin
    TFile.Delete(AFileName);
  end;
end;

/// <summary>Rumpf von TShellWorkspaceCache.DiscardFiles; eigene Routine, damit die anonyme Methode nur die
/// Parameter einfängt.</summary>
procedure DiscardNow(const AFiles: TShellCacheFiles; const ALogger: ILogger);
begin
  if not TFile.Exists(AFiles.ProjectFile) then
  begin
    Exit;
  end;
  try
    TFile.Delete(AFiles.ProjectFile);
    DeleteIfExists(AFiles.LibraryFile);
    DeleteIfExists(AFiles.SearchFile);
    ALogger.Info('Index-Cache verworfen: ' + TLogMarks.Path(ExtractFileName(AFiles.ProjectFile)));
  except
    on E: Exception do
      ALogger.Warning(Format('Index-Cache %s nicht löschbar: %s', [TLogMarks.Path(ExtractFileName(AFiles.ProjectFile)),
        E.ClassName]));
  end;
end;

class function TShellWorkspaceCache.DiscardFiles(const AFiles: TShellCacheFiles; const ALogger: ILogger): TProc;
var
  mFiles: TShellCacheFiles;
  mLogger: ILogger;
begin
  mFiles := AFiles;
  mLogger := ALogger;
  Result :=
    procedure
    begin
      DiscardNow(mFiles, mLogger);
    end;
end;

initialization
  TAtlasTextTables.Add('Shell.Workspace.Cache', cTexts);

end.
