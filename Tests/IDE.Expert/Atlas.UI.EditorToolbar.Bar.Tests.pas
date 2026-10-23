unit Atlas.UI.EditorToolbar.Bar.Tests;

// Atlas-Editorleiste (#1101), Darstellung: feste Höhe, Knöpfe von links,
// Rücksprung hinter den angehefteten Abschnittssymbolen, Überlauf » mit den
// hinteren Knöpfen, Zahnrad rechts, gesperrte Knöpfe melden keinen Befehl,
// Tooltips; Inline in der Brotkrumenzeile lässt den Gliedern den Platz links.
// Klick mit der Maus über die Fensternachrichten: Ein Mausverlassen zwischen
// Drücken und Loslassen (in der IDE bei jedem Klick) bricht nicht ab.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.EditorToolbar.Bar;

type
  [TestFixture]
  TAtlasEditorToolbarTests = class
  private
    FForm: TForm;
    FBar: TAtlasEditorToolbar;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsHeightAndOrder;
    [Test]
    procedure ReturnFollowsPinnedSections;
    [Test]
    procedure NarrowBarOverflows;
    [Test]
    procedure ClicksAndDisabledButtons;
    [Test]
    procedure MouseClickSurvivesMouseLeave;
    /// <summary>Sperrt jemand die Leiste, meldet OnDisabled das, solange sie noch bedienbar ist (der Aufrufer steht
    /// dann noch auf dem Stapel); danach ist sie gesperrt.</summary>
    [Test]
    procedure ReportsDisablingBeforeItHappens;
    [Test]
    procedure HintsNameCommandAndReason;
    [Test]
    procedure InlineLeavesCrumbsTheLeftSide;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Settings.ToolbarItems,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Outline.Breadcrumbs,
  Atlas.UI.Outline.Breadcrumbs;

/// <summary>Punkt als lParam einer Mausnachricht.</summary>
function MousePoint(const APoint: TPoint): LPARAM;
begin
  Result := MakeLParam(Word(APoint.X), Word(APoint.Y));
end;

function Sample: TArray<TAtlasToolbarButton>;
var
  Button: TAtlasToolbarButton;
begin
  Result := nil;
  Button := TAtlasToolbarButton.Create(TAtlasToolbarItems.GotoInterface, 'Zum interface-Teil', 'Zum interface-Teil',
    TAtlasToolbarIcon.InterfacePart);
  Button.Pinned := True;
  Result := Result + [Button];
  Button := TAtlasToolbarButton.Create(TAtlasToolbarItems.GotoImplementation, 'Zum implementation-Teil', '',
    TAtlasToolbarIcon.ImplementationPart);
  Button.Pinned := True;
  Button.Pressed := True;
  Result := Result + [Button];
  Result := Result + [TAtlasToolbarButton.Separator];
  Result := Result + [TAtlasToolbarButton.Create('Atlas.NavBack', 'Zurück', 'Zurück (Alt+Links)',
    TAtlasToolbarIcon.Back)];
  Button := TAtlasToolbarButton.Create('Atlas.NavForward', 'Vor', 'Vor', TAtlasToolbarIcon.Forward);
  Button.Enabled := False;
  Result := Result + [Button];
  Result := Result + [TAtlasToolbarButton.Separator];
  Button := TAtlasToolbarButton.Create('Atlas.ProblemsWindow', 'Probleme', 'Probleme · 3 Befunde',
    TAtlasToolbarIcon.Problems);
  Button.Dot := True;
  Result := Result + [Button];
  Result := Result + [TAtlasToolbarButton.Create('Atlas.Custom', 'Eigener Befehl', '', TAtlasToolbarIcon.Letter)];
end;

procedure TAtlasEditorToolbarTests.WarmUpFirstUse;
begin
  SetUp;
  try
    KeepsHeightAndOrder;
  finally
    TearDown;
  end;
end;

procedure TAtlasEditorToolbarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 800;
  FForm.Height := 300;
  FBar := TAtlasEditorToolbar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
end;

procedure TAtlasEditorToolbarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasEditorToolbarTests.KeepsHeightAndOrder;
var
  Height_: Integer;
