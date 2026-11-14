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
  Atlas.Core.Notifications.Center;

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
    /// <summary>#530: Eintrag nach der Bewertung; zeroHints macht einen erfolgreichen Build rot, Meldungen in der
    /// Basislinie zählen nicht.</summary>
    [Test]
    procedure VerdictRejectsAndSkipsBaseline;
    [Test]
    procedure BackgroundCheckOnlyOnErrorsAndRecovery;
  private
    function Msg(ASeverity: TAtlasCompilerSeverity; const AFileName: string; ALine: Integer): TAtlasCompilerMessage;
  end;

implementation

uses
  Atlas.Core.Build.Verdict,
  Atlas.Core.Notifications.Contract,
  Atlas.Core.Notifications.Sources,
  Atlas.Core.Notifications.Build;

const
  cServerSource = TAtlasNotificationSources.cServer;
  cTips = TAtlasNotificationSources.cShortcutTips;

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
  mCenter: IAtlasNotificationCenter;
  mEntry: IAtlasNotification;
  mMode: TAtlasNotificationMode;
begin
  // Akzeptanzkriterium: melden ohne Änderung an der Oberfläche, nur über die Schnittstelle.
  mCenter := NewCenter;
  mMode := mCenter.Notify('ci', TAtlasNotificationSeverity.Error, 'Server rot', 'Jenkins #482');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mMode), 'unbekannte Quelle zeigt');
  Assert.AreEqual(1, Integer(Length(mCenter.Items())));
  mEntry := mCenter.Items()[0];
  Assert.AreEqual(1, mEntry.Id);
  Assert.AreEqual('ci', mEntry.Source);
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mEntry.Severity));
  Assert.AreEqual('Server rot', mEntry.Title);
  Assert.AreEqual('Server rot', mEntry.Caption);
  Assert.AreEqual('Jenkins #482', mEntry.Text);
  Assert.AreEqual(1, Integer(mEntry.Count));
  Assert.IsFalse(mEntry.Read);
  Assert.AreEqual<TDateTime>(FNow, mEntry.Time, 'Zeit der Meldung');
  Assert.AreEqual(1, mCenter.UnreadCount);
  Assert.IsNotNull(mCenter.Find(1));
  Assert.IsNull(mCenter.Find(2));
end;

procedure TAtlasNotificationCenterTests.NewestComesFirst;
var
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := NewCenter;
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Info, 'Build fertig: erfolgreich', '');
  FNow := FNow + Seconds(1);
  mCenter.Notify(TAtlasNotificationSources.cReload, TAtlasNotificationSeverity.Info, 'Dateien neu geladen: 2', '');
  Assert.AreEqual(2, Integer(Length(mCenter.Items())));
  Assert.AreEqual('Dateien neu geladen: 2', mCenter.Items()[0].Title);
  Assert.AreEqual('Build fertig: erfolgreich', mCenter.Items()[1].Title);
  Assert.AreEqual(2, mCenter.Items()[0].Id);
end;

procedure TAtlasNotificationCenterTests.ThreeRestartsWithinTenSecondsMerge;
var
  mCenter: IAtlasNotificationCenter;
  mEntry: IAtlasNotification;
begin
  // Akzeptanzkriterium: drei Neustarts innerhalb von 10 s ergeben einen Eintrag „3 × Server neu gestartet“.
  mCenter := NewCenter;
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'erster');
  mCenter.MarkRead(1);
  FNow := FNow + Seconds(4);
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'zweiter');
  FNow := FNow + Seconds(9);
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server neu gestartet', 'dritter');
  Assert.AreEqual(1, Integer(Length(mCenter.Items())), 'ein Eintrag');
  mEntry := mCenter.Items()[0];
  Assert.AreEqual('3 × Server neu gestartet', mEntry.Caption);
  Assert.AreEqual('Server neu gestartet', mEntry.Title);
  Assert.AreEqual(3, Integer(mEntry.Count));
  Assert.AreEqual(1, mEntry.Id, 'Kennung bleibt');
  Assert.AreEqual('dritter', mEntry.Text, 'neuester Text');
  Assert.AreEqual<TDateTime>(FNow, mEntry.Time, 'Zeit der letzten Meldung');
  Assert.IsFalse(mEntry.Read, 'wieder ungelesen');
  Assert.AreEqual(1, mCenter.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.NoMergeAfterTenSecondsOrOtherTitle;
var
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := NewCenter;
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  FNow := FNow + Seconds(11);
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Assert.AreEqual(2, Integer(Length(mCenter.Items())), 'nach mehr als 10 s ein neuer Eintrag');
  FNow := FNow + Seconds(1);
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Server: Fehler', '');
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Info, 'Server neu gestartet', '');
  Assert.AreEqual(4, Integer(Length(mCenter.Items())), 'anderer Titel bzw. andere Quelle');
  Assert.AreEqual(1, mCenter.Items()[3].Count);
