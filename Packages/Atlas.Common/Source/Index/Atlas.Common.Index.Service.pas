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
// Ein beschädigter Cache (falsche Prüfsumme, abgeschnitten, andere
// Formatversion, #492) wird nur über OnCacheRejected gemeldet; der Aufbau
// liest dann alles neu und schreibt den Cache wieder, ohne Meldung an den
// Benutzer. UsagesOf liefert die Verwendungen einer Unit auch dann, wenn sie
// wegen des Speicherbudgets ausgelagert sind: aus dem Cache, sonst aus der
// Datei.
//
// Stufen (#648): Projektdateien, dann alle Units der Suchpfade, dann die
// Bibliothek. Mit einem gemeinsamen TIndexScheduler laufen die Aufbauten
// mehrerer Projekte nacheinander und stufenweise.
//
// Speicher (Rückmeldung 15.10.2026, 1,5 GB bei sechs Projekten): Den
// gemeinsamen Bibliotheks-Cache lesen alle Dienste eines Prozesses nur einmal
// (TSharedCacheReads), und nach einem vollständigen Aufbau gibt der Builder
// seine Cache-Einträge frei. Vorher hielt jedes Projekt seinen Projekt- und
// eine eigene Kopie des Bibliotheks-Caches bis zum nächsten Aufbau.

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
    /// <summary>Verwendungen der Bezeichner in Projekt-Units erfassen (#492, index.usages).</summary>
    Usages: Boolean;
  end;

  /// <summary>Cache-Datei verworfen; AReason z. B. "Prüfsumme stimmt nicht" (#492).</summary>
  TIndexCacheRejectedEvent = reference to procedure(const AFileName, AReason: string);

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
    FOnCacheRejected: TIndexCacheRejectedEvent;
    /// <summary>Cache-Datei des letzten Aufbaus; nur unter FLock.</summary>
    FCacheFile: string;
    procedure Run(const ARequest: TIndexRequest);
    function ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
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
    /// <summary>Verwendungen der Bezeichner in AFileName (#492): aus dem Speicher, bei ausgelagerten aus dem
    /// Cache, sonst frisch aus der Datei. False, wenn die Unit nicht im Index ist oder keine erfasst wurden.</summary>
    function UsagesOf(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
    property Index: ISymbolIndex read FIndex;
    property OnCacheRejected: TIndexCacheRejectedEvent read FOnCacheRejected write FOnCacheRejected;
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
  /// <summary>Gemeinsam gelesener Bibliotheks-Cache: Alle Dienste eines Prozesses teilen eine Kopie, solange
  /// jemand sie nutzt; Schlüssel ist Dateisystem und Datei, gültig für einen Zeitstempel.</summary>
  TSharedCacheReads = class
  private type
    TShared = class
      Stamp: Int64;
      Entries: TArray<TIndexCacheEntry>;
      Users: Integer;
    end;
  private
    class var FLock: TObject;
    class var FFiles: TObjectDictionary<string, TShared>;
    class function KeyOf(const AFileSystem: IIndexFileSystem; const AFileName: string): string; static;
  public
    class constructor Create;
    class destructor Destroy;
    /// <summary>Einträge von AFileName; liest nur, wenn niemand denselben Stand hält. AStamp merkt sich der
    /// Aufrufer für Release.</summary>
    class function Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string; out AStamp: Int64;
      const ARead: TFunc<TArray<TIndexCacheEntry>>): TArray<TIndexCacheEntry>; static;
    class procedure Release(const AFileSystem: IIndexFileSystem; const AFileName: string; AStamp: Int64); static;
    /// <summary>Zahl der gehaltenen Dateien (für Tests).</summary>
    class function HeldCount: Integer; static;
  end;

class constructor TSharedCacheReads.Create;
begin
  FLock := TObject.Create;
  FFiles := TObjectDictionary<string, TShared>.Create([doOwnsValues]);
end;

class destructor TSharedCacheReads.Destroy;
begin
  FFiles.Free;
  FLock.Free;
end;

class function TSharedCacheReads.KeyOf(const AFileSystem: IIndexFileSystem; const AFileName: string): string;
begin
  Result := IntToHex(NativeInt(Pointer(AFileSystem)), 16) + '|' + AnsiUpperCase(AFileName);
end;

class function TSharedCacheReads.Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
  out AStamp: Int64; const ARead: TFunc<TArray<TIndexCacheEntry>>): TArray<TIndexCacheEntry>;
var
  Key: string;
  Shared: TShared;
