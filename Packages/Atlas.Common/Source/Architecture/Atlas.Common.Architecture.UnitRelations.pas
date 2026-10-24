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

  TUnitRelationsBuilder = class
  private
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FReader: TUsesTextReader;
    FDefines: TUsesDefinesFunc;
    FComponent: TArray<Boolean>;
    FNode: Integer;
    function InComponent(ANode: Integer): Boolean;
    function EdgeBetween(ASource, ATarget: Integer; ASection: TUsesSection; out AEdge: TUsesEdge): Boolean;
    function UsesCyclePath(ATarget: Integer): string;
    function UsedByCyclePath(ASource: Integer): string;
    procedure Locate(const AEdge: TUsesEdge; var ARelation: TUnitRelation);
    function FromEdge(const AEdge: TUsesEdge; AOutgoing: Boolean): TUnitRelation;
    function Distances(AStart: Integer; AOutgoing: Boolean): TArray<Integer>;
    function Expand(ANode, ALevel, ADepth: Integer; AOutgoing: Boolean; const ADistance: TArray<Integer>;
      var AExpanded: TArray<Boolean>): TArray<TUnitRelation>;
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
    if Item = ANode then
      Exit(True);
  Result := False;
end;

/// <summary>Dateiname ohne Pfad und Endung, für \ und / gleich.</summary>
function BareName(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := AFileName;
  for Index := Length(Result) downto 1 do
    if (Result[Index] = '\') or (Result[Index] = '/') then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  Result := ChangeFileExt(Result, '');
end;

/// <summary>Steht AName (auch mit oder ohne Namensraum geschrieben) in ANames?</summary>
function NamedIn(const AName: string; const ANames: TArray<string>): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) or EndsText('.' + Name, AName) or EndsText('.' + AName, Name) then
      Exit(True);
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
    Result := 'interface'
  else
    Result := 'implementation';
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
    if (Edge.Target = ATarget) and (Edge.Section = ASection) then
    begin
      AEdge := Edge;
      Exit(True);
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
    Exit;
  if ATarget = FNode then
    Back := nil
  else
  begin
    Back := FGraph.Path(ATarget, FNode, InterfaceUsesOnly);
    if Back = nil then
      Exit;
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
    Exit;
  if ASource = FNode then
    Forth := nil
  else
  begin
    Forth := FGraph.Path(FNode, ASource, InterfaceUsesOnly);
    if Forth = nil then
      Exit;
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
    Other := AEdge.Target
  else
    Other := AEdge.Source;
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
      Exit;
    Result[ANext] := Result[Current] + 1;
    Queue.Enqueue(ANext);
  end;

begin
  SetLength(Result, FGraph.NodeCount);
  for Current := 0 to High(Result) do
    Result[Current] := -1;
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
          Visit(Edge.Target);
      end
      else
        for Ref in Node.Incoming do
          Visit(Ref.Source);
    end;
  finally
    Queue.Free;
  end;
end;

function TUnitRelationsBuilder.Expand(ANode, ALevel, ADepth: Integer; AOutgoing: Boolean;
  const ADistance: TArray<Integer>; var AExpanded: TArray<Boolean>): TArray<TUnitRelation>;
var
  Node: TUsesNode;
  Edge: TUsesEdge;
  Ref: TUsesEdgeRef;
  Edges: TUsesEdges;
  Seen: TDictionary<Integer, Boolean>;
  Relation: TUnitRelation;
  Other: Integer;
  Names: TArray<string>;
  Index, Swap: Integer;
  Temp: TUsesEdge;
begin
  Result := nil;
  Node := FGraph.Node(ANode);
  // Kanten der Ebene: ausgehend in Quelltextreihenfolge, eingehend nach Name der verwendenden Unit.
  Edges := nil;
  if AOutgoing then
    Edges := Node.Outgoing
  else
  begin
    for Ref in Node.Incoming do
      Edges := Edges + [FGraph.Node(Ref.Source).Outgoing[Ref.Item]];
    SetLength(Names, Length(Edges));
    for Index := 0 to High(Edges) do
      Names[Index] := LowerCase(FGraph.Node(Edges[Index].Source).UnitName);
    // Einfügesortierung: stabil und eindeutig (Name, dann interface vor implementation).
    for Index := 1 to High(Edges) do
    begin
      Swap := Index;
      while (Swap > 0) and ((Names[Swap - 1] > Names[Swap]) or ((Names[Swap - 1] = Names[Swap]) and
        (Ord(Edges[Swap - 1].Section) > Ord(Edges[Swap].Section)))) do
      begin
        Temp := Edges[Swap - 1];
        Edges[Swap - 1] := Edges[Swap];
        Edges[Swap] := Temp;
        Names[Swap] := Names[Swap - 1];
        Names[Swap - 1] := LowerCase(FGraph.Node(Edges[Swap - 1].Source).UnitName);
        Dec(Swap);
      end;
    end;
  end;
  Seen := TDictionary<Integer, Boolean>.Create;
  try
    for Edge in Edges do
    begin
      if AOutgoing then
        Other := Edge.Target
      else
        Other := Edge.Source;
      // Eine Unit, die in beiden Listen steht, nur einmal (die erste Kante).
      if Seen.ContainsKey(Other) then
        Continue;
      Seen.Add(Other, True);
      Relation := FromEdge(Edge, AOutgoing);
      // Kinder nur unterhalb der gewünschten Tiefe; jede Unit einmal, auf ihrer kürzesten Ebene.
      if (ADepth = 0) or (ALevel + 1 < ADepth) then
      begin
        if AExpanded[Other] or (ADistance[Other] <> ALevel + 1) then
        begin
          if AOutgoing then
            Relation.Repeated := FGraph.Node(Other).Outgoing <> nil
          else
            Relation.Repeated := FGraph.Node(Other).Incoming <> nil;
        end
        else
        begin
          AExpanded[Other] := True;
          Relation.Children := Expand(Other, ALevel + 1, ADepth, AOutgoing, ADistance, AExpanded);
        end;
      end;
      Result := Result + [Relation];
    end;
  finally
    Seen.Free;
  end;
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
    Exit;
  Defines := nil;
  if Assigned(FDefines) then
    Defines := FDefines(AFileName);
  for Reference in TUsesLocator.UsesReferences(Text, Defines) do
  begin
    Relation := Default(TUnitRelation);
    Relation.Name := Reference.Name;
    if Reference.InInterface then
      Relation.Section := TUsesSection.Interface_
    else
      Relation.Section := TUsesSection.Implementation_;
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

function TUnitRelationsBuilder.Build(const AFileName: string; ADepth: Integer; const AUnused,
  AOnlyImplementation: TArray<string>): TUnitRelations;
var
  Cycle: TUsesCycle;
  Member, Index, Child, Target: Integer;
  Expanded: TArray<Boolean>;
  Distance: TArray<Integer>;
  Tree: TArray<TUnitRelation>;
  Node: TUsesNode;
begin
  Result := Default(TUnitRelations);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  if ADepth < 0 then
    ADepth := 1;
  FNode := FGraph.IndexOfFile(AFileName);
  FComponent := nil;
  SetLength(FComponent, FGraph.NodeCount);
  // „Verwendet“ aus dem Text der Unit selbst, so fehlen auch Units ohne Quelltext nicht.
  Result.Uses_ := TextUses(AFileName);
  if FNode >= 0 then
  begin
    Node := FGraph.Node(FNode);
    Result.Found := True;
    Result.UnitName := Node.UnitName;
    Result.FileName := Node.FileName;
    for Cycle in FGraph.Cycles(InterfaceUsesOnly) do
      if ContainsNode(FNode, Cycle.Component) then
      begin
        for Member in Cycle.Component do
          FComponent[Member] := True;
        Result.InCycle := True;
      end;
    Result.RecompileCount := FGraph.RecompileCount(FNode);
    Result.DependencyCount := Length(FGraph.Dependencies(FNode, AllUsesSections));
    Result.DependentCount := Length(FGraph.Dependents(FNode, AllUsesSections));
    // Ohne lesbaren Text: die Kanten des Graphen.
    if (Result.Uses_ = nil) and (Node.Outgoing <> nil) then
    begin
      SetLength(Distance, FGraph.NodeCount);
      SetLength(Expanded, FGraph.NodeCount);
      Result.Uses_ := Expand(FNode, 0, 1, True, Distance, Expanded);
    end;
    // Bäume über alle bzw. ADepth Ebenen; die erste Ebene von „Verwendet“ bleibt die aus dem Text.
    if ADepth <> 1 then
    begin
      Distance := Distances(FNode, True);
      Expanded := nil;
      SetLength(Expanded, FGraph.NodeCount);
      Expanded[FNode] := True;
      Tree := Expand(FNode, 0, ADepth, True, Distance, Expanded);
      for Index := 0 to High(Result.Uses_) do
      begin
        Target := FGraph.IndexOf(Result.Uses_[Index].Name);
        for Child := 0 to High(Tree) do
          if (Target >= 0) and SameText(Tree[Child].Name, FGraph.Node(Target).UnitName) then
          begin
            Result.Uses_[Index].Children := Tree[Child].Children;
            Result.Uses_[Index].Repeated := Tree[Child].Repeated;
            // Steht die Unit in beiden Listen, gehört der Baum zum ersten Eintrag.
            Tree[Child].Name := '';
            Break;
          end;
      end;
    end;
    if ADepth <> 1 then
      Distance := Distances(FNode, False)
    else
    begin
      // Nur direkt: Expand baut keine Kinder, die Abstände zählen nicht.
      Distance := nil;
      SetLength(Distance, FGraph.NodeCount);
    end;
    Expanded := nil;
    SetLength(Expanded, FGraph.NodeCount);
    Expanded[FNode] := True;
    Result.UsedBy := Expand(FNode, 0, ADepth, False, Distance, Expanded);
    for Index := 0 to High(Result.UsedBy) do
    begin
      Member := FGraph.IndexOfFile(Result.UsedBy[Index].FileName);
      if (Result.UsedBy[Index].Section = TUsesSection.Interface_) and InComponent(Member) then
      begin
        Result.UsedBy[Index].CyclePath := UsedByCyclePath(Member);
        Result.UsedBy[Index].Cycle := Result.UsedBy[Index].CyclePath <> '';
      end;
    end;
    for Index := 0 to High(Result.Uses_) do
    begin
      Target := FGraph.IndexOf(Result.Uses_[Index].Name);
      if (Result.Uses_[Index].Section = TUsesSection.Interface_) and InComponent(Target) then
      begin
        Result.Uses_[Index].CyclePath := UsesCyclePath(Target);
        Result.Uses_[Index].Cycle := Result.Uses_[Index].CyclePath <> '';
        if Result.CyclePath = '' then
          Result.CyclePath := Result.Uses_[Index].CyclePath;
      end;
    end;
  end;
  for Index := 0 to High(Result.Uses_) do
  begin
    Result.Uses_[Index].Unused := NamedIn(Result.Uses_[Index].Name, AUnused);
    Result.Uses_[Index].OnlyImplementation := (Result.Uses_[Index].Section = TUsesSection.Interface_) and
      NamedIn(Result.Uses_[Index].Name, AOnlyImplementation);
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
    Exit;
  Result.Found := True;
  Result.UnitName := AGraph.Node(Node).UnitName;
  Result.FileName := AGraph.Node(Node).FileName;
  // RecompileSet ist schon nach Name sortiert.
  Units := AGraph.RecompileSet(Node);
  Result.RecompileCount := Length(Units);
  SetLength(Result.Units, Min(Max(ALimit, 0), Length(Units)));
  for Index := 0 to High(Result.Units) do
    Result.Units[Index] := AGraph.Node(Units[Index]).UnitName;
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
    List.Add(Name);
  Result.AddPair('units', List);
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
    Result.AddPair('file', ARelation.FileName);
  Result.AddPair('section', TUnitRelationsBuilder.SectionName(ARelation.Section));
  if ARelation.Library_ then
    Result.AddPair('library', TJSONBool.Create(True));
  if ARelation.Cycle then
  begin
    Result.AddPair('cycle', TJSONBool.Create(True));
    Result.AddPair('cyclePath', ARelation.CyclePath);
  end;
  if ARelation.Unused then
    Result.AddPair('unused', TJSONBool.Create(True));
  if ARelation.OnlyImplementation then
    Result.AddPair('onlyImplementation', TJSONBool.Create(True));
  if ARelation.Repeated then
    Result.AddPair('repeated', TJSONBool.Create(True));
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
      Children.AddElement(RelationJson(Child));
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
    Result.AddPair('cyclePath', ARelations.CyclePath);
  List := TJSONArray.Create;
  for Relation in ARelations.Uses_ do
    List.AddElement(RelationJson(Relation));
  Result.AddPair('uses', List);
  List := TJSONArray.Create;
  for Relation in ARelations.UsedBy do
    List.AddElement(RelationJson(Relation));
  Result.AddPair('usedBy', List);
end;

end.
