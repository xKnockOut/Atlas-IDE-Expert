unit Shell.Workspace.Indexing;

// Internals-Rolle Shell: Indexaufbau eines Arbeitsbereichs. Startet den Aufbau eines geladenen Projekts in den
// gemeinsamen Symbolindex (#648), mit Unit-Suche (#1016), Packages (#46), Cache-Sperre (#62, #184) und
// Fortschritt, und meldet Ende, Fehler und Cache-Ereignisse an Protokoll, Diagnoselog (#647) und Zustand.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.WorkDoneProgress,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Shell.Workspace.Setup,
  Shell.Workspace.State,
  Shell.Workspace.Cache,
  Shell.Workspace.Loader,
  Shell.Workspace.Encodings;

type
  /// <summary>Teile des Arbeitsbereichs, mit denen der Aufbau arbeitet; sie gehören dem Arbeitsbereich.</summary>
  TShellIndexingParts = record
    Name: string;
    Root: string;
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Index: ISymbolIndex;
    ProgressToken: string;
    Setup: TShellWorkspaceSetup;
    Events: TShellWorkspaceEvents;
    State: TShellProjectState;
    Cache: TShellWorkspaceCache;
  end;

  TShellWorkspaceIndexing = class
  private
    FParts: TShellIndexingParts;
    FService: TIndexService;
    FProgress: TLspWorkDoneProgress;
    FEncodings: TShellEncodingReport;
    FResolver: TUnitResolver;
    /// <summary>Frühere Resolver: Der alte Builder bedient EnsureUnit, bis der neue veröffentlicht ist,
    /// und ruft sie dabei noch auf. Freigabe erst mit dem Arbeitsbereich.</summary>
    FRetiredResolvers: TObjectList<TUnitResolver>;
    /// <summary>Schlüssel und Unit-Listen des letzten Aufbaus; gleich = nicht neu starten.</summary>
    FSignature: string;
    /// <summary>Beim nächsten Aufbau den Cache verwerfen (#49).</summary>
    FDiscardCache: Boolean;
    procedure Attach;
    procedure ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
    procedure CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
    procedure CacheRejected(const AFileName, AReason: string);
    procedure CacheNotWritten(const AFileName, AReason: string);
    procedure Failed(const AError: Exception);
    procedure IndexEvent(const AText: string);
    /// <summary>Package-Locator und Unit-Suche des Projekts in den Zustand (#46, #1016).</summary>
    function PublishLookups(const ALoaded: TShellLoadedProject): TPackageLocator;
    function NewResolver(const ALoaded: TShellLoadedProject): TUnitResolver;
    /// <summary>Sperre, Warten auf den Schreiber (#62) und Verwerfen (#49) des Caches.</summary>
    procedure PrepareCache(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
      var ARequest: TIndexRequest);
    procedure Publish(const ALoaded: TShellLoadedProject; const ARequest: TIndexRequest);
  public
    constructor Create(const AParts: TShellIndexingParts);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau für ALoaded; False, wenn sich Schlüssel und Unit-Listen seit dem letzten nicht
    /// geändert haben. Bricht einen laufenden Aufbau ab, ohne auf ihn zu warten (#874).</summary>
    function Start(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): Boolean;
    /// <summary>Nächster Start baut auch bei gleichem Schlüssel neu auf.</summary>
    procedure Forget;
    /// <summary>Nächster Start verwirft den Cache (#49).</summary>
    procedure DiscardNext;
    procedure Stop;
    function EnsureUnit(const AUnitName: string): Boolean;
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Fortschritt des laufenden Aufbaus in Prozent; -1, wenn keiner läuft (#647).</summary>
    function Loading: Integer;
    /// <summary>Stufe des laufenden Aufbaus und ob er auf sie wartet (#2142).</summary>
    function Stage: TIndexStageState;
    /// <summary>Token der $/progress-Meldungen dieses Arbeitsbereichs (#2142).</summary>
    function ProgressToken: string;
    /// <summary>Der gemeinsame Symbolindex.</summary>
    function Index: ISymbolIndex;
  end;

implementation

uses
  Shell.Workspace.Requests,
  System.StrUtils,
  Atlas.Common.Index.Adapters.DiskFileSystem,
  Atlas.Common.Index.Adapters.CacheDirectory,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Projects.UnitAliases,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Shell.Workspace.Listings,
  Shell.Workspace.Packages,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TWorkspaceIndexingText = (FromCache, Failed);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TWorkspaceIndexingText] of TAtlasText = (
    (De: 'Stand übernommen (%d Units aus dem Cache)'; En: 'State taken over (%d units from the cache)'),
    (De: 'Fehlgeschlagen'; En: 'Failed'));

