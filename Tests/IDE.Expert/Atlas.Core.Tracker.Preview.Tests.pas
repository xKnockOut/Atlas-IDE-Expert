unit Atlas.Core.Tracker.Preview.Tests;

// Entscheidungen des Fensters „Atlas-Issue“ (#1264) ohne Fenster: Verlauf
// Zurück/Vor, Abzeichen in fester Reihenfolge, Zeitabstände, eingeklappte
// Kommentare, Bildadressen (Anhänge), was geladen bzw. im Browser geöffnet
// werden darf, Fehler → Befehl zum Beheben, Kennung aus der Eingabe und
// Dateinamen für Anhänge.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIssuePreviewTests = class
  public
    [Test]
    procedure HistoryBackForwardAndTruncate;
    [Test]
    procedure HistoryKeepsMaxEntries;
    [Test]
    procedure BadgesInFixedOrder;
    [Test]
    procedure AgeUnits;
    [Test]
    procedure CollapsedComments;
    /// <summary>#1271: Aus einer Meldung öffnet die Vorschau am ersten neuen Kommentar.</summary>
    [Test]
    procedure CommentAtAnchor;
    [Test]
    procedure ImageUrlFromAttachments;
    /// <summary>Abnahme: Bilder nur vom Server des Tokens, nie eine Anfrage an einen Rechner aus dem Text.</summary>
    [Test]
    procedure MayLoadOnlyFromApiServer;
    [Test]
    procedure MayBrowseOnlyWebWithoutUser;
    [Test]
    procedure FixPerError;
    [Test]
    procedure KeyFromInput;
    [Test]
    procedure SafeFileNames;
  end;

implementation

uses
  System.SysUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Preview;

function Entry(const AKey: string): TAtlasIssueHistoryEntry;
begin
  Result := TAtlasIssueHistoryEntry.Create(TAtlasTrackerTarget.Create('github', 'https://github.com',
    'beispiel/atlas', ''), AKey);
end;

{ TAtlasIssuePreviewTests }

procedure TAtlasIssuePreviewTests.HistoryBackForwardAndTruncate;
var
  mHistory: TAtlasIssueHistory;
  mEntry: TAtlasIssueHistoryEntry;
begin
  mHistory := TAtlasIssueHistory.Create;
  try
    Assert.IsFalse(mHistory.Current(mEntry));
    Assert.IsFalse(mHistory.CanBack);
    mHistory.Visit(Entry('#1'));
    mHistory.Visit(Entry('#2'));
    mHistory.Visit(Entry('#2'));
    mHistory.Visit(Entry('#3'));
    Assert.AreEqual(Integer(3), mHistory.Count, 'dasselbe Issue zweimal ist ein Eintrag');
    Assert.IsTrue(mHistory.CanBack);
    Assert.IsFalse(mHistory.CanForward);
    Assert.IsTrue(mHistory.GoBack(mEntry));
    Assert.AreEqual('#2', mEntry.Key);
    Assert.IsTrue(mHistory.GoBack(mEntry));
    Assert.AreEqual('#1', mEntry.Key);
    Assert.IsFalse(mHistory.GoBack(mEntry));
    Assert.IsTrue(mHistory.GoForward(mEntry));
    Assert.AreEqual('#2', mEntry.Key);
    // Neues Issue mitten im Verlauf: Vor-Einträge entfallen.
    mHistory.Visit(Entry('#9'));
    Assert.IsFalse(mHistory.CanForward);
    Assert.AreEqual(Integer(3), mHistory.Count);
    Assert.IsTrue(mHistory.Current(mEntry));
    Assert.AreEqual('#9', mEntry.Key);
    mHistory.Clear;
    Assert.AreEqual(Integer(0), mHistory.Count);
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasIssuePreviewTests.HistoryKeepsMaxEntries;
var
  mHistory: TAtlasIssueHistory;
  mEntry: TAtlasIssueHistoryEntry;
  mIndex: Integer;
