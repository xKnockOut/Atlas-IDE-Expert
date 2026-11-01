unit Atlas.Common.Editing.Inlining;

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
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Pascal.PureRoutines;

const
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  CompoundKinds = [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.IfExpr, TSyntaxKind.RangeExpr];
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
  begin
    Exit(Index);
  end;
  if (Index > 0) and (Index - 1 <= High(ATokens)) and
    (ATokens[Index - 1].Offset + Length(ATokens[Index - 1].Text) >= AOffset) and
    (ATokens[Index - 1].Kind = TPascalTokenKind.Identifier) then
  begin
    Exit(Index - 1);
  end;
  Result := -1;
end;

/// <summary>Identifier bzw. MemberAccess, dessen Name AOffset..AEnd belegt; nil ohne.</summary>
function NameNodeAt(ANode: TSyntaxNode; AOffset, AEnd: Integer): TSyntaxNode;
var
  Pending: TStack<TSyntaxPostOrderEntry>;
  Entry: TSyntaxPostOrderEntry;
  Node: TSyntaxNode;
  Index: Integer;
begin
  // Eigener Stapel statt Rekursion (Bericht M1); wie früher die Kinder vor dem Knoten selbst.
  Result := nil;
  Pending := TStack<TSyntaxPostOrderEntry>.Create;
  try
    Pending.Push(TSyntaxPostOrderEntry.Create(ANode, False));
    while Pending.Count > 0 do
    begin
      Entry := Pending.Pop;
      Node := Entry.Node;
      if not Entry.Done then
      begin
        if (Node.StartOffset > AOffset) or (Node.EndOffset < AEnd) then
        begin
          Continue;
        end;
        Pending.Push(TSyntaxPostOrderEntry.Create(Node, True));
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(TSyntaxPostOrderEntry.Create(Node[Index], False));
        end;
        Continue;
      end;
      if ((Node.Kind = TSyntaxKind.Identifier) and (Node.StartOffset = AOffset) and (Node.EndOffset = AEnd)) or
        ((Node.Kind = TSyntaxKind.MemberAccess) and (Node.EndOffset = AEnd) and
        (AEnd - Length(Node.Name) = AOffset)) then
      begin
        Exit(Node);
      end;
    end;
  finally
    Pending.Free;
  end;
end;

/// <summary>Innerste Routine mit Rumpf, deren Deklaration AOffset enthält (auch var-Abschnitt); nil ohne.</summary>
function RoutineContaining(ANode: TSyntaxNode; AOffset: Integer): TSyntaxNode;
var
  Index: Integer;
  Node, Child: TSyntaxNode;
begin
  // Schleife statt Rekursion (Bericht M1): dem ersten Kind folgen, das AOffset enthält; die letzte Routine
  // auf dem Weg ist die innerste.
  Result := nil;
  Node := ANode;
  while Node <> nil do
  begin
    Child := nil;
    for Index := 0 to Node.ChildCount - 1 do
    begin
      if (Node[Index].StartOffset <= AOffset) and (AOffset < Node[Index].EndOffset) then
      begin
        Child := Node[Index];
        Break;
      end;
    end;
    if (Child <> nil) and (Child.Kind = TSyntaxKind.RoutineDecl) and (TRoutineBody.BodyOf(Child) <> nil) then
    begin
      Result := Child;
    end;
    Node := Child;
  end;
end;

function IsSimpleChain(ANode: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode;
  while Node.Kind = TSyntaxKind.MemberAccess do
  begin
    Node := Node[0];
  end;
  Result := Node.Kind = TSyntaxKind.Identifier;
end;

function ChainNames(ANode: TSyntaxNode): TArray<string>;
var
  Node: TSyntaxNode;
  Count, Index: Integer;
begin
  // Schleife statt Rekursion (Bericht M1): A.B.C → [A, B, C].
  Count := 0;
  Node := ANode;
  while Node.Kind = TSyntaxKind.MemberAccess do
  begin
    Inc(Count);
    Node := Node[0];
  end;
  SetLength(Result, Count + 1);
  Node := ANode;
  for Index := Count downto 1 do
  begin
    Result[Index] := Node.Name;
    Node := Node[0];
  end;
  Result[0] := Node.Name;
end;

/// <summary>Muss ein zusammengesetzter Ausdruck AExpression an der Stelle ATarget in Klammern?</summary>
function NeedsParens(AExpression, ATarget: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Result := False;
  if not (AExpression.Kind in CompoundKinds) then
  begin
    Exit;
  end;
  Parent := ATarget.Parent;
  if Parent = nil then
  begin
    Exit;
  end;
  case Parent.Kind of
    TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.MemberAccess, TSyntaxKind.Dereference,
    TSyntaxKind.AddressOf:
      Result := True;
    TSyntaxKind.IndexAccess, TSyntaxKind.Call:
      Result := Parent[0] = ATarget;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function Parenthesized(const AText: string; AExpression, ATarget: TSyntaxNode): string;
begin
  if NeedsParens(AExpression, ATarget) then
  begin
    Result := '(' + AText + ')';
  end
  else
  begin
    Result := AText;
  end;
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
  begin
    Result := ALookup(ASource.Tree, ASource.FileName, ANames, AOffset);
  end;
end;

/// <summary>Aufruf ohne Seiteneffekte: Standardroutine der Liste oder Typumwandlung.</summary>
function CallIsPure(ACall: TSyntaxNode; const ASource: TInlineSource; const ALookup: TInlineLookup): Boolean;
var
  Callee: TSyntaxNode;
  Found: TInlineMeaning;
begin
  Callee := ACall[0];
  if (Callee.Kind = TSyntaxKind.Identifier) and TPureRoutines.IsPure(Callee.Name) then
  begin
    Exit(True);
  end;
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
  begin
    Exit(True);
  end;
  Result := False;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Call, Nodes);
    for Node in Nodes do
    begin
      if not CallIsPure(Node, ASource, ALookup) then
      begin
        Exit(True);
      end;
    end;
    if not Assigned(ALookup) then
    begin
      Exit;
    end;
    // Routinen ohne Klammern und Methoden über eine Kette (A.Next) rufen auch auf.
    Nodes.Clear;
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.Identifier, Nodes);
    TRoutineLocals.CollectKind(ANode, TSyntaxKind.MemberAccess, Nodes);
    for Node in Nodes do
    begin
      if not IsCallee(Node) and IsSimpleChain(Node) then
      begin
        Found := Meaning(ALookup, ASource, ChainNames(Node), Node.StartOffset);
        if Found.Found and Found.IsRoutine then
        begin
          Exit(True);
        end;
      end;
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
  begin
    Inc(Result);
  end;
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
  begin
    EndOffset := Tokens[Index].Offset + 1;
  end;
  Lines := TLineTable.Build(AText);
  EndPos := Lines.PositionAt(EndOffset);
  Line := AStatement.StartPos.Line;
  Before := Copy(AText, Lines.LineStart(Line) + 1, AStatement.StartOffset - Lines.LineStart(Line));
  After := Copy(AText, EndOffset + 1, Lines.LineContentEnd(EndPos.Line) - EndOffset);
  if (Trim(Before) = '') and (Trim(After) = '') then
  begin
    Result := TTextEdit.Create(TTextRange.Create(Line, 0, EndPos.Line + 1, 0), '');
  end
  else
  begin
    Result := TTextEdit.Create(TTextRange.Create(AStatement.StartPos, EndPos), '');
  end;
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

