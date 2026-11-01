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
//
// Speicher (Rückmeldung 22.10.2026, 3 GB im Task-Manager bei acht Projekten): Die Aufbauten einer
// Projektgruppe enden fast gleichzeitig. Jeder verglich die Bibliothek mit seinem eigenen, beim Start
// gelesenen Stand, fand die Units der anderen als neu und schrieb den ganzen gemeinsamen Cache, nach der
// Projektstufe und am Ende: bis zu 16 vollständige Serialisierungen je Start, mehrere gleichzeitig. Jetzt
// schreibt im Prozess immer nur ein Dienst (TSharedCacheWrites), und der Stand der zuletzt geschriebenen
// Bibliotheks-Datei ist bekannt: Wer nichts Neues hat, schreibt nicht. Ist der Stand unbekannt (Datei von
// einem anderen Prozess geschrieben), gilt der Weg über die Dateisperre oben.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
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
    /// <summary>Gemeinsamer Cache der Units aus SearchFiles für alle Projekte mit denselben Suchpfaden,
    /// Defines und Include-Pfaden (Speicher, Rückmeldung 01.11.2026): Vorher stand jede Suchpfad-Unit im Cache
    /// jedes Projekts, und eine Gruppe hielt beim Laden alle Kopien gleichzeitig. '' = im Projekt-Cache.</summary>
    SearchCacheFile: string;
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

  /// <summary>Ein Cache wurde geschrieben (Diagnoselog): ALibrary = gemeinsamer Bibliotheks-Cache.</summary>
  TIndexCacheWrittenEvent = reference to procedure(ALibrary: Boolean; AUnits: Integer; ABytes, AElapsedMs: Int64);

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
    FOnCacheWritten: TIndexCacheWrittenEvent;
    /// <summary>Cache-Datei des letzten Aufbaus; nur unter FLock.</summary>
    FCacheFile: string;
    procedure Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
    function ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
    /// <summary>Schreibt Projekt-, Suchpfad- und Bibliotheks-Cache; AParsed = seit dem letzten Schreiben neu
    /// gelesene Units.</summary>
    procedure WriteCaches(const ARequest: TIndexRequest; const ACached, ALibraryCached,
      ASearchCached: TArray<TIndexCacheEntry>; AParsed: Integer; const ACancelled: TFunc<Boolean>);
    /// <summary>Ergänzt einen gemeinsamen Cache (Bibliothek, Suchpfade) um AUnits, wenn etwas fehlt: unter der
    /// Schreibsperre mit dem aktuellen Stand der Datei zusammengeführt (andere Projekte und Prozesse).</summary>
    procedure WriteSharedCache(const AFileName: string; const AStartCached: TArray<TIndexCacheEntry>;
      AUnits: TList<TUnitIndex>; const ACancelled: TFunc<Boolean>);
    /// <summary>Serialisiert AUnits nach AFileName; meldet Erfolg über OnCacheWritten, sonst OnCacheNotWritten.
    /// </summary>
    function WriteCache(ALibrary: Boolean; const AFileName: string; const AUnits: TArray<TUnitIndex>): Boolean;
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
    /// <summary>Nach jedem geschriebenen Cache; im Index-Thread.</summary>
    property OnCacheWritten: TIndexCacheWrittenEvent read FOnCacheWritten write FOnCacheWritten;
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
  System.Diagnostics;

/// <summary>Schlüssel einer Cache-Datei im Prozess: Dateisystem und Datei.</summary>
function SharedCacheKey(const AFileSystem: IIndexFileSystem; const AFileName: string): string;
begin
  Result := IntToHex(NativeInt(Pointer(AFileSystem)), 16) + '|' + AnsiUpperCase(AFileName);
end;

