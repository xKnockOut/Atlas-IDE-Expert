unit Atlas.UI.Outline.Breadcrumbs.Tests;

// Brotkrumenleiste (#590), Darstellung: feste Höhe, Hinweis ohne Glieder,
// Trefferprüfung, Menü nur für Glieder mit Geschwistern, Tastatur (←/→/↓/
// Esc) und Kürzen von vorn bei schmaler Leiste; „›“ mit Kindermenü,
// Springen per Strg+Klick und Strg+Enter; Meldung, wenn das Fenster der Leiste
// von außen gesperrt wird; Ursache, wenn die Maus nicht bei der Leiste ankommt.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.Outline.Breadcrumbs;

type
  [TestFixture]
  TAtlasBreadcrumbBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasBreadcrumbBar;
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsHeightAndShowsEmptyText;
    [Test]
    procedure HitTestAndMenuOnlyWithSiblings;
    [Test]
    procedure KeyboardMovesAndOpens;
    [Test]
    procedure DropsLeadingCrumbsWhenNarrow;
    [Test]
    procedure DropsRankedCrumbsFirst;
    [Test]
    procedure SameCrumbsKeepSelection;
    [Test]
    procedure SeparatorOpensChildren;
    [Test]
    procedure CtrlClickAndCtrlEnterJump;
    /// <summary>EnableWindow(False) von außen (wie VCL Enabled := False) meldet OnDisabled; Freigeben nicht.</summary>
    [Test]
    procedure ReportsWhenItsWindowIsDisabled;
    /// <summary>HitProblem nennt, warum Windows die Maus nicht an die Leiste gibt: ausgeblendet, gesperrt, Punkt
    /// außerhalb, Fensterregion, Geschwister darüber, HTTRANSPARENT.</summary>
    [Test]
    procedure NamesWhyTheMouseMissesTheBar;
  end;

implementation

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Breadcrumbs;

type
  TBarAccess = class(TAtlasBreadcrumbBar);

  /// <summary>Leiste, deren Fensterprozedur die Maus durchreicht, wie eine Unterklasse mit HTTRANSPARENT.</summary>
  TTransparentBar = class(TAtlasBreadcrumbBar)
  private
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
  end;

procedure TTransparentBar.WMNCHitTest(var Message: TWMNCHitTest);
begin
  Message.Result := HTTRANSPARENT;
end;

function Crumb(const AText, ACode: string; ANode: Integer; const ASiblings: TArray<Integer>): TAtlasCrumb;
begin
  Result := Default(TAtlasCrumb);
  Result.Text := AText;
  Result.Badge.Kind := TAtlasBadgeKind.Type_;
  Result.Badge.Code := ACode;
  Result.Node := ANode;
  Result.Siblings := ASiblings;
  Result.Current := -1;
end;

function Path: TAtlasCrumbs;
begin
  Result := nil;
  Result := Result + [Crumb('uKundeForm', '', -1, nil)];
  Result := Result + [Crumb('TfrmKunde', 'C', 0, [0, 5])];
  Result := Result + [Crumb('btnSpeichernClick', 'P', 2, [2, 3, 4])];
  Result := Result + [Crumb('Pruefe', 'P', 7, [7])];
end;

/// <summary>Pfad mit Kindern: Unit (Typen), Typ (Mitglieder), Methode ohne lokale Routinen.</summary>
function PathWithChildren: TAtlasCrumbs;
begin
  Result := nil;
  Result := Result + [Crumb('uKundeForm', 'un', -1, [0, 5])];
  Result[0].Badge.Kind := TAtlasBadgeKind.Unit_;
  Result[0].Children := [0, 5];
  Result := Result + [Crumb('TfrmKunde', 'ty', 0, [0, 5])];
  Result[1].Children := [1, 2, 3];
  Result := Result + [Crumb('btnSpeichernClick', 'fn', 2, [2, 3])];
end;

procedure TAtlasBreadcrumbBarTests.WarmUpFirstUse;
begin
  SetUp;
  try
    KeepsHeightAndShowsEmptyText;
  finally
    TearDown;
  end;
  // Erstes Kontextmenü (VCL) ebenfalls vorweg.
  SetUp;
  try
    HitTestAndMenuOnlyWithSiblings;
  finally
    TearDown;
  end;
  // Erstes benanntes TPanel vor einem Geschwisterfenster (VCL) ebenfalls vorweg: Es belegte einmalig bis zu 336 Byte,
  // die bis Programmende bleiben; ein zweiter Lauf belegt nichts mehr.
  SetUp;
  try
    NamesWhyTheMouseMissesTheBar;
  finally
    TearDown;
  end;
end;

procedure TAtlasBreadcrumbBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 800;
  FForm.Height := 300;
  FBar := TAtlasBreadcrumbBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alTop;
  FBar.HandleNeeded;
