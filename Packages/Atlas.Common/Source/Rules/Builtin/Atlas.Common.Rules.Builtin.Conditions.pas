unit Atlas.Common.Rules.Builtin.Conditions;

// Bedingungen und Schleifen (#909, Gruppe Fehler finden):
//   constant-condition  Bedingung von if, while oder until steht fest (#1041):
//                       True, False, Vergleiche von Zahlen und untypisierte
//                       Konstanten der Datei, auch über and, or, xor und not;
//                       "X or True" ist immer wahr, "X and False" immer falsch.
//                       while True do und repeat … until False sind gewollte
//                       Endlosschleifen und bleiben still (dafür infinite-loop).
//                       Konstanten aus der Option switchConstants, Konstanten in
//                       einem Zweig von {$IF…} und solche aus anderen Units gelten
//                       als unbekannt. Korrektur bei if: toten Zweig entfernen
//                       bzw. die Bedingung entfernen (Zweig bleibt).
//   infinite-loop       while mit immer wahrer bzw. repeat mit immer falscher
//                       Bedingung ohne Ausgang im Rumpf (#1042): kein Break (in
//                       verschachtelten Schleifen zählt es nicht), Exit, raise,
//                       goto, Halt, Abort oder RunError, kein Aufruf einer
//                       Routine der Datei, die eine Ausnahme auslöst bzw. das
//                       Programm beendet, und keine Prüfung von Terminated (dafür
//                       thread-loop-without-terminated). Anonyme Methoden im
//                       Rumpf zählen nicht. Steht die Schleife im try-Teil eines
//                       try … except derselben Routine, endet sie gewollt über
//                       eine Ausnahme (lesen bis EJsonRpcTransportClosed) und
//                       bleibt still. Aktion: Sprung zum Schleifenkopf.
//   loop-condition-unchanged
//                       Keine Variable der while- bzw. until-Bedingung ändert sich
//                       im Rumpf (#1043): typisch das vergessene Inc(I). Gemeldet
//                       nur, wenn jede Variable der Bedingung eine lokale Variable
//                       bzw. ein Wertparameter der Routine ist und mindestens eine
//                       direkt (nicht nur über X.Eigenschaft) vorkommt. Still bei
//                       Aufrufen in der Bedingung, Feldern, globalen Variablen,
//                       var-/out-Parametern, Terminated, with im Rumpf, Ausgängen
//                       (wie infinite-loop), Warteschleifen (Sleep, ProcessMessages
//                       …), Aufrufen lokaler Routinen und Variablen, die eine
//                       anonyme Methode erfasst. Als Änderung gilt: Zuweisung,
//                       Argument eines Aufrufs (var möglich), X.Methode bzw. jeder
//                       Zugriff X.Name im Rumpf, @X und for X; über X[…] nur, wenn
//                       die Bedingung X[…] liest.
//   redundant-jump      Exit als letzte Anweisung einer Routine bzw. anonymen
//                       Methode und Continue als letzte Anweisung eines
//                       Schleifenrumpfs (#1141, Stil): Sie ändern den Ablauf nicht.
//                       Continue zählt auch im letzten Zweig eines if am Ende des
//                       Rumpfs (then nur ohne else; then Continue else … ist ein
//                       Wächter der Kette) und in begin … end. Still: Exit(Wert), Exit in
//                       inneren Blöcken (if, try, case), Sprünge in try … finally
//                       bzw. try … except, Anweisungen mit Marke und Rümpfe mit
//                       bedingten Direktiven. Korrektur „Anweisung entfernen“,
//                       wenn die Anweisung in einem begin … end steht.
//   loop-runs-at-most-once
//                       Jeder Weg durch den Rumpf einer for-, for-in-, while- oder
//                       repeat-Schleife endet mit Exit, Break, raise, Halt, Abort,
//                       RunError, ExitProcess oder dem Aufruf einer Routine der
//                       Datei, die auf jedem Weg eine Ausnahme auslöst (#1131):
//                       Die Schleife läuft höchstens einmal. Ein Weg zählt als
//                       Sprung bei if mit else und beiden Zweigen, case mit else
//                       und allen Zweigen, try … finally mit try- oder
//                       finally-Teil, try … except mit try-Teil und jedem
//                       Behandler. Still bei
//                       Continue dieser Schleife, goto bzw. Marken und bedingten
//                       Direktiven im Rumpf (der Baum enthält alle Zweige); ein
//                       Break innerer Schleifen zählt nicht, TMonitor.Exit(…)
//                       ist kein Sprung. Option allowFirstElement: for-in, in
//                       dem keine Bedingung die Schleifenvariable liest („erstes
//                       Element holen“), bleibt still. Keine Korrektur, die Absicht ist unklar; steht der
//                       Sprung direkt hinter einem if ohne else, fragt die
//                       Meldung, ob er in den if-Zweig gehört.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

const
  cConstantConditionRuleId = 'constant-condition';
  cInfiniteLoopRuleId = 'infinite-loop';
  cLoopConditionUnchangedRuleId = 'loop-condition-unchanged';
  cRedundantJumpRuleId = 'redundant-jump';
  cLoopRunsAtMostOnceRuleId = 'loop-runs-at-most-once';

type
  TConstantConditionRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TInfiniteLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopConditionUnchangedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRedundantJumpRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopRunsAtMostOnceRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.OrdinalConstants,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Builtin.Conditions.Values,
  Atlas.Common.Rules.Builtin.Conditions.Jumps,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TConditionsText = (ConstantTitle, AlwaysTrue, AlwaysFalse, RemoveCondition, RemoveDeadBranch, InfiniteTitle, NoExit,
    JumpToHead, UnchangedTitle, AndWord, NeverChangedOne, NeverChangedMany, RedundantTitle, RemoveStatement,
    RedundantExit, RedundantContinue, OnceTitle, OfSubject, FirstElement, ExactlyOnce, AtMostOnce, AJump, BelongsInIf);

