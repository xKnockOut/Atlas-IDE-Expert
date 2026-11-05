unit Atlas.IDE.BuildTools.Composition;

// Modul Build-Werkzeuge (#1455, ADR 0017): einzige Unit, die „Beim Öffnen
// bauen“ (#764), die Projektaufgaben (#900), die Startprofile (#575) und die
// wirksamen Compiler-Schalter (#558) erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.build“ (Modulschalter buildTools, #1454)
// bei der Registry von Base an und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (OpenBuild, Tasks, StartProfiles,
//   CompilerSwitches),
// - Befehle (Palette), Einträge im Atlas-Menü („Compiler-Schalter“, Untermenü
//   „Aufgaben“ mit einem Eintrag je Aufgabe),
// - Hörer für Einstellungen und Thema,
// - für andere Module Startprofile und Projektaufgaben
//   (IAtlasBuildToolsSource, Atlas.IDE.Contracts.BuildTools); das Ende einer Aufgabe
//   geht an jeden IAtlasTaskListener.
// Die Build-Pipeline selbst (Läufer der Builds auf Auftrag, Prüfung vor dem
// Kompilieren, Release-Wächter, Bewertung) ist ein eigenes Modul
// (atlas.buildpipeline); dieses Modul erreicht die Builds auf Auftrag über
// den Vertrag IAtlasBuildJobs, die Compile-Ereignisse über TAtlasIdeHost. Seine
// Teilnehmer an den Compile-Ereignissen meldet es beim Stoppen ab.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.BuildTools,
  Atlas.IDE.Contracts.BuildPipeline;

type
  TAtlasBuildModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme, IAtlasBuildToolsSource)
  public const
    ModuleId = 'atlas.build';
    Switch = 'buildTools';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
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
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Build.SettingsSection,
  System.Types,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Modules.Contributions,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Build.Events,
  Atlas.Core.StartProfiles.Store,
  Atlas.Core.Tasks.Adapters.Process,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Build.OpenBuild,
  Atlas.IDE.Build.CompilerSwitches,
  Atlas.IDE.StartProfiles.Service,
  Atlas.IDE.Tasks.Projects,
  Atlas.IDE.Tasks.Runner,
  Atlas.UI.Tasks.Texts,
  Atlas.UI.Strings,
  Atlas.UI.Build.Strings;

const
  StartProfileExtra = 'startProfile';
  CompilerSwitchesExtra = 'compilerSwitches';
  /// <summary>Kennung der Einträge je Aufgabe im Untermenü „Aufgaben“.</summary>
  TaskEntryPrefix = 'Atlas.Task:';

var
  GScope: IAtlasModuleScope;
  GOpenBuild: TAtlasIdeOpenBuild;
  GTasks: TAtlasIdeTasks;
  /// <summary>Teilnehmer der Projektaufgaben an den Compile-Ereignissen (#900, tasks.beforeBuild).</summary>
  GTasksParticipant: TAtlasCompileParticipant;

{ Sichtbarkeit }

function CompilerSwitchesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.BuildCompilerSwitches;
end;

function StartProfilesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.StartProfiles and TAtlasIdeStartProfiles.Started;
end;

function TasksVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.TasksEnabled and (GTasks <> nil);
end;

