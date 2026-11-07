unit Atlas.UI.Settings.Page.EditorView;

// Reiter „Editor“, erster Teil: Anzeige im Editor (Editorleiste #1101, Statusleiste #1155, Kopf, Minimap,
// Änderungsmarken, gleiche Stellen).

interface

uses
  System.SysUtils,
  Vcl.StdCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Settings.ChoiceBox,
  Atlas.UI.EditorToolbar.Customize,
  Atlas.UI.Settings.Page.Host;

type
  /// <summary>Reiter „Editor“, erster Teil: Anzeige im Editor (Editorleiste #1101, Statusleiste #1155, Kopf,
  /// Minimap, Änderungsmarken, gleiche Stellen).</summary>
  TAtlasSettingsEditorViewPart = class(TAtlasSettingsPagePart)
  private
    FXmlDocExpand: TAtlasChoiceBox;
    FNestedRoutines: TAtlasChoiceBox;
    FStickyScrollBlockMinLines: TEdit;
    FMinimapRender: TAtlasChoiceBox;
    FMinimapSide: TAtlasChoiceBox;
    FMinimapShowSlider: TAtlasChoiceBox;
    FEditorToolbarPosition: TAtlasChoiceBox;
    FEditorToolbarItems: TEdit;
    FEditorToolbarLabels: TCheckBox;
    FEditorToolbarCustomize: TButton;
    FEditorStatusBarItems: TEdit;
    FOnToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>>;
    FGitGutter: TCheckBox;
    FSelectionMatchesMinLength: TEdit;
    FSelectionMatchesMaxMatches: TEdit;
    procedure EditorToolbarCustomizeClick(Sender: TObject);
  public
    procedure Build;
    procedure Build2;
    procedure Build3;
    procedure Load(const ASettings: TAtlasPluginSettings); override;
    procedure Save(var ASettings: TAtlasPluginSettings); override;
    procedure BindMarks; override;
    property StickyScrollBlockMinLines: TEdit read FStickyScrollBlockMinLines;
    property MinimapRender: TAtlasChoiceBox read FMinimapRender;
    /// <summary>Zum Testen: Färbung lokaler Routinen (#1788).</summary>
    property NestedRoutines: TAtlasChoiceBox read FNestedRoutines;
    /// <summary>Zum Testen: Editorleiste (#1101).</summary>
    property EditorToolbarItemsEdit: TEdit read FEditorToolbarItems;
    property EditorToolbarPositionBox: TAtlasChoiceBox read FEditorToolbarPosition;
    property EditorToolbarCustomizeButton: TButton read FEditorToolbarCustomize;
    property EditorStatusBarItemsEdit: TEdit read FEditorStatusBarItems;
    property SelectionMatchesMinLength: TEdit read FSelectionMatchesMinLength;
    property SelectionMatchesMaxMatches: TEdit read FSelectionMatchesMaxMatches;
    /// <summary>Befehle für „Leiste anpassen …“ der Editorleiste (#1101): Atlas-Befehle der Palette.</summary>
    property OnToolbarCommands: TFunc<TArray<TAtlasToolbarCommandInfo>> read FOnToolbarCommands
      write FOnToolbarCommands;
    property GitGutter: TCheckBox read FGitGutter;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  Vcl.Controls,
  Atlas.UI.Strings,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Editor.RoutineNesting,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.Settings.StatusBarItems;

{ TAtlasSettingsEditorViewPart }

procedure TAtlasSettingsEditorViewPart.Build;
var
  mPanel: TWinControl;
