unit Atlas.Common.Editing.ExpressionText;

// Ausdrücke aus dem Syntaxbaum als Text für Umformungen (Kette L: #646, #656,
// #684): Vorrang nach Delphi, Klammern nur, wo der Vorrang sie verlangt,
// lesbares Verneinen und Vergleich zweier Ausdrücke unabhängig von Leerraum,
// Kommentaren, Groß-/Kleinschreibung und äußeren Klammern.
//   Vorrang (höher bindet stärker):
//     5 Operand (Name, Literal, Aufruf, Klammer, Menge)
//     4 not, @, Vorzeichen
//     3 * / div mod and shl shr as
//     2 + - or xor
//     1 = <> < > <= >= in is
//     0 bedingter Ausdruck if … then … else …
//   Verneinen: Vergleiche drehen (= ↔ <>, < ↔ >=, > ↔ <=), and/or nach De
//   Morgan, not X wird X, True ↔ False, in und is werden not (…). Die
//   Reihenfolge der Operanden bleibt, damit die Kurzschlussauswertung gleich
//   bleibt. Ohne Typprüfung: and/or gelten nur dort als boolesch, wo der
//   Aufrufer einen booleschen Ausdruck übergibt (Bedingung von if/while).

interface

uses
  Atlas.Common.Pascal.SyntaxTree;

const
  PrecedenceIfExpr = 0;
  PrecedenceRelational = 1;
  PrecedenceAdditive = 2;
  PrecedenceMultiplicative = 3;
  PrecedenceUnary = 4;
  PrecedenceOperand = 5;

type
  /// <summary>Text eines Ausdrucks mit dem Vorrang seines äußersten Operators.</summary>
  TExpressionPart = record
    Text: string;
    Precedence: Integer;
    class function Create(const AText: string; APrecedence: Integer): TExpressionPart; static;
    /// <summary>Text mit Klammern, wenn der Vorrang unter AMinimum liegt.</summary>
    function AtLeast(AMinimum: Integer): string;
  end;

  TExpressionText = record
  public
    /// <summary>ANode ohne umschließende Klammern.</summary>
    class function Strip(ANode: TSyntaxNode): TSyntaxNode; static;
    /// <summary>Vorrang des äußersten Operators von ANode (Klammern zählen als Operand).</summary>
    class function Precedence(ANode: TSyntaxNode): Integer; static;
    /// <summary>Vorrang eines binären Operators; -1 bei unbekanntem.</summary>
    class function OperatorPrecedence(const AOperator: string): Integer; static;
    /// <summary>Quelltext von ANode, unverändert.</summary>
    class function Source(const AText: string; ANode: TSyntaxNode): string; static;
    /// <summary>Quelltext von ANode als Teil mit seinem Vorrang.</summary>
    class function Part(const AText: string; ANode: TSyntaxNode): TExpressionPart; static;
    /// <summary>ALeft AOperator ARight mit Klammern nach Vorrang (linksassoziativ).</summary>
    class function Combine(const AOperator: string; const ALeft, ARight: TExpressionPart): TExpressionPart; static;
    /// <summary>ANode ohne doppelte Verneinung: not X wird zur lesbaren Verneinung von X (not not A → A,
    /// not (A &lt;&gt; B) → A = B); sonst der Ausdruck unverändert.</summary>
    class function Simplify(const AText: string; ANode: TSyntaxNode): TExpressionPart; static;
    /// <summary>Lesbare Verneinung des booleschen Ausdrucks ANode.</summary>
    class function Negate(const AText: string; ANode: TSyntaxNode): TExpressionPart; static;
    /// <summary>Gegenoperator eines Vergleichs (= ↔ &lt;&gt; …); '' bei anderen Operatoren.</summary>
    class function InvertedComparison(const AOperator: string): string; static;
    /// <summary>Vergleich mit vertauschten Seiten (&lt; ↔ &gt; …); '' bei anderen Operatoren.</summary>
    class function MirroredComparison(const AOperator: string): string; static;
    /// <summary>Gleicher Ausdruck ohne Rücksicht auf Leerraum, Kommentare, Groß-/Kleinschreibung der Namen
    /// und äußere Klammern.</summary>
    class function Same(ATree: TSyntaxTree; A, B: TSyntaxNode): Boolean; static;
    /// <summary>Token von ANode ohne Kommentare, Namen in Kleinbuchstaben, durch Leerzeichen getrennt.</summary>
    class function Normalized(ATree: TSyntaxTree; ANode: TSyntaxNode): string; static;
    /// <summary>Ohne Seiteneffekte: Namen, Literale, Mitglieder, Indizes, Operatoren und Aufrufe von
    /// Standardroutinen ohne Seiteneffekte (Pascal.PureRoutines). Ein Name kann eine parameterlose Funktion
    /// sein; das prüft der Aufrufer bei Bedarf über die Namensauflösung.</summary>
    class function IsSideEffectFree(ANode: TSyntaxNode): Boolean; static;
    /// <summary>True oder False als Name bzw. Literal.</summary>
    class function IsBooleanLiteral(ANode: TSyntaxNode): Boolean; static;
    /// <summary>Mindestvorrang, den ein Ersatz für ANode an seiner Stelle braucht, damit er ohne Klammern
    /// dasselbe bedeutet (siehe TExpressionPart.AtLeast): Operand eines Operators, Empfänger eines Aufrufs,
    /// Indexzugriffs oder Mitglieds, Bedingung oder Wert vor else eines Bedingungsausdrucks; sonst (Bedingung einer
    /// Anweisung, Argument, Klammer, Wert nach else) PrecedenceIfExpr.</summary>
    class function ContextPrecedence(ANode: TSyntaxNode): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Editing.RoutineBody;

