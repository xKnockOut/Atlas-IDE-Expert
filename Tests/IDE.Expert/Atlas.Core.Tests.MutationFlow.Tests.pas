unit Atlas.Core.Tests.MutationFlow.Tests;

// Tests für den Ablauf des Mutationslaufs (TAtlasMutationFlow) gegen das
// gefälschte Schattenprojekt (TAtlasMutationShadowFake) mit einer Uhr des
// Tests: erst unverändert, dann je Mutant; rote, nicht gebaute und nicht
// bewertbare Läufe ohne Mutation; ungültiger Mutant; Build abgelehnt, ohne
// EXE, Kopie nicht schreibbar, Schattenprojekt nicht zu öffnen oder zu
// schließen; Ende mitten im Lauf behält die Ergebnisse; nicht gestartete
// Test-EXE zählt nicht als erkannt; Abbruch; späte Antworten; Ergebnisse im
// Ende; Zustand der Test-EXE aus dem Ergebnis des Prozessläufers.

interface

uses
  DUnitX.TestFramework,
  Atlas.Core.Tests.MutationResults,
  Atlas.Core.Tests.MutationPlan,
  Atlas.Core.Tests.MutationFlow,
  Atlas.Tests.MutationShadowFake;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasMutationFlowTests = class
  private
    FFake: TAtlasMutationShadowFake;
    FProject: IAtlasMutationShadowProject;
    FFlow: TAtlasMutationFlow;
    FNotes: TArray<TAtlasMutationNote>;
    FEnds: string;
    FNow: UInt64;
    /// <summary>Beim Ende gesehen: Anzahl Jobs, fertige und Status je Ausgang.</summary>
    FEndedJobs: Integer;
    FEndedDone: Integer;
    FEndedStatus: TArray<TAtlasMutationStatus>;
    procedure Noted(const ANote: TAtlasMutationNote);
    procedure Ended(AEnd: TAtlasMutationEnd);
    /// <summary>Lauf über AJobs.</summary>
    procedure StartWith(const AJobs: TArray<TAtlasMutationJob>);
    /// <summary>Lauf über die beiden Mutanten von „&gt;“.</summary>
    procedure Start;
    /// <summary>Den ausstehenden Schritt gebaut und mit grünen (AGreen) bzw. roten Tests beenden.</summary>
    procedure Pass(AGreen: Boolean);
    /// <summary>Arten der Meldungen, durch Komma getrennt.</summary>
    function Kinds: string;
    function LastNote: TAtlasMutationNote;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure BaselineThenEachMutant;
    [Test]
    procedure SurvivorIsNotedAtEnd;
    [Test]
    procedure OutcomesAvailableWhenEnded;
    [Test]
    procedure DurationFromClock;
    [Test]
    procedure OpenProblemStops;
    [Test]
    procedure RedBaselineStops;
    [Test]
    procedure BaselineNotBuiltStops;
    [Test]
    procedure MutantNotBuiltCounts;
    [Test]
    procedure TimedOutMutantCounts;
    [Test]
    procedure InvalidMutantIsNotBuilt;
    [Test]
    procedure BuildRefusedStops;
    [Test]
    procedure BuildErrorStops;
    [Test]
    procedure MissingExecutableStops;
    [Test]
    procedure WriteErrorStops;
    [Test]
    procedure CloseErrorIsNoted;
    [Test]
    procedure BuildRefusedMidRunKeepsResults;
    [Test]
    procedure BuildErrorMidRunKeepsResults;
    [Test]
    procedure WriteErrorMidRunKeepsResults;
    [Test]
    procedure MissingExecutableMidRunKeepsResults;
    [Test]
    procedure BaselineNotStartedStops;
    [Test]
    procedure MutantNotStartedIsNotKilled;
    [Test]
    procedure RunStatesFromRunner;
    [Test]
    procedure CancelEndsAfterCurrentStep;
    [Test]
    procedure CancelledTestRunEnds;
    [Test]
    procedure LateAnswerAfterAbandonIsIgnored;
    [Test]
    procedure WithoutJobsNothingStarts;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.VersionControl.Contract;

