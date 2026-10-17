unit Atlas.Common.Editing.Inline;

// Einbetten (#103, Teil A) als Code-Aktionen, ohne Protokollbezug:
//   - „Variable einbetten“: Eine lokale Variable mit genau einer Zuweisung
//     (bzw. eine Inline-Variable mit Startwert) verschwindet; jedes Lesen
//     bekommt den Ausdruck, bei Bedarf in Klammern. Der Datenfluss muss
//     zeigen, dass jedes Lesen genau diese Zuweisung sieht und die lokalen
//     Namen des Ausdrucks dort denselben Wert haben. Liest der Ausdruck
//     Felder, globale Namen oder Speicher, darf dazwischen nichts aufgerufen
//     und nichts außer lokalen Variablen geschrieben werden; hat er
//     Seiteneffekte (Aufrufe), darf er nur einmal und ohne Lesen davor
//     gebraucht werden.
//   - „Methode einbetten“: Der Aufruf an der Einfügemarke wird durch den
//     Rumpf ersetzt. Lokale Namen der Methode bekommen eindeutige Namen;
//     Parameter werden durch die Argumente ersetzt, wenn das die Bedeutung
//     nicht ändert, sonst durch Hilfsvariablen; Mitglieder bekommen den
//     Empfänger des Aufrufs. Ein Ergebnis aus einer einzigen Zuweisung
//     ersetzt den Aufruf direkt, sonst trägt es eine Variable <Name>Result.
//     Erlaubt sind ein Exit als letzte Anweisung und ein „if … then Exit“
//     auf oberster Ebene; daraus wird ein if mit else.
// Namensauflösung bringt der Aufrufer über TInlineOptions.Lookup mit: Sie
// sagt, ob ein Name ein Mitglied oder eine Routine ist und ob er am Aufruf
// dasselbe bedeutet wie in der Methode.
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
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.CodeActions;

const
  /// <summary>Art der Einbetten-Aktionen (LSP).</summary>
  InlineKind = 'refactor.inline';

type
{$SCOPEDENUMS ON}
  TInlineVisibility = (Public, Protected, StrictProtected, Private, StrictPrivate);
{$SCOPEDENUMS OFF}

  /// <summary>Bedeutung eines Namens laut Namensauflösung.</summary>
  TInlineMeaning = record
    Found: Boolean;
    /// <summary>Kennung der Deklaration: gleich, wenn zwei Stellen dasselbe meinen.</summary>
    Key: string;
    /// <summary>Feld, Methode oder Eigenschaft eines Typs.</summary>
    IsMember: Boolean;
    /// <summary>Routine oder Methode: Ein Zugriff ruft auf.</summary>
    IsRoutine: Boolean;
    /// <summary>Typ: Ein Aufruf ist eine Typumwandlung.</summary>
    IsType: Boolean;
    /// <summary>Typ des Mitglieds; '' sonst.</summary>
    Container: string;
    Visibility: TInlineVisibility;
  end;

  /// <summary>Bedeutung der Kette ANames (A.B.C), wie sie in ATree (Datei AFileName) an AOffset stünde.</summary>
  TInlineLookup = reference to function(ATree: TSyntaxTree; const AFileName: string;
    const ANames: TArray<string>; AOffset: Integer): TInlineMeaning;

  /// <summary>Eine Datei mit Text und Syntaxbaum.</summary>
  TInlineSource = record
    FileName: string;
    Text: string;
    Tree: TSyntaxTree;
    class function Create(const AFileName, AText: string; ATree: TSyntaxTree): TInlineSource; static;
  end;

  TInlineOptions = record
    /// <summary>Inline-Variablen erzeugen (Einstellung und Sprachversion).</summary>
    InlineVar: Boolean;
    Style: TFormatStyle;
    /// <summary>Namensauflösung; nil: alle fremden Namen gelten als gleich und nicht als Mitglieder.</summary>
    Lookup: TInlineLookup;
    class function Default: TInlineOptions; static;
  end;

  /// <summary>Aufruf an der Einfügemarke.</summary>
  TInlineCall = record
    /// <summary>Kurzer Name der aufgerufenen Routine.</summary>
    Name: string;
    NameOffset: Integer;
    NamePos: TTextPosition;
    /// <summary>Identifier bzw. MemberAccess mit dem Namen.</summary>
    Callee: TSyntaxNode;
    /// <summary>Ausdruck, den der Rumpf ersetzt: Call oder der Name selbst (ohne Klammern).</summary>
    Node: TSyntaxNode;
    /// <summary>Qualifizierer vor dem Namen; nil ohne.</summary>
    Receiver: TSyntaxNode;
    Arguments: TArray<TSyntaxNode>;
    /// <summary>CallStatement, wenn der Aufruf die ganze Anweisung ist; nil im Ausdruck.</summary>
    Statement: TSyntaxNode;
  end;

  TInlineRefactoring = class
  public const
    ResultSuffix = 'Result';
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
    /// <summary>„Methode einbetten“ für den Aufruf an APosition in ACaller; ARoutine ist der Rumpf in ACallee
    /// (dieselbe Datei oder eine andere). False mit Grund in AReason.</summary>
    class function InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
      const ACallee: TInlineSource; ARoutine: TSyntaxNode; const AOptions: TInlineOptions;
      out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    class function InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
      const ACallee: TInlineSource; ARoutine: TSyntaxNode; const AOptions: TInlineOptions;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>„Variable einbetten“ und, wenn der Rumpf eindeutig in derselben Datei steht, „Methode
    /// einbetten“ für APosition.</summary>
    class function Actions(const ASource: TInlineSource; const APosition: TTextPosition;
      const AOptions: TInlineOptions): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.StrUtils,
  System.Generics.Collections,
  System.Generics.Defaults,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals;

const
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  CompoundKinds = [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr, TSyntaxKind.RangeExpr];
  /// <summary>Standardroutinen ohne Seiteneffekte.</summary>
  PureRoutines: array[0..27] of string = ('Abs', 'Assigned', 'Chr', 'Copy', 'Frac', 'High', 'Int', 'IntToStr',
    'Length', 'Low', 'LowerCase', 'Max', 'Min', 'Odd', 'Ord', 'Pos', 'Pred', 'Round', 'SameText', 'SizeOf', 'Sqr',
    'Sqrt', 'Succ', 'Trim', 'Trunc', 'UpperCase', 'Format', 'FloatToStr');
  /// <summary>Bezeichner, die wie Literale nie ihren Wert ändern.</summary>
  ConstantNames: array[0..2] of string = ('True', 'False', 'MaxInt');

type
  TLocal = TRoutineLocal;
  TLocalKind = TRoutineLocalKind;

  /// <summary>Ersetzung im Text der Methode: Offsets Start..Finish (exklusiv) werden zu Text.</summary>
  TReplacement = record
    Start: Integer;
    Finish: Integer;
    Text: string;
  end;

  TParameterInfo = record
    Name: string;
    Modifier: TParameterModifier;
    TypeText: string;
    TypeNode: TSyntaxNode;
    DefaultValue: TSyntaxNode;
  end;

{ TInlineSource }

class function TInlineSource.Create(const AFileName, AText: string; ATree: TSyntaxTree): TInlineSource;
begin
  Result.FileName := AFileName;
  Result.Text := AText;
  Result.Tree := ATree;
end;

{ TInlineOptions }

class function TInlineOptions.Default: TInlineOptions;
begin
  Result.InlineVar := True;
  Result.Style := TFormatStyle.Default;
  Result.Lookup := nil;
end;

{ Gemeinsames }

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

