unit Atlas.Common.Rules.Derived.Tests;

// Tests für den Ableitungscache der Prüfregeln.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRuleDerivedTests = class
  public
    [Test]
    procedure UnitIndexIsExtractedOncePerCache;
    [Test]
    procedure OpenWithoutEngineReturnsFreshCache;
    [Test]
    procedure RoutinesIncludeNestedWithBody;
    [Test]
    procedure CodeTokensSkipCommentsAndDirectives;
    [Test]
    procedure GraphIsSharedPerRoutine;
    [Test]
    procedure PositionAtMatchesOldBehaviourForCrLfAndLf;
    /// <summary>Abweichung zur alten Kopie in den Regeln: einzelnes CR beendet die Zeile.</summary>
    [Test]
    procedure PositionAtTreatsLoneCrAsLineBreak;
    [Test]
    procedure GetCallsFactoryOnce;
    [Test]
    procedure ClearFreesValues;
    [Test]
    procedure WithoutTreeEverythingIsEmpty;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Derived;

const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'procedure A;'#10 +
    'implementation'#10 +
    'procedure Later; forward;'#10 +
    '{$HINTS OFF}'#10 +
    'procedure A;'#10 +
    '  procedure Inner;'#10 +
    '  begin'#10 +
    '  end;'#10 +
    'begin'#10 +
    '  // Kommentar'#10 +
    '  Inner;'#10 +
    'end;'#10 +
    '{$HINTS ON}'#10 +
    'procedure Later;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

var
  // Freigaben von TCounted.
  CountedFreed: Integer;

type
  TCounted = class
  public
    destructor Destroy; override;
  end;

destructor TCounted.Destroy;
begin
  Inc(CountedFreed);
  inherited Destroy;
end;

function ContextOf(ATree: TSyntaxTree; const AText: string): TRuleContext;
begin
  Result := Default(TRuleContext);
  Result.Text := AText;
  Result.Tree := ATree;
end;

procedure TRuleDerivedTests.UnitIndexIsExtractedOncePerCache;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mCache: IRuleDerivedCache;
  mFirst, mSecond: TUnitIndex;
  mStored, mStoredAgain: TObject;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := ContextOf(mTree, cSource);
    mCache := TRuleDerivedCache.Create;
    mFirst := TRuleDerived.UnitIndex(mCache, mContext);
    Assert.IsTrue(mCache.TryGet('rules.unitIndex', mStored), 'abgelegt');
    mSecond := TRuleDerived.UnitIndex(mCache, mContext);
    Assert.IsTrue(mCache.TryGet('rules.unitIndex', mStoredAgain));
    Assert.AreSame(mStored, mStoredAgain, 'nicht neu berechnet');
    Assert.IsTrue(Length(mFirst.Symbols) > 0, 'Symbole gefunden');
    Assert.AreEqual(Integer(Length(mFirst.Symbols)), Integer(Length(mSecond.Symbols)));
    Assert.AreEqual('U', mFirst.UnitName);
    mCache := nil;
  finally
    mTree.Free;
  end;
end;

procedure TRuleDerivedTests.OpenWithoutEngineReturnsFreshCache;
var
  mContext: TRuleContext;
  mFirst, mSecond, mShared: IRuleDerivedCache;
begin
  mContext := Default(TRuleContext);
  mFirst := TRuleDerived.Open(mContext);
  mSecond := TRuleDerived.Open(mContext);
  Assert.IsNotNull(mFirst);
  Assert.AreNotSame(mFirst, mSecond, 'ohne Engine je Aufruf ein eigener Cache');
  mShared := TRuleDerivedCache.Create;
  mContext.Derived := mShared;
  Assert.AreSame(mShared, TRuleDerived.Open(mContext), 'Cache des Laufs');
  mContext.Derived := nil;
end;

procedure TRuleDerivedTests.RoutinesIncludeNestedWithBody;
var
  mTree: TSyntaxTree;
  mCache: IRuleDerivedCache;
  mRoutines: TArray<TSyntaxNode>;
  mNames: string;
  mRoutine: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mCache := TRuleDerivedCache.Create;
    mRoutines := TRuleDerived.Routines(mCache, ContextOf(mTree, cSource));
    mNames := '';
    for mRoutine in mRoutines do
    begin
      mNames := mNames + mRoutine.Name + ' ';
    end;
    // forward-Deklaration und Deklaration im interface ohne Rumpf fehlen; Inner nach A (Baumreihenfolge).
    Assert.AreEqual('A Inner Later ', mNames);
    mCache := nil;
  finally
    mTree.Free;
  end;
end;

procedure TRuleDerivedTests.CodeTokensSkipCommentsAndDirectives;
var
  mTree: TSyntaxTree;
  mCache: IRuleDerivedCache;
  mTokens: TArray<TPascalToken>;
  mToken: TPascalToken;
  mExpected: Integer;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mCache := TRuleDerivedCache.Create;
    mTokens := TRuleDerived.CodeTokens(mCache, ContextOf(mTree, cSource));
    mExpected := 0;
    for mToken in mTree.Tokens do
    begin
      if not (mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
      begin
        Inc(mExpected);
      end;
    end;
    Assert.IsTrue(mExpected < Length(mTree.Tokens), 'Quelltext enthält Kommentare und Direktiven');
    Assert.AreEqual(mExpected, Integer(Length(mTokens)));
    for mToken in mTokens do
    begin
      Assert.IsFalse(mToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive], mToken.Text);
    end;
    mCache := nil;
  finally
    mTree.Free;
  end;
