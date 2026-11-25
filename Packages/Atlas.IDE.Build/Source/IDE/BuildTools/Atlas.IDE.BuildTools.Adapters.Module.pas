unit Atlas.IDE.BuildTools.Adapters.Module;

// Modulklasse der Build-Werkzeuge (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.BuildTools.Composition) über den Scope des Moduls bereitstellt: Befehle (Palette), Einträge im
// Atlas-Menü (Untermenü „Build“ mit „Compiler-Schalter“ und einem Eintrag je Aufgabe), Einstellungen und Thema und
// für andere Module Startprofile und Projektaufgaben (IAtlasBuildToolsSource). Den Läufer der Projektaufgaben (#900)
// und das Stoppen der Startprofile (#575) reicht die Composition als TAtlasBuildModuleHooks herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Base.Foundation.BuildTools,
  Atlas.IDE.Tasks.Runner;

type
  /// <summary>Was die Modulklasse von der Composition braucht.</summary>
  TAtlasBuildModuleHooks = record
    /// <summary>Läufer der Projektaufgaben (#900); nil, solange der Teil Tasks nicht läuft.</summary>
    Tasks: TFunc<TAtlasIdeTasks>;
    /// <summary>Startprofile (#575) anhalten und ihr Statusfeld entfernen.</summary>
    StopStartProfiles: TProc;
  end;

  TAtlasBuildModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasBuildToolsSource)
  public const
    cModuleId = 'atlas.build';
    cSwitch = 'buildTools';
  private
    FActive: Boolean;
    FHooks: TAtlasBuildModuleHooks;
    function TasksVisible: Boolean;
  public
    constructor Create(const AHooks: TAtlasBuildModuleHooks);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
    function StartProfiles(const AProject: string; out AActive: string): TArray<string>;
    function RunStartProfile(const AProject, AProfile: string; out AReason: string): Boolean;
    function TaskNames(const AProject: string): TArray<string>;
    function RunTask(const AProject, AName: string; out AReason: string): Boolean;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.StartProfiles.Store,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.CompilerSwitches,
  Atlas.IDE.StartProfiles.Service,
  Atlas.UI.Build.Strings;

const
  /// <summary>Kennung der Einträge je Aufgabe im Untermenü „Build“.</summary>
  cTaskEntryPrefix = 'Atlas.Task:';

function CompilerSwitchesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BuildCompilerSwitches;
end;
function StartProfilesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.StartProfiles and TAtlasIdeStartProfiles.Started;
end;
function TAtlasBuildModule.TasksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TasksEnabled and (FHooks.Tasks() <> nil);
end;
/// <summary>AProc der Projektaufgaben aus ATasks, abgesichert; ohne Läufer nichts.</summary>
function TasksCommand(const ATasks: TFunc<TAtlasIdeTasks>; const AProc: TProc<TAtlasIdeTasks>): TProc;
begin
  Result :=
    procedure
    var
      mTasks: TAtlasIdeTasks;
    begin
      mTasks := ATasks();
      if mTasks <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            AProc(mTasks);
          end);
      end;
    end;
end;
function TaskMenuRun(const ATasks: TFunc<TAtlasIdeTasks>; const AName: string): TProc;
begin
  Result :=
    procedure
    var
      mTasks: TAtlasIdeTasks;
    begin
      mTasks := ATasks();
      if mTasks <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            mTasks.RunFromMenu(AName);
          end);
      end;
    end;
end;

{ Befehle }

