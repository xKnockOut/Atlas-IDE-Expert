unit Core.Workspace.Indexing;

// Host-Rolle Core: Indexaufbau eines Arbeitsbereichs. Startet den Aufbau eines geladenen Projekts in den
// gemeinsamen Symbolindex (#648), mit Unit-Suche (#1016), Packages (#46), Cache-Sperre (#62, #184) und
// Fortschritt, und meldet Ende, Fehler und Cache-Ereignisse an Protokoll, Diagnoselog (#647) und Zustand.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Logging.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.WorkDoneProgress,
  Atlas.Common.Projects.UnitResolver,
  Atlas.Common.Projects.PackageLocator,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Service,
  Atlas.Common.Index.Scheduler,
  Core.Workspace.Setup,
  Core.Workspace.State,
  Core.Workspace.Cache,
  Core.Workspace.Loader,
  Core.Workspace.Encodings;

type
  /// <summary>Teile des Arbeitsbereichs, mit denen der Aufbau arbeitet; sie gehören dem Arbeitsbereich.</summary>
  TCoreIndexingParts = record
    Name: string;
    Root: string;
    Logger: ILogger;
    Transport: IJsonRpcTransport;
    Index: ISymbolIndex;
    ProgressToken: string;
    Setup: TCoreWorkspaceSetup;
    Events: TCoreWorkspaceEvents;
    State: TCoreProjectState;
    Cache: TCoreWorkspaceCache;
  end;

  TCoreWorkspaceIndexing = class
  private
    FParts: TCoreIndexingParts;
    FService: TIndexService;
    FProgress: TWorkDoneProgress;
    FEncodings: TCoreEncodingReport;
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
    function PublishLookups(const ALoaded: TCoreLoadedProject): TPackageLocator;
    function NewResolver(const ALoaded: TCoreLoadedProject): TUnitResolver;
    /// <summary>Sperre, Warten auf den Schreiber (#62) und Verwerfen (#49) des Caches.</summary>
    procedure PrepareCache(const ALoaded: TCoreLoadedProject; const ASettings: TServerSettings;
      var ARequest: TIndexRequest);
    procedure Publish(const ALoaded: TCoreLoadedProject; const ARequest: TIndexRequest);
  public
    constructor Create(const AParts: TCoreIndexingParts);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau für ALoaded; False, wenn sich Schlüssel und Unit-Listen seit dem letzten nicht
    /// geändert haben. Bricht einen laufenden Aufbau ab, ohne auf ihn zu warten (#874).</summary>
    function Start(const ALoaded: TCoreLoadedProject; const ASettings: TServerSettings): Boolean;
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
  Core.Workspace.Requests,
  System.StrUtils,
  Atlas.Common.Index.CacheDirectory,
  Atlas.Common.Index.Processes,
  Atlas.Common.Index.ProjectFiles,
  Atlas.Common.Projects.UnitAliases,
  Atlas.Common.Diagnostics.ShutdownLeaks,
  Core.Workspace.Listings,
  Core.Workspace.Packages,
  Atlas.Text.LogMarks,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Reporting;

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

/// <summary>Neu eingelesene Units nach Grund und belegter Speicher, fürs Diagnoselog.
/// </summary>
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

{ TCoreWorkspaceIndexing }

constructor TCoreWorkspaceIndexing.Create(const AParts: TCoreIndexingParts);
begin
  inherited Create;
  FParts := AParts;
  FRetiredResolvers := TObjectList<TUnitResolver>.Create(True);
  FEncodings := TCoreEncodingReport.Create(AParts.Name, AParts.Root, AParts.Logger, AParts.Transport, AParts.Index);
  FService := TIndexService.Create(AParts.Index, AParts.Setup.Factories.IndexFileSystem());
  FProgress := TWorkDoneProgress.Create(AParts.Transport, AParts.ProgressToken);
  Attach;
end;

destructor TCoreWorkspaceIndexing.Destroy;
begin
  FService.Free;
  FProgress.Free;
  FResolver.Free;
  FRetiredResolvers.Free;
  FEncodings.Free;
  FParts := Default(TCoreIndexingParts);
  inherited;
end;

procedure TCoreWorkspaceIndexing.Attach;
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

procedure TCoreWorkspaceIndexing.ProjectReady(const AResult: TIndexBuildResult; AElapsedMs: Int64);
begin
  FParts.State.ProjectPending := False;
  IndexEvent(Format('index project#%d projectStage %d ms parsed %d cached %d missing %d',
    [FParts.Setup.Priority, AElapsedMs, AResult.Parsed, AResult.FromCache, AResult.Missing]) + MissText(AResult));
  FParts.Events.ProjectReady;
end;

procedure TCoreWorkspaceIndexing.Finished(const AResult: TIndexBuildResult; AElapsedMs: Int64);
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

