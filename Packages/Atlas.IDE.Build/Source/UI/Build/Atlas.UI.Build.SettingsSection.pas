unit Atlas.UI.Build.SettingsSection;

// Abschnitt „Compiler“ des Moduls Build-Werkzeuge im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher
// Atlas.UI.Settings.Page.Tasks in Base): Modulschalter, wirksame Compiler-Schalter (#558), Startprofile (#575),
// Bauen beim Öffnen (build.onOpen, #1293) und Projektaufgaben aus atlas.json (#900). „Bauen beim Öffnen“ fasst
// build.onOpen und build.onOpenKind in einer Auswahl zusammen; der Abschnitt liest und schreibt sie selbst.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Section;

type
  TAtlasBuildSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.buildTools';
    cAreaId = 'Compiler';
  private
    FOpenBuild: TAtlasChoiceBox;
    FOpenBuildExclude: TEdit;
    procedure BuildOpenBuild;
    procedure BuildTasks;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Close; override;
    /// <summary>Zum Testen: nicht bauen, prüfen, Make, Build.</summary>
    property OpenBuildChoice: TAtlasChoiceBox read FOpenBuild;
    property OpenBuildExcludeEdit: TEdit read FOpenBuildExclude;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.OpenBuildSettings,
  Atlas.Core.Settings.Plugin.Store,
  Atlas.UI.Build.Strings;

const
  cOnOpenKey = 'build.onOpen';
  cOnOpenKindKey = 'build.onOpenKind';
  cOnOpenExcludeKey = 'build.onOpenExclude';
  /// <summary>Zielplattformen für Bauen beim Öffnen (#1293), Namen wie in der IDE; Eintrag 0 = wie im Projekt.
  /// </summary>
  cPlatforms: array[0..7] of string = ('', 'Win32', 'Win64', 'Win64x', 'Linux64', 'OSXARM64', 'Android64',
    'iOSDevice64');

{ TAtlasBuildSettingsSection }

function TAtlasBuildSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasBuildSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasBuildSettingsSection.BuildRows;
begin
  ModuleSwitch('buildTools.enabled');
  // Wirksame Compiler-Schalter an der Cursorposition (#558).
  Switch('build.compilerSwitches', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsBuildCompilerSwitches));
  Switch('build.showSwitchesInStatusBar', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsBuildSwitchesInStatusBar));
  // Startprofile (#575).
  Switch('startProfiles.enabled', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsStartProfiles));
  Switch('startProfiles.statusField', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsStartProfilesStatusField));
  BuildOpenBuild;
  BuildTasks;
end;

procedure TAtlasBuildSettingsSection.BuildOpenBuild;
var
  mScope: TAtlasOpenBuildScope;
  mScopes, mPlatforms: TArray<string>;
  mPlatform: string;
begin
  Title(TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildTitle));
  // Reihenfolge: nicht bauen, dann wie TAtlasOpenBuildSettings.KindNames (check, make, build).
  FOpenBuild := OwnChoice(TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuild),
    [TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildNone),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildCheck),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildMake),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildBuild)], [cOnOpenKey, cOnOpenKindKey]);
  mScopes := nil;
  for mScope := Low(TAtlasOpenBuildScope) to High(TAtlasOpenBuildScope) do
  begin
    mScopes := mScopes + [TAtlasOpenBuildSettings.ScopeNames[mScope]];
  end;
  Choice('build.onOpenScope', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildScope),
    [TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildScopeAll),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildScopeActive)], mScopes);
  Number('build.onOpenDelayMs', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildDelay));
  FOpenBuildExclude := Line(cOnOpenExcludeKey, TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildExclude));
  Line('build.onOpenConfig', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildConfig));
  // Auswahl statt Freitext (#1293): Tippfehler griffen still nicht; der leere Eintrag heißt wie im Projekt.
  mPlatforms := nil;
  for mPlatform in cPlatforms do
  begin
    mPlatforms := mPlatforms + [mPlatform];
  end;
  Choice('build.onOpenPlatform', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsOpenBuildPlatform), mPlatforms,
    mPlatforms);
end;

procedure TAtlasBuildSettingsSection.BuildTasks;
var
  mNames: TArray<string>;
  mIndex: Integer;
begin
  // Projektaufgaben aus atlas.json (#900); Reihenfolge der Auswahl wie TasksBeforeBuildNames: off, warn, block.
  Title(TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksTitle));
  Switch('taskRunner.enabled', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksEnabled));
  Switch('taskRunner.problemsFromOutput', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksProblemsFromOutput));
  mNames := nil;
  for mIndex := Low(TasksBeforeBuildNames) to High(TasksBeforeBuildNames) do
  begin
    mNames := mNames + [TasksBeforeBuildNames[mIndex]];
  end;
  Choice('taskRunner.beforeBuild', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksBeforeBuild),
    [TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksBeforeBuildOff),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksBeforeBuildWarn),
    TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksBeforeBuildBlock)], mNames);
  Switch('taskRunner.saveBeforeRun', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksSaveBeforeRun));
  Switch('taskRunner.runChecksParallel', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksRunChecksParallel));
  Switch('taskRunner.onlyFindings', TAtlasBuildStrings.Text(TAtlasBuildTextId.SettingsTasksOnlyFindings));
end;

procedure TAtlasBuildSettingsSection.Load(const AValues: IAtlasSettingsValues);
var
  mIndex: Integer;
  mKind: string;
begin
  if Closed then
  begin
    Exit;
  end;
  FOpenBuild.Choice := 0;
  if AValues.ReadBoolean(cOnOpenKey) then
  begin
    mKind := TAtlasOpenBuildSettings.KindName(TAtlasOpenBuildSettings.KindOf(AValues.ReadString(cOnOpenKindKey)));
    for mIndex := Low(TAtlasOpenBuildSettings.KindNames) to High(TAtlasOpenBuildSettings.KindNames) do
    begin
      if SameText(TAtlasOpenBuildSettings.KindNames[mIndex], mKind) then
      begin
        FOpenBuild.Choice := mIndex + 1;
      end;
    end;
  end;
  FOpenBuildExclude.Text := TAtlasOpenBuildSettings.NormalizedExclude(AValues.ReadString(cOnOpenExcludeKey));
end;

procedure TAtlasBuildSettingsSection.Save(const AValues: IAtlasSettingsValues);
begin
  if Closed then
  begin
    Exit;
  end;
  // „nicht bauen“ behält die Art für das nächste Einschalten (Schnellschalter).
  AValues.WriteBoolean(cOnOpenKey, FOpenBuild.Choice > 0);
  if (FOpenBuild.Choice > 0) and (FOpenBuild.Choice - 1 <= High(TAtlasOpenBuildSettings.KindNames)) then
  begin
    AValues.WriteString(cOnOpenKindKey, TAtlasOpenBuildSettings.KindNames[FOpenBuild.Choice - 1]);
  end;
  AValues.WriteString(cOnOpenExcludeKey,
    TAtlasOpenBuildSettings.NormalizedExclude(AValues.ReadString(cOnOpenExcludeKey)));
end;

procedure TAtlasBuildSettingsSection.Close;
begin
  // Die Elemente gehören der Seite: nur die Verweise lösen.
  FOpenBuild := nil;
  FOpenBuildExclude := nil;
  inherited Close;
end;

end.
