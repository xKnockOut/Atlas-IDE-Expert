unit Atlas.Core.Debug.WhyHereFlow.Tests;

// Tests für „Warum bin ich hier?“ außerhalb der Blöcke (#1878, #2169, #1967): Reihenfolge der Teile, Text am
// Zeilenende, Klick auf den Text; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasWhyHereFlowTests = class
  public
    [Test]
    procedure WhyHereBeforeForecast;
    [Test]
    procedure NothingPending;
    [Test]
    procedure LineTextJoinsBoth;
    [Test]
    procedure ClickPrefersCalls;
  end;

implementation

uses
  Atlas.Core.Debug.WhyHere,
  Atlas.Core.Debug.Forecast,
  Atlas.Core.Debug.WhyHereFlow;

const
  cFile = 'C:\Src\Kunden.pas';
  cWhy = '{"format":1,"blocks":[{"kind":"if","line":3,"branch":"then","parts":[' +
    '{"kind":"value","text":"Aktiv","parent":-1}]}]}';
  cForecast = '{"format":1,"blocks":[{"kind":"if","line":5,"parts":[' +
    '{"kind":"value","text":"Fertig","parent":-1}],' +
    '"branches":[{"name":"then","from":6,"to":6,"labels":[]}]}]}';

{ TAtlasWhyHereFlowTests }

procedure TAtlasWhyHereFlowTests.WhyHereBeforeForecast;
var
  mWhy: TAtlasWhyHere;
  mForecast: TAtlasForecast;
  mBlocks: TAtlasWhyHereBlocks;
  mBranches: TArray<TAtlasForecastBranches>;
  mRef: TAtlasWhyHereRef;
  mIsForecast: Boolean;
begin
  mWhy := TAtlasWhyHere.Create;
  mForecast := TAtlasForecast.Create;
  try
    Assert.IsTrue(TAtlasWhyHere.ReadAnswerText(cWhy, mBlocks));
    mWhy.Start(cFile, mBlocks);
    Assert.IsTrue(TAtlasForecast.ReadAnswerText(cForecast, mBlocks, mBranches));
    mForecast.Start(cFile, mBlocks, mBranches);
    Assert.IsTrue(TAtlasWhyHereFlow.NextOf(mWhy, mForecast, mRef, mIsForecast));
    Assert.IsFalse(mIsForecast);
    Assert.AreEqual('Aktiv', mRef.Expression);
    mWhy.Put(mRef, 'True', True);
    Assert.IsTrue(TAtlasWhyHereFlow.NextOf(mWhy, mForecast, mRef, mIsForecast));
    Assert.IsTrue(mIsForecast);
    Assert.AreEqual('Fertig', mRef.Expression);
    mForecast.Put(mRef, 'False', True);
    Assert.IsFalse(TAtlasWhyHereFlow.NextOf(mWhy, mForecast, mRef, mIsForecast));
  finally
    mForecast.Free;
    mWhy.Free;
  end;
end;

procedure TAtlasWhyHereFlowTests.NothingPending;
var
  mWhy: TAtlasWhyHere;
  mForecast: TAtlasForecast;
  mRef: TAtlasWhyHereRef;
  mIsForecast: Boolean;
begin
  mWhy := TAtlasWhyHere.Create;
  mForecast := TAtlasForecast.Create;
  try
    Assert.IsFalse(TAtlasWhyHereFlow.NextOf(mWhy, mForecast, mRef, mIsForecast));
  finally
    mForecast.Free;
    mWhy.Free;
  end;
end;

procedure TAtlasWhyHereFlowTests.LineTextJoinsBoth;
begin
  Assert.AreEqual('A  B', TAtlasWhyHereFlow.LineText('A', 'B'));
  Assert.AreEqual('A', TAtlasWhyHereFlow.LineText('A', ''));
  Assert.AreEqual('B', TAtlasWhyHereFlow.LineText('', 'B'));
  Assert.AreEqual('', TAtlasWhyHereFlow.LineText('', ''));
end;

procedure TAtlasWhyHereFlowTests.ClickPrefersCalls;
begin
  Assert.AreEqual<TAtlasWhyHereClick>(TAtlasWhyHereClick.Calls, TAtlasWhyHereFlow.Click(2, '→ then'));
  Assert.AreEqual<TAtlasWhyHereClick>(TAtlasWhyHereClick.Forecast, TAtlasWhyHereFlow.Click(0, '→ then'));
  Assert.AreEqual<TAtlasWhyHereClick>(TAtlasWhyHereClick.None, TAtlasWhyHereFlow.Click(0, ''));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWhyHereFlowTests);

end.
