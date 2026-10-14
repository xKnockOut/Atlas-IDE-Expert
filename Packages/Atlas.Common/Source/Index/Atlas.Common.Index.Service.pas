unit Atlas.Common.Index.Service;

// Hält den Symbolindex und baut ihn in einem Hintergrund-Thread auf:
// Cache laden, Projektdateien und referenzierte Units indizieren, Cache
// schreiben. Ein neuer Start (z. B. nach geänderter Konfiguration) bricht
// den laufenden Aufbau ab und wartet auf ihn.
//
// Schreibt eine andere Instanz den Cache gerade (#62), wartet der Aufbau
// begrenzt, bis sie fertig ist oder die Sperre freigibt, und lädt dann ihren
// Stand, statt alles selbst noch einmal zu lesen.
//
// EnsureUnit parst ohne globale Sperre (#617): Die Sperre schützt nur den
// Zugriff auf den Builder und zählt seine Nutzer. Ein neuer Aufbau gibt den
// alten Builder erst frei, wenn ihn niemand mehr nutzt. So warten Hover und
// Vervollständigung nicht hintereinander auf das Parsen anderer Anfragen.
//
// Stufen (#648): Projektdateien, dann alle Units der Suchpfade, dann die
// Bibliothek. Mit einem gemeinsamen TIndexScheduler laufen die Aufbauten
// mehrerer Projekte nacheinander und stufenweise.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Builder,
  Atlas.Common.Index.Scheduler;