const
  cExe = 'C:\P\Shadow\Tests.exe';
  cKindNames: array[TAtlasMutationNoteKind] of string = ('Started', 'OpenFailed', 'WriteFailed', 'BuildRefused',
    'NoExecutable', 'NotStarted', 'BaselineFailed', 'Outcome', 'Survivor', 'Cancelled', 'Finished', 'CloseFailed');
  cEndNames: array[TAtlasMutationEnd] of string = ('Finished', 'Cancelled', 'Stopped');

/// <summary>Zeilen der Unit: Routine P mit „A &gt; B“ in Zeile 3 (ab 1).</summary>
function Lines: TArray<string>;
begin
  Result := TArray<string>.Create('procedure P;', 'begin', '  if A > B then', '    X;', 'end;');
end;

/// <summary>Mutant AIndex in Routine P: „&gt;“ an Zeile 3, Spalte 8 durch AReplacement; AOriginal steht dort
/// (sonst ungültig).</summary>
function Job(AIndex: Integer; const AOriginal, AReplacement: string): TAtlasMutationJob;
begin
  Result := Default(TAtlasMutationJob);
  Result.Mutant.Id := AIndex + 1;
  Result.Mutant.OperatorId := 'boundary';
  Result.Mutant.Routine := 'P';
  Result.Mutant.Line := 3;
  Result.Mutant.Character := 8;
  Result.Mutant.EndLine := 3;
  Result.Mutant.EndCharacter := 9;
  Result.Mutant.Original := AOriginal;
  Result.Mutant.Replacement := AReplacement;
  Result.Routine.Name := 'P';
  Result.Routine.Line := 0;
  Result.Routine.EndLine := 4;
  Result.Index := AIndex;
end;

{ TAtlasMutationFlowTests }

procedure TAtlasMutationFlowTests.Setup;
begin
  FNow := 1000;
  TAtlasTicks.SetClock(
    function: UInt64
    begin
      Result := FNow;
    end);
  FFake := TAtlasMutationShadowFake.Create;
  FProject := FFake;
  FFlow := TAtlasMutationFlow.Create;
  FFlow.OnNote := Noted;
  FFlow.OnEnded := Ended;
end;

procedure TAtlasMutationFlowTests.TearDown;
begin
  FFlow.Free;
  FFlow := nil;
  FProject := nil;
  FFake := nil;
  FNotes := nil;
  FEnds := '';
  FEndedStatus := nil;
  TAtlasTicks.SetClock(nil);
end;

procedure TAtlasMutationFlowTests.Noted(const ANote: TAtlasMutationNote);
begin
  SetLength(FNotes, Length(FNotes) + 1);
  FNotes[High(FNotes)] := ANote;
end;

procedure TAtlasMutationFlowTests.Ended(AEnd: TAtlasMutationEnd);
var
  mIndex: Integer;
begin
  if FEnds <> '' then
  begin
    FEnds := FEnds + ',';
  end;
  FEnds := FEnds + cEndNames[AEnd];
  FEndedJobs := Length(FFlow.Jobs);
  FEndedDone := FFlow.DoneCount;
  SetLength(FEndedStatus, Length(FFlow.Outcomes));
  for mIndex := 0 to High(FFlow.Outcomes) do
  begin
    FEndedStatus[mIndex] := FFlow.Outcomes[mIndex].Status;
  end;
end;

procedure TAtlasMutationFlowTests.Start;
begin
  StartWith(TArray<TAtlasMutationJob>.Create(Job(0, '>', '>='), Job(1, '>', '<')));
end;

procedure TAtlasMutationFlowTests.StartWith(const AJobs: TArray<TAtlasMutationJob>);
var
  mSource: TAtlasMutationFlowSource;
