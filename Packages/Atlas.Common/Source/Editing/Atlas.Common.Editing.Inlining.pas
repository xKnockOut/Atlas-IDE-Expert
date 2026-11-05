unit Atlas.Common.Editing.Inlining;

// Einbetten (#103, Teil A) als Code-Aktionen, ohne Protokollbezug:
//   - „Variable einbetten“ (hier): Eine lokale Variable mit genau einer
//     Zuweisung (bzw. eine Inline-Variable mit Startwert) verschwindet; jedes
//     Lesen bekommt den Ausdruck, bei Bedarf in Klammern. Der Datenfluss muss
//     zeigen, dass jedes Lesen genau diese Zuweisung sieht und die lokalen
//     Namen des Ausdrucks dort denselben Wert haben. Liest der Ausdruck
//     Felder, globale Namen oder Speicher, darf dazwischen nichts aufgerufen
//     und nichts außer lokalen Variablen geschrieben werden; hat er
//     Seiteneffekte (Aufrufe), darf er nur einmal und ohne Lesen davor
//     gebraucht werden.
//   - „Methode einbetten“ (Atlas.Common.Editing.Inlining.Method): Der Aufruf
//     an der Einfügemarke wird durch den Rumpf ersetzt.
// Namensauflösung bringt der Aufrufer über TInlineOptions.Lookup mit: Sie
// sagt, ob ein Name ein Mitglied oder eine Routine ist und ob er am Aufruf
// dasselbe bedeutet wie in der Methode. Die Typen stehen in
// Atlas.Common.Editing.Inlining.Types und sind hier noch einmal benannt.
//
// Nicht angeboten wird: Parameter, Laufvariablen und Konstanten; mehrere
// Zuweisungen; Lesen in anonymen Methoden, verschachtelten Routinen oder
// with; asm, inherited, goto, with, anonyme Methoden, verschachtelte
// Routinen oder lokale Typen in der Methode; Rekursion, Konstruktoren,
// Destruktoren und generische Methoden; mehrere Exit; Result vor dem ersten
// Setzen gelesen; private oder strict-Mitglieder außerhalb ihrer Klasse bzw.
// Unit; ein Name, der am Aufruf etwas anderes bedeutet.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.Inlining.Types;

const
  /// <summary>Art der Einbetten-Aktionen (LSP).</summary>
  InlineKind = Atlas.Common.Editing.Inlining.Types.InlineKind;

type
  TInlineVisibility = Atlas.Common.Editing.Inlining.Types.TInlineVisibility;
  TInlineMeaning = Atlas.Common.Editing.Inlining.Types.TInlineMeaning;
  TInlineLookup = Atlas.Common.Editing.Inlining.Types.TInlineLookup;
  TInlineSource = Atlas.Common.Editing.Inlining.Types.TInlineSource;
  TInlineCallee = Atlas.Common.Editing.Inlining.Types.TInlineCallee;
  TInlineOptions = Atlas.Common.Editing.Inlining.Types.TInlineOptions;
  TInlineCall = Atlas.Common.Editing.Inlining.Types.TInlineCall;

  TInlineRefactoring = class
  public const
    ResultSuffix = InlineResultSuffix;
  public
    /// <summary>„Variable einbetten“ für die lokale Variable an APosition; False mit Grund in AReason.</summary>
    class function InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
      const AOptions: TInlineOptions; out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    class function InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
      const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Aufruf, dessen Name an APosition steht; False ohne.</summary>
    class function CallAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
      out ACall: TInlineCall): Boolean; static;
    /// <summary>Rümpfe (RoutineDecl mit Block) mit dem Namen AName ("TFoo.Bar" bzw. "Bar"), ohne
    /// verschachtelte Routinen.</summary>
    class function FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>; static;
    /// <summary>„Methode einbetten“ für den Aufruf an APosition in ACaller; ACallee ist der Rumpf (dieselbe Datei
    /// oder eine andere). False mit Grund in AReason.</summary>
    class function InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
      const ACallee: TInlineCallee; const AOptions: TInlineOptions; out AAction: TCodeAction;
      out AReason: string): Boolean; overload; static;
    class function InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
      const ACallee: TInlineCallee; const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean; overload;
      static;
    /// <summary>„Variable einbetten“ und, wenn der Rumpf eindeutig in derselben Datei steht, „Methode
    /// einbetten“ für APosition.</summary>
    class function Actions(const ASource: TInlineSource; const APosition: TTextPosition;
      const AOptions: TInlineOptions): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Editing.Inlining.Syntax,
  Atlas.Common.Editing.Inlining.Method,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TInliningText = (NoSyntaxTree, NoIdentifier, NotInARoutine, IsNotALocalVariable, SeveralNamesInOneDeclaration,
    IsUsedInANested, IsALoopVariable, IsUsedInAnAnonymous, IsChanged, IsAssignedMoreThanOnce, GetsNoValue,
    IsNeverRead, TheAssignmentIsNotIn, TheAssignmentIsInA, TheExpressionContains, TheExpressionHasSideEffects,
    AsmOrSyntaxErrorIn, AssignmentNotInTheFlow, ReadNotInTheFlow, AtOnePlaceADifferent, IsNotVisibleAtOne,
    ChangesBeforeOnePlace, InBetweenTheValueOf, TheExpressionHasSideEffects2, OnlyLocalVariables, IsInAWithBody);

