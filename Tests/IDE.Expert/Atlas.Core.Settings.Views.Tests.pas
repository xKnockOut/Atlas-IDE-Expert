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
    [Test]
    procedure DesignerLayoutOptions;
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
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.BlockEndLabels, 'Blockende-Beschriftung standardmäßig an');
  Assert.AreEqual($40BE, mSettings.HideElementKey, 'Strg+.');
  mSettings.HideElementKey := -5;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.HideElementKey, 'negativ = keine Taste');
  Assert.AreEqual(25, TAtlasPluginSettings.Defaults.BlockEndLabelsMinLines, 'Mindestlänge (#620)');
  Assert.IsTrue(mSettings.DimUnusedUses, 'ungenutzte uses standardmäßig abgeblendet (#621)');
  // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
  Assert.AreEqual('errors', mSettings.InlineDiagnostics);
  Assert.IsTrue(mSettings.ProblemsStatusCounter);
  Assert.AreEqual($C077, mSettings.NextProblemKey);
  Assert.AreEqual($E077, mSettings.PreviousProblemKey);
  mSettings.InlineDiagnostics := 'ALL';
  mSettings.Normalize;
  Assert.AreEqual('all', mSettings.InlineDiagnostics, 'Schreibweise des Schemas');
  mSettings.InlineDiagnostics := 'unsinn';
  mSettings.Normalize;
  Assert.AreEqual('errors', mSettings.InlineDiagnostics, 'Unbekanntes = Vorgabe');
  mSettings.BlockEndLabelsMinLines := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinBlockEndLines, mSettings.BlockEndLabelsMinLines, 'unten begrenzt');
  mSettings.BlockEndLabelsMinLines := 5000;
  mSettings.DebugInlineValuesPerLine := 0;
  mSettings.DebugWhyHereDepth := 99;
  mSettings.DebugVariablesSearchDepth := 0;
  mSettings.DebugVariablesSearchLimit := 1000000;
  mSettings.DebugPredictLines := 0;
  mSettings.DebugHoverMaxChildren := 5000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinInlineValuesPerLine, mSettings.DebugInlineValuesPerLine,
    'debug.inlineValuesPerLine unten begrenzt (#508)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxWhyHereDepth, mSettings.DebugWhyHereDepth,
    'debug.whyHere.depth oben begrenzt (#1878)');
  Assert.AreEqual(TAtlasPluginSettings.cMinVariablesSearchDepth, mSettings.DebugVariablesSearchDepth,
    'debug.variablesWindow.searchDepth unten begrenzt (#853)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxVariablesSearchLimit, mSettings.DebugVariablesSearchLimit,
    'debug.variablesWindow.searchLimit oben begrenzt (#853)');
  Assert.AreEqual(TAtlasPluginSettings.cMinPredictLines, mSettings.DebugPredictLines,
    'debug.predictConditions.lines unten begrenzt (#2169)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxHoverMaxChildren, mSettings.DebugHoverMaxChildren,
    'debug.hoverMaxChildren oben begrenzt (#895)');
  mSettings.DebugMemoryTimelineIntervalMs := 60000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxMemoryTimelineIntervalMs, mSettings.DebugMemoryTimelineIntervalMs,
    'debug.memoryTimeline.intervalMs oben begrenzt (#858)');
  mSettings.DebugProfilerIntervalMs := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinProfilerIntervalMs, mSettings.DebugProfilerIntervalMs,
    'debug.profiler.intervalMs unten begrenzt (#2057)');
  Assert.AreEqual(TAtlasPluginSettings.cMaxBlockEndLines, mSettings.BlockEndLabelsMinLines, 'oben begrenzt');
  SetHideElementOptions(mSettings);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  AssertHideElementLoaded(mLoaded);
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
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Units suchen (#777): alles an, Strg+F12 übernommen, Gruppen nach Projekt, Herkunft Projektgruppe.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.UnitSearchEnabled);
  Assert.IsTrue(mSettings.UnitSearchReplaceIdeDialog, 'überschreibt Strg+F12 standardmäßig');
  Assert.IsTrue(mSettings.UnitSearchReplaceUseUnitDialog, 'überschreibt Alt+F11 standardmäßig (#786)');
  Assert.IsTrue(mSettings.UnitSearchReplaceFormsDialog, 'überschreibt Umschalt+F12 standardmäßig (#786)');
  Assert.IsTrue(mSettings.UnitSearchRememberCollapsed);
  Assert.IsTrue(mSettings.UnitSearchFilters);
  Assert.IsTrue(mSettings.UnitSearchFilterSyntax);
  Assert.IsTrue(mSettings.UnitSearchFormCaptions);
  Assert.IsTrue(mSettings.UnitSearchPreview);
  Assert.IsTrue(mSettings.UnitSearchPreviewForm);
  Assert.IsTrue(mSettings.UnitSearchPreviewUsedBy);
  Assert.IsTrue(mSettings.UnitSearchPreviewAutoCollapse);
  Assert.IsTrue(mSettings.UnitSearchMultiSelect);
  Assert.IsTrue(mSettings.UnitSearchActions);
  Assert.IsTrue(mSettings.UnitSearchActionsAddUses);
  Assert.AreEqual('relative', mSettings.UnitSearchPathStyle);
  Assert.AreEqual('project', mSettings.UnitSearchGroupBy);
  Assert.AreEqual('group', mSettings.UnitSearchDefaultScope);
  Assert.AreEqual(0, mSettings.UnitSearchKey);
  // Unbekannte Werte fallen auf die Vorgabe zurück, Groß-/Kleinschrift wird vereinheitlicht.
  mSettings.UnitSearchPathStyle := 'irgendwie';
  mSettings.UnitSearchGroupBy := 'FOLDER';
  mSettings.UnitSearchDefaultScope := 'searchpath';
  mSettings.Normalize;
  Assert.AreEqual('relative', mSettings.UnitSearchPathStyle);
  Assert.AreEqual('folder', mSettings.UnitSearchGroupBy);
  Assert.AreEqual('searchPath', mSettings.UnitSearchDefaultScope);
  SetUnitSearchOptions(mSettings);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  AssertUnitSearchLoaded(mLoaded);
end;
procedure TAtlasViewSettingsTests.QuickOpenOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Schnell öffnen (#503): an, ohne RTL/VCL-Quellen, Strg+P.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.QuickOpen);
  Assert.IsFalse(mSettings.QuickOpenLibrary);
  Assert.AreEqual($4050, mSettings.QuickOpenKey);
  mSettings.QuickOpenKey := $1FFFF;
  mSettings.Normalize;
  Assert.AreEqual($FFFF, mSettings.QuickOpenKey);
  mSettings.QuickOpen := False;
  mSettings.QuickOpenLibrary := True;
  mSettings.QuickOpenKey := $6050;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.QuickOpen);
  Assert.IsTrue(mLoaded.QuickOpenLibrary);
  Assert.AreEqual($6050, mLoaded.QuickOpenKey);
end;
procedure TAtlasViewSettingsTests.NavHistoryOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Navigationsverlauf (#504): an, Alt+Links, Alt+Rechts, Strg+Alt+Q.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.NavHistory);
  Assert.AreEqual($8025, mSettings.NavBackKey);
  Assert.AreEqual($8027, mSettings.NavForwardKey);
  Assert.AreEqual($C051, mSettings.LastEditKey);
  mSettings.NavHistory := False;
  mSettings.NavBackKey := 0;
  mSettings.NavForwardKey := $C027;
  mSettings.LastEditKey := -5;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.LastEditKey);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.NavHistory);
  Assert.AreEqual(0, mLoaded.NavBackKey);
  Assert.AreEqual($C027, mLoaded.NavForwardKey);
  Assert.AreEqual(0, mLoaded.LastEditKey);
