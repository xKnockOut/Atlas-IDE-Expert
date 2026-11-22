unit Atlas.Plugin.Status.Signal.Tests;

// Zuordnung der Statuszustände zu den Signalfarben (#1255).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasStatusSignalTests = class
  public
    [Test]
    procedure StatesMapToKinds;
    [Test]
    procedure ForStateTakesSignalOfKind;
  end;

implementation

uses
  Atlas.Plugin.Style.Signal,
  Atlas.Plugin.Status.Contract,
  Atlas.Plugin.Status.Signal;

procedure TAtlasStatusSignalTests.StatesMapToKinds;
begin
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Ok, TAtlasStatusSignal.KindOf(TAtlasStatusState.Green));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Warn, TAtlasStatusSignal.KindOf(TAtlasStatusState.Yellow));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Error, TAtlasStatusSignal.KindOf(TAtlasStatusState.Red));
  Assert.AreEqual<TAtlasSignalKind>(TAtlasSignalKind.Idle, TAtlasStatusSignal.KindOf(TAtlasStatusState.Neutral));
end;

procedure TAtlasStatusSignalTests.ForStateTakesSignalOfKind;
var
  mSignals: TAtlasSignals;
begin
  mSignals := TAtlasSignals.Light;
  Assert.AreEqual(mSignals.Get(TAtlasSignalKind.Error).Fill,
    TAtlasStatusSignal.ForState(mSignals, TAtlasStatusState.Red).Fill);
  mSignals := TAtlasSignals.Dark;
  Assert.AreEqual(mSignals.Get(TAtlasSignalKind.Ok).Ring,
    TAtlasStatusSignal.ForState(mSignals, TAtlasStatusState.Green).Ring);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasStatusSignalTests);

end.
