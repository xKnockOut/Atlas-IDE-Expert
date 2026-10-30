unit Atlas.UI.Architecture.Map;

// Karte des Fensters „Atlas-Architektur“ (#1118), reine VCL: Teilsysteme als
// Kreise mit Namen, Units als Punkte in der Farbe ihres Teilsystems (Größe
// nach „gesamt abhängig“), uses-Kanten als Linien (implementation
// gestrichelt), Ausreißer mit Ring in Warnfarbe. Lage aus den Daten des
// Servers (TArchitectureLayouter), Farben aus dem IDE-Thema (TAtlasColors) und
// der Palette der HTML-Karte. Wie in der HTML-Karte:
// - „Zyklen markieren“ (MarkCycles) zeichnet Kanten und Units der Zyklen in
//   Fehlerfarbe,
// - Teilsysteme lassen sich aus- und einblenden (SubsystemVisible), ihre
//   Units und Kanten verschwinden dann,
// - implementation-uses ein und aus (ShowImplementation), Namen ein und aus,
// - Umschalt+Klick zeigt den kürzesten Weg über uses von der gewählten Unit
//   zur angeklickten (ShowPath, TAtlasArchitectureModel.ShortestPath), alles
//   andere tritt zurück; Esc hebt ihn auf (OnPathChanged),
// - „Änderungen zum Stand“ (ShowChanges, #1121): Mit einem Vergleich stehen
//   neue uses-Kanten grün, entfernte (zwischen Units, die es noch gibt) rot
//   gestrichelt.
// - ShowRoute markiert einen festen Weg aus „Weg zwischen Symbolen“ (#1117)
//   ebenso; er bleibt, bis Esc, ein Umschalt+Klick oder neue Daten ihn
//   aufheben.
// - Hinweis (#1368): Über einer Unit steht ihre Zuordnung (Kanten je
//   Teilsystem, TAtlasArchitectureAssignment), wenn der Server sie mitschickt
//   (architecture.explainAssignment) und ShowAssignment an ist.
// Bedienung sonst: Mausrad zoomt um den Mauszeiger, Ziehen verschiebt, Klick
// wählt eine Unit (OnSelect; ihre Kanten werden hervorgehoben), Doppelklick
// oder Enter öffnet sie (OnOpen), + und − zoomen, 0 passt ein. Namen
// erscheinen erst ab einer lesbaren Größe, zentrale, gewählte, gefilterte und
// die des Wegs immer. Umrechnung und Treffer: TAtlasArchitectureView
// (getestet im Kern).

interface

uses
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Palette,
  Atlas.Core.Architecture.Model;