const
  cTexts: array[TInliningText] of TAtlasText = (
    (De: 'kein Syntaxbaum'; En: 'no syntax tree'),
    (De: 'kein Bezeichner'; En: 'no identifier'),
    (De: 'nicht in einer Routine'; En: 'not in a routine'),
    (De: ' ist keine lokale Variable'; En: ' is not a local variable'),
    (De: 'mehrere Namen in einer Deklaration'; En: 'several names in one declaration'),
    (De: ' wird in einer verschachtelten Routine verwendet'; En: ' is used in a nested routine'),
    (De: ' ist Laufvariable'; En: ' is a loop variable'),
    (De: ' wird in einer anonymen Methode verwendet'; En: ' is used in an anonymous method'),
    (De: ' wird verändert'; En: ' is changed'),
    (De: ' wird mehrfach zugewiesen'; En: ' is assigned more than once'),
    (De: ' bekommt keinen Wert'; En: ' gets no value'),
    (De: ' wird nie gelesen'; En: ' is never read'),
    (De: 'die Zuweisung steht nicht in einer Anweisungsliste'; En: 'the assignment is not in a statement list'),
    (De: 'die Zuweisung steht in einem with-Rumpf'; En: 'the assignment is in a with body'),
    (De: 'der Ausdruck enthält '; En: 'the expression contains '),
    (De: 'der Ausdruck hat Seiteneffekte und wird mehrfach gelesen';
     En: 'the expression has side effects and is read more than once'),
    (De: 'asm oder Syntaxfehler in der Routine'; En: 'asm or syntax error in the routine'),
    (De: 'Zuweisung nicht im Ablauf'; En: 'assignment not in the flow'),
    (De: 'Lesen nicht im Ablauf'; En: 'read not in the flow'),
    (De: 'an einer Stelle kommt ein anderer Wert von %s an'; En: 'at one place a different value of %s arrives'),
    (De: ' ist an einer Stelle nicht sichtbar'; En: ' is not visible at one place'),
    (De: ' ändert sich vor einer Stelle'; En: ' changes before one place'),
    (De: 'dazwischen kann sich der Wert des Ausdrucks ändern';
     En: 'in between the value of the expression may change'),
    (De: 'der Ausdruck hat Seiteneffekte; die Reihenfolge änderte sich';
     En: 'the expression has side effects; the order would change'),
    (De: 'nur lokale Variablen'; En: 'only local variables'),
    (De: ' steht in einem with-Rumpf'; En: ' is in a with body'));

{$SCOPEDENUMS OFF}

