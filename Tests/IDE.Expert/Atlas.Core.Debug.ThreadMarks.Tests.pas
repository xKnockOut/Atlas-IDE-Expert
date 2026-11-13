unit Atlas.Core.Debug.ThreadMarks.Tests;

// Tests zu den Threads im Quelltext (#852): Zuordnung Thread → Zeile, markierte Threads zuerst und Buchführung
// markierter bzw. eingefrorener Threads, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugThreadMarksTests = class
  public
    [Test]
    procedure EightWorkersShareOneLine;
    [Test]
    procedure SkipsCurrentThread;
    [Test]
    procedure SkipsThreadsWithoutOwnCode;
    [Test]
    procedure FlaggedThreadsFirst;
    [Test]
    procedure FileNamesIgnoreCaseAndSlashes;
    [Test]
    procedure SetFollowsThreadId;
    [Test]
    procedure ToggleAndClear;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ThreadMarks;

function Worker(AThreadId: Cardinal; ALine: Integer): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', [
    'System.SyncObjs.TEvent.WaitFor|System.SyncObjs.pas|500',
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|' + IntToStr(ALine) + '|own',
    'System.Classes.TThread.Execute|System.Classes.pas|1000']);
end;

function NoFlags: TAtlasDebugThreadSet;
begin
  Result := Default(TAtlasDebugThreadSet);
end;

{ TAtlasDebugThreadMarksTests }

procedure TAtlasDebugThreadMarksTests.EightWorkersShareOneLine;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
  mIndex: Integer;
begin
  mStacks := [TAtlasDebugTestStacks.Stack(1, '', ['Project1|C:\P\Project1.dpr|10|own'])];
  for mIndex := 1 to 8 do
  begin
    mStacks := mStacks + [Worker(100 + Cardinal(mIndex), 30)];
  end;
  mStacks := mStacks + [Worker(200, 42)];
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, 0, NoFlags);
  Assert.AreEqual(2, Integer(Length(mMarks.Marks)));
  mIndex := mMarks.IndexAt('C:\P\Unit2.pas', 30);
  Assert.IsTrue(mIndex >= 0);
  Assert.AreEqual(8, Integer(Length(mMarks.Marks[mIndex].Threads)));
  Assert.AreEqual(1, mMarks.Marks[mIndex].Threads[0]);
  Assert.IsTrue(mMarks.IndexAt('C:\P\Unit2.pas', 42) >= 0);
  Assert.AreEqual(-1, mMarks.IndexAt('C:\P\Unit2.pas', 31));
  mStacks := nil;
  mMarks := Default(TAtlasDebugThreadMarks);
end;

procedure TAtlasDebugThreadMarksTests.SkipsCurrentThread;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
begin
  mStacks := [Worker(1, 30), Worker(2, 30)];
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, 1, NoFlags);
  Assert.AreEqual(1, Integer(Length(mMarks.Marks)));
  Assert.AreEqual(1, Integer(Length(mMarks.Marks[0].Threads)));
  Assert.AreEqual(0, mMarks.Marks[0].Threads[0]);
  mStacks := nil;
  mMarks := Default(TAtlasDebugThreadMarks);
end;

procedure TAtlasDebugThreadMarksTests.SkipsThreadsWithoutOwnCode;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
  mUnreadable: TAtlasDebugThreadStack;
begin
  mUnreadable := Worker(3, 30);
  mUnreadable.Readable := False;
  mStacks := [TAtlasDebugTestStacks.Stack(1, '', ['ntdll.NtWaitForSingleObject||0',
    'System.Classes.ThreadProc|System.Classes.pas|900']), mUnreadable];
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, -1, NoFlags);
  Assert.AreEqual(0, Integer(Length(mMarks.Marks)));
  Assert.IsFalse(mMarks.HasFile('C:\P\Unit2.pas'));
  mStacks := nil;
  mUnreadable := Default(TAtlasDebugThreadStack);
  mMarks := Default(TAtlasDebugThreadMarks);
end;

procedure TAtlasDebugThreadMarksTests.FlaggedThreadsFirst;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
  mFlags: TAtlasDebugThreadSet;
begin
  mStacks := [Worker(11, 30), Worker(12, 30), Worker(13, 30)];
  mFlags := NoFlags;
  mFlags.Add(13);
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, -1, mFlags);
  Assert.AreEqual(2, mMarks.Marks[0].Threads[0]);
  Assert.AreEqual(0, mMarks.Marks[0].Threads[1]);
  Assert.AreEqual(1, mMarks.Marks[0].Threads[2]);
  mStacks := nil;
  mMarks := Default(TAtlasDebugThreadMarks);
  mFlags.Clear;
end;

procedure TAtlasDebugThreadMarksTests.FileNamesIgnoreCaseAndSlashes;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
begin
  mStacks := [Worker(1, 30)];
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, -1, NoFlags);
  Assert.IsTrue(mMarks.HasFile('c:/p/UNIT2.pas'));
  Assert.AreEqual(0, mMarks.IndexAt('c:/p/unit2.PAS', 30));
  Assert.IsFalse(mMarks.HasFile('C:\P\Unit3.pas'));
  mStacks := nil;
  mMarks := Default(TAtlasDebugThreadMarks);
end;

procedure TAtlasDebugThreadMarksTests.SetFollowsThreadId;
var
  mStacks: TAtlasDebugThreadStacks;
  mFlags: TAtlasDebugThreadSet;
  mOrder: TArray<Integer>;
begin
  // Die IDE liefert die Threads beim nächsten Halt in anderer Reihenfolge: Die Markierung bleibt am Thread.
  mFlags := NoFlags;
  mFlags.Add(12);
  mStacks := [Worker(12, 30), Worker(11, 30)];
  mOrder := TAtlasDebugThreadMarks.Ordered(mStacks, [1, 0], mFlags);
  Assert.AreEqual(0, mOrder[0]);
  Assert.AreEqual(1, mOrder[1]);
  mStacks := nil;
  mOrder := nil;
  mFlags.Clear;
end;

procedure TAtlasDebugThreadMarksTests.ToggleAndClear;
var
  mFrozen: TAtlasDebugThreadSet;
begin
  mFrozen := NoFlags;
  Assert.IsTrue(mFrozen.Toggle(7));
  mFrozen.Add(7);
  mFrozen.Add(9);
  Assert.AreEqual(2, mFrozen.Count);
  Assert.IsFalse(mFrozen.Toggle(7));
  Assert.IsFalse(mFrozen.Contains(7));
  Assert.IsTrue(mFrozen.Contains(9));
  Assert.AreEqual(Cardinal(9), mFrozen.Ids[0]);
  mFrozen.Clear;
  Assert.AreEqual(0, mFrozen.Count);
end;

end.