const
  cTexts: array[TConditionsText] of TAtlasText = (
    (De: 'Bedingung ist immer gleich'; En: 'Condition is always the same'),
    (De: 'Die Bedingung ist immer wahr (%s).'; En: 'The condition is always true (%s).'),
    (De: 'Die Bedingung ist immer falsch (%s).'; En: 'The condition is always false (%s).'),
    (De: 'Bedingung entfernen'; En: 'Remove condition'),
    (De: 'Toten Zweig entfernen'; En: 'Remove dead branch'),
    (De: 'Schleife ohne Ausgang'; En: 'Loop without exit'),
    (De: 'Die Schleife hat keinen Ausgang (kein Break, Exit oder raise).';
     En: 'The loop has no exit (no Break, Exit or raise).'),
    (De: 'Zum Schleifenkopf springen'; En: 'Jump to the loop head'),
    (De: 'Schleifenbedingung ändert sich im Rumpf nie'; En: 'Loop condition never changes in the body'),
    (De: ' und '; En: ' and '),
    (De: ' wird im Rumpf nie verändert; die Schleife endet nicht.';
     En: ' is never changed in the body; the loop does not end.'),
    (De: ' werden im Rumpf nie verändert; die Schleife endet nicht.';
     En: ' are never changed in the body; the loop does not end.'),
    (De: 'Überflüssiges Exit oder Continue'; En: 'Redundant Exit or Continue'),
    (De: 'Anweisung entfernen'; En: 'Remove statement'),
    (De: 'Exit am Ende der Routine ist überflüssig.'; En: 'Exit at the end of the routine is redundant.'),
    (De: 'Continue am Ende des Schleifenrumpfs ist überflüssig.';
     En: 'Continue at the end of the loop body is redundant.'),
    (De: 'Schleife läuft höchstens einmal'; En: 'Loop runs at most once'),
    (De: ' von %s'; En: ' of %s'),
    (De: 'Jeder Durchlauf endet mit %s: Die Schleife prüft nur das erste Element%s.';
     En: 'Every iteration ends with %s: the loop checks only the first element%s.'),
    (De: 'Jeder Durchlauf endet mit %s: Die Schleife läuft genau einmal.';
     En: 'Every iteration ends with %s: the loop runs exactly once.'),
    (De: 'Jeder Durchlauf endet mit %s: Die Schleife läuft höchstens einmal.';
     En: 'Every iteration ends with %s: the loop runs at most once.'),
    (De: 'einem Sprung'; En: 'a jump'),
    (De: ' Gehört %s in den if-Zweig?'; En: ' Does %s belong in the if branch?'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

/// <summary>Dateiname für die Namensauflösung: Pfad, sonst relativer Pfad, sonst Unit-Name.</summary>
function RuleFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

function Unwrapped(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode;
  while (Result <> nil) and (Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1) do
  begin
    Result := Result[0];
  end;
end;

function IsBoolLiteral(ANode: TSyntaxNode; AValue: Boolean): Boolean;
begin
  ANode := Unwrapped(ANode);
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, BoolText(AValue));
end;

{ TConstantConditionRule }

function TConstantConditionRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cConstantConditionRuleId, TRuleSeverity.Warning,
    cTexts[TConditionsText.ConstantTitle].Text);
end;

/// <summary>Text des Knotens; Folgezeilen um die Spalte des Knotens gegenüber AColumn ausgerückt.</summary>
function Outdented(const AText: string; ANode: TSyntaxNode; AColumn: Integer): string;
var
  mLines: TArray<string>;
  mLineBreak: string;
  mIndex, mShift, mRemove: Integer;
begin
  mLines := TTextLines.SplitLines(NodeText(AText, ANode), mLineBreak);
  mShift := ANode.StartPos.Character - AColumn;
  if mShift > 0 then
  begin
    for mIndex := 1 to High(mLines) do
    begin
      mRemove := TTextLines.IndentLength(mLines[mIndex]);
      if mRemove > mShift then
      begin
        mRemove := mShift;
      end;
      mLines[mIndex] := Copy(mLines[mIndex], mRemove + 1, MaxInt);
    end;
  end;
  Result := TTextLines.JoinLines(mLines, mLineBreak);
end;

/// <summary>Bereich, der eine ganze Anweisung entfernt: mit folgendem Semikolon und, wenn sie allein auf ihren
/// Zeilen steht, mit den Zeilen.</summary>
function StatementRemoval(const AText: string; ANode: TSyntaxNode): TTextRange;
var
  mLines: TLineTable;
  mFirst, mLast, mProbe: Integer;
begin
  mLines := TLineTable.Build(AText);
  mFirst := ANode.StartOffset;
  mLast := ANode.EndOffset;
  mProbe := mLast;
  while (mProbe < Length(AText)) and CharInSet(AText[mProbe + 1], [' ', #9]) do
  begin
    Inc(mProbe);
  end;
  if (mProbe < Length(AText)) and (AText[mProbe + 1] = ';') then
  begin
    mLast := mProbe + 1;
  end;
  mProbe := mLast;
  while (mProbe < Length(AText)) and CharInSet(AText[mProbe + 1], [' ', #9]) do
  begin
    Inc(mProbe);
  end;
  if ((mProbe = Length(AText)) or CharInSet(AText[mProbe + 1], [#13, #10])) and
    (Trim(Copy(AText, mLines.LineStart(ANode.StartPos.Line) + 1, mFirst -
      mLines.LineStart(ANode.StartPos.Line))) = '') then
  begin
    mFirst := mLines.LineStart(ANode.StartPos.Line);
    mLast := mLines.LineStart(mLines.PositionAt(mProbe).Line + 1);
    if mLast <= mProbe then
    begin
      mLast := mProbe;
    end;
  end;
  Result := TTextRange.Create(mLines.PositionAt(mFirst), mLines.PositionAt(mLast));
end;

/// <summary>Bedingung einer if-, while- oder repeat-Anweisung; nil bei anderen Knoten.</summary>
function ConditionOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.IfStatement, TSyntaxKind.WhileStatement:
      Result := ANode[0];
    TSyntaxKind.RepeatStatement:
      Result := ANode[ANode.ChildCount - 1];
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>while True do und repeat … until False: gewollte Endlosschleife (infinite-loop prüft den
/// Ausgang).</summary>
function WantedEndless(ANode, ACondition: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.WhileStatement) and IsBoolLiteral(ACondition, True) or
    (ANode.Kind = TSyntaxKind.RepeatStatement) and IsBoolLiteral(ACondition, False);
end;

function ConstantMessage(const AValue: TConstantValue): string;
begin
  if AValue.Bool then
  begin
    Result := cTexts[TConditionsText.AlwaysTrue].Fmt([AValue.Shown]);
  end
  else
  begin
    Result := cTexts[TConditionsText.AlwaysFalse].Fmt([AValue.Shown]);
  end;
end;

procedure TConstantConditionRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mValues: TConditionValues;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mFileName: string;

  procedure ReportIf(ANode: TSyntaxNode; const AValue: TConstantValue);
  var
    mMessage: string;
    mFixes: TArray<TRuleFix>;
    mBranch: TSyntaxNode;
  begin
    mMessage := ConstantMessage(AValue);
    mFixes := nil;
    mBranch := nil;
    if AValue.Bool and (ANode.ChildCount >= 2) then
    begin
      mBranch := ANode[1];
    end
    else if not AValue.Bool and (ANode.ChildCount >= 3) then
    begin
      mBranch := ANode[2];
    end;
    if (mBranch <> nil) and (mBranch.Kind <> TSyntaxKind.EmptyStatement) then
    begin
      if AValue.Bool then
      begin
        mFixes := [TRuleFix.Create(cTexts[TConditionsText.RemoveCondition].Text, [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, mBranch, ANode.StartPos.Character))])];
      end
      else
      begin
        mFixes := [TRuleFix.Create(cTexts[TConditionsText.RemoveDeadBranch].Text, [TRuleEdit.Create(NodeRange(ANode),
          Outdented(AContext.Text, mBranch, ANode.StartPos.Character))])];
      end;
    end
    else if not AValue.Bool then
    begin
      mFixes := [TRuleFix.Create(cTexts[TConditionsText.RemoveDeadBranch].Text,
        [TRuleEdit.Create(StatementRemoval(AContext.Text, ANode),
        '')])];
    end;
    AReport.Add(NodeRange(ANode[0]), mMessage, TRuleConfidence.High, mFixes);
  end;

  procedure CheckCondition(ANode, ACondition: TSyntaxNode);
  var
    mValue: TConstantValue;
  begin
    mValue := mValues.Evaluate(ACondition);
    if (mValue.Kind <> TConstantKind.Bool) or WantedEndless(ANode, ACondition) then
    begin
      Exit;
    end;
    if ANode.Kind = TSyntaxKind.IfStatement then
    begin
      ReportIf(ANode, mValue);
    end
    else
    begin
      AReport.Add(NodeRange(ACondition), ConstantMessage(mValue), TRuleConfidence.High);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mCondition: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mCondition := ConditionOf(mNode);
        if (mCondition <> nil) and not mValues.Conditional(mCondition) then
        begin
          CheckCondition(mNode, mCondition);
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
  mFileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  mValues := TConditionValues.Create(AContext.Tree, AContext.Text, mFileName, mResolver,
    TRuleOptions.Strings(AContext.Options, 'switchConstants', []));
  try
    Visit(AContext.Tree.Root);
  finally
    mValues.Free;
    mResolver.UnpinTree;
  end;
end;

{ TInfiniteLoopRule }

function TInfiniteLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cInfiniteLoopRuleId, TRuleSeverity.Error, cTexts[TConditionsText.InfiniteTitle].Text);
end;

procedure TInfiniteLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mValues: TConditionValues;
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mRaising: TDictionary<string, Boolean>;
  mFileName: string;

  function Endless(ALoop: TSyntaxNode): Boolean;
  var
    mIndex, mFirst, mLast: Integer;
    mValue: TConstantValue;
  begin
    Result := False;
    if ALoop.ChildCount = 0 then
    begin
      Exit;
    end;
    if ALoop.Kind = TSyntaxKind.WhileStatement then
    begin
      mValue := mValues.Evaluate(ALoop[0]);
      if (mValue.Kind <> TConstantKind.Bool) or not mValue.Bool or mValues.Conditional(ALoop[0]) then
      begin
        Exit;
      end;
      mFirst := 1;
      mLast := ALoop.ChildCount - 1;
    end
    else
    begin
      mValue := mValues.Evaluate(ALoop[ALoop.ChildCount - 1]);
      if (mValue.Kind <> TConstantKind.Bool) or mValue.Bool or mValues.Conditional(ALoop[ALoop.ChildCount - 1]) then
      begin
        Exit;
      end;
      mFirst := 0;
      mLast := ALoop.ChildCount - 2;
    end;
    for mIndex := mFirst to mLast do
    begin
      if HasExit(ALoop[mIndex], False, mRaising) then
      begin
        Exit;
      end;
    end;
    Result := not InTryExcept(ALoop);
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode, mCondition: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement]) and Endless(mNode) then
        begin
          if mNode.Kind = TSyntaxKind.WhileStatement then
          begin
            AReport.Add(TTextRange.Create(mNode.StartPos, mNode[0].EndPos),
              cTexts[TConditionsText.NoExit].Text, TRuleConfidence.High);
          end
          else
          begin
            mCondition := mNode[mNode.ChildCount - 1];
            AReport.Add(NodeRange(mCondition), cTexts[TConditionsText.NoExit].Text,
              TRuleConfidence.High, [TRuleFix.Jump(cTexts[TConditionsText.JumpToHead].Text, mNode.StartPos)]);
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
  mFileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  mValues := TConditionValues.Create(AContext.Tree, AContext.Text, mFileName, mResolver, nil);
  mRaising := RaisingRoutines(AContext.Tree);
  try
    Visit(AContext.Tree.Root);
  finally
    mRaising.Free;
    mValues.Free;
    mResolver.UnpinTree;
  end;
end;

{ TLoopConditionUnchangedRule }

const
  // Warteschleifen: Ein anderer Thread oder eine Nachricht ändert den Zustand.
  cWaitingCalls: array[0..8] of string = ('Sleep', 'ProcessMessages', 'WaitFor', 'Yield', 'SpinWait',
    'WaitForSingleObject', 'WaitForMultipleObjects', 'CheckSynchronize', 'HandleMessage');

type
  /// <summary>Variable der Bedingung: Plain = kommt direkt vor (nicht nur X.Name), Indexed = X[…] in der
  /// Bedingung.</summary>
  TLoopVariable = record
    Name: string;
    Plain: Boolean;
    Indexed: Boolean;
  end;

function TLoopConditionUnchangedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLoopConditionUnchangedRuleId, TRuleSeverity.Warning,
    cTexts[TConditionsText.UnchangedTitle].Text);
end;

function Before(const A, B: TTextPosition): Boolean;
begin
  Result := (A.Line < B.Line) or ((A.Line = B.Line) and (A.Character <= B.Character));
end;

/// <summary>Erster Bezeichner einer Kette X.A[…].B^ bzw. (X); nil, wenn die Kette nicht mit einem Bezeichner
/// beginnt. AViaIndex: direkt auf den Bezeichner folgt [ ].</summary>
function ChainRoot(ANode: TSyntaxNode; out AViaIndex: Boolean): TSyntaxNode;
var
  mPrevious: TSyntaxNode;
begin
  AViaIndex := False;
  mPrevious := nil;
  Result := ANode;
  while (Result <> nil) and (Result.ChildCount > 0) and ((Result.Kind in [TSyntaxKind.MemberAccess,
    TSyntaxKind.IndexAccess, TSyntaxKind.Call, TSyntaxKind.Dereference]) or
    ((Result.Kind = TSyntaxKind.ParenExpr) and (Result.ChildCount = 1))) do
  begin
    mPrevious := Result;
    Result := Result[0];
  end;
  if (Result = nil) or (Result.Kind <> TSyntaxKind.Identifier) then
  begin
    Exit(nil);
  end;
  AViaIndex := (mPrevious <> nil) and (mPrevious.Kind = TSyntaxKind.IndexAccess);
end;

/// <summary>Enthält der Teilbaum einen Knoten der Art AKind?</summary>
function Contains(ANode: TSyntaxNode; AKind: TSyntaxKind): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = AKind then
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

/// <summary>Kommt im Teilbaum ein Bezeichner aus ANames vor (auch als Aufruf)?</summary>
function Mentions(ANode: TSyntaxNode; const ANames: array of string): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess]) and MatchText(mNode.Name, ANames) then
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

/// <summary>Routine oder anonyme Methode um ANode; nil auf Unit-Ebene.</summary>
function EnclosingRoutineOf(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not (Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod]) do
  begin
    Result := Result.Parent;
  end;
end;

/// <summary>Namen der lokalen Routinen innerhalb von ARoutine.</summary>
function NestedRoutines(ARoutine: TSyntaxNode): TArray<string>;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    for mIndex := ARoutine.ChildCount - 1 downto 0 do
    begin
      mPending.Push(ARoutine[mIndex]);
    end;
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Result + [ShortName(mNode.Name)];
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

/// <summary>Werden Namen aus ANames in einer anonymen Methode in ARoot erfasst?</summary>
function Captured(ARoot: TSyntaxNode; const ANames: TArray<string>): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while (mPending.Count > 0) and not Result do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.AnonymousMethod then
      begin
        Result := Mentions(mNode, ANames);
        Continue;
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

/// <summary>Parameter-Knoten, dessen Bereich APosition enthält; nil sonst.</summary>
function ParameterAt(ARoot: TSyntaxNode; const APosition: TTextPosition): TSyntaxNode;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while (mPending.Count > 0) and (Result = nil) do
    begin
      mNode := mPending.Pop;
      if not Before(mNode.StartPos, APosition) or not Before(APosition, mNode.EndPos) then
      begin
        Continue;
      end;
      if mNode.Kind = TSyntaxKind.Parameter then
      begin
        Result := mNode;
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

/// <summary>Variable oder Wertparameter, in ARoutine deklariert (var-, out- und const [ref]-Parameter zählen
/// nicht: Sie kann ein anderer ändern).</summary>
function IsRoutineVariable(const AResolved: TResolvedSymbol; ARoutine: TSyntaxNode): Boolean;
var
  mParameter: TSyntaxNode;
begin
  Result := (AResolved.Kind = TResolvedKind.Local) and (AResolved.SymbolKind = TIndexSymbolKind.Variable) and
    Before(ARoutine.StartPos, AResolved.Range.StartPos) and Before(AResolved.Range.EndPos, ARoutine.EndPos);
  if Result and AResolved.IsParameter then
  begin
    mParameter := ParameterAt(ARoutine, AResolved.SelectionRange.StartPos);
    Result := (mParameter <> nil) and not (mParameter.Modifier in [TParameterModifier.VarParam,
      TParameterModifier.OutParam, TParameterModifier.ConstRefParam]);
  end;
end;

/// <summary>Bezeichner ANode der Bedingung in AVariables aufnehmen bzw. dort ergänzen.</summary>
procedure AddLoopVariable(var AVariables: TArray<TLoopVariable>; ANode: TSyntaxNode);
var
  mIndex: Integer;
  mPlain, mIndexed: Boolean;
begin
  mPlain := (ANode.Parent = nil) or not ((ANode.Parent.Kind in [TSyntaxKind.MemberAccess, TSyntaxKind.IndexAccess,
    TSyntaxKind.Dereference]) and (ANode.Parent.ChildCount > 0) and (ANode.Parent[0] = ANode));
  mIndexed := (ANode.Parent <> nil) and (ANode.Parent.Kind = TSyntaxKind.IndexAccess) and (ANode.Parent[0] = ANode);
  for mIndex := 0 to High(AVariables) do
  begin
    if SameText(AVariables[mIndex].Name, ANode.Name) then
    begin
      AVariables[mIndex].Plain := AVariables[mIndex].Plain or mPlain;
      AVariables[mIndex].Indexed := AVariables[mIndex].Indexed or mIndexed;
      Exit;
    end;
  end;
  SetLength(AVariables, Length(AVariables) + 1);
  AVariables[High(AVariables)].Name := ANode.Name;
  AVariables[High(AVariables)].Plain := mPlain;
  AVariables[High(AVariables)].Indexed := mIndexed;
end;

/// <summary>Ändert die Kette AExpression die Variable AVariable? AViaIndex: über X[…].</summary>
function ChangesChain(AExpression: TSyntaxNode; const AVariable: TLoopVariable; out AViaIndex: Boolean): Boolean;
var
  mRoot: TSyntaxNode;
begin
  mRoot := ChainRoot(AExpression, AViaIndex);
  Result := (mRoot <> nil) and SameText(mRoot.Name, AVariable.Name) and (not AViaIndex or AVariable.Indexed);
end;

/// <summary>Ändert der Knoten ANode selbst (ohne Kinder) die Variable AVariable?</summary>
function ChangesAt(ANode: TSyntaxNode; const AVariable: TLoopVariable): Boolean;
var
  mIndex: Integer;
  mViaIndex: Boolean;
begin
  Result := False;
  case ANode.Kind of
    TSyntaxKind.AssignStatement:
      Result := (ANode.ChildCount > 0) and ChangesChain(ANode[0], AVariable, mViaIndex);
    TSyntaxKind.Call:
      for mIndex := 1 to ANode.ChildCount - 1 do
      begin
        Result := Result or ChangesChain(ANode[mIndex], AVariable, mViaIndex);
      end;
    TSyntaxKind.MemberAccess, TSyntaxKind.AddressOf:
      // X.Methode, X.Eigenschaft (Getter können ändern), @X.
      Result := (ANode.ChildCount > 0) and ChangesChain(ANode[0], AVariable, mViaIndex) and not mViaIndex;
    TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement:
      Result := SameText(ANode.Name, AVariable.Name);
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

/// <summary>Ändert der Teilbaum ARoot die Variable AVariable?</summary>
function Changes(ARoot: TSyntaxNode; const AVariable: TLoopVariable): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while (mPending.Count > 0) and not Result do
    begin
      mNode := mPending.Pop;
      Result := ChangesAt(mNode, AVariable);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

function LoopMessage(const AVariables: TArray<TLoopVariable>): string;
var
  mIndex: Integer;
begin
  Result := AVariables[0].Name;
  for mIndex := 1 to High(AVariables) do
  begin
    if mIndex = High(AVariables) then
    begin
      Result := Result + cTexts[TConditionsText.AndWord].Text + AVariables[mIndex].Name;
    end
    else
    begin
      Result := Result + ', ' + AVariables[mIndex].Name;
    end;
  end;
  if Length(AVariables) = 1 then
  begin
    Result := Result + cTexts[TConditionsText.NeverChangedOne].Text;
  end
  else
  begin
    Result := Result + cTexts[TConditionsText.NeverChangedMany].Text;
  end;
end;

/// <summary>Bedingung und Rumpf einer while- oder repeat-Schleife.</summary>
procedure LoopParts(ALoop: TSyntaxNode; out ACondition: TSyntaxNode; out ABody: TArray<TSyntaxNode>);
var
  mIndex: Integer;
begin
  if ALoop.Kind = TSyntaxKind.WhileStatement then
  begin
    ACondition := ALoop[0];
    ABody := [ALoop[1]];
  end
  else
  begin
    ACondition := ALoop[ALoop.ChildCount - 1];
    ABody := nil;
    for mIndex := 0 to ALoop.ChildCount - 2 do
    begin
      ABody := ABody + [ALoop[mIndex]];
    end;
  end;
end;

/// <summary>Namen der Variablen; False, wenn keine direkt (nicht nur als X.Name) vorkommt.</summary>
function PlainNames(const AVariables: TArray<TLoopVariable>; out ANames: TArray<string>): Boolean;
var
  mVariable: TLoopVariable;
begin
  Result := False;
  ANames := nil;
  for mVariable in AVariables do
  begin
    Result := Result or mVariable.Plain;
    ANames := ANames + [mVariable.Name];
  end;
end;

/// <summary>Kann der Rumpf die Schleife beenden: Ausgang, Warteaufruf, lokale Routine, with oder Änderung
/// einer Variablen der Bedingung?</summary>
function BodyMayEnd(const ABody: TArray<TSyntaxNode>; AOwner: TSyntaxNode; const AVariables: TArray<TLoopVariable>;
  ARaising: TDictionary<string, Boolean>): Boolean;
var
  mStatement: TSyntaxNode;
  mVariable: TLoopVariable;
begin
  Result := False;
  for mStatement in ABody do
  begin
    Result := Result or HasExit(mStatement, False, ARaising) or Mentions(mStatement, cWaitingCalls) or
      Mentions(mStatement, NestedRoutines(AOwner)) or Contains(mStatement, TSyntaxKind.WithStatement);
    for mVariable in AVariables do
    begin
      Result := Result or Changes(mStatement, mVariable);
    end;
  end;
end;

procedure TLoopConditionUnchangedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mResolver: TNameResolver;
  mCache: IRuleDerivedCache;
  mRaising: TDictionary<string, Boolean>;
  mFileName: string;

  /// <summary>Beurteilbarer Bezeichner der Bedingung: AIgnore bei True, False, nil, Konstanten und
  /// Aufzählungswerten; sonst eine Variable der Routine. False, wenn die Regel ihn nicht beurteilt.</summary>
  function Assessable(ANode, ARoutine: TSyntaxNode; out AIgnore: Boolean): Boolean;
  var
    mResolved: TResolvedSymbol;
  begin
    AIgnore := MatchText(ANode.Name, ['True', 'False', 'nil']);
    if AIgnore then
    begin
      Exit(True);
    end;
    if MatchText(ANode.Name, ['Self', 'Terminated']) then
    begin
      Exit(False);
    end;
    mResolved := mResolver.ResolveChain(AContext.Tree, mFileName, [ANode.Name], ANode.StartOffset);
    AIgnore := mResolved.Found and (mResolved.SymbolKind in [TIndexSymbolKind.Constant,
      TIndexSymbolKind.EnumMember]);
    Result := mResolved.Found and (AIgnore or IsRoutineVariable(mResolved, ARoutine));
  end;

  // Variablen der Bedingung; False, wenn die Bedingung etwas enthält, das die Regel nicht beurteilt.
  function ConditionVariables(ACondition, ARoutine: TSyntaxNode; out AVariables: TArray<TLoopVariable>): Boolean;
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
    mIgnore: Boolean;
  begin
    // Iterativ (Bericht M1).
    AVariables := nil;
    Result := True;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ACondition);
      while (mPending.Count > 0) and Result do
      begin
        mNode := mPending.Pop;
        Result := not (mNode.Kind in [TSyntaxKind.Call, TSyntaxKind.AnonymousMethod, TSyntaxKind.InheritedExpr,
          TSyntaxKind.Error]) and ((mNode.Kind <> TSyntaxKind.Identifier) or Assessable(mNode, ARoutine, mIgnore));
        if Result and (mNode.Kind = TSyntaxKind.Identifier) and not mIgnore then
        begin
          AddLoopVariable(AVariables, mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
    Result := Result and (AVariables <> nil);
  end;

  procedure CheckLoop(ALoop: TSyntaxNode);
  var
    mCondition, mOwner: TSyntaxNode;
    mVariables: TArray<TLoopVariable>;
    mBody: TArray<TSyntaxNode>;
    mNames: TArray<string>;
  begin
    mOwner := EnclosingRoutineOf(ALoop);
    if (mOwner = nil) or (mOwner.Kind <> TSyntaxKind.RoutineDecl) or (ALoop.ChildCount < 2) then
    begin
      Exit;
    end;
    LoopParts(ALoop, mCondition, mBody);
    if ConditionVariables(mCondition, mOwner, mVariables) and PlainNames(mVariables, mNames) and
      not Captured(mOwner, mNames) and not BodyMayEnd(mBody, mOwner, mVariables, mRaising) then
    begin
      AReport.Add(NodeRange(mCondition), LoopMessage(mVariables), TRuleConfidence.Medium);
    end;
  end;

  procedure Visit(ARoot: TSyntaxNode);
  var
    mIndex: Integer;
    mNode: TSyntaxNode;
    mPending: TStack<TSyntaxNode>;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ARoot);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement] then
        begin
          CheckLoop(mNode);
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
  mFileName := RuleFileName(AContext);
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mResolver.PinTree(AContext.Tree, mFileName);
  mRaising := RaisingRoutines(AContext.Tree);
  try
    Visit(AContext.Tree.Root);
  finally
    mRaising.Free;
    mResolver.UnpinTree;
  end;