type
  /// <summary>Schreiben der Index-Caches im Prozess: immer nur ein Dienst zur Zeit (Enter/Leave), damit nie
  /// mehrere große Serialisierungen gleichzeitig Speicher belegen. Merkt sich je Bibliotheks-Datei, welche
  /// Unit-Stände zuletzt hineingeschrieben wurden; gilt nur, solange die Datei denselben Zeitstempel hat
  /// (schreibt eine andere Instanz, ist der Stand unbekannt).</summary>
  TSharedCacheWrites = class
  private type
    TWritten = class
    public
      Stamp: Int64;
      Units: TDictionary<string, string>;
      destructor Destroy; override;
    end;
  private
    class var FLock: TObject;
    class var FFiles: TObjectDictionary<string, TWritten>;
  public
    class constructor Create;
    class destructor Destroy;
    class procedure Enter; static;
    class procedure Leave; static;
    /// <summary>Datei (groß) → Stand (StateOf) der zuletzt in AFileName geschriebenen Units; nil, wenn
    /// unbekannt oder die Datei seither einen anderen Zeitstempel hat. Nur zwischen Enter und Leave
    /// verwenden; das Ergebnis gehört weiter TSharedCacheWrites.</summary>
    class function Written(const AFileSystem: IIndexFileSystem; const AFileName: string): TDictionary<string, string>;
      static;
    /// <summary>Merkt den eben geschriebenen Stand mit dem jetzigen Zeitstempel der Datei; übernimmt AUnits.
    /// Nur zwischen Enter und Leave.</summary>
    class procedure Remember(const AFileSystem: IIndexFileSystem; const AFileName: string;
      AUnits: TDictionary<string, string>); static;
    /// <summary>Vergisst den Stand (kein Aufbau nutzt die Datei mehr).</summary>
    class procedure Forget(const AFileSystem: IIndexFileSystem; const AFileName: string); static;
    /// <summary>Stand einer Unit: Zeitstempel und Prüfsumme.</summary>
    class function StateOf(const AUnit: TUnitIndex): string; static;
  end;

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

  /// <summary>Hält eine Kopie aus TSharedCacheReads für die Dauer eines Aufbaus; gibt sie frei, sobald die letzte
  /// Referenz fällt, auch nach einer Ausnahme (wie die Schreibsperre aus LockForWrite).</summary>
  TSharedCacheHold = class(TInterfacedObject)
  private
    FFileSystem: IIndexFileSystem;
    FFileName: string;
    FStamp: Int64;
  public
    /// <summary>Holt die Einträge von AFileName; AHold hält sie. '' = kein gemeinsamer Cache: leer, AHold nil.</summary>
    class function Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
      const ARead: TFunc<TArray<TIndexCacheEntry>>; out AHold: IInterface): TArray<TIndexCacheEntry>; static;
    destructor Destroy; override;
  end;

{ TSharedCacheWrites.TWritten }

destructor TSharedCacheWrites.TWritten.Destroy;
begin
  Units.Free;
  inherited;
end;

{ TSharedCacheWrites }

class constructor TSharedCacheWrites.Create;
begin
  FLock := TObject.Create;
  FFiles := TObjectDictionary<string, TWritten>.Create([doOwnsValues]);
end;

class destructor TSharedCacheWrites.Destroy;
begin
  FFiles.Free;
  FLock.Free;
end;

class procedure TSharedCacheWrites.Enter;
begin
  TMonitor.Enter(FLock);
end;

class procedure TSharedCacheWrites.Leave;
begin
  TMonitor.Exit(FLock);
end;

class function TSharedCacheWrites.Written(const AFileSystem: IIndexFileSystem;
  const AFileName: string): TDictionary<string, string>;
var
  Entry: TWritten;
  Stamp: Int64;
begin
  Result := nil;
  if not FFiles.TryGetValue(SharedCacheKey(AFileSystem, AFileName), Entry) then
  begin
    Exit;
  end;
  if AFileSystem.FileStamp(AFileName, Stamp) and (Stamp = Entry.Stamp) then
  begin
    Result := Entry.Units;
  end;
end;

class procedure TSharedCacheWrites.Remember(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AUnits: TDictionary<string, string>);
var
  Entry: TWritten;
  Stamp: Int64;
begin
  if not AFileSystem.FileStamp(AFileName, Stamp) then
  begin
    AUnits.Free;
    FFiles.Remove(SharedCacheKey(AFileSystem, AFileName));
    Exit;
  end;
  Entry := TWritten.Create;
  Entry.Stamp := Stamp;
  Entry.Units := AUnits;
  FFiles.AddOrSetValue(SharedCacheKey(AFileSystem, AFileName), Entry);
end;

