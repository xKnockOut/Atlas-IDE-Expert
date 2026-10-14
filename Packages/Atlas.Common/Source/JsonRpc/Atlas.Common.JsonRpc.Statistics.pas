unit Atlas.Common.JsonRpc.Statistics;

// Antwortzeiten je Methode für den Status-Befehl (#28). Der Dispatcher misst
// jede Anfrage, auch nebenläufige aus Worker-Threads; daher threadsicher.
// Dazu ein Ringpuffer der letzten Anfragen für den Fehlerbericht (#108): nur
// Methode, Zeit, Dauer und Ergebnisstatus, nie Parameter oder Ergebnisse.

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

  /// <summary>Eine Anfrage im Ringpuffer (#108); ohne Inhalt.</summary>
  TRecentRequest = record
    /// <summary>Ende der Anfrage (lokale Zeit).</summary>
    Finished: TDateTime;
    Method: string;
    ElapsedMs: Int64;
    Failed: Boolean;
  end;

  IJsonRpcStatistics = interface
    ['{4B7C2A10-8E55-4F3B-9B1E-6A0D2C1F7E21}']
    procedure Add(const AMethod: string; AElapsedMs: Int64; AFailed: Boolean);
    /// <summary>Stand aller Methoden, langsamste im Mittel zuerst.</summary>
    function Snapshot: TArray<TMethodStatistics>;
    /// <summary>Die letzten Anfragen, älteste zuerst; höchstens TJsonRpcStatistics.RecentCapacity.</summary>
    function Recent: TArray<TRecentRequest>;
  end;

  TJsonRpcStatistics = class(TInterfacedObject, IJsonRpcStatistics)
  public const
    /// <summary>Größe des Ringpuffers; ältere Einträge werden verdrängt.</summary>
    RecentCapacity = 50;
  private
    FLock: TObject;
    FMethods: TDictionary<string, TMethodStatistics>;
    FRecent: array[0..RecentCapacity - 1] of TRecentRequest;
    /// <summary>Nächster Platz im Ring.</summary>
    FRecentNext: Integer;
    FRecentCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Add(const AMethod: string; AElapsedMs: Int64; AFailed: Boolean);
    function Snapshot: TArray<TMethodStatistics>;
    function Recent: TArray<TRecentRequest>;
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
    FRecent[FRecentNext].Finished := Now;
    FRecent[FRecentNext].Method := AMethod;
    FRecent[FRecentNext].ElapsedMs := AElapsedMs;
    FRecent[FRecentNext].Failed := AFailed;
    FRecentNext := (FRecentNext + 1) mod RecentCapacity;
    if FRecentCount < RecentCapacity then
      Inc(FRecentCount);
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

function TJsonRpcStatistics.Recent: TArray<TRecentRequest>;
var
  Index, First: Integer;
begin
  TMonitor.Enter(FLock);
  try
    SetLength(Result, FRecentCount);
    // Ältester Eintrag: bei vollem Ring der nächste Platz, sonst der erste.
    First := (FRecentNext - FRecentCount + RecentCapacity) mod RecentCapacity;
    for Index := 0 to FRecentCount - 1 do
      Result[Index] := FRecent[(First + Index) mod RecentCapacity];
  finally
    TMonitor.Exit(FLock);
  end;
end;

end.
