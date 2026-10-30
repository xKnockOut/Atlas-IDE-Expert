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
// - Angleichung (#1367, KeepPrevious): Nach dem Rechnen werden Farben und
//   Namen der Teilsysteme an den vorigen Stand angeglichen: Baseline, falls
//   gesetzt und ladbar, sonst PreviousFile (der zuletzt berechnete Stand).
//   Mit PreviousFile schreibt jede Rechnung ihr Ergebnis dorthin; ohne
//   (AtlasServer --architecture) bleibt die Platte unberührt. Rename rechnet
//   einmal ohne vorigen Stand (Befehl „Teilsysteme neu benennen“).

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
    /// <summary>Zuordnung der Units erklären (architecture.explainAssignment, #1368); ändert nur die Ausgabe,
    /// nicht die Rechnung.</summary>
    ExplainAssignment: Boolean;
    /// <summary>Farben und Namen an den vorigen Stand angleichen (architecture.grouping.keepPrevious, #1367).
    /// </summary>
    KeepPrevious: Boolean;
    /// <summary>Gespeicherter Stand (architecture.baseline), relativ zu Root oder absolut; '' = keiner.</summary>
    Baseline: string;
    /// <summary>Zuletzt berechneter Stand dieses Umfangs (TIndexCacheDirectory.ArchitectureFileFor); '' = weder
    /// lesen noch schreiben.</summary>
    PreviousFile: string;
    /// <summary>Einmal ohne vorigen Stand rechnen (nicht im Schlüssel: rechnet immer neu).</summary>
    Rename: Boolean;
    /// <summary>Werte aus den Einstellungen architecture.*.</summary>
    class function FromSettings(const ASettings: TServerSettings): TArchitectureRequest; static;
    /// <summary>Text, der die Anfrage eindeutig beschreibt (Schlüssel des Zwischenspeichers).</summary>
    function Key: string;
    /// <summary>Umfang (Scope, Root, Title) für die Ablage des zuletzt berechneten Stands.</summary>
    function ScopeKey: string;
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
  System.Classes,
  System.Generics.Collections,
  System.IOUtils,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.Snapshot,
  Atlas.Common.Architecture.Comparison,
  Atlas.Common.Architecture.Alignment;

/// <summary>Stand aus AFileName, wenn die Datei existiert und lesbar ist; AAt = letzte Änderung der Datei.</summary>
function TryLoad(const AFileName: string; out ASnapshot: TArchitectureSnapshot; out AAt: TDateTime): Boolean;
var
  mError: string;
begin
  AAt := 0;
  Result := (AFileName <> '') and FileExists(AFileName) and TArchitectureSnapshots.Load(AFileName, ASnapshot, mError);
  if Result then
    AAt := TFile.GetLastWriteTime(AFileName);
end;

/// <summary>Angleichung an den vorigen Stand der Anfrage (#1367): Baseline vor PreviousFile.</summary>
procedure AlignToPrevious(var AOverview: TArchitectureOverview; const ARequest: TArchitectureRequest);
var
  mPrevious: TArchitectureSnapshot;
  mAt: TDateTime;
begin
  if TryLoad(TArchitectureComparer.ResolvePath(ARequest.Root, ARequest.Baseline), mPrevious, mAt) then
    TArchitectureAlignment.Align(AOverview, mPrevious, TArchitectureAnalyzer.AlignedBaseline, mAt)
  else if TryLoad(ARequest.PreviousFile, mPrevious, mAt) then
    TArchitectureAlignment.Align(AOverview, mPrevious, TArchitectureAnalyzer.AlignedLast, mAt);
end;

/// <summary>Ergebnis als zuletzt berechneten Stand ablegen (#1367).</summary>
procedure SavePrevious(const AOverview: TArchitectureOverview; const AFileName: string);
begin
  try
    TArchitectureSnapshots.Save(AFileName, TArchitectureSnapshots.FromOverview(AOverview));
  except
    // Sicherheitsnetz: Der Stand dient nur der nächsten Angleichung. Ohne ihn (Platte voll, keine Rechte) rechnet
    // der nächste Lauf wie ohne keepPrevious; die Übersicht selbst darf daran nicht scheitern.
    on EInOutError do
      ;
    on EFileStreamError do
      ;
    on EOSError do
      ;
  end;
