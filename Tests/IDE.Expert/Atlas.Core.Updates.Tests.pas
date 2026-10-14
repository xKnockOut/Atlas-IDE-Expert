unit Atlas.Core.Updates.Tests;

// Update-Prüfung (#495) ohne Netzwerk: SemVer-Vergleich, Versionsdatei,
// höchstens einmal täglich, nur mit Zustimmung, übertragene Angaben, Zustand;
// dazu die Versionsangaben im Diagnoseexport.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasUpdatesTests = class
  public
    [Test]
    procedure ComparesSemanticVersions;
    [Test]
    procedure ParsesVersionFile;
    [Test]
    procedure DueAtMostOncePerDay;
    [Test]
    procedure RequestCarriesOnlyAtlasAndIdeVersion;
    [Test]
    procedure DisabledOrNotDueMakesNoRequest;
    [Test]
    procedure ReportsNewCurrentAndFailed;
    [Test]
    procedure StateRoundTrip;
    [Test]
    procedure DiagnosticExportCarriesVersions;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  System.Zip,
  Atlas.Core.Updates.Contract,
  Atlas.Core.Updates.Check,
  Atlas.Core.Diagnostics.Export;

type
  TFakeSource = class(TInterfacedObject, IAtlasVersionSource)
  public
    Calls: Integer;
    LastUrl: string;
    Answer: string;
    Fails: Boolean;
    function Fetch(const AUrl: string; ATimeoutMs: Integer; out AText, AError: string): Boolean;
  end;

function TFakeSource.Fetch(const AUrl: string; ATimeoutMs: Integer; out AText, AError: string): Boolean;
begin
  Inc(Calls);
  LastUrl := AUrl;
  AText := Answer;
  AError := '';
  Result := not Fails;
  if Fails then
    AError := 'HTTP 404';
end;

procedure TAtlasUpdatesTests.ComparesSemanticVersions;
begin
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0', '0.9.9') > 0);
  Assert.IsTrue(TAtlasUpdates.Compare('0.10.0', '0.9.0') > 0, 'numerisch, nicht als Text');
  Assert.AreEqual(0, TAtlasUpdates.Compare('1.2.3', '1.2.3'));
  Assert.AreEqual(0, TAtlasUpdates.Compare('1.2.3+build.5', '1.2.3'), 'Build-Angabe zählt nicht');
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-beta.1', '1.0.0') < 0, 'Vorabversion vor der Version');
  // Reihenfolge aus SemVer 2.0, Abschnitt 11.
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-alpha', '1.0.0-alpha.1') < 0);
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-alpha.1', '1.0.0-alpha.beta') < 0);
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-alpha.beta', '1.0.0-beta') < 0);
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-beta.2', '1.0.0-beta.11') < 0);
  Assert.IsTrue(TAtlasUpdates.Compare('1.0.0-beta.11', '1.0.0-rc.1') < 0);
  Assert.IsTrue(TAtlasUpdates.Compare('unsinn', '0.0.1') < 0, 'ungültig ist kleiner');
  Assert.IsFalse(TAtlasUpdates.IsValidVersion('1.0'));
  Assert.IsFalse(TAtlasUpdates.IsValidVersion('01.0.0'));
  Assert.IsTrue(TAtlasUpdates.IsValidVersion('2.10.3-rc.1+abc'));
end;

procedure TAtlasUpdatesTests.ParsesVersionFile;
var
  Release: TAtlasRelease;
begin
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0","changes":"https://example.org/v1.2.0"}', Release));
  Assert.AreEqual('1.2.0', Release.Version);
  Assert.AreEqual('https://example.org/v1.2.0', Release.ChangesUrl);
  // Ohne oder mit unsicherer Adresse: die Release-Seite.
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0","changes":"http://example.org"}', Release));
  Assert.AreEqual(TAtlasUpdates.ReleasesUrl + '/tag/v1.2.0', Release.ChangesUrl);
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0"}', Release));
  Assert.AreEqual(TAtlasUpdates.ReleasesUrl + '/tag/v1.2.0', Release.ChangesUrl);
  Assert.IsFalse(TAtlasUpdates.TryParse('{"version":"neu"}', Release));
  Assert.IsFalse(TAtlasUpdates.TryParse('<html>', Release));
  Assert.IsFalse(TAtlasUpdates.TryParse('', Release));
  Assert.AreEqual('', Release.Version);
