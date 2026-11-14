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
// Ein Schreiber je Cache: Den Projekt-Cache schreibt nur, wer
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

  /// <summary>Rückmeldungen beim Lesen und Schreiben der Caches (Diagnoselog).</summary>
  TIndexCacheEvents = record
    Rejected: TIndexCacheRejectedEvent;
    NotWritten: TIndexCacheRejectedEvent;
    Written: TIndexCacheWrittenEvent;
  end;

  /// <summary>Rückmeldungen des Aufbaus an den Aufrufer.</summary>
  TIndexServiceEvents = record
    Progress: TIndexProgressEvent;
    Finished: TIndexFinishedEvent;
    ProjectReady: TIndexFinishedEvent;
    Error: TIndexErrorEvent;
  end;

  /// <summary>Wartet höchstens AMs oder bis der Aufbau abgebrochen wird; True bei Abbruch. Für das Warten auf
  /// eine andere Instanz (Schreibsperre, Cache-Datei): Dafür gibt es kein Signal über Prozessgrenzen, also wird
  /// nachgesehen; der Abbruch aber wirkt sofort und nicht erst nach dem nächsten Takt.</summary>
  TIndexPause = reference to function(AMs: Cardinal): Boolean;

  /// <summary>Caches eines Aufbaus (#647): liest beim Start Projekt-, Suchpfad- und Bibliotheks-Cache und schreibt
  /// sie nach der Projektstufe und am Ende getrennt zurück. Hält die gemeinsam gelesenen Kopien (TSharedCacheHold)
  /// bis zur Freigabe.</summary>
  TIndexCacheWriter = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FEvents: TIndexCacheEvents;
    FRequest: TIndexRequest;
    FCancelled: TFunc<Boolean>;
    FPause: TIndexPause;
    FCached: TArray<TIndexCacheEntry>;
    FLibraryCached: TArray<TIndexCacheEntry>;
    FSearchCached: TArray<TIndexCacheEntry>;
    FLibraryHold: IInterface;
    FSearchHold: IInterface;
    /// <summary>Bis zum letzten Schreiben neu gelesene Units.</summary>
    FWrittenParsed: Integer;
    function ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
    procedure NotWritten(const AFileName, AReason: string);
    /// <summary>Wartet begrenzt auf die Schreibsperre; nil, wenn sie ein anderer so lange hält oder der Aufbau
    /// abgebrochen ist.</summary>
    function LockForWrite(const AFileName: string): IInterface;
    /// <summary>Serialisiert AUnits nach AFileName; meldet Erfolg über Written, sonst NotWritten.</summary>
    function WriteCache(ALibrary: Boolean; const AFileName: string; const AUnits: TArray<TUnitIndex>): Boolean;
    /// <summary>Ergänzt einen gemeinsamen Cache (Bibliothek, Suchpfade) um AUnits, wenn etwas fehlt: unter der
    /// Schreibsperre mit dem aktuellen Stand der Datei zusammengeführt (andere Projekte und Prozesse).</summary>
    procedure WriteSharedCache(const AFileName: string; const AStartCached: TArray<TIndexCacheEntry>;
      AUnits: TList<TUnitIndex>);
    /// <summary>Projekt-Units ins Projekt, Suchpfade und Bibliothek in die gemeinsamen Caches.</summary>
    procedure WriteSplit(AParsed: Integer);
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const AEvents: TIndexCacheEvents; const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>;
      const APause: TIndexPause);
    /// <summary>Liest die Caches; Ergebnis für TIndexBuilder.UseCache.</summary>
    function Load: TArray<TIndexCacheEntry>;
    /// <summary>Schreibt Projekt-, Suchpfad- und Bibliotheks-Cache; AParsedTotal = im ganzen Aufbau bisher neu
    /// gelesene Units.</summary>
    procedure WriteCaches(AParsedTotal: Integer);
    /// <summary>Gibt die gelesenen Einträge frei; die gemeinsamen Kopien hält das Objekt bis zum Ende.</summary>
    procedure Release;
  end;

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
    FEvents: TIndexServiceEvents;
    FScheduler: TIndexScheduler;
    FStages: TIndexStageWatch;
    FCacheEvents: TIndexCacheEvents;
    /// <summary>Cache-Datei des letzten Aufbaus; nur unter FLock.</summary>
    FCacheFile: string;
    procedure Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>; const APause: TIndexPause);
    /// <summary>Neuer Builder mit gelesenem Cache; noch nicht veröffentlicht.</summary>
    function PrepareBuilder(const ARequest: TIndexRequest; const APause: TIndexPause;
      ACaches: TIndexCacheWriter): TIndexBuilder;
    procedure WaitForOtherWriter(const ARequest: TIndexRequest; const APause: TIndexPause);
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
    /// <summary>Stufe des laufenden Aufbaus und ob er auf sie wartet (#2142).</summary>
    function StageState: TIndexStageState;
    property Index: ISymbolIndex read FIndex;
    property OnCacheRejected: TIndexCacheRejectedEvent read FCacheEvents.Rejected write FCacheEvents.Rejected;
    /// <summary>Cache nicht geschrieben; AReason ohne Pfad. Im Index-Thread.</summary>
    property OnCacheNotWritten: TIndexCacheRejectedEvent read FCacheEvents.NotWritten write FCacheEvents.NotWritten;
    /// <summary>Nach jedem geschriebenen Cache; im Index-Thread.</summary>
    property OnCacheWritten: TIndexCacheWrittenEvent read FCacheEvents.Written write FCacheEvents.Written;
    property OnProgress: TIndexProgressEvent read FEvents.Progress write FEvents.Progress;
    property OnFinished: TIndexFinishedEvent read FEvents.Finished write FEvents.Finished;
    /// <summary>Projektstufe fertig (Projektdateien und über uses erreichbare Units), Cache geschrieben;
    /// Suchpfade und Bibliothek folgen. Im Index-Thread, nicht bei Abbruch.</summary>
    property OnProjectReady: TIndexFinishedEvent read FEvents.ProjectReady write FEvents.ProjectReady;
    property OnError: TIndexErrorEvent read FEvents.Error write FEvents.Error;
    /// <summary>Gemeinsam für alle Projekte (#648); gehört dem Aufrufer, nil = ohne Reihenfolge.</summary>
    property Scheduler: TIndexScheduler read FScheduler write FScheduler;
  end;

