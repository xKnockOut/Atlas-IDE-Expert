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
  [Category('Atlas.IDE.Welcome')]
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
  [Category('Atlas.IDE.Welcome')]
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
  cProject = 'C:\Projekte\Kasse\Kasse.dproj';

/// <summary>Zusammenfassung mit ACount Punkten; Warnungen = Nummer des Builds, TODOs nur bei geraden.</summary>
function WithPoints(ACount: Integer): TAtlasProjectSummary;
var
  mIndex: Integer;
  mPoint: TAtlasTrendPoint;
begin
  Result := TAtlasProjectSummary.Create(cProject);
  Result.Trends.Known := True;
  for mIndex := 1 to ACount do
  begin
    mPoint := TAtlasTrendPoint.Create(EncodeDateTime(2026, 10, 1, 8, 0, 0, 0) + mIndex / MinsPerDay, mIndex);
    mPoint.SetValue(TAtlasTrendSeries.Warnings, mIndex * 10);
    if not Odd(mIndex) then
    begin
      mPoint.SetValue(TAtlasTrendSeries.Todos, mIndex * 10);
    end;
    Result.Trends.Points := Result.Trends.Points + [mPoint];
  end;
  Result.Trends.Builds := ACount;
end;

{ TAtlasWelcomeTrendsTests }

procedure TAtlasWelcomeTrendsTests.ParseSeriesKeepsTileOrder;
var
  mSeries: TAtlasTrendSeriesList;
begin
  mSeries := TAtlasWelcomeTrends.ParseSeries('todos; WARNINGS unbekannt,todos');
  Assert.AreEqual(2, Integer(Length(mSeries)));
  Assert.IsTrue(mSeries[0] = TAtlasTrendSeries.Warnings, 'Reihenfolge der Kacheln, nicht der Liste');
  Assert.IsTrue(mSeries[1] = TAtlasTrendSeries.Todos);
  Assert.AreEqual(5, Integer(Length(TAtlasWelcomeTrends.ParseSeries(TAtlasWelcomeTrends.cDefaultSeries))));
  Assert.AreEqual(0, Integer(Length(TAtlasWelcomeTrends.ParseSeries(''))));
end;

procedure TAtlasWelcomeTrendsTests.SeriesTextAndNormalize;
begin
  Assert.AreEqual('warnings,todos', TAtlasWelcomeTrends.SeriesText([TAtlasTrendSeries.Warnings,
    TAtlasTrendSeries.Todos]));
  Assert.AreEqual('ruleHits,methodLength', TAtlasWelcomeTrends.NormalizeSeries(' methodlength ; RULEHITS '));
  Assert.AreEqual('', TAtlasWelcomeTrends.NormalizeSeries('nichts'));
  Assert.AreEqual(TAtlasWelcomeTrends.cDefaultSeries, TAtlasWelcomeTrends.NormalizeSeries(
    'methodLength,duration,todos,ruleHits,warnings'));
end;

procedure TAtlasWelcomeTrendsTests.ChooseSelectedOrTop;
var
  mProjects: TArray<string>;
begin
  mProjects := ['C:\A\A.dproj', 'C:\B\B.dproj', 'C:\C\C.groupproj'];
  Assert.AreEqual('C:\A\A.dproj', TAtlasWelcomeTrends.Choose(mProjects, ''), 'ohne Auswahl das oberste');
  Assert.AreEqual('C:\B\B.dproj', TAtlasWelcomeTrends.Choose(mProjects, 'c:/b/b.DPROJ'), 'gewählt');
  Assert.AreEqual('C:\C\C.groupproj', TAtlasWelcomeTrends.Choose(mProjects, 'C:\C\C.groupproj'));
  Assert.AreEqual('C:\A\A.dproj', TAtlasWelcomeTrends.Choose(mProjects, 'C:\Weg\Weg.dproj'), 'nicht mehr in der Liste');
  Assert.AreEqual('', TAtlasWelcomeTrends.Choose(nil, 'C:\B\B.dproj'));
end;

procedure TAtlasWelcomeTrendsTests.ViewHasOneTilePerSeries;
var
  mView: TAtlasTrendView;
