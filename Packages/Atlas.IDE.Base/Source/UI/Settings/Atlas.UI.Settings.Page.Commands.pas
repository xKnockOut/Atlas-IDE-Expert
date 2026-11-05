unit Atlas.UI.Settings.Page.Commands;

// Reiter „Editorbefehle“ (#399): Tasten der Befehle und Blockkommentar (#703).

interface

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editorbefehle“ (#399): Tasten der Befehle und Blockkommentar (#703).</summary>
  TAtlasSettingsCommandsPart = class(TAtlasSettingsPagePart)
  private
    FToggleBlockCommentStyle: TAtlasChoiceBox;
    FToggleBlockCommentFallback: TAtlasChoiceBox;
    FToggleBlockCommentScope: TAtlasChoiceBox;
  public
    procedure Build;
    procedure Build2;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property ToggleBlockCommentStyle: TAtlasChoiceBox read FToggleBlockCommentStyle;
    property ToggleBlockCommentFallback: TAtlasChoiceBox read FToggleBlockCommentFallback;
    property ToggleBlockCommentScope: TAtlasChoiceBox read FToggleBlockCommentScope;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Atlas.UI.Strings;

{ TAtlasSettingsCommandsPart }

procedure TAtlasSettingsCommandsPart.Build;
begin
  // Editorbefehle (#399): ein Vorrang für alle.
  AddSheet(TAtlasTextId.SettingsTabCommands);
  BindKey('ActionsKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorActions)));
  BindKey('ExpandKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorExpand)));
  BindKey('ShrinkKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorShrink)));
  BindKey('ImplementationKey', AddKey(TAtlasStrings.Text(TAtlasTextId.MenuImplementations)));
  BindKey('TypeDefinitionKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTypeDefinition)));
  // Deklaration ⇄ Implementierung (#775); aus: Klassennavigation der IDE.
  BindCheck('MethodToggle', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggle)));
  BindKey('MethodToggleUpKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggleUp)));
  BindKey('MethodToggleDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggleDown)));
  // Sprung zum Gegenstück (#635); aus: beide Tasten bleiben frei.
  BindCheck('JumpToMatch', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsJumpToMatch)));
  BindKey('JumpToMatchKey', AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchCommand)));
  BindKey('JumpToMatchSelectKey', AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchSelectCommand)));
  // Zeilen verschieben und duplizieren (#634); aus: die Tasten bleiben der IDE.
  BindCheck('MoveLines', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMoveLines)));
  BindKey('MoveLinesUpKey', AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesUpCommand)));
  BindKey('MoveLinesDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesDownCommand)));
  BindKey('DuplicateLinesUpKey', AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesUpCommand)));
  BindKey('DuplicateLinesDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesDownCommand)));
  // Blockkommentar umschalten (#703).
  BindCheck('ToggleBlockComment', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockComment)));
  BindKey('ToggleBlockCommentKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentCommand)));
  FToggleBlockCommentStyle := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentStyle),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentBraces),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentParens)]);
  FToggleBlockCommentFallback := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentFallback),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentLineComments),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentRefuse)]);
  BindCheck('ToggleBlockCommentOwnLines', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentOwnLines)));
  FToggleBlockCommentScope := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsToggleBlockCommentScope),
    [TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentStatement),
    TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentLine)]);
  // Neue Zeile ober- oder unterhalb (#700).
  BindCheck('NewLineAround', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNewLineAround)));
  BindKey('NewLineBelowKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineBelowCommand)));
  BindKey('NewLineAboveKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineAboveCommand)));
  BindCheck('NewLineAroundStatementAware', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNewLineAroundStatementAware)));
  // Umschließung entfernen (#657).
  BindCheck('Unwrap', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsUnwrap)));
  BindKey('UnwrapKey', AddKey(TAtlasStrings.Text(TAtlasTextId.UnwrapCommand)));
  // Sicher löschen (#716).
  BindCheck('SafeDelete', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSafeDelete)));
  BindKey('SafeDeleteKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand)));
  BindKey('TestUnitKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTestUnit)));
  // Abschnittssprünge der Editorleiste (#1101), auch ohne die Leiste.
  BindKey('GotoInterfaceKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand)));
  BindKey('GotoImplementationKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand)));
  // Navigationsverlauf über Dateien (#504).
  BindCheck('NavHistory', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNavHistory)));
  BindKey('NavBackKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavBackCommand)));
  BindKey('NavForwardKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavForwardCommand)));
  BindKey('LastEditKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavLastEditCommand)));
end;

procedure TAtlasSettingsCommandsPart.Build2;
begin
  // Definition und Referenzen einblenden (#505).
  BindCheck('Peek', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPeek)));
  BindText('PeekHeightLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPeekHeight)));
  BindCheck('PeekShowImplementation', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPeekImplementation)));
  BindKey('PeekDefinitionKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand)));
  BindKey('PeekReferencesKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PeekReferencesCommand)));
  // Treffersicherheit der Verwendungen (#1119).
  BindCheck('ReferencesInferred', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReferencesInferred)));
  BindCheck('ReferencesTextMatches', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsReferencesTextMatches)));
  // Auswirkungsanalyse (#1120).
  BindCheck('Impact', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsImpact)));
  BindText('ImpactDepth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsImpactDepth)));
  // Datenfluss im Ergebnisfenster (#690).
  BindCheck('DataFlow', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlow)));
  BindText('DataFlowMaxDepth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlowMaxDepth)));
  BindCheck('DataFlowExcludeTests', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDataFlowExcludeTests)));
  BindCheck('Outline', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutline)));
  BindCheck('OutlineAlphabetical', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineAlphabetical)));
  BindCheck('OutlineFollowCursor', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineFollowCursor)));
  BindCheck('OutlineConditions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsOutlineConditions)));
  // „Element ausblenden …“ am gezeichneten Element (#628).
  BindKey('HideElementKey', AddKey(TAtlasStrings.Text(TAtlasTextId.HideElementCommand)));
  // Nächster/vorheriger Befund (#509).
  BindKey('NextProblemKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand)));
  BindKey('PreviousProblemKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand)));
  // Fenster „Atlas-Prüfung“ (#909).
  BindKey('ProblemsWindowKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemsWindowCommand)));
  // „Issue anlegen …“ (#1268), ohne Vorgabe.
  BindKey('CreateIssueKey', AddKey(TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand)));
  BindKey('UndoKey', AddKey(TAtlasStrings.Text(TAtlasTextId.UndoMenu)));
  BindKey('RedoKey', AddKey(TAtlasStrings.Text(TAtlasTextId.RedoMenu)));
  BindCheck('EditorKeysPriority', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorKeysPriority)));
  BindCheck('SlashCommands', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSlashCommands)));
  // Erzeugen-Menü (#719): Schnellbefehle, Vorlagen und Code-Aktionen an der Cursorstelle.
  BindCheck('GenerateMenu', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenu)));
  BindKey('GenerateMenuKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand)));
  BindText('GenerateMenuGroups', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuGroups)));
  BindText('GenerateMenuHidden', AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuHidden)));
  BindCheck('GenerateMenuRecentFirst', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuRecentFirst)));
  BindCheck('GenerateMenuShowCommandNames', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGenerateMenuShowCommandNames)));
  // Liste der Benachrichtigungen (#601).
  BindKey('NotificationsKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NotificationsCommand)));
end;

procedure TAtlasSettingsCommandsPart.BindMarks;
begin
  FPage.Marks.Bind(FToggleBlockCommentStyle, ['ToggleBlockCommentStyle']);
  FPage.Marks.Bind(FToggleBlockCommentFallback, ['ToggleBlockCommentFallback']);
  FPage.Marks.Bind(FToggleBlockCommentScope, ['ToggleBlockCommentWithoutSelection']);
end;

procedure TAtlasSettingsCommandsPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FToggleBlockCommentStyle.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentStyle, ['braces', 'parens']));
  FToggleBlockCommentFallback.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentFallback,
    ['lineComments', 'refuse']));
  FToggleBlockCommentScope.Choice := Max(0, IndexText(ASettings.ToggleBlockCommentWithoutSelection,
    ['statement', 'line']));
end;

procedure TAtlasSettingsCommandsPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.ToggleBlockCommentStyle := 'braces';
  if FToggleBlockCommentStyle.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentStyle := 'parens';
  end;
  ASettings.ToggleBlockCommentFallback := 'lineComments';
  if FToggleBlockCommentFallback.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentFallback := 'refuse';
  end;
  ASettings.ToggleBlockCommentWithoutSelection := 'statement';
  if FToggleBlockCommentScope.Choice = 1 then
  begin
    ASettings.ToggleBlockCommentWithoutSelection := 'line';
  end;
end;

end.
