unit Atlas.Core.Status.FieldFlow.Tests;

// Tests für den Ablauf des Atlas-Felds gegen die Fälschung der Statuszeilen:
// Aktualisierung auf Anforderung, Zusatzfelder mit und ohne Atlas-Panel,
// leeres Panel (Leisten aushängen), Umzug in die Atlas-Statusleiste,
// Plakette, Klicks, Schnellschalter, Statusfenster und Abmelden.

interface

uses
  System.SysUtils,
  System.Types,
  DUnitX.TestFramework,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Contract,
  Atlas.Core.Status.FieldFlow,
  Atlas.Tests.StatusFieldSurfaceFake;

type
  [TestFixture]
  TAtlasStatusFieldFlowTests = class
  private
    FRegistry: IAtlasStatusRegistry;
    FFake: TAtlasStatusFieldSurfaceFake;
    FSurface: IAtlasStatusFieldSurface;
    FSettings: TAtlasPluginSettings;
    FFlow: TAtlasStatusFieldFlow;
    FLog: string;
    /// <summary>Feld neu anlegen (nach geänderten Einstellungen nicht nötig, sie werden je Aufruf gelesen).</summary>
    procedure CreateFlow;
    /// <summary>Rückruf, der ALabel mit dem Punkt ins Protokoll schreibt.</summary>
    function Logger(const ALabel: string): TProc<TPoint>;
    /// <summary>Atlas-Feld in der Statuszeile, Atlas-Statusleiste aus.</summary>
    procedure InStatusLine;
    /// <summary>Atlas-Statusleiste zeigt das Element status.</summary>
    procedure InStatusBar;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure CreateAttachesAndAsksForRefresh;
    [Test]
    procedure RegistryChangeAsksForRefresh;
    [Test]
    procedure RefreshShowsTextStateAndTooltip;
    [Test]
    procedure RefreshRunsOnRefreshFirst;
    [Test]
    procedure ExtrasFollowFieldInStatusLine;
    [Test]
    procedure ExtraWithEmptyTextIsRemoved;
    [Test]
    procedure ExtrasStayWithoutAtlasPanel;
    [Test]
    procedure EmptyStatusLineUnhooks;
    [Test]
    procedure RelocatedMovesFieldAndExtras;
    [Test]
    procedure BadgeChangesOnlyWhenDifferent;
    [Test]
    procedure BadgeNamedInTooltipAndView;
    [Test]
    procedure ClickOnBadgeClosesWindowAndOpensList;
    [Test]
    procedure ClickOnFieldTogglesWindow;
    [Test]
    procedure ClickOnExtraUsesItsCorner;
    [Test]
    procedure ClickOutsideIsNotOurs;
    [Test]
    procedure HintsPerZone;
    [Test]
    procedure TogglesNeedContextHandler;
    [Test]
    procedure ContextClosesWindowFirst;
    [Test]
    procedure ExtraItemsAndClickExtra;
    [Test]
    procedure AnchorFromSurfaceOrRelocatedBar;
    [Test]
    procedure FailingClickIsGuarded;
    [Test]
    procedure DestroyDetachesAndStopsListening;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Status.Registry;

{ TAtlasStatusFieldFlowTests }

procedure TAtlasStatusFieldFlowTests.Setup;
begin
  FRegistry := TAtlasStatusRegistry.Create;
  FFake := TAtlasStatusFieldSurfaceFake.Create;
  FSurface := FFake;
  FSettings := TAtlasPluginSettings.Defaults;
  InStatusLine;
  FLog := '';
  CreateFlow;
end;

procedure TAtlasStatusFieldFlowTests.TearDown;
begin
  FreeAndNil(FFlow);
  FFake := nil;
  FSurface := nil;
  FRegistry := nil;
  FSettings := Default(TAtlasPluginSettings);
  FLog := '';
end;

procedure TAtlasStatusFieldFlowTests.CreateFlow;
var
  mOwner: TAtlasStatusFieldFlowTests;
begin
  FreeAndNil(FFlow);
  mOwner := Self;
  FFlow := TAtlasStatusFieldFlow.Create(FRegistry, FSurface,
    function: TAtlasPluginSettings
    begin
      Result := mOwner.FSettings;
    end);
end;

function TAtlasStatusFieldFlowTests.Logger(const ALabel: string): TProc<TPoint>;
var
  mOwner: TAtlasStatusFieldFlowTests;
  mLabel: string;
