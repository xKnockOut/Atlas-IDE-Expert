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
    [Test]
    procedure WelcomeSettingsRoundTrip;
    /// <summary>Freies Layout (#767): Schalter, Spalten, Layouts anlegen, wechseln, umbenennen, löschen; je
    /// Layout eigene Sichtbarkeit; Reveal der neuen Einstellungen.</summary>
    [Test]
    procedure WelcomeLayoutsOnPage;
    [Test]
    procedure UsageButtonsCallBack;
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
  Atlas.Core.Build.ReleaseGuard,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.QuickActions,
  Atlas.Core.Welcome.Layouts,
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
  Atlas.Core.Style.Symbol,
  Atlas.UI.Style.Symbol,
  Vcl.Graphics,
  Vcl.ImageCollection,
  System.JSON,
  System.Generics.Collections,
  System.StrUtils,
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
    AControl := AControl.Parent;
  Result := AControl <> nil;
end;

/// <summary>Reiter, auf dem AControl liegt; nil ohne.</summary>
function SheetOf(AControl: TControl): TTabSheet;
begin
  while (AControl <> nil) and not (AControl is TTabSheet) do
    AControl := AControl.Parent;
  Result := TTabSheet(AControl);
end;

/// <summary>Nächster Rahmen über AControl; nil ohne.</summary>
function FrameAround(AControl: TControl): TAtlasSettingsGroup;
begin
  AControl := AControl.Parent;
  while (AControl <> nil) and not (AControl is TAtlasSettingsGroup) do
    AControl := AControl.Parent;
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
      Exit;
  end;
  Result := nil;
end;

function TopLevelNodes(APage: TAtlasSettingsPage): TArray<TTreeNode>;
var
  Index: Integer;
begin
  Result := nil;
  for Index := 0 to APage.Navigation.Items.Count - 1 do
    if APage.Navigation.Items[Index].Level = 0 then
      Result := Result + [APage.Navigation.Items[Index]];
end;

procedure TAtlasSettingsPageTests.TreeShowsAreasAndNodes;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Areas: TArray<TTreeNode>;
  Node: TTreeNode;
  Minimap: TTabSheet;
  Index: Integer;
begin
  // #890: Bereiche oben im Baum, Funktionen als Unterpunkte; jeder Knoten zeigt nur seine Seite.
  TAtlasSettingsPage.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Areas := TopLevelNodes(Page);
    Assert.AreEqual(17, Integer(Length(Areas)));
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabGeneral), Areas[0].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabCompiler), Areas[6].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRules), Areas[7].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRelease), Areas[8].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabDebug), Areas[9].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUndo), Areas[13].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUnitSearch), Areas[14].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabWelcome), Areas[15].Text);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabTeamFile), Areas[16].Text);
    Assert.IsTrue(Page.Pages.PageCount > 16, 'Unterpunkte haben eigene Seiten');
    for Index := 0 to Page.Pages.PageCount - 1 do
    begin
      Assert.IsTrue(Page.Pages.Pages[Index].ControlCount > 0, Page.Pages.Pages[Index].Caption);
      Assert.IsFalse(Page.Pages.Pages[Index].TabVisible, Page.Pages.Pages[Index].Caption);
    end;
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
        if (Known = '') and Page.Groups.Contains(Name) then
          Known := Name;
      if Known = '' then
        Continue;
      Sheet := SheetOf(Binding.Control);
      Assert.IsNotNull(Sheet, Known);
      Assert.AreEqual(Page.Groups.NodeOf(Known), Page.NodeOfSheet(Sheet), Known);
      Frame := FrameAround(Binding.Control);
      // Ohne Rahmen (Einstellung ohne Hauptschalter, z. B. debug.hoverValues) ist nichts weiter zu prüfen.
      if (Frame <> nil) and Inside(Binding.Control, Frame.Master) then
        Frame := FrameAround(Frame);
      if Frame = nil then
        Continue;
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
    // 16 Bereiche und „Prüfregeln“ (#909).
    Assert.AreEqual(17, Integer(Length(TopLevelNodes(Page))));
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
        Result := Team;
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
    Assert.Contains(Page.TeamFileInfo.Caption, TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileInvalid));
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.CreatesAndRoundTripsSettings;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  Settings := TAtlasPluginSettings.Defaults;
  Settings.Enabled := False;
  Settings.VisibleRows := 12;
  Settings.Preview := True;
  Settings.HoverTooltip := False;
  Settings.XmlDocExpand := 'collapsed';
  Settings.XmlDocMaxLines := 7;
  Settings.ListWidth := 333;
  Settings.ActionsKey := 0;
  Settings.ExpandKey := $C057;
  Settings.EditorKeysPriority := True;
  Settings.SlashCommands := False;
  Settings.Snippets := False;
  Settings.ImportIdeTemplates := False;
  Settings.ProviderTimeLimitMs := 400;
  Settings.PairOwners := False;
  Settings.PairGuideWidth := 3;
  Settings.PairGuideOpacity := 70;
  Settings.PairColorsLight := '#0071E3,#007C8A,#C000E0,#008700,#4040FF';
  Settings.CodeLensMetrics := False;
  Settings.TodoList := False;
  Settings.MetricsReport := False;
  Settings.TeamFile := False;
  Settings.StartProfiles := False;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
  finally
    Page.Free;
  end;
  Assert.IsFalse(Saved.Enabled);
  Assert.AreEqual(12, Saved.VisibleRows);
  Assert.IsTrue(Saved.Preview);
  Assert.IsFalse(Saved.HoverTooltip);
  Assert.AreEqual('collapsed', Saved.XmlDocExpand);
  Assert.AreEqual(7, Saved.XmlDocMaxLines);
  Assert.AreEqual(333, Saved.ListWidth);
  Assert.AreEqual(0, Saved.ActionsKey);
  Assert.AreEqual($C057, Saved.ExpandKey);
  Assert.AreEqual($6057, Saved.ShrinkKey);
  Assert.IsTrue(Saved.EditorKeysPriority);
  Assert.IsFalse(Saved.SlashCommands);
  Assert.IsFalse(Saved.Snippets);
  Assert.IsFalse(Saved.ImportIdeTemplates);
  Assert.AreEqual(400, Saved.ProviderTimeLimitMs);
  Assert.IsFalse(Saved.PairOwners);
  Assert.AreEqual(3, Saved.PairGuideWidth);
  Assert.AreEqual(70, Saved.PairGuideOpacity);
  Assert.AreEqual('#0071E3,#007C8A,#C000E0,#008700,#4040FF', Saved.PairColorsLight);
  Assert.AreEqual('', Saved.PairColorsDark, 'Standardfarben bleiben leer');
  Assert.IsFalse(Saved.CodeLensMetrics, 'Code Lens Metriken (#66)');
  Assert.IsFalse(Saved.TodoList, 'Befehl (#68)');
  Assert.IsFalse(Saved.MetricsReport, 'Befehl (#66)');
  Assert.IsFalse(Saved.TeamFile, 'Projektdatei (#486)');
  Assert.IsFalse(Saved.StartProfiles, 'Startprofile (#575)');
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
    // Antwort noch während des Ereignisses, wie ohne Server.
    Page.OnIndexMetrics :=
      procedure
      begin
        Page.IndexAnswered('Units: 3');
      end;
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
    Page.IndexAnswered('wird neu aufgebaut');
    Assert.IsFalse(Page.IndexBusy);
    Assert.AreEqual('wird neu aufgebaut', Page.IndexInfo.Caption);
    Assert.IsTrue(Page.IndexRebuild.Enabled and Page.IndexClear.Enabled);
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
    Page.CodeLensTestsCheck.Checked := False;
    Page.TestRunCheck.Checked := False;
    Page.TestsBuildFirstCheck.Checked := False;
    Page.TestsAfterBuildCheck.Checked := True;
    Page.BuildZeroHintsCheck.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.CodeLensTests);
    Assert.IsFalse(Saved.TestRun);
    Assert.IsFalse(Saved.TestsBuildFirst);
    Assert.IsTrue(Saved.TestsAfterBuild);
    Assert.IsTrue(Saved.BuildZeroHints);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.CodeLensTestsCheck.Checked);
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
    Assert.AreEqual('Release', Page.ReleaseConfigsEdit.Text);
    Assert.IsTrue(Page.ReleaseCheckBox(TAtlasReleaseCheck.DebugDefine).Checked);
    Assert.IsNull(Page.ReleaseCheckChoice(TAtlasReleaseCheck.DebugDefine));
    Assert.IsNull(Page.ReleaseCheckBox(TAtlasReleaseCheck.RangeChecks));
    Assert.AreEqual(1, Page.ReleaseCheckChoice(TAtlasReleaseCheck.RangeChecks).Choice, 'prüfen, Soll aus');
    Page.ReleaseGuardCheck.Checked := False;
    Page.BuildGateChoice.Choice := 2;
    Page.ReleaseConfigsEdit.Text := 'Release; Ship ,ship';
    Page.ReleaseCheckBox(TAtlasReleaseCheck.OutputFolder).Checked := False;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.Assertions).Choice := 0;
    Page.ReleaseCheckChoice(TAtlasReleaseCheck.StackFrames).Choice := 2;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ReleaseGuard);
    Assert.AreEqual('block', Saved.BuildGate);
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