/// <summary>Bezeichner-Token, in dem oder direkt hinter dem AOffset liegt; -1 ohne.</summary>
function TokenContaining(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Index: Integer;
begin
  Index := TRoutineBody.TokenAt(ATokens, AOffset);
  if (Index <= High(ATokens)) and (ATokens[Index].Offset = AOffset) and
    (ATokens[Index].Kind = TPascalTokenKind.Identifier) then
    Exit(Index);
  if (Index > 0) and (Index - 1 <= High(ATokens)) and
    (ATokens[Index - 1].Offset + Length(ATokens[Index - 1].Text) >= AOffset) and
    (ATokens[Index - 1].Kind = TPascalTokenKind.Identifier) then
    Exit(Index - 1);
  Result := -1;
end;

/// <summary>Identifier bzw. MemberAccess, dessen Name AOffset..AEnd belegt; nil ohne.</summary>
function NameNodeAt(ANode: TSyntaxNode; AOffset, AEnd: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  if (ANode.StartOffset > AOffset) or (ANode.EndOffset < AEnd) then
    Exit;
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    Result := NameNodeAt(ANode[Index], AOffset, AEnd);
    if Result <> nil then
      Exit;
  end;
  if ((ANode.Kind = TSyntaxKind.Identifier) and (ANode.StartOffset = AOffset) and (ANode.EndOffset = AEnd)) or
    ((ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.EndOffset = AEnd) and
    (AEnd - Length(ANode.Name) = AOffset)) then
    Result := ANode;
end;

/// <summary>Innerste Routine mit Rumpf, deren Deklaration AOffset enthält (auch var-Abschnitt); nil ohne.</summary>
function RoutineContaining(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Inner: TSyntaxNode;
begin
  Result := nil;
  for Index := 0 to ANode.ChildCount - 1 do
    if (ANode[Index].StartOffset <= AOffset) and (AOffset < ANode[Index].EndOffset) then
    begin
      if (ANode[Index].Kind = TSyntaxKind.RoutineDecl) and (TRoutineBody.BodyOf(ANode[Index]) <> nil) then
        Result := ANode[Index];
      Inner := RoutineContaining(ANode[Index], AOffset);
      if Inner <> nil then
        Result := Inner;
      Exit;
    end;
end;

function IsSimpleChain(ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Identifier:
      Result := True;
    TSyntaxKind.MemberAccess:
      Result := IsSimpleChain(ANode[0]);
  else
    Result := False;
  end;
end;

function ChainNames(ANode: TSyntaxNode): TArray<string>;
begin
  if ANode.Kind = TSyntaxKind.MemberAccess then
    Result := ChainNames(ANode[0]) + [ANode.Name]
  else
    Result := [ANode.Name];
end;

/// <summary>Muss ein zusammengesetzter Ausdruck AExpression an der Stelle ATarget in Klammern?</summary>
function NeedsParens(AExpression, ATarget: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Result := False;
  if not (AExpression.Kind in CompoundKinds) then
    Exit;
  Parent := ATarget.Parent;
  if Parent = nil then
    Exit;
  case Parent.Kind of
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.MemberAccess, TSyntaxKind.Dereference,
    TSyntaxKind.AddressOf:
      Result := True;
    TSyntaxKind.IndexAccess, TSyntaxKind.Call:
      Result := Parent[0] = ATarget;
  end;
end;

function Parenthesized(const AText: string; AExpression, ATarget: TSyntaxNode): string;
begin
  if NeedsParens(AExpression, ATarget) then
    Result := '(' + AText + ')'
  else
    Result := AText;
end;

/// <summary>Bezeichner ist der aufgerufene Name eines Aufrufs.</summary>
function IsCallee(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Parent <> nil) and (((ANode.Parent.Kind = TSyntaxKind.Call) and (ANode.Parent[0] = ANode)) or
    (ANode.Parent.Kind = TSyntaxKind.CallStatement));
end;

function Meaning(const ALookup: TInlineLookup; const ASource: TInlineSource; const ANames: TArray<string>;
  AOffset: Integer): TInlineMeaning;
begin
  Result := Default(TInlineMeaning);
  if Assigned(ALookup) then
    Result := ALookup(ASource.Tree, ASource.FileName, ANames, AOffset);
end;

/// <summary>Aufruf ohne Seiteneffekte: Standardroutine der Liste oder Typumwandlung.</summary>
function CallIsPure(ACall: TSyntaxNode; const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  Callee: TSyntaxNode;
  Found: TInlineMeaning;
begin
  Callee := ACall[0];
  if (Callee.Kind = TSyntaxKind.Identifier) and MatchText(Callee.Name, PureRoutines) then
    Exit(True);
  Result := False;
  if Assigned(ALookup) and IsSimpleChain(Callee) then
  begin
    Found := Meaning(ALookup, ASource, ChainNames(Callee), Callee.StartOffset);
    Result := Found.Found and Found.IsType;
  end;
end;

/// <summary>Hat der Ausdruck Seiteneffekte: Aufrufe außer reinen, inherited, Routinen ohne Klammern?</summary>
function HasSideEffects(ANode: TSyntaxNode; const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Found: TInlineMeaning;
begin
  if TRoutineLocals.HasKind(ANode, TSyntaxKind.InheritedExpr) or
    TRoutineLocals.HasKind(ANode, TSyntaxKind.AnonymousMethod) then
    Exit(True);
  Result := False;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Call, Nodes);
    for Node in Nodes do
      if not CallIsPure(Node, ASource, ALookup) then
        Exit(True);
    if not Assigned(ALookup) then
      Exit;
    // Routinen ohne Klammern und Methoden über eine Kette (A.Next) rufen auch auf.
    Nodes.Clear;
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Identifier, Nodes);
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.MemberAccess, Nodes);
    for Node in Nodes do
      if not IsCallee(Node) and IsSimpleChain(Node) then
      begin
        Found := Meaning(ALookup, ASource, ChainNames(Node), Node.StartOffset);
        if Found.Found and Found.IsRoutine then
          Exit(True);
      end;
  finally
    Nodes.Free;
  end;
end;

function NextSignificant(const ATokens: TArray<TPascalToken>; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and (ATokens[Result].Kind in [TPascalTokenKind.Comment,
    TPascalTokenKind.Directive]) do
    Inc(Result);
end;

/// <summary>Anweisung samt ";" entfernen; steht sie allein auf ihren Zeilen, die ganzen Zeilen.</summary>
function RemoveStatement(const AText: string; ATree: TSyntaxTree; AStatement: TSyntaxNode): TTextEdit;
var
  Tokens: TArray<TPascalToken>;
  Index, EndOffset, Line: Integer;
  Lines: TLineTable;
  EndPos: TTextPosition;
  Before, After: string;
begin
  Tokens := ATree.Tokens;
  EndOffset := AStatement.EndOffset;
  Index := NextSignificant(Tokens, TRoutineBody.TokenAt(Tokens, AStatement.EndOffset));
  if (Index <= High(Tokens)) and Tokens[Index].IsSymbol(';') then
    EndOffset := Tokens[Index].Offset + 1;
  Lines := TLineTable.Build(AText);
  EndPos := Lines.PositionAt(EndOffset);
  Line := AStatement.StartPos.Line;
  Before := Copy(AText, Lines.LineStart(Line) + 1, AStatement.StartOffset - Lines.LineStart(Line));
  After := Copy(AText, EndOffset + 1, Lines.LineContentEnd(EndPos.Line) - EndOffset);
  if (Trim(Before) = '') and (Trim(After) = '') then
    Result := TTextEdit.Create(TTextRange.Create(Line, 0, EndPos.Line + 1, 0), '')
  else
    Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, EndPos), '');
end;

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
    Exit(False);
  for Node in A do
  begin
    Found := False;
    for Other in B do
      if Other = Node then
        Found := True;
    if not Found then
      Exit(False);
  end;
  Result := True;
end;

function SameReaching(const A, B: TReachingDefinitions): Boolean;
begin
  Result := (A.FromEntry = B.FromEntry) and (A.MaybeFromEntry = B.MaybeFromEntry) and
    SameNodes(A.Definitions, B.Definitions) and SameNodes(A.Uncertain, B.Uncertain);
end;

/// <summary>Liegt ANode in einer Schleife (bis ABody), die AOther nicht enthält?</summary>
function InLoopWithout(ANode, AOther, ABody: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> ABody) do
  begin
    if (Node.Kind in LoopKinds) and not TRoutineBody.Within(AOther, Node) then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

function Inside(ANode: TSyntaxNode; AKind: TSyntaxKind; AStop: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> AStop) do
  begin
    if Node.Kind = AKind then
      Exit(True);
    Node := Node.Parent;
  end;
  Result := False;
end;

{ Variable einbetten }

/// <summary>Ausdruck nur aus Literalen, lokalen Namen, Operatoren und reinen Aufrufen darauf.</summary>
function LocalOnly(ANode: TSyntaxNode; const ALocals: TArray<TLocal>): Boolean;
var
  Index, First: Integer;
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      Exit(True);
    TSyntaxKind.Identifier:
      Exit((TRoutineLocals.IndexOf(ALocals, ANode.Name, ANode.StartOffset) >= 0) or
        MatchText(ANode.Name, ConstantNames));
    TSyntaxKind.Call:
      begin
        if (ANode[0].Kind <> TSyntaxKind.Identifier) or not MatchText(ANode[0].Name, PureRoutines) then
          Exit(False);
        First := 1;
      end;
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr, TSyntaxKind.SetConstructor,
    TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr:
      First := 0;
  else
    Exit(False);
  end;
  for Index := First to ANode.ChildCount - 1 do
    if not LocalOnly(ANode[Index], ALocals) then
      Exit(False);
  Result := True;
end;

/// <summary>Wird zwischen AFrom und ATo etwas aufgerufen oder außer lokalen Variablen etwas geschrieben?</summary>
function ChangesBetween(ABody: TSyntaxNode; const ALocals: TArray<TLocal>; AFrom, ATo: Integer;
  const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  Nodes: TList<TSyntaxNode>;
  Node: TSyntaxNode;
  Kind: TSyntaxKind;
begin
  Result := False;
  Nodes := TList<TSyntaxNode>.Create;
  try
    for Kind in [TSyntaxKind.Call, TSyntaxKind.CallStatement, TSyntaxKind.InheritedExpr,
      TSyntaxKind.RaiseStatement, TSyntaxKind.AssignStatement] do
      TRoutineLocals.CollectKind(ABody, Kind, Nodes);
    for Node in Nodes do
      if (Node.StartOffset >= AFrom) and (Node.EndOffset <= ATo) then
        case Node.Kind of
          TSyntaxKind.Call:
            if not CallIsPure(Node, ASource, ALookup) then
              Exit(True);
          TSyntaxKind.CallStatement:
            if (Node.ChildCount = 0) or (Node[0].Kind <> TSyntaxKind.Call) then
              Exit(True);
          TSyntaxKind.AssignStatement:
            if (Node[0].Kind <> TSyntaxKind.Identifier) or
              (TRoutineLocals.IndexOf(ALocals, Node[0].Name, Node[0].StartOffset) < 0) then
              Exit(True);
        else
          Exit(True);
        end;
  finally
    Nodes.Free;
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
      if (Node.StartOffset >= AFrom) and (Node.EndOffset <= ATo) and not IsCallee(Node) and
        not ((Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] = Node)) then
        Exit(True);
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
      Exit;
    if (Node.Kind = TSyntaxKind.BinaryExpr) and (Child <> Node[0]) and (SameText(Node.Name, 'and') or
      SameText(Node.Name, 'or')) then
      Exit;
    if Node.Kind = TSyntaxKind.CaseItem then
      Exit;
    Child := Node;
    Node := Node.Parent;
  end;
  Result := (Node <> nil) and not (Node.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]);
end;

function UsesName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Index: Integer;
begin
  if (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, AName) then
    Exit(True);
  for Index := 0 to ANode.ChildCount - 1 do
    if UsesName(ANode[Index], AName) then
      Exit(True);
  Result := False;
end;

class function TInlineRefactoring.InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions; out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := InlineVariable(ASource, APosition, AOptions, AAction, Reason);
end;

class function TInlineRefactoring.InlineVariable(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions; out AAction: TCodeAction; out AReason: string): Boolean;
var
  Tree: TSyntaxTree;
  Tokens: TArray<TPascalToken>;
  Token, Offset, LocalIndex, Index, Inner: Integer;
  Name, ExprText: string;
  Routine, Body, Node, Definition, Expression, Read: TSyntaxNode;
  Locals: TArray<TLocal>;
  Local: TLocal;
  Nodes: TList<TSyntaxNode>;
  Reads, ExprNames: TArray<TSyntaxNode>;
  Graph: TControlFlowGraph;
  DefNode, ReadNode: TFlowNode;
  Reaching, AtDef, AtRead: TReachingDefinitions;
  Volatile, SideEffects: Boolean;
  Edits: TArray<TTextEdit>;
  Flow: TFlowSignatureLookup;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Tree := ASource.Tree;
  if (Tree = nil) or (Tree.Root = nil) then
    Exit(Fail('kein Syntaxbaum', AReason));
  Tokens := Tree.Tokens;
  Offset := TLineTable.Build(ASource.Text).OffsetAt(APosition);
  Token := TokenContaining(Tokens, Offset);
  if Token < 0 then
    Exit(Fail('kein Bezeichner', AReason));
  Name := Tokens[Token].Text;
  Offset := Tokens[Token].Offset;
  Routine := RoutineContaining(Tree.Root, Offset);
  if Routine = nil then
    Exit(Fail('nicht in einer Routine', AReason));
  Body := TRoutineBody.BodyOf(Routine);
  Locals := TRoutineLocals.Collect(ASource.Text, Tree, Routine);
  LocalIndex := -1;
  if Offset < Body.StartOffset then
  begin
    // Name im var-Abschnitt.
    for Index := 0 to High(Locals) do
      if (Locals[Index].Kind = TLocalKind.Variable) and SameText(Locals[Index].Name, Name) and
        (Locals[Index].Decl.StartOffset <= Offset) and (Offset < Locals[Index].Decl.EndOffset) then
        LocalIndex := Index;
  end
  else
    LocalIndex := TRoutineLocals.IndexOf(Locals, Name, Offset);
  if LocalIndex < 0 then
    Exit(Fail(Name + ' ist keine lokale Variable', AReason));
  Local := Locals[LocalIndex];
  if not (Local.Kind in [TLocalKind.Variable, TLocalKind.InlineVariable]) then
    Exit(Fail('nur lokale Variablen', AReason));
  if Local.Decl.Kind = TSyntaxKind.InlineConst then
    Exit(Fail('Konstante', AReason));
  if (Local.Kind = TLocalKind.InlineVariable) and (Pos(',', Local.Decl.Name) > 0) then
    Exit(Fail('mehrere Namen in einer Deklaration', AReason));
  Name := Local.Name;
  // Verschachtelte Routinen sehen die Variable auch.
  if Local.Kind = TLocalKind.Variable then
    for Index := 0 to Routine.ChildCount - 1 do
      if (Routine[Index].Kind = TSyntaxKind.RoutineDecl) and UsesName(Routine[Index], Name) then
        Exit(Fail(Name + ' wird in einer verschachtelten Routine verwendet', AReason));
  Definition := nil;
  Expression := nil;
  if (Local.Kind = TLocalKind.InlineVariable) and (Local.Decl.ChildCount > 0) and
    not (Local.Decl[Local.Decl.ChildCount - 1].Kind in TRoutineLocals.TypeKinds) then
  begin
    Definition := Local.Decl;
    Expression := Local.Decl[Local.Decl.ChildCount - 1];
  end;
  Reads := nil;
  Flow := TFlowSignatures.FromTree(Tree.Root);
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.ForStatement, Nodes);
    for Node in Nodes do
      if SameText(Node.Name, Name) and not TRoutineLocals.IsInlineFor(Tokens, Node) and
        (TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset) = LocalIndex) then
        Exit(Fail(Name + ' ist Laufvariable', AReason));
    Nodes.Clear;
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
    begin
      if not SameText(Node.Name, Name) or (TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset) <>
        LocalIndex) then
        Continue;
      if Inside(Node, TSyntaxKind.AnonymousMethod, Body) then
        Exit(Fail(Name + ' wird in einer anonymen Methode verwendet', AReason));
      if Inside(Node, TSyntaxKind.WithStatement, Body) then
        Exit(Fail(Name + ' steht in einem with-Rumpf', AReason));
      case TRoutineLocals.AccessOf(Node, Flow) of
        TLocalAccess.Read:
          Reads := Reads + [Node];
        TLocalAccess.Write:
          begin
            if Definition <> nil then
              Exit(Fail(Name + ' wird mehrfach zugewiesen', AReason));
            Definition := Node.Parent;
            Expression := Definition[1];
          end;
      else
        Exit(Fail(Name + ' wird verändert', AReason));
      end;
    end;
  finally
    Nodes.Free;
  end;
  if Definition = nil then
    Exit(Fail(Name + ' bekommt keinen Wert', AReason));
  if Reads = nil then
    Exit(Fail(Name + ' wird nie gelesen', AReason));
  if not TRoutineBody.InList(Definition) then
    Exit(Fail('die Zuweisung steht nicht in einer Anweisungsliste', AReason));
  if Inside(Definition, TSyntaxKind.WithStatement, Body) then
    Exit(Fail('die Zuweisung steht in einem with-Rumpf', AReason));
  if UsesName(Expression, Name) then
    Exit(Fail('der Ausdruck enthält ' + Name, AReason));
  // Klammern um den ganzen Ausdruck braucht der eingesetzte Text nicht doppelt.
  if (Expression.Kind = TSyntaxKind.ParenExpr) and (Expression.ChildCount = 1) then
    Expression := Expression[0];
  Volatile := not LocalOnly(Expression, Locals);
  SideEffects := HasSideEffects(Expression, ASource, AOptions.Lookup);
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Expression, TSyntaxKind.Identifier, Nodes);
    ExprNames := Nodes.ToArray;
  finally
    Nodes.Free;
  end;
  // Adresse eines Namens genommen: Er kann sich über den Zeiger ändern.
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(Body, TSyntaxKind.AddressOf, Nodes);
    for Node in Nodes do
      for Read in ExprNames do
        if UsesName(Node, Read.Name) then
          Volatile := True;
  finally
    Nodes.Free;
  end;
  if SideEffects and (Length(Reads) > 1) then
    Exit(Fail('der Ausdruck hat Seiteneffekte und wird mehrfach gelesen', AReason));
  Graph := TControlFlowGraph.Build(Routine, Flow);
  try
    if not Graph.Complete then
      Exit(Fail('asm oder Syntaxfehler in der Routine', AReason));
    DefNode := Graph.NodeOf(Definition);
    if DefNode = nil then
      Exit(Fail('Zuweisung nicht im Ablauf', AReason));
    for Read in Reads do
    begin
      ReadNode := FlowNodeAt(Graph, Read);
      if ReadNode = nil then
        Exit(Fail('Lesen nicht im Ablauf', AReason));
      Reaching := Graph.ReachingDefinitions(ReadNode, Name);
      if (Length(Reaching.Definitions) <> 1) or (Reaching.Definitions[0] <> DefNode) or Reaching.FromEntry or
        Reaching.MaybeFromEntry or (Reaching.Uncertain <> nil) then
        Exit(Fail('an einer Stelle kommt ein anderer Wert von ' + Name + ' an', AReason));
      // Lokale Namen des Ausdrucks: am Lesen sichtbar und mit demselben Wert wie bei der Zuweisung.
      for Node in ExprNames do
      begin
        Index := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
        if Index < 0 then
          Continue;
        Inner := TRoutineLocals.IndexOf(Locals, Node.Name, Read.StartOffset);
        if Inner <> Index then
          Exit(Fail(Node.Name + ' ist an einer Stelle nicht sichtbar', AReason));
        if Locals[Index].Kind = TLocalKind.Constant then
          Continue;
        AtDef := Graph.ReachingDefinitions(DefNode, Node.Name);
        AtRead := Graph.ReachingDefinitions(ReadNode, Node.Name);
        if not SameReaching(AtDef, AtRead) then
          Exit(Fail(Node.Name + ' ändert sich vor einer Stelle', AReason));
      end;
      if (Volatile or SideEffects) and (InLoopWithout(Read, Definition, Body) or
        ChangesBetween(Body, Locals, Definition.EndOffset, Read.StartOffset, ASource, AOptions.Lookup)) then
        Exit(Fail('dazwischen kann sich der Wert des Ausdrucks ändern', AReason));
      if SideEffects and (not EvaluatedOnce(Read) or
        ReadsBetween(Body, Definition.EndOffset, Read.StartOffset)) then
        Exit(Fail('der Ausdruck hat Seiteneffekte; die Reihenfolge änderte sich', AReason));
    end;
  finally
    Graph.Free;
  end;
  ExprText := TRoutineBody.TextOf(ASource.Text, Expression);
  Edits := nil;
  for Read in Reads do
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Read.StartPos, Read.EndPos),
      Parenthesized(ExprText, Expression, Read))];
  Edits := Edits + [RemoveStatement(ASource.Text, Tree, Definition)];
  if Local.Kind = TLocalKind.Variable then
    TRoutineLocals.RemoveVariables(ASource.Text, Tree, Local.Decl, [Name], Edits)
  else if Definition <> Local.Decl then
    Edits := Edits + [RemoveStatement(ASource.Text, Tree, Local.Decl)];
  AAction.Title := Format('Variable %s einbetten', [Name]);
  AAction.Kind := InlineKind;
  AAction.Edits := Edits;
  Result := True;
