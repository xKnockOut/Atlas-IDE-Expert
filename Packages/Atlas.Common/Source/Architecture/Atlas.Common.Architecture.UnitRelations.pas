unit Atlas.Common.Architecture.UnitRelations;

// Beziehungen einer Unit (#593) aus dem Uses-Graphen (#268), für das
// Seitenfenster „Unit-Beziehungen“ im Plugin:
//
// - „Verwendet“: die Einträge der uses-Listen der Unit in Quelltextreihenfolge
//   (erst interface, dann implementation), auch solche, die der Graph nicht
//   kennt (RTL ohne Quelltext): Sie gelten als Bibliothek. Fundstelle ist der
//   Eintrag in der Unit selbst.
// - „Wird verwendet von“: alle Units des Graphen, die die Unit verwenden,
//   nach Name, mit dem Abschnitt ihres Eintrags; Fundstelle ist der Eintrag
//   in der verwendenden Unit.
// - Zyklen: Liegt die Unit in einer stark zusammenhängenden Komponente über
//   interface-uses (Compilerfehler F2047), sind die interface-Einträge zu
//   Units derselben Komponente „Zyklus“ und tragen den Rundweg als Text.
// - Kosten: RecompileCount des Graphen (wie #554 und „gesamt abhängig“ in
//   #1118).
// - Tiefe: 1 = direkt; n > 1 bzw. 0 (alle Ebenen) baut Bäume. Jede Unit wird
//   nur einmal aufgeklappt, und zwar auf der Ebene, auf der sie zuerst
//   erreicht wird; weitere Vorkommen sind „Repeated“ ohne Kinder. So bleibt
//   der Baum endlich und höchstens so groß wie der Graph.
// - Ungenutzte Einträge (Unused) nennt der Aufrufer (TUsesActions.Entries),
//   damit das Fenster „Eintrag entfernen“ nur dort anbietet; ebenso
//   interface-Einträge, die nur im implementation-Teil gebraucht werden
//   (OnlyImplementation, #554): Sie lassen sich ins implementation-uses
//   verschieben und senken so die Kosten einer interface-Änderung.
// - InterfaceCost (#554) ist der kleine Teil davon für die Statusleiste:
//   RecompileCount und die ersten Units, die neu übersetzt werden, ohne
//   Text, Fundstellen und Bäume.
// - UseCandidates (#786, „Unit verwenden“): alle Units, die die Unit schon
//   (auch über Umwege) verwenden. Nimmt die Unit eine davon ins interface
//   auf und führt der Rückweg nur über interface-uses, entsteht ein
//   Kreisbezug, den der Compiler ablehnt (F2047, InterfacePath); sonst ist es
//   ein erlaubter Kreis über implementation-uses (Path), nur ein Hinweis.
//   Die Wege kommen aus einer Rückwärtssuche je Abschnittswahl, nicht aus
//   einer Suche je Unit.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator;

