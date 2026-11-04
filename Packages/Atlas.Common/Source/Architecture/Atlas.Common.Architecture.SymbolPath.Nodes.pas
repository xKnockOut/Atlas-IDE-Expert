unit Atlas.Common.Architecture.SymbolPath.Nodes;

// Knoten und Kanten der Pfadsuche zwischen Symbolen (#1117), ausgelagert aus
// Atlas.Common.Architecture.SymbolPath.
//
// - Ein Knoten ist eine Unit oder eine Deklaration des Index. Die Knotentabelle
//   vergibt je Unit bzw. Deklaration genau eine Nummer; eine Routine mit
//   Deklaration und Rumpf ist ein Knoten (die Deklaration).
// - Kanten tragen einen Sortierschlüssel: Rang der Kantenart, dann bei uses die
//   Reihenfolge im Quelltext, sonst der qualifizierte Name des Ziels.
// - Gleiche Kanten (Ziel, Art, Richtung) stehen nach dem Sortieren nur einmal.

interface

{$SCOPEDENUMS ON}

uses
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Architecture.UsesGraph;

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

  TSymbolPathKinds = set of TIndexSymbolKind;

  TSymbolPathReadText = reference to function(const AFileName: string; out AText: string): Boolean;
  /// <summary>True, wenn die Suche abbrechen soll (MCP-Cancel, $/cancelRequest).</summary>
  TSymbolPathCancelled = reference to function: Boolean;

  /// <summary>Kante der Suche: Ziel (Knotennummer), Art und Fundstelle.</summary>
  TSymbolPathEdge = record
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
  TSymbolPathEdges = TArray<TSymbolPathEdge>;

  /// <summary>Hilfen für Namen in Typangaben und uses-Listen.</summary>
  TSymbolPathNames = class
  public
    /// <summary>Typnamen in einer Typangabe: "TList&lt;TKunde&gt;" → TList, TKunde; "array of TFoo" → TFoo.
    /// </summary>
    class function TypeNamesIn(const AText: string): TArray<string>; static;
    class function LastSegment(const AName: string): string; static;
    /// <summary>Trifft der uses-Eintrag AEntry die Unit AUnitName (SysUtils → System.SysUtils)?</summary>
    class function UsesMatches(const AEntry, AUnitName: string): Boolean; static;
    class function PositionKey(const APosition: TTextPosition): string; static;
  end;

  /// <summary>Eine Unit des Index mit ihren Mitgliedern je Container.</summary>
  TSymbolPathUnit = class
  private type
    TIndexList = TList<Integer>;
  private
    FData: TUnitIndex;
    /// <summary>Container in Großschreibung ('' = Unit-Ebene) → Stellen in Data.Symbols.</summary>
    FMembers: TObjectDictionary<string, TIndexList>;
    FUsesNames: TArray<string>;
  public
    constructor Create(const AData: TUnitIndex);
    destructor Destroy; override;
    function MembersOf(const AContainer: string): TArray<Integer>;
    property Data: TUnitIndex read FData;
    property UsesNames: TArray<string> read FUsesNames;
  end;

  /// <summary>Knoten der Suche: je Unit und Deklaration eine Nummer.</summary>
  TSymbolPathNodeTable = class
  private
    FIndex: ISymbolIndex;
    FUnits: TObjectDictionary<string, TSymbolPathUnit>;
    FNodes: TList<TSymbolPathNode>;
    FKeys: TDictionary<string, Integer>;
    function Canonical(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
    function IndexInUnit(AUnit: TSymbolPathUnit; const ASymbol: TIndexSymbol): Integer;
    /// <summary>Knoten der Unit AQuery (auch ohne Namensraum über AGraph); -1 ohne.</summary>
    function UnitEndpoint(const AQuery: string; AGraph: TUsesGraph): Integer;
  public
    constructor Create(const AIndex: ISymbolIndex);
    destructor Destroy; override;
    function UnitFor(const AUnitName: string): TSymbolPathUnit;
    function UnitNode(const AUnitName: string): Integer;
    function SymbolNode(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
    function NodeOf(const ALocation: TSymbolLocation): Integer;
    function NodeUnit(ANode: Integer): TSymbolPathUnit;
    /// <summary>Knoten des Typs, zu dem ASymbol gehört (die letzte Deklaration); -1 ohne.</summary>
    function ContainerNode(AUnit: TSymbolPathUnit; const ASymbol: TIndexSymbol): Integer;
    /// <summary>Routine AName unter den Mitgliedern des Typs ATypeNode; -1 ohne.</summary>
    function MemberNamed(ATypeNode: Integer; const AName: string): Integer;
    /// <summary>ANode und bei einer Unit ihre Deklarationen, bei einem Typ seine Mitglieder.</summary>
    function Targets(ANode: Integer): TArray<Integer>;
    /// <summary>Knoten zur Angabe AText: Unit, einfacher Name, TTyp.Name oder Unit.Name.</summary>
    function Endpoints(const AText: string; AGraph: TUsesGraph): TArray<Integer>;
    /// <summary>Kante nach ATarget mit Sortierschlüssel aus dessen Namen.</summary>
    function EdgeTo(ATarget: Integer; AKind: TSymbolPathEdgeKind; AInferred: Boolean; const AFileName: string;
      const APosition: TTextPosition): TSymbolPathEdge;
    function Node(ANode: Integer): TSymbolPathNode;
    property Index: ISymbolIndex read FIndex;
  end;

  /// <summary>Kantenliste eines Knotens; ToArray sortiert und lässt gleiche Kanten einmal stehen.</summary>
  TSymbolPathEdgeList = class
  private
    FTable: TSymbolPathNodeTable;
    FItems: TList<TSymbolPathEdge>;
  public
    constructor Create(ATable: TSymbolPathNodeTable);
    destructor Destroy; override;
    procedure Add(const AEdge: TSymbolPathEdge); overload;
    procedure Add(ATarget: Integer; AKind: TSymbolPathEdgeKind; AInferred: Boolean; const AFileName: string;
      const APosition: TTextPosition); overload;
    /// <summary>implements in Gegenrichtung (Interface → Umsetzung) mit der Deklaration des Ziels als Fundstelle.
    /// </summary>
    procedure AddReverse(ATarget: Integer; AInferred: Boolean);
    function ToArray: TSymbolPathEdges;
    /// <summary>Sortiert nach Rang und Ziel und lässt gleiche Kanten (Deklaration und Rumpf derselben Routine)
    /// nur einmal stehen.</summary>
    class procedure Sort(var AEdges: TSymbolPathEdges); static;
  end;

const
  SymbolPathTypeKinds: TSymbolPathKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
  SymbolPathStructKinds: TSymbolPathKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType];
  SymbolPathRoutineKinds: TSymbolPathKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine];
  SymbolPathValueKinds: TSymbolPathKinds = [TIndexSymbolKind.Constant, TIndexSymbolKind.Variable,
    TIndexSymbolKind.Field, TIndexSymbolKind.Property_];

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Defaults;