function Command(const AId: string; ACaption: TAtlasBuildTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasBuildStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;
procedure ChooseTask(ATasks: TAtlasIdeTasks);
begin
  ATasks.Choose;
end;
procedure RunChecks(ATasks: TAtlasIdeTasks);
begin
  ATasks.RunChecks;
end;
procedure RepeatTask(ATasks: TAtlasIdeTasks);
begin
  ATasks.RepeatLast;
end;
procedure CancelTasks(ATasks: TAtlasIdeTasks);
begin
  ATasks.CancelAll;
end;
procedure ToggleTasksOutput(ATasks: TAtlasIdeTasks);
begin
  ATasks.ToggleOutput;
end;
procedure ChooseTaskFindings(ATasks: TAtlasIdeTasks);
begin
  ATasks.ChooseFindings;
end;
{ TAtlasBuildModule }

constructor TAtlasBuildModule.Create(const AHooks: TAtlasBuildModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasBuildModule.Info: TAtlasModuleInfo;
begin
  // Die Compiler-Schalter liefen schon im abgesicherten Start; die übrigen Teile verlangen den normalen Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Build-Werkzeuge', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;
procedure TAtlasBuildModule.Start;
begin
  FActive := True;
end;
procedure TAtlasBuildModule.Stop;
begin
  FActive := False;
end;
function TAtlasBuildModule.IsActive: Boolean;
begin
  Result := FActive;
end;
/// <summary>Eintrag im Untermenü „Build“ des Atlas-Menüs („-“ = Trennlinie).</summary>
function MenuEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := TAtlasMenuPlace.AtlasMenu;
  Result.Section := TAtlasBuildStrings.Text(TAtlasBuildTextId.MenuGroupBuild);
end;
/// <summary>Fenster unter Ansicht › Atlas.</summary>
function ViewEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := TAtlasMenuPlace.ViewMenu;
end;
/// <summary>Eintrag ohne Befehl für eine Projektaufgabe im Untermenü „Build“; ARun nil = ausgegraut.</summary>
function TaskEntry(const AId, ACaption: string; const ARun: TProc): TAtlasMenuEntry;
begin
  Result := MenuEntry(AId);
  Result.Caption := ACaption;
  Result.Run := ARun;
end;
function TAtlasBuildModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Wirksame Compiler-Schalter (#558); nur sichtbar, solange build.compilerSwitches an ist.
    Command('Atlas.CompilerSwitches', TAtlasBuildTextId.CompilerSwitchesCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, TAtlasIdeCompilerSwitches.ShowWindow), CompilerSwitchesVisible),
    // Projektaufgaben (#900): sichtbar, solange tasks.enabled an ist und der Läufer läuft.
    Command('Atlas.RunTask', TAtlasBuildTextId.TasksRunCommand, TasksCommand(FHooks.Tasks, ChooseTask), TasksVisible),
    Command('Atlas.RunChecks', TAtlasBuildTextId.TasksRunChecksCommand, TasksCommand(FHooks.Tasks, RunChecks), TasksVisible),
    Command('Atlas.RepeatTask', TAtlasBuildTextId.TasksRepeatCommand, TasksCommand(FHooks.Tasks, RepeatTask), TasksVisible),
    Command('Atlas.CancelTasks', TAtlasBuildTextId.TasksCancelCommand, TasksCommand(FHooks.Tasks, CancelTasks), TasksVisible),
    Command('Atlas.TasksOutput', TAtlasBuildTextId.TasksOutputCommand, TasksCommand(FHooks.Tasks, ToggleTasksOutput), TasksVisible),
    Command('Atlas.TasksFindings', TAtlasBuildTextId.TasksFindingsCommand, TasksCommand(FHooks.Tasks, ChooseTaskFindings),
      TasksVisible),
    // Startprofile (#575): Auswahl für das aktive Projekt; sichtbar, solange StartProfiles an ist.
    Command('Atlas.StartProfile', TAtlasBuildTextId.StartProfilesCommand,
      TAtlasGuard.Wrap(TAtlasFeature.Build, TAtlasIdeStartProfiles.ShowPicker), StartProfilesVisible)];
end;
function TAtlasBuildModule.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mItem: TAtlasTaskMenuItem;
  mItems: TArray<TAtlasTaskMenuItem>;
  mTasks: TAtlasIdeTasks;
begin
  // Wirksame Compiler-Schalter an der Cursorposition (#558), auch als Fenster unter Ansicht › Atlas.
  Result := [MenuEntry('Atlas.CompilerSwitches'), ViewEntry('Atlas.CompilerSwitches')];
  // Projektaufgaben (#900) hinter einer Trennlinie: ohne Läufer bzw. mit tasks.enabled aus fehlen sie; Base fragt
  // bei jedem Öffnen.
  if not TasksVisible then
  begin
    Exit;
  end;
  Result := Result + [MenuEntry('-')];
  mItems := nil;
  mTasks := FHooks.Tasks();
  TAtlasGuard.Run(TAtlasFeature.Tasks,
    procedure
    begin
      mItems := mTasks.MenuItems;
    end);
  for mItem in mItems do
  begin
    Result := Result + [TaskEntry(cTaskEntryPrefix + mItem.Name, mItem.Caption, TaskMenuRun(FHooks.Tasks, mItem.Name))];
  end;
  if Length(mItems) = 0 then
  begin
    Result := Result + [TaskEntry(cTaskEntryPrefix, TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksMenuEmpty), nil)];
  end;
end;
procedure TAtlasBuildModule.ApplySettings;
var
  mTasks: TAtlasIdeTasks;
begin
  // tasks.onlyFindings und Tasten der Projektaufgaben (#900).
  mTasks := FHooks.Tasks();
  if mTasks <> nil then
  begin
    mTasks.ApplySettings;
  end;
  // build.compilerSwitches, build.showSwitchesInStatusBar (#558).
  TAtlasIdeCompilerSwitches.ApplySettings;
  // startProfiles.enabled aus: Zeitgeber und Feld weg (die Feature-Tabelle startet sie wieder);
  // startProfiles.statusField oder .atlas geändert: Feld neu melden (#575).
  if not TAtlasIdeSettings.Current.StartProfiles then
  begin
    FHooks.StopStartProfiles();
  end
  else
  begin
    TAtlasIdeStartProfiles.Refresh;
  end;
end;
procedure TAtlasBuildModule.ThemeChanged;
begin
  TAtlasIdeCompilerSwitches.ThemeChanged;
end;
function TAtlasBuildModule.StartProfiles(const AProject: string; out AActive: string): TArray<string>;
var
  mEntry: TAtlasStartProfileEntry;
begin
  Result := nil;
  for mEntry in TAtlasIdeStartProfiles.Profiles(AProject) do
  begin
    Result := Result + [mEntry.Profile.Name];
  end;
  AActive := TAtlasIdeStartProfiles.ActiveName(AProject);
end;
function TAtlasBuildModule.RunStartProfile(const AProject, AProfile: string; out AReason: string): Boolean;
begin
  Result := TAtlasIdeStartProfiles.Run(AProject, AProfile, True, AReason);
end;
function TAtlasBuildModule.TaskNames(const AProject: string): TArray<string>;
begin
  Result := nil;
  if TasksVisible then
  begin
    Result := FHooks.Tasks().TaskNamesOf(AProject);
  end;
end;
function TAtlasBuildModule.RunTask(const AProject, AName: string; out AReason: string): Boolean;
begin
  AReason := '';
  if not TasksVisible then
  begin
    AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.WelcomeQuickReasonTasksOff);
    Exit(False);
  end;
  Result := FHooks.Tasks().RunInProject(AProject, AName, AReason);
end;

end.
