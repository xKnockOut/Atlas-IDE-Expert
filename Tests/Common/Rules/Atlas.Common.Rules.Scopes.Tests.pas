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
  cUnitText =
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
  mScopes: TFindingScopes;
begin
  mScopes := TFindingScopes.FromText(cUnitText);
  Assert.AreEqual('TFoo.Bar', mScopes.At(4));
  Assert.AreEqual('TFoo.Bar', mScopes.At(10));
  Assert.AreEqual('TFoo.Bar', mScopes.At(11));
  Assert.AreEqual('Frei', mScopes.At(13));
end;

procedure TFindingScopesTests.NestedRoutineAppendsName;
begin
  Assert.AreEqual('TFoo.Bar.Lokal', TFindingScopes.FromText(cUnitText).At(7));
end;

procedure TFindingScopesTests.OutsideRoutineIsSection;
var
  mScopes: TFindingScopes;
begin
  mScopes := TFindingScopes.FromText(cUnitText);
  Assert.AreEqual('unit', mScopes.At(0));
  Assert.AreEqual('interface', mScopes.At(2));
  Assert.AreEqual('implementation', mScopes.At(3));
  Assert.AreEqual('initialization', mScopes.At(16));
  Assert.AreEqual('finalization', mScopes.At(18));
end;

procedure TFindingScopesTests.ProgramMainBlock;
const
  cText =
    'program P;' + #10 +
    'procedure Hilfe;' + #10 +
    'begin' + #10 +
    'end;' + #10 +
    'begin' + #10 +
    '  Hilfe;' + #10 +
    'end.';
var
  mScopes: TFindingScopes;
begin
  mScopes := TFindingScopes.FromText(cText);
  Assert.AreEqual('Hilfe', mScopes.At(2));
  Assert.AreEqual('program', mScopes.At(5));
end;

procedure TFindingScopesTests.ForwardDeclarationIsNoRoutine;
var
  mScopes: TFindingScopes;
begin
  // "procedure Frei;" im interface hat keinen Rumpf.
  mScopes := TFindingScopes.FromText(cUnitText);
  Assert.AreEqual(3, mScopes.RoutineCount);
  Assert.AreEqual('interface', mScopes.At(2));
end;

procedure TFindingScopesTests.HeaderLineAndHasRoutine;
var
  mScopes: TFindingScopes;
begin
  mScopes := TFindingScopes.FromText(cUnitText);
  Assert.AreEqual(4, mScopes.HeaderLine(10));
  Assert.AreEqual(5, mScopes.HeaderLine(7));
  Assert.AreEqual(-1, mScopes.HeaderLine(16));
  Assert.IsTrue(mScopes.HasRoutine('tfoo.bar'));
  Assert.IsTrue(mScopes.HasRoutine('TFoo.Bar.Lokal'));
  Assert.IsFalse(mScopes.HasRoutine('TFoo.Baz'));
end;

procedure TFindingScopesTests.EmptyWithoutTree;
var
  mScopes: TFindingScopes;
begin
  mScopes := TFindingScopes.FromTree(nil);
  Assert.AreEqual('', mScopes.At(0));
  Assert.AreEqual(0, mScopes.RoutineCount);
  Assert.AreEqual(-1, mScopes.HeaderLine(0));
end;

initialization
  TDUnitX.RegisterTestFixture(TFindingScopesTests);

end.
