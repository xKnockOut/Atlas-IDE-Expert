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
  mItem: Integer;
begin
  for mItem in ANodes do
  begin
    if mItem = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Dateiname ohne Pfad und Endung, für \ und / gleich.</summary>
function BareName(const AFileName: string): string;
var
  mIndex: Integer;
begin
  Result := AFileName;
  for mIndex := Length(Result) downto 1 do
  begin
    if (Result[mIndex] = '\') or (Result[mIndex] = '/') then
    begin
      Result := Copy(Result, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  Result := ChangeFileExt(Result, '');
end;

/// <summary>Steht AName (auch mit oder ohne Namensraum geschrieben) in ANames?</summary>
function NamedIn(const AName: string; const ANames: TArray<string>): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) or EndsText('.' + mName, AName) or EndsText('.' + AName, mName) then
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
  mEdge: TUsesEdge;
begin
  for mEdge in FGraph.Node(ASource).Outgoing do
  begin
    if (mEdge.Target = ATarget) and (mEdge.Section = ASection) then
    begin
      AEdge := mEdge;
      Exit(True);
    end;
  end;
  AEdge := Default(TUsesEdge);
  Result := False;
end;

function TUnitRelationsBuilder.UsesCyclePath(ATarget: Integer): string;
var
  mFirst: TUsesEdge;
  mBack: TUsesEdges;
begin
  Result := '';
  if not EdgeBetween(FNode, ATarget, TUsesSection.Interface_, mFirst) then
  begin
    Exit;
  end;
  if ATarget = FNode then
  begin
    mBack := nil;
  end
  else
  begin
    mBack := FGraph.Path(ATarget, FNode, cInterfaceUsesOnly);
    if mBack = nil then
    begin
      Exit;
    end;
  end;
  Result := FGraph.Describe(TUsesEdges.Create(mFirst) + mBack);
end;

function TUnitRelationsBuilder.UsedByCyclePath(ASource: Integer): string;
var
  mLast: TUsesEdge;
  mForth: TUsesEdges;
begin
  Result := '';
  if not EdgeBetween(ASource, FNode, TUsesSection.Interface_, mLast) then
  begin
    Exit;
  end;
  if ASource = FNode then
  begin
    mForth := nil;
  end
  else
  begin
    mForth := FGraph.Path(FNode, ASource, cInterfaceUsesOnly);
    if mForth = nil then
    begin
      Exit;
    end;
  end;
  Result := FGraph.Describe(mForth + TUsesEdges.Create(mLast));
end;

procedure TUnitRelationsBuilder.Locate(const AEdge: TUsesEdge; var ARelation: TUnitRelation);
var
  mLocation: TUsesLocation;
begin
  ARelation.Line := -1;
  ARelation.Character := -1;
  ARelation.LocationFile := '';
  if (FLocator <> nil) and FLocator.Locate(FGraph, AEdge, mLocation) then
  begin
    ARelation.LocationFile := mLocation.FileName;
    ARelation.Line := mLocation.Range.StartPos.Line;
    ARelation.Character := mLocation.Range.StartPos.Character;
  end;
end;

function TUnitRelationsBuilder.FromEdge(const AEdge: TUsesEdge; AOutgoing: Boolean): TUnitRelation;
var
  mOther: Integer;
  mNode: TUsesNode;
begin
  Result := Default(TUnitRelation);
  if AOutgoing then
  begin
    mOther := AEdge.Target;
  end
  else
  begin
    mOther := AEdge.Source;
  end;
  mNode := FGraph.Node(mOther);
  Result.Name := mNode.UnitName;
  Result.FileName := mNode.FileName;
  Result.Section := AEdge.Section;
  Result.Library_ := mNode.Library_;
  Locate(AEdge, Result);
end;

function TUnitRelationsBuilder.Distances(AStart: Integer; AOutgoing: Boolean): TArray<Integer>;
var
  mQueue: TQueue<Integer>;
  mCurrent: Integer;
  mEdge: TUsesEdge;
  mRef: TUsesEdgeRef;
  mNode: TUsesNode;

  procedure Visit(ANext: Integer);
  begin
    if Result[ANext] >= 0 then
    begin
      Exit;
    end;
    Result[ANext] := Result[mCurrent] + 1;
    mQueue.Enqueue(ANext);
  end;

begin
  SetLength(Result, FGraph.NodeCount);
  for mCurrent := 0 to High(Result) do
  begin
    Result[mCurrent] := -1;
  end;
  Result[AStart] := 0;
  mQueue := TQueue<Integer>.Create;
  try
    mQueue.Enqueue(AStart);
    while mQueue.Count > 0 do
    begin
      mCurrent := mQueue.Dequeue;
      mNode := FGraph.Node(mCurrent);
      if AOutgoing then
      begin
        for mEdge in mNode.Outgoing do
        begin
          Visit(mEdge.Target);
        end;
      end
      else
      begin
        for mRef in mNode.Incoming do
        begin
          Visit(mRef.Source);
        end;
      end;
    end;
  finally
    mQueue.Free;
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
  mText: string;
  mDefines: TArray<string>;
  mReference: TUsesReference;
  mRelation: TUnitRelation;
  mTarget: Integer;
  mNode: TUsesNode;
begin
  Result := nil;
  if not (Assigned(FReader) and FReader(AFileName, mText)) then
  begin
    Exit;
  end;
  mDefines := nil;
  if Assigned(FDefines) then
  begin
    mDefines := FDefines(AFileName);
  end;
  for mReference in TUsesLocator.UsesReferences(mText, mDefines) do
  begin
    mRelation := Default(TUnitRelation);
    mRelation.Name := mReference.Name;
    if mReference.InInterface then
    begin
      mRelation.Section := TUsesSection.Interface_;
    end
    else
    begin
      mRelation.Section := TUsesSection.Implementation_;
    end;
    mRelation.LocationFile := AFileName;
    mRelation.Line := mReference.Range.StartPos.Line;
    mRelation.Character := mReference.Range.StartPos.Character;
    mRelation.Library_ := True;
    mTarget := FGraph.IndexOf(mReference.Name);
    if mTarget >= 0 then
    begin
      mNode := FGraph.Node(mTarget);
      mRelation.Name := mNode.UnitName;
      mRelation.FileName := mNode.FileName;
      mRelation.Library_ := mNode.Library_;
    end;
    Result := Result + [mRelation];
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
  for mCycle in FGraph.Cycles(cInterfaceUsesOnly) do
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
  AResult.DependencyCount := Length(FGraph.Dependencies(FNode, cAllUsesSections));
  AResult.DependentCount := Length(FGraph.Dependents(FNode, cAllUsesSections));
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
  mNode, mIndex: Integer;
  mUnits: TArray<Integer>;
begin
  Result := Default(TUnitInterfaceCost);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  mNode := AGraph.IndexOfFile(AFileName);
  if mNode < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.UnitName := AGraph.Node(mNode).UnitName;
  Result.FileName := AGraph.Node(mNode).FileName;
  // RecompileSet ist schon nach Name sortiert.
  mUnits := AGraph.RecompileSet(mNode);
  Result.RecompileCount := Length(mUnits);
  SetLength(Result.Units, Min(Max(ALimit, 0), Length(mUnits)));
  for mIndex := 0 to High(Result.Units) do
  begin
    Result.Units[mIndex] := AGraph.Node(mUnits[mIndex]).UnitName;
  end;
end;

class function TUnitRelationsBuilder.CostToJson(const ACost: TUnitInterfaceCost): TJSONObject;
var
  mList: TJSONArray;
  mName: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(ACost.Found));
  Result.AddPair('unit', ACost.UnitName);
  Result.AddPair('file', ACost.FileName);
  Result.AddPair('recompileCount', TJSONNumber.Create(ACost.RecompileCount));
  mList := TJSONArray.Create;
  for mName in ACost.Units do
  begin
    mList.Add(mName);
  end;
  Result.AddPair('units', mList);