begin
  mSource := Default(TAtlasMutationFlowSource);
  mSource.Jobs := AJobs;
  mSource.Lines := Lines;
  FFlow.Start(FProject, mSource);
end;

procedure TAtlasMutationFlowTests.Pass(AGreen: Boolean);
begin
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''), 'Build steht aus');
  Assert.IsTrue(FFake.FinishTests(AGreen), 'Test-EXE läuft');
end;

function TAtlasMutationFlowTests.Kinds: string;
var
  mNote: TAtlasMutationNote;
begin
  Result := '';
  for mNote in FNotes do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + cKindNames[mNote.Kind];
  end;
end;

function TAtlasMutationFlowTests.LastNote: TAtlasMutationNote;
begin
  Assert.IsTrue(Length(FNotes) > 0, 'keine Meldung');
  Result := FNotes[High(FNotes)];
end;

procedure TAtlasMutationFlowTests.BaselineThenEachMutant;
begin
  Start;
  Assert.AreEqual('open,write,build', FFake.Calls.CommaText);
  Assert.AreEqual(string.Join(#10, Lines), FFake.Written[0]);
  Pass(True);
  Assert.AreEqual('open,write,build,run:' + cExe + ',write,build', FFake.Calls.CommaText);
  Assert.IsTrue(FFake.Written[1].Contains('A >= B'), FFake.Written[1]);
  Pass(False);
  Assert.IsTrue(FFake.Written[2].Contains('A < B'), FFake.Written[2]);
  Pass(True);
  Assert.AreEqual('close', FFake.Calls[FFake.Calls.Count - 1]);
  Assert.AreEqual('Finished', FEnds);
  Assert.IsFalse(FFlow.Active);
  Assert.AreEqual('Started,Outcome,Outcome,Survivor,Finished', Kinds);
  Assert.AreEqual(2, FNotes[0].Total);
  Assert.AreEqual(0, FNotes[1].Position);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed, FNotes[1].Status);
  Assert.AreEqual('U.TT.B', FNotes[1].By);
  Assert.AreEqual(1, FNotes[2].Position);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Survived, FNotes[2].Status);
  Assert.AreEqual(1, LastNote.Totals.Killed);
  Assert.AreEqual(1, LastNote.Totals.Survived);
  Assert.AreEqual(50, LastNote.Totals.Score);
end;

procedure TAtlasMutationFlowTests.SurvivorIsNotedAtEnd;
begin
  Start;
  Pass(True);
  Pass(False);
  Pass(True);
  Assert.AreEqual(1, FNotes[3].Position, 'der zweite Mutant überlebt');
  Assert.AreEqual(cMutationShadowFakeName, FNotes[3].Shadow);
end;

procedure TAtlasMutationFlowTests.OutcomesAvailableWhenEnded;
begin
  Start;
  Pass(True);
  Pass(False);
  Pass(True);
  Assert.AreEqual(2, FEndedJobs);
  Assert.AreEqual(2, FEndedDone);
  Assert.AreEqual(2, Integer(Length(FEndedStatus)));
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed, FEndedStatus[0]);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Survived, FEndedStatus[1]);
  // Nach dem Ende ist der Ablauf leer.
  Assert.AreEqual(0, Integer(Length(FFlow.Jobs)));
end;

procedure TAtlasMutationFlowTests.DurationFromClock;
var
  mMilliseconds: Integer;
begin
  Start;
  Pass(True);
  FNow := FNow + 250;
  Pass(False);
  mMilliseconds := FFlow.Outcomes[0].Milliseconds;
  Assert.AreEqual(250, mMilliseconds);
end;

procedure TAtlasMutationFlowTests.OpenProblemStops;
begin
  FFake.OpenProblem := 'dpr kaputt';
  Start;
  Assert.AreEqual('open,close', FFake.Calls.CommaText);
  Assert.AreEqual('OpenFailed', Kinds);
  Assert.AreEqual('dpr kaputt', LastNote.Text);
  Assert.AreEqual('Stopped', FEnds);
  Assert.IsFalse(FFlow.Active);
