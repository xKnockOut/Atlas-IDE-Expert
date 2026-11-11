unit Atlas.Core.Settings.Views.Tests;

// Tests der Einstellungen für Fenster, Leisten und Ansichten im Editor.

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Einstellungen der Fenster, Leisten und Ansichten im Editor.</summary>
  [TestFixture]
  TAtlasViewSettingsTests = class
  public
    /// <summary>#1101: Atlas-Editorleiste, Lage, Belegung, Rücksprung, Text, Tasten der Abschnittssprünge.</summary>
    [Test]
    procedure EditorToolbarOptions;
    /// <summary>#1155: Atlas-Statusleiste an, alle Elemente in Vorgabe-Reihenfolge; Bereinigen, Speichern, Laden.
    /// </summary>
    [Test]
    procedure EditorStatusBarOptions;
    /// <summary>#1122: Aufrufdiagramm standardmäßig an, abschaltbar, übersteht Speichern und Laden.</summary>
    [Test]
    procedure CallHierarchyDiagramOption;
    /// <summary>#1442: Designer-Leiste Vorgabe an; Speichern und Laden.</summary>
    [Test]
    procedure EditorDesignerBarOptions;
    /// <summary>Schnelle Lesezeichen (#1104): Vorgaben laut Issue, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure QuickBookmarkOptions;
    [Test]
    procedure UnitSearchOptions;
    [Test]
    procedure QuickOpenOptions;
    [Test]
    procedure NavHistoryOptions;
    [Test]
    procedure PeekOptions;
    [Test]
    procedure DataFlowOptions;
    /// <summary>Gliederungsfenster (#537): an, Quelltextreihenfolge, Cursor folgen; Speichern und Laden.</summary>
    [Test]
    procedure OutlineOptions;
    [Test]
    procedure BreadcrumbsOptions;
    [Test]
    procedure JumpToMatchOptions;
    [Test]
    procedure StickyScrollOptions;
    [Test]
    procedure MinimapOptions;
    /// <summary>Änderungsmarken und Zeilenhistorie (#507): Vorgaben, Tasten, Speichern und Laden.</summary>
    [Test]
    procedure GitChangeOptions;
    /// <summary>Atlas-Spalte in der Zeilenleiste (#768): Vorgaben, Unterschalter, Speichern und Laden.</summary>
    [Test]
    procedure GutterColumnOptions;
    /// <summary>Gleichen Text hervorheben (#709): Vorgaben, Grenzen, Speichern und Laden.</summary>
    [Test]
    procedure SelectionMatchesOptions;
    [Test]
    procedure ExpressionTypeOptions;
    /// <summary>Übersichtsleiste (#519): Vorgaben, Arten normalisiert, Speichern und Laden.</summary>
    [Test]
    procedure OverviewRulerOptions;
    /// <summary>Ausblenden am Element (#628): Blockende-Beschriftung und Taste, Vorgaben, Speichern und Laden.
    /// </summary>
    [Test]
    procedure HideElementOptions;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.Settings.StatusBarItems,
  Atlas.Core.Settings.TestSupport;

/// <summary>Ausblenden am Element: Werte von der Vorgabe abweichend setzen.</summary>
procedure SetHideElementOptions(var ASettings: TAtlasPluginSettings);
begin
  ASettings.BlockEndLabels := False;
  ASettings.BlockEndLabelsMinLines := 40;
  ASettings.DimUnusedUses := False;
  ASettings.RecursionMarkers := False;
  ASettings.RecursionMarkersDepth := 7;
  ASettings.ExitPoints := False;
  ASettings.ExitPointsExceptions := False;
  ASettings.ExitPointsLoops := False;
  ASettings.ExitPointsBadge := False;
  ASettings.Reassigned := False;
  ASettings.ReassignedTargets := 'fields,locals';
  ASettings.ReassignedStyle := 'wavy';
  ASettings.ReassignedColor := '#00ff80';
  ASettings.ExpressionType := False;
  ASettings.ExpressionTypeConversions := False;
  ASettings.ExpressionTypeConstValue := False;
  ASettings.ExpressionTypeKey := $4054;
  ASettings.InlineDiagnostics := 'off';
  ASettings.ProblemsStatusCounter := False;
  ASettings.NextProblemKey := 0;
  ASettings.PreviousProblemKey := $6077;
  ASettings.HideElementKey := 0;
end;
/// <summary>Ausblenden am Element: gespeicherte Werte gelesen.</summary>
procedure AssertHideElementLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.BlockEndLabels, 'abschaltbar');
  Assert.AreEqual(40, ALoaded.BlockEndLabelsMinLines);
  Assert.IsFalse(ALoaded.DimUnusedUses, 'uses-Abblenden abschaltbar');
  Assert.IsFalse(ALoaded.RecursionMarkers, 'Rekursionssymbole abschaltbar (#623)');
  Assert.AreEqual(7, ALoaded.RecursionMarkersDepth);
  Assert.IsFalse(ALoaded.ExitPoints, 'Austrittspunkte abschaltbar (#698)');
  Assert.IsFalse(ALoaded.ExitPointsExceptions);
  Assert.IsFalse(ALoaded.ExitPointsLoops);
  Assert.IsFalse(ALoaded.ExitPointsBadge);
  Assert.IsFalse(ALoaded.Reassigned, 'Unterstreichung abschaltbar (#712)');
  Assert.AreEqual('locals,fields', ALoaded.ReassignedTargets, 'feste Reihenfolge');
  Assert.AreEqual('wavy', ALoaded.ReassignedStyle);
  Assert.AreEqual('#00FF80', ALoaded.ReassignedColor);
  Assert.IsFalse(ALoaded.ExpressionType, 'Typ des Ausdrucks abschaltbar (#689)');
  Assert.IsFalse(ALoaded.ExpressionTypeConversions);
  Assert.IsFalse(ALoaded.ExpressionTypeConstValue);
  Assert.AreEqual($4054, ALoaded.ExpressionTypeKey);
  Assert.AreEqual('off', ALoaded.InlineDiagnostics, 'Fehlertext abschaltbar');
  Assert.IsFalse(ALoaded.ProblemsStatusCounter, 'Zähler abschaltbar');
  Assert.AreEqual(0, ALoaded.NextProblemKey);
  Assert.AreEqual($6077, ALoaded.PreviousProblemKey);
  Assert.AreEqual(0, ALoaded.HideElementKey, '0 = keine Taste');
