unit Atlas.IDE.Welcome.Composition.TileProjects;

// Bereich „Projekte“ (#592) für Kacheln anderer Module (#1455): baut aus dem
// laufenden Bereich, was IAtlasWelcomeProjects erreicht (Liste, gewähltes
// Projekt, Öffnen, Aktualisieren). Jeder Aufruf fragt den Bereich neu; ohne
// Bereich liefert er nichts bzw. tut nichts.

interface

uses
  System.SysUtils,
  Atlas.IDE.Welcome.Adapters.Projects,
  Atlas.IDE.Welcome.Adapters.Tiles;

type
  TAtlasWelcomeTileProjects = class
  public
    /// <summary>Zugriff auf den Bereich „Projekte“, den ACurrent gerade liefert (nil = keiner).</summary>
    class function Access(const ACurrent: TFunc<TAtlasIdeProjects>): TAtlasWelcomeProjectsAccess; static;
  end;

implementation

uses
  Atlas.Core.Welcome.Projects,
  Atlas.IDE.Contracts.WelcomeTiles;

/// <summary>Bereich „Projekte“; nil ohne Bereich.</summary>
function ProjectsOf(const ACurrent: TFunc<TAtlasIdeProjects>): TAtlasIdeProjects;
begin
  Result := ACurrent();
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

{ TAtlasWelcomeTileProjects }

class function TAtlasWelcomeTileProjects.Access(const ACurrent: TFunc<TAtlasIdeProjects>):
  TAtlasWelcomeProjectsAccess;
var
  mCurrent: TFunc<TAtlasIdeProjects>;
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