const
  /// <summary>So lange wartet ein lesender Prozess höchstens auf den Cache des schreibenden (#62).</summary>
  cCacheWaitMs = 120000;

/// <summary>Neu eingelesene Units nach Grund und belegter Speicher, fürs Diagnoselog (Rückmeldung
/// 22.10.2026).</summary>
function MissText(const AResult: TIndexBuildResult): string;
begin
  Result := Format(' new %d changed %d includes %d usages %d compact %d damaged %d mem %d MB',
    [AResult.Misses[TIndexCacheMiss.NoEntry], AResult.Misses[TIndexCacheMiss.Changed],
     AResult.Misses[TIndexCacheMiss.Includes], AResult.Misses[TIndexCacheMiss.Usages],
     AResult.Misses[TIndexCacheMiss.Compact], AResult.Misses[TIndexCacheMiss.Damaged],
     TShutdownLeaks.AllocatedBytes div (1024 * 1024)]);
end;

/// <summary>Art des Caches an seinem Ordner: AProject, ALibrary oder ASearch.</summary>
function CacheKindOf(const AFileName, AProject, ALibrary, ASearch: string): string;
begin
  Result := AProject;
  if Pos(PathDelim + TIndexCacheDirectory.cLibraryFolder + PathDelim, AFileName) > 0 then
  begin
    Result := ALibrary;
  end
  else if Pos(PathDelim + TIndexCacheDirectory.cSearchFolder + PathDelim, AFileName) > 0 then
  begin
    Result := ASearch;
  end;
end;

/// <summary>Rückruf für TIndexRequest.ResolveUnit; fängt nur den Resolver ein.</summary>
function ResolveUnitOf(AResolver: TUnitResolver): TUnitFileResolver;
begin
  Result :=
    function(const AUnitName: string): string
    begin
      Result := AResolver.Resolve(AUnitName);
    end;
end;

/// <summary>Rückruf für TIndexRequest.CacheBusy; fängt nur die Datei ein.</summary>
function CacheBusyOf(const ACacheFile: string): TFunc<Boolean>;
begin
  Result :=
    function: Boolean
    begin
      Result := TIndexCacheDirectory.IsLocked(ACacheFile);
    end;
end;

{ TShellWorkspaceIndexing }

constructor TShellWorkspaceIndexing.Create(const AParts: TShellIndexingParts);
begin
  inherited Create;
  FParts := AParts;
  FRetiredResolvers := TObjectList<TUnitResolver>.Create(True);
  FEncodings := TShellEncodingReport.Create(AParts.Name, AParts.Root, AParts.Logger, AParts.Transport, AParts.Index);
  FService := TIndexService.Create(AParts.Index, TDiskIndexFileSystem.Create);
  FProgress := TLspWorkDoneProgress.Create(AParts.Transport, AParts.ProgressToken);
  Attach;
end;

destructor TShellWorkspaceIndexing.Destroy;
begin
  FService.Free;
  FProgress.Free;
  FResolver.Free;
  FRetiredResolvers.Free;
  FEncodings.Free;
  FParts := Default(TShellIndexingParts);
  inherited;
end;

procedure TShellWorkspaceIndexing.Attach;
begin
  FService.OnProgress := FProgress.AsIndexProgress();
  FService.OnProjectReady :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      ProjectReady(AResult, AElapsedMs);
    end;
  FService.OnFinished :=
    procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64)
    begin
      Finished(AResult, AElapsedMs);
    end;
  FService.OnCacheWritten :=
    procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64)
    begin
      CacheWritten(ALibrary, AUnits, ABytes, AElapsedMs);
    end;
  FService.OnCacheRejected :=
    procedure(const AFileName, AReason: string)
    begin
      CacheRejected(AFileName, AReason);
    end;
  FService.OnCacheNotWritten :=
    procedure(const AFileName, AReason: string)
    begin
      CacheNotWritten(AFileName, AReason);
    end;
  FService.OnError :=
    procedure(const AError: Exception)
    begin
      Failed(AError);
    end;
end;

procedure TShellWorkspaceIndexing.IndexEvent(const AText: string);
begin
  FParts.Events.IndexEvent(AText);
end;