end;
procedure TAtlasViewSettingsTests.PeekOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Definition einblenden (#505): an, 15 Zeilen, mit Implementierung, Alt+F12 und Umschalt+Alt+F12.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Peek);
  Assert.AreEqual(15, mSettings.PeekHeightLines);
  Assert.IsTrue(mSettings.PeekShowImplementation);
  Assert.AreEqual($807B, mSettings.PeekDefinitionKey);
  Assert.AreEqual($A07B, mSettings.PeekReferencesKey);
  mSettings.PeekHeightLines := 2;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinPeekLines, mSettings.PeekHeightLines);
  mSettings.PeekHeightLines := 1000;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxPeekLines, mSettings.PeekHeightLines);
  mSettings.Peek := False;
  mSettings.PeekHeightLines := 20;
  mSettings.PeekShowImplementation := False;
  mSettings.PeekDefinitionKey := 0;
  mSettings.PeekReferencesKey := $C07B;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.Peek);
  Assert.AreEqual(20, mLoaded.PeekHeightLines);
  Assert.IsFalse(mLoaded.PeekShowImplementation);
  Assert.AreEqual(0, mLoaded.PeekDefinitionKey);
  Assert.AreEqual($C07B, mLoaded.PeekReferencesKey);
end;
procedure TAtlasViewSettingsTests.DataFlowOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Datenfluss (#690): an, Tiefe 6, Tests sichtbar.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.DataFlow, 'navigation.dataFlow (#690)');
  Assert.AreEqual(6, mSettings.DataFlowMaxDepth);
  Assert.IsFalse(mSettings.DataFlowExcludeTests);
  mSettings.DataFlowMaxDepth := 0;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinDataFlowDepth, mSettings.DataFlowMaxDepth);
  mSettings.DataFlowMaxDepth := 99;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxDataFlowDepth, mSettings.DataFlowMaxDepth);
  mSettings.DataFlow := False;
  mSettings.DataFlowMaxDepth := 3;
  mSettings.DataFlowExcludeTests := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := Default(TAtlasPluginSettings);
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.DataFlow);
  Assert.AreEqual(3, mLoaded.DataFlowMaxDepth);
  Assert.IsTrue(mLoaded.DataFlowExcludeTests);