begin
  mHistory := TAtlasIssueHistory.Create;
  try
    for mIndex := 1 to TAtlasIssueHistory.MaxEntries + 5 do
      mHistory.Visit(Entry('#' + IntToStr(mIndex)));
    Assert.AreEqual(Integer(TAtlasIssueHistory.MaxEntries), mHistory.Count);
    while mHistory.GoBack(mEntry) do
      ;
    Assert.AreEqual('#6', mEntry.Key, 'die ältesten fallen heraus');
  finally
    mHistory.Free;
  end;
end;

procedure TAtlasIssuePreviewTests.BadgesInFixedOrder;
var
  mDetails: TAtlasTrackerDetails;
  mBadges: TArray<TAtlasIssueBadge>;
begin
  mDetails := TAtlasTrackerDetails.Empty;
  mDetails.Key := 'ATL-1';
  mDetails.Sprint := 'Sprint 42';
  mDetails.State := 'Offen';
  mDetails.Labels := TArray<string>.Create('ui', 'plugin');
  mDetails.Updated := 46000;
  mBadges := TAtlasIssuePreview.Badges(mDetails);
  Assert.AreEqual(Integer(5), Integer(Length(mBadges)), 'leere Felder entfallen');
  Assert.IsTrue(mBadges[0].Kind = TAtlasIssueBadgeKind.State);
  Assert.IsTrue(mBadges[1].Kind = TAtlasIssueBadgeKind.Sprint);
  Assert.IsTrue(mBadges[2].Kind = TAtlasIssueBadgeKind.LabelName);
  Assert.AreEqual('ui', mBadges[2].Text);
  Assert.AreEqual('plugin', mBadges[3].Text);
  Assert.IsTrue(mBadges[4].Kind = TAtlasIssueBadgeKind.Updated);
  Assert.AreEqual(Double(46000), Double(mBadges[4].Time), 0.0001);
end;

procedure TAtlasIssuePreviewTests.AgeUnits;
const
  cNow = 46000.5;
var
  mAge: TAtlasIssueAge;
begin
  Assert.IsTrue(TAtlasIssuePreview.Age(cNow - 20 / SecsPerDay, cNow).UnitKind = TAtlasIssueAgeUnit.JustNow);
  Assert.IsTrue(TAtlasIssuePreview.Age(cNow + 1, cNow).UnitKind = TAtlasIssueAgeUnit.JustNow, 'Zukunft');
  Assert.IsTrue(TAtlasIssuePreview.Age(0, cNow).UnitKind = TAtlasIssueAgeUnit.JustNow, 'ohne Zeit');
  mAge := TAtlasIssuePreview.Age(cNow - 5.5 / MinsPerDay, cNow);
  Assert.IsTrue(mAge.UnitKind = TAtlasIssueAgeUnit.Minutes);
  Assert.AreEqual(Integer(5), mAge.Count);
  mAge := TAtlasIssuePreview.Age(cNow - 3.5 / HoursPerDay, cNow);
  Assert.IsTrue(mAge.UnitKind = TAtlasIssueAgeUnit.Hours);
  Assert.AreEqual(Integer(3), mAge.Count);
  mAge := TAtlasIssuePreview.Age(cNow - 12.2, cNow);
  Assert.IsTrue(mAge.UnitKind = TAtlasIssueAgeUnit.Days);
  Assert.AreEqual(Integer(12), mAge.Count);
  mAge := TAtlasIssuePreview.Age(cNow - 95.2, cNow);
  Assert.IsTrue(mAge.UnitKind = TAtlasIssueAgeUnit.Months);
  Assert.AreEqual(Integer(3), mAge.Count);
  mAge := TAtlasIssuePreview.Age(cNow - 800.2, cNow);
  Assert.IsTrue(mAge.UnitKind = TAtlasIssueAgeUnit.Years);
  Assert.AreEqual(Integer(2), mAge.Count);
end;

