unit Atlas.Core.Editor.LineTracking.Tests;

// Tests der Zeilenverfolgung (#1818): Marken folgen eingefügten und gelöschten
// Zeilen sofort, gelöschte Zeilen tragen keine Marke mehr, Kennungen der IDE
// unterscheiden Atlas von Fremden, Reset beginnt neu; Zeitmessung für viele
// Befunde.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasLineTrackingTests = class
  public
    [Test]
    procedure WithoutMovesEveryLineIsItself;
    /// <summary>Akzeptanz: drei Zeilen über einem Befund eingefügt, die Marke steht drei Zeilen tiefer.</summary>
    [Test]
    procedure FollowsInsertedLines;
    /// <summary>Rückgängig: die Marke kehrt zurück.</summary>
    [Test]
    procedure UndoBringsMarkBack;
    /// <summary>Akzeptanz: Zeile gelöscht, keine Marke, auch nicht auf der Folgezeile.</summary>
    [Test]
    procedure DeletedLineHasNoMark;
    [Test]
    procedure MergedLinesPreferSmallerSource;
    [Test]
    procedure UnknownSourceIsIgnored;
    [Test]
    procedure ResetStartsOver;
    [Test]
    procedure EncodeDecodeRoundTrip;
    [Test]
    procedure ForeignDataIsIgnored;
    [Test]
    procedure ChangedReachesFileAndChannel;
    [Test]
    procedure RemoveForgetsAllChannels;
    /// <summary>Zehntausend Befunde, Zeile ganz oben eingefügt: jede Meldung und das Zeichnen bleiben schnell.
    /// </summary>
    [Test]
    [Category('Benchmark')]
    procedure ManyLinesStayFast;
  end;

implementation

uses
  System.SysUtils,
  System.Diagnostics,
  Atlas.Core.Editor.LineTracking;

procedure TAtlasLineTrackingTests.WithoutMovesEveryLineIsItself;
var
  mLines: TAtlasTrackedLines;
  mSource: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [4, 9]);
    Assert.IsTrue(mLines.SourceAt(4, mSource));
    Assert.AreEqual(4, mSource);
    Assert.IsTrue(mLines.SourceAt(7, mSource), 'ohne Verschiebung gilt jede Zeile');
    Assert.AreEqual(7, mSource);
    Assert.IsFalse(mLines.HasMoved);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.FollowsInsertedLines;
var
  mLines: TAtlasTrackedLines;
  mSource, mCurrent: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [2, 5]);
    // Drei Zeilen über Zeile 2 eingefügt: Die IDE meldet beide Marken.
    mLines.Moved(2, 5);
    mLines.Moved(5, 8);
    Assert.IsTrue(mLines.HasMoved);
    Assert.IsTrue(mLines.SourceAt(5, mSource));
    Assert.AreEqual(2, mSource, 'Zeile 5 zeigt jetzt die Marke von Zeile 2');
    Assert.IsTrue(mLines.SourceAt(8, mSource));
    Assert.AreEqual(5, mSource);
    Assert.IsFalse(mLines.SourceAt(2, mSource), 'an der alten Stelle steht keine Marke mehr');
    Assert.IsTrue(mLines.CurrentOf(5, mCurrent));
    Assert.AreEqual(8, mCurrent);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.UndoBringsMarkBack;
var
  mLines: TAtlasTrackedLines;
  mSource: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [2]);
    mLines.Moved(2, 5);
    mLines.Moved(2, 2);
    Assert.IsTrue(mLines.SourceAt(2, mSource));
    Assert.AreEqual(2, mSource);
    Assert.IsFalse(mLines.SourceAt(5, mSource));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.DeletedLineHasNoMark;
var
  mLines: TAtlasTrackedLines;
  mSource, mCurrent: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [3, 6]);
    mLines.Moved(3, -1);
    mLines.Moved(6, 5);
    Assert.IsFalse(mLines.SourceAt(3, mSource), 'Folgezeile ohne Marke');
    Assert.IsTrue(mLines.SourceAt(5, mSource));
    Assert.AreEqual(6, mSource);
    Assert.IsFalse(mLines.CurrentOf(3, mCurrent));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.MergedLinesPreferSmallerSource;
var
  mLines: TAtlasTrackedLines;
  mSource: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [7, 4]);
    mLines.Moved(7, 4);
    Assert.IsTrue(mLines.SourceAt(4, mSource));
    Assert.AreEqual(4, mSource);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.UnknownSourceIsIgnored;
var
  mLines: TAtlasTrackedLines;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [1]);
    mLines.Moved(9, 12);
    Assert.IsFalse(mLines.HasMoved);
    Assert.AreEqual(1, Integer(Length(mLines.Lines)));
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.ResetStartsOver;
var
  mLines: TAtlasTrackedLines;
  mSource: Integer;