type
  TLocal = TRoutineLocal;
  TLocalKind = TRoutineLocalKind;

  /// <summary>Arbeitsstand von „Variable einbetten“.</summary>
  TVariableInliner = record
    Source: TInlineSource;
    Options: TInlineOptions;
    Tree: TSyntaxTree;
    Tokens: TArray<TPascalToken>;
    Name: string;
    Offset: Integer;
    Routine: TSyntaxNode;
    Body: TSyntaxNode;
    Locals: TArray<TLocal>;
    LocalIndex: Integer;
    Local: TLocal;
    Flow: TFlowSignatureLookup;
    /// <summary>Zuweisung bzw. Inline-Deklaration mit Startwert und ihr Ausdruck.</summary>
    Definition: TSyntaxNode;
    Expression: TSyntaxNode;
    Reads: TArray<TSyntaxNode>;
    /// <summary>Bezeichner im Ausdruck.</summary>
    ExprNames: TArray<TSyntaxNode>;
    /// <summary>Kann sich der Wert des Ausdrucks ohne lokale Zuweisung ändern?</summary>
    Volatile: Boolean;
    SideEffects: Boolean;
    class function Create(const ASource: TInlineSource; const AOptions: TInlineOptions): TVariableInliner; static;
    function Execute(const APosition: TTextPosition): string;
    function Action: TCodeAction;
    function StartIssue(const APosition: TTextPosition): string;
    function LocalIssue: string;
    function DeclaredIndex: Integer;
    function KindIssue: string;
    function UsedInNested: Boolean;
    function UsesIssue: string;
    procedure InitialDefinition;
    function LoopVariableIssue: string;
    function UseIssue: string;
    function OccurrenceIssue(ANode: TSyntaxNode): string;
    function NoteDefinition(ANode: TSyntaxNode): string;
    function DefinitionIssue: string;
    function ExpressionIssue: string;
    function AddressTaken: Boolean;
    function FlowIssue: string;
    function ReadIssue(AGraph: TControlFlowGraph; ADefinition: TFlowNode; ARead: TSyntaxNode): string;
    function NamesIssue(AGraph: TControlFlowGraph; ADefinition, ARead: TFlowNode; AReadNode: TSyntaxNode): string;
    function OrderIssue(ARead: TSyntaxNode): string;
  end;

{ Datenfluss }


/// <summary>Knoten des Graphen für ANode: die Anweisung oder Bedingung, in der er steht.</summary>
function FlowNodeAt(AGraph: TControlFlowGraph; ANode: TSyntaxNode): TFlowNode;
var
  Node: TSyntaxNode;
begin
  Result := nil;
  Node := ANode;
  while (Node <> nil) and (Result = nil) do
  begin
    Result := AGraph.NodeOf(Node);
    Node := Node.Parent;
  end;
end;

function SameNodes(const A, B: TArray<TFlowNode>): Boolean;
var
  Node, Other: TFlowNode;
  Found: Boolean;
begin
  if Length(A) <> Length(B) then
  begin
    Exit(False);
  end;
  for Node in A do
  begin
    Found := False;
    for Other in B do
    begin
      if Other = Node then
      begin
        Found := True;
      end;
    end;
    if not Found then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

function SameReaching(const A, B: TReachingDefinitions): Boolean;
begin
  Result := (A.FromEntry = B.FromEntry) and (A.MaybeFromEntry = B.MaybeFromEntry) and
    SameNodes(A.Definitions, B.Definitions) and SameNodes(A.Uncertain, B.Uncertain);
end;

/// <summary>Kommt an einem Lesen genau die Definition ADefinition an?</summary>
function SingleReaching(const AReaching: TReachingDefinitions; ADefinition: TFlowNode): Boolean;
begin
  Result := (Length(AReaching.Definitions) = 1) and (AReaching.Definitions[0] = ADefinition) and
    not AReaching.FromEntry and not AReaching.MaybeFromEntry and (AReaching.Uncertain = nil);
end;

/// <summary>Ändert ANode (Aufruf, Zuweisung, inherited, raise) Zustand außer lokalen Variablen?</summary>
function ChangesState(ANode: TSyntaxNode; const ALocals: TArray<TLocal>; const ASource: TInlineSource;
  const ALookup: TInlineLookup): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Call:
      Result := not TInlineSyntax.CallIsPure(ANode, ASource, ALookup);
    TSyntaxKind.CallStatement:
      Result := (ANode.ChildCount = 0) or (ANode[0].Kind <> TSyntaxKind.Call);
    TSyntaxKind.AssignStatement:
      Result := (ANode[0].Kind <> TSyntaxKind.Identifier) or
        (TRoutineLocals.IndexOf(ALocals, ANode[0].Name, ANode[0].StartOffset) < 0);
  else
    Result := True;
  end;
