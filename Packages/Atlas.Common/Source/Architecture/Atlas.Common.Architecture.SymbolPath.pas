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

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Architecture.UsesGraph,
  Atlas.Common.Architecture.UsesLocator,
  Atlas.Common.Architecture.UsesService;

type
  /// <summary>Kantenarten in ihrer Rangfolge bei gleich langen Wegen.</summary>
  TSymbolPathEdgeKind = (Uses_, Inherits, Implements, HasField, Parameter, Result_, Calls, Contains);
  TSymbolPathEdgeKinds = set of TSymbolPathEdgeKind;

  TSymbolPathNode = record
    /// <summary>Unit statt Deklaration; Symbol ist dann leer.</summary>
    IsUnit: Boolean;
    UnitName: string;
    /// <summary>Datei der Unit bzw. der Deklaration (Include-Datei, #500).</summary>
    FileName: string;
    Symbol: TIndexSymbol;
    Library_: Boolean;
    /// <summary>Unit-Name bzw. qualifizierter Name; Felder, Properties und Variablen mit Typ ("TFoo.FDb: TDb").</summary>
    function Caption: string;
    /// <summary>Stelle des Namens, Zeile und Spalte ab 0; bei Units der Anfang der Datei.</summary>
    function Position: TTextPosition;
  end;

  /// <summary>Ein Schritt von Nodes[i] nach Nodes[i+1].</summary>
  TSymbolPathStep = record
    Kind: TSymbolPathEdgeKind;
    /// <summary>implements in Gegenrichtung: Interface → umsetzende Klasse („umgesetzt von“).</summary>
    Reverse: Boolean;
    /// <summary>Mehrere mögliche Ziele (#1119).</summary>
    Inferred: Boolean;
    /// <summary>uses im implementation-Teil.</summary>
    Implementation_: Boolean;
    /// <summary>Fundstelle der Kante (uses-Eintrag, Feld, Aufrufstelle …), Zeile und Spalte ab 0.</summary>
    FileName: string;
    Position: TTextPosition;
  end;

  TSymbolPathRoute = record
    Nodes: TArray<TSymbolPathNode>;
    Steps: TArray<TSymbolPathStep>;
  end;

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

  TSymbolPathReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>True, wenn die Suche abbrechen soll (MCP-Cancel, $/cancelRequest).</summary>
  TSymbolPathCancelled = reference to function: Boolean;

  TSymbolPathSearch = class
  private type
    TPathEdge = record
      Target: Integer;
      Kind: TSymbolPathEdgeKind;
      Reverse: Boolean;
      Inferred: Boolean;
      FileName: string;
      Position: TTextPosition;
      HasUsesEdge: Boolean;
      UsesEdge: TUsesEdge;
      SortKey: string;
    end;
    TPathEdges = TArray<TPathEdge>;
    TIndexList = TList<Integer>;
    TMemberMap = TObjectDictionary<string, TIndexList>;
    TPathUnit = class
    public
      Data: TUnitIndex;
      /// <summary>Container in Großschreibung ('' = Unit-Ebene) → Stellen in Data.Symbols.</summary>
      Members: TMemberMap;
      UsesNames: TArray<string>;
      constructor Create(const AData: TUnitIndex);
      destructor Destroy; override;
      function MembersOf(const AContainer: string): TArray<Integer>;
    end;
    TSymbolRef = record
      UnitName: string;
      Index: Integer;
    end;
    TRefList = TList<TSymbolRef>;
    TRefMap = TObjectDictionary<string, TRefList>;
    TTypeTarget = record
      Nodes: TArray<Integer>;
      Inferred: Boolean;
    end;
    TEdgeCache = TDictionary<Integer, TPathEdges>;
    TNodeCache = TDictionary<Integer, TArray<Integer>>;
    TDistances = TDictionary<Integer, Integer>;
    TFrontier = TList<Integer>;
    TStepRef = record
      Source: Integer;
      Edge: TPathEdge;
    end;
    TStepRefs = TArray<TStepRef>;
    TOutcome = (Found, NoPath, Aborted);
  private
    FIndex: ISymbolIndex;
    FGraph: TUsesGraph;
    FLocator: TUsesLocator;
    FReadText: TSymbolPathReadText;
    FEnsureUnit: TEnsureUnitFunc;
    FNamespaces: TArray<string>;
    FResolver: TNameResolver;
    FUnits: TObjectDictionary<string, TPathUnit>;
    FNodes: TList<TSymbolPathNode>;
    FKeys: TDictionary<string, Integer>;
    FForward: TEdgeCache;
    FCalls: TEdgeCache;
    FPredecessors: TNodeCache;
    FCallers: TNodeCache;
    FImplementers: TNodeCache;
    FTypes: TDictionary<string, TTypeTarget>;
    FRefs: TRefMap;
    FEndpoints: TDictionary<Integer, Boolean>;
    FDistF: TDistances;
    FDistB: TDistances;
    FVia: TSymbolPathEdgeKinds;
    FThroughLibrary: Boolean;
    FMaxNodes: Integer;
    FTimeoutMs: Integer;
    FCancelled: TSymbolPathCancelled;
    FClock: Int64;
    FVisited: Integer;
    FAbortReason: string;
    FSearchedSteps: Integer;
    function UnitFor(const AUnitName: string): TPathUnit;
    function UnitNode(const AUnitName: string): Integer;
    function Canonical(AUnit: TPathUnit; AIndex: Integer): Integer;
    function SymbolNode(AUnit: TPathUnit; AIndex: Integer): Integer;
    function NodeOf(const ALocation: TSymbolLocation): Integer;
    function NodeUnit(ANode: Integer): TPathUnit;
    function IndexInUnit(AUnit: TPathUnit; const ASymbol: TIndexSymbol): Integer;
    function ContainerNode(AUnit: TPathUnit; const ASymbol: TIndexSymbol): Integer;
    function Visible(AUnit: TPathUnit; const AUnitName: string): Integer;
    function ResolveType(AUnit: TPathUnit; const AName: string): TTypeTarget;
    function ImplementersOf(ANode: Integer): TArray<Integer>;
    function InterfacesOf(ANode: Integer): TArray<Integer>;
    function MemberNamed(ATypeNode: Integer; const AName: string): Integer;
    function ImplementingMember(AClass, AInterface: Integer; const AName: string): Integer;
    procedure AddEdge(AList: TList<TPathEdge>; ATarget: Integer; AKind: TSymbolPathEdgeKind; AInferred: Boolean;
      const AFileName: string; const APosition: TTextPosition);
    procedure AddTypeEdges(AList: TList<TPathEdge>; AUnit: TPathUnit; const ATypeText: string;
      AKind: TSymbolPathEdgeKind; const AFileName: string; const APosition: TTextPosition);
    function BuildForward(ANode: Integer): TPathEdges;
    function ForwardOf(ANode: Integer): TPathEdges;
    function CallsOf(ANode: Integer): TPathEdges;
    procedure BuildRefs;
    function PredecessorsOf(ANode: Integer): TArray<Integer>;
    function CallersOf(ANode: Integer): TArray<Integer>;
    function Leads(ASource, ATarget: Integer; AWithCalls: Boolean): Boolean;
    function Passable(ANode: Integer): Boolean;
    function Stopped: Boolean;
    function Endpoints(const AText: string): TArray<Integer>;
    function Targets(ANode: Integer): TArray<Integer>;
    function Search(AStart: Integer; const ATargets: TArray<Integer>; AWithCalls: Boolean; ALimit: Integer;
      out ALength, AForwardDepth: Integer): TOutcome;
    function EdgesFor(ANode: Integer; AWithCalls: Boolean): TPathEdges;
    function Collect(AStart, ALength, AForwardDepth: Integer; AWithCalls: Boolean; AMax: Integer): TArray<TStepRefs>;
    function RouteOf(AStart: Integer; const ASteps: TStepRefs): TSymbolPathRoute;
    function Elapsed: Int64;
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
  System.StrUtils,
  System.Math,
  System.Generics.Defaults,
  System.Diagnostics,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Hierarchies;

type
  TIndexSymbolKinds = set of TIndexSymbolKind;

const
  TypeKinds: TIndexSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
  StructKinds: TIndexSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType];
  RoutineKinds: TIndexSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine];
  ValueKinds: TIndexSymbolKinds = [TIndexSymbolKind.Constant, TIndexSymbolKind.Variable,
    TIndexSymbolKind.Field, TIndexSymbolKind.Property_];
  /// <summary>Wörter in Typangaben, die kein Typname sind (array of TFoo, reference to function …).</summary>
  TypeWords: array[0..9] of string = ('array', 'of', 'set', 'class', 'packed', 'reference', 'to', 'function',
    'procedure', 'const');
  EdgeNames: array[TSymbolPathEdgeKind] of string = ('uses', 'inherits', 'implements', 'hasField', 'parameter',
    'result', 'calls', 'contains');
  /// <summary>Alle so viele Knoten Zeitlimit und Abbruch prüfen.</summary>
  CheckEvery = 16;

function IsTypeWord(const AWord: string): Boolean;
var
  Word: string;
begin
  for Word in TypeWords do
    if SameText(Word, AWord) then
      Exit(True);
  Result := False;
end;

