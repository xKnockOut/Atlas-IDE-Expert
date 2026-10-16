unit Atlas.Core.Ci.Providers.Jenkins.Tests;

// Tests des CI-Anbieters Jenkins ohne Server (#763): Job aus .atlas,
// Adressen der REST-API (Ordner, Multibranch, Kodierung), Lesen von Build und
// Testbericht aus Beispieldateien (Tests\Data\Jenkins, auch mit Teilberichten)
// und der Ablauf einer Abfrage über einen Transport mit festen Antworten
// (Zeitlimit, Anmeldung abgelehnt, kein Testbericht).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCiJobTests = class
  public
    [Test]
    procedure CreateTrimsAndLowercasesProvider;
    [Test]
    procedure ConfiguredNeedsServerJobAndBranch;
    /// <summary>Zugangsdaten nie aus der Adresse übernehmen; Eintrag im Anmeldespeicher je Server.</summary>
    [Test]
    procedure ServerAndCredentialTarget;
    [Test]
    procedure KeysOfOutcomeAndError;
  end;

  [TestFixture]
  TAtlasCiAddressesTests = class
  public
    /// <summary>Token nur über https und nur an den eingetragenen Server.</summary>
    [Test]
    procedure AuthenticateOnlyOverHttpsAtServer;
    /// <summary>Weiterleitungen nur auf denselben Rechner (http → https erlaubt).</summary>
    [Test]
    procedure RedirectsStayOnHost;
    [Test]
    procedure ResolveRelativeLocation;
  end;

  [TestFixture]
  TAtlasJenkinsProviderTests = class
  public
    [Test]
    procedure JobUrlWithFoldersAndMultibranch;
    [Test]
    procedure ApiUrlsAskOnlyNeededFields;
    /// <summary>Abnahme: Build-Nummer und Ergebnis aus lastCompletedBuild/api/json.</summary>
    [Test]
    procedure ParsesLastCompletedBuildFromFixture;
    /// <summary>Abnahme: Jenkins-Testbericht (JSON aus einer Beispieldatei) lesen.</summary>
    [Test]
    procedure ParsesTestReportFromFixture;
    [Test]
    procedure ParsesChildReportsFromFixture;
    [Test]
    procedure RejectsInvalidAnswers;
    [Test]
    procedure ErrorOfStatus;
    [Test]
    procedure FetchReadsBuildAndReport;
    [Test]
    procedure FetchWithoutReportKeepsBuild;
    /// <summary>Server nicht erreichbar: kein Build, Fehler statt Ausnahme.</summary>
    [Test]
    procedure FetchReportsNetworkAndAuthErrors;
    [Test]
    procedure FetchWithoutConfigurationDoesNotCallTransport;
    /// <summary>Abnahme: „Im Browser“ öffnet die Build-Seite.</summary>
    [Test]
    procedure BuildPage;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Ci.Internals.Addresses,
  Atlas.Core.Ci.Providers.Jenkins;

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
    Timeouts: TArray<Integer>;
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
  Timeouts := Timeouts + [ATimeoutMs];
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

/// <summary>Datei aus Tests\Data\Jenkins, gesucht ab dem Ordner des Testprogramms aufwärts.</summary>
function Fixture(const AName: string): string;
var
  Directory, FileName: string;
begin
  Directory := ExtractFileDir(ParamStr(0));
  while Directory <> '' do
  begin
    FileName := TPath.Combine(Directory, TPath.Combine('Tests', TPath.Combine('Data',
      TPath.Combine('Jenkins', AName))));
    if TFile.Exists(FileName) then
      Exit(TFile.ReadAllText(FileName, TEncoding.UTF8));
    if ExtractFileDir(Directory) = Directory then
      Break;
    Directory := ExtractFileDir(Directory);
  end;
  raise Exception.Create('Tests\Data\Jenkins\' + AName + ' nicht gefunden');
end;

function Job: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'team/kasse', False, 'main');
end;

