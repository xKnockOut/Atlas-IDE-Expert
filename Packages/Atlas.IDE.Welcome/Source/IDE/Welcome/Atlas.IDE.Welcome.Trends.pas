unit Atlas.IDE.Welcome.Trends;

// Bereich „Projektverlauf“ in der IDE (#758): Quelle des Bereichs
// (IAtlasTrendsSource) und Bereich atlas.history der Willkommensseite.
// - Projekt: das im Bereich „Projekte“ (#592) gewählte, ohne Auswahl das
//   oberste der Liste. Die Liste und die Zusammenfassungen kommen von
//   TAtlasIdeProjects (dieselben Dateien, schon geladen); der Bereich
//   „Projekte“ meldet Änderungen und Auswahl auch an diesen Bereich.
// - Messpunkte schreibt TAtlasIdeProjects nach jedem Build
//   (TAtlasProjectTrendLog); hier wird nur gelesen und nichts gerechnet.
// - welcomePage.trends aus: kein Bereich (und keine neuen Messpunkte);
//   welcomePage.trends.series wählt die Kacheln, welcomePage.trends.points
//   begrenzt die gezeigten Builds.

interface

uses
  System.SysUtils,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Trends,
  Atlas.UI.Welcome.Projects,
  Atlas.UI.Welcome.Trends;

type
  TAtlasIdeTrends = class(TInterfacedObject, IAtlasTrendsSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts: gleich nach „Projekte“.</summary>
    cOrder = 22;
  private
    FProjects: IAtlasProjectsSource;
    FStarted: Boolean;
    FTitle: string;
    FActive: Boolean;
  public
    /// <summary>AProjects: Bereich „Projekte“ mit Liste, Zusammenfassungen und Auswahl.</summary>
    constructor Create(const AProjects: IAtlasProjectsSource);
    /// <summary>Bereich und Fabrik anmelden.</summary>
    procedure Start;
    /// <summary>Bereich und Fabrik abmelden (beim Entladen).</summary>
    procedure Stop;
    /// <summary>Nach geänderten Einstellungen: Sichtbarkeit, Reihen und Anzahl der Punkte neu.</summary>
    procedure Refresh;
    function Section: TAtlasWelcomeSection;
    /// <summary>welcomePage.trends an?</summary>
    class function Active: Boolean; static;
    { IAtlasTrendsSource }
    function View: TAtlasTrendView;
  end;

implementation

uses
  System.Classes,
  Atlas.Core.Welcome.Projects,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeTrends }

constructor TAtlasIdeTrends.Create(const AProjects: IAtlasProjectsSource);
begin
  inherited Create;
  FProjects := AProjects;
end;

class function TAtlasIdeTrends.Active: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePageTrends;
end;

procedure TAtlasIdeTrends.Start;
var
  mKeep: IAtlasTrendsSource;
begin
  FStarted := True;
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cHistory,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeTrendsFrame;
    begin
      Frame := TAtlasWelcomeTrendsFrame.Create(AOwner);
      Frame.Source := mKeep;
      Result := Frame;
    end);
  FTitle := '';
  Refresh;
end;

procedure TAtlasIdeTrends.Stop;
begin
  if not FStarted then
  begin
    Exit;
  end;
  FStarted := False;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cHistory);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cHistory);
  FProjects := nil;
end;

function TAtlasIdeTrends.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cHistory, TAtlasWelcomeTrendsFrame.TitleText, cOrder,
    TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeTrends.Refresh;
var
  mNext: TAtlasWelcomeSection;
begin
  if not FStarted then
  begin
    Exit;
  end;
  mNext := Section;
  // Nur beim ersten Mal (oder nach einem Sprachwechsel) anmelden: Add meldet allen Beobachtern.
  if mNext.Title <> FTitle then
  begin
    FTitle := mNext.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(mNext);
    Exit;
  end;
  // welcomePage.trends umgeschaltet: Auswahl der Bereiche neu; sonst nur Reihen und Punkte.
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cHistory);
end;

function TAtlasIdeTrends.View: TAtlasTrendView;
var
  mEntries: TAtlasProjectEntries;
  mPaths: TArray<string>;
  mChosen: string;
  mIndex: Integer;
  mSeries: TAtlasTrendSeriesList;
begin
  Result := Default(TAtlasTrendView);
  if not FStarted or (FProjects = nil) or not Active then
  begin
    Exit;
  end;
  mEntries := FProjects.Entries;
  mPaths := nil;
  for mIndex := 0 to High(mEntries) do
  begin
    mPaths := mPaths + [mEntries[mIndex].Project];
  end;
  mChosen := TAtlasWelcomeTrends.Choose(mPaths, FProjects.Selected);
  for mIndex := 0 to High(mEntries) do
  begin
    if mEntries[mIndex].Project = mChosen then
    begin
      mSeries := TAtlasWelcomeTrends.ParseSeries(TAtlasIdeSettings.Current.WelcomePageTrendsSeries);
      Exit(TAtlasWelcomeTrends.View(mEntries[mIndex].Summary, mSeries,
        TAtlasIdeSettings.Current.WelcomePageTrendsPoints));
    end;
  end;
end;

end.
