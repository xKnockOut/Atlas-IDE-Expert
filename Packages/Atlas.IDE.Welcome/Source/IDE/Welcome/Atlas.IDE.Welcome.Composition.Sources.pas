unit Atlas.IDE.Welcome.Composition.Sources;

// Quellen der Bereiche der Willkommensseite (#753) anlegen und verbinden:
// „Neu in Atlas“, „Projekte“, „Projektverlauf“, „Nicht gesichert“,
// Schnellaktionen, „Weiterarbeiten“ mit dem Reiter „Issues“, Zustand,
// „Atlas entdecken“, Hilfe und Einrichtung. Die Dienste kommen von Base
// (TAtlasIdeHost) und anderen Modulen (TAtlasWelcomeNeighbors). Dazu die Ziele
// der Ereignisse anderer Module (Aufgaben, Testläufe, Befehlsnutzung).

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.IDE.Welcome.Composition.Areas,
  Atlas.IDE.Welcome.Adapters.ContinueIssues,
  Atlas.IDE.Welcome.Adapters.Listener;

type
  /// <summary>Führt AProc als benannten Schritt aus (Startzeiten in atlas.log).</summary>
  TAtlasWelcomeStep = reference to procedure(const AName: string; const AProc: TProc);

  TAtlasWelcomeSourcesBuild = class
  public
    class procedure Warn(AText: string); static;
    class procedure Execute(AId: string); static;
    class function PaletteCommands: TArray<TAtlasCommand>; static;
    /// <summary>„Neu in Atlas“ (#756), „Projekte“ (#592), „Projektverlauf“ (#758) und „Nicht gesichert“ (#762).
    /// </summary>
    class procedure StartProjectSections(AAreas: TAtlasIdeWelcomeSources; const AStep: TAtlasWelcomeStep); static;
    /// <summary>Schnellaktionen (#764), „Weiterarbeiten“ (#755), Zustand (#754), „Atlas entdecken“ (#757), Hilfe
    /// (#766) und Einrichtung (#759).</summary>
    class procedure StartWorkSections(AAreas: TAtlasIdeWelcomeSources; const AStep: TAtlasWelcomeStep); static;
    /// <summary>Reiter „Issues“ der Quellen; nil ohne Quellen oder ohne „Weiterarbeiten“.</summary>
    class function Issues(AAreas: TAtlasIdeWelcomeSources): TAtlasIdeContinueIssues; static;
    /// <summary>Ereignisse anderer Module an die Quellen, die ACurrent gerade liefert; ohne (nil) fallen sie weg.
    /// </summary>
    class function ListenerHooks(const ACurrent: TFunc<TAtlasIdeWelcomeSources>): TAtlasWelcomeListenerHooks;
      static;
  end;

implementation

uses
  System.Generics.Collections,
  Atlas.Core.Projects.Contract.Summary,
  Atlas.Core.Welcome.Contract,
  Atlas.IDE.Base.Foundation.BuildTools,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Welcome.ContinueIssueLink,
  Atlas.IDE.Welcome.Adapters.WhatsNew,
  Atlas.IDE.Welcome.Adapters.Projects,
  Atlas.IDE.Welcome.Adapters.Trends,
  Atlas.IDE.Welcome.Adapters.Unsaved,
  Atlas.IDE.Welcome.Adapters.QuickActions,
  Atlas.IDE.Welcome.Adapters.Continue,
  Atlas.IDE.Welcome.Adapters.ContinueHost,
  Atlas.IDE.Welcome.Adapters.State,
  Atlas.IDE.Welcome.Adapters.Discover,
  Atlas.IDE.Welcome.Adapters.Help,
  Atlas.IDE.Welcome.Adapters.Setup,
  Atlas.IDE.Welcome.Neighbors;

