unit BDLsp.Common.Index.Service;

// Hält den Symbolindex und baut ihn in einem Hintergrund-Thread auf:
// Cache laden, Projektdateien und referenzierte Units indizieren, Cache
// schreiben. Ein neuer Start (z. B. nach geänderter Konfiguration) bricht
// den laufenden Aufbau ab und wartet auf ihn.
//
// Schreibt eine andere Instanz den Cache gerade (#62), wartet der Aufbau
// begrenzt, bis sie fertig ist oder die Sperre freigibt, und lädt dann ihren
// Stand, statt alles selbst noch einmal zu lesen.

interface

uses
  System.SysUtils,
  System.Classes,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Index.Builder;

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
    FOnProgress: TIndexProgressEvent;
    FOnFinished: TIndexFinishedEvent;
    FOnError: TIndexErrorEvent;
    procedure Run(const ARequest: TIndexRequest);
    procedure WaitForOtherWriter(const ARequest: TIndexRequest);
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
    property Index: ISymbolIndex read FIndex;
    property OnProgress: TIndexProgressEvent read FOnProgress write FOnProgress;
    property OnFinished: TIndexFinishedEvent read FOnFinished write FOnFinished;
    property OnError: TIndexErrorEvent read FOnError write FOnError;
  end;

implementation

uses
  System.Diagnostics,
  BDLsp.Common.Index.Cache;

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
  NameThreadForDebugging('BDLsp.Index');
  FService.Run(FRequest);
end;

{ TIndexService }

constructor TIndexService.Create(const AIndex: ISymbolIndex; const AFileSystem: IIndexFileSystem);
begin
  inherited Create;
  FIndex := AIndex;
  FFileSystem := AFileSystem;
  FLock := TObject.Create;
end;

destructor TIndexService.Destroy;
begin
  Stop;
  FBuilder.Free;
  FLock.Free;
  inherited;
end;

procedure TIndexService.Run(const ARequest: TIndexRequest);
var
  Builder: TIndexBuilder;
  Cached: TArray<TUnitIndex>;
  Text: string;
  Watch: TStopwatch;
  BuildResult: TIndexBuildResult;
begin
  try
    Watch := TStopwatch.StartNew;
    Builder := TIndexBuilder.Create(FIndex, FFileSystem, ARequest.Defines, ARequest.ResolveUnit);
    Builder.IncludePaths := ARequest.IncludePaths;
    TMonitor.Enter(FLock);
    try
      FBuilder.Free;
      FBuilder := Builder;
    finally
      TMonitor.Exit(FLock);
    end;
    WaitForOtherWriter(ARequest);
    if (ARequest.CacheFile <> '') and FFileSystem.ReadText(ARequest.CacheFile, Text) then
    begin
      Cached := TIndexCache.Deserialize(Text);
      Builder.UseCache(Cached);
    end;
    BuildResult := Builder.Build(ARequest.Files, FOnProgress,
      function: Boolean
      begin
        Result := FCancelled;
      end);
    if not BuildResult.Cancelled and (ARequest.CacheFile <> '') and not ARequest.ReadOnlyCache and
      ((BuildResult.Parsed > 0) or (Length(Cached) <> FIndex.UnitCount)) then
      FFileSystem.WriteText(ARequest.CacheFile, TIndexCache.Serialize(FIndex.Units));
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

function TIndexService.EnsureUnit(const AUnitName: string): Boolean;
var
  Builder: TIndexBuilder;
begin
  TMonitor.Enter(FLock);
  try
    Builder := FBuilder;
    Result := (Builder <> nil) and Builder.EnsureUnit(AUnitName);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TIndexService.ApplyChanges(const AChanges: TArray<TFileChange>): Integer;
begin
  TMonitor.Enter(FLock);
  try
    if FBuilder = nil then
      Exit(0);
    Result := FBuilder.ApplyChanges(AChanges);
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