{ Beim Öffnen bauen (#764) }

procedure StartOpenBuild;
begin
  GOpenBuild := TAtlasIdeOpenBuild.Create(TAtlasIdeHost.CompileEvents,
    procedure(AText: string)
    begin
      TAtlasIdeHost.Report(AText);
    end);
end;

procedure StopOpenBuild;
begin
  FreeAndNil(GOpenBuild);
end;

function OpenBuildStarted: Boolean;
begin
  Result := GOpenBuild <> nil;
end;

{ Projektaufgaben (#900) }

/// <summary>Prozessstart der Projektaufgaben (Adapter); eigene Routine, damit die Referenz nichts aus StartTasks
/// einfängt.</summary>
function TaskProcess: TAtlasTaskProcessRun;
begin
  Result :=
    function(const ATask: TAtlasTaskDefinition; ACodePage: Integer; const ACancelled: TFunc<Boolean>;
      const AOnLine: TAtlasTaskLineProc): TAtlasTaskProcessResult
    begin
      Result := TAtlasTaskProcess.Run(ATask, ACodePage, ACancelled, AOnLine);
    end;
end;

/// <summary>Ende einer Aufgabe an jeden IAtlasTaskListener (etwa die Schnellaktionen der Willkommensseite).</summary>
procedure AnnounceTask(const AProject: string; const ARun: TAtlasTaskRun);
var
  mResult: TAtlasTaskResult;
  mItem: IInterface;
  mListener: IAtlasTaskListener;
begin
  if AProject = '' then
  begin
    Exit;
  end;
  mResult := Default(TAtlasTaskResult);
  mResult.Name := ARun.Name;
  mResult.Passed := ARun.Passed;
  mResult.Summary := TAtlasTaskTexts.LastResult(TAtlasTaskLastRun.From(ARun), True);
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasTaskListener) do
  begin
    if Supports(mItem, IAtlasTaskListener, mListener) then
    begin
      TAtlasGuard.Run(TAtlasFeature.Tasks,
        procedure
        begin
          mListener.TaskFinished(AProject, mResult);
        end);
    end;
  end;
end;

/// <summary>Builds auf Auftrag des Moduls Build-Pipeline (Vertrag); False ohne laufendes Modul.</summary>
function BuildJobs(out AJobs: IAtlasBuildJobs): Boolean;
var
  mItem: IInterface;
begin
  AJobs := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildJobs) do
  begin
    if Supports(mItem, IAtlasBuildJobs, AJobs) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Neubau nach bestandener Prüfung über die Builds auf Auftrag (#261) der Build-Pipeline.</summary>
function RebuildAfterTasks(const AProject: TAtlasCompileProject; out AReason: string): Boolean;
var
  mJobs: IAtlasBuildJobs;
  mJob: TAtlasBuildJob;
begin
  if not BuildJobs(mJobs) then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
    Exit(False);
  end;
  mJob := Default(TAtlasBuildJob);
  mJob.Project := AProject.FileName;
  // Dieselbe Art wie der angehaltene Compile; Make für alles außer Build und Check.
  mJob.Kind := TAtlasBuildJobKind.Make;
  if AProject.Kind = TAtlasCompileKind.Build then
  begin
    mJob.Kind := TAtlasBuildJobKind.Build;
  end
  else if AProject.Kind = TAtlasCompileKind.Check then
  begin
    mJob.Kind := TAtlasBuildJobKind.Check;
  end;
  // Auftraggeber '' wie ein Build des Benutzers: Tests nach dem Build und die übrigen Teilnehmer laufen mit.
  Result := mJobs.Start(mJob, nil, AReason);
end;

procedure StartTasks;
var
  mEvents: TAtlasCompileEvents;
begin
  GTasks := TAtlasIdeTasks.Create(TaskProcess());
  GTasks.OnRebuild := RebuildAfterTasks;
  GTasks.OnFinished := AnnounceTask;
  // Projektaufgaben vor dem Build (tasks.beforeBuild); beim Stoppen wieder abgemeldet.
  mEvents := TAtlasIdeHost.CompileEvents;
  if mEvents <> nil then
  begin
    GTasksParticipant := TAtlasIdeTasks.CreateParticipant(
      function: TAtlasIdeTasks
      begin
        Result := GTasks;
      end);
    mEvents.Add(GTasksParticipant);
  end;
end;

procedure StopTasks;
var
  mEvents: TAtlasCompileEvents;
begin
  mEvents := TAtlasIdeHost.CompileEvents;
  if (mEvents <> nil) and (GTasksParticipant <> nil) then
  begin
    mEvents.Remove(GTasksParticipant);
  end;
  GTasksParticipant := nil;
  // Laufende Aufgaben enden mit dem Läufer; ihre Befunde verschwinden mit ihm. Schutznetz: Die Befunde
  // gehen auch dann weg, wenn der Abbau des Läufers scheitert.
  try
    FreeAndNil(GTasks);
  finally
    TAtlasIdeTaskProjects.ClearFindings;
  end;
end;

function TasksStarted: Boolean;
begin
  Result := GTasks <> nil;
end;

/// <summary>AProc der Projektaufgaben, abgesichert; ohne Läufer nichts.</summary>
function TasksCommand(const AProc: TProc<TAtlasIdeTasks>): TProc;
begin
  Result :=
    procedure
    begin
      if GTasks <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            AProc(GTasks);
          end);
      end;
    end;
end;

function TaskMenuRun(const AName: string): TProc;
begin
  Result :=
    procedure
    begin
      if GTasks <> nil then
      begin
        TAtlasGuard.Run(TAtlasFeature.Tasks,
          procedure
          begin
            GTasks.RunFromMenu(AName);
          end);
      end;
    end;
end;

{ Startprofile (#575) }

/// <summary>Startprofil im Zusatzfeld der Statusleiste; ohne startProfiles.statusField kein Feld.</summary>
procedure ShowStartProfileStatus(const AText, AHint: string);
begin
  if (AText = '') or not TAtlasIdeSettings.Current.StartProfilesStatusField then
  begin
    TAtlasIdeHost.SetStatusExtra(StartProfileExtra, '');
    Exit;
  end;
  TAtlasIdeHost.SetStatusField(StartProfileExtra, AText, AHint,
    procedure(APoint: TPoint)
    begin
      TAtlasIdeStartProfiles.ShowPicker;
    end);
end;

procedure StartStartProfiles;
begin
  TAtlasIdeStartProfiles.SetStatusHandler(ShowStartProfileStatus);
  TAtlasIdeStartProfiles.Start;
end;

procedure StopStartProfiles;
begin
  // Stop meldet noch Text '' und entfernt so das Feld; danach kein Empfänger mehr.
  TAtlasIdeStartProfiles.Stop;
  TAtlasIdeStartProfiles.SetStatusHandler(nil);
  TAtlasIdeHost.SetStatusExtra(StartProfileExtra, '');
end;

function StartProfilesStarted: Boolean;
begin
  Result := TAtlasIdeStartProfiles.Started;
end;

{ Compiler-Schalter (#558) }

procedure ShowSwitchesStatus(const AText, AHint: string);
begin
  if AText = '' then
  begin
    TAtlasIdeHost.SetStatusExtra(CompilerSwitchesExtra, '');
    Exit;
  end;
  TAtlasIdeHost.SetStatusField(CompilerSwitchesExtra, AText, AHint,
    procedure(APoint: TPoint)
    begin
      TAtlasIdeCompilerSwitches.ShowWindow;
    end);
end;

procedure StartCompilerSwitches;
begin
  // Fragt den Server nur, wenn er ohnehin läuft.
  TAtlasIdeCompilerSwitches.Start(
    function: TLspSession
    begin
      Result := TAtlasIdeHost.RunningSession;
    end, ShowSwitchesStatus);
end;

procedure StopCompilerSwitches;
begin
  TAtlasIdeCompilerSwitches.Release;
  TAtlasIdeHost.SetStatusExtra(CompilerSwitchesExtra, '');
end;

function CompilerSwitchesStarted: Boolean;
begin
  Result := TAtlasIdeCompilerSwitches.Started;
end;

{ Befehle }

function Guarded(AFeature: TAtlasFeature; const AProc: TProc): TProc;
begin
  Result :=
    procedure
    begin
      TAtlasGuard.Run(AFeature, AProc);
    end;
end;

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

function TAtlasBuildModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := ModuleId;
  Result.Name := 'Build-Werkzeuge';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Die Compiler-Schalter liefen schon im abgesicherten Start; die übrigen Teile verlangen den normalen Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
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

function TAtlasBuildModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Wirksame Compiler-Schalter (#558); nur sichtbar, solange build.compilerSwitches an ist.
    Command('Atlas.CompilerSwitches', TAtlasBuildTextId.CompilerSwitchesCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeCompilerSwitches.ShowWindow), CompilerSwitchesVisible),
    // Projektaufgaben (#900): sichtbar, solange tasks.enabled an ist und der Läufer läuft.
    Command('Atlas.RunTask', TAtlasBuildTextId.TasksRunCommand, TasksCommand(ChooseTask), TasksVisible),
    Command('Atlas.RunChecks', TAtlasBuildTextId.TasksRunChecksCommand, TasksCommand(RunChecks), TasksVisible),
    Command('Atlas.RepeatTask', TAtlasBuildTextId.TasksRepeatCommand, TasksCommand(RepeatTask), TasksVisible),
    Command('Atlas.CancelTasks', TAtlasBuildTextId.TasksCancelCommand, TasksCommand(CancelTasks), TasksVisible),
    Command('Atlas.TasksOutput', TAtlasBuildTextId.TasksOutputCommand, TasksCommand(ToggleTasksOutput), TasksVisible),
    Command('Atlas.TasksFindings', TAtlasBuildTextId.TasksFindingsCommand, TasksCommand(ChooseTaskFindings),
      TasksVisible),
    // Startprofile (#575): Auswahl für das aktive Projekt; sichtbar, solange StartProfiles an ist.
    Command('Atlas.StartProfile', TAtlasBuildTextId.StartProfilesCommand,
      Guarded(TAtlasFeature.Build, TAtlasIdeStartProfiles.ShowPicker), StartProfilesVisible)];
end;

function MenuEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := TAtlasMenuPlace.AtlasMenu;
end;

/// <summary>Eintrag ohne Befehl im Untermenü „Aufgaben“; ARun nil = ausgegraut.</summary>
function TaskEntry(const AId, ACaption: string; const ARun: TProc): TAtlasMenuEntry;
begin
  Result := MenuEntry(AId);
  Result.Section := TAtlasBuildStrings.Text(TAtlasBuildTextId.MenuGroupTasks);
  Result.Caption := ACaption;
  Result.Run := ARun;
end;

function TAtlasBuildModule.MenuEntries: TArray<TAtlasMenuEntry>;
var
  mItem: TAtlasTaskMenuItem;
  mItems: TArray<TAtlasTaskMenuItem>;
begin
  // Wirksame Compiler-Schalter an der Cursorposition (#558).
  Result := [MenuEntry('Atlas.CompilerSwitches')];
  // Untermenü „Aufgaben“ (#900): ohne Läufer bzw. mit tasks.enabled aus fehlt es; Base fragt bei jedem Öffnen.
  if not TasksVisible then
  begin
    Exit;
  end;
  mItems := nil;
  TAtlasGuard.Run(TAtlasFeature.Tasks,
    procedure
    begin
      mItems := GTasks.MenuItems;
    end);
  for mItem in mItems do
  begin
    Result := Result + [TaskEntry(TaskEntryPrefix + mItem.Name, mItem.Caption, TaskMenuRun(mItem.Name))];
  end;
  if Length(mItems) = 0 then
  begin
    Result := Result + [TaskEntry(TaskEntryPrefix, TAtlasBuildStrings.Text(TAtlasBuildTextId.TasksMenuEmpty), nil)];
  end;
end;

procedure TAtlasBuildModule.ApplySettings;
begin
  // tasks.onlyFindings und Tasten der Projektaufgaben (#900).
  if GTasks <> nil then
  begin
    GTasks.ApplySettings;
  end;
  // build.compilerSwitches, build.showSwitchesInStatusBar (#558).
  TAtlasIdeCompilerSwitches.ApplySettings;
  // startProfiles.enabled aus: Zeitgeber und Feld weg (die Feature-Tabelle startet sie wieder);
  // startProfiles.statusField oder .atlas geändert: Feld neu melden (#575).
  if not TAtlasIdeSettings.Current.StartProfiles then
  begin
    StopStartProfiles;
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
    Result := GTasks.TaskNamesOf(AProject);
  end;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasBuildSettingsSection.ProvideIn(GScope);
end;

function TAtlasBuildModule.RunTask(const AProject, AName: string; out AReason: string): Boolean;
begin
  AReason := '';
  if not TasksVisible then
  begin
    AReason := TAtlasBuildStrings.Text(TAtlasBuildTextId.WelcomeQuickReasonTasksOff);
    Exit(False);
  end;
  Result := GTasks.RunInProject(AProject, AName, AReason);
end;

class function TAtlasBuildModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Beim Öffnen bauen: nur im normalen Start, mit den Compile-Ereignissen und solange BuildOnOpen an ist.
    TAtlasFeaturePart.When('OpenBuild',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.BuildOnOpen and
          (TAtlasIdeHost.CompileEvents <> nil);
      end, OpenBuildStarted, StartOpenBuild, StopOpenBuild),
    // Projektaufgaben (#900): nur im normalen Start und solange tasks.enabled an ist.
    TAtlasFeaturePart.When('Tasks',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.TasksEnabled;
      end, TasksStarted, StartTasks, StopTasks),
    // Startprofile (#575): nur im normalen Start und solange StartProfiles an ist; liest .atlas über TeamFile.
    TAtlasFeaturePart.When('StartProfiles',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.StartProfiles;
      end, StartProfilesStarted, StartStartProfiles, StopStartProfiles),
    // Wirksame Compiler-Schalter an der Cursorposition (#558): Fenster, Befehl und Statusfeld; aus = kein Zeitgeber.
    TAtlasFeaturePart.When('CompilerSwitches',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.BuildCompilerSwitches;
      end, CompilerSwitchesStarted, StartCompilerSwitches, StopCompilerSwitches)];
end;

class function TAtlasBuildModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasBuildModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasBuildModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  // Vertrag zwischen Modulen: Startprofile und Projektaufgaben für die Schnellaktionen der Willkommensseite (#764).
  GScope.Provide(IAtlasBuildToolsSource, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasBuildModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasBuildModule.RegisterModule;

finalization
  TAtlasBuildModule.UnregisterModule;

end.