/// <summary>Typnamen in einer Typangabe: "TList&lt;TKunde&gt;" → TList, TKunde; "array of TFoo" → TFoo.</summary>
function TypeNamesIn(const AText: string): TArray<string>;
var
  Index, Start: Integer;
  Word: string;
begin
  Result := nil;
  Index := 1;
  while Index <= Length(AText) do
  begin
    if CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '_', '&']) then
    begin
      Start := Index;
      while (Index <= Length(AText)) and CharInSet(AText[Index], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&', '.']) do
        Inc(Index);
      Word := Copy(AText, Start, Index - Start);
      if (Word <> '') and (Word[1] = '&') then
        Delete(Word, 1, 1);
      while (Word <> '') and (Word[Length(Word)] = '.') do
        Delete(Word, Length(Word), 1);
      if (Word <> '') and not IsTypeWord(Word) then
        Result := Result + [Word];
    end
    else
      Inc(Index);
  end;
end;

function LastSegment(const AName: string): string;
var
  Dot: Integer;
begin
  Dot := LastDelimiter('.', AName);
  if Dot > 0 then
    Result := Copy(AName, Dot + 1, MaxInt)
  else
    Result := AName;
end;

/// <summary>Trifft der uses-Eintrag AEntry die Unit AUnitName (SysUtils → System.SysUtils)?</summary>
function UsesMatches(const AEntry, AUnitName: string): Boolean;
begin
  Result := SameText(AEntry, AUnitName) or EndsText('.' + AEntry, AUnitName);
end;

function PositionKey(const APosition: TTextPosition): string;
begin
  Result := Format('%.6d:%.6d', [APosition.Line, APosition.Character]);
end;

{ TSymbolPathNode }

function TSymbolPathNode.Caption: string;
begin
  if IsUnit then
    Exit(UnitName);
  Result := Symbol.QualifiedName;
  if (Symbol.Kind in ValueKinds) and (Symbol.TypeName <> '') then
    Result := Result + ': ' + Symbol.TypeName;
end;

function TSymbolPathNode.Position: TTextPosition;
begin
  if IsUnit then
    Result := TTextPosition.Create(0, 0)
  else
    Result := Symbol.SelectionRange.StartPos;
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

{ TSymbolPathSearch.TPathUnit }

constructor TSymbolPathSearch.TPathUnit.Create(const AData: TUnitIndex);
var
  Index: Integer;
  Key: string;
  List: TIndexList;
begin
  inherited Create;
  Data := AData;
  Members := TMemberMap.Create([doOwnsValues]);
  for Index := 0 to High(Data.Symbols) do
  begin
    Key := UpperCase(Data.Symbols[Index].Container);
    if not Members.TryGetValue(Key, List) then
    begin
      List := TIndexList.Create;
      Members.Add(Key, List);
    end;
    List.Add(Index);
  end;
  UsesNames := Data.InterfaceUses + Data.ImplementationUses;
end;

destructor TSymbolPathSearch.TPathUnit.Destroy;
begin
  Members.Free;
  inherited;
end;

function TSymbolPathSearch.TPathUnit.MembersOf(const AContainer: string): TArray<Integer>;
var
  List: TIndexList;
begin
  if Members.TryGetValue(UpperCase(AContainer), List) then
    Result := List.ToArray
  else
    Result := nil;
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
  FUnits := TObjectDictionary<string, TPathUnit>.Create([doOwnsValues]);
  FNodes := TList<TSymbolPathNode>.Create;
  FKeys := TDictionary<string, Integer>.Create;
  FForward := TEdgeCache.Create;
  FCalls := TEdgeCache.Create;
  FPredecessors := TNodeCache.Create;
  FCallers := TNodeCache.Create;
  FImplementers := TNodeCache.Create;
  FTypes := TDictionary<string, TTypeTarget>.Create;
  FEndpoints := TDictionary<Integer, Boolean>.Create;
  FDistF := TDistances.Create;
  FDistB := TDistances.Create;
end;

destructor TSymbolPathSearch.Destroy;
begin
  FDistB.Free;
  FDistF.Free;
  FEndpoints.Free;
  FRefs.Free;
  FTypes.Free;
  FImplementers.Free;
  FCallers.Free;
  FPredecessors.Free;
  FCalls.Free;
  FForward.Free;
  FKeys.Free;
  FNodes.Free;
  FUnits.Free;
  FResolver.Free;
  inherited;
end;

class function TSymbolPathSearch.EdgeName(AKind: TSymbolPathEdgeKind): string;
begin
  Result := EdgeNames[AKind];
end;

class function TSymbolPathSearch.TryParseEdge(const AText: string; out AKind: TSymbolPathEdgeKind;
  out AThroughLibrary: Boolean): Boolean;
var
  Kind: TSymbolPathEdgeKind;
begin
  AKind := TSymbolPathEdgeKind.Uses_;
  AThroughLibrary := SameText(Trim(AText), 'library');
  if AThroughLibrary then
    Exit(True);
  for Kind := Low(TSymbolPathEdgeKind) to High(TSymbolPathEdgeKind) do
    if SameText(Trim(AText), EdgeNames[Kind]) then
    begin
      AKind := Kind;
      Exit(True);
    end;
  Result := False;
end;

function TSymbolPathSearch.Elapsed: Int64;
begin
  Result := (TStopwatch.GetTimeStamp - FClock) * 1000 div TStopwatch.Frequency;
end;

function TSymbolPathSearch.Stopped: Boolean;
begin
  if FAbortReason <> '' then
    Exit(True);
  if Assigned(FCancelled) and FCancelled() then
    FAbortReason := 'abgebrochen'
  else if (FTimeoutMs > 0) and (Elapsed > FTimeoutMs) then
    FAbortReason := 'Zeitlimit'
  else if FVisited > FMaxNodes then
    FAbortReason := 'Knotengrenze';
  Result := FAbortReason <> '';
end;

function TSymbolPathSearch.UnitFor(const AUnitName: string): TPathUnit;
var
  Key: string;
  Data: TUnitIndex;
begin
  Key := LowerCase(AUnitName);
  if FUnits.TryGetValue(Key, Result) then
    Exit;
  Result := nil;
  if not FIndex.FindUnit(AUnitName, Data) then
    Exit;
  Result := TPathUnit.Create(Data);
  FUnits.Add(Key, Result);
end;

function TSymbolPathSearch.UnitNode(const AUnitName: string): Integer;
var
  Key: string;
  Node: TSymbolPathNode;
  Data: TPathUnit;
begin
  Key := 'U|' + LowerCase(AUnitName);
  if FKeys.TryGetValue(Key, Result) then
    Exit;
  Node := Default(TSymbolPathNode);
  Node.IsUnit := True;
  Node.UnitName := AUnitName;
  Data := UnitFor(AUnitName);
  if Data <> nil then
  begin
    Node.UnitName := Data.Data.UnitName;
    Node.FileName := Data.Data.FileName;
    Node.Library_ := Data.Data.Library_;
  end;
  Result := FNodes.Add(Node);
  FKeys.Add(Key, Result);
end;

function SameParameters(const ALeft, ARight: TIndexSymbol): Boolean;
begin
  Result := SameText(string.Join(',', ALeft.ParamTypes), string.Join(',', ARight.ParamTypes));
end;

function Encloses(const AOuter: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((AOuter.StartPos.Line < APosition.Line) or ((AOuter.StartPos.Line = APosition.Line) and
    (AOuter.StartPos.Character <= APosition.Character))) and ((APosition.Line < AOuter.EndPos.Line) or
    ((APosition.Line = AOuter.EndPos.Line) and (APosition.Character <= AOuter.EndPos.Character)));
end;

function TSymbolPathSearch.Canonical(AUnit: TPathUnit; AIndex: Integer): Integer;
var
  Symbol, Other: TIndexSymbol;
  Index, Owner: Integer;
begin
  // Der Index führt eine Routine zweimal: Deklaration (in der Klasse bzw. im interface) und Rumpf im
  // implementation-Teil. Knoten ist immer die Deklaration.
  Result := AIndex;
  Symbol := AUnit.Data.Symbols[AIndex];
  if not (Symbol.Kind in RoutineKinds) then
    Exit;
  if Symbol.Container <> '' then
  begin
    Owner := -1;
    for Index in AUnit.Data.SymbolsNamed(Symbol.Container) do
      if AUnit.Data.Symbols[Index].Kind in StructKinds + [TIndexSymbolKind.HelperType] then
        Owner := Index;
    if (Owner < 0) or Encloses(AUnit.Data.Symbols[Owner].Range, Symbol.SelectionRange.StartPos) then
      Exit;
    for Index in AUnit.MembersOf(Symbol.Container) do
    begin
      Other := AUnit.Data.Symbols[Index];
      if (Index <> AIndex) and (Other.Kind in RoutineKinds) and SameText(Other.Name, Symbol.Name) and
        SameParameters(Other, Symbol) and Encloses(AUnit.Data.Symbols[Owner].Range, Other.SelectionRange.StartPos) then
        Exit(Index);
    end;
  end
  else if not Symbol.InInterface then
    for Index in AUnit.Data.SymbolsNamed(Symbol.Name) do
    begin
      Other := AUnit.Data.Symbols[Index];
      if (Index <> AIndex) and (Other.Kind in RoutineKinds) and (Other.Container = '') and Other.InInterface and
        SameParameters(Other, Symbol) then
        Exit(Index);
    end;
end;

function TSymbolPathSearch.SymbolNode(AUnit: TPathUnit; AIndex: Integer): Integer;
var
  Key: string;
  Node: TSymbolPathNode;
begin
  AIndex := Canonical(AUnit, AIndex);
  Key := 'S|' + LowerCase(AUnit.Data.UnitName) + '|' + IntToStr(AIndex);
  if FKeys.TryGetValue(Key, Result) then
    Exit;
  Node := Default(TSymbolPathNode);
  Node.UnitName := AUnit.Data.UnitName;
  Node.Symbol := AUnit.Data.Symbols[AIndex];
  Node.FileName := AUnit.Data.SymbolFile(Node.Symbol);
  Node.Library_ := AUnit.Data.Library_;
  Result := FNodes.Add(Node);
  FKeys.Add(Key, Result);
end;

function TSymbolPathSearch.IndexInUnit(AUnit: TPathUnit; const ASymbol: TIndexSymbol): Integer;
var
  Index: Integer;
begin
  Result := -1;
  for Index in AUnit.Data.SymbolsNamed(ASymbol.Name) do
    if SameText(AUnit.Data.Symbols[Index].Container, ASymbol.Container) then
    begin
      if Result < 0 then
        Result := Index;
      if AUnit.Data.Symbols[Index].SelectionRange.StartPos = ASymbol.SelectionRange.StartPos then
        Exit(Index);
    end;
end;

function TSymbolPathSearch.NodeOf(const ALocation: TSymbolLocation): Integer;
var
  Data: TPathUnit;
  Index: Integer;
begin
  Result := -1;
  Data := UnitFor(ALocation.UnitName);
  if Data = nil then
    Exit;
  Index := IndexInUnit(Data, ALocation.Symbol);
  if Index >= 0 then
    Result := SymbolNode(Data, Index);
end;

function TSymbolPathSearch.NodeUnit(ANode: Integer): TPathUnit;
begin
  Result := UnitFor(FNodes[ANode].UnitName);
end;

function TSymbolPathSearch.ContainerNode(AUnit: TPathUnit; const ASymbol: TIndexSymbol): Integer;
var
  Index, Found: Integer;
begin
  Result := -1;
  if ASymbol.Container = '' then
    Exit;
  // Die letzte Deklaration gewinnt: TFoo = class; (Vorwärtsdeklaration) steht vor der vollständigen.
  Found := -1;
  for Index in AUnit.Data.SymbolsNamed(ASymbol.Container) do
    if AUnit.Data.Symbols[Index].Kind in StructKinds + [TIndexSymbolKind.HelperType] then
      Found := Index;
  if Found >= 0 then
    Result := SymbolNode(AUnit, Found);
end;

function TSymbolPathSearch.Visible(AUnit: TPathUnit; const AUnitName: string): Integer;
var
  Index: Integer;
begin
  // Spätere uses-Einträge verdecken frühere: höchste Stelle zählt.
  Result := -1;
  for Index := 0 to High(AUnit.UsesNames) do
    if UsesMatches(AUnit.UsesNames[Index], AUnitName) then
      Result := Index;
end;

function TSymbolPathSearch.ResolveType(AUnit: TPathUnit; const AName: string): TTypeTarget;
var
  Key, Name, Qualifier: string;
  Dot, Best, BestRank, Rank, Index: Integer;
  Location: TSymbolLocation;
  Candidates: TList<TSymbolLocation>;
  Seen: TDictionary<string, Integer>;
  Node: Integer;
begin
  Key := LowerCase(AUnit.Data.UnitName) + '|' + LowerCase(AName);
  if FTypes.TryGetValue(Key, Result) then
    Exit;
  Result := Default(TTypeTarget);
  Name := AName;
  Qualifier := '';
  Dot := LastDelimiter('.', Name);
  if Dot > 0 then
  begin
    Qualifier := Copy(Name, 1, Dot - 1);
    Name := Copy(Name, Dot + 1, MaxInt);
  end;
  Candidates := TList<TSymbolLocation>.Create;
  Seen := TDictionary<string, Integer>.Create;
  try
    for Location in FIndex.FindSymbols(Name) do
    begin
      if not (Location.Symbol.Kind in TypeKinds) then
        Continue;
      if (Qualifier <> '') and not SameText(Location.Symbol.Container, LastSegment(Qualifier)) and
        not UsesMatches(Qualifier, Location.UnitName) then
        Continue;
      // Vorwärtsdeklaration und vollständige Deklaration: die spätere zählt.
      Rank := 0;
      if Seen.TryGetValue(LowerCase(Location.UnitName + '|' + Location.Symbol.QualifiedName), Rank) then
      begin
        if Candidates[Rank].Symbol.SelectionRange.StartPos.Line < Location.Symbol.SelectionRange.StartPos.Line then
          Candidates[Rank] := Location;
        Continue;
      end;
      Seen.Add(LowerCase(Location.UnitName + '|' + Location.Symbol.QualifiedName), Candidates.Count);
      Candidates.Add(Location);
    end;
    if Candidates.Count = 0 then
    begin
      FTypes.Add(Key, Result);
      Exit;
    end;
    // Eigene Unit vor den Units der uses-Liste (die letzte gewinnt); ohne sichtbaren Treffer erschlossen.
    Best := -1;
    BestRank := -1;
    for Index := 0 to Candidates.Count - 1 do
    begin
      if SameText(Candidates[Index].UnitName, AUnit.Data.UnitName) then
        Rank := MaxInt
      else
        Rank := Visible(AUnit, Candidates[Index].UnitName);
      if Rank > BestRank then
      begin
        BestRank := Rank;
        Best := Index;
      end;
    end;
    if (BestRank >= 0) or (Candidates.Count = 1) then
    begin
      if Best < 0 then
        Best := 0;
      Node := NodeOf(Candidates[Best]);
      if Node >= 0 then
        Result.Nodes := [Node];
    end
    else
    begin
      Result.Inferred := True;
      for Location in Candidates do
      begin
        Node := NodeOf(Location);
        if Node >= 0 then
          Result.Nodes := Result.Nodes + [Node];
      end;
    end;
  finally
    Seen.Free;
    Candidates.Free;
  end;
  FTypes.Add(Key, Result);
end;

function TSymbolPathSearch.InterfacesOf(ANode: Integer): TArray<Integer>;
var
  Ancestor: string;
  Data: TPathUnit;
  Node: Integer;
begin
  Result := nil;
  Data := NodeUnit(ANode);
  if Data = nil then
    Exit;
  for Ancestor in FNodes[ANode].Symbol.Ancestors do
    for Node in ResolveType(Data, Ancestor).Nodes do
      if FNodes[Node].Symbol.Kind = TIndexSymbolKind.InterfaceType then
        Result := Result + [Node];
end;

function TSymbolPathSearch.ImplementersOf(ANode: Integer): TArray<Integer>;
var
  Location: TSymbolLocation;
  Node, Iface: Integer;
begin
  if FImplementers.TryGetValue(ANode, Result) then
    Exit;
  Result := nil;
  for Location in FIndex.Descendants(FNodes[ANode].Symbol.Name) do
  begin
    if Location.Symbol.Kind <> TIndexSymbolKind.ClassType then
      Continue;
    Node := NodeOf(Location);
    if Node < 0 then
      Continue;
    for Iface in InterfacesOf(Node) do
      if Iface = ANode then
      begin
        Result := Result + [Node];
        Break;
      end;
  end;
  FImplementers.Add(ANode, Result);
end;

function TSymbolPathSearch.MemberNamed(ATypeNode: Integer; const AName: string): Integer;
var
  Data: TPathUnit;
  Index: Integer;
begin
  Result := -1;
  Data := NodeUnit(ATypeNode);
  if Data = nil then
    Exit;
  for Index in Data.MembersOf(FNodes[ATypeNode].Symbol.Name) do
    if SameText(Data.Data.Symbols[Index].Name, AName) and (Data.Data.Symbols[Index].Kind in RoutineKinds) then
      Exit(SymbolNode(Data, Index));
end;

function TSymbolPathSearch.ImplementingMember(AClass, AInterface: Integer; const AName: string): Integer;
var
  Resolution, Left, Right, Prefix: string;
  Separator: Integer;
begin
  // Methodenzuordnung IFoo.Bar=Baz geht vor dem gleichnamigen Mitglied.
  for Resolution in FNodes[AClass].Symbol.Resolutions do
  begin
    Separator := Pos('=', Resolution);
    if Separator = 0 then
      Continue;
    Left := Trim(Copy(Resolution, 1, Separator - 1));
    Right := Trim(Copy(Resolution, Separator + 1, MaxInt));
    Prefix := Copy(Left, 1, LastDelimiter('.', Left) - 1);
    if SameText(LastSegment(Left), AName) and SameText(LastSegment(Prefix), FNodes[AInterface].Symbol.Name) then
      Exit(MemberNamed(AClass, Right));
  end;
  Result := MemberNamed(AClass, AName);
end;

procedure TSymbolPathSearch.AddEdge(AList: TList<TPathEdge>; ATarget: Integer; AKind: TSymbolPathEdgeKind;
  AInferred: Boolean; const AFileName: string; const APosition: TTextPosition);
var
  Edge: TPathEdge;
begin
  Edge := Default(TPathEdge);
  Edge.Target := ATarget;
  Edge.Kind := AKind;
  Edge.Inferred := AInferred;
  Edge.FileName := AFileName;
  Edge.Position := APosition;
  Edge.SortKey := LowerCase(FNodes[ATarget].Caption) + '|' + LowerCase(FNodes[ATarget].UnitName) + '|' +
    PositionKey(FNodes[ATarget].Position);
  AList.Add(Edge);
end;

procedure TSymbolPathSearch.AddTypeEdges(AList: TList<TPathEdge>; AUnit: TPathUnit; const ATypeText: string;
  AKind: TSymbolPathEdgeKind; const AFileName: string; const APosition: TTextPosition);
var
  Name: string;
  Target: TTypeTarget;
  Node: Integer;
begin
  for Name in TypeNamesIn(ATypeText) do
  begin
    Target := ResolveType(AUnit, Name);
    for Node in Target.Nodes do
      AddEdge(AList, Node, AKind, Target.Inferred, AFileName, APosition);
  end;
end;

function CompareEdges(const ALeft, ARight: TSymbolPathSearch.TPathEdge): Integer;
begin
  Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
  if Result = 0 then
    Result := CompareStr(ALeft.SortKey, ARight.SortKey);
  if Result = 0 then
    Result := Ord(ALeft.Reverse) - Ord(ARight.Reverse);
  if Result = 0 then
    Result := CompareStr(PositionKey(ALeft.Position), PositionKey(ARight.Position));
end;

/// <summary>Sortiert nach Rang und Ziel und lässt gleiche Kanten (Deklaration und Rumpf derselben Routine)
/// nur einmal stehen.</summary>
procedure SortEdges(var AEdges: TArray<TSymbolPathSearch.TPathEdge>);
var
  Sorted: TArray<TSymbolPathSearch.TPathEdge>;
  Seen: TDictionary<string, Boolean>;
  Edge: TSymbolPathSearch.TPathEdge;
  Key: string;
begin
  TArray.Sort<TSymbolPathSearch.TPathEdge>(AEdges, TComparer<TSymbolPathSearch.TPathEdge>.Construct(
    function(const ALeft, ARight: TSymbolPathSearch.TPathEdge): Integer
    begin
      Result := CompareEdges(ALeft, ARight);
    end));
  Sorted := nil;
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Edge in AEdges do
    begin
      Key := Format('%d|%d|%d', [Edge.Target, Ord(Edge.Kind), Ord(Edge.Reverse)]);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, True);
      Sorted := Sorted + [Edge];
    end;
  finally
    Seen.Free;
  end;
  AEdges := Sorted;
end;

function TSymbolPathSearch.BuildForward(ANode: Integer): TPathEdges;
var
  List: TList<TPathEdge>;
  Node: TSymbolPathNode;
  Data: TPathUnit;
  GraphNode, Item, Index, Target, Container: Integer;
  Edge: TPathEdge;
  Ancestor, ParamType, SymbolFile: string;
  Resolved: TTypeTarget;
  Member: TIndexSymbol;
  Implementers: TArray<Integer>;
  Matches: TArray<Integer>;
begin
  Node := FNodes[ANode];
  Data := UnitFor(Node.UnitName);
  if Data = nil then
    Exit(nil);
  List := TList<TPathEdge>.Create;
  try
    if Node.IsUnit then
    begin
      GraphNode := -1;
      if FGraph <> nil then
        GraphNode := FGraph.IndexOf(Node.UnitName);
      if GraphNode >= 0 then
        for Item := 0 to High(FGraph.Node(GraphNode).Outgoing) do
        begin
          if not FGraph.Node(FGraph.Node(GraphNode).Outgoing[Item].Target).Active then
            Continue;
          Edge := Default(TPathEdge);
          Edge.Target := UnitNode(FGraph.Node(FGraph.Node(GraphNode).Outgoing[Item].Target).UnitName);
          Edge.Kind := TSymbolPathEdgeKind.Uses_;
          Edge.FileName := Node.FileName;
          Edge.HasUsesEdge := True;
          Edge.UsesEdge := FGraph.Node(GraphNode).Outgoing[Item];
          // Reihenfolge im Quelltext wie TUsesGraph.Path.
          Edge.SortKey := Format('%.6d', [Item]);
          List.Add(Edge);
        end;
      for Index in Data.MembersOf('') do
        AddEdge(List, SymbolNode(Data, Index), TSymbolPathEdgeKind.Contains, False,
          Data.Data.SymbolFile(Data.Data.Symbols[Index]), Data.Data.Symbols[Index].SelectionRange.StartPos);
    end
    else
    begin
      SymbolFile := Node.FileName;
      if Node.Symbol.Kind in StructKinds then
      begin
        for Ancestor in Node.Symbol.Ancestors do
        begin
          Resolved := ResolveType(Data, Ancestor);
          for Target in Resolved.Nodes do
            if (FNodes[Target].Symbol.Kind = TIndexSymbolKind.InterfaceType) and
              (Node.Symbol.Kind <> TIndexSymbolKind.InterfaceType) then
              AddEdge(List, Target, TSymbolPathEdgeKind.Implements, Resolved.Inferred, SymbolFile,
                Node.Symbol.SelectionRange.StartPos)
            else
              AddEdge(List, Target, TSymbolPathEdgeKind.Inherits, Resolved.Inferred, SymbolFile,
                Node.Symbol.SelectionRange.StartPos);
        end;
        if Node.Symbol.Kind = TIndexSymbolKind.InterfaceType then
        begin
          Implementers := ImplementersOf(ANode);
          for Target in Implementers do
          begin
            AddEdge(List, Target, TSymbolPathEdgeKind.Implements, Length(Implementers) > 1, FNodes[Target].FileName,
              FNodes[Target].Symbol.SelectionRange.StartPos);
            Edge := List[List.Count - 1];
            Edge.Reverse := True;
            List[List.Count - 1] := Edge;
          end;
        end;
        for Index in Data.MembersOf(Node.Symbol.Name) do
        begin
          Member := Data.Data.Symbols[Index];
          AddEdge(List, SymbolNode(Data, Index), TSymbolPathEdgeKind.Contains, False, Data.Data.SymbolFile(Member),
            Member.SelectionRange.StartPos);
          if Member.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_] then
            AddTypeEdges(List, Data, Member.TypeName + ' ' + Member.TypeArgs, TSymbolPathEdgeKind.HasField,
              Data.Data.SymbolFile(Member), Member.SelectionRange.StartPos);
        end;
      end;
      if Node.Symbol.Kind in ValueKinds then
        AddTypeEdges(List, Data, Node.Symbol.TypeName + ' ' + Node.Symbol.TypeArgs, TSymbolPathEdgeKind.HasField,
          SymbolFile, Node.Symbol.SelectionRange.StartPos);
      if Node.Symbol.Kind in RoutineKinds then
      begin
        for ParamType in Node.Symbol.ParamTypes do
          AddTypeEdges(List, Data, ParamType, TSymbolPathEdgeKind.Parameter, SymbolFile,
            Node.Symbol.SelectionRange.StartPos);
        if Node.Symbol.TypeName <> '' then
          AddTypeEdges(List, Data, Node.Symbol.TypeName + ' ' + Node.Symbol.TypeArgs, TSymbolPathEdgeKind.Result_,
            SymbolFile, Node.Symbol.SelectionRange.StartPos);
        Container := ContainerNode(Data, Node.Symbol);
        if (Container >= 0) and (FNodes[Container].Symbol.Kind = TIndexSymbolKind.InterfaceType) then
        begin
          // Interface-Methode → Methoden der umsetzenden Klassen; mehrere Umsetzungen sind erschlossen.
          Matches := nil;
          for Target in ImplementersOf(Container) do
          begin
            Index := ImplementingMember(Target, Container, Node.Symbol.Name);
            if Index >= 0 then
              Matches := Matches + [Index];
          end;
          for Target in Matches do
          begin
            AddEdge(List, Target, TSymbolPathEdgeKind.Implements, Length(Matches) > 1, FNodes[Target].FileName,
              FNodes[Target].Symbol.SelectionRange.StartPos);
            Edge := List[List.Count - 1];
            Edge.Reverse := True;
            List[List.Count - 1] := Edge;
          end;
        end
        else if Container >= 0 then
          for Target in InterfacesOf(Container) do
          begin
            // Klassenmethode → Interface-Methode, die sie umsetzt.
            Index := MemberNamed(Target, Node.Symbol.Name);
            if (Index >= 0) and (ImplementingMember(Container, Target, FNodes[Index].Symbol.Name) = ANode) then
              AddEdge(List, Index, TSymbolPathEdgeKind.Implements, False, SymbolFile,
                Node.Symbol.SelectionRange.StartPos);
          end;
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
  SortEdges(Result);