begin
  Height_ := FBar.Height;
  Assert.AreEqual(TAtlasEditorToolbar.BarHeight(FBar.CurrentPPI), Height_);
  FBar.SetButtons(Sample);
  FBar.Height := Height_ * 2;
  Assert.AreEqual(Height_, FBar.Height, 'eine Zeile, nie höher');
  Assert.IsTrue(FBar.ButtonRect(TAtlasToolbarItems.GotoInterface).Right <=
    FBar.ButtonRect(TAtlasToolbarItems.GotoImplementation).Left, 'Reihenfolge von links');
  Assert.IsTrue(FBar.ButtonRect('Atlas.NavBack').Left > FBar.ButtonRect(TAtlasToolbarItems.GotoImplementation).Right,
    'Trennstrich dazwischen');
  Assert.IsTrue(FBar.MoreRect.IsEmpty, 'alles passt');
  Assert.AreEqual(0, Integer(Length(FBar.OverflowIds)));
  Assert.IsTrue(FBar.GearRect.Right > FBar.ClientWidth - 10, 'Zahnrad rechts außen');
  Assert.IsTrue(FBar.PreferredWidth < FBar.ClientWidth);
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.ReturnFollowsPinnedSections;
begin
  FBar.SetButtons(Sample);
  Assert.IsTrue(FBar.ReturnRect.IsEmpty);
  FBar.SetReturn(True, '214', 'Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick');
  Assert.IsFalse(FBar.ReturnRect.IsEmpty);
  Assert.IsTrue(FBar.ReturnRect.Left >= FBar.ButtonRect(TAtlasToolbarItems.GotoImplementation).Right,
    'hinter den Abschnittssymbolen');
  Assert.IsTrue(FBar.ReturnRect.Right <= FBar.ButtonRect('Atlas.NavBack').Left);
  Assert.AreEqual('Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick',
    FBar.HintAt(FBar.ReturnRect.CenterPoint.X, FBar.ReturnRect.CenterPoint.Y));
  FBar.Repaint;
  FBar.SetReturn(False, '', '');
  Assert.IsTrue(FBar.ReturnRect.IsEmpty);
end;

procedure TAtlasEditorToolbarTests.NarrowBarOverflows;
var
  Overflow: TArray<string>;
begin
  FBar.SetButtons(Sample);
  FBar.SetReturn(True, '214', '');
  // alTop: Die Leiste ist so breit wie das Formular.
  FForm.ClientWidth := 204;
  Assert.IsFalse(FBar.MoreRect.IsEmpty, '» erscheint');
  Overflow := FBar.OverflowIds;
  Assert.IsTrue(Length(Overflow) > 0);
  Assert.AreEqual('Atlas.Custom', Overflow[High(Overflow)], 'Reihenfolge bleibt');
  Assert.IsFalse(FBar.ButtonRect(TAtlasToolbarItems.GotoInterface).IsEmpty, 'angeheftet');
  Assert.IsFalse(FBar.ButtonRect(TAtlasToolbarItems.GotoImplementation).IsEmpty, 'angeheftet');
  Assert.IsFalse(FBar.ReturnRect.IsEmpty, 'Rücksprung bleibt sichtbar');
  Assert.IsFalse(Overflow[0] = TAtlasToolbarItems.Separator, 'kein Trennstrich vorn im Menü');
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.ClicksAndDisabledButtons;
var
  Fired: string;
  Returned, Customized: Boolean;
  Area: TRect;
