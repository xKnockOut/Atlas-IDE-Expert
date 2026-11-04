unit Atlas.Common.Architecture.SymbolPath;

// Kürzester Weg zwischen zwei Symbolen oder Units (#1117): MCP-Werkzeug
// find_path, Anfrage atlas/symbolPath und IDE-Befehl „Weg zwischen
// Symbolen…“.
//
// - Knoten sind Units und Deklarationen des Index (Typen, Routinen, Felder …).
// - Kanten, gerichtet „von → nach“:
//     uses        Unit → Unit, über den Uses-Graphen (#268)
//     inherits    Typ → Vorfahr
//     implements  Klasse → Interface und Interface → umsetzende Klasse, ebenso
//                 je Methode (Name oder Methodenzuordnung IFoo.Bar=Baz)
//     hasField    Typ → Typ eines Felds/einer Property, Feld/Property → Typ
//     parameter   Routine → Typ eines Parameters
//     result      Routine → Ergebnistyp
//     calls       Routine → aufgerufene Routine (TLspHierarchies wie
//                 get_call_hierarchy)
//     contains    Unit → Deklaration, Typ → Mitglied
// - Zweistufig: Erst eine bidirektionale Breitensuche über die Kanten, die der
//   Index schon kennt (alle außer calls). Danach, falls calls erlaubt ist, eine
//   zweite, die nur noch einen kürzeren Weg sucht. Aufrufkanten entstehen dabei
//   erst für die Routinen, die die Suche erreicht: vorwärts aus ihrem Rumpf,
//   rückwärts nur aus Units, deren Verwendungsindex (#492) den Namen enthält.
// - Ziel ist ein Typ samt seinen Mitgliedern bzw. eine Unit samt ihren
//   Deklarationen: Der Weg endet, sobald er eines davon erreicht.
// - Gleich lange Wege eindeutig: Kantenart nach der Rangfolge von
//   TSymbolPathEdgeKind, dann bei uses die Reihenfolge im Quelltext (wie
//   TUsesGraph.Path), sonst der qualifizierte Name des Ziels.
// - Bibliotheks-Units sind Start oder Ziel, aber kein Durchgang, außer mit
//   ThroughLibrary ("library" in via).
// - Grenzen: MaxSteps, MaxNodes besuchte Knoten, Zeitlimit und Abbruch; dann
//   Status Aborted, nie ein stilles „kein Weg“.
// - Kanten mit mehreren möglichen Zielen (Interface mit mehreren Umsetzungen,
//   Typname in mehreren Units, von denen keine sichtbar ist) gelten als
//   erschlossen (#1119).
// - Knoten und Kanten stehen in SymbolPath.Nodes, die Kanten aus dem Index in
//   SymbolPath.Graph, die Aufrufkanten in SymbolPath.Calls; hier die Suche und
//   die Ausgabe.

interface

{$SCOPEDENUMS ON}

uses
  System.JSON,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesService,
  Atlas.Common.Architecture.SymbolPath.Nodes,
  Atlas.Common.Architecture.SymbolPath.Graph,
  Atlas.Common.Architecture.SymbolPath.Calls;