end;

procedure TAtlasNotificationCenterTests.MergeKeepsWorseSeverityAndMovesUp;
var
  mCenter: IAtlasNotificationCenter;
  mActions: TArray<TAtlasNotificationAction>;
begin
  mCenter := NewCenter;
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Error, 'Meldung des Servers', 'a');
  FNow := FNow + Seconds(1);
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Info, 'Build fertig: erfolgreich', '');
  FNow := FNow + Seconds(1);
  mActions := [TAtlasNotificationCenter.Action('Protokoll öffnen', nil)];
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Warning, 'Meldung des Servers', 'b', mActions);
  Assert.AreEqual(2, Integer(Length(mCenter.Items())));
  Assert.AreEqual('2 × Meldung des Servers', mCenter.Items()[0].Caption, 'nach oben gerückt');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mCenter.Items()[0].Severity), 'schwerere bleibt');
  Assert.AreEqual(1, Integer(Length(mCenter.Items()[0].Actions)), 'Aktionen der neuesten Meldung');
  Assert.AreEqual('Protokoll öffnen', mCenter.Items()[0].Actions[0].Caption);
end;

procedure TAtlasNotificationCenterTests.ListKeepsAtMostMaxEntries;
var
  mCenter: TAtlasNotificationCenter;
  mKeep: IAtlasNotificationCenter;
  mIndex: Integer;
begin
  mCenter := NewCenter;
  mKeep := mCenter;
  Assert.AreEqual(200, mCenter.MaxEntries, 'Vorgabe 200');
  mCenter.SetMaxEntries(10);
  for mIndex := 1 to 12 do
  begin
    FNow := FNow + Seconds(20);
    mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Eintrag ' + IntToStr(mIndex), '');
  end;
  Assert.AreEqual(10, Integer(Length(mCenter.Items())));
  Assert.AreEqual('Eintrag 12', mCenter.Items()[0].Title, 'neuester bleibt');
  Assert.AreEqual('Eintrag 3', mCenter.Items()[9].Title, 'die ältesten fallen weg');
  Assert.IsNull(mCenter.Find(1));
  Assert.AreEqual(10, mCenter.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.MaxEntriesIsClampedAndShrinks;
var
  mCenter: TAtlasNotificationCenter;
  mKeep: IAtlasNotificationCenter;
  mIndex: Integer;
begin
  mCenter := NewCenter;
  mKeep := mCenter;
  mCenter.SetMaxEntries(3);
  Assert.AreEqual(TAtlasNotificationCenter.cMinEntries, mCenter.MaxEntries, 'nach unten begrenzt');
  mCenter.SetMaxEntries(5000);
  Assert.AreEqual(TAtlasNotificationCenter.cMaxMaxEntries, mCenter.MaxEntries, 'nach oben begrenzt');
  for mIndex := 1 to 15 do
  begin
    mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'Eintrag ' + IntToStr(mIndex), '');
  end;
  mCenter.SetMaxEntries(10);
  Assert.AreEqual(10, Integer(Length(mCenter.Items())), 'Verkleinern kürzt die Liste');
  Assert.AreEqual('Eintrag 15', mCenter.Items()[0].Title);
end;

procedure TAtlasNotificationCenterTests.ReadStateAndWorstUnread;
var
  mCenter: IAtlasNotificationCenter;
  mSeverity: TAtlasNotificationSeverity;