begin
  mOwner := Self;
  mLabel := ALabel;
  Result :=
    procedure(APoint: TPoint)
    begin
      mOwner.FLog := mOwner.FLog + Format('%s@%d,%d;', [mLabel, APoint.X, APoint.Y]);
    end;
end;

procedure TAtlasStatusFieldFlowTests.InStatusLine;
begin
  FSettings.StatusField := True;
  FSettings.EditorStatusBar := False;
end;

procedure TAtlasStatusFieldFlowTests.InStatusBar;
begin
  FSettings.StatusField := True;
  FSettings.EditorStatusBar := True;
  FSettings.EditorStatusBarItems := 'status,method';
end;

procedure TAtlasStatusFieldFlowTests.CreateAttachesAndAsksForRefresh;
begin
  Assert.AreEqual('attach', FFake.CallText);
  Assert.IsTrue(FFake.Attached);
  Assert.IsTrue(FFake.Ticks > 0, 'Erstes Zeichnen angefordert');
  FFake.Tick;
  Assert.AreEqual('attach,show', FFake.CallText);
  Assert.IsTrue(FFake.View.Panel);
end;

procedure TAtlasStatusFieldFlowTests.RegistryChangeAsksForRefresh;
var
  mLine: TAtlasStatusLine;
  mItem: IAtlasStatusItem;
begin
  FFake.Tick;
  Assert.AreEqual(0, FFake.Ticks);
  mLine := TAtlasStatusLine.Create(FRegistry, 'atlas.server', 0);
  mItem := mLine;
  FRegistry.Add(mItem);
  mLine.Update('Server läuft nicht', TAtlasStatusState.Red, 'Server aus');
  Assert.IsTrue(FFake.Ticks > 0, 'Änderung der Registry fordert an');
  FFake.Tick;
  Assert.AreEqual(Integer(TAtlasStatusState.Red), Integer(FFake.View.State));
  mLine.Detach;
end;

procedure TAtlasStatusFieldFlowTests.RefreshShowsTextStateAndTooltip;
var
  mLine: TAtlasStatusLine;
  mItem: IAtlasStatusItem;
begin
  mLine := TAtlasStatusLine.Create(FRegistry, 'atlas.server', 0);
  mItem := mLine;
  FRegistry.Add(mItem);
  mLine.Update('Server langsam', TAtlasStatusState.Yellow, 'Server langsam');
  FFlow.Refresh;
  Assert.AreEqual('Atlas · Server langsam', FFlow.Text);
  Assert.AreEqual(Integer(TAtlasStatusState.Yellow), Integer(FFlow.State));
  Assert.IsTrue(Pos('Server langsam', FFlow.Tooltip) > 0, FFlow.Tooltip);
  Assert.AreEqual(FFlow.Text, FFake.View.Text);
  Assert.AreEqual(Integer(TAtlasStatusState.Yellow), Integer(FFake.View.State));
  mLine.Detach;
end;

procedure TAtlasStatusFieldFlowTests.RefreshRunsOnRefreshFirst;
var
  mOwner: TAtlasStatusFieldFlowTests;
begin
  mOwner := Self;
  FFlow.OnRefresh :=
    procedure
    begin
      mOwner.FLog := mOwner.FLog + 'refresh(' + mOwner.FFake.CallText + ');';
    end;
  FFlow.Refresh;
  Assert.AreEqual('refresh(attach);', FLog);
  Assert.AreEqual('attach,show', FFake.CallText);
end;

procedure TAtlasStatusFieldFlowTests.ExtrasFollowFieldInStatusLine;
begin
  FFlow.SetExtra(TAtlasStatusExtra.Make('profile', 'Profil: Debug', 'Startprofil', nil));
  FFlow.SetExtra(TAtlasStatusExtra.Make('problems', '1 Fehler', 'Probleme', nil));
  FFlow.SetExtra(TAtlasStatusExtra.Make('profile', 'Profil: Release', 'Startprofil', nil));
  Assert.IsTrue(FFake.Ticks > 0);
  FFake.Tick;
  Assert.IsTrue(FFake.View.Panel);
  Assert.AreEqual(2, Integer(Length(FFake.View.Extras)));
  Assert.AreEqual('Profil: Release', FFake.View.Extras[0], 'Ersetzt an seiner Stelle');
  Assert.AreEqual('1 Fehler', FFake.View.Extras[1]);