type
  TUnitRelation = record
    /// <summary>Unit-Name; bei Einträgen ohne Knoten wie im uses geschrieben.</summary>
    Name: string;
    /// <summary>Datei der Unit; '' ohne Knoten.</summary>
    FileName: string;
    /// <summary>Abschnitt des uses-Eintrags (bei „Wird verwendet von“ in der verwendenden Unit).</summary>
    Section: TUsesSection;
    Library_: Boolean;
    Cycle: Boolean;
    /// <summary>Rundweg über interface-uses, etwa "A → B → A"; '' ohne Zyklus.</summary>
    CyclePath: string;
    Unused: Boolean;
    /// <summary>Steht im interface-uses, gebraucht wird die Unit nur im implementation-Teil (#554).</summary>
    OnlyImplementation: Boolean;
    /// <summary>Kommt im Baum schon weiter oben vor und wird hier nicht aufgeklappt.</summary>
    Repeated: Boolean;
    /// <summary>Fundstelle des uses-Eintrags; Line = -1 ohne.</summary>
    LocationFile: string;
    Line: Integer;
    Character: Integer;
    Children: TArray<TUnitRelation>;
  end;

  TUnitRelations = record
    /// <summary>Die Unit steht im Graphen (sonst nur „Verwendet“ aus dem Text).</summary>
    Found: Boolean;
    UnitName: string;
    FileName: string;
    Uses_: TArray<TUnitRelation>;
    UsedBy: TArray<TUnitRelation>;
    /// <summary>Units, die nach einer Änderung im interface neu übersetzt werden.</summary>
    RecompileCount: Integer;
    /// <summary>Transitive Hüllen über alle Abschnitte.</summary>
    DependencyCount: Integer;
    DependentCount: Integer;
    InCycle: Boolean;
    /// <summary>Kürzester Rundweg über interface-uses durch die Unit.</summary>
    CyclePath: string;
  end;

  /// <summary>Kosten einer Änderung im interface-Teil (#554).</summary>
  TUnitInterfaceCost = record
    Found: Boolean;
    UnitName: string;
    FileName: string;
    /// <summary>Units, die nach einer Änderung im interface neu übersetzt werden.</summary>
    RecompileCount: Integer;
    /// <summary>Die ersten davon nach Name (höchstens ALimit von InterfaceCost).</summary>
    Units: TArray<string>;
  end;

  /// <summary>Eine Unit, deren Aufnahme in die uses einen Kreis schließt (#786).</summary>
  TUnitUseCandidate = record
    Name: string;
    FileName: string;
    /// <summary>Kreis über interface-uses, etwa "A → B → C → A"; '' ohne.</summary>
    InterfacePath: string;
    /// <summary>Kürzester Kreis über alle uses.</summary>
    Path: string;
  end;

  TUnitUseInfo = record
    Found: Boolean;
    UnitName: string;
    FileName: string;
    /// <summary>Nach Name.</summary>
    Candidates: TArray<TUnitUseCandidate>;
  end;

  TUnitRelationsBuilder = class
  private
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FReader: TUsesTextReader;
    FDefines: TUsesDefinesFunc;
    FComponent: TArray<Boolean>;
    FNode: Integer;
    FDepth: Integer;
    FOutgoing: Boolean;
    FDistance: TArray<Integer>;
    FExpanded: TArray<Boolean>;
    function InComponent(ANode: Integer): Boolean;
    function EdgeBetween(ASource, ATarget: Integer; ASection: TUsesSection; out AEdge: TUsesEdge): Boolean;
    function UsesCyclePath(ATarget: Integer): string;
    function UsedByCyclePath(ASource: Integer): string;
    procedure Locate(const AEdge: TUsesEdge; var ARelation: TUnitRelation);
    function FromEdge(const AEdge: TUsesEdge; AOutgoing: Boolean): TUnitRelation;
    function Distances(AStart: Integer; AOutgoing: Boolean): TArray<Integer>;
    /// <summary>Eingehende Kanten von ANode, nach Name der verwendenden Unit, dann interface vor implementation.
    /// </summary>
    function IncomingEdges(const ANode: TUsesNode): TUsesEdges;
    /// <summary>Kinder von ARelation (Unit AOther auf Ebene ALevel + 1) oder Markierung als wiederholt.</summary>
    procedure ExpandChild(var ARelation: TUnitRelation; AOther, ALevel: Integer);
    /// <summary>Baum unter ANode auf Ebene ALevel mit FDepth, FOutgoing, FDistance und FExpanded.</summary>
    function Expand(ANode, ALevel: Integer): TArray<TUnitRelation>;
    /// <summary>Baum unter FNode; AMarkStart: FNode selbst gilt als schon ausgeklappt.</summary>
    function ExpandFrom(ADepth: Integer; AOutgoing: Boolean; const ADistance: TArray<Integer>;
      AMarkStart: Boolean): TArray<TUnitRelation>;
    procedure MarkComponent(var AResult: TUnitRelations);
    /// <summary>Bäume über ADepth Ebenen an die erste Ebene von „Verwendet“ (aus dem Text) hängen.</summary>
    procedure AttachUsesTrees(var AResult: TUnitRelations; ADepth: Integer);
    procedure MarkCycles(var AResult: TUnitRelations);
    procedure BuildFound(var AResult: TUnitRelations; ADepth: Integer);
    function TextUses(const AFileName: string): TArray<TUnitRelation>;
  public
    /// <summary>ALocator findet die Fundstellen der Kanten; AReader/ADefines lesen die uses der Unit selbst.</summary>
    constructor Create(AGraph: TUsesGraph; ALocator: TUsesLocator; const AReader: TUsesTextReader;
      const ADefines: TUsesDefinesFunc);
    /// <summary>Beziehungen der Unit in AFileName; ADepth 1 = direkt, 0 = alle Ebenen. AUnused: Namen
    /// ungenutzter Einträge der Unit.</summary>
    function Build(const AFileName: string; ADepth: Integer; const AUnused: TArray<string>): TUnitRelations;
      overload;
    /// <summary>Wie oben; AOnlyImplementation: interface-Einträge, die nur im implementation-Teil gebraucht
    /// werden (#554).</summary>
    function Build(const AFileName: string; ADepth: Integer; const AUnused,
      AOnlyImplementation: TArray<string>): TUnitRelations; overload;
    /// <summary>Kosten einer interface-Änderung der Unit in AFileName (#554); Units mit höchstens ALimit
    /// Namen.</summary>
    class function InterfaceCost(AGraph: TUsesGraph; const AFileName: string; ALimit: Integer): TUnitInterfaceCost;
      static;
    class function CostToJson(const ACost: TUnitInterfaceCost): TJSONObject; static;
    /// <summary>Units, die die Unit in AFileName verwenden, mit dem Kreis, den ihre Aufnahme schlösse (#786).
    /// </summary>
    class function UseCandidates(AGraph: TUsesGraph; const AFileName: string): TUnitUseInfo; static;
    class function UseInfoToJson(const AInfo: TUnitUseInfo): TJSONObject; static;
    /// <summary>JSON der Antwort von atlas/unitRelations (ohne "generation").</summary>
    class function ToJson(const ARelations: TUnitRelations): TJSONObject; static;
    class function SectionName(ASection: TUsesSection): string; static;
  end;