end;

procedure TAtlasMutationFlowTests.RedBaselineStops;
begin
  Start;
  Pass(False);
  Assert.AreEqual(1, FFake.Written.Count, 'kein Mutant geschrieben');
  Assert.AreEqual('Started,BaselineFailed', Kinds);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed, LastNote.Status);
  Assert.AreEqual('U.TT.B', LastNote.By);
  Assert.AreEqual('Stopped', FEnds);
  Assert.AreEqual('close', FFake.Calls[FFake.Calls.Count - 1]);
end;

procedure TAtlasMutationFlowTests.BaselineNotBuiltStops;
begin
  Start;
  Assert.IsTrue(FFake.FinishBuild(False, '', ''));
  Assert.AreEqual('Started,BaselineFailed', Kinds);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.BuildFailed, LastNote.Status);
  Assert.AreEqual('Stopped', FEnds);
end;

procedure TAtlasMutationFlowTests.MutantNotBuiltCounts;
begin
  Start;
  Pass(True);
  Assert.IsTrue(FFake.FinishBuild(False, '', ''));
  // Weiter mit dem nächsten Mutanten, ohne die Test-EXE.
  Assert.AreEqual('open,write,build,run:' + cExe + ',write,build,write,build', FFake.Calls.CommaText);
  Pass(True);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.BuildFailed, FEndedStatus[0]);
  Assert.AreEqual('Finished', FEnds);
end;

procedure TAtlasMutationFlowTests.TimedOutMutantCounts;
begin
  Start;
  Pass(True);
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''));
  Assert.IsTrue(FFake.FinishRun(TAtlasMutationRunState.TimedOut, 0, ''));
  Pass(True);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.TimedOut, FEndedStatus[0]);
end;

procedure TAtlasMutationFlowTests.InvalidMutantIsNotBuilt;
begin
  // Der zweite Mutant passt nicht zum Text („<“ steht dort nicht).
  StartWith(TArray<TAtlasMutationJob>.Create(Job(0, '>', '>='), Job(1, '<', '>'), Job(2, '>', '<')));
  Pass(True);
  Pass(False);
  // Gleich weiter zum dritten, ohne Kopie und Build für den zweiten.
  Assert.AreEqual(3, FFake.Written.Count);
  Pass(True);
  Assert.AreEqual(3, Integer(Length(FEndedStatus)));
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Invalid, FEndedStatus[1]);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Survived, FEndedStatus[2]);
end;

procedure TAtlasMutationFlowTests.BuildRefusedStops;
begin
  FFake.BuildRefusal := 'Build läuft';
  Start;
  Assert.AreEqual('Started,BuildRefused', Kinds);
  Assert.AreEqual('Build läuft', LastNote.Text);
  Assert.AreEqual(cMutationShadowFakeName, LastNote.Shadow);
  Assert.AreEqual('open,write,build,close', FFake.Calls.CommaText);
  Assert.AreEqual('Stopped', FEnds);
end;

procedure TAtlasMutationFlowTests.BuildErrorStops;
begin
  Start;
  Assert.IsTrue(FFake.FinishBuild(False, '', 'gesperrt'));
  Assert.AreEqual('Started,BuildRefused', Kinds);
  Assert.AreEqual('gesperrt', LastNote.Text);
  Assert.AreEqual('Stopped', FEnds);
end;

procedure TAtlasMutationFlowTests.MissingExecutableStops;
begin
  Start;
  Assert.IsTrue(FFake.FinishBuild(True, '', ''));
  Assert.AreEqual('Started,NoExecutable', Kinds);
  Assert.IsFalse(FFake.Calls.CommaText.Contains('run:'));
  Assert.AreEqual('Stopped', FEnds);
end;