end;

/// <summary>Zeitpunkt des gespeicherten Stands für den Schlüssel: Ein neu gespeicherter Stand gleicht neu an.
/// </summary>
function BaselineStamp(const ARequest: TArchitectureRequest): string;
var
  mFileName: string;
begin
  Result := '';
  if not ARequest.KeepPrevious then
    Exit;
  mFileName := TArchitectureComparer.ResolvePath(ARequest.Root, ARequest.Baseline);
  if (mFileName <> '') and FileExists(mFileName) then
    Result := FloatToStr(TFile.GetLastWriteTime(mFileName));
end;

{ TArchitectureRequest }

class function TArchitectureRequest.FromSettings(const ASettings: TServerSettings): TArchitectureRequest;
begin
  Result := Default(TArchitectureRequest);
  Result.Scope := ASettings.ArchitectureScope;
  Result.IncludeLibrary := ASettings.ArchitectureIncludeLibraryUnits;
  Result.CentralUnits := ASettings.ArchitectureCentralUnits;
  Result.Exclude := ASettings.ArchitectureExclude;
  Result.ExplainAssignment := ASettings.ArchitectureExplainAssignment;
  Result.KeepPrevious := ASettings.ArchitectureGroupingKeepPrevious;
  Result.Baseline := ASettings.ArchitectureBaseline;
  Result.Grouping := TArchitectureGrouping.Default;
  Result.Grouping.Resolution := ASettings.ArchitectureGroupingResolution;
  Result.Grouping.MaxShare := ASettings.ArchitectureGroupingMaxShare;
  Result.Grouping.MinCohesion := ASettings.ArchitectureGroupingMinCohesion;
  // Der Parser lässt nur group, attach und separate durch; sonst die Vorgabe.
  if not TArchitectureGrouping.TryFoundations(ASettings.ArchitectureGroupingFoundations,
    Result.Grouping.Foundations) then
    Result.Grouping.Foundations := TArchitectureFoundations.Separate;
end;

function TArchitectureRequest.Key: string;
var
  Files: TArray<string>;
begin
  Files := Copy(Self.Files);
  TArray.Sort<string>(Files);
  Result := Title + #1 + Root + #1 + Scope + #1 + BoolToStr(IncludeLibrary, True) + #1 + IntToStr(CentralUnits) + #1 +
    string.Join(#2, Exclude) + #1 + string.Join(#2, Namespaces) + #1 + LowerCase(string.Join(#2, Files)) + #1 +
    Grouping.Key + #1 + BoolToStr(KeepPrevious, True) + #1 + Baseline + #1 + PreviousFile;
end;

function TArchitectureRequest.ScopeKey: string;
begin
  Result := Scope + #1 + Root + #1 + Title;
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
  if ARequest.KeepPrevious then
  begin
    if not ARequest.Rename then
      AlignToPrevious(Result, ARequest);
    if ARequest.PreviousFile <> '' then
      SavePrevious(Result, ARequest.PreviousFile);
  end;
end;

function TArchitectureService.Overview(const ARequest: TArchitectureRequest): TArchitectureOverview;
var
  Generation: Int64;
  Key: string;
begin
  System.TMonitor.Enter(FLock);
  try
    Generation := FIndex.Generation;
    Key := ARequest.Key + #1 + BaselineStamp(ARequest);
    // Rename rechnet auf Wunsch neu, auch bei gleichem Index (#1367).
    if not FHasResult or (FGeneration <> Generation) or (FKey <> Key) or ARequest.Rename then
    begin
      FResult := Compute(ARequest, Generation);
      FGeneration := Generation;
      FKey := Key;
      FHasResult := True;
      Inc(FComputations);
    end;
    Result := FResult;
    // Nicht im Schlüssel: Ein- und Ausschalten braucht keine neue Rechnung.
    Result.ExplainAssignment := ARequest.ExplainAssignment;
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