end;

function TSymbolPathSearch.ForwardOf(ANode: Integer): TPathEdges;
begin
  if not FForward.TryGetValue(ANode, Result) then
  begin
    Result := BuildForward(ANode);
    FForward.Add(ANode, Result);
  end;
end;

function TSymbolPathSearch.CallsOf(ANode: Integer): TPathEdges;
var
  Node: TSymbolPathNode;
  Data, CalleeUnit: TPathUnit;
  Item: THierarchyItem;
  Call: THierarchyCall;
  List: TList<TPathEdge>;
  Location: TSymbolLocation;
  Target: Integer;
  ReadText: TSymbolPathReadText;
  Reader: TReferenceReadText;
begin
  if FCalls.TryGetValue(ANode, Result) then
    Exit;
  Result := nil;
  Node := FNodes[ANode];
  Data := UnitFor(Node.UnitName);
  if Node.IsUnit or not (Node.Symbol.Kind in RoutineKinds) or (Data = nil) or not Assigned(FReadText) then
  begin
    FCalls.Add(ANode, Result);
    Exit;
  end;
  if FResolver = nil then
  begin
    FResolver := TNameResolver.Create(FIndex, FEnsureUnit);
    FResolver.Namespaces := FNamespaces;
  end;
  Item := Default(THierarchyItem);
  Item.Name := Node.Symbol.Name;
  Item.Container := Node.Symbol.Container;
  Item.SymbolKind := Node.Symbol.Kind;
  Item.UnitName := Node.UnitName;
  // Der Rumpf steht in der Datei der Unit, auch wenn die Deklaration aus einer Include-Datei kommt.
  Item.FileName := Data.Data.FileName;
  Item.Range := Node.Symbol.Range;
  Item.SelectionRange := Node.Symbol.SelectionRange;
  ReadText := FReadText;
  // Als typisierte Variable: OutgoingCalls ist überladen.
  Reader :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := ReadText(AFileName, AText);
    end;
  List := TList<TPathEdge>.Create;
  try
    for Call in TLspHierarchies.OutgoingCalls(FResolver, Item, Reader) do
    begin
      CalleeUnit := UnitFor(Call.Item.UnitName);
      if CalleeUnit = nil then
        Continue;
      Location.UnitName := CalleeUnit.Data.UnitName;
      Location.FileName := CalleeUnit.Data.FileName;
      Location.Symbol := Default(TIndexSymbol);
      Location.Symbol.Name := Call.Item.Name;
      Location.Symbol.Container := Call.Item.Container;
      Location.Symbol.SelectionRange := Call.Item.SelectionRange;
      Target := NodeOf(Location);
      if (Target < 0) or (Target = ANode) or (Length(Call.Ranges) = 0) then
        Continue;
      AddEdge(List, Target, TSymbolPathEdgeKind.Calls, False, Item.FileName, Call.Ranges[0].StartPos);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
  SortEdges(Result);
  FCalls.Add(ANode, Result);
