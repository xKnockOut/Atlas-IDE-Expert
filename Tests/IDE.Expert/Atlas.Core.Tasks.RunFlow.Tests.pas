unit Atlas.Core.Tasks.RunFlow.Tests;

// Tests für den Ablauf der Projektaufgaben gegen die Fälschung des Starters:
// einzelne Läufe, Reihen nacheinander und gleichzeitig, übersprungene
// Aufgaben, Entscheidung vor dem Build, Abbruch, verspätete Enden und ein
// Rückruf, der während des Endes neue Läufe startet.

interface

uses
  System.Generics.Collections,
  DUnitX.TestFramework,
  Atlas.Core.Tasks.RunFlow,
  Atlas.Tests.TaskLauncherFake;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskFlowTests = class
  private
    FFake: TAtlasTaskLauncherFake;
    FLauncher: IAtlasTaskLauncher;
    FNotes: TList<TAtlasTaskFlowNote>;
    FFlow: TAtlasTaskFlow;
    /// <summary>Meldungen als „Art:Name“, durch Komma getrennt.</summary>
    function NoteText: string;
    function NotesOf(AKind: TAtlasTaskFlowNoteKind): TArray<TAtlasTaskFlowNote>;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure SingleRunLaunchesAndEnds;
    [Test]
    procedure SameTaskRunsOncePerProject;
    [Test]
    procedure OnlySingleRunsAreRemembered;
    [Test]
    procedure SequentialBatchStartsOneAfterAnother;
    [Test]
    procedure ParallelBatchStartsAll;
    [Test]
    procedure RefusedTaskIsSkippedWithReason;
    [Test]
    procedure PassedBlockAsksForRebuild;
    [Test]
    procedure FailedBlockStopsTheBuild;
    [Test]
    procedure WarnOnlyReportsAndNeverRebuilds;
    [Test]
    procedure CancelAllDropsWaitingAndRebuild;
    [Test]
    procedure UnknownOrRepeatedEndIsIgnored;
    [Test]
    procedure BatchStartedFromEndKeepsBothApart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.Runs,
  Atlas.Core.Tasks.PreBuild;

const
  cProject = 'C:\p\A.dproj';
  cKey = 'c:\p\a.dproj';
  cKindNames: array[TAtlasTaskFlowNoteKind] of string = ('Started', 'Skipped', 'Ended', 'Blocked', 'Warned',
    'Passed');

function Task(const AName: string): TAtlasTaskDefinition;
begin
  Result := Default(TAtlasTaskDefinition);
  Result.Name := AName;
  Result.Command := 'tool.exe';
end;

function Tasks(const AFirst, ASecond, AThird: string): TAtlasTaskDefinitions;
begin
  Result := nil;
  SetLength(Result, 3);
  Result[0] := Task(AFirst);
  Result[1] := Task(ASecond);
  Result[2] := Task(AThird);
end;

function Modes(AMode: TAtlasTaskBeforeBuild; ACount: Integer): TArray<TAtlasTaskBeforeBuild>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, ACount);
  for mIndex := 0 to ACount - 1 do
  begin
    Result[mIndex] := AMode;
  end;
end;

function Ran(const AName: string; AExitCode: Integer): TAtlasTaskRun;
begin
  Result := Default(TAtlasTaskRun);
  Result.Name := AName;
  Result.Outcome := TAtlasTaskOutcome.Finished;
  Result.ExitCode := AExitCode;
end;

function Target: TAtlasTaskTarget;
begin
  Result := TAtlasTaskTarget.Create(cProject, cKey);
end;

function Compile: TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := cProject;
  Result.Kind := TAtlasCompileKind.Build;
end;

/// <summary>Sammelt die Meldungen in AList; eigene Routine, damit die Referenz nur die Liste einfängt.</summary>
function Collect(AList: TList<TAtlasTaskFlowNote>): TAtlasTaskFlowNoted;
begin
  Result :=
    procedure(const ANote: TAtlasTaskFlowNote)
    begin
      AList.Add(ANote);
    end;
end;

/// <summary>Wie Collect, startet aber beim ersten Ende eine neue Reihe mit „Z“ im Ablauf von ATest.</summary>
function CollectAndStart(ATest: TAtlasTaskFlowTests): TAtlasTaskFlowNoted;
var
  mStarted: Boolean;
