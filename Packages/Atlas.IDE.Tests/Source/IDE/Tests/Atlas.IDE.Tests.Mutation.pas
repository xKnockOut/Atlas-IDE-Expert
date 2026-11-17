unit Atlas.IDE.Tests.Mutation;

// Mutationslauf in der IDE (#1460, tests.mutation, experimentell):
// - Befehle „Mutationen der Methode prüfen“ (Methode am Cursor bzw. an der
//   zuletzt rechts geklickten Zeile der Rinne), „… der Unit“ und
//   „… geänderter Methoden“ (Routinen ohne gültiges Ergebnis).
// - Ablauf im Hauptthread: Testprojekt wie „Tests ausführen“ wählen,
//   Mutanten beim Server erfragen (atlas.server.mutants mit den Operatoren
//   aus tests.mutation.operators), auswählen (Atlas.Core.Tests.MutationPlan),
//   Schattenprojekt neben dem Testprojekt anlegen (Atlas.Core.Tests.
//   MutationShadow) und in der Projektgruppe öffnen
//   (Atlas.IDE.Tests.MutationShadowProject). Den Ablauf (erst unverändert,
//   dann je Mutant schreiben, bauen, Test-EXE mit Zeitlimit
//   tests.mutation.timeoutSec ausführen, Ausgang festhalten) führt
//   TAtlasMutationFlow (Atlas.Core.Tests.MutationFlow).
// - Original und seine DCUs bleiben unberührt.
// - Abbrechen setzt TAtlasMutationAlive.Cancelled; der Prozessläufer prüft das
//   alle 10 ms und beendet die Test-EXE. Destroy wartet mit der üblichen
//   Zeitgrenze, was dann noch läuft, übernimmt TAtlasOverdueThreads.
// - Am Ende (oder nach „Mutationslauf abbrechen“) schließt der Lauf das
//   Schattenprojekt, merkt die Ergebnisse vollständig geprüfter Routinen in
//   .atlas-local\mutation\results.json des Testprojekts und meldet in der
//   Meldungsansicht Zahlen, Mutation-Score und je überlebendem Mutanten eine
//   anklickbare Zeile. Die Rinne (Atlas.IDE.Tests.MutationMarks) zeigt die
//   Ergebnisse, solange die Routine unverändert ist.
// Rückrufe (Server, Build, Thread) prüfen über TAtlasMutationAlive, ob der Lauf noch lebt.

interface

uses
  ToolsAPI,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.MutationResults,
  Atlas.Core.Tests.MutationPlan,
  Atlas.Core.Tests.MutationFlow,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Output,
  Atlas.IDE.Tests.MutationShadowProject;

type
  TAtlasIdeMutationRun = class
  private type
    /// <summary>Ein laufender Mutationslauf (vom Start bis zum Ende des Ablaufs).</summary>
    TState = record
      Active: Boolean;
      Scope: TAtlasMutationScope;
      FileName: string;
      Line: Integer;
      Lines: TArray<string>;
      Original: IOTAProject;
      Target: TAtlasTestTarget;
    end;
  private const
    cServerTimeoutMs = 60000;
  private class var
    FCurrent: TAtlasIdeMutationRun;
  private
    FScope: IAtlasModuleScope;
    FTests: TAtlasIdeTests;
    FOutput: TAtlasIdeTestsOutput;
    FNewRunner: TAtlasTestsRunnerFactory;
    FBuild: TAtlasMutationBuildFunc;
    FAlive: TAtlasMutationAlive;
    FAliveRef: IInterface;
    FFlow: TAtlasMutationFlow;
    /// <summary>Thread der Test-EXE; höchstens einer läuft, ein endender Vorgänger kann noch darin stehen.</summary>
    FThreads: TAtlasWorkerSlot;
    FResults: TAtlasMutationResults;
    FResultsProject: string;
    FVersion: Integer;
    FState: TState;
    procedure ProjectChosen(const AProject: IOTAProject);
    procedure Answered(const AJson: string);
    /// <summary>Schattenprojekt für den Lauf in FState.</summary>
    function NewShadowProject: IAtlasMutationShadowProject;
    procedure StartFlow(const AJobs: TArray<TAtlasMutationJob>);
    procedure FlowNote(const ANote: TAtlasMutationNote);
    procedure FlowEnded(AEnd: TAtlasMutationEnd);
    procedure StopWith(const AText: string);
    procedure Remember;
    procedure LoadResults(const AProject: string);
    procedure SaveResults;
  public
    /// <summary>ATests und AOutput gehören dem Aufrufer und leben länger.</summary>
    constructor Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests; AOutput: TAtlasIdeTestsOutput;
      const ANewRunner: TAtlasTestsRunnerFactory; const ABuild: TAtlasMutationBuildFunc);
    destructor Destroy; override;
    /// <summary>Lauf für AScope im oberen Editor starten.</summary>
    procedure Start(AScope: TAtlasMutationScope);
    /// <summary>Laufenden Mutationslauf nach dem aktuellen Schritt beenden.</summary>
    procedure Cancel;
    function Running: Boolean;
    /// <summary>Marken der Rinne für AFileName mit dem Text ALines; liest ohne Ergebnisse die des aktiven
    /// Testprojekts.</summary>
    function MarksOf(const AFileName: string; const ALines: TArray<string>): TArray<TAtlasMutationLineMark>;
    /// <summary>Zählt jede Änderung der Ergebnisse (Neuzeichnen der Rinne).</summary>
    property Version: Integer read FVersion;
    /// <summary>Der Lauf des Moduls; nil ohne.</summary>
    class property Current: TAtlasIdeMutationRun read FCurrent;
    /// <summary>Text eines Ausgangs für Meldungsansicht und Tooltip.</summary>
    class function StatusText(AStatus: TAtlasMutationStatus; const ABy: string): string; static;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Tests.MutationShadow,
  Atlas.Core.Tests.Mutants,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.GutterMarks,
  Atlas.IDE.Tests.Projects;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

