unit Atlas.Core.Debug.ExceptionBarFlow.Tests;

// Tests für den Ablauf der Exception-Leiste (#783, #1967): Warten auf die Anzeige, Tasten, abgedeckter Halt,
// „Nur an dieser Stelle ignorieren“; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasExceptionBarFlowTests = class
  public
    [Test]
    procedure ShowsAfterQuietTicks;
    [Test]
    procedure DropsWhenGoneOrLate;
    [Test]
    procedure KeysOfBar;
    [Test]
    procedure CoversShownOrPendingStop;
    [Test]
    procedure IgnoreLocationNeedsProjectAndPlace;
  end;

implementation

uses
  Atlas.Core.Debug.ExceptionBarFlow;

{ TAtlasExceptionBarFlowTests }

procedure TAtlasExceptionBarFlowTests.ShowsAfterQuietTicks;
var
  mQuiet: Integer;
begin
  mQuiet := 0;
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Wait, TAtlasExceptionBarFlow.WaitStep(True, 10, 1000, False, mQuiet));
  // Ein modaler Dialog setzt die ruhigen Takte zurück.
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Wait, TAtlasExceptionBarFlow.WaitStep(True, 20, 1000, True, mQuiet));
  Assert.AreEqual(0, mQuiet);
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Wait, TAtlasExceptionBarFlow.WaitStep(True, 30, 1000, False, mQuiet));
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Go, TAtlasExceptionBarFlow.WaitStep(True, 40, 1000, False, mQuiet));
end;

procedure TAtlasExceptionBarFlowTests.DropsWhenGoneOrLate;
var
  mQuiet: Integer;
begin
  mQuiet := 5;
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Drop, TAtlasExceptionBarFlow.WaitStep(False, 10, 1000, False,
    mQuiet));
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Drop, TAtlasExceptionBarFlow.WaitStep(True, 1001, 1000, False,
    mQuiet));
  Assert.AreEqual<TAtlasBarWait>(TAtlasBarWait.Go, TAtlasExceptionBarFlow.WaitStep(True, 1000, 1000, False,
    mQuiet));
end;

procedure TAtlasExceptionBarFlowTests.KeysOfBar;
begin
  Assert.AreEqual<TAtlasBarKey>(TAtlasBarKey.Continue, TAtlasExceptionBarFlow.KeyOf(TAtlasExceptionBarFlow.cKeyF9));
  Assert.AreEqual<TAtlasBarKey>(TAtlasBarKey.BreakHere, TAtlasExceptionBarFlow.KeyOf(TAtlasExceptionBarFlow.cKeyF8));
  Assert.AreEqual<TAtlasBarKey>(TAtlasBarKey.BreakHere,
    TAtlasExceptionBarFlow.KeyOf(TAtlasExceptionBarFlow.cKeyEscape));
  Assert.AreEqual<TAtlasBarKey>(TAtlasBarKey.None, TAtlasExceptionBarFlow.KeyOf(Ord('A')));
end;

procedure TAtlasExceptionBarFlowTests.CoversShownOrPendingStop;
begin
  Assert.IsTrue(TAtlasExceptionBarFlow.Covers(True, 3, False, 0, 3));
  Assert.IsFalse(TAtlasExceptionBarFlow.Covers(False, 3, False, 0, 3));
  Assert.IsTrue(TAtlasExceptionBarFlow.Covers(False, 0, True, 4, 4));
  Assert.IsFalse(TAtlasExceptionBarFlow.Covers(True, 3, True, 4, 5));
end;

procedure TAtlasExceptionBarFlowTests.IgnoreLocationNeedsProjectAndPlace;
begin
  Assert.IsTrue(TAtlasExceptionBarFlow.CanIgnoreLocation(True, 'P.dproj', True));
  Assert.IsFalse(TAtlasExceptionBarFlow.CanIgnoreLocation(False, 'P.dproj', True));
  Assert.IsFalse(TAtlasExceptionBarFlow.CanIgnoreLocation(True, '', True));
  Assert.IsFalse(TAtlasExceptionBarFlow.CanIgnoreLocation(True, 'P.dproj', False));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasExceptionBarFlowTests);

end.
