unit Atlas.Common.Lsp.DataFlow;

// Datenfluss (#690, atlas/dataFlow): „Woher kommt der Wert?“ und „Wohin geht der Wert?“ für das Symbol an
// einer Position (Variable, Feld, Parameter, Property, Funktion; Result steht für die umgebende Funktion).
//
// Die Referenzsuche liefert alle Vorkommen; jedes wird am Syntaxbaum eingeordnet:
//   - Woher (Sources): Zuweisungen (:=), var- und out-Argumente, Read/ReadLn (externe Eingabe),
//     Initialisierungen (var X := …, X: T = …), Schleifenvariablen, Schreiben über eine Property (write FFeld
//     bzw. Setter), Inc/Dec und Verwandte. Ein Parameter führt zu den Argumenten aller Aufrufer (auch über
//     eine Property mit diesem Setter), eine Funktion zu den Zuweisungen an Result bzw. ihren Namen und zu
//     Exit(Wert), eine Property zusätzlich zum gelesenen Feld bzw. Getter.
//   - Wohin (Targets): Zuweisungen, Argumente (an den Parameter des Aufgerufenen), Rückgaben (Result, Exit),
//     Initialisierungen, Schleifen und Properties, die das Feld lesen; sonst eine Verwendung (Bedingung,
//     Index, verworfenes Ergebnis) als Blatt. Über Routinen außerhalb des Projekts und Typumwandlungen
//     (IntToStr(X), Integer(X)) geht der Wert weiter nach außen.
// Jede Stelle nennt die Symbole, aus denen ihr Wert kommt bzw. in die er geht. Der Editor fragt sie beim
// Aufklappen einzeln nach und schickt die Schlüssel der Vorfahren mit (Path); ein Symbol, das dort schon
// steht, ist ein Zyklus. Blätter: Literale, Konstanten, externe Eingaben und Ausgaben, Stellen außerhalb
// des Projekts. Unsichere Kanten (Zeiger, absolute, Move, FillChar, Adressen) sind markiert. Gleiche Stellen
// (Art, Ausdruck, Quellen) werden zu einem Knoten mit mehreren Fundorten zusammengefasst.

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
  Atlas.Common.Lsp.References;

type
  TDataFlowDirection = (Sources, Targets);

  /// <summary>Art einer Stelle im Datenfluss.</summary>
  TDataFlowKind = (Assignment, VarArgument, OutArgument, Input, Initializer, Loop, CallerArgument, Return,
    PropertyWrite, PropertyRead, Modify, Argument, Output, Use, Constant, Outside, Address);

  /// <summary>Warum sich eine Quelle bzw. ein Ziel nicht weiter aufklappen lässt.</summary>
  TDataFlowLeaf = (None, Constant, Outside, Cycle);

  TDataFlowSymbol = record
    Name: string;
    FileName: string;
    /// <summary>Name der Deklaration.</summary>
    Position: TTextPosition;
    SymbolKind: TIndexSymbolKind;
    Leaf: TDataFlowLeaf;
    /// <summary>"DATEI|Zeile:Zeichen" der Deklaration; gleich für alle Wege zum selben Symbol.</summary>
    function Key: string;
  end;

  TDataFlowPlace = record
    FileName: string;
    Position: TTextPosition;
    /// <summary>Zeile ohne Einrückung.</summary>
    LineText: string;
  end;

  TDataFlowNode = record
    Kind: TDataFlowKind;
    /// <summary>Fundorte; mehrere, wenn gleiche Stellen zusammengefasst sind.</summary>
    Places: TArray<TDataFlowPlace>;
    /// <summary>Wert- bzw. Zielausdruck, einzeilig ("A + B", "Kunde.Name").</summary>
    Detail: string;
    /// <summary>Weg des Werts: Aufgerufener, Property oder Setter ("Summe", "Property Name").</summary>
    Via: string;
    /// <summary>Der Wert enthält Literale; ohne Quellen ist die Stelle ein Literal-Blatt.</summary>
    Literal: Boolean;
    Unsafe: Boolean;
    /// <summary>Zeiger, absolute, Move, FillChar oder Adresse.</summary>
    UnsafeReason: string;
    Sources: TArray<TDataFlowSymbol>;
  end;

  TDataFlowOptions = record
    /// <summary>Stellen in Test-Units auslassen.</summary>
    ExcludeTests: Boolean;
    /// <summary>Nur Stellen in Projektdateien; Quellen außerhalb bleiben als Blätter.</summary>
    OnlyProject: Boolean;
    /// <summary>Schlüssel der Vorfahren im Baum des Editors (für Zyklen).</summary>
    Path: TArray<string>;
  end;

  TDataFlowResult = record
    Found: Boolean;
    Symbol: TDataFlowSymbol;
    Nodes: TArray<TDataFlowNode>;
  end;

  TLspDataFlow = class
  public const
    Method = 'atlas/dataFlow';
    /// <summary>Höchstzahl der Knoten einer Antwort.</summary>
    MaxNodes = 500;
  private
    FStore: IDocumentStore;
    FIndex: ISymbolIndex;
    FEnsureUnit: TEnsureUnitFunc;
    FReadText: TReferenceReadText;
    FFiles: TReferenceFilesProvider;
    FNamespaces: TArray<string>;
    function HandleDataFlow(const AParams: TJSONValue; const ACancellation: IJsonRpcCancellationToken): TJSONValue;
  private
    /// <summary>Unter TLspNamespaces gelesen und ersetzt wie bei den übrigen Anfragen (Code-Review A-03).</summary>
    function GetNamespaces: TArray<string>;
    procedure SetNamespaces(const AValue: TArray<string>);
  public
    constructor Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex; const AReadText: TReferenceReadText;
      const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
    procedure Attach(ADispatcher: TJsonRpcDispatcher);
    /// <summary>Datenfluss des Symbols an APosition in ATree. AFiles: Projektdateien (leer = alles zählt zum
    /// Projekt); AReadText liest jede Datei, auch AFileName.</summary>
    class function Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const APosition: TTextPosition; ADirection: TDataFlowDirection;
      const AOptions: TDataFlowOptions; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
      const ACancellation: IJsonRpcCancellationToken): TDataFlowResult; static;
    /// <summary>Antwort von atlas/dataFlow. Der Aufrufer übernimmt das Objekt.</summary>
    class function ToJson(const AResult: TDataFlowResult): TJSONObject; static;
    /// <summary>Name der Art im Protokoll ("assignment", "callerArgument" …).</summary>
    class function KindName(AKind: TDataFlowKind): string; static;
    class function LeafName(ALeaf: TDataFlowLeaf): string; static;
    property Namespaces: TArray<string> read GetNamespaces write SetNamespaces;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Lsp.Definition,
  Atlas.Common.Lsp.Positions,
  Atlas.Common.Lsp.Internals.Namespaces,
  Atlas.Common.Lsp.Internals.Cancellation;

