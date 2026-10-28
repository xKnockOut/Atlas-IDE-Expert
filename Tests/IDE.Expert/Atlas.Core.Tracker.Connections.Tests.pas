unit Atlas.Core.Tracker.Connections.Tests;

// Tests der Tracker-Verbindungen (#1260) ohne Netz: Liste lesen und
// schreiben, Adresse nur https ohne Benutzer, eindeutige Namen, Adresse der
// Prüfung je Anbieter und Zuordnung der Prüfantworten zu den Zuständen aus
// Beispieldateien (Tests\Data\YouTrack, Tests\Data\GitHub).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasTrackerConnectionsTests = class
  public
    /// <summary>Abnahme: zwei Verbindungen (YouTrack selbst gehostet, GitHub) hin und zurück.</summary>
    [Test]
    procedure ReadAndWriteRoundTrip;
    [Test]
    procedure ReadSkipsIncompleteAndDuplicateEntries;
    /// <summary>Abnahme: http und Adressen mit Benutzer werden abgewiesen.</summary>
    [Test]
    procedure CheckUrlAcceptsOnlyHttpsWithoutUser;
    [Test]
    procedure NamesAreUnique;
    [Test]
    procedure TeamFileConnectionIsReadOnly;
    [Test]
    procedure ProbeUrlsPerProvider;
    /// <summary>Abnahme: Prüfantworten aus Beispieldateien → gespeichert · geprüft, abgelehnt, unerwartet.</summary>
    [Test]
    procedure StatesFromFixtures;
    /// <summary>Abnahme: ohne Token „fehlt“ und kein Netzzugriff.</summary>
    [Test]
    procedure CheckWithoutTokenIsMissing;
    /// <summary>Genau ein GET auf die Adresse der Prüfung mit 5 s; ohne Antwort „nicht erreichbar“.</summary>
    [Test]
    procedure CheckAsksOnceWithTimeout;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack;

type
  /// <summary>Transport mit einer festen Antwort; merkt Adressen und Zeitgrenzen.</summary>
  TFakeTransport = class(TInterfacedObject, IAtlasCiTransport)
  private
    FStatus: Integer;
    FText: string;
    FFail: TAtlasCiFetchError;
  public
    Calls: TArray<string>;
    Timeouts: TArray<Integer>;
    constructor Create(AStatus: Integer; const AText: string; AFail: TAtlasCiFetchError);
    function Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
      out AError: TAtlasCiFetchError): Boolean;
  end;

constructor TFakeTransport.Create(AStatus: Integer; const AText: string; AFail: TAtlasCiFetchError);
begin
  inherited Create;
  FStatus := AStatus;
  FText := AText;
  FFail := AFail;
end;

function TFakeTransport.Get(const AUrl: string; ATimeoutMs: Integer; out AStatus: Integer; out AText: string;
  out AError: TAtlasCiFetchError): Boolean;
begin
  Calls := Calls + [AUrl];
  Timeouts := Timeouts + [ATimeoutMs];
  AStatus := FStatus;
  AText := FText;
  AError := FFail;
  Result := FFail = TAtlasCiFetchError.None;
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

{ TAtlasTrackerConnectionsTests }

procedure TAtlasTrackerConnectionsTests.ReadAndWriteRoundTrip;
var
  mItems, mAgain: TArray<TAtlasTrackerConnection>;
  mJson: string;
begin
  mItems := TAtlasTrackerConnections.Read('[{"name": "Firma", "provider": "YouTrack", ' +
    '"url": "https://youtrack.firma.local/"}, {"name": "GitHub", "provider": "github", "url": "https://github.com"}]');
  Assert.AreEqual(2, Integer(Length(mItems)));
  Assert.AreEqual('Firma', mItems[0].Name);
  Assert.AreEqual('youtrack', mItems[0].Provider, 'Anbieter klein');
  Assert.AreEqual('https://youtrack.firma.local', mItems[0].Url, 'ohne „/“ am Ende');
  Assert.IsFalse(mItems[0].ReadOnly);
  Assert.AreEqual('Atlas:tracker:https://youtrack.firma.local', mItems[0].Target.CredentialTarget);
  mJson := TAtlasTrackerConnections.ToJson(mItems);
  Assert.AreEqual('[{"name": "Firma", "provider": "youtrack", "url": "https://youtrack.firma.local"}, ' +
    '{"name": "GitHub", "provider": "github", "url": "https://github.com"}]', mJson);
  Assert.IsFalse(mJson.ToLower.Contains('token'), 'nie ein Token');
  mAgain := TAtlasTrackerConnections.Read(mJson);
  Assert.AreEqual(2, Integer(Length(mAgain)));
  Assert.AreEqual('https://github.com', mAgain[1].Url);
  Assert.AreEqual('[]', TAtlasTrackerConnections.ToJson(nil));
  mItems := nil;
  mAgain := nil;
end;

procedure TAtlasTrackerConnectionsTests.ReadSkipsIncompleteAndDuplicateEntries;
var
  mItems: TArray<TAtlasTrackerConnection>;
