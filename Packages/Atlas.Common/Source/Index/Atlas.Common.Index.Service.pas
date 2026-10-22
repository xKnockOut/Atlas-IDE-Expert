unit Atlas.Common.Index.Service;

// Hält den Symbolindex und baut ihn in einem Hintergrund-Thread auf:
// Cache laden, Projektdateien und referenzierte Units indizieren, Cache
// schreiben. Ein neuer Start (z. B. nach geänderter Konfiguration) bricht
// den laufenden Aufbau ab, wartet aber nicht auf ihn (#874): Das tut der neue
// Index-Thread, bevor er beginnt. So hält Start die Nachrichtenschleife des
// Servers nicht auf, und zwei Aufbauten laufen trotzdem nie gleichzeitig.
// Stop bricht ab und wartet.
//
// Schreibt eine andere Instanz den Cache gerade (#62), wartet der Aufbau
// begrenzt, bis sie fertig ist oder die Sperre freigibt, und lädt dann ihren
// Stand, statt alles selbst noch einmal zu lesen.
//
// Ein Schreiber je Cache (Bericht N1): Den Projekt-Cache schreibt nur, wer
// seine Sperre hält (sonst ReadOnlyCache). Den gemeinsamen Bibliotheks-Cache
// teilen alle Projekte und Prozesse; wer ihm Units hinzufügt, sperrt ihn mit
// TryLockWrite, liest unter der Sperre den aktuellen Stand neu und ergänzt
// ihn. Vorher schrieben mehrere gleichzeitig und überschrieben gegenseitig
// ihre Ergänzungen. Was nicht geschrieben werden konnte, meldet
// OnCacheNotWritten.
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
    /// <summary>Optional: läuft im Index-Thread, wenn der vorige Aufbau geendet hat, vor dem Lesen der Caches,
    /// z. B. um sie zu löschen (#874: Start wartet nicht mehr auf den alten Aufbau).</summary>
    Prepare: TProc;
  end;

  /// <summary>Cache-Datei verworfen; AReason z. B. "Prüfsumme stimmt nicht" (#492).</summary>
  TIndexCacheRejectedEvent = reference to procedure(const AFileName, AReason: string);

  TIndexFinishedEvent = reference to procedure(const AResult: TIndexBuildResult; AElapsedMs: Int64);
  TIndexErrorEvent = reference to procedure(const AError: Exception);

  TIndexService = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    /// <summary>Jüngster Index-Thread (TIndexThread); hält den abgebrochenen Vorgänger, bis der endet.</summary>
    FThread: TThread;
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
    FOnCacheNotWritten: TIndexCacheRejectedEvent;
    /// <summary>Cache-Datei des letzten Aufbaus; nur unter FLock.</summary>
    FCacheFile: string;
    procedure Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    function ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
    /// <summary>Schreibt Projekt- und Bibliotheks-Cache; AParsed = seit dem letzten Schreiben neu gelesene Units.</summary>
    procedure WriteCaches(const ARequest: TIndexRequest; const ACached, ALibraryCached: TArray<TIndexCacheEntry>;
      AParsed: Integer; const ACancelled: TFunc<Boolean>);
    procedure WriteCache(const AFileName: string; const AUnits: TArray<TUnitIndex>);
    /// <summary>Wartet begrenzt auf die Schreibsperre; nil, wenn sie ein anderer so lange hält oder der Aufbau
    /// abgebrochen ist.</summary>
    function LockForWrite(const AFileName: string; const ACancelled: TFunc<Boolean>): IInterface;
    procedure NotWritten(const AFileName, AReason: string);
    procedure WaitForOtherWriter(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    function AcquireBuilder: TIndexBuilder;
    procedure ReleaseBuilder;
    procedure ReplaceBuilder(ABuilder: TIndexBuilder);
    /// <summary>Meldet AError über OnError; eine Ausnahme der Meldung beendet den Index-Thread nicht.</summary>
    procedure ReportError(const AError: Exception);
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
    destructor Destroy; override;
    /// <summary>Startet den Aufbau im Hintergrund; ein laufender wird abgebrochen. Kehrt sofort zurück: Der neue
    /// Aufbau beginnt erst, wenn der alte geendet hat (#874).</summary>
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
    /// <summary>Cache nicht geschrieben; AReason ohne Pfad (Bericht N1). Im Index-Thread.</summary>
    property OnCacheNotWritten: TIndexCacheRejectedEvent read FOnCacheNotWritten write FOnCacheNotWritten;
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
    /// <summary>Abgebrochener Vorgänger; Execute wartet auf ihn und gibt ihn frei.</summary>
    FPrevious: TThread;
    FCancelled: Boolean;
    function IsCancelled: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(AService: TIndexService; const ARequest: TIndexRequest; APrevious: TThread);
    destructor Destroy; override;
    /// <summary>Bricht den Aufbau ab; wartet nicht.</summary>
    procedure Cancel;
  end;

{ TIndexThread }

constructor TIndexThread.Create(AService: TIndexService; const ARequest: TIndexRequest; APrevious: TThread);
begin
  FService := AService;
  FRequest := ARequest;
  FPrevious := APrevious;
  inherited Create(False);
end;

destructor TIndexThread.Destroy;
begin
  // Wartet selbst, falls Execute nicht bis zum Vorgänger kam.
  FreeAndNil(FPrevious);
  inherited Destroy;
end;

procedure TIndexThread.Cancel;
begin
  FCancelled := True;
end;

function TIndexThread.IsCancelled: Boolean;
begin
  Result := FCancelled;
end;

procedure TIndexThread.Execute;
begin
  NameThreadForDebugging('Atlas.Index');
  // Erst den abgebrochenen Vorgänger beenden: Builder und Cache-Dateien gehören immer nur einem Aufbau.
  if FPrevious <> nil then
  begin
    FPrevious.WaitFor;
    FreeAndNil(FPrevious);
  end;
  if not FCancelled then
    FService.Run(FRequest, IsCancelled);
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

/// <summary>Fehlt eine Unit aus AUnits in AEntries oder steht sie dort mit anderem Stand?</summary>
function MissingIn(const AEntries: TArray<TIndexCacheEntry>; AUnits: TList<TUnitIndex>): Boolean;
var
  ByFile: TDictionary<string, Integer>;
  Position: Integer;
  UnitIndex: TUnitIndex;
begin
  Result := False;
  ByFile := TDictionary<string, Integer>.Create;
  try
    for Position := 0 to High(AEntries) do
      ByFile.AddOrSetValue(AnsiUpperCase(AEntries[Position].Header.FileName), Position);
    for UnitIndex in AUnits do
      if not ContainsUnit(AEntries, ByFile, UnitIndex) then
        Exit(True);
  finally
    ByFile.Free;
  end;
end;

/// <summary>Hängt an AUnits die Units aus AEntries an, die AUnits nicht hat: Units anderer Projekte im
/// gemeinsamen Cache bleiben erhalten.</summary>
procedure AddOthers(const AEntries: TArray<TIndexCacheEntry>; AUnits: TList<TUnitIndex>);
var
  Current: TDictionary<string, Boolean>;
  Entry: TIndexCacheEntry;
  UnitIndex: TUnitIndex;
begin
  Current := TDictionary<string, Boolean>.Create;
  try
    for UnitIndex in AUnits do
      Current.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), True);
    for Entry in AEntries do
      if not Current.ContainsKey(AnsiUpperCase(Entry.Header.FileName)) and
        TIndexCache.Expand(Entry, UnitIndex) then
        AUnits.Add(UnitIndex);
  finally
    Current.Free;
  end;
