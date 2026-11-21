unit Atlas.IDE.Welcome.Composition.Areas;

// Die Quellen der Bereiche der Atlas-Willkommensseite (#753), die der
// Steuerung (Atlas.IDE.Welcome.Commands) gehören: Setzen startet den Bereich,
// Refresh führt sie nach den Einstellungen nach, Stop hält sie in der
// Reihenfolge an, die das Beenden der IDE braucht, Release gibt sie frei.
// Die Steuerung kennt nur die Sicht Atlas.IDE.Welcome.Areas; hier hängen die
// Adapter. Je Quelle eine Schnittstelle, weil auch die Frames sie so halten.

interface

uses
  Atlas.Core.Welcome.Contract,
  Atlas.UI.Welcome.Contract,
  Atlas.IDE.Welcome.Areas,
  Atlas.IDE.Welcome.Adapters.WhatsNew,
  Atlas.IDE.Welcome.Adapters.Projects,
  Atlas.IDE.Welcome.Adapters.QuickActions,
  Atlas.IDE.Welcome.Adapters.Trends,
  Atlas.IDE.Welcome.Adapters.Unsaved,
  Atlas.IDE.Welcome.Adapters.Continue,
  Atlas.IDE.Welcome.Adapters.State,
  Atlas.IDE.Welcome.Adapters.Discover,
  Atlas.IDE.Welcome.Adapters.Help,
  Atlas.IDE.Welcome.Adapters.Setup;

type
  TAtlasIdeWelcomeSources = class(TAtlasIdeWelcomeAreas)
  private type
    TArea = (WhatsNew, Projects, QuickActions, Trends, Unsaved, ContinueWork, State, Discover, Help, Setup);
  private
    // Hält die Quellen am Leben; die Frames halten sie ebenfalls als Schnittstelle.
    FRefs: array[TArea] of IInterface;
    FWhatsNew: TAtlasIdeWhatsNew;
    FProjects: TAtlasIdeProjects;
    FQuickActions: TAtlasIdeQuickActions;
    FTrends: TAtlasIdeTrends;
    FUnsaved: TAtlasIdeUnsaved;
    FContinue: TAtlasIdeContinue;
    FState: TAtlasIdeWelcomeState;
    FDiscover: TAtlasIdeDiscover;
    FHelp: TAtlasIdeHelp;
    FSetup: TAtlasIdeSetup;
    procedure SetWhatsNew(AValue: TAtlasIdeWhatsNew);
    procedure SetProjects(AValue: TAtlasIdeProjects);
    procedure SetQuickActions(AValue: TAtlasIdeQuickActions);
    procedure SetTrends(AValue: TAtlasIdeTrends);
    procedure SetUnsaved(AValue: TAtlasIdeUnsaved);
    procedure SetContinue(AValue: TAtlasIdeContinue);
    procedure SetState(AValue: TAtlasIdeWelcomeState);
    procedure SetDiscover(AValue: TAtlasIdeDiscover);
    procedure SetHelp(AValue: TAtlasIdeHelp);
    procedure SetSetup(AValue: TAtlasIdeSetup);
  public
    /// <summary>Titel, Reihenfolge und Inhalt nach den Einstellungen (bei jedem Sync der Steuerung).</summary>
    procedure Refresh; override;
    /// <summary>Alle anhalten (Beenden der IDE oder Entladen).</summary>
    procedure Stop; override;
    /// <summary>Nach den Frames: alle Quellen freigeben.</summary>
    procedure Release; override;
    function News: IAtlasWhatsNewSource; override;
    function NewsActive: Boolean; override;
    function NewsOnTop: Boolean; override;
    procedure AnnounceNews(const AItems: TArray<TAtlasWhatsNewItem>); override;
    procedure ShowNews(AView: TAtlasWhatsNewView); override;
    /// <summary>Karte „Neu in Atlas“ (#756); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property WhatsNew: TAtlasIdeWhatsNew read FWhatsNew write SetWhatsNew;
    /// <summary>Bereich „Projekte“ (#592); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property Projects: TAtlasIdeProjects read FProjects write SetProjects;
    /// <summary>Schnellaktionen (#764); vor ContinueWork und vor dem ersten Sync setzen, nach Projects.</summary>
    property QuickActions: TAtlasIdeQuickActions read FQuickActions write SetQuickActions;
    /// <summary>Bereich „Projektverlauf“ (#758); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Trends: TAtlasIdeTrends read FTrends write SetTrends;
    /// <summary>Bereich „Nicht gesichert“ (#762); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Unsaved: TAtlasIdeUnsaved read FUnsaved write SetUnsaved;
    /// <summary>Bereich „Weiterarbeiten“ (#755); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// Nicht „Continue“: Das verdeckte in den Methoden die Prozedur System.Continue.</summary>
    property ContinueWork: TAtlasIdeContinue read FContinue write SetContinue;
    /// <summary>Zustandskachel „Atlas“ (#754); gehört danach der Steuerung (Start beim Setzen). nil = ohne.</summary>
    property State: TAtlasIdeWelcomeState read FState write SetState;
    /// <summary>Karte „Atlas entdecken“ (#757); gehört danach der Steuerung (Start beim Setzen). nil = ohne.
    /// </summary>
    property Discover: TAtlasIdeDiscover read FDiscover write SetDiscover;
    /// <summary>Bereich „Hilfe und Rückmeldung“ (#766); gehört danach der Steuerung (Start beim Setzen). nil =
    /// ohne.</summary>
    property Help: TAtlasIdeHelp read FHelp write SetHelp;
    /// <summary>Bereich „Projekt für Atlas einrichten“ (#759); gehört danach der Steuerung (Start beim Setzen).
    /// nil = ohne.</summary>
    property Setup: TAtlasIdeSetup read FSetup write SetSetup;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard;

