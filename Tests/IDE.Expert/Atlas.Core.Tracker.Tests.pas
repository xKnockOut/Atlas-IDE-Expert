unit Atlas.Core.Tracker.Tests;

// Tests des Issue-Trackers ohne Server (#765): Ziel aus .atlas, Kurztitel
// und Branch-Namen (Umlaute, Akzente, Sonderzeichen), Commit-Muster,
// Branch → Ticket, GitHub- und YouTrack-Antworten aus Beispieldateien
// (Tests\Data\GitHub, Tests\Data\YouTrack), Ablauf einer Abfrage über einen
// Transport mit festen Antworten und der Git-Hook prepare-commit-msg.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerTargetTests = class
  public
    [Test]
    procedure GitHubWithoutUrlUsesGitHubCom;
    [Test]
    procedure GitHubProjectFromUrl;
    [Test]
    procedure ConfiguredNeedsOwnerAndRepoForGitHub;
    /// <summary>Zugangsdaten nie aus der Adresse; Eintrag im Anmeldespeicher je Server.</summary>
    [Test]
    procedure ServerAndCredentialTarget;
    [Test]
    procedure ChecksKeysRoundTrip;
  end;

  [TestFixture]
  TAtlasTrackerNamingTests = class
  public
    /// <summary>Abnahme: „Beginnen“ auf #753 ergibt feature/753-atlas-bereiche-und.</summary>
    [Test]
    procedure BranchNameOfMockupIssue;
    [Test]
    procedure ShortTitleReplacesUmlautsAndAccents;
    [Test]
    procedure ShortTitleDropsPrefixAndSpecialChars;
    [Test]
    procedure BranchNameIsValidRef;
    [Test]
    procedure BranchNameForYouTrackAndSvn;
    [Test]
    procedure ValidBranchNames;
    /// <summary>Commit-Muster: Vorgabe „{kennung} “, leer = unverändert, kein doppelter Präfix.</summary>
    [Test]
    procedure CommitPrefixAndPrefixed;
    [Test]
    procedure KeyOfGitHubBranch;
    [Test]
    procedure KeyOfYouTrackBranch;
    /// <summary>#1286: issues.branchBase, sonst Hauptbranch des Projekts, sonst geraten.</summary>
    [Test]
    procedure BasesPreferBranchBaseThenMainBranch;
  end;

  [TestFixture]
  TAtlasGitHubTrackerTests = class
  public
    [Test]
    procedure ApiUrls;
    /// <summary>Abnahme: Liste mit Labels aus einer Beispielantwort; Pull Requests der Suche entfallen.</summary>
    [Test]
    procedure ParsesIssuesFromFixture;
    [Test]
    procedure ParsesPullsAndLinksIssues;
    /// <summary>Abnahme: PR-Ampel aus Check Runs bzw. kombiniertem Status.</summary>
    [Test]
    procedure ParsesChecksFromFixtures;
    [Test]
    procedure FetchReadsIssuesPullsAndChecks;
    [Test]
    procedure FetchReportsErrors;
    [Test]
    procedure Pages;
  end;

  [TestFixture]
  TAtlasYouTrackTrackerTests = class
  public
    /// <summary>Abnahme: dieselbe Abfrage wie in der YouTrack-Oberfläche, mit Projekt.</summary>
    [Test]
    procedure QueryAndUrl;
    /// <summary>Abnahme: ATL-123 mit Zustand, Priorität und Sprint aus einer Beispielantwort.</summary>
    [Test]
    procedure ParsesIssuesFromFixture;
    [Test]
    procedure FetchAndErrors;
    [Test]
    procedure IssuePage;
  end;

  /// <summary>Issue-Vorschau (#1264): ein Issue mit Beschreibung, Feldern, Kommentaren, Anhängen und Verweisen.
  /// </summary>
  [TestFixture]
  TAtlasTrackerDetailsTests = class
  public
    [Test]
    procedure YouTrackDetailsFromFixture;
    [Test]
    procedure YouTrackWithoutComments;
    [Test]
    procedure YouTrackUrlAndTransport;
    [Test]
    procedure GitHubDetailsFromFixture;
    [Test]
    procedure GitHubCommentsAndTimeline;
    /// <summary>Abnahme: Issue, neueste Kommentare und Verweise in einem Aufruf; Dateien als Anhänge.</summary>
    [Test]
    procedure GitHubDetailsOverTransport;
    [Test]
    procedure DetailsErrors;
  end;

  /// <summary>Checklisten (#1273): Beschreibung ungekürzt lesen und zurückschreiben (GitHub PATCH, YouTrack POST).
  /// </summary>
  [TestFixture]
  TAtlasTrackerDescriptionsTests = class
  public
    [Test]
    procedure GitHubParseAndJson;
    [Test]
    procedure GitHubReadAndWrite;
    [Test]
    procedure YouTrackParseUrlAndJson;
    [Test]
    procedure YouTrackReadAndWrite;
    /// <summary>Ohne Schreibrecht (403) bzw. ohne schreibenden Transport.</summary>
    [Test]
    procedure WriteErrors;
  end;

  /// <summary>Abhängigkeiten und Unteraufgaben (#1279): Linktypen aus Fixtures (deutsch und englisch),
  /// Beziehungen von GitHub, Abhängigkeiten aus dem Text und die Anfragen beim Anlegen und Verknüpfen.</summary>
  [TestFixture]
  TAtlasTrackerLinkProviderTests = class
  public
    [Test]
    procedure YouTrackLinksEnglish;
    [Test]
    procedure YouTrackLinksGerman;
    [Test]
    procedure YouTrackLinkTypes;
    [Test]
    procedure YouTrackCreateSubtaskRequests;
    [Test]
    procedure YouTrackAddLinkRequests;
    [Test]
    procedure GitHubRelationsFromFixtures;
    [Test]
    procedure GitHubDetailsWithRelations;
    [Test]
    procedure GitHubTextDependencies;
    [Test]
    procedure GitHubCreateSubtaskRequests;
    [Test]
    procedure GitHubAddLinkRequests;
    /// <summary>Ohne Schreib-Transport, ohne Titel bzw. mit unpassender Art wird nichts gesendet.</summary>
    [Test]
    procedure WritesRefused;
  end;

  [TestFixture]
  TAtlasCommitHookTests = class
  private
    FDir: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ScriptHasMarkerAndUnixLineEnds;
    /// <summary>Ein fremder Hook wird nie überschrieben oder entfernt.</summary>
    [Test]
    procedure InstallKeepsForeignHook;
    [Test]
    procedure PrefixFileRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Naming,
  Atlas.Core.Tracker.Links,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.Core.Tracker.CommitHook;

type
  /// <summary>Transport mit festen Antworten je Adressanfang; zählt die Aufrufe.</summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
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