begin
  AddSheet(TAtlasTextId.SettingsTabEditor);
  BindCheck('HoverTooltip', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHover)));
  // Aktionszeile unter Befunden im Hover (#909).
  BindCheck('HoverProblemActions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsHoverProblemActions)));
  // Rollbereich der published-Mitglieder (#1841).
  BindText('HoverMembersMaxLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsHoverMembersMaxLines)));
  // XMLDoc in Tooltip und Detailpanel (#654, #770): zu- oder aufgeklappt beim Öffnen; gespeichert in
  // settings.json (hints.*, #227).
  FXmlDocExpand := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocExpand),
    [TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocCollapsed), TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocLast),
    TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocExpanded)]);
  BindText('XmlDocMaxLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsXmlDocMaxLines)));
  BindCheck('PairColors', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairs)));
  BindCheck('PairGuides', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuides)));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  BindCheck('PairOwners', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsPairOwners)));
  BindText('PairGuideWidth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideWidth)));
  BindText('PairGuideOpacity', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsPairGuideOpacity)));
  // Lokale Routinen abheben (#1788): Färbung und Band getrennt.
  FNestedRoutines := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsNestedRoutines),
    [TAtlasStrings.Text(TAtlasTextId.SettingsNestedRoutinesOuter),
    TAtlasStrings.Text(TAtlasTextId.SettingsNestedRoutinesDeeper),
    TAtlasStrings.Text(TAtlasTextId.SettingsNestedRoutinesColor)]);
  BindCheck('NestedRoutineBand', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsNestedRoutineBand)));
  BindCheck('InactiveDim', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInactiveDim)));
  BindCheck('InlayHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayHints)));
  // Typmarken von Inline-Variablen (#453), unabhängig von den Parameternamen.
  BindCheck('InlayTypeHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayTypeHints)));
  // Symbole aus Include-Dateien hinter {$I} (#860).
  BindCheck('InlayDefineHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayDefineHints)));
  // Code hinter Steuerzeichen wie ^C (#862).
  BindCheck('InlayCharHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayCharHints)));
  // Marke „braucht kein Self“ hinter Methoden, die Self nicht brauchen (#686).
  BindCheck('InlayMethodHints', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsInlayMethodHints)));
  // Beschriftung hinter dem end langer Blöcke (#620).
  BindCheck('BlockEndLabels', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabels)));
  BindText('BlockEndLabelsMinLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsBlockEndLabelsMinLines)));
  BindCheck('DimUnusedUses', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsDimUnusedUses)));
  // Brotkrumenleiste (#590).
  BindCheck('Breadcrumbs', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbs)));
  BindCheck('BreadcrumbsShowUnit', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsShowUnit)));
  BindCheck('BreadcrumbsIdeColors', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsIdeColors)));
  BindCheck('BreadcrumbsHideIdeToolbar', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsBreadcrumbsHideIdeToolbar)));
  BindKey('BreadcrumbsKey', AddKey(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand)));
  // Atlas-Editorleiste (#1101).
  BindCheck('EditorToolbar', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbar)));
  FEditorToolbarPosition := AddChoice(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPosition),
    [TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionBelow),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionAbove),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionInline)]);
  FEditorToolbarItems := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarItems));
  mPanel := AddPanel(32);
  FEditorToolbarCustomize := TButton.Create(FPage);
  FEditorToolbarCustomize.Parent := mPanel;
  FEditorToolbarCustomize.Caption := TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarCustomize);
  FEditorToolbarCustomize.Left := 0;
  FEditorToolbarCustomize.Top := 3;
  FEditorToolbarCustomize.Width := 180;
  FEditorToolbarCustomize.OnClick := EditorToolbarCustomizeClick;
  Attach(mPanel, FEditorToolbarItems);
  BindCheck('EditorToolbarReturnButton', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorToolbarReturnButton)));
  FEditorToolbarLabels := BindCheck('EditorToolbarLabels', AddCheck(TAtlasStrings.Text(TAtlasTextId.EditorToolbarLabels)));
end;

