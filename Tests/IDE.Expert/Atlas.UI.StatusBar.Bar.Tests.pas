unit Atlas.UI.StatusBar.Bar.Tests;

// Atlas-Statusleiste (#1155), Darstellung: feste Höhe einer Zeile, Elemente in
// der Reihenfolge der Einstellung, Zahnrad rechts, schmale Leiste kürzt erst
// die Methode und lässt Elemente weg statt umzubrechen, Klicks auf Status,
// Zähler, Live-Prüfung, Methode, Doppelklick auf die Zähler, Tooltips und das Menü
// „Leiste anpassen“ mit Häkchen.

interface

uses
  DUnitX.TestFramework,
  Vcl.Forms,
  Atlas.UI.StatusBar.Bar;

type
  [TestFixture]
  TAtlasEditorStatusBarTests = class
  private
    FForm: TForm;
    FBar: TAtlasEditorStatusBar;
  public
    [Setup]
    procedure SetUp;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure KeepsHeightAndOrder;
    [Test]
    procedure NarrowBarDropsInsteadOfWrapping;
    [Test]
    procedure ClicksReachTheirEvents;
    [Test]
    procedure HintsAndMenu;
    /// <summary>#1234: Plakette der Benachrichtigungen direkt hinter dem Status, nur mit ungelesenen; Klick meldet
    /// ihre Ecke.</summary>
    [Test]
    procedure BadgeFollowsTheStatus;
    /// <summary>Zusatzfelder (z. B. „interface-Änderung“ der Unit-Beziehungen) stehen hinter Status und Plakette,
    /// mit eigenem Tooltip; ein Klick meldet Kennung und Ecke, nur bei Feldern mit Klick.</summary>
    [Test]
    procedure ExtrasFollowTheStatus;
    [Test]
    procedure ExtraWithStateHasDot;
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Menus,
  Atlas.Core.Status.Contract,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Settings.StatusBarItems;

function Sample: TAtlasStatusBarView;
begin
  Result := Default(TAtlasStatusBarView);
  Result.Items := TAtlasStatusBarItems.All;
  Result.StatusText := 'Atlas · bereit';
  Result.StatusHint := 'Atlas läuft';
  Result.FindingsShown := True;
  Result.Counts[TAtlasFindingKind.Error] := 2;
  Result.Counts[TAtlasFindingKind.Warning] := 5;
  Result.Counts[TAtlasFindingKind.Info] := 1;
  Result.FindingsHint := '2 Fehler, 5 Warnungen, 1 Hinweis';
  Result.LiveText := 'live · geprüft vor 2 s';
  Result.LiveHint := 'Live-Prüfung an';
  Result.MethodFound := True;
  Result.MethodName := 'TKunde.Speichern';
  Result.MethodDetail := '48 Zeilen · CC 9';
  Result.MethodHint := 'Zum Methodenkopf';
  Result.MethodOver := True;
end;

function Middle(const ARect: TRect): TPoint;
begin
  Result := Point((ARect.Left + ARect.Right) div 2, (ARect.Top + ARect.Bottom) div 2);
end;

procedure TAtlasEditorStatusBarTests.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.Width := 1000;
  FForm.Height := 300;
  FBar := TAtlasEditorStatusBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Align := alBottom;
  FBar.HandleNeeded;
  FBar.Texts := TAtlasStatusBarTexts.Create(TArray<string>.Create('Status', 'Meldungen', 'Live-Prüfung', 'Methode'),
    'Leiste anpassen …', 'Statusleiste ausblenden');
end;

procedure TAtlasEditorStatusBarTests.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FBar := nil;
end;

procedure TAtlasEditorStatusBarTests.KeepsHeightAndOrder;
var
  Height_: Integer;
begin
  Height_ := FBar.Height;
  Assert.AreEqual(TAtlasEditorStatusBar.BarHeight(FBar.CurrentPPI), Height_);
  FBar.SetView(Sample);
  FBar.Height := Height_ * 2;
  Assert.AreEqual(Height_, FBar.Height, 'eine Zeile, nie höher');
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Status).IsEmpty, 'Status');
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Status).Right <= FBar.PartRect(TAtlasStatusBarPart.Findings).Left);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Findings).Right <=
    FBar.PartRect(TAtlasStatusBarPart.LiveCheck).Left);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.LiveCheck).Right <= FBar.PartRect(TAtlasStatusBarPart.Method).Left);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Method).Right <= FBar.PartRect(TAtlasStatusBarPart.Gear).Left,
    'Zahnrad rechts');
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Gear).Right <= FBar.ClientWidth, 'Zahnrad in der Leiste');
  Assert.IsTrue(FBar.KindRect(TAtlasFindingKind.Error).Right <= FBar.KindRect(TAtlasFindingKind.Warning).Left);
  Assert.IsTrue(FBar.KindRect(TAtlasFindingKind.Warning).Right <= FBar.KindRect(TAtlasFindingKind.Info).Left);