procedure TAtlasSettingsPageTests.TestDebugRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.TestDebugCheck.Checked, 'Test debuggen standardmäßig an');
    Assert.IsTrue(Page.TestBreakAtStartCheck.Checked, 'Haltepunkt am Anfang standardmäßig an');
    Assert.IsTrue(Page.DebugHoverValuesCheck.Checked, 'Werte im Hover standardmäßig an (#891)');
    Page.TestDebugCheck.Checked := False;
    Page.TestBreakAtStartCheck.Checked := False;
    Page.DebugHoverValuesCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.TestDebug);
    Assert.IsFalse(Saved.TestBreakAtStart);
    Assert.IsFalse(Saved.DebugHoverValues);
    Saved.TestBreakAtStart := True;
    Saved.DebugHoverValues := True;
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.TestDebugCheck.Checked);
    Assert.IsTrue(Page.TestBreakAtStartCheck.Checked);
    Assert.IsTrue(Page.DebugHoverValuesCheck.Checked);
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
    // Erzeugen, nur das aktive Projekt, 5 s, ein Package ausgeschlossen.
    Page.OpenBuildChoice.Choice := 3;
    Page.OpenBuildScopeChoice.Choice := 1;
    Page.OpenBuildDelayEdit.Text := '5000';
    Page.OpenBuildExcludeEdit.Text := 'Atlas.IDE.Expert.dproj';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.BuildOnOpen);
    Assert.AreEqual('build', Saved.BuildOnOpenKind);
    Assert.AreEqual('active', Saved.BuildOnOpenScope);
    Assert.AreEqual(5000, Saved.BuildOnOpenDelayMs);
    Assert.AreEqual('Atlas.IDE.Expert', Saved.BuildOnOpenExclude);
    Page.LoadFrom(Saved);
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

