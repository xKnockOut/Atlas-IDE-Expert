unit Atlas.Common.Lsp.Profiler;

// Stichproben-Profiler (#2057), Befehle des Plugins an den Server (workspace/executeCommand, ein Argument-Objekt).
// Gemessen wird im Server, weil er unter Windows als 64-Bit-Prozess läuft und so Threads von 32- und
// 64-Bit-Programmen lesen kann (das Plugin in der IDE nicht).
//   atlas.server.profilerStart  { processId, intervalMs?, mapFile?, program?, project?, platform? }
//                               -> { started: true, mapFile, routines }  routines = 0: keine Map, Rahmen [Modul]
//   atlas.server.profilerStatus {} -> { running, processId, elapsedMs, samples, lastFile }
//   atlas.server.profilerStop   {} -> { file, path, samples, durationMs }
// Stop löst die Adressen über die Map-Datei auf (Atlas.Common.Profiling.Sampling), schreibt den Lauf nach
// TAtlasProfileStore.Folder und behält die neuesten fünf. Endet das Programm vorher, schreibt Status den Lauf.
// Den Prober liefert die Komposition (Atlas.Windows.Profiling.Adapters.Sampler); ohne ihn melden die Befehle einen
// Fehler. Die Befehle laufen der Reihe nach (nicht nebenläufig); die Sperre trennt sie von StopRun, das beim Ende des
// Servers aus einem anderen Thread kommen kann.
// Ende des Servers: Der Prober hält für jede Probe einen Thread des Zielprogramms kurz an. Endet der Server in diesem
// Moment von außen (TerminateProcess) oder beim Ende des Prozesses, setzt Windows den Thread nicht fort, und das
// Programm bleibt hängen. Die Komposition ruft deshalb StopRun als ersten Schritt ihres Abbaus, bevor der Client
// nach seiner Schonfrist hart beendet; OnProcessChange meldet den gemessenen Prozess für die Statusdatei.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Text.MapFile,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Profiling.Contract,
  Atlas.Text.Profile;

type
  /// <summary>Gemessener Prozess; 0, sobald kein Lauf mehr geht.</summary>
  TLspProfiledProcessProc = reference to procedure(AProcessId: Cardinal);

  TLspProfiler = class
  public const
    cStartCommand = 'atlas.server.profilerStart';
    cStatusCommand = 'atlas.server.profilerStatus';
    cStopCommand = 'atlas.server.profilerStop';
    cDefaultIntervalMs = 10;
    cMinIntervalMs = 1;
    cMaxIntervalMs = 1000;
  private
    FLock: TObject;
    FFactory: TAtlasProfileSamplerFactory;
    FFolder: string;
    FSampler: IAtlasProfileSampler;
    FMap: TMapFile;
    FProfile: TAtlasProfile;
    FProcessId: Cardinal;
    FWatch: TStopwatch;
    FLastFile: string;
    FOnProcessChange: TLspProfiledProcessProc;
    /// <summary>AHandler unter FLock.</summary>
    function Locked(const AHandler: TLspCommandHandler): TLspCommandHandler;
    procedure ProcessChanged(AProcessId: Cardinal);
    function HandleStart(const AArguments: TJSONArray): TJSONValue;
    function HandleStatus(const AArguments: TJSONArray): TJSONValue;
    function HandleStop(const AArguments: TJSONArray): TJSONValue;
    procedure LoadMap(const AFileName: string);
    function StartedSampler(AParams: TJSONObject; AProcessId: Integer): IAtlasProfileSampler;
    procedure BeginProfile(AParams: TJSONObject; const ASampler: IAtlasProfileSampler; AProcessId: Integer);
    function StartResult(const AMapFile: string): TJSONObject;
    /// <summary>Beendet den Lauf, schreibt die Datei und räumt auf; Ergebnis wie atlas/profilerStop.</summary>
    function Finish: TJSONObject;
    procedure Prune;
  public
    /// <summary>AFolder: Ablage der Läufe (TAtlasProfileStore.Folder des Caches).</summary>
    constructor Create(const AFactory: TAtlasProfileSamplerFactory; const AFolder: string);
    destructor Destroy; override;
    procedure Register(ACommands: TLspCommands);
    /// <summary>Ende des Servers: hält einen laufenden Lauf an und schreibt ihn; ohne Lauf nichts. Threadsicher.
    /// Der Prober ist auch dann angehalten, wenn das Schreiben scheitert (die Ausnahme geht an den Aufrufer).
    /// </summary>
    procedure StopRun;
    /// <summary>Gemessener Prozess beim Start, 0 beim Ende eines Laufs (für die Statusdatei); nil = keiner.</summary>
    property OnProcessChange: TLspProfiledProcessProc read FOnProcessChange write FOnProcessChange;
  end;