class procedure TSharedCacheWrites.Forget(const AFileSystem: IIndexFileSystem; const AFileName: string);
begin
  TMonitor.Enter(FLock);
  try
    FFiles.Remove(SharedCacheKey(AFileSystem, AFileName));
  finally
    TMonitor.Exit(FLock);
  end;
end;

class function TSharedCacheWrites.StateOf(const AUnit: TUnitIndex): string;
begin
  Result := IntToStr(AUnit.Stamp) + '|' + AUnit.Hash;
end;

{ TSharedCacheHold }

class function TSharedCacheHold.Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
  const ARead: TFunc<TArray<TIndexCacheEntry>>; out AHold: IInterface): TArray<TIndexCacheEntry>;
var
  mHold: TSharedCacheHold;
  mStamp: Int64;
begin
  AHold := nil;
  Result := nil;
  if AFileName = '' then
  begin
    Exit;
  end;
  Result := TSharedCacheReads.Acquire(AFileSystem, AFileName, mStamp, ARead);
  mHold := TSharedCacheHold.Create;
  mHold.FFileSystem := AFileSystem;
  mHold.FFileName := AFileName;
  mHold.FStamp := mStamp;
  AHold := mHold;
end;

destructor TSharedCacheHold.Destroy;
begin
  TSharedCacheReads.Release(FFileSystem, FFileName, FStamp);
  inherited;
end;

{ TSharedCacheReads }

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
  Result := SharedCacheKey(AFileSystem, AFileName);
end;

class function TSharedCacheReads.Acquire(const AFileSystem: IIndexFileSystem; const AFileName: string;
  out AStamp: Int64; const ARead: TFunc<TArray<TIndexCacheEntry>>): TArray<TIndexCacheEntry>;
var
  Key: string;
  Shared: TShared;
begin
  if not AFileSystem.FileStamp(AFileName, AStamp) then
  begin
    AStamp := -1;
  end;
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
  Unused: Boolean;
begin
  Key := KeyOf(AFileSystem, AFileName);
  Unused := False;
  TMonitor.Enter(FLock);
  try
    // Anderer Stand: Der Eintrag wurde schon ersetzt; die eigene Kopie hält der Aufrufer selbst.
    if not FFiles.TryGetValue(Key, Shared) or (Shared.Stamp <> AStamp) then
    begin
      Exit;
    end;
    Dec(Shared.Users);
    if Shared.Users <= 0 then
    begin
      FFiles.Remove(Key);
      Unused := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Lese-Sperre: Forget wartet auf ein laufendes Schreiben.
  if Unused then
  begin
    TSharedCacheWrites.Forget(AFileSystem, AFileName);
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
  // Niedrige Priorität (#1236): Der Aufbau läuft im Hintergrund; IDE, Editor und Anfragen gehen vor. Der Thread
  // startet erst nach dem Konstruktor. Nicht jede Plattform erlaubt das.
  try
    Priority := tpLower;
  except
    // Dann eben mit normaler Priorität; der Aufbau selbst ist davon nicht betroffen.
  end;
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
  begin
    FService.Run(FRequest, IsCancelled);
  end;
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
    begin
      ByFile.AddOrSetValue(AnsiUpperCase(AEntries[Position].Header.FileName), Position);
    end;
    for UnitIndex in AUnits do
    begin
      if not ContainsUnit(AEntries, ByFile, UnitIndex) then
      begin
        Exit(True);
      end;
    end;
  finally
    ByFile.Free;
  end;
end;

/// <summary>Steht jede Unit aus AUnits mit demselben Stand in AWritten (zuletzt in diesem Prozess geschrieben)?
/// </summary>
function AllWritten(AWritten: TDictionary<string, string>; AUnits: TList<TUnitIndex>): Boolean;
var
  UnitIndex: TUnitIndex;
  State: string;
begin
  for UnitIndex in AUnits do
  begin
    if not AWritten.TryGetValue(AnsiUpperCase(UnitIndex.FileName), State) or
      (State <> TSharedCacheWrites.StateOf(UnitIndex)) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
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
    begin
      Current.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), True);
    end;
    for Entry in AEntries do
    begin
      if not Current.ContainsKey(AnsiUpperCase(Entry.Header.FileName)) and
        TIndexCache.Expand(Entry, UnitIndex) then
      begin
        AUnits.Add(UnitIndex);
      end;
    end;
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
  begin
    FOnCacheNotWritten(AFileName, AReason);
  end;