end;

{ Methode einbetten }

class function TInlineRefactoring.CallAt(ATree: TSyntaxTree; const AText: string; const APosition: TTextPosition;
  out ACall: TInlineCall): Boolean;
var
  Tokens: TArray<TPascalToken>;
  Token, Offset, Index: Integer;
  Routine, Body, Name, Parent: TSyntaxNode;
begin
  ACall := Default(TInlineCall);
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Tokens := ATree.Tokens;
  Offset := TLineTable.Build(AText).OffsetAt(APosition);
  Token := TokenContaining(Tokens, Offset);
  if Token < 0 then
    Exit;
  Routine := TRoutineBody.RoutineAt(ATree, Tokens[Token].Offset);
  if Routine = nil then
    Exit;
  Body := TRoutineBody.BodyOf(Routine);
  Name := NameNodeAt(Body, Tokens[Token].Offset, Tokens[Token].Offset + Length(Tokens[Token].Text));
  if Name = nil then
    Exit;
  Parent := Name.Parent;
  // Qualifizierer (Foo in Foo.Bar), Ziel einer Zuweisung und @Foo sind keine Aufrufe.
  if (Parent = nil) or ((Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Parent[0] = Name)) or (Parent.Kind = TSyntaxKind.AddressOf) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Name)) then
    Exit;
  ACall.Name := Name.Name;
  ACall.NameOffset := Tokens[Token].Offset;
  ACall.NamePos := Tokens[Token].StartPos;
  ACall.Callee := Name;
  ACall.Node := Name;
  if Name.Kind = TSyntaxKind.MemberAccess then
    ACall.Receiver := Name[0];
  if (Parent.Kind = TSyntaxKind.Call) and (Parent[0] = Name) then
  begin
    ACall.Node := Parent;
    for Index := 1 to Parent.ChildCount - 1 do
      ACall.Arguments := ACall.Arguments + [Parent[Index]];
  end;
  if (ACall.Node.Parent <> nil) and (ACall.Node.Parent.Kind = TSyntaxKind.CallStatement) then
    ACall.Statement := ACall.Node.Parent;
  Result := True;
