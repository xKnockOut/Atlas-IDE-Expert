unit Atlas.Core.Welcome.Trends.Tests;

// Tests des Bereichs „Projektverlauf“ ohne VCL (#758): Auswahl des Projekts,
// Reihen aus welcomePage.trends.series, Ansicht mit Kacheln, Skala mit
// Nulllinie, Vorwert über Lücken, Texte der Werte, Lage der Punkte und die
// Einstellungen welcomePage.trends, .points und .series.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasWelcomeTrendsTests = class
  public
    [Test]
    procedure ParseSeriesKeepsTileOrder;
    [Test]
    procedure SeriesTextAndNormalize;
    /// <summary>Abnahme: Wechsel der Auswahl in „Projekte“ wechselt den Verlauf; ohne Auswahl das oberste.</summary>
    [Test]
    procedure ChooseSelectedOrTop;
    /// <summary>Abnahme: welcomePage.trends.series blendet einzelne Reihen aus.</summary>
    [Test]
    procedure ViewHasOneTilePerSeries;
    [Test]
    procedure ViewShowsNewestPoints;
    [Test]
    procedure ViewWithoutPoints;
    [Test]
    procedure ScaleIncludesZero;
    [Test]
    procedure PreviousSkipsGaps;
    [Test]
    procedure ValueTextWithDecimals;
    [Test]
    procedure ShortCommitOnlyForHashes;
    [Test]
    procedure PointPositions;
  end;

  [TestFixture]
  TAtlasTrendSettingsTests = class
  public
    [Test]
    procedure Defaults;
    [Test]
    procedure NormalizeClampsAndCleans;
    [Test]
    procedure SeriesNamesMatchFileKeys;
    [Test]
    procedure SaveAndLoadRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.Generics.Collections,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Trends,
  Atlas.Core.Welcome.Trends;

const
  Project = 'C:\Projekte\Kasse\Kasse.dproj';

/// <summary>Zusammenfassung mit ACount Punkten; Warnungen = Nummer des Builds, TODOs nur bei geraden.</summary>
function WithPoints(ACount: Integer): TAtlasProjectSummary;
var
  Index: Integer;
  Point: TAtlasTrendPoint;
begin
  Result := TAtlasProjectSummary.Create(Project);
  Result.Trends.Known := True;
  for Index := 1 to ACount do
  begin
    Point := TAtlasTrendPoint.Create(EncodeDateTime(2026, 10, 1, 8, 0, 0, 0) + Index / MinsPerDay, Index);
    Point.SetValue(TAtlasTrendSeries.Warnings, Index * 10);
    if not Odd(Index) then
      Point.SetValue(TAtlasTrendSeries.Todos, Index * 10);
    Result.Trends.Points := Result.Trends.Points + [Point];
  end;
  Result.Trends.Builds := ACount;
end;

{ TAtlasWelcomeTrendsTests }

procedure TAtlasWelcomeTrendsTests.ParseSeriesKeepsTileOrder;
var
  Series: TAtlasTrendSeriesList;
begin
  Series := TAtlasWelcomeTrends.ParseSeries('todos; WARNINGS unbekannt,todos');
  Assert.AreEqual(2, Integer(Length(Series)));
  Assert.IsTrue(Series[0] = TAtlasTrendSeries.Warnings, 'Reihenfolge der Kacheln, nicht der Liste');
  Assert.IsTrue(Series[1] = TAtlasTrendSeries.Todos);
  Assert.AreEqual(5, Integer(Length(TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.DefaultSeries))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeTrends.ParseSeries(''))));
end;

procedure TAtlasWelcomeTrendsTests.SeriesTextAndNormalize;
begin
  Assert.AreEqual('warnings,todos', TAtlasWelcomeTrends.SeriesText([TAtlasTrendSeries.Warnings,
    TAtlasTrendSeries.Todos]));
  Assert.AreEqual('ruleHits,methodLength', TAtlasWelcomeTrends.NormalizeSeries(' methodlength ; RULEHITS '));
  Assert.AreEqual('', TAtlasWelcomeTrends.NormalizeSeries('nichts'));
  Assert.AreEqual(TAtlasWelcomeTrends.DefaultSeries, TAtlasWelcomeTrends.NormalizeSeries(
    'methodLength,duration,todos,ruleHits,warnings'));