end;
procedure TAtlasViewSettingsTests.OutlineOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Outline);
  Assert.IsFalse(mSettings.OutlineAlphabetical);
  Assert.IsTrue(mSettings.OutlineFollowCursor);
  Assert.IsTrue(mSettings.OutlineConditions);
  mSettings.Outline := False;
  mSettings.OutlineAlphabetical := True;
  mSettings.OutlineFollowCursor := False;
  mSettings.OutlineConditions := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.Outline);
  Assert.IsTrue(mLoaded.OutlineAlphabetical);
  Assert.IsFalse(mLoaded.OutlineFollowCursor);
  Assert.IsFalse(mLoaded.OutlineConditions);
end;
procedure TAtlasViewSettingsTests.BreadcrumbsOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.Breadcrumbs);
  Assert.IsFalse(mSettings.BreadcrumbsShowUnit);
  Assert.IsTrue(mSettings.BreadcrumbsVisibility, 'Sichtbarkeitsabschnitt');
  Assert.IsTrue(mSettings.BreadcrumbsMemberBlocks, 'Unterblock');
  Assert.IsTrue(mSettings.BreadcrumbsVisibilityMark, 'Sichtbarkeitsmarke');
  Assert.IsTrue(mSettings.BreadcrumbsDeclarationBlocks, 'Deklarationsblock');
  Assert.IsTrue(mSettings.BreadcrumbsConditionals, 'Bedingungszweig');
  Assert.IsTrue(mSettings.BreadcrumbsRegions, 'Region');
  Assert.IsFalse(mSettings.BreadcrumbsStatements, 'Rahmen im Rumpf: Vorgabe aus');
  Assert.IsTrue(mSettings.BreadcrumbsSectionCounts, 'Mitgliederzahl');
  Assert.IsTrue(mSettings.BreadcrumbsSectionAppend, 'Neue Zeile am Ende von');
  Assert.IsTrue(mSettings.BreadcrumbsSectionCreate, 'Abschnitt anlegen');
  Assert.AreEqual(0, mSettings.SectionAppendKey, 'ohne Taste');
  Assert.IsTrue(mSettings.BreadcrumbsContextMenu, 'Rechtsklick-Menü');
  Assert.IsTrue(mSettings.BreadcrumbsOverloads, 'Überladungen');
  Assert.IsTrue(mSettings.BreadcrumbsInterfaces, 'Interface-Marke');
  Assert.IsTrue(mSettings.BreadcrumbsMetrics, 'Kennzahlen-Karte');
  Assert.IsTrue(mSettings.MouseNavButtons, 'Maustasten');
  Assert.IsTrue(mSettings.BreadcrumbsIdeColors, 'Farben der IDE');
  Assert.IsTrue(mSettings.BreadcrumbsHideIdeToolbar, 'Navigationsleiste der IDE aus');
  Assert.AreEqual($60BE, mSettings.BreadcrumbsKey, 'Strg+Umschalt+.');
  mSettings.Breadcrumbs := False;
  mSettings.BreadcrumbsShowUnit := True;
  mSettings.BreadcrumbsVisibility := False;
  mSettings.BreadcrumbsMemberBlocks := False;
  mSettings.BreadcrumbsVisibilityMark := False;
  mSettings.BreadcrumbsDeclarationBlocks := False;
  mSettings.BreadcrumbsConditionals := False;
  mSettings.BreadcrumbsRegions := False;
  mSettings.BreadcrumbsStatements := True;
  mSettings.BreadcrumbsSectionCounts := False;
  mSettings.BreadcrumbsSectionAppend := False;
  mSettings.BreadcrumbsSectionCreate := False;
  mSettings.SectionAppendKey := $C04E;
  mSettings.BreadcrumbsContextMenu := False;
  mSettings.BreadcrumbsOverloads := False;
  mSettings.BreadcrumbsInterfaces := False;
  mSettings.BreadcrumbsMetrics := False;
  mSettings.MouseNavButtons := False;
  mSettings.BreadcrumbsIdeColors := False;
  mSettings.BreadcrumbsHideIdeToolbar := False;
  mSettings.BreadcrumbsKey := 0;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.Breadcrumbs);
  Assert.IsTrue(mLoaded.BreadcrumbsShowUnit);
  Assert.IsFalse(mLoaded.BreadcrumbsVisibility);
  Assert.IsFalse(mLoaded.BreadcrumbsMemberBlocks);
  Assert.IsFalse(mLoaded.BreadcrumbsVisibilityMark);
  Assert.IsFalse(mLoaded.BreadcrumbsDeclarationBlocks);
  Assert.IsFalse(mLoaded.BreadcrumbsConditionals);
  Assert.IsFalse(mLoaded.BreadcrumbsRegions);
  Assert.IsTrue(mLoaded.BreadcrumbsStatements);
  Assert.IsFalse(mLoaded.BreadcrumbsSectionCounts);
  Assert.IsFalse(mLoaded.BreadcrumbsSectionAppend);
  Assert.IsFalse(mLoaded.BreadcrumbsSectionCreate);
  Assert.AreEqual($C04E, mLoaded.SectionAppendKey, 'Strg+Alt+N');
  Assert.IsFalse(mLoaded.BreadcrumbsContextMenu);
  Assert.IsFalse(mLoaded.BreadcrumbsOverloads);
  Assert.IsFalse(mLoaded.BreadcrumbsInterfaces);
  Assert.IsFalse(mLoaded.BreadcrumbsMetrics);
  Assert.IsFalse(mLoaded.MouseNavButtons);
  Assert.IsFalse(mLoaded.BreadcrumbsIdeColors);
  Assert.IsFalse(mLoaded.BreadcrumbsHideIdeToolbar);
  Assert.AreEqual(0, mLoaded.BreadcrumbsKey);
  mLoaded.BreadcrumbsKey := -5;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.BreadcrumbsKey);
