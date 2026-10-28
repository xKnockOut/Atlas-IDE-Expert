unit Atlas.Core.Tracker.PaletteSearch.Tests;

// Tests der Issue-Suche in der Befehlspalette (#1270) ohne Server und ohne
// VCL: Erkennung des Auslösers ("#", Projektkürzel mit "-", Befehlstext),
// Entprellung mit festen Zeitwerten statt Zeitgeber, Aufbau der Such- und
// Leseadressen für GitHub und YouTrack, Search und Lookup über einen
// Transport mit festen Antworten (Beispieldateien in Tests\Data), Zeilen
// der Palette und die Liste der zuletzt geöffneten Issues.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasIssuePaletteSearchTests = class
  public
    /// <summary>GitHub: "#" allein, "#42", "#Text"; Kürzel mit "-" gehört den Befehlen.</summary>
    [Test]
    procedure ParseGitHub;
    /// <summary>YouTrack: "ATL-12", "ATL-Text", "ATL-", "#42" als ATL-42, Groß-/Kleinschreibung.</summary>
    [Test]
    procedure ParseYouTrack;
    /// <summary>Befehlstext, leere Eingabe und fehlender Tracker bleiben bei den Befehlen.</summary>
    [Test]
    procedure ParseKeepsCommands;
    [Test]
    procedure QueryCompareAndHighlight;
    /// <summary>Tippen in schneller Folge: genau eine Anfrage, DelayMs nach der letzten Eingabe.</summary>
    [Test]
    procedure DebounceOneRequestAfterTyping;
    /// <summary>Nichts fällig ohne Eingabe und nach Clear; Wartezeit bis zur Fälligkeit.</summary>
    [Test]
    procedure DebounceClearAndWait;
    /// <summary>Höchstens eine Anfrage je DelayMs, auch bei Eingaben genau im Takt.</summary>
    [Test]
    procedure DebounceAtMostOncePerDelay;
    /// <summary>GitHub: Suchadresse mit Repository, ohne Abfrage der Einstellungen, Grenze 1..100.</summary>
    [Test]
    procedure GitHubTextSearchUrl;
    /// <summary>YouTrack: "project: ATL Text" statt der Abfrage der Einstellungen; Leseadresse einer Kennung.</summary>
    [Test]
    procedure YouTrackSearchAndLookupUrl;
    [Test]
    procedure GitHubSearchAndLookupOverTransport;
    [Test]
    procedure YouTrackSearchAndLookupOverTransport;
    /// <summary>Fehler: ohne Projekt nicht konfiguriert, 401, 404, Zeitgrenze, ungültige Antwort.</summary>
    [Test]
    procedure SearchErrors;
    [Test]
    procedure RowShowsKeyTitleStateAssignee;
    /// <summary>Zuletzt geöffnete zuerst, doppelte entfallen, getrennt je Tracker, höchstens MaxRecent.</summary>
    [Test]
    procedure RecentOrderAndLimits;
    /// <summary>JSON hin und zurück; andere Version oder kaputtes JSON = leer; Datei atomar.</summary>
    [Test]
    procedure RecentRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.PaletteSearch;

