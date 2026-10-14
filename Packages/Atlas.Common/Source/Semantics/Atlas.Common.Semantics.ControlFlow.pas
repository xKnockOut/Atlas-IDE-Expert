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
    FDominators: TArray<TArray<Boolean>>;
    procedure ComputeDominators;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Baut den Graphen für eine Routine (RoutineDecl, AnonymousMethod)
    /// oder einen Anweisungsblock. Der Syntaxbaum muss länger leben als der Graph.
    /// ALookup nennt die Übergabeart von Argumenten; nil = TFlowSignatures.FromTree
    /// mit der Wurzel des Baums.</summary>
    class function Build(ARoutine: TSyntaxNode; const ALookup: TFlowSignatureLookup = nil): TControlFlowGraph;
      static;
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
  end;

implementation

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
    constructor Create(ADepth: Integer);
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

function IsStatement(AKind: TSyntaxKind): Boolean;
begin
  case AKind of
    TSyntaxKind.Block, TSyntaxKind.AsmBlock, TSyntaxKind.AssignStatement, TSyntaxKind.CallStatement,
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.ForStatement,
    TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
    TSyntaxKind.WithStatement, TSyntaxKind.TryStatement, TSyntaxKind.RaiseStatement,
    TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement, TSyntaxKind.InlineVar,
    TSyntaxKind.InlineConst, TSyntaxKind.EmptyStatement, TSyntaxKind.Error:
      Result := True;
  else
    Result := False;
  end;
end;

function ContainsName(const ANames: TArray<string>; const AName: string): Boolean;
var
  Name: string;
begin
  for Name in ANames do
    if SameText(Name, AName) then
      Exit(True);
  Result := False;
end;

procedure AddName(var ANames: TArray<string>; const AName: string);
begin
  if (AName <> '') and not ContainsName(ANames, AName) then
    ANames := ANames + [AName];
end;

/// <summary>Bezeichner, an dem eine Kette wie X.Feld, X[I] oder X^ hängt; sonst ''.</summary>
function RootName(ANode: TSyntaxNode): string;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
    ANode := ANode.Children[0];
  if (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) then
    Result := ANode.Name
  else
    Result := '';
end;

/// <summary>Enthält die Kette bis zum Bezeichner ein ^? Dann ändert sie nicht die Variable selbst.</summary>
function ThroughPointer(ANode: TSyntaxNode): Boolean;
begin
  while (ANode <> nil) and (ANode.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.ChildCount > 0) do
  begin
    if ANode.Kind = TSyntaxKind.Dereference then
      Exit(True);
    ANode := ANode.Children[0];
  end;
  Result := False;
end;

