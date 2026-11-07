unit Atlas.UI.BuildPipeline.SettingsSection;

// Abschnitte des Moduls Build-Pipeline im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher im Teil „Compiler“
// und in Atlas.UI.Settings.Page.Release von Base).
// - „Compiler“: Modulschalter, Build für Claude Code (#261), Schranke für Hinweise und Warnungen (#530) und
//   Prüfung vor dem Compile (#529). Warnungen als Fehler bindet die Seite; der Abschnitt bringt sie beim Speichern
//   in die einheitliche Form. Die Grenzen des Zeitlimits setzt TAtlasPluginSettings.Normalize.
// - „Release-Build“: Release-Build-Wächter (#533) mit je Prüfung einem Haken (ohne Sollwert) bzw. einer Auswahl
//   „nicht prüfen / Soll aus / Soll an“; alle Prüfungen stehen in build.releaseChecks.

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Contract,
  Atlas.Core.Build.PipelineSettings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Section;

type
  TAtlasBuildPipelineCompilerSection = class(TAtlasSettingsSection)
  private
    FWarningsAsErrors: TEdit;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Close; override;
    property WarningsAsErrorsEdit: TEdit read FWarningsAsErrors;
  end;

  TAtlasBuildPipelineReleaseSection = class(TAtlasSettingsSection)
  private
    FConfigs: TEdit;
    FCheckBoxes: array[TAtlasReleaseCheck] of TCheckBox;
    FCheckChoices: array[TAtlasReleaseCheck] of TAtlasChoiceBox;
    procedure LoadCheck(ACheck: TAtlasReleaseCheck; const AItem: TAtlasReleaseCheckSetting);
    procedure SaveCheck(ACheck: TAtlasReleaseCheck; var AItem: TAtlasReleaseCheckSetting);
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
    procedure Load(const AValues: IAtlasSettingsValues); override;
    procedure Save(const AValues: IAtlasSettingsValues); override;
    procedure Close; override;
    /// <summary>Haken einer Prüfung ohne Sollwert; nil für Prüfungen mit Sollwert.</summary>
    function CheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
    /// <summary>Auswahl einer Prüfung mit Sollwert (0 = nicht prüfen, 1 = Soll aus, 2 = Soll an); sonst nil.</summary>
    function CheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
    property ConfigsEdit: TEdit read FConfigs;
  end;

const
  cBuildPipelineSettingsOwner = 'atlas.buildPipeline';

implementation

uses
  Atlas.Core.Build.Verdict,
  Atlas.UI.BuildPipeline.Strings;

const
  cWarningsAsErrorsKey = 'build.warningsAsErrors';
  cReleaseConfigsKey = 'build.releaseConfigs';
  cReleaseChecksKey = 'build.releaseChecks';

{ TAtlasBuildPipelineCompilerSection }

function TAtlasBuildPipelineCompilerSection.OwnerId: string;
begin
  Result := cBuildPipelineSettingsOwner;
end;

function TAtlasBuildPipelineCompilerSection.AreaId: string;
begin
  Result := 'Compiler';
end;

procedure TAtlasBuildPipelineCompilerSection.BuildRows;
var
  mGate: TAtlasBuildGate;
  mGates: TArray<string>;
begin
  ModuleSwitch('buildPipeline.enabled');
  // Claude Code baut über diese IDE (#261, build_project), z. B. ohne Kommandozeilen-Compiler.
  Switch('compiler.mcpBuild', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsMcpBuild));
  Switch('build.zeroHints', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildZeroHints));
  // Schranke für Hinweise und Warnungen (#530).
  Switch('build.summary', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildSummary));
  FWarningsAsErrors := Line(cWarningsAsErrorsKey,
    TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildWarningsAsErrors));
  // Prüfung vor dem Compile (#529); Reihenfolge wie TAtlasBuildGate: off, warn, block.
  mGates := nil;
  for mGate := Low(TAtlasBuildGate) to High(TAtlasBuildGate) do
  begin
    mGates := mGates + [TAtlasBuildPipelineSettings.cGateNames[mGate]];
  end;
  Choice('build.gate', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildGate),
    [TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildGateOff),
    TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildGateWarn),
    TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildGateBlock)], mGates);
  Number('build.gateTimeoutMs', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsBuildGateTimeout));
end;

procedure TAtlasBuildPipelineCompilerSection.Load(const AValues: IAtlasSettingsValues);
begin
  if Closed then
  begin
    Exit;
  end;
  FWarningsAsErrors.Text := TAtlasBuildVerdicts.NormalizeCodes(AValues.ReadString(cWarningsAsErrorsKey));
end;

procedure TAtlasBuildPipelineCompilerSection.Save(const AValues: IAtlasSettingsValues);
begin
  if Closed then
  begin
    Exit;
  end;
  // Ungültige Einträge fallen weg; gespeichert wird die einheitliche Form „W1035, H2164“.
  AValues.WriteString(cWarningsAsErrorsKey,
    TAtlasBuildVerdicts.NormalizeCodes(AValues.ReadString(cWarningsAsErrorsKey)));
end;

procedure TAtlasBuildPipelineCompilerSection.Close;
begin
  // Die Elemente gehören der Seite: nur den Verweis lösen.
  FWarningsAsErrors := nil;
  inherited Close;
end;

{ TAtlasBuildPipelineReleaseSection }

