unit Atlas.UI.Welcome.Trends.Tests;

// Tests des Trendbereichs der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeTrendsFrameTests = class
  public
    /// <summary>Abnahme: 12, 9, 6, 3, 0 Hinweise ergeben „0“ und „vorher 3“; Einheiten je Sprache.</summary>
    [Test]
    procedure TextsShowValueAndPrevious;
    /// <summary>Abnahme: Klick auf einen Punkt zeigt Build, Datum, Branch und Commit.</summary>
    [Test]
    procedure ClickShowsBuild;
    /// <summary>Abnahme: Anderes Projekt gewählt, anderer Verlauf; der gewählte Punkt gehört zum alten.</summary>
    [Test]
    procedure OtherProjectResetsChoice;
    [Test]
    procedure HitTestFindsPoints;
    [Test]
    procedure EmptyStates;
    [Test]
    procedure TilesWrapByWidth;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  Vcl.Forms,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Strings,
  System.Types,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Trends,
  Atlas.Core.Welcome.Trends,
  Atlas.UI.Welcome.Trends,
  System.DateUtils;


type
  /// <summary>Quelle des Bereichs „Projektverlauf“ für die Tests.</summary>
  TFakeTrends = class(TInterfacedObject, IAtlasTrendsSource)
  public
    FView: TAtlasTrendView;
    function View: TAtlasTrendView;
  end;

{ TFakeTrends }

function TFakeTrends.View: TAtlasTrendView;
begin
  Result := FView;
end;
/// <summary>Projekt mit einem Build je Wert in AHints (Hinweise), Dauer 12,48 s, Branch main, eigener Commit je
/// Build, TODOs ab dem zweiten.</summary>
function TrendSummary(const AProject: string; const AHints: array of Integer): TAtlasProjectSummary;
var
  mIndex: Integer;
  mStamp: TDateTime;
begin
  Result := TAtlasProjectSummary.Create(AProject);
  for mIndex := 0 to High(AHints) do
  begin
    mStamp := EncodeDateTime(2026, 10, 10 + mIndex, 9, 30, 0, 0);
    Result.Build := TAtlasProjectBuild.Empty;
    Result.Build.Known := True;
    Result.Build.At := mStamp;
    Result.Build.Hints := AHints[mIndex];
    Result.Build.DurationMs := 12480;
    Result.Vcs := TAtlasProjectVcs.Empty;
    Result.Vcs.Known := True;
    Result.Vcs.Kind := 'git';
    Result.Vcs.Branch := 'main';
    Result.Vcs.Revision := Format('1a2b3c%dd5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', [mIndex]);
    if mIndex > 0 then
    begin
      Result.Todos := TAtlasProjectTodos.Empty;
      Result.Todos.Known := True;
      Result.Todos.At := mStamp;
      Result.Todos.Open := 7;
    end;
    TAtlasProjectTrendLog.Append(Result, mStamp, 30);
  end;
end;
function TrendsFrame(AHost: TForm; const ASource: IAtlasTrendsSource): TAtlasWelcomeTrendsFrame;
begin
  Result := TAtlasWelcomeTrendsFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Width := 600;
  Result.Source := ASource;
end;
{ TAtlasWelcomeTrendsFrameTests }

