unit Atlas.Core.Architecture.MapState;

// Zustand der Karte im Fenster „Atlas-Architektur“ (#1118) ohne VCL: Daten,
// gewählte Unit und Unit unter dem Mauszeiger, Filter, Schalter (Namen,
// implementation-uses, Zyklen, Änderungen zum Stand, Kanten zum Fundament,
// Zuordnung), ausgeblendete Teilsysteme und der markierte Weg.
// - TAtlasArchitectureMapPath hält den Weg: kürzester Weg über uses
//   (TAtlasArchitectureModel.ShortestPath, ohne ausgeblendete Teilsysteme und
//   je nach Schalter ohne implementation-uses) oder ein fester Weg aus „Weg
//   zwischen Symbolen“ (#1117), der auch ohne implementation-uses bleibt.
// - TAtlasArchitectureMapState meldet über OnChange, wenn die Karte neu
//   gezeichnet werden muss, und über OnPathChanged, wenn sich der Weg
//   geändert hat. Ein ausgeblendetes Teilsystem oder der Schalter
//   implementation-uses lässt einen bestehenden Weg neu suchen; neue Daten
//   heben ihn auf.
// Gezeichnet wird in Atlas.UI.Architecture.Map.

interface

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Core.Architecture.Model;

type
{$SCOPEDENUMS ON}
  TAtlasArchMapFlag = (ShowNames, ShowImplementation, MarkCycles, ShowChanges, ShowFoundationEdges, ShowAssignment);
{$SCOPEDENUMS OFF}
  TAtlasArchMapFlags = set of TAtlasArchMapFlag;

  /// <summary>Markierter Weg der Karte.</summary>
  TAtlasArchitectureMapPath = class
  private
    FFrom: Integer;
    FTo: Integer;
    FFound: Boolean;
    /// <summary>Kanten des Wegs (Nummern in Model.Edges).</summary>
    FEdges: TArray<Integer>;
    /// <summary>Units eines festen Wegs (SetRoute); nil = Weg aus ShortestPath.</summary>
    FRoute: TArray<Integer>;
    FEdgeMarks: TArray<Boolean>;
    FNodeMarks: TArray<Boolean>;
  public
    constructor Create;
    /// <summary>Kein Weg.</summary>
    procedure Clear;
    /// <summary>Kürzester Weg von AFrom nach ATo (ein fester Weg wird aufgehoben).</summary>
    procedure SetEnds(AFrom, ATo: Integer);
    /// <summary>Fester Weg (#1117): AUnits in Reihenfolge, AEdges Nummern in Model.Edges.</summary>
    procedure SetRoute(const AUnits, AEdges: TArray<Integer>);
    /// <summary>Markierungen neu rechnen; ein fester Weg bleibt, sonst sucht ShortestPath.</summary>
    procedure Compute(const AModel: TAtlasArchitectureModel; AImplementation: Boolean;
      const AHidden: TArray<Boolean>);
    /// <summary>Ein Weg ist markiert; ein fester Weg kann aus einer einzigen Unit bestehen.</summary>
    function Shown: Boolean;
    function IsEdge(AEdge: Integer): Boolean;
    function IsNode(AUnit: Integer): Boolean;
    /// <summary>Start und Ziel, -1 ohne Weg.</summary>
    property From: Integer read FFrom;
    property To_: Integer read FTo;
    property Found: Boolean read FFound;
    property Edges: TArray<Integer> read FEdges;
    property Route: TArray<Integer> read FRoute;
  end;

  TAtlasArchitectureMapState = class
  private type
    /// <summary>Aus den Daten abgeleitete Markierungen.</summary>
    TMarks = record
      Central: TArray<Boolean>;
      /// <summary>Je Kante in Model.Edges: neu gegenüber dem gespeicherten Stand.</summary>
      AddedEdges: TArray<Boolean>;
    end;

    THandlers = record
      OnChange: TProc;
      OnPathChanged: TProc;
    end;
  private
    FModel: TAtlasArchitectureModel;
    FSelected: Integer;
    FHover: Integer;
    FFilter: string;
    FFlags: TAtlasArchMapFlags;
    /// <summary>Ausgeblendete Teilsysteme, je Teilsystem.</summary>
    FHidden: TArray<Boolean>;
    FMarks: TMarks;
    FCycleEdges: TDictionary<Int64, Boolean>;
    FPath: TAtlasArchitectureMapPath;
    FHandlers: THandlers;
    function GetSubsystemVisible(ASubsystem: Integer): Boolean;
    procedure SetSubsystemVisible(ASubsystem: Integer; AValue: Boolean);
    procedure SetFilter(const AValue: string);
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Neue Daten; die Auswahl bleibt, wenn die Unit noch da ist (nach Name), sonst keine. Ein Weg wird
    /// aufgehoben (OnPathChanged, wenn einer bestand), ausgeblendete Teilsysteme werden wieder sichtbar.</summary>
    procedure SetModel(const AModel: TAtlasArchitectureModel);
    /// <summary>Unit wählen; ungültige Nummern ergeben -1.</summary>
    procedure SelectUnit(AUnit: Integer);
    /// <summary>Unit unter dem Mauszeiger (-1 ohne); OnChange nur, wenn ein Hinweis zu zeigen ist.</summary>
    procedure SetHover(AUnit: Integer);
    function Has(AFlag: TAtlasArchMapFlag): Boolean;
    procedure SetFlag(AFlag: TAtlasArchMapFlag; AValue: Boolean);
    /// <summary>Kürzesten Weg über uses von AFrom nach ATo zeigen; False ohne Weg (Start und Ziel stehen
    /// trotzdem). Meldet OnPathChanged.</summary>
    function ShowPath(AFrom, ATo: Integer): Boolean;
    /// <summary>Weg aufheben; meldet OnPathChanged, wenn einer bestand.</summary>
    procedure ClearPath;
    /// <summary>Festen Weg markieren (#1117); blendet ausgeblendete Teilsysteme der Units ein.</summary>
    procedure ShowRoute(const AUnits, AEdges: TArray<Integer>);
    procedure ShowAllSubsystems;
    /// <summary>Änderungen zum Stand zeigen: Schalter an und ein Vergleich da.</summary>
    function HasChanges: Boolean;
    function UnitVisible(AUnit: Integer): Boolean;
    function EdgeVisible(const AEdge: TAtlasArchEdge): Boolean;
    /// <summary>Kante liegt auf einem Zyklus und Zyklen werden markiert.</summary>
    function MarksCycle(const AEdge: TAtlasArchEdge): Boolean;
    /// <summary>Unit tritt nicht zurück: auf dem Weg bzw. ohne Weg vom Filter getroffen (oder kein Filter).</summary>
    function Highlighted(AUnit: Integer): Boolean;
    function IsCentral(AUnit: Integer): Boolean;
    function IsAdded(AEdge: Integer): Boolean;
    property Model: TAtlasArchitectureModel read FModel;
    property Selected: Integer read FSelected;
    property Hover: Integer read FHover;
    /// <summary>Units, deren Name nicht passt (TAtlasArchitectureModel.Matches), treten zurück.</summary>
    property Filter: string read FFilter write SetFilter;
    property SubsystemVisible[ASubsystem: Integer]: Boolean read GetSubsystemVisible write SetSubsystemVisible;
    property Path: TAtlasArchitectureMapPath read FPath;
    /// <summary>Ausgeblendete Teilsysteme, je Teilsystem (für TAtlasArchitectureView.UnitAt).</summary>
    property Hidden: TArray<Boolean> read FHidden;
    /// <summary>Die Karte muss neu gezeichnet werden.</summary>
    property OnChange: TProc read FHandlers.OnChange write FHandlers.OnChange;
    property OnPathChanged: TProc read FHandlers.OnPathChanged write FHandlers.OnPathChanged;
  end;