type
  TAtlasArchitectureMap = class(TCustomControl)
  private
    FModel: TAtlasArchitectureModel;
    FView: TAtlasArchitectureView;
    FFitted: Boolean;
    FSelected: Integer;
    FFilter: string;
    FShowNames: Boolean;
    FShowImplementation: Boolean;
    FMarkCycles: Boolean;
    FShowChanges: Boolean;
    FShowFoundationEdges: Boolean;
    /// <summary>Je Kante in Model.Edges: neu gegenüber dem gespeicherten Stand.</summary>
    FAddedEdges: TArray<Boolean>;
    FCentral: TArray<Boolean>;
    FCycleEdges: TDictionary<Int64, Boolean>;
    /// <summary>Ausgeblendete Teilsysteme, je Teilsystem.</summary>
    FHidden: TArray<Boolean>;
    FPathFrom: Integer;
    FPathTo: Integer;
    FPathFound: Boolean;
    /// <summary>Kanten des Wegs (Nummern in Model.Edges).</summary>
    FPath: TArray<Integer>;
    FPathEdges: TArray<Boolean>;
    FPathNodes: TArray<Boolean>;
    /// <summary>Units eines festen Wegs (ShowRoute); nil = Weg aus ShortestPath.</summary>
    FRoute: TArray<Integer>;
    /// <summary>Unit unter dem Mauszeiger (Hinweis mit Zuordnung, #1368); -1 ohne.</summary>
    FHover: Integer;
    FShowAssignment: Boolean;
    FDragging: Boolean;
    FMoved: Boolean;
    FDragX: Integer;
    FDragY: Integer;
    FOnSelect: TProc<Integer>;
    FOnOpen: TProc<Integer>;
    FOnPathChanged: TProc;
    function EdgeKey(ASource, ATarget: Integer): Int64;
    function Px(AValue: Double): Integer;
    function HasPath: Boolean;
    function UnitVisible(AUnit: Integer): Boolean;
    function EdgeVisible(const AEdge: TAtlasArchEdge): Boolean;
    function GetSubsystemVisible(ASubsystem: Integer): Boolean;
    procedure SetSubsystemVisible(ASubsystem: Integer; AValue: Boolean);
    procedure SetFilter(const AValue: string);
    procedure SetShowNames(AValue: Boolean);
    procedure SetShowImplementation(AValue: Boolean);
    procedure SetMarkCycles(AValue: Boolean);
    procedure SetShowChanges(AValue: Boolean);
    procedure SetShowFoundationEdges(AValue: Boolean);
    function HasChanges: Boolean;
    procedure ComputePath;
    procedure PathChanged;
    procedure DrawEdge(const AEdge: TAtlasArchEdge);
    procedure PaintNames(const AColors: TAtlasColors; APathing, AFiltered: Boolean);
    procedure PaintHover(const AColors: TAtlasColors);
    procedure SetHover(AUnit: Integer);
    procedure SetShowAssignment(AValue: Boolean);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neue Daten; die Auswahl bleibt, wenn die Unit noch da ist (nach Name), sonst keine. Ein Weg
    /// wird aufgehoben, ausgeblendete Teilsysteme werden wieder sichtbar.</summary>
    procedure SetModel(const AModel: TAtlasArchitectureModel);
    /// <summary>Alle Teilsysteme einpassen.</summary>
    procedure FitView;
    procedure ZoomBy(AFactor: Double);
    /// <summary>Unit wählen (-1 = keine); ACenter verschiebt die Karte zu ihr.</summary>
    procedure SelectUnit(AUnit: Integer; ACenter: Boolean);
    /// <summary>Kürzesten Weg über uses von AFrom nach ATo zeigen; False ohne Weg (PathFrom und PathTo
    /// stehen trotzdem, PathFound ist False). Meldet OnPathChanged.</summary>
    function ShowPath(AFrom, ATo: Integer): Boolean;
    /// <summary>Weg aufheben; meldet OnPathChanged, wenn einer bestand.</summary>
    procedure ClearPath;
    /// <summary>Festen Weg markieren (#1117): AUnits in Reihenfolge, AEdges Nummern in Model.Edges (aus
    /// TAtlasArchitectureModel.RouteOf). Blendet ausgeblendete Teilsysteme der Units ein und meldet
    /// OnPathChanged.</summary>
    procedure ShowRoute(const AUnits, AEdges: TArray<Integer>);
    /// <summary>Alle Teilsysteme wieder einblenden.</summary>
    procedure ShowAllSubsystems;
    property Model: TAtlasArchitectureModel read FModel;
    property View: TAtlasArchitectureView read FView;
    property Selected: Integer read FSelected;
    /// <summary>Units, deren Name nicht passt (TAtlasArchitectureModel.Matches), treten zurück.</summary>
    property Filter: string read FFilter write SetFilter;
    property ShowNames: Boolean read FShowNames write SetShowNames;
    property ShowImplementation: Boolean read FShowImplementation write SetShowImplementation;
    property MarkCycles: Boolean read FMarkCycles write SetMarkCycles;
    /// <summary>Geänderte Kanten des Vergleichs zeigen (wirkt nur mit Model.Comparison.Present).</summary>
    property ShowChanges: Boolean read FShowChanges write SetShowChanges;
    /// <summary>Kanten zum Teilsystem „Fundament“ (#1365) blass zeigen; aus = ausgeblendet.</summary>
    property ShowFoundationEdges: Boolean read FShowFoundationEdges write SetShowFoundationEdges;
    /// <summary>Hinweis mit der Zuordnung der Unit unter dem Mauszeiger (#1368).</summary>
    property ShowAssignment: Boolean read FShowAssignment write SetShowAssignment;
    /// <summary>Unit unter dem Mauszeiger, -1 ohne.</summary>
    property Hover: Integer read FHover;
    property SubsystemVisible[ASubsystem: Integer]: Boolean read GetSubsystemVisible write SetSubsystemVisible;
    /// <summary>Start und Ziel des Wegs, -1 ohne Weg.</summary>
    property PathFrom: Integer read FPathFrom;
    property PathTo: Integer read FPathTo;
    property PathFound: Boolean read FPathFound;
    property Path: TArray<Integer> read FPath;
    /// <summary>Units eines festen Wegs aus ShowRoute, nil sonst.</summary>
    property Route: TArray<Integer> read FRoute;
    property OnSelect: TProc<Integer> read FOnSelect write FOnSelect;
    property OnOpen: TProc<Integer> read FOnOpen write FOnOpen;
    property OnPathChanged: TProc read FOnPathChanged write FOnPathChanged;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.UI.Architecture.Assignment;