const
  /// <summary>Wörter in Typangaben, die kein Typname sind (array of TFoo, reference to function …).</summary>
  cTypeWords: array[0..9] of string = ('array', 'of', 'set', 'class', 'packed', 'reference', 'to', 'function',
    'procedure', 'const');

{ TSymbolPathNode }

function TSymbolPathNode.Caption: string;
begin
  if IsUnit then
  begin
    Exit(UnitName);
  end;
  Result := Symbol.QualifiedName;
  if (Symbol.Kind in SymbolPathValueKinds) and (Symbol.TypeName <> '') then
  begin
    Result := Result + ': ' + Symbol.TypeName;
  end;
end;

function TSymbolPathNode.Position: TTextPosition;
begin
  if IsUnit then
  begin
    Result := TTextPosition.Create(0, 0);
  end
  else
  begin
    Result := Symbol.SelectionRange.StartPos;
  end;
end;

{ TSymbolPathNames }

function IsTypeWord(const AWord: string): Boolean;
var
  mWord: string;
begin
  for mWord in cTypeWords do
  begin
    if SameText(mWord, AWord) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Wort ab AText[AIndex] (Buchstaben, Ziffern, _, &amp; und Punkte); AIndex danach hinter dem Wort.
/// Ohne führendes &amp; und abschließende Punkte.</summary>
function ReadWord(const AText: string; var AIndex: Integer): string;
var
  mStart: Integer;