implementation

function EdgeKey(ASource, ATarget: Integer): Int64;
begin
  Result := Int64(ASource) shl 32 or Cardinal(ATarget);
end;

procedure Changed(AState: TAtlasArchitectureMapState);
begin
  if Assigned(AState.FHandlers.OnChange) then
  begin
    AState.FHandlers.OnChange();
  end;
end;

procedure PathChanged(AState: TAtlasArchitectureMapState);
begin
  if Assigned(AState.FHandlers.OnPathChanged) then
  begin
    AState.FHandlers.OnPathChanged();
  end;
end;

/// <summary>Ein bestehender Weg wird neu gesucht (ausgeblendetes Teilsystem, implementation-uses).</summary>
procedure RecomputePath(AState: TAtlasArchitectureMapState);
begin
  if AState.FPath.From < 0 then
  begin
    Exit;
  end;
  AState.FPath.Compute(AState.FModel, AState.Has(TAtlasArchMapFlag.ShowImplementation), AState.FHidden);
  PathChanged(AState);
end;

function ValidUnit(const AModel: TAtlasArchitectureModel; AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit <= High(AModel.Units));
end;

/// <summary>Alle Units und Kanten des festen Wegs gibt es in AModel, und es ist mindestens eine Unit.</summary>
function ValidRoute(const AModel: TAtlasArchitectureModel; const AUnits, AEdges: TArray<Integer>): Boolean;
var
  mUnit, mEdge: Integer;
