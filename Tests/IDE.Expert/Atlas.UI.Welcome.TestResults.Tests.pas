unit Atlas.UI.Welcome.TestResults.Tests;

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
  TAtlasWelcomeTestResultsFrameTests = class
  public
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
  Atlas.Core.Ci.Contract,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Welcome.TestResults,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.TestResults;

const
  TestProject = 'C:\Projekte\Atlas\Atlas.Tests.dproj';

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
  Result.Project := TestProject;
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
  Index: Integer;
  Item: TAtlasCiFailure;
begin
  Result := TAtlasCiBuild.Empty;
  Result.Number := ANumber;
  Result.Outcome := AOutcome;
  Result.TestsKnown := True;
  Result.Passed := 400;
  Result.Failed := AFailed;
  for Index := 1 to AFailed do
  begin
    Item.Test := 'Atlas.Server.Tests.TServerTests.Case' + IntToStr(Index);
    Item.Message := 'Server ' + IntToStr(Index);
    Result.Failures := Result.Failures + [Item];
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
    // Abgerufen vor 40 Minuten.
    Result.Summary.Ci := TAtlasWelcomeTestResults.Recorded(TAtlasProjectCi.Empty, AJob, True, ABuild,
      TAtlasCiFetchError.None, IncMinute(NowUtc0, -40));
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
  Result := TAtlasWelcomeTestResults.View([
    Project(TestProject, LocalRun, Job, Build(482, TAtlasCiOutcome.Unstable, 1)),
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

{ TAtlasWelcomeTestResultsFrameTests }

procedure TAtlasWelcomeTestResultsFrameTests.TextsFollowMockup;
var
  Saved: TAtlasLanguage;
  View: TAtlasTestResultsView;
  Row: TAtlasTestRow;
  Item: TAtlasTestFailureItem;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView(False);
    Row := View.Rows[0];
    Assert.AreEqual('Atlas.Tests', Row.Name);
    // Mockup: Marke „2 fehlgeschlagen“, daneben „412 ok · 3 übersprungen · 18,4 s · 19:41“.
    Assert.AreEqual('2 fehlgeschlagen', TAtlasWelcomeTestResultsFrame.PillText(Row));
    Assert.AreEqual('412 ok · 3 übersprungen · ' + FormatFloat('0.0', 18.4) + ' s · ' +
      FormatDateTime('t', TTimeZone.Local.ToLocalTime(NowUtc0)),
      TAtlasWelcomeTestResultsFrame.LocalText(Row, NowUtc0));
    // „alle 57 ok“ nennt die Zahl schon in der Marke.
    Row := View.Rows[1];
    Assert.AreEqual('alle 57 ok', TAtlasWelcomeTestResultsFrame.PillText(Row));
    Assert.AreEqual(FormatFloat('0.0', 2.1) + ' s', TAtlasWelcomeTestResultsFrame.LocalText(Row, NowUtc0));
    Row.Local := TAtlasProjectTests.Empty;
    Row.LocalLevel := TAtlasWelcomeTestResults.LocalLevel(Row.Local);
    Assert.AreEqual('noch kein Lauf', TAtlasWelcomeTestResultsFrame.PillText(Row));
    Assert.AreEqual('', TAtlasWelcomeTestResultsFrame.LocalText(Row, NowUtc0));
    Assert.AreEqual('2:05 min', TAtlasWelcomeTestResultsFrame.DurationText(125000));
    // Fehlschläge: Meldung und Datei:Zeile.
    Assert.AreEqual(2, Integer(Length(View.Failures)));
    Item := View.Failures[0];
    Assert.AreEqual('Erwartet 3 Deklarationen, gefunden 0 · Atlas.Core.Index.Tests.pas:214',
      TAtlasWelcomeTestResultsFrame.FailureDetail(Item));
    Item.Message := '';
    Assert.AreEqual('Atlas.Core.Index.Tests.pas:214', TAtlasWelcomeTestResultsFrame.FailureDetail(Item));
    Item.FileName := '';
    Item.Message := 'Nur Meldung';
    Assert.AreEqual('Nur Meldung', TAtlasWelcomeTestResultsFrame.FailureDetail(Item));
    // Zeitangaben.
    Assert.AreEqual('gerade eben', TAtlasWelcomeTestResultsFrame.AgoText(NowUtc0, NowUtc0));
    Assert.AreEqual('vor 40 Min.', TAtlasWelcomeTestResultsFrame.AgoText(IncMinute(NowUtc0, -40), NowUtc0));
    Assert.AreEqual('vor 4 Tagen', TAtlasWelcomeTestResultsFrame.AgoText(IncDay(NowUtc0, -4), NowUtc0));
    Assert.AreEqual('', TAtlasWelcomeTestResultsFrame.AgoText(0, NowUtc0));
    Assert.AreEqual('Fehlgeschlagene erneut ausführen',
      TAtlasWelcomeTestResultsFrame.ButtonText(TAtlasTestResultsButton.Rerun));
    Assert.AreEqual('Im Debugger', TAtlasWelcomeTestResultsFrame.ButtonText(TAtlasTestResultsButton.Debug));
    Assert.AreEqual('Im Browser', TAtlasWelcomeTestResultsFrame.ButtonText(TAtlasTestResultsButton.Browse));
    Assert.IsTrue(TAtlasWelcomeTestResultsFrame.LevelColor(TAtlasTestLevel.Passed) <>
      TAtlasWelcomeTestResultsFrame.LevelColor(TAtlasTestLevel.Failed), 'rot ist nicht grün');
    Assert.Contains(TAtlasWelcomeTestResultsFrame.RowHint(View.Rows[0]), TestProject);
    Assert.Contains(TAtlasWelcomeTestResultsFrame.EmptyText, 'Tests ausführen');
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTestResultsFrameTests.ServerTextsAndMismatch;
var
  Saved: TAtlasLanguage;
  View: TAtlasTestResultsView;
  Row: TAtlasTestRow;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.German;
    View := SampleView(True);
    Row := View.Rows[0];
    Assert.IsTrue(Row.HasCi);
    // Zweite Zeile wie im Issue: „Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main“.
    Assert.AreEqual('Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main',
      TAtlasWelcomeTestResultsFrame.CiText(Row, NowUtc0));
    // Server-Fehlschläge stehen in derselben Liste, mit Marke „Server“.
    Assert.AreEqual(3, Integer(Length(View.Failures)));
    Assert.IsTrue(View.Failures[2].Server);
    // Nicht erreichbar: letzter Stand mit „Stand vom …“, kein Fehler.
    Row.CiStale := True;
    Assert.StartsWith('Jenkins #482 · 1 fehlgeschlagen · vor 40 Min. · main · Stand vom ',
      TAtlasWelcomeTestResultsFrame.CiText(Row, NowUtc0));
    // Noch nie abgerufen.
    Row.Ci := TAtlasProjectCi.Empty;
    Row.CiStale := False;
    Row.Ci.Error := TAtlasCiFetchError.Network;
    Assert.AreEqual('Jenkins · nicht erreichbar · main', TAtlasWelcomeTestResultsFrame.CiText(Row, NowUtc0));
    Row.CiQuerying := True;
    Assert.AreEqual('Jenkins · wird abgefragt … · main', TAtlasWelcomeTestResultsFrame.CiText(Row, NowUtc0));
    Row.HasCi := False;
    Assert.AreEqual('', TAtlasWelcomeTestResultsFrame.CiText(Row, NowUtc0));
    Assert.AreEqual('lokal grün, Server rot',
      TAtlasWelcomeTestResultsFrame.MismatchText(TAtlasTestMismatch.LocalGreenServerRed));
    Assert.AreEqual('lokal rot, Server grün',
      TAtlasWelcomeTestResultsFrame.MismatchText(TAtlasTestMismatch.LocalRedServerGreen));
    Assert.AreEqual('', TAtlasWelcomeTestResultsFrame.MismatchText(TAtlasTestMismatch.None));
    Assert.AreEqual('instabil', TAtlasWelcomeTestResultsFrame.BuildText(Build(7, TAtlasCiOutcome.Unstable, 0)));
    Assert.AreEqual('alle 400 ok', TAtlasWelcomeTestResultsFrame.BuildText(Build(7, TAtlasCiOutcome.Success, 0)));
    Assert.AreEqual('Anmeldung abgelehnt (Zugang hinterlegen)',
      TAtlasWelcomeTestResultsFrame.ErrorText(TAtlasCiFetchError.Unauthorized));
    Assert.AreEqual('keine Antwort in 5 s', TAtlasWelcomeTestResultsFrame.ErrorText(TAtlasCiFetchError.Timeout));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTestResultsFrameTests.EnglishTexts;
var
  Saved: TAtlasLanguage;
  View: TAtlasTestResultsView;
begin
  Saved := TAtlasStrings.Language;
  try
    TAtlasStrings.Language := TAtlasLanguage.English;
    View := SampleView(True);
    Assert.AreEqual('2 failed', TAtlasWelcomeTestResultsFrame.PillText(View.Rows[0]));
    Assert.AreEqual('all 57 passed', TAtlasWelcomeTestResultsFrame.PillText(View.Rows[1]));
    Assert.AreEqual('Jenkins #482 · 1 failed · 40 min ago · main',
      TAtlasWelcomeTestResultsFrame.CiText(View.Rows[0], NowUtc0));
    Assert.AreEqual('green locally, red on the server',
      TAtlasWelcomeTestResultsFrame.MismatchText(TAtlasTestMismatch.LocalGreenServerRed));
    Assert.AreEqual('Re-run failed', TAtlasWelcomeTestResultsFrame.ButtonText(TAtlasTestResultsButton.Rerun));
  finally
    TAtlasStrings.Language := Saved;
  end;
end;

procedure TAtlasWelcomeTestResultsFrameTests.ClicksReachSource;
var
  Host: TForm;
  Fake: TFakeTestResults;
  Source: IAtlasTestResultsSource;
  Frame: TAtlasWelcomeTestResultsFrame;
begin
  Fake := TFakeTestResults.Create;
  Source := Fake;
  Fake.FView := SampleView(True);
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeTestResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.AreEqual(1, Integer(Length(Fake.Calls)), 'Shown beim Setzen der Quelle');
    Assert.AreEqual('shown', Fake.Calls[0]);
    Fake.Calls := nil;
    Assert.IsTrue(Frame.ButtonVisible(TAtlasTestResultsButton.Browse), 'mit Build-Server');
    Assert.IsTrue(Frame.ButtonEnabled(TAtlasTestResultsButton.Rerun));
    Assert.IsTrue(Frame.ButtonEnabled(TAtlasTestResultsButton.Debug), 'ohne Wahl der erste lokale Fehlschlag');
    // Klick auf den zweiten Fehlschlag wählt ihn (ohne Quelle).
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, 1));
    Assert.AreEqual(1, Frame.Failure);
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Debug, -1));
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Rerun, -1));
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Browse, -1));
    Frame.DoubleClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Failure, 2));
    // Gewählte Zeile noch einmal: nichts; andere Zeile: wählen; Doppelklick auf die Zeile öffnet das Projekt.
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 0));
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 1));
    Frame.DoubleClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 1));
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Row, 9));
    Frame.MenuRow := 0;
    Frame.QueryItem.Click;
    Frame.CredentialsItem.Click;
    Frame.OpenItem.Click;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)), 'alles über die Nachrichtenschleife');
    CheckSynchronize;
    Assert.AreEqual(9, Integer(Length(Fake.Calls)));
    Assert.AreEqual('debug Atlas.Tests Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation', Fake.Calls[0]);
    Assert.AreEqual('rerun Atlas.Tests Atlas.Core.Index.Tests.TIndexTests.FindsDeclarations,' +
      'Atlas.Core.Hover.Tests.THoverTests.ShowsDocumentation,Atlas.Server.Tests.TServerTests.Case1', Fake.Calls[1],
      'lokal und vom Server, jeder Test einmal');
    Assert.AreEqual('browse Atlas.Tests 482', Fake.Calls[2]);
    Assert.AreEqual('open Atlas.Tests Atlas.Server.Tests.TServerTests.Case1', Fake.Calls[3],
      'Doppelklick auf einen Server-Fehlschlag öffnet den Test lokal');
    Assert.AreEqual('select Kasse.dproj', Fake.Calls[4]);
    Assert.AreEqual('project Kasse.Tests', Fake.Calls[5]);
    Assert.AreEqual('query Atlas.Tests', Fake.Calls[6]);
    Assert.AreEqual('login https://ci.firma.de', Fake.Calls[7]);
    Assert.AreEqual('project Atlas.Tests', Fake.Calls[8]);
    Assert.IsTrue(Frame.HitTest(20, -5).Kind = TAtlasTestResultsHitKind.None, 'über der ersten Zeile');
    Assert.IsTrue(Frame.HitTest(20, 10).Kind = TAtlasTestResultsHitKind.Row);
  finally
    Host.Free;
  end;