end;
procedure TAtlasViewSettingsTests.HideElementOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.BlockEndLabels, 'Blockende-Beschriftung standardmäßig an');
  Assert.AreEqual($40BE, Settings.HideElementKey, 'Strg+.');
  Settings.HideElementKey := -5;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.HideElementKey, 'negativ = keine Taste');
  Assert.AreEqual(25, TAtlasPluginSettings.Defaults.BlockEndLabelsMinLines, 'Mindestlänge (#620)');
  Assert.IsTrue(Settings.DimUnusedUses, 'ungenutzte uses standardmäßig abgeblendet (#621)');
  // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
  Assert.AreEqual('errors', Settings.InlineDiagnostics);
  Assert.IsTrue(Settings.ProblemsStatusCounter);
  Assert.AreEqual($C077, Settings.NextProblemKey);
  Assert.AreEqual($E077, Settings.PreviousProblemKey);
  Settings.InlineDiagnostics := 'ALL';
  Settings.Normalize;
  Assert.AreEqual('all', Settings.InlineDiagnostics, 'Schreibweise des Schemas');
  Settings.InlineDiagnostics := 'unsinn';
  Settings.Normalize;
  Assert.AreEqual('errors', Settings.InlineDiagnostics, 'Unbekanntes = Vorgabe');
  Settings.BlockEndLabelsMinLines := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinBlockEndLines, Settings.BlockEndLabelsMinLines, 'unten begrenzt');
  Settings.BlockEndLabelsMinLines := 5000;
  Settings.DebugInlineValuesPerLine := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinInlineValuesPerLine, Settings.DebugInlineValuesPerLine,
    'debug.inlineValuesPerLine unten begrenzt (#508)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxBlockEndLines, Settings.BlockEndLabelsMinLines, 'oben begrenzt');
  SetHideElementOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertHideElementLoaded(Loaded);
end;
/// <summary>Units suchen (#777): Werte von der Vorgabe abweichend setzen.</summary>
procedure SetUnitSearchOptions(var ASettings: TAtlasPluginSettings);
begin
  // Speichern und Laden.
  ASettings.UnitSearchEnabled := False;
  ASettings.UnitSearchReplaceIdeDialog := False;
  ASettings.UnitSearchReplaceUseUnitDialog := False;
  ASettings.UnitSearchReplaceFormsDialog := False;
  ASettings.UnitSearchRememberCollapsed := False;
  ASettings.UnitSearchFilters := False;
  ASettings.UnitSearchFilterSyntax := False;
  ASettings.UnitSearchFormCaptions := False;
  ASettings.UnitSearchPreview := False;
  ASettings.UnitSearchPreviewForm := False;
  ASettings.UnitSearchPreviewUsedBy := False;
  ASettings.UnitSearchPreviewAutoCollapse := False;
  ASettings.UnitSearchMultiSelect := False;
  ASettings.UnitSearchActions := False;
  ASettings.UnitSearchActionsAddUses := False;
  ASettings.UnitSearchPathStyle := 'compact';
  ASettings.UnitSearchDefaultScope := 'library';
  ASettings.UnitSearchKey := $6055;
  // Suchleiste (#878): Liste in den Meldungen abschaltbar.
  ASettings.SearchResultsInMessages := False;
end;
/// <summary>Units suchen (#777): gespeicherte Werte gelesen.</summary>
procedure AssertUnitSearchLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.UnitSearchEnabled);
  Assert.IsFalse(ALoaded.UnitSearchReplaceIdeDialog);
  Assert.IsFalse(ALoaded.UnitSearchReplaceUseUnitDialog);
  Assert.IsFalse(ALoaded.UnitSearchReplaceFormsDialog);
  Assert.IsFalse(ALoaded.SearchResultsInMessages);
  Assert.IsFalse(ALoaded.UnitSearchRememberCollapsed);
  Assert.IsFalse(ALoaded.UnitSearchFilters);
  Assert.IsFalse(ALoaded.UnitSearchFilterSyntax);
  Assert.IsFalse(ALoaded.UnitSearchFormCaptions);
  Assert.IsFalse(ALoaded.UnitSearchPreview);
  Assert.IsFalse(ALoaded.UnitSearchPreviewForm);
  Assert.IsFalse(ALoaded.UnitSearchPreviewUsedBy);
  Assert.IsFalse(ALoaded.UnitSearchPreviewAutoCollapse);
  Assert.IsFalse(ALoaded.UnitSearchMultiSelect);
  Assert.IsFalse(ALoaded.UnitSearchActions);
  Assert.IsFalse(ALoaded.UnitSearchActionsAddUses);
  Assert.AreEqual('compact', ALoaded.UnitSearchPathStyle);
  Assert.AreEqual('folder', ALoaded.UnitSearchGroupBy);
  Assert.AreEqual('library', ALoaded.UnitSearchDefaultScope);
  Assert.AreEqual($6055, ALoaded.UnitSearchKey);
