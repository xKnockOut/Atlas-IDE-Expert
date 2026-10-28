unit Atlas.Common.Lsp.Hierarchies;

// Typ- und Aufrufhierarchie.
//   - textDocument/prepareTypeHierarchy, typeHierarchy/supertypes, typeHierarchy/subtypes:
//     Vorfahr und Interfaces (ohne Angabe TObject bzw. IInterface) sowie direkte Nachfahren.
//   - textDocument/prepareCallHierarchy, callHierarchy/incomingCalls, callHierarchy/outgoingCalls:
//     aufrufende Routinen über die Referenzsuche, aufgerufene Routinen über die Namensauflösung
//     der Bezeichner im Rumpf.
// Eingehende Aufrufe tragen die Treffersicherheit der Referenzsuche (#1119):
// Je Aufrufer und Einstufung ein Eintrag mit atlasConfidence.
// Der Editor schickt das Element zurück; es wird über Datei, Name und Position der
// Deklaration wiedergefunden.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.JsonRpc.Dispatcher,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.ReferenceConfidence,
  Atlas.Common.Lsp.References;

type
  THierarchyItem = record
    Name: string;
    /// <summary>Umgebender Typ bei Methoden.</summary>
    Container: string;
    SymbolKind: TIndexSymbolKind;
    UnitName: string;
    FileName: string;
    Range: TTextRange;
    SelectionRange: TTextRange;
    /// <summary>SymbolKind des LSP.</summary>
    function LspKind: Integer;
  end;

  THierarchyCall = record
    /// <summary>Aufrufer (incoming) bzw. Aufgerufener (outgoing).</summary>
    Item: THierarchyItem;
    /// <summary>Aufrufstellen im Aufrufer.</summary>
    Ranges: TArray<TTextRange>;
    /// <summary>Einstufung der Aufrufstellen (#1119); ausgehende Aufrufe sind immer sicher.</summary>
    Confidence: TReferenceConfidence;
    /// <summary>Aufruf über ein Interface bzw. eine virtuelle Methode (#1122), sonst None; mit der Zahl der
    /// Umsetzungen, die er erreichen kann. Als atlasDispatch im LSP.</summary>
    Dispatch: TReferenceReason;
    Implementations: Integer;
  end;

  TLspHierarchies = class
  public const
    PrepareTypeMethod = 'textDocument/prepareTypeHierarchy';
    SupertypesMethod = 'typeHierarchy/supertypes';
    SubtypesMethod = 'typeHierarchy/subtypes';
    PrepareCallMethod = 'textDocument/prepareCallHierarchy';
    IncomingMethod = 'callHierarchy/incomingCalls';
    OutgoingMethod = 'callHierarchy/outgoingCalls';
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    FSettingsFor: TReferenceSettingsProvider;
    function NewResolver: TNameResolver;
    function Prepare(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
      ACall: Boolean): TJSONValue;
    function HandlePrepareType(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleSupertypes(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleSubtypes(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandlePrepareCall(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleIncoming(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
    function HandleOutgoing(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt (Code-Review A-03): Die Komposition setzt sie
    /// beim Laden eines Projekts, Anfragen lesen sie in Worker-Threads.</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc = nil);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Klasse, Interface, Record oder Objekt an APosition (bei Variablen deren Typ).</summary>
    class function TypeItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; out AItem: THierarchyItem): Boolean; static;
    class function Supertypes(AResolver: TNameResolver; const AItem: THierarchyItem;
      const AReadText: TReferenceReadText): TArray<THierarchyItem>; static;
    class function Subtypes(const AIndex: ISymbolIndex; const AItem: THierarchyItem): TArray<THierarchyItem>; static;
    /// <summary>Routine oder Methode an APosition, als Deklaration.</summary>
    class function CallItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; out AItem: THierarchyItem): Boolean; static;
    /// <summary>Symbol jeder Art an APosition (Routine, Typ, Feld, Konstante …), als Deklaration (#1120).</summary>
    class function SymbolItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; out AItem: THierarchyItem): Boolean; static;
    /// <summary>Routine mit Rumpf, in der APosition steht, als Aufrufer (procedure TFoo.Bar → Bar in TFoo). False
    /// außerhalb von Routinen und im Kopf der Routine selbst, der deklariert und nicht aufruft.</summary>
    class function CallerAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out AItem: THierarchyItem): Boolean; static;
    /// <summary>Element zu einem Symbol aus dem Index.</summary>
    class function ItemOf(const AUnitName, AFileName: string; const ASymbol: TIndexSymbol): THierarchyItem; static;
    /// <summary>Ist das Element eine Routine oder Methode?</summary>
    class function IsRoutine(const AItem: THierarchyItem): Boolean; static;
    class function IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AItem: THierarchyItem;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken = nil): TArray<THierarchyCall>; overload; static;
    /// <summary>Wie oben, mit erschlossenen Aufrufen nach ASettings (#1119): je Aufrufer und Einstufung ein
    /// Eintrag.</summary>
    class function IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AItem: THierarchyItem;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText; const ASettings: TReferenceSettings;
      const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>; overload; static;
    class function OutgoingCalls(AResolver: TNameResolver; const AItem: THierarchyItem;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken = nil): TArray<THierarchyCall>; overload; static;
    /// <summary>Wie oben; mit AIndex sind Aufrufe über ein Interface oder eine virtuelle Methode samt Zahl der
    /// Umsetzungen gekennzeichnet (#1122).</summary>
    class function OutgoingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AItem: THierarchyItem;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
      overload; static;
    /// <summary>Art des Aufrufs von AResolved (#1122): Interface_, Virtual oder None, dazu die Umsetzungen.</summary>
    class function DispatchOf(const AIndex: ISymbolIndex; const AResolved: TResolvedSymbol;
      out AImplementations: Integer): TReferenceReason; static;
    /// <summary>TypeHierarchyItem bzw. CallHierarchyItem. Der Aufrufer übernimmt das Objekt.</summary>
    class function ItemToJson(const AItem: THierarchyItem): TJSONObject; static;
    class function ItemFromJson(const AValue: TJSONValue; out AItem: THierarchyItem): Boolean; static;
    /// <summary>CallHierarchyIncomingCall[] (AKey 'from') bzw. OutgoingCall[] (AKey 'to').</summary>
    class function CallsToJson(const ACalls: TArray<THierarchyCall>; const AKey: string): TJSONArray; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
    /// <summary>Einstellungen references.* je Datei; nicht gesetzt: Vorgaben.</summary>
    property SettingsFor: TReferenceSettingsProvider read FSettingsFor write FSettingsFor;
  end;

implementation

uses
  Atlas.Common.Lsp.Internals.Namespaces,
  System.Generics.Collections,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.Implementations,
  Atlas.Common.Lsp.Internals.Cancellation;

type
  TIndexSymbolKinds = set of TIndexSymbolKind;

const
  HierarchyTypeKinds: TIndexSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.RecordType,
    TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType];
  RoutineKinds: TIndexSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_, TIndexSymbolKind.Routine];
  MaxCalls = 1000;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function RangeContains(const AOuter: TTextRange; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(AOuter.StartPos, APosition) <= 0) and (ComparePositions(APosition, AOuter.EndPos) < 0);
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function WithoutGenerics(const AName: string): string;
var
  Bracket: Integer;