type
  /// <summary>Kantenarten in ihrer Rangfolge bei gleich langen Wegen.</summary>
  TSymbolPathEdgeKind = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathEdgeKind;
  TSymbolPathEdgeKinds = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathEdgeKinds;
  TSymbolPathNode = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathNode;
  TSymbolPathStep = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathStep;
  TSymbolPathRoute = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathRoute;
  TSymbolPathReadText = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathReadText;
  TSymbolPathCancelled = Atlas.Common.Architecture.SymbolPath.Nodes.TSymbolPathCancelled;

  TSymbolPathStatus = (Found, NoPath, Aborted, Ambiguous, NotFound);

  TSymbolPathResult = record
    Status: TSymbolPathStatus;
    From: string;
    To_: string;
    /// <summary>Gefundene Wege: einer, mit All bis zu MaxRoutes.</summary>
    Routes: TArray<TSymbolPathRoute>;
    /// <summary>Zahl der gleich kurzen Wege bis MaxRoutes; MoreRoutes, wenn es mehr gibt.</summary>
    RouteCount: Integer;
    MoreRoutes: Boolean;
    MaxSteps: Integer;
    /// <summary>So viele Schritte hat die Suche vollständig geprüft (bei Aborted).</summary>
    SearchedSteps: Integer;
    Visited: Integer;
    ElapsedMs: Int64;
    /// <summary>Grund des Abbruchs: Zeitlimit, Abbruch oder Knotengrenze.</summary>
    AbortReason: string;
    /// <summary>Weg gefunden, die Suche nach einem kürzeren über Aufrufe wurde aber abgebrochen.</summary>
    CallsIncomplete: Boolean;
    /// <summary>Die Kantenarten der Anfrage waren eingeschränkt.</summary>
    Restricted: Boolean;
    /// <summary>Mehrdeutig bzw. nicht gefunden: die Angabe und bei Ambiguous ihre Treffer.</summary>
    Subject: string;
    Candidates: TArray<TSymbolPathNode>;
    /// <summary>Gesuchtes Ziel; der letzte Knoten eines Wegs kann ein Mitglied davon sein.</summary>
    Target: TSymbolPathNode;
  end;

  TSymbolPathRequest = record
  public const
    DefaultSteps = 8;
    MaxStepsLimit = 16;
    MaxRoutes = 5;
    DefaultNodes = 20000;
  public
    From: string;
    To_: string;
    Via: TSymbolPathEdgeKinds;
    /// <summary>Bibliotheks-Units auch als Durchgang ("library" in via).</summary>
    ThroughLibrary: Boolean;
    MaxSteps: Integer;
    /// <summary>Alle gleich kurzen Wege (höchstens MaxRoutes) statt nur des ersten.</summary>
    All: Boolean;
    MaxNodes: Integer;
    /// <summary>0 = ohne Zeitlimit.</summary>
    TimeoutMs: Integer;
    class function Default: TSymbolPathRequest; static;
  end;

  TSymbolPathSearch = class
  private
    FIndex: ISymbolIndex;
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FReadText: TSymbolPathReadText;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FTable: TSymbolPathNodeTable;
    FEdges: TSymbolPathGraph;
    FCalls: TSymbolPathCalls;
  public
    /// <summary>AGraph mit Bibliotheks-Units (IncludeLibrary); ALocator für die Fundstellen der uses-Einträge.
    /// Beide gehören dem Aufrufer und gelten nur während Find.</summary>
    constructor Create(const AIndex: ISymbolIndex; AGraph: TUsesGraph; ALocator: TUsesLocator;
      const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc);
    destructor Destroy; override;
    function Find(const ARequest: TSymbolPathRequest; const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
    /// <summary>Find über den Graphen des Dienstes (unter seiner Sperre).</summary>
    class function Run(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService; ALocator: TUsesLocator;
      const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc; const ANamespaces: TArray<string>;
      const ARequest: TSymbolPathRequest; const ACancelled: TSymbolPathCancelled): TSymbolPathResult; static;
    /// <summary>Name der Kantenart in via ("uses", "hasField" …).</summary>
    class function EdgeName(AKind: TSymbolPathEdgeKind): string; static;
    /// <summary>Kantenart aus via; "library" setzt AThroughLibrary statt einer Kantenart.</summary>
    class function TryParseEdge(const AText: string; out AKind: TSymbolPathEdgeKind;
      out AThroughLibrary: Boolean): Boolean; static;
    /// <summary>Beschriftung eines Schritts: "ruft auf", "verwendet", "hat Feld", "umgesetzt von" …</summary>
    class function StepCaption(const AStep: TSymbolPathStep; const AFrom: TSymbolPathNode): string; static;
    /// <summary>Antwort als Text für die KI; Pfade relativ zu ARoot, wenn sie darunter liegen.</summary>
    class function Text(const AResult: TSymbolPathResult; const ARoot: string): string; static;
    /// <summary>Antwort als JSON für das Plugin (Zeilen und Spalten ab 0); der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TSymbolPathResult): TJSONObject; static;
    property Namespaces: TArray<string> read FNamespaces write FNamespaces;
  end;

const
  AllSymbolPathEdges: TSymbolPathEdgeKinds = [Low(TSymbolPathEdgeKind)..High(TSymbolPathEdgeKind)];

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Diagnostics,
  System.Generics.Collections;

const
  cEdgeNames: array[TSymbolPathEdgeKind] of string = ('uses', 'inherits', 'implements', 'hasField', 'parameter',
    'result', 'calls', 'contains');
  /// <summary>Alle so viele Knoten Zeitlimit und Abbruch prüfen.</summary>
  cCheckEvery = 16;

type
  TSymbolPathOutcome = (Found, NoPath, Aborted);

  /// <summary>Ein Schritt eines gefundenen Wegs: Quelle und Kante.</summary>
  TSymbolPathStepRef = record
    Source: Integer;
    Edge: TSymbolPathEdge;
  end;
  TSymbolPathStepRefs = TArray<TSymbolPathStepRef>;

  TSymbolPathRun = class;

  /// <summary>Sammelt die gleich kurzen Wege einer gefundenen Länge (Tiefensuche über die Abstände).</summary>
  TSymbolPathWalker = class
  private
    FRun: TSymbolPathRun;
    FLength: Integer;
    FForwardDepth: Integer;
    FWithCalls: Boolean;
    FMax: Integer;
    FFound: TList<TSymbolPathStepRefs>;
    FDead: TDictionary<Integer, Boolean>;
    FCurrent: TList<TSymbolPathStepRef>;
    /// <summary>ANode liegt an Stelle APosition eines kürzesten Wegs.</summary>
    function Fits(ANode, APosition: Integer): Boolean;
    procedure Walk(ANode, APosition: Integer);
  public
    constructor Create(ARun: TSymbolPathRun; ALength, AForwardDepth: Integer; AWithCalls: Boolean; AMax: Integer);
    destructor Destroy; override;
    function Walked(AStart: Integer): TArray<TSymbolPathStepRefs>;
  end;

  /// <summary>Zustand einer Suche (ein Aufruf von Find).</summary>
  TSymbolPathRun = class
  private
    FTable: TSymbolPathNodeTable;
    FEdges: TSymbolPathGraph;
    FCalls: TSymbolPathCalls;
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FDistF: TDictionary<Integer, Integer>;
    FDistB: TDictionary<Integer, Integer>;
    FStart: Integer;
    FGoal: TArray<Integer>;
    FMaxNodes: Integer;
    FTimeoutMs: Integer;
    FCancelled: TSymbolPathCancelled;
    FClock: Int64;
    FVisited: Integer;
    FAbortReason: string;
    FSearchedSteps: Integer;
    function Elapsed: Int64;
    function Stopped: Boolean;
    function EdgesFor(ANode: Integer; AWithCalls: Boolean): TSymbolPathEdges;
    /// <summary>Abstände auf Start und Ziele setzen; True, wenn der Start schon ein Ziel ist.</summary>
    function Prime: Boolean;
    procedure ExpandForward(ANode, ADepth: Integer; AWithCalls: Boolean; ANext: TList<Integer>);
    /// <summary>Vorgänger (und mit AWithCalls Aufrufer) von ANode; False, wenn die Suche abgebrochen wurde.</summary>
    function ExpandBackward(ANode, ADepth: Integer; AWithCalls: Boolean; ANext: TList<Integer>): Boolean;
    procedure Reach(const ANodes: TArray<Integer>; ADepth: Integer; ANext: TList<Integer>);
    /// <summary>Die Front AFront um eine ganze Ebene erweitern; False, wenn die Suche abgebrochen wurde.</summary>
    function Advance(var AFront: TList<Integer>; var ADepth: Integer; AWithCalls, AForward: Boolean): Boolean;
    function Search(AWithCalls: Boolean; ALimit: Integer; out ALength, AForwardDepth: Integer): TSymbolPathOutcome;
    function Collect(ALength, AForwardDepth: Integer; AWithCalls: Boolean): TArray<TSymbolPathStepRefs>;
    function RouteOf(const ASteps: TSymbolPathStepRefs): TSymbolPathRoute;
    /// <summary>Stufe 2: nur ein kürzerer Weg über Aufrufe.</summary>
    procedure CallStage(var AOutcome: TSymbolPathOutcome; var ALength: Integer;
      var APaths: TArray<TSymbolPathStepRefs>; var AResult: TSymbolPathResult);
    procedure Route(AEnd: Integer; const ARequest: TSymbolPathRequest; var AResult: TSymbolPathResult);
    procedure Report(AOutcome: TSymbolPathOutcome; const APaths: TArray<TSymbolPathStepRefs>; ALength: Integer;
      AAll: Boolean; var AResult: TSymbolPathResult);
  public
    constructor Create(ASearch: TSymbolPathSearch);
    destructor Destroy; override;
    function Execute(const ARequest: TSymbolPathRequest; const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
  end;

{ TSymbolPathRequest }

class function TSymbolPathRequest.Default: TSymbolPathRequest;
begin
  Result.From := '';
  Result.To_ := '';
  Result.Via := AllSymbolPathEdges;
  Result.ThroughLibrary := False;
  Result.MaxSteps := DefaultSteps;
  Result.All := False;
  Result.MaxNodes := DefaultNodes;
  Result.TimeoutMs := 0;
end;

{ TSymbolPathWalker }

constructor TSymbolPathWalker.Create(ARun: TSymbolPathRun; ALength, AForwardDepth: Integer; AWithCalls: Boolean;
  AMax: Integer);
begin
  inherited Create;
  FRun := ARun;
  FLength := ALength;
  FForwardDepth := AForwardDepth;
  FWithCalls := AWithCalls;
  FMax := AMax;
  FFound := TList<TSymbolPathStepRefs>.Create;
  FDead := TDictionary<Integer, Boolean>.Create;
  FCurrent := TList<TSymbolPathStepRef>.Create;
end;

destructor TSymbolPathWalker.Destroy;
begin
  FCurrent.Free;
  FDead.Free;
  FFound.Free;
  inherited;
end;

function TSymbolPathWalker.Fits(ANode, APosition: Integer): Boolean;
var
  mDistance: Integer;
begin
  if APosition > FForwardDepth then
  begin
    Exit(FRun.FDistB.TryGetValue(ANode, mDistance) and (mDistance = FLength - APosition));
  end;
  Result := FRun.FDistF.TryGetValue(ANode, mDistance) and (mDistance = APosition);
  if Result and (APosition = FLength) then
  begin
    Result := FRun.FDistB.TryGetValue(ANode, mDistance) and (mDistance = 0);
  end;
end;

procedure TSymbolPathWalker.Walk(ANode, APosition: Integer);
var
  mEdge: TSymbolPathEdge;
  mBefore: Integer;
  mStep: TSymbolPathStepRef;
begin
  if APosition = FLength then
  begin
    FFound.Add(FCurrent.ToArray);
    Exit;
  end;
  mBefore := FFound.Count;
  for mEdge in FRun.EdgesFor(ANode, FWithCalls) do
  begin
    if FFound.Count >= FMax then
    begin
      Exit;
    end;
    if FDead.ContainsKey(mEdge.Target) or not Fits(mEdge.Target, APosition + 1) then
    begin
      Continue;
    end;
    mStep.Source := ANode;
    mStep.Edge := mEdge;
    FCurrent.Add(mStep);
    Walk(mEdge.Target, APosition + 1);
    FCurrent.Delete(FCurrent.Count - 1);
  end;
  if FFound.Count = mBefore then
  begin
    FDead.AddOrSetValue(ANode, True);
  end;
end;

function TSymbolPathWalker.Walked(AStart: Integer): TArray<TSymbolPathStepRefs>;
begin
  Walk(AStart, 0);
  Result := FFound.ToArray;
end;

{ TSymbolPathRun }

/// <summary>Abbruchprüfung für die Aufrufkanten: fragt die laufende Suche ARun.</summary>
function StopCheckOf(ARun: TSymbolPathRun): TSymbolPathCancelled;
begin
  Result :=
    function: Boolean
    begin
      Result := ARun.Stopped;
    end;
end;

constructor TSymbolPathRun.Create(ASearch: TSymbolPathSearch);
begin
  inherited Create;
  FTable := ASearch.FTable;
  FEdges := ASearch.FEdges;
  FCalls := ASearch.FCalls;
  FGraph := ASearch.FGraph;
  FLocator := ASearch.FLocator;
  FDistF := TDictionary<Integer, Integer>.Create;
  FDistB := TDictionary<Integer, Integer>.Create;
  FCalls.Stopped := StopCheckOf(Self);
end;

destructor TSymbolPathRun.Destroy;
begin
  FCalls.Stopped := nil;
  FDistB.Free;
  FDistF.Free;
  inherited;
end;

function TSymbolPathRun.Elapsed: Int64;
begin
  Result := (TStopwatch.GetTimeStamp - FClock) * 1000 div TStopwatch.Frequency;
end;

function TSymbolPathRun.Stopped: Boolean;
begin
  if FAbortReason = '' then
  begin
    if Assigned(FCancelled) and FCancelled() then
    begin
      FAbortReason := 'abgebrochen';
    end
    else if (FTimeoutMs > 0) and (Elapsed > FTimeoutMs) then
    begin
      FAbortReason := 'Zeitlimit';
    end
    else if FVisited > FMaxNodes then
    begin
      FAbortReason := 'Knotengrenze';
    end;
  end;
  Result := FAbortReason <> '';
end;

function TSymbolPathRun.EdgesFor(ANode: Integer; AWithCalls: Boolean): TSymbolPathEdges;
var
  mEdge: TSymbolPathEdge;
begin
  Result := nil;
  for mEdge in FEdges.ForwardOf(ANode) do
  begin
    if mEdge.Kind in FEdges.Via then
    begin
      Result := Result + [mEdge];
    end;
  end;
  if AWithCalls then
  begin
    Result := Result + FCalls.CallsOf(ANode);
    TSymbolPathEdgeList.Sort(Result);
  end;
end;

function TSymbolPathRun.Prime: Boolean;
var
  mNode: Integer;
begin
  FDistF.Clear;
  FDistB.Clear;
  FDistF.Add(FStart, 0);
  for mNode in FGoal do
  begin
    FDistB.AddOrSetValue(mNode, 0);
  end;
  Result := FDistB.ContainsKey(FStart);
  if not Result then
  begin
    Inc(FVisited, FDistF.Count + FDistB.Count);
  end;
end;

procedure TSymbolPathRun.ExpandForward(ANode, ADepth: Integer; AWithCalls: Boolean; ANext: TList<Integer>);
var
  mEdge: TSymbolPathEdge;
begin
  for mEdge in EdgesFor(ANode, AWithCalls) do
  begin
    if not FDistF.ContainsKey(mEdge.Target) and FEdges.Passable(mEdge.Target) then
    begin
      FDistF.Add(mEdge.Target, ADepth + 1);
      Inc(FVisited);
      ANext.Add(mEdge.Target);
    end;
  end;
end;

procedure TSymbolPathRun.Reach(const ANodes: TArray<Integer>; ADepth: Integer; ANext: TList<Integer>);
var
  mNode: Integer;
begin
  for mNode in ANodes do
  begin
    if not FDistB.ContainsKey(mNode) then
    begin
      FDistB.Add(mNode, ADepth + 1);
      Inc(FVisited);
      ANext.Add(mNode);
    end;
  end;
end;

function TSymbolPathRun.ExpandBackward(ANode, ADepth: Integer; AWithCalls: Boolean; ANext: TList<Integer>): Boolean;
begin
  Reach(FEdges.PredecessorsOf(ANode), ADepth, ANext);
  if AWithCalls then
  begin
    Reach(FCalls.CallersOf(ANode), ADepth, ANext);
  end;
  Result := FAbortReason = '';
end;

function TSymbolPathRun.Advance(var AFront: TList<Integer>; var ADepth: Integer; AWithCalls, AForward: Boolean)
  : Boolean;
var
  mNext: TList<Integer>;
  mNode, mCount: Integer;
begin
  mNext := TList<Integer>.Create;
  try
    mCount := 0;
    for mNode in AFront.ToArray do
    begin
      Inc(mCount);
      // Am Anfang jeder Ebene und dann alle cCheckEvery Knoten.
      if ((mCount mod cCheckEvery = 1) or (FVisited > FMaxNodes)) and Stopped then
      begin
        Exit(False);
      end;
      if AForward then
      begin
        ExpandForward(mNode, ADepth, AWithCalls, mNext);
      end
      else if not ExpandBackward(mNode, ADepth, AWithCalls, mNext) then
      begin
        Exit(False);
      end;
    end;
    Inc(ADepth);
    AFront.Free;
    AFront := mNext;
    mNext := nil;
    Result := True;
  finally
    mNext.Free;
  end;
end;

/// <summary>Kürzeste Länge über die Knoten von AFront (Tiefe ADepth), die die andere Seite AOther schon erreicht
/// hat; -1 ohne.</summary>
function Meeting(AFront: TList<Integer>; ADepth: Integer; AOther: TDictionary<Integer, Integer>): Integer;
var
  mNode, mOther: Integer;
begin
  Result := -1;
  for mNode in AFront do
  begin
    if AOther.TryGetValue(mNode, mOther) and ((Result < 0) or (ADepth + mOther < Result)) then
    begin
      Result := ADepth + mOther;
    end;
  end;
end;

function TSymbolPathRun.Search(AWithCalls: Boolean; ALimit: Integer; out ALength, AForwardDepth: Integer)
  : TSymbolPathOutcome;
var
  mFrontF, mFrontB: TList<Integer>;
  mDepthF, mDepthB, mBest: Integer;
  mAdvanced: Boolean;
begin
  ALength := -1;
  AForwardDepth := 0;
  if Prime then
  begin
    ALength := 0;
    Exit(TSymbolPathOutcome.Found);
  end;
  mFrontF := TList<Integer>.Create;
  mFrontB := TList<Integer>.Create;
  try
    mFrontF.Add(FStart);
    mFrontB.AddRange(FGoal);
    mDepthF := 0;
    mDepthB := 0;
    Result := TSymbolPathOutcome.NoPath;
    // Je Schritt die kleinere Front um eine ganze Ebene erweitern; sobald sich beide treffen, ist die
    // kürzeste Länge das Minimum über die gemeinsamen Knoten.
    while (mDepthF + mDepthB < ALimit) and (mFrontF.Count > 0) and (mFrontB.Count > 0) do
    begin
      FSearchedSteps := mDepthF + mDepthB;
      if mFrontF.Count <= mFrontB.Count then
      begin
        mAdvanced := Advance(mFrontF, mDepthF, AWithCalls, True);
        mBest := Meeting(mFrontF, mDepthF, FDistB);
      end
      else
      begin
        mAdvanced := Advance(mFrontB, mDepthB, AWithCalls, False);
        mBest := Meeting(mFrontB, mDepthB, FDistF);
      end;
      if not mAdvanced then
      begin
        Exit(TSymbolPathOutcome.Aborted);
      end;
      if mBest >= 0 then
      begin
        ALength := mBest;
        AForwardDepth := mDepthF;
        Exit(TSymbolPathOutcome.Found);
      end;
    end;
  finally
    mFrontB.Free;
    mFrontF.Free;
  end;
end;

function TSymbolPathRun.Collect(ALength, AForwardDepth: Integer; AWithCalls: Boolean): TArray<TSymbolPathStepRefs>;
var
  mWalker: TSymbolPathWalker;
begin
  mWalker := TSymbolPathWalker.Create(Self, ALength, AForwardDepth, AWithCalls, TSymbolPathRequest.MaxRoutes + 1);
  try
    Result := mWalker.Walked(FStart);
  finally
    mWalker.Free;
  end;
end;

function TSymbolPathRun.RouteOf(const ASteps: TSymbolPathStepRefs): TSymbolPathRoute;
var
  mRef: TSymbolPathStepRef;
  mStep: TSymbolPathStep;
  mLocation: TUsesLocation;
begin
  Result.Nodes := [FTable.Node(FStart)];
  Result.Steps := nil;
  for mRef in ASteps do
  begin
    mStep := Default(TSymbolPathStep);
    mStep.Kind := mRef.Edge.Kind;
    mStep.Reverse := mRef.Edge.Reverse;
    mStep.Inferred := mRef.Edge.Inferred;
    mStep.FileName := mRef.Edge.FileName;
    mStep.Position := mRef.Edge.Position;
    if mRef.Edge.HasUsesEdge then
    begin
      mStep.Implementation_ := mRef.Edge.UsesEdge.Section = TUsesSection.Implementation_;
      if (FLocator <> nil) and FLocator.Locate(FGraph, mRef.Edge.UsesEdge, mLocation) then
      begin
        mStep.FileName := mLocation.FileName;
        mStep.Position := mLocation.Range.StartPos;
      end;
    end;
    Result.Steps := Result.Steps + [mStep];
    Result.Nodes := Result.Nodes + [FTable.Node(mRef.Edge.Target)];
  end;
end;

procedure TSymbolPathRun.CallStage(var AOutcome: TSymbolPathOutcome; var ALength: Integer;
  var APaths: TArray<TSymbolPathStepRefs>; var AResult: TSymbolPathResult);
var
  mLimit, mLength, mDepth: Integer;
  mOutcome: TSymbolPathOutcome;
begin
  mLimit := AResult.MaxSteps;
  if AOutcome = TSymbolPathOutcome.Found then
  begin
    mLimit := ALength - 1;
  end;
  mOutcome := Search(True, mLimit, mLength, mDepth);
  if mOutcome = TSymbolPathOutcome.Found then
  begin
    APaths := Collect(mLength, mDepth, True);
    ALength := mLength;
    AOutcome := TSymbolPathOutcome.Found;
  end
  else if (mOutcome = TSymbolPathOutcome.Aborted) and (AOutcome = TSymbolPathOutcome.Found) then
  begin
    AResult.CallsIncomplete := True;
    AResult.AbortReason := FAbortReason;
  end
  else if mOutcome = TSymbolPathOutcome.Aborted then
  begin
    AOutcome := TSymbolPathOutcome.Aborted;
  end;
end;

procedure TSymbolPathRun.Report(AOutcome: TSymbolPathOutcome; const APaths: TArray<TSymbolPathStepRefs>;
  ALength: Integer; AAll: Boolean; var AResult: TSymbolPathResult);
var
  mIndex, mCount: Integer;
begin
  case AOutcome of
    TSymbolPathOutcome.Found:
      begin
        AResult.Status := TSymbolPathStatus.Found;
        AResult.RouteCount := Min(Length(APaths), TSymbolPathRequest.MaxRoutes);
        AResult.MoreRoutes := Length(APaths) > TSymbolPathRequest.MaxRoutes;
        mCount := AResult.RouteCount;
        if not AAll then
        begin
          mCount := Min(mCount, 1);
        end;
        for mIndex := 0 to mCount - 1 do
        begin
          AResult.Routes := AResult.Routes + [RouteOf(APaths[mIndex])];
        end;
        AResult.SearchedSteps := ALength;
      end;
    TSymbolPathOutcome.NoPath:
      begin
        AResult.Status := TSymbolPathStatus.NoPath;
        AResult.SearchedSteps := AResult.MaxSteps;
      end;
  else
    AResult.Status := TSymbolPathStatus.Aborted;
    AResult.AbortReason := FAbortReason;
    AResult.SearchedSteps := FSearchedSteps;
  end;
end;

procedure TSymbolPathRun.Route(AEnd: Integer; const ARequest: TSymbolPathRequest; var AResult: TSymbolPathResult);
var
  mOutcome: TSymbolPathOutcome;
  mLength, mDepth: Integer;
  mPaths: TArray<TSymbolPathStepRefs>;
begin
  AResult.Target := FTable.Node(AEnd);
  FGoal := FTable.Targets(AEnd);
  FEdges.Configure(ARequest.Via, ARequest.ThroughLibrary, TArray<Integer>.Create(FStart) + FGoal);
  // Stufe 1: Kanten aus dem Index.
  mOutcome := Search(False, AResult.MaxSteps, mLength, mDepth);
  mPaths := nil;
  if mOutcome = TSymbolPathOutcome.Found then
  begin
    mPaths := Collect(mLength, mDepth, False);
  end;
  // Stufe 2: nur ein kürzerer Weg über Aufrufe.
  if (TSymbolPathEdgeKind.Calls in ARequest.Via) and (mOutcome <> TSymbolPathOutcome.Aborted) and
    ((mOutcome = TSymbolPathOutcome.NoPath) or (mLength > 1)) then
  begin
    CallStage(mOutcome, mLength, mPaths, AResult);
  end;
  Report(mOutcome, mPaths, mLength, ARequest.All, AResult);
end;

/// <summary>Mehrdeutig oder unbekannt: ANodes zur Angabe ASubject als Trefferliste.</summary>
procedure Unresolved(ATable: TSymbolPathNodeTable; const ANodes: TArray<Integer>; const ASubject: string;
  var AResult: TSymbolPathResult);
var
  mNode: Integer;
begin
  AResult.Subject := ASubject;
  if Length(ANodes) = 0 then
  begin
    AResult.Status := TSymbolPathStatus.NotFound;
    Exit;
  end;
  AResult.Status := TSymbolPathStatus.Ambiguous;
  for mNode in ANodes do
  begin
    AResult.Candidates := AResult.Candidates + [ATable.Node(mNode)];
  end;
end;

function TSymbolPathRun.Execute(const ARequest: TSymbolPathRequest;
  const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
var
  mStarts, mEnds: TArray<Integer>;
begin
  Result := Default(TSymbolPathResult);
  Result.From := ARequest.From;
  Result.To_ := ARequest.To_;
  Result.MaxSteps := EnsureRange(ARequest.MaxSteps, 1, TSymbolPathRequest.MaxStepsLimit);
  Result.Restricted := ARequest.Via <> AllSymbolPathEdges;
  FClock := TStopwatch.GetTimeStamp;
  FMaxNodes := ARequest.MaxNodes;
  if FMaxNodes <= 0 then
  begin
    FMaxNodes := TSymbolPathRequest.DefaultNodes;
  end;
  FTimeoutMs := ARequest.TimeoutMs;
  FCancelled := ACancelled;
  mStarts := FTable.Endpoints(ARequest.From, FGraph);
  mEnds := FTable.Endpoints(ARequest.To_, FGraph);
  // Mehrdeutig oder unbekannt: Trefferliste statt Suche.
  if Length(mStarts) <> 1 then
  begin
    Unresolved(FTable, mStarts, ARequest.From, Result);
  end
  else if Length(mEnds) <> 1 then
  begin
    Unresolved(FTable, mEnds, ARequest.To_, Result);
  end
  else
  begin
    FStart := mStarts[0];
    Route(mEnds[0], ARequest, Result);
  end;
  Result.Visited := FVisited;
  Result.ElapsedMs := Elapsed;
end;

{ TSymbolPathSearch }

constructor TSymbolPathSearch.Create(const AIndex: ISymbolIndex; AGraph: TUsesGraph; ALocator: TUsesLocator;
  const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FIndex := AIndex;
  FGraph := AGraph;
  FLocator := ALocator;
  FReadText := AReadText;
  FEnsureUnit := AEnsureUnit;
  FTable := TSymbolPathNodeTable.Create(AIndex);
  FEdges := TSymbolPathGraph.Create(FTable, AGraph);
end;

destructor TSymbolPathSearch.Destroy;
begin
  FCalls.Free;
  FEdges.Free;
  FTable.Free;
  inherited;
end;

function TSymbolPathSearch.Find(const ARequest: TSymbolPathRequest;
  const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
var
  mRun: TSymbolPathRun;
begin
  if FCalls = nil then
  begin
    FCalls := TSymbolPathCalls.Create(FTable, FEdges, FReadText, FEnsureUnit, FNamespaces);
  end;
  mRun := TSymbolPathRun.Create(Self);
  try
    Result := mRun.Execute(ARequest, ACancelled);
  finally
    mRun.Free;
  end;
end;

class function TSymbolPathSearch.Run(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService;
  ALocator: TUsesLocator; const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc;
  const ANamespaces: TArray<string>; const ARequest: TSymbolPathRequest;
  const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
var
  mAnswer: TSymbolPathResult;
begin
  mAnswer := Default(TSymbolPathResult);
  AGraphs.Read(
    procedure(const AGraph: TUsesGraph)
    var
      mSearch: TSymbolPathSearch;
    begin
      mSearch := TSymbolPathSearch.Create(AIndex, AGraph, ALocator, AReadText, AEnsureUnit);
      try
        mSearch.Namespaces := ANamespaces;
        mAnswer := mSearch.Find(ARequest, ACancelled);
      finally
        mSearch.Free;
      end;
    end);
  Result := mAnswer;
end;

class function TSymbolPathSearch.EdgeName(AKind: TSymbolPathEdgeKind): string;
begin
  Result := cEdgeNames[AKind];
end;

class function TSymbolPathSearch.TryParseEdge(const AText: string; out AKind: TSymbolPathEdgeKind;
  out AThroughLibrary: Boolean): Boolean;
var
  mKind: TSymbolPathEdgeKind;
begin
  AKind := TSymbolPathEdgeKind.Uses_;
  AThroughLibrary := SameText(Trim(AText), 'library');
  if AThroughLibrary then
  begin
    Exit(True);
  end;
  for mKind := Low(TSymbolPathEdgeKind) to High(TSymbolPathEdgeKind) do
  begin
    if SameText(Trim(AText), cEdgeNames[mKind]) then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Beschriftung bei Kanten mit zwei Lesarten: AWhenTrue, wenn ACondition gilt, sonst AWhenFalse.</summary>
function Either(ACondition: Boolean; const AWhenTrue, AWhenFalse: string): string;
begin
  if ACondition then
  begin
    Result := AWhenTrue;
  end
  else
  begin
    Result := AWhenFalse;
  end;
end;

class function TSymbolPathSearch.StepCaption(const AStep: TSymbolPathStep; const AFrom: TSymbolPathNode): string;
begin
  case AStep.Kind of
    TSymbolPathEdgeKind.Uses_:
      Result := Either(AStep.Implementation_, 'verwendet (implementation)', 'verwendet');
    TSymbolPathEdgeKind.Inherits:
      Result := 'erbt von';
    TSymbolPathEdgeKind.Implements:
      Result := Either(AStep.Reverse, 'umgesetzt von', 'setzt um');
    TSymbolPathEdgeKind.HasField:
      Result := Either(AFrom.IsUnit or (AFrom.Symbol.Kind in SymbolPathValueKinds), 'vom Typ', 'hat Feld');
    TSymbolPathEdgeKind.Parameter:
      Result := 'Parameter vom Typ';
    TSymbolPathEdgeKind.Result_:
      Result := 'Ergebnis vom Typ';
    TSymbolPathEdgeKind.Calls:
      Result := 'ruft auf';
  else
    Result := 'enthält';
  end;
end;

function RelativePath(const AFileName, ARoot: string): string;
var
  mRoot: string;
begin
  Result := AFileName;
  mRoot := ARoot;
  while (mRoot <> '') and CharInSet(mRoot[Length(mRoot)], ['\', '/']) do
  begin
    Delete(mRoot, Length(mRoot), 1);
  end;
  if mRoot = '' then
  begin
    Exit;
  end;
  // Beide Trenner: Pfade aus Windows-Projekten auch im Linux-Bau.
  if StartsText(mRoot + '\', AFileName) or StartsText(mRoot + '/', AFileName) then
  begin
    Result := Copy(AFileName, Length(mRoot) + 2, MaxInt);
  end;
end;

function Seconds(AMilliseconds: Int64): string;
var
  mSettings: TFormatSettings;
begin
  mSettings := TFormatSettings.Create;
  mSettings.DecimalSeparator := ',';
  Result := FormatFloat('0.00', AMilliseconds / 1000, mSettings) + ' s';
end;

function StepsText(ACount: Integer): string;
begin
  if ACount = 1 then
  begin
    Result := '1 Schritt';
  end
  else
  begin
    Result := Format('%d Schritten', [ACount]);
  end;
end;

function SearchedText(const AResult: TSymbolPathResult): string;
begin
  Result := Format('Durchsucht: %d Knoten, %s', [AResult.Visited, Seconds(AResult.ElapsedMs)]);
end;

procedure AppendAmbiguous(ALines: TStringBuilder; const AResult: TSymbolPathResult; const ARoot: string);
var
  mNode: TSymbolPathNode;
begin
  ALines.Append(Format('"%s" ist mehrdeutig (%d Treffer):', [AResult.Subject, Length(AResult.Candidates)]));
  for mNode in AResult.Candidates do
  begin
    ALines.Append(sLineBreak).Append(Format('  %s  %s:%d', [mNode.Caption, RelativePath(mNode.FileName, ARoot),
      mNode.Position.Line + 1]));
  end;
  ALines.Append(sLineBreak).Append('Bitte qualifiziert angeben (TTyp.Name oder Unit.Name).');
end;

procedure AppendNoPath(ALines: TStringBuilder; const AResult: TSymbolPathResult);
begin
  ALines.Append(Format('Kein Weg in höchstens %s.', [StepsText(AResult.MaxSteps)]));
  if AResult.Restricted then
  begin
    ALines.Append(' Nur die erlaubten Kantenarten (via) wurden durchsucht.');
  end;
  ALines.Append(sLineBreak).Append(SearchedText(AResult));
end;

/// <summary>"Kürzester Weg (3 Schritte, 2 Wege gleich lang):"</summary>
function FoundHeader(const AResult: TSymbolPathResult): string;
var
  mSteps: Integer;
begin
  mSteps := 0;
  if Length(AResult.Routes) > 0 then
  begin
    mSteps := Length(AResult.Routes[0].Steps);
  end;
  Result := Either(mSteps = 1, 'Kürzester Weg (1 Schritt', Format('Kürzester Weg (%d Schritte', [mSteps]));
  if AResult.MoreRoutes then
  begin
    Result := Result + Format(', mehr als %d Wege gleich lang', [AResult.RouteCount]);
  end
  else if AResult.RouteCount > 1 then
  begin
    Result := Result + Format(', %d Wege gleich lang', [AResult.RouteCount]);
  end;
  Result := Result + '):';
end;

/// <summary>Zeile unter einem Knoten: Beschriftung des Schritts und Fundstelle.</summary>
function StepLine(const AStep: TSymbolPathStep; const AFrom: TSymbolPathNode; const ARoot: string): string;
var
  mCaption, mLocation: string;
begin
  mCaption := TSymbolPathSearch.StepCaption(AStep, AFrom);
  mLocation := Format('%s:%d', [RelativePath(AStep.FileName, ARoot), AStep.Position.Line + 1]);
  if AStep.Inferred then
  begin
    mLocation := '[erschlossen] ' + mLocation;
  end;
  Result := '   ' + mCaption + StringOfChar(' ', Max(1, 18 - Length(mCaption))) + mLocation;
end;

procedure AppendRoute(ALines: TStringBuilder; const ARoute: TSymbolPathRoute; const ATarget: TSymbolPathNode;
  const ARoot: string);
var
  mIndex: Integer;
  mLast: TSymbolPathNode;
begin
  for mIndex := 0 to High(ARoute.Nodes) do
  begin
    ALines.Append(sLineBreak).Append(Format('%d. %s', [mIndex + 1, ARoute.Nodes[mIndex].Caption]));
    if mIndex <= High(ARoute.Steps) then
    begin
      ALines.Append(sLineBreak).Append(StepLine(ARoute.Steps[mIndex], ARoute.Nodes[mIndex], ARoot));
    end;
  end;
  mLast := ARoute.Nodes[High(ARoute.Nodes)];
  if (mLast.UnitName <> ATarget.UnitName) or (mLast.Caption <> ATarget.Caption) then
  begin
    ALines.Append(sLineBreak).Append(Format('   gehört zu %s', [ATarget.Caption]));
  end;
end;

procedure AppendFound(ALines: TStringBuilder; const AResult: TSymbolPathResult; const ARoot: string);
var
  mIndex: Integer;
begin
  ALines.Append(FoundHeader(AResult));
  for mIndex := 0 to High(AResult.Routes) do
  begin
    if Length(AResult.Routes) > 1 then
    begin
      ALines.Append(sLineBreak).Append(Format('Weg %d:', [mIndex + 1]));
    end;
    AppendRoute(ALines, AResult.Routes[mIndex], AResult.Target, ARoot);
  end;
  if AResult.CallsIncomplete then
  begin
    ALines.Append(sLineBreak).Append(Format('Hinweis: Kürzere Wege über Aufrufe nur bis %s geprüft ' +
      '(Suche abgebrochen: %s).', [StepsText(AResult.SearchedSteps), AResult.AbortReason]));
  end;
  ALines.Append(sLineBreak).Append(SearchedText(AResult));
end;

class function TSymbolPathSearch.Text(const AResult: TSymbolPathResult; const ARoot: string): string;
var
  mLines: TStringBuilder;
begin
  mLines := TStringBuilder.Create;
  try
    case AResult.Status of
      TSymbolPathStatus.NotFound:
        mLines.Append(Format('Kein Symbol und keine Unit "%s" im Index.', [AResult.Subject]));
      TSymbolPathStatus.Ambiguous:
        AppendAmbiguous(mLines, AResult, ARoot);
      TSymbolPathStatus.NoPath:
        AppendNoPath(mLines, AResult);
      TSymbolPathStatus.Aborted:
        mLines.Append(Format('Kein Weg gefunden in %s (Suche nach %d Knoten abgebrochen: %s).',
          [StepsText(AResult.SearchedSteps), AResult.Visited, AResult.AbortReason])).Append(sLineBreak)
          .Append(SearchedText(AResult));
    else
      AppendFound(mLines, AResult, ARoot);
    end;
    Result := mLines.ToString;
  finally
    mLines.Free;
  end;
end;

function NodeJson(const ANode: TSymbolPathNode): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('caption', ANode.Caption);
  Result.AddPair('isUnit', TJSONBool.Create(ANode.IsUnit));
  Result.AddPair('unit', ANode.UnitName);
  if not ANode.IsUnit then
  begin
    Result.AddPair('name', ANode.Symbol.Name);
    Result.AddPair('container', ANode.Symbol.Container);
    Result.AddPair('kind', TJSONNumber.Create(Ord(ANode.Symbol.Kind)));
  end;
  Result.AddPair('file', ANode.FileName);
  Result.AddPair('line', TJSONNumber.Create(ANode.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(ANode.Position.Character));
  Result.AddPair('library', TJSONBool.Create(ANode.Library_));
end;

function StepJson(const AStep: TSymbolPathStep; const AFrom: TSymbolPathNode): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('kind', cEdgeNames[AStep.Kind]);
  Result.AddPair('caption', TSymbolPathSearch.StepCaption(AStep, AFrom));
  Result.AddPair('inferred', TJSONBool.Create(AStep.Inferred));
  Result.AddPair('reverse', TJSONBool.Create(AStep.Reverse));
  Result.AddPair('implementation', TJSONBool.Create(AStep.Implementation_));
  Result.AddPair('file', AStep.FileName);
  Result.AddPair('line', TJSONNumber.Create(AStep.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(AStep.Position.Character));
end;

function RouteJson(const ARoute: TSymbolPathRoute): TJSONObject;
var
  mNodes, mSteps: TJSONArray;
  mNode: TSymbolPathNode;
  mIndex: Integer;
begin
  Result := TJSONObject.Create;
  mNodes := TJSONArray.Create;
  Result.AddPair('nodes', mNodes);
  for mNode in ARoute.Nodes do
  begin
    mNodes.AddElement(NodeJson(mNode));
  end;
  mSteps := TJSONArray.Create;
  Result.AddPair('steps', mSteps);
  for mIndex := 0 to High(ARoute.Steps) do
  begin
    mSteps.AddElement(StepJson(ARoute.Steps[mIndex], ARoute.Nodes[mIndex]));
  end;
end;

/// <summary>Kopfwerte der Antwort: Status, Angaben, Zähler und Gründe.</summary>
procedure AddResultPairs(AObject: TJSONObject; const AResult: TSymbolPathResult);
const
  cStatusNames: array[TSymbolPathStatus] of string = ('found', 'noPath', 'aborted', 'ambiguous', 'notFound');
begin
  AObject.AddPair('status', cStatusNames[AResult.Status]);
  AObject.AddPair('from', AResult.From);
  AObject.AddPair('to', AResult.To_);
  AObject.AddPair('maxSteps', TJSONNumber.Create(AResult.MaxSteps));
  AObject.AddPair('searchedSteps', TJSONNumber.Create(AResult.SearchedSteps));
  AObject.AddPair('visited', TJSONNumber.Create(AResult.Visited));
  AObject.AddPair('elapsedMs', TJSONNumber.Create(AResult.ElapsedMs));
  AObject.AddPair('routeCount', TJSONNumber.Create(AResult.RouteCount));
  AObject.AddPair('moreRoutes', TJSONBool.Create(AResult.MoreRoutes));
  AObject.AddPair('callsIncomplete', TJSONBool.Create(AResult.CallsIncomplete));
  AObject.AddPair('restricted', TJSONBool.Create(AResult.Restricted));
  if AResult.AbortReason <> '' then
  begin
    AObject.AddPair('abortReason', AResult.AbortReason);
  end;
  if AResult.Subject <> '' then
  begin
    AObject.AddPair('subject', AResult.Subject);
  end;
  if AResult.Status = TSymbolPathStatus.Found then
  begin
    AObject.AddPair('target', NodeJson(AResult.Target));
  end;
end;

class function TSymbolPathSearch.ToJson(const AResult: TSymbolPathResult): TJSONObject;
var
  mRoutes, mCandidates: TJSONArray;
  mRoute: TSymbolPathRoute;
  mNode: TSymbolPathNode;
begin
  Result := TJSONObject.Create;
  AddResultPairs(Result, AResult);
  mCandidates := TJSONArray.Create;
  Result.AddPair('candidates', mCandidates);
  for mNode in AResult.Candidates do
  begin
    mCandidates.AddElement(NodeJson(mNode));
  end;
  mRoutes := TJSONArray.Create;
  Result.AddPair('routes', mRoutes);
  for mRoute in AResult.Routes do
  begin
    mRoutes.AddElement(RouteJson(mRoute));
  end;
end;

end.