procedure TAtlasSettingsEditorViewPart.Build2;
begin
  // Atlas-Statusleiste unten im Editorfenster (#1155).
  BindCheck('EditorStatusBar', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsEditorStatusBar)));
  FEditorStatusBarItems := AddTextLine(TAtlasStrings.Text(TAtlasTextId.SettingsEditorStatusBarItems));
  // Aufrufdiagramm (#1122).
  BindCheck('CallHierarchyDiagram', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsCallHierarchyDiagram)));
  // Mitlaufender Kopf (#506, experimentell).
  BindCheck('StickyScroll', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScroll)));
  BindText('StickyScrollMaxLines', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollMaxLines)));
  BindCheck('StickyScrollTypes', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollTypes)));
  BindCheck('StickyScrollRoutines', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollRoutines)));
  BindCheck('StickyScrollBlocks', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollBlocks)));
  BindCheck('StickyScrollLoops', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollLoops)));
  BindCheck('StickyScrollTry', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollTry)));
  BindCheck('StickyScrollCase', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollCase)));
  BindCheck('StickyScrollWith', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollWith)));
  FStickyScrollBlockMinLines := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsStickyScrollBlockMinLines));
  // Minimap neben der Scrollleiste (#873, experimentell).
  BindCheck('Minimap', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimap)));
  FMinimapRender := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapRender),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapBlocks),
      TAtlasStrings.Text(TAtlasTextId.SettingsMinimapCharacters)]);
  BindText('MinimapWidth', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapWidth)));
  BindText('MinimapScale', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapScale)));
  BindText('MinimapMaxColumn', AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMaxColumn)));
  FMinimapSide := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSide),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapRight), TAtlasStrings.Text(TAtlasTextId.SettingsMinimapLeft)]);
  FMinimapShowSlider := AddChoice(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSlider),
    [TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSliderAlways),
    TAtlasStrings.Text(TAtlasTextId.SettingsMinimapSliderHover)]);
  BindCheck('MinimapSectionHeaders', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapHeaders)));
  BindCheck('MinimapHighlightMethod', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMethod)));
  BindCheck('MinimapMarkers', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapMarkers)));
  BindCheck('MinimapClickJumps', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsMinimapClickJumps)));
  // Änderungsmarken und Zeilenhistorie (#507).
  FGitGutter := BindCheck('GitGutter', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGitGutter)));
  BindKey('NextChangeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NextChangeCommand)));
  BindKey('PreviousChangeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PreviousChangeCommand)));
  BindCheck('GitBlame', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGitBlame)));
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und je Symbolart ein Häkchen.
  BindCheck('GutterColumn', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumn)));
  BindCheck('GutterColumnProblems', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnProblems)));
  BindCheck('GutterColumnCodeActions', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnActions)));
  BindCheck('GutterColumnOverrides', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsGutterColumnOverrides)));
  // Gleichen Text wie die Markierung hervorheben (#709).
  BindCheck('SelectionMatches', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatches)));
  FSelectionMatchesMinLength := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesMinLength));
end;

procedure TAtlasSettingsEditorViewPart.Build3;
begin
  BindCheck('SelectionMatchesCaseSensitive', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesCase)));
  BindCheck('SelectionMatchesWholeWord', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesWholeWord)));
  BindCheck('SelectionMatchesNavigateF3', AddCheck(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesF3)));
  FSelectionMatchesMaxMatches := AddNumber(TAtlasStrings.Text(TAtlasTextId.SettingsSelectionMatchesMax));
end;

procedure TAtlasSettingsEditorViewPart.BindMarks;
begin
  // Aus SaveTo: Element und die Einstellungen, die es schreibt. Listen aus mehreren Haken zeigen keinen Punkt
  // (der gälte für jeden Haken), lassen sich aber zurücksetzen.
  FPage.Marks.Bind(FEditorToolbarPosition, ['EditorToolbarPosition']);
  FPage.Marks.Bind(FEditorToolbarItems, ['EditorToolbarItems']);
  FPage.Marks.Bind(FEditorStatusBarItems, ['EditorStatusBarItems']);
  FPage.Marks.Bind(FStickyScrollBlockMinLines, ['StickyScrollBlockMinLines']);
  FPage.Marks.Bind(FMinimapRender, ['MinimapRender']);
  FPage.Marks.Bind(FMinimapSide, ['MinimapSide']);
  FPage.Marks.Bind(FMinimapShowSlider, ['MinimapShowSlider']);
  FPage.Marks.Bind(FSelectionMatchesMinLength, ['SelectionMatchesMinLength']);
  FPage.Marks.Bind(FSelectionMatchesMaxMatches, ['SelectionMatchesMaxMatches']);
  FPage.Marks.Bind(FXmlDocExpand, ['XmlDocExpand']);
  FPage.Marks.Bind(FNestedRoutines, ['NestedRoutines']);
end;

