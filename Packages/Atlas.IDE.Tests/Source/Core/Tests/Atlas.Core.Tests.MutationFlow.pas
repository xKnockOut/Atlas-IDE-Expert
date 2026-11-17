unit Atlas.Core.Tests.MutationFlow;

// Ablauf des Mutationslaufs (#1460) ohne VCL und Open Tools API:
// - Erst laufen die Tests gegen die unveränderte Kopie (sonst ist jedes
//   Ergebnis wertlos), dann je Mutant: Kopie schreiben, Schattenprojekt bauen,
//   Test-EXE ausführen, Ausgang festhalten.
// - Öffnen, Schreiben, Bauen, Ausführen und Schließen des Schattenprojekts
//   übernimmt IAtlasMutationShadowProject: in der IDE das echte
//   Schattenprojekt, in den Tests eine Fälschung.
// - Ein Ende mitten im Lauf (Kopie nicht schreibbar, Build abgelehnt, keine
//   oder nicht startbare Test-EXE) behält wie „Abbrechen“ alles bis dahin
//   Bewertete: Grund, Überlebende, Schlusszeile, Ende Cancelled. Nur vor dem
//   ersten Mutanten (Öffnen, Lauf ohne Mutation) endet er mit Stopped.
// - Eine Test-EXE, die nicht gestartet ist, sagt nichts über den Mutanten;
//   sie zählt nie als „erkannt“, sondern beendet den Lauf.
// - Was zu melden ist, geht als TAtlasMutationNote an OnNote (den Text macht
//   der Aufrufer), das Ende an OnEnded. Bei Finished und Cancelled stehen
//   Jobs, Outcomes und DoneCount in beiden noch bereit (Ergebnisse merken).
// - Rückrufe des Schattenprojekts zählen nur für den Lauf, der sie angestoßen
//   hat; spätere (nach Abbruch oder Ende) verfallen.
// Nur im Hauptthread verwenden; das Schattenprojekt ruft dort zurück.

interface

uses
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Tests.MutationResults,
  Atlas.Core.Tests.MutationPlan;

