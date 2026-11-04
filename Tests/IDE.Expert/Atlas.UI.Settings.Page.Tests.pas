unit Atlas.UI.Settings.Page.Tests;

// Tests für die Optionsseite (#227): Die IDE erzeugt sie über die Klasse,
// TCustomFrame.Create braucht dafür die DFM-Ressource.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
    [Test]
    procedure CreatesAndRoundTripsSettings;
    [Test]
    procedure SnippetsPageShowsCatalogAndValidates;
    [Test]
    procedure ShowsAndReenablesTrippedFeatures;
    [Test]
    procedure IndexSectionRoundTripsAndRunsCommands;
    [Test]
    procedure StatusFieldRoundTrips;
    [Test]
    procedure ShortcutTipsRoundTrip;
    /// <summary>Benachrichtigungszentrale (#601): Schalter, Höchstzahl und Verhalten je Quelle auf dem Reiter
    /// Allgemein, Taste auf dem Reiter Befehle.</summary>
    [Test]
    procedure NotificationsRoundTrip;
    /// <summary>Notizen (#545): Schalter auf dem Reiter Editor, Vorgabe an.</summary>
    [Test]
    procedure NotesRoundTrip;
    /// <summary>#261: Schalter „Builds für Claude Code“ auf dem Reiter Compiler.</summary>
    [Test]
    procedure McpBuildRoundTrip;
    /// <summary>Beim Öffnen bauen: Auswahl, Umfang, Wartezeit und Ausschluss hin und zurück; standardmäßig aus.
    /// </summary>
    [Test]
    procedure OpenBuildRoundTrip;
    /// <summary>#900: Projektaufgaben auf dem Reiter Compiler hin und zurück, Vorgaben wie im Issue.</summary>
    [Test]
    procedure TasksRoundTrip;
    [Test]
    procedure ListModeRoundTrip;
    /// <summary>#69: Code Lens auf dem Reiter Editor, Tests ausführen, vorher bauen, nach dem Build und
    /// build.zeroHints (#530) auf dem Reiter Compiler.</summary>
    [Test]
    procedure TestRunRoundTrip;
    /// <summary>#575: Startprofile und ihr Feld in der Statusleiste auf dem Reiter Compiler.</summary>
    [Test]
    procedure StartProfilesRoundTrip;
    /// <summary>Reiter „Release-Build“ (#533): Schalter, build.gate, Konfigurationen und Prüfungen samt Sollwert.
    /// </summary>
    [Test]
    procedure ReleaseGuardRoundTrip;
    /// <summary>#585: Test debuggen und Haltepunkt am Anfang auf dem Reiter Debuggen.</summary>
    [Test]
    procedure TestDebugRoundTrip;
    /// <summary>#786: Alt+F11 und Umschalt+F12 auf der Seite „Units suchen“.</summary>
    [Test]
    procedure UseUnitAndFormsDialogsRoundTrip;
    [Test]
    procedure DebugVisualizersRoundTrip;
    [Test]
    procedure DebugDisplayRulesRoundTrip;
    [Test]
    procedure DebugStepIntoTargetRoundTrip;
    [Test]
    procedure DebugBreakOnNextEventRoundTrip;
    [Test]
    procedure DebugStepFiltersRoundTrip;
    /// <summary>Benannte Lesezeichen (#622): zwei Schalter auf dem Reiter Editor, Taste bei den Befehlen.</summary>
    [Test]
    procedure BookmarksRoundTrip;
    /// <summary>Erzeugen-Menü (#719) auf dem Reiter Befehle.</summary>
    [Test]
    procedure GenerateMenuRoundTrip;
    /// <summary>Blockende-Beschriftung (#620) und Taste „Element ausblenden …“ (#628) laden und speichern.
    /// </summary>
    [Test]
    procedure HideElementRoundTrip;
    [Test]
    procedure SafeModeRoundTrips;
    [Test]
    procedure UndoSettingsRoundTrip;
    [Test]
    procedure MethodToggleRoundTrip;
    [Test]
    procedure MoveLinesRoundTrip;
    [Test]
    procedure ContinueCommentsRoundTrip;
    [Test]
    procedure CompleteStatementRoundTrip;
    [Test]
    procedure FormatCodeRoundTrip;
    [Test]
    procedure ContinuePatternRoundTrip;
    [Test]
    procedure MultiCursorRoundTrip;
    [Test]
    procedure SmartPasteRoundTrip;
    [Test]
    procedure StickyScrollRoundTrip;
    [Test]
    procedure EditorToolbarRoundTrip;
    [Test]
    procedure EditorStatusBarRoundTrip;
    [Test]
    procedure QuickBookmarksRoundTrip;
    /// <summary>#1122: Kontrollkästchen „Aufrufdiagramm“ liest und schreibt callHierarchy.diagram.</summary>
    [Test]
    procedure CallHierarchyDiagramRoundTrip;
    /// <summary>#1285: Seite Versionsverwaltung als eigener Bereich: Art, Programmpfade mit Fundort ohne
    /// Prozess, „Prüfen“ im Hintergrund, Zeitlimit, aktuelles Projekt beim ersten Zeigen und Links.</summary>
    [Test]
    procedure VcsPageLocatesChecksAndShowsProject;
    /// <summary>#1285: Texte für Fundort, Prüfergebnis und aktuelles Projekt.</summary>
    [Test]
    procedure VcsTexts;
    /// <summary>#1286: Tabelle Projekte der Versionsverwaltung: Zeile aus der .atlas schreibgeschützt, überdeckte
    /// persönliche Zeile markiert, „Aktuelles Projekt“ mit erkannter Art, Ordner über OnTrackerBrowse, Hauptbranch
    /// ohne Leerraum, Entfernen, Speichern nach vcs.projects.</summary>
    [Test]
    procedure VcsProjectsTable;
    /// <summary>#1287: Tabelle „Server“: Zeile je Ordner aus aktuellem Projekt und Tabelle Projekte, Zustand aus
    /// der Sitzung, „Prüfen“ und „Alle prüfen“ über OnVcsServerCheck, „Anmelden …“ nur bei „Anmeldung nötig“.
    /// </summary>
    [Test]
    procedure VcsServersTable;
    /// <summary>Favoriten (#458): Schalter, Liste, „Entfernen“ und „Alle entfernen“.</summary>
    [Test]
    procedure FavoritesListAndRemove;
    [Test]
    procedure AcceptOptionsRoundTrip;
    [Test]
    procedure ServerPageRunsActions;
    [Test]
    procedure DialogShowsOriginAndResetsToGlobal;
    [Test]
    procedure DialogRuleTableChangesOnlyThatRule;
    /// <summary>Die Dialoge der Einstellungsdateien zeigen die Prüfregeln mit einem Knoten je Gruppe (#909).
    /// </summary>
    [Test]
    procedure DialogRulesByGroupNodes;
    /// <summary>#1296: Wächst der Regel-Editor mit der markierten Regel, rücken die Felder darunter nach statt
    /// überdeckt zu werden.</summary>
    [Test]
    procedure DialogRuleEditorPushesFieldsDown;
    [Test]
    procedure DialogValidatesBeforeSaving;
    [Test]
    procedure SymbolResourcesInAllSizes;
    [Test]
    procedure PageHeaderShowsSymbol;
    /// <summary>Baum links (#890): Bereiche, Unterpunkte, Seitenwechsel, Auswahl bis zum nächsten Öffnen.</summary>
    [Test]
    procedure TreeShowsAreasAndNodes;
    /// <summary>Wächter (#890): jede Einstellung auf ihrem Knoten, höchstens im Rahmen ihres Hauptschalters.</summary>
    [Test]
    procedure EveryBindingOnOneNode;
    /// <summary>Hauptschalter sperrt seine Gruppe; experimentell aus sperrt auch ihn (#890).</summary>
    [Test]
    procedure MasterLocksItsGroup;
    /// <summary>Hauptschalter auf einer anderen Seite sperrt mit Grund im Rahmen (#890).</summary>
    [Test]
    procedure MasterOnOtherPageLocks;
    /// <summary>Übersicht auf dem Hauptknoten spiegelt die Hauptschalter (#890).</summary>
    [Test]
    procedure OverviewMirrorsMasters;
    /// <summary>Reveal einer gesperrten Einstellung hebt den Hauptschalter hervor (#890, #628).</summary>
    [Test]
    procedure RevealLockedShowsMaster;
    /// <summary>Filter im Baum und „Seite zurücksetzen“ je Knoten (#890).</summary>
    [Test]
    procedure FilterAndResetPerNode;
    /// <summary>„Wächter testen“ nur im Diagnosemodus (Code-Review S-07).</summary>
    [Test]
    procedure HangTestOnlyInDiagnosticMode;
    /// <summary>#909: Bereich Prüfregeln mit Prüffenster, Knoten je Gruppe, Hauptschalter, Reveal einer Regel
    /// und den Änderungen für settings.json.</summary>
    [Test]
    procedure RulesAreaLinksToDialogs;
    /// <summary>#1108: offene Units zuerst auf dem Knoten „Prüffenster“; der Schalter sperrt seine Unterpunkte.
    /// </summary>
    [Test]
    procedure ProblemsWindowOpenFirstLocksItsOptions;
    /// <summary>Reiter „Projektdatei“ (#486): jeder Wert mit „aus .atlas“, Hinweise, Öffnen.</summary>
    [Test]
    procedure TeamFileTabShowsValuesFromAtlas;
    /// <summary>Hauptschalter für experimentelle Funktionen (#834): Vorgabe aus, Rundweg, Filterzeile.</summary>
    [Test]
    procedure ExperimentalSwitchRoundTrips;
    /// <summary>Filter „Nur experimentelle“ und „Geändert“ (#834): Kennzeichen, Ausblenden, Zusammenrücken, Wiederherstellen.</summary>
    [Test]
    procedure FilterHidesAndRestoresRows;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.VisualizerKinds,
  Atlas.Text.StepFilter,
  Atlas.Core.Settings.Reassigned,
  Atlas.Core.Build.PipelineSettings,
  Atlas.Core.Projects.Vcs,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Completion.Snippets,
  Atlas.Core.Completion.SnippetCatalog,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  Atlas.UI.Settings.SnippetsPage,
  Atlas.UI.Settings.ServerPage,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.Core.Settings.Schema,
  Atlas.Core.Settings.SchemaData,
  Atlas.Core.Settings.Layers,
  Atlas.Core.Settings.Validation,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Projects,
  Atlas.Core.Tracker.Queries,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools,
  Atlas.Core.Vcs.ToolCheck,
  Atlas.Core.Vcs.ServerCheck,
  Atlas.Core.Vcs.ServerAccess,
  Atlas.Core.Tracker.Workflow,
  Atlas.Core.Tracker.CommentEditor,
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Vcl.Graphics,
  Vcl.ImageCollection,
  System.JSON,
  System.Generics.Collections,
  System.StrUtils,
  System.Math,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Settings.Rules,
  Atlas.UI.Strings;

procedure TAtlasSettingsPageTests.WarmUp;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
begin
  TAtlasSettingsPage.Create(nil).Free;
  // Auch mit Fenster (Reiter, PageControl): einmalige VCL-Daten nicht dem ersten Test anrechnen.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
  finally
    Host.Free;
  end;
  SnippetsPageShowsCatalogAndValidates;
end;

/// <summary>Liegt AControl in AParent (oder ist es selbst)?</summary>
function Inside(AControl, AParent: TControl): Boolean;
begin
  while (AControl <> nil) and (AControl <> AParent) do
  begin
    AControl := AControl.Parent;
  end;
  Result := AControl <> nil;
end;

/// <summary>Reiter, auf dem AControl liegt; nil ohne.</summary>
function SheetOf(AControl: TControl): TTabSheet;
begin
  while (AControl <> nil) and not (AControl is TTabSheet) do
  begin
    AControl := AControl.Parent;
  end;
  Result := TTabSheet(AControl);
end;

/// <summary>Nächster Rahmen über AControl; nil ohne.</summary>
function FrameAround(AControl: TControl): TAtlasSettingsGroup;
begin
  AControl := AControl.Parent;
  while (AControl <> nil) and not (AControl is TAtlasSettingsGroup) do
  begin
    AControl := AControl.Parent;
  end;
  Result := TAtlasSettingsGroup(AControl);
end;

/// <summary>Knoten des Baums, der ASheet zeigt; nil ohne.</summary>
function TreeNodeOf(APage: TAtlasSettingsPage; ASheet: TTabSheet): TTreeNode;
var
  Index: Integer;
begin
  for Index := 0 to APage.Navigation.Items.Count - 1 do
  begin
    Result := APage.Navigation.Items[Index];
    APage.Navigation.OnChange(APage.Navigation, Result);
    if APage.Pages.ActivePage = ASheet then
    begin
      Exit;
    end;
  end;
  Result := nil;
end;

function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to APage.Navigation.Items.Count - 1 do
  begin
    if APage.Navigation.Items[Index].Level = 0 then
    begin
      Result := Result + [APage.Navigation.Items[Index]];
    end;
  end;
end;

/// <summary>#890: Bereiche oben im Baum in fester Reihenfolge; jede Seite hat Inhalt und keinen sichtbaren Reiter.</summary>
procedure AssertTreeAreas(APage: TAtlasSettingsPage; const AAreas: TArray<TTreeNode>);
var
  mIndex: Integer;
begin
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabGeneral), AAreas[0].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabCompiler), AAreas[6].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRules), AAreas[7].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRelease), AAreas[8].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabDebug), AAreas[9].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUndo), AAreas[13].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUnitSearch), AAreas[14].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabWelcome), AAreas[15].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabIssues), AAreas[16].Text, 'eigener Bereich (#1280)');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabVcs), AAreas[17].Text, 'eigener Bereich (#1285)');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabTeamFile), AAreas[18].Text);
  Assert.IsTrue(APage.Pages.PageCount > 17, 'Unterpunkte haben eigene Seiten');
  for mIndex := 0 to APage.Pages.PageCount - 1 do
  begin
    Assert.IsTrue(APage.Pages.Pages[mIndex].ControlCount > 0, APage.Pages.Pages[mIndex].Caption);
    Assert.IsFalse(APage.Pages.Pages[mIndex].TabVisible, APage.Pages.Pages[mIndex].Caption);
  end;
end;

procedure TAtlasSettingsPageTests.TreeShowsAreasAndNodes;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Areas: TArray<TTreeNode>;
  Node: TTreeNode;
  Minimap: TTabSheet;
begin
  // #890: Bereiche oben im Baum, Funktionen als Unterpunkte; jeder Knoten zeigt nur seine Seite.
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Areas := TopLevelNodes(Page);
    Assert.AreEqual(19, Integer(Length(Areas)));
    AssertTreeAreas(Page, Areas);
    Assert.IsTrue(Page.Pages.ActivePage = Page.Pages.Pages[0], 'erstes Öffnen: Allgemein');
    // Unterpunkt „Minikarte“ unter „Editor“ mit ihren Einstellungen und nichts sonst.
    Minimap := Page.NodeSheet('editor.minimap');
    Assert.IsNotNull(Minimap);
    Assert.AreEqual('editor.minimap', Page.NodeOfSheet(Minimap));
    Assert.IsTrue(SheetOf(Page.MinimapWidth) = Minimap);
    Assert.IsFalse(SheetOf(Page.StickyScroll) = Minimap);
    Node := TreeNodeOf(Page, Minimap);
    Assert.IsNotNull(Node, 'Knoten im Baum');
    Assert.AreEqual(1, Node.Level);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabEditor), Node.Parent.Text);
    Page.Navigation.OnChange(Page.Navigation, Areas[13]);
    Assert.AreEqual('', Page.NodeOfSheet(Page.Pages.ActivePage), 'Hauptknoten zeigt den Bereich');
    Page.Navigation.OnChange(Page.Navigation, Node);
    Assert.IsTrue(Page.Pages.ActivePage = Minimap, 'Klick im Baum schaltet die Seite');
  finally
    Host.Free;
  end;
  // Beim nächsten Öffnen dieselbe Seite, ihr Bereich aufgeklappt.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Assert.IsTrue(Page.Pages.ActivePage = Page.NodeSheet('editor.minimap'), 'Auswahl gemerkt');
    Assert.IsNotNull(Page.Navigation.Selected);
    Assert.IsTrue(Page.Navigation.Selected.Parent.Expanded, 'Bereich aufgeklappt');
  finally
    Host.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

procedure TAtlasSettingsPageTests.EveryBindingOnOneNode;
var
  Page: TAtlasSettingsPage;
  Index: Integer;
  Binding: TAtlasSettingsBinding;
  Name, Known: string;
  Sheet: TTabSheet;
  Frame: TAtlasSettingsGroup;
  Ancestors: TArray<string>;
begin
  // #890 Wächter: Jede Einstellung steht auf genau dem Knoten aus dem Schema und höchstens in einem Rahmen,
  // dem ihres Hauptschalters (oder eines seiner Vorfahren).
  Page := TAtlasSettingsPage.Create(nil);
  try
    for Index := 0 to Page.Marks.Count - 1 do
    begin
      Binding := Page.Marks.Bindings[Index];
      Known := '';
      for Name in Binding.Names do
      begin
        if (Known = '') and Page.Groups.Contains(Name) then
        begin
          Known := Name;
        end;
      end;
      if Known = '' then
      begin
        Continue;
      end;
      Sheet := SheetOf(Binding.Control);
      Assert.IsNotNull(Sheet, Known);
      Assert.AreEqual(Page.Groups.NodeOf(Known), Page.NodeOfSheet(Sheet), Known);
      Frame := FrameAround(Binding.Control);
      // Ohne Rahmen (Einstellung ohne Hauptschalter, z. B. debug.hoverValues) ist nichts weiter zu prüfen.
      if (Frame <> nil) and Inside(Binding.Control, Frame.Master) then
      begin
        Frame := FrameAround(Frame);
      end;
      if Frame = nil then
      begin
        Continue;
      end;
      Ancestors := Page.Groups.AncestorsOf(Known);
      Assert.IsTrue(Frame.MasterName <> '', Known);
      Assert.IsTrue(MatchText(Frame.MasterName, Ancestors), Known + ' in ' + Frame.MasterName);
    end;
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MasterLocksItsGroup;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Frame: TAtlasSettingsGroup;
begin
  // #890: Hauptschalter aus ⇒ jede Unteroption gesperrt; die Werte bleiben und werden gespeichert.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ExperimentalEnabled := True;
    Settings.Minimap := True;
    Settings.MinimapWidth := 90;
    Page.LoadFrom(Settings);
    Frame := Page.FrameOf('Minimap');
    Assert.IsNotNull(Frame, 'Minikarte hat einen Rahmen');
    Assert.IsTrue(Frame.Master = Page.Minimap, 'Hauptschalter oben im Rahmen');
    Assert.IsTrue(Page.MinimapRender.Enabled and Page.MinimapWidth.Enabled);
    Assert.IsFalse(Page.SheetGray(Page.NodeSheet('editor.minimap')));
    Page.Minimap.Checked := False;
    Assert.IsTrue(Page.Minimap.Enabled, 'der Hauptschalter bleibt bedienbar');
    Assert.IsFalse(Page.MinimapRender.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(Page.MinimapWidth.Enabled, 'Textfeld gesperrt');
    Assert.IsFalse(Frame.Reason.Visible, 'kein Grund: Der Schalter steht im Rahmen');
    Assert.IsTrue(Page.SheetGray(Page.NodeSheet('editor.minimap')), 'Knoten grau');
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual(90, Saved.MinimapWidth, 'Wert bleibt erhalten');
    Page.Minimap.Checked := True;
    Assert.IsTrue(Page.MinimapRender.Enabled and Page.MinimapWidth.Enabled, 'wieder frei');
    // Experimentelle Funktionen aus: auch der Hauptschalter gesperrt, mit Grund im Rahmen.
    Page.ExperimentalEnabled.Checked := False;
    Assert.IsFalse(Page.Minimap.Enabled);
    Assert.IsFalse(Page.MinimapWidth.Enabled);
    Assert.IsTrue(Frame.Reason.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsLockedExperimental), Frame.Reason.Caption);
    Assert.IsTrue(Page.Minimap.Checked, 'Wert bleibt');
    Page.ExperimentalEnabled.Checked := True;
    Assert.IsTrue(Page.Minimap.Enabled);
    Assert.IsFalse(Frame.Reason.Visible);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MasterOnOtherPageLocks;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Frame: TAtlasSettingsGroup;
  Master: TCheckBox;
