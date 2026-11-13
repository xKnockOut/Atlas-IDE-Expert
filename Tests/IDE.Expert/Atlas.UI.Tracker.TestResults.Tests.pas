unit Atlas.UI.Tracker.TestResults.Tests;

// Bereich „Testergebnisse“ der Willkommensseite (#763, Mockup #ws11): Texte
// der Zeilen (Marke, lokaler Lauf, Zeile des Build-Servers mit „Stand vom …“,
// „lokal grün, Server rot“), der Fehlschläge und der Knöpfe; Klicks wählen
// Zeile und Fehlschlag, Knöpfe und Doppelklick erreichen die Quelle über die
// Nachrichtenschleife; „Im Browser“ nur mit Build-Server, Kontextmenü mit
// „Zugang zum Build-Server hinterlegen …“ nur mit Schalter CiLogin.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tracker')]
  TAtlasTrackerTestResultsViewTests = class
  public
    /// <summary>Erste Benutzung ungemessen vorwegnehmen.</summary>
    [SetupFixture]
    procedure WarmUpFirstUse;
    [Test]
    procedure TextsFollowMockup;
    [Test]
    procedure ServerTextsAndMismatch;
    [Test]
    procedure EnglishTexts;
    [Test]
    procedure ClicksReachSource;
    [Test]
    procedure BrowseOnlyWithServer;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.DateUtils,
  Vcl.Forms,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tracker.TestResults,
  Atlas.UI.Strings,
  Atlas.UI.Tracker.TestResults;

const
  cTestProject = 'C:\Projekte\Atlas\Atlas.Tests.dproj';

type
  /// <summary>Quelle des Bereichs für die Tests; merkt sich die Aufrufe.</summary>
  TFakeTestResults = class(TInterfacedObject, IAtlasTestResultsSource)
  public
    FView: TAtlasTestResultsView;
    Calls: TArray<string>;
    Login: Boolean;
    function View: TAtlasTestResultsView;
    procedure Select(const AProject: string);
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    procedure Browse(const ARow: TAtlasTestRow);
    procedure QueryNow(const ARow: TAtlasTestRow);
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    function CanEnterCredentials: Boolean;
    procedure Shown;
  end;

function NowUtc0: TDateTime;
begin
  Result := EncodeDate(2026, 10, 16) + EncodeTime(19, 41, 0, 0);
end;

function Failure(const ATest, AMessage, AFile: string; ALine: Integer): TAtlasProjectTestFailure;
begin
  Result.Test := ATest;
  Result.Message := AMessage;
  Result.FileName := AFile;
  Result.Line := ALine;
end;

/// <summary>412 bestanden, 3 übersprungen, 2 fehlgeschlagen (Beispiel aus dem Issue).</summary>
function LocalRun: TAtlasProjectTests;
begin
  Result := TAtlasProjectTests.Empty;
  Result.Known := True;
  Result.At := NowUtc0;
  Result.Project := cTestProject;
  Result.Passed := 412;
  Result.Failed := 2;
  Result.Skipped := 3;
  Result.DurationMs := 18400;
  Result.Failures := [
    Failure('Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations', 'Erwartet 3 Deklarationen, gefunden 0',
      'C:\Projekte\Atlas\Atlas.Core.Index.Tests.pas', 214),
    Failure('Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', 'Zugriffsverletzung',
      'C:\Projekte\Atlas\Atlas.Core.Hover.Tests.pas', 88)];
end;

function GreenRun: TAtlasProjectTests;
begin
  Result := TAtlasProjectTests.Empty;
  Result.Known := True;
  Result.Project := 'C:\Projekte\Kasse\Kasse.Tests.dproj';
  Result.Passed := 57;
  Result.DurationMs := 2100;
end;

function Job: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('jenkins', 'https://ci.firma.de', 'atlas', True, 'main');
end;

function Build(ANumber: Integer; AOutcome: TAtlasCiOutcome; AFailed: Integer): TAtlasCiBuild;
var
  mIndex: Integer;
  mItem: TAtlasCiFailure;