procedure TShellWorkspaceIndexing.ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  FParts.State.ProjectPending := False;
  IndexEvent(Format('index project#%d projectStage %d ms parsed %d cached %d missing %d',
    [FParts.Setup.Priority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing]) + MissText(AResult));
  FParts.Events.ProjectReady;
end;

procedure TShellWorkspaceIndexing.Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  // Abgebrochen (Neustart): Der neue Aufbau hat ProjectPending schon wieder gesetzt.
  if not AResult.Cancelled then
  begin
    FParts.State.ProjectPending := False;
    FParts.State.Finished(AResult, AElapsedMs);
  end;
  IndexEvent(Format('index project#%d done %d ms parsed %d cached %d missing %d units %d resolve %d ms parse %d ms%s',
    [FParts.Setup.Priority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing, FParts.Index.UnitCount,
     AResult.ResolveMs, AResult.ParseMs, IfThen(AResult.Cancelled, ' cancelled', '')]) + MissText(AResult));
  FParts.Logger.Info(Format('Symbolindex für %s fertig in %d ms: %d Units, %d Symbole (%d neu eingelesen, %d aus dem Cache, %d fehlen)%s',
    [TLogMarks.Name(FParts.Name), AElapsedMs, FParts.Index.UnitCount, FParts.Index.SymbolCount, AResult.Parsed,
     AResult.FromCache, AResult.Missing, IfThen(AResult.Cancelled, ', abgebrochen', '')]));
  if AResult.Cancelled then
  begin
    Exit;
  end;
  // Prozesse am Projekt (#62): Der Schreiber hat gespeichert, ein Leser den Stand übernommen.
  if FParts.Cache.Writes then
  begin
    FParts.Cache.Report(TIndexProcessInfo.cStateReady, True, Format('Index gespeichert (%d Units)',
      [AResult.Parsed + AResult.FromCache]));
  end
  else
  begin
    FParts.Cache.Report(TIndexProcessInfo.cStateReady, False,
      cTexts[TWorkspaceIndexingText.FromCache].Fmt([AResult.FromCache]));
  end;
  FEncodings.Report(FParts.State.ProjectFiles);
  FParts.Events.IndexFinished;
end;

procedure TShellWorkspaceIndexing.CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
begin
  // Wie oft und wie groß geschrieben wird (Rückmeldung 22.10.2026); ohne Pfad. Das Zeilenformat ist festgelegt
  // (#1478, docs/Diagnose.md): Einheiten außer „MB“ am Ende klein, damit ^\S+ index project#\d+ \w+ [\d a-z]+ mem \d+
  // MB$
  // jede Speicherzeile trifft.
  IndexEvent(Format('index project#%d cacheWrite %s units %d %d kb %d ms mem %d MB',
    [FParts.Setup.Priority, IfThen(ALibrary, 'library', 'project'), AUnits, ABytes div 1024, AElapsedMs,
     TShutdownLeaks.AllocatedBytes div (1024 * 1024)]));
end;

procedure TShellWorkspaceIndexing.CacheRejected(const AFileName, AReason: string);
begin
  // Still neu aufbauen (#492): nur ins Log, keine Meldung an den Benutzer. Ohne Pfad: Das Log bleibt
  // anonym (der Cache liegt im Benutzerprofil). Welcher Cache und warum, steht auch im Diagnose-Log: Ohne
  // Grund war nicht zu sehen, warum ein Rechner bei jedem Start alles neu aufbaut (29.10.2026). Die Gründe
  // von TIndexCache.ReadEntries enthalten keinen Pfad.
  FParts.Logger.Info(Format('Index-Cache verworfen (%s); wird neu aufgebaut', [AReason]));
  IndexEvent(Format('index project#%d cache rejected %s reason %s', [FParts.Setup.Priority,
    CacheKindOf(AFileName, 'project', 'library', 'search'), AReason]));
  FParts.Cache.Report(TIndexProcessInfo.cStateBuilding, FParts.Cache.Writes, Format('Cache verworfen (%s)', [AReason]));
end;

procedure TShellWorkspaceIndexing.CacheNotWritten(const AFileName, AReason: string);
var
  mKind: string;
begin
  // Früher still. Der nächste Aufbau liest die fehlenden Units neu; ohne Pfad ins Log.
  mKind := CacheKindOf(AFileName, 'Projekt', 'Bibliothek', 'Suchpfade');
  FParts.Logger.Warning(Format('Index-Cache (%s) nicht geschrieben: %s', [mKind, AReason]));
  IndexEvent('index cache not written ' + mKind);
