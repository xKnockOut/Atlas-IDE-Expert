unit Atlas.UI.Debug.ParallelStacksFrame.Tests;

// Fenster „Parallele Aufrufstapel“ (#837), Oberfläche: Baum mit Knotentexten, Filter melden sich, Enter meldet den
// gewählten Knoten, Statuszeile ohne Baum.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugParallelStacksFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FillsTreeFromBottom;
    [Test]
    procedure FiltersAndOpenReport;
    [Test]
    procedure StatusClearsTree;
  end;

implementation

uses
  System.SysUtils,
  Winapi.Windows,
  System.Classes,
  Vcl.Forms,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ParallelStacks,
  Atlas.UI.Debug.ParallelStacksFrame;

function Stacks: TAtlasDebugThreadStacks;
begin
  Result := [
    TAtlasDebugTestStacks.Stack(7, '', ['System.TMonitor.Enter', 'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own']),
    TAtlasDebugTestStacks.Stack(8, '', ['Unit2.TWorker.Step|C:\P\Unit2.pas|12|own',
      'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own'])];
end;

function Tree(const AStacks: TAtlasDebugThreadStacks): TAtlasDebugStackTree;
begin
  Result := TAtlasDebugStackTree.Build(AStacks, 1, TAtlasDebugStackTree.ParseRoutines(''),
    Default(TAtlasDebugStackFilter));
end;

{ TAtlasDebugParallelStacksFrameTests }

procedure TAtlasDebugParallelStacksFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugParallelStacksFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugParallelStacksFrameTests.FillsTreeFromBottom;
var
  mHost: TForm;
  mFrame: TAtlasDebugParallelStacksFrame;
  mStacks: TAtlasDebugThreadStacks;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugParallelStacksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mStacks := Stacks;
    mFrame.SetTree(mStacks, Tree(mStacks), '');
    Assert.AreEqual(3, mFrame.Tree.Items.Count);
    Assert.AreEqual('Unit2.TWorker.Execute (Unit2.pas:30) · 2 Threads', mFrame.Tree.Items[0].Text);
    Assert.AreEqual(2, mFrame.Tree.Items[0].Count);
    Assert.AreEqual('2 Threads, 1 wartend', mFrame.StatusLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugParallelStacksFrameTests.FiltersAndOpenReport;
var
  mHost: TForm;
  mFrame: TAtlasDebugParallelStacksFrame;
  mStacks: TAtlasDebugThreadStacks;
  mFilters, mOpened: Integer;
  mKey: Word;
begin
  mFilters := 0;
  mOpened := -1;
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugParallelStacksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mFrame.OnFilter :=
      procedure
      begin
        Inc(mFilters);
      end;
    mFrame.OnOpen :=
      procedure(ANode: Integer)
      begin
        mOpened := ANode;
      end;
    mStacks := Stacks;
    mFrame.SetTree(mStacks, Tree(mStacks), '');
    mFrame.WaitingOnlyCheck.Checked := True;
    Assert.AreEqual(1, mFilters);
    Assert.IsTrue(mFrame.Filter.WaitingOnly);
    Assert.IsFalse(mFrame.Filter.OwnCodeOnly);
    mFrame.Tree.Selected := mFrame.Tree.Items[0];
    mKey := VK_RETURN;
    mFrame.Tree.OnKeyDown(mFrame.Tree, mKey, []);
    Assert.AreEqual(0, mOpened);
    Assert.AreEqual('Threads: 7, 8', mFrame.ThreadsLabel.Caption);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasDebugParallelStacksFrameTests.StatusClearsTree;
var
  mHost: TForm;
  mFrame: TAtlasDebugParallelStacksFrame;
  mStacks: TAtlasDebugThreadStacks;
begin
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasDebugParallelStacksFrame.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.HandleNeeded;
    mStacks := Stacks;
    mFrame.SetTree(mStacks, Tree(mStacks), '');
    mFrame.ShowStatus('läuft');
    Assert.AreEqual(0, mFrame.Tree.Items.Count);
    Assert.AreEqual('läuft', mFrame.StatusLabel.Caption);
  finally
    mHost.Free;
  end;
end;

end.