end;

const
  /// <summary>So lange wartet ein Aufbau höchstens darauf, den Bibliotheks-Cache schreiben zu dürfen; ein
  /// anderer Schreiber braucht für Lesen, Ergänzen und Schreiben wenige Sekunden.</summary>
  LibraryLockWaitMs = 30000;
  LockPollMs = 100;

function TIndexService.LockForWrite(const AFileName: string; const ACancelled: TFunc<Boolean>): IInterface;
var
  Watch: TStopwatch;
begin
  Watch := TStopwatch.StartNew;
  Result := FFileSystem.TryLockWrite(AFileName);
  while (Result = nil) and not ACancelled() and (Watch.ElapsedMilliseconds < LibraryLockWaitMs) do
  begin
    TThread.Sleep(LockPollMs);
    Result := FFileSystem.TryLockWrite(AFileName);
  end;
end;

procedure TIndexService.NotWritten(const AFileName, AReason: string);
begin
  if Assigned(FOnCacheNotWritten) then
    FOnCacheNotWritten(AFileName, AReason);
end;

procedure TIndexService.WriteCache(const AFileName: string; const AUnits: TArray<TUnitIndex>);
var
  Error: string;
begin
  if not FFileSystem.WriteBytes(AFileName, TIndexCache.Serialize(AUnits), Error) then
    NotWritten(AFileName, Error);
end;

procedure TIndexService.WriteCaches(const ARequest: TIndexRequest; const ACached,
  ALibraryCached: TArray<TIndexCacheEntry>; AParsed: Integer; const ACancelled: TFunc<Boolean>);
var
  ProjectUnits, LibraryUnits: TList<TUnitIndex>;
  UnitIndex: TUnitIndex;
  Own: TDictionary<string, Boolean>;
  FileName: string;
  Lock: IInterface;
  Latest: TArray<TIndexCacheEntry>;
