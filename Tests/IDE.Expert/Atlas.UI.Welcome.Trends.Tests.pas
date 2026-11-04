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
  System.DateUtils,
  Atlas.UI.Welcome.TestSupport;


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
  Index: Integer;
  Stamp: TDateTime;
begin
  Result := TAtlasProjectSummary.Create(AProject);
  for Index := 0 to High(AHints) do
  begin
    Stamp := EncodeDateTime(2026, 10, 10 + Index, 9, 30, 0, 0);
    Result.Build := TAtlasProjectBuild.Empty;
    Result.Build.Known := True;
    Result.Build.At := Stamp;
    Result.Build.Hints := AHints[Index];
    Result.Build.DurationMs := 12480;
    Result.Vcs := TAtlasProjectVcs.Empty;
    Result.Vcs.Known := True;
    Result.Vcs.Kind := 'git';
    Result.Vcs.Branch := 'main';
    Result.Vcs.Revision := Format('1a2b3c%dd5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b', [Index]);
    if Index > 0 then
    begin
      Result.Todos := TAtlasProjectTodos.Empty;
      Result.Todos.Known := True;
      Result.Todos.At := Stamp;
      Result.Todos.Open := 7;
    end;
    TAtlasProjectTrendLog.Append(Result, Stamp, 30);
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
  Saved: TAtlasLanguage;
  View: TAtlasTrendView;
  Tile: TAtlasTrendTile;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
    Assert.AreEqual(5, Integer(Length(View.Tiles)));
    Tile := View.Tiles[0];
    Assert.AreEqual('0', TAtlasWelcomeTrendsFrame.ValueLine(Tile));
    Assert.AreEqual('vorher 3', TAtlasWelcomeTrendsFrame.PreviousLine(Tile));
    // Regeltreffer ohne Baseline: kein Wert statt 0, kein Vorwert.
    Tile := View.Tiles[1];
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue),
      TAtlasWelcomeTrendsFrame.ValueLine(Tile));
    Assert.AreEqual('', TAtlasWelcomeTrendsFrame.PreviousLine(Tile));
    Assert.AreEqual('7', TAtlasWelcomeTrendsFrame.ValueLine(View.Tiles[2]));
    Assert.AreEqual('12,5 s', TAtlasWelcomeTrendsFrame.ValueLine(View.Tiles[3]));
    Assert.AreEqual('vorher 12,5 s', TAtlasWelcomeTrendsFrame.PreviousLine(View.Tiles[3]));
    Assert.AreEqual('11,8 Zeilen', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('Projektverlauf', TAtlasWelcomeTrendsFrame.TitleText);
    Assert.AreEqual('Warnungen + Hinweise', TAtlasWelcomeTrendsFrame.SeriesTitle(TAtlasTrendSeries.Warnings));
    TAtlasStrings.Language := TAtlasLanguage.English;
    Assert.AreEqual('11.8 lines', TAtlasWelcomeTrendsFrame.ValueWithUnit(TAtlasTrendSeries.MethodLength, 118));
    Assert.AreEqual('before 3', TAtlasWelcomeTrendsFrame.PreviousLine(View.Tiles[0]));
  finally
    TAtlasStrings.Language := Saved;
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
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Info: string;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Frame := TrendsFrame(Host, Source);
    Assert.AreEqual('Kasse · letzte 30 Builds', Frame.HeadingText);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsClickHint), Frame.InfoText,
      'vor dem Klick');
    ClickTrendPoint(Frame, 0, 2);
    Assert.AreEqual(2, Frame.ChosenPoint);
    Assert.AreEqual(0, Frame.ChosenTile);
    Info := Frame.InfoText;
    Assert.Contains(Info, 'Build 3 von 5', 'Position wie im Mockup');
    Assert.IsFalse(Info.Contains('Nr.'), 'laufende Nummer gleich der Position: nicht doppelt');
    Assert.Contains(Info, TAtlasWelcomeTrendsFrame.LocalText(Fake.FView.Points[2].At), 'Datum');
    Assert.Contains(Info, 'main', 'Branch');
    Assert.Contains(Info, '1a2b3c2', 'Commit gekürzt');
    Assert.Contains(Info, 'Warnungen + Hinweise: 6', 'Wert');
    // Lücke: kein Wert.
    ClickTrendPoint(Frame, 2, 0);
    Assert.Contains(Frame.InfoText,
      'Offene TODOs: ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoValue));
    // Daneben: nichts ändert sich.
    ClickTrendPoint(Frame, -1, -1);
    Assert.Contains(Frame.InfoText, 'Offene TODOs');
    // Neu laden (gleiches Projekt, neuer Build): Auswahl bleibt am Build.
    Frame.UpdateContent;
    Assert.AreEqual(0, Frame.ChosenPoint);
    // Nur die letzten 3 Builds gezeigt: Position in der Reihe, dazu die laufende Nummer.
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
      [TAtlasTrendSeries.Warnings], 3);
    Frame.UpdateContent;
    ClickTrendPoint(Frame, 0, 0);
    Assert.Contains(Frame.InfoText, 'Build 1 von 3 · Nr. 3 · ');
    Info := TAtlasWelcomeTrendsFrame.PointInfo(Frame.View, 0, 0, False);
    Assert.Contains(Info, 'Build 1 von 3 · ');
    Assert.IsFalse(Info.Contains('Nr.'), 'ohne Platz ohne laufende Nummer');
    Assert.Contains(Info, 'Warnungen + Hinweise: 6');
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.OtherProjectResetsChoice;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Hit: TAtlasTrendsHit;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Eins.dproj', [1, 2, 3]),
    [TAtlasTrendSeries.Warnings], 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Hit.Tile := 0;
    Hit.Point := 1;
    Frame.ClickAt(Hit);
    Assert.AreEqual(1, Frame.ChosenPoint);
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Zwei.dproj', [8, 4]), [TAtlasTrendSeries.Warnings], 30);
    Frame.UpdateContent;
    Assert.AreEqual('C:\P\Zwei.dproj', Frame.View.Project);
    Assert.AreEqual(2, Integer(Length(Frame.View.Points)));
    Assert.AreEqual(-1, Frame.ChosenPoint, 'Punkt gehörte zum anderen Projekt');
    Assert.AreEqual(40, Frame.View.Tiles[0].Last);
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.HitTestFindsPoints;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Tile, Spark: TRect;
  Hit: TAtlasTrendsHit;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [12, 9, 6, 3, 0]),
    [TAtlasTrendSeries.Warnings, TAtlasTrendSeries.Todos], 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Tile := Frame.TileRect(1, Frame.ClientWidth);
    Spark := Frame.SparkRect(Tile);
    Hit := Frame.HitTest(Spark.Left, Spark.Top + Spark.Height div 2);
    Assert.AreEqual(1, Hit.Tile);
    Assert.AreEqual(0, Hit.Point);
    Hit := Frame.HitTest(Spark.Right, Spark.Bottom);
    Assert.AreEqual(4, Hit.Point, 'letzter Punkt rechts');
    Hit := Frame.HitTest(Tile.Left + 4, Tile.Top + 4);
    Assert.AreEqual(1, Hit.Tile, 'Bezeichnung: Kachel, aber kein Punkt');
    Assert.AreEqual(-1, Hit.Point);
    Hit := Frame.HitTest(2, 2);
    Assert.AreEqual(-1, Hit.Tile, 'Kopfzeile');
  finally
    Host.Free;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.EmptyStates;
