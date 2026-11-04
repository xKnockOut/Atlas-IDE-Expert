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

  /// <summary>Womit Aufrufe gesucht werden: Namensauflösung, Index (für Dispatch, darf nil sein), Lesen der
  /// Dateien und Abbruch (darf nil sein).</summary>
  THierarchyCallSource = record
    Resolver: TNameResolver;
    Index: ISymbolIndex;
    ReadText: TReferenceReadText;
    Cancellation: IJsonRpcCancellationToken;
    class function Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): THierarchyCallSource; static;
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
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc); overload;
    /// <summary>Wie oben mit AEnsureUnit = nil.</summary>
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider); overload;
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
    /// <summary>Routine mit Rumpf, in der APosition steht, samt ihrem Kopf (procedure TFoo.Bar → Bar in TFoo), für
    /// geänderte Zeilen (#1353). False außerhalb von Routinen.</summary>
    class function RoutineAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out AItem: THierarchyItem): Boolean; static;
    /// <summary>Element zu einem Symbol aus dem Index.</summary>
    class function ItemOf(const AUnitName, AFileName: string; const ASymbol: TIndexSymbol): THierarchyItem; static;
    /// <summary>Ist das Element eine Routine oder Methode?</summary>
    class function IsRoutine(const AItem: THierarchyItem): Boolean; static;
    class function IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AItem: THierarchyItem;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>; overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex; const AItem: THierarchyItem;
      const AFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<THierarchyCall>; overload; static;
    /// <summary>Wie oben, mit erschlossenen Aufrufen nach ASettings (#1119): je Aufrufer und Einstufung ein
    /// Eintrag.</summary>
    class function IncomingCalls(const ASource: THierarchyCallSource; const AItem: THierarchyItem;
      const AFiles: TArray<string>; const ASettings: TReferenceSettings): TArray<THierarchyCall>; overload; static;
    class function OutgoingCalls(AResolver: TNameResolver; const AItem: THierarchyItem;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
      overload; static;
    /// <summary>Wie oben ohne Abbruch (ACancellation = nil).</summary>
    class function OutgoingCalls(AResolver: TNameResolver; const AItem: THierarchyItem;
      const AReadText: TReferenceReadText): TArray<THierarchyCall>; overload; static;
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
  begin
    Result := A.Line - B.Line;
  end
  else
  begin
    Result := A.Character - B.Character;
  end;
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
  begin
    Result := Copy(AName, 1, Bracket - 1);
  end
  else
  begin
    Result := AName;
  end;
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
  begin
    Exit;
  end;
  AUnit := TIndexExtractor.ExtractText(Text, AItem.FileName, nil);
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.Name, AItem.Name) and SameText(Symbol.Container, AItem.Container) and
      (Symbol.SelectionRange.StartPos = AItem.SelectionRange.StartPos) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
  end;
  // Datei inzwischen geändert: erstes gleichnamiges Symbol.
  for Symbol in AUnit.Symbols do
  begin
    if SameText(Symbol.Name, AItem.Name) and SameText(Symbol.Container, AItem.Container) then
    begin
      ASymbol := Symbol;
      Exit(True);
    end;
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
        begin
          Exit(Entry.Node);
        end;
        Continue;
      end;
      Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node, True));
      for Index := Entry.Node.ChildCount - 1 downto 0 do
      begin
        if RangeContains(NodeRange(Entry.Node[Index]), APosition) then
        begin
          Pending.Push(TSyntaxPostOrderEntry.Create(Entry.Node[Index], False));
        end;
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Stelle des Namens AName im Kopf von ANode; bei AQualified (TFoo.Bar) das letzte Vorkommen, sonst das
/// erste. ANode selbst, wenn der Name im Kopf fehlt.</summary>
function NameRangeIn(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string; AQualified: Boolean): TTextRange;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  Result := NodeRange(ANode);
  mIndex := ATree.FirstTokenFrom(ANode.StartOffset);
  // Erst ab dem Knoten: Ein Semikolon davor (unit X;) beendete die Suche sonst vor dem Kopf, und der Name
  // fehlte in SelectionRange (#1120).
  while (mIndex <= High(ATree.Tokens)) and (ATree.Tokens[mIndex].Offset < ANode.StartOffset) do
  begin
    Inc(mIndex);
  end;
  while (mIndex <= High(ATree.Tokens)) and (ATree.Tokens[mIndex].Offset < ANode.EndOffset) do
  begin
    mToken := ATree.Tokens[mIndex];
    if (mToken.Kind = TPascalTokenKind.Identifier) and
      (SameText(mToken.Text, AName) or SameText(mToken.Text, '&' + AName)) then
    begin
      // Bei TFoo.Bar das letzte Vorkommen im Kopf; der Name folgt dem Typ.
      Result := TTextRange.Create(mToken.StartPos, mToken.EndPos);
      if not AQualified then
      begin
        Break;
      end;
    end;
    if mToken.IsSymbol('(') or mToken.IsSymbol(';') or mToken.IsSymbol(':') then
    begin
      Break;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Element für eine Routine im Baum (procedure TFoo.Bar → Bar in TFoo).</summary>
