unit Atlas.Common.Metrics.Calculator;

// Kennzahlen je Routine aus dem Syntaxbaum (#66); Zählweise siehe
// Atlas.Common.Metrics.Contract. Gemessen wird jede Routine mit Rumpf
// (begin … end), auch lokale Routinen; Routinen mit asm-Rumpf und forward-
// bzw. external-Deklarationen nicht. Anonyme Methoden gehören zur Routine, in
// der sie stehen (kognitiv eine Ebene tiefer).
//
// Einzelheiten:
//   - else erkennt der Calculator auch ohne then-Zweig (if A then else B)
//     am Schlüsselwort vor dem Zweig.
//   - and/or zählen nur in Bedingungen (if, while, until, Bedingungsausdruck):
//     dort sind sie logisch; anderswo können sie bitweise sein.
//   - Rekursion erhöht die kognitive Komplexität nicht (dafür bräuchte es
//     die Namensauflösung).
//   - Implementierungen ohne Parameterliste (procedure TFoo.Bar;) nehmen die
//     Parameter der Deklaration in derselben Datei.
// Der Baum wird iterativ durchlaufen: Lange Ausdrucksketten ergeben sehr
// tiefe Bäume.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Metrics.Contract;

type
  TMetricsCalculator = class
  public
    /// <summary>Kennzahlen aller Routinen mit Rumpf in ATree, nach Position im Quelltext.</summary>
    class function Routines(ATree: TSyntaxTree): TArray<TRoutineMetrics>; static;
    /// <summary>Parst AText und liefert die Kennzahlen seiner Routinen.</summary>
    class function ForText(const AText: string): TArray<TRoutineMetrics>; static;
    /// <summary>Codezeilen von ARoutine (RoutineDecl) ohne Leerzeilen, Kommentare, Direktiven und lokale
    /// Routinen.</summary>
    class function CodeLines(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Verschachtelungstiefe von ARoutine (RoutineDecl); 0 ohne Kontrollstruktur.</summary>
    class function NestingDepth(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Zyklomatische Komplexität von ARoutine (RoutineDecl); mindestens 1.</summary>
    class function Cyclomatic(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Kognitive Komplexität von ARoutine (RoutineDecl).</summary>
    class function Cognitive(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer; static;
    /// <summary>Parameternamen in der Liste von AHeader (RoutineHeader); 0 ohne Liste.</summary>
    class function ParameterCount(AHeader: TSyntaxNode): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Parser;

const
  ExpressionKinds = [TSyntaxKind.Identifier, TSyntaxKind.Literal, TSyntaxKind.MemberAccess, TSyntaxKind.Call,
    TSyntaxKind.IndexAccess, TSyntaxKind.Dereference, TSyntaxKind.AddressOf, TSyntaxKind.GenericArgs,
    TSyntaxKind.SetConstructor, TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.ParenExpr,
    TSyntaxKind.InheritedExpr, TSyntaxKind.RangeExpr, TSyntaxKind.IfExpr];
  LoopKinds = [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
  TypeBodyKinds = [TSyntaxKind.ClassType, TSyntaxKind.ObjectType, TSyntaxKind.RecordType,
    TSyntaxKind.InterfaceType, TSyntaxKind.HelperType];

type
  /// <summary>Ein Knoten auf dem Stapel des Durchlaufs.</summary>
  TVisit = record
    Node: TSyntaxNode;
    /// <summary>Zahl der umgebenden Kontrollstrukturen (Verschachtelungstiefe).</summary>
    Depth: Integer;
    /// <summary>Schachtelungsebene der kognitiven Komplexität.</summary>
    Level: Integer;
    /// <summary>Der Knoten steht in einer Bedingung.</summary>
    Condition: Boolean;
    /// <summary>Der Knoten ist der else-Zweig eines if und selbst ein if (else if).</summary>
    ElseIf: Boolean;
  end;

  /// <summary>Ergebnis eines Durchlaufs über den Rumpf einer Routine.</summary>
  TFlow = record
    Depth: Integer;
    Cyclomatic: Integer;
    Cognitive: Integer;
  end;

function Visit(ANode: TSyntaxNode; ADepth, ALevel: Integer; ACondition, AElseIf: Boolean): TVisit;
begin
  Result.Node := ANode;
  Result.Depth := ADepth;
  Result.Level := ALevel;
  Result.Condition := ACondition;
  Result.ElseIf := AElseIf;
end;

/// <summary>Index des ersten Tokens mit Offset ab AOffset.</summary>
function FirstTokenAt(const ATokens: TArray<TPascalToken>; AOffset: Integer): Integer;
var
  Left, Right, Middle: Integer;
begin
  Left := 0;
  Right := Length(ATokens);
  while Left < Right do
  begin
    Middle := (Left + Right) div 2;
    if ATokens[Middle].Offset < AOffset then
      Left := Middle + 1
    else
      Right := Middle;
  end;
  Result := Left;
end;

/// <summary>Steht vor ANode (ohne Kommentare und Direktiven) das Schlüsselwort else?</summary>
function AfterElse(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode): Boolean;
var
  Index: Integer;
begin
  Index := FirstTokenAt(ATokens, ANode.StartOffset) - 1;
  while (Index >= 0) and ((ATokens[Index].Kind = TPascalTokenKind.Comment) or
    (ATokens[Index].Kind = TPascalTokenKind.Directive)) do
    Dec(Index);
  Result := (Index >= 0) and ATokens[Index].IsKeyword('else');
end;

/// <summary>else-Zweig eines if; nil ohne.</summary>
function ElseBranch(const ATokens: TArray<TPascalToken>; AIf: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if AIf.ChildCount >= 3 then
    Result := AIf[2]
  else if (AIf.ChildCount = 2) and AfterElse(ATokens, AIf[1]) then
    Result := AIf[1];
end;

function IsLogical(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.BinaryExpr) and (SameText(ANode.Name, 'and') or SameText(ANode.Name, 'or'));
end;

/// <summary>Setzt ANode (and/or) eine Folge desselben Operators fort? Klammern zählen nicht.</summary>
function ContinuesSequence(ANode: TSyntaxNode): Boolean;
var
  Parent: TSyntaxNode;
begin
  Parent := ANode.Parent;
  while (Parent <> nil) and (Parent.Kind = TSyntaxKind.ParenExpr) do
    Parent := Parent.Parent;
  Result := (Parent <> nil) and (Parent.Kind = TSyntaxKind.BinaryExpr) and SameText(Parent.Name, ANode.Name);
end;

function BodyOf(ARoutine: TSyntaxNode): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  if ARoutine = nil then
    Exit;
  for Index := ARoutine.ChildCount - 1 downto 0 do
    if ARoutine[Index].Kind = TSyntaxKind.Block then
      Exit(ARoutine[Index]);
end;

/// <summary>Ein Durchlauf über den Rumpf: Tiefe, zyklomatische und kognitive Komplexität.</summary>
function Analyze(ATree: TSyntaxTree; ARoutine: TSyntaxNode): TFlow;
var
  Tokens: TArray<TPascalToken>;
  Stack: TStack<TVisit>;
  Item: TVisit;
  Node, Branch: TSyntaxNode;
  Index, Handlers: Integer;
  Inner: Boolean;
  Flow: TFlow;

  procedure Push(AChild: TSyntaxNode; ADepth, ALevel: Integer; ACondition: Boolean);
  begin
    Stack.Push(Visit(AChild, ADepth, ALevel, ACondition, False));
  end;

  procedure Reach(ADepth: Integer);
  begin
    if ADepth > Flow.Depth then
      Flow.Depth := ADepth;
  end;

begin
  Flow.Depth := 0;
  Flow.Cyclomatic := 1;
  Flow.Cognitive := 0;
  Result := Flow;
  Node := BodyOf(ARoutine);
  if Node = nil then
    Exit;
  Tokens := ATree.Tokens;
  Stack := TStack<TVisit>.Create;
  try
    Push(Node, 0, 0, False);
    while Stack.Count > 0 do
    begin
      Item := Stack.Pop;
      Node := Item.Node;
      case Node.Kind of
        TSyntaxKind.RoutineDecl:
          // Lokale Routinen zählen für sich.
          Continue;
        TSyntaxKind.IfStatement:
          begin
            Inc(Flow.Cyclomatic);
            Reach(Item.Depth + 1);
            if Item.ElseIf then
              Inc(Flow.Cognitive)
            else
              Inc(Flow.Cognitive, 1 + Item.Level);
            Branch := ElseBranch(Tokens, Node);
            for Index := 0 to Node.ChildCount - 1 do
              if Index = 0 then
                Push(Node[Index], Item.Depth, Item.Level, True)
              else if Node[Index] = Branch then
              begin
                if Branch.Kind = TSyntaxKind.IfStatement then
                  // else if: gleiche Ebene wie das if, +1 beim inneren if.
                  Stack.Push(Visit(Branch, Item.Depth, Item.Level, False, True))
                else
                begin
                  Inc(Flow.Cognitive);
                  Push(Branch, Item.Depth + 1, Item.Level + 1, False);
                end;
              end
              else
                Push(Node[Index], Item.Depth + 1, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.IfExpr:
          begin
            Inc(Flow.Cyclomatic);
            Inc(Flow.Cognitive, 1 + Item.Level);
            for Index := 0 to Node.ChildCount - 1 do
              if Index = 0 then
                Push(Node[Index], Item.Depth, Item.Level, True)
              else
                Push(Node[Index], Item.Depth, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.CaseStatement:
          begin
            Reach(Item.Depth + 1);
            Inc(Flow.Cognitive, 1 + Item.Level);
            for Index := 0 to Node.ChildCount - 1 do
              if Index = 0 then
                Push(Node[Index], Item.Depth, Item.Level, False)
              else
                Push(Node[Index], Item.Depth + 1, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.CaseItem:
          Inc(Flow.Cyclomatic);
        TSyntaxKind.TryStatement:
          begin
            // Nur die Tiefe; kognitiv zählt erst der except-Teil.
            Reach(Item.Depth + 1);
            for Index := 0 to Node.ChildCount - 1 do
              Push(Node[Index], Item.Depth + 1, Item.Level, False);
            Continue;
          end;
        TSyntaxKind.ExceptBlock:
          begin
            Handlers := 0;
            for Index := 0 to Node.ChildCount - 1 do
              if Node[Index].Kind = TSyntaxKind.ExceptionHandler then
                Inc(Handlers);
            if Handlers = 0 then
            begin
              Inc(Flow.Cyclomatic);
              Inc(Flow.Cognitive, 1 + Item.Level);
            end;
            for Index := 0 to Node.ChildCount - 1 do
              if Node[Index].Kind = TSyntaxKind.ExceptionHandler then
                Push(Node[Index], Item.Depth, Item.Level, False)
              else
                Push(Node[Index], Item.Depth, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.ExceptionHandler:
          begin
            Inc(Flow.Cyclomatic);
            Inc(Flow.Cognitive, 1 + Item.Level);
            for Index := 0 to Node.ChildCount - 1 do
              Push(Node[Index], Item.Depth, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.GotoStatement:
          Inc(Flow.Cognitive);
        TSyntaxKind.AnonymousMethod:
          begin
            for Index := 0 to Node.ChildCount - 1 do
              Push(Node[Index], Item.Depth, Item.Level + 1, False);
            Continue;
          end;
        TSyntaxKind.BinaryExpr:
          if Item.Condition and IsLogical(Node) then
          begin
            Inc(Flow.Cyclomatic);
            if not ContinuesSequence(Node) then
              Inc(Flow.Cognitive);
          end;
      end;
      if Node.Kind in LoopKinds then
      begin
        Inc(Flow.Cyclomatic);
        Reach(Item.Depth + 1);
        Inc(Flow.Cognitive, 1 + Item.Level);
        for Index := 0 to Node.ChildCount - 1 do
          if ((Node.Kind = TSyntaxKind.WhileStatement) and (Index = 0)) or
            ((Node.Kind = TSyntaxKind.RepeatStatement) and (Index = Node.ChildCount - 1) and
            (Node[Index].Kind in ExpressionKinds)) then
            Push(Node[Index], Item.Depth, Item.Level, True)
          else
            Push(Node[Index], Item.Depth + 1, Item.Level + 1, False);
        Continue;
      end;
      // Alles andere reicht Tiefe und Ebene weiter; die Bedingung nur innerhalb von Ausdrücken.
      Inner := Item.Condition and (Node.Kind in ExpressionKinds);
      for Index := 0 to Node.ChildCount - 1 do
        Push(Node[Index], Item.Depth, Item.Level, Inner);
    end;
  finally
    Stack.Free;
  end;
  Result := Flow;
end;

/// <summary>Qualifizierter Name der Typen um ANode, z. B. "TFoo.TInner"; '' außerhalb von Typen.</summary>
function OwnerName(ANode: TSyntaxNode): string;
var
  Parent: TSyntaxNode;
begin
  Result := '';
  Parent := ANode.Parent;
  while Parent <> nil do
  begin
    if (Parent.Kind = TSyntaxKind.TypeDecl) and (Result = '') then
      Result := Parent.Name
    else if Parent.Kind = TSyntaxKind.TypeDecl then
      Result := Parent.Name + '.' + Result;
    Parent := Parent.Parent;
  end;
end;

/// <summary>Parameterzahl der Deklarationen in Typen: Großbuchstaben-Name → Zahl, -1 bei Überladungen.</summary>
function Declarations(ATree: TSyntaxTree): TDictionary<string, Integer>;
var
  Stack: TStack<TSyntaxNode>;
  Node: TSyntaxNode;
  Index, Count: Integer;
  Key: string;
begin
  Result := TDictionary<string, Integer>.Create;
  Stack := TStack<TSyntaxNode>.Create;
  try
    Stack.Push(ATree.Root);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if (Node.Kind = TSyntaxKind.RoutineHeader) and (Node.Parent <> nil) and (Node.Parent.Kind in TypeBodyKinds) then
      begin
        Key := UpperCase(OwnerName(Node) + '.' + Node.Name);
        Count := TMetricsCalculator.ParameterCount(Node);
        if Result.ContainsKey(Key) then
          Result[Key] := -1
        else
          Result.Add(Key, Count);
        Continue;
      end;
      // Rümpfe enthalten keine Typdeklarationen mit Methoden, die hier fehlen würden.
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] then
        Continue;
      for Index := 0 to Node.ChildCount - 1 do
        Stack.Push(Node[Index]);
    end;
  finally
    Stack.Free;
  end;
end;

/// <summary>Bereich des Namens im Kopf: Bezeichner mit Punkten, generische Parameter übersprungen.</summary>
function NameRangeOf(const ATokens: TArray<TPascalToken>; AHeader: TSyntaxNode): TTextRange;
var
  Index, Depth: Integer;
  First, Last: Integer;
begin
  Result := TTextRange.Create(AHeader.StartPos, AHeader.StartPos);
  Index := FirstTokenAt(ATokens, AHeader.StartOffset);
  while (Index < Length(ATokens)) and (ATokens[Index].Offset < AHeader.EndOffset) and
    (ATokens[Index].Kind <> TPascalTokenKind.Identifier) do
    Inc(Index);
  if (Index >= Length(ATokens)) or (ATokens[Index].Offset >= AHeader.EndOffset) then
    Exit;
  First := Index;
  Last := Index;
  Inc(Index);
  while Index < Length(ATokens) do
  begin
    if (ATokens[Index].Kind = TPascalTokenKind.Comment) or (ATokens[Index].Kind = TPascalTokenKind.Directive) then
    begin
      Inc(Index);
      Continue;
    end;
    if ATokens[Index].IsSymbol('<') then
    begin
      // TFoo<T>.Bar: bis zur passenden spitzen Klammer.
      Depth := 0;
      while Index < Length(ATokens) do
      begin
        if ATokens[Index].IsSymbol('<') then
          Inc(Depth)
        else if ATokens[Index].IsSymbol('>') then
        begin
          Dec(Depth);
          if Depth = 0 then
            Break;
        end
        else if ATokens[Index].IsSymbol('>>') then
        begin
          Dec(Depth, 2);
          if Depth <= 0 then
            Break;
        end;
        Inc(Index);
      end;
      Inc(Index);
      Continue;
    end;
    if ATokens[Index].IsSymbol('.') and (Index + 1 < Length(ATokens)) and
      (ATokens[Index + 1].Kind = TPascalTokenKind.Identifier) then
    begin
      Last := Index + 1;
      Inc(Index, 2);
      Continue;
    end;
    Break;
  end;
  Result := TTextRange.Create(ATokens[First].StartPos, ATokens[Last].EndPos);
end;

{ TMetricsCalculator }

class function TMetricsCalculator.ParameterCount(AHeader: TSyntaxNode): Integer;
var
  Parameters, Parameter: TSyntaxNode;
  Index, Position: Integer;
  Names: string;
begin
  Result := 0;
  if AHeader = nil then
    Exit;
  Parameters := AHeader.FindChild(TSyntaxKind.Parameters);
  if Parameters = nil then
    Exit;
  for Index := 0 to Parameters.ChildCount - 1 do
  begin
    Parameter := Parameters[Index];
    if Parameter.Kind <> TSyntaxKind.Parameter then
      Continue;
    Names := Trim(Parameter.Name);
    if Names = '' then
      Continue;
    Inc(Result);
    for Position := 1 to Length(Names) do
      if Names[Position] = ',' then
        Inc(Result);
  end;
end;

class function TMetricsCalculator.CodeLines(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
var
  Tokens: TArray<TPascalToken>;
  Lines: TDictionary<Integer, Boolean>;
  Skips: TArray<TSyntaxNode>;
  Skip: TSyntaxNode;
  Index, Line: Integer;
  Token: TPascalToken;
  Inside: Boolean;
begin
  Result := 0;
  if ARoutine = nil then
    Exit;
  Tokens := ATree.Tokens;
  Skips := nil;
  for Index := 0 to ARoutine.ChildCount - 1 do
    if ARoutine[Index].Kind = TSyntaxKind.RoutineDecl then
      Skips := Skips + [ARoutine[Index]];
  Lines := TDictionary<Integer, Boolean>.Create;
  try
    Index := FirstTokenAt(Tokens, ARoutine.StartOffset);
    while (Index < Length(Tokens)) and (Tokens[Index].Offset < ARoutine.EndOffset) do
    begin
      Token := Tokens[Index];
      Inc(Index);
      if (Token.Kind = TPascalTokenKind.Comment) or (Token.Kind = TPascalTokenKind.Directive) then
        Continue;
      Inside := False;
      for Skip in Skips do
        if (Token.Offset >= Skip.StartOffset) and (Token.Offset < Skip.EndOffset) then
          Inside := True;
      if Inside then
        Continue;
      for Line := Token.StartPos.Line to Token.EndPos.Line do
        Lines.AddOrSetValue(Line, True);
    end;
    Result := Lines.Count;
  finally
    Lines.Free;
  end;
end;

class function TMetricsCalculator.NestingDepth(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Depth;
end;

class function TMetricsCalculator.Cyclomatic(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Cyclomatic;
end;

class function TMetricsCalculator.Cognitive(ATree: TSyntaxTree; ARoutine: TSyntaxNode): Integer;
begin
  Result := Analyze(ATree, ARoutine).Cognitive;
end;

class function TMetricsCalculator.Routines(ATree: TSyntaxTree): TArray<TRoutineMetrics>;
var
  Stack: TStack<TSyntaxNode>;
  Found: TList<TSyntaxNode>;
  Node, Header, Parent: TSyntaxNode;
  Index, Count: Integer;
  Known: TDictionary<string, Integer>;
  Metrics: TRoutineMetrics;
  Flow: TFlow;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Found := TList<TSyntaxNode>.Create;
  Stack := TStack<TSyntaxNode>.Create;
  Known := nil;
  try
    Stack.Push(ATree.Root);
    while Stack.Count > 0 do
    begin
      Node := Stack.Pop;
      if Node.Kind = TSyntaxKind.RoutineDecl then
      begin
        if BodyOf(Node) <> nil then
          Found.Add(Node);
        // Lokale Routinen stehen als Kinder darin.
        for Index := Node.ChildCount - 1 downto 0 do
          if Node[Index].Kind = TSyntaxKind.RoutineDecl then
            Stack.Push(Node[Index]);
        Continue;
      end;
      if Node.Kind in [TSyntaxKind.Block, TSyntaxKind.AsmBlock] + ExpressionKinds then
        Continue;
      for Index := Node.ChildCount - 1 downto 0 do
        Stack.Push(Node[Index]);
    end;
    for Node in Found do
    begin
      Metrics := Default(TRoutineMetrics);
      Metrics.Name := Node.Name;
      Parent := Node.Parent;
      while Parent <> nil do
      begin
        if Parent.Kind = TSyntaxKind.RoutineDecl then
          Metrics.Name := Parent.Name + '.' + Metrics.Name;
        Parent := Parent.Parent;
      end;
      Metrics.Range := TTextRange.Create(Node.StartPos, Node.EndPos);
      Header := Node.FindChild(TSyntaxKind.RoutineHeader);
      if Header <> nil then
        Metrics.NameRange := NameRangeOf(ATree.Tokens, Header)
      else
        Metrics.NameRange := TTextRange.Create(Node.StartPos, Node.StartPos);
      Metrics.Values[TMetricKind.MethodLength] := CodeLines(ATree, Node);
      Flow := Analyze(ATree, Node);
      Metrics.Values[TMetricKind.NestingDepth] := Flow.Depth;
      Metrics.Values[TMetricKind.Cyclomatic] := Flow.Cyclomatic;
      Metrics.Values[TMetricKind.Cognitive] := Flow.Cognitive;
      Count := ParameterCount(Header);
      if (Header <> nil) and (Header.FindChild(TSyntaxKind.Parameters) = nil) and (Pos('.', Node.Name) > 0) then
      begin
        // procedure TFoo.Bar; ohne Liste: Parameter der Deklaration.
        if Known = nil then
          Known := Declarations(ATree);
        if Known.TryGetValue(UpperCase(Node.Name), Index) and (Index > 0) then
          Count := Index;
      end;
      Metrics.Values[TMetricKind.ParameterCount] := Count;
      Result := Result + [Metrics];
    end;
  finally
    Known.Free;
    Stack.Free;
    Found.Free;
  end;
end;

class function TMetricsCalculator.ForText(const AText: string): TArray<TRoutineMetrics>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Result := Routines(Tree);
  finally
    Tree.Free;
  end;
end;

end.