end;

procedure TAtlasWelcomeTrendsTests.ChooseSelectedOrTop;
var
  Projects: TArray<string>;
begin
  Projects := ['C:\A\A.dproj', 'C:\B\B.dproj', 'C:\C\C.groupproj'];
  Assert.AreEqual('C:\A\A.dproj', TAtlasWelcomeTrends.Choose(Projects, ''), 'ohne Auswahl das oberste');
  Assert.AreEqual('C:\B\B.dproj', TAtlasWelcomeTrends.Choose(Projects, 'c:/b/b.DPROJ'), 'gewählt');
  Assert.AreEqual('C:\C\C.groupproj', TAtlasWelcomeTrends.Choose(Projects, 'C:\C\C.groupproj'));
  Assert.AreEqual('C:\A\A.dproj', TAtlasWelcomeTrends.Choose(Projects, 'C:\Weg\Weg.dproj'), 'nicht mehr in der Liste');
  Assert.AreEqual('', TAtlasWelcomeTrends.Choose(nil, 'C:\B\B.dproj'));
end;

procedure TAtlasWelcomeTrendsTests.ViewHasOneTilePerSeries;
var
  View: TAtlasTrendView;
begin
  View := TAtlasWelcomeTrends.View(WithPoints(4), TAtlasWelcomeTrends.ParseSeries('todos,warnings'), 30);
  Assert.AreEqual(Project, View.Project);
  Assert.AreEqual('Kasse', View.Name);
  Assert.AreEqual(30, View.Limit);
  Assert.AreEqual(2, Integer(Length(View.Tiles)));
  Assert.IsTrue(View.Tiles[0].Series = TAtlasTrendSeries.Warnings);
  Assert.IsTrue(View.Tiles[1].Series = TAtlasTrendSeries.Todos);
  Assert.AreEqual(4, Integer(Length(View.Tiles[1].Values)));
  Assert.IsFalse(View.Tiles[1].Has[0], 'Lücke');
  Assert.IsTrue(View.Tiles[1].Has[1]);
  View := TAtlasWelcomeTrends.View(WithPoints(4), nil, 30);
  Assert.AreEqual(0, Integer(Length(View.Tiles)), 'alle Reihen ausgeblendet');
  Assert.AreEqual(4, Integer(Length(View.Points)));
end;

procedure TAtlasWelcomeTrendsTests.ViewShowsNewestPoints;
var
  View: TAtlasTrendView;
begin
  View := TAtlasWelcomeTrends.View(WithPoints(40), [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(30, Integer(Length(View.Points)));
  Assert.AreEqual(11, View.Points[0].Build);
  Assert.AreEqual(40, View.Points[29].Build);
  Assert.AreEqual(400, View.Tiles[0].Last);
  View := TAtlasWelcomeTrends.View(WithPoints(40), [TAtlasTrendSeries.Warnings], 0);
  Assert.AreEqual(2, View.Limit, 'Grenze mindestens 2');
  Assert.AreEqual(2, Integer(Length(View.Points)));
end;

procedure TAtlasWelcomeTrendsTests.ViewWithoutPoints;
var
  View: TAtlasTrendView;
begin
  View := TAtlasWelcomeTrends.View(TAtlasProjectSummary.Create(Project), [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(Project, View.Project);
  Assert.AreEqual(0, Integer(Length(View.Points)));
  Assert.AreEqual(1, Integer(Length(View.Tiles)));
  Assert.IsFalse(View.Tiles[0].HasLast);
end;

procedure TAtlasWelcomeTrendsTests.ScaleIncludesZero;
var
  Bottom, Top: Integer;
begin
  TAtlasWelcomeTrends.Scale([50, 90, 70], [True, True, True], Bottom, Top);
  Assert.AreEqual(0, Bottom, 'Nulllinie sichtbar');
  Assert.AreEqual(90, Top);
  TAtlasWelcomeTrends.Scale([-30, 20], [True, True], Bottom, Top);
  Assert.AreEqual(-30, Bottom);
  Assert.AreEqual(20, Top);
  TAtlasWelcomeTrends.Scale([0, 0], [True, True], Bottom, Top);
  Assert.AreEqual(0, Bottom);
  Assert.AreEqual(10, Top, 'nur Nullen: eine Einheit Luft');
  TAtlasWelcomeTrends.Scale([500, 20], [False, True], Bottom, Top);
  Assert.AreEqual(20, Top, 'Lücken zählen nicht');
end;

procedure TAtlasWelcomeTrendsTests.PreviousSkipsGaps;
var
  Tile: TAtlasTrendTile;
  Value: Integer;
begin
  Tile := Default(TAtlasTrendTile);
  Tile.Values := [10, 20, 0, 40];
  Tile.Has := [True, True, False, True];
  Assert.IsTrue(Tile.HasLast);
  Assert.AreEqual(40, Tile.Last);
  Assert.IsTrue(Tile.Previous(Value));
  Assert.AreEqual(20, Value, 'über die Lücke hinweg');
  Tile.Has := [True, True, True, False];
  Assert.IsFalse(Tile.HasLast, 'letzter Build ohne Wert');
  Assert.IsTrue(Tile.Previous(Value));
  Assert.AreEqual(0, Value);
  Tile.Values := [5];
  Tile.Has := [True];
  Assert.IsFalse(Tile.Previous(Value), 'ein Build: kein Vorwert');
end;

procedure TAtlasWelcomeTrendsTests.ValueTextWithDecimals;
begin
  Assert.AreEqual('3', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.Warnings, 30, ','));
  Assert.AreEqual('12', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.Todos, 120, ','));
  Assert.AreEqual('12,5', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.Duration, 125, ','));
  Assert.AreEqual('11.8', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.MethodLength, 118, '.'));
  Assert.AreEqual('0,0', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.Duration, 0, ','));
  Assert.AreEqual('-0,5', TAtlasWelcomeTrends.ValueText(TAtlasTrendSeries.Duration, -5, ','));
