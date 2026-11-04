unit Atlas.UI.Settings.Page.Rules;

// Bereich „Prüfregeln“ (#909): Wege zu den Regeln, Prüffenster, Compiler vorab (#1024) und Knoten „Profile und
// Baseline“.

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Bereich „Prüfregeln“ (#909): Wege zu den Regeln, Prüffenster, Compiler vorab (#1024) und Knoten
  /// „Profile und Baseline“.</summary>
  TAtlasSettingsRulesPart = class(TAtlasSettingsPagePart)
  private
    FProblemsWindowScope: TAtlasChoiceBox;
    FProblemsWindowGroupBy: TAtlasChoiceBox;
    FProblemsWindowClosedUnits: TAtlasChoiceBox;
    FProblemsCompilerMerge: TAtlasChoiceBox;
    /// <summary>Bereich Prüfregeln (#909): Index in FSheets. Die Regeln selbst stehen in den Dialogen der
    /// Einstellungsdateien (Projekt und global); hier Prüffenster, Compiler vorab, Profile und Baseline.</summary>
    FRulesArea: Integer;
    FOnRulesProject: TProc;
    FOnRulesGlobal: TProc;
    FOnBaselineInfo: TFunc<string>;
    FOnBaselineUpdate: TFunc<string>;
    FOnBaselineDelete: TFunc<string>;
    FBaselineInfo: TLabel;
    FRulesProject: TButton;
    FRulesGlobal: TButton;
    FBaselineUpdateButton: TButton;
    FBaselineDelete: TButton;
    procedure AddRulesLinks;
    procedure SetOnBaselineInfo(const AValue: TFunc<string>);
    procedure RulesProjectClick(Sender: TObject);
    procedure RulesGlobalClick(Sender: TObject);
    procedure BaselineUpdateClick(Sender: TObject);
    procedure BaselineDeleteClick(Sender: TObject);
  public
    procedure AddNodePages; override;
    procedure Build;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property ProblemsWindowScopeChoice: TAtlasChoiceBox read FProblemsWindowScope;
    property ProblemsWindowGroupByChoice: TAtlasChoiceBox read FProblemsWindowGroupBy;
    property ProblemsWindowClosedUnitsChoice: TAtlasChoiceBox read FProblemsWindowClosedUnits;
    property ProblemsCompilerMergeChoice: TAtlasChoiceBox read FProblemsCompilerMerge;
    property RulesProjectButton: TButton read FRulesProject;
    property RulesGlobalButton: TButton read FRulesGlobal;
    /// <summary>„Projekt-Prüfregeln bearbeiten …“: Projektdialog öffnen.</summary>
    property OnRulesProject: TProc read FOnRulesProject write FOnRulesProject;
    /// <summary>„Globale Prüfregeln bearbeiten …“: Dialog der globalen Einstellungen öffnen.</summary>
    property OnRulesGlobal: TProc read FOnRulesGlobal write FOnRulesGlobal;
    /// <summary>Baseline des aktiven Projekts: Text, neu erzeugen, löschen (Ergebnis als Text).</summary>
    property OnBaselineInfo: TFunc<string> read FOnBaselineInfo write SetOnBaselineInfo;
    property OnBaselineUpdate: TFunc<string> read FOnBaselineUpdate write FOnBaselineUpdate;
    property OnBaselineDelete: TFunc<string> read FOnBaselineDelete write FOnBaselineDelete;
    property BaselineInfoLabel: TLabel read FBaselineInfo;
  end;

implementation

uses
  System.Classes,
  System.UITypes,
  System.Math,
  System.StrUtils,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Dialogs,
  Atlas.UI.Settings.Page.Sheets,
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

{ TAtlasSettingsRulesPart }

procedure TAtlasSettingsRulesPart.Build;
begin
  // Prüfregeln (#909): oben der Weg zu den Regeln (sie stehen in den Dialogen der Einstellungsdateien), darunter
  // das Fenster „Atlas-Prüfung“ und die laufende Prüfung (Unterpunkt „Prüffenster“). „Profile und Baseline“
  // entsteht in AddRulePages.
  AddSheet(TAtlasTextId.SettingsTabRules);
  FRulesArea := High(FPage.Sheets);
  AddModuleSwitch('RuleChecksEnabled');
  AddRulesLinks;
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
  BindCheck('ProblemsLive', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsProblemsLive)));
  // Sammelkorrektur im Kontextmenü des Fensters (#1352).
  BindCheck('FixBulk', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsFixBulk)));
  // Liste âAtlas-Problemeâ im Meldungsfenster (#398), seit #909 nur noch zusÃ¤tzlich zum Fenster.
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
end;

procedure TAtlasSettingsRulesPart.AddRulesLinks;
var
  Row: TWinControl;

  function AddLink(const ACaption: string; ALeft: Integer; AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FPage);
    Result.Parent := Row;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, 1, 210, 25);
    Result.OnClick := AClick;
  end;