{ TAtlasCiJobTests }

procedure TAtlasCiJobTests.CreateTrimsAndLowercasesProvider;
var
  Value: TAtlasCiJob;
begin
  Value := TAtlasCiJob.Create(' Jenkins ', ' https://ci.firma.de/jenkins// ', '/team/kasse/', True, ' main ');
  Assert.AreEqual('jenkins', Value.Provider);
  Assert.AreEqual('https://ci.firma.de/jenkins', Value.Url);
  Assert.AreEqual('team/kasse', Value.Job);
  Assert.AreEqual('main', Value.Branch);
  Assert.AreEqual('main', Value.JobBranch);
  Assert.AreEqual('jenkins|https://ci.firma.de/jenkins|team/kasse|main', Value.Key);
  Value.Multibranch := False;
  Assert.AreEqual('', Value.JobBranch, 'ohne Multibranch gehört der Branch nicht zum Job');
end;

procedure TAtlasCiJobTests.ConfiguredNeedsServerJobAndBranch;
begin
  Assert.IsTrue(Job.Configured);
  Assert.IsFalse(TAtlasCiJob.Create('jenkins', '', 'kasse', False, '').Configured);
  Assert.IsFalse(TAtlasCiJob.Create('jenkins', 'ci.firma.de', 'kasse', False, '').Configured, 'ohne Schema');
  Assert.IsFalse(TAtlasCiJob.Create('jenkins', 'https://ci', '', False, '').Configured);
  Assert.IsFalse(TAtlasCiJob.Create('', 'https://ci', 'kasse', False, '').Configured);
  Assert.IsFalse(TAtlasCiJob.Create('jenkins', 'https://ci', 'kasse', True, '').Configured,
    'Multibranch ohne Branch');
  Assert.IsTrue(TAtlasCiJob.Create('jenkins', 'https://ci', 'kasse', True, 'main').Configured);
end;

procedure TAtlasCiJobTests.ServerAndCredentialTarget;
begin
  Assert.AreEqual('https://ci.firma.de:8443',
    TAtlasCiJob.Create('jenkins', 'HTTPS://CI.Firma.de:8443/jenkins', 'k', False, '').Server);
  Assert.AreEqual('Atlas:ci:https://ci.firma.de:8443',
    TAtlasCiJob.Create('jenkins', 'https://ci.firma.de:8443/jenkins', 'k', False, '').CredentialTarget);
  Assert.AreEqual('', TAtlasCiJob.Create('jenkins', 'https://user:token@ci.firma.de', 'k', False, '').Server,
    'Zugangsdaten in der Adresse');
  Assert.AreEqual('', TAtlasCiJob.Create('jenkins', 'ftp://ci', 'k', False, '').Server);
  Assert.AreEqual('', TAtlasCiJob.Create('jenkins', '', 'k', False, '').CredentialTarget);
  Assert.IsTrue(Job.Secure);
  Assert.IsFalse(TAtlasCiJob.Create('jenkins', 'http://ci', 'k', False, '').Secure);
end;

procedure TAtlasCiJobTests.KeysOfOutcomeAndError;
var
  Outcome: TAtlasCiOutcome;
  Error: TAtlasCiFetchError;
begin
  for Outcome := Low(TAtlasCiOutcome) to High(TAtlasCiOutcome) do
    Assert.IsTrue(TAtlasCiBuild.OutcomeOf(TAtlasCiBuild.OutcomeKey(Outcome)) = Outcome);
  for Error := Low(TAtlasCiFetchError) to High(TAtlasCiFetchError) do
    Assert.IsTrue(TAtlasCiBuild.ErrorOf(TAtlasCiBuild.ErrorKey(Error)) = Error);
  Assert.AreEqual('', TAtlasCiBuild.ErrorKey(TAtlasCiFetchError.None));
  Assert.IsTrue(TAtlasCiBuild.OutcomeOf('seltsam') = TAtlasCiOutcome.Unknown);
  Assert.IsTrue(TAtlasCiBuild.ErrorOf('seltsam') = TAtlasCiFetchError.Network);
