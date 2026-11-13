unit Atlas.Core.Debug.ParallelStacks.Tests;

// Tests zu den parallelen Aufrufstapeln (#837): Zusammenführen der Stapel zum Baum, wartende Threads und Filter,
// ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugParallelStacksTests = class
  public
    [Test]
    procedure TenWorkersShareOneNode;
    [Test]
    procedure WaitingThreadsFormTwoBranches;
    [Test]
    procedure MarksCurrentThread;
    [Test]
    procedure OwnCodeOnlyHidesLibraryFrames;
    [Test]
    procedure WaitingOnlyKeepsWaitingThreads;
    [Test]
    procedure SkipsUnreadableStacks;
    [Test]
    procedure WaitRoutinesFromSetting;
    [Test]
    procedure WaitAboveOwnCodeOnly;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ParallelStacks;

function Stack(AThreadId: Cardinal; const AFrames: array of string): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', AFrames);
end;

function Worker(AThreadId: Cardinal; const ATop: string): TAtlasDebugThreadStack;
begin
  Result := Stack(AThreadId, [ATop,
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own',
    'System.Classes.TThread.Execute|System.Classes.pas|1000',
    'System.Classes.ThreadProc|System.Classes.pas|900']);
end;

function Routines: TArray<string>;
begin
  Result := TAtlasDebugStackTree.ParseRoutines('');
end;

function NoFilter: TAtlasDebugStackFilter;
begin
  Result := Default(TAtlasDebugStackFilter);
end;

/// <summary>Knoten, dessen Routine auf ARoutine endet; -1 ohne.</summary>
function NodeOf(const ATree: TAtlasDebugStackTree; const ARoutine: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ATree.Nodes) do
  begin
    if TAtlasDebugWaits.Matches(ATree.Nodes[mIndex].Frame.Routine, ARoutine) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

{ TAtlasDebugParallelStacksTests }

procedure TAtlasDebugParallelStacksTests.TenWorkersShareOneNode;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
  mIndex, mNode: Integer;
begin
  mStacks := nil;
  for mIndex := 1 to 10 do
  begin
    mStacks := mStacks + [Worker(mIndex, 'Unit2.TWorker.Step|C:\P\Unit2.pas|12|own')];
  end;
  mTree := TAtlasDebugStackTree.Build(mStacks, -1, Routines, NoFilter);
  Assert.AreEqual(1, Integer(Length(mTree.Roots)));
  Assert.AreEqual(4, Integer(Length(mTree.Nodes)));
  mNode := NodeOf(mTree, 'TWorker.Execute');
  Assert.AreEqual(10, Integer(Length(mTree.Nodes[mNode].Threads)));
  Assert.AreEqual(0, mTree.Nodes[mNode].Waiting);
end;

procedure TAtlasDebugParallelStacksTests.WaitingThreadsFormTwoBranches;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
  mIndex, mExecute, mMonitor, mSleep: Integer;
begin
  mStacks := nil;
  for mIndex := 1 to 8 do
  begin
    mStacks := mStacks + [Worker(mIndex, 'System.TMonitor.Enter|System.pas|500')];
  end;
  mStacks := mStacks + [Worker(9, 'System.SysUtils.Sleep|System.SysUtils.pas|700')];
  mTree := TAtlasDebugStackTree.Build(mStacks, -1, Routines, NoFilter);
  mExecute := NodeOf(mTree, 'TWorker.Execute');
  Assert.AreEqual(2, Integer(Length(mTree.Nodes[mExecute].Children)));
  mMonitor := NodeOf(mTree, 'TMonitor.Enter');
  mSleep := NodeOf(mTree, 'Sleep');
  Assert.AreEqual(8, Integer(Length(mTree.Nodes[mMonitor].Threads)));
  Assert.IsTrue(mTree.Nodes[mMonitor].AllWaiting);
  Assert.IsTrue(mTree.Nodes[mSleep].AllWaiting);
  Assert.IsTrue(mTree.Nodes[mExecute].AllWaiting);
end;

procedure TAtlasDebugParallelStacksTests.MarksCurrentThread;
var
  mTree: TAtlasDebugStackTree;
