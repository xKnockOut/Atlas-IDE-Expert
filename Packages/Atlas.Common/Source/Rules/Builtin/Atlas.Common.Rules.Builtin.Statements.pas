unit Atlas.Common.Rules.Builtin.Statements;


//   empty-statement   Semikolon direkt nach then, do oder else (#912): die
//                     folgende Zeile läuft immer bzw. die Schleife dreht leer.
//                     Leere Blöcke begin … end nach then, do oder else ebenso,
//                     außer mit Kommentar darin (Option allowCommented).
//   destroy-called-directly
//                     Obj.Destroy als Anweisung statt Obj.Free (#920): bei nil
//                     knallt es. inherited Destroy und Destroy mit Argumenten
//                     (eigener Destruktor) bleiben still; Korrektur Free.
//   comparison-as-statement
//                     Result = 0; als eigene Anweisung (#982, wie E2014): gemeint
//                     war :=. Bei = mit zuweisbarer linker Seite ersetzt die
//                     Korrektur = durch :=; andere Vergleiche und Ausdrücke wie
//                     A + B; oder not A; meldet die Regel ohne Korrektur.
// Weitere Anweisungsregeln: Statements.Loops, Statements.Cases, Statements.Datasets, Statements.Properties.
// Grundlage ist der Syntaxbaum: if, while, for, for-in und with ohne Rumpf
// bzw. mit leerem Block; das Schlüsselwort davor sucht die Regel in den Token.

interface

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cEmptyStatementRuleId = 'empty-statement';
  cDestroyCalledDirectlyRuleId = 'destroy-called-directly';
  cComparisonAsStatementRuleId = 'comparison-as-statement';

type
  TEmptyStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDestroyCalledDirectlyRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TComparisonAsStatementRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ausdruck, den die Aufrufanweisung AStatement als Anweisung stehen lässt (Vergleich, Operator, Literal);
    /// nil sonst.</summary>
    class function ExpressionOf(AStatement: TSyntaxNode): TSyntaxNode; static;
  end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Pascal.Contract,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Statements.Tokens,
  Atlas.Common.Rules.Builtin.Statements.Loops,
  Atlas.Common.Rules.Builtin.Statements.Cases,
  Atlas.Common.Rules.Builtin.Statements.Datasets,
  Atlas.Common.Rules.Builtin.Statements.Properties,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TStatementsText = (EmptyTitle, EmptyLoop, EmptyNextLine, RemoveSemicolon, EmptyBlock, DestroyTitle, DestroyDirect,
    FreeInstead, ComparisonTitle, ComparisonUnused, ComparisonMeant, AssignMeant, ToAssign, ExpressionUnused);

const
  cTexts: array[TStatementsText] of TAtlasText = (
    (De: 'Leere Anweisung nach then, do oder else'; En: 'Empty statement after then, do or else'),
    (De: 'Leere Anweisung nach %s: die Schleife dreht leer.'; En: 'Empty statement after %s: the loop spins empty.'),
    (De: 'Leere Anweisung nach %s: die nächste Zeile läuft immer.';
     En: 'Empty statement after %s: the next line always runs.'),
    (De: 'Semikolon entfernen'; En: 'Remove semicolon'),
    (De: 'Leerer Block nach %s: hier passiert nichts.'; En: 'Empty block after %s: nothing happens here.'),
    (De: 'Destroy statt Free aufgerufen'; En: 'Destroy called instead of Free'),
    (De: 'Destroy direkt aufgerufen; Free prüft vorher auf nil.';
     En: 'Destroy called directly; Free checks for nil first.'),
    (De: 'Free statt Destroy'; En: 'Free instead of Destroy'),
    (De: 'Vergleich statt Zuweisung als Anweisung'; En: 'Comparison instead of assignment as statement'),
    (De: 'Vergleich als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.';
     En: 'Comparison as statement (like E2014); the result is not used.'),
    (De: 'Vergleich als Anweisung (wie E2014); gemeint ist wohl %s.';
     En: 'Comparison as statement (like E2014); %s is probably meant.'),
    (De: 'Vergleich als Anweisung (wie E2014); gemeint ist wohl := statt =.';
     En: 'Comparison as statement (like E2014); := instead of = is probably meant.'),
    (De: '= durch := ersetzen'; En: 'Replace = with :='),
    (De: 'Ausdruck als Anweisung (wie E2014); das Ergebnis wird nicht verwendet.';
     En: 'Expression as statement (like E2014); the result is not used.'));