end;
procedure TAtlasViewSettingsTests.UnitSearchOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Units suchen (#777): alles an, Strg+F12 übernommen, Gruppen nach Projekt, Herkunft Projektgruppe.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.UnitSearchEnabled);
  Assert.IsTrue(Settings.UnitSearchReplaceIdeDialog, 'überschreibt Strg+F12 standardmäßig');
  Assert.IsTrue(Settings.UnitSearchReplaceUseUnitDialog, 'überschreibt Alt+F11 standardmäßig (#786)');
  Assert.IsTrue(Settings.UnitSearchReplaceFormsDialog, 'überschreibt Umschalt+F12 standardmäßig (#786)');
  Assert.IsTrue(Settings.UnitSearchRememberCollapsed);
  Assert.IsTrue(Settings.UnitSearchFilters);
  Assert.IsTrue(Settings.UnitSearchFilterSyntax);
  Assert.IsTrue(Settings.UnitSearchFormCaptions);
  Assert.IsTrue(Settings.UnitSearchPreview);
  Assert.IsTrue(Settings.UnitSearchPreviewForm);
  Assert.IsTrue(Settings.UnitSearchPreviewUsedBy);
  Assert.IsTrue(Settings.UnitSearchPreviewAutoCollapse);
  Assert.IsTrue(Settings.UnitSearchMultiSelect);
  Assert.IsTrue(Settings.UnitSearchActions);
  Assert.IsTrue(Settings.UnitSearchActionsAddUses);
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('project', Settings.UnitSearchGroupBy);
  Assert.AreEqual('group', Settings.UnitSearchDefaultScope);
  Assert.AreEqual(0, Settings.UnitSearchKey);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschrift wird vereinheitlicht.
  Settings.UnitSearchPathStyle := 'irgendwie';
  Settings.UnitSearchGroupBy := 'FOLDER';
  Settings.UnitSearchDefaultScope := 'searchpath';
  Settings.Normalize;
  Assert.AreEqual('relative', Settings.UnitSearchPathStyle);
  Assert.AreEqual('folder', Settings.UnitSearchGroupBy);
  Assert.AreEqual('searchPath', Settings.UnitSearchDefaultScope);
  SetUnitSearchOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  AssertUnitSearchLoaded(Loaded);
end;
procedure TAtlasViewSettingsTests.QuickOpenOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Schnell öffnen (#503): an, ohne RTL/VCL-Quellen, Strg+P.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.QuickOpen);
  Assert.IsFalse(Settings.QuickOpenLibrary);
  Assert.AreEqual($4050, Settings.QuickOpenKey);
  Settings.QuickOpenKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual($FFFF, Settings.QuickOpenKey);
  Settings.QuickOpen := False;
  Settings.QuickOpenLibrary := True;
  Settings.QuickOpenKey := $6050;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.QuickOpen);
  Assert.IsTrue(Loaded.QuickOpenLibrary);
  Assert.AreEqual($6050, Loaded.QuickOpenKey);
end;
procedure TAtlasViewSettingsTests.NavHistoryOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Navigationsverlauf (#504): an, Alt+Links, Alt+Rechts, Strg+Alt+Q.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.NavHistory);
  Assert.AreEqual($8025, Settings.NavBackKey);
  Assert.AreEqual($8027, Settings.NavForwardKey);
  Assert.AreEqual($C051, Settings.LastEditKey);
  Settings.NavHistory := False;
  Settings.NavBackKey := 0;
  Settings.NavForwardKey := $C027;
  Settings.LastEditKey := -5;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.LastEditKey);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.NavHistory);
  Assert.AreEqual(0, Loaded.NavBackKey);
  Assert.AreEqual($C027, Loaded.NavForwardKey);
  Assert.AreEqual(0, Loaded.LastEditKey);
end;
procedure TAtlasViewSettingsTests.PeekOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Definition einblenden (#505): an, 15 Zeilen, mit Implementierung, Alt+F12 und Umschalt+Alt+F12.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Peek);
  Assert.AreEqual(15, Settings.PeekHeightLines);
  Assert.IsTrue(Settings.PeekShowImplementation);
  Assert.AreEqual($807B, Settings.PeekDefinitionKey);
  Assert.AreEqual($A07B, Settings.PeekReferencesKey);
  Settings.PeekHeightLines := 2;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinPeekLines, Settings.PeekHeightLines);
  Settings.PeekHeightLines := 1000;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxPeekLines, Settings.PeekHeightLines);
  Settings.Peek := False;
  Settings.PeekHeightLines := 20;
  Settings.PeekShowImplementation := False;
  Settings.PeekDefinitionKey := 0;
  Settings.PeekReferencesKey := $C07B;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Peek);
  Assert.AreEqual(20, Loaded.PeekHeightLines);
  Assert.IsFalse(Loaded.PeekShowImplementation);
  Assert.AreEqual(0, Loaded.PeekDefinitionKey);
  Assert.AreEqual($C07B, Loaded.PeekReferencesKey);