begin
  // #890: Abhängigkeit über Seiten hinweg: Atlas-Code-Insight (Allgemein) aus sperrt den mitlaufenden Kopf.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ExperimentalEnabled := True;
    Settings.StickyScroll := True;
    Page.LoadFrom(Settings);
    Frame := Page.FrameOf('StickyScroll');
    Assert.IsNotNull(Frame);
    Assert.IsTrue(Page.StickyScroll.Enabled and Page.StickyScrollMaxLines.Enabled);
    Master := Page.FrameOf('Enabled').Master as TCheckBox;
    Master.Checked := False;
    Assert.IsFalse(Page.StickyScroll.Enabled, 'Hauptschalter gesperrt');
    Assert.IsFalse(Page.StickyScrollMaxLines.Enabled, 'Unteroption gesperrt');
    Assert.IsTrue(Frame.Reason.Visible, 'Grund im Rahmen');
    Assert.IsTrue(Pos(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled).Replace('&', ''), Frame.Reason.Caption) > 0,
      Frame.Reason.Caption);
    Assert.IsFalse(Page.ControlOf('PairGuides').Enabled, 'auch Klammerfarben');
    Master.Checked := True;
    Assert.IsTrue(Page.StickyScroll.Enabled and Page.StickyScrollMaxLines.Enabled);
    Assert.IsFalse(Frame.Reason.Visible);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.OverviewMirrorsMasters;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Mirror: TCheckBox;
begin
  // #890: Der Hauptknoten „Editor“ zeigt je Funktion ihren Hauptschalter; beide folgen einander.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ExperimentalEnabled := True;
    Settings.Minimap := True;
    Page.LoadFrom(Settings);
    Mirror := Page.OverviewMirror('Minimap');
    Assert.IsNotNull(Mirror);
    Assert.AreEqual('', Page.NodeOfSheet(SheetOf(Mirror)), 'auf dem Hauptknoten');
    Assert.IsTrue(SheetOf(Mirror) <> nil);
    Assert.IsTrue(Mirror.Checked);
    Mirror.Checked := False;
    Assert.IsFalse(Page.Minimap.Checked, 'Spiegel schaltet');
    Assert.IsFalse(Page.MinimapWidth.Enabled);
    Page.Minimap.Checked := True;
    Assert.IsTrue(Mirror.Checked, 'Spiegel folgt');
    Page.ExperimentalEnabled.Checked := False;
    Assert.IsFalse(Mirror.Enabled, 'gesperrt wie das Original');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.RevealLockedShowsMaster;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Master: TCheckBox;
begin
  // #890: Eine gesperrte Einstellung zeigen: Ihr Hauptschalter ist hervorgehoben.
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Settings := TAtlasPluginSettings.Defaults;
    Settings.PairColors := False;
    Page.LoadFrom(Settings);
    Master := Page.ControlOf('PairColors') as TCheckBox;
    Assert.IsTrue(Page.Reveal('PairGuides'));
    Assert.IsTrue(fsBold in Master.Font.Style, 'Hauptschalter hervorgehoben');
    Assert.IsTrue(Page.Pages.ActivePage = SheetOf(Master), 'dessen Seite gewählt');
    Assert.IsTrue(Page.Navigation.Selected <> nil);
  finally
    Host.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

procedure TAtlasSettingsPageTests.FilterAndResetPerNode;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Minimap: TTabSheet;
begin
  // #890: Der Filter blendet Knoten ohne Treffer aus; „Seite zurücksetzen“ wirkt auf den gewählten Knoten.
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ExperimentalEnabled := True;
    Settings.Minimap := True;
    Page.LoadFrom(Settings);
    Minimap := Page.NodeSheet('editor.minimap');
    Page.Filter.Choice := 2;
    Page.Filter.OnChange(Page.Filter);
    Assert.IsTrue(Length(TopLevelNodes(Page)) < 17, 'Bereiche ohne experimentelle Einstellung fehlen');
    Assert.IsNotNull(TreeNodeOf(Page, Minimap), 'Minikarte ist experimentell');
    Assert.IsNotNull(Page.NodeSheet('welcome.header'));
    Assert.IsNull(TreeNodeOf(Page, Page.NodeSheet('welcome.header')), 'Kopf der Willkommensseite ohne Treffer');
    Page.Filter.Choice := 0;
    Page.Filter.OnChange(Page.Filter);
    // 16 Bereiche, „Prüfregeln“ (#909), Issue-Tracker (#1280) und Versionsverwaltung (#1285).
    Assert.AreEqual(19, Integer(Length(TopLevelNodes(Page))));
    // Zurücksetzen auf dem Unterpunkt: nur die Minikarte.
    Page.MinimapWidth.Text := '90';
    Page.StickyScrollMaxLines.Text := '7';
    Page.Navigation.OnChange(Page.Navigation, TreeNodeOf(Page, Minimap));
    Page.ResetPage;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual(TAtlasPluginSettings.Defaults.MinimapWidth, Saved.MinimapWidth, 'zurückgesetzt');
    Assert.AreEqual(7, Saved.StickyScrollMaxLines, 'anderer Unterpunkt bleibt');
    Assert.IsTrue(Saved.ExperimentalEnabled);
  finally
    Host.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

procedure TAtlasSettingsPageTests.TeamFileTabShowsValuesFromAtlas;
var
  Page: TAtlasSettingsPage;
  Team: TAtlasTeamSettings;
  Opened: Integer;
  Settings: TAtlasPluginSettings;
begin
  Team := TAtlasTeamFile.Parse('{"version": 1, "naming": {"field": "F"}, "snippets": "Vorlagen", "token": "x"}',
    'C:\Repo\.atlas', 'C:\Repo');
  Team.Project := 'C:\Repo\Kasse.dproj';
  Opened := 0;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Page.LoadFrom(Settings);
    Assert.Contains(Page.TeamFileInfo.Caption, TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoProject));
    Assert.IsFalse(Page.TeamFileOpenButton.Enabled, 'ohne Projekt');
    Page.OnTeamFile :=
      function: TAtlasTeamSettings
      begin
        Result := Team; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
      end;
    Page.OnOpenTeamFile :=
      procedure
      begin
        Inc(Opened);
      end;
    Assert.Contains(Page.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileValue,
      ['naming.field', '"F"']));
    Assert.Contains(Page.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileIssues, [1]),
      'Zugangsdaten ignoriert');
    Assert.Contains(Page.TeamSnippetsLabel.Caption, 'Vorlagen');
    Assert.IsTrue(Page.TeamFileOpenButton.Enabled);
    Page.TeamFileOpenButton.Click;
    Assert.AreEqual(1, Opened);
    // Ausgeschaltet: keine Werte, kein Hinweis bei den Vorlagen, gespeichert als TeamFile = False.
    Page.TeamFileCheck.Checked := False;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOff), Page.TeamFileInfo.Caption);
    Assert.AreEqual('', Page.TeamSnippetsLabel.Caption);
    Page.SaveTo(Settings);
    Assert.IsFalse(Settings.TeamFile);
    // Fehlerhafte Datei: Hinweis statt Werte.
    Team := TAtlasTeamFile.Parse('{', 'C:\Repo\.atlas', 'C:\Repo');
    Team.Project := 'C:\Repo\Kasse.dproj';
    Page.TeamFileCheck.Checked := True;
    // Mit Lage des Fehlers in der Datei (Zeile 1, Spalte 2 für "{").
    Assert.Contains(Page.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileInvalidAt, [1, 2]));
  finally
    Page.Free;
  end;
end;

/// <summary>Werte von der Vorgabe abweichend setzen.</summary>
procedure SetPageRoundTrip(var ASettings: TAtlasPluginSettings);
begin
  ASettings.Enabled := False;
  ASettings.VisibleRows := 12;
  ASettings.Preview := True;
  ASettings.HoverTooltip := False;
  ASettings.XmlDocExpand := 'collapsed';
  ASettings.XmlDocMaxLines := 7;
  ASettings.ListWidth := 333;
  ASettings.ActionsKey := 0;
  ASettings.ExpandKey := $C057;
  ASettings.EditorKeysPriority := True;
  ASettings.SlashCommands := False;
  ASettings.Snippets := False;
  ASettings.ImportIdeTemplates := False;
  ASettings.ProviderTimeLimitMs := 400;
  ASettings.PairOwners := False;
  ASettings.PairGuideWidth := 3;
  ASettings.PairGuideOpacity := 70;
  ASettings.PairColorsLight := '#0071E3,#007C8A,#C000E0,#008700,#4040FF';
  ASettings.CodeLensMetrics := False;
  ASettings.TodoList := False;
  ASettings.MetricsReport := False;
  ASettings.TeamFile := False;
  ASettings.StartProfiles := False;
end;

/// <summary>Über die Seite gespeicherte Werte.</summary>
procedure AssertPageRoundTrip(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.Enabled);
  Assert.AreEqual(12, ASaved.VisibleRows);
  Assert.IsTrue(ASaved.Preview);
  Assert.IsFalse(ASaved.HoverTooltip);
  Assert.AreEqual('collapsed', ASaved.XmlDocExpand);
  Assert.AreEqual(7, ASaved.XmlDocMaxLines);
  Assert.AreEqual(333, ASaved.ListWidth);
  Assert.AreEqual(0, ASaved.ActionsKey);
  Assert.AreEqual($C057, ASaved.ExpandKey);
  Assert.AreEqual($6057, ASaved.ShrinkKey);
  Assert.IsTrue(ASaved.EditorKeysPriority);
  Assert.IsFalse(ASaved.SlashCommands);
  Assert.IsFalse(ASaved.Snippets);
  Assert.IsFalse(ASaved.ImportIdeTemplates);
  Assert.AreEqual(400, ASaved.ProviderTimeLimitMs);
  Assert.IsFalse(ASaved.PairOwners);
  Assert.AreEqual(3, ASaved.PairGuideWidth);
  Assert.AreEqual(70, ASaved.PairGuideOpacity);
  Assert.AreEqual('#0071E3,#007C8A,#C000E0,#008700,#4040FF', ASaved.PairColorsLight);
  Assert.AreEqual('', ASaved.PairColorsDark, 'Standardfarben bleiben leer');
  Assert.IsFalse(ASaved.CodeLensMetrics, 'Code Lens Metriken (#66)');
  Assert.IsFalse(ASaved.TodoList, 'Befehl (#68)');
  Assert.IsFalse(ASaved.MetricsReport, 'Befehl (#66)');
  Assert.IsFalse(ASaved.TeamFile, 'Projektdatei (#486)');
  Assert.IsFalse(ASaved.StartProfiles, 'Startprofile (#575)');
end;

procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  SetPageRoundTrip(Settings);
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  AssertPageRoundTrip(Saved);
end;

procedure TAtlasSettingsPageTests.ShowsAndReenablesTrippedFeatures;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Index: Integer;
begin
  TAtlasGuard.Fuse.ResetAll;
  try
    for Index := 1 to 3 do
    begin
      TAtlasGuard.ReportProvider('Testquelle', 'Fehler');
      TAtlasGuard.Fuse.Failed(TAtlasFeature.Pairs);
    end;
    // Die Liste der Sicherung braucht ein Fenster, wie in der IDE.
    Host := TForm.CreateNew(nil);
    try
      Page := TAtlasSettingsPage.Create(Host);
      Page.Parent := Host;
      Page.HandleNeeded;
      Page.LoadFrom(TAtlasPluginSettings.Defaults);
      Assert.AreEqual(2, Integer(Page.FuseList.Items.Count));
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs), Page.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', Page.FuseList.Items[1]);
      Assert.IsTrue(Page.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      Page.FuseList.Selected[1] := True;
      Page.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Page.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Integer(Page.FuseList.Items.Count), 'nur der Hinweis „keine“');
      Assert.IsFalse(Page.FuseEnableAll.Enabled);
    finally
      Host.Free;
    end;
  finally
    TAtlasGuard.Fuse.ResetAll;
  end;
end;

/// <summary>Antwort noch während des Ereignisses, wie ohne Server.</summary>
procedure AnswerIndexMetricsAtOnce(APage: TAtlasSettingsPage);
begin
  // Antwort noch während des Ereignisses, wie ohne Server.
  APage.OnIndexMetrics :=
    procedure
    begin
      APage.IndexAnswered('Units: 3');
    end;
end;

/// <summary>Antwort auf den Neuaufbau gibt die Befehle wieder frei.</summary>
procedure AnswerIndexRebuild(APage: TAtlasSettingsPage);
begin
  APage.IndexAnswered('wird neu aufgebaut');
  Assert.IsFalse(APage.IndexBusy);
  Assert.AreEqual('wird neu aufgebaut', APage.IndexInfo.Caption);
  Assert.IsTrue(APage.IndexRebuild.Enabled and APage.IndexClear.Enabled);
end;

procedure TAtlasSettingsPageTests.IndexSectionRoundTripsAndRunsCommands;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Confirm: Boolean;
  Cleared: Integer;
  Rebuilds: Integer;
begin
  // #492: Verwendungen und Speicherbudget, Kennzahlen, Neuaufbau und Löschen mit Rückfrage.
  // #874: Die Befehle laufen im Hintergrund; die Antwort kommt über IndexAnswered.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.IndexUsages := False;
  Settings.MemoryBudgetMb := 512;
  Confirm := False;
  Cleared := 0;
  Rebuilds := 0;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsFalse(Page.IndexRebuild.Enabled or Page.IndexClear.Enabled, 'ohne Server keine Befehle');
    AnswerIndexMetricsAtOnce(Page);
    // Antwort erst später, wie bei einem Server, der gerade indexiert.
    Page.OnIndexRebuild :=
      procedure
      begin
        Inc(Rebuilds);
      end;
    Page.OnIndexClear :=
      procedure
      begin
        Inc(Cleared);
        Page.IndexAnswered('gelöscht');
      end;
    Page.ConfirmClear :=
      function: Boolean
      begin
        Result := Confirm;
      end;
    Page.LoadFrom(Settings);
    Assert.AreEqual('Units: 3', Page.IndexInfo.Caption);
    Assert.IsTrue(Page.IndexRebuild.Enabled and Page.IndexClear.Enabled);
    Page.IndexRebuild.Click;
    Assert.AreEqual(1, Rebuilds);
    Assert.IsTrue(Page.IndexBusy);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIndexAsking), Page.IndexInfo.Caption);
    Assert.IsFalse(Page.IndexRebuild.Enabled or Page.IndexClear.Enabled, 'gesperrt bis zur Antwort');
    Page.IndexRebuild.Click;
    Assert.AreEqual(1, Rebuilds, 'kein zweiter Befehl, solange einer läuft');
    AnswerIndexRebuild(Page);
    Page.IndexClear.Click;
    Assert.AreEqual(0, Cleared, 'abgelehnt: nichts löschen');
    Confirm := True;
    Page.IndexClear.Click;
    Assert.AreEqual(1, Cleared);
    Assert.AreEqual('gelöscht', Page.IndexInfo.Caption);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.IndexUsages);
  Assert.AreEqual(512, Saved.MemoryBudgetMb);
end;

