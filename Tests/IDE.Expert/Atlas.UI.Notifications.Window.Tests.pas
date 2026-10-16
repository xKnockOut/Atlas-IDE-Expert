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
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Vcl.Forms,
  Vcl.Menus,
  Atlas.Core.Style.Palette,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Sources,
  Atlas.UI.Strings,
  Atlas.UI.Notifications.Window;

function SampleCenter: IAtlasNotificationCenter;
begin
  Result := TAtlasNotificationCenter.Create;
  Result.Notify(TAtlasNotificationSources.Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Result.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler',
    'Projekt1: 2 Fehler', [TAtlasNotificationCenter.Action('Zum Fehler', nil)]);
  Result.Notify(TAtlasNotificationSources.Server, TAtlasNotificationSeverity.Warning, 'Meldung des Servers', 'x');
end;

procedure TAtlasNotificationsWindowTests.WarmUpFirstUse;
begin
  ListsNewestFirstAndFilters;
end;

procedure TAtlasNotificationsWindowTests.ListsNewestFirstAndFilters;
var
  Window: TAtlasNotificationsWindow;
  Center: IAtlasNotificationCenter;
begin
  Center := SampleCenter;
  Window := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, Center);
  try
    Assert.AreEqual(3, Window.RowCount);
    Assert.AreEqual('Meldung des Servers', Window.Row(0).Title);
    Assert.AreEqual('Server neu gestartet', Window.Row(2).Title);
    // „Alle Quellen“ und die beiden Quellen in der Reihenfolge der Liste.
    Assert.AreEqual(3, Window.FilterBox.Items.Count);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsFilterAll), Window.FilterBox.Items[0]);
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsSourceServer), Window.FilterBox.Items[1]);
    Window.SetFilter(TAtlasNotificationSources.Build);
    Assert.AreEqual(1, Window.RowCount);
    Assert.AreEqual(2, Window.FilterBox.ItemIndex);
    // Gewählte Quelle bleibt im Filter, auch wenn sie keine Einträge mehr hat.
    Center.Clear;
    Window.Reload;
    Assert.AreEqual(0, Window.RowCount);
    Assert.AreEqual(2, Window.FilterBox.Items.Count);
    Assert.AreEqual(1, Window.FilterBox.ItemIndex);
    Window.SetFilter('');
    Assert.AreEqual(0, Window.FilterBox.ItemIndex);
  finally
    Window.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ClickMarksRead;
var
  Window: TAtlasNotificationsWindow;
  Center: IAtlasNotificationCenter;
begin
  Center := SampleCenter;
  Window := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Dark, Center);
  try
    Assert.AreEqual(3, Center.UnreadCount);
    Window.ClickRow(1);
    Assert.AreEqual(2, Center.UnreadCount);
    Assert.IsTrue(Window.Row(1).Read);
    Assert.AreEqual(1, Window.Selected);
    Assert.IsTrue(Window.AllReadButton.Enabled);
  finally
    Window.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ActionRunsAfterClosing;
var
  Window: TAtlasNotificationsWindow;
  Center: IAtlasNotificationCenter;
  Count: Integer;
begin
  Count := 0;
  Center := TAtlasNotificationCenter.Create;
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler', '',
    [TAtlasNotificationCenter.Action('Zum Fehler',
    procedure
    begin
      Inc(Count);
    end)]);
  Window := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, Center);
  try
    Window.ClickAction(0, 0);
    Assert.AreEqual(0, Count, 'erst nach dem Schließen');
    // Schließt schon: weitere Klicks tun nichts.
    Window.ClickAction(0, 0);
    CheckSynchronize;
    Application.ProcessMessages;
    Assert.AreEqual(1, Count);
    Assert.AreEqual(0, Center.UnreadCount, 'die Aktion markiert als gelesen');
  finally
    Application.ProcessMessages;
  end;
end;