function RoutineItem(ATree: TSyntaxTree; ANode: TSyntaxNode; const AFileName: string): THierarchyItem;
var
  mDot: Integer;
begin
  mDot := LastDelimiter('.', ANode.Name);
  Result.Name := Copy(ANode.Name, mDot + 1, MaxInt);
  Result.Container := Copy(ANode.Name, 1, mDot - 1);
  if mDot > 0 then
  begin
    Result.SymbolKind := TIndexSymbolKind.Method;
  end
  else
  begin
    Result.SymbolKind := TIndexSymbolKind.Routine;
  end;
  Result.UnitName := '';
  Result.FileName := AFileName;
  Result.Range := NodeRange(ANode);
  Result.SelectionRange := NameRangeIn(ATree, ANode, Result.Name, mDot > 0);
end;

/// <summary>Routine mit Rumpf (keine Vorwärtsdeklaration).</summary>
function IsRoutineWithBody(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.RoutineDecl) and (ANode.FindChild(TSyntaxKind.Block) <> nil);
end;

/// <summary>ANode gehört zu AItem: gleicher Name mit Typ-Präfix AQualified bzw. dieselbe Startposition.</summary>
function IsBodyOf(ANode: TSyntaxNode; const AItem: THierarchyItem; const AQualified: string): Boolean;
begin
  Result := SameText(ANode.Name, AQualified) or
    ((ANode.StartPos = AItem.Range.StartPos) and SameText(ANode.Name, AItem.Name));
end;

/// <summary>Rumpf zur Routine AItem: gleicher Name mit Typ-Präfix bzw. dieselbe Startposition.</summary>
function FindBody(ANode: TSyntaxNode; const AItem: THierarchyItem): TSyntaxNode;
var
  mRoot: TSyntaxNode;
  mItem: THierarchyItem;
  mQualified: string;
begin
  if AItem.Container <> '' then
  begin
    mQualified := AItem.Container + '.' + AItem.Name;
  end
  else
  begin
    mQualified := AItem.Name;
  end;
  mItem := AItem;
  mRoot := ANode;
  // Search statt Rekursion (Bericht M1); ANode selbst zählt wie früher nicht.
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate <> mRoot) and IsRoutineWithBody(ACandidate) and IsBodyOf(ACandidate, mItem, mQualified) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
end;

/// <summary>Formulare rufen nicht auf, sie verweisen nur.</summary>
function IsFormFile(const AFileName: string): Boolean;
begin
  Result := SameText(ExtractFileExt(AFileName), '.dfm') or SameText(ExtractFileExt(AFileName), '.fmx');
end;

procedure CheckCancelled(const ACancellation: IJsonRpcCancellationToken);
begin
  if Assigned(ACancellation) then
  begin
    ACancellation.ThrowIfCancellationRequested;
  end;
end;

type
  /// <summary>Gesammelte Aufrufe: je Schlüssel ein Eintrag mit allen Aufrufstellen, höchstens MaxCalls.</summary>
  TCallCollector = class
  private
    FCalls: TList<THierarchyCall>;
    FKeys: TDictionary<string, Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Hängt ARange an den Eintrag zu AKey; False, wenn es ihn nicht gibt.</summary>
    function Extend(const AKey: string; const ARange: TTextRange): Boolean;
    /// <summary>Platz für einen neuen Eintrag?</summary>
    function CanAdd: Boolean;
    procedure Add(const AKey: string; const ACall: THierarchyCall);
    function ToArray: TArray<THierarchyCall>;
  end;

  /// <summary>Syntaxbäume der gelesenen Dateien, je Datei einmal geparst.</summary>
  TTreeSet = class
  private
    FTrees: TObjectDictionary<string, TSyntaxTree>;
    FReadText: TReferenceReadText;
  public
    constructor Create(const AReadText: TReferenceReadText);
    destructor Destroy; override;
    /// <summary>Baum von AFileName; False, wenn sich die Datei nicht lesen lässt.</summary>
    function TryGet(const AFileName: string; out ATree: TSyntaxTree): Boolean;
  end;

