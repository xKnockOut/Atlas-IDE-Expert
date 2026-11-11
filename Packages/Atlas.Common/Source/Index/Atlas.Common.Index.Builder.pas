unit Atlas.Common.Index.Builder;

// Baut den Symbolindex auf.
//
// - Build: indiziert die Projektdateien. Einträge aus dem Cache gelten
//   weiter, wenn der Zeitstempel gleich ist (Datei wird nicht gelesen) oder
//   der Hash des Inhalts gleich ist (nur der Zeitstempel wird erneuert).
// - Danach werden die referenzierten Units (uses) bedarfsweise über den
//   Resolver gesucht und indiziert, rekursiv, aber nur was wirklich in einer
//   uses-Liste vorkommt. So kommen RTL und VCL nur teilweise in den Index.
// - EnsureUnit indiziert eine einzelne Unit nachträglich.
// - ApplyChanges übernimmt Dateiänderungen von außen (git checkout,
//   andere Werkzeuge): bekannte Units neu einlesen, gelöschte entfernen.
//   Neue Dateien kommen erst in den Index, wenn sie referenziert werden;
//   dafür vergisst der Builder die bisher nicht gefundenen Units.
// - Include-Dateien (#264) werden über IncludePaths gesucht. Units mit
//   Includes übernimmt der Builder aus dem Cache nur, wenn auch alle
//   Include-Dateien denselben Zeitstempel haben (#617); eine geänderte
//   Include-Datei liest alle Units neu ein, die sie einbinden.
// - Aus dem Cache kommen zunächst nur die Köpfe; die Symbole einer Unit
//   dekodiert der Builder erst, wenn er die Unit übernimmt (#617).
// - Mit Usages (#492, index.usages) erfasst der Builder in Projekt-Units auch
//   die Verwendungen der Bezeichner. Ein Cache-Eintrag ohne sie gilt dann als
//   veraltet; ohne Usages bleiben Verwendungen aus dem Cache weg.
// - Projekt-Units bekommen beim Einlesen ihre Folgemuster (#1890, gelernte
//   Vorschläge); sie kommen mit dem Eintrag in den Cache. Bibliotheken nicht.
// - Läuft im aufrufenden Thread; den Hintergrund-Thread stellt die
//   Komposition bereit.
// - Jede Datei liest nur ein Thread zur selben Zeit (#1236): Fragen Aufbau und
//   Anfragen (EnsureUnit) dieselbe Unit gleichzeitig an, wartet der zweite
//   auf den ersten und übernimmt sein Ergebnis. Früher parsten beim Start
//   mehrere Anfrage-Threads und der Aufbau dieselben RTL-/VCL-Units parallel.
//   Verschiedene Units laufen weiter parallel (#617).
// - ReleaseCache gibt die Cache-Einträge nach dem Aufbau frei (Rückmeldung
//   15.10.2026): Jeder Eintrag hält die ganze gelesene Cache-Datei; mit sechs
//   Projekten lagen so Projekt- und Bibliotheks-Cache sechsmal im Speicher,
//   obwohl der Index sie längst übernommen hatte.

interface

uses
  System.SysUtils,
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Pascal.Preprocessor,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache;