end;

{ TRedundantJumpRule }

function TRedundantJumpRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cRedundantJumpRuleId, TRuleSeverity.Hint,
    cTexts[TConditionsText.RedundantTitle].Text);
end;

/// <summary>Ist AStatement ein bloßes AName; (ohne Argumente, ohne Qualifizierer)?</summary>
function IsBareJump(AStatement: TSyntaxNode; const AName: string): Boolean;
begin
  Result := (AStatement <> nil) and (AStatement.Kind = TSyntaxKind.CallStatement) and (AStatement.ChildCount = 1) and
    (AStatement[0].Kind = TSyntaxKind.Identifier) and SameText(AStatement[0].Name, AName);
end;

/// <summary>Steht zwischen AStart und AEnd eine bedingte Direktive oder eine andere Direktive?</summary>
function HasDirectiveBetween(const ATokens: TTokens; AStart, AEnd: Integer): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  for mIndex := TSyntaxTree.FirstTokenOf(ATokens, AStart) to High(ATokens) do
  begin
    mToken := ATokens[mIndex];
    if mToken.Offset < AStart then
    begin
      Continue;
    end;
    if mToken.Offset >= AEnd then
    begin
      Break;
    end;
    if mToken.Kind = TPascalTokenKind.Directive then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Letzte Anweisung, mit der AStatement endet: in begin … end die letzte, bei if die des letzten Zweigs