begin
  mView := TAtlasWelcomeTrends.View(WithPoints(4), TAtlasWelcomeTrends.ParseSeries('todos,warnings'), 30);
  Assert.AreEqual(cProject, mView.Project);
  Assert.AreEqual('Kasse', mView.Name);
  Assert.AreEqual(30, mView.Limit);
  Assert.AreEqual(2, Integer(Length(mView.Tiles)));
  Assert.IsTrue(mView.Tiles[0].Series = TAtlasTrendSeries.Warnings);
  Assert.IsTrue(mView.Tiles[1].Series = TAtlasTrendSeries.Todos);
  Assert.AreEqual(4, Integer(Length(mView.Tiles[1].Values)));
  Assert.IsFalse(mView.Tiles[1].Has[0], 'Lücke');
  Assert.IsTrue(mView.Tiles[1].Has[1]);
  mView := TAtlasWelcomeTrends.View(WithPoints(4), nil, 30);
  Assert.AreEqual(0, Integer(Length(mView.Tiles)), 'alle Reihen ausgeblendet');
  Assert.AreEqual(4, Integer(Length(mView.Points)));
end;

procedure TAtlasWelcomeTrendsTests.ViewShowsNewestPoints;
var
  mView: TAtlasTrendView;
begin
  mView := TAtlasWelcomeTrends.View(WithPoints(40), [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(30, Integer(Length(mView.Points)));
  Assert.AreEqual(11, mView.Points[0].Build);
  Assert.AreEqual(40, mView.Points[29].Build);
  Assert.AreEqual(400, mView.Tiles[0].Last);
  mView := TAtlasWelcomeTrends.View(WithPoints(40), [TAtlasTrendSeries.Warnings], 0);
  Assert.AreEqual(2, mView.Limit, 'Grenze mindestens 2');
  Assert.AreEqual(2, Integer(Length(mView.Points)));
end;

procedure TAtlasWelcomeTrendsTests.ViewWithoutPoints;
var
  mView: TAtlasTrendView;
begin
  mView := TAtlasWelcomeTrends.View(TAtlasProjectSummary.Create(cProject), [TAtlasTrendSeries.Warnings], 30);
  Assert.AreEqual(cProject, mView.Project);
  Assert.AreEqual(0, Integer(Length(mView.Points)));
  Assert.AreEqual(1, Integer(Length(mView.Tiles)));
  Assert.IsFalse(mView.Tiles[0].HasLast);
end;

procedure TAtlasWelcomeTrendsTests.ScaleIncludesZero;
var
  mBottom, mTop: Integer;
begin
  TAtlasWelcomeTrends.Scale([50, 90, 70], [True, True, True], mBottom, mTop);
  Assert.AreEqual(0, mBottom, 'Nulllinie sichtbar');
  Assert.AreEqual(90, mTop);
  TAtlasWelcomeTrends.Scale([-30, 20], [True, True], mBottom, mTop);
  Assert.AreEqual(-30, mBottom);
  Assert.AreEqual(20, mTop);
  TAtlasWelcomeTrends.Scale([0, 0], [True, True], mBottom, mTop);
  Assert.AreEqual(0, mBottom);
  Assert.AreEqual(10, mTop, 'nur Nullen: eine Einheit Luft');
  TAtlasWelcomeTrends.Scale([500, 20], [False, True], mBottom, mTop);
  Assert.AreEqual(20, mTop, 'Lücken zählen nicht');
end;

procedure TAtlasWelcomeTrendsTests.PreviousSkipsGaps;
var
  mTile: TAtlasTrendTile;
  mValue: Integer;
begin
  mTile := Default(TAtlasTrendTile);
  mTile.Values := [10, 20, 0, 40];
  mTile.Has := [True, True, False, True];
  Assert.IsTrue(mTile.HasLast);
  Assert.AreEqual(40, mTile.Last);
  Assert.IsTrue(mTile.Previous(mValue));
  Assert.AreEqual(20, mValue, 'über die Lücke hinweg');
  mTile.Has := [True, True, True, False];
  Assert.IsFalse(mTile.HasLast, 'letzter Build ohne Wert');
  Assert.IsTrue(mTile.Previous(mValue));
  Assert.AreEqual(0, mValue);
  mTile.Values := [5];
  mTile.Has := [True];
  Assert.IsFalse(mTile.Previous(mValue), 'ein Build: kein Vorwert');
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
  mText: string;
begin
  Result := ADefault;
  if FValues.TryGetValue(AName, mText) then
  begin
    Result := StrToIntDef(mText, ADefault);
  end;
end;

procedure TTrendStore.WriteInteger(const AName: string; AValue: Integer);
begin
  FValues.AddOrSetValue(AName, IntToStr(AValue));
end;

function TTrendStore.ReadString(const AName, ADefault: string): string;
begin
  if not FValues.TryGetValue(AName, Result) then
  begin
    Result := ADefault;
  end;
end;

procedure TTrendStore.WriteString(const AName, AValue: string);
begin
  FValues.AddOrSetValue(AName, AValue);
end;

procedure TAtlasTrendSettingsTests.Defaults;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.WelcomePageTrends);
  Assert.AreEqual(30, mSettings.WelcomePageTrendsPoints);
  Assert.AreEqual(TAtlasProjectTrendLog.cDefaultPoints, mSettings.WelcomePageTrendsPoints);
  Assert.AreEqual('warnings,ruleHits,todos,duration,methodLength', mSettings.WelcomePageTrendsSeries, 'alle fünf');
  Assert.AreEqual(TAtlasWelcomeTrends.cDefaultSeries, TAtlasPluginSettings.cDefaultTrendSeries);
end;

procedure TAtlasTrendSettingsTests.NormalizeClampsAndCleans;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.WelcomePageTrendsPoints := 1;
  mSettings.WelcomePageTrendsSeries := ' TODOS; foo warnings ';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinTrendPoints, mSettings.WelcomePageTrendsPoints);
  Assert.AreEqual('warnings,todos', mSettings.WelcomePageTrendsSeries);
  mSettings.WelcomePageTrendsPoints := 1000;
  mSettings.WelcomePageTrendsSeries := '';
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxTrendPoints, mSettings.WelcomePageTrendsPoints);
  Assert.AreEqual('', mSettings.WelcomePageTrendsSeries, 'leer = keine Kachel');
  Assert.AreEqual(TAtlasProjectTrendLog.cMinPoints, TAtlasPluginSettings.cMinTrendPoints);
  Assert.AreEqual(TAtlasProjectTrendLog.cMaxPoints, TAtlasPluginSettings.cMaxTrendPoints);