end;
procedure TAtlasViewSettingsTests.DataFlowOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Datenfluss (#690): an, Tiefe 6, Tests sichtbar.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.DataFlow, 'navigation.dataFlow (#690)');
  Assert.AreEqual(6, Settings.DataFlowMaxDepth);
  Assert.IsFalse(Settings.DataFlowExcludeTests);
  Settings.DataFlowMaxDepth := 0;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinDataFlowDepth, Settings.DataFlowMaxDepth);
  Settings.DataFlowMaxDepth := 99;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxDataFlowDepth, Settings.DataFlowMaxDepth);
  Settings.DataFlow := False;
  Settings.DataFlowMaxDepth := 3;
  Settings.DataFlowExcludeTests := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := Default(TAtlasPluginSettings);
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.DataFlow);
  Assert.AreEqual(3, Loaded.DataFlowMaxDepth);
  Assert.IsTrue(Loaded.DataFlowExcludeTests);
end;
procedure TAtlasViewSettingsTests.OutlineOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Outline);
  Assert.IsFalse(Settings.OutlineAlphabetical);
  Assert.IsTrue(Settings.OutlineFollowCursor);
  Assert.IsTrue(Settings.OutlineConditions);
  Settings.Outline := False;
  Settings.OutlineAlphabetical := True;
  Settings.OutlineFollowCursor := False;
  Settings.OutlineConditions := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Outline);
  Assert.IsTrue(Loaded.OutlineAlphabetical);
  Assert.IsFalse(Loaded.OutlineFollowCursor);
  Assert.IsFalse(Loaded.OutlineConditions);
end;
procedure TAtlasViewSettingsTests.BreadcrumbsOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.Breadcrumbs);
  Assert.IsFalse(Settings.BreadcrumbsShowUnit);
  Assert.IsTrue(Settings.BreadcrumbsVisibility, 'Sichtbarkeitsabschnitt');
  Assert.IsTrue(Settings.BreadcrumbsMemberBlocks, 'Unterblock');
  Assert.IsTrue(Settings.BreadcrumbsVisibilityMark, 'Sichtbarkeitsmarke');
  Assert.IsTrue(Settings.BreadcrumbsDeclarationBlocks, 'Deklarationsblock');
  Assert.IsTrue(Settings.BreadcrumbsConditionals, 'Bedingungszweig');
  Assert.IsTrue(Settings.BreadcrumbsRegions, 'Region');
  Assert.IsFalse(Settings.BreadcrumbsStatements, 'Rahmen im Rumpf: Vorgabe aus');
  Assert.IsTrue(Settings.BreadcrumbsSectionCounts, 'Mitgliederzahl');
  Assert.IsTrue(Settings.BreadcrumbsSectionAppend, 'Neue Zeile am Ende von');
  Assert.IsTrue(Settings.BreadcrumbsSectionCreate, 'Abschnitt anlegen');
  Assert.AreEqual(0, Settings.SectionAppendKey, 'ohne Taste');
  Assert.IsTrue(Settings.BreadcrumbsContextMenu, 'Rechtsklick-Menü');
  Assert.IsTrue(Settings.BreadcrumbsOverloads, 'Überladungen');
  Assert.IsTrue(Settings.BreadcrumbsInterfaces, 'Interface-Marke');
  Assert.IsTrue(Settings.BreadcrumbsMetrics, 'Kennzahlen-Karte');
  Assert.IsTrue(Settings.MouseNavButtons, 'Maustasten');
  Assert.IsTrue(Settings.BreadcrumbsIdeColors, 'Farben der IDE');
  Assert.IsTrue(Settings.BreadcrumbsHideIdeToolbar, 'Navigationsleiste der IDE aus');
  Assert.AreEqual($60BE, Settings.BreadcrumbsKey, 'Strg+Umschalt+.');
  Settings.Breadcrumbs := False;
  Settings.BreadcrumbsShowUnit := True;
  Settings.BreadcrumbsVisibility := False;
  Settings.BreadcrumbsMemberBlocks := False;
  Settings.BreadcrumbsVisibilityMark := False;
  Settings.BreadcrumbsDeclarationBlocks := False;
  Settings.BreadcrumbsConditionals := False;
  Settings.BreadcrumbsRegions := False;
  Settings.BreadcrumbsStatements := True;
  Settings.BreadcrumbsSectionCounts := False;
  Settings.BreadcrumbsSectionAppend := False;
  Settings.BreadcrumbsSectionCreate := False;
  Settings.SectionAppendKey := $C04E;
  Settings.BreadcrumbsContextMenu := False;
  Settings.BreadcrumbsOverloads := False;
  Settings.BreadcrumbsInterfaces := False;
  Settings.BreadcrumbsMetrics := False;
  Settings.MouseNavButtons := False;
  Settings.BreadcrumbsIdeColors := False;
  Settings.BreadcrumbsHideIdeToolbar := False;
  Settings.BreadcrumbsKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.Breadcrumbs);
  Assert.IsTrue(Loaded.BreadcrumbsShowUnit);
  Assert.IsFalse(Loaded.BreadcrumbsVisibility);
  Assert.IsFalse(Loaded.BreadcrumbsMemberBlocks);
  Assert.IsFalse(Loaded.BreadcrumbsVisibilityMark);
  Assert.IsFalse(Loaded.BreadcrumbsDeclarationBlocks);
  Assert.IsFalse(Loaded.BreadcrumbsConditionals);
  Assert.IsFalse(Loaded.BreadcrumbsRegions);
  Assert.IsTrue(Loaded.BreadcrumbsStatements);
  Assert.IsFalse(Loaded.BreadcrumbsSectionCounts);
  Assert.IsFalse(Loaded.BreadcrumbsSectionAppend);
  Assert.IsFalse(Loaded.BreadcrumbsSectionCreate);
  Assert.AreEqual($C04E, Loaded.SectionAppendKey, 'Strg+Alt+N');
  Assert.IsFalse(Loaded.BreadcrumbsContextMenu);
  Assert.IsFalse(Loaded.BreadcrumbsOverloads);
  Assert.IsFalse(Loaded.BreadcrumbsInterfaces);
  Assert.IsFalse(Loaded.BreadcrumbsMetrics);
  Assert.IsFalse(Loaded.MouseNavButtons);
  Assert.IsFalse(Loaded.BreadcrumbsIdeColors);
  Assert.IsFalse(Loaded.BreadcrumbsHideIdeToolbar);
  Assert.AreEqual(0, Loaded.BreadcrumbsKey);
  Loaded.BreadcrumbsKey := -5;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.BreadcrumbsKey);