end;

/// <summary>Wird zwischen AFrom und ATo etwas aufgerufen oder außer lokalen Variablen etwas geschrieben?</summary>
function ChangesBetween(ABody: TSyntaxNode; const ALocals: TArray<TLocal>; AFrom, ATo: Integer;
  const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
  mKind: TSyntaxKind;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    for mKind in [TSyntaxKind.Call, TSyntaxKind.CallStatement, TSyntaxKind.InheritedExpr,
      TSyntaxKind.RaiseStatement, TSyntaxKind.AssignStatement] do
    begin
      TRoutineLocals.CollectKind(ABody, mKind, mNodes);
    end;
    for mNode in mNodes do
    begin
      if (mNode.StartOffset >= AFrom) and (mNode.EndOffset <= ATo) and
        ChangesState(mNode, ALocals, ASource, ALookup) then
      begin
        Result := True;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

{ Variable einbetten }

/// <summary>Ausdruck nur aus Literalen, lokalen Namen, Operatoren und reinen Aufrufen darauf.</summary>
function LocalOnly(ANode: TSyntaxNode; const ALocals: TArray<TLocal>): Boolean;
var
  Pending: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, First: Integer;
begin
  // Eigener Stapel statt Rekursion (Bericht M1); jeder Knoten muss passen, die Reihenfolge ist gleich.
  Result := True;
  Pending := TStack<TSyntaxNode>.Create;
  try
    Pending.Push(ANode);
    while Pending.Count > 0 do
    begin
      Node := Pending.Pop;
      case Node.Kind of
        TSyntaxKind.Literal:
          Continue;
        TSyntaxKind.Identifier:
          begin
            if (TRoutineLocals.IndexOf(ALocals, Node.Name, Node.StartOffset) < 0) and
              not MatchText(Node.Name, ConstantNames) then
            begin
              Exit(False);
            end;
            Continue;
          end;
        TSyntaxKind.Call:
          begin
            if (Node[0].Kind <> TSyntaxKind.Identifier) or not TPureRoutines.IsPure(Node[0].Name) then
            begin
              Exit(False);
            end;
            First := 1;
          end;
        TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
        TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr:
          First := 0;
      else
        Exit(False);
      end;
      for Index := Node.ChildCount - 1 downto First do
      begin
        Pending.Push(Node[Index]);
      end;
    end;
  finally
    Pending.Free;
  end;
end;


/// <summary>Wird zwischen AFrom und ATo irgendetwas gelesen (außer Zielen einfacher Zuweisungen und Namen
/// aufgerufener Routinen)?</summary>
function ReadsBetween(ABody: TSyntaxNode; AFrom, ATo: Integer): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
begin
  Result := False;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.Identifier, Nodes);
    TRoutineLocals.CollectKind(ABody, TSyntaxKind.Call, Nodes);
    for Node in Nodes do
    begin
      if (Node.StartOffset >= AFrom) and (Node.EndOffset <= ATo) and not TInlineSyntax.IsCallee(Node) and
        not ((Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] = Node)) then
      begin
        Exit(True);
      end;
    end;
  finally
    Nodes.Free;
  end;
end;

/// <summary>Wird ANode in seiner Anweisung genau einmal und unbedingt ausgewertet: nicht rechts von and/or, nicht
/// in einem Zweig von if-Ausdrücken, nicht in einer Schleifenbedingung oder case-Marke?</summary>
function EvaluatedOnce(ANode: TSyntaxNode): Boolean;
var
  Node, Child: TSyntaxNode;
begin
  Result := False;
  Child := ANode;
  Node := ANode.Parent;
  while (Node <> nil) and not TRoutineBody.IsStatement(Node) do
  begin
    if (Node.Kind = TSyntaxKind.IfExpr) and (Child <> Node[0]) then
    begin
      Exit;
    end;
    if (Node.Kind = TSyntaxKind.BinaryExpr) and (Child <> Node[0]) and (SameText(Node.Name, 'and') or
      SameText(Node.Name, 'or')) then
    begin
      Exit;
    end;
    if Node.Kind = TSyntaxKind.CaseItem then
    begin
      Exit;
    end;
    Child := Node;
    Node := Node.Parent;
  end;
  Result := (Node <> nil) and not (Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
end;

function IdentifiersOf(ANode: TSyntaxNode): TArray<TSyntaxNode>;
var
  mNodes: TList<TSyntaxNode>;
begin
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Identifier, mNodes);
    Result := mNodes.ToArray;
  finally
    mNodes.Free;
  end;
