unit Atlas.Common.Metrics.UnitRoutines.Tests;

// Tests der freien Routinen, die als Mitglieder einer Klasse zählen (metric-class-size): Zugriff über Parameter,
// lokale und globale Variable, nur auf nicht öffentliche Mitglieder, je Routine einmal, keine Methoden und keine
// Klassen anderer Units.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TUnitRoutineAccessTests = class
  public
    [Test]
    procedure ParameterReadingPrivateFieldCounts;
    [Test]
    procedure PublicMembersDoNotCount;
    [Test]
    procedure ClassOfOtherUnitDoesNotCount;
    [Test]
    procedure EachRoutineCountsOncePerClass;
    [Test]
    procedure LocalAndGlobalVariablesCount;
    [Test]
    procedure MethodsAndLocalRoutinesAreNoFreeRoutines;
    [Test]
    procedure StructureAddsRoutinesToClassSize;
  end;

implementation

uses
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Metrics.Contract,
  Atlas.Common.Metrics.Calculator,
  Atlas.Common.Metrics.UnitRoutines;

const
  cHead = 'unit U;'#10'interface'#10'type'#10'  TFoo = class'#10'  private'#10'    FA: Integer;'#10 +
    '    procedure Intern;'#10'  protected'#10'    FB: string;'#10'  public'#10'    Wert: Integer;'#10 +
    '    procedure Zeige;'#10'  end;'#10'implementation'#10;

/// <summary>Zahl der freien Routinen für TFoo in AText.</summary>
function CountFor(const AText: string): Integer;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TUnitRoutineAccess.CountOf(TUnitRoutineAccess.Count(mTree), 'TFoo');
  finally
    mTree.Free;
  end;
end;

procedure TUnitRoutineAccessTests.ParameterReadingPrivateFieldCounts;
begin
  Assert.AreEqual(1, CountFor(cHead + 'function Lies(AFoo: TFoo): Integer;'#10'begin'#10'  Result := AFoo.FA;'#10 +
    'end;'#10'end.'), 'privates Feld');
  Assert.AreEqual(1, CountFor(cHead + 'procedure Setze(const AFoo: TFoo);'#10'begin'#10'  AFoo.FB := ''x'';'#10 +
    'end;'#10'end.'), 'geschütztes Feld');
  Assert.AreEqual(1, CountFor(cHead + 'procedure Rufe(AFoo: TFoo);'#10'begin'#10'  AFoo.Intern;'#10'end;'#10 +
    'end.'), 'private Methode');
end;

procedure TUnitRoutineAccessTests.PublicMembersDoNotCount;
begin
  Assert.AreEqual(0, CountFor(cHead + 'procedure Rufe(AFoo: TFoo);'#10'begin'#10'  AFoo.Zeige;'#10 +
    '  AFoo.Wert := 1;'#10'end;'#10'end.'));
end;

procedure TUnitRoutineAccessTests.ClassOfOtherUnitDoesNotCount;
begin
  Assert.AreEqual(0, CountFor('unit U;'#10'interface'#10'implementation'#10'uses'#10'  Fremd;'#10 +
    'procedure Rufe(AFoo: TFoo);'#10'begin'#10'  AFoo.FA := 1;'#10'end;'#10'end.'));
end;

procedure TUnitRoutineAccessTests.EachRoutineCountsOncePerClass;
begin
  Assert.AreEqual(2, CountFor(cHead + 'procedure Eins(AFoo: TFoo);'#10'begin'#10'  AFoo.FA := 1;'#10 +
    '  AFoo.FB := ''y'';'#10'end;'#10'procedure Zwei(A, B: TFoo);'#10'begin'#10'  A.FA := B.FA;'#10'end;'#10 +
    'end.'));
end;

procedure TUnitRoutineAccessTests.LocalAndGlobalVariablesCount;
begin
  Assert.AreEqual(1, CountFor(cHead + 'procedure Lokal;'#10'var'#10'  mFoo: TFoo;'#10'begin'#10 +
    '  mFoo := TFoo.Create;'#10'  mFoo.FA := 1;'#10'end;'#10'end.'), 'lokale Variable');
  Assert.AreEqual(1, CountFor(cHead + 'var'#10'  GFoo: TFoo;'#10'procedure Global;'#10'begin'#10 +
    '  GFoo.Intern;'#10'end;'#10'end.'), 'Variable der Unit');
end;

procedure TUnitRoutineAccessTests.MethodsAndLocalRoutinesAreNoFreeRoutines;
begin
  Assert.AreEqual(0, CountFor(cHead + 'procedure TFoo.Zeige;'#10#10'  procedure Innen(AFoo: TFoo);'#10 +
    '  begin'#10'    AFoo.FA := 1;'#10'  end;'#10#10'begin'#10'  Innen(Self);'#10'end;'#10'end.'), 'Methode');
  Assert.AreEqual(1, CountFor(cHead + 'procedure Aussen(AFoo: TFoo);'#10#10'  procedure Innen;'#10 +
    '  begin'#10'    AFoo.FA := 1;'#10'  end;'#10#10'begin'#10'  Innen;'#10'end;'#10'end.'),
    'lokale Routine gehört zur freien Routine');
end;

procedure TUnitRoutineAccessTests.StructureAddsRoutinesToClassSize;
var
  mItem: TStructureMetrics;
  mFound: Boolean;
begin
  mFound := False;
  for mItem in TMetricsCalculator.StructureForText(cHead + 'procedure Eins(AFoo: TFoo);'#10'begin'#10 +
    '  AFoo.FA := 1;'#10'end;'#10'end.') do
  begin
    if mItem.Kind = TStructureKind.ClassSize then
    begin
      mFound := True;
      Assert.AreEqual(6, mItem.Value, '5 Member und eine Routine');
      Assert.AreEqual(1, mItem.UnitRoutines);
    end;
  end;
  Assert.IsTrue(mFound);
end;

initialization
  TDUnitX.RegisterTestFixture(TUnitRoutineAccessTests);

end.