begin
  mCenter := NewCenter;
  Assert.IsFalse(mCenter.WorstUnread(mSeverity), 'leer');
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'a', '');
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Error, 'b', '');
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Warning, 'c', '');
  Assert.AreEqual(3, mCenter.UnreadCount);
  Assert.IsTrue(mCenter.WorstUnread(mSeverity));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mSeverity));
  mCenter.MarkRead(2);
  Assert.IsTrue(mCenter.Find(2).Read);
  Assert.AreEqual(2, mCenter.UnreadCount);
  Assert.IsTrue(mCenter.WorstUnread(mSeverity));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Warning), Ord(mSeverity), 'gelesene zählen nicht');
  mCenter.MarkAllRead;
  Assert.AreEqual(0, mCenter.UnreadCount);
  Assert.IsFalse(mCenter.WorstUnread(mSeverity));
  Assert.AreEqual(3, Integer(Length(mCenter.Items())), 'gelesene bleiben in der Liste');
end;

procedure TAtlasNotificationCenterTests.ActionMarksReadAndRuns;
var
  mCenter: IAtlasNotificationCenter;
  mJumped: Integer;
  mReadWhenRun: Boolean;
begin
  // Akzeptanzkriterium: „Zum Fehler“ springt und markiert den Eintrag als gelesen.
  mCenter := NewCenter;
  mJumped := 0;
  mReadWhenRun := False;
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Error, 'Build fertig: 2 Fehler', '',
    [TAtlasNotificationCenter.Action('Zum Fehler',
    procedure
    begin
      Inc(mJumped);
      mReadWhenRun := mCenter.Find(1).Read;
    end)]);
  Assert.AreEqual(1, mCenter.UnreadCount, 'Zähler zeigt 1');
  Assert.IsTrue(mCenter.RunAction(1, 0));
  Assert.AreEqual(1, mJumped);
  Assert.IsTrue(mReadWhenRun, 'vor der Aktion gelesen');
  Assert.AreEqual(0, mCenter.UnreadCount);
  Assert.IsFalse(mCenter.RunAction(1, 1), 'keine zweite Aktion');
  Assert.IsFalse(mCenter.RunAction(7, 0), 'kein Eintrag');
  Assert.AreEqual(1, mJumped);
  // Kein Kreis über die Referenz der Aktion auf die Zentrale.
  mCenter.Clear;
end;

procedure TAtlasNotificationCenterTests.CollectOnlyKeepsEntryButNoPopup;
var
  mCenter: IAtlasNotificationCenter;
begin
  // Akzeptanzkriterium: Tastenkürzel-Tipps auf „nur sammeln“: keine Einblendung, aber der Eintrag.
  mCenter := NewCenter;
  mCenter.SetMode(cTips, TAtlasNotificationMode.Collect);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mCenter.ModeOf('SHORTCUTTIPS')),
    'Quelle ohne Groß-/Kleinschreibung');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect),
    Ord(mCenter.Notify(cTips, TAtlasNotificationSeverity.Info, 'Tastenkürzel: Strg+Umschalt+P', 'Befehlspalette')),
    'die Quelle zeigt nichts');
  Assert.AreEqual(1, Integer(Length(mCenter.Items())), 'der Tipp steht in der Liste');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mCenter.ModeOf(cServerSource)), 'andere Quellen zeigen');
  mCenter.SetMode(cTips, TAtlasNotificationMode.Show);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mCenter.ModeOf(cTips)));
end;

procedure TAtlasNotificationCenterTests.OffCollectsNothing;
var
  mCenter: IAtlasNotificationCenter;
begin
  mCenter := NewCenter;
  mCenter.SetMode(cServerSource, TAtlasNotificationMode.Off);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Off),
    Ord(mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Error, 'Server: Fehler', '')));
  Assert.AreEqual(0, Integer(Length(mCenter.Items())), 'aus: weder Einblendung noch Eintrag');
  Assert.AreEqual(0, mCenter.UnreadCount);
end;

procedure TAtlasNotificationCenterTests.ApplyModesReplacesAllModes;
var
  mCenter: TAtlasNotificationCenter;
  mKeep: IAtlasNotificationCenter;
begin
  mCenter := NewCenter;
  mKeep := mCenter;
  mCenter.SetMode(TAtlasNotificationSources.cBuild, TAtlasNotificationMode.Off);
  mCenter.ApplyModes('shortcutTips=collect; server = OFF, kaputt, check=irgendwas');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mCenter.ModeOf(cTips)));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Off), Ord(mCenter.ModeOf(cServerSource)));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mCenter.ModeOf(TAtlasNotificationSources.cBuild)),
    'nicht genannte Quellen zeigen wieder');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mCenter.ModeOf(TAtlasNotificationSources.cCheck)),
    'unbekanntes Verhalten');
