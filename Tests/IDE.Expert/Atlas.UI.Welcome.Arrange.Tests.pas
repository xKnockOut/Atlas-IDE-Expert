unit Atlas.UI.Welcome.Arrange.Tests;

// Tests von „Seite anpassen“ der Willkommensseite.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Welcome')]
  TAtlasWelcomeArrangeBoardTests = class
  public
    /// <summary>Erste Benutzung (Menüs, Bearbeitungsleiste) ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure BarFollowsCustomLayoutAndEditing;
    [Test]
    procedure CtrlArrowsMoveAndSave;
    [Test]
    procedure ToolsChangeWidthAndHide;
    [Test]
    procedure BarPartsReachSource;
    [Test]
    procedure AddMenuAndHiddenBarShowAtTarget;
    [Test]
    procedure LayoutMenuSwitchesAndAsksNames;
    [Test]
    procedure SectionMenuHidesAndOpensSettings;
  end;

implementation

uses
  Vcl.Menus,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Vcl.Forms,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Board,
  Atlas.UI.Welcome.Arrange,
  System.Types,
  Atlas.UI.Welcome.TestSupport;

{ TAtlasWelcomeArrangeBoardTests }

type
  /// <summary>Quelle für „Seite anpassen“, die jeden Aufruf mitschreibt.</summary>
  TFakeArrangeSource = class(TInterfacedObject, IAtlasWelcomeArrangeSource)
  public
    Can: Boolean;
    EditingOn: Boolean;
    Names: TArray<string>;
    Active: string;
    Entries: TArray<TAtlasWelcomeCatalogEntry>;
    Calls: TArray<string>;
    Arranged: TAtlasWelcomeLayout;
    function CanCustomize: Boolean;
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    procedure HideSection(const AId: string);
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    function DeleteLayout: Boolean;
    procedure ResetLayout;
    function Last: string;
  end;

function TFakeArrangeSource.CanCustomize: Boolean;
begin
  Result := Can;
end;
function TFakeArrangeSource.Editing: Boolean;
begin
  Result := EditingOn;
end;
procedure TFakeArrangeSource.SetEditing(AOn: Boolean);
begin
  Calls := Calls + ['edit ' + BoolToStr(AOn, True)];
end;
function TFakeArrangeSource.LayoutNames: TArray<string>;
begin
  Result := Names;
end;
function TFakeArrangeSource.ActiveLayout: string;
begin
  Result := Active;
end;
function TFakeArrangeSource.Catalog: TArray<TAtlasWelcomeCatalogEntry>;
begin
  Result := Entries;
end;
procedure TFakeArrangeSource.Arrange(const ALayout: TAtlasWelcomeLayout);
begin
  Arranged := ALayout;
  Calls := Calls + ['arrange'];
end;
procedure TFakeArrangeSource.ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
begin
  Calls := Calls + [Format('show %s %d %s', [AId, AColumn, ABefore])];
end;
procedure TFakeArrangeSource.HideSection(const AId: string);
begin
  Calls := Calls + ['hide ' + AId];
end;
procedure TFakeArrangeSource.HideSectionAt(const AId: string; const APoint: TPoint);
begin
  Calls := Calls + ['hideAt ' + AId];
end;
procedure TFakeArrangeSource.ShowSectionSettings(const AId: string);
begin
  Calls := Calls + ['settings ' + AId];
end;
procedure TFakeArrangeSource.SwitchLayout(const AName: string);
begin
  Calls := Calls + ['switch ' + AName];
end;
function TFakeArrangeSource.AddLayout(const AName: string): Boolean;
begin
  Calls := Calls + ['add ' + AName];
  Result := True;
end;
function TFakeArrangeSource.RenameLayout(const AName: string): Boolean;
begin
  Calls := Calls + ['rename ' + AName];
  Result := True;
end;
function TFakeArrangeSource.DeleteLayout: Boolean;
begin
  Calls := Calls + ['delete'];
  Result := True;
end;
procedure TFakeArrangeSource.ResetLayout;
begin
  Calls := Calls + ['reset'];
end;
function TFakeArrangeSource.Last: string;
begin
  Result := '';
  if Length(Calls) > 0 then
  begin
    Result := Calls[High(Calls)];
  end;
