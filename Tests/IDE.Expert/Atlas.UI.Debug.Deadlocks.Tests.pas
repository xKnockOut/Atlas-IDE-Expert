unit Atlas.UI.Debug.Deadlocks.Tests;

// „Was wartet worauf?“ (#587), Texte: Thread mit Name und Hauptthread, Wartepunkt, Sprungziel und die Sätze der
// Muster, deutsch und englisch.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugWaitTextsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NamesThreadsAndMainThread;
    [Test]
    procedure DescribesWaitPoints;
    [Test]
    procedure ThreadItemNamesFirstOwnLine;
    [Test]
    procedure DestructorPatternNamesRule;
    [Test]
    procedure SameLockListsAllThreads;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.Deadlocks,
  Atlas.UI.Debug.Deadlocks;

function Report: TAtlasDebugWaitReport;
begin
  Result := TAtlasDebugWaitReport.Analyze([
    TAtlasDebugTestStacks.Stack(7, 'Worker', [
      ':77A1F0CC ntdll.NtWaitForSingleObject + 0xc',
      'System.Classes.TThread.Synchronize',
      'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own',
      'System.Classes.ThreadProc']),
    TAtlasDebugTestStacks.Stack(100, '', [
      'System.Classes.TThread.WaitFor',
      'System.Classes.TThread.Destroy',
      'Unit2.TWorker.Destroy|C:\P\Unit2.pas|50|own',
      'Project1.Project1|C:\P\Project1.dpr|19|own']),
    TAtlasDebugTestStacks.Stack(8, '', ['Unit3.Compute|C:\P\Unit3.pas|5|own']),
    TAtlasDebugTestStacks.Stack(9, '', [])]);
  Result.Stacks[3].Readable := False;
end;

function LockReport: TAtlasDebugWaitReport;
begin
  Result := TAtlasDebugWaitReport.Analyze([
    TAtlasDebugTestStacks.Stack(100, '', ['System.TMonitor.Enter', 'Unit3.TCache.Add|C:\P\Unit3.pas|12|own',
      'Project1.Project1|C:\P\Project1.dpr|19|own']),
    TAtlasDebugTestStacks.Stack(7, '', ['System.TMonitor.Enter', 'Unit3.TCache.Add|C:\P\Unit3.pas|12|own']),
    TAtlasDebugTestStacks.Stack(8, '', ['user32.GetMessageW'])]);
end;

{ TAtlasDebugWaitTextsTests }

procedure TAtlasDebugWaitTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugWaitTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugWaitTextsTests.NamesThreadsAndMainThread;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := Report;
  Assert.AreEqual('Was wartet worauf? (4 Threads)', TAtlasDebugWaitTexts.Title(mReport));
  Assert.AreEqual('7 „Worker“', TAtlasDebugWaitTexts.ThreadLabel(mReport, 0));
  Assert.AreEqual('100 (Hauptthread)', TAtlasDebugWaitTexts.ThreadLabel(mReport, 1));
end;

procedure TAtlasDebugWaitTextsTests.DescribesWaitPoints;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := Report;
  Assert.AreEqual('wartet in TThread.Synchronize', TAtlasDebugWaitTexts.WaitText(mReport, 0));
  Assert.AreEqual('wartet in TThread.WaitFor', TAtlasDebugWaitTexts.WaitText(mReport, 1));
  Assert.AreEqual('läuft', TAtlasDebugWaitTexts.WaitText(mReport, 2));
  Assert.AreEqual('Aufrufstapel nicht lesbar', TAtlasDebugWaitTexts.WaitText(mReport, 3));
  Assert.AreEqual('wartet auf Nachrichten', TAtlasDebugWaitTexts.WaitText(LockReport, 2));
end;

procedure TAtlasDebugWaitTextsTests.ThreadItemNamesFirstOwnLine;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := Report;
  Assert.AreEqual('Thread 7 „Worker“: wartet in TThread.Synchronize, bei TWorker.Execute (Unit2.pas:30)',
    TAtlasDebugWaitTexts.ThreadItem(mReport, 0));
  Assert.AreEqual('Thread 9: Aufrufstapel nicht lesbar', TAtlasDebugWaitTexts.ThreadItem(mReport, 3));
end;

procedure TAtlasDebugWaitTextsTests.DestructorPatternNamesRule;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := Report;
  Assert.AreEqual<TAtlasDebugDeadlockKind>(TAtlasDebugDeadlockKind.MainWaitsForSynchronize, mReport.Patterns[0].Kind);
  Assert.AreEqual('Verklemmung: Der Hauptthread wartet in TThread.WaitFor im Destruktor eines Threads, ' +
    'Thread 7 „Worker“ wartet in Synchronize auf den Hauptthread (Regel synchronize-in-destructor)',
    TAtlasDebugWaitTexts.PatternText(mReport, mReport.Patterns[0]));
end;

procedure TAtlasDebugWaitTextsTests.SameLockListsAllThreads;
var
  mReport: TAtlasDebugWaitReport;
begin
  mReport := LockReport;
  Assert.AreEqual(1, Integer(Length(mReport.Patterns)));
  Assert.AreEqual('2 Threads warten an derselben Sperre in TCache.Add: 100 (Hauptthread), 7 ' +
    '(wer sie hält, zeigt der Debugger nicht)', TAtlasDebugWaitTexts.PatternText(mReport, mReport.Patterns[0]));
end;

procedure TAtlasDebugWaitTextsTests.EnglishTexts;
var
  mReport: TAtlasDebugWaitReport;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  mReport := Report;
  Assert.AreEqual('7 “Worker”', TAtlasDebugWaitTexts.ThreadLabel(mReport, 0));
  Assert.AreEqual('Thread 100 (main thread): waiting in TThread.WaitFor, at TWorker.Destroy (Unit2.pas:50)',
    TAtlasDebugWaitTexts.ThreadItem(mReport, 1));
end;

end.