constructor TCallCollector.Create;
begin
  inherited Create;
  FCalls := TList<THierarchyCall>.Create;
  FKeys := TDictionary<string, Integer>.Create;
end;

destructor TCallCollector.Destroy;
begin
  FKeys.Free;
  FCalls.Free;
  inherited Destroy;
end;

function TCallCollector.Extend(const AKey: string; const ARange: TTextRange): Boolean;
var
  mSlot: Integer;
  mCall: THierarchyCall;
begin
  Result := FKeys.TryGetValue(AKey, mSlot);
  if Result then
  begin
    mCall := FCalls[mSlot];
    mCall.Ranges := mCall.Ranges + [ARange];
    FCalls[mSlot] := mCall;
  end;
end;

function TCallCollector.CanAdd: Boolean;
begin
  Result := FCalls.Count < MaxCalls;
end;

procedure TCallCollector.Add(const AKey: string; const ACall: THierarchyCall);
begin
  FKeys.Add(AKey, FCalls.Count);
  FCalls.Add(ACall);
end;

function TCallCollector.ToArray: TArray<THierarchyCall>;
begin
  Result := FCalls.ToArray;
end;

constructor TTreeSet.Create(const AReadText: TReferenceReadText);
begin
  inherited Create;
  FTrees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  FReadText := AReadText;
end;

destructor TTreeSet.Destroy;
begin
  FTrees.Free;
  inherited Destroy;
end;

function TTreeSet.TryGet(const AFileName: string; out ATree: TSyntaxTree): Boolean;
var
  mText: string;
begin
  Result := FTrees.TryGetValue(UpperCase(AFileName), ATree);
  if not Result and Assigned(FReadText) and FReadText(AFileName, mText) then
  begin
    ATree := TSyntaxTreeCache.Parse(mText);
    FTrees.Add(UpperCase(AFileName), ATree);
    Result := True;
  end;
end;

/// <summary>Neuer eingehender Aufruf von ACaller an ALocation; erschlossen über Interface oder virtual erreicht
/// derselbe Aufruf auch andere Umsetzungen (#1122).</summary>
function IncomingCall(const ACaller: THierarchyItem; const ALocation: TReferenceLocation): THierarchyCall;
begin
  Result.Item := ACaller;
  Result.Ranges := [ALocation.Range];
  Result.Confidence := ALocation.Confidence;
  Result.Dispatch := TReferenceReason.None;
  Result.Implementations := 0;
  if ALocation.Confidence.Reason in [TReferenceReason.Interface_, TReferenceReason.Virtual] then
  begin
    Result.Dispatch := ALocation.Confidence.Reason;
    Result.Implementations := ALocation.Confidence.Implementations;
  end;
end;

/// <summary>Aufruf an ALocation dem Aufrufer zuordnen; außerhalb von Routinen bleibt er weg.</summary>
procedure AddIncoming(ACalls: TCallCollector; ATrees: TTreeSet; const ALocation: TReferenceLocation);
var
  mTree: TSyntaxTree;
  mCaller: THierarchyItem;
  mKey: string;
begin
  if IsFormFile(ALocation.FileName) or not ATrees.TryGet(ALocation.FileName, mTree) or
    not TLspHierarchies.CallerAt(mTree, ALocation.FileName, ALocation.Range.StartPos, mCaller) then
  begin
    Exit;
  end;
  // Sichere und erschlossene Aufrufe desselben Aufrufers getrennt, damit der Editor sie unterscheidet.
  mKey := ItemKey(mCaller) + '|' + ALocation.Confidence.LevelName + '|' + ALocation.Confidence.ReasonName;
  if not ACalls.Extend(mKey, ALocation.Range) and ACalls.CanAdd then
  begin
    ACalls.Add(mKey, IncomingCall(mCaller, ALocation));
  end;
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
  begin
    if (Symbol.Kind in AKinds) and (ComparePositions(Symbol.SelectionRange.StartPos, APosition) <= 0) and
      (ComparePositions(APosition, Symbol.SelectionRange.EndPos) <= 0) then
    begin
      AItem := FromIndex(OwnUnit.UnitName, AFileName, Symbol);
      Exit(True);
    end;
  end;
  Result := False;