begin
  mStarted := False;
  Result :=
    procedure(const ANote: TAtlasTaskFlowNote)
    var
      mZ: TAtlasTaskDefinitions;
    begin
      ATest.FNotes.Add(ANote);
      if (ANote.Kind = TAtlasTaskFlowNoteKind.Ended) and not mStarted then
      begin
        mStarted := True;
        SetLength(mZ, 1);
        mZ[0] := Task('Z');
        ATest.FFlow.RunBatch(Target, mZ, Modes(TAtlasTaskBeforeBuild.Off, 1), False, False);
      end;
    end;
end;

{ TAtlasTaskFlowTests }

procedure TAtlasTaskFlowTests.Setup;
begin
  FFake := TAtlasTaskLauncherFake.Create;
  FLauncher := FFake;
  FNotes := TList<TAtlasTaskFlowNote>.Create;
  FFlow := TAtlasTaskFlow.Create(FLauncher, Collect(FNotes));
end;

procedure TAtlasTaskFlowTests.TearDown;
begin
  FreeAndNil(FFlow);
  FreeAndNil(FNotes);
  FFake := nil;
  FLauncher := nil;
end;

function TAtlasTaskFlowTests.NoteText: string;
var
  mNote: TAtlasTaskFlowNote;
begin
  Result := '';
  for mNote in FNotes do
  begin
    if Result <> '' then
    begin
      Result := Result + ',';
    end;
    Result := Result + cKindNames[mNote.Kind] + ':' + mNote.Name;
  end;
end;

function TAtlasTaskFlowTests.NotesOf(AKind: TAtlasTaskFlowNoteKind): TArray<TAtlasTaskFlowNote>;
var
  mNote: TAtlasTaskFlowNote;
begin
  Result := nil;
  for mNote in FNotes do
  begin
    if mNote.Kind = AKind then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := mNote;
    end;
  end;
end;

procedure TAtlasTaskFlowTests.SingleRunLaunchesAndEnds;
var
  mEnded: TArray<TAtlasTaskFlowNote>;
begin
  Assert.IsTrue(FFlow.Run(Target, Task('Lint')));
  Assert.AreEqual('launch:1:Lint:' + cProject + ':show', FFake.CallText);
  Assert.IsTrue(FFlow.Busy);
  Assert.IsTrue(FFlow.IsRunning(cKey, 'lint'), 'Name ohne Groß-/Kleinschreibung');
  FFlow.Finished(1, Ran('Lint', 0));
  Assert.AreEqual('launch:1:Lint:' + cProject + ':show,release:1', FFake.CallText);
  Assert.AreEqual('Started:Lint,Ended:Lint', NoteText);
  mEnded := NotesOf(TAtlasTaskFlowNoteKind.Ended);
  Assert.AreEqual(1, mEnded[0].Id);
  Assert.AreEqual(cKey, mEnded[0].Key);
  Assert.IsFalse(FFlow.Busy);
  Assert.IsFalse(FFlow.IsRunning(cKey, 'Lint'));
end;

procedure TAtlasTaskFlowTests.SameTaskRunsOncePerProject;
begin
  Assert.IsTrue(FFlow.Run(Target, Task('Lint')));
  Assert.IsFalse(FFlow.Run(Target, Task('LINT')), 'läuft schon');
  Assert.IsTrue(FFlow.Run(TAtlasTaskTarget.Create('C:\p\B.dproj', 'c:\p\b.dproj'), Task('Lint')),
    'anderes Projekt');
  Assert.AreEqual(2, FFake.Calls.Count);
  FFlow.Finished(1, Ran('Lint', 0));
  Assert.IsTrue(FFlow.Run(Target, Task('Lint')), 'nach dem Ende wieder');
end;

procedure TAtlasTaskFlowTests.OnlySingleRunsAreRemembered;
begin
  Assert.AreEqual('', FFlow.LastName);
  FFlow.Run(Target, Task('Lint'));
  FFlow.RunBatch(TAtlasTaskTarget.Create('C:\p\B.dproj', 'c:\p\b.dproj'), Tasks('X', 'Y', 'W'),
    Modes(TAtlasTaskBeforeBuild.Off, 3), False, True);
  Assert.AreEqual('Lint', FFlow.LastName);
  Assert.AreEqual(cProject, FFlow.LastTarget.Project);
