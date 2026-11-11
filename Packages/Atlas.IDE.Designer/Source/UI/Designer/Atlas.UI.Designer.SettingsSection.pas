unit Atlas.UI.Designer.SettingsSection;

// Abschnitt „Editor“ des Moduls Designer im Optionsdialog (#1456; vorher im Teil
// „Editor“ von Base): Modulschalter und Designer-Leiste im Formular-Designer (#1442), Tab-Reihenfolge (#603),
// Gleiche auswählen (#738), Befehle im Menü „Anordnen“ (#730 ff.), fast bündige Kanten (#746), Standardgrößen
// (#747), Ebenen (#749), Format-Pinsel (#726), Anchors vorschlagen (#727), Texte des Formulars (#728), Label und
// Feld (#729), Formularraster (#731), Einpacken in Container (#733), Schriften und Farben (#741), Gruppen (#744),
// Beschriftung (#748), Werkzeuge mit eigenem Knopf (#734 ff.), Designer-Ansichten mit eigenem Knopf (#605 ff.).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasDesignerSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.designer';
    cAreaId = 'Editor';
  private
    /// <summary>Zeilen der Befehle im Menü „Anordnen“ (#730 ff.).</summary>
    procedure BuildArrangeRows;
    /// <summary>Zeilen der eigenen Knöpfe der Designer-Leiste (#605 ff.).</summary>
    procedure BuildViewRows;
    /// <summary>Zeilen von Ebenen (#749), Format-Pinsel (#726), Anchors vorschlagen (#727), Texte des Formulars (#728) und Label und Feld (#729).</summary>
    procedure BuildToolRows;
    /// <summary>Zeilen von Label und Feld (#729), Formularraster (#731), Einpacken (#733) und Schriften und Farben (#741).</summary>
    procedure BuildPairRows;
    /// <summary>Zeilen der Werkzeuge mit eigenem Knopf in der Designer-Leiste (#734 ff.).</summary>
    procedure BuildButtonRows;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.ToolStrings,
  Atlas.UI.Designer.ViewStrings;

{ TAtlasDesignerSettingsSection }

function TAtlasDesignerSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasDesignerSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasDesignerSettingsSection.BuildRows;
begin
  ModuleSwitch('designer.enabled');
  Switch('editor.designerBar', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsEditorDesignerBar));
  Key('editor.designerBar.searchKey', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSearchKey));
  Choice('editor.designerBar.searchStyle', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSearchStyle),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSearchWindow),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSearchPopup)],
    [TAtlasPluginSettings.cDesignerSearchWindow, TAtlasPluginSettings.cDesignerSearchPopup]);
  Switch('editor.designerBar.tabOrderClick', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTabOrderClick));
  Switch('designer.tabOrderOverlay',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTabOrderOverlay));
  Switch('designer.tabOrderPaths', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTabOrderPaths));
  Switch('editor.designerBar.align', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerAlign));
  Switch('designer.selectSimilar', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectSimilar));
  Switch('designer.selectSimilar.includeDescendants',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectDescendants));
  Choice('designer.selectSimilar.scope', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectScope),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerScopeForm),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerScopeParent)],
    [TAtlasPluginSettings.cDesignerScopeForm, TAtlasPluginSettings.cDesignerScopeParent]);
  Switch('designer.selectionSets', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectionSets));
  Switch('designer.selectionSets.shortcuts',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectionSetsShortcuts));
  Key('designer.selectionSets.saveKey',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectionSetsSaveKey));
  Choice('designer.selectionSets.storage',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSelectionSetsStorage),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSetsLocal),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSetsShared)],
    [TAtlasPluginSettings.cDesignerSetsLocal, TAtlasPluginSettings.cDesignerSetsShared]);
  Switch('designer.showInDesigner',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerShowInDesigner));
  Key('designer.showInDesigner.key', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerShowKey));
  Switch('designer.propertySearch',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPropertySearch));
  Switch('designer.spatialNavigation',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSpatialNavigation));
  Switch('designer.spatialNavigation.crossContainers',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSpatialCross));
  BuildViewRows;
  BuildArrangeRows;
  BuildToolRows;
  BuildButtonRows;
end;