procedure TAtlasSettingsPageTests.HideElementRoundTrip;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.BlockEndLabelsCheck.Checked, 'standardmäßig an');
    Assert.AreEqual(ShortCutToText($40BE), Page.HideElementKey.Text, 'Strg+.');
    Assert.AreEqual('25', Page.BlockEndLabelsMinLinesEdit.Text, 'Mindestlänge (#620)');
    Assert.IsTrue(Page.DimUnusedUsesCheck.Checked, 'uses abblenden standardmäßig an (#621)');
    Assert.IsTrue(Page.RecursionMarkersCheck.Checked, 'Rekursionssymbole standardmäßig an (#623)');
    Assert.AreEqual('4', Page.RecursionMarkersDepthEdit.Text);
    // Atlas-Spalte in der Zeilenleiste (#768).
    Assert.IsTrue(Page.GutterColumnCheck.Checked, 'Atlas-Spalte standardmäßig an (#768)');
    Assert.IsTrue(Page.GutterColumnProblemsCheck.Checked);
    Assert.IsTrue(Page.GutterColumnCodeActionsCheck.Checked);
    Assert.IsTrue(Page.GutterColumnOverridesCheck.Checked);
    Page.GutterColumnCodeActionsCheck.Checked := False;
    Page.GutterColumnOverridesCheck.Checked := False;
    // Gleichen Text hervorheben (#709).
    Assert.IsTrue(Page.SelectionMatchesCheck.Checked, 'gleichen Text hervorheben standardmäßig an (#709)');
    Assert.AreEqual('3', Page.SelectionMatchesMinLength.Text);
    Assert.IsFalse(Page.SelectionMatchesCaseSensitiveCheck.Checked);
    Assert.IsFalse(Page.SelectionMatchesWholeWordCheck.Checked);
    Assert.IsTrue(Page.SelectionMatchesNavigateF3Check.Checked);
    Assert.AreEqual('1000', Page.SelectionMatchesMaxMatches.Text);
    Page.SelectionMatchesMinLength.Text := '4';
    Page.SelectionMatchesWholeWordCheck.Checked := True;
    Page.SelectionMatchesNavigateF3Check.Checked := False;
    Page.SelectionMatchesMaxMatches.Text := '50';
    // Blockkommentar umschalten (#703).
    Assert.IsTrue(Page.ToggleBlockComment.Checked, 'Blockkommentar umschalten standardmäßig an (#703)');
    Assert.AreEqual(ShortCutToText($A041), Page.ToggleBlockCommentKey.Text);
    Assert.AreEqual(0, Page.ToggleBlockCommentStyle.Choice);
    Assert.AreEqual(0, Page.ToggleBlockCommentFallback.Choice);
    Assert.IsFalse(Page.ToggleBlockCommentOwnLines.Checked);
    Assert.AreEqual(0, Page.ToggleBlockCommentScope.Choice);
    Page.ToggleBlockCommentStyle.Choice := 1;
    Page.ToggleBlockCommentFallback.Choice := 1;
    Page.ToggleBlockCommentOwnLines.Checked := True;
    Page.ToggleBlockCommentScope.Choice := 1;
    // Neue Zeile ober- oder unterhalb (#700).
    Assert.IsTrue(Page.NewLineAround.Checked, 'Neue Zeile ober-/unterhalb standardmäßig an (#700)');
    Assert.AreEqual(ShortCutToText($200D), Page.NewLineBelowKey.Text);
    Assert.AreEqual(ShortCutToText($C00D), Page.NewLineAboveKey.Text);
    Assert.IsTrue(Page.NewLineAroundStatementAware.Checked);
    Page.NewLineAroundStatementAware.Checked := False;
    // Umschließung entfernen (#657).
    Assert.IsTrue(Page.Unwrap.Checked, 'Umschließung entfernen standardmäßig an (#657)');
    Assert.AreEqual(ShortCutToText($602E), Page.UnwrapKey.Text);
    Page.Unwrap.Checked := False;
    // Markierung beim Tippen umschließen (#672).
    Assert.IsTrue(Page.WrapSelection.Checked, 'Umschließen standardmäßig an (#672)');
    Assert.AreEqual('([{''', Page.WrapSelectionChars.Text);
    Page.WrapSelectionChars.Text := ' ([<';
    // Fehlertext am Zeilenende, Zähler und Sprungtasten (#509).
    Assert.AreEqual(1, Page.InlineDiagnostics.Choice, 'nur Fehler');
    Assert.IsTrue(Page.ProblemsStatusCounterCheck.Checked);
    Assert.AreEqual(ShortCutToText($C077), Page.NextProblemKey.Text);
    Page.BlockEndLabelsCheck.Checked := False;
    Page.DimUnusedUsesCheck.Checked := False;
    Page.RecursionMarkersCheck.Checked := False;
    Page.RecursionMarkersDepthEdit.Text := '2';
    Page.InlineDiagnostics.Choice := 2;
    Page.ProblemsStatusCounterCheck.Checked := False;
    Page.PreviousProblemKey.Text := '';
    Page.BlockEndLabelsMinLinesEdit.Text := '30';
    Page.HideElementKey.Text := '';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.BlockEndLabels, 'abschaltbar');
    Assert.AreEqual(30, Saved.BlockEndLabelsMinLines);
    Assert.IsFalse(Saved.DimUnusedUses);
    Assert.IsFalse(Saved.RecursionMarkers);
    Assert.AreEqual(2, Saved.RecursionMarkersDepth);
    Assert.IsTrue(Saved.GutterColumn);
    Assert.IsTrue(Saved.GutterColumnProblems);
    Assert.IsFalse(Saved.GutterColumnCodeActions);
    Assert.IsFalse(Saved.GutterColumnOverrides);
    Assert.IsTrue(Saved.SelectionMatches);
    Assert.AreEqual(4, Saved.SelectionMatchesMinLength);
    Assert.IsFalse(Saved.SelectionMatchesCaseSensitive);
    Assert.IsTrue(Saved.SelectionMatchesWholeWord);
    Assert.IsFalse(Saved.SelectionMatchesNavigateF3);
    Assert.AreEqual(50, Saved.SelectionMatchesMaxMatches);
    Assert.IsTrue(Saved.ToggleBlockComment);
    Assert.AreEqual($A041, Saved.ToggleBlockCommentKey);
    Assert.AreEqual('parens', Saved.ToggleBlockCommentStyle);
    Assert.AreEqual('refuse', Saved.ToggleBlockCommentFallback);
    Assert.IsTrue(Saved.ToggleBlockCommentOwnLines);
    Assert.AreEqual('line', Saved.ToggleBlockCommentWithoutSelection);
    Assert.IsTrue(Saved.NewLineAround);
    Assert.AreEqual($200D, Saved.NewLineBelowKey);
    Assert.AreEqual($C00D, Saved.NewLineAboveKey);
    Assert.IsFalse(Saved.NewLineAroundStatementAware);
    Assert.IsFalse(Saved.Unwrap);
    Assert.AreEqual($602E, Saved.UnwrapKey);
    Assert.IsTrue(Saved.WrapSelection);
    Assert.AreEqual('([<', Saved.WrapSelectionChars);
    Assert.AreEqual('errorsAndWarnings', Saved.InlineDiagnostics);
    Assert.IsFalse(Saved.ProblemsStatusCounter);
    Assert.AreEqual($C077, Saved.NextProblemKey);
    Assert.AreEqual(0, Saved.PreviousProblemKey);
    Assert.AreEqual(0, Saved.HideElementKey, 'leer = keine Taste');
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.BlockEndLabelsCheck.Checked);
    Assert.IsFalse(Page.DimUnusedUsesCheck.Checked);
    Assert.IsFalse(Page.RecursionMarkersCheck.Checked);
    Assert.IsFalse(Page.GutterColumnOverridesCheck.Checked);
    Assert.IsTrue(Page.SelectionMatchesWholeWordCheck.Checked);
    Assert.AreEqual(1, Page.ToggleBlockCommentScope.Choice);
    Assert.AreEqual(2, Page.InlineDiagnostics.Choice);
    Assert.AreEqual('', Page.HideElementKey.Text);
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