end;

/// <summary>Nächster Schritt zur Unit ATarget je Knoten (Rückwärtssuche über die eingehenden Kanten); -1 =
/// erreicht ATarget nicht, ATarget selbst trägt sich ein.</summary>
function NextTowards(AGraph: TUsesGraph; ATarget: Integer; AInterfaceOnly: Boolean): TArray<Integer>;
var
  mQueue: TQueue<Integer>;
  mCurrent: Integer;
  mRef: TUsesEdgeRef;
  mSource: TUsesNode;
begin
  SetLength(Result, AGraph.NodeCount);
  for mCurrent := 0 to High(Result) do
  begin
    Result[mCurrent] := -1;
  end;
  Result[ATarget] := ATarget;
  mQueue := TQueue<Integer>.Create;
  try
    mQueue.Enqueue(ATarget);
    while mQueue.Count > 0 do
    begin
      mCurrent := mQueue.Dequeue;
      for mRef in AGraph.Node(mCurrent).Incoming do
      begin
        mSource := AGraph.Node(mRef.Source);
        if not mSource.Active or (Result[mRef.Source] >= 0) then
        begin
          Continue;
        end;
        if AInterfaceOnly and (mSource.Outgoing[mRef.Item].Section <> TUsesSection.Interface_) then
        begin
          Continue;
        end;
        Result[mRef.Source] := mCurrent;
        mQueue.Enqueue(mRef.Source);
      end;
    end;
  finally
    mQueue.Free;
  end;
