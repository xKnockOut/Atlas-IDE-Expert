unit Atlas.IDE.Welcome.TileProjects;

// Bereich „Projekte“ (#592) für Kacheln anderer Module (#1455): baut aus der
// laufenden Willkommensseite, was IAtlasWelcomeProjects erreicht (Liste,
// gewähltes Projekt, Öffnen, Aktualisieren). Jeder Aufruf fragt die Seite neu;
// ohne Seite oder ohne den Bereich liefert er nichts bzw. tut nichts.

interface

uses
  System.SysUtils,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Welcome.Tiles;

type
  TAtlasWelcomeTileProjects = class
  public
    /// <summary>Zugriff auf „Projekte“ der Seite, die ACurrent gerade liefert (nil = keine).</summary>
    class function Access(const ACurrent: TFunc<TAtlasIdeWelcome>): TAtlasWelcomeProjectsAccess; static;
  end;

implementation

uses
  Atlas.Core.Welcome.Projects,
  Atlas.IDE.Contracts.WelcomeTiles,
  Atlas.IDE.Welcome.Projects;

/// <summary>Bereich „Projekte“ der Seite; nil ohne Seite oder Bereich.</summary>
function ProjectsOf(const ACurrent: TFunc<TAtlasIdeWelcome>): TAtlasIdeProjects;
var
  mPage: TAtlasIdeWelcome;
begin
  Result := nil;
  mPage := ACurrent();
  if mPage <> nil then
  begin
    Result := mPage.Projects;
  end;
end;

function ListOf(AProjects: TAtlasIdeProjects): TArray<TAtlasWelcomeProject>;
var
  mEntry: TAtlasProjectEntry;
  mProject: TAtlasWelcomeProject;
begin
  Result := nil;
  if AProjects = nil then
  begin
    Exit;
  end;
  for mEntry in AProjects.Entries do
  begin
    mProject.Project := mEntry.Project;
    mProject.Name := mEntry.Name;
    Result := Result + [mProject];
  end;
end;

class function TAtlasWelcomeTileProjects.Access(const ACurrent: TFunc<TAtlasIdeWelcome>):
  TAtlasWelcomeProjectsAccess;
var
  mCurrent: TFunc<TAtlasIdeWelcome>;
begin
  mCurrent := ACurrent;
  Result := Default(TAtlasWelcomeProjectsAccess);
  Result.Projects :=
    function: TArray<TAtlasWelcomeProject>
    begin
      Result := ListOf(ProjectsOf(mCurrent));
    end;
  Result.Selected :=
    function: string
    var
      mProjects: TAtlasIdeProjects;
    begin
      Result := '';
      mProjects := ProjectsOf(mCurrent);
      if mProjects <> nil then
      begin
        Result := mProjects.Selected;
      end;
    end;
  Result.Open :=
    procedure(AProject: string)
    var
      mProjects: TAtlasIdeProjects;
    begin
      mProjects := ProjectsOf(mCurrent);
      if mProjects <> nil then
      begin
        mProjects.Open(AProject);
      end;
    end;
  Result.Refresh :=
    procedure(AProject: string)
    var
      mProjects: TAtlasIdeProjects;
    begin
      mProjects := ProjectsOf(mCurrent);
      if mProjects <> nil then
      begin
        mProjects.Refresh(AProject);
      end;
    end;
end;

end.