var
  Saved: TAtlasLanguage;
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
begin
  Saved := TAtlasStrings.Language;
  Fake := TFakeTrends.Create;
  Source := Fake;
  Host := TForm.CreateNew(nil);
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    Frame := TrendsFrame(Host, Source);
    Assert.AreEqual('', Frame.HeadingText);
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoProject), Frame.InfoText);
    Assert.IsTrue(Frame.PreferredHeight > 0);
    Fake.FView := TAtlasWelcomeTrends.View(TAtlasProjectSummary.Create('C:\P\Neu.dproj'),
      [TAtlasTrendSeries.Warnings], 30);
    Frame.UpdateContent;
    Assert.Contains(Frame.InfoText, 'Neu:');
    Assert.AreEqual(-1, Frame.HitTest(20, 60).Tile, 'ohne Punkte keine Kacheln');
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [1, 2]), nil, 30);
    Frame.UpdateContent;
    Assert.AreEqual(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeTrendsNoSeries), Frame.InfoText);
  finally
    Host.Free;
    TAtlasStrings.Language := Saved;
  end;
end;
procedure TAtlasWelcomeTrendsFrameTests.TilesWrapByWidth;
var
  Host: TForm;
  Fake: TFakeTrends;
  Source: IAtlasTrendsSource;
  Frame: TAtlasWelcomeTrendsFrame;
  Wide, Narrow, One: Integer;
begin
  Fake := TFakeTrends.Create;
  Source := Fake;
  Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
    TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries), 30);
  Host := TForm.CreateNew(nil);
  try
    Frame := TrendsFrame(Host, Source);
    Frame.Width := Frame.ScaleValue(900);
    Wide := Frame.PreferredHeight;
    Frame.Width := Frame.ScaleValue(340);
    Narrow := Frame.PreferredHeight;
    Assert.IsTrue(Narrow > Wide, Format('breit %d, schmal %d', [Wide, Narrow]));
    Assert.AreEqual(Frame.TileRect(0, Frame.ScaleValue(900)).Top, Frame.TileRect(4, Frame.ScaleValue(900)).Top,
      'breit: eine Reihe');
    Assert.IsTrue(Frame.TileRect(2, Frame.ScaleValue(340)).Top > Frame.TileRect(0, Frame.ScaleValue(340)).Top,
      'schmal: umgebrochen');
    Fake.FView := TAtlasWelcomeTrends.View(TrendSummary('C:\P\Kasse.dproj', [3, 2, 1]),
      [TAtlasTrendSeries.Todos], 30);
    Frame.UpdateContent;
    One := Frame.PreferredHeight;
    Assert.IsTrue(One < Narrow, 'eine Reihe weniger Kacheln');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTrendsFrameTests);

end.
