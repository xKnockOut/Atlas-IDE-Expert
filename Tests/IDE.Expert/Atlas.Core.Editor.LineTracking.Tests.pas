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
  Lines: TAtlasTrackedLines;
  Source: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [4, 9]);
    Assert.IsTrue(Lines.SourceAt(4, Source));
    Assert.AreEqual(4, Source);
    Assert.IsTrue(Lines.SourceAt(7, Source), 'ohne Verschiebung gilt jede Zeile');
    Assert.AreEqual(7, Source);
    Assert.IsFalse(Lines.HasMoved);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.FollowsInsertedLines;
var
  Lines: TAtlasTrackedLines;
  Source, Current: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [2, 5]);
    // Drei Zeilen über Zeile 2 eingefügt: Die IDE meldet beide Marken.
    Lines.Moved(2, 5);
    Lines.Moved(5, 8);
    Assert.IsTrue(Lines.HasMoved);
    Assert.IsTrue(Lines.SourceAt(5, Source));
    Assert.AreEqual(2, Source, 'Zeile 5 zeigt jetzt die Marke von Zeile 2');
    Assert.IsTrue(Lines.SourceAt(8, Source));
    Assert.AreEqual(5, Source);
    Assert.IsFalse(Lines.SourceAt(2, Source), 'an der alten Stelle steht keine Marke mehr');
    Assert.IsTrue(Lines.CurrentOf(5, Current));
    Assert.AreEqual(8, Current);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.UndoBringsMarkBack;
var
  Lines: TAtlasTrackedLines;
  Source: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [2]);
    Lines.Moved(2, 5);
    Lines.Moved(2, 2);
    Assert.IsTrue(Lines.SourceAt(2, Source));
    Assert.AreEqual(2, Source);
    Assert.IsFalse(Lines.SourceAt(5, Source));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.DeletedLineHasNoMark;
var
  Lines: TAtlasTrackedLines;
  Source, Current: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [3, 6]);
    Lines.Moved(3, -1);
    Lines.Moved(6, 5);
    Assert.IsFalse(Lines.SourceAt(3, Source), 'Folgezeile ohne Marke');
    Assert.IsTrue(Lines.SourceAt(5, Source));
    Assert.AreEqual(6, Source);
    Assert.IsFalse(Lines.CurrentOf(3, Current));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.MergedLinesPreferSmallerSource;
var
  Lines: TAtlasTrackedLines;
  Source: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [7, 4]);
    Lines.Moved(7, 4);
    Assert.IsTrue(Lines.SourceAt(4, Source));
    Assert.AreEqual(4, Source);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.UnknownSourceIsIgnored;
var
  Lines: TAtlasTrackedLines;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [1]);
    Lines.Moved(9, 12);
    Assert.IsFalse(Lines.HasMoved);
    Assert.AreEqual(1, Integer(Length(Lines.Lines)));
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.ResetStartsOver;
var
  Lines: TAtlasTrackedLines;
  Source: Integer;
begin
  Lines := TAtlasTrackedLines.Create;
  try
    Lines.Reset(1, [1]);
    Lines.Moved(1, 3);
    Lines.Reset(2, [3]);
    Assert.AreEqual(2, Lines.Stamp);
    Assert.IsFalse(Lines.HasMoved);
    Assert.IsTrue(Lines.SourceAt(3, Source));
    Assert.AreEqual(3, Source);
  finally
    Lines.Free;
  end;
end;

procedure TAtlasLineTrackingTests.EncodeDecodeRoundTrip;
var
  Channel, Line: Integer;
  Data: NativeInt;