end;
function ArrangeSource(AEditing: Boolean): TFakeArrangeSource;
begin
  Result := TFakeArrangeSource.Create;
  Result.Can := True;
  Result.EditingOn := AEditing;
  Result.Names := ['Standard'];
  Result.Active := 'Standard';
  Result.Entries := [
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.cContinue, 'Weiterarbeiten', 'Zuletzt', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.cProjects, 'Projekte', 'Zustand', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.cTests, 'Testergebnisse', 'Letzter Lauf', False),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.cState, 'Atlas', 'Zustandskachel', True)];
end;
/// <summary>Tafel mit Weiterarbeiten und Projekten links, Zustandskachel rechts.</summary>
function ArrangeBoard(AHost: TForm; const ASource: IAtlasWelcomeArrangeSource): TAtlasWelcomeBoardFrame;
begin
  RegisterViews([TAtlasWelcomeIds.cContinue, TAtlasWelcomeIds.cProjects, TAtlasWelcomeIds.cState]);
  AHost.ClientWidth := 800;
  AHost.ClientHeight := 600;
  Result := TAtlasWelcomeBoardFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.Source := ASource;
  Result.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.cProjects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
end;
procedure TAtlasWelcomeArrangeBoardTests.WarmUpFirstUse;
begin
  try
    BarFollowsCustomLayoutAndEditing;
  except
    on Exception do
      ;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.BarFollowsCustomLayoutAndEditing;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(False);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    // Außerhalb des Bearbeitungsmodus: nur der Stift, keine Griffe, keine Leiste „Ausgeblendet“.
    Assert.IsTrue(mBoard.Arranger.Bar.Visible);
    Assert.IsTrue(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Edit, '') >= 0);
    Assert.AreEqual(-1, mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '2'));
    Assert.AreEqual(-1, mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, ''), 'ein Layout: kein Umschalter');
    Assert.IsNull(mBoard.GripOf(TAtlasWelcomeIds.cState));
    Assert.IsFalse(mBoard.Arranger.HiddenBar.Visible);
    Assert.IsFalse(mBoard.Arranger.InsertLine.Visible);
    Assert.IsTrue(mBoard.View(TAtlasWelcomeIds.cState).TitleBar.PopupMenu = mBoard.Menus.SectionMenu, 'Rechtsklick');
    // Bearbeitungsmodus.
    mSource.EditingOn := True;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.cProjects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsTrue(mBoard.Editing);
    Assert.IsNotNull(mBoard.GripOf(TAtlasWelcomeIds.cState));
    Assert.IsNotNull(mBoard.ToolsOf(TAtlasWelcomeIds.cState));
    Assert.IsTrue(mBoard.GripOf(TAtlasWelcomeIds.cState).TabStop, 'Tab erreicht den Griff');
    Assert.IsTrue(mBoard.Arranger.Bar.Parts[mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '2')].Down);
    Assert.IsTrue(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Add, '') >= 0);
    Assert.IsTrue(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Reset, '') >= 0);
    Assert.IsTrue(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    Assert.IsTrue(mBoard.Arranger.HiddenBar.Visible);
    Assert.IsTrue(mBoard.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.cTests) >= 0);
    Assert.AreEqual(-1, mBoard.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.cState));
    Assert.IsTrue(mBoard.Arranger.InsertLine.Visible);
    // welcomePage.customLayout aus: kein Bearbeitungsmodus, keine Leiste, festes Layout.
    mSource.Can := False;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsFalse(mBoard.Editing);
    Assert.IsFalse(mBoard.Arranger.Bar.Visible);
    Assert.IsNull(mBoard.GripOf(TAtlasWelcomeIds.cState));
    Assert.IsNull(mBoard.ToolsOf(TAtlasWelcomeIds.cState));
    Assert.IsFalse(mBoard.Arranger.HiddenBar.Visible);
    // Ohne Quelle (Tests, ältere Aufrufer): kein Rechtsklick-Menü.
    mBoard.Source := nil;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsNull(mBoard.View(TAtlasWelcomeIds.cState).TitleBar.PopupMenu);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.CtrlArrowsMoveAndSave;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
  mGrip: TAtlasWelcomeGrip;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(True);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    mGrip := mBoard.GripOf(TAtlasWelcomeIds.cState);
    Assert.IsFalse(mGrip.HandleKey(VK_LEFT, []), 'ohne Strg nichts');
    // Akzeptanz: nur mit Tastatur nach links oben.
    Assert.IsTrue(mGrip.HandleKey(VK_LEFT, [ssCtrl]));
    Assert.AreEqual(TAtlasWelcomeIds.cState, mBoard.Columns[0][0], 'sofort sichtbar');
    Assert.AreEqual(mBoard.View(TAtlasWelcomeIds.cContinue).Left, mBoard.View(TAtlasWelcomeIds.cState).Left);
    Assert.IsTrue(mBoard.View(TAtlasWelcomeIds.cContinue).Top > mBoard.View(TAtlasWelcomeIds.cState).Top);
    Assert.AreEqual(0, Integer(Length(mSource.Calls)), 'gespeichert wird über die Warteschlange');
    CheckSynchronize;
    Assert.AreEqual('arrange', mSource.Last);
    Assert.AreEqual(TAtlasWelcomeIds.cState, mSource.Arranged.Arrange([Section(TAtlasWelcomeIds.cState, 10,
      TAtlasWelcomeColumn.Right), Section(TAtlasWelcomeIds.cContinue, 20, TAtlasWelcomeColumn.Left)], 2)[0][0]);
    // Am Rand: verarbeitet (der Fokus wandert nicht), aber nichts gespeichert.
    mSource.Calls := nil;
    Assert.IsTrue(mBoard.GripOf(TAtlasWelcomeIds.cState).HandleKey(VK_UP, [ssCtrl]));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mSource.Calls)));
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.ToolsChangeWidthAndHide;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(True);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    Assert.IsFalse(mBoard.ToolsOf(TAtlasWelcomeIds.cProjects).Wide);
    mBoard.ToolsOf(TAtlasWelcomeIds.cProjects).Click(TAtlasWelcomeTool.Width);
    Assert.AreEqual(2, mBoard.Layout.WidthOf(TAtlasWelcomeIds.cProjects));
    Assert.IsTrue(mBoard.ToolsOf(TAtlasWelcomeIds.cProjects).Wide);
    Assert.AreEqual(mBoard.View(TAtlasWelcomeIds.cContinue).Width * 2 + TAtlasWelcomeBoardFrame.cGap,
      mBoard.View(TAtlasWelcomeIds.cProjects).Width, 'über zwei Spalten');
    CheckSynchronize;
    Assert.AreEqual('arrange', mSource.Last);
    // Akzeptanz: das Auge schaltet die Einstellung des Bereichs aus.
    mBoard.ToolsOf(TAtlasWelcomeIds.cState).Click(TAtlasWelcomeTool.Eye);
    CheckSynchronize;
    Assert.AreEqual('hide ' + TAtlasWelcomeIds.cState, mSource.Last);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.BarPartsReachSource;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(True);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    mBoard.Arranger.Bar.ClickPart(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '1'));
    Assert.AreEqual(1, mBoard.Layout.Columns);
    Assert.AreEqual(1, Integer(Length(mBoard.Columns)));
    Assert.IsTrue(mBoard.Arranger.Bar.Parts[mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '1')].Down);
    CheckSynchronize;
    Assert.AreEqual('arrange', mSource.Last);
    Assert.AreEqual(1, mSource.Arranged.Columns);
    mBoard.Arranger.Bar.ClickPart(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Reset, ''));
    CheckSynchronize;
    Assert.AreEqual('reset', mSource.Last);
    mBoard.Arranger.Bar.ClickPart(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Edit, ''));
    CheckSynchronize;
    Assert.AreEqual('edit False', mSource.Last, '„Fertig“');
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.AddMenuAndHiddenBarShowAtTarget;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
  mColumn: Integer;
  mBefore: string;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(True);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    // Akzeptanz: „Bereich hinzufügen“ listet alle Bereiche; sichtbare sind abgehakt.
    mBoard.Menus.BuildAddMenu;
    Assert.AreEqual(4, Integer(mBoard.Menus.BarMenu.Items.Count));
    Assert.IsTrue(mBoard.Menus.BarMenu.Items[0].Checked);
    Assert.IsFalse(mBoard.Menus.BarMenu.Items[0].Enabled);
    Assert.IsFalse(mBoard.Menus.BarMenu.Items[2].Checked);
    Assert.IsTrue(mBoard.Menus.BarMenu.Items[2].Enabled);
    Assert.AreEqual('Testergebnisse – Letzter Lauf', StripHotkey(mBoard.Menus.BarMenu.Items[2].Caption));
    // Der Ausgeblendete erscheint an der Einfügelinie.
    mBoard.Arranger.SetTarget(0, TAtlasWelcomeIds.cProjects);
    mBoard.Arranger.Target(mColumn, mBefore);
    Assert.AreEqual(0, mColumn);
    Assert.AreEqual(mBoard.View(TAtlasWelcomeIds.cProjects).Top - TAtlasWelcomeBoardFrame.cGap div 2 - 1,
      mBoard.Arranger.InsertLine.Top);
    mBoard.Menus.BarMenu.Items[2].Click;
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 0 atlas.projects', mSource.Last);
    // Danach wieder die Vorgabe: Ende der Spalte mit dem meisten Platz (rechts steht nur die Kachel).
    mBoard.Arranger.Target(mColumn, mBefore);
    Assert.AreEqual(1, mColumn);
    Assert.AreEqual('', mBefore);
    mBoard.Arranger.HiddenBar.ClickPart(mBoard.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden,
      TAtlasWelcomeIds.cTests));
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 1 ', mSource.Last);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.LayoutMenuSwitchesAndAsksNames;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
  mAnswer, mTold: string;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(False);
    mSource.Names := ['Arbeit', 'Präsentation'];
    mSource.Active := 'Arbeit';
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    // Akzeptanz: zwei Layouts lassen sich im Kopf umschalten, auch ohne Bearbeitungsmodus.
    Assert.IsTrue(mBoard.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    mBoard.Menus.BuildLayoutMenu;
    Assert.AreEqual(6, Integer(mBoard.Menus.BarMenu.Items.Count), 'zwei Layouts, Strich, Neu, Umbenennen, Löschen');
    Assert.IsTrue(mBoard.Menus.BarMenu.Items[0].Checked);
    Assert.IsTrue(mBoard.Menus.BarMenu.Items[5].Enabled);
    mBoard.Menus.BarMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('switch Präsentation', mSource.Last);
    // Neu: vergebener Name wird gemeldet, nichts angelegt.
    mBoard.Menus.OnAskName :=
      function(const APrompt: string; var AName: string): Boolean
      begin
        AName := mAnswer; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
        Result := True;
      end;
    mBoard.Menus.OnConfirm :=
      function(const AText: string; AQuestion: Boolean): Boolean
      begin
        mTold := AText;
        Result := True;
      end;
    mSource.Calls := nil;
    mAnswer := 'arbeit';
    mBoard.Menus.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mSource.Calls)));
    Assert.IsTrue(Pos('arbeit', mTold) > 0);
    mAnswer := ' Vortrag ';
    mBoard.Menus.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('add Vortrag', mSource.Last);
    mAnswer := 'Arbeit 2';
    mBoard.Menus.BarMenu.Items[4].Click;
    CheckSynchronize;
    Assert.AreEqual('rename Arbeit 2', mSource.Last);
    mBoard.Menus.BarMenu.Items[5].Click;
    CheckSynchronize;
    Assert.AreEqual('delete', mSource.Last);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.SectionMenuHidesAndOpensSettings;