end;
procedure TAtlasViewSettingsTests.JumpToMatchOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.JumpToMatch);
  Assert.AreEqual($40BA, Settings.JumpToMatchKey, 'Strg+Ü');
  Assert.AreEqual($60BA, Settings.JumpToMatchSelectKey, 'Strg+Umschalt+Ü');
  Settings.JumpToMatch := False;
  Settings.JumpToMatchKey := $4042;
  Settings.JumpToMatchSelectKey := 0;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.JumpToMatch);
  Assert.AreEqual($4042, Loaded.JumpToMatchKey);
  Assert.AreEqual(0, Loaded.JumpToMatchSelectKey);
  Loaded.JumpToMatchKey := $1FFFF;
  Loaded.Normalize;
  Assert.AreEqual($FFFF, Loaded.JumpToMatchKey);
end;
procedure TAtlasViewSettingsTests.StickyScrollOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #506: nicht mehr experimentell, also an; drei Zeilen; Grenzen 1 bis 10.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.StickyScroll);
  Assert.AreEqual(3, Settings.StickyScrollMaxLines);
  Settings.StickyScroll := True;
  Settings.StickyScrollMaxLines := 5;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.StickyScroll);
  Assert.AreEqual(5, Loaded.StickyScrollMaxLines);
  Loaded.StickyScrollMaxLines := 0;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinStickyLines, Loaded.StickyScrollMaxLines);
  Loaded.StickyScrollMaxLines := 99;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxStickyLines, Loaded.StickyScrollMaxLines);
  // #1230: if/else-Blöcke an, ab 25 Zeilen; Grenzen 5 bis 1000.
  Assert.IsTrue(Settings.StickyScrollBlocks);
  Assert.AreEqual(25, Settings.StickyScrollBlockMinLines);
  Settings.StickyScrollBlocks := False;
  Settings.StickyScrollBlockMinLines := 40;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.StickyScrollBlocks);
  Assert.AreEqual(40, Loaded.StickyScrollBlockMinLines);
  Loaded.StickyScrollBlockMinLines := 1;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinStickyBlockLines, Loaded.StickyScrollBlockMinLines);
  // Was der Kopf zeigt: Typen und Routinen an, weitere Anweisungsblöcke aus; jede Art einzeln gespeichert.
  Assert.IsTrue(Settings.StickyScrollTypes and Settings.StickyScrollRoutines);
  Assert.IsFalse(Settings.StickyScrollLoops or Settings.StickyScrollTry or Settings.StickyScrollCase or
    Settings.StickyScrollWith);
  Settings.StickyScrollTypes := False;
  Settings.StickyScrollLoops := True;
  Settings.StickyScrollCase := True;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.StickyScrollTypes);
  Assert.IsTrue(Loaded.StickyScrollRoutines);
  Assert.IsTrue(Loaded.StickyScrollLoops);
  Assert.IsFalse(Loaded.StickyScrollTry);
  Assert.IsTrue(Loaded.StickyScrollCase);
  Assert.IsFalse(Loaded.StickyScrollWith);
end;
procedure TAtlasViewSettingsTests.MinimapOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // #873: experimentell, also aus; Vorgaben laut Issue; Speichern, Laden, Klemmen.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.Minimap);
  Assert.AreEqual('characters', Settings.MinimapRender);
  Assert.AreEqual(120, Settings.MinimapWidth);
  Assert.AreEqual(2, Settings.MinimapScale);
  Assert.AreEqual(120, Settings.MinimapMaxColumn);
  Assert.AreEqual('right', Settings.MinimapSide);
  Assert.AreEqual('always', Settings.MinimapShowSlider);
  Assert.IsTrue(Settings.MinimapSectionHeaders and Settings.MinimapHighlightMethod and Settings.MinimapMarkers and
    Settings.MinimapClickJumps);
  Assert.IsFalse(Settings.MinimapNoticeShown);
  Settings.Minimap := True;
  Settings.MinimapRender := 'blocks';
  Settings.MinimapWidth := 90;
  Settings.MinimapScale := 3;
  Settings.MinimapMaxColumn := 80;
  Settings.MinimapSide := 'left';
  Settings.MinimapShowSlider := 'mouseover';
  Settings.MinimapSectionHeaders := False;
  Settings.MinimapHighlightMethod := False;
  Settings.MinimapMarkers := False;
  Settings.MinimapClickJumps := False;
  Settings.MinimapNoticeShown := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsTrue(Loaded.Minimap);
  Assert.AreEqual('blocks', Loaded.MinimapRender);
  Assert.AreEqual(90, Loaded.MinimapWidth);
  Assert.AreEqual(3, Loaded.MinimapScale);
  Assert.AreEqual(80, Loaded.MinimapMaxColumn);
  Assert.AreEqual('left', Loaded.MinimapSide);
  Assert.AreEqual('mouseover', Loaded.MinimapShowSlider);
  Assert.IsFalse(Loaded.MinimapSectionHeaders or Loaded.MinimapHighlightMethod or Loaded.MinimapMarkers or
    Loaded.MinimapClickJumps);
  Assert.IsTrue(Loaded.MinimapNoticeShown);
  Loaded.MinimapRender := 'pixel';
  Loaded.MinimapSide := 'oben';
  Loaded.MinimapShowSlider := '';
  Loaded.MinimapWidth := 1;
  Loaded.MinimapScale := 9;
  Loaded.MinimapMaxColumn := 100000;
  Loaded.Normalize;
  Assert.AreEqual('characters', Loaded.MinimapRender);
  Assert.AreEqual('right', Loaded.MinimapSide);
  Assert.AreEqual('always', Loaded.MinimapShowSlider);
  Assert.AreEqual(TAtlasPluginSettings.cMinMinimapWidth, Loaded.MinimapWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMinimapScale, Loaded.MinimapScale);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMinimapColumn, Loaded.MinimapMaxColumn);