end;

procedure TAtlasEditorStatusBarTests.NarrowBarDropsInsteadOfWrapping;
var
  View: TAtlasStatusBarView;
  Wide, Narrow: Integer;
begin
  View := Sample;
  FBar.SetView(View);
  Wide := FBar.PartRect(TAtlasStatusBarPart.Method).Width;
  FForm.Width := 520;
  Narrow := FBar.PartRect(TAtlasStatusBarPart.Method).Width;
  Assert.IsTrue(Narrow < Wide, 'Methode kürzt sich zuerst');
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Findings).IsEmpty, 'Zähler bleiben');
  FForm.Width := 120;
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Method).IsEmpty, 'Methode fällt weg');
  Assert.AreEqual(TAtlasEditorStatusBar.BarHeight(FBar.CurrentPPI), FBar.Height, 'bricht nicht um');
  // Ohne Probleme fällt das Element weg; ohne Element in der Einstellung ebenso.
  FForm.Width := 1000;
  View.FindingsShown := False;
  View.Items := TArray<string>.Create(TAtlasStatusBarItems.cStatus, TAtlasStatusBarItems.cFindings);
  FBar.SetView(View);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Findings).IsEmpty, 'Probleme aus');
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.LiveCheck).IsEmpty, 'nicht gewählt');
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Status).IsEmpty);
end;

type
  /// <summary>Hält fest, welche Ereignisse der Leiste ankamen.</summary>
  TStatusBarClickProbe = class
  public
    FStatusAt: TPoint;
    FKind: TAtlasFindingKind;
    FKindHit: Integer;
    FOpened: Integer;
    FMethodHit: Integer;
    FRechecked: Integer;
  end;

/// <summary>Hängt die Ereignisse der Leiste an die Probe.</summary>
procedure WireStatusBarClicks(const ABar: TAtlasEditorStatusBar; const AProbe: TStatusBarClickProbe);
begin
  AProbe.FStatusAt := Point(-1, -1);
  AProbe.FKind := TAtlasFindingKind.Info;
  ABar.OnLiveCheck :=
    procedure
    begin
      Inc(AProbe.FRechecked);
    end;
  ABar.OnStatus :=
    procedure(APoint: TPoint)
    begin
      AProbe.FStatusAt := APoint;
    end;
  ABar.OnFinding :=
    procedure(AKind: TAtlasFindingKind)
    begin
      AProbe.FKind := AKind;
      Inc(AProbe.FKindHit);
    end;
  ABar.OnFindingsOpen :=
    procedure
    begin
      Inc(AProbe.FOpened);
    end;
  ABar.OnMethod :=
    procedure
    begin
      Inc(AProbe.FMethodHit);
    end;
end;

/// <summary>Ohne Methode, Doppelklick auf Status und Live-Prüfung, Klick auf die Live-Prüfung.</summary>
procedure AssertStatusBarLaterClicks(const ABar: TAtlasEditorStatusBar; const AProbe: TStatusBarClickProbe);
var
  mView: TAtlasStatusBarView;
  mPoint: TPoint;
begin
  // Ohne Methode am Cursor springt nichts.
  mView := Sample;
  mView.MethodFound := False;
  mView.MethodName := 'keine Methode';
  ABar.SetView(mView);
  mPoint := Middle(ABar.PartRect(TAtlasStatusBarPart.Method));
  ABar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, AProbe.FMethodHit, 'keine Methode');
  mPoint := Middle(ABar.PartRect(TAtlasStatusBarPart.LiveCheck));
  ABar.DoubleClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, AProbe.FOpened, 'nur auf den Zählern');
  // Doppelklick auf den Status öffnet das Fenster „Atlas-Server“ (#1356), ohne Hook nichts.
  mPoint := Middle(ABar.PartRect(TAtlasStatusBarPart.Status));
  ABar.DoubleClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, AProbe.FOpened, 'Status öffnet nicht „Atlas-Prüfung“');
  ABar.OnStatusOpen :=
    procedure
    begin
      Inc(AProbe.FOpened, 10);
    end;
  ABar.DoubleClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(11, AProbe.FOpened, 'Fenster „Atlas-Server“');
  ABar.OnStatusOpen := nil;
  // Klick auf die Live-Prüfung prüft alle Units neu (#1231).
  mPoint := Middle(ABar.PartRect(TAtlasStatusBarPart.LiveCheck));
  ABar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual(1, AProbe.FRechecked, 'Live-Prüfung');
