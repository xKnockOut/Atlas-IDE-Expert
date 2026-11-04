unit Atlas.UI.Settings.Page.Tasks;

// Reiter „Compiler“, zweiter Teil: Bauen beim Öffnen (build.onOpen) und Projektaufgaben (#900).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Compiler“, zweiter Teil: Bauen beim Öffnen (build.onOpen) und Projektaufgaben (#900).</summary>
  TAtlasSettingsTasksPart = class(TAtlasSettingsPagePart)
  private
    /// <summary>Beim Öffnen bauen (build.onOpen*): eine Auswahl „nicht bauen / Syntaxprüfung / Compilieren /
    /// Erzeugen“, Umfang in einer Gruppe, Wartezeit, ausgeschlossene Projekte, Konfiguration und Plattform
    /// (#1293).</summary>
    FOpenBuild: TAtlasChoiceBox;
    FOpenBuildScope: TAtlasChoiceBox;
    FOpenBuildDelay: TEdit;
    FOpenBuildExclude: TEdit;
    /// <summary>Projektaufgaben (#900, tasks.*): Schalter, Befunde, vor dem Build (aus / warnen / abbrechen),
    /// speichern, Prüfungen gleichzeitig, nur Befunde in der Ausgabe.</summary>
    FTasksEnabled: TCheckBox;
    FTasksProblemsFromOutput: TCheckBox;
    FTasksBeforeBuild: TAtlasChoiceBox;
    FTasksSaveBeforeRun: TCheckBox;
    FTasksRunChecksParallel: TCheckBox;
    FTasksOnlyFindings: TCheckBox;
    FOpenBuildConfig: TEdit;
    FOpenBuildPlatform: TAtlasChoiceBox;
    procedure AddOpenBuildSection;
    procedure LoadOpenBuild(const ASettings: TAtlasPluginSettings);
    procedure SaveOpenBuild(var ASettings: TAtlasPluginSettings);
    procedure AddTasksSection;
    procedure LoadTasks(const ASettings: TAtlasPluginSettings);
    procedure SaveTasks(var ASettings: TAtlasPluginSettings);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Zum Testen: Beim Öffnen bauen.</summary>
    property OpenBuildChoice: TAtlasChoiceBox read FOpenBuild;
    property OpenBuildScopeChoice: TAtlasChoiceBox read FOpenBuildScope;
    property OpenBuildDelayEdit: TEdit read FOpenBuildDelay;
    property OpenBuildExcludeEdit: TEdit read FOpenBuildExclude;
    /// <summary>Zum Testen: Projektaufgaben (#900).</summary>
    property TasksEnabledCheck: TCheckBox read FTasksEnabled;
    property TasksProblemsFromOutputCheck: TCheckBox read FTasksProblemsFromOutput;
    property TasksBeforeBuildChoice: TAtlasChoiceBox read FTasksBeforeBuild;
    property TasksSaveBeforeRunCheck: TCheckBox read FTasksSaveBeforeRun;
    property TasksRunChecksParallelCheck: TCheckBox read FTasksRunChecksParallel;
    property TasksOnlyFindingsCheck: TCheckBox read FTasksOnlyFindings;
    property OpenBuildConfigEdit: TEdit read FOpenBuildConfig;
    property OpenBuildPlatformChoice: TAtlasChoiceBox read FOpenBuildPlatform;
  end;

implementation

uses
  System.SysUtils,
  Atlas.UI.Strings,
  Atlas.Core.Build.OpenBuildSettings;

const
  /// <summary>Zielplattformen für Bauen beim Öffnen (#1293), Namen wie in der IDE; Eintrag 0 = wie im Projekt.
  /// </summary>
  OpenBuildPlatforms: array[0..7] of string = ('', 'Win32', 'Win64', 'Win64x', 'Linux64', 'OSXARM64', 'Android64',
    'iOSDevice64');

{ TAtlasSettingsTasksPart }

procedure TAtlasSettingsTasksPart.Build;
begin
  // Wirksame Compiler-Schalter an der Cursorposition (#558).
  BindCheck('BuildCompilerSwitches', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildCompilerSwitches)));
  BindCheck('BuildSwitchesInStatusBar', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildSwitchesInStatusBar)));
  // Startprofile (#575).
  BindCheck('StartProfiles', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfiles)));
  BindCheck('StartProfilesStatusField', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStartProfilesStatusField)));
  // Beim Öffnen eines Projekts oder einer Projektgruppe einmal bauen (build.onOpen).
  AddOpenBuildSection;
  // Projektaufgaben aus atlas.json (#900).
  AddTasksSection;