end;

procedure TSymbolPathSearch.BuildRefs;

  procedure AddRef(const AName, AUnitName: string; AIndex: Integer);
  var
    Key: string;
    List: TRefList;
    Ref: TSymbolRef;
  begin
    Key := UpperCase(LastSegment(AName));
    if not FRefs.TryGetValue(Key, List) then
    begin
      List := TRefList.Create;
      FRefs.Add(Key, List);
    end;
    Ref.UnitName := AUnitName;
    Ref.Index := AIndex;
    List.Add(Ref);
  end;

var
  Item: TUnitIndex;
  Index: Integer;
  Symbol: TIndexSymbol;
  Name, ParamType: string;
  Scope: TDictionary<string, Boolean>;
  Endpoint: Integer;
begin
  FRefs := TRefMap.Create([doOwnsValues]);
  // Bibliotheks-Units nur als Durchgang mit ThroughLibrary; Start und Ziel immer.
  Scope := TDictionary<string, Boolean>.Create;
  try
    for Endpoint in FEndpoints.Keys do
      Scope.AddOrSetValue(LowerCase(FNodes[Endpoint].UnitName), True);
    for Item in FIndex.Units do
    begin
      if Item.Library_ and not FThroughLibrary and not Scope.ContainsKey(LowerCase(Item.UnitName)) then
        Continue;
      for Index := 0 to High(Item.Symbols) do
      begin
        Symbol := Item.Symbols[Index];
        if not (Symbol.Kind in ValueKinds + RoutineKinds) then
          Continue;
        for Name in TypeNamesIn(Symbol.TypeName + ' ' + Symbol.TypeArgs) do
          AddRef(Name, Item.UnitName, Index);
        if Symbol.Kind in RoutineKinds then
          for ParamType in Symbol.ParamTypes do
            for Name in TypeNamesIn(ParamType) do
              AddRef(Name, Item.UnitName, Index);
      end;
    end;
  finally
    Scope.Free;
  end;