procedure TAtlasSettingsPageTests.StatusFieldRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #591: Feld an/aus, Kurztext, ausgeblendete Zeilen; #479: Diagnosemodus, #625: Prüfliste auf derselben Seite.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.StatusField := False;
  Settings.StatusFieldSummary := False;
  Settings.StatusFieldToggles := 'rightClick';
  Settings.IndexProgressPlace := 'off';
  Settings.StatusFieldHidden := 'atlas.file';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.StatusField.Checked);
    Assert.IsFalse(Page.StatusSummary.Checked);
    Assert.AreEqual(1, Page.StatusToggles.Choice, 'nur Rechtsklick');
    Assert.AreEqual(2, Page.IndexProgress.Choice, 'Fortschritt aus');
    Assert.AreEqual('atlas.file', Page.StatusHidden.Text);
    Assert.IsFalse(Page.DiagnosticMode.Checked, 'Diagnosemodus standardmäßig aus');
    Assert.IsTrue(Page.SetupChecklist.Checked, 'Prüfliste beim Start standardmäßig an (#625)');
    Page.DiagnosticMode.Checked := True;
    Page.SetupChecklist.Checked := False;
    Page.StatusField.Checked := True;
    Page.StatusToggles.Choice := 2;
    Page.IndexProgress.Choice := 1;
    Page.StatusHidden.Text := ' atlas.file, atlas.index ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StatusField);
    Assert.IsTrue(Saved.DiagnosticMode);
    Assert.IsFalse(Saved.SetupChecklist);
    Assert.IsFalse(Saved.StatusFieldSummary);
    Assert.AreEqual('doubleClick', Saved.StatusFieldToggles);
    Assert.AreEqual('menu', Saved.IndexProgressPlace);
    Assert.AreEqual('atlas.file, atlas.index', Saved.StatusFieldHidden);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ShortcutTipsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #600: shortcutTips.enabled und shortcutTips.scope auf der Seite Allgemein.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.ShortcutTips.Checked, 'Tipps standardmäßig an');
    Assert.AreEqual(1, Page.ShortcutTipsScope.Choice, 'Vorgabe all');
    Page.ShortcutTips.Checked := False;
    Page.ShortcutTipsScope.Choice := 0;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ShortcutTips);
    Assert.AreEqual('atlas', Saved.ShortcutTipsScope);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.ShortcutTips.Checked);
    Assert.AreEqual(0, Page.ShortcutTipsScope.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.NotificationsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.NotificationsSources := 'server=off, buildServer=collect, tracker=off';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.Notifications.Checked, 'standardmäßig an');
    Assert.AreEqual('200', Page.NotificationsMax.Text);
    Assert.AreEqual(ShortCutToText($E04E), Page.NotificationsKey.Text, 'Strg+Umschalt+Alt+N');
    // Erste Quelle (build) ohne Angabe: einblenden.
    Assert.AreEqual(0, Page.NotificationSource.Choice);
    Assert.AreEqual(0, Page.NotificationMode.Choice);
    // Quelle server (vierte) zeigt „aus“.
    Page.NotificationSource.Choice := 3;
    Page.NotificationSource.OnChange(Page.NotificationSource);
    Assert.AreEqual(2, Page.NotificationMode.Choice);
    // Build-Server (sechste, #763) zeigt „nur sammeln“.
    Page.NotificationSource.Choice := 5;
    Page.NotificationSource.OnChange(Page.NotificationSource);
    Assert.AreEqual(1, Page.NotificationMode.Choice);
    // Tastenkürzel-Tipps (fünfte) auf „nur sammeln“.
    Page.NotificationSource.Choice := 4;
    Page.NotificationSource.OnChange(Page.NotificationSource);
    Page.NotificationMode.Choice := 1;
    Page.NotificationMode.OnChange(Page.NotificationMode);
    Page.Notifications.Checked := False;
    Page.NotificationsMax.Text := '50';
    Page.NotificationsKey.Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Notifications);
  Assert.AreEqual(50, Saved.NotificationsMaxEntries);
  Assert.AreEqual(0, Saved.NotificationsKey, 'leer = keine Taste');
  // Build-Server (#763, sechste Quelle) behält sein Verhalten; unbekannte Quellen bleiben erhalten.
  Assert.AreEqual('server=off, buildServer=collect, tracker=off, shortcutTips=collect', Saved.NotificationsSources);
end;

procedure TAtlasSettingsPageTests.NotesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.NotesCheck.Checked, 'Notizen standardmäßig an');
    Page.NotesCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.Notes, 'Notizen abschaltbar');
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.NotesCheck.Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.TestRunRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.CodeLensTestsCheck.Checked, 'Code Lens standardmäßig an');
    Assert.IsTrue(Page.TestRunCheck.Checked);
    Assert.IsTrue(Page.TestsBuildFirstCheck.Checked);
    Assert.IsFalse(Page.TestsAfterBuildCheck.Checked);
    Assert.IsFalse(Page.BuildZeroHintsCheck.Checked);
    Assert.IsTrue(Page.ShowInterfaceCostCheck.Checked, 'Kosten einer interface-Änderung standardmäßig an (#554)');
    Assert.IsTrue(Page.BuildCompilerSwitchesCheck.Checked);
    Assert.IsFalse(Page.BuildSwitchesInStatusBarCheck.Checked);
    Page.CodeLensTestsCheck.Checked := False;
    Page.TestRunCheck.Checked := False;
    Page.TestsBuildFirstCheck.Checked := False;
    Page.TestsAfterBuildCheck.Checked := True;
    Page.BuildZeroHintsCheck.Checked := True;
    Page.ShowInterfaceCostCheck.Checked := False;
    Page.BuildCompilerSwitchesCheck.Checked := False;
    Page.BuildSwitchesInStatusBarCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CodeLensTests);
    Assert.IsFalse(Saved.TestRun);
    Assert.IsFalse(Saved.TestsBuildFirst);
    Assert.IsTrue(Saved.TestsAfterBuild);
    Assert.IsTrue(Saved.BuildZeroHints);
    Assert.IsFalse(Saved.ShowInterfaceCost);
    Assert.IsFalse(Saved.BuildCompilerSwitches);
    Assert.IsTrue(Saved.BuildSwitchesInStatusBar);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.CodeLensTestsCheck.Checked);
    Assert.IsFalse(Page.ShowInterfaceCostCheck.Checked);
    Assert.IsTrue(Page.TestsAfterBuildCheck.Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ReleaseGuardRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
  Checks: TAtlasReleaseChecks;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.ReleaseGuardCheck.Checked, 'Wächter standardmäßig an');
    Assert.AreEqual(0, Page.BuildGateChoice.Choice, 'build.gate off');
    Assert.AreEqual('300', Page.BuildGateTimeoutEdit.Text, 'build.gateTimeoutMs (#529)');
    Assert.IsTrue(Page.BuildSummaryCheck.Checked, 'build.summary (#530)');
    Assert.AreEqual('', Page.BuildWarningsAsErrorsEdit.Text, 'build.warningsAsErrors (#530)');
    Assert.AreEqual('Release', Page.ReleaseConfigsEdit.Text);
    Assert.IsTrue(Page.ReleaseCheckBox(TAtlasReleaseCheck.DebugDefine).Checked);
    Assert.IsNull(Page.ReleaseCheckChoice(TAtlasReleaseCheck.DebugDefine));
    Assert.IsNull(Page.ReleaseCheckBox(TAtlasReleaseCheck.RangeChecks));
    Assert.AreEqual(1, Page.ReleaseCheckChoice(TAtlasReleaseCheck.RangeChecks).Choice, 'prüfen, Soll aus');
    Page.ReleaseGuardCheck.Checked := False;
    Page.BuildGateChoice.Choice := 2;
    Page.BuildGateTimeoutEdit.Text := '20';
    Page.BuildSummaryCheck.Checked := False;
    Page.BuildWarningsAsErrorsEdit.Text := 'w1035 h2164';
    Page.ReleaseConfigsEdit.Text := 'Release; Ship ,ship';
    Page.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked := False;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice := 0;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ReleaseGuard);
    Assert.AreEqual('block', Saved.BuildGate);
    Assert.AreEqual(50, Saved.BuildGateTimeoutMs, 'auf die untere Grenze gehoben');
    Assert.IsFalse(Saved.BuildSummary);
    Assert.AreEqual('W1035, H2164', Saved.BuildWarningsAsErrors);
    Assert.AreEqual('Release, Ship', Saved.ReleaseConfigs);
    Checks := TAtlasReleaseChecks.Parse(Saved.ReleaseChecks);
    Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.OutputFolder].Enabled);
    Assert.IsFalse(Checks.Items[TAtlasReleaseCheck.Assertions].Enabled);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.StackFrames].Enabled);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.StackFrames].Expected);
    Assert.IsTrue(Checks.Items[TAtlasReleaseCheck.DebugDefine].Enabled);
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.ReleaseGuardCheck.Checked);
    Assert.AreEqual(2, Page.BuildGateChoice.Choice);
    Assert.AreEqual(0, Page.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice);
    Assert.AreEqual(2, Page.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice);
    Assert.IsFalse(Page.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.StartProfilesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.StartProfilesCheck.Checked, 'Startprofile standardmäßig an');
    Assert.IsTrue(Page.StartProfilesStatusFieldCheck.Checked, 'Statusfeld standardmäßig an');
    Page.StartProfilesCheck.Checked := False;
    Page.StartProfilesStatusFieldCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.StartProfiles);
    Assert.IsFalse(Saved.StartProfilesStatusField);
    Saved.StartProfilesStatusField := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.StartProfilesCheck.Checked);
    Assert.IsTrue(Page.StartProfilesStatusFieldCheck.Checked);
  finally
    Page.Free;
  end;
end;

/// <summary>Debugger-Schalter der Seite mit den Vorgaben.</summary>
procedure AssertDebugPageDefaults(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(APage.TestDebugCheck.Checked, 'Test debuggen standardmäßig an');
  Assert.IsTrue(APage.TestBreakAtStartCheck.Checked, 'Haltepunkt am Anfang standardmäßig an');
  Assert.IsTrue(APage.DebugHoverValuesCheck.Checked, 'Werte im Hover standardmäßig an (#891)');
  Assert.IsTrue(APage.DebugExplainUnavailableCheck.Checked, 'debug.explainUnavailable (#840)');
  Assert.IsTrue(APage.DebugCompletionInDialogsCheck.Checked, 'debug.completionInDialogs (#538)');
  Assert.IsTrue(APage.DebugEvaluateWindowCheck.Checked, 'debug.evaluateWindow (#784)');
  Assert.IsTrue(APage.DebugEvaluateReplaceCtrlF7Check.Checked, 'debug.evaluateWindow.replaceCtrlF7 (#784)');
  Assert.IsTrue(APage.DebugExplainAccessViolationCheck.Checked, 'debug.explainAccessViolation (#865)');
  Assert.IsFalse(APage.DebugExplainAccessViolationAllowCallsCheck.Checked, 'debug.explainAccessViolation.allowCalls (#865)');
  Assert.IsTrue(APage.DebugExceptionHistoryCheck.Checked, 'debug.exceptionHistory (#517)');
  Assert.IsTrue(APage.DebugJustMyCodeCheck.Checked, 'debug.justMyCode (#578)');
  Assert.IsFalse(APage.DebugExceptionBannerCheck.Checked, 'debug.exceptionBanner (#783)');
  Assert.IsTrue(APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked,
    'debug.exceptionBanner.ignoreAtLocation (#783)');
  Assert.IsTrue(APage.DebugInlineValuesCheck.Checked, 'debug.inlineValues (#508)');
  Assert.AreEqual('5', APage.DebugInlineValuesPerLineEdit.Text, 'debug.inlineValuesPerLine (#508)');
end;

/// <summary>Alle Debugger-Schalter der Seite umstellen.</summary>
procedure EditDebugPage(APage: TAtlasSettingsPage);
begin
  APage.TestDebugCheck.Checked := False;
  APage.TestBreakAtStartCheck.Checked := False;
  APage.DebugHoverValuesCheck.Checked := False;
  APage.DebugExplainUnavailableCheck.Checked := False;
  APage.DebugCompletionInDialogsCheck.Checked := False;
  APage.DebugEvaluateWindowCheck.Checked := False;
  APage.DebugEvaluateReplaceCtrlF7Check.Checked := False;
  APage.DebugExplainAccessViolationCheck.Checked := False;
  APage.DebugExplainAccessViolationAllowCallsCheck.Checked := True;
  APage.DebugExceptionHistoryCheck.Checked := False;
  APage.DebugJustMyCodeCheck.Checked := False;
  APage.DebugExceptionBannerCheck.Checked := True;
  APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked := False;
  APage.DebugInlineValuesCheck.Checked := False;
  APage.DebugInlineValuesPerLineEdit.Text := '3';
  APage.DebugOwnCodeFoldersEdit.Text := 'C:\Komponenten\; ;c:\komponenten';
end;

/// <summary>Umgestellte Debugger-Schalter gespeichert.</summary>
procedure AssertDebugSaved(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.TestDebug);
  Assert.IsFalse(ASaved.TestBreakAtStart);
  Assert.IsFalse(ASaved.DebugHoverValues);
  Assert.IsFalse(ASaved.DebugExplainUnavailable);
  Assert.IsFalse(ASaved.DebugCompletionInDialogs);
  Assert.IsFalse(ASaved.DebugEvaluateWindow);
  Assert.IsFalse(ASaved.DebugEvaluateReplaceCtrlF7);
  Assert.IsFalse(ASaved.DebugExplainAccessViolation);
  Assert.IsTrue(ASaved.DebugExplainAccessViolationAllowCalls);
  Assert.IsFalse(ASaved.DebugExceptionHistory);
  Assert.IsFalse(ASaved.DebugJustMyCode);
  Assert.IsTrue(ASaved.DebugExceptionBanner);
  Assert.IsFalse(ASaved.DebugExceptionBannerIgnoreAtLocation);
  Assert.IsFalse(ASaved.DebugInlineValues);
  Assert.AreEqual(3, ASaved.DebugInlineValuesPerLine);
  Assert.AreEqual('C:\Komponenten', ASaved.DebugOwnCodeFolders, 'bereinigt (#578)');
end;

/// <summary>Debugger-Werte für das erneute Laden zurückstellen.</summary>
procedure SetDebugSaved(var ASaved: TAtlasPluginSettings);
begin
  ASaved.TestBreakAtStart := True;
  ASaved.DebugHoverValues := True;
  ASaved.DebugExplainUnavailable := True;
  ASaved.DebugCompletionInDialogs := True;
  ASaved.DebugEvaluateWindow := True;
  ASaved.DebugEvaluateReplaceCtrlF7 := True;
  ASaved.DebugExplainAccessViolation := True;
  ASaved.DebugExplainAccessViolationAllowCalls := False;
  ASaved.DebugExceptionHistory := True;
  ASaved.DebugJustMyCode := True;
  ASaved.DebugExceptionBanner := False;
  ASaved.DebugExceptionBannerIgnoreAtLocation := True;
  ASaved.DebugInlineValues := True;
end;

/// <summary>Debugger-Schalter der Seite nach erneutem Laden.</summary>
procedure AssertDebugReloaded(APage: TAtlasSettingsPage);
begin
  Assert.IsFalse(APage.TestDebugCheck.Checked);
  Assert.IsTrue(APage.TestBreakAtStartCheck.Checked);
  Assert.IsTrue(APage.DebugHoverValuesCheck.Checked);
  Assert.IsTrue(APage.DebugExplainUnavailableCheck.Checked);
  Assert.IsTrue(APage.DebugCompletionInDialogsCheck.Checked);
  Assert.IsTrue(APage.DebugEvaluateWindowCheck.Checked);
  Assert.IsTrue(APage.DebugEvaluateReplaceCtrlF7Check.Checked);
  Assert.IsTrue(APage.DebugExplainAccessViolationCheck.Checked);
  Assert.IsFalse(APage.DebugExplainAccessViolationAllowCallsCheck.Checked);
  Assert.IsTrue(APage.DebugExceptionHistoryCheck.Checked);
  Assert.IsTrue(APage.DebugJustMyCodeCheck.Checked);
  Assert.IsFalse(APage.DebugExceptionBannerCheck.Checked);
  Assert.IsTrue(APage.DebugExceptionBannerIgnoreAtLocationCheck.Checked);
  Assert.IsTrue(APage.DebugInlineValuesCheck.Checked);
end;

procedure TAtlasSettingsPageTests.TestDebugRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    AssertDebugPageDefaults(Page);
    EditDebugPage(Page);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    AssertDebugSaved(Saved);
    SetDebugSaved(Saved);
    Page.LoadFrom(Saved);
    AssertDebugReloaded(Page);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UseUnitAndFormsDialogsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.UnitSearchReplaceUseUnitCheck.Checked, 'Alt+F11 standardmäßig übernommen');
    Assert.IsTrue(Page.UnitSearchReplaceFormsCheck.Checked, 'Umschalt+F12 standardmäßig übernommen');
    Page.UnitSearchReplaceUseUnitCheck.Checked := False;
    Page.UnitSearchReplaceFormsCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UnitSearchReplaceUseUnitDialog);
    Assert.IsFalse(Saved.UnitSearchReplaceFormsDialog);
    Assert.IsTrue(Saved.UnitSearchReplaceIdeDialog, 'Strg+F12 bleibt');
    Saved.UnitSearchReplaceFormsDialog := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.UnitSearchReplaceUseUnitCheck.Checked);
    Assert.IsTrue(Page.UnitSearchReplaceFormsCheck.Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DebugDisplayRulesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #854: Schalter und Aufrufe in Vorlagen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.DebugDisplayRulesCheck.Checked);
    Assert.IsFalse(Page.DebugDisplayRulesAllowCallsCheck.Checked);
    Page.DebugDisplayRulesCheck.Checked := False;
    Page.DebugDisplayRulesAllowCallsCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugDisplayRules);
    Assert.IsTrue(Saved.DebugDisplayRulesAllowCalls);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DebugStepIntoTargetRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #836: Schalter und Taste auf dem Reiter Debuggen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.DebugStepIntoTargetCheck.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($C076)), Page.DebugStepIntoTargetKeyEdit.Text);
    Page.DebugStepIntoTargetCheck.Checked := False;
    Page.DebugStepIntoTargetKeyEdit.Text := ShortCutToText(TShortCut($6076));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugStepIntoTarget);
    Assert.AreEqual($6076, Saved.DebugStepIntoTargetKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DebugBreakOnNextEventRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #856: Schalter und ausgenommene Ereignisse auf dem Reiter Debuggen; die Liste wird beim Speichern bereinigt.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.DebugBreakOnNextEventCheck.Checked);
    Assert.AreEqual('OnPaint, OnMouseMove, OnUpdate', Page.DebugBreakOnNextEventExcludedEdit.Text);
    Page.DebugBreakOnNextEventCheck.Checked := False;
    Page.DebugBreakOnNextEventExcludedEdit.Text := 'OnPaint;OnResize';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugBreakOnNextEvent);
    Assert.AreEqual('OnPaint, OnResize', Saved.DebugBreakOnNextEventExcluded);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DebugStepFiltersRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // #850: Schalter, Kontrollkästchen je Art und Muster auf dem Reiter Debuggen.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.DebugStepFiltersCheck.Checked);
    Assert.IsTrue(Page.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked);
    Assert.IsFalse(Page.DebugStepFilterKindCheck(TStepFilterKind.Setters).Checked);
    Assert.IsTrue(Page.DebugStepFilterKindCheck(TStepFilterKind.Trivial).Checked);
    Assert.AreEqual('', Page.DebugStepFilterPatternsEdit.Text);
    Page.DebugStepFiltersCheck.Checked := False;
    Page.DebugStepFilterKindCheck(TStepFilterKind.Getters).Checked := False;
    Page.DebugStepFilterKindCheck(TStepFilterKind.EmptyConstructors).Checked := True;
    Page.DebugStepFilterPatternsEdit.Text := ' *.Log* ; ;TBasisForm.*';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugStepFilters);
    Assert.AreEqual('trivial,emptyConstructors', Saved.DebugStepFilterKinds);
    Assert.AreEqual('*.Log*;TBasisForm.*', Saved.DebugStepFilterPatterns, 'bereinigt');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DebugVisualizersRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
  Kind: TAtlasVisualizerKind;