type
  /// <summary>Transport mit festen Antworten je Adressanfang; merkt die Adressen.</summary>
  TSearchTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
    FFail: TAtlasCiFetchError;
  public
    Calls: TArray<string>;
    procedure Answer(const APrefix: string; AStatus: Integer; const AText: string);
    procedure FailWith(AError: TAtlasCiFetchError);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TSearchTransport.Answer(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

procedure TSearchTransport.FailWith(AError: TAtlasCiFetchError);
begin
  FFail := AError;
end;

function TSearchTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AStatus := 0;
  AText := '';
  AError := FFail;
  if FFail <> TAtlasCiFetchError.None then
    Exit(False);
  for mIndex := 0 to High(FPrefixes) do
    if Copy(AUrl, 1, Length(FPrefixes[mIndex])) = FPrefixes[mIndex] then
    begin
      AStatus := FStatus[mIndex];
      AText := FTexts[mIndex];
      Exit(True);
    end;
  AStatus := 404;
  Result := True;
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  mDirectory, mFileName: string;
begin
  mDirectory := ExtractFileDir(ParamStr(0));
  while mDirectory <> '' do
  begin
    mFileName := TPath.Combine(mDirectory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(mFileName) then
      Exit(TFile.ReadAllText(mFileName, TEncoding.UTF8));
    if ExtractFileDir(mDirectory) = mDirectory then
      Break;
    mDirectory := ExtractFileDir(mDirectory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', 'label:bug');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud/', 'ATL', 'for: me #Unresolved');
end;

function Issue(const AKey, ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Title := ATitle;
end;

function KindOf(const ATarget: TAtlasTrackerTarget; const APattern: string): TAtlasIssueSearchKind;
begin
  Result := TAtlasIssuePaletteSearch.Parse(ATarget, APattern).Kind;
end;

{ TAtlasIssuePaletteSearchTests }

procedure TAtlasIssuePaletteSearchTests.ParseGitHub;
var
  mQuery: TAtlasIssueSearchQuery;
begin
  Assert.IsTrue(KindOf(GitHubTarget, '#') = TAtlasIssueSearchKind.Recent);
  Assert.IsTrue(KindOf(GitHubTarget, '  #  ') = TAtlasIssueSearchKind.Recent, 'Leerzeichen zählen nicht');
  mQuery := TAtlasIssuePaletteSearch.Parse(GitHubTarget, '#42');
  Assert.IsTrue(mQuery.Kind = TAtlasIssueSearchKind.Key);
  Assert.AreEqual('#42', mQuery.Key);
  Assert.AreEqual('#42', TAtlasIssuePaletteSearch.Parse(GitHubTarget, '#042').Key, 'ohne führende Null');
  mQuery := TAtlasIssuePaletteSearch.Parse(GitHubTarget, '#Speicherleck beim Schließen ');
  Assert.IsTrue(mQuery.Kind = TAtlasIssueSearchKind.Text);
  Assert.AreEqual('Speicherleck beim Schließen', mQuery.Text);
  Assert.AreEqual('0', TAtlasIssuePaletteSearch.Parse(GitHubTarget, '#0').Text, 'keine Nummer: Text');
  // "owner/repo" ist kein Kürzel: "atlas-…" bleibt bei den Befehlen.
  Assert.IsTrue(KindOf(GitHubTarget, 'ATL-12') = TAtlasIssueSearchKind.None);
  Assert.IsTrue(KindOf(GitHubTarget, 'beispiel/atlas-1') = TAtlasIssueSearchKind.None);
end;

procedure TAtlasIssuePaletteSearchTests.ParseYouTrack;
var
  mQuery: TAtlasIssueSearchQuery;
begin
  mQuery := TAtlasIssuePaletteSearch.Parse(YouTrackTarget, 'ATL-12');
  Assert.IsTrue(mQuery.Kind = TAtlasIssueSearchKind.Key);
  Assert.AreEqual('ATL-12', mQuery.Key);
  Assert.AreEqual('ATL-12', TAtlasIssuePaletteSearch.Parse(YouTrackTarget, 'atl-12').Key, 'Kürzel groß');
  Assert.AreEqual('ATL-42', TAtlasIssuePaletteSearch.Parse(YouTrackTarget, '#42').Key, 'Nummer im Projekt');
  Assert.AreEqual('ATL-7', TAtlasIssuePaletteSearch.Parse(YouTrackTarget, '#atl-7').Key);
  mQuery := TAtlasIssuePaletteSearch.Parse(YouTrackTarget, 'ATL-Speicher');
  Assert.IsTrue(mQuery.Kind = TAtlasIssueSearchKind.Text);
  Assert.AreEqual('Speicher', mQuery.Text);
  Assert.AreEqual('Speicherleck', TAtlasIssuePaletteSearch.Parse(YouTrackTarget, '#Speicherleck').Text);
  Assert.IsTrue(KindOf(YouTrackTarget, 'ATL-') = TAtlasIssueSearchKind.Recent);
  Assert.IsTrue(KindOf(YouTrackTarget, '#') = TAtlasIssueSearchKind.Recent);
  // Ohne Projekt keine Kennung aus "#42", nur Text; Kürzel mit Leerzeichen nie als Auslöser.
  Assert.IsTrue(KindOf(TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', '', ''), '#42') =
    TAtlasIssueSearchKind.Text);
  Assert.IsTrue(KindOf(TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', 'Atlas IDE', ''),
    'Atlas IDE-3') = TAtlasIssueSearchKind.None);
end;

procedure TAtlasIssuePaletteSearchTests.ParseKeepsCommands;
begin
  Assert.IsTrue(KindOf(YouTrackTarget, '') = TAtlasIssueSearchKind.None);
  Assert.IsTrue(KindOf(YouTrackTarget, 'Projekt erzeugen') = TAtlasIssueSearchKind.None);
  Assert.IsTrue(KindOf(YouTrackTarget, 'ATLAS') = TAtlasIssueSearchKind.None, 'Kürzel ohne "-"');
  Assert.IsTrue(KindOf(YouTrackTarget, 'Atlas-Optionen') = TAtlasIssueSearchKind.None, 'nur Anfang gleich');
  Assert.IsTrue(KindOf(YouTrackTarget, 'x #12') = TAtlasIssueSearchKind.None, '"#" nur am Anfang');
  Assert.IsTrue(KindOf(TAtlasTrackerTarget.Create('', '', '', ''), '#42') = TAtlasIssueSearchKind.None,
    'ohne Tracker');
end;

procedure TAtlasIssuePaletteSearchTests.QueryCompareAndHighlight;
var
  mKey, mText: TAtlasIssueSearchQuery;
begin
  mKey := TAtlasIssuePaletteSearch.Parse(YouTrackTarget, 'ATL-12');
  mText := TAtlasIssuePaletteSearch.Parse(YouTrackTarget, '#Speicher');
  Assert.AreEqual('ATL-12', mKey.Highlight);
  Assert.AreEqual('Speicher', mText.Highlight);
  Assert.AreEqual('', TAtlasIssueSearchQuery.None.Highlight);
  Assert.IsTrue(mText.SameAs(TAtlasIssuePaletteSearch.Parse(YouTrackTarget, 'atl-speicher')),
    'gleiche Suche auf beiden Wegen');
  Assert.IsFalse(mText.SameAs(mKey));
end;

procedure TAtlasIssuePaletteSearchTests.DebounceOneRequestAfterTyping;
var
  mDebounce: TAtlasIssueSearchDebounce;
  mText: string;
begin
  mDebounce := TAtlasIssueSearchDebounce.Create(TAtlasIssuePaletteSearch.DelayMs);
  try
    mDebounce.Input('S', 1000);
    Assert.IsFalse(mDebounce.Take(1100, mText));
    mDebounce.Input('Sp', 1100);
    mDebounce.Input('Spe', 1250);
    Assert.AreEqual(250, mDebounce.WaitMs(1300), 'ab der letzten Eingabe');
    Assert.IsFalse(mDebounce.Take(1549, mText));
    Assert.AreEqual('', mText);
    Assert.IsTrue(mDebounce.Take(1550, mText));
    Assert.AreEqual('Spe', mText);
    Assert.AreEqual(1, mDebounce.Sent, 'eine Anfrage für drei Eingaben');
    Assert.IsFalse(mDebounce.Pending);
    Assert.IsFalse(mDebounce.Take(5000, mText), 'nichts mehr fällig');
    Assert.AreEqual(1, mDebounce.Sent);
  finally
    mDebounce.Free;
  end;
end;

procedure TAtlasIssuePaletteSearchTests.DebounceClearAndWait;
var
  mDebounce: TAtlasIssueSearchDebounce;
  mText: string;
begin
  mDebounce := TAtlasIssueSearchDebounce.Create(300);
  try
    Assert.AreEqual(-1, mDebounce.WaitMs(0));
    mDebounce.Input('ATL-1', 10);
    Assert.IsTrue(mDebounce.Pending);
    Assert.AreEqual(300, mDebounce.WaitMs(10));
    Assert.AreEqual(0, mDebounce.WaitMs(400), 'überfällig');
    mDebounce.Clear;
    Assert.AreEqual(-1, mDebounce.WaitMs(400));
    Assert.IsFalse(mDebounce.Take(400, mText));
    Assert.AreEqual(0, mDebounce.Sent);
  finally
    mDebounce.Free;
  end;
  // Negative Wartezeit wie 0: sofort fällig.
  mDebounce := TAtlasIssueSearchDebounce.Create(-5);
  try
    mDebounce.Input('x', 7);
    Assert.IsTrue(mDebounce.Take(7, mText));
  finally
    mDebounce.Free;
  end;
end;

procedure TAtlasIssuePaletteSearchTests.DebounceAtMostOncePerDelay;
var
  mDebounce: TAtlasIssueSearchDebounce;
  mText: string;
  mNow: Integer;
begin
  mDebounce := TAtlasIssueSearchDebounce.Create(300);
  try
    // Eine Eingabe alle 300 ms, nach jeder Pause abgefragt: je Takt eine Anfrage, nie zwei im selben.
    mNow := 0;
    while mNow < 3000 do
    begin
      mDebounce.Input('T' + IntToStr(mNow), mNow);
      Assert.IsFalse(mDebounce.Take(mNow + 299, mText));
      Assert.IsTrue(mDebounce.Take(mNow + 300, mText));
      Assert.AreEqual('T' + IntToStr(mNow), mText);
      Inc(mNow, 300);
    end;
    Assert.AreEqual(10, mDebounce.Sent);
    // Eingabe vor der letzten Anfrage (Uhr springt zurück): nicht vor 300 ms nach der Anfrage.
    mDebounce.Input('spät', 3000);
    Assert.AreEqual(300, mDebounce.WaitMs(3000));
    mDebounce.Input('früh', 2900);
    Assert.AreEqual(300, mDebounce.WaitMs(3000), 'Mindestabstand zur letzten Anfrage');
  finally
    mDebounce.Free;
  end;
end;

procedure TAtlasIssuePaletteSearchTests.GitHubTextSearchUrl;
begin
  Assert.AreEqual('https://api.github.com/search/issues?q=repo%3Abeispiel/atlas%20is%3Aissue%20Speicherleck' +
    '&per_page=20', TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, ' Speicherleck ', 20));
  Assert.AreEqual(0, Pos('label', TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, 'x', 20)),
    'Abfrage der Einstellungen gilt nicht');
  Assert.IsTrue(TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, 'x', 500).EndsWith('&per_page=100'));
  Assert.IsTrue(TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, 'x', 0).EndsWith('&per_page=1'));
  Assert.AreEqual('', TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, '  ', 20));
  Assert.AreEqual('', TAtlasGitHubTracker.TextSearchUrl(TAtlasTrackerTarget.Create('github', '', '', ''), 'x', 20));
  Assert.IsTrue(TAtlasGitHubTracker.TextSearchUrl(TAtlasTrackerTarget.Create('github', 'https://git.firma.de',
    'team/kasse', ''), 'x', 20).StartsWith('https://git.firma.de/api/v3/search/issues?q=repo%3Ateam/kasse'),
    'GitHub Enterprise');
