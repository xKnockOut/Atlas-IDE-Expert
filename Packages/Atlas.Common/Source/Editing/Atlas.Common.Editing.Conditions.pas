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
  begin
    if TRoutineBody.IsStatement(ANode[Index]) and (ANode[Index].Kind <> TSyntaxKind.EmptyStatement) then
    begin
      Exit(ANode[Index]);
    end;
  end;
end;

function HasInlineDeclaration(const AStatements: TArray<TSyntaxNode>): Boolean;
var
  Statement: TSyntaxNode;
begin
  for Statement in AStatements do
  begin
    if Statement.Kind in [TSyntaxKind.InlineVar, TSyntaxKind.InlineConst] then
    begin
      Exit(True);
    end;
  end;
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
  begin
    Exit;
  end;
  EmptyThen := TStatementText.Statements(Node[1]) = nil;
  // Ohne else stünde das neue if vor dem else eines äußeren if und bekäme es (if Q then if A then else B else Z).
  Parent := Node.Parent;
  if EmptyThen and (Parent <> nil) and (Parent.Kind = TSyntaxKind.IfStatement) and HasElse(Parent) and
    (Parent[1] = Node) then
  begin
    Exit;
  end;
  Spans := TStatementText.Spans(ATree, [Node[1], Node[2]]);
  if TStatementText.Uncovered(ATree, Node.StartOffset, Node.EndOffset, Spans) then
  begin
    Exit;
  end;
  Layout := LayoutAt(AText, Node, ALayout);
  EndPos := TStatementText.ReplacementEnd(ATree, Node, Spans, Suffix);
  Code := 'if ' + TExpressionText.Negate(AText, Node[0]).Text + ' then';
  if EmptyThen then
  begin
    Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[2], Layout, False), Suffix);
  end
  else
  begin
    Code := Code + TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[2], Layout, True), '') +
      Layout.LineBreak + Layout.Indent + 'else' +
      TStatementText.Finish(TStatementText.GuardedBranch(AText, ATree, Node[1], Layout, False), Suffix);
  end;
  ARewrite := TStatementRewrite.Create(InvertTitle, TTextEdit.Create(TTextRange.Create(Node.StartPos, EndPos), Code));
  Result := True;
end;

/// <summary>if ohne else mit Anweisungen im then-Zweig und ohne Inline-Variablen darin.</summary>
function CanExitEarly(ANode: TSyntaxNode): Boolean;
var
  mStatements: TArray<TSyntaxNode>;
begin
  Result := (ANode <> nil) and not HasElse(ANode);
  if Result then
  begin
    mStatements := TStatementText.Statements(ANode[1]);
    Result := (mStatements <> nil) and not HasInlineDeclaration(mStatements);
  end;
end;

/// <summary>Ausstieg für das if ANode als letzte Anweisung des Blocks ABlock: Exit im Rumpf einer Routine,
/// Continue im Rumpf einer Schleife; '' sonst.</summary>
function BlockExitKeyword(ANode, ABlock: TSyntaxNode): string;
var
  mSiblings: TArray<TSyntaxNode>;
  mOwner: TSyntaxNode;
begin
  Result := '';
  mSiblings := TStatementText.Statements(ABlock);
  if (mSiblings = nil) or (mSiblings[High(mSiblings)] <> ANode) then
  begin
    Exit;
  end;
  mOwner := ABlock.Parent;
  if (mOwner <> nil) and (mOwner.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) then
  begin
    Result := 'Exit';
  end
  else if IsLoop(mOwner) and (mOwner[mOwner.ChildCount - 1] = ABlock) then
  begin
    Result := 'Continue';
  end;
end;

/// <summary>Wo steht das if? Als letzte Anweisung des Rumpfs einer Routine, eines Schleifenrumpfs (begin … end
/// oder repeat … until) oder direkt als Rumpf einer Schleife (AWrap). Liefert Exit, Continue oder ''.</summary>
function ExitKeyword(ANode: TSyntaxNode; out AWrap: Boolean): string;
var
  mParent: TSyntaxNode;
begin
  AWrap := False;
  Result := '';
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  if mParent.Kind = TSyntaxKind.Block then
  begin
    Result := BlockExitKeyword(ANode, mParent);
  end
  else if mParent.Kind = TSyntaxKind.RepeatStatement then
  begin
    if (mParent.ChildCount >= 2) and (LastStatement(mParent, mParent.ChildCount - 2) = ANode) then
    begin
      Result := 'Continue';
    end;
  end
  else if IsLoop(mParent) and (mParent[mParent.ChildCount - 1] = ANode) then
  begin
    Result := 'Continue';
    AWrap := True;
  end;
