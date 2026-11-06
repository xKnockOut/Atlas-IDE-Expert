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
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Continue, 'Weiterarbeiten', 'Zuletzt', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Projects, 'Projekte', 'Zustand', True),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.Tests, 'Testergebnisse', 'Letzter Lauf', False),
    TAtlasWelcomeCatalogEntry.Create(TAtlasWelcomeIds.State, 'Atlas', 'Zustandskachel', True)];
end;
/// <summary>Tafel mit Weiterarbeiten und Projekten links, Zustandskachel rechts.</summary>
function ArrangeBoard(AHost: TForm; const ASource: IAtlasWelcomeArrangeSource): TAtlasWelcomeBoardFrame;
begin
  RegisterViews([TAtlasWelcomeIds.Continue, TAtlasWelcomeIds.Projects, TAtlasWelcomeIds.State]);
  AHost.ClientWidth := 800;
  AHost.ClientHeight := 600;
  Result := TAtlasWelcomeBoardFrame.Create(AHost);
  Result.Parent := AHost;
  Result.Align := alClient;
  Result.Source := ASource;
  Result.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
    Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
    Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
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
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Außerhalb des Bearbeitungsmodus: nur der Stift, keine Griffe, keine Leiste „Ausgeblendet“.
    Assert.IsTrue(Board.Arranger.Bar.Visible);
    Assert.IsTrue(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Edit, '') >= 0);
    Assert.AreEqual(-1, Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '2'));
    Assert.AreEqual(-1, Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, ''), 'ein Layout: kein Umschalter');
    Assert.IsNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsFalse(Board.Arranger.HiddenBar.Visible);
    Assert.IsFalse(Board.Arranger.InsertLine.Visible);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.State).TitleBar.PopupMenu = Board.Menus.SectionMenu, 'Rechtsklick');
    // Bearbeitungsmodus.
    Source.EditingOn := True;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left),
      Section(TAtlasWelcomeIds.Projects, 30, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsTrue(Board.Editing);
    Assert.IsNotNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsNotNull(Board.ToolsOf(TAtlasWelcomeIds.State));
    Assert.IsTrue(Board.GripOf(TAtlasWelcomeIds.State).TabStop, 'Tab erreicht den Griff');
    Assert.IsTrue(Board.Arranger.Bar.Parts[Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '2')].Down);
    Assert.IsTrue(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Add, '') >= 0);
    Assert.IsTrue(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Reset, '') >= 0);
    Assert.IsTrue(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    Assert.IsTrue(Board.Arranger.HiddenBar.Visible);
    Assert.IsTrue(Board.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.Tests) >= 0);
    Assert.AreEqual(-1, Board.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.State));
    Assert.IsTrue(Board.Arranger.InsertLine.Visible);
    // welcomePage.customLayout aus: kein Bearbeitungsmodus, keine Leiste, festes Layout.
    Source.Can := False;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right),
      Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsFalse(Board.Editing);
    Assert.IsFalse(Board.Arranger.Bar.Visible);
    Assert.IsNull(Board.GripOf(TAtlasWelcomeIds.State));
    Assert.IsNull(Board.ToolsOf(TAtlasWelcomeIds.State));
    Assert.IsFalse(Board.Arranger.HiddenBar.Visible);
    // Ohne Quelle (Tests, ältere Aufrufer): kein Rechtsklick-Menü.
    Board.Source := nil;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Assert.IsNull(Board.View(TAtlasWelcomeIds.State).TitleBar.PopupMenu);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.CtrlArrowsMoveAndSave;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Grip: TAtlasWelcomeGrip;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Grip := Board.GripOf(TAtlasWelcomeIds.State);
    Assert.IsFalse(Grip.HandleKey(VK_LEFT, []), 'ohne Strg nichts');
    // Akzeptanz: nur mit Tastatur nach links oben.
    Assert.IsTrue(Grip.HandleKey(VK_LEFT, [ssCtrl]));
    Assert.AreEqual(TAtlasWelcomeIds.State, Board.Columns[0][0], 'sofort sichtbar');
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Left, Board.View(TAtlasWelcomeIds.State).Left);
    Assert.IsTrue(Board.View(TAtlasWelcomeIds.Continue).Top > Board.View(TAtlasWelcomeIds.State).Top);
    Assert.AreEqual(0, Integer(Length(Source.Calls)), 'gespeichert wird über die Warteschlange');
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    Assert.AreEqual(TAtlasWelcomeIds.State, Source.Arranged.Arrange([Section(TAtlasWelcomeIds.State, 10,
      TAtlasWelcomeColumn.Right), Section(TAtlasWelcomeIds.Continue, 20, TAtlasWelcomeColumn.Left)], 2)[0][0]);
    // Am Rand: verarbeitet (der Fokus wandert nicht), aber nichts gespeichert.
    Source.Calls := nil;
    Assert.IsTrue(Board.GripOf(TAtlasWelcomeIds.State).HandleKey(VK_UP, [ssCtrl]));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Source.Calls)));
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.ToolsChangeWidthAndHide;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Assert.IsFalse(Board.ToolsOf(TAtlasWelcomeIds.Projects).Wide);
    Board.ToolsOf(TAtlasWelcomeIds.Projects).Click(TAtlasWelcomeTool.Width);
    Assert.AreEqual(2, Board.Layout.WidthOf(TAtlasWelcomeIds.Projects));
    Assert.IsTrue(Board.ToolsOf(TAtlasWelcomeIds.Projects).Wide);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Continue).Width * 2 + TAtlasWelcomeBoardFrame.Gap,
      Board.View(TAtlasWelcomeIds.Projects).Width, 'über zwei Spalten');
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    // Akzeptanz: das Auge schaltet die Einstellung des Bereichs aus.
    Board.ToolsOf(TAtlasWelcomeIds.State).Click(TAtlasWelcomeTool.Eye);
    CheckSynchronize;
    Assert.AreEqual('hide ' + TAtlasWelcomeIds.State, Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.BarPartsReachSource;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Board.Arranger.Bar.ClickPart(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '1'));
    Assert.AreEqual(1, Board.Layout.Columns);
    Assert.AreEqual(1, Integer(Length(Board.Columns)));
    Assert.IsTrue(Board.Arranger.Bar.Parts[Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Column, '1')].Down);
    CheckSynchronize;
    Assert.AreEqual('arrange', Source.Last);
    Assert.AreEqual(1, Source.Arranged.Columns);
    Board.Arranger.Bar.ClickPart(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Reset, ''));
    CheckSynchronize;
    Assert.AreEqual('reset', Source.Last);
    Board.Arranger.Bar.ClickPart(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Edit, ''));
    CheckSynchronize;
    Assert.AreEqual('edit False', Source.Last, '„Fertig“');
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.AddMenuAndHiddenBarShowAtTarget;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Column: Integer;
  Before: string;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(True);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Akzeptanz: „Bereich hinzufügen“ listet alle Bereiche; sichtbare sind abgehakt.
    Board.Menus.BuildAddMenu;
    Assert.AreEqual(4, Integer(Board.Menus.BarMenu.Items.Count));
    Assert.IsTrue(Board.Menus.BarMenu.Items[0].Checked);
    Assert.IsFalse(Board.Menus.BarMenu.Items[0].Enabled);
    Assert.IsFalse(Board.Menus.BarMenu.Items[2].Checked);
    Assert.IsTrue(Board.Menus.BarMenu.Items[2].Enabled);
    Assert.AreEqual('Testergebnisse – Letzter Lauf', StripHotkey(Board.Menus.BarMenu.Items[2].Caption));
    // Der Ausgeblendete erscheint an der Einfügelinie.
    Board.Arranger.SetTarget(0, TAtlasWelcomeIds.Projects);
    Board.Arranger.Target(Column, Before);
    Assert.AreEqual(0, Column);
    Assert.AreEqual(Board.View(TAtlasWelcomeIds.Projects).Top - TAtlasWelcomeBoardFrame.Gap div 2 - 1,
      Board.Arranger.InsertLine.Top);
    Board.Menus.BarMenu.Items[2].Click;
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 0 atlas.projects', Source.Last);
    // Danach wieder die Vorgabe: Ende der Spalte mit dem meisten Platz (rechts steht nur die Kachel).
    Board.Arranger.Target(Column, Before);
    Assert.AreEqual(1, Column);
    Assert.AreEqual('', Before);
    Board.Arranger.HiddenBar.ClickPart(Board.Arranger.HiddenBar.IndexOf(TAtlasArrangePartKind.Hidden, TAtlasWelcomeIds.Tests));
    CheckSynchronize;
    Assert.AreEqual('show atlas.tests 1 ', Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.LayoutMenuSwitchesAndAsksNames;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
  Answer, Told: string;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Source.Names := ['Arbeit', 'Präsentation'];
    Source.Active := 'Arbeit';
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    // Akzeptanz: zwei Layouts lassen sich im Kopf umschalten, auch ohne Bearbeitungsmodus.
    Assert.IsTrue(Board.Arranger.Bar.IndexOf(TAtlasArrangePartKind.Layout, '') >= 0);
    Board.Menus.BuildLayoutMenu;
    Assert.AreEqual(6, Integer(Board.Menus.BarMenu.Items.Count), 'zwei Layouts, Strich, Neu, Umbenennen, Löschen');
    Assert.IsTrue(Board.Menus.BarMenu.Items[0].Checked);
    Assert.IsTrue(Board.Menus.BarMenu.Items[5].Enabled);
    Board.Menus.BarMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('switch Präsentation', Source.Last);
    // Neu: vergebener Name wird gemeldet, nichts angelegt.
    Board.Menus.OnAskName :=
      function(const APrompt: string; var AName: string): Boolean
      begin
        AName := Answer; // lsp-ignore: captured-loop-variable -- Absicht: liest den jeweils aktuellen Wert
        Result := True;
      end;
    Board.Menus.OnConfirm :=
      function(const AText: string; AQuestion: Boolean): Boolean
      begin
        Told := AText;
        Result := True;
      end;
    Source.Calls := nil;
    Answer := 'arbeit';
    Board.Menus.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Source.Calls)));
    Assert.IsTrue(Pos('arbeit', Told) > 0);
    Answer := ' Vortrag ';
    Board.Menus.BarMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('add Vortrag', Source.Last);
    Answer := 'Arbeit 2';
    Board.Menus.BarMenu.Items[4].Click;
    CheckSynchronize;
    Assert.AreEqual('rename Arbeit 2', Source.Last);
    Board.Menus.BarMenu.Items[5].Click;
    CheckSynchronize;
    Assert.AreEqual('delete', Source.Last);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;
