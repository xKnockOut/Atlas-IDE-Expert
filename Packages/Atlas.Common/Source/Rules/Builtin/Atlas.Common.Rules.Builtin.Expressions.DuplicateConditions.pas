unit Atlas.Common.Rules.Builtin.Expressions.DuplicateConditions;

// duplicate-condition (#928): dieselbe Bedingung zweimal in einer if-else-if-Kette, gleiche then- und else-Zweige,
// A and A bzw. A or A, X = X. Verglichen wird der Quelltext ohne Leerraum, Kommentare und Groß-/Kleinschreibung.
// Angemeldet wird die Regel mit den übrigen Ausdrucksregeln (Atlas.Common.Rules.Builtin.Expressions).

interface

uses
  Atlas.Common.Rules.Contract;

const
  cDuplicateConditionRuleId = 'duplicate-condition';

type
  TDuplicateConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.ConditionalExpression,
  Atlas.Text.Lines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TDuplicateConditionText = (DuplicateTitle, SameCondition, JumpToFirst, SameBranches, JumpToThen, Twice, SelfCompare);

const
  cTexts: array[TDuplicateConditionText] of TAtlasText = (
    (De: 'Doppelte Bedingung oder gleiche Zweige'; En: 'Duplicate condition or identical branches'),
    (De: 'Gleiche Bedingung wie in Zeile %d; dieser Zweig wird nie erreicht.';
     En: 'Same condition as in line %d; this branch is never reached.'),
    (De: 'Zum ersten Vorkommen springen'; En: 'Jump to the first occurrence'),
    (De: 'then- und else-Zweig sind gleich; die Bedingung hat keine Wirkung.';
     En: 'then and else branch are identical; the condition has no effect.'),
    (De: 'Zum then-Zweig springen'; En: 'Jump to the then branch'),
    (De: '%s steht zweimal in derselben %s-Verknüpfung; vermutlich ein Kopierfehler.';
     En: '%s appears twice in the same %s chain; probably a copy error.'),
    (De: '%s wird mit sich selbst verglichen; das Ergebnis ist immer %s.';
     En: '%s is compared with itself; the result is always %s.'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

{ TDuplicateConditionRule }

const
  // Aufrufe, die bei jedem Aufruf etwas anderes liefern können: dann ist die Wiederholung gewollt.
  cImpureCalls: array[0..11] of string = ('Read', 'Readln', 'Next', 'MoveNext', 'Pop', 'Dequeue', 'Extract',
    'Random', 'Execute', 'ExecSQL', 'GetTickCount', 'Now');
  cFloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Real', 'TDateTime');

function TDuplicateConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDuplicateConditionRuleId, TRuleSeverity.Warning,
    cTexts[TDuplicateConditionText.DuplicateTitle].Text);
end;

procedure TDuplicateConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;

  // Erstes Token ab AOffset (binäre Suche); Length(Tokens) ohne.
  function FirstToken(AOffset: Integer): Integer;
  var
    mLo, mHi, mMiddle: Integer;
  begin
    mLo := 0;
    mHi := Length(mTokens);
    while mLo < mHi do
    begin
      mMiddle := (mLo + mHi) div 2;
      if mTokens[mMiddle].Offset < AOffset then
      begin
        mLo := mMiddle + 1;
      end
      else
      begin
        mHi := mMiddle;
      end;
    end;
    Result := mLo;
  end;

  function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode;
    while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
    begin
      Result := Result[0];
    end;
  end;

  // Vergleichsschlüssel: Token ohne Kommentare, Bezeichner und Schlüsselwörter klein.
  function Key(ANode: TSyntaxNode): string;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
  begin
    mNode := Unwrapped(ANode);
    Result := '';
    mIndex := FirstToken(mNode.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < mNode.EndOffset) do
    begin
      if not IsTrivia(mTokens[mIndex]) then
      begin
        if mTokens[mIndex].Kind in [TPascalTokenKind.Identifier, TPascalTokenKind.Keyword] then
        begin
          Result := Result + LowerCase(mTokens[mIndex].Text) + ' ';
        end
        else
        begin
          Result := Result + mTokens[mIndex].Text + ' ';
        end;
      end;
      Inc(mIndex);
    end;
  end;

  function Display(ANode: TSyntaxNode): string;
  var
    mNode: TSyntaxNode;
  begin
    mNode := Unwrapped(ANode);
    Result := Trim(Copy(AContext.Text, mNode.StartOffset + 1, mNode.EndOffset - mNode.StartOffset));
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  function Impure(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.Call, TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and
          MatchText(mNode.Name, cImpureCalls) then
        begin
          Exit(True);
        end;
        if (mNode.Kind = TSyntaxKind.Call) and not TPureRoutines.IsPure(mNode.Name) then
        begin
          Exit(True);
        end;
        if mNode.Kind = TSyntaxKind.AnonymousMethod then
        begin
          Exit(True);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // if … else if …: spätere Bedingung gleich einer früheren.
  procedure CheckChain(AIf: TSyntaxNode);
  var
    mConditions: TArray<TSyntaxNode>;
    mCurrent: TSyntaxNode;
    mIndex, mEarlier: Integer;
  begin
    mConditions := nil;
    mCurrent := AIf;
    while (mCurrent <> nil) and (mCurrent.Kind = TSyntaxKind.IfStatement) and (mCurrent.ChildCount > 0) do
    begin
      mConditions := mConditions + [mCurrent[0]];
      if (mCurrent.ChildCount = 3) and (mCurrent[2].Kind = TSyntaxKind.IfStatement) then
      begin
        mCurrent := mCurrent[2];
      end
      else
      begin
        mCurrent := nil;
      end;
    end;
    // Ein Aufruf in der Kette kann den Zustand ändern, den eine spätere Bedingung liest.
    for mIndex := 0 to High(mConditions) do
    begin
      if Impure(mConditions[mIndex]) then
      begin
        Exit;
      end;
    end;
    for mIndex := 1 to High(mConditions) do
    begin
      for mEarlier := 0 to mIndex - 1 do
      begin
          if Key(mConditions[mEarlier]) = Key(mConditions[mIndex]) then
          begin
            AReport.Add(TTextRange.Create(mConditions[mIndex].StartPos, mConditions[mIndex].EndPos),
              cTexts[TDuplicateConditionText.SameCondition].Fmt([mConditions[mEarlier].StartPos.Line + 1]),
                TRuleConfidence.High,
              [TRuleFix.Jump(cTexts[TDuplicateConditionText.JumpToFirst].Text, mConditions[mEarlier].StartPos)]);
            Break;
          end;
      end;
    end;
  end;

  procedure CheckBranches(AIf: TSyntaxNode);
  begin
    if (AIf.ChildCount <> 3) or (AIf[2].Kind = TSyntaxKind.IfStatement) or (Key(AIf[1]) = '') or
      (Key(AIf[1]) <> Key(AIf[2])) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(AIf[0].StartPos, AIf[0].EndPos), cTexts[TDuplicateConditionText.SameBranches].Text,
      TRuleConfidence.High,
      [TRuleFix.Jump(cTexts[TDuplicateConditionText.JumpToThen].Text, AIf[1].StartPos)]);
  end;

  // Operanden einer Kette aus demselben Operator: A and B and A. Iterativ (tiefe Bäume sprengen den Stapel nicht):
  // rechter Operand zuerst auf den Stapel, damit die Operanden von links nach rechts in AList landen.
  procedure Operands(ANode: TSyntaxNode; const AOperator: string; var AList: TArray<TSyntaxNode>);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := Unwrapped(mPending.Pop);
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and SameText(mNode.Name, AOperator) and (mNode.ChildCount = 2) then
        begin
          mPending.Push(mNode[1]);
          mPending.Push(mNode[0]);
        end
        else
        begin
          AList := AList + [mNode];
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CheckLogical(ANode: TSyntaxNode);
  var
    mList: TArray<TSyntaxNode>;
    mIndex, mEarlier: Integer;
    mOp: string;
    mParent: TSyntaxNode;
  begin
    // Nur am Anfang der Kette prüfen, auch durch Klammern hindurch.
    mParent := ANode.Parent;
    while (mParent <> nil) and (mParent.Kind = TSyntaxKind.ParenExpr) do
    begin
      mParent := mParent.Parent;
    end;
    if (mParent <> nil) and (mParent.Kind = TSyntaxKind.BinaryExpr) and SameText(mParent.Name, ANode.Name) then
    begin
      Exit;
    end;
    mOp := LowerCase(ANode.Name);
    mList := nil;
    Operands(ANode, mOp, mList);
    for mIndex := 0 to High(mList) do
    begin
      if Impure(mList[mIndex]) then
      begin
        Exit;
      end;
    end;
    for mIndex := 1 to High(mList) do
    begin
      for mEarlier := 0 to mIndex - 1 do
      begin
          if Key(mList[mEarlier]) = Key(mList[mIndex]) then
          begin
            AReport.Add(TTextRange.Create(mList[mIndex].StartPos, mList[mIndex].EndPos),
              cTexts[TDuplicateConditionText.Twice].Fmt([Display(mList[mIndex]), mOp]), TRuleConfidence.High,
              [TRuleFix.Jump(cTexts[TDuplicateConditionText.JumpToFirst].Text, mList[mEarlier].StartPos)]);
            Break;
          end;
      end;
    end;
  end;

  function IsFloat(ANode: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    mNode := Unwrapped(ANode);
    Result := (mNode.Kind = TSyntaxKind.Identifier) and MatchText(mTypes.DeclaredType(mNode.Name, mNode.StartPos),
      cFloatTypes);
  end;

  // TKlasse.Instanz: Mitglied eines Bezeichners in der Form TName?
  function IsClassMember(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.MemberAccess) and (ANode.ChildCount > 0) and
      (ANode[0].Kind = TSyntaxKind.Identifier);
    Result := Result and (Length(ANode[0].Name) > 1) and (ANode[0].Name[1] = 'T') and
      CharInSet(ANode[0].Name[2], ['A'..'Z']);
  end;

  // TKlasse.Instanz = TKlasse.Instanz prüft bewusst die Identität eines Singletons.
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  function OnClass(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if IsClassMember(mNode) then
        begin
          Exit(True);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CheckComparison(ANode: TSyntaxNode);
  var
    mOutcome: string;
  begin
    if (ANode.ChildCount <> 2) or (Key(ANode[0]) <> Key(ANode[1])) or Impure(ANode) or OnClass(ANode) then
    begin
      Exit;
    end;
    // X <> X ist bei Gleitkommazahlen die Prüfung auf NaN.
    if IsFloat(ANode[0]) then
    begin
      Exit;
    end;
    if MatchStr(ANode.Name, ['=', '<=', '>=']) then
    begin
      mOutcome := 'True';
    end
    else
    begin
      mOutcome := 'False';
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      cTexts[TDuplicateConditionText.SelfCompare].Fmt([Display(ANode[0]), mOutcome]), TRuleConfidence.High);
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Visit(ARoot: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.IfStatement then
        begin
          // Kette nur vom ersten if aus.
          if not ((mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.IfStatement) and
            (mNode.Parent.ChildCount = 3) and (mNode.Parent[2] = mNode)) then
          begin
            CheckChain(mNode);
          end;
          CheckBranches(mNode);
        end
        else if mNode.Kind = TSyntaxKind.BinaryExpr then
        begin
          if MatchText(mNode.Name, ['and', 'or', 'xor']) then
          begin
            CheckLogical(mNode);
          end
          else if MatchStr(mNode.Name, ['=', '<>', '<', '>', '<=', '>=']) then
          begin
            CheckComparison(mNode);
          end;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    mTypes.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Expressions.DuplicateConditions', cTexts);

end.
