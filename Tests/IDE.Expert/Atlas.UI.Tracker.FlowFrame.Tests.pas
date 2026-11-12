unit Atlas.UI.Tracker.FlowFrame.Tests;

// Tests des Fensters „Atlas-Ablauf“ (#2125) ohne IDE: Lage der Kästen
// (Hauptweg oben, Rest darunter), Treffer der Maus, Wege der Pfeile
// (benachbart gerade, weiter als Bogen, Rückweg unten, zwischen Zeilen),
// Texte der Kästen und der Liste sowie Filter der Liste nach Zustand.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasFlowFrameTests = class
  private
    FSaved: Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure LayoutRowsAndColumns;
    [Test]
    procedure HitTesting;
    [Test]
    procedure PathsBetweenBoxes;
    [Test]
    procedure BoxTexts;
    [Test]
    procedure FrameFiltersList;
    [Test]
    procedure NoticeHidesMap;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  System.DateUtils,
  Atlas.Core.Tracker.FlowMap,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.Strings,
  Atlas.UI.Tracker.FlowFrame;

function NowUtc: TDateTime;
begin
  Result := EncodeDateTime(2026, 3, 31, 12, 0, 0, 0);
end;

function Change(const AId, AKey: string; ADay: Word; const AFrom, ATo: string): TAtlasFlowChange;
begin
  Result := TAtlasFlowChange.Create(AId, AKey, EncodeDateTime(2026, 3, ADay, 12, 0, 0, 0), AFrom, ATo);
  Result.Created := EncodeDateTime(2026, 3, 1, 12, 0, 0, 0);
end;

/// <summary>Offen → In Arbeit → Prüfung → Fertig, ein Rückweg, „Später“ darunter, ATL-3 liegt in Prüfung.
/// </summary>
function Map: TAtlasFlowMap;
var
  mData: TAtlasFlowData;
  mLater, mStuck: TAtlasFlowIssue;
begin
  mData := TAtlasFlowData.Empty;
  mData.Days := 90;
  mData.Resolved := TArray<string>.Create('Fertig');
  mData.Changes := TArray<TAtlasFlowChange>.Create(Change('1', 'ATL-1', 2, 'Offen', 'In Arbeit'),
    Change('2', 'ATL-1', 4, 'In Arbeit', 'Prüfung'), Change('3', 'ATL-1', 6, 'Prüfung', 'Fertig'),
    Change('4', 'ATL-3', 2, 'Offen', 'In Arbeit'), Change('5', 'ATL-3', 3, 'In Arbeit', 'Prüfung'),
    Change('6', 'ATL-3', 5, 'Prüfung', 'In Arbeit'), Change('7', 'ATL-3', 6, 'In Arbeit', 'Prüfung'));
  mLater := TAtlasFlowIssue.Create('ATL-2', 'Später', 'Später');
  mLater.Created := NowUtc - 1;
  mStuck := TAtlasFlowIssue.Create('ATL-3', 'Liegt', 'Prüfung');
  mStuck.Mine := True;
  mStuck.Assignee := 'Marco';
  mData.Open := TArray<TAtlasFlowIssue>.Create(mLater, mStuck);
  Result := TAtlasFlowMap.Build(mData, NowUtc, 5);
end;

function Metrics: TAtlasFlowMetrics;
begin
  Result := TAtlasFlowMetrics.Create(15);
end;

{ TAtlasFlowFrameTests }

procedure TAtlasFlowFrameTests.Setup;
begin
  FSaved := Ord(TAtlasStrings.Language);
  TAtlasStrings.Language := TAtlasLanguage.German;
end;

procedure TAtlasFlowFrameTests.TearDown;
begin
  TAtlasStrings.Language := TAtlasLanguage(FSaved);
end;

procedure TAtlasFlowFrameTests.LayoutRowsAndColumns;
var
  mMap: TAtlasFlowMap;
  mLayout: TAtlasFlowLayout;
  mOpen, mWork, mLater: TRect;