procedure TAtlasDesignerSettingsSection.BuildViewRows;
begin
  Switch('designer.measureDistances',
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsMeasureDistances));
  Switch('designer.measureAltKey', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsMeasureAltKey));
  Switch('designer.resizePreview', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsResizePreview));
  Line('designer.resizePreviewSizes', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsResizeSizes));
  Switch('designer.resizePreviewShowAnchors',
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsResizeAnchors));
  Switch('designer.scalePreview', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsScalePreview));
  Line('designer.scalePreviewLevels', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsScaleLevels));
  Line('designer.scalePreviewScreens', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsScaleScreens));
  Number('designer.longTextFactor', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.SettingsLongTextFactor));
end;

procedure TAtlasDesignerSettingsSection.BuildArrangeRows;
begin
  Switch('designer.fitToText', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitToText));
  Number('designer.fitToText.minWidth', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitMinWidth));
  Number('designer.fitToText.padding', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitPadding));
  Line('designer.fitToText.sources', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitSources));
  Switch('designer.buttonBar', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBar));
  Line('designer.buttonBar.order', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarOrder));
  Choice('designer.buttonBar.position',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarPosition),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerBarBottomRight),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerBarBottomLeft),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerBarRightTop),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerBarRightBottom)],
    [TAtlasPluginSettings.cButtonBarBottomRight, TAtlasPluginSettings.cButtonBarBottomLeft,
    TAtlasPluginSettings.cButtonBarRightTop, TAtlasPluginSettings.cButtonBarRightBottom]);
  Number('designer.buttonBar.gap', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarGap));
  Number('designer.buttonBar.margin', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarMargin));
  Switch('designer.buttonBar.setModalResult',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarModal));
  Line('designer.buttonBar.roles', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerButtonBarRoles));
  Switch('designer.duplicateRow', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerDuplicateRow));
  Switch('designer.duplicateRow.shareEvents',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerDuplicateShare));
  Number('designer.duplicateRow.defaultGap',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerDuplicateGap));
  Switch('designer.insertSpace', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerInsertSpace));
  Switch('designer.insertSpace.growParent',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerInsertSpaceGrow));
  Switch('designer.fitContainer', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitContainer));
  Number('designer.fitContainer.padding',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitContainerPadding));
  Switch('designer.fitContainer.alignTopLeft',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFitContainerTopLeft));
  Switch('designer.nearAlignment', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerNearAlignment));
  Number('designer.nearAlignment.tolerance',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerNearTolerance));
  Switch('designer.nearAlignment.baseline',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerNearBaseline));
  Line('designer.nearAlignment.ignoreClasses',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerNearIgnore));
  Switch('designer.defaultSizes', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerDefaultSizes));
  Line('designer.defaultSizes.table', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSizesTable));
  Switch('designer.defaultSizes.applyOnInsert',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSizesOnInsert));
  Switch('designer.defaultSizes.markDeviations',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSizesMark));
end;

procedure TAtlasDesignerSettingsSection.BuildToolRows;
begin
  Switch('designer.zOrder', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerZOrder));
  Switch('designer.zOrder.shortcuts',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerZOrderShortcuts));
  Switch('designer.zOrder.includeParents',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerZOrderParents));
  Switch('designer.propertyPainter', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPainter));
  Line('designer.propertyPainter.defaultGroups',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPainterGroups));
  Switch('designer.propertyPainter.rememberPerClass',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPainterRemember));
  Switch('designer.suggestAnchors', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerAnchors));
  Number('designer.suggestAnchors.edgeDistance',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerAnchorsEdge));
  Switch('designer.suggestAnchors.keepExisting',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerAnchorsKeep));
  Line('designer.suggestAnchors.fillClasses',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerAnchorsFill));
  Switch('designer.textTable', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTexts));
  Line('designer.textTable.checks', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTextsChecks));
  Line('designer.textTable.synonyms', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTextsSynonyms));
  Line('designer.textTable.excludeProperties',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerTextsExclude));
  BuildPairRows;
end;