end;
procedure TAtlasViewSettingsTests.JumpToMatchOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.JumpToMatch);
  Assert.AreEqual($40BA, mSettings.JumpToMatchKey, 'Strg+Ü');
  Assert.AreEqual($60BA, mSettings.JumpToMatchSelectKey, 'Strg+Umschalt+Ü');
  mSettings.JumpToMatch := False;
  mSettings.JumpToMatchKey := $4042;
  mSettings.JumpToMatchSelectKey := 0;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.JumpToMatch);
  Assert.AreEqual($4042, mLoaded.JumpToMatchKey);
  Assert.AreEqual(0, mLoaded.JumpToMatchSelectKey);
  mLoaded.JumpToMatchKey := $1FFFF;
  mLoaded.Normalize;
  Assert.AreEqual($FFFF, mLoaded.JumpToMatchKey);
end;
procedure TAtlasViewSettingsTests.StickyScrollOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #506: nicht mehr experimentell, also an; drei Zeilen; Grenzen 1 bis 10.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.StickyScroll);
  Assert.AreEqual(3, mSettings.StickyScrollMaxLines);
  mSettings.StickyScroll := True;
  mSettings.StickyScrollMaxLines := 5;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.StickyScroll);
  Assert.AreEqual(5, mLoaded.StickyScrollMaxLines);
  mLoaded.StickyScrollMaxLines := 0;
  mLoaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinStickyLines, mLoaded.StickyScrollMaxLines);
  mLoaded.StickyScrollMaxLines := 99;
  mLoaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxStickyLines, mLoaded.StickyScrollMaxLines);
  // #1230: if/else-Blöcke an, ab 25 Zeilen; Grenzen 5 bis 1000.
  Assert.IsTrue(mSettings.StickyScrollBlocks);
  Assert.AreEqual(25, mSettings.StickyScrollBlockMinLines);
  mSettings.StickyScrollBlocks := False;
  mSettings.StickyScrollBlockMinLines := 40;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.StickyScrollBlocks);
  Assert.AreEqual(40, mLoaded.StickyScrollBlockMinLines);
  mLoaded.StickyScrollBlockMinLines := 1;
  mLoaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinStickyBlockLines, mLoaded.StickyScrollBlockMinLines);
  // Was der Kopf zeigt: Typen und Routinen an, weitere Anweisungsblöcke aus; jede Art einzeln gespeichert.
  Assert.IsTrue(mSettings.StickyScrollTypes and mSettings.StickyScrollRoutines);
  Assert.IsFalse(mSettings.StickyScrollLoops or mSettings.StickyScrollTry or mSettings.StickyScrollCase or
    mSettings.StickyScrollWith);
  mSettings.StickyScrollTypes := False;
  mSettings.StickyScrollLoops := True;
  mSettings.StickyScrollCase := True;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.StickyScrollTypes);
  Assert.IsTrue(mLoaded.StickyScrollRoutines);
  Assert.IsTrue(mLoaded.StickyScrollLoops);
  Assert.IsFalse(mLoaded.StickyScrollTry);
  Assert.IsTrue(mLoaded.StickyScrollCase);
  Assert.IsFalse(mLoaded.StickyScrollWith);