implementation

uses
  System.Diagnostics,
  System.SyncObjs,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TIndexServiceText = (WriteLockNotObtained);

const
  cTexts: array[TIndexServiceText] of TAtlasText = (
    (De: 'Schreibsperre nicht erhalten'; En: 'Write lock not obtained'));

{$SCOPEDENUMS OFF}

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
      FStamp: Int64;
      FEntries: TArray<TIndexCacheEntry>;
      FUsers: Integer;
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
  end;

  /// <summary>Hält eine Kopie aus TSharedCacheReads für die Dauer eines Aufbaus; gibt sie frei, sobald die letzte
  /// Referenz fällt, auch nach einer Ausnahme (wie die Schreibsperre aus LockForWrite).</summary>
  TSharedCacheHold = class(TInterfacedObject)
  private
    FFileSystem: IIndexFileSystem;
    FFileName: string;
    FStamp: Int64;
  public
    /// <summary>Holt die Einträge von AFileName; AHold hält sie. '' = kein gemeinsamer Cache: leer, AHold
    /// nil.</summary>
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
  mEntry: TWritten;
  mStamp: Int64;
begin
  Result := nil;
  if not FFiles.TryGetValue(SharedCacheKey(AFileSystem, AFileName), mEntry) then
  begin
    Exit;
  end;
  if AFileSystem.FileStamp(AFileName, mStamp) and (mStamp = mEntry.Stamp) then
  begin
    Result := mEntry.Units;
  end;
end;

class procedure TSharedCacheWrites.Remember(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AUnits: TDictionary<string, string>);
var
  mEntry: TWritten;
  mStamp: Int64;
begin
  if not AFileSystem.FileStamp(AFileName, mStamp) then
  begin
    AUnits.Free;
    FFiles.Remove(SharedCacheKey(AFileSystem, AFileName));
    Exit;
  end;
  mEntry := TWritten.Create;
  mEntry.Stamp := mStamp;
  mEntry.Units := AUnits;
  FFiles.AddOrSetValue(SharedCacheKey(AFileSystem, AFileName), mEntry);
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
  mKey: string;
  mShared: TShared;
