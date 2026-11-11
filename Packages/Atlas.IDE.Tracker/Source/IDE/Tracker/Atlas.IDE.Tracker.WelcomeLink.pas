unit Atlas.IDE.Tracker.WelcomeLink;

// Verbindung der Kacheln des Trackers zur Willkommensseite (#1455,
// Modulregeln 2 und 6) über Atlas.IDE.Contracts.WelcomeTiles: Projekte und gewähltes
// Projekt (IAtlasWelcomeProjects), geänderte Kacheln (IAtlasWelcomeBoard).
// Beide fragt die Verbindung bei jedem Gebrauch neu über die Haken der
// Komposition; fehlt die Willkommensseite, ist die Liste leer, „Öffnen“ geht
// direkt an die IDE und Meldungen entfallen. Branch und Versionsverwaltung
// kommen aus den Projekt-Zusammenfassungen von Base, auch ohne
// Willkommensseite. Alles im Hauptthread.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.IDE.Contracts.WelcomeTiles;

type
  /// <summary>Wie die Verbindung die Dienste der Willkommensseite findet; jedes Feld darf fehlen.</summary>
  TAtlasTrackerWelcomeLookup = record
    Projects: TFunc<IAtlasWelcomeProjects>;
    Board: TFunc<IAtlasWelcomeBoard>;
  end;

  TAtlasTrackerWelcomeLink = class
  private
    FLookup: TAtlasTrackerWelcomeLookup;
    function ProjectsService: IAtlasWelcomeProjects;
    function BoardService: IAtlasWelcomeBoard;
  public
    constructor Create(const ALookup: TAtlasTrackerWelcomeLookup);
    /// <summary>Projekte des Bereichs „Projekte“ in dessen Reihenfolge; leer ohne Willkommensseite.</summary>
    function Projects: TArray<TAtlasWelcomeProject>;
    /// <summary>Dort gewähltes Projekt; '' ohne.</summary>
    function Selected: string;
    /// <summary>Anzeigename von AProject aus der Liste, sonst der Dateiname ohne Endung; '' ohne Projekt.</summary>
    function NameOf(const AProject: string): string;
    /// <summary>AProject öffnen: über die Willkommensseite, ohne sie direkt in der IDE.</summary>
    procedure Open(const AProject: string);
    /// <summary>Stand der Versionsverwaltung von AProject neu abfragen (nach „Beginnen“).</summary>
    class procedure Refresh(const AProject: string); static;
    /// <summary>Branch und Art der Versionsverwaltung von AProject aus der Zusammenfassung.</summary>
    class function VcsOf(const AProject: string): TAtlasProjectVcs; static;
    /// <summary>Inhalt der Kachel AId geändert.</summary>
    procedure TileChanged(const AId: string);
    /// <summary>Titel oder Schalter der Kachel AId geändert.</summary>
    procedure TileInfoChanged(const AId: string);
    /// <summary>Haken lösen (beim Stoppen des Moduls); danach wirkungslos.</summary>
    procedure Release;
  end;

implementation

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Projects.Summaries;

{ TAtlasTrackerWelcomeLink }

constructor TAtlasTrackerWelcomeLink.Create(const ALookup: TAtlasTrackerWelcomeLookup);
begin
  inherited Create;
  FLookup := ALookup;
end;

procedure TAtlasTrackerWelcomeLink.Release;
begin
  FLookup := Default(TAtlasTrackerWelcomeLookup);
end;

function TAtlasTrackerWelcomeLink.ProjectsService: IAtlasWelcomeProjects;
begin
  Result := nil;
  if Assigned(FLookup.Projects) then
  begin
    Result := FLookup.Projects();
  end;
end;

function TAtlasTrackerWelcomeLink.BoardService: IAtlasWelcomeBoard;
begin
  Result := nil;
  if Assigned(FLookup.Board) then
  begin
    Result := FLookup.Board();
  end;
end;

function TAtlasTrackerWelcomeLink.Projects: TArray<TAtlasWelcomeProject>;
var
  mService: IAtlasWelcomeProjects;
begin
  Result := nil;
  mService := ProjectsService;
  if mService <> nil then
  begin
    Result := mService.Projects;
  end;
end;

function TAtlasTrackerWelcomeLink.Selected: string;
var
  mService: IAtlasWelcomeProjects;
begin
  Result := '';
  mService := ProjectsService;
  if mService <> nil then
  begin
    Result := mService.Selected;
  end;
end;

function TAtlasTrackerWelcomeLink.NameOf(const AProject: string): string;
var
  mProject: TAtlasWelcomeProject;
begin
  Result := '';
  if AProject = '' then
  begin
    Exit;
  end;
  for mProject in Projects do
  begin
    if SameText(mProject.Project, AProject) then
    begin
      Exit(mProject.Name);
    end;
  end;
  Result := ChangeFileExt(ExtractFileName(AProject), '');
end;

procedure TAtlasTrackerWelcomeLink.Open(const AProject: string);
var
  mService: IAtlasWelcomeProjects;
  mActions: IOTAActionServices;
begin
  mService := ProjectsService;
  if mService <> nil then
  begin
    mService.Open(AProject);
  end
  else if FileExists(AProject) and Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    TAtlasGuard.RunIde(
      procedure
      begin
        mActions.OpenProject(AProject, True);
      end);
  end;
end;

class procedure TAtlasTrackerWelcomeLink.Refresh(const AProject: string);
var
  mSummaries: TAtlasIdeProjectSummaries;
begin
  mSummaries := TAtlasIdeProjectSummaries.Current;
  if mSummaries <> nil then
  begin
    mSummaries.Refresh(AProject);
  end;
end;

class function TAtlasTrackerWelcomeLink.VcsOf(const AProject: string): TAtlasProjectVcs;
var
  mSummaries: TAtlasIdeProjectSummaries;
begin
  Result := TAtlasProjectVcs.Empty;
  mSummaries := TAtlasIdeProjectSummaries.Current;
  if (mSummaries <> nil) and (AProject <> '') then
  begin
    Result := mSummaries.VcsOf(AProject);
  end;
end;

procedure TAtlasTrackerWelcomeLink.TileChanged(const AId: string);
var
  mBoard: IAtlasWelcomeBoard;
begin
  mBoard := BoardService;
  if mBoard <> nil then
  begin
    mBoard.TileChanged(AId);
  end;
end;

procedure TAtlasTrackerWelcomeLink.TileInfoChanged(const AId: string);
var
  mBoard: IAtlasWelcomeBoard;
begin
  mBoard := BoardService;
  if mBoard <> nil then
  begin
    mBoard.TileInfoChanged(AId);
  end;
end;

end.
