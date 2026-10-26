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
  end;

implementation

uses
  System.SysUtils,
  System.Types,
  Vcl.Controls,
  Vcl.Menus,
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
  FBar.ItemCaptions := TArray<string>.Create('Status', 'Meldungen', 'Live-Prüfung', 'Methode');
  FBar.CustomizeCaption := 'Leiste anpassen …';
  FBar.HideCaption := 'Statusleiste ausblenden';
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
  View.Items := TArray<string>.Create(TAtlasStatusBarItems.Status, TAtlasStatusBarItems.Findings);
  FBar.SetView(View);
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.Findings).IsEmpty, 'Probleme aus');
  Assert.IsTrue(FBar.PartRect(TAtlasStatusBarPart.LiveCheck).IsEmpty, 'nicht gewählt');
  Assert.IsFalse(FBar.PartRect(TAtlasStatusBarPart.Status).IsEmpty);
end;

procedure TAtlasEditorStatusBarTests.ClicksReachTheirEvents;
var
  StatusAt: TPoint;
  Kind: TAtlasFindingKind;
  KindHit, Opened, MethodHit, Rechecked: Integer;
  View: TAtlasStatusBarView;
  P: TPoint;
begin
  StatusAt := Point(-1, -1);
  Kind := TAtlasFindingKind.Info;
  KindHit := 0;
  Opened := 0;
  MethodHit := 0;
  Rechecked := 0;
  FBar.OnLiveCheck :=
    procedure
    begin
      Inc(Rechecked);
    end;
  FBar.OnStatus :=
    procedure(APoint: TPoint)
    begin
      StatusAt := APoint;
    end;
  FBar.OnFinding :=
    procedure(AKind: TAtlasFindingKind)
    begin
      Kind := AKind;
      Inc(KindHit);
    end;
  FBar.OnFindingsOpen :=
    procedure
    begin
      Inc(Opened);
    end;
  FBar.OnMethod :=
    procedure
    begin
      Inc(MethodHit);
    end;
  FBar.SetView(Sample);
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Status));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(FBar.ClientToScreen(FBar.PartRect(TAtlasStatusBarPart.Status).TopLeft).X, StatusAt.X,
    'Statusfenster an der Leiste');
  P := Middle(FBar.KindRect(TAtlasFindingKind.Warning));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(1, KindHit);
  Assert.IsTrue(Kind = TAtlasFindingKind.Warning, 'Warnung');
  P := Middle(FBar.KindRect(TAtlasFindingKind.Error));
  FBar.DoubleClickAt(P.X, P.Y);
  Assert.AreEqual(1, Opened, 'Doppelklick öffnet „Atlas-Prüfung“');
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Method));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(1, MethodHit);
  // Ohne Methode am Cursor springt nichts.
  View := Sample;
  View.MethodFound := False;
  View.MethodName := 'keine Methode';
  FBar.SetView(View);
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.Method));
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(1, MethodHit, 'keine Methode');
  P := Middle(FBar.PartRect(TAtlasStatusBarPart.LiveCheck));
  FBar.DoubleClickAt(P.X, P.Y);
  Assert.AreEqual(1, Opened, 'nur auf den Zählern');
  // Klick auf die Live-Prüfung prüft alle Units neu (#1231).
  FBar.ClickAt(P.X, P.Y);
  Assert.AreEqual(1, Rechecked, 'Live-Prüfung');
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
  View.Items := TArray<string>.Create(TAtlasStatusBarItems.Status, TAtlasStatusBarItems.Method);
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
  Assert.AreEqual(TAtlasStatusBarItems.Findings, Toggled);
  Menu.Items[5].Click;
  Assert.IsTrue(Hidden, 'ausblenden');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasEditorStatusBarTests);

end.
