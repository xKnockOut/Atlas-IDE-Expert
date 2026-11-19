unit Atlas.Core.Debug.Elapsed.Tests;

// Tests für die Laufzeit zwischen Haltepunkten (#579): Anzeige am Haltepunkt und ab der Schwelle bei Schritten,
// Text, Verlauf der letzten Messungen mit Start- und Zielzeile, Verbergen beim Weiterlaufen.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Debug.Elapsed;

type
  [TestFixture]
  [Category('Atlas.IDE.Debugger')]
  TAtlasElapsedTests = class
  private
    FElapsed: TAtlasElapsed;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BreakpointAlwaysShown;
    [Test]
    procedure ShortStepHidden;
    [Test]
    procedure StepAboveThresholdShown;
    [Test]
    procedure TextOnlyAtStopLine;
    [Test]
    procedure HideKeepsHistory;
    [Test]
    procedure HistoryNewestFirstWithStartLine;
    [Test]
    procedure HistoryKeepsTwenty;
    [Test]
    procedure ClearForgetsStart;
    [Test]
    procedure FormatsUnits;
    [Test]
    procedure HistoryLineNamesFiles;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasElapsedTests }

procedure TAtlasElapsedTests.Setup;
begin
  FElapsed := TAtlasElapsed.Create;
end;

procedure TAtlasElapsedTests.TearDown;
begin
  FreeAndNil(FElapsed);
end;

procedure TAtlasElapsedTests.BreakpointAlwaysShown;
begin
  Assert.IsTrue(FElapsed.Add(200, 'C:\P\Unit1.pas', 9, True));
  Assert.AreEqual('+<1 ms', FElapsed.LineText('c:\p\unit1.pas', 9));
end;

procedure TAtlasElapsedTests.ShortStepHidden;
begin
  Assert.IsFalse(FElapsed.Add(999, 'C:\P\Unit1.pas', 9, False));
  Assert.AreEqual('', FElapsed.LineText('C:\P\Unit1.pas', 9));
  // Auch nicht gezeigte Messungen stehen im Verlauf.
  Assert.AreEqual(1, FElapsed.Count);
end;

procedure TAtlasElapsedTests.StepAboveThresholdShown;
begin
  Assert.IsTrue(FElapsed.Add(201500, 'C:\P\Unit1.pas', 9, False));
  Assert.AreEqual('+201 ms', FElapsed.LineText('C:\P\Unit1.pas', 9));
end;

procedure TAtlasElapsedTests.TextOnlyAtStopLine;
begin
  FElapsed.Add(5000, 'C:\P\Unit1.pas', 9, True);
  Assert.AreEqual('', FElapsed.LineText('C:\P\Unit1.pas', 8));
  Assert.AreEqual('', FElapsed.LineText('C:\P\Unit2.pas', 9));
end;

procedure TAtlasElapsedTests.HideKeepsHistory;
begin
  FElapsed.Add(5000, 'C:\P\Unit1.pas', 9, True);
  FElapsed.Hide;
  Assert.AreEqual('', FElapsed.LineText('C:\P\Unit1.pas', 9));
  Assert.AreEqual(1, FElapsed.Count);
end;

procedure TAtlasElapsedTests.HistoryNewestFirstWithStartLine;
var
  mEntries: TArray<TAtlasElapsedEntry>;
begin
  FElapsed.Add(1000, 'C:\P\Unit1.pas', 9, True);
  FElapsed.Add(2000, 'C:\P\Unit1.pas', 14, False);
  mEntries := FElapsed.Entries;
  Assert.AreEqual(2, Integer(Length(mEntries)));
  Assert.AreEqual<Int64>(2000, mEntries[0].Micros);
  Assert.AreEqual('C:\P\Unit1.pas', mEntries[0].FromFile);
  Assert.AreEqual(9, mEntries[0].FromLine);
  Assert.AreEqual(14, mEntries[0].ToLine);
  // Der erste Halt nach dem Start hat keinen Startort.
  Assert.AreEqual('', mEntries[1].FromFile);
  mEntries := nil;
end;

procedure TAtlasElapsedTests.HistoryKeepsTwenty;
var
  mIndex: Integer;
  mEntries: TArray<TAtlasElapsedEntry>;
begin
  for mIndex := 1 to TAtlasElapsed.cMaxEntries + 5 do
  begin
    FElapsed.Add(mIndex, 'C:\P\Unit1.pas', mIndex, False);
  end;
  mEntries := FElapsed.Entries;
  Assert.AreEqual(TAtlasElapsed.cMaxEntries, Integer(Length(mEntries)));
  Assert.AreEqual<Int64>(TAtlasElapsed.cMaxEntries + 5, mEntries[0].Micros);
  Assert.AreEqual<Int64>(6, mEntries[High(mEntries)].Micros);
  mEntries := nil;
end;

procedure TAtlasElapsedTests.ClearForgetsStart;
var
  mEntries: TArray<TAtlasElapsedEntry>;
begin
  FElapsed.Add(1000, 'C:\P\Unit1.pas', 9, True);
  FElapsed.Clear;
  Assert.AreEqual(0, FElapsed.Count);
  FElapsed.Add(1000, 'C:\P\Unit1.pas', 12, True);
  mEntries := FElapsed.Entries;
  Assert.AreEqual('', mEntries[0].FromFile);
  mEntries := nil;
end;

procedure TAtlasElapsedTests.FormatsUnits;
begin
  Assert.AreEqual('+<1 ms', TAtlasElapsed.Format(0));
  Assert.AreEqual('+1 ms', TAtlasElapsed.Format(1000));
  Assert.AreEqual('+9999 ms', TAtlasElapsed.Format(9999999));
  Assert.AreEqual('+10 s', TAtlasElapsed.Format(10000000));
  Assert.AreEqual('+59 s', TAtlasElapsed.Format(59999999));
  Assert.AreEqual('+2 min 5 s', TAtlasElapsed.Format(125000000));
end;

procedure TAtlasElapsedTests.HistoryLineNamesFiles;
var
  mEntry: TAtlasElapsedEntry;
begin
  mEntry := Default(TAtlasElapsedEntry);
  mEntry.Micros := 124000;
  mEntry.FromFile := 'C:\P\Unit1.pas';
  mEntry.FromLine := 116;
  mEntry.ToFile := 'C:\P\Unit1.pas';
  mEntry.ToLine := 122;
  Assert.AreEqual('+124 ms  Unit1.pas 117 → 123', TAtlasElapsed.HistoryLine(mEntry));
  mEntry.ToFile := 'C:\P\Unit2.pas';
  mEntry.ToLine := 39;
  Assert.AreEqual('+124 ms  Unit1.pas 117 → Unit2.pas 40', TAtlasElapsed.HistoryLine(mEntry));
  mEntry.FromFile := '';
  Assert.AreEqual('+124 ms  → Unit2.pas 40', TAtlasElapsed.HistoryLine(mEntry));
  mEntry := Default(TAtlasElapsedEntry);
end;

end.