function TAtlasBuildPipelineReleaseSection.OwnerId: string;
begin
  Result := cBuildPipelineSettingsOwner;
end;

function TAtlasBuildPipelineReleaseSection.AreaId: string;
begin
  Result := 'Release-Build';
end;

procedure TAtlasBuildPipelineReleaseSection.BuildRows;
const
  cCaptions: array[TAtlasReleaseCheck] of TAtlasBuildPipelineTextId = (
    TAtlasBuildPipelineTextId.SettingsReleaseCheckDebugDefine, TAtlasBuildPipelineTextId.SettingsReleaseCheckDebugInfo,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckStackFrames, TAtlasBuildPipelineTextId.SettingsReleaseCheckAssertions,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckRangeChecks,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckOverflowChecks,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckMemoryLeaks,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckVersionInfo,
    TAtlasBuildPipelineTextId.SettingsReleaseCheckOutputFolder);
var
  mCheck: TAtlasReleaseCheck;
  mCaption: string;
begin
  Switch('build.releaseGuard', TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseGuard));
  // build.gate steht beim Compiler (#529) und gilt auch hier.
  FConfigs := Line(cReleaseConfigsKey,
    TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseConfigs));
  Title(TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseChecksTitle));
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    mCaption := TAtlasBuildPipelineStrings.Text(cCaptions[mCheck]);
    // Alle Prüfungen teilen build.releaseChecks: Punkt nur an der Einstellung, nicht an jeder Zeile.
    if TAtlasBuildPipelineSettings.cHasTarget[mCheck] then
    begin
      FCheckChoices[mCheck] := OwnChoice(mCaption,
        [TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseNotChecked),
        TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseExpectOff),
        TAtlasBuildPipelineStrings.Text(TAtlasBuildPipelineTextId.SettingsReleaseExpectOn)], nil);
      Host.ShareKeys(FCheckChoices[mCheck], [cReleaseChecksKey]);
    end
    else
    begin
      FCheckBoxes[mCheck] := OwnCheck(mCaption, nil);
      Host.ShareKeys(FCheckBoxes[mCheck], [cReleaseChecksKey]);
    end;
  end;
end;

function TAtlasBuildPipelineReleaseSection.CheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
begin
  Result := FCheckBoxes[ACheck];
end;

function TAtlasBuildPipelineReleaseSection.CheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
begin
  Result := FCheckChoices[ACheck];
end;

procedure TAtlasBuildPipelineReleaseSection.LoadCheck(ACheck: TAtlasReleaseCheck;
  const AItem: TAtlasReleaseCheckSetting);
begin
  if FCheckBoxes[ACheck] <> nil then
  begin
    FCheckBoxes[ACheck].Checked := AItem.Enabled;
  end
  else if not AItem.Enabled then
  begin
    FCheckChoices[ACheck].Choice := 0;
  end
  else if AItem.Expected then
  begin
    FCheckChoices[ACheck].Choice := 2;
  end
  else
  begin
    FCheckChoices[ACheck].Choice := 1;
  end;
end;

procedure TAtlasBuildPipelineReleaseSection.SaveCheck(ACheck: TAtlasReleaseCheck; var AItem: TAtlasReleaseCheckSetting);
begin
  if FCheckBoxes[ACheck] <> nil then
  begin
    AItem.Enabled := FCheckBoxes[ACheck].Checked;
  end
  else if FCheckChoices[ACheck].Choice >= 0 then
  begin
    AItem.Enabled := FCheckChoices[ACheck].Choice > 0;
    if AItem.Enabled then
    begin
      AItem.Expected := FCheckChoices[ACheck].Choice = 2;
    end;
  end;
end;

procedure TAtlasBuildPipelineReleaseSection.Load(const AValues: IAtlasSettingsValues);
var
  mChecks: TAtlasReleaseChecks;
  mCheck: TAtlasReleaseCheck;
begin
  if Closed then
  begin
    Exit;
  end;
  FConfigs.Text := TAtlasBuildPipelineSettings.NormalizedConfigurations(AValues.ReadString(cReleaseConfigsKey));
  mChecks := TAtlasReleaseChecks.Parse(AValues.ReadString(cReleaseChecksKey));
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    LoadCheck(mCheck, mChecks.Items[mCheck]);
  end;
end;

procedure TAtlasBuildPipelineReleaseSection.Save(const AValues: IAtlasSettingsValues);
var
  mChecks: TAtlasReleaseChecks;
  mCheck: TAtlasReleaseCheck;
begin
  if Closed then
  begin
    Exit;
  end;
  AValues.WriteString(cReleaseConfigsKey,
    TAtlasBuildPipelineSettings.NormalizedConfigurations(AValues.ReadString(cReleaseConfigsKey)));
  mChecks := TAtlasReleaseChecks.Parse(AValues.ReadString(cReleaseChecksKey));
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    SaveCheck(mCheck, mChecks.Items[mCheck]);
  end;
  AValues.WriteString(cReleaseChecksKey, mChecks.ToText);
end;

procedure TAtlasBuildPipelineReleaseSection.Close;
var
  mCheck: TAtlasReleaseCheck;
begin
  // Die Elemente gehören der Seite: nur die Verweise lösen.
  for mCheck := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    FCheckBoxes[mCheck] := nil;
    FCheckChoices[mCheck] := nil;
  end;
  FConfigs := nil;
  inherited Close;
end;

end.
