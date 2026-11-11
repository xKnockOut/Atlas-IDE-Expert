unit Atlas.UI.Settings.Page.Rules;

// Bereich „Prüfregeln“ (#909): Fenster „Atlas-Prüfung“, laufende Prüfung und Compiler vorab (#1024). Wege zu den
// Regeln, Profile, Baseline und Unterdrückungen trägt der Abschnitt des Moduls Prüfregeln bei (#1755).

interface

uses
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Bereich „Prüfregeln“ (#909): Prüffenster und Compiler vorab (#1024); den Rest liefert das Modul
  /// Prüfregeln als Abschnitt (#1755).</summary>
  TAtlasSettingsRulesPart = class(TAtlasSettingsPagePart)
  private
    FProblemsWindowScope: TAtlasChoiceBox;
    FProblemsWindowGroupBy: TAtlasChoiceBox;
    FProblemsWindowClosedUnits: TAtlasChoiceBox;
    FProblemsCompilerMerge: TAtlasChoiceBox;
    FProblemsUpdate: TAtlasChoiceBox;
    FProblemsLiveDelay: TEdit;
  public
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property ProblemsWindowScopeChoice: TAtlasChoiceBox read FProblemsWindowScope;
    property ProblemsWindowGroupByChoice: TAtlasChoiceBox read FProblemsWindowGroupBy;
    property ProblemsWindowClosedUnitsChoice: TAtlasChoiceBox read FProblemsWindowClosedUnits;
    property ProblemsCompilerMergeChoice: TAtlasChoiceBox read FProblemsCompilerMerge;
    property ProblemsUpdateChoice: TAtlasChoiceBox read FProblemsUpdate;
    property ProblemsLiveDelayEdit: TEdit read FProblemsLiveDelay;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Problems.ScopeBox;

const
  /// <summary>Werte von problems.window.scope und problems.window.groupBy in der Reihenfolge der Auswahl (#909).
  /// </summary>
  cScopeValues: array[0..2] of string = ('file', 'project', 'group');
  cGroupByValues: array[0..3] of string = ('none', 'file', 'rule', 'category');
  /// <summary>Werte von problems.window.closedUnits in der Reihenfolge der Auswahl (#1108).</summary>
  cClosedUnitsValues: array[0..2] of string = ('dimmed', 'normal', 'hidden');
  /// <summary>Werte von problems.compilerMerge in der Reihenfolge der Auswahl (#1024).</summary>
  cCompilerMergeValues: array[0..1] of string = ('merge', 'both');
  /// <summary>Werte von problems.update in der Reihenfolge der Auswahl (wie TAtlasProblemsRefresh).</summary>
  cProblemsUpdateValues: array[0..2] of string = ('live', 'save', 'manual');

{ TAtlasSettingsRulesPart }

procedure TAtlasSettingsRulesPart.Build;
begin
  // Prüfregeln (#909): das Fenster „Atlas-Prüfung“ und die laufende Prüfung. Den Weg zu den Regeln (sie stehen in
  // den Dialogen der Einstellungsdateien), Profile, Baseline und Unterdrückungen trägt das Modul bei (#1755).
  AddSheet(TAtlasTextId.SettingsTabRules);
  BindCheck('ProblemsWindow', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindow)));
  FProblemsWindowScope := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowScope),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)]);
  // Einzelne Projekte der Gruppe in der Bereichsliste (#1843).
  BindCheck('ProblemsWindowScopeProjects', AddCheck(TAtlasProblemsScopeBox.Text(TAtlasScopeBoxText.Setting)));
  FProblemsWindowGroupBy := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsGroupNone), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupFile),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupRule), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupCategory)]);
  BindCheck('ProblemsWindowCompiler',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowCompiler)));
  BindCheck('ProblemsWindowFollowCursor',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowFollowCursor)));
  // Offene Units zuerst (#1108); der Hauptschalter sperrt die beiden Zeilen darunter (x-parent).
  BindCheck('ProblemsWindowOpenFirst',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowOpenFirst)));
  FProblemsWindowClosedUnits := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsProblemsWindowClosedUnits),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsClosedDimmed),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsClosedNormal),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsClosedHidden)]);
  BindCheck('ProblemsWindowShowCleanActive', AddCheck(
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsWindowShowCleanActive)));
  // Wann die offene Datei geprüft wird, und die Verzögerung der Live-Prüfung.
  FProblemsUpdate := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsUpdate),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsUpdateLive),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsUpdateSave),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsUpdateManual)]);
  FProblemsLiveDelay := BindText('ProblemsLiveDelayMs',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsLiveDelay)));
  // Liste „Atlas-Probleme“ im Meldungsfenster (#398), seit #909 nur noch zusätzlich zum Fenster.
  BindCheck('ProblemsMessageList', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsList)));
  // Gruppe „Compiler vorab“ (#1024): stehen über x-node im Knoten der Gruppe unter dem Regel-Editor.
  FProblemsCompilerMerge := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsCompilerMerge),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsCompilerMergeMerge),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ProblemsCompilerMergeBoth)]);
  BindCheck('ProblemsShowCompilerCode',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProblemsShowCompilerCode)));