/// <summary>Datei und Zeile (ab 0) im oberen Editor: zuletzt rechts geklickte Zeile der Rinne, sonst der Cursor.
/// False ohne Unit.</summary>
function TopUnit(out AFileName: string; out ALine: Integer): Boolean;
var
  mEditors: IOTAEditorServices;
  mView: IOTAEditView;
begin
  AFileName := '';
  ALine := -1;
  mView := nil;
  if Supports(BorlandIDEServices, IOTAEditorServices, mEditors) then
  begin
    mView := mEditors.TopView;
  end;
  if (mView = nil) or (mView.Buffer = nil) or not SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Exit(False);
  end;
  AFileName := mView.Buffer.FileName;
  if not TAtlasIdeGutterMarks.TakeLine(AFileName, ALine) then
  begin
    ALine := mView.CursorPos.Line - 1;
  end;
  Result := True;
end;

/// <summary>Rückruf der Projektwahl, solange der Lauf lebt.</summary>
function ChosenProc(ARun: TAtlasIdeMutationRun; AAlive: TAtlasMutationAlive;
  const AKeep: IInterface): TAtlasTestsProjectProc;
var
  mRun: TAtlasIdeMutationRun;
  mAlive: TAtlasMutationAlive;
  mKeep: IInterface;
begin
  mRun := ARun;
  mAlive := AAlive;
  mKeep := AKeep;
  Result :=
    procedure(const AProject: IOTAProject)
    begin
      if (mKeep <> nil) and mAlive.Alive then
      begin
        mRun.ProjectChosen(AProject);
      end;
    end;
end;

/// <summary>Rückruf des Servers, solange der Lauf lebt.</summary>
function AnswerProc(ARun: TAtlasIdeMutationRun; AAlive: TAtlasMutationAlive;
  const AKeep: IInterface): TProc<string>;
var
  mRun: TAtlasIdeMutationRun;
  mAlive: TAtlasMutationAlive;
  mKeep: IInterface;
begin
  mRun := ARun;
  mAlive := AAlive;
  mKeep := AKeep;
  Result :=
    procedure(AJson: string)
    begin
      if (mKeep <> nil) and mAlive.Alive then
      begin
        mRun.Answered(AJson);
      end;
    end;
end;

{ TAtlasIdeMutationRun }

constructor TAtlasIdeMutationRun.Create(const AScope: IAtlasModuleScope; ATests: TAtlasIdeTests;
  AOutput: TAtlasIdeTestsOutput; const ANewRunner: TAtlasTestsRunnerFactory; const ABuild: TAtlasMutationBuildFunc);
begin
  inherited Create;
  FScope := AScope;
  FTests := ATests;
  FOutput := AOutput;
  FNewRunner := ANewRunner;
  FBuild := ABuild;
  FAlive := TAtlasMutationAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FResults := TAtlasMutationResults.Create;
  FThreads := TAtlasWorkerSlot.Create(HInstance);
  FFlow := TAtlasMutationFlow.Create;
  FFlow.OnNote := FlowNote;
  FFlow.OnEnded := FlowEnded;
  FCurrent := Self;