end;

function TIndexService.WriteCache(ALibrary: Boolean; const AFileName: string;
  const AUnits: TArray<TUnitIndex>): Boolean;
var
  Watch: TStopwatch;
  Data: TBytes;
  Error: string;
begin
  Watch := TStopwatch.StartNew;
  Data := TIndexCache.Serialize(AUnits);
  Result := FFileSystem.WriteBytes(AFileName, Data, Error);
  if not Result then
  begin
    NotWritten(AFileName, Error);
  end
  else if Assigned(FOnCacheWritten) then
  begin
    FOnCacheWritten(ALibrary, Length(AUnits), Length(Data), Watch.ElapsedMilliseconds);
  end;
end;

procedure TIndexService.WriteSharedCache(const AFileName: string; const AStartCached: TArray<TIndexCacheEntry>;
  AUnits: TList<TUnitIndex>; const ACancelled: TFunc<Boolean>);
var
  Written, NewState: TDictionary<string, string>;
  UnitIndex: TUnitIndex;
  Lock: IInterface;
  Latest: TArray<TIndexCacheEntry>;
begin
  // Hat in diesem Prozess schon ein Dienst diese Units in die unveränderte Datei geschrieben, gibt es
  // nichts Neues; dann weder sperren noch lesen. Sonst gegen den beim Start gelesenen Stand.
  Written := TSharedCacheWrites.Written(FFileSystem, AFileName);
  if Written <> nil then
  begin
    if AllWritten(Written, AUnits) then
    begin
      Exit;
    end;
  end
  else if not MissingIn(AStartCached, AUnits) then
  begin
    Exit;
  end;
  // Ein Schreiber zur Zeit (Bericht N1). Unter der Sperre den aktuellen Stand lesen: Ein anderes Projekt
  // oder ein anderer Prozess kann seit dem Start Units ergänzt haben, die sonst verloren gingen.
  Lock := LockForWrite(AFileName, ACancelled);
  if Lock = nil then
  begin
    // Abgebrochen ist kein Fehler: Der nächste Aufbau ergänzt den Cache.
    if not ACancelled() then
    begin
      NotWritten(AFileName, 'Schreibsperre nicht erhalten');
    end;
    Exit;
  end;
  Latest := ReadCache(AFileName);
  if not MissingIn(Latest, AUnits) then
  begin
    Exit;
  end;
  AddOthers(Latest, AUnits);
  Latest := nil;
  if WriteCache(True, AFileName, AUnits.ToArray) then
  begin
    NewState := TDictionary<string, string>.Create;
    for UnitIndex in AUnits do
    begin
      NewState.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), TSharedCacheWrites.StateOf(UnitIndex));
    end;
    TSharedCacheWrites.Remember(FFileSystem, AFileName, NewState);
  end;
end;

procedure TIndexService.WriteCaches(const ARequest: TIndexRequest; const ACached, ALibraryCached,
  ASearchCached: TArray<TIndexCacheEntry>; AParsed: Integer; const ACancelled: TFunc<Boolean>);
var
  ProjectUnits, SearchUnits, LibraryUnits: TList<TUnitIndex>;
  UnitIndex: TUnitIndex;
  Own, Searched: TDictionary<string, Boolean>;
  FileName, Key: string;
