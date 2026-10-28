unit Atlas.Core.Tracker.QueryTest.Tests;

// Tests zu „Testen“ im Dialog „Abfrage bearbeiten“ (#1263) ohne Netz: Zuordnung
// der Antworten aus Beispieldateien (200 leer, 200 mit Treffern, 400/422 mit
// Text, 401, 404, HTML statt JSON) zu den Ursachen, gesendete Abfrage ohne
// Token, Erkennung der Sprache von YouTrack (localeSettings bzw. Probe) mit
// Tipp auf die deutsche Vorlage, Vorlagen je Sprache und die Vorgabe einer
// Verbindung mit erkannter Sprache.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerQueryTestTests = class
  public
    /// <summary>Abnahme: Antworten aus Beispieldateien → Meldungen.</summary>
    [Test]
    procedure YouTrackAnswersFromFixtures;
    [Test]
    procedure GitHubAnswersFromFixtures;
    [Test]
    procedure TrackerMessageFromErrorBodies;
    /// <summary>Abnahme: Die angezeigte Abfrage entspricht genau der gesendeten; ohne Token kein Netz.</summary>
    [Test]
    procedure SentQueryMatchesRequest;
    /// <summary>Abnahme: Deutsche Oberfläche: englische Vorlage leer mit Tipp, deutsche mit Treffern.</summary>
    [Test]
    procedure GermanInterfaceSuggestsGermanTemplate;
    [Test]
    procedure DetectLanguageWithoutLocaleRight;
    /// <summary>Abnahme: Vorlagen je Sprache; GitHub nur Englisch, ohne Sprint.</summary>
    [Test]
    procedure TemplatesPerLanguage;
    /// <summary>Abnahme: Neue YouTrack-Verbindung zu einem deutschen Server: Vorgabe „Mir zugewiesen“ auf Deutsch.
    /// </summary>
    [Test]
    procedure CheckedConnectionGetsGermanDefault;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Text.Uris,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.QueryTest,
  Atlas.Core.Tracker.Templates;

type
  /// <summary>Transport mit festen Antworten je Adressanfang (erster Treffer gilt); merkt die Adressen.</summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FPrefixes: TArray<string>;
    FStatus: TArray<Integer>;
    FTexts: TArray<string>;
  public
    Calls: TArray<string>;
    destructor Destroy; override;
    procedure Answer(const APrefix: string; AStatus: Integer; const AText: string);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

destructor TFakeTransport.Destroy;
begin
  FPrefixes := nil;
  FStatus := nil;
  FTexts := nil;
  Calls := nil;
  inherited Destroy;
end;

