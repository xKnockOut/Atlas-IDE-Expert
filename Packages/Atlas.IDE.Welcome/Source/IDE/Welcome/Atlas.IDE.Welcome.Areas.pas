unit Atlas.IDE.Welcome.Areas;

// Die Quellen der Bereiche der Atlas-Willkommensseite (#753), die der
// Steuerung (Atlas.IDE.Welcome.Commands) gehören: Setzen startet den Bereich,
// Refresh führt sie nach den Einstellungen nach, Stop hält sie in der
// Reihenfolge an, die das Beenden der IDE braucht, Release gibt sie frei.
// Die Steuerung hält je Quelle eine Schnittstelle, weil auch die Frames sie
// so halten. Abgeteilt aus Atlas.IDE.Welcome.Commands (Atlas-Befunde).

interface

uses
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Trends,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.Continue,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover,
  Atlas.IDE.Welcome.Help,
  Atlas.IDE.Welcome.Setup;

type
  TAtlasIdeWelcomeAreas = class
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
    procedure Refresh;
    /// <summary>Alle anhalten (Beenden der IDE oder Entladen).</summary>
    procedure Stop;
    /// <summary>Nach den Frames: alle Quellen freigeben.</summary>
    procedure Release;
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

{ TAtlasIdeWelcomeAreas }

procedure TAtlasIdeWelcomeAreas.SetWhatsNew(AValue: TAtlasIdeWhatsNew);
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

procedure TAtlasIdeWelcomeAreas.SetProjects(AValue: TAtlasIdeProjects);
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

procedure TAtlasIdeWelcomeAreas.SetQuickActions(AValue: TAtlasIdeQuickActions);
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
    FContinue.Hooks.QuickActions := AValue;
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

procedure TAtlasIdeWelcomeAreas.SetTrends(AValue: TAtlasIdeTrends);
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

procedure TAtlasIdeWelcomeAreas.SetUnsaved(AValue: TAtlasIdeUnsaved);
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

procedure TAtlasIdeWelcomeAreas.SetContinue(AValue: TAtlasIdeContinue);
begin
  FContinue := AValue;
  FRefs[TArea.ContinueWork] := AValue;
  if AValue = nil then
  begin
    Exit;
  end;
  if FQuickActions <> nil then
  begin
    AValue.Hooks.QuickActions := FQuickActions;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      AValue.Start;
    end);
end;

procedure TAtlasIdeWelcomeAreas.SetState(AValue: TAtlasIdeWelcomeState);
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

procedure TAtlasIdeWelcomeAreas.SetDiscover(AValue: TAtlasIdeDiscover);
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

procedure TAtlasIdeWelcomeAreas.SetHelp(AValue: TAtlasIdeHelp);
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

procedure TAtlasIdeWelcomeAreas.SetSetup(AValue: TAtlasIdeSetup);
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

procedure TAtlasIdeWelcomeAreas.Refresh;
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

procedure TAtlasIdeWelcomeAreas.Stop;
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

procedure TAtlasIdeWelcomeAreas.Release;
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