begin
  Result := TAtlasCiBuild.Empty;
  Result.Number := ANumber;
  Result.Outcome := AOutcome;
  Result.TestsKnown := True;
  Result.Passed := 400;
  Result.Failed := AFailed;
  for mIndex := 1 to AFailed do
  begin
    mItem.Test := 'Atlas.Server.Tests.TServerTests.Case' + IntToStr(mIndex);
    mItem.Message := 'Server ' + IntToStr(mIndex);
    Result.Failures := Result.Failures + [mItem];
  end;
end;

function Project(const AFile: string; const ATests: TAtlasProjectTests; const AJob: TAtlasCiJob;
  const ABuild: TAtlasCiBuild): TAtlasTestProject;
begin
  Result.Project := AFile;
  Result.Summary := TAtlasProjectSummary.Create(AFile);
  Result.Summary.Tests := ATests;
  Result.Summary.Ci := TAtlasProjectCi.Empty;
  if ABuild.Number > 0 then
  begin
    // Abgerufen vor 40 Minuten.
    Result.Summary.Ci := TAtlasTestResults.Recorded(TAtlasProjectCi.Empty, AJob, True, ABuild,
      TAtlasCiFetchError.None, IncMinute(NowUtc0, -40));
  end;
  Result.Job := AJob;
  Result.Querying := False;
end;

function NoJob: TAtlasCiJob;
begin
  Result := TAtlasCiJob.Create('', '', '', False, '');
end;

/// <summary>Atlas.Tests (lokal rot, Server rot) und Kasse.Tests (alle ok, ohne Build-Server).</summary>
function SampleView(ACi: Boolean): TAtlasTestResultsView;
begin
  Result := TAtlasTestResults.View([
    Project(cTestProject, LocalRun, Job, Build(482, TAtlasCiOutcome.Unstable, 1)),
    Project('C:\Projekte\Kasse\Kasse.dproj', GreenRun, NoJob, TAtlasCiBuild.Empty)], '', 5, ACi);
end;

{ TFakeTestResults }

function TFakeTestResults.View: TAtlasTestResultsView;
begin
  Result := FView;
end;

procedure TFakeTestResults.Select(const AProject: string);
begin
  Calls := Calls + ['select ' + ExtractFileName(AProject)];
end;

procedure TFakeTestResults.OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
begin
  Calls := Calls + ['open ' + ARow.Name + ' ' + AFailure.Test];
end;

procedure TFakeTestResults.RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
begin
  Calls := Calls + ['rerun ' + ARow.Name + ' ' + string.Join(',', ATests)];
end;

procedure TFakeTestResults.Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
begin
  Calls := Calls + ['debug ' + ARow.Name + ' ' + AFailure.Test];
end;

procedure TFakeTestResults.Browse(const ARow: TAtlasTestRow);
begin
  Calls := Calls + ['browse ' + ARow.Name + ' ' + IntToStr(ARow.Ci.Build.Number)];
end;

procedure TFakeTestResults.QueryNow(const ARow: TAtlasTestRow);
begin
  Calls := Calls + ['query ' + ARow.Name];
end;

procedure TFakeTestResults.Credentials(const ARow: TAtlasTestRow);
begin
  Calls := Calls + ['login ' + ARow.Job.Server];
end;

procedure TFakeTestResults.OpenProject(const ARow: TAtlasTestRow);
begin
  Calls := Calls + ['project ' + ARow.Name];
end;

function TFakeTestResults.CanEnterCredentials: Boolean;
begin
  Result := Login;
end;

procedure TFakeTestResults.Shown;
begin
  Calls := Calls + ['shown'];
end;

{ TAtlasTrackerTestResultsViewTests }

procedure TAtlasTrackerTestResultsViewTests.WarmUpFirstUse;
begin
  ClicksReachSource;
end;