end;

procedure TAtlasTaskFlowTests.SequentialBatchStartsOneAfterAnother;
begin
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Off, 3), False, False);
  Assert.AreEqual('launch:2:A:' + cProject + ':show', FFake.CallText, 'Id 1 gehört der Reihe');
  FFlow.Finished(2, Ran('A', 1));
  Assert.AreEqual(3, FFake.Calls.Count);
  Assert.AreEqual('launch:3:B:' + cProject + ':show', FFake.Calls[2]);
  FFlow.Finished(3, Ran('B', 0));
  FFlow.Finished(4, Ran('C', 0));
  Assert.AreEqual('Started:A,Ended:A,Started:B,Ended:B,Started:C,Ended:C', NoteText);
  Assert.IsFalse(FFlow.Busy);
end;

procedure TAtlasTaskFlowTests.ParallelBatchStartsAll;
begin
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Off, 3), False, True);
  Assert.AreEqual(3, FFake.Calls.Count);
  FFlow.Finished(3, Ran('B', 0));
  Assert.IsTrue(FFlow.IsRunning(cKey, 'A'));
  Assert.IsFalse(FFlow.IsRunning(cKey, 'B'));
  Assert.IsTrue(FFlow.IsRunning(cKey, 'C'));
  Assert.AreEqual(4, FFake.Calls.Count, 'nichts nachgestartet');
end;

procedure TAtlasTaskFlowTests.RefusedTaskIsSkippedWithReason;
var
  mSkipped: TArray<TAtlasTaskFlowNote>;
begin
  FFake.Refused.Add('B');
  FFlow.RunBatch(Target, Tasks('B', 'A', 'C'), Modes(TAtlasTaskBeforeBuild.Off, 3), False, False);
  Assert.AreEqual('launch:2:A:' + cProject + ':show', FFake.CallText);
  mSkipped := NotesOf(TAtlasTaskFlowNoteKind.Skipped);
  Assert.AreEqual(1, Integer(Length(mSkipped)));
  Assert.AreEqual('B fehlt', mSkipped[0].Text);
  Assert.IsTrue(mSkipped[0].Loud, 'eigene Reihe: auffallen');
  FNotes.Clear;
  FFlow.PreBuild.Decide(Compile, True, False, 0);
  FFlow.RunBatch(Target, Tasks('B', 'D', 'E'), Modes(TAtlasTaskBeforeBuild.Block, 3), True, True);
  mSkipped := NotesOf(TAtlasTaskFlowNoteKind.Skipped);
  Assert.IsFalse(mSkipped[0].Loud, 'vor dem Build: leise');
end;

procedure TAtlasTaskFlowTests.PassedBlockAsksForRebuild;
var
  mPassed: TArray<TAtlasTaskFlowNote>;
begin
  Assert.IsTrue(FFlow.PreBuild.Decide(Compile, True, False, 0) = TAtlasTaskPreBuildAction.StartAndCancel);
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Block, 3), True, True);
  Assert.AreEqual('launch:2:A:' + cProject, FFake.Calls[0], 'vor dem Build ohne Ausgabe');
  FFlow.Finished(2, Ran('A', 0));
  FFlow.Finished(3, Ran('B', 0));
  Assert.AreEqual(0, Integer(Length(NotesOf(TAtlasTaskFlowNoteKind.Passed))), 'C läuft noch');
  FFlow.Finished(4, Ran('C', 0));
  mPassed := NotesOf(TAtlasTaskFlowNoteKind.Passed);
  Assert.AreEqual(1, Integer(Length(mPassed)));
  Assert.AreEqual(cProject, mPassed[0].Compile.FileName);
  Assert.IsFalse(FFlow.PreBuild.Running);
end;

procedure TAtlasTaskFlowTests.FailedBlockStopsTheBuild;
var
  mBlocked: TArray<TAtlasTaskFlowNote>;
begin
  FFlow.PreBuild.Decide(Compile, True, False, 0);
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Block, 3), True, False);
  FFlow.Finished(2, Ran('A', 0));
  FFlow.Finished(3, Ran('B', 2));
  FFlow.Finished(4, Ran('C', 0));
  mBlocked := NotesOf(TAtlasTaskFlowNoteKind.Blocked);
  Assert.AreEqual(1, Integer(Length(mBlocked)));
  Assert.AreEqual('B', mBlocked[0].Run.Name);
  Assert.AreEqual(0, Integer(Length(NotesOf(TAtlasTaskFlowNoteKind.Passed))));
  Assert.IsFalse(FFlow.PreBuild.Running);