end;

procedure TAtlasEditorStatusBarTests.ClicksReachTheirEvents;
var
  mProbe: TStatusBarClickProbe;
  mPoint: TPoint;
begin
  mProbe := TStatusBarClickProbe.Create;
  try
    WireStatusBarClicks(FBar, mProbe);
    FBar.SetView(Sample);
    mPoint := Middle(FBar.PartRect(TAtlasStatusBarPart.Status));
    FBar.ClickAt(mPoint.X, mPoint.Y);
    Assert.AreEqual(FBar.ClientToScreen(FBar.PartRect(TAtlasStatusBarPart.Status).TopLeft).X, mProbe.FStatusAt.X,
      'Statusfenster an der Leiste');
    mPoint := Middle(FBar.KindRect(TAtlasFindingKind.Warning));
    FBar.ClickAt(mPoint.X, mPoint.Y);
    Assert.AreEqual(1, mProbe.FKindHit);
    Assert.AreEqual<TAtlasFindingKind>(TAtlasFindingKind.Warning, mProbe.FKind, 'Warnung');
    mPoint := Middle(FBar.KindRect(TAtlasFindingKind.Error));
    FBar.DoubleClickAt(mPoint.X, mPoint.Y);
    Assert.AreEqual(1, mProbe.FOpened, 'Doppelklick öffnet „Atlas-Prüfung“');
    mPoint := Middle(FBar.PartRect(TAtlasStatusBarPart.Method));
    FBar.ClickAt(mPoint.X, mPoint.Y);
    Assert.AreEqual(1, mProbe.FMethodHit);
    AssertStatusBarLaterClicks(FBar, mProbe);
  finally
    FBar.OnLiveCheck := nil;
    FBar.OnStatus := nil;
    FBar.OnFinding := nil;
    FBar.OnFindingsOpen := nil;
    FBar.OnMethod := nil;
    mProbe.Free;
  end;
end;

procedure TAtlasEditorStatusBarTests.HintsAndMenu;
var
  View: TAtlasStatusBarView;
  P: TPoint;
  Toggled: string;
  Hidden: Boolean;
  Menu: TPopupMenu;
begin
  Toggled := '';
  Hidden := False;
  FBar.OnToggleItem :=
    procedure(const AId: string)
    begin
      Toggled := AId;
    end;
  FBar.OnHide :=
    procedure
    begin
      Hidden := True;
    end;
  View := Sample;
  View.Items := TArray<string>.Create(TAtlasStatusBarItems.cStatus, TAtlasStatusBarItems.cMethod);
  FBar.SetView(View);
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Method));
  Assert.AreEqual('Zum Methodenkopf', FBar.HintAt(P.X, P.Y));
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Gear));
  Assert.AreEqual('Leiste anpassen …', FBar.HintAt(P.X, P.Y));
  // Vier Elemente, Trennstrich, Ausblenden; das Menü gehört der Leiste.
  Menu := FBar.BuildMenu;
  Assert.AreEqual(6, Menu.Items.Count);
  Assert.IsTrue(Menu.Items[0].Checked, 'status');
  Assert.IsFalse(Menu.Items[1].Checked, 'findings');
  Assert.IsFalse(Menu.Items[2].Checked, 'liveCheck');
  Assert.IsTrue(Menu.Items[3].Checked, 'method');
  Assert.AreEqual('Live-Prüfung', Menu.Items[2].Caption);
  Menu.Items[1].Click;
  Assert.AreEqual(TAtlasStatusBarItems.cFindings, Toggled);
  Menu.Items[5].Click;
  Assert.IsTrue(Hidden, 'ausblenden');
end;

procedure TAtlasEditorStatusBarTests.BadgeFollowsTheStatus;
var
  View: TAtlasStatusBarView;
  Clicked: TPoint;
  P: TPoint;