begin
  Bracket := Pos('<', AName);
  if Bracket > 0 then
    Result := Copy(AName, 1, Bracket - 1)
  else
    Result := AName;
end;

function FromResolved(const ASymbol: TResolvedSymbol): THierarchyItem;
begin
  Result.Name := ASymbol.Name;
  Result.Container := ASymbol.Container;
  Result.SymbolKind := ASymbol.SymbolKind;
  Result.UnitName := ASymbol.UnitName;
  Result.FileName := ASymbol.FileName;
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
end;

function FromIndex(const AUnitName, AFileName: string; const ASymbol: TIndexSymbol): THierarchyItem;
begin
  Result.Name := ASymbol.Name;
  Result.Container := ASymbol.Container;
  Result.SymbolKind := ASymbol.Kind;
  Result.UnitName := AUnitName;
  Result.FileName := AFileName;
  Result.Range := ASymbol.Range;
  Result.SelectionRange := ASymbol.SelectionRange;
end;

function ItemKey(const AItem: THierarchyItem): string;
begin
  Result := UpperCase(AItem.FileName) + '|' + IntToStr(AItem.SelectionRange.StartPos.Line) + ':' +
    IntToStr(AItem.SelectionRange.StartPos.Character);
end;

/// <summary>Symbol des Elements in der aktuellen Fassung seiner Datei.</summary>
function FindItemSymbol(const AItem: THierarchyItem; const AReadText: TReferenceReadText;
  out AUnit: TUnitIndex; out ASymbol: TIndexSymbol): Boolean;