begin
  // #835: Hauptschalter, Haken je Art, Namensfelder, Grenzen, Auswertung als Auswahl.
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.DebugVisualizersCheck.Checked);
    for Kind := Low(TAtlasVisualizerKind) to High(TAtlasVisualizerKind) do
    begin
      Assert.IsTrue(Page.DebugVisualizerKindCheck(Kind).Checked);
    end;
    Assert.AreEqual('Name,Caption,Text', Page.DebugVisualizerNameFieldsEdit.Text);
    Assert.AreEqual('120', Page.DebugVisualizerMaxLengthEdit.Text);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Properties), Page.DebugVisualizerEvaluationBox.Choice);
    Page.DebugVisualizersCheck.Checked := False;
    Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked := False;
    Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Graphics).Checked := False;
    Page.DebugVisualizerNameFieldsEdit.Text := 'Bezeichnung, Name';
    Page.DebugVisualizerMaxLengthEdit.Text := '99999';
    Page.DebugVisualizerEvaluationBox.Choice := Ord(TAtlasVisualizerEvaluation.Calls);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.DebugVisualizers);
    Assert.AreEqual('lists,dictionaries,dataSets,bytes,colors,guid,geometry', Saved.DebugVisualizerTypes);
    Assert.AreEqual('Bezeichnung,Name', Saved.DebugVisualizerNameFields);
    Assert.AreEqual(TAtlasVisualizerSettings.MaxMaxLength, Saved.DebugVisualizerMaxLength);
    Assert.AreEqual('calls', Saved.DebugVisualizerEvaluation);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Json).Checked);
    Assert.IsTrue(Page.DebugVisualizerKindCheck(TAtlasVisualizerKind.Lists).Checked);
    Assert.AreEqual(Ord(TAtlasVisualizerEvaluation.Calls), Page.DebugVisualizerEvaluationBox.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.McpBuildRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.McpBuildCheck.Checked, 'standardmäßig an');
    Page.McpBuildCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.McpBuild, 'abschaltbar');
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.McpBuildCheck.Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ListModeRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  // Listenmodus der Vervollständigung (#497).
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, Page.ListModeChoice.Choice, 'nur Treffer');
    Assert.AreEqual(0, Page.ListScopeChoice.Choice, 'Mitgliederlisten');
    Page.ListModeChoice.Choice := 2;
    Page.ListScopeChoice.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('rest', Saved.CompletionListMode);
    Assert.AreEqual('everywhere', Saved.CompletionListScope);
    Page.ListModeChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('all', Saved.CompletionListMode);
    Page.LoadFrom(Saved);
    Assert.AreEqual(1, Page.ListModeChoice.Choice);
    Assert.AreEqual(1, Page.ListScopeChoice.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.OpenBuildRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.AreEqual(0, Page.OpenBuildChoice.Choice, 'standardmäßig nicht bauen');
    Assert.AreEqual(0, Page.OpenBuildScopeChoice.Choice, 'alle Projekte');
    Assert.AreEqual('3000', Page.OpenBuildDelayEdit.Text);
    Assert.AreEqual('', Page.OpenBuildExcludeEdit.Text);
    Assert.AreEqual('', Page.OpenBuildConfigEdit.Text);
    Assert.AreEqual(0, Page.OpenBuildPlatformChoice.Choice, 'wie im Projekt');
    // Erzeugen, nur das aktive Projekt, 5 s, ein Package ausgeschlossen.
    Page.OpenBuildChoice.Choice := 3;
    Page.OpenBuildScopeChoice.Choice := 1;
    Page.OpenBuildDelayEdit.Text := '5000';
    Page.OpenBuildExcludeEdit.Text := 'Atlas.IDE.Expert.dproj';
    Page.OpenBuildConfigEdit.Text := ' Debug ';
    Page.OpenBuildPlatformChoice.Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.BuildOnOpen);
    Assert.AreEqual('build', Saved.BuildOnOpenKind);
    Assert.AreEqual('active', Saved.BuildOnOpenScope);
    Assert.AreEqual(5000, Saved.BuildOnOpenDelayMs);
    Assert.AreEqual('Atlas.IDE.Expert', Saved.BuildOnOpenExclude);
    Assert.AreEqual('Debug', Saved.BuildOnOpenConfig);
    Assert.AreEqual('Win64', Saved.BuildOnOpenPlatform);
    Page.LoadFrom(Saved);
    Assert.AreEqual('Debug', Page.OpenBuildConfigEdit.Text);
    Assert.AreEqual(3, Page.OpenBuildChoice.Choice);
    Assert.AreEqual(1, Page.OpenBuildScopeChoice.Choice);
    // Syntaxprüfung; „nicht bauen“ schaltet ab und behält die Art.
    Page.OpenBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.OpenBuildChoice.Choice := 0;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BuildOnOpen, 'abschaltbar');
    Assert.AreEqual('check', Saved.BuildOnOpenKind);
    Page.LoadFrom(Saved);
    Assert.AreEqual(0, Page.OpenBuildChoice.Choice);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.TasksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.TasksEnabledCheck.Checked, 'standardmäßig an');
    Assert.IsTrue(Page.TasksProblemsFromOutputCheck.Checked);
    Assert.AreEqual(0, Page.TasksBeforeBuildChoice.Choice, 'vor dem Build: aus');
    Assert.IsTrue(Page.TasksSaveBeforeRunCheck.Checked);
    Assert.IsFalse(Page.TasksRunChecksParallelCheck.Checked);
    Assert.IsFalse(Page.TasksOnlyFindingsCheck.Checked);
    Page.TasksEnabledCheck.Checked := False;
    Page.TasksProblemsFromOutputCheck.Checked := False;
    Page.TasksBeforeBuildChoice.Choice := 2;
    Page.TasksSaveBeforeRunCheck.Checked := False;
    Page.TasksRunChecksParallelCheck.Checked := True;
    Page.TasksOnlyFindingsCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.TasksEnabled, 'abschaltbar');
    Assert.IsFalse(Saved.TasksProblemsFromOutput);
    Assert.AreEqual('block', Saved.TasksBeforeBuild);
    Assert.IsFalse(Saved.TasksSaveBeforeRun);
    Assert.IsTrue(Saved.TasksRunChecksParallel);
    Assert.IsTrue(Saved.TasksOnlyFindings);
    Page.LoadFrom(Saved);
    Assert.AreEqual(2, Page.TasksBeforeBuildChoice.Choice);
    Assert.IsFalse(Page.TasksEnabledCheck.Checked);
    Page.TasksBeforeBuildChoice.Choice := 1;
    Page.SaveTo(Saved);
    Assert.AreEqual('warn', Saved.TasksBeforeBuild);
  finally
    Page.Free;
  end;
end;

/// <summary>Vorgaben und Änderungen: Blockende, Datenfluss, Austrittspunkte, Unterstreichung, Ausdruckstyp.</summary>
procedure EditHideElementMarkers(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(APage.BlockEndLabelsCheck.Checked, 'standardmäßig an');
  Assert.AreEqual(ShortCutToText($40BE), APage.HideElementKey.Text, 'Strg+.');
  Assert.AreEqual('25', APage.BlockEndLabelsMinLinesEdit.Text, 'Mindestlänge (#620)');
  Assert.IsTrue(APage.DimUnusedUsesCheck.Checked, 'uses abblenden standardmäßig an (#621)');
  Assert.IsTrue(APage.RecursionMarkersCheck.Checked, 'Rekursionssymbole standardmäßig an (#623)');
  Assert.AreEqual('4', APage.RecursionMarkersDepthEdit.Text);
  // Datenfluss (#690).
  Assert.IsTrue(APage.DataFlowCheck.Checked, 'navigation.dataFlow (#690)');
  Assert.AreEqual('6', APage.DataFlowMaxDepthEdit.Text);
  Assert.IsFalse(APage.DataFlowExcludeTestsCheck.Checked);
  APage.DataFlowCheck.Checked := False;
  APage.DataFlowMaxDepthEdit.Text := '9';
  APage.DataFlowExcludeTestsCheck.Checked := True;
  Assert.IsTrue(APage.ExitPointsCheck.Checked, 'Austrittspunkte standardmaessig an (#698)');
  Assert.IsTrue(APage.ExitPointsExceptionsCheck.Checked);
  Assert.IsTrue(APage.ExitPointsLoopsCheck.Checked);
  Assert.IsTrue(APage.ExitPointsBadgeCheck.Checked);
  Assert.IsTrue(APage.ReassignedCheck.Checked, 'Unterstreichung standardmaessig an (#712)');
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.Locals).Checked);
  Assert.IsFalse(APage.ReassignedTargetCheck(TAtlasReassignedTarget.LoopVars).Checked);
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams).Checked);
  Assert.IsFalse(APage.ReassignedTargetCheck(TAtlasReassignedTarget.Fields).Checked);
  Assert.AreEqual(0, APage.ReassignedStyleBox.Choice, 'gepunktet');
  Assert.AreEqual('theme', APage.ReassignedColorEdit.Text);
  Assert.IsTrue(APage.ExpressionTypeCheck.Checked, 'Typ des Ausdrucks standardmaessig an (#689)');
  Assert.IsTrue(APage.ExpressionTypeConversionsCheck.Checked);
  Assert.IsTrue(APage.ExpressionTypeConstValueCheck.Checked);
  Assert.AreEqual(ShortCutToText($6054), APage.ExpressionTypeKey.Text);
  Assert.AreEqual(0, APage.MethodPlacementBox.Choice, 'Methoden wie die Deklaration (#660)');
end;

/// <summary>Vorgaben und Änderungen: Atlas-Spalte, gleicher Text, Blockkommentar.</summary>
procedure EditHideElementSelection(APage: TAtlasSettingsPage);
begin
  // Atlas-Spalte in der Zeilenleiste (#768).
  Assert.IsTrue(APage.GutterColumnCheck.Checked, 'Atlas-Spalte standardmäßig an (#768)');
  Assert.IsTrue(APage.GutterColumnProblemsCheck.Checked);
  Assert.IsTrue(APage.GutterColumnCodeActionsCheck.Checked);
  Assert.IsTrue(APage.GutterColumnOverridesCheck.Checked);
  APage.GutterColumnCodeActionsCheck.Checked := False;
  APage.GutterColumnOverridesCheck.Checked := False;
  // Gleichen Text hervorheben (#709).
  Assert.IsTrue(APage.SelectionMatchesCheck.Checked, 'gleichen Text hervorheben standardmäßig an (#709)');
  Assert.AreEqual('3', APage.SelectionMatchesMinLength.Text);
  Assert.IsFalse(APage.SelectionMatchesCaseSensitiveCheck.Checked);
  Assert.IsFalse(APage.SelectionMatchesWholeWordCheck.Checked);
  Assert.IsTrue(APage.SelectionMatchesNavigateF3Check.Checked);
  Assert.AreEqual('1000', APage.SelectionMatchesMaxMatches.Text);
  APage.SelectionMatchesMinLength.Text := '4';
  APage.SelectionMatchesWholeWordCheck.Checked := True;
  APage.SelectionMatchesNavigateF3Check.Checked := False;
  APage.SelectionMatchesMaxMatches.Text := '50';
  // Blockkommentar umschalten (#703).
  Assert.IsTrue(APage.ToggleBlockComment.Checked, 'Blockkommentar umschalten standardmäßig an (#703)');
  Assert.AreEqual(ShortCutToText($A041), APage.ToggleBlockCommentKey.Text);
  Assert.AreEqual(0, APage.ToggleBlockCommentStyle.Choice);
  Assert.AreEqual(0, APage.ToggleBlockCommentFallback.Choice);
  Assert.IsFalse(APage.ToggleBlockCommentOwnLines.Checked);
  Assert.AreEqual(0, APage.ToggleBlockCommentScope.Choice);
  APage.ToggleBlockCommentStyle.Choice := 1;
  APage.ToggleBlockCommentFallback.Choice := 1;
  APage.ToggleBlockCommentOwnLines.Checked := True;
  APage.ToggleBlockCommentScope.Choice := 1;
end;

/// <summary>Vorgaben und Änderungen: Zeilen, Umschließen, Löschen, Fehlertext, Abschalten.</summary>
procedure EditHideElementCommands(APage: TAtlasSettingsPage);
begin
  // Neue Zeile ober- oder unterhalb (#700).
  Assert.IsTrue(APage.NewLineAround.Checked, 'Neue Zeile ober-/unterhalb standardmäßig an (#700)');
  Assert.AreEqual(ShortCutToText($200D), APage.NewLineBelowKey.Text);
  Assert.AreEqual(ShortCutToText($C00D), APage.NewLineAboveKey.Text);
  Assert.IsTrue(APage.NewLineAroundStatementAware.Checked);
  APage.NewLineAroundStatementAware.Checked := False;
  // Umschließung entfernen (#657).
  Assert.IsTrue(APage.Unwrap.Checked, 'Umschließung entfernen standardmäßig an (#657)');
  Assert.AreEqual(ShortCutToText($602E), APage.UnwrapKey.Text);
  APage.Unwrap.Checked := False;
  // Sicher löschen (#716).
  Assert.IsTrue(APage.SafeDelete.Checked, 'Sicher löschen standardmäßig an (#716)');
  Assert.AreEqual(ShortCutToText($802E), APage.SafeDeleteKey.Text);
  APage.SafeDelete.Checked := False;
  // Markierung beim Tippen umschließen (#672).
  Assert.IsTrue(APage.WrapSelection.Checked, 'Umschließen standardmäßig an (#672)');
  Assert.AreEqual('([{''', APage.WrapSelectionChars.Text);
  APage.WrapSelectionChars.Text := ' ([<';
  // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
  Assert.AreEqual(1, APage.InlineDiagnostics.Choice, 'nur Fehler');
  Assert.IsTrue(APage.ProblemsStatusCounterCheck.Checked);
  Assert.AreEqual(ShortCutToText($C077), APage.NextProblemKey.Text);
  APage.BlockEndLabelsCheck.Checked := False;
  APage.DimUnusedUsesCheck.Checked := False;
  APage.RecursionMarkersCheck.Checked := False;
  APage.RecursionMarkersDepthEdit.Text := '2';
  APage.ExitPointsCheck.Checked := False;
  APage.ExitPointsBadgeCheck.Checked := False;
  APage.ReassignedCheck.Checked := False;
  APage.ReassignedTargetCheck(TAtlasReassignedTarget.ValueParams).Checked := False;
  APage.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams).Checked := True;
  APage.ReassignedStyleBox.Choice := 1;
  APage.ReassignedColorEdit.Text := 'rot';
  APage.ExpressionTypeCheck.Checked := False;
  APage.ExpressionTypeConstValueCheck.Checked := False;
  APage.ExpressionTypeKey.Text := '';
  APage.MethodPlacementBox.Choice := 2;
  APage.InlineDiagnostics.Choice := 2;
  APage.ProblemsStatusCounterCheck.Checked := False;
  APage.PreviousProblemKey.Text := '';
  APage.BlockEndLabelsMinLinesEdit.Text := '30';
  APage.HideElementKey.Text := '';
end;