procedure TAtlasIssuePreviewTests.CollapsedComments;
begin
  Assert.AreEqual(Integer(0), TAtlasIssuePreview.CollapsedComments(3, False));
  Assert.AreEqual(Integer(9), TAtlasIssuePreview.CollapsedComments(12, False));
  Assert.AreEqual(Integer(0), TAtlasIssuePreview.CollapsedComments(12, True));
end;

procedure TAtlasIssuePreviewTests.CommentAtAnchor;
var
  mComments: TArray<TAtlasTrackerComment>;
  mIndex: Integer;
begin
  SetLength(mComments, 4);
  for mIndex := 0 to High(mComments) do
  begin
    mComments[mIndex].Author := 'anna';
    mComments[mIndex].Created := EncodeDateTime(2026, 1, 1, 10, mIndex * 10, 0, 0);
  end;
  Assert.AreEqual(Integer(2), TAtlasIssuePreview.CommentAt(mComments, EncodeDateTime(2026, 1, 1, 10, 20, 0, 0)));
  Assert.AreEqual(Integer(2), TAtlasIssuePreview.CommentAt(mComments, EncodeDateTime(2026, 1, 1, 10, 20, 1, 0)),
    'Millisekunden und Sekunden des Trackers weichen ab');
  Assert.AreEqual(Integer(3), TAtlasIssuePreview.CommentAt(mComments, EncodeDateTime(2026, 1, 1, 10, 25, 0, 0)));
  Assert.AreEqual(Integer(3), TAtlasIssuePreview.CommentAt(mComments, EncodeDateTime(2026, 1, 1, 11, 0, 0, 0)),
    'Kommentar inzwischen gelöscht: der letzte');
  Assert.AreEqual(Integer(-1), TAtlasIssuePreview.CommentAt(mComments, 0), 'ohne Anker oben');
  Assert.AreEqual(Integer(-1), TAtlasIssuePreview.CommentAt(nil, EncodeDateTime(2026, 1, 1, 10, 0, 0, 0)));
end;

procedure TAtlasIssuePreviewTests.ImageUrlFromAttachments;
var
  mDetails: TAtlasTrackerDetails;
  mAttachment: TAtlasTrackerAttachment;
begin
  mDetails := TAtlasTrackerDetails.Empty;
  mAttachment := Default(TAtlasTrackerAttachment);
  mAttachment.Name := 'Skizze.png';
  mAttachment.Url := 'https://beispiel.youtrack.cloud/api/files/1-2?sign=x';
  mDetails.Attachments := [mAttachment];
  Assert.AreEqual(mAttachment.Url, TAtlasIssuePreview.ImageUrl(mDetails, 'skizze.png'), 'Name des Anhangs');
  Assert.AreEqual('https://h.de/a.png', TAtlasIssuePreview.ImageUrl(mDetails, ' https://h.de/a.png '));
  Assert.AreEqual('', TAtlasIssuePreview.ImageUrl(mDetails, 'fehlt.png'));
end;

procedure TAtlasIssuePreviewTests.MayLoadOnlyFromApiServer;
const
  cApi = 'https://beispiel.youtrack.cloud';
begin
  Assert.IsTrue(TAtlasIssuePreview.MayLoad('https://beispiel.youtrack.cloud/api/files/1?sign=x', cApi));
  Assert.IsFalse(TAtlasIssuePreview.MayLoad('https://boese.example.com/pixel.png', cApi), 'fremder Rechner');
  Assert.IsFalse(TAtlasIssuePreview.MayLoad('http://beispiel.youtrack.cloud/a.png', 'http://beispiel.youtrack.cloud'),
    'nur https');
  Assert.IsFalse(TAtlasIssuePreview.MayLoad('https://user@beispiel.youtrack.cloud/a.png', cApi), 'mit Benutzer');
  Assert.IsFalse(TAtlasIssuePreview.MayLoad('https://beispiel.youtrack.cloud/a.png', ''));
  Assert.IsFalse(TAtlasIssuePreview.MayLoad('skizze.png', cApi), 'relativ');
