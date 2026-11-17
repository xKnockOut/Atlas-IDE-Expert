unit Atlas.Core.Tasks.RunFlow;

// Ablauf der Projektaufgaben (#590) ohne VCL und Open Tools API:
// - Einzelne Läufe und Reihen („Alle Prüfungen“, Aufgaben vor dem Build).
//   Eine Reihe startet nacheinander oder gleichzeitig; eine Aufgabe, die der
//   Starter ablehnt (Refuses, etwa fehlender Kommandozeilen-Compiler), wird
//   mit Grund übersprungen. Läuft dieselbe Aufgabe im selben Projekt schon,
//   startet sie nicht noch einmal.
// - Ist eine Reihe vor dem Build fertig, entscheidet TAtlasTaskGate über
//   Abbruch; bestandene block-Läufe melden Passed (neu bauen).
// - Prozess, Thread und Ausgabe übernimmt IAtlasTaskLauncher: in der IDE ein
//   Thread je Lauf, in den Tests eine Fälschung. Das Ende eines Laufs meldet
//   der Aufrufer mit Finished im Hauptthread.
// - Was zu melden oder nachzuführen ist, geht als TAtlasTaskFlowNote an den
//   Rückruf; die Texte macht der Aufrufer.
// Nur im Hauptthread verwenden.

interface

uses
  System.Generics.Collections,
  Atlas.Core.Build.Events,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.PreBuild;