procedure TAtlasTrackerTestResultsViewTests.TextsFollowMockup;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasTestResultsView;
  mRow: TAtlasTestRow;
  mItem: TAtlasTestFailureItem;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := SampleView(False);
    mRow := mView.Rows[0];
    Assert.AreEqual('Atlas.Tests', mRow.Name);
    // Mockup: Marke „2 fehlgeschlagen“, daneben „412 ok · 3 übersprungen · 18,4 s · 19:41“.
    Assert.AreEqual('2 fehlgeschlagen', TAtlasTrackerTestResultsText.PillText(mRow));
    Assert.AreEqual('412 ok · 3 übersprungen · ' + FormatFloat('0.0', 18.4, FormatSettings) + ' s · ' +
      FormatDateTime('t', TTimeZone.Local.ToLocalTime(NowUtc0), FormatSettings),
      TAtlasTrackerTestResultsText.LocalText(mRow, NowUtc0));
    // „alle 57 ok“ nennt die Zahl schon in der Marke.
    mRow := mView.Rows[1];
    Assert.AreEqual('alle 57 ok', TAtlasTrackerTestResultsText.PillText(mRow));
    Assert.AreEqual(FormatFloat('0.0', 2.1, FormatSettings) + ' s',
      TAtlasTrackerTestResultsText.LocalText(mRow, NowUtc0));
    mRow.Local := TAtlasProjectTests.Empty;
    mRow.LocalLevel := TAtlasTestResults.LocalLevel(mRow.Local);
    Assert.AreEqual('noch kein Lauf', TAtlasTrackerTestResultsText.PillText(mRow));
    Assert.AreEqual('', TAtlasTrackerTestResultsText.LocalText(mRow, NowUtc0));
    Assert.AreEqual('2:05 min', TAtlasTrackerTestResultsText.DurationText(125000));
    // Fehlschläge: Meldung und Datei:Zeile.
    Assert.AreEqual(2, Integer(Length(mView.Failures)));
    mItem := mView.Failures[0];
    Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0 · Atlas.Core.Index.Tests.pas:214',
      TAtlasTrackerTestResultsText.FailureDetail(mItem));
    mItem.Message := '';
    Assert.AreEqual('Atlas.Core.Index.Tests.pas:214', TAtlasTrackerTestResultsText.FailureDetail(mItem));
    mItem.FileName := '';
    mItem.Message := 'Nur Meldung';
    Assert.AreEqual('Nur Meldung', TAtlasTrackerTestResultsText.FailureDetail(mItem));
    // Zeitangaben.
    Assert.AreEqual('gerade eben', TAtlasTrackerTestResultsText.AgoText(NowUtc0, NowUtc0));
    Assert.AreEqual('vor 40 Min.', TAtlasTrackerTestResultsText.AgoText(IncMinute(NowUtc0, -40), NowUtc0));
    Assert.AreEqual('vor 4 Tagen', TAtlasTrackerTestResultsText.AgoText(IncDay(NowUtc0, -4), NowUtc0));
    Assert.AreEqual('', TAtlasTrackerTestResultsText.AgoText(0, NowUtc0));
    Assert.AreEqual('Fehlgeschlagene erneut ausführen',
      TAtlasTrackerTestResultsText.ButtonText(TAtlasTestResultsButton.Rerun));
    Assert.AreEqual('Im Debugger', TAtlasTrackerTestResultsText.ButtonText(TAtlasTestResultsButton.Debug));
    Assert.AreEqual('Im Browser', TAtlasTrackerTestResultsText.ButtonText(TAtlasTestResultsButton.Browse));
    Assert.IsTrue(TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Passed) <>
      TAtlasTrackerTestResultsText.LevelColor(TAtlasTestLevel.Failed), 'rot ist nicht grün');
    Assert.Contains(TAtlasTrackerTestResultsText.RowHint(mView.Rows[0]), cTestProject);
    Assert.Contains(TAtlasTrackerTestResultsText.EmptyText, 'Tests ausführen');
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerTestResultsViewTests.ServerTextsAndMismatch;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasTestResultsView;
  mRow: TAtlasTestRow;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    mView := SampleView(True);
    mRow := mView.Rows[0];
    Assert.IsTrue(mRow.HasCi);
    // Zweite Zeile wie im Issue: „Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main“.
    Assert.AreEqual('Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main',
      TAtlasTrackerTestResultsText.CiText(mRow, NowUtc0));
    // Server-Fehlschläge stehen in derselben Liste, mit Marke „Server“.
    Assert.AreEqual(3, Integer(Length(mView.Failures)));
    Assert.IsTrue(mView.Failures[2].Server);
    // Nicht erreichbar: letzter Stand mit „Stand vom …“, kein Fehler.
    mRow.CiStale := True;
    Assert.StartsWith('Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main · Stand vom ',
      TAtlasTrackerTestResultsText.CiText(mRow, NowUtc0));
    // Noch nie abgerufen.
    mRow.Ci := TAtlasProjectCi.Empty;
    mRow.CiStale := False;
    mRow.Ci.Error := TAtlasCiFetchError.Network;
    Assert.AreEqual('Jenkins · nicht erreichbar · main', TAtlasTrackerTestResultsText.CiText(mRow, NowUtc0));
    mRow.CiQuerying := True;
    Assert.AreEqual('Jenkins · wird abgefragt … · main', TAtlasTrackerTestResultsText.CiText(mRow, NowUtc0));
    mRow.HasCi := False;
    Assert.AreEqual('', TAtlasTrackerTestResultsText.CiText(mRow, NowUtc0));
    Assert.AreEqual('lokal grün, Server rot',
      TAtlasTrackerTestResultsText.MismatchText(TAtlasTestMismatch.LocalGreenServerRed));
    Assert.AreEqual('lokal rot, Server grün',
      TAtlasTrackerTestResultsText.MismatchText(TAtlasTestMismatch.LocalRedServerGreen));
    Assert.AreEqual('', TAtlasTrackerTestResultsText.MismatchText(TAtlasTestMismatch.None));
    Assert.AreEqual('instabil', TAtlasTrackerTestResultsText.BuildText(Build(7, TAtlasCiOutcome.Unstable, 0)));
    Assert.AreEqual('alle 400 ok', TAtlasTrackerTestResultsText.BuildText(Build(7, TAtlasCiOutcome.Success, 0)));
    Assert.AreEqual('Anmeldung abgelehnt (Zugang hinterlegen)',
      TAtlasTrackerTestResultsText.ErrorText(TAtlasCiFetchError.Unauthorized));
    Assert.AreEqual('keine Antwort in 5 s', TAtlasTrackerTestResultsText.ErrorText(TAtlasCiFetchError.Timeout));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerTestResultsViewTests.EnglishTexts;