begin
  Fired := '';
  Returned := False;
  Customized := False;
  FBar.OnCommand :=
    procedure(const AId: string)
    begin
      Fired := AId;
    end;
  FBar.OnReturn :=
    procedure
    begin
      Returned := True;
    end;
  FBar.OnCustomize :=
    procedure
    begin
      Customized := True;
    end;
  FBar.SetButtons(Sample);
  FBar.SetReturn(True, '214', '');
  Area := FBar.ButtonRect('Atlas.NavBack');
  FBar.ClickAt(Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual('Atlas.NavBack', Fired);
  Fired := '';
  Area := FBar.ButtonRect('Atlas.NavForward');
  FBar.ClickAt(Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual('', Fired, 'gesperrt');
  Area := FBar.ReturnRect;
  FBar.ClickAt(Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.IsTrue(Returned);
  Area := FBar.GearRect;
  FBar.ClickAt(Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.IsTrue(Customized);
  FBar.OnCommand := nil;
  FBar.OnReturn := nil;
  FBar.OnCustomize := nil;
end;

/// <summary>Regression (#1101): Ein Klick tat in der IDE nichts, Delphi flackerte nur. Zwischen Drücken und
/// Loslassen kommt dort CM_MOUSELEAVE, und das löschte den gedrückten Knopf.</summary>
procedure TAtlasEditorToolbarTests.MouseClickSurvivesMouseLeave;
var
  Fired: string;
  Customized: Boolean;
  Back, Problems, Gear: LPARAM;
begin
  Fired := '';
  Customized := False;
  FBar.OnCommand :=
    procedure(const AId: string)
    begin
      Fired := AId;
    end;
  FBar.OnCustomize :=
    procedure
    begin
      Customized := True;
    end;
  FBar.SetButtons(Sample);
  // Mauspunkte als lParam der Fensternachrichten.
  Back := MousePoint(FBar.ButtonRect('Atlas.NavBack').CenterPoint);
  Problems := MousePoint(FBar.ButtonRect('Atlas.ProblemsWindow').CenterPoint);
  Gear := MousePoint(FBar.GearRect.CenterPoint);
  // Drücken, Mausverlassen (Mausfang, Fokus in den Editor), Loslassen auf demselben Knopf.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, Back);
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  FBar.Perform(WM_LBUTTONUP, 0, Back);
  Assert.AreEqual('Atlas.NavBack', Fired, 'Klick trotz Mausverlassen');
  Fired := '';
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, Gear);
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  FBar.Perform(WM_LBUTTONUP, 0, Gear);
  Assert.IsTrue(Customized, 'Zahnrad trotz Mausverlassen');
  // Ohne gesehenes Drücken zählt das Loslassen über dem Knopf.
  FBar.Perform(WM_LBUTTONUP, 0, Problems);
  Assert.AreEqual('Atlas.ProblemsWindow', Fired, 'Loslassen ohne Drücken');
  Fired := '';
  // Auf einem Knopf gedrückt, auf einem anderen losgelassen: kein Befehl.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, Back);
  FBar.Perform(WM_LBUTTONUP, 0, Problems);
  Assert.AreEqual('', Fired, 'auf anderem Knopf losgelassen');
  // Danach ist nichts mehr gedrückt: Der nächste Klick gilt wieder.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, Problems);
  FBar.Perform(WM_LBUTTONUP, 0, Problems);
  Assert.AreEqual('Atlas.ProblemsWindow', Fired, 'nächster Klick');
  Fired := '';
  FBar.OnCommand := nil;
  FBar.OnCustomize := nil;
end;

procedure TAtlasEditorToolbarTests.ReportsDisablingBeforeItHappens;
var
  Calls: Integer;
  EnabledAtCall: Boolean;
begin
  Calls := 0;
  EnabledAtCall := False;
  FBar.OnDisabled :=
    procedure(Sender: TObject)
    begin
      Inc(Calls);
      EnabledAtCall := TAtlasEditorToolbar(Sender).Enabled;
    end;
  FBar.Enabled := False;
  Assert.AreEqual(1, Calls);
  Assert.IsTrue(EnabledAtCall, 'gemeldet, bevor gesperrt');
  Assert.IsFalse(FBar.Enabled);
  // Schon gesperrt oder wieder frei: keine Meldung.
  FBar.Enabled := False;
  FBar.Enabled := True;
  Assert.AreEqual(1, Calls);
  FBar.OnDisabled := nil;
end;

procedure TAtlasEditorToolbarTests.HintsNameCommandAndReason;
var
  Area: TRect;
begin
  FBar.SetButtons(Sample);
  Area := FBar.ButtonRect('Atlas.NavBack');
  Assert.AreEqual('Zurück (Alt+Links)', FBar.HintAt(Area.CenterPoint.X, Area.CenterPoint.Y));
  Area := FBar.ButtonRect(TAtlasToolbarItems.GotoImplementation);
  Assert.AreEqual('Zum implementation-Teil', FBar.HintAt(Area.CenterPoint.X, Area.CenterPoint.Y),
    'ohne Tooltip die Beschriftung');
  Area := FBar.ButtonRect('Atlas.ProblemsWindow');
  Assert.AreEqual('Probleme · 3 Befunde', FBar.HintAt(Area.CenterPoint.X, Area.CenterPoint.Y));
  // Mit Text neben den Symbolen werden die Knöpfe breiter.
  Area := FBar.ButtonRect('Atlas.NavBack');
  FBar.Labels := True;
  Assert.IsTrue(FBar.ButtonRect('Atlas.NavBack').Width > Area.Width);
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.InlineLeavesCrumbsTheLeftSide;
var
  Crumbs: TAtlasBreadcrumbBar;
  Path: TAtlasCrumbs;
  Crumb: TAtlasCrumb;
begin
  Crumbs := TAtlasBreadcrumbBar.Create(FForm);
  Crumbs.Parent := FForm;
  Crumbs.Align := alTop;
  Crumbs.HandleNeeded;
  Path := nil;
  Crumb := Default(TAtlasCrumb);
  Crumb.Text := 'uKundeForm';
  Crumb.Node := -1;
  Path := Path + [Crumb];
  Crumb.Text := 'TfrmKunde.btnSpeichernClickMitEinemSehrLangenNamen';
  Crumb.Node := 0;
  Path := Path + [Crumb];
  Crumbs.SetCrumbs(Path);
  FBar.Parent := nil;
  FBar.InlineMode := True;
  FBar.Align := alRight;
  FBar.Parent := Crumbs;
  FBar.SetButtons(Sample);
  FBar.Width := 300;
  Assert.AreEqual(Crumbs.ClientWidth - 300, Crumbs.ContentRight);
  Assert.IsTrue(Crumbs.CrumbRect(1).Right <= Crumbs.ContentRight, 'Glieder links der Leiste');
  Crumbs.Repaint;
  FBar.Repaint;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorToolbarTests);

end.