procedure TAtlasSettingsPageTests.WelcomeLayoutsOnPage;
var
  Page: TAtlasSettingsPage;
  Saved: TAtlasPluginSettings;
  Layouts: TAtlasWelcomeLayouts;
  Answer, Told: string;
begin
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.OnAskLayoutName :=
      function(const APrompt: string; var AName: string): Boolean
      begin
        AName := Answer;
        Result := Answer <> '';
      end;
    Page.OnConfirmLayout :=
      function(const AText: string; AQuestion: Boolean): Boolean
      begin
        Told := AText;
        Result := True;
      end;
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Assert.IsTrue(Page.WelcomeCustomLayout.Checked);
    Assert.AreEqual('2', Page.WelcomeColumns.Text);
    Assert.AreEqual(0, Page.WelcomeActiveLayout.Choice);
    Assert.AreEqual(1, Integer(Length(Page.PageLayouts.Items)));
    Assert.IsFalse(Page.WelcomeLayoutDelete.Enabled, 'das letzte Layout bleibt');
    // Neues Layout „Präsentation“: Kopie, danach aktiv; dort Testergebnisse aus, eine Spalte.
    Answer := 'Präsentation';
    Page.WelcomeLayoutNew.Click;
    Assert.AreEqual(1, Page.WelcomeActiveLayout.Choice);
    Assert.AreEqual('Präsentation', Page.PageLayouts.ActiveName);
    Assert.IsTrue(Page.WelcomeLayoutDelete.Enabled);
    Page.WelcomeTests.Checked := False;
    Page.WelcomeWhatsNew.Choice := 0;
    Page.WelcomeColumns.Text := '1';
    // Zurück zu „Standard“: dessen Sichtbarkeit und Spalten.
    Page.SelectWelcomeLayout(0);
    Assert.IsTrue(Page.WelcomeTests.Checked);
    Assert.AreEqual(1, Page.WelcomeWhatsNew.Choice, '„Neu in Atlas“ wieder nach einem Update');
    Assert.AreEqual('2', Page.WelcomeColumns.Text);
    Page.SelectWelcomeLayout(1);
    Assert.IsFalse(Page.WelcomeTests.Checked);
    Assert.AreEqual(0, Page.WelcomeWhatsNew.Choice);
    Assert.AreEqual('1', Page.WelcomeColumns.Text);
    // Vergebener Name: Hinweis, nichts geändert.
    Answer := 'standard';
    Page.WelcomeLayoutRename.Click;
    Assert.IsTrue(Pos('standard', Told) > 0);
    Assert.AreEqual('Präsentation', Page.PageLayouts.ActiveName);
    Answer := 'Vortrag';
    Page.WelcomeLayoutRename.Click;
    Assert.AreEqual('Vortrag', Page.PageLayouts.ActiveName);
    // Abbrechen ändert nichts.
    Answer := '';
    Page.WelcomeLayoutNew.Click;
    Assert.AreEqual(2, Integer(Length(Page.PageLayouts.Items)));
    Page.WelcomeCustomLayout.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.WelcomePageCustomLayout);
    Assert.AreEqual('Vortrag', Saved.WelcomePageActiveLayout);
    Assert.AreEqual(1, Saved.WelcomePageColumns);
    Assert.IsFalse(Saved.WelcomePageTests);
    Assert.AreEqual('off', Saved.WelcomePageWhatsNew);
    Layouts := TAtlasWelcomeCustomizing.Load(Saved);
    Assert.AreEqual(2, Integer(Length(Layouts.Items)));
    Assert.AreEqual('Standard', Layouts.Items[0].Name);
    Assert.AreEqual(2, Layouts.Items[0].Columns);
    // Wieder laden und löschen: „Standard“ bleibt mit seiner Sichtbarkeit.
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.WelcomeCustomLayout.Checked);
    Assert.AreEqual(1, Page.WelcomeActiveLayout.Choice);
    Page.WelcomeLayoutDelete.Click;
    Assert.IsTrue(Pos('Vortrag', Told) > 0, 'Rückfrage nennt das Layout');
    Assert.AreEqual(0, Page.WelcomeActiveLayout.Choice);
    Assert.IsTrue(Page.WelcomeTests.Checked);
    Assert.AreEqual('2', Page.WelcomeColumns.Text);
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual('', Saved.WelcomePageLayouts, 'nur noch die Vorgabe');
    Assert.AreEqual('Standard', Saved.WelcomePageActiveLayout);
    // „Einstellungen dazu …“ (#628) findet die neuen Einstellungen und Meine Issues.
    Assert.IsTrue(Page.Reveal('WelcomePageCustomLayout'));
    Assert.IsTrue(Page.Reveal('WelcomePageColumns'));
    Assert.IsTrue(Page.Reveal('WelcomePageActiveLayout'));
    Assert.IsTrue(Page.Reveal('WelcomePageIssues'));
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.WelcomeSettingsRoundTrip;
var
  Page: TAtlasSettingsPage;
  Settings, Saved: TAtlasPluginSettings;