end;

/// <summary>"Ziel → X → … → Ziel" über die Schritte ANext; '' ohne Weg.</summary>
function CirclePath(AGraph: TUsesGraph; ATarget, AStart: Integer; const ANext: TArray<Integer>): string;
var
  mNode: Integer;
begin
  Result := '';
  if (AStart = ATarget) or (ANext[AStart] < 0) then
  begin
    Exit;
  end;
  Result := AGraph.Node(ATarget).UnitName;
  mNode := AStart;
  while mNode <> ATarget do
  begin
    Result := Result + ' → ' + AGraph.Node(mNode).UnitName;
    mNode := ANext[mNode];
  end;
  Result := Result + ' → ' + AGraph.Node(ATarget).UnitName;
end;

class function TUnitRelationsBuilder.UseCandidates(AGraph: TUsesGraph; const AFileName: string): TUnitUseInfo;
var
  mTarget, mNode: Integer;
  mByInterface, mByAny, mOrder: TArray<Integer>;
  mCandidate: TUnitUseCandidate;
begin
  Result := Default(TUnitUseInfo);
  Result.FileName := AFileName;
  Result.UnitName := BareName(AFileName);
  mTarget := AGraph.IndexOfFile(AFileName);
  if mTarget < 0 then
  begin
    Exit;
  end;
  Result.Found := True;
  Result.UnitName := AGraph.Node(mTarget).UnitName;
  Result.FileName := AGraph.Node(mTarget).FileName;
  mByInterface := NextTowards(AGraph, mTarget, True);
  mByAny := NextTowards(AGraph, mTarget, False);
  // Nach Name: dieselbe Reihenfolge wie die übrigen Listen des Graphen.
  mOrder := AGraph.Dependents(mTarget, cAllUsesSections);
  for mNode in mOrder do
  begin
    if mByAny[mNode] < 0 then
    begin
      Continue;
    end;
    mCandidate := Default(TUnitUseCandidate);
    mCandidate.Name := AGraph.Node(mNode).UnitName;
    mCandidate.FileName := AGraph.Node(mNode).FileName;
    mCandidate.InterfacePath := CirclePath(AGraph, mTarget, mNode, mByInterface);
    mCandidate.Path := CirclePath(AGraph, mTarget, mNode, mByAny);
    Result.Candidates := Result.Candidates + [mCandidate];
  end;
end;

class function TUnitRelationsBuilder.UseInfoToJson(const AInfo: TUnitUseInfo): TJSONObject;
var
  mList: TJSONArray;
  mCandidate: TUnitUseCandidate;
  mItem: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(AInfo.Found));
  Result.AddPair('unit', AInfo.UnitName);
  Result.AddPair('file', AInfo.FileName);
  mList := TJSONArray.Create;
  for mCandidate in AInfo.Candidates do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mCandidate.Name);
    if mCandidate.FileName <> '' then
    begin
      mItem.AddPair('file', mCandidate.FileName);
    end;
    if mCandidate.InterfacePath <> '' then
    begin
      mItem.AddPair('interfacePath', mCandidate.InterfacePath);
    end;
    mItem.AddPair('path', mCandidate.Path);
    mList.AddElement(mItem);
  end;
  Result.AddPair('cycles', mList);
end;

function RelationJson(const ARelation: TUnitRelation): TJSONObject;
var
  mChildren: TJSONArray;
  mChild: TUnitRelation;
  mLocation: TJSONObject;
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
    mLocation := TJSONObject.Create;
    mLocation.AddPair('file', ARelation.LocationFile);
    mLocation.AddPair('line', TJSONNumber.Create(ARelation.Line));
    mLocation.AddPair('character', TJSONNumber.Create(ARelation.Character));
    Result.AddPair('location', mLocation);
  end;
  if ARelation.Children <> nil then
  begin
    mChildren := TJSONArray.Create;
    for mChild in ARelation.Children do
    begin
      mChildren.AddElement(RelationJson(mChild));
    end;
    Result.AddPair('children', mChildren);
  end;
end;

class function TUnitRelationsBuilder.ToJson(const ARelations: TUnitRelations): TJSONObject;
var
  mList: TJSONArray;
  mRelation: TUnitRelation;
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
  mList := TJSONArray.Create;
  for mRelation in ARelations.Uses_ do
  begin
    mList.AddElement(RelationJson(mRelation));
  end;
  Result.AddPair('uses', mList);
  mList := TJSONArray.Create;
  for mRelation in ARelations.UsedBy do
  begin
    mList.AddElement(RelationJson(mRelation));
  end;
  Result.AddPair('usedBy', mList);
end;

end.