end;

procedure TAtlasIssuePaletteSearchTests.YouTrackSearchAndLookupUrl;
var
  mUrl: string;
begin
  mUrl := TAtlasYouTrackTracker.TextSearchUrl(YouTrackTarget, ' Speicher leck ', 20);
  Assert.IsTrue(mUrl.StartsWith('https://beispiel.youtrack.cloud/api/issues?query=project%3A%20ATL%20Speicher%20leck' +
    '&fields='), mUrl);
  Assert.IsTrue(mUrl.EndsWith('&$top=20'), mUrl);
  Assert.AreEqual(0, Pos('Unresolved', mUrl), 'Abfrage der Einstellungen gilt nicht');
  Assert.IsTrue(mUrl.Contains('fullName'), 'Zuständig wird mitgelesen');
  Assert.AreEqual('', TAtlasYouTrackTracker.TextSearchUrl(YouTrackTarget, '', 20));
  Assert.AreEqual('', TAtlasYouTrackTracker.TextSearchUrl(TAtlasTrackerTarget.Create('youtrack', '', 'ATL', ''), 'x',
    20), 'ohne Server');
  mUrl := TAtlasYouTrackTracker.LookupUrl(YouTrackTarget, 'ATL-12');
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues/ATL-12?fields=idReadable%2CnumberInProject%2Csummary' +
    '%2CcustomFields%28name%2Cvalue%28name%2Cpresentation%2Clogin%2CfullName%29%29', mUrl,
    'dieselben Felder wie die Liste');
  Assert.AreEqual('', TAtlasYouTrackTracker.LookupUrl(YouTrackTarget, 'ATL 1/../x'));
  Assert.AreEqual('', TAtlasYouTrackTracker.LookupUrl(YouTrackTarget, ''));