var
  Text: string;
  Symbol: TIndexSymbol;
begin
  Result := False;
  if not (Assigned(AReadText) and AReadText(AItem.FileName, Text)) then
    Exit;
  AUnit := TIndexExtractor.ExtractText(Text, AItem.FileName, nil);
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Name, AItem.Name) and SameText(Symbol.Container, AItem.Container) and
      (Symbol.SelectionRange.StartPos = AItem.SelectionRange.StartPos) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  // Datei inzwischen geändert: erstes gleichnamiges Symbol.
  for Symbol in AUnit.Symbols do
    if SameText(Symbol.Name, AItem.Name) and SameText(Symbol.Container, AItem.Container) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
end;

/// <summary>Innerste Routine mit Rumpf, die APosition enthält; nil außerhalb von Routinen.</summary>
function EnclosingRoutine(ANode: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Entry: TSyntaxPostOrderEntry;
  Index: Integer;
begin
  // Eigener Stapel statt Rekursion (Bericht M1): Der Weg zur Position kann durch tiefe Ausdrücke führen.
  // Wie früher zuerst die Kinder eines Knotens, dann der Knoten selbst; Geschwister in ihrer Reihenfolge.
  Result := nil;
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      if Entry.Done then
      begin
        if (Entry.Node <> ANode) and (Entry.Node.Kind = TSyntaxKind.RoutineDecl) and
          (Entry.Node.FindChild(TSyntaxKind.Block) <> nil) then
          Exit(Entry.Node);
        Continue;
      end;
      Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node, True));
      for Index := Entry.Node.ChildCount - 1 downto 0 do
        if RangeContains(NodeRange(Entry.Node[Index]), APosition) then
          Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node[Index], False));
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Element für eine Routine im Baum (procedure TFoo.Bar → Bar in TFoo).</summary>
function RoutineItem(ATree: TSyntaxTree; ANode: TSyntaxNode; const AFileName: string): THierarchyItem;
var
  Dot: Integer;
  Token: TPascalToken;
  mIndex: Integer;
begin
  Dot := LastDelimiter('.', ANode.Name);
  Result.Name := Copy(ANode.Name, Dot + 1, MaxInt);
  Result.Container := Copy(ANode.Name, 1, Dot - 1);
  if Dot > 0 then
    Result.SymbolKind := TIndexSymbolKind.Method
  else
    Result.SymbolKind := TIndexSymbolKind.Routine;
  Result.UnitName := '';
  Result.FileName := AFileName;
  Result.Range := NodeRange(ANode);
  Result.SelectionRange := Result.Range;
  for mIndex := ATree.FirstTokenFrom(ANode.StartOffset) to High(ATree.Tokens) do
  begin
    Token := ATree.Tokens[mIndex];
    if Token.Offset >= ANode.EndOffset then
      Break;
    // Erst ab dem Knoten: Ein Semikolon davor (unit X;) beendete die Suche sonst vor dem Kopf, und der Name
    // fehlte in SelectionRange (#1120).
    if Token.Offset < ANode.StartOffset then
      Continue;
    if (Token.Kind = TPascalTokenKind.Identifier) and
      (SameText(Token.Text, Result.Name) or SameText(Token.Text, '&' + Result.Name)) then
    begin
      // Bei TFoo.Bar das letzte Vorkommen im Kopf; der Name folgt dem Typ.
      Result.SelectionRange := TTextRange.Create(Token.StartPos, Token.EndPos);
      if Dot = 0 then
        Break;
    end;
    if Token.IsSymbol('(') or Token.IsSymbol(';') or Token.IsSymbol(':') then
      Break;
  end;
end;