end;

procedure TAtlasWelcomeTestResultsFrameTests.BrowseOnlyWithServer;
var
  Host: TForm;
  Fake: TFakeTestResults;
  Source: IAtlasTestResultsSource;
  Frame: TAtlasWelcomeTestResultsFrame;
begin
  Fake := TFakeTestResults.Create;
  Source := Fake;
  Fake.FView := SampleView(False);
  Host := TForm.CreateNew(nil);
  try
    Frame := TAtlasWelcomeTestResultsFrame.Create(Host);
    Frame.Parent := Host;
    Frame.Width := 600;
    Frame.Source := Source;
    Assert.IsFalse(Frame.ButtonVisible(TAtlasTestResultsButton.Browse), 'ohne Build-Server kein „Im Browser“');
    Assert.IsTrue(Frame.ButtonVisible(TAtlasTestResultsButton.Rerun));
    Fake.Calls := nil;
    Frame.ClickAt(TAtlasTestResultsHit.Create(TAtlasTestResultsHitKind.Browse, -1));
    CheckSynchronize;
    Assert.AreEqual(0, Integer(Length(Fake.Calls)));
    // Ohne Fehlschläge: nichts erneut auszuführen.
    Fake.FView := TAtlasWelcomeTestResults.View([Project('C:\Projekte\Kasse\Kasse.dproj', GreenRun, NoJob,
      TAtlasCiBuild.Empty)], '', 5, False);
    Frame.UpdateContent;
    Assert.IsFalse(Frame.ButtonEnabled(TAtlasTestResultsButton.Rerun));
    Assert.IsFalse(Frame.ButtonEnabled(TAtlasTestResultsButton.Debug));
    Fake.FView := Default(TAtlasTestResultsView);
    Fake.FView.Selected := -1;
    Frame.UpdateContent;
    Assert.IsTrue(Frame.HitTest(20, 10).Kind = TAtlasTestResultsHitKind.None, 'leerer Bereich');
  finally
    Host.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasWelcomeTestResultsFrameTests);

end.
