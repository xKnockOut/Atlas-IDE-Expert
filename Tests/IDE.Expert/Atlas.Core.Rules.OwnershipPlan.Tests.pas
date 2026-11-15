unit Atlas.Core.Rules.OwnershipPlan.Tests;

// Tests für die Entscheidungen der Marke „Wer gibt das frei?“ (#1877):
// Schalter, Dateien, Klick, gemerkte Marken und Tooltip.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Rules')]
  TAtlasOwnershipPlanTests = class
  public
    /// <summary>Marken nur mit Atlas und Einstellung an, nicht abgeschaltet; nur .pas und .dpr.</summary>
    [Test]
    procedure WantedAndFiles;
    /// <summary>Klick springt nur mit linker Taste ohne Zusatztasten und gezeichneten Marken.</summary>
    [Test]
    procedure ClickNeedsPlainLeft;
    /// <summary>Gescrollt: alle Marken verfallen; dieselbe Zeile wird ersetzt.</summary>
    [Test]
    procedure HitsFollowScrolling;
    /// <summary>Tooltip nach der Verzögerung, zu beim Verlassen.</summary>
    [Test]
    procedure TipSteps;
  end;

implementation

uses
  Atlas.Core.Rules.OwnershipPlan;

{ TAtlasOwnershipPlanTests }

procedure TAtlasOwnershipPlanTests.WantedAndFiles;
begin
  Assert.IsTrue(TAtlasOwnershipPlan.Wanted(True, True, False));
  Assert.IsFalse(TAtlasOwnershipPlan.Wanted(False, True, False), 'Atlas aus');
  Assert.IsFalse(TAtlasOwnershipPlan.Wanted(True, False, False), 'Einstellung aus');
  Assert.IsFalse(TAtlasOwnershipPlan.Wanted(True, True, True), 'abgeschaltet');
  Assert.IsTrue(TAtlasOwnershipPlan.MarksFile('C:\P\A.PAS'));
  Assert.IsTrue(TAtlasOwnershipPlan.MarksFile('C:\P\App.dpr'));
  Assert.IsFalse(TAtlasOwnershipPlan.MarksFile('C:\P\Pkg.dpk'));
end;

procedure TAtlasOwnershipPlanTests.ClickNeedsPlainLeft;
begin
  Assert.IsTrue(TAtlasOwnershipPlan.ClickJumps(True, False, True, True));
  Assert.IsFalse(TAtlasOwnershipPlan.ClickJumps(False, False, True, True), 'rechte Taste');
  Assert.IsFalse(TAtlasOwnershipPlan.ClickJumps(True, True, True, True), 'mit Strg');
  Assert.IsFalse(TAtlasOwnershipPlan.ClickJumps(True, False, False, True), 'keine Marken');
  Assert.IsFalse(TAtlasOwnershipPlan.ClickJumps(True, False, True, False), 'aus');
end;

procedure TAtlasOwnershipPlanTests.HitsFollowScrolling;
begin
  Assert.IsTrue(TAtlasOwnershipPlan.ForgetsHits(True, 10, 11));
  Assert.IsFalse(TAtlasOwnershipPlan.ForgetsHits(True, 10, 10));
  Assert.IsFalse(TAtlasOwnershipPlan.ForgetsHits(False, -1, 11), 'keine gemerkt');
  Assert.AreEqual(1, TAtlasOwnershipPlan.SameLine(TArray<Integer>.Create(4, 7, 9), 7));
  Assert.AreEqual(-1, TAtlasOwnershipPlan.SameLine(TArray<Integer>.Create(4, 7, 9), 8));
  Assert.AreEqual(-1, TAtlasOwnershipPlan.SameLine(nil, 0));
end;

procedure TAtlasOwnershipPlanTests.TipSteps;
begin
  Assert.AreEqual(Ord(TAtlasOwnershipTipStep.Close), Ord(TAtlasOwnershipPlan.TipStep(False, True, 0, 0, 500)));
  Assert.AreEqual(Ord(TAtlasOwnershipTipStep.Stay), Ord(TAtlasOwnershipPlan.TipStep(True, False, 1000, 1499, 500)));
  Assert.AreEqual(Ord(TAtlasOwnershipTipStep.Show), Ord(TAtlasOwnershipPlan.TipStep(True, False, 1000, 1500, 500)));
  Assert.AreEqual(Ord(TAtlasOwnershipTipStep.Stay), Ord(TAtlasOwnershipPlan.TipStep(True, True, 1000, 9000, 500)),
    'schon sichtbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasOwnershipPlanTests);

end.
