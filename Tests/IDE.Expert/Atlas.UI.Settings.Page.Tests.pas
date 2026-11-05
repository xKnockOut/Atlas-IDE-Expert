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
    [Test]
    procedure SafeModeRoundTrips;
    [Test]
    procedure UndoSettingsRoundTrip;
    /// <summary>Favoriten (#458): Schalter, Liste, „Entfernen“ und „Alle entfernen“.</summary>
    [Test]
    procedure FavoritesListAndRemove;
    [Test]
    procedure AcceptOptionsRoundTrip;
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
    procedure RulesAreaWindowSettings;
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
  Atlas.UI.Settings.Page.Tree,
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Favorites,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  Atlas.Core.Settings.TeamFile,
  Atlas.Core.Style.Symbol,
  System.StrUtils,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.Completion,
  Atlas.UI.Settings.Page.EditorView,
  Atlas.UI.Settings.Page.General,
  Atlas.UI.Settings.Page.Index,
  Atlas.UI.Settings.Page.Robustness,
  Atlas.UI.Settings.Page.Rules,
  Atlas.UI.Settings.Page.Startup,
  Atlas.UI.Settings.Page.TeamFile;

procedure TAtlasSettingsPageTests.WarmUp;
begin
  WarmUpSettingsPage;
  FilterAndResetPerNode;
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
/// <summary>#890: Bereiche oben im Baum in fester Reihenfolge; jede Seite hat Inhalt und keinen sichtbaren
/// Reiter.</summary>
procedure AssertTreeAreas(APage: TAtlasSettingsPage; const AAreas: TArray<TTreeNode>);
var
  mIndex: Integer;