type
  {$SCOPEDENUMS ON}
  /// <summary>Wie die Test-EXE endete: Completed = gelaufen (Exitcode und Bericht zählen), Cancelled = abgebrochen,
  /// TimedOut = Zeitlimit, NotStarted = gar nicht gelaufen (fehlt, gesperrt, nicht startbar).</summary>
  TAtlasMutationRunState = (Completed, Cancelled, TimedOut, NotStarted);
  {$SCOPEDENUMS OFF}

  /// <summary>Ende des Builds: ASucceeded = übersetzt; AExecutable: die Test-EXE ('' = keine gefunden); AError: Build
  /// gar nicht gelaufen.</summary>
  TAtlasMutationBuilt = reference to procedure(ASucceeded: Boolean; const AExecutable, AError: string);
  /// <summary>Ende der Test-EXE: wie sie endete, Exitcode und XML-Bericht ('' = keiner).</summary>
  TAtlasMutationRan = reference to procedure(AState: TAtlasMutationRunState; AExitCode: Integer; const AXml: string);

  TAtlasMutationRunStates = class
  public
    /// <summary>Zustand der Test-EXE aus dem Ergebnis des Prozessläufers: fehlende oder nicht startbare EXE
    /// (ToolMissing, Failed mit Exitcode -1) und jede Ablehnung ohne Prozess gelten als NotStarted.</summary>
    class function FromRunner(AOutcome: TAtlasVcsOutcome; AExitCode: Integer): TAtlasMutationRunState; static;
  end;

  /// <summary>Das Schattenprojekt neben dem Testprojekt, wie der Ablauf es braucht.</summary>
  IAtlasMutationShadowProject = interface
    ['{4E5D92B9-A5F1-428C-9F07-B64BC3698A39}']
    /// <summary>Anlegen und öffnen; False mit Meldung AProblem.</summary>
    function Open(out AProblem: string): Boolean;
    /// <summary>Name für Meldungen.</summary>
    function Name: string;
    /// <summary>Kopie der Unit mit den Zeilen ALines schreiben; wirft bei Fehler.</summary>
    procedure Write(const ALines: TArray<string>);
    /// <summary>Vollständig bauen; False mit AReason, wenn nicht gebaut wird, sonst kommt ADone.</summary>
    function Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
    /// <summary>Test-EXE AExecutable ausführen; ADone kommt im Hauptthread.</summary>
    procedure Run(const AExecutable: string; const ADone: TAtlasMutationRan);
    /// <summary>Schließen; auch nach gescheitertem Open. Wirft bei Fehler, der Ablauf meldet ihn.</summary>
    procedure Close;
  end;

  /// <summary>Was geprüft wird.</summary>
  TAtlasMutationFlowSource = record
    Jobs: TArray<TAtlasMutationJob>;
    /// <summary>Text der Unit ohne Mutation.</summary>
    Lines: TArray<string>;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Finished: alle Mutanten geprüft; Cancelled: abgebrochen; Stopped: mit Fehlermeldung beendet.</summary>
  TAtlasMutationEnd = (Finished, Cancelled, Stopped);
  /// <summary>Started: Schattenprojekt offen, Lauf ohne Mutation folgt. OpenFailed: Text = Grund. WriteFailed: Text =
  /// Fehler beim Schreiben der Kopie. BuildRefused: Text = Grund. NoExecutable: gebaut, aber keine Test-EXE.
  /// NotStarted: Test-EXE ließ sich nicht starten. BaselineFailed: Lauf ohne Mutation nicht grün (Status, By).
  /// Outcome: Ausgang des Mutanten Position. Survivor: Mutant Position überlebt (am Ende). Cancelled: abgebrochen nach
  /// Done von Total. Finished: Totals. CloseFailed: Text = Fehler beim Schließen.</summary>
  TAtlasMutationNoteKind = (Started, OpenFailed, WriteFailed, BuildRefused, NoExecutable, NotStarted, BaselineFailed,
    Outcome, Survivor, Cancelled, Finished, CloseFailed);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Meldung des Ablaufs; nur die Felder ihrer Art sind gesetzt.</summary>
  TAtlasMutationNote = record
    Kind: TAtlasMutationNoteKind;
    Text: string;
    /// <summary>Name des Schattenprojekts.</summary>
    Shadow: string;
    Status: TAtlasMutationStatus;
    By: string;
    /// <summary>Index in Jobs.</summary>
    Position: Integer;
    Done: Integer;
    Total: Integer;
    Totals: TAtlasMutationTotals;
  end;

  TAtlasMutationNoted = reference to procedure(const ANote: TAtlasMutationNote);
  TAtlasMutationEnded = reference to procedure(AEnd: TAtlasMutationEnd);

  TAtlasMutationFlow = class
  private
    FProject: IAtlasMutationShadowProject;
    FSource: TAtlasMutationFlowSource;
    FOutcomes: TArray<TAtlasMutationOutcome>;
    /// <summary>-1 = Lauf ohne Mutation, sonst Index in Jobs.</summary>
    FPosition: Integer;
    FStartedAt: UInt64;
    FActive: Boolean;
    FCancelled: Boolean;
    /// <summary>Zählt die Läufe; Rückrufe eines früheren verfallen.</summary>
    FRun: Integer;
    FOnNote: TAtlasMutationNoted;
    FOnEnded: TAtlasMutationEnded;
    procedure Note(const ANote: TAtlasMutationNote);
    procedure NoteText(AKind: TAtlasMutationNoteKind; const AText: string);
    procedure CloseProject;
    procedure Step;
    procedure Rate(AStatus: TAtlasMutationStatus; const ABy: string);
    procedure Advance;
    procedure Finish(ACancelled: Boolean);
    procedure StopWith(AKind: TAtlasMutationNoteKind; const AText: string);
    procedure Ended(AEnd: TAtlasMutationEnd);
    procedure Clear;
    function Done: Integer;
  public
    /// <summary>Lauf über ASource mit dem Schattenprojekt AProject; ohne Jobs nichts.</summary>
    procedure Start(const AProject: IAtlasMutationShadowProject; const ASource: TAtlasMutationFlowSource);
    /// <summary>Nach dem aktuellen Schritt beenden.</summary>
    procedure Cancel;
    /// <summary>Ohne OnEnded schließen (Entladen).</summary>
    procedure Abandon;
    /// <summary>Rückrufe des Schattenprojekts zum Lauf ARun.</summary>
    procedure Built(ARun: Integer; ASucceeded: Boolean; const AExecutable, AError: string);
    procedure Ran(ARun: Integer; AState: TAtlasMutationRunState; AExitCode: Integer; const AXml: string);
    property Active: Boolean read FActive;
    property Jobs: TArray<TAtlasMutationJob> read FSource.Jobs;
    property Outcomes: TArray<TAtlasMutationOutcome> read FOutcomes;
    /// <summary>Anzahl fertig geprüfter Mutanten.</summary>
    property DoneCount: Integer read Done;
    property OnNote: TAtlasMutationNoted read FOnNote write FOnNote;
    property OnEnded: TAtlasMutationEnded read FOnEnded write FOnEnded;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Diagnostics.Deadline,
  Atlas.Core.Tests.Mutants;