{$SCOPEDENUMS OFF}

{ TEmptyStatementRule }

function TEmptyStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cEmptyStatementRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsText.EmptyTitle].Text);
end;

procedure TEmptyStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mAllowCommented: Boolean;
  mReport: IRuleReport;

  // Semikolon ANext direkt nach dem Schlüsselwort AKeyword melden, außer am Blockende.
  procedure InspectSemicolon(AKeyword, ANext: Integer; AIsLoop: Boolean);
  var
    mAfter: Integer;
    mWord, mMessage: string;
  begin
    mAfter := NextCode(mTokens, ANext + 1);
    // Am Blockende ändert das Semikolon nichts am Ablauf (z. B. while not Fertig do; als Warteschleife).
    if (mAfter > High(mTokens)) or (mTokens[mAfter].Kind = TPascalTokenKind.Keyword) and
      MatchText(mTokens[mAfter].Text, ['end', 'until', 'except', 'finally', 'else']) then
    begin
      Exit;
    end;
    mWord := LowerCase(mTokens[AKeyword].Text);
    if AIsLoop then
    begin
      mMessage := cTexts[TStatementsText.EmptyLoop].Fmt([mWord]);
    end
    else
    begin
      mMessage := cTexts[TStatementsText.EmptyNextLine].Fmt([mWord]);
    end;
    mReport.Add(TTextRange.Create(mTokens[AKeyword].StartPos, mTokens[ANext].EndPos), mMessage, TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TStatementsText.RemoveSemicolon].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[ANext].StartPos,
      mTokens[ANext].EndPos), '')])]);
  end;

  // begin end ohne Anweisung ab Token ANext, mit Kommentar darin nur bei allowCommented = false.
  procedure InspectEmptyBlock(AKeyword, ANext: Integer; ABody: TSyntaxNode);
  var
    mIndex: Integer;
    mHasComment: Boolean;
  begin
    mHasComment := False;
    mIndex := ANext + 1;
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ABody.EndOffset) do
    begin
      mHasComment := mHasComment or (mTokens[mIndex].Kind = TPascalTokenKind.Comment);
      Inc(mIndex);
    end;
    if not (mHasComment and mAllowCommented) then
    begin
      mReport.Add(TTextRange.Create(mTokens[AKeyword].StartPos, mTokens[mIndex - 1].EndPos),
        cTexts[TStatementsText.EmptyBlock].Fmt([LowerCase(mTokens[AKeyword].Text)]),
        TRuleConfidence.High);
    end;
  end;

  // AKeyword: Index von then/do/else; ABody: Anweisung danach oder nil.
  procedure Inspect(AKeyword: Integer; ABody: TSyntaxNode; AIsLoop: Boolean);
  var
    mNext: Integer;
  begin
    if AKeyword < 0 then
    begin
      Exit;
    end;
    mNext := NextCode(mTokens, AKeyword + 1);
    if mNext > High(mTokens) then
    begin
      Exit;
    end;
    if mTokens[mNext].IsSymbol(';') and ((ABody = nil) or (ABody.StartOffset > mTokens[mNext].Offset)) then
    begin
      InspectSemicolon(AKeyword, mNext, AIsLoop);
    end
    else if (ABody <> nil) and (ABody.Kind = TSyntaxKind.Block) and (ABody.ChildCount = 0) and
      mTokens[mNext].IsKeyword('begin') and (mTokens[mNext].Offset = ABody.StartOffset) then
    begin
      InspectEmptyBlock(AKeyword, mNext, ABody);
    end;
  end;

  // Liegt der Token AIndex in einer untergeordneten Anweisung von ANode?
  function InChildStatement(ANode: TSyntaxNode; AIndex: Integer): Boolean;
  var
    mChild: Integer;
  begin
    Result := False;
    for mChild := 0 to ANode.ChildCount - 1 do
    begin
      if (ANode[mChild].Kind in StatementKinds) and (mTokens[AIndex].Offset >= ANode[mChild].StartOffset) and
        (mTokens[AIndex].Offset < ANode[mChild].EndOffset) then
      begin
        Exit(True);
      end;
    end;
  end;

  // Schlüsselwort AWord dieses Knotens: auf Klammerebene 0 und nicht in einer untergeordneten Anweisung.
  function OwnKeyword(ANode: TSyntaxNode; AFrom, AStop: Integer; const AWord: string): Integer;
  var
    mIndex, mDepth: Integer;
  begin
    mDepth := 0;
    for mIndex := AFrom to AStop - 1 do
    begin
      if mTokens[mIndex].IsSymbol('(') or mTokens[mIndex].IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if mTokens[mIndex].IsSymbol(')') or mTokens[mIndex].IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and mTokens[mIndex].IsKeyword(AWord) and not InChildStatement(ANode, mIndex) then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

  procedure VisitIf(ANode: TSyntaxNode; AStop: Integer);
  var
    mThen, mElse: Integer;
    mBody: TSyntaxNode;
  begin
    mThen := OwnKeyword(ANode, TokenFrom(mTokens, ANode[0].EndOffset), AStop, 'then');
    if mThen < 0 then
    begin
      Exit;
    end;
    mElse := OwnKeyword(ANode, mThen + 1, AStop, 'else');
    mBody := StatementAfter(ANode, mTokens[mThen].Offset);
    if (mBody <> nil) and (mElse >= 0) and (mBody.StartOffset > mTokens[mElse].Offset) then
    begin
      mBody := nil;
    end;
    Inspect(mThen, mBody, False);
    if mElse >= 0 then
    begin
      Inspect(mElse, StatementAfter(ANode, mTokens[mElse].Offset), False);
    end;
  end;

  procedure VisitLoop(ANode: TSyntaxNode; AStop: Integer);
  var
    mDo: Integer;
  begin
    mDo := OwnKeyword(ANode, TokenFrom(mTokens, ANode.StartOffset), AStop, 'do');
    if mDo >= 0 then
    begin
      Inspect(mDo, StatementAfter(ANode, mTokens[mDo].Offset), ANode.Kind <> TSyntaxKind.WithStatement);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex, mStop: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1): lange else-if-Ketten ergeben sehr tiefe Bäume.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mStop := TokenFrom(mTokens, mNode.EndOffset);
        case mNode.Kind of
          TSyntaxKind.IfStatement:
            if mNode.ChildCount > 0 then
            begin
              VisitIf(mNode, mStop);
            end;
          TSyntaxKind.WhileStatement, TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement,
          TSyntaxKind.WithStatement:
            VisitLoop(mNode, mStop);
        else
          // Übrige Werte bewusst ohne Wirkung.
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
  mAllowCommented := TRuleOptions.Bool(AContext.Options, 'allowCommented', True);
  mReport := AReport;
  Visit(AContext.Tree.Root);