end;

procedure TAtlasIssuePreviewTests.MayBrowseOnlyWebWithoutUser;
begin
  Assert.IsTrue(TAtlasIssuePreview.MayBrowse('https://github.com/a/b/issues/1'));
  Assert.IsTrue(TAtlasIssuePreview.MayBrowse('http://intern/issue/ATL-1'));
  Assert.IsFalse(TAtlasIssuePreview.MayBrowse('file:///C:/Windows/notepad.exe'));
  Assert.IsFalse(TAtlasIssuePreview.MayBrowse('javascript:alert(1)'));
  Assert.IsFalse(TAtlasIssuePreview.MayBrowse('https://user:pass@h.de/'));
end;

procedure TAtlasIssuePreviewTests.FixPerError;
begin
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.Unauthorized) = TAtlasIssueFix.EnterToken);
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.NotConfigured) = TAtlasIssueFix.Settings);
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.NotFound) = TAtlasIssueFix.Browser);
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.Timeout) = TAtlasIssueFix.Retry);
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.Network) = TAtlasIssueFix.Retry);
  Assert.IsTrue(TAtlasIssuePreview.FixOf(TAtlasCiFetchError.None) = TAtlasIssueFix.None);
end;

procedure TAtlasIssuePreviewTests.KeyFromInput;
begin
  Assert.AreEqual('#753', TAtlasIssuePreview.KeyOf('github', '#753'));
  Assert.AreEqual('#753', TAtlasIssuePreview.KeyOf('github', ' 0753 '));
  Assert.AreEqual('#753', TAtlasIssuePreview.KeyOf('github', 'https://github.com/a/b/issues/753#issuecomment-1'));
  Assert.AreEqual('', TAtlasIssuePreview.KeyOf('github', 'ATL-1'));
  Assert.AreEqual('', TAtlasIssuePreview.KeyOf('github', '#0'));
  Assert.AreEqual('ATL-12', TAtlasIssuePreview.KeyOf('youtrack', 'atl-12'));
  Assert.AreEqual('ATL-12', TAtlasIssuePreview.KeyOf('youtrack', 'https://firma.youtrack.cloud/issue/ATL-12/'));
  Assert.AreEqual('ATL-12', TAtlasIssuePreview.KeyOf('youtrack', 'https://firma.youtrack.cloud/issue/ATL-12?x=1'));
  Assert.AreEqual('', TAtlasIssuePreview.KeyOf('youtrack', '12'));
  Assert.AreEqual('', TAtlasIssuePreview.KeyOf('youtrack', 'ATL-'));
  Assert.AreEqual('', TAtlasIssuePreview.KeyOf('youtrack', 'ATL 12'));
  Assert.AreEqual('#753', TAtlasIssuePreview.KeyExample('github'));
  Assert.AreEqual('ATL-123', TAtlasIssuePreview.KeyExample('youtrack'));
end;

procedure TAtlasIssuePreviewTests.SafeFileNames;
begin
  Assert.AreEqual('log.txt', TAtlasIssuePreview.SafeFileName('log.txt'));
  Assert.AreEqual('boese.exe', TAtlasIssuePreview.SafeFileName('..\..\Windows\boese.exe'));
  Assert.AreEqual('passwd', TAtlasIssuePreview.SafeFileName('../../etc/passwd'));
  Assert.AreEqual('a_b_.txt', TAtlasIssuePreview.SafeFileName('a:b?.txt'));
  Assert.AreEqual('bashrc', TAtlasIssuePreview.SafeFileName('.bashrc'));
  Assert.AreEqual('anhang', TAtlasIssuePreview.SafeFileName(' .. '));
  Assert.AreEqual(Integer(120), Integer(Length(TAtlasIssuePreview.SafeFileName(StringOfChar('x', 300)))));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssuePreviewTests);

end.
