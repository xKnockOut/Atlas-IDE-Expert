unit Atlas.IDE.CodeInsight.Composition.EditorBars;

// Leisten und Fenster am Editor: Navigationsverlauf (#504), Einblenden (#505), Gliederung (#537), Brotkrumen
// (#590), Atlas-Editorleiste (#1101), Atlas-Statusleiste (#1155), mitlaufender Kopf (#506), Übersichtsleiste
// (#519), Minimap (#873) und Schnell öffnen (#503). Dazu der Teil „Commands“ der Feature-Tabelle in seiner Start-
// und Abbaureihenfolge mit den Units Navigation und Editing.

interface

/// <summary>Teil „Commands“ (#399, #400) anmelden: Navigation, Leisten, Bearbeitungshilfen in Startreihenfolge.
/// </summary>
procedure StartCommands;
/// <summary>Teil „Commands“ in umgekehrter Reihenfolge abmelden.</summary>
procedure StopCommands;
function CommandsStarted: Boolean;

implementation

uses
  Atlas.Core.Editor.Metrics,
  Atlas.IDE.Editor.NavHistory,
  Atlas.IDE.Editor.MouseButtons,
  Atlas.IDE.Results.Peek,
  Atlas.IDE.Outline.Cache,
  Atlas.IDE.Outline.Service,
  Atlas.IDE.Outline.Breadcrumbs,
  Atlas.IDE.Outline.CrumbMenu,
  Atlas.IDE.Results.Commands,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Outline.StickyScroll,
  Atlas.IDE.EditorToolbar.Service,
  Atlas.IDE.StatusBar.Service,
  Atlas.IDE.Editor.MetricsSource,
  Atlas.IDE.Editor.OverviewRuler,
  Atlas.IDE.Editor.Minimap,
  Atlas.IDE.Commands.QuickOpen,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Problems.Controller,
  Atlas.IDE.CodeInsight.Composition.Session,
  Atlas.IDE.CodeInsight.Composition.Status,
  Atlas.IDE.CodeInsight.Composition.Palette,
  Atlas.IDE.CodeInsight.Composition.Navigation,
  Atlas.IDE.CodeInsight.Composition.Editing,
  Atlas.IDE.CodeInsight.Composition.Tools;

var
  // Ergebnisfenster (#400) und Editorbefehle (#399) angemeldet.
  CommandsInstalled: Boolean;

function FindingsOf(AFileName: string): Integer;
begin
  Result := 0;
  if TAtlasProblemsController.Current <> nil then
  begin
    Result := Length(TAtlasProblemsController.Current.ForFile(AFileName));
  end;
end;

function CanGoBack: Boolean;
begin
  Result := (TAtlasIdeNavHistory.History <> nil) and (TAtlasIdeNavHistory.History.BackCount > 0);
end;

function CanGoForward: Boolean;
begin
  Result := (TAtlasIdeNavHistory.History <> nil) and (TAtlasIdeNavHistory.History.ForwardCount > 0);
end;

/// <summary>Atlas-Editorleiste (#1101): Palette, Befunde, Verlauf und Meldungen über Hooks (kein Feature-Zyklus).
/// Die Palette entsteht später (StartPalette); die Hooks fragen sie erst beim Aufruf.</summary>
procedure StartEditorToolbar;
var
  mHooks: TAtlasIdeEditorToolbar.THooks;
begin
  mHooks := Default(TAtlasIdeEditorToolbar.THooks);
  mHooks.Commands := PaletteCommands;
  mHooks.Execute :=
    procedure(AId: string)
    begin
      ExecutePaletteCommand(AId);
    end;
  mHooks.ShowPalette := ShowPalette;
  mHooks.ShortCuts :=
    function: TFunc<string, string>
    begin
      Result := TAtlasIdeKeyMap.AtlasShortCuts();
    end;
  mHooks.FindingsOf := FindingsOf;
  mHooks.CanGoBack := CanGoBack;
  mHooks.CanGoForward := CanGoForward;
  mHooks.Message := MessageLines();
  TAtlasIdeEditorToolbar.Install(mHooks);
end;

/// <summary>Klick auf die Live-Prüfung (#1231); startet keinen Server.</summary>
procedure Recheck;
begin
  if Manager <> nil then
  begin
    Manager.RunServerCommandAsync('atlas.server.recheck', '[]', 10000, nil);
  end;
end;

const
  /// <summary>Kennung der Statusleiste beim Abruf der Metriken.</summary>
  cStatusBarClient = 'atlas.statusBar';

/// <summary>Bedarf der Statusleiste beim Abruf der Metriken: lesen oder keiner.</summary>
procedure WantStatusMetrics(AOn: Boolean);
begin
  if AOn then
  begin
    TAtlasEditorMetricsSource.Want(cStatusBarClient, TAtlasMetricsDemand.Read);
  end
  else
  begin
    TAtlasEditorMetricsSource.Want(cStatusBarClient, TAtlasMetricsDemand.None);
  end;
end;

/// <summary>Atlas-Statusleiste (#1155): Atlas-Feld, Metriken aus dem Abruf von Base (#66) und Meldungen über Hooks.
/// Zeigt die Leiste das Element status, öffnet das Feld Statusfenster und Schnellschalter an der Leiste.</summary>
procedure StartStatusBar;
var
  mHooks: TAtlasIdeStatusBar.THooks;