procedure TFakeTransport.Answer(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Calls := Calls + [AUrl];
  AStatus := 0;
  AText := '';
  AError := TAtlasCiFetchError.None;
  for mIndex := 0 to High(FPrefixes) do
    if AUrl.StartsWith(FPrefixes[mIndex]) then
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

function YouTrackTarget(const AQuery: string): TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://yt.local', 'ATL', AQuery);
end;

/// <summary>Anfang der Adresse der Liste zu ATarget (ohne fields und $top).</summary>
function ListPrefix(const ATarget: TAtlasTrackerTarget): string;
begin
  Result := ATarget.Url + '/api/issues?query=' + TTextUris.PercentEncode(TAtlasYouTrackTracker.FullQuery(ATarget)) +
    '&';
end;

function Evaluate(const AProvider: IAtlasTrackerProvider; const ATarget: TAtlasTrackerTarget; AStatus: Integer;
  const AText: string): TAtlasTrackerQueryTestResult;
begin
  Result := TAtlasTrackerQueryTest.Evaluate(AProvider, ATarget, True, AStatus, AText, TAtlasCiFetchError.None);
end;

{ TAtlasTrackerQueryTestTests }

procedure TAtlasTrackerQueryTestTests.YouTrackAnswersFromFixtures;
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mResult: TAtlasTrackerQueryTestResult;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mTarget := YouTrackTarget('assignee: meine #Ungelöst');
  mResult := Evaluate(mProvider, mTarget, 200, Fixture('YouTrack', 'issues.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Found), Ord(mResult.Outcome));
  Assert.AreEqual(2, mResult.Count);
  Assert.IsFalse(mResult.More);
  Assert.AreEqual('ATL-123, ATL-7', string.Join(', ', mResult.Keys));
  mResult := Evaluate(mProvider, mTarget, 200, Fixture('YouTrack', 'issues-empty.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Empty), Ord(mResult.Outcome));
  Assert.AreEqual(0, mResult.Count);
  mResult := Evaluate(mProvider, mTarget, 400, Fixture('YouTrack', 'query-400.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.QueryRejected), Ord(mResult.Outcome));
  Assert.AreEqual('Die Abfrage enthält einen Fehler: Unbekannter Wert „mee“ für das Feld assignee.',
    mResult.TrackerMessage, 'Meldung von YouTrack, einzeilig');
  Assert.AreEqual(400, mResult.HttpStatus);
  mResult := Evaluate(mProvider, mTarget, 401, Fixture('YouTrack', 'users-me-401.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Rejected), Ord(mResult.Outcome));
  mResult := Evaluate(mProvider, mTarget, 403, '');
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Rejected), Ord(mResult.Outcome));
  mResult := Evaluate(mProvider, mTarget, 404, Fixture('YouTrack', 'project-404.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.ProjectUnknown), Ord(mResult.Outcome));
  // Falsche Adresse: Die Anmeldeseite des Portals kommt mit 200.
  mResult := Evaluate(mProvider, mTarget, 200, Fixture('YouTrack', 'login-page.html'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Unreadable), Ord(mResult.Outcome));
  mResult := Evaluate(mProvider, mTarget, 502, '<html>Bad Gateway</html>');
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Unreadable), Ord(mResult.Outcome));
  mResult := Evaluate(mProvider, mTarget, 500, '{"error": "server_error"}');
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.ServerError), Ord(mResult.Outcome));
  Assert.AreEqual(500, mResult.HttpStatus);
  mResult := TAtlasTrackerQueryTest.Evaluate(mProvider, mTarget, False, 0, '', TAtlasCiFetchError.Timeout);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Unreachable), Ord(mResult.Outcome));
  Assert.AreEqual(0, mResult.HttpStatus);
  mResult := Default(TAtlasTrackerQueryTestResult);
end;

procedure TAtlasTrackerQueryTestTests.GitHubAnswersFromFixtures;
var
  mProvider: IAtlasTrackerProvider;
  mTarget: TAtlasTrackerTarget;
  mResult: TAtlasTrackerQueryTestResult;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTarget := TAtlasTrackerTarget.Create('github', '', 'xKnockOut/Atlas', '');
  mResult := Evaluate(mProvider, mTarget, 200, Fixture('GitHub', 'search-issues.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Found), Ord(mResult.Outcome));
  Assert.AreEqual(3, mResult.Count, 'der Pull Request zählt nicht');
  Assert.AreEqual('#753, #612', Copy(string.Join(', ', mResult.Keys), 1, 10));
  Assert.AreEqual(3, Integer(Length(mResult.Keys)));
  mResult := Evaluate(mProvider, mTarget, 200, Fixture('GitHub', 'search-empty.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Empty), Ord(mResult.Outcome));
  mResult := Evaluate(mProvider, mTarget, 422, Fixture('GitHub', 'search-422.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.QueryRejected), Ord(mResult.Outcome));
  Assert.IsTrue(mResult.TrackerMessage.StartsWith('The listed users and repositories cannot be searched'),
    mResult.TrackerMessage);
  mResult := Evaluate(mProvider, mTarget, 401, Fixture('GitHub', 'user-401.json'));
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Rejected), Ord(mResult.Outcome));
  mResult := Default(TAtlasTrackerQueryTestResult);
end;

procedure TAtlasTrackerQueryTestTests.TrackerMessageFromErrorBodies;
var
  mLong: string;
begin
  Assert.AreEqual('', TAtlasTrackerQueryTest.TrackerMessage('<html><body>Fehler</body></html>'), 'HTML nie');
  Assert.AreEqual('Bad credentials', TAtlasTrackerQueryTest.TrackerMessage('{"message": "Bad credentials"}'));
  Assert.AreEqual('kein JSON', TAtlasTrackerQueryTest.TrackerMessage('  kein' + #10 + 'JSON '));
  mLong := StringOfChar('x', 400);
  Assert.AreEqual(TAtlasTrackerQueryTest.MaxMessage, Length(TAtlasTrackerQueryTest.TrackerMessage(mLong)));
end;

procedure TAtlasTrackerQueryTestTests.SentQueryMatchesRequest;
var
  mProvider: IAtlasTrackerProvider;
  mTransport: TFakeTransport;
  mKeep: IAtlasCiTransport;
  mTarget: TAtlasTrackerTarget;
  mResult: TAtlasTrackerQueryTestResult;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mTarget := YouTrackTarget('assignee: meine #Ungelöst');
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/issues', 200, Fixture('YouTrack', 'issues.json'));
  mResult := TAtlasTrackerQueryTest.Run(mProvider, mTarget, mKeep);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Found), Ord(mResult.Outcome));
  Assert.AreEqual('project: ATL assignee: meine #Ungelöst', mResult.SentQuery);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'bei Treffern keine Spracherkennung');
  Assert.IsTrue(mTransport.Calls[0].StartsWith(ListPrefix(mTarget)), 'genau die angezeigte Abfrage');
  // GitHub: mit repo: und is:issue, wie gesendet.
  mProvider := TAtlasGitHubTracker.Create;
  mResult := TAtlasTrackerQueryTest.Run(mProvider, TAtlasTrackerTarget.Create('github', '', 'o/r', ''), nil);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.NoToken), Ord(mResult.Outcome), 'ohne Token kein Netz');
  Assert.AreEqual('assignee:@me state:open repo:o/r is:issue', mResult.SentQuery);
  // GitHub ohne owner/repo: nicht testbar.
  mResult := TAtlasTrackerQueryTest.Run(mProvider, TAtlasTrackerTarget.Create('github', 'https://ghe.firma.de', '',
    ''), mKeep);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.NotConfigured), Ord(mResult.Outcome));
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  mResult := Default(TAtlasTrackerQueryTestResult);
end;

procedure TAtlasTrackerQueryTestTests.GermanInterfaceSuggestsGermanTemplate;
var
  mProvider: IAtlasTrackerProvider;
  mTransport: TFakeTransport;
  mKeep: IAtlasCiTransport;
  mGerman, mEnglish: TAtlasTrackerTarget;
  mResult: TAtlasTrackerQueryTestResult;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mGerman := YouTrackTarget('assignee: meine #Ungelöst');
  mEnglish := YouTrackTarget('assignee: me #Unresolved');
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer(ListPrefix(mGerman), 200, Fixture('YouTrack', 'issues.json'));
  mTransport.Answer(ListPrefix(mEnglish), 200, Fixture('YouTrack', 'issues-empty.json'));
  mTransport.Answer('https://yt.local/api/admin/globalSettings/localeSettings', 200,
    Fixture('YouTrack', 'locale-de.json'));
  mResult := TAtlasTrackerQueryTest.Run(mProvider, mEnglish, mKeep);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Empty), Ord(mResult.Outcome));
  Assert.AreEqual('de', mResult.Language);
  Assert.AreEqual('assignee: meine #Ungelöst', mResult.SuggestedQuery, 'Tipp auf die deutsche Vorlage');
  mResult := TAtlasTrackerQueryTest.Run(mProvider, mGerman, mKeep);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Found), Ord(mResult.Outcome));
  Assert.AreEqual(2, mResult.Count);
  Assert.AreEqual('', mResult.SuggestedQuery);
  // Leer mit der deutschen Vorlage: kein Tipp (es passt einfach nichts).
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/issues', 200, '[]');
  mTransport.Answer('https://yt.local/api/admin/', 200, Fixture('YouTrack', 'locale-de.json'));
  mResult := TAtlasTrackerQueryTest.Run(mProvider, mGerman, mKeep);
  Assert.AreEqual(Ord(TAtlasTrackerQueryOutcome.Empty), Ord(mResult.Outcome));
  Assert.AreEqual('', mResult.SuggestedQuery);
  mResult := Default(TAtlasTrackerQueryTestResult);