type
  /// <summary>Warum der Builder eine Unit neu einlas statt aus dem Cache (Diagnoselog, Rückmeldung
  /// 22.10.2026: bei jedem Start rund 2300 Units neu): kein Eintrag, Datei geändert, Include-Datei geändert,
  /// Verwendungen fehlen, kompakter Eintrag nicht verwendbar, Block beschädigt.</summary>
  TIndexCacheMiss = (NoEntry, Changed, Includes, Usages, Compact, Damaged);

  TIndexBuildResult = record
    Parsed: Integer;
    /// <summary>Parsed nach Grund; die Summe ist Parsed.</summary>
    Misses: array[TIndexCacheMiss] of Integer;
    FromCache: Integer;
    Missing: Integer;
    /// <summary>Zeit für das Suchen der Unit-Dateien (uses) und für das Parsen, fürs Diagnoselog (#647).</summary>
    ResolveMs: Int64;
    ParseMs: Int64;
    Cancelled: Boolean;
  end;

  /// <summary>Eine Stufe des Aufbaus ist fertig; APartial ist der Stand bis dahin.</summary>
  TIndexStageDone = reference to procedure(const APartial: TIndexBuildResult);

  /// <summary>Defines je Datei (#647): Dateien unter LibraryRoots (Delphi-Installation) mit LibraryDefines, alle
  /// anderen mit denen des Projekts.</summary>
  TIndexFileDefines = record
    Project: TArray<string>;
    LibraryDefines: TArray<string>;
    LibraryRoots: TArray<string>;
    function DefinesOf(const AFileName: string): TArray<string>;
    /// <summary>Schlüssel der Defines für AFileName (TUnitIndex.DefinesKey).</summary>
    function KeyOf(const AFileName: string): string;
    /// <summary>Liegt AFileName unter einem der Ordner aus ARoots?</summary>
    class function IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean; static;
  end;

  /// <summary>Threadsichere Menge von Schlüsseln (Großschreibung) für den Builder: nicht gefundene Units und
  /// Dateien, die gerade ein Thread liest (#1236).</summary>
  TIndexKeySet = class
  private
    FKeys: TDictionary<string, Boolean>;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    function Contains(const AKey: string): Boolean;
    procedure Add(const AKey: string);
    /// <summary>Entfernt AKey und weckt alle, die in Claim darauf warten.</summary>
    procedure Remove(const AKey: string);
    procedure Clear;
    /// <summary>Wartet, bis AKey frei ist, und trägt ihn ein. False (nicht eingetragen), wenn gewartet wurde und
    /// AAlreadyDone danach gilt: Dann hat ein anderer Thread die Arbeit schon erledigt.</summary>
    function Claim(const AKey: string; const AAlreadyDone: TFunc<Boolean>): Boolean;
  end;

  /// <summary>Threadsicherer Vergleichsstand aus dem Cache: EnsureUnit liest ihn aus Anfrage-Threads,
  /// ReleaseCache leert ihn.</summary>
  TIndexCacheEntries = class
  private
    FEntries: TDictionary<string, TIndexCacheEntry>;
    FLock: TObject;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AFileName: string; const AEntry: TIndexCacheEntry);
    function TryGet(const AFileName: string; out AEntry: TIndexCacheEntry): Boolean;
    procedure Clear;
    function Count: Integer;
  end;

  /// <summary>Was alle Stufen eines Aufbaus teilen: Fortschritt, Abbruch, Reihenfolge mehrerer Aufbauten,
  /// Gesamtzahl der Dateien für die Prozentangabe.</summary>
  TIndexStageRun = record
    Progress: TIndexProgressEvent;
    Cancelled: TIndexCancelled;
    Turn: IIndexTurn;
    Total: Integer;
  end;

  TIndexBuilder = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FResolveUnit: TUnitFileResolver;
    FCache: TIndexCacheEntries;
    // Von EnsureUnit aus Anfrage-Threads genutzt.
    FFailedUnits: TIndexKeySet;
    // Dateien, die gerade ein Thread liest.
    FInFlight: TIndexKeySet;
    FIncludePaths: TArray<string>;
    FDefines: TIndexFileDefines;
    FUsages: Boolean;
    FOnProjectDone: TIndexStageDone;
    function WantsUsages(ALibrary: Boolean): Boolean;
    /// <summary>Taugt der Cache-Eintrag? AMiss nennt bei False den Grund.</summary>
    function CacheFits(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AMiss: TIndexCacheMiss): Boolean;
    function FromCache(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AUnit: TUnitIndex): Boolean;
    function IncludeResolver: TIncludeResolver;
    /// <summary>Steht AFileName mit Stand AStamp schon passend im Index, z. B. von einem anderen Projekt der
    /// Gruppe mit denselben Defines? Dann nicht noch einmal übernehmen.</summary>
    function AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
    /// <summary>Indiziert AFileName; liest ein anderer Thread die Datei gerade, wartet es auf ihn und übernimmt sein
    /// Ergebnis (#1236).</summary>
    function IndexFile(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    function IndexFileNow(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    /// <summary>Liest AText neu ein und übernimmt die Unit in den Index (Parsed).</summary>
    procedure ParseFile(const AFileName, AText, AHash: string; AStamp: Int64; ALibrary: Boolean;
      var AResult: TIndexBuildResult);
    procedure IndexReferenced(var AResult: TIndexBuildResult; const ARun: TIndexStageRun);
    /// <summary>Holt die über uses genannte Unit AName in den Index, falls nötig; AUses sind die uses, denen der
    /// Aufbau weiter folgt. False, wenn es nichts zu folgen gibt.</summary>
    function NextReferenced(const AName: string; var AResult: TIndexBuildResult;
      const AProgress: TIndexProgressEvent; out AUses: TArray<string>): Boolean;
    /// <summary>Eine Stufe (#648): AFiles einlesen, in der Projektstufe auch über uses erreichbare Units. Wartet über
    /// ARun.Turn auf ihre Reihe; False bei Abbruch (dann ist AResult.Cancelled gesetzt).</summary>
    function RunStage(AStage: TIndexStage; const AFiles: TArray<string>; const ALabel: string; ADone: Integer;
      var AResult: TIndexBuildResult; const ARun: TIndexStageRun): Boolean;
    /// <summary>Eine Dateiänderung übernehmen; liefert die Zahl geänderter Units.</summary>
    function ApplyChange(const AChange: TFileChange; var AIgnored: TIndexBuildResult): Integer;
  public
    constructor Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
      const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
    destructor Destroy; override;
    /// <summary>Übernimmt einen geladenen Cache als Vergleichsstand.</summary>
    procedure UseCache(const AUnits: TArray<TUnitIndex>); overload;
    /// <summary>Übernimmt die Köpfe eines Caches; Symbole werden erst bei Bedarf dekodiert.</summary>
    procedure UseCache(const AEntries: TArray<TIndexCacheEntry>); overload;
    /// <summary>Gibt die Cache-Einträge frei (nach dem Aufbau); spätere Units liest der Builder aus der Datei.
    /// Threadsicher.</summary>
    procedure ReleaseCache;
    /// <summary>Zahl der gehaltenen Cache-Einträge (für Tests).</summary>
    function CachedCount: Integer;
    function Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled): TIndexBuildResult; overload;
    /// <summary>Aufbau in Stufen (#648): AFiles samt über uses erreichbarer Units, dann ASearchFiles (Projekt),
    /// dann ALibraryFiles (Bibliothek). ATurn ordnet die Stufen mehrerer Aufbauten; nil = ohne Warten.
    /// Nach der Projektstufe läuft OnProjectDone.</summary>
    function Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled; const ATurn: IIndexTurn): TIndexBuildResult; overload;
    /// <summary>Indiziert die Unit, falls noch nicht vorhanden. False, wenn sie nicht gefunden wird.</summary>
    function EnsureUnit(const AUnitName: string): Boolean;
    /// <summary>Übernimmt Dateiänderungen; liefert die Zahl geänderter Units.</summary>
    function ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
    /// <summary>Ungespeicherter Text einer bekannten Unit (Tipp-Pause, #492): nur im Speicher, ohne Cache;
    /// True, wenn der Index sich dadurch geändert hat.</summary>
    function ApplyText(const AFileName, AText: string): Boolean;
    /// <summary>Suchpfade für $I nach dem Ordner der Unit (Projekt-Suchpfade, dann Bibliothekspfade).</summary>
    property IncludePaths: TArray<string> read FIncludePaths write FIncludePaths;
    /// <summary>Verwendungen der Bezeichner in Projekt-Units erfassen (#492); Standard aus.</summary>
    property Usages: Boolean read FUsages write FUsages;
    /// <summary>Verwendungen einer Unit frisch aus der Datei (ausgelagert und nicht im Cache).</summary>
    function ReadUsages(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
    /// <summary>Ordner der Delphi-Installation (BDS-Ordner) samt Unterordnern.
    /// Deren Units kommen als fertige DCUs; die Defines des Projekts wirken nicht auf sie. Leer = alle
    /// Dateien mit den Defines des Projekts.</summary>
    property LibraryRoots: TArray<string> read FDefines.LibraryRoots write FDefines.LibraryRoots;
    /// <summary>Symbole für Dateien unter LibraryRoots: nur die des Compilers (Plattform, Version).</summary>
    property LibraryDefines: TArray<string> read FDefines.LibraryDefines write FDefines.LibraryDefines;
    /// <summary>Läuft nach der Projektstufe (Projektdateien und über uses erreichbare Units) mit dem Stand bis
    /// dahin, z. B. um den Projekt-Cache früh zu schreiben (#647).</summary>
    property OnProjectDone: TIndexStageDone read FOnProjectDone write FOnProjectDone;
  end;

implementation

uses
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TBuilderText = (SymbolIndex, SearchPaths, LibraryText, UnitsSymbols);

const
  cTexts: array[TBuilderText] of TAtlasText = (
    (De: 'Symbolindex'; En: 'Symbol index'),
    (De: 'Suchpfade: '; En: 'Search paths: '),
    (De: 'Bibliothek: '; En: 'Library: '),
    (De: '%d Units, %d Symbole'; En: '%d units, %d symbols'));

{$SCOPEDENUMS OFF}

function IsCancelled(const ACancelled: TIndexCancelled): Boolean;
begin
  Result := Assigned(ACancelled) and ACancelled();
end;

/// <summary>Zeitstempel der Include-Dateien beim Einlesen, parallel zu AIncludes; -1 = fehlt.</summary>
function IncludeStampsOf(const AFileSystem: IIndexFileSystem; const AIncludes: TArray<string>): TArray<Int64>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AIncludes));
  for mIndex := 0 to High(AIncludes) do
  begin
    if not AFileSystem.FileStamp(AIncludes[mIndex], Result[mIndex]) then
    begin
      Result[mIndex] := -1;
    end;
  end;