/// <summary>Rumpf zur Routine AItem: gleicher Name mit Typ-Präfix bzw. dieselbe Startposition.</summary>
function FindBody(ANode: TSyntaxNode; const AItem: THierarchyItem): TSyntaxNode;
var
  Root: TSyntaxNode;
  Qualified, Name: string;
  Start: TTextPosition;
begin
  if AItem.Container <> '' then
    Qualified := AItem.Container + '.' + AItem.Name
  else
    Qualified := AItem.Name;
  Name := AItem.Name;
  Start := AItem.Range.StartPos;
  Root := ANode;
  // Search statt Rekursion (Bericht M1); ANode selbst zählt wie früher nicht.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate <> Root) and (ACandidate.Kind = TSyntaxKind.RoutineDecl) and
        (ACandidate.FindChild(TSyntaxKind.Block) <> nil) and (SameText(ACandidate.Name, Qualified) or
        (ACandidate.StartPos = Start) and SameText(ACandidate.Name, Name)) then
        Result := TSyntaxSearchStep.Found;
    end);
end;

/// <summary>Deklaration, deren Name an APosition steht (z. B. Methode in der Klasse).</summary>
function DeclarationAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  AKinds: TIndexSymbolKinds; out AItem: THierarchyItem): Boolean;
var
  OwnUnit: TUnitIndex;
  Symbol: TIndexSymbol;
begin
  OwnUnit := TIndexExtractor.Extract(ATree, AFileName);
  for Symbol in OwnUnit.Symbols do
    if (Symbol.Kind in AKinds) and (ComparePositions(Symbol.SelectionRange.StartPos, APosition) <= 0) and
      (ComparePositions(APosition, Symbol.SelectionRange.EndPos) <= 0) then
    begin
      AItem := FromIndex(OwnUnit.UnitName, AFileName, Symbol);
      Exit(True);
    end;
  Result := False;
end;

{ THierarchyItem }

function THierarchyItem.LspKind: Integer;
begin
  case SymbolKind of
    TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType, TIndexSymbolKind.HelperType:
      Result := 5;
    TIndexSymbolKind.InterfaceType:
      Result := 11;
    TIndexSymbolKind.RecordType:
      Result := 23;
    TIndexSymbolKind.Method:
      Result := 6;
    TIndexSymbolKind.Constructor_:
      Result := 9;
  else
    Result := 12;
  end;
end;

{ TLspHierarchies }

function TLspHierarchies.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspHierarchies.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspHierarchies.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspHierarchies.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(PrepareTypeMethod, HandlePrepareType);
  ADispatcher.RegisterConcurrentRequest(SupertypesMethod, HandleSupertypes);
  ADispatcher.RegisterConcurrentRequest(SubtypesMethod, HandleSubtypes);
  ADispatcher.RegisterConcurrentRequest(PrepareCallMethod, HandlePrepareCall);
  ADispatcher.RegisterConcurrentRequest(IncomingMethod, HandleIncoming);
  ADispatcher.RegisterConcurrentRequest(OutgoingMethod, HandleOutgoing);
end;

class function TLspHierarchies.TypeItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AItem: THierarchyItem): Boolean;
var
  Resolved: TResolvedSymbol;
begin
  Resolved := AResolver.ResolveType(ATree, AFileName, APosition);
  Result := Resolved.Found and (Resolved.SymbolKind in HierarchyTypeKinds);
  if Result then
    AItem := FromResolved(Resolved)
  else
    Result := DeclarationAt(ATree, AFileName, APosition, HierarchyTypeKinds, AItem);
end;

class function TLspHierarchies.Supertypes(AResolver: TNameResolver; const AItem: THierarchyItem;
  const AReadText: TReferenceReadText): TArray<THierarchyItem>;
var
  OwnerUnit: TUnitIndex;
  Symbol: TIndexSymbol;
  Names: TArray<string>;
  Name: string;
  Resolved: TResolvedSymbol;
begin
  Result := nil;
  if not FindItemSymbol(AItem, AReadText, OwnerUnit, Symbol) then
    Exit;
  Names := Symbol.Ancestors;
  if Length(Names) = 0 then
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and not SameText(Symbol.Name, 'TObject') then
      Names := ['TObject']
    else if (Symbol.Kind = TIndexSymbolKind.InterfaceType) and not SameText(Symbol.Name, 'IInterface') then
      Names := ['IInterface'];
  for Name in Names do
    if AResolver.ResolveTypeFrom(OwnerUnit, WithoutGenerics(Name), Resolved) and
      (Resolved.SymbolKind in HierarchyTypeKinds) then
      Result := Result + [FromResolved(Resolved)];
