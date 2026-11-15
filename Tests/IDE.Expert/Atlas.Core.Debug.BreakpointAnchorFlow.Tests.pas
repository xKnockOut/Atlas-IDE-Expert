unit Atlas.Core.Debug.BreakpointAnchorFlow.Tests;

// Tests für die Entscheidungen der mitwandernden Haltepunkte außerhalb von Anker und Suche (#841, #1967): geänderte
// Datei, Fall je Zeile, Ergebnis nach dem Nachziehen, Speichern, alte Verwaiste; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasBreakpointAnchorFlowTests = class
  public
    [Test]
    procedure ChangedByHash;
    [Test]
    procedure CasePerLine;
    [Test]
    procedure OutcomeNeedsExternalOrStored;
    [Test]
    procedure SaveAfterInterval;
    [Test]
    procedure OldOrphanStaysUnlessNew;
  end;

implementation

uses
  Atlas.Core.Debug.BreakpointAnchors,
  Atlas.Core.Debug.BreakpointAnchorFlow;

function Orphan(const AFileName: string; ALine: Integer): TAtlasAnchorOrphan;
begin
  Result := Default(TAtlasAnchorOrphan);
  Result.Item.FileName := AFileName;
  Result.Item.Line := ALine;
end;

{ TAtlasBreakpointAnchorFlowTests }

procedure TAtlasBreakpointAnchorFlowTests.ChangedByHash;
var
  mSeen: TAtlasAnchorFileSeen;
begin
  mSeen := Default(TAtlasAnchorFileSeen);
  mSeen.Hash := 17;
  Assert.IsFalse(TAtlasBreakpointAnchorFlow.Changed(True, mSeen, 17));
  Assert.IsTrue(TAtlasBreakpointAnchorFlow.Changed(True, mSeen, 18));
  Assert.IsTrue(TAtlasBreakpointAnchorFlow.Changed(False, mSeen, 17));
end;

procedure TAtlasBreakpointAnchorFlowTests.CasePerLine;
begin
  Assert.AreEqual<TAtlasAnchorCase>(TAtlasAnchorCase.Stored, TAtlasBreakpointAnchorFlow.CaseOf(False, True, False));
  Assert.AreEqual<TAtlasAnchorCase>(TAtlasAnchorCase.Added, TAtlasBreakpointAnchorFlow.CaseOf(False, False, True));
  Assert.AreEqual<TAtlasAnchorCase>(TAtlasAnchorCase.Unchanged,
    TAtlasBreakpointAnchorFlow.CaseOf(True, False, False));
  Assert.AreEqual<TAtlasAnchorCase>(TAtlasAnchorCase.Follow, TAtlasBreakpointAnchorFlow.CaseOf(True, False, True));
end;

procedure TAtlasBreakpointAnchorFlowTests.OutcomeNeedsExternalOrStored;
begin
  Assert.AreEqual<TAtlasAnchorOutcome>(TAtlasAnchorOutcome.Recapture,
    TAtlasBreakpointAnchorFlow.OutcomeOf(TAtlasAnchorStep.Keep, True, True));
  // Im Editor bearbeitet: Die IDE zieht den Haltepunkt selbst mit.
  Assert.AreEqual<TAtlasAnchorOutcome>(TAtlasAnchorOutcome.Recapture,
    TAtlasBreakpointAnchorFlow.OutcomeOf(TAtlasAnchorStep.Move, False, False));
  Assert.AreEqual<TAtlasAnchorOutcome>(TAtlasAnchorOutcome.Move,
    TAtlasBreakpointAnchorFlow.OutcomeOf(TAtlasAnchorStep.Move, True, False));
  Assert.AreEqual<TAtlasAnchorOutcome>(TAtlasAnchorOutcome.Orphan,
    TAtlasBreakpointAnchorFlow.OutcomeOf(TAtlasAnchorStep.Orphan, False, True));
end;

procedure TAtlasBreakpointAnchorFlowTests.SaveAfterInterval;
begin
  Assert.IsFalse(TAtlasBreakpointAnchorFlow.SaveDue(False, 10000, 0, 2000));
  Assert.IsFalse(TAtlasBreakpointAnchorFlow.SaveDue(True, 1999, 0, 2000));
  Assert.IsTrue(TAtlasBreakpointAnchorFlow.SaveDue(True, 2000, 0, 2000));
end;

procedure TAtlasBreakpointAnchorFlowTests.OldOrphanStaysUnlessNew;
begin
  Assert.IsTrue(TAtlasBreakpointAnchorFlow.KeepsOrphan(Orphan('Kunden.pas', 4), [Orphan('Kunden.pas', 5)]));
  Assert.IsFalse(TAtlasBreakpointAnchorFlow.KeepsOrphan(Orphan('Kunden.pas', 4), [Orphan('KUNDEN.PAS', 4)]));
  Assert.IsTrue(TAtlasBreakpointAnchorFlow.KeepsOrphan(Orphan('Kunden.pas', 4), nil));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreakpointAnchorFlowTests);

end.