end;

{ TAtlasCiAddressesTests }

procedure TAtlasCiAddressesTests.AuthenticateOnlyOverHttpsAtServer;
begin
  Assert.IsTrue(TAtlasCiAddresses.MayAuthenticate('https://ci.firma.de/job/x/api/json', 'https://ci.firma.de'));
  Assert.IsTrue(TAtlasCiAddresses.MayAuthenticate('HTTPS://CI.firma.de/job', 'https://ci.firma.de'));
  Assert.IsFalse(TAtlasCiAddresses.MayAuthenticate('http://ci.firma.de/job', 'http://ci.firma.de'), 'nie über http');
  Assert.IsFalse(TAtlasCiAddresses.MayAuthenticate('https://login.example/job', 'https://ci.firma.de'));
  Assert.IsFalse(TAtlasCiAddresses.MayAuthenticate('https://ci.firma.de:8443/job', 'https://ci.firma.de'),
    'anderer Port');
  Assert.IsFalse(TAtlasCiAddresses.MayAuthenticate('https://ci.firma.de.example/job', 'https://ci.firma.de'));
end;

procedure TAtlasCiAddressesTests.RedirectsStayOnHost;
begin
  Assert.IsTrue(TAtlasCiAddresses.RedirectAllowed('https://ci/job/a', 'https://ci/job/a/'));
  Assert.IsTrue(TAtlasCiAddresses.RedirectAllowed('http://ci/job/a', 'https://ci/job/a'), 'http → https');
  Assert.IsTrue(TAtlasCiAddresses.RedirectAllowed('http://ci:8080/job/a', 'https://ci:8443/job/a'));
  Assert.IsFalse(TAtlasCiAddresses.RedirectAllowed('https://ci/job/a', 'http://ci/job/a'), 'nicht zurück auf http');
  Assert.IsFalse(TAtlasCiAddresses.RedirectAllowed('https://ci/job/a', 'https://sso.example/login'));
  Assert.IsFalse(TAtlasCiAddresses.RedirectAllowed('https://ci/job/a', ''));
  Assert.IsFalse(TAtlasCiAddresses.RedirectAllowed('https://ci/job/a', 'https://user@ci/job/a'));
  Assert.AreEqual('ci.firma.de', TAtlasCiAddresses.HostOf('https://ci.firma.de:8443'));
end;

procedure TAtlasCiAddressesTests.ResolveRelativeLocation;
begin
  Assert.AreEqual('https://ci:8443/job/b/', TAtlasCiAddresses.Resolve('https://ci:8443/job/a', '/job/b/'));
  Assert.AreEqual('https://other/x', TAtlasCiAddresses.Resolve('https://ci/job/a', ' https://other/x '));
  Assert.AreEqual('//other/x', TAtlasCiAddresses.Resolve('https://ci/job/a', '//other/x'),
    'ohne Schema bleibt ungültig');
end;

{ TAtlasJenkinsProviderTests }