end;

procedure TAtlasIssuePaletteSearchTests.GitHubSearchAndLookupOverTransport;
var
  mTransport: TSearchTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mIssues: TArray<TAtlasTrackerIssue>;
  mIssue: TAtlasTrackerIssue;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TSearchTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://api.github.com/search/issues?q=repo%3Abeispiel/atlas', 200,
    Fixture('GitHub', 'search-issues.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753', 200,
    Fixture('GitHub', 'issue-details.json'));
  Assert.IsTrue(mProvider.Search(GitHubTarget, mTransportRef, 'Willkommensseite', 5000, 20, mIssues, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.None);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  Assert.AreEqual(TAtlasGitHubTracker.TextSearchUrl(GitHubTarget, 'Willkommensseite', 20), mTransport.Calls[0]);
  Assert.AreEqual(3, Integer(Length(mIssues)), 'ohne Pull Requests');
  Assert.AreEqual('#753', mIssues[0].Key);
  Assert.AreEqual('beispiel', mIssues[0].Assignee);
  Assert.IsTrue(mProvider.Search(GitHubTarget, mTransportRef, 'Willkommensseite', 5000, 1, mIssues, mError));
  Assert.AreEqual(1, Integer(Length(mIssues)), 'höchstens AMax');
  Assert.IsTrue(mProvider.Lookup(GitHubTarget, mTransportRef, '#753', 5000, mIssue, mError));
  Assert.AreEqual('#753', mIssue.Key);
  Assert.AreEqual(753, mIssue.Number);
  Assert.AreEqual('closed (not planned)', mIssue.State);
  Assert.AreEqual('xKnockOut, kollege', mIssue.Assignee);
  Assert.AreEqual(3, Integer(Length(mTransport.Calls)), 'Lookup ohne Kommentare und Zeitleiste');
  mIssues := nil;
end;

procedure TAtlasIssuePaletteSearchTests.YouTrackSearchAndLookupOverTransport;
var
  mTransport: TSearchTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mIssues: TArray<TAtlasTrackerIssue>;
  mIssue: TAtlasTrackerIssue;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mTransport := TSearchTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues?query=', 200, Fixture('YouTrack', 'issues.json'));
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues/ATL-12?', 200,
    Fixture('YouTrack', 'issue-lookup.json'));
  Assert.IsTrue(mProvider.Search(YouTrackTarget, mTransportRef, 'Tracker', 5000, 20, mIssues, mError));
  Assert.AreEqual(TAtlasYouTrackTracker.TextSearchUrl(YouTrackTarget, 'Tracker', 20), mTransport.Calls[0]);
  Assert.AreEqual('ATL-123', mIssues[0].Key);
  Assert.AreEqual('In Progress', mIssues[0].State);
  Assert.AreEqual('Beispiel', mIssues[0].Assignee);
  Assert.IsTrue(mProvider.Lookup(YouTrackTarget, mTransportRef, 'ATL-12', 5000, mIssue, mError));
  Assert.AreEqual(TAtlasYouTrackTracker.LookupUrl(YouTrackTarget, 'ATL-12'), mTransport.Calls[1]);
  Assert.AreEqual('ATL-12', mIssue.Key);
  Assert.AreEqual(12, mIssue.Number);
  Assert.AreEqual('Speicherleck beim Schließen', mIssue.Title);
  Assert.AreEqual('Offen', mIssue.State);
  Assert.AreEqual('Marie Beispiel', mIssue.Assignee, 'Anzeigename vor Login');
  mIssues := nil;