implementation

uses
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  System.Math,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Profiling.Sampling,
  Atlas.Text.Json;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TProfilerText = (NotAvailable, AlreadyRunning, NotRunning, ProcessIdMissing, StartFailed);

const
  cTexts: array[TProfilerText] of TAtlasText = (
    (De: 'Der Profiler steht nur unter Windows zur Verfügung.'; En: 'The profiler is only available on Windows.'),
    (De: 'Es läuft schon ein Profil (Prozess %d).'; En: 'A profile is already running (process %d).'),
    (De: 'Es läuft kein Profil.'; En: 'No profile is running.'),
    (De: 'Feld "processId" fehlt.'; En: 'Field "processId" is missing.'),
    (De: 'Profil für Prozess %d lässt sich nicht starten: %s'; En: 'Cannot profile process %d: %s'));

{$SCOPEDENUMS OFF}

{ TLspProfiler }

constructor TLspProfiler.Create(const AFactory: TAtlasProfileSamplerFactory; const AFolder: string);
begin
  inherited Create;
  FLock := TObject.Create;
  FFactory := AFactory;
  FFolder := AFolder;
end;

destructor TLspProfiler.Destroy;
begin
  if FSampler <> nil then
  begin
    FSampler.Stop;
    FSampler := nil;
  end;
  FMap.Free;
  FLock.Free;
  inherited;
end;

function TLspProfiler.Locked(const AHandler: TLspCommandHandler): TLspCommandHandler;
var
  mLock: TObject;
begin
  mLock := FLock;
  Result :=
    function(const AArguments: TJSONArray): TJSONValue
    begin
      System.TMonitor.Enter(mLock);
      try
        Result := AHandler(AArguments);
      finally
        System.TMonitor.Exit(mLock);
      end;
    end;
end;

procedure TLspProfiler.ProcessChanged(AProcessId: Cardinal);
begin
  if Assigned(FOnProcessChange) then
  begin
    FOnProcessChange(AProcessId);
  end;
end;

function TLspProfiler.HandleStart(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
  mSampler: IAtlasProfileSampler;
  mMapFile: string;
  mProcessId: Integer;
begin
  mParams := nil;
  if (AArguments <> nil) and (AArguments.Count > 0) and (AArguments.Items[0] is TJSONObject) then
  begin
    mParams := TJSONObject(AArguments.Items[0]);
  end;
  if FSampler <> nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed,
      cTexts[TProfilerText.AlreadyRunning].Fmt([FProcessId]));
  end;
  mProcessId := TJsonRead.IntOr(mParams, 'processId', 0);
  if mProcessId <= 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TProfilerText.ProcessIdMissing].Text);
  end;
  mSampler := StartedSampler(mParams, mProcessId);
  BeginProfile(mParams, mSampler, mProcessId);
  mMapFile := TJsonRead.Text(mParams, 'mapFile');
  if mMapFile = '' then
  begin
    mMapFile := ChangeFileExt(mSampler.MainFileName, '.map');
  end;
  LoadMap(mMapFile);
  Result := StartResult(mMapFile);
end;

function TLspProfiler.HandleStatus(const AArguments: TJSONArray): TJSONValue;
var
  mResult: TJSONObject;
  mRunning: Boolean;
begin
  // Programm beendet: Lauf jetzt schreiben, damit lastFile ihn nennt.
  if (FSampler <> nil) and not FSampler.Running then
  begin
    Finish.Free;
  end;
  mRunning := FSampler <> nil;
  mResult := TJSONObject.Create;
  mResult.AddPair('running', TJSONBool.Create(mRunning));
  mResult.AddPair('processId', TJSONNumber.Create(Int64(FProcessId)));
  if mRunning then
  begin
    mResult.AddPair('elapsedMs', TJSONNumber.Create(FWatch.ElapsedMilliseconds));
    mResult.AddPair('samples', TJSONNumber.Create(FSampler.Samples));
  end
  else
  begin
    mResult.AddPair('elapsedMs', TJSONNumber.Create(0));
    mResult.AddPair('samples', TJSONNumber.Create(0));
  end;
  mResult.AddPair('lastFile', FLastFile);
  Result := mResult;
end;

function TLspProfiler.HandleStop(const AArguments: TJSONArray): TJSONValue;
begin
  if FSampler = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, cTexts[TProfilerText.NotRunning].Text);
  end;
  Result := Finish;
end;

