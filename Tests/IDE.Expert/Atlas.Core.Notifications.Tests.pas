unit Atlas.Core.Notifications.Tests;

// Tests der Benachrichtigungszentrale (#601) ohne IDE: Melden über
// IAtlasNotificationCenter, Zusammenfassen gleichartiger Hinweise innerhalb
// von 10 s, Begrenzung der Liste, Gelesen-Status, Aktionen, Verhalten je
// Quelle (einblenden und sammeln, nur sammeln, aus) samt Einstellung
// notifications.sources und die Einträge für Build und Hintergrundprüfung.

interface

uses
  DUnitX.TestFramework,
  System.SysUtils,
  Atlas.Core.Build.Messages,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Notifications.Center,
  Atlas.Core.Notifications.Build;

type
  [TestFixture]
  TAtlasNotificationCenterTests = class
  public
    [Test]
    procedure NotifyThroughInterfaceAddsUnreadEntry;
    [Test]
    procedure NewestComesFirst;
    [Test]
    procedure ThreeRestartsWithinTenSecondsMerge;
    [Test]
    procedure NoMergeAfterTenSecondsOrOtherTitle;
    [Test]
    procedure MergeKeepsWorseSeverityAndMovesUp;
    [Test]
    procedure ListKeepsAtMostMaxEntries;
    [Test]
    procedure MaxEntriesIsClampedAndShrinks;
    [Test]
    procedure ReadStateAndWorstUnread;
    [Test]
    procedure ActionMarksReadAndRuns;
    [Test]
    procedure CollectOnlyKeepsEntryButNoPopup;
    [Test]
    procedure OffCollectsNothing;
    [Test]
    procedure ApplyModesReplacesAllModes;
    [Test]
    procedure DisabledCenterBehavesLikeBefore;
    [Test]
    procedure ListenersSeeEveryChange;
    [Test]
    procedure FilterBySourceAndClear;
    [Test]
    procedure DefaultStaysOffUntilEnabled;
  private
    FNow: TDateTime;
    function NewCenter: TAtlasNotificationCenter;
    function Seconds(ACount: Integer): TDateTime;
  end;

  [TestFixture]
  TAtlasNotificationSourcesTests = class
  public
    [Test]
    procedure ParseSkipsBrokenEntries;
    [Test]
    procedure ToTextLeavesOutShow;
    [Test]
    procedure WithModeChangesOneSource;
    [Test]
    procedure KnownSourcesAndModeNames;
  end;

  [TestFixture]
  TAtlasBuildNoticeTests = class
  public
    [Test]
    procedure BuildWithErrorsTargetsFirstErrorWithFile;
    [Test]
    procedure BuildWithWarningsSucceededOrFailed;
    [Test]
    procedure BackgroundCheckOnlyOnErrorsAndRecovery;
  private
    function Msg(ASeverity: TAtlasCompilerSeverity; const AFileName: string; ALine: Integer): TAtlasCompilerMessage;
  end;

implementation

const
  Server = TAtlasNotificationSources.Server;
  Tips = TAtlasNotificationSources.ShortcutTips;

{ TAtlasNotificationCenterTests }

function TAtlasNotificationCenterTests.NewCenter: TAtlasNotificationCenter;
begin
  FNow := EncodeDate(2026, 10, 16) + EncodeTime(9, 0, 0, 0);
  Result := TAtlasNotificationCenter.Create(
    function: TDateTime
    begin
      Result := FNow;
    end);
end;

function TAtlasNotificationCenterTests.Seconds(ACount: Integer): TDateTime;
begin
  Result := ACount / SecsPerDay;
end;

procedure TAtlasNotificationCenterTests.NotifyThroughInterfaceAddsUnreadEntry;
var
  Center: IAtlasNotificationCenter;
  Entry: IAtlasNotification;
  Mode: TAtlasNotificationMode;
begin
  // Akzeptanzkriterium: melden ohne Änderung an der Oberfläche, nur über die Schnittstelle.
  Center := NewCenter;
  Mode := Center.Notify('ci', TAtlasNotificationSeverity.Error, 'Server rot', 'Jenkins #482');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Mode), 'unbekannte Quelle zeigt');
  Assert.AreEqual(1, Integer(Length(Center.Items())));
  Entry := Center.Items()[0];
  Assert.AreEqual(1, Entry.Id);
  Assert.AreEqual('ci', Entry.Source);
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(Entry.Severity));
  Assert.AreEqual('Server rot', Entry.Title);
  Assert.AreEqual('Server rot', Entry.Caption);
  Assert.AreEqual('Jenkins #482', Entry.Text);
  Assert.AreEqual(1, Integer(Entry.Count));
  Assert.IsFalse(Entry.Read);
  Assert.IsTrue(Entry.Time = FNow, 'Zeit der Meldung');
  Assert.AreEqual(1, Center.UnreadCount);
  Assert.IsTrue(Center.Find(1) <> nil);
  Assert.IsTrue(Center.Find(2) = nil);