begin
  if not AFileSystem.FileStamp(AFileName, AStamp) then
  begin
    AStamp := -1;
  end;
  mKey := KeyOf(AFileSystem, AFileName);
  // Unter der Sperre lesen: Ein zweiter Dienst wartet lieber, als dieselbe Datei ein zweites Mal zu laden.
  TMonitor.Enter(FLock);
  try
    if FFiles.TryGetValue(mKey, mShared) and (mShared.FStamp = AStamp) then
    begin
      Inc(mShared.FUsers);
      Exit(mShared.FEntries);
    end;
    mShared := TShared.Create;
    mShared.FStamp := AStamp;
    mShared.FEntries := ARead();
    mShared.FUsers := 1;
    FFiles.AddOrSetValue(mKey, mShared);
    Result := mShared.FEntries;
  finally
    TMonitor.Exit(FLock);
  end;
end;

class procedure TSharedCacheReads.Release(const AFileSystem: IIndexFileSystem; const AFileName: string;
  AStamp: Int64);
var
  mKey: string;
  mShared: TShared;
  mUnused: Boolean;
begin
  mKey := KeyOf(AFileSystem, AFileName);
  mUnused := False;
  TMonitor.Enter(FLock);
  try
    // Anderer Stand: Der Eintrag wurde schon ersetzt; die eigene Kopie hält der Aufrufer selbst.
    if not FFiles.TryGetValue(mKey, mShared) or (mShared.FStamp <> AStamp) then
    begin
      Exit;
    end;
    Dec(mShared.FUsers);
    if mShared.FUsers <= 0 then
    begin
      FFiles.Remove(mKey);
      mUnused := True;
    end;
  finally
    TMonitor.Exit(FLock);
  end;
  // Außerhalb der Lese-Sperre: Forget wartet auf ein laufendes Schreiben.
  if mUnused then
  begin
    TSharedCacheWrites.Forget(AFileSystem, AFileName);
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
    /// <summary>Gesetzt von Cancel; weckt Pause.</summary>
    FCancelEvent: TEvent;
    function IsCancelled: Boolean;
    function Pause(AMs: Cardinal): Boolean;
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
  FCancelEvent := TEvent.Create(nil, True, False, '');
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
  // Nach inherited: Das wartet auf Execute, das Pause noch rufen kann.
  FCancelEvent.Free;
end;

procedure TIndexThread.Cancel;
begin
  FCancelled := True;
  FCancelEvent.SetEvent;
end;

function TIndexThread.Pause(AMs: Cardinal): Boolean;
begin
  Result := FCancelled or (FCancelEvent.WaitFor(AMs) = wrSignaled);
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
    FService.Run(FRequest, IsCancelled, Pause);
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
  FStages := TIndexStageWatch.Create;
end;

destructor TIndexService.Destroy;
begin
  Stop;
  ReplaceBuilder(nil);
  FStages.Free;
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
  mPosition: Integer;
begin
  Result := AByFile.TryGetValue(AnsiUpperCase(AUnit.FileName), mPosition) and
    (AEntries[mPosition].Header.Stamp = AUnit.Stamp) and (AEntries[mPosition].Header.Hash = AUnit.Hash);
end;

function InSharedCache(const ARequest: TIndexRequest; const AFileName: string): Boolean;
begin
  // Ohne Installationsordner wie bisher: alle nachgeladenen Units in den gemeinsamen Cache.
  Result := (Length(ARequest.LibraryRoots) = 0) or TIndexFileDefines.IsUnder(AFileName, ARequest.LibraryRoots);
end;

/// <summary>Fehlt eine Unit aus AUnits in AEntries oder steht sie dort mit anderem Stand?</summary>
function MissingIn(const AEntries: TArray<TIndexCacheEntry>; AUnits: TList<TUnitIndex>): Boolean;
var
  mByFile: TDictionary<string, Integer>;
  mPosition: Integer;
  mUnitIndex: TUnitIndex;
begin
  Result := False;
  mByFile := TDictionary<string, Integer>.Create;
  try
    for mPosition := 0 to High(AEntries) do
    begin
      mByFile.AddOrSetValue(AnsiUpperCase(AEntries[mPosition].Header.FileName), mPosition);
    end;
    for mUnitIndex in AUnits do
    begin
      if not ContainsUnit(AEntries, mByFile, mUnitIndex) then
      begin
        Exit(True);
      end;
    end;
  finally
    mByFile.Free;
  end;
end;