end;

{ THierarchyCallSource }

class function THierarchyCallSource.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken): THierarchyCallSource;
begin
  Result.Resolver := AResolver;
  Result.Index := AIndex;
  Result.ReadText := AReadText;
  Result.Cancellation := ACancellation;
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
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider);
begin
  Create(AStore, AIndex, AReadText, AFiles, nil);
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
  begin
    AItem := FromResolved(Resolved);
  end
  else
  begin
    Result := DeclarationAt(ATree, AFileName, APosition, HierarchyTypeKinds, AItem);
  end;
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
  begin
    Exit;
  end;
  Names := Symbol.Ancestors;
  if Length(Names) = 0 then
  begin
    if (Symbol.Kind = TIndexSymbolKind.ClassType) and not SameText(Symbol.Name, 'TObject') then
    begin
      Names := ['TObject'];
    end
    else if (Symbol.Kind = TIndexSymbolKind.InterfaceType) and not SameText(Symbol.Name, 'IInterface') then
    begin
      Names := ['IInterface'];
    end;
  end;
  for Name in Names do
  begin
    if AResolver.ResolveTypeFrom(OwnerUnit, WithoutGenerics(Name), Resolved) and
      (Resolved.SymbolKind in HierarchyTypeKinds) then
    begin
      Result := Result + [FromResolved(Resolved)];
    end;
  end;
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
  begin
    if Locations[Index].Symbol.Kind in HierarchyTypeKinds then
    begin
      Result[Count] := FromIndex(Locations[Index].UnitName, Locations[Index].FileName, Locations[Index].Symbol);
      Inc(Count);
    end;
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
  begin
    AItem := FromResolved(Resolved);
  end
  else
  begin
    Result := DeclarationAt(ATree, AFileName, APosition, RoutineKinds, AItem);
  end;
end;

class function TLspHierarchies.SymbolItemAt(AResolver: TNameResolver; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; out AItem: THierarchyItem): Boolean;
var
  Resolved: TResolvedSymbol;
begin
  Resolved := AResolver.Resolve(ATree, AFileName, APosition);
  Result := Resolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local];
  if Result then
  begin
    AItem := FromResolved(Resolved);
  end
  else
  begin
    Result := DeclarationAt(ATree, AFileName, APosition, [Low(TIndexSymbolKind)..High(TIndexSymbolKind)], AItem);
  end;
end;

class function TLspHierarchies.CallerAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AItem: THierarchyItem): Boolean;
var
  Routine, Header: TSyntaxNode;
begin
  Result := False;
  Routine := EnclosingRoutine(ATree.Root, APosition);
  if Routine = nil then
  begin
    Exit;
  end;
  // Der Kopf der Implementierung (procedure TFoo.Bar) ist kein Aufruf.
  Header := Routine.FindChild(TSyntaxKind.RoutineHeader);
  if (Header <> nil) and RangeContains(NodeRange(Header), APosition) then
  begin
    Exit;
  end;
  AItem := RoutineItem(ATree, Routine, AFileName);
  Result := True;
end;

class function TLspHierarchies.RoutineAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AItem: THierarchyItem): Boolean;
var
  mRoutine: TSyntaxNode;
begin
  mRoutine := EnclosingRoutine(ATree.Root, APosition);
  Result := mRoutine <> nil;
  if Result then
  begin
    AItem := RoutineItem(ATree, mRoutine, AFileName);
  end;
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
  const AItem: THierarchyItem; const AFiles: TArray<string>; const AReadText: TReferenceReadText): TArray<THierarchyCall>;
begin
  Result := IncomingCalls(AResolver, AIndex, AItem, AFiles, AReadText, nil);
end;

class function TLspHierarchies.IncomingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AItem: THierarchyItem; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
begin
  Result := IncomingCalls(THierarchyCallSource.Create(AResolver, AIndex, AReadText, ACancellation), AItem, AFiles,
    TReferenceSettings.SureOnly);
end;

class function TLspHierarchies.IncomingCalls(const ASource: THierarchyCallSource; const AItem: THierarchyItem;
  const AFiles: TArray<string>; const ASettings: TReferenceSettings): TArray<THierarchyCall>;