/// <summary>Rückruf des Builds an AFlow für den Lauf ARun; eigene Routine: fängt nur, was sie braucht.</summary>
function BuiltProc(AFlow: TAtlasMutationFlow; ARun: Integer): TAtlasMutationBuilt;
var
  mFlow: TAtlasMutationFlow;
  mRun: Integer;
begin
  mFlow := AFlow;
  mRun := ARun;
  Result :=
    procedure(ASucceeded: Boolean; const AExecutable, AError: string)
    begin
      mFlow.Built(mRun, ASucceeded, AExecutable, AError);
    end;
end;

/// <summary>Rückruf der Test-EXE an AFlow für den Lauf ARun.</summary>
function RanProc(AFlow: TAtlasMutationFlow; ARun: Integer): TAtlasMutationRan;
var
  mFlow: TAtlasMutationFlow;
  mRun: Integer;
begin
  mFlow := AFlow;
  mRun := ARun;
  Result :=
    procedure(AState: TAtlasMutationRunState; AExitCode: Integer; const AXml: string)
    begin
      mFlow.Ran(mRun, AState, AExitCode, AXml);
    end;
end;

{ TAtlasMutationRunStates }

class function TAtlasMutationRunStates.FromRunner(AOutcome: TAtlasVcsOutcome;
  AExitCode: Integer): TAtlasMutationRunState;
begin
  case AOutcome of
    TAtlasVcsOutcome.Ok:
      Result := TAtlasMutationRunState.Completed;
    // Failed mit echtem Exitcode: gelaufen, aber zu viel Ausgabe; -1: Pipes oder Start gescheitert.
    TAtlasVcsOutcome.Failed:
      if AExitCode = -1 then
      begin
        Result := TAtlasMutationRunState.NotStarted;
      end
      else
      begin
        Result := TAtlasMutationRunState.Completed;
      end;
    TAtlasVcsOutcome.Cancelled:
      Result := TAtlasMutationRunState.Cancelled;
    TAtlasVcsOutcome.TimedOut:
      Result := TAtlasMutationRunState.TimedOut;
  else
    // ToolMissing, MainThread und alles, was keinen Prozess gestartet hat.
    Result := TAtlasMutationRunState.NotStarted;
  end;
end;

/// <summary>Leere Meldung der Art AKind.</summary>
function NoteOf(AKind: TAtlasMutationNoteKind): TAtlasMutationNote;
begin
  Result := Default(TAtlasMutationNote);
  Result.Kind := AKind;
end;

{ TAtlasMutationFlow }

procedure TAtlasMutationFlow.Note(const ANote: TAtlasMutationNote);
var
  mNote: TAtlasMutationNote;
begin
  mNote := ANote;
  mNote.Total := Length(FSource.Jobs);
  if FProject <> nil then
  begin
    mNote.Shadow := FProject.Name;
  end;
  if Assigned(FOnNote) then
  begin
    FOnNote(mNote);
  end;
end;

