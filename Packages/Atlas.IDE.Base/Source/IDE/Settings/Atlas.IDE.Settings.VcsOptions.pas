unit Atlas.IDE.Settings.VcsOptions;

// Seite Versionsverwaltung in Tools › Optionen › Atlas (#1285, #1286, #1287):
// Fundort ohne Prozess, „Prüfen“ und „Aktuelles Projekt“ über TAtlasIdeVcs im
// Hintergrund, Serverzugang prüfen und anmelden. Ein Ergebnis geht nur an die
// Seite, für die es bestellt wurde: AAlive (von der Optionsseite) sagt, ob sie
// noch offen und dieselbe ist.

interface

uses
  System.SysUtils,
  Atlas.UI.Settings.Page;

type
  TAtlasVcsOptions = class
  private
    class procedure ConnectTools(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>); static;
    class procedure ConnectProject(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>); static;
    class procedure ConnectServer(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>); static;
  public
    /// <summary>Haken der Seite Versionsverwaltung von APage setzen.</summary>
    class procedure Connect(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>); static;
    /// <summary>Zeile AFolder der Tabelle „Server“ im Hintergrund prüfen (#1287).</summary>
    class procedure CheckServer(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>;
      const AFolder: string); static;
  end;

implementation

uses
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.TeamFile,
  Atlas.UI.Settings.Page.VcsTools,
  Atlas.UI.Settings.Page.VcsProject,
  Atlas.UI.Settings.Page.VcsProjects;

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dem Abschnitt vcs der .atlas
/// für die Seite Versionsverwaltung (#1286).</summary>
function VcsProjectContext: TAtlasVcsProjectContext;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasVcsProjectContext.Empty;
  Result.ProjectFile := TAtlasIdeTeamFile.ActiveProject;
  if Result.ProjectFile = '' then
  begin
    Exit;
  end;
  Result.GroupFile := TAtlasIdeFiles.GroupOfProject(Result.ProjectFile);
  mTeam := TAtlasIdeTeamFile.Read(Result.ProjectFile);
  if mTeam.Vcs.Configured then
  begin
    Result.Team := [TAtlasVcsProjectMapping.FromTeamFile(Result.ProjectFile, mTeam.Vcs.Provider,
      mTeam.Vcs.MainBranch)];
  end;
end;

{ TAtlasVcsOptions }

class procedure TAtlasVcsOptions.Connect(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>);
begin
  APage.Part<TAtlasSettingsVcsProjectsPart>.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := VcsProjectContext;
    end;
  ConnectTools(APage, AAlive);
  ConnectProject(APage, AAlive);
  ConnectServer(APage, AAlive);
end;

class procedure TAtlasVcsOptions.ConnectTools(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>);
begin
  APage.Part<TAtlasSettingsVcsToolsPart>.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      Result := TAtlasIdeVcs.Locate(AKind, APath);
    end;
  APage.Part<TAtlasSettingsVcsToolsPart>.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    begin
      if not TAtlasIdeVcs.CheckTool(AKind, APath,
        procedure(ACheck: TAtlasVcsToolCheck)
        begin
          // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
          if AAlive() then
          begin
            APage.Part<TAtlasSettingsVcsToolsPart>.VcsCheckDone(ACheck);
          end;
        end) then
      begin
        // Nichts gestartet (Versionsverwaltung noch nicht bereit): Zustand ohne Prozess.
        APage.Part<TAtlasSettingsVcsToolsPart>.VcsCheckDone(TAtlasVcsToolChecks.Missing(AKind,
          TAtlasIdeVcs.Locate(AKind, APath)));
      end;
    end;
end;

class procedure TAtlasVcsOptions.ConnectProject(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>);
begin
  APage.Part<TAtlasSettingsVcsProjectPart>.OnVcsProject :=
    procedure
    var
      mProject, mGroup: string;
    begin
      // Aktive .dproj in der geöffneten .groupproj; Art und Hauptbranch nach vcs.projects und .atlas (#1286).
      mProject := TAtlasIdeTeamFile.ActiveProject;
      mGroup := '';
      if mProject <> '' then
      begin
        mGroup := TAtlasIdeFiles.GroupOfProject(mProject);
      end;
      TAtlasIdeVcs.QueryProject(mProject, mGroup,
        procedure(AState: TAtlasVcsProjectState)
        begin
          if AAlive() then
          begin
            APage.Part<TAtlasSettingsVcsProjectPart>.VcsProjectDone(AState);
          end;
        end);
    end;
end;

class procedure TAtlasVcsOptions.ConnectServer(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>);
begin
  // Serverzugang (#1287): Zustand nur aus der Sitzung, Prüfen und Anmelden nur auf Klick.
  APage.Part<TAtlasSettingsVcsServersPart>.OnVcsServerState :=
    function(AFolder: string): TAtlasVcsServerCheck
    begin
      Result := TAtlasIdeVcs.ServerState(AFolder);
    end;
  APage.Part<TAtlasSettingsVcsServersPart>.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      CheckServer(APage, AAlive, AFolder);
    end;
  APage.Part<TAtlasSettingsVcsServersPart>.OnVcsServerLogin :=
    function(const AFolder: string; const ACheck: TAtlasVcsServerCheck): Boolean
    var
      mFolder: string;
    begin
      mFolder := AFolder;
      // Nach dem Schließen der Konsole dieselbe Zeile erneut prüfen.
      Result := TAtlasIdeVcs.OpenServerLogin(ACheck,
        procedure
        begin
          if AAlive() then
          begin
            CheckServer(APage, AAlive, mFolder);
          end;
        end);
    end;
end;

class procedure TAtlasVcsOptions.CheckServer(APage: TAtlasSettingsPage; const AAlive: TFunc<Boolean>;
  const AFolder: string);
var
  mFolder: string;
begin
  mFolder := AFolder;
  if not TAtlasIdeVcs.CheckServer(mFolder,
    procedure(ACheck: TAtlasVcsServerCheck)
    begin
      // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
      if AAlive() then
      begin
        APage.Part<TAtlasSettingsVcsServersPart>.VcsServerDone(mFolder, ACheck);
      end;
    end) then
  begin
    APage.Part<TAtlasSettingsVcsServersPart>.VcsServerDone(mFolder, TAtlasVcsServerCheck.Empty);
  end;
end;

end.