end;
procedure TAtlasViewSettingsTests.MinimapOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // #873: experimentell, also aus; Vorgaben laut Issue; Speichern, Laden, Klemmen.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.Minimap);
  Assert.AreEqual('characters', mSettings.MinimapRender);
  Assert.AreEqual(120, mSettings.MinimapWidth);
  Assert.AreEqual(2, mSettings.MinimapScale);
  Assert.AreEqual(120, mSettings.MinimapMaxColumn);
  Assert.AreEqual('right', mSettings.MinimapSide);
  Assert.AreEqual('always', mSettings.MinimapShowSlider);
  Assert.IsTrue(mSettings.MinimapSectionHeaders and mSettings.MinimapHighlightMethod and mSettings.MinimapMarkers and
    mSettings.MinimapClickJumps);
  Assert.IsFalse(mSettings.MinimapNoticeShown);
  mSettings.Minimap := True;
  mSettings.MinimapRender := 'blocks';
  mSettings.MinimapWidth := 90;
  mSettings.MinimapScale := 3;
  mSettings.MinimapMaxColumn := 80;
  mSettings.MinimapSide := 'left';
  mSettings.MinimapShowSlider := 'mouseover';
  mSettings.MinimapSectionHeaders := False;
  mSettings.MinimapHighlightMethod := False;
  mSettings.MinimapMarkers := False;
  mSettings.MinimapClickJumps := False;
  mSettings.MinimapNoticeShown := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.Minimap);
  Assert.AreEqual('blocks', mLoaded.MinimapRender);
  Assert.AreEqual(90, mLoaded.MinimapWidth);
  Assert.AreEqual(3, mLoaded.MinimapScale);
  Assert.AreEqual(80, mLoaded.MinimapMaxColumn);
  Assert.AreEqual('left', mLoaded.MinimapSide);
  Assert.AreEqual('mouseover', mLoaded.MinimapShowSlider);
  Assert.IsFalse(mLoaded.MinimapSectionHeaders or mLoaded.MinimapHighlightMethod or mLoaded.MinimapMarkers or
    mLoaded.MinimapClickJumps);
  Assert.IsTrue(mLoaded.MinimapNoticeShown);
  mLoaded.MinimapRender := 'pixel';
  mLoaded.MinimapSide := 'oben';
  mLoaded.MinimapShowSlider := '';
  mLoaded.MinimapWidth := 1;
  mLoaded.MinimapScale := 9;
  mLoaded.MinimapMaxColumn := 100000;
  mLoaded.Normalize;
  Assert.AreEqual('characters', mLoaded.MinimapRender);
  Assert.AreEqual('right', mLoaded.MinimapSide);
  Assert.AreEqual('always', mLoaded.MinimapShowSlider);
  Assert.AreEqual(TAtlasPluginSettings.cMinMinimapWidth, mLoaded.MinimapWidth);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMinimapScale, mLoaded.MinimapScale);
  Assert.AreEqual(TAtlasPluginSettings.cMaxMinimapColumn, mLoaded.MinimapMaxColumn);
end;
procedure TAtlasViewSettingsTests.GutterColumnOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  // Atlas-Spalte in der Zeilenleiste (#768): Hauptschalter und Unterschalter standardmäßig an, je einzeln aus.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.GutterColumn);
  Assert.IsTrue(mSettings.GutterColumnProblems);
  Assert.IsTrue(mSettings.GutterColumnCodeActions);
  Assert.IsTrue(mSettings.GutterColumnOverrides);
  mSettings.GutterColumn := False;
  mSettings.GutterColumnCodeActions := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.GutterColumn);
  Assert.IsTrue(mLoaded.GutterColumnProblems);
  Assert.IsFalse(mLoaded.GutterColumnCodeActions);
  Assert.IsTrue(mLoaded.GutterColumnOverrides);
  mLoaded.GutterColumnOverrides := False;
  mLoaded.Save(mStore);
  mSettings := TAtlasPluginSettings.Defaults;
  mSettings.Load(mStore);
  Assert.IsFalse(mSettings.GutterColumnOverrides);