implementation

uses
  System.StrUtils,
  System.Math,
  Atlas.Common.Editing.UsesClause;

function ContainsNode(ANode: Integer; const ANodes: TArray<Integer>): Boolean;
var
  Item: Integer;
begin
  for Item in ANodes do
  begin
    if Item = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Dateiname ohne Pfad und Endung, für \ und / gleich.</summary>
function BareName(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(Result) downto 1 do
  begin
    if (Result[Index] = '\') or (Result[Index] = '/') then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  end;
  Result := ChangeFileExt(Result, '');
end;

/// <summary>Steht AName (auch mit oder ohne Namensraum geschrieben) in ANames?</summary>
function NamedIn(const AName: string; const ANames: TArray<string>): Boolean;
var
  Name: string;
begin
  for Name in ANames do
  begin
    if SameText(Name, AName) or EndsText('.' + Name, AName) or EndsText('.' + AName, Name) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TUnitRelationsBuilder }

constructor TUnitRelationsBuilder.Create(AGraph: TUsesGraph; ALocator: TUsesLocator; const AReader: TUsesTextReader;
  const ADefines: TUsesDefinesFunc);
begin
  inherited Create;
  FGraph := AGraph;
  FLocator := ALocator;
  FReader := AReader;
  FDefines := ADefines;
  FNode := -1;
end;

class function TUnitRelationsBuilder.SectionName(ASection: TUsesSection): string;
begin
  if ASection = TUsesSection.Interface_ then
  begin
    Result := 'interface';
  end
  else
  begin
    Result := 'implementation';
  end;
end;

function TUnitRelationsBuilder.InComponent(ANode: Integer): Boolean;
begin
  Result := (ANode >= 0) and (ANode <= High(FComponent)) and FComponent[ANode];
end;

function TUnitRelationsBuilder.EdgeBetween(ASource, ATarget: Integer; ASection: TUsesSection;
  out AEdge: TUsesEdge): Boolean;
var
  Edge: TUsesEdge;
begin
  for Edge in FGraph.Node(ASource).Outgoing do
  begin
    if (Edge.Target = ATarget) and (Edge.Section = ASection) then
    begin
      AEdge := Edge;
      Exit(True);
    end;
  end;
  AEdge := Default(TUsesEdge);
  Result := False;
end;

function TUnitRelationsBuilder.UsesCyclePath(ATarget: Integer): string;
var
  First: TUsesEdge;
  Back: TUsesEdges;
begin
  Result := '';
  if not EdgeBetween(FNode, ATarget, TUsesSection.Interface_, First) then
  begin
    Exit;
  end;
  if ATarget = FNode then
  begin
    Back := nil;
  end
  else
  begin
    Back := FGraph.Path(ATarget, FNode, InterfaceUsesOnly);
    if Back = nil then
    begin
      Exit;
    end;
  end;
  Result := FGraph.Describe(TUsesEdges.Create(First) + Back);
end;

function TUnitRelationsBuilder.UsedByCyclePath(ASource: Integer): string;
var
  Last: TUsesEdge;
  Forth: TUsesEdges;
begin
  Result := '';
  if not EdgeBetween(ASource, FNode, TUsesSection.Interface_, Last) then
  begin
    Exit;
  end;
  if ASource = FNode then
  begin
    Forth := nil;
  end
  else
  begin
    Forth := FGraph.Path(FNode, ASource, InterfaceUsesOnly);
    if Forth = nil then
    begin
      Exit;
    end;
  end;
  Result := FGraph.Describe(Forth + TUsesEdges.Create(Last));
end;

procedure TUnitRelationsBuilder.Locate(const AEdge: TUsesEdge; var ARelation: TUnitRelation);
var
  Location: TUsesLocation;
begin
  ARelation.Line := -1;
  ARelation.Character := -1;
  ARelation.LocationFile := '';
  if (FLocator <> nil) and FLocator.Locate(FGraph, AEdge, Location) then
  begin
    ARelation.LocationFile := Location.FileName;
    ARelation.Line := Location.Range.StartPos.Line;
    ARelation.Character := Location.Range.StartPos.Character;
  end;
end;

function TUnitRelationsBuilder.FromEdge(const AEdge: TUsesEdge; AOutgoing: Boolean): TUnitRelation;
var
  Other: Integer;
  Node: TUsesNode;
begin
  Result := Default(TUnitRelation);
  if AOutgoing then
  begin
    Other := AEdge.Target;
  end
  else
  begin
    Other := AEdge.Source;
  end;
  Node := FGraph.Node(Other);
  Result.Name := Node.UnitName;
  Result.FileName := Node.FileName;
  Result.Section := AEdge.Section;
  Result.Library_ := Node.Library_;
  Locate(AEdge, Result);
end;

function TUnitRelationsBuilder.Distances(AStart: Integer; AOutgoing: Boolean): TArray<Integer>;
var
  Queue: TQueue<Integer>;
  Current: Integer;
  Edge: TUsesEdge;
  Ref: TUsesEdgeRef;
  Node: TUsesNode;

  procedure Visit(ANext: Integer);
  begin
    if Result[ANext] >= 0 then
    begin
      Exit;
    end;
    Result[ANext] := Result[Current] + 1;
    Queue.Enqueue(ANext);
  end;

begin
  SetLength(Result, FGraph.NodeCount);
  for Current := 0 to High(Result) do
  begin
    Result[Current] := -1;
  end;
  Result[AStart] := 0;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Enqueue(AStart);
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      Node := FGraph.Node(Current);
      if AOutgoing then
      begin
        for Edge in Node.Outgoing do
        begin
          Visit(Edge.Target);
        end;
      end
      else
      begin
        for Ref in Node.Incoming do
        begin
          Visit(Ref.Source);
        end;
      end;
    end;
  finally
    Queue.Free;
  end;
end;

function TUnitRelationsBuilder.IncomingEdges(const ANode: TUsesNode): TUsesEdges;
var
  mRef: TUsesEdgeRef;
  mNames: TArray<string>;
  mIndex, mSwap: Integer;
  mTemp: TUsesEdge;
begin
  Result := nil;
  for mRef in ANode.Incoming do
  begin
    Result := Result + [FGraph.Node(mRef.Source).Outgoing[mRef.Item]];
  end;
  SetLength(mNames, Length(Result));
  for mIndex := 0 to High(Result) do
  begin
    mNames[mIndex] := LowerCase(FGraph.Node(Result[mIndex].Source).UnitName);
  end;
  // Einfügesortierung: stabil und eindeutig (Name, dann interface vor implementation).
  for mIndex := 1 to High(Result) do
  begin
    mSwap := mIndex;
    while (mSwap > 0) and ((mNames[mSwap - 1] > mNames[mSwap]) or ((mNames[mSwap - 1] = mNames[mSwap]) and
      (Ord(Result[mSwap - 1].Section) > Ord(Result[mSwap].Section)))) do
    begin
      mTemp := Result[mSwap - 1];
      Result[mSwap - 1] := Result[mSwap];
      Result[mSwap] := mTemp;
      mNames[mSwap] := mNames[mSwap - 1];
      mNames[mSwap - 1] := LowerCase(FGraph.Node(Result[mSwap - 1].Source).UnitName);
      Dec(mSwap);
    end;
  end;
end;

procedure TUnitRelationsBuilder.ExpandChild(var ARelation: TUnitRelation; AOther, ALevel: Integer);
begin
  // Kinder nur unterhalb der gewünschten Tiefe; jede Unit einmal, auf ihrer kürzesten Ebene.
  if (FDepth <> 0) and (ALevel + 1 >= FDepth) then
  begin
    Exit;
  end;
  if FExpanded[AOther] or (FDistance[AOther] <> ALevel + 1) then
  begin
    if FOutgoing then
    begin
      ARelation.Repeated := FGraph.Node(AOther).Outgoing <> nil;
    end
    else
    begin
      ARelation.Repeated := FGraph.Node(AOther).Incoming <> nil;
    end;
  end
  else
  begin
    FExpanded[AOther] := True;
    ARelation.Children := Expand(AOther, ALevel + 1);
  end;
end;

function TUnitRelationsBuilder.Expand(ANode, ALevel: Integer): TArray<TUnitRelation>;
var
  mEdge: TUsesEdge;
  mEdges: TUsesEdges;
  mSeen: TDictionary<Integer, Boolean>;
  mRelation: TUnitRelation;
  mOther: Integer;
begin
  Result := nil;
  // Kanten der Ebene: ausgehend in Quelltextreihenfolge, eingehend nach Name der verwendenden Unit.
  if FOutgoing then
  begin
    mEdges := FGraph.Node(ANode).Outgoing;
  end
  else
  begin
    mEdges := IncomingEdges(FGraph.Node(ANode));
  end;
  mSeen := TDictionary<Integer, Boolean>.Create;
  try
    for mEdge in mEdges do
    begin
      if FOutgoing then
      begin
        mOther := mEdge.Target;
      end
      else
      begin
        mOther := mEdge.Source;
      end;
      // Eine Unit, die in beiden Listen steht, nur einmal (die erste Kante).
      if mSeen.ContainsKey(mOther) then
      begin
        Continue;
      end;
      mSeen.Add(mOther, True);
      mRelation := FromEdge(mEdge, FOutgoing);
      ExpandChild(mRelation, mOther, ALevel);
      Result := Result + [mRelation];
    end;
  finally
    mSeen.Free;
  end;
end;

function TUnitRelationsBuilder.ExpandFrom(ADepth: Integer; AOutgoing: Boolean; const ADistance: TArray<Integer>;
  AMarkStart: Boolean): TArray<TUnitRelation>;
begin
  FDepth := ADepth;
  FOutgoing := AOutgoing;
  FDistance := ADistance;
  FExpanded := nil;
  SetLength(FExpanded, FGraph.NodeCount);
  FExpanded[FNode] := AMarkStart;
  Result := Expand(FNode, 0);
end;

function TUnitRelationsBuilder.TextUses(const AFileName: string): TArray<TUnitRelation>;
var
  Text: string;
  Defines: TArray<string>;
  Reference: TUsesReference;
  Relation: TUnitRelation;
  Target: Integer;
  Node: TUsesNode;
begin
  Result := nil;
  if not (Assigned(FReader) and FReader(AFileName, Text)) then
  begin
    Exit;
  end;
  Defines := nil;
  if Assigned(FDefines) then
  begin
    Defines := FDefines(AFileName);
  end;
  for Reference in TUsesLocator.UsesReferences(Text, Defines) do
  begin
    Relation := Default(TUnitRelation);
    Relation.Name := Reference.Name;
    if Reference.InInterface then
    begin
      Relation.Section := TUsesSection.Interface_;
    end
    else
    begin
      Relation.Section := TUsesSection.Implementation_;
    end;
    Relation.LocationFile := AFileName;
    Relation.Line := Reference.Range.StartPos.Line;
    Relation.Character := Reference.Range.StartPos.Character;
    Relation.Library_ := True;
    Target := FGraph.IndexOf(Reference.Name);
    if Target >= 0 then
    begin
      Node := FGraph.Node(Target);
      Relation.Name := Node.UnitName;
      Relation.FileName := Node.FileName;
      Relation.Library_ := Node.Library_;
    end;
    Result := Result + [Relation];
  end;
end;

function TUnitRelationsBuilder.Build(const AFileName: string; ADepth: Integer;
  const AUnused: TArray<string>): TUnitRelations;
begin
  Result := Build(AFileName, ADepth, AUnused, nil);
end;

procedure TUnitRelationsBuilder.MarkComponent(var AResult: TUnitRelations);
var
  mCycle: TUsesCycle;
  mMember: Integer;
begin
  for mCycle in FGraph.Cycles(InterfaceUsesOnly) do
  begin
    if ContainsNode(FNode, mCycle.Component) then
    begin
      for mMember in mCycle.Component do
      begin
        FComponent[mMember] := True;
      end;
      AResult.InCycle := True;
    end;
  end;
end;

procedure TUnitRelationsBuilder.AttachUsesTrees(var AResult: TUnitRelations; ADepth: Integer);
var
  mIndex, mChild, mTarget: Integer;
  mTree: TArray<TUnitRelation>;
begin
  mTree := ExpandFrom(ADepth, True, Distances(FNode, True), True);
  for mIndex := 0 to High(AResult.Uses_) do
  begin
    mTarget := FGraph.IndexOf(AResult.Uses_[mIndex].Name);
    if mTarget < 0 then
    begin
      Continue;
    end;
    for mChild := 0 to High(mTree) do
    begin
      if SameText(mTree[mChild].Name, FGraph.Node(mTarget).UnitName) then
      begin
        AResult.Uses_[mIndex].Children := mTree[mChild].Children;
        AResult.Uses_[mIndex].Repeated := mTree[mChild].Repeated;
        // Steht die Unit in beiden Listen, gehört der Baum zum ersten Eintrag.
        mTree[mChild].Name := '';
        Break;
      end;
    end;
  end;
end;

/// <summary>Kreispfade der interface-Einträge, die im Kreis der Unit liegen.</summary>
procedure TUnitRelationsBuilder.MarkCycles(var AResult: TUnitRelations);
var
  mIndex, mMember: Integer;
begin
  for mIndex := 0 to High(AResult.UsedBy) do
  begin
    mMember := FGraph.IndexOfFile(AResult.UsedBy[mIndex].FileName);
    if (AResult.UsedBy[mIndex].Section = TUsesSection.Interface_) and InComponent(mMember) then
    begin
      AResult.UsedBy[mIndex].CyclePath := UsedByCyclePath(mMember);
      AResult.UsedBy[mIndex].Cycle := AResult.UsedBy[mIndex].CyclePath <> '';
    end;
  end;
  for mIndex := 0 to High(AResult.Uses_) do
  begin
    mMember := FGraph.IndexOf(AResult.Uses_[mIndex].Name);
    if (AResult.Uses_[mIndex].Section = TUsesSection.Interface_) and InComponent(mMember) then
    begin
      AResult.Uses_[mIndex].CyclePath := UsesCyclePath(mMember);
      AResult.Uses_[mIndex].Cycle := AResult.Uses_[mIndex].CyclePath <> '';
      if AResult.CyclePath = '' then
      begin
        AResult.CyclePath := AResult.Uses_[mIndex].CyclePath;
      end;
    end;
  end;
end;

/// <summary>Beziehungen einer Unit, die im Graphen steht.</summary>
procedure TUnitRelationsBuilder.BuildFound(var AResult: TUnitRelations; ADepth: Integer);
var
  mNode: TUsesNode;
  mDistance: TArray<Integer>;
begin
  mNode := FGraph.Node(FNode);
  AResult.Found := True;
  AResult.UnitName := mNode.UnitName;
  AResult.FileName := mNode.FileName;
  MarkComponent(AResult);
  AResult.RecompileCount := FGraph.RecompileCount(FNode);
  AResult.DependencyCount := Length(FGraph.Dependencies(FNode, AllUsesSections));
  AResult.DependentCount := Length(FGraph.Dependents(FNode, AllUsesSections));
  // Ohne lesbaren Text: die Kanten des Graphen.
  if (AResult.Uses_ = nil) and (mNode.Outgoing <> nil) then
  begin
    SetLength(mDistance, FGraph.NodeCount);
    AResult.Uses_ := ExpandFrom(1, True, mDistance, False);
  end;
  // Bäume über alle bzw. ADepth Ebenen; die erste Ebene von „Verwendet“ bleibt die aus dem Text.
  if ADepth <> 1 then
  begin
    AttachUsesTrees(AResult, ADepth);
    mDistance := Distances(FNode, False);
  end
  else
  begin
    // Nur direkt: Expand baut keine Kinder, die Abstände zählen nicht.
    mDistance := nil;
    SetLength(mDistance, FGraph.NodeCount);
  end;
  AResult.UsedBy := ExpandFrom(ADepth, False, mDistance, True);
  MarkCycles(AResult);
end;

function TUnitRelationsBuilder.Build(const AFileName: string; ADepth: Integer; const AUnused,
  AOnlyImplementation: TArray<string>): TUnitRelations;
var
  mIndex, mDepth: Integer;
begin
  Result := Default(TUnitRelations);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  mDepth := ADepth;
  if mDepth < 0 then
  begin
    mDepth := 1;
  end;
  FNode := FGraph.IndexOfFile(AFileName);
  FComponent := nil;
  SetLength(FComponent, FGraph.NodeCount);
  // „Verwendet“ aus dem Text der Unit selbst, so fehlen auch Units ohne Quelltext nicht.
  Result.Uses_ := TextUses(AFileName);
  if FNode >= 0 then
  begin
    BuildFound(Result, mDepth);
  end;
  for mIndex := 0 to High(Result.Uses_) do
  begin
    Result.Uses_[mIndex].Unused := NamedIn(Result.Uses_[mIndex].Name, AUnused);
    Result.Uses_[mIndex].OnlyImplementation := (Result.Uses_[mIndex].Section = TUsesSection.Interface_) and
      NamedIn(Result.Uses_[mIndex].Name, AOnlyImplementation);
  end;
end;

class function TUnitRelationsBuilder.InterfaceCost(AGraph: TUsesGraph; const AFileName: string;
  ALimit: Integer): TUnitInterfaceCost;
var
  Node, Index: Integer;
  Units: TArray<Integer>;
begin
  Result := Default(TUnitInterfaceCost);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  Node := AGraph.IndexOfFile(AFileName);
  if Node < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.UnitName := AGraph.Node(Node).UnitName;
  Result.FileName := AGraph.Node(Node).FileName;
  // RecompileSet ist schon nach Name sortiert.
  Units := AGraph.RecompileSet(Node);
  Result.RecompileCount := Length(Units);
  SetLength(Result.Units, Min(Max(ALimit, 0), Length(Units)));
  for Index := 0 to High(Result.Units) do
  begin
    Result.Units[Index] := AGraph.Node(Units[Index]).UnitName;
  end;
end;

class function TUnitRelationsBuilder.CostToJson(const ACost: TUnitInterfaceCost): TJSONObject;
var
  List: TJSONArray;
  Name: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(ACost.Found));
  Result.AddPair('unit', ACost.UnitName);
  Result.AddPair('file', ACost.FileName);
  Result.AddPair('recompileCount', TJSONNumber.Create(ACost.RecompileCount));
  List := TJSONArray.Create;
  for Name in ACost.Units do
  begin
    List.Add(Name);
  end;
  Result.AddPair('units', List);