procedure TCoreWorkspaceIndexing.CacheWritten(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);
begin
  // Wie oft und wie groß geschrieben wird; ohne Pfad. Das Zeilenformat ist festgelegt
  // (#1478, docs/Diagnose.md): Einheiten außer „MB“ am Ende klein, damit ^\S+ index project#\d+ \w+ [\d a-z]+ mem \d+
  // MB$
  // jede Speicherzeile trifft.
  IndexEvent(Format('index project#%d cacheWrite %s units %d %d kb %d ms mem %d MB',
    [FParts.Setup.Priority, IfThen(ALibrary, 'library', 'project'), AUnits, ABytes div 1024, AElapsedMs,
     TShutdownLeaks.AllocatedBytes div (1024 * 1024)]));
end;

procedure TCoreWorkspaceIndexing.CacheRejected(const AFileName, AReason: string);
begin
  // Still neu aufbauen (#492): nur ins Log, keine Meldung an den Benutzer. Ohne Pfad: Das Log bleibt
  // anonym (der Cache liegt im Benutzerprofil). Welcher Cache und warum, steht auch im Diagnose-Log: Ohne
  // Grund ist nicht zu sehen, warum ein Rechner bei jedem Start alles neu aufbaut. Die Gründe
  // von TIndexCache.ReadEntries enthalten keinen Pfad.
  FParts.Logger.Info(Format('Index-Cache verworfen (%s); wird neu aufgebaut', [AReason]));
  IndexEvent(Format('index project#%d cache rejected %s reason %s', [FParts.Setup.Priority,
    CacheKindOf(AFileName, 'project', 'library', 'search'), AReason]));
  FParts.Cache.Report(TIndexProcessInfo.cStateBuilding, FParts.Cache.Writes, Format('Cache verworfen (%s)', [AReason]));
end;

procedure TCoreWorkspaceIndexing.CacheNotWritten(const AFileName, AReason: string);
var
  mKind: string;
begin
  // Nicht still, sonst bleibt unklar, warum Units fehlen. Der nächste Aufbau liest die fehlenden Units neu;
  // ohne Pfad ins Log.
  mKind := CacheKindOf(AFileName, 'Projekt', 'Bibliothek', 'Suchpfade');
  FParts.Logger.Warning(Format('Index-Cache (%s) nicht geschrieben: %s', [mKind, AReason]));
  IndexEvent('index cache not written ' + mKind);
end;

procedure TCoreWorkspaceIndexing.Failed(const AError: Exception);
begin
  // Sonst bliebe workspace/diagnostic bis zum nächsten Reload bei indexLoading.
  // Start hält den alten Lauf an, bevor es ProjectPending setzt: Das hier trifft nur den eigenen.
  FParts.State.ProjectPending := False;
  FParts.Logger.Error(Format('Fehler beim Aufbau des Symbolindex für %s: %s: %s', [TLogMarks.Name(FParts.Name),
    AError.ClassName,
      TLogMarks.Text(AError.Message)]));
  IndexEvent(Format('index project#%d failed %s', [FParts.Setup.Priority, AError.ClassName]));
  // Ohne aktiven Fortschritt ein No-op; ist der Transport schon geschlossen, genügt das Log oben.
  TReporting.Quietly(
    procedure
    begin
      FProgress.Finish(cTexts[TWorkspaceIndexingText.Failed].Text);
    end);
  // Teilweise aufgebauter Index: Syntaxprüfung und Pull-Diagnosen sollen ihn trotzdem nutzen.
  FParts.Events.IndexFinished;
end;

procedure TCoreWorkspaceIndexing.IndexEvent(const AText: string);
begin
  FParts.Events.IndexEvent(AText);
end;

function TCoreWorkspaceIndexing.PublishLookups(const ALoaded: TCoreLoadedProject): TPackageLocator;
var
  mSource: TCoreUnitLookupSource;
begin
  // requires-Packages (#46): Quelle .dpk in den Ordnern der Gruppe, im Projektordner und in den Suchpfaden,
  // übersetzt .dcp in den Bibliothekspfaden.
  Result := TPackageLocator.Create(FParts.Setup.PackageFolders + [ExtractFileDir(ALoaded.ProjectFile)] +
    ALoaded.Project.SearchPaths + ALoaded.CompilerLibraryPaths);
  mSource := Default(TCoreUnitLookupSource);
  mSource.Project := ALoaded.Project;
  mSource.Installation := ALoaded.Installation;
  mSource.LibraryPaths := ALoaded.CompilerLibraryPaths;
  mSource.Packages := TPackageLocatorHold.Create(Result);
  mSource.Index := FParts.Index;
  mSource.CreateLookup := FParts.Setup.Factories.UnitLookup;
  // Unit-Aliase der .dproj (DCC_UnitAlias) für Namensauflösung und Vorschläge; die Vorgaben kennt der Index.
  FParts.Index.AddUnitAliases(TUnitAliases.OfProject(ALoaded.Project));
  if Assigned(FParts.Setup.OnGroupProjects) then
  begin
    mSource.GroupOutputsOf := TCorePackageLookups.GroupOutputsOf(FParts.Setup.OnGroupProjects,
      ALoaded.ProjectFile, ALoaded.Options, FParts.Logger);
  end;
  FParts.State.SetLookups(mSource.Packages, TCorePackageLookups.UnitLookupFor(mSource));