begin
  if not AFileSystem.FileStamp(AFileName, AStamp) then
    AStamp := -1;
  Key := KeyOf(AFileSystem, AFileName);
  // Unter der Sperre lesen: Ein zweiter Dienst wartet lieber, als dieselbe Datei ein zweites Mal zu laden.
  TMonitor.Enter(FLock);
  try
    if FFiles.TryGetValue(Key, Shared) and (Shared.Stamp = AStamp) then
    begin
      Inc(Shared.Users);
      Exit(Shared.Entries);
    end;
    Shared := TShared.Create;
    Shared.Stamp := AStamp;
    Shared.Entries := ARead();
    Shared.Users := 1;
    FFiles.AddOrSetValue(Key, Shared);
    Result := Shared.Entries;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSharedCacheReads.Release(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AStamp: Int64);
var
  Key: string;
  Shared: TShared;
begin
  Key := KeyOf(AFileSystem, AFileName);
  TMonitor.Enter(FLock);
  try
    // Anderer Stand: Der Eintrag wurde schon ersetzt; die eigene Kopie hält der Aufrufer selbst.
    if not FFiles.TryGetValue(Key, Shared) or (Shared.Stamp <> AStamp) then
      Exit;
    Dec(Shared.Users);
    if Shared.Users <= 0 then
      FFiles.Remove(Key);
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TSharedCacheReads.HeldCount: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FFiles.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

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

/// <summary>Steht AUnit mit gleichem Stand (Zeitstempel, Prüfsumme) in AEntries? AByFile ordnet
/// jedem Dateinamen (groß) seine Stelle in AEntries zu; linear wären es bei Tausenden
/// Bibliotheks-Units Millionen Vergleiche (Diagnoselog 15.10.2026).</summary>
function ContainsUnit(const AEntries: TArray<TIndexCacheEntry>; AByFile: TDictionary<string, Integer>;
  const AUnit: TUnitIndex): Boolean;
var
  Position: Integer;
begin
  Result := AByFile.TryGetValue(AnsiUpperCase(AUnit.FileName), Position) and
    (AEntries[Position].Header.Stamp = AUnit.Stamp) and (AEntries[Position].Header.Hash = AUnit.Hash);
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
  ProjectUnits, LibraryUnits: TList<TUnitIndex>;
  UnitIndex: TUnitIndex;
  Current: TDictionary<string, Boolean>;
  CachedByFile: TDictionary<string, Integer>;
  LibraryChanged: Boolean;
  Own: TDictionary<string, Boolean>;
  FileName: string;
  Position: Integer;
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
  // Listen statt Array-Anhängen: das kopierte bei jeder Unit das ganze Array.
  ProjectUnits := TList<TUnitIndex>.Create;
  LibraryUnits := TList<TUnitIndex>.Create;
  try
    // Der Index ist mit anderen Projekten geteilt: in den Projekt-Cache nur die eigenen Units.
    Own := TDictionary<string, Boolean>.Create;
    try
      for FileName in ARequest.Files + ARequest.SearchFiles do
        Own.AddOrSetValue(AnsiUpperCase(FileName), True);
      for UnitIndex in FIndex.Units do
        if UnitIndex.Library_ and InSharedCache(ARequest, UnitIndex.FileName) then
          LibraryUnits.Add(UnitIndex)
        else if UnitIndex.Library_ or Own.ContainsKey(AnsiUpperCase(UnitIndex.FileName)) then
          // Über uses erreichte Units außerhalb der Installation (gemeinsamer Firmencode) liest
          // der Builder mit den Defines des Projekts; sie gehören in dessen Cache (#647).
          ProjectUnits.Add(UnitIndex);
    finally
      Own.Free;
    end;
    if (AParsed > 0) or (Length(ACached) <> ProjectUnits.Count) then
      FFileSystem.WriteBytes(ARequest.CacheFile, TIndexCache.Serialize(ProjectUnits.ToArray));
    // Units anderer Projekte im gemeinsamen Cache behalten; neu sind nur die fehlenden.
    Current := TDictionary<string, Boolean>.Create;
    CachedByFile := TDictionary<string, Integer>.Create;
    try
      for Position := 0 to High(ALibraryCached) do
        CachedByFile.AddOrSetValue(AnsiUpperCase(ALibraryCached[Position].Header.FileName), Position);
      for UnitIndex in LibraryUnits do
        Current.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), True);
      LibraryChanged := False;
      for UnitIndex in LibraryUnits do
        if not ContainsUnit(ALibraryCached, CachedByFile, UnitIndex) then
        begin
          LibraryChanged := True;
          Break;
        end;
      // Ohne Änderung wird nichts geschrieben; dann auch nichts dekodieren.
      if LibraryChanged then
        for Entry in ALibraryCached do
          if not Current.ContainsKey(AnsiUpperCase(Entry.Header.FileName)) and
            TIndexCache.Expand(Entry, UnitIndex) then
            LibraryUnits.Add(UnitIndex);
    finally
      CachedByFile.Free;
      Current.Free;
    end;
    if LibraryChanged then
      FFileSystem.WriteBytes(ARequest.LibraryCacheFile, TIndexCache.Serialize(LibraryUnits.ToArray));
  finally
    LibraryUnits.Free;
    ProjectUnits.Free;
  end;