begin
  mStart := AIndex;
  while (AIndex <= Length(AText)) and CharInSet(AText[AIndex], ['A'..'Z', 'a'..'z', '0'..'9', '_', '&', '.']) do
  begin
    Inc(AIndex);
  end;
  Result := Copy(AText, mStart, AIndex - mStart);
  if (Result <> '') and (Result[1] = '&') then
  begin
    Delete(Result, 1, 1);
  end;
  while (Result <> '') and (Result[Length(Result)] = '.') do
  begin
    Delete(Result, Length(Result), 1);
  end;
end;

class function TSymbolPathNames.TypeNamesIn(const AText: string): TArray<string>;
var
  mIndex: Integer;
  mWord: string;
begin
  Result := nil;
  mIndex := 1;
  while mIndex <= Length(AText) do
  begin
    if not CharInSet(AText[mIndex], ['A'..'Z', 'a'..'z', '_', '&']) then
    begin
      Inc(mIndex);
      Continue;
    end;
    mWord := ReadWord(AText, mIndex);
    if (mWord <> '') and not IsTypeWord(mWord) then
    begin
      Result := Result + [mWord];
    end;
  end;
end;

class function TSymbolPathNames.LastSegment(const AName: string): string;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', AName);
  if mDot > 0 then
  begin
    Result := Copy(AName, mDot + 1, MaxInt);
  end
  else
  begin
    Result := AName;
  end;
end;

class function TSymbolPathNames.UsesMatches(const AEntry, AUnitName: string): Boolean;
begin
  Result := SameText(AEntry, AUnitName) or EndsText('.' + AEntry, AUnitName);
end;

class function TSymbolPathNames.PositionKey(const APosition: TTextPosition): string;
begin
  Result := Format('%.6d:%.6d', [APosition.Line, APosition.Character]);
end;

{ TSymbolPathUnit }

constructor TSymbolPathUnit.Create(const AData: TUnitIndex);
var
  mIndex: Integer;
  mKey: string;
  mList: TIndexList;
begin
  inherited Create;
  FData := AData;
  FMembers := TObjectDictionary<string, TIndexList>.Create([doOwnsValues]);
  for mIndex := 0 to High(FData.Symbols) do
  begin
    mKey := UpperCase(FData.Symbols[mIndex].Container);
    if not FMembers.TryGetValue(mKey, mList) then
    begin
      mList := TIndexList.Create;
      FMembers.Add(mKey, mList);
    end;
    mList.Add(mIndex);
  end;
  FUsesNames := FData.InterfaceUses + FData.ImplementationUses;
end;

destructor TSymbolPathUnit.Destroy;
begin
  FMembers.Free;
  inherited;
end;

function TSymbolPathUnit.MembersOf(const AContainer: string): TArray<Integer>;
var
  mList: TIndexList;
begin
  if FMembers.TryGetValue(UpperCase(AContainer), mList) then
  begin
    Result := mList.ToArray;
  end
  else
  begin
    Result := nil;
  end;
end;

{ TSymbolPathNodeTable }

constructor TSymbolPathNodeTable.Create(const AIndex: ISymbolIndex);
begin
  inherited Create;
  FIndex := AIndex;
  FUnits := TObjectDictionary<string, TSymbolPathUnit>.Create([doOwnsValues]);
  FNodes := TList<TSymbolPathNode>.Create;
  FKeys := TDictionary<string, Integer>.Create;
end;