end;

/// <summary>Haben alle Include-Dateien von ACached noch den Zeitstempel vom Einlesen (#617)?</summary>
function IncludesUnchanged(const AFileSystem: IIndexFileSystem; const ACached: TUnitIndex): Boolean;
var
  mIndex: Integer;
  mStamp: Int64;
begin
  // Ältere Einträge ohne Zeitstempel gelten als geändert.
  Result := Length(ACached.IncludeStamps) = Length(ACached.Includes);
  mIndex := 0;
  while Result and (mIndex < Length(ACached.Includes)) do
  begin
    Result := AFileSystem.FileStamp(ACached.Includes[mIndex], mStamp) and (ACached.IncludeStamps[mIndex] >= 0) and
      (mStamp = ACached.IncludeStamps[mIndex]);
    Inc(mIndex);
  end;
end;

procedure EnqueueAll(APending: TQueue<string>; const ANames: TArray<string>);
var
  mName: string;
begin
  for mName in ANames do
  begin
    APending.Enqueue(mName);
  end;
end;

/// <summary>Units in AIndex gelten als gesehen; ihre uses (interface und implementation) warten in APending.</summary>
procedure SeedReferenced(const AIndex: ISymbolIndex; APending: TQueue<string>; ASeen: TDictionary<string, Boolean>);
var
  mUnit: TUnitIndex;