type
  TIndexRequest = record
    /// <summary>Projektdateien in Reihenfolge (Hauptdatei, Units).</summary>
    Files: TArray<string>;
    /// <summary>Alle Units der Projekt-Suchpfade (#648); gehören zum Projekt-Cache.</summary>
    SearchFiles: TArray<string>;
    /// <summary>Alle Units der Bibliotheks- und Suchpfade der Installation (#648); Bibliothek.</summary>
    LibraryFiles: TArray<string>;
    /// <summary>Reihenfolge unter mehreren Projekten; kleiner = früher (aktives Projekt 0).</summary>
    Priority: Integer;
    Defines: TArray<string>;
    /// <summary>Ordner der Installation und die Symbole, mit denen deren Units gelesen werden (#647);
    /// siehe TIndexBuilder.LibraryRoots.</summary>
    LibraryRoots: TArray<string>;
    LibraryDefines: TArray<string>;
    ResolveUnit: TUnitFileResolver;
    /// <summary>Suchpfade für $I-Dateien (#264).</summary>
    IncludePaths: TArray<string>;
    /// <summary>Cache-Datei; '' = ohne Cache.</summary>
    CacheFile: string;
    /// <summary>Gemeinsamer Cache der Units unter LibraryRoots (RTL/VCL/FMX) je Compilerversion und
    /// Plattform; '' = Bibliothek im Projekt-Cache (#492).</summary>
    LibraryCacheFile: string;
    /// <summary>Cache nur lesen, z. B. weil eine andere Instanz ihn schreibt (#184).</summary>
    ReadOnlyCache: Boolean;
    /// <summary>Hält eine andere Instanz die Sperre noch? nil = nicht warten (#62).</summary>
    CacheBusy: TFunc<Boolean>;
    /// <summary>Höchstens so lange auf die andere Instanz warten, in ms.</summary>
    CacheWaitMs: Integer;
  end;

  TIndexFinishedEvent = reference to procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64);
  TIndexErrorEvent = reference to procedure(const AError: Exception);

  TIndexService = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FThread: TThread;
    FCancelled: Boolean;
    FBuilder: TIndexBuilder;
    FLock: TObject;
    /// <summary>Anfragen, die FBuilder gerade nutzen; nur unter FLock ändern.</summary>
    FUsers: Integer;
    /// <summary>Hält ApplyText und ApplyChanges in Reihe; EnsureUnit wartet darauf nicht.</summary>
    FApplyLock: TObject;
    FOnProgress: TIndexProgressEvent;
    FOnFinished: TIndexFinishedEvent;
    FOnProjectReady: TIndexFinishedEvent;
    FOnError: TIndexErrorEvent;
    FScheduler: TIndexScheduler;
    procedure Run(const ARequest: TIndexRequest);
    /// <summary>Schreibt Projekt- und Bibliotheks-Cache; AParsed = seit dem letzten Schreiben neu gelesene Units.</summary>
    procedure WriteCaches(const ARequest: TIndexRequest; const ACached, ALibraryCached: TArray<TIndexCacheEntry>;
      AParsed: Integer);
    procedure WaitForOtherWriter(const ARequest: TIndexRequest);
    function AcquireBuilder: TIndexBuilder;
    procedure ReleaseBuilder;
    procedure ReplaceBuilder(ABuilder: TIndexBuilder);
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau im Hintergrund; ein laufender wird vorher abgebrochen.</summary>
    procedure Start(const ARequest: TIndexRequest);
    /// <summary>Bricht ab und wartet auf das Ende.</summary>
    procedure Stop;
    /// <summary>Wartet auf das Ende des Aufbaus (für Tests).</summary>
    procedure WaitFor;
    /// <summary>Indiziert eine Unit nachträglich (z. B. für die Namensauflösung).</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Übernimmt Dateiänderungen im aufrufenden Thread; 0 ohne laufenden Builder.</summary>
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Ungespeicherter Text einer Unit nach der Tipp-Pause (#492).</summary>
    function ApplyText(const AFileName, AText: string): Boolean;
    property Index: ISymbolIndex read FIndex;
    property OnProgress: TIndexProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TIndexFinishedEvent read FOnFinished write FOnFinished;
    /// <summary>Projektstufe fertig (Projektdateien und über uses erreichbare Units), Cache geschrieben;
    /// Suchpfade und Bibliothek folgen. Im Index-Thread, nicht bei Abbruch.</summary>
    property OnProjectReady: TIndexFinishedEvent read FOnProjectReady write FOnProjectReady;
    property OnError: TIndexErrorEvent read FOnError write FOnError;
    /// <summary>Gemeinsam für alle Projekte (#648); gehört dem Aufrufer, nil = ohne Reihenfolge.</summary>
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections;

type
  TIndexThread = class(TThread)
  private
    FService: TIndexService;
    FRequest: TIndexRequest;
  protected
    procedure Execute; override;
  public
    constructor Create(AService: TIndexService; const ARequest: TIndexRequest);
  end;

{ TIndexThread }

constructor TIndexThread.Create(AService: TIndexService; const ARequest: TIndexRequest);
begin
  FService := AService;
  FRequest := ARequest;
  inherited Create(False);
end;

procedure TIndexThread.Execute;
begin
  NameThreadForDebugging('Atlas.Index');
  FService.Run(FRequest);
end;

{ TIndexService }

constructor TIndexService.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FLock := TObject.Create;
  FApplyLock := TObject.Create;
end;

destructor TIndexService.Destroy;
begin
  Stop;
  ReplaceBuilder(nil);
  FApplyLock.Free;
  FLock.Free;
  inherited;
end;

/// <summary>Steht AUnit mit gleichem Stand (Zeitstempel, Prüfsumme) in AEntries?</summary>
function ContainsUnit(const AEntries: TArray<TIndexCacheEntry>; const AUnit: TUnitIndex): Boolean;
var
  Candidate: TIndexCacheEntry;
begin
  Result := False;
  for Candidate in AEntries do
    if SameText(Candidate.Header.FileName, AUnit.FileName) and (Candidate.Header.Stamp = AUnit.Stamp) and
      (Candidate.Header.Hash = AUnit.Hash) then
      Exit(True);
end;

function InSharedCache(const ARequest: TIndexRequest; const AFileName: string): Boolean;
begin
  // Ohne Installationsordner wie bisher: alle nachgeladenen Units in den gemeinsamen Cache.
  Result := (Length(ARequest.LibraryRoots) = 0) or TIndexBuilder.IsUnder(AFileName, ARequest.LibraryRoots);
end;

procedure TIndexService.WriteCaches(const ARequest: TIndexRequest; const ACached,
  ALibraryCached: TArray<TIndexCacheEntry>; AParsed: Integer);
var
  Entry: TIndexCacheEntry;
  ProjectUnits, LibraryUnits: TArray<TUnitIndex>;
  UnitIndex: TUnitIndex;
  Current: TDictionary<string, Boolean>;
  LibraryChanged: Boolean;
  Own: TDictionary<string, Boolean>;
  FileName: string;
begin
  if (ARequest.CacheFile = '') or ARequest.ReadOnlyCache then
    Exit;
  if ARequest.LibraryCacheFile = '' then
  begin
    if (AParsed > 0) or (Length(ACached) <> FIndex.UnitCount) then
      FFileSystem.WriteBytes(ARequest.CacheFile, TIndexCache.Serialize(FIndex.Units));
    Exit;
  end;
  // Getrennt schreiben: Projekt-Units ins Projekt, Bibliothek in den gemeinsamen Cache.
  ProjectUnits := nil;
  LibraryUnits := nil;
  // Der Index ist mit anderen Projekten geteilt: in den Projekt-Cache nur die eigenen Units.
  Own := TDictionary<string, Boolean>.Create;
  try
    for FileName in ARequest.Files + ARequest.SearchFiles do
      Own.AddOrSetValue(AnsiUpperCase(FileName), True);
    for UnitIndex in FIndex.Units do
      if UnitIndex.Library_ and InSharedCache(ARequest, UnitIndex.FileName) then
        LibraryUnits := LibraryUnits + [UnitIndex]
      else if UnitIndex.Library_ or Own.ContainsKey(AnsiUpperCase(UnitIndex.FileName)) then
        // Über uses erreichte Units außerhalb der Installation (gemeinsamer Firmencode) liest
        // der Builder mit den Defines des Projekts; sie gehören in dessen Cache (#647).
        ProjectUnits := ProjectUnits + [UnitIndex];
  finally
    Own.Free;
  end;
  if (AParsed > 0) or (Length(ACached) <> Length(ProjectUnits)) then
    FFileSystem.WriteBytes(ARequest.CacheFile, TIndexCache.Serialize(ProjectUnits));
  // Units anderer Projekte im gemeinsamen Cache behalten; neu sind nur die fehlenden.
  Current := TDictionary<string, Boolean>.Create;
  try
    for UnitIndex in LibraryUnits do
      Current.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), True);
    LibraryChanged := False;
    for UnitIndex in LibraryUnits do
      if not ContainsUnit(ALibraryCached, UnitIndex) then
        LibraryChanged := True;
    for Entry in ALibraryCached do
      if not Current.ContainsKey(AnsiUpperCase(Entry.Header.FileName)) and
        TIndexCache.Expand(Entry, UnitIndex) then
        LibraryUnits := LibraryUnits + [UnitIndex];
  finally
    Current.Free;
  end;
  if LibraryChanged then
    FFileSystem.WriteBytes(ARequest.LibraryCacheFile, TIndexCache.Serialize(LibraryUnits));