end;

/// <summary>Nächster Schritt zur Unit ATarget je Knoten (Rückwärtssuche über die eingehenden Kanten); -1 =
/// erreicht ATarget nicht, ATarget selbst trägt sich ein.</summary>
function NextTowards(AGraph: TUsesGraph; ATarget: Integer; AInterfaceOnly: Boolean): TArray<Integer>;
var
  Queue: TQueue<Integer>;
  Current: Integer;
  Ref: TUsesEdgeRef;
  Source: TUsesNode;
begin
  SetLength(Result, AGraph.NodeCount);
  for Current := 0 to High(Result) do
  begin
    Result[Current] := -1;
  end;
  Result[ATarget] := ATarget;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Enqueue(ATarget);
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      for Ref in AGraph.Node(Current).Incoming do
      begin
        Source := AGraph.Node(Ref.Source);
        if not Source.Active or (Result[Ref.Source] >= 0) then
        begin
          Continue;
        end;
        if AInterfaceOnly and (Source.Outgoing[Ref.Item].Section <> TUsesSection.Interface_) then
        begin
          Continue;
        end;
        Result[Ref.Source] := Current;
        Queue.Enqueue(Ref.Source);
      end;
    end;
  finally
    Queue.Free;
  end;
end;

/// <summary>"Ziel → X → … → Ziel" über die Schritte ANext; '' ohne Weg.</summary>
function CirclePath(AGraph: TUsesGraph; ATarget, AStart: Integer; const ANext: TArray<Integer>): string;
var
  Node: Integer;