const
  /// <summary>Ab dieser Vergrößerung stehen alle Namen da (darunter überdecken sie sich).</summary>
  AllNamesScale = 0.9;
  /// <summary>Bildpunkte, ab denen ein Mausdruck als Ziehen gilt.</summary>
  DragThreshold = 3;
  /// <summary>Anteil der eigenen Farbe bei Units, die hinter einem Weg oder Filter zurücktreten.</summary>
  DimAlpha = 0.3;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasArchitectureMap }

constructor TAtlasArchitectureMap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  FSelected := -1;
  FHover := -1;
  FShowAssignment := True;
  FPathFrom := -1;
  FPathTo := -1;
  FShowNames := True;
  FShowImplementation := True;
  FShowFoundationEdges := True;
  FShowChanges := True;
  FView := Default(TAtlasArchitectureView);
  FView.Scale := 1;
  FCycleEdges := TDictionary<Int64, Boolean>.Create;
end;

destructor TAtlasArchitectureMap.Destroy;
begin
  FCycleEdges.Free;
  inherited Destroy;
end;

function TAtlasArchitectureMap.EdgeKey(ASource, ATarget: Integer): Int64;
begin
  Result := Int64(ASource) shl 32 or Cardinal(ATarget);
end;

function TAtlasArchitectureMap.Px(AValue: Double): Integer;
begin
  Result := Round(AValue);
end;

function TAtlasArchitectureMap.HasPath: Boolean;
begin
  // Ein fester Weg (#1117) kann aus einer einzigen Unit bestehen.
  Result := FPathFound and ((Length(FPath) > 0) or (Length(FRoute) > 0));
end;

function TAtlasArchitectureMap.UnitVisible(AUnit: Integer): Boolean;
begin
  Result := not FModel.IsHidden(AUnit, FHidden);
end;

function TAtlasArchitectureMap.EdgeVisible(const AEdge: TAtlasArchEdge): Boolean;
begin
  Result := UnitVisible(AEdge.Source) and UnitVisible(AEdge.Target);
end;

function TAtlasArchitectureMap.GetSubsystemVisible(ASubsystem: Integer): Boolean;
begin
  Result := not ((ASubsystem >= 0) and (ASubsystem < Length(FHidden)) and FHidden[ASubsystem]);
end;

procedure TAtlasArchitectureMap.SetSubsystemVisible(ASubsystem: Integer; AValue: Boolean);
begin
  if (ASubsystem < 0) or (ASubsystem >= Length(FHidden)) or (FHidden[ASubsystem] = not AValue) then
    Exit;
  FHidden[ASubsystem] := not AValue;
  if FModel.IsHidden(FSelected, FHidden) then
    FSelected := -1;
  // Wie die HTML-Karte: Ein bestehender Weg wird ohne das Teilsystem neu gesucht.
  if FPathFrom >= 0 then
  begin
    ComputePath;
    PathChanged;
  end;
  Invalidate;
end;

procedure TAtlasArchitectureMap.ShowAllSubsystems;
var
  Index: Integer;
begin
  for Index := 0 to High(FHidden) do
    SetSubsystemVisible(Index, True);
end;