/// <summary>Liegt ANode in einer Schleife (bis ABody), die AOther nicht enthält?</summary>
function InLoopWithout(ANode, AOther, ABody: TSyntaxNode): Boolean;
var
  Node: TSyntaxNode;
begin
  Node := ANode.Parent;
  while (Node <> nil) and (Node <> ABody) do
  begin
    if (Node.Kind in LoopKinds) and not TRoutineBody.Within(AOther, Node) then
    begin
      Exit(True);
    end;
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
    begin
      Exit(True);
    end;
    Node := Node.Parent;
  end;
  Result := False;
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
    begin
      TRoutineLocals.CollectKind(ABody, Kind, Nodes);
    end;
    for Node in Nodes do
    begin
      if (Node.StartOffset >= AFrom) and (Node.EndOffset <= ATo) then
        case Node.Kind of
          TSyntaxKind.Call:
            if not CallIsPure(Node, ASource, ALookup) then
            begin
              Exit(True);
            end;
          TSyntaxKind.CallStatement:
            if (Node.ChildCount = 0) or (Node[0].Kind <> TSyntaxKind.Call) then
            begin
              Exit(True);
            end;
          TSyntaxKind.AssignStatement:
            if (Node[0].Kind <> TSyntaxKind.Identifier) or
              (TRoutineLocals.IndexOf(ALocals, Node[0].Name, Node[0].StartOffset) < 0) then
            begin
              Exit(True);
            end;
        else
          Exit(True);
        end;
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
    begin
      if (Node.StartOffset >= AFrom) and (Node.EndOffset <= ATo) and not IsCallee(Node) and
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

function UsesName(ANode: TSyntaxNode; const AName: string): Boolean;
var
  Name: string;