procedure TAtlasNotificationsWindowTests.MenuSetsModeOfSource;
var
  Window: TAtlasNotificationsWindow;
  Center: IAtlasNotificationCenter;
  Menu: TPopupMenu;
  Changed: string;
  ChangedMode: TAtlasNotificationMode;
begin
  Center := SampleCenter;
  Changed := '';
  ChangedMode := TAtlasNotificationMode.Show;
  Window := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, Center);
  try
    Window.OnModeChange :=
      procedure(const ASource: string; AMode: TAtlasNotificationMode)
      begin
        Changed := ASource;
        ChangedMode := AMode;
      end;
    Menu := Window.BuildMenu(0);
    // Gelesen, Trennlinie, Überschrift, drei Verhalten.
    Assert.AreEqual(6, Menu.Items.Count);
    Assert.IsTrue(Menu.Items[0].Enabled);
    Assert.IsFalse(Menu.Items[2].Enabled, 'Überschrift');
    Assert.IsTrue(Menu.Items[3].Checked, 'Vorgabe: einblenden');
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsModeCollect), Menu.Items[4].Caption);
    Menu.Items[4].Click;
    Assert.AreEqual(TAtlasNotificationSources.Server, Changed);
    Assert.IsTrue(ChangedMode = TAtlasNotificationMode.Collect);
    Assert.IsTrue(Center.ModeOf(TAtlasNotificationSources.Server) = TAtlasNotificationMode.Collect);
    Menu := Window.BuildMenu(0);
    Assert.IsTrue(Menu.Items[4].Checked);
    Menu.Items[0].Click;
    Assert.IsTrue(Window.Row(0).Read);
  finally
    Window.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.ButtonsMarkAllReadAndClear;
var
  Window: TAtlasNotificationsWindow;
  Center: IAtlasNotificationCenter;
begin
  Center := SampleCenter;
  Window := TAtlasNotificationsWindow.CreateList(nil, TAtlasColors.Light, Center);
  try
    Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsAllRead), Window.AllReadButton.Caption);
    Window.AllReadButton.Click;
    Assert.AreEqual(0, Center.UnreadCount);
    Assert.IsFalse(Window.AllReadButton.Enabled);
    Assert.AreEqual(3, Window.RowCount, 'gelesen bleiben sie in der Liste');
    Window.ClearButton.Click;
    Assert.AreEqual(0, Window.RowCount);
    Assert.AreEqual(0, Integer(Length(Center.Items())));
    Assert.IsFalse(Window.ClearButton.Enabled);
  finally
    Window.Free;
  end;
end;

procedure TAtlasNotificationsWindowTests.CaptionsAndTimes;
var
  Day: TDateTime;
begin
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsSourceShortcutTips),
    TAtlasNotificationsWindow.SourceCaption('ShortcutTips'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsSourceBuildServer),
    TAtlasNotificationsWindow.SourceCaption('buildServer'));
  Assert.AreEqual(TAtlasStrings.Text(TAtlasTextId.NotificationsSourceOpenBuild),
    TAtlasNotificationsWindow.SourceCaption('openBuild'));
  Assert.AreEqual('tracker', TAtlasNotificationsWindow.SourceCaption('tracker'), 'unbekannt: Kennung');
  Day := EncodeDateTime(2026, 10, 16, 14, 3, 0, 0);
  Assert.AreEqual('14:03', TAtlasNotificationsWindow.TimeText(Day, IncHour(Day, 2)));
  Assert.AreEqual('16.10. 14:03', TAtlasNotificationsWindow.TimeText(Day, IncDay(Day)));
  Assert.IsTrue(TAtlasNotificationsWindow.SeverityColor(TAtlasColors.Light, TAtlasNotificationSeverity.Error) =
    TAtlasColors.Light.Error);
  Assert.IsTrue(TAtlasNotificationsWindow.SeverityColor(TAtlasColors.Light, TAtlasNotificationSeverity.Info) =
    TAtlasColors.Light.Accent);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationsWindowTests);

end.
