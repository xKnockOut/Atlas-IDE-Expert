unit Atlas.Common.Semantics.ControlFlow;

// Kontrollflussgraph je Routine als gemeinsamer Dienst für flussbasierte
// Prüfregeln (unerreichbarer Code, nicht gesetztes Result, nicht
// initialisierte Variablen, Speicherlecks, ungenutzte Variablen).
//
// Jede Anweisung ist ein Knoten. Bedingungen von if, case und Schleifen
// sind eigene Knoten der Art Condition. Berücksichtigt werden
// try/finally/except, Exit, Break, Continue, raise, Abort, Halt und goto.
// Innerhalb eines try kann jede Anweisung eine Ausnahme auslösen; außerhalb
// führen nur raise und Abort zum Knoten RaiseExit.
//
// Ein finally-Block wird je Ausgang einmal modelliert: für das normale Ende
// des try-Teils und für jedes Sprungziel (Exit, Break, Continue, Ausnahme)
// eine eigene Kopie, deren Ende nur zu diesem Ziel führt. Früher gab es eine
// Kopie für alle; dann lief der Weg einer Ausnahme nach dem finally normal
// weiter, und result-not-set meldete jede Funktion, die Result im try-Teil
// setzt (#647).
//
// Zuweisungen: einfache Zuweisungen an einen Bezeichner, Schleifenvariablen,
// Inline-Variablen mit Startwert und Exit(Wert) für Result.
//
// Unsichere Änderungen (#143): Übergibt eine Anweisung eine Variable an einen
// var- oder out-Parameter oder an eine Routine mit unbekannter Signatur
// (TryGetValue(K, Result), SetLength(Result, N), FillChar(Result, …)), nimmt
// sie ihre Adresse (@Result, Addr(Result)), weist sie einem Teil zu
// (Result.Feld := …, Result[I] := …), ruft eine Methode auf ihr auf, nutzt sie
// in with oder erwähnt sie in einer anonymen Methode, "berührt" der Knoten die
// Variable: Sie kann danach gesetzt sein oder nicht. Abfragen über Wege durch
// einen solchen Knoten antworten Unknown statt No oder Yes. Die Signatur
// liefert ein TFlowSignatureLookup; ohne Angabe gelten die Routinen derselben
// Datei und die Standardroutinen, Aufrufe über Objekte (Obj.Methode) sind
// unbekannt. Bei bekannter Signatur mit Wertparameter (ohne Modifizierer oder
// const) bleibt die Aussage unverändert.
//
// Enthält die Routine asm oder Syntaxfehler, ist der Graph unvollständig;
// die Abfragen liefern dann Unknown statt einer Vermutung.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.SyntaxTree;