procedure TAtlasArchitectureMap.SetModel(const AModel: TAtlasArchitectureModel);
var
  SelectedName: string;
  Member: Integer;
  Cycle: TAtlasArchCycle;
  Link: TAtlasArchLink;
  HadPath: Boolean;
begin
  SelectedName := '';
  if (FSelected >= 0) and (FSelected <= High(FModel.Units)) then
    SelectedName := FModel.Units[FSelected].Name;
  HadPath := FPathFrom >= 0;
  FModel := AModel;
  FCentral := nil;
  SetLength(FCentral, Length(FModel.Units));
  for Member in FModel.Central do
    FCentral[Member] := True;
  FCycleEdges.Clear;
  for Cycle in FModel.Cycles do
    for Link in Cycle.Edges do
      FCycleEdges.AddOrSetValue(EdgeKey(Link.Source, Link.Target), True);
  FAddedEdges := nil;
  SetLength(FAddedEdges, Length(FModel.Edges));
  for Member in FModel.Comparison.AddedEdges do
    if (Member >= 0) and (Member <= High(FAddedEdges)) then
      FAddedEdges[Member] := True;
  FHidden := nil;
  SetLength(FHidden, Length(FModel.Subsystems));
  FPathFrom := -1;
  FPathTo := -1;
  FPathFound := False;
  FPath := nil;
  FPathEdges := nil;
  FPathNodes := nil;
  FRoute := nil;
  FSelected := -1;
  FHover := -1;
  if SelectedName <> '' then
    FSelected := FModel.IndexOf(SelectedName);
  FFitted := False;
  if (ClientWidth > 0) and (ClientHeight > 0) then
    FitView;
  if HadPath then
    PathChanged;
  Invalidate;
end;

procedure TAtlasArchitectureMap.FitView;
begin
  FView.Fit(FModel, ClientWidth, ClientHeight);
  FFitted := Length(FModel.Subsystems) > 0;
  Invalidate;
end;

procedure TAtlasArchitectureMap.ZoomBy(AFactor: Double);
begin
  FView.ZoomAt(AFactor, ClientWidth / 2, ClientHeight / 2);
  Invalidate;
end;

procedure TAtlasArchitectureMap.SelectUnit(AUnit: Integer; ACenter: Boolean);
begin
  if (AUnit < 0) or (AUnit > High(FModel.Units)) then
    AUnit := -1;
  FSelected := AUnit;
  if ACenter and (AUnit >= 0) then
    FView.Pan(ClientWidth / 2 - FView.ScreenX(FModel.Units[AUnit].X),
      ClientHeight / 2 - FView.ScreenY(FModel.Units[AUnit].Y));
  Invalidate;
end;

procedure TAtlasArchitectureMap.ComputePath;
var
  Edge, Unit_: Integer;
begin
  FPathEdges := nil;
  FPathNodes := nil;
  if Length(FRoute) > 0 then
  begin
    // Fester Weg (#1117): bleibt, auch wenn implementation-uses aus sind.
    FPathFound := True;
    SetLength(FPathEdges, Length(FModel.Edges));
    SetLength(FPathNodes, Length(FModel.Units));
    for Unit_ in FRoute do
      FPathNodes[Unit_] := True;
    for Edge in FPath do
      FPathEdges[Edge] := True;
    Exit;
  end;
  FPathFound := FModel.ShortestPath(FPathFrom, FPathTo, FShowImplementation, FHidden, FPath);
  if not FPathFound then
    Exit;
  SetLength(FPathEdges, Length(FModel.Edges));
  SetLength(FPathNodes, Length(FModel.Units));
  FPathNodes[FPathFrom] := True;
  for Edge in FPath do
  begin
    FPathEdges[Edge] := True;
    FPathNodes[FModel.Edges[Edge].Target] := True;
  end;
end;

procedure TAtlasArchitectureMap.PathChanged;
begin
  if Assigned(FOnPathChanged) then
    FOnPathChanged();
end;

function TAtlasArchitectureMap.ShowPath(AFrom, ATo: Integer): Boolean;
begin
  if (AFrom < 0) or (AFrom > High(FModel.Units)) or (ATo < 0) or (ATo > High(FModel.Units)) then
  begin
    ClearPath;
    Exit(False);
  end;
  FPathFrom := AFrom;
  FPathTo := ATo;
  FRoute := nil;
  ComputePath;
  Result := FPathFound;
  Invalidate;
  PathChanged;