end;

{ TDestroyCalledDirectlyRule }

function TDestroyCalledDirectlyRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDestroyCalledDirectlyRuleId, TRuleSeverity.Warning,
    cTexts[TStatementsText.DestroyTitle].Text);
end;

procedure TDestroyCalledDirectlyRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;

  // X.Destroy bzw. X.Destroy() ohne Argumente als Anweisung: der Zugriff; sonst nil.
  function DestroyAccess(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := nil;
    if (ANode.Kind <> TSyntaxKind.CallStatement) or (ANode.ChildCount = 0) then
    begin
      Exit;
    end;
    Result := ANode[0];
    if (Result.Kind = TSyntaxKind.Call) and (Result.ChildCount = 1) then
    begin
      Result := Result[0];
    end;
    if (Result.Kind <> TSyntaxKind.MemberAccess) or (Result.ChildCount <> 1) or
      not SameText(Result.Name, 'Destroy') then
    begin
      Result := nil;
    end;
  end;

  // Letztes Token "Destroy" im Zugriff ATarget; -1 ohne.
  function NameToken(ATarget: TSyntaxNode): Integer;
  var
    mIndex: Integer;
  begin
    Result := -1;
    mIndex := TokenFrom(mTokens, ATarget.StartOffset);
    while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ATarget.EndOffset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, 'Destroy') then
      begin
        Result := mIndex;
      end;
      Inc(mIndex);
    end;
  end;

  procedure Inspect(ANode: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
    mName: Integer;
    mRange: TTextRange;
  begin
    mTarget := DestroyAccess(ANode);
    mName := -1;
    if mTarget <> nil then
    begin
      mName := NameToken(mTarget);
    end;
    if mName >= 0 then
    begin
      mRange := TTextRange.Create(mTokens[mName].StartPos, mTokens[mName].EndPos);
      AReport.Add(mRange, cTexts[TStatementsText.DestroyDirect].Text, TRuleConfidence.High,
        [TRuleFix.Create(cTexts[TStatementsText.FreeInstead].Text, [TRuleEdit.Create(mRange, 'Free')], True)]);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mNode: TSyntaxNode;
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        Inspect(mNode);
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
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  Visit(AContext.Tree.Root);
end;

{ TComparisonAsStatementRule }

function TComparisonAsStatementRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cComparisonAsStatementRuleId, TRuleSeverity.Error,
    cTexts[TStatementsText.ComparisonTitle].Text);