type
  TFlowNodeKind = (Entry, Exit, RaiseExit, Statement, Condition, Join);

  TFlowAnswer = (No, Yes, Unknown);

  /// <summary>Wie ein Aufruf ein Argument übergibt (#143).</summary>
  TFlowArgumentMode = (Value, Reference, Output, Unknown);

  /// <summary>Übergabeart des Arguments AArgument (0-basiert) im Aufruf ACall (Knoten der Art Call).</summary>
  TFlowSignatureLookup = reference to function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode;

  TFlowSignatures = class
  public
    /// <summary>Übergabeart bei Standardroutinen und Typumwandlungen (SetLength, FillChar, Inc, Str,
    /// Addr, IntToStr, Integer(…)); False bei unbekanntem Namen.</summary>
    class function TryBuiltin(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
      static;
    /// <summary>Routinen aus dem Baum unter ARoot (Überladungen zusammengefasst), dann Standardroutinen,
    /// sonst Unknown; Aufrufe über Objekte sind Unknown. Liest den Baum erst beim ersten Aufruf;
    /// ARoot muss länger leben als die Funktion.</summary>
    class function FromTree(ARoot: TSyntaxNode): TFlowSignatureLookup; static;
  end;

  TFlowNode = class
  private
    FIndex: Integer;
    FKind: TFlowNodeKind;
    FSyntax: TSyntaxNode;
    FDefines: string;
    FReads: TArray<string>;
    FMaybeReads: TArray<string>;
    FTouches: TArray<string>;
    FSuccessors: TList<TFlowNode>;
    FPredecessors: TList<TFlowNode>;
    FMayRaise: Boolean;
    FRaiseEntry: Boolean;
  public
    constructor Create(AIndex: Integer; AKind: TFlowNodeKind; ASyntax: TSyntaxNode);
    destructor Destroy; override;
    property Index: Integer read FIndex;
    property Kind: TFlowNodeKind read FKind;
    /// <summary>Anweisung oder Bedingung; nil bei Entry, Exit, RaiseExit und Join.</summary>
    property Syntax: TSyntaxNode read FSyntax;
    /// <summary>Name der Variablen, der dieser Knoten einen Wert zuweist; sonst ''.</summary>
    property Defines: string read FDefines;
    function ReadsName(const AName: string): Boolean;
    function MaybeReadsName(const AName: string): Boolean;
    function TouchesName(const AName: string): Boolean;
    /// <summary>Anweisung in einem try: Sie kann eine Ausnahme auslösen, bevor sie wirkt (#915).</summary>
    property MayRaise: Boolean read FMayRaise;
    /// <summary>Führt die Kante zu ANext nur über eine mögliche Ausnahme dieser Anweisung (nicht über raise)?
    /// Regeln, die einem Wert folgen, können solche Wege auslassen (use-after-free, #915).</summary>
    function IsImplicitRaiseEdge(ANext: TFlowNode): Boolean;
    property Successors: TList<TFlowNode> read FSuccessors;
    property Predecessors: TList<TFlowNode> read FPredecessors;
  end;

  TReachingDefinitions = record
    /// <summary>Zuweisungen, die den Knoten ohne erneute Zuweisung erreichen.</summary>
    Definitions: TArray<TFlowNode>;
    /// <summary>Ein Weg vom Anfang der Routine kommt ohne Zuweisung und ohne unsichere Änderung an.</summary>
    FromEntry: Boolean;
    /// <summary>Ein Weg vom Anfang kommt ohne Zuweisung, aber über eine unsichere Änderung an.</summary>
    MaybeFromEntry: Boolean;
    /// <summary>Knoten mit unsicherer Änderung auf den Wegen zurück (#143).</summary>
    Uncertain: TArray<TFlowNode>;
  end;

  TControlFlowGraph = class
  private
    FNodes: TObjectList<TFlowNode>;
    FEntry: TFlowNode;
    FExit: TFlowNode;
    FRaiseExit: TFlowNode;
    FComplete: Boolean;
    FFallThrough: TArray<TFlowNode>;
    FDominators: TArray<TArray<Boolean>>;
    procedure ComputeDominators;
    /// <summary>Ein Durchgang über alle Knoten; True, wenn sich etwas geändert hat.</summary>
    function UpdateDominators(const AReachable: TArray<Boolean>): Boolean;
    /// <summary>Ist eine andere Kopie der Anweisung von ANode (finally je Ausgang) erreichbar?</summary>
    function HasReachableCopy(ANode: TFlowNode): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Baut den Graphen für eine Routine (RoutineDecl, AnonymousMethod)
    /// oder einen Anweisungsblock. Der Syntaxbaum muss länger leben als der Graph.
    /// ALookup nennt die Übergabeart von Argumenten; nil = TFlowSignatures.FromTree
    /// mit der Wurzel des Baums.</summary>
    class function Build(ARoutine: TSyntaxNode; const ALookup: TFlowSignatureLookup): TControlFlowGraph;
      overload; static;
    /// <summary>Wie oben mit ALookup = nil.</summary>
    class function Build(ARoutine: TSyntaxNode): TControlFlowGraph; overload; static;
    function NodeOf(ASyntax: TSyntaxNode): TFlowNode;
    function IsReachable(ANode: TFlowNode): TFlowAnswer;
    /// <summary>Wird A auf jedem Weg vom Anfang zu B durchlaufen?</summary>
    function Dominates(A, B: TFlowNode): TFlowAnswer;
    /// <summary>Anweisungen, die vom Anfang aus nicht erreichbar sind.</summary>
    function UnreachableStatements: TArray<TFlowNode>;
    function ReachingDefinitions(ANode: TFlowNode; const AName: string): TReachingDefinitions;
    /// <summary>Kann die Routine normal enden, ohne dass AName (z. B. Result) gesetzt wurde?
    /// Unknown, wenn das nur über eine unsichere Änderung möglich ist.</summary>
    function MayEndWithout(const AName: string): TFlowAnswer;
    /// <summary>Wird AName irgendwo gelesen, bevor ihm auf jedem Weg ein Wert zugewiesen wurde?</summary>
    function MayReadBeforeWrite(const AName: string): TFlowAnswer; overload;
    /// <summary>Kann AName beim Erreichen von ANode noch ohne Zuweisung sein?</summary>
    function MayReadBeforeWrite(ANode: TFlowNode; const AName: string): TFlowAnswer; overload;
    property Nodes: TObjectList<TFlowNode> read FNodes;
    property Entry: TFlowNode read FEntry;
    property ExitNode: TFlowNode read FExit;
    property RaiseExit: TFlowNode read FRaiseExit;
    /// <summary>False bei asm oder Syntaxfehlern in der Routine.</summary>
    property Complete: Boolean read FComplete;
    /// <summary>Letzte Knoten der Wege, die am Ende des Rumpfs herausfallen (ohne Exit, Halt oder raise); sie
    /// führen direkt zu ExitNode. Leer, wenn jeder Weg vorher springt (#698).</summary>
    property FallThrough: TArray<TFlowNode> read FFallThrough;
  end;

implementation

uses
  Atlas.Common.Semantics.ControlFlow.Statements;

type
  /// <summary>Sprungziel, dessen Knoten erst später feststeht.</summary>
  TJumpTarget = class
  public
    Depth: Integer;
    Sources: TList<TFlowNode>;
    constructor Create(ADepth: Integer);
    destructor Destroy; override;
  end;

  TFinallyContext = class
  public
    /// <summary>Ziele der Sprünge aus dem try-Teil; Routes[I] sammelt die Quellen zu Onward[I].</summary>
    Onward: TList<TJumpTarget>;
    Routes: TObjectList<TJumpTarget>;
    constructor Create;
    destructor Destroy; override;
  end;

  TLoopContext = record
    BreakTarget: TJumpTarget;
    ContinueTarget: TJumpTarget;
  end;

  TFlowBuilder = class
  private
    FGraph: TControlFlowGraph;
    FTargets: TObjectList<TJumpTarget>;
    FFinallies: TObjectList<TFinallyContext>;
    FLoops: TList<TLoopContext>;
    FRaiseTargets: TList<TJumpTarget>;
    FExitTarget: TJumpTarget;
    FRaiseTarget: TJumpTarget;
    FLabels: TDictionary<string, TFlowNode>;
    FTryDepth: Integer;
    FLookup: TFlowSignatureLookup;
    procedure Analyze(ANode: TFlowNode);
    function NewNode(AKind: TFlowNodeKind; ASyntax: TSyntaxNode): TFlowNode;
    function NewTarget: TJumpTarget;
    procedure Link(AFrom, ATo: TFlowNode);
    procedure LinkAll(const AFrom: TArray<TFlowNode>; ATo: TFlowNode);
    procedure Resolve(ATarget: TJumpTarget; ATo: TFlowNode);
    procedure Jump(AFrom: TFlowNode; ATarget: TJumpTarget);
    function LabelNode(const AName: string): TFlowNode;
    function Simple(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TFlowNode;
    function Sequence(AParent: TSyntaxNode; AFirst: Integer; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function Statement(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildIf(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCase(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildLoop(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildRepeat(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildTry(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCall(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>with und Label: ein Knoten vor den enthaltenen Anweisungen.</summary>
    function BuildPrefixed(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>raise und goto: Der Weg geht nicht hinter der Anweisung weiter.</summary>
    function BuildJump(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>Zuweisung und Inline-Deklaration: setzt Defines.</summary>
    function BuildDefinition(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildTryFinally(AStatement, AFinallyPart: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>Je Sprungziel aus dem try-Teil eine Kopie des finally-Teils, die nur dorthin weiterführt.</summary>
    procedure FinallyCopies(AContext: TFinallyContext; AFinallyPart: TSyntaxNode);
    function BuildTryExcept(AStatement, AExceptPart: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
  public
    constructor Create(AGraph: TControlFlowGraph; const ALookup: TFlowSignatureLookup);
    destructor Destroy; override;
    procedure Run(ARoutine: TSyntaxNode);
  end;

  /// <summary>Signaturen der Routinen einer Datei, erst bei Bedarf gelesen.</summary>
  IFlowRoutineTable = interface
    ['{6E1B7C2A-4F3D-4A8B-9C5E-2D7F1A3B8E64}']
    function Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
  end;

  TFlowRoutineTable = class(TInterfacedObject, IFlowRoutineTable)
  private
    FRoot: TSyntaxNode;
    FRoutines: TDictionary<string, TArray<TFlowArgumentMode>>;
    procedure Collect(ANode: TSyntaxNode);
    procedure AddHeader(AHeader: TSyntaxNode);
  public
    constructor Create(ARoot: TSyntaxNode);
    destructor Destroy; override;
    function Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
  end;

function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

procedure AddName(var ANames: TArray<string>; const AName: string);
begin
  if (AName <> '') and not ContainsName(ANames, AName) then
  begin
    ANames := ANames + [AName];
  end;
end;

/// <summary>Bezeichner, an dem eine Kette wie X.Feld, X[I] oder X^ hängt; sonst ''.</summary>
function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
  begin
    ANode := ANode.Children[0];
  end;
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
  begin
    Result := ANode.Name;
  end
  else
  begin
    Result := '';
  end;
end;

/// <summary>Enthält die Kette bis zum Bezeichner ein ^? Dann ändert sie nicht die Variable selbst.</summary>
function ThroughPointer(ANode: TSyntaxNode): Boolean;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
  begin
    if ANode.Kind = TSyntaxKind.Dereference then
    begin
      Exit(True);
    end;
    ANode := ANode.Children[0];
  end;
  Result := False;
end;

/// <summary>Enthält der Teilbaum einen Fehlerknoten (auch in Ausdrücken)?</summary>
function ContainsError(ANode: TSyntaxNode): Boolean;
begin
  // Iterativ (Bericht M1): Ausdrücke wie 1 - 1 - … - 1 sind so tief wie lang.
  Result := ANode.Search(
    function(AVisited: TSyntaxNode): TSyntaxSearchStep
    begin
      if AVisited.Kind = TSyntaxKind.Error then
      begin
        Exit(TSyntaxSearchStep.Found);
      end;
      Result := TSyntaxSearchStep.Descend;
    end) <> nil;
end;

function Concat(const A, B: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  Result := A;
  for mNode in B do
  begin
    Result := Result + [mNode];
  end;
end;

{ TFlowNode }

constructor TFlowNode.Create(AIndex: Integer; AKind: TFlowNodeKind; ASyntax: TSyntaxNode);
begin
  inherited Create;
  FIndex := AIndex;
  FKind := AKind;
  FSyntax := ASyntax;
  FSuccessors := TList<TFlowNode>.Create;
  FPredecessors := TList<TFlowNode>.Create;
end;

destructor TFlowNode.Destroy;
begin
  FSuccessors.Free;
  FPredecessors.Free;
  inherited;
end;

function TFlowNode.ReadsName(const AName: string): Boolean;
begin
  Result := ContainsName(FReads, AName);
end;

function TFlowNode.MaybeReadsName(const AName: string): Boolean;
begin
  Result := ContainsName(FMaybeReads, AName);
end;

function TFlowNode.TouchesName(const AName: string): Boolean;
begin
  Result := ContainsName(FTouches, AName);
end;

function TFlowNode.IsImplicitRaiseEdge(ANext: TFlowNode): Boolean;
begin
  Result := FMayRaise and (ANext <> nil) and ANext.FRaiseEntry and
    not ((FSyntax <> nil) and (FSyntax.Kind = TSyntaxKind.RaiseStatement));
end;

{ TFlowSignatures }

type
  TBuiltinSignature = record
    Name: string;
    /// <summary>Je Argument V (Wert), R (var), O (out); das letzte Zeichen gilt für alle weiteren.</summary>
    Modes: string;
  end;

const
  cBuiltinSignatures: array[0..27] of TBuiltinSignature = (
    (Name: 'SetLength'; Modes: 'RV'), (Name: 'FillChar'; Modes: 'RV'), (Name: 'Inc'; Modes: 'RV'),
    (Name: 'Dec'; Modes: 'RV'), (Name: 'Include'; Modes: 'RV'), (Name: 'Exclude'; Modes: 'RV'),
    (Name: 'Insert'; Modes: 'VRV'), (Name: 'Delete'; Modes: 'RV'), (Name: 'Move'; Modes: 'VRV'),
    (Name: 'SetString'; Modes: 'RV'), (Name: 'Initialize'; Modes: 'RV'), (Name: 'Finalize'; Modes: 'RV'),
    (Name: 'FreeAndNil'; Modes: 'R'), (Name: 'GetMem'; Modes: 'RV'), (Name: 'ReallocMem'; Modes: 'RV'),
    (Name: 'New'; Modes: 'RV'), (Name: 'Dispose'; Modes: 'RV'), (Name: 'Addr'; Modes: 'R'),
    (Name: 'AtomicIncrement'; Modes: 'RV'), (Name: 'AtomicDecrement'; Modes: 'RV'),
    (Name: 'AtomicExchange'; Modes: 'RV'), (Name: 'AtomicCmpExchange'; Modes: 'RV'),
    (Name: 'Read'; Modes: 'R'), (Name: 'ReadLn'; Modes: 'R'), (Name: 'Str'; Modes: 'VO'),
    (Name: 'Val'; Modes: 'VO'), (Name: 'SwapEndian'; Modes: 'V'), (Name: 'Exit'; Modes: 'V'));

  /// <summary>Routinen und Typumwandlungen, die alle Argumente als Wert nehmen.</summary>
  cValueRoutines: array[0..63] of string = ('Length', 'High', 'Low', 'SizeOf', 'Assigned', 'Ord', 'Chr', 'Succ',
    'Pred', 'Abs', 'Round', 'Trunc', 'Frac', 'Int', 'Odd', 'Sqr', 'Sqrt', 'Copy', 'Pos', 'Concat', 'IntToStr',
    'StrToInt', 'StrToIntDef', 'FloatToStr', 'Format', 'Trim', 'UpperCase', 'LowerCase', 'SameText',
    'CompareText', 'CompareStr', 'Write', 'WriteLn', 'ShowMessage', 'Assert', 'Halt', 'TypeInfo', 'Default',
    'IntToHex', 'QuotedStr', 'Max', 'Min', 'BoolToStr', 'FreeMem', 'Integer', 'Cardinal', 'Byte', 'Word',
    'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Boolean', 'Char', 'AnsiChar', 'WideChar', 'string',
    'Pointer', 'Double', 'Single', 'Extended', 'Currency', 'LongInt', 'TObject');

class function TFlowSignatures.TryBuiltin(const AName: string; AArgument: Integer;
  out AMode: TFlowArgumentMode): Boolean;
var
  mSignature: TBuiltinSignature;
  mCode: Char;
  mName: string;
begin
  AMode := TFlowArgumentMode.Unknown;
  for mSignature in cBuiltinSignatures do
  begin
    if SameText(mSignature.Name, AName) then
    begin
      if AArgument < Length(mSignature.Modes) then
      begin
        mCode := mSignature.Modes[AArgument + 1];
      end
      else
      begin
        mCode := mSignature.Modes[Length(mSignature.Modes)];
      end;
      case mCode of
        'R':
          AMode := TFlowArgumentMode.Reference;
        'O':
          AMode := TFlowArgumentMode.Output;
      else
        AMode := TFlowArgumentMode.Value;
      end;
      Exit(True);
    end;
  end;
  for mName in cValueRoutines do
  begin
    if SameText(mName, AName) then
    begin
      AMode := TFlowArgumentMode.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TFlowSignatures.FromTree(ARoot: TSyntaxNode): TFlowSignatureLookup;
var
  mTable: IFlowRoutineTable;
begin
  mTable := TFlowRoutineTable.Create(ARoot);
  Result :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    var
      Callee: TSyntaxNode;
    begin
      Result := TFlowArgumentMode.Unknown;
      if (ACall = nil) or (ACall.ChildCount = 0) then
      begin
        Exit;
      end;
      Callee := ACall.Children[0];
      // Obj.Methode(…) oder Foo<T>(…): ohne Typauflösung unbekannt.
      if Callee.Kind <> TSyntaxKind.Identifier then
      begin
        Exit;
      end;
      if not mTable.Find(Callee.Name, AArgument, Result) then
      begin
        TFlowSignatures.TryBuiltin(Callee.Name, AArgument, Result);
      end;
    end;
end;

{ TFlowRoutineTable }

constructor TFlowRoutineTable.Create(ARoot: TSyntaxNode);
begin
  inherited Create;
  FRoot := ARoot;
end;

destructor TFlowRoutineTable.Destroy;
begin
  FRoutines.Free;
  inherited;
end;

/// <summary>Übergabeart je Parameter im Kopf AHeader.</summary>
function ParameterModes(AHeader: TSyntaxNode): TArray<TFlowArgumentMode>;
var
  mParams, mParam: TSyntaxNode;
  mMode: TFlowArgumentMode;
  mIndex, mCount: Integer;
begin
  Result := nil;
  mParams := AHeader.FindChild(TSyntaxKind.Parameters);
  if mParams = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mParams.ChildCount - 1 do
  begin
    mParam := mParams.Children[mIndex];
    if mParam.Kind <> TSyntaxKind.Parameter then
    begin
      Continue;
    end;
    case mParam.Modifier of
      TParameterModifier.VarParam:
        mMode := TFlowArgumentMode.Reference;
      TParameterModifier.OutParam:
        mMode := TFlowArgumentMode.Output;
    else
      mMode := TFlowArgumentMode.Value;
    end;
    for mCount := 1 to Length(mParam.Name.Split([','])) do
    begin
      Result := Result + [mMode];
    end;
  end;
end;

/// <summary>Überladungen: Wo sich die Übergabeart unterscheidet oder ein Argument fehlt, ist sie unbekannt.</summary>
procedure MergeOverload(const AKnown: TArray<TFlowArgumentMode>; var AModes: TArray<TFlowArgumentMode>);
var
  mIndex: Integer;
begin
  if Length(AKnown) > Length(AModes) then
  begin
    SetLength(AModes, Length(AKnown));
  end;
  for mIndex := 0 to High(AModes) do
  begin
    if (mIndex > High(AKnown)) or (AKnown[mIndex] <> AModes[mIndex]) then
    begin
      AModes[mIndex] := TFlowArgumentMode.Unknown;
    end;
  end;
end;

procedure TFlowRoutineTable.AddHeader(AHeader: TSyntaxNode);
var
  mModes, mKnown: TArray<TFlowArgumentMode>;
  mKey: string;
begin
  mModes := ParameterModes(AHeader);
  mKey := LowerCase(Copy(AHeader.Name, LastDelimiter('.', AHeader.Name) + 1, MaxInt));
  if mKey = '' then
  begin
    Exit;
  end;
  if FRoutines.TryGetValue(mKey, mKnown) then
  begin
    MergeOverload(mKnown, mModes);
  end;
  FRoutines.AddOrSetValue(mKey, mModes);
end;

procedure TFlowRoutineTable.Collect(ANode: TSyntaxNode);
var
  mHeaders: TList<TSyntaxNode>;
  mHeader: TSyntaxNode;
begin
  // Iterativ (Bericht M1): erst die Köpfe sammeln, dann eintragen.
  mHeaders := TList<TSyntaxNode>.Create;
  try
    ANode.Walk(
      function(AVisited: TSyntaxNode): Boolean
      begin
        if AVisited.Kind = TSyntaxKind.RoutineHeader then
        begin
          mHeaders.Add(AVisited);
        end;
        Result := True;
      end);
    for mHeader in mHeaders do
    begin
      AddHeader(mHeader);
    end;
  finally
    mHeaders.Free;
  end;
end;

function TFlowRoutineTable.Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
var
  mModes: TArray<TFlowArgumentMode>;
begin
  AMode := TFlowArgumentMode.Unknown;
  if FRoutines = nil then
  begin
    FRoutines := TDictionary<string, TArray<TFlowArgumentMode>>.Create;
    if FRoot <> nil then
    begin
      Collect(FRoot);
    end;
  end;
  Result := FRoutines.TryGetValue(LowerCase(AName), mModes);
  // Mehr Argumente als Parameter: andere Überladung oder offenes Array, also unbekannt.
  if Result and (AArgument >= 0) and (AArgument <= High(mModes)) then
  begin
    AMode := mModes[AArgument];
  end;
end;

{ TJumpTarget }

constructor TJumpTarget.Create(ADepth: Integer);
begin
  inherited Create;
  Depth := ADepth;
  Sources := TList<TFlowNode>.Create;
end;

destructor TJumpTarget.Destroy;
begin
  Sources.Free;
  inherited;
end;

{ TFinallyContext }

constructor TFinallyContext.Create;
begin
  inherited Create;
  Onward := TList<TJumpTarget>.Create;
  Routes := TObjectList<TJumpTarget>.Create;
end;

destructor TFinallyContext.Destroy;
begin
  Routes.Free;
  Onward.Free;
  inherited;
end;

{ TFlowBuilder }

constructor TFlowBuilder.Create(AGraph: TControlFlowGraph; const ALookup: TFlowSignatureLookup);
begin
  inherited Create;
  FGraph := AGraph;
  FLookup := ALookup;
  FTargets := TObjectList<TJumpTarget>.Create;
  FFinallies := TObjectList<TFinallyContext>.Create(False);
  FLoops := TList<TLoopContext>.Create;
  FRaiseTargets := TList<TJumpTarget>.Create;
  FLabels := TDictionary<string, TFlowNode>.Create;
end;

destructor TFlowBuilder.Destroy;
begin
  FLabels.Free;
  FRaiseTargets.Free;
  FLoops.Free;
  FFinallies.Free;
  FTargets.Free;
  inherited;
end;

function TFlowBuilder.NewNode(AKind: TFlowNodeKind; ASyntax: TSyntaxNode): TFlowNode;
begin
  Result := TFlowNode.Create(FGraph.FNodes.Count, AKind, ASyntax);
  FGraph.FNodes.Add(Result);
end;

function TFlowBuilder.NewTarget: TJumpTarget;
begin
  Result := TJumpTarget.Create(FFinallies.Count);
  FTargets.Add(Result);
end;

procedure TFlowBuilder.Link(AFrom, ATo: TFlowNode);
begin
  if AFrom.FSuccessors.Contains(ATo) then
  begin
    Exit;
  end;
  AFrom.FSuccessors.Add(ATo);
  ATo.FPredecessors.Add(AFrom);
end;

procedure TFlowBuilder.LinkAll(const AFrom: TArray<TFlowNode>; ATo: TFlowNode);
var
  mNode: TFlowNode;
begin
  for mNode in AFrom do
  begin
    Link(mNode, ATo);
  end;
end;

procedure TFlowBuilder.Resolve(ATarget: TJumpTarget; ATo: TFlowNode);
begin
  LinkAll(ATarget.Sources.ToArray, ATo);
end;

procedure TFlowBuilder.Jump(AFrom: TFlowNode; ATarget: TJumpTarget);
var
  mContext: TFinallyContext;
  mRoute: Integer;
begin
  // Verlässt der Sprung einen finally-Bereich, läuft er zuerst durch dessen finally.
  if FFinallies.Count > ATarget.Depth then
  begin
    mContext := FFinallies[FFinallies.Count - 1];
    mRoute := mContext.Onward.IndexOf(ATarget);
    if mRoute < 0 then
    begin
      mContext.Onward.Add(ATarget);
      mRoute := mContext.Routes.Add(TJumpTarget.Create(ATarget.Depth));
    end;
    mContext.Routes[mRoute].Sources.Add(AFrom);
  end
  else
  begin
    ATarget.Sources.Add(AFrom);
  end;
end;

function TFlowBuilder.LabelNode(const AName: string): TFlowNode;
var
  mKey: string;
begin
  mKey := LowerCase(AName);
  if not FLabels.TryGetValue(mKey, Result) then
  begin
    Result := NewNode(TFlowNodeKind.Join, nil);
    FLabels.Add(mKey, Result);
  end;
end;

function TFlowBuilder.Simple(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TFlowNode;
begin
  Result := NewNode(TFlowNodeKind.Statement, AStatement);
  LinkAll(APreds, Result);
  // Innerhalb eines try kann jede Anweisung eine Ausnahme auslösen.
  if FTryDepth > 0 then
  begin
    Result.FMayRaise := True;
    Jump(Result, FRaiseTargets.Last);
  end;
end;

function TFlowBuilder.Sequence(AParent: TSyntaxNode; AFirst: Integer;
  const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mIndex: Integer;
begin
  Result := APreds;
  for mIndex := AFirst to AParent.ChildCount - 1 do
  begin
    if TFlowStatements.IsStatement(AParent.Children[mIndex].Kind) then
    begin
      Result := Statement(AParent.Children[mIndex], Result);
    end;
  end;
end;

function TFlowBuilder.BuildPrefixed(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  if AStatement.Kind = TSyntaxKind.LabeledStatement then
  begin
    mNode := LabelNode(AStatement.Name);
    LinkAll(APreds, mNode);
  end
  else
  begin
    mNode := Simple(AStatement, APreds);
  end;
  Result := Sequence(AStatement, 0, [mNode]);
end;

function TFlowBuilder.BuildJump(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  mNode := Simple(AStatement, APreds);
  if AStatement.Kind = TSyntaxKind.RaiseStatement then
  begin
    Jump(mNode, FRaiseTargets.Last);
  end
  else
  begin
    Link(mNode, LabelNode(AStatement.Name));
  end;
  Result := nil;
end;

function TFlowBuilder.BuildDefinition(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
  mIndex: Integer;
begin
  mNode := Simple(AStatement, APreds);
  if AStatement.Kind = TSyntaxKind.AssignStatement then
  begin
    if (AStatement.ChildCount > 0) and (AStatement.Children[0].Kind = TSyntaxKind.Identifier) then
    begin
      mNode.FDefines := AStatement.Children[0].Name;
    end;
  end
  else
  begin
    for mIndex := 0 to AStatement.ChildCount - 1 do
    begin
      if AStatement.Children[mIndex].Kind <> TSyntaxKind.TypeReference then
      begin
        mNode.FDefines := AStatement.Name;
      end;
    end;
  end;
  Result := [mNode];
end;

function TFlowBuilder.Statement(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
begin
  case AStatement.Kind of
    TSyntaxKind.Block:
      Result := Sequence(AStatement, 0, APreds);
    TSyntaxKind.IfStatement:
      Result := BuildIf(AStatement, APreds);
    TSyntaxKind.CaseStatement:
      Result := BuildCase(AStatement, APreds);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement:
      Result := BuildLoop(AStatement, APreds);
    TSyntaxKind.RepeatStatement:
      Result := BuildRepeat(AStatement, APreds);
    TSyntaxKind.WithStatement, TSyntaxKind.LabeledStatement:
      Result := BuildPrefixed(AStatement, APreds);
    TSyntaxKind.TryStatement:
      Result := BuildTry(AStatement, APreds);
    TSyntaxKind.CallStatement:
      Result := BuildCall(AStatement, APreds);
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
      Result := BuildJump(AStatement, APreds);
    TSyntaxKind.AssignStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      Result := BuildDefinition(AStatement, APreds);
    TSyntaxKind.AsmBlock, TSyntaxKind.Error:
      begin
        FGraph.FComplete := False;
        Result := [Simple(AStatement, APreds)];
      end;
  else
    Result := [Simple(AStatement, APreds)];
  end;
end;

function TFlowBuilder.BuildIf(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mCondition: TFlowNode;
  mIndex, mBranches: Integer;
begin
  mCondition := NewNode(TFlowNodeKind.Condition, AStatement);
  LinkAll(APreds, mCondition);
  Result := nil;
  mBranches := 0;
  for mIndex := 0 to AStatement.ChildCount - 1 do
  begin
    if TFlowStatements.IsStatement(AStatement.Children[mIndex].Kind) then
    begin
      Result := Concat(Result, Statement(AStatement.Children[mIndex], [mCondition]));
      Inc(mBranches);
    end;
  end;
  if mBranches < 2 then
  begin
    Result := Concat(Result, [mCondition]);
  end;
end;

function TFlowBuilder.BuildCase(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mCondition: TFlowNode;
  mIndex: Integer;
  mHasElse: Boolean;
begin
  mCondition := NewNode(TFlowNodeKind.Condition, AStatement);
  LinkAll(APreds, mCondition);
  Result := nil;
  mHasElse := False;
  for mIndex := 0 to AStatement.ChildCount - 1 do
  begin
    if AStatement.Children[mIndex].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
    begin
      mHasElse := mHasElse or (AStatement.Children[mIndex].Kind = TSyntaxKind.CaseElse);
      Result := Concat(Result, Sequence(AStatement.Children[mIndex], 0, [mCondition]));
    end;
  end;
  if not mHasElse then
  begin
    Result := Concat(Result, [mCondition]);
  end;
end;

function TFlowBuilder.BuildLoop(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mInit, mCondition: TFlowNode;
  mLoop: TLoopContext;
  mBody, mEntry: TArray<TFlowNode>;
begin
  mBody := APreds;
  // for und for-in weisen der Schleifenvariablen vor dem ersten Durchlauf zu.
  if AStatement.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
  begin
    mInit := Simple(AStatement, APreds);
    mInit.FDefines := AStatement.Name;
    mBody := [mInit];
  end;
  mCondition := NewNode(TFlowNodeKind.Condition, AStatement);
  mEntry := [mCondition];
  if TFlowStatements.RunsAtLeastOnce(AStatement) then
  begin
    // Läuft die Schleife sicher einmal, geht der erste Durchlauf an der Prüfung vorbei in den Rumpf.
    mEntry := Concat(mBody, mEntry);
    mBody := nil;
  end;
  LinkAll(mBody, mCondition);
  mLoop.BreakTarget := NewTarget;
  mLoop.ContinueTarget := NewTarget;
  FLoops.Add(mLoop);
  mBody := Sequence(AStatement, 0, mEntry);
  FLoops.Delete(FLoops.Count - 1);
  LinkAll(mBody, mCondition);
  Resolve(mLoop.ContinueTarget, mCondition);
  if (AStatement.Kind = TSyntaxKind.WhileStatement) and TFlowStatements.ConstantCondition(AStatement, 'True') then
  begin
    Result := mLoop.BreakTarget.Sources.ToArray;
  end
  else
  begin
    Result := Concat([mCondition], mLoop.BreakTarget.Sources.ToArray);
  end;
end;

function TFlowBuilder.BuildRepeat(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mHead, mCondition: TFlowNode;
  mLoop: TLoopContext;
  mBody: TArray<TFlowNode>;
begin
  mHead := NewNode(TFlowNodeKind.Join, nil);
  LinkAll(APreds, mHead);
  mLoop.BreakTarget := NewTarget;
  mLoop.ContinueTarget := NewTarget;
  FLoops.Add(mLoop);
  mBody := Sequence(AStatement, 0, [mHead]);
  FLoops.Delete(FLoops.Count - 1);
  mCondition := NewNode(TFlowNodeKind.Condition, AStatement);
  LinkAll(mBody, mCondition);
  Resolve(mLoop.ContinueTarget, mCondition);
  Link(mCondition, mHead);
  if TFlowStatements.ConstantCondition(AStatement, 'False') then
  begin
    Result := mLoop.BreakTarget.Sources.ToArray;
  end
  else
  begin
    Result := Concat([mCondition], mLoop.BreakTarget.Sources.ToArray);
  end;
end;

procedure TFlowBuilder.FinallyCopies(AContext: TFinallyContext; AFinallyPart: TSyntaxNode);
var
  mEntry, mNode: TFlowNode;
  mIndex: Integer;
  mPass: Boolean;
  mOnward: TJumpTarget;
begin
  // Die Wege für Ausnahmen kommen zuletzt, damit NodeOf eine Anweisung im finally zuerst auf dem normalen Weg
  // findet.
  for mPass := False to True do
  begin
    for mIndex := 0 to AContext.Onward.Count - 1 do
    begin
      mOnward := AContext.Onward[mIndex];
      if FRaiseTargets.Contains(mOnward) <> mPass then
      begin
        Continue;
      end;
      mEntry := NewNode(TFlowNodeKind.Join, nil);
      mEntry.FRaiseEntry := mPass;
      Resolve(AContext.Routes[mIndex], mEntry);
      for mNode in Sequence(AFinallyPart, 0, [mEntry]) do
      begin
        Jump(mNode, mOnward);
      end;
    end;
  end;
end;

function TFlowBuilder.BuildTryFinally(AStatement, AFinallyPart: TSyntaxNode;
  const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mContext: TFinallyContext;
  mEntry: TFlowNode;
  mBody: TArray<TFlowNode>;
begin
  mContext := TFinallyContext.Create;
  FFinallies.Add(mContext);
  try
    // Ausnahmen im try-Teil verlassen den Bereich nach außen, also durch finally.
    Inc(FTryDepth);
    mBody := Sequence(AStatement, 0, APreds);
    Dec(FTryDepth);
    FFinallies.Delete(FFinallies.Count - 1);
    // Normales Ende des try-Teils: weiter hinter dem try.
    Result := nil;
    if Length(mBody) > 0 then
    begin
      mEntry := NewNode(TFlowNodeKind.Join, nil);
      LinkAll(mBody, mEntry);
      Result := Sequence(AFinallyPart, 0, [mEntry]);
    end;
    FinallyCopies(mContext, AFinallyPart);
  finally
    mContext.Free;
  end;
end;

function TFlowBuilder.BuildTryExcept(AStatement, AExceptPart: TSyntaxNode;
  const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mHandlers: TJumpTarget;
  mHandler: TFlowNode;
  mChild: TSyntaxNode;
  mIndex: Integer;
  mHasHandlers, mHasElse: Boolean;
begin
  mHandlers := NewTarget;
  FRaiseTargets.Add(mHandlers);
  Inc(FTryDepth);
  Result := Sequence(AStatement, 0, APreds);
  Dec(FTryDepth);
  FRaiseTargets.Delete(FRaiseTargets.Count - 1);
  mHandler := NewNode(TFlowNodeKind.Join, nil);
  mHandler.FRaiseEntry := True;
  Resolve(mHandlers, mHandler);
  mHasHandlers := False;
  mHasElse := False;
  for mIndex := 0 to AExceptPart.ChildCount - 1 do
  begin
    mChild := AExceptPart.Children[mIndex];
    if mChild.Kind = TSyntaxKind.ExceptionHandler then
    begin
      mHasHandlers := True;
      Result := Concat(Result, Sequence(mChild, 0, [mHandler]));
    end
    else if TFlowStatements.IsStatement(mChild.Kind) then
    begin
      mHasElse := True;
    end;
  end;
  if mHasElse or not mHasHandlers then
  begin
    Result := Concat(Result, Sequence(AExceptPart, 0, [mHandler]));
  end
  else
  begin
    // Nicht behandelte Ausnahmen laufen weiter nach außen.
    Jump(mHandler, FRaiseTargets.Last);
  end;
end;

function TFlowBuilder.BuildTry(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mExceptPart, mFinallyPart: TSyntaxNode;
begin
  mExceptPart := AStatement.FindChild(TSyntaxKind.ExceptBlock);
  mFinallyPart := AStatement.FindChild(TSyntaxKind.FinallyBlock);
  if mFinallyPart <> nil then
  begin
    Result := BuildTryFinally(AStatement, mFinallyPart, APreds);
  end
  else if mExceptPart <> nil then
  begin
    Result := BuildTryExcept(AStatement, mExceptPart, APreds);
  end
  else
  begin
    Result := Sequence(AStatement, 0, APreds);
  end;
end;

function IsPlainCall(AStatement: TSyntaxNode): Boolean;
var
  mTarget: TSyntaxNode;
begin
  // Ohne Kinder ist es der Name allein ("Exit;").
  if AStatement.ChildCount = 0 then
  begin
    Exit(True);
  end;
  mTarget := AStatement.Children[0];
  if (mTarget.Kind = TSyntaxKind.Call) and (mTarget.ChildCount > 0) then
  begin
    mTarget := mTarget.Children[0];
  end;
  Result := mTarget.Kind = TSyntaxKind.Identifier;
end;

function TFlowBuilder.BuildCall(AStatement: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
  mName: string;
begin
  mNode := Simple(AStatement, APreds);
  // Der Parser nennt TMonitor.Exit(FLock) "Exit"; nur einfache Namen sind Exit, Break, Abort usw. (#647).
  mName := '';
  if IsPlainCall(AStatement) then
  begin
    mName := LowerCase(AStatement.Name);
  end;
  if mName = 'exit' then
  begin
    // Exit(Wert) setzt Result.
    if (AStatement.ChildCount > 0) and (AStatement.Children[0].Kind = TSyntaxKind.Call) and
      (AStatement.Children[0].ChildCount > 1) then
    begin
      mNode.FDefines := 'Result';
    end;
    Jump(mNode, FExitTarget);
    Result := nil;
  end
  else if (mName = 'break') and (FLoops.Count > 0) then
  begin
    Jump(mNode, FLoops.Last.BreakTarget);
    Result := nil;
  end
  else if (mName = 'continue') and (FLoops.Count > 0) then
  begin
    Jump(mNode, FLoops.Last.ContinueTarget);
    Result := nil;
  end
  else if mName = 'abort' then
  begin
    Jump(mNode, FRaiseTargets.Last);
    Result := nil;
  end
  else if mName = 'halt' then
  begin
    // Halt beendet das Programm; finally-Blöcke laufen nicht.
    Link(mNode, FGraph.FExit);
    Result := nil;
  end
  else
  begin
    Result := [mNode];
  end;
end;

type
  /// <summary>Schritt in TFlowBuilder.Analyze: Namen in Node lesen oder, bei Node = nil, Name berühren.</summary>
  TAnalyzeStep = record
    Node: TSyntaxNode;
    ChainParts: Boolean;
    Name: string;
    MaybeRead: Boolean;
  end;

function VisitStep(ANode: TSyntaxNode; AChainParts: Boolean): TAnalyzeStep;
begin
  Result := Default(TAnalyzeStep);
  Result.Node := ANode;
  Result.ChainParts := AChainParts;
end;

function TouchStep(const AName: string; AMaybeRead: Boolean): TAnalyzeStep;
begin
  Result := Default(TAnalyzeStep);
  Result.Name := AName;
  Result.MaybeRead := AMaybeRead;
end;

type
  /// <summary>Liest, berührt und übergibt Namen in der Anweisung eines Knotens (TFlowBuilder.Analyze).</summary>
  TFlowAnalyzer = class
  private
    FNode: TFlowNode;
    FLookup: TFlowSignatureLookup;
    FPending: TStack<TAnalyzeStep>;
    FSteps: TList<TAnalyzeStep>;
    procedure Touch(const AName: string; AMaybeRead: Boolean);
    /// <summary>Jede Erwähnung in einer anonymen Methode: Sie kann die Variable später ändern.</summary>
    procedure Captured(AExpression: TSyntaxNode);
    procedure AddArgument(ACall: TSyntaxNode; AIndex: Integer);
    procedure AddChildren(AExpression: TSyntaxNode; AFirst: Integer);
    /// <summary>Kette wie X[I].Feld: die Teile außer dem Bezeichner am Anfang (die Indizes werden gelesen).</summary>
    procedure AddChainParts(AExpression: TSyntaxNode);
    procedure AddAddressOf(AExpression: TSyntaxNode);
    procedure AddCall(AExpression: TSyntaxNode);
    procedure AddNode(AExpression: TSyntaxNode);
    /// <summary>Liest die Namen in ARoot; mit AChainParts nur die Teile einer Kette.</summary>
    procedure Visit(ARoot: TSyntaxNode; AChainParts: Boolean);
    /// <summary>Ziel einer Zuweisung: X := … setzt X (Defines); X.Feld := … und X[I] := … ändern nur einen Teil.
    /// </summary>
    procedure VisitTarget(ATarget: TSyntaxNode);
  public
    constructor Create(ANode: TFlowNode; const ALookup: TFlowSignatureLookup);
    destructor Destroy; override;
    procedure Run;
  end;

constructor TFlowAnalyzer.Create(ANode: TFlowNode; const ALookup: TFlowSignatureLookup);
begin
  inherited Create;
  FNode := ANode;
  FLookup := ALookup;
  FPending := TStack<TAnalyzeStep>.Create;
  FSteps := TList<TAnalyzeStep>.Create;
end;

destructor TFlowAnalyzer.Destroy;
begin
  FSteps.Free;
  FPending.Free;
  inherited;
end;

procedure TFlowAnalyzer.Touch(const AName: string; AMaybeRead: Boolean);
begin
  AddName(FNode.FTouches, AName);
  if AMaybeRead then
  begin
    AddName(FNode.FMaybeReads, AName);
  end;
end;

procedure TFlowAnalyzer.Captured(AExpression: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ mit eigenem Stapel (Bericht M1), Reihenfolge wie die frühere Rekursion.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AExpression);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.Identifier then
      begin
        Touch(mNode.Name, True);
      end;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode.Children[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

procedure TFlowAnalyzer.AddArgument(ACall: TSyntaxNode; AIndex: Integer);
var
  mArg: TSyntaxNode;
  mRoot: string;
  mMode: TFlowArgumentMode;
begin
  mArg := ACall.Children[AIndex];
  mRoot := RootName(mArg);
  // Nur eine Variable oder ein Teil davon kann als var/out übergeben werden.
  mMode := TFlowArgumentMode.Value;
  if (mRoot <> '') and not ThroughPointer(mArg) then
  begin
    mMode := TFlowArgumentMode.Unknown;
    if Assigned(FLookup) then
    begin
      mMode := FLookup(ACall, AIndex - 1);
    end;
  end;
  case mMode of
    TFlowArgumentMode.Value:
      FSteps.Add(VisitStep(mArg, False));
    TFlowArgumentMode.Output:
      begin
        FSteps.Add(TouchStep(mRoot, False));
        FSteps.Add(VisitStep(mArg, True));
      end;
  else
    begin
      // var oder unbekannt: kann lesen und schreiben.
      FSteps.Add(TouchStep(mRoot, True));
      FSteps.Add(VisitStep(mArg, True));
    end;
  end;
end;

procedure TFlowAnalyzer.AddChildren(AExpression: TSyntaxNode; AFirst: Integer);
var
  mIndex: Integer;
begin
  for mIndex := AFirst to AExpression.ChildCount - 1 do
  begin
    FSteps.Add(VisitStep(AExpression.Children[mIndex], False));
  end;
end;

procedure TFlowAnalyzer.AddChainParts(AExpression: TSyntaxNode);
var
  mPart: TSyntaxNode;
begin
  mPart := AExpression;
  while (mPart <> nil) and (mPart.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (mPart.ChildCount > 0) do
  begin
    AddChildren(mPart, 1);
    mPart := mPart.Children[0];
  end;
end;

procedure TFlowAnalyzer.AddAddressOf(AExpression: TSyntaxNode);
var
  mRoot: string;
begin
  mRoot := '';
  if AExpression.ChildCount > 0 then
  begin
    mRoot := RootName(AExpression.Children[0]);
  end;
  if (mRoot <> '') and not ThroughPointer(AExpression.Children[0]) then
  begin
    Touch(mRoot, False);
    FSteps.Add(VisitStep(AExpression.Children[0], True));
  end
  else
  begin
    AddChildren(AExpression, 0);
  end;
end;

procedure TFlowAnalyzer.AddCall(AExpression: TSyntaxNode);
var
  mIndex: Integer;
begin
  if AExpression.ChildCount = 0 then
  begin
    Exit;
  end;
  FSteps.Add(VisitStep(AExpression.Children[0], False));
  // Methode auf einer Variablen (X.Clear, R.Init(…)) kann deren Teile ändern.
  if (AExpression.Children[0].Kind = TSyntaxKind.MemberAccess) and not ThroughPointer(AExpression.Children[0]) then
  begin
    FSteps.Add(TouchStep(RootName(AExpression.Children[0]), True));
  end;
  for mIndex := 1 to AExpression.ChildCount - 1 do
  begin
    AddArgument(AExpression, mIndex);
  end;
end;

procedure TFlowAnalyzer.AddNode(AExpression: TSyntaxNode);
begin
  case AExpression.Kind of
    TSyntaxKind.Identifier:
      AddName(FNode.FReads, AExpression.Name);
    TSyntaxKind.TypeReference, TSyntaxKind.GenericArgs, TSyntaxKind.Literal:
      ;
    TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl:
      Captured(AExpression);
    TSyntaxKind.AddressOf:
      AddAddressOf(AExpression);
    TSyntaxKind.Call:
      AddCall(AExpression);
  else
    AddChildren(AExpression, 0);
  end;
end;

procedure TFlowAnalyzer.Visit(ARoot: TSyntaxNode; AChainParts: Boolean);
var
  mStep: TAnalyzeStep;
  mIndex: Integer;
begin
  // Iterativ mit eigenem Stapel (Bericht M1): Ausdrücke wie 1 - 1 - … - 1 sind so tief wie lang. Jeder Knoten
  // legt seine Folgeschritte in FSteps ab; sie kommen rückwärts auf den Stapel, damit Lesen und Berühren in
  // derselben Reihenfolge geschehen wie in der früheren Rekursion.
  FPending.Clear;
  FPending.Push(VisitStep(ARoot, AChainParts));
  while FPending.Count > 0 do
  begin
    mStep := FPending.Pop;
    FSteps.Clear;
    if mStep.Node = nil then
    begin
      Touch(mStep.Name, mStep.MaybeRead);
    end
    else if mStep.ChainParts then
    begin
      AddChainParts(mStep.Node);
    end
    else
    begin
      AddNode(mStep.Node);
    end;
    for mIndex := FSteps.Count - 1 downto 0 do
    begin
      FPending.Push(FSteps[mIndex]);
    end;
  end;
end;

procedure TFlowAnalyzer.VisitTarget(ATarget: TSyntaxNode);
begin
  if ATarget.Kind = TSyntaxKind.Identifier then
  begin
    Exit;
  end;
  if (RootName(ATarget) <> '') and not ThroughPointer(ATarget) then
  begin
    Touch(RootName(ATarget), True);
    Visit(ATarget, True);
  end
  else
  begin
    Visit(ATarget, False);
  end;
end;

/// <summary>Teil einer Anweisung, den eigene Knoten auswerten (Anweisungen, case-Zweige, except, finally).</summary>
function IsNestedPart(AChild: TSyntaxNode): Boolean;
begin
  Result := TFlowStatements.IsStatement(AChild.Kind) or (AChild.Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse,
    TSyntaxKind.ExceptBlock, TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock]);
end;

/// <summary>X.Methode; ohne Klammern und with X do …: Teile von X können sich ändern.</summary>
function ChangesReceiver(AStatement, AChild: TSyntaxNode): Boolean;
begin
  Result := (AStatement.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.WithStatement]) and
    (AChild.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Identifier, TSyntaxKind.IndexAccess]) and
    ((AStatement.Kind = TSyntaxKind.WithStatement) or (AChild.Kind = TSyntaxKind.MemberAccess)) and
    not ThroughPointer(AChild);
end;

procedure TFlowAnalyzer.Run;
var
  mStatement, mChild: TSyntaxNode;
  mIndex: Integer;
  mAllChildren: Boolean;
begin
  mStatement := FNode.Syntax;
  if (mStatement = nil) or
    (mStatement.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.GotoStatement, TSyntaxKind.EmptyStatement]) then
  begin
    Exit;
  end;
  mAllChildren := (FNode.Kind = TFlowNodeKind.Statement) and (mStatement.Kind in [TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
    TSyntaxKind.Error]);
  for mIndex := 0 to mStatement.ChildCount - 1 do
  begin
    mChild := mStatement.Children[mIndex];
    if not mAllChildren and IsNestedPart(mChild) then
    begin
      Continue;
    end;
    if (mIndex = 0) and (mStatement.Kind = TSyntaxKind.AssignStatement) then
    begin
      VisitTarget(mChild);
      Continue;
    end;
    Visit(mChild, False);
    if ChangesReceiver(mStatement, mChild) then
    begin
      Touch(RootName(mChild), True);
    end;
  end;
end;

procedure TFlowBuilder.Analyze(ANode: TFlowNode);
var
  mAnalyzer: TFlowAnalyzer;
begin
  mAnalyzer := TFlowAnalyzer.Create(ANode, FLookup);
  try
    mAnalyzer.Run;
  finally
    mAnalyzer.Free;
  end;
end;

procedure TFlowBuilder.Run(ARoutine: TSyntaxNode);
var
  mBody: TSyntaxNode;
  mIndex: Integer;
  mEnds: TArray<TFlowNode>;
  mNode: TFlowNode;
begin
  FGraph.FEntry := NewNode(TFlowNodeKind.Entry, nil);
  FGraph.FExit := NewNode(TFlowNodeKind.Exit, nil);
  FGraph.FRaiseExit := NewNode(TFlowNodeKind.RaiseExit, nil);
  FExitTarget := NewTarget;
  FRaiseTarget := NewTarget;
  FRaiseTargets.Add(FRaiseTarget);
  mBody := nil;
  if ARoutine.Kind = TSyntaxKind.Block then
  begin
    mBody := ARoutine;
  end
  else
  begin
    for mIndex := ARoutine.ChildCount - 1 downto 0 do
    begin
      if ARoutine.Children[mIndex].Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
      begin
        mBody := ARoutine.Children[mIndex];
        Break;
      end;
    end;
  end;
  if mBody = nil then
  begin
    FGraph.FComplete := False;
    Link(FGraph.FEntry, FGraph.FExit);
    Exit;
  end;
  // Syntaxfehler irgendwo in der Routine, auch mitten in einem Ausdruck: keine Aussage.
  if ContainsError(mBody) then
  begin
    FGraph.FComplete := False;
  end;
  mEnds := Statement(mBody, [FGraph.FEntry]);
  FGraph.FFallThrough := mEnds;
  LinkAll(mEnds, FGraph.FExit);
  Resolve(FExitTarget, FGraph.FExit);
  Resolve(FRaiseTarget, FGraph.FRaiseExit);
  for mNode in FGraph.FNodes do
  begin
    Analyze(mNode);
  end;
end;

{ TControlFlowGraph }

constructor TControlFlowGraph.Create;
begin
  inherited Create;
  FNodes := TObjectList<TFlowNode>.Create;
  FComplete := True;
end;

destructor TControlFlowGraph.Destroy;
begin
  FNodes.Free;
  inherited;
end;

class function TControlFlowGraph.Build(ARoutine: TSyntaxNode): TControlFlowGraph;
begin
  Result := Build(ARoutine, nil);
end;

class function TControlFlowGraph.Build(ARoutine: TSyntaxNode; const ALookup: TFlowSignatureLookup):
  TControlFlowGraph;
var
  mBuilder: TFlowBuilder;
  mLookup: TFlowSignatureLookup;
  mRoot: TSyntaxNode;
begin
  mLookup := ALookup;
  if not Assigned(mLookup) then
  begin
    mRoot := ARoutine;
    while mRoot.Parent <> nil do
    begin
      mRoot := mRoot.Parent;
    end;
    mLookup := TFlowSignatures.FromTree(mRoot);
  end;
  Result := TControlFlowGraph.Create;
  mBuilder := TFlowBuilder.Create(Result, mLookup);
  try
    mBuilder.Run(ARoutine);
  finally
    mBuilder.Free;
  end;
end;

function TControlFlowGraph.NodeOf(ASyntax: TSyntaxNode): TFlowNode;
var
  mNode: TFlowNode;
begin
  // Bei Schleifen gibt es Start- und Bedingungsknoten; der erste zählt.
  for mNode in FNodes do
  begin
    if mNode.Syntax = ASyntax then
    begin
      Exit(mNode);
    end;
  end;
  Result := nil;
end;

function TControlFlowGraph.IsReachable(ANode: TFlowNode): TFlowAnswer;
var
  mSeen: TArray<Boolean>;
  mStack: TStack<TFlowNode>;
  mNode, mNext: TFlowNode;
begin
  SetLength(mSeen, FNodes.Count);
  mStack := TStack<TFlowNode>.Create;
  try
    mStack.Push(FEntry);
    mSeen[FEntry.Index] := True;
    while mStack.Count > 0 do
    begin
      mNode := mStack.Pop;
      if mNode = ANode then
      begin
        Exit(TFlowAnswer.Yes);
      end;
      for mNext in mNode.Successors do
      begin
        if not mSeen[mNext.Index] then
        begin
          mSeen[mNext.Index] := True;
          mStack.Push(mNext);
        end;
      end;
    end;
  finally
    mStack.Free;
  end;
  if FComplete then
  begin
    Result := TFlowAnswer.No;
  end
  else
  begin
    Result := TFlowAnswer.Unknown;
  end;
end;

/// <summary>Schnitt der Spalte AColumn über alle erreichbaren Vorgänger von ANode; False ohne.</summary>
function IntersectPredecessors(ANode: TFlowNode; AColumn: Integer; const AReachable: TArray<Boolean>;
  const ADominators: TArray<TArray<Boolean>>): Boolean;
var
  mPred: TFlowNode;
  mFirst: Boolean;
begin
  Result := False;
  mFirst := True;
  for mPred in ANode.Predecessors do
  begin
    if not AReachable[mPred.Index] then
    begin
      Continue;
    end;
    if mFirst then
    begin
      Result := ADominators[mPred.Index][AColumn];
    end
    else
    begin
      Result := Result and ADominators[mPred.Index][AColumn];
    end;
    mFirst := False;
  end;
end;

function TControlFlowGraph.UpdateDominators(const AReachable: TArray<Boolean>): Boolean;
var
  mNode: TFlowNode;
  mColumn: Integer;
  mValue: Boolean;
begin
  Result := False;
  for mNode in FNodes do
  begin
    if mNode = FEntry then
    begin
      Continue;
    end;
    for mColumn := 0 to FNodes.Count - 1 do
    begin
      // Schnitt über alle Vorgänger, dazu der Knoten selbst.
      mValue := (mColumn = mNode.Index) or IntersectPredecessors(mNode, mColumn, AReachable, FDominators);
      if mValue <> FDominators[mNode.Index][mColumn] then
      begin
        FDominators[mNode.Index][mColumn] := mValue;
        Result := True;
      end;
    end;
  end;
end;

procedure TControlFlowGraph.ComputeDominators;
var
  mCount, mRow, mColumn: Integer;
  mNode: TFlowNode;
  mReachable: TArray<Boolean>;
  mChanged: Boolean;
begin
  if FDominators <> nil then
  begin
    Exit;
  end;
  mCount := FNodes.Count;
  // Unerreichbare Vorgänger (Code nach Exit) zählen nicht; sonst dominierte
  // nichts mehr den gemeinsamen Nachfolger.
  SetLength(mReachable, mCount);
  for mNode in FNodes do
  begin
    mReachable[mNode.Index] := IsReachable(mNode) = TFlowAnswer.Yes;
  end;
  SetLength(FDominators, mCount);
  for mRow := 0 to mCount - 1 do
  begin
    SetLength(FDominators[mRow], mCount);
    for mColumn := 0 to mCount - 1 do
    begin
      FDominators[mRow][mColumn] := mRow <> FEntry.Index;
    end;
  end;
  FDominators[FEntry.Index][FEntry.Index] := True;
  mChanged := True;
  while mChanged do
  begin
    mChanged := UpdateDominators(mReachable);
  end;
end;

function TControlFlowGraph.Dominates(A, B: TFlowNode): TFlowAnswer;
begin
  if not FComplete then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  if IsReachable(B) <> TFlowAnswer.Yes then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  ComputeDominators;
  if FDominators[B.Index][A.Index] then
  begin
    Result := TFlowAnswer.Yes;
  end
  else
  begin
    Result := TFlowAnswer.No;
  end;
end;

function TControlFlowGraph.HasReachableCopy(ANode: TFlowNode): Boolean;
var
  mOther: TFlowNode;
begin
  for mOther in FNodes do
  begin
    if (mOther <> ANode) and (mOther.Syntax = ANode.Syntax) and (IsReachable(mOther) = TFlowAnswer.Yes) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Steht die Anweisung von ANode schon in ANodes?</summary>
function ListsSyntax(const ANodes: TArray<TFlowNode>; ANode: TFlowNode): Boolean;
var
  mSeen: TFlowNode;
begin
  for mSeen in ANodes do
  begin
    if mSeen.Syntax = ANode.Syntax then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TControlFlowGraph.UnreachableStatements: TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  Result := nil;
  if not FComplete then
  begin
    Exit;
  end;
  // Ein finally steht je Ausgang einmal im Graphen; unerreichbar ist es nur, wenn keine seiner Kopien erreichbar
  // ist. Gemeldet wird es einmal.
  for mNode in FNodes do
  begin
    if (mNode.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) and
      (IsReachable(mNode) = TFlowAnswer.No) and not HasReachableCopy(mNode) and not ListsSyntax(Result, mNode) then
    begin
      Result := Result + [mNode];
    end;
  end;
end;

function TControlFlowGraph.ReachingDefinitions(ANode: TFlowNode; const AName: string): TReachingDefinitions;
var
  // Zustand je Knoten: 0 = Weg ohne, 1 = Weg mit unsicherer Änderung dahinter.
  mSeen: array[Boolean] of TArray<Boolean>;
  mStack: TStack<Integer>;
  mNode: TFlowNode;
  mItem: Integer;
  mTouched: Boolean;

  procedure Push(APred: TFlowNode; ATouched: Boolean);
  begin
    if not mSeen[ATouched][APred.Index] then
    begin
      mSeen[ATouched][APred.Index] := True;
      mStack.Push(APred.Index * 2 + Ord(ATouched));
    end;
  end;

  procedure AddUnique(var ANodes: TArray<TFlowNode>; ANew: TFlowNode);
  var
    mExisting: TFlowNode;
  begin
    for mExisting in ANodes do
    begin
      if mExisting = ANew then
      begin
        Exit;
      end;
    end;
    ANodes := ANodes + [ANew];
  end;

  // Vorgänger von ANext. Über die Ausnahmekante einer Zuweisung an AName (X := F im try) ist der Wert nie
  // gespeichert worden: Die Ausnahme fliegt beim Rechnen der rechten Seite, es gilt der Wert davor (#1109).
  procedure PushPredecessors(ANext: TFlowNode; ATouched: Boolean);
  var
    mBefore, mEarlier: TFlowNode;
  begin
    for mBefore in ANext.Predecessors do
    begin
      if mBefore.IsImplicitRaiseEdge(ANext) and SameText(mBefore.Defines, AName) then
      begin
        for mEarlier in mBefore.Predecessors do
        begin
          Push(mEarlier, ATouched);
        end;
      end
      else
      begin
        Push(mBefore, ATouched);
      end;
    end;
  end;

begin
  Result.Definitions := nil;
  Result.FromEntry := False;
  Result.MaybeFromEntry := False;
  Result.Uncertain := nil;
  SetLength(mSeen[False], FNodes.Count);
  SetLength(mSeen[True], FNodes.Count);
  mStack := TStack<Integer>.Create;
  try
    PushPredecessors(ANode, False);
    while mStack.Count > 0 do
    begin
      mItem := mStack.Pop;
      mNode := FNodes[mItem div 2];
      mTouched := Odd(mItem);
      if SameText(mNode.Defines, AName) then
      begin
        AddUnique(Result.Definitions, mNode);
        Continue;
      end;
      if mNode = FEntry then
      begin
        if mTouched then
        begin
          Result.MaybeFromEntry := True;
        end
        else
        begin
          Result.FromEntry := True;
        end;
      end;
      if mNode.TouchesName(AName) then
      begin
        AddUnique(Result.Uncertain, mNode);
        mTouched := True;
      end;
      PushPredecessors(mNode, mTouched);
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Yes über einen sicheren Weg, Unknown nur über unsichere Änderungen, sonst No.</summary>
function AnswerOf(const ADefinitions: TReachingDefinitions): TFlowAnswer;
begin
  if ADefinitions.FromEntry then
  begin
    Result := TFlowAnswer.Yes;
  end
  else if ADefinitions.MaybeFromEntry then
  begin
    Result := TFlowAnswer.Unknown;
  end
  else
  begin
    Result := TFlowAnswer.No;
  end;
end;

function TControlFlowGraph.MayEndWithout(const AName: string): TFlowAnswer;
begin
  if not FComplete then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  Result := AnswerOf(ReachingDefinitions(FExit, AName));
end;

function TControlFlowGraph.MayReadBeforeWrite(ANode: TFlowNode; const AName: string): TFlowAnswer;
begin
  if not FComplete then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  Result := AnswerOf(ReachingDefinitions(ANode, AName));
end;

function TControlFlowGraph.MayReadBeforeWrite(const AName: string): TFlowAnswer;
var
  mNode: TFlowNode;
  mAnswer: TFlowAnswer;
begin
  if not FComplete then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  Result := TFlowAnswer.No;
  for mNode in FNodes do
  begin
    if (mNode.ReadsName(AName) or mNode.MaybeReadsName(AName)) and (IsReachable(mNode) = TFlowAnswer.Yes) then
    begin
      mAnswer := AnswerOf(ReachingDefinitions(mNode, AName));
      // Ein Lesen, das nur vielleicht eines ist, ergibt höchstens Unknown.
      if (mAnswer = TFlowAnswer.Yes) and mNode.ReadsName(AName) then
      begin
        Exit(TFlowAnswer.Yes);
      end;
      if mAnswer <> TFlowAnswer.No then
      begin
        Result := TFlowAnswer.Unknown;
      end;
    end;
  end;
end;

end.
