unit Atlas.Core.Status.Signal.Tests;

// Signalfarbe zum Zustand einer Statuszeile.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusSignalTests = class
  public
    [Test]
    procedure StatusStatesMapToSignals;
  end;

implementation

uses
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.Signal;

{ TAtlasStatusSignalTests }

procedure TAtlasStatusSignalTests.StatusStatesMapToSignals;
var
  mSignals: TAtlasSignals;
begin
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Ok, TAtlasStatusSignal.KindOf(TAtlasStatusState.Green));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Warn, TAtlasStatusSignal.KindOf(TAtlasStatusState.Yellow));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Error, TAtlasStatusSignal.KindOf(TAtlasStatusState.Red));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Idle, TAtlasStatusSignal.KindOf(TAtlasStatusState.Neutral));
  mSignals := TAtlasSignals.Light;
  Assert.AreEqual(mSignals.Get(TAtlasSignalKind.Error).Fill, TAtlasStatusSignal.Pick(mSignals,
    TAtlasStatusState.Red).Fill);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusSignalTests);

end.
