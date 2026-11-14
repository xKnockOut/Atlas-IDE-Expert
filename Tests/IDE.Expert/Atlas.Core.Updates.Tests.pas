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
  begin
    AError := 'HTTP 404';
  end;
end;

function Query(const AInstalled: string): TAtlasUpdateQuery;
begin
  Result.Url := TAtlasUpdates.cVersionUrl;
  Result.Installed := AInstalled;
  Result.IdeVersion := '37.0';
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
  mRelease: TAtlasRelease;
begin
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0","changes":"https://example.org/v1.2.0"}', mRelease));
  Assert.AreEqual('1.2.0', mRelease.Version);
  Assert.AreEqual('https://example.org/v1.2.0', mRelease.ChangesUrl);
  // Ohne oder mit unsicherer Adresse: die Release-Seite.
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0","changes":"http://example.org"}', mRelease));
  Assert.AreEqual(TAtlasUpdates.cReleasesUrl + '/tag/v1.2.0', mRelease.ChangesUrl);
  Assert.IsTrue(TAtlasUpdates.TryParse('{"version":"1.2.0"}', mRelease));
  Assert.AreEqual(TAtlasUpdates.cReleasesUrl + '/tag/v1.2.0', mRelease.ChangesUrl);
  Assert.IsFalse(TAtlasUpdates.TryParse('{"version":"neu"}', mRelease));
  Assert.IsFalse(TAtlasUpdates.TryParse('<html>', mRelease));
  Assert.IsFalse(TAtlasUpdates.TryParse('', mRelease));
  Assert.AreEqual('', mRelease.Version);
end;

procedure TAtlasUpdatesTests.DueAtMostOncePerDay;
var
  mLast: TDateTime;
begin
  mLast := EncodeDateTime(2026, 10, 14, 9, 0, 0, 0);
  Assert.IsTrue(TAtlasUpdates.IsDue(0, mLast), 'noch nie');
  Assert.IsFalse(TAtlasUpdates.IsDue(mLast, IncHour(mLast, 23)));
  Assert.IsTrue(TAtlasUpdates.IsDue(mLast, IncHour(mLast, 24)));
  Assert.IsTrue(TAtlasUpdates.IsDue(mLast, IncHour(mLast, -2)), 'Uhr zurückgestellt');
end;

procedure TAtlasUpdatesTests.RequestCarriesOnlyAtlasAndIdeVersion;
var
  mUrl, mQuery: string;
begin
  mUrl := TAtlasUpdates.RequestUrl(TAtlasUpdates.cVersionUrl, '1.0.0-beta.1', '37.0');
  Assert.IsTrue(mUrl.StartsWith(TAtlasUpdates.cVersionUrl + '?'));
  mQuery := Copy(mUrl, Length(TAtlasUpdates.cVersionUrl) + 2, MaxInt);
  Assert.AreEqual('atlas=1.0.0-beta.1&ide=37.0', mQuery);
  Assert.IsTrue(TAtlasUpdates.cVersionUrl.StartsWith('https://'));
  Assert.AreEqual(FormatFloat('0.0', CompilerVersion, TFormatSettings.Invariant), TAtlasUpdates.IdeVersion);
end;

procedure TAtlasUpdatesTests.DisabledOrNotDueMakesNoRequest;
var
  mSource: TFakeSource;
  mKeep: IAtlasVersionSource;
  mState: TAtlasUpdateState;
  mOutcome: TAtlasUpdateResult;
  mToday: TDateTime;
begin
  mSource := TFakeSource.Create;
  mKeep := mSource;
  mSource.Answer := '{"version":"9.0.0"}';
  mToday := EncodeDateTime(2026, 10, 14, 12, 0, 0, 0);
  mState := Default(TAtlasUpdateState);
  // Ohne Zustimmung keine Netzwerkabfrage.
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, False, mToday);
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.Disabled, mOutcome.Outcome);
  Assert.AreEqual(0, mSource.Calls);
  Assert.AreEqual(Double(0), Double(mState.LastCheck), 1 / SecsPerDay);
  mState.LastCheck := IncHour(mToday, -3);
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, True, mToday);
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.NotDue, mOutcome.Outcome);
  Assert.AreEqual(0, mSource.Calls);
end;

procedure TAtlasUpdatesTests.ReportsNewCurrentAndFailed;
var
  mSource: TFakeSource;
  mKeep: IAtlasVersionSource;
  mState: TAtlasUpdateState;
  mOutcome: TAtlasUpdateResult;
  mToday: TDateTime;