end;

procedure TAtlasStatusFieldFlowTests.ExtraWithEmptyTextIsRemoved;
begin
  FFlow.SetExtra(TAtlasStatusExtra.Make('a', 'A', '', nil));
  FFlow.SetExtra(TAtlasStatusExtra.Make('b', 'B', '', nil));
  FFlow.SetExtra(TAtlasStatusExtra.Make('a', '', '', nil));
  FFlow.SetExtra(TAtlasStatusExtra.Make('unbekannt', '', '', nil));
  FFlow.Refresh;
  Assert.AreEqual(1, Integer(Length(FFake.View.Extras)));
  Assert.AreEqual('B', FFake.View.Extras[0]);
end;

procedure TAtlasStatusFieldFlowTests.ExtrasStayWithoutAtlasPanel;
begin
  FSettings.StatusField := False;
  FFlow.SetExtra(TAtlasStatusExtra.Make('profile', 'Profil: Debug', '', nil));
  FFlow.Refresh;
  Assert.AreEqual('attach,show', FFake.CallText, 'Leisten bleiben für das Zusatzfeld eingehängt');
  Assert.IsFalse(FFake.View.Panel, 'Kein Atlas-Panel');
  Assert.AreEqual(1, Integer(Length(FFake.View.Extras)));
end;

procedure TAtlasStatusFieldFlowTests.EmptyStatusLineUnhooks;
begin
  FFlow.Refresh;
  FSettings.StatusField := False;
  FFlow.Refresh;
  Assert.AreEqual('attach,show,unhook', FFake.CallText, 'Ohne Panel und Zusatzfelder aushängen');
end;

procedure TAtlasStatusFieldFlowTests.RelocatedMovesFieldAndExtras;
begin
  InStatusBar;
  FFlow.SetExtra(TAtlasStatusExtra.Make('assistant', 'KI-Assistent', '', nil));
  Assert.IsTrue(FFlow.Relocated);
  FFlow.Refresh;
  Assert.AreEqual('attach,unhook', FFake.CallText, 'Feld und Zusatzfelder stehen in der Atlas-Statusleiste');
  Assert.AreEqual(1, Integer(Length(FFlow.ExtraItems)), 'Die Leiste liest sie über ExtraItems');
  // Element status abgewählt: zurück in die Statuszeile.
  FSettings.EditorStatusBarItems := 'method';
  Assert.IsFalse(FFlow.Relocated);
  FFlow.Refresh;
  Assert.AreEqual('attach,unhook,show', FFake.CallText);
  Assert.IsTrue(FFake.View.Panel);
  Assert.AreEqual(1, Integer(Length(FFake.View.Extras)));
end;

procedure TAtlasStatusFieldFlowTests.BadgeChangesOnlyWhenDifferent;
var
  mBadge: TAtlasStatusBadge;
begin
  FFake.Tick;
  mBadge := Default(TAtlasStatusBadge);
  mBadge.Shown := True;
  mBadge.Count := 3;
  mBadge.State := TAtlasStatusState.Red;
  mBadge.Hint := '3 neue';
  FFlow.SetBadge(mBadge);
  Assert.AreEqual(1, FFake.Ticks);
  FFake.Tick;
  FFlow.SetBadge(mBadge);
  Assert.AreEqual(0, FFake.Ticks, 'Unverändert: nicht neu zeichnen');
  mBadge.Count := -5;
  FFlow.SetBadge(mBadge);
  Assert.AreEqual(0, Integer(FFlow.Badge.Count), 'Negativ zählt als 0');
  Assert.AreEqual(1, FFake.Ticks);
end;

procedure TAtlasStatusFieldFlowTests.BadgeNamedInTooltipAndView;
var
  mBadge: TAtlasStatusBadge;
begin
  mBadge := Default(TAtlasStatusBadge);
  mBadge.Shown := True;
  mBadge.Count := 4;
  mBadge.State := TAtlasStatusState.Yellow;
  mBadge.Hint := '4 neue Benachrichtigungen';
  FFlow.SetBadge(mBadge);
  FFlow.Refresh;
  Assert.IsTrue(Pos('4 neue Benachrichtigungen', FFlow.Tooltip) > 0, FFlow.Tooltip);
  Assert.AreEqual(4, FFake.View.BadgeCount);
  Assert.AreEqual(Integer(TAtlasStatusState.Yellow), Integer(FFake.View.BadgeState));