begin
  if (ARequest.CacheFile = '') or ARequest.ReadOnlyCache then
  begin
    Exit;
  end;
  // Immer nur ein Dienst des Prozesses serialisiert (Rückmeldung 22.10.2026): Die Projekte einer Gruppe
  // enden fast gleichzeitig, jede Serialisierung belegt kurzzeitig ein Vielfaches der Datei. Gegen andere
  // Prozesse schützt die Schreibsperre der Datei (Bericht N1).
  TSharedCacheWrites.Enter;
  try
    if ARequest.LibraryCacheFile = '' then
    begin
      if (AParsed > 0) or (Length(ACached) <> FIndex.UnitCount) then
      begin
        WriteCache(False, ARequest.CacheFile, FIndex.Units);
      end;
      Exit;
    end;
    // Getrennt schreiben: Projekt-Units ins Projekt, Suchpfade und Bibliothek in die gemeinsamen Caches.
    // Listen statt Array-Anhängen: das kopierte bei jeder Unit das ganze Array.
    ProjectUnits := TList<TUnitIndex>.Create;
    SearchUnits := TList<TUnitIndex>.Create;
    LibraryUnits := TList<TUnitIndex>.Create;
    Own := TDictionary<string, Boolean>.Create;
    Searched := TDictionary<string, Boolean>.Create;
    try
      // Der Index ist mit anderen Projekten geteilt: in den Projekt-Cache nur die eigenen Units.
      for FileName in ARequest.Files do
      begin
        Own.AddOrSetValue(AnsiUpperCase(FileName), True);
      end;
      // Eine Projektdatei, die auch im Suchpfad liegt, bleibt im Projekt-Cache.
      for FileName in ARequest.SearchFiles do
      begin
        Key := AnsiUpperCase(FileName);
        if not Own.ContainsKey(Key) then
        begin
          Searched.AddOrSetValue(Key, True);
        end;
      end;
      for UnitIndex in FIndex.Units do
      begin
        Key := AnsiUpperCase(UnitIndex.FileName);
        if UnitIndex.Library_ and InSharedCache(ARequest, UnitIndex.FileName) then
        begin
          LibraryUnits.Add(UnitIndex);
        end
        else if (ARequest.SearchCacheFile <> '') and Searched.ContainsKey(Key) then
        begin
          SearchUnits.Add(UnitIndex);
        end
        else if UnitIndex.Library_ or Own.ContainsKey(Key) or Searched.ContainsKey(Key) then
        begin
          // Über uses erreichte Units außerhalb der Installation (gemeinsamer Firmencode) liest
          // der Builder mit den Defines des Projekts; sie gehören in dessen Cache (#647).
          ProjectUnits.Add(UnitIndex);
        end;
      end;
      if (AParsed > 0) or (Length(ACached) <> ProjectUnits.Count) then
      begin
        WriteCache(False, ARequest.CacheFile, ProjectUnits.ToArray);
      end;
      if ARequest.SearchCacheFile <> '' then
      begin
        WriteSharedCache(ARequest.SearchCacheFile, ASearchCached, SearchUnits, ACancelled);
      end;
      WriteSharedCache(ARequest.LibraryCacheFile, ALibraryCached, LibraryUnits, ACancelled);
    finally
      Searched.Free;
      Own.Free;
      LibraryUnits.Free;
      SearchUnits.Free;
      ProjectUnits.Free;
    end;
  finally
    TSharedCacheWrites.Leave;
  end;
end;

function TIndexService.ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
var
  Data: TBytes;
  Reason: string;
begin
  Result := nil;
  if (AFileName = '') or not FFileSystem.ReadBytes(AFileName, Data) then
  begin
    Exit;
  end;
  Result := TIndexCache.ReadEntries(Data, Reason);
  if (Reason <> '') and Assigned(FOnCacheRejected) then
  begin
    FOnCacheRejected(AFileName, Reason);
  end;
end;

procedure TIndexService.Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>);
var
  Builder: TIndexBuilder;
  Cached: TArray<TIndexCacheEntry>;
  Watch: TStopwatch;
  BuildResult: TIndexBuildResult;
  Turn: IIndexTurn;
  WrittenParsed: Integer;
  Request: TIndexRequest;
  LibraryCached, SearchCached: TArray<TIndexCacheEntry>;
  mLibraryHold, mSearchHold: IInterface;