{ TExpressionPart }

class function TExpressionPart.Create(const AText: string; APrecedence: Integer): TExpressionPart;
begin
  Result.Text := AText;
  Result.Precedence := APrecedence;
end;

function TExpressionPart.AtLeast(AMinimum: Integer): string;
begin
  if Precedence < AMinimum then
    Result := '(' + Text + ')'
  else
    Result := Text;
end;

{ TExpressionText }

class function TExpressionText.Strip(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    Result := Result[0];
end;

class function TExpressionText.OperatorPrecedence(const AOperator: string): Integer;
var
  Op: string;
begin
  Op := LowerCase(AOperator);
  if MatchStr(Op, ['=', '<>', '<', '>', '<=', '>=', 'in', 'is', 'is not', 'not in']) then
    Result := PrecedenceRelational
  else if MatchStr(Op, ['+', '-', 'or', 'xor']) then
    Result := PrecedenceAdditive
  else if MatchStr(Op, ['*', '/', 'div', 'mod', 'and', 'shl', 'shr', 'as']) then
    Result := PrecedenceMultiplicative
  else
    Result := -1;
end;

class function TExpressionText.Precedence(ANode: TSyntaxNode): Integer;
begin
  case ANode.Kind of
    TSyntaxKind.BinaryExpr:
    begin
      Result := OperatorPrecedence(ANode.Name);
      if Result < 0 then
        Result := PrecedenceRelational;
    end;
    TSyntaxKind.UnaryExpr, TSyntaxKind.AddressOf:
      Result := PrecedenceUnary;
    TSyntaxKind.IfExpr:
      Result := PrecedenceIfExpr;
  else
    Result := PrecedenceOperand;
  end;
end;

class function TExpressionText.Source(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := TRoutineBody.TextOf(AText, ANode);
end;

class function TExpressionText.Part(const AText: string; ANode: TSyntaxNode): TExpressionPart;
begin
  Result := TExpressionPart.Create(Source(AText, ANode), Precedence(ANode));
end;

class function TExpressionText.Combine(const AOperator: string; const ALeft, ARight: TExpressionPart): TExpressionPart;
var
  Level: Integer;
begin
  Level := OperatorPrecedence(AOperator);
  // Linksassoziativ: links reicht derselbe Vorrang, rechts braucht es einen höheren. Vergleiche lassen sich
  // in Delphi nicht verketten (A = B = C ist A = (B = C) nicht), deshalb dort beidseitig höher.
  if Level = PrecedenceRelational then
    Result := TExpressionPart.Create(ALeft.AtLeast(Level + 1) + ' ' + AOperator + ' ' + ARight.AtLeast(Level + 1),
      Level)
  else
    Result := TExpressionPart.Create(ALeft.AtLeast(Level) + ' ' + AOperator + ' ' + ARight.AtLeast(Level + 1), Level);
end;

class function TExpressionText.InvertedComparison(const AOperator: string): string;
begin
  case IndexStr(AOperator, ['=', '<>', '<', '>=', '>', '<=']) of
    0: Result := '<>';
    1: Result := '=';
    2: Result := '>=';
    3: Result := '<';
    4: Result := '<=';
    5: Result := '>';
  else
    Result := '';
  end;
end;

class function TExpressionText.MirroredComparison(const AOperator: string): string;
begin
  case IndexStr(AOperator, ['=', '<>', '<', '>', '<=', '>=']) of
    0: Result := '=';
    1: Result := '<>';
    2: Result := '>';
    3: Result := '<';
    4: Result := '>=';
    5: Result := '<=';
  else
    Result := '';
  end;
end;

class function TExpressionText.IsBooleanLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
    (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False'));
end;

class function TExpressionText.ContextPrecedence(ANode: TSyntaxNode): Integer;
var
  Parent: TSyntaxNode;
  Level: Integer;
begin
  Result := PrecedenceIfExpr;
  Parent := ANode.Parent;
  if Parent = nil then
    Exit;
  case Parent.Kind of
    TSyntaxKind.BinaryExpr:
      if Parent.ChildCount = 2 then
      begin
        // Wie Combine: links derselbe Vorrang, rechts und bei Vergleichen beidseitig ein höherer.
        Level := OperatorPrecedence(Parent.Name);
        if Level < 0 then
          Level := PrecedenceRelational;
        if (Parent[1] = ANode) or (Level = PrecedenceRelational) then
          Result := Level + 1
        else
          Result := Level;
      end;
    TSyntaxKind.UnaryExpr:
      Result := PrecedenceUnary;
    TSyntaxKind.AddressOf, TSyntaxKind.Call, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess:
      if Parent[0] = ANode then
        Result := PrecedenceOperand;
    // Bedingung und Wert vor else eines Bedingungsausdrucks: ein innerer Bedingungsausdruck in Klammern
    // (sonst gehörte das else zum inneren).
    TSyntaxKind.IfExpr:
      if (Parent.ChildCount = 3) and (Parent[2] <> ANode) then
        Result := PrecedenceIfExpr + 1;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

class function TExpressionText.Negate(const AText: string; ANode: TSyntaxNode): TExpressionPart;
var
  Node: TSyntaxNode;
  Op, Inverted: string;
begin
  Node := Strip(ANode);
  case Node.Kind of
    TSyntaxKind.UnaryExpr:
      if SameText(Node.Name, 'not') and (Node.ChildCount = 1) then
      begin
        // not X → X (ohne doppelte Verneinung); Klammern um X fallen weg, der Aufrufer setzt sie nach Vorrang
        // neu.
        Result := Simplify(AText, Node[0]);
        Exit;
      end;
    TSyntaxKind.BinaryExpr:
      if Node.ChildCount = 2 then
      begin
        Op := LowerCase(Node.Name);
        Inverted := InvertedComparison(Op);
        if Inverted <> '' then
        begin
          Result := Combine(Inverted, Part(AText, Node[0]), Part(AText, Node[1]));
          Exit;
        end;
        // De Morgan: not (A and B) = not A or not B; die Reihenfolge bleibt (Kurzschluss).
        if Op = 'and' then
        begin
          Result := Combine('or', Negate(AText, Node[0]), Negate(AText, Node[1]));
          Exit;
        end;
        if Op = 'or' then
        begin
          Result := Combine('and', Negate(AText, Node[0]), Negate(AText, Node[1]));
          Exit;
        end;
      end;
    TSyntaxKind.Identifier, TSyntaxKind.Literal:
      if IsBooleanLiteral(Node) then
      begin
        if SameText(Node.Name, 'True') then
          Result := TExpressionPart.Create('False', PrecedenceOperand)
        else
          Result := TExpressionPart.Create('True', PrecedenceOperand);
        Exit;
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
  // Alles andere (Name, Aufruf, in, is, xor, bedingter Ausdruck): not vor den Operanden.
  Result := TExpressionPart.Create('not ' + Part(AText, Node).AtLeast(PrecedenceUnary), PrecedenceUnary);
end;

class function TExpressionText.Simplify(const AText: string; ANode: TSyntaxNode): TExpressionPart;
var
  Node: TSyntaxNode;
begin
  Node := Strip(ANode);
  if (Node.Kind = TSyntaxKind.UnaryExpr) and SameText(Node.Name, 'not') and (Node.ChildCount = 1) then
    Result := Negate(AText, Node[0])
  else
    Result := Part(AText, Node);
end;

class function TExpressionText.Normalized(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
var
  Node: TSyntaxNode;
  Tokens: TArray<TPascalToken>;
  Index: Integer;
  Word: string;
begin
  Node := Strip(ANode);
  Tokens := ATree.Tokens;
  Result := '';
  Index := TRoutineBody.TokenAt(Tokens, Node.StartOffset);
  while (Index <= High(Tokens)) and (Tokens[Index].Offset < Node.EndOffset) do
  begin
    if not (Tokens[Index].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      Word := Tokens[Index].Text;
      if Tokens[Index].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
        Word := LowerCase(Word);
      if Result <> '' then
        Result := Result + ' ';
      Result := Result + Word;
    end;
    Inc(Index);
  end;
end;

class function TExpressionText.Same(ATree: TSyntaxTree; A, B: TSyntaxNode): Boolean;
begin
  Result := (A <> nil) and (B <> nil) and (Normalized(ATree, A) = Normalized(ATree, B));
end;

class function TExpressionText.IsSideEffectFree(ANode: TSyntaxNode): Boolean;
begin
  // Search statt Rekursion (Bericht M1).
  Result := ANode.Search(
    function(ACandidate: TSyntaxNode): TSyntaxSearchStep
    var
      Callee: TSyntaxNode;
    begin
      Result := TSyntaxSearchStep.Descend;
      case ACandidate.Kind of
        TSyntaxKind.Call:
        begin
          Callee := nil;
          if ACandidate.ChildCount > 0 then
            Callee := ACandidate[0];
          if (Callee = nil) or (Callee.Kind <> TSyntaxKind.Identifier) or not TPureRoutines.IsPure(Callee.Name) then
            Result := TSyntaxSearchStep.Found;
        end;
        TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr, TSyntaxKind.Error:
          Result := TSyntaxSearchStep.Found;
      else
        // Übrige Arten: nichts zu tun.
      end;
    end) = nil;
end;

end.