end;

procedure TAtlasSettingsTasksPart.AddOpenBuildSection;
begin
  AddTitle(TAtlasTextId.SettingsOpenBuildTitle);
  // Reihenfolge: nicht bauen, dann wie TAtlasOpenBuildSettings.KindNames (check, make, build).
  FOpenBuild := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuild),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildNone), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildMake), TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildBuild)]);
  // Reihenfolge wie TAtlasOpenBuildScope: alle, nur das aktive.
  FOpenBuildScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScope),
    [TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeAll),
    TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildScopeActive)]);
  FOpenBuildDelay := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildDelay));
  FOpenBuildExclude := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildExclude));
  FOpenBuildConfig := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildConfig));
  // Auswahl statt Freitext (#1293): Tippfehler griffen still nicht; der leere Eintrag heißt wie im Projekt.
  FOpenBuildPlatform := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsOpenBuildPlatform), OpenBuildPlatforms);
end;

procedure TAtlasSettingsTasksPart.LoadOpenBuild(const ASettings: TAtlasPluginSettings);
var
  Index: Integer;
begin
  FOpenBuild.Choice := 0;
  if ASettings.BuildOnOpen then
  begin
    for Index := Low(TAtlasOpenBuildSettings.KindNames) to High(TAtlasOpenBuildSettings.KindNames) do
    begin
      if SameText(TAtlasOpenBuildSettings.KindNames[Index],
        TAtlasOpenBuildSettings.KindName(TAtlasOpenBuildSettings.KindOf(ASettings.BuildOnOpenKind))) then
      begin
        FOpenBuild.Choice := Index + 1;
      end;
    end;
  end;
  FOpenBuildScope.Choice := Ord(TAtlasOpenBuildSettings.ScopeOf(ASettings.BuildOnOpenScope));
  FOpenBuildDelay.Text := IntToStr(ASettings.BuildOnOpenDelayMs);
  FOpenBuildExclude.Text := TAtlasOpenBuildSettings.NormalizedExclude(ASettings.BuildOnOpenExclude);
  FOpenBuildConfig.Text := ASettings.BuildOnOpenConfig;
  FOpenBuildPlatform.Choice := 0;
  for Index := 1 to High(OpenBuildPlatforms) do
  begin
    if TAtlasOpenBuildSettings.PickTarget(ASettings.BuildOnOpenPlatform, [OpenBuildPlatforms[Index]]) <> '' then
    begin
      FOpenBuildPlatform.Choice := Index;
    end;
  end;
end;

procedure TAtlasSettingsTasksPart.SaveOpenBuild(var ASettings: TAtlasPluginSettings);
begin
  // „nicht bauen“ behält die Art für das nächste Einschalten (Schnellschalter).
  ASettings.BuildOnOpen := FOpenBuild.Choice > 0;
  if (FOpenBuild.Choice > 0) and (FOpenBuild.Choice - 1 <= High(TAtlasOpenBuildSettings.KindNames)) then
  begin
    ASettings.BuildOnOpenKind := TAtlasOpenBuildSettings.KindNames[FOpenBuild.Choice - 1];
  end;
  if (FOpenBuildScope.Choice >= Ord(Low(TAtlasOpenBuildScope))) and
    (FOpenBuildScope.Choice <= Ord(High(TAtlasOpenBuildScope))) then
  begin
    ASettings.BuildOnOpenScope := TAtlasOpenBuildSettings.ScopeNames[TAtlasOpenBuildScope(FOpenBuildScope.Choice)];
  end;
  ASettings.BuildOnOpenDelayMs := StrToIntDef(FOpenBuildDelay.Text, ASettings.BuildOnOpenDelayMs);
  ASettings.BuildOnOpenExclude := TAtlasOpenBuildSettings.NormalizedExclude(FOpenBuildExclude.Text);
  ASettings.BuildOnOpenConfig := Trim(FOpenBuildConfig.Text);
  ASettings.BuildOnOpenPlatform := '';
  if (FOpenBuildPlatform.Choice > 0) and (FOpenBuildPlatform.Choice <= High(OpenBuildPlatforms)) then
  begin
    ASettings.BuildOnOpenPlatform := OpenBuildPlatforms[FOpenBuildPlatform.Choice];
  end;
end;