begin
  mLines := TAtlasTrackedLines.Create;
  try
    mLines.Reset(1, [1]);
    mLines.Moved(1, 3);
    mLines.Reset(2, [3]);
    Assert.AreEqual(2, mLines.Stamp);
    Assert.IsFalse(mLines.HasMoved);
    Assert.IsTrue(mLines.SourceAt(3, mSource));
    Assert.AreEqual(3, mSource);
  finally
    mLines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.EncodeDecodeRoundTrip;
var
  mChannel, mLine: Integer;
  mData: NativeInt;
begin
  mData := TAtlasLineTracking.Encode(TAtlasLineTracking.cProblems, 12345);
  Assert.IsTrue(mData > 0, 'auch unter Win32 positiv');
  Assert.IsTrue(TAtlasLineTracking.Decode(mData, mChannel, mLine));
  Assert.AreEqual(TAtlasLineTracking.cProblems, mChannel);
  Assert.AreEqual(12345, mLine);
  mData := TAtlasLineTracking.Encode(TAtlasLineTracking.cMaxChannel, TAtlasLineTracking.cMaxLine);
  Assert.IsTrue(TAtlasLineTracking.Decode(mData, mChannel, mLine));
  Assert.AreEqual(TAtlasLineTracking.cMaxChannel, mChannel);
  Assert.AreEqual(TAtlasLineTracking.cMaxLine, mLine);
  Assert.AreEqual(NativeInt(0), TAtlasLineTracking.Encode(0, 1), 'Kanal 0 gibt es nicht');
  Assert.AreEqual(NativeInt(0), TAtlasLineTracking.Encode(1, TAtlasLineTracking.cMaxLine + 1));
end;

procedure TAtlasLineTrackingTests.ForeignDataIsIgnored;
var
  mChannel, mLine: Integer;
begin
  Assert.IsFalse(TAtlasLineTracking.Decode(0, mChannel, mLine));
  Assert.IsFalse(TAtlasLineTracking.Decode(42, mChannel, mLine), 'Kennung eines anderen Experten');
  Assert.IsFalse(TAtlasLineTracking.Decode(-1, mChannel, mLine));
  Assert.IsFalse(TAtlasLineTracking.Decode(NativeInt($50000000), mChannel, mLine), 'ohne Kanal');
end;

procedure TAtlasLineTrackingTests.ChangedReachesFileAndChannel;
var
  mTracking: TAtlasLineTracking;
  mSource: Integer;
begin
  mTracking := TAtlasLineTracking.Create;
  try
    mTracking.Ensure('C:\P\A.pas', TAtlasLineTracking.cProblems).Reset(1, [2]);
    mTracking.Ensure('C:\P\B.pas', TAtlasLineTracking.cProblems).Reset(1, [2]);
    mTracking.Changed('c:\p\a.pas', TAtlasLineTracking.Encode(TAtlasLineTracking.cProblems, 2), 4);
    mTracking.Changed('c:\p\a.pas', 42, 9);
    Assert.IsTrue(mTracking.Find('C:\P\A.pas', TAtlasLineTracking.cProblems).SourceAt(4, mSource));
    Assert.AreEqual(2, mSource);
    Assert.IsFalse(mTracking.Find('C:\P\B.pas', TAtlasLineTracking.cProblems).HasMoved, 'andere Datei unberührt');
    Assert.IsNull(mTracking.Find('C:\P\A.pas', 2), 'anderer Kanal nicht angelegt');
  finally
    mTracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.RemoveForgetsAllChannels;
var
  mTracking: TAtlasLineTracking;
begin
  mTracking := TAtlasLineTracking.Create;
  try
    mTracking.Ensure('C:\P\A.pas', 1);
    mTracking.Ensure('C:\P\A.pas', 3);
    mTracking.Remove('C:\P\A.PAS');
    Assert.IsNull(mTracking.Find('C:\P\A.pas', 1));
    Assert.IsNull(mTracking.Find('C:\P\A.pas', 3));
  finally
    mTracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.ManyLinesStayFast;
const
  cCount = 10000;
var
  mLines: TAtlasTrackedLines;
  mAll: TArray<Integer>;
  mIndex, mSource: Integer;
  mWatch: TStopwatch;
begin
  SetLength(mAll, cCount);
  for mIndex := 0 to cCount - 1 do
  begin
    mAll[mIndex] := mIndex * 3;
  end;
  mLines := TAtlasTrackedLines.Create;
  try
    mWatch := TStopwatch.StartNew;
    mLines.Reset(1, mAll);
    // Eine Zeile ganz oben: Die IDE meldet jede Marke einzeln, danach zeichnet der Editor 60 Zeilen.
    for mIndex := 0 to cCount - 1 do
    begin
      mLines.Moved(mIndex * 3, mIndex * 3 + 1);
    end;
    for mIndex := 0 to 59 do
    begin
      mLines.SourceAt(mIndex, mSource);
    end;
    mWatch.Stop;
    Assert.IsTrue(mLines.SourceAt(1, mSource));
    Assert.AreEqual(0, mSource);
    Assert.IsTrue(mWatch.ElapsedMilliseconds < 200, Format('%d ms', [mWatch.ElapsedMilliseconds]));
  finally
    mLines.Free;
  end;
end;

end.