end;

procedure TIndexService.Run(const ARequest: TIndexRequest);
var
  Builder: TIndexBuilder;
  Cached, LibraryCached: TArray<TIndexCacheEntry>;
  Data: TBytes;
  Watch: TStopwatch;
  BuildResult: TIndexBuildResult;
  Turn: IIndexTurn;
  WrittenParsed: Integer;
  Request: TIndexRequest;
begin
  // Kopie für die anonyme Methode: const-Parameter lassen sich nicht einfangen.
  Request := ARequest;
  try
    Watch := TStopwatch.StartNew;
    Builder := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
    Builder.IncludePaths := ARequest.IncludePaths;
    Builder.LibraryRoots := ARequest.LibraryRoots;
    Builder.LibraryDefines := ARequest.LibraryDefines;
    WaitForOtherWriter(ARequest);
    Cached := nil;
    LibraryCached := nil;
    // Nur die Köpfe lesen; die Symbole dekodiert der Builder je Unit, wenn er sie übernimmt (#617).
    if (ARequest.CacheFile <> '') and FFileSystem.ReadBytes(ARequest.CacheFile, Data) then
      Cached := TIndexCache.ReadEntries(Data);
    // Bibliothek aus dem gemeinsamen Cache; Einträge im Projekt-Cache (ältere Stände) gelten weiter.
    if (ARequest.LibraryCacheFile <> '') and FFileSystem.ReadBytes(ARequest.LibraryCacheFile, Data) then
      LibraryCached := TIndexCache.ReadEntries(Data);
    Builder.UseCache(LibraryCached + Cached);
    // Erst mit gefülltem Cache veröffentlichen; bis dahin bedient der alte Builder EnsureUnit.
    ReplaceBuilder(Builder);
    Turn := nil;
    if FScheduler <> nil then
      Turn := FScheduler.Register(ARequest.Priority);
    WrittenParsed := 0;
    BuildResult := Builder.Build(ARequest.Files, ARequest.SearchFiles, ARequest.LibraryFiles, FOnProgress,
      function: Boolean
      begin
        Result := FCancelled;
      end, Turn,
      procedure(const APartial: TIndexBuildResult)
      begin
        // Nach der Projektstufe schon schreiben (#647): In einer Projektgruppe endet der ganze Aufbau
        // erst nach allen Projekten; wer die IDE vorher schließt, begann sonst jedes Mal von vorn.
        WriteCaches(Request, Cached, LibraryCached, APartial.Parsed);
        WrittenParsed := APartial.Parsed;
        if Assigned(FOnProjectReady) then
          FOnProjectReady(APartial, Watch.ElapsedMilliseconds);
      end);
    // Abmelden vor dem Schreiben des Caches: Das nächste Projekt muss darauf nicht warten.
    Turn := nil;
    if not BuildResult.Cancelled then
      WriteCaches(ARequest, Cached, LibraryCached, BuildResult.Parsed - WrittenParsed);
    if Assigned(FOnFinished) then
      FOnFinished(BuildResult, Watch.ElapsedMilliseconds);
  except
    on E: Exception do
      if Assigned(FOnError) then
        FOnError(E);
  end;