end;

function TIndexService.ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
var
  Data: TBytes;
  Reason: string;
begin
  Result := nil;
  if (AFileName = '') or not FFileSystem.ReadBytes(AFileName, Data) then
    Exit;
  Result := TIndexCache.ReadEntries(Data, Reason);
  if (Reason <> '') and Assigned(FOnCacheRejected) then
    FOnCacheRejected(AFileName, Reason);
end;

procedure TIndexService.Run(const ARequest: TIndexRequest);
var
  Builder: TIndexBuilder;
  Cached, LibraryCached: TArray<TIndexCacheEntry>;
  Watch: TStopwatch;
  BuildResult: TIndexBuildResult;
  Turn: IIndexTurn;
  WrittenParsed: Integer;
  Request: TIndexRequest;
  LibraryStamp: Int64;
  LibraryHeld: Boolean;
begin
  // Kopie für die anonyme Methode: const-Parameter lassen sich nicht einfangen.
  Request := ARequest;
  LibraryHeld := False;
  LibraryStamp := -1;
  try
    Watch := TStopwatch.StartNew;
    Builder := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
    Builder.IncludePaths := ARequest.IncludePaths;
    Builder.LibraryRoots := ARequest.LibraryRoots;
    Builder.LibraryDefines := ARequest.LibraryDefines;
    Builder.Usages := ARequest.Usages;
    WaitForOtherWriter(ARequest);
    TMonitor.Enter(FLock);
    try
      FCacheFile := ARequest.CacheFile;
    finally
      TMonitor.Exit(FLock);
    end;
    // Nur die Köpfe lesen; die Symbole dekodiert der Builder je Unit, wenn er sie übernimmt (#617).
    // Ein beschädigter Cache liefert nichts: Dann liest der Aufbau alles neu (#492).
    Cached := ReadCache(ARequest.CacheFile);
    // Bibliothek aus dem gemeinsamen Cache; Einträge im Projekt-Cache (ältere Stände) gelten weiter.
    // Alle Projekte teilen eine gelesene Kopie (Rückmeldung 15.10.2026).
    LibraryStamp := -1;
    if ARequest.LibraryCacheFile <> '' then
    begin
      LibraryCached := TSharedCacheReads.Acquire(FFileSystem, ARequest.LibraryCacheFile, LibraryStamp,
        function: TArray<TIndexCacheEntry>
        begin
          Result := ReadCache(Request.LibraryCacheFile);
        end);
      LibraryHeld := True;
    end;
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
    begin
      WriteCaches(ARequest, Cached, LibraryCached, BuildResult.Parsed - WrittenParsed);
      // Der Index hat alles übernommen; spätere Units (EnsureUnit) liest der Builder aus der Datei.
      Builder.ReleaseCache;
    end;
    if Assigned(FOnFinished) then
      FOnFinished(BuildResult, Watch.ElapsedMilliseconds);
  except
    on E: Exception do
      if Assigned(FOnError) then
        FOnError(E);
  end;
  if LibraryHeld then
    TSharedCacheReads.Release(FFileSystem, ARequest.LibraryCacheFile, LibraryStamp);
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

function TIndexService.UsagesOf(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
var
  Existing: TUnitIndex;
  CacheFile: string;
  Entry: TIndexCacheEntry;
  Builder: TIndexBuilder;
begin
  AUsages := nil;
  if not FIndex.FindFile(AFileName, Existing) or not Existing.UsagesIndexed then
    Exit(False);
  if not Existing.UsagesOffloaded then
  begin
    AUsages := Existing.Usages;
    Exit(True);
  end;
  // Ausgelagert: aus dem Cache, wenn er denselben Stand der Unit hat.
  TMonitor.Enter(FLock);
  try
    CacheFile := FCacheFile;
  finally
    TMonitor.Exit(FLock);
  end;
  for Entry in ReadCache(CacheFile) do
    if SameText(Entry.Header.FileName, AFileName) and (Entry.Header.Hash = Existing.Hash) and
      Entry.Header.UsagesIndexed then
      Exit(TIndexCache.ExpandUsages(Entry, AUsages));
  // Noch nicht geschrieben (neu eingelesen): aus der Datei.
  Builder := AcquireBuilder;
  if Builder = nil then
    Exit(False);
  try
    Result := Builder.ReadUsages(AFileName, AUsages);
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