end;

procedure TAtlasNotificationCenterTests.NewestComesFirst;
var
  Center: IAtlasNotificationCenter;
begin
  Center := NewCenter;
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Info, 'Build fertig: erfolgreich', '');
  FNow := FNow + Seconds(1);
  Center.Notify(TAtlasNotificationSources.Reload, TAtlasNotificationSeverity.Info, 'Dateien neu geladen: 2', '');
  Assert.AreEqual(2, Integer(Length(Center.Items())));
  Assert.AreEqual('Dateien neu geladen: 2', Center.Items()[0].Title);
  Assert.AreEqual('Build fertig: erfolgreich', Center.Items()[1].Title);
  Assert.AreEqual(2, Center.Items()[0].Id);
end;

procedure TAtlasNotificationCenterTests.ThreeRestartsWithinTenSecondsMerge;
var
  Center: IAtlasNotificationCenter;
  Entry: IAtlasNotification;
begin
  // Akzeptanzkriterium: drei Neustarts innerhalb von 10 s ergeben einen Eintrag „3 × Server neu gestartet“.
  Center := NewCenter;
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'erster');
  Center.MarkRead(1);
  FNow := FNow + Seconds(4);
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'zweiter');
  FNow := FNow + Seconds(9);
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'dritter');
  Assert.AreEqual(1, Integer(Length(Center.Items())), 'ein Eintrag');
  Entry := Center.Items()[0];
  Assert.AreEqual('3 × Server neu gestartet', Entry.Caption);
  Assert.AreEqual('Server neu gestartet', Entry.Title);
  Assert.AreEqual(3, Integer(Entry.Count));
  Assert.AreEqual(1, Entry.Id, 'Kennung bleibt');
  Assert.AreEqual('dritter', Entry.Text, 'neuester Text');
  Assert.IsTrue(Entry.Time = FNow, 'Zeit der letzten Meldung');
  Assert.IsFalse(Entry.Read, 'wieder ungelesen');
  Assert.AreEqual(1, Center.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.NoMergeAfterTenSecondsOrOtherTitle;
var
  Center: IAtlasNotificationCenter;
begin
  Center := NewCenter;
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  FNow := FNow + Seconds(11);
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Assert.AreEqual(2, Integer(Length(Center.Items())), 'nach mehr als 10 s ein neuer Eintrag');
  FNow := FNow + Seconds(1);
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Server: Fehler', '');
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Assert.AreEqual(4, Integer(Length(Center.Items())), 'anderer Titel bzw. andere Quelle');
  Assert.AreEqual(1, Center.Items()[3].Count);
end;

procedure TAtlasNotificationCenterTests.MergeKeepsWorseSeverityAndMovesUp;
var
  Center: IAtlasNotificationCenter;
  Actions: TArray<TAtlasNotificationAction>;
begin
  Center := NewCenter;
  Center.Notify(Server, TAtlasNotificationSeverity.Error, 'Meldung des Servers', 'a');
  FNow := FNow + Seconds(1);
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Info, 'Build fertig: erfolgreich', '');
  FNow := FNow + Seconds(1);
  Actions := [TAtlasNotificationCenter.Action('Protokoll öffnen', nil)];
  Center.Notify(Server, TAtlasNotificationSeverity.Warning, 'Meldung des Servers', 'b', Actions);
  Assert.AreEqual(2, Integer(Length(Center.Items())));
  Assert.AreEqual('2 × Meldung des Servers', Center.Items()[0].Caption, 'nach oben gerückt');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(Center.Items()[0].Severity), 'schwerere bleibt');
  Assert.AreEqual(1, Integer(Length(Center.Items()[0].Actions)), 'Aktionen der neuesten Meldung');
  Assert.AreEqual('Protokoll öffnen', Center.Items()[0].Actions[0].Caption);
end;

procedure TAtlasNotificationCenterTests.ListKeepsAtMostMaxEntries;
var
  Center: TAtlasNotificationCenter;
  Keep: IAtlasNotificationCenter;
  Index: Integer;
