unit Atlas.Core.Problems.Flow.Tests;

// Tests für den Ablauf der Probleme gegen die Fälschung von Server und IDE:
// wann eine Datei geholt wird (Tipp-Pause, unverändert, Anfrage läuft,
// Code nicht vorn, Bitte des Servers, neue Sitzung, Anforderung), was mit den
// Antworten geschieht (Speicher, Weitertippen, Projektdateien, Fehler der IDE,
// Zähler) und wann alles ruht oder verworfen wird (abgeschaltet, Debugger,
// weggefallene Projekte, gescheiterter Start, Ende der Sitzung).

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Problems.Contract.Sync,
  Atlas.Core.Problems.Flow,
  Atlas.Tests.ProblemsSyncFake;

type
  [TestFixture]
  TAtlasProblemsFlowTests = class
  private
    FFake: TAtlasProblemsServerFake;
    FIde: TAtlasProblemsEditorsFake;
    FServer: IAtlasProblemsServer;
    FEditors: IAtlasProblemsEditors;
    FFlow: TAtlasProblemsFlow;
    FSettings: TAtlasPluginSettings;
    FLogText: string;
    /// <summary>Uhr weiterstellen und einen Takt laufen lassen.</summary>
    procedure TickAfter(AMs: Cardinal);
    /// <summary>Wartende Aufträge holen und mit je einem Problem in Zeile ALine beantworten.</summary>
    procedure Answer(ALine: Integer);
    /// <summary>Dateien der Aufträge mit Compilerersatz als „Datei+“, durch Komma getrennt; leert sie nicht.</summary>
    function PullText(const APulls: TAtlasProblemsPulls): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure TypingPullsAfterQuietDelay;
    [Test]
    procedure AnswerFillsStoreAndFollowsTyping;
    [Test]
    procedure UnchangedTextIsNotPulledAgain;
    [Test]
    procedure BusyServerGetsNoSecondPull;
    [Test]
    procedure DesignerInFrontDoesNotPull;
    [Test]
    procedure RefreshPullsAllSyncedFiles;
    [Test]
    procedure SwitchSendsPreviousText;
    [Test]
    procedure DisabledDropsEverything;
    [Test]
    procedure DebuggerPausesAndResumes;
    [Test]
    procedure RemovedProjectsDropAndRestart;
    [Test]
    procedure NewSessionPullsAgain;
    [Test]
    procedure ClosedFilesAreClosedOnServer;
    [Test]
    procedure RequestedFilesAreSyncedAndPulled;
    [Test]
    procedure RequestedFilesWithoutServerAreDropped;
    [Test]
    procedure WorkspaceReportsSkipSyncedFiles;
    [Test]
    procedure WorkspaceRunRemembersFinish;
    [Test]
    procedure WorkspaceOnlyWhileProblemsShown;
    [Test]
    procedure IdeErrorsFollowEachCheck;
    [Test]
    procedure CountsAreReportedOnChange;
    [Test]
    procedure FailedStartWaitsBeforeRetry;
    [Test]
    procedure StoppedSessionStartsFresh;
    [Test]
    procedure CheckingWhilePullOpen;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Plugin.Lsp.Contract,
  Atlas.Plugin.Problems.Contract,
  Atlas.Plugin.Diagnostics.Deadline,
  Atlas.Core.Problems.Refresh,
  Atlas.Core.Problems.InlineHints;

const
  cFileA = 'C:\p\A.pas';
  cFileB = 'C:\p\B.pas';
  cTextA = 'unit A;'#13#10'interface'#13#10'implementation'#13#10'end.';
  cDelayMs = 400;

var
  // Uhr der Tests (TAtlasTicks.SetClock).
  GNow: UInt64;

function TestClock: UInt64;
begin
  Result := GNow;
end;

function Problem(ALine: Integer; const AMessage: string): TAtlasProblem;
begin
  Result := Default(TAtlasProblem);
  Result.StartLine := ALine;
  Result.EndLine := ALine;
  Result.StartCharacter := 0;
  Result.EndCharacter := 4;
  Result.Severity := TAtlasProblemSeverity.Warning;
  Result.Code := 'rule';
  Result.Source := 'Atlas';
  Result.Message := AMessage;
end;

function Report(const AFileName: string; ALine: Integer; const AResultId: string): TLspDiagnosticReport;
begin
  Result := Default(TLspDiagnosticReport);
  Result.FileName := AFileName;
  Result.ResultId := AResultId;
  Result.Problems := TArray<TAtlasProblem>.Create(Problem(ALine, 'Befund'));