end;

procedure TAtlasNotificationCenterTests.DisabledCenterBehavesLikeBefore;
var
  mCenter: TAtlasNotificationCenter;
  mKeep: IAtlasNotificationCenter;
begin
  mCenter := NewCenter;
  mKeep := mCenter;
  mCenter.ApplyModes('shortcutTips=collect');
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'a', '');
  mCenter.Enabled := False;
  Assert.AreEqual(0, Integer(Length(mCenter.Items())), 'Ausschalten leert die Liste');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mCenter.ModeOf(cTips)), 'aus: alle Quellen zeigen');
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show),
    Ord(mCenter.Notify(cTips, TAtlasNotificationSeverity.Info, 'b', '')));
  Assert.AreEqual(0, Integer(Length(mCenter.Items())), 'aus: nichts gesammelt');
  mCenter.Enabled := True;
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mCenter.ModeOf(cTips)), 'Verhalten bleiben gemerkt');
end;

procedure TAtlasNotificationCenterTests.ListenersSeeEveryChange;
var
  mCenter: IAtlasNotificationCenter;
  mCalls, mHandle, mBefore: Integer;
begin
  mCenter := NewCenter;
  mCalls := 0;
  mHandle := mCenter.AddListener(
    procedure
    begin
      Inc(mCalls);
    end);
  mBefore := mCenter.Version;
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'a', '');
  mCenter.MarkRead(1);
  mCenter.MarkRead(1);
  mCenter.MarkAllRead;
  mCenter.Clear;
  Assert.AreEqual(3, mCalls, 'Melden, Gelesen, Leeren; ohne Änderung kein Ereignis');
  Assert.AreEqual(mBefore + 3, mCenter.Version);
  mCenter.RemoveListener(mHandle);
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'b', '');
  Assert.AreEqual(3, mCalls, 'abgemeldet');
end;

procedure TAtlasNotificationCenterTests.FilterBySourceAndClear;
var
  mCenter: IAtlasNotificationCenter;
  mSources: TArray<string>;
begin
  mCenter := NewCenter;
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'a', '');
  mCenter.Notify(TAtlasNotificationSources.cBuild, TAtlasNotificationSeverity.Info, 'b', '');
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'c', '');
  Assert.AreEqual(2, Integer(Length(mCenter.Items('SERVER'))));
  Assert.AreEqual('c', mCenter.Items(cServerSource)[0].Title);
  Assert.AreEqual(3, Integer(Length(mCenter.Items(''))), 'leer = alle');
  mSources := mCenter.Sources;
  Assert.AreEqual(2, Integer(Length(mSources)));
  Assert.AreEqual(cServerSource, mSources[0], 'Reihenfolge der Liste');
  Assert.AreEqual(TAtlasNotificationSources.cBuild, mSources[1]);
  mCenter.Clear;
  Assert.AreEqual(0, Integer(Length(mCenter.Items())));
  Assert.AreEqual(0, Integer(Length(mCenter.Sources)));
  mCenter.Notify(cServerSource, TAtlasNotificationSeverity.Info, 'd', '');
  Assert.AreEqual(4, mCenter.Items()[0].Id, 'Kennungen laufen weiter');
end;

procedure TAtlasNotificationCenterTests.DefaultStaysOffUntilEnabled;
var
  mCenter: IAtlasNotificationCenter;
begin
  TAtlasNotificationCenter.ReleaseDefault;
  try
    mCenter := TAtlasNotificationCenter.Default;
    Assert.AreSame(TAtlasNotificationCenter.Default, mCenter, 'eine Zentrale');
    Assert.AreEqual(Ord(TAtlasNotificationMode.Show),
      Ord(mCenter.Notify(cTips, TAtlasNotificationSeverity.Info, 'a', '')));
    Assert.AreEqual(0, Integer(Length(mCenter.Items())), 'ohne Plugin-Einstellung wie vor #601');
    TAtlasNotificationCenter.DefaultCenter.Enabled := True;
    mCenter.Notify(cTips, TAtlasNotificationSeverity.Info, 'a', '');
    Assert.AreEqual(1, Integer(Length(mCenter.Items())));
  finally
    mCenter := nil;
    TAtlasNotificationCenter.ReleaseDefault;
  end;
end;

{ TAtlasNotificationSourcesTests }

