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
  mButton: TAtlasToolbarButton;
begin
  Result := nil;
  mButton := TAtlasToolbarButton.Create(TAtlasToolbarItems.cGotoInterface, 'Zum interface-Teil', 'Zum interface-Teil',
    TAtlasToolbarIcon.InterfacePart);
  mButton.Pinned := True;
  Result := Result + [mButton];
  mButton := TAtlasToolbarButton.Create(TAtlasToolbarItems.cGotoImplementation, 'Zum implementation-Teil', '',
    TAtlasToolbarIcon.ImplementationPart);
  mButton.Pinned := True;
  mButton.Pressed := True;
  Result := Result + [mButton];
  Result := Result + [TAtlasToolbarButton.Separator];
  Result := Result + [TAtlasToolbarButton.Create('Atlas.NavBack', 'Zurück', 'Zurück (Alt+Links)',
    TAtlasToolbarIcon.Back)];
  mButton := TAtlasToolbarButton.Create('Atlas.NavForward', 'Vor', 'Vor', TAtlasToolbarIcon.Forward);
  mButton.Enabled := False;
  Result := Result + [mButton];
  Result := Result + [TAtlasToolbarButton.Separator];
  mButton := TAtlasToolbarButton.Create('Atlas.ProblemsWindow', 'Probleme', 'Probleme · 3 Befunde',
    TAtlasToolbarIcon.Problems);
  mButton.Dot := True;
  Result := Result + [mButton];
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
  // Rücksprung mit Hinweis und Neuzeichnen: legt beim ersten Mal Daten der RTL an (je nach Reihenfolge der Teile
  // sonst als Leck in ReturnFollowsPinnedSections gemeldet).
  SetUp;
  try
    ReturnFollowsPinnedSections;
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
  mHeight_: Integer;
begin
  mHeight_ := FBar.Height;
  Assert.AreEqual(TAtlasEditorToolbar.BarHeight(FBar.CurrentPPI), mHeight_);
  FBar.SetButtons(Sample);
  FBar.Height := mHeight_ * 2;
  Assert.AreEqual(mHeight_, FBar.Height, 'eine Zeile, nie höher');
  Assert.IsTrue(FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoInterface).Right <=
    FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoImplementation).Left, 'Reihenfolge von links');
  Assert.IsTrue(FBar.Places.ButtonRect('Atlas.NavBack').Left > FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoImplementation).Right,
    'Trennstrich dazwischen');
  Assert.IsTrue(FBar.Places.More.IsEmpty, 'alles passt');
  Assert.AreEqual(0, Integer(Length(FBar.Places.OverflowIds)));
  Assert.IsTrue(FBar.Places.Gear.Right > FBar.ClientWidth - 10, 'Zahnrad rechts außen');
  Assert.IsTrue(FBar.PreferredWidth < FBar.ClientWidth);
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.ReturnFollowsPinnedSections;
begin
  FBar.SetButtons(Sample);
  Assert.IsTrue(FBar.Places.Return.IsEmpty);
  FBar.SetReturn(True, '214', 'Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick');
  Assert.IsFalse(FBar.Places.Return.IsEmpty);
  Assert.IsTrue(FBar.Places.Return.Left >= FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoImplementation).Right,
    'hinter den Abschnittssymbolen');
  Assert.IsTrue(FBar.Places.Return.Right <= FBar.Places.ButtonRect('Atlas.NavBack').Left);
  Assert.AreEqual('Zurück zu Zeile 214 · TfrmKunde.btnSpeichernClick',
    FBar.HintAt(FBar.Places.Return.CenterPoint.X, FBar.Places.Return.CenterPoint.Y));
  FBar.Repaint;
  FBar.SetReturn(False, '', '');
  Assert.IsTrue(FBar.Places.Return.IsEmpty);
end;

procedure TAtlasEditorToolbarTests.NarrowBarOverflows;
var
  mOverflow: TArray<string>;
