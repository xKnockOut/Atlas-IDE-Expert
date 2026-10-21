unit Atlas.UI.Outline.Breadcrumbs.Tests;

// Brotkrumenleiste (#590), Darstellung: feste Höhe, Hinweis ohne Glieder,
// Trefferprüfung, Menü nur für Glieder mit Geschwistern, Tastatur (←/→/↓/
// Esc) und Kürzen von vorn bei schmaler Leiste; „›“ mit Kindermenü,
// Springen per Strg+Klick und Strg+Enter.

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
    procedure SameCrumbsKeepSelection;
    [Test]
    procedure SeparatorOpensChildren;
    [Test]
    procedure CtrlClickAndCtrlEnterJump;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Breadcrumbs;

type
  TBarAccess = class(TAtlasBreadcrumbBar);

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
  Height_: Integer;
begin
  Height_ := FBar.Height;
  Assert.AreEqual(TAtlasBreadcrumbBar.BarHeight(FBar.CurrentPPI), Height_);
  FBar.EmptyText := 'Keine Gliederung an dieser Stelle';
  Assert.AreEqual(0, Integer(Length(FBar.Crumbs)));
  Assert.AreEqual(-1, FBar.CrumbAt(10, 5));
  FBar.SetCrumbs(Path);
  FBar.Height := Height_ * 3;
  Assert.AreEqual(Height_, FBar.Height, 'eine Zeile, nie höher');
  FBar.Repaint;
end;

procedure TAtlasBreadcrumbBarTests.HitTestAndMenuOnlyWithSiblings;
var
  Opened: Integer;
  Area: TRect;
begin
  Opened := -1;
  FBar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      Opened := AIndex;
    end;
  FBar.SetCrumbs(Path);
  Area := FBar.CrumbRect(2);
  Assert.IsFalse(Area.IsEmpty);
  Assert.AreEqual(2, FBar.CrumbAt(Area.CenterPoint.X, Area.CenterPoint.Y));
  Assert.IsTrue(FBar.CrumbRect(1).Right <= Area.Left, 'Reihenfolge von links');
  Assert.AreEqual(-1, FBar.CrumbAt(FBar.ClientWidth - 2, 5), 'rechts neben dem Pfad');
  FBar.OpenMenu(2);
  Assert.AreEqual(2, Opened);
  Opened := -1;
  FBar.OpenMenu(0);
  Assert.AreEqual(-1, Opened, 'Unit ohne Geschwister: kein Menü');
end;

procedure TAtlasBreadcrumbBarTests.KeyboardMovesAndOpens;
var
  Opened: Integer;
  Left: Boolean;
  Key: Word;
begin
  Opened := -1;
  Left := False;
  FBar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      Opened := AIndex;
    end;
  FBar.OnLeave :=
    procedure
    begin
      Left := True;
    end;
  FBar.SetCrumbs(Path);
  Assert.AreEqual(3, FBar.Selected, 'letztes Glied');
  Key := VK_LEFT;
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.AreEqual(2, FBar.Selected);
  Assert.AreEqual(0, Integer(Key), 'Taste verbraucht');
  Key := VK_DOWN;
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.AreEqual(2, Opened);
  Key := VK_RIGHT;
  TBarAccess(FBar).KeyDown(Key, []);
  Key := VK_RIGHT;
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.AreEqual(3, FBar.Selected, 'bleibt am Ende');
  Key := VK_HOME;
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.AreEqual(0, FBar.Selected);
  Key := VK_ESCAPE;
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.IsTrue(Left);
  Key := Ord('A');
  TBarAccess(FBar).KeyDown(Key, []);
  Assert.AreEqual(Ord('A'), Integer(Key), 'andere Tasten nicht verbraucht');
end;

procedure TAtlasBreadcrumbBarTests.DropsLeadingCrumbsWhenNarrow;
var
  Area: TRect;
begin
  FForm.Width := 200;
  FBar.SetCrumbs(Path);
  Assert.IsTrue(FBar.FirstShown > 0, 'vorn gekürzt');
  Assert.IsTrue(FBar.CrumbRect(0).IsEmpty);
  Area := FBar.CrumbRect(3);
  Assert.IsFalse(Area.IsEmpty, 'letztes Glied bleibt');
  Assert.AreEqual(3, FBar.CrumbAt(Area.Left + 1, 5));
  FBar.Repaint;
  FForm.Width := 1200;
  FBar.SetCrumbs(Path);
  Assert.AreEqual(0, FBar.FirstShown);
end;

procedure TAtlasBreadcrumbBarTests.SameCrumbsKeepSelection;
var
  Key: Word;
  Changed: TAtlasCrumbs;
begin
  FBar.SetCrumbs(Path);
  Key := VK_LEFT;
  TBarAccess(FBar).KeyDown(Key, []);
  FBar.SetCrumbs(Path);
  Assert.AreEqual(2, FBar.Selected, 'gleicher Pfad ändert nichts');
  Changed := Path;
  Changed[3].Text := 'Pruefe2';
  FBar.SetCrumbs(Changed);
  Assert.AreEqual(3, FBar.Selected, 'neuer Pfad wählt das letzte Glied');
