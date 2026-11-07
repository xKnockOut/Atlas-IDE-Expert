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
  cPrecedenceIfExpr = 0;
  cPrecedenceRelational = 1;
  cPrecedenceAdditive = 2;
  cPrecedenceMultiplicative = 3;
  cPrecedenceUnary = 4;
  cPrecedenceOperand = 5;

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
  begin
    Result := '(' + Text + ')';
  end
  else
  begin
    Result := Text;
  end;
end;

{ TExpressionText }

class function TExpressionText.Strip(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

class function TExpressionText.OperatorPrecedence(const AOperator: string): Integer;
var
  mOp: string;
begin
  mOp := LowerCase(AOperator);
  if MatchStr(mOp, ['=', '<>', '<', '>', '<=', '>=', 'in', 'is', 'is not', 'not in']) then
  begin
    Result := cPrecedenceRelational;
  end
  else if MatchStr(mOp, ['+', '-', 'or', 'xor']) then
  begin
    Result := cPrecedenceAdditive;
  end
  else if MatchStr(mOp, ['*', '/', 'div', 'mod', 'and', 'shl', 'shr', 'as']) then
  begin
    Result := cPrecedenceMultiplicative;
  end
  else
  begin
    Result := -1;
  end;
end;

class function TExpressionText.Precedence(ANode: TSyntaxNode): Integer;
begin
  case ANode.Kind of
    TSyntaxKind.BinaryExpr:
    begin
      Result := OperatorPrecedence(ANode.Name);
      if Result < 0 then
      begin
        Result := cPrecedenceRelational;
      end;
    end;
    TSyntaxKind.UnaryExpr, TSyntaxKind.AddressOf:
      Result := cPrecedenceUnary;
    TSyntaxKind.IfExpr:
      Result := cPrecedenceIfExpr;
  else
    Result := cPrecedenceOperand;
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
  mLevel: Integer;
begin
  mLevel := OperatorPrecedence(AOperator);
  // Linksassoziativ: links reicht derselbe Vorrang, rechts braucht es einen höheren. Vergleiche lassen sich
  // in Delphi nicht verketten (A = B = C ist A = (B = C) nicht), deshalb dort beidseitig höher.
  if mLevel = cPrecedenceRelational then
  begin
    Result := TExpressionPart.Create(ALeft.AtLeast(mLevel + 1) + ' ' + AOperator + ' ' + ARight.AtLeast(mLevel + 1),
      mLevel);
  end
  else
  begin
    Result := TExpressionPart.Create(ALeft.AtLeast(mLevel) + ' ' + AOperator + ' ' + ARight.AtLeast(mLevel + 1), mLevel);
  end;
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

class function TExpressionText.IsBooleanLiteral(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.Literal]) and
    (SameText(ANode.Name, 'True') or SameText(ANode.Name, 'False'));
end;

/// <summary>Vorrang, den ANode als Operand des binären Ausdrucks AParent braucht. Wie Combine: links derselbe
/// Vorrang, rechts und bei Vergleichen beidseitig ein höherer.</summary>
function BinaryContextPrecedence(AParent, ANode: TSyntaxNode): Integer;
begin
  Result := TExpressionText.OperatorPrecedence(AParent.Name);
  if Result < 0 then
  begin
    Result := cPrecedenceRelational;
  end;
  if (AParent[1] = ANode) or (Result = cPrecedenceRelational) then
  begin
    Inc(Result);
  end;
end;

class function TExpressionText.ContextPrecedence(ANode: TSyntaxNode): Integer;
var
  mParent: TSyntaxNode;
