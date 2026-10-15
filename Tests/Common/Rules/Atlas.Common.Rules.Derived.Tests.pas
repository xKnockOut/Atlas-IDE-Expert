unit Atlas.Common.Rules.Derived.Tests;

// Tests für den Ableitungscache der Prüfregeln (Review P-03, P-08, D-04).

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
  Source =
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
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Cache: IRuleDerivedCache;
  First, Second: TUnitIndex;
  Stored, StoredAgain: TObject;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Context := ContextOf(Tree, Source);
    Cache := TRuleDerivedCache.Create;
    First := TRuleDerived.UnitIndex(Cache, Context);
    Assert.IsTrue(Cache.TryGet('rules.unitIndex', Stored), 'abgelegt');
    Second := TRuleDerived.UnitIndex(Cache, Context);
    Assert.IsTrue(Cache.TryGet('rules.unitIndex', StoredAgain));
    Assert.IsTrue(Stored = StoredAgain, 'nicht neu berechnet');
    Assert.IsTrue(Length(First.Symbols) > 0, 'Symbole gefunden');
    Assert.AreEqual(Integer(Length(First.Symbols)), Integer(Length(Second.Symbols)));
    Assert.AreEqual('U', First.UnitName);
    Cache := nil;
  finally
    Tree.Free;
  end;
end;

procedure TRuleDerivedTests.OpenWithoutEngineReturnsFreshCache;
var
  Context: TRuleContext;
  First, Second, Shared: IRuleDerivedCache;
begin
  Context := Default(TRuleContext);
  First := TRuleDerived.Open(Context);
  Second := TRuleDerived.Open(Context);
  Assert.IsTrue(First <> nil);
  Assert.IsTrue(First <> Second, 'ohne Engine je Aufruf ein eigener Cache');
  Shared := TRuleDerivedCache.Create;
  Context.Derived := Shared;
  Assert.IsTrue(TRuleDerived.Open(Context) = Shared, 'Cache des Laufs');
  Context.Derived := nil;
end;

procedure TRuleDerivedTests.RoutinesIncludeNestedWithBody;
var
  Tree: TSyntaxTree;
  Cache: IRuleDerivedCache;
  Routines: TArray<TSyntaxNode>;
  Names: string;
  Routine: TSyntaxNode;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Cache := TRuleDerivedCache.Create;
    Routines := TRuleDerived.Routines(Cache, ContextOf(Tree, Source));
    Names := '';
    for Routine in Routines do
      Names := Names + Routine.Name + ' ';
    // forward-Deklaration und Deklaration im interface ohne Rumpf fehlen; Inner nach A (Baumreihenfolge).
    Assert.AreEqual('A Inner Later ', Names);
    Cache := nil;
  finally
    Tree.Free;
  end;
end;

procedure TRuleDerivedTests.CodeTokensSkipCommentsAndDirectives;
var
  Tree: TSyntaxTree;
  Cache: IRuleDerivedCache;
  Tokens: TArray<TPascalToken>;
  Token: TPascalToken;
  Expected: Integer;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Cache := TRuleDerivedCache.Create;
    Tokens := TRuleDerived.CodeTokens(Cache, ContextOf(Tree, Source));
    Expected := 0;
    for Token in Tree.Tokens do
      if not (Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive]) then
        Inc(Expected);
    Assert.IsTrue(Expected < Length(Tree.Tokens), 'Quelltext enthält Kommentare und Direktiven');
    Assert.AreEqual(Expected, Integer(Length(Tokens)));
    for Token in Tokens do
      Assert.IsFalse(Token.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive], Token.Text);
    Cache := nil;
  finally
    Tree.Free;
  end;
end;

procedure TRuleDerivedTests.GraphIsSharedPerRoutine;
var
  Tree: TSyntaxTree;
  Context: TRuleContext;
  Cache: IRuleDerivedCache;
  Routines: TArray<TSyntaxNode>;
  First, Again, Other: TControlFlowGraph;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Context := ContextOf(Tree, Source);
    Cache := TRuleDerivedCache.Create;
    Routines := TRuleDerived.Routines(Cache, Context);
    First := TRuleDerived.Graph(Cache, Context, Routines[0]);
    Again := TRuleDerived.Graph(Cache, Context, Routines[0]);
    Other := TRuleDerived.Graph(Cache, Context, Routines[1]);
    Assert.IsTrue(First <> nil);
    Assert.IsTrue(First = Again, 'derselbe Graph');
    Assert.IsTrue(First <> Other, 'je Routine ein Graph');
    Assert.IsTrue(First.Complete);
    Cache := nil;
  finally
    Tree.Free;
  end;
