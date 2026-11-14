unit Atlas.UI.Settings.Page.Tree.Tests;

// Tests für den Baum der Optionsseite (#890): Bereiche, Knoten, Hauptschalter und ihre Sperren.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSettingsPageTreeTests = class
  public
    /// <summary>Erstes Erzeugen von Steuerelementen legt einmalige VCL-Daten an (Themes, Schriften).</summary>
    [SetupFixture]
    procedure WarmUp;
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
  end;

implementation

uses
  Atlas.UI.Settings.Page.Tree,
  System.SysUtils,
  System.Classes,
  System.UITypes,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Settings.Page,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.Forms,
  Vcl.ComCtrls,
  Vcl.StdCtrls,
  Atlas.UI.Settings.Marks,
  Atlas.UI.Settings.Group,
  Atlas.UI.Strings,
  Atlas.UI.Settings.Strings,
  Atlas.UI.Settings.Page.TestSupport,
  Atlas.UI.Settings.Page.EditorView,
  Atlas.UI.Settings.Page.General;

procedure TAtlasSettingsPageTreeTests.WarmUp;
begin
  WarmUpSettingsPage;
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
  // Versionsverwaltung bringt das Modul als Abschnitt mit (#1905).
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabTeamFile), AAreas[13].Text);
  Assert.IsTrue(APage.Pages.PageCount > 13, 'Unterpunkte haben eigene Seiten');
  for mIndex := 0 to APage.Pages.PageCount - 1 do
  begin
    Assert.IsTrue(APage.Pages.Pages[mIndex].ControlCount > 0, APage.Pages.Pages[mIndex].Caption);
    Assert.IsFalse(APage.Pages.Pages[mIndex].TabVisible, APage.Pages.Pages[mIndex].Caption);
  end;
end;
procedure TAtlasSettingsPageTreeTests.TreeShowsAreasAndNodes;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mAreas: TArray<TTreeNode>;
  mNode: TTreeNode;
  mMinimap: TTabSheet;
begin
  // #890: Bereiche oben im Baum, Funktionen als Unterpunkte; jeder Knoten zeigt nur seine Seite.
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mAreas := TopLevelNodes(mPage);
    Assert.AreEqual(14, Integer(Length(mAreas)));
    AssertTreeAreas(mPage, mAreas);
    Assert.AreSame(mPage.Pages.Pages[0], mPage.Pages.ActivePage, 'erstes Öffnen: Allgemein');
    // Unterpunkt „Minikarte“ unter „Editor“ mit ihren Einstellungen und nichts sonst.
    mMinimap := mPage.NodeSheet('editor.minimap');
    Assert.IsNotNull(mMinimap);
    Assert.AreEqual('editor.minimap', mPage.NodeOfSheet(mMinimap));
    Assert.AreSame(mMinimap, SheetOf(EditOf(mPage, 'MinimapWidth')));
    Assert.AreNotSame(mMinimap, SheetOf(CheckOf(mPage, 'StickyScroll')));
    mNode := TreeNodeOf(mPage, mMinimap);
    Assert.IsNotNull(mNode, 'Knoten im Baum');
    Assert.AreEqual(1, mNode.Level);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.SettingsTabEditor), mNode.Parent.Text);
    mPage.Navigation.OnChange(mPage.Navigation, mAreas[11]);
    Assert.AreEqual('', mPage.NodeOfSheet(mPage.Pages.ActivePage), 'Hauptknoten zeigt den Bereich');
    mPage.Navigation.OnChange(mPage.Navigation, mNode);
    Assert.AreSame(mMinimap, mPage.Pages.ActivePage, 'Klick im Baum schaltet die Seite');
  finally
    mHost.Free;
  end;
  // Beim nächsten Öffnen dieselbe Seite, ihr Bereich aufgeklappt.
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    Assert.AreSame(mPage.NodeSheet('editor.minimap'), mPage.Pages.ActivePage, 'Auswahl gemerkt');
    Assert.IsNotNull(mPage.Navigation.Selected);
    Assert.IsTrue(mPage.Navigation.Selected.Parent.Expanded, 'Bereich aufgeklappt');
  finally
    mHost.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;
procedure TAtlasSettingsPageTreeTests.EveryBindingOnOneNode;
var
  mPage: TAtlasSettingsPage;
  mIndex: Integer;
  mBinding: TAtlasSettingsBinding;
  mName, mKnown: string;
  mSheet: TTabSheet;
  mFrame: TAtlasSettingsGroup;
  mAncestors: TArray<string>;