end;

procedure TAtlasWelcomeTrendsTests.ShortCommitOnlyForHashes;
begin
  Assert.AreEqual('1a2b3c4', TAtlasWelcomeTrends.ShortCommit('1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b'));
  Assert.AreEqual('4711', TAtlasWelcomeTrends.ShortCommit('4711'), 'SVN-Revision bleibt');
  Assert.AreEqual('', TAtlasWelcomeTrends.ShortCommit(''));
  Assert.AreEqual('zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz',
    TAtlasWelcomeTrends.ShortCommit('zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'), 'kein Hash');
end;

procedure TAtlasWelcomeTrendsTests.PointPositions;
begin
  Assert.AreEqual(10, TAtlasWelcomeTrends.PointX(0, 5, 10, 100));
  Assert.AreEqual(60, TAtlasWelcomeTrends.PointX(2, 5, 10, 100));
  Assert.AreEqual(110, TAtlasWelcomeTrends.PointX(4, 5, 10, 100), 'letzter Punkt ganz rechts');
  Assert.AreEqual(110, TAtlasWelcomeTrends.PointX(0, 1, 10, 100), 'ein Punkt steht rechts');
  Assert.AreEqual(36, TAtlasWelcomeTrends.PointY(0, 0, 100, 0, 36), 'Null unten');
  Assert.AreEqual(0, TAtlasWelcomeTrends.PointY(100, 0, 100, 0, 36), 'Höchstwert oben');
  Assert.AreEqual(18, TAtlasWelcomeTrends.PointY(0, -50, 50, 0, 36), 'Null in der Mitte');
  Assert.AreEqual(2, TAtlasWelcomeTrends.NearestPoint(58, 5, 10, 100));
  Assert.AreEqual(0, TAtlasWelcomeTrends.NearestPoint(-20, 5, 10, 100));
  Assert.AreEqual(4, TAtlasWelcomeTrends.NearestPoint(500, 5, 10, 100));
  Assert.AreEqual(-1, TAtlasWelcomeTrends.NearestPoint(50, 0, 10, 100));
end;

{ TAtlasTrendSettingsTests }

type
  TTrendStore = class(TInterfacedObject, IAtlasSettingsStore)
  private
    FValues: TDictionary<string, string>;
  public
    constructor Create;
    destructor Destroy; override;
    function ReadInteger(const AName: string; ADefault: Integer): Integer;
    procedure WriteInteger(const AName: string; AValue: Integer);
    function ReadString(const AName, ADefault: string): string;
    procedure WriteString(const AName, AValue: string);
  end;