begin
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabGeneral), AAreas[0].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabCompiler), AAreas[6].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabRules), AAreas[7].Text);
  // Ohne angemeldete Module nur die Bereiche von Base (#1456): Debuggen, Release-Build, Willkommensseite und
  // Issue-Tracker bringen die Module als Abschnitte mit.
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabCommands), AAreas[8].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUndo), AAreas[11].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabUnitSearch), AAreas[12].Text);
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabVcs), AAreas[13].Text, 'eigener Bereich (#1285)');
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabTeamFile), AAreas[14].Text);
  Assert.IsTrue(APage.Pages.PageCount > 14, 'Unterpunkte haben eigene Seiten');
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
  TAtlasSettingsPageTree.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    Areas := TopLevelNodes(Page);
    Assert.AreEqual(15, Integer(Length(Areas)));
    AssertTreeAreas(Page, Areas);
    Assert.IsTrue(Page.Pages.ActivePage = Page.Pages.Pages[0], 'erstes Öffnen: Allgemein');
    // Unterpunkt „Minikarte“ unter „Editor“ mit ihren Einstellungen und nichts sonst.
    Minimap := Page.NodeSheet('editor.minimap');
    Assert.IsNotNull(Minimap);
    Assert.AreEqual('editor.minimap', Page.NodeOfSheet(Minimap));
    Assert.IsTrue(SheetOf(EditOf(Page, 'MinimapWidth')) = Minimap);
    Assert.IsFalse(SheetOf(CheckOf(Page, 'StickyScroll')) = Minimap);
    Node := TreeNodeOf(Page, Minimap);
    Assert.IsNotNull(Node, 'Knoten im Baum');
    Assert.AreEqual(1, Node.Level);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabEditor), Node.Parent.Text);
    Page.Navigation.OnChange(Page.Navigation, Areas[11]);
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
    TAtlasSettingsPageTree.ForgetTreeState;
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
    Assert.IsTrue(Frame.Master = CheckOf(Page, 'Minimap'), 'Hauptschalter oben im Rahmen');
    Assert.IsTrue(Page.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled and EditOf(Page, 'MinimapWidth').Enabled);
    Assert.IsFalse(Page.SheetGray(Page.NodeSheet('editor.minimap')));
    CheckOf(Page, 'Minimap').Checked := False;
    Assert.IsTrue(CheckOf(Page, 'Minimap').Enabled, 'der Hauptschalter bleibt bedienbar');
    Assert.IsFalse(Page.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(EditOf(Page, 'MinimapWidth').Enabled, 'Textfeld gesperrt');
    Assert.IsFalse(Frame.Reason.Visible, 'kein Grund: Der Schalter steht im Rahmen');
    Assert.IsTrue(Page.SheetGray(Page.NodeSheet('editor.minimap')), 'Knoten grau');
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual(90, Saved.MinimapWidth, 'Wert bleibt erhalten');
    CheckOf(Page, 'Minimap').Checked := True;
    Assert.IsTrue(Page.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled and EditOf(Page, 'MinimapWidth').Enabled, 'wieder frei');
    // Experimentelle Funktionen aus: auch der Hauptschalter gesperrt, mit Grund im Rahmen.
    Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := False;
    Assert.IsFalse(CheckOf(Page, 'Minimap').Enabled);
    Assert.IsFalse(EditOf(Page, 'MinimapWidth').Enabled);
    Assert.IsTrue(Frame.Reason.Visible);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsLockedExperimental), Frame.Reason.Caption);
    Assert.IsTrue(CheckOf(Page, 'Minimap').Checked, 'Wert bleibt');
    Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
    Assert.IsTrue(CheckOf(Page, 'Minimap').Enabled);
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
    Assert.IsTrue(CheckOf(Page, 'StickyScroll').Enabled and EditOf(Page, 'StickyScrollMaxLines').Enabled);
    Master := Page.FrameOf('Enabled').Master as TCheckBox;
    Master.Checked := False;
    Assert.IsFalse(CheckOf(Page, 'StickyScroll').Enabled, 'Hauptschalter gesperrt');
    Assert.IsFalse(EditOf(Page, 'StickyScrollMaxLines').Enabled, 'Unteroption gesperrt');
    Assert.IsTrue(Frame.Reason.Visible, 'Grund im Rahmen');
    Assert.IsTrue(Pos(TAtlasStrings.Text(TAtlasTextId.SettingsEnabled).Replace('&', ''), Frame.Reason.Caption) > 0,
      Frame.Reason.Caption);
    Assert.IsFalse(Page.ControlOf('PairGuides').Enabled, 'auch Klammerfarben');
    Master.Checked := True;
    Assert.IsTrue(CheckOf(Page, 'StickyScroll').Enabled and EditOf(Page, 'StickyScrollMaxLines').Enabled);
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
    Assert.IsFalse(CheckOf(Page, 'Minimap').Checked, 'Spiegel schaltet');
    Assert.IsFalse(EditOf(Page, 'MinimapWidth').Enabled);
    CheckOf(Page, 'Minimap').Checked := True;
    Assert.IsTrue(Mirror.Checked, 'Spiegel folgt');
    Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := False;
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
  TAtlasSettingsPageTree.ForgetTreeState;
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
    TAtlasSettingsPageTree.ForgetTreeState;
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
  TAtlasSettingsPageTree.ForgetTreeState;
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
    Assert.IsTrue(Length(TopLevelNodes(Page)) < 15, 'Bereiche ohne experimentelle Einstellung fehlen');
    Assert.IsNotNull(TreeNodeOf(Page, Minimap), 'Minikarte ist experimentell');
    Page.Filter.Choice := 0;
    Page.Filter.OnChange(Page.Filter);
    // Bereiche von Base ohne Module (#1456), darunter „Prüfregeln“ (#909) und Versionsverwaltung (#1285).
    Assert.AreEqual(15, Integer(Length(TopLevelNodes(Page))));
    // Zurücksetzen auf dem Unterpunkt: nur die Minikarte.
    EditOf(Page, 'MinimapWidth').Text := '90';
    EditOf(Page, 'StickyScrollMaxLines').Text := '7';
    Page.Navigation.OnChange(Page.Navigation, TreeNodeOf(Page, Minimap));
    Page.ResetPage;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.AreEqual(TAtlasPluginSettings.Defaults.MinimapWidth, Saved.MinimapWidth, 'zurückgesetzt');
    Assert.AreEqual(7, Saved.StickyScrollMaxLines, 'anderer Unterpunkt bleibt');
    Assert.IsTrue(Saved.ExperimentalEnabled);
  finally
    Host.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
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
    Assert.Contains(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption, TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileNoProject));
    Assert.IsFalse(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Enabled, 'ohne Projekt');
    Page.Part<TAtlasSettingsTeamFilePart>.OnTeamFile :=
      function: TAtlasTeamSettings
      begin
        Result := Team; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
      end;
    Page.Part<TAtlasSettingsTeamFilePart>.OnOpenTeamFile :=
      procedure
      begin
        Inc(Opened);
      end;
    Assert.Contains(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileValue,
      ['naming.field', '"F"']));
    Assert.Contains(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileIssues, [1]),
      'Zugangsdaten ignoriert');
    Assert.Contains(Page.Part<TAtlasSettingsTeamFilePart>.TeamSnippetsLabel.Caption, 'Vorlagen');
    Assert.IsTrue(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Enabled);
    Page.Part<TAtlasSettingsTeamFilePart>.TeamFileOpenButton.Click;
    Assert.AreEqual(1, Opened);
    // Ausgeschaltet: keine Werte, kein Hinweis bei den Vorlagen, gespeichert als TeamFile = False.
    Page.Part<TAtlasSettingsTeamFilePart>.TeamFileCheck.Checked := False;
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTeamFileOff), Page.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption);
    Assert.AreEqual('', Page.Part<TAtlasSettingsTeamFilePart>.TeamSnippetsLabel.Caption);
    Page.SaveTo(Settings);
    Assert.IsFalse(Settings.TeamFile);
    // Fehlerhafte Datei: Hinweis statt Werte.
    Team := TAtlasTeamFile.Parse('{', 'C:\Repo\.atlas', 'C:\Repo');
    Team.Project := 'C:\Repo\Kasse.dproj';
    Page.Part<TAtlasSettingsTeamFilePart>.TeamFileCheck.Checked := True;
    // Mit Lage des Fehlers in der Datei (Zeile 1, Spalte 2 für "{").
    Assert.Contains(Page.Part<TAtlasSettingsTeamFilePart>.TeamFileInfo.Caption, TAtlasStrings.Fmt(TAtlasTextId.SettingsTeamFileInvalidAt, [1, 2]));
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
  ASettings.NestedRoutines := 'outer';
  ASettings.NestedRoutineBand := True;
  ASettings.NestedRoutineColorDark := '#123456';
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
  Assert.AreEqual('outer', ASaved.NestedRoutines, 'Färbung lokaler Routinen (#1788)');
  Assert.IsTrue(ASaved.NestedRoutineBand, 'Band lokaler Routinen (#1788)');
  Assert.AreEqual('#123456', ASaved.NestedRoutineColorDark, 'eigene Farbe lokaler Routinen (#1788)');
  Assert.AreEqual('', ASaved.NestedRoutineColorLight, 'Standardfarbe bleibt leer (#1788)');
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
      Assert.AreEqual(2, Integer(Page.Part<TAtlasSettingsRobustnessPart>.FuseList.Items.Count));
      Assert.AreEqual(TAtlasGuard.FeatureName(TAtlasFeature.Pairs), Page.Part<TAtlasSettingsRobustnessPart>.FuseList.Items[0]);
      Assert.AreEqual('Testquelle', Page.Part<TAtlasSettingsRobustnessPart>.FuseList.Items[1]);
      Assert.IsTrue(Page.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Enabled);
      // Nur die Quelle wieder einschalten.
      Page.Part<TAtlasSettingsRobustnessPart>.FuseList.Selected[1] := True;
      Page.Part<TAtlasSettingsRobustnessPart>.FuseEnableSelected.Click;
      Assert.IsFalse(TAtlasGuard.ProviderDisabled('Testquelle'));
      Assert.IsTrue(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Page.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Click;
      Assert.IsFalse(TAtlasGuard.Disabled(TAtlasFeature.Pairs));
      Assert.AreEqual(1, Integer(Page.Part<TAtlasSettingsRobustnessPart>.FuseList.Items.Count), 'nur der Hinweis „keine“');
      Assert.IsFalse(Page.Part<TAtlasSettingsRobustnessPart>.FuseEnableAll.Enabled);
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
  APage.Part<TAtlasSettingsIndexPart>.OnIndexMetrics :=
    procedure
    begin
      APage.Part<TAtlasSettingsIndexPart>.IndexAnswered('Units: 3');
    end;
end;
/// <summary>Antwort auf den Neuaufbau gibt die Befehle wieder frei.</summary>
procedure AnswerIndexRebuild(APage: TAtlasSettingsPage);
begin
  APage.Part<TAtlasSettingsIndexPart>.IndexAnswered('wird neu aufgebaut');
  Assert.IsFalse(APage.Part<TAtlasSettingsIndexPart>.IndexBusy);
  Assert.AreEqual('wird neu aufgebaut', APage.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
  Assert.IsTrue(APage.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled and APage.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled);
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
    Assert.IsFalse(Page.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled or Page.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled, 'ohne Server keine Befehle');
    AnswerIndexMetricsAtOnce(Page);
    // Antwort erst später, wie bei einem Server, der gerade indexiert.
    Page.Part<TAtlasSettingsIndexPart>.OnIndexRebuild :=
      procedure
      begin
        Inc(Rebuilds);
      end;
    Page.Part<TAtlasSettingsIndexPart>.OnIndexClear :=
      procedure
      begin
        Inc(Cleared);
        Page.Part<TAtlasSettingsIndexPart>.IndexAnswered('gelöscht');
      end;
    Page.Part<TAtlasSettingsIndexPart>.ConfirmClear :=
      function: Boolean
      begin
        Result := Confirm;
      end;
    Page.LoadFrom(Settings);
    Assert.AreEqual('Units: 3', Page.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
    Assert.IsTrue(Page.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled and Page.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled);
    Page.Part<TAtlasSettingsIndexPart>.IndexRebuild.Click;
    Assert.AreEqual(1, Rebuilds);
    Assert.IsTrue(Page.Part<TAtlasSettingsIndexPart>.IndexBusy);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsIndexAsking), Page.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
    Assert.IsFalse(Page.Part<TAtlasSettingsIndexPart>.IndexRebuild.Enabled or Page.Part<TAtlasSettingsIndexPart>.IndexClear.Enabled, 'gesperrt bis zur Antwort');
    Page.Part<TAtlasSettingsIndexPart>.IndexRebuild.Click;
    Assert.AreEqual(1, Rebuilds, 'kein zweiter Befehl, solange einer läuft');
    AnswerIndexRebuild(Page);
    Page.Part<TAtlasSettingsIndexPart>.IndexClear.Click;
    Assert.AreEqual(0, Cleared, 'abgelehnt: nichts löschen');
    Confirm := True;
    Page.Part<TAtlasSettingsIndexPart>.IndexClear.Click;
    Assert.AreEqual(1, Cleared);
    Assert.AreEqual('gelöscht', Page.Part<TAtlasSettingsIndexPart>.IndexInfo.Caption);
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
    Assert.IsFalse(CheckOf(Page, 'StatusField').Checked);
    Assert.IsFalse(CheckOf(Page, 'StatusFieldSummary').Checked);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsGeneralPart>.StatusToggles.Choice, 'nur Rechtsklick');
    Assert.AreEqual(2, Page.Part<TAtlasSettingsGeneralPart>.IndexProgress.Choice, 'Fortschritt aus');
    Assert.AreEqual('atlas.file', Page.Part<TAtlasSettingsGeneralPart>.StatusHidden.Text);
    Assert.IsFalse(Page.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked, 'Diagnosemodus standardmäßig aus');
    Assert.IsTrue(CheckOf(Page, 'SetupChecklist').Checked, 'Prüfliste beim Start standardmäßig an (#625)');
    Page.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked := True;
    CheckOf(Page, 'SetupChecklist').Checked := False;
    CheckOf(Page, 'StatusField').Checked := True;
    Page.Part<TAtlasSettingsGeneralPart>.StatusToggles.Choice := 2;
    Page.Part<TAtlasSettingsGeneralPart>.IndexProgress.Choice := 1;
    Page.Part<TAtlasSettingsGeneralPart>.StatusHidden.Text := ' atlas.file, atlas.index ';
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
    Assert.IsTrue(CheckOf(Page, 'ShortcutTips').Checked, 'Tipps standardmäßig an');
    Assert.AreEqual(1, Page.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice, 'Vorgabe all');
    CheckOf(Page, 'ShortcutTips').Checked := False;
    Page.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice := 0;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.ShortcutTips);
    Assert.AreEqual('atlas', Saved.ShortcutTipsScope);
    Page.LoadFrom(Saved);
    Assert.IsFalse(CheckOf(Page, 'ShortcutTips').Checked);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsGeneralPart>.ShortcutTipsScope.Choice);
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
    Assert.IsTrue(CheckOf(Page, 'Notifications').Checked, 'standardmäßig an');
    Assert.AreEqual('200', Page.Part<TAtlasSettingsNotificationsPart>.NotificationsMax.Text);
    Assert.AreEqual(ShortCutToText($E04E), EditOf(Page, 'NotificationsKey').Text, 'Strg+Umschalt+Alt+N');
    // Erste Quelle (build) ohne Angabe: einblenden.
    Assert.AreEqual(0, Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.Choice);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode.Choice);
    // Quelle server (vierte) zeigt „aus“.
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.Choice := 3;
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.OnChange(Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode.Choice);
    // Build-Server (sechste, #763) zeigt „nur sammeln“.
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.Choice := 5;
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.OnChange(Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode.Choice);
    // Tastenkürzel-Tipps (fünfte) auf „nur sammeln“.
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.Choice := 4;
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource.OnChange(Page.Part<TAtlasSettingsNotificationsPart>.NotificationSource);
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode.Choice := 1;
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode.OnChange(Page.Part<TAtlasSettingsNotificationsPart>.NotificationMode);
    CheckOf(Page, 'Notifications').Checked := False;
    Page.Part<TAtlasSettingsNotificationsPart>.NotificationsMax.Text := '50';
    EditOf(Page, 'NotificationsKey').Text := '';
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
    Assert.IsFalse(Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked);
    Assert.IsNotNull(Page.Filter);
    Assert.AreEqual(0, Page.Filter.Choice);
    // Ohne experimentelle Einstellung im Katalog kein Hinweis.
    Assert.AreEqual(Page.Marks.HasExperimental, Page.ExperimentalBanner.Visible);
    Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.ExperimentalEnabled);
    Page.LoadFrom(Saved);
    Assert.IsTrue(Page.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked);
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
    Assert.IsFalse(CheckOf(Page, 'SafeAskAfterCrash').Checked);
    Assert.IsTrue(CheckOf(Page, 'SafeAutoAfterRepeatedCrash').Checked);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsStartupPart>.SafeKey.Choice);
    Assert.AreEqual('20000', EditOf(Page, 'SafeStartupTimeoutMs').Text);
    Assert.AreEqual('5', EditOf(Page, 'SafeKeepSettingsHistory').Text);
    CheckOf(Page, 'SafeAutoAfterRepeatedCrash').Checked := False;
    Page.Part<TAtlasSettingsStartupPart>.SafeKey.Choice := 2;
    EditOf(Page, 'SafeKeepSettingsHistory').Text := '500';
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
/// <summary>Die Seite liest und löst Favoriten über AFavorites.</summary>
procedure WireFavorites(APage: TAtlasSettingsPage; AFavorites: TAtlasFavorites);
begin
  APage.Part<TAtlasSettingsFavoritesPart>.OnRemoveFavorites :=
    procedure(AKeys: TArray<string>)
    var
      Key: string;
    begin
      for Key in AKeys do
      begin
        AFavorites.Remove(Key);
      end;
    end;
  APage.Part<TAtlasSettingsFavoritesPart>.OnFavorites :=
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
    Assert.IsTrue(Page.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked);
    Page.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked := False;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsFalse(Saved.Favorites, 'abschaltbar');
    Assert.IsFalse(Page.Part<TAtlasSettingsFavoritesPart>.FavoritesRemove.Enabled, 'Liste gehört zum Schalter (#890)');
    Page.Part<TAtlasSettingsCompletionPart>.FavoritesCheck.Checked := True;
    Assert.AreEqual(3, Integer(Page.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items.Count));
    Assert.AreEqual('TDataSet.Open', Page.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items[0]);
    Page.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Selected[1] := True;
    Page.Part<TAtlasSettingsFavoritesPart>.FavoritesRemove.Click;
    Assert.AreEqual(2, Integer(Favorites.Count), 'Close gelöst');
    Assert.AreEqual('TDataSet.ParamByName', Page.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items[1]);
    Page.Part<TAtlasSettingsFavoritesPart>.FavoritesRemoveAll.Click;
    Assert.AreEqual(0, Integer(Favorites.Count));
    Assert.AreEqual(1, Integer(Page.Part<TAtlasSettingsFavoritesPart>.FavoritesList.Items.Count), 'nur der Hinweis „keine“');
    Assert.IsFalse(Page.Part<TAtlasSettingsFavoritesPart>.FavoritesRemoveAll.Enabled);
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
    Assert.IsTrue(CheckOf(Page, 'UndoMultiFile').Checked);
    Assert.AreEqual('7', EditOf(Page, 'UndoMultiFileDepth').Text);
    Assert.IsTrue(CheckOf(Page, 'UndoMultiFilePersist').Checked);
    Assert.AreEqual('50', EditOf(Page, 'UndoMultiFileMaxSizeMb').Text);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsStartupPart>.UndoOnConflict.Choice);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsStartupPart>.UndoNewFiles.Choice);
    Assert.IsTrue(EditOf(Page, 'UndoKey').Text <> '');
    Assert.IsTrue(EditOf(Page, 'RedoKey').Text <> '');
    CheckOf(Page, 'UndoMultiFile').Checked := False;
    CheckOf(Page, 'UndoMultiFilePersist').Checked := False;
    EditOf(Page, 'UndoMultiFileDepth').Text := '999';
    EditOf(Page, 'UndoMultiFileMaxSizeMb').Text := '0';
    Page.Part<TAtlasSettingsStartupPart>.UndoOnConflict.Choice := 0;
    Page.Part<TAtlasSettingsStartupPart>.UndoNewFiles.Choice := 1;
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
    Assert.IsFalse(CheckOf(Page, 'CommitCharacters').Checked);
    Assert.IsFalse(CheckOf(Page, 'AutoUses').Checked);
    Assert.IsFalse(CheckOf(Page, 'ParameterHints').Checked);
    Assert.IsFalse(CheckOf(Page, 'FormatPlaceholders').Checked);
    Assert.AreEqual('300', EditOf(Page, 'OpenDelayMs').Text);
    Assert.IsFalse(Page.Part<TAtlasSettingsCompletionPart>.AutoWidth.Checked);
    CheckOf(Page, 'CommitCharacters').Checked := True;
    CheckOf(Page, 'FormatPlaceholders').Checked := True;
    EditOf(Page, 'OpenDelayMs').Text := '0';
    Page.Part<TAtlasSettingsCompletionPart>.AutoWidth.Checked := True;
    Saved := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Saved);
    Assert.IsTrue(Saved.CommitCharacters);
    Assert.IsFalse(Saved.AutoUses);
    Assert.IsFalse(Saved.ParameterHints);
    Assert.IsTrue(Saved.FormatPlaceholders);
    Assert.AreEqual(0, Saved.OpenDelayMs);
    Assert.AreEqual(0, Saved.ListWidth, 'automatische Breite');
    // Version des Servers neben dem Pfad.
    Page.Part<TAtlasSettingsGeneralPart>.OnServerVersion :=
      function(APath: string): string
      begin
        Result := '1.2.3.4';
      end;
  finally
    Page.Free;
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
    Assert.IsFalse(Page.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'ohne Diagnosemodus verborgen');
    Page.Part<TAtlasSettingsGeneralPart>.DiagnosticMode.Checked := True;
    Assert.IsTrue(Page.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'sofort sichtbar, wenn der Diagnosemodus eingeschaltet wird');
    Page.LoadFrom(Settings);
    Assert.IsFalse(Page.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'nach dem Laden ohne Diagnosemodus wieder verborgen');
    Settings.DiagnosticMode := True;
    Page.LoadFrom(Settings);
    Assert.IsTrue(Page.Part<TAtlasSettingsRobustnessPart>.HangTestRow.Visible, 'mit Diagnosemodus geladen');
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
    Assert.IsTrue(CheckOf(Page, 'ProblemsWindowOpenFirst').Checked);
    Assert.AreEqual(0, Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Choice);
    Assert.IsTrue(CheckOf(Page, 'ProblemsWindowShowCleanActive').Checked);
    Assert.IsTrue(SheetOf(CheckOf(Page, 'ProblemsWindowOpenFirst')) = Page.NodeSheet('rules.window'));
    Assert.IsTrue(SheetOf(Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice) = Page.NodeSheet('rules.window'));
    Assert.IsTrue(Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled and CheckOf(Page, 'ProblemsWindowShowCleanActive').Enabled);
    CheckOf(Page, 'ProblemsWindowOpenFirst').Checked := False;
    Assert.IsFalse(Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(CheckOf(Page, 'ProblemsWindowShowCleanActive').Enabled, 'Schalter gesperrt');
    Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Choice := 2;
    CheckOf(Page, 'ProblemsWindowShowCleanActive').Checked := False;
    Settings := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Settings);
    Assert.IsFalse(Settings.ProblemsWindowOpenFirst);
    Assert.AreEqual('hidden', Settings.ProblemsWindowClosedUnits);
    Assert.IsFalse(Settings.ProblemsWindowShowCleanActive);
    CheckOf(Page, 'ProblemsWindowOpenFirst').Checked := True;
    Assert.IsTrue(Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowClosedUnitsChoice.Enabled, 'wieder frei');
  finally
    Page.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
