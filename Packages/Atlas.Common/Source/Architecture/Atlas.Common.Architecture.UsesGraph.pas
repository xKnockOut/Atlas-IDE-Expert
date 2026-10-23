unit Atlas.Common.Architecture.UsesGraph;

// Gemeinsamer Uses-Graph-Dienst (#268): Units als Knoten, uses-Einträge als
// Kanten mit Abschnitt (interface/implementation) und Reihenfolge.
//
// - Quelle ist der Symbolindex. Er liest jede Datei mit den aktiven Defines
//   der gewählten Konfiguration (inaktive {$IFDEF}-Zweige sind ausgeblendet),
//   bedingte uses-Einträge gelten also genau dann, wenn ihr Zweig gilt.
// - Kanten nur zwischen Knoten des Graphen: Bibliotheks-Units nur mit
//   IncludeLibrary, Units aus Exclude (Glob auf Unit-Name oder Pfad relativ
//   zu Root) nie. Namen ohne Namensraum (SysUtils) werden über Namespaces
//   aufgelöst (System.SysUtils).
// - Update/Remove ändern nur die Kanten der betroffenen Unit (inkrementell,
//   #22); Knoten behalten ihre Nummer, entfernte bleiben als Lücke stehen.
// - Abfragen: Zyklen (stark zusammenhängende Komponenten nach Tarjan, je
//   Komponente der kürzeste Rundweg), Weg zwischen zwei Units, transitive
//   Hülle in beide Richtungen, neu zu übersetzende Units und
//   Initialisierungsreihenfolge.
// - Alle Ergebnisse sind deterministisch: Knoten in Namensreihenfolge,
//   Kanten in Quelltextreihenfolge (erst interface, dann implementation).
//
// Fundstellen der Kanten (Zeile und Spalte) liefert TUsesLocator bei Bedarf;
// der Graph selbst hält keine Positionen.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Index.Contract;