var
  mHost: TForm;
  mBoard: TAtlasWelcomeBoardFrame;
  mSource: TFakeArrangeSource;
  mKeep: IAtlasWelcomeArrangeSource;
begin
  mHost := TForm.CreateNew(nil);
  try
    mSource := ArrangeSource(False);
    mKeep := mSource;
    mBoard := ArrangeBoard(mHost, mKeep);
    mBoard.Menus.PrepareSectionMenu(TAtlasWelcomeIds.cState);
    Assert.IsTrue(mBoard.Menus.SectionMenu.Items[0].Enabled);
    Assert.IsTrue(mBoard.Menus.SectionMenu.Items[3].Visible, '„Seite anpassen“');
    mBoard.Menus.SectionMenu.Items[0].Click;
    CheckSynchronize;
    Assert.AreEqual('hideAt ' + TAtlasWelcomeIds.cState, mSource.Last);
    mBoard.Menus.SectionMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('settings ' + TAtlasWelcomeIds.cState, mSource.Last);
    mBoard.Menus.SectionMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('edit True', mSource.Last);
    // Fremder Bereich ohne Schalter: nichts auszublenden.
    mBoard.Menus.PrepareSectionMenu('plugin.fremd');
    Assert.IsFalse(mBoard.Menus.SectionMenu.Items[0].Enabled);
    // Ohne welcomePage.customLayout: „Ausblenden“ bleibt, „Seite anpassen“ fehlt.
    mSource.Can := False;
    mBoard.Rebuild([Section(TAtlasWelcomeIds.cState, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    mBoard.Menus.PrepareSectionMenu(TAtlasWelcomeIds.cState);
    Assert.IsTrue(mBoard.Menus.SectionMenu.Items[0].Enabled);
    Assert.IsFalse(mBoard.Menus.SectionMenu.Items[3].Visible);
  finally
    mHost.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeArrangeBoardTests);

end.