end;

procedure TAtlasBreadcrumbBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasBreadcrumbBarTests.KeepsHeightAndShowsEmptyText;
var
  mHeight_: Integer;
begin
  mHeight_ := FBar.Height;
  Assert.AreEqual(TAtlasBreadcrumbBar.BarHeight(FBar.CurrentPPI), mHeight_);
  FBar.EmptyText := 'Keine Gliederung an dieser Stelle';
  Assert.AreEqual(0, Integer(Length(FBar.Crumbs)));
  Assert.AreEqual(-1, FBar.CrumbAt(10, 5));
  FBar.SetCrumbs(Path);
  FBar.Height := mHeight_ * 3;
  Assert.AreEqual(mHeight_, FBar.Height, 'eine Zeile, nie höher');
  FBar.Repaint;
end;

procedure TAtlasBreadcrumbBarTests.HitTestAndMenuOnlyWithSiblings;
var
  mSetup: TAtlasCrumbBarSetup;
  mOpened: Integer;
  mArea: TRect;
begin
  mOpened := -1;
  mSetup.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      mOpened := AIndex;
    end;
  FBar.Setup := mSetup;
  FBar.SetCrumbs(Path);
  mArea := FBar.CrumbRect(2);
  Assert.IsFalse(mArea.IsEmpty);
  Assert.AreEqual(2, FBar.CrumbAt(mArea.CenterPoint.X, mArea.CenterPoint.Y));
  Assert.IsTrue(FBar.CrumbRect(1).Right <= mArea.Left, 'Reihenfolge von links');
  Assert.AreEqual(-1, FBar.CrumbAt(FBar.ClientWidth - 2, 5), 'rechts neben dem Pfad');
  FBar.OpenMenu(2);
  Assert.AreEqual(2, mOpened);
  mOpened := -1;
  FBar.OpenMenu(0);
  Assert.AreEqual(-1, mOpened, 'Unit ohne Geschwister: kein Menü');
end;

procedure TAtlasBreadcrumbBarTests.KeyboardMovesAndOpens;
var
  mSetup: TAtlasCrumbBarSetup;
  mOpened: Integer;
  mLeft: Boolean;
  mKey: Word;
begin
  mOpened := -1;
  mLeft := False;
  mSetup.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      mOpened := AIndex;
    end;
  mSetup.OnLeave :=
    procedure
    begin
      mLeft := True;
    end;
  FBar.Setup := mSetup;
  FBar.SetCrumbs(Path);
  Assert.AreEqual(3, FBar.Selected, 'letztes Glied');
  mKey := VK_LEFT;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(2, FBar.Selected);
  Assert.AreEqual(0, Integer(mKey), 'Taste verbraucht');
  mKey := VK_DOWN;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(2, mOpened);
  mKey := VK_RIGHT;
  TBarAccess(FBar).KeyDown(mKey, []);
  mKey := VK_RIGHT;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(3, FBar.Selected, 'bleibt am Ende');
  mKey := VK_HOME;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(0, FBar.Selected);
  mKey := VK_ESCAPE;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.IsTrue(mLeft);
  mKey := Ord('A');
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(Ord('A'), Integer(mKey), 'andere Tasten nicht verbraucht');
end;

procedure TAtlasBreadcrumbBarTests.DropsLeadingCrumbsWhenNarrow;
var
  mArea: TRect;
begin
  FForm.Width := 200;
  FBar.SetCrumbs(Path);
  Assert.IsTrue(FBar.FirstShown > 0, 'vorn gekürzt');
  Assert.IsTrue(FBar.CrumbRect(0).IsEmpty);
  mArea := FBar.CrumbRect(3);
  Assert.IsFalse(mArea.IsEmpty, 'letztes Glied bleibt');
  Assert.AreEqual(3, FBar.CrumbAt(mArea.Left + 1, 5));
  FBar.Repaint;
  FForm.Width := 1200;
  FBar.SetCrumbs(Path);
  Assert.AreEqual(0, FBar.FirstShown);
end;

procedure TAtlasBreadcrumbBarTests.DropsRankedCrumbsFirst;
var
  mRanked: TAtlasCrumbs;
  mKey: Word;