procedure TAtlasJenkinsProviderTests.JobUrlWithFoldersAndMultibranch;
begin
  Assert.AreEqual('https://ci.firma.de/job/team/job/kasse', TAtlasJenkinsProvider.JobUrl(Job));
  Assert.AreEqual('https://ci.firma.de/jenkins/job/Kasse%20Neu',
    TAtlasJenkinsProvider.JobUrl(TAtlasCiJob.Create('jenkins', 'https://ci.firma.de/jenkins/', 'Kasse Neu', False,
    'main')));
  // Multibranch: Jenkins führt den Branch kodiert, in der Adresse noch einmal kodiert.
  Assert.AreEqual('https://ci/job/kasse/job/feature%252F763-tests',
    TAtlasJenkinsProvider.JobUrl(TAtlasCiJob.Create('jenkins', 'https://ci', 'kasse', True, 'feature/763-tests')));
  Assert.AreEqual('https://ci/job/kasse/job/main',
    TAtlasJenkinsProvider.JobUrl(TAtlasCiJob.Create('jenkins', 'https://ci', 'kasse', True, 'main')));
  Assert.AreEqual('%C3%BC%2F', TAtlasJenkinsProvider.Encode(#$00FC'/'));
  Assert.AreEqual('', TAtlasJenkinsProvider.JobUrl(TAtlasCiJob.Create('jenkins', '', 'kasse', False, '')));
end;

procedure TAtlasJenkinsProviderTests.ApiUrlsAskOnlyNeededFields;
var
  Url: string;
begin
  Assert.AreEqual('https://ci.firma.de/job/team/job/kasse/lastCompletedBuild/api/json?' +
    'tree=number,result,timestamp,duration', TAtlasJenkinsProvider.BuildApiUrl(Job));
  Url := TAtlasJenkinsProvider.TestReportApiUrl(Job, 482);
  Assert.StartsWith('https://ci.firma.de/job/team/job/kasse/482/testReport/api/json?tree=passCount,failCount,' +
    'skipCount,suites%5Bcases%5BclassName,name,status,errorDetails%5D%5D', Url);
  Assert.Contains(Url, 'childReports%5Bresult%5B');
  Assert.DoesNotContain(Url, '[', 'eckige Klammern kodiert');
  Assert.AreEqual('', TAtlasJenkinsProvider.TestReportApiUrl(Job, 0));
end;

procedure TAtlasJenkinsProviderTests.ParsesLastCompletedBuildFromFixture;
var
  Build: TAtlasCiBuild;
begin
  Assert.IsTrue(TAtlasJenkinsProvider.ParseBuild(Fixture('last-completed-build.json'), Build));
  Assert.AreEqual(482, Build.Number);
  Assert.IsTrue(Build.Outcome = TAtlasCiOutcome.Unstable);
  Assert.AreEqual(Int64(61234), Build.DurationMs);
  // 1792138800500 ms = 2026-10-16 08:20:00,5 UTC
  Assert.IsTrue(Abs(Build.StartedUtc - (EncodeDate(2026, 10, 16) + EncodeTime(8, 20, 0, 500))) < 1 / 86400000 * 2);
  Assert.IsFalse(Build.TestsKnown, 'Tests erst aus dem Testbericht');
end;

procedure TAtlasJenkinsProviderTests.ParsesTestReportFromFixture;
var
  Build: TAtlasCiBuild;
begin
  Build := TAtlasCiBuild.Empty;
  Build.Number := 482;
  Assert.IsTrue(TAtlasJenkinsProvider.ParseTestReport(Fixture('test-report.json'), Build));
  Assert.IsTrue(Build.TestsKnown);
  Assert.AreEqual(410, Build.Passed);
  Assert.AreEqual(2, Build.Failed);
  Assert.AreEqual(3, Build.Skipped);
  Assert.AreEqual(2, Integer(Length(Build.Failures)), 'FAILED und REGRESSION, nicht FIXED');
  Assert.AreEqual('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', Build.Failures[0].Test);
  Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0', Build.Failures[0].Message, 'nur die erste Zeile');
  Assert.AreEqual('Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', Build.Failures[1].Test);
  Assert.AreEqual(482, Build.Number, 'Build bleibt');
end;

procedure TAtlasJenkinsProviderTests.ParsesChildReportsFromFixture;
var
  Build: TAtlasCiBuild;
begin
  Build := TAtlasCiBuild.Empty;
  Assert.IsTrue(TAtlasJenkinsProvider.ParseTestReport(Fixture('test-report-child.json'), Build));
  Assert.AreEqual(42, Build.Passed, 'Teilberichte zusammengezählt');
  Assert.AreEqual(1, Build.Failed);
  Assert.AreEqual(1, Build.Skipped);
  Assert.AreEqual(1, Integer(Length(Build.Failures)));
  Assert.AreEqual('Win32.Atlas.Tests.TRechnerTests.Summe', Build.Failures[0].Test);
end;

procedure TAtlasJenkinsProviderTests.RejectsInvalidAnswers;
var
  Build: TAtlasCiBuild;
  Text: string;
  Index: Integer;
begin
  Assert.IsFalse(TAtlasJenkinsProvider.ParseBuild('<html>Login</html>', Build));
  Assert.IsFalse(TAtlasJenkinsProvider.ParseBuild('{"result": "SUCCESS"}', Build), 'ohne Nummer');
  Assert.IsFalse(TAtlasJenkinsProvider.ParseBuild('{"number": 0}', Build));
  Assert.IsTrue(TAtlasJenkinsProvider.ParseBuild('{"number": 5, "result": null}', Build), 'läuft noch');
  Assert.IsTrue(Build.Outcome = TAtlasCiOutcome.Unknown);
  Build := TAtlasCiBuild.Empty;
  Assert.IsFalse(TAtlasJenkinsProvider.ParseTestReport('[]', Build));
  Assert.IsFalse(Build.TestsKnown);
  // Mehr Fehlschläge als MaxFailures: gezählt alle, gespeichert höchstens MaxFailures; lange Meldung gekürzt.
  Text := '{"failCount": 70, "suites": [{"cases": [';
  for Index := 1 to 70 do
  begin
    if Index > 1 then
      Text := Text + ',';
    Text := Text + '{"className": "U.T", "name": "M' + IntToStr(Index) + '", "status": "FAILED", ' +
      '"errorDetails": "' + StringOfChar('x', 400) + '"}';
  end;
  Text := Text + ']}]}';
  Assert.IsTrue(TAtlasJenkinsProvider.ParseTestReport(Text, Build));
  Assert.AreEqual(70, Build.Failed);
  Assert.AreEqual(TAtlasCiBuild.MaxFailures, Integer(Length(Build.Failures)));
  Assert.AreEqual(TAtlasJenkinsProvider.MaxMessage, Integer(Length(Build.Failures[0].Message)));
end;

procedure TAtlasJenkinsProviderTests.ErrorOfStatus;
begin
  Assert.IsTrue(TAtlasJenkinsProvider.ErrorOfStatus(401) = TAtlasCiFetchError.Unauthorized);
  Assert.IsTrue(TAtlasJenkinsProvider.ErrorOfStatus(403) = TAtlasCiFetchError.Unauthorized);
  Assert.IsTrue(TAtlasJenkinsProvider.ErrorOfStatus(404) = TAtlasCiFetchError.NotFound);
  Assert.IsTrue(TAtlasJenkinsProvider.ErrorOfStatus(500) = TAtlasCiFetchError.Server);
  Assert.IsTrue(TAtlasJenkinsProvider.ErrorOfStatus(302) = TAtlasCiFetchError.Server);
end;

procedure TAtlasJenkinsProviderTests.FetchReadsBuildAndReport;
var
  Transport: TFakeTransport;
  Keep: IAtlasCiTransport;
  Provider: IAtlasCiProvider;
  Build: TAtlasCiBuild;
  Error: TAtlasCiFetchError;
begin
  Transport := TFakeTransport.Create;
  Keep := Transport;
  Transport.Answer('https://ci.firma.de/job/team/job/kasse/lastCompletedBuild/', 200,
    Fixture('last-completed-build.json'));
  Transport.Answer('https://ci.firma.de/job/team/job/kasse/482/testReport/', 200, Fixture('test-report.json'));
  Provider := TAtlasJenkinsProvider.Create;
  Assert.AreEqual('jenkins', Provider.Name);
  Assert.IsTrue(Provider.Fetch(Job, Keep, 5000, Build, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.None);
  Assert.AreEqual(482, Build.Number);
  Assert.IsTrue(Build.TestsKnown);
  Assert.AreEqual(2, Build.Failed);
  Assert.AreEqual(2, Integer(Length(Transport.Calls)));
  Assert.IsTrue(Transport.Timeouts[0] <= 5000);
  Assert.IsTrue(Transport.Timeouts[1] <= 5000, 'eine Zeitgrenze für beide Aufrufe');
end;

procedure TAtlasJenkinsProviderTests.FetchWithoutReportKeepsBuild;
var
  Transport: TFakeTransport;
  Keep: IAtlasCiTransport;
  Provider: IAtlasCiProvider;
  Build: TAtlasCiBuild;
  Error: TAtlasCiFetchError;
begin
  Transport := TFakeTransport.Create;
  Keep := Transport;
  Transport.Answer('https://ci.firma.de/job/team/job/kasse/lastCompletedBuild/', 200,
    '{"number": 12, "result": "FAILURE"}');
  Provider := TAtlasJenkinsProvider.Create;
  Assert.IsTrue(Provider.Fetch(Job, Keep, 5000, Build, Error), 'Testbericht fehlt (404)');
  Assert.IsTrue(Error = TAtlasCiFetchError.None);
  Assert.AreEqual(12, Build.Number);
  Assert.IsTrue(Build.Outcome = TAtlasCiOutcome.Failure);
  Assert.IsFalse(Build.TestsKnown);
end;

procedure TAtlasJenkinsProviderTests.FetchReportsNetworkAndAuthErrors;
var
  Transport: TFakeTransport;
  Keep: IAtlasCiTransport;
  Provider: IAtlasCiProvider;
  Build: TAtlasCiBuild;
  Error: TAtlasCiFetchError;
begin
  Provider := TAtlasJenkinsProvider.Create;
  Transport := TFakeTransport.Create;
  Keep := Transport;
  Transport.FailWith(TAtlasCiFetchError.Timeout);
  Assert.IsFalse(Provider.Fetch(Job, Keep, 5000, Build, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Timeout);
  Assert.AreEqual(0, Build.Number);
  Assert.AreEqual(1, Integer(Length(Transport.Calls)), 'nach dem Zeitlimit kein zweiter Aufruf');

  Transport := TFakeTransport.Create;
  Keep := Transport;
  Transport.Answer('https://ci.firma.de/', 401, '');
  Assert.IsFalse(Provider.Fetch(Job, Keep, 5000, Build, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Unauthorized);

  Transport := TFakeTransport.Create;
  Keep := Transport;
  Transport.Answer('https://ci.firma.de/', 200, '<html>Anmeldung</html>');
  Assert.IsFalse(Provider.Fetch(Job, Keep, 5000, Build, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.Invalid);
end;

procedure TAtlasJenkinsProviderTests.FetchWithoutConfigurationDoesNotCallTransport;
var
  Transport: TFakeTransport;
  Keep: IAtlasCiTransport;
  Provider: IAtlasCiProvider;
  Build: TAtlasCiBuild;
  Error: TAtlasCiFetchError;
begin
  Transport := TFakeTransport.Create;
  Keep := Transport;
  Provider := TAtlasJenkinsProvider.Create;
  Assert.IsFalse(Provider.Fetch(TAtlasCiJob.Create('jenkins', '', 'kasse', False, ''), Keep, 5000, Build, Error));
  Assert.IsTrue(Error = TAtlasCiFetchError.NotConfigured);
  Assert.AreEqual(0, Integer(Length(Transport.Calls)));
end;

procedure TAtlasJenkinsProviderTests.BuildPage;
var
  Provider: IAtlasCiProvider;
begin
  Provider := TAtlasJenkinsProvider.Create;
  Assert.AreEqual('https://ci.firma.de/job/team/job/kasse/482/', Provider.BuildPage(Job, 482));
  Assert.AreEqual('', Provider.BuildPage(Job, 0));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCiJobTests);
  TDUnitX.RegisterTestFixture(TAtlasCiAddressesTests);
  TDUnitX.RegisterTestFixture(TAtlasJenkinsProviderTests);

end.