begin
  mMap := Map;
  mLayout := TAtlasFlowLayout.Build(mMap, Metrics);
  Assert.AreEqual(Integer(Length(mMap.States)), Integer(Length(mLayout.Boxes)));
  mOpen := mLayout.Boxes[mMap.IndexOf('Offen')];
  mWork := mLayout.Boxes[mMap.IndexOf('In Arbeit')];
  mLater := mLayout.Boxes[mMap.IndexOf('Später')];
  Assert.AreEqual(mOpen.Top, mWork.Top, 'Hauptweg in einer Zeile');
  Assert.IsTrue(mWork.Left > mOpen.Right, 'von links nach rechts');
  Assert.AreEqual(Metrics.ColumnGap, mWork.Left - mOpen.Right);
  Assert.IsTrue(mLater.Top > mOpen.Bottom, 'Rest darunter');
  Assert.AreEqual(mOpen.Left, mLater.Left, 'Rest beginnt links');
  Assert.IsTrue(mOpen.Top >= Metrics.Margin + Metrics.ArcSpace, 'Platz für Bögen oben');
  Assert.IsTrue(mLayout.Width >= mLayout.Boxes[mMap.IndexOf('Fertig')].Right);
  Assert.IsTrue(mLayout.Height > mLater.Bottom);
end;

procedure TAtlasFlowFrameTests.HitTesting;
var
  mMap: TAtlasFlowMap;
  mLayout: TAtlasFlowLayout;
begin
  mMap := Map;
  mLayout := TAtlasFlowLayout.Build(mMap, Metrics);
  Assert.AreEqual(mMap.IndexOf('Prüfung'), mLayout.StateAt(mLayout.Boxes[mMap.IndexOf('Prüfung')].CenterPoint));
  Assert.AreEqual(-1, mLayout.StateAt(TPoint.Create(1, 1)));
end;

procedure TAtlasFlowFrameTests.PathsBetweenBoxes;
var
  mLeft, mRight, mFar, mBelow: TRect;
  mPath: TAtlasFlowPath;
begin
  mLeft := TRect.Create(0, 40, 100, 100);
  mRight := TRect.Create(160, 40, 260, 100);
  mFar := TRect.Create(480, 40, 580, 100);
  mBelow := TRect.Create(0, 160, 100, 220);
  // Benachbart vorwärts: gerade im oberen Drittel.
  mPath := TAtlasFlowPath.Build(mLeft, mRight, True, False, 14);
  Assert.AreEqual(Integer(2), Integer(Length(mPath.Points)));
  Assert.AreEqual(100, mPath.Points[0].X);
  Assert.AreEqual(160, mPath.Points[1].X);
  Assert.AreEqual(60, mPath.Points[0].Y);
  // Benachbart zurück: gerade im unteren Drittel, von links der rechten Box.
  mPath := TAtlasFlowPath.Build(mRight, mLeft, True, True, 14);
  Assert.AreEqual(160, mPath.Points[0].X);
  Assert.AreEqual(100, mPath.Points[1].X);
  Assert.AreEqual(80, mPath.Points[0].Y);
  // Weiter vorwärts: Bogen über der Zeile; zurück: darunter.
  mPath := TAtlasFlowPath.Build(mLeft, mFar, True, False, 14);
  Assert.AreEqual(Integer(4), Integer(Length(mPath.Points)));
  Assert.AreEqual(26, mPath.Points[1].Y);
  Assert.AreEqual(26, mPath.LabelPoint.Y);
  mPath := TAtlasFlowPath.Build(mFar, mLeft, True, True, 14);
  Assert.AreEqual(114, mPath.Points[1].Y);
  // Zwischen den Zeilen: von Kante zu Kante.
  mPath := TAtlasFlowPath.Build(mLeft, mBelow, False, False, 14);
  Assert.AreEqual(100, mPath.Points[0].Y);
  Assert.AreEqual(160, mPath.Points[1].Y);
  mPath := TAtlasFlowPath.Build(mBelow, mRight, False, False, 14);
  Assert.AreEqual(160, mPath.Points[0].Y);
  Assert.AreEqual(100, mPath.Points[1].Y);
end;

procedure TAtlasFlowFrameTests.BoxTexts;
var
  mMap: TAtlasFlowMap;
  mStuck: TAtlasFlowStuck;