/// <summary>Steht jede Unit aus AUnits mit demselben Stand in AWritten (zuletzt in diesem Prozess geschrieben)?
/// </summary>
function AllWritten(AWritten: TDictionary<string, string>; AUnits: TList<TUnitIndex>): Boolean;
var
  mUnitIndex: TUnitIndex;
  mState: string;
begin
  for mUnitIndex in AUnits do
  begin
    if not AWritten.TryGetValue(AnsiUpperCase(mUnitIndex.FileName), mState) or
      (mState <> TSharedCacheWrites.StateOf(mUnitIndex)) then
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
  mCurrent: TDictionary<string, Boolean>;
  mEntry: TIndexCacheEntry;
  mUnitIndex: TUnitIndex;
begin
  mCurrent := TDictionary<string, Boolean>.Create;
  try
    for mUnitIndex in AUnits do
    begin
      mCurrent.AddOrSetValue(AnsiUpperCase(mUnitIndex.FileName), True);
    end;
    for mEntry in AEntries do
    begin
      if not mCurrent.ContainsKey(AnsiUpperCase(mEntry.Header.FileName)) and
        TIndexCache.Expand(mEntry, mUnitIndex) then
      begin
        AUnits.Add(mUnitIndex);
      end;
    end;
  finally
    mCurrent.Free;
  end;
end;

/// <summary>Einträge der Cache-Datei AFileName; meldet einen verworfenen Cache über ARejected.</summary>
function ReadCacheFile(const AFileSystem: IIndexFileSystem; const AFileName: string;
  const ARejected: TIndexCacheRejectedEvent): TArray<TIndexCacheEntry>;
var
  mData: TBytes;
  mReason: string;
begin
  Result := nil;
  if (AFileName = '') or not AFileSystem.ReadBytes(AFileName, mData) then
  begin
    Exit;
  end;
  Result := TIndexCache.ReadEntries(mData, mReason);
  if (mReason <> '') and Assigned(ARejected) then
  begin
    ARejected(AFileName, mReason);
  end;
end;

/// <summary>Großgeschriebene Dateinamen aus AFiles ohne die aus AExcept (nil = keine).</summary>
function FileKeys(const AFiles: TArray<string>; AExcept: TDictionary<string, Boolean>): TDictionary<string, Boolean>;
var
  mFileName, mKey: string;
begin
  Result := TDictionary<string, Boolean>.Create;
  for mFileName in AFiles do
  begin
    mKey := AnsiUpperCase(mFileName);
    if (AExcept = nil) or not AExcept.ContainsKey(mKey) then
    begin
      Result.AddOrSetValue(mKey, True);
    end;
  end;
end;

/// <summary>Verteilt AUnits auf die Caches: Bibliothek, Suchpfade, Projekt. Der Index ist mit anderen Projekten
/// geteilt: in den Projekt-Cache nur die eigenen Units.</summary>
procedure SortUnits(const ARequest: TIndexRequest; const AUnits: TArray<TUnitIndex>;
  AProject, ASearch, ALibrary: TList<TUnitIndex>);
var
  mOwn, mSearched: TDictionary<string, Boolean>;
  mUnit: TUnitIndex;
  mKey: string;
begin
  mOwn := FileKeys(ARequest.Files, nil);
  mSearched := nil;
  try
    // Eine Projektdatei, die auch im Suchpfad liegt, bleibt im Projekt-Cache.
    mSearched := FileKeys(ARequest.SearchFiles, mOwn);
    for mUnit in AUnits do
    begin
      mKey := AnsiUpperCase(mUnit.FileName);
      if mUnit.Library_ and InSharedCache(ARequest, mUnit.FileName) then
      begin
        ALibrary.Add(mUnit);
      end
      else if (ARequest.SearchCacheFile <> '') and mSearched.ContainsKey(mKey) then
      begin
        ASearch.Add(mUnit);
      end
      else if mUnit.Library_ or mOwn.ContainsKey(mKey) or mSearched.ContainsKey(mKey) then
      begin
        // Über uses erreichte Units außerhalb der Installation (gemeinsamer Firmencode) liest
        // der Builder mit den Defines des Projekts; sie gehören in dessen Cache (#647).
        AProject.Add(mUnit);
      end;
    end;
  finally
    mSearched.Free;
    mOwn.Free;
  end;
end;

{ TIndexCacheWriter }

constructor TIndexCacheWriter.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const AEvents: TIndexCacheEvents; const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>;
  const APause: TIndexPause);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FEvents := AEvents;
  FRequest := ARequest;
  FCancelled := ACancelled;
  FPause := APause;