constructor TTrendStore.Create;
begin
  inherited Create;
  FValues := TDictionary<string, string>.Create;
end;

destructor TTrendStore.Destroy;
begin
  FValues.Free;
  inherited;
end;

function TTrendStore.ReadInteger(const AName: string; ADefault: Integer): Integer;
var
  Text: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, Text) then
    Result := StrToIntDef(Text, ADefault);
end;

procedure TTrendStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TTrendStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
    Result := ADefault;
end;

procedure TTrendStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

procedure TAtlasTrendSettingsTests.Defaults;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.WelcomePageTrends);
  Assert.AreEqual(30, Settings.WelcomePageTrendsPoints);
  Assert.AreEqual(TAtlasProjectTrendLog.DefaultPoints, Settings.WelcomePageTrendsPoints);
  Assert.AreEqual('warnings,ruleHits,todos,duration,methodLength', Settings.WelcomePageTrendsSeries, 'alle fünf');
  Assert.AreEqual(TAtlasWelcomeTrends.DefaultSeries, TAtlasPluginSettings.DefaultTrendSeries);
end;

procedure TAtlasTrendSettingsTests.NormalizeClampsAndCleans;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.WelcomePageTrendsPoints := 1;
  Settings.WelcomePageTrendsSeries := ' TODOS; foo warnings ';
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MinTrendPoints, Settings.WelcomePageTrendsPoints);
  Assert.AreEqual('warnings,todos', Settings.WelcomePageTrendsSeries);
  Settings.WelcomePageTrendsPoints := 1000;
  Settings.WelcomePageTrendsSeries := '';
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.MaxTrendPoints, Settings.WelcomePageTrendsPoints);
  Assert.AreEqual('', Settings.WelcomePageTrendsSeries, 'leer = keine Kachel');
  Assert.AreEqual(TAtlasProjectTrendLog.MinPoints, TAtlasPluginSettings.MinTrendPoints);
  Assert.AreEqual(TAtlasProjectTrendLog.MaxPoints, TAtlasPluginSettings.MaxTrendPoints);
end;

procedure TAtlasTrendSettingsTests.SeriesNamesMatchFileKeys;
var
  Series: TAtlasTrendSeries;
  Settings: TAtlasPluginSettings;
begin
  // Die Einstellungen kennen die Namen ohne die Zusammenfassung: Sie müssen denen der Datei entsprechen.
  for Series := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    Settings := TAtlasPluginSettings.Defaults;
    Settings.WelcomePageTrendsSeries := TAtlasProjectSummaries.TrendKeys[Series];
    Settings.Normalize;
    Assert.AreEqual(TAtlasProjectSummaries.TrendKeys[Series], Settings.WelcomePageTrendsSeries);
    Assert.AreEqual(TAtlasProjectSummaries.TrendKeys[Series], TAtlasWelcomeTrends.SeriesKey(Series));
  end;
end;

procedure TAtlasTrendSettingsTests.SaveAndLoadRoundTrip;
var
  Store: IAtlasSettingsStore;
  Saved, Loaded: TAtlasPluginSettings;
begin
  Store := TTrendStore.Create;
  Saved := TAtlasPluginSettings.Defaults;
  Saved.WelcomePageTrends := False;
  Saved.WelcomePageTrendsPoints := 12;
  Saved.WelcomePageTrendsSeries := 'todos,duration';
  Saved.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('WelcomePageTrends', 1), 'Registry-Name');
  Assert.AreEqual(12, Store.ReadInteger('WelcomePageTrendsPoints', 0));
  Assert.AreEqual('todos,duration', Store.ReadString('WelcomePageTrendsSeries', ''));
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.WelcomePageTrends);
  Assert.AreEqual(12, Loaded.WelcomePageTrendsPoints);
  Assert.AreEqual('todos,duration', Loaded.WelcomePageTrendsSeries);
  // Leere Liste bleibt leer (alle Reihen ausgeblendet), statt auf die Vorgabe zurückzufallen.
  Saved.WelcomePageTrendsSeries := '';
  Saved.Save(Store);
  Loaded.Load(Store);
  Assert.AreEqual('', Loaded.WelcomePageTrendsSeries);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTrendsTests);
  TDUnitX.RegisterTestFixture(TAtlasTrendSettingsTests);

end.