end;

procedure TAtlasArchitectureMap.ShowRoute(const AUnits, AEdges: TArray<Integer>);
var
  Unit_, Edge: Integer;
begin
  for Unit_ in AUnits do
    if (Unit_ < 0) or (Unit_ > High(FModel.Units)) then
    begin
      ClearPath;
      Exit;
    end;
  for Edge in AEdges do
    if (Edge < 0) or (Edge > High(FModel.Edges)) then
    begin
      ClearPath;
      Exit;
    end;
  if Length(AUnits) = 0 then
  begin
    ClearPath;
    Exit;
  end;
  // Ein Teilsystem des Wegs ausgeblendet: wieder einblenden, sonst wäre der Weg lückenhaft.
  for Unit_ in AUnits do
    if FModel.IsHidden(Unit_, FHidden) then
      FHidden[FModel.Units[Unit_].Subsystem] := False;
  FRoute := AUnits;
  FPath := AEdges;
  FPathFrom := AUnits[0];
  FPathTo := AUnits[High(AUnits)];
  ComputePath;
  Invalidate;
  PathChanged;
end;

procedure TAtlasArchitectureMap.ClearPath;
begin
  if FPathFrom < 0 then
    Exit;
  FPathFrom := -1;
  FPathTo := -1;
  FPathFound := False;
  FPath := nil;
  FPathEdges := nil;
  FPathNodes := nil;
  FRoute := nil;
  Invalidate;
  PathChanged;
end;

procedure TAtlasArchitectureMap.SetFilter(const AValue: string);
begin
  if FFilter = AValue then
    Exit;
  FFilter := AValue;
  Invalidate;
end;

procedure TAtlasArchitectureMap.SetShowNames(AValue: Boolean);
begin
  FShowNames := AValue;
  Invalidate;
end;

procedure TAtlasArchitectureMap.SetShowImplementation(AValue: Boolean);
begin
  if FShowImplementation = AValue then
    Exit;
  FShowImplementation := AValue;
  // Der Weg hängt davon ab, ob implementation-uses zählen.
  if FPathFrom >= 0 then
  begin
    ComputePath;
    PathChanged;
  end;
  Invalidate;
end;

procedure TAtlasArchitectureMap.SetMarkCycles(AValue: Boolean);
begin
  FMarkCycles := AValue;
  Invalidate;
end;

procedure TAtlasArchitectureMap.SetShowFoundationEdges(AValue: Boolean);
begin
  FShowFoundationEdges := AValue;
  Invalidate;
end;

procedure TAtlasArchitectureMap.SetShowChanges(AValue: Boolean);
begin
  FShowChanges := AValue;
  Invalidate;
end;

function TAtlasArchitectureMap.HasChanges: Boolean;
begin
  Result := FShowChanges and FModel.Comparison.Present;
end;

procedure TAtlasArchitectureMap.Resize;
begin
  inherited Resize;
  if not FFitted and (ClientWidth > 0) and (ClientHeight > 0) then
    FitView;
end;

procedure TAtlasArchitectureMap.DrawEdge(const AEdge: TAtlasArchEdge);
begin
  Canvas.MoveTo(Px(FView.ScreenX(FModel.Units[AEdge.Source].X)), Px(FView.ScreenY(FModel.Units[AEdge.Source].Y)));
  Canvas.LineTo(Px(FView.ScreenX(FModel.Units[AEdge.Target].X)), Px(FView.ScreenY(FModel.Units[AEdge.Target].Y)));
end;

procedure TAtlasArchitectureMap.Paint;
var
  Colors: TAtlasColors;
  Dark, Touches, OnCycle, Visible, Pathing, Changes, Added: Boolean;
  Index: Integer;
  Subsystem: TAtlasArchSubsystem;
  Edge: TAtlasArchEdge;
  Item: TAtlasArchUnit;
  X, Y, Radius: Integer;
  Caption: string;
  TextSize: TSize;
  Filtered: Boolean;
  Fill: TAtlasColor;
