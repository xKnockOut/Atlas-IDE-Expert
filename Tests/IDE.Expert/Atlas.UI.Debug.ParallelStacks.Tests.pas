unit Atlas.UI.Debug.ParallelStacks.Tests;

// Parallele Aufrufstapel (#837), Texte: Knoten mit Ort, Zahl der Threads und „wartend“, Threads eines Knotens und
// Statuszeile, deutsch und englisch.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasParallelStacksTextsTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure NodeTexts;
    [Test]
    procedure ThreadsAndStatus;
    [Test]
    procedure EnglishTexts;
  end;

implementation

uses
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ParallelStacks,
  Atlas.UI.Debug.ParallelStacks;

function Tree(out AStacks: TAtlasDebugThreadStacks): TAtlasDebugStackTree;
begin
  AStacks := [
    TAtlasDebugTestStacks.Stack(7, 'Worker', ['System.TMonitor.Enter', 'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own']),
    TAtlasDebugTestStacks.Stack(8, '', ['System.TMonitor.Enter', 'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own']),
    TAtlasDebugTestStacks.Stack(9, '', ['Unit2.TWorker.Step|C:\P\Unit2.pas|12|own',
      'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own'])];
  Result := TAtlasDebugStackTree.Build(AStacks, -1, TAtlasDebugStackTree.ParseRoutines(''),
    Default(TAtlasDebugStackFilter));
end;

{ TAtlasParallelStacksTextsTests }

procedure TAtlasParallelStacksTextsTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasParallelStacksTextsTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasParallelStacksTextsTests.NodeTexts;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
begin
  mTree := Tree(mStacks);
  // Wurzel: TWorker.Execute für alle drei; darüber TMonitor.Enter (zwei, wartend) und TWorker.Step (einer).
  Assert.AreEqual('Unit2.TWorker.Execute (Unit2.pas:30) · 3 Threads',
    TAtlasParallelStacksTexts.NodeText(mTree.Nodes[mTree.Roots[0]]));
  Assert.AreEqual('System.TMonitor.Enter · 2 Threads · wartend', TAtlasParallelStacksTexts.NodeText(mTree.Nodes[1]));
  Assert.AreEqual('Unit2.TWorker.Step (Unit2.pas:12) · 1 Thread', TAtlasParallelStacksTexts.NodeText(mTree.Nodes[2]));
end;

procedure TAtlasParallelStacksTextsTests.ThreadsAndStatus;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
begin
  mTree := Tree(mStacks);
  Assert.AreEqual('Threads: 7 „Worker“, 8', TAtlasParallelStacksTexts.ThreadsText(mTree.Nodes[1], mStacks));
  Assert.AreEqual('3 Threads, 2 wartend', TAtlasParallelStacksTexts.StatusText(mTree));
end;

procedure TAtlasParallelStacksTextsTests.EnglishTexts;
var
  mStacks: TAtlasDebugThreadStacks;
  mTree: TAtlasDebugStackTree;
begin
  TAtlasStrings.Language := TAtlasLanguage.English;
  mTree := Tree(mStacks);
  Assert.AreEqual('System.TMonitor.Enter · 2 threads · waiting', TAtlasParallelStacksTexts.NodeText(mTree.Nodes[1]));
  Assert.AreEqual('3 threads, 2 waiting', TAtlasParallelStacksTexts.StatusText(mTree));
end;

end.