procedure TAtlasSettingsTasksPart.AddTasksSection;
begin
  AddTitle(TAtlasTextId.SettingsTasksTitle);
  FTasksEnabled := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksEnabled));
  FTasksProblemsFromOutput := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksProblemsFromOutput));
  // Reihenfolge wie TasksBeforeBuildNames: off, warn, block.
  FTasksBeforeBuild := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuild),
    [TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildOff),
    TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildWarn),
    TAtlasStrings.Text(TAtlasTextId.SettingsTasksBeforeBuildBlock)]);
  FTasksSaveBeforeRun := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksSaveBeforeRun));
  FTasksRunChecksParallel := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksRunChecksParallel));
  FTasksOnlyFindings := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTasksOnlyFindings));
end;

procedure TAtlasSettingsTasksPart.LoadTasks(const ASettings: TAtlasPluginSettings);
var
  mIndex: Integer;
begin
  FTasksEnabled.Checked := ASettings.TasksEnabled;
  FTasksProblemsFromOutput.Checked := ASettings.TasksProblemsFromOutput;
  // Unbekannt = „off“ wie beim Lesen der Einstellungen.
  FTasksBeforeBuild.Choice := 0;
  for mIndex := Low(TasksBeforeBuildNames) to High(TasksBeforeBuildNames) do
  begin
    if SameText(Trim(ASettings.TasksBeforeBuild), TasksBeforeBuildNames[mIndex]) then
    begin
      FTasksBeforeBuild.Choice := mIndex;
    end;
  end;
  FTasksSaveBeforeRun.Checked := ASettings.TasksSaveBeforeRun;
  FTasksRunChecksParallel.Checked := ASettings.TasksRunChecksParallel;
  FTasksOnlyFindings.Checked := ASettings.TasksOnlyFindings;
end;

procedure TAtlasSettingsTasksPart.SaveTasks(var ASettings: TAtlasPluginSettings);
begin
  ASettings.TasksEnabled := FTasksEnabled.Checked;
  ASettings.TasksProblemsFromOutput := FTasksProblemsFromOutput.Checked;
  if (FTasksBeforeBuild.Choice >= Low(TasksBeforeBuildNames)) and
    (FTasksBeforeBuild.Choice <= High(TasksBeforeBuildNames)) then
  begin
    ASettings.TasksBeforeBuild := TasksBeforeBuildNames[FTasksBeforeBuild.Choice];
  end;
  ASettings.TasksSaveBeforeRun := FTasksSaveBeforeRun.Checked;
  ASettings.TasksRunChecksParallel := FTasksRunChecksParallel.Checked;
  ASettings.TasksOnlyFindings := FTasksOnlyFindings.Checked;
end;

procedure TAtlasSettingsTasksPart.BindMarks;
begin
  FPage.Marks.Bind(FOpenBuild, ['BuildOnOpen', 'BuildOnOpenKind']);
  FPage.Marks.Bind(FOpenBuildScope, ['BuildOnOpenScope']);
  FPage.Marks.Bind(FOpenBuildDelay, ['BuildOnOpenDelayMs']);
  FPage.Marks.Bind(FOpenBuildExclude, ['BuildOnOpenExclude']);
  FPage.Marks.Bind(FTasksEnabled, ['TasksEnabled']);
  FPage.Marks.Bind(FTasksProblemsFromOutput, ['TasksProblemsFromOutput']);
  FPage.Marks.Bind(FTasksBeforeBuild, ['TasksBeforeBuild']);
  FPage.Marks.Bind(FTasksSaveBeforeRun, ['TasksSaveBeforeRun']);
  FPage.Marks.Bind(FTasksRunChecksParallel, ['TasksRunChecksParallel']);
  FPage.Marks.Bind(FTasksOnlyFindings, ['TasksOnlyFindings']);
  FPage.Marks.Bind(FOpenBuildConfig, ['BuildOnOpenConfig']);
  FPage.Marks.Bind(FOpenBuildPlatform, ['BuildOnOpenPlatform']);
end;

procedure TAtlasSettingsTasksPart.Load(const ASettings: TAtlasPluginSettings);
begin
  LoadOpenBuild(ASettings);
  LoadTasks(ASettings);
end;

procedure TAtlasSettingsTasksPart.Save(var ASettings: TAtlasPluginSettings);
begin
  SaveOpenBuild(ASettings);
  SaveTasks(ASettings);
end;

end.
