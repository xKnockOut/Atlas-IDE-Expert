unit Atlas.Core.Debug.ThreadsInSourceFlow.Tests;

// Tests für die Entscheidungen von „Threads im Quelltext“ außerhalb der Marken (#852, #1967): Lesen der Stapel,
// Threads einer Zeile, Auswahlliste und ihre Einträge; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasThreadsInSourceFlowTests = class
  public
    [Test]
    procedure ReadDoneAfterRetries;
    [Test]
    procedure ThreadsOfMarkOrCurrent;
    [Test]
    procedure PickByCount;
    [Test]
    procedure TargetsAndAllEntry;
  end;

implementation

uses
  Atlas.Core.Debug.ThreadMarks,
  Atlas.Core.Debug.ThreadsInSourceFlow;

function Marks: TAtlasDebugThreadMarks;
var
  mMark: TAtlasDebugThreadMark;
begin
  Result := Default(TAtlasDebugThreadMarks);
  mMark := Default(TAtlasDebugThreadMark);
  mMark.FileName := 'Kunden.pas';
  mMark.Line := 12;
  mMark.Threads := [3, 1];
  Result.Marks := [mMark];
end;

{ TAtlasThreadsInSourceFlowTests }

procedure TAtlasThreadsInSourceFlowTests.ReadDoneAfterRetries;
begin
  Assert.IsTrue(TAtlasThreadsInSourceFlow.ReadDone(False, 1, 10));
  Assert.IsFalse(TAtlasThreadsInSourceFlow.ReadDone(True, 10, 10));
  Assert.IsTrue(TAtlasThreadsInSourceFlow.ReadDone(True, 11, 10));
end;

procedure TAtlasThreadsInSourceFlowTests.ThreadsOfMarkOrCurrent;
var
  mThreads: TArray<Integer>;
begin
  mThreads := TAtlasThreadsInSourceFlow.ThreadsAt(Marks, 'Kunden.pas', 12);
  Assert.AreEqual(2, Integer(Length(mThreads)));
  Assert.AreEqual(3, mThreads[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasThreadsInSourceFlow.ThreadsAt(Marks, 'Kunden.pas', 13))));
  Assert.AreEqual(0, Integer(Length(TAtlasThreadsInSourceFlow.ThreadsAt(Marks, '', 12))));
  mThreads := TAtlasThreadsInSourceFlow.CurrentOnly(2);
  Assert.AreEqual(1, Integer(Length(mThreads)));
  Assert.AreEqual(2, mThreads[0]);
  Assert.AreEqual(0, Integer(Length(TAtlasThreadsInSourceFlow.CurrentOnly(-1))));
end;

procedure TAtlasThreadsInSourceFlowTests.PickByCount;
begin
  Assert.AreEqual<TAtlasThreadPick>(TAtlasThreadPick.NotStopped, TAtlasThreadsInSourceFlow.PickOf(False, True, 2));
  Assert.AreEqual<TAtlasThreadPick>(TAtlasThreadPick.NotStopped, TAtlasThreadsInSourceFlow.PickOf(True, False, 2));
  Assert.AreEqual<TAtlasThreadPick>(TAtlasThreadPick.Nothing, TAtlasThreadsInSourceFlow.PickOf(True, True, 0));
  Assert.AreEqual<TAtlasThreadPick>(TAtlasThreadPick.Direct, TAtlasThreadsInSourceFlow.PickOf(True, True, 1));
  Assert.AreEqual<TAtlasThreadPick>(TAtlasThreadPick.Menu, TAtlasThreadsInSourceFlow.PickOf(True, True, 2));
end;

procedure TAtlasThreadsInSourceFlowTests.TargetsAndAllEntry;
var
  mTargets: TArray<Integer>;
begin
  Assert.IsFalse(TAtlasThreadsInSourceFlow.OffersAll(TAtlasThreadAction.Switch));
  Assert.IsTrue(TAtlasThreadsInSourceFlow.OffersAll(TAtlasThreadAction.Freeze));
  mTargets := TAtlasThreadsInSourceFlow.Targets(TAtlasThreadsInSourceFlow.cAllTag, [4, 5]);
  Assert.AreEqual(2, Integer(Length(mTargets)));
  mTargets := TAtlasThreadsInSourceFlow.Targets(5, [4, 5]);
  Assert.AreEqual(1, Integer(Length(mTargets)));
  Assert.AreEqual(5, mTargets[0]);
  Assert.IsTrue(TAtlasThreadsInSourceFlow.ValidThread(1, 2));
  Assert.IsFalse(TAtlasThreadsInSourceFlow.ValidThread(2, 2));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasThreadsInSourceFlowTests);

end.
