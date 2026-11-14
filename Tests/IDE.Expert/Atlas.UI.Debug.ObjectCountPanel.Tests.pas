unit Atlas.UI.Debug.ObjectCountPanel.Tests;

// Bereich „Objekte zählen“ im Fenster „Atlas: Speicher“ (#858), Oberfläche: Tabelle mit Zuwachs oben,
// Zusammenfassung, Filter, Leeren, Knopf ruft OnCount, im Frame standardmäßig verborgen.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugObjectCountPanelTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ShowsGrowthFirst;
    [Test]
    procedure FirstCountHasNoGrowth;
    [Test]
    procedure FilterNarrowsRows;
    [Test]
    procedure ClearEmptiesTable;
    [Test]
    procedure ButtonCallsOnCount;
    [Test]
    procedure FrameShowsPanelOnlyWhenAsked;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.ObjectCount,
  Atlas.UI.Debug.ObjectCountPanel,
  Atlas.UI.Debug.MemoryFrame;

function Counted(const AItems: array of string; const ACounts: array of Integer): TAtlasObjectCount;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasObjectCount);
  Result.ScannedBytes := 2 * 1024 * 1024;
  SetLength(Result.Classes, Length(AItems));
  for mIndex := 0 to High(AItems) do
  begin
    Result.Classes[mIndex].Name := AItems[mIndex];
    Result.Classes[mIndex].Count := ACounts[mIndex];
    Result.Classes[mIndex].InstanceSize := 32;
  end;
end;

{ TAtlasDebugObjectCountPanelTests }

procedure TAtlasDebugObjectCountPanelTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugObjectCountPanelTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugObjectCountPanelTests.ShowsGrowthFirst;
var
  mPanel: TAtlasDebugObjectCountPanel;
begin
  mPanel := TAtlasDebugObjectCountPanel.Create(nil);
  try
    mPanel.SetCounts(Counted(['TKeep', 'TLeak'], [1000, 5]), Counted(['TKeep', 'TLeak'], [1000, 15]), True);
    Assert.AreEqual(3, mPanel.Grid.RowCount);
    Assert.AreEqual('TLeak', mPanel.Grid.Cells[0, 1]);
    Assert.AreEqual('15', mPanel.Grid.Cells[1, 1]);
    Assert.AreEqual('+10', mPanel.Grid.Cells[2, 1]);
    Assert.AreEqual('TKeep', mPanel.Grid.Cells[0, 2]);
    Assert.AreEqual('0', mPanel.Grid.Cells[2, 2]);
    Assert.StartsWith('1015 Objekte in 2 Klassen', mPanel.SummaryLabel.Caption);
    Assert.IsTrue(mPanel.SummaryLabel.Caption.EndsWith('gegenüber der vorigen Zählung.'),
      mPanel.SummaryLabel.Caption);
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasDebugObjectCountPanelTests.FirstCountHasNoGrowth;
var
  mPanel: TAtlasDebugObjectCountPanel;
begin
  mPanel := TAtlasDebugObjectCountPanel.Create(nil);
  try
    mPanel.SetCounts(Default(TAtlasObjectCount), Counted(['TA', 'TB'], [2, 9]), False);
    Assert.AreEqual('TB', mPanel.Grid.Cells[0, 1]);
    Assert.AreEqual('', mPanel.Grid.Cells[2, 1], 'ohne Basis kein Zuwachs');
    Assert.IsFalse(mPanel.SummaryLabel.Caption.Contains('vorigen'), mPanel.SummaryLabel.Caption);
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasDebugObjectCountPanelTests.FilterNarrowsRows;
var
  mPanel: TAtlasDebugObjectCountPanel;
  mRows: TArray<TAtlasObjectCountRow>;
begin
  mPanel := TAtlasDebugObjectCountPanel.Create(nil);
  try
    mPanel.SetCounts(Default(TAtlasObjectCount), Counted(['TKunde', 'TRechnung'], [2, 9]), False);
    mPanel.FilterEdit.Text := 'KUNDE';
    mRows := mPanel.Rows;
    Assert.AreEqual(1, Integer(Length(mRows)));
    Assert.AreEqual('TKunde', mRows[0].Name);
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasDebugObjectCountPanelTests.ClearEmptiesTable;
var
  mPanel: TAtlasDebugObjectCountPanel;
begin
  mPanel := TAtlasDebugObjectCountPanel.Create(nil);
  try
    mPanel.SetCounts(Default(TAtlasObjectCount), Counted(['TA', 'TB', 'TC'], [1, 2, 3]), False);
    mPanel.ClearCounts;
    Assert.AreEqual(2, mPanel.Grid.RowCount, 'Kopfzeile und eine leere Zeile');
    Assert.AreEqual('', mPanel.Grid.Cells[0, 1]);
    Assert.AreEqual('Klasse', mPanel.Grid.Cells[0, 0]);
    Assert.AreEqual('', mPanel.SummaryLabel.Caption);
    Assert.AreEqual(0, Integer(Length(mPanel.Rows)));
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasDebugObjectCountPanelTests.ButtonCallsOnCount;
var
  mPanel: TAtlasDebugObjectCountPanel;
  mCalls: Integer;
begin
  mCalls := 0;
  mPanel := TAtlasDebugObjectCountPanel.Create(nil);
  try
    mPanel.CountButton.Click;
    Assert.AreEqual(0, mCalls);
    mPanel.OnCount :=
      procedure
      begin
        Inc(mCalls);
      end;
    mPanel.CountButton.Click;
    Assert.AreEqual(1, mCalls);
    mPanel.ShowStatus('Nur angehalten');
    Assert.AreEqual('Nur angehalten', mPanel.SummaryLabel.Caption);
  finally
    mPanel.Free;
  end;
end;

procedure TAtlasDebugObjectCountPanelTests.FrameShowsPanelOnlyWhenAsked;
var
  mFrame: TAtlasDebugMemoryFrame;
begin
  mFrame := TAtlasDebugMemoryFrame.Create(nil);
  try
    Assert.IsNotNull(mFrame.ObjectCount);
    Assert.IsFalse(mFrame.ObjectCount.Visible, 'experimentell, standardmäßig verborgen');
    mFrame.ShowObjectCount(True);
    Assert.IsTrue(mFrame.ObjectCount.Visible);
    mFrame.ShowObjectCount(False);
    Assert.IsFalse(mFrame.ObjectCount.Visible);
  finally
    mFrame.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugObjectCountPanelTests);

end.
