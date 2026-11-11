unit Atlas.UI.Designer.SettingsSection;

// Abschnitt „Editor“ des Moduls Designer im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher im Teil
// „Editor“ von Base): Modulschalter und Designer-Leiste im Formular-Designer (#1442), Gleiche auswählen (#738),
// Befehle im Menü „Anordnen“ (#730 ff.), fast bündige Kanten (#746), Standardgrößen (#747), Ebenen (#749), Format-Pinsel (#726), Anchors vorschlagen (#727), Texte des Formulars (#728), Label und Feld (#729), Formularraster (#731).

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
    /// <summary>Zeilen von Ebenen (#749), Format-Pinsel (#726), Anchors vorschlagen (#727), Texte des Formulars (#728) und Label und Feld (#729).</summary>
    procedure BuildToolRows;
    /// <summary>Zeilen von Label und Feld (#729) und Formularraster (#731).</summary>
    procedure BuildPairRows;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings;

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
  BuildArrangeRows;
  BuildToolRows;
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
end;

end.