begin
  Center := NewCenter;
  Keep := Center;
  Assert.AreEqual(200, Center.MaxEntries, 'Vorgabe 200');
  Center.SetMaxEntries(10);
  for Index := 1 to 12 do
  begin
    FNow := FNow + Seconds(20);
    Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Eintrag ' + IntToStr(Index), '');
  end;
  Assert.AreEqual(10, Integer(Length(Center.Items())));
  Assert.AreEqual('Eintrag 12', Center.Items()[0].Title, 'neuester bleibt');
  Assert.AreEqual('Eintrag 3', Center.Items()[9].Title, 'die ältesten fallen weg');
  Assert.IsTrue(Center.Find(1) = nil);
  Assert.AreEqual(10, Center.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.MaxEntriesIsClampedAndShrinks;
var
  Center: TAtlasNotificationCenter;
  Keep: IAtlasNotificationCenter;
  Index: Integer;
begin
  Center := NewCenter;
  Keep := Center;
  Center.SetMaxEntries(3);
  Assert.AreEqual(TAtlasNotificationCenter.MinEntries, Center.MaxEntries, 'nach unten begrenzt');
  Center.SetMaxEntries(5000);
  Assert.AreEqual(TAtlasNotificationCenter.MaxMaxEntries, Center.MaxEntries, 'nach oben begrenzt');
  for Index := 1 to 15 do
    Center.Notify(Server, TAtlasNotificationSeverity.Info, 'Eintrag ' + IntToStr(Index), '');
  Center.SetMaxEntries(10);
  Assert.AreEqual(10, Integer(Length(Center.Items())), 'Verkleinern kürzt die Liste');
  Assert.AreEqual('Eintrag 15', Center.Items()[0].Title);
end;

procedure TAtlasNotificationCenterTests.ReadStateAndWorstUnread;
var
  Center: IAtlasNotificationCenter;
  Severity: TAtlasNotificationSeverity;
begin
  Center := NewCenter;
  Assert.IsFalse(Center.WorstUnread(Severity), 'leer');
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'a', '');
  Center.Notify(Server, TAtlasNotificationSeverity.Error, 'b', '');
  Center.Notify(Server, TAtlasNotificationSeverity.Warning, 'c', '');
  Assert.AreEqual(3, Center.UnreadCount);
  Assert.IsTrue(Center.WorstUnread(Severity));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(Severity));
  Center.MarkRead(2);
  Assert.IsTrue(Center.Find(2).Read);
  Assert.AreEqual(2, Center.UnreadCount);
  Assert.IsTrue(Center.WorstUnread(Severity));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Warning), Ord(Severity), 'gelesene zählen nicht');
  Center.MarkAllRead;
  Assert.AreEqual(0, Center.UnreadCount);
  Assert.IsFalse(Center.WorstUnread(Severity));
  Assert.AreEqual(3, Integer(Length(Center.Items())), 'gelesene bleiben in der Liste');
end;

procedure TAtlasNotificationCenterTests.ActionMarksReadAndRuns;
var
  Center: IAtlasNotificationCenter;
  Jumped: Integer;
  ReadWhenRun: Boolean;
begin
  // Akzeptanzkriterium: „Zum Fehler“ springt und markiert den Eintrag als gelesen.
  Center := NewCenter;
  Jumped := 0;
  ReadWhenRun := False;
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler', '',
    [TAtlasNotificationCenter.Action('Zum Fehler',
    procedure
    begin
      Inc(Jumped);
      ReadWhenRun := Center.Find(1).Read;
    end)]);
  Assert.AreEqual(1, Center.UnreadCount, 'Zähler zeigt 1');
  Assert.IsTrue(Center.RunAction(1, 0));
  Assert.AreEqual(1, Jumped);
  Assert.IsTrue(ReadWhenRun, 'vor der Aktion gelesen');
  Assert.AreEqual(0, Center.UnreadCount);
  Assert.IsFalse(Center.RunAction(1, 1), 'keine zweite Aktion');
  Assert.IsFalse(Center.RunAction(7, 0), 'kein Eintrag');
  Assert.AreEqual(1, Jumped);
  // Kein Kreis über die Referenz der Aktion auf die Zentrale.
  Center.Clear;
end;

procedure TAtlasNotificationCenterTests.CollectOnlyKeepsEntryButNoPopup;
var
  Center: IAtlasNotificationCenter;
