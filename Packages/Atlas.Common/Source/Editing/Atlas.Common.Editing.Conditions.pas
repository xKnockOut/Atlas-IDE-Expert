unit Atlas.Common.Editing.Conditions;

// Bedingungen umformen (#656), ohne die Bedeutung zu ändern:
//   Bedingung umkehren: if mit else; then- und else-Zweig tauschen, die
//     Bedingung lesbar verneinen (TExpressionText.Negate). Ist der then-Zweig
//     leer, entfällt das else.
//   Frühen Ausstieg einführen: if ohne else als letzte Anweisung einer Routine
//     (Exit) bzw. eines Schleifenrumpfs (Continue); der Zweig rückt eine Ebene
//     aus. Nicht bei Inline-Variablen im Zweig (ihr Gültigkeitsbereich würde
//     größer).
//   Verschachtelte if zusammenfassen: if A then if B then X (beide ohne else)
//     wird if A and B then X; die Reihenfolge bleibt (Kurzschluss).
//   Doppelte Verneinung entfernen: not not X, not (A <> B), not True.
// Klammern nur, wo der Vorrang sie verlangt. Kommentare in den Zweigen bleiben
// an ihrer Anweisung; ginge einer verloren (etwa in der Bedingung), gibt es
// die Aktion nicht.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Editing.StatementText;

type
  TConditions = class
  public const
    InvertTitle = 'Bedingung umkehren';
    EarlyExitTitle = 'Frühen Ausstieg einführen (Exit)';
    EarlyContinueTitle = 'Frühen Ausstieg einführen (Continue)';
    MergeTitle = 'Verschachtelte if zusammenfassen';
    DoubleNegationTitle = 'Doppelte Verneinung entfernen';
  public
    /// <summary>„Bedingung umkehren“ für das if, dessen Kopf APosition enthält (nur mit else).</summary>
    class function Invert(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>„Frühen Ausstieg einführen“ für das if ohne else, dessen Kopf APosition enthält.</summary>
    class function EarlyExit(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>„Verschachtelte if zusammenfassen“ auf dem Kopf des äußeren oder des inneren if.</summary>
    class function MergeNested(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>„Doppelte Verneinung entfernen“ für das äußerste not an APosition.</summary>
    class function RemoveDoubleNegation(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      out ARewrite: TStatementRewrite): Boolean; static;
    /// <summary>Alle Umformungen an APosition.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALayout: TStatementLayout): TArray<TStatementRewrite>; static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ExpressionText,
  Atlas.Text.Lines;

function LayoutAt(const AText: string; ANode: TSyntaxNode; const ALayout: TStatementLayout): TStatementLayout;
begin
  Result := TStatementLayout.Create(TTextLines.IndentOf(AText, ANode.StartPos.Line), ALayout.IndentUnit,
    ALayout.LineBreak);
end;

function HasElse(AIf: TSyntaxNode): Boolean;
begin
  Result := AIf.ChildCount >= 3;
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
    TSyntaxKind.WhileStatement]);
end;

/// <summary>Letzte echte Anweisung unter den Kindern 0..ALast von ANode; nil ohne.</summary>
function LastStatement(ANode: TSyntaxNode; ALast: Integer): TSyntaxNode;
var
  Index: Integer;
begin
  Result := nil;
  for Index := ALast downto 0 do
    if TRoutineBody.IsStatement(ANode[Index]) and (ANode[Index].Kind <> TSyntaxKind.EmptyStatement) then
      Exit(ANode[Index]);
end;

function HasInlineDeclaration(const AStatements: TArray<TSyntaxNode>): Boolean;
var
  Statement: TSyntaxNode;
begin
  for Statement in AStatements do
    if Statement.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
      Exit(True);
  Result := False;
end;

{ TConditions }

class function TConditions.Invert(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  Node, Parent: TSyntaxNode;
  Layout: TStatementLayout;
  Spans: TArray<TStatementSpan>;
  EndPos: TTextPosition;
  Suffix, Code: string;
  EmptyThen: Boolean;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  Node := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if (Node = nil) or not HasElse(Node) then
    Exit;
  EmptyThen := TStatementText.Statements(Node[1]) = nil;
  // Ohne else stünde das neue if vor dem else eines äußeren if und bekäme es (if Q then if A then else B else Z).
  Parent := Node.Parent;
  if EmptyThen and (Parent <> nil) and (Parent.Kind = TSyntaxKind.IfStatement) and HasElse(Parent) and
    (Parent[1] = Node) then
    Exit;
  Spans := TStatementText.Spans(ATree, [Node[1], Node[2]]);
  if TStatementText.Uncovered(ATree, Node.StartOffset, Node.EndOffset, Spans) then
    Exit;
  Layout := LayoutAt(AText, Node, ALayout);
  EndPos := TStatementText.ReplacementEnd(ATree, Node, Spans, Suffix);
  Code := 'if ' + TExpressionText.Negate(AText, Node[0]).Text + ' then';
  if EmptyThen then
    Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[2], Layout, False), Suffix)
  else
    Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[2], Layout, True), '') +
      Layout.LineBreak + Layout.Indent + 'else' +
      TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[1], Layout, False), Suffix);
  ARewrite := TStatementRewrite.Create(InvertTitle, TTextEdit.Create(TTextRange.Create(Node.StartPos, EndPos), Code));
  Result := True;