begin
  mItems := TAtlasTrackerConnections.Read('[{"name": "A", "provider": "github", "url": "https://github.com"},' +
    ' {"name": "a", "provider": "youtrack", "url": "https://yt.local"}, {"provider": "github", "url": "https://x"},' +
    ' {"name": "B", "url": "https://x"}, {"name": "C", "provider": "github"}, 3, "D"]');
  Assert.AreEqual(1, Integer(Length(mItems)), 'Doppelname, ohne Name, ohne Anbieter, ohne Adresse, keine Objekte');
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerConnections.Read(''))));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerConnections.Read('{"name": "A"}'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTrackerConnections.Read('[{"name": '))));
  mItems := nil;
end;

procedure TAtlasTrackerConnectionsTests.CheckUrlAcceptsOnlyHttpsWithoutUser;
begin
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.Valid),
    Ord(TAtlasTrackerConnections.CheckUrl('https://youtrack.firma.local')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.Valid),
    Ord(TAtlasTrackerConnections.CheckUrl('https://firma.de:8443/youtrack/')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.NotHttps), Ord(TAtlasTrackerConnections.CheckUrl('http://yt.local')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.NotHttps), Ord(TAtlasTrackerConnections.CheckUrl('yt.local')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.WithUser),
    Ord(TAtlasTrackerConnections.CheckUrl('https://marco@yt.local')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.WithUser),
    Ord(TAtlasTrackerConnections.CheckUrl('https://marco:perm-geheim@yt.local/api')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.Empty), Ord(TAtlasTrackerConnections.CheckUrl('  ')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.Invalid), Ord(TAtlasTrackerConnections.CheckUrl('https://')));
  Assert.AreEqual(Ord(TAtlasTrackerUrlCheck.Invalid), Ord(TAtlasTrackerConnections.CheckUrl('https://yt local')));
end;

procedure TAtlasTrackerConnectionsTests.NamesAreUnique;
var
  mItems: TArray<TAtlasTrackerConnection>;
begin
  mItems := [TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local'),
    TAtlasTrackerConnection.Create('Neue Verbindung', 'github', '')];
  Assert.AreEqual(0, TAtlasTrackerConnections.IndexOfName(mItems, ' firma '));
  Assert.AreEqual(-1, TAtlasTrackerConnections.IndexOfName(mItems, 'GitHub'));
  Assert.IsTrue(TAtlasTrackerConnections.NameTaken(mItems, 'FIRMA', 1), 'vergeben');
  Assert.IsFalse(TAtlasTrackerConnections.NameTaken(mItems, 'Firma', 0), 'eigener Name');
  Assert.IsTrue(TAtlasTrackerConnections.NameTaken(mItems, ' ', -1), 'leer');
  Assert.AreEqual('Neue Verbindung 2', TAtlasTrackerConnections.FreeName(mItems, 'Neue Verbindung'));
  Assert.AreEqual('GitHub', TAtlasTrackerConnections.FreeName(mItems, 'GitHub'));
  mItems := nil;
end;

procedure TAtlasTrackerConnectionsTests.TeamFileConnectionIsReadOnly;
var
  mTeam: TAtlasTrackerConnection;
  mItems: TArray<TAtlasTrackerConnection>;
begin
  mTeam := TAtlasTrackerConnection.FromTeamFile('Atlas', TAtlasTrackerTarget.Create('github',
    'https://github.com/xKnockOut/Atlas-IDE-Expert', '', ''));
  Assert.IsTrue(mTeam.ReadOnly);
  Assert.AreEqual('https://github.com', mTeam.Url, 'Projekt aus der Adresse, Server bleibt');
  mItems := [TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local'), mTeam];
  // Nur persönliche Verbindungen kommen in settings.json.
  Assert.AreEqual('[{"name": "Firma", "provider": "youtrack", "url": "https://yt.local"}]',
    TAtlasTrackerConnections.ToJson(mItems));
  mItems := nil;
end;

procedure TAtlasTrackerConnectionsTests.ProbeUrlsPerProvider;
var
  mYouTrack, mGitHub: IAtlasTrackerProvider;
begin
  mYouTrack := TAtlasYouTrackTracker.Create;
  mGitHub := TAtlasGitHubTracker.Create;
  Assert.AreEqual('https://youtrack.firma.local/api/users/me?fields=login', mYouTrack.ProbeUrl(
    TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://youtrack.firma.local/').Target));
  Assert.AreEqual('https://firma.de/youtrack/api/users/me?fields=login', mYouTrack.ProbeUrl(
    TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://firma.de/youtrack').Target));
  Assert.AreEqual('https://api.github.com/user', mGitHub.ProbeUrl(
    TAtlasTrackerConnection.Create('GitHub', 'github', 'https://github.com').Target));
  Assert.AreEqual('https://git.firma.de/api/v3/user', mGitHub.ProbeUrl(
    TAtlasTrackerConnection.Create('GHE', 'github', 'https://git.firma.de').Target));
  Assert.AreEqual('', mYouTrack.ProbeUrl(TAtlasTrackerConnection.Create('X', 'youtrack', 'ftp://x').Target));
end;

procedure TAtlasTrackerConnectionsTests.StatesFromFixtures;
begin
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Verified), Ord(TAtlasTrackerConnections.StateOf(True, 200,
    Fixture('YouTrack', 'users-me.json'))));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Rejected), Ord(TAtlasTrackerConnections.StateOf(True, 401,
    Fixture('YouTrack', 'users-me-401.json'))));
  // Anmeldeseite eines Proxys mit 200: kein Benutzer, also nicht geprüft.
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Unexpected), Ord(TAtlasTrackerConnections.StateOf(True, 200,
    Fixture('YouTrack', 'login-page.html'))));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Verified), Ord(TAtlasTrackerConnections.StateOf(True, 200,
    Fixture('GitHub', 'user.json'))));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Rejected), Ord(TAtlasTrackerConnections.StateOf(True, 403,
    Fixture('GitHub', 'user-401.json'))));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Unexpected), Ord(TAtlasTrackerConnections.StateOf(True, 404, '')));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Unexpected), Ord(TAtlasTrackerConnections.StateOf(True, 500,
    Fixture('GitHub', 'user.json'))));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Unreachable), Ord(TAtlasTrackerConnections.StateOf(False, 0, '')));