begin
  // Ein langes Glied mit Rang (Rahmen im Rumpf, #1769) fällt vor Unit und Typ weg.
  mRanked := Path;
  Insert(Crumb('case EinSehrLangerAusdruckMitVielenZeichenUndNochMehrZeichen of', 'kw', -1, nil), mRanked, 3);
  mRanked[3].Drop := 2;
  FForm.Width := 520;
  FBar.SetCrumbs(mRanked);
  Assert.AreEqual(0, FBar.FirstShown, 'vorn nichts gekürzt');
  Assert.IsFalse(FBar.Shown(3));
  Assert.IsTrue(FBar.CrumbRect(3).IsEmpty);
  Assert.IsFalse(FBar.CrumbRect(0).IsEmpty);
  Assert.IsFalse(FBar.CrumbRect(4).IsEmpty, 'letztes Glied bleibt');
  FBar.Repaint;
  // Die Tastatur überspringt das weggelassene Glied.
  mKey := VK_LEFT;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(2, FBar.Selected);
  mKey := VK_RIGHT;
  TBarAccess(FBar).KeyDown(mKey, []);
  Assert.AreEqual(4, FBar.Selected);
  FForm.Width := 1600;
  FBar.SetCrumbs(Path);
  FBar.SetCrumbs(mRanked);
  Assert.IsTrue(FBar.Shown(3), 'breit genug');
end;

procedure TAtlasBreadcrumbBarTests.SameCrumbsKeepSelection;
var
  mKey: Word;
  mChanged: TAtlasCrumbs;
begin
  FBar.SetCrumbs(Path);
  mKey := VK_LEFT;
  TBarAccess(FBar).KeyDown(mKey, []);
  FBar.SetCrumbs(Path);
  Assert.AreEqual(2, FBar.Selected, 'gleicher Pfad ändert nichts');
  mChanged := Path;
  mChanged[3].Text := 'Pruefe2';
  FBar.SetCrumbs(mChanged);
  Assert.AreEqual(3, FBar.Selected, 'neuer Pfad wählt das letzte Glied');
end;

procedure TAtlasBreadcrumbBarTests.SeparatorOpensChildren;
var
  mSetup: TAtlasCrumbBarSetup;
  mOpened, mMenu: Integer;
  mCrumbs: TAtlasCrumbs;
  mArea: TRect;
  mKey: Word;