/// (else, ohne else then). Ein then-Zweig mit folgendem else ist ein Wächter der else-if-Kette und zählt nicht.
/// Andere Anweisungen (try, case, with, Schleifen) enden mit sich selbst.</summary>
function LastStatement(AStatement: TSyntaxNode): TSyntaxNode;
begin
  Result := AStatement;
  // Schleife statt Rekursion (Bericht M1): lange else-if-Ketten wären sonst tiefe Rekursion.
  while (Result <> nil) and (Result.Kind in [TSyntaxKind.Block, TSyntaxKind.IfStatement]) do
  begin
    if (Result.Kind = TSyntaxKind.IfStatement) and (Result.ChildCount < 2) then
    begin
      Exit(nil);
    end
    else if Result.ChildCount = 0 then
    begin
      Exit(nil);
    end
    else
    begin
      Result := Result[Result.ChildCount - 1];
    end;
  end;
end;

/// <summary>Rumpf einer for-, for-in- oder while-Schleife; bei repeat (die Anweisungen sind direkte Kinder) und
/// bei anderen Knoten nil.</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement]) and
    (ALoop.ChildCount > 0) then
  begin
    Result := ALoop[ALoop.ChildCount - 1];
  end;
end;

/// <summary>Letzte Anweisung des Rumpfs einer Schleife in ALast: der Rumpf aus LoopBody, bei repeat die Anweisung
/// vor der Bedingung hinter until.</summary>
function LoopLastStatement(ALoop: TSyntaxNode; out ALast: TSyntaxNode): Boolean;
begin
  ALast := LoopBody(ALoop);
  if (ALast = nil) and (ALoop.Kind = TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 1) then
  begin
    ALast := ALoop[ALoop.ChildCount - 2];
  end;
  Result := ALast <> nil;