end;

procedure TAtlasStatusFieldFlowTests.ClickOnBadgeClosesWindowAndOpensList;
var
  mBadge: TAtlasStatusBadge;
begin
  FFlow.OpenWindowAt(Point(1, 2));
  mBadge := Default(TAtlasStatusBadge);
  mBadge.Shown := True;
  mBadge.Count := 2;
  mBadge.OnClick := Logger('liste');
  FFlow.SetBadge(mBadge);
  Assert.IsTrue(FFake.Click(0, 90, 80));
  Assert.AreEqual('liste@10,20;', FLog, 'Liste an der Oberkante des Felds');
  Assert.IsFalse(FFake.WindowOpen, 'Statusfenster geschlossen');
  // Links der Plakette gilt das Feld.
  FLog := '';
  Assert.IsTrue(FFake.Click(0, 50, 80));
  Assert.AreEqual('', FLog);
  Assert.IsTrue(FFake.WindowOpen);
end;

procedure TAtlasStatusFieldFlowTests.ClickOnFieldTogglesWindow;
var
  mOwner: TAtlasStatusFieldFlowTests;
  mOpenLog: TProc;
begin
  mOwner := Self;
  FFlow.OnOpenLog :=
    procedure
    begin
      mOwner.FLog := 'log';
    end;
  Assert.IsTrue(FFake.Click(0, 5, 0));
  Assert.IsTrue(FFake.WindowOpen);
  Assert.AreEqual(10, FFake.WindowAt.X);
  Assert.AreEqual(20, FFake.WindowAt.Y);
  mOpenLog := FFake.OnOpenLog;
  Assert.IsTrue(Assigned(mOpenLog));
  mOpenLog();
  Assert.AreEqual('log', FLog);
  Assert.IsTrue(FFake.Click(0, 5, 0));
  Assert.IsFalse(FFake.WindowOpen, 'Zweiter Klick schließt');
  Assert.AreEqual('attach,show,open,close', FFake.CallText, 'Vor dem Öffnen frisch bestimmt');
end;

procedure TAtlasStatusFieldFlowTests.ClickOnExtraUsesItsCorner;
begin
  FFlow.SetExtra(TAtlasStatusExtra.Make('a', 'A', '', Logger('a')));
  FFlow.SetExtra(TAtlasStatusExtra.Make('b', 'B', '', nil));
  Assert.IsTrue(FFake.Click(1, 0, 0));
  Assert.AreEqual('a@30,20;', FLog);
  Assert.IsTrue(FFake.Click(2, 0, 0), 'Zusatzfeld ohne Klick bleibt unseres');
  Assert.AreEqual('a@30,20;', FLog);
end;

procedure TAtlasStatusFieldFlowTests.ClickOutsideIsNotOurs;
begin
  Assert.IsFalse(FFake.Click(-1, 0, 0));
  Assert.IsFalse(FFake.Click(1, 0, 0), 'Kein Zusatzfeld');
  Assert.IsFalse(FFake.WindowOpen);
end;

procedure TAtlasStatusFieldFlowTests.HintsPerZone;
begin
  FFlow.SetExtra(TAtlasStatusExtra.Make('a', 'A', 'Tooltip A', nil));
  FFlow.Refresh;
  Assert.AreEqual(FFlow.Tooltip, FFake.Hint(0));
  Assert.AreEqual('Tooltip A', FFake.Hint(1));
  Assert.AreEqual('', FFake.Hint(2));
  Assert.AreEqual('', FFake.Hint(-1));
end;

procedure TAtlasStatusFieldFlowTests.TogglesNeedContextHandler;
begin
  Assert.IsFalse(FFake.Gesture(TAtlasStatusFieldGesture.RightButton, True, False), 'Ohne Schnellschalter');
  FFlow.OnContext := Logger('toggles');
  Assert.IsTrue(FFake.Gesture(TAtlasStatusFieldGesture.RightButton, True, False));
  Assert.IsFalse(FFake.Gesture(TAtlasStatusFieldGesture.RightButton, False, False), 'Nicht über dem Feld');
  Assert.IsFalse(FFake.Gesture(TAtlasStatusFieldGesture.ContextMenu, True, True), 'Tastatur bleibt bei der IDE');
end;