procedure TAtlasSettingsEditorViewPart.Load(const ASettings: TAtlasPluginSettings);
begin
  FEditorToolbarPosition.Choice := Max(0, IndexText(ASettings.EditorToolbarPosition, cAtlasToolbarPositions));
  FEditorToolbarItems.Text := ASettings.EditorToolbarItems;
  FEditorStatusBarItems.Text := ASettings.EditorStatusBarItems;
  FStickyScrollBlockMinLines.Text := IntToStr(ASettings.StickyScrollBlockMinLines);
  FMinimapRender.Choice := Max(0, IndexText(ASettings.MinimapRender, ['blocks', 'characters']));
  FMinimapSide.Choice := Max(0, IndexText(ASettings.MinimapSide, ['right', 'left']));
  FMinimapShowSlider.Choice := Max(0, IndexText(ASettings.MinimapShowSlider, ['always', 'mouseover']));
  FSelectionMatchesMinLength.Text := IntToStr(ASettings.SelectionMatchesMinLength);
  FSelectionMatchesMaxMatches.Text := IntToStr(ASettings.SelectionMatchesMaxMatches);
  FXmlDocExpand.Choice := Ord(TAtlasDocDisplay.ExpandOf(ASettings.XmlDocExpand));
  FNestedRoutines.Choice := Ord(TAtlasRoutineNesting.StyleOf(ASettings.NestedRoutines));
end;

procedure TAtlasSettingsEditorViewPart.Save(var ASettings: TAtlasPluginSettings);
begin
  ASettings.EditorToolbarPosition := cAtlasToolbarPositions[EnsureRange(FEditorToolbarPosition.Choice, 0,
    High(cAtlasToolbarPositions))];
  ASettings.EditorToolbarItems := TAtlasToolbarItems.Normalize(FEditorToolbarItems.Text);
  ASettings.EditorStatusBarItems := TAtlasStatusBarItems.Normalize(FEditorStatusBarItems.Text);
  ASettings.StickyScrollBlockMinLines := StrToIntDef(FStickyScrollBlockMinLines.Text,
    ASettings.StickyScrollBlockMinLines);
  ASettings.MinimapRender := 'blocks';
  if FMinimapRender.Choice = 1 then
  begin
    ASettings.MinimapRender := 'characters';
  end;
  ASettings.MinimapSide := 'right';
  if FMinimapSide.Choice = 1 then
  begin
    ASettings.MinimapSide := 'left';
  end;
  ASettings.MinimapShowSlider := 'always';
  if FMinimapShowSlider.Choice = 1 then
  begin
    ASettings.MinimapShowSlider := 'mouseover';
  end;
  ASettings.SelectionMatchesMinLength := StrToIntDef(FSelectionMatchesMinLength.Text,
    ASettings.SelectionMatchesMinLength);
  ASettings.SelectionMatchesMaxMatches := StrToIntDef(FSelectionMatchesMaxMatches.Text,
    ASettings.SelectionMatchesMaxMatches);
  ASettings.XmlDocExpand := TAtlasDocDisplay.ExpandName(TAtlasDocExpand(EnsureRange(FXmlDocExpand.Choice, 0, 2)));
  ASettings.NestedRoutines := TAtlasRoutineNesting.cStyleNames[TAtlasNestedRoutineStyle(EnsureRange(
    FNestedRoutines.Choice, Ord(Low(TAtlasNestedRoutineStyle)), Ord(High(TAtlasNestedRoutineStyle))))];
end;

/// <summary>„Leiste anpassen …“ (#1101): Dialog auf den Werten der Seite; übernommen wird erst mit OK der Optionen.
/// </summary>
procedure TAtlasSettingsEditorViewPart.EditorToolbarCustomizeClick(Sender: TObject);
var
  mCommands: TArray<TAtlasToolbarCommandInfo>;
  mConfig: TAtlasToolbarConfig;
begin
  mCommands := nil;
  if Assigned(FOnToolbarCommands) then
  begin
    mCommands := FOnToolbarCommands();
  end;
  mConfig.Items := TAtlasToolbarItems.Parse(FEditorToolbarItems.Text);
  mConfig.Labels := FEditorToolbarLabels.Checked;
  mConfig.Position := cAtlasToolbarPositions[EnsureRange(FEditorToolbarPosition.Choice, 0,
    High(cAtlasToolbarPositions))];
  if not TAtlasToolbarCustomizeDialog.Execute(mCommands, mConfig) then
  begin
    Exit;
  end;
  FEditorToolbarItems.Text := TAtlasToolbarItems.Format(mConfig.Items);
  FEditorToolbarLabels.Checked := mConfig.Labels;
  FEditorToolbarPosition.Choice := Max(0, IndexText(mConfig.Position, cAtlasToolbarPositions));
end;

end.