begin
  // Kopie für die anonyme Methode: const-Parameter lassen sich nicht einfangen.
  Request := ARequest;
  try
    Watch := TStopwatch.StartNew;
    Builder := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
    try
      Builder.IncludePaths := ARequest.IncludePaths;
      Builder.LibraryRoots := ARequest.LibraryRoots;
      Builder.LibraryDefines := ARequest.LibraryDefines;
      Builder.Usages := ARequest.Usages;
      if Assigned(ARequest.Prepare) then
      begin
        ARequest.Prepare();
      end;
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
      LibraryCached := TSharedCacheHold.Acquire(FFileSystem, ARequest.LibraryCacheFile,
        function: TArray<TIndexCacheEntry>
        begin
          Result := ReadCache(Request.LibraryCacheFile);
        end, mLibraryHold);
      // Suchpfade ebenso: Die Projekte einer Gruppe teilen meist dieselben (Speicher, Rückmeldung 01.11.2026).
      SearchCached := TSharedCacheHold.Acquire(FFileSystem, ARequest.SearchCacheFile,
        function: TArray<TIndexCacheEntry>
        begin
          Result := ReadCache(Request.SearchCacheFile);
        end, mSearchHold);
      Builder.UseCache(LibraryCached + SearchCached + Cached);
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
    begin
      Turn := FScheduler.Register(ARequest.Priority);
    end;
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
        WriteCaches(Request, Cached, LibraryCached, SearchCached, APartial.Parsed, ACancelled);
        WrittenParsed := APartial.Parsed;
        if Assigned(FOnProjectReady) then
        begin
          FOnProjectReady(APartial, Watch.ElapsedMilliseconds);
        end;
      end);
    // Abmelden vor dem Schreiben des Caches: Das nächste Projekt muss darauf nicht warten.
    Turn := nil;
    if not BuildResult.Cancelled then
    begin
      WriteCaches(ARequest, Cached, LibraryCached, SearchCached, BuildResult.Parsed - WrittenParsed,
        ACancelled);
    end;
    // Der Index hat alles übernommen; spätere Units (EnsureUnit) liest der Builder aus der Datei. Auch nach einem
    // Abbruch: Sonst hielt der Builder die Einträge samt String-Tabellen ganzer Cache-Dateien, bis ein neuer
    // Aufbau ihn ersetzte, und ein abgebrochener Aufbau ohne Nachfolger behielt sie (Speicher, Rückmeldung
    // 01.11.2026).
    Builder.ReleaseCache;
    Cached := nil;
    LibraryCached := nil;
    SearchCached := nil;
    if Assigned(FOnFinished) then
    begin
      FOnFinished(BuildResult, Watch.ElapsedMilliseconds);
    end;
  except
    on E: Exception do
      ReportError(E);
  end;
  // Gemeinsame Kopien freigeben (TSharedCacheHold), auch nach einer Ausnahme.
  mLibraryHold := nil;
  mSearchHold := nil;
end;

procedure TIndexService.ReportError(const AError: Exception);
begin
  if not Assigned(FOnError) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  if not FFileSystem.FileStamp(ARequest.CacheFile, Before) then
  begin
    Before := 0;
  end;
  Watch := TStopwatch.StartNew;
  // Bis die andere Instanz einen neuen Stand geschrieben oder die Sperre freigegeben hat,
  // nie länger als CacheWaitMs.
  while not ACancelled() and (Watch.ElapsedMilliseconds < ARequest.CacheWaitMs) and ARequest.CacheBusy() do
  begin
    if FFileSystem.FileStamp(ARequest.CacheFile, Stamp) and (Stamp <> Before) then
    begin
      Exit;
    end;
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
  begin
    TIndexThread(Previous).Cancel;
  end;
  FThread := TIndexThread.Create(Self, ARequest, Previous);
end;

procedure TIndexService.Stop;
begin
  if FThread = nil then
  begin
    Exit;
  end;
  TIndexThread(FThread).Cancel;
  FThread.WaitFor;
  FreeAndNil(FThread);
end;

procedure TIndexService.WaitFor;
begin
  if FThread <> nil then
  begin
    FThread.WaitFor;
  end;
end;

function TIndexService.AcquireBuilder: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Result := FBuilder;
    if Result <> nil then
    begin
      Inc(FUsers);
    end;
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
    begin
      TMonitor.PulseAll(FLock);
    end;
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
    begin
      TMonitor.Wait(FLock, INFINITE);
    end;
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
  begin
    Exit(FIndex.FindUnit(AUnitName, Existing));
  end;
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
  begin
    Exit(False);
  end;
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
  begin
    Exit(False);
  end;
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
  begin
    if SameText(Entry.Header.FileName, AFileName) and (Entry.Header.Hash = Existing.Hash) and
      Entry.Header.UsagesIndexed then
    begin
      Exit(TIndexCache.ExpandUsages(Entry, AUsages));
    end;
  end;
  // Noch nicht geschrieben (neu eingelesen): aus der Datei.
  Builder := AcquireBuilder;
  if Builder = nil then
  begin
    Exit(False);
  end;
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
  begin
    Exit(0);
  end;
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