begin
  // #890 Wächter: Jede Einstellung steht auf genau dem Knoten aus dem Schema und höchstens in einem Rahmen,
  // dem ihres Hauptschalters (oder eines seiner Vorfahren).
  mPage := TAtlasSettingsPage.Create(nil);
  try
    for mIndex := 0 to mPage.Marks.Count - 1 do
    begin
      mBinding := mPage.Marks.Bindings[mIndex];
      mKnown := '';
      for mName in mBinding.Names do
      begin
        if (mKnown = '') and mPage.Groups.Contains(mName) then
        begin
          mKnown := mName;
        end;
      end;
      if mKnown = '' then
      begin
        Continue;
      end;
      mSheet := SheetOf(mBinding.Control);
      Assert.IsNotNull(mSheet, mKnown);
      Assert.AreEqual(mPage.Groups.NodeOf(mKnown), mPage.NodeOfSheet(mSheet), mKnown);
      mFrame := FrameAround(mBinding.Control);
      // Ohne Rahmen (Einstellung ohne Hauptschalter, z. B. debug.hoverValues) ist nichts weiter zu prüfen.
      if (mFrame <> nil) and Inside(mBinding.Control, mFrame.Master) then
      begin
        mFrame := FrameAround(mFrame);
      end;
      if mFrame = nil then
      begin
        Continue;
      end;
      mAncestors := mPage.Groups.AncestorsOf(mKnown);
      Assert.AreNotEqual('', mFrame.MasterName, mKnown);
      Assert.IsTrue(MatchText(mFrame.MasterName, mAncestors), mKnown + ' in ' + mFrame.MasterName);
    end;
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTreeTests.MasterLocksItsGroup;
var
  mPage: TAtlasSettingsPage;
  mSettings, mSaved: TAtlasPluginSettings;
  mFrame: TAtlasSettingsGroup;
begin
  // #890: Hauptschalter aus ⇒ jede Unteroption gesperrt; die Werte bleiben und werden gespeichert.
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.ExperimentalEnabled := True;
    mSettings.Minimap := True;
    mSettings.MinimapWidth := 90;
    mPage.LoadFrom(mSettings);
    mFrame := mPage.FrameOf('Minimap');
    Assert.IsNotNull(mFrame, 'Minikarte hat einen Rahmen');
    Assert.AreSame(CheckOf(mPage, 'Minimap'), mFrame.Master, 'Hauptschalter oben im Rahmen');
    Assert.IsTrue(mPage.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled and EditOf(mPage, 'MinimapWidth').Enabled);
    Assert.IsFalse(mPage.SheetGray(mPage.NodeSheet('editor.minimap')));
    CheckOf(mPage, 'Minimap').Checked := False;
    Assert.IsTrue(CheckOf(mPage, 'Minimap').Enabled, 'der Hauptschalter bleibt bedienbar');
    Assert.IsFalse(mPage.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled, 'Auswahl gesperrt');
    Assert.IsFalse(EditOf(mPage, 'MinimapWidth').Enabled, 'Textfeld gesperrt');
    Assert.IsFalse(mFrame.Reason.Visible, 'kein Grund: Der Schalter steht im Rahmen');
    Assert.IsTrue(mPage.SheetGray(mPage.NodeSheet('editor.minimap')), 'Knoten grau');
    mSaved := TAtlasPluginSettings.Defaults;
    mPage.SaveTo(mSaved);
    Assert.AreEqual(90, mSaved.MinimapWidth, 'Wert bleibt erhalten');
    CheckOf(mPage, 'Minimap').Checked := True;
    Assert.IsTrue(mPage.Part<TAtlasSettingsEditorViewPart>.MinimapRender.Enabled and EditOf(mPage, 'MinimapWidth').Enabled, 'wieder frei');
    // Experimentelle Funktionen aus: auch der Hauptschalter gesperrt, mit Grund im Rahmen.
    mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := False;
    Assert.IsFalse(CheckOf(mPage, 'Minimap').Enabled);
    Assert.IsFalse(EditOf(mPage, 'MinimapWidth').Enabled);
    Assert.IsTrue(mFrame.Reason.Visible);
    Assert.AreEqual(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsLockedExperimental), mFrame.Reason.Caption);
    Assert.IsTrue(CheckOf(mPage, 'Minimap').Checked, 'Wert bleibt');
    mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := True;
    Assert.IsTrue(CheckOf(mPage, 'Minimap').Enabled);
    Assert.IsFalse(mFrame.Reason.Visible);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTreeTests.MasterOnOtherPageLocks;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mFrame: TAtlasSettingsGroup;
  mMaster: TCheckBox;