begin
  mSource := TFakeSource.Create;
  mKeep := mSource;
  mToday := EncodeDateTime(2026, 10, 14, 12, 0, 0, 0);
  mState := Default(TAtlasUpdateState);
  mSource.Answer := '{"version":"1.1.0","changes":"https://example.org/1.1.0"}';
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, True, mToday);
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.NewVersion, mOutcome.Outcome);
  Assert.AreEqual('1.1.0', mOutcome.Release.Version);
  Assert.AreEqual('https://example.org/1.1.0', mOutcome.Release.ChangesUrl);
  Assert.AreEqual(1, mSource.Calls);
  Assert.AreEqual(TAtlasUpdates.RequestUrl(TAtlasUpdates.cVersionUrl, '1.0.0', '37.0'), mSource.LastUrl);
  Assert.AreEqual(Double(mToday), Double(mState.LastCheck), 1 / SecsPerDay);
  // Am selben Tag nicht noch einmal.
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, True, IncHour(mToday, 5));
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.NotDue, mOutcome.Outcome);
  Assert.AreEqual(1, mSource.Calls);
  // Gleich oder älter: aktuell.
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.1.0'), mState, True, IncDay(mToday, 1));
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.Current, mOutcome.Outcome);
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.2.0-beta.1'), mState, True, IncDay(mToday, 2));
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.Current, mOutcome.Outcome);
  // Fehler zählen als Prüfung: höchstens einmal am Tag.
  mSource.Fails := True;
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, True, IncDay(mToday, 3));
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.Failed, mOutcome.Outcome);
  Assert.AreEqual('HTTP 404', mOutcome.Error);
  Assert.AreEqual(Double(IncDay(mToday, 3)), Double(mState.LastCheck), 1 / SecsPerDay);
  mSource.Fails := False;
  mSource.Answer := 'kaputt';
  mOutcome := TAtlasUpdates.Run(mKeep, Query('1.0.0'), mState, True, IncDay(mToday, 4));
  Assert.AreEqual<TAtlasUpdateOutcome>(TAtlasUpdateOutcome.Failed, mOutcome.Outcome);
end;

procedure TAtlasUpdatesTests.StateRoundTrip;
var
  mState, mLoaded: TAtlasUpdateState;
begin
  mState.Asked := True;
  mState.LastCheck := EncodeDateTime(2026, 10, 14, 9, 30, 15, 0);
  mLoaded := TAtlasUpdateState.FromJson(mState.ToJson);
  Assert.IsTrue(mLoaded.Asked);
  Assert.AreEqual(Double(mState.LastCheck), Double(mLoaded.LastCheck), 1 / SecsPerDay);
  mLoaded := TAtlasUpdateState.FromJson('kein json');
  Assert.IsFalse(mLoaded.Asked);
  Assert.AreEqual(Double(0), Double(mLoaded.LastCheck), 1 / SecsPerDay);
  mLoaded := TAtlasUpdateState.FromJson('{"asked":true,"lastCheck":"gestern"}');
  Assert.IsTrue(mLoaded.Asked);
  Assert.AreEqual(Double(0), Double(mLoaded.LastCheck), 1 / SecsPerDay);
  Assert.IsTrue(TAtlasUpdates.StateFile.EndsWith(TPath.Combine('Atlas', 'updates.json')));
end;

procedure TAtlasUpdatesTests.DiagnosticExportCarriesVersions;
var
  mFolder, mLogFile, mTarget, mInfo, mPreview: string;
  mZip: TZipFile;
  mBytes: TBytes;
begin
  mFolder := TPath.Combine(TPath.GetTempPath, 'atlas-export-' + IntToStr(Random(1000000)));
  ForceDirectories(mFolder);
  try
    mLogFile := TPath.Combine(mFolder, 'diag-1.log');
    TFile.WriteAllText(mLogFile, 'hover ok'#10, TEncoding.UTF8);
    mInfo := TAtlasDiagnosticExport.Info('1.0.0', '37.0', 'Win32');
    Assert.AreEqual('Atlas 1.0.0' + sLineBreak + 'IDE 37.0' + sLineBreak + 'Plattform Win32' + sLineBreak, mInfo);
    mPreview := TAtlasDiagnosticExport.Preview([mLogFile], mInfo);
    Assert.IsTrue(mPreview.StartsWith('== atlas-info.txt ==' + sLineBreak + 'Atlas 1.0.0'));
    Assert.Contains(mPreview, 'hover ok');
    mTarget := TPath.Combine(mFolder, 'export.zip');
    TAtlasDiagnosticExport.WriteZip([mLogFile], mTarget, mInfo);
    mZip := TZipFile.Create;
    try
      mZip.Open(mTarget, TZipMode.zmRead);
      Assert.AreEqual(2, mZip.FileCount);
      Assert.AreEqual('atlas-info.txt', mZip.FileNames[0]);
      mZip.Read(0, mBytes);
      Assert.AreEqual(mInfo, TEncoding.UTF8.GetString(mBytes));
    finally
      mZip.Free;
    end;
  finally
    TDirectory.Delete(mFolder, True);
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasUpdatesTests);

end.