end;

procedure TRuleDerivedTests.PositionAtMatchesOldBehaviourForCrLfAndLf;
const
  Lf = 'ab'#10'cde'#10'f';
  CrLf = 'ab'#13#10'cde'#13#10'f';
var
  Cache: IRuleDerivedCache;
  Position: TTextPosition;
  Range: TTextRange;
begin
  Cache := TRuleDerivedCache.Create;
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, Lf), 0);
  Assert.AreEqual(0, Position.Line);
  Assert.AreEqual(0, Position.Character);
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, Lf), 4);
  Assert.AreEqual(1, Position.Line);
  Assert.AreEqual(1, Position.Character);
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, Lf), 7);
  Assert.AreEqual(2, Position.Line);
  Assert.AreEqual(0, Position.Character);
  Cache := TRuleDerivedCache.Create;
  // Zeilenanfang und Zeichen mitten in der Zeile wie bisher.
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, CrLf), 4);
  Assert.AreEqual(1, Position.Line);
  Assert.AreEqual(0, Position.Character);
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, CrLf), 6);
  Assert.AreEqual(1, Position.Line);
  Assert.AreEqual(2, Position.Character);
  // Auf dem CR: Zeilenende der Zeile.
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, CrLf), 7);
  Assert.AreEqual(1, Position.Line);
  Assert.AreEqual(3, Position.Character);
  Range := TRuleDerived.OffsetRange(Cache, ContextOf(nil, CrLf), 4, 9);
  Assert.AreEqual(1, Range.StartPos.Line);
  Assert.AreEqual(0, Range.StartPos.Character);
  Assert.AreEqual(2, Range.EndPos.Line);
  Assert.AreEqual(0, Range.EndPos.Character);
end;

procedure TRuleDerivedTests.PositionAtTreatsLoneCrAsLineBreak;
var
  Cache: IRuleDerivedCache;
  Position: TTextPosition;
begin
  Cache := TRuleDerivedCache.Create;
  Position := TRuleDerived.PositionAt(Cache, ContextOf(nil, 'ab'#13'cd'), 4);
  Assert.AreEqual(1, Position.Line);
  Assert.AreEqual(1, Position.Character);
end;

procedure TRuleDerivedTests.GetCallsFactoryOnce;
var
  Cache: IRuleDerivedCache;
  Calls: Integer;
  First, Second: TCounted;
  Factory: TFunc<TCounted>;
begin
  CountedFreed := 0;
  Calls := 0;
  Factory :=
    function: TCounted
    begin
      Inc(Calls);
      Result := TCounted.Create;
    end;
  Cache := TRuleDerivedCache.Create;
  First := TRuleDerived.Get<TCounted>(Cache, 'test.counted', Factory);
  Second := TRuleDerived.Get<TCounted>(Cache, 'test.counted', Factory);
  Assert.AreEqual(1, Calls);
  Assert.IsTrue(First = Second);
  Cache := nil;
  Assert.AreEqual(1, CountedFreed, 'mit dem Cache freigegeben');
end;

procedure TRuleDerivedTests.ClearFreesValues;
var
  Cache: IRuleDerivedCache;
  Value: TObject;
begin
  CountedFreed := 0;
  Cache := TRuleDerivedCache.Create;
  Cache.Put('a', TCounted.Create);
  Cache.Put('b', TCounted.Create);
  // Ersetzen gibt den alten Wert frei.
  Cache.Put('b', TCounted.Create);
  Assert.AreEqual(1, CountedFreed);
  Cache.Clear;
  Assert.AreEqual(3, CountedFreed);
  Assert.IsFalse(Cache.TryGet('a', Value));
end;

procedure TRuleDerivedTests.WithoutTreeEverythingIsEmpty;
var
  Cache: IRuleDerivedCache;
  Context: TRuleContext;
begin
  Cache := TRuleDerivedCache.Create;
  Context := ContextOf(nil, '');
  Assert.AreEqual(0, Integer(Length(TRuleDerived.Routines(Cache, Context))));
  Assert.AreEqual(0, Integer(Length(TRuleDerived.CodeTokens(Cache, Context))));
  Assert.AreEqual(0, Integer(Length(TRuleDerived.UnitIndex(Cache, Context).Symbols)));
  Assert.IsFalse(Assigned(TRuleDerived.FlowSignatures(Cache, Context)));
end;

initialization
  TDUnitX.RegisterTestFixture(TRuleDerivedTests);

end.
