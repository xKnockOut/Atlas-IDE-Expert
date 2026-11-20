unit Atlas.Core.Debug.ParallelWatch.Tests;

// Tests für „Parallel auswerten“ (#866): Tabellenaufbau aus den Stapeln aller Threads, nicht gültige Ausdrücke,
// Ausblenden ohne eigenen Rahmen, Filter, Sortierung, markierte Threads oben; ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasParallelWatchTests = class
  public
    [Test]
    procedure RowsUseTopOwnFrame;
    [Test]
    procedure RowWithoutOwnCodeFallsBackToTopFrame;
    [Test]
    procedure InvalidCellShowsDash;
    [Test]
    procedure PendingCellIsEmpty;
    [Test]
    procedure ThreadsWithoutOwnFrameHiddenByDefault;
    [Test]
    procedure FilterKeepsMatchingRows;
    [Test]
    procedure FilterIgnoresCase;
    [Test]
    procedure SortNumbersByValue;
    [Test]
    procedure SortDescendingAndStable;
    [Test]
    procedure FlaggedThreadsFirst;
    [Test]
    procedure ToggledOrder;
    [Test]
    procedure AutomaticBelowLimit;
    [Test]
    procedure DeleteColumnRemovesCells;
    [Test]
    procedure ThreadColumnFallsBackToId;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Threads,
  Atlas.Core.Debug.Threads.Tests,
  Atlas.Core.Debug.ThreadMarks,
  Atlas.Core.Debug.ParallelWatch;

function Worker(AThreadId: Cardinal; const AName: string): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, AName, [
    'Winapi.Windows.Sleep|Winapi.Windows.pas|10',
    'Unit2.TWorker.Execute|C:\P\Unit2.pas|30|own',
    'System.Classes.ThreadProc|System.Classes.pas|900']);
end;

function Idle(AThreadId: Cardinal): TAtlasDebugThreadStack;
begin
  Result := TAtlasDebugTestStacks.Stack(AThreadId, '', [
    'ntdll.NtWaitForSingleObject', 'System.Classes.ThreadProc|System.Classes.pas|900']);
end;

/// <summary>Vier Arbeiter (Werte AValues in Spalte 0) und ein Leerlauf-Thread.</summary>
function Table(const AValues: array of string): TAtlasParallelRows;
var
  mStacks: TAtlasDebugThreadStacks;
  mIndex: Integer;
begin
  mStacks := nil;
  for mIndex := 0 to High(AValues) do
  begin
    mStacks := mStacks + [Worker(100 + Cardinal(mIndex), 'Arbeiter ' + IntToStr(mIndex))];
  end;
  mStacks := mStacks + [Idle(999)];
  Result := TAtlasParallelWatch.Rows(mStacks, 1, Default(TAtlasDebugThreadSet));
  for mIndex := 0 to High(AValues) do
  begin
    Result[mIndex].Cells[0] := TAtlasParallelCell.Create(True, AValues[mIndex]);
  end;
end;

function Ids(const ARows: TAtlasParallelRows; const AView: TArray<Integer>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex in AView do
  begin
    Result := Result + IntToStr(ARows[mIndex].ThreadId) + ' ';
  end;
  Result := Trim(Result);
end;

function Order(AColumn: Integer; ADescending: Boolean): TAtlasParallelOrder;
begin
  Result := TAtlasParallelOrder.None;
  Result.Column := AColumn;
  Result.Descending := ADescending;
end;

function Filter(AColumn: Integer; const AText: string): TAtlasParallelFilter;
begin
  Result := TAtlasParallelFilter.None;
  Result.Column := AColumn;
  Result.Text := AText;
end;

{ TAtlasParallelWatchTests }

procedure TAtlasParallelWatchTests.RowsUseTopOwnFrame;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['1']);
  Assert.AreEqual('C:\P\Unit2.pas', mRows[0].FileName);
  Assert.AreEqual(30, mRows[0].Line);
  Assert.AreEqual('Unit2.TWorker.Execute (Unit2.pas:30)', mRows[0].Place);
  Assert.IsTrue(mRows[0].HasOwn);
  Assert.AreEqual(1, Integer(Length(mRows[0].Cells)));
end;

procedure TAtlasParallelWatchTests.RowWithoutOwnCodeFallsBackToTopFrame;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['1']);
  Assert.IsFalse(mRows[1].HasOwn);
  // Oberster Rahmen mit Quelltext: dort wertet Atlas aus.
  Assert.AreEqual('System.Classes.pas', mRows[1].FileName);
  Assert.AreEqual('System.Classes.ThreadProc (System.Classes.pas:900)', mRows[1].Place);
end;

procedure TAtlasParallelWatchTests.InvalidCellShowsDash;
var
  mCell: TAtlasParallelCell;
begin
  mCell := TAtlasParallelCell.Create(False, 'Undeclared identifier: ''FAuftrag''');
  Assert.AreEqual(TAtlasParallelWatch.cInvalidText, mCell.Shown);
  Assert.AreEqual('Undeclared identifier: ''FAuftrag''', mCell.Text);
  Assert.AreEqual('42', TAtlasParallelCell.Create(True, '42').Shown);
end;

procedure TAtlasParallelWatchTests.PendingCellIsEmpty;
var
  mRows: TAtlasParallelRows;
begin
  mRows := TAtlasParallelWatch.Rows([Worker(1, '')], 2, Default(TAtlasDebugThreadSet));
  Assert.AreEqual('', mRows[0].ColumnText(TAtlasParallelWatch.cFirstValue + 1));
  Assert.AreEqual('', mRows[0].ColumnText(TAtlasParallelWatch.cFirstValue + 5));