procedure Note(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

function PaletteHas(AId: string): Boolean;
var
  mCommand: TAtlasCommand;
begin
  Result := False;
  for mCommand in TAtlasIdeHost.PaletteCommands do
  begin
    Result := Result or SameText(mCommand.Id, AId);
  end;
end;

procedure TryCommand(AId: string);
begin
  TAtlasIdeDiscover.TryCommand(AId);
end;

procedure ShowKeys;
begin
  TAtlasIdeHost.ShowKeyMap;
end;

procedure ShowVcsServer(AFolder: string);
begin
  TAtlasOptionsRegistration.ShowVcsServer(AFolder);
end;

/// <summary>Reiter „Issues“ von „Weiterarbeiten“ (#2052).</summary>
function CreateIssues(const AMessage: TProc<string>; AChanges: TDictionary<string, TAtlasWorkTab>;
  const AChanged: TProc): TAtlasIdeContinueIssueLink;
begin
  Result := TAtlasIdeContinueIssues.Create(AMessage, AChanges, AChanged);
end;

/// <summary>Schnellaktionen (#764) mit dem Stand aus „Projekte“ und den Diensten anderer Module.</summary>
function CreateQuickActions(ASource: TAtlasIdeProjects): TAtlasIdeQuickActions;
var
  mProjects: TAtlasQuickProjects;
begin
  mProjects := Default(TAtlasQuickProjects);
  if ASource <> nil then
  begin
    mProjects.VcsOf :=
      function(AProject: string): TAtlasProjectVcs
      begin
        Result := ASource.VcsOf(AProject);
      end;
    mProjects.OpenFolder :=
      procedure(AProject: string)
      begin
        ASource.OpenFolder(AProject);
      end;
    mProjects.Refresh :=
      procedure(AProject: string)
      begin
        ASource.Refresh(AProject);
      end;
  end;
  Result := TAtlasIdeQuickActions.Create(mProjects, Note);
  Result.Hooks := TAtlasWelcomeNeighbors.QuickActionHooks;
end;

{ TAtlasWelcomeSourcesBuild }

class procedure TAtlasWelcomeSourcesBuild.Warn(AText: string);
begin
  TAtlasIdeHost.Warning(AText);
end;

class procedure TAtlasWelcomeSourcesBuild.Execute(AId: string);
begin
  TAtlasIdeHost.ExecuteCommand(AId);
end;

class function TAtlasWelcomeSourcesBuild.PaletteCommands: TArray<TAtlasCommand>;
begin
  Result := TAtlasIdeHost.PaletteCommands;
end;

class procedure TAtlasWelcomeSourcesBuild.StartProjectSections(AAreas: TAtlasIdeWelcomeSources;
  const AStep: TAtlasWelcomeStep);
begin
  AStep('WhatsNew',
    procedure
    begin
      AAreas.WhatsNew := TAtlasIdeWhatsNew.Create(PaletteHas, Execute, Warn);
    end);
  AStep('Projects',
    procedure
    begin
      AAreas.Projects := TAtlasIdeProjects.Create(Warn);
    end);
  AStep('Trends',
    procedure
    begin
      AAreas.Trends := TAtlasIdeTrends.Create(AAreas.Projects);
    end);
  AStep('Unsaved',
    procedure
    begin
      AAreas.Unsaved := TAtlasIdeUnsaved.Create(Warn);
    end);
end;

class procedure TAtlasWelcomeSourcesBuild.StartWorkSections(AAreas: TAtlasIdeWelcomeSources;
  const AStep: TAtlasWelcomeStep);
begin
  // Meldungen tragen Pfade und gehen deshalb nur in die Meldungsansicht.
  AStep('QuickActions',
    procedure
    begin
      AAreas.QuickActions := CreateQuickActions(AAreas.Projects);
    end);
  AStep('Continue',
    procedure
    begin
      AAreas.ContinueWork := TAtlasIdeContinue.Create(Warn, TAtlasIdeContinueHost.Create(Warn), CreateIssues);
      AAreas.ContinueWork.OnServerAccess := ShowVcsServer;
    end);
  AStep('State',
    procedure
    begin
      AAreas.State := TAtlasIdeWelcomeState.CreateForHost;
    end);
  AStep('Discover',
    procedure
    begin
      AAreas.Discover := TAtlasIdeDiscover.Create(PaletteCommands, TryCommand, Warn);
    end);
  AStep('Help',
    procedure
    begin
      AAreas.Help := TAtlasIdeHelp.Create(ShowKeys);
    end);
  AStep('Setup',
    procedure
    begin
      AAreas.Setup := TAtlasIdeSetup.Create(Note, TAtlasWelcomeNeighbors.SetupBaseline(),
        TAtlasWelcomeNeighbors.SetupNewFile());
    end);
end;

class function TAtlasWelcomeSourcesBuild.Issues(AAreas: TAtlasIdeWelcomeSources): TAtlasIdeContinueIssues;
begin
  Result := nil;
  if (AAreas <> nil) and (AAreas.ContinueWork <> nil) then
  begin
    Result := AAreas.ContinueWork.Issues as TAtlasIdeContinueIssues;
  end;
end;

class function TAtlasWelcomeSourcesBuild.ListenerHooks(const ACurrent: TFunc<TAtlasIdeWelcomeSources>):
  TAtlasWelcomeListenerHooks;
var
  mCurrent: TFunc<TAtlasIdeWelcomeSources>;
begin
  mCurrent := ACurrent;
  Result := Default(TAtlasWelcomeListenerHooks);
  Result.TaskFinished :=
    procedure(AProject: string; AResult: TAtlasTaskResult)
    var
      mAreas: TAtlasIdeWelcomeSources;
    begin
      mAreas := mCurrent();
      if (mAreas <> nil) and (mAreas.QuickActions <> nil) then
      begin
        mAreas.QuickActions.TaskFinished(AProject, AResult);
      end;
    end;
  // Ergebnis in der Zeile des Projekts; die Karte Tests (#763) liest die Projekt-Zusammenfassung.
  Result.TestsFinished :=
    procedure(AProject: string; APassed, AFailed: Integer)
    var
      mAreas: TAtlasIdeWelcomeSources;
    begin
      mAreas := mCurrent();
      if (mAreas <> nil) and (mAreas.QuickActions <> nil) then
      begin
        mAreas.QuickActions.TestsFinished(AProject, APassed, AFailed);
      end;
    end;
  Result.UsageReset :=
    procedure
    var
      mAreas: TAtlasIdeWelcomeSources;
    begin
      mAreas := mCurrent();
      if (mAreas <> nil) and (mAreas.Discover <> nil) then
      begin
        mAreas.Discover.Refresh;
      end;
    end;
end;

end.