begin
  Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Dark := Colors.IsDark;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Canvas.Font.Color := ToColor(Colors.Text);
  Filtered := Trim(FFilter) <> '';
  Pathing := HasPath;
  Changes := HasChanges and not Pathing;
  // Teilsysteme: gestrichelter Kreis in ihrer Farbe, Name oben.
  for Index := 0 to High(FModel.Subsystems) do
  begin
    if not GetSubsystemVisible(Index) then
      Continue;
    Subsystem := FModel.Subsystems[Index];
    X := Px(FView.ScreenX(Subsystem.X));
    Y := Px(FView.ScreenY(Subsystem.Y));
    Radius := Max(2, Px(Subsystem.R * FView.Scale));
    // Das Fundament (#1365) deutlicher gestrichelt.
    if Subsystem.Foundation then
    begin
      Canvas.Pen.Style := psDash;
      Canvas.Pen.Width := 2;
    end
    else
    begin
      Canvas.Pen.Style := psDot;
      Canvas.Pen.Width := 1;
    end;
    Canvas.Pen.Color := TColor(FModel.SubsystemColor(Index, Dark));
    Canvas.Brush.Style := bsClear;
    Canvas.Ellipse(X - Radius, Y - Radius, X + Radius + 1, Y + Radius + 1);
    Caption := Subsystem.Name;
    TextSize := Canvas.TextExtent(Caption);
    Canvas.Font.Color := TColor(FModel.SubsystemColor(Index, Dark));
    Canvas.Font.Style := [fsBold];
    Canvas.TextOut(X - TextSize.cx div 2, Y - Radius - TextSize.cy - 2, Caption);
    Canvas.Font.Style := [];
  end;
  // Kanten: zuerst die gewöhnlichen, darüber Zyklen, die Kanten der gewählten Unit und der Weg.
  for Index := 0 to High(FModel.Edges) do
  begin
    Edge := FModel.Edges[Index];
    if not EdgeVisible(Edge) or (not Edge.Interface_ and not FShowImplementation) then
      Continue;
    OnCycle := FMarkCycles and FCycleEdges.ContainsKey(EdgeKey(Edge.Source, Edge.Target));
    Touches := not Pathing and (FSelected >= 0) and ((Edge.Source = FSelected) or (Edge.Target = FSelected));
    Added := Changes and FAddedEdges[Index];
    if OnCycle or Touches or Added or (Pathing and FPathEdges[Index]) then
      Continue;
    Canvas.Pen.Width := 1;
    // Kanten zum Fundament (#1365) blass und gepunktet, abschaltbar.
    if FModel.TouchesFoundation(Edge) then
    begin
      if not FShowFoundationEdges then
        Continue;
      Canvas.Pen.Style := psDot;
      Canvas.Pen.Color := ToColor(TAtlasColorMath.Mix(Colors.Line, Colors.Surface, 0.4));
    end
    else
    begin
      if Edge.Interface_ then
        Canvas.Pen.Style := psSolid
      else
        Canvas.Pen.Style := psDot;
      Canvas.Pen.Color := ToColor(Colors.Line);
    end;
    DrawEdge(Edge);
  end;
  for Index := 0 to High(FModel.Edges) do
  begin
    Edge := FModel.Edges[Index];
    if not EdgeVisible(Edge) or (not Edge.Interface_ and not FShowImplementation) then
      Continue;
    OnCycle := FMarkCycles and FCycleEdges.ContainsKey(EdgeKey(Edge.Source, Edge.Target));
    Touches := not Pathing and (FSelected >= 0) and ((Edge.Source = FSelected) or (Edge.Target = FSelected));
    Added := Changes and FAddedEdges[Index];
    if not (OnCycle or Touches or Added) or (Pathing and FPathEdges[Index]) then
      Continue;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 2;
    // Wie die HTML-Karte: Zyklus vor gewählt vor neu.
    if OnCycle then
      Canvas.Pen.Color := ToColor(Colors.Error)
    else if Touches then
      Canvas.Pen.Color := ToColor(Colors.Accent)
    else
      Canvas.Pen.Color := ToColor(Colors.Add);
    DrawEdge(Edge);
  end;
  // Entfernte Kanten gibt es in Edges nicht mehr: rot gestrichelt zwischen den Units, die noch da sind.
  if Changes then
    for Edge in FModel.Comparison.DroppedEdges do
    begin
      if not EdgeVisible(Edge) or (not Edge.Interface_ and not FShowImplementation) then
        Continue;
      Canvas.Pen.Style := psDash;
      Canvas.Pen.Width := 1;
      Canvas.Pen.Color := ToColor(Colors.Error);
      DrawEdge(Edge);
    end;
  if Pathing then
    for Index in FPath do
    begin
      Edge := FModel.Edges[Index];
      if Edge.Interface_ then
        Canvas.Pen.Style := psSolid
      else
        Canvas.Pen.Style := psDash;
      Canvas.Pen.Width := 3;
      Canvas.Pen.Color := ToColor(Colors.Accent);
      DrawEdge(Edge);
    end;
  // Units.
  Canvas.Pen.Style := psSolid;
  for Index := 0 to High(FModel.Units) do
  begin
    if not UnitVisible(Index) then
      Continue;
    Item := FModel.Units[Index];
    X := Px(FView.ScreenX(Item.X));
    Y := Px(FView.ScreenY(Item.Y));
    Radius := Max(2, Px(FModel.NodeRadius(Index) * FView.Scale));
    if Pathing then
      Visible := FPathNodes[Index]
    else
      Visible := not Filtered or FModel.Matches(Index, FFilter);
    Fill := TAtlasColor(FModel.SubsystemColor(Item.Subsystem, Dark));
    if not Visible then
      Fill := TAtlasColorMath.Mix(Fill, Colors.Surface, DimAlpha);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Fill);
    Canvas.Pen.Width := 1;
    Canvas.Pen.Color := ToColor(Colors.Surface);
    if Item.Outlier then
    begin
      Canvas.Pen.Width := 2;
      Canvas.Pen.Color := ToColor(Colors.Warn);
    end;
    if FMarkCycles and Item.OnCycle then
    begin
      Canvas.Pen.Width := 2;
      Canvas.Pen.Color := ToColor(Colors.Error);
    end;
    if (Index = FSelected) or (Pathing and ((Index = FPathFrom) or (Index = FPathTo))) then
    begin
      Canvas.Pen.Width := 3;
      Canvas.Pen.Color := ToColor(Colors.Text);
    end;
    Canvas.Ellipse(X - Radius, Y - Radius, X + Radius + 1, Y + Radius + 1);
  end;
  // Namen zuletzt, damit keine Linie sie durchstreicht; darüber der Hinweis (#1368).
  if FShowNames then
    PaintNames(Colors, Pathing, Filtered);
  PaintHover(Colors);
