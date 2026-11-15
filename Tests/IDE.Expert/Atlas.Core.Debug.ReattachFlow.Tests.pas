unit Atlas.Core.Debug.ReattachFlow.Tests;

// Tests für die Entscheidungen von „Erneut anhängen“ außerhalb der Prozesswahl (#2171, #1967): Angebot nach dem Ende,
// Treffer des Wartens, Wechsel der Projektgruppe, gemerktes Programm, Vorschlag im Dateidialog; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasReattachFlowTests = class
  public
    [Test]
    procedure OffersWaitAfterAttachedEnd;
    [Test]
    procedure OnlyCurrentWaitCounts;
    [Test]
    procedure GroupChangeIgnoresCase;
    [Test]
    procedure LastAndDefaultExe;
  end;

implementation

uses
  Atlas.Core.Debug.ReattachFlow;

{ TAtlasReattachFlowTests }

procedure TAtlasReattachFlowTests.OffersWaitAfterAttachedEnd;
begin
  Assert.IsTrue(TAtlasReattachFlow.OffersWait('C:\Bin\Kunden.exe', False));
  Assert.IsFalse(TAtlasReattachFlow.OffersWait('C:\Bin\Kunden.exe', True));
  Assert.IsFalse(TAtlasReattachFlow.OffersWait('', False));
end;

procedure TAtlasReattachFlowTests.OnlyCurrentWaitCounts;
begin
  Assert.IsTrue(TAtlasReattachFlow.Counts(5, 5, True));
  Assert.IsFalse(TAtlasReattachFlow.Counts(4, 5, True));
  Assert.IsFalse(TAtlasReattachFlow.Counts(5, 5, False));
end;

procedure TAtlasReattachFlowTests.GroupChangeIgnoresCase;
begin
  Assert.IsFalse(TAtlasReattachFlow.GroupLeft(True, 'C:\P\Gruppe.groupproj', 'c:\p\gruppe.GROUPPROJ'));
  Assert.IsTrue(TAtlasReattachFlow.GroupLeft(True, '', 'C:\P\Gruppe.groupproj'));
  Assert.IsFalse(TAtlasReattachFlow.GroupLeft(False, '', 'C:\P\Gruppe.groupproj'));
  Assert.IsTrue(TAtlasReattachFlow.MenuStale('C:\P\Andere.groupproj', 'C:\P\Gruppe.groupproj'));
  Assert.IsFalse(TAtlasReattachFlow.MenuStale('C:\P\Gruppe.groupproj', 'C:\P\GRUPPE.groupproj'));
end;

procedure TAtlasReattachFlowTests.LastAndDefaultExe;
begin
  Assert.AreEqual('B.exe', TAtlasReattachFlow.LastOf(['B.exe', 'A.exe']));
  Assert.AreEqual('', TAtlasReattachFlow.LastOf(nil));
  Assert.AreEqual('B.exe', TAtlasReattachFlow.DefaultExe('B.exe', 'P.exe'));
  Assert.AreEqual('P.exe', TAtlasReattachFlow.DefaultExe('', 'P.exe'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasReattachFlowTests);

end.