begin
  FBar.SetButtons(Sample);
  FBar.SetReturn(True, '214', '');
  // alTop: Die Leiste ist so breit wie das Formular.
  FForm.ClientWidth := 204;
  Assert.IsFalse(FBar.Places.More.IsEmpty, '» erscheint');
  mOverflow := FBar.Places.OverflowIds;
  Assert.IsTrue(Length(mOverflow) > 0);
  Assert.AreEqual('Atlas.Custom', mOverflow[High(mOverflow)], 'Reihenfolge bleibt');
  Assert.IsFalse(FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoInterface).IsEmpty, 'angeheftet');
  Assert.IsFalse(FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoImplementation).IsEmpty, 'angeheftet');
  Assert.IsFalse(FBar.Places.Return.IsEmpty, 'Rücksprung bleibt sichtbar');
  Assert.AreNotEqual(TAtlasToolbarItems.cSeparator, mOverflow[0], 'kein Trennstrich vorn im Menü');
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.ClicksAndDisabledButtons;
var
  mFired: string;
  mReturned, mCustomized: Boolean;
  mArea: TRect;
begin
  mFired := '';
  mReturned := False;
  mCustomized := False;
  FBar.OnCommand :=
    procedure(const AId: string)
    begin
      mFired := AId;
    end;
  FBar.OnReturn :=
    procedure
    begin
      mReturned := True;
    end;
  FBar.OnCustomize :=
    procedure
    begin
      mCustomized := True;
    end;
  FBar.SetButtons(Sample);
  FBar.SetReturn(True, '214', '');
  mArea := FBar.Places.ButtonRect('Atlas.NavBack');
  FBar.ClickAt(mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual('Atlas.NavBack', mFired);
  mFired := '';
  mArea := FBar.Places.ButtonRect('Atlas.NavForward');
  FBar.ClickAt(mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual('', mFired, 'gesperrt');
  mArea := FBar.Places.Return;
  FBar.ClickAt(mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.IsTrue(mReturned);
  mArea := FBar.Places.Gear;
  FBar.ClickAt(mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.IsTrue(mCustomized);
  FBar.OnCommand := nil;
  FBar.OnReturn := nil;
  FBar.OnCustomize := nil;
end;

/// <summary>Regression (#1101): Ein Klick tat in der IDE nichts, Delphi flackerte nur. Zwischen Drücken und
/// Loslassen kommt dort CM_MOUSELEAVE, und das löschte den gedrückten Knopf.</summary>
procedure TAtlasEditorToolbarTests.MouseClickSurvivesMouseLeave;
var
  mFired: string;
  mCustomized: Boolean;
  mBack, mProblems, mGear: LPARAM;
begin
  mFired := '';
  mCustomized := False;
  FBar.OnCommand :=
    procedure(const AId: string)
    begin
      mFired := AId;
    end;
  FBar.OnCustomize :=
    procedure
    begin
      mCustomized := True;
    end;
  FBar.SetButtons(Sample);
  // Mauspunkte als lParam der Fensternachrichten.
  mBack := MousePoint(FBar.Places.ButtonRect('Atlas.NavBack').CenterPoint);
  mProblems := MousePoint(FBar.Places.ButtonRect('Atlas.ProblemsWindow').CenterPoint);
  mGear := MousePoint(FBar.Places.Gear.CenterPoint);
  // Drücken, Mausverlassen (Mausfang, Fokus in den Editor), Loslassen auf demselben Knopf.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mBack);
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  FBar.Perform(WM_LBUTTONUP, 0, mBack);
  Assert.AreEqual('Atlas.NavBack', mFired, 'Klick trotz Mausverlassen');
  mFired := '';
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mGear);
  FBar.Perform(CM_MOUSELEAVE, 0, 0);
  FBar.Perform(WM_LBUTTONUP, 0, mGear);
  Assert.IsTrue(mCustomized, 'Zahnrad trotz Mausverlassen');
  // Ohne gesehenes Drücken zählt das Loslassen über dem Knopf.
  FBar.Perform(WM_LBUTTONUP, 0, mProblems);
  Assert.AreEqual('Atlas.ProblemsWindow', mFired, 'Loslassen ohne Drücken');
  mFired := '';
  // Auf einem Knopf gedrückt, auf einem anderen losgelassen: kein Befehl.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mBack);
  FBar.Perform(WM_LBUTTONUP, 0, mProblems);
  Assert.AreEqual('', mFired, 'auf anderem Knopf losgelassen');
  // Danach ist nichts mehr gedrückt: Der nächste Klick gilt wieder.
  FBar.Perform(WM_LBUTTONDOWN, MK_LBUTTON, mProblems);
  FBar.Perform(WM_LBUTTONUP, 0, mProblems);
  Assert.AreEqual('Atlas.ProblemsWindow', mFired, 'nächster Klick');
  mFired := '';
  FBar.OnCommand := nil;
  FBar.OnCustomize := nil;
end;

procedure TAtlasEditorToolbarTests.ReportsDisablingBeforeItHappens;
var
  mCalls: Integer;
  mEnabledAtCall: Boolean;
begin
  mCalls := 0;
  mEnabledAtCall := False;
  FBar.OnDisabled :=
    procedure(Sender: TObject)
    begin
      Inc(mCalls);
      mEnabledAtCall := TAtlasEditorToolbar(Sender).Enabled;
    end;
  FBar.Enabled := False;
  Assert.AreEqual(1, mCalls);
  Assert.IsTrue(mEnabledAtCall, 'gemeldet, bevor gesperrt');
  Assert.IsFalse(FBar.Enabled);
  // Schon gesperrt oder wieder frei: keine Meldung.
  FBar.Enabled := False;
  FBar.Enabled := True;
  Assert.AreEqual(1, mCalls);
  FBar.OnDisabled := nil;
end;

procedure TAtlasEditorToolbarTests.HintsNameCommandAndReason;
var
  mArea: TRect;
begin
  FBar.SetButtons(Sample);
  mArea := FBar.Places.ButtonRect('Atlas.NavBack');
  Assert.AreEqual('Zurück (Alt+Links)', FBar.HintAt(mArea.CenterPoint.X, mArea.CenterPoint.Y));
  mArea := FBar.Places.ButtonRect(TAtlasToolbarItems.cGotoImplementation);
  Assert.AreEqual('Zum implementation-Teil', FBar.HintAt(mArea.CenterPoint.X, mArea.CenterPoint.Y),
    'ohne Tooltip die Beschriftung');
  mArea := FBar.Places.ButtonRect('Atlas.ProblemsWindow');
  Assert.AreEqual('Probleme · 3 Befunde', FBar.HintAt(mArea.CenterPoint.X, mArea.CenterPoint.Y));
  // Mit Text neben den Symbolen werden die Knöpfe breiter.
  mArea := FBar.Places.ButtonRect('Atlas.NavBack');
  FBar.Labels := True;
  Assert.IsTrue(FBar.Places.ButtonRect('Atlas.NavBack').Width > mArea.Width);
  FBar.Repaint;
end;

procedure TAtlasEditorToolbarTests.InlineLeavesCrumbsTheLeftSide;
var
  mCrumbs: TAtlasBreadcrumbBar;
  mPath: TAtlasCrumbs;
  mCrumb: TAtlasCrumb;
begin
  mCrumbs := TAtlasBreadcrumbBar.Create(FForm);
  mCrumbs.Parent := FForm;
  mCrumbs.Align := alTop;
  mCrumbs.HandleNeeded;
  mPath := nil;
  mCrumb := Default(TAtlasCrumb);
  mCrumb.Text := 'uKundeForm';
  mCrumb.Node := -1;
  mPath := mPath + [mCrumb];
  mCrumb.Text := 'TfrmKunde.btnSpeichernClickMitEinemSehrLangenNamen';
  mCrumb.Node := 0;
  mPath := mPath + [mCrumb];
  mCrumbs.SetCrumbs(mPath);
  FBar.Parent := nil;
  FBar.InlineMode := True;
  FBar.Align := alRight;
  FBar.Parent := mCrumbs;
  FBar.SetButtons(Sample);
  FBar.Width := 300;
  Assert.AreEqual(mCrumbs.ClientWidth - 300, mCrumbs.ContentRight);
  Assert.IsTrue(mCrumbs.CrumbRect(1).Right <= mCrumbs.ContentRight, 'Glieder links der Leiste');
  mCrumbs.Repaint;
  FBar.Repaint;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorToolbarTests);

end.