/// <summary>Knoten des Bereichs Regeln: Prüffenster; „Profile und Baseline“ und die Regelgruppen kommen vom
/// Modul Prüfregeln (#1755).</summary>
procedure AssertRulesNodes(APage: TAtlasSettingsPage);
begin
  Assert.IsTrue(SheetOf(CheckOf(APage, 'ProblemsWindow')) = APage.NodeSheet('rules.window'));
  Assert.IsTrue(SheetOf(APage.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice) = APage.NodeSheet('rules.window'));
  Assert.IsTrue(SheetOf(APage.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit) = APage.NodeSheet('rules.window'));
  Assert.IsNull(APage.NodeSheet('rules.profiles'), 'Profile und Baseline im Abschnitt des Moduls');
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
  Assert.AreEqual('save', ASettings.ProblemsUpdate, 'Aktualisierung gespeichert');
  Assert.AreEqual(800, ASettings.ProblemsLiveDelayMs, 'Verzögerung gespeichert');
  Assert.IsFalse(ASettings.HoverProblemActions, 'Hover-Aktionen gespeichert');
end;
procedure TAtlasSettingsPageTests.RulesAreaWindowSettings;
var
  Host: TForm;
  Page: TAtlasSettingsPage;
  Settings: TAtlasPluginSettings;