end;

function TSymbolPathSearch.Leads(ASource, ATarget: Integer; AWithCalls: Boolean): Boolean;
var
  Edge: TPathEdge;
begin
  for Edge in ForwardOf(ASource) do
    if (Edge.Target = ATarget) and (Edge.Kind in FVia) then
      Exit(True);
  if AWithCalls then
    for Edge in CallsOf(ASource) do
      if Edge.Target = ATarget then
        Exit(True);
  Result := False;
end;

function TSymbolPathSearch.PredecessorsOf(ANode: Integer): TArray<Integer>;
var
  Candidates: TList<Integer>;
  Seen: TDictionary<Integer, Boolean>;
  Node: TSymbolPathNode;
  Data, RefUnit: TPathUnit;
  GraphNode, Source, Container, Candidate: Integer;
  Location: TSymbolLocation;
  Ancestor: string;
  Refs: TRefList;
  Ref: TSymbolRef;
  Edge: TPathEdge;

  procedure Add(ACandidate: Integer);
  begin
    if (ACandidate >= 0) and (ACandidate <> ANode) and not Seen.ContainsKey(ACandidate) then
    begin
      Seen.Add(ACandidate, True);
      Candidates.Add(ACandidate);
    end;
  end;

begin
  if FPredecessors.TryGetValue(ANode, Result) then
    Exit;
  Result := nil;
  Node := FNodes[ANode];
  Data := UnitFor(Node.UnitName);
  Candidates := TList<Integer>.Create;
  Seen := TDictionary<Integer, Boolean>.Create;
  try
    if Node.IsUnit then
    begin
      GraphNode := -1;
      if FGraph <> nil then
        GraphNode := FGraph.IndexOf(Node.UnitName);
      if GraphNode >= 0 then
        for Source in FGraph.DirectDependents(GraphNode, AllUsesSections) do
          Add(UnitNode(FGraph.Node(Source).UnitName));
    end
    else if Data <> nil then
    begin
      // contains
      if Node.Symbol.Container = '' then
        Add(UnitNode(Node.UnitName))
      else
        Add(ContainerNode(Data, Node.Symbol));
      if Node.Symbol.Kind in StructKinds then
      begin
        // inherits und implements Klasse → Interface
        for Location in FIndex.Descendants(Node.Symbol.Name) do
          Add(NodeOf(Location));
        // implements Interface → Klasse: die Interfaces dieser Klasse
        for Ancestor in Node.Symbol.Ancestors do
          for Candidate in ResolveType(Data, Ancestor).Nodes do
            Add(Candidate);
      end;
      if Node.Symbol.Kind in TypeKinds then
      begin
        // hasField, parameter, result: Deklarationen, deren Typangabe den Namen nennt, und ihre Typen
        if FRefs = nil then
          BuildRefs;
        if FRefs.TryGetValue(UpperCase(Node.Symbol.Name), Refs) then
          for Ref in Refs do
          begin
            RefUnit := UnitFor(Ref.UnitName);
            if RefUnit = nil then
              Continue;
            Candidate := SymbolNode(RefUnit, Ref.Index);
            Add(Candidate);
            if FNodes[Candidate].Symbol.Kind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_] then
              Add(ContainerNode(RefUnit, FNodes[Candidate].Symbol));
          end;
      end;
      if Node.Symbol.Kind in RoutineKinds then
      begin
        // implements je Methode ist in beide Richtungen angelegt.
        for Edge in ForwardOf(ANode) do
          if Edge.Kind = TSymbolPathEdgeKind.Implements then
            Add(Edge.Target);
        Container := ContainerNode(Data, Node.Symbol);
        if Container >= 0 then
          for Candidate in InterfacesOf(Container) do
            Add(MemberNamed(Candidate, Node.Symbol.Name));
      end;
    end;
    // Nur, was wirklich eine Kante hierher hat (gleiche Kanten wie vorwärts).
    for Candidate in Candidates do
      if Passable(Candidate) and Leads(Candidate, ANode, False) then
        Result := Result + [Candidate];
  finally
    Seen.Free;
    Candidates.Free;
  end;
  FPredecessors.Add(ANode, Result);
end;

function HasUsage(const AUnit: TUnitIndex; const AName: string): Boolean;
var
  Usage: TIndexUsage;
begin
  for Usage in AUnit.Usages do
    if SameText(Usage.Name, AName) then
      Exit(True);
  Result := False;
end;

function TSymbolPathSearch.CallersOf(ANode: Integer): TArray<Integer>;
var
  Node: TSymbolPathNode;
  Item: TUnitIndex;
  Data: TPathUnit;
  Index, Candidate: Integer;
  Possible: Boolean;
  Name: string;
