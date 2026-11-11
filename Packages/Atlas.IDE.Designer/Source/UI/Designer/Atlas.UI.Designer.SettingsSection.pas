unit Atlas.UI.Designer.SettingsSection;

// Abschnitt „Editor“ des Moduls Designer im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher im Teil
// „Editor“ von Base): Modulschalter und Designer-Leiste im Formular-Designer (#1442), Gleiche auswählen (#738),
// Befehle im Menü „Anordnen“ (#730 ff.), fast bündige Kanten (#746), Werkzeuge mit eigenem Knopf (#734 ff.),
// Designer-Ansichten mit eigenem Knopf (#605 ff.).

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
    /// <summary>Zeilen der Werkzeuge mit eigenem Knopf in der Designer-Leiste (#734 ff.).</summary>
    procedure BuildToolRows;
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
  Switch('designer.spatialNavigation',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSpatialNavigation));
  Switch('designer.spatialNavigation.crossContainers',
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.SettingsDesignerSpatialCross));
  BuildViewRows;
  BuildArrangeRows;
  BuildToolRows;
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
end;

procedure TAtlasDesignerSettingsSection.BuildToolRows;
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