end;

procedure TAtlasTrendSettingsTests.SeriesNamesMatchFileKeys;
var
  mSeries: TAtlasTrendSeries;
  mSettings: TAtlasPluginSettings;
begin
  // Die Einstellungen kennen die Namen ohne die Zusammenfassung: Sie müssen denen der Datei entsprechen.
  for mSeries := Low(TAtlasTrendSeries) to High(TAtlasTrendSeries) do
  begin
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.WelcomePageTrendsSeries := TAtlasProjectSummaries.cTrendKeys[mSeries];
    mSettings.Normalize;
    Assert.AreEqual(TAtlasProjectSummaries.cTrendKeys[mSeries], mSettings.WelcomePageTrendsSeries);
    Assert.AreEqual(TAtlasProjectSummaries.cTrendKeys[mSeries], TAtlasWelcomeTrends.SeriesKey(mSeries));
  end;
end;

procedure TAtlasTrendSettingsTests.SaveAndLoadRoundTrip;
var
  mStore: IAtlasSettingsStore;
  mSaved, mLoaded: TAtlasPluginSettings;
begin
  mStore := TTrendStore.Create;
  mSaved := TAtlasPluginSettings.Defaults;
  mSaved.WelcomePageTrends := False;
  mSaved.WelcomePageTrendsPoints := 12;
  mSaved.WelcomePageTrendsSeries := 'todos,duration';
  mSaved.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('WelcomePageTrends', 1), 'Registry-Name');
  Assert.AreEqual(12, mStore.ReadInteger('WelcomePageTrendsPoints', 0));
  Assert.AreEqual('todos,duration', mStore.ReadString('WelcomePageTrendsSeries', ''));
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.WelcomePageTrends);
  Assert.AreEqual(12, mLoaded.WelcomePageTrendsPoints);
  Assert.AreEqual('todos,duration', mLoaded.WelcomePageTrendsSeries);
  // Leere Liste bleibt leer (alle Reihen ausgeblendet), statt auf die Vorgabe zurückzufallen.
  mSaved.WelcomePageTrendsSeries := '';
  mSaved.Save(mStore);
  mLoaded.Load(mStore);
  Assert.AreEqual('', mLoaded.WelcomePageTrendsSeries);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTrendsTests);
  TDUnitX.RegisterTestFixture(TAtlasTrendSettingsTests);

end.