procedure TAtlasNotificationSourcesTests.ParseSkipsBrokenEntries;
var
  mModes: TArray<TAtlasNotificationSourceMode>;
begin
  mModes := TAtlasNotificationSources.Parse(' shortcutTips = collect ;server=OFF,' + #13#10 +
    'x=laut, =off, ohneGleich, build=show, server=collect');
  Assert.AreEqual(3, Integer(Length(mModes)));
  Assert.AreEqual('shortcutTips', mModes[0].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mModes[0].Mode));
  Assert.AreEqual('server', mModes[1].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mModes[1].Mode), 'spätere Angabe gewinnt');
  Assert.AreEqual('build', mModes[2].Source);
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mModes[2].Mode));
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
  mSpec: string;
begin
  mSpec := TAtlasNotificationSources.WithMode('', 'shortcutTips', TAtlasNotificationMode.Collect);
  Assert.AreEqual('shortcutTips=collect', mSpec);
  // Unbekannte Quellen (künftige Hinweise wie #763) bleiben erhalten.
  mSpec := TAtlasNotificationSources.WithMode('ci=off, ' + mSpec, 'server', TAtlasNotificationMode.Off);
  Assert.AreEqual('ci=off, shortcutTips=collect, server=off', mSpec);
  mSpec := TAtlasNotificationSources.WithMode(mSpec, 'SHORTCUTTIPS', TAtlasNotificationMode.Show);
  Assert.AreEqual('ci=off, server=off', mSpec, 'Show ist die Vorgabe und fällt weg');
  Assert.AreEqual('ci=off, server=off', TAtlasNotificationSources.WithMode(mSpec, ' ', TAtlasNotificationMode.Off));
end;

procedure TAtlasNotificationSourcesTests.KnownSourcesAndModeNames;
var
  mMode: TAtlasNotificationMode;
begin
  Assert.AreEqual(10, Integer(Length(TAtlasNotificationSources.Known)));
  Assert.AreEqual('build', TAtlasNotificationSources.Known[0]);
  Assert.AreEqual('shortcutTips', TAtlasNotificationSources.Known[4]);
  Assert.AreEqual('buildServer', TAtlasNotificationSources.Known[5], 'Build-Server (#763)');
  Assert.AreEqual('openBuild', TAtlasNotificationSources.Known[6], 'Bauen beim Öffnen');
  Assert.AreEqual('hidden', TAtlasNotificationSources.Known[7], 'Ausblenden am Element (#628)');
  Assert.AreEqual('unitRename', TAtlasNotificationSources.Known[8], 'uses nachziehen (#512)');
  Assert.AreEqual('issues', TAtlasNotificationSources.Known[9], 'Meldungen zu meinen Issues (#1271)');
  Assert.AreEqual('show', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Show));
  Assert.AreEqual('collect', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Collect));
  Assert.AreEqual('off', TAtlasNotificationSources.ModeName(TAtlasNotificationMode.Off));
  Assert.IsTrue(TAtlasNotificationSources.TryMode(' Collect ', mMode));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Collect), Ord(mMode));
  Assert.IsFalse(TAtlasNotificationSources.TryMode('laut', mMode));
  Assert.AreEqual(Ord(TAtlasNotificationMode.Show), Ord(mMode));
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
  mNotice: TAtlasBuildNotice;
begin
  // Akzeptanzkriterium: Build mit 2 Fehlern ergibt „Build fertig: 2 Fehler“ mit Sprung zur ersten Meldung.
  mNotice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Hint, 'C:\P\A.pas', 1),
    Msg(TAtlasCompilerSeverity.Fatal, '', 0), Msg(TAtlasCompilerSeverity.Error, 'C:\P\Main.pas', 12),
    Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], False, True, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Errors), Ord(mNotice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mNotice.Severity));
  Assert.AreEqual(2, mNotice.Errors);
  Assert.AreEqual(1, mNotice.Warnings);
  Assert.AreEqual(1, mNotice.Hints);
  Assert.IsTrue(mNotice.HasTarget);
  Assert.AreEqual('C:\P\Main.pas', mNotice.Target.FileName, 'erste Fehlermeldung mit Datei');
  Assert.AreEqual(12, mNotice.Target.Line);
  Assert.AreEqual(TAtlasNotificationSources.cBuild, TAtlasBuildNotices.SourceOf(False));
end;