begin
  Clicked := Point(-1, -1);
  FBar.OnBadge :=
    procedure(APoint: TPoint)
    begin
      Clicked := APoint;
    end;
  View := Sample;
  FBar.SetView(View);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Badge).IsEmpty, 'Benachrichtigungen aus: keine Plakette');
  // Benachrichtigungen an: Plakette immer, auch ohne Ungelesene; ein Klick öffnet die Liste.
  View.BadgeShown := True;
  View.BadgeHint := '0 ungelesene Benachrichtigungen';
  FBar.SetView(View);
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Badge).IsEmpty, 'Plakette auch mit 0');
  Assert.AreEqual('0', View.BadgeText);
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Badge));
  Assert.AreEqual('0 ungelesene Benachrichtigungen', FBar.HintAt(P.X, P.Y));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(FBar.ClientToScreen(FBar.PartRect(TAtlasStatusBarPart.Badge).TopLeft).X, Clicked.X);
  Clicked := Point(-1, -1);
  View.BadgeCount := 3;
  View.BadgeHint := '3 ungelesene Benachrichtigungen';
  FBar.SetView(View);
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Badge).IsEmpty);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Status).Right <= FBar.PartRect(TAtlasStatusBarPart.Badge).Left);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Badge).Right <= FBar.PartRect(TAtlasStatusBarPart.Findings).Left);
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Badge));
  Assert.AreEqual('3 ungelesene Benachrichtigungen', FBar.HintAt(P.X, P.Y));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(FBar.ClientToScreen(FBar.PartRect(TAtlasStatusBarPart.Badge).TopLeft).X, Clicked.X);
  // Ohne Element status auch keine Plakette (dann steht sie im Atlas-Feld der Statuszeile).
  View.Items := TArray<string>.Create(TAtlasStatusBarItems.cMethod);
  FBar.SetView(View);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Badge).IsEmpty);
end;

function Extra(const AId, AText, AHint: string; AClickable: Boolean): TAtlasStatusBarExtra;
begin
  Result := Default(TAtlasStatusBarExtra);
  Result.Id := AId;
  Result.Text := AText;
  Result.Hint := AHint;
  Result.Clickable := AClickable;
end;

procedure TAtlasEditorStatusBarTests.ExtrasFollowTheStatus;
var
  mView: TAtlasStatusBarView;
  mClickedId: string;
  mClickedAt, mPoint: TPoint;
  mContext: Boolean;
begin
  mClickedId := '';
  mClickedAt := Point(-1, -1);
  mContext := True;
  FBar.OnExtra :=
    procedure(const AId: string; const APoint: TPoint; AContext: Boolean)
    begin
      mClickedId := AId;
      mClickedAt := APoint;
      mContext := AContext;
    end;
  mView := Sample;
  mView.BadgeShown := True;
  mView.BadgeCount := 1;
  mView.Extras := [Extra('interfaceCost', 'interface-Änderung: 12 Units', '12 Units werden neu übersetzt', True),
    Extra('startProfile', 'Profil: Debug', 'Startprofil', False)];
  FBar.SetView(mView);
  Assert.IsFalse(FBar.ExtraRect(0).IsEmpty, 'erstes Zusatzfeld');
  Assert.IsFalse(FBar.ExtraRect(1).IsEmpty, 'zweites Zusatzfeld');
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Badge).Right <= FBar.ExtraRect(0).Left, 'hinter der Plakette');
  Assert.IsTrue(FBar.ExtraRect(0).Right <= FBar.ExtraRect(1).Left, 'in ihrer Reihenfolge');
  Assert.IsTrue(FBar.ExtraRect(1).Right <= FBar.PartRect(TAtlasStatusBarPart.Findings).Left, 'vor den Zählern');
  mPoint := Middle(FBar.ExtraRect(0));
  Assert.AreEqual('12 Units werden neu übersetzt', FBar.HintAt(mPoint.X, mPoint.Y));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual('interfaceCost', mClickedId);
  Assert.AreEqual(FBar.ClientToScreen(FBar.ExtraRect(0).TopLeft).X, mClickedAt.X);
  Assert.IsFalse(mContext, 'Linksklick');
  // Ohne Klick meldet das Feld nichts.
  mClickedId := '';
  mPoint := Middle(FBar.ExtraRect(1));
  Assert.AreEqual('Startprofil', FBar.HintAt(mPoint.X, mPoint.Y));
  FBar.ClickAt(mPoint.X, mPoint.Y);
  Assert.AreEqual('', mClickedId);
  // Ohne Element status auch keine Zusatzfelder (dann stehen sie in der Statuszeile).
  mView.Items := TArray<string>.Create(TAtlasStatusBarItems.cMethod);
  FBar.SetView(mView);
  Assert.IsTrue(FBar.ExtraRect(0).IsEmpty);
end;

procedure TAtlasEditorStatusBarTests.ExtraWithStateHasDot;
var
  mView: TAtlasStatusBarView;
  mPlain: Integer;
begin
  // Teststand (#1777): Mit Zustand steht ein Punkt vor dem Text, das Feld wird breiter.
  mView := Sample;
  mView.Extras := [Extra('atlas.tests', 'Tests 41/42', '', True)];
  FBar.SetView(mView);
  mPlain := FBar.ExtraRect(0).Width;
  mView.Extras[0].State := TAtlasStatusState.Red;
  mView.Extras[0].HasContext := True;
  FBar.SetView(mView);
  Assert.IsTrue(FBar.ExtraRect(0).Width > mPlain, 'Punkt braucht Platz');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorStatusBarTests);

end.