/// <summary>Gespeichert: Blockende, Datenfluss, Austrittspunkte, Unterstreichung, Ausdruckstyp, Spalte.</summary>
procedure AssertHideElementSavedMarkers(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsFalse(ASaved.BlockEndLabels, 'abschaltbar');
  Assert.AreEqual(30, ASaved.BlockEndLabelsMinLines);
  Assert.IsFalse(ASaved.DimUnusedUses);
  Assert.IsFalse(ASaved.RecursionMarkers);
  Assert.AreEqual(2, ASaved.RecursionMarkersDepth);
  Assert.IsFalse(ASaved.DataFlow);
  Assert.AreEqual(9, ASaved.DataFlowMaxDepth);
  Assert.IsTrue(ASaved.DataFlowExcludeTests);
  Assert.IsFalse(ASaved.ExitPoints);
  Assert.IsTrue(ASaved.ExitPointsExceptions);
  Assert.IsTrue(ASaved.ExitPointsLoops);
  Assert.IsFalse(ASaved.ExitPointsBadge);
  Assert.IsFalse(ASaved.Reassigned);
  Assert.AreEqual('locals,varParams', ASaved.ReassignedTargets);
  Assert.AreEqual('solid', ASaved.ReassignedStyle);
  Assert.AreEqual('theme', ASaved.ReassignedColor, 'Unlesbares wird theme');
  Assert.IsFalse(ASaved.ExpressionType);
  Assert.IsTrue(ASaved.ExpressionTypeConversions);
  Assert.IsFalse(ASaved.ExpressionTypeConstValue);
  Assert.AreEqual('off', ASaved.MethodPlacement, 'Methodenreihenfolge abschaltbar');
  Assert.AreEqual(0, ASaved.ExpressionTypeKey, 'leer = kein Kuerzel');
  Assert.IsTrue(ASaved.GutterColumn);
  Assert.IsTrue(ASaved.GutterColumnProblems);
  Assert.IsFalse(ASaved.GutterColumnCodeActions);
  Assert.IsFalse(ASaved.GutterColumnOverrides);
end;

/// <summary>Gespeichert: gleicher Text, Blockkommentar, Zeilen, Umschließen, Löschen, Fehlertext.</summary>
procedure AssertHideElementSavedEditing(const ASaved: TAtlasPluginSettings);
begin
  Assert.IsTrue(ASaved.SelectionMatches);
  Assert.AreEqual(4, ASaved.SelectionMatchesMinLength);
  Assert.IsFalse(ASaved.SelectionMatchesCaseSensitive);
  Assert.IsTrue(ASaved.SelectionMatchesWholeWord);
  Assert.IsFalse(ASaved.SelectionMatchesNavigateF3);
  Assert.AreEqual(50, ASaved.SelectionMatchesMaxMatches);
  Assert.IsTrue(ASaved.ToggleBlockComment);
  Assert.AreEqual($A041, ASaved.ToggleBlockCommentKey);
  Assert.AreEqual('parens', ASaved.ToggleBlockCommentStyle);
  Assert.AreEqual('refuse', ASaved.ToggleBlockCommentFallback);
  Assert.IsTrue(ASaved.ToggleBlockCommentOwnLines);
  Assert.AreEqual('line', ASaved.ToggleBlockCommentWithoutSelection);
  Assert.IsTrue(ASaved.NewLineAround);
  Assert.AreEqual($200D, ASaved.NewLineBelowKey);
  Assert.AreEqual($C00D, ASaved.NewLineAboveKey);
  Assert.IsFalse(ASaved.NewLineAroundStatementAware);
  Assert.IsFalse(ASaved.Unwrap);
  Assert.AreEqual($602E, ASaved.UnwrapKey);
  Assert.IsFalse(ASaved.SafeDelete);
  Assert.AreEqual($802E, ASaved.SafeDeleteKey);
  Assert.IsTrue(ASaved.WrapSelection);
  Assert.AreEqual('([<', ASaved.WrapSelectionChars);
  Assert.AreEqual('errorsAndWarnings', ASaved.InlineDiagnostics);
  Assert.IsFalse(ASaved.ProblemsStatusCounter);
  Assert.AreEqual($C077, ASaved.NextProblemKey);
  Assert.AreEqual(0, ASaved.PreviousProblemKey);
  Assert.AreEqual(0, ASaved.HideElementKey, 'leer = keine Taste');
end;

/// <summary>Seite nach erneutem Laden.</summary>
procedure AssertHideElementReloaded(APage: TAtlasSettingsPage);
begin
  Assert.IsFalse(APage.BlockEndLabelsCheck.Checked);
  Assert.IsFalse(APage.DimUnusedUsesCheck.Checked);
  Assert.IsFalse(APage.RecursionMarkersCheck.Checked);
  Assert.IsFalse(APage.ExitPointsCheck.Checked);
  Assert.IsFalse(APage.ExitPointsBadgeCheck.Checked);
  Assert.IsFalse(APage.ReassignedCheck.Checked);
  Assert.IsTrue(APage.ReassignedTargetCheck(TAtlasReassignedTarget.VarParams).Checked);
  Assert.AreEqual(1, APage.ReassignedStyleBox.Choice);
  Assert.IsFalse(APage.ExpressionTypeCheck.Checked);
  Assert.IsFalse(APage.ExpressionTypeConstValueCheck.Checked);
  Assert.IsFalse(APage.GutterColumnOverridesCheck.Checked);
  Assert.IsTrue(APage.SelectionMatchesWholeWordCheck.Checked);
  Assert.AreEqual(1, APage.ToggleBlockCommentScope.Choice);
  Assert.AreEqual(2, APage.InlineDiagnostics.Choice);
  Assert.AreEqual('', APage.HideElementKey.Text);
end;

procedure TAtlasSettingsPageTests.HideElementRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    EditHideElementMarkers(Page);
    EditHideElementSelection(Page);
    EditHideElementCommands(Page);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    AssertHideElementSavedMarkers(Saved);
    AssertHideElementSavedEditing(Saved);
    Page.LoadFrom(Saved);
    AssertHideElementReloaded(Page);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.GenerateMenuRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.GenerateMenuCheck.Checked, 'standardmäßig an');
    Assert.AreEqual(ShortCutToText($802D), Page.GenerateMenuKey.Text, 'Alt+Einfg');
    Assert.AreEqual('generate,surround,templates', Page.GenerateMenuGroups.Text);
    Assert.AreEqual('', Page.GenerateMenuHidden.Text);
    Assert.IsTrue(Page.GenerateMenuRecentFirstCheck.Checked);
    Assert.IsTrue(Page.GenerateMenuShowCommandNamesCheck.Checked);
    Page.GenerateMenuCheck.Checked := False;
    Page.GenerateMenuKey.Text := '';
    Page.GenerateMenuGroups.Text := 'templates';
    Page.GenerateMenuHidden.Text := '/json';
    Page.GenerateMenuRecentFirstCheck.Checked := False;
    Page.GenerateMenuShowCommandNamesCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.GenerateMenu, 'abschaltbar');
    Assert.AreEqual(0, Saved.GenerateMenuKey, 'leer = keine Taste');
    Assert.AreEqual('templates', Saved.GenerateMenuGroups);
    Assert.AreEqual('/json', Saved.GenerateMenuHidden);
    Assert.IsFalse(Saved.GenerateMenuRecentFirst);
    Assert.IsFalse(Saved.GenerateMenuShowCommandNames);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.GenerateMenuCheck.Checked);
    Assert.AreEqual('/json', Page.GenerateMenuHidden.Text);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.BookmarksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.BookmarksNamedCheck.Checked, 'Lesezeichen standardmäßig an');
    Assert.IsFalse(Page.BookmarksSharedCheck.Checked, 'standardmäßig lokal');
    Assert.AreEqual(ShortCutToText($C04B), Page.BookmarkKey.Text, 'Strg+Alt+K');
    Page.BookmarksNamedCheck.Checked := False;
    Page.BookmarksSharedCheck.Checked := True;
    Page.BookmarkKey.Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BookmarksNamed, 'abschaltbar');
    Assert.IsTrue(Saved.BookmarksShared);
    Assert.AreEqual(0, Saved.BookmarkKey, 'leer = keine Taste');
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.BookmarksNamedCheck.Checked);
    Assert.IsTrue(Page.BookmarksSharedCheck.Checked);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ExperimentalSwitchRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Assert.IsFalse(Settings.ExperimentalEnabled);
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.ExperimentalEnabled.Checked);
    Assert.IsNotNull(Page.Filter);
    Assert.AreEqual(0, Page.Filter.Choice);
    // Ohne experimentelle Einstellung im Katalog kein Hinweis.
    Assert.AreEqual(Page.Marks.HasExperimental, Page.ExperimentalBanner.Visible);
    Page.ExperimentalEnabled.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.ExperimentalEnabled);
    Page.LoadFrom(Saved);
    Assert.IsTrue(Page.ExperimentalEnabled.Checked);
    Assert.IsFalse(Page.ExperimentalBanner.Visible);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.FilterHidesAndRestoresRows;
var
  Owner: TComponent;
  Box: TScrollBox;
  Marks: TAtlasSettingsMarks;
  First, Second, Third: TCheckBox;

  function Check(const ACaption: string; ATop: Integer): TCheckBox;
  begin
    Result := TCheckBox.Create(Owner);
    Result.Parent := Box;
    Result.Caption := ACaption;
    Result.Top := ATop;
  end;

begin
  Owner := TComponent.Create(nil);
  try
    Box := TScrollBox.Create(Owner);
    Marks := TAtlasSettingsMarks.Create(Owner);
    First := Check('Erste', 10);
    Second := Check('Zweite', 40);
    Third := Check('Dritte', 70);
    Marks.Bind(First, ['First']);
    Marks.Bind(Second, ['Second']);
    Marks.Bind(Third, ['Third']);
    Marks.MarkExperimental(['third']);
    Assert.IsTrue(Marks.HasExperimental);
    Assert.IsTrue(Marks.IsExperimental(Third));
    Assert.IsFalse(Marks.IsExperimental(First));
    Assert.AreEqual('Dritte  [' + TAtlasStrings.Text(TAtlasTextId.SettingsExperimentalTag) + ']', string(Third.Caption));
    Marks.ApplyFilter(sfExperimental);
    Assert.IsFalse(First.Visible);
    Assert.IsFalse(Second.Visible);
    Assert.IsTrue(Third.Visible);
    // Rückt an den Platz der ersten Zeile.
    Assert.AreEqual(10, Third.Top);
    Marks.Show(['Second'], True);
    Marks.ApplyFilter(sfModified);
    Assert.IsFalse(First.Visible);
    Assert.IsTrue(Second.Visible);
    Assert.IsFalse(Third.Visible);
    Assert.AreEqual(10, Second.Top);
    Marks.ApplyFilter(sfAll);
    Assert.IsTrue(First.Visible and Second.Visible and Third.Visible);
    Assert.AreEqual(10, First.Top);
    Assert.AreEqual(40, Second.Top);
    Assert.AreEqual(70, Third.Top);
    Assert.IsTrue(Marks.Filter = sfAll);
  finally
    Owner.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SafeModeRoundTrips;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #722: Rückfrage, ohne Rückfrage nach zwei Abstürzen, Taste, Zeitlimit, gemerkte Stände.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.SafeAskAfterCrash := False;
  Settings.SafeStartupKey := 'ctrl';
  Settings.SafeStartupTimeoutMs := 20000;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.SafeAsk.Checked);
    Assert.IsTrue(Page.SafeAuto.Checked);
    Assert.AreEqual(1, Page.SafeKey.Choice);
    Assert.AreEqual('20000', Page.SafeTimeout.Text);
    Assert.AreEqual('5', Page.SafeHistory.Text);
    Page.SafeAuto.Checked := False;
    Page.SafeKey.Choice := 2;
    Page.SafeHistory.Text := '500';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.SafeAskAfterCrash);
    Assert.IsFalse(Saved.SafeAutoAfterRepeatedCrash);
    Assert.AreEqual('none', Saved.SafeStartupKey);
    Assert.AreEqual(20000, Saved.SafeStartupTimeoutMs);
    // Begrenzt auf die Höchstzahl.
    Assert.AreEqual(TAtlasPluginSettings.MaxSafeSettingsHistory, Saved.SafeKeepSettingsHistory);
  finally
    Page.Free;
  end;
end;

type
  /// <summary>Hält fest, was die Seite „Versionsverwaltung“ über ihre Ereignisse angefragt hat.</summary>
  TVcsPageProbe = class
  public
    FLocated: string;
    FCheckedKind: TAtlasVcsKind;
    FCheckedPath: string;
    FProjectCalls: Integer;
  end;

/// <summary>Werkzeugpfad lokalisieren: leer = bekannter Ordner, sonst fehlt die angegebene Datei.</summary>
function LocateVcsTool(const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasVcsToolLocation.Empty;
  Result.Configured := APath;
  if APath = '' then
  begin
    Result.Executable := 'C:\Program Files\Git\cmd\git.exe';
    Result.Source := TAtlasVcsToolSource.KnownDir;
  end
  else
  begin
    Result.Source := TAtlasVcsToolSource.ConfiguredMissing;
  end;
end;

/// <summary>Hängt die Ereignisse der Seite an AProbe.</summary>
procedure WireVcsPage(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe);
begin
  AProbe.FCheckedKind := TAtlasVcsKind.None;
  APage.OnVcsLocate :=
    function(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation
    begin
      AProbe.FLocated := APath;
      Result := LocateVcsTool(APath);
    end;
  APage.OnVcsCheck :=
    procedure(AKind: TAtlasVcsKind; const APath: string)
    begin
      AProbe.FCheckedKind := AKind;
      AProbe.FCheckedPath := APath;
    end;
  APage.OnVcsProject :=
    procedure
    begin
      Inc(AProbe.FProjectCalls);
    end;
end;

/// <summary>Steuerelemente der Seite: Lage im Baum und geladene Werte (#1285, #1288, #1290–#1292).</summary>
procedure AssertVcsPageControls(APage: TAtlasSettingsPage; AVcs: TTabSheet);
begin
  Assert.IsTrue(SheetOf(APage.VcsPath(TAtlasVcsKind.Git)) = AVcs);
  Assert.IsTrue(SheetOf(APage.VcsPath(TAtlasVcsKind.Svn)) = AVcs);
  Assert.IsTrue(SheetOf(APage.VcsTimeout) = AVcs);
  Assert.IsTrue(SheetOf(APage.VcsProjectInfo) = AVcs);
  Assert.AreEqual(2, APage.VcsProviderChoice.Choice, 'svn');
  Assert.AreEqual('D:\Tools\svn.exe', APage.VcsPath(TAtlasVcsKind.Svn).Text);
  Assert.AreEqual('45', APage.VcsTimeout.Text);
  // #1288: Dialog „Branch anlegen“ bei „Beginnen“, Unterknoten vcs.branches (Schema).
  Assert.IsTrue(SheetOf(APage.VcsBranchConfirm) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(APage.VcsBranchConfirm.Checked);
  // #1290: SVN-Gruppe auf derselben Seite, Vorgaben aus den Einstellungen.
  Assert.IsTrue(SheetOf(APage.VcsBranchSvnLocation) = APage.NodeSheet('vcs.branches'));
  Assert.IsTrue(SheetOf(APage.VcsBranchSvnMessage) = APage.NodeSheet('vcs.branches'));
  Assert.AreEqual('{projektwurzel}/branches/{name}', APage.VcsBranchSvnLocation.Text);
  Assert.AreEqual(0, APage.VcsBranchSvnSource.Choice, 'head');
  Assert.AreEqual(0, APage.VcsBranchSvnAfter.Choice, 'switch');
  Assert.AreEqual('..\{projekt}-{kennung}', APage.VcsBranchSvnFolder.Text);
  // #1291: Gruppe „Externals“ auf derselben Seite, Regeln als Zeilen; ungültige Zeile mit Hinweis.
  Assert.IsTrue(SheetOf(APage.VcsExternalsRules) = APage.NodeSheet('vcs.externals'));
  Assert.AreEqual(0, APage.VcsExternalsOnBranch.Choice, 'pin');
  Assert.AreEqual(0, APage.VcsExternalsSuggest.Choice, 'modified');
  Assert.AreEqual('', APage.VcsExternalsRules.Text);
  APage.VcsExternalsRules.Text := '^/Packages/Basis = fragen';
  APage.VcsExternalsRules.OnChange(APage.VcsExternalsRules);
  Assert.Contains(APage.VcsExternalsRulesError.Caption, '^/Packages/Basis = fragen');
  APage.VcsExternalsRules.Text := '^/Packages/Basis = keep';
  APage.VcsExternalsRules.OnChange(APage.VcsExternalsRules);
  Assert.AreEqual('', APage.VcsExternalsRulesError.Caption);
  // #1292: Arbeitskopien und Aktualisieren auf derselben Seite.
  Assert.IsTrue(SheetOf(APage.VcsExternalsShow) = APage.NodeSheet('vcs.externals'));
  Assert.IsTrue(APage.VcsExternalsShow.Checked);
  Assert.AreEqual(0, APage.VcsExternalsUpdate.Choice, 'with');
end;

/// <summary>Pfad ändern prüft nur die Datei; „Prüfen“ fragt im Hintergrund und sperrt den Knopf bis zum
/// Ergebnis.</summary>
procedure AssertVcsToolChecks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe);
var
  mCheck: TAtlasVcsToolCheck;
begin
  APage.VcsPath(TAtlasVcsKind.Git).Text := 'X:\fehlt\git.exe';
  APage.VcsPath(TAtlasVcsKind.Git).OnChange(APage.VcsPath(TAtlasVcsKind.Git));
  Assert.AreEqual('X:\fehlt\git.exe', AProbe.FLocated);
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Git).Caption, 'X:\fehlt\git.exe');
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.None, 'Prüfen erst auf Klick');
  APage.VcsPath(TAtlasVcsKind.Git).Text := '';
  APage.VcsPath(TAtlasVcsKind.Git).OnChange(APage.VcsPath(TAtlasVcsKind.Git));
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Git).Caption, 'C:\Program Files\Git\cmd\git.exe');
  APage.VcsCheckButton(TAtlasVcsKind.Svn).Click;
  Assert.IsTrue(AProbe.FCheckedKind = TAtlasVcsKind.Svn);
  Assert.AreEqual('D:\Tools\svn.exe', AProbe.FCheckedPath);
  Assert.IsFalse(APage.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Svn, TAtlasVcsToolLocation.Empty);
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'svn 1.14.3';
  mCheck.Location.Executable := 'D:\Tools\svn.exe';
  mCheck.Location.Source := TAtlasVcsToolSource.Configured;
  APage.VcsCheckDone(mCheck);
  Assert.IsTrue(APage.VcsCheckButton(TAtlasVcsKind.Svn).Enabled);
  Assert.Contains(APage.VcsState(TAtlasVcsKind.Svn).Caption, 'svn 1.14.3');
end;

/// <summary>Aktuelles Projekt: einmal beim ersten Zeigen der Seite; Links auf die steuernden Seiten.</summary>
procedure AssertVcsProjectAndLinks(APage: TAtlasSettingsPage; AProbe: TVcsPageProbe; const AAreas: TArray<TTreeNode>);
var
  mVcs: TTabSheet;
  mState: TAtlasVcsProjectState;
begin
  mVcs := SheetOf(APage.VcsProviderChoice);
  APage.Navigation.OnChange(APage.Navigation, AAreas[17]);
  Assert.IsTrue(APage.Pages.ActivePage = mVcs);
  Assert.AreEqual(1, AProbe.FProjectCalls);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectQuerying), APage.VcsProjectInfo.Caption);
  APage.Navigation.OnChange(APage.Navigation, AAreas[0]);
  APage.Navigation.OnChange(APage.Navigation, AAreas[17]);
  Assert.AreEqual(1, AProbe.FProjectCalls, 'nur einmal je Öffnen');
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.NoWorkingCopy;
  APage.VcsProjectDone(mState);
  Assert.Contains(APage.VcsProjectInfo.Caption, 'Kasse.dproj');
  APage.VcsLinkWelcome.Click;
  // Ohne das Modul Willkommensseite die Seite seines Schalters (#1456).
  Assert.IsTrue(APage.Pages.ActivePage = SheetOf(APage.ControlOfSetting('WelcomePage')));
  APage.VcsLinkIssues.Click;
  Assert.IsTrue(APage.Pages.ActivePage = SheetOf(APage.ControlOfSetting('IssuesEnabled')));
  APage.VcsLinkEditor.Click;
  Assert.IsFalse(APage.Pages.ActivePage = mVcs, 'Editor-Seite mit Git-Rand');
end;

/// <summary>Alle Werte der Seite ändern.</summary>
procedure EditVcsPage(APage: TAtlasSettingsPage);
begin
  APage.VcsProviderChoice.Choice := 1;
  APage.VcsPath(TAtlasVcsKind.Git).Text := '  D:\Git\git.exe ';
  APage.VcsTimeout.Text := '120';
  APage.VcsBranchConfirm.Checked := False;
  APage.VcsBranchSvnLocation.Text := '^/branches/{kennung}';
  APage.VcsBranchSvnSource.Choice := 1;
  APage.VcsBranchSvnAfter.Choice := 1;
  APage.VcsBranchSvnFolder.Text := 'D:\Branches\{name}';
  APage.VcsBranchSvnMessage.Text := 'Neu: {kennung}';
  APage.VcsExternalsOnBranch.Choice := 2;
  APage.VcsExternalsSuggest.Choice := 2;
  APage.VcsExternalsShow.Checked := False;
  APage.VcsExternalsUpdate.Choice := 1;
end;