procedure TAtlasMutationFlow.NoteText(AKind: TAtlasMutationNoteKind; const AText: string);
var
  mNote: TAtlasMutationNote;
begin
  mNote := NoteOf(AKind);
  mNote.Text := AText;
  Note(mNote);
end;

procedure TAtlasMutationFlow.CloseProject;
begin
  try
    FProject.Close;
  except
    on E: Exception do
      NoteText(TAtlasMutationNoteKind.CloseFailed, E.Message);
  end;
end;

procedure TAtlasMutationFlow.Start(const AProject: IAtlasMutationShadowProject;
  const ASource: TAtlasMutationFlowSource);
var
  mProject: IAtlasMutationShadowProject;
  mProblem: string;
begin
  if FActive or (Length(ASource.Jobs) = 0) then
  begin
    Exit;
  end;
  Inc(FRun);
  FProject := AProject;
  FSource := ASource;
  FOutcomes := nil;
  SetLength(FOutcomes, Length(FSource.Jobs));
  FPosition := -1;
  FCancelled := False;
  FActive := True;
  // Eigene Referenz: Antwortet das Schattenprojekt sofort, kann der Lauf darin enden und FProject freigeben.
  mProject := FProject;
  if not mProject.Open(mProblem) then
  begin
    StopWith(TAtlasMutationNoteKind.OpenFailed, mProblem);
    Exit;
  end;
  Note(NoteOf(TAtlasMutationNoteKind.Started));
  Step;
end;

procedure TAtlasMutationFlow.Step;
var
  mProject: IAtlasMutationShadowProject;
  mLines: TArray<string>;
  mReason: string;
begin
  mProject := FProject;
  if FCancelled then
  begin
    Finish(True);
    Exit;
  end;
  mLines := FSource.Lines;
  if (FPosition >= 0) and not TAtlasMutants.Apply(FSource.Lines, FSource.Jobs[FPosition].Mutant, mLines) then
  begin
    Rate(TAtlasMutationStatus.Invalid, '');
    Exit;
  end;
  try
    mProject.Write(mLines);
  except
    on E: Exception do
    begin
      StopWith(TAtlasMutationNoteKind.WriteFailed, E.Message);
      Exit;
    end;
  end;
  FStartedAt := TAtlasTicks.Now;
  if not mProject.Build(BuiltProc(Self, FRun), mReason) then
  begin
    StopWith(TAtlasMutationNoteKind.BuildRefused, mReason);
  end;
end;

procedure TAtlasMutationFlow.Built(ARun: Integer; ASucceeded: Boolean; const AExecutable, AError: string);
var
  mProject: IAtlasMutationShadowProject;
begin
  if not FActive or (ARun <> FRun) then
  begin
    Exit;
  end;
  if AError <> '' then
  begin
    StopWith(TAtlasMutationNoteKind.BuildRefused, AError);
    Exit;
  end;
  if not ASucceeded then
  begin
    Rate(TAtlasMutationStatus.BuildFailed, '');
    Exit;
  end;
  if AExecutable = '' then
  begin
    StopWith(TAtlasMutationNoteKind.NoExecutable, '');
    Exit;
  end;
  mProject := FProject;
  mProject.Run(AExecutable, RanProc(Self, FRun));
end;

procedure TAtlasMutationFlow.Ran(ARun: Integer; AState: TAtlasMutationRunState; AExitCode: Integer;
  const AXml: string);
var
  mBy: string;
  mStatus: TAtlasMutationStatus;
begin
  if not FActive or (ARun <> FRun) then
  begin
    Exit;
  end;
  if AState = TAtlasMutationRunState.Cancelled then
  begin
    Finish(True);
    Exit;
  end;
  // Nicht gestartet ist nicht „erkannt“: Der Exitcode -1 stammt dann vom Läufer, nicht von den Tests.
  if AState = TAtlasMutationRunState.NotStarted then
  begin
    StopWith(TAtlasMutationNoteKind.NotStarted, '');
    Exit;
  end;
  mStatus := TAtlasMutationPlan.StatusOf(AState = TAtlasMutationRunState.TimedOut, AExitCode, AXml, mBy);
  Rate(mStatus, mBy);