destructor TSymbolPathNodeTable.Destroy;
begin
  FKeys.Free;
  FNodes.Free;
  FUnits.Free;
  inherited;
end;

function TSymbolPathNodeTable.Node(ANode: Integer): TSymbolPathNode;
begin
  Result := FNodes[ANode];
end;

function TSymbolPathNodeTable.UnitFor(const AUnitName: string): TSymbolPathUnit;
var
  mKey: string;
  mData: TUnitIndex;
begin
  mKey := LowerCase(AUnitName);
  if FUnits.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  Result := nil;
  if FIndex.FindUnit(AUnitName, mData) then
  begin
    Result := TSymbolPathUnit.Create(mData);
    FUnits.Add(mKey, Result);
  end;
end;

function TSymbolPathNodeTable.UnitNode(const AUnitName: string): Integer;
var
  mKey: string;
  mNode: TSymbolPathNode;
  mData: TSymbolPathUnit;
begin
  mKey := 'U|' + LowerCase(AUnitName);
  if FKeys.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mNode := Default(TSymbolPathNode);
  mNode.IsUnit := True;
  mNode.UnitName := AUnitName;
  mData := UnitFor(AUnitName);
  if mData <> nil then
  begin
    mNode.UnitName := mData.Data.UnitName;
    mNode.FileName := mData.Data.FileName;
    mNode.Library_ := mData.Data.Library_;
  end;
  Result := FNodes.Add(mNode);
  FKeys.Add(mKey, Result);
end;

function SameParameters(const ALeft, ARight: TIndexSymbol): Boolean;
begin
  Result := SameText(string.Join(',', ALeft.ParamTypes), string.Join(',', ARight.ParamTypes));
end;