end;

procedure TAtlasArchitectureMap.PaintNames(const AColors: TAtlasColors; APathing, AFiltered: Boolean);
var
  Index, Radius: Integer;
  Item: TAtlasArchUnit;
  Visible, Major: Boolean;
begin
  Canvas.Brush.Style := bsClear;
  for Index := 0 to High(FModel.Units) do
  begin
    if not UnitVisible(Index) then
      Continue;
    Item := FModel.Units[Index];
    if APathing then
      Visible := FPathNodes[Index]
    else
      Visible := not AFiltered or FModel.Matches(Index, FFilter);
    Major := FCentral[Index] or (Index = FSelected) or (APathing and Visible) or (AFiltered and Visible);
    if not Major and not ((FView.Scale >= AllNamesScale) and Visible) then
      Continue;
    if Visible then
      Canvas.Font.Color := ToColor(AColors.Text)
    else
      Canvas.Font.Color := ToColor(AColors.Muted);
    Radius := Max(2, Px(FModel.NodeRadius(Index) * FView.Scale));
    Canvas.TextOut(Px(FView.ScreenX(Item.X)) + Radius + 3, Px(FView.ScreenY(Item.Y)) - Canvas.TextHeight('Ag') div 2,
      Item.Name);
  end;
end;

procedure TAtlasArchitectureMap.PaintHover(const AColors: TAtlasColors);
var
  mSize: TSize;
  mX, mY, mRadius: Integer;
  mRect: TRect;