procedure TFakeTransport.Answer(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPrefixes := FPrefixes + [APrefix];
  FStatus := FStatus + [AStatus];
  FTexts := FTexts + [AText];
end;

procedure TFakeTransport.FailWith(AError: TAtlasCiFetchError);
begin
  FFail := AError;
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
var
  Index: Integer;
begin
  Calls := Calls + [AUrl];
  AStatus := 0;
  AText := '';
  AError := FFail;
  if FFail <> TAtlasCiFetchError.None then
    Exit(False);
  for Index := 0 to High(FPrefixes) do
    if Copy(AUrl, 1, Length(FPrefixes[Index])) = FPrefixes[Index] then
    begin
      AStatus := FStatus[Index];
      AText := FTexts[Index];
      Exit(True);
    end;
  AStatus := 404;
  Result := True;
end;

type
  /// <summary>Transport, der auch schreibt (#1279): merkt sich Methoden, Adressen und Inhalte, Antworten je
  /// Adressanfang.</summary>
  TFakePostTransport = class(TFakeTransport, IAtlasCiSend)
  private
    FPostPrefixes: TArray<string>;
    FPostStatus: TArray<Integer>;
    FPostTexts: TArray<string>;
  public
    Methods: TArray<string>;
    Posts: TArray<string>;
    Bodies: TArray<string>;
    procedure AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

procedure TFakePostTransport.AnswerPost(const APrefix: string; AStatus: Integer; const AText: string);
begin
  FPostPrefixes := FPostPrefixes + [APrefix];
  FPostStatus := FPostStatus + [AStatus];
  FPostTexts := FPostTexts + [AText];
end;

function TFakePostTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
var
  mIndex: Integer;
begin
  Methods := Methods + [AMethod];
  Posts := Posts + [AUrl];
  Bodies := Bodies + [ABody];
  AStatus := 404;
  AText := '';
  AError := TAtlasCiFetchError.None;
  Result := True;
  for mIndex := 0 to High(FPostPrefixes) do
    if Copy(AUrl, 1, Length(FPostPrefixes[mIndex])) = FPostPrefixes[mIndex] then
    begin
      AStatus := FPostStatus[mIndex];
      AText := FPostTexts[mIndex];
      Exit;
    end;
end;

/// <summary>Datei aus Tests\Data\&lt;AFolder&gt;, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AFolder, AName: string): string;
var
  Directory, FileName: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    FileName := TPath.Combine(Directory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine(AFolder, AName))));
    if TFile.Exists(FileName) then
      Exit(TFile.ReadAllText(FileName, TEncoding.UTF8));
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  raise Exception.Create('Tests\Data\' + AFolder + '\' + AName + ' nicht gefunden');
end;

function GitHubTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('github', '', 'beispiel/atlas', '');
end;

function YouTrackTarget: TAtlasTrackerTarget;
begin
  Result := TAtlasTrackerTarget.Create('youtrack', 'https://beispiel.youtrack.cloud/', 'ATL', '');
end;

function Issue(const AKey: string; ANumber: Integer; const ATitle: string): TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := AKey;
  Result.Number := ANumber;
  Result.Title := ATitle;
end;

{ TAtlasTrackerTargetTests }

procedure TAtlasTrackerTargetTests.GitHubWithoutUrlUsesGitHubCom;
var
  Target: TAtlasTrackerTarget;
begin
  Target := TAtlasTrackerTarget.Create(' GitHub ', '', ' beispiel/atlas/ ', ' label:bug ');
  Assert.AreEqual('github', Target.Provider);
  Assert.AreEqual('https://github.com', Target.Url);
  Assert.AreEqual('beispiel/atlas', Target.Project);
  Assert.AreEqual('label:bug', Target.Query);
  Assert.IsTrue(Target.Configured);
  // YouTrack braucht eine Adresse.
  Assert.IsFalse(TAtlasTrackerTarget.Create('youtrack', '', 'ATL', '').Configured);
end;

procedure TAtlasTrackerTargetTests.GitHubProjectFromUrl;
var
  Target: TAtlasTrackerTarget;
begin
  Target := TAtlasTrackerTarget.Create('github', 'https://github.com/beispiel/atlas/', '', '');
  Assert.AreEqual('https://github.com', Target.Url);
  Assert.AreEqual('beispiel/atlas', Target.Project);
  // Eingetragenes Projekt geht vor.
  Target := TAtlasTrackerTarget.Create('github', 'https://git.firma.de/team/kasse', 'team/andere', '');
  Assert.AreEqual('https://git.firma.de', Target.Url);
  Assert.AreEqual('team/andere', Target.Project);
end;

procedure TAtlasTrackerTargetTests.ConfiguredNeedsOwnerAndRepoForGitHub;
begin
  Assert.IsFalse(TAtlasTrackerTarget.Create('github', '', '', '').Configured);
  Assert.IsFalse(TAtlasTrackerTarget.Create('github', '', 'atlas', '').Configured);
  Assert.IsTrue(TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', '', '').Configured,
    'YouTrack ohne Projekt fragt alle Projekte');
  Assert.IsFalse(TAtlasTrackerTarget.Create('', 'https://yt.firma.de', 'ATL', '').Configured);
end;

procedure TAtlasTrackerTargetTests.ServerAndCredentialTarget;
var
  Target: TAtlasTrackerTarget;
begin
  Target := TAtlasTrackerTarget.Create('youtrack', 'https://YT.Firma.de:8443/youtrack', 'ATL', '');
  Assert.AreEqual('https://yt.firma.de:8443', Target.Server);
  Assert.AreEqual('Atlas:tracker:https://yt.firma.de:8443', Target.CredentialTarget);
  Assert.IsTrue(Target.Secure);
  Target := TAtlasTrackerTarget.Create('youtrack', 'https://nutzer:geheim@yt.firma.de', 'ATL', '');
  Assert.AreEqual('', Target.Server, 'nie Zugangsdaten aus der Adresse');
  Assert.AreEqual('', Target.CredentialTarget);
  Assert.IsFalse(Target.Configured);
  Target := TAtlasTrackerTarget.Create('youtrack', 'http://yt.intern', 'ATL', '');
  Assert.IsFalse(Target.Secure);
end;

procedure TAtlasTrackerTargetTests.ChecksKeysRoundTrip;
var
  Checks: TAtlasTrackerChecks;
begin
  for Checks := Low(TAtlasTrackerChecks) to High(TAtlasTrackerChecks) do
    Assert.IsTrue(TAtlasTrackerPullRequest.ChecksOf(TAtlasTrackerPullRequest.ChecksKey(Checks)) = Checks);
  Assert.IsTrue(TAtlasTrackerPullRequest.ChecksOf('neu') = TAtlasTrackerChecks.Unknown);
end;

{ TAtlasTrackerNamingTests }

procedure TAtlasTrackerNamingTests.BasesPreferBranchBaseThenMainBranch;
var
  mBases: TArray<string>;
begin
  mBases := TAtlasTrackerNaming.Bases(False, '', '');
  Assert.AreEqual(2, Integer(Length(mBases)));
  Assert.AreEqual('main', mBases[0]);
  Assert.AreEqual('master', mBases[1]);
  mBases := TAtlasTrackerNaming.Bases(True, '', '');
  Assert.AreEqual('trunk', string.Join(',', mBases));
  Assert.AreEqual('develop', string.Join(',', TAtlasTrackerNaming.Bases(False, '', ' develop ')));
  Assert.AreEqual('develop', string.Join(',', TAtlasTrackerNaming.Bases(True, '', 'develop')));
  Assert.AreEqual('release', string.Join(',', TAtlasTrackerNaming.Bases(False, 'release', 'develop')));
end;

procedure TAtlasTrackerNamingTests.BranchNameOfMockupIssue;
begin
  Assert.AreEqual('feature/753-atlas-bereiche-und', TAtlasTrackerNaming.BranchName(
    TAtlasTrackerNaming.GitBranchPattern, Issue('#753', 753, 'Plugin: Atlas-Bereiche und Layouts der Willkommensseite')));
end;

procedure TAtlasTrackerNamingTests.ShortTitleReplacesUmlautsAndAccents;
begin
  Assert.AreEqual('groesse-aendern-fuer', TAtlasTrackerNaming.ShortTitle('Größe ändern für Übersicht'));
  Assert.AreEqual('ueber-aerger-oel', TAtlasTrackerNaming.ShortTitle('ÜBER ÄRGER ÖL'));
  Assert.AreEqual('strasse-cafe-creme', TAtlasTrackerNaming.ShortTitle('Straße Café Crème brûlée'));
  Assert.AreEqual('', TAtlasTrackerNaming.ShortTitle('  …  '));
end;

procedure TAtlasTrackerNamingTests.ShortTitleDropsPrefixAndSpecialChars;
begin
  Assert.AreEqual('100-fertig', TAtlasTrackerNaming.ShortTitle('Server: 100% fertig?'));
  Assert.AreEqual('c-fehler-in', TAtlasTrackerNaming.ShortTitle('C++ Fehler in TList<T>'));
  // Nur eine Vorsilbe aus einem Wort entfällt.
  Assert.AreEqual('zwei-worte-rest', TAtlasTrackerNaming.ShortTitle('Zwei Worte: Rest'));
  Assert.AreEqual('url-https-x', TAtlasTrackerNaming.ShortTitle('URL https://x.de'));
end;

procedure TAtlasTrackerNamingTests.BranchNameIsValidRef;
var
  Name: string;
begin
  Name := TAtlasTrackerNaming.BranchName('feature/{kennung}-{kurztitel}',
    Issue('#612', 612, 'Überschrift mit Ümläuten, Akzenten (café) & Sonderzeichen: 100% fertig?'));
  Assert.AreEqual('feature/612-ueberschrift-mit-uemlaeuten', Name);
  // Muster mit Leerzeichen und Zeichen, die Git verbietet.
  Name := TAtlasTrackerNaming.BranchName(' bug fix/{kennung}..{kurztitel}~^:? ', Issue('#9', 9, 'A'));
  Assert.AreEqual('bug-fix/9.a', Name);
  Assert.IsTrue(TAtlasTrackerNaming.ValidBranchName(Name));
  // Ohne Kurztitel kein Strich am Ende.
  Assert.AreEqual('feature/7', TAtlasTrackerNaming.BranchName(TAtlasTrackerNaming.GitBranchPattern,
    Issue('#7', 7, '???')));
  Assert.AreEqual('feature/7-x', TAtlasTrackerNaming.BranchName('feature//{nummer}-x.lock/', Issue('#7', 7, '')));
  Assert.AreEqual('', TAtlasTrackerNaming.BranchName('///', Issue('#7', 7, '')));
end;

procedure TAtlasTrackerNamingTests.BranchNameForYouTrackAndSvn;
begin
  Assert.AreEqual('ATL-123-tracker-im-plugin', TAtlasTrackerNaming.BranchName(TAtlasTrackerNaming.SvnBranchPattern,
    Issue('ATL-123', 123, 'Tracker im Plugin anbinden')));
  Assert.AreEqual('feature/ATL-123-tracker-im-plugin', TAtlasTrackerNaming.BranchName(
    TAtlasTrackerNaming.GitBranchPattern, Issue('ATL-123', 123, 'Tracker im Plugin anbinden')));
  Assert.AreEqual('issue/123', TAtlasTrackerNaming.BranchName('issue/{NUMMER}', Issue('ATL-123', 123, '')));
end;

procedure TAtlasTrackerNamingTests.ValidBranchNames;
begin
  Assert.IsTrue(TAtlasTrackerNaming.ValidBranchName('feature/753-x'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName(''));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('-x'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('a/.b'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('a.lock'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('a b'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('a@{b'));
  Assert.IsFalse(TAtlasTrackerNaming.ValidBranchName('@'));
end;

procedure TAtlasTrackerNamingTests.CommitPrefixAndPrefixed;
var
  Prefix: string;
begin
  Prefix := TAtlasTrackerNaming.CommitPrefix(TAtlasTrackerNaming.CommitPattern, Issue('ATL-123', 123, 'x'));
  Assert.AreEqual('ATL-123 ', Prefix, 'Leerzeichen am Ende bleibt');
  Assert.AreEqual('ATL-123 Parser repariert', TAtlasTrackerNaming.Prefixed('Parser repariert', Prefix));
  Assert.AreEqual('ATL-123 Parser', TAtlasTrackerNaming.Prefixed('ATL-123 Parser', Prefix), 'nicht doppelt');
  Assert.AreEqual('ATL-123: Parser', TAtlasTrackerNaming.Prefixed('ATL-123: Parser', Prefix));
  // Leeres Muster: Nachricht unverändert.
  Assert.AreEqual('', TAtlasTrackerNaming.CommitPrefix('', Issue('ATL-123', 123, 'x')));
  Assert.AreEqual('Parser', TAtlasTrackerNaming.Prefixed('Parser', ''));
  Assert.AreEqual('#753 ', TAtlasTrackerNaming.CommitPrefix('{kennung} ', Issue('#753', 753, 'x')));
  Assert.AreEqual('[#753] ', TAtlasTrackerNaming.CommitPrefix('[{kennung}] ', Issue('#753', 753, 'x')));
  Assert.AreEqual('753-atlas: ', TAtlasTrackerNaming.CommitPrefix('{nummer}-{kurztitel}: ',
    Issue('#753', 753, 'Atlas')));
  Assert.AreEqual('', TAtlasTrackerNaming.CommitPrefix('{kennung} ', Issue('', 0, 'x')), 'ohne Issue kein Präfix');
end;

procedure TAtlasTrackerNamingTests.KeyOfGitHubBranch;
begin
  Assert.AreEqual('#753', TAtlasTrackerNaming.KeyOfBranch('github', '', 'feature/753-atlas-bereiche-und'));
  Assert.AreEqual('#42', TAtlasTrackerNaming.KeyOfBranch('github', '', '42-fix'));
  Assert.AreEqual('#42', TAtlasTrackerNaming.KeyOfBranch('github', '', 'bugfix/42'));
  Assert.AreEqual('#7', TAtlasTrackerNaming.KeyOfBranch('github', '', 'issue_007_x'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('github', '', 'main'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('github', '', 'release/2.1'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('github', '', 'v2-fix'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('github', '', 'feature/0-x'));
end;

procedure TAtlasTrackerNamingTests.KeyOfYouTrackBranch;
begin
  Assert.AreEqual('ATL-123', TAtlasTrackerNaming.KeyOfBranch('youtrack', 'ATL', 'feature/ATL-123-tracker'));
  Assert.AreEqual('ATL-123', TAtlasTrackerNaming.KeyOfBranch('youtrack', 'atl', 'branches/atl-123'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('youtrack', 'ATL', 'feature/XATL-123'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('youtrack', 'ATL', 'feature/KASSE-5'));
  Assert.AreEqual('KASSE-5', TAtlasTrackerNaming.KeyOfBranch('youtrack', '', 'feature/KASSE-5-x'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('youtrack', 'ATL', 'ATL-12a'));
  Assert.AreEqual('', TAtlasTrackerNaming.KeyOfBranch('jira', 'ATL', 'ATL-1'));
end;

{ TAtlasGitHubTrackerTests }

procedure TAtlasGitHubTrackerTests.ApiUrls;
var
  Target: TAtlasTrackerTarget;
begin
  Assert.AreEqual('https://api.github.com/search/issues?q=assignee%3A%40me%20state%3Aopen%20repo%3Abeispiel/atlas' +
    '%20is%3Aissue&per_page=20&sort=updated&order=desc', TAtlasGitHubTracker.SearchUrl(GitHubTarget, 20));
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/pulls?state=open&per_page=50',
    TAtlasGitHubTracker.PullsUrl(GitHubTarget));
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/commits/0123456789abcdef/check-runs?per_page=100',
    TAtlasGitHubTracker.CheckRunsUrl(GitHubTarget, '0123456789abcdef'));
  Assert.AreEqual('', TAtlasGitHubTracker.CheckRunsUrl(GitHubTarget, '../x'), 'nur eine Prüfsumme');
  Target := TAtlasTrackerTarget.Create('github', 'https://git.firma.de', 'team/kasse', 'label:"bug #1"');
  Assert.AreEqual('https://git.firma.de/api/v3', TAtlasGitHubTracker.ApiBase(Target));
  Assert.AreEqual('https://git.firma.de/api/v3/search/issues?q=label%3A%22bug%20%231%22%20repo%3Ateam/kasse' +
    '%20is%3Aissue&per_page=5&sort=updated&order=desc', TAtlasGitHubTracker.SearchUrl(Target, 5));
  Assert.AreEqual('https://api.github.com', (TAtlasGitHubTracker.Create as IAtlasTrackerProvider).ApiServer(
    GitHubTarget), 'das Token geht nur an die Schnittstelle');
end;

procedure TAtlasGitHubTrackerTests.ParsesIssuesFromFixture;
var
  Issues: TArray<TAtlasTrackerIssue>;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParseIssues(Fixture('GitHub', 'search-issues.json'), 20, Issues));
  Assert.AreEqual(3, Integer(Length(Issues)), 'der Pull Request #640 entfällt');
  Assert.AreEqual('#753', Issues[0].Key);
  Assert.AreEqual(753, Issues[0].Number);
  Assert.AreEqual('Plugin: Atlas-Bereiche und Layouts der Willkommensseite', Issues[0].Title);
  Assert.AreEqual(2, Integer(Length(Issues[0].Labels)));
  Assert.AreEqual('plugin', Issues[0].Labels[0]);
  Assert.AreEqual('willkommensseite', Issues[0].Labels[1]);
  Assert.AreEqual('beispiel', Issues[0].Assignee, 'Zuständig für die Palette (#1270)');
  Assert.AreEqual('', Issues[1].Assignee);
  Assert.AreEqual('#612', Issues[1].Key);
  Assert.AreEqual('bug', Issues[1].Labels[0]);
  Assert.AreEqual(0, Integer(Length(Issues[2].Labels)));
  Assert.AreEqual('Fehler im Parser zweite Zeile', Issues[2].Title, 'Titel einzeilig');
  Assert.IsTrue(TAtlasGitHubTracker.ParseIssues(Fixture('GitHub', 'search-issues.json'), 1, Issues));
  Assert.AreEqual(1, Integer(Length(Issues)), 'höchstens AMax');
  Assert.IsFalse(TAtlasGitHubTracker.ParseIssues('{"message":"x"}', 20, Issues));
  Assert.IsFalse(TAtlasGitHubTracker.ParseIssues('kein json', 20, Issues));
end;

procedure TAtlasGitHubTrackerTests.ParsesPullsAndLinksIssues;
var
  Pulls: TArray<TAtlasGitHubPull>;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParsePulls(Fixture('GitHub', 'pulls.json'), Pulls));
  Assert.AreEqual(3, Integer(Length(Pulls)));
  Assert.AreEqual(760, Pulls[0].Number);
  Assert.AreEqual('feature/753-atlas-bereiche-und', Pulls[0].Branch);
  Assert.AreEqual('0123456789abcdef0123456789abcdef01234567', Pulls[0].Sha);
  Assert.IsTrue(Pulls[1].Draft);
  Assert.IsTrue(TAtlasGitHubTracker.PullMentions(Pulls[0], 753), 'Branch mit der Nummer');
  Assert.IsTrue(TAtlasGitHubTracker.PullMentions(Pulls[1], 598), '„Fixes: #598“');
  Assert.IsFalse(TAtlasGitHubTracker.PullMentions(Pulls[2], 612), 'bloße Erwähnung zählt nicht');
  Assert.IsFalse(TAtlasGitHubTracker.PullMentions(Pulls[2], 6120), 'Erwähnung ohne „closes“');
  Assert.IsFalse(TAtlasGitHubTracker.PullMentions(Pulls[0], 75));
  Assert.IsFalse(TAtlasGitHubTracker.ParsePulls('{}', Pulls));
end;

procedure TAtlasGitHubTrackerTests.ParsesChecksFromFixtures;
var
  Checks: TAtlasTrackerChecks;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParseCheckRuns(Fixture('GitHub', 'check-runs.json'), Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Failure, 'rot, sobald einer fehlschlug');
  Assert.IsTrue(TAtlasGitHubTracker.ParseCheckRuns(Fixture('GitHub', 'check-runs-empty.json'), Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Unknown);
  Assert.IsTrue(TAtlasGitHubTracker.ParseCheckRuns(
    '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"queued"}]}', Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Pending);
  Assert.IsTrue(TAtlasGitHubTracker.ParseCheckRuns(
    '{"check_runs":[{"status":"completed","conclusion":"success"},{"status":"completed","conclusion":"skipped"}]}',
    Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Success);
  Assert.IsTrue(TAtlasGitHubTracker.ParseStatus(Fixture('GitHub', 'status.json'), Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Success);
  Assert.IsTrue(TAtlasGitHubTracker.ParseStatus('{"state":"pending","statuses":[]}', Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Unknown, 'ohne Status keine Ampel');
  Assert.IsTrue(TAtlasGitHubTracker.ParseStatus('{"state":"error","statuses":[{}]}', Checks));
  Assert.IsTrue(Checks = TAtlasTrackerChecks.Failure);
  Assert.IsFalse(TAtlasGitHubTracker.ParseCheckRuns('[]', Checks));
end;

procedure TAtlasGitHubTrackerTests.FetchReadsIssuesPullsAndChecks;
var
  Transport: TFakeTransport;
  TransportRef: IAtlasCiTransport;
  Provider: IAtlasTrackerProvider;
  Issues: TArray<TAtlasTrackerIssue>;
  Error: TAtlasCiFetchError;
begin
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Transport.Answer('https://api.github.com/search/issues', 200, Fixture('GitHub', 'search-issues.json'));
  Transport.Answer('https://api.github.com/repos/beispiel/atlas/pulls', 200, Fixture('GitHub', 'pulls.json'));
  Transport.Answer('https://api.github.com/repos/beispiel/atlas/commits/0123', 200,
    Fixture('GitHub', 'check-runs-empty.json'));
  Transport.Answer('https://api.github.com/repos/beispiel/atlas/commits/fedcba9876543210fedcba9876543210fedcba98/check',
    200, Fixture('GitHub', 'check-runs.json'));
  Provider := TAtlasGitHubTracker.Create;
  Assert.IsTrue(Provider.Fetch(GitHubTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.None);
  Assert.AreEqual(3, Integer(Length(Issues)));
  Assert.AreEqual(760, Issues[0].PullRequest.Number, 'PR #760 über den Branch');
  // 760 hat keine Check Runs und keinen kombinierten Status: Ampel unbekannt.
  Assert.IsTrue(Issues[0].PullRequest.Checks = TAtlasTrackerChecks.Unknown);
  Assert.AreEqual(0, Issues[1].PullRequest.Number);
  Assert.AreEqual(640, Issues[2].PullRequest.Number);
  Assert.IsTrue(Issues[2].PullRequest.Draft);
  Assert.IsTrue(Issues[2].PullRequest.Checks = TAtlasTrackerChecks.Failure);
  Assert.AreEqual(5, Integer(Length(Transport.Calls)), 'Suche, PRs, zwei Check-Runs, ein Status');
end;

procedure TAtlasGitHubTrackerTests.FetchReportsErrors;
var
  Transport: TFakeTransport;
  TransportRef: IAtlasCiTransport;
  Provider: IAtlasTrackerProvider;
  Issues: TArray<TAtlasTrackerIssue>;
  Error: TAtlasCiFetchError;
begin
  Provider := TAtlasGitHubTracker.Create;
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Transport.Answer('https://api.github.com/search/issues', 401, '{}');
  Assert.IsFalse(Provider.Fetch(GitHubTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Unauthorized);
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Transport.Answer('https://api.github.com/search/issues', 422, '{}');
  Assert.IsFalse(Provider.Fetch(GitHubTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Invalid, 'ungültige Abfrage');
  Transport.FailWith(TAtlasCiFetchError.Timeout);
  Assert.IsFalse(Provider.Fetch(GitHubTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Timeout);
  Assert.AreEqual(0, Integer(Length(Issues)));
  // Ohne Projekt: kein Netzzugriff.
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Assert.IsFalse(Provider.Fetch(TAtlasTrackerTarget.Create('github', '', '', ''), TransportRef, 5000, 20, Issues,
    Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.NotConfigured);
  Assert.AreEqual(0, Integer(Length(Transport.Calls)));
end;

procedure TAtlasGitHubTrackerTests.Pages;
var
  Provider: IAtlasTrackerProvider;
begin
  Provider := TAtlasGitHubTracker.Create;
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/753', Provider.IssuePage(GitHubTarget, '#753'));
  Assert.AreEqual('https://github.com/beispiel/atlas/pull/760', Provider.PullRequestPage(GitHubTarget, 760));
  Assert.AreEqual('', Provider.IssuePage(GitHubTarget, '#x'));
  Assert.AreEqual('GitHub', Provider.Caption);
  Assert.AreEqual('assignee:@me state:open', Provider.DefaultQuery);
end;

{ TAtlasYouTrackTrackerTests }

procedure TAtlasYouTrackTrackerTests.QueryAndUrl;
var
  Target: TAtlasTrackerTarget;
begin
  Assert.AreEqual('project: ATL for: me #Unresolved', TAtlasYouTrackTracker.FullQuery(YouTrackTarget));
  Target := TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', '', 'for: me State: Open');
  Assert.AreEqual('for: me State: Open', TAtlasYouTrackTracker.FullQuery(Target));
  Target := TAtlasTrackerTarget.Create('youtrack', 'https://yt.firma.de', 'Atlas IDE', '');
  Assert.AreEqual('project: {Atlas IDE} for: me #Unresolved', TAtlasYouTrackTracker.FullQuery(Target));
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues?query=project%3A%20ATL%20for%3A%20me%20%23Unresolved' +
    '&fields=idReadable%2CnumberInProject%2Csummary%2CcustomFields%28name%2Cvalue%28name%2Cpresentation%2Clogin' +
    '%2CfullName%29%29&$top=20', TAtlasYouTrackTracker.IssuesUrl(YouTrackTarget, 20));
end;

procedure TAtlasYouTrackTrackerTests.ParsesIssuesFromFixture;
var
  Issues: TArray<TAtlasTrackerIssue>;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseIssues(Fixture('YouTrack', 'issues.json'), 20, Issues));
  Assert.AreEqual(2, Integer(Length(Issues)), 'ohne Kennung entfällt');
  Assert.AreEqual('ATL-123', Issues[0].Key);
  Assert.AreEqual(123, Issues[0].Number);
  Assert.AreEqual('Tracker im Plugin anbinden', Issues[0].Title);
  Assert.AreEqual('In Progress', Issues[0].State);
  Assert.AreEqual('Major', Issues[0].Priority);
  Assert.AreEqual('Sprint 42', Issues[0].Sprint);
  Assert.AreEqual('Beispiel', Issues[0].Assignee, 'Zuständig für die Palette (#1270)');
  Assert.AreEqual('ATL-7', Issues[1].Key);
  Assert.AreEqual('', Issues[1].Assignee);
  Assert.AreEqual('Offen', Issues[1].State, 'deutscher Feldname, Wert als presentation');
  Assert.AreEqual('', Issues[1].Priority);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseIssues('{"error":"x"}', 20, Issues));
end;

procedure TAtlasYouTrackTrackerTests.FetchAndErrors;
var
  Transport: TFakeTransport;
  TransportRef: IAtlasCiTransport;
  Provider: IAtlasTrackerProvider;
  Issues: TArray<TAtlasTrackerIssue>;
  Error: TAtlasCiFetchError;
begin
  Provider := TAtlasYouTrackTracker.Create;
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Transport.Answer('https://beispiel.youtrack.cloud/api/issues', 200, Fixture('YouTrack', 'issues.json'));
  Assert.IsTrue(Provider.Fetch(YouTrackTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.AreEqual(2, Integer(Length(Issues)));
  Assert.AreEqual(1, Integer(Length(Transport.Calls)));
  Assert.AreEqual('https://beispiel.youtrack.cloud', Provider.ApiServer(YouTrackTarget));
  Transport := TFakeTransport.Create;
  TransportRef := Transport;
  Transport.Answer('https://beispiel.youtrack.cloud/api/issues', 400, '{"error":"invalid_query"}');
  Assert.IsFalse(Provider.Fetch(YouTrackTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Invalid);
  Transport.FailWith(TAtlasCiFetchError.Network);
  Assert.IsFalse(Provider.Fetch(YouTrackTarget, TransportRef, 5000, 20, Issues, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Network);
end;

procedure TAtlasYouTrackTrackerTests.IssuePage;
var
  Provider: IAtlasTrackerProvider;
begin
  Provider := TAtlasYouTrackTracker.Create;
  Assert.AreEqual('https://beispiel.youtrack.cloud/issue/ATL-123', Provider.IssuePage(YouTrackTarget, 'ATL-123'));
  Assert.AreEqual('', Provider.IssuePage(YouTrackTarget, 'ATL-1/../x'));
  Assert.AreEqual('', Provider.PullRequestPage(YouTrackTarget, 5));
end;

{ TAtlasCommitHookTests }

procedure TAtlasCommitHookTests.Setup;
begin
  FDir := TPath.Combine(TPath.GetTempPath, 'atlas-hook-' + IntToStr(Random(1000000)));
  ForceDirectories(FDir);
end;

procedure TAtlasCommitHookTests.TearDown;
begin
  if TDirectory.Exists(FDir) then
    TDirectory.Delete(FDir, True);
  FDir := '';
end;

procedure TAtlasCommitHookTests.ScriptHasMarkerAndUnixLineEnds;
var
  Script: string;
begin
  Script := TAtlasCommitHook.Script;
  Assert.IsTrue(Script.StartsWith('#!/bin/sh' + #10 + TAtlasCommitHook.Marker + #10));
  Assert.AreEqual(0, Pos(#13, Script), 'sh verträgt kein CR');
  Assert.IsTrue(Pos('merge|squash|commit) exit 0', Script) > 0, 'Merge, Squash und Amend bleiben');
  Assert.IsTrue(TAtlasCommitHook.IsOwn(Script));
  Assert.IsFalse(TAtlasCommitHook.IsOwn('#!/bin/sh' + #10 + 'npx husky'));
end;

procedure TAtlasCommitHookTests.InstallKeepsForeignHook;
var
  Hooks: string;
begin
  Hooks := TPath.Combine(FDir, 'hooks');
  Assert.IsTrue(TAtlasCommitHook.State(Hooks) = TAtlasCommitHookState.Missing);
  Assert.IsTrue(TAtlasCommitHook.Install(Hooks), 'legt Ordner und Hook an');
  Assert.IsTrue(TAtlasCommitHook.State(Hooks) = TAtlasCommitHookState.Own);
  Assert.IsTrue(TAtlasCommitHook.Install(Hooks), 'eigener wird ersetzt');
  Assert.IsTrue(TAtlasCommitHook.Uninstall(Hooks));
  Assert.IsTrue(TAtlasCommitHook.State(Hooks) = TAtlasCommitHookState.Missing);
  TFile.WriteAllText(TAtlasCommitHook.HookFile(Hooks), '#!/bin/sh' + #10 + 'echo fremd' + #10);
  Assert.IsTrue(TAtlasCommitHook.State(Hooks) = TAtlasCommitHookState.Foreign);
  Assert.IsFalse(TAtlasCommitHook.Install(Hooks), 'fremder Hook bleibt');
  Assert.IsTrue(TAtlasCommitHook.Uninstall(Hooks));
  Assert.IsTrue(Pos('echo fremd', TFile.ReadAllText(TAtlasCommitHook.HookFile(Hooks))) > 0);
  Assert.IsFalse(TAtlasCommitHook.Install(''));
end;

procedure TAtlasCommitHookTests.PrefixFileRoundTrip;
begin
  Assert.AreEqual('', TAtlasCommitHook.ReadPrefix(FDir));
  Assert.IsTrue(TAtlasCommitHook.WritePrefix(FDir, 'ATL-123 '));
  Assert.AreEqual('ATL-123 ', TAtlasCommitHook.ReadPrefix(FDir), 'ohne Zeilenende, Leerzeichen bleibt');
  Assert.IsTrue(TAtlasCommitHook.WritePrefix(FDir, ''));
  Assert.IsFalse(FileExists(TAtlasCommitHook.PrefixFileOf(FDir)));
  Assert.IsTrue(TAtlasCommitHook.WritePrefix(FDir, ''), 'ohne Datei ebenso');
  Assert.IsFalse(TAtlasCommitHook.WritePrefix('', 'x'));
end;

{ TAtlasTrackerDetailsTests }

procedure TAtlasTrackerDetailsTests.YouTrackDetailsFromFixture;
var
  mDetails: TAtlasTrackerDetails;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDetails(Fixture('YouTrack', 'issue-details.json'), YouTrackTarget, True,
    mDetails));
  Assert.AreEqual('ATL-123', mDetails.Key);
  Assert.AreEqual(123, mDetails.Number);
  Assert.AreEqual('Tracker im Plugin anbinden', mDetails.Title);
  Assert.IsTrue(mDetails.Description.StartsWith('## Ziel'));
  Assert.AreEqual('In Progress', mDetails.State);
  Assert.AreEqual('Major', mDetails.Priority);
  Assert.AreEqual('Feature', mDetails.Kind);
  Assert.AreEqual('Marco B.', mDetails.Assignee, 'Benutzer mit vollem Namen');
  Assert.AreEqual('Sprint 42', mDetails.Sprint);
  Assert.AreEqual(2, Integer(Length(mDetails.Labels)));
  Assert.AreEqual('ui', mDetails.Labels[1]);
  Assert.IsTrue(Abs(mDetails.Created - UnixToDateTime(1761645649, True)) < 1 / SecsPerDay, 'Millisekunden seit 1970');
  Assert.IsTrue(mDetails.Updated > mDetails.Created);
  // Entfernte Anhänge entfallen; relative Adressen beim Server, fremde Rechner sind extern.
  Assert.AreEqual(2, Integer(Length(mDetails.Attachments)));
  Assert.AreEqual('skizze.png', mDetails.Attachments[0].Name);
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/files/1-2?sign=abc', mDetails.Attachments[0].Url);
  Assert.AreEqual<Int64>(2048, mDetails.Attachments[0].Size);
  Assert.IsFalse(mDetails.Attachments[0].External);
  Assert.AreEqual('fremd.zip', mDetails.Attachments[1].Name);
  Assert.AreEqual<Int64>(-1, mDetails.Attachments[1].Size, 'Größe unbekannt');
  Assert.IsTrue(mDetails.Attachments[1].External);
  Assert.AreEqual(0, mDetails.AttachmentIndex('Skizze.PNG'));
  // Verknüpfungen mit Richtung.
  Assert.AreEqual(2, Integer(Length(mDetails.Links)));
  Assert.AreEqual('ATL-100', mDetails.Links[0].Key);
  Assert.AreEqual('depends on', mDetails.Links[0].Relation);
  Assert.IsTrue(mDetails.Links[0].Local);
  Assert.AreEqual('is required for', mDetails.Links[1].Relation);
  // Gelöschte Kommentare entfallen.
  Assert.IsTrue(mDetails.CommentsLoaded);
  Assert.AreEqual(2, Integer(Length(mDetails.Comments)));
  Assert.AreEqual('Marco B.', mDetails.Comments[0].Author);
  Assert.AreEqual('kollege', mDetails.Comments[1].Author);
  Assert.AreEqual('Zweiter `Code`', mDetails.Comments[1].Text);
end;

procedure TAtlasTrackerDetailsTests.YouTrackWithoutComments;
var
  mDetails: TAtlasTrackerDetails;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDetails(Fixture('YouTrack', 'issue-details.json'), YouTrackTarget, False,
    mDetails));
  Assert.IsFalse(mDetails.CommentsLoaded);
  Assert.AreEqual(0, Integer(Length(mDetails.Comments)));
  Assert.IsFalse(TAtlasYouTrackTracker.ParseDetails('{"summary": "ohne Kennung"}', YouTrackTarget, True, mDetails));
  Assert.IsFalse(TAtlasYouTrackTracker.ParseDetails('kein JSON', YouTrackTarget, True, mDetails));
end;

procedure TAtlasTrackerDetailsTests.YouTrackUrlAndTransport;
var
  mUrl: string;
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mDetails: TAtlasTrackerDetails;
  mError: TAtlasCiFetchError;
begin
  mUrl := TAtlasYouTrackTracker.DetailsUrl(YouTrackTarget, 'ATL-123', False);
  Assert.IsTrue(mUrl.StartsWith('https://beispiel.youtrack.cloud/api/issues/ATL-123?fields='));
  Assert.IsFalse(mUrl.Contains('comments'), 'ohne Kommentare nicht abgefragt');
  Assert.IsTrue(TAtlasYouTrackTracker.DetailsUrl(YouTrackTarget, 'ATL-123', True).Contains('comments'));
  Assert.AreEqual('', TAtlasYouTrackTracker.DetailsUrl(YouTrackTarget, 'ATL 1/../x', True));
  mProvider := TAtlasYouTrackTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues/ATL-123', 200,
    Fixture('YouTrack', 'issue-details.json'));
  Assert.IsTrue(mProvider.Details(YouTrackTarget, mTransportRef, 'ATL-123', True, 5000, mDetails, mError));
  Assert.AreEqual(1, Integer(Length(mTransport.Calls)), 'eine Abfrage samt Kommentaren');
  Assert.AreEqual(mProvider.IssuePage(YouTrackTarget, 'ATL-123'), mDetails.Page);
  Assert.AreEqual(2, Integer(Length(mDetails.Comments)));
end;

procedure TAtlasTrackerDetailsTests.GitHubDetailsFromFixture;
var
  mDetails: TAtlasTrackerDetails;
  mCount: Integer;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParseDetails(Fixture('GitHub', 'issue-details.json'), mDetails, mCount));
  Assert.AreEqual('#753', mDetails.Key);
  Assert.AreEqual(753, mDetails.Number);
  Assert.AreEqual('closed (not planned)', mDetails.State);
  Assert.AreEqual(3, Integer(Length(mDetails.Labels)), 'Objekte und Texte');
  Assert.AreEqual('rohtext', mDetails.Labels[2]);
  Assert.AreEqual('xKnockOut, kollege', mDetails.Assignee, 'alle Zuständigen');
  Assert.AreEqual('v1.2.0', mDetails.Sprint, 'Meilenstein');
  Assert.AreEqual('Feature', mDetails.Kind);
  Assert.AreEqual(2, mCount);
  Assert.IsTrue(Abs(mDetails.Updated - EncodeDateTime(2026, 10, 28, 10, 40, 49, 0)) < 1 / SecsPerDay);
  Assert.IsFalse(TAtlasGitHubTracker.ParseDetails('{"title": "ohne Nummer"}', mDetails, mCount));
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/issues/753',
    TAtlasGitHubTracker.IssueApiUrl(GitHubTarget, '#753'));
  Assert.AreEqual('', TAtlasGitHubTracker.IssueApiUrl(GitHubTarget, 'abc'));
end;

procedure TAtlasTrackerDetailsTests.GitHubCommentsAndTimeline;
var
  mComments: TArray<TAtlasTrackerComment>;
  mLinks: TArray<TAtlasTrackerLink>;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParseComments(Fixture('GitHub', 'issue-comments.json'), mComments));
  Assert.AreEqual(2, Integer(Length(mComments)));
  Assert.AreEqual('xKnockOut', mComments[0].Author);
  Assert.AreEqual('Erster', mComments[0].Text);
  Assert.IsTrue(TAtlasGitHubTracker.ParseTimeline(Fixture('GitHub', 'issue-timeline.json'), 'beispiel/atlas', mLinks));
  Assert.AreEqual(2, Integer(Length(mLinks)), 'doppelte und ungültige Verweise entfallen');
  Assert.AreEqual('#760', mLinks[0].Key);
  Assert.AreEqual('pull request', mLinks[0].Relation);
  Assert.IsTrue(mLinks[0].Local);
  Assert.AreEqual('https://github.com/beispiel/atlas/pull/760', mLinks[0].Page);
  Assert.AreEqual('andere/repo#12', mLinks[1].Key);
  Assert.AreEqual('cross-referenced', mLinks[1].Relation);
  Assert.IsFalse(mLinks[1].Local, 'anderes Repository im Browser');
end;

procedure TAtlasTrackerDetailsTests.GitHubDetailsOverTransport;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mDetails: TAtlasTrackerDetails;
  mError: TAtlasCiFetchError;
  mCall: string;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  // Längere Anfänge zuerst: Der Transport nimmt den ersten passenden.
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753/comments', 200,
    Fixture('GitHub', 'issue-comments.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753/timeline', 200,
    Fixture('GitHub', 'issue-timeline.json'));
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753', 200,
    Fixture('GitHub', 'issue-details.json'));
  Assert.IsTrue(mProvider.Details(GitHubTarget, mTransportRef, '#753', True, 5000, mDetails, mError));
  // Issue, Kommentare, Zeitleiste; ohne Zusammenfassungen dazu Unteraufgaben, „blocked by“, „blocking“ (#1279).
  Assert.AreEqual(6, Integer(Length(mTransport.Calls)));
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/issues/753/comments?per_page=100&page=1',
    mTransport.Calls[1]);
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/753', mDetails.Page);
  Assert.IsTrue(mDetails.CommentsLoaded);
  Assert.AreEqual(2, Integer(Length(mDetails.Comments)));
  Assert.AreEqual(2, Integer(Length(mDetails.Links)));
  // Dateien aus Beschreibung und Kommentaren; andere Links bleiben Links.
  Assert.AreEqual(2, Integer(Length(mDetails.Attachments)));
  Assert.AreEqual('Protokoll.zip', mDetails.Attachments[0].Name);
  Assert.AreEqual('shot.zip', mDetails.Attachments[1].Name);
  Assert.IsTrue(mDetails.Attachments[1].External);
  // Ohne Kommentare: keine Abfrage dafür.
  mTransport.Calls := nil;
  Assert.IsTrue(mProvider.Details(GitHubTarget, mTransportRef, '#753', False, 5000, mDetails, mError));
  Assert.IsFalse(mDetails.CommentsLoaded);
  for mCall in mTransport.Calls do
    Assert.IsFalse(mCall.Contains('/comments'));
end;

procedure TAtlasTrackerDetailsTests.DetailsErrors;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mDetails: TAtlasTrackerDetails;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  Assert.IsFalse(mProvider.Details(GitHubTarget, mTransportRef, '#1', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound, '404');
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/2', 410, '{}');
  Assert.IsFalse(mProvider.Details(GitHubTarget, mTransportRef, '#2', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound, '410: gelöscht');
  Assert.IsFalse(mProvider.Details(GitHubTarget, mTransportRef, 'abc', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured, 'ungültige Kennung');
  Assert.IsFalse(mProvider.Details(GitHubTarget, nil, '#1', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured, 'ohne Token');
  // Fehler des Transports kommen bei beiden Anbietern unverändert an.
  mTransport.FailWith(TAtlasCiFetchError.Timeout);
  Assert.IsFalse(mProvider.Details(GitHubTarget, mTransportRef, '#1', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Timeout, 'GitHub: Zeitüberschreitung');
  mProvider := TAtlasYouTrackTracker.Create;
  Assert.IsFalse(mProvider.Details(YouTrackTarget, mTransportRef, 'ATL-1', True, 5000, mDetails, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Timeout, 'YouTrack: Zeitüberschreitung');
end;

type
  /// <summary>Wie TFakeTransport, schreibt aber auch (IAtlasCiSend) und merkt sich Methode, Adresse und Inhalt.
  /// </summary>
  TFakeSendTransport = class(TFakeTransport, IAtlasCiSend)
  public
    SendStatus: Integer;
    SendFail: TAtlasCiFetchError;
    Method: string;
    Url: string;
    Body: string;
    constructor Create;
    function Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

constructor TFakeSendTransport.Create;
begin
  inherited Create;
  SendStatus := 200;
end;

function TFakeSendTransport.Send(const AMethod, AUrl, ABody: string; ATimeoutMs: Integer; out AStatus: Integer;
  out AText: string; out AError: TAtlasCiFetchError): Boolean;
begin
  Method := AMethod;
  Url := AUrl;
  Body := ABody;
  AText := '{}';
  AStatus := SendStatus;
  AError := SendFail;
  Result := SendFail = TAtlasCiFetchError.None;
end;

{ TAtlasTrackerDescriptionsTests }

procedure TAtlasTrackerDescriptionsTests.GitHubParseAndJson;
var
  mText: string;
begin
  Assert.IsTrue(TAtlasGitHubTracker.ParseBody('{"number":7,"body":"- [ ] a\r\n- [x] b"}', mText));
  Assert.AreEqual('- [ ] a'#13#10'- [x] b', mText, 'Zeilenenden bleiben');
  Assert.IsTrue(TAtlasGitHubTracker.ParseBody('{"number":7,"body":null}', mText), 'ohne Beschreibung');
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasGitHubTracker.ParseBody('{"body":"x"}', mText), 'kein Issue');
  Assert.IsFalse(TAtlasGitHubTracker.ParseBody('kein JSON', mText));
  Assert.AreEqual('{"body":"- [x] a\r\n\"b\""}', TAtlasGitHubTracker.BodyJson('- [x] a'#13#10'"b"'));
end;

procedure TAtlasTrackerDescriptionsTests.GitHubReadAndWrite;
var
  mTransport: TFakeSendTransport;
  mTransportRef: IAtlasCiTransport;
  mEditor: IAtlasTrackerDescriptions;
  mText: string;
  mError: TAtlasCiFetchError;
begin
  mEditor := TAtlasGitHubTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://api.github.com/repos/beispiel/atlas/issues/753', 200,
    '{"number":753,"body":"- [ ] a"}');
  Assert.IsTrue(mEditor.Description(GitHubTarget, mTransportRef, '#753', 5000, mText, mError));
  Assert.AreEqual('- [ ] a', mText);
  Assert.IsTrue(mEditor.UpdateDescription(GitHubTarget, mTransportRef, '#753', '- [x] a', 5000, mError));
  Assert.AreEqual('PATCH', mTransport.Method);
  Assert.AreEqual('https://api.github.com/repos/beispiel/atlas/issues/753', mTransport.Url);
  Assert.AreEqual('{"body":"- [x] a"}', mTransport.Body);
end;

procedure TAtlasTrackerDescriptionsTests.YouTrackParseUrlAndJson;
var
  mText: string;
begin
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues/ATL-131?fields=idReadable%2Cdescription',
    TAtlasYouTrackTracker.IssueUrl(YouTrackTarget, 'ATL-131', 'idReadable,description'));
  Assert.AreEqual('', TAtlasYouTrackTracker.IssueUrl(YouTrackTarget, 'ATL 131', 'idReadable'), 'ungültige Kennung');
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDescription('{"idReadable":"ATL-131","description":"* [x] a\nb"}',
    mText));
  Assert.AreEqual('* [x] a'#10'b', mText);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDescription('{"idReadable":"ATL-131","description":null}', mText));
  Assert.AreEqual('', mText);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseDescription('{"description":"x"}', mText), 'kein Issue');
  Assert.AreEqual('{"description":"1. [ ] a"}', TAtlasYouTrackTracker.DescriptionJson('1. [ ] a'));
end;

procedure TAtlasTrackerDescriptionsTests.YouTrackReadAndWrite;
var
  mTransport: TFakeSendTransport;
  mTransportRef: IAtlasCiTransport;
  mEditor: IAtlasTrackerDescriptions;
  mText: string;
  mError: TAtlasCiFetchError;
begin
  mEditor := TAtlasYouTrackTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer('https://beispiel.youtrack.cloud/api/issues/ATL-131?fields=idReadable%2Cdescription', 200,
    '{"idReadable":"ATL-131","description":"- [ ] a"}');
  Assert.IsTrue(mEditor.Description(YouTrackTarget, mTransportRef, 'ATL-131', 5000, mText, mError));
  Assert.AreEqual('- [ ] a', mText);
  Assert.IsTrue(mEditor.UpdateDescription(YouTrackTarget, mTransportRef, 'ATL-131', '- [x] a', 5000, mError));
  Assert.AreEqual('POST', mTransport.Method);
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issues/ATL-131?fields=idReadable', mTransport.Url);
  Assert.AreEqual('{"description":"- [x] a"}', mTransport.Body);
end;

procedure TAtlasTrackerDescriptionsTests.WriteErrors;
var
  mTransport: TFakeSendTransport;
  mTransportRef: IAtlasCiTransport;
  mReadOnly: TFakeTransport;
  mReadOnlyRef: IAtlasCiTransport;
  mEditor: IAtlasTrackerDescriptions;
  mText: string;
  mError: TAtlasCiFetchError;
begin
  mEditor := TAtlasGitHubTracker.Create;
  mTransport := TFakeSendTransport.Create;
  mTransportRef := mTransport;
  // Kein Schreibrecht: 403 heißt Unauthorized.
  mTransport.SendStatus := 403;
  Assert.IsFalse(mEditor.UpdateDescription(GitHubTarget, mTransportRef, '#753', 'x', 5000, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Unauthorized);
  // Transport lehnt ab (ohne Token, anderer Server).
  mTransport.SendStatus := 200;
  mTransport.SendFail := TAtlasCiFetchError.Unauthorized;
  Assert.IsFalse(mEditor.UpdateDescription(GitHubTarget, mTransportRef, '#753', 'x', 5000, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Unauthorized);
  // Transport ohne IAtlasCiSend: nicht einstellbar.
  mReadOnly := TFakeTransport.Create;
  mReadOnlyRef := mReadOnly;
  Assert.IsFalse(mEditor.UpdateDescription(GitHubTarget, mReadOnlyRef, '#753', 'x', 5000, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured);
  // Lesen: unbekanntes Issue, zu lange Beschreibung.
  Assert.IsFalse(mEditor.Description(GitHubTarget, mReadOnlyRef, '#9', 5000, mText, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound);
  mReadOnly.Answer('https://api.github.com/repos/beispiel/atlas/issues/8', 200,
    '{"number":8,"body":"' + StringOfChar('a', TAtlasTrackerDetails.MaxDescription + 1) + '"}');
  Assert.IsFalse(mEditor.Description(GitHubTarget, mReadOnlyRef, '#8', 5000, mText, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid);
  Assert.AreEqual('', mText);
end;

{ TAtlasTrackerLinkProviderTests }

const
  cYouTrackApi = 'https://beispiel.youtrack.cloud/api/';
  cGitHubIssues = 'https://api.github.com/repos/beispiel/atlas/issues';

function LinkOf(const ADetails: TAtlasTrackerDetails; const AKey: string): TAtlasTrackerLink;
var
  mLink: TAtlasTrackerLink;
begin
  for mLink in ADetails.Links do
    if mLink.Key = AKey then
      Exit(mLink);
  raise Exception.Create(AKey + ' fehlt');
end;

procedure TAtlasTrackerLinkProviderTests.YouTrackLinksEnglish;
var
  mDetails: TAtlasTrackerDetails;
  mDone, mTotal: Integer;
  mBlockers: TArray<TAtlasTrackerLink>;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDetails(Fixture('YouTrack', 'issue-links-en.json'), YouTrackTarget, False,
    mDetails));
  Assert.AreEqual(9, Integer(Length(mDetails.Links)));
  Assert.IsTrue(LinkOf(mDetails, 'ATL-129').Kind = TAtlasTrackerLinkKind.DependsOn, 'Depend, INWARD');
  Assert.AreEqual('depends on', LinkOf(mDetails, 'ATL-129').Relation);
  Assert.AreEqual('In Progress', LinkOf(mDetails, 'ATL-129').State, 'Feld State');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-129').StateKnown);
  Assert.IsFalse(LinkOf(mDetails, 'ATL-129').Resolved, 'resolved null');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-128').Resolved);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-140').Kind = TAtlasTrackerLinkKind.Blocks, 'Depend, OUTWARD');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-131').Kind = TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-100').Kind = TAtlasTrackerLinkKind.Parent);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-90').Kind = TAtlasTrackerLinkKind.Duplicates);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-77').Kind = TAtlasTrackerLinkKind.Relates);
  Assert.IsTrue(TAtlasTrackerLinks.Progress(mDetails.Links, mDone, mTotal));
  Assert.AreEqual('2/3', TAtlasTrackerLinks.ProgressText(mDone, mTotal));
  mBlockers := TAtlasTrackerLinks.WarnOnStart(True, mDetails);
  Assert.AreEqual(1, Integer(Length(mBlockers)));
  Assert.AreEqual('ATL-129', mBlockers[0].Key);
  Assert.IsTrue(TAtlasTrackerLinks.Locked(mDetails));
  // Älteres Fixture ohne resolved: Zustand unbekannt, keine Warnung; vertauschte Beschriftungen.
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDetails(Fixture('YouTrack', 'issue-details.json'), YouTrackTarget, False,
    mDetails));
  Assert.IsTrue(LinkOf(mDetails, 'ATL-100').Kind = TAtlasTrackerLinkKind.DependsOn);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-130').Kind = TAtlasTrackerLinkKind.Blocks);
  Assert.IsFalse(LinkOf(mDetails, 'ATL-100').StateKnown);
  Assert.IsFalse(TAtlasTrackerLinks.Locked(mDetails));
end;

procedure TAtlasTrackerLinkProviderTests.YouTrackLinksGerman;
var
  mDetails: TAtlasTrackerDetails;
begin
  Assert.IsTrue(TAtlasYouTrackTracker.ParseDetails(Fixture('YouTrack', 'issue-links-de.json'), YouTrackTarget, False,
    mDetails));
  Assert.AreEqual(7, Integer(Length(mDetails.Links)));
  Assert.IsTrue(LinkOf(mDetails, 'ATL-129').Kind = TAtlasTrackerLinkKind.DependsOn);
  Assert.AreEqual('hängt ab von', LinkOf(mDetails, 'ATL-129').Relation, 'Beschriftung der Oberfläche');
  Assert.AreEqual('In Bearbeitung', LinkOf(mDetails, 'ATL-129').State, 'Feld Zustand');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-140').Kind = TAtlasTrackerLinkKind.Blocks, 'eigener Name, deutsche Wendung');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-131').Kind = TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-133').Kind = TAtlasTrackerLinkKind.Subtask);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-150').Kind = TAtlasTrackerLinkKind.DependsOn, 'vertauschte Beschriftungen');
  Assert.IsTrue(LinkOf(mDetails, 'ATL-90').Kind = TAtlasTrackerLinkKind.Duplicates);
  Assert.IsTrue(LinkOf(mDetails, 'ATL-77').Kind = TAtlasTrackerLinkKind.Relates);
  Assert.AreEqual(2, Integer(Length(TAtlasTrackerLinks.OpenBlockers(mDetails.Links))), 'ATL-129 und ATL-150');
end;

procedure TAtlasTrackerLinkProviderTests.YouTrackLinkTypes;
var
  mTypes, mId: string;
begin
  mTypes := Fixture('YouTrack', 'issue-link-types.json');
  // Bekannte Namen gehen vor („Requirement“ steht davor).
  Assert.IsTrue(TAtlasYouTrackTracker.ParseLinkType(mTypes, TAtlasTrackerLinkKind.DependsOn, mId));
  Assert.AreEqual('80-1t', mId, 'Issue im Pfad ist das Ziel von „is required for“');
  Assert.IsTrue(TAtlasYouTrackTracker.ParseLinkType(mTypes, TAtlasTrackerLinkKind.Blocks, mId));
  Assert.AreEqual('80-1s', mId);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseLinkType(mTypes, TAtlasTrackerLinkKind.Subtask, mId));
  Assert.AreEqual('80-3s', mId);
  Assert.IsTrue(TAtlasYouTrackTracker.ParseLinkType(mTypes, TAtlasTrackerLinkKind.Parent, mId));
  Assert.AreEqual('80-3t', mId);
  // Ohne Depend: eigener Typ mit passenden Beschriftungen.
  Assert.IsTrue(TAtlasYouTrackTracker.ParseLinkType('[{"id": "80-9", "name": "Requirement", ' +
    '"sourceToTarget": "is required for", "targetToSource": "depends on"}]', TAtlasTrackerLinkKind.DependsOn, mId));
  Assert.AreEqual('80-9t', mId);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseLinkType('[{"id": "80-0", "name": "Relates"}]',
    TAtlasTrackerLinkKind.Subtask, mId));
  Assert.AreEqual('', mId);
  Assert.IsFalse(TAtlasYouTrackTracker.ParseLinkType('kein JSON', TAtlasTrackerLinkKind.Subtask, mId));
  Assert.AreEqual('https://beispiel.youtrack.cloud/api/issueLinkTypes?fields=' +
    'id%2Cname%2ClocalizedName%2CsourceToTarget%2ClocalizedSourceToTarget%2CtargetToSource%2C' +
    'localizedTargetToSource%2Caggregation', TAtlasYouTrackTracker.LinkTypesUrl(YouTrackTarget));
end;

procedure TAtlasTrackerLinkProviderTests.YouTrackCreateSubtaskRequests;
var
  mTransport: TFakePostTransport;
  mTransportRef: IAtlasCiTransport;
  mWriter: IAtlasTrackerLinkWriter;
  mKey: string;
  mError: TAtlasCiFetchError;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cYouTrackApi + 'issues/ATL-130?', 200, '{"id": "2-130", "project": {"id": "0-1"}}');
  mTransport.Answer(cYouTrackApi + 'issueLinkTypes', 200, Fixture('YouTrack', 'issue-link-types.json'));
  mTransport.AnswerPost(cYouTrackApi + 'issues?', 200, '{"idReadable": "ATL-134"}');
  mTransport.AnswerPost(cYouTrackApi + 'issues/ATL-130/links/', 200, '{"id": "80-3s"}');
  Assert.IsTrue(mWriter.CreateSubtask(YouTrackTarget, mTransportRef, 'ATL-130', ' Baum ', 'Text', 5000, mKey,
    mError));
  Assert.AreEqual('ATL-134', mKey);
  Assert.IsTrue(mError = TAtlasCiFetchError.None);
  Assert.AreEqual(2, Integer(Length(mTransport.Posts)));
  Assert.AreEqual('POST', mTransport.Methods[0]);
  Assert.AreEqual('POST', mTransport.Methods[0]);
  Assert.AreEqual(cYouTrackApi + 'issues?fields=idReadable', mTransport.Posts[0]);
  Assert.AreEqual('{"project":{"id":"0-1"},"summary":"Baum","description":"Text"}', mTransport.Bodies[0]);
  Assert.AreEqual(cYouTrackApi + 'issues/ATL-130/links/80-3s/issues?fields=id', mTransport.Posts[1]);
  Assert.AreEqual('{"idReadable":"ATL-134"}', mTransport.Bodies[1]);
  // Ohne Subtask-Typ entsteht kein loses Issue.
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cYouTrackApi + 'issues/ATL-130?', 200, '{"id": "2-130", "project": {"id": "0-1"}}');
  mTransport.Answer(cYouTrackApi + 'issueLinkTypes', 200, '[{"id": "80-0", "name": "Relates"}]');
  Assert.IsFalse(mWriter.CreateSubtask(YouTrackTarget, mTransportRef, 'ATL-130', 'Baum', '', 5000, mKey, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid);
  Assert.AreEqual(0, Integer(Length(mTransport.Posts)));
end;

procedure TAtlasTrackerLinkProviderTests.YouTrackAddLinkRequests;
var
  mTransport: TFakePostTransport;
  mTransportRef: IAtlasCiTransport;
  mWriter: IAtlasTrackerLinkWriter;
  mError: TAtlasCiFetchError;
begin
  mWriter := TAtlasYouTrackTracker.Create;
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cYouTrackApi + 'issueLinkTypes', 200, Fixture('YouTrack', 'issue-link-types.json'));
  mTransport.AnswerPost(cYouTrackApi + 'issues/', 200, '{}');
  Assert.IsTrue(mWriter.AddLink(YouTrackTarget, mTransportRef, 'ATL-130', TAtlasTrackerLinkKind.DependsOn, 'ATL-129',
    5000, mError));
  Assert.AreEqual(cYouTrackApi + 'issues/ATL-130/links/80-1t/issues?fields=id', mTransport.Posts[0]);
  Assert.AreEqual('{"idReadable":"ATL-129"}', mTransport.Bodies[0]);
  Assert.IsTrue(mWriter.AddLink(YouTrackTarget, mTransportRef, 'ATL-130', TAtlasTrackerLinkKind.Blocks, 'ATL-140',
    5000, mError));
  Assert.AreEqual(cYouTrackApi + 'issues/ATL-130/links/80-1s/issues?fields=id', mTransport.Posts[1]);
  Assert.AreEqual('{"idReadable":"ATL-140"}', mTransport.Bodies[1]);
  // Abgelehnt vom Server.
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cYouTrackApi + 'issueLinkTypes', 200, Fixture('YouTrack', 'issue-link-types.json'));
  mTransport.AnswerPost(cYouTrackApi + 'issues/', 403, '{"error": "forbidden"}');
  Assert.IsFalse(mWriter.AddLink(YouTrackTarget, mTransportRef, 'ATL-130', TAtlasTrackerLinkKind.DependsOn,
    'ATL-129', 5000, mError));
  Assert.IsFalse(mError = TAtlasCiFetchError.None);
end;

procedure TAtlasTrackerLinkProviderTests.GitHubRelationsFromFixtures;
var
  mSummary: TAtlasGitHubLinkSummary;
  mLinks, mExisting: TArray<TAtlasTrackerLink>;
  mLink: TAtlasTrackerLink;
begin
  mSummary := TAtlasGitHubTracker.ParseLinkSummary(Fixture('GitHub', 'issue-links-summary.json'));
  Assert.AreEqual(3, mSummary.SubIssues);
  Assert.AreEqual(1, mSummary.BlockedBy);
  Assert.AreEqual(0, mSummary.Blocking);
  mSummary := TAtlasGitHubTracker.ParseLinkSummary(Fixture('GitHub', 'issue-details.json'));
  Assert.AreEqual(-1, mSummary.SubIssues, 'ältere Server: unbekannt');
  Assert.AreEqual(-1, mSummary.BlockedBy);
  Assert.IsTrue(TAtlasGitHubTracker.ParseRelated(Fixture('GitHub', 'issue-sub-issues.json'), 'beispiel/atlas',
    TAtlasTrackerLinkKind.Subtask, mLinks));
  Assert.AreEqual(3, Integer(Length(mLinks)), 'ohne Nummer und Nicht-Objekte entfallen');
  Assert.AreEqual('#761', mLinks[0].Key);
  Assert.IsTrue(mLinks[0].Local);
  Assert.IsTrue(mLinks[0].Resolved);
  Assert.IsTrue(mLinks[0].Kind = TAtlasTrackerLinkKind.Subtask);
  Assert.AreEqual('sub-issue', mLinks[0].Relation);
  Assert.AreEqual('andere/repo#12', mLinks[2].Key);
  Assert.IsFalse(mLinks[2].Local);
  Assert.IsFalse(mLinks[2].Resolved);
  Assert.AreEqual('https://github.com/andere/repo/issues/12', mLinks[2].Page);
  Assert.IsFalse(TAtlasGitHubTracker.ParseRelated('{}', 'beispiel/atlas', TAtlasTrackerLinkKind.Subtask, mLinks));
  // Eine Erwähnung weicht der genaueren Art; dieselbe Art nicht doppelt.
  mLink := Default(TAtlasTrackerLink);
  mLink.Key := '#761';
  mLink.Kind := TAtlasTrackerLinkKind.Mentioned;
  mExisting := TArray<TAtlasTrackerLink>.Create(mLink);
  mLink.Key := '#900';
  mLink.Kind := TAtlasTrackerLinkKind.PullRequest;
  mExisting := mExisting + [mLink];
  Assert.IsTrue(TAtlasGitHubTracker.ParseRelated(Fixture('GitHub', 'issue-sub-issues.json'), 'beispiel/atlas',
    TAtlasTrackerLinkKind.Subtask, mLinks));
  TAtlasGitHubTracker.MergeLinks(mExisting, mLinks);
  TAtlasGitHubTracker.MergeLinks(mExisting, mLinks);
  Assert.AreEqual(4, Integer(Length(mExisting)));
  Assert.IsTrue(mExisting[0].Kind = TAtlasTrackerLinkKind.Subtask, 'an der Stelle der Erwähnung');
  Assert.AreEqual<Int64>(1753, TAtlasGitHubTracker.ParseIssueId(Fixture('GitHub', 'issue-links-summary.json')));
  Assert.AreEqual<Int64>(0, TAtlasGitHubTracker.ParseIssueId('{"number": 1}'));
end;

procedure TAtlasTrackerLinkProviderTests.GitHubDetailsWithRelations;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mDetails: TAtlasTrackerDetails;
  mError: TAtlasCiFetchError;
  mDone, mTotal: Integer;
  mCall: string;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cGitHubIssues + '/753/timeline', 200, Fixture('GitHub', 'issue-timeline.json'));
  mTransport.Answer(cGitHubIssues + '/753/sub_issues', 200, Fixture('GitHub', 'issue-sub-issues.json'));
  mTransport.Answer(cGitHubIssues + '/753/dependencies/blocked_by', 200, Fixture('GitHub', 'issue-blocked-by.json'));
  mTransport.Answer(cGitHubIssues + '/753', 200, Fixture('GitHub', 'issue-links-summary.json'));
  Assert.IsTrue(mProvider.Details(GitHubTarget, mTransportRef, '#753', True, 5000, mDetails, mError));
  // Issue (ohne Kommentare), Zeitleiste, Unteraufgaben, „blocked by“; „blocking“ meldet 0 und wird nicht
  // gefragt, mit „blocked by“ gelten keine Abhängigkeiten aus dem Text.
  Assert.AreEqual(4, Integer(Length(mTransport.Calls)));
  for mCall in mTransport.Calls do
    Assert.IsFalse(mCall.Contains('/dependencies/blocking'), mCall);
  Assert.AreEqual(5, Integer(Length(mDetails.Links)));
  Assert.IsTrue(LinkOf(mDetails, 'andere/repo#12').Kind = TAtlasTrackerLinkKind.Subtask, 'Erwähnung ersetzt');
  Assert.IsTrue(TAtlasTrackerLinks.Progress(mDetails.Links, mDone, mTotal));
  Assert.AreEqual('2/3', TAtlasTrackerLinks.ProgressText(mDone, mTotal));
  Assert.AreEqual(1, Integer(Length(TAtlasTrackerLinks.OpenBlockers(mDetails.Links))));
  Assert.AreEqual('#760', TAtlasTrackerLinks.OpenBlockers(mDetails.Links)[0].Key);
end;

procedure TAtlasTrackerLinkProviderTests.GitHubTextDependencies;
var
  mTransport: TFakeTransport;
  mTransportRef: IAtlasCiTransport;
  mProvider: IAtlasTrackerProvider;
  mDetails: TAtlasTrackerDetails;
  mError: TAtlasCiFetchError;
begin
  mProvider := TAtlasGitHubTracker.Create;
  mTransport := TFakeTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cGitHubIssues + '/753/timeline', 200, '[]');
  mTransport.Answer(cGitHubIssues + '/753', 200, '{"number": 753, "title": "x", "state": "open", ' +
    '"body": "Requires: #700, #753\nDie Arbeit depends on #701.", "sub_issues_summary": {"total": 0}, ' +
    '"issue_dependencies_summary": {"total_blocked_by": 0, "total_blocking": 0}}');
  mTransport.Answer(cGitHubIssues + '/700', 200, '{"number": 700, "title": "Basis", "state": "closed"}');
  Assert.IsTrue(mProvider.Details(GitHubTarget, mTransportRef, '#753', True, 5000, mDetails, mError));
  // Issue (ohne Kommentare), Zeitleiste, dann je Nummer aus dem Text (nicht das Issue selbst).
  Assert.AreEqual(4, Integer(Length(mTransport.Calls)));
  Assert.AreEqual(2, Integer(Length(mDetails.Links)));
  Assert.AreEqual('#700', mDetails.Links[0].Key);
  Assert.IsTrue(mDetails.Links[0].Kind = TAtlasTrackerLinkKind.DependsOn);
  Assert.AreEqual('Basis', mDetails.Links[0].Title);
  Assert.IsTrue(mDetails.Links[0].StateKnown);
  Assert.IsTrue(mDetails.Links[0].Resolved);
  Assert.AreEqual('#701', mDetails.Links[1].Key);
  Assert.IsFalse(mDetails.Links[1].StateKnown, '404: Zustand unbekannt');
  Assert.AreEqual('https://github.com/beispiel/atlas/issues/701', mDetails.Links[1].Page);
  Assert.IsFalse(TAtlasTrackerLinks.Locked(mDetails), 'unbekannt warnt nicht');
end;

procedure TAtlasTrackerLinkProviderTests.GitHubCreateSubtaskRequests;
var
  mTransport: TFakePostTransport;
  mTransportRef: IAtlasCiTransport;
  mWriter: IAtlasTrackerLinkWriter;
  mKey: string;
  mError: TAtlasCiFetchError;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  // Längere Anfänge zuerst.
  mTransport.AnswerPost(cGitHubIssues + '/753/sub_issues', 201, '{}');
  mTransport.AnswerPost(cGitHubIssues, 201, '{"id": 9001, "number": 770}');
  Assert.IsTrue(mWriter.CreateSubtask(GitHubTarget, mTransportRef, '#753', 'Baum', 'Text', 5000, mKey, mError));
  Assert.AreEqual('#770', mKey);
  Assert.AreEqual(2, Integer(Length(mTransport.Posts)));
  Assert.AreEqual('POST', mTransport.Methods[0]);
  Assert.AreEqual('POST', mTransport.Methods[0]);
  Assert.AreEqual(cGitHubIssues, mTransport.Posts[0]);
  Assert.AreEqual('{"title":"Baum","body":"Text"}', mTransport.Bodies[0]);
  Assert.AreEqual(cGitHubIssues + '/753/sub_issues', mTransport.Posts[1]);
  Assert.AreEqual('{"sub_issue_id":9001}', mTransport.Bodies[1]);
  // Angelegt, aber nicht verknüpft: Kennung bleibt für die Meldung.
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.AnswerPost(cGitHubIssues + '/753/sub_issues', 422, '{}');
  mTransport.AnswerPost(cGitHubIssues, 201, '{"id": 9002, "number": 771}');
  Assert.IsFalse(mWriter.CreateSubtask(GitHubTarget, mTransportRef, '#753', 'Baum', '', 5000, mKey, mError));
  Assert.AreEqual('#771', mKey);
  Assert.AreEqual('{"title":"Baum"}', mTransport.Bodies[0], 'ohne Beschreibung kein body');
end;

procedure TAtlasTrackerLinkProviderTests.GitHubAddLinkRequests;
var
  mTransport: TFakePostTransport;
  mTransportRef: IAtlasCiTransport;
  mWriter: IAtlasTrackerLinkWriter;
  mError: TAtlasCiFetchError;
begin
  mWriter := TAtlasGitHubTracker.Create;
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  mTransport.Answer(cGitHubIssues + '/760', 200, '{"id": 2760, "number": 760}');
  mTransport.Answer(cGitHubIssues + '/753', 200, '{"id": 1753, "number": 753}');
  mTransport.AnswerPost(cGitHubIssues, 201, '{}');
  // #753 hängt ab von #760: #753 wird von #760 blockiert.
  Assert.IsTrue(mWriter.AddLink(GitHubTarget, mTransportRef, '#753', TAtlasTrackerLinkKind.DependsOn, '#760', 5000,
    mError));
  Assert.AreEqual(cGitHubIssues + '/753/dependencies/blocked_by', mTransport.Posts[0]);
  Assert.AreEqual('{"issue_id":2760}', mTransport.Bodies[0]);
  // #753 blockiert #760.
  Assert.IsTrue(mWriter.AddLink(GitHubTarget, mTransportRef, '#753', TAtlasTrackerLinkKind.Blocks, '#760', 5000,
    mError));
  Assert.AreEqual(cGitHubIssues + '/760/dependencies/blocked_by', mTransport.Posts[1]);
  Assert.AreEqual('{"issue_id":1753}', mTransport.Bodies[1]);
  // Unbekanntes Issue: kein POST.
  Assert.IsFalse(mWriter.AddLink(GitHubTarget, mTransportRef, '#753', TAtlasTrackerLinkKind.DependsOn, '#999', 5000,
    mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotFound);
  Assert.AreEqual(2, Integer(Length(mTransport.Posts)));
end;

procedure TAtlasTrackerLinkProviderTests.WritesRefused;
var
  mReader: TFakeTransport;
  mReaderRef: IAtlasCiTransport;
  mTransport: TFakePostTransport;
  mTransportRef: IAtlasCiTransport;
  mWriter: IAtlasTrackerLinkWriter;
  mKey: string;
  mError: TAtlasCiFetchError;
begin
  mReader := TFakeTransport.Create;
  mReaderRef := mReader;
  mWriter := TAtlasGitHubTracker.Create;
  Assert.IsFalse(mWriter.CreateSubtask(GitHubTarget, mReaderRef, '#753', 'Baum', '', 5000, mKey, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured, 'Transport kann nicht schreiben');
  mTransport := TFakePostTransport.Create;
  mTransportRef := mTransport;
  Assert.IsFalse(mWriter.CreateSubtask(GitHubTarget, mTransportRef, '#753', '  ', '', 5000, mKey, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid, 'ohne Titel');
  Assert.IsFalse(mWriter.AddLink(GitHubTarget, mTransportRef, '#753', TAtlasTrackerLinkKind.Relates, '#760', 5000,
    mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid, 'nur „hängt ab von“ und „blockiert“');
  Assert.IsFalse(mWriter.AddLink(GitHubTarget, mTransportRef, '#753', TAtlasTrackerLinkKind.DependsOn, '#753', 5000,
    mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid, 'nicht mit sich selbst');
  mWriter := TAtlasYouTrackTracker.Create;
  Assert.IsFalse(mWriter.AddLink(YouTrackTarget, mTransportRef, 'ATL-130', TAtlasTrackerLinkKind.Blocks, 'atl-130',
    5000, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.Invalid);
  Assert.IsFalse(mWriter.CreateSubtask(YouTrackTarget, mReaderRef, 'ATL-130', 'Baum', '', 5000, mKey, mError));
  Assert.IsTrue(mError = TAtlasCiFetchError.NotConfigured);
  Assert.AreEqual(0, Integer(Length(mTransport.Posts)));
  Assert.AreEqual(0, Integer(Length(mTransport.Calls)));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerTargetTests);
  TDUnitX.RegisterTestFixture(TAtlasTrackerNamingTests);
  TDUnitX.RegisterTestFixture(TAtlasGitHubTrackerTests);
  TDUnitX.RegisterTestFixture(TAtlasYouTrackTrackerTests);
  TDUnitX.RegisterTestFixture(TAtlasTrackerDetailsTests);
  TDUnitX.RegisterTestFixture(TAtlasTrackerDescriptionsTests);
  TDUnitX.RegisterTestFixture(TAtlasTrackerLinkProviderTests);
  TDUnitX.RegisterTestFixture(TAtlasCommitHookTests);

end.