begin
  Name := AName;
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    begin
      Result := TSyntaxSearchStep.Descend;
      if (ACandidate.Kind = TSyntaxKind.Identifier) and SameText(ACandidate.Name, Name) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end) <> nil;
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
  begin
    Exit(Fail('kein Syntaxbaum', AReason));
  end;
  Tokens := Tree.Tokens;
  Offset := TLineTable.Build(ASource.Text).OffsetAt(APosition);
  Token := TokenContaining(Tokens, Offset);
  if Token < 0 then
  begin
    Exit(Fail('kein Bezeichner', AReason));
  end;
  Name := Tokens[Token].Text;
  Offset := Tokens[Token].Offset;
  Routine := RoutineContaining(Tree.Root, Offset);
  if Routine = nil then
  begin
    Exit(Fail('nicht in einer Routine', AReason));
  end;
  Body := TRoutineBody.BodyOf(Routine);
  Locals := TRoutineLocals.Collect(ASource.Text, Tree, Routine);
  LocalIndex := -1;
  if Offset < Body.StartOffset then
  begin
    // Name im var-Abschnitt.
    for Index := 0 to High(Locals) do
    begin
      if (Locals[Index].Kind = TLocalKind.Variable) and SameText(Locals[Index].Name, Name) and
        (Locals[Index].Decl.StartOffset <= Offset) and (Offset < Locals[Index].Decl.EndOffset) then
      begin
        LocalIndex := Index;
      end;
    end;
  end
  else
  begin
    LocalIndex := TRoutineLocals.IndexOf(Locals, Name, Offset);
  end;
  if LocalIndex < 0 then
  begin
    Exit(Fail(Name + ' ist keine lokale Variable', AReason));
  end;
  Local := Locals[LocalIndex];
  if not (Local.Kind in [TLocalKind.Variable, TLocalKind.InlineVariable]) then
  begin
    Exit(Fail('nur lokale Variablen', AReason));
  end;
  if Local.Decl.Kind = TSyntaxKind.InlineConst then
  begin
    Exit(Fail('Konstante', AReason));
  end;
  if (Local.Kind = TLocalKind.InlineVariable) and (Pos(',', Local.Decl.Name) > 0) then
  begin
    Exit(Fail('mehrere Namen in einer Deklaration', AReason));
  end;
  Name := Local.Name;
  // Verschachtelte Routinen sehen die Variable auch.
  if Local.Kind = TLocalKind.Variable then
  begin
    for Index := 0 to Routine.ChildCount - 1 do
    begin
      if (Routine[Index].Kind = TSyntaxKind.RoutineDecl) and UsesName(Routine[Index], Name) then
      begin
        Exit(Fail(Name + ' wird in einer verschachtelten Routine verwendet', AReason));
      end;
    end;
  end;
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
    begin
      if SameText(Node.Name, Name) and not TRoutineLocals.IsInlineFor(Tokens, Node) and
        (TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset) = LocalIndex) then
      begin
        Exit(Fail(Name + ' ist Laufvariable', AReason));
      end;
    end;
    Nodes.Clear;
    TRoutineLocals.CollectKind(Body, TSyntaxKind.Identifier, Nodes);
    for Node in Nodes do
    begin
      if not SameText(Node.Name, Name) or (TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset) <>
        LocalIndex) then
      begin
        Continue;
      end;
      if Inside(Node, TSyntaxKind.AnonymousMethod, Body) then
      begin
        Exit(Fail(Name + ' wird in einer anonymen Methode verwendet', AReason));
      end;
      if Inside(Node, TSyntaxKind.WithStatement, Body) then
      begin
        Exit(Fail(Name + ' steht in einem with-Rumpf', AReason));
      end;
      case TRoutineLocals.AccessOf(Node, Flow) of
        TLocalAccess.Read:
          Reads := Reads + [Node];
        TLocalAccess.Write:
          begin
            if Definition <> nil then
            begin
              Exit(Fail(Name + ' wird mehrfach zugewiesen', AReason));
            end;
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
  begin
    Exit(Fail(Name + ' bekommt keinen Wert', AReason));
  end;
  if Reads = nil then
  begin
    Exit(Fail(Name + ' wird nie gelesen', AReason));
  end;
  if not TRoutineBody.InList(Definition) then
  begin
    Exit(Fail('die Zuweisung steht nicht in einer Anweisungsliste', AReason));
  end;
  if Inside(Definition, TSyntaxKind.WithStatement, Body) then
  begin
    Exit(Fail('die Zuweisung steht in einem with-Rumpf', AReason));
  end;
  if UsesName(Expression, Name) then
  begin
    Exit(Fail('der Ausdruck enthält ' + Name, AReason));
  end;
  // Klammern um den ganzen Ausdruck braucht der eingesetzte Text nicht doppelt.
  if (Expression.Kind = TSyntaxKind.ParenExpr) and (Expression.ChildCount = 1) then
  begin
    Expression := Expression[0];
  end;
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
    begin
      for Read in ExprNames do
      begin
        if UsesName(Node, Read.Name) then
        begin
          Volatile := True;
        end;
      end;
    end;
  finally
    Nodes.Free;
  end;
  if SideEffects and (Length(Reads) > 1) then
  begin
    Exit(Fail('der Ausdruck hat Seiteneffekte und wird mehrfach gelesen', AReason));
  end;
  Graph := TControlFlowGraph.Build(Routine, Flow);
  try
    if not Graph.Complete then
    begin
      Exit(Fail('asm oder Syntaxfehler in der Routine', AReason));
    end;
    DefNode := Graph.NodeOf(Definition);
    if DefNode = nil then
    begin
      Exit(Fail('Zuweisung nicht im Ablauf', AReason));
    end;
    for Read in Reads do
    begin
      ReadNode := FlowNodeAt(Graph, Read);
      if ReadNode = nil then
      begin
        Exit(Fail('Lesen nicht im Ablauf', AReason));
      end;
      Reaching := Graph.ReachingDefinitions(ReadNode, Name);
      if (Length(Reaching.Definitions) <> 1) or (Reaching.Definitions[0] <> DefNode) or Reaching.FromEntry or
        Reaching.MaybeFromEntry or (Reaching.Uncertain <> nil) then
      begin
        Exit(Fail('an einer Stelle kommt ein anderer Wert von ' + Name + ' an', AReason));
      end;
      // Lokale Namen des Ausdrucks: am Lesen sichtbar und mit demselben Wert wie bei der Zuweisung.
      for Node in ExprNames do
      begin
        Index := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
        if Index < 0 then
        begin
          Continue;
        end;
        Inner := TRoutineLocals.IndexOf(Locals, Node.Name, Read.StartOffset);
        if Inner <> Index then
        begin
          Exit(Fail(Node.Name + ' ist an einer Stelle nicht sichtbar', AReason));
        end;
        if Locals[Index].Kind = TLocalKind.Constant then
        begin
          Continue;
        end;
        AtDef := Graph.ReachingDefinitions(DefNode, Node.Name);
        AtRead := Graph.ReachingDefinitions(ReadNode, Node.Name);
        if not SameReaching(AtDef, AtRead) then
        begin
          Exit(Fail(Node.Name + ' ändert sich vor einer Stelle', AReason));
        end;
      end;
      if (Volatile or SideEffects) and (InLoopWithout(Read, Definition, Body) or
        ChangesBetween(Body, Locals, Definition.EndOffset, Read.StartOffset, ASource, AOptions.Lookup)) then
      begin
        Exit(Fail('dazwischen kann sich der Wert des Ausdrucks ändern', AReason));
      end;
      if SideEffects and (not EvaluatedOnce(Read) or
        ReadsBetween(Body, Definition.EndOffset, Read.StartOffset)) then
      begin
        Exit(Fail('der Ausdruck hat Seiteneffekte; die Reihenfolge änderte sich', AReason));
      end;
    end;
  finally
    Graph.Free;
  end;
  ExprText := TRoutineBody.TextOf(ASource.Text, Expression);
  Edits := nil;
  for Read in Reads do
  begin
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(Read.StartPos, Read.EndPos),
      Parenthesized(ExprText, Expression, Read))];
  end;
  Edits := Edits + [RemoveStatement(ASource.Text, Tree, Definition)];
  if Local.Kind = TLocalKind.Variable then
  begin
    TRoutineLocals.RemoveVariables(Tree, Local.Decl, [Name], Edits);
  end
  else if Definition <> Local.Decl then
  begin
    Edits := Edits + [RemoveStatement(ASource.Text, Tree, Local.Decl)];
  end;
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
  begin
    Exit;
  end;
  Tokens := ATree.Tokens;
  Offset := TLineTable.Build(AText).OffsetAt(APosition);
  Token := TokenContaining(Tokens, Offset);
  if Token < 0 then
  begin
    Exit;
  end;
  Routine := TRoutineBody.RoutineAt(ATree, Tokens[Token].Offset);
  if Routine = nil then
  begin
    Exit;
  end;
  Body := TRoutineBody.BodyOf(Routine);
  Name := NameNodeAt(Body, Tokens[Token].Offset, Tokens[Token].Offset + Length(Tokens[Token].Text));
  if Name = nil then
  begin
    Exit;
  end;
  Parent := Name.Parent;
  // Qualifizierer (Foo in Foo.Bar), Ziel einer Zuweisung und @Foo sind keine Aufrufe.
  if (Parent = nil) or ((Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (Parent[0] = Name)) or (Parent.Kind = TSyntaxKind.AddressOf) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = Name)) then
  begin
    Exit;
  end;
  ACall.Name := Name.Name;
  ACall.NameOffset := Tokens[Token].Offset;
  ACall.NamePos := Tokens[Token].StartPos;
  ACall.Callee := Name;
  ACall.Node := Name;
  if Name.Kind = TSyntaxKind.MemberAccess then
  begin
    ACall.Receiver := Name[0];
  end;
  if (Parent.Kind = TSyntaxKind.Call) and (Parent[0] = Name) then
  begin
    ACall.Node := Parent;
    for Index := 1 to Parent.ChildCount - 1 do
    begin
      ACall.Arguments := ACall.Arguments + [Parent[Index]];
    end;
  end;
  if (ACall.Node.Parent <> nil) and (ACall.Node.Parent.Kind = TSyntaxKind.CallStatement) then
  begin
    ACall.Statement := ACall.Node.Parent;
  end;
  Result := True;
end;

procedure CollectRoutines(ANode: TSyntaxNode; const AName: string; AList: TList<TSyntaxNode>);
var
  Index: Integer;
  Short: string;