end;

type
  /// <summary>Ersetzung für „Frühen Ausstieg einführen“: Wächter und Rest des Endes als Eingabe, Anfang und Text
  /// als Ergebnis.</summary>
  TEarlyExitCode = record
    /// <summary>"if not … then Exit;"</summary>
    Guard: string;
    /// <summary>Was hinter dem if bleibt (Semikolon), aus TStatementText.ReplacementEnd.</summary>
    Suffix: string;
    StartOffset: Integer;
    StartPos: TTextPosition;
    Code: string;
    function Wrapped(const AText: string; ATree: TSyntaxTree; ANode: TSyntaxNode;
      const ALayout: TStatementLayout): Boolean;
    procedure Plain(const AText: string; ATree: TSyntaxTree; ANode: TSyntaxNode; const ALayout: TStatementLayout);
  end;

/// <summary>Der Schleifenrumpf wird zum Block: die Ersetzung beginnt hinter do. False ohne do davor.</summary>
function TEarlyExitCode.Wrapped(const AText: string; ATree: TSyntaxTree; ANode: TSyntaxNode;
  const ALayout: TStatementLayout): Boolean;
var
  mTokens: TArray<TPascalToken>;
  mDoToken: Integer;
  mLayout, mInner: TStatementLayout;
  mLB: string;
begin
  mTokens := ATree.Tokens;
  mDoToken := TRoutineBody.PreviousToken(mTokens, TRoutineBody.TokenAt(mTokens, ANode.StartOffset));
  Result := (mDoToken >= 0) and SameText(mTokens[mDoToken].Text, 'do');
  if not Result then
  begin
    Exit;
  end;
  StartOffset := mTokens[mDoToken].Offset + Length(mTokens[mDoToken].Text);
  StartPos := mTokens[mDoToken].EndPos;
  mLayout := LayoutAt(AText, ANode.Parent, ALayout);
  mInner := mLayout.Deeper;
  mLB := mLayout.LineBreak;
  Code := mLB + mLayout.Indent + 'begin' + mLB + mInner.Indent + Guard + mLB +
    TStatementText.List(AText, ATree, TStatementText.Statements(ANode[1]), mInner.Indent, mLB) + mLB +
    mLayout.Indent + 'end' + Suffix;
end;

procedure TEarlyExitCode.Plain(const AText: string; ATree: TSyntaxTree; ANode: TSyntaxNode;
  const ALayout: TStatementLayout);
var
  mLayout: TStatementLayout;
begin
  StartOffset := ANode.StartOffset;
  StartPos := ANode.StartPos;
  mLayout := LayoutAt(AText, ANode, ALayout);
  Code := Guard + mLayout.LineBreak + TStatementText.List(AText, ATree, TStatementText.Statements(ANode[1]),
    mLayout.Indent, mLayout.LineBreak);
end;

class function TConditions.EarlyExit(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALayout: TStatementLayout; out ARewrite: TStatementRewrite): Boolean;
var
  mNode: TSyntaxNode;
  mKeyword, mTitle: string;
  mWrap: Boolean;
  mSpans: TArray<TStatementSpan>;
  mEndPos: TTextPosition;
  mCode: TEarlyExitCode;
begin
  Result := False;
  ARewrite := Default(TStatementRewrite);
  mNode := TStatementText.HeadAt(ATree, APosition, TSyntaxKind.IfStatement);
  if not CanExitEarly(mNode) then
  begin
    Exit;
  end;
  mKeyword := ExitKeyword(mNode, mWrap);
  if mKeyword = '' then
  begin
    Exit;
  end;
  mCode := Default(TEarlyExitCode);
  mCode.Guard := 'if ' + TExpressionText.Negate(AText, mNode[0]).Text + ' then ' + mKeyword + ';';
  mSpans := TStatementText.Spans(ATree, [mNode[1]]);
  mEndPos := TStatementText.ReplacementEnd(ATree, mNode, mSpans, mCode.Suffix);
  Result := True;
  if mWrap then
  begin
    Result := mCode.Wrapped(AText, ATree, mNode, ALayout);
  end
  else
  begin
    mCode.Plain(AText, ATree, mNode, ALayout);
  end;
  Result := Result and not TStatementText.Uncovered(ATree, mCode.StartOffset, mNode.EndOffset, mSpans);
  if Result then
  begin
    mTitle := EarlyExitTitle;
    if mKeyword = 'Continue' then
    begin
      mTitle := EarlyContinueTitle;
    end;
    ARewrite := TStatementRewrite.Create(mTitle, TTextEdit.Create(TTextRange.Create(mCode.StartPos, mEndPos),
      mCode.Code));
  end;