end;

{ TVariableInliner }

class function TVariableInliner.Create(const ASource: TInlineSource; const AOptions: TInlineOptions): TVariableInliner;
begin
  Result := Default(TVariableInliner);
  Result.Source := ASource;
  Result.Options := AOptions;
  Result.LocalIndex := -1;
end;

function TVariableInliner.Execute(const APosition: TTextPosition): string;
begin
  Result := StartIssue(APosition);
  if Result = '' then
  begin
    Result := LocalIssue;
  end;
  if Result = '' then
  begin
    Result := KindIssue;
  end;
  if Result = '' then
  begin
    Result := UsesIssue;
  end;
  if Result = '' then
  begin
    Result := DefinitionIssue;
  end;
  if Result = '' then
  begin
    Result := ExpressionIssue;
  end;
  if Result = '' then
  begin
    Result := FlowIssue;
  end;
end;

function TVariableInliner.Action: TCodeAction;
var
  mText: string;
  mRead: TSyntaxNode;
  mEdits: TArray<TTextEdit>;
begin
  mText := TRoutineBody.TextOf(Source.Text, Expression);
  mEdits := nil;
  for mRead in Reads do
  begin
    mEdits := mEdits + [TTextEdit.Create(TTextRange.Create(mRead.StartPos, mRead.EndPos),
      TInlineSyntax.Parenthesized(mText, Expression, mRead))];
  end;
  mEdits := mEdits + [TInlineSyntax.RemoveStatement(Source.Text, Tree, Definition)];
  if Local.Kind = TLocalKind.Variable then
  begin
    TRoutineLocals.RemoveVariables(Tree, Local.Decl, [Name], mEdits);
  end
  else if Definition <> Local.Decl then
  begin
    mEdits := mEdits + [TInlineSyntax.RemoveStatement(Source.Text, Tree, Local.Decl)];
  end;
  Result := Default(TCodeAction);
  Result.Title := Format('Variable %s einbetten', [Name]);
  Result.Kind := InlineKind;
  Result.Edits := mEdits;
end;

function TVariableInliner.StartIssue(const APosition: TTextPosition): string;
var
  mToken: Integer;
begin
  Result := '';
  Tree := Source.Tree;
  if (Tree = nil) or (Tree.Root = nil) then
  begin
    Exit(cTexts[TInliningText.NoSyntaxTree].Text);
  end;
  Tokens := Tree.Tokens;
  mToken := TInlineSyntax.TokenContaining(Tokens, TLineTable.Build(Source.Text).OffsetAt(APosition));
  if mToken < 0 then
  begin
    Exit(cTexts[TInliningText.NoIdentifier].Text);
  end;
  Name := Tokens[mToken].Text;
  Offset := Tokens[mToken].Offset;
  Routine := TInlineSyntax.RoutineContaining(Tree.Root, Offset);
  if Routine = nil then
  begin
    Result := cTexts[TInliningText.NotInARoutine].Text;
  end;
end;

function TVariableInliner.LocalIssue: string;
begin
  Result := '';
  Body := TRoutineBody.BodyOf(Routine);
  Locals := TRoutineLocals.Collect(Source.Text, Tree, Routine);
  if Offset < Body.StartOffset then
  begin
    LocalIndex := DeclaredIndex;
  end
  else
  begin
    LocalIndex := TRoutineLocals.IndexOf(Locals, Name, Offset);
  end;
  if LocalIndex < 0 then
  begin
    Result := Name + cTexts[TInliningText.IsNotALocalVariable].Text;
  end
  else
  begin
    Local := Locals[LocalIndex];
  end;
end;

/// <summary>Variable, deren Deklaration im var-Abschnitt den Namen an der Einfügemarke enthält; -1 ohne.</summary>
function TVariableInliner.DeclaredIndex: Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(Locals) do
  begin
    if (Locals[mIndex].Kind = TLocalKind.Variable) and SameText(Locals[mIndex].Name, Name) and
      (Locals[mIndex].Decl.StartOffset <= Offset) and (Offset < Locals[mIndex].Decl.EndOffset) then
    begin
      Result := mIndex;
    end;
  end;
