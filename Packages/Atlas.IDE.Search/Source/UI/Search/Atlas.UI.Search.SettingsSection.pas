unit Atlas.UI.Search.SettingsSection;

// Abschnitte des Moduls Suche im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher in den Teilen „Units
// suchen“ und „Allgemein“ von Base).
// - „Units suchen“: Modulschalter, Dialog „Units suchen“ (#777) und Suchleiste im Editor (#878, #893). Base behält
//   auf dieser Seite nur „Datei und Symbol schnell öffnen“.
// - „Allgemein“: Code-Abfragen (#1351).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasSearchUnitSearchSection = class(TAtlasSettingsSection)
  private
    procedure BuildUnitSearch;
    procedure BuildSearchBar;
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasSearchQuerySection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

const
  cSearchSettingsOwner = 'atlas.search';

implementation

uses
  Atlas.UI.Strings,
  Atlas.UI.Search.Strings;

{ TAtlasSearchUnitSearchSection }

function TAtlasSearchUnitSearchSection.OwnerId: string;
begin
  Result := cSearchSettingsOwner;
end;

function TAtlasSearchUnitSearchSection.AreaId: string;
begin
  Result := 'Units suchen';
end;

procedure TAtlasSearchUnitSearchSection.BuildRows;
begin
  ModuleSwitch('search.enabled');
  BuildUnitSearch;
  BuildSearchBar;
end;

procedure TAtlasSearchUnitSearchSection.BuildUnitSearch;
begin
  // Auswahllisten in der Reihenfolge der Werte der Einstellungen.
  Switch('unitSearch.enabled', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchEnabled));
  Switch('unitSearch.replaceIdeDialog', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchReplace));
  Switch('unitSearch.replaceUseUnitDialog', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchReplaceUseUnit));
  Switch('unitSearch.replaceFormsDialog', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchReplaceForms));
  Key('unitSearch.key', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchKey));
  Choice('unitSearch.pathStyle', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPathStyle),
    [TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPathRelative),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPathCompact),
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPathAbsolute)], ['relative', 'compact', 'absolute']);
  Choice('unitSearch.groupBy', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchGroupBy),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupProject),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupFolder),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupNone)], ['project', 'folder', 'none']);
  Switch('unitSearch.rememberCollapsed', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchRememberCollapsed));
  Switch('unitSearch.filters', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchFilters));
  Choice('unitSearch.defaultScope', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchDefaultScope),
    [TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginGroup),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginActive),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginSearchPath),
    TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginLibrary)], ['group', 'project', 'searchPath', 'library']);
  Switch('unitSearch.filterSyntax', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchFilterSyntax));
  Switch('unitSearch.formCaptions', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchFormCaptions));
  Switch('unitSearch.preview', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPreview));
  Switch('unitSearch.preview.form', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPreviewForm));
  Switch('unitSearch.preview.usedBy', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPreviewUsedBy));
  Switch('unitSearch.preview.autoCollapse',
    TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchPreviewAutoCollapse));
  Switch('unitSearch.multiSelect', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchMultiSelect));
  Switch('unitSearch.actions', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchActions));
  Switch('unitSearch.actions.addUses', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsUnitSearchAddUses));
end;

procedure TAtlasSearchUnitSearchSection.BuildSearchBar;
begin
  // Suchleiste im Editor (#878); Ersetzen, Regex, Verlauf und Bereiche über Dateien (#893).
  Title(TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchTitle));
  Switch('search.replaceIdeSearch', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchReplace));
  Switch('search.resultsInMessages', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchMessages));
  Switch('search.replace', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchReplaceBar));
  Switch('search.regex', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchRegex));
  Number('search.history', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchHistory));
  Switch('search.multiFile', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchMultiFile));
  Switch('search.fromFirstHit', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsSearchFromFirst));
end;

{ TAtlasSearchQuerySection }

function TAtlasSearchQuerySection.OwnerId: string;
begin
  Result := cSearchSettingsOwner;
end;

function TAtlasSearchQuerySection.AreaId: string;
begin
  Result := 'Allgemein';
end;

procedure TAtlasSearchQuerySection.BuildRows;
begin
  // Code-Abfragen (#1351): Fenster „Atlas-Abfrage“, Befehl und Menüeintrag; Unterpunkt über x-node.
  Switch('query.enabled', TAtlasSearchStrings.Text(TAtlasSearchTextId.SettingsQuery));
end;

end.