var
  mSaved: TAtlasLanguage;
  mView: TAtlasTestResultsView;
begin
  mSaved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    mView := SampleView(True);
    Assert.AreEqual('2 failed', TAtlasTrackerTestResultsText.PillText(mView.Rows[0]));
    Assert.AreEqual('all 57 passed', TAtlasTrackerTestResultsText.PillText(mView.Rows[1]));
    Assert.AreEqual('Jenkins #482 · 1 failed · 40 min ago · main',
      TAtlasTrackerTestResultsText.CiText(mView.Rows[0], NowUtc0));
    Assert.AreEqual('green locally, red on the server',
      TAtlasTrackerTestResultsText.MismatchText(TAtlasTestMismatch.LocalGreenServerRed));
    Assert.AreEqual('Re-run failed', TAtlasTrackerTestResultsText.ButtonText(TAtlasTestResultsButton.Rerun));
  finally
    TAtlasStrings.Language := mSaved;
  end;
end;

procedure TAtlasTrackerTestResultsViewTests.ClicksReachSource;
var
  mHost: TForm;
  mFake: TFakeTestResults;
  mSource: IAtlasTestResultsSource;
  mFrame: TAtlasTrackerTestResultsView;
begin
  mFake := TFakeTestResults.Create;
  mSource := mFake;
  mFake.FView := SampleView(True);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasTrackerTestResultsView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.AreEqual(1, Integer(Length(mFake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', mFake.Calls[0]);
    mFake.Calls := nil;
    Assert.IsTrue(mFrame.ButtonVisible(TAtlasTestResultsButton.Browse), 'mit Build-Server');
    Assert.IsTrue(mFrame.ButtonEnabled(TAtlasTestResultsButton.Rerun));
    Assert.IsTrue(mFrame.ButtonEnabled(TAtlasTestResultsButton.Debug), 'ohne Wahl der erste lokale Fehlschlag');
    // Klick auf den zweiten Fehlschlag wählt ihn (ohne Quelle).
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, 1));
    Assert.AreEqual(1, mFrame.Failure);
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Debug, -1));
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Rerun, -1));
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Browse, -1));
    mFrame.DoubleClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, 2));
    // Gewählte Zeile noch einmal: nichts; andere Zeile: wählen; Doppelklick auf die Zeile öffnet das Projekt.
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 0));
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 1));
    mFrame.DoubleClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 1));
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 9));
    mFrame.Menus.MenuRow := 0;
    mFrame.Menus.QueryItem.Click;
    mFrame.Menus.CredentialsItem.Click;
    mFrame.Menus.OpenItem.Click;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(9, Integer(Length(mFake.Calls)));
    Assert.AreEqual('debug Atlas.Tests Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', mFake.Calls[0]);
    Assert.AreEqual('rerun Atlas.Tests Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations,' +
      'Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation,Atlas.Server.Tests.TServerTests.Case1', mFake.Calls[1],
      'lokal und vom Server, jeder Test einmal');
    Assert.AreEqual('browse Atlas.Tests 482', mFake.Calls[2]);
    Assert.AreEqual('open Atlas.Tests Atlas.Server.Tests.TServerTests.Case1', mFake.Calls[3],
      'Doppelklick auf einen Server-Fehlschlag öffnet den Test lokal');
    Assert.AreEqual('select Kasse.dproj', mFake.Calls[4]);
    Assert.AreEqual('project Kasse.Tests', mFake.Calls[5]);
    Assert.AreEqual('query Atlas.Tests', mFake.Calls[6]);
    Assert.AreEqual('login https://ci.firma.de', mFake.Calls[7]);
    Assert.AreEqual('project Atlas.Tests', mFake.Calls[8]);
    Assert.IsTrue(mFrame.HitTest(20, -5).Kind = TAtlasTestResultsHitKind.None, 'über der ersten Zeile');
    Assert.IsTrue(mFrame.HitTest(20, 10).Kind = TAtlasTestResultsHitKind.Row);
  finally
    mHost.Free;
  end;
