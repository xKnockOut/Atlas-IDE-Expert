unit Atlas.Common.Architecture.Service;

// Architekturübersicht je Symbolindex (#1118) für Fenster, Bericht,
// Kommandozeile und get_architecture: ein Dienst, dieselben Zahlen.
//
// - Umfang: die Units des Index, deren Datei in ARequest.Files steht (leer =
//   alle Projekt-Units), Bibliotheks-Units nur mit IncludeLibrary;
//   Exclude-Muster auf Unit-Name oder Pfad relativ zu Root; Packages (.dpk)
//   nie, Programme (.dpr) mit ihren uses schon.
// - Zwischenspeicher: Das Ergebnis gilt, solange Index-Generation und
//   Anfrage gleich bleiben; sonst wird neu gerechnet. Rechnen und Lesen
//   laufen unter einer Sperre im Arbeitsthread des Aufrufers (Server), nie im
//   Hauptthread der IDE.

interface

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.Overview;

type
  TArchitectureRequest = record
    Title: string;
    Root: string;
    /// <summary>"project" oder "projectGroup" (nur zur Anzeige; den Umfang bestimmt Files).</summary>
    Scope: string;
    IncludeLibrary: Boolean;
    CentralUnits: Integer;
    Exclude: TArray<string>;
    /// <summary>Namensräume des Projekts für uses ohne Präfix (SysUtils → System.SysUtils).</summary>
    Namespaces: TArray<string>;
    /// <summary>Dateien im Umfang; leer = alle Units des Index (außer Bibliothek ohne IncludeLibrary).</summary>
    Files: TArray<string>;
    /// <summary>Einstellungen der Gruppierung (architecture.grouping).</summary>
    Grouping: TArchitectureGrouping;
    /// <summary>Werte aus den Einstellungen architecture.*.</summary>
    class function FromSettings(const ASettings: TServerSettings): TArchitectureRequest; static;
    /// <summary>Text, der die Anfrage eindeutig beschreibt (Schlüssel des Zwischenspeichers).</summary>
    function Key: string;
  end;

  TArchitectureService = class
  private
    FIndex: ISymbolIndex;
    FLocator: TUsesLocator;
    FLock: TObject;
    FHasResult: Boolean;
    FGeneration: Int64;
    FKey: string;
    FResult: TArchitectureOverview;
    FComputations: Integer;
    function Compute(const ARequest: TArchitectureRequest; AGeneration: Int64): TArchitectureOverview;
  public
    /// <summary>AReader/ADefines für die Fundstellen der uses-Einträge (Zyklen, Querverbindungen).</summary>
    constructor Create(const AIndex: ISymbolIndex; const AReader: TUsesTextReader; const ADefines: TUsesDefinesFunc);
    destructor Destroy; override;
    /// <summary>Übersicht zur Anfrage; aus dem Zwischenspeicher, solange Index und Anfrage gleich sind.</summary>
    function Overview(const ARequest: TArchitectureRequest): TArchitectureOverview;
    /// <summary>Wie oft wirklich gerechnet wurde (Tests, Diagnoselog).</summary>
    function Computations: Integer;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Common.Architecture.UsesGraph;

{ TArchitectureRequest }

class function TArchitectureRequest.FromSettings(const ASettings: TServerSettings): TArchitectureRequest;
begin
  Result := Default(TArchitectureRequest);
  Result.Scope := ASettings.ArchitectureScope;
  Result.IncludeLibrary := ASettings.ArchitectureIncludeLibraryUnits;
  Result.CentralUnits := ASettings.ArchitectureCentralUnits;
  Result.Exclude := ASettings.ArchitectureExclude;
  Result.Grouping := TArchitectureGrouping.Default;
  Result.Grouping.Resolution := ASettings.ArchitectureGroupingResolution;
  Result.Grouping.MaxShare := ASettings.ArchitectureGroupingMaxShare;
  Result.Grouping.MinCohesion := ASettings.ArchitectureGroupingMinCohesion;