end;

{ TAtlasProblemsFlowTests }

procedure TAtlasProblemsFlowTests.TickAfter(AMs: Cardinal);
begin
  GNow := GNow + AMs;
  FFlow.Tick(FSettings);
end;

procedure TAtlasProblemsFlowTests.Answer(ALine: Integer);
var
  mPull: TAtlasProblemsPull;
begin
  for mPull in FFake.TakePulls do
  begin
    FFlow.Results.Document(FSettings, mPull, Report(mPull.FileName, ALine, 'r1'));
  end;
end;

function TAtlasProblemsFlowTests.PullText(const APulls: TAtlasProblemsPulls): string;
var
  mPull: TAtlasProblemsPull;
begin
  Result := '';
  for mPull in APulls do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + ExtractFileName(mPull.FileName);
    if mPull.ReplaceCompiler then
    begin
      Result := Result + '+';
    end;
  end;
end;

procedure TAtlasProblemsFlowTests.Setup;
begin
  GNow := 100000;
  TAtlasTicks.SetClock(TestClock);
  TAtlasProblemsCheckRequest.Clear;
  TAtlasProblemsCheckRequest.TakeFiles;
  FFake := TAtlasProblemsServerFake.Create;
  FServer := FFake;
  FIde := TAtlasProblemsEditorsFake.Create;
  FEditors := FIde;
  FSettings := TAtlasPluginSettings.Defaults;
  FSettings.Enabled := True;
  FSettings.Problems := True;
  FSettings.ProblemsLiveDelayMs := cDelayMs;
  // Nur die Probleme: Abblenden braucht ebenfalls Diagnosen und hielte den Ablauf an.
  FSettings.InactiveDim := False;
  FSettings.DimUnusedUses := False;
  FSettings.HighlightMovableUses := False;
  FLogText := '';
  FFlow := TAtlasProblemsFlow.Create(FServer, FEditors,
    procedure(const AMessage: string)
    begin
      FLogText := FLogText + AMessage + '|';
    end);
end;

procedure TAtlasProblemsFlowTests.TearDown;
begin
  FreeAndNil(FFlow);
  FFake := nil;
  FIde := nil;
  FServer := nil;
  FEditors := nil;
  FLogText := '';
  FSettings := Default(TAtlasPluginSettings);
  TAtlasTicks.SetClock(nil);
  TAtlasProblemsCheckRequest.Clear;
  TAtlasProblemsCheckRequest.TakeFiles;
end;

procedure TAtlasProblemsFlowTests.TypingPullsAfterQuietDelay;
var
  mPulls: TAtlasProblemsPulls;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  Assert.AreEqual('start+workspace,target', FFake.TakeCalls);
  Assert.IsTrue(FFake.Idle, 'vor der Tipp-Pause nichts holen');
  TickAfter(cDelayMs - 1);
  Assert.IsTrue(FFake.Idle, 'Pause noch nicht um');
  Assert.AreEqual('target', FFake.TakeCalls);
  TickAfter(1);
  Assert.AreEqual('target,sync:' + cFileA, FFake.TakeCalls);
  mPulls := FFake.TakePulls;
  Assert.AreEqual('A.pas+', PullText(mPulls), 'erste Prüfung ersetzt die Compilermeldungen');
  Assert.AreEqual(cTextA, mPulls[0].Text);
  Assert.AreEqual('', mPulls[0].PreviousId);
end;

