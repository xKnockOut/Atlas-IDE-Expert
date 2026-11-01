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

  TIndexBuilder = class
  private
    FIndex: ISymbolIndex;
    FFileSystem: IIndexFileSystem;
    FDefines: TArray<string>;
    FResolveUnit: TUnitFileResolver;
    FCached: TDictionary<string, TIndexCacheEntry>;
    // EnsureUnit liest FCached aus Anfrage-Threads, ReleaseCache leert es.
    FCacheLock: TObject;
    // Von EnsureUnit aus Anfrage-Threads genutzt.
    FFailedUnits: TDictionary<string, Boolean>;
    FFailedLock: TObject;
    // Dateien, die gerade ein Thread liest (Großschreibung); Wartende schlafen an FFlightLock.
    FInFlight: TDictionary<string, Boolean>;
    FFlightLock: TObject;
    FIncludePaths: TArray<string>;
    FLibraryDefines: TArray<string>;
    FUsages: Boolean;
    FLibraryRoots: TArray<string>;
    function WantsUsages(ALibrary: Boolean): Boolean;
    /// <summary>Taugt der Cache-Eintrag? AMiss nennt bei False den Grund.</summary>
    function CacheFits(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AMiss: TIndexCacheMiss): Boolean;
    function FromCache(const AEntry: TIndexCacheEntry; ALibrary: Boolean; out AUnit: TUnitIndex): Boolean;
    function IncludeResolver: TIncludeResolver;
    /// <summary>Symbole für AFileName: Dateien der Installation mit LibraryDefines, alle anderen mit
    /// denen des Projekts.</summary>
    function DefinesFor(const AFileName: string): TArray<string>;
    /// <summary>Schlüssel der Defines für AFileName (TUnitIndex.DefinesKey).</summary>
    function DefinesKeyFor(const AFileName: string): string;
    /// <summary>Steht AFileName mit Stand AStamp schon passend im Index, z. B. von einem anderen Projekt der
    /// Gruppe mit denselben Defines? Dann nicht noch einmal übernehmen.</summary>
    function AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
    function IncludeStampsOf(const AIncludes: TArray<string>): TArray<Int64>;
    function IncludesUnchanged(const ACached: TUnitIndex): Boolean;
    /// <summary>Indiziert AFileName; liest ein anderer Thread die Datei gerade, wartet es auf ihn und übernimmt sein
    /// Ergebnis (#1236).</summary>
    function IndexFile(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    function IndexFileNow(const AFileName: string; ALibrary: Boolean; var AResult: TIndexBuildResult): Boolean;
    procedure IndexReferenced(var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled);
    function IsCancelled(const ACancelled: TIndexCancelled): Boolean;
    /// <summary>Alle Units aus AFiles, die noch nicht im Index stehen (#648); False bei Abbruch.</summary>
    function IndexAll(const AFiles: TArray<string>; ALibrary: Boolean; const ALabel: string; ADone, ATotal: Integer;
      var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled): Boolean;
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
    /// AProjectDone läuft nach der Projektstufe (Projektdateien und über uses erreichbare Units).</summary>
    function Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>; const AProgress: TIndexProgressEvent;
      const ACancelled: TIndexCancelled; const ATurn: IIndexTurn;
      const AProjectDone: TIndexStageDone): TIndexBuildResult; overload;
    /// <summary>Wie oben mit AProjectDone = nil.</summary>
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
    property LibraryRoots: TArray<string> read FLibraryRoots write FLibraryRoots;
    /// <summary>Symbole für Dateien unter LibraryRoots: nur die des Compilers (Plattform, Version).</summary>
    property LibraryDefines: TArray<string> read FLibraryDefines write FLibraryDefines;
    /// <summary>Liegt AFileName unter einem der Ordner aus ARoots?</summary>
    class function IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean; static;
  end;

implementation

uses
  Atlas.Common.Pascal.IncludeFiles,
  Atlas.Common.Index.Extractor;

{ TIndexBuilder }

constructor TIndexBuilder.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem;
  const ADefines: TArray<string>; const AResolveUnit: TUnitFileResolver);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FDefines := ADefines;
  FResolveUnit := AResolveUnit;
  FCached := TDictionary<string, TIndexCacheEntry>.Create;
  FCacheLock := TObject.Create;
  FFailedUnits := TDictionary<string, Boolean>.Create;
  FFailedLock := TObject.Create;
  FInFlight := TDictionary<string, Boolean>.Create;
  FFlightLock := TObject.Create;