end;

procedure TAtlasBreadcrumbBarTests.SeparatorOpensChildren;
var
  Opened, Menu: Integer;
  Crumbs: TAtlasCrumbs;
  Area: TRect;
  Key: Word;
begin
  Opened := -1;
  Menu := -1;
  FBar.OnOpenChildren :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      Opened := AIndex;
    end;
  FBar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      Menu := AIndex;
    end;
  FBar.SetCrumbs(PathWithChildren);
  // „›“ zwischen den Gliedern; das letzte Glied hat keine Kinder, also kein „›“ dahinter.
  Area := FBar.SeparatorRect(0);
  Assert.IsFalse(Area.IsEmpty);
  Assert.IsTrue(Area.Left >= FBar.CrumbRect(0).Right - 1, 'hinter dem Glied');
  Assert.IsTrue(Area.Right <= FBar.CrumbRect(1).Left + 1, 'vor dem nächsten Glied');
  Assert.AreEqual(0, FBar.SeparatorAt(Area.CenterPoint.X, Area.CenterPoint.Y));
  Assert.AreEqual(-1, FBar.CrumbAt(Area.CenterPoint.X, Area.CenterPoint.Y), 'kein Glied');
  Assert.IsTrue(FBar.SeparatorRect(2).IsEmpty, 'letztes Glied ohne Kinder');
  TBarAccess(FBar).MouseUp(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual(0, Opened);
  Assert.AreEqual(-1, Menu, 'kein Geschwistermenü');
  // Klick aufs Unit-Glied: Menü mit allen Elementen der Unit.
  Area := FBar.CrumbRect(0);
  TBarAccess(FBar).MouseUp(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual(0, Menu);
  // Letztes Glied mit Kindern: „›“ auch dahinter.
  Crumbs := PathWithChildren;
  Crumbs[2].Children := [8, 9];
  FBar.SetCrumbs(Crumbs);
  Area := FBar.SeparatorRect(2);
  Assert.IsFalse(Area.IsEmpty, '„›“ hinter dem letzten Glied');
  Assert.AreEqual(2, FBar.SeparatorAt(Area.CenterPoint.X, Area.CenterPoint.Y));
  // Tastatur: Strg+↓ öffnet die Kinder des gewählten Glieds.
  Opened := -1;
  Key := VK_DOWN;
  TBarAccess(FBar).KeyDown(Key, [ssCtrl]);
  Assert.AreEqual(2, Opened);
  FBar.Repaint;
end;

procedure TAtlasBreadcrumbBarTests.CtrlClickAndCtrlEnterJump;
var
  Jumped, Menu: Integer;
  Declaration: Boolean;
  Crumbs: TAtlasCrumbs;
  Area: TRect;
  Key: Word;
begin
  Jumped := -1;
  Menu := -1;
  Declaration := False;
  FBar.OnJump :=
    procedure(AIndex: Integer; ADeclaration: Boolean)
    begin
      Jumped := AIndex;
      Declaration := ADeclaration;
    end;
  FBar.OnOpenMenu :=
    procedure(AIndex: Integer; const APoint: TPoint)
    begin
      Menu := AIndex;
    end;
  FBar.SetCrumbs(PathWithChildren);
  Area := FBar.CrumbRect(1);
  TBarAccess(FBar).MouseUp(mbLeft, [ssCtrl], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual(1, Jumped, 'Strg+Klick springt');
  Assert.IsFalse(Declaration);
  Assert.AreEqual(-1, Menu, 'kein Menü bei Strg+Klick');
  TBarAccess(FBar).MouseUp(mbLeft, [ssCtrl, ssShift], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.IsTrue(Declaration, 'Strg+Umschalt+Klick: Deklaration');
  // Unit-Glied springt an den Anfang.
  Jumped := -1;
  FBar.Jump(0, False);
  Assert.AreEqual(0, Jumped);
  // Glied ohne Knoten (Besitzer aus einer anderen Unit) springt nicht.
  Jumped := -1;
  FBar.SetCrumbs(Path);
  FBar.Jump(0, False);
  Assert.AreEqual(-1, Jumped, 'Glied ohne Knoten');
  // Ohne Geschwister springt schon der einfache Klick.
  Crumbs := PathWithChildren;
  Crumbs[2].Siblings := nil;
  FBar.SetCrumbs(Crumbs);
  Area := FBar.CrumbRect(2);
  TBarAccess(FBar).MouseUp(mbLeft, [], Area.CenterPoint.X, Area.CenterPoint.Y);
  Assert.AreEqual(2, Jumped);
  // Strg+Enter mit Fokus.
  Jumped := -1;
  Key := VK_LEFT;
  TBarAccess(FBar).KeyDown(Key, []);
  Key := VK_RETURN;
  TBarAccess(FBar).KeyDown(Key, [ssCtrl]);
  Assert.AreEqual(1, Jumped);
  Assert.AreEqual(0, Integer(Key), 'Taste verbraucht');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBreadcrumbBarTests);

end.
