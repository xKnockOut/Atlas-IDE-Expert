unit Atlas.UI.Settings.Page.Build;

// Reiter „Compiler“: Probleme im Editor und Aktion nach dem Speichern (#398, #548). Module bauen ihre Einstellungen
// zum Compiler als Abschnitte in diesen Reiter (#1455).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Compiler“: Probleme im Editor und Aktion nach dem Speichern (#398, #548).</summary>
  TAtlasSettingsBuildPart = class(TAtlasSettingsPagePart)
  private
    FAfterSave: TAtlasChoiceBox;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    /// <summary>Zum Testen: nichts, Syntaxprüfung, Kompilieren.</summary>
    property AfterSaveChoice: TAtlasChoiceBox read FAfterSave;
  end;

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

{ TAtlasSettingsBuildPart }

procedure TAtlasSettingsBuildPart.Build;
begin
  // Probleme im Editor und eine Aktion nach dem Speichern (#398, #548): Syntaxprüfung der IDE oder
  // Kompilieren durch den Server (compiler.onSave in settings.json), nie beides.
  AddSheet(TAtlasTextId.SettingsTabCompiler);
  BindCheck('Problems', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblems)));
  BindCheck('ProblemsStatusCounter',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsStatusCounter)));
  // Reihenfolge: nichts, Syntaxprüfung (CheckOnSave), Kompilieren (CompileOnSave).
  FAfterSave := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCheckOnSave),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAfterSaveNone),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAfterSaveCheck),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsAfterSaveCompile)]);
  BindText('CheckOnSaveDelayMs', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCheckDelay)));
  BindText('CheckOnSaveMaxMs', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCheckMax)));
  BindCheck('ShowInterfaceCost', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsShowInterfaceCost)));
end;

procedure TAtlasSettingsBuildPart.BindMarks;
begin
  FPage.Marks.Bind(FAfterSave, ['CheckOnSave', 'CompileOnSave']);
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
end;

procedure TAtlasSettingsBuildPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.CheckOnSave := FAfterSave.Choice = 1;
  ASettings.CompileOnSave := FAfterSave.Choice = 2;
end;

end.