end;

function TArchitectureRequest.Key: string;
var
  Files: TArray<string>;
begin
  Files := Copy(Self.Files);
  TArray.Sort<string>(Files);
  Result := Title + #1 + Root + #1 + Scope + #1 + BoolToStr(IncludeLibrary, True) + #1 + IntToStr(CentralUnits) + #1 +
    string.Join(#2, Exclude) + #1 + string.Join(#2, Namespaces) + #1 + LowerCase(string.Join(#2, Files)) + #1 +
    Grouping.Key;
end;

{ TArchitectureService }

constructor TArchitectureService.Create(const AIndex: ISymbolIndex; const AReader: TUsesTextReader;
  const ADefines: TUsesDefinesFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FLocator := TUsesLocator.Create(AReader, ADefines);
  FLock := TObject.Create;
end;

destructor TArchitectureService.Destroy;
begin
  FLocator.Free;
  FLock.Free;
  inherited;
end;

function TArchitectureService.Compute(const ARequest: TArchitectureRequest; AGeneration: Int64): TArchitectureOverview;
var
  Units, Selected: TArray<TUnitIndex>;
  Item: TUnitIndex;
  InScope: TDictionary<string, Boolean>;
  FileName: string;
  Options: TUsesGraphOptions;
  Graph: TUsesGraph;
  Count: Integer;
begin
  Units := FIndex.Units;
  InScope := TDictionary<string, Boolean>.Create;
  try
    for FileName in ARequest.Files do
      InScope.AddOrSetValue(LowerCase(FileName), True);
    SetLength(Selected, Length(Units));
    Count := 0;
    for Item in Units do
    begin
      // Packages (.dpk) kennen nur requires und contains, keine uses: in der Karte stünden sie als Unit ohne
      // Beziehung.
      if SameText(ExtractFileExt(Item.FileName), '.dpk') then
        Continue;
      // Bibliotheks-Units zählt der Graph je nach IncludeLibrary; die Dateiliste betrifft nur Projekt-Units.
      if not Item.Library_ and (InScope.Count > 0) and not InScope.ContainsKey(LowerCase(Item.FileName)) then
        Continue;
      Selected[Count] := Item;
      Inc(Count);
    end;
    SetLength(Selected, Count);
  finally
    InScope.Free;
  end;
  Options := TUsesGraphOptions.Default;
  Options.IncludeLibrary := ARequest.IncludeLibrary;
  Options.Exclude := ARequest.Exclude;
  Options.Root := ARequest.Root;
  Options.Namespaces := ARequest.Namespaces;
  Graph := TUsesGraph.Create(Selected, Options);
  try
    if ARequest.CentralUnits > 0 then
      Result := TArchitectureAnalyzer.Analyze(Graph, FLocator, ARequest.CentralUnits, ARequest.Grouping)
    else
      Result := TArchitectureAnalyzer.Analyze(Graph, FLocator, 15, ARequest.Grouping);
  finally
    Graph.Free;
  end;
  Result.Title := ARequest.Title;
  Result.Scope := ARequest.Scope;
  Result.Generation := AGeneration;
end;

function TArchitectureService.Overview(const ARequest: TArchitectureRequest): TArchitectureOverview;
var
  Generation: Int64;
  Key: string;
begin
  System.TMonitor.Enter(FLock);
  try
    Generation := FIndex.Generation;
    Key := ARequest.Key;
    if not FHasResult or (FGeneration <> Generation) or (FKey <> Key) then
    begin
      FResult := Compute(ARequest, Generation);
      FGeneration := Generation;
      FKey := Key;
      FHasResult := True;
      Inc(FComputations);
    end;
    Result := FResult;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

function TArchitectureService.Computations: Integer;
begin
  System.TMonitor.Enter(FLock);
  try
    Result := FComputations;
  finally
    System.TMonitor.Exit(FLock);
  end;
end;

end.