end;

class function TComparisonAsStatementRule.ExpressionOf(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (AStatement = nil) or (AStatement.Kind <> TSyntaxKind.CallStatement) or (AStatement.ChildCount <> 1) then
  begin
    Exit;
  end;
  Result := AStatement[0];
  // (A = 1); zählt wie A = 1;
  while (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
  if not (Result.Kind in [TSyntaxKind.BinaryExpr, TSyntaxKind.UnaryExpr, TSyntaxKind.Literal,
    TSyntaxKind.SetConstructor]) then
  begin
    Result := nil;
  end;
end;

procedure TComparisonAsStatementRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
const
  cComparisons: array[0..7] of string = ('=', '<>', '<', '>', '<=', '>=', 'in', 'is');
  // Längere Vorschläge kürzt die Meldung nicht, sie lässt sie weg.
  cMaxSuggestion = 60;
var
  mTokens: TTokens;

  function IsComparison(const AOperator: string): Boolean;
  var
    mItem: string;
  begin
    for mItem in cComparisons do
    begin
      if SameText(mItem, AOperator) then
      begin
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Quelltext von ANode, Leerraum und Zeilenumbrüche zu einem Leerzeichen.
  function Compact(ANode: TSyntaxNode): string;
  var
    mRaw: string;
    mIndex: Integer;
    mSpace: Boolean;
  begin
    mRaw := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
    Result := '';
    mSpace := False;
    for mIndex := 1 to Length(mRaw) do
    begin
      if CharInSet(mRaw[mIndex], [' ', #9, #10, #13]) then
      begin
        mSpace := True;
      end
      else
      begin
        if mSpace and (Result <> '') then
        begin
          Result := Result + ' ';
        end;
        mSpace := False;
        Result := Result + mRaw[mIndex];
      end;
    end;
  end;

  // Linke Seite, der man zuweisen kann (Variable, Feld, Element, Ziel eines Zeigers).
  function Assignable(ANode: TSyntaxNode): Boolean;
  begin
    Result := ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
      TSyntaxKind.Dereference];
  end;

  // Token "=" zwischen linker und rechter Seite; -1 ohne.
  function EqualsToken(AExpression: TSyntaxNode): Integer;
  var
    mIndex: Integer;
  begin
    for mIndex := TokenFrom(mTokens, AExpression[0].EndOffset) to High(mTokens) do
    begin
      if mTokens[mIndex].Offset >= AExpression[1].StartOffset then
      begin
        Break;
      end;
      if mTokens[mIndex].IsSymbol('=') then
      begin
        Exit(mIndex);
      end;
    end;
    Result := -1;
  end;

  // A = B mit zuweisbarem A: Token "="; sonst -1.
  function AssignmentEquals(AExpression: TSyntaxNode): Integer;
  begin
    Result := -1;
    if (AExpression.Name = '=') and (AExpression.ChildCount = 2) and Assignable(AExpression[0]) then
    begin
      Result := EqualsToken(AExpression);
    end;
  end;

  // Meldung für einen Vergleich als Anweisung; mit Korrektur := statt =, wenn eine Zuweisung gemeint sein kann.
  function ComparisonMessage(AExpression: TSyntaxNode; out AFixes: TArray<TRuleFix>): string;
  var
    mEquals: Integer;
    mSuggestion: string;
  begin
    AFixes := nil;
    Result := cTexts[TStatementsText.ComparisonUnused].Text;
    mEquals := AssignmentEquals(AExpression);
    if mEquals < 0 then
    begin
      Exit;
    end;
    mSuggestion := Compact(AExpression[0]) + ' := ' + Compact(AExpression[1]);
    if Length(mSuggestion) <= cMaxSuggestion then
    begin
      Result := cTexts[TStatementsText.ComparisonMeant].Fmt([mSuggestion]);
    end
    else
    begin
      Result := cTexts[TStatementsText.AssignMeant].Text;
    end;
    AFixes := [TRuleFix.Create(cTexts[TStatementsText.ToAssign].Text,
      [TRuleEdit.Create(TTextRange.Create(mTokens[mEquals].StartPos,
      mTokens[mEquals].EndPos), ':=')], True)];
  end;

  procedure Inspect(AExpression: TSyntaxNode);
  var
    mMessage: string;
    mFixes: TArray<TRuleFix>;
  begin
    mFixes := nil;
    if (AExpression.Kind = TSyntaxKind.BinaryExpr) and IsComparison(AExpression.Name) then
    begin
      mMessage := ComparisonMessage(AExpression, mFixes);
    end
    else
    begin
      mMessage := cTexts[TStatementsText.ExpressionUnused].Text;
    end;
    AReport.Add(TTextRange.Create(AExpression.StartPos, AExpression.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mNode, mExpression: TSyntaxNode;
    mIndex: Integer;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mExpression := ExpressionOf(mNode);
        if mExpression <> nil then
        begin
          Inspect(mExpression);
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
  Visit(AContext.Tree.Root);
end;

procedure RegisterStatementRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TEmptyStatementRule.Create);
  ARegistry.Register(TDestroyCalledDirectlyRule.Create);
  ARegistry.Register(TLoopOffByOneRule.Create);
  ARegistry.Register(TCollectionModifiedInLoopRule.Create);
  ARegistry.Register(TCaseMissingEnumValueRule.Create);
  ARegistry.Register(TDatasetLoopWithoutNextRule.Create);
  ARegistry.Register(TDatasetEditWithoutPostRule.Create);
  ARegistry.Register(TTransactionWithoutRollbackRule.Create);
  ARegistry.Register(TComparisonAsStatementRule.Create);
  ARegistry.Register(TDuplicateCaseLabelRule.Create);
  ARegistry.Register(TAssignToPropertyMemberRule.Create);
  ARegistry.Register(TUntypedPointerRefcountRule.Create);
  ARegistry.Register(TReadonlyPropertyAssignedRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Statements', cTexts);

end.
