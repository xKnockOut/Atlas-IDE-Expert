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
  Atlas.UI.Strings;

const
  /// <summary>Werte von problems.window.scope und problems.window.groupBy in der Reihenfolge der Auswahl (#909).
  /// </summary>
  ScopeValues: array[0..2] of string = ('file', 'project', 'group');
  GroupByValues: array[0..3] of string = ('none', 'file', 'rule', 'category');
  /// <summary>Werte von problems.window.closedUnits in der Reihenfolge der Auswahl (#1108).</summary>
  ClosedUnitsValues: array[0..2] of string = ('dimmed', 'normal', 'hidden');
  /// <summary>Werte von problems.compilerMerge in der Reihenfolge der Auswahl (#1024).</summary>
  CompilerMergeValues: array[0..1] of string = ('merge', 'both');
  /// <summary>Werte von problems.update in der Reihenfolge der Auswahl (wie TAtlasProblemsRefresh).</summary>
  ProblemsUpdateValues: array[0..2] of string = ('live', 'save', 'manual');

{ TAtlasSettingsRulesPart }

procedure TAtlasSettingsRulesPart.Build;
begin
  // Prüfregeln (#909): das Fenster „Atlas-Prüfung“ und die laufende Prüfung. Den Weg zu den Regeln (sie stehen in
  // den Dialogen der Einstellungsdateien), Profile, Baseline und Unterdrückungen trägt das Modul bei (#1755).
  AddSheet(TAtlasTextId.SettingsTabRules);
  BindCheck('ProblemsWindow', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindow)));
  FProblemsWindowScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowScope),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)]);
  FProblemsWindowGroupBy := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsGroupNone), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupFile),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupRule), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupCategory)]);
  BindCheck('ProblemsWindowCompiler', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowCompiler)));
  BindCheck('ProblemsWindowFollowCursor', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowFollowCursor)));
  // Offene Units zuerst (#1108); der Hauptschalter sperrt die beiden Zeilen darunter (x-parent).
  BindCheck('ProblemsWindowOpenFirst', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowOpenFirst)));
  FProblemsWindowClosedUnits := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowClosedUnits),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsClosedDimmed), TAtlasStrings.Text(TAtlasTextId.ProblemsClosedNormal),
    TAtlasStrings.Text(TAtlasTextId.ProblemsClosedHidden)]);
  BindCheck('ProblemsWindowShowCleanActive', AddCheck(
    TAtlasStrings.Text(TAtlasTextId.SettingsProblemsWindowShowCleanActive)));
  // Wann die offene Datei geprüft wird, und die Verzögerung der Live-Prüfung.
  FProblemsUpdate := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsUpdate),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsUpdateLive), TAtlasStrings.Text(TAtlasTextId.ProblemsUpdateSave),
    TAtlasStrings.Text(TAtlasTextId.ProblemsUpdateManual)]);
  FProblemsLiveDelay := BindText('ProblemsLiveDelayMs',
    AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsLiveDelay)));
  // Liste „Atlas-Probleme“ im Meldungsfenster (#398), seit #909 nur noch zusätzlich zum Fenster.
  BindCheck('ProblemsMessageList', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsList)));
  // Gruppe „Compiler vorab“ (#1024): stehen über x-node im Knoten der Gruppe unter dem Regel-Editor.
  FProblemsCompilerMerge := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsCompilerMerge),
    [TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerMergeMerge),
    TAtlasStrings.Text(TAtlasTextId.ProblemsCompilerMergeBoth)]);
  BindCheck('ProblemsShowCompilerCode', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsShowCompilerCode)));
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
  FProblemsWindowScope.Choice := Max(0, IndexText(ASettings.ProblemsWindowScope, ScopeValues));
  FProblemsWindowGroupBy.Choice := Max(0, IndexText(ASettings.ProblemsWindowGroupBy, GroupByValues));
  FProblemsWindowClosedUnits.Choice := Max(0, IndexText(ASettings.ProblemsWindowClosedUnits, ClosedUnitsValues));
  FProblemsCompilerMerge.Choice := Max(0, IndexText(ASettings.ProblemsCompilerMerge, CompilerMergeValues));
  FProblemsUpdate.Choice := Max(0, IndexText(ASettings.ProblemsUpdate, ProblemsUpdateValues));
end;

procedure TAtlasSettingsRulesPart.Save(var ASettings: TAtlasPluginSettings);
begin
  if (FProblemsWindowScope.Choice >= 0) and (FProblemsWindowScope.Choice <= High(ScopeValues)) then
  begin
    ASettings.ProblemsWindowScope := ScopeValues[FProblemsWindowScope.Choice];
  end;
  if (FProblemsWindowGroupBy.Choice >= 0) and (FProblemsWindowGroupBy.Choice <= High(GroupByValues)) then
  begin
    ASettings.ProblemsWindowGroupBy := GroupByValues[FProblemsWindowGroupBy.Choice];
  end;
  if (FProblemsWindowClosedUnits.Choice >= 0) and (FProblemsWindowClosedUnits.Choice <= High(ClosedUnitsValues)) then
  begin
    ASettings.ProblemsWindowClosedUnits := ClosedUnitsValues[FProblemsWindowClosedUnits.Choice];
  end;
  if (FProblemsCompilerMerge.Choice >= 0) and (FProblemsCompilerMerge.Choice <= High(CompilerMergeValues)) then
  begin
    ASettings.ProblemsCompilerMerge := CompilerMergeValues[FProblemsCompilerMerge.Choice];
  end;
  if (FProblemsUpdate.Choice >= 0) and (FProblemsUpdate.Choice <= High(ProblemsUpdateValues)) then
  begin
    ASettings.ProblemsUpdate := ProblemsUpdateValues[FProblemsUpdate.Choice];
  end;
end;

end.