var
  mTree: TSyntaxTree;
  mTrees: TTreeSet;
  mCalls: TCallCollector;
  mLocation: TReferenceLocation;
begin
  Result := nil;
  mTrees := TTreeSet.Create(ASource.ReadText);
  mCalls := TCallCollector.Create;
  try
    if not mTrees.TryGet(AItem.FileName, mTree) then
    begin
      Exit;
    end;
    for mLocation in TLspReferences.Find(ASource.Resolver, ASource.Index, mTree,
      TReferenceSearch.Create(AItem.FileName, AItem.SelectionRange.StartPos, False, AFiles, ASource.ReadText),
      ASettings, ASource.Cancellation) do
    begin
      CheckCancelled(ASource.Cancellation);
      AddIncoming(mCalls, mTrees, mLocation);
    end;
    Result := mCalls.ToArray;
  finally
    mCalls.Free;
    mTrees.Free;
  end;
end;

class function TLspHierarchies.OutgoingCalls(AResolver: TNameResolver; const AItem: THierarchyItem;
  const AReadText: TReferenceReadText): TArray<THierarchyCall>;
begin
  Result := OutgoingCalls(AResolver, AItem, AReadText, nil);
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
  begin
    Exit;
  end;
  if TLspImplementations.IsInterfaceType(AIndex, AResolved.Container) then
  begin
    Result := TReferenceReason.Interface_;
  end
  else if AResolved.IsVirtual then
  begin
    Result := TReferenceReason.Virtual;
  end
  else
  begin
    Exit;
  end;
  AImplementations := TLspImplementations.ImplementationCount(AIndex, AResolved.Container, AResolved.Name,
    Result = TReferenceReason.Interface_);
end;

/// <summary>Bezeichner ATokenIndex im Rumpf als Aufruf eintragen, wenn er eine Routine bezeichnet.</summary>
procedure AddOutgoing(ACalls: TCallCollector; const ASource: THierarchyCallSource; ATree: TSyntaxTree;
  const AFileName: string; const AToken: TPascalToken);
var
  mResolved: TResolvedSymbol;
  mCall: THierarchyCall;
  mKey: string;
  mRange: TTextRange;
begin
  CheckCancelled(ASource.Cancellation);
  mResolved := ASource.Resolver.Resolve(ATree, AFileName, AToken.StartPos);
  if not (mResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) or not (mResolved.SymbolKind in RoutineKinds) then
  begin
    Exit;
  end;
  mCall.Item := FromResolved(mResolved);
  mKey := ItemKey(mCall.Item);
  mRange := TTextRange.Create(AToken.StartPos, AToken.EndPos);
  if not ACalls.Extend(mKey, mRange) and ACalls.CanAdd then
  begin
    mCall.Ranges := [mRange];
    mCall.Confidence := TReferenceConfidence.Sure;
    mCall.Dispatch := TLspHierarchies.DispatchOf(ASource.Index, mResolved, mCall.Implementations);
    ACalls.Add(mKey, mCall);
  end;
end;

/// <summary>Aufrufe aus dem Block ABlock: jeder Bezeichner, der eine Routine bezeichnet.</summary>
procedure CollectOutgoing(ACalls: TCallCollector; const ASource: THierarchyCallSource; ATree: TSyntaxTree;
  const AFileName: string; ABlock: TSyntaxNode);
var
  mIndex: Integer;
  mToken: TPascalToken;
begin
  for mIndex := ATree.FirstTokenFrom(ABlock.StartOffset) to High(ATree.Tokens) do
  begin
    mToken := ATree.Tokens[mIndex];
    if mToken.Offset >= ABlock.EndOffset then
    begin
      Break;
    end;
    if (mToken.Offset >= ABlock.StartOffset) and (mToken.Kind = TPascalTokenKind.Identifier) then
    begin
      AddOutgoing(ACalls, ASource, ATree, AFileName, mToken);
    end;
  end;
end;