begin
  mOpened := -1;
  mMenu := -1;
  mSetup.OnOpenChildren :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      mOpened := AIndex;
    end;
  mSetup.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      mMenu := AIndex;
    end;
  FBar.Setup := mSetup;
  FBar.SetCrumbs(PathWithChildren);
  // „›“ zwischen den Gliedern; das letzte Glied hat keine Kinder, also kein „›“ dahinter.
  mArea := FBar.SeparatorRect(0);
  Assert.IsFalse(mArea.IsEmpty);
  Assert.IsTrue(mArea.Left >= FBar.CrumbRect(0).Right - 1, 'hinter dem Glied');
  Assert.IsTrue(mArea.Right <= FBar.CrumbRect(1).Left + 1, 'vor dem nächsten Glied');
  Assert.AreEqual(0, FBar.SeparatorAt(mArea.CenterPoint.X, mArea.CenterPoint.Y));
  Assert.AreEqual(-1, FBar.CrumbAt(mArea.CenterPoint.X, mArea.CenterPoint.Y), 'kein Glied');
  Assert.IsTrue(FBar.SeparatorRect(2).IsEmpty, 'letztes Glied ohne Kinder');
  TBarAccess(FBar).MouseUp(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual(0, mOpened);
  Assert.AreEqual(-1, mMenu, 'kein Geschwistermenü');
  // Klick aufs Unit-Glied: Menü mit allen Elementen der Unit.
  mArea := FBar.CrumbRect(0);
  TBarAccess(FBar).MouseUp(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual(0, mMenu);
  // Letztes Glied mit Kindern: „›“ auch dahinter.
  mCrumbs := PathWithChildren;
  mCrumbs[2].Children := [8, 9];
  FBar.SetCrumbs(mCrumbs);
  mArea := FBar.SeparatorRect(2);
  Assert.IsFalse(mArea.IsEmpty, '„›“ hinter dem letzten Glied');
  Assert.AreEqual(2, FBar.SeparatorAt(mArea.CenterPoint.X, mArea.CenterPoint.Y));
  // Tastatur: Strg+↓ öffnet die Kinder des gewählten Glieds.
  mOpened := -1;
  mKey := VK_DOWN;
  TBarAccess(FBar).KeyDown(mKey, [ssCtrl]);
  Assert.AreEqual(2, mOpened);
  FBar.Repaint;
end;

procedure TAtlasBreadcrumbBarTests.CtrlClickAndCtrlEnterJump;
var
  mSetup: TAtlasCrumbBarSetup;
  mJumped, mMenu: Integer;
  mDeclaration: Boolean;
  mCrumbs: TAtlasCrumbs;
  mArea: TRect;
  mKey: Word;
begin
  mJumped := -1;
  mMenu := -1;
  mDeclaration := False;
  mSetup.OnJump :=
    procedure(AIndex: Integer; ADeclaration: Boolean)
    begin
      mJumped := AIndex;
      mDeclaration := ADeclaration;
    end;
  mSetup.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      mMenu := AIndex;
    end;
  FBar.Setup := mSetup;
  FBar.SetCrumbs(PathWithChildren);
  mArea := FBar.CrumbRect(1);
  TBarAccess(FBar).MouseUp(mbLeft, [ssCtrl], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual(1, mJumped, 'Strg+Klick springt');
  Assert.IsFalse(mDeclaration);
  Assert.AreEqual(-1, mMenu, 'kein Menü bei Strg+Klick');
  TBarAccess(FBar).MouseUp(mbLeft, [ssCtrl, ssShift], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.IsTrue(mDeclaration, 'Strg+Umschalt+Klick: Deklaration');
  // Unit-Glied springt an den Anfang.
  mJumped := -1;
  FBar.Jump(0, False);
  Assert.AreEqual(0, mJumped);
  // Glied ohne Knoten (Besitzer aus einer anderen Unit) springt nicht.
  mJumped := -1;
  FBar.SetCrumbs(Path);
  FBar.Jump(0, False);
  Assert.AreEqual(-1, mJumped, 'Glied ohne Knoten');
  // Ohne Geschwister springt schon der einfache Klick.
  mCrumbs := PathWithChildren;
  mCrumbs[2].Siblings := nil;
  FBar.SetCrumbs(mCrumbs);
  mArea := FBar.CrumbRect(2);
  TBarAccess(FBar).MouseUp(mbLeft, [], mArea.CenterPoint.X, mArea.CenterPoint.Y);
  Assert.AreEqual(2, mJumped);
  // Strg+Enter mit Fokus.
  mJumped := -1;
  mKey := VK_LEFT;
  TBarAccess(FBar).KeyDown(mKey, []);
  mKey := VK_RETURN;
  TBarAccess(FBar).KeyDown(mKey, [ssCtrl]);
  Assert.AreEqual(1, mJumped);
  Assert.AreEqual(0, Integer(mKey), 'Taste verbraucht');
end;

procedure TAtlasBreadcrumbBarTests.ReportsWhenItsWindowIsDisabled;
var
  mCalls: Integer;
begin
  mCalls := 0;
  FBar.OnDisabled :=
    procedure(ASender: TObject)
    begin
      Inc(mCalls);
    end;
  FBar.HandleNeeded;
  EnableWindow(FBar.Handle, False);
  Assert.AreEqual(1, mCalls, 'gesperrt');
  EnableWindow(FBar.Handle, True);
  Assert.AreEqual(1, mCalls, 'Freigeben meldet nichts');
  FBar.Enabled := False;
  Assert.AreEqual(2, mCalls, 'über VCL gesperrt');
  FBar.OnDisabled := nil;
end;

procedure TAtlasBreadcrumbBarTests.NamesWhyTheMouseMissesTheBar;
var
  mPoint: TPoint;
  mOther: TPanel;
  mTransparent: TTransparentBar;
begin
  FForm.Show;
  mPoint := FBar.ClientToScreen(TPoint.Create(10, 5));
  Assert.AreEqual('', FBar.HitProblem(mPoint), 'in Ordnung');
  Assert.Contains(FBar.HitProblem(FBar.ClientToScreen(TPoint.Create(10, FBar.Height + 40))),
    'außerhalb des Fensters', 'Punkt unter der Leiste');
  ShowWindow(FBar.Handle, SW_HIDE);
  Assert.Contains(FBar.HitProblem(mPoint), 'ausgeblendet');
  ShowWindow(FBar.Handle, SW_SHOWNA);
  EnableWindow(FBar.Handle, False);
  Assert.Contains(FBar.HitProblem(mPoint), 'gesperrt');
  EnableWindow(FBar.Handle, True);
  // Die Region gehört danach dem Fenster; 0 nimmt sie wieder weg.
  SetWindowRgn(FBar.Handle, CreateRectRgn(0, 0, 5, 5), False);
  Assert.Contains(FBar.HitProblem(mPoint), 'Fensterregion');
  SetWindowRgn(FBar.Handle, 0, False);
  Assert.AreEqual('', FBar.HitProblem(mPoint), 'Region wieder weg');
  mOther := TPanel.Create(FForm);
  mOther.Name := 'Darueber';
  mOther.Parent := FForm;
  mOther.SetBounds(0, 0, 100, 10);
  mOther.BringToFront;
  Assert.Contains(FBar.HitProblem(mPoint), 'Geschwisterfenster liegt darüber (TPanel Darueber)');
  mOther.Free;
  mTransparent := TTransparentBar.Create(FForm);
  mTransparent.Parent := FForm;
  mTransparent.Align := alBottom;
  Assert.Contains(mTransparent.HitProblem(mTransparent.ClientToScreen(TPoint.Create(10, 5))), 'HTTRANSPARENT');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreadcrumbBarTests);

end.