type
  /// <summary>Startet und beendet die Prozesse der Läufe.</summary>
  IAtlasTaskLauncher = interface
    ['{86D5C598-12BC-476D-AA52-9D4C01ED9763}']
    /// <summary>Kann ATask hier gar nicht laufen? AReason nennt den Grund.</summary>
    function Refuses(const ATask: TAtlasTaskDefinition; out AReason: string): Boolean;
    /// <summary>ATask für AProject als Lauf AId starten; AShow: Ausgabe zeigen. Das Ende kommt später über
    /// TAtlasTaskFlow.Finished, auch wenn der Prozess nicht startet.</summary>
    procedure Launch(AId: Integer; const AProject: string; const ATask: TAtlasTaskDefinition; AShow: Boolean);
    /// <summary>Lauf AId abbrechen; sein Ende kommt wie sonst.</summary>
    procedure Cancel(AId: Integer);
    /// <summary>Lauf AId ist fertig gemeldet: aufräumen.</summary>
    procedure Release(AId: Integer);
  end;

  /// <summary>Projekt eines Laufs: Datei für den Starter ('' ohne Projekt) und Schlüssel für Verlauf und
  /// „läuft schon“.</summary>
  TAtlasTaskTarget = record
    Project: string;
    Key: string;
    class function Create(const AProject, AKey: string): TAtlasTaskTarget; static;
  end;

  {$SCOPEDENUMS ON}
  /// <summary>Started: Lauf Name gestartet. Skipped: Aufgabe einer Reihe übersprungen (Text, Loud). Ended: Lauf Id
  /// fertig (Key, Run). Blocked/Warned: Lauf Run hält den Build an bzw. warnt. Passed: Prüfungen vor dem Build
  /// bestanden, Compile neu bauen.</summary>
  TAtlasTaskFlowNoteKind = (Started, Skipped, Ended, Blocked, Warned, Passed);
  {$SCOPEDENUMS OFF}

  /// <summary>Eine Meldung des Ablaufs; nur die Felder ihrer Art sind gesetzt.</summary>
  TAtlasTaskFlowNote = record
    Kind: TAtlasTaskFlowNoteKind;
    Id: Integer;
    Name: string;
    Key: string;
    Text: string;
    /// <summary>Meldung soll auffallen (Meldungsfenster zeigen).</summary>
    Loud: Boolean;
    Run: TAtlasTaskRun;
    Compile: TAtlasCompileProject;
  end;

  TAtlasTaskFlowNoted = reference to procedure(const ANote: TAtlasTaskFlowNote);

  TAtlasTaskFlow = class
  private type
    TJob = record
      Id: Integer;
      Name: string;
      Key: string;
      /// <summary>Reihe des Laufs; 0 = einzeln.</summary>
      Batch: Integer;
      Mode: TAtlasTaskBeforeBuild;
    end;

    TBatch = class
    public
      Id: Integer;
      Target: TAtlasTaskTarget;
      PreBuild: Boolean;
      Parallel: Boolean;
      Waiting: TAtlasTaskDefinitions;
      WaitingModes: TArray<TAtlasTaskBeforeBuild>;
      Running: Integer;
      Entries: TArray<TAtlasTaskGateEntry>;
    end;
  private
    FLauncher: IAtlasTaskLauncher;
    FOnNote: TAtlasTaskFlowNoted;
    FPreBuild: TAtlasTaskPreBuild;
    FJobs: TArray<TJob>;
    FBatches: TObjectList<TBatch>;
    FNextId: Integer;
    FLast: TAtlasTaskTarget;
    FLastName: string;
    procedure Note(const ANote: TAtlasTaskFlowNote);
    procedure NoteRun(AKind: TAtlasTaskFlowNoteKind; const ARun: TAtlasTaskRun);
    function JobIndex(AId: Integer): Integer;
    function FindBatch(AId: Integer): TBatch;
    function Start(const ATarget: TAtlasTaskTarget; const ATask: TAtlasTaskDefinition; ABatch: Integer;
      AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
    procedure StartNextOf(ABatch: TBatch);
    procedure BatchDone(ABatch: TBatch);
  public
    /// <summary>ALauncher startet die Prozesse; AOnNote bekommt jede Meldung.</summary>
    constructor Create(const ALauncher: IAtlasTaskLauncher; const AOnNote: TAtlasTaskFlowNoted);
    /// <summary>Gibt den Starter frei (der seine Läufe beendet); ein Lauf vor dem Build gilt als aufgegeben.</summary>
    destructor Destroy; override;
    /// <summary>Läuft AName im Projekt AKey?</summary>
    function IsRunning(const AKey, AName: string): Boolean;
    /// <summary>Läuft überhaupt etwas?</summary>
    function Busy: Boolean;
    /// <summary>Einzelner Lauf (merkt ihn für „wiederholen“); False, wenn er schon läuft.</summary>
    function Run(const ATarget: TAtlasTaskTarget; const ATask: TAtlasTaskDefinition): Boolean;
    /// <summary>Reihe ATasks mit den Modi AModes (je Aufgabe); APreBuild: vor dem Build (Ausgabe nicht zeigen,
    /// am Ende entscheiden); AParallel: alle zugleich statt nacheinander.</summary>
    procedure RunBatch(const ATarget: TAtlasTaskTarget; const ATasks: TAtlasTaskDefinitions;
      const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild, AParallel: Boolean);
    /// <summary>Lauf AId ist mit ARun zu Ende (Hauptthread); unbekannte Läufe verfallen.</summary>
    procedure Finished(AId: Integer; const ARun: TAtlasTaskRun);
    /// <summary>Alle Läufe abbrechen; wartende Aufgaben der Reihen starten nicht mehr, ein Lauf vor dem Build baut
    /// nicht neu. Ergebnis: Zahl der abgebrochenen Läufe.</summary>
    function CancelAll: Integer;
    /// <summary>Entscheidung vor dem Build (Freischein, „läuft schon“).</summary>
    property PreBuild: TAtlasTaskPreBuild read FPreBuild;
    /// <summary>Zuletzt einzeln gestartete Aufgabe ('' = keine).</summary>
    property LastName: string read FLastName;
    property LastTarget: TAtlasTaskTarget read FLast;
  end;

implementation

uses
  System.SysUtils,
  System.Classes;

{ TAtlasTaskTarget }

class function TAtlasTaskTarget.Create(const AProject, AKey: string): TAtlasTaskTarget;
begin
  Result.Project := AProject;
  Result.Key := AKey;
end;

{ TAtlasTaskFlow }

constructor TAtlasTaskFlow.Create(const ALauncher: IAtlasTaskLauncher; const AOnNote: TAtlasTaskFlowNoted);
begin
  inherited Create;
  FLauncher := ALauncher;
  FOnNote := AOnNote;
  FPreBuild := TAtlasTaskPreBuild.Create;
  FBatches := TObjectList<TBatch>.Create(True);
end;

destructor TAtlasTaskFlow.Destroy;
begin
  FOnNote := nil;
  FLauncher := nil;
  FJobs := nil;
  FreeAndNil(FBatches);
  if FPreBuild <> nil then
  begin
    FPreBuild.Abandon;
  end;
  FreeAndNil(FPreBuild);
  inherited Destroy;
end;

procedure TAtlasTaskFlow.Note(const ANote: TAtlasTaskFlowNote);
begin
  if Assigned(FOnNote) then
  begin
    FOnNote(ANote);
  end;
end;

procedure TAtlasTaskFlow.NoteRun(AKind: TAtlasTaskFlowNoteKind; const ARun: TAtlasTaskRun);
var
  mNote: TAtlasTaskFlowNote;
begin
  mNote := Default(TAtlasTaskFlowNote);
  mNote.Kind := AKind;
  mNote.Name := ARun.Name;
  mNote.Run := ARun;
  Note(mNote);
end;

function TAtlasTaskFlow.JobIndex(AId: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FJobs) do
  begin
    if FJobs[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasTaskFlow.FindBatch(AId: Integer): TBatch;
var
  mBatch: TBatch;
begin
  for mBatch in FBatches do
  begin
    if mBatch.Id = AId then
    begin
      Exit(mBatch);
    end;
  end;
  Result := nil;
end;

function TAtlasTaskFlow.IsRunning(const AKey, AName: string): Boolean;
var
  mJob: TJob;
begin
  for mJob in FJobs do
  begin
    if SameText(mJob.Name, AName) and SameText(mJob.Key, AKey) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function TAtlasTaskFlow.Busy: Boolean;
begin
  Result := Length(FJobs) > 0;
end;

function TAtlasTaskFlow.Start(const ATarget: TAtlasTaskTarget; const ATask: TAtlasTaskDefinition; ABatch: Integer;
  AMode: TAtlasTaskBeforeBuild; AShow: Boolean): Boolean;
var
  mJob: TJob;
  mNote: TAtlasTaskFlowNote;
begin
  if IsRunning(ATarget.Key, ATask.Name) then
  begin
    Exit(False);
  end;
  Inc(FNextId);
  mJob.Id := FNextId;
  mJob.Name := ATask.Name;
  mJob.Key := ATarget.Key;
  mJob.Batch := ABatch;
  mJob.Mode := AMode;
  SetLength(FJobs, Length(FJobs) + 1);
  FJobs[High(FJobs)] := mJob;
  FLauncher.Launch(mJob.Id, ATarget.Project, ATask, AShow);
  if ABatch = 0 then
  begin
    FLast := ATarget;
    FLastName := ATask.Name;
  end;
  mNote := Default(TAtlasTaskFlowNote);
  mNote.Kind := TAtlasTaskFlowNoteKind.Started;
  mNote.Id := mJob.Id;
  mNote.Name := ATask.Name;
  mNote.Key := ATarget.Key;
  Note(mNote);
  Result := True;
end;

function TAtlasTaskFlow.Run(const ATarget: TAtlasTaskTarget; const ATask: TAtlasTaskDefinition): Boolean;
begin
  Result := Start(ATarget, ATask, 0, TAtlasTaskBeforeBuild.Off, True);
end;

procedure TAtlasTaskFlow.RunBatch(const ATarget: TAtlasTaskTarget; const ATasks: TAtlasTaskDefinitions;
  const AModes: TArray<TAtlasTaskBeforeBuild>; APreBuild, AParallel: Boolean);
var
  mBatch: TBatch;
begin
  Inc(FNextId);
  mBatch := TBatch.Create;
  mBatch.Id := FNextId;
  mBatch.Target := ATarget;
  mBatch.PreBuild := APreBuild;
  mBatch.Parallel := AParallel;
  mBatch.Waiting := Copy(ATasks);
  mBatch.WaitingModes := Copy(AModes);
  FBatches.Add(mBatch);
  StartNextOf(mBatch);
end;

procedure TAtlasTaskFlow.StartNextOf(ABatch: TBatch);
var
  mTask: TAtlasTaskDefinition;
  mMode: TAtlasTaskBeforeBuild;
  mNote: TAtlasTaskFlowNote;
begin
  while Length(ABatch.Waiting) > 0 do
  begin
    mTask := ABatch.Waiting[0];
    mMode := TAtlasTaskBeforeBuild.Off;
    if Length(ABatch.WaitingModes) > 0 then
    begin
      mMode := ABatch.WaitingModes[0];
      Delete(ABatch.WaitingModes, 0, 1);
    end;
    Delete(ABatch.Waiting, 0, 1);
    mNote := Default(TAtlasTaskFlowNote);
    if FLauncher.Refuses(mTask, mNote.Text) then
    begin
      mNote.Kind := TAtlasTaskFlowNoteKind.Skipped;
      mNote.Name := mTask.Name;
      mNote.Key := ABatch.Target.Key;
      mNote.Loud := not ABatch.PreBuild;
      Note(mNote);
      Continue;
    end;
    if Start(ABatch.Target, mTask, ABatch.Id, mMode, not ABatch.PreBuild) then
    begin
      Inc(ABatch.Running);
      if not ABatch.Parallel then
      begin
        Exit;
      end;
    end;
  end;
  if ABatch.Running = 0 then
  begin
    BatchDone(ABatch);
  end;
end;

procedure TAtlasTaskFlow.BatchDone(ABatch: TBatch);
var
  mDecision: TAtlasTaskGateDecision;
  mRun: TAtlasTaskRun;
  mProject: TAtlasCompileProject;
  mNote: TAtlasTaskFlowNote;
begin
  if not ABatch.PreBuild then
  begin
    FBatches.Remove(ABatch);
    Exit;
  end;
  mDecision := TAtlasTaskGate.Decide(ABatch.Entries);
  FBatches.Remove(ABatch);
  for mRun in mDecision.Blocking do
  begin
    NoteRun(TAtlasTaskFlowNoteKind.Blocked, mRun);
  end;
  for mRun in mDecision.Warnings do
  begin
    NoteRun(TAtlasTaskFlowNoteKind.Warned, mRun);
  end;
  mProject := FPreBuild.Project;
  if not FPreBuild.Finish(not mDecision.Block, Int64(TThread.GetTickCount64)) then
  begin
    Exit;
  end;
  mNote := Default(TAtlasTaskFlowNote);
  mNote.Kind := TAtlasTaskFlowNoteKind.Passed;
  mNote.Compile := mProject;
  Note(mNote);
end;

procedure TAtlasTaskFlow.Finished(AId: Integer; const ARun: TAtlasTaskRun);
var
  mIndex: Integer;
  mJob: TJob;
  mBatch: TBatch;
  mEntry: TAtlasTaskGateEntry;
  mNote: TAtlasTaskFlowNote;
begin
  mIndex := JobIndex(AId);
  if mIndex < 0 then
  begin
    Exit;
  end;
  mJob := FJobs[mIndex];
  Delete(FJobs, mIndex, 1);
  FLauncher.Release(AId);
  mNote := Default(TAtlasTaskFlowNote);
  mNote.Kind := TAtlasTaskFlowNoteKind.Ended;
  mNote.Id := AId;
  mNote.Name := mJob.Name;
  mNote.Key := mJob.Key;
  mNote.Run := ARun;
  Note(mNote);
  if mJob.Batch = 0 then
  begin
    Exit;
  end;
  // Nach dem Rückruf neu suchen: Er kann Reihen gestartet oder abgebrochen haben.
  mBatch := FindBatch(mJob.Batch);
  if mBatch = nil then
  begin
    Exit;
  end;
  mEntry.Mode := mJob.Mode;
  mEntry.Run := ARun;
  SetLength(mBatch.Entries, Length(mBatch.Entries) + 1);
  mBatch.Entries[High(mBatch.Entries)] := mEntry;
  Dec(mBatch.Running);
  StartNextOf(mBatch);
end;

function TAtlasTaskFlow.CancelAll: Integer;
var
  mJobs: TArray<TJob>;
  mJob: TJob;
  mBatch: TBatch;
begin
  Result := 0;
  mJobs := Copy(FJobs);
  for mJob in mJobs do
  begin
    FLauncher.Cancel(mJob.Id);
    Inc(Result);
  end;
  // Wartende Aufgaben einer Reihe starten nicht mehr; ein abgebrochener Lauf vor dem Build baut nicht neu.
  for mBatch in FBatches do
  begin
    mBatch.Waiting := nil;
    mBatch.WaitingModes := nil;
  end;
  if FPreBuild.Running then
  begin
    FPreBuild.Abandon;
  end;
end;

end.