begin
  if not FShowAssignment or FDragging or not TAtlasArchitectureAssignment.Available(FModel, FHover) then
    Exit;
  Canvas.Font.Assign(Font);
  mSize := TAtlasArchitectureAssignment.Measure(Canvas, FModel, FHover, CurrentPPI);
  // Rechts unter der Unit, am Rand der Karte nach innen geklappt.
  mRadius := Max(2, Px(FModel.NodeRadius(FHover) * FView.Scale));
  mX := Px(FView.ScreenX(FModel.Units[FHover].X)) + mRadius + 4;
  mY := Px(FView.ScreenY(FModel.Units[FHover].Y)) + mRadius + 4;
  if mX + mSize.cx > ClientWidth then
    mX := Px(FView.ScreenX(FModel.Units[FHover].X)) - mRadius - 4 - mSize.cx;
  if mY + mSize.cy > ClientHeight then
    mY := Px(FView.ScreenY(FModel.Units[FHover].Y)) - mRadius - 4 - mSize.cy;
  mX := Max(0, mX);
  mY := Max(0, mY);
  mRect := Rect(mX, mY, mX + mSize.cx, mY + mSize.cy);
  TAtlasArchitectureAssignment.Draw(Canvas, mRect, FModel, FHover, CurrentPPI, AColors);
end;

procedure TAtlasArchitectureMap.SetHover(AUnit: Integer);
begin
  if AUnit = FHover then
    Exit;
  FHover := AUnit;
  if FShowAssignment and FModel.HasAssignment then
    Invalidate;
end;

procedure TAtlasArchitectureMap.SetShowAssignment(AValue: Boolean);
begin
  if AValue = FShowAssignment then
    Exit;
  FShowAssignment := AValue;
  Invalidate;
end;

procedure TAtlasArchitectureMap.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  SetHover(-1);
end;

procedure TAtlasArchitectureMap.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
  if Button <> mbLeft then
    Exit;
  FDragging := True;
  FMoved := False;
  FDragX := X;
  FDragY := Y;
end;

procedure TAtlasArchitectureMap.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
  begin
    SetHover(FView.UnitAt(FModel, X, Y, FHidden));
    Exit;
  end;
  if not FMoved and (Abs(X - FDragX) <= DragThreshold) and (Abs(Y - FDragY) <= DragThreshold) then
    Exit;
  FMoved := True;
  FView.Pan(X - FDragX, Y - FDragY);
  FDragX := X;
  FDragY := Y;
  Invalidate;
end;

procedure TAtlasArchitectureMap.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not FDragging then
    Exit;
  FDragging := False;
  if FMoved then
    Exit;
  Hit := FView.UnitAt(FModel, X, Y, FHidden);
  // Umschalt+Klick: Weg von der gewählten Unit hierher (wie die HTML-Karte).
  if (ssShift in Shift) and (FSelected >= 0) and (Hit >= 0) and (Hit <> FSelected) then
  begin
    ShowPath(FSelected, Hit);
    Exit;
  end;
  SelectUnit(Hit, False);
  if Assigned(FOnSelect) then
    FOnSelect(Hit);
end;

procedure TAtlasArchitectureMap.DblClick;
begin
  inherited DblClick;
  if (FSelected >= 0) and Assigned(FOnOpen) then
    FOnOpen(FSelected);
end;

procedure TAtlasArchitectureMap.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ADD, VK_OEM_PLUS:
      ZoomBy(1.25);
    VK_SUBTRACT, VK_OEM_MINUS:
      ZoomBy(1 / 1.25);
    Ord('0'), VK_NUMPAD0:
      FitView;
    VK_RETURN:
      if (FSelected >= 0) and Assigned(FOnOpen) then
        FOnOpen(FSelected);
    VK_ESCAPE:
      if FPathFrom >= 0 then
        ClearPath
      else
        Exit;
  else
    Exit;
  end;
  Key := 0;
end;

function TAtlasArchitectureMap.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  Local: TPoint;
begin
  Result := True;
  Local := ScreenToClient(MousePos);
  if WheelDelta > 0 then
    FView.ZoomAt(1.15, Local.X, Local.Y)
  else
    FView.ZoomAt(1 / 1.15, Local.X, Local.Y);
  Invalidate;
end;

end.