end;

procedure TShellWorkspaceIndexing.Failed(const AError: Exception);
begin
  // Sonst bliebe workspace/diagnostic bis zum nächsten Reload bei indexLoading.
  // Start hält den alten Lauf an, bevor es ProjectPending setzt: Das hier trifft nur den eigenen.
  FParts.State.ProjectPending := False;
  FParts.Logger.Error(Format('Fehler beim Aufbau des Symbolindex für %s: %s: %s', [TLogMarks.Name(FParts.Name),
    AError.ClassName,
      TLogMarks.Text(AError.Message)]));
  IndexEvent(Format('index project#%d failed %s', [FParts.Setup.Priority, AError.ClassName]));
  try
    // Ohne aktiven Fortschritt ein No-op.
    FProgress.Finish(cTexts[TWorkspaceIndexingText.Failed].Text);
  except
    // Transport schon geschlossen: Das Log genügt.
  end;
  // Teilweise aufgebauter Index: Syntaxprüfung und Pull-Diagnosen sollen ihn trotzdem nutzen.
  FParts.Events.IndexFinished;
end;

function TShellWorkspaceIndexing.PublishLookups(const ALoaded: TShellLoadedProject): TPackageLocator;
var
  mSource: TShellUnitLookupSource;
begin
  // requires-Packages (#46): Quelle .dpk in den Ordnern der Gruppe, im Projektordner und in den Suchpfaden,
  // übersetzt .dcp in den Bibliothekspfaden.
  Result := TPackageLocator.Create(FParts.Setup.PackageFolders + [ExtractFileDir(ALoaded.ProjectFile)] +
    ALoaded.Project.SearchPaths + ALoaded.CompilerLibraryPaths);
  mSource := Default(TShellUnitLookupSource);
  mSource.Project := ALoaded.Project;
  mSource.Installation := ALoaded.Installation;
  mSource.LibraryPaths := ALoaded.CompilerLibraryPaths;
  mSource.Packages := TPackageLocatorHold.Create(Result);
  mSource.Index := FParts.Index;
  // Unit-Aliase der .dproj (DCC_UnitAlias) für Namensauflösung und Vorschläge; die Vorgaben kennt der Index.
  FParts.Index.AddUnitAliases(TUnitAliases.OfProject(ALoaded.Project));
  if Assigned(FParts.Setup.OnGroupProjects) then
  begin
    mSource.GroupOutputsOf := TShellPackageLookups.GroupOutputsOf(FParts.Setup.OnGroupProjects,
      ALoaded.ProjectFile, ALoaded.Options, FParts.Logger);
  end;
  FParts.State.SetLookups(mSource.Packages, TShellPackageLookups.UnitLookupFor(mSource));
end;

function TShellWorkspaceIndexing.NewResolver(const ALoaded: TShellLoadedProject): TUnitResolver;
begin
  Result := TUnitResolver.Create(ALoaded.Project, ALoaded.LibraryPaths, TShellFileAccess.ExistsFunc());
  // Ordner einmal auflisten, über alle Projekte geteilt (CPU beim Start).
  Result.ListUnits := TSharedUnitListings.ListFunc();
  // Nicht freigeben: Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647).
  if FResolver <> nil then
  begin
    FRetiredResolvers.Add(FResolver);
  end;
  FResolver := Result;
end;

procedure TShellWorkspaceIndexing.PrepareCache(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings;
  var ARequest: TIndexRequest);
var
  mFiles: TShellCacheFiles;
begin
  mFiles := TShellCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ARequest.SearchCacheFile);
  ARequest.ReadOnlyCache := not FParts.Cache.Lock(mFiles, TShellIndexRequests.CacheOriginOf(ALoaded.Project,
    FParts.Root), ASettings);
  if ARequest.ReadOnlyCache then
  begin
    FParts.Logger.Info(Format('Cache %s wird von einer anderen Instanz geschrieben und hier nur gelesen',
      [TLogMarks.Path(ARequest.CacheFile)]));
    // Auf deren Stand warten statt alles doppelt zu lesen (#62), begrenzt.
    ARequest.CacheBusy := CacheBusyOf(ARequest.CacheFile);
    ARequest.CacheWaitMs := cCacheWaitMs;
  end;
  if FDiscardCache then
  begin
    FDiscardCache := False;
    // Im Index-Thread nach dem Ende des alten Aufbaus löschen: Sonst schriebe er den Cache danach wieder.
    if not ARequest.ReadOnlyCache then
    begin
      ARequest.Prepare := TShellWorkspaceCache.DiscardFiles(mFiles, FParts.Logger);
    end;
  end;