end;

function TVariableInliner.KindIssue: string;
begin
  Result := '';
  if not (Local.Kind in [TLocalKind.Variable, TLocalKind.InlineVariable]) then
  begin
    Result := cTexts[TInliningText.OnlyLocalVariables].Text;
  end
  else if Local.Decl.Kind = TSyntaxKind.InlineConst then
  begin
    Result := 'Konstante';
  end
  else if (Local.Kind = TLocalKind.InlineVariable) and (Pos(',', Local.Decl.Name) > 0) then
  begin
    Result := cTexts[TInliningText.SeveralNamesInOneDeclaration].Text;
  end
  else
  begin
    Name := Local.Name;
    if (Local.Kind = TLocalKind.Variable) and UsedInNested then
    begin
      Result := Name + cTexts[TInliningText.IsUsedInANested].Text;
    end;
  end;
end;

/// <summary>Verschachtelte Routinen sehen die Variable auch.</summary>
function TVariableInliner.UsedInNested: Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  for mIndex := 0 to Routine.ChildCount - 1 do
  begin
    if (Routine[mIndex].Kind = TSyntaxKind.RoutineDecl) and TInlineSyntax.UsesName(Routine[mIndex], Name) then
    begin
      Result := True;
    end;
  end;
end;

function TVariableInliner.UsesIssue: string;
begin
  InitialDefinition;
  Reads := nil;
  Flow := TFlowSignatures.FromTree(Tree.Root);
  Result := LoopVariableIssue;
  if Result = '' then
  begin
    Result := UseIssue;
  end;
end;

/// <summary>Inline-Variable mit Startwert: Die Deklaration ist die Zuweisung.</summary>
procedure TVariableInliner.InitialDefinition;
begin
  Definition := nil;
  Expression := nil;
  if (Local.Kind = TLocalKind.InlineVariable) and (Local.Decl.ChildCount > 0) and
    not (Local.Decl[Local.Decl.ChildCount - 1].Kind in TRoutineLocals.TypeKinds) then
  begin
    Definition := Local.Decl;
    Expression := Local.Decl[Local.Decl.ChildCount - 1];
  end;
end;

function TVariableInliner.LoopVariableIssue: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := '';
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.ForStatement, mNodes);
    for mNode in mNodes do
    begin
      if SameText(mNode.Name, Name) and not TRoutineLocals.IsInlineFor(Tokens, mNode) and
        (TRoutineLocals.IndexOf(Locals, mNode.Name, mNode.StartOffset) = LocalIndex) then
      begin
        Result := Name + cTexts[TInliningText.IsALoopVariable].Text;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

/// <summary>Jede Stelle der Variablen: Lesen sammeln, die eine Zuweisung merken.</summary>
function TVariableInliner.UseIssue: string;
var
  mNodes: TList<TSyntaxNode>;
  mNode: TSyntaxNode;
begin
  Result := '';
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, mNodes);
    for mNode in mNodes do
    begin
      if (Result = '') and SameText(mNode.Name, Name) and
        (TRoutineLocals.IndexOf(Locals, mNode.Name, mNode.StartOffset) = LocalIndex) then
      begin
        Result := OccurrenceIssue(mNode);
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TVariableInliner.OccurrenceIssue(ANode: TSyntaxNode): string;
begin
  Result := '';
  if TInlineSyntax.Inside(ANode, TSyntaxKind.AnonymousMethod, Body) then
  begin
    Result := Name + cTexts[TInliningText.IsUsedInAnAnonymous].Text;
  end
  else if TInlineSyntax.Inside(ANode, TSyntaxKind.WithStatement, Body) then
  begin
    Result := Name + cTexts[TInliningText.IsInAWithBody].Text;
  end
  else
  begin
    case TRoutineLocals.AccessOf(ANode, Flow) of
      TLocalAccess.Read:
        Reads := Reads + [ANode];
      TLocalAccess.Write:
        Result := NoteDefinition(ANode);
    else
      Result := Name + cTexts[TInliningText.IsChanged].Text;
    end;
  end;