begin
  mHooks := Default(TAtlasIdeStatusBar.THooks);
  mHooks.Field := StatusField;
  mHooks.Metrics :=
    function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean
    begin
      Result := TAtlasEditorMetricsSource.Latest(AFileName, AMetrics);
    end;
  mHooks.WantMetrics :=
    WantStatusMetrics;
  mHooks.Message := MessageLines();
  mHooks.Recheck := Recheck;
  TAtlasIdeStatusBar.Install(mHooks);
  RequestStatusRefresh;
end;

/// <summary>Haken des Kontextmenüs der Brotkrumen (#1786): Umbenennen, Verwendungen, Formulartext.</summary>
function CrumbMenuHooks: TAtlasCrumbMenuHooks;
begin
  Result := Default(TAtlasCrumbMenuHooks);
  Result.Rename := RenameSymbol;
  Result.References :=
    procedure(const AFileName: string; ALine, ACharacter: Integer; const AName: string)
    begin
      TAtlasIdeResults.ShowReferences(AFileName, ALine, ACharacter, AName);
    end;
  Result.CurrentText :=
    function(AFileName: string): string
    begin
      Result := TAtlasIdeWorkspaceEdit.CurrentText(AFileName);
    end;
end;

const
  /// <summary>Kennung der Brotkrumen beim Abruf der Metriken (Kennzahlen-Karte, #1787).</summary>
  cBreadcrumbsClient = 'atlas.breadcrumbs';

/// <summary>Kennzahlen-Karte der Brotkrumen (#1787): dieselben Metriken wie Statusleiste und Metrik-Linse.</summary>
function CrumbCardHooks: TAtlasCrumbCardHooks;
begin
  Result := Default(TAtlasCrumbCardHooks);
  Result.Metrics :=
    function(const AFileName: string; out AMetrics: TAtlasFileMetrics): Boolean
    begin
      Result := TAtlasEditorMetricsSource.Latest(AFileName, AMetrics);
    end;
  Result.WantMetrics :=
    procedure(AOn: Boolean)
    begin
      if AOn then
      begin
        TAtlasEditorMetricsSource.Want(cBreadcrumbsClient, TAtlasMetricsDemand.Read);
      end
      else
      begin
        TAtlasEditorMetricsSource.Want(cBreadcrumbsClient, TAtlasMetricsDemand.None);
      end;
    end;
end;

/// <summary>Verlauf, Einblenden, Gliederung, Brotkrumen, Editor- und Statusleiste und mitlaufender Kopf.</summary>
procedure InstallBars;
begin
  // Navigationsverlauf (#504): Sprünge und Bearbeitungsstellen der Sitzung.
  TAtlasIdeNavHistory.Install;
  // Zurück-/Vor-Taste der Maus durch denselben Verlauf (#1889).
  TAtlasIdeMouseButtons.Install;
  // Definition und Referenzen einblenden (#505).
  TAtlasIdePeek.Install;
  // Gemeinsamer Stand der Gliederung, Gliederungsfenster (#537) und Brotkrumenleiste (#590).
  TAtlasIdeOutlineCache.Install(ActiveSession);
  TAtlasIdeOutline.Install;
  TAtlasIdeBreadcrumbs.Install(CrumbMenuHooks, CrumbCardHooks);
  // Atlas-Editorleiste (#1101) nach den Brotkrumen (Position „in der Brotkrumenzeile“).
  StartEditorToolbar;
  StartStatusBar;
  // Mitlaufender Kopf (#506) aus demselben Gliederungsstand.
  TAtlasIdeStickyScroll.Install;
end;

/// <summary>Übersichtsleiste (#519), Minimap (#873, fragt die Gliederung über TAtlasIdeOutlineCache) und Schnell
/// öffnen (#503, Dateiliste im Hintergrund, zuletzt geöffnete Dateien zählen).</summary>
procedure InstallOverviews;
begin
  TAtlasIdeOverviewRuler.Install;
  TAtlasIdeMinimap.Install;
  TAtlasIdeQuickOpen.Install(ActiveSession);
end;

procedure StartCommands;
begin
  CommandsInstalled := True;
  InstallNavigation;
  InstallBars;
  InstallEditing;
  InstallOverviews;
end;

procedure StopCommands;
begin
  TAtlasIdeQuickOpen.Uninstall;
  TAtlasIdePeek.Uninstall;
  TAtlasIdeStickyScroll.Uninstall;
  TAtlasIdeEditorToolbar.Uninstall;
  TAtlasIdeStatusBar.Uninstall;
  TAtlasIdeBreadcrumbs.Uninstall;
  TAtlasIdeMinimap.Uninstall;
  TAtlasIdeOverviewRuler.Uninstall;
  UninstallEditing;
  TAtlasIdeOutline.Uninstall;
  TAtlasIdeOutlineCache.Uninstall;
  TAtlasIdeMouseButtons.Uninstall;
  TAtlasIdeNavHistory.Uninstall;
  UninstallNavigation;
  CommandsInstalled := False;
end;

function CommandsStarted: Boolean;
begin
  Result := CommandsInstalled;
end;

end.
