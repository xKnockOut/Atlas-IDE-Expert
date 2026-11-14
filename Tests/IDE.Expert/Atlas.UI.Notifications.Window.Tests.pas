unit Atlas.UI.Notifications.Window.Tests;

// Liste der Benachrichtigungszentrale (#601): neueste zuerst, Filter nach
// Quelle, Klick markiert als gelesen, Aktion erst nach dem Schließen,
// Kontextmenü mit dem Verhalten der Quelle, „Alle gelesen“ und „Liste leeren“.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasNotificationsWindowTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure ListsNewestFirstAndFilters;
    [Test]
    procedure ClickMarksRead;
    [Test]
    procedure ActionRunsAfterClosing;
    [Test]
    procedure MenuSetsModeOfSource;
    [Test]
    procedure ButtonsMarkAllReadAndClear;
    [Test]
    procedure CaptionsAndTimes;
    [Test]
    procedure SeveritySignalIsStatusBarSignal;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Status.Contract,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Notifications.Strings,
  Atlas.UI.Notifications.Window;

function SampleCenter: IAtlasNotificationCenter;
begin
  Result := TAtlasNotificationCenter.Create;
  Result.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Result.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler',
    'Projekt1: 2 Fehler', [TAtlasNotificationCenter.Action('Zum Fehler', nil)]);
  Result.Notify(TAtlasNotificationSources.cServer, TAtlasNotificationSeverity.Warning, 'Meldung des Servers', 'x');
end;

procedure TAtlasNotificationsWindowTests.WarmUpFirstUse;
begin
  ListsNewestFirstAndFilters;
end;

procedure TAtlasNotificationsWindowTests.ListsNewestFirstAndFilters;
var
  mWindow: TAtlasNotificationsWindow;
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := SampleCenter;
  mWindow := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, mCenter);
  try
    Assert.AreEqual(3, Integer(Length(mWindow.Rows)));
    Assert.AreEqual('Meldung des Servers', mWindow.Rows[0].Title);
    Assert.AreEqual('Server neu gestartet', mWindow.Rows[2].Title);
    // „Alle Quellen“ und die beiden Quellen in der Reihenfolge der Liste.
    Assert.AreEqual(3, Integer(mWindow.FilterBox.Items.Count));
    Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsFilterAll),
      mWindow.FilterBox.Items[0]);
    Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceServer),
      mWindow.FilterBox.Items[1]);
    mWindow.SetFilter(TAtlasNotificationSources.cBuild);
    Assert.AreEqual(1, Integer(Length(mWindow.Rows)));
    Assert.AreEqual(2, mWindow.FilterBox.ItemIndex);
    // Gewählte Quelle bleibt im Filter, auch wenn sie keine Einträge mehr hat.
    mCenter.Clear;
    mWindow.Reload;
    Assert.AreEqual(0, Integer(Length(mWindow.Rows)));
    Assert.AreEqual(2, Integer(mWindow.FilterBox.Items.Count));
    Assert.AreEqual(1, mWindow.FilterBox.ItemIndex);
    mWindow.SetFilter('');
    Assert.AreEqual(0, mWindow.FilterBox.ItemIndex);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ClickMarksRead;
var
  mWindow: TAtlasNotificationsWindow;
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := SampleCenter;
  mWindow := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Dark, mCenter);
  try
    Assert.AreEqual(3, mCenter.UnreadCount);
    mWindow.ClickRow(1);
    Assert.AreEqual(2, mCenter.UnreadCount);
    Assert.IsTrue(mWindow.Rows[1].Read);
    Assert.AreEqual(1, mWindow.Selected);
    Assert.IsTrue(mWindow.AllReadButton.Enabled);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ActionRunsAfterClosing;
var
  mWindow: TAtlasNotificationsWindow;
  mCenter: IAtlasNotificationCenter;
  mCount: Integer;
begin
  mCount := 0;
  mCenter := TAtlasNotificationCenter.Create;
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler', '',
    [TAtlasNotificationCenter.Action('Zum Fehler',
    procedure
    begin
      Inc(mCount);
    end)]);
  mWindow := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, mCenter);
  try
    mWindow.ClickAction(0, 0);
    Assert.AreEqual(0, mCount, 'erst nach dem Schließen');
    // Schließt schon: weitere Klicks tun nichts.
    mWindow.ClickAction(0, 0);
    CheckSynchronize;
    Application.ProcessMessages;
    Assert.AreEqual(1, mCount);
    Assert.AreEqual(0, mCenter.UnreadCount, 'die Aktion markiert als gelesen');
  finally
    Application.ProcessMessages;
  end;
end;

procedure TAtlasNotificationsWindowTests.MenuSetsModeOfSource;
var
  mWindow: TAtlasNotificationsWindow;
  mCenter: IAtlasNotificationCenter;
  mMenu: TPopupMenu;
  mChanged: string;
  mChangedMode: TAtlasNotificationMode;