end;

procedure TAtlasTrackerQueryTestTests.DetectLanguageWithoutLocaleRight;
var
  mProvider: IAtlasTrackerProvider;
  mTransport: TFakeTransport;
  mKeep: IAtlasCiTransport;
  mTarget, mGerman, mEnglish: TAtlasTrackerTarget;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mTarget := YouTrackTarget('');
  mGerman := YouTrackTarget('assignee: meine #Ungelöst');
  mEnglish := YouTrackTarget('assignee: me #Unresolved');
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  // Kein Recht auf die globalen Einstellungen: Probe mit beiden Vorlagen.
  mTransport.Answer('https://yt.local/api/admin/', 403, Fixture('YouTrack', 'locale-403.json'));
  mTransport.Answer(ListPrefix(mGerman), 200, Fixture('YouTrack', 'issues.json'));
  mTransport.Answer(ListPrefix(mEnglish), 200, '[]');
  Assert.AreEqual('de', TAtlasTrackerQueryTest.DetectLanguage(mProvider, mTarget, mKeep, 5000));
  Assert.AreEqual(3, Integer(Length(mTransport.Calls)));
  // Englische Oberfläche: Die deutsche Vorlage wird abgelehnt, die englische findet nichts.
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/admin/', 403, '');
  mTransport.Answer(ListPrefix(mGerman), 400, Fixture('YouTrack', 'query-400.json'));
  mTransport.Answer(ListPrefix(mEnglish), 200, '[]');
  Assert.AreEqual('en', TAtlasTrackerQueryTest.DetectLanguage(mProvider, mTarget, mKeep, 5000));
  // Beide leer: unbekannt.
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/admin/', 403, '');
  mTransport.Answer('https://yt.local/api/issues', 200, '[]');
  Assert.AreEqual('', TAtlasTrackerQueryTest.DetectLanguage(mProvider, mTarget, mKeep, 5000));
  // GitHub: keine Sprache, kein Netz.
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  // Anbieter in einer Variablen: ein const-Parameter zählt die Referenz nicht.
  mProvider := TAtlasGitHubTracker.Create;
  Assert.AreEqual('', TAtlasTrackerQueryTest.DetectLanguage(mProvider, TAtlasTrackerTarget.Create('github', '', 'o/r',
    ''), mKeep, 5000));
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('de', TAtlasTrackerQueryTest.LanguageOfLocale('{"locale": {"locale": "de_AT"}}'));
  Assert.AreEqual('', TAtlasTrackerQueryTest.LanguageOfLocale('{"locale": {"language": "fr"}}'));