end;

function TCoreWorkspaceIndexing.NewResolver(const ALoaded: TCoreLoadedProject): TUnitResolver;
begin
  Result := TUnitResolver.Create(ALoaded.Project, ALoaded.LibraryPaths, TCoreFileAccess.ExistsFunc());
  // Ordner einmal auflisten, über alle Projekte geteilt (CPU beim Start).
  Result.ListUnits := TSharedUnitListings.ListFunc();
  // Nicht freigeben: Anfragen können den alten Builder noch nutzen (EnsureUnit ohne Sperre, #647).
  if FResolver <> nil then
  begin
    FRetiredResolvers.Add(FResolver);
  end;
  FResolver := Result;
end;

procedure TCoreWorkspaceIndexing.PrepareCache(const ALoaded: TCoreLoadedProject; const ASettings: TServerSettings;
  var ARequest: TIndexRequest);
var
  mFiles: TCoreCacheFiles;
begin
  mFiles := TCoreCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ARequest.SearchCacheFile);
  ARequest.ReadOnlyCache := not FParts.Cache.Lock(mFiles, TCoreIndexRequests.CacheOriginOf(ALoaded.Project,
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
      ARequest.Prepare := TCoreWorkspaceCache.DiscardFiles(mFiles, FParts.Logger);
    end;
  end;
end;

procedure TCoreWorkspaceIndexing.Publish(const ALoaded: TCoreLoadedProject; const ARequest: TIndexRequest);
var
  mFiles: TCoreIndexedFiles;
begin
  mFiles.Defines := ARequest.Defines;
  mFiles.Namespaces := ALoaded.Project.Namespaces;
  mFiles.SearchPaths := ALoaded.Project.SearchPaths;
  mFiles.ProjectFiles := ARequest.Files;
  mFiles.SearchFiles := ARequest.SearchFiles;
  FParts.State.SetIndexedFiles(mFiles);
  FParts.Cache.SetFiles(TCoreCacheFiles.Create(ARequest.CacheFile, ARequest.LibraryCacheFile, ''));
end;

function TCoreWorkspaceIndexing.Start(const ALoaded: TCoreLoadedProject; const ASettings: TServerSettings): Boolean;
var
  mFiles: TCoreIndexFiles;
  mTarget: TCoreRequestTarget;
  mRequest: TIndexRequest;
  mKey: string;
begin
  mFiles := TCoreIndexRequests.FilesOf(ALoaded, ASettings);
  TCoreIndexRequests.AddPackageFiles(ALoaded.Project, PublishLookups(ALoaded), mFiles, FParts.Logger, FParts.Name);
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
  mRequest := TCoreIndexRequests.RequestOf(ALoaded, mFiles, mTarget);
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

procedure TCoreWorkspaceIndexing.Forget;
begin
  FSignature := '';
end;

procedure TCoreWorkspaceIndexing.DiscardNext;
begin
  FDiscardCache := True;
end;

procedure TCoreWorkspaceIndexing.Stop;
begin
  FService.Stop;
end;

function TCoreWorkspaceIndexing.EnsureUnit(const AUnitName: string): Boolean;
begin
  Result := FService.EnsureUnit(AUnitName);
end;

function TCoreWorkspaceIndexing.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  Result := FService.ApplyChanges(AChanges);
  if Result > 0 then
  begin
    FParts.State.Touch;
  end;
end;

function TCoreWorkspaceIndexing.ApplyText(const AFileName, AText: string): Boolean;
begin
  Result := FService.ApplyText(AFileName, AText);
  if Result then
  begin
    FParts.State.Touch;
  end;
end;

function TCoreWorkspaceIndexing.Loading: Integer;
begin
  Result := -1;
  if FProgress.Active then
  begin
    Result := FProgress.Percent;
  end;
end;

function TCoreWorkspaceIndexing.Stage: TIndexStageState;
begin
  Result := FService.StageState;
end;

function TCoreWorkspaceIndexing.ProgressToken: string;
begin
  Result := FParts.ProgressToken;
end;

function TCoreWorkspaceIndexing.Index: ISymbolIndex;
begin
  Result := FParts.Index;
end;

initialization
  TAtlasTextTables.Add('Core.Workspace.Indexing', cTexts);

end.