begin
  for Index := 0 to ANode.ChildCount - 1 do
  begin
    if ANode[Index].Kind = TSyntaxKind.RoutineDecl then
    begin
      Short := ANode[Index].Name;
      if (Pos('.', AName) = 0) and (Pos('.', Short) > 0) then
      begin
        Short := Short.Substring(Short.LastIndexOf('.') + 1);
      end;
      if SameText(Short, AName) and (TRoutineBody.BodyOf(ANode[Index]) <> nil) then
      begin
        AList.Add(ANode[Index]);
      end;
    end
    else if ANode[Index].Kind in [TSyntaxKind.ImplementationSection, TSyntaxKind.InterfaceSection] then
    begin
      CollectRoutines(ANode[Index], AName, AList);
    end;
  end;
end;

class function TInlineRefactoring.FindRoutines(ATree: TSyntaxTree; const AName: string): TArray<TSyntaxNode>;
var
  List: TList<TSyntaxNode>;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
  begin
    Exit;
  end;
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
  begin
    Index := NextSignificant(ATokens, Index + 1);
  end;
  Result := '';
  if Index <= High(ATokens) then
  begin
    Result := LowerCase(ATokens[Index].Text);
  end;
end;

function Render(const AText: string; AReplacements: TList<TReplacement>; AStart, AFinish: Integer): string;
var
  Position: Integer;
  Replacement: TReplacement;
begin
  Result := '';
  Position := AStart;
  for Replacement in AReplacements do
  begin
    if (Replacement.Start >= Position) and (Replacement.Finish <= AFinish) then
    begin
      Result := Result + Copy(AText, Position + 1, Replacement.Start - Position) + Replacement.Text;
      Position := Replacement.Finish;
    end;
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
    begin
      Piece := Copy(Piece, Length(AIndent) + 1, MaxInt);
    end;
    if Index > 0 then
    begin
      Result := Result + ';' + ALineBreak;
    end;
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
  begin
    Dec(Index);
  end;
  Indent := Copy(Result.NewText, Index + 1, Start - Index - 1);
  Entries := AEntries[0];
  for Index := 1 to High(AEntries) do
  begin
    Entries := Entries + LineBreak + Indent + AEntries[Index];
  end;
  Result.NewText := StringReplace(Result.NewText, Placeholder, Entries, []);
end;

function Negated(const AText: string; ACondition: TSyntaxNode): string;
begin
  if ACondition.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Call, TSyntaxKind.MemberAccess,
    TSyntaxKind.ParenExpr, TSyntaxKind.IndexAccess, TSyntaxKind.Literal] then
  begin
    Result := 'not ' + AText;
  end
  else
  begin
    Result := 'not (' + AText + ')';
  end;
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
    begin
      Exit;
    end;
    if (ATypeNode.Kind = TSyntaxKind.TypeReference) and Assigned(AOptions.Lookup) then
    begin
      TypeName := ATypeNode.Name;
      if Pos('<', TypeName) > 0 then
      begin
        TypeName := Copy(TypeName, 1, Pos('<', TypeName) - 1);
      end;
      InCallee := Meaning(AOptions.Lookup, ACallee, TypeName.Split(['.']), ATypeNode.StartOffset);
      if InCallee.Found then
      begin
        InCaller := Meaning(AOptions.Lookup, ACaller, TypeName.Split(['.']), Call.NameOffset);
        if not InCaller.Found or (InCaller.Key <> InCallee.Key) then
        begin
          Exit(False);
        end;
      end;
    end;
    for Child := 0 to ATypeNode.ChildCount - 1 do
    begin
      if not SameType(ATypeNode[Child]) then
      begin
        Exit(False);
      end;
    end;
  end;

  function Visible(const AMeaning: TInlineMeaning): Boolean;
  begin
    // Private Mitglieder nur in der eigenen Klasse, auch wenn Delphi sie in der ganzen Unit zuließe.
    case AMeaning.Visibility of
      TInlineVisibility.StrictPrivate, TInlineVisibility.StrictProtected, TInlineVisibility.Private:
        Result := SameText(CallerClass, AMeaning.Container) and SameText(ACaller.FileName, ACallee.FileName);
      TInlineVisibility.Protected:
        Result := SameText(ACaller.FileName, ACallee.FileName);
    else
      Result := True;
    end;
  end;