procedure TAtlasProblemsFlowTests.AnswerFillsStoreAndFollowsTyping;
var
  mPulls: TAtlasProblemsPulls;
  mProblems: TArray<TAtlasProblem>;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  mPulls := FFake.TakePulls;
  // Während der Anfrage eine Zeile oben eingefügt: Der Befund rutscht mit.
  FIde.ShowEditor(cFileA, '// neu'#13#10 + cTextA, True);
  TickAfter(10);
  FFlow.Results.Document(FSettings, mPulls[0], Report(cFileA, 1, 'r1'));
  mProblems := FFlow.Results.Store.ForFile(cFileA);
  Assert.AreEqual(1, Integer(Length(mProblems)));
  Assert.AreEqual(2, mProblems[0].StartLine, 'auf den aktuellen Text gebracht');
  Assert.AreEqual(cFileA, FFlow.Results.LastCheck.FileName);
  Assert.IsTrue(FFlow.Results.Store.Contains(cFileA));
end;

procedure TAtlasProblemsFlowTests.UnchangedTextIsNotPulledAgain;
var
  mPulls: TAtlasProblemsPulls;
begin
  FIde.ShowEditor(cFileA, cTextA, False);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  TickAfter(cDelayMs * 3);
  Assert.IsTrue(FFake.Idle, 'gleicher Text: kein zweites Mal');
  FIde.ShowEditor(cFileA, cTextA + ' ', True);
  TickAfter(0);
  TickAfter(cDelayMs);
  mPulls := FFake.TakePulls;
  Assert.AreEqual('A.pas', PullText(mPulls), 'mit Ergebnis-Id, ohne Compilerersatz');
  Assert.AreEqual('r1', mPulls[0].PreviousId);
end;

procedure TAtlasProblemsFlowTests.BusyServerGetsNoSecondPull;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  FIde.ShowEditor(cFileA, cTextA + ' ', True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Assert.AreEqual(1, Integer(Length(FFake.TakePulls)), 'solange die Anfrage läuft, keine zweite');
  TickAfter(0);
  Assert.AreEqual(1, Integer(Length(FFake.TakePulls)), 'danach der neue Stand');
end;

procedure TAtlasProblemsFlowTests.DesignerInFrontDoesNotPull;
begin
  FIde.CodeInFront := False;
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Assert.IsTrue(FFake.Idle, 'im Designer nicht nachfragen');
  FIde.CodeInFront := True;
  TickAfter(0);
  Assert.IsFalse(FFake.Idle, 'zurück im Code');
end;

procedure TAtlasProblemsFlowTests.RefreshPullsAllSyncedFiles;
begin
  FFake.Sync(cFileB, 'unit B;');
  FIde.Open.Add(cFileB);
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  FFake.TakeCalls;
  FFake.RefreshCounter := 1;
  TickAfter(0);
  Assert.AreEqual('A.pas+,B.pas+', PullText(FFake.TakePulls), 'nach dem Compile alle neu, mit dcc-Meldungen');
  TickAfter(0);
  Assert.IsTrue(FFake.Idle, 'eine Bitte des Servers zählt einmal');
end;

procedure TAtlasProblemsFlowTests.SwitchSendsPreviousText;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  FIde.ShowEditor(cFileB, 'unit B;', True);
  FFake.TakeCalls;
  TickAfter(0);
  Assert.AreEqual('target,sync:' + cFileA, FFake.TakeCalls, 'Getipptes der vorigen Unit sofort an den Server');
  TickAfter(0);
  Assert.AreEqual('target', FFake.TakeCalls, 'nur einmal');
end;

procedure TAtlasProblemsFlowTests.DisabledDropsEverything;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  FFake.TakeCalls;
  FSettings.Problems := False;
  TickAfter(0);
  Assert.AreEqual('stop', FFake.TakeCalls);
  Assert.AreEqual(0, Integer(Length(FFlow.Results.Store.Files)), 'Speicher verworfen');
  TickAfter(0);
  Assert.AreEqual('', FFake.TakeCalls, 'angehalten bleibt angehalten');
  FFlow.Results.Document(FSettings, Default(TAtlasProblemsPull), Report(cFileA, 1, 'r2'));
  Assert.AreEqual(0, Integer(Length(FFlow.Results.Store.Files)), 'späte Antwort verfällt');
  FSettings.Problems := True;
  TickAfter(0);
  Assert.AreEqual('start+workspace,target', FFake.TakeCalls);
end;

procedure TAtlasProblemsFlowTests.DebuggerPausesAndResumes;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  FFake.TakeCalls;
  FIde.InDebugger := True;
  TickAfter(0);
  Assert.AreEqual('pause:an,stop', FFake.TakeCalls);
  TickAfter(cDelayMs);
  Assert.AreEqual('', FFake.TakeCalls, 'während des Debuggens ruht alles');
  Assert.IsTrue(FFake.Idle);
  FIde.InDebugger := False;
  TickAfter(0);
  Assert.AreEqual('pause:aus,start+workspace,target,sync:' + cFileA, FFake.TakeCalls,
    'danach geht es weiter; die Pause ist um');
end;

procedure TAtlasProblemsFlowTests.RemovedProjectsDropAndRestart;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  FFake.TakeCalls;
  FFake.RemovedProjects := 1;
  TickAfter(0);
  Assert.StartsWith('stop,start+workspace', FFake.TakeCalls);
  Assert.Contains(FLogText, 'projects removed');
  Assert.IsFalse(FFlow.Results.Store.Contains(cFileA), 'Befunde verworfen');
  TickAfter(cDelayMs);
  Assert.AreEqual(1, Integer(Length(FFake.TakePulls)), 'und nach der Pause neu geholt');
end;

procedure TAtlasProblemsFlowTests.NewSessionPullsAgain;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  FFake.TakeCalls;
  FFake.Restart;
  TickAfter(0);
  Assert.AreEqual('stop,start+workspace,target,sync:' + cFileA, FFake.TakeCalls);
  Assert.AreEqual('A.pas', PullText(FFake.TakePulls), 'gleicher Text, aber neue Sitzung');
end;

procedure TAtlasProblemsFlowTests.ClosedFilesAreClosedOnServer;
var
  mCalls: string;
begin
  FFake.Sync(cFileB, 'unit B;');
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  Assert.Contains(FFake.TakeCalls, 'close:' + cFileB, 'B ist in der IDE nicht offen');
  FFake.Sync(cFileB, 'unit B;');
  TickAfter(TAtlasProblemsFlow.cClosedCheckMs - 1);
  Assert.DoesNotContain(FFake.TakeCalls, 'close:', 'erst nach dem Abstand wieder suchen');
  TickAfter(1);
  mCalls := FFake.TakeCalls;
  Assert.Contains(mCalls, 'close:' + cFileB);
  Assert.DoesNotContain(mCalls, 'close:' + cFileA, 'A ist offen');
end;

procedure TAtlasProblemsFlowTests.RequestedFilesAreSyncedAndPulled;
begin
  FIde.Disk.Add(cFileB, 'unit B;');
  TAtlasProblemsCheckRequest.RequestFiles(TArray<string>.Create(cFileB, 'C:\p\Liesmich.txt', 'C:\p\Fehlt.pas'));
  TickAfter(0);
  Assert.AreEqual('start+workspace,sync:' + cFileB, FFake.TakeCalls, 'ohne offenen Editor; nur lesbare Quellen');
  Assert.AreEqual('B.pas+', PullText(FFake.TakePulls));
  TickAfter(0);
  Assert.AreEqual('', FFake.TakeCalls, 'einmal');
end;

procedure TAtlasProblemsFlowTests.RequestedFilesWithoutServerAreDropped;
begin
  FFake.Session := 0;
  FIde.Disk.Add(cFileB, 'unit B;');
  TAtlasProblemsCheckRequest.RequestFiles(TArray<string>.Create(cFileB));
  TickAfter(0);
  Assert.AreEqual('', FFake.TakeCalls);
  Assert.Contains(FLogText, 'requested check dropped');
  Assert.AreEqual(0, Integer(Length(TAtlasProblemsCheckRequest.TakeFiles)), 'verworfen, nicht aufgehoben');
end;

procedure TAtlasProblemsFlowTests.WorkspaceReportsSkipSyncedFiles;
var
  mRun: TLspWorkspaceRun;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  mRun := Default(TLspWorkspaceRun);
  FFlow.Results.Workspace(FSettings, TArray<TLspDiagnosticReport>.Create(Report(cFileA, 1, 'w1'),
    Report(cFileB, 0, 'w2')), mRun);
  Assert.IsFalse(FFlow.Results.Store.Contains(cFileA), 'abgeglichene Dateien kommen über textDocument/diagnostic');
  Assert.IsTrue(FFlow.Results.Store.Contains(cFileB));
  Assert.AreEqual(1, Integer(Length(FFlow.Results.Store.ForFile(cFileB))));
end;

procedure TAtlasProblemsFlowTests.WorkspaceRunRemembersFinish;
var
  mRun, mSeen: TLspWorkspaceRun;
  mAgo: UInt64;
begin
  Assert.IsFalse(FFlow.Results.ProjectRun(mSeen, mAgo), 'noch kein Stand');
  mRun := Default(TLspWorkspaceRun);
  mRun.Known := True;
  mRun.Active := True;
  mRun.Done := 3;
  mRun.Total := 10;
  FFlow.Results.Workspace(FSettings, nil, mRun);
  Assert.IsTrue(FFlow.Results.ProjectRun(mSeen, mAgo));
  Assert.AreEqual(3, mSeen.Done);
  Assert.AreEqual<UInt64>(High(UInt64), mAgo, 'noch kein Lauf zu Ende');
  mRun.Active := False;
  mRun.Done := 10;
  FFlow.Results.Workspace(FSettings, nil, mRun);
  GNow := GNow + 1500;
  Assert.IsTrue(FFlow.Results.ProjectRun(mSeen, mAgo));
  Assert.AreEqual<UInt64>(1500, mAgo, 'seit dem Ende des Laufs');
end;

procedure TAtlasProblemsFlowTests.WorkspaceOnlyWhileProblemsShown;
var
  mRun: TLspWorkspaceRun;
begin
  FSettings.Problems := False;
  FSettings.InactiveDim := True;
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  Assert.AreEqual('start,target', FFake.TakeCalls, 'Abblenden braucht nur die geöffneten Dateien');
  mRun := Default(TLspWorkspaceRun);
  FFlow.Results.Workspace(FSettings, TArray<TLspDiagnosticReport>.Create(Report(cFileB, 0, 'w2')), mRun);
  Assert.IsFalse(FFlow.Results.Store.Contains(cFileB));
end;

procedure TAtlasProblemsFlowTests.IdeErrorsFollowEachCheck;
var
  mPull: TAtlasProblemsPull;
  mIde: TAtlasProblem;
begin
  FIde.IdeErrorsOn := True;
  mIde := Problem(3, 'Undeklarierter Bezeichner');
  mIde.Source := TAtlasProblem.cIdeSource;
  mIde.Severity := TAtlasProblemSeverity.Error;
  FIde.SetIdeErrors(cFileA, TArray<TAtlasProblem>.Create(mIde));
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  mPull := FFake.TakePulls[0];
  FFlow.Results.Document(FSettings, mPull, Report(cFileA, 1, 'r1'));
  Assert.AreEqual(2, Integer(Length(FFlow.Results.Store.WithIde(cFileA))), 'Befund und Fehler der IDE');
  FIde.IdeErrorsOn := False;
  TickAfter(0);
  Assert.AreEqual(1, Integer(Length(FFlow.Results.Store.WithIde(cFileA))), 'ausgeschaltet verworfen');
end;

procedure TAtlasProblemsFlowTests.CountsAreReportedOnChange;
var
  mShow: Boolean;
  mCounts: TAtlasProblemCounts;
begin
  FSettings.ProblemsStatusCounter := True;
  // Ohne Atlas-Statusleiste am Editor, sonst zeigt diese die Befunde.
  FSettings.EditorStatusBar := False;
  Assert.IsTrue(FFlow.Results.CountsDue(FSettings, mShow, mCounts), 'erste Meldung');
  Assert.IsTrue(mShow);
  Assert.IsFalse(FFlow.Results.CountsDue(FSettings, mShow, mCounts), 'unverändert');
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  Assert.IsTrue(FFlow.Results.CountsDue(FSettings, mShow, mCounts));
  Assert.AreEqual(1, mCounts.Warnings);
  FSettings.Problems := False;
  Assert.IsTrue(FFlow.Results.CountsDue(FSettings, mShow, mCounts));
  Assert.IsFalse(mShow, 'ausgeschaltet: Feld entfernen');
end;

procedure TAtlasProblemsFlowTests.FailedStartWaitsBeforeRetry;
begin
  FFake.Session := 0;
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  Assert.AreEqual('', FFake.TakeCalls, 'Start gescheitert');
  FFake.Startable := True;
  TickAfter(1000);
  Assert.AreEqual(0, FFake.Session, 'nicht gleich wieder starten');
  TickAfter(TAtlasProblemsFlow.cStartRetryMs);
  Assert.AreEqual(1, FFake.Session, 'nach der Wartezeit erneut');
  Assert.StartsWith('start+workspace', FFake.TakeCalls);
end;

procedure TAtlasProblemsFlowTests.StoppedSessionStartsFresh;
begin
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Answer(1);
  FFake.TakeCalls;
  FFlow.StopPulls;
  FFlow.Stopped;
  Assert.AreEqual('stop', FFake.TakeCalls);
  TickAfter(0);
  Assert.AreEqual('start+workspace,target,sync:' + cFileA, FFake.TakeCalls);
  Assert.AreEqual('A.pas', PullText(FFake.TakePulls), 'Stände der alten Sitzung verworfen');
end;

procedure TAtlasProblemsFlowTests.CheckingWhilePullOpen;
begin
  Assert.IsFalse(FFlow.Checking);
  FIde.ShowEditor(cFileA, cTextA, True);
  TickAfter(0);
  TickAfter(cDelayMs);
  Assert.IsTrue(FFlow.Checking);
  Answer(1);
  Assert.IsFalse(FFlow.Checking);
end;

end.