begin
  mMap := Map;
  Assert.AreEqual('⌀ ' + FormatFloat('0.0', 2, FormatSettings) + ' Tage',
    TAtlasFlowTexts.Average(mMap.States[mMap.IndexOf('Prüfung')]));
  Assert.AreEqual('⌀ –', TAtlasFlowTexts.Average(mMap.States[mMap.IndexOf('Fertig')]));
  Assert.AreEqual('Ende', TAtlasFlowTexts.Counts(mMap.States[mMap.IndexOf('Fertig')]));
  Assert.AreEqual('1 offen · 1 ich · 1 lange', TAtlasFlowTexts.Counts(mMap.States[mMap.IndexOf('Prüfung')]));
  Assert.AreEqual('0 offen', TAtlasFlowTexts.Counts(mMap.States[mMap.IndexOf('In Arbeit')]));
  Assert.AreEqual('ATL · 90 Tage · 3 Issues · 7 Wechsel', TAtlasFlowTexts.Summary(mMap, 'ATL'));
  mMap.Truncated := True;
  Assert.IsTrue(TAtlasFlowTexts.Summary(mMap, 'ATL').EndsWith('unvollständig (Grenze erreicht)'));
  mStuck := Default(TAtlasFlowStuck);
  mStuck.Days := 9;
  Assert.AreEqual('9 Tagen', TAtlasFlowTexts.Since(mStuck));
  mStuck.Before := True;
  Assert.AreEqual('über 9 Tagen', TAtlasFlowTexts.Since(mStuck));
end;

procedure TAtlasFlowFrameTests.FrameFiltersList;
var
  mFrame: TAtlasFlowFrame;
begin
  mFrame := TAtlasFlowFrame.Create(nil);
  try
    mFrame.SetMap(Map, 'ATL', 5, 'Stand vom 30.03.');
    Assert.IsTrue(mFrame.HasMap);
    Assert.AreEqual('Stand vom 30.03.', mFrame.StatusText);
    Assert.AreEqual('ATL · 90 Tage · 3 Issues · 7 Wechsel', mFrame.Parts.Summary.Caption);
    Assert.IsTrue(mFrame.Parts.View.Visible);
    Assert.AreEqual(Integer(1), Integer(Length(mFrame.VisibleRows)));
    Assert.AreEqual('Liegt lange (ab 5 Tagen)', mFrame.ListCaption);
    mFrame.Parts.View.Selected := 'Offen';
    Assert.AreEqual(Integer(0), Integer(Length(mFrame.VisibleRows)));
    Assert.IsTrue(mFrame.ListCaption.StartsWith('Liegt lange in „Offen“'));
    Assert.IsTrue(mFrame.ListCaption.EndsWith('nichts'));
    mFrame.Parts.View.Selected := 'Prüfung';
    Assert.AreEqual('ATL-3', mFrame.VisibleRows[0].Key);
    // Ein neuer Stand ohne den gewählten Zustand hebt die Wahl auf.
    mFrame.SetMap(TAtlasFlowMap.Build(TAtlasFlowData.Empty, NowUtc, 5), 'ATL', 5, '');
    Assert.AreEqual('', mFrame.Parts.View.Selected);
    Assert.IsFalse(mFrame.Parts.View.Visible, 'ohne Zustände der Hinweis');
    Assert.IsTrue(mFrame.Parts.Empty.Visible);
  finally
    mFrame.Free;
  end;
end;

procedure TAtlasFlowFrameTests.NoticeHidesMap;
var
  mFrame: TAtlasFlowFrame;
begin
  mFrame := TAtlasFlowFrame.Create(nil);
  try
    mFrame.SetMap(Map, 'ATL', 5, '');
    mFrame.ShowNotice('Kein Tracker');
    Assert.IsFalse(mFrame.HasMap);
    Assert.IsFalse(mFrame.Parts.View.Visible);
    Assert.AreEqual('Kein Tracker', mFrame.Parts.Empty.Caption);
    Assert.AreEqual('', mFrame.Parts.Summary.Caption);
    mFrame.SetLoading(True);
    Assert.IsFalse(mFrame.Parts.Refresh.Enabled);
    Assert.AreEqual('Wird geladen …', mFrame.StatusText);
    mFrame.SetLoading(False);
    Assert.IsTrue(mFrame.Parts.Refresh.Enabled);
  finally
    mFrame.Free;
  end;
end;

end.
