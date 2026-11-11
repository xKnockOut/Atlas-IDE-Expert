unit Atlas.Common.Rules.Builtin.Expressions;

// Regeln für Ausdrücke, die anders gebunden werden als gemeint (#909):
//   operator-precedence   not bindet stärker als in und Vergleiche (#911):
//                         "not X in Menge" ist "(not X) in Menge", "not A = B"
//                         ist "(not A) = B", bei Ganzzahlen bitweise.
// Gemeldet wird nur, wenn der Typ des Operanden in der Datei deklariert und
// kein Boolean ist (Atlas.Common.Pascal.DeclaredTypes); unbekannte Typen und
// Variants bleiben stumm.
//   duplicate-condition   dieselbe Bedingung zweimal in einer if-else-if-Kette, gleiche then- und
//                         else-Zweige, A and A bzw. A or A, X = X (#928). Verglichen wird der
//                         Quelltext ohne Leerraum, Kommentare und Groß-/Kleinschreibung.
//   string-index-base     Copy(S, 0, N), Delete(S, 0, N), Insert(T, S, 0) auf Strings (deklarierter Typ,
//                         Literal, .Text/.Caption) und Pos(…) verglichen mit -1 bzw. >= 0 (#951); umgekehrt
//                         S.IndexOf(…) > 0 bzw. < 1 (nullbasiert, -1 bei keinem Treffer; LastIndexOf nicht,
//                         dort ist "> 0" meist bewusst).
//   null-compare          X = Null bzw. X <> Null (#953): Das Ergebnis hängt von NullEqualityRule ab (Vorgabe
//                         ncrLoose vergleicht wie erwartet, ncrStrict liefert nie wahr, ncrError eine Exception).
//                         Korrektur: Feld.IsNull bei X.Value auf FieldByName/FindField/Fields[…]/Params bzw.
//                         einem Feld vom Typ T…Field/T…Param, sonst VarIsNull(X); bei <> mit not.
//   pos-arguments-swapped Pos(Text, ';') statt Pos(';', Text), ebenso PosEx, StartsText, EndsText (…Str, Ansi…) und
//                         umgekehrt ContainsText(';', Text) (#1045): an der Stelle des Textes ein kurzes Literal
//                         (bis maxLiteralLength Zeichen, Vorgabe 3), an der Stelle des Teils sicher ein String
//                         (deklarierter Typ, .Text/.Caption, String-Funktion, Verkettung). Zeichen bleiben stumm:
//                         Pos(C, ';,') prüft bewusst, ob C einer der Trenner ist.
//   integer-division-to-float
//                         Schnitt := Summe div Anzahl mit Schnitt: Double (#1046): div schneidet ab, bevor zugewiesen
//                         wird; auch Teil div Gesamt * 100, Result und var X: Double := …. Gesucht wird durch Klammern
//                         und + - * / hindurch, nicht in Aufrufen (Round(A div B)). Ziel mit in der Datei deklariertem
//                         Gleitkommatyp; TDateTime bleibt stumm (ganze Tage sind dort meist gewollt), ebenso with
//                         und Trunc(A) div Trunc(B) (ausdrücklich gewandelt, also gewollt ganzzahlig).
//   conditional-expression-version
//                         Bedingungsausdruck X := if C then A else B in einem Projekt, das mit Delphi 12 oder älter
//                         übersetzen muss (#684, Gruppe Compiler, wie E2029): gemeldet wird der äußerste Ausdruck,
//                         nicht in Zweigen von {$IF}, die nach CompilerVersion, RTLVersion, VERnnn oder Declared
//                         fragen. Korrektur „In if-Anweisung umwandeln“ (TConditionalExpression), auch als
//                         Sammelkorrektur. Ohne bekannte Version still.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cOperatorPrecedenceRuleId = 'operator-precedence';
  cDuplicateConditionRuleId = 'duplicate-condition';
  cStringIndexBaseRuleId = 'string-index-base';
  cNullCompareRuleId = 'null-compare';
  cPosArgumentsSwappedRuleId = 'pos-arguments-swapped';
  cIntegerDivisionToFloatRuleId = 'integer-division-to-float';
  cConditionalExpressionVersionRuleId = 'conditional-expression-version';

type
  TOperatorPrecedenceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TDuplicateConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TStringIndexBaseRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist AType ein String-Typ (string, AnsiString, ShortString, String[n] …)?</summary>
    class function IsStringType(const AType: string): Boolean; static;
  end;

  TNullCompareRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Ist AType ein Datenbankfeld oder Parameter (TField, TStringField, TParam, TFDParam …)?</summary>
    class function IsDataType(const AType: string): Boolean; static;
  end;

  TPosArgumentsSwappedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Zeichenzahl eines Literals aus '…'- und #n-Teilen ('''' zählt als ein Zeichen); -1, wenn
    /// ALiteral kein solches Literal ist.</summary>
    class function LiteralLength(const ALiteral: string): Integer; static;
  end;

  TIntegerDivisionToFloatRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Gleitkommatyp mit Nachkommastellen (Double, Single, Extended, Real, Currency …), ohne
    /// TDateTime.</summary>
    class function IsFractional(const AType: string): Boolean; static;
  end;

  TConditionalExpressionVersionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Fragt die Direktive ADirective (Text samt Klammern) nach der Compilerversion?</summary>
    class function IsVersionDirective(const ADirective: string): Boolean; static;
  end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);

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
  Atlas.Common.Rules.Options,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.LanguageFeatures,
  Atlas.Common.Editing.StatementText,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.ConditionalExpression,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.Expressions.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TExpressionsText = (NotTitle, NotIn, NotBitwise, NotCompare, AddParens, DuplicateTitle, SameCondition, JumpToFirst,
    SameBranches, JumpToThen, Twice, SelfCompare, IndexTitle, DeleteZero, StartZero, StartOne, FixComparison,
    AlwaysTrue, NeverTrue, MissesFirst, FirstNotFound, NullTitle, NullField, NullVariant, ReplaceWith, SwappedTitle,
    SwappedText, SwappedPart, SwapArguments, DivTitle, DivLoses, ReplaceDiv, ConditionalTitle, ConditionalVersion);

