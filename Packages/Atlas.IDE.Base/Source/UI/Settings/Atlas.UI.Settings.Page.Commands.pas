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
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings;

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
  BindCheck('MethodToggle', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodToggle)));
  BindKey('MethodToggleUpKey', AddKey(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMethodToggleUp)));
  BindKey('MethodToggleDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SettingsMethodToggleDown)));
  // Sprung zum Gegenstück (#635); aus: beide Tasten bleiben frei.
  BindCheck('JumpToMatch', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsJumpToMatch)));
  BindKey('JumpToMatchKey', AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchCommand)));
  BindKey('JumpToMatchSelectKey', AddKey(TAtlasStrings.Text(TAtlasTextId.JumpToMatchSelectCommand)));
  // Zeilen verschieben und duplizieren (#634); aus: die Tasten bleiben der IDE.
  BindCheck('MoveLines', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMoveLines)));
  BindKey('MoveLinesUpKey', AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesUpCommand)));
  BindKey('MoveLinesDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.MoveLinesDownCommand)));
  BindKey('DuplicateLinesUpKey', AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesUpCommand)));
  BindKey('DuplicateLinesDownKey', AddKey(TAtlasStrings.Text(TAtlasTextId.DuplicateLinesDownCommand)));
  // Blockkommentar umschalten (#703).
  BindCheck('ToggleBlockComment',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsToggleBlockComment)));
  BindKey('ToggleBlockCommentKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ToggleBlockCommentCommand)));
  FToggleBlockCommentStyle := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsToggleBlockCommentStyle),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentBraces),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentParens)]);
  FToggleBlockCommentFallback := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsToggleBlockCommentFallback),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentLineComments),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentRefuse)]);
  BindCheck('ToggleBlockCommentOwnLines',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsToggleBlockCommentOwnLines)));
  FToggleBlockCommentScope := AddChoice(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsToggleBlockCommentScope),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentStatement),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.ToggleBlockCommentLine)]);
  // Neue Zeile ober- oder unterhalb (#700).
  BindCheck('NewLineAround', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNewLineAround)));
  BindKey('NewLineBelowKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineBelowCommand)));
  BindKey('NewLineAboveKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NewLineAboveCommand)));
  BindCheck('NewLineAroundStatementAware',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNewLineAroundStatementAware)));
  // Umschließung entfernen (#657).
  BindCheck('Unwrap', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsUnwrap)));
  BindKey('UnwrapKey', AddKey(TAtlasStrings.Text(TAtlasTextId.UnwrapCommand)));
  // Sicher löschen (#716).
  BindCheck('SafeDelete', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSafeDelete)));
  BindKey('SafeDeleteKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SafeDeleteCommand)));
  BindKey('TestUnitKey', AddKey(TAtlasStrings.Text(TAtlasTextId.EditorTestUnit)));
  // Abschnittssprünge der Editorleiste (#1101), auch ohne die Leiste.
  BindKey('GotoInterfaceKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GotoInterfaceCommand)));
  BindKey('GotoImplementationKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GotoImplementationCommand)));
  // Navigationsverlauf über Dateien (#504).
  BindCheck('NavHistory', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNavHistory)));
  BindKey('NavBackKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavBackCommand)));
  BindKey('NavForwardKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavForwardCommand)));
  BindKey('LastEditKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NavLastEditCommand)));
end;

procedure TAtlasSettingsCommandsPart.Build2;
begin
  // Definition und Referenzen einblenden (#505).
  BindCheck('Peek', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPeek)));
  BindText('PeekHeightLines', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPeekHeight)));
  BindCheck('PeekShowImplementation',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPeekImplementation)));
  BindKey('PeekDefinitionKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PeekDefinitionCommand)));
  BindKey('PeekReferencesKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PeekReferencesCommand)));
  // Treffersicherheit der Verwendungen (#1119).
  BindCheck('ReferencesInferred',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReferencesInferred)));
  BindCheck('ReferencesTextMatches',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsReferencesTextMatches)));
  // Auswirkungsanalyse (#1120).
  BindCheck('Impact', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsImpact)));
  BindText('ImpactDepth', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsImpactDepth)));
  // Datenfluss im Ergebnisfenster (#690).
  BindCheck('DataFlow', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDataFlow)));
  BindText('DataFlowMaxDepth', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDataFlowMaxDepth)));
  BindCheck('DataFlowExcludeTests',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDataFlowExcludeTests)));
  BindCheck('Outline', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOutline)));
  BindCheck('OutlineAlphabetical',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOutlineAlphabetical)));
  BindCheck('OutlineFollowCursor',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOutlineFollowCursor)));
  BindCheck('OutlineConditions', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsOutlineConditions)));
  // „Element ausblenden …“ am gezeichneten Element (#628).
  BindKey('HideElementKey', AddKey(TAtlasStrings.Text(TAtlasTextId.HideElementCommand)));
  // Nächster/vorheriger Befund (#509).
  BindKey('NextProblemKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemNextCommand)));
  BindKey('PreviousProblemKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemPreviousCommand)));
  // Fenster „Atlas-Prüfung“ (#909).
  BindKey('ProblemsWindowKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemsWindowCommand)));
  // „Datei jetzt prüfen“ (#1744).
  BindKey('CheckFileKey', AddKey(TAtlasStrings.Text(TAtlasTextId.ProblemsCheckFileCommand)));
  // „Issue anlegen …“ (#1268), ohne Vorgabe.
  BindKey('CreateIssueKey', AddKey(TAtlasStrings.Text(TAtlasTextId.CreateIssueCommand)));
  BindKey('UndoKey', AddKey(TAtlasStrings.Text(TAtlasTextId.UndoMenu)));
  BindKey('RedoKey', AddKey(TAtlasStrings.Text(TAtlasTextId.RedoMenu)));
  BindCheck('EditorKeysPriority',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorKeysPriority)));
  BindCheck('SlashCommands', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSlashCommands)));
  // Einstellungen mit @ in der Befehlspalette (#1884).
  BindCheck('PaletteSettingsPrefix', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.PaletteSettingsPrefix)));
  // Erzeugen-Menü (#719): Schnellbefehle, Vorlagen und Code-Aktionen an der Cursorstelle.
  BindCheck('GenerateMenu', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGenerateMenu)));
  BindKey('GenerateMenuKey', AddKey(TAtlasStrings.Text(TAtlasTextId.GenerateMenuCommand)));
  BindText('GenerateMenuGroups',
    AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGenerateMenuGroups)));
  BindText('GenerateMenuHidden',
    AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGenerateMenuHidden)));
  BindCheck('GenerateMenuRecentFirst',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGenerateMenuRecentFirst)));
  BindCheck('GenerateMenuShowCommandNames',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGenerateMenuShowCommandNames)));
  // Untermenü Atlas in der Projektverwaltung (#1817).
  BindCheck('ProjectContextMenu',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsProjectContextMenu)));
  // Assistenten in Datei › Neu › Weitere (#1821).
  BindCheck('GalleryWizards', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGalleryWizards)));
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