end;

procedure TAtlasTrackerQueryTestTests.TemplatesPerLanguage;
var
  mTemplates: TArray<TAtlasTrackerTemplate>;
  mTemplate: TAtlasTrackerTemplate;
begin
  mTemplates := TAtlasTrackerTemplates.Templates('youtrack', 'de');
  Assert.AreEqual(4, Integer(Length(mTemplates)));
  for mTemplate in mTemplates do
    Assert.AreEqual('de', mTemplate.Language);
  Assert.AreEqual('assignee: meine #Ungelöst', mTemplates[0].Query);
  Assert.AreEqual(8, Integer(Length(TAtlasTrackerTemplates.Templates('youtrack', ''))), 'beide Sprachen');
  Assert.AreEqual('assignee: me #Unresolved', TAtlasTrackerTemplates.QueryOf('youtrack', 'en_US',
    TAtlasTrackerTemplateKind.AssignedToMe));
  mTemplates := TAtlasTrackerTemplates.Templates('github', 'de');
  Assert.AreEqual(3, Integer(Length(mTemplates)), 'GitHub ohne Sprint');
  Assert.AreEqual('en', mTemplates[0].Language, 'GitHub nur Englisch');
  Assert.AreEqual('assignee:@me state:open', mTemplates[0].Query);
  Assert.AreEqual('', TAtlasTrackerTemplates.QueryOf('github', '', TAtlasTrackerTemplateKind.CurrentSprint));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerTemplates.Templates('jira', ''))));
  Assert.AreEqual('', TAtlasTrackerTemplates.DefaultQuery('youtrack', ''), 'ohne Sprache die Vorgabe des Anbieters');
  Assert.AreEqual('de', TAtlasTrackerTemplates.NormalLanguage('de-AT'));
  Assert.AreEqual('', TAtlasTrackerTemplates.NormalLanguage('fr'));
  mTemplates := nil;
