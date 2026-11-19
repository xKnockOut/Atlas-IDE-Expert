unit Atlas.Core.Editor.LineTracking.Tests;

// Tests der Zeilenverfolgung (#1818): Marken folgen eingefügten und gelöschten
// Zeilen sofort, gelöschte Zeilen tragen keine Marke mehr, Kennungen der IDE
// unterscheiden Atlas von Fremden, Reset beginnt neu; ein Stand ohne
// Verfolgung bleibt bis zum nächsten; Anmeldungen je Puffer löschen nur sich
// selbst; Zeitmessung für viele Befunde.

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
    /// <summary>Der IDE nur Zeilen geben, die der Puffer hat, jede einmal: Eine Zeile hinter dem Ende brachte
    /// boreditu.dll beim Vergrößern der Tabelle zum Absturz.</summary>
    [Test]
    procedure TrackableOnlyLinesOfTheBuffer;
    [Test]
    procedure ChangedReachesFileAndChannel;
    [Test]
    procedure RemoveForgetsAllChannels;
    /// <summary>Current nur zum eigenen Stand: Ein neuer Stand verlangt neues Anmelden.</summary>
    [Test]
    procedure CurrentOnlyForItsStamp;
    /// <summary>Nach einem Fehler beim Anmelden: Der Stand gilt ohne Verfolgung, jede Zeile ist sie selbst, und
    /// Current liefert ihn, damit der Zeichner nicht bei jedem Zeichnen neu anmeldet.</summary>
    [Test]
    procedure UntrackedKeepsEveryLineUntilNextStamp;
    /// <summary>Zwei Beobachter für denselben Dateinamen: Das Ende des alten löscht die Anmeldung des neuen nicht.
    /// </summary>
    [Test]
    procedure ForgetOnlyOwnRegistration;
    /// <summary>Eine neue Anmeldung derselben Datei ersetzt die alte und lässt ihren Tracker los.</summary>
    [Test]
    procedure PutReplacesAndReleasesEarlierTracker;
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

type
  /// <summary>Platzhalter für den Tracker der IDE; zählt, wie viele noch leben.</summary>
  TFakeTracker = class(TInterfacedObject)
  public
    class var Alive: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  TFakeBuffers = TAtlasLineBuffers<IInterface>;
  TFakeEntry = TAtlasLineBuffer<IInterface>;

constructor TFakeTracker.Create;
begin
  inherited Create;
  Inc(Alive);
end;

destructor TFakeTracker.Destroy;
begin
  Dec(Alive);
  inherited Destroy;
end;

/// <summary>Anmeldung für AFileName mit eigenem Tracker und neuer Seriennummer.</summary>
function Registration(ABuffers: TFakeBuffers; const AFileName: string): TFakeEntry;
begin
  Result := Default(TFakeEntry);
  Result.FileName := AFileName;
  Result.Tracker := TFakeTracker.Create;
  Result.Serial := ABuffers.NextSerial;
end;

{ TAtlasLineTrackingTests }

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

procedure TAtlasLineTrackingTests.TrackableOnlyLinesOfTheBuffer;
var
  mLines: TArray<Integer>;
begin
  // Befund bis zum Dateiende: endet in Zeile 10 eines Puffers mit 10 Zeilen (0..9).
  mLines := TAtlasLineTracking.Trackable(TArray<Integer>.Create(8, 9, 10, 3, 3, -1, 9), 10);
  Assert.AreEqual(3, Integer(Length(mLines)));
  Assert.AreEqual(3, mLines[0]);
  Assert.AreEqual(8, mLines[1]);
  Assert.AreEqual(9, mLines[2]);
  Assert.AreEqual(0, Integer(Length(TAtlasLineTracking.Trackable(TArray<Integer>.Create(0, 1), 0))));
  Assert.AreEqual(0, Integer(Length(TAtlasLineTracking.Trackable(nil, 5))));
  mLines := nil;
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

procedure TAtlasLineTrackingTests.CurrentOnlyForItsStamp;
var
  mTracking: TAtlasLineTracking;
begin
  mTracking := TAtlasLineTracking.Create;
  try
    Assert.IsNull(mTracking.Current('C:\P\A.pas', 1, 5), 'nichts angemeldet');
    mTracking.Ensure('C:\P\A.pas', 1).Reset(5, [2]);
    Assert.IsNotNull(mTracking.Current('C:\P\A.PAS', 1, 5));
    Assert.IsNull(mTracking.Current('C:\P\A.pas', 1, 6), 'neuer Stand');
    Assert.IsNull(mTracking.Current('C:\P\A.pas', 2, 5), 'anderer Kanal');
  finally
    mTracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.UntrackedKeepsEveryLineUntilNextStamp;