begin
  Data := TAtlasLineTracking.Encode(TAtlasLineTracking.cProblems, 12345);
  Assert.IsTrue(Data > 0, 'auch unter Win32 positiv');
  Assert.IsTrue(TAtlasLineTracking.Decode(Data, Channel, Line));
  Assert.AreEqual(TAtlasLineTracking.cProblems, Channel);
  Assert.AreEqual(12345, Line);
  Data := TAtlasLineTracking.Encode(TAtlasLineTracking.cMaxChannel, TAtlasLineTracking.cMaxLine);
  Assert.IsTrue(TAtlasLineTracking.Decode(Data, Channel, Line));
  Assert.AreEqual(TAtlasLineTracking.cMaxChannel, Channel);
  Assert.AreEqual(TAtlasLineTracking.cMaxLine, Line);
  Assert.AreEqual(NativeInt(0), TAtlasLineTracking.Encode(0, 1), 'Kanal 0 gibt es nicht');
  Assert.AreEqual(NativeInt(0), TAtlasLineTracking.Encode(1, TAtlasLineTracking.cMaxLine + 1));
end;

procedure TAtlasLineTrackingTests.ForeignDataIsIgnored;
var
  Channel, Line: Integer;
begin
  Assert.IsFalse(TAtlasLineTracking.Decode(0, Channel, Line));
  Assert.IsFalse(TAtlasLineTracking.Decode(42, Channel, Line), 'Kennung eines anderen Experten');
  Assert.IsFalse(TAtlasLineTracking.Decode(-1, Channel, Line));
  Assert.IsFalse(TAtlasLineTracking.Decode(NativeInt($50000000), Channel, Line), 'ohne Kanal');
end;

procedure TAtlasLineTrackingTests.ChangedReachesFileAndChannel;
var
  Tracking: TAtlasLineTracking;
  Source: Integer;
begin
  Tracking := TAtlasLineTracking.Create;
  try
    Tracking.Ensure('C:\P\A.pas', TAtlasLineTracking.cProblems).Reset(1, [2]);
    Tracking.Ensure('C:\P\B.pas', TAtlasLineTracking.cProblems).Reset(1, [2]);
    Tracking.Changed('c:\p\a.pas', TAtlasLineTracking.Encode(TAtlasLineTracking.cProblems, 2), 4);
    Tracking.Changed('c:\p\a.pas', 42, 9);
    Assert.IsTrue(Tracking.Find('C:\P\A.pas', TAtlasLineTracking.cProblems).SourceAt(4, Source));
    Assert.AreEqual(2, Source);
    Assert.IsFalse(Tracking.Find('C:\P\B.pas', TAtlasLineTracking.cProblems).HasMoved, 'andere Datei unberührt');
    Assert.IsNull(Tracking.Find('C:\P\A.pas', 2), 'anderer Kanal nicht angelegt');
  finally
    Tracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.RemoveForgetsAllChannels;
var
  Tracking: TAtlasLineTracking;
begin
  Tracking := TAtlasLineTracking.Create;
  try
    Tracking.Ensure('C:\P\A.pas', 1);
    Tracking.Ensure('C:\P\A.pas', 3);
    Tracking.Remove('C:\P\A.PAS');
    Assert.IsNull(Tracking.Find('C:\P\A.pas', 1));
    Assert.IsNull(Tracking.Find('C:\P\A.pas', 3));
  finally
    Tracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.ManyLinesStayFast;
const
  cCount = 10000;
var
  Lines: TAtlasTrackedLines;
  All: TArray<Integer>;
  Index, Source: Integer;
  Watch: TStopwatch;
begin
  SetLength(All, cCount);
  for Index := 0 to cCount - 1 do
  begin
    All[Index] := Index * 3;
  end;
  Lines := TAtlasTrackedLines.Create;
  try
    Watch := TStopwatch.StartNew;
    Lines.Reset(1, All);
    // Eine Zeile ganz oben: Die IDE meldet jede Marke einzeln, danach zeichnet der Editor 60 Zeilen.
    for Index := 0 to cCount - 1 do
    begin
      Lines.Moved(Index * 3, Index * 3 + 1);
    end;
    for Index := 0 to 59 do
    begin
      Lines.SourceAt(Index, Source);
    end;
    Watch.Stop;
    Assert.IsTrue(Lines.SourceAt(1, Source));
    Assert.AreEqual(0, Source);
    Assert.IsTrue(Watch.ElapsedMilliseconds < 200, Format('%d ms', [Watch.ElapsedMilliseconds]));
  finally
    Lines.Free;
  end;
end;

end.