end;

class function TIndexBuilder.IsUnder(const AFileName: string; const ARoots: TArray<string>): Boolean;
var
  Root: string;
begin
  // Windows-Pfade auch unter anderen Systemen (Tests): beide Trenner gelten.
  for Root in ARoots do
  begin
    if (Root <> '') and AFileName.StartsWith(Root, True) then
    begin
      if CharInSet(Root[Length(Root)], ['\', '/']) then
      begin
        Exit(True);
      end;
      if (Length(AFileName) > Length(Root)) and CharInSet(AFileName[Length(Root) + 1], ['\', '/']) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

function TIndexBuilder.DefinesFor(const AFileName: string): TArray<string>;
begin
  // RTL, VCL und FMX einmal je Compiler und Plattform statt je Projekt-Defines (#647).
  if IsUnder(AFileName, FLibraryRoots) then
  begin
    Result := FLibraryDefines;
  end
  else
  begin
    Result := FDefines;
  end;
end;

function TIndexBuilder.DefinesKeyFor(const AFileName: string): string;
begin
  Result := AnsiUpperCase(String.Join(';', DefinesFor(AFileName)));
end;

function TIndexBuilder.AlreadyIndexed(const AFileName: string; AStamp: Int64; ALibrary: Boolean): Boolean;
var
  mExisting: TUnitIndex;
begin
  // Ohne diese Prüfung übernahm jedes Projekt einer Gruppe die gemeinsamen Units erneut (aus dem Cache oder
  // geparst) und ersetzte die des vorigen; die Namenslisten des Index behielten die ersetzten Einträge, bis es
  // mehr tote als lebende gab (Speicher, Rückmeldung 01.11.2026). Bedingungen wie bei CacheFits.
  Result := FIndex.FindFile(AFileName, mExisting) and (mExisting.Stamp = AStamp) and
    (mExisting.DefinesKey <> '') and (mExisting.DefinesKey = DefinesKeyFor(AFileName)) and
    (mExisting.Library_ = ALibrary) and IncludesUnchanged(mExisting) and
    (mExisting.UsagesIndexed or not WantsUsages(ALibrary)) and
    (not mExisting.Compact or (ALibrary and (FIndex.Budget > 0)));
end;

destructor TIndexBuilder.Destroy;
begin
  FFlightLock.Free;
  FInFlight.Free;
  FFailedLock.Free;
  FFailedUnits.Free;
  FCacheLock.Free;
  FCached.Free;
  inherited;
end;

procedure TIndexBuilder.UseCache(const AUnits: TArray<TUnitIndex>);
var
  UnitIndex: TUnitIndex;
begin
  TMonitor.Enter(FCacheLock);
  try
    // Ob ein kompakter Eintrag taugt, entscheidet CacheFits beim Einlesen.
    for UnitIndex in AUnits do
    begin
      FCached.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), TIndexCacheEntry.FromUnit(UnitIndex));
    end;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

procedure TIndexBuilder.UseCache(const AEntries: TArray<TIndexCacheEntry>);
var
  Entry: TIndexCacheEntry;
begin
  TMonitor.Enter(FCacheLock);
  try
    for Entry in AEntries do
    begin
      FCached.AddOrSetValue(AnsiUpperCase(Entry.Header.FileName), Entry);
    end;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

procedure TIndexBuilder.ReleaseCache;
begin
  TMonitor.Enter(FCacheLock);
  try
    FCached.Clear;
    FCached.TrimExcess;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

function TIndexBuilder.CachedCount: Integer;
begin
  TMonitor.Enter(FCacheLock);
  try
    Result := FCached.Count;
  finally
    TMonitor.Exit(FCacheLock);
  end;
end;

function TIndexBuilder.IsCancelled(const ACancelled: TIndexCancelled): Boolean;
begin
  Result := Assigned(ACancelled) and ACancelled();
end;

function TIndexBuilder.IncludeResolver: TIncludeResolver;
var
  FileSystem: IIndexFileSystem;
begin
  FileSystem := FFileSystem;
  Result := TIncludeFiles.Resolver(FIncludePaths,
    function(const AFileName: string): Boolean
    var
      Stamp: Int64;
    begin
      Result := FileSystem.FileStamp(AFileName, Stamp);
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := FileSystem.ReadText(AFileName, AText);
    end);
end;

function TIndexBuilder.IncludeStampsOf(const AIncludes: TArray<string>): TArray<Int64>;
var
  Index: Integer;
begin
  SetLength(Result, Length(AIncludes));
  for Index := 0 to High(AIncludes) do
  begin
    if not FFileSystem.FileStamp(AIncludes[Index], Result[Index]) then
    begin
      Result[Index] := -1;
    end;
  end;
end;

function TIndexBuilder.IncludesUnchanged(const ACached: TUnitIndex): Boolean;
var
  Index: Integer;
  Stamp: Int64;
begin
  if Length(ACached.Includes) = 0 then
  begin
    Exit(True);
  end;
  // Ältere Einträge ohne Zeitstempel gelten als geändert.
  if Length(ACached.IncludeStamps) <> Length(ACached.Includes) then
  begin
    Exit(False);
  end;
  for Index := 0 to High(ACached.Includes) do
  begin
    if not FFileSystem.FileStamp(ACached.Includes[Index], Stamp) then
    begin
      Exit(False);
    end;
    if (ACached.IncludeStamps[Index] < 0) or (Stamp <> ACached.IncludeStamps[Index]) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
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
  Result := IncludesUnchanged(AEntry.Header);
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
  Text: string;
begin
  AUsages := nil;
  Result := FFileSystem.ReadText(AFileName, Text);
  if Result then
  begin
    AUsages := TIndexExtractor.ExtractText(Text, AFileName, DefinesFor(AFileName), IncludeResolver(), True).Usages;
  end;
end;

function TIndexBuilder.IndexFile(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
const
  cWaitSliceMs = 50;
var
  mKey: string;
  mWaited: Boolean;
  mExisting: TUnitIndex;
begin
  mKey := AnsiUpperCase(AFileName);
  mWaited := False;
  TMonitor.Enter(FFlightLock);
  try
    while FInFlight.ContainsKey(mKey) do
    begin
      mWaited := True;
      TMonitor.Wait(FFlightLock, cWaitSliceMs);
    end;
    // Ein anderer Thread hat die Datei eben gelesen: sein Ergebnis gilt, kein zweites Parsen.
    if mWaited and FIndex.FindFile(AFileName, mExisting) then
    begin
      Exit(True);
    end;
    FInFlight.Add(mKey, True);
  finally
    TMonitor.Exit(FFlightLock);
  end;
  try
    Result := IndexFileNow(AFileName, ALibrary, AResult);
  finally
    TMonitor.Enter(FFlightLock);
    try
      FInFlight.Remove(mKey);
      TMonitor.PulseAll(FFlightLock);
    finally
      TMonitor.Exit(FFlightLock);
    end;
  end;
end;

function TIndexBuilder.IndexFileNow(const AFileName: string; ALibrary: Boolean;
  var AResult: TIndexBuildResult): Boolean;
var
  Stamp: Int64;
  Text, Hash: string;
  Entry: TIndexCacheEntry;
  Cached, UnitIndex: TUnitIndex;
  HasCache, Taken: Boolean;
  Watch: TStopwatch;
  Miss: TIndexCacheMiss;
begin
  if not FFileSystem.FileStamp(AFileName, Stamp) then
  begin
    Inc(AResult.Missing);
    Exit(False);
  end;
  if AlreadyIndexed(AFileName, Stamp, ALibrary) then
  begin
    Inc(AResult.FromCache);
    Exit(True);
  end;
  TMonitor.Enter(FCacheLock);
  try
    HasCache := FCached.TryGetValue(AnsiUpperCase(AFileName), Entry);
  finally
    TMonitor.Exit(FCacheLock);
  end;
  Miss := TIndexCacheMiss.NoEntry;
  if HasCache and not CacheFits(Entry, ALibrary, Miss) then
  begin
    HasCache := False;
  end;
  // Zeitstempel oder Inhalt passen: erst jetzt die Symbole dekodieren; ein beschädigter Block
  // zählt wie ein fehlender Cache-Eintrag.
  Taken := HasCache and (Entry.Header.Stamp = Stamp) and FromCache(Entry, ALibrary, Cached);
  if not Taken then
  begin
    if not FFileSystem.ReadText(AFileName, Text) then
    begin
      Inc(AResult.Missing);
      Exit(False);
    end;
    Hash := TIndexCache.HashOf(Text);
    if HasCache and (Entry.Header.Hash = Hash) then
    begin
      Taken := FromCache(Entry, ALibrary, Cached);
      Miss := TIndexCacheMiss.Damaged;
    end
    else if HasCache then
    begin
      Miss := TIndexCacheMiss.Changed;
    end;
  end;
  if Taken then
  begin
    Cached.Stamp := Stamp;
    Cached.Library_ := ALibrary;
    Cached.DefinesKey := DefinesKeyFor(AFileName);
    FIndex.AddUnit(Cached);
    Inc(AResult.FromCache);
    Exit(True);
  end;
  Watch := TStopwatch.StartNew;
  UnitIndex := TIndexExtractor.ExtractText(Text, AFileName, DefinesFor(AFileName), IncludeResolver(),
    WantsUsages(ALibrary));
  Inc(AResult.ParseMs, Watch.ElapsedMilliseconds);
  UnitIndex.Stamp := Stamp;
  UnitIndex.Hash := Hash;
  UnitIndex.IncludeStamps := IncludeStampsOf(UnitIndex.Includes);
  UnitIndex.Library_ := ALibrary;
  UnitIndex.DefinesKey := DefinesKeyFor(AFileName);
  FIndex.AddUnit(UnitIndex);
  Inc(AResult.Parsed);
  Inc(AResult.Misses[Miss]);
  Result := True;
end;

procedure TIndexBuilder.IndexReferenced(var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled);
var
  Pending: TQueue<string>;
  Seen: TDictionary<string, Boolean>;
  UnitIndex: TUnitIndex;
  Name, UsedName, FileName: string;
  Existing: TUnitIndex;
  Stamp: Int64;
  Watch: TStopwatch;
begin
  if not Assigned(FResolveUnit) then
  begin
    Exit;
  end;
  Pending := TQueue<string>.Create;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for UnitIndex in FIndex.Units do
    begin
      Seen.AddOrSetValue(UpperCase(UnitIndex.UnitName), True);
      for Name in UnitIndex.InterfaceUses do
      begin
        Pending.Enqueue(Name);
      end;
      for Name in UnitIndex.ImplementationUses do
      begin
        Pending.Enqueue(Name);
      end;
    end;
    while Pending.Count > 0 do
    begin
      if IsCancelled(ACancelled) then
      begin
        AResult.Cancelled := True;
        Exit;
      end;
      Name := Pending.Dequeue;
      if Seen.ContainsKey(UpperCase(Name)) then
      begin
        Continue;
      end;
      Seen.Add(UpperCase(Name), True);
      if FIndex.FindUnit(Name, Existing) then
      begin
        Continue;
      end;
      Watch := TStopwatch.StartNew;
      FileName := FResolveUnit(Name);
      Inc(AResult.ResolveMs, Watch.ElapsedMilliseconds);
      if FileName = '' then
      begin
        Continue;
      end;
      // Unter anderem Namen schon im Index, z. B. "Forms" als Vcl.Forms aus einem anderen Projekt
      // der Gruppe: nicht neu einlesen. Sonst las jedes Projekt dieselben Units erneut (#647).
      if FIndex.FindFile(FileName, Existing) and FFileSystem.FileStamp(FileName, Stamp) and
        (Stamp = Existing.Stamp) then
      begin
        for UsedName in Existing.InterfaceUses do
        begin
          Pending.Enqueue(UsedName);
        end;
        Continue;
      end;
      if Assigned(AProgress) then
      begin
        AProgress(TIndexProgressKind.Report, Name, -1);
      end;
      if IndexFile(FileName, True, AResult) and FIndex.FindFile(FileName, UnitIndex) then
      begin
        // Nur das interface ist von außen sichtbar; dessen uses reichen.
        for UsedName in UnitIndex.InterfaceUses do
        begin
          Pending.Enqueue(UsedName);
        end;
      end;
    end;
  finally
    Seen.Free;
    Pending.Free;
  end;
end;

function TIndexBuilder.Build(const AFiles: TArray<string>; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): TIndexBuildResult;
begin
  Result := Build(AFiles, nil, nil, AProgress, ACancelled, nil);
end;

function TIndexBuilder.IndexAll(const AFiles: TArray<string>; ALibrary: Boolean; const ALabel: string;
  ADone, ATotal: Integer; var AResult: TIndexBuildResult; const AProgress: TIndexProgressEvent;
  const ACancelled: TIndexCancelled): Boolean;
var
  Index: Integer;
  Existing: TUnitIndex;
begin
  for Index := 0 to High(AFiles) do
  begin
    if IsCancelled(ACancelled) then
    begin
      Exit(False);
    end;
    // Schon da (anderes Projekt der Gruppe, über uses erreicht): nicht noch einmal lesen.
    if FIndex.FindFile(AFiles[Index], Existing) then
    begin
      Continue;
    end;
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Report, ALabel + ExtractFileName(AFiles[Index]),
        ((ADone + Index) * 100) div ATotal);
    end;
    IndexFile(AFiles[Index], ALibrary, AResult);
  end;
  Result := True;
end;

function TIndexBuilder.Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>;
  const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled; const ATurn: IIndexTurn): TIndexBuildResult;
begin
  Result := Build(AFiles, ASearchFiles, ALibraryFiles, AProgress, ACancelled, ATurn, nil);
end;

function TIndexBuilder.Build(const AFiles, ASearchFiles, ALibraryFiles: TArray<string>;
  const AProgress: TIndexProgressEvent; const ACancelled: TIndexCancelled; const ATurn: IIndexTurn;
  const AProjectDone: TIndexStageDone): TIndexBuildResult;
var
  Index, Total: Integer;

  function Enter(AStage: TIndexStage): Boolean;
  begin
    Result := (ATurn = nil) or ATurn.Enter(AStage, ACancelled);
  end;

  procedure Leave;
  begin
    if ATurn <> nil then
    begin
      ATurn.Leave;
    end;
  end;

begin
  Result := Default(TIndexBuildResult);
  Total := Length(AFiles) + Length(ASearchFiles) + Length(ALibraryFiles);
  if Total = 0 then
  begin
    Total := 1;
  end;
  if Assigned(AProgress) then
  begin
    AProgress(TIndexProgressKind.Started, 'Symbolindex', 0);
  end;
  try
    if not Enter(TIndexStage.Project) then
    begin
      Result.Cancelled := True;
      Exit;
    end;
    try
      for Index := 0 to High(AFiles) do
      begin
        if IsCancelled(ACancelled) then
        begin
          Result.Cancelled := True;
          Exit;
        end;
        if Assigned(AProgress) then
        begin
          AProgress(TIndexProgressKind.Report, AFiles[Index], (Index * 100) div Total);
        end;
        IndexFile(AFiles[Index], False, Result);
      end;
      IndexReferenced(Result, AProgress, ACancelled);
    finally
      Leave;
    end;
    if Result.Cancelled then
    begin
      Exit;
    end;
    if Assigned(AProjectDone) then
    begin
      AProjectDone(Result);
    end;
    if Length(ASearchFiles) > 0 then
    begin
      if not Enter(TIndexStage.SearchPaths) then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      try
        // Units der Suchpfade gehören zum Projekt, auch wenn keine sie einbindet.
        Result.Cancelled := not IndexAll(ASearchFiles, False, 'Suchpfade: ', Length(AFiles), Total, Result,
          AProgress, ACancelled);
      finally
        Leave;
      end;
      if Result.Cancelled then
      begin
        Exit;
      end;
    end;
    if Length(ALibraryFiles) > 0 then
    begin
      if not Enter(TIndexStage.Library_) then
      begin
        Result.Cancelled := True;
        Exit;
      end;
      try
        Result.Cancelled := not IndexAll(ALibraryFiles, True, 'Bibliothek: ',
          Length(AFiles) + Length(ASearchFiles), Total, Result, AProgress, ACancelled);
      finally
        Leave;
      end;
    end;
  finally
    if Assigned(AProgress) then
    begin
      AProgress(TIndexProgressKind.Finished,
        Format('%d Units, %d Symbole', [FIndex.UnitCount, FIndex.SymbolCount]), 100);
    end;
  end;
end;

function TIndexBuilder.EnsureUnit(const AUnitName: string): Boolean;
var
  Existing: TUnitIndex;
  FileName: string;
  Ignored: TIndexBuildResult;
  Failed: Boolean;
begin
  if FIndex.FindUnit(AUnitName, Existing) then
  begin
    Exit(True);
  end;
  if not Assigned(FResolveUnit) then
  begin
    Exit(False);
  end;
  TMonitor.Enter(FFailedLock);
  try
    Failed := FFailedUnits.ContainsKey(UpperCase(AUnitName));
  finally
    TMonitor.Exit(FFailedLock);
  end;
  if Failed then
  begin
    Exit(False);
  end;
  FileName := FResolveUnit(AUnitName);
  Ignored := Default(TIndexBuildResult);
  Result := (FileName <> '') and IndexFile(FileName, True, Ignored);
  if not Result then
  begin
    TMonitor.Enter(FFailedLock);
    try
      FFailedUnits.AddOrSetValue(UpperCase(AUnitName), True);
    finally
      TMonitor.Exit(FFailedLock);
    end;
  end;
end;

function TIndexBuilder.ApplyText(const AFileName, AText: string): Boolean;
var
  Existing, UnitIndex: TUnitIndex;
  Hash: string;
begin
  Result := False;
  // Nur Units, die der Index kennt; neue Dateien kommen wie bisher beim Speichern dazu.
  if not FIndex.FindFile(AFileName, Existing) then
  begin
    Exit;
  end;
  Hash := TIndexCache.HashOf(AText);
  if Hash = Existing.Hash then
  begin
    Exit;
  end;
  UnitIndex := TIndexExtractor.ExtractText(AText, AFileName, DefinesFor(AFileName), IncludeResolver(),
    WantsUsages(Existing.Library_));
  // Zeitstempel bleibt der der Datei: Beim Speichern liest IndexFile sie dann neu von der Platte.
  UnitIndex.Stamp := Existing.Stamp;
  UnitIndex.Hash := Hash;
  UnitIndex.IncludeStamps := IncludeStampsOf(UnitIndex.Includes);
  UnitIndex.Library_ := Existing.Library_;
  FIndex.AddUnit(UnitIndex);
  Result := True;
end;

function TIndexBuilder.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
var
  Change: TFileChange;
  Existing: TUnitIndex;
  Ignored: TIndexBuildResult;
  Known: Boolean;
  UnitIndex: TUnitIndex;
  Dependent: TArray<TUnitIndex>;
  Include: string;
begin
  Result := 0;
  Ignored := Default(TIndexBuildResult);
  for Change in AChanges do
  begin
    // Units, die die Datei per $I einbinden, neu einlesen.
    Dependent := nil;
    for UnitIndex in FIndex.Units do
    begin
      for Include in UnitIndex.Includes do
      begin
        if SameText(Include, Change.FileName) then
        begin
          Dependent := Dependent + [UnitIndex];
          Break;
        end;
      end;
    end;
    for UnitIndex in Dependent do
    begin
      if IndexFile(UnitIndex.FileName, UnitIndex.Library_, Ignored) then
      begin
        Inc(Result);
      end;
    end;
    Known := FIndex.FindFile(Change.FileName, Existing);
    case Change.Kind of
      TFileChangeKind.Deleted:
        if Known then
        begin
          FIndex.RemoveFile(Change.FileName);
          Inc(Result);
        end;
      TFileChangeKind.Created, TFileChangeKind.Changed:
        if Known then
        begin
          // IndexFile vergleicht mit dem Cache vom Start; ein geänderter
          // Zeitstempel führt zum Neueinlesen, gleicher Inhalt nicht.
          if IndexFile(Change.FileName, Existing.Library_, Ignored) then
          begin
            Inc(Result);
          end
          else
          begin
            FIndex.RemoveFile(Change.FileName);
            Inc(Result);
          end;
        end
        else
        begin
          // Eine neue Datei kann eine bisher fehlende Unit sein.
          TMonitor.Enter(FFailedLock);
          try
            FFailedUnits.Clear;
          finally
            TMonitor.Exit(FFailedLock);
          end;
        end;
    end;
  end;
end;

end.
