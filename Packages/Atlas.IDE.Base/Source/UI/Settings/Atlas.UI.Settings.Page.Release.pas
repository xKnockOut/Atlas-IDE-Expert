unit Atlas.UI.Settings.Page.Release;

// Reiter „Release“: Release-Build-Wächter (#533).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.PipelineSettings,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Release“: Release-Build-Wächter (#533).</summary>
  TAtlasSettingsReleasePart = class(TAtlasSettingsPagePart)
  private
    /// <summary>Release-Build-Wächter (#533): Schalter, weitere Release-Konfigurationen und je Prüfung ein Haken
    /// (ohne Sollwert) bzw. eine Auswahl „nicht prüfen / Soll aus / Soll an“.</summary>
    FReleaseGuard: TCheckBox;
    FReleaseConfigs: TEdit;
    FReleaseCheckBoxes: array[TAtlasReleaseCheck] of TCheckBox;
    FReleaseCheckChoices: array[TAtlasReleaseCheck] of TAtlasChoiceBox;
    procedure AddReleaseSection;
    procedure LoadRelease(const ASettings: TAtlasPluginSettings);
    procedure SaveRelease(var ASettings: TAtlasPluginSettings);
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Haken einer Prüfung ohne Sollwert; nil für Prüfungen mit Sollwert.</summary>
    function ReleaseCheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
    /// <summary>Auswahl einer Prüfung mit Sollwert (0 = nicht prüfen, 1 = Soll aus, 2 = Soll an); sonst nil.</summary>
    function ReleaseCheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
    /// <summary>Zum Testen: Release-Build-Wächter (#533).</summary>
    property ReleaseGuardCheck: TCheckBox read FReleaseGuard;
    property ReleaseConfigsEdit: TEdit read FReleaseConfigs;
  end;

implementation

uses
  Atlas.UI.Strings;

{ TAtlasSettingsReleasePart }

procedure TAtlasSettingsReleasePart.Build;
begin
  // Release-Build-Wächter (#533).
  AddSheet(TAtlasTextId.SettingsTabRelease);
  AddReleaseSection;
end;

procedure TAtlasSettingsReleasePart.AddReleaseSection;
const
  Captions: array[TAtlasReleaseCheck] of TAtlasTextId = (TAtlasTextId.SettingsReleaseCheckDebugDefine,
    TAtlasTextId.SettingsReleaseCheckDebugInfo, TAtlasTextId.SettingsReleaseCheckStackFrames,
    TAtlasTextId.SettingsReleaseCheckAssertions, TAtlasTextId.SettingsReleaseCheckRangeChecks,
    TAtlasTextId.SettingsReleaseCheckOverflowChecks, TAtlasTextId.SettingsReleaseCheckMemoryLeaks,
    TAtlasTextId.SettingsReleaseCheckVersionInfo, TAtlasTextId.SettingsReleaseCheckOutputFolder);
var
  Check: TAtlasReleaseCheck;
begin
  FReleaseGuard := AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReleaseGuard));
  // build.gate steht beim Compiler (#529) und gilt auch hier.
  FReleaseConfigs := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsReleaseConfigs));
  AddTitle(TAtlasTextId.SettingsReleaseChecksTitle);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if TAtlasBuildPipelineSettings.HasTarget[Check] then
    begin
      FReleaseCheckChoices[Check] := AddChoice(TAtlasStrings.Text(Captions[Check]),
        [TAtlasStrings.Text(TAtlasTextId.SettingsReleaseNotChecked),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOff),
        TAtlasStrings.Text(TAtlasTextId.SettingsReleaseExpectOn)]);
    end
    else
    begin
      FReleaseCheckBoxes[Check] := AddCheck(TAtlasStrings.Text(Captions[Check]));
    end;
  end;
end;

function TAtlasSettingsReleasePart.ReleaseCheckBox(ACheck: TAtlasReleaseCheck): TCheckBox;
begin
  Result := FReleaseCheckBoxes[ACheck];
end;

function TAtlasSettingsReleasePart.ReleaseCheckChoice(ACheck: TAtlasReleaseCheck): TAtlasChoiceBox;
begin
  Result := FReleaseCheckChoices[ACheck];
end;

procedure TAtlasSettingsReleasePart.LoadRelease(const ASettings: TAtlasPluginSettings);
var
  Checks: TAtlasReleaseChecks;
  Check: TAtlasReleaseCheck;
begin
  FReleaseGuard.Checked := ASettings.ReleaseGuard;
  FReleaseConfigs.Text := TAtlasBuildPipelineSettings.NormalizedConfigurations(ASettings.ReleaseConfigs);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if not Checks.Items[Check].Enabled then
      begin
        FReleaseCheckChoices[Check].Choice := 0;
      end
      else if Checks.Items[Check].Expected then
      begin
        FReleaseCheckChoices[Check].Choice := 2;
      end
      else
      begin
        FReleaseCheckChoices[Check].Choice := 1;
      end;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
    begin
      FReleaseCheckBoxes[Check].Checked := Checks.Items[Check].Enabled;
    end;
  end;
end;

procedure TAtlasSettingsReleasePart.SaveRelease(var ASettings: TAtlasPluginSettings);
var
  Checks: TAtlasReleaseChecks;
  Check: TAtlasReleaseCheck;
begin
  ASettings.ReleaseGuard := FReleaseGuard.Checked;
  ASettings.ReleaseConfigs := TAtlasBuildPipelineSettings.NormalizedConfigurations(FReleaseConfigs.Text);
  Checks := TAtlasReleaseChecks.Parse(ASettings.ReleaseChecks);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    if FReleaseCheckChoices[Check] <> nil then
    begin
      if FReleaseCheckChoices[Check].Choice >= 0 then
      begin
        Checks.Items[Check].Enabled := FReleaseCheckChoices[Check].Choice > 0;
        if FReleaseCheckChoices[Check].Choice > 0 then
        begin
          Checks.Items[Check].Expected := FReleaseCheckChoices[Check].Choice = 2;
        end;
      end;
    end
    else if FReleaseCheckBoxes[Check] <> nil then
    begin
      Checks.Items[Check].Enabled := FReleaseCheckBoxes[Check].Checked;
    end;
  end;
  ASettings.ReleaseChecks := Checks.ToText;
end;

procedure TAtlasSettingsReleasePart.BindMarks;
var
  Check: TAtlasReleaseCheck;
begin
  FPage.Marks.Bind(FReleaseGuard, ['ReleaseGuard']);
  FPage.Marks.Bind(FReleaseConfigs, ['ReleaseConfigs']);
  for Check := Low(TAtlasReleaseCheck) to High(TAtlasReleaseCheck) do
  begin
    FPage.Marks.Bind(FReleaseCheckBoxes[Check], ['ReleaseChecks'], False);
    FPage.Marks.Bind(FReleaseCheckChoices[Check], ['ReleaseChecks'], False);
  end;
end;

procedure TAtlasSettingsReleasePart.Load(const ASettings: TAtlasPluginSettings);
begin
  LoadRelease(ASettings);
end;

procedure TAtlasSettingsReleasePart.Save(var ASettings: TAtlasPluginSettings);
begin
  SaveRelease(ASettings);
end;

end.