type
  TUsesSection = (Interface_, Implementation_);
  TUsesSections = set of TUsesSection;

  /// <summary>Ein uses-Eintrag von Source nach Target (Knotennummern).</summary>
  TUsesEdge = record
    Source: Integer;
    Target: Integer;
    Section: TUsesSection;
    /// <summary>Stelle in der Liste des Abschnitts ab 0.</summary>
    Order: Integer;
    /// <summary>Name, wie er im uses steht (SysUtils statt System.SysUtils).</summary>
    Name: string;
  end;

  TUsesEdges = TArray<TUsesEdge>;

  /// <summary>Verweis auf die Kante Outgoing[Item] des Knotens Source.</summary>
  TUsesEdgeRef = record
    Source: Integer;
    Item: Integer;
  end;

  TUsesNode = record
    UnitName: string;
    FileName: string;
    Library_: Boolean;
    /// <summary>Programm, Bibliothek oder Package (.dpr/.dpk): nur ein uses, gilt als implementation.</summary>
    IsProgram: Boolean;
    HasInitialization: Boolean;
    /// <summary>Hash und Zeitstempel des Index-Eintrags; daran erkennt Update unveränderte Units.</summary>
    Hash: string;
    Stamp: Int64;
    /// <summary>False nach Remove; die Nummer bleibt belegt.</summary>
    Active: Boolean;
    /// <summary>uses-Einträge in Quelltextreihenfolge, die einen Knoten des Graphen treffen.</summary>
    Outgoing: TUsesEdges;
    Incoming: TArray<TUsesEdgeRef>;
  end;

  /// <summary>Ein Zyklus: Units in Laufrichtung und die Kanten dazwischen (Edges[i] führt von Units[i] nach
  /// Units[i+1], die letzte zurück zu Units[0]).</summary>
  TUsesCycle = record
    Units: TArray<Integer>;
    Edges: TUsesEdges;
    /// <summary>Alle Units der stark zusammenhängenden Komponente, nach Name sortiert.</summary>
    Component: TArray<Integer>;
    /// <summary>Alle Kanten des Rundwegs stehen im interface: Compilerfehler F2047.</summary>
    InterfaceOnly: Boolean;
  end;

  TUsesGraphOptions = record
    /// <summary>Bibliotheks-Units (RTL, VCL, Suchpfade) als Knoten aufnehmen.</summary>
    IncludeLibrary: Boolean;
    /// <summary>Globs auf Unit-Name oder Pfad relativ zu Root (z. B. "Tests/**", "*.Tests").</summary>
    Exclude: TArray<string>;
    Root: string;
    /// <summary>Namensräume des Projekts für Namen ohne Präfix (System, Vcl, Winapi …).</summary>
    Namespaces: TArray<string>;
    class function Default: TUsesGraphOptions; static;
  end;

  /// <summary>Name ohne Treffer (Kleinschreibung) → Knoten, die ihn verwenden.</summary>
  TUsesWaiting = TObjectDictionary<string, TList<Integer>>;
  TUsesNameLists = TList<TArray<string>>;

  TUsesGraph = class
  private
    FOptions: TUsesGraphOptions;
    FNodes: TList<TUsesNode>;
    /// <summary>Unit-Name in Kleinschreibung → Knoten (nur aktive).</summary>
    FByName: TDictionary<string, Integer>;
    FByFile: TDictionary<string, Integer>;
    /// <summary>uses-Listen je Knoten, wie im Index (für spätere Auflösung neuer Knoten).</summary>
    FInterfaceNames: TUsesNameLists;
    FImplementationNames: TUsesNameLists;
    FUnresolved: TUsesWaiting;
    function Accepts(const AUnit: TUnitIndex): Boolean;
    function Resolve(const AName: string): Integer;
    procedure Link(ANode: Integer);
    procedure Unlink(ANode: Integer);
    procedure ForgetUnresolved(ANode: Integer);
    procedure Relink(const ANames: TArray<string>);
    function NamesOf(ANode: Integer): TArray<string>;
    function Allowed(const AEdge: TUsesEdge; ASections: TUsesSections): Boolean;
    function ShortestCycle(AStart: Integer; const AInComponent: TArray<Boolean>; ASections: TUsesSections;
      out ACycle: TUsesCycle): Boolean;
    function Components(ASections: TUsesSections): TArray<TArray<Integer>>;
    function CyclesOf(ASections: TUsesSections): TArray<TUsesCycle>;
    function RecompileMarks(ANode: Integer; out ACount: Integer): TArray<Boolean>;
  public
    constructor Create(const AOptions: TUsesGraphOptions); overload;
    constructor Create(const AUnits: TArray<TUnitIndex>; const AOptions: TUsesGraphOptions); overload;
    destructor Destroy; override;
    /// <summary>Nimmt die Unit auf oder ersetzt ihre Kanten; unveränderte Units (gleicher Hash und Zeitstempel)
    /// bleiben unberührt. False, wenn die Unit nicht in den Graphen gehört (Bibliothek, Ausschluss).</summary>
    function Update(const AUnit: TUnitIndex): Boolean;
    /// <summary>Entfernt die Unit der Datei AFileName; Kanten auf sie gelten wieder als offen.</summary>
    procedure Remove(const AFileName: string);
    /// <summary>Gleicht den Graphen mit allen Units des Index ab: neue und geänderte aufnehmen, fehlende
    /// entfernen. Liefert die Zahl der geänderten Knoten.</summary>
    function Synchronize(const AUnits: TArray<TUnitIndex>): Integer;
    /// <summary>Zahl der Knotennummern einschließlich entfernter.</summary>
    function NodeCount: Integer;
    function ActiveCount: Integer;
    function EdgeCount: Integer;
    function Node(AIndex: Integer): TUsesNode;
    /// <summary>Knoten zum Unit-Namen (auch über Namespaces); -1 ohne Treffer.</summary>
    function IndexOf(const AUnitName: string): Integer;
    function IndexOfFile(const AFileName: string): Integer;
    /// <summary>Aktive Knoten nach Unit-Name sortiert.</summary>
    function SortedNodes: TArray<Integer>;
    /// <summary>Direkte Abhängigkeiten von ANode (Ziele seiner uses) in Quelltextreihenfolge, ohne doppelte.</summary>
    function DirectDependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
    /// <summary>Direkte Abhängige (Units, die ANode verwenden), ohne doppelte, nach Name sortiert.</summary>
    function DirectDependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
    /// <summary>Transitive Hülle der Abhängigkeiten ohne ANode selbst, nach Name sortiert.</summary>
    function Dependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
    /// <summary>Transitive Hülle der Abhängigen ohne ANode selbst, nach Name sortiert.</summary>
    function Dependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
    /// <summary>Units, die neu übersetzt werden, wenn sich der interface-Teil von ANode ändert: alle direkten
    /// Verwender und, über interface-uses weitergereicht, deren Verwender (#554, #593, #1118 „gesamt
    /// abhängig“). Ohne ANode, nach Name sortiert.</summary>
    function RecompileSet(ANode: Integer): TArray<Integer>;
    /// <summary>Länge von RecompileSet, ohne die Liste zu bauen.</summary>
    function RecompileCount(ANode: Integer): Integer;
    /// <summary>Kürzester Weg von AFrom nach ATo als Kanten (Breitensuche, bei Gleichstand die Kante, die im
    /// Quelltext früher steht); leer, wenn es keinen gibt oder AFrom = ATo.</summary>
    function Path(AFrom, ATo: Integer; ASections: TUsesSections): TUsesEdges;
    /// <summary>Zyklen über die Kanten der Abschnitte ASections: je stark zusammenhängender Komponente mit mehr
    /// als einer Unit (oder einer Unit, die sich selbst verwendet) der kürzeste Rundweg durch ihre Unit mit
    /// dem kleinsten Namen. Nach diesem Namen sortiert.</summary>
    function Cycles(ASections: TUsesSections): TArray<TUsesCycle>;
    /// <summary>Alle Zyklen für die Anzeige (#1118): zuerst die über interface-uses (Compilerfehler), dann jede
    /// weitere Komponente über alle Kanten mit ihrem kürzesten Rundweg.</summary>
    function AllCycles: TArray<TUsesCycle>;
    /// <summary>Initialisierungsreihenfolge ab ARoot (Programm oder Unit): Tiefensuche über die uses in
    /// Quelltextreihenfolge, erst interface, dann implementation; eine Unit kommt nach allen, die sie zuerst
    /// erreicht. Nur Units mit initialization-/finalization-Teil, wenn AOnlyWithInitialization.</summary>
    function InitializationOrder(ARoot: Integer; AOnlyWithInitialization: Boolean): TArray<Integer>;
    /// <summary>Text eines Wegs oder Zyklus: "A → B → C" (bei Zyklen mit A am Ende).</summary>
    function Describe(const AEdges: TUsesEdges): string;
    property Options: TUsesGraphOptions read FOptions;
  end;