procedure TAtlasMutationFlowTests.WriteErrorStops;
begin
  FFake.WriteError := 'Zugriff verweigert';
  Start;
  Assert.AreEqual('Started,WriteFailed', Kinds);
  Assert.AreEqual('Zugriff verweigert', LastNote.Text);
  Assert.AreEqual('open,write,close', FFake.Calls.CommaText);
  Assert.AreEqual('Stopped', FEnds);
end;

procedure TAtlasMutationFlowTests.CloseErrorIsNoted;
begin
  FFake.CloseError := 'Projekt gesperrt';
  Start;
  Pass(True);
  Pass(False);
  Pass(True);
  Assert.AreEqual('Started,Outcome,Outcome,CloseFailed,Survivor,Finished', Kinds);
  Assert.AreEqual('Projekt gesperrt', FNotes[3].Text);
  Assert.AreEqual(cMutationShadowFakeName, FNotes[3].Shadow, 'Name für die Meldung, das Projekt steht noch offen');
  Assert.AreEqual('Finished', FEnds);
end;

/// <summary>Erst ohne Mutation grün, der erste Mutant überlebt; danach endet der Lauf durch die Umgebung.</summary>
procedure TAtlasMutationFlowTests.BuildRefusedMidRunKeepsResults;
begin
  Start;
  Pass(True);
  // Beim Build des zweiten Mutanten läuft der Debugger.
  FFake.BuildRefusal := 'Debugger läuft';
  Pass(True);
  Assert.AreEqual('Started,Outcome,BuildRefused,Survivor,Cancelled,Finished', Kinds);
  Assert.AreEqual('Debugger läuft', FNotes[2].Text);
  Assert.AreEqual(0, FNotes[3].Position, 'Überlebender des ersten Mutanten');
  Assert.AreEqual(1, LastNote.Done);
  Assert.AreEqual(1, LastNote.Totals.Survived);
  Assert.AreEqual(0, LastNote.Totals.Score);
  Assert.AreEqual('Cancelled', FEnds, 'wie Abbrechen: Ergebnisse werden gemerkt');
  Assert.AreEqual(1, FEndedDone);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Survived, FEndedStatus[0]);
  Assert.AreEqual('close', FFake.Calls[FFake.Calls.Count - 1]);
  Assert.IsFalse(FFlow.Active);
end;

procedure TAtlasMutationFlowTests.BuildErrorMidRunKeepsResults;
begin
  Start;
  Pass(True);
  Pass(False);
  Assert.IsTrue(FFake.FinishBuild(False, '', 'anderer Build läuft'));
  Assert.AreEqual('Started,Outcome,BuildRefused,Cancelled,Finished', Kinds);
  Assert.AreEqual('anderer Build läuft', FNotes[2].Text);
  Assert.AreEqual(1, LastNote.Totals.Killed);
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(1, FEndedDone);
  Assert.AreEqual<TAtlasMutationStatus>(TAtlasMutationStatus.Killed, FEndedStatus[0]);
end;

procedure TAtlasMutationFlowTests.WriteErrorMidRunKeepsResults;
begin
  Start;
  Pass(True);
  FFake.WriteError := 'Zugriff verweigert';
  Pass(False);
  Assert.AreEqual('Started,Outcome,WriteFailed,Cancelled,Finished', Kinds);
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(1, FEndedDone);
end;

procedure TAtlasMutationFlowTests.MissingExecutableMidRunKeepsResults;
begin
  Start;
  Pass(True);
  Pass(True);
  Assert.IsTrue(FFake.FinishBuild(True, '', ''));
  Assert.AreEqual('Started,Outcome,NoExecutable,Survivor,Cancelled,Finished', Kinds);
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(1, FEndedDone);
end;

procedure TAtlasMutationFlowTests.BaselineNotStartedStops;
begin
  Start;
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''));
  Assert.IsTrue(FFake.FinishRun(TAtlasMutationRunState.NotStarted, -1, ''));
  Assert.AreEqual('Started,NotStarted', Kinds);
  Assert.AreEqual(cMutationShadowFakeName, LastNote.Shadow);
  Assert.AreEqual('Stopped', FEnds);
  Assert.AreEqual(1, FFake.Written.Count, 'kein Mutant geschrieben');