procedure TAtlasWelcomeArrangeBoardTests.SectionMenuHidesAndOpensSettings;
var
  Host: TForm;
  Board: TAtlasWelcomeBoardFrame;
  Source: TFakeArrangeSource;
  Keep: IAtlasWelcomeArrangeSource;
begin
  Host := TForm.CreateNew(nil);
  try
    Source := ArrangeSource(False);
    Keep := Source;
    Board := ArrangeBoard(Host, Keep);
    Board.Menus.PrepareSectionMenu(TAtlasWelcomeIds.State);
    Assert.IsTrue(Board.Menus.SectionMenu.Items[0].Enabled);
    Assert.IsTrue(Board.Menus.SectionMenu.Items[3].Visible, '„Seite anpassen“');
    Board.Menus.SectionMenu.Items[0].Click;
    CheckSynchronize;
    Assert.AreEqual('hideAt ' + TAtlasWelcomeIds.State, Source.Last);
    Board.Menus.SectionMenu.Items[1].Click;
    CheckSynchronize;
    Assert.AreEqual('settings ' + TAtlasWelcomeIds.State, Source.Last);
    Board.Menus.SectionMenu.Items[3].Click;
    CheckSynchronize;
    Assert.AreEqual('edit True', Source.Last);
    // Fremder Bereich ohne Schalter: nichts auszublenden.
    Board.Menus.PrepareSectionMenu('plugin.fremd');
    Assert.IsFalse(Board.Menus.SectionMenu.Items[0].Enabled);
    // Ohne welcomePage.customLayout: „Ausblenden“ bleibt, „Seite anpassen“ fehlt.
    Source.Can := False;
    Board.Rebuild([Section(TAtlasWelcomeIds.State, 10, TAtlasWelcomeColumn.Right)], TAtlasWelcomeLayout.Atlas, 2);
    Board.Menus.PrepareSectionMenu(TAtlasWelcomeIds.State);
    Assert.IsTrue(Board.Menus.SectionMenu.Items[0].Enabled);
    Assert.IsFalse(Board.Menus.SectionMenu.Items[3].Visible);
  finally
    Host.Free;
    TAtlasWelcomeViews.Release;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeArrangeBoardTests);

end.