/// <summary>Enthält der Teilbaum einen Fehlerknoten (auch in Ausdrücken)?</summary>
function ContainsError(ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.Error then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if ContainsError(ANode.Children[Index]) then
      Exit(True);
  Result := False;
end;

function Concat(const A, B: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
begin
  Result := A;
  for Node in B do
    Result := Result + [Node];
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
    if SameText(Signature.Name, AName) then
    begin
      if AArgument < Length(Signature.Modes) then
        Code := Signature.Modes[AArgument + 1]
      else
        Code := Signature.Modes[Length(Signature.Modes)];
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
  for Name in ValueRoutines do
    if SameText(Name, AName) then
    begin
      AMode := TFlowArgumentMode.Value;
      Exit(True);
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
        Exit;
      Callee := ACall.Children[0];
      // Obj.Methode(…) oder Foo<T>(…): ohne Typauflösung unbekannt.
      if Callee.Kind <> TSyntaxKind.Identifier then
        Exit;
      if not Table.Find(Callee.Name, AArgument, Result) then
        TFlowSignatures.TryBuiltin(Callee.Name, AArgument, Result);
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

procedure TFlowRoutineTable.AddHeader(AHeader: TSyntaxNode);
var
  Params, Param: TSyntaxNode;
  Modes, Known: TArray<TFlowArgumentMode>;
  Mode: TFlowArgumentMode;
  Key: string;
  Index, Count: Integer;
begin
  Modes := nil;
  Params := AHeader.FindChild(TSyntaxKind.Parameters);
  if Params <> nil then
    for Index := 0 to Params.ChildCount - 1 do
    begin
      Param := Params.Children[Index];
      if Param.Kind <> TSyntaxKind.Parameter then
        Continue;
      case Param.Modifier of
        TParameterModifier.VarParam:
          Mode := TFlowArgumentMode.Reference;
        TParameterModifier.OutParam:
          Mode := TFlowArgumentMode.Output;
      else
        Mode := TFlowArgumentMode.Value;
      end;
      for Count := 1 to Length(Param.Name.Split([','])) do
        Modes := Modes + [Mode];
    end;
  Key := LowerCase(Copy(AHeader.Name, LastDelimiter('.', AHeader.Name) + 1, MaxInt));
  if Key = '' then
    Exit;
  // Überladungen: Wo sich die Übergabeart unterscheidet oder ein Argument fehlt, ist sie unbekannt.
  if FRoutines.TryGetValue(Key, Known) then
  begin
    if Length(Known) > Length(Modes) then
      SetLength(Modes, Length(Known));
    for Index := 0 to High(Modes) do
      if (Index > High(Known)) or (Known[Index] <> Modes[Index]) then
        Modes[Index] := TFlowArgumentMode.Unknown;
  end;
  FRoutines.AddOrSetValue(Key, Modes);
end;

procedure TFlowRoutineTable.Collect(ANode: TSyntaxNode);
var
  Index: Integer;
begin
  if ANode.Kind = TSyntaxKind.RoutineHeader then
    AddHeader(ANode);
  for Index := 0 to ANode.ChildCount - 1 do
    Collect(ANode.Children[Index]);
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
      Collect(FRoot);
  end;
  Result := FRoutines.TryGetValue(LowerCase(AName), Modes);
  // Mehr Argumente als Parameter: andere Überladung oder offenes Array, also unbekannt.
  if Result and (AArgument >= 0) and (AArgument <= High(Modes)) then
    AMode := Modes[AArgument];
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

constructor TFinallyContext.Create(ADepth: Integer);
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
    Exit;
  AFrom.FSuccessors.Add(ATo);
  ATo.FPredecessors.Add(AFrom);
end;

procedure TFlowBuilder.LinkAll(const AFrom: TArray<TFlowNode>; ATo: TFlowNode);
var
  Node: TFlowNode;
begin
  for Node in AFrom do
    Link(Node, ATo);
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
    ATarget.Sources.Add(AFrom);
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
    Jump(Result, FRaiseTargets.Last);
end;

function TFlowBuilder.Sequence(AParent: TSyntaxNode; AFirst: Integer;
  const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Index: Integer;
begin
  Result := APreds;
  for Index := AFirst to AParent.ChildCount - 1 do
    if IsStatement(AParent.Children[Index].Kind) then
      Result := Statement(AParent.Children[Index], Result);
end;

function TFlowBuilder.Statement(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Node: TFlowNode;
  Index: Integer;
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
    TSyntaxKind.WithStatement:
      begin
        Node := Simple(S, APreds);
        Result := Sequence(S, 0, [Node]);
      end;
    TSyntaxKind.TryStatement:
      Result := BuildTry(S, APreds);
    TSyntaxKind.CallStatement:
      Result := BuildCall(S, APreds);
    TSyntaxKind.RaiseStatement:
      begin
        Node := Simple(S, APreds);
        Jump(Node, FRaiseTargets.Last);
        Result := nil;
      end;
    TSyntaxKind.GotoStatement:
      begin
        Node := Simple(S, APreds);
        Link(Node, LabelNode(S.Name));
        Result := nil;
      end;
    TSyntaxKind.LabeledStatement:
      begin
        Node := LabelNode(S.Name);
        LinkAll(APreds, Node);
        Result := Sequence(S, 0, [Node]);
      end;
    TSyntaxKind.AssignStatement:
      begin
        Node := Simple(S, APreds);
        if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Identifier) then
          Node.FDefines := S.Children[0].Name;
        Result := [Node];
      end;
    TSyntaxKind.InlineVar, TSyntaxKind.InlineConst:
      begin
        Node := Simple(S, APreds);
        for Index := 0 to S.ChildCount - 1 do
          if S.Children[Index].Kind <> TSyntaxKind.TypeReference then
            Node.FDefines := S.Name;
        Result := [Node];
      end;
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
    if IsStatement(S.Children[Index].Kind) then
    begin
      Result := Concat(Result, Statement(S.Children[Index], [Condition]));
      Inc(Branches);
    end;
  if Branches < 2 then
    Result := Concat(Result, [Condition]);
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
    if S.Children[Index].Kind in [TSyntaxKind.CaseItem, TSyntaxKind.CaseElse] then
    begin
      HasElse := HasElse or (S.Children[Index].Kind = TSyntaxKind.CaseElse);
      Result := Concat(Result, Sequence(S.Children[Index], 0, [Condition]));
    end;
  if not HasElse then
    Result := Concat(Result, [Condition]);
end;

function TFlowBuilder.BuildLoop(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  Init, Condition: TFlowNode;
  Loop: TLoopContext;
  Body: TArray<TFlowNode>;
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
  LinkAll(Body, Condition);
  Loop.BreakTarget := NewTarget;
  Loop.ContinueTarget := NewTarget;
  FLoops.Add(Loop);
  Body := Sequence(S, 0, [Condition]);
  FLoops.Delete(FLoops.Count - 1);
  LinkAll(Body, Condition);
  Resolve(Loop.ContinueTarget, Condition);
  Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
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
  Result := Concat([Condition], Loop.BreakTarget.Sources.ToArray);
end;

function TFlowBuilder.BuildTry(S: TSyntaxNode; const APreds: TArray<TFlowNode>): TArray<TFlowNode>;
var
  ExceptPart, FinallyPart, Child: TSyntaxNode;
  Handlers: TJumpTarget;
  Context: TFinallyContext;
  Handler, FinallyEntry, Node: TFlowNode;
  Body, Ends: TArray<TFlowNode>;
  Index: Integer;
  HasHandlers, HasElse, Pass: Boolean;
  Onward: TJumpTarget;
begin
  ExceptPart := S.FindChild(TSyntaxKind.ExceptBlock);
  FinallyPart := S.FindChild(TSyntaxKind.FinallyBlock);
  if FinallyPart <> nil then
  begin
    Context := TFinallyContext.Create(FFinallies.Count);
    FFinallies.Add(Context);
    try
      // Ausnahmen im try-Teil verlassen den Bereich nach außen, also durch finally.
      Inc(FTryDepth);
      Body := Sequence(S, 0, APreds);
      Dec(FTryDepth);
      FFinallies.Delete(FFinallies.Count - 1);
      // Normales Ende des try-Teils: weiter hinter dem try.
      Result := nil;
      if Length(Body) > 0 then
      begin
        FinallyEntry := NewNode(TFlowNodeKind.Join, nil);
        LinkAll(Body, FinallyEntry);
        Result := Sequence(FinallyPart, 0, [FinallyEntry]);
      end;
      // Je Sprungziel eine eigene Kopie, die nur dorthin weiterführt. Die
      // Wege für Ausnahmen kommen zuletzt, damit NodeOf eine Anweisung im
      // finally zuerst auf dem normalen Weg findet.
      for Pass := False to True do
        for Index := 0 to Context.Onward.Count - 1 do
        begin
          Onward := Context.Onward[Index];
          if FRaiseTargets.Contains(Onward) <> Pass then
            Continue;
          FinallyEntry := NewNode(TFlowNodeKind.Join, nil);
          Resolve(Context.Routes[Index], FinallyEntry);
          Ends := Sequence(FinallyPart, 0, [FinallyEntry]);
          for Node in Ends do
            Jump(Node, Onward);
        end;
    finally
      Context.Free;
    end;
    Exit;
  end;

  if ExceptPart = nil then
    Exit(Sequence(S, 0, APreds));

  Handlers := NewTarget;
  FRaiseTargets.Add(Handlers);
  Inc(FTryDepth);
  Body := Sequence(S, 0, APreds);
  Dec(FTryDepth);
  FRaiseTargets.Delete(FRaiseTargets.Count - 1);
  Handler := NewNode(TFlowNodeKind.Join, nil);
  Resolve(Handlers, Handler);
  Result := Body;
  HasHandlers := False;
  HasElse := False;
  for Index := 0 to ExceptPart.ChildCount - 1 do
  begin
    Child := ExceptPart.Children[Index];
    if Child.Kind = TSyntaxKind.ExceptionHandler then
    begin
      HasHandlers := True;
      Ends := Sequence(Child, 0, [Handler]);
      Result := Concat(Result, Ends);
    end
    else if IsStatement(Child.Kind) then
      HasElse := True;
  end;
  if HasElse or not HasHandlers then
    Result := Concat(Result, Sequence(ExceptPart, 0, [Handler]))
  else
    // Nicht behandelte Ausnahmen laufen weiter nach außen.
    Jump(Handler, FRaiseTargets.Last);
end;

/// <summary>Aufruf über einen einfachen Namen (Exit, Exit(1)), nicht über ein Objekt (TMonitor.Exit(FLock)).</summary>
function IsPlainCall(S: TSyntaxNode): Boolean;
var
  Target: TSyntaxNode;
begin
  // Ohne Kinder ist es der Name allein ("Exit;").
  if S.ChildCount = 0 then
    Exit(True);
  Target := S.Children[0];
  if (Target.Kind = TSyntaxKind.Call) and (Target.ChildCount > 0) then
    Target := Target.Children[0];
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
    Name := LowerCase(S.Name);
  if Name = 'exit' then
  begin
    // Exit(Wert) setzt Result.
    if (S.ChildCount > 0) and (S.Children[0].Kind = TSyntaxKind.Call) and (S.Children[0].ChildCount > 1) then
      Node.FDefines := 'Result';
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
    Result := [Node];
end;

procedure TFlowBuilder.Analyze(ANode: TFlowNode);

  procedure Touch(const AName: string; AMaybeRead: Boolean);
  begin
    AddName(ANode.FTouches, AName);
    if AMaybeRead then
      AddName(ANode.FMaybeReads, AName);
  end;

  /// <summary>Jede Erwähnung in einer anonymen Methode: Sie kann die Variable später ändern.</summary>
  procedure Captured(E: TSyntaxNode);
  var
    Index: Integer;
  begin
    if E.Kind = TSyntaxKind.Identifier then
      Touch(E.Name, True);
    for Index := 0 to E.ChildCount - 1 do
      Captured(E.Children[Index]);
  end;

  /// <summary>Liest die Namen in E. Mit AChainParts nur die Teile einer Kette wie X[I].Feld
  /// außer dem Bezeichner am Anfang (die Indizes werden gelesen).</summary>
  procedure Visit(E: TSyntaxNode; AChainParts: Boolean);

    procedure VisitArgument(ACall: TSyntaxNode; AIndex: Integer);
    var
      Arg: TSyntaxNode;
      Root: string;
      Mode: TFlowArgumentMode;
    begin
      Arg := ACall.Children[AIndex];
      Root := RootName(Arg);
      // Nur eine Variable oder ein Teil davon kann als var/out übergeben werden.
      if (Root = '') or ThroughPointer(Arg) then
      begin
        Visit(Arg, False);
        Exit;
      end;
      Mode := TFlowArgumentMode.Unknown;
      if Assigned(FLookup) then
        Mode := FLookup(ACall, AIndex - 1);
      case Mode of
        TFlowArgumentMode.Value:
          Visit(Arg, False);
        TFlowArgumentMode.Output:
          begin
            Touch(Root, False);
            Visit(Arg, True);
          end;
      else
        begin
          // var oder unbekannt: kann lesen und schreiben.
          Touch(Root, True);
          Visit(Arg, True);
        end;
      end;
    end;

  var
    Index: Integer;
    Root: string;
  begin
    if AChainParts then
    begin
      while (E <> nil) and (E.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
        TSyntaxKind.Dereference]) and (E.ChildCount > 0) do
      begin
        for Index := 1 to E.ChildCount - 1 do
          Visit(E.Children[Index], False);
        E := E.Children[0];
      end;
      Exit;
    end;
    case E.Kind of
      TSyntaxKind.Identifier:
        AddName(ANode.FReads, E.Name);
      TSyntaxKind.TypeReference, TSyntaxKind.GenericArgs, TSyntaxKind.Literal:
        ;
      TSyntaxKind.AnonymousMethod, TSyntaxKind.RoutineDecl:
        Captured(E);
      TSyntaxKind.AddressOf:
        begin
          Root := '';
          if E.ChildCount > 0 then
            Root := RootName(E.Children[0]);
          if (Root <> '') and not ThroughPointer(E.Children[0]) then
          begin
            Touch(Root, False);
            Visit(E.Children[0], True);
          end
          else
            for Index := 0 to E.ChildCount - 1 do
              Visit(E.Children[Index], False);
        end;
      TSyntaxKind.Call:
        if E.ChildCount > 0 then
        begin
          Visit(E.Children[0], False);
          // Methode auf einer Variablen (X.Clear, R.Init(…)) kann deren Teile ändern.
          if (E.Children[0].Kind = TSyntaxKind.MemberAccess) and not ThroughPointer(E.Children[0]) then
            Touch(RootName(E.Children[0]), True);
          for Index := 1 to E.ChildCount - 1 do
            VisitArgument(E, Index);
        end;
    else
      for Index := 0 to E.ChildCount - 1 do
        Visit(E.Children[Index], False);
    end;
  end;

var
  S, Child, Target: TSyntaxNode;
  Index: Integer;
  AllChildren: Boolean;
begin
  S := ANode.Syntax;
  if (S = nil) or (S.Kind in [TSyntaxKind.AsmBlock, TSyntaxKind.GotoStatement, TSyntaxKind.EmptyStatement]) then
    Exit;
  AllChildren := (ANode.Kind = TFlowNodeKind.Statement) and (S.Kind in [TSyntaxKind.AssignStatement,
    TSyntaxKind.CallStatement, TSyntaxKind.RaiseStatement, TSyntaxKind.InlineVar, TSyntaxKind.InlineConst,
    TSyntaxKind.Error]);
  for Index := 0 to S.ChildCount - 1 do
  begin
    Child := S.Children[Index];
    if not AllChildren and (IsStatement(Child.Kind) or (Child.Kind in [TSyntaxKind.CaseItem,
      TSyntaxKind.CaseElse, TSyntaxKind.ExceptBlock, TSyntaxKind.ExceptionHandler, TSyntaxKind.FinallyBlock])) then
      Continue;
    if (Index = 0) and (S.Kind = TSyntaxKind.AssignStatement) then
    begin
      // Ziel der Zuweisung: X := … setzt X (Defines); X.Feld := … und X[I] := … ändern nur einen Teil.
      Target := Child;
      if Target.Kind <> TSyntaxKind.Identifier then
        if (RootName(Target) <> '') and not ThroughPointer(Target) then
        begin
          Touch(RootName(Target), True);
          Visit(Target, True);
        end
        else
          Visit(Target, False);
      Continue;
    end;
    Visit(Child, False);
    // X.Methode; ohne Klammern und with X do …: Teile von X können sich ändern.
    if ((S.Kind = TSyntaxKind.CallStatement) or (S.Kind = TSyntaxKind.WithStatement)) and
      (Child.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.Identifier, TSyntaxKind.IndexAccess]) and
      ((S.Kind = TSyntaxKind.WithStatement) or (Child.Kind = TSyntaxKind.MemberAccess)) and
      not ThroughPointer(Child) then
      Touch(RootName(Child), True);
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
    Body := ARoutine
  else
    for Index := ARoutine.ChildCount - 1 downto 0 do
      if ARoutine.Children[Index].Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
      begin
        Body := ARoutine.Children[Index];
        Break;
      end;
  if Body = nil then
  begin
    FGraph.FComplete := False;
    Link(FGraph.FEntry, FGraph.FExit);
    Exit;
  end;
  // Syntaxfehler irgendwo in der Routine, auch mitten in einem Ausdruck: keine Aussage.
  if ContainsError(Body) then
    FGraph.FComplete := False;
  Ends := Statement(Body, [FGraph.FEntry]);
  LinkAll(Ends, FGraph.FExit);
  Resolve(FExitTarget, FGraph.FExit);
  Resolve(FRaiseTarget, FGraph.FRaiseExit);
  for Node in FGraph.FNodes do
    Analyze(Node);
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
      Root := Root.Parent;
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
    if Node.Syntax = ASyntax then
      Exit(Node);
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
        Exit(TFlowAnswer.Yes);
      for Next in Node.Successors do
        if not Seen[Next.Index] then
        begin
          Seen[Next.Index] := True;
          Stack.Push(Next);
        end;
    end;
  finally
    Stack.Free;
  end;
  if FComplete then
    Result := TFlowAnswer.No
  else
    Result := TFlowAnswer.Unknown;
end;

procedure TControlFlowGraph.ComputeDominators;
var
  Count, I, J: Integer;
  Changed, Value: Boolean;
  Node, Pred: TFlowNode;
  First: Boolean;
  Reachable: TArray<Boolean>;
begin
  if FDominators <> nil then
    Exit;
  Count := FNodes.Count;
  // Unerreichbare Vorgänger (Code nach Exit) zählen nicht; sonst dominierte
  // nichts mehr den gemeinsamen Nachfolger.
  SetLength(Reachable, Count);
  for Node in FNodes do
    Reachable[Node.Index] := IsReachable(Node) = TFlowAnswer.Yes;
  SetLength(FDominators, Count);
  for I := 0 to Count - 1 do
  begin
    SetLength(FDominators[I], Count);
    for J := 0 to Count - 1 do
      FDominators[I][J] := I <> FEntry.Index;
  end;
  FDominators[FEntry.Index][FEntry.Index] := True;
  repeat
    Changed := False;
    for Node in FNodes do
    begin
      if Node = FEntry then
        Continue;
      for J := 0 to Count - 1 do
      begin
        // Schnitt über alle Vorgänger, dazu der Knoten selbst.
        if J = Node.Index then
          Value := True
        else
        begin
          Value := False;
          First := True;
          for Pred in Node.Predecessors do
          begin
            if not Reachable[Pred.Index] then
              Continue;
            if First then
              Value := FDominators[Pred.Index][J]
            else
              Value := Value and FDominators[Pred.Index][J];
            First := False;
          end;
        end;
        if Value <> FDominators[Node.Index][J] then
        begin
          FDominators[Node.Index][J] := Value;
          Changed := True;
        end;
      end;
    end;
  until not Changed;
end;

function TControlFlowGraph.Dominates(A, B: TFlowNode): TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  if IsReachable(B) <> TFlowAnswer.Yes then
    Exit(TFlowAnswer.Unknown);
  ComputeDominators;
  if FDominators[B.Index][A.Index] then
    Result := TFlowAnswer.Yes
  else
    Result := TFlowAnswer.No;
end;

function TControlFlowGraph.UnreachableStatements: TArray<TFlowNode>;
var
  Node, Other, Seen: TFlowNode;
  Reachable, Listed: Boolean;
begin
  Result := nil;
  if not FComplete then
    Exit;
  for Node in FNodes do
    if (Node.Kind in [TFlowNodeKind.Statement, TFlowNodeKind.Condition]) and
      (IsReachable(Node) = TFlowAnswer.No) then
    begin
      // Ein finally steht je Ausgang einmal im Graphen; unerreichbar ist es
      // nur, wenn keine seiner Kopien erreichbar ist. Gemeldet wird es einmal.
      Reachable := False;
      Listed := False;
      for Other in FNodes do
        if (Other <> Node) and (Other.Syntax = Node.Syntax) and (IsReachable(Other) = TFlowAnswer.Yes) then
          Reachable := True;
      for Seen in Result do
        if Seen.Syntax = Node.Syntax then
          Listed := True;
      if not Reachable and not Listed then
        Result := Result + [Node];
    end;
end;

function TControlFlowGraph.ReachingDefinitions(ANode: TFlowNode; const AName: string): TReachingDefinitions;
var
  // Zustand je Knoten: 0 = Weg ohne, 1 = Weg mit unsicherer Änderung dahinter.
  Seen: array[Boolean] of TArray<Boolean>;
  Stack: TStack<Integer>;
  Node, Pred: TFlowNode;
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
      if Existing = ANew then
        Exit;
    ANodes := ANodes + [ANew];
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
    for Pred in ANode.Predecessors do
      Push(Pred, False);
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
          Result.MaybeFromEntry := True
        else
          Result.FromEntry := True;
      end;
      if Node.TouchesName(AName) then
      begin
        AddUnique(Result.Uncertain, Node);
        Touched := True;
      end;
      for Pred in Node.Predecessors do
        Push(Pred, Touched);
    end;
  finally
    Stack.Free;
  end;
end;

/// <summary>Yes über einen sicheren Weg, Unknown nur über unsichere Änderungen, sonst No.</summary>
function AnswerOf(const ADefinitions: TReachingDefinitions): TFlowAnswer;
begin
  if ADefinitions.FromEntry then
    Result := TFlowAnswer.Yes
  else if ADefinitions.MaybeFromEntry then
    Result := TFlowAnswer.Unknown
  else
    Result := TFlowAnswer.No;
end;

function TControlFlowGraph.MayEndWithout(const AName: string): TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  Result := AnswerOf(ReachingDefinitions(FExit, AName));
end;

function TControlFlowGraph.MayReadBeforeWrite(ANode: TFlowNode; const AName: string): TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  Result := AnswerOf(ReachingDefinitions(ANode, AName));
end;

function TControlFlowGraph.MayReadBeforeWrite(const AName: string): TFlowAnswer;
var
  Node: TFlowNode;
  Answer: TFlowAnswer;
begin
  if not FComplete then
    Exit(TFlowAnswer.Unknown);
  Result := TFlowAnswer.No;
  for Node in FNodes do
    if (Node.ReadsName(AName) or Node.MaybeReadsName(AName)) and (IsReachable(Node) = TFlowAnswer.Yes) then
    begin
      Answer := AnswerOf(ReachingDefinitions(Node, AName));
      // Ein Lesen, das nur vielleicht eines ist, ergibt höchstens Unknown.
      if (Answer = TFlowAnswer.Yes) and Node.ReadsName(AName) then
        Exit(TFlowAnswer.Yes);
      if Answer <> TFlowAnswer.No then
        Result := TFlowAnswer.Unknown;
    end;
end;

end.