end;

destructor TAtlasIdeMutationRun.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FAlive.Alive := False;
  FAlive.Cancelled := True;
  // Der Prozessläufer sieht den Abbruch nach höchstens 10 ms und beendet die Test-EXE. Hängt der Thread trotzdem
  // (Prozess lässt sich nicht beenden), wartet die IDE nicht länger als die übliche Zeitgrenze; den Rest übernimmt
  // TAtlasOverdueThreads und wartet beim Abmelden des Moduls nach bzw. hält das Package fest.
  if FThreads <> nil then
  begin
    FThreads.Stop(TAtlasShutdown.cStopMs);
    FreeAndNil(FThreads);
  end;
  if FFlow <> nil then
  begin
    FFlow.Abandon;
    FreeAndNil(FFlow);
  end;
  FResults.Free;
  FAliveRef := nil;
  TAtlasIdeGutterMarks.Invalidate;
  inherited Destroy;
end;

procedure TAtlasIdeMutationRun.ProjectChosen(const AProject: IOTAProject);
var
  mOperators: TArray<string>;
begin
  if FState.Active or FTests.Busy then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationBusy));
    Exit;
  end;
  if not TAtlasIdeFiles.ReadLines(FState.FileName, FState.Lines) then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoUnit));
    Exit;
  end;
  FState.Original := AProject;
  FState.Target := TAtlasIdeTests.TargetOf(AProject, nil);
  LoadResults(FState.Target.Project);
  FState.Active := True;
  FAlive.Cancelled := False;
  Inc(FVersion);
  mOperators := TAtlasMutationPlan.OperatorsOf(TAtlasIdeSettings.Current.TestsMutationOperators);
  if not TAtlasIdeHost.RunServerCommandAsync(FScope, TAtlasFeature.Build, TAtlasMutationPlan.cCommand,
    TAtlasMutationPlan.RequestJson(TLspSessionJson.PathToUri(FState.FileName), mOperators), cServerTimeoutMs,
    AnswerProc(Self, FAlive, FAliveRef)) then
  begin
    FState.Active := False;
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoServer));
  end;
end;

procedure TAtlasIdeMutationRun.Answered(const AJson: string);
var
  mList: TAtlasMutantList;
  mUnit: string;
  mJobs: TArray<TAtlasMutationJob>;
begin
  mUnit := ExtractFileName(FState.FileName);
  if not TAtlasMutants.Parse(AJson, mList) then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationServerFailed, [mUnit]));
    Exit;
  end;
  mJobs := TAtlasMutationPlan.Select(mList, FState.Scope, FState.Line, FState.FileName, FState.Lines, FResults);
  if Length(mJobs) = 0 then
  begin
    case FState.Scope of
      TAtlasMutationScope.Routine:
        StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationNoRoutine, [FState.Line + 1]));
      TAtlasMutationScope.Changed:
        StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationNothingChanged, [mUnit]));
    else
      StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationNoMutants, [mUnit]));
    end;
    Exit;
  end;
  StartFlow(mJobs);
end;

function TAtlasIdeMutationRun.NewShadowProject: IAtlasMutationShadowProject;
var
  mSetup: TAtlasIdeMutationShadowSetup;
begin
  mSetup := Default(TAtlasIdeMutationShadowSetup);
  mSetup.Original := FState.Original;
  mSetup.Target := FState.Target;
  mSetup.UnitFile := FState.FileName;
  mSetup.Build := FBuild;
  mSetup.NewRunner := FNewRunner;
  mSetup.Threads := FThreads;
  mSetup.Alive := FAlive;
  Result := TAtlasIdeMutationShadowProject.Create(mSetup);
end;

procedure TAtlasIdeMutationRun.StartFlow(const AJobs: TArray<TAtlasMutationJob>);
var
  mSource: TAtlasMutationFlowSource;
begin
  mSource := Default(TAtlasMutationFlowSource);
  mSource.Jobs := AJobs;
  mSource.Lines := FState.Lines;
  FFlow.Start(NewShadowProject, mSource);
end;

/// <summary>Score der Zahlen ATotals für die Schlussmeldung.</summary>
function ScoreText(const ATotals: TAtlasMutationTotals): string;
begin
  Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoScore);
  if ATotals.Score >= 0 then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationScore, [ATotals.Score]);
  end;