const
  AllUsesSections: TUsesSections = [TUsesSection.Interface_, TUsesSection.Implementation_];
  InterfaceUsesOnly: TUsesSections = [TUsesSection.Interface_];

implementation

uses
  System.StrUtils,
  System.Generics.Defaults,
  Atlas.Common.Configuration.Contract;

function NormalizedPath(const APath: string): string;
begin
  Result := LowerCase(StringReplace(APath, '\', '/', [rfReplaceAll]));
end;

function RelativeTo(const ARoot, AFileName: string): string;
var
  Root, FileName: string;
begin
  FileName := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  Root := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (Root <> '') and (Root[Length(Root)] <> '/') then
    Root := Root + '/';
  if (Root <> '') and StartsText(Root, FileName) then
    Result := Copy(FileName, Length(Root) + 1, MaxInt)
  else
    Result := FileName;
end;

function ContainsNode(const ANodes: TArray<Integer>; ANode: Integer): Boolean;
var
  Item: Integer;
begin
  for Item in ANodes do
    if Item = ANode then
      Exit(True);
  Result := False;
end;

function IsProgramFile(const AFileName: string): Boolean;
var
  Extension: string;
begin
  Extension := LowerCase(ExtractFileExt(AFileName));
  Result := (Extension = '.dpr') or (Extension = '.dpk');
end;

{ TUsesGraphOptions }

class function TUsesGraphOptions.Default: TUsesGraphOptions;
begin
  Result.IncludeLibrary := False;
  Result.Exclude := nil;
  Result.Root := '';
  Result.Namespaces := nil;
end;

{ TUsesGraph }

constructor TUsesGraph.Create(const AOptions: TUsesGraphOptions);
begin
  inherited Create;
  FOptions := AOptions;
  FNodes := TList<TUsesNode>.Create;
  FByName := TDictionary<string, Integer>.Create;
  FByFile := TDictionary<string, Integer>.Create;
  FInterfaceNames := TUsesNameLists.Create;
  FImplementationNames := TUsesNameLists.Create;
  FUnresolved := TUsesWaiting.Create([doOwnsValues]);
end;

constructor TUsesGraph.Create(const AUnits: TArray<TUnitIndex>; const AOptions: TUsesGraphOptions);
begin
  Create(AOptions);
  Synchronize(AUnits);
end;

destructor TUsesGraph.Destroy;
begin
  FUnresolved.Free;
  FImplementationNames.Free;
  FInterfaceNames.Free;
  FByFile.Free;
  FByName.Free;
  FNodes.Free;
  inherited;
end;

function TUsesGraph.Accepts(const AUnit: TUnitIndex): Boolean;
var
  Pattern, Relative: string;
begin
  if AUnit.UnitName = '' then
    Exit(False);
  if AUnit.Library_ and not FOptions.IncludeLibrary then
    Exit(False);
  Relative := RelativeTo(FOptions.Root, AUnit.FileName);
  for Pattern in FOptions.Exclude do
    if MatchesGlob(Pattern, AUnit.UnitName) or MatchesGlob(Pattern, Relative) then
      Exit(False);
  Result := True;
end;

function TUsesGraph.Resolve(const AName: string): Integer;
var
  Namespace: string;
begin
  if FByName.TryGetValue(LowerCase(AName), Result) then
    Exit;
  for Namespace in FOptions.Namespaces do
    if FByName.TryGetValue(LowerCase(Namespace + '.' + AName), Result) then
      Exit;
  Result := -1;
end;

function TUsesGraph.NamesOf(ANode: Integer): TArray<string>;
begin
  Result := FInterfaceNames[ANode] + FImplementationNames[ANode];
end;

procedure TUsesGraph.ForgetUnresolved(ANode: Integer);
var
  Name: string;
  Users: TList<Integer>;
begin
  for Name in NamesOf(ANode) do
    if FUnresolved.TryGetValue(LowerCase(Name), Users) then
    begin
      Users.Remove(ANode);
      if Users.Count = 0 then
        FUnresolved.Remove(LowerCase(Name));
    end;
end;

procedure TUsesGraph.Link(ANode: Integer);
var
  Item: TUsesNode;
  Edge: TUsesEdge;
  Target, Order: Integer;
  Section: TUsesSection;
  Names: TArray<string>;
  Users: TList<Integer>;
  Ref: TUsesEdgeRef;
  Target_: TUsesNode;
begin
  Item := FNodes[ANode];
  Item.Outgoing := nil;
  for Section := Low(TUsesSection) to High(TUsesSection) do
  begin
    if Section = TUsesSection.Interface_ then
      Names := FInterfaceNames[ANode]
    else
      Names := FImplementationNames[ANode];
    for Order := 0 to High(Names) do
    begin
      Target := Resolve(Names[Order]);
      if Target < 0 then
      begin
        if not FUnresolved.TryGetValue(LowerCase(Names[Order]), Users) then
        begin
          Users := TList<Integer>.Create;
          FUnresolved.Add(LowerCase(Names[Order]), Users);
        end;
        if not Users.Contains(ANode) then
          Users.Add(ANode);
        Continue;
      end;
      Edge.Source := ANode;
      Edge.Target := Target;
      Edge.Section := Section;
      Edge.Order := Order;
      Edge.Name := Names[Order];
      Item.Outgoing := Item.Outgoing + [Edge];
    end;
  end;
  FNodes[ANode] := Item;
  for Order := 0 to High(Item.Outgoing) do
  begin
    Ref.Source := ANode;
    Ref.Item := Order;
    Target_ := FNodes[Item.Outgoing[Order].Target];
    Target_.Incoming := Target_.Incoming + [Ref];
    FNodes[Item.Outgoing[Order].Target] := Target_;
  end;
end;

procedure TUsesGraph.Unlink(ANode: Integer);
var
  Item, Target: TUsesNode;
  Edge: TUsesEdge;
  Kept: TArray<TUsesEdgeRef>;
  Ref: TUsesEdgeRef;
begin
  Item := FNodes[ANode];
  for Edge in Item.Outgoing do
  begin
    Target := FNodes[Edge.Target];
    Kept := nil;
    for Ref in Target.Incoming do
      if Ref.Source <> ANode then
        Kept := Kept + [Ref];
    Target.Incoming := Kept;
    FNodes[Edge.Target] := Target;
  end;
  Item.Outgoing := nil;
  FNodes[ANode] := Item;
  ForgetUnresolved(ANode);
end;

procedure TUsesGraph.Relink(const ANames: TArray<string>);
var
  Name: string;
  Users: TList<Integer>;
  Waiting: TList<Integer>;
  Node_: Integer;
begin
  // Ein neuer oder entfernter Knoten ändert die Auflösung bei allen, die seinen Namen verwenden.
  Waiting := TList<Integer>.Create;
  try
    for Name in ANames do
      if FUnresolved.TryGetValue(LowerCase(Name), Users) then
        for Node_ in Users do
          if not Waiting.Contains(Node_) then
            Waiting.Add(Node_);
    for Node_ in Waiting do
      if FNodes[Node_].Active then
      begin
        Unlink(Node_);
        Link(Node_);
      end;
  finally
    Waiting.Free;
  end;
end;

function TUsesGraph.Update(const AUnit: TUnitIndex): Boolean;
var
  Index_: Integer;
  Item: TUsesNode;
  Key, Namespace: string;
begin
  if not Accepts(AUnit) then
  begin
    Remove(AUnit.FileName);
    Exit(False);
  end;
  Result := True;
  if FByFile.TryGetValue(NormalizedPath(AUnit.FileName), Index_) then
  begin
    Item := FNodes[Index_];
    if (Item.Hash = AUnit.Hash) and (Item.Stamp = AUnit.Stamp) and SameText(Item.UnitName, AUnit.UnitName) then
      Exit;
    if not SameText(Item.UnitName, AUnit.UnitName) then
    begin
      // Unit umbenannt: wie Entfernen und neu Anlegen.
      Remove(AUnit.FileName);
      Exit(Update(AUnit));
    end;
    Unlink(Index_);
  end
  else
  begin
    Index_ := FNodes.Count;
    Item := Default(TUsesNode);
    FNodes.Add(Item);
    FInterfaceNames.Add(nil);
    FImplementationNames.Add(nil);
    FByFile.Add(NormalizedPath(AUnit.FileName), Index_);
    FByName.AddOrSetValue(LowerCase(AUnit.UnitName), Index_);
  end;
  Item := FNodes[Index_];
  Item.UnitName := AUnit.UnitName;
  Item.FileName := AUnit.FileName;
  Item.Library_ := AUnit.Library_;
  Item.IsProgram := IsProgramFile(AUnit.FileName);
  Item.HasInitialization := AUnit.HasInitialization;
  Item.Hash := AUnit.Hash;
  Item.Stamp := AUnit.Stamp;
  Item.Active := True;
  FNodes[Index_] := Item;
  FInterfaceNames[Index_] := AUnit.InterfaceUses;
  FImplementationNames[Index_] := AUnit.ImplementationUses;
  Link(Index_);
  // Units, die diesen Namen schon verwenden (auch ohne Namensraum), bekommen ihre Kante.
  Key := AUnit.UnitName;
  Relink([Key]);
  for Namespace in FOptions.Namespaces do
    if StartsText(Namespace + '.', Key) then
      Relink([Copy(Key, Length(Namespace) + 2, MaxInt)]);
end;

procedure TUsesGraph.Remove(const AFileName: string);
var
  Index_, Name_: Integer;
  Item: TUsesNode;
  Users: TArray<Integer>;
  Ref: TUsesEdgeRef;
  Key, Namespace: string;
begin
  if not FByFile.TryGetValue(NormalizedPath(AFileName), Index_) then
    Exit;
  Unlink(Index_);
  Item := FNodes[Index_];
  // Wer die Unit verwendet, verliert die Kante; der Name gilt dort wieder als offen.
  Users := nil;
  for Ref in Item.Incoming do
    if not ContainsNode(Users, Ref.Source) then
      Users := Users + [Ref.Source];
  Item.Active := False;
  Item.Incoming := nil;
  FNodes[Index_] := Item;
  FByFile.Remove(NormalizedPath(AFileName));
  Key := LowerCase(Item.UnitName);
  if FByName.TryGetValue(Key, Name_) and (Name_ = Index_) then
    FByName.Remove(Key);
  for Name_ in Users do
    if FNodes[Name_].Active then
    begin
      Unlink(Name_);
      Link(Name_);
    end;
  for Namespace in FOptions.Namespaces do
    if StartsText(Namespace + '.', Item.UnitName) then
      Relink([Copy(Item.UnitName, Length(Namespace) + 2, MaxInt)]);
end;

function TUsesGraph.Synchronize(const AUnits: TArray<TUnitIndex>): Integer;
var
  Seen: TDictionary<string, Boolean>;
  Unit_: TUnitIndex;
  Index_: Integer;
  Item: TUsesNode;
  Gone: TArray<string>;
  FileName: string;
begin
  Result := 0;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Unit_ in AUnits do
    begin
      if not Accepts(Unit_) then
        Continue;
      Seen.AddOrSetValue(NormalizedPath(Unit_.FileName), True);
      if FByFile.TryGetValue(NormalizedPath(Unit_.FileName), Index_) then
      begin
        Item := FNodes[Index_];
        if (Item.Hash = Unit_.Hash) and (Item.Stamp = Unit_.Stamp) and SameText(Item.UnitName, Unit_.UnitName) then
          Continue;
      end;
      Update(Unit_);
      Inc(Result);
    end;
    Gone := nil;
    for Index_ := 0 to FNodes.Count - 1 do
      if FNodes[Index_].Active and not Seen.ContainsKey(NormalizedPath(FNodes[Index_].FileName)) then
        Gone := Gone + [FNodes[Index_].FileName];
    for FileName in Gone do
    begin
      Remove(FileName);
      Inc(Result);
    end;
  finally
    Seen.Free;
  end;
end;

function TUsesGraph.NodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TUsesGraph.ActiveCount: Integer;
var
  Index_: Integer;
begin
  Result := 0;
  for Index_ := 0 to FNodes.Count - 1 do
    if FNodes[Index_].Active then
      Inc(Result);
end;

function TUsesGraph.EdgeCount: Integer;
var
  Index_: Integer;
begin
  Result := 0;
  for Index_ := 0 to FNodes.Count - 1 do
    if FNodes[Index_].Active then
      Inc(Result, Length(FNodes[Index_].Outgoing));
end;

function TUsesGraph.Node(AIndex: Integer): TUsesNode;
begin
  Result := FNodes[AIndex];
end;

function TUsesGraph.IndexOf(const AUnitName: string): Integer;
begin
  Result := Resolve(AUnitName);
end;

function TUsesGraph.IndexOfFile(const AFileName: string): Integer;
begin
  if not FByFile.TryGetValue(NormalizedPath(AFileName), Result) then
    Result := -1;
end;

function TUsesGraph.SortedNodes: TArray<Integer>;
var
  Index_: Integer;
  List: TList<Integer>;
begin
  List := TList<Integer>.Create;
  try
    for Index_ := 0 to FNodes.Count - 1 do
      if FNodes[Index_].Active then
        List.Add(Index_);
    List.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := CompareText(FNodes[ALeft].UnitName, FNodes[ARight].UnitName);
        if Result = 0 then
          Result := ALeft - ARight;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Sortiert Knotennummern nach Unit-Name.</summary>
procedure SortByName(AGraph: TUsesGraph; var ANodes: TArray<Integer>);
begin
  TArray.Sort<Integer>(ANodes, TComparer<Integer>.Construct(
    function(const ALeft, ARight: Integer): Integer
    begin
      Result := CompareText(AGraph.Node(ALeft).UnitName, AGraph.Node(ARight).UnitName);
      if Result = 0 then
        Result := ALeft - ARight;
    end));
end;

function TUsesGraph.Allowed(const AEdge: TUsesEdge; ASections: TUsesSections): Boolean;
begin
  Result := (AEdge.Section in ASections) and FNodes[AEdge.Target].Active;
end;

function TUsesGraph.DirectDependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  Edge: TUsesEdge;
begin
  Result := nil;
  for Edge in FNodes[ANode].Outgoing do
    if Allowed(Edge, ASections) and not ContainsNode(Result, Edge.Target) then
      Result := Result + [Edge.Target];
end;

function TUsesGraph.DirectDependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  Ref: TUsesEdgeRef;
  Edge: TUsesEdge;
begin
  Result := nil;
  for Ref in FNodes[ANode].Incoming do
  begin
    Edge := FNodes[Ref.Source].Outgoing[Ref.Item];
    if (Edge.Section in ASections) and FNodes[Ref.Source].Active and
      not ContainsNode(Result, Ref.Source) then
      Result := Result + [Ref.Source];
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.Dependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  Seen: TArray<Boolean>;
  Stack: TStack<Integer>;
  Found: TList<Integer>;
  Current, Next: Integer;
begin
  SetLength(Seen, FNodes.Count);
  Seen[ANode] := True;
  Stack := TStack<Integer>.Create;
  Found := TList<Integer>.Create;
  try
    Stack.Push(ANode);
    while Stack.Count > 0 do
    begin
      Current := Stack.Pop;
      for Next in DirectDependencies(Current, ASections) do
        if not Seen[Next] then
        begin
          Seen[Next] := True;
          Found.Add(Next);
          Stack.Push(Next);
        end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Stack.Free;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.Dependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  Seen: TArray<Boolean>;
  Stack: TStack<Integer>;
  Found: TList<Integer>;
  Current, Next: Integer;
begin
  SetLength(Seen, FNodes.Count);
  Seen[ANode] := True;
  Stack := TStack<Integer>.Create;
  Found := TList<Integer>.Create;
  try
    Stack.Push(ANode);
    while Stack.Count > 0 do
    begin
      Current := Stack.Pop;
      for Next in DirectDependents(Current, ASections) do
        if not Seen[Next] then
        begin
          Seen[Next] := True;
          Found.Add(Next);
          Stack.Push(Next);
        end;
    end;
    Result := Found.ToArray;
  finally
    Found.Free;
    Stack.Free;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.RecompileMarks(ANode: Integer; out ACount: Integer): TArray<Boolean>;
var
  Spreads: TArray<Boolean>;
  Queue: TQueue<Integer>;
  Current: Integer;
  Ref: TUsesEdgeRef;
  Source: TUsesNode;
begin
  // Ändert sich das interface von X, übersetzt der Compiler jeden Verwender von X neu. Verwendet ein Verwender X
  // im interface, ändert sich dadurch auch seine Schnittstelle, und seine Verwender folgen.
  ACount := 0;
  SetLength(Result, FNodes.Count);
  SetLength(Spreads, FNodes.Count);
  Spreads[ANode] := True;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Enqueue(ANode);
    while Queue.Count > 0 do
    begin
      Current := Queue.Dequeue;
      for Ref in FNodes[Current].Incoming do
      begin
        Source := FNodes[Ref.Source];
        if not Source.Active then
          Continue;
        if (Ref.Source <> ANode) and not Result[Ref.Source] then
        begin
          Result[Ref.Source] := True;
          Inc(ACount);
        end;
        if (Source.Outgoing[Ref.Item].Section = TUsesSection.Interface_) and not Spreads[Ref.Source] then
        begin
          Spreads[Ref.Source] := True;
          Queue.Enqueue(Ref.Source);
        end;
      end;
    end;
  finally
    Queue.Free;
  end;
end;

function TUsesGraph.RecompileSet(ANode: Integer): TArray<Integer>;
var
  Marks: TArray<Boolean>;
  Count, Node_: Integer;
begin
  Marks := RecompileMarks(ANode, Count);
  SetLength(Result, Count);
  Count := 0;
  for Node_ := 0 to High(Marks) do
    if Marks[Node_] then
    begin
      Result[Count] := Node_;
      Inc(Count);
    end;
  SortByName(Self, Result);
end;

function TUsesGraph.RecompileCount(ANode: Integer): Integer;
begin
  RecompileMarks(ANode, Result);
end;

function TUsesGraph.Path(AFrom, ATo: Integer; ASections: TUsesSections): TUsesEdges;
var
  Via: TArray<Integer>;
  ViaItem: TArray<Integer>;
  Queue: TQueue<Integer>;
  Current, Item, Step: Integer;
  Edge: TUsesEdge;
begin
  Result := nil;
  if (AFrom = ATo) or (AFrom < 0) or (ATo < 0) or not FNodes[AFrom].Active or not FNodes[ATo].Active then
    Exit;
  SetLength(Via, FNodes.Count);
  SetLength(ViaItem, FNodes.Count);
  for Item := 0 to High(Via) do
    Via[Item] := -1;
  Via[AFrom] := AFrom;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Enqueue(AFrom);
    while (Queue.Count > 0) and (Via[ATo] < 0) do
    begin
      Current := Queue.Dequeue;
      for Item := 0 to High(FNodes[Current].Outgoing) do
      begin
        Edge := FNodes[Current].Outgoing[Item];
        if not Allowed(Edge, ASections) or (Via[Edge.Target] >= 0) then
          Continue;
        Via[Edge.Target] := Current;
        ViaItem[Edge.Target] := Item;
        Queue.Enqueue(Edge.Target);
      end;
    end;
  finally
    Queue.Free;
  end;
  if Via[ATo] < 0 then
    Exit;
  Step := ATo;
  while Step <> AFrom do
  begin
    Result := [FNodes[Via[Step]].Outgoing[ViaItem[Step]]] + Result;
    Step := Via[Step];
  end;
end;

type
  TTarjanFrame = record
    Node: Integer;
    Next: Integer;
  end;

function TUsesGraph.Components(ASections: TUsesSections): TArray<TArray<Integer>>;
var
  Order, Low_: TArray<Integer>;
  OnStack: TArray<Boolean>;
  Stack: TStack<Integer>;
  Frames: TStack<TTarjanFrame>;
  Counter, Start, Member: Integer;
  Frame, Parent: TTarjanFrame;
  Edge: TUsesEdge;
  Component: TArray<Integer>;
  Advanced: Boolean;
begin
  // Tarjan ohne Rekursion (tiefe Ketten sprengen sonst den Stapel, vgl. #1094).
  Result := nil;
  SetLength(Order, FNodes.Count);
  SetLength(Low_, FNodes.Count);
  SetLength(OnStack, FNodes.Count);
  for Start := 0 to High(Order) do
    Order[Start] := -1;
  Counter := 0;
  Stack := TStack<Integer>.Create;
  Frames := TStack<TTarjanFrame>.Create;
  try
    for Start in SortedNodes do
    begin
      if Order[Start] >= 0 then
        Continue;
      Frame.Node := Start;
      Frame.Next := 0;
      Order[Start] := Counter;
      Low_[Start] := Counter;
      Inc(Counter);
      Stack.Push(Start);
      OnStack[Start] := True;
      Frames.Push(Frame);
      while Frames.Count > 0 do
      begin
        Frame := Frames.Pop;
        Advanced := False;
        while Frame.Next <= High(FNodes[Frame.Node].Outgoing) do
        begin
          Edge := FNodes[Frame.Node].Outgoing[Frame.Next];
          Inc(Frame.Next);
          if not Allowed(Edge, ASections) then
            Continue;
          if Order[Edge.Target] < 0 then
          begin
            Frames.Push(Frame);
            Parent.Node := Edge.Target;
            Parent.Next := 0;
            Order[Edge.Target] := Counter;
            Low_[Edge.Target] := Counter;
            Inc(Counter);
            Stack.Push(Edge.Target);
            OnStack[Edge.Target] := True;
            Frames.Push(Parent);
            Advanced := True;
            Break;
          end
          else if OnStack[Edge.Target] and (Order[Edge.Target] < Low_[Frame.Node]) then
            Low_[Frame.Node] := Order[Edge.Target];
        end;
        if Advanced then
          Continue;
        if Low_[Frame.Node] = Order[Frame.Node] then
        begin
          Component := nil;
          repeat
            Member := Stack.Pop;
            OnStack[Member] := False;
            Component := Component + [Member];
          until Member = Frame.Node;
          SortByName(Self, Component);
          Result := Result + [Component];
        end;
        if Frames.Count > 0 then
        begin
          Parent := Frames.Pop;
          if Low_[Frame.Node] < Low_[Parent.Node] then
            Low_[Parent.Node] := Low_[Frame.Node];
          Frames.Push(Parent);
        end;
      end;
    end;
  finally
    Frames.Free;
    Stack.Free;
  end;
end;

function TUsesGraph.ShortestCycle(AStart: Integer; const AInComponent: TArray<Boolean>; ASections: TUsesSections;
  out ACycle: TUsesCycle): Boolean;
var
  Via, ViaItem: TArray<Integer>;
  Queue: TQueue<Integer>;
  Current, Item, Step, Last, LastItem: Integer;
  Edge: TUsesEdge;
begin
  // Breitensuche ab AStart innerhalb der Komponente, bis eine Kante zurück zu AStart führt.
  ACycle := Default(TUsesCycle);
  SetLength(Via, FNodes.Count);
  SetLength(ViaItem, FNodes.Count);
  for Item := 0 to High(Via) do
    Via[Item] := -1;
  Via[AStart] := AStart;
  Last := -1;
  LastItem := -1;
  Queue := TQueue<Integer>.Create;
  try
    Queue.Enqueue(AStart);
    while (Queue.Count > 0) and (Last < 0) do
    begin
      Current := Queue.Dequeue;
      for Item := 0 to High(FNodes[Current].Outgoing) do
      begin
        Edge := FNodes[Current].Outgoing[Item];
        if not Allowed(Edge, ASections) or not AInComponent[Edge.Target] then
          Continue;
        if Edge.Target = AStart then
        begin
          Last := Current;
          LastItem := Item;
          Break;
        end;
        if Via[Edge.Target] >= 0 then
          Continue;
        Via[Edge.Target] := Current;
        ViaItem[Edge.Target] := Item;
        Queue.Enqueue(Edge.Target);
      end;
    end;
  finally
    Queue.Free;
  end;
  Result := Last >= 0;
  if not Result then
    Exit;
  ACycle.Edges := [FNodes[Last].Outgoing[LastItem]];
  Step := Last;
  while Step <> AStart do
  begin
    ACycle.Edges := [FNodes[Via[Step]].Outgoing[ViaItem[Step]]] + ACycle.Edges;
    Step := Via[Step];
  end;
  ACycle.InterfaceOnly := True;
  for Edge in ACycle.Edges do
  begin
    ACycle.Units := ACycle.Units + [Edge.Source];
    if Edge.Section <> TUsesSection.Interface_ then
      ACycle.InterfaceOnly := False;
  end;
end;

function TUsesGraph.CyclesOf(ASections: TUsesSections): TArray<TUsesCycle>;
var
  Component: TArray<Integer>;
  InComponent: TArray<Boolean>;
  Member: Integer;
  Cycle: TUsesCycle;
  SelfLoop: Boolean;
  Edge: TUsesEdge;
begin
  Result := nil;
  SetLength(InComponent, FNodes.Count);
  for Component in Components(ASections) do
  begin
    SelfLoop := False;
    if Length(Component) = 1 then
      for Edge in FNodes[Component[0]].Outgoing do
        if Allowed(Edge, ASections) and (Edge.Target = Component[0]) then
          SelfLoop := True;
    if (Length(Component) < 2) and not SelfLoop then
      Continue;
    for Member in Component do
      InComponent[Member] := True;
    if ShortestCycle(Component[0], InComponent, ASections, Cycle) then
    begin
      Cycle.Component := Component;
      Result := Result + [Cycle];
    end;
    for Member in Component do
      InComponent[Member] := False;
  end;
  TArray.Sort<TUsesCycle>(Result, TComparer<TUsesCycle>.Construct(
    function(const ALeft, ARight: TUsesCycle): Integer
    begin
      Result := CompareText(FNodes[ALeft.Units[0]].UnitName, FNodes[ARight.Units[0]].UnitName);
      if Result = 0 then
        Result := ALeft.Units[0] - ARight.Units[0];
    end));
end;

function TUsesGraph.Cycles(ASections: TUsesSections): TArray<TUsesCycle>;
begin
  Result := CyclesOf(ASections);
end;

function TUsesGraph.AllCycles: TArray<TUsesCycle>;
var
  Errors, Wider: TArray<TUsesCycle>;
  Cycle, Error: TUsesCycle;
  Covered: Boolean;
  Member: Integer;
  InError: TArray<Boolean>;
begin
  Errors := CyclesOf(InterfaceUsesOnly);
  Wider := CyclesOf(AllUsesSections);
  Result := Errors;
  SetLength(InError, FNodes.Count);
  for Error in Errors do
    for Member in Error.Component do
      InError[Member] := True;
  // Eine Komponente über alle Kanten, die nur aus Units eines interface-Zyklus besteht, zeigt nichts Neues.
  for Cycle in Wider do
  begin
    Covered := True;
    for Member in Cycle.Component do
      if not InError[Member] then
        Covered := False;
    if not Covered then
      Result := Result + [Cycle];
  end;
end;

function TUsesGraph.InitializationOrder(ARoot: Integer; AOnlyWithInitialization: Boolean): TArray<Integer>;
var
  Seen: TArray<Boolean>;
  Frames: TStack<TTarjanFrame>;
  Frame, Child: TTarjanFrame;
  Edge: TUsesEdge;
  Advanced: Boolean;
begin
  // Der Compiler initialisiert eine Unit, nachdem alle Units ihrer uses (in deren Reihenfolge, zuerst interface)
  // initialisiert sind: Nachordnung einer Tiefensuche.
  Result := nil;
  if (ARoot < 0) or not FNodes[ARoot].Active then
    Exit;
  SetLength(Seen, FNodes.Count);
  Frames := TStack<TTarjanFrame>.Create;
  try
    Frame.Node := ARoot;
    Frame.Next := 0;
    Seen[ARoot] := True;
    Frames.Push(Frame);
    while Frames.Count > 0 do
    begin
      Frame := Frames.Pop;
      Advanced := False;
      while Frame.Next <= High(FNodes[Frame.Node].Outgoing) do
      begin
        Edge := FNodes[Frame.Node].Outgoing[Frame.Next];
        Inc(Frame.Next);
        if not FNodes[Edge.Target].Active or Seen[Edge.Target] then
          Continue;
        Seen[Edge.Target] := True;
        Frames.Push(Frame);
        Child.Node := Edge.Target;
        Child.Next := 0;
        Frames.Push(Child);
        Advanced := True;
        Break;
      end;
      if Advanced then
        Continue;
      if not AOnlyWithInitialization or FNodes[Frame.Node].HasInitialization then
        Result := Result + [Frame.Node];
    end;
  finally
    Frames.Free;
  end;
end;

function TUsesGraph.Describe(const AEdges: TUsesEdges): string;
var
  Edge: TUsesEdge;
begin
  Result := '';
  if AEdges = nil then
    Exit;
  Result := FNodes[AEdges[0].Source].UnitName;
  for Edge in AEdges do
    Result := Result + ' → ' + FNodes[Edge.Target].UnitName;
end;

end.