begin
  Result := '';
  if (AStart = ATarget) or (ANext[AStart] < 0) then
  begin
    Exit;
  end;
  Result := AGraph.Node(ATarget).UnitName;
  Node := AStart;
  while Node <> ATarget do
  begin
    Result := Result + ' → ' + AGraph.Node(Node).UnitName;
    Node := ANext[Node];
  end;
  Result := Result + ' → ' + AGraph.Node(ATarget).UnitName;
end;

class function TUnitRelationsBuilder.UseCandidates(AGraph: TUsesGraph; const AFileName: string): TUnitUseInfo;
var
  Target, Node: Integer;
  ByInterface, ByAny, Order: TArray<Integer>;
  Candidate: TUnitUseCandidate;
begin
  Result := Default(TUnitUseInfo);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  Target := AGraph.IndexOfFile(AFileName);
  if Target < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.UnitName := AGraph.Node(Target).UnitName;
  Result.FileName := AGraph.Node(Target).FileName;
  ByInterface := NextTowards(AGraph, Target, True);
  ByAny := NextTowards(AGraph, Target, False);
  // Nach Name: dieselbe Reihenfolge wie die übrigen Listen des Graphen.
  Order := AGraph.Dependents(Target, AllUsesSections);
  for Node in Order do
  begin
    if ByAny[Node] < 0 then
    begin
      Continue;
    end;
    Candidate := Default(TUnitUseCandidate);
    Candidate.Name := AGraph.Node(Node).UnitName;
    Candidate.FileName := AGraph.Node(Node).FileName;
    Candidate.InterfacePath := CirclePath(AGraph, Target, Node, ByInterface);
    Candidate.Path := CirclePath(AGraph, Target, Node, ByAny);
    Result.Candidates := Result.Candidates + [Candidate];
  end;
