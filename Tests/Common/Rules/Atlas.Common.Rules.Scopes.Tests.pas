unit Atlas.Common.Rules.Scopes.Tests;

// Tests für die umgebende Routine eines Treffers (#97, Baseline-Schlüssel).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TFindingScopesTests = class
  public
    [Test]
    procedure MethodHasQualifiedName;
    [Test]
    procedure NestedRoutineAppendsName;
    [Test]
    procedure OutsideRoutineIsSection;
    [Test]
    procedure ProgramMainBlock;
    [Test]
    procedure ForwardDeclarationIsNoRoutine;
    [Test]
    procedure HeaderLineAndHasRoutine;
    [Test]
    procedure EmptyWithoutTree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Scopes;

const
  UnitText =
    'unit U;' + #10 +                      // 0
    'interface' + #10 +                    // 1
    'procedure Frei;' + #10 +              // 2
    'implementation' + #10 +               // 3
    'procedure TFoo.Bar;' + #10 +          // 4
    '  procedure Lokal;' + #10 +           // 5
    '  begin' + #10 +                      // 6
    '    X.Free;' + #10 +                  // 7
    '  end;' + #10 +                       // 8
    'begin' + #10 +                        // 9
    '  Lokal;' + #10 +                     // 10
    'end;' + #10 +                         // 11
    'procedure Frei;' + #10 +              // 12
    'begin' + #10 +                        // 13
    'end;' + #10 +                         // 14
    'initialization' + #10 +               // 15
    '  X := 1;' + #10 +                    // 16
    'finalization' + #10 +                 // 17
    '  X := 0;' + #10 +                    // 18
    'end.';                                // 19

{ TFindingScopesTests }

procedure TFindingScopesTests.MethodHasQualifiedName;
var
  Scopes: TFindingScopes;
begin
  Scopes := TFindingScopes.FromText(UnitText);
  Assert.AreEqual('TFoo.Bar', Scopes.At(4));
  Assert.AreEqual('TFoo.Bar', Scopes.At(10));
  Assert.AreEqual('TFoo.Bar', Scopes.At(11));
  Assert.AreEqual('Frei', Scopes.At(13));
end;

procedure TFindingScopesTests.NestedRoutineAppendsName;
begin
  Assert.AreEqual('TFoo.Bar.Lokal', TFindingScopes.FromText(UnitText).At(7));
end;

procedure TFindingScopesTests.OutsideRoutineIsSection;
var
  Scopes: TFindingScopes;
begin
  Scopes := TFindingScopes.FromText(UnitText);
  Assert.AreEqual('unit', Scopes.At(0));
  Assert.AreEqual('interface', Scopes.At(2));
  Assert.AreEqual('implementation', Scopes.At(3));
  Assert.AreEqual('initialization', Scopes.At(16));
  Assert.AreEqual('finalization', Scopes.At(18));
end;

procedure TFindingScopesTests.ProgramMainBlock;
const
  Text =
    'program P;' + #10 +
    'procedure Hilfe;' + #10 +
    'begin' + #10 +
    'end;' + #10 +
    'begin' + #10 +
    '  Hilfe;' + #10 +
    'end.';
var
  Scopes: TFindingScopes;
begin
  Scopes := TFindingScopes.FromText(Text);
  Assert.AreEqual('Hilfe', Scopes.At(2));
  Assert.AreEqual('program', Scopes.At(5));
end;

procedure TFindingScopesTests.ForwardDeclarationIsNoRoutine;
var
  Scopes: TFindingScopes;
begin
  // "procedure Frei;" im interface hat keinen Rumpf.
  Scopes := TFindingScopes.FromText(UnitText);
  Assert.AreEqual(3, Scopes.RoutineCount);
  Assert.AreEqual('interface', Scopes.At(2));
end;

procedure TFindingScopesTests.HeaderLineAndHasRoutine;
var
  Scopes: TFindingScopes;
begin
  Scopes := TFindingScopes.FromText(UnitText);
  Assert.AreEqual(4, Scopes.HeaderLine(10));
  Assert.AreEqual(5, Scopes.HeaderLine(7));
  Assert.AreEqual(-1, Scopes.HeaderLine(16));
  Assert.IsTrue(Scopes.HasRoutine('tfoo.bar'));
  Assert.IsTrue(Scopes.HasRoutine('TFoo.Bar.Lokal'));
  Assert.IsFalse(Scopes.HasRoutine('TFoo.Baz'));
end;

procedure TFindingScopesTests.EmptyWithoutTree;
var
  Scopes: TFindingScopes;
begin
  Scopes := TFindingScopes.FromTree(nil);
  Assert.AreEqual('', Scopes.At(0));
  Assert.AreEqual(0, Scopes.RoutineCount);
  Assert.AreEqual(-1, Scopes.HeaderLine(0));
end;

initialization
  TDUnitX.RegisterTestFixture(TFindingScopesTests);

end.
