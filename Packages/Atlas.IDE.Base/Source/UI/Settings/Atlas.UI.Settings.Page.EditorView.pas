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
  Atlas.UI.Settings.Strings,
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
  BindCheck('HoverTooltip', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsHover)));
  // Aktionszeile unter Befunden im Hover (#909).
  BindCheck('HoverProblemActions',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsHoverProblemActions)));
  // Rollbereich der published-Mitglieder (#1841).
  BindText('HoverMembersMaxLines',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsHoverMembersMaxLines)));
  // Parameter und Rückgabe immer offen (#1919).
  BindCheck('HoverSignatureParams',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsHoverSignatureParams)));
  // XMLDoc in Tooltip und Detailpanel (#654, #770): zu- oder aufgeklappt beim Öffnen; gespeichert in
  // settings.json (hints.*, #227).
  FXmlDocExpand := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsXmlDocExpand),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsXmlDocCollapsed),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsXmlDocLast),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsXmlDocExpanded)]);
  BindText('XmlDocMaxLines', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsXmlDocMaxLines)));
  BindCheck('PairColors', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairs)));
  BindCheck('PairGuides', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairGuides)));
  // Anweisungen mitfärben, Linienbreite und Deckkraft (#653); wirken nur mit der Paarfärbung.
  BindCheck('PairOwners', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairOwners)));
  BindText('PairGuideWidth', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairGuideWidth)));
  BindText('PairGuideOpacity', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsPairGuideOpacity)));
  // Lokale Routinen abheben (#1788): Färbung und Band getrennt.
  FNestedRoutines := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutines),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutinesOuter),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutinesDeeper),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutinesColor)]);
  BindCheck('NestedRoutineBand', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsNestedRoutineBand)));
  BindCheck('InactiveDim', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInactiveDim)));
  BindCheck('InlayHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlayHints)));
  // Typmarken von Inline-Variablen (#453), unabhängig von den Parameternamen.
  BindCheck('InlayTypeHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlayTypeHints)));
  // Symbole aus Include-Dateien hinter {$I} (#860).
  BindCheck('InlayDefineHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlayDefineHints)));
  // Code hinter Steuerzeichen wie ^C (#862).
  BindCheck('InlayCharHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlayCharHints)));
  // Marke „braucht kein Self“ hinter Methoden, die Self nicht brauchen (#686).
  BindCheck('InlayMethodHints', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsInlayMethodHints)));
  // Beschriftung hinter dem end langer Blöcke (#620).
  BindCheck('BlockEndLabels', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBlockEndLabels)));
  BindText('BlockEndLabelsMinLines',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBlockEndLabelsMinLines)));
  BindCheck('DimUnusedUses', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsDimUnusedUses)));
  // Brotkrumenleiste (#590).
  BindCheck('Breadcrumbs', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbs)));
  BindCheck('BreadcrumbsShowUnit',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsShowUnit)));
  // Sichtbarkeitsabschnitt als Glied (#1759).
  BindCheck('BreadcrumbsVisibility',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsVisibility)));
  // Unterblock in Typen (#1767).
  BindCheck('BreadcrumbsMemberBlocks',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsMemberBlocks)));
  // Sichtbarkeitsmarke am Methodenglied (#1765).
  BindCheck('BreadcrumbsVisibilityMark',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsVisibilityMark)));
  // Deklarationsblock der Unit (#1766).
  BindCheck('BreadcrumbsDeclarationBlocks',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsDeclarationBlocks)));
  // Bedingungszweig (#1763).
  BindCheck('BreadcrumbsConditionals',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsConditionals)));
  // Region (#1764).
  BindCheck('BreadcrumbsRegions',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsRegions)));
  // try/except/finally und case-Zweig (#1769).
  BindCheck('BreadcrumbsStatements',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsStatements)));
  // Sprungmenü am Sichtbarkeitsglied (#1768).
  BindCheck('BreadcrumbsSectionCounts',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsSectionCounts)));
  BindCheck('BreadcrumbsSectionAppend',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsSectionAppend)));
  BindCheck('BreadcrumbsSectionCreate',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsSectionCreate)));
  BindCheck('BreadcrumbsIdeColors',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsIdeColors)));
  BindCheck('BreadcrumbsHideIdeToolbar',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsHideIdeToolbar)));
  BindKey('BreadcrumbsKey', AddKey(TAtlasStrings.Text(TAtlasTextId.BreadcrumbsCommand)));
  BindKey('SectionAppendKey', AddKey(TAtlasStrings.Text(TAtlasTextId.SectionAppendCommand)));
  // Rechtsklick-Menü an den Gliedern (#1786).
  BindCheck('BreadcrumbsContextMenu',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsContextMenu)));
  // Überladungen mit Zähler und Parametern (#1784).
  BindCheck('BreadcrumbsOverloads',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsOverloads)));
  BindCheck('BreadcrumbsInterfaces',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsInterfaces)));
  BindCheck('BreadcrumbsMetrics',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsBreadcrumbsMetrics)));
  BindCheck('MouseNavButtons', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMouseNavButtons)));
  // Atlas-Editorleiste (#1101).
  BindCheck('EditorToolbar', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorToolbar)));
  FEditorToolbarPosition := AddChoice(TAtlasStrings.Text(TAtlasTextId.EditorToolbarPosition),
    [TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionBelow),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionAbove),
    TAtlasStrings.Text(TAtlasTextId.EditorToolbarPositionInline)]);
  FEditorToolbarItems := AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorToolbarItems));
  mPanel := AddPanel(32);
  FEditorToolbarCustomize := TButton.Create(FPage);
  FEditorToolbarCustomize.Parent := mPanel;
  FEditorToolbarCustomize.Caption := TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorToolbarCustomize);
  FEditorToolbarCustomize.Left := 0;
  FEditorToolbarCustomize.Top := 3;
  FEditorToolbarCustomize.Width := 180;
  FEditorToolbarCustomize.OnClick := EditorToolbarCustomizeClick;
  Attach(mPanel, FEditorToolbarItems);
  BindCheck('EditorToolbarReturnButton',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorToolbarReturnButton)));
  FEditorToolbarLabels := BindCheck('EditorToolbarLabels', AddCheck(TAtlasStrings.Text(TAtlasTextId.EditorToolbarLabels)));