const
  cTexts: array[TExpressionsText] of TAtlasText = (
    (De: 'Vorrang von not vor in und Vergleichen übersehen';
     En: 'Precedence of not over in and comparisons overlooked'),
    (De: '„not“ gilt nur für %s, nicht für den in-Ausdruck. Gemeint ist vermutlich not (%s).';
     En: '“not” applies only to %s, not to the in expression. Probably not (%s) is meant.'),
    (De: '„not“ kehrt die Ganzzahl %s bitweise um, nicht den Vergleich. Gemeint ist vermutlich not (%s).';
     En: '“not” inverts the integer %s bitwise, not the comparison. Probably not (%s) is meant.'),
    (De: '„not“ gilt nur für %s, nicht für den Vergleich. Gemeint ist vermutlich not (%s).';
     En: '“not” applies only to %s, not to the comparison. Probably not (%s) is meant.'),
    (De: 'Klammern setzen: not (%s)'; En: 'Add parentheses: not (%s)'),
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
     En: '%s is compared with itself; the result is always %s.'),
    (De: 'String-Index ab 0 oder Pos-Ergebnis mit -1 verglichen';
     En: 'String index from 0 or Pos result compared with -1'),
    (De: 'Delete zählt Zeichen ab 1; mit dem Startwert 0 löscht es nichts.';
     En: 'Delete counts characters from 1; with the start value 0 it deletes nothing.'),
    (De: '%s zählt Zeichen ab 1; der Startwert 0 wirkt nur zufällig wie 1.';
     En: '%s counts characters from 1; the start value 0 only works like 1 by chance.'),
    (De: 'Startwert 1'; En: 'Start value 1'),
    (De: 'Vergleich auf "%s" korrigieren'; En: 'Correct comparison to "%s"'),
    (De: '%s liefert 0 bei keinem Treffer; der Vergleich %s ist immer wahr.';
     En: '%s returns 0 for no match; the comparison %s is always true.'),
    (De: '%s liefert 0 bei keinem Treffer; der Vergleich %s ist nie wahr.';
     En: '%s returns 0 for no match; the comparison %s is never true.'),
    (De: '%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s übersieht den Treffer am Anfang.';
     En: '%s counts from 0 and returns -1 for no match; the comparison %s misses the match at the start.'),
    (De: '%s zählt ab 0 und liefert -1 bei keinem Treffer; der Vergleich %s zählt den Treffer am Anfang als nicht ' +
      'gefunden.';
     En: '%s counts from 0 and returns -1 for no match; the comparison %s counts the match at the start as not found.'),
    (De: 'Vergleich mit Null statt VarIsNull oder IsNull'; En: 'Comparison with Null instead of VarIsNull or IsNull'),
    (De: 'Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: Exception); IsNull ' +
      'prüft das Feld unabhängig davon.';
     En: 'The comparison with Null depends on NullEqualityRule (ncrStrict: never true, ncrError: exception); IsNull ' +
      'checks the field regardless.'),
    (De: 'Der Vergleich mit Null hängt von NullEqualityRule ab (ncrStrict: nie wahr, ncrError: Exception); VarIsNull ' +
      'prüft den Wert unabhängig davon.';
     En: 'The comparison with Null depends on NullEqualityRule (ncrStrict: never true, ncrError: exception); ' +
      'VarIsNull checks the value regardless.'),
    (De: 'Durch "%s" ersetzen'; En: 'Replace with "%s"'),
    (De: 'Argumente von Pos, StartsText oder ContainsText vertauscht';
     En: 'Arguments of Pos, StartsText or ContainsText swapped'),
    (De: '%s(Text, Teil): vermutlich vertauscht, gesucht wird %s in %s.';
     En: '%s(Text, Part): probably swapped, %s is searched in %s.'),
    (De: '%s(Teil, Text): vermutlich vertauscht, gesucht wird %s in %s.';
     En: '%s(Part, Text): probably swapped, %s is searched in %s.'),
    (De: 'Argumente tauschen'; En: 'Swap arguments'),
    (De: 'Ganzzahldivision an Gleitkommazahl'; En: 'Integer division assigned to a floating-point number'),
    (De: 'div rechnet ganzzahlig; %s ist %s und verliert die Nachkommastellen.';
     En: 'div calculates as integer; %s is %s and loses the decimal places.'),
    (De: 'div durch / ersetzen'; En: 'Replace div with /'),
    (De: 'Bedingungsausdruck vor Delphi 13'; En: 'Conditional expression before Delphi 13'),
    (De: 'Bedingungsausdrücke gibt es erst ab %s (eingestellt: %s)';
     En: 'Conditional expressions exist only from %s on (set: %s)'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

{ TOperatorPrecedenceRule }

function TOperatorPrecedenceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cOperatorPrecedenceRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.NotTitle].Text);
end;

/// <summary>Meldung für "not X op Y" (AShown) mit dem Operator AOp und dem Typ ATypeName von X.</summary>
function PrecedenceMessage(const AOp: TPascalToken; const ATypeName, AName, AShown: string): string;
begin
  if AOp.IsKeyword('in') then
  begin
    Result := cTexts[TExpressionsText.NotIn].Fmt([AName, AShown]);
  end
  else if TDeclaredTypes.IsInt32(ATypeName) or TDeclaredTypes.IsInt64(ATypeName) then
  begin
    Result := cTexts[TExpressionsText.NotBitwise].Fmt([AName, AShown]);
  end
  else
  begin
    Result := cTexts[TExpressionsText.NotCompare].Fmt([AName, AShown]);
  end;
end;

/// <summary>Meldet "not X op Y" (AParts) mit dem Typ ATypeName von X samt Korrektur not (X op Y).</summary>
procedure ReportPrecedence(const AContext: TRuleContext; const AReport: IRuleReport; const ATokens: TTokens;
  const AParts: TNotComparison; const ATypeName: string);
var
  mName, mShown: string;
begin
  mName := ATokens[AParts.Operand].Text;
  mShown := Trim(SourceText(AContext.Text, ATokens, AParts.Right, AParts.Last));
  if ATokens[AParts.Right].IsSymbol('[') then
  begin
    mShown := '[…]';
  end;
  mShown := mName + ' ' + ATokens[AParts.Op].Text + ' ' + mShown;
  AReport.Add(RangeOf(ATokens, AParts.NotToken, AParts.Last), PrecedenceMessage(ATokens[AParts.Op], ATypeName,
    mName, mShown), TRuleConfidence.High, [TRuleFix.Create(cTexts[TExpressionsText.AddParens].Fmt([mShown]),
    [TRuleEdit.Create(RangeOf(ATokens, AParts.Operand, AParts.Last),
    '(' + SourceText(AContext.Text, ATokens, AParts.Operand, AParts.Last) + ')')])]);
end;

procedure TOperatorPrecedenceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mTypes: TDeclaredTypes;
  mIndex: Integer;
  mParts: TNotComparison;
  mTypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      if not NotComparisonAt(mTokens, mIndex, mParts) or not InStatements(AContext.Tree, mTokens[mIndex].StartPos) then
      begin
        Continue;
      end;
      mTypeName := mTypes.DeclaredType(mTokens[mParts.Operand].Text, mTokens[mParts.Operand].StartPos);
      if (mTypeName <> '') and not IsLogical(mTypeName) then
      begin
        ReportPrecedence(AContext, AReport, mTokens, mParts, mTypeName);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TDuplicateConditionRule }

const
  // Aufrufe, die bei jedem Aufruf etwas anderes liefern können: dann ist die Wiederholung gewollt.
  cImpureCalls: array[0..11] of string = ('Read', 'Readln', 'Next', 'MoveNext', 'Pop', 'Dequeue', 'Extract',
    'Random', 'Execute', 'ExecSQL', 'GetTickCount', 'Now');
  cFloatTypes: array[0..4] of string = ('Double', 'Single', 'Extended', 'Real', 'TDateTime');

function TDuplicateConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cDuplicateConditionRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.DuplicateTitle].Text);
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
              cTexts[TExpressionsText.SameCondition].Fmt([mConditions[mEarlier].StartPos.Line + 1]),
                TRuleConfidence.High,
              [TRuleFix.Jump(cTexts[TExpressionsText.JumpToFirst].Text, mConditions[mEarlier].StartPos)]);
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
    AReport.Add(TTextRange.Create(AIf[0].StartPos, AIf[0].EndPos), cTexts[TExpressionsText.SameBranches].Text,
      TRuleConfidence.High,
      [TRuleFix.Jump(cTexts[TExpressionsText.JumpToThen].Text, AIf[1].StartPos)]);
  end;

  // Operanden einer Kette aus demselben Operator: A and B and A. Iterativ (tiefe Bäume sprengen den Stapel nicht): rechter Operand
  // zuerst auf den Stapel, damit die Operanden von links nach rechts in AList landen.
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
              cTexts[TExpressionsText.Twice].Fmt([Display(mList[mIndex]), mOp]), TRuleConfidence.High,
              [TRuleFix.Jump(cTexts[TExpressionsText.JumpToFirst].Text, mList[mEarlier].StartPos)]);
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
      cTexts[TExpressionsText.SelfCompare].Fmt([Display(ANode[0]), mOutcome]), TRuleConfidence.High);
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

{ TStringIndexBaseRule }

function TStringIndexBaseRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cStringIndexBaseRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.IndexTitle].Text);
end;

class function TStringIndexBaseRule.IsStringType(const AType: string): Boolean;
var
  mName: string;
begin
  mName := LowerCase(Trim(AType));
  if Pos('[', mName) > 0 then
  begin
    mName := Trim(Copy(mName, 1, Pos('[', mName) - 1));
  end;
  Result := MatchText(mName, ['string', 'unicodestring', 'ansistring', 'widestring', 'rawbytestring', 'utf8string',
    'shortstring', 'tcaption', 'system.string']);
end;

procedure TStringIndexBaseRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mTypes: TDeclaredTypes;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    mDepth: Integer;
  begin
    mDepth := 0;
    for Result := AOpen to High(mCode) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  // Positionen der Argumente (erstes Token) zwischen AOpen und AClose.
  function Arguments(AOpen, AClose: Integer): TArray<Integer>;
  var
    mPosition, mDepth: Integer;
  begin
    Result := [AOpen + 1];
    mDepth := 0;
    for mPosition := AOpen + 1 to AClose - 1 do
    begin
      if Token(mPosition).IsSymbol('(') or Token(mPosition).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and Token(mPosition).IsSymbol(',') then
      begin
        Result := Result + [mPosition + 1];
      end;
    end;
  end;

  // Ist das Argument ab AFirst bis vor ANext sicher ein String? Deklarierter Typ, Literal oder .Text/.Caption.
  function IsStringArgument(AFirst, ANext: Integer): Boolean;
  var
    mLast: Integer;
  begin
    mLast := ANext - 1;
    if mLast < AFirst then
    begin
      Exit(False);
    end;
    if (AFirst = mLast) and (Token(AFirst).Kind = TPascalTokenKind.StringLiteral) then
    begin
      Exit(True);
    end;
    if (Token(mLast).Kind = TPascalTokenKind.Identifier) and IsSym(mLast - 1, '.') and
      MatchText(Token(mLast).Text, ['Text', 'Caption']) then
    begin
      Exit(True);
    end;
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
    begin
      Inc(AFirst, 2);
    end;
    Result := (AFirst = mLast) and (Token(AFirst).Kind = TPascalTokenKind.Identifier) and
      IsStringType(mTypes.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  // Ist ARoutine der Aufruf der RTL-Routine (ohne Punkt davor bzw. mit System./StrUtils.)?
  function IsRtlCall(APosition: Integer): Boolean;
  begin
    Result := not IsSym(APosition - 1, '.') or IsName(APosition - 2, 'System') or IsName(APosition - 2, 'StrUtils');
  end;

  // Copy(S, 0, N), Delete(S, 0, N), Insert(T, S, 0).
  procedure CheckStartIndex(APosition: Integer);
  var
    mClose, mIndex: Integer;
    mArgs: TArray<Integer>;
    mName, mMessage: string;
    mConfidence: TRuleConfidence;
    mLiteral: TPascalToken;
  begin
    if not IsSym(APosition + 1, '(') or not IsRtlCall(APosition) then
    begin
      Exit;
    end;
    mClose := Closing(APosition + 1);
    if mClose < 0 then
    begin
      Exit;
    end;
    mArgs := Arguments(APosition + 1, mClose);
    mArgs := mArgs + [mClose + 1];
    mName := Token(APosition).Text;
    if SameText(mName, 'Insert') then
    begin
      mIndex := 2;
    end
    else
    begin
      mIndex := 1;
    end;
    if Length(mArgs) < mIndex + 2 then
    begin
      Exit;
    end;
    // Das Argument muss genau "0" sein; der String steht bei Insert an zweiter, sonst an erster Stelle.
    if (mArgs[mIndex + 1] - mArgs[mIndex] <> 2) or (Token(mArgs[mIndex]).Text <> '0') or
      not IsStringArgument(mArgs[mIndex - 1], mArgs[mIndex] - 1) then
    begin
      Exit;
    end;
    mLiteral := Token(mArgs[mIndex]);
    if SameText(mName, 'Delete') then
    begin
      mMessage := cTexts[TExpressionsText.DeleteZero].Text;
      mConfidence := TRuleConfidence.High;
    end
    else
    begin
      mMessage := cTexts[TExpressionsText.StartZero].Fmt([mName]);
      mConfidence := TRuleConfidence.Medium;
    end;
    AReport.Add(TTextRange.Create(mLiteral.StartPos, mLiteral.EndPos), mMessage, mConfidence,
      [TRuleFix.Create(cTexts[TExpressionsText.StartOne].Text, [TRuleEdit.Create(TTextRange.Create(mLiteral.StartPos,
        mLiteral.EndPos), '1')])]);
  end;

  // Rechenoperator (+, -, *, div, mod) beim Code-Token APosition?
  function IsArithmeticAt(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition, '+') or IsSym(APosition, '-') or IsSym(APosition, '*');
    Result := Result or ((APosition >= 0) and (APosition <= High(mCode)) and (Token(APosition).IsKeyword('div') or
      Token(APosition).IsKeyword('mod')));
  end;

  // Vergleich hinter AClose: Operator, optional "-", Zahl. Liefert die Positionen und den Text.
  function Comparison(AAfter: Integer; out AOperator, ALast: Integer; out AText: string): Boolean;
  begin
    AOperator := AAfter;
    ALast := -1;
    AText := '';
    Result := (AAfter <= High(mCode)) and IsComparison(Token(AAfter));
    if not Result then
    begin
      Exit;
    end;
    if IsSym(AAfter + 1, '-') and (AAfter + 2 <= High(mCode)) and
      (Token(AAfter + 2).Kind = TPascalTokenKind.Number) then
    begin
      ALast := AAfter + 2;
      AText := Token(AAfter).Text + '-' + Token(AAfter + 2).Text;
    end
    else if (AAfter + 1 <= High(mCode)) and (Token(AAfter + 1).Kind = TPascalTokenKind.Number) then
    begin
      ALast := AAfter + 1;
      AText := Token(AAfter).Text + Token(AAfter + 1).Text;
    end;
    // "Pos(…) > 1 + X" vergleicht mit einem anderen Wert.
    Result := (ALast >= 0) and not IsArithmeticAt(ALast + 1);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := SourceText(AContext.Text, mTokens, mCode[AFirst], mCode[ALast]);
  end;

  // Steht vor APosition ein Rechenoperator ("X + Pos(…) > 0")? Dann gilt der Vergleich der Summe.
  function InArithmetic(APosition: Integer): Boolean;
  begin
    if IsSym(APosition - 1, '.') then
    begin
      Dec(APosition, 2);
    end;
    Result := IsArithmeticAt(APosition - 1);
  end;

  procedure ReportComparison(AOperator, ALast: Integer; const AMessage, AReplacement: string;
    AConfidence: TRuleConfidence);
  var
    mRange: TTextRange;
  begin
    mRange := TTextRange.Create(Token(AOperator).StartPos, Token(ALast).EndPos);
    AReport.Add(mRange, AMessage, AConfidence, [TRuleFix.Create(cTexts[TExpressionsText.FixComparison].Fmt(
      [AReplacement]), [TRuleEdit.Create(mRange, AReplacement)])]);
  end;

  // Pos(…) > -1, >= 0, <> -1 (immer wahr), = -1, < 0 (nie wahr).
  procedure CheckPos(APosition: Integer);
  var
    mClose, mOperator, mLast: Integer;
    mCompare, mName: string;
  begin
    if not IsSym(APosition + 1, '(') or not IsRtlCall(APosition) or InArithmetic(APosition) then
    begin
      Exit;
    end;
    mClose := Closing(APosition + 1);
    // "Pos(…) > -1", aber nicht "Pos(…) - 1 > 0" oder "X.Pos".
    if (mClose < 0) or not Comparison(mClose + 1, mOperator, mLast, mCompare) then
    begin
      Exit;
    end;
    mName := Token(APosition).Text;
    if (mCompare = '>-1') or (mCompare = '>=0') or (mCompare = '<>-1') then
    begin
      ReportComparison(mOperator, mLast, cTexts[TExpressionsText.AlwaysTrue].Fmt(
        [mName, TextOf(mOperator, mLast)]), '> 0', TRuleConfidence.High);
    end
    else if (mCompare = '=-1') or (mCompare = '<0') or (mCompare = '<=-1') then
    begin
      ReportComparison(mOperator, mLast, cTexts[TExpressionsText.NeverTrue].Fmt(
        [mName, TextOf(mOperator, mLast)]), '= 0', TRuleConfidence.High);
    end;
  end;

  // S.IndexOf(…) > 0 bzw. >= 1 übersieht den Treffer am Anfang; < 1 bzw. <= 0 zählt ihn als "nicht gefunden".
  procedure CheckIndexOf(APosition: Integer);
  var
    mClose, mOperator, mLast: Integer;
    mCompare, mName: string;
  begin
    if not IsSym(APosition - 1, '.') or not IsSym(APosition + 1, '(') then
    begin
      Exit;
    end;
    mClose := Closing(APosition + 1);
    if (mClose < 0) or not Comparison(mClose + 1, mOperator, mLast, mCompare) then
    begin
      Exit;
    end;
    mName := Token(APosition).Text;
    if (mCompare = '>0') or (mCompare = '>=1') then
    begin
      ReportComparison(mOperator, mLast, cTexts[TExpressionsText.MissesFirst].Fmt([mName, TextOf(mOperator, mLast)]),
        '>= 0',
        TRuleConfidence.Medium);
    end
    else if (mCompare = '<1') or (mCompare = '<=0') then
    begin
      ReportComparison(mOperator, mLast, cTexts[TExpressionsText.FirstNotFound].Fmt([mName, TextOf(mOperator, mLast)]),
        '< 0',
        TRuleConfidence.Medium);
    end;
  end;

var
  mIndex, mPosition: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mPosition := 0 to High(mCode) do
    begin
      if Token(mPosition).Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      if MatchText(Token(mPosition).Text, ['Copy', 'Delete', 'Insert']) then
      begin
        CheckStartIndex(mPosition);
      end
      else if MatchText(Token(mPosition).Text, ['Pos', 'PosEx', 'AnsiPos']) then
      begin
        CheckPos(mPosition);
      end
      // LastIndexOf(…) > 0 heißt meist bewusst "Trenner nicht am Anfang" (Name.LastIndexOf('.') > 0).
      else if MatchText(Token(mPosition).Text, ['IndexOf', 'IndexOfAny']) then
      begin
        CheckIndexOf(mPosition);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TNullCompareRule }

function TNullCompareRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cNullCompareRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.NullTitle].Text);
end;

class function TNullCompareRule.IsDataType(const AType: string): Boolean;
var
  mName: string;
begin
  mName := Copy(Trim(AType), LastDelimiter('.', Trim(AType)) + 1, MaxInt);
  Result := (Length(mName) > 1) and (mName[1] = 'T') and (EndsText('Field', mName) or EndsText('Param', mName));
end;

procedure TNullCompareRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mCode: TArray<Integer>;
  mTypes: TDeclaredTypes;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsKey(APosition: Integer; const AKeyword: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsKeyword(AKeyword);
  end;

  function IsWord(APosition: Integer): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := IsWord(APosition) and SameText(Token(APosition).Text, AName);
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := Copy(AContext.Text, Token(AFirst).Offset + 1,
      Token(ALast).Offset + Length(Token(ALast).Text) - Token(AFirst).Offset);
  end;

  // Position vor der öffnenden Klammer zur schließenden bei APosition; -1, wenn keine passt.
  function BeforeBrackets(APosition: Integer): Integer;
  var
    mDepth: Integer;
  begin
    Result := APosition;
    mDepth := 0;
    repeat
      if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Dec(mDepth);
      end;
      Dec(Result);
    until (mDepth = 0) or (Result < 0);
  end;

  // Position hinter der schließenden Klammer zur öffnenden bei APosition; -1, wenn keine passt.
  function AfterBrackets(APosition: Integer): Integer;
  var
    mDepth: Integer;
  begin
    Result := APosition;
    mDepth := 0;
    repeat
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(mDepth);
      end;
      Inc(Result);
    until (mDepth = 0) or (Result > High(mCode));
    if mDepth <> 0 then
    begin
      Result := -1;
    end;
  end;

  // Erstes Token der Kette (A, A.B, A(…), A[…]), die bei ALast endet; -1 bei anderen Ausdrücken.
  function ChainStart(ALast: Integer): Integer;
  var
    mPosition: Integer;
  begin
    Result := -1;
    mPosition := ALast;
    while mPosition >= 0 do
    begin
      if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        mPosition := BeforeBrackets(mPosition);
      end;
      if (mPosition < 0) or not IsWord(mPosition) then
      begin
        Exit;
      end;
      if not IsSym(mPosition - 1, '.') then
      begin
        Exit(mPosition);
      end;
      Dec(mPosition, 2);
    end;
  end;

  // Letztes Token der Kette ab AFirst; -1, wenn dort keine beginnt.
  function ChainEnd(AFirst: Integer): Integer;
  var
    mPosition: Integer;
  begin
    mPosition := AFirst;
    while IsWord(mPosition) do
    begin
      Result := mPosition;
      Inc(mPosition);
      while IsSym(mPosition, '(') or IsSym(mPosition, '[') do
      begin
        mPosition := AfterBrackets(mPosition);
        if mPosition < 0 then
        begin
          Exit(-1);
        end;
        Result := mPosition - 1;
      end;
      if not IsSym(mPosition, '.') then
      begin
        Exit;
      end;
      Inc(mPosition);
    end;
    Result := -1;
  end;

  // Vor dem Vergleich: Anfang einer Bedingung oder eines Arguments (sonst bindet ein Operator anders).
  function OpensExpression(APosition: Integer): Boolean;
  begin
    Result := IsSym(APosition, '(') or IsSym(APosition, ',') or IsSym(APosition, ':=') or IsKey(APosition, 'if') or
      IsKey(APosition, 'while') or IsKey(APosition, 'until') or IsKey(APosition, 'not');
  end;

  // Nach dem Vergleich: Ende der Bedingung oder des Arguments.
  function ClosesExpression(APosition: Integer): Boolean;
  begin
    Result := (APosition > High(mCode)) or IsSym(APosition, ')') or IsSym(APosition, ',') or
      IsSym(APosition, ';') or IsKey(APosition, 'then') or IsKey(APosition, 'do') or IsKey(APosition, 'else') or
      IsKey(APosition, 'end');
  end;

  // Ist die Kette AFirst..ALast "X.Value" auf einem Feld oder Parameter? ABase liefert X.
  function DataValue(AFirst, ALast: Integer; out ABase: string): Boolean;
  var
    mPosition: Integer;
  begin
    Result := False;
    if (ALast - AFirst < 2) or not IsName(ALast, 'Value') or not IsSym(ALast - 1, '.') then
    begin
      Exit;
    end;
    ABase := TextOf(AFirst, ALast - 2);
    // FieldByName('…'), FindField, Fields[…], ParamByName, Params[…] in der Kette.
    for mPosition := AFirst to ALast - 2 do
    begin
      if IsWord(mPosition) and (MatchText(Token(mPosition).Text, ['FieldByName', 'FindField', 'ParamByName',
        'FindParam']) or (MatchText(Token(mPosition).Text, ['Fields', 'Params']) and IsSym(mPosition + 1, '['))) then
      begin
        Exit(True);
      end;
    end;
    // Feld mit deklariertem Typ TStringField, TIntegerField, TParam …
    Result := (ALast - 2 = AFirst) and IsDataType(mTypes.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  procedure ReportAt(AFirst, ALast, AOperator, AExprFirst, AExprLast: Integer);
  var
    mBase, mReplacement, mMessage, mPrefix: string;
  begin
    if Token(AOperator).IsSymbol('<>') then
    begin
      mPrefix := 'not ';
    end
    else
    begin
      mPrefix := '';
    end;
    if DataValue(AExprFirst, AExprLast, mBase) then
    begin
      mReplacement := mPrefix + mBase + '.IsNull';
      mMessage := cTexts[TExpressionsText.NullField].Text;
    end
    else
    begin
      mReplacement := mPrefix + 'VarIsNull(' + TextOf(AExprFirst, AExprLast) + ')';
      mMessage := cTexts[TExpressionsText.NullVariant].Text;
    end;
    // "not X = Null" bindet als "(not X) = Null": dann keine Korrektur, die Bedeutung ist unklar.
    if IsKey(AFirst - 1, 'not') then
    begin
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), mMessage);
    end
    else
    begin
      AReport.Add(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), mMessage,
        [TRuleFix.Create(cTexts[TExpressionsText.ReplaceWith].Fmt([mReplacement]),
        [TRuleEdit.Create(TTextRange.Create(Token(AFirst).StartPos, Token(ALast).EndPos), mReplacement)])]);
    end;
  end;

  procedure CheckAt(APosition: Integer);
  var
    mFirst, mLast: Integer;
  begin
    // X = Null bzw. X <> Null
    if IsSym(APosition - 1, '=') or IsSym(APosition - 1, '<>') then
    begin
      mFirst := ChainStart(APosition - 2);
      if (mFirst >= 0) and OpensExpression(mFirst - 1) and ClosesExpression(APosition + 1) then
      begin
        ReportAt(mFirst, APosition, APosition - 1, mFirst, APosition - 2);
      end;
    end
    // Null = X bzw. Null <> X
    else if (IsSym(APosition + 1, '=') or IsSym(APosition + 1, '<>')) and OpensExpression(APosition - 1) then
    begin
      mLast := ChainEnd(APosition + 2);
      if (mLast >= 0) and ClosesExpression(mLast + 1) then
      begin
        ReportAt(APosition, mLast, APosition + 1, APosition + 2, mLast);
      end;
    end;
  end;

