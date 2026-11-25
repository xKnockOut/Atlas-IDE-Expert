unit Atlas.Common.Architecture.UsesService;

// Uses-Graph je Symbolindex (#268), für alle Nutzer derselbe: Architektur
// (#1118), Zyklen (#64), Unit-Beziehungen (#593), Kosten einer Änderung
// (#554), Export (#65).
//
// - Der Graph folgt dem Index: Hat sich dessen Generation geändert, gleicht
//   Read ihn vor dem Lesen ab und baut nur die geänderten Units neu ein
//   (inkrementell, #22). Neue Optionen bauen ihn neu auf.
// - Lesen und Abgleichen laufen unter einer Sperre; ein Leser hält sie nur
//   für seine Abfrage. Abfragen dauern auch bei einigen tausend Units nur
//   Millisekunden. Aus dem Hauptthread der IDE wird nie gelesen: der Server
//   rechnet im Arbeitsthread der Anfrage.
// - Derived hält Auswertungen über den ganzen Graphen (Feature-Zyklen) je
//   Schlüssel, bis sich der Graph ändert: Jede Datei einer Prüfung fragt
//   dieselbe Auswertung, gerechnet wird sie einmal.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph;

type
  TUsesGraphReader = reference to procedure(const AGraph: TUsesGraph);
  TUsesGraphDerive = reference to function(const AGraph: TUsesGraph): IInterface;

  TUsesGraphService = class
  private
    FIndex: ISymbolIndex;
    FOptions: TUsesGraphOptions;
    FGraph: TUsesGraph;
    FGeneration: Int64;
    FLock: TObject;
    FRebuilds: Integer;
    FUpdates: Integer;
    /// <summary>Abgeleitete Werte je Schlüssel zur Generation FGeneration.</summary>
    FDerived: TDictionary<string, IInterface>;
    procedure Refresh;
  public
    constructor Create(const AIndex: ISymbolIndex; const AOptions: TUsesGraphOptions);
    destructor Destroy; override;
    /// <summary>Neue Optionen; der Graph entsteht beim nächsten Read neu.</summary>
    procedure SetOptions(const AOptions: TUsesGraphOptions);
    function Options: TUsesGraphOptions;
    /// <summary>Gleicht den Graphen mit dem Index ab und ruft AReader unter der Sperre auf.</summary>
    procedure Read(const AReader: TUsesGraphReader);
    /// <summary>Wert zu AKey aus dem aktuellen Graphen: ADerive läuft unter der Sperre, je Schlüssel einmal bis
    /// zur nächsten Änderung des Graphen.</summary>
    function Derived(const AKey: string; const ADerive: TUsesGraphDerive): IInterface;
    /// <summary>Generation des Index, auf der der Graph zuletzt stand; -1 vor dem ersten Read.</summary>
    function Generation: Int64;
    /// <summary>Wie oft der Graph ganz neu aufgebaut bzw. inkrementell abgeglichen wurde (für Tests und das
    /// Diagnoselog).</summary>
    function Rebuilds: Integer;
    function Updates: Integer;
  end;

implementation

{ TUsesGraphService }

constructor TUsesGraphService.Create(const AIndex: ISymbolIndex; const AOptions: TUsesGraphOptions);
begin
  inherited Create;
  FIndex := AIndex;
  FOptions := AOptions;
  FGeneration := -1;
  FLock := TObject.Create;
  FDerived := TDictionary<string, IInterface>.Create(4);
end;

destructor TUsesGraphService.Destroy;
begin
  FDerived.Free;
  FGraph.Free;
  FLock.Free;
  inherited;
end;

procedure TUsesGraphService.Refresh;
var
  mCurrent: Int64;
begin
  mCurrent := FIndex.Generation;
  if (FGraph <> nil) and (mCurrent = FGeneration) then
  begin
    Exit;
  end;
  if FGraph = nil then
  begin
    FGraph := TUsesGraph.Create(FIndex.Units, FOptions);
    Inc(FRebuilds);
  end
  else
  begin
    FGraph.Synchronize(FIndex.Units);
    Inc(FUpdates);
  end;
  FGeneration := mCurrent;
  FDerived.Clear;
end;

procedure TUsesGraphService.SetOptions(const AOptions: TUsesGraphOptions);
begin
  System.TMonitor.Enter(FLock);
  try
    FOptions := AOptions;
    FreeAndNil(FGraph);
    FGeneration := -1;
    FDerived.Clear;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Options: TUsesGraphOptions;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FOptions;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

procedure TUsesGraphService.Read(const AReader: TUsesGraphReader);
begin
  System.TMonitor.Enter(FLock);
  try
    Refresh;
    AReader(FGraph);
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Derived(const AKey: string; const ADerive: TUsesGraphDerive): IInterface;
begin
  System.TMonitor.Enter(FLock);
  try
    Refresh;
    if not FDerived.TryGetValue(AKey, Result) then
    begin
      Result := ADerive(FGraph);
      FDerived.Add(AKey, Result);
    end;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Generation: Int64;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FGeneration;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TUsesGraphService.Rebuilds: Integer;
begin
  Result := FRebuilds;
end;

function TUsesGraphService.Updates: Integer;
begin
  Result := FUpdates;
end;

end.