end;

function TIndexCacheWriter.ReadCache(const AFileName: string): TArray<TIndexCacheEntry>;
begin
  Result := ReadCacheFile(FFileSystem, AFileName, FEvents.Rejected);
end;

function TIndexCacheWriter.Load: TArray<TIndexCacheEntry>;
begin
  // Nur die Köpfe lesen; die Symbole dekodiert der Builder je Unit, wenn er sie übernimmt (#617).
  // Ein beschädigter Cache liefert nichts: Dann liest der Aufbau alles neu (#492).
  FCached := ReadCache(FRequest.CacheFile);
  // Bibliothek aus dem gemeinsamen Cache; Einträge im Projekt-Cache (ältere Stände) gelten weiter.
  // Alle Projekte teilen eine gelesene Kopie (Rückmeldung 15.10.2026).
  FLibraryCached := TSharedCacheHold.Acquire(FFileSystem, FRequest.LibraryCacheFile,
    function: TArray<TIndexCacheEntry>
    begin
      Result := ReadCache(FRequest.LibraryCacheFile);
    end, FLibraryHold);
  // Suchpfade ebenso: Die Projekte einer Gruppe teilen meist dieselben (Speicher, Rückmeldung 01.11.2026).
  FSearchCached := TSharedCacheHold.Acquire(FFileSystem, FRequest.SearchCacheFile,
    function: TArray<TIndexCacheEntry>
    begin
      Result := ReadCache(FRequest.SearchCacheFile);
    end, FSearchHold);
  Result := FLibraryCached + FSearchCached + FCached;
end;

procedure TIndexCacheWriter.Release;
begin
  FCached := nil;
  FLibraryCached := nil;
  FSearchCached := nil;
end;

const
  /// <summary>So lange wartet ein Aufbau höchstens darauf, den Bibliotheks-Cache schreiben zu dürfen; ein
  /// anderer Schreiber braucht für Lesen, Ergänzen und Schreiben wenige Sekunden.</summary>
  cLibraryLockWaitMs = 30000;
  /// <summary>Abstand, in dem nach der Sperre einer anderen Instanz gesehen wird (kein Signal über
  /// Prozesse).</summary>
  cLockPollMs = 100;

function TIndexCacheWriter.LockForWrite(const AFileName: string): IInterface;
var
  mWatch: TStopwatch;
begin
  mWatch := TStopwatch.StartNew;
  Result := FFileSystem.TryLockWrite(AFileName);
  while (Result = nil) and (mWatch.ElapsedMilliseconds < cLibraryLockWaitMs) do
  begin
    if FPause(cLockPollMs) then
    begin
      Exit;
    end;
    Result := FFileSystem.TryLockWrite(AFileName);
  end;
end;

procedure TIndexCacheWriter.NotWritten(const AFileName, AReason: string);
begin
  if Assigned(FEvents.NotWritten) then
  begin
    FEvents.NotWritten(AFileName, AReason);
  end;
end;

function TIndexCacheWriter.WriteCache(ALibrary: Boolean; const AFileName: string;
  const AUnits: TArray<TUnitIndex>): Boolean;
var
  mWatch: TStopwatch;
  mData: TBytes;
  mError: string;
begin
  mWatch := TStopwatch.StartNew;
  mData := TIndexCache.Serialize(AUnits);
  Result := FFileSystem.WriteBytes(AFileName, mData, mError);
  if not Result then
  begin
    NotWritten(AFileName, mError);
  end
  else if Assigned(FEvents.Written) then
  begin
    FEvents.Written(ALibrary, Length(AUnits), Length(mData), mWatch.ElapsedMilliseconds);
  end;
end;

procedure TIndexCacheWriter.WriteSharedCache(const AFileName: string;
  const AStartCached: TArray<TIndexCacheEntry>; AUnits: TList<TUnitIndex>);
var
  mWritten, mNewState: TDictionary<string, string>;
  mUnit: TUnitIndex;
  mLock: IInterface;
  mLatest: TArray<TIndexCacheEntry>;
