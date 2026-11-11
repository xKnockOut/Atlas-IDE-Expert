unit Atlas.IDE.VersionControl.Settings;

// Seite Versionsverwaltung in Tools › Optionen › Atlas › Module › Versionsverwaltung (#1285, #1286, #1287; seit
// #1905 im Modul): TAtlasIdeVcsSettings ist der IAtlasSettingsSectionProvider, den die Composition über den Scope
// anmeldet. Für jede Optionsseite entsteht ein TAtlasVcsSettingsSection mit den Haken dazu: Fundort ohne Prozess,
// „Prüfen“ und „Aktuelles Projekt“ über TAtlasIdeVcs im Hintergrund, Serverzugang prüfen und anmelden. Ein
// Ergebnis geht nur an den Abschnitt, für den es bestellt wurde, solange er offen ist (Alive).

interface

uses
  System.SysUtils,
  Atlas.UI.Settings.Contract,
  Atlas.UI.VersionControl.SettingsSection;

type
  TAtlasIdeVcsSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

  TAtlasVcsOptions = class
  private
    class procedure ConnectTools(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>); static;
    class procedure ConnectProject(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>); static;
    class procedure ConnectServer(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>); static;
  public
    /// <summary>Haken des Abschnitts setzen.</summary>
    class procedure Connect(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>); static;
    /// <summary>Zeile AFolder der Tabelle „Server“ im Hintergrund prüfen (#1287).</summary>
    class procedure CheckServer(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>;
      const AFolder: string); static;
  end;

implementation

uses
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Projects.VersionControl,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.ToolCheck,
  Atlas.Core.VersionControl.ServerCheck,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.TeamFile;

/// <summary>Aktives Projekt, geöffnete .groupproj (wenn es darin ist) und die Zeile aus dem Abschnitt vcs der .atlas
/// für die Seite Versionsverwaltung (#1286).</summary>
function VcsProjectContext: TAtlasVcsProjectContext;
var
  mTeam: TAtlasTeamSettings;
begin
  Result := TAtlasVcsProjectContext.Empty;
  Result.ProjectFile := TAtlasIdeFiles.ActiveProjectFile;
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

{ TAtlasIdeVcsSettings }

function TAtlasIdeVcsSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasVcsSettingsSection;
begin
  mSection := TAtlasVcsSettingsSection.Create;
  Result := mSection;
  TAtlasVcsOptions.Connect(mSection, mSection.Alive());
end;

{ TAtlasVcsOptions }


class procedure TAtlasVcsOptions.Connect(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>);
begin
  ASection.Projects.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := VcsProjectContext;
    end;
  ConnectTools(ASection, AAlive);
  ConnectProject(ASection, AAlive);
  ConnectServer(ASection, AAlive);
end;

class procedure TAtlasVcsOptions.ConnectTools(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>);
begin
  ASection.Tools.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      Result := TAtlasIdeVcs.Locate(AKind, APath);
    end;
  ASection.Tools.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    begin
      if not TAtlasIdeVcs.CheckTool(AKind, APath,
        procedure(ACheck: TAtlasVcsToolCheck)
        begin
          // Nur an die Seite, für die geprüft wurde, solange der Dialog offen ist.
          if AAlive() then
          begin
            ASection.Tools.VcsCheckDone(ACheck);
          end;
        end) then
      begin
        // Nichts gestartet (Versionsverwaltung noch nicht bereit): Zustand ohne Prozess.
        ASection.Tools.VcsCheckDone(TAtlasVcsToolChecks.Missing(AKind,
          TAtlasIdeVcs.Locate(AKind, APath)));
      end;
    end;
end;

class procedure TAtlasVcsOptions.ConnectProject(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>);
begin
  ASection.Project.OnVcsProject :=
    procedure
    var
      mProject, mGroup: string;
    begin
      // Aktive .dproj in der geöffneten .groupproj; Art und Hauptbranch nach vcs.projects und .atlas (#1286).
      mProject := TAtlasIdeFiles.ActiveProjectFile;
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
            ASection.Project.VcsProjectDone(AState);
          end;
        end);
    end;
end;

class procedure TAtlasVcsOptions.ConnectServer(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>);
begin
  // Serverzugang (#1287): Zustand nur aus der Sitzung, Prüfen und Anmelden nur auf Klick.
  ASection.Servers.OnVcsServerState :=
    function(AFolder: string): TAtlasVcsServerCheck
    begin
      Result := TAtlasIdeVcs.ServerState(AFolder);
    end;
  ASection.Servers.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      CheckServer(ASection, AAlive, AFolder);
    end;
  ASection.Servers.OnVcsServerLogin :=
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
            CheckServer(ASection, AAlive, mFolder);
          end;
        end);
    end;
end;

class procedure TAtlasVcsOptions.CheckServer(ASection: TAtlasVcsSettingsSection; const AAlive: TFunc<Boolean>;
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
        ASection.Servers.VcsServerDone(mFolder, ACheck);
      end;
    end) then
  begin
    ASection.Servers.VcsServerDone(mFolder, TAtlasVcsServerCheck.Empty);
  end;
end;

end.