end;

class function TConditions.EarlyExit(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  Node, Parent, Owner: TSyntaxNode;
  Statements, Siblings: TArray<TSyntaxNode>;
  Spans: TArray<TStatementSpan>;
  Layout, Inner: TStatementLayout;
  Tokens: TArray<TPascalToken>;
  Keyword, Title, Suffix, Code, Guard: string;
  StartPos, EndPos: TTextPosition;
  StartOffset, DoToken: Integer;
  Wrap: Boolean;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  Node := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if (Node = nil) or HasElse(Node) then
    Exit;
  Statements := TStatementText.Statements(Node[1]);
  if (Statements = nil) or HasInlineDeclaration(Statements) then
    Exit;
  // Wo steht das if? Als letzte Anweisung des Rumpfs einer Routine, eines Schleifenrumpfs (begin … end oder
  // repeat … until) oder direkt als Rumpf einer Schleife.
  Parent := Node.Parent;
  Keyword := '';
  Wrap := False;
  if Parent = nil then
    Exit;
  if Parent.Kind = TSyntaxKind.Block then
  begin
    Siblings := TStatementText.Statements(Parent);
    if (Siblings = nil) or (Siblings[High(Siblings)] <> Node) then
      Exit;
    Owner := Parent.Parent;
    if (Owner <> nil) and (Owner.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
      Keyword := 'Exit'
    else if IsLoop(Owner) and (Owner[Owner.ChildCount - 1] = Parent) then
      Keyword := 'Continue';
  end
  else if Parent.Kind = TSyntaxKind.RepeatStatement then
  begin
    if (Parent.ChildCount >= 2) and (LastStatement(Parent, Parent.ChildCount - 2) = Node) then
      Keyword := 'Continue';
  end
  else if IsLoop(Parent) and (Parent[Parent.ChildCount - 1] = Node) then
  begin
    Keyword := 'Continue';
    Wrap := True;
  end;
  if Keyword = '' then
    Exit;
  Title := EarlyExitTitle;
  if Keyword = 'Continue' then
    Title := EarlyContinueTitle;
  Guard := 'if ' + TExpressionText.Negate(AText, Node[0]).Text + ' then ' + Keyword + ';';
  Spans := TStatementText.Spans(ATree, [Node[1]]);
  EndPos := TStatementText.ReplacementEnd(ATree, Node, Spans, Suffix);
  if Wrap then
  begin
    // Der Schleifenrumpf wird zum Block: die Ersetzung beginnt hinter do.
    Tokens := ATree.Tokens;
    DoToken := TRoutineBody.PreviousToken(Tokens, TRoutineBody.TokenAt(Tokens, Node.StartOffset));
    if (DoToken < 0) or not SameText(Tokens[DoToken].Text, 'do') then
      Exit;
    StartOffset := Tokens[DoToken].Offset + Length(Tokens[DoToken].Text);
    StartPos := Tokens[DoToken].EndPos;
    Layout := LayoutAt(AText, Parent, ALayout);
    Inner := Layout.Deeper;
    Code := Layout.LineBreak + Layout.Indent + 'begin' + Layout.LineBreak + Inner.Indent + Guard + Layout.LineBreak +
      TStatementText.List(AText, ATree, Statements, Inner.Indent, Layout.LineBreak) + Layout.LineBreak +
      Layout.Indent + 'end' + Suffix;
  end
  else
  begin
    StartOffset := Node.StartOffset;
    StartPos := Node.StartPos;
    Layout := LayoutAt(AText, Node, ALayout);
    Code := Guard + Layout.LineBreak + TStatementText.List(AText, ATree, Statements, Layout.Indent, Layout.LineBreak);
  end;
  if TStatementText.Uncovered(ATree, StartOffset, Node.EndOffset, Spans) then
    Exit;
  ARewrite := TStatementRewrite.Create(Title, TTextEdit.Create(TTextRange.Create(StartPos, EndPos), Code));
  Result := True;
end;

/// <summary>Das einzige innere if ohne else im then-Zweig von AIf (selbst ohne else); nil ohne.</summary>
function SoleInnerIf(AIf: TSyntaxNode): TSyntaxNode;
var
  Statements: TArray<TSyntaxNode>;
begin
  Result := nil;
  if (AIf = nil) or (AIf.Kind <> TSyntaxKind.IfStatement) or HasElse(AIf) or (AIf.ChildCount < 2) then
    Exit;
  Statements := TStatementText.Statements(AIf[1]);
  if (Length(Statements) = 1) and (Statements[0].Kind = TSyntaxKind.IfStatement) and not HasElse(Statements[0]) and
    (Statements[0].ChildCount = 2) then
    Result := Statements[0];
end;

class function TConditions.MergeNested(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  Node, Outer, Inner, Parent: TSyntaxNode;
  Statements: TArray<TSyntaxNode>;
  Spans: TArray<TStatementSpan>;
  Layout: TStatementLayout;
  EndPos: TTextPosition;
  Suffix, Code: string;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  Node := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if Node = nil then
    Exit;
  Outer := nil;
  Inner := SoleInnerIf(Node);
  if Inner <> nil then
    Outer := Node
  else
  begin
    // Auf dem inneren if: das äußere ist der Elternknoten bzw. der um den Block begin … end.
    Parent := Node.Parent;
    if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Block) then
      Parent := Parent.Parent;
    if SoleInnerIf(Parent) = Node then
    begin
      Outer := Parent;
      Inner := Node;
    end;
  end;
  if Outer = nil then
    Exit;
  Statements := TStatementText.Statements(Inner[1]);
  if Statements = nil then
    Exit;
  Spans := TStatementText.Spans(ATree, [Inner[1]]);
  if TStatementText.Uncovered(ATree, Outer.StartOffset, Outer.EndOffset, Spans) then
    Exit;
  Layout := LayoutAt(AText, Outer, ALayout);
  EndPos := TStatementText.ReplacementEnd(ATree, Outer, Spans, Suffix);
  Code := 'if ' + TExpressionText.Combine('and', TExpressionText.Part(AText, Outer[0]),
    TExpressionText.Part(AText, Inner[0])).Text + ' then' +
    TStatementText.Finish(TStatementText.Branch(AText, ATree, Statements, Layout, False), Suffix);
  ARewrite := TStatementRewrite.Create(MergeTitle, TTextEdit.Create(TTextRange.Create(Outer.StartPos, EndPos), Code));
  Result := True;
end;

function Encloses(ANode: TSyntaxNode; const APosition: TTextPosition): Boolean;
begin
  Result := ((ANode.StartPos.Line < APosition.Line) or ((ANode.StartPos.Line = APosition.Line) and
    (ANode.StartPos.Character <= APosition.Character))) and ((APosition.Line < ANode.EndPos.Line) or
    ((APosition.Line = ANode.EndPos.Line) and (APosition.Character <= ANode.EndPos.Character)));
end;

/// <summary>not, dessen Operand sich ohne not schreiben lässt: not X, ein Vergleich oder True/False.</summary>
function IsDoubleNegation(ANode: TSyntaxNode): Boolean;
var
  Operand: TSyntaxNode;
begin
  Result := False;
  if (ANode.Kind <> TSyntaxKind.UnaryExpr) or not SameText(ANode.Name, 'not') or (ANode.ChildCount <> 1) then
    Exit;
  Operand := TExpressionText.Strip(ANode[0]);
  case Operand.Kind of
    TSyntaxKind.UnaryExpr:
      Result := SameText(Operand.Name, 'not');
    TSyntaxKind.BinaryExpr:
      Result := TExpressionText.InvertedComparison(Operand.Name) <> '';
  else
    Result := TExpressionText.IsBooleanLiteral(Operand);
  end;
end;

class function TConditions.RemoveDoubleNegation(const AText: string; ATree: TSyntaxTree;
  const APosition: TTextPosition; out ARewrite: TStatementRewrite): Boolean;
var
  Found: TSyntaxNode;
  Position: TTextPosition;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  Position := APosition;
  // Das äußerste passende not: Search findet den Elternknoten vor seinen Kindern.
  Found := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not Encloses(ANode, Position) then
        Exit(TSyntaxSearchStep.Skip);
      Result := TSyntaxSearchStep.Descend;
      if IsDoubleNegation(ANode) then
        Result := TSyntaxSearchStep.Found;
    end);
  if (Found = nil) or TStatementText.HasComment(ATree, Found.StartOffset, Found.EndOffset) then
    Exit;
  ARewrite := TStatementRewrite.Create(DoubleNegationTitle, TTextEdit.Create(TTextRange.Create(Found.StartPos,
    Found.EndPos), TExpressionText.Simplify(AText, Found).AtLeast(TExpressionText.ContextPrecedence(Found))));
  Result := True;
end;

class function TConditions.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALayout: TStatementLayout): TArray<TStatementRewrite>;
var
  Rewrite: TStatementRewrite;
begin
  Result := nil;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit;
  if Invert(AText, ATree, APosition, ALayout, Rewrite) then
    Result := Result + [Rewrite];
  if EarlyExit(AText, ATree, APosition, ALayout, Rewrite) then
    Result := Result + [Rewrite];
  if MergeNested(AText, ATree, APosition, ALayout, Rewrite) then
    Result := Result + [Rewrite];
  if RemoveDoubleNegation(AText, ATree, APosition, Rewrite) then
    Result := Result + [Rewrite];
end;

end.