end;

procedure CollectRoutines(ANode: TSyntaxNode; const AName: string; AList: TList<TSyntaxNode>);
var
  Index: Integer;
  Short: string;
begin
  for Index := 0 to ANode.ChildCount - 1 do
    if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
    begin
      Short := ANode[Index].Name;
      if (Pos('.', AName) = 0) and (Pos('.', Short) > 0) then
        Short := Short.Substring(Short.LastIndexOf('.') + 1);
      if SameText(Short, AName) and (TRoutineBody.BodyOf(ANode[Index]) <> nil) then
        AList.Add(ANode[Index]);
    end
    else if ANode[Index].Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.InterfaceSection] then
      CollectRoutines(ANode[Index], AName, AList);
end;

class function TInlineRefactoring.FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  List := TList<TSyntaxNode>.Create;
  try
    CollectRoutines(ATree.Root, AName, List);
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

function RoutineKeyword(const ATokens: TArray<TPascalToken>; ARoutine: TSyntaxNode): string;
var
  Index: Integer;
begin
  Index := NextSignificant(ATokens, TRoutineBody.TokenAt(ATokens, ARoutine.StartOffset));
  if (Index <= High(ATokens)) and ATokens[Index].IsKeyword('class') then
    Index := NextSignificant(ATokens, Index + 1);
  Result := '';
  if Index <= High(ATokens) then
    Result := LowerCase(ATokens[Index].Text);
end;

function Render(const AText: string; AReplacements: TList<TReplacement>; AStart, AFinish: Integer): string;
var
  Position: Integer;
  Replacement: TReplacement;
begin
  Result := '';
  Position := AStart;
  for Replacement in AReplacements do
    if (Replacement.Start >= Position) and (Replacement.Finish <= AFinish) then
    begin
      Result := Result + Copy(AText, Position + 1, Replacement.Start - Position) + Replacement.Text;
      Position := Replacement.Finish;
    end;
  Result := Result + Copy(AText, Position + 1, AFinish - Position);
end;

/// <summary>Anweisungen untereinander mit AIndent; die erste ohne, wenn AFirst False ist.</summary>
function JoinStatements(const ALines: TArray<string>; const AIndent, ALineBreak: string; AFirst: Boolean): string;
var
  Index: Integer;
  Piece: string;
begin
  Result := '';
  for Index := 0 to High(ALines) do
  begin
    Piece := TRoutineBody.Reindent(ALines[Index], '', AIndent, ALineBreak);
    if (Index = 0) and not AFirst then
      Piece := Copy(Piece, Length(AIndent) + 1, MaxInt);
    if Index > 0 then
      Result := Result + ';' + ALineBreak;
    Result := Result + Piece;
  end;
end;

/// <summary>Einträge im var- bzw. const-Abschnitt der Routine als eine Bearbeitung.</summary>
function SectionEdit(const AText: string; ARoutine: TSyntaxNode; AConstants: Boolean;
  const AEntries: TArray<string>; const AStyle: TFormatStyle): TTextEdit;
const
  Marker = #1;
var
  Placeholder, Indent, Entries, LineBreak: string;
  Start, Index: Integer;