end;

procedure TAtlasUpdatesTests.DueAtMostOncePerDay;
var
  Last: TDateTime;
begin
  Last := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  Assert.IsTrue(TAtlasUpdates.IsDue(0, Last), 'noch nie');
  Assert.IsFalse(TAtlasUpdates.IsDue(Last, IncHour(Last, 23)));
  Assert.IsTrue(TAtlasUpdates.IsDue(Last, IncHour(Last, 24)));
  Assert.IsTrue(TAtlasUpdates.IsDue(Last, IncHour(Last, -2)), 'Uhr zurückgestellt');
end;

procedure TAtlasUpdatesTests.RequestCarriesOnlyAtlasAndIdeVersion;
var
  Url, Query: string;
begin
  Url := TAtlasUpdates.RequestUrl(TAtlasUpdates.VersionUrl, '1.0.0-beta.1', '37.0');
  Assert.IsTrue(Url.StartsWith(TAtlasUpdates.VersionUrl + '?'));
  Query := Copy(Url, Length(TAtlasUpdates.VersionUrl) + 2, MaxInt);
  Assert.AreEqual('atlas=1.0.0-beta.1&ide=37.0', Query);
  Assert.IsTrue(TAtlasUpdates.VersionUrl.StartsWith('https://'));
  Assert.AreEqual(FormatFloat('0.0', CompilerVersion, TFormatSettings.Invariant), TAtlasUpdates.IdeVersion);
end;

procedure TAtlasUpdatesTests.DisabledOrNotDueMakesNoRequest;
var
  Source: TFakeSource;
  Keep: IAtlasVersionSource;
  State: TAtlasUpdateState;
  Outcome: TAtlasUpdateResult;
  Today: TDateTime;
begin
  Source := TFakeSource.Create;
  Keep := Source;
  Source.Answer := '{"version":"9.0.0"}';
  Today := EncodeDateTime(2026, 10, 14, 12, 0, 0, 0);
  State := Default(TAtlasUpdateState);
  // Ohne Zustimmung keine Netzwerkabfrage.
  Outcome := TAtlasUpdates.Run(Keep, State, False, '1.0.0', '37.0', Today);
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.Disabled);
  Assert.AreEqual(0, Source.Calls);
  Assert.AreEqual(Double(0), Double(State.LastCheck), 1 / SecsPerDay);
  State.LastCheck := IncHour(Today, -3);
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.0.0', '37.0', Today);
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.NotDue);
  Assert.AreEqual(0, Source.Calls);
end;

procedure TAtlasUpdatesTests.ReportsNewCurrentAndFailed;
var
  Source: TFakeSource;
  Keep: IAtlasVersionSource;
  State: TAtlasUpdateState;
  Outcome: TAtlasUpdateResult;
  Today: TDateTime;