end;

class function TUnitRelationsBuilder.UseInfoToJson(const AInfo: TUnitUseInfo): TJSONObject;
var
  List: TJSONArray;
  Candidate: TUnitUseCandidate;
  Item: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(AInfo.Found));
  Result.AddPair('unit', AInfo.UnitName);
  Result.AddPair('file', AInfo.FileName);
  List := TJSONArray.Create;
  for Candidate in AInfo.Candidates do
  begin
    Item := TJSONObject.Create;
    Item.AddPair('name', Candidate.Name);
    if Candidate.FileName <> '' then
    begin
      Item.AddPair('file', Candidate.FileName);
    end;
    if Candidate.InterfacePath <> '' then
    begin
      Item.AddPair('interfacePath', Candidate.InterfacePath);
    end;
    Item.AddPair('path', Candidate.Path);
    List.AddElement(Item);
  end;
  Result.AddPair('cycles', List);
end;

function RelationJson(const ARelation: TUnitRelation): TJSONObject;
var
  Children: TJSONArray;
  Child: TUnitRelation;
  Location: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ARelation.Name);
  if ARelation.FileName <> '' then
  begin
    Result.AddPair('file', ARelation.FileName);
  end;
  Result.AddPair('section', TUnitRelationsBuilder.SectionName(ARelation.Section));
  if ARelation.Library_ then
  begin
    Result.AddPair('library', TJSONBool.Create(True));
  end;
  if ARelation.Cycle then
  begin
    Result.AddPair('cycle', TJSONBool.Create(True));
    Result.AddPair('cyclePath', ARelation.CyclePath);
  end;
  if ARelation.Unused then
  begin
    Result.AddPair('unused', TJSONBool.Create(True));
  end;
  if ARelation.OnlyImplementation then
  begin
    Result.AddPair('onlyImplementation', TJSONBool.Create(True));
  end;
  if ARelation.Repeated then
  begin
    Result.AddPair('repeated', TJSONBool.Create(True));
  end;
  if ARelation.Line >= 0 then
  begin
    Location := TJSONObject.Create;
    Location.AddPair('file', ARelation.LocationFile);
    Location.AddPair('line', TJSONNumber.Create(ARelation.Line));
    Location.AddPair('character', TJSONNumber.Create(ARelation.Character));
    Result.AddPair('location', Location);
  end;
  if ARelation.Children <> nil then
  begin
    Children := TJSONArray.Create;
    for Child in ARelation.Children do
    begin
      Children.AddElement(RelationJson(Child));
    end;
    Result.AddPair('children', Children);
  end;
end;

class function TUnitRelationsBuilder.ToJson(const ARelations: TUnitRelations): TJSONObject;
var
  List: TJSONArray;
  Relation: TUnitRelation;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(ARelations.Found));
  Result.AddPair('unit', ARelations.UnitName);
  Result.AddPair('file', ARelations.FileName);
  Result.AddPair('recompileCount', TJSONNumber.Create(ARelations.RecompileCount));
  Result.AddPair('dependencies', TJSONNumber.Create(ARelations.DependencyCount));
  Result.AddPair('dependents', TJSONNumber.Create(ARelations.DependentCount));
  Result.AddPair('inCycle', TJSONBool.Create(ARelations.InCycle));
  if ARelations.CyclePath <> '' then
  begin
    Result.AddPair('cyclePath', ARelations.CyclePath);
  end;
  List := TJSONArray.Create;
  for Relation in ARelations.Uses_ do
  begin
    List.AddElement(RelationJson(Relation));
  end;
  Result.AddPair('uses', List);
  List := TJSONArray.Create;
  for Relation in ARelations.UsedBy do
  begin
    List.AddElement(RelationJson(Relation));
  end;
  Result.AddPair('usedBy', List);
end;

end.