procedure TLspProfiler.LoadMap(const AFileName: string);
begin
  FreeAndNil(FMap);
  if (AFileName <> '') and TFile.Exists(AFileName) then
  begin
    FMap := TMapFile.Create(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  end;
end;

/// <summary>Abtastung des Prozesses AProcessId mit dem Takt aus AParams, gestartet; sonst EJsonRpcError.</summary>
function TLspProfiler.StartedSampler(AParams: TJSONObject; AProcessId: Integer): IAtlasProfileSampler;
var
  mError: string;
begin
  Result := nil;
  if Assigned(FFactory) then
  begin
    Result := FFactory();
  end;
  if Result = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, cTexts[TProfilerText.NotAvailable].Text);
  end;
  if not Result.Start(Cardinal(AProcessId), EnsureRange(TJsonRead.IntOr(AParams, 'intervalMs', cDefaultIntervalMs),
    cMinIntervalMs, cMaxIntervalMs), mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed,
      cTexts[TProfilerText.StartFailed].Fmt([AProcessId, mError]));
  end;
end;

/// <summary>Übernimmt die laufende Abtastung ASampler und legt den Kopf des Profils aus AParams an.</summary>
procedure TLspProfiler.BeginProfile(AParams: TJSONObject; const ASampler: IAtlasProfileSampler; AProcessId: Integer);
begin
  FSampler := ASampler;
  FProcessId := Cardinal(AProcessId);
  ProcessChanged(FProcessId);
  FWatch := TStopwatch.StartNew;
  FProfile := Default(TAtlasProfile);
  FProfile.ProgramName := TJsonRead.Text(AParams, 'program');
  FProfile.Project := TJsonRead.Text(AParams, 'project');
  FProfile.Platform := TJsonRead.Text(AParams, 'platform');
  FProfile.StartedAt := Now;
  FProfile.IntervalMs := EnsureRange(TJsonRead.IntOr(AParams, 'intervalMs', cDefaultIntervalMs), cMinIntervalMs,
    cMaxIntervalMs);
  if FProfile.ProgramName = '' then
  begin
    FProfile.ProgramName := ExtractFileName(ASampler.MainFileName);
  end;
end;

/// <summary>Antwort von atlas/profilerStart mit der Map-Datei AMapFile.</summary>
function TLspProfiler.StartResult(const AMapFile: string): TJSONObject;
var
  mRoutines: Integer;
begin
  mRoutines := 0;
  if FMap <> nil then
  begin
    mRoutines := FMap.SymbolCount;
  end;
  Result := TJSONObject.Create;
  Result.AddPair('started', TJSONBool.Create(True));
  Result.AddPair('mapFile', AMapFile);
  Result.AddPair('routines', TJSONNumber.Create(mRoutines));
end;

function TLspProfiler.Finish: TJSONObject;
var
  mRun: TAtlasSampleRun;
  mResolver: TAtlasProfileResolver;
  mPath: string;
begin
  mRun := FSampler.Stop;
  FSampler := nil;
  ProcessChanged(0);
  mResolver := TAtlasProfileResolver.Create(mRun, FMap);
  try
    mResolver.FillProfile(FProfile);
  finally
    mResolver.Free;
  end;
  FreeAndNil(FMap);
  TDirectory.CreateDirectory(FFolder);
  FLastFile := TAtlasProfileStore.FileNameFor(FProfile.StartedAt);
  mPath := TPath.Combine(FFolder, FLastFile);
  TFile.WriteAllText(mPath, TAtlasProfileJson.ToText(FProfile), TEncoding.UTF8);
  Prune;
  Result := TJSONObject.Create;
  Result.AddPair('file', FLastFile);
  Result.AddPair('path', mPath);
  Result.AddPair('samples', TJSONNumber.Create(FProfile.Samples));
  Result.AddPair('durationMs', TJSONNumber.Create(FProfile.DurationMs));
  if mRun.Error <> '' then
  begin
    Result.AddPair('error', mRun.Error);
  end;
  FProfile := Default(TAtlasProfile);
end;

procedure TLspProfiler.Prune;
var
  mFile: string;
begin
  for mFile in TAtlasProfileStore.Surplus(TDirectory.GetFiles(FFolder, TAtlasProfileStore.cPrefix + '*.json'),
    TAtlasProfileStore.cKeep) do
  begin
    TFile.Delete(mFile);
  end;
end;

procedure TLspProfiler.Register(ACommands: TLspCommands);
begin
  ACommands.Register(cStartCommand, Locked(HandleStart));
  ACommands.Register(cStatusCommand, Locked(HandleStatus));
  ACommands.Register(cStopCommand, Locked(HandleStop));
end;

procedure TLspProfiler.StopRun;
begin
  System.TMonitor.Enter(FLock);
  try
    if FSampler <> nil then
    begin
      Finish.Free;
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Profiler', cTexts);

end.
