unit Atlas.IDE.Rules.Settings;

// Abschnitt „Prüfregeln“ im Optionsdialog, IDE-Teil des Moduls Prüfregeln
// (#1755; vorher Atlas.IDE.Settings.PageOptions und Atlas.IDE.Settings.SubPages
// in Base). TAtlasIdeRulesSettings ist der IAtlasSettingsSectionProvider, den
// die Composition des Moduls über seinen Scope anmeldet: Für jede Optionsseite
// entsteht ein TAtlasRulesChecksSection mit den Haken dazu. Die Wege zu den
// Regeln öffnen die Dialoge der Einstellungsdateien (TAtlasProjectSettings von
// Base), Baseline und Unterdrückungen laufen über TAtlasIdeRulesMaintenance.

interface

uses
  Atlas.UI.Settings.Contract;

type
  TAtlasIdeRulesSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Rules.Maintenance,
  Atlas.UI.Rules.SettingsSection;

procedure OpenProject;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasProjectSettings.Execute;
    end);
end;

procedure OpenGlobal;
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasProjectSettings.ExecuteGlobal;
    end);
end;

function BaselineInfo: string;
begin
  Result := TAtlasIdeRulesMaintenance.BaselineText;
end;

function BaselineUpdate: string;
begin
  Result := TAtlasIdeRulesMaintenance.UpdateBaseline;
end;

function BaselineDelete: string;
begin
  Result := TAtlasIdeRulesMaintenance.DeleteBaseline;
end;

function Suppressions: TArray<string>;
begin
  Result := TAtlasIdeRulesMaintenance.Suppressions;
end;

{ TAtlasIdeRulesSettings }

function TAtlasIdeRulesSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasRulesChecksSection;
  mHooks: TAtlasRulesChecksHooks;
begin
  mSection := TAtlasRulesChecksSection.Create;
  Result := mSection;
  mHooks := Default(TAtlasRulesChecksHooks);
  mHooks.OpenProject := OpenProject;
  mHooks.OpenGlobal := OpenGlobal;
  mHooks.BaselineInfo := BaselineInfo;
  mHooks.BaselineUpdate := BaselineUpdate;
  mHooks.BaselineDelete := BaselineDelete;
  mHooks.Suppressions := Suppressions;
  mSection.Hooks := mHooks;
end;

end.