/// <summary>APosition liegt in ARange (Grenzen eingeschlossen).</summary>
function Encloses(const ARange: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := ((ARange.StartPos.Line < APosition.Line) or ((ARange.StartPos.Line = APosition.Line) and
    (ARange.StartPos.Character <= APosition.Character))) and ((APosition.Line < ARange.EndPos.Line) or
    ((APosition.Line = ARange.EndPos.Line) and (APosition.Character <= ARange.EndPos.Character)));
end;

/// <summary>Letzte Deklaration des Typs AName (Klasse, Record, Interface, Helfer) in AUnit; -1 ohne.</summary>
function LastStruct(AUnit: TSymbolPathUnit; const AName: string): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex in AUnit.Data.SymbolsNamed(AName) do
  begin
    if AUnit.Data.Symbols[mIndex].Kind in SymbolPathStructKinds + [TIndexSymbolKind.HelperType] then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>Deklaration der Methode AIndex in ihrer Klasse, wenn AIndex der Rumpf außerhalb der Klasse ist; sonst
/// AIndex.</summary>
function MethodDeclaration(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
var
  mSymbol, mOther: TIndexSymbol;
  mIndex, mOwner: Integer;
begin
  Result := AIndex;
  mSymbol := AUnit.Data.Symbols[AIndex];
  mOwner := LastStruct(AUnit, mSymbol.Container);
  if (mOwner < 0) or Encloses(AUnit.Data.Symbols[mOwner].Range, mSymbol.SelectionRange.StartPos) then
  begin
    Exit;
  end;
  for mIndex in AUnit.MembersOf(mSymbol.Container) do
  begin
    mOther := AUnit.Data.Symbols[mIndex];
    if (mIndex <> AIndex) and (mOther.Kind in SymbolPathRoutineKinds) and SameText(mOther.Name, mSymbol.Name) and
      SameParameters(mOther, mSymbol) and Encloses(AUnit.Data.Symbols[mOwner].Range, mOther.SelectionRange.StartPos)
    then
    begin
      Exit(mIndex);
    end;
  end;
end;

/// <summary>Deklaration der freien Routine AIndex im interface, wenn AIndex der Rumpf ist; sonst AIndex.</summary>
function RoutineDeclaration(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
var
  mSymbol, mOther: TIndexSymbol;
  mIndex: Integer;
begin
  Result := AIndex;
  mSymbol := AUnit.Data.Symbols[AIndex];
  for mIndex in AUnit.Data.SymbolsNamed(mSymbol.Name) do
  begin
    mOther := AUnit.Data.Symbols[mIndex];
    if (mIndex <> AIndex) and (mOther.Kind in SymbolPathRoutineKinds) and (mOther.Container = '') and
      mOther.InInterface and SameParameters(mOther, mSymbol) then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TSymbolPathNodeTable.Canonical(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
var
  mSymbol: TIndexSymbol;
begin
  // Der Index führt eine Routine zweimal: Deklaration (in der Klasse bzw. im interface) und Rumpf im
  // implementation-Teil. Knoten ist immer die Deklaration.
  Result := AIndex;
  mSymbol := AUnit.Data.Symbols[AIndex];
  if not (mSymbol.Kind in SymbolPathRoutineKinds) then
  begin
    Exit;
  end;
  if mSymbol.Container <> '' then
  begin
    Result := MethodDeclaration(AUnit, AIndex);
  end
  else if not mSymbol.InInterface then
  begin
    Result := RoutineDeclaration(AUnit, AIndex);
  end;
end;

function TSymbolPathNodeTable.SymbolNode(AUnit: TSymbolPathUnit; AIndex: Integer): Integer;
var
  mKey: string;
  mNode: TSymbolPathNode;
  mIndex: Integer;
begin
  mIndex := Canonical(AUnit, AIndex);
  mKey := 'S|' + LowerCase(AUnit.Data.UnitName) + '|' + IntToStr(mIndex);
  if FKeys.TryGetValue(mKey, Result) then
  begin
    Exit;
  end;
  mNode := Default(TSymbolPathNode);
  mNode.UnitName := AUnit.Data.UnitName;
  mNode.Symbol := AUnit.Data.Symbols[mIndex];
  mNode.FileName := AUnit.Data.SymbolFile(mNode.Symbol);
  mNode.Library_ := AUnit.Data.Library_;
  Result := FNodes.Add(mNode);
  FKeys.Add(mKey, Result);
end;

function TSymbolPathNodeTable.IndexInUnit(AUnit: TSymbolPathUnit; const ASymbol: TIndexSymbol): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex in AUnit.Data.SymbolsNamed(ASymbol.Name) do
  begin
    if not SameText(AUnit.Data.Symbols[mIndex].Container, ASymbol.Container) then
    begin
      Continue;
    end;
    if Result < 0 then
    begin
      Result := mIndex;
    end;
    if AUnit.Data.Symbols[mIndex].SelectionRange.StartPos = ASymbol.SelectionRange.StartPos then
    begin
      Exit(mIndex);
    end;
  end;
end;

function TSymbolPathNodeTable.NodeOf(const ALocation: TSymbolLocation): Integer;
var
  mData: TSymbolPathUnit;
  mIndex: Integer;
begin
  Result := -1;
  mData := UnitFor(ALocation.UnitName);
  if mData = nil then
  begin
    Exit;
  end;
  mIndex := IndexInUnit(mData, ALocation.Symbol);
  if mIndex >= 0 then
  begin
    Result := SymbolNode(mData, mIndex);
  end;
end;

function TSymbolPathNodeTable.NodeUnit(ANode: Integer): TSymbolPathUnit;
begin
  Result := UnitFor(FNodes[ANode].UnitName);
end;

function TSymbolPathNodeTable.ContainerNode(AUnit: TSymbolPathUnit; const ASymbol: TIndexSymbol): Integer;
var
  mFound: Integer;
begin
  Result := -1;
  if ASymbol.Container = '' then
  begin
    Exit;
  end;
  // Die letzte Deklaration gewinnt: TFoo = class; (Vorwärtsdeklaration) steht vor der vollständigen.
  mFound := LastStruct(AUnit, ASymbol.Container);
  if mFound >= 0 then
  begin
    Result := SymbolNode(AUnit, mFound);
  end;
end;

function TSymbolPathNodeTable.MemberNamed(ATypeNode: Integer; const AName: string): Integer;
var
  mData: TSymbolPathUnit;
  mIndex: Integer;
begin
  Result := -1;
  mData := NodeUnit(ATypeNode);
  if mData = nil then
  begin
    Exit;
  end;
  for mIndex in mData.MembersOf(FNodes[ATypeNode].Symbol.Name) do
  begin
    if SameText(mData.Data.Symbols[mIndex].Name, AName) and
      (mData.Data.Symbols[mIndex].Kind in SymbolPathRoutineKinds) then
    begin
      Exit(SymbolNode(mData, mIndex));
    end;
  end;
end;

function TSymbolPathNodeTable.Targets(ANode: Integer): TArray<Integer>;
var
  mData: TSymbolPathUnit;
  mIndex: Integer;
begin
  Result := [ANode];
  mData := NodeUnit(ANode);
  if mData = nil then
  begin
    Exit;
  end;
  // Unit: auch ihre Deklarationen; Typ: auch seine Mitglieder.
  if FNodes[ANode].IsUnit then
  begin
    for mIndex := 0 to High(mData.Data.Symbols) do
    begin
      Result := Result + [SymbolNode(mData, mIndex)];
    end;
  end
  else if FNodes[ANode].Symbol.Kind in SymbolPathStructKinds then
  begin
    for mIndex in mData.MembersOf(FNodes[ANode].Symbol.Name) do
    begin
      Result := Result + [SymbolNode(mData, mIndex)];
    end;
  end;
end;

function TSymbolPathNodeTable.UnitEndpoint(const AQuery: string; AGraph: TUsesGraph): Integer;
var
  mData: TUnitIndex;
begin
  Result := -1;
  if FIndex.FindUnit(AQuery, mData) then
  begin
    Result := UnitNode(mData.UnitName);
  end
  else if (AGraph <> nil) and (AGraph.IndexOf(AQuery) >= 0) then
  begin
    Result := UnitNode(AGraph.Node(AGraph.IndexOf(AQuery)).UnitName);
  end;
end;

function ContainsNode(ANode: Integer; const ANodes: TArray<Integer>): Boolean;
var
  mNode: Integer;
begin
  for mNode in ANodes do
  begin
    if mNode = ANode then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Teilt "Unit.TTyp.Name" in den Namen und den Container davor (nur der letzte Abschnitt). ADot: Stelle
/// des letzten Punkts, 0 ohne.</summary>
procedure SplitQuery(const AQuery: string; out AName, AContainer: string; out ADot: Integer);
begin
  AName := AQuery;
  AContainer := '';
  ADot := LastDelimiter('.', AQuery);
  if ADot > 0 then
  begin
    AContainer := TSymbolPathNames.LastSegment(Copy(AQuery, 1, ADot - 1));
    AName := Copy(AQuery, ADot + 1, MaxInt);
  end;
end;

function TSymbolPathNodeTable.Endpoints(const AText: string; AGraph: TUsesGraph): TArray<Integer>;
var
  mQuery, mContainer, mName: string;
  mDot, mNode: Integer;
  mLocation: TSymbolLocation;
begin
  mQuery := Trim(AText);
  Result := nil;
  // Unit (auch ohne Namensraum über den Graphen).
  mNode := UnitEndpoint(mQuery, AGraph);
  if mNode >= 0 then
  begin
    Result := [mNode];
  end;
  // Symbol wie bei find_symbol: einfach, TTyp.Name oder Unit.Name.
  SplitQuery(mQuery, mName, mContainer, mDot);
  for mLocation in FIndex.FindSymbols(mName) do
  begin
    if (mContainer <> '') and not SameText(mLocation.Symbol.Container, mContainer) and
      not ((mDot > 0) and SameText(mLocation.UnitName, Copy(mQuery, 1, mDot - 1))) then
    begin
      Continue;
    end;
    // Deklaration und Rumpf einer Routine sind derselbe Knoten (Canonical).
    mNode := NodeOf(mLocation);
    if (mNode >= 0) and not ContainsNode(mNode, Result) then
    begin
      Result := Result + [mNode];
    end;
  end;
end;

function TSymbolPathNodeTable.EdgeTo(ATarget: Integer; AKind: TSymbolPathEdgeKind; AInferred: Boolean;
  const AFileName: string; const APosition: TTextPosition): TSymbolPathEdge;
begin
  Result := Default(TSymbolPathEdge);
  Result.Target := ATarget;
  Result.Kind := AKind;
  Result.Inferred := AInferred;
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.SortKey := LowerCase(FNodes[ATarget].Caption) + '|' + LowerCase(FNodes[ATarget].UnitName) + '|' +
    TSymbolPathNames.PositionKey(FNodes[ATarget].Position);
end;

{ TSymbolPathEdgeList }

constructor TSymbolPathEdgeList.Create(ATable: TSymbolPathNodeTable);
begin
  inherited Create;
  FTable := ATable;
  FItems := TList<TSymbolPathEdge>.Create;
end;

destructor TSymbolPathEdgeList.Destroy;
begin
  FItems.Free;
  inherited;
end;

procedure TSymbolPathEdgeList.Add(const AEdge: TSymbolPathEdge);
begin
  FItems.Add(AEdge);
end;

procedure TSymbolPathEdgeList.Add(ATarget: Integer; AKind: TSymbolPathEdgeKind; AInferred: Boolean;
  const AFileName: string; const APosition: TTextPosition);
begin
  FItems.Add(FTable.EdgeTo(ATarget, AKind, AInferred, AFileName, APosition));
end;

procedure TSymbolPathEdgeList.AddReverse(ATarget: Integer; AInferred: Boolean);
var
  mNode: TSymbolPathNode;
  mEdge: TSymbolPathEdge;
begin
  mNode := FTable.Node(ATarget);
  mEdge := FTable.EdgeTo(ATarget, TSymbolPathEdgeKind.Implements, AInferred, mNode.FileName,
    mNode.Symbol.SelectionRange.StartPos);
  mEdge.Reverse := True;
  FItems.Add(mEdge);
end;

function TSymbolPathEdgeList.ToArray: TSymbolPathEdges;
begin
  Result := FItems.ToArray;
  Sort(Result);
end;

function CompareEdges(const ALeft, ARight: TSymbolPathEdge): Integer;
begin
  Result := Ord(ALeft.Kind) - Ord(ARight.Kind);
  if Result = 0 then
  begin
    Result := CompareStr(ALeft.SortKey, ARight.SortKey);
  end;
  if Result = 0 then
  begin
    Result := Ord(ALeft.Reverse) - Ord(ARight.Reverse);
  end;
  if Result = 0 then
  begin
    Result := CompareStr(TSymbolPathNames.PositionKey(ALeft.Position),
      TSymbolPathNames.PositionKey(ARight.Position));
  end;
end;

class procedure TSymbolPathEdgeList.Sort(var AEdges: TSymbolPathEdges);
var
  mSorted: TSymbolPathEdges;
  mSeen: TDictionary<string, Boolean>;
  mEdge: TSymbolPathEdge;
  mKey: string;
begin
  TArray.Sort<TSymbolPathEdge>(AEdges, TComparer<TSymbolPathEdge>.Construct(
    function(const ALeft, ARight: TSymbolPathEdge): Integer
    begin
      Result := CompareEdges(ALeft, ARight);
    end));
  mSorted := nil;
  mSeen := TDictionary<string, Boolean>.Create;
  try
    for mEdge in AEdges do
    begin
      mKey := Format('%d|%d|%d', [mEdge.Target, Ord(mEdge.Kind), Ord(mEdge.Reverse)]);
      if not mSeen.ContainsKey(mKey) then
      begin
        mSeen.Add(mKey, True);
        mSorted := mSorted + [mEdge];
      end;
    end;
  finally
    mSeen.Free;
  end;
  AEdges := mSorted;
end;

end.