begin
  // Akzeptanzkriterium: Tastenkürzel-Tipps auf „nur sammeln“: keine Einblendung, aber der Eintrag.
  Center := NewCenter;
  Center.SetMode(Tips, TAtlasNotificationMode.Collect);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Center.ModeOf('SHORTCUTTIPS')),
    'Quelle ohne Groß-/Kleinschreibung');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect),
    Ord(Center.Notify(Tips, TAtlasNotificationSeverity.Info, 'Tastenkürzel: Strg+Umschalt+P', 'Befehlspalette')),
    'die Quelle zeigt nichts');
  Assert.AreEqual(1, Integer(Length(Center.Items())), 'der Tipp steht in der Liste');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Center.ModeOf(Server)), 'andere Quellen zeigen');
  Center.SetMode(Tips, TAtlasNotificationMode.Show);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Center.ModeOf(Tips)));
end;

procedure TAtlasNotificationCenterTests.OffCollectsNothing;
var
  Center: IAtlasNotificationCenter;
begin
  Center := NewCenter;
  Center.SetMode(Server, TAtlasNotificationMode.Off);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Off),
    Ord(Center.Notify(Server, TAtlasNotificationSeverity.Error, 'Server: Fehler', '')));
  Assert.AreEqual(0, Integer(Length(Center.Items())), 'aus: weder Einblendung noch Eintrag');
  Assert.AreEqual(0, Center.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.ApplyModesReplacesAllModes;
var
  Center: TAtlasNotificationCenter;
  Keep: IAtlasNotificationCenter;
begin
  Center := NewCenter;
  Keep := Center;
  Center.SetMode(TAtlasNotificationSources.Build, TAtlasNotificationMode.Off);
  Center.ApplyModes('shortcutTips=collect; server = OFF, kaputt, check=irgendwas');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Center.ModeOf(Tips)));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Off), Ord(Center.ModeOf(Server)));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Center.ModeOf(TAtlasNotificationSources.Build)),
    'nicht genannte Quellen zeigen wieder');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Center.ModeOf(TAtlasNotificationSources.Check)),
    'unbekanntes Verhalten');
end;

procedure TAtlasNotificationCenterTests.DisabledCenterBehavesLikeBefore;
var
  Center: TAtlasNotificationCenter;
  Keep: IAtlasNotificationCenter;
begin
  Center := NewCenter;
  Keep := Center;
  Center.ApplyModes('shortcutTips=collect');
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'a', '');
  Center.Enabled := False;
  Assert.AreEqual(0, Integer(Length(Center.Items())), 'Ausschalten leert die Liste');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Center.ModeOf(Tips)), 'aus: alle Quellen zeigen');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show),
    Ord(Center.Notify(Tips, TAtlasNotificationSeverity.Info, 'b', '')));
  Assert.AreEqual(0, Integer(Length(Center.Items())), 'aus: nichts gesammelt');
  Center.Enabled := True;
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Center.ModeOf(Tips)), 'Verhalten bleiben gemerkt');
end;

procedure TAtlasNotificationCenterTests.ListenersSeeEveryChange;
var
  Center: IAtlasNotificationCenter;
  Calls, Handle, Before: Integer;
begin
  Center := NewCenter;
  Calls := 0;
  Handle := Center.AddListener(
    procedure
    begin
      Inc(Calls);
    end);
  Before := Center.Version;
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'a', '');
  Center.MarkRead(1);
  Center.MarkRead(1);
  Center.MarkAllRead;
  Center.Clear;
  Assert.AreEqual(3, Calls, 'Melden, Gelesen, Leeren; ohne Änderung kein Ereignis');
  Assert.AreEqual(Before + 3, Center.Version);
  Center.RemoveListener(Handle);
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'b', '');
  Assert.AreEqual(3, Calls, 'abgemeldet');
end;

procedure TAtlasNotificationCenterTests.FilterBySourceAndClear;
var
  Center: IAtlasNotificationCenter;
  Sources: TArray<string>;
begin
  Center := NewCenter;
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'a', '');
  Center.Notify(TAtlasNotificationSources.Build, TAtlasNotificationSeverity.Info, 'b', '');
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'c', '');
  Assert.AreEqual(2, Integer(Length(Center.Items('SERVER'))));
  Assert.AreEqual('c', Center.Items(Server)[0].Title);
  Assert.AreEqual(3, Integer(Length(Center.Items(''))), 'leer = alle');
  Sources := Center.Sources;
  Assert.AreEqual(2, Integer(Length(Sources)));
  Assert.AreEqual(Server, Sources[0], 'Reihenfolge der Liste');
  Assert.AreEqual(TAtlasNotificationSources.Build, Sources[1]);
  Center.Clear;
  Assert.AreEqual(0, Integer(Length(Center.Items())));
  Assert.AreEqual(0, Integer(Length(Center.Sources)));
  Center.Notify(Server, TAtlasNotificationSeverity.Info, 'd', '');
  Assert.AreEqual(4, Center.Items()[0].Id, 'Kennungen laufen weiter');
