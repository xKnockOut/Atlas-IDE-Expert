unit Atlas.UI.Designer.SettingsSection;

// Abschnitt „Editor“ des Moduls Designer im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher im Teil
// „Editor“ von Base): Modulschalter und Designer-Leiste im Formular-Designer (#1442), Gleiche auswählen (#738).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasDesignerSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.designer';
    cAreaId = 'Editor';
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
end;

end.