begin
  Result := False;
  for mUnit in AUnits do
  begin
    if not ValidUnit(AModel, mUnit) then
    begin
      Exit;
    end;
  end;
  for mEdge in AEdges do
  begin
    if (mEdge < 0) or (mEdge > High(AModel.Edges)) then
    begin
      Exit;
    end;
  end;
  Result := Length(AUnits) > 0;
end;

{ TAtlasArchitectureMapPath }

constructor TAtlasArchitectureMapPath.Create;
begin
  inherited Create;
  Clear;
end;

procedure TAtlasArchitectureMapPath.Clear;
begin
  FFrom := -1;
  FTo := -1;
  FFound := False;
  FEdges := nil;
  FRoute := nil;
  FEdgeMarks := nil;
  FNodeMarks := nil;
end;

procedure TAtlasArchitectureMapPath.SetEnds(AFrom, ATo: Integer);
begin
  FFrom := AFrom;
  FTo := ATo;
  FRoute := nil;
end;

procedure TAtlasArchitectureMapPath.SetRoute(const AUnits, AEdges: TArray<Integer>);
begin
  FRoute := AUnits;
  FEdges := AEdges;
  FFrom := AUnits[0];
  FTo := AUnits[High(AUnits)];
end;

procedure TAtlasArchitectureMapPath.Compute(const AModel: TAtlasArchitectureModel; AImplementation: Boolean;
  const AHidden: TArray<Boolean>);
var
  mEdge, mUnit: Integer;
begin
  FEdgeMarks := nil;
  FNodeMarks := nil;
  if Length(FRoute) > 0 then
  begin
    // Fester Weg (#1117): bleibt, auch wenn implementation-uses aus sind.
    FFound := True;
  end
  else
  begin
    FFound := AModel.ShortestPath(FFrom, FTo, AImplementation, AHidden, FEdges);
  end;
  if not FFound then
  begin
    Exit;
  end;
  SetLength(FEdgeMarks, Length(AModel.Edges));
  SetLength(FNodeMarks, Length(AModel.Units));
  if Length(FRoute) = 0 then
  begin
    FNodeMarks[FFrom] := True;
  end;
  for mUnit in FRoute do
  begin
    FNodeMarks[mUnit] := True;
  end;
  for mEdge in FEdges do
  begin
    FEdgeMarks[mEdge] := True;
    if Length(FRoute) = 0 then
    begin
      FNodeMarks[AModel.Edges[mEdge].Target] := True;
    end;
  end;
end;

function TAtlasArchitectureMapPath.Shown: Boolean;
begin
  Result := FFound and ((Length(FEdges) > 0) or (Length(FRoute) > 0));
end;

function TAtlasArchitectureMapPath.IsEdge(AEdge: Integer): Boolean;
begin
  Result := (AEdge >= 0) and (AEdge < Length(FEdgeMarks)) and FEdgeMarks[AEdge];
end;

function TAtlasArchitectureMapPath.IsNode(AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(FNodeMarks)) and FNodeMarks[AUnit];
end;

{ TAtlasArchitectureMapState }