begin
  // Hat in diesem Prozess schon ein Dienst diese Units in die unveränderte Datei geschrieben, gibt es
  // nichts Neues; dann weder sperren noch lesen. Sonst gegen den beim Start gelesenen Stand.
  mWritten := TSharedCacheWrites.Written(FFileSystem, AFileName);
  if (mWritten <> nil) and AllWritten(mWritten, AUnits) then
  begin
    Exit;
  end;
  if (mWritten = nil) and not MissingIn(AStartCached, AUnits) then
  begin
    Exit;
  end;
  // Ein Schreiber zur Zeit. Unter der Sperre den aktuellen Stand lesen: Ein anderes Projekt
  // oder ein anderer Prozess kann seit dem Start Units ergänzt haben, die sonst verloren gingen.
  mLock := LockForWrite(AFileName);
  if mLock = nil then
  begin
    // Abgebrochen ist kein Fehler: Der nächste Aufbau ergänzt den Cache.
    if not FCancelled() then
    begin
      NotWritten(AFileName, cTexts[TIndexServiceText.WriteLockNotObtained].Text);
    end;
    Exit;
  end;
  mLatest := ReadCache(AFileName);
  if not MissingIn(mLatest, AUnits) then
  begin
    Exit;
  end;
  AddOthers(mLatest, AUnits);
  mLatest := nil;
  if WriteCache(True, AFileName, AUnits.ToArray) then
  begin
    mNewState := TDictionary<string, string>.Create;
    for mUnit in AUnits do
    begin
      mNewState.AddOrSetValue(AnsiUpperCase(mUnit.FileName), TSharedCacheWrites.StateOf(mUnit));
    end;
    TSharedCacheWrites.Remember(FFileSystem, AFileName, mNewState);
  end;
end;

procedure TIndexCacheWriter.WriteSplit(AParsed: Integer);
var
  mProject, mSearch, mLibrary: TList<TUnitIndex>;
begin
  // Listen statt Array-Anhängen: das kopierte bei jeder Unit das ganze Array.
  mProject := TList<TUnitIndex>.Create;
  mSearch := TList<TUnitIndex>.Create;
  mLibrary := TList<TUnitIndex>.Create;
  try
    SortUnits(FRequest, FIndex.Units, mProject, mSearch, mLibrary);
    if (AParsed > 0) or (Length(FCached) <> mProject.Count) then
    begin
      WriteCache(False, FRequest.CacheFile, mProject.ToArray);
    end;
    if FRequest.SearchCacheFile <> '' then
    begin
      WriteSharedCache(FRequest.SearchCacheFile, FSearchCached, mSearch);
    end;
    WriteSharedCache(FRequest.LibraryCacheFile, FLibraryCached, mLibrary);
  finally
    mLibrary.Free;
    mSearch.Free;
    mProject.Free;
  end;
end;

procedure TIndexCacheWriter.WriteCaches(AParsedTotal: Integer);
var
  mParsed: Integer;
begin
  mParsed := AParsedTotal - FWrittenParsed;
  FWrittenParsed := AParsedTotal;
  if (FRequest.CacheFile = '') or FRequest.ReadOnlyCache then
  begin
    Exit;
  end;
  // Immer nur ein Dienst des Prozesses serialisiert (Rückmeldung 22.10.2026): Die Projekte einer Gruppe
  // enden fast gleichzeitig, jede Serialisierung belegt kurzzeitig ein Vielfaches der Datei. Gegen andere
  // Prozesse schützt die Schreibsperre der Datei.
  TSharedCacheWrites.Enter;
  try
    if FRequest.LibraryCacheFile <> '' then
    begin
      WriteSplit(mParsed);
    end
    else if (mParsed > 0) or (Length(FCached) <> FIndex.UnitCount) then
    begin
      WriteCache(False, FRequest.CacheFile, FIndex.Units);
    end;
  finally
    TSharedCacheWrites.Leave;
  end;
end;

/// <summary>Nach der Projektstufe schon schreiben (#647): In einer Projektgruppe endet der ganze Aufbau erst nach
/// allen Projekten; wer die IDE vorher schließt, begann sonst jedes Mal von vorn.</summary>
function ProjectDoneHandler(ACaches: TIndexCacheWriter; const AWatch: TStopwatch;
  const AReady: TIndexFinishedEvent): TIndexStageDone;
var
  mWatch: TStopwatch;
begin
  mWatch := AWatch;
  Result :=
    procedure(const APartial: TIndexBuildResult)
    begin
      ACaches.WriteCaches(APartial.Parsed);
      if Assigned(AReady) then
      begin
        AReady(APartial, mWatch.ElapsedMilliseconds);
      end;
    end;