end;

class function TLspHierarchies.Subtypes(const AIndex: ISymbolIndex; const AItem: THierarchyItem): TArray<THierarchyItem>;
var
  Locations: TArray<TSymbolLocation>;
  Index, Count: Integer;
begin
  // Einmal anlegen statt je Nachfahr anhängen (Code-Review P-08): bei TObject bzw. TComponent viele Hundert.
  Locations := AIndex.Descendants(AItem.Name);
  SetLength(Result, Length(Locations));
  Count := 0;
  for Index := 0 to High(Locations) do
    if Locations[Index].Symbol.Kind in HierarchyTypeKinds then
    begin
      Result[Count] := FromIndex(Locations[Index].UnitName, Locations[Index].FileName, Locations[Index].Symbol);
      Inc(Count);
    end;
  SetLength(Result, Count);
end;

class function TLspHierarchies.CallItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AItem: THierarchyItem): Boolean;
var
  Resolved: TResolvedSymbol;
begin
  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  Result := (Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (Resolved.SymbolKind in RoutineKinds);
  if Result then
    AItem := FromResolved(Resolved)
  else
    Result := DeclarationAt(ATree, AFileName, APosition, RoutineKinds, AItem);
end;

class function TLspHierarchies.SymbolItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AItem: THierarchyItem): Boolean;
var
  Resolved: TResolvedSymbol;
begin
  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  Result := Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local];
  if Result then
    AItem := FromResolved(Resolved)
  else
    Result := DeclarationAt(ATree, AFileName, APosition, [Low(TIndexSymbolKind)..High(TIndexSymbolKind)], AItem);
end;

class function TLspHierarchies.CallerAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AItem: THierarchyItem): Boolean;
var
  Routine, Header: TSyntaxNode;
begin
  Result := False;
  Routine := EnclosingRoutine(ATree.Root, APosition);
  if Routine = nil then
    Exit;
  // Der Kopf der Implementierung (procedure TFoo.Bar) ist kein Aufruf.
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header <> nil) and RangeContains(NodeRange(Header), APosition) then
    Exit;
  AItem := RoutineItem(ATree, Routine, AFileName);
  Result := True;
end;

class function TLspHierarchies.ItemOf(const AUnitName, AFileName: string; const ASymbol: TIndexSymbol): THierarchyItem;
begin
  Result := FromIndex(AUnitName, AFileName, ASymbol);
end;

class function TLspHierarchies.IsRoutine(const AItem: THierarchyItem): Boolean;
begin
  Result := AItem.SymbolKind in RoutineKinds;
end;

class function TLspHierarchies.IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AItem: THierarchyItem; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
begin
  Result := IncomingCalls(AResolver, AIndex, AItem, AFiles, AReadText, TReferenceSettings.SureOnly, ACancellation);
end;

class function TLspHierarchies.IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AItem: THierarchyItem; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ASettings: TReferenceSettings; const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
var
  Text: string;
  Tree: TSyntaxTree;
  Trees: TObjectDictionary<string, TSyntaxTree>;
  Calls: TList<THierarchyCall>;
  Keys: TDictionary<string, Integer>;
  Locations: TArray<TReferenceLocation>;
  Location: TReferenceLocation;
  Caller: THierarchyItem;
  Call: THierarchyCall;
  Key: string;
  Slot: Integer;