end;
procedure TAtlasViewSettingsTests.SelectionMatchesOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.SelectionMatches);
  Assert.AreEqual(3, mSettings.SelectionMatchesMinLength);
  Assert.IsFalse(mSettings.SelectionMatchesCaseSensitive);
  Assert.IsFalse(mSettings.SelectionMatchesWholeWord);
  Assert.IsTrue(mSettings.SelectionMatchesNavigateF3);
  Assert.AreEqual(1000, mSettings.SelectionMatchesMaxMatches);
  mSettings.SelectionMatches := False;
  mSettings.SelectionMatchesMinLength := 5;
  mSettings.SelectionMatchesCaseSensitive := True;
  mSettings.SelectionMatchesWholeWord := True;
  mSettings.SelectionMatchesNavigateF3 := False;
  mSettings.SelectionMatchesMaxMatches := 250;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.SelectionMatches);
  Assert.AreEqual(5, mLoaded.SelectionMatchesMinLength);
  Assert.IsTrue(mLoaded.SelectionMatchesCaseSensitive);
  Assert.IsTrue(mLoaded.SelectionMatchesWholeWord);
  Assert.IsFalse(mLoaded.SelectionMatchesNavigateF3);
  Assert.AreEqual(250, mLoaded.SelectionMatchesMaxMatches);
  // Grenzen: Mindestlänge 1 bis 100, Treffer 1 bis 100000.
  mLoaded.SelectionMatchesMinLength := 0;
  mLoaded.SelectionMatchesMaxMatches := 0;
  mLoaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMinSelectionMatchLength, mLoaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.cMinSelectionMatches, mLoaded.SelectionMatchesMaxMatches);
  mLoaded.SelectionMatchesMinLength := 500;
  mLoaded.SelectionMatchesMaxMatches := 5000000;
  mLoaded.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxSelectionMatchLength, mLoaded.SelectionMatchesMinLength);
  Assert.AreEqual(TAtlasPluginSettings.cMaxSelectionMatches, mLoaded.SelectionMatchesMaxMatches);
end;
procedure TAtlasViewSettingsTests.ExpressionTypeOptions;
var
  mSettings: TAtlasPluginSettings;
begin
  // Typ des markierten Ausdrucks (#689): an, mit Umwandlungen und Wert, Strg+Umschalt+T.
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.ExpressionType);
  Assert.IsTrue(mSettings.ExpressionTypeConversions);
  Assert.IsTrue(mSettings.ExpressionTypeConstValue);
  Assert.AreEqual($6054, mSettings.ExpressionTypeKey, 'Strg+Umschalt+T');
  mSettings.ExpressionTypeKey := $1FFFF;
  mSettings.Normalize;
  Assert.AreEqual($FFFF, mSettings.ExpressionTypeKey);
  mSettings.ExpressionTypeKey := -3;
  mSettings.Normalize;
  Assert.AreEqual(0, mSettings.ExpressionTypeKey);
end;
procedure TAtlasViewSettingsTests.GitChangeOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.GitGutter);
  Assert.IsFalse(mSettings.GitBlame, 'blame nur auf Wunsch');
  Assert.AreEqual($C022, mSettings.NextChangeKey, 'Strg+Alt+Bild↓');
  Assert.AreEqual($C021, mSettings.PreviousChangeKey, 'Strg+Alt+Bild↑');
  mSettings.GitGutter := False;
  mSettings.GitBlame := True;
  mSettings.NextChangeKey := 0;
  mSettings.PreviousChangeKey := $4074;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.GitGutter);
  Assert.IsTrue(mLoaded.GitBlame);
  Assert.AreEqual(0, mLoaded.NextChangeKey);
  Assert.AreEqual($4074, mLoaded.PreviousChangeKey);
  mLoaded.NextChangeKey := -1;
  mLoaded.PreviousChangeKey := $20000;
  mLoaded.Normalize;
  Assert.AreEqual(0, mLoaded.NextChangeKey);
  Assert.AreEqual($FFFF, mLoaded.PreviousChangeKey);
end;
procedure TAtlasViewSettingsTests.OverviewRulerOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.OverviewRuler);
  Assert.AreEqual('diagnostics,search,changes,breakpoints,bookmarks,cursor', mSettings.OverviewRulerKinds);
  mSettings.OverviewRuler := False;
  mSettings.OverviewRulerKinds := 'changes,diagnostics';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.OverviewRuler);
  mLoaded.Normalize;
  Assert.AreEqual('diagnostics,changes', mLoaded.OverviewRulerKinds, 'feste Reihenfolge');
  mLoaded.OverviewRulerKinds := 'gibtsnicht, cursor';
  mLoaded.Normalize;
  Assert.AreEqual('cursor', mLoaded.OverviewRulerKinds);
  mLoaded.OverviewRulerKinds := '';
  mLoaded.Normalize;
  Assert.AreEqual('', mLoaded.OverviewRulerKinds, 'leer = keine Marken');