end;

/// <summary>Das einzige innere if ohne else im then-Zweig von AIf (selbst ohne else); nil ohne.</summary>
function SoleInnerIf(AIf: TSyntaxNode): TSyntaxNode;
var
  Statements: TArray<TSyntaxNode>;
begin
  Result := nil;
  if (AIf = nil) or (AIf.Kind <> TSyntaxKind.IfStatement) or HasElse(AIf) or (AIf.ChildCount < 2) then
  begin
    Exit;
  end;
  Statements := TStatementText.Statements(AIf[1]);
  if (Length(Statements) = 1) and (Statements[0].Kind = TSyntaxKind.IfStatement) and not HasElse(Statements[0]) and
    (Statements[0].ChildCount = 2) then
  begin
    Result := Statements[0];
  end;
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
  begin
    Exit;
  end;
  Outer := nil;
  Inner := SoleInnerIf(Node);
  if Inner <> nil then
  begin
    Outer := Node;
  end
  else
  begin
    // Auf dem inneren if: das äußere ist der Elternknoten bzw. der um den Block begin … end.
    Parent := Node.Parent;
    if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Block) then
    begin
      Parent := Parent.Parent;
    end;
    if SoleInnerIf(Parent) = Node then
    begin
      Outer := Parent;
      Inner := Node;
    end;
  end;
  if Outer = nil then
  begin
    Exit;
  end;
  Statements := TStatementText.Statements(Inner[1]);
  if Statements = nil then
  begin
    Exit;
  end;
  Spans := TStatementText.Spans(ATree, [Inner[1]]);
  if TStatementText.Uncovered(ATree, Outer.StartOffset, Outer.EndOffset, Spans) then
  begin
    Exit;
  end;
  Layout := LayoutAt(AText, Outer, ALayout);
  EndPos := TStatementText.ReplacementEnd(ATree, Outer, Spans, Suffix);
  Code := 'if ' + TExpressionText.Combine('and', TExpressionText.Part(AText, Outer[0]),
    TExpressionText.Part(AText, Inner[0])).Text + ' then' +
    TStatementText.Finish(TStatementText.Branch(AText, ATree, Statements, Layout, False), Suffix);
  ARewrite := TStatementRewrite.Create(MergeTitle, TTextEdit.Create(TTextRange.Create(Outer.StartPos, EndPos), Code));
  Result := True;
end;

/// <summary>not, dessen Operand sich ohne not schreiben lässt: not X, ein Vergleich oder True/False.</summary>
function IsDoubleNegation(ANode: TSyntaxNode): Boolean;
var
  Operand: TSyntaxNode;
begin
  Result := False;
  if (ANode.Kind <> TSyntaxKind.UnaryExpr) or not SameText(ANode.Name, 'not') or (ANode.ChildCount <> 1) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  Position := APosition;
  // Das äußerste passende not: Search findet den Elternknoten vor seinen Kindern.
  Found := ATree.Root.Search(
    function(ANode: TSyntaxNode): TSyntaxSearchStep
    begin
      if not TStatementText.Encloses(ANode, Position) then
      begin
        Exit(TSyntaxSearchStep.Skip);
      end;
      Result := TSyntaxSearchStep.Descend;
      if IsDoubleNegation(ANode) then
      begin
        Result := TSyntaxSearchStep.Found;
      end;
    end);
  if (Found = nil) or TStatementText.HasComment(ATree, Found.StartOffset, Found.EndOffset) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  if Invert(AText, ATree, APosition, ALayout, Rewrite) then
  begin
    Result := Result + [Rewrite];
  end;
  if EarlyExit(AText, ATree, APosition, ALayout, Rewrite) then
  begin
    Result := Result + [Rewrite];
  end;
  if MergeNested(AText, ATree, APosition, ALayout, Rewrite) then
  begin
    Result := Result + [Rewrite];
  end;
  if RemoveDoubleNegation(AText, ATree, APosition, Rewrite) then
  begin
    Result := Result + [Rewrite];
  end;
end;

end.