begin
  Result := nil;
  if not (Assigned(AReadText) and AReadText(AItem.FileName, Text)) then
    Exit;
  Trees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  Calls := TList<THierarchyCall>.Create;
  Keys := TDictionary<string, Integer>.Create;
  try
    Tree := TSyntaxTreeCache.Parse(Text);
    Trees.Add(UpperCase(AItem.FileName), Tree);
    Locations := TLspReferences.Find(AResolver, AIndex, Tree, AItem.FileName, AItem.SelectionRange.StartPos, False,
      AFiles, AReadText, ASettings, ACancellation);
    for Location in Locations do
    begin
      if Assigned(ACancellation) then
        ACancellation.ThrowIfCancellationRequested;
      // Formulare rufen nicht auf, sie verweisen nur.
      if SameText(ExtractFileExt(Location.FileName), '.dfm') or SameText(ExtractFileExt(Location.FileName), '.fmx') then
        Continue;
      if not Trees.TryGetValue(UpperCase(Location.FileName), Tree) then
      begin
        if not AReadText(Location.FileName, Text) then
          Continue;
        Tree := TSyntaxTreeCache.Parse(Text);
        Trees.Add(UpperCase(Location.FileName), Tree);
      end;
      if not CallerAt(Tree, Location.FileName, Location.Range.StartPos, Caller) then
        Continue;
      // Sichere und erschlossene Aufrufe desselben Aufrufers getrennt, damit der Editor sie unterscheidet.
      Key := ItemKey(Caller) + '|' + Location.Confidence.LevelName + '|' + Location.Confidence.ReasonName;
      if Keys.TryGetValue(Key, Slot) then
      begin
        Call := Calls[Slot];
        Call.Ranges := Call.Ranges + [Location.Range];
        Calls[Slot] := Call;
      end
      else if Calls.Count < MaxCalls then
      begin
        Call.Item := Caller;
        Call.Ranges := [Location.Range];
        Call.Confidence := Location.Confidence;
        // Erschlossen über Interface oder virtual: derselbe Aufruf erreicht auch andere Umsetzungen (#1122).
        Call.Dispatch := TReferenceReason.None;
        Call.Implementations := 0;
        if Location.Confidence.Reason in [TReferenceReason.Interface_, TReferenceReason.Virtual] then
        begin
          Call.Dispatch := Location.Confidence.Reason;
          Call.Implementations := Location.Confidence.Implementations;
        end;
        Keys.Add(Key, Calls.Count);
        Calls.Add(Call);
      end;
    end;
    Result := Calls.ToArray;
  finally
    Keys.Free;
    Calls.Free;
    Trees.Free;
  end;
end;