begin
  if FCallers.TryGetValue(ANode, Result) then
    Exit;
  Result := nil;
  Node := FNodes[ANode];
  if Node.IsUnit or not (Node.Symbol.Kind in RoutineKinds) then
  begin
    FCallers.Add(ANode, Result);
    Exit;
  end;
  for Item in FIndex.Units do
  begin
    if Stopped then
      Break;
    if Item.Library_ and not FThroughLibrary then
      Continue;
    // Verwendungsindex (#492) als Vorfilter; ohne ihn jede Unit, die die Unit der Routine verwendet.
    if Item.UsagesIndexed and not Item.UsagesOffloaded then
      Possible := HasUsage(Item, Node.Symbol.Name)
    else
    begin
      Possible := SameText(Item.UnitName, Node.UnitName);
      for Name in Item.InterfaceUses + Item.ImplementationUses do
        if UsesMatches(Name, Node.UnitName) then
          Possible := True;
    end;
    if not Possible then
      Continue;
    Data := UnitFor(Item.UnitName);
    if Data = nil then
      Continue;
    for Index := 0 to High(Data.Data.Symbols) do
    begin
      if not (Data.Data.Symbols[Index].Kind in RoutineKinds) then
        Continue;
      Candidate := SymbolNode(Data, Index);
      if (Candidate <> ANode) and Passable(Candidate) and Leads(Candidate, ANode, True) then
        Result := Result + [Candidate];
    end;
  end;
  // Abgebrochen: nicht zwischenspeichern, die Liste ist unvollständig.
  if FAbortReason = '' then
    FCallers.Add(ANode, Result);
end;

function TSymbolPathSearch.Passable(ANode: Integer): Boolean;
begin
  Result := not FNodes[ANode].Library_ or FThroughLibrary or FEndpoints.ContainsKey(ANode);
end;

function TSymbolPathSearch.Endpoints(const AText: string): TArray<Integer>;
var
  Query, Container, Name: string;
  Dot, Node: Integer;
  Location: TSymbolLocation;
  Data: TUnitIndex;
  Seen: TDictionary<string, Integer>;
  Key: string;
  List: TList<Integer>;
begin
  Query := Trim(AText);
  List := TList<Integer>.Create;
  Seen := TDictionary<string, Integer>.Create;
  try
    // Unit (auch ohne Namensraum über den Graphen).
    if FIndex.FindUnit(Query, Data) then
      List.Add(UnitNode(Data.UnitName))
    else if (FGraph <> nil) and (FGraph.IndexOf(Query) >= 0) then
      List.Add(UnitNode(FGraph.Node(FGraph.IndexOf(Query)).UnitName));
    // Symbol wie bei find_symbol: einfach, TTyp.Name oder Unit.Name.
    Name := Query;
    Container := '';
    Dot := LastDelimiter('.', Name);
    if Dot > 0 then
    begin
      Container := Copy(Name, 1, Dot - 1);
      if LastDelimiter('.', Container) > 0 then
        Container := Copy(Container, LastDelimiter('.', Container) + 1, MaxInt);
      Name := Copy(Name, Dot + 1, MaxInt);
    end;
    for Location in FIndex.FindSymbols(Name) do
    begin
      if (Container <> '') and not SameText(Location.Symbol.Container, Container) and
        not ((Dot > 0) and SameText(Location.UnitName, Copy(Query, 1, Dot - 1))) then
        Continue;
      // Deklaration und Rumpf einer Routine sind derselbe Knoten (Canonical).
      Node := NodeOf(Location);
      if Node < 0 then
        Continue;
      Key := IntToStr(Node);
      if Seen.ContainsKey(Key) then
        Continue;
      Seen.Add(Key, List.Count);
      List.Add(Node);
    end;
    Result := List.ToArray;
  finally
    Seen.Free;
    List.Free;
  end;
end;

function TSymbolPathSearch.Targets(ANode: Integer): TArray<Integer>;
var
  Data: TPathUnit;
  Index: Integer;
begin
  Result := [ANode];
  Data := NodeUnit(ANode);
  if Data = nil then
    Exit;
  // Unit: auch ihre Deklarationen; Typ: auch seine Mitglieder.
  if FNodes[ANode].IsUnit then
  begin
    for Index := 0 to High(Data.Data.Symbols) do
      Result := Result + [SymbolNode(Data, Index)];
  end
  else if FNodes[ANode].Symbol.Kind in StructKinds then
    for Index in Data.MembersOf(FNodes[ANode].Symbol.Name) do
      Result := Result + [SymbolNode(Data, Index)];
end;

function TSymbolPathSearch.EdgesFor(ANode: Integer; AWithCalls: Boolean): TPathEdges;
var
  Edge: TPathEdge;
begin
  Result := nil;
  for Edge in ForwardOf(ANode) do
    if Edge.Kind in FVia then
      Result := Result + [Edge];
  if AWithCalls then
  begin
    Result := Result + CallsOf(ANode);
    SortEdges(Result);
  end;
end;

function TSymbolPathSearch.Search(AStart: Integer; const ATargets: TArray<Integer>; AWithCalls: Boolean;
  ALimit: Integer; out ALength, AForwardDepth: Integer): TOutcome;
var
  FrontF, FrontB, Next: TFrontier;
  DepthF, DepthB, Best, Node, Neighbour, Other, Count: Integer;
  Forward_: Boolean;
  Edge: TPathEdge;
  Neighbours: TArray<Integer>;
begin
  ALength := -1;
  AForwardDepth := 0;
  FDistF.Clear;
  FDistB.Clear;
  FDistF.Add(AStart, 0);
  for Node in ATargets do
    FDistB.AddOrSetValue(Node, 0);
  if FDistB.ContainsKey(AStart) then
  begin
    ALength := 0;
    Exit(TOutcome.Found);
  end;
  Inc(FVisited, FDistF.Count + FDistB.Count);
  FrontF := TFrontier.Create;
  FrontB := TFrontier.Create;
  try
    FrontF.Add(AStart);
    FrontB.AddRange(ATargets);
    DepthF := 0;
    DepthB := 0;
    // Je Schritt die kleinere Front um eine ganze Ebene erweitern; sobald sich beide treffen, ist die
    // kürzeste Länge das Minimum über die gemeinsamen Knoten.
    while DepthF + DepthB < ALimit do
    begin
      if (FrontF.Count = 0) or (FrontB.Count = 0) then
        Exit(TOutcome.NoPath);
      Forward_ := FrontF.Count <= FrontB.Count;
      Next := TFrontier.Create;
      try
        if Forward_ then
          Neighbours := FrontF.ToArray
        else
          Neighbours := FrontB.ToArray;
        Count := 0;
        for Node in Neighbours do
        begin
          Inc(Count);
          // Am Anfang jeder Ebene und dann alle CheckEvery Knoten.
          if ((Count mod CheckEvery = 1) or (FVisited > FMaxNodes)) and Stopped then
          begin
            FSearchedSteps := DepthF + DepthB;
            Exit(TOutcome.Aborted);
          end;
          if Forward_ then
          begin
            for Edge in EdgesFor(Node, AWithCalls) do
            begin
              Neighbour := Edge.Target;
              if FDistF.ContainsKey(Neighbour) or not Passable(Neighbour) then
                Continue;
              FDistF.Add(Neighbour, DepthF + 1);
              Inc(FVisited);
              Next.Add(Neighbour);
            end;
          end
          else
          begin
            for Neighbour in PredecessorsOf(Node) do
              if not FDistB.ContainsKey(Neighbour) then
              begin
                FDistB.Add(Neighbour, DepthB + 1);
                Inc(FVisited);
                Next.Add(Neighbour);
              end;
            if AWithCalls then
              for Neighbour in CallersOf(Node) do
                if not FDistB.ContainsKey(Neighbour) then
                begin
                  FDistB.Add(Neighbour, DepthB + 1);
                  Inc(FVisited);
                  Next.Add(Neighbour);
                end;
            if FAbortReason <> '' then
            begin
              FSearchedSteps := DepthF + DepthB;
              Exit(TOutcome.Aborted);
            end;
          end;
        end;
        if Forward_ then
        begin
          Inc(DepthF);
          FrontF.Free;
          FrontF := Next;
        end
        else
        begin
          Inc(DepthB);
          FrontB.Free;
          FrontB := Next;
        end;
        Next := nil;
      finally
        Next.Free;
      end;
      Best := -1;
      if Forward_ then
      begin
        for Node in FrontF do
          if FDistB.TryGetValue(Node, Other) and ((Best < 0) or (DepthF + Other < Best)) then
            Best := DepthF + Other;
      end
      else
        for Node in FrontB do
          if FDistF.TryGetValue(Node, Other) and ((Best < 0) or (DepthB + Other < Best)) then
            Best := DepthB + Other;
      if Best >= 0 then
      begin
        ALength := Best;
        AForwardDepth := DepthF;
        Exit(TOutcome.Found);
      end;
    end;
    Result := TOutcome.NoPath;
  finally
    FrontB.Free;
    FrontF.Free;
  end;
end;

function TSymbolPathSearch.Collect(AStart, ALength, AForwardDepth: Integer; AWithCalls: Boolean;
  AMax: Integer): TArray<TStepRefs>;