begin
  AAction := Default(TCodeAction);
  AReason := '';
  if (ACaller.Tree = nil) or (ACallee.Tree = nil) or (ARoutine = nil) then
  begin
    Exit(Fail('kein Syntaxbaum', AReason));
  end;
  if not CallAt(ACaller.Tree, ACaller.Text, APosition, Call) then
  begin
    Exit(Fail('kein Aufruf', AReason));
  end;
  CalleeTokens := ACallee.Tree.Tokens;
  CallerTokens := ACaller.Tree.Tokens;
  // Die Methode selbst.
  Keyword := RoutineKeyword(CalleeTokens, ARoutine);
  if (Keyword = 'constructor') or (Keyword = 'destructor') then
  begin
    Exit(Fail('Konstruktoren und Destruktoren', AReason));
  end;
  if Pos('<', ARoutine.Name) > 0 then
  begin
    Exit(Fail('generische Methode', AReason));
  end;
  ShortName := ARoutine.Name;
  CalleeClass := '';
  if ShortName.LastIndexOf('.') > 0 then
  begin
    CalleeClass := ShortName.Substring(0, ShortName.LastIndexOf('.'));
    ShortName := ShortName.Substring(ShortName.LastIndexOf('.') + 1);
  end;
  IsMethod := (CalleeClass <> '') and (ARoutine.Parent <> nil) and (ARoutine.Parent.Kind <> TSyntaxKind.RoutineDecl);
  if not SameText(ShortName, Call.Name) then
  begin
    Exit(Fail('der Rumpf gehört zu einer anderen Routine', AReason));
  end;
  CalleeBody := TRoutineBody.BodyOf(ARoutine);
  if CalleeBody = nil then
  begin
    Exit(Fail('kein Rumpf', AReason));
  end;
  Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
  ReturnType := nil;
  if Header <> nil then
  begin
    ReturnType := Header.FindChild(TSyntaxKind.TypeReference);
  end;
  IsFunction := ReturnType <> nil;
  ResultType := '';
  if IsFunction then
  begin
    ResultType := TRoutineBody.TextOf(ACallee.Text, ReturnType);
  end;
  for Index := 0 to ARoutine.ChildCount - 1 do
    case ARoutine[Index].Kind of
      TSyntaxKind.RoutineDecl, TSyntaxKind.TypeSection:
        Exit(Fail('verschachtelte Routinen oder lokale Typen', AReason));
      TSyntaxKind.LabelSection:
        Exit(Fail('Marken', AReason));
    end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AsmBlock) then
  begin
    Exit(Fail('asm', AReason));
  end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.InheritedExpr) then
  begin
    Exit(Fail('inherited', AReason));
  end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.GotoStatement) or
    TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.LabeledStatement) then
  begin
    Exit(Fail('goto', AReason));
  end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.WithStatement) then
  begin
    Exit(Fail('with', AReason));
  end;
  if TRoutineLocals.HasKind(CalleeBody, TSyntaxKind.AnonymousMethod) then
  begin
    Exit(Fail('anonyme Methode im Rumpf', AReason));
  end;
  if UsesName(CalleeBody, ShortName) then
  begin
    Exit(Fail('rekursiv', AReason));
  end;
  Nodes := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.MemberAccess, Nodes);
    for Node in Nodes do
    begin
      if SameText(Node.Name, ShortName) then
      begin
        Exit(Fail('rekursiv', AReason));
      end;
    end;
  finally
    Nodes.Free;
  end;
  // Der Aufruf.
  CallerRoutine := TRoutineBody.RoutineAt(ACaller.Tree, Call.NameOffset);
  if (ACaller.Tree = ACallee.Tree) and (CallerRoutine = ARoutine) then
  begin
    Exit(Fail('rekursiv', AReason));
  end;
  CallerBody := TRoutineBody.BodyOf(CallerRoutine);
  CallerClass := '';
  if CallerRoutine.Name.LastIndexOf('.') > 0 then
  begin
    CallerClass := CallerRoutine.Name.Substring(0, CallerRoutine.Name.LastIndexOf('.'));
  end;
  ReceiverText := '';
  if IsMethod and (Call.Receiver <> nil) then
  begin
    if not IsSimpleChain(Call.Receiver) then
    begin
      Exit(Fail('der Empfänger ist kein einfacher Name', AReason));
    end;
    if not SameText(TRoutineBody.TextOf(ACaller.Text, Call.Receiver), 'Self') then
    begin
      ReceiverText := TRoutineBody.TextOf(ACaller.Text, Call.Receiver);
    end;
  end
  else if IsMethod and (CallerClass = '') then
  begin
    Exit(Fail('Methode ohne Empfänger', AReason));
  end;
  if Inside(Call.Node, TSyntaxKind.WithStatement, CallerBody) then
  begin
    Exit(Fail('der Aufruf steht in einem with-Rumpf', AReason));
  end;
  if not AOptions.InlineVar and Inside(Call.Node, TSyntaxKind.AnonymousMethod, CallerBody) then
  begin
    Exit(Fail('der Aufruf steht in einer anonymen Methode', AReason));
  end;
  if Call.Statement = nil then
  begin
    if not IsFunction then
    begin
      Exit(Fail('Prozedur im Ausdruck', AReason));
    end;
    Host := TRoutineBody.HostStatement(Call.Node, CallerBody);
    if Host = nil then
    begin
      Exit(Fail('an dieser Stelle nicht einbettbar', AReason));
    end;
    // Der Rumpf liefe vor allem, was in der Anweisung davor steht.
    Nodes := TList<TSyntaxNode>.Create;
    try
      TRoutineLocals.CollectKind(Host, TSyntaxKind.Call, Nodes);
      TRoutineLocals.CollectKind(Host, TSyntaxKind.InheritedExpr, Nodes);
      for Node in Nodes do
      begin
        if (Node.EndOffset <= Call.Node.StartOffset) and ((Node.Kind = TSyntaxKind.InheritedExpr) or
          not CallIsPure(Node, ACaller, AOptions.Lookup)) then
        begin
          Exit(Fail('die Reihenfolge der Aufrufe änderte sich', AReason));
        end;
      end;
    finally
      Nodes.Free;
    end;
  end
  else
  begin
    Host := Call.Statement;
  end;
  // Parameter und Argumente.
  Parameters := nil;
  if Header <> nil then
  begin
    Node := Header.FindChild(TSyntaxKind.Parameters);
    if Node <> nil then
    begin
      for Index := 0 to Node.ChildCount - 1 do
      begin
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
            begin
              Parameter.DefaultValue := Node[Index][Node[Index].ChildCount - 1];
            end;
          end;
          Parameters := Parameters + [Parameter];
        end;
      end;
    end;
  end;
  if Length(Call.Arguments) > Length(Parameters) then
  begin
    Exit(Fail('zu viele Argumente', AReason));
  end;
  for Index := Length(Call.Arguments) to High(Parameters) do
  begin
    if Parameters[Index].DefaultValue = nil then
    begin
      Exit(Fail('zu wenige Argumente', AReason));
    end;
  end;
  Locals := TRoutineLocals.Collect(ACallee.Text, ACallee.Tree, ARoutine);
  CallerLocals := TRoutineLocals.Collect(ACaller.Text, ACaller.Tree, CallerRoutine);
  CalleeFlow := TFlowSignatures.FromTree(ACallee.Tree.Root);
  Graph := TControlFlowGraph.Build(ARoutine, CalleeFlow);
  try
    if not Graph.Complete then
    begin
      Exit(Fail('Syntaxfehler in der Methode', AReason));
    end;
    if IsFunction and (Graph.MayReadBeforeWrite('Result') <> TFlowAnswer.No) then
    begin
      Exit(Fail('Result wird vor dem Setzen gelesen', AReason));
    end;
  finally
    Graph.Free;
  end;
  // Result-Zuweisungen in Schleifen lassen sich nicht in eine einzelne Ersetzung übersetzen.
  if IsFunction then
  begin
    Nodes := TList<TSyntaxNode>.Create;
    try
      TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, Nodes);
      for Node in Nodes do
      begin
        if SameText(Node.Name, 'Result') and (TRoutineLocals.AccessOf(Node, CalleeFlow) <> TLocalAccess.Read) and
          InLoopWithout(Node, CalleeBody, CalleeBody) then
        begin
          Exit(Fail('Result wird in einer Schleife gesetzt', AReason));
        end;
      end;
    finally
      Nodes.Free;
    end;
  end;
  // Exit: höchstens eins, als letzte Anweisung oder als "if … then Exit" auf oberster Ebene.
  Statements := nil;
  for Index := 0 to CalleeBody.ChildCount - 1 do
  begin
    if CalleeBody[Index].Kind <> TSyntaxKind.EmptyStatement then
    begin
      Statements := Statements + [CalleeBody[Index]];
    end;
  end;
  ExitMode := TExitMode.NoExit;
  ExitStatement := nil;
  ExitValue := nil;
  Guard := nil;
  GuardIndex := -1;
  Exits := TList<TSyntaxNode>.Create;
  try
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, Exits);
    for Node in Exits do
    begin
      if SameText(Node.Name, 'Exit') then
      begin
        if ExitStatement <> nil then
        begin
          Exit(Fail('mehrere Exit', AReason));
        end;
        ExitStatement := Node;
      end;
    end;
  finally
    Exits.Free;
  end;
  if ExitStatement <> nil then
  begin
    if (ExitStatement.ChildCount > 0) and (ExitStatement[0].Kind = TSyntaxKind.Call) and
      (ExitStatement[0].ChildCount > 1) then
    begin
      ExitValue := ExitStatement[0][1];
    end;
    if (ExitStatement.Parent = CalleeBody) and (Statements <> nil) and
      (Statements[High(Statements)] = ExitStatement) then
    begin
      ExitMode := TExitMode.LastExit;
    end
    else if (ExitStatement.Parent.Kind = TSyntaxKind.IfStatement) and (ExitStatement.Parent.Parent = CalleeBody) and
      (ExitStatement.Parent.ChildCount = 2) and (ExitStatement.Parent[1] = ExitStatement) then
    begin
      ExitMode := TExitMode.GuardExit;
      Guard := ExitStatement.Parent;
      for Index := 0 to High(Statements) do
      begin
        if Statements[Index] = Guard then
        begin
          GuardIndex := Index;
        end;
      end;
    end
    else
    begin
      Exit(Fail('Exit mitten im Rumpf', AReason));
    end;
  end;
  // Einfache Form: nur "Result := E" bzw. "Exit(E)" ersetzt den Aufruf direkt.
  SimpleExpression := nil;
  if IsFunction and (Call.Statement = nil) and (Length(Statements) = 1) and (ExitMode <> TExitMode.GuardExit) then
  begin
    Node := Statements[0];
    if (Node.Kind = TSyntaxKind.AssignStatement) and (Node[0].Kind = TSyntaxKind.Identifier) and
      SameText(Node[0].Name, 'Result') then
    begin
      SimpleExpression := Node[1];
    end
    else if (ExitMode = TExitMode.LastExit) and (ExitValue <> nil) then
    begin
      SimpleExpression := ExitValue;
    end;
    for Index := 0 to High(Locals) do
    begin
      if Locals[Index].Kind <> TLocalKind.Parameter then
      begin
        SimpleExpression := nil;
      end;
    end;
    if (SimpleExpression <> nil) and UsesName(SimpleExpression, 'Result') then
    begin
      SimpleExpression := nil;
    end;
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
    begin
      Outer := Outer.Parent;
    end;
    for Index := TRoutineBody.TokenAt(CallerTokens, Outer.StartOffset) to High(CallerTokens) do
    begin
      if CallerTokens[Index].Offset >= Outer.EndOffset then
      begin
        Break;
      end;
      if CallerTokens[Index].Kind = TPascalTokenKind.Identifier then
      begin
        Taken.AddOrSetValue(LowerCase(CallerTokens[Index].Text), True);
      end;
    end;
    // Fremde Namen der Methode: gleiche Bedeutung am Aufruf, Mitglieder mit Empfänger.
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Index].Kind <> TSyntaxKind.RoutineHeader then
      begin
        TRoutineLocals.CollectKind(ARoutine[Index], TSyntaxKind.Identifier, Nodes);
      end;
    end;
    Mutates := False;
    for Node in Nodes do
    begin
      if SameText(Node.Name, 'Exit') and IsCallee(Node) then
      begin
        Continue;
      end;
      LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
      if (LocalIndex < 0) and (Node.StartOffset < CalleeBody.StartOffset) then
      begin
        // var- und const-Abschnitt: Konstanten der Methode gelten dort auch.
        for Inner := 0 to High(Locals) do
        begin
          if (Locals[Inner].Kind = TLocalKind.Constant) and SameText(Locals[Inner].Name, Node.Name) then
          begin
            LocalIndex := Inner;
          end;
        end;
      end;
      if LocalIndex >= 0 then
      begin
        if (Locals[LocalIndex].Kind = TLocalKind.Parameter) and
          (Locals[LocalIndex].Decl.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
          (TRoutineLocals.AccessOf(Node, CalleeFlow) <> TLocalAccess.Read) then
        begin
          Mutates := True;
        end;
        Continue;
      end;
      if IsFunction and SameText(Node.Name, 'Result') then
      begin
        Continue;
      end;
      if SameText(Node.Name, 'Self') then
      begin
        if ReceiverText <> '' then
        begin
          Replace(Node.StartOffset, Node.EndOffset, ReceiverText);
        end;
        Continue;
      end;
      if (Node.Parent.Kind = TSyntaxKind.AssignStatement) and (Node.Parent[0] = Node) then
      begin
        Mutates := True;
      end;
      Taken.AddOrSetValue(LowerCase(Node.Name), True);
      if not Assigned(AOptions.Lookup) then
      begin
        Continue;
      end;
      Found := Meaning(AOptions.Lookup, ACallee, [Node.Name], Node.StartOffset);
      if not Found.Found then
      begin
        Exit(Fail(Node.Name + ' unbekannt', AReason));
      end;
      if Found.IsRoutine then
      begin
        Mutates := True;
      end;
      AtCall := Meaning(AOptions.Lookup, ACaller, [Node.Name], Call.NameOffset);
      if Found.IsMember and IsMethod then
      begin
        if ReceiverText <> '' then
        begin
          if not Visible(Found) then
          begin
            Exit(Fail(Node.Name + ' ist am Aufruf nicht sichtbar', AReason));
          end;
          Replace(Node.StartOffset, Node.EndOffset, ReceiverText + '.' + Node.Name);
        end
        else if AtCall.Key <> Found.Key then
        begin
          Replace(Node.StartOffset, Node.EndOffset, 'Self.' + Node.Name);
        end;
      end
      else if not AtCall.Found or (AtCall.Key <> Found.Key) then
      begin
        Exit(Fail(Node.Name + ' bedeutet am Aufruf etwas anderes', AReason));
      end;
    end;
    Nodes.Clear;
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Call, Nodes);
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.CallStatement, Nodes);
    for Node in Nodes do
    begin
      if not SameText(Node.Name, 'Exit') and ((Node.Kind = TSyntaxKind.CallStatement) or
        not CallIsPure(Node, ACallee, AOptions.Lookup)) then
      begin
        Mutates := True;
      end;
    end;
    Nodes.Clear;
    TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.AssignStatement, Nodes);
    for Node in Nodes do
    begin
      if Node[0].Kind <> TSyntaxKind.Identifier then
      begin
        Mutates := True;
      end;
    end;
    // Typen der neuen Deklarationen.
    for Index := 0 to High(Locals) do
    begin
      if (Locals[Index].Kind <> TLocalKind.Parameter) and not SameType(Locals[Index].Decl) then
      begin
        Exit(Fail('ein Typ bedeutet am Aufruf etwas anderes', AReason));
      end;
    end;
    if not SameType(ReturnType) then
    begin
      Exit(Fail('der Ergebnistyp bedeutet am Aufruf etwas anderes', AReason));
    end;
    // Lokale Namen der Methode: eindeutig gegen die Routine am Aufruf.
    SetLength(NewNames, Length(Locals));
    for Index := 0 to High(Locals) do
    begin
      if Locals[Index].Kind <> TLocalKind.Parameter then
      begin
        NewNames[Index] := Unique(Locals[Index].Name);
      end;
    end;
    Nodes.Clear;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      if ARoutine[Index].Kind <> TSyntaxKind.RoutineHeader then
      begin
        TRoutineLocals.CollectKind(ARoutine[Index], TSyntaxKind.Identifier, Nodes);
      end;
    end;
    for Node in Nodes do
    begin
      LocalIndex := TRoutineLocals.IndexOf(Locals, Node.Name, Node.StartOffset);
      if (LocalIndex < 0) and (Node.StartOffset < CalleeBody.StartOffset) then
      begin
        for Inner := 0 to High(Locals) do
        begin
          if (Locals[Inner].Kind = TLocalKind.Constant) and SameText(Locals[Inner].Name, Node.Name) then
          begin
            LocalIndex := Inner;
          end;
        end;
      end;
      if (LocalIndex >= 0) and (Locals[LocalIndex].Kind <> TLocalKind.Parameter) then
      begin
        Replace(Node.StartOffset, Node.EndOffset, NewNames[LocalIndex]);
      end;
    end;
    // Namen in Inline-Deklarationen und for var.
    for Index := 0 to High(Locals) do
    begin
      if Locals[Index].Kind in [TLocalKind.InlineVariable, TLocalKind.LoopVariable] then
      begin
        NameToken := TRoutineBody.TokenAt(CalleeTokens, Locals[Index].Decl.StartOffset);
        while (NameToken <= High(CalleeTokens)) and (CalleeTokens[NameToken].Offset < Locals[Index].Decl.EndOffset) and
          not CalleeTokens[NameToken].IsSymbol(':') and not CalleeTokens[NameToken].IsSymbol(':=') and
          not CalleeTokens[NameToken].IsSymbol('=') and not CalleeTokens[NameToken].IsKeyword('in') do
        begin
          if (CalleeTokens[NameToken].Kind = TPascalTokenKind.Identifier) and
            SameText(CalleeTokens[NameToken].Text, Locals[Index].Name) then
          begin
            Replace(CalleeTokens[NameToken].Offset, CalleeTokens[NameToken].Offset +
              Length(CalleeTokens[NameToken].Text), NewNames[Index]);
          end;
          Inc(NameToken);
        end;
      end
      else if Locals[Index].Kind = TLocalKind.Constant then
      begin
        NameToken := NextSignificant(CalleeTokens, TRoutineBody.TokenAt(CalleeTokens, Locals[Index].Decl.StartOffset));
        Replace(CalleeTokens[NameToken].Offset, CalleeTokens[NameToken].Offset + Length(CalleeTokens[NameToken].Text),
          NewNames[Index]);
      end;
    end;
    // Parameter: Argument direkt, sonst Hilfsvariable.
    Lines := nil;
    VarEntries := nil;
    ConstEntries := nil;
    SetLength(ParameterText, Length(Parameters));
    ArgumentNames := nil;
    for Index := 0 to High(Parameters) do
    begin
      if (Parameters[Index].Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam]) and
        (Index <= High(Call.Arguments)) and IsSimpleChain(Call.Arguments[Index]) then
      begin
        ArgumentNames := ArgumentNames + [ChainNames(Call.Arguments[Index])[0]];
      end;
    end;
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
        begin
          for Node in Nodes do
          begin
            Found := Meaning(AOptions.Lookup, ACallee, [Node.Name], Node.StartOffset);
            AtCall := Meaning(AOptions.Lookup, ACaller, [Node.Name], Call.NameOffset);
            if not Found.Found or not AtCall.Found or (Found.Key <> AtCall.Key) then
            begin
              Exit(Fail('der Vorgabewert von ' + Parameter.Name + ' bedeutet am Aufruf etwas anderes', AReason));
            end;
          end;
        end;
      end;
      Occurrences.Clear;
      Nodes.Clear;
      TRoutineLocals.CollectKind(CalleeBody, TSyntaxKind.Identifier, Nodes);
      for Node in Nodes do
      begin
        if SameText(Node.Name, Parameter.Name) and (TRoutineLocals.IndexOf(Locals, Node.Name,
          Node.StartOffset) >= 0) and (Locals[TRoutineLocals.IndexOf(Locals, Node.Name,
          Node.StartOffset)].Kind = TLocalKind.Parameter) then
        begin
          Occurrences.Add(Node);
        end;
      end;
      if Parameter.Modifier in [TParameterModifier.VarParam, TParameterModifier.OutParam] then
      begin
        if (Index > High(Call.Arguments)) or not TRoutineBody.IsVariableChain(Argument) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.Call) then
        begin
          Exit(Fail('das Argument für ' + Parameter.Name + ' ist keine einfache Variable', AReason));
        end;
        ParameterText[Index] := Text;
        for Node in Occurrences do
        begin
          Replace(Node.StartOffset, Node.EndOffset, Text);
        end;
        Continue;
      end;
      Written := False;
      Reads := 0;
      InLoop := False;
      for Node in Occurrences do
      begin
        if TRoutineLocals.AccessOf(Node, CalleeFlow) <> TLocalAccess.Read then
        begin
          Written := True;
        end;
        Inc(Reads);
        if InLoopWithout(Node, CalleeBody, CalleeBody) then
        begin
          InLoop := True;
        end;
      end;
      if Parameter.Modifier in [TParameterModifier.ConstParam, TParameterModifier.ConstRefParam] then
      begin
        Written := False;
      end;
      if Index <= High(Call.Arguments) then
      begin
        Pure := not HasSideEffects(Argument, ACaller, AOptions.Lookup);
      end
      else
      begin
        Pure := not HasSideEffects(Argument, ACallee, AOptions.Lookup);
      end;
      // Stabil: ändert sich während des Rumpfs nicht.
      Stable := Pure and ((Argument.Kind = TSyntaxKind.Literal) or not Mutates);
      if Pure and not Stable and (Index <= High(Call.Arguments)) then
      begin
        Stable := True;
        Nodes.Clear;
        TRoutineLocals.CollectKind(Argument, TSyntaxKind.Identifier, Nodes);
        for Node in Nodes do
        begin
          if not IsCallee(Node) and ((TRoutineLocals.IndexOf(CallerLocals, Node.Name, Node.StartOffset) < 0) and
            not MatchText(Node.Name, ConstantNames)) or (IndexText(Node.Name, ArgumentNames) >= 0) then
          begin
            Stable := False;
          end;
        end;
        if TRoutineLocals.HasKind(Argument, TSyntaxKind.Dereference) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.MemberAccess) or
          TRoutineLocals.HasKind(Argument, TSyntaxKind.IndexAccess) then
        begin
          Stable := False;
        end;
      end;
      Simple := Argument.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess,
        TSyntaxKind.ParenExpr];
      if not Written and Stable and (Simple or ((Reads <= 1) and not InLoop)) then
      begin
        ParameterText[Index] := Text;
        for Node in Occurrences do
        begin
          Replace(Node.StartOffset, Node.EndOffset, Parenthesized(Text, Argument, Node));
        end;
        Continue;
      end;
      if Parameter.TypeText = '' then
      begin
        Exit(Fail('untypisierter Parameter ' + Parameter.Name, AReason));
      end;
      if not SameType(Parameter.TypeNode) then
      begin
        Exit(Fail('der Typ von ' + Parameter.Name + ' bedeutet am Aufruf etwas anderes', AReason));
      end;
      ParameterText[Index] := Unique(Parameter.Name);
      for Node in Occurrences do
      begin
        Replace(Node.StartOffset, Node.EndOffset, ParameterText[Index]);
      end;
      if AOptions.InlineVar then
      begin
        Lines := Lines + ['var ' + ParameterText[Index] + ': ' + Parameter.TypeText + ' := ' + Text];
      end
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
      begin
        if SameText(Node.Name, 'Result') then
        begin
          Replace(Node.StartOffset, Node.EndOffset, ResultName);
        end;
      end;
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
          begin
            Lines := Lines + ['var ' + NewNames[Index] + ': ' + RenderNode(Locals[Index].Decl[0])];
          end
          else
          begin
            VarEntries := VarEntries + [NewNames[Index] + ': ' + RenderNode(Locals[Index].Decl[0]) + ';'];
          end;
        TLocalKind.Constant:
          ConstEntries := ConstEntries + [RenderNode(Locals[Index].Decl)];
      end;
    if ResultName <> '' then
    begin
      if AOptions.InlineVar then
      begin
        Lines := Lines + ['var ' + ResultName + ': ' + ResultType];
      end
      else
      begin
        VarEntries := VarEntries + [ResultName + ': ' + ResultType + ';'];
      end;
    end;
    // Rumpf.
    if SimpleExpression = nil then
    begin
      for Index := 0 to High(Statements) do
      begin
        Node := Statements[Index];
        if (ExitMode = TExitMode.LastExit) and (Node = ExitStatement) then
        begin
          if (ExitValue <> nil) and (ResultName <> '') then
          begin
            Lines := Lines + [ResultName + ' := ' + RenderNode(ExitValue)];
          end;
          Continue;
        end;
        if (ExitMode = TExitMode.GuardExit) and (Index = GuardIndex) then
        begin
          RestLines := nil;
          for Inner := Index + 1 to High(Statements) do
          begin
            RestLines := RestLines + [Normalized(Statements[Inner])];
          end;
          Condition := RenderNode(Guard[0]);
          if (ExitValue <> nil) and (ResultName <> '') then
          begin
            Text := 'if ' + Condition + ' then' + LineBreak + Unit_ + ResultName + ' := ' + RenderNode(ExitValue);
            if RestLines <> nil then
            begin
              Text := Text + LineBreak + 'else' + LineBreak + 'begin' + LineBreak +
                JoinStatements(RestLines, Unit_, LineBreak, True) + ';' + LineBreak + 'end';
            end;
            Lines := Lines + [Text];
          end
          else if RestLines <> nil then
          begin
            if (Guard[0].Kind = TSyntaxKind.UnaryExpr) and SameText(Guard[0].Name, 'not') then
            begin
              Text := RenderNode(Guard[0][0]);
            end
            else
            begin
              Text := Negated(Condition, Guard[0]);
            end;
            Lines := Lines + ['if ' + Text + ' then' + LineBreak + 'begin' + LineBreak +
              JoinStatements(RestLines, Unit_, LineBreak, True) + ';' + LineBreak + 'end'];
          end
          else if HasSideEffects(Guard[0], ACallee, AOptions.Lookup) then
          begin
            Lines := Lines + ['if ' + Condition + ' then' + LineBreak + 'begin' + LineBreak + 'end'];
          end;
          Break;
        end;
        Lines := Lines + [Normalized(Node)];
      end;
    end;
    // Bearbeitungen am Aufruf.
    Indent := TTextLines.IndentOf(ACaller.Text, Host.StartPos.Line);
    if Call.Statement <> nil then
    begin
      if Lines = nil then
      begin
        NewText := '';
      end
      else if TRoutineBody.InList(Host) then
      begin
        NewText := JoinStatements(Lines, Indent, LineBreak, False);
      end
      else
      begin
        NewText := 'begin' + LineBreak + JoinStatements(Lines, Indent + Unit_, LineBreak, True) + ';' + LineBreak +
          Indent + 'end';
      end;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.EndPos), NewText)];
    end
    else
    begin
      if SimpleExpression <> nil then
      begin
        Replacement := Parenthesized(RenderNode(SimpleExpression), SimpleExpression, Call.Node);
      end
      else
      begin
        Replacement := ResultName;
      end;
      NewText := '';
      if Lines <> nil then
      begin
        NewText := JoinStatements(Lines, Indent, LineBreak, False) + ';' + LineBreak + Indent;
      end;
      if Call.Node.StartOffset = Host.StartOffset then
      begin
        Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call.Node.StartPos, Call.Node.EndPos),
          NewText + Replacement)];
      end
      else
      begin
        if NewText <> '' then
        begin
          Edits := Edits + [TTextEdit.Create(TTextRange.Create(Host.StartPos, Host.StartPos), NewText)];
        end;
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
  begin
    AAction.Title := Format('Methode %s einbetten', [ShortName]);
  end
  else
  begin
    AAction.Title := Format('Routine %s einbetten', [ShortName]);
  end;
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
  begin
    Result := Result + [Action];
  end;
  if CallAt(ASource.Tree, ASource.Text, APosition, Call) then
  begin
    Routines := FindRoutines(ASource.Tree, Call.Name);
    if (Length(Routines) = 1) and InlineMethod(ASource, APosition, ASource, Routines[0], AOptions, Action) then
    begin
      Result := Result + [Action];
    end;
  end;
end;

end.