end;

/// <summary>Abbruchabfrage des Dienstes für den Builder.</summary>
function BuilderCancelled(const ACancelled: TFunc<Boolean>): TIndexCancelled;
begin
  Result :=
    function: Boolean
    begin
      Result := ACancelled();
    end;
end;

function TIndexService.PrepareBuilder(const ARequest: TIndexRequest; const APause: TIndexPause;
  ACaches: TIndexCacheWriter): TIndexBuilder;
begin
  Result := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
  try
    Result.IncludePaths := ARequest.IncludePaths;
    Result.LibraryRoots := ARequest.LibraryRoots;
    Result.LibraryDefines := ARequest.LibraryDefines;
    Result.Usages := ARequest.Usages;
    if Assigned(ARequest.Prepare) then
    begin
      ARequest.Prepare();
    end;
    WaitForOtherWriter(ARequest, APause);
    TMonitor.Enter(FLock);
    try
      FCacheFile := ARequest.CacheFile;
    finally
      TMonitor.Exit(FLock);
    end;
    Result.UseCache(ACaches.Load);
  except
    // Noch nicht veröffentlicht: sonst bliebe der Builder als Leck zurück.
    Result.Free;
    raise;
  end;
end;

procedure TIndexService.Run(const ARequest: TIndexRequest; const ACancelled: TFunc<Boolean>;
  const APause: TIndexPause);
var
  mCaches: TIndexCacheWriter;
  mBuilder: TIndexBuilder;
  mWatch: TStopwatch;
  mResult: TIndexBuildResult;
  mTurn: IIndexTurn;
begin
  mCaches := TIndexCacheWriter.Create(FIndex, FFileSystem, FCacheEvents, ARequest, ACancelled, APause);
  try
    try
      mWatch := TStopwatch.StartNew;
      mBuilder := PrepareBuilder(ARequest, APause, mCaches);
      // Erst mit gefülltem Cache veröffentlichen; bis dahin bedient der alte Builder EnsureUnit.
      // Ab hier gehört der Builder dem Dienst.
      ReplaceBuilder(mBuilder);
      mTurn := nil;
      if FScheduler <> nil then
      begin
        mTurn := FScheduler.Register(ARequest.Priority);
      end;
      mTurn := FStages.Watch(mTurn);
      mBuilder.OnProjectDone := ProjectDoneHandler(mCaches, mWatch, FEvents.ProjectReady);
      mResult := mBuilder.Build(ARequest.Files, ARequest.SearchFiles, ARequest.LibraryFiles, FEvents.Progress,
        BuilderCancelled(ACancelled), mTurn);
      mBuilder.OnProjectDone := nil;
      // Abmelden vor dem Schreiben des Caches: Das nächste Projekt muss darauf nicht warten.
      mTurn := nil;
      if not mResult.Cancelled then
      begin
        mCaches.WriteCaches(mResult.Parsed);
      end;
      // Der Index hat alles übernommen; spätere Units (EnsureUnit) liest der Builder aus der Datei. Auch nach
      // einem Abbruch: Sonst hielt der Builder die Einträge samt String-Tabellen ganzer Cache-Dateien, bis ein
      // neuer Aufbau ihn ersetzte, und ein abgebrochener Aufbau ohne Nachfolger behielt sie (Speicher,
      // Rückmeldung 01.11.2026).
      mBuilder.ReleaseCache;
      mCaches.Release;
      if Assigned(FEvents.Finished) then
      begin
        FEvents.Finished(mResult, mWatch.ElapsedMilliseconds);
      end;
    except
      // lsp-ignore: catch-all-without-raise -- Fehlergrenze des Hintergrundlaufs; ReportError meldet
      on E: Exception do
        ReportError(E);
    end;
  finally
    FStages.Clear;
    // Gemeinsame Kopien freigeben (TSharedCacheHold), auch nach einer Ausnahme.
    mCaches.Free;
  end;
end;

function TIndexService.StageState: TIndexStageState;
begin
  Result := FStages.State;
end;

procedure TIndexService.ReportError(const AError: Exception);
begin
  if not Assigned(FEvents.Error) then
  begin
    Exit;
  end;
  try
    FEvents.Error(AError);
  except
    // Sonst läge die Ausnahme ungelesen in TThread.FatalException.
  end;
end;

