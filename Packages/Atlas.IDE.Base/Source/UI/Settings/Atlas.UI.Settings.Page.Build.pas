unit Atlas.UI.Settings.Page.Build;

// Reiter „Compiler“: Aktion nach dem Speichern (#398, #548), Warnungen als Fehler und Prüfung vor dem Compile
// (#529, #530).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Compiler“: Aktion nach dem Speichern (#398, #548), Warnungen als Fehler und Prüfung vor dem
  /// Compile (#529, #530).</summary>
  TAtlasSettingsBuildPart = class(TAtlasSettingsPagePart)
  private
    FAfterSave: TAtlasChoiceBox;
    FBuildWarningsAsErrors: TEdit;
    /// <summary>Prüfung vor dem Compile (#529): build.gate (gilt auch für den Release-Wächter) und ihr Zeitlimit.
    /// </summary>
    FBuildGate: TAtlasChoiceBox;
    FBuildGateTimeout: TEdit;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property BuildWarningsAsErrorsEdit: TEdit read FBuildWarningsAsErrors;
    /// <summary>Zum Testen: Prüfung vor dem Compile (#529).</summary>
    property BuildGateChoice: TAtlasChoiceBox read FBuildGate;
    property BuildGateTimeoutEdit: TEdit read FBuildGateTimeout;
  end;

implementation

uses
  System.SysUtils,
  System.Math,
  Atlas.Core.Build.PipelineSettings,
  Atlas.UI.Strings,
  Atlas.Core.Build.Verdict;

{ TAtlasSettingsBuildPart }

procedure TAtlasSettingsBuildPart.Build;
begin
  // Probleme im Editor und eine Aktion nach dem Speichern (#398, #548): Syntaxprüfung der IDE oder
  // Kompilieren durch den Server (compiler.onSave in settings.json), nie beides.
  AddSheet(TAtlasTextId.SettingsTabCompiler);
  AddModuleSwitch('BuildToolsEnabled');
  AddModuleSwitch('BuildPipelineEnabled');
  AddModuleSwitch('TestsEnabled');
  BindCheck('Problems', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblems)));
  BindCheck('ProblemsList', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsList)));
  BindCheck('ProblemsStatusCounter', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsStatusCounter)));
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsCheckOnSave),
    [TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveNone), TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCheck),
    TAtlasStrings.Text(TAtlasTextId.SettingsAfterSaveCompile)]);
  BindText('CheckOnSaveDelayMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckDelay)));
  BindText('CheckOnSaveMaxMs', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsCheckMax)));
  // Claude Code baut über diese IDE (#261, build_project), z. B. ohne Kommandozeilen-Compiler.
  BindCheck('McpBuild', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMcpBuild)));
  // DUnitX-Tests ausführen (#69).
  BindCheck('TestRun', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestRun)));
  BindCheck('TestsBuildFirst', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsBuildFirst)));
  BindCheck('TestsAfterBuild', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAfterBuild)));
  // Betroffene Tests (#1353).
  BindCheck('TestsAffected', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffected)));
  BindText('TestsAffectedDepth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffectedDepth)));
  BindCheck('TestsAffectedBeforeCommit', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsTestsAffectedBeforeCommit)));
  BindCheck('BuildZeroHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildZeroHints)));
  BindCheck('ShowInterfaceCost', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsShowInterfaceCost)));
  // Schranke für Hinweise und Warnungen (#530).
  BindCheck('BuildSummary', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBuildSummary)));
  FBuildWarningsAsErrors := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsBuildWarningsAsErrors));
  // Prüfung vor dem Compile (#529); Reihenfolge wie TAtlasBuildGate: off, warn, block.
  FBuildGate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsBuildGate),
    [TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateOff), TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateWarn),
    TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateBlock)]);
  FBuildGateTimeout := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsBuildGateTimeout));
end;

procedure TAtlasSettingsBuildPart.BindMarks;
begin
  FPage.Marks.Bind(FAfterSave, ['CheckOnSave', 'CompileOnSave']);
  FPage.Marks.Bind(FBuildWarningsAsErrors, ['BuildWarningsAsErrors']);
  FPage.Marks.Bind(FBuildGateTimeout, ['BuildGateTimeoutMs']);
  FPage.Marks.Bind(FBuildGate, ['BuildGate']);
end;

procedure TAtlasSettingsBuildPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FAfterSave.Choice := 0;
  if ASettings.CheckOnSave then
  begin
    FAfterSave.Choice := 1;
  end
  else if ASettings.CompileOnSave then
  begin
    FAfterSave.Choice := 2;
  end;
  FBuildWarningsAsErrors.Text := TAtlasBuildVerdicts.NormalizeCodes(ASettings.BuildWarningsAsErrors);
  FBuildGate.Choice := Ord(TAtlasBuildPipelineSettings.GateOf(ASettings.BuildGate));
  FBuildGateTimeout.Text := IntToStr(ASettings.BuildGateTimeoutMs);
end;

procedure TAtlasSettingsBuildPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.CheckOnSave := FAfterSave.Choice = 1;
  ASettings.CompileOnSave := FAfterSave.Choice = 2;
  // Ungültige Einträge fallen weg; gespeichert wird die einheitliche Form „W1035, H2164“.
  ASettings.BuildWarningsAsErrors := TAtlasBuildVerdicts.NormalizeCodes(FBuildWarningsAsErrors.Text);
  if (FBuildGate.Choice >= Ord(Low(TAtlasBuildGate))) and (FBuildGate.Choice <= Ord(High(TAtlasBuildGate))) then
  begin
    ASettings.BuildGate := TAtlasBuildPipelineSettings.GateNames[TAtlasBuildGate(FBuildGate.Choice)];
  end;
  ASettings.BuildGateTimeoutMs := EnsureRange(StrToIntDef(FBuildGateTimeout.Text, ASettings.BuildGateTimeoutMs),
    TAtlasBuildPipelineSettings.GateMinTimeoutMs, TAtlasBuildPipelineSettings.GateMaxTimeoutMs);
end;

end.
