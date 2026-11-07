unit Atlas.Common.Lsp.PullDiagnostics.Cache;

// Gespeicherte Befunde für textDocument/diagnostic (#82, #1237): je Datei die
// letzte Ergebnis-Id mit den Befunden kompakt als JSON-Text. Fragt der Client
// dieselbe Datei im selben Stand erneut an, wird nicht neu geprüft. Fragen
// mehrere Anfragen dieselbe Datei im selben Stand an, rechnet nur die erste;
// die übrigen warten auf ihr Ergebnis. Threadsicher.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract;

type
  /// <summary>Berechnet die Befunde einer Datei; der Aufrufer übernimmt das Ergebnis.</summary>
  TPullCompute = reference to function: TJSONArray;

  TPullReportCache = class
  public const
    /// <summary>Höchstzahl gespeicherter Dateibefunde, danach wird der Speicher geleert.</summary>
    cMaxCachedReports = 500;
    /// <summary>Takt, in dem eine Anfrage auf die gleiche Berechnung einer anderen wartet.</summary>
    cRunningPollMs = 20;
  private
    // Uri -> Befunde bzw. Ergebnis-Id. Unter FLock.
    FReports: TDictionary<string, TBytes>;
    FIds: TDictionary<string, string>;
    FLock: TObject;
    // Laufende Berechnungen: Uri + #0 + Ergebnis-Id. Unter FLock.
    FRunning: TDictionary<string, Boolean>;
    /// <summary>True: Der Aufrufer rechnet AKey jetzt selbst. False mit ACached: Befunde aus dem
    /// Speicher (gehören dem Aufrufer). False ohne: Eine andere Anfrage rechnet gerade.</summary>
    function Claim(const AUri, AResultId, AKey: string; out ACached: TJSONArray): Boolean;
    procedure Store(const AUri, AResultId: string; AItems: TJSONArray);
    procedure Release(const AKey: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Befunde zu AUri im Stand AResultId, aus dem Speicher oder mit ACompute neu berechnet. Ohne
    /// Ergebnis-Id rechnet ACompute immer. ACancellation darf nil sein. Der Aufrufer übernimmt das Ergebnis.
    /// </summary>
    function Get(const AUri, AResultId: string; const ACompute: TPullCompute;
      const ACancellation: IJsonRpcCancellationToken): TJSONArray;
  end;

implementation

uses
  Atlas.Common.Lsp.CompactJson;

constructor TPullReportCache.Create;
begin
  inherited Create;
  FReports := TDictionary<string, TBytes>.Create;
  FIds := TDictionary<string, string>.Create;
  FLock := TObject.Create;
  FRunning := TDictionary<string, Boolean>.Create;
end;

destructor TPullReportCache.Destroy;
begin
  FRunning.Free;
  FLock.Free;
  FIds.Free;
  FReports.Free;
  inherited;
end;

function TPullReportCache.Claim(const AUri, AResultId, AKey: string; out ACached: TJSONArray): Boolean;
var
  mKnown: string;
  mItems: TBytes;
begin
  ACached := nil;
  TMonitor.Enter(FLock);
  try
    if FIds.TryGetValue(AUri, mKnown) and (mKnown = AResultId) and FReports.TryGetValue(AUri, mItems) then
    begin
      ACached := TCompactJson.UnpackArray(mItems);
      Exit(False);
    end;
    Result := not FRunning.ContainsKey(AKey);
    if Result then
    begin
      FRunning.Add(AKey, True);
    end;
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TPullReportCache.Store(const AUri, AResultId: string; AItems: TJSONArray);
var
  mCompact: TBytes;
begin
  mCompact := TCompactJson.Pack(AItems);
  TMonitor.Enter(FLock);
  try
    if FReports.Count >= cMaxCachedReports then
    begin
      FReports.Clear;
      FIds.Clear;
    end;
    FReports.AddOrSetValue(AUri, mCompact);
    FIds.AddOrSetValue(AUri, AResultId);
  finally
    TMonitor.Exit(FLock);
  end;
end;

procedure TPullReportCache.Release(const AKey: string);
begin
  TMonitor.Enter(FLock);
  try
    FRunning.Remove(AKey);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TPullReportCache.Get(const AUri, AResultId: string; const ACompute: TPullCompute;
  const ACancellation: IJsonRpcCancellationToken): TJSONArray;
var
  mKey: string;
  mCached: TJSONArray;
begin
  if AResultId = '' then
  begin
    Exit(ACompute());
  end;
  mKey := AUri + #0 + AResultId;
  while not Claim(AUri, AResultId, mKey, mCached) do
  begin
    if mCached <> nil then
    begin
      Exit(mCached);
    end;
    // Dieselbe Datei im selben Stand rechnet schon eine andere Anfrage: auf ihr Ergebnis warten.
    if ACancellation <> nil then
    begin
      ACancellation.ThrowIfCancellationRequested;
    end;
    Sleep(cRunningPollMs);
  end;
  try
    Result := ACompute();
    Store(AUri, AResultId, Result);
  finally
    Release(mKey);
  end;
end;

end.