end;

procedure TIndexService.WaitForOtherWriter(const ARequest: TIndexRequest);
var
  Watch: TStopwatch;
  Before, Stamp: Int64;
begin
  if (ARequest.CacheFile = '') or not ARequest.ReadOnlyCache or not Assigned(ARequest.CacheBusy) then
    Exit;
  if not FFileSystem.FileStamp(ARequest.CacheFile, Before) then
    Before := 0;
  Watch := TStopwatch.StartNew;
  // Bis die andere Instanz einen neuen Stand geschrieben oder die Sperre freigegeben hat,
  // nie länger als CacheWaitMs.
  while not FCancelled and (Watch.ElapsedMilliseconds < ARequest.CacheWaitMs) and ARequest.CacheBusy() do
  begin
    if FFileSystem.FileStamp(ARequest.CacheFile, Stamp) and (Stamp <> Before) then
      Exit;
    TThread.Sleep(200);
  end;
end;

procedure TIndexService.Start(const ARequest: TIndexRequest);
begin
  Stop;
  FCancelled := False;
  FThread := TIndexThread.Create(Self, ARequest);
end;

procedure TIndexService.Stop;
begin
  if FThread = nil then
    Exit;
  FCancelled := True;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

procedure TIndexService.WaitFor;
begin
  if FThread <> nil then
    FThread.WaitFor;
end;

function TIndexService.AcquireBuilder: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBuilder;
    if Result <> nil then
      Inc(FUsers);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexService.ReleaseBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Dec(FUsers);
    if FUsers = 0 then
      TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexService.ReplaceBuilder(ABuilder: TIndexBuilder);
var
  Old: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    // Neue Anfragen sehen sofort den neuen Builder; der alte wird frei, sobald niemand ihn nutzt.
    Old := FBuilder;
    FBuilder := nil;
    while FUsers > 0 do
      TMonitor.Wait(FLock, INFINITE);
    FBuilder := ABuilder;
  finally
    TMonitor.Exit(FLock);
  end;
  Old.Free;
end;

function TIndexService.EnsureUnit(const AUnitName: string): Boolean;
var
  Builder: TIndexBuilder;
  Existing: TUnitIndex;
begin
  Builder := AcquireBuilder;
  if Builder = nil then
    Exit(FIndex.FindUnit(AUnitName, Existing));
  try
    Result := Builder.EnsureUnit(AUnitName);
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyText(const AFileName, AText: string): Boolean;
var
  Builder: TIndexBuilder;
begin
  Builder := AcquireBuilder;
  if Builder = nil then
    Exit(False);
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := Builder.ApplyText(AFileName, AText);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  Builder: TIndexBuilder;
begin
  Builder := AcquireBuilder;
  if Builder = nil then
    Exit(0);
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := Builder.ApplyChanges(AChanges);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

end.