end;

procedure TAtlasMutationFlowTests.MutantNotStartedIsNotKilled;
begin
  StartWith(TArray<TAtlasMutationJob>.Create(Job(0, '>', '>='), Job(1, '>', '<'), Job(2, '>', '<=')));
  Pass(True);
  Pass(False);
  Pass(True);
  // Der dritte Mutant ist gebaut, aber die Test-EXE startet nicht (Virenscanner hält sie fest).
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''));
  Assert.IsTrue(FFake.FinishRun(TAtlasMutationRunState.NotStarted, -1, ''));
  Assert.AreEqual('Started,Outcome,Outcome,NotStarted,Survivor,Cancelled,Finished', Kinds);
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(2, FEndedDone, 'der dritte zählt nicht');
  Assert.AreEqual(1, LastNote.Totals.Killed);
  Assert.AreEqual(1, LastNote.Totals.Survived);
  Assert.AreEqual(4, FFake.Written.Count, 'kein weiterer Schritt');
end;

procedure TAtlasMutationFlowTests.RunStatesFromRunner;
begin
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.Completed,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.Ok, 1));
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.Completed,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.Failed, 3), 'gelaufen, nur zu viel Ausgabe');
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.NotStarted,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.Failed, -1), 'Pipes oder Start gescheitert');
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.NotStarted,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.ToolMissing, -1));
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.NotStarted,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.MainThread, 0));
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.Cancelled,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.Cancelled, -1));
  Assert.AreEqual<TAtlasMutationRunState>(TAtlasMutationRunState.TimedOut,
    TAtlasMutationRunStates.FromRunner(TAtlasVcsOutcome.TimedOut, -1));
end;

procedure TAtlasMutationFlowTests.CancelEndsAfterCurrentStep;
begin
  Start;
  Pass(True);
  FFlow.Cancel;
  Assert.IsTrue(FFlow.Active, 'der laufende Schritt endet noch');
  Pass(False);
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(1, FEndedDone);
  Assert.AreEqual(2, FFake.Written.Count, 'zweiter Mutant nicht mehr geschrieben');
  Assert.AreEqual('Started,Outcome,Cancelled,Finished', Kinds);
  Assert.AreEqual(1, FNotes[2].Done);
  Assert.AreEqual(2, FNotes[2].Total);
end;

procedure TAtlasMutationFlowTests.CancelledTestRunEnds;
begin
  Start;
  Pass(True);
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''));
  Assert.IsTrue(FFake.FinishRun(TAtlasMutationRunState.Cancelled, 0, ''));
  Assert.AreEqual('Cancelled', FEnds);
  Assert.AreEqual(0, FEndedDone);
  Assert.AreEqual('close', FFake.Calls[FFake.Calls.Count - 1]);
end;

procedure TAtlasMutationFlowTests.LateAnswerAfterAbandonIsIgnored;
var
  mCalls: Integer;
begin
  Start;
  FFlow.Abandon;
  Assert.IsFalse(FFlow.Active);
  Assert.AreEqual('close', FFake.Calls[FFake.Calls.Count - 1]);
  mCalls := FFake.Calls.Count;
  Assert.IsTrue(FFake.FinishBuild(True, cExe, ''));
  Assert.AreEqual(mCalls, FFake.Calls.Count, 'keine Test-EXE nach dem Ende');
  Assert.AreEqual('', FEnds, 'Abandon meldet kein Ende');
end;

procedure TAtlasMutationFlowTests.WithoutJobsNothingStarts;
begin
  FFlow.Start(FProject, Default(TAtlasMutationFlowSource));
  Assert.IsFalse(FFlow.Active);
  Assert.AreEqual(0, FFake.Calls.Count);
  Assert.AreEqual('', Kinds);
end;

end.