end;

/// <summary>Text der Meldung ANote zum Mutanten AJob; Unit AUnit, Testprojekt mit Ziel ATarget.</summary>
function NoteText(const ANote: TAtlasMutationNote; const AJob: TAtlasMutationJob; const AUnit: string;
  const ATarget: TAtlasTestTarget): string;
begin
  case ANote.Kind of
    TAtlasMutationNoteKind.Started:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStarted, [ANote.Total, AUnit,
        ProjectName(ATarget.Project), ATarget.Configuration, ATarget.Platform]);
    TAtlasMutationNoteKind.WriteFailed:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowFailed, [AUnit, ANote.Text]);
    TAtlasMutationNoteKind.BuildRefused:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBuildRefused, [ANote.Shadow, ANote.Text]);
    TAtlasMutationNoteKind.NoExecutable:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationNoExe, [ANote.Shadow]);
    TAtlasMutationNoteKind.BaselineFailed:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBaselineFailed, [ProjectName(ATarget.Project),
        TAtlasIdeMutationRun.StatusText(ANote.Status, ANote.By)]);
    TAtlasMutationNoteKind.Outcome:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationOutcome, [ANote.Position + 1, ANote.Total,
        AJob.Routine.Name, AJob.Mutant.Line, AJob.Mutant.Original, AJob.Mutant.Replacement,
        TAtlasIdeMutationRun.StatusText(ANote.Status, ANote.By)]);
    TAtlasMutationNoteKind.Survivor:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationSurvivor, [AJob.Routine.Name, AJob.Mutant.Line,
        AJob.Mutant.Original, AJob.Mutant.Replacement, AJob.Mutant.OperatorId]);
    TAtlasMutationNoteKind.Cancelled:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationCancelled, [ANote.Done, ANote.Total]);
    TAtlasMutationNoteKind.Finished:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationFinished, [AUnit,
        ANote.Totals.Killed + ANote.Totals.TimedOut, ANote.Totals.Survived,
        ANote.Totals.BuildFailed + ANote.Totals.Invalid, ScoreText(ANote.Totals)]);
    TAtlasMutationNoteKind.NotStarted:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationTestsNotStarted, [ANote.Shadow]);
    TAtlasMutationNoteKind.CloseFailed:
      Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowNotClosed, [ANote.Shadow, ANote.Text]);
  else
    // OpenFailed: Der Grund ist schon der Text.
    Result := ANote.Text;
  end;
end;

procedure TAtlasIdeMutationRun.FlowNote(const ANote: TAtlasMutationNote);
var
  mJob: TAtlasMutationJob;
  mText: string;
begin
  mJob := Default(TAtlasMutationJob);
  if (ANote.Position >= 0) and (ANote.Position < Length(FFlow.Jobs)) then
  begin
    mJob := FFlow.Jobs[ANote.Position];
  end;
  mText := NoteText(ANote, mJob, ExtractFileName(FState.FileName), FState.Target);
  if ANote.Kind = TAtlasMutationNoteKind.Survivor then
  begin
    FOutput.Jump(FState.FileName, mText, mJob.Mutant.Line - 1, mJob.Mutant.Character - 1);
    Exit;
  end;
  FOutput.Say(mText);
  if ANote.Kind = TAtlasMutationNoteKind.Started then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationBaseline));
  end;
end;

procedure TAtlasIdeMutationRun.FlowEnded(AEnd: TAtlasMutationEnd);
begin
  if AEnd = TAtlasMutationEnd.Stopped then
  begin
    FState := Default(TState);
    Inc(FVersion);
    Exit;
  end;
  Remember;
  SaveResults;
  FOutput.ShowView;
  FState := Default(TState);
  Inc(FVersion);
  TAtlasIdeGutterMarks.Invalidate;
end;

procedure TAtlasIdeMutationRun.StopWith(const AText: string);
begin
  FOutput.Say(AText);
  FState := Default(TState);
  Inc(FVersion);
end;

procedure TAtlasIdeMutationRun.Start(AScope: TAtlasMutationScope);
var
  mFileName: string;
  mLine: Integer;
begin
  if FState.Active or FTests.Busy then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationBusy));
    Exit;
  end;
  if not TopUnit(mFileName, mLine) then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoUnit));
    Exit;
  end;
  if TAtlasIdeHost.ActiveSession = nil then
  begin
    FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoServer));
    Exit;
  end;
  FState := Default(TState);
  FState.Scope := AScope;
  FState.FileName := mFileName;
  FState.Line := mLine;
  FTests.ResolveProject(mFileName, ChosenProc(Self, FAlive, FAliveRef));