type
  TSyntaxKinds = set of TSyntaxKind;
  TIndexSymbolKinds = set of TIndexSymbolKind;

  /// <summary>Parameter einer Routine, Namen einzeln.</summary>
  TDataFlowParam = record
    Name: string;
    Modifier: TParameterModifier;
    FileName: string;
    Position: TTextPosition;
  end;

  /// <summary>Ein Lauf von TLspDataFlow.Analyze: hält die geparsten Fremddateien und sammelt die Knoten.</summary>
  TDataFlowRun = class
  private
    FResolver: TNameResolver;
    FIndex: ISymbolIndex;
    FReadText: TReferenceReadText;
    FFiles: TArray<string>;
    FOptions: TDataFlowOptions;
    FCancellation: IJsonRpcCancellationToken;
    FOwnTree: TSyntaxTree;
    FOwnFile: string;
    FProject: TDictionary<string, Boolean>;
    FTrees: TObjectDictionary<string, TSyntaxTree>;
    FTexts: TDictionary<string, string>;
    FLines: TDictionary<string, TArray<string>>;
    FTests: TDictionary<string, Boolean>;
    FNodes: TList<TDataFlowNode>;
    FGroups: TDictionary<string, Integer>;
    FCurrentKey: string;
    procedure CheckCancelled;
    function TreeOf(const AFileName: string): TSyntaxTree;
    function TextOf(const AFileName: string): string;
    function LineText(const AFileName: string; ALine: Integer): string;
    function ExprText(const AFileName: string; ANode: TSyntaxNode): string;
    function InProject(const AFileName: string): Boolean;
    function IsTestFile(const AFileName: string): Boolean;
    function Excluded(const AFileName: string): Boolean;
    function LeafOf(const ASymbol: TDataFlowSymbol): TDataFlowLeaf;
    function Place(const AFileName: string; const APosition: TTextPosition): TDataFlowPlace;
    function ResolveSymbol(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out ASymbol: TDataFlowSymbol): Boolean;
    function ResolvedAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      out AResolved: TResolvedSymbol): Boolean;
    function FunctionOf(ATree: TSyntaxTree; const AFileName: string; ARoutine: TSyntaxNode;
      out ASymbol: TDataFlowSymbol): Boolean;
    function EnclosingFunction(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
      out ASymbol: TDataFlowSymbol): Boolean;
    function ParamsOf(const AFileName: string; const APosition: TTextPosition): TArray<TDataFlowParam>;
    function Occurrences(const ASymbol: TDataFlowSymbol): TArray<TReferenceLocation>;
    procedure AddSource(var ANode: TDataFlowNode; const ASymbol: TDataFlowSymbol);
    procedure CollectValue(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
      var ANode: TDataFlowNode);
    procedure AddNode(const ANode: TDataFlowNode);
    function NewNode(AKind: TDataFlowKind; const AFileName: string; const APosition: TTextPosition): TDataFlowNode;
    procedure AddValueNode(AKind: TDataFlowKind; ATree: TSyntaxTree; const AFileName: string;
      const APosition: TTextPosition; AValue: TSyntaxNode; const AVia, AUnsafeReason: string);
    procedure AddTargetNode(AKind: TDataFlowKind; const AFileName: string; const APosition: TTextPosition;
      const ATarget: TDataFlowSymbol; const ADetail, AVia, AUnsafeReason: string);
    procedure AddLeafNode(AKind: TDataFlowKind; const AFileName: string; const APosition: TTextPosition;
      const ADetail, AVia, AUnsafeReason: string);
    function TargetRoot(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
      var AUnsafeReason: string; out ASymbol: TDataFlowSymbol): Boolean;
    function WrittenTarget(ANode: TSyntaxNode; out AStatement: TSyntaxNode; var AUnsafeReason: string): Boolean;
    function PropertyName(ATree: TSyntaxTree; AProperty: TSyntaxNode; out APosition: TTextPosition): Boolean;
    function AccessorBefore(ATree: TSyntaxTree; const APosition: TTextPosition): string;
    function Accessor(ATree: TSyntaxTree; AProperty: TSyntaxNode; const AKeyword: string;
      out APosition: TTextPosition): Boolean;
    procedure PropertyWrites(ATree: TSyntaxTree; const AFileName: string; AProperty: TSyntaxNode;
      AParamIndex: Integer);
    // Woher
    procedure SourcesOf(const ASymbol: TDataFlowSymbol);
    procedure ClassifyWrite(const ASymbol: TDataFlowSymbol; const ALocation: TReferenceLocation);
    procedure ArgumentWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree; const AFileName: string;
      ACall: TSyntaxNode; AArgument: Integer; const APosition: TTextPosition; const AUnsafeReason: string);
    procedure CallerArguments(const ASymbol: TDataFlowSymbol; ADeclaration: TSyntaxNode);
    procedure FunctionSources(const ASymbol: TDataFlowSymbol);
    procedure PropertyReads(const ASymbol: TDataFlowSymbol);
    // Wohin
    procedure TargetsOf(const ASymbol: TDataFlowSymbol);
    procedure FlowUp(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
      AStart: TSyntaxNode);
  public
    constructor Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
      const AFileName: string; const AOptions: TDataFlowOptions; const AFiles: TArray<string>;
      const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken);
    destructor Destroy; override;
    function Run(const APosition: TTextPosition; ADirection: TDataFlowDirection): TDataFlowResult;
  end;

const
  RoutineKinds: TIndexSymbolKinds = [TIndexSymbolKind.Method, TIndexSymbolKind.Constructor_,
    TIndexSymbolKind.Routine];
  TypeKinds: TIndexSymbolKinds = [TIndexSymbolKind.ClassType, TIndexSymbolKind.ObjectType,
    TIndexSymbolKind.RecordType, TIndexSymbolKind.InterfaceType, TIndexSymbolKind.HelperType,
    TIndexSymbolKind.EnumType, TIndexSymbolKind.TypeAlias];
  ConstantKinds: TIndexSymbolKinds = [TIndexSymbolKind.Constant, TIndexSymbolKind.EnumMember];
  // Knoten, die in Deklarationen einen Typ statt eines Werts beschreiben.
  TypeNodeKinds: TSyntaxKinds = [TSyntaxKind.TypeReference, TSyntaxKind.ArrayType, TSyntaxKind.SetType,
    TSyntaxKind.PointerType, TSyntaxKind.ProcedureType, TSyntaxKind.FileType, TSyntaxKind.SubrangeType,
    TSyntaxKind.ClassOfType, TSyntaxKind.RecordType, TSyntaxKind.EnumType, TSyntaxKind.GenericArgs];
  StatementKinds: TSyntaxKinds = [TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement,
    TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement];
  MaxDetail = 120;

function ComparePositions(const A, B: TTextPosition): Integer;
begin
  if A.Line <> B.Line then
    Result := A.Line - B.Line
  else
    Result := A.Character - B.Character;
end;

function NodeContains(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := (ComparePositions(ANode.StartPos, APosition) <= 0) and (ComparePositions(APosition, ANode.EndPos) < 0);
end;

/// <summary>Innerster Knoten, der APosition enthält. Überlappen sich Geschwister (ein Sichtbarkeitsabschnitt
/// reicht über die Mitglieder dahinter), gewinnt das später beginnende.</summary>
function NodeAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  Index: Integer;
  Inner: TSyntaxNode;
begin
  Result := ARoot;
  repeat
    Inner := nil;
    for Index := 0 to Result.ChildCount - 1 do
      if NodeContains(Result[Index], APosition) and ((Inner = nil) or
        (ComparePositions(Result[Index].StartPos, Inner.StartPos) > 0)) then
        Inner := Result[Index];
    if Inner <> nil then
      Result := Inner;
  until Inner = nil;
end;

function ChildIndex(AParent, AChild: TSyntaxNode): Integer;
var
  Index: Integer;
begin
  for Index := 0 to AParent.ChildCount - 1 do
    if AParent[Index] = AChild then
      Exit(Index);
  Result := -1;
end;

/// <summary>Token, das an APosition beginnt oder sie enthält; -1 sonst.</summary>
function TokenIndexAt(ATree: TSyntaxTree; const APosition: TTextPosition): Integer;
var
  First, Last, Middle: Integer;
begin
  First := 0;
  Last := Length(ATree.Tokens) - 1;
  while First <= Last do
  begin
    Middle := (First + Last) div 2;
    if ComparePositions(ATree.Tokens[Middle].EndPos, APosition) <= 0 then
      First := Middle + 1
    else if ComparePositions(ATree.Tokens[Middle].StartPos, APosition) > 0 then
      Last := Middle - 1
    else
      Exit(Middle);
  end;
  Result := -1;
end;

function CleanName(const AText: string): string;
begin
  if (AText <> '') and (AText[1] = '&') then
    Result := Copy(AText, 2, MaxInt)
  else
    Result := AText;
end;

/// <summary>Position des Namens eines Bezeichners bzw. des Mitglieds hinter dem letzten Punkt.</summary>
function NamePosition(ATree: TSyntaxTree; ANode: TSyntaxNode): TTextPosition;
var
  Index: Integer;
  Token: TPascalToken;
begin
  Result := ANode.StartPos;
  if ANode.Kind <> TSyntaxKind.MemberAccess then
    Exit;
  // Das Mitglied steht als letzter gleichnamiger Bezeichner im Knoten.
  for Index := 0 to High(ATree.Tokens) do
  begin
    Token := ATree.Tokens[Index];
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Offset >= ANode.StartOffset) and (Token.Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(Token.Text), CleanName(ANode.Name)) then
      Result := Token.StartPos;
  end;
end;

/// <summary>Erster Bezeichner AName im Bereich des Knotens.</summary>
function NameInNode(ATree: TSyntaxTree; ANode: TSyntaxNode; const AName: string; out APosition: TTextPosition): Boolean;
var
  Index: Integer;
  Token: TPascalToken;
begin
  for Index := 0 to High(ATree.Tokens) do
  begin
    Token := ATree.Tokens[Index];
    if Token.Offset >= ANode.EndOffset then
      Break;
    if (Token.Offset >= ANode.StartOffset) and (Token.Kind = TPascalTokenKind.Identifier) and
      SameText(CleanName(Token.Text), AName) then
    begin
      APosition := Token.StartPos;
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Name der Routine bzw. des Aufgerufenen ohne Typ-Präfix.</summary>
function ShortName(const AName: string): string;
begin
  Result := Copy(AName, LastDelimiter('.', AName) + 1, MaxInt);
end;

function CalleeName(ACall: TSyntaxNode): string;
begin
  Result := '';
  if ACall.ChildCount > 0 then
    Result := LowerCase(CleanName(ShortName(ACall[0].Name)));
end;

function SingleLine(const AText: string): string;
var
  Index: Integer;
  Space: Boolean;
