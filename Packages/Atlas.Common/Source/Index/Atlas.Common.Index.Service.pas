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

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Builder;

type
  TIndexRequest = record
    /// <summary>Projektdateien in Reihenfolge (Hauptdatei, Units).</summary>
    Files: TArray<string>;
    Defines: TArray<string>;
    ResolveUnit: TUnitFileResolver;
    /// <summary>Suchpfade für $I-Dateien (#264).</summary>
    IncludePaths: TArray<string>;
    /// <summary>Cache-Datei; '' = ohne Cache.</summary>
    CacheFile: string;
    /// <summary>Gemeinsamer Cache der Bibliotheks-Units (RTL/VCL) je Compilerversion, Plattform und Defines;
    /// '' = Bibliothek im Projekt-Cache (#492).</summary>
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
    FOnError: TIndexErrorEvent;
    procedure Run(const ARequest: TIndexRequest);
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
    property OnError: TIndexErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  System.Diagnostics,
  System.Generics.Collections,
  Atlas.Common.Index.Cache;

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

procedure TIndexService.Run(const ARequest: TIndexRequest);
var
  Builder: TIndexBuilder;
  Cached, LibraryCached: TArray<TIndexCacheEntry>;
  Entry: TIndexCacheEntry;
  ProjectUnits, LibraryUnits: TArray<TUnitIndex>;
  Data: TBytes;
  Watch: TStopwatch;
  BuildResult: TIndexBuildResult;
  UnitIndex: TUnitIndex;
  Current: TDictionary<string, Boolean>;
  LibraryChanged: Boolean;
begin
  try
    Watch := TStopwatch.StartNew;
    Builder := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
    Builder.IncludePaths := ARequest.IncludePaths;
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
    BuildResult := Builder.Build(ARequest.Files, FOnProgress,
      function: Boolean
      begin
        Result := FCancelled;
      end);
    if not BuildResult.Cancelled and (ARequest.CacheFile <> '') and not ARequest.ReadOnlyCache then
    begin
      if ARequest.LibraryCacheFile = '' then
      begin
        if (BuildResult.Parsed > 0) or (Length(Cached) <> FIndex.UnitCount) then
          FFileSystem.WriteBytes(ARequest.CacheFile, TIndexCache.Serialize(FIndex.Units));
      end
      else
      begin
        // Getrennt schreiben: Projekt-Units ins Projekt, Bibliothek in den gemeinsamen Cache.
        ProjectUnits := nil;
        LibraryUnits := nil;
        for UnitIndex in FIndex.Units do
          if UnitIndex.Library_ then
            LibraryUnits := LibraryUnits + [UnitIndex]
          else
            ProjectUnits := ProjectUnits + [UnitIndex];
        if (BuildResult.Parsed > 0) or (Length(Cached) <> Length(ProjectUnits)) then
          FFileSystem.WriteBytes(ARequest.CacheFile, TIndexCache.Serialize(ProjectUnits));
        // Units anderer Projekte im gemeinsamen Cache behalten; neu sind nur die fehlenden.
        Current := TDictionary<string, Boolean>.Create;
        try
          for UnitIndex in LibraryUnits do
            Current.AddOrSetValue(AnsiUpperCase(UnitIndex.FileName), True);
          LibraryChanged := False;
          for UnitIndex in LibraryUnits do
            if not ContainsUnit(LibraryCached, UnitIndex) then
              LibraryChanged := True;
          for Entry in LibraryCached do
            if not Current.ContainsKey(AnsiUpperCase(Entry.Header.FileName)) and
              TIndexCache.Expand(Entry, UnitIndex) then
              LibraryUnits := LibraryUnits + [UnitIndex];
        finally
          Current.Free;
        end;
        if LibraryChanged then
          FFileSystem.WriteBytes(ARequest.LibraryCacheFile, TIndexCache.Serialize(LibraryUnits));
      end;
    end;
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