end;

procedure TAtlasIssuePaletteSearchTests.SearchErrors;
var
  mTransport: TSearchTransport;
  mTransportRef: IAtlasCiTransport;
  mGitHub, mYouTrack: IAtlasTrackerProvider;
  mIssues: TArray<TAtlasTrackerIssue>;
  mIssue: TAtlasTrackerIssue;
  mError: TAtlasCiFetchError;
begin
  mGitHub := TAtlasGitHubTracker.Create;
  mYouTrack := TAtlasYouTrackTracker.Create;
  mTransport := TSearchTransport.Create;
  mTransportRef := mTransport;
  // Ohne Projekt bzw. ohne Transport: keine Anfrage.
  Assert.IsFalse(mGitHub.Search(TAtlasTrackerTarget.Create('github', '', '', ''), mTransportRef, 'x', 5000, 20,
    mIssues, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured);
  Assert.IsFalse(mYouTrack.Lookup(YouTrackTarget, nil, 'ATL-1', 5000, mIssue, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured);
  Assert.IsFalse(mGitHub.Lookup(GitHubTarget, mTransportRef, 'ATL-1', 5000, mIssue, mError), 'keine GitHub-Kennung');
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured);
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)));
  // Antworten des Servers.
  mTransport.Answer('https://api.github.com/search/', 401, '{"message":"Bad credentials"}');
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues/ATL-9?', 200, 'kein JSON');
  Assert.IsFalse(mGitHub.Search(GitHubTarget, mTransportRef, 'x', 5000, 20, mIssues, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Unauthorized);
  Assert.IsFalse(mGitHub.Lookup(GitHubTarget, mTransportRef, '#99', 5000, mIssue, mError), 'unbekannte Adresse');
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound);
  Assert.IsFalse(mYouTrack.Lookup(YouTrackTarget, mTransportRef, 'ATL-9', 5000, mIssue, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid);
  Assert.AreEqual('', mIssue.Key);
  // Zeitgrenze des Transports kommt unverändert an.
  mTransport.FailWith(TAtlasCiFetchError.Timeout);
  Assert.IsFalse(mYouTrack.Search(YouTrackTarget, mTransportRef, 'x', 5000, 20, mIssues, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Timeout);
  Assert.AreEqual(0, Integer(Length(mIssues)));
end;

procedure TAtlasIssuePaletteSearchTests.RowShowsKeyTitleStateAssignee;
var
  mIssue: TAtlasTrackerIssue;
  mRow: TAtlasCommand;
  mRows: TArray<TAtlasCommand>;
begin
  mIssue := Issue('ATL-12', 'Speicherleck beim Schließen');
  mIssue.State := 'Offen';
  mIssue.Assignee := 'Marie Beispiel';
  mRow := TAtlasIssuePaletteSearch.Row(mIssue);
  Assert.AreEqual('ATL-12', mRow.Id);
  Assert.AreEqual('ATL-12  Speicherleck beim Schließen', mRow.Caption);
  Assert.AreEqual('Offen', mRow.Badge);
  Assert.AreEqual('Marie Beispiel', mRow.Path);
  Assert.AreEqual('Speicherleck beim Schließen', mRow.Description);
  Assert.IsFalse(mRow.IsAtlas);
  Assert.AreEqual('#5', TAtlasIssuePaletteSearch.Row(Issue('#5', '')).Caption, 'ohne Titel nur die Kennung');
  mRows := TAtlasIssuePaletteSearch.Rows([mIssue, Issue('ATL-7', 'Zweites')]);
  Assert.AreEqual(2, Integer(Length(mRows)));
  Assert.AreEqual('ATL-7', mRows[1].Id);
  Assert.AreEqual(0, Integer(Length(TAtlasIssuePaletteSearch.Rows(nil))));
end;

procedure TAtlasIssuePaletteSearchTests.RecentOrderAndLimits;
var
  mRecent: TAtlasRecentIssues;
  mItems: TArray<TAtlasTrackerIssue>;
  mIssue: TAtlasTrackerIssue;
  mIndex: Integer;
begin
  mRecent := TAtlasRecentIssues.Create;
  try
    mRecent.Add(YouTrackTarget, Issue('ATL-1', 'Eins'));
    mRecent.Add(YouTrackTarget, Issue('ATL-2', 'Zwei'));
    mRecent.Add(GitHubTarget, Issue('#3', 'Drei'));
    mRecent.Add(YouTrackTarget, Issue('atl-1', 'Eins neu'));
    mItems := mRecent.Items(YouTrackTarget);
    Assert.AreEqual(2, Integer(Length(mItems)), 'doppelte Kennung entfällt, GitHub getrennt');
    Assert.AreEqual('atl-1', mItems[0].Key, 'zuletzt geöffnet zuerst');
    Assert.AreEqual('Eins neu', mItems[0].Title);
    Assert.AreEqual('ATL-2', mItems[1].Key);
    Assert.AreEqual(1, Integer(Length(mRecent.Items(GitHubTarget))));
    // Gleicher Server, andere Abfrage: derselbe Tracker.
    Assert.AreEqual(2, Integer(Length(mRecent.Items(TAtlasTrackerTarget.Create('youtrack',
      'https://BEISPIEL.youtrack.cloud', 'atl', '')))));
    // Ohne Server oder Kennung nichts merken; Labels und Pull Request nicht.
    mRecent.Add(TAtlasTrackerTarget.Create('youtrack', '', 'ATL', ''), Issue('ATL-5', 'ohne Server'));
    mRecent.Add(YouTrackTarget, Issue('  ', 'ohne Kennung'));
    Assert.AreEqual(3, mRecent.Count);
    mIssue := Issue('#4', 'Mit Labels');
    mIssue.Labels := ['bug'];
    mIssue.PullRequest.Number := 9;
    mRecent.Add(GitHubTarget, mIssue);
    Assert.AreEqual(0, Integer(Length(mRecent.Items(GitHubTarget)[0].Labels)));
    Assert.AreEqual(0, mRecent.Items(GitHubTarget)[0].PullRequest.Number);
    // Höchstens MaxRecent je Tracker, MaxStored insgesamt.
    for mIndex := 1 to TAtlasRecentIssues.MaxStored + 5 do
      mRecent.Add(YouTrackTarget, Issue('ATL-' + IntToStr(100 + mIndex), 'Nr. ' + IntToStr(mIndex)));
    Assert.AreEqual(TAtlasRecentIssues.MaxStored, mRecent.Count);
    mItems := mRecent.Items(YouTrackTarget);
    Assert.AreEqual(TAtlasRecentIssues.MaxRecent, Integer(Length(mItems)));
    Assert.AreEqual('ATL-' + IntToStr(100 + TAtlasRecentIssues.MaxStored + 5), mItems[0].Key);
    Assert.AreEqual(0, Integer(Length(mRecent.Items(GitHubTarget))), 'älteste verdrängt');
    mRecent.Clear;
    Assert.AreEqual(0, mRecent.Count);
  finally
    mRecent.Free;
  end;
  mItems := nil;
end;

procedure TAtlasIssuePaletteSearchTests.RecentRoundTrip;
var
  mRecent, mCopy: TAtlasRecentIssues;
  mIssue: TAtlasTrackerIssue;
  mItems: TArray<TAtlasTrackerIssue>;
  mFileName: string;
begin
  mFileName := TPath.Combine(TPath.GetTempPath, 'atlas-recent-' + IntToStr(Random(MaxInt)) + '.json');
  mRecent := TAtlasRecentIssues.Create;
  mCopy := TAtlasRecentIssues.Create;
  try
    mIssue := Issue('ATL-12', 'Speicherleck "beim" Schließen');
    mIssue.Number := 12;
    mIssue.State := 'Offen';
    mIssue.Assignee := 'Marie Beispiel';
    mRecent.Add(YouTrackTarget, Issue('ATL-1', 'Eins'));
    mRecent.Add(YouTrackTarget, mIssue);
    Assert.IsTrue(mCopy.Parse(mRecent.ToJson));
    mItems := mCopy.Items(YouTrackTarget);
    Assert.AreEqual(2, Integer(Length(mItems)));
    Assert.AreEqual('ATL-12', mItems[0].Key);
    Assert.AreEqual(12, mItems[0].Number);
    Assert.AreEqual('Speicherleck "beim" Schließen', mItems[0].Title);
    Assert.AreEqual('Offen', mItems[0].State);
    Assert.AreEqual('Marie Beispiel', mItems[0].Assignee);
    Assert.AreEqual(0, Pos('youtrack.cloud/', mRecent.ToJson), 'nur der Server, keine Adresse');
    // Andere Version, kaputtes JSON, Einträge ohne Kennung.
    Assert.IsFalse(mCopy.Parse('{"version":2,"issues":[{"tracker":"a","key":"B-1"}]}'));
    Assert.AreEqual(0, mCopy.Count);
    Assert.IsFalse(mCopy.Parse('kein JSON'));
    Assert.IsTrue(mCopy.Parse('{"version":1,"issues":[{"tracker":"a"},{"key":"B-1"},3,{"tracker":"a","key":"B-2"}]}'));
    Assert.AreEqual(1, mCopy.Count);
    // Datei: fehlt = leer, geschrieben = gleich.
    Assert.IsTrue(mCopy.LoadFromFile(mFileName) = TAtlasDataLoad.Missing);
    Assert.IsTrue(mRecent.SaveToFile(mFileName));
    Assert.IsTrue(mCopy.LoadFromFile(mFileName) = TAtlasDataLoad.Loaded);
    Assert.AreEqual(2, Integer(Length(mCopy.Items(YouTrackTarget))));
    TFile.WriteAllText(mFileName, '[1]');
    Assert.IsTrue(mCopy.LoadFromFile(mFileName) = TAtlasDataLoad.Renewed);
    Assert.AreEqual(0, mCopy.Count);
  finally
    mCopy.Free;
    mRecent.Free;
    System.SysUtils.DeleteFile(mFileName);
    System.SysUtils.DeleteFile(mFileName + TAtlasDataFile.DefectExtension);
  end;
  mItems := nil;
  // Gemeldete Datendateien vergessen: Das Register bliebe sonst als Leck stehen.
  TAtlasDataFile.ForgetReports;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasIssuePaletteSearchTests);

end.