end;

procedure TAtlasParallelWatchTests.ThreadsWithoutOwnFrameHiddenByDefault;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['1', '2']);
  Assert.AreEqual('100 101', Ids(mRows, TAtlasParallelWatch.View(mRows, False, TAtlasParallelFilter.None,
    TAtlasParallelOrder.None)));
  Assert.AreEqual('100 101 999', Ids(mRows, TAtlasParallelWatch.View(mRows, True, TAtlasParallelFilter.None,
    TAtlasParallelOrder.None)));
end;

procedure TAtlasParallelWatchTests.FilterKeepsMatchingRows;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['True', 'False', 'True', 'False']);
  Assert.AreEqual('100 102', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    Filter(TAtlasParallelWatch.cFirstValue, 'True'), TAtlasParallelOrder.None)));
  // Leerer Filter: alles.
  Assert.AreEqual('100 101 102 103', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    Filter(TAtlasParallelWatch.cFirstValue, '  '), TAtlasParallelOrder.None)));
end;

procedure TAtlasParallelWatchTests.FilterIgnoresCase;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['1', '2']);
  Assert.AreEqual('101', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    Filter(TAtlasParallelWatch.cThreadColumn, 'ARBEITER 1'), TAtlasParallelOrder.None)));
end;

procedure TAtlasParallelWatchTests.SortNumbersByValue;
var
  mRows: TAtlasParallelRows;
begin
  // Als Text stünde 10 vor 9; Text nach den Zahlen.
  mRows := Table(['10', 'abc', '9', '-1']);
  Assert.AreEqual('103 102 100 101', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    TAtlasParallelFilter.None, Order(TAtlasParallelWatch.cFirstValue, False))));
end;

procedure TAtlasParallelWatchTests.SortDescendingAndStable;
var
  mRows: TAtlasParallelRows;
begin
  mRows := Table(['1', '2', '1', '2']);
  // Gleichstand: Reihenfolge der IDE, auch absteigend.
  Assert.AreEqual('101 103 100 102', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    TAtlasParallelFilter.None, Order(TAtlasParallelWatch.cFirstValue, True))));
end;

procedure TAtlasParallelWatchTests.FlaggedThreadsFirst;
var
  mRows: TAtlasParallelRows;
  mFlagged: TAtlasDebugThreadSet;
begin
  mFlagged := Default(TAtlasDebugThreadSet);
  mFlagged.Add(103);
  mRows := TAtlasParallelWatch.Rows([Worker(100, ''), Worker(101, ''), Worker(102, ''), Worker(103, '')], 1,
    mFlagged);
  mRows[0].Cells[0] := TAtlasParallelCell.Create(True, '1');
  mRows[1].Cells[0] := TAtlasParallelCell.Create(True, '2');
  mRows[2].Cells[0] := TAtlasParallelCell.Create(True, '3');
  mRows[3].Cells[0] := TAtlasParallelCell.Create(True, '4');
  Assert.IsTrue(mRows[3].Flagged);
  Assert.AreEqual('103 100 101 102', Ids(mRows, TAtlasParallelWatch.View(mRows, False,
    TAtlasParallelFilter.None, Order(TAtlasParallelWatch.cFirstValue, False))));
end;

procedure TAtlasParallelWatchTests.ToggledOrder;
var
  mOrder: TAtlasParallelOrder;
begin
  mOrder := TAtlasParallelOrder.None.Toggled(2);
  Assert.AreEqual(2, mOrder.Column);
  Assert.IsFalse(mOrder.Descending);
  mOrder := mOrder.Toggled(2);
  Assert.IsTrue(mOrder.Descending);
  mOrder := mOrder.Toggled(3);
  Assert.AreEqual(3, mOrder.Column);
  Assert.IsFalse(mOrder.Descending);
end;

procedure TAtlasParallelWatchTests.AutomaticBelowLimit;
begin
  Assert.IsTrue(TAtlasParallelWatch.Automatic(TAtlasParallelWatch.cAutoLimit - 1));
  Assert.IsFalse(TAtlasParallelWatch.Automatic(TAtlasParallelWatch.cAutoLimit));
end;

procedure TAtlasParallelWatchTests.DeleteColumnRemovesCells;
var
  mRows: TAtlasParallelRows;
begin
  mRows := TAtlasParallelWatch.Rows([Worker(1, '')], 3, Default(TAtlasDebugThreadSet));
  mRows[0].Cells[0] := TAtlasParallelCell.Create(True, 'a');
  mRows[0].Cells[1] := TAtlasParallelCell.Create(True, 'b');
  mRows[0].Cells[2] := TAtlasParallelCell.Create(True, 'c');
  TAtlasParallelWatch.DeleteColumn(mRows, 1);
  Assert.AreEqual(2, Integer(Length(mRows[0].Cells)));
  Assert.AreEqual('c', mRows[0].Cells[1].Text);
  // Außerhalb: nichts.
  TAtlasParallelWatch.DeleteColumn(mRows, 5);
  Assert.AreEqual(2, Integer(Length(mRows[0].Cells)));
end;

procedure TAtlasParallelWatchTests.ThreadColumnFallsBackToId;
var
  mRows: TAtlasParallelRows;
begin
  mRows := TAtlasParallelWatch.Rows([Worker(4711, ''), Worker(1, 'Haupt')], 0, Default(TAtlasDebugThreadSet));
  Assert.AreEqual('4711', mRows[0].ColumnText(TAtlasParallelWatch.cThreadColumn));
  Assert.AreEqual('Haupt', mRows[1].ColumnText(TAtlasParallelWatch.cThreadColumn));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasParallelWatchTests);

end.
