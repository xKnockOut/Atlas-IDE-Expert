unit Atlas.UI.Settings.Page.Parts;

// Teile der Optionsseite „Atlas“ (#227) je Bereich: legt sie in der Reihenfolge der Reiter an und baut ihre
// Elemente. Die Seite selbst kennt nur den Ablauf (Bindung, Abschnitte der Module, Baum).

interface

uses
  Atlas.UI.Settings.Page.Host;

type
  TAtlasSettingsPageParts = class
  private
    class procedure CreateParts(APage: TAtlasSettingsPageHost); static;
  public
    /// <summary>Legt die Teile der Bereiche auf APage an und baut ihre Reiter in der Reihenfolge der Seite.</summary>
    class procedure Build(APage: TAtlasSettingsPageHost); static;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.Build,
  Atlas.UI.Settings.Page.Colors,
  Atlas.UI.Settings.Page.Commands,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.Debug,
  Atlas.UI.Settings.Page.EditorCode,
  Atlas.UI.Settings.Page.EditorView,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.Release,
  Atlas.UI.Settings.Page.Robustness,
  Atlas.UI.Settings.Page.Rules,
  Atlas.UI.Settings.Page.Startup,
  Atlas.UI.Settings.Page.Tasks,
  Atlas.UI.Settings.Page.TeamFile,
  Atlas.UI.Settings.Page.Transfer,
  Atlas.UI.Settings.Page.Vcs,
  Atlas.UI.Settings.Page.VcsBranch,
  Atlas.UI.Settings.Page.VcsProject,
  Atlas.UI.Settings.Page.VcsProjects,
  Atlas.UI.Settings.Page.VcsTools,
  Atlas.UI.Settings.Page.Sections;

class procedure TAtlasSettingsPageParts.CreateParts(APage: TAtlasSettingsPageHost);
begin
  APage.AddPart(TAtlasSettingsGeneralPart.Create(APage));
  APage.AddPart(TAtlasSettingsNotificationsPart.Create(APage));
  APage.AddPart(TAtlasSettingsTransferPart.Create(APage));
  APage.AddPart(TAtlasSettingsCompletionPart.Create(APage));
  APage.AddPart(TAtlasSettingsFavoritesPart.Create(APage));
  APage.AddPart(TAtlasSettingsTeamFilePart.Create(APage));
  APage.AddPart(TAtlasSettingsEditorViewPart.Create(APage));
  APage.AddPart(TAtlasSettingsEditorCodePart.Create(APage));
  APage.AddPart(TAtlasSettingsColorsPart.Create(APage));
  APage.AddPart(TAtlasSettingsIndexPart.Create(APage));
  APage.AddPart(TAtlasSettingsBuildPart.Create(APage));
  APage.AddPart(TAtlasSettingsTasksPart.Create(APage));
  APage.AddPart(TAtlasSettingsRulesPart.Create(APage));
  APage.AddPart(TAtlasSettingsReleasePart.Create(APage));
  APage.AddPart(TAtlasSettingsDebugPart.Create(APage));
  APage.AddPart(TAtlasSettingsCommandsPart.Create(APage));
  APage.AddPart(TAtlasSettingsRobustnessPart.Create(APage));
  APage.AddPart(TAtlasSettingsStartupPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsToolsPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsProjectPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsProjectsPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsProjectAddPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsServersPart.Create(APage));
  APage.AddPart(TAtlasSettingsVcsBranchPart.Create(APage));
  // Zuletzt: Die Abschnitte der Module laden und speichern nach den Einstellungen von Base.
  APage.AddPart(TAtlasSettingsSectionsPart.Create(APage));
end;

class procedure TAtlasSettingsPageParts.Build(APage: TAtlasSettingsPageHost);
begin
  CreateParts(APage);
  APage.Part<TAtlasSettingsGeneralPart>.Build;
  APage.Part<TAtlasSettingsGeneralPart>.Build2;
  APage.Part<TAtlasSettingsNotificationsPart>.Build;
  APage.Part<TAtlasSettingsTransferPart>.Build;
  APage.Part<TAtlasSettingsCompletionPart>.Build;
  APage.Part<TAtlasSettingsCompletionPart>.Build2;
  APage.Part<TAtlasSettingsFavoritesPart>.Build;
  APage.Part<TAtlasSettingsTeamFilePart>.Build;
  APage.Part<TAtlasSettingsEditorViewPart>.Build;
  APage.Part<TAtlasSettingsEditorViewPart>.Build2;
  APage.Part<TAtlasSettingsEditorViewPart>.Build3;
  APage.Part<TAtlasSettingsEditorCodePart>.Build;
  APage.Part<TAtlasSettingsEditorCodePart>.Build2;
  APage.Part<TAtlasSettingsEditorCodePart>.Build3;
  APage.Part<TAtlasSettingsColorsPart>.Build;
  APage.Part<TAtlasSettingsIndexPart>.Build;
  APage.Part<TAtlasSettingsBuildPart>.Build;
  APage.Part<TAtlasSettingsTasksPart>.Build;
  APage.Part<TAtlasSettingsRulesPart>.Build;
  APage.Part<TAtlasSettingsReleasePart>.Build;
  APage.Part<TAtlasSettingsDebugPart>.Build;
  APage.Part<TAtlasSettingsDebugPart>.Build2;
  APage.Part<TAtlasSettingsCommandsPart>.Build;
  APage.Part<TAtlasSettingsCommandsPart>.Build2;
  APage.Part<TAtlasSettingsRobustnessPart>.Build;
  APage.Part<TAtlasSettingsStartupPart>.Build;
  // Willkommensseite (#753): Base zeigt nur den Modulschalter; die Einstellungen der Seite baut das Modul als
  // Abschnitt (#1456, Atlas.UI.Welcome.SettingsSection).
  APage.AddSheet(TAtlasTextId.SettingsTabWelcome);
  APage.Part<TAtlasSettingsModulesPart>.Add('WelcomePage');
  // Issue-Tracker (#1280): eigener Bereich; die Willkommensseite schaltet nur, ob „Meine Issues“ erscheint.
  // Die Einstellungen darin baut das Modul Tracker als Abschnitt (#1455, Atlas.UI.Tracker.SettingsSection).
  APage.AddSheet(TAtlasTextId.SettingsTabIssues);
  APage.Part<TAtlasSettingsModulesPart>.Add('IssuesEnabled');
  APage.Part<TAtlasSettingsVcsPart>.Build;
  APage.Part<TAtlasSettingsVcsToolsPart>.Build;
  APage.Part<TAtlasSettingsVcsProjectPart>.Build;
  APage.Part<TAtlasSettingsVcsProjectsPart>.Build;
  APage.Part<TAtlasSettingsVcsServersPart>.Build;
  APage.Part<TAtlasSettingsVcsPart>.Build2;
  APage.Part<TAtlasSettingsVcsBranchPart>.Build;
  APage.Part<TAtlasSettingsTeamFilePart>.Build2;
end;

end.