end;

procedure TRuleDerivedTests.GraphIsSharedPerRoutine;
var
  mTree: TSyntaxTree;
  mContext: TRuleContext;
  mCache: IRuleDerivedCache;
  mRoutines: TArray<TSyntaxNode>;
  mFirst, mAgain, mOther: TControlFlowGraph;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mContext := ContextOf(mTree, cSource);
    mCache := TRuleDerivedCache.Create;
    mRoutines := TRuleDerived.Routines(mCache, mContext);
    mFirst := TRuleDerived.Graph(mCache, mContext, mRoutines[0]);
    mAgain := TRuleDerived.Graph(mCache, mContext, mRoutines[0]);
    mOther := TRuleDerived.Graph(mCache, mContext, mRoutines[1]);
    Assert.IsNotNull(mFirst);
    Assert.AreSame(mAgain, mFirst, 'derselbe Graph');
    Assert.AreNotSame(mFirst, mOther, 'je Routine ein Graph');
    Assert.IsTrue(mFirst.Complete);
    mCache := nil;
  finally
    mTree.Free;
  end;
end;

procedure TRuleDerivedTests.PositionAtMatchesOldBehaviourForCrLfAndLf;
const
  cLf = 'ab'#10'cde'#10'f';
  cCrLf = 'ab'#13#10'cde'#13#10'f';
var
  mCache: IRuleDerivedCache;
  mPosition: TTextPosition;
  mRange: TTextRange;
begin
  mCache := TRuleDerivedCache.Create;
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cLf), 0);
  Assert.AreEqual(0, mPosition.Line);
  Assert.AreEqual(0, mPosition.Character);
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cLf), 4);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(1, mPosition.Character);
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cLf), 7);
  Assert.AreEqual(2, mPosition.Line);
  Assert.AreEqual(0, mPosition.Character);
  mCache := TRuleDerivedCache.Create;
  // Zeilenanfang und Zeichen mitten in der Zeile wie bisher.
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cCrLf), 4);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(0, mPosition.Character);
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cCrLf), 6);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(2, mPosition.Character);
  // Auf dem CR: Zeilenende der Zeile.
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, cCrLf), 7);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(3, mPosition.Character);
  mRange := TRuleDerived.OffsetRange(mCache, ContextOf(nil, cCrLf), 4, 9);
  Assert.AreEqual(1, mRange.StartPos.Line);
  Assert.AreEqual(0, mRange.StartPos.Character);
  Assert.AreEqual(2, mRange.EndPos.Line);
  Assert.AreEqual(0, mRange.EndPos.Character);
end;

procedure TRuleDerivedTests.PositionAtTreatsLoneCrAsLineBreak;
var
  mCache: IRuleDerivedCache;
  mPosition: TTextPosition;
begin
  mCache := TRuleDerivedCache.Create;
  mPosition := TRuleDerived.PositionAt(mCache, ContextOf(nil, 'ab'#13'cd'), 4);
  Assert.AreEqual(1, mPosition.Line);
  Assert.AreEqual(1, mPosition.Character);
end;

procedure TRuleDerivedTests.GetCallsFactoryOnce;
var
  mCache: IRuleDerivedCache;
  mCalls: Integer;
  mFirst, mSecond: TCounted;
  mFactory: TFunc<TCounted>;
begin
  CountedFreed := 0;
  mCalls := 0;
  mFactory :=
    function: TCounted
    begin
      Inc(mCalls);
      Result := TCounted.Create;
    end;
  mCache := TRuleDerivedCache.Create;
  mFirst := TRuleDerived.Get<TCounted>(mCache, 'test.counted', mFactory);
  mSecond := TRuleDerived.Get<TCounted>(mCache, 'test.counted', mFactory);
  Assert.AreEqual(1, mCalls);
  Assert.AreSame(mSecond, mFirst);
  mCache := nil;
  Assert.AreEqual(1, CountedFreed, 'mit dem Cache freigegeben');
end;

procedure TRuleDerivedTests.ClearFreesValues;
var
  mCache: IRuleDerivedCache;
  mValue: TObject;
begin
  CountedFreed := 0;
  mCache := TRuleDerivedCache.Create;
  mCache.Put('a', TCounted.Create);
  mCache.Put('b', TCounted.Create);
  // Ersetzen gibt den alten Wert frei.
  mCache.Put('b', TCounted.Create);
  Assert.AreEqual(1, CountedFreed);
  mCache.Clear;
  Assert.AreEqual(3, CountedFreed);
  Assert.IsFalse(mCache.TryGet('a', mValue));
end;

procedure TRuleDerivedTests.WithoutTreeEverythingIsEmpty;
var
  mCache: IRuleDerivedCache;
  mContext: TRuleContext;
begin
  mCache := TRuleDerivedCache.Create;
  mContext := ContextOf(nil, '');
  Assert.AreEqual(0, Integer(Length(TRuleDerived.Routines(mCache, mContext))));
  Assert.AreEqual(0, Integer(Length(TRuleDerived.CodeTokens(mCache, mContext))));
  Assert.AreEqual(0, Integer(Length(TRuleDerived.UnitIndex(mCache, mContext).Symbols)));
  Assert.IsFalse(Assigned(TRuleDerived.FlowSignatures(mCache, mContext)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDerivedTests);

end.