constructor TAtlasArchitectureMapState.Create;
begin
  inherited Create;
  FSelected := -1;
  FHover := -1;
  FFlags := [TAtlasArchMapFlag.ShowNames, TAtlasArchMapFlag.ShowImplementation, TAtlasArchMapFlag.ShowChanges,
    TAtlasArchMapFlag.ShowFoundationEdges, TAtlasArchMapFlag.ShowAssignment];
  FCycleEdges := TDictionary<Int64, Boolean>.Create;
  FPath := TAtlasArchitectureMapPath.Create;
end;

destructor TAtlasArchitectureMapState.Destroy;
begin
  FPath.Free;
  FCycleEdges.Free;
  inherited Destroy;
end;

/// <summary>Zentrale Units, Kanten der Zyklen und neue Kanten des Vergleichs aus den Daten.</summary>
procedure ReadMarks(AState: TAtlasArchitectureMapState);
var
  mMember: Integer;
  mCycle: TAtlasArchCycle;
  mLink: TAtlasArchLink;
begin
  AState.FMarks := Default(TAtlasArchitectureMapState.TMarks);
  SetLength(AState.FMarks.Central, Length(AState.FModel.Units));
  for mMember in AState.FModel.Central do
  begin
    AState.FMarks.Central[mMember] := True;
  end;
  AState.FCycleEdges.Clear;
  for mCycle in AState.FModel.Cycles do
  begin
    for mLink in mCycle.Edges do
    begin
      AState.FCycleEdges.AddOrSetValue(EdgeKey(mLink.Source, mLink.Target), True);
    end;
  end;
  SetLength(AState.FMarks.AddedEdges, Length(AState.FModel.Edges));
  for mMember in AState.FModel.Comparison.AddedEdges do
  begin
    if (mMember >= 0) and (mMember <= High(AState.FMarks.AddedEdges)) then
    begin
      AState.FMarks.AddedEdges[mMember] := True;
    end;
  end;
end;

procedure TAtlasArchitectureMapState.SetModel(const AModel: TAtlasArchitectureModel);
var
  mSelectedName: string;
  mHadPath: Boolean;
begin
  mSelectedName := '';
  if ValidUnit(FModel, FSelected) then
  begin
    mSelectedName := FModel.Units[FSelected].Name;
  end;
  mHadPath := FPath.From >= 0;
  FModel := AModel;
  ReadMarks(Self);
  FHidden := nil;
  SetLength(FHidden, Length(FModel.Subsystems));
  FPath.Clear;
  FSelected := -1;
  FHover := -1;
  if mSelectedName <> '' then
  begin
    FSelected := FModel.IndexOf(mSelectedName);
  end;
  if mHadPath then
  begin
    PathChanged(Self);
  end;
  Changed(Self);
end;

procedure TAtlasArchitectureMapState.SelectUnit(AUnit: Integer);
begin
  if not ValidUnit(FModel, AUnit) then
  begin
    AUnit := -1;
  end;
  FSelected := AUnit;
  Changed(Self);
end;

procedure TAtlasArchitectureMapState.SetHover(AUnit: Integer);
begin
  if AUnit = FHover then
  begin
    Exit;
  end;
  FHover := AUnit;
  if Has(TAtlasArchMapFlag.ShowAssignment) and FModel.HasAssignment then
  begin
    Changed(Self);
  end;
end;

function TAtlasArchitectureMapState.Has(AFlag: TAtlasArchMapFlag): Boolean;
begin
  Result := AFlag in FFlags;
end;

procedure TAtlasArchitectureMapState.SetFlag(AFlag: TAtlasArchMapFlag; AValue: Boolean);
begin
  if Has(AFlag) = AValue then
  begin
    Exit;
  end;
  if AValue then
  begin
    Include(FFlags, AFlag);
  end
  else
  begin
    Exclude(FFlags, AFlag);
  end;
  // Der Weg hängt davon ab, ob implementation-uses zählen.
  if AFlag = TAtlasArchMapFlag.ShowImplementation then
  begin
    RecomputePath(Self);
  end;
  Changed(Self);
end;

procedure TAtlasArchitectureMapState.SetFilter(const AValue: string);
begin
  if FFilter = AValue then
  begin
    Exit;
  end;
  FFilter := AValue;
  Changed(Self);