end;
procedure TAtlasViewSettingsTests.GutterColumnOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und Unterschalter standardmäßig an, je einzeln aus.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GutterColumn);
  Assert.IsTrue(Settings.GutterColumnProblems);
  Assert.IsTrue(Settings.GutterColumnCodeActions);
  Assert.IsTrue(Settings.GutterColumnOverrides);
  Settings.GutterColumn := False;
  Settings.GutterColumnCodeActions := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GutterColumn);
  Assert.IsTrue(Loaded.GutterColumnProblems);
  Assert.IsFalse(Loaded.GutterColumnCodeActions);
  Assert.IsTrue(Loaded.GutterColumnOverrides);
  Loaded.GutterColumnOverrides := False;
  Loaded.Save(Store);
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Load(Store);
  Assert.IsFalse(Settings.GutterColumnOverrides);
end;
procedure TAtlasViewSettingsTests.SelectionMatchesOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.SelectionMatches);
  Assert.AreEqual(3, Settings.SelectionMatchesMinLength);
  Assert.IsFalse(Settings.SelectionMatchesCaseSensitive);
  Assert.IsFalse(Settings.SelectionMatchesWholeWord);
  Assert.IsTrue(Settings.SelectionMatchesNavigateF3);
  Assert.AreEqual(1000, Settings.SelectionMatchesMaxMatches);
  Settings.SelectionMatches := False;
  Settings.SelectionMatchesMinLength := 5;
  Settings.SelectionMatchesCaseSensitive := True;
  Settings.SelectionMatchesWholeWord := True;
  Settings.SelectionMatchesNavigateF3 := False;
  Settings.SelectionMatchesMaxMatches := 250;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.SelectionMatches);
  Assert.AreEqual(5, Loaded.SelectionMatchesMinLength);
  Assert.IsTrue(Loaded.SelectionMatchesCaseSensitive);
  Assert.IsTrue(Loaded.SelectionMatchesWholeWord);
  Assert.IsFalse(Loaded.SelectionMatchesNavigateF3);
  Assert.AreEqual(250, Loaded.SelectionMatchesMaxMatches);
  // Grenzen: Mindestlänge 1 bis 100, Treffer 1 bis 100000.
  Loaded.SelectionMatchesMinLength := 0;
  Loaded.SelectionMatchesMaxMatches := 0;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinSelectionMatchLength, Loaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.cMinSelectionMatches, Loaded.SelectionMatchesMaxMatches);
  Loaded.SelectionMatchesMinLength := 500;
  Loaded.SelectionMatchesMaxMatches := 5000000;
  Loaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxSelectionMatchLength, Loaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.cMaxSelectionMatches, Loaded.SelectionMatchesMaxMatches);
end;
procedure TAtlasViewSettingsTests.ExpressionTypeOptions;
var
  Settings: TAtlasPluginSettings;
begin
  // Typ des markierten Ausdrucks (#689): an, mit Umwandlungen und Wert, Strg+Umschalt+T.
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.ExpressionType);
  Assert.IsTrue(Settings.ExpressionTypeConversions);
  Assert.IsTrue(Settings.ExpressionTypeConstValue);
  Assert.AreEqual($6054, Settings.ExpressionTypeKey, 'Strg+Umschalt+T');
  Settings.ExpressionTypeKey := $1FFFF;
  Settings.Normalize;
  Assert.AreEqual($FFFF, Settings.ExpressionTypeKey);
  Settings.ExpressionTypeKey := -3;
  Settings.Normalize;
  Assert.AreEqual(0, Settings.ExpressionTypeKey);
end;
procedure TAtlasViewSettingsTests.GitChangeOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.GitGutter);
  Assert.IsFalse(Settings.GitBlame, 'blame nur auf Wunsch');
  Assert.AreEqual($C022, Settings.NextChangeKey, 'Strg+Alt+Bild↓');
  Assert.AreEqual($C021, Settings.PreviousChangeKey, 'Strg+Alt+Bild↑');
  Settings.GitGutter := False;
  Settings.GitBlame := True;
  Settings.NextChangeKey := 0;
  Settings.PreviousChangeKey := $4074;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.GitGutter);
  Assert.IsTrue(Loaded.GitBlame);
  Assert.AreEqual(0, Loaded.NextChangeKey);
  Assert.AreEqual($4074, Loaded.PreviousChangeKey);
  Loaded.NextChangeKey := -1;
  Loaded.PreviousChangeKey := $20000;
  Loaded.Normalize;
  Assert.AreEqual(0, Loaded.NextChangeKey);
  Assert.AreEqual($FFFF, Loaded.PreviousChangeKey);