begin
  if (ARequest.CacheFile = '') or ARequest.ReadOnlyCache then
    Exit;
  if ARequest.LibraryCacheFile = '' then
  begin
    if (AParsed > 0) or (Length(ACached) <> FIndex.UnitCount) then
      WriteCache(ARequest.CacheFile, FIndex.Units);
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
      WriteCache(ARequest.CacheFile, ProjectUnits.ToArray);
    // Ohne Änderung gegenüber dem gelesenen Stand nichts sperren, lesen oder schreiben.
    if not MissingIn(ALibraryCached, LibraryUnits) then
      Exit;
    // Ein Schreiber zur Zeit (Bericht N1). Unter der Sperre den aktuellen Stand lesen: Ein anderes Projekt oder
    // ein anderer Prozess kann seit dem Start Units ergänzt haben, die sonst verloren gingen.
    Lock := LockForWrite(ARequest.LibraryCacheFile, ACancelled);
    if Lock = nil then
    begin
      // Abgebrochen ist kein Fehler: Der nächste Aufbau ergänzt den Cache.
      if not ACancelled() then
        NotWritten(ARequest.LibraryCacheFile, 'Schreibsperre nicht erhalten');
      Exit;
    end;
    Latest := ReadCache(ARequest.LibraryCacheFile);
    if MissingIn(Latest, LibraryUnits) then
    begin
      AddOthers(Latest, LibraryUnits);
      WriteCache(ARequest.LibraryCacheFile, LibraryUnits.ToArray);
    end;
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

procedure TIndexService.Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
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
    try
      Builder.IncludePaths := ARequest.IncludePaths;
      Builder.LibraryRoots := ARequest.LibraryRoots;
      Builder.LibraryDefines := ARequest.LibraryDefines;
      Builder.Usages := ARequest.Usages;
      if Assigned(ARequest.Prepare) then
        ARequest.Prepare();
      WaitForOtherWriter(ARequest, ACancelled);
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
    except
      // Noch nicht veröffentlicht: sonst bliebe der Builder als Leck zurück (Code-Review A-04).
      Builder.Free;
      raise;
    end;
    // Erst mit gefülltem Cache veröffentlichen; bis dahin bedient der alte Builder EnsureUnit.
    // Hinter dem inneren try: Ab hier gehört der Builder dem Dienst (kein doppeltes Free).
    ReplaceBuilder(Builder);
    Turn := nil;
    if FScheduler <> nil then
      Turn := FScheduler.Register(ARequest.Priority);
    WrittenParsed := 0;
    BuildResult := Builder.Build(ARequest.Files, ARequest.SearchFiles, ARequest.LibraryFiles, FOnProgress,
      function: Boolean
      begin
        Result := ACancelled();
      end, Turn,
      procedure(const APartial: TIndexBuildResult)
      begin
        // Nach der Projektstufe schon schreiben (#647): In einer Projektgruppe endet der ganze Aufbau
        // erst nach allen Projekten; wer die IDE vorher schließt, begann sonst jedes Mal von vorn.
        WriteCaches(Request, Cached, LibraryCached, APartial.Parsed, ACancelled);
        WrittenParsed := APartial.Parsed;
        if Assigned(FOnProjectReady) then
          FOnProjectReady(APartial, Watch.ElapsedMilliseconds);
      end);
    // Abmelden vor dem Schreiben des Caches: Das nächste Projekt muss darauf nicht warten.
    Turn := nil;
    if not BuildResult.Cancelled then
    begin
      WriteCaches(ARequest, Cached, LibraryCached, BuildResult.Parsed - WrittenParsed, ACancelled);
      // Der Index hat alles übernommen; spätere Units (EnsureUnit) liest der Builder aus der Datei.
      Builder.ReleaseCache;
    end;
    if Assigned(FOnFinished) then
      FOnFinished(BuildResult, Watch.ElapsedMilliseconds);
  except
    on E: Exception do
      ReportError(E);
  end;
  if LibraryHeld then
    TSharedCacheReads.Release(FFileSystem, ARequest.LibraryCacheFile, LibraryStamp);
end;

procedure TIndexService.ReportError(const AError: Exception);
begin
  if not Assigned(FOnError) then
    Exit;
  try
    FOnError(AError);
  except
    // Sonst läge die Ausnahme ungelesen in TThread.FatalException (Code-Review A-04).
  end;
end;

procedure TIndexService.WaitForOtherWriter(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
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
  while not ACancelled() and (Watch.ElapsedMilliseconds < ARequest.CacheWaitMs) and ARequest.CacheBusy() do
  begin
    if FFileSystem.FileStamp(ARequest.CacheFile, Stamp) and (Stamp <> Before) then
      Exit;
    TThread.Sleep(200);
  end;
end;

procedure TIndexService.Start(const ARequest: TIndexRequest);
var
  Previous: TThread;
begin
  // Nicht warten (#874): Der neue Thread wartet auf den abgebrochenen und gibt ihn frei.
  Previous := FThread;
  FThread := nil;
  if Previous <> nil then
    TIndexThread(Previous).Cancel;
  FThread := TIndexThread.Create(Self, ARequest, Previous);
end;

procedure TIndexService.Stop;
begin
  if FThread = nil then
    Exit;
  TIndexThread(FThread).Cancel;
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