end;

procedure TShellWorkspaceIndexing.Publish(const ALoaded: TShellLoadedProject; const ARequest: TIndexRequest);
var
  mFiles: TShellIndexedFiles;
begin
  mFiles.Defines := ARequest.Defines;
  mFiles.Namespaces := ALoaded.Project.Namespaces;
  mFiles.SearchPaths := ALoaded.Project.SearchPaths;
  mFiles.ProjectFiles := ARequest.Files;
  mFiles.SearchFiles := ARequest.SearchFiles;
  FParts.State.SetIndexedFiles(mFiles);
  FParts.Cache.SetFiles(TShellCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ''));
end;

function TShellWorkspaceIndexing.Start(const ALoaded: TShellLoadedProject; const ASettings: TServerSettings): Boolean;
var
  mFiles: TShellIndexFiles;
  mTarget: TShellRequestTarget;
  mRequest: TIndexRequest;
  mKey: string;
begin
  mFiles := TShellIndexRequests.FilesOf(ALoaded, ASettings);
  TShellIndexRequests.AddPackageFiles(ALoaded.Project, PublishLookups(ALoaded), mFiles, FParts.Logger, FParts.Name);
  mKey := mFiles.Key(TIndexProjectFiles.Signature(ALoaded.Project, ALoaded.Version));
  Result := mKey <> FSignature;
  if not Result then
  begin
    Exit;
  end;
  FSignature := mKey;
  mTarget.CacheRoot := FParts.Setup.CacheRoot;
  mTarget.Priority := FParts.Setup.Priority;
  mTarget.Usages := ASettings.IndexUsages;
  mRequest := TShellIndexRequests.RequestOf(ALoaded, mFiles, mTarget);
  mRequest.ResolveUnit := ResolveUnitOf(NewResolver(ALoaded));
  FService.Scheduler := FParts.Setup.Scheduler;
  PrepareCache(ALoaded, ASettings, mRequest);
  Publish(ALoaded, mRequest);
  FParts.Logger.Info(Format('Symbolindex für %s (%s, %s): %d Projektdateien, %d Units der Suchpfade, %d der Bibliothek, Cache %s',
    [TLogMarks.Path(ALoaded.ProjectFile),
      TLogMarks.Name(ALoaded.Project.Config), TLogMarks.Name(ALoaded.Project.Platform), Length(mRequest.Files),
     Length(mRequest.SearchFiles), Length(mRequest.LibraryFiles), TLogMarks.Path(mRequest.CacheFile)]));
  IndexEvent(Format('index project#%d start files %d search %d library %d cache %s',
    [FParts.Setup.Priority, Length(mRequest.Files), Length(mRequest.SearchFiles), Length(mRequest.LibraryFiles),
     IfThen(mRequest.ReadOnlyCache, 'readOnly', 'write')]));
  FParts.State.ProjectPending := True;
  FService.Start(mRequest);
end;

procedure TShellWorkspaceIndexing.Forget;
begin
  FSignature := '';
end;

procedure TShellWorkspaceIndexing.DiscardNext;
begin
  FDiscardCache := True;
end;

procedure TShellWorkspaceIndexing.Stop;
begin
  FService.Stop;
end;

function TShellWorkspaceIndexing.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FService.EnsureUnit(AUnitName);
end;

function TShellWorkspaceIndexing.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FService.ApplyChanges(AChanges);
  if Result > 0 then
  begin
    FParts.State.Touch;
  end;
end;

function TShellWorkspaceIndexing.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FService.ApplyText(AFileName, AText);
  if Result then
  begin
    FParts.State.Touch;
  end;
end;

function TShellWorkspaceIndexing.Loading: Integer;
begin
  Result := -1;
  if FProgress.Active then
  begin
    Result := FProgress.Percent;
  end;
end;

function TShellWorkspaceIndexing.Stage: TIndexStageState;
begin
  Result := FService.StageState;
end;

function TShellWorkspaceIndexing.ProgressToken: string;
begin
  Result := FParts.ProgressToken;
end;

function TShellWorkspaceIndexing.Index: ISymbolIndex;
begin
  Result := FParts.Index;
end;

initialization
  TAtlasTextTables.Add('Shell.Workspace.Indexing', cTexts);

end.