procedure TAtlasWelcomeTrendsFrameTests.TextsShowValueAndPrevious;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasTrendView;
  mTile: TAtlasTrendTile;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.cDefaultSeries), 30);
    Assert.AreEqual(5, Integer(Length(mView.Tiles)));
    mTile := mView.Tiles[0];
    Assert.AreEqual('0', TAtlasWelcomeTrendsFrame.ValueLine(mTile));
    Assert.AreEqual('vorher 3', TAtlasWelcomeTrendsFrame.PreviousLine(mTile));
    // Regeltreffer ohne Baseline: kein Wert statt 0, kein Vorwert.
    mTile := mView.Tiles[1];
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue),
      TAtlasWelcomeTrendsFrame.ValueLine(mTile));
    Assert.AreEqual('', TAtlasWelcomeTrendsFrame.PreviousLine(mTile));
    Assert.AreEqual('7', TAtlasWelcomeTrendsFrame.ValueLine(mView.Tiles[2]));
    Assert.AreEqual('12,5 s', TAtlasWelcomeTrendsFrame.ValueLine(mView.Tiles[3]));
    Assert.AreEqual('vorher 12,5 s', TAtlasWelcomeTrendsFrame.PreviousLine(mView.Tiles[3]));
    Assert.AreEqual('11,8 Zeilen', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('Projektverlauf', TAtlasWelcomeTrendsFrame.TitleText);
    Assert.AreEqual('Warnungen + Hinweise', TAtlasWelcomeTrendsFrame.SeriesTitle(TAtlasTrendSeries.Warnings));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('11.8 lines', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('before 3', TAtlasWelcomeTrendsFrame.PreviousLine(mView.Tiles[0]));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;
/// <summary>Klick auf Punkt APoint der Kachel ATile (-1: daneben).</summary>
procedure ClickTrendPoint(const AFrame: TAtlasWelcomeTrendsFrame; ATile, APoint: Integer);
var
  mHit: TAtlasTrendsHit;
begin
  mHit.Tile := ATile;
  mHit.Point := APoint;
  AFrame.ClickAt(mHit);
end;
procedure TAtlasWelcomeTrendsFrameTests.ClickShowsBuild;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeTrends;
  mSource: IAtlasTrendsSource;
  mFrame: TAtlasWelcomeTrendsFrame;
  mInfo: string;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeTrends.Create;
  mSource := mFake;
  mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.cDefaultSeries), 30);
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mFrame := TrendsFrame(mHost, mSource);
    Assert.AreEqual('Kasse · letzte 30 Builds', mFrame.HeadingText);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsClickHint), mFrame.InfoText,
      'vor dem Klick');
    ClickTrendPoint(mFrame, 0, 2);
    Assert.AreEqual(2, mFrame.ChosenPoint);
    Assert.AreEqual(0, mFrame.ChosenTile);
    mInfo := mFrame.InfoText;
    Assert.Contains(mInfo, 'Build 3 von 5', 'Position wie im Mockup');
    Assert.IsFalse(mInfo.Contains('Nr.'), 'laufende Nummer gleich der Position: nicht doppelt');
    Assert.Contains(mInfo, TAtlasWelcomeTrendsFrame.LocalText(mFake.FView.Points[2].At), 'Datum');
    Assert.Contains(mInfo, 'main', 'Branch');
    Assert.Contains(mInfo, '1a2b3c2', 'Commit gekürzt');
    Assert.Contains(mInfo, 'Warnungen + Hinweise: 6', 'Wert');
    // Lücke: kein Wert.
    ClickTrendPoint(mFrame, 2, 0);
    Assert.Contains(mFrame.InfoText,
      'Offene TODOs: ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue));
    // Daneben: nichts ändert sich.
    ClickTrendPoint(mFrame, -1, -1);
    Assert.Contains(mFrame.InfoText, 'Offene TODOs');
    // Neu laden (gleiches Projekt, neuer Build): Auswahl bleibt am Build.
    mFrame.UpdateContent;
    Assert.AreEqual(0, mFrame.ChosenPoint);
    // Nur die letzten 3 Builds gezeigt: Position in der Reihe, dazu die laufende Nummer.
    mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      [TAtlasTrendSeries.Warnings], 3);
    mFrame.UpdateContent;
    ClickTrendPoint(mFrame, 0, 0);
    Assert.Contains(mFrame.InfoText, 'Build 1 von 3 · Nr. 3 · ');
    mInfo := TAtlasWelcomeTrendsFrame.PointInfo(mFrame.View, 0, 0, False);
    Assert.Contains(mInfo, 'Build 1 von 3 · ');
    Assert.IsFalse(mInfo.Contains('Nr.'), 'ohne Platz ohne laufende Nummer');
    Assert.Contains(mInfo, 'Warnungen + Hinweise: 6');
  finally
    mHost.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.OtherProjectResetsChoice;
var
  mHost: TForm;
  mFake: TFakeTrends;
  mSource: IAtlasTrendsSource;
  mFrame: TAtlasWelcomeTrendsFrame;
  mHit: TAtlasTrendsHit;
begin
  mFake := TFakeTrends.Create;
  mSource := mFake;
  mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Eins.dproj', [1, 2, 3]),
    [TAtlasTrendSeries.Warnings], 30);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TrendsFrame(mHost, mSource);
    mHit.Tile := 0;
    mHit.Point := 1;
    mFrame.ClickAt(mHit);
    Assert.AreEqual(1, mFrame.ChosenPoint);
    mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Zwei.dproj', [8, 4]), [TAtlasTrendSeries.Warnings], 30);
    mFrame.UpdateContent;
    Assert.AreEqual('C:\P\Zwei.dproj', mFrame.View.Project);
    Assert.AreEqual(2, Integer(Length(mFrame.View.Points)));
    Assert.AreEqual(-1, mFrame.ChosenPoint, 'Punkt gehörte zum anderen Projekt');
    Assert.AreEqual(40, mFrame.View.Tiles[0].Last);
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.HitTestFindsPoints;
var
  mHost: TForm;
  mFake: TFakeTrends;
  mSource: IAtlasTrendsSource;
  mFrame: TAtlasWelcomeTrendsFrame;
  mTile, mSpark: TRect;
  mHit: TAtlasTrendsHit;
