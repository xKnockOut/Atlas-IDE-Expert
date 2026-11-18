unit Atlas.Common.Mcp.Statistics;

// Statistik der MCP-Aufrufe je Sitzung (#2611), Zählung im Server. Die Zahlen selbst (TMcpSessionStatistics) liegen
// in Atlas.Text.McpStatistics, weil AtlasMonitor und das Plugin sie aus der Statusdatei lesen. TMcpServer meldet
// jeden Aufruf eines Werkzeugs, einer Ressource oder eines Prompts mit Erfolg bzw. Fehler, Dauer und Antwortgröße. Gezählt wird je Name: Aufrufe, Fehler, Median
// und Höchstwert von Dauer und Antwortgröße (Median über die letzten cMaxSamples Aufrufe) und der letzte
// fehlgeschlagene Aufruf mit seinen Argumenten. Die Argumente stehen gekennzeichnet wie im Protokoll
// (Atlas.Text.LogMarks): Werte unter Schlüsseln für Dateien und Ordner als Pfad, alle anderen als fremder Text, je
// Wert höchstens cMaxArgumentChars Zeichen (Argumente wie text bei check_code tragen Quelltext). Anzeigen nehmen
// TLogMarks.Plain, das anonyme Diagnosepaket ersetzt die Werte.
// Bekannte Werkzeuge (Know) stehen auch ohne Aufruf in der Liste, damit sichtbar wird, was nie vorkommt.
// Threadsicher: Der Takt der Statusdatei liest den Stand, während Aufrufe laufen.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Text.McpStatistics;

type
  /// <summary>Ein Aufruf, wie TMcpServer ihn meldet.</summary>
  TMcpCall = record
    Kind: TMcpCallKind;
    Name: string;
    Failed: Boolean;
    ElapsedMs: Int64;
    /// <summary>Länge der Antwort in Bytes (UTF-8).</summary>
    Bytes: Int64;
    /// <summary>Argumente (nil ohne); gehören dem Aufrufer und werden nur bei Failed gelesen.</summary>
    Arguments: TJSONValue;
    /// <summary>Fehlermeldung bei Failed.</summary>
    Message: string;
  end;

  TMcpStatistics = class
  public const
    /// <summary>Höchstlänge je Argument eines fehlgeschlagenen Aufrufs.</summary>
    cMaxArgumentChars = 500;
    /// <summary>Median über so viele letzte Aufrufe je Name.</summary>
    cMaxSamples = 1000;
  private type
    TCounter = class
    public
      Summary: TMcpCallSummary;
      Durations: TList<Int64>;
      Sizes: TList<Int64>;
      constructor Create(AKind: TMcpCallKind; const AName: string);
      destructor Destroy; override;
      procedure Add(const ACall: TMcpCall; ANow: TDateTime);
      function Current: TMcpCallSummary;
    end;
  private
    FLock: TObject;
    FCounters: TObjectDictionary<string, TCounter>;
    FClient: string;
    FProject: string;
    FStarted: TDateTime;
    /// <summary>Zähler für AKind und AName, bei Bedarf angelegt; nur unter FLock.</summary>
    function CounterOf(AKind: TMcpCallKind; const AName: string): TCounter;
  public
    constructor Create(const AProject: string; AStarted: TDateTime);
    destructor Destroy; override;
    procedure SetClient(const AClient: string);
    /// <summary>AName steht auch ohne Aufruf in der Liste (angebotenes Werkzeug).</summary>
    procedure Know(AKind: TMcpCallKind; const AName: string);
    procedure Add(const ACall: TMcpCall; ANow: TDateTime);
    function Snapshot: TMcpSessionStatistics;
    /// <summary>Argumente als „name=wert …“ wie im Protokoll: Werte unter Pfad-Schlüsseln als Pfad gekennzeichnet,
    /// anderer Text als Text, je Wert höchstens cMaxArgumentChars Zeichen; '' bei nil.</summary>
    class function MarkedArguments(AArguments: TJSONValue): string; static;
    /// <summary>Median (bei gerader Anzahl der Mittelwert der beiden mittleren, abgerundet); 0 ohne Werte.</summary>
    class function Median(const AValues: TArray<Int64>): Int64; static;
  end;

implementation

uses
  System.Math,
  System.Generics.Defaults,
  Atlas.Text.LogMarks;

const
  /// <summary>Schlüssel, deren Werte Dateien oder Ordner sind (wie in den Eingabeschemas der Werkzeuge).</summary>
  cPathKeys: array[0..9] of string = ('file', 'files', 'path', 'paths', 'folder', 'project', 'uri', 'unitFile',
    'target', 'root');

function IsPathKey(const AKey: string): Boolean;
var
  mKey: string;