end;

procedure TAtlasTaskFlowTests.WarnOnlyReportsAndNeverRebuilds;
var
  mWarned: TArray<TAtlasTaskFlowNote>;
begin
  Assert.IsTrue(FFlow.PreBuild.Decide(Compile, False, True, 0) = TAtlasTaskPreBuildAction.StartWarn);
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Warn, 3), True, True);
  FFlow.Finished(2, Ran('A', 1));
  FFlow.Finished(3, Ran('B', 0));
  FFlow.Finished(4, Ran('C', 0));
  mWarned := NotesOf(TAtlasTaskFlowNoteKind.Warned);
  Assert.AreEqual(1, Integer(Length(mWarned)));
  Assert.AreEqual('A', mWarned[0].Run.Name);
  Assert.AreEqual(0, Integer(Length(NotesOf(TAtlasTaskFlowNoteKind.Blocked))));
  Assert.AreEqual(0, Integer(Length(NotesOf(TAtlasTaskFlowNoteKind.Passed))));
  Assert.IsFalse(FFlow.PreBuild.Running);
end;

procedure TAtlasTaskFlowTests.CancelAllDropsWaitingAndRebuild;
begin
  FFlow.PreBuild.Decide(Compile, True, False, 0);
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Block, 3), True, False);
  FFlow.Run(Target, Task('Lint'));
  Assert.AreEqual(2, FFlow.CancelAll);
  Assert.IsTrue(FFake.Calls.IndexOf('cancel:2') >= 0);
  Assert.IsTrue(FFake.Calls.IndexOf('cancel:3') >= 0);
  Assert.IsFalse(FFlow.PreBuild.Running, 'aufgegeben');
  FFlow.Finished(2, Ran('A', 0));
  FFlow.Finished(3, Ran('Lint', 0));
  Assert.AreEqual(-1, FFake.Calls.IndexOf('launch:4:B:' + cProject), 'B startet nicht mehr');
  Assert.AreEqual(0, Integer(Length(NotesOf(TAtlasTaskFlowNoteKind.Passed))), 'kein Neubau');
  Assert.IsFalse(FFlow.Busy);
  Assert.AreEqual(0, FFlow.CancelAll, 'nichts mehr zu tun');
end;

procedure TAtlasTaskFlowTests.UnknownOrRepeatedEndIsIgnored;
begin
  FFlow.Finished(99, Ran('X', 0));
  Assert.AreEqual(0, FNotes.Count);
  Assert.AreEqual(0, FFake.Calls.Count);
  FFlow.Run(Target, Task('Lint'));
  FFlow.Finished(1, Ran('Lint', 0));
  FFlow.Finished(1, Ran('Lint', 0));
  Assert.AreEqual('Started:Lint,Ended:Lint', NoteText);
  Assert.AreEqual(2, FFake.Calls.Count, 'einmal freigegeben');
end;

procedure TAtlasTaskFlowTests.BatchStartedFromEndKeepsBothApart;
begin
  FreeAndNil(FFlow);
  FFlow := TAtlasTaskFlow.Create(FLauncher, CollectAndStart(Self));
  FFlow.RunBatch(Target, Tasks('A', 'B', 'C'), Modes(TAtlasTaskBeforeBuild.Off, 3), False, False);
  FFlow.Finished(2, Ran('A', 0));
  Assert.AreEqual('launch:2:A:' + cProject + ':show,release:2,launch:4:Z:' + cProject + ':show,launch:5:B:' +
    cProject + ':show', FFake.CallText, 'neue Reihe im Rückruf, dann weiter mit B');
  FFlow.Finished(4, Ran('Z', 0));
  Assert.IsTrue(FFlow.IsRunning(cKey, 'B'));
  Assert.AreEqual(-1, FFake.Calls.IndexOf('launch:6:C:' + cProject + ':show'), 'Ende von Z startet nicht C');
  FFlow.Finished(5, Ran('B', 0));
  Assert.IsTrue(FFake.Calls.IndexOf('launch:6:C:' + cProject + ':show') >= 0);
end;

end.