end;

procedure TAtlasNotificationCenterTests.DefaultStaysOffUntilEnabled;
var
  Center: IAtlasNotificationCenter;
begin
  TAtlasNotificationCenter.ReleaseDefault;
  try
    Center := TAtlasNotificationCenter.Default;
    Assert.IsTrue(Center = TAtlasNotificationCenter.Default, 'eine Zentrale');
    Assert.AreEqual(Ord(TAtlasNotificationMode.Show),
      Ord(Center.Notify(Tips, TAtlasNotificationSeverity.Info, 'a', '')));
    Assert.AreEqual(0, Integer(Length(Center.Items())), 'ohne Plugin-Einstellung wie vor #601');
    TAtlasNotificationCenter.DefaultCenter.Enabled := True;
    Center.Notify(Tips, TAtlasNotificationSeverity.Info, 'a', '');
    Assert.AreEqual(1, Integer(Length(Center.Items())));
  finally
    Center := nil;
    TAtlasNotificationCenter.ReleaseDefault;
  end;
end;

{ TAtlasNotificationSourcesTests }

procedure TAtlasNotificationSourcesTests.ParseSkipsBrokenEntries;
var
  Modes: TArray<TAtlasNotificationSourceMode>;
begin
  Modes := TAtlasNotificationSources.Parse(' shortcutTips = collect ;server=OFF,' + #13#10 +
    'x=laut, =off, ohneGleich, build=show, server=collect');
  Assert.AreEqual(3, Integer(Length(Modes)));
  Assert.AreEqual('shortcutTips', Modes[0].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Modes[0].Mode));
  Assert.AreEqual('server', Modes[1].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Modes[1].Mode), 'spätere Angabe gewinnt');
  Assert.AreEqual('build', Modes[2].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Modes[2].Mode));
  Assert.AreEqual(0, Integer(Length(TAtlasNotificationSources.Parse(''))));
end;

procedure TAtlasNotificationSourcesTests.ToTextLeavesOutShow;
begin
  Assert.AreEqual('shortcutTips=collect, server=off',
    TAtlasNotificationSources.Normalize('shortcutTips=collect;build=show; server=off'));
  Assert.AreEqual('', TAtlasNotificationSources.Normalize('build=show'));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Off),
    Ord(TAtlasNotificationSources.ModeIn('server=off', 'SERVER')));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(TAtlasNotificationSources.ModeIn('server=off', 'build')));
end;

procedure TAtlasNotificationSourcesTests.WithModeChangesOneSource;
var
  Spec: string;
begin
  Spec := TAtlasNotificationSources.WithMode('', 'shortcutTips', TAtlasNotificationMode.Collect);
  Assert.AreEqual('shortcutTips=collect', Spec);
  // Unbekannte Quellen (künftige Hinweise wie #763) bleiben erhalten.
  Spec := TAtlasNotificationSources.WithMode('ci=off, ' + Spec, 'server', TAtlasNotificationMode.Off);
  Assert.AreEqual('ci=off, shortcutTips=collect, server=off', Spec);
  Spec := TAtlasNotificationSources.WithMode(Spec, 'SHORTCUTTIPS', TAtlasNotificationMode.Show);
  Assert.AreEqual('ci=off, server=off', Spec, 'Show ist die Vorgabe und fällt weg');
  Assert.AreEqual('ci=off, server=off', TAtlasNotificationSources.WithMode(Spec, ' ', TAtlasNotificationMode.Off));
end;

procedure TAtlasNotificationSourcesTests.KnownSourcesAndModeNames;
var
  Mode: TAtlasNotificationMode;