end;

procedure ReportRedundantJump(const AContext: TRuleContext; const AReport: IRuleReport; AStatement: TSyntaxNode;
  const AMessage: string);
var
  mFixes: TArray<TRuleFix>;
begin
  mFixes := nil;
  // In einer Anweisungsfolge (begin … end, repeat … until); als Zweig eines if bliebe ein leeres then.
  if (AStatement.Parent <> nil) and (AStatement.Parent.Kind in [TSyntaxKind.Block, TSyntaxKind.RepeatStatement]) then
  begin
    mFixes := [TRuleFix.Create(cTexts[TConditionsText.RemoveStatement].Text,
      [TRuleEdit.Create(StatementRemoval(AContext.Text, AStatement),
      '')])];
  end;
  AReport.Add(TTextRange.Create(AStatement.StartPos, AStatement.EndPos), AMessage, TRuleConfidence.High, mFixes);
end;

/// <summary>Überflüssiger Sprung am Ende von ANode: Exit als letzte Anweisung eines Routinenrumpfs (Exit in
/// inneren Blöcken kann gewollt früh verlassen) bzw. Continue am Ende eines Schleifenrumpfs; nil ohne.</summary>
function RedundantJump(ANode: TSyntaxNode; const ATokens: TTokens; out AMessage: string): TSyntaxNode;
var
  mBlock, mLast: TSyntaxNode;