begin
  // #890: Abhängigkeit über Seiten hinweg: Atlas-Code-Insight (Allgemein) aus sperrt den mitlaufenden Kopf.
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.ExperimentalEnabled := True;
    mSettings.StickyScroll := True;
    mPage.LoadFrom(mSettings);
    mFrame := mPage.FrameOf('StickyScroll');
    Assert.IsNotNull(mFrame);
    Assert.IsTrue(CheckOf(mPage, 'StickyScroll').Enabled and EditOf(mPage, 'StickyScrollMaxLines').Enabled);
    mMaster := mPage.FrameOf('Enabled').Master as TCheckBox;
    mMaster.Checked := False;
    Assert.IsFalse(CheckOf(mPage, 'StickyScroll').Enabled, 'Hauptschalter gesperrt');
    Assert.IsFalse(EditOf(mPage, 'StickyScrollMaxLines').Enabled, 'Unteroption gesperrt');
    Assert.IsTrue(mFrame.Reason.Visible, 'Grund im Rahmen');
    Assert.IsTrue(Pos(TAtlasSettingsStrings.Text(TAtlasSettingsTextId.SettingsEnabled).Replace('&', ''),
      mFrame.Reason.Caption) > 0,
      mFrame.Reason.Caption);
    Assert.IsFalse(mPage.ControlOf('PairGuides').Enabled, 'auch Klammerfarben');
    mMaster.Checked := True;
    Assert.IsTrue(CheckOf(mPage, 'StickyScroll').Enabled and EditOf(mPage, 'StickyScrollMaxLines').Enabled);
    Assert.IsFalse(mFrame.Reason.Visible);
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTreeTests.OverviewMirrorsMasters;
var
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mMirror: TCheckBox;
begin
  // #890: Der Hauptknoten „Editor“ zeigt je Funktion ihren Hauptschalter; beide folgen einander.
  mPage := TAtlasSettingsPage.Create(nil);
  try
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.ExperimentalEnabled := True;
    mSettings.Minimap := True;
    mPage.LoadFrom(mSettings);
    mMirror := mPage.OverviewMirror('Minimap');
    Assert.IsNotNull(mMirror);
    Assert.AreEqual('', mPage.NodeOfSheet(SheetOf(mMirror)), 'auf dem Hauptknoten');
    Assert.IsNotNull(SheetOf(mMirror));
    Assert.IsTrue(mMirror.Checked);
    mMirror.Checked := False;
    Assert.IsFalse(CheckOf(mPage, 'Minimap').Checked, 'Spiegel schaltet');
    Assert.IsFalse(EditOf(mPage, 'MinimapWidth').Enabled);
    CheckOf(mPage, 'Minimap').Checked := True;
    Assert.IsTrue(mMirror.Checked, 'Spiegel folgt');
    mPage.Part<TAtlasSettingsGeneralPart>.ExperimentalEnabled.Checked := False;
    Assert.IsFalse(mMirror.Enabled, 'gesperrt wie das Original');
  finally
    mPage.Free;
  end;
end;
procedure TAtlasSettingsPageTreeTests.RevealLockedShowsMaster;
var
  mHost: TForm;
  mPage: TAtlasSettingsPage;
  mSettings: TAtlasPluginSettings;
  mMaster: TCheckBox;
begin
  // #890: Eine gesperrte Einstellung zeigen: Ihr Hauptschalter ist hervorgehoben.
  TAtlasSettingsPageTree.ForgetTreeState;
  mHost := TForm.CreateNew(nil);
  try
    mPage := TAtlasSettingsPage.Create(mHost);
    mPage.Parent := mHost;
    mPage.HandleNeeded;
    mSettings := TAtlasPluginSettings.Defaults;
    mSettings.PairColors := False;
    mPage.LoadFrom(mSettings);
    mMaster := mPage.ControlOf('PairColors') as TCheckBox;
    Assert.IsTrue(mPage.Reveal('PairGuides'));
    Assert.IsTrue(fsBold in mMaster.Font.Style, 'Hauptschalter hervorgehoben');
    Assert.AreSame(SheetOf(mMaster), mPage.Pages.ActivePage, 'dessen Seite gewählt');
    Assert.IsNotNull(mPage.Navigation.Selected);
  finally
    mHost.Free;
    TAtlasSettingsPageTree.ForgetTreeState;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSettingsPageTreeTests);

end.