begin
  if AConstants then
  begin
    Result := TRoutineBody.AddConstant(AText, ARoutine, Marker, Marker, AStyle);
    Placeholder := Marker + ' = ' + Marker + ';';
  end
  else
  begin
    Result := TRoutineBody.AddVariable(AText, ARoutine, Marker, Marker, AStyle);
    Placeholder := Marker + ': ' + Marker + ';';
  end;
  LineBreak := TTextLines.LineBreakOf(AText);
  Start := Pos(Placeholder, Result.NewText);
  Index := Start - 1;
  while (Index > 0) and (Result.NewText[Index] <> #10) do
    Dec(Index);
  Indent := Copy(Result.NewText, Index + 1, Start - Index - 1);
  Entries := AEntries[0];
  for Index := 1 to High(AEntries) do
    Entries := Entries + LineBreak + Indent + AEntries[Index];
  Result.NewText := StringReplace(Result.NewText, Placeholder, Entries, []);
end;

function Negated(const AText: string; ACondition: TSyntaxNode): string;
begin
  if ACondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Call, TSyntaxKind.MemberAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.IndexAccess, TSyntaxKind.Literal] then
    Result := 'not ' + AText
  else
    Result := 'not (' + AText + ')';
end;

class function TInlineRefactoring.InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
  const ACallee: TInlineSource; ARoutine: TSyntaxNode; const AOptions: TInlineOptions;
  out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := InlineMethod(ACaller, APosition, ACallee, ARoutine, AOptions, AAction, Reason);
end;

class function TInlineRefactoring.InlineMethod(const ACaller: TInlineSource; const APosition: TTextPosition;
  const ACallee: TInlineSource; ARoutine: TSyntaxNode; const AOptions: TInlineOptions;
  out AAction: TCodeAction; out AReason: string): Boolean;
type
  TExitMode = (NoExit, LastExit, GuardExit);
var
  Call: TInlineCall;
  CalleeTokens, CallerTokens: TArray<TPascalToken>;
  Keyword, ShortName, CalleeClass, CallerClass, ReceiverText, ResultName, ResultType, LineBreak, Indent, Unit_,
    Text, Condition, NewText, Replacement: string;
  Header, CalleeBody, CallerRoutine, CallerBody, Outer, Node, ExitStatement, ExitValue, Guard, Host, Argument,
    SimpleExpression, ReturnType: TSyntaxNode;
  IsFunction, IsMethod, Mutates, Written, Pure, Stable, Simple, InLoop: Boolean;
  Locals, CallerLocals: TArray<TLocal>;
  Parameters: TArray<TParameterInfo>;
  Parameter: TParameterInfo;
  NewNames: TArray<string>;
  ParameterText: TArray<string>;
  Nodes, Exits, Occurrences: TList<TSyntaxNode>;
  Replacements: TList<TReplacement>;
  Taken: TDictionary<string, Boolean>;
  Graph: TControlFlowGraph;
  ExitMode: TExitMode;
  Lines, RestLines, VarEntries, ConstEntries, ArgumentNames: TArray<string>;
  Statements: TArray<TSyntaxNode>;
  Index, Inner, LocalIndex, Reads, GuardIndex, NameToken: Integer;
  Found, AtCall: TInlineMeaning;
  Edits: TArray<TTextEdit>;
  SectionChange: TTextEdit;
  CalleeFlow: TFlowSignatureLookup;

  procedure Replace(AStart, AFinish: Integer; const AText: string);
  var
    Item: TReplacement;
  begin
    Item.Start := AStart;
    Item.Finish := AFinish;
    Item.Text := AText;
    Replacements.Add(Item);
  end;

  function IsFree(const AName: string): Boolean;
  begin
    Result := not Taken.ContainsKey(LowerCase(AName));
  end;

  function Unique(const ABase: string): string;
  var
    Number: Integer;
  begin
    Result := ABase;
    Number := 2;
    while not IsFree(Result) do
    begin
      Result := ABase + IntToStr(Number);
      Inc(Number);
    end;
    Taken.AddOrSetValue(LowerCase(Result), True);
  end;

  function Normalized(AStatement: TSyntaxNode): string;
  begin
    Result := TRoutineBody.Reindent(Render(ACallee.Text, Replacements, AStatement.StartOffset,
      AStatement.EndOffset), TTextLines.IndentOf(ACallee.Text, AStatement.StartPos.Line), '', LineBreak);
  end;

  function RenderNode(ANode: TSyntaxNode): string;
  begin
    Result := TTextLines.NormalizeLineBreaks(Render(ACallee.Text, Replacements, ANode.StartOffset,
      ANode.EndOffset), LineBreak);
  end;

  /// <summary>Bedeutet der Typ am Aufruf dasselbe wie in der Methode?</summary>
  function SameType(ATypeNode: TSyntaxNode): Boolean;
  var
    TypeName: string;
    InCallee, InCaller: TInlineMeaning;
    Child: Integer;
  begin
    Result := True;
    if ATypeNode = nil then
      Exit;
    if (ATypeNode.Kind = TSyntaxKind.TypeReference) and Assigned(AOptions.Lookup) then
    begin
      TypeName := ATypeNode.Name;
      if Pos('<', TypeName) > 0 then
        TypeName := Copy(TypeName, 1, Pos('<', TypeName) - 1);
      InCallee := Meaning(AOptions.Lookup, ACallee, TypeName.Split(['.']), ATypeNode.StartOffset);
      if InCallee.Found then
      begin
        InCaller := Meaning(AOptions.Lookup, ACaller, TypeName.Split(['.']), Call.NameOffset);
        if not InCaller.Found or (InCaller.Key <> InCallee.Key) then
          Exit(False);
      end;
    end;
    for Child := 0 to ATypeNode.ChildCount - 1 do
      if not SameType(ATypeNode[Child]) then
        Exit(False);
  end;

  function Visible(const AMeaning: TInlineMeaning): Boolean;
  begin
    case AMeaning.Visibility of
      TInlineVisibility.StrictPrivate, TInlineVisibility.StrictProtected:
        Result := SameText(CallerClass, AMeaning.Container) and SameText(ACaller.FileName, ACallee.FileName);
      TInlineVisibility.Private, TInlineVisibility.Protected:
        Result := SameText(ACaller.FileName, ACallee.FileName);
    else
      Result := True;
    end;
  end;

begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ACaller.Tree = nil) or (ACallee.Tree = nil) or (ARoutine = nil) then
    Exit(Fail('kein Syntaxbaum', AReason));
  if not CallAt(ACaller.Tree, ACaller.Text, APosition, Call) then
    Exit(Fail('kein Aufruf', AReason));
  CalleeTokens := ACallee.Tree.Tokens;
  CallerTokens := ACaller.Tree.Tokens;
  // Die Methode selbst.
  Keyword := RoutineKeyword(CalleeTokens, ARoutine);
  if (Keyword = 'constructor') or (Keyword = 'destructor') then
    Exit(Fail('Konstruktoren und Destruktoren', AReason));
  if Pos('<', ARoutine.Name) > 0 then
    Exit(Fail('generische Methode', AReason));
  ShortName := ARoutine.Name;
  CalleeClass := '';
  if ShortName.LastIndexOf('.') > 0 then
  begin
    CalleeClass := ShortName.Substring(0, ShortName.LastIndexOf('.'));
    ShortName := ShortName.Substring(ShortName.LastIndexOf('.') + 1);
  end;
  IsMethod := (CalleeClass <> '') and (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind <> TSyntaxKind.RoutineDecl);
  if not SameText(ShortName, Call.Name) then
    Exit(Fail('der Rumpf gehört zu einer anderen Routine', AReason));
  CalleeBody := TRoutineBody.BodyOf(ARoutine);
  if CalleeBody = nil then
    Exit(Fail('kein Rumpf', AReason));
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  ReturnType := nil;
  if Header <> nil then
    ReturnType := Header.FindChild(TSyntaxKind.TypeReference);
  IsFunction := ReturnType <> nil;
  ResultType := '';
  if IsFunction then
    ResultType := TRoutineBody.TextOf(ACallee.Text, ReturnType);
  for Index := 0 to ARoutine.ChildCount - 1 do
    case ARoutine[Index].Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.TypeSection:
        Exit(Fail('verschachtelte Routinen oder lokale Typen', AReason));
      TSyntaxKind.LabelSection:
        Exit(Fail('Marken', AReason));
    end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AsmBlock) then
    Exit(Fail('asm', AReason));
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.InheritedExpr) then
    Exit(Fail('inherited', AReason));
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.GotoStatement) or
    TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.LabeledStatement) then
    Exit(Fail('goto', AReason));
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.WithStatement) then
    Exit(Fail('with', AReason));
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AnonymousMethod) then
    Exit(Fail('anonyme Methode im Rumpf', AReason));
  if UsesName(CalleeBody, ShortName) then
    Exit(Fail('rekursiv', AReason));
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.MemberAccess, Nodes);
    for Node in Nodes do
      if SameText(Node.Name, ShortName) then
        Exit(Fail('rekursiv', AReason));
  finally
    Nodes.Free;
  end;
  // Der Aufruf.
  CallerRoutine := TRoutineBody.RoutineAt(ACaller.Tree, Call.NameOffset);
  if (ACaller.Tree = ACallee.Tree) and (CallerRoutine = ARoutine) then
    Exit(Fail('rekursiv', AReason));
  CallerBody := TRoutineBody.BodyOf(CallerRoutine);
  CallerClass := '';
  if CallerRoutine.Name.LastIndexOf('.') > 0 then
    CallerClass := CallerRoutine.Name.Substring(0, CallerRoutine.Name.LastIndexOf('.'));
  ReceiverText := '';
  if IsMethod and (Call.Receiver <> nil) then
  begin
    if not IsSimpleChain(Call.Receiver) then
      Exit(Fail('der Empfänger ist kein einfacher Name', AReason));
    if not SameText(TRoutineBody.TextOf(ACaller.Text, Call.Receiver), 'Self') then
      ReceiverText := TRoutineBody.TextOf(ACaller.Text, Call.Receiver);
  end
  else if IsMethod and (CallerClass = '') then
    Exit(Fail('Methode ohne Empfänger', AReason));
  if Inside(Call.Node, TSyntaxKind.WithStatement, CallerBody) then
    Exit(Fail('der Aufruf steht in einem with-Rumpf', AReason));
  if not AOptions.InlineVar and Inside(Call.Node, TSyntaxKind.AnonymousMethod, CallerBody) then
    Exit(Fail('der Aufruf steht in einer anonymen Methode', AReason));
  if Call.Statement = nil then
  begin
    if not IsFunction then
      Exit(Fail('Prozedur im Ausdruck', AReason));
    Host := TRoutineBody.HostStatement(Call.Node, CallerBody);
    if Host = nil then
      Exit(Fail('an dieser Stelle nicht einbettbar', AReason));
    // Der Rumpf liefe vor allem, was in der Anweisung davor steht.
    Nodes := TList<TSyntaxNode>.Create;
    try
      TRoutineLocals.CollectKind(Host, TSyntaxKind.Call, Nodes);
      TRoutineLocals.CollectKind(Host, TSyntaxKind.InheritedExpr, Nodes);
      for Node in Nodes do
        if (Node.EndOffset <= Call.Node.StartOffset) and ((Node.Kind = TSyntaxKind.InheritedExpr) or
          not CallIsPure(Node, ACaller, AOptions.Lookup)) then
          Exit(Fail('die Reihenfolge der Aufrufe änderte sich', AReason));
    finally
      Nodes.Free;
    end;
  end
  else
    Host := Call.Statement;
  // Parameter und Argumente.
  Parameters := nil;
  if Header <> nil then
  begin
    Node := Header.FindChild(TSyntaxKind.Parameters);
    if Node <> nil then
      for Index := 0 to Node.ChildCount - 1 do
        for Text in Node[Index].Name.Split([',']) do
        begin
          Parameter := Default(TParameterInfo);
          Parameter.Name := Trim(Text);
          Parameter.Modifier := Node[Index].Modifier;
          if (Node[Index].ChildCount > 0) and (Node[Index][0].Kind in TRoutineLocals.TypeKinds) then
          begin
            Parameter.TypeNode := Node[Index][0];
            Parameter.TypeText := TRoutineBody.TextOf(ACallee.Text, Parameter.TypeNode);
            if Node[Index].ChildCount > 1 then
              Parameter.DefaultValue := Node[Index][Node[Index].ChildCount - 1];
          end;
          Parameters := Parameters + [Parameter];
        end;
  end;
  if Length(Call.Arguments) > Length(Parameters) then
    Exit(Fail('zu viele Argumente', AReason));
  for Index := Length(Call.Arguments) to High(Parameters) do
    if Parameters[Index].DefaultValue = nil then
      Exit(Fail('zu wenige Argumente', AReason));
  Locals := TRoutineLocals.Collect(ACallee.Text, ACallee.Tree, ARoutine);
  CallerLocals := TRoutineLocals.Collect(ACaller.Text, ACaller.Tree, CallerRoutine);
  CalleeFlow := TFlowSignatures.FromTree(ACallee.Tree.Root);
  Graph := TControlFlowGraph.Build(ARoutine, CalleeFlow);
  try
    if not Graph.Complete then
      Exit(Fail('Syntaxfehler in der Methode', AReason));
    if IsFunction and (Graph.MayReadBeforeWrite('Result') <> TFlowAnswer.No) then
      Exit(Fail('Result wird vor dem Setzen gelesen', AReason));
  finally
    Graph.Free;
  end;
  // Exit: höchstens eins, als letzte Anweisung oder als "if … then Exit" auf oberster Ebene.
  Statements := nil;
  for Index := 0 to CalleeBody.ChildCount - 1 do
    if CalleeBody[Index].Kind <> TSyntaxKind.EmptyStatement then
      Statements := Statements + [CalleeBody[Index]];
  ExitMode := TExitMode.NoExit;
  ExitStatement := nil;
  ExitValue := nil;
  Guard := nil;
  GuardIndex := -1;
  Exits := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, Exits);
    for Node in Exits do
      if SameText(Node.Name, 'Exit') then
      begin
        if ExitStatement <> nil then
          Exit(Fail('mehrere Exit', AReason));
        ExitStatement := Node;
      end;
  finally
    Exits.Free;
  end;
  if ExitStatement <> nil then
  begin
    if (ExitStatement.ChildCount > 0) and (ExitStatement[0].Kind = TSyntaxKind.Call) and
      (ExitStatement[0].ChildCount > 1) then
      ExitValue := ExitStatement[0][1];
    if (ExitStatement.Parent = CalleeBody) and (Statements <> nil) and
      (Statements[High(Statements)] = ExitStatement) then
      ExitMode := TExitMode.LastExit
    else if (ExitStatement.Parent.Kind = TSyntaxKind.IfStatement) and (ExitStatement.Parent.Parent = CalleeBody) and
      (ExitStatement.Parent.ChildCount = 2) and (ExitStatement.Parent[1] = ExitStatement) then
    begin
      ExitMode := TExitMode.GuardExit;
      Guard := ExitStatement.Parent;
      for Index := 0 to High(Statements) do
        if Statements[Index] = Guard then
          GuardIndex := Index;
    end
    else
      Exit(Fail('Exit mitten im Rumpf', AReason));
  end;
  // Einfache Form: nur "Result := E" bzw. "Exit(E)" ersetzt den Aufruf direkt.
  SimpleExpression := nil;
  if IsFunction and (Call.Statement = nil) and (Length(Statements) = 1) and (ExitMode <> TExitMode.GuardExit) then
  begin
    Node := Statements[0];
    if (Node.Kind = TSyntaxKind.AssignStatement) and (Node[0].Kind = TSyntaxKind.Identifier) and
      SameText(Node[0].Name, 'Result') then
      SimpleExpression := Node[1]
    else if (ExitMode = TExitMode.LastExit) and (ExitValue <> nil) then
      SimpleExpression := ExitValue;
    for Index := 0 to High(Locals) do
      if Locals[Index].Kind <> TLocalKind.Parameter then
        SimpleExpression := nil;
    if (SimpleExpression <> nil) and UsesName(SimpleExpression, 'Result') then
      SimpleExpression := nil;
  end;
  LineBreak := TTextLines.LineBreakOf(ACaller.Text);
  Unit_ := TRoutineBody.IndentUnit(AOptions.Style);
  Edits := nil;
  Replacements := TList<TReplacement>.Create;
  Taken := TDictionary<string, Boolean>.Create;
  Nodes := TList<TSyntaxNode>.Create;
  Occurrences := TList<TSyntaxNode>.Create;
  try
    // Namen der umgebenden Routine sind vergeben.
    Outer := CallerRoutine;
    while (Outer.Parent <> nil) and (Outer.Parent.Kind = TSyntaxKind.RoutineDecl) do
      Outer := Outer.Parent;
    for Index := TRoutineBody.TokenAt(CallerTokens, Outer.StartOffset) to High(CallerTokens) do
    begin
      if CallerTokens[Index].Offset >= Outer.EndOffset then
        Break;
      if CallerTokens[Index].Kind = TPascalTokenKind.Identifier then
        Taken.AddOrSetValue(LowerCase(CallerTokens[Index].Text), True);
    end;
    // Fremde Namen der Methode: gleiche Bedeutung am Aufruf, Mitglieder mit Empfänger.
    for Index := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Index].Kind <> TSyntaxKind.RoutineHeader then
        TRoutineLocals.CollectKind(ARoutine[Index], TSyntaxKind.Identifier, Nodes);
    Mutates := False;
    for Node in Nodes do
    begin
      if SameText(Node.Name, 'Exit') and IsCallee(Node) then
        Continue;
      LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
      if (LocalIndex < 0) and (Node.StartOffset < CalleeBody.StartOffset) then
        // var- und const-Abschnitt: Konstanten der Methode gelten dort auch.
        for Inner := 0 to High(Locals) do
          if (Locals[Inner].Kind = TLocalKind.Constant) and SameText(Locals[Inner].Name, Node.Name) then
            LocalIndex := Inner;
      if LocalIndex >= 0 then
      begin
        if (Locals[LocalIndex].Kind = TLocalKind.Parameter) and
          (Locals[LocalIndex].Decl.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
          (TRoutineLocals.AccessOf(Node, CalleeFlow) <> TLocalAccess.Read) then
          Mutates := True;
        Continue;
      end;
      if IsFunction and SameText(Node.Name, 'Result') then
        Continue;
      if SameText(Node.Name, 'Self') then
      begin
        if ReceiverText <> '' then
          Replace(Node.StartOffset, Node.EndOffset, ReceiverText);
        Continue;
      end;
      if (Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] = Node) then
        Mutates := True;
      Taken.AddOrSetValue(LowerCase(Node.Name), True);
      if not Assigned(AOptions.Lookup) then
        Continue;
      Found := Meaning(AOptions.Lookup, ACallee, [Node.Name], Node.StartOffset);
      if not Found.Found then
        Exit(Fail(Node.Name + ' unbekannt', AReason));
      if Found.IsRoutine then
        Mutates := True;
      AtCall := Meaning(AOptions.Lookup, ACaller, [Node.Name], Call.NameOffset);
      if Found.IsMember and IsMethod then
      begin
        if ReceiverText <> '' then
        begin
          if not Visible(Found) then
            Exit(Fail(Node.Name + ' ist am Aufruf nicht sichtbar', AReason));
          Replace(Node.StartOffset, Node.EndOffset, ReceiverText + '.' + Node.Name);
        end
        else if AtCall.Key <> Found.Key then
          Replace(Node.StartOffset, Node.EndOffset, 'Self.' + Node.Name);
      end
      else if not AtCall.Found or (AtCall.Key <> Found.Key) then
        Exit(Fail(Node.Name + ' bedeutet am Aufruf etwas anderes', AReason));
    end;
    Nodes.Clear;
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Call, Nodes);
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, Nodes);
    for Node in Nodes do
      if not SameText(Node.Name, 'Exit') and ((Node.Kind = TSyntaxKind.CallStatement) or
        not CallIsPure(Node, ACallee, AOptions.Lookup)) then
        Mutates := True;
    Nodes.Clear;
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.AssignStatement, Nodes);
    for Node in Nodes do
      if Node[0].Kind <> TSyntaxKind.Identifier then
        Mutates := True;
    // Typen der neuen Deklarationen.
    for Index := 0 to High(Locals) do
      if (Locals[Index].Kind <> TLocalKind.Parameter) and not SameType(Locals[Index].Decl) then
        Exit(Fail('ein Typ bedeutet am Aufruf etwas anderes', AReason));
    if not SameType(ReturnType) then
      Exit(Fail('der Ergebnistyp bedeutet am Aufruf etwas anderes', AReason));
    // Lokale Namen der Methode: eindeutig gegen die Routine am Aufruf.
    SetLength(NewNames, Length(Locals));
    for Index := 0 to High(Locals) do
      if Locals[Index].Kind <> TLocalKind.Parameter then
        NewNames[Index] := Unique(Locals[Index].Name);
    Nodes.Clear;
    for Index := 0 to ARoutine.ChildCount - 1 do
      if ARoutine[Index].Kind <> TSyntaxKind.RoutineHeader then
        TRoutineLocals.CollectKind(ARoutine[Index], TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
    begin
      LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
      if (LocalIndex < 0) and (Node.StartOffset < CalleeBody.StartOffset) then
        for Inner := 0 to High(Locals) do
          if (Locals[Inner].Kind = TLocalKind.Constant) and SameText(Locals[Inner].Name, Node.Name) then
            LocalIndex := Inner;
      if (LocalIndex >= 0) and (Locals[LocalIndex].Kind <> TLocalKind.Parameter) then
        Replace(Node.StartOffset, Node.EndOffset, NewNames[LocalIndex]);
    end;
    // Namen in Inline-Deklarationen und for var.
    for Index := 0 to High(Locals) do
      if Locals[Index].Kind in [TLocalKind.InlineVariable, TLocalKind.LoopVariable] then
      begin
        NameToken := TRoutineBody.TokenAt(CalleeTokens, Locals[Index].Decl.StartOffset);
        while (NameToken <= High(CalleeTokens)) and (CalleeTokens[NameToken].Offset < Locals[Index].Decl.EndOffset) and
          not CalleeTokens[NameToken].IsSymbol(':') and not CalleeTokens[NameToken].IsSymbol(':=') and
          not CalleeTokens[NameToken].IsSymbol('=') and not CalleeTokens[NameToken].IsKeyword('in') do
        begin
          if (CalleeTokens[NameToken].Kind = TPascalTokenKind.Identifier) and
            SameText(CalleeTokens[NameToken].Text, Locals[Index].Name) then
            Replace(CalleeTokens[NameToken].Offset, CalleeTokens[NameToken].Offset +
              Length(CalleeTokens[NameToken].Text), NewNames[Index]);
          Inc(NameToken);
        end;
      end
      else if Locals[Index].Kind = TLocalKind.Constant then
      begin
        NameToken := NextSignificant(CalleeTokens, TRoutineBody.TokenAt(CalleeTokens, Locals[Index].Decl.StartOffset));
        Replace(CalleeTokens[NameToken].Offset, CalleeTokens[NameToken].Offset + Length(CalleeTokens[NameToken].Text),
          NewNames[Index]);
      end;
    // Parameter: Argument direkt, sonst Hilfsvariable.
    Lines := nil;
    VarEntries := nil;
    ConstEntries := nil;
    SetLength(ParameterText, Length(Parameters));
    ArgumentNames := nil;
    for Index := 0 to High(Parameters) do
      if (Parameters[Index].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
        (Index <= High(Call.Arguments)) and IsSimpleChain(Call.Arguments[Index]) then
        ArgumentNames := ArgumentNames + [ChainNames(Call.Arguments[Index])[0]];
    for Index := 0 to High(Parameters) do
    begin
      Parameter := Parameters[Index];
      if Index <= High(Call.Arguments) then
      begin
        Argument := Call.Arguments[Index];
        Text := TTextLines.NormalizeLineBreaks(TRoutineBody.TextOf(ACaller.Text, Argument), LineBreak);
      end
      else
      begin
        // Vorgabewert: seine Namen müssen am Aufruf dasselbe bedeuten.
        Argument := Parameter.DefaultValue;
        Text := TRoutineBody.TextOf(ACallee.Text, Argument);
        Nodes.Clear;
        TRoutineLocals.CollectKind(Argument, TSyntaxKind.Identifier, Nodes);
        if Assigned(AOptions.Lookup) then
          for Node in Nodes do
          begin
            Found := Meaning(AOptions.Lookup, ACallee, [Node.Name], Node.StartOffset);
            AtCall := Meaning(AOptions.Lookup, ACaller, [Node.Name], Call.NameOffset);
            if not Found.Found or not AtCall.Found or (Found.Key <> AtCall.Key) then
              Exit(Fail('der Vorgabewert von ' + Parameter.Name + ' bedeutet am Aufruf etwas anderes', AReason));
          end;
      end;
      Occurrences.Clear;
      Nodes.Clear;
      TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, Nodes);
      for Node in Nodes do
        if SameText(Node.Name, Parameter.Name) and (TRoutineLocals.IndexOf(Locals, Node.Name,
          Node.StartOffset) >= 0) and (Locals[TRoutineLocals.IndexOf(Locals, Node.Name,
          Node.StartOffset)].Kind = TLocalKind.Parameter) then
          Occurrences.Add(Node);
      if Parameter.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam] then
      begin
        if (Index > High(Call.Arguments)) or not TRoutineBody.IsVariableChain(Argument) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.Call) then
          Exit(Fail('das Argument für ' + Parameter.Name + ' ist keine einfache Variable', AReason));
        ParameterText[Index] := Text;
        for Node in Occurrences do
          Replace(Node.StartOffset, Node.EndOffset, Text);
        Continue;
      end;
      Written := False;
      Reads := 0;
      InLoop := False;
      for Node in Occurrences do
      begin
        if TRoutineLocals.AccessOf(Node, CalleeFlow) <> TLocalAccess.Read then
          Written := True;
        Inc(Reads);
        if InLoopWithout(Node, CalleeBody, CalleeBody) then
          InLoop := True;
      end;
      if Parameter.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam] then
        Written := False;
      if Index <= High(Call.Arguments) then
        Pure := not HasSideEffects(Argument, ACaller, AOptions.Lookup)
      else
        Pure := not HasSideEffects(Argument, ACallee, AOptions.Lookup);
      // Stabil: ändert sich während des Rumpfs nicht.
      Stable := Pure and ((Argument.Kind = TSyntaxKind.Literal) or not Mutates);
      if Pure and not Stable and (Index <= High(Call.Arguments)) then
      begin
        Stable := True;
        Nodes.Clear;
        TRoutineLocals.CollectKind(Argument, TSyntaxKind.Identifier, Nodes);
        for Node in Nodes do
          if not IsCallee(Node) and ((TRoutineLocals.IndexOf(CallerLocals, Node.Name, Node.StartOffset) < 0) and
            not MatchText(Node.Name, ConstantNames)) or (IndexText(Node.Name, ArgumentNames) >= 0) then
            Stable := False;
        if TRoutineLocals.HasKind(Argument, TSyntaxKind.Dereference) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.MemberAccess) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.IndexAccess) then
          Stable := False;
      end;
      Simple := Argument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess,
        TSyntaxKind.ParenExpr];
      if not Written and Stable and (Simple or ((Reads <= 1) and not InLoop)) then
      begin
        ParameterText[Index] := Text;
        for Node in Occurrences do
          Replace(Node.StartOffset, Node.EndOffset, Parenthesized(Text, Argument, Node));
        Continue;
      end;
      if Parameter.TypeText = '' then
        Exit(Fail('untypisierter Parameter ' + Parameter.Name, AReason));
      if not SameType(Parameter.TypeNode) then
        Exit(Fail('der Typ von ' + Parameter.Name + ' bedeutet am Aufruf etwas anderes', AReason));
      ParameterText[Index] := Unique(Parameter.Name);
      for Node in Occurrences do
        Replace(Node.StartOffset, Node.EndOffset, ParameterText[Index]);
      if AOptions.InlineVar then
        Lines := Lines + ['var ' + ParameterText[Index] + ': ' + Parameter.TypeText + ' := ' + Text]
      else
      begin
        VarEntries := VarEntries + [ParameterText[Index] + ': ' + Parameter.TypeText + ';'];
        Lines := Lines + [ParameterText[Index] + ' := ' + Text];
      end;
    end;
    // Ergebnis.
    ResultName := '';
    if IsFunction and (SimpleExpression = nil) then
    begin
      ResultName := Unique(ShortName + ResultSuffix);
      Nodes.Clear;
      TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, Nodes);
      for Node in Nodes do
        if SameText(Node.Name, 'Result') then
          Replace(Node.StartOffset, Node.EndOffset, ResultName);
    end;
    Replacements.Sort(TComparer<TReplacement>.Construct(
      function(const A, B: TReplacement): Integer
      begin
        Result := A.Start - B.Start;
      end));
    // Lokale Variablen und Konstanten der Methode.
    for Index := 0 to High(Locals) do
      case Locals[Index].Kind of
        TLocalKind.Variable:
          if AOptions.InlineVar then
            Lines := Lines + ['var ' + NewNames[Index] + ': ' + RenderNode(Locals[Index].Decl[0])]
          else
            VarEntries := VarEntries + [NewNames[Index] + ': ' + RenderNode(Locals[Index].Decl[0]) + ';'];
        TLocalKind.Constant:
          ConstEntries := ConstEntries + [RenderNode(Locals[Index].Decl)];
      end;
    if ResultName <> '' then
      if AOptions.InlineVar then
        Lines := Lines + ['var ' + ResultName + ': ' + ResultType]
      else
        VarEntries := VarEntries + [ResultName + ': ' + ResultType + ';'];
    // Rumpf.
    if SimpleExpression = nil then
      for Index := 0 to High(Statements) do
      begin
        Node := Statements[Index];
        if (ExitMode = TExitMode.LastExit) and (Node = ExitStatement) then
        begin
          if (ExitValue <> nil) and (ResultName <> '') then
            Lines := Lines + [ResultName + ' := ' + RenderNode(ExitValue)];
          Continue;
        end;
        if (ExitMode = TExitMode.GuardExit) and (Index = GuardIndex) then
        begin
          RestLines := nil;
          for Inner := Index + 1 to High(Statements) do
            RestLines := RestLines + [Normalized(Statements[Inner])];
          Condition := RenderNode(Guard[0]);
          if (ExitValue <> nil) and (ResultName <> '') then
          begin
            Text := 'if ' + Condition + ' then' + LineBreak + Unit_ + ResultName + ' := ' + RenderNode(ExitValue);
            if RestLines <> nil then
              Text := Text + LineBreak + 'else' + LineBreak + 'begin' + LineBreak +
                JoinStatements(RestLines, Unit_, LineBreak, True) + ';' + LineBreak + 'end';
            Lines := Lines + [Text];
          end
          else if RestLines <> nil then
          begin
            if (Guard[0].Kind = TSyntaxKind.UnaryExpr) and SameText(Guard[0].Name, 'not') then
              Text := RenderNode(Guard[0][0])
            else
              Text := Negated(Condition, Guard[0]);
            Lines := Lines + ['if ' + Text + ' then' + LineBreak + 'begin' + LineBreak +
              JoinStatements(RestLines, Unit_, LineBreak, True) + ';' + LineBreak + 'end'];
          end
          else if HasSideEffects(Guard[0], ACallee, AOptions.Lookup) then
            Lines := Lines + ['if ' + Condition + ' then' + LineBreak + 'begin' + LineBreak + 'end'];
          Break;
        end;
        Lines := Lines + [Normalized(Node)];
      end;
    // Bearbeitungen am Aufruf.
    Indent := TTextLines.IndentOf(ACaller.Text, Host.StartPos.Line);
    if Call.Statement <> nil then
    begin
      if Lines = nil then
        NewText := ''
      else if TRoutineBody.InList(Host) then
        NewText := JoinStatements(Lines, Indent, LineBreak, False)
      else
        NewText := 'begin' + LineBreak + JoinStatements(Lines, Indent + Unit_, LineBreak, True) + ';' + LineBreak +
          Indent + 'end';
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.EndPos), NewText)];
    end
    else
    begin
      if SimpleExpression <> nil then
        Replacement := Parenthesized(RenderNode(SimpleExpression), SimpleExpression, Call.Node)
      else
        Replacement := ResultName;
      NewText := '';
      if Lines <> nil then
        NewText := JoinStatements(Lines, Indent, LineBreak, False) + ';' + LineBreak + Indent;
      if Call.Node.StartOffset = Host.StartOffset then
        Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call.Node.StartPos, Call.Node.EndPos),
          NewText + Replacement)]
      else
      begin
        if NewText <> '' then
          Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.StartPos), NewText)];
        Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call.Node.StartPos, Call.Node.EndPos), Replacement)];
      end;
    end;
    if VarEntries <> nil then
    begin
      SectionChange := SectionEdit(ACaller.Text, CallerRoutine, False, VarEntries, AOptions.Style);
      Edits := Edits + [SectionChange];
    end;
    if ConstEntries <> nil then
    begin
      SectionChange := SectionEdit(ACaller.Text, CallerRoutine, True, ConstEntries, AOptions.Style);
      Edits := Edits + [SectionChange];
    end;
  finally
    Occurrences.Free;
    Nodes.Free;
    Taken.Free;
    Replacements.Free;
  end;
  if IsMethod then
    AAction.Title := Format('Methode %s einbetten', [ShortName])
  else
    AAction.Title := Format('Routine %s einbetten', [ShortName]);
  AAction.Kind := InlineKind;
  AAction.Edits := Edits;
  Result := True;
end;

class function TInlineRefactoring.Actions(const ASource: TInlineSource; const APosition: TTextPosition;
  const AOptions: TInlineOptions): TArray<TCodeAction>;
var
  Action: TCodeAction;
  Call: TInlineCall;
  Routines: TArray<TSyntaxNode>;
begin
  Result := nil;
  if InlineVariable(ASource, APosition, AOptions, Action) then
    Result := Result + [Action];
  if CallAt(ASource.Tree, ASource.Text, APosition, Call) then
  begin
    Routines := FindRoutines(ASource.Tree, Call.Name);
    if (Length(Routines) = 1) and InlineMethod(ASource, APosition, ASource, Routines[0], AOptions, Action) then
      Result := Result + [Action];
  end;
end;

end.