begin
  mFake := TFakeTrends.Create;
  mSource := mFake;
  mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    [TAtlasTrendSeries.Warnings, TAtlasTrendSeries.Todos], 30);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TrendsFrame(mHost, mSource);
    mTile := mFrame.TileRect(1, mFrame.ClientWidth);
    mSpark := mFrame.SparkRect(mTile);
    mHit := mFrame.HitTest(mSpark.Left, mSpark.Top + mSpark.Height div 2);
    Assert.AreEqual(1, mHit.Tile);
    Assert.AreEqual(0, mHit.Point);
    mHit := mFrame.HitTest(mSpark.Right, mSpark.Bottom);
    Assert.AreEqual(4, mHit.Point, 'letzter Punkt rechts');
    mHit := mFrame.HitTest(mTile.Left + 4, mTile.Top + 4);
    Assert.AreEqual(1, mHit.Tile, 'Bezeichnung: Kachel, aber kein Punkt');
    Assert.AreEqual(-1, mHit.Point);
    mHit := mFrame.HitTest(2, 2);
    Assert.AreEqual(-1, mHit.Tile, 'Kopfzeile');
  finally
    mHost.Free;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.EmptyStates;
var
  mSaved: TAtlasLanguage;
  mHost: TForm;
  mFake: TFakeTrends;
  mSource: IAtlasTrendsSource;
  mFrame: TAtlasWelcomeTrendsFrame;
begin
  mSaved := TAtlasStrings.Language;
  mFake := TFakeTrends.Create;
  mSource := mFake;
  mHost := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mFrame := TrendsFrame(mHost, mSource);
    Assert.AreEqual('', mFrame.HeadingText);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoProject), mFrame.InfoText);
    Assert.IsTrue(mFrame.PreferredHeight > 0);
    mFake.FView := TAtlasWelcomeTrends.View(TAtlasProjectSummary.Create('C:\P\Neu.dproj'),
      [TAtlasTrendSeries.Warnings], 30);
    mFrame.UpdateContent;
    Assert.Contains(mFrame.InfoText, 'Neu:');
    Assert.AreEqual(-1, mFrame.HitTest(20, 60).Tile, 'ohne Punkte keine Kacheln');
    mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [1, 2]), nil, 30);
    mFrame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoSeries), mFrame.InfoText);
  finally
    mHost.Free;
    TAtlasStrings.Language := mSaved;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.TilesWrapByWidth;
var
  mHost: TForm;
  mFake: TFakeTrends;
  mSource: IAtlasTrendsSource;
  mFrame: TAtlasWelcomeTrendsFrame;
  mWide, mNarrow, mOne: Integer;
begin
  mFake := TFakeTrends.Create;
  mSource := mFake;
  mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.cDefaultSeries), 30);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TrendsFrame(mHost, mSource);
    mFrame.Width := mFrame.ScaleValue(900);
    mWide := mFrame.PreferredHeight;
    mFrame.Width := mFrame.ScaleValue(340);
    mNarrow := mFrame.PreferredHeight;
    Assert.IsTrue(mNarrow > mWide, Format('breit %d, schmal %d', [mWide, mNarrow]));
    Assert.AreEqual(mFrame.TileRect(0, mFrame.ScaleValue(900)).Top, mFrame.TileRect(4, mFrame.ScaleValue(900)).Top,
      'breit: eine Reihe');
    Assert.IsTrue(mFrame.TileRect(2, mFrame.ScaleValue(340)).Top > mFrame.TileRect(0, mFrame.ScaleValue(340)).Top,
      'schmal: umgebrochen');
    mFake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
      [TAtlasTrendSeries.Todos], 30);
    mFrame.UpdateContent;
    mOne := mFrame.PreferredHeight;
    Assert.IsTrue(mOne < mNarrow, 'eine Reihe weniger Kacheln');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTrendsFrameTests);

end.