end;
procedure TAtlasViewSettingsTests.CallHierarchyDiagramOption;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.CallHierarchyDiagram, 'Aufrufdiagramm standardmäßig an');
  mSettings.CallHierarchyDiagram := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  Assert.AreEqual(0, mStore.ReadInteger('CallHierarchyDiagram', 1));
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.CallHierarchyDiagram);
end;
procedure TAtlasViewSettingsTests.EditorToolbarOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.EditorToolbar);
  Assert.AreEqual('belowBreadcrumbs', mSettings.EditorToolbarPosition);
  Assert.AreEqual(TAtlasToolbarItems.DefaultText, mSettings.EditorToolbarItems);
  Assert.IsTrue(mSettings.EditorToolbarReturnButton);
  Assert.IsFalse(mSettings.EditorToolbarLabels);
  Assert.AreEqual(0, mSettings.GotoInterfaceKey, 'keine Taste');
  Assert.AreEqual(0, mSettings.GotoImplementationKey, 'keine Taste');
  mSettings.EditorToolbarPosition := 'INBREADCRUMBS';
  mSettings.EditorToolbarItems := '|, Atlas.GotoInterface ,|,|,Atlas.NavBack,Atlas.navback,|';
  mSettings.GotoInterfaceKey := $1FFFF;
  mSettings.GotoImplementationKey := -3;
  mSettings.Normalize;
  Assert.AreEqual('inBreadcrumbs', mSettings.EditorToolbarPosition);
  Assert.AreEqual('Atlas.GotoInterface,|,Atlas.NavBack', mSettings.EditorToolbarItems);
  Assert.AreEqual($FFFF, mSettings.GotoInterfaceKey);
  Assert.AreEqual(0, mSettings.GotoImplementationKey);
  mSettings.EditorToolbarPosition := 'oben';
  mSettings.Normalize;
  Assert.AreEqual('belowBreadcrumbs', mSettings.EditorToolbarPosition, 'Unbekanntes = Vorgabe');
  mSettings.EditorToolbar := False;
  mSettings.EditorToolbarPosition := 'aboveBreadcrumbs';
  mSettings.EditorToolbarItems := '';
  mSettings.EditorToolbarReturnButton := False;
  mSettings.EditorToolbarLabels := True;
  mSettings.GotoInterfaceKey := $6049;
  mSettings.GotoImplementationKey := $604D;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.EditorToolbar);
  Assert.AreEqual('aboveBreadcrumbs', mLoaded.EditorToolbarPosition);
  Assert.AreEqual('', mLoaded.EditorToolbarItems, 'alle Knöpfe entfernt bleibt leer');
  Assert.IsFalse(mLoaded.EditorToolbarReturnButton);
  Assert.IsTrue(mLoaded.EditorToolbarLabels);
  Assert.AreEqual($6049, mLoaded.GotoInterfaceKey);
  Assert.AreEqual($604D, mLoaded.GotoImplementationKey);
end;
procedure TAtlasViewSettingsTests.EditorStatusBarOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.EditorStatusBar);
  Assert.AreEqual('status,findings,liveCheck,method', mSettings.EditorStatusBarItems);
  Assert.AreEqual(TAtlasStatusBarItems.DefaultText, mSettings.EditorStatusBarItems);
  mSettings.EditorStatusBarItems := ' METHOD, zahnrad ,status,method';
  mSettings.Normalize;
  Assert.AreEqual('method,status', mSettings.EditorStatusBarItems, 'nur bekannte, jedes einmal');
  mSettings.EditorStatusBar := False;
  mSettings.EditorStatusBarItems := '';
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.EditorStatusBar);
  Assert.AreEqual('', mLoaded.EditorStatusBarItems, 'alle Elemente aus bleibt leer');