/// <summary>Speichern; eine ungültige Regelzeile lässt die bisherigen Regeln stehen.</summary>
procedure AssertVcsPageSaved(APage: TAtlasSettingsPage; var ASaved: TAtlasPluginSettings);
begin
  APage.SaveTo(ASaved);
  Assert.IsFalse(ASaved.VcsExternalsShow);
  Assert.AreEqual('without', ASaved.VcsExternalsUpdate);
  Assert.AreEqual('ask', ASaved.VcsExternalsOnBranch);
  Assert.AreEqual('always', ASaved.VcsExternalsSuggestBranch);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', ASaved.VcsExternalsRules);
  APage.VcsExternalsRules.Text := '^/Packages/Basis = keep'#13#10'kaputt';
  APage.SaveTo(ASaved);
  Assert.AreEqual('[{"source": "^/Packages/Basis", "onBranch": "keep"}]', ASaved.VcsExternalsRules);
  APage.LoadFrom(ASaved);
  Assert.AreEqual('^/Packages/Basis = keep', APage.VcsExternalsRules.Text);
  Assert.AreEqual(2, APage.VcsExternalsOnBranch.Choice);
  APage.SaveTo(ASaved);
  Assert.IsFalse(ASaved.VcsBranchConfirm);
  Assert.AreEqual('^/branches/{kennung}', ASaved.VcsBranchSvnLocation);
  Assert.AreEqual('workingCopy', ASaved.VcsBranchSvnSource);
  Assert.AreEqual('checkout', ASaved.VcsBranchSvnAfter);
  Assert.AreEqual('D:\Branches\{name}', ASaved.VcsBranchSvnCheckoutFolder);
  Assert.AreEqual('Neu: {kennung}', ASaved.VcsBranchSvnMessage);
  Assert.AreEqual('git', ASaved.VcsProvider);
  Assert.AreEqual('D:\Git\git.exe', ASaved.VcsGitPath);
  Assert.AreEqual('D:\Tools\svn.exe', ASaved.VcsSvnPath);
  Assert.AreEqual(120, ASaved.VcsTimeoutSeconds);
end;

procedure TAtlasSettingsPageTests.VcsPageLocatesChecksAndShowsProject;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mAreas: TArray<TTreeNode>;
  mVcs: TTabSheet;
  mSettings, mSaved: TAtlasPluginSettings;
  mProbe: TVcsPageProbe;
begin
  TAtlasSettingsPage.ForgetTreeState;
  mProbe := TVcsPageProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireVcsPage(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProvider := 'svn';
    mSettings.VcsSvnPath := 'D:\Tools\svn.exe';
    mSettings.VcsTimeoutSeconds := 45;
    mPage.LoadFrom(mSettings);
    mVcs := SheetOf(mPage.VcsProviderChoice);
    Assert.IsNotNull(mVcs);
    mAreas := TopLevelNodes(mPage);
    // Mit Punkt: svn, Pfad und Zeitlimit weichen von der Vorgabe ab.
    Assert.AreEqual(TAtlasSettingsMarks.Dot + TAtlasStrings.Text(TAtlasTextId.SettingsTabVcs), mAreas[17].Text,
      'eigener Bereich');
    AssertVcsPageControls(mPage, mVcs);
    Assert.AreEqual(0, mProbe.FProjectCalls, 'kein Prozess, solange die Seite nicht gezeigt wurde');
    AssertVcsToolChecks(mPage, mProbe);
    AssertVcsProjectAndLinks(mPage, mProbe, mAreas);
    EditVcsPage(mPage);
    mSaved := mSettings;
    AssertVcsPageSaved(mPage, mSaved);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;

/// <summary>Texte zu Fundort und Prüfung des Werkzeugs.</summary>
procedure AssertVcsToolTexts;
var
  mLocation: TAtlasVcsToolLocation;
  mCheck: TAtlasVcsToolCheck;
  mText: string;
begin
  mLocation := TAtlasVcsToolLocation.Empty;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolMissing),
    TAtlasSettingsPage.VcsLocationText(mLocation));
  mLocation.Source := TAtlasVcsToolSource.ConfiguredMissing;
  mLocation.Configured := 'X:\git.exe';
  Assert.Contains(TAtlasSettingsPage.VcsLocationText(mLocation), 'X:\git.exe');
  mLocation.Source := TAtlasVcsToolSource.Path;
  mLocation.Executable := 'C:\Git\cmd\git.exe';
  mText := TAtlasSettingsPage.VcsLocationText(mLocation);
  Assert.Contains(mText, 'C:\Git\cmd\git.exe');
  Assert.Contains(mText, TAtlasSettingsPage.VcsSourceText(TAtlasVcsToolSource.Path));
  mCheck := TAtlasVcsToolChecks.Missing(TAtlasVcsKind.Git, mLocation);
  mCheck.State := TAtlasVcsToolState.StartFailed;
  mCheck.ExitCode := 128;
  Assert.Contains(TAtlasSettingsPage.VcsCheckText(mCheck), '128');
  mCheck.State := TAtlasVcsToolState.NoAnswer;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsToolNoAnswer), TAtlasSettingsPage.VcsCheckText(mCheck));
  mCheck.State := TAtlasVcsToolState.Found;
  mCheck.Version := 'git version 2.47.1';
  mText := TAtlasSettingsPage.VcsCheckText(mCheck);
  Assert.Contains(mText, 'git version 2.47.1');
  Assert.Contains(mText, 'C:\Git\cmd\git.exe');
end;

/// <summary>#1287: Zustände der Tabelle „Server“.</summary>
procedure AssertVcsServerTexts;
var
  mServer: TAtlasVcsServerCheck;
begin
  // #1287: Zustände der Tabelle „Server“.
  mServer := TAtlasVcsServerCheck.Empty;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking),
    TAtlasSettingsPage.VcsServerStateText(mServer, True));
  mServer.State := TAtlasVcsServerState.Reachable;
  mServer.CheckedAt := EncodeTime(14, 5, 0, 0);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['14:05']),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.LoginNeeded;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.Unreachable;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnreachable),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.NoServer;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerNoServer),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
  mServer.State := TAtlasVcsServerState.ToolMissing;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerToolMissing),
    TAtlasSettingsPage.VcsServerStateText(mServer, False));
end;

procedure TAtlasSettingsPageTests.VcsTexts;
var
  mState: TAtlasVcsProjectState;
  mText: string;
begin
  AssertVcsToolTexts;
  mState := TAtlasVcsProjectState.Empty;
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectNone), TAtlasSettingsPage.VcsProjectText(mState));
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.Ok;
  mState.WorkingCopy.Kind := TAtlasVcsKind.Git;
  mState.WorkingCopy.Root := 'C:\Projekte\Kasse';
  mState.Head.Branch := 'feature/42-kasse';
  mState.Head.Revision := '1979e3d795214220705682d5b0b63c8f3b7e66d7';
  mState.Head.Upstream := 'origin/feature/42-kasse';
  mText := TAtlasSettingsPage.VcsProjectText(mState);
  Assert.Contains(mText, 'Kasse.dproj');
  Assert.Contains(mText, 'C:\Projekte\Kasse');
  Assert.Contains(mText, 'feature/42-kasse');
  Assert.Contains(mText, 'origin/feature/42-kasse');
  Assert.Contains(mText, TAtlasStrings.Text(TAtlasTextId.SettingsVcsSourceSetting), 'Herkunft der Art');
  mState.Source := TAtlasVcsProviderSource.Project;
  mState.SourceMatch := 'C:\Projekte\Kasse\Kasse.groupproj';
  Assert.Contains(TAtlasSettingsPage.VcsProjectText(mState), 'Kasse.groupproj');
  // #1286: Hauptbranch aus Zeile oder .atlas.
  Assert.DoesNotContain(TAtlasSettingsPage.VcsProjectText(mState),
    TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, ['develop']));
  mState.MainBranch := 'develop';
  Assert.Contains(TAtlasSettingsPage.VcsProjectText(mState),
    TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsProjectMainBranch, ['develop']));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), TAtlasSettingsPage.VcsProviderCaption('SVN'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), TAtlasSettingsPage.VcsProviderCaption(''));
  AssertVcsServerTexts;
end;

/// <summary>Kontext: Projekt und Gruppe Kasse, eine Zeile aus der .atlas.</summary>
procedure WireKasseTeamContext(APage: TAtlasSettingsPage);
begin
  APage.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := TAtlasVcsProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
      Result.Team := [TAtlasVcsProjectMapping.FromTeamFile('C:\Projekte\Kasse\Kasse.dproj', '', 'develop')];
    end;
end;

/// <summary>Persönliche Zeile vor der aus der .atlas; diese nur ansehen.</summary>
procedure AssertVcsProjectRows(APage: TAtlasSettingsPage; AList: TListView);
begin
  // Persönliche Zeile vor der aus der .atlas; die .atlas gewinnt für Kasse.
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('C:\Projekte', AList.Items[0].Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderSvn), AList.Items[0].SubItems[0]);
  Assert.AreEqual('trunk', AList.Items[0].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectCovered), AList.Items[0].SubItems[2]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderAuto), AList.Items[1].SubItems[0]);
  Assert.AreEqual('develop', AList.Items[1].SubItems[1]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectTeam), AList.Items[1].SubItems[2]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsCoveredHint), APage.VcsProjectNote.Caption);
  Assert.IsTrue(APage.VcsProjectMatch.Enabled);
  // Zeile aus der .atlas: nur ansehen.
  AList.Items[1].Selected := True;
  Assert.IsFalse(APage.VcsProjectMatch.Enabled);
  Assert.IsFalse(APage.VcsProjectProvider.Enabled);
  Assert.IsFalse(APage.VcsProjectRemove.Enabled);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectReadOnly), APage.VcsProjectNote.Caption);
end;

/// <summary>Aktuelles Projekt übernehmen, Hauptbranch prüfen, doppelten Pfad abweisen.</summary>
procedure EditVcsProjectRows(APage: TAtlasSettingsPage; AList: TListView);
var
  mState: TAtlasVcsProjectState;
begin
  // „Aktuelles Projekt“: die geöffnete Gruppe, Art aus der letzten Abfrage.
  mState := TAtlasVcsProjectState.Empty;
  mState.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
  mState.Outcome := TAtlasVcsOutcome.Ok;
  mState.WorkingCopy.Kind := TAtlasVcsKind.Svn;
  APage.VcsProjectDone(mState);
  APage.VcsProjectAddCurrent.Click;
  Assert.AreEqual(2, Integer(Length(APage.VcsProjects)));
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', APage.VcsProjects[1].Match);
  Assert.AreEqual('svn', APage.VcsProjects[1].Provider);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsGuess), AList.Items[1].SubItems[1]);
  // Hauptbranch: Leerraum wird abgewiesen.
  APage.VcsProjectMainBranch.Text := 'release 1';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProjectsBranchInvalid), APage.VcsProjectNote.Caption);
  Assert.AreEqual('', APage.VcsProjects[1].MainBranch);
  APage.VcsProjectMainBranch.Text := 'branches/develop';
  Assert.AreEqual('branches/develop', APage.VcsProjects[1].MainBranch);
  Assert.AreEqual('branches/develop', AList.Items[1].SubItems[1]);
  // Derselbe Pfad zweimal wird nicht übernommen.
  APage.VcsProjectMatch.Text := 'c:\projekte';
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIssuesProjectMatchTaken), APage.VcsProjectNote.Caption);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', APage.VcsProjects[1].Match);
end;

/// <summary>Nur persönliche Zeilen landen in vcs.projects.</summary>
procedure AssertVcsProjectsSaved(APage: TAtlasSettingsPage; const ASettings: TAtlasPluginSettings);
var
  mSaved: TAtlasPluginSettings;
  mMappings: TArray<TAtlasVcsProjectMapping>;
begin
  mSaved := ASettings;
  APage.SaveTo(mSaved);
  mMappings := TAtlasVcsProjects.Read(mSaved.VcsProjects);
  Assert.AreEqual(2, Integer(Length(mMappings)), mSaved.VcsProjects);
  Assert.AreEqual('C:\Projekte\Kasse\Kasse.groupproj', mMappings[0].Match);
  Assert.AreEqual('branches/develop', mMappings[0].MainBranch);
  Assert.AreEqual('git', mMappings[1].Provider);
  Assert.IsFalse(mSaved.VcsProjects.Contains('Kasse.dproj'), 'Zeile aus der .atlas bleibt dort');
end;

procedure TAtlasSettingsPageTests.VcsProjectsTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mList: TListView;
  mBrowsed: string;
begin
  mBrowsed := '';
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireKasseTeamContext(mPage);
    mPage.OnBrowseProject :=
      function(AFolder: Boolean; out APath: string): Boolean
      begin
        mBrowsed := BoolToStr(AFolder, True);
        APath := 'C:\Projekte\Kasse\Pakete\Basis';
        Result := True;
      end;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte", "provider": "svn", "mainBranch": "trunk"}]';
    mPage.LoadFrom(mSettings);
    mList := mPage.VcsProjectList;
    AssertVcsProjectRows(mPage, mList);
    EditVcsProjectRows(mPage, mList);
    // Paketordner aus SVN-Externals über die Ordnerauswahl, dann Art Git.
    mPage.VcsProjectAddMenu.Items[1].Click;
    Assert.AreEqual('True', mBrowsed);
    Assert.AreEqual(3, Integer(Length(mPage.VcsProjects)));
    Assert.AreEqual('C:\Projekte\Kasse\Pakete\Basis', mPage.VcsProjects[2].Match);
    Assert.AreEqual('auto', mPage.VcsProjects[2].Provider);
    // Zuweisen löst kein OnChange aus (wie bei der Auswahl mit der Maus erst über das Ereignis).
    mPage.VcsProjectProvider.Choice := 1;
    mPage.VcsProjectProvider.OnChange(mPage.VcsProjectProvider);
    Assert.AreEqual('git', mPage.VcsProjects[2].Provider);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsProviderGit), mList.Items[2].SubItems[0]);
    // Entfernen, dann speichern: nur persönliche Zeilen landen in vcs.projects.
    mList.Items[0].Selected := True;
    mPage.VcsProjectRemove.Click;
    Assert.AreEqual(2, Integer(Length(mPage.VcsProjects)));
    AssertVcsProjectsSaved(mPage, mSettings);
  finally
    mHost.Free;
  end;
  mBrowsed := '';
end;

/// <summary>Projekt und Gruppe teilen den Ordner: eine Zeile; dazu der Paketordner (SVN-Externals).</summary>
procedure AssertVcsServerRows(AList: TListView);
begin
  // Aktuelles Projekt und Gruppe teilen den Ordner: eine Zeile; dazu der Paketordner (SVN-Externals).
  Assert.AreEqual(2, AList.Items.Count);
  Assert.AreEqual('Kasse.groupproj', AList.Items[0].Caption);
  Assert.AreEqual('–', AList.Items[0].SubItems[0]);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerUnknown), AList.Items[0].SubItems[1]);
  Assert.AreEqual('Basis', AList.Items[1].Caption);
  Assert.AreEqual('https://svn.firma.local/basis', AList.Items[1].SubItems[0]);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['09:30']), AList.Items[1].SubItems[1]);
end;

/// <summary>Prüfergebnis: Git-Server von Kasse verlangt eine Anmeldung.</summary>
function KasseLoginNeeded: TAtlasVcsServerCheck;
begin
  Result := TAtlasVcsServerCheck.Empty;
  Result.Kind := TAtlasVcsKind.Git;
  Result.Root := 'C:\Projekte\Kasse';
  Result.Remote := 'origin';
  Result.Url := 'https://git.firma.local/kasse.git';
  Result.State := TAtlasVcsServerState.LoginNeeded;
end;

/// <summary>Nach der Anmeldung wartet die Zeile auf die neue Prüfung und wird erreichbar.</summary>
procedure AssertVcsLoginRechecked(APage: TAtlasSettingsPage; AList: TListView; const ACheck: TAtlasVcsServerCheck);
var
  mCheck: TAtlasVcsServerCheck;
begin
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginOpen), APage.VcsServerNote.Caption);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking), AList.Items[0].SubItems[1]);
  mCheck := ACheck;
  mCheck.State := TAtlasVcsServerState.Reachable;
  mCheck.CheckedAt := EncodeTime(10, 0, 0, 0);
  APage.VcsServerDone('C:\Projekte\Kasse', mCheck);
  Assert.AreEqual(TAtlasStrings.Fmt(TAtlasTextId.SettingsVcsServerReachable, ['10:00']), AList.Items[0].SubItems[1]);
  Assert.IsFalse(APage.VcsServerLogin.Enabled);
end;

type
  /// <summary>Hält fest, welche Ordner die Tabelle „Server“ prüfen und anmelden ließ.</summary>
  TVcsServerProbe = class
  public
    FChecked: TArray<string>;
    FLogins: TArray<string>;
  end;

/// <summary>Kontext Kasse, bekannter Zustand des Paketordners, Prüfen und Anmelden über AProbe.</summary>
procedure WireVcsServers(APage: TAtlasSettingsPage; AProbe: TVcsServerProbe);
begin
  APage.OnVcsContext :=
    function: TAtlasVcsProjectContext
    begin
      Result := TAtlasVcsProjectContext.Empty;
      Result.ProjectFile := 'C:\Projekte\Kasse\Kasse.dproj';
      Result.GroupFile := 'C:\Projekte\Kasse\Kasse.groupproj';
    end;
  APage.OnVcsServerState :=
    function(AFolder: string): TAtlasVcsServerCheck
    begin
      Result := TAtlasVcsServerCheck.Empty;
      // Aus der Sitzung: das Paket war schon erreichbar.
      if SameText(AFolder, 'C:\Projekte\Pakete\Basis') then
      begin
        Result.Kind := TAtlasVcsKind.Svn;
        Result.Url := 'https://svn.firma.local/basis';
        Result.State := TAtlasVcsServerState.Reachable;
        Result.CheckedAt := EncodeTime(9, 30, 0, 0);
      end;
    end;
  APage.OnVcsServerCheck :=
    procedure(const AFolder: string)
    begin
      AProbe.FChecked := AProbe.FChecked + [AFolder];
    end;
  APage.OnVcsServerLogin :=
    function(const AFolder: string; const ACheck: TAtlasVcsServerCheck): Boolean
    begin
      AProbe.FLogins := AProbe.FLogins + [AFolder + '|' + ACheck.Remote];
      Result := True;
    end;
end;

procedure TAtlasSettingsPageTests.VcsServersTable;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mList: TListView;
  mCheck: TAtlasVcsServerCheck;
  mProbe: TVcsServerProbe;
