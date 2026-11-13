unit Atlas.UI.Debug.ThreadMarks.Tests;

// Tests zu den Texten der Threads im Quelltext (#852): Tooltip, Links und Hinweis „2 Threads eingefroren“.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasThreadMarkTextsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TitleCountsThreads;
    [Test]
    procedure LineShowsFlagWaitAndFrozen;
    [Test]
    procedure TipListsFlaggedFirst;
    [Test]
    procedure SwitchLinkAndFrozenText;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.UI.Debug.ThreadMarks;

function Worker(AThreadId: Cardinal; const AName: string): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, AName, [
    'System.SyncObjs.TEvent.WaitFor|System.SyncObjs.pas|500',
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own']);
end;

function Busy(AThreadId: Cardinal): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', ['Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own']);
end;

{ TAtlasThreadMarkTextsTests }

procedure TAtlasThreadMarkTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasThreadMarkTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasThreadMarkTextsTests.TitleCountsThreads;
begin
  Assert.AreEqual('Ein Thread steht hier', TAtlasThreadMarkTexts.TipTitle(1));
  Assert.AreEqual('8 Threads stehen hier', TAtlasThreadMarkTexts.TipTitle(8));
end;

procedure TAtlasThreadMarkTextsTests.LineShowsFlagWaitAndFrozen;
begin
  Assert.AreEqual(#$2691' 12 „Worker“ · wartet in TEvent.WaitFor · eingefroren',
    TAtlasThreadMarkTexts.ThreadLine(Worker(12, 'Worker'), True, True));
  Assert.AreEqual('13', TAtlasThreadMarkTexts.ThreadLine(Busy(13), False, False));
end;

procedure TAtlasThreadMarkTextsTests.TipListsFlaggedFirst;
var
  mStacks: TAtlasDebugThreadStacks;
  mMarks: TAtlasDebugThreadMarks;
  mFlagged, mFrozen: TAtlasDebugThreadSet;
begin
  mStacks := [Busy(11), Busy(12)];
  mFlagged := Default(TAtlasDebugThreadSet);
  mFrozen := Default(TAtlasDebugThreadSet);
  mFlagged.Add(12);
  mMarks := TAtlasDebugThreadMarks.Build(mStacks, -1, mFlagged);
  Assert.AreEqual(#$2691' 12' + sLineBreak + '11',
    TAtlasThreadMarkTexts.TipText(mStacks, mMarks.Marks[0], mFlagged, mFrozen));
  mStacks := nil;
  mMarks := Default(TAtlasDebugThreadMarks);
  mFlagged.Clear;
end;

procedure TAtlasThreadMarkTextsTests.SwitchLinkAndFrozenText;
begin
  Assert.AreEqual('Zu 12 „Worker“ wechseln', TAtlasThreadMarkTexts.SwitchLink(Worker(12, 'Worker')));
  Assert.AreEqual('1 Thread eingefroren', TAtlasThreadMarkTexts.FrozenText(1));
  Assert.AreEqual('2 Threads eingefroren', TAtlasThreadMarkTexts.FrozenText(2));
end;

end.