{ TAtlasIdeWelcomeSources }

procedure TAtlasIdeWelcomeSources.SetWhatsNew(AValue: TAtlasIdeWhatsNew);
begin
  FWhatsNew := AValue;
  FRefs[TArea.WhatsNew] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetProjects(AValue: TAtlasIdeProjects);
begin
  FProjects := AValue;
  FRefs[TArea.Projects] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetQuickActions(AValue: TAtlasIdeQuickActions);
begin
  FQuickActions := AValue;
  FRefs[TArea.QuickActions] := AValue;
  // Die Bereiche reichen die Quelle an jeden neuen Frame weiter.
  if FProjects <> nil then
  begin
    FProjects.QuickActions := AValue;
  end;
  if FContinue <> nil then
  begin
    FContinue.QuickActions := AValue;
  end;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetTrends(AValue: TAtlasIdeTrends);
begin
  FTrends := AValue;
  FRefs[TArea.Trends] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetUnsaved(AValue: TAtlasIdeUnsaved);
begin
  FUnsaved := AValue;
  FRefs[TArea.Unsaved] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetContinue(AValue: TAtlasIdeContinue);
begin
  FContinue := AValue;
  FRefs[TArea.ContinueWork] := AValue;
  if AValue = nil then
  begin
    Exit;
  end;
  if FQuickActions <> nil then
  begin
    AValue.QuickActions := FQuickActions;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      AValue.Start;
    end);
end;

procedure TAtlasIdeWelcomeSources.SetState(AValue: TAtlasIdeWelcomeState);
begin
  FState := AValue;
  FRefs[TArea.State] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetDiscover(AValue: TAtlasIdeDiscover);
begin
  FDiscover := AValue;
  FRefs[TArea.Discover] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetHelp(AValue: TAtlasIdeHelp);
begin
  FHelp := AValue;
  FRefs[TArea.Help] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.SetSetup(AValue: TAtlasIdeSetup);