end;

function TVariableInliner.NoteDefinition(ANode: TSyntaxNode): string;
begin
  Result := '';
  if Definition <> nil then
  begin
    Result := Name + cTexts[TInliningText.IsAssignedMoreThanOnce].Text;
  end
  else
  begin
    Definition := ANode.Parent;
    Expression := Definition[1];
  end;
end;

function TVariableInliner.DefinitionIssue: string;
begin
  Result := '';
  if Definition = nil then
  begin
    Result := Name + cTexts[TInliningText.GetsNoValue].Text;
  end
  else if Reads = nil then
  begin
    Result := Name + cTexts[TInliningText.IsNeverRead].Text;
  end
  else if not TRoutineBody.InList(Definition) then
  begin
    Result := cTexts[TInliningText.TheAssignmentIsNotIn].Text;
  end
  else if TInlineSyntax.Inside(Definition, TSyntaxKind.WithStatement, Body) then
  begin
    Result := cTexts[TInliningText.TheAssignmentIsInA].Text;
  end
  else if TInlineSyntax.UsesName(Expression, Name) then
  begin
    Result := cTexts[TInliningText.TheExpressionContains].Text + Name;
  end;
end;

function TVariableInliner.ExpressionIssue: string;
begin
  Result := '';
  // Klammern um den ganzen Ausdruck braucht der eingesetzte Text nicht doppelt.
  if (Expression.Kind = TSyntaxKind.ParenExpr) and (Expression.ChildCount = 1) then
  begin
    Expression := Expression[0];
  end;
  Volatile := not LocalOnly(Expression, Locals);
  SideEffects := TInlineSyntax.HasSideEffects(Expression, Source, Options.Lookup);
  ExprNames := IdentifiersOf(Expression);
  if AddressTaken then
  begin
    Volatile := True;
  end;
  if SideEffects and (Length(Reads) > 1) then
  begin
    Result := cTexts[TInliningText.TheExpressionHasSideEffects].Text;
  end;
end;

/// <summary>Adresse eines Namens des Ausdrucks genommen: Er kann sich über den Zeiger ändern.</summary>
function TVariableInliner.AddressTaken: Boolean;
var
  mNodes: TList<TSyntaxNode>;
  mNode, mName: TSyntaxNode;
begin
  Result := False;
  mNodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.AddressOf, mNodes);
    for mNode in mNodes do
    begin
      for mName in ExprNames do
      begin
        if TInlineSyntax.UsesName(mNode, mName.Name) then
        begin
          Result := True;
        end;
      end;
    end;
  finally
    mNodes.Free;
  end;
end;

function TVariableInliner.FlowIssue: string;
var
  mGraph: TControlFlowGraph;
  mDefinition: TFlowNode;
  mIndex: Integer;
begin
  mGraph := TControlFlowGraph.Build(Routine, Flow);
  try
    if not mGraph.Complete then
    begin
      Exit(cTexts[TInliningText.AsmOrSyntaxErrorIn].Text);
    end;
    mDefinition := mGraph.NodeOf(Definition);
    if mDefinition = nil then
    begin
      Exit(cTexts[TInliningText.AssignmentNotInTheFlow].Text);
    end;
    Result := '';
    mIndex := 0;
    while (Result = '') and (mIndex <= High(Reads)) do
    begin
      Result := ReadIssue(mGraph, mDefinition, Reads[mIndex]);
      Inc(mIndex);
    end;
  finally
    mGraph.Free;
  end;
end;

function TVariableInliner.ReadIssue(AGraph: TControlFlowGraph; ADefinition: TFlowNode; ARead: TSyntaxNode): string;
var
  mRead: TFlowNode;
begin
  mRead := FlowNodeAt(AGraph, ARead);
  if mRead = nil then
  begin
    Exit(cTexts[TInliningText.ReadNotInTheFlow].Text);
  end;
  if not SingleReaching(AGraph.ReachingDefinitions(mRead, Name), ADefinition) then
  begin
    Exit(cTexts[TInliningText.AtOnePlaceADifferent].Fmt([Name]));
  end;
  Result := NamesIssue(AGraph, ADefinition, mRead, ARead);
  if Result = '' then
  begin
    Result := OrderIssue(ARead);
  end;
