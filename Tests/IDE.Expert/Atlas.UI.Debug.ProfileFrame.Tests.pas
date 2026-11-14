unit Atlas.UI.Debug.ProfileFrame.Tests;

// Fenster „Atlas: Profil“ (#2057), Oberfläche: Spalten allein und im
// Vergleich, Zeilen, Beschriftung des Knopfs während eines Laufs und die
// Ereignisse der Schalter.

interface

uses
  DUnitX.TestFramework,
  Atlas.UI.Strings;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasDebugProfileFrameTests = class
  private
    FLanguage: TAtlasLanguage;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ColumnsFollowCompare;
    [Test]
    procedure KeepsRows;
    [Test]
    procedure ToggleCaptionFollowsRun;
    [Test]
    procedure SwitchesReportChanges;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Debug.Profiler,
  Atlas.UI.Debug.ProfileFrame;

function Row(const ARoutine: string): TAtlasProfileRow;
begin
  Result := Default(TAtlasProfileRow);
  Result.Routine := ARoutine;
  Result.FileName := 'App.pas';
  Result.Line := 12;
  Result.Cells := TArray<string>.Create(ARoutine, '+1.0 %', '2.0 %', '+1.0 %');
end;

{ TAtlasDebugProfileFrameTests }

procedure TAtlasDebugProfileFrameTests.Setup;
begin
  FLanguage := TAtlasStrings.Language;
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasDebugProfileFrameTests.TearDown;
begin
  TAtlasStrings.Language := FLanguage;
end;

procedure TAtlasDebugProfileFrameTests.ColumnsFollowCompare;
var
  mFrame: TAtlasDebugProfileFrame;
begin
  mFrame := TAtlasDebugProfileFrame.Create(nil);
  try
    Assert.AreEqual(5, mFrame.List.Columns.Count, 'Methode, Unit, Eigen, Gesamt, Zeile');
    Assert.AreEqual('Eigen', mFrame.List.Columns[2].Caption);
    mFrame.ShowRows(nil, True);
    Assert.AreEqual(4, mFrame.List.Columns.Count, 'Methode, Vorher, Nachher, Änderung');
    Assert.AreEqual('Änderung', mFrame.List.Columns[3].Caption);
    mFrame.ShowRows(nil, False);
    Assert.AreEqual(5, mFrame.List.Columns.Count);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDebugProfileFrameTests.KeepsRows;
var
  mFrame: TAtlasDebugProfileFrame;
  mRow: TAtlasProfileRow;
begin
  mFrame := TAtlasDebugProfileFrame.Create(nil);
  try
    mFrame.ShowRows(TArray<TAtlasProfileRow>.Create(Row('App.A'), Row('App.B')), True);
    Assert.AreEqual(2, mFrame.RowCount);
    Assert.IsTrue(mFrame.TryRow(1, mRow));
    Assert.AreEqual('App.B', mRow.Routine);
    Assert.IsFalse(mFrame.TryRow(2, mRow), 'außerhalb');
    mFrame.SetSummary('Lauf');
    Assert.AreEqual('Lauf', mFrame.SummaryLabel.Caption);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDebugProfileFrameTests.ToggleCaptionFollowsRun;
var
  mFrame: TAtlasDebugProfileFrame;
begin
  mFrame := TAtlasDebugProfileFrame.Create(nil);
  try
    Assert.AreEqual('Profil starten', mFrame.ToggleButton.Caption);
    mFrame.SetRunning(True);
    Assert.AreEqual('Profil beenden', mFrame.ToggleButton.Caption);
    mFrame.SetRunning(False);
    Assert.AreEqual('Profil starten', mFrame.ToggleButton.Caption);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasDebugProfileFrameTests.SwitchesReportChanges;
var
  mFrame: TAtlasDebugProfileFrame;
  mChanges, mToggles, mReloads: Integer;
begin
  mChanges := 0;
  mToggles := 0;
  mReloads := 0;
  mFrame := TAtlasDebugProfileFrame.Create(nil);
  try
    mFrame.OnOptionsChange :=
      procedure
      begin
        Inc(mChanges);
      end;
    mFrame.OnToggle :=
      procedure
      begin
        Inc(mToggles);
      end;
    mFrame.OnReload :=
      procedure
      begin
        Inc(mReloads);
      end;
    mFrame.OwnOnlyCheck.Checked := True;
    mFrame.CompareCheck.Checked := True;
    Assert.AreEqual(2, mChanges);
    Assert.IsTrue(mFrame.OwnOnly);
    Assert.IsTrue(mFrame.CompareWanted);
    mFrame.ToggleButton.Click;
    mFrame.ReloadButton.Click;
    Assert.AreEqual(1, mToggles);
    Assert.AreEqual(1, mReloads);
  finally
    mFrame.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasDebugProfileFrameTests);

end.
