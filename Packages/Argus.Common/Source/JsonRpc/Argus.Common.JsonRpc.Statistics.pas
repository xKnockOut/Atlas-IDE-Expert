unit Argus.Common.JsonRpc.Statistics;

// Antwortzeiten je Methode für den Status-Befehl (#28). Der Dispatcher misst
// jede Anfrage, auch nebenläufige aus Worker-Threads; daher threadsicher.

interface

uses
  System.SysUtils,
  System.Generics.Collections;

type
  TMethodStatistics = record
    Method: string;
    Count: Integer;
    TotalMs: Int64;
    MaxMs: Int64;
    Failed: Integer;
    function AverageMs: Double;
  end;

  IJsonRpcStatistics = interface
    ['{4B7C2A10-8E55-4F3B-9B1E-6A0D2C1F7E21}']
    procedure Add(const AMethod: string; AElapsedMs: Int64; AFailed: Boolean);
    /// <summary>Stand aller Methoden, langsamste im Mittel zuerst.</summary>
    function Snapshot: TArray<TMethodStatistics>;
  end;

  TJsonRpcStatistics = class(TInterfacedObject, IJsonRpcStatistics)
  private
    FLock: TObject;
    FMethods: TDictionary<string, TMethodStatistics>;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AMethod: string; AElapsedMs: Int64; AFailed: Boolean);
    function Snapshot: TArray<TMethodStatistics>;
  end;

implementation

uses
  System.Generics.Defaults;

{ TMethodStatistics }

function TMethodStatistics.AverageMs: Double;
begin
  if Count = 0 then
    Result := 0
  else
    Result := TotalMs / Count;
end;

function CompareBySlowest(const ALeft, ARight: TMethodStatistics): Integer;
begin
  if ALeft.AverageMs > ARight.AverageMs then
    Result := -1
  else if ALeft.AverageMs < ARight.AverageMs then
    Result := 1
  else
    Result := CompareStr(ALeft.Method, ARight.Method);
end;

{ TJsonRpcStatistics }

constructor TJsonRpcStatistics.Create;
begin
  inherited Create;
  FLock := TObject.Create;
  FMethods := TDictionary<string, TMethodStatistics>.Create;
end;

destructor TJsonRpcStatistics.Destroy;
begin
  FMethods.Free;
  FLock.Free;
  inherited;
end;

procedure TJsonRpcStatistics.Add(const AMethod: string; AElapsedMs: Int64; AFailed: Boolean);
var
  Entry: TMethodStatistics;
begin
  TMonitor.Enter(FLock);
  try
    if not FMethods.TryGetValue(AMethod, Entry) then
    begin
      Entry := Default(TMethodStatistics);
      Entry.Method := AMethod;
    end;
    Inc(Entry.Count);
    Inc(Entry.TotalMs, AElapsedMs);
    if AElapsedMs > Entry.MaxMs then
      Entry.MaxMs := AElapsedMs;
    if AFailed then
      Inc(Entry.Failed);
    FMethods.AddOrSetValue(AMethod, Entry);
  finally
    TMonitor.Exit(FLock);
  end;
end;

function TJsonRpcStatistics.Snapshot: TArray<TMethodStatistics>;
var
  List: TList<TMethodStatistics>;
begin
  List := TList<TMethodStatistics>.Create(TComparer<TMethodStatistics>.Construct(CompareBySlowest));
  try
    TMonitor.Enter(FLock);
    try
      List.AddRange(FMethods.Values);
    finally
      TMonitor.Exit(FLock);
    end;
    List.Sort;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

end.