begin
  mProbe := TVcsServerProbe.Create;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    WireVcsServers(mPage, mProbe);
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.VcsProjects := '[{"match": "C:\\Projekte\\Kasse\\Kasse.groupproj", "provider": "svn"},' +
      ' {"match": "C:\\Projekte\\Pakete\\Basis", "provider": "svn"}]';
    mPage.LoadFrom(mSettings);
    mList := mPage.VcsServerList;
    AssertVcsServerRows(mList);
    Assert.AreEqual(0, Integer(Length(mProbe.FChecked)), 'ohne Klick kein Netzzugriff');
    Assert.IsFalse(mPage.VcsServerLogin.Enabled);
    // Prüfen der gewählten Zeile.
    mPage.VcsServerCheck.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Kasse', mProbe.FChecked[0]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerChecking), mList.Items[0].SubItems[1]);
    Assert.IsFalse(mPage.VcsServerCheck.Enabled, 'läuft schon');
    mCheck := KasseLoginNeeded;
    mPage.VcsServerDone('c:\projekte\kasse', mCheck);
    Assert.AreEqual('origin · git.firma.local', mList.Items[0].SubItems[0]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsVcsServerLoginNeeded), mList.Items[0].SubItems[1]);
    Assert.IsTrue(mPage.VcsServerLogin.Enabled, 'Anmelden bei „Anmeldung nötig“');
    // „Anmelden …“: Konsole offen, die Zeile wartet auf die neue Prüfung.
    mPage.VcsServerLogin.Click;
    Assert.AreEqual(1, Integer(Length(mProbe.FLogins)));
    Assert.AreEqual('C:\Projekte\Kasse|origin', mProbe.FLogins[0]);
    AssertVcsLoginRechecked(mPage, mList, mCheck);
    // „Alle prüfen“.
    mProbe.FChecked := nil;
    mPage.VcsServerCheckAll.Click;
    Assert.AreEqual(2, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Pakete\Basis', mProbe.FChecked[1]);
    // „prüfen …“ der Willkommensseite für einen Ordner ohne Zeile: Zeile kommt dazu und wird geprüft.
    mProbe.FChecked := nil;
    mPage.RevealVcsServer('C:\Projekte\Lager\');
    Assert.AreEqual(3, mList.Items.Count);
    Assert.AreEqual('Lager', mList.Items[2].Caption);
    Assert.AreEqual(1, Integer(Length(mProbe.FChecked)));
    Assert.AreEqual('C:\Projekte\Lager', mProbe.FChecked[0]);
  finally
    mHost.Free;
    mProbe.Free;
  end;
end;

/// <summary>Die Seite liest und löst Favoriten über AFavorites.</summary>
procedure WireFavorites(APage: TAtlasSettingsPage; AFavorites: TAtlasFavorites);
begin
  APage.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    var
      Key: string;
    begin
      for Key in AKeys do
      begin
        AFavorites.Remove(Key);
      end;
    end;
  APage.OnFavorites :=
    function: TArray<TAtlasFavorite>
    begin
      Result := AFavorites.Items;
    end;
end;

procedure TAtlasSettingsPageTests.FavoritesListAndRemove;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Favorites: TAtlasFavorites;
  Settings, Saved: TAtlasPluginSettings;
  Item: TAtlasCompletionItem;
  Names: TArray<string>;
  Name: string;
begin
  Names := ['Open', 'Close', 'ParamByName'];
  Favorites := TAtlasFavorites.Create;
  Host := TForm.CreateNew(nil);
  try
    for Name in Names do
    begin
      Item := Default(TAtlasCompletionItem);
      Item.Name := Name;
      Item.DeclaringClass := 'TDataSet';
      Favorites.Toggle(Item);
    end;
    // Die Liste braucht ein Fenster, wie in der IDE.
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    WireFavorites(Page, Favorites);
    Settings := TAtlasPluginSettings.Defaults;
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.FavoritesCheck.Checked);
    Page.FavoritesCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.Favorites, 'abschaltbar');
    Assert.IsFalse(Page.FavoritesRemove.Enabled, 'Liste gehört zum Schalter (#890)');
    Page.FavoritesCheck.Checked := True;
    Assert.AreEqual(3, Integer(Page.FavoritesList.Items.Count));
    Assert.AreEqual('TDataSet.Open', Page.FavoritesList.Items[0]);
    Page.FavoritesList.Selected[1] := True;
    Page.FavoritesRemove.Click;
    Assert.AreEqual(2, Integer(Favorites.Count), 'Close gelöst');
    Assert.AreEqual('TDataSet.ParamByName', Page.FavoritesList.Items[1]);
    Page.FavoritesRemoveAll.Click;
    Assert.AreEqual(0, Integer(Favorites.Count));
    Assert.AreEqual(1, Integer(Page.FavoritesList.Items.Count), 'nur der Hinweis „keine“');
    Assert.IsFalse(Page.FavoritesRemoveAll.Enabled);
  finally
    Host.Free;
    Favorites.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UndoSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #721: Ein/Aus, Tiefe, Sicherung, Größe, Konflikte, neue Dateien und die beiden Tasten.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.UndoMultiFileDepth := 7;
  Settings.UndoMultiFileOnConflict := 'abort';
  Settings.UndoMultiFileNewFiles := 'keep';
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.UndoEnabled.Checked);
    Assert.AreEqual('7', Page.UndoDepth.Text);
    Assert.IsTrue(Page.UndoPersist.Checked);
    Assert.AreEqual('50', Page.UndoMaxSize.Text);
    Assert.AreEqual(1, Page.UndoOnConflict.Choice);
    Assert.AreEqual(2, Page.UndoNewFiles.Choice);
    Assert.IsTrue(Page.UndoKey.Text <> '');
    Assert.IsTrue(Page.RedoKey.Text <> '');
    Page.UndoEnabled.Checked := False;
    Page.UndoPersist.Checked := False;
    Page.UndoDepth.Text := '999';
    Page.UndoMaxSize.Text := '0';
    Page.UndoOnConflict.Choice := 0;
    Page.UndoNewFiles.Choice := 1;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.UndoMultiFile);
    Assert.IsFalse(Saved.UndoMultiFilePersist);
    // Begrenzt auf den erlaubten Bereich.
    Assert.AreEqual(TAtlasPluginSettings.MaxUndoDepth, Saved.UndoMultiFileDepth);
    Assert.AreEqual(TAtlasPluginSettings.MinUndoMaxSizeMb, Saved.UndoMultiFileMaxSizeMb);
    Assert.AreEqual('partial', Saved.UndoMultiFileOnConflict);
    Assert.AreEqual('delete', Saved.UndoMultiFileNewFiles);
    Assert.AreEqual(Settings.UndoKey, Saved.UndoKey);
    Assert.AreEqual(Settings.RedoKey, Saved.RedoKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MoveLinesRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #634: Schalter und Tasten; leeres Feld = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.MoveLines.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($8026)), Page.MoveLinesUpKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A028)), Page.DuplicateLinesDownKey.Text);
    Page.MoveLines.Checked := False;
    Page.MoveLinesUpKey.Text := '';
    Page.DuplicateLinesDownKey.Text := ShortCutToText(TShortCut($C044));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.MoveLines);
    Assert.AreEqual(0, Saved.MoveLinesUpKey);
    Assert.AreEqual($8028, Saved.MoveLinesDownKey);
    Assert.AreEqual($C044, Saved.DuplicateLinesDownKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ContinueCommentsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #696: Schalter und Präfix; Leerraum am Rand des Präfixes bleibt.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.ContinueComments.Checked);
    Assert.IsTrue(Page.ContinueCommentsLists.Checked);
    Assert.AreEqual('', Page.ContinueCommentsBlockPrefix.Text);
    Page.ContinueComments.Checked := False;
    Page.ContinueCommentsLists.Checked := False;
    Page.ContinueCommentsBlockPrefix.Text := ' * ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ContinueComments);
    Assert.IsFalse(Saved.ContinueCommentsLists);
    Assert.IsTrue(Saved.ContinueCommentsLineComments);
    Assert.AreEqual(' * ', Saved.ContinueCommentsBlockPrefix);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.CompleteStatementRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #697: Schalter, Taste und beide Auswahlen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.CompleteStatement.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($600D)), Page.CompleteStatementKey.Text);
    Assert.AreEqual(1, Page.CompleteStatementBeginEnd.Choice);
    Assert.AreEqual(0, Page.CompleteStatementTryKind.Choice);
    Page.CompleteStatement.Checked := False;
    Page.CompleteStatementKey.Text := '';
    Page.CompleteStatementBeginEnd.Choice := 2;
    Page.CompleteStatementTryKind.Choice := 2;
    Page.CompleteStatementMethodBody.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CompleteStatement);
    Assert.AreEqual(0, Saved.CompleteStatementKey);
    Assert.AreEqual('never', Saved.CompleteStatementBeginEnd);
    Assert.AreEqual('ask', Saved.CompleteStatementTryKind);
    Assert.IsFalse(Saved.CompleteStatementMethodBody);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.FormatCodeRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #43: Schalter und Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.FormatCode.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($E04C)), Page.FormatCodeKey.Text);
    Page.FormatCode.Checked := False;
    Page.FormatCodeKey.Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.FormatCode);
    Assert.AreEqual(0, Saved.FormatCodeKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MultiCursorRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #589: Schalter, Klicktaste und die fünf Kürzel.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.MultiCursor.Checked);
    // #658 steht daneben, ebenfalls experimentell und aus.
    Assert.IsFalse(Page.LinkedEditing.Checked);
    Assert.AreEqual(0, Page.MultiCursorModifier.Choice);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), Page.MultiCursorNextKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($4044)), Page.MultiCursorSkipKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($A049)), Page.MultiCursorLineEndsKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C026)), Page.MultiCursorAboveKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($C028)), Page.MultiCursorBelowKey.Text);
    Page.MultiCursor.Checked := True;
    Page.LinkedEditing.Checked := True;
    Page.MultiCursorModifier.Choice := 1;
    Page.MultiCursorNextKey.Text := '';
    Page.MultiCursorSkipKey.Text := ShortCutToText(TShortCut($4053));
    Page.MultiCursorLineEndsKey.Text := ShortCutToText(TShortCut($C049));
    Page.MultiCursorAboveKey.Text := ShortCutToText(TShortCut($A026));
    Page.MultiCursorBelowKey.Text := ShortCutToText(TShortCut($A028));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.MultiCursor);
    Assert.IsTrue(Saved.LinkedEditing);
    Assert.AreEqual('ctrl', Saved.MultiCursorModifier);
    Assert.AreEqual(0, Saved.MultiCursorNextKey);
    Assert.AreEqual($4053, Saved.MultiCursorSkipKey);
    Assert.AreEqual($C049, Saved.MultiCursorLineEndsKey);
    Assert.AreEqual($A026, Saved.MultiCursorAboveKey);
    Assert.AreEqual($A028, Saved.MultiCursorBelowKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SmartPasteRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
  Index: Integer;
const
  Values: array[0..3] of string = ('off', 'uses', 'indent', 'both');
begin
  // #515: Auswahl mit vier Einträgen, Vorgabe aus.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(0, Page.SmartPaste.Choice);
    for Index := 0 to High(Values) do
    begin
      Settings.SmartPaste := Values[Index];
      Page.LoadFrom(Settings);
      Assert.AreEqual(Index, Page.SmartPaste.Choice);
      Saved := TAtlasPluginSettings.Defaults;
      Page.SaveTo(Saved);
      Assert.AreEqual(Values[Index], Saved.SmartPaste);
    end;
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.StickyScrollRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #506: Schalter und Höchstzahl der Zeilen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.StickyScroll.Checked);
    Assert.AreEqual('3', Page.StickyScrollMaxLines.Text);
    Page.StickyScroll.Checked := True;
    Page.StickyScrollMaxLines.Text := '2';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StickyScroll);
    Assert.AreEqual(2, Saved.StickyScrollMaxLines);
    // Was der Kopf zeigt: je Art ein Schalter.
    Assert.IsTrue(Page.StickyScrollTypes.Checked and Page.StickyScrollRoutines.Checked);
    Assert.IsFalse(Page.StickyScrollTry.Checked);
    Page.StickyScrollRoutines.Checked := False;
    Page.StickyScrollTry.Checked := True;
    Page.StickyScrollWith.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StickyScrollTypes);
    Assert.IsFalse(Saved.StickyScrollRoutines);
    Assert.IsFalse(Saved.StickyScrollLoops);
    Assert.IsTrue(Saved.StickyScrollTry);
    Assert.IsFalse(Saved.StickyScrollCase);
    Assert.IsTrue(Saved.StickyScrollWith);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.EditorToolbarRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1101: Position als Auswahl, Belegung als Text (beim Speichern bereinigt), „Leiste anpassen …“ vorhanden.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual(Settings.EditorToolbarItems, Page.EditorToolbarItemsEdit.Text);
    Assert.AreEqual(0, Page.EditorToolbarPositionBox.Choice);
    Assert.IsNotNull(Page.EditorToolbarCustomizeButton);
    Page.EditorToolbarPositionBox.Choice := 2;
    Page.EditorToolbarItemsEdit.Text := ' Atlas.NavBack , | , | ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('inBreadcrumbs', Saved.EditorToolbarPosition);
    Assert.AreEqual('Atlas.NavBack', Saved.EditorToolbarItems);
    Assert.IsTrue(Saved.EditorToolbar);
    Assert.IsTrue(Saved.EditorToolbarReturnButton);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.EditorStatusBarRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1155: Schalter und Elemente als Text; beim Speichern bereinigt (unbekannte weg, doppelte einmal).
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.AreEqual('status,findings,liveCheck,method', Page.EditorStatusBarItemsEdit.Text);
    Page.EditorStatusBarItemsEdit.Text := ' method , foo, status, method ';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('method,status', Saved.EditorStatusBarItems);
    Assert.IsTrue(Saved.EditorStatusBar);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.CallHierarchyDiagramRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.CallHierarchyDiagram := False;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Assert.IsTrue(Saved.CallHierarchyDiagram);
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CallHierarchyDiagram, 'aus bleibt aus');
    Settings.CallHierarchyDiagram := True;
    Page.LoadFrom(Settings);
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CallHierarchyDiagram, 'an bleibt an');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.QuickBookmarksRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #1104: Schalter, Taste, Wartezeit (begrenzt), Sprungbereich als Auswahl, Tasten für nächstes/voriges.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.QuickBookmarksCheck.Checked);
    Assert.IsTrue(Page.QuickBookmarksGutterCheck.Checked);
    Assert.AreEqual('800', Page.QuickBookmarkChordWaitEdit.Text);
    Assert.AreEqual(0, Page.QuickBookmarksScopeBox.Choice);
    Assert.AreEqual('', Page.NextBookmarkKeyEdit.Text);
    Page.QuickBookmarksGutterClickCheck.Checked := False;
    Page.QuickBookmarksNumberedKeysCheck.Checked := False;
    Page.QuickBookmarksImportIdeCheck.Checked := False;
    Page.QuickBookmarkChordWaitEdit.Text := '99999';
    Page.QuickBookmarksScopeBox.Choice := 1;
    Page.QuickBookmarkKeyEdit.Text := '';
    Page.NextBookmarkKeyEdit.Text := 'F2';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.QuickBookmarks);
    Assert.IsFalse(Saved.QuickBookmarksGutterClick);
    Assert.IsFalse(Saved.QuickBookmarksNumberedKeys);
    Assert.IsFalse(Saved.QuickBookmarksImportIde);
    Assert.AreEqual(TAtlasPluginSettings.MaxQuickChordWait, Saved.QuickBookmarkChordWait);
    Assert.AreEqual('file', Saved.QuickBookmarksScope);
    Assert.AreEqual(0, Saved.QuickBookmarkKey);
    Assert.AreEqual($71, Saved.NextBookmarkKey, 'F2');
    Assert.AreEqual(0, Saved.PreviousBookmarkKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ContinuePatternRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #671: Schalter und Mindestzeilen.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.ContinuePattern.Checked);
    Assert.AreEqual('2', Page.ContinuePatternMinLines.Text);
    Page.ContinuePattern.Checked := False;
    Page.ContinuePatternMinLines.Text := '3';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ContinuePattern);
    Assert.AreEqual(3, Saved.ContinuePatternMinLines);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.MethodToggleRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #775: Schalter und beide Tasten; leeres Feld = keine Taste.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.MethodToggle.Checked);
    Assert.AreEqual(ShortCutToText(TShortCut($6026)), Page.MethodToggleUpKey.Text);
    Assert.AreEqual(ShortCutToText(TShortCut($6028)), Page.MethodToggleDownKey.Text);
    Page.MethodToggle.Checked := False;
    Page.MethodToggleUpKey.Text := '';
    Page.MethodToggleDownKey.Text := ShortCutToText(TShortCut($C044));
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.MethodToggle);
    Assert.AreEqual(0, Saved.MethodToggleUpKey);
    Assert.AreEqual($C044, Saved.MethodToggleDownKey);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SnippetsPageShowsCatalogAndValidates;
var
  Host: TForm;
  Page: TAtlasSnippetsPage;
  Own: TAtlasSnippet;
begin
  Own := Default(TAtlasSnippet);
  Own.Prefix := 'eigen';
  Own.Body := 'X;';
  Own.Origin := TAtlasSnippetOrigin.User;
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSnippetsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Page.Load(TAtlasSnippetCatalog.Create(TAtlasSnippets.BuiltIn, nil, [Own]));
    Assert.AreEqual(Integer(Length(TAtlasSnippets.BuiltIn)) + 1, Page.Catalog.Count);
    Assert.AreEqual('', Page.Validate);
    // Zweite eigene mit demselben Kürzel: Meldung nennt das Kürzel.
    Page.Catalog.Update(Page.Catalog.AddNew, Own);
    Assert.IsTrue(Pos('eigen', Page.Validate) > 0);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.AcceptOptionsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // ARG-046 (#227): Commit-Zeichen, uses, Parameter-Hint, Verzögerung und automatische Breite.
  Settings := TAtlasPluginSettings.Defaults;
  Settings.CommitCharacters := False;
  Settings.AutoUses := False;
  Settings.ParameterHints := False;
  Settings.FormatPlaceholders := False;
  Settings.OpenDelayMs := 300;
  Settings.ListWidth := 400;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.CommitChars.Checked);
    Assert.IsFalse(Page.AutoUses.Checked);
    Assert.IsFalse(Page.ParameterHints.Checked);
    Assert.IsFalse(Page.FormatPlaceholders.Checked);
    Assert.AreEqual('300', Page.OpenDelay.Text);
    Assert.IsFalse(Page.AutoWidth.Checked);
    Page.CommitChars.Checked := True;
    Page.FormatPlaceholders.Checked := True;
    Page.OpenDelay.Text := '0';
    Page.AutoWidth.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CommitCharacters);
    Assert.IsFalse(Saved.AutoUses);
    Assert.IsFalse(Saved.ParameterHints);
    Assert.IsTrue(Saved.FormatPlaceholders);
    Assert.AreEqual(0, Saved.OpenDelayMs);
    Assert.AreEqual(0, Saved.ListWidth, 'automatische Breite');
    // Version des Servers neben dem Pfad.
    Page.OnServerVersion :=
      function(APath: string): string
      begin
        Result := '1.2.3.4';
      end;
  finally
    Page.Free;
  end;
end;