begin
  FSetup := AValue;
  FRefs[TArea.Setup] := AValue;
  if AValue <> nil then
  begin
    TAtlasGuard.Run(TAtlasFeature.WelcomePage,
      procedure
      begin
        AValue.Start;
      end);
  end;
end;

procedure TAtlasIdeWelcomeSources.Refresh;
begin
  // Titel und Reihenfolge der Karte „Neu in Atlas“ nach den Einstellungen (welcomePage.whatsNew).
  if FWhatsNew <> nil then
  begin
    FWhatsNew.Refresh;
  end;
  // Karte „Atlas entdecken“: eingeschaltete Funktionen und welcomePage.discover (#757).
  if FDiscover <> nil then
  begin
    FDiscover.Refresh;
  end;
  // Bereich „Hilfe und Rückmeldung“: welcomePage.help und keys.overview (#766).
  if FHelp <> nil then
  begin
    FHelp.Refresh;
  end;
  // Bereich „Projekt für Atlas einrichten“: welcomePage.projectSetup und .newFromTemplate (#759).
  if FSetup <> nil then
  begin
    FSetup.Refresh;
  end;
  // Bereich „Projektverlauf“: welcomePage.trends, .series und .points (#758).
  if FTrends <> nil then
  begin
    FTrends.Refresh;
  end;
  // Schnellaktionen: welcomePage.quickActions, .items, .console und Tasten (#764).
  if FQuickActions <> nil then
  begin
    FQuickActions.Refresh;
  end;
end;

procedure TAtlasIdeWelcomeSources.Stop;
begin
  // Vor „Projekte“: Die Schnellaktionen fragen dort nach dem Stand der Versionsverwaltung.
  if FQuickActions <> nil then
  begin
    FQuickActions.Stop;
  end;
  if FWhatsNew <> nil then
  begin
    FWhatsNew.Stop;
  end;
  if FTrends <> nil then
  begin
    FTrends.Stop;
  end;
  if FProjects <> nil then
  begin
    FProjects.Stop;
  end;
  if FUnsaved <> nil then
  begin
    FUnsaved.Stop;
  end;
  // Schreibt den Arbeitsstand des noch offenen Projekts (Beenden der IDE).
  if FContinue <> nil then
  begin
    FContinue.Stop;
  end;
  if FState <> nil then
  begin
    FState.Stop;
  end;
  if FDiscover <> nil then
  begin
    FDiscover.Stop;
  end;
  if FHelp <> nil then
  begin
    FHelp.Stop;
  end;
  if FSetup <> nil then
  begin
    FSetup.Stop;
  end;
end;

function TAtlasIdeWelcomeSources.News: IAtlasWhatsNewSource;
begin
  Result := FWhatsNew;
end;

function TAtlasIdeWelcomeSources.NewsActive: Boolean;
begin
  Result := (FWhatsNew <> nil) and FWhatsNew.Active;
end;

function TAtlasIdeWelcomeSources.NewsOnTop: Boolean;
begin
  Result := (FWhatsNew <> nil) and FWhatsNew.OnTop;
end;

procedure TAtlasIdeWelcomeSources.AnnounceNews(const AItems: TArray<TAtlasWhatsNewItem>);
begin
  if FWhatsNew <> nil then
  begin
    FWhatsNew.Announce(AItems);
  end;
end;

procedure TAtlasIdeWelcomeSources.ShowNews(AView: TAtlasWhatsNewView);
begin
  if FWhatsNew <> nil then
  begin
    FWhatsNew.Show(AView);
  end;
end;

procedure TAtlasIdeWelcomeSources.Release;
var
  mArea: TArea;
begin
  FWhatsNew := nil;
  FProjects := nil;
  FQuickActions := nil;
  FTrends := nil;
  FUnsaved := nil;
  FContinue := nil;
  FState := nil;
  FDiscover := nil;
  FHelp := nil;
  FSetup := nil;
  for mArea := Low(TArea) to High(TArea) do
  begin
    FRefs[mArea] := nil;
  end;
end;

end.