class function TLspHierarchies.OutgoingCalls(AResolver: TNameResolver; const AItem: THierarchyItem;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
begin
  Result := OutgoingCalls(AResolver, nil, AItem, AReadText, ACancellation);
end;

class function TLspHierarchies.DispatchOf(const AIndex: ISymbolIndex; const AResolved: TResolvedSymbol;
  out AImplementations: Integer): TReferenceReason;
begin
  Result := TReferenceReason.None;
  AImplementations := 0;
  if (AIndex = nil) or (AResolved.Kind <> TResolvedKind.Symbol) or (AResolved.Container = '') or
    not (AResolved.SymbolKind in RoutineKinds) then
    Exit;
  if TLspImplementations.IsInterfaceType(AIndex, AResolved.Container) then
    Result := TReferenceReason.Interface_
  else if AResolved.IsVirtual then
    Result := TReferenceReason.Virtual
  else
    Exit;
  AImplementations := TLspImplementations.ImplementationCount(AIndex, AResolved.Container, AResolved.Name,
    Result = TReferenceReason.Interface_);
end;

class function TLspHierarchies.OutgoingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AItem: THierarchyItem; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
var
  Text: string;
  Tree: TSyntaxTree;
  Body, Block: TSyntaxNode;
  Token: TPascalToken;
  mIndex: Integer;
  Resolved: TResolvedSymbol;
  Callee: THierarchyItem;
  Calls: TList<THierarchyCall>;
  Keys: TDictionary<string, Integer>;
  Call: THierarchyCall;
  Key: string;
  Slot: Integer;
begin
  Result := nil;
  if not (Assigned(AReadText) and AReadText(AItem.FileName, Text)) then
    Exit;
  Tree := TSyntaxTreeCache.Parse(Text);
  Calls := TList<THierarchyCall>.Create;
  Keys := TDictionary<string, Integer>.Create;
  try
    Body := FindBody(Tree.Root, AItem);
    if Body = nil then
      Exit;
    Block := Body.FindChild(TSyntaxKind.Block);
    for mIndex := Tree.FirstTokenFrom(Block.StartOffset) to High(Tree.Tokens) do
    begin
      Token := Tree.Tokens[mIndex];
      if Token.Offset >= Block.EndOffset then
        Break;
      if (Token.Offset < Block.StartOffset) or (Token.Kind <> TPascalTokenKind.Identifier) then
        Continue;
      if Assigned(ACancellation) then
        ACancellation.ThrowIfCancellationRequested;
      Resolved := AResolver.Resolve(Tree, AItem.FileName, Token.StartPos);
      if not (Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) or not (Resolved.SymbolKind in RoutineKinds) then
        Continue;
      Callee := FromResolved(Resolved);
      Key := ItemKey(Callee);
      if Keys.TryGetValue(Key, Slot) then
      begin
        Call := Calls[Slot];
        Call.Ranges := Call.Ranges + [TTextRange.Create(Token.StartPos, Token.EndPos)];
        Calls[Slot] := Call;
      end
      else if Calls.Count < MaxCalls then
      begin
        Call.Item := Callee;
        Call.Ranges := [TTextRange.Create(Token.StartPos, Token.EndPos)];
        Call.Confidence := TReferenceConfidence.Sure;
        Call.Dispatch := DispatchOf(AIndex, Resolved, Call.Implementations);
        Keys.Add(Key, Calls.Count);
        Calls.Add(Call);
      end;
    end;
    Result := Calls.ToArray;
  finally
    Keys.Free;
    Calls.Free;
    Tree.Free;
  end;
end;

class function TLspHierarchies.ItemToJson(const AItem: THierarchyItem): TJSONObject;
var
  Data: TJSONObject;
  Detail: string;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AItem.Name);
  Result.AddPair('kind', TJSONNumber.Create(AItem.LspKind));
  Detail := AItem.Container;
  if AItem.UnitName <> '' then
    if Detail <> '' then
      Detail := Detail + ' · ' + AItem.UnitName
    else
      Detail := AItem.UnitName;
  if Detail <> '' then
    Result.AddPair('detail', Detail);
  Result.AddPair('uri', TDocumentUris.FromPath(AItem.FileName));
  Result.AddPair('range', TLspPositions.RangeToJson(AItem.Range));
  Result.AddPair('selectionRange', TLspPositions.RangeToJson(AItem.SelectionRange));
  Data := TJSONObject.Create;
  Data.AddPair('container', AItem.Container);
  Data.AddPair('symbolKind', TJSONNumber.Create(Ord(AItem.SymbolKind)));
  Result.AddPair('data', Data);
end;

class function TLspHierarchies.ItemFromJson(const AValue: TJSONValue; out AItem: THierarchyItem): Boolean;
var
  Item: TJSONObject;
  Uri: string;
  RangeValue, SelectionValue: TJSONValue;
  Kind: Integer;
begin
  AItem := Default(THierarchyItem);
  Result := (AValue is TJSONObject) and TJSONObject(AValue).TryGetValue<string>('name', AItem.Name) and
    TJSONObject(AValue).TryGetValue<string>('uri', Uri) and
    TJSONObject(AValue).TryGetValue<TJSONValue>('range', RangeValue) and
    TJSONObject(AValue).TryGetValue<TJSONValue>('selectionRange', SelectionValue);
  if not Result then
    Exit;
  Item := TJSONObject(AValue);
  AItem.FileName := TDocumentUris.ToPath(Uri);
  AItem.Range := TLspPositions.ReadRange(RangeValue);
  AItem.SelectionRange := TLspPositions.ReadRange(SelectionValue);
  if not Item.TryGetValue<string>('data.container', AItem.Container) then
    AItem.Container := '';
  if Item.TryGetValue<Integer>('data.symbolKind', Kind) and (Kind >= Ord(Low(TIndexSymbolKind))) and
    (Kind <= Ord(High(TIndexSymbolKind))) then
    AItem.SymbolKind := TIndexSymbolKind(Kind)
  else
    AItem.SymbolKind := TIndexSymbolKind.Routine;
end;

class function TLspHierarchies.CallsToJson(const ACalls: TArray<THierarchyCall>; const AKey: string): TJSONArray;
var
  Call: THierarchyCall;
  Entry, Dispatch: TJSONObject;
  Ranges: TJSONArray;
  Range: TTextRange;