begin
  // #753: Ein/Aus, Ort (Willkommensseite oder Fenster „Atlas-Start“), Atlas-Layout, Kopf und Grußzeile;
  // #760: Suchfeld, Gruppe „Symbole“ und Taste; #756: Karte „Neu in Atlas“; #592: Bereich „Projekte“;
  // #762: Bereich „Nicht gesichert“; #755: Bereich „Weiterarbeiten“; #754: Zustandskachel „Atlas“; #757: Karte „Atlas entdecken“, Zählung und
  // ihre Knöpfe.
  Settings := TAtlasPluginSettings.Defaults;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.WelcomeEnabled.Checked);
    Assert.IsFalse(Page.WelcomeOpenOnStart.Checked, 'Atlas-Start nur auf Wunsch (#1114)');
    Assert.IsTrue(Page.WelcomeOpenWhenNoProject.Checked, 'Atlas-Start ohne Projekt (#1114)');
    Assert.IsTrue(Page.WelcomeHeader.Checked);
    Assert.IsTrue(Page.WelcomeGreeting.Checked);
    Assert.IsTrue(Page.WelcomeSearch.Checked);
    Assert.IsTrue(Page.WelcomeSearchSymbols.Checked);
    Assert.AreEqual(ShortCutToText($4045), Page.WelcomeSearchKey.Text);
    Assert.AreEqual(1, Page.WelcomeWhatsNew.Choice, 'afterUpdate');
    // #755: Bereich „Weiterarbeiten“ und Reiter „Gemerkt“.
    Assert.IsTrue(Page.WelcomeContinue.Checked);
    Assert.AreEqual('5', Page.WelcomeContinueCount.Text);
    Assert.IsTrue(Page.WelcomeContinueIncoming.Checked);
    Assert.IsFalse(Page.WelcomeContinueFetch.Checked);
    Assert.IsTrue(Page.WelcomeSaved.Checked);
    Assert.IsTrue(Page.WelcomeProjects.Checked);
    Assert.AreEqual('8', Page.WelcomeMaxProjects.Text);
    Assert.IsTrue(Page.WelcomeRefreshVcs.Checked);
    // #758: Projektverlauf mit 30 Builds und allen fünf Reihen.
    Assert.IsTrue(Page.WelcomeTrends.Checked);
    Assert.AreEqual('30', Page.WelcomeTrendsPoints.Text);
    Assert.IsTrue(Page.WelcomeTrendsSeries(TAtlasTrendSeries.Warnings).Checked);
    Assert.IsTrue(Page.WelcomeTrendsSeries(TAtlasTrendSeries.MethodLength).Checked);
    // #763: Testergebnisse an, Build-Server aus (Jenkins, alle 10 Min., Hinweis an), Befehl Atlas.CiLogin an.
    Assert.IsTrue(Page.WelcomeTests.Checked);
    Assert.AreEqual('5', Page.WelcomeTestsMaxFailures.Text);
    Assert.IsFalse(Page.WelcomeTestsCi.Checked);
    Assert.AreEqual(0, Page.WelcomeTestsCiProvider.Choice);
    Assert.AreEqual('10', Page.WelcomeTestsCiInterval.Text);
    Assert.IsTrue(Page.WelcomeTestsCiNotify.Checked);
    Assert.IsTrue(Page.CiLogin.Checked);
    // #765: Meine Issues aus, Tracker aus der .atlas, Branch anlegen, Präfix „{kennung} “, Befehl Atlas.TrackerLogin an.
    Assert.IsFalse(Page.WelcomeIssues.Checked);
    Assert.AreEqual(0, Page.WelcomeIssuesTracker.Choice);
    Assert.AreEqual('', Page.WelcomeIssuesQuery.Text);
    Assert.AreEqual(0, Page.WelcomeIssuesStart.Choice);
    Assert.AreEqual('', Page.WelcomeIssuesBranchPattern.Text);
    Assert.AreEqual('', Page.WelcomeIssuesBranchBase.Text);
    Assert.AreEqual('{kennung} ', Page.WelcomeIssuesCommitPattern.Text);
    Assert.IsTrue(Page.TrackerLogin.Checked);
    // #764: Schnellaktionen an, alle sechs Knöpfe, wt.exe, Strg+B und Strg+T.
    Assert.IsTrue(Page.WelcomeQuickActions.Checked);
    Assert.IsTrue(Page.WelcomeQuickActionsItem(TAtlasQuickAction.Build).Checked);
    Assert.IsTrue(Page.WelcomeQuickActionsItem(TAtlasQuickAction.Console).Checked);
    Assert.AreEqual('wt.exe', Page.WelcomeQuickActionsConsole.Text);
    Assert.AreEqual(ShortCutToText($4042), Page.WelcomeQuickActionsBuildKey.Text);
    Assert.AreEqual(ShortCutToText($4054), Page.WelcomeQuickActionsTestKey.Text);
    Assert.IsTrue(Page.WelcomeUnsaved.Checked);
    Assert.AreEqual('0', Page.WelcomeUnsavedMinAge.Text);
    Assert.AreEqual('24', Page.WelcomeUnsavedWarn.Text);
    Assert.AreEqual('72', Page.WelcomeUnsavedAlert.Text);
    Assert.IsFalse(Page.WelcomeUnsavedHideClean.Checked);
    Assert.IsTrue(Page.WelcomeStatusTile.Checked);
    Assert.IsFalse(Page.WelcomeStatusTileOnlyProblems.Checked);
    Assert.IsTrue(Page.WelcomeDiscover.Checked);
    Assert.IsTrue(Page.TipsUsageTracking.Checked);
    // #766: Bereich „Hilfe und Rückmeldung“, Ziel der Issue-Seite, Ordner (leer = Desktop).
    Assert.IsTrue(Page.WelcomeHelp.Checked);
    Assert.AreEqual(TAtlasPluginSettings.DefaultHelpReportUrl, Page.WelcomeHelpReportUrl.Text);
    Assert.AreEqual('', Page.WelcomeHelpReportFolder.Text);
    Page.WelcomeEnabled.Checked := False;
    Page.WelcomeOpenOnStart.Checked := True;
    Page.WelcomeOpenWhenNoProject.Checked := False;
    Page.WelcomeHeader.Checked := False;
    Page.WelcomeGreeting.Checked := False;
    Page.WelcomeSearch.Checked := False;
    Page.WelcomeSearchSymbols.Checked := False;
    Page.WelcomeSearchKey.Text := ShortCutToText($6046);
    Page.WelcomeWhatsNew.Choice := 2;
    Page.WelcomeContinue.Checked := False;
    Page.WelcomeContinueCount.Text := '50';
    Page.WelcomeContinueIncoming.Checked := False;
    Page.WelcomeContinueFetch.Checked := True;
    Page.WelcomeSaved.Checked := False;
    Page.WelcomeProjects.Checked := False;
    Page.WelcomeMaxProjects.Text := '99';
    Page.WelcomeRefreshVcs.Checked := False;
    Page.WelcomeTrends.Checked := False;
    Page.WelcomeTrendsPoints.Text := '500';
    Page.WelcomeTrendsSeries(TAtlasTrendSeries.RuleHits).Checked := False;
    Page.WelcomeTrendsSeries(TAtlasTrendSeries.Duration).Checked := False;
    Page.WelcomeTests.Checked := False;
    Page.WelcomeTestsMaxFailures.Text := '99';
    Page.WelcomeTestsCi.Checked := True;
    Page.WelcomeTestsCiInterval.Text := '0';
    Page.WelcomeTestsCiNotify.Checked := False;
    Page.CiLogin.Checked := False;
    Page.WelcomeIssues.Checked := True;
    Page.WelcomeIssuesTracker.Choice := 2;
    Page.WelcomeIssuesQuery.Text := '  for: me State: {In Progress} ';
    Page.WelcomeIssuesStart.Choice := 1;
    Page.WelcomeIssuesBranchPattern.Text := ' {kennung}/{kurztitel} ';
    Page.WelcomeIssuesBranchBase.Text := ' develop ';
    Page.WelcomeIssuesCommitPattern.Text := '[{kennung}] ';
    Page.TrackerLogin.Checked := False;
    Page.WelcomeQuickActions.Checked := False;
    Page.WelcomeQuickActionsItem(TAtlasQuickAction.Console).Checked := False;
    Page.WelcomeQuickActionsItem(TAtlasQuickAction.Run).Checked := False;
    Page.WelcomeQuickActionsConsole.Text := '  pwsh.exe ';
    Page.WelcomeQuickActionsBuildKey.Text := '';
    Page.WelcomeQuickActionsTestKey.Text := ShortCutToText($C054);
    Page.WelcomeUnsaved.Checked := False;
    Page.WelcomeUnsavedMinAge.Text := '2';
    Page.WelcomeUnsavedWarn.Text := '48';
    Page.WelcomeUnsavedAlert.Text := '12';
    Page.WelcomeUnsavedHideClean.Checked := True;
    Page.WelcomeStatusTile.Checked := False;
    Page.WelcomeStatusTileOnlyProblems.Checked := True;
    Page.WelcomeDiscover.Checked := False;
    Page.TipsUsageTracking.Checked := False;
    Page.WelcomeHelp.Checked := False;
    Page.WelcomeHelpReportUrl.Text := ' https://example.org/issues/new ';
    Page.WelcomeHelpReportFolder.Text := ' D:\Diagnose ';
    Assert.IsTrue(Page.WelcomeProjectSetup.Checked, 'Vorgabe an (#759)');
    Assert.IsTrue(Page.WelcomeNewFromTemplate.Checked, 'Vorgabe an (#759)');
    Page.WelcomeProjectSetup.Checked := False;
    Page.WelcomeNewFromTemplate.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.WelcomePageHelp);
    Assert.AreEqual('https://example.org/issues/new', Saved.WelcomePageHelpReportUrl);
    Assert.AreEqual('D:\Diagnose', Saved.WelcomePageHelpReportFolder);
    Assert.IsFalse(Saved.WelcomePageProjectSetup);
    Assert.IsFalse(Saved.WelcomePageNewFromTemplate);
    Assert.IsFalse(Saved.WelcomePage);
    Assert.IsTrue(Saved.WelcomePageOpenOnStart);
    Assert.IsFalse(Saved.WelcomePageOpenWhenNoProject);
    Assert.IsFalse(Saved.WelcomePageHeader);
    Assert.IsFalse(Saved.WelcomePageGreeting);
    Assert.IsFalse(Saved.WelcomePageSearch);
    Assert.IsFalse(Saved.WelcomePageSearchSymbols);
    Assert.AreEqual($6046, Saved.WelcomePageSearchKey);
    Assert.AreEqual('always', Saved.WelcomePageWhatsNew);
    Assert.IsFalse(Saved.WelcomePageContinue);
    Assert.AreEqual(20, Saved.WelcomePageContinueCount, 'auf 1–20 begrenzt');
    Assert.IsFalse(Saved.WelcomePageContinueIncoming);
    Assert.IsTrue(Saved.WelcomePageContinueFetch);
    Assert.IsFalse(Saved.WelcomePageSaved);
    Assert.IsFalse(Saved.WelcomePageProjectStatus);
    Assert.AreEqual(30, Saved.WelcomePageMaxProjects, 'auf 1–30 begrenzt');
    Assert.IsFalse(Saved.WelcomePageRefreshVcs);
    Assert.IsFalse(Saved.WelcomePageTrends);
    Assert.AreEqual(100, Saved.WelcomePageTrendsPoints, 'auf 2–100 begrenzt');
    Assert.AreEqual('warnings,todos,methodLength', Saved.WelcomePageTrendsSeries);
    Assert.IsFalse(Saved.WelcomePageTests);
    Assert.AreEqual(50, Saved.WelcomePageTestsMaxFailures, 'auf 1–50 begrenzt');
    Assert.IsTrue(Saved.WelcomePageTestsCi);
    Assert.AreEqual('jenkins', Saved.WelcomePageTestsCiProvider);
    Assert.AreEqual(1, Saved.WelcomePageTestsCiIntervalMinutes, 'auf 1–1440 begrenzt');
    Assert.IsFalse(Saved.WelcomePageTestsCiNotify);
    Assert.IsFalse(Saved.CiLogin);
    Assert.IsTrue(Saved.WelcomePageIssues);
    Assert.AreEqual('youtrack', Saved.WelcomePageIssuesTracker);
    Assert.AreEqual('for: me State: {In Progress}', Saved.WelcomePageIssuesQuery);
    Assert.AreEqual('remember', Saved.WelcomePageIssuesStart);
    Assert.AreEqual('{kennung}/{kurztitel}', Saved.WelcomePageIssuesBranchPattern);
    Assert.AreEqual('develop', Saved.WelcomePageIssuesBranchBase);
    Assert.AreEqual('[{kennung}] ', Saved.WelcomePageIssuesCommitPattern, 'Leerzeichen am Ende bleibt');
    Assert.IsFalse(Saved.TrackerLogin);
    Assert.IsFalse(Saved.WelcomePageQuickActions);
    Assert.AreEqual('build,tests,pull,folder', Saved.WelcomePageQuickActionsItems, 'ohne run und console');
    Assert.AreEqual('pwsh.exe', Saved.WelcomePageQuickActionsConsole);
    Assert.AreEqual(0, Saved.WelcomePageQuickActionsBuildKey, 'leer = keine Taste');
    Assert.AreEqual($C054, Saved.WelcomePageQuickActionsTestKey);
    Assert.IsFalse(Saved.WelcomePageUnsaved);
    Assert.AreEqual(2, Saved.WelcomePageUnsavedMinAgeHours);
    Assert.AreEqual(48, Saved.WelcomePageUnsavedWarnHours);
    Assert.AreEqual(48, Saved.WelcomePageUnsavedAlertHours, 'rot nie vor gelb');
    Assert.IsTrue(Saved.WelcomePageUnsavedHideWhenClean);
    Assert.IsFalse(Saved.WelcomePageStatusTile);
    Assert.IsTrue(Saved.WelcomePageStatusTileOnlyProblems);
    Assert.IsFalse(Saved.WelcomePageDiscover);
    Assert.IsFalse(Saved.TipsUsageTracking);
    Page.LoadFrom(Saved);
    Assert.IsFalse(Page.WelcomeTrends.Checked);
    Assert.AreEqual('100', Page.WelcomeTrendsPoints.Text);
    Assert.IsFalse(Page.WelcomeTrendsSeries(TAtlasTrendSeries.RuleHits).Checked);
    Assert.IsTrue(Page.WelcomeTrendsSeries(TAtlasTrendSeries.Todos).Checked);
    Assert.IsFalse(Page.WelcomeTests.Checked);
    Assert.AreEqual('50', Page.WelcomeTestsMaxFailures.Text);
    Assert.IsTrue(Page.WelcomeTestsCi.Checked);
    Assert.AreEqual('1', Page.WelcomeTestsCiInterval.Text);
    Assert.IsFalse(Page.WelcomeTestsCiNotify.Checked);
    Assert.IsFalse(Page.CiLogin.Checked);
    Assert.IsTrue(Page.WelcomeIssues.Checked);
    Assert.AreEqual(2, Page.WelcomeIssuesTracker.Choice);
    Assert.AreEqual(1, Page.WelcomeIssuesStart.Choice);
    Assert.AreEqual('develop', Page.WelcomeIssuesBranchBase.Text);
    Assert.AreEqual('[{kennung}] ', Page.WelcomeIssuesCommitPattern.Text);
    Assert.IsFalse(Page.TrackerLogin.Checked);
    Assert.IsFalse(Page.WelcomeQuickActions.Checked);
    Assert.IsFalse(Page.WelcomeQuickActionsItem(TAtlasQuickAction.Console).Checked);
    Assert.IsTrue(Page.WelcomeQuickActionsItem(TAtlasQuickAction.Pull).Checked);
    Assert.AreEqual('pwsh.exe', Page.WelcomeQuickActionsConsole.Text);
    Assert.AreEqual('', Page.WelcomeQuickActionsBuildKey.Text);
    Assert.IsFalse(Page.WelcomeHelp.Checked);
    Assert.AreEqual('https://example.org/issues/new', Page.WelcomeHelpReportUrl.Text);
    Assert.AreEqual('D:\Diagnose', Page.WelcomeHelpReportFolder.Text);
    Assert.IsFalse(Page.WelcomeDiscover.Checked);
    Assert.IsFalse(Page.TipsUsageTracking.Checked);
    Assert.IsTrue(Page.WelcomeOpenOnStart.Checked);
    Assert.AreEqual(2, Page.WelcomeWhatsNew.Choice);
    Page.WelcomeWhatsNew.Choice := 0;
    // Keine Webadresse als Ziel: die Vorgabe.
    Page.WelcomeHelpReportUrl.Text := 'cmd.exe';
    Page.SaveTo(Saved);
    Assert.AreEqual('off', Saved.WelcomePageWhatsNew);
    Assert.AreEqual(TAtlasPluginSettings.DefaultHelpReportUrl, Saved.WelcomePageHelpReportUrl);
  finally
    Page.Free;
  end;