begin
  Source := TFakeSource.Create;
  Keep := Source;
  Today := EncodeDateTime(2026, 10, 14, 12, 0, 0, 0);
  State := Default(TAtlasUpdateState);
  Source.Answer := '{"version":"1.1.0","changes":"https://example.org/1.1.0"}';
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.0.0', '37.0', Today);
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.NewVersion);
  Assert.AreEqual('1.1.0', Outcome.Release.Version);
  Assert.AreEqual('https://example.org/1.1.0', Outcome.Release.ChangesUrl);
  Assert.AreEqual(1, Source.Calls);
  Assert.AreEqual(TAtlasUpdates.RequestUrl(TAtlasUpdates.VersionUrl, '1.0.0', '37.0'), Source.LastUrl);
  Assert.AreEqual(Double(Today), Double(State.LastCheck), 1 / SecsPerDay);
  // Am selben Tag nicht noch einmal.
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.0.0', '37.0', IncHour(Today, 5));
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.NotDue);
  Assert.AreEqual(1, Source.Calls);
  // Gleich oder älter: aktuell.
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.1.0', '37.0', IncDay(Today, 1));
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.Current);
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.2.0-beta.1', '37.0', IncDay(Today, 2));
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.Current);
  // Fehler zählen als Prüfung: höchstens einmal am Tag.
  Source.Fails := True;
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.0.0', '37.0', IncDay(Today, 3));
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.Failed);
  Assert.AreEqual('HTTP 404', Outcome.Error);
  Assert.AreEqual(Double(IncDay(Today, 3)), Double(State.LastCheck), 1 / SecsPerDay);
  Source.Fails := False;
  Source.Answer := 'kaputt';
  Outcome := TAtlasUpdates.Run(Keep, State, True, '1.0.0', '37.0', IncDay(Today, 4));
  Assert.IsTrue(Outcome.Outcome = TAtlasUpdateOutcome.Failed);
end;

procedure TAtlasUpdatesTests.StateRoundTrip;
var
  State, Loaded: TAtlasUpdateState;
begin
  State.Asked := True;
  State.LastCheck := EncodeDateTime(2026, 10, 14, 9, 30, 15, 0);
  Loaded := TAtlasUpdateState.FromJson(State.ToJson);
  Assert.IsTrue(Loaded.Asked);
  Assert.AreEqual(Double(State.LastCheck), Double(Loaded.LastCheck), 1 / SecsPerDay);
  Loaded := TAtlasUpdateState.FromJson('kein json');
  Assert.IsFalse(Loaded.Asked);
  Assert.AreEqual(Double(0), Double(Loaded.LastCheck), 1 / SecsPerDay);
  Loaded := TAtlasUpdateState.FromJson('{"asked":true,"lastCheck":"gestern"}');
  Assert.IsTrue(Loaded.Asked);
  Assert.AreEqual(Double(0), Double(Loaded.LastCheck), 1 / SecsPerDay);
  Assert.IsTrue(TAtlasUpdates.StateFile.EndsWith(TPath.Combine('Atlas', 'updates.json')));
end;

procedure TAtlasUpdatesTests.DiagnosticExportCarriesVersions;
var
  Folder, LogFile, Target, Info, Preview: string;
  Zip: TZipFile;
  Bytes: TBytes;
begin
  Folder := TPath.Combine(TPath.GetTempPath, 'atlas-export-' + IntToStr(Random(1000000)));
  ForceDirectories(Folder);
  try
    LogFile := TPath.Combine(Folder, 'diag-1.log');
    TFile.WriteAllText(LogFile, 'hover ok'#10, TEncoding.UTF8);
    Info := TAtlasDiagnosticExport.Info('1.0.0', '37.0', 'Win32');
    Assert.AreEqual('Atlas 1.0.0' + sLineBreak + 'IDE 37.0' + sLineBreak + 'Plattform Win32' + sLineBreak, Info);
    Preview := TAtlasDiagnosticExport.Preview([LogFile], Info);
    Assert.IsTrue(Preview.StartsWith('== atlas-info.txt ==' + sLineBreak + 'Atlas 1.0.0'));
    Assert.Contains(Preview, 'hover ok');
    Target := TPath.Combine(Folder, 'export.zip');
    TAtlasDiagnosticExport.WriteZip([LogFile], Target, Info);
    Zip := TZipFile.Create;
    try
      Zip.Open(Target, TZipMode.zmRead);
      Assert.AreEqual(2, Zip.FileCount);
      Assert.AreEqual('atlas-info.txt', Zip.FileNames[0]);
      Zip.Read(0, Bytes);
      Assert.AreEqual(Info, TEncoding.UTF8.GetString(Bytes));
    finally
      Zip.Free;
    end;
  finally
    TDirectory.Delete(Folder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUpdatesTests);

end.