/// <summary>Feste Antworten für Unterdrückungen, Cache und Rückfrage.</summary>
procedure WireServerPageAnswers(APage: TAtlasServerPage);
begin
  APage.OnSuppressions :=
    function: TArray<string>
    begin
      Result := ['no-with: 3 (ungenutzt 1, in 2 Dateien)'];
    end;
  APage.OnClearCache :=
    function: string
    begin
      Result := 'Cache leer';
    end;
  APage.Confirm :=
    function(AQuestion: string): Boolean
    begin
      Result := True;
    end;
end;

procedure TAtlasSettingsPageTests.ServerPageRunsActions;
var
  Host: TForm;
  Page: TAtlasServerPage;
  Global, Deleted: Boolean;
begin
  // Listen brauchen ein Fenster, wie in der IDE.
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasServerPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    // Ohne Ereignisse ist alles aus.
    Assert.IsFalse(Page.BaselineUpdate.Enabled);
    Assert.IsFalse(Page.CacheClear.Enabled);
    Global := False;
    Deleted := False;
    Page.OnEditGlobal :=
      procedure
      begin
        Global := True;
      end;
    Page.OnBaselineInfo :=
      function: string
      begin
        Result := '5 Treffer in 2 Einträgen';
      end;
    Page.OnBaselineDelete :=
      function: string
      begin
        Deleted := True;
        Result := 'gelöscht';
      end;
    WireServerPageAnswers(Page);
    Page.Refresh;
    Assert.AreEqual('5 Treffer in 2 Einträgen', Page.BaselineInfo.Caption);
    Page.EditGlobal.Click;
    Assert.IsTrue(Global);
    Page.BaselineDelete.Click;
    Assert.IsTrue(Deleted);
    Assert.AreEqual('gelöscht', Page.BaselineInfo.Caption);
    Page.SuppressionsRefresh.Click;
    Assert.AreEqual(1, Integer(Page.Suppressions.Items.Count));
    Page.CacheClear.Click;
    Assert.AreEqual('Cache leer', Page.CacheInfo.Caption);
  finally
    Host.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogShowsOriginAndResetsToGlobal;
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{"language": "en"}',
    '{"language": "de", "encoding": "windows-1252"}', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\P\atlas.json');
    try
      Assert.IsTrue(Dialog.SelectPage('Allgemein'));
      Assert.IsTrue(Pos('Projekt', Dialog.StateText('language')) > 0);
      Assert.IsTrue(Pos('windows-1252', Dialog.StateText('encoding')) > 0, 'global geerbt');
      Model.Reset(Model.IndexOf('language'));
      Assert.AreEqual('{}', Model.ResultText);
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogRuleTableChangesOnlyThatRule;
const
  Text = '{' + #13#10 + '  "rules": {' + #13#10 + '    "no-with": "error" // streng' + #13#10 + '  }' + #13#10 + '}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
begin
  Catalog := TJSONObject.ParseJSONValue('{"rules": [{"id": "no-with", "name": "Kein with", "category": "code-smell",' +
    ' "severity": "warning"}, {"id": "empty-except", "name": "Leeres except", "category": "bug",' +
    ' "severity": "error"}]}');
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), Text, '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\P\atlas.json');
    try
      Dialog.Catalog := Catalog;
      // Mit Fenster: Erst dann hat der Behälter seine Breite; ohne war die Prüfung der Breite wertlos.
      Dialog.HandleNeeded;
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Assert.AreEqual(2, Integer(Dialog.RuleList.Items.Count));
      Assert.IsTrue(Dialog.RuleEditor.Parent.ClientWidth > 400, 'Behälter breit');
      // AutoSize ohne Align ließ den Editor auf die Breite eines leeren Panels schrumpfen.
      Assert.IsTrue(Dialog.RuleEditor.Left + Dialog.RuleEditor.Width >= Dialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor in voller Breite');
      Assert.IsTrue(Dialog.SetRuleSeverity('no-with', 'off'));
      Assert.AreEqual(StringReplace(Text, '"error"', '"off"', []), Model.ResultText);
      Assert.IsFalse(Dialog.SetRuleSeverity('unbekannt', 'off'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogRulesByGroupNodes;
const
  CatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style"}, {"id": "lock-without-finally", "name": "Sperre ohne finally",' +
    ' "category": "bug", "severity": "warning", "group": "threads"}]}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Users\X\settings.json');
    try
      Dialog.Catalog := Catalog;
      // Unter der Seite mit "rules" je Gruppe ein Knoten (Aufbau wie früher in Tools › Optionen).
      Assert.IsNotNull(Dialog.GroupNode('threads'));
      Assert.IsNotNull(Dialog.GroupNode('style'));
      Assert.AreEqual(Model.Fields[Model.IndexOf('rules')].Page, Dialog.GroupNode('threads').Parent.Text);
      // Knoten der Gruppe: nur ihre Regeln; der Hauptschalter schreibt "group:threads".
      Dialog.HandleNeeded;
      Dialog.PageTree.Selected := Dialog.GroupNode('threads');
      Assert.AreEqual('threads', Dialog.RuleEditor.FixedGroup);
      Assert.AreEqual(1, Dialog.RuleList.Items.Count);
      Assert.IsTrue(Dialog.RuleEditor.Left + Dialog.RuleEditor.Width >= Dialog.RuleEditor.Parent.ClientWidth - 50,
        'Regel-Editor der Gruppe in voller Breite');
      Dialog.RuleEditor.Master.Checked := False;
      Assert.Contains(Model.ResultText, '"group:threads"');
      // „Regel einstellen…“: Knoten der Gruppe der Regel, die Regel markiert.
      Assert.IsTrue(Dialog.SelectRule('magic-number'));
      Assert.IsTrue(Dialog.PageTree.Selected = Dialog.GroupNode('style'));
      Assert.AreEqual('style', Dialog.RuleEditor.FixedGroup);
      Assert.IsNotNull(Dialog.RuleList.Selected);
      Assert.AreEqual('magic-number', Dialog.RuleList.Selected.Caption);
      Assert.IsFalse(Dialog.SelectRule('unbekannt'));
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;

/// <summary>Abstand des nächsten Steuerelements unter AEditor zu dessen Unterkante; MaxInt ohne.</summary>
function SpaceBelow(ABox: TWinControl; AEditor: TControl): Integer;
var
  mIndex: Integer;
  mControl: TControl;
begin
  Result := MaxInt;
  for mIndex := 0 to ABox.ControlCount - 1 do
  begin
    mControl := ABox.Controls[mIndex];
    if (mControl <> AEditor) and (mControl.Top > AEditor.Top) then
    begin
      Result := Min(Result, mControl.Top - (AEditor.Top + AEditor.Height));
    end;
  end;
end;

procedure TAtlasSettingsPageTests.DialogRuleEditorPushesFieldsDown;
const
  CatalogText = '{"rules": [{"id": "magic-number", "name": "Magische Zahl", "category": "code-smell",' +
    ' "severity": "hint", "group": "style", "description": "Zahl ohne Namen", "bad": "X := 42;",' +
    ' "good": "X := Answer;", "options": [{"name": "ignore", "type": "string-list", "default": ["0"]},' +
    ' {"name": "maxDigits", "type": "integer", "default": 3}], "experimental": true},' +
    ' {"id": "no-with", "name": "Kein with", "category": "code-smell", "severity": "warning"}]}';
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Catalog: TJSONValue;
  Editor: TAtlasRulesEditor;
  Box: TWinControl;
  Before, Spacing, Below: Integer;
begin
  Catalog := TJSONObject.ParseJSONValue(CatalogText);
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', False);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
    try
      Dialog.Catalog := Catalog;
      Dialog.HandleNeeded;
      Assert.IsTrue(Dialog.SelectPage(Model.Fields[Model.IndexOf('rules')].Page));
      Editor := Dialog.RuleEditor;
      Box := Editor.Parent;
      // Abstand des ersten Steuerelements unter dem Editor zu seiner Unterkante beim Aufbau.
      Spacing := SpaceBelow(Box, Editor);
      Assert.IsTrue(Spacing < MaxInt, 'Zustand und Zurücksetzen von "rules" stehen unter dem Editor');
      Assert.IsTrue(Spacing >= 0);
      Before := Editor.Height;
      Assert.IsTrue(Editor.SelectRule('magic-number'));
      Assert.IsTrue(Editor.Height > Before, 'Optionen und Beispiele lassen den Editor wachsen');
      Below := SpaceBelow(Box, Editor);
      Assert.AreEqual(Spacing, Below, 'Felder darunter rücken mit dem Editor nach unten');
      // Zurück zu einer Regel ohne Optionen: Die Felder rücken wieder hoch.
      Assert.IsTrue(Editor.SelectRule('no-with'));
      Below := SpaceBelow(Box, Editor);
      Assert.AreEqual(Spacing, Below, 'Felder darunter rücken mit dem Editor wieder hoch');
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
    Catalog.Free;
  end;
end;

procedure TAtlasSettingsPageTests.DialogValidatesBeforeSaving;
var
  Model: TAtlasSettingsModel;
  Dialog: TAtlasProjectSettingsDialog;
  Checked: Integer;
begin
  Model := TAtlasSettingsModel.Create(TAtlasSettingsSchema.Fields(AtlasSchemaJson), '{}', '', True);
  try
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Users\X\settings.json');
    try
      Checked := 0;
      Dialog.OnValidate :=
        function(const AText: string; out AChecked: Boolean): TArray<TAtlasSettingIssue>
        begin
          Inc(Checked);
          AChecked := True;
          Result := nil;
        end;
      // Unverändert: nichts zu prüfen.
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(0, Checked);
      Model.SetValue(Model.IndexOf('memoryBudgetMb'), '256');
      Assert.IsTrue(Dialog.Validate);
      Assert.AreEqual(1, Checked);
      Dialog.ServerChecks := False;
      Assert.IsTrue(Dialog.HintLabel.Visible, 'Hinweis: nur Syntax');
      // Eine Zeile Hinweis: Nach dem Anpassen an die Breite bleibt kein hoher leerer Streifen.
      Dialog.HandleNeeded;
      Dialog.Width := Dialog.Width + 10;
      Assert.IsTrue(Dialog.HintLabel.Height < 60, 'Hinweis ohne leeren Streifen');
    finally
      Dialog.Free;
    end;
  finally
    Model.Free;
  end;
end;

procedure TAtlasSettingsPageTests.SymbolResourcesInAllSizes;
var
  Variant_: TAtlasSymbolVariant;
  Index: Integer;
  Image: TWICImage;
  Icon: TIcon;
  Collection: TImageCollection;
begin
  // #751: jede Größe beider Varianten ist als PNG eingebunden und hat genau diese Größe.
  for Variant_ := Low(TAtlasSymbolVariant) to High(TAtlasSymbolVariant) do
  begin
    for Index := 0 to TAtlasSymbol.SizeCount - 1 do
    begin
      Image := TAtlasSymbolImages.Load(Variant_, TAtlasSymbol.Size(Index));
      try
        Assert.IsNotNull(Image, TAtlasSymbol.ResourceName(Variant_, TAtlasSymbol.Size(Index)));
        Assert.AreEqual(TAtlasSymbol.Size(Index), Image.Width);
      finally
        Image.Free;
      end;
    end;
    Icon := TAtlasSymbolImages.Icon(Variant_);
    try
      Assert.IsFalse(Icon.Empty, TAtlasSymbol.IconName(Variant_));
    finally
      Icon.Free;
    end;
  end;
  Collection := TAtlasSymbolImages.Collection(nil);
  try
    Assert.AreEqual(2, Integer(Collection.Images.Count));
    Assert.AreEqual(TAtlasSymbol.SizeCount, Collection.Images[1].SourceImages.Count);
  finally
    Collection.Free;
  end;
end;

procedure TAtlasSettingsPageTests.PageHeaderShowsSymbol;
var
  Page: TAtlasSettingsPage;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Assert.IsNotNull(Page.Symbol);
    Assert.AreEqual(TAtlasSymbol.HeaderSize, Page.Symbol.LogicalSize);
    Assert.AreEqual(TAtlasSymbol.PixelSize(TAtlasSymbol.HeaderSize, Page.Symbol.CurrentPPI), Page.Symbol.Width);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.HangTestOnlyInDiagnosticMode;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.DiagnosticMode := False;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.HangTestRow.Visible, 'ohne Diagnosemodus verborgen');
    Page.DiagnosticMode.Checked := True;
    Assert.IsTrue(Page.HangTestRow.Visible, 'sofort sichtbar, wenn der Diagnosemodus eingeschaltet wird');
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.HangTestRow.Visible, 'nach dem Laden ohne Diagnosemodus wieder verborgen');
    Settings.DiagnosticMode := True;
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.HangTestRow.Visible, 'mit Diagnosemodus geladen');
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.ProblemsWindowOpenFirstLocksItsOptions;
var
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Settings := TAtlasPluginSettings.Defaults;
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.ProblemsWindowOpenFirstCheck.Checked);
    Assert.AreEqual(0, Page.ProblemsWindowClosedUnitsChoice.Choice);
    Assert.IsTrue(Page.ProblemsWindowShowCleanActiveCheck.Checked);
    Assert.IsTrue(SheetOf(Page.ProblemsWindowOpenFirstCheck) = Page.NodeSheet('rules.window'));
    Assert.IsTrue(SheetOf(Page.ProblemsWindowClosedUnitsChoice) = Page.NodeSheet('rules.window'));
    Assert.IsTrue(Page.ProblemsWindowClosedUnitsChoice.Enabled and Page.ProblemsWindowShowCleanActiveCheck.Enabled);
    Page.ProblemsWindowOpenFirstCheck.Checked := False;
    Assert.IsFalse(Page.ProblemsWindowClosedUnitsChoice.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(Page.ProblemsWindowShowCleanActiveCheck.Enabled, 'Schalter gesperrt');
    Page.ProblemsWindowClosedUnitsChoice.Choice := 2;
    Page.ProblemsWindowShowCleanActiveCheck.Checked := False;
    Settings := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Settings);
    Assert.IsFalse(Settings.ProblemsWindowOpenFirst);
    Assert.AreEqual('hidden', Settings.ProblemsWindowClosedUnits);
    Assert.IsFalse(Settings.ProblemsWindowShowCleanActive);
    Page.ProblemsWindowOpenFirstCheck.Checked := True;
    Assert.IsTrue(Page.ProblemsWindowClosedUnitsChoice.Enabled, 'wieder frei');
  finally
    Page.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

/// <summary>Knoten des Bereichs Regeln: Prüffenster und „Profile und Baseline“, keine Regelgruppen.</summary>
procedure AssertRulesNodes(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(SheetOf(APage.ProblemsWindowCheck) = APage.NodeSheet('rules.window'));
  Assert.IsTrue(SheetOf(APage.ProblemsLiveCheck) = APage.NodeSheet('rules.window'));
  Assert.IsTrue(SheetOf(APage.FixBulkCheck) = APage.NodeSheet('rules.window'));
  Assert.IsNotNull(APage.NodeSheet('rules.profiles'));
  Assert.IsTrue(SheetOf(APage.BaselineInfoLabel) = APage.NodeSheet('rules.profiles'));
  Assert.IsNull(APage.NodeSheet('rules.group.threads'), 'keine Regelgruppen in Tools › Optionen');
end;

/// <summary>Gespeicherte Einstellungen des Prüffensters und der Gruppe „Compiler vorab“.</summary>
procedure AssertRulesAreaSaved(const ASettings: TAtlasPluginSettings);
begin
  Assert.AreEqual('both', ASettings.ProblemsCompilerMerge);
  Assert.IsFalse(ASettings.ProblemsShowCompilerCode);
  Assert.AreEqual('file', ASettings.ProblemsWindowScope);
  Assert.AreEqual('rule', ASettings.ProblemsWindowGroupBy);
  Assert.IsTrue(ASettings.ProblemsWindowCompiler);
  Assert.IsFalse(ASettings.ProblemsLive, 'Live gespeichert');
  Assert.IsFalse(ASettings.FixBulk, 'Sammelkorrektur gespeichert');
  Assert.IsFalse(ASettings.HoverProblemActions, 'Hover-Aktionen gespeichert');
end;

procedure TAtlasSettingsPageTests.RulesAreaLinksToDialogs;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
  Project, Global: Integer;
begin
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    // Knoten: Prüffenster, Compiler vorab, „Profile und Baseline“; die Regeln stehen in den Dialogen der
    // Einstellungsdateien.
    AssertRulesNodes(Page);
    // Hauptknoten: Wege zum Projekt- und zum globalen Dialog.
    Project := 0;
    Global := 0;
    Page.OnRulesProject :=
      procedure
      begin
        Inc(Project);
      end;
    Page.OnRulesGlobal :=
      procedure
      begin
        Inc(Global);
      end;
    Assert.AreEqual('', Page.NodeOfSheet(SheetOf(Page.RulesProjectButton)));
    Page.RulesProjectButton.Click;
    Page.RulesGlobalButton.Click;
    Assert.AreEqual(1, Project);
    Assert.AreEqual(1, Global);
    // Einstellungen des Prüffensters im Rundweg.
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ProblemsWindowScope := 'project';
    Settings.ProblemsWindowGroupBy := 'rule';
    Settings.ProblemsLive := False;
    Settings.FixBulk := False;
    Settings.HoverProblemActions := False;
    Page.LoadFrom(Settings);
    Assert.AreEqual(1, Page.ProblemsWindowScopeChoice.Choice);
    Assert.AreEqual(2, Page.ProblemsWindowGroupByChoice.Choice);
    Assert.IsFalse(Page.ProblemsLiveCheck.Checked, 'Live geladen');
    Assert.IsFalse(Page.FixBulkCheck.Checked, 'Sammelkorrektur geladen');
    Assert.IsFalse(Page.HoverProblemActionsCheck.Checked, 'Hover-Aktionen geladen');
    Page.ProblemsWindowScopeChoice.Choice := 0;
    Page.ProblemsWindowCompilerCheck.Checked := True;
    // Gruppe „Compiler vorab“ (#1024): eigener Knoten mit den Plugin-Einstellungen der Gruppe.
    Assert.AreEqual(0, Page.ProblemsCompilerMergeChoice.Choice);
    Assert.IsTrue(Page.ProblemsShowCompilerCodeCheck.Checked);
    Assert.IsTrue(SheetOf(Page.ProblemsShowCompilerCodeCheck) = Page.NodeSheet('rules.group.compiler'));
    Page.ProblemsCompilerMergeChoice.Choice := 1;
    Page.ProblemsShowCompilerCodeCheck.Checked := False;
    Settings := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Settings);
    AssertRulesAreaSaved(Settings);
  finally
    Host.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.