end;

procedure TAtlasIdeMutationRun.Remember;
var
  mIndex: Integer;
  mResult: TAtlasMutationRoutineResult;
  mComplete: Boolean;
  mJobs: TArray<TAtlasMutationJob>;
begin
  mJobs := FFlow.Jobs;
  for mIndex := 0 to High(mJobs) do
  begin
    if not TAtlasMutationSteps.FirstOfRoutine(mJobs, mIndex) then
    begin
      Continue;
    end;
    mResult := TAtlasMutationSteps.RoutineResult(mJobs, FFlow.Outcomes, mIndex, FFlow.DoneCount, mComplete);
    mResult.FileName := FState.FileName;
    mResult.Body := TAtlasMutants.RoutineBody(FState.Lines, mJobs[mIndex].Routine);
    mResult.AtUtc := TTimeZone.Local.ToUniversalTime(Now);
    // Abgebrochen: nur ganz geprüfte Routinen gelten, sonst fehlten „geänderten Methoden“ Mutanten.
    if mComplete then
    begin
      FResults.Put(mResult);
    end;
  end;
end;

procedure TAtlasIdeMutationRun.Cancel;
begin
  if FState.Active then
  begin
    FAlive.Cancelled := True;
    FFlow.Cancel;
  end;
end;

function TAtlasIdeMutationRun.Running: Boolean;
begin
  Result := FState.Active;
end;

function ResultsFileOf(const AProject: string): string;
begin
  Result := TPath.Combine(TAtlasMutationShadows.DataFolderOf(AProject), TAtlasMutationResults.cFileName);
end;

procedure TAtlasIdeMutationRun.LoadResults(const AProject: string);
var
  mFile: string;
begin
  if SameText(AProject, FResultsProject) then
  begin
    Exit;
  end;
  FResultsProject := AProject;
  FResults.Forget('');
  mFile := ResultsFileOf(AProject);
  if FileExists(mFile) then
  begin
    try
      FResults.LoadJson(TAtlasTextFile.LoadText(mFile));
    except
      on Exception do
        FResults.Forget('');
    end;
  end;
  Inc(FVersion);
end;

procedure TAtlasIdeMutationRun.SaveResults;
var
  mFile: string;
begin
  if FResultsProject = '' then
  begin
    Exit;
  end;
  mFile := ResultsFileOf(FResultsProject);
  try
    ForceDirectories(ExtractFileDir(mFile));
    // UTF-8 ohne BOM wie im Format beschrieben.
    TFile.WriteAllBytes(mFile, TEncoding.UTF8.GetBytes(FResults.ToJson(FResultsProject)));
  except
    on E: Exception do
      FOutput.Say(E.Message);
  end;
end;

function TAtlasIdeMutationRun.MarksOf(const AFileName: string;
  const ALines: TArray<string>): TArray<TAtlasMutationLineMark>;
var
  mModules: IOTAModuleServices;
  mProject: IOTAProject;
begin
  // Ohne Lauf seit dem Start: die Ergebnisse des aktiven Testprojekts.
  if (FResultsProject = '') and Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    mProject := mModules.GetActiveProject;
    if TAtlasIdeTestProjects.IsTestProject(mProject) then
    begin
      LoadResults(mProject.FileName);
    end;
  end;
  Result := FResults.MarksOf(AFileName, ALines);
end;

class function TAtlasIdeMutationRun.StatusText(AStatus: TAtlasMutationStatus; const ABy: string): string;
begin
  case AStatus of
    TAtlasMutationStatus.Killed:
      case TAtlasMutationSteps.KilledText(ABy) of
        // Ohne Bericht: der Exitcode (Absturz).
        TAtlasMutationKilledText.ExitCode:
          Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStatusKilledExit, [ABy]);
        TAtlasMutationKilledText.ByTest:
          Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStatusKilledBy, [ABy]);
      else
        Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationStatusKilled);
      end;
    TAtlasMutationStatus.Survived:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationStatusSurvived);
    TAtlasMutationStatus.TimedOut:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationStatusTimedOut);
    TAtlasMutationStatus.BuildFailed:
      Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationStatusBuildFailed);
  else
    Result := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationStatusInvalid);
  end;
end;

end.