end;

procedure TAtlasSettingsRulesPart.BindMarks;
begin
  FPage.Marks.Bind(FProblemsWindowScope, ['ProblemsWindowScope']);
  FPage.Marks.Bind(FProblemsWindowGroupBy, ['ProblemsWindowGroupBy']);
  FPage.Marks.Bind(FProblemsWindowClosedUnits, ['ProblemsWindowClosedUnits']);
  FPage.Marks.Bind(FProblemsCompilerMerge, ['ProblemsCompilerMerge']);
  FPage.Marks.Bind(FProblemsUpdate, ['ProblemsUpdate']);
end;

procedure TAtlasSettingsRulesPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FProblemsWindowScope.Choice := Max(0, IndexText(ASettings.ProblemsWindowScope, cScopeValues));
  FProblemsWindowGroupBy.Choice := Max(0, IndexText(ASettings.ProblemsWindowGroupBy, cGroupByValues));
  FProblemsWindowClosedUnits.Choice := Max(0, IndexText(ASettings.ProblemsWindowClosedUnits, cClosedUnitsValues));
  FProblemsCompilerMerge.Choice := Max(0, IndexText(ASettings.ProblemsCompilerMerge, cCompilerMergeValues));
  FProblemsUpdate.Choice := Max(0, IndexText(ASettings.ProblemsUpdate, cProblemsUpdateValues));
end;

procedure TAtlasSettingsRulesPart.Save(var ASettings: TAtlasPluginSettings);
begin
  if (FProblemsWindowScope.Choice >= 0) and (FProblemsWindowScope.Choice <= High(cScopeValues)) then
  begin
    ASettings.ProblemsWindowScope := cScopeValues[FProblemsWindowScope.Choice];
  end;
  if (FProblemsWindowGroupBy.Choice >= 0) and (FProblemsWindowGroupBy.Choice <= High(cGroupByValues)) then
  begin
    ASettings.ProblemsWindowGroupBy := cGroupByValues[FProblemsWindowGroupBy.Choice];
  end;
  if (FProblemsWindowClosedUnits.Choice >= 0) and (FProblemsWindowClosedUnits.Choice <= High(cClosedUnitsValues)) then
  begin
    ASettings.ProblemsWindowClosedUnits := cClosedUnitsValues[FProblemsWindowClosedUnits.Choice];
  end;
  if (FProblemsCompilerMerge.Choice >= 0) and (FProblemsCompilerMerge.Choice <= High(cCompilerMergeValues)) then
  begin
    ASettings.ProblemsCompilerMerge := cCompilerMergeValues[FProblemsCompilerMerge.Choice];
  end;
  if (FProblemsUpdate.Choice >= 0) and (FProblemsUpdate.Choice <= High(cProblemsUpdateValues)) then
  begin
    ASettings.ProblemsUpdate := cProblemsUpdateValues[FProblemsUpdate.Choice];
  end;
end;

end.