end;

/// <summary>Lokale Namen des Ausdrucks: am Lesen sichtbar und mit demselben Wert wie bei der Zuweisung.</summary>
function TVariableInliner.NamesIssue(AGraph: TControlFlowGraph; ADefinition, ARead: TFlowNode;
  AReadNode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := '';
  for mNode in ExprNames do
  begin
    mIndex := TRoutineLocals.IndexOf(Locals, mNode.Name, mNode.StartOffset);
    if (Result <> '') or (mIndex < 0) then
    begin
      Continue;
    end;
    if TRoutineLocals.IndexOf(Locals, mNode.Name, AReadNode.StartOffset) <> mIndex then
    begin
      Result := mNode.Name + cTexts[TInliningText.IsNotVisibleAtOne].Text;
    end
    else if (Locals[mIndex].Kind <> TLocalKind.Constant) and
      not SameReaching(AGraph.ReachingDefinitions(ADefinition, mNode.Name),
      AGraph.ReachingDefinitions(ARead, mNode.Name)) then
    begin
      Result := mNode.Name + cTexts[TInliningText.ChangesBeforeOnePlace].Text;
    end;
  end;
end;

function TVariableInliner.OrderIssue(ARead: TSyntaxNode): string;
begin
  Result := '';
  if (Volatile or SideEffects) and (TInlineSyntax.InLoopWithout(ARead, Definition, Body) or
    ChangesBetween(Body, Locals, Definition.EndOffset, ARead.StartOffset, Source, Options.Lookup)) then
  begin
    Result := cTexts[TInliningText.InBetweenTheValueOf].Text;
  end
  else if SideEffects and (not EvaluatedOnce(ARead) or ReadsBetween(Body, Definition.EndOffset,
    ARead.StartOffset)) then
  begin
    Result := cTexts[TInliningText.TheExpressionHasSideEffects2].Text;
  end;
end;

{ TInlineRefactoring }

class function TInlineRefactoring.InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := InlineVariable(ASource, APosition, AOptions, AAction, mReason);
end;

class function TInlineRefactoring.InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions; out AAction: TCodeAction; out AReason: string): Boolean;
var
  mInliner: TVariableInliner;
begin
  AAction := Default(TCodeAction);
  mInliner := TVariableInliner.Create(ASource, AOptions);
  AReason := mInliner.Execute(APosition);
  Result := AReason = '';
  if Result then
  begin
    AAction := mInliner.Action;
  end;
end;

class function TInlineRefactoring.CallAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out ACall: TInlineCall): Boolean;
begin
  Result := TInlineSyntax.CallAt(ATree, AText, APosition, ACall);
end;

class function TInlineRefactoring.FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
begin
  Result := TInlineSyntax.FindRoutines(ATree, AName);
end;

class function TInlineRefactoring.InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
  const ACallee: TInlineCallee; const AOptions: TInlineOptions; out AAction: TCodeAction;
  out AReason: string): Boolean;
begin
  Result := TMethodInlining.Run(ACaller, APosition, ACallee, AOptions, AAction, AReason);
end;

class function TInlineRefactoring.InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
  const ACallee: TInlineCallee; const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean;
var
  mReason: string;
begin
  Result := InlineMethod(ACaller, APosition, ACallee, AOptions, AAction, mReason);
end;

class function TInlineRefactoring.Actions(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions): TArray<TCodeAction>;
var
  mAction: TCodeAction;
  mCall: TInlineCall;
  mRoutines: TArray<TSyntaxNode>;
begin
  Result := nil;
  if InlineVariable(ASource, APosition, AOptions, mAction) then
  begin
    Result := Result + [mAction];
  end;
  if TInlineSyntax.CallAt(ASource.Tree, ASource.Text, APosition, mCall) then
  begin
    mRoutines := TInlineSyntax.FindRoutines(ASource.Tree, mCall.Name);
    if (Length(mRoutines) = 1) and InlineMethod(ASource, APosition, TInlineCallee.Create(ASource, mRoutines[0]),
      AOptions, mAction) then
    begin
      Result := Result + [mAction];
    end;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Editing.Inlining', cTexts);

end.