procedure TAtlasDesignerSettingsSection.BuildPairRows;
begin
  Switch('designer.labelPairs', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairs));
  Switch('designer.labelPairs.baseline', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsBaseline));
  Switch('designer.labelPairs.focusControl',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsFocus));
  Switch('designer.labelPairs.moveTogether',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsMove));
  Number('designer.labelPairs.pairDistance',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsDistance));
  Choice('designer.labelPairs.newLabelPosition',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsPosition),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsLeft),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsAbove)],
    [TAtlasPluginSettings.cLabelLeft, TAtlasPluginSettings.cLabelAbove]);
  Line('designer.labelPairs.abbreviations',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsAbbreviations));
  Switch('designer.arrangeForm', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGrid));
  Number('designer.arrangeForm.rowGap', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridRowGap));
  Number('designer.arrangeForm.labelGap', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridLabelGap));
  Choice('designer.arrangeForm.labelAlign', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridAlign),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridLeft),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridRight),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerPairsAbove)],
    [TAtlasPluginSettings.cGridLabelLeft, TAtlasPluginSettings.cGridLabelRight, TAtlasPluginSettings.cGridLabelAbove]);
  Switch('designer.arrangeForm.equalFieldWidth',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridEqual));
  Switch('designer.arrangeForm.twoPerRow', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridTwo));
  Switch('designer.arrangeForm.setTabOrder',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGridTabOrder));
  Switch('designer.wrapInContainer', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerWrap));
  Number('designer.wrapInContainer.padding',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerWrapPadding));
  Line('designer.wrapInContainer.defaultClass',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerWrapDefault));
  Line('designer.wrapInContainer.classes',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerWrapClasses));
  Switch('designer.fontsColors', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFonts));
  Switch('designer.fontsColors.restoreParent',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFontsRestore));
  Line('designer.fontsColors.ignoreColors',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerFontsIgnore));
  Switch('designer.groups', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGroups));
  Choice('designer.groups.memberClick', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGroupsClick),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGroupsAlt),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGroupsDouble)],
    [TAtlasPluginSettings.cDesignerGroupsAltClick, TAtlasPluginSettings.cDesignerGroupsDoubleClick]);
  Choice('designer.groups.storage', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerGroupsStorage),
    [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSetsLocal),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSetsShared)],
    [TAtlasPluginSettings.cDesignerSetsLocal, TAtlasPluginSettings.cDesignerSetsShared]);
  Switch('designer.inlineCaption', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerCaption));
  Switch('designer.inlineCaption.slowDoubleClick',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerCaptionSlow));
  Switch('designer.inlineCaption.autoWidth',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerCaptionWidth));
  Key('designer.inlineCaption.key', TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerCaptionKey));
  Line('designer.inlineCaption.properties',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerCaptionMap));
end;

procedure TAtlasDesignerSettingsSection.BuildButtonRows;
begin
  Switch('designer.gapHandles', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapHandles));
  Line('designer.gapHandles.snapValues', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapSnap));
  Choice('designer.gapHandles.anchor', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapAnchor),
    [TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapCenter),
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapFirst),
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsGapLast)],
    [TAtlasPluginSettings.cGapAnchorCenter, TAtlasPluginSettings.cGapAnchorFirst, TAtlasPluginSettings.cGapAnchorLast]);
  Switch('designer.multiResize', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsResize));
  Choice('designer.multiResize.mode', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsResizeMode),
    [TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsResizeDelta),
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsResizeAlign)],
    [TAtlasPluginSettings.cResizeModeDelta, TAtlasPluginSettings.cResizeModeAlign]);
  Switch('designer.multiResize.leftTopHandles',
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsResizeLeftTop));
  Switch('designer.selectionBar', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBar));
  Choice('designer.selectionBar.mode', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarMode),
    [TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarAuto),
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarShortcut)],
    [TAtlasPluginSettings.cSelectionBarAuto, TAtlasPluginSettings.cSelectionBarShortcut]);
  Number('designer.selectionBar.delayMs', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarDelay));
  Line('designer.selectionBar.items', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarItems));
  Key('designer.selectionBar.key', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsBarKey));
  Switch('designer.magnifier', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsMag));
  Number('designer.magnifier.zoom', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsMagZoom));
  Switch('designer.magnifier.grid', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsMagGrid));
  Switch('designer.magnifier.edges', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsMagEdges));
  Key('designer.magnifier.key', TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.SettingsMagKey));
end;

end.