end;

procedure TAtlasTrackerTestResultsViewTests.BrowseOnlyWithServer;
var
  mHost: TForm;
  mFake: TFakeTestResults;
  mSource: IAtlasTestResultsSource;
  mFrame: TAtlasTrackerTestResultsView;
begin
  mFake := TFakeTestResults.Create;
  mSource := mFake;
  mFake.FView := SampleView(False);
  mHost := TForm.CreateNew(nil);
  try
    mFrame := TAtlasTrackerTestResultsView.Create(mHost);
    mFrame.Parent := mHost;
    mFrame.Width := 600;
    mFrame.Source := mSource;
    Assert.IsFalse(mFrame.ButtonVisible(TAtlasTestResultsButton.Browse), 'ohne Build-Server kein „Im Browser“');
    Assert.IsTrue(mFrame.ButtonVisible(TAtlasTestResultsButton.Rerun));
    mFake.Calls := nil;
    mFrame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Browse, -1));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(mFake.Calls)));
    // Ohne Fehlschläge: nichts erneut auszuführen.
    mFake.FView := TAtlasTestResults.View([Project('C:\Projekte\Kasse\Kasse.dproj', GreenRun, NoJob,
      TAtlasCiBuild.Empty)], '', 5, False);
    mFrame.UpdateContent;
    Assert.IsFalse(mFrame.ButtonEnabled(TAtlasTestResultsButton.Rerun));
    Assert.IsFalse(mFrame.ButtonEnabled(TAtlasTestResultsButton.Debug));
    mFake.FView := Default(TAtlasTestResultsView);
    mFake.FView.Selected := -1;
    mFrame.UpdateContent;
    Assert.IsTrue(mFrame.HitTest(20, 10).Kind = TAtlasTestResultsHitKind.None, 'leerer Bereich');
  finally
    mHost.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTrackerTestResultsViewTests);

end.