begin
  for mKey in cPathKeys do
  begin
    if SameText(mKey, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Ein Argument als „name=wert“: Zahlen, Wahrheitswerte und null im Klartext, Text in Anführungszeichen,
/// Listen und Objekte als JSON; Text, Listen und Objekte gekürzt und gekennzeichnet (Pfad bzw. Text).</summary>
function ArgumentText(const AKey: string; AValue: TJSONValue): string;
var
  mText: string;
  mKind: TLogMarkKind;
begin
  if (AValue is TJSONNumber) or (AValue is TJSONBool) or (AValue is TJSONNull) then
  begin
    Exit(AKey + '=' + AValue.ToJSON([]));
  end;
  mKind := TLogMarkKind.Text;
  if IsPathKey(AKey) then
  begin
    mKind := TLogMarkKind.Path;
  end;
  if AValue is TJSONString then
  begin
    mText := Copy(AValue.Value, 1, TMcpStatistics.cMaxArgumentChars);
    Exit(AKey + '="' + TLogMarks.Mark(mKind, mText) + '"');
  end;
  mText := Copy(AValue.ToJSON([]), 1, TMcpStatistics.cMaxArgumentChars);
  Result := AKey + '=' + TLogMarks.Mark(mKind, mText);
end;

{ TMcpStatistics.TCounter }

constructor TMcpStatistics.TCounter.Create(AKind: TMcpCallKind; const AName: string);
begin
  inherited Create;
  Summary := Default(TMcpCallSummary);
  Summary.Kind := AKind;
  Summary.Name := AName;
  Durations := TList<Int64>.Create;
  Sizes := TList<Int64>.Create;
end;

destructor TMcpStatistics.TCounter.Destroy;
begin
  Sizes.Free;
  Durations.Free;
  inherited;
end;

procedure TMcpStatistics.TCounter.Add(const ACall: TMcpCall; ANow: TDateTime);
begin
  Inc(Summary.Calls);
  Summary.MaxMs := Max(Summary.MaxMs, ACall.ElapsedMs);
  Summary.MaxBytes := Max(Summary.MaxBytes, ACall.Bytes);
  if Durations.Count >= TMcpStatistics.cMaxSamples then
  begin
    Durations.Delete(0);
    Sizes.Delete(0);
  end;
  Durations.Add(ACall.ElapsedMs);
  Sizes.Add(ACall.Bytes);
  if ACall.Failed then
  begin
    Inc(Summary.Errors);
    Summary.LastFailed.At := ANow;
    Summary.LastFailed.Arguments := TMcpStatistics.MarkedArguments(ACall.Arguments);
    Summary.LastFailed.Message := TLogMarks.Text(Copy(ACall.Message, 1, TMcpStatistics.cMaxArgumentChars));
  end;
end;

function TMcpStatistics.TCounter.Current: TMcpCallSummary;
begin
  Result := Summary;
  Result.MedianMs := TMcpStatistics.Median(Durations.ToArray);
  Result.MedianBytes := TMcpStatistics.Median(Sizes.ToArray);
end;

{ TMcpStatistics }

constructor TMcpStatistics.Create(const AProject: string; AStarted: TDateTime);
begin
  inherited Create;
  FLock := TObject.Create;
  FCounters := TObjectDictionary<string, TCounter>.Create([doOwnsValues]);
  FProject := AProject;
  FStarted := AStarted;
  // Monitor-Datensatz gleich anlegen, nicht beim ersten Aufruf (Leckmonitor der Tests).
  System.TMonitor.Enter(FLock);
  System.TMonitor.Exit(FLock);
end;

destructor TMcpStatistics.Destroy;
begin
  FCounters.Free;
  FLock.Free;
  inherited;
end;

function TMcpStatistics.CounterOf(AKind: TMcpCallKind; const AName: string): TCounter;
var
  mKey: string;
begin
  mKey := TMcpStatisticsFormat.KindCode(AKind) + ':' + AName;
  if not FCounters.TryGetValue(mKey, Result) then
  begin
    Result := TCounter.Create(AKind, AName);
    FCounters.Add(mKey, Result);
  end;
end;

procedure TMcpStatistics.SetClient(const AClient: string);
begin
  System.TMonitor.Enter(FLock);
  try
    FClient := AClient;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TMcpStatistics.Know(AKind: TMcpCallKind; const AName: string);
begin
  System.TMonitor.Enter(FLock);
  try
    CounterOf(AKind, AName);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TMcpStatistics.Add(const ACall: TMcpCall; ANow: TDateTime);
begin
  System.TMonitor.Enter(FLock);
  try
    CounterOf(ACall.Kind, ACall.Name).Add(ACall, ANow);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function CompareSummaries(const ALeft, ARight: TMcpCallSummary): Integer;
begin
  Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
  if Result = 0 then
  begin
    Result := ARight.Calls - ALeft.Calls;
  end;
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.Name, ARight.Name);
  end;
end;

function TMcpStatistics.Snapshot: TMcpSessionStatistics;
var
  mCounter: TCounter;
  mCalls: TArray<TMcpCallSummary>;
begin
  Result := Default(TMcpSessionStatistics);
  mCalls := nil;
  System.TMonitor.Enter(FLock);
  try
    Result.Client := FClient;
    Result.Project := FProject;
    Result.Started := FStarted;
    for mCounter in FCounters.Values do
    begin
      mCalls := mCalls + [mCounter.Current];
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
  // Name zuletzt: eindeutig, die Sortierung muss nicht stabil sein.
  TArray.Sort<TMcpCallSummary>(mCalls, TComparer<TMcpCallSummary>.Construct(CompareSummaries));
  Result.Calls := mCalls;
end;

class function TMcpStatistics.MarkedArguments(AArguments: TJSONValue): string;
var
  mPair: TJSONPair;
begin
  Result := '';
  if AArguments = nil then
  begin
    Exit;
  end;
  if not (AArguments is TJSONObject) then
  begin
    Exit(TLogMarks.Text(Copy(AArguments.ToJSON([]), 1, cMaxArgumentChars)));
  end;
  for mPair in TJSONObject(AArguments) do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + ArgumentText(mPair.JsonString.Value, mPair.JsonValue);
  end;
end;

class function TMcpStatistics.Median(const AValues: TArray<Int64>): Int64;
var
  mSorted: TArray<Int64>;
  mMiddle: Integer;
begin
  if Length(AValues) = 0 then
  begin
    Exit(0);
  end;
  mSorted := Copy(AValues);
  TArray.Sort<Int64>(mSorted);
  mMiddle := Length(mSorted) div 2;
  if Odd(Length(mSorted)) then
  begin
    Exit(mSorted[mMiddle]);
  end;
  Result := (mSorted[mMiddle - 1] + mSorted[mMiddle]) div 2;
end;

end.