end;

procedure TAtlasTrackerConnectionsTests.CheckWithoutTokenIsMissing;
var
  mStatus: TAtlasTrackerTokenStatus;
  mNow: TDateTime;
  mProvider: IAtlasTrackerProvider;
begin
  mNow := EncodeDate(2026, 10, 28) + EncodeTime(10, 18, 0, 0);
  mProvider := TAtlasYouTrackTracker.Create;
  mStatus := TAtlasTrackerConnections.Check(mProvider,
    TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local').Target, nil, mNow);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Missing), Ord(mStatus.State));
  Assert.AreEqual(0, mStatus.HttpStatus);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Missing), Ord(TAtlasTrackerTokenStatus.Stored(False).State));
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Saved), Ord(TAtlasTrackerTokenStatus.Stored(True).State));
end;

procedure TAtlasTrackerConnectionsTests.CheckAsksOnceWithTimeout;
var
  mTransport: TFakeTransport;
  mKeep: IAtlasCiTransport;
  mStatus: TAtlasTrackerTokenStatus;
  mNow: TDateTime;
  mTarget: TAtlasTrackerTarget;
  mProvider: IAtlasTrackerProvider;
begin
  mNow := EncodeDate(2026, 10, 28) + EncodeTime(10, 18, 0, 0);
  mProvider := TAtlasYouTrackTracker.Create;
  mTarget := TAtlasTrackerConnection.Create('Firma', 'youtrack', 'https://yt.local').Target;
  mTransport := TFakeTransport.Create(200, Fixture('YouTrack', 'users-me.json'), TAtlasCiFetchError.None);
  mKeep := mTransport;
  mStatus := TAtlasTrackerConnections.Check(mProvider, mTarget, mKeep, mNow);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Verified), Ord(mStatus.State));
  Assert.AreEqual(200, mStatus.HttpStatus);
  Assert.IsTrue(mStatus.CheckedAt = mNow, 'Zeit der Prüfung');
  Assert.AreEqual('https://yt.local/api/users/me?fields=login', mTransport.Calls[0]);
  Assert.AreEqual(TAtlasTrackerConnections.CheckTimeoutMs, mTransport.Timeouts[0]);
  // Danach in der restlichen Zeit die Sprache der Oberfläche (#1263): localeSettings, ohne Antwort darauf die Probe
  // mit beiden Vorlagen; die feste Antwort hier nennt keine Sprache.
  Assert.AreEqual(4, Integer(Length(mTransport.Calls)));
  Assert.IsTrue(mTransport.Calls[1].StartsWith('https://yt.local/api/admin/globalSettings/localeSettings'),
    mTransport.Calls[1]);
  Assert.IsTrue(mTransport.Timeouts[1] <= TAtlasTrackerConnections.CheckTimeoutMs);
  Assert.AreEqual('', mStatus.Language);
  Assert.AreEqual(5000, TAtlasTrackerConnections.CheckTimeoutMs);
  // Nicht erreichbar (Zeitlimit, kein Netz): ohne Dialog, ohne Status.
  mTransport := TFakeTransport.Create(0, '', TAtlasCiFetchError.Timeout);
  mKeep := mTransport;
  mStatus := TAtlasTrackerConnections.Check(mProvider, mTarget, mKeep, mNow);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Unreachable), Ord(mStatus.State));
  Assert.AreEqual(0, mStatus.HttpStatus);
  // Abgelehnt.
  mTransport := TFakeTransport.Create(401, Fixture('YouTrack', 'users-me-401.json'), TAtlasCiFetchError.None);
  mKeep := mTransport;
  mStatus := TAtlasTrackerConnections.Check(mProvider, mTarget, mKeep, mNow);
  Assert.AreEqual(Ord(TAtlasTrackerTokenState.Rejected), Ord(mStatus.State));
  Assert.AreEqual(401, mStatus.HttpStatus);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerConnectionsTests);

end.
