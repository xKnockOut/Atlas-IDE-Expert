unit Atlas.Common.Query.Service;

// Code-Abfragen je Arbeitsbereich (#1351) für IDE-Fenster, MCP query_code,
// --query und die Regeln query:<name>: ein Dienst, dieselben Zahlen.
//
// Ein Ergebnis gilt, solange Index-Generation, Umfang und Anfrage gleich
// bleiben; so rechnet eine gespeicherte Abfrage mit failIfAny einmal je
// Index-Stand, nicht je geprüfter Datei. Abgebrochene Läufe merkt der Dienst
// sich nicht. Rechnen läuft ohne Sperre im Thread des Aufrufers; die Sperre
// schützt nur den Zwischenspeicher. Die Metriken unveränderter Dateien hält
// ein TMetricsCollector über alle Abfragen.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Metrics.Collector,
  Atlas.Common.Query.Contract;

type
  /// <summary>Aktuelle Datenquelle (Index, Umfang, Lesen, Aufrufhierarchie); False, wenn es keine gibt (Projekt
  /// lädt noch nicht).</summary>
  TQuerySourceFunc = reference to function(out ASource: TQuerySource): Boolean;

  TCodeQueryService = class(TInterfacedObject, ICodeQueries)
  private type
    TEntry = record
      Generation: Int64;
      Scope: string;
      Result: TQueryResult;
    end;
  private const
    /// <summary>Höchstzahl gemerkter Ergebnisse; darüber beginnt der Speicher von vorn.</summary>
    cMaxEntries = 64;
  private
    FSourceOf: TQuerySourceFunc;
    FCollector: TMetricsCollector;
    FLock: TObject;
    FCache: TDictionary<string, TEntry>;
    FComputations: Integer;
  public
    constructor Create(const ASourceOf: TQuerySourceFunc);
    destructor Destroy; override;
    function Execute(const ARequest: TQueryRequest): TQueryResult;
    /// <summary>Wie oft wirklich gerechnet wurde (Tests, Diagnoselog).</summary>
    function Computations: Integer;
    /// <summary>Schlüssel des Umfangs: Wurzel und Dateien, sortiert und klein.</summary>
    class function ScopeKey(const ASource: TQuerySource): string; static;
  end;

implementation

uses
  Atlas.Common.Query.Engine;

/// <summary>Abbruch, sobald AFirst oder ASecond ihn meldet; eigene Routine, damit die Methodenreferenz keinen
/// Rahmen von Execute festhält.</summary>
function CombinedCancel(const AFirst, ASecond: TQueryCancelled): TQueryCancelled;
begin
  if not Assigned(AFirst) then
    Exit(ASecond);
  Result :=
    function: Boolean
    begin
      Result := AFirst() or ASecond();
    end;
end;

{ TCodeQueryService }

constructor TCodeQueryService.Create(const ASourceOf: TQuerySourceFunc);
begin
  inherited Create;
  FSourceOf := ASourceOf;
  FCollector := TMetricsCollector.Create;
  FLock := TObject.Create;
  FCache := TDictionary<string, TEntry>.Create;
end;

destructor TCodeQueryService.Destroy;
begin
  FCache.Free;
  FLock.Free;
  FCollector.Free;
  inherited;
end;

class function TCodeQueryService.ScopeKey(const ASource: TQuerySource): string;
var
  mFiles: TArray<string>;
begin
  mFiles := Copy(ASource.Files);
  TArray.Sort<string>(mFiles);
  Result := LowerCase(ASource.Root + #1 + string.Join(#2, mFiles) + #1 + string.Join(#2, ASource.Namespaces));
end;

function TCodeQueryService.Execute(const ARequest: TQueryRequest): TQueryResult;
var
  mSource: TQuerySource;
  mKey, mScope: string;
  mGeneration: Int64;
  mEntry: TEntry;
begin
  if not (Assigned(FSourceOf) and FSourceOf(mSource)) or (mSource.Index = nil) then
  begin
    Result := Default(TQueryResult);
    Result.Query := ARequest.Query;
    Result.Error := 'Kein Projekt geladen';
    Exit;
  end;
  mKey := ARequest.Query + #1 + string.Join(#2, ARequest.Fields) + #1 + IntToStr(ARequest.Limit);
  mScope := ScopeKey(mSource);
  mGeneration := mSource.Index.Generation;
  System.TMonitor.Enter(FLock);
  try
    if FCache.TryGetValue(mKey, mEntry) and (mEntry.Generation = mGeneration) and (mEntry.Scope = mScope) then
      Exit(mEntry.Result);
  finally
    System.TMonitor.Exit(FLock);
  end;
  if Assigned(ARequest.Cancelled) then
    mSource.Cancelled := CombinedCancel(mSource.Cancelled, ARequest.Cancelled);
  Result := TCodeQueryEngine.Run(mSource, ARequest, FCollector);
  // Abgebrochene Läufe nicht merken: Der nächste Aufruf soll rechnen.
  if Result.Failed and (Result.ErrorColumn = 0) then
    Exit;
  mEntry.Generation := mGeneration;
  mEntry.Scope := mScope;
  mEntry.Result := Result;
  System.TMonitor.Enter(FLock);
  try
    Inc(FComputations);
    if (FCache.Count >= cMaxEntries) and not FCache.ContainsKey(mKey) then
      FCache.Clear;
    FCache.AddOrSetValue(mKey, mEntry);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TCodeQueryService.Computations: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FComputations;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