begin
  for mUnit in AIndex.Units do
  begin
    ASeen.AddOrSetValue(UpperCase(mUnit.UnitName), True);
    EnqueueAll(APending, mUnit.InterfaceUses);
    EnqueueAll(APending, mUnit.ImplementationUses);
  end;
end;

/// <summary>Units in AIndex, die AFileName per $I einbinden.</summary>
function DependentsOf(const AIndex: ISymbolIndex; const AFileName: string): TArray<TUnitIndex>;
var
  mList: TList<TUnitIndex>;
  mUnit: TUnitIndex;
  mInclude: string;
begin
  mList := TList<TUnitIndex>.Create;
  try
    for mUnit in AIndex.Units do
    begin
      for mInclude in mUnit.Includes do
      begin
        if SameText(mInclude, AFileName) then
        begin
          mList.Add(mUnit);
          Break;
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

{ TIndexFileDefines }

class function TIndexFileDefines.IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean;
var
  mRoot: string;
begin
  // Windows-Pfade auch unter anderen Systemen (Tests): beide Trenner gelten.
  Result := False;
  for mRoot in ARoots do
  begin
    if (mRoot <> '') and AFileName.StartsWith(mRoot, True) and (CharInSet(mRoot[Length(mRoot)], ['\', '/']) or
      ((Length(AFileName) > Length(mRoot)) and CharInSet(AFileName[Length(mRoot) + 1], ['\', '/']))) then
    begin
      Exit(True);
    end;
  end;
end;

function TIndexFileDefines.DefinesOf(const AFileName: string): TArray<string>;
begin
  // RTL, VCL und FMX einmal je Compiler und Plattform statt je Projekt-Defines (#647).
  if IsUnder(AFileName, LibraryRoots) then
  begin
    Result := LibraryDefines;
  end
  else
  begin
    Result := Project;
  end;
end;

function TIndexFileDefines.KeyOf(const AFileName: string): string;
begin
  Result := AnsiUpperCase(String.Join(';', DefinesOf(AFileName)));
end;

{ TIndexKeySet }

constructor TIndexKeySet.Create;
begin
  inherited Create;
  FKeys := TDictionary<string, Boolean>.Create;
  FLock := TObject.Create;
end;

destructor TIndexKeySet.Destroy;
begin
  FLock.Free;
  FKeys.Free;
  inherited;
end;

function TIndexKeySet.Contains(const AKey: string): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FKeys.ContainsKey(AnsiUpperCase(AKey));
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Add(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FKeys.AddOrSetValue(AnsiUpperCase(AKey), True);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Remove(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FKeys.Remove(AnsiUpperCase(AKey));
    TMonitor.PulseAll(FLock);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexKeySet.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FKeys.Clear;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexKeySet.Claim(const AKey: string; const AAlreadyDone: TFunc<Boolean>): Boolean;
const
  cWaitSliceMs = 50;
var
  mKey: string;
  mWaited: Boolean;
begin
  mKey := AnsiUpperCase(AKey);
  mWaited := False;
  TMonitor.Enter(FLock);
  try
    while FKeys.ContainsKey(mKey) do
    begin
      mWaited := True;
      TMonitor.Wait(FLock, cWaitSliceMs);
    end;
    Result := not (mWaited and AAlreadyDone());
    if Result then
    begin
      FKeys.Add(mKey, True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TIndexCacheEntries }

constructor TIndexCacheEntries.Create;
begin
  inherited Create;
  FEntries := TDictionary<string, TIndexCacheEntry>.Create;
  FLock := TObject.Create;
end;

destructor TIndexCacheEntries.Destroy;
begin
  FLock.Free;
  FEntries.Free;
  inherited;
end;

procedure TIndexCacheEntries.Add(const AFileName: string; const AEntry: TIndexCacheEntry);
begin
  TMonitor.Enter(FLock);
  try
    FEntries.AddOrSetValue(AnsiUpperCase(AFileName), AEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexCacheEntries.TryGet(const AFileName: string; out AEntry: TIndexCacheEntry): Boolean;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.TryGetValue(AnsiUpperCase(AFileName), AEntry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TIndexCacheEntries.Clear;
begin
  TMonitor.Enter(FLock);
  try
    FEntries.Clear;
    FEntries.TrimExcess;
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexCacheEntries.Count: Integer;
begin
  TMonitor.Enter(FLock);
  try
    Result := FEntries.Count;
  finally
    TMonitor.Exit(FLock);
  end;
end;

{ TIndexBuilder }

constructor TIndexBuilder.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FDefines.Project := ADefines;
  FResolveUnit := AResolveUnit;
  FCache := TIndexCacheEntries.Create;
  FFailedUnits := TIndexKeySet.Create;
  FInFlight := TIndexKeySet.Create;
end;

function TIndexBuilder.AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
var
  mExisting: TUnitIndex;
begin
  // Ohne diese Prüfung übernahm jedes Projekt einer Gruppe die gemeinsamen Units erneut (aus dem Cache oder
  // geparst) und ersetzte die des vorigen; die Namenslisten des Index behielten die ersetzten Einträge, bis es
  // mehr tote als lebende gab (Speicher, Rückmeldung 01.11.2026). Bedingungen wie bei CacheFits.
  Result := FIndex.FindFile(AFileName, mExisting) and (mExisting.Stamp = AStamp) and
    (mExisting.DefinesKey <> '') and (mExisting.DefinesKey = FDefines.KeyOf(AFileName)) and
    (mExisting.Library_ = ALibrary) and IncludesUnchanged(FFileSystem, mExisting) and
    (mExisting.UsagesIndexed or not WantsUsages(ALibrary)) and
    (not mExisting.Compact or (ALibrary and (FIndex.Budget > 0)));
end;

destructor TIndexBuilder.Destroy;
begin
  FInFlight.Free;
  FFailedUnits.Free;
  FCache.Free;
  inherited;
end;

procedure TIndexBuilder.UseCache(const AUnits: TArray<TUnitIndex>);
var
  mUnitIndex: TUnitIndex;
begin
  // Ob ein kompakter Eintrag taugt, entscheidet CacheFits beim Einlesen.
  for mUnitIndex in AUnits do
  begin
    FCache.Add(mUnitIndex.FileName, TIndexCacheEntry.FromUnit(mUnitIndex));
  end;
end;

procedure TIndexBuilder.UseCache(const AEntries: TArray<TIndexCacheEntry>);
var
  mEntry: TIndexCacheEntry;
begin
  for mEntry in AEntries do
  begin
    FCache.Add(mEntry.Header.FileName, mEntry);
  end;
end;

procedure TIndexBuilder.ReleaseCache;
begin
  FCache.Clear;
end;

function TIndexBuilder.CachedCount: Integer;
begin
  Result := FCache.Count;
end;

function TIndexBuilder.IncludeResolver: TIncludeResolver;
var
  mFileSystem: IIndexFileSystem;
begin
  mFileSystem := FFileSystem;
  Result := TIncludeFiles.Resolver(FIncludePaths,
    function(const AFileName: string): Boolean
    var
      Stamp: Int64;
    begin
      Result := mFileSystem.FileStamp(AFileName, Stamp);
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := mFileSystem.ReadText(AFileName, AText);
    end);
end;

function TIndexBuilder.WantsUsages(ALibrary: Boolean): Boolean;
begin
  Result := FUsages and not ALibrary;
end;

function TIndexBuilder.CacheFits(const AEntry: TIndexCacheEntry; ALibrary: Boolean;
  out AMiss: TIndexCacheMiss): Boolean;
begin
  AMiss := TIndexCacheMiss.NoEntry;
  // Mit Includes kann sich das Ergebnis ändern, ohne dass die Unit sich ändert; ohne erfasste
  // Verwendungen taugt der Eintrag nicht, sobald sie gebraucht werden.
  Result := IncludesUnchanged(FFileSystem, AEntry.Header);
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Includes;
    Exit;
  end;
  Result := AEntry.Header.UsagesIndexed or not WantsUsages(ALibrary);
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Usages;
    Exit;
  end;
  // Kompakten Einträgen fehlen die Symbole aus dem implementation-Teil. Für Bibliotheken reicht
  // das, solange ein Budget gilt: der Index würde sie ohnehin wieder kompakt halten. Sonst liefen
  // bei knappem Budget alle Bibliotheken bei jedem Start durch den Parser (Diagnoselog 15.10.2026).
  if AEntry.Header.Compact then
  begin
    Result := ALibrary and (FIndex.Budget > 0);
  end;
  if not Result then
  begin
    AMiss := TIndexCacheMiss.Compact;
  end;
end;

function TIndexBuilder.FromCache(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AUnit: TUnitIndex): Boolean;
begin
  Result := TIndexCache.Expand(AEntry, AUnit, WantsUsages(ALibrary));
  if Result and not WantsUsages(ALibrary) then
  begin
    AUnit.Usages := nil;
    AUnit.UsagesIndexed := False;
    AUnit.UsagesOffloaded := False;
  end;
end;

function TIndexBuilder.ReadUsages(const AFileName: string; out AUsages: TArray<TIndexUsage>): Boolean;
var
  mText: string;
begin
  AUsages := nil;
  Result := FFileSystem.ReadText(AFileName, mText);
  if Result then
  begin
    AUsages := TIndexExtractor.ExtractText(mText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
      True).Usages;
  end;
end;

function TIndexBuilder.IndexFile(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
var
  mIndex: ISymbolIndex;
  mFileName: string;
begin
  mIndex := FIndex;
  mFileName := AFileName;
  // Ein anderer Thread hat die Datei eben gelesen: sein Ergebnis gilt, kein zweites Parsen.
  if not FInFlight.Claim(AFileName,
    function: Boolean
    var
      mExisting: TUnitIndex;
    begin
      Result := mIndex.FindFile(mFileName, mExisting);
    end) then
  begin
    Exit(True);
  end;
  try
    Result := IndexFileNow(AFileName, ALibrary, AResult);
  finally
    FInFlight.Remove(AFileName);
  end;
end;

function TIndexBuilder.IndexFileNow(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
var
  mStamp: Int64;
  mText, mHash: string;
  mEntry: TIndexCacheEntry;
  mCached: TUnitIndex;
  mHasCache, mTaken: Boolean;
  mMiss: TIndexCacheMiss;
begin
  if not FFileSystem.FileStamp(AFileName, mStamp) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  if AlreadyIndexed(AFileName, mStamp, ALibrary) then
  begin
    Inc(AResult.FromCache);
    Exit(True);
  end;
  mMiss := TIndexCacheMiss.NoEntry;
  mHasCache := FCache.TryGet(AFileName, mEntry) and CacheFits(mEntry, ALibrary, mMiss);
  // Zeitstempel oder Inhalt passen: erst jetzt die Symbole dekodieren; ein beschädigter Block
  // zählt wie ein fehlender Cache-Eintrag.
  mTaken := mHasCache and (mEntry.Header.Stamp = mStamp) and FromCache(mEntry, ALibrary, mCached);
  if not mTaken then
  begin
    if not FFileSystem.ReadText(AFileName, mText) then
    begin
      Inc(AResult.Missing);
      Exit(False);
    end;
    mHash := TIndexCache.HashOf(mText);
    if mHasCache and (mEntry.Header.Hash = mHash) then
    begin
      mTaken := FromCache(mEntry, ALibrary, mCached);
      mMiss := TIndexCacheMiss.Damaged;
    end
    else if mHasCache then
    begin
      mMiss := TIndexCacheMiss.Changed;
    end;
  end;
  if mTaken then
  begin
    mCached.Stamp := mStamp;
    mCached.Library_ := ALibrary;
    mCached.DefinesKey := FDefines.KeyOf(AFileName);
    FIndex.AddUnit(mCached);
    Inc(AResult.FromCache);
    Exit(True);
  end;
  ParseFile(AFileName, mText, mHash, mStamp, ALibrary, AResult);
  Inc(AResult.Misses[mMiss]);
  Result := True;
end;

procedure TIndexBuilder.ParseFile(const AFileName, AText, AHash: string; AStamp: Int64; ALibrary: Boolean;
  var AResult: TIndexBuildResult);
var
  mWatch: TStopwatch;
  mUnit: TUnitIndex;
begin
  mWatch := TStopwatch.StartNew;
  mUnit := TIndexExtractor.ExtractText(AText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
    WantsUsages(ALibrary), not ALibrary);
  Inc(AResult.ParseMs, mWatch.ElapsedMilliseconds);
  mUnit.Stamp := AStamp;
  mUnit.Hash := AHash;
  mUnit.IncludeStamps := IncludeStampsOf(FFileSystem, mUnit.Includes);
  mUnit.Library_ := ALibrary;
  mUnit.DefinesKey := FDefines.KeyOf(AFileName);
  FIndex.AddUnit(mUnit);
  Inc(AResult.Parsed);
end;

function TIndexBuilder.NextReferenced(const AName: string; var AResult: TIndexBuildResult;
  const AProgress: TIndexProgressEvent; out AUses: TArray<string>): Boolean;
var
  mExisting: TUnitIndex;
  mFileName: string;
  mStamp: Int64;
  mWatch: TStopwatch;
begin
  AUses := nil;
  if FIndex.FindUnit(AName, mExisting) then
  begin
    Exit(False);
  end;
  mWatch := TStopwatch.StartNew;
  mFileName := FResolveUnit(AName);
  Inc(AResult.ResolveMs, mWatch.ElapsedMilliseconds);
  if mFileName = '' then
  begin
    Exit(False);
  end;
  // Unter anderem Namen schon im Index, z. B. "Forms" als Vcl.Forms aus einem anderen Projekt
  // der Gruppe: nicht neu einlesen. Sonst las jedes Projekt dieselben Units erneut (#647).
  if not (FIndex.FindFile(mFileName, mExisting) and FFileSystem.FileStamp(mFileName, mStamp) and
    (mStamp = mExisting.Stamp)) then
  begin
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Report, AName, -1);
    end;
    if not (IndexFile(mFileName, True, AResult) and FIndex.FindFile(mFileName, mExisting)) then
    begin
      Exit(False);
    end;
  end;
  // Nur das interface ist von außen sichtbar; dessen uses reichen.
  AUses := mExisting.InterfaceUses;
  Result := True;
end;

procedure TIndexBuilder.IndexReferenced(var AResult: TIndexBuildResult; const ARun: TIndexStageRun);
var
  mPending: TQueue<string>;
  mSeen: TDictionary<string, Boolean>;
  mName: string;
  mUses_: TArray<string>;
begin
  if not Assigned(FResolveUnit) then
  begin
    Exit;
  end;
  mPending := TQueue<string>.Create;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    SeedReferenced(FIndex, mPending, mSeen);
    while (mPending.Count > 0) and not AResult.Cancelled do
    begin
      AResult.Cancelled := IsCancelled(ARun.Cancelled);
      mName := mPending.Dequeue;
      if not AResult.Cancelled and not mSeen.ContainsKey(UpperCase(mName)) then
      begin
        mSeen.Add(UpperCase(mName), True);
        if NextReferenced(mName, AResult, ARun.Progress, mUses_) then
        begin
          EnqueueAll(mPending, mUses_);
        end;
      end;
    end;
  finally
    mSeen.Free;
    mPending.Free;
  end;
end;

function TIndexBuilder.Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): TIndexBuildResult;
begin
  Result := Build(AFiles, nil, nil, AProgress, ACancelled, nil);
end;

function TIndexBuilder.RunStage(AStage: TIndexStage; const AFiles: TArray<string>; const ALabel: string;
  ADone: Integer; var AResult: TIndexBuildResult; const ARun: TIndexStageRun): Boolean;
var
  mIndex: Integer;
  mExisting: TUnitIndex;
  mProject: Boolean;
begin
  mProject := AStage = TIndexStage.Project;
  // Ohne Dateien wartet nur die Projektstufe auf ihre Reihe: Sie folgt auch ohne Projektdateien den uses.
  if not mProject and (Length(AFiles) = 0) then
  begin
    Exit(True);
  end;
  AResult.Cancelled := (ARun.Turn <> nil) and not ARun.Turn.Enter(AStage, ARun.Cancelled);
  if AResult.Cancelled then
  begin
    Exit(False);
  end;
  try
    mIndex := 0;
    while (mIndex < Length(AFiles)) and not AResult.Cancelled do
    begin
      AResult.Cancelled := IsCancelled(ARun.Cancelled);
      // Schon da (anderes Projekt der Gruppe, über uses erreicht): Suchpfade und Bibliothek nicht noch einmal
      // lesen. Projektdateien prüft IndexFile selbst (gleiche Defines, AlreadyIndexed).
      if not AResult.Cancelled and (mProject or not FIndex.FindFile(AFiles[mIndex], mExisting)) then
      begin
        if Assigned(ARun.Progress) then
        begin
          ARun.Progress(TIndexProgressKind.Report, ALabel + AFiles[mIndex], ((ADone + mIndex) * 100) div ARun.Total);
        end;
        IndexFile(AFiles[mIndex], AStage = TIndexStage.Library_, AResult);
      end;
      Inc(mIndex);
    end;
    if mProject and not AResult.Cancelled then
    begin
      IndexReferenced(AResult, ARun);
    end;
  finally
    if ARun.Turn <> nil then
    begin
      ARun.Turn.Leave;
    end;
  end;
  Result := not AResult.Cancelled;
end;

function TIndexBuilder.Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>;
  const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled; const ATurn: IIndexTurn): TIndexBuildResult;
var
  mRun: TIndexStageRun;
begin
  Result := Default(TIndexBuildResult);
  mRun := Default(TIndexStageRun);
  mRun.Progress := AProgress;
  mRun.Cancelled := ACancelled;
  mRun.Turn := ATurn;
  mRun.Total := Length(AFiles) + Length(ASearchFiles) + Length(ALibraryFiles);
  if mRun.Total = 0 then
  begin
    mRun.Total := 1;
  end;
  if Assigned(AProgress) then
  begin
    AProgress(TIndexProgressKind.Started, cTexts[TBuilderText.SymbolIndex].Text, 0);
  end;
  try
    // Units der Suchpfade gehören zum Projekt, auch wenn keine sie einbindet.
    if RunStage(TIndexStage.Project, AFiles, '', 0, Result, mRun) and Assigned(FOnProjectDone) then
    begin
      FOnProjectDone(Result);
    end;
    if not Result.Cancelled and RunStage(TIndexStage.SearchPaths, ASearchFiles, cTexts[TBuilderText.SearchPaths].Text,
      Length(AFiles),
      Result, mRun) then
    begin
      RunStage(TIndexStage.Library_, ALibraryFiles, cTexts[TBuilderText.LibraryText].Text, Length(AFiles) +
        Length(ASearchFiles), Result,
        mRun);
    end;
  finally
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Finished,
        cTexts[TBuilderText.UnitsSymbols].Fmt([FIndex.UnitCount, FIndex.SymbolCount]), 100);
    end;
  end;
end;

function TIndexBuilder.EnsureUnit(const AUnitName: string): Boolean;
var
  mExisting: TUnitIndex;
  mFileName: string;
  mIgnored: TIndexBuildResult;
begin
  if FIndex.FindUnit(AUnitName, mExisting) then
  begin
    Exit(True);
  end;
  if not Assigned(FResolveUnit) then
  begin
    Exit(False);
  end;
  if FFailedUnits.Contains(AUnitName) then
  begin
    Exit(False);
  end;
  mFileName := FResolveUnit(AUnitName);
  mIgnored := Default(TIndexBuildResult);
  Result := (mFileName <> '') and IndexFile(mFileName, True, mIgnored);
  if not Result then
  begin
    FFailedUnits.Add(AUnitName);
  end;
end;

function TIndexBuilder.ApplyText(const AFileName, AText: string): Boolean;
var
  mExisting, mUnitIndex: TUnitIndex;
  mHash: string;
begin
  Result := False;
  // Nur Units, die der Index kennt; neue Dateien kommen wie bisher beim Speichern dazu.
  if not FIndex.FindFile(AFileName, mExisting) then
  begin
    Exit;
  end;
  mHash := TIndexCache.HashOf(AText);
  if mHash = mExisting.Hash then
  begin
    Exit;
  end;
  mUnitIndex := TIndexExtractor.ExtractText(AText, AFileName, FDefines.DefinesOf(AFileName), IncludeResolver(),
    WantsUsages(mExisting.Library_), not mExisting.Library_);
  // Zeitstempel bleibt der der Datei: Beim Speichern liest IndexFile sie dann neu von der Platte.
  mUnitIndex.Stamp := mExisting.Stamp;
  mUnitIndex.Hash := mHash;
  mUnitIndex.IncludeStamps := IncludeStampsOf(FFileSystem, mUnitIndex.Includes);
  mUnitIndex.Library_ := mExisting.Library_;
  FIndex.AddUnit(mUnitIndex);
  Result := True;
end;

function TIndexBuilder.ApplyChange(const AChange: TFileChange; var AIgnored: TIndexBuildResult): Integer;
var
  mExisting, mDependent: TUnitIndex;
begin
  Result := 0;
  // Units, die die Datei per $I einbinden, neu einlesen.
  for mDependent in DependentsOf(FIndex, AChange.FileName) do
  begin
    if IndexFile(mDependent.FileName, mDependent.Library_, AIgnored) then
    begin
      Inc(Result);
    end;
  end;
  if not FIndex.FindFile(AChange.FileName, mExisting) then
  begin
    // Eine neue Datei kann eine bisher fehlende Unit sein.
    if AChange.Kind <> TFileChangeKind.Deleted then
    begin
      FFailedUnits.Clear;
    end;
    Exit;
  end;
  // IndexFile vergleicht mit dem Cache vom Start; ein geänderter Zeitstempel
  // führt zum Neueinlesen, gleicher Inhalt nicht. Was sich nicht mehr lesen
  // lässt oder gelöscht ist, fällt aus dem Index.
  if (AChange.Kind = TFileChangeKind.Deleted) or not IndexFile(AChange.FileName, mExisting.Library_, AIgnored) then
  begin
    FIndex.RemoveFile(AChange.FileName);
  end;
  Inc(Result);
end;

function TIndexBuilder.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  mChange: TFileChange;
  mIgnored: TIndexBuildResult;
begin
  Result := 0;
  mIgnored := Default(TIndexBuildResult);
  for mChange in AChanges do
  begin
    Inc(Result, ApplyChange(mChange, mIgnored));
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Index.Builder', cTexts);

end.