var
  mTracking: TAtlasLineTracking;
  mLines: TAtlasTrackedLines;
  mLine, mSource: Integer;
begin
  mTracking := TAtlasLineTracking.Create;
  try
    mTracking.Ensure('C:\P\A.pas', 1).Reset(4, [3, 8]);
    mTracking.Changed('C:\P\A.pas', TAtlasLineTracking.Encode(1, 3), 5);
    mTracking.Untracked('C:\P\A.pas', 1, 5);
    mLines := mTracking.Current('C:\P\A.pas', 1, 5);
    Assert.IsNotNull(mLines, 'derselbe Stand gilt als angemeldet: kein neuer Versuch beim Zeichnen');
    Assert.AreEqual(0, Integer(Length(mLines.Lines)), 'nichts verfolgt');
    for mLine in TArray<Integer>.Create(0, 3, 5, 8, 100) do
    begin
      Assert.IsTrue(mLines.SourceAt(mLine, mSource));
      Assert.AreEqual(mLine, mSource, 'jede Zeile ist sie selbst');
    end;
    // Eine späte Meldung der IDE zu einer früher angemeldeten Zeile verschiebt nichts.
    mTracking.Changed('C:\P\A.pas', TAtlasLineTracking.Encode(1, 8), 2);
    Assert.IsFalse(mLines.HasMoved);
    Assert.IsNull(mTracking.Current('C:\P\A.pas', 1, 6), 'der nächste Stand meldet wieder an');
  finally
    mTracking.Free;
  end;
end;

procedure TAtlasLineTrackingTests.ForgetOnlyOwnRegistration;
var
  mBuffers: TFakeBuffers;
  mOld, mNew, mFound: TFakeEntry;
begin
  mBuffers := TFakeBuffers.Create;
  try
    mOld := Registration(mBuffers, 'C:\P\A.pas');
    mBuffers.Put(mOld);
    mNew := Registration(mBuffers, 'C:\P\a.PAS');
    mBuffers.Put(mNew);
    Assert.AreNotEqual(mOld.Serial, mNew.Serial);
    // Der alte Beobachter meldet sein Ende erst, als der neue Puffer schon angemeldet ist.
    Assert.IsFalse(mBuffers.Forget('C:\P\A.pas', mOld.Serial), 'fremde Anmeldung bleibt');
    Assert.IsTrue(mBuffers.TryGet('C:\P\A.pas', mFound));
    Assert.AreEqual(mNew.Serial, mFound.Serial);
    Assert.AreSame(mNew.Tracker, mFound.Tracker);
    Assert.IsTrue(mBuffers.Forget('C:\P\A.pas', mNew.Serial), 'eigene Anmeldung');
    Assert.IsFalse(mBuffers.TryGet('C:\P\A.pas', mFound));
    Assert.AreEqual(0, mBuffers.Count);
  finally
    mBuffers.Free;
  end;
  mOld := Default(TFakeEntry);
  mNew := Default(TFakeEntry);
  mFound := Default(TFakeEntry);
  Assert.AreEqual(0, TFakeTracker.Alive);
end;

procedure TAtlasLineTrackingTests.PutReplacesAndReleasesEarlierTracker;
var
  mBuffers: TFakeBuffers;
  mEntry: TFakeEntry;
  mEntries: TArray<TFakeEntry>;
begin
  mBuffers := TFakeBuffers.Create;
  try
    mEntry := Registration(mBuffers, 'C:\P\A.pas');
    mBuffers.Put(mEntry);
    mBuffers.Put(Registration(mBuffers, 'C:\P\B.pas'));
    mEntry := Registration(mBuffers, 'C:\P\A.pas');
    mBuffers.Put(mEntry);
    Assert.AreEqual(2, TFakeTracker.Alive, 'der Tracker der ersten Anmeldung ist losgelassen');
    mEntries := mBuffers.Entries;
    Assert.AreEqual(2, Integer(Length(mEntries)));
    Assert.IsTrue(mBuffers.TryGet('C:\P\A.pas', mEntry));
    Assert.AreEqual(3, mEntry.Serial);
  finally
    mBuffers.Free;
  end;
  mEntry := Default(TFakeEntry);
  mEntries := nil;
  Assert.AreEqual(0, TFakeTracker.Alive);
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