var
  Found: TList<TStepRefs>;
  Dead: TDictionary<Integer, Boolean>;
  Current: TList<TStepRef>;

  function Fits(ANode, APosition: Integer): Boolean;
  var
    Distance: Integer;
  begin
    if APosition <= AForwardDepth then
    begin
      Result := FDistF.TryGetValue(ANode, Distance) and (Distance = APosition);
      if Result and (APosition = ALength) then
        Result := FDistB.TryGetValue(ANode, Distance) and (Distance = 0);
    end
    else
      Result := FDistB.TryGetValue(ANode, Distance) and (Distance = ALength - APosition);
  end;

  procedure Walk(ANode, APosition: Integer);
  var
    Edge: TPathEdge;
    Before: Integer;
    Step: TStepRef;
  begin
    if APosition = ALength then
    begin
      Found.Add(Current.ToArray);
      Exit;
    end;
    Before := Found.Count;
    for Edge in EdgesFor(ANode, AWithCalls) do
    begin
      if Found.Count >= AMax then
        Exit;
      if Dead.ContainsKey(Edge.Target) or not Fits(Edge.Target, APosition + 1) then
        Continue;
      Step.Source := ANode;
      Step.Edge := Edge;
      Current.Add(Step);
      Walk(Edge.Target, APosition + 1);
      Current.Delete(Current.Count - 1);
    end;
    if Found.Count = Before then
      Dead.AddOrSetValue(ANode, True);
  end;

begin
  Found := TList<TStepRefs>.Create;
  Dead := TDictionary<Integer, Boolean>.Create;
  Current := TList<TStepRef>.Create;
  try
    Walk(AStart, 0);
    Result := Found.ToArray;
  finally
    Current.Free;
    Dead.Free;
    Found.Free;
  end;
end;

function TSymbolPathSearch.RouteOf(AStart: Integer; const ASteps: TStepRefs): TSymbolPathRoute;
var
  Ref: TStepRef;
  Step: TSymbolPathStep;
  Location: TUsesLocation;
begin
  Result.Nodes := [FNodes[AStart]];
  Result.Steps := nil;
  for Ref in ASteps do
  begin
    Step := Default(TSymbolPathStep);
    Step.Kind := Ref.Edge.Kind;
    Step.Reverse := Ref.Edge.Reverse;
    Step.Inferred := Ref.Edge.Inferred;
    Step.FileName := Ref.Edge.FileName;
    Step.Position := Ref.Edge.Position;
    if Ref.Edge.HasUsesEdge then
    begin
      Step.Implementation_ := Ref.Edge.UsesEdge.Section = TUsesSection.Implementation_;
      if (FLocator <> nil) and FLocator.Locate(FGraph, Ref.Edge.UsesEdge, Location) then
      begin
        Step.FileName := Location.FileName;
        Step.Position := Location.Range.StartPos;
      end;
    end;
    Result.Steps := Result.Steps + [Step];
    Result.Nodes := Result.Nodes + [FNodes[Ref.Edge.Target]];
  end;
end;