begin
  // Die Regeln stehen in atlas.json des Projekts und in settings.json („Weitere globale Einstellungen“), mit
  // einem Knoten je Gruppe; hier nur der Weg dorthin.
  AddWrappedLabel(34, TAtlasStrings.Text(TAtlasTextId.RulesGlobalNote));
  Row := AddPanel(28);
  FRulesProject := AddLink(TAtlasStrings.Text(TAtlasTextId.RulesProjectButton), 0, RulesProjectClick);
  FRulesGlobal := AddLink(TAtlasStrings.Text(TAtlasTextId.RulesGlobalButton), 216, RulesGlobalClick);
end;

procedure TAtlasSettingsRulesPart.AddNodePages;
var
  Box: TScrollBox;
  Row: TWinControl;
  mText: TLabel;

  function AddRow(ATop: Integer): TWinControl;
  begin
    Result := TAtlasSettingsRow.Create(FPage);
    Result.Parent := Box;
    Result.Align := alTop;
    Result.AlignWithMargins := True;
    Result.Height := 28;
    Result.Top := ATop;
  end;

  function AddButton(AParent: TWinControl; const ACaption: string; ALeft: Integer;
    AClick: TNotifyEvent): TButton;
  begin
    Result := TButton.Create(FPage);
    Result.Parent := AParent;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, 1, 210, 25);
    Result.OnClick := AClick;
  end;

begin
  // „Profile und Baseline“: Profile gelten je Projekt (atlas.json), die Baseline je Projekt.
  Box := FPage.NodeBox(FRulesArea, 'rules.profiles', TAtlasStrings.Text(TAtlasTextId.RulesProfilesNode));
  mText := TLabel.Create(FPage);
  mText.Parent := Box;
  mText.Align := alTop;
  mText.AlignWithMargins := True;
  mText.WordWrap := True;
  mText.ShowAccelChar := False;
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.RulesProfilesText);
  mText.Top := 1000;
  mText := TLabel.Create(FPage);
  mText.Parent := Box;
  mText.Align := alTop;
  mText.AlignWithMargins := True;
  mText.ShowAccelChar := False;
  mText.Font.Style := [fsBold];
  mText.Caption := TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineTitle);
  mText.Top := 3000;
  FBaselineInfo := TLabel.Create(FPage);
  FBaselineInfo.Parent := Box;
  FBaselineInfo.Align := alTop;
  FBaselineInfo.AlignWithMargins := True;
  FBaselineInfo.WordWrap := True;
  FBaselineInfo.ShowAccelChar := False;
  FBaselineInfo.Caption := TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineNone);
  FBaselineInfo.Top := 4000;
  Row := AddRow(5000);
  FBaselineUpdateButton := AddButton(Row, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineUpdate), 0,
    BaselineUpdateClick);
  FBaselineDelete := AddButton(Row, TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDelete), 216,
    BaselineDeleteClick);
end;

procedure TAtlasSettingsRulesPart.SetOnBaselineInfo(const AValue: TFunc<string>);
begin
  FOnBaselineInfo := AValue;
  if Assigned(FOnBaselineInfo) and (FBaselineInfo <> nil) then
  begin
    FBaselineInfo.Caption := FOnBaselineInfo();
  end;
end;

procedure TAtlasSettingsRulesPart.RulesProjectClick(Sender: TObject);
begin
  if Assigned(FOnRulesProject) then
  begin
    FOnRulesProject();
  end;
end;

procedure TAtlasSettingsRulesPart.RulesGlobalClick(Sender: TObject);
begin
  if Assigned(FOnRulesGlobal) then
  begin
    FOnRulesGlobal();
  end;
end;

procedure TAtlasSettingsRulesPart.BaselineUpdateClick(Sender: TObject);
begin
  if Assigned(FOnBaselineUpdate) then
  begin
    FBaselineInfo.Caption := FOnBaselineUpdate();
  end;
end;

procedure TAtlasSettingsRulesPart.BaselineDeleteClick(Sender: TObject);
begin
  if Assigned(FOnBaselineDelete) and (MessageDlg(TAtlasStrings.Text(TAtlasTextId.ServerPageBaselineDeleteConfirm),
    mtConfirmation, [mbYes, mbNo], 0) = mrYes) then
  begin
    FBaselineInfo.Caption := FOnBaselineDelete();
  end;
end;

procedure TAtlasSettingsRulesPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FProblemsWindowScope.Choice := Max(0, IndexText(ASettings.ProblemsWindowScope, ScopeValues));
  FProblemsWindowGroupBy.Choice := Max(0, IndexText(ASettings.ProblemsWindowGroupBy, GroupByValues));
  FProblemsWindowClosedUnits.Choice := Max(0, IndexText(ASettings.ProblemsWindowClosedUnits, ClosedUnitsValues));
  FProblemsCompilerMerge.Choice := Max(0, IndexText(ASettings.ProblemsCompilerMerge, CompilerMergeValues));
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
end;

end.