procedure TAtlasBuildNoticeTests.VerdictRejectsAndSkipsBaseline;
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mNotice: TAtlasBuildNotice;
begin
  mMessages := [Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7),
    Msg(TAtlasCompilerSeverity.Hint, 'C:\P\A.pas', 3)];
  mMessages[0].Code := 'W1035';
  mMessages[1].Code := 'H2164';
  mNotice := TAtlasBuildNotices.FromVerdict(mMessages, TAtlasBuildVerdicts.Evaluate(mMessages, nil, True,
    TAtlasBuildVerdictSettings.Create(True, '')));
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Rejected), Ord(mNotice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mNotice.Severity));
  Assert.IsTrue(mNotice.HasTarget, 'Zur Meldung');
  Assert.AreEqual(7, mNotice.Target.Line);
  mNotice := TAtlasBuildNotices.FromVerdict(mMessages, TAtlasBuildVerdicts.Evaluate(mMessages, nil, True,
    TAtlasBuildVerdictSettings.Create(False, 'H2164')));
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Rejected), Ord(mNotice.Kind));
  Assert.AreEqual('H2164', mNotice.PromotedCode);
  Assert.AreEqual(3, mNotice.Target.Line, 'Ziel ist die Meldung aus warningsAsErrors');
  // Warnung in der Basislinie: nur der Hinweis zählt, der Build ist ohne Schranke erfolgreich.
  mNotice := TAtlasBuildNotices.FromVerdict(mMessages, TAtlasBuildVerdicts.Evaluate(mMessages,
    TArray<Boolean>.Create(True, False), True, TAtlasBuildVerdictSettings.Create(False, '')));
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Succeeded), Ord(mNotice.Kind));
  Assert.AreEqual(0, mNotice.Warnings);
  Assert.AreEqual(1, mNotice.Hints);
  Assert.AreEqual(1, mNotice.Baselined);
end;

procedure TAtlasBuildNoticeTests.BuildWithWarningsSucceededOrFailed;
var
  mNotice: TAtlasBuildNotice;
begin
  mNotice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], True, True, False,
    -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Warnings), Ord(mNotice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Warning), Ord(mNotice.Severity));
  Assert.IsFalse(mNotice.HasTarget, 'Warnungen sind kein Fehler');
  mNotice := TAtlasBuildNotices.FromRun(nil, True, True, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Succeeded), Ord(mNotice.Kind));
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Info), Ord(mNotice.Severity));
  mNotice := TAtlasBuildNotices.FromRun(nil, False, False, False, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.Failed), Ord(mNotice.Kind), 'ohne lesbare Meldungen');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Error), Ord(mNotice.Severity));
end;

procedure TAtlasBuildNoticeTests.BackgroundCheckOnlyOnErrorsAndRecovery;
var
  mNotice: TAtlasBuildNotice;
begin
  Assert.AreEqual(TAtlasNotificationSources.cCheck, TAtlasBuildNotices.SourceOf(True));
  mNotice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Error, 'C:\P\Main.pas', 4)], False, True, True, 0);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.CheckErrors), Ord(mNotice.Kind));
  Assert.AreEqual(1, mNotice.Errors);
  Assert.IsTrue(mNotice.HasTarget);
  mNotice := TAtlasBuildNotices.FromRun([Msg(TAtlasCompilerSeverity.Warning, 'C:\P\B.pas', 7)], True, True, True, 2);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.CheckClean), Ord(mNotice.Kind), 'wieder fehlerfrei');
  Assert.AreEqual(Ord(TAtlasNotificationSeverity.Info), Ord(mNotice.Severity));
  mNotice := TAtlasBuildNotices.FromRun(nil, True, True, True, 0);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(mNotice.Kind), 'fehlerfrei wie vorher: nichts');
  mNotice := TAtlasBuildNotices.FromRun(nil, True, True, True, -1);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(mNotice.Kind), 'erste Prüfung ohne Fehler: nichts');
  mNotice := TAtlasBuildNotices.FromRun(nil, False, False, True, 3);
  Assert.AreEqual(Ord(TAtlasBuildNoticeKind.None), Ord(mNotice.Kind), 'nicht lesbar: keine Entwarnung');
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasNotificationCenterTests);
  TDUnitX.RegisterTestFixture(TAtlasNotificationSourcesTests);
  TDUnitX.RegisterTestFixture(TAtlasBuildNoticeTests);

end.