end;

procedure TAtlasSettingsPageTests.UsageButtonsCallBack;
var
  Page: TAtlasSettingsPage;
  Calls: string;
begin
  // #757: „Zählung zurücksetzen“ und „Gesperrte Tipps wieder zeigen“ rufen die IDE-Schicht, je einmal.
  Calls := '';
  Page := TAtlasSettingsPage.Create(nil);
  try
    // Die Knöpfe gehören zu „Atlas entdecken“ und sind nur mit dessen Schalter frei (#890).
    Page.LoadFrom(TAtlasPluginSettings.Defaults);
    Page.OnResetUsage :=
      procedure
      begin
        Calls := Calls + 'reset;';
      end;
    Page.OnUnblockTips :=
      procedure
      begin
        Calls := Calls + 'unblock;';
      end;
    Assert.IsTrue(Page.ResetUsageButton.Enabled);
    Page.ResetUsageButton.Click;
    Page.UnblockTipsButton.Click;
    Assert.AreEqual('reset;unblock;', Calls);
    Assert.IsFalse(Page.ResetUsageButton.Enabled, 'erledigt');
    Assert.IsFalse(Page.UnblockTipsButton.Enabled, 'erledigt');
  finally
    Page.Free;
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
    Page.OnRemoveFavorites :=
      procedure(AKeys: TArray<string>)
      var
        Key: string;
      begin
        for Key in AKeys do
          Favorites.Remove(Key);
      end;
    Page.OnFavorites :=
      function: TArray<TAtlasFavorite>
      begin
        Result := Favorites.Items;
      end;
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
    Assert.IsFalse(Page.StickyScroll.Checked);
    Assert.AreEqual('3', Page.StickyScrollMaxLines.Text);
    Page.StickyScroll.Checked := True;
    Page.StickyScrollMaxLines.Text := '2';
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.StickyScroll);
    Assert.AreEqual(2, Saved.StickyScrollMaxLines);
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
  Settings.OpenDelayMs := 300;
  Settings.ListWidth := 400;
  Page := TAtlasSettingsPage.Create(nil);
  try
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.CommitChars.Checked);
    Assert.IsFalse(Page.AutoUses.Checked);
    Assert.IsFalse(Page.ParameterHints.Checked);
    Assert.AreEqual('300', Page.OpenDelay.Text);
    Assert.IsFalse(Page.AutoWidth.Checked);
    Page.CommitChars.Checked := True;
    Page.OpenDelay.Text := '0';
    Page.AutoWidth.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CommitCharacters);
    Assert.IsFalse(Saved.AutoUses);
    Assert.IsFalse(Saved.ParameterHints);
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
    Page.OnSuppressions :=
      function: TArray<string>
      begin
        Result := ['no-with: 3 (ungenutzt 1, in 2 Dateien)'];
      end;
    Page.OnClearCache :=
      function: string
      begin
        Result := 'Cache leer';
      end;
    Page.Confirm :=
      function(AQuestion: string): Boolean
      begin
        Result := True;
      end;
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
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
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
    Dialog := TAtlasProjectSettingsDialog.CreateDialog(nil, Model, 'C:\Ptlas.json');
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
    Assert.IsTrue(SheetOf(Page.ProblemsWindowCheck) = Page.NodeSheet('rules.window'));
    Assert.IsTrue(SheetOf(Page.ProblemsLiveCheck) = Page.NodeSheet('rules.window'));
    Assert.IsNotNull(Page.NodeSheet('rules.profiles'));
    Assert.IsTrue(SheetOf(Page.BaselineInfoLabel) = Page.NodeSheet('rules.profiles'));
    Assert.IsNull(Page.NodeSheet('rules.group.threads'), 'keine Regelgruppen in Tools › Optionen');
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
    Settings.HoverProblemActions := False;
    Page.LoadFrom(Settings);
    Assert.AreEqual(1, Page.ProblemsWindowScopeChoice.Choice);
    Assert.AreEqual(2, Page.ProblemsWindowGroupByChoice.Choice);
    Assert.IsFalse(Page.ProblemsLiveCheck.Checked, 'Live geladen');
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
    Assert.AreEqual('both', Settings.ProblemsCompilerMerge);
    Assert.IsFalse(Settings.ProblemsShowCompilerCode);
    Assert.AreEqual('file', Settings.ProblemsWindowScope);
    Assert.AreEqual('rule', Settings.ProblemsWindowGroupBy);
    Assert.IsTrue(Settings.ProblemsWindowCompiler);
    Assert.IsFalse(Settings.ProblemsLive, 'Live gespeichert');
    Assert.IsFalse(Settings.HoverProblemActions, 'Hover-Aktionen gespeichert');
  finally
    Host.Free;
    TAtlasSettingsPage.ForgetTreeState;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.