end;
procedure TAtlasViewSettingsTests.OverviewRulerOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.OverviewRuler);
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor', Settings.OverviewRulerKinds);
  Settings.OverviewRuler := False;
  Settings.OverviewRulerKinds := 'changes,diagnostics';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.OverviewRuler);
  Loaded.Normalize;
  Assert.AreEqual('diagnostics,changes', Loaded.OverviewRulerKinds, 'feste Reihenfolge');
  Loaded.OverviewRulerKinds := 'gibtsnicht, cursor';
  Loaded.Normalize;
  Assert.AreEqual('cursor', Loaded.OverviewRulerKinds);
  Loaded.OverviewRulerKinds := '';
  Loaded.Normalize;
  Assert.AreEqual('', Loaded.OverviewRulerKinds, 'leer = keine Marken');
end;
procedure TAtlasViewSettingsTests.CallHierarchyDiagramOption;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.CallHierarchyDiagram, 'Aufrufdiagramm standardmäßig an');
  Settings.CallHierarchyDiagram := False;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Assert.AreEqual(0, Store.ReadInteger('CallHierarchyDiagram', 1));
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.CallHierarchyDiagram);
end;
procedure TAtlasViewSettingsTests.EditorToolbarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorToolbar);
  Assert.AreEqual('belowBreadcrumbs', Settings.EditorToolbarPosition);
  Assert.AreEqual(TAtlasToolbarItems.DefaultText, Settings.EditorToolbarItems);
  Assert.IsTrue(Settings.EditorToolbarReturnButton);
  Assert.IsFalse(Settings.EditorToolbarLabels);
  Assert.AreEqual(0, Settings.GotoInterfaceKey, 'keine Taste');
  Assert.AreEqual(0, Settings.GotoImplementationKey, 'keine Taste');
  Settings.EditorToolbarPosition := 'INBREADCRUMBS';
  Settings.EditorToolbarItems := '|, Atlas.GotoInterface ,|,|,Atlas.NavBack,Atlas.navback,|';
  Settings.GotoInterfaceKey := $1FFFF;
  Settings.GotoImplementationKey := -3;
  Settings.Normalize;
  Assert.AreEqual('inBreadcrumbs', Settings.EditorToolbarPosition);
  Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack', Settings.EditorToolbarItems);
  Assert.AreEqual($FFFF, Settings.GotoInterfaceKey);
  Assert.AreEqual(0, Settings.GotoImplementationKey);
  Settings.EditorToolbarPosition := 'oben';
  Settings.Normalize;
  Assert.AreEqual('belowBreadcrumbs', Settings.EditorToolbarPosition, 'Unbekanntes = Vorgabe');
  Settings.EditorToolbar := False;
  Settings.EditorToolbarPosition := 'aboveBreadcrumbs';
  Settings.EditorToolbarItems := '';
  Settings.EditorToolbarReturnButton := False;
  Settings.EditorToolbarLabels := True;
  Settings.GotoInterfaceKey := $6049;
  Settings.GotoImplementationKey := $604D;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorToolbar);
  Assert.AreEqual('aboveBreadcrumbs', Loaded.EditorToolbarPosition);
  Assert.AreEqual('', Loaded.EditorToolbarItems, 'alle Knöpfe entfernt bleibt leer');
  Assert.IsFalse(Loaded.EditorToolbarReturnButton);
  Assert.IsTrue(Loaded.EditorToolbarLabels);
  Assert.AreEqual($6049, Loaded.GotoInterfaceKey);
  Assert.AreEqual($604D, Loaded.GotoImplementationKey);
end;
procedure TAtlasViewSettingsTests.EditorStatusBarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorStatusBar);
  Assert.AreEqual('status,findings,liveCheck,method', Settings.EditorStatusBarItems);
  Assert.AreEqual(TAtlasStatusBarItems.DefaultText, Settings.EditorStatusBarItems);
  Settings.EditorStatusBarItems := ' METHOD, zahnrad ,status,method';
  Settings.Normalize;
  Assert.AreEqual('method,status', Settings.EditorStatusBarItems, 'nur bekannte, jedes einmal');
  Settings.EditorStatusBar := False;
  Settings.EditorStatusBarItems := '';
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorStatusBar);
  Assert.AreEqual('', Loaded.EditorStatusBarItems, 'alle Elemente aus bleibt leer');
