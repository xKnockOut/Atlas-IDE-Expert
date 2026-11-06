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
  cAllUsesSections: TUsesSections = [TUsesSection.Interface_, TUsesSection.Implementation_];
  cInterfaceUsesOnly: TUsesSections = [TUsesSection.Interface_];

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
  mRoot, mFileName: string;
begin
  mFileName := StringReplace(AFileName, '\', '/', [rfReplaceAll]);
  mRoot := StringReplace(ARoot, '\', '/', [rfReplaceAll]);
  if (mRoot <> '') and (mRoot[Length(mRoot)] <> '/') then
  begin
    mRoot := mRoot + '/';
  end;
  if (mRoot <> '') and StartsText(mRoot, mFileName) then
  begin
    Result := Copy(mFileName, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    Result := mFileName;
  end;
end;

function ContainsNode(const ANodes: TArray<Integer>; ANode: Integer): Boolean;
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

function IsProgramFile(const AFileName: string): Boolean;
var
  mExtension: string;
begin
  mExtension := LowerCase(ExtractFileExt(AFileName));
  Result := (mExtension = '.dpr') or (mExtension = '.dpk');
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
  mPattern, mRelative: string;
begin
  if AUnit.UnitName = '' then
  begin
    Exit(False);
  end;
  if AUnit.Library_ and not FOptions.IncludeLibrary then
  begin
    Exit(False);
  end;
  mRelative := RelativeTo(FOptions.Root, AUnit.FileName);
  for mPattern in FOptions.Exclude do
  begin
    if MatchesGlob(mPattern, AUnit.UnitName) or MatchesGlob(mPattern, mRelative) then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function TUsesGraph.Resolve(const AName: string): Integer;
var
  mNamespace: string;
begin
  if FByName.TryGetValue(LowerCase(AName), Result) then
  begin
    Exit;
  end;
  for mNamespace in FOptions.Namespaces do
  begin
    if FByName.TryGetValue(LowerCase(mNamespace + '.' + AName), Result) then
    begin
      Exit;
    end;
  end;
  Result := -1;
end;

function TUsesGraph.NamesOf(ANode: Integer): TArray<string>;
begin
  Result := FInterfaceNames[ANode] + FImplementationNames[ANode];
end;

procedure TUsesGraph.ForgetUnresolved(ANode: Integer);
var
  mName: string;
  mUsers: TList<Integer>;
begin
  for mName in NamesOf(ANode) do
  begin
    if FUnresolved.TryGetValue(LowerCase(mName), mUsers) then
    begin
      mUsers.Remove(ANode);
      if mUsers.Count = 0 then
      begin
        FUnresolved.Remove(LowerCase(mName));
      end;
    end;
  end;
end;

/// <summary>ANode wartet auf eine Unit namens AName (bisher ohne Knoten).</summary>
procedure AddWaiting(AUnresolved: TUsesWaiting; const AName: string; ANode: Integer);
var
  mUsers: TList<Integer>;
begin
  if not AUnresolved.TryGetValue(LowerCase(AName), mUsers) then
  begin
    mUsers := TList<Integer>.Create;
    AUnresolved.Add(LowerCase(AName), mUsers);
  end;
  if not mUsers.Contains(ANode) then
  begin
    mUsers.Add(ANode);
  end;
end;

procedure TUsesGraph.Link(ANode: Integer);
var
  mItem, mTarget: TUsesNode;
  mEdge: TUsesEdge;
  mTargetIndex, mOrder: Integer;
  mSection: TUsesSection;
  mNames: TArray<string>;
  mRef: TUsesEdgeRef;
begin
  mItem := FNodes[ANode];
  mItem.Outgoing := nil;
  for mSection := Low(TUsesSection) to High(TUsesSection) do
  begin
    if mSection = TUsesSection.Interface_ then
    begin
      mNames := FInterfaceNames[ANode];
    end
    else
    begin
      mNames := FImplementationNames[ANode];
    end;
    for mOrder := 0 to High(mNames) do
    begin
      mTargetIndex := Resolve(mNames[mOrder]);
      if mTargetIndex < 0 then
      begin
        AddWaiting(FUnresolved, mNames[mOrder], ANode);
        Continue;
      end;
      mEdge.Source := ANode;
      mEdge.Target := mTargetIndex;
      mEdge.Section := mSection;
      mEdge.Order := mOrder;
      mEdge.Name := mNames[mOrder];
      mItem.Outgoing := mItem.Outgoing + [mEdge];
    end;
  end;
  FNodes[ANode] := mItem;
  for mOrder := 0 to High(mItem.Outgoing) do
  begin
    mRef.Source := ANode;
    mRef.Item := mOrder;
    mTarget := FNodes[mItem.Outgoing[mOrder].Target];
    mTarget.Incoming := mTarget.Incoming + [mRef];
    FNodes[mItem.Outgoing[mOrder].Target] := mTarget;
  end;
end;

procedure TUsesGraph.Unlink(ANode: Integer);
var
  mItem, mTarget: TUsesNode;
  mEdge: TUsesEdge;
  mKept: TArray<TUsesEdgeRef>;
  mRef: TUsesEdgeRef;
begin
  mItem := FNodes[ANode];
  for mEdge in mItem.Outgoing do
  begin
    mTarget := FNodes[mEdge.Target];
    mKept := nil;
    for mRef in mTarget.Incoming do
    begin
      if mRef.Source <> ANode then
      begin
        mKept := mKept + [mRef];
      end;
    end;
    mTarget.Incoming := mKept;
    FNodes[mEdge.Target] := mTarget;
  end;
  mItem.Outgoing := nil;
  FNodes[ANode] := mItem;
  ForgetUnresolved(ANode);
end;

/// <summary>Knoten, die auf einen der Namen ANames warten, jeder einmal in der Reihenfolge des Auftretens.
/// </summary>
function WaitingFor(AUnresolved: TUsesWaiting; const ANames: TArray<string>): TArray<Integer>;
var
  mName: string;
  mUsers: TList<Integer>;
  mNode: Integer;
begin
  Result := nil;
  for mName in ANames do
  begin
    if not AUnresolved.TryGetValue(LowerCase(mName), mUsers) then
    begin
      Continue;
    end;
    for mNode in mUsers do
    begin
      if not ContainsNode(Result, mNode) then
      begin
        Result := Result + [mNode];
      end;
    end;
  end;
end;

procedure TUsesGraph.Relink(const ANames: TArray<string>);
var
  mNode: Integer;
begin
  // Ein neuer oder entfernter Knoten ändert die Auflösung bei allen, die seinen Namen verwenden.
  for mNode in WaitingFor(FUnresolved, ANames) do
  begin
    if FNodes[mNode].Active then
    begin
      Unlink(mNode);
      Link(mNode);
    end;
  end;
end;

function TUsesGraph.Update(const AUnit: TUnitIndex): Boolean;
var
  mIndex_: Integer;
  mItem: TUsesNode;
  mKey, mNamespace: string;
begin
  if not Accepts(AUnit) then
  begin
    Remove(AUnit.FileName);
    Exit(False);
  end;
  Result := True;
  if FByFile.TryGetValue(NormalizedPath(AUnit.FileName), mIndex_) then
  begin
    mItem := FNodes[mIndex_];
    if (mItem.Hash = AUnit.Hash) and (mItem.Stamp = AUnit.Stamp) and SameText(mItem.UnitName, AUnit.UnitName) then
    begin
      Exit;
    end;
    if not SameText(mItem.UnitName, AUnit.UnitName) then
    begin
      // Unit umbenannt: wie Entfernen und neu Anlegen.
      Remove(AUnit.FileName);
      Exit(Update(AUnit));
    end;
    Unlink(mIndex_);
  end
  else
  begin
    mIndex_ := FNodes.Count;
    mItem := Default(TUsesNode);
    FNodes.Add(mItem);
    FInterfaceNames.Add(nil);
    FImplementationNames.Add(nil);
    FByFile.Add(NormalizedPath(AUnit.FileName), mIndex_);
    FByName.AddOrSetValue(LowerCase(AUnit.UnitName), mIndex_);
  end;
  mItem := FNodes[mIndex_];
  mItem.UnitName := AUnit.UnitName;
  mItem.FileName := AUnit.FileName;
  mItem.Library_ := AUnit.Library_;
  mItem.IsProgram := IsProgramFile(AUnit.FileName);
  mItem.HasInitialization := AUnit.HasInitialization;
  mItem.Hash := AUnit.Hash;
  mItem.Stamp := AUnit.Stamp;
  mItem.Active := True;
  FNodes[mIndex_] := mItem;
  FInterfaceNames[mIndex_] := AUnit.InterfaceUses;
  FImplementationNames[mIndex_] := AUnit.ImplementationUses;
  Link(mIndex_);
  // Units, die diesen Namen schon verwenden (auch ohne Namensraum), bekommen ihre Kante.
  mKey := AUnit.UnitName;
  Relink([mKey]);
  for mNamespace in FOptions.Namespaces do
  begin
    if StartsText(mNamespace + '.', mKey) then
    begin
      Relink([Copy(mKey, Length(mNamespace) + 2, MaxInt)]);
    end;
  end;
end;

procedure TUsesGraph.Remove(const AFileName: string);
var
  mIndex_, mName_: Integer;
  mItem: TUsesNode;
  mUsers: TArray<Integer>;
  mRef: TUsesEdgeRef;
  mKey, mNamespace: string;
begin
  if not FByFile.TryGetValue(NormalizedPath(AFileName), mIndex_) then
  begin
    Exit;
  end;
  Unlink(mIndex_);
  mItem := FNodes[mIndex_];
  // Wer die Unit verwendet, verliert die Kante; der Name gilt dort wieder als offen.
  mUsers := nil;
  for mRef in mItem.Incoming do
  begin
    if not ContainsNode(mUsers, mRef.Source) then
    begin
      mUsers := mUsers + [mRef.Source];
    end;
  end;
  mItem.Active := False;
  mItem.Incoming := nil;
  FNodes[mIndex_] := mItem;
  FByFile.Remove(NormalizedPath(AFileName));
  mKey := LowerCase(mItem.UnitName);
  if FByName.TryGetValue(mKey, mName_) and (mName_ = mIndex_) then
  begin
    FByName.Remove(mKey);
  end;
  for mName_ in mUsers do
  begin
    if FNodes[mName_].Active then
    begin
      Unlink(mName_);
      Link(mName_);
    end;
  end;
  for mNamespace in FOptions.Namespaces do
  begin
    if StartsText(mNamespace + '.', mItem.UnitName) then
    begin
      Relink([Copy(mItem.UnitName, Length(mNamespace) + 2, MaxInt)]);
    end;
  end;
end;

function TUsesGraph.Synchronize(const AUnits: TArray<TUnitIndex>): Integer;
var
  mSeen: TDictionary<string, Boolean>;
  mUnit_: TUnitIndex;
  mIndex_: Integer;
  mItem: TUsesNode;
  mGone: TArray<string>;
  mFileName: string;
begin
  Result := 0;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mUnit_ in AUnits do
    begin
      if not Accepts(mUnit_) then
      begin
        Continue;
      end;
      mSeen.AddOrSetValue(NormalizedPath(mUnit_.FileName), True);
      if FByFile.TryGetValue(NormalizedPath(mUnit_.FileName), mIndex_) then
      begin
        mItem := FNodes[mIndex_];
        if (mItem.Hash = mUnit_.Hash) and (mItem.Stamp = mUnit_.Stamp) and
          SameText(mItem.UnitName, mUnit_.UnitName) then
        begin
          Continue;
        end;
      end;
      Update(mUnit_);
      Inc(Result);
    end;
    mGone := nil;
    for mIndex_ := 0 to FNodes.Count - 1 do
    begin
      if FNodes[mIndex_].Active and not mSeen.ContainsKey(NormalizedPath(FNodes[mIndex_].FileName)) then
      begin
        mGone := mGone + [FNodes[mIndex_].FileName];
      end;
    end;
    for mFileName in mGone do
    begin
      Remove(mFileName);
      Inc(Result);
    end;
  finally
    mSeen.Free;
  end;
end;

function TUsesGraph.NodeCount: Integer;
begin
  Result := FNodes.Count;
end;

function TUsesGraph.ActiveCount: Integer;
var
  mIndex_: Integer;
begin
  Result := 0;
  for mIndex_ := 0 to FNodes.Count - 1 do
  begin
    if FNodes[mIndex_].Active then
    begin
      Inc(Result);
    end;
  end;
end;

function TUsesGraph.EdgeCount: Integer;
var
  mIndex_: Integer;
begin
  Result := 0;
  for mIndex_ := 0 to FNodes.Count - 1 do
  begin
    if FNodes[mIndex_].Active then
    begin
      Inc(Result, Length(FNodes[mIndex_].Outgoing));
    end;
  end;
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
  begin
    Result := -1;
  end;
end;

function TUsesGraph.SortedNodes: TArray<Integer>;
var
  mIndex_: Integer;
  mList: TList<Integer>;
begin
  mList := TList<Integer>.Create;
  try
    for mIndex_ := 0 to FNodes.Count - 1 do
    begin
      if FNodes[mIndex_].Active then
      begin
        mList.Add(mIndex_);
      end;
    end;
    mList.Sort(TComparer<Integer>.Construct(
      function(const ALeft, ARight: Integer): Integer
      begin
        Result := CompareText(FNodes[ALeft].UnitName, FNodes[ARight].UnitName);
        if Result = 0 then
        begin
          Result := ALeft - ARight;
        end;
      end));
    Result := mList.ToArray;
  finally
    mList.Free;
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
      begin
        Result := ALeft - ARight;
      end;
    end));
end;

/// <summary>Kante gehört zu einem der Abschnitte ASections und führt zu einem aktiven Knoten.</summary>
function EdgeAllowed(AGraph: TUsesGraph; const AEdge: TUsesEdge; ASections: TUsesSections): Boolean;
begin
  Result := (AEdge.Section in ASections) and AGraph.Node(AEdge.Target).Active;
end;

function TUsesGraph.DirectDependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  mEdge: TUsesEdge;
begin
  Result := nil;
  for mEdge in FNodes[ANode].Outgoing do
  begin
    if EdgeAllowed(Self, mEdge, ASections) and not ContainsNode(Result, mEdge.Target) then
    begin
      Result := Result + [mEdge.Target];
    end;
  end;
end;

function TUsesGraph.DirectDependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  mRef: TUsesEdgeRef;
  mEdge: TUsesEdge;
begin
  Result := nil;
  for mRef in FNodes[ANode].Incoming do
  begin
    mEdge := FNodes[mRef.Source].Outgoing[mRef.Item];
    if (mEdge.Section in ASections) and FNodes[mRef.Source].Active and
      not ContainsNode(Result, mRef.Source) then
    begin
      Result := Result + [mRef.Source];
    end;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.Dependencies(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  mSeen: TArray<Boolean>;
  mStack: TStack<Integer>;
  mFound: TList<Integer>;
  mCurrent, mNext: Integer;
begin
  SetLength(mSeen, FNodes.Count);
  mSeen[ANode] := True;
  mStack := TStack<Integer>.Create;
  mFound := TList<Integer>.Create;
  try
    mStack.Push(ANode);
    while mStack.Count > 0 do
    begin
      mCurrent := mStack.Pop;
      for mNext in DirectDependencies(mCurrent, ASections) do
      begin
        if not mSeen[mNext] then
        begin
          mSeen[mNext] := True;
          mFound.Add(mNext);
          mStack.Push(mNext);
        end;
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
    mStack.Free;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.Dependents(ANode: Integer; ASections: TUsesSections): TArray<Integer>;
var
  mSeen: TArray<Boolean>;
  mStack: TStack<Integer>;
  mFound: TList<Integer>;
  mCurrent, mNext: Integer;
begin
  SetLength(mSeen, FNodes.Count);
  mSeen[ANode] := True;
  mStack := TStack<Integer>.Create;
  mFound := TList<Integer>.Create;
  try
    mStack.Push(ANode);
    while mStack.Count > 0 do
    begin
      mCurrent := mStack.Pop;
      for mNext in DirectDependents(mCurrent, ASections) do
      begin
        if not mSeen[mNext] then
        begin
          mSeen[mNext] := True;
          mFound.Add(mNext);
          mStack.Push(mNext);
        end;
      end;
    end;
    Result := mFound.ToArray;
  finally
    mFound.Free;
    mStack.Free;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.RecompileMarks(ANode: Integer; out ACount: Integer): TArray<Boolean>;
var
  mSpreads: TArray<Boolean>;
  mQueue: TQueue<Integer>;
  mCurrent: Integer;
  mRef: TUsesEdgeRef;
  mSource: TUsesNode;
begin
  // Ändert sich das interface von X, übersetzt der Compiler jeden Verwender von X neu. Verwendet ein Verwender X
  // im interface, ändert sich dadurch auch seine Schnittstelle, und seine Verwender folgen.
  ACount := 0;
  // Result kann auf ein altes Feld des Aufrufers zeigen: frisch anlegen.
  Result := nil;
  SetLength(Result, FNodes.Count);
  SetLength(mSpreads, FNodes.Count);
  mSpreads[ANode] := True;
  mQueue := TQueue<Integer>.Create;
  try
    mQueue.Enqueue(ANode);
    while mQueue.Count > 0 do
    begin
      mCurrent := mQueue.Dequeue;
      for mRef in FNodes[mCurrent].Incoming do
      begin
        mSource := FNodes[mRef.Source];
        if not mSource.Active then
        begin
          Continue;
        end;
        if (mRef.Source <> ANode) and not Result[mRef.Source] then
        begin
          Result[mRef.Source] := True;
          Inc(ACount);
        end;
        if (mSource.Outgoing[mRef.Item].Section = TUsesSection.Interface_) and not mSpreads[mRef.Source] then
        begin
          mSpreads[mRef.Source] := True;
          mQueue.Enqueue(mRef.Source);
        end;
      end;
    end;
  finally
    mQueue.Free;
  end;
end;

function TUsesGraph.RecompileSet(ANode: Integer): TArray<Integer>;
var
  mMarks: TArray<Boolean>;
  mCount, mNode_: Integer;
begin
  mMarks := RecompileMarks(ANode, mCount);
  SetLength(Result, mCount);
  mCount := 0;
  for mNode_ := 0 to High(mMarks) do
  begin
    if mMarks[mNode_] then
    begin
      Result[mCount] := mNode_;
      Inc(mCount);
    end;
  end;
  SortByName(Self, Result);
end;

function TUsesGraph.RecompileCount(ANode: Integer): Integer;
begin
  RecompileMarks(ANode, Result);
end;

function TUsesGraph.Path(AFrom, ATo: Integer; ASections: TUsesSections): TUsesEdges;
var
  mVia: TArray<Integer>;
  mViaItem: TArray<Integer>;
  mQueue: TQueue<Integer>;
  mCurrent, mItem, mStep: Integer;
  mEdge: TUsesEdge;
begin
  Result := nil;
  if (AFrom = ATo) or (AFrom < 0) or (ATo < 0) or not FNodes[AFrom].Active or not FNodes[ATo].Active then
  begin
    Exit;
  end;
  SetLength(mVia, FNodes.Count);
  SetLength(mViaItem, FNodes.Count);
  for mItem := 0 to High(mVia) do
  begin
    mVia[mItem] := -1;
  end;
  mVia[AFrom] := AFrom;
  mQueue := TQueue<Integer>.Create;
  try
    mQueue.Enqueue(AFrom);
    while (mQueue.Count > 0) and (mVia[ATo] < 0) do
    begin
      mCurrent := mQueue.Dequeue;
      for mItem := 0 to High(FNodes[mCurrent].Outgoing) do
      begin
        mEdge := FNodes[mCurrent].Outgoing[mItem];
        if not EdgeAllowed(Self, mEdge, ASections) or (mVia[mEdge.Target] >= 0) then
        begin
          Continue;
        end;
        mVia[mEdge.Target] := mCurrent;
        mViaItem[mEdge.Target] := mItem;
        mQueue.Enqueue(mEdge.Target);
      end;
    end;
  finally
    mQueue.Free;
  end;
  if mVia[ATo] < 0 then
  begin
    Exit;
  end;
  mStep := ATo;
  while mStep <> AFrom do
  begin
    Result := [FNodes[mVia[mStep]].Outgoing[mViaItem[mStep]]] + Result;
    mStep := mVia[mStep];
  end;
end;

type
  TTarjanFrame = record
    Node: Integer;
    Next: Integer;
  end;

  /// <summary>Zyklen über die Kanten der Abschnitte ASections: stark zusammenhängende Komponenten nach Tarjan
  /// (ohne Rekursion, tiefe Ketten sprengen sonst den Stapel, vgl. #1094), je Komponente der kürzeste Rundweg.
  /// </summary>
  TUsesCycleFinder = class
  private
    FGraph: TUsesGraph;
    FSections: TUsesSections;
    FOrder, FLow: TArray<Integer>;
    FOnStack: TArray<Boolean>;
    FCounter: Integer;
    FStack: TStack<Integer>;
    FFrames: TStack<TTarjanFrame>;
    FComponents: TArray<TArray<Integer>>;
    /// <summary>ANode betreten: Nummer vergeben, auf beide Stapel legen.</summary>
    procedure Enter(ANode: Integer);
    /// <summary>Nächste Kante von AFrame; True, wenn ein neuer Knoten betreten wurde.</summary>
    function Advance(var AFrame: TTarjanFrame): Boolean;
    /// <summary>AFrame ist fertig: ggf. Komponente abschließen, kleinste Nummer an den Elternrahmen geben.</summary>
    procedure Finish(const AFrame: TTarjanFrame);
    procedure Connect(AStart: Integer);
    function Components: TArray<TArray<Integer>>;
    function HasSelfLoop(ANode: Integer): Boolean;
    /// <summary>Kante zählt für den Rundweg: erlaubt und innerhalb der Komponente.</summary>
    function Follows(const AEdge: TUsesEdge; const AInComponent: TArray<Boolean>): Boolean;
    /// <summary>Breitensuche ab AStart innerhalb der Komponente, bis eine Kante zurück zu AStart führt.
    /// </summary>
    function ShortestCycle(AStart: Integer; const AInComponent: TArray<Boolean>; out ACycle: TUsesCycle): Boolean;
  public
    constructor Create(AGraph: TUsesGraph; ASections: TUsesSections);
    destructor Destroy; override;
    function Cycles: TArray<TUsesCycle>;
  end;

constructor TUsesCycleFinder.Create(AGraph: TUsesGraph; ASections: TUsesSections);
begin
  inherited Create;
  FGraph := AGraph;
  FSections := ASections;
  FStack := TStack<Integer>.Create;
  FFrames := TStack<TTarjanFrame>.Create;
end;

destructor TUsesCycleFinder.Destroy;
begin
  FFrames.Free;
  FStack.Free;
  inherited;
end;

procedure TUsesCycleFinder.Enter(ANode: Integer);
var
  mFrame: TTarjanFrame;
begin
  mFrame.Node := ANode;
  mFrame.Next := 0;
  FOrder[ANode] := FCounter;
  FLow[ANode] := FCounter;
  Inc(FCounter);
  FStack.Push(ANode);
  FOnStack[ANode] := True;
  FFrames.Push(mFrame);
end;

function TUsesCycleFinder.Advance(var AFrame: TTarjanFrame): Boolean;
var
  mEdge: TUsesEdge;
  mOutgoing: TUsesEdges;
begin
  mOutgoing := FGraph.Node(AFrame.Node).Outgoing;
  while AFrame.Next <= High(mOutgoing) do
  begin
    mEdge := mOutgoing[AFrame.Next];
    Inc(AFrame.Next);
    if not EdgeAllowed(FGraph, mEdge, FSections) then
    begin
      Continue;
    end;
    if FOrder[mEdge.Target] < 0 then
    begin
      FFrames.Push(AFrame);
      Enter(mEdge.Target);
      Exit(True);
    end;
    if FOnStack[mEdge.Target] and (FOrder[mEdge.Target] < FLow[AFrame.Node]) then
    begin
      FLow[AFrame.Node] := FOrder[mEdge.Target];
    end;
  end;
  Result := False;
end;

procedure TUsesCycleFinder.Finish(const AFrame: TTarjanFrame);
var
  mComponent: TArray<Integer>;
  mMember: Integer;
  mParent: TTarjanFrame;
begin
  if FLow[AFrame.Node] = FOrder[AFrame.Node] then
  begin
    mComponent := nil;
    repeat
      mMember := FStack.Pop;
      FOnStack[mMember] := False;
      mComponent := mComponent + [mMember];
    until mMember = AFrame.Node;
    SortByName(FGraph, mComponent);
    FComponents := FComponents + [mComponent];
  end;
  if FFrames.Count > 0 then
  begin
    mParent := FFrames.Pop;
    if FLow[AFrame.Node] < FLow[mParent.Node] then
    begin
      FLow[mParent.Node] := FLow[AFrame.Node];
    end;
    FFrames.Push(mParent);
  end;
end;

procedure TUsesCycleFinder.Connect(AStart: Integer);
var
  mFrame: TTarjanFrame;
begin
  Enter(AStart);
  while FFrames.Count > 0 do
  begin
    mFrame := FFrames.Pop;
    if not Advance(mFrame) then
    begin
      Finish(mFrame);
    end;
  end;
end;

function TUsesCycleFinder.Components: TArray<TArray<Integer>>;
var
  mStart: Integer;
begin
  FComponents := nil;
  SetLength(FOrder, FGraph.NodeCount);
  SetLength(FLow, FGraph.NodeCount);
  SetLength(FOnStack, FGraph.NodeCount);
  for mStart := 0 to High(FOrder) do
  begin
    FOrder[mStart] := -1;
  end;
  FCounter := 0;
  for mStart in FGraph.SortedNodes do
  begin
    if FOrder[mStart] < 0 then
    begin
      Connect(mStart);
    end;
  end;
  Result := FComponents;
end;

function TUsesCycleFinder.HasSelfLoop(ANode: Integer): Boolean;
var
  mEdge: TUsesEdge;
begin
  for mEdge in FGraph.Node(ANode).Outgoing do
  begin
    if EdgeAllowed(FGraph, mEdge, FSections) and (mEdge.Target = ANode) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TUsesCycleFinder.Follows(const AEdge: TUsesEdge; const AInComponent: TArray<Boolean>): Boolean;
begin
  Result := EdgeAllowed(FGraph, AEdge, FSections) and AInComponent[AEdge.Target];
end;

/// <summary>Rundweg aus den Vorgängern AVia/AViaItem bis ALast und der Kante ALastItem zurück zu AStart.
/// </summary>
function CycleFromPath(AGraph: TUsesGraph; AStart, ALast, ALastItem: Integer;
  const AVia, AViaItem: TArray<Integer>): TUsesCycle;
var
  mStep: Integer;
  mEdge: TUsesEdge;
begin
  Result := Default(TUsesCycle);
  Result.Edges := [AGraph.Node(ALast).Outgoing[ALastItem]];
  mStep := ALast;
  while mStep <> AStart do
  begin
    Result.Edges := [AGraph.Node(AVia[mStep]).Outgoing[AViaItem[mStep]]] + Result.Edges;
    mStep := AVia[mStep];
  end;
  Result.InterfaceOnly := True;
  for mEdge in Result.Edges do
  begin
    Result.Units := Result.Units + [mEdge.Source];
    if mEdge.Section <> TUsesSection.Interface_ then
    begin
      Result.InterfaceOnly := False;
    end;
  end;
end;

function TUsesCycleFinder.ShortestCycle(AStart: Integer; const AInComponent: TArray<Boolean>;
  out ACycle: TUsesCycle): Boolean;
var
  mVia, mViaItem: TArray<Integer>;
  mQueue: TQueue<Integer>;
  mCurrent, mItem, mLast, mLastItem: Integer;
  mEdge: TUsesEdge;
begin
  ACycle := Default(TUsesCycle);
  SetLength(mVia, FGraph.NodeCount);
  SetLength(mViaItem, FGraph.NodeCount);
  for mItem := 0 to High(mVia) do
  begin
    mVia[mItem] := -1;
  end;
  mVia[AStart] := AStart;
  mLast := -1;
  mLastItem := -1;
  mQueue := TQueue<Integer>.Create;
  try
    mQueue.Enqueue(AStart);
    while (mQueue.Count > 0) and (mLast < 0) do
    begin
      mCurrent := mQueue.Dequeue;
      for mItem := 0 to High(FGraph.Node(mCurrent).Outgoing) do
      begin
        mEdge := FGraph.Node(mCurrent).Outgoing[mItem];
        if not Follows(mEdge, AInComponent) then
        begin
          Continue;
        end;
        if mEdge.Target = AStart then
        begin
          mLast := mCurrent;
          mLastItem := mItem;
          Break;
        end;
        if mVia[mEdge.Target] < 0 then
        begin
          mVia[mEdge.Target] := mCurrent;
          mViaItem[mEdge.Target] := mItem;
          mQueue.Enqueue(mEdge.Target);
        end;
      end;
    end;
  finally
    mQueue.Free;
  end;
  Result := mLast >= 0;
  if Result then
  begin
    ACycle := CycleFromPath(FGraph, AStart, mLast, mLastItem, mVia, mViaItem);
  end;
end;

function TUsesCycleFinder.Cycles: TArray<TUsesCycle>;
var
  mComponent: TArray<Integer>;
  mInComponent: TArray<Boolean>;
  mMember: Integer;
  mCycle: TUsesCycle;
  mGraph: TUsesGraph;
begin
  Result := nil;
  SetLength(mInComponent, FGraph.NodeCount);
  for mComponent in Components do
  begin
    if (Length(mComponent) < 2) and not HasSelfLoop(mComponent[0]) then
    begin
      Continue;
    end;
    for mMember in mComponent do
    begin
      mInComponent[mMember] := True;
    end;
    if ShortestCycle(mComponent[0], mInComponent, mCycle) then
    begin
      mCycle.Component := mComponent;
      Result := Result + [mCycle];
    end;
    for mMember in mComponent do
    begin
      mInComponent[mMember] := False;
    end;
  end;
  mGraph := FGraph;
  TArray.Sort<TUsesCycle>(Result, TComparer<TUsesCycle>.Construct(
    function(const ALeft, ARight: TUsesCycle): Integer
    begin
      Result := CompareText(mGraph.Node(ALeft.Units[0]).UnitName, mGraph.Node(ARight.Units[0]).UnitName);
      if Result = 0 then
      begin
        Result := ALeft.Units[0] - ARight.Units[0];
      end;
    end));
end;

function CyclesOf(AGraph: TUsesGraph; ASections: TUsesSections): TArray<TUsesCycle>;
var
  mFinder: TUsesCycleFinder;
begin
  mFinder := TUsesCycleFinder.Create(AGraph, ASections);
  try
    Result := mFinder.Cycles;
  finally
    mFinder.Free;
  end;
end;

function TUsesGraph.Cycles(ASections: TUsesSections): TArray<TUsesCycle>;
begin
  Result := CyclesOf(Self, ASections);
end;

function TUsesGraph.AllCycles: TArray<TUsesCycle>;
var
  mErrors, mWider: TArray<TUsesCycle>;
  mCycle, mError: TUsesCycle;
  mCovered: Boolean;
  mMember: Integer;
  mInError: TArray<Boolean>;
begin
  mErrors := CyclesOf(Self, cInterfaceUsesOnly);
  mWider := CyclesOf(Self, cAllUsesSections);
  Result := mErrors;
  SetLength(mInError, FNodes.Count);
  for mError in mErrors do
  begin
    for mMember in mError.Component do
    begin
      mInError[mMember] := True;
    end;
  end;
  // Eine Komponente über alle Kanten, die nur aus Units eines interface-Zyklus besteht, zeigt nichts Neues.
  for mCycle in mWider do
  begin
    mCovered := True;
    for mMember in mCycle.Component do
    begin
      if not mInError[mMember] then
      begin
        mCovered := False;
      end;
    end;
    if not mCovered then
    begin
      Result := Result + [mCycle];
    end;
  end;
end;

function TUsesGraph.InitializationOrder(ARoot: Integer; AOnlyWithInitialization: Boolean): TArray<Integer>;
var
  mSeen: TArray<Boolean>;
  mFrames: TStack<TTarjanFrame>;
  mFrame, mChild: TTarjanFrame;
  mEdge: TUsesEdge;
  mAdvanced: Boolean;
begin
  // Der Compiler initialisiert eine Unit, nachdem alle Units ihrer uses (in deren Reihenfolge, zuerst interface)
  // initialisiert sind: Nachordnung einer Tiefensuche.
  Result := nil;
  if (ARoot < 0) or not FNodes[ARoot].Active then
  begin
    Exit;
  end;
  SetLength(mSeen, FNodes.Count);
  mFrames := TStack<TTarjanFrame>.Create;
  try
    mFrame.Node := ARoot;
    mFrame.Next := 0;
    mSeen[ARoot] := True;
    mFrames.Push(mFrame);
    while mFrames.Count > 0 do
    begin
      mFrame := mFrames.Pop;
      mAdvanced := False;
      while mFrame.Next <= High(FNodes[mFrame.Node].Outgoing) do
      begin
        mEdge := FNodes[mFrame.Node].Outgoing[mFrame.Next];
        Inc(mFrame.Next);
        if not FNodes[mEdge.Target].Active or mSeen[mEdge.Target] then
        begin
          Continue;
        end;
        mSeen[mEdge.Target] := True;
        mFrames.Push(mFrame);
        mChild.Node := mEdge.Target;
        mChild.Next := 0;
        mFrames.Push(mChild);
        mAdvanced := True;
        Break;
      end;
      if mAdvanced then
      begin
        Continue;
      end;
      if not AOnlyWithInitialization or FNodes[mFrame.Node].HasInitialization then
      begin
        Result := Result + [mFrame.Node];
      end;
    end;
  finally
    mFrames.Free;
  end;
end;

function TUsesGraph.Describe(const AEdges: TUsesEdges): string;
var
  mEdge: TUsesEdge;
begin
  Result := '';
  if AEdges = nil then
  begin
    Exit;
  end;
  Result := FNodes[AEdges[0].Source].UnitName;
  for mEdge in AEdges do
  begin
    Result := Result + ' → ' + FNodes[mEdge.Target].UnitName;
  end;
end;

end.
