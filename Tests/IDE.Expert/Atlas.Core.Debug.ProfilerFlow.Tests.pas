unit Atlas.Core.Debug.ProfilerFlow.Tests;

// Tests für die Entscheidungen des Profilers außerhalb von Protokoll und Tabelle (#2057, #1967): Knopf „Messen“,
// gewählte Messung, Datei der beendeten Messung, schon geladen, Zeile im Editor; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasProfilerFlowTests = class
  public
    [Test]
    procedure ToggleFollowsState;
    [Test]
    procedure RunActsAsToggleWhileMeasuring;
    [Test]
    procedure SelectsRunByFileName;
    [Test]
    procedure ResultFilePrefersPath;
    [Test]
    procedure LoadedOnlyWithSamePath;
    [Test]
    procedure EditorLineFromTableLine;
  end;

implementation

uses
  Atlas.Core.Debug.ProfilerFlow;

{ TAtlasProfilerFlowTests }

procedure TAtlasProfilerFlowTests.ToggleFollowsState;
begin
  Assert.AreEqual<TAtlasProfilerToggle>(TAtlasProfilerToggle.Ignore, TAtlasProfilerFlow.Toggle(True, True, 7));
  Assert.AreEqual<TAtlasProfilerToggle>(TAtlasProfilerToggle.Stop, TAtlasProfilerFlow.Toggle(False, True, 0));
  Assert.AreEqual<TAtlasProfilerToggle>(TAtlasProfilerToggle.NoProcess, TAtlasProfilerFlow.Toggle(False, False, 0));
  Assert.AreEqual<TAtlasProfilerToggle>(TAtlasProfilerToggle.Start, TAtlasProfilerFlow.Toggle(False, False, 7));
end;

procedure TAtlasProfilerFlowTests.RunActsAsToggleWhileMeasuring;
begin
  Assert.IsTrue(TAtlasProfilerFlow.ActsAsToggle(True, False));
  Assert.IsTrue(TAtlasProfilerFlow.ActsAsToggle(False, True));
  Assert.IsFalse(TAtlasProfilerFlow.ActsAsToggle(False, False));
end;

procedure TAtlasProfilerFlowTests.SelectsRunByFileName;
var
  mRuns: TArray<string>;
begin
  mRuns := ['C:\Cache\profile-2.json', 'C:\Cache\profile-1.json'];
  Assert.AreEqual(1, TAtlasProfilerFlow.SelectedRun(mRuns, 'PROFILE-1.json'));
  Assert.AreEqual(0, TAtlasProfilerFlow.SelectedRun(mRuns, ''));
  Assert.AreEqual(0, TAtlasProfilerFlow.SelectedRun(mRuns, 'profile-9.json'));
  Assert.AreEqual(-1, TAtlasProfilerFlow.SelectedRun(nil, 'profile-1.json'));
end;

procedure TAtlasProfilerFlowTests.ResultFilePrefersPath;
begin
  Assert.AreEqual('C:\Cache\p.json', TAtlasProfilerFlow.ResultFile('C:\Cache\p.json', 'p.json'));
  Assert.AreEqual('p.json', TAtlasProfilerFlow.ResultFile('', 'p.json'));
end;

procedure TAtlasProfilerFlowTests.LoadedOnlyWithSamePath;
begin
  Assert.IsTrue(TAtlasProfilerFlow.IsLoaded('C:\Cache\p.json', 'c:\cache\P.json'));
  Assert.IsFalse(TAtlasProfilerFlow.IsLoaded('C:\Cache\p.json', 'C:\Cache\q.json'));
  Assert.IsFalse(TAtlasProfilerFlow.IsLoaded('', ''));
end;

procedure TAtlasProfilerFlowTests.EditorLineFromTableLine;
begin
  Assert.AreEqual(41, TAtlasProfilerFlow.EditorLine(42));
  Assert.AreEqual(0, TAtlasProfilerFlow.EditorLine(1));
  Assert.AreEqual(0, TAtlasProfilerFlow.EditorLine(0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasProfilerFlowTests);

end.
