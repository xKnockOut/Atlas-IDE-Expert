unit Atlas.IDE.CodeInsight.Composition.Appearance;

// Thema und Einstellungen der Fenster und Leisten: Wechsel des IDE-Themas an Menü, Statusfeld, Fenster, Leisten
// und Module (#751, #1455) und geänderte Einstellungen an Fenster und Leisten am Editor.

interface

/// <summary>Thema der IDE gewechselt: Bilder, Farben und Fenster aller Teile und Module nachziehen.</summary>
procedure ThemeChanged;
/// <summary>Geänderte Einstellungen an Fenster und Leisten: Prüfung (#909), Gliederung (#537), Aufrufdiagramm
/// (#1122), Server (#1356), Kontextmenü (#1117), Brotkrumen (#590), Editorleiste (#1101), Statusleiste (#1155),
/// mitlaufender Kopf (#506), Änderungen (#507), Übersichtsleiste (#519) und Minimap (#873).</summary>
procedure ApplyWindowSettings;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Status.ServerWindow,
  Atlas.IDE.Problems.Service,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.Outline.StickyScroll,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.StatusBar.Service,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Editor.OverviewRuler,
  Atlas.IDE.Editor.Minimap,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Tools;

/// <summary>Thema an die angemeldeten Module weitergeben (#1455); Fehler eines Moduls ins Protokoll.</summary>
procedure ModulesThemeChanged;
var
  mFailure: string;
begin
  for mFailure in TAtlasModuleContributions.ThemeChanged(AtlasModuleRegistry) do
  begin
    TAtlasGuard.Log('Thema im Modul nicht übernommen: ' + mFailure);
  end;
end;

/// <summary>Thema an die Teile mit eigenem Fenster: Diagnose, Einrichtung, Tastenbelegung und Tipps.</summary>
procedure PartsThemeChanged;
begin
  if DiagnosticMode <> nil then
  begin
    DiagnosticMode.ThemeChanged;
  end;
  if Setup <> nil then
  begin
    Setup.ThemeChanged;
  end;
  if KeyMap <> nil then
  begin
    KeyMap.ThemeChanged;
  end;
  if ShortcutTips <> nil then
  begin
    ShortcutTips.ThemeChanged;
  end;
end;

procedure ThemeChanged;
begin
  if MainMenu <> nil then
  begin
    MainMenu.UpdateImage;
  end;
  RequestStatusRefresh;
  TAtlasIdeResultsWindow.ApplyTheme;
  TAtlasIdeServerWindow.ApplyTheme;
  PartsThemeChanged;
  TAtlasIdeProblems.ThemeChanged;
  TAtlasIdeOutline.ThemeChanged;
  TAtlasIdeBreadcrumbs.ThemeChanged;
  TAtlasIdeStickyScroll.ThemeChanged;
  TAtlasIdeEditorToolbar.ThemeChanged;
  TAtlasIdeStatusBar.ThemeChanged;
  TAtlasIdeOverviewRuler.ThemeChanged;
  TAtlasIdeMinimap.ThemeChanged;
  // Fenster der Module (#1455).
  ModulesThemeChanged;
end;

procedure ApplyWindowSettings;
begin
  TAtlasIdeProblems.ApplySettings;
  TAtlasIdeOutline.ApplySettings;
  TAtlasIdeResultsWindow.ApplySettings;
  TAtlasIdeServerWindow.ApplySettings;
  // navigation.symbolPath (#1117): Kontextmenü „Weg von hier nach …“.
  TAtlasIdeEditorCommands.ApplySettings;
  TAtlasIdeBreadcrumbs.ApplySettings;
  TAtlasIdeEditorToolbar.ApplySettings;
  // editor.statusBar* (#1155); das Atlas-Feld zieht um oder zurück (RequestRefresh am Ende).
  TAtlasIdeStatusBar.ApplySettings;
  TAtlasIdeStickyScroll.ApplySettings;
  // editor.gitGutter, editor.gitBlame (#507): übernimmt das Modul Versionsverwaltung (#1905).
  // editor.overviewRuler, editor.overviewRulerKinds (#519).
  TAtlasIdeOverviewRuler.ApplySettings;
  // editor.minimap* (#873, experimentell).
  TAtlasIdeMinimap.ApplySettings;
end;

end.