begin
  Result := nil;
  if ANode.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
  begin
    AMessage := cTexts[TConditionsText.RedundantExit].Text;
    mBlock := ANode.FindChild(TSyntaxKind.Block);
    if (mBlock <> nil) and (mBlock.ChildCount > 0) and IsBareJump(mBlock[mBlock.ChildCount - 1], 'Exit') and
      not HasDirectiveBetween(ATokens, mBlock.StartOffset, mBlock.EndOffset) then
    begin
      Result := mBlock[mBlock.ChildCount - 1];
    end;
  end
  else if LoopLastStatement(ANode, mLast) and not HasDirectiveBetween(ATokens, ANode.StartOffset, ANode.EndOffset) then
  begin
    AMessage := cTexts[TConditionsText.RedundantContinue].Text;
    Result := LastStatement(mLast);
    if (Result <> nil) and not IsBareJump(Result, 'Continue') then
    begin
      Result := nil;
    end;
  end;
end;

procedure TRedundantJumpRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mPending: TStack<TSyntaxNode>;
  mNode, mJump: TSyntaxNode;
  mIndex: Integer;
  mMessage: string;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not (ContainsText(AContext.Text, 'Exit') or ContainsText(AContext.Text, 'Continue')) then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(AContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
      mJump := RedundantJump(mNode, AContext.Tree.Tokens, mMessage);
      if mJump <> nil then
      begin
        ReportRedundantJump(AContext, AReport, mJump, mMessage);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

{ TLoopRunsAtMostOnceRule }

function TLoopRunsAtMostOnceRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cLoopRunsAtMostOnceRuleId, TRuleSeverity.Warning,
    cTexts[TConditionsText.OnceTitle].Text);
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

type
  /// <summary>Ein Lauf von loop-runs-at-most-once über eine Datei.</summary>
  TLoopOnceCheck = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    // Routinen (Kurzname klein), deren Rumpf auf jedem Weg auslöst bzw. das Programm beendet.
    FRaising: TDictionary<string, Boolean>;
    FAllowFirstElement: Boolean;
    // Nur Ausnahmen und Programmende zählen (Rumpf einer Routine: Exit verlässt nur sie).
    FRaisingOnly: Boolean;
    function Sequence(AParent: TSyntaxNode; AFrom, ATo: Integer; out AMixed: Boolean): string;
    function CallLeaves(ANode: TSyntaxNode): string;
    function IfLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
    function CaseBranchLeaves(ABranch: TSyntaxNode; out AMixed: Boolean): string;
    function CaseLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
    function ExceptLeaves(APart: TSyntaxNode; const AName: string; var AMixed: Boolean): string;
    function TryLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
    function Leaves(ANode: TSyntaxNode; out AMixed: Boolean): string;
    function HasConditional(ANode: TSyntaxNode): Boolean;
    function FirstJump(const AStatements: TArray<TSyntaxNode>; out AJumpAt: Integer; out AMixed: Boolean): string;
    function Applies(ALoop: TSyntaxNode): Boolean;
    function MisplacedJump(const AStatements: TArray<TSyntaxNode>; AJumpAt: Integer): Boolean;
    procedure CheckLoop(ALoop: TSyntaxNode);
    procedure CollectAlwaysRaising;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

/// <summary>Verlässt auch AOther die Schleife? Merkt verschiedene Sprünge in AMixed.</summary>
function BothLeave(const AFirst, AOther: string; AOtherMixed: Boolean; var AMixed: Boolean): string;
begin
  Result := '';
  if (AFirst <> '') and (AOther <> '') then
  begin
    AMixed := AMixed or AOtherMixed or not SameText(AFirst, AOther);
    Result := AFirst;
  end;
end;

/// <summary>Enthält ANode ein Continue dieser Schleife (nicht in inneren Schleifen und anonymen Methoden),
/// ein goto oder eine Marke? Dann gibt es einen Weg zum nächsten Durchlauf.</summary>
function MayContinue(ANode: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  // Iterativ (Bericht M1).
  Result := False;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ANode);
    while (mPending.Count > 0) and not Result do
    begin
      mNode := mPending.Pop;
      if (mNode.Kind = TSyntaxKind.AnonymousMethod) or (mNode <> ANode) and IsLoop(mNode) then
      begin
        Result := mNode.Kind in [TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement];
        Continue;
      end;
      Result := (mNode.Kind in [TSyntaxKind.GotoStatement, TSyntaxKind.LabeledStatement]) or
        (mNode.Kind = TSyntaxKind.CallStatement) and (mNode.ChildCount > 0) and
        SameText(JumpName(mNode[0]), 'Continue');
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Beginnt die Direktive ADirective einen bedingten Teil, einen anderen Zweig oder sein Ende?</summary>
function IsConditionalDirective(const ADirective: string): Boolean;
var
  mText, mPrefix: string;
begin
  Result := False;
  mText := UpperCase(Copy(ADirective, 1, 8));
  for mPrefix in TArray<string>.Create('{$IF', '{$ELSE', '{$END', '(*$IF', '(*$ELSE', '(*$END') do
  begin
    Result := Result or StartsStr(mPrefix, mText);
  end;
end;