begin
  Result := TJSONArray.Create;
  for Call in ACalls do
  begin
    Entry := TJSONObject.Create;
    Result.AddElement(Entry);
    Entry.AddPair(AKey, ItemToJson(Call.Item));
    Ranges := TJSONArray.Create;
    Entry.AddPair('fromRanges', Ranges);
    for Range in Call.Ranges do
      Ranges.AddElement(TLspPositions.RangeToJson(Range));
    // Erweiterung (#1119); Editoren ohne Kenntnis übergehen das Feld.
    Entry.AddPair('atlasConfidence', Call.Confidence.ToJson);
    // Erweiterung (#1122): Aufruf über Interface bzw. virtuelle Methode mit der Zahl der Umsetzungen.
    if Call.Dispatch <> TReferenceReason.None then
    begin
      Dispatch := TJSONObject.Create;
      Dispatch.AddPair('kind', TReferenceConfidence.NameOfReason(Call.Dispatch));
      Dispatch.AddPair('implementations', TJSONNumber.Create(Call.Implementations));
      Entry.AddPair('atlasDispatch', Dispatch);
    end;
  end;
end;

function ItemsToJson(const AItems: TArray<THierarchyItem>): TJSONArray;
var
  Item: THierarchyItem;
begin
  Result := TJSONArray.Create;
  for Item in AItems do
    Result.AddElement(TLspHierarchies.ItemToJson(Item));
end;

function ReadItem(const AParams: TJSONValue): THierarchyItem;
var
  Value: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONValue>('item', Value) and
    TLspHierarchies.ItemFromJson(Value, Result)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "item" fehlt oder ist unvollständig');
end;

function TLspHierarchies.NewResolver: TNameResolver;
begin
  Result := TNameResolver.Create(FIndex, FEnsureUnit);
  Result.Namespaces := Namespaces;
end;

function TLspHierarchies.Prepare(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken;
  ACall: Boolean): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Uri: string;
  PositionValue: TJSONValue;
  Document: ITextDocument;
  Tree: TSyntaxTree;
  Shared: ISharedSyntaxTree;
  Resolver: TNameResolver;
  Item: THierarchyItem;
  Found: Boolean;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  if not FStore.TryGet(Uri, Document) then
    Exit(TJSONNull.Create);
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := NewResolver;
  try
    if ACall then
      Found := CallItemAt(Resolver, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), Item)
    else
      Found := TypeItemAt(Resolver, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), Item);
  finally
    Resolver.Free;
  end;
  if not Found then
    Exit(TJSONNull.Create);
  Result := TJSONArray.Create;
  TJSONArray(Result).AddElement(ItemToJson(Item));
end;

function TLspHierarchies.HandlePrepareType(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Prepare(AParams, ACancellation, False);
end;

function TLspHierarchies.HandlePrepareCall(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := Prepare(AParams, ACancellation, True);
end;

function TLspHierarchies.HandleSupertypes(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Resolver: TNameResolver;
begin
  Resolver := NewResolver;
  try
    Result := ItemsToJson(Supertypes(Resolver, ReadItem(AParams), FReadText));
  finally
    Resolver.Free;
  end;
end;

function TLspHierarchies.HandleSubtypes(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
begin
  Result := ItemsToJson(Subtypes(FIndex, ReadItem(AParams)));
end;

function TLspHierarchies.HandleIncoming(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Resolver: TNameResolver;
  Files: TArray<string>;
  Item: THierarchyItem;
  Settings: TReferenceSettings;
begin
  if Assigned(FFiles) then
    Files := FFiles()
  else
    Files := nil;
  Item := ReadItem(AParams);
  if Assigned(FSettingsFor) then
    Settings := FSettingsFor(TDocumentUris.FromPath(Item.FileName))
  else
    Settings := TReferenceSettings.Default;
  Resolver := NewResolver;
  try
    Result := CallsToJson(IncomingCalls(Resolver, FIndex, Item, Files, FReadText, Settings, ACancellation), 'from');
  finally
    Resolver.Free;
  end;
end;

function TLspHierarchies.HandleOutgoing(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Resolver: TNameResolver;
begin
  Resolver := NewResolver;
  try
    Result := CallsToJson(OutgoingCalls(Resolver, FIndex, ReadItem(AParams), FReadText, ACancellation), 'to');
  finally
    Resolver.Free;
  end;
end;

end.