procedure TAtlasStatusFieldFlowTests.ContextClosesWindowFirst;
begin
  FFlow.OpenWindowAt(Point(1, 2));
  FFake.Context(Point(7, 8));
  Assert.IsTrue(FFake.WindowOpen, 'Ohne Schnellschalter bleibt alles');
  FFlow.OnContext := Logger('toggles');
  FFake.Context(Point(7, 8));
  Assert.IsFalse(FFake.WindowOpen);
  Assert.AreEqual('toggles@7,8;', FLog);
end;

procedure TAtlasStatusFieldFlowTests.ExtraItemsAndClickExtra;
var
  mExtra: TAtlasStatusExtra;
  mItems: TArray<TAtlasStatusExtraItem>;
begin
  mExtra := TAtlasStatusExtra.Make('a', 'A', 'Tipp', Logger('links'));
  mExtra.State := TAtlasStatusState.Green;
  mExtra.OnContext := Logger('rechts');
  FFlow.SetExtra(mExtra);
  FFlow.SetExtra(TAtlasStatusExtra.Make('b', 'B', '', nil));
  mItems := FFlow.ExtraItems;
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('a', mItems[0].Id);
  Assert.AreEqual('Tipp', mItems[0].Hint);
  Assert.IsTrue(mItems[0].Clickable);
  Assert.IsTrue(mItems[0].HasContext);
  Assert.AreEqual(Integer(TAtlasStatusState.Green), Integer(mItems[0].State));
  Assert.IsFalse(mItems[1].Clickable);
  Assert.IsFalse(mItems[1].HasContext);
  FFlow.ClickExtra('a', Point(1, 1), False);
  FFlow.ClickExtra('a', Point(2, 2), True);
  FFlow.ClickExtra('b', Point(3, 3), True);
  FFlow.ClickExtra('fehlt', Point(4, 4), False);
  Assert.AreEqual('links@1,1;rechts@2,2;', FLog);
  mItems := nil;
end;

procedure TAtlasStatusFieldFlowTests.AnchorFromSurfaceOrRelocatedBar;
var
  mPoint: TPoint;
begin
  Assert.IsFalse(FFlow.Anchor(mPoint), 'Ohne Feld');
  FFake.HasCorner := True;
  FFake.Corner := Point(100, 200);
  Assert.IsTrue(FFlow.Anchor(mPoint));
  Assert.AreEqual(100, mPoint.X);
  InStatusBar;
  Assert.IsFalse(FFlow.Anchor(mPoint), 'Umgezogen ohne Element der Leiste');
  FFlow.OnRelocatedAnchor :=
    function(out APoint: TPoint): Boolean
    begin
      APoint := Point(5, 6);
      Result := True;
    end;
  Assert.IsTrue(FFlow.Anchor(mPoint));
  Assert.AreEqual(5, mPoint.X);
  Assert.AreEqual(6, mPoint.Y);
end;

procedure TAtlasStatusFieldFlowTests.FailingClickIsGuarded;
begin
  FFlow.SetExtra(TAtlasStatusExtra.Make('a', 'A', '',
    procedure(APoint: TPoint)
    begin
      raise EArgumentException.Create('Absicht');
    end));
  Assert.WillNotRaise(
    procedure
    begin
      FFake.Click(1, 0, 0);
    end);
  // Die gemeinsame Sicherung hat den Fehler gezählt (Schlüssel und Zeitstempel); zurücksetzen, sonst bleibt das
  // bis Programmende stehen und der Leckmonitor zählt es diesem Test zu.
  TAtlasGuard.Fuse.ResetAll;
end;

procedure TAtlasStatusFieldFlowTests.DestroyDetachesAndStopsListening;
var
  mLine: TAtlasStatusLine;
  mItem: IAtlasStatusItem;
begin
  FFake.Tick;
  FreeAndNil(FFlow);
  Assert.AreEqual('attach,show,detach', FFake.CallText);
  Assert.IsFalse(FFake.Attached, 'Nach dem Abmelden erreicht nichts mehr das Feld');
  mLine := TAtlasStatusLine.Create(FRegistry, 'atlas.server', 0);
  mItem := mLine;
  FRegistry.Add(mItem);
  mLine.Update('x', TAtlasStatusState.Red);
  Assert.AreEqual(0, FFake.Ticks, 'Kein Beobachter mehr');
  mLine.Detach;
end;

end.