begin
  Assert.AreEqual(9, Integer(Length(TAtlasNotificationSources.Known)));
  Assert.AreEqual('build', TAtlasNotificationSources.Known[0]);
  Assert.AreEqual('shortcutTips', TAtlasNotificationSources.Known[4]);
  Assert.AreEqual('buildServer', TAtlasNotificationSources.Known[5], 'Build-Server (#763)');
  Assert.AreEqual('openBuild', TAtlasNotificationSources.Known[6], 'Bauen beim Öffnen');
  Assert.AreEqual('hidden', TAtlasNotificationSources.Known[7], 'Ausblenden am Element (#628)');
  Assert.AreEqual('unitRename', TAtlasNotificationSources.Known[8], 'uses nachziehen (#512)');
  Assert.AreEqual('show', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Show));
  Assert.AreEqual('collect', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Collect));
  Assert.AreEqual('off', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Off));
  Assert.IsTrue(TAtlasNotificationSources.TryMode(' Collect ', Mode));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(Mode));
  Assert.IsFalse(TAtlasNotificationSources.TryMode('laut', Mode));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(Mode));
end;

{ TAtlasBuildNoticeTests }

function TAtlasBuildNoticeTests.Msg(ASeverity: TAtlasCompilerSeverity; const AFileName: string;
  ALine: Integer): TAtlasCompilerMessage;
begin
  Result := Default(TAtlasCompilerMessage);
  Result.Severity := ASeverity;
  Result.FileName := AFileName;
  Result.Line := ALine;
  Result.Column := 3;
  Result.Code := 'E2003';
  Result.Text := 'Undeklarierter Bezeichner';
end;

procedure TAtlasBuildNoticeTests.BuildWithErrorsTargetsFirstErrorWithFile;
var
  Notice: TAtlasBuildNotice;
begin
  // Akzeptanzkriterium: Build mit 2 Fehlern ergibt „Build fertig: 2 Fehler“ mit Sprung zur ersten Meldung.
  Notice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Hint, 'C:\P\A.pas', 1),
    Msg(TAtlasCompilerSeverity.Fatal, '', 0), Msg(TAtlasCompilerSeverity.Error, 'C:\P\Main.pas', 12),
    Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], False, True, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Errors), Ord(Notice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(Notice.Severity));
  Assert.AreEqual(2, Notice.Errors);
  Assert.AreEqual(1, Notice.Warnings);
  Assert.AreEqual(1, Notice.Hints);
  Assert.IsTrue(Notice.HasTarget);
  Assert.AreEqual('C:\P\Main.pas', Notice.Target.FileName, 'erste Fehlermeldung mit Datei');
  Assert.AreEqual(12, Notice.Target.Line);
  Assert.AreEqual(TAtlasNotificationSources.Build, TAtlasBuildNotices.SourceOf(False));
end;

procedure TAtlasBuildNoticeTests.BuildWithWarningsSucceededOrFailed;
var
  Notice: TAtlasBuildNotice;
begin
  Notice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], True, True, False,
    -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Warnings), Ord(Notice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Warning), Ord(Notice.Severity));
  Assert.IsFalse(Notice.HasTarget, 'Warnungen sind kein Fehler');
  Notice := TAtlasBuildNotices.FromRun(nil, True, True, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Succeeded), Ord(Notice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Info), Ord(Notice.Severity));
  Notice := TAtlasBuildNotices.FromRun(nil, False, False, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Failed), Ord(Notice.Kind), 'ohne lesbare Meldungen');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(Notice.Severity));
end;

procedure TAtlasBuildNoticeTests.BackgroundCheckOnlyOnErrorsAndRecovery;
var
  Notice: TAtlasBuildNotice;
begin
  Assert.AreEqual(TAtlasNotificationSources.Check, TAtlasBuildNotices.SourceOf(True));
  Notice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Error, 'C:\P\Main.pas', 4)], False, True, True, 0);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.CheckErrors), Ord(Notice.Kind));
  Assert.AreEqual(1, Notice.Errors);
  Assert.IsTrue(Notice.HasTarget);
  Notice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], True, True, True, 2);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.CheckClean), Ord(Notice.Kind), 'wieder fehlerfrei');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Info), Ord(Notice.Severity));
  Notice := TAtlasBuildNotices.FromRun(nil, True, True, True, 0);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(Notice.Kind), 'fehlerfrei wie vorher: nichts');
  Notice := TAtlasBuildNotices.FromRun(nil, True, True, True, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(Notice.Kind), 'erste Prüfung ohne Fehler: nichts');
  Notice := TAtlasBuildNotices.FromRun(nil, False, False, True, 3);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(Notice.Kind), 'nicht lesbar: keine Entwarnung');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationCenterTests);
  TDUnitX.RegisterTestFixture(TAtlasNotificationSourcesTests);
  TDUnitX.RegisterTestFixture(TAtlasBuildNoticeTests);

end.
