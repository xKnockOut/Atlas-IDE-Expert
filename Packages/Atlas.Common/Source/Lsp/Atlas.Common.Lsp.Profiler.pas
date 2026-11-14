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
// Fehler. Die Befehle laufen der Reihe nach (nicht nebenläufig), der Zustand braucht deshalb keine Sperre.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Diagnostics,
  Atlas.Text.MapFile,
  Atlas.Common.Lsp.Commands,
  Atlas.Common.Profiling.Contract,
  Atlas.Common.Profiling.Profile;

type
  TLspProfiler = class
  public const
    cStartCommand = 'atlas.server.profilerStart';
    cStatusCommand = 'atlas.server.profilerStatus';
    cStopCommand = 'atlas.server.profilerStop';
    cDefaultIntervalMs = 10;
    cMinIntervalMs = 1;
    cMaxIntervalMs = 1000;
  private
    FFactory: TAtlasProfileSamplerFactory;
    FFolder: string;
    FSampler: IAtlasProfileSampler;
    FMap: TMapFile;
    FProfile: TAtlasProfile;
    FProcessId: Cardinal;
    FWatch: TStopwatch;
    FLastFile: string;
    function HandleStart(const AArguments: TJSONArray): TJSONValue;
    function HandleStatus(const AArguments: TJSONArray): TJSONValue;
    function HandleStop(const AArguments: TJSONArray): TJSONValue;
    procedure LoadMap(const AFileName: string);
    /// <summary>Beendet den Lauf, schreibt die Datei und räumt auf; Ergebnis wie atlas/profilerStop.</summary>
    function Finish: TJSONObject;
    procedure Prune;
  public
    /// <summary>AFolder: Ablage der Läufe (TAtlasProfileStore.Folder des Caches).</summary>
    constructor Create(const AFactory: TAtlasProfileSamplerFactory; const AFolder: string);
    destructor Destroy; override;
    procedure Register(ACommands: TLspCommands);
  end;

implementation

uses
  System.Math,
  System.IOUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Localization.Texts,
  Atlas.Common.Profiling.Sampling;

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

function TextParam(const AParams: TJSONObject; const AName: string): string;
begin
  Result := '';
  if AParams <> nil then
  begin
    AParams.TryGetValue<string>(AName, Result);
  end;
end;

function IntParam(const AParams: TJSONObject; const AName: string; ADefault: Integer): Integer;
begin
  Result := ADefault;
  if AParams <> nil then
  begin
    AParams.TryGetValue<Integer>(AName, Result);
  end;
end;

{ TLspProfiler }

constructor TLspProfiler.Create(const AFactory: TAtlasProfileSamplerFactory; const AFolder: string);
begin
  inherited Create;
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
  inherited;
end;

procedure TLspProfiler.Register(ACommands: TLspCommands);
begin
  ACommands.Register(cStartCommand, HandleStart);
  ACommands.Register(cStatusCommand, HandleStatus);
  ACommands.Register(cStopCommand, HandleStop);
end;

procedure TLspProfiler.LoadMap(const AFileName: string);
begin
  FreeAndNil(FMap);
  if (AFileName <> '') and TFile.Exists(AFileName) then
  begin
    FMap := TMapFile.Create(TFile.ReadAllText(AFileName, TEncoding.UTF8));
  end;
end;

function TLspProfiler.HandleStart(const AArguments: TJSONArray): TJSONValue;
var
  mParams: TJSONObject;
  mSampler: IAtlasProfileSampler;
  mError, mMapFile: string;
  mProcessId: Integer;
  mResult: TJSONObject;
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
  mProcessId := IntParam(mParams, 'processId', 0);
  if mProcessId <= 0 then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, cTexts[TProfilerText.ProcessIdMissing].Text);
  end;
  mSampler := nil;
  if Assigned(FFactory) then
  begin
    mSampler := FFactory();
  end;
  if mSampler = nil then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed, cTexts[TProfilerText.NotAvailable].Text);
  end;
  if not mSampler.Start(Cardinal(mProcessId), EnsureRange(IntParam(mParams, 'intervalMs', cDefaultIntervalMs),
    cMinIntervalMs, cMaxIntervalMs), mError) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cRequestFailed,
      cTexts[TProfilerText.StartFailed].Fmt([mProcessId, mError]));
  end;
  FSampler := mSampler;
  FProcessId := Cardinal(mProcessId);
  FWatch := TStopwatch.StartNew;
  FProfile := Default(TAtlasProfile);
  FProfile.ProgramName := TextParam(mParams, 'program');
  FProfile.Project := TextParam(mParams, 'project');
  FProfile.Platform := TextParam(mParams, 'platform');
  FProfile.StartedAt := Now;
  FProfile.IntervalMs := EnsureRange(IntParam(mParams, 'intervalMs', cDefaultIntervalMs), cMinIntervalMs,
    cMaxIntervalMs);
  if FProfile.ProgramName = '' then
  begin
    FProfile.ProgramName := ExtractFileName(mSampler.MainFileName);
  end;
  mMapFile := TextParam(mParams, 'mapFile');
  if mMapFile = '' then
  begin
    mMapFile := ChangeFileExt(mSampler.MainFileName, '.map');
  end;
  LoadMap(mMapFile);
  mResult := TJSONObject.Create;
  mResult.AddPair('started', TJSONBool.Create(True));
  mResult.AddPair('mapFile', mMapFile);
  if FMap <> nil then
  begin
    mResult.AddPair('routines', TJSONNumber.Create(FMap.SymbolCount));
  end
  else
  begin
    mResult.AddPair('routines', TJSONNumber.Create(0));
  end;
  Result := mResult;
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

function TLspProfiler.Finish: TJSONObject;
var
  mRun: TAtlasSampleRun;
  mResolver: TAtlasProfileResolver;
  mPath: string;
begin
  mRun := FSampler.Stop;
  FSampler := nil;
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

initialization
  TAtlasTextTables.Add('Atlas.Common.Lsp.Profiler', cTexts);

end.