/// <summary>Anweisungen des Rumpfs als Folge (Block, einzelne Anweisung bzw. die Anweisungen von repeat).
/// </summary>
function LoopStatements(ALoop: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mBody: TSyntaxNode;
begin
  Result := nil;
  mBody := nil;
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    for mIndex := 0 to ALoop.ChildCount - 2 do
    begin
      Result := Result + [ALoop[mIndex]];
    end;
  end
  else
  begin
    mBody := LoopBody(ALoop);
  end;
  if (mBody <> nil) and (mBody.Kind = TSyntaxKind.Block) then
  begin
    for mIndex := 0 to mBody.ChildCount - 1 do
    begin
      Result := Result + [mBody[mIndex]];
    end;
  end
  else if mBody <> nil then
  begin
    Result := [mBody];
  end;
end;

/// <summary>Kommt im Teilbaum ARoot der Bezeichner AName vor?</summary>
function MentionsName(ARoot: TSyntaxNode; const AName: string): Boolean;
var
  mAt: Integer;
  mInner: TSyntaxNode;
  mStack: TStack<TSyntaxNode>;
begin
  Result := False;
  mStack := TStack<TSyntaxNode>.Create;
  try
    mStack.Push(ARoot);
    while (mStack.Count > 0) and not Result do
    begin
      mInner := mStack.Pop;
      Result := (mInner.Kind = TSyntaxKind.Identifier) and SameText(mInner.Name, AName);
      for mAt := 0 to mInner.ChildCount - 1 do
      begin
        mStack.Push(mInner[mAt]);
      end;
    end;
  finally
    mStack.Free;
  end;
end;

/// <summary>Bedingung von if, case, while, repeat und Bedingungsausdruck; nil bei anderen Knoten.</summary>
function BranchCondition(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  case ANode.Kind of
    TSyntaxKind.IfStatement, TSyntaxKind.CaseStatement, TSyntaxKind.WhileStatement, TSyntaxKind.IfExpr:
      Result := ANode[0];
    TSyntaxKind.RepeatStatement:
      Result := ANode[ANode.ChildCount - 1];
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>for-in, das nur das erste Element holt: Keine Bedingung im Rumpf (if, case, Schleife) liest die
/// Schleifenvariable, der Sprung hängt also nicht vom Element ab.</summary>
function ReadsFirstElement(ALoop: TSyntaxNode): Boolean;
var
  mIndex: Integer;
  mNode, mCondition: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  Result := (ALoop.Kind = TSyntaxKind.ForInStatement) and (ALoop.Name <> '');
  if not Result then
  begin
    Exit;
  end;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(LoopBody(ALoop));
    while (mPending.Count > 0) and Result do
    begin
      mNode := mPending.Pop;
      mCondition := BranchCondition(mNode);
      Result := (mCondition = nil) or not MentionsName(mCondition, ALoop.Name);
      for mIndex := mNode.ChildCount - 1 downto 0 do
      begin
        mPending.Push(mNode[mIndex]);
      end;
    end;
  finally
    mPending.Free;
  end;
end;

/// <summary>Routinen im Baum unter ARoot in Vorordnung.</summary>
function RoutineDecls(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = TSyntaxKind.RoutineDecl then
      begin
        Result := Result + [mNode];
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

/// <summary>Schlüsselwort der Schleife für den Meldungsbereich.</summary>
function KeywordRange(ALoop: TSyntaxNode): TTextRange;
var
  mLength: Integer;
begin
  mLength := 3;
  if ALoop.Kind = TSyntaxKind.WhileStatement then
  begin
    mLength := 5;
  end
  else if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    mLength := 6;
  end;
  Result := TTextRange.Create(ALoop.StartPos, TTextPosition.Create(ALoop.StartPos.Line,
    ALoop.StartPos.Character + mLength));
end;

function LoopOnceMessage(const AText: string; ALoop: TSyntaxNode; const AJump: string): string;
var
  mSubject: string;
begin
  case ALoop.Kind of
    TSyntaxKind.ForInStatement:
      begin
        mSubject := '';
        if ALoop.ChildCount > 1 then
        begin
          mSubject := cTexts[TConditionsText.OfSubject].Fmt([NodeText(AText, ALoop[ALoop.ChildCount - 2])]);
        end;
        Result := cTexts[TConditionsText.FirstElement].Fmt([AJump, mSubject]);
      end;
    TSyntaxKind.RepeatStatement:
      Result := cTexts[TConditionsText.ExactlyOnce].Fmt([AJump]);
  else
    Result := cTexts[TConditionsText.AtMostOnce].Fmt([AJump]);
  end;
end;

constructor TLoopOnceCheck.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FAllowFirstElement := TRuleOptions.Bool(AContext.Options, 'allowFirstElement', False);
  FRaising := TDictionary<string, Boolean>.Create;
end;

destructor TLoopOnceCheck.Destroy;
begin
  FRaising.Free;
  inherited Destroy;
end;

/// <summary>Kinder von AParent ab AFrom als Anweisungsfolge (ohne on-Behandler): Ein Sprung beendet sie, was
/// danach steht, ist unerreichbar.</summary>
function TLoopOnceCheck.Sequence(AParent: TSyntaxNode; AFrom, ATo: Integer; out AMixed: Boolean): string;
var
  mAt: Integer;
begin
  Result := '';
  AMixed := False;
  mAt := AFrom;
  while (mAt <= ATo) and (Result = '') do
  begin
    if AParent[mAt].Kind <> TSyntaxKind.ExceptionHandler then
    begin
      Result := Leaves(AParent[mAt], AMixed);
    end;
    Inc(mAt);
  end;
end;

/// <summary>Aufruf, der immer auslöst (Halt, eine immer auslösende Routine) bzw. Exit oder Break.</summary>
function TLoopOnceCheck.CallLeaves(ANode: TSyntaxNode): string;
var
  mName, mJump: string;
begin
  Result := '';
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mName := CalledName(ANode[0]);
  mJump := JumpName(ANode[0]);
  if MatchText(mJump, cRaisingCalls) or (mName <> '') and FRaising.ContainsKey(LowerCase(mName)) or
    not FRaisingOnly and MatchText(mJump, ['Exit', 'Break']) then
  begin
    Result := mName;
  end;
end;

/// <summary>Nur mit else: Ohne else läuft ein Weg am Sprung vorbei.</summary>
function TLoopOnceCheck.IfLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
var
  mName: string;
  mMixed: Boolean;
begin
  Result := '';
  if ANode.ChildCount = 3 then
  begin
    mName := Leaves(ANode[1], AMixed);
    if mName <> '' then
    begin
      Result := BothLeave(mName, Leaves(ANode[2], mMixed), mMixed, AMixed);
    end;
  end;
end;

function TLoopOnceCheck.CaseBranchLeaves(ABranch: TSyntaxNode; out AMixed: Boolean): string;
begin
  AMixed := False;
  Result := '';
  if (ABranch.Kind = TSyntaxKind.CaseItem) and (ABranch.ChildCount > 0) then
  begin
    Result := Leaves(ABranch[ABranch.ChildCount - 1], AMixed);
  end
  else if ABranch.Kind = TSyntaxKind.CaseElse then
  begin
    Result := Sequence(ABranch, 0, ABranch.ChildCount - 1, AMixed);
  end;
end;

/// <summary>Jeder Zweig und ein else-Zweig.</summary>
function TLoopOnceCheck.CaseLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
var
  mIndex: Integer;
  mOther: string;
  mMixed: Boolean;
begin
  Result := '';
  if ANode.FindChild(TSyntaxKind.CaseElse) = nil then
  begin
    Exit;
  end;
  for mIndex := 1 to ANode.ChildCount - 1 do
  begin
    mOther := CaseBranchLeaves(ANode[mIndex], mMixed);
    if mOther = '' then
    begin
      Exit('');
    end;
    if Result = '' then
    begin
      Result := mOther;
      AMixed := mMixed;
    end
    else
    begin
      Result := BothLeave(Result, mOther, mMixed, AMixed);
    end;
  end;
end;

/// <summary>try … except: der try-Teil (Sprung AName) und jeder Behandler; Anweisungen ohne on bzw. der
/// else-Teil. Nur on-Behandler: andere Ausnahmen laufen nach außen.</summary>
function TLoopOnceCheck.ExceptLeaves(APart: TSyntaxNode; const AName: string; var AMixed: Boolean): string;
var
  mIndex: Integer;
  mHandlers, mMixed: Boolean;
  mHandler: TSyntaxNode;
begin
  Result := AName;
  mHandlers := False;
  for mIndex := 0 to APart.ChildCount - 1 do
  begin
    mHandler := APart[mIndex];
    if (mHandler.Kind = TSyntaxKind.ExceptionHandler) and (Result <> '') then
    begin
      mHandlers := True;
      Result := '';
      if mHandler.ChildCount > 0 then
      begin
        Result := BothLeave(AName, Leaves(mHandler[mHandler.ChildCount - 1], mMixed), mMixed, AMixed);
      end;
    end;
  end;
  if (Result <> '') and (not mHandlers or (APart[APart.ChildCount - 1].Kind <> TSyntaxKind.ExceptionHandler)) then
  begin
    Result := BothLeave(Result, Sequence(APart, 0, APart.ChildCount - 1, mMixed), mMixed, AMixed);
  end;
end;

/// <summary>try … finally: der try- oder der finally-Teil; try … except: der try-Teil und jeder Behandler.
/// </summary>
function TLoopOnceCheck.TryLeaves(ANode: TSyntaxNode; var AMixed: Boolean): string;
var
  mPart: TSyntaxNode;
  mName: string;
begin
  Result := '';
  if ANode.ChildCount = 0 then
  begin
    Exit;
  end;
  mPart := ANode[ANode.ChildCount - 1];
  mName := Sequence(ANode, 0, ANode.ChildCount - 2, AMixed);
  if mPart.Kind = TSyntaxKind.FinallyBlock then
  begin
    Result := mName;
    if Result = '' then
    begin
      Result := Sequence(mPart, 0, mPart.ChildCount - 1, AMixed);
    end;
  end
  else if (mName <> '') and (mPart.Kind = TSyntaxKind.ExceptBlock) then
  begin
    Result := ExceptLeaves(mPart, mName, AMixed);
  end;
end;

/// <summary>Name des Sprungs, mit dem die Anweisung ANode die Schleife immer verlässt (Exit, Break, raise,
/// Halt …), '' wenn sie es nicht immer tut. AMixed: verschiedene Sprünge auf verschiedenen Wegen.</summary>
function TLoopOnceCheck.Leaves(ANode: TSyntaxNode; out AMixed: Boolean): string;
begin
  Result := '';
  AMixed := False;
  case ANode.Kind of
    TSyntaxKind.RaiseStatement:
      Result := 'raise';
    TSyntaxKind.CallStatement:
      Result := CallLeaves(ANode);
    TSyntaxKind.Block:
      Result := Sequence(ANode, 0, ANode.ChildCount - 1, AMixed);
    TSyntaxKind.WithStatement:
      if ANode.ChildCount > 0 then
      begin
        Result := Leaves(ANode[ANode.ChildCount - 1], AMixed);
      end;
    TSyntaxKind.IfStatement:
      Result := IfLeaves(ANode, AMixed);
    TSyntaxKind.CaseStatement:
      Result := CaseLeaves(ANode, AMixed);
    TSyntaxKind.TryStatement:
      Result := TryLeaves(ANode, AMixed);
  else
    // Übrige Arten: nichts zu tun.
  end;
end;

/// <summary>Steht im Bereich von ANode eine bedingte Direktive? Der Baum enthält dann alle Zweige.</summary>
function TLoopOnceCheck.HasConditional(ANode: TSyntaxNode): Boolean;
var
  mToken: TPascalToken;
  mIndex: Integer;
begin
  Result := False;
  mIndex := FContext.Tree.FirstTokenFrom(ANode.StartOffset);
  while (mIndex <= High(FContext.Tree.Tokens)) and (FContext.Tree.Tokens[mIndex].Offset < ANode.EndOffset) and
    not Result do
  begin
    mToken := FContext.Tree.Tokens[mIndex];
    Result := (mToken.Offset >= ANode.StartOffset) and (mToken.Kind = TPascalTokenKind.Directive) and
      IsConditionalDirective(mToken.Text);
    Inc(mIndex);
  end;
end;

/// <summary>Erste Anweisung, die die Schleife immer verlässt: ihr Sprung, ihre Stelle in AJumpAt.</summary>
function TLoopOnceCheck.FirstJump(const AStatements: TArray<TSyntaxNode>; out AJumpAt: Integer;
  out AMixed: Boolean): string;
var
  mIndex: Integer;
begin
  Result := '';
  AJumpAt := -1;
  AMixed := False;
  mIndex := 0;
  while (mIndex <= High(AStatements)) and (Result = '') do
  begin
    Result := Leaves(AStatements[mIndex], AMixed);
    AJumpAt := mIndex;
    Inc(mIndex);
  end;
end;

/// <summary>Keine Weiterführung (Continue, goto), kein bedingter Teil und kein erlaubtes Holen des ersten
/// Elements.</summary>
function TLoopOnceCheck.Applies(ALoop: TSyntaxNode): Boolean;
var
  mBody: TSyntaxNode;
begin
  mBody := LoopBody(ALoop);
  if mBody = nil then
  begin
    mBody := ALoop;
  end;
  Result := not MayContinue(mBody) and not HasConditional(ALoop) and
    not (FAllowFirstElement and ReadsFirstElement(ALoop));
end;

/// <summary>Typisch: "if … then X; Exit;" – der Sprung gehört in den if-Zweig.</summary>
function TLoopOnceCheck.MisplacedJump(const AStatements: TArray<TSyntaxNode>; AJumpAt: Integer): Boolean;
var
  mOtherMixed: Boolean;
begin
  Result := (AJumpAt > 0) and (AStatements[AJumpAt].Kind = TSyntaxKind.CallStatement) and
    (AStatements[AJumpAt - 1].Kind = TSyntaxKind.IfStatement) and (AStatements[AJumpAt - 1].ChildCount = 2);
  Result := Result and (Leaves(AStatements[AJumpAt - 1][1], mOtherMixed) = '');
end;

procedure TLoopOnceCheck.CheckLoop(ALoop: TSyntaxNode);
var
  mStatements: TArray<TSyntaxNode>;
  mJumpAt: Integer;
  mJump, mMessage: string;
  mMixed: Boolean;
begin
  mStatements := LoopStatements(ALoop);
  mJump := FirstJump(mStatements, mJumpAt, mMixed);
  if (mJump = '') or not Applies(ALoop) then
  begin
    Exit;
  end;
  if mMixed then
  begin
    mJump := cTexts[TConditionsText.AJump].Text;
  end;
  mMessage := LoopOnceMessage(FContext.Text, ALoop, mJump);
  if not mMixed and MisplacedJump(mStatements, mJumpAt) then
  begin
    mMessage := mMessage + cTexts[TConditionsText.BelongsInIf].Fmt([mJump]);
  end;
  FReport.Add(KeywordRange(ALoop), mMessage, TRuleConfidence.High);
end;

/// <summary>Routinen der Datei (Kurzname klein), deren Rumpf auf jedem Weg eine Ausnahme auslöst bzw. das
/// Programm beendet; RaisingRoutines genügt nicht, dort reicht ein raise irgendwo.</summary>
procedure TLoopOnceCheck.CollectAlwaysRaising;
var
  mRoutines: TArray<TSyntaxNode>;
  mRoutine, mBlock: TSyntaxNode;
  mChanged, mMixed: Boolean;
begin
  mRoutines := RoutineDecls(FContext.Tree.Root);
  FRaisingOnly := True;
  // Bis nichts mehr dazukommt: A ruft B, B löst immer aus.
  repeat
    mChanged := False;
    for mRoutine in mRoutines do
    begin
      mBlock := mRoutine.FindChild(TSyntaxKind.Block);
      if (mBlock <> nil) and not FRaising.ContainsKey(LowerCase(ShortName(mRoutine.Name))) and
        (Leaves(mBlock, mMixed) <> '') then
      begin
        FRaising.Add(LowerCase(ShortName(mRoutine.Name)), True);
        mChanged := True;
      end;
    end;
  until not mChanged;
  FRaisingOnly := False;
end;

procedure TLoopOnceCheck.Run;
var
  mIndex: Integer;
  mNode: TSyntaxNode;
  mPending: TStack<TSyntaxNode>;
begin
  CollectAlwaysRaising;
  // Iterativ (Bericht M1).
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(FContext.Tree.Root);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if IsLoop(mNode) then
      begin
        CheckLoop(mNode);
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

procedure TLoopRunsAtMostOnceRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCheck: TLoopOnceCheck;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) then
  begin
    Exit;
  end;
  mCheck := TLoopOnceCheck.Create(AContext, AReport);
  try
    mCheck.Run;
  finally
    mCheck.Free;
  end;
end;

procedure RegisterConditionRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TConstantConditionRule.Create);
  ARegistry.Register(TInfiniteLoopRule.Create);
  ARegistry.Register(TLoopConditionUnchangedRule.Create);
  ARegistry.Register(TRedundantJumpRule.Create);
  ARegistry.Register(TLoopRunsAtMostOnceRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Conditions', cTexts);

end.