end;

procedure TAtlasSettingsEditorViewPart.Build2;
begin
  // Atlas-Statusleiste unten im Editorfenster (#1155).
  BindCheck('EditorStatusBar', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorStatusBar)));
  FEditorStatusBarItems := AddTextLine(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEditorStatusBarItems));
  // Aufrufdiagramm (#1122).
  BindCheck('CallHierarchyDiagram',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsCallHierarchyDiagram)));
  // Mitlaufender Kopf (#506, experimentell).
  BindCheck('StickyScroll', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScroll)));
  BindText('StickyScrollMaxLines',
    AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollMaxLines)));
  BindCheck('StickyScrollTypes', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollTypes)));
  BindCheck('StickyScrollRoutines',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollRoutines)));
  BindCheck('StickyScrollBlocks',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollBlocks)));
  BindCheck('StickyScrollLoops', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollLoops)));
  BindCheck('StickyScrollTry', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollTry)));
  BindCheck('StickyScrollCase', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollCase)));
  BindCheck('StickyScrollWith', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsStickyScrollWith)));
  FStickyScrollBlockMinLines := AddNumber(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsStickyScrollBlockMinLines));
  // Minimap neben der Scrollleiste (#873, experimentell).
  BindCheck('Minimap', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimap)));
  FMinimapRender := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapRender),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapBlocks),
      TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapCharacters)]);
  BindText('MinimapWidth', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapWidth)));
  BindText('MinimapScale', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapScale)));
  BindText('MinimapMaxColumn', AddNumber(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapMaxColumn)));
  FMinimapSide := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapSide),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapRight),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapLeft)]);
  FMinimapShowSlider := AddChoice(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapSlider),
    [TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapSliderAlways),
    TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapSliderHover)]);
  BindCheck('MinimapSectionHeaders', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapHeaders)));
  BindCheck('MinimapHighlightMethod', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapMethod)));
  BindCheck('MinimapMarkers', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapMarkers)));
  BindCheck('MinimapClickJumps', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsMinimapClickJumps)));
  // Änderungsmarken und Zeilenhistorie (#507).
  FGitGutter := BindCheck('GitGutter', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGitGutter)));
  BindKey('NextChangeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.NextChangeCommand)));
  BindKey('PreviousChangeKey', AddKey(TAtlasStrings.Text(TAtlasTextId.PreviousChangeCommand)));
  BindCheck('GitBlame', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGitBlame)));
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und je Symbolart ein Häkchen.
  BindCheck('GutterColumn', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGutterColumn)));
  BindCheck('GutterColumnProblems',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGutterColumnProblems)));
  BindCheck('GutterColumnCodeActions',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGutterColumnActions)));
  BindCheck('GutterColumnOverrides',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsGutterColumnOverrides)));
  // Gleichen Text wie die Markierung hervorheben (#709).
  BindCheck('SelectionMatches', AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSelectionMatches)));
  FSelectionMatchesMinLength := AddNumber(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsSelectionMatchesMinLength));
end;

procedure TAtlasSettingsEditorViewPart.Build3;
begin
  BindCheck('SelectionMatchesCaseSensitive',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSelectionMatchesCase)));
  BindCheck('SelectionMatchesWholeWord',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSelectionMatchesWholeWord)));
  BindCheck('SelectionMatchesNavigateF3',
    AddCheck(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsSelectionMatchesF3)));
  FSelectionMatchesMaxMatches := AddNumber(TAtlasSettingsStrings.Text(
    TAtlasSettingsTextId.SettingsSelectionMatchesMax));
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
