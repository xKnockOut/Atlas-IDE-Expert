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
    /// <summary>Variablen, die der Knoten sicher liest.</summary>
    property Reads: TArray<string> read FReads;
    /// <summary>Variablen, die der Knoten vielleicht liest (var-Argument, unbekannte Signatur, Teilzuweisung).</summary>
    property MaybeReads: TArray<string> read FMaybeReads;
    /// <summary>Variablen, die der Knoten vielleicht ändert, ohne sie sicher zu setzen (#143).</summary>
    property Touches: TArray<string> read FTouches;
    function ReadsName(const AName: string): Boolean;
    function MaybeReadsName(const AName: string): Boolean;
    function TouchesName(const AName: string): Boolean;
    /// <summary>Anweisung in einem try: Sie kann eine Ausnahme auslösen, bevor sie wirkt (#915).</summary>
    property MayRaise: Boolean read FMayRaise;
    /// <summary>Eingang eines except-Teils bzw. der finally-Kopie für Ausnahmen (#915).</summary>
    property RaiseEntry: Boolean read FRaiseEntry;
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
    function Statement(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildIf(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCase(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildLoop(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildRepeat(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildTry(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildCall(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>with und Label: ein Knoten vor den enthaltenen Anweisungen.</summary>
    function BuildPrefixed(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>raise und goto: Der Weg geht nicht hinter der Anweisung weiter.</summary>
    function BuildJump(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>Zuweisung und Inline-Deklaration: setzt Defines.</summary>
    function BuildDefinition(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    function BuildTryFinally(S, AFinallyPart: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
    /// <summary>Je Sprungziel aus dem try-Teil eine Kopie des finally-Teils, die nur dorthin weiterführt.</summary>
    procedure FinallyCopies(AContext: TFinallyContext; AFinallyPart: TSyntaxNode);
    function BuildTryExcept(S, AExceptPart: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
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
  Name: string;
begin
  for Name in ANames do
  begin
    if SameText(Name, AName) then
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
  Node: TFlowNode;
begin
  Result := A;
  for Node in B do
  begin
    Result := Result + [Node];
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
  BuiltinSignatures: array[0..27] of TBuiltinSignature = (
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
  ValueRoutines: array[0..63] of string = ('Length', 'High', 'Low', 'SizeOf', 'Assigned', 'Ord', 'Chr', 'Succ',
    'Pred', 'Abs', 'Round', 'Trunc', 'Frac', 'Int', 'Odd', 'Sqr', 'Sqrt', 'Copy', 'Pos', 'Concat', 'IntToStr',
    'StrToInt', 'StrToIntDef', 'FloatToStr', 'Format', 'Trim', 'UpperCase', 'LowerCase', 'SameText',
    'CompareText', 'CompareStr', 'Write', 'WriteLn', 'ShowMessage', 'Assert', 'Halt', 'TypeInfo', 'Default',
    'IntToHex', 'QuotedStr', 'Max', 'Min', 'BoolToStr', 'FreeMem', 'Integer', 'Cardinal', 'Byte', 'Word',
    'Int64', 'UInt64', 'NativeInt', 'NativeUInt', 'Boolean', 'Char', 'AnsiChar', 'WideChar', 'string',
    'Pointer', 'Double', 'Single', 'Extended', 'Currency', 'LongInt', 'TObject');

class function TFlowSignatures.TryBuiltin(const AName: string; AArgument: Integer;
  out AMode: TFlowArgumentMode): Boolean;
var
  Signature: TBuiltinSignature;
  Code: Char;
  Name: string;
begin
  AMode := TFlowArgumentMode.Unknown;
  for Signature in BuiltinSignatures do
  begin
    if SameText(Signature.Name, AName) then
    begin
      if AArgument < Length(Signature.Modes) then
      begin
        Code := Signature.Modes[AArgument + 1];
      end
      else
      begin
        Code := Signature.Modes[Length(Signature.Modes)];
      end;
      case Code of
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
  for Name in ValueRoutines do
  begin
    if SameText(Name, AName) then
    begin
      AMode := TFlowArgumentMode.Value;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TFlowSignatures.FromTree(ARoot: TSyntaxNode): TFlowSignatureLookup;
var
  Table: IFlowRoutineTable;
begin
  Table := TFlowRoutineTable.Create(ARoot);
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
      if not Table.Find(Callee.Name, AArgument, Result) then
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
  Headers: TList<TSyntaxNode>;
  Header: TSyntaxNode;
begin
  // Iterativ (Bericht M1): erst die Köpfe sammeln, dann eintragen.
  Headers := TList<TSyntaxNode>.Create;
  try
    ANode.Walk(
      function(AVisited: TSyntaxNode): Boolean
      begin
        if AVisited.Kind = TSyntaxKind.RoutineHeader then
        begin
          Headers.Add(AVisited);
        end;
        Result := True;
      end);
    for Header in Headers do
    begin
      AddHeader(Header);
    end;
  finally
    Headers.Free;
  end;
end;

function TFlowRoutineTable.Find(const AName: string; AArgument: Integer; out AMode: TFlowArgumentMode): Boolean;
var
  Modes: TArray<TFlowArgumentMode>;
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
  Result := FRoutines.TryGetValue(LowerCase(AName), Modes);
  // Mehr Argumente als Parameter: andere Überladung oder offenes Array, also unbekannt.
  if Result and (AArgument >= 0) and (AArgument <= High(Modes)) then
  begin
    AMode := Modes[AArgument];
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
  Node: TFlowNode;
begin
  for Node in AFrom do
  begin
    Link(Node, ATo);
  end;
end;

procedure TFlowBuilder.Resolve(ATarget: TJumpTarget; ATo: TFlowNode);
begin
  LinkAll(ATarget.Sources.ToArray, ATo);
end;

procedure TFlowBuilder.Jump(AFrom: TFlowNode; ATarget: TJumpTarget);
var
  Context: TFinallyContext;
  Route: Integer;
begin
  // Verlässt der Sprung einen finally-Bereich, läuft er zuerst durch dessen finally.
  if FFinallies.Count > ATarget.Depth then
  begin
    Context := FFinallies[FFinallies.Count - 1];
    Route := Context.Onward.IndexOf(ATarget);
    if Route < 0 then
    begin
      Context.Onward.Add(ATarget);
      Route := Context.Routes.Add(TJumpTarget.Create(ATarget.Depth));
    end;
    Context.Routes[Route].Sources.Add(AFrom);
  end
  else
  begin
    ATarget.Sources.Add(AFrom);
  end;
end;

function TFlowBuilder.LabelNode(const AName: string): TFlowNode;
var
  Key: string;
begin
  Key := LowerCase(AName);
  if not FLabels.TryGetValue(Key, Result) then
  begin
    Result := NewNode(TFlowNodeKind.Join, nil);
    FLabels.Add(Key, Result);
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
  Index: Integer;
begin
  Result := APreds;
  for Index := AFirst to AParent.ChildCount - 1 do
  begin
    if TFlowStatements.IsStatement(AParent.Children[Index].Kind) then
    begin
      Result := Statement(AParent.Children[Index], Result);
    end;
  end;
end;

function TFlowBuilder.BuildPrefixed(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  if S.Kind = TSyntaxKind.LabeledStatement then
  begin
    mNode := LabelNode(S.Name);
    LinkAll(APreds, mNode);
  end
  else
  begin
    mNode := Simple(S, APreds);
  end;
  Result := Sequence(S, 0, [mNode]);
end;

function TFlowBuilder.BuildJump(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
begin
  mNode := Simple(S, APreds);
  if S.Kind = TSyntaxKind.RaiseStatement then
  begin
    Jump(mNode, FRaiseTargets.Last);
  end
  else
  begin
    Link(mNode, LabelNode(S.Name));
  end;
  Result := nil;
end;

function TFlowBuilder.BuildDefinition(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mNode: TFlowNode;
  mIndex: Integer;
begin
  mNode := Simple(S, APreds);
  if S.Kind = TSyntaxKind.AssignStatement then
  begin
    if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Identifier) then
    begin
      mNode.FDefines := S.Children[0].Name;
    end;
  end
  else
  begin
    for mIndex := 0 to S.ChildCount - 1 do
    begin
      if S.Children[mIndex].Kind <> TSyntaxKind.TypeReference then
      begin
        mNode.FDefines := S.Name;
      end;
    end;
  end;
  Result := [mNode];
end;

function TFlowBuilder.Statement(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
begin
  case S.Kind of
    TSyntaxKind.Block:
      Result := Sequence(S, 0, APreds);
    TSyntaxKind.IfStatement:
      Result := BuildIf(S, APreds);
    TSyntaxKind.CaseStatement:
      Result := BuildCase(S, APreds);
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement:
      Result := BuildLoop(S, APreds);
    TSyntaxKind.RepeatStatement:
      Result := BuildRepeat(S, APreds);
    TSyntaxKind.WithStatement, TSyntaxKind.LabeledStatement:
      Result := BuildPrefixed(S, APreds);
    TSyntaxKind.TryStatement:
      Result := BuildTry(S, APreds);
    TSyntaxKind.CallStatement:
      Result := BuildCall(S, APreds);
    TSyntaxKind.RaiseStatement, TSyntaxKind.GotoStatement:
      Result := BuildJump(S, APreds);
    TSyntaxKind.AssignStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      Result := BuildDefinition(S, APreds);
    TSyntaxKind.AsmBlock, TSyntaxKind.Error:
      begin
        FGraph.FComplete := False;
        Result := [Simple(S, APreds)];
      end;
  else
    Result := [Simple(S, APreds)];
  end;
end;

function TFlowBuilder.BuildIf(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Condition: TFlowNode;
  Index, Branches: Integer;
begin
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(APreds, Condition);
  Result := nil;
  Branches := 0;
  for Index := 0 to S.ChildCount - 1 do
  begin
    if TFlowStatements.IsStatement(S.Children[Index].Kind) then
    begin
      Result := Concat(Result, Statement(S.Children[Index], [Condition]));
      Inc(Branches);
    end;
  end;
  if Branches < 2 then
  begin
    Result := Concat(Result, [Condition]);
  end;
end;

function TFlowBuilder.BuildCase(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Condition: TFlowNode;
  Index: Integer;
  HasElse: Boolean;
begin
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(APreds, Condition);
  Result := nil;
  HasElse := False;
  for Index := 0 to S.ChildCount - 1 do
  begin
    if S.Children[Index].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
    begin
      HasElse := HasElse or (S.Children[Index].Kind = TSyntaxKind.CaseElse);
      Result := Concat(Result, Sequence(S.Children[Index], 0, [Condition]));
    end;
  end;
  if not HasElse then
  begin
    Result := Concat(Result, [Condition]);
  end;
end;

function TFlowBuilder.BuildLoop(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Init, Condition: TFlowNode;
  Loop: TLoopContext;
  Body, Entry: TArray<TFlowNode>;
begin
  Body := APreds;
  // for und for-in weisen der Schleifenvariablen vor dem ersten Durchlauf zu.
  if S.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement] then
  begin
    Init := Simple(S, APreds);
    Init.FDefines := S.Name;
    Body := [Init];
  end;
  Condition := NewNode(TFlowNodeKind.Condition, S);
  Entry := [Condition];
  if TFlowStatements.RunsAtLeastOnce(S) then
  begin
    // Läuft die Schleife sicher einmal, geht der erste Durchlauf an der Prüfung vorbei in den Rumpf.
    Entry := Concat(Body, Entry);
    Body := nil;
  end;
  LinkAll(Body, Condition);
  Loop.BreakTarget := NewTarget;
  Loop.ContinueTarget := NewTarget;
  FLoops.Add(Loop);
  Body := Sequence(S, 0, Entry);
  FLoops.Delete(FLoops.Count - 1);
  LinkAll(Body, Condition);
  Resolve(Loop.ContinueTarget, Condition);
  if (S.Kind = TSyntaxKind.WhileStatement) and TFlowStatements.ConstantCondition(S, 'True') then
  begin
    Result := Loop.BreakTarget.Sources.ToArray;
  end
  else
  begin
    Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
  end;
end;

function TFlowBuilder.BuildRepeat(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Head, Condition: TFlowNode;
  Loop: TLoopContext;
  Body: TArray<TFlowNode>;
begin
  Head := NewNode(TFlowNodeKind.Join, nil);
  LinkAll(APreds, Head);
  Loop.BreakTarget := NewTarget;
  Loop.ContinueTarget := NewTarget;
  FLoops.Add(Loop);
  Body := Sequence(S, 0, [Head]);
  FLoops.Delete(FLoops.Count - 1);
  Condition := NewNode(TFlowNodeKind.Condition, S);
  LinkAll(Body, Condition);
  Resolve(Loop.ContinueTarget, Condition);
  Link(Condition, Head);
  if TFlowStatements.ConstantCondition(S, 'False') then
  begin
    Result := Loop.BreakTarget.Sources.ToArray;
  end
  else
  begin
    Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
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

function TFlowBuilder.BuildTryFinally(S, AFinallyPart: TSyntaxNode;
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
    mBody := Sequence(S, 0, APreds);
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

function TFlowBuilder.BuildTryExcept(S, AExceptPart: TSyntaxNode;
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
  Result := Sequence(S, 0, APreds);
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

function TFlowBuilder.BuildTry(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  mExceptPart, mFinallyPart: TSyntaxNode;
begin
  mExceptPart := S.FindChild(TSyntaxKind.ExceptBlock);
  mFinallyPart := S.FindChild(TSyntaxKind.FinallyBlock);
  if mFinallyPart <> nil then
  begin
    Result := BuildTryFinally(S, mFinallyPart, APreds);
  end
  else if mExceptPart <> nil then
  begin
    Result := BuildTryExcept(S, mExceptPart, APreds);
  end
  else
  begin
    Result := Sequence(S, 0, APreds);
  end;
end;

function IsPlainCall(S: TSyntaxNode): Boolean;
var
  Target: TSyntaxNode;
begin
  // Ohne Kinder ist es der Name allein ("Exit;").
  if S.ChildCount = 0 then
  begin
    Exit(True);
  end;
  Target := S.Children[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
  begin
    Target := Target.Children[0];
  end;
  Result := Target.Kind = TSyntaxKind.Identifier;
end;

function TFlowBuilder.BuildCall(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
  Name: string;
begin
  Node := Simple(S, APreds);
  // Der Parser nennt TMonitor.Exit(FLock) "Exit"; nur einfache Namen sind Exit, Break, Abort usw. (#647).
  Name := '';
  if IsPlainCall(S) then
  begin
    Name := LowerCase(S.Name);
  end;
  if Name = 'exit' then
  begin
    // Exit(Wert) setzt Result.
    if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Call) and (S.Children[0].ChildCount > 1) then
    begin
      Node.FDefines := 'Result';
    end;
    Jump(Node, FExitTarget);
    Result := nil;
  end
  else if (Name = 'break') and (FLoops.Count > 0) then
  begin
    Jump(Node, FLoops.Last.BreakTarget);
    Result := nil;
  end
  else if (Name = 'continue') and (FLoops.Count > 0) then
  begin
    Jump(Node, FLoops.Last.ContinueTarget);
    Result := nil;
  end
  else if Name = 'abort' then
  begin
    Jump(Node, FRaiseTargets.Last);
    Result := nil;
  end
  else if Name = 'halt' then
  begin
    // Halt beendet das Programm; finally-Blöcke laufen nicht.
    Link(Node, FGraph.FExit);
    Result := nil;
  end
  else
  begin
    Result := [Node];
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
    procedure Captured(E: TSyntaxNode);
    procedure AddArgument(ACall: TSyntaxNode; AIndex: Integer);
    procedure AddChildren(E: TSyntaxNode; AFirst: Integer);
    /// <summary>Kette wie X[I].Feld: die Teile außer dem Bezeichner am Anfang (die Indizes werden gelesen).</summary>
    procedure AddChainParts(E: TSyntaxNode);
    procedure AddAddressOf(E: TSyntaxNode);
    procedure AddCall(E: TSyntaxNode);
    procedure AddNode(E: TSyntaxNode);
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

procedure TFlowAnalyzer.Captured(E: TSyntaxNode);
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  // Iterativ mit eigenem Stapel (Bericht M1), Reihenfolge wie die frühere Rekursion.
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(E);
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

procedure TFlowAnalyzer.AddChildren(E: TSyntaxNode; AFirst: Integer);
var
  mIndex: Integer;
begin
  for mIndex := AFirst to E.ChildCount - 1 do
  begin
    FSteps.Add(VisitStep(E.Children[mIndex], False));
  end;
end;

procedure TFlowAnalyzer.AddChainParts(E: TSyntaxNode);
var
  mPart: TSyntaxNode;
begin
  mPart := E;
  while (mPart <> nil) and (mPart.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (mPart.ChildCount > 0) do
  begin
    AddChildren(mPart, 1);
    mPart := mPart.Children[0];
  end;
end;

procedure TFlowAnalyzer.AddAddressOf(E: TSyntaxNode);
var
  mRoot: string;
begin
  mRoot := '';
  if E.ChildCount > 0 then
  begin
    mRoot := RootName(E.Children[0]);
  end;
  if (mRoot <> '') and not ThroughPointer(E.Children[0]) then
  begin
    Touch(mRoot, False);
    FSteps.Add(VisitStep(E.Children[0], True));
  end
  else
  begin
    AddChildren(E, 0);
  end;
end;

procedure TFlowAnalyzer.AddCall(E: TSyntaxNode);
var
  mIndex: Integer;
begin
  if E.ChildCount = 0 then
  begin
    Exit;
  end;
  FSteps.Add(VisitStep(E.Children[0], False));
  // Methode auf einer Variablen (X.Clear, R.Init(…)) kann deren Teile ändern.
  if (E.Children[0].Kind = TSyntaxKind.MemberAccess) and not ThroughPointer(E.Children[0]) then
  begin
    FSteps.Add(TouchStep(RootName(E.Children[0]), True));
  end;
  for mIndex := 1 to E.ChildCount - 1 do
  begin
    AddArgument(E, mIndex);
  end;
end;

procedure TFlowAnalyzer.AddNode(E: TSyntaxNode);
begin
  case E.Kind of
    TSyntaxKind.Identifier:
      AddName(FNode.FReads, E.Name);
    TSyntaxKind.TypeReference, TSyntaxKind.GenericArgs, TSyntaxKind.Literal:
      ;
    TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl:
      Captured(E);
    TSyntaxKind.AddressOf:
      AddAddressOf(E);
    TSyntaxKind.Call:
      AddCall(E);
  else
    AddChildren(E, 0);
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
function ChangesReceiver(S, AChild: TSyntaxNode): Boolean;
begin
  Result := (S.Kind in [TSyntaxKind.CallStatement, TSyntaxKind.WithStatement]) and
    (AChild.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Identifier, TSyntaxKind.IndexAccess]) and
    ((S.Kind = TSyntaxKind.WithStatement) or (AChild.Kind = TSyntaxKind.MemberAccess)) and
    not ThroughPointer(AChild);
end;

procedure TFlowAnalyzer.Run;
var
  S, mChild: TSyntaxNode;
  mIndex: Integer;
  mAllChildren: Boolean;
begin
  S := FNode.Syntax;
  if (S = nil) or (S.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.GotoStatement, TSyntaxKind.EmptyStatement]) then
  begin
    Exit;
  end;
  mAllChildren := (FNode.Kind = TFlowNodeKind.Statement) and (S.Kind in [TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
    TSyntaxKind.Error]);
  for mIndex := 0 to S.ChildCount - 1 do
  begin
    mChild := S.Children[mIndex];
    if not mAllChildren and IsNestedPart(mChild) then
    begin
      Continue;
    end;
    if (mIndex = 0) and (S.Kind = TSyntaxKind.AssignStatement) then
    begin
      VisitTarget(mChild);
      Continue;
    end;
    Visit(mChild, False);
    if ChangesReceiver(S, mChild) then
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
  Body: TSyntaxNode;
  Index: Integer;
  Ends: TArray<TFlowNode>;
  Node: TFlowNode;
begin
  FGraph.FEntry := NewNode(TFlowNodeKind.Entry, nil);
  FGraph.FExit := NewNode(TFlowNodeKind.Exit, nil);
  FGraph.FRaiseExit := NewNode(TFlowNodeKind.RaiseExit, nil);
  FExitTarget := NewTarget;
  FRaiseTarget := NewTarget;
  FRaiseTargets.Add(FRaiseTarget);
  Body := nil;
  if ARoutine.Kind = TSyntaxKind.Block then
  begin
    Body := ARoutine;
  end
  else
  begin
    for Index := ARoutine.ChildCount - 1 downto 0 do
    begin
      if ARoutine.Children[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
      begin
        Body := ARoutine.Children[Index];
        Break;
      end;
    end;
  end;
  if Body = nil then
  begin
    FGraph.FComplete := False;
    Link(FGraph.FEntry, FGraph.FExit);
    Exit;
  end;
  // Syntaxfehler irgendwo in der Routine, auch mitten in einem Ausdruck: keine Aussage.
  if ContainsError(Body) then
  begin
    FGraph.FComplete := False;
  end;
  Ends := Statement(Body, [FGraph.FEntry]);
  FGraph.FFallThrough := Ends;
  LinkAll(Ends, FGraph.FExit);
  Resolve(FExitTarget, FGraph.FExit);
  Resolve(FRaiseTarget, FGraph.FRaiseExit);
  for Node in FGraph.FNodes do
  begin
    Analyze(Node);
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
  Builder: TFlowBuilder;
  Lookup: TFlowSignatureLookup;
  Root: TSyntaxNode;
begin
  Lookup := ALookup;
  if not Assigned(Lookup) then
  begin
    Root := ARoutine;
    while Root.Parent <> nil do
    begin
      Root := Root.Parent;
    end;
    Lookup := TFlowSignatures.FromTree(Root);
  end;
  Result := TControlFlowGraph.Create;
  Builder := TFlowBuilder.Create(Result, Lookup);
  try
    Builder.Run(ARoutine);
  finally
    Builder.Free;
  end;
end;

function TControlFlowGraph.NodeOf(ASyntax: TSyntaxNode): TFlowNode;
var
  Node: TFlowNode;
begin
  // Bei Schleifen gibt es Start- und Bedingungsknoten; der erste zählt.
  for Node in FNodes do
  begin
    if Node.Syntax = ASyntax then
    begin
      Exit(Node);
    end;
  end;
  Result := nil;
end;

function TControlFlowGraph.IsReachable(ANode: TFlowNode): TFlowAnswer;
var
  Seen: TArray<Boolean>;
  Stack: TStack<TFlowNode>;
  Node, Next: TFlowNode;
begin
  SetLength(Seen, FNodes.Count);
  Stack := TStack<TFlowNode>.Create;
  try
    Stack.Push(FEntry);
    Seen[FEntry.Index] := True;
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Node = ANode then
      begin
        Exit(TFlowAnswer.Yes);
      end;
      for Next in Node.Successors do
      begin
        if not Seen[Next.Index] then
        begin
          Seen[Next.Index] := True;
          Stack.Push(Next);
        end;
      end;
    end;
  finally
    Stack.Free;
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
  Seen: array[Boolean] of TArray<Boolean>;
  Stack: TStack<Integer>;
  Node: TFlowNode;
  Item: Integer;
  Touched: Boolean;

  procedure Push(APred: TFlowNode; ATouched: Boolean);
  begin
    if not Seen[ATouched][APred.Index] then
    begin
      Seen[ATouched][APred.Index] := True;
      Stack.Push(APred.Index * 2 + Ord(ATouched));
    end;
  end;

  procedure AddUnique(var ANodes: TArray<TFlowNode>; ANew: TFlowNode);
  var
    Existing: TFlowNode;
  begin
    for Existing in ANodes do
    begin
      if Existing = ANew then
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
    Before, Earlier: TFlowNode;
  begin
    for Before in ANext.Predecessors do
    begin
      if Before.IsImplicitRaiseEdge(ANext) and SameText(Before.Defines, AName) then
      begin
        for Earlier in Before.Predecessors do
        begin
          Push(Earlier, ATouched);
        end;
      end
      else
      begin
        Push(Before, ATouched);
      end;
    end;
  end;

begin
  Result.Definitions := nil;
  Result.FromEntry := False;
  Result.MaybeFromEntry := False;
  Result.Uncertain := nil;
  SetLength(Seen[False], FNodes.Count);
  SetLength(Seen[True], FNodes.Count);
  Stack := TStack<Integer>.Create;
  try
    PushPredecessors(ANode, False);
    while Stack.Count > 0 do
    begin
      Item := Stack.Pop;
      Node := FNodes[Item div 2];
      Touched := Odd(Item);
      if SameText(Node.Defines, AName) then
      begin
        AddUnique(Result.Definitions, Node);
        Continue;
      end;
      if Node = FEntry then
      begin
        if Touched then
        begin
          Result.MaybeFromEntry := True;
        end
        else
        begin
          Result.FromEntry := True;
        end;
      end;
      if Node.TouchesName(AName) then
      begin
        AddUnique(Result.Uncertain, Node);
        Touched := True;
      end;
      PushPredecessors(Node, Touched);
    end;
  finally
    Stack.Free;
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
  Node: TFlowNode;
  Answer: TFlowAnswer;
begin
  if not FComplete then
  begin
    Exit(TFlowAnswer.Unknown);
  end;
  Result := TFlowAnswer.No;
  for Node in FNodes do
  begin
    if (Node.ReadsName(AName) or Node.MaybeReadsName(AName)) and (IsReachable(Node) = TFlowAnswer.Yes) then
    begin
      Answer := AnswerOf(ReachingDefinitions(Node, AName));
      // Ein Lesen, das nur vielleicht eines ist, ergibt höchstens Unknown.
      if (Answer = TFlowAnswer.Yes) and Node.ReadsName(AName) then
      begin
        Exit(TFlowAnswer.Yes);
      end;
      if Answer <> TFlowAnswer.No then
      begin
        Result := TFlowAnswer.Unknown;
      end;
    end;
  end;
end;

end.