var
  mIndex, mPosition: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'Null') then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mPosition := 0 to High(mCode) do
    begin
      // Null als Wert: nicht Teil einer Kette (X.Null) und kein Aufruf.
      if IsName(mPosition, 'Null') and not IsSym(mPosition - 1, '.') and not IsSym(mPosition + 1, '.') and
        not IsSym(mPosition + 1, '(') then
      begin
        CheckAt(mPosition);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TPosArgumentsSwappedRule }

function TPosArgumentsSwappedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPosArgumentsSwappedRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.SwappedTitle].Text);
end;

class function TPosArgumentsSwappedRule.LiteralLength(const ALiteral: string): Integer;
begin
  Result := PascalLiteralLength(ALiteral);
end;

procedure TPosArgumentsSwappedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mCode: TArray<Integer>;
  mTypes: TDeclaredTypes;
  mMaxLength: Integer;

  function Token(APosition: Integer): TPascalToken;
  begin
    Result := mTokens[mCode[APosition]];
  end;

  function IsSym(APosition: Integer; const ASymbol: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and Token(APosition).IsSymbol(ASymbol);
  end;

  function IsName(APosition: Integer; const AName: string): Boolean;
  begin
    Result := (APosition >= 0) and (APosition <= High(mCode)) and
      (Token(APosition).Kind = TPascalTokenKind.Identifier) and SameText(Token(APosition).Text, AName);
  end;

  function Closing(AOpen: Integer): Integer;
  var
    mDepth: Integer;
  begin
    mDepth := 0;
    for Result := AOpen to High(mCode) do
    begin
      if Token(Result).IsSymbol('(') or Token(Result).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(Result).IsSymbol(')') or Token(Result).IsSymbol(']') then
      begin
        Dec(mDepth);
        if mDepth = 0 then
        begin
          Exit;
        end;
      end;
    end;
    Result := -1;
  end;

  // Erstes Token jedes Arguments zwischen AOpen und AClose, dazu AClose + 1 als Ende des letzten.
  function Arguments(AOpen, AClose: Integer): TArray<Integer>;
  var
    mPosition, mDepth: Integer;
  begin
    Result := [AOpen + 1];
    mDepth := 0;
    for mPosition := AOpen + 1 to AClose - 1 do
    begin
      if Token(mPosition).IsSymbol('(') or Token(mPosition).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and Token(mPosition).IsSymbol(',') then
      begin
        Result := Result + [mPosition + 1];
      end;
    end;
    Result := Result + [AClose + 1];
  end;

  function TextOf(AFirst, ALast: Integer): string;
  begin
    Result := SourceText(AContext.Text, mTokens, mCode[AFirst], mCode[ALast]);
  end;

  // Zeichenzahl des Literals AFirst..ALast (nur String- und Zeichenliterale, keine mehrzeiligen); -1 sonst.
  function Literal(AFirst, ALast: Integer): Integer;
  var
    mPosition: Integer;
    mText: string;
  begin
    if ALast < AFirst then
    begin
      Exit(-1);
    end;
    mText := '';
    for mPosition := AFirst to ALast do
    begin
      if not (Token(mPosition).Kind in [TPascalTokenKind.StringLiteral, TPascalTokenKind.CharLiteral]) or
        (Pos(#10, Token(mPosition).Text) > 0) then
      begin
        Exit(-1);
      end;
      mText := mText + Token(mPosition).Text;
    end;
    Result := LiteralLength(mText);
  end;

  // Teil AFirst..ALast ohne + auf oberster Ebene: deklarierter String-Typ, .Text/.Caption oder Aufruf einer
  // String-Funktion der RTL.
  function IsStringPart(AFirst, ALast: Integer): Boolean;
  begin
    if ALast < AFirst then
    begin
      Exit(False);
    end;
    if (Token(ALast).Kind = TPascalTokenKind.Identifier) and IsSym(ALast - 1, '.') and
      MatchText(Token(ALast).Text, ['Text', 'Caption']) then
    begin
      Exit(True);
    end;
    if (Token(AFirst).Kind = TPascalTokenKind.Identifier) and IsSym(AFirst + 1, '(') and
      not IsSym(AFirst - 1, '.') and MatchText(Token(AFirst).Text, ['Trim', 'TrimLeft', 'TrimRight', 'UpperCase',
      'LowerCase', 'AnsiUpperCase', 'AnsiLowerCase', 'IntToStr', 'Format', 'QuotedStr', 'StringReplace',
      'ExtractFileName', 'ExtractFilePath', 'ExtractFileExt', 'ChangeFileExt', 'IncludeTrailingPathDelimiter',
      'ExcludeTrailingPathDelimiter', 'LeftStr', 'RightStr', 'MidStr', 'ReverseString', 'DupeString']) then
    begin
      Exit(Closing(AFirst + 1) = ALast);
    end;
    if IsName(AFirst, 'Self') and IsSym(AFirst + 1, '.') then
    begin
      Inc(AFirst, 2);
    end;
    Result := (AFirst = ALast) and (Token(AFirst).Kind = TPascalTokenKind.Identifier) and
      TStringIndexBaseRule.IsStringType(mTypes.DeclaredType(Token(AFirst).Text, Token(AFirst).StartPos));
  end;

  // Erstes + auf oberster Klammerebene in AFirst..ALast; -1 ohne.
  function TopLevelPlus(AFirst, ALast: Integer): Integer;
  var
    mPosition, mDepth: Integer;
  begin
    Result := -1;
    mDepth := 0;
    mPosition := AFirst;
    while (Result < 0) and (mPosition <= ALast) do
    begin
      if Token(mPosition).IsSymbol('(') or Token(mPosition).IsSymbol('[') then
      begin
        Inc(mDepth);
      end
      else if Token(mPosition).IsSymbol(')') or Token(mPosition).IsSymbol(']') then
      begin
        Dec(mDepth);
      end
      else if (mDepth = 0) and Token(mPosition).IsSymbol('+') then
      begin
        Result := mPosition;
      end;
      Inc(mPosition);
    end;
  end;

  // Ist das Argument AFirst..ALast sicher ein String und kein Zeichen? Deklarierter String-Typ, .Text/.Caption,
  // Aufruf einer String-Funktion der RTL oder Verkettung mit einem String-Teil. Iterativ (tiefe Bäume sprengen den Stapel nicht): die
  // Teile einer langen Verkettung nacheinander statt einer Rekursionsebene je +.
  function IsStringArgument(AFirst, ALast: Integer): Boolean;
  var
    mStart, mPlus: Integer;
  begin
    Result := False;
    mStart := AFirst;
    while mStart <= ALast do
    begin
      mPlus := TopLevelPlus(mStart, ALast);
      if mPlus < 0 then
      begin
        Exit(IsStringPart(mStart, ALast));
      end;
      // Zeichen + Zeichen ist schon ein String, Zahl + Zahl nicht: ein Teil muss sicher String sein.
      if IsStringPart(mStart, mPlus - 1) or (Literal(mStart, mPlus - 1) >= 2) or (Literal(mPlus + 1, ALast) >= 2) then
      begin
        Exit(True);
      end;
      mStart := mPlus + 1;
    end;
  end;

  // ATextFirst: ContainsText(Text, Teil), sonst Pos(Teil, Text). Vertauscht steht an der Stelle des Textes ein
  // kurzes Literal und an der Stelle des Teils ein String.
  procedure CheckCall(APosition: Integer; ATextFirst: Boolean);
  var
    mClose, mTextArg, mPartArg, mSize: Integer;
    mArgs: TArray<Integer>;
    mName, mMessage, mBetween: string;
    mRange: TTextRange;
  begin
    // Nur die RTL-Routine: ohne Punkt davor oder mit System. bzw. StrUtils. (auch System.StrUtils.).
    if not IsSym(APosition + 1, '(') or (IsSym(APosition - 1, '.') and not IsName(APosition - 2, 'System') and
      not IsName(APosition - 2, 'StrUtils')) then
    begin
      Exit;
    end;
    mClose := Closing(APosition + 1);
    if mClose < 0 then
    begin
      Exit;
    end;
    mArgs := Arguments(APosition + 1, mClose);
    if Length(mArgs) < 3 then
    begin
      Exit;
    end;
    if ATextFirst then
    begin
      mTextArg := 0;
      mPartArg := 1;
    end
    else
    begin
      mTextArg := 1;
      mPartArg := 0;
    end;
    mSize := Literal(mArgs[mTextArg], mArgs[mTextArg + 1] - 2);
    if (mSize < 1) or (mSize > mMaxLength) or (Literal(mArgs[mPartArg], mArgs[mPartArg + 1] - 2) >= 0) or
      not IsStringArgument(mArgs[mPartArg], mArgs[mPartArg + 1] - 2) then
    begin
      Exit;
    end;
    mName := Token(APosition).Text;
    if ATextFirst then
    begin
      mMessage := cTexts[TExpressionsText.SwappedText].Text;
    end
    else
    begin
      mMessage := cTexts[TExpressionsText.SwappedPart].Text;
    end;
    mMessage := Format(mMessage, [mName, TextOf(mArgs[mTextArg], mArgs[mTextArg + 1] - 2),
      TextOf(mArgs[mPartArg], mArgs[mPartArg + 1] - 2)]);
    // Eine Änderung über beide Argumente (ein Undo-Schritt); Komma, Leerraum und Kommentare dazwischen bleiben.
    mBetween := Copy(AContext.Text, mTokens[mCode[mArgs[1] - 2]].Offset + Length(mTokens[mCode[mArgs[1] - 2]].Text) + 1,
      mTokens[mCode[mArgs[1]]].Offset - mTokens[mCode[mArgs[1] - 2]].Offset -
        Length(mTokens[mCode[mArgs[1] - 2]].Text));
    mRange := TTextRange.Create(Token(mArgs[0]).StartPos, Token(mArgs[2] - 2).EndPos);
    AReport.Add(mRange, mMessage, TRuleConfidence.Medium, [TRuleFix.Create(cTexts[TExpressionsText.SwapArguments].Text,
      [TRuleEdit.Create(mRange, TextOf(mArgs[1], mArgs[2] - 2) + mBetween + TextOf(mArgs[0], mArgs[1] - 2))])]);
  end;

var
  mIndex, mPosition: Integer;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mMaxLength := TRuleOptions.Int(AContext.Options, 'maxLiteralLength', 3);
  mTokens := AContext.Tree.Tokens;
  mCode := nil;
  for mIndex := 0 to High(mTokens) do
  begin
    if not IsTrivia(mTokens[mIndex]) then
    begin
      mCode := mCode + [mIndex];
    end;
  end;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mPosition := 0 to High(mCode) do
    begin
      if Token(mPosition).Kind <> TPascalTokenKind.Identifier then
      begin
        Continue;
      end;
      if MatchText(Token(mPosition).Text, ['Pos', 'PosEx', 'AnsiPos', 'StartsText', 'StartsStr', 'EndsText',
        'EndsStr', 'AnsiStartsText', 'AnsiStartsStr', 'AnsiEndsText', 'AnsiEndsStr']) then
      begin
        CheckCall(mPosition, False);
      end
      else if MatchText(Token(mPosition).Text, ['ContainsText', 'ContainsStr', 'AnsiContainsText',
        'AnsiContainsStr']) then
      begin
        CheckCall(mPosition, True);
      end;
    end;
  finally
    mTypes.Free;
  end;
end;

{ TIntegerDivisionToFloatRule }

function TIntegerDivisionToFloatRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cIntegerDivisionToFloatRuleId, TRuleSeverity.Warning,
    cTexts[TExpressionsText.DivTitle].Text);
end;

class function TIntegerDivisionToFloatRule.IsFractional(const AType: string): Boolean;
begin
  // TDateTime, TDate und TTime nicht: A div B als ganze Tage ist dort meist gewollt; Comp ist ganzzahlig.
  Result := MatchText(Trim(AType), ['Single', 'Double', 'Extended', 'Real', 'Real48', 'Float32', 'Float64',
    'Currency', 'System.Single', 'System.Double', 'System.Extended', 'System.Currency']);
end;

procedure TIntegerDivisionToFloatRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TArray<TPascalToken>;
  mTypes: TDeclaredTypes;

  // Typ des Funktionsergebnisses der Routine um ANode; '' ohne Funktion.
  function ResultType(ANode: TSyntaxNode): string;
  var
    mHeader, mReference: TSyntaxNode;
  begin
    Result := '';
    while (ANode <> nil) and not (ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
    begin
      ANode := ANode.Parent;
    end;
    if (ANode = nil) or (ANode.Kind <> TSyntaxKind.RoutineDecl) then
    begin
      Exit;
    end;
    mHeader := ANode.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader = nil then
    begin
      Exit;
    end;
    mReference := mHeader.FindChild(TSyntaxKind.TypeReference);
    if mReference <> nil then
    begin
      Result := Trim(Copy(AContext.Text, mReference.StartOffset + 1, mReference.EndOffset - mReference.StartOffset));
    end;
  end;

  // Steht ANode in einem with-Block? Dann kann der Name ein Feld des with-Objekts sein.
  function InWith(ANode: TSyntaxNode): Boolean;
  begin
    while ANode <> nil do
    begin
      if ANode.Kind = TSyntaxKind.WithStatement then
      begin
        Exit(True);
      end;
      ANode := ANode.Parent;
    end;
    Result := False;
  end;

  // Das Schlüsselwort div zwischen den Operanden von ADivision.
  function DivToken(ADivision: TSyntaxNode; out AToken: TPascalToken): Boolean;
  var
    mIndex: Integer;
  begin
    for mIndex := TSyntaxTree.FirstTokenOf(mTokens, ADivision[0].EndOffset) to High(mTokens) do
    begin
      if (mTokens[mIndex].Offset >= ADivision[0].EndOffset) and (mTokens[mIndex].Offset < ADivision[1].StartOffset) and
        mTokens[mIndex].IsKeyword('div') then
      begin
        AToken := mTokens[mIndex];
        Exit(True);
      end;
    end;
    Result := False;
  end;

  // Trunc(X), Round(X), Floor(X), Ceil(X): Wer Gleitkommazahlen ausdrücklich in Ganzzahlen wandelt und dann
  // mit div teilt, will die ganzzahlige Division (Trunc(A) div Trunc(B) im Präprozessor).
  function IsExplicitInteger(AOperand: TSyntaxNode): Boolean;
  begin
    while (AOperand.Kind = TSyntaxKind.ParenExpr) and (AOperand.ChildCount = 1) do
    begin
      AOperand := AOperand[0];
    end;
    Result := (AOperand.Kind = TSyntaxKind.Call) and (AOperand.ChildCount > 0) and
      (AOperand[0].Kind = TSyntaxKind.Identifier) and MatchText(AOperand[0].Name, ['Trunc', 'Round', 'Floor', 'Ceil']);
  end;

  // Meldet die Division ANode, wenn keiner der Operanden ausdrücklich ganzzahlig gewandelt ist.
  procedure CheckDiv(ANode: TSyntaxNode; const ATarget, AType: string);
  var
    mToken: TPascalToken;
  begin
    if IsExplicitInteger(ANode[0]) or IsExplicitInteger(ANode[1]) or not DivToken(ANode, mToken) then
    begin
      Exit;
    end;
    AReport.Add(TTextRange.Create(ANode.StartPos, ANode.EndPos),
      cTexts[TExpressionsText.DivLoses].Fmt([ATarget, AType]),
      TRuleConfidence.High, [TRuleFix.Create(cTexts[TExpressionsText.ReplaceDiv].Text,
      [TRuleEdit.Create(TTextRange.Create(mToken.StartPos, mToken.EndPos), '/')])]);
  end;

  // Führt das Ergebnis von ANode ungekürzt weiter: Klammern, Vorzeichen und + - * /?
  function PassesThrough(ANode: TSyntaxNode): Boolean;
  begin
    case ANode.Kind of
      TSyntaxKind.ParenExpr:
        Result := True;
      TSyntaxKind.UnaryExpr:
        Result := (ANode.Name = '-') or (ANode.Name = '+');
      TSyntaxKind.BinaryExpr:
        Result := MatchStr(ANode.Name, ['+', '-', '*', '/']);
    else
      Result := False;
    end;
  end;

  // div in AExpression, deren Ergebnis ungekürzt in die Gleitkommazahl fließt: durch Klammern, Vorzeichen und
  // + - * / hindurch, nicht in Aufrufe, Indizes, mod oder Vergleiche.
  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Search(AExpression: TSyntaxNode; const ATarget, AType: string);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(AExpression);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and SameText(mNode.Name, 'div') and (mNode.ChildCount = 2) then
        begin
          CheckDiv(mNode, ATarget, AType);
        end
        else if PassesThrough(mNode) then
        begin
          for mIndex := mNode.ChildCount - 1 downto 0 do
          begin
            mPending.Push(mNode[mIndex]);
          end;
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    mTarget: TSyntaxNode;
    mName, mTypeName: string;
  begin
    if (ANode.ChildCount <> 2) or InWith(ANode) then
    begin
      Exit;
    end;
    mTarget := ANode[0];
    // Self.X wie X.
    if (mTarget.Kind = TSyntaxKind.MemberAccess) and (mTarget.ChildCount = 1) and
      (mTarget[0].Kind = TSyntaxKind.Identifier) and SameText(mTarget[0].Name, 'Self') then
    begin
      mName := mTarget.Name;
    end
    else if mTarget.Kind = TSyntaxKind.Identifier then
    begin
      mName := mTarget.Name;
    end
    else
    begin
      Exit;
    end;
    if SameText(mName, 'Result') then
    begin
      mTypeName := mTypes.DeclaredType(mName, mTarget.StartPos);
      if mTypeName = '' then
      begin
        mTypeName := ResultType(ANode);
      end;
    end
    else
    begin
      mTypeName := mTypes.DeclaredType(mName, mTarget.StartPos);
    end;
    if IsFractional(mTypeName) then
    begin
      Search(ANode[1], mName, mTypeName);
    end;
  end;

  // var Schnitt: Double := Summe div Anzahl;
  procedure CheckInlineVar(ANode: TSyntaxNode);
  var
    mIndex: Integer;
    mTypeName: string;
  begin
    if (ANode.ChildCount <> 2) or (Pos(',', ANode.Name) > 0) or (ANode[0].Kind <> TSyntaxKind.TypeReference) then
    begin
      Exit;
    end;
    mTypeName := Trim(Copy(AContext.Text, ANode[0].StartOffset + 1, ANode[0].EndOffset - ANode[0].StartOffset));
    if IsFractional(mTypeName) then
    begin
      for mIndex := 1 to ANode.ChildCount - 1 do
      begin
        Search(ANode[mIndex], Trim(ANode.Name), mTypeName);
      end;
    end;
  end;

  // Iterativ (tiefe Bäume sprengen den Stapel nicht).
  procedure Walk(ARoot: TSyntaxNode);
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
        if mNode.Kind = TSyntaxKind.AssignStatement then
        begin
          CheckAssignment(mNode);
        end
        else if mNode.Kind = TSyntaxKind.InlineVar then
        begin
          CheckInlineVar(mNode);
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
    Walk(AContext.Tree.Root);
  finally
    mTypes.Free;
  end;
end;

{ TConditionalExpressionVersionRule }

type
  TOffsetRange = record
    Start: Integer;
    Stop: Integer;
  end;

  TVersionBlock = record
    Start: Integer;
    Version: Boolean;
  end;

function TConditionalExpressionVersionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cConditionalExpressionVersionRuleId, TRuleSeverity.Error,
    cTexts[TExpressionsText.ConditionalTitle].Text);
end;

class function TConditionalExpressionVersionRule.IsVersionDirective(const ADirective: string): Boolean;
var
  mText: string;
  mIndex: Integer;
begin
  mText := UpperCase(ADirective);
  Result := ContainsStr(mText, 'COMPILERVERSION') or ContainsStr(mText, 'RTLVERSION') or
    ContainsStr(mText, 'DECLARED');
  // VER370, VER360 …
  mIndex := Pos('VER', mText);
  while not Result and (mIndex > 0) do
  begin
    Result := (mIndex + 3 <= Length(mText)) and CharInSet(mText[mIndex + 3], ['0'..'9']) and
      ((mIndex = 1) or not CharInSet(mText[mIndex - 1], ['A'..'Z', '0'..'9', '_']));
    mIndex := PosEx('VER', mText, mIndex + 3);
  end;
end;

/// <summary>Offsetbereiche der {$IF…}-Blöcke (alle Zweige), die nach der Compilerversion fragen.</summary>
function VersionBlocks(const ATokens: TArray<TPascalToken>): TArray<TOffsetRange>;
var
  mStack: TArray<TVersionBlock>;
  mBlock: TVersionBlock;
  mRange: TOffsetRange;
  mToken: TPascalToken;
  mName: string;
begin
  Result := nil;
  mStack := nil;
  for mToken in ATokens do
  begin
    if mToken.Kind <> TPascalTokenKind.Directive then
    begin
      Continue;
    end;
    mName := TPascalLexer.DirectiveName(mToken.Text);
    if (mName = 'IF') or (mName = 'IFDEF') or (mName = 'IFNDEF') or (mName = 'IFOPT') then
    begin
      mBlock.Start := mToken.Offset;
      mBlock.Version := TConditionalExpressionVersionRule.IsVersionDirective(mToken.Text);
      mStack := mStack + [mBlock];
    end
    else if (mName = 'ELSEIF') and (mStack <> nil) and not mStack[High(mStack)].Version and
      TConditionalExpressionVersionRule.IsVersionDirective(mToken.Text) then
    begin
      mStack[High(mStack)].Version := True;
      mStack[High(mStack)].Start := mToken.Offset;
    end
    else if ((mName = 'ENDIF') or (mName = 'IFEND')) and (mStack <> nil) then
    begin
      if mStack[High(mStack)].Version then
      begin
        mRange.Start := mStack[High(mStack)].Start;
        mRange.Stop := mToken.Offset + Length(mToken.Text);
        Result := Result + [mRange];
      end;
      SetLength(mStack, Length(mStack) - 1);
    end;
  end;
end;

procedure TConditionalExpressionVersionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mBlocks: TArray<TOffsetRange>;
  mFound: TArray<TSyntaxNode>;
  mNode: TSyntaxNode;
  mLayout: TStatementLayout;
  mRewrite: TStatementRewrite;
  mFixes: TArray<TRuleFix>;
  mMessage: string;

  function Guarded(AOffset: Integer): Boolean;
  var
    mRange: TOffsetRange;
  begin
    Result := False;
    for mRange in mBlocks do
    begin
      if (AOffset >= mRange.Start) and (AOffset < mRange.Stop) then
      begin
        Exit(True);
      end;
    end;
  end;

begin
  // Ohne bekannte Version (IsAvailable liefert dann True) oder ab Delphi 13 still.
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    TLanguageFeatures.IsAvailable(TLanguageFeature.IfExpression, AContext.DelphiVersion) then
  begin
    Exit;
  end;
  mFound := nil;
  AContext.Tree.Root.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.IfExpr) and (TConditionalExpression.Outermost(ANode) = ANode) then
      begin
        mFound := mFound + [ANode];
      end;
    end);
  if mFound = nil then
  begin
    Exit;
  end;
  mBlocks := VersionBlocks(AContext.Tree.Tokens);
  mLayout := TStatementLayout.Create('', TRoutineBody.IndentUnit(AContext.Formatting),
    TTextLines.LineBreakOf(AContext.Text));
  mMessage := cTexts[TExpressionsText.ConditionalVersion].Fmt(
    [TLanguageFeatures.ProductName(TLanguageFeatures.MinimumVersion(TLanguageFeature.IfExpression)),
    TLanguageFeatures.ProductName(AContext.DelphiVersion)]);
  for mNode in mFound do
  begin
    if Guarded(mNode.StartOffset) then
    begin
      Continue;
    end;
    mFixes := nil;
    if TConditionalExpression.ToStatement(AContext.Text, AContext.Tree, mNode, mLayout, mRewrite) then
    begin
      mFixes := [TRuleFix.Create(mRewrite.Title, [TRuleEdit.Create(mRewrite.Edit.Range, mRewrite.Edit.NewText)])];
    end;
    AReport.Add(TTextRange.Create(mNode.StartPos, mNode.EndPos), mMessage, TRuleConfidence.High, mFixes);
  end;
end;

procedure RegisterExpressionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TOperatorPrecedenceRule.Create);
  ARegistry.Register(TDuplicateConditionRule.Create);
  ARegistry.Register(TStringIndexBaseRule.Create);
  ARegistry.Register(TNullCompareRule.Create);
  ARegistry.Register(TPosArgumentsSwappedRule.Create);
  ARegistry.Register(TIntegerDivisionToFloatRule.Create);
  ARegistry.Register(TConditionalExpressionVersionRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Expressions', cTexts);

end.