begin
  TAtlasSettingsPageTree.ForgetTreeState;
  Host := TForm.CreateNew(nil);
  try
    Page := TAtlasSettingsPage.Create(Host);
    Page.Parent := Host;
    Page.HandleNeeded;
    // Knoten: Prüffenster und Compiler vorab; die Wege zu den Regeln, Baseline und Unterdrückungen bringt das
    // Modul Prüfregeln als Abschnitt mit (#1755, Atlas.UI.Rules.SettingsSection.Tests).
    AssertRulesNodes(Page);
    // Einstellungen des Prüffensters im Rundweg.
    Settings := TAtlasPluginSettings.Defaults;
    Settings.ProblemsWindowScope := 'project';
    Settings.ProblemsWindowGroupBy := 'rule';
    Settings.ProblemsUpdate := 'manual';
    Settings.ProblemsLiveDelayMs := 1200;
    Settings.HoverProblemActions := False;
    Page.LoadFrom(Settings);
    Assert.AreEqual(1, Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowScopeChoice.Choice);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowGroupByChoice.Choice);
    Assert.AreEqual(2, Page.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice.Choice, 'Aktualisierung geladen');
    Assert.AreEqual('1200', Page.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit.Text, 'Verzögerung geladen');
    Page.Part<TAtlasSettingsRulesPart>.ProblemsUpdateChoice.Choice := 1;
    Page.Part<TAtlasSettingsRulesPart>.ProblemsLiveDelayEdit.Text := '800';
    Assert.IsFalse(CheckOf(Page, 'HoverProblemActions').Checked, 'Hover-Aktionen geladen');
    Page.Part<TAtlasSettingsRulesPart>.ProblemsWindowScopeChoice.Choice := 0;
    CheckOf(Page, 'ProblemsWindowCompiler').Checked := True;
    // Gruppe „Compiler vorab“ (#1024): eigener Knoten mit den Plugin-Einstellungen der Gruppe.
    Assert.AreEqual(0, Page.Part<TAtlasSettingsRulesPart>.ProblemsCompilerMergeChoice.Choice);
    Assert.IsTrue(CheckOf(Page, 'ProblemsShowCompilerCode').Checked);
    Assert.IsTrue(SheetOf(CheckOf(Page, 'ProblemsShowCompilerCode')) = Page.NodeSheet('rules.group.compiler'));
    Page.Part<TAtlasSettingsRulesPart>.ProblemsCompilerMergeChoice.Choice := 1;
    CheckOf(Page, 'ProblemsShowCompilerCode').Checked := False;
    Settings := TAtlasPluginSettings.Defaults;
    Page.SaveTo(Settings);
    AssertRulesAreaSaved(Settings);
  finally
    Host.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTests);

end.
