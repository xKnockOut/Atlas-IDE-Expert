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
    Order = 22;
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
  Keep: IAtlasTrendsSource;
begin
  FStarted := True;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.History,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeTrendsFrame;
    begin
      Frame := TAtlasWelcomeTrendsFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  FTitle := '';
  Refresh;
end;

procedure TAtlasIdeTrends.Stop;
begin
  if not FStarted then
    Exit;
  FStarted := False;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.History);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.History);
  FProjects := nil;
end;

function TAtlasIdeTrends.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.History, TAtlasWelcomeTrendsFrame.TitleText, Order,
    TAtlasWelcomeColumn.Left,
    function: Boolean
    begin
      Result := Active;
    end);
end;

procedure TAtlasIdeTrends.Refresh;
var
  Next: TAtlasWelcomeSection;
begin
  if not FStarted then
    Exit;
  Next := Section;
  // Nur beim ersten Mal (oder nach einem Sprachwechsel) anmelden: Add meldet allen Beobachtern.
  if Next.Title <> FTitle then
  begin
    FTitle := Next.Title;
    FActive := Active;
    TAtlasWelcomeSections.Default.Add(Next);
    Exit;
  end;
  // welcomePage.trends umgeschaltet: Auswahl der Bereiche neu; sonst nur Reihen und Punkte.
  if FActive <> Active then
  begin
    FActive := Active;
    TAtlasWelcomeSections.Default.Changed;
  end;
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.History);
end;

function TAtlasIdeTrends.View: TAtlasTrendView;
var
  Entries: TAtlasProjectEntries;
  Paths: TArray<string>;
  Chosen: string;
  Index: Integer;
  Series: TAtlasTrendSeriesList;
begin
  Result := Default(TAtlasTrendView);
  if not FStarted or (FProjects = nil) or not Active then
    Exit;
  Entries := FProjects.Entries;
  Paths := nil;
  for Index := 0 to High(Entries) do
    Paths := Paths + [Entries[Index].Project];
  Chosen := TAtlasWelcomeTrends.Choose(Paths, FProjects.Selected);
  for Index := 0 to High(Entries) do
    if Entries[Index].Project = Chosen then
    begin
      Series := TAtlasWelcomeTrends.ParseSeries(TAtlasIdeSettings.Current.WelcomePageTrendsSeries);
      Exit(TAtlasWelcomeTrends.View(Entries[Index].Summary, Series,
        TAtlasIdeSettings.Current.WelcomePageTrendsPoints));
    end;
end;

end.