begin
  mTree := TAtlasDebugStackTree.Build([Worker(1, 'Unit2.TWorker.Step|C:\P\Unit2.pas|12|own'),
    Worker(2, 'Unit2.TWorker.Other|C:\P\Unit2.pas|20|own')], 1, Routines, NoFilter);
  Assert.IsTrue(mTree.Nodes[NodeOf(mTree, 'TWorker.Other')].Current);
  Assert.IsFalse(mTree.Nodes[NodeOf(mTree, 'TWorker.Step')].Current);
  Assert.IsTrue(mTree.Nodes[NodeOf(mTree, 'TWorker.Execute')].Current);
end;

procedure TAtlasDebugParallelStacksTests.OwnCodeOnlyHidesLibraryFrames;
var
  mFilter: TAtlasDebugStackFilter;
  mTree: TAtlasDebugStackTree;
begin
  mFilter := NoFilter;
  mFilter.OwnCodeOnly := True;
  mTree := TAtlasDebugStackTree.Build([Worker(1, 'System.TMonitor.Enter|System.pas|500')], -1, Routines, mFilter);
  Assert.AreEqual(1, Integer(Length(mTree.Nodes)));
  Assert.AreEqual('Unit2.TWorker.Execute', mTree.Nodes[0].Frame.Routine);
  // Gewartet wird trotzdem: der Filter ändert nur die Anzeige.
  Assert.IsTrue(mTree.Nodes[0].AllWaiting);
end;

procedure TAtlasDebugParallelStacksTests.WaitingOnlyKeepsWaitingThreads;
var
  mFilter: TAtlasDebugStackFilter;
  mTree: TAtlasDebugStackTree;
begin
  mFilter := NoFilter;
  mFilter.WaitingOnly := True;
  mTree := TAtlasDebugStackTree.Build([Worker(1, 'Unit2.TWorker.Step|C:\P\Unit2.pas|12|own'),
    Worker(2, 'System.TMonitor.Enter|System.pas|500')], -1, Routines, mFilter);
  Assert.AreEqual(1, Integer(Length(mTree.Nodes[NodeOf(mTree, 'TWorker.Execute')].Threads)));
  Assert.AreEqual(-1, NodeOf(mTree, 'TWorker.Step'));
  Assert.IsFalse(mTree.Waiting[0]);
  Assert.IsTrue(mTree.Waiting[1]);
end;

procedure TAtlasDebugParallelStacksTests.SkipsUnreadableStacks;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
begin
  mStacks := [Worker(1, 'System.TMonitor.Enter|System.pas|500'), Stack(2, [])];
  mStacks[1].Readable := False;
  mTree := TAtlasDebugStackTree.Build(mStacks, -1, Routines, NoFilter);
  Assert.AreEqual(1, Integer(Length(mTree.Nodes[mTree.Roots[0]].Threads)));
  Assert.IsFalse(mTree.Waiting[1]);
end;

procedure TAtlasDebugParallelStacksTests.WaitRoutinesFromSetting;
var
  mRoutines: TArray<string>;
begin
  mRoutines := TAtlasDebugStackTree.ParseRoutines(' TMonitor.Enter ; ;MyLock.Acquire ');
  Assert.AreEqual(2, Integer(Length(mRoutines)));
  Assert.AreEqual('TMonitor.Enter', mRoutines[0]);
  Assert.AreEqual('MyLock.Acquire', mRoutines[1]);
  Assert.IsTrue(Pos('TMonitor.Enter', TAtlasDebugStackTree.DefaultRoutinesText) > 0);
  Assert.AreEqual(0, Pos('GetMessage', TAtlasDebugStackTree.DefaultRoutinesText));
  Assert.IsTrue(TAtlasDebugStackTree.IsWaiting(Worker(1, 'Unit3.MyLock.Acquire'), mRoutines));
  Assert.IsFalse(TAtlasDebugStackTree.IsWaiting(Worker(1, 'System.SysUtils.Sleep'), mRoutines));
end;

procedure TAtlasDebugParallelStacksTests.WaitAboveOwnCodeOnly;
begin
  // Ein Sleep unterhalb des eigenen Codes (der Aufrufer) zählt nicht.
  Assert.IsFalse(TAtlasDebugStackTree.IsWaiting(Stack(1, ['Unit2.Compute|C:\P\Unit2.pas|5|own',
    'System.SysUtils.Sleep']), Routines));
end;

end.