begin
  Result := cPrecedenceIfExpr;
  mParent := ANode.Parent;
  if mParent = nil then
  begin
    Exit;
  end;
  case mParent.Kind of
    TSyntaxKind.BinaryExpr:
      if mParent.ChildCount = 2 then
      begin
        Result := BinaryContextPrecedence(mParent, ANode);
      end;
    TSyntaxKind.UnaryExpr:
      Result := cPrecedenceUnary;
    TSyntaxKind.AddressOf, TSyntaxKind.Call, TSyntaxKind.IndexAccess, TSyntaxKind.MemberAccess:
      if mParent[0] = ANode then
      begin
        Result := cPrecedenceOperand;
      end;
    // Bedingung und Wert vor else eines Bedingungsausdrucks: ein innerer Bedingungsausdruck in Klammern
    // (sonst gehörte das else zum inneren).
    TSyntaxKind.IfExpr:
      if (mParent.ChildCount = 3) and (mParent[2] <> ANode) then
      begin
        Result := cPrecedenceIfExpr + 1;
      end;
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>Verneinung eines binären Ausdrucks: Vergleich umkehren, and/or nach De Morgan (die Reihenfolge
/// bleibt wegen des Kurzschlusses). False bei anderen Operatoren.</summary>
function NegateBinary(const AText: string; ANode: TSyntaxNode; out APart: TExpressionPart): Boolean;
var
  mOperator, mInverted: string;
begin
  Result := ANode.ChildCount = 2;
  if not Result then
  begin
    Exit;
  end;
  mOperator := LowerCase(ANode.Name);
  mInverted := TExpressionText.InvertedComparison(mOperator);
  if mInverted <> '' then
  begin
    APart := TExpressionText.Combine(mInverted, TExpressionText.Part(AText, ANode[0]),
      TExpressionText.Part(AText, ANode[1]));
  end
  else if (mOperator = 'and') or (mOperator = 'or') then
  begin
    mInverted := 'and';
    if mOperator = 'and' then
    begin
      mInverted := 'or';
    end;
    APart := TExpressionText.Combine(mInverted, TExpressionText.Negate(AText, ANode[0]),
      TExpressionText.Negate(AText, ANode[1]));
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Verneinung ohne Sonderfall: Ergebnis von not X, True/False getauscht oder X ohne doppelte
/// Verneinung; False, wenn nichts davon passt.</summary>
function NegateSimple(const AText: string; ANode: TSyntaxNode; out APart: TExpressionPart): Boolean;
begin
  Result := True;
  if (ANode.Kind = TSyntaxKind.UnaryExpr) and SameText(ANode.Name, 'not') and (ANode.ChildCount = 1) then
  begin
    // not X → X; Klammern um X fallen weg, der Aufrufer setzt sie nach Vorrang neu.
    APart := TExpressionText.Simplify(AText, ANode[0]);
  end
  else if TExpressionText.IsBooleanLiteral(ANode) and SameText(ANode.Name, 'True') then
  begin
    APart := TExpressionPart.Create('False', cPrecedenceOperand);
  end
  else if TExpressionText.IsBooleanLiteral(ANode) then
  begin
    APart := TExpressionPart.Create('True', cPrecedenceOperand);
  end
  else
  begin
    Result := False;
  end;
end;

class function TExpressionText.Negate(const AText: string; ANode: TSyntaxNode): TExpressionPart;
var
  mNode: TSyntaxNode;
  mDone: Boolean;
begin
  mNode := Strip(ANode);
  if mNode.Kind = TSyntaxKind.BinaryExpr then
  begin
    mDone := NegateBinary(AText, mNode, Result);
  end
  else
  begin
    mDone := NegateSimple(AText, mNode, Result);
  end;
  if not mDone then
  begin
    // Alles andere (Name, Aufruf, in, is, xor, bedingter Ausdruck): not vor den Operanden.
    Result := TExpressionPart.Create('not ' + Part(AText, mNode).AtLeast(cPrecedenceUnary), cPrecedenceUnary);
  end;
end;

class function TExpressionText.Simplify(const AText: string; ANode: TSyntaxNode): TExpressionPart;
var
  mNode: TSyntaxNode;
begin
  mNode := Strip(ANode);
  if (mNode.Kind = TSyntaxKind.UnaryExpr) and SameText(mNode.Name, 'not') and (mNode.ChildCount = 1) then
  begin
    Result := Negate(AText, mNode[0]);
  end
  else
  begin
    Result := Part(AText, mNode);
  end;
end;

class function TExpressionText.Normalized(ATree: TSyntaxTree; ANode: TSyntaxNode): string;
var
  mNode: TSyntaxNode;
  mTokens: TArray<TPascalToken>;
  mIndex: Integer;
  mWord: string;
begin
  mNode := Strip(ANode);
  mTokens := ATree.Tokens;
  Result := '';
  mIndex := TRoutineBody.TokenAt(mTokens, mNode.StartOffset);
  while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mNode.EndOffset) do
  begin
    if not (mTokens[mIndex].Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
    begin
      mWord := mTokens[mIndex].Text;
      if mTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
      begin
        mWord := LowerCase(mWord);
      end;
      if Result <> '' then
      begin
        Result := Result + ' ';
      end;
      Result := Result + mWord;
    end;
    Inc(mIndex);
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
          begin
            Callee := ACandidate[0];
          end;
          if (Callee = nil) or (Callee.Kind <> TSyntaxKind.Identifier) or not TPureRoutines.IsPure(Callee.Name) then
          begin
            Result := TSyntaxSearchStep.Found;
          end;
        end;
        TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr, TSyntaxKind.Error:
          Result := TSyntaxSearchStep.Found;
      else
        // Übrige Arten: nichts zu tun.
      end;
    end) = nil;
end;

end.