end;
procedure TAtlasViewSettingsTests.EditorDesignerBarOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.EditorDesignerBar);
  Assert.AreEqual(32988, mSettings.DesignerSearchKey, 'Alt+^');
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchWindow, mSettings.DesignerSearchStyle, 'großes Fenster');
  Assert.IsTrue(mSettings.DesignerTabOrderClick, 'Neuvergeben an (#603)');
  Assert.IsFalse(mSettings.DesignerTabOrderOverlay, 'Marken nur auf Knopfdruck');
  Assert.IsFalse(mSettings.DesignerTabOrderPaths);
  Assert.IsTrue(mSettings.DesignerTabOrderColors, 'Farben je Container an');
  Assert.IsFalse(mSettings.DesignerAlign, 'experimentell: aus');
  mSettings.EditorDesignerBar := False;
  mSettings.DesignerSearchKey := 0;
  mSettings.DesignerSearchStyle := TAtlasPluginSettings.cDesignerSearchPopup;
  mSettings.DesignerTabOrderClick := False;
  mSettings.DesignerTabOrderOverlay := True;
  mSettings.DesignerTabOrderPaths := True;
  mSettings.DesignerTabOrderColors := False;
  mSettings.DesignerAlign := True;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsFalse(mLoaded.EditorDesignerBar);
  Assert.AreEqual(0, mLoaded.DesignerSearchKey, 'keine Taste');
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchPopup, mLoaded.DesignerSearchStyle);
  Assert.IsFalse(mLoaded.DesignerTabOrderClick);
  Assert.IsTrue(mLoaded.DesignerTabOrderOverlay);
  Assert.IsTrue(mLoaded.DesignerTabOrderPaths);
  Assert.IsFalse(mLoaded.DesignerTabOrderColors);
  Assert.IsTrue(mLoaded.DesignerAlign);
  mStore.WriteString('DesignerSearchStyle', 'riesig');
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cDesignerSearchWindow, mLoaded.DesignerSearchStyle, 'Unbekanntes: Vorgabe');
end;
/// <summary>Eigenes Desktop-Layout im Designer (#2079): Vorgaben, Speichern und Laden, unbekannter Rückweg.
/// </summary>
procedure TAtlasViewSettingsTests.DesignerLayoutOptions;
var
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(mSettings.DesignerLayout, 'Vorgabe aus');
  Assert.AreEqual('', mSettings.DesignerLayoutName);
  Assert.AreEqual(TAtlasPluginSettings.cDesignerLayoutPrevious, mSettings.DesignerLayoutReturnTo);
  Assert.IsTrue(mSettings.DesignerLayoutSkipWhileDebugging);
  mSettings.DesignerLayout := True;
  mSettings.DesignerLayoutName := '  Designer ';
  mSettings.DesignerLayoutReturnTo := TAtlasPluginSettings.cDesignerLayoutDefault;
  mSettings.DesignerLayoutSkipWhileDebugging := False;
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  Assert.IsTrue(mLoaded.DesignerLayout);
  Assert.AreEqual('Designer', mLoaded.DesignerLayoutName, 'ohne Leerraum');
  Assert.AreEqual(TAtlasPluginSettings.cDesignerLayoutDefault, mLoaded.DesignerLayoutReturnTo);
  Assert.IsFalse(mLoaded.DesignerLayoutSkipWhileDebugging);
  mStore.WriteString('DesignerLayoutReturnTo', 'irgendwo');
  mLoaded.Load(mStore);
  Assert.AreEqual(TAtlasPluginSettings.cDesignerLayoutPrevious, mLoaded.DesignerLayoutReturnTo, 'Unbekanntes: Vorgabe');
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
  mSettings, mLoaded: TAtlasPluginSettings;
  mStore: IAtlasSettingsStore;
begin
  mSettings := TAtlasPluginSettings.Defaults;
  Assert.IsTrue(mSettings.QuickBookmarks);
  Assert.IsTrue(mSettings.QuickBookmarksGutter);
  Assert.IsTrue(mSettings.QuickBookmarksGutterClick);
  Assert.IsTrue(mSettings.QuickBookmarksNumberedKeys);
  Assert.AreEqual($604B, mSettings.QuickBookmarkKey, 'Strg+Umschalt+K');
  Assert.IsTrue(mSettings.QuickBookmarkKeyPriority);
  Assert.AreEqual(800, mSettings.QuickBookmarkChordWait);
  Assert.AreEqual($6031, mSettings.QuickBookmarkSetKey, 'Strg+Umschalt+1');
  Assert.AreEqual($4031, mSettings.QuickBookmarkJumpKey, 'Strg+1');
  Assert.AreEqual('project', mSettings.QuickBookmarksScope);
  Assert.IsTrue(mSettings.QuickBookmarksImportIde);
  Assert.AreEqual(0, mSettings.NextBookmarkKey, 'ohne voreingestellte Taste');
  Assert.AreEqual(0, mSettings.PreviousBookmarkKey);
  mSettings.QuickBookmarkChordWait := 99999;
  mSettings.QuickBookmarksScope := 'FILE';
  mSettings.QuickBookmarkKey := -1;
  mSettings.Normalize;
  Assert.AreEqual(TAtlasPluginSettings.cMaxQuickChordWait, mSettings.QuickBookmarkChordWait);
  Assert.AreEqual('file', mSettings.QuickBookmarksScope);
  Assert.AreEqual(0, mSettings.QuickBookmarkKey);
  mSettings.QuickBookmarksScope := 'irgendwo';
  mSettings.QuickBookmarkChordWait := -5;
  mSettings.Normalize;
  Assert.AreEqual('project', mSettings.QuickBookmarksScope);
  Assert.AreEqual(0, mSettings.QuickBookmarkChordWait);
  SetQuickBookmarkOptions(mSettings);
  mStore := TMemoryStore.Create;
  mSettings.Save(mStore);
  mLoaded := TAtlasPluginSettings.Defaults;
  mLoaded.Load(mStore);
  AssertQuickBookmarkLoaded(mLoaded);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasViewSettingsTests);

end.