end;

function TAtlasArchitectureMapState.GetSubsystemVisible(ASubsystem: Integer): Boolean;
begin
  Result := not ((ASubsystem >= 0) and (ASubsystem < Length(FHidden)) and FHidden[ASubsystem]);
end;

procedure TAtlasArchitectureMapState.SetSubsystemVisible(ASubsystem: Integer; AValue: Boolean);
begin
  if (ASubsystem < 0) or (ASubsystem >= Length(FHidden)) or (FHidden[ASubsystem] = not AValue) then
  begin
    Exit;
  end;
  FHidden[ASubsystem] := not AValue;
  if FModel.IsHidden(FSelected, FHidden) then
  begin
    FSelected := -1;
  end;
  // Wie die HTML-Karte: Ein bestehender Weg wird ohne das Teilsystem neu gesucht.
  RecomputePath(Self);
  Changed(Self);
end;

procedure TAtlasArchitectureMapState.ShowAllSubsystems;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FHidden) do
  begin
    SetSubsystemVisible(mIndex, True);
  end;
end;

function TAtlasArchitectureMapState.ShowPath(AFrom, ATo: Integer): Boolean;
begin
  if not ValidUnit(FModel, AFrom) or not ValidUnit(FModel, ATo) then
  begin
    ClearPath;
    Exit(False);
  end;
  FPath.SetEnds(AFrom, ATo);
  FPath.Compute(FModel, Has(TAtlasArchMapFlag.ShowImplementation), FHidden);
  Result := FPath.Found;
  Changed(Self);
  PathChanged(Self);
end;

procedure TAtlasArchitectureMapState.ShowRoute(const AUnits, AEdges: TArray<Integer>);
var
  mUnit: Integer;
begin
  if not ValidRoute(FModel, AUnits, AEdges) then
  begin
    ClearPath;
    Exit;
  end;
  // Ein Teilsystem des Wegs ausgeblendet: wieder einblenden, sonst wäre der Weg lückenhaft.
  for mUnit in AUnits do
  begin
    if FModel.IsHidden(mUnit, FHidden) then
    begin
      FHidden[FModel.Units[mUnit].Subsystem] := False;
    end;
  end;
  FPath.SetRoute(AUnits, AEdges);
  FPath.Compute(FModel, Has(TAtlasArchMapFlag.ShowImplementation), FHidden);
  Changed(Self);
  PathChanged(Self);
end;

procedure TAtlasArchitectureMapState.ClearPath;
begin
  if FPath.From < 0 then
  begin
    Exit;
  end;
  FPath.Clear;
  Changed(Self);
  PathChanged(Self);
end;

function TAtlasArchitectureMapState.HasChanges: Boolean;
begin
  Result := Has(TAtlasArchMapFlag.ShowChanges) and FModel.Comparison.Present;
end;

function TAtlasArchitectureMapState.UnitVisible(AUnit: Integer): Boolean;
begin
  Result := not FModel.IsHidden(AUnit, FHidden);
end;

function TAtlasArchitectureMapState.EdgeVisible(const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := UnitVisible(AEdge.Source) and UnitVisible(AEdge.Target);
end;

function TAtlasArchitectureMapState.MarksCycle(const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := Has(TAtlasArchMapFlag.MarkCycles) and FCycleEdges.ContainsKey(EdgeKey(AEdge.Source, AEdge.Target));
end;

function TAtlasArchitectureMapState.Highlighted(AUnit: Integer): Boolean;
begin
  if FPath.Shown then
  begin
    Result := FPath.IsNode(AUnit);
  end
  else
  begin
    Result := (Trim(FFilter) = '') or FModel.Matches(AUnit, FFilter);
  end;
end;

function TAtlasArchitectureMapState.IsCentral(AUnit: Integer): Boolean;
begin
  Result := (AUnit >= 0) and (AUnit < Length(FMarks.Central)) and FMarks.Central[AUnit];
end;

function TAtlasArchitectureMapState.IsAdded(AEdge: Integer): Boolean;
begin
  Result := (AEdge >= 0) and (AEdge < Length(FMarks.AddedEdges)) and FMarks.AddedEdges[AEdge];
end;

end.