end;

procedure TAtlasTrackerQueryTestTests.CheckedConnectionGetsGermanDefault;
var
  mProvider: IAtlasTrackerProvider;
  mTransport: TFakeTransport;
  mKeep: IAtlasCiTransport;
  mConnection: TAtlasTrackerConnection;
  mStatus: TAtlasTrackerTokenStatus;
  mItems: TArray<TAtlasTrackerConnection>;
  mTarget: TAtlasTrackerTarget;
begin
  mProvider := TAtlasYouTrackTracker.Create;
  mConnection := TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local');
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/users/me', 200, Fixture('YouTrack', 'users-me.json'));
  mTransport.Answer('https://yt.local/api/admin/', 200, Fixture('YouTrack', 'locale-de.json'));
  mStatus := TAtlasTrackerConnections.Check(mProvider, mConnection.Target, mKeep, Now);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Verified), Ord(mStatus.State));
  Assert.AreEqual('de', mStatus.Language, '„Prüfen“ erkennt die Sprache');
  // Die Seite merkt sie an der Verbindung; sie bleibt in settings.json.
  mConnection.Language := mStatus.Language;
  mItems := TAtlasTrackerConnections.Read(TAtlasTrackerConnections.ToJson(TArray<TAtlasTrackerConnection>.Create(
    mConnection)));
  Assert.AreEqual('de', mItems[0].Language);
  Assert.IsTrue(TAtlasTrackerConnections.ToJson(mItems).Contains('"language": "de"'));
  // Vorgabe „Mir zugewiesen“ auf Deutsch, auch für den Tracker aus der .atlas zum selben Server.
  mTarget := TAtlasTrackerTarget.Create('youtrack', 'https://YT.local/', 'ATL', '');
  mTarget.Language := TAtlasTrackerConnections.LanguageOf(mItems, mTarget);
  Assert.AreEqual('de', mTarget.Language);
  Assert.AreEqual('project: ATL assignee: meine #Ungelöst', TAtlasYouTrackTracker.FullQuery(mTarget));
  mTarget.Language := '';
  Assert.AreEqual('project: ATL for: me #Unresolved', TAtlasYouTrackTracker.FullQuery(mTarget),
    'ohne erkannte Sprache wie bisher');
  // Abgelehnt: keine Spracherkennung.
  mTransport := TFakeTransport.Create;
  mKeep := mTransport;
  mTransport.Answer('https://yt.local/api/users/me', 401, Fixture('YouTrack', 'users-me-401.json'));
  mStatus := TAtlasTrackerConnections.Check(mProvider, mConnection.Target, mKeep, Now);
  Assert.AreEqual('', mStatus.Language);
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)));
  mItems := nil;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerQueryTestTests);

end.