const
  /// <summary>Abstand, in dem nach dem Cache einer anderen Instanz gesehen wird (kein Signal über Prozesse).</summary>
  cOtherWriterPollMs = 200;

procedure TIndexService.WaitForOtherWriter(const ARequest: TIndexRequest; const APause: TIndexPause);
var
  mWatch: TStopwatch;
  mBefore, mStamp: Int64;
begin
  if (ARequest.CacheFile = '') or not ARequest.ReadOnlyCache or not Assigned(ARequest.CacheBusy) then
  begin
    Exit;
  end;
  if not FFileSystem.FileStamp(ARequest.CacheFile, mBefore) then
  begin
    mBefore := 0;
  end;
  mWatch := TStopwatch.StartNew;
  // Bis die andere Instanz einen neuen Stand geschrieben oder die Sperre freigegeben hat,
  // nie länger als CacheWaitMs.
  while (mWatch.ElapsedMilliseconds < ARequest.CacheWaitMs) and ARequest.CacheBusy() do
  begin
    if FFileSystem.FileStamp(ARequest.CacheFile, mStamp) and (mStamp <> mBefore) then
    begin
      Exit;
    end;
    if APause(cOtherWriterPollMs) then
    begin
      Exit;
    end;
  end;
end;

procedure TIndexService.Start(const ARequest: TIndexRequest);
var
  mPrevious: TThread;
begin
  // Nicht warten (#874): Der neue Thread wartet auf den abgebrochenen und gibt ihn frei.
  mPrevious := FThread;
  FThread := nil;
  if mPrevious <> nil then
  begin
    TIndexThread(mPrevious).Cancel;
  end;
  FThread := TIndexThread.Create(Self, ARequest, mPrevious);
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
  mOld: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    // Neue Anfragen sehen sofort den neuen Builder; der alte wird frei, sobald niemand ihn nutzt.
    mOld := FBuilder;
    FBuilder := nil;
    while FUsers > 0 do
    begin
      TMonitor.Wait(FLock, INFINITE);
    end;
    FBuilder := ABuilder;
  finally
    TMonitor.Exit(FLock);
  end;
  mOld.Free;
end;

function TIndexService.EnsureUnit(const AUnitName: string): Boolean;
var
  mBuilder: TIndexBuilder;
  mExisting: TUnitIndex;
begin
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(FIndex.FindUnit(AUnitName, mExisting));
  end;
  try
    Result := mBuilder.EnsureUnit(AUnitName);
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyText(const AFileName, AText: string): Boolean;
var
  mBuilder: TIndexBuilder;
begin
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(False);
  end;
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := mBuilder.ApplyText(AFileName, AText);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.UsagesOf(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mExisting: TUnitIndex;
  mCacheFile: string;
  mEntry: TIndexCacheEntry;
  mBuilder: TIndexBuilder;
begin
  AUsages := nil;
  if not FIndex.FindFile(AFileName, mExisting) or not mExisting.UsagesIndexed then
  begin
    Exit(False);
  end;
  if not mExisting.UsagesOffloaded then
  begin
    AUsages := mExisting.Usages;
    Exit(True);
  end;
  // Ausgelagert: aus dem Cache, wenn er denselben Stand der Unit hat.
  TMonitor.Enter(FLock);
  try
    mCacheFile := FCacheFile;
  finally
    TMonitor.Exit(FLock);
  end;
  for mEntry in ReadCacheFile(FFileSystem, mCacheFile, FCacheEvents.Rejected) do
  begin
    if SameText(mEntry.Header.FileName, AFileName) and (mEntry.Header.Hash = mExisting.Hash) and
      mEntry.Header.UsagesIndexed then
    begin
      Exit(TIndexCache.ExpandUsages(mEntry, AUsages));
    end;
  end;
  // Noch nicht geschrieben (neu eingelesen): aus der Datei.
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(False);
  end;
  try
    Result := mBuilder.ReadUsages(AFileName, AUsages);
  finally
    ReleaseBuilder;
  end;
end;

function TIndexService.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  mBuilder: TIndexBuilder;
begin
  mBuilder := AcquireBuilder;
  if mBuilder = nil then
  begin
    Exit(0);
  end;
  try
    TMonitor.Enter(FApplyLock);
    try
      Result := mBuilder.ApplyChanges(AChanges);
    finally
      TMonitor.Exit(FApplyLock);
    end;
  finally
    ReleaseBuilder;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Index.Service', cTexts);

end.