function TSymbolPathSearch.Find(const ARequest: TSymbolPathRequest;
  const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
var
  Starts, Ends, Goal: TArray<Integer>;
  Start, Node, Length1, Length2, Depth1, Depth2: Integer;
  Outcome1, Outcome2: TOutcome;
  Paths: TArray<TStepRefs>;
  Path: TStepRefs;
  WithCalls: Boolean;
begin
  Result := Default(TSymbolPathResult);
  Result.From := ARequest.From;
  Result.To_ := ARequest.To_;
  Result.MaxSteps := EnsureRange(ARequest.MaxSteps, 1, TSymbolPathRequest.MaxStepsLimit);
  Result.Restricted := ARequest.Via <> AllSymbolPathEdges;
  FClock := TStopwatch.GetTimeStamp;
  FVia := ARequest.Via;
  FThroughLibrary := ARequest.ThroughLibrary;
  FMaxNodes := ARequest.MaxNodes;
  if FMaxNodes <= 0 then
    FMaxNodes := TSymbolPathRequest.DefaultNodes;
  FTimeoutMs := ARequest.TimeoutMs;
  FCancelled := ACancelled;
  FVisited := 0;
  FAbortReason := '';
  // Mehrdeutig oder unbekannt: Trefferliste statt Suche.
  Starts := Endpoints(ARequest.From);
  Ends := Endpoints(ARequest.To_);
  if (Length(Starts) <> 1) or (Length(Ends) <> 1) then
  begin
    if Length(Starts) = 0 then
    begin
      Result.Status := TSymbolPathStatus.NotFound;
      Result.Subject := ARequest.From;
    end
    else if Length(Starts) > 1 then
    begin
      Result.Status := TSymbolPathStatus.Ambiguous;
      Result.Subject := ARequest.From;
      for Node in Starts do
        Result.Candidates := Result.Candidates + [FNodes[Node]];
    end
    else if Length(Ends) = 0 then
    begin
      Result.Status := TSymbolPathStatus.NotFound;
      Result.Subject := ARequest.To_;
    end
    else
    begin
      Result.Status := TSymbolPathStatus.Ambiguous;
      Result.Subject := ARequest.To_;
      for Node in Ends do
        Result.Candidates := Result.Candidates + [FNodes[Node]];
    end;
    Result.ElapsedMs := Elapsed;
    Exit;
  end;
  Start := Starts[0];
  Result.Target := FNodes[Ends[0]];
  Goal := Targets(Ends[0]);
  FEndpoints.Clear;
  FEndpoints.Add(Start, True);
  for Node in Goal do
    FEndpoints.AddOrSetValue(Node, True);
  // Stufe 1: Kanten aus dem Index.
  Outcome1 := Search(Start, Goal, False, Result.MaxSteps, Length1, Depth1);
  Paths := nil;
  WithCalls := False;
  if Outcome1 = TOutcome.Found then
    Paths := Collect(Start, Length1, Depth1, False, TSymbolPathRequest.MaxRoutes + 1);
  // Stufe 2: nur ein kürzerer Weg über Aufrufe.
  if (TSymbolPathEdgeKind.Calls in FVia) and (Outcome1 <> TOutcome.Aborted) and
    ((Outcome1 = TOutcome.NoPath) or (Length1 > 1)) then
  begin
    if Outcome1 = TOutcome.Found then
      Outcome2 := Search(Start, Goal, True, Length1 - 1, Length2, Depth2)
    else
      Outcome2 := Search(Start, Goal, True, Result.MaxSteps, Length2, Depth2);
    if Outcome2 = TOutcome.Found then
    begin
      Paths := Collect(Start, Length2, Depth2, True, TSymbolPathRequest.MaxRoutes + 1);
      WithCalls := True;
      Outcome1 := TOutcome.Found;
    end
    else if Outcome2 = TOutcome.Aborted then
    begin
      if Outcome1 = TOutcome.Found then
      begin
        Result.CallsIncomplete := True;
        Result.AbortReason := FAbortReason;
        Result.SearchedSteps := FSearchedSteps;
      end
      else
        Outcome1 := TOutcome.Aborted;
    end;
  end;
  case Outcome1 of
    TOutcome.Found:
      begin
        Result.Status := TSymbolPathStatus.Found;
        Result.RouteCount := Min(Length(Paths), TSymbolPathRequest.MaxRoutes);
        Result.MoreRoutes := Length(Paths) > TSymbolPathRequest.MaxRoutes;
        for Path in Paths do
        begin
          if Length(Result.Routes) >= Result.RouteCount then
            Break;
          if (Length(Result.Routes) > 0) and not ARequest.All then
            Break;
          Result.Routes := Result.Routes + [RouteOf(Start, Path)];
        end;
        if WithCalls then
          Result.SearchedSteps := Length2
        else
          Result.SearchedSteps := Length1;
      end;
    TOutcome.NoPath:
      begin
        Result.Status := TSymbolPathStatus.NoPath;
        Result.SearchedSteps := Result.MaxSteps;
      end;
  else
    Result.Status := TSymbolPathStatus.Aborted;
    Result.AbortReason := FAbortReason;
    Result.SearchedSteps := FSearchedSteps;
  end;
  Result.Visited := FVisited;
  Result.ElapsedMs := Elapsed;
end;

class function TSymbolPathSearch.Run(const AIndex: ISymbolIndex; AGraphs: TUsesGraphService;
  ALocator: TUsesLocator; const AReadText: TSymbolPathReadText; const AEnsureUnit: TEnsureUnitFunc;
  const ANamespaces: TArray<string>; const ARequest: TSymbolPathRequest;
  const ACancelled: TSymbolPathCancelled): TSymbolPathResult;
var
  Answer: TSymbolPathResult;
begin
  Answer := Default(TSymbolPathResult);
  AGraphs.Read(
    procedure(const AGraph: TUsesGraph)
    var
      Search: TSymbolPathSearch;
    begin
      Search := TSymbolPathSearch.Create(AIndex, AGraph, ALocator, AReadText, AEnsureUnit);
      try
        Search.Namespaces := ANamespaces;
        Answer := Search.Find(ARequest, ACancelled);
      finally
        Search.Free;
      end;
    end);
  Result := Answer;
end;

class function TSymbolPathSearch.StepCaption(const AStep: TSymbolPathStep; const AFrom: TSymbolPathNode): string;
begin
  case AStep.Kind of
    TSymbolPathEdgeKind.Uses_:
      if AStep.Implementation_ then
        Result := 'verwendet (implementation)'
      else
        Result := 'verwendet';
    TSymbolPathEdgeKind.Inherits:
      Result := 'erbt von';
    TSymbolPathEdgeKind.Implements:
      if AStep.Reverse then
        Result := 'umgesetzt von'
      else
        Result := 'setzt um';
    TSymbolPathEdgeKind.HasField:
      if AFrom.IsUnit or (AFrom.Symbol.Kind in ValueKinds) then
        Result := 'vom Typ'
      else
        Result := 'hat Feld';
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
  Root: string;
begin
  Result := AFileName;
  Root := ARoot;
  while (Root <> '') and CharInSet(Root[Length(Root)], ['\', '/']) do
    Delete(Root, Length(Root), 1);
  if Root = '' then
    Exit;
  // Beide Trenner: Pfade aus Windows-Projekten auch im Linux-Bau.
  if StartsText(Root + '\', AFileName) or StartsText(Root + '/', AFileName) then
    Result := Copy(AFileName, Length(Root) + 2, MaxInt);
end;

function Seconds(AMilliseconds: Int64): string;
var
  Settings: TFormatSettings;
begin
  Settings := TFormatSettings.Create;
  Settings.DecimalSeparator := ',';
  Result := FormatFloat('0.00', AMilliseconds / 1000, Settings) + ' s';
end;

function StepsText(ACount: Integer): string;
begin
  if ACount = 1 then
    Result := '1 Schritt'
  else
    Result := Format('%d Schritten', [ACount]);
end;

class function TSymbolPathSearch.Text(const AResult: TSymbolPathResult; const ARoot: string): string;
var
  Lines: TStringBuilder;
  Route: TSymbolPathRoute;
  RouteIndex, Index, Steps: Integer;
  Caption, Location, Header: string;
  Node: TSymbolPathNode;
begin
  Lines := TStringBuilder.Create;
  try
    case AResult.Status of
      TSymbolPathStatus.NotFound:
        Lines.Append(Format('Kein Symbol und keine Unit "%s" im Index.', [AResult.Subject]));
      TSymbolPathStatus.Ambiguous:
        begin
          Lines.Append(Format('"%s" ist mehrdeutig (%d Treffer):', [AResult.Subject, Length(AResult.Candidates)]));
          for Node in AResult.Candidates do
            Lines.Append(sLineBreak).Append(Format('  %s  %s:%d', [Node.Caption, RelativePath(Node.FileName, ARoot),
              Node.Position.Line + 1]));
          Lines.Append(sLineBreak).Append('Bitte qualifiziert angeben (TTyp.Name oder Unit.Name).');
        end;
      TSymbolPathStatus.NoPath:
        begin
          Lines.Append(Format('Kein Weg in höchstens %s.', [StepsText(AResult.MaxSteps)]));
          if AResult.Restricted then
            Lines.Append(' Nur die erlaubten Kantenarten (via) wurden durchsucht.');
          Lines.Append(sLineBreak).Append(Format('Durchsucht: %d Knoten, %s', [AResult.Visited,
            Seconds(AResult.ElapsedMs)]));
        end;
      TSymbolPathStatus.Aborted:
        Lines.Append(Format('Kein Weg gefunden in %s (Suche nach %d Knoten abgebrochen: %s).',
          [StepsText(AResult.SearchedSteps), AResult.Visited, AResult.AbortReason]))
          .Append(sLineBreak).Append(Format('Durchsucht: %d Knoten, %s', [AResult.Visited,
          Seconds(AResult.ElapsedMs)]));
    else
      begin
        Steps := 0;
        if Length(AResult.Routes) > 0 then
          Steps := Length(AResult.Routes[0].Steps);
        if Steps = 1 then
          Header := 'Kürzester Weg (1 Schritt'
        else
          Header := Format('Kürzester Weg (%d Schritte', [Steps]);
        if AResult.MoreRoutes then
          Header := Header + Format(', mehr als %d Wege gleich lang', [AResult.RouteCount])
        else if AResult.RouteCount > 1 then
          Header := Header + Format(', %d Wege gleich lang', [AResult.RouteCount]);
        Lines.Append(Header + '):');
        for RouteIndex := 0 to High(AResult.Routes) do
        begin
          Route := AResult.Routes[RouteIndex];
          if Length(AResult.Routes) > 1 then
            Lines.Append(sLineBreak).Append(Format('Weg %d:', [RouteIndex + 1]));
          for Index := 0 to High(Route.Nodes) do
          begin
            Lines.Append(sLineBreak).Append(Format('%d. %s', [Index + 1, Route.Nodes[Index].Caption]));
            if Index > High(Route.Steps) then
              Continue;
            Caption := StepCaption(Route.Steps[Index], Route.Nodes[Index]);
            Location := Format('%s:%d', [RelativePath(Route.Steps[Index].FileName, ARoot),
              Route.Steps[Index].Position.Line + 1]);
            if Route.Steps[Index].Inferred then
              Location := '[erschlossen] ' + Location;
            Lines.Append(sLineBreak).Append('   ' + Caption + StringOfChar(' ', Max(1, 18 - Length(Caption))) +
              Location);
          end;
          Node := Route.Nodes[High(Route.Nodes)];
          if (Node.UnitName <> AResult.Target.UnitName) or (Node.Caption <> AResult.Target.Caption) then
            Lines.Append(sLineBreak).Append(Format('   gehört zu %s', [AResult.Target.Caption]));
        end;
        if AResult.CallsIncomplete then
          Lines.Append(sLineBreak).Append(Format('Hinweis: Kürzere Wege über Aufrufe nur bis %s geprüft ' +
            '(Suche abgebrochen: %s).', [StepsText(AResult.SearchedSteps), AResult.AbortReason]));
        Lines.Append(sLineBreak).Append(Format('Durchsucht: %d Knoten, %s', [AResult.Visited,
          Seconds(AResult.ElapsedMs)]));
      end;
    end;
    Result := Lines.ToString;
  finally
    Lines.Free;
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

class function TSymbolPathSearch.ToJson(const AResult: TSymbolPathResult): TJSONObject;
const
  StatusNames: array[TSymbolPathStatus] of string = ('found', 'noPath', 'aborted', 'ambiguous', 'notFound');
var
  Routes, Nodes, Steps, Candidates: TJSONArray;
  Route: TSymbolPathRoute;
  RouteObject, StepObject: TJSONObject;
  Index: Integer;
  Node: TSymbolPathNode;
begin
  Result := TJSONObject.Create;
  Result.AddPair('status', StatusNames[AResult.Status]);
  Result.AddPair('from', AResult.From);
  Result.AddPair('to', AResult.To_);
  Result.AddPair('maxSteps', TJSONNumber.Create(AResult.MaxSteps));
  Result.AddPair('searchedSteps', TJSONNumber.Create(AResult.SearchedSteps));
  Result.AddPair('visited', TJSONNumber.Create(AResult.Visited));
  Result.AddPair('elapsedMs', TJSONNumber.Create(AResult.ElapsedMs));
  Result.AddPair('routeCount', TJSONNumber.Create(AResult.RouteCount));
  Result.AddPair('moreRoutes', TJSONBool.Create(AResult.MoreRoutes));
  Result.AddPair('callsIncomplete', TJSONBool.Create(AResult.CallsIncomplete));
  Result.AddPair('restricted', TJSONBool.Create(AResult.Restricted));
  if AResult.AbortReason <> '' then
    Result.AddPair('abortReason', AResult.AbortReason);
  if AResult.Subject <> '' then
    Result.AddPair('subject', AResult.Subject);
  if AResult.Status = TSymbolPathStatus.Found then
    Result.AddPair('target', NodeJson(AResult.Target));
  Candidates := TJSONArray.Create;
  Result.AddPair('candidates', Candidates);
  for Node in AResult.Candidates do
    Candidates.AddElement(NodeJson(Node));
  Routes := TJSONArray.Create;
  Result.AddPair('routes', Routes);
  for Route in AResult.Routes do
  begin
    RouteObject := TJSONObject.Create;
    Routes.AddElement(RouteObject);
    Nodes := TJSONArray.Create;
    RouteObject.AddPair('nodes', Nodes);
    for Node in Route.Nodes do
      Nodes.AddElement(NodeJson(Node));
    Steps := TJSONArray.Create;
    RouteObject.AddPair('steps', Steps);
    for Index := 0 to High(Route.Steps) do
    begin
      StepObject := TJSONObject.Create;
      Steps.AddElement(StepObject);
      StepObject.AddPair('kind', EdgeNames[Route.Steps[Index].Kind]);
      StepObject.AddPair('caption', StepCaption(Route.Steps[Index], Route.Nodes[Index]));
      StepObject.AddPair('inferred', TJSONBool.Create(Route.Steps[Index].Inferred));
      StepObject.AddPair('reverse', TJSONBool.Create(Route.Steps[Index].Reverse));
      StepObject.AddPair('implementation', TJSONBool.Create(Route.Steps[Index].Implementation_));
      StepObject.AddPair('file', Route.Steps[Index].FileName);
      StepObject.AddPair('line', TJSONNumber.Create(Route.Steps[Index].Position.Line));
      StepObject.AddPair('character', TJSONNumber.Create(Route.Steps[Index].Position.Character));
    end;
  end;
end;

end.