end;
procedure TAtlasViewSettingsTests.EditorDesignerBarOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.EditorDesignerBar);
  Assert.AreEqual(32988, Settings.DesignerSearchKey, 'Alt+^');
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchWindow, Settings.DesignerSearchStyle, 'großes Fenster');
  Assert.IsTrue(Settings.DesignerTabOrderClick, 'Neuvergeben an (#603)');
  Assert.IsFalse(Settings.DesignerTabOrderOverlay, 'Marken nur auf Knopfdruck');
  Assert.IsFalse(Settings.DesignerTabOrderPaths);
  Assert.IsFalse(Settings.DesignerAlign, 'experimentell: aus');
  Settings.EditorDesignerBar := False;
  Settings.DesignerSearchKey := 0;
  Settings.DesignerSearchStyle := TAtlasPluginSettings.cDesignerSearchPopup;
  Settings.DesignerTabOrderClick := False;
  Settings.DesignerTabOrderOverlay := True;
  Settings.DesignerTabOrderPaths := True;
  Settings.DesignerAlign := True;
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  Assert.IsFalse(Loaded.EditorDesignerBar);
  Assert.AreEqual(0, Loaded.DesignerSearchKey, 'keine Taste');
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchPopup, Loaded.DesignerSearchStyle);
  Assert.IsFalse(Loaded.DesignerTabOrderClick);
  Assert.IsTrue(Loaded.DesignerTabOrderOverlay);
  Assert.IsTrue(Loaded.DesignerTabOrderPaths);
  Assert.IsTrue(Loaded.DesignerAlign);
  Store.WriteString('DesignerSearchStyle', 'riesig');
  Loaded.Load(Store);
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchWindow, Loaded.DesignerSearchStyle, 'Unbekanntes: Vorgabe');
end;
/// <summary>Schnelle Lesezeichen (#1104): Werte von der Vorgabe abweichend setzen.</summary>
procedure SetQuickBookmarkOptions(var ASettings: TAtlasPluginSettings);
begin
  ASettings.QuickBookmarks := False;
  ASettings.QuickBookmarksGutter := False;
  ASettings.QuickBookmarksGutterClick := False;
  ASettings.QuickBookmarksNumberedKeys := False;
  ASettings.QuickBookmarkKey := $604C;
  ASettings.QuickBookmarkKeyPriority := False;
  ASettings.QuickBookmarkChordWait := 500;
  ASettings.QuickBookmarkSetKey := $C031;
  ASettings.QuickBookmarkSetKeyPriority := False;
  ASettings.QuickBookmarkJumpKey := $8031;
  ASettings.QuickBookmarkJumpKeyPriority := False;
  ASettings.QuickBookmarksScope := 'file';
  ASettings.QuickBookmarksImportIde := False;
  ASettings.NextBookmarkKey := $4071;
  ASettings.PreviousBookmarkKey := $6071;
end;
/// <summary>Schnelle Lesezeichen (#1104): gespeicherte Werte gelesen.</summary>
procedure AssertQuickBookmarkLoaded(const ALoaded: TAtlasPluginSettings);
begin
  Assert.IsFalse(ALoaded.QuickBookmarks);
  Assert.IsFalse(ALoaded.QuickBookmarksGutter);
  Assert.IsFalse(ALoaded.QuickBookmarksGutterClick);
  Assert.IsFalse(ALoaded.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604C, ALoaded.QuickBookmarkKey);
  Assert.IsFalse(ALoaded.QuickBookmarkKeyPriority);
  Assert.AreEqual(500, ALoaded.QuickBookmarkChordWait);
  Assert.AreEqual($C031, ALoaded.QuickBookmarkSetKey);
  Assert.IsFalse(ALoaded.QuickBookmarkSetKeyPriority);
  Assert.AreEqual($8031, ALoaded.QuickBookmarkJumpKey);
  Assert.IsFalse(ALoaded.QuickBookmarkJumpKeyPriority);
  Assert.AreEqual('file', ALoaded.QuickBookmarksScope);
  Assert.IsFalse(ALoaded.QuickBookmarksImportIde);
  Assert.AreEqual($4071, ALoaded.NextBookmarkKey);
  Assert.AreEqual($6071, ALoaded.PreviousBookmarkKey);
end;
procedure TAtlasViewSettingsTests.QuickBookmarkOptions;
var
  Settings, Loaded: TAtlasPluginSettings;
  Store: IAtlasSettingsStore;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(Settings.QuickBookmarks);
  Assert.IsTrue(Settings.QuickBookmarksGutter);
  Assert.IsTrue(Settings.QuickBookmarksGutterClick);
  Assert.IsTrue(Settings.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604B, Settings.QuickBookmarkKey, 'Strg+Umschalt+K');
  Assert.IsTrue(Settings.QuickBookmarkKeyPriority);
  Assert.AreEqual(800, Settings.QuickBookmarkChordWait);
  Assert.AreEqual($6031, Settings.QuickBookmarkSetKey, 'Strg+Umschalt+1');
  Assert.AreEqual($4031, Settings.QuickBookmarkJumpKey, 'Strg+1');
  Assert.AreEqual('project', Settings.QuickBookmarksScope);
  Assert.IsTrue(Settings.QuickBookmarksImportIde);
  Assert.AreEqual(0, Settings.NextBookmarkKey, 'ohne voreingestellte Taste');
  Assert.AreEqual(0, Settings.PreviousBookmarkKey);
  Settings.QuickBookmarkChordWait := 99999;
  Settings.QuickBookmarksScope := 'FILE';
  Settings.QuickBookmarkKey := -1;
  Settings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxQuickChordWait, Settings.QuickBookmarkChordWait);
  Assert.AreEqual('file', Settings.QuickBookmarksScope);
  Assert.AreEqual(0, Settings.QuickBookmarkKey);
  Settings.QuickBookmarksScope := 'irgendwo';
  Settings.QuickBookmarkChordWait := -5;
  Settings.Normalize;
  Assert.AreEqual('project', Settings.QuickBookmarksScope);
  Assert.AreEqual(0, Settings.QuickBookmarkChordWait);
  SetQuickBookmarkOptions(Settings);
  Store := TMemoryStore.Create;
  Settings.Save(Store);
  Loaded := TAtlasPluginSettings.Defaults;
  Loaded.Load(Store);
  AssertQuickBookmarkLoaded(Loaded);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasViewSettingsTests);

end.