begin
  mCenter := SampleCenter;
  mChanged := '';
  mChangedMode := TAtlasNotificationMode.Show;
  mWindow := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, mCenter);
  try
    mWindow.OnModeChange :=
      procedure(const ASource: string; AMode: TAtlasNotificationMode)
      begin
        mChanged := ASource;
        mChangedMode := AMode;
      end;
    mMenu := mWindow.BuildMenu(0);
    // Gelesen, Trennlinie, Überschrift, drei Verhalten.
    Assert.AreEqual(6, Integer(mMenu.Items.Count));
    Assert.IsTrue(mMenu.Items[0].Enabled);
    Assert.IsFalse(mMenu.Items[2].Enabled, 'Überschrift');
    Assert.IsTrue(mMenu.Items[3].Checked, 'Vorgabe: einblenden');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsModeCollect), mMenu.Items[4].Caption);
    mMenu.Items[4].Click;
    Assert.AreEqual(TAtlasNotificationSources.cServer, mChanged);
    Assert.AreEqual<TAtlasNotificationMode>(TAtlasNotificationMode.Collect, mChangedMode);
    Assert.AreEqual<TAtlasNotificationMode>(TAtlasNotificationMode.Collect,
      mCenter.ModeOf(TAtlasNotificationSources.cServer));
    mMenu := mWindow.BuildMenu(0);
    Assert.IsTrue(mMenu.Items[4].Checked);
    mMenu.Items[0].Click;
    Assert.IsTrue(mWindow.Rows[0].Read);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ButtonsMarkAllReadAndClear;
var
  mWindow: TAtlasNotificationsWindow;
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := SampleCenter;
  mWindow := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, mCenter);
  try
    Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsAllRead),
      mWindow.AllReadButton.Caption);
    mWindow.AllReadButton.Click;
    Assert.AreEqual(0, mCenter.UnreadCount);
    Assert.IsFalse(mWindow.AllReadButton.Enabled);
    Assert.AreEqual(3, Integer(Length(mWindow.Rows)), 'gelesen bleiben sie in der Liste');
    mWindow.ClearButton.Click;
    Assert.AreEqual(0, Integer(Length(mWindow.Rows)));
    Assert.AreEqual(0, Integer(Length(mCenter.Items())));
    Assert.IsFalse(mWindow.ClearButton.Enabled);
  finally
    mWindow.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.CaptionsAndTimes;
var
  mDay: TDateTime;
begin
  Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceShortcutTips),
    TAtlasNotificationTexts.SourceCaption('ShortcutTips'));
  Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceBuildServer),
    TAtlasNotificationTexts.SourceCaption('buildServer'));
  Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceOpenBuild),
    TAtlasNotificationTexts.SourceCaption('openBuild'));
  Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceHidden),
    TAtlasNotificationTexts.SourceCaption('hidden'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.UnitRenameTitle),
    TAtlasNotificationTexts.SourceCaption('unitRename'));
  Assert.AreEqual(TAtlasNotificationsStrings.Text(TAtlasNotificationsTextId.NotificationsSourceRuleChecks),
    TAtlasNotificationTexts.SourceCaption('ruleChecks'), 'Modulschalter (#1454)');
  Assert.AreEqual('tracker', TAtlasNotificationTexts.SourceCaption('tracker'), 'unbekannt: Kennung');
  mDay := EncodeDateTime(2026, 10, 16, 14, 3, 0, 0);
  Assert.AreEqual('14:03', TAtlasNotificationTexts.TimeText(mDay, IncHour(mDay, 2)));
  Assert.AreEqual('16.10. 14:03', TAtlasNotificationTexts.TimeText(mDay, IncDay(mDay)));
end;

procedure TAtlasNotificationsWindowTests.SeveritySignalIsStatusBarSignal;
var
  mDark: TAtlasColors;
  mLight: TAtlasColors;
begin
  // Dieselben kräftigen Signalfarben wie die Plakette der Statusleiste, nicht die blassen Textfarben.
  mDark := TAtlasColors.Dark;
  mLight := TAtlasColors.Light;
  Assert.AreEqual<TAtlasColor>(mDark.Signals.ForStatus(TAtlasStatusState.Yellow).Solid,
    TAtlasNotificationTexts.SeveritySignal(mDark, TAtlasNotificationSeverity.Warning).Fill, 'Warnung dunkel');
  Assert.AreEqual<TAtlasColor>(mDark.Signals.ForStatus(TAtlasStatusState.Red).Solid,
    TAtlasNotificationTexts.SeveritySignal(mDark, TAtlasNotificationSeverity.Error).Fill, 'Fehler dunkel');
  Assert.AreNotEqual<TAtlasColor>(mDark.Warn,
    TAtlasNotificationTexts.SeveritySignal(mDark, TAtlasNotificationSeverity.Warning).Fill, 'nicht die Textfarbe');
  Assert.AreEqual<TAtlasColor>(mLight.Signals.ForStatus(TAtlasStatusState.Red).Solid,
    TAtlasNotificationTexts.SeveritySignal(mLight, TAtlasNotificationSeverity.Error).Solid, 'Fehler hell');
  Assert.AreEqual<TAtlasColor>(mLight.Signals.Get(TAtlasSignalKind.Info).Fill,
    TAtlasNotificationTexts.SeveritySignal(mLight, TAtlasNotificationSeverity.Info).Fill, 'Info');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationsWindowTests);

end.