end;

procedure TAtlasMutationFlow.Rate(AStatus: TAtlasMutationStatus; const ABy: string);
var
  mNote: TAtlasMutationNote;
begin
  mNote := Default(TAtlasMutationNote);
  mNote.Status := AStatus;
  mNote.By := ABy;
  mNote.Position := FPosition;
  // Rot, nicht gebaut oder nicht bewertbar schon ohne Mutation: Jeder Mutant wäre „erkannt“.
  if TAtlasMutationSteps.BaselineFailed(FPosition, AStatus) then
  begin
    mNote.Kind := TAtlasMutationNoteKind.BaselineFailed;
    Note(mNote);
    StopWith(TAtlasMutationNoteKind.BaselineFailed, '');
    Exit;
  end;
  if FPosition >= 0 then
  begin
    FOutcomes[FPosition] := TAtlasMutationSteps.OutcomeOf(FSource.Jobs[FPosition], AStatus, ABy,
      Integer(TAtlasTicks.SinceMs(FStartedAt)));
    mNote.Kind := TAtlasMutationNoteKind.Outcome;
    Note(mNote);
  end;
  Advance;
end;

procedure TAtlasMutationFlow.Advance;
begin
  Inc(FPosition);
  if FPosition > High(FSource.Jobs) then
  begin
    Finish(False);
    Exit;
  end;
  Step;
end;

procedure TAtlasMutationFlow.Finish(ACancelled: Boolean);
var
  mNote: TAtlasMutationNote;
  mIndex: Integer;
begin
  if not FActive then
  begin
    Exit;
  end;
  CloseProject;
  for mIndex in TAtlasMutationSteps.Survivors(FOutcomes, Done) do
  begin
    mNote := NoteOf(TAtlasMutationNoteKind.Survivor);
    mNote.Position := mIndex;
    Note(mNote);
  end;
  if ACancelled then
  begin
    mNote := NoteOf(TAtlasMutationNoteKind.Cancelled);
    mNote.Done := Done;
    Note(mNote);
  end;
  mNote := NoteOf(TAtlasMutationNoteKind.Finished);
  mNote.Done := Done;
  mNote.Totals := TAtlasMutationSteps.Totals(FOutcomes, Done);
  Note(mNote);
  if ACancelled then
  begin
    Ended(TAtlasMutationEnd.Cancelled);
  end
  else
  begin
    Ended(TAtlasMutationEnd.Finished);
  end;
end;

procedure TAtlasMutationFlow.StopWith(AKind: TAtlasMutationNoteKind; const AText: string);
begin
  // BaselineFailed hat Rate schon gemeldet.
  if AKind <> TAtlasMutationNoteKind.BaselineFailed then
  begin
    NoteText(AKind, AText);
  end;
  // Mitten im Lauf (nach dem Lauf ohne Mutation): Was bis hierher bewertet ist, zählt wie nach „Abbrechen“.
  if FActive and (FPosition >= 0) then
  begin
    Finish(True);
    Exit;
  end;
  if FActive then
  begin
    CloseProject;
  end;
  Ended(TAtlasMutationEnd.Stopped);
end;

procedure TAtlasMutationFlow.Ended(AEnd: TAtlasMutationEnd);
begin
  FActive := False;
  // Rückrufe dieses Laufs verfallen ab jetzt.
  Inc(FRun);
  if Assigned(FOnEnded) then
  begin
    FOnEnded(AEnd);
  end;
  Clear;
end;

procedure TAtlasMutationFlow.Clear;
begin
  FProject := nil;
  FSource := Default(TAtlasMutationFlowSource);
  FOutcomes := nil;
  FPosition := -1;
end;

procedure TAtlasMutationFlow.Cancel;
begin
  if FActive then
  begin
    FCancelled := True;
  end;
end;

procedure TAtlasMutationFlow.Abandon;
begin
  if FActive then
  begin
    FActive := False;
    Inc(FRun);
    CloseProject;
  end;
  Clear;
end;

function TAtlasMutationFlow.Done: Integer;
begin
  Result := TAtlasMutationSteps.Done(FPosition);
end;

end.