begin
  Result := '';
  Space := False;
  for Index := 1 to Length(AText) do
    if CharInSet(AText[Index], [#9, #10, #13, ' ']) then
      Space := Result <> ''
    else
    begin
      if Space then
        Result := Result + ' ';
      Space := False;
      Result := Result + AText[Index];
    end;
  if Length(Result) > MaxDetail then
    Result := Copy(Result, 1, MaxDetail - 1) + '…';
end;

function SymbolFromResolved(const AResolved: TResolvedSymbol): TDataFlowSymbol;
begin
  Result := Default(TDataFlowSymbol);
  Result.Name := AResolved.Name;
  Result.FileName := AResolved.FileName;
  Result.Position := AResolved.SelectionRange.StartPos;
  Result.SymbolKind := AResolved.SymbolKind;
end;

{ TDataFlowSymbol }

function TDataFlowSymbol.Key: string;
begin
  Result := UpperCase(FileName) + '|' + IntToStr(Position.Line) + ':' + IntToStr(Position.Character);
end;

{ TDataFlowRun }

constructor TDataFlowRun.Create(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const AOptions: TDataFlowOptions; const AFiles: TArray<string>;
  const AReadText: TReferenceReadText; const ACancellation: IJsonRpcCancellationToken);
var
  FileName: string;
begin
  inherited Create;
  FResolver := AResolver;
  FIndex := AIndex;
  FOwnTree := ATree;
  FOwnFile := AFileName;
  FOptions := AOptions;
  FFiles := AFiles;
  FReadText := AReadText;
  FCancellation := ACancellation;
  FProject := TDictionary<string, Boolean>.Create;
  for FileName in AFiles do
    FProject.AddOrSetValue(AnsiUpperCase(FileName), True);
  FProject.AddOrSetValue(AnsiUpperCase(AFileName), True);
  FTrees := TObjectDictionary<string, TSyntaxTree>.Create([doOwnsValues]);
  FTexts := TDictionary<string, string>.Create;
  FLines := TDictionary<string, TArray<string>>.Create;
  FTests := TDictionary<string, Boolean>.Create;
  FNodes := TList<TDataFlowNode>.Create;
  FGroups := TDictionary<string, Integer>.Create;
end;

destructor TDataFlowRun.Destroy;
begin
  FGroups.Free;
  FNodes.Free;
  FTests.Free;
  FLines.Free;
  FTexts.Free;
  FTrees.Free;
  FProject.Free;
  inherited;
end;

procedure TDataFlowRun.CheckCancelled;
begin
  if FCancellation <> nil then
    FCancellation.ThrowIfCancellationRequested;
end;

function TDataFlowRun.TextOf(const AFileName: string): string;
begin
  if FTexts.TryGetValue(AnsiUpperCase(AFileName), Result) then
    Exit;
  if not (Assigned(FReadText) and FReadText(AFileName, Result)) then
    Result := '';
  FTexts.Add(AnsiUpperCase(AFileName), Result);
end;

function TDataFlowRun.TreeOf(const AFileName: string): TSyntaxTree;
var
  Text: string;
begin
  if SameText(AFileName, FOwnFile) then
    Exit(FOwnTree);
  if FTrees.TryGetValue(AnsiUpperCase(AFileName), Result) then
    Exit;
  Result := nil;
  if AFileName = '' then
    Exit;
  Text := TextOf(AFileName);
  if Text = '' then
    Exit;
  Result := TSyntaxTreeCache.Parse(Text);
  FTrees.Add(AnsiUpperCase(AFileName), Result);
end;

function TDataFlowRun.LineText(const AFileName: string; ALine: Integer): string;
var
  Lines: TArray<string>;
begin
  if not FLines.TryGetValue(AnsiUpperCase(AFileName), Lines) then
  begin
    Lines := TTextLines.SplitLines(TextOf(AFileName));
    FLines.Add(AnsiUpperCase(AFileName), Lines);
  end;
  Result := '';
  if (ALine >= 0) and (ALine < Length(Lines)) then
    Result := Trim(Lines[ALine]);
end;

function TDataFlowRun.ExprText(const AFileName: string; ANode: TSyntaxNode): string;
begin
  Result := '';
  if ANode <> nil then
    Result := SingleLine(Copy(TextOf(AFileName), ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
end;

function TDataFlowRun.InProject(const AFileName: string): Boolean;
begin
  // Ohne Projekt zählt jede lesbare Datei dazu.
  Result := FProject.ContainsKey(AnsiUpperCase(AFileName)) or ((Length(FFiles) = 0) and (TextOf(AFileName) <> ''));
end;

function TDataFlowRun.IsTestFile(const AFileName: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  if FTests.TryGetValue(AnsiUpperCase(AFileName), Result) then
    Exit;
  Tree := TreeOf(AFileName);
  Result := (Tree <> nil) and TUsesClauses.IsTestUnit(Tree.Tokens);
  FTests.Add(AnsiUpperCase(AFileName), Result);
end;

function TDataFlowRun.Excluded(const AFileName: string): Boolean;
begin
  Result := (FOptions.ExcludeTests and IsTestFile(AFileName)) or (FOptions.OnlyProject and not InProject(AFileName));
end;

function TDataFlowRun.LeafOf(const ASymbol: TDataFlowSymbol): TDataFlowLeaf;
var
  Key, Ancestor: string;
begin
  Result := TDataFlowLeaf.None;
  if ASymbol.SymbolKind in ConstantKinds then
    Exit(TDataFlowLeaf.Constant);
  if not InProject(ASymbol.FileName) then
    Exit(TDataFlowLeaf.Outside);
  Key := ASymbol.Key;
  if Key = FCurrentKey then
    Exit(TDataFlowLeaf.Cycle);
  for Ancestor in FOptions.Path do
    if SameText(Ancestor, Key) then
      Exit(TDataFlowLeaf.Cycle);
end;

function TDataFlowRun.Place(const AFileName: string; const APosition: TTextPosition): TDataFlowPlace;
begin
  Result.FileName := AFileName;
  Result.Position := APosition;
  Result.LineText := LineText(AFileName, APosition.Line);
end;

function TDataFlowRun.ResolvedAt(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out AResolved: TResolvedSymbol): Boolean;
begin
  AResolved := FResolver.Resolve(ATree, AFileName, APosition);
  Result := (AResolved.Kind in [TResolvedKind.Symbol, TResolvedKind.Local]) and (AResolved.FileName <> '');
end;

function TDataFlowRun.FunctionOf(ATree: TSyntaxTree; const AFileName: string; ARoutine: TSyntaxNode;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  Header: TSyntaxNode;
  Name: string;
  Index: Integer;
  Token: TPascalToken;
  Found: Boolean;
  Position: TTextPosition;
  Resolved: TResolvedSymbol;
begin
  Result := False;
  Header := ARoutine;
  if ARoutine.Kind = TSyntaxKind.RoutineDecl then
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  if Header = nil then
    Exit;
  Name := ShortName(Header.Name);
  Position := Header.StartPos;
  // Bei TFoo.Bar das letzte Vorkommen vor der Parameterliste.
  Found := False;
  for Index := 0 to High(ATree.Tokens) do
  begin
    Token := ATree.Tokens[Index];
    if Token.Offset >= Header.EndOffset then
      Break;
    if Token.Offset < Header.StartOffset then
      Continue;
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(CleanName(Token.Text), Name) then
    begin
      Position := Token.StartPos;
      Found := True;
    end;
    if Token.IsSymbol('(') or Token.IsSymbol(';') or Token.IsSymbol(':') then
      Break;
  end;
  if not Found then
    Exit;
  if ResolvedAt(ATree, AFileName, Position, Resolved) and (Resolved.SymbolKind in RoutineKinds) then
    ASymbol := SymbolFromResolved(Resolved)
  else
  begin
    ASymbol := Default(TDataFlowSymbol);
    ASymbol.Name := Name;
    ASymbol.FileName := AFileName;
    ASymbol.Position := Position;
    ASymbol.SymbolKind := TIndexSymbolKind.Routine;
  end;
  Result := True;
end;

function TDataFlowRun.EnclosingFunction(ATree: TSyntaxTree; const AFileName: string; ANode: TSyntaxNode;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  Current: TSyntaxNode;
begin
  Current := ANode;
  while (Current <> nil) and not ((Current.Kind = TSyntaxKind.RoutineDecl) and
    (Current.FindChild(TSyntaxKind.Block) <> nil)) do
  begin
    // Result in einer anonymen Methode gehört zu ihr, nicht zur Routine außen.
    if Current.Kind = TSyntaxKind.AnonymousMethod then
      Exit(False);
    Current := Current.Parent;
  end;
  Result := (Current <> nil) and FunctionOf(ATree, AFileName, Current, ASymbol);
end;

function TDataFlowRun.ResolveSymbol(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  out ASymbol: TDataFlowSymbol): Boolean;
var
  Index: Integer;
  Resolved: TResolvedSymbol;
  Targets: TArray<TDefinitionTarget>;
begin
  ASymbol := Default(TDataFlowSymbol);
  Index := TokenIndexAt(ATree, APosition);
  // Result steht für die Funktion, in der es vorkommt.
  if (Index >= 0) and (ATree.Tokens[Index].Kind = TPascalTokenKind.Identifier) and
    SameText(ATree.Tokens[Index].Text, 'Result') then
    Exit(EnclosingFunction(ATree, AFileName, NodeAt(ATree.Root, APosition), ASymbol));
  if ResolvedAt(ATree, AFileName, APosition, Resolved) then
  begin
    ASymbol := SymbolFromResolved(Resolved);
    Exit(True);
  end;
  Targets := TLspDefinition.Targets(FResolver, FIndex, ATree, AFileName, APosition, True);
  Result := Length(Targets) > 0;
  if not Result then
    Exit;
  ASymbol.FileName := Targets[0].FileName;
  ASymbol.Position := Targets[0].SelectionRange.StartPos;
  ASymbol.SymbolKind := TIndexSymbolKind.Variable;
  if Index >= 0 then
    ASymbol.Name := CleanName(ATree.Tokens[Index].Text);
end;

function TDataFlowRun.ParamsOf(const AFileName: string; const APosition: TTextPosition): TArray<TDataFlowParam>;
var
  Tree: TSyntaxTree;
  Node, Parameters, Parameter: TSyntaxNode;
  Index: Integer;
  Name: string;
  Param: TDataFlowParam;
begin
  Result := nil;
  Tree := TreeOf(AFileName);
  if Tree = nil then
    Exit;
  Node := NodeAt(Tree.Root, APosition);
  if Node.Kind = TSyntaxKind.RoutineDecl then
    Node := Node.FindChild(TSyntaxKind.RoutineHeader);
  while (Node <> nil) and (Node.Kind <> TSyntaxKind.RoutineHeader) do
    Node := Node.Parent;
  if Node = nil then
    Exit;
  Parameters := Node.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Parameter := Parameters[Index];
    if Parameter.Kind <> TSyntaxKind.Parameter then
      Continue;
    for Name in Parameter.Name.Split([',']) do
    begin
      Param := Default(TDataFlowParam);
      Param.Name := Trim(Name);
      Param.Modifier := Parameter.Modifier;
      Param.FileName := AFileName;
      if not NameInNode(Tree, Parameter, CleanName(Param.Name), Param.Position) then
        Param.Position := Parameter.StartPos;
      Result := Result + [Param];
    end;
  end;
end;

function TDataFlowRun.Occurrences(const ASymbol: TDataFlowSymbol): TArray<TReferenceLocation>;
var
  Tree: TSyntaxTree;
begin
  Result := nil;
  Tree := TreeOf(ASymbol.FileName);
  if Tree = nil then
    Exit;
  Result := TLspReferences.Find(FResolver, FIndex, Tree, ASymbol.FileName, ASymbol.Position, True, FFiles, FReadText,
    FCancellation);
end;

procedure TDataFlowRun.AddSource(var ANode: TDataFlowNode; const ASymbol: TDataFlowSymbol);
var
  Existing: TDataFlowSymbol;
  Symbol: TDataFlowSymbol;
begin
  for Existing in ANode.Sources do
    if Existing.Key = ASymbol.Key then
      Exit;
  Symbol := ASymbol;
  Symbol.Leaf := LeafOf(Symbol);
  ANode.Sources := ANode.Sources + [Symbol];
end;

procedure TDataFlowRun.CollectValue(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
  var ANode: TDataFlowNode);
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index: Integer;
  Symbol: TDataFlowSymbol;
  Resolved: TResolvedSymbol;
  Name: string;
  Outer: Boolean;
begin
  if AExpr = nil then
    Exit;
  // Eigener Stapel statt Rekursion (Bericht M1).
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(AExpr);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      case Node.Kind of
        TSyntaxKind.Literal:
          ANode.Literal := True;
        TSyntaxKind.Identifier:
          begin
            Name := LowerCase(Node.Name);
            if (Name = 'nil') or (Name = 'true') or (Name = 'false') then
              ANode.Literal := True
            else if ResolveSymbol(ATree, AFileName, Node.StartPos, Symbol) and not (Symbol.SymbolKind in TypeKinds) then
              AddSource(ANode, Symbol);
          end;
        TSyntaxKind.MemberAccess:
          if ResolveSymbol(ATree, AFileName, NamePosition(ATree, Node), Symbol) and
            not (Symbol.SymbolKind in TypeKinds) then
            AddSource(ANode, Symbol);
        TSyntaxKind.Call:
          begin
            // Routinen des Projekts liefern ihr Ergebnis; Typumwandlungen und Routinen von außen reichen
            // die Argumente durch.
            Outer := True;
            if (Node.ChildCount > 0) and ResolvedAt(ATree, AFileName, NamePosition(ATree, Node[0]), Resolved) and
              not (Resolved.SymbolKind in TypeKinds) then
            begin
              if InProject(Resolved.FileName) then
              begin
                AddSource(ANode, SymbolFromResolved(Resolved));
                Outer := False;
              end
              else if ANode.Via = '' then
                ANode.Via := ShortName(Node.Name);
            end;
            if Outer then
              for Index := Node.ChildCount - 1 downto 1 do
                Pending.Push(Node[Index]);
          end;
        TSyntaxKind.IndexAccess:
          if Node.ChildCount > 0 then
            Pending.Push(Node[0]);
        TSyntaxKind.Dereference:
          begin
            ANode.Unsafe := True;
            if ANode.UnsafeReason = '' then
              ANode.UnsafeReason := 'pointer';
            if Node.ChildCount > 0 then
              Pending.Push(Node[0]);
          end;
        TSyntaxKind.AddressOf:
          begin
            ANode.Unsafe := True;
            if ANode.UnsafeReason = '' then
              ANode.UnsafeReason := 'address';
          end;
        TSyntaxKind.IfExpr:
          for Index := Node.ChildCount - 1 downto 1 do
            Pending.Push(Node[Index]);
        TSyntaxKind.InheritedExpr, TSyntaxKind.AnonymousMethod, TSyntaxKind.GenericArgs:
          ;
      else
        for Index := Node.ChildCount - 1 downto 0 do
          Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

procedure TDataFlowRun.AddNode(const ANode: TDataFlowNode);
var
  Key: string;
  Source: TDataFlowSymbol;
  Slot: Integer;
  Existing: TDataFlowNode;
begin
  if Length(ANode.Places) = 0 then
    Exit;
  Key := IntToStr(Ord(ANode.Kind)) + '|' + ANode.Detail + '|' + ANode.Via + '|' + ANode.UnsafeReason;
  for Source in ANode.Sources do
    Key := Key + '|' + Source.Key;
  if FGroups.TryGetValue(Key, Slot) then
  begin
    Existing := FNodes[Slot];
    Existing.Places := Existing.Places + ANode.Places;
    FNodes[Slot] := Existing;
  end
  else if FNodes.Count < TLspDataFlow.MaxNodes then
    FGroups.Add(Key, FNodes.Add(ANode));
end;

function TDataFlowRun.NewNode(AKind: TDataFlowKind; const AFileName: string;
  const APosition: TTextPosition): TDataFlowNode;
begin
  Result := Default(TDataFlowNode);
  Result.Kind := AKind;
  Result.Places := [Place(AFileName, APosition)];
end;

procedure TDataFlowRun.AddValueNode(AKind: TDataFlowKind; ATree: TSyntaxTree; const AFileName: string;
  const APosition: TTextPosition; AValue: TSyntaxNode; const AVia, AUnsafeReason: string);
var
  Node: TDataFlowNode;
begin
  if Excluded(AFileName) then
    Exit;
  Node := NewNode(AKind, AFileName, APosition);
  Node.Detail := ExprText(AFileName, AValue);
  Node.Via := AVia;
  Node.Unsafe := AUnsafeReason <> '';
  Node.UnsafeReason := AUnsafeReason;
  CollectValue(ATree, AFileName, AValue, Node);
  AddNode(Node);
end;

procedure TDataFlowRun.AddTargetNode(AKind: TDataFlowKind; const AFileName: string; const APosition: TTextPosition;
  const ATarget: TDataFlowSymbol; const ADetail, AVia, AUnsafeReason: string);
var
  Node: TDataFlowNode;
begin
  if Excluded(AFileName) then
    Exit;
  Node := NewNode(AKind, AFileName, APosition);
  Node.Detail := ADetail;
  Node.Via := AVia;
  Node.Unsafe := AUnsafeReason <> '';
  Node.UnsafeReason := AUnsafeReason;
  AddSource(Node, ATarget);
  AddNode(Node);
end;

procedure TDataFlowRun.AddLeafNode(AKind: TDataFlowKind; const AFileName: string; const APosition: TTextPosition;
  const ADetail, AVia, AUnsafeReason: string);
var
  Node: TDataFlowNode;
begin
  if Excluded(AFileName) then
    Exit;
  Node := NewNode(AKind, AFileName, APosition);
  Node.Detail := ADetail;
  Node.Via := AVia;
  Node.Unsafe := AUnsafeReason <> '';
  Node.UnsafeReason := AUnsafeReason;
  AddNode(Node);
end;

function TDataFlowRun.TargetRoot(ATree: TSyntaxTree; const AFileName: string; AExpr: TSyntaxNode;
  var AUnsafeReason: string; out ASymbol: TDataFlowSymbol): Boolean;
var
  Current: TSyntaxNode;
begin
  Result := False;
  Current := AExpr;
  // Liste[I] := … schreibt in Liste, P^ := … über einen Zeiger.
  while (Current <> nil) and (Current.Kind in [TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (Current.ChildCount > 0) do
  begin
    if (Current.Kind = TSyntaxKind.Dereference) and (AUnsafeReason = '') then
      AUnsafeReason := 'pointer';
    Current := Current[0];
  end;
  if (Current <> nil) and (Current.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
    Result := ResolveSymbol(ATree, AFileName, NamePosition(ATree, Current), ASymbol);
end;

function TDataFlowRun.WrittenTarget(ANode: TSyntaxNode; out AStatement: TSyntaxNode;
  var AUnsafeReason: string): Boolean;
var
  Current: TSyntaxNode;
begin
  Current := ANode;
  while (Current.Parent <> nil) and (Current.Parent.Kind in [TSyntaxKind.IndexAccess, TSyntaxKind.Dereference]) and
    (Current.Parent[0] = Current) do
  begin
    if Current.Parent.Kind = TSyntaxKind.Dereference then
      AUnsafeReason := 'pointer';
    Current := Current.Parent;
  end;
  AStatement := Current.Parent;
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.AssignStatement) and
    (AStatement.ChildCount >= 2) and (AStatement[0] = Current);
end;

function TDataFlowRun.PropertyName(ATree: TSyntaxTree; AProperty: TSyntaxNode; out APosition: TTextPosition): Boolean;
begin
  Result := NameInNode(ATree, AProperty, CleanName(AProperty.Name), APosition);
end;

function TDataFlowRun.AccessorBefore(ATree: TSyntaxTree; const APosition: TTextPosition): string;
var
  Index: Integer;
begin
  Result := '';
  Index := TokenIndexAt(ATree, APosition) - 1;
  while (Index >= 0) and (ATree.Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) do
    Dec(Index);
  if Index >= 0 then
    Result := LowerCase(ATree.Tokens[Index].Text);
end;

function TDataFlowRun.Accessor(ATree: TSyntaxTree; AProperty: TSyntaxNode; const AKeyword: string;
  out APosition: TTextPosition): Boolean;
var
  Index: Integer;
  Token: TPascalToken;
  Armed: Boolean;
begin
  Armed := False;
  for Index := 0 to High(ATree.Tokens) do
  begin
    Token := ATree.Tokens[Index];
    if Token.Offset >= AProperty.EndOffset then
      Break;
    if (Token.Offset < AProperty.StartOffset) or (Token.Kind in [TPascalTokenKind.Comment,
      TPascalTokenKind.Directive]) then
      Continue;
    if Armed and (Token.Kind = TPascalTokenKind.Identifier) then
    begin
      APosition := Token.StartPos;
      Exit(True);
    end;
    Armed := SameText(Token.Text, AKeyword) and (Token.Kind in [TPascalTokenKind.Keyword,
      TPascalTokenKind.Identifier]);
  end;
  Result := False;
end;

procedure TDataFlowRun.PropertyWrites(ATree: TSyntaxTree; const AFileName: string; AProperty: TSyntaxNode;
  AParamIndex: Integer);
var
  Position: TTextPosition;
  Prop: TDataFlowSymbol;
  Location: TReferenceLocation;
  Tree: TSyntaxTree;
  Node, Statement: TSyntaxNode;
  Reason: string;
begin
  // Indizierte Properties: Der Wert ist der letzte Parameter des Setters, davor stehen die Indizes.
  if AParamIndex < 0 then
    Exit;
  if not PropertyName(ATree, AProperty, Position) then
    Exit;
  if not ResolveSymbol(ATree, AFileName, Position, Prop) then
  begin
    Prop := Default(TDataFlowSymbol);
    Prop.Name := CleanName(AProperty.Name);
    Prop.FileName := AFileName;
    Prop.Position := Position;
    Prop.SymbolKind := TIndexSymbolKind.Property_;
  end;
  for Location in Occurrences(Prop) do
  begin
    CheckCancelled;
    Tree := TreeOf(Location.FileName);
    if Tree = nil then
      Continue;
    Node := NodeAt(Tree.Root, Location.Range.StartPos);
    if not (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      Continue;
    Reason := '';
    if WrittenTarget(Node, Statement, Reason) then
      AddValueNode(TDataFlowKind.PropertyWrite, Tree, Location.FileName, Location.Range.StartPos, Statement[1],
        Prop.Name, Reason);
  end;
end;

{ TDataFlowRun: Woher }

procedure TDataFlowRun.SourcesOf(const ASymbol: TDataFlowSymbol);
var
  Tree: TSyntaxTree;
  Declaration: TSyntaxNode;
  Location: TReferenceLocation;
  Value: TSyntaxNode;
  Node: TDataFlowNode;
begin
  Tree := TreeOf(ASymbol.FileName);
  if ASymbol.SymbolKind in ConstantKinds then
  begin
    // Konstante: ein Blatt mit ihrem Wert.
    Node := NewNode(TDataFlowKind.Constant, ASymbol.FileName, ASymbol.Position);
    Node.Detail := ASymbol.Name;
    Node.Literal := True;
    if Tree <> nil then
    begin
      Declaration := NodeAt(Tree.Root, ASymbol.Position);
      if (Declaration.Kind = TSyntaxKind.ConstDecl) and (Declaration.ChildCount > 0) then
      begin
        Value := Declaration[Declaration.ChildCount - 1];
        if not (Value.Kind in TypeNodeKinds) then
          Node.Detail := ExprText(ASymbol.FileName, Value);
      end;
    end;
    AddNode(Node);
    Exit;
  end;
  if not InProject(ASymbol.FileName) or (Tree = nil) then
  begin
    AddLeafNode(TDataFlowKind.Outside, ASymbol.FileName, ASymbol.Position, ASymbol.Name, '', '');
    Exit;
  end;
  if ASymbol.SymbolKind in RoutineKinds then
  begin
    FunctionSources(ASymbol);
    Exit;
  end;
  for Location in Occurrences(ASymbol) do
  begin
    CheckCancelled;
    if SameText(ExtractFileExt(Location.FileName), '.dfm') or SameText(ExtractFileExt(Location.FileName), '.fmx') then
      Continue;
    ClassifyWrite(ASymbol, Location);
  end;
  Declaration := NodeAt(Tree.Root, ASymbol.Position);
  if Declaration.Kind = TSyntaxKind.Parameter then
    CallerArguments(ASymbol, Declaration);
  if ASymbol.SymbolKind = TIndexSymbolKind.Property_ then
    PropertyReads(ASymbol);
end;

procedure TDataFlowRun.ClassifyWrite(const ASymbol: TDataFlowSymbol; const ALocation: TReferenceLocation);
var
  Tree: TSyntaxTree;
  Node, Statement, Value, Child: TSyntaxNode;
  Parent: TSyntaxNode;
  Reason, Via, Keyword: string;
  Index: Integer;
  Loop: TDataFlowNode;
  Position: TTextPosition;
  Setter: TResolvedSymbol;
  Alias: TDataFlowSymbol;
begin
  Tree := TreeOf(ALocation.FileName);
  if Tree = nil then
    Exit;
  Position := ALocation.Range.StartPos;
  Node := NodeAt(Tree.Root, Position);
  case Node.Kind of
    TSyntaxKind.VarDecl, TSyntaxKind.InlineVar:
      begin
        // Deklaration mit Wert: var X := …, X: T = …; X: T absolute Y ist eine unsichere Kante.
        if Node.ChildCount = 0 then
          Exit;
        Value := Node[Node.ChildCount - 1];
        if Value.Kind in TypeNodeKinds then
          Exit;
        Reason := '';
        if SameText(AccessorBefore(Tree, Value.StartPos), 'absolute') then
          Reason := 'absolute';
        AddValueNode(TDataFlowKind.Initializer, Tree, ALocation.FileName, Position, Value, '', Reason);
        Exit;
      end;
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      begin
        if not SameText(CleanName(Node.Name), CleanName(ASymbol.Name)) or Excluded(ALocation.FileName) then
          Exit;
        Loop := NewNode(TDataFlowKind.Loop, ALocation.FileName, Position);
        Loop.Detail := '';
        for Index := 0 to Node.ChildCount - 1 do
        begin
          Child := Node[Index];
          if (Child.Kind in StatementKinds) or (Child.Kind in TypeNodeKinds) then
            Continue;
          if Loop.Detail <> '' then
            Loop.Detail := Loop.Detail + ' .. ';
          Loop.Detail := Loop.Detail + ExprText(ALocation.FileName, Child);
          CollectValue(Tree, ALocation.FileName, Child, Loop);
        end;
        if Node.Kind = TSyntaxKind.ForInStatement then
          Loop.Via := 'in';
        AddNode(Loop);
        Exit;
      end;
    TSyntaxKind.PropertyDecl:
      begin
        // Feld hinter write: Jede Zuweisung an die Property schreibt hinein.
        if (ASymbol.SymbolKind = TIndexSymbolKind.Field) and SameText(AccessorBefore(Tree, Position), 'write') then
          PropertyWrites(Tree, ALocation.FileName, Node, 0);
        Exit;
      end;
    TSyntaxKind.Identifier, TSyntaxKind.MemberAccess:
      ;
  else
    Exit;
  end;
  Reason := '';
  if WrittenTarget(Node, Statement, Reason) then
  begin
    Via := '';
    // Zuweisung an eine Property mit Setter.
    if ASymbol.SymbolKind = TIndexSymbolKind.Property_ then
    begin
      Parent := NodeAt(TreeOf(ASymbol.FileName).Root, ASymbol.Position);
      if (Parent.Kind = TSyntaxKind.PropertyDecl) and Accessor(TreeOf(ASymbol.FileName), Parent, 'write', Position) and
        ResolvedAt(TreeOf(ASymbol.FileName), ASymbol.FileName, Position, Setter) and
        (Setter.SymbolKind in RoutineKinds) then
        Via := Setter.Name;
      Position := ALocation.Range.StartPos;
    end;
    AddValueNode(TDataFlowKind.Assignment, Tree, ALocation.FileName, Position, Statement[1], Via, Reason);
    Exit;
  end;
  Parent := Node.Parent;
  if Parent = nil then
    Exit;
  if (Parent.Kind = TSyntaxKind.VarDecl) and SameText(AccessorBefore(Tree, Position), 'absolute') then
  begin
    // X: T absolute Y: Jede Zuweisung an X ändert Y.
    if NameInNode(Tree, Parent, CleanName(Trim(Parent.Name.Split([','])[0])), Position) and
      ResolveSymbol(Tree, ALocation.FileName, Position, Alias) then
      AddTargetNode(TDataFlowKind.Assignment, ALocation.FileName, ALocation.Range.StartPos, Alias,
        ExprText(ALocation.FileName, Parent), 'absolute', 'absolute');
  end
  else if (Parent.Kind = TSyntaxKind.Call) and (Parent[0] <> Node) then
    ArgumentWrite(ASymbol, Tree, ALocation.FileName, Parent, ChildIndex(Parent, Node) - 1, Position, Reason)
  else if Parent.Kind = TSyntaxKind.AddressOf then
  begin
    // Über die Adresse kann der Wert sich überall ändern.
    Keyword := ExprText(ALocation.FileName, Parent);
    AddLeafNode(TDataFlowKind.Address, ALocation.FileName, Position, Keyword, '', 'address');
  end;
end;

procedure TDataFlowRun.ArgumentWrite(const ASymbol: TDataFlowSymbol; ATree: TSyntaxTree; const AFileName: string;
  ACall: TSyntaxNode; AArgument: Integer; const APosition: TTextPosition; const AUnsafeReason: string);
var
  Name: string;
  Node: TDataFlowNode;
  Resolved: TResolvedSymbol;
  Params: TArray<TDataFlowParam>;
  Param: TDataFlowSymbol;
  Argument: Integer;
begin
  Name := CalleeName(ACall);
  // Eingebaute Routinen, die ein Argument schreiben.
  if (Name = 'read') or (Name = 'readln') or ((Name = 'blockread') and (AArgument = 1)) then
  begin
    AddLeafNode(TDataFlowKind.Input, AFileName, APosition, ExprText(AFileName, ACall), ShortName(ACall.Name),
      AUnsafeReason);
    Exit;
  end;
  if ((Name = 'inc') or (Name = 'dec') or (Name = 'include') or (Name = 'exclude') or (Name = 'setlength') or
    (Name = 'delete')) and (AArgument = 0) or (Name = 'insert') and (AArgument = 1) then
  begin
    if Excluded(AFileName) then
      Exit;
    Node := NewNode(TDataFlowKind.Modify, AFileName, APosition);
    Node.Detail := ExprText(AFileName, ACall);
    Node.Via := ShortName(ACall.Name);
    AddSource(Node, ASymbol);
    for Argument := 1 to ACall.ChildCount - 1 do
      if Argument - 1 <> AArgument then
        CollectValue(ATree, AFileName, ACall[Argument], Node);
    AddNode(Node);
    Exit;
  end;
  if ((Name = 'str') or (Name = 'val')) and (AArgument = 1) and (ACall.ChildCount > 1) then
  begin
    AddValueNode(TDataFlowKind.Assignment, ATree, AFileName, APosition, ACall[1], ShortName(ACall.Name),
      AUnsafeReason);
    Exit;
  end;
  if (Name = 'move') and (AArgument = 1) and (ACall.ChildCount > 1) then
  begin
    AddValueNode(TDataFlowKind.Assignment, ATree, AFileName, APosition, ACall[1], ShortName(ACall.Name), 'move');
    Exit;
  end;
  if (Name = 'fillchar') and (AArgument = 0) then
  begin
    if ACall.ChildCount > 3 then
      AddValueNode(TDataFlowKind.Assignment, ATree, AFileName, APosition, ACall[3], ShortName(ACall.Name), 'fillchar')
    else
      AddLeafNode(TDataFlowKind.Assignment, AFileName, APosition, ExprText(AFileName, ACall), ShortName(ACall.Name),
        'fillchar');
    Exit;
  end;
  // Routine mit var- bzw. out-Parameter an dieser Stelle: Der Wert kommt aus ihrem Rumpf.
  if not ResolvedAt(ATree, AFileName, NamePosition(ATree, ACall[0]), Resolved) or
    not (Resolved.SymbolKind in RoutineKinds) then
    Exit;
  Params := ParamsOf(Resolved.FileName, Resolved.SelectionRange.StartPos);
  if (AArgument < 0) or (AArgument > High(Params)) or
    not (Params[AArgument].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) then
    Exit;
  Param := Default(TDataFlowSymbol);
  Param.Name := Params[AArgument].Name;
  Param.FileName := Params[AArgument].FileName;
  Param.Position := Params[AArgument].Position;
  Param.SymbolKind := TIndexSymbolKind.Variable;
  if Params[AArgument].Modifier = TParameterModifier.OutParam then
    AddTargetNode(TDataFlowKind.OutArgument, AFileName, APosition, Param, ExprText(AFileName, ACall), Resolved.Name,
      AUnsafeReason)
  else
    AddTargetNode(TDataFlowKind.VarArgument, AFileName, APosition, Param, ExprText(AFileName, ACall), Resolved.Name,
      AUnsafeReason);
end;

procedure TDataFlowRun.CallerArguments(const ASymbol: TDataFlowSymbol; ADeclaration: TSyntaxNode);
var
  Tree, CallTree: TSyntaxTree;
  Header, Node, Call: TSyntaxNode;
  Params: TArray<TDataFlowParam>;
  Index, ParamIndex: Integer;
  Routine: TDataFlowSymbol;
  Location: TReferenceLocation;
begin
  Tree := TreeOf(ASymbol.FileName);
  Header := ADeclaration;
  while (Header <> nil) and not (Header.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.AnonymousMethod,
    TSyntaxKind.ProcedureType]) do
    Header := Header.Parent;
  if (Header = nil) or (Header.Kind <> TSyntaxKind.RoutineHeader) then
    Exit;
  Params := ParamsOf(ASymbol.FileName, Header.StartPos);
  ParamIndex := -1;
  for Index := 0 to High(Params) do
    if Params[Index].Position = ASymbol.Position then
      ParamIndex := Index;
  // out-Parameter bekommen vom Aufrufer keinen Wert.
  if (ParamIndex < 0) or (Params[ParamIndex].Modifier = TParameterModifier.OutParam) then
    Exit;
  if not FunctionOf(Tree, ASymbol.FileName, Header, Routine) then
    Exit;
  for Location in Occurrences(Routine) do
  begin
    CheckCancelled;
    CallTree := TreeOf(Location.FileName);
    if CallTree = nil then
      Continue;
    Node := NodeAt(CallTree.Root, Location.Range.StartPos);
    if Node.Kind = TSyntaxKind.PropertyDecl then
    begin
      // Setter einer Property: Der Wert jeder Zuweisung an sie kommt als letzter Parameter an.
      if SameText(AccessorBefore(CallTree, Location.Range.StartPos), 'write') and (ParamIndex = High(Params)) then
        PropertyWrites(CallTree, Location.FileName, Node, ParamIndex);
      Continue;
    end;
    if not (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      Continue;
    Call := Node.Parent;
    if (Call = nil) or (Call.Kind <> TSyntaxKind.Call) or (Call[0] <> Node) or (ParamIndex + 1 >= Call.ChildCount) then
      Continue;
    AddValueNode(TDataFlowKind.CallerArgument, CallTree, Location.FileName, Call[ParamIndex + 1].StartPos,
      Call[ParamIndex + 1], Routine.Name, '');
  end;
end;

procedure TDataFlowRun.FunctionSources(const ASymbol: TDataFlowSymbol);
var
  Tree, BodyTree: TSyntaxTree;
  Targets: TArray<TDefinitionTarget>;
  Body, Block: TSyntaxNode;
  Name, BodyFile: string;
  Returns: TList<TSyntaxNode>;
  Statement: TSyntaxNode;
begin
  Tree := TreeOf(ASymbol.FileName);
  Targets := TLspDefinition.Targets(FResolver, FIndex, Tree, ASymbol.FileName, ASymbol.Position, False);
  BodyFile := ASymbol.FileName;
  BodyTree := Tree;
  Body := nil;
  if Length(Targets) > 0 then
  begin
    BodyFile := Targets[0].FileName;
    BodyTree := TreeOf(BodyFile);
  end;
  if (BodyTree <> nil) and InProject(BodyFile) then
  begin
    if Length(Targets) > 0 then
      Body := NodeAt(BodyTree.Root, Targets[0].SelectionRange.StartPos)
    else
      Body := NodeAt(BodyTree.Root, ASymbol.Position);
    while (Body <> nil) and not ((Body.Kind = TSyntaxKind.RoutineDecl) and
      (Body.FindChild(TSyntaxKind.Block) <> nil)) do
      Body := Body.Parent;
  end;
  if Body = nil then
  begin
    // Ohne Rumpf im Projekt (Bibliothek, abstract, external): ein Blatt.
    AddLeafNode(TDataFlowKind.Outside, ASymbol.FileName, ASymbol.Position, ASymbol.Name, '', '');
    Exit;
  end;
  Name := ShortName(ASymbol.Name);
  Block := Body.FindChild(TSyntaxKind.Block);
  Returns := TList<TSyntaxNode>.Create;
  try
    // Zuweisungen an Result bzw. den Namen und Exit(Wert), ohne verschachtelte Routinen und anonyme Methoden.
    Block.Walk(
      function(ANode: TSyntaxNode): Boolean
      begin
        Result := not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]);
        if (ANode.Kind = TSyntaxKind.AssignStatement) and (ANode.ChildCount >= 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and (SameText(ANode[0].Name, 'Result') or
          SameText(CleanName(ANode[0].Name), Name)) then
          Returns.Add(ANode)
        else if (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
          (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, 'Exit') then
          Returns.Add(ANode);
      end);
    for Statement in Returns do
    begin
      CheckCancelled;
      if Statement.Kind = TSyntaxKind.AssignStatement then
        AddValueNode(TDataFlowKind.Return, BodyTree, BodyFile, Statement.StartPos, Statement[1], '', '')
      else
        AddValueNode(TDataFlowKind.Return, BodyTree, BodyFile, Statement.StartPos, Statement[1], 'Exit', '');
    end;
  finally
    Returns.Free;
  end;
end;

procedure TDataFlowRun.PropertyReads(const ASymbol: TDataFlowSymbol);
var
  Tree: TSyntaxTree;
  Declaration: TSyntaxNode;
  Position: TTextPosition;
  Reader: TDataFlowSymbol;
begin
  // Der gelesene Wert kommt aus dem Feld bzw. Getter hinter read.
  Tree := TreeOf(ASymbol.FileName);
  Declaration := NodeAt(Tree.Root, ASymbol.Position);
  if (Declaration.Kind <> TSyntaxKind.PropertyDecl) or not Accessor(Tree, Declaration, 'read', Position) or
    not ResolveSymbol(Tree, ASymbol.FileName, Position, Reader) then
    Exit;
  AddTargetNode(TDataFlowKind.PropertyRead, ASymbol.FileName, Position, Reader, 'read ' + Reader.Name, '', '');
end;

{ TDataFlowRun: Wohin }

procedure TDataFlowRun.TargetsOf(const ASymbol: TDataFlowSymbol);
var
  Location: TReferenceLocation;
  Tree, DeclarationTree: TSyntaxTree;
  Node, Statement, Ancestor: TSyntaxNode;
  Reason: string;
  Position: TTextPosition;
  Prop: TDataFlowSymbol;
  InHeader: Boolean;
begin
  DeclarationTree := TreeOf(ASymbol.FileName);
  if DeclarationTree = nil then
    Exit;
  for Location in Occurrences(ASymbol) do
  begin
    CheckCancelled;
    if SameText(ExtractFileExt(Location.FileName), '.dfm') or SameText(ExtractFileExt(Location.FileName), '.fmx') then
      Continue;
    Tree := TreeOf(Location.FileName);
    if Tree = nil then
      Continue;
    Position := Location.Range.StartPos;
    Node := NodeAt(Tree.Root, Position);
    if Node.Kind = TSyntaxKind.PropertyDecl then
    begin
      // Feld bzw. Getter hinter read: Der Wert geht in die Property.
      if SameText(AccessorBefore(Tree, Position), 'read') and PropertyName(Tree, Node, Position) and
        ResolveSymbol(Tree, Location.FileName, Position, Prop) then
        AddTargetNode(TDataFlowKind.PropertyRead, Location.FileName, Location.Range.StartPos, Prop,
          'property ' + Prop.Name, '', '');
      Continue;
    end;
    if not (Node.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) then
      Continue;
    // Köpfe von Deklaration und Implementierung sind keine Verwendung.
    InHeader := False;
    Ancestor := Node.Parent;
    while Ancestor <> nil do
    begin
      if Ancestor.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.Parameters] then
        InHeader := True;
      Ancestor := Ancestor.Parent;
    end;
    if InHeader then
      Continue;
    Reason := '';
    if WrittenTarget(Node, Statement, Reason) then
      Continue;
    FlowUp(Tree, Location.FileName, Position, Node);
  end;
end;

procedure TDataFlowRun.FlowUp(ATree: TSyntaxTree; const AFileName: string; const APosition: TTextPosition;
  AStart: TSyntaxNode);
var
  Current, Parent: TSyntaxNode;
  Reason, Via, Name: string;
  Target: TDataFlowSymbol;
  Resolved: TResolvedSymbol;
  Params: TArray<TDataFlowParam>;
  Argument: Integer;
  Position: TTextPosition;
begin
  Current := AStart;
  Reason := '';
  Via := '';
  while True do
  begin
    Parent := Current.Parent;
    if Parent = nil then
      Break;
    case Parent.Kind of
      TSyntaxKind.ParenExpr, TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.SetConstructor,
        TSyntaxKind.RangeExpr:
        Current := Parent;
      TSyntaxKind.IfExpr:
        if Parent[0] = Current then
          Break
        else
          Current := Parent;
      TSyntaxKind.IndexAccess:
        if Parent[0] = Current then
          Current := Parent
        else
          Break;
      TSyntaxKind.Dereference:
        begin
          Reason := 'pointer';
          Current := Parent;
        end;
      TSyntaxKind.AddressOf:
        begin
          Reason := 'address';
          Current := Parent;
        end;
      TSyntaxKind.Call:
        begin
          // Der Aufgerufene selbst: Sein Ergebnis fließt weiter.
          if Parent[0] = Current then
          begin
            Current := Parent;
            Continue;
          end;
          Argument := ChildIndex(Parent, Current) - 1;
          Name := CalleeName(Parent);
          if Name = 'exit' then
          begin
            if EnclosingFunction(ATree, AFileName, Parent, Target) then
              AddTargetNode(TDataFlowKind.Return, AFileName, APosition, Target, ExprText(AFileName, Parent), 'Exit',
                Reason);
            Exit;
          end;
          if (Name = 'write') or (Name = 'writeln') then
          begin
            AddLeafNode(TDataFlowKind.Output, AFileName, APosition, ExprText(AFileName, Parent), ShortName(Parent.Name),
              Reason);
            Exit;
          end;
          if ((Name = 'move') and (Argument = 0) or ((Name = 'str') or (Name = 'val')) and (Argument = 0)) and
            (Parent.ChildCount > 2) then
          begin
            if Name = 'move' then
              Reason := 'move';
            if TargetRoot(ATree, AFileName, Parent[2], Reason, Target) then
              AddTargetNode(TDataFlowKind.Assignment, AFileName, APosition, Target, ExprText(AFileName, Parent[2]),
                ShortName(Parent.Name), Reason);
            Exit;
          end;
          if not ResolvedAt(ATree, AFileName, NamePosition(ATree, Parent[0]), Resolved) or
            (Resolved.SymbolKind in TypeKinds) or not InProject(Resolved.FileName) then
          begin
            // Typumwandlung oder Routine von außen: Der Wert steckt im Ergebnis.
            if Via = '' then
              Via := ShortName(Parent.Name);
            Current := Parent;
            Continue;
          end;
          Params := ParamsOf(Resolved.FileName, Resolved.SelectionRange.StartPos);
          if (Argument >= 0) and (Argument <= High(Params)) then
          begin
            Target := Default(TDataFlowSymbol);
            Target.Name := Params[Argument].Name;
            Target.FileName := Params[Argument].FileName;
            Target.Position := Params[Argument].Position;
            Target.SymbolKind := TIndexSymbolKind.Variable;
            AddTargetNode(TDataFlowKind.Argument, AFileName, APosition, Target, ExprText(AFileName, Parent),
              Resolved.Name, Reason);
            Exit;
          end;
          Break;
        end;
      TSyntaxKind.AssignStatement:
        begin
          if (Parent.ChildCount < 2) or (Parent[1] <> Current) then
            Break;
          // Result := … bzw. Funktionsname := … gibt den Wert zurück.
          if (Parent[0].Kind = TSyntaxKind.Identifier) and EnclosingFunction(ATree, AFileName, Parent, Target) and
            (SameText(Parent[0].Name, 'Result') or SameText(CleanName(Parent[0].Name), ShortName(Target.Name))) then
          begin
            AddTargetNode(TDataFlowKind.Return, AFileName, APosition, Target, ExprText(AFileName, Parent), Via, Reason);
            Exit;
          end;
          if TargetRoot(ATree, AFileName, Parent[0], Reason, Target) then
            AddTargetNode(TDataFlowKind.Assignment, AFileName, APosition, Target, ExprText(AFileName, Parent), Via,
              Reason);
          Exit;
        end;
      TSyntaxKind.InlineVar, TSyntaxKind.InlineConst, TSyntaxKind.VarDecl, TSyntaxKind.ConstDecl:
        begin
          if Current.Kind in TypeNodeKinds then
            Break;
          if SameText(AccessorBefore(ATree, Current.StartPos), 'absolute') then
            Reason := 'absolute';
          if NameInNode(ATree, Parent, CleanName(Trim(Parent.Name.Split([','])[0])), Position) and
            ResolveSymbol(ATree, AFileName, Position, Target) then
            AddTargetNode(TDataFlowKind.Initializer, AFileName, APosition, Target, ExprText(AFileName, Parent), Via,
              Reason);
          Exit;
        end;
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
        begin
          if (Current.Kind in StatementKinds) or (Current.Kind in TypeNodeKinds) then
            Break;
          if NameInNode(ATree, Parent, CleanName(Parent.Name), Position) and
            ResolveSymbol(ATree, AFileName, Position, Target) then
            AddTargetNode(TDataFlowKind.Loop, AFileName, APosition, Target, ExprText(AFileName, Current), Via, Reason);
          Exit;
        end;
    else
      Break;
    end;
  end;
  // Bedingung, Index, verworfenes Ergebnis, Mitgliedszugriff: verwendet, fließt aber nicht weiter.
  AddLeafNode(TDataFlowKind.Use, AFileName, APosition, '', Via, Reason);
end;

function TDataFlowRun.Run(const APosition: TTextPosition; ADirection: TDataFlowDirection): TDataFlowResult;
begin
  Result := Default(TDataFlowResult);
  Result.Found := ResolveSymbol(FOwnTree, FOwnFile, APosition, Result.Symbol);
  if not Result.Found then
    Exit;
  FCurrentKey := Result.Symbol.Key;
  if ADirection = TDataFlowDirection.Sources then
    SourcesOf(Result.Symbol)
  else
    TargetsOf(Result.Symbol);
  Result.Nodes := FNodes.ToArray;
end;

{ TLspDataFlow }

function TLspDataFlow.GetNamespaces: TArray<string>;
begin
  Result := TLspNamespaces.Read(FNamespaces);
end;

procedure TLspDataFlow.SetNamespaces(const AValue: TArray<string>);
begin
  TLspNamespaces.Write(FNamespaces, AValue);
end;

constructor TLspDataFlow.Create(const AStore: IDocumentStore; const AIndex: ISymbolIndex;
  const AReadText: TReferenceReadText; const AFiles: TReferenceFilesProvider; const AEnsureUnit: TEnsureUnitFunc);
begin
  inherited Create;
  FStore := AStore;
  FIndex := AIndex;
  FReadText := AReadText;
  FFiles := AFiles;
  FEnsureUnit := AEnsureUnit;
end;

procedure TLspDataFlow.Attach(ADispatcher: TJsonRpcDispatcher);
begin
  ADispatcher.RegisterConcurrentRequest(Method, HandleDataFlow);
end;

class function TLspDataFlow.Analyze(AResolver: TNameResolver; const AIndex: ISymbolIndex; ATree: TSyntaxTree;
  const AFileName: string; const APosition: TTextPosition; ADirection: TDataFlowDirection;
  const AOptions: TDataFlowOptions; const AFiles: TArray<string>; const AReadText: TReferenceReadText;
  const ACancellation: IJsonRpcCancellationToken): TDataFlowResult;
var
  Run: TDataFlowRun;
begin
  Run := TDataFlowRun.Create(AResolver, AIndex, ATree, AFileName, AOptions, AFiles, AReadText, ACancellation);
  try
    Result := Run.Run(APosition, ADirection);
  finally
    Run.Free;
  end;
end;

class function TLspDataFlow.KindName(AKind: TDataFlowKind): string;
const
  Names: array[TDataFlowKind] of string = ('assignment', 'varArgument', 'outArgument', 'input', 'initialization',
    'loop', 'callerArgument', 'return', 'propertyWrite', 'propertyRead', 'modify', 'argument', 'output', 'use',
    'constant', 'outside', 'address');
begin
  Result := Names[AKind];
end;

class function TLspDataFlow.LeafName(ALeaf: TDataFlowLeaf): string;
const
  Names: array[TDataFlowLeaf] of string = ('', 'constant', 'outside', 'cycle');
begin
  Result := Names[ALeaf];
end;

function SymbolToJson(const ASymbol: TDataFlowSymbol): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', ASymbol.Name);
  Result.AddPair('uri', TDocumentUris.FromPath(ASymbol.FileName));
  Result.AddPair('line', TJSONNumber.Create(ASymbol.Position.Line));
  Result.AddPair('character', TJSONNumber.Create(ASymbol.Position.Character));
  Result.AddPair('key', ASymbol.Key);
  Result.AddPair('symbolKind', TJSONNumber.Create(Ord(ASymbol.SymbolKind)));
  if ASymbol.Leaf <> TDataFlowLeaf.None then
    Result.AddPair('leaf', TLspDataFlow.LeafName(ASymbol.Leaf));
end;

class function TLspDataFlow.ToJson(const AResult: TDataFlowResult): TJSONObject;
var
  Nodes, Places, Sources: TJSONArray;
  Node: TDataFlowNode;
  Item, Entry: TJSONObject;
  Place: TDataFlowPlace;
  Source: TDataFlowSymbol;
begin
  Result := TJSONObject.Create;
  Result.AddPair('found', TJSONBool.Create(AResult.Found));
  if not AResult.Found then
    Exit;
  Result.AddPair('symbol', SymbolToJson(AResult.Symbol));
  Nodes := TJSONArray.Create;
  Result.AddPair('nodes', Nodes);
  for Node in AResult.Nodes do
  begin
    Item := TJSONObject.Create;
    Nodes.AddElement(Item);
    Item.AddPair('kind', KindName(Node.Kind));
    Item.AddPair('detail', Node.Detail);
    if Node.Via <> '' then
      Item.AddPair('via', Node.Via);
    if Node.Literal then
      Item.AddPair('literal', TJSONBool.Create(True));
    if Node.Unsafe then
    begin
      Item.AddPair('unsafe', TJSONBool.Create(True));
      Item.AddPair('unsafeReason', Node.UnsafeReason);
    end;
    Places := TJSONArray.Create;
    Item.AddPair('places', Places);
    for Place in Node.Places do
    begin
      Entry := TJSONObject.Create;
      Places.AddElement(Entry);
      Entry.AddPair('uri', TDocumentUris.FromPath(Place.FileName));
      Entry.AddPair('line', TJSONNumber.Create(Place.Position.Line));
      Entry.AddPair('character', TJSONNumber.Create(Place.Position.Character));
      Entry.AddPair('lineText', Place.LineText);
    end;
    Sources := TJSONArray.Create;
    Item.AddPair('sources', Sources);
    for Source in Node.Sources do
      Sources.AddElement(SymbolToJson(Source));
  end;
end;

function TLspDataFlow.HandleDataFlow(const AParams: TJSONValue;
  const ACancellation: IJsonRpcCancellationToken): TJSONValue;
var
  Cancellation: IPascalCancellation;
  Params: TJSONObject;
  Uri, Direction: string;
  PositionValue, PathValue: TJSONValue;
  Document: ITextDocument;
  Shared: ISharedSyntaxTree;
  Tree, OwnTree: TSyntaxTree;
  Text: string;
  Options: TDataFlowOptions;
  Files: TArray<string>;
  Resolver: TNameResolver;
  Analysis: TDataFlowResult;
  Item: TJSONValue;
begin
  if not ((AParams is TJSONObject) and TJSONObject(AParams).TryGetValue<string>('textDocument.uri', Uri) and
    TJSONObject(AParams).TryGetValue<TJSONValue>('position', PositionValue)) then
    raise EJsonRpcError.Create(TJsonRpcErrorCode.InvalidParams,
      'Felder "textDocument.uri" und "position" fehlen in ' + Method);
  Params := TJSONObject(AParams);
  if not Params.TryGetValue<string>('direction', Direction) then
    Direction := 'sources';
  Options := Default(TDataFlowOptions);
  if not Params.TryGetValue<Boolean>('excludeTests', Options.ExcludeTests) then
    Options.ExcludeTests := False;
  if not Params.TryGetValue<Boolean>('onlyProject', Options.OnlyProject) then
    Options.OnlyProject := False;
  if Params.TryGetValue<TJSONValue>('path', PathValue) and (PathValue is TJSONArray) then
    for Item in TJSONArray(PathValue) do
      Options.Path := Options.Path + [Item.Value];
  Cancellation := TRequestCancellation.Create(ACancellation);
  OwnTree := nil;
  if FStore.TryGet(Uri, Document) then
  begin
    Shared := TSyntaxTreeCache.Get(Document, Cancellation);
    Tree := Shared.Tree;
  end
  else if Assigned(FReadText) and FReadText(TDocumentUris.ToPath(Uri), Text) then
  begin
    OwnTree := TSyntaxTreeCache.Parse(Text, Cancellation);
    Tree := OwnTree;
  end
  else
    Exit(TJSONNull.Create);
  try
    Files := nil;
    if Assigned(FFiles) then
      Files := FFiles();
    ACancellation.ThrowIfCancellationRequested;
    Resolver := TNameResolver.Create(FIndex, FEnsureUnit);
    try
      Resolver.Namespaces := Namespaces;
      if SameText(Direction, 'targets') then
        Analysis := Analyze(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
          TDataFlowDirection.Targets, Options, Files, FReadText, ACancellation)
      else
        Analysis := Analyze(Resolver, FIndex, Tree, TDocumentUris.ToPath(Uri), TLspPositions.ReadPosition(PositionValue),
          TDataFlowDirection.Sources, Options, Files, FReadText, ACancellation);
    finally
      Resolver.Free;
    end;
  finally
    OwnTree.Free;
  end;
  Result := ToJson(Analysis);
end;

end.