class function TLspHierarchies.OutgoingCalls(AResolver: TNameResolver; const AIndex: ISymbolIndex;
  const AItem: THierarchyItem; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TArray<THierarchyCall>;
var
  mText: string;
  mTree: TSyntaxTree;
  mBody: TSyntaxNode;
  mCalls: TCallCollector;
begin
  Result := nil;
  if not (Assigned(AReadText) and AReadText(AItem.FileName, mText)) then
  begin
    Exit;
  end;
  mTree := TSyntaxTreeCache.Parse(mText);
  mCalls := TCallCollector.Create;
  try
    mBody := FindBody(mTree.Root, AItem);
    if mBody <> nil then
    begin
      CollectOutgoing(mCalls, THierarchyCallSource.Create(AResolver, AIndex, AReadText, ACancellation), mTree,
        AItem.FileName, mBody.FindChild(TSyntaxKind.Block));
      Result := mCalls.ToArray;
    end;
  finally
    mCalls.Free;
    mTree.Free;
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
  begin
    if Detail <> '' then
    begin
      Detail := Detail + ' · ' + AItem.UnitName;
    end
    else
    begin
      Detail := AItem.UnitName;
    end;
  end;
  if Detail <> '' then
  begin
    Result.AddPair('detail', Detail);
  end;
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
  begin
    Exit;
  end;
  Item := TJSONObject(AValue);
  AItem.FileName := TDocumentUris.ToPath(Uri);
  AItem.Range := TLspPositions.ReadRange(RangeValue);
  AItem.SelectionRange := TLspPositions.ReadRange(SelectionValue);
  if not Item.TryGetValue<string>('data.container', AItem.Container) then
  begin
    AItem.Container := '';
  end;
  if Item.TryGetValue<Integer>('data.symbolKind', Kind) and (Kind >= Ord(Low(TIndexSymbolKind))) and
    (Kind <= Ord(High(TIndexSymbolKind))) then
  begin
    AItem.SymbolKind := TIndexSymbolKind(Kind);
  end
  else
  begin
    AItem.SymbolKind := TIndexSymbolKind.Routine;
  end;
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
    begin
      Ranges.AddElement(TLspPositions.RangeToJson(Range));
    end;
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
  begin
    Result.AddElement(TLspHierarchies.ItemToJson(Item));
  end;
end;

function ReadItem(const AParams: TJSONValue): THierarchyItem;
var
  Value: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<TJSONValue>('item', Value) and
    TLspHierarchies.ItemFromJson(Value, Result)) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams, 'Feld "item" fehlt oder ist unvollständig');
  end;
end;

function NewResolver(const AIndex: ISymbolIndex; const AEnsureUnit: TEnsureUnitFunc;
  const ANamespaces: TArray<string>): TNameResolver;
begin
  Result := TNameResolver.Create(AIndex, AEnsureUnit);
  Result.Namespaces := ANamespaces;
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
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen');
  end;
  if not FStore.TryGet(Uri, Document) then
  begin
    Exit(TJSONNull.Create);
  end;
  Cancellation := TRequestCancellation.Create(ACancellation);
  Shared := TSyntaxTreeCache.Get(Document, Cancellation);
  Tree := Shared.Tree;
  ACancellation.ThrowIfCancellationRequested;
  Resolver := NewResolver(FIndex, FEnsureUnit, Namespaces);
  try
    if ACall then
    begin
      Found := CallItemAt(Resolver, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), Item);
    end
    else
    begin
      Found := TypeItemAt(Resolver, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue), Item);
    end;
  finally
    Resolver.Free;
  end;
  if not Found then
  begin
    Exit(TJSONNull.Create);
  end;
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
  Resolver := NewResolver(FIndex, FEnsureUnit, Namespaces);
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
  begin
    Files := FFiles();
  end
  else
  begin
    Files := nil;
  end;
  Item := ReadItem(AParams);
  if Assigned(FSettingsFor) then
  begin
    Settings := FSettingsFor(TDocumentUris.FromPath(Item.FileName));
  end
  else
  begin
    Settings := TReferenceSettings.Default;
  end;
  Resolver := NewResolver(FIndex, FEnsureUnit, Namespaces);
  try
    Result := CallsToJson(IncomingCalls(THierarchyCallSource.Create(Resolver, FIndex, FReadText, ACancellation), Item,
      Files, Settings), 'from');
  finally
    Resolver.Free;
  end;
end;

function TLspHierarchies.HandleOutgoing(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Resolver: TNameResolver;
begin
  Resolver := NewResolver(FIndex, FEnsureUnit, Namespaces);
  try
    Result := CallsToJson(OutgoingCalls(Resolver, FIndex, ReadItem(AParams), FReadText, ACancellation), 'to');
  finally
    Resolver.Free;
  end;
end;

end.
