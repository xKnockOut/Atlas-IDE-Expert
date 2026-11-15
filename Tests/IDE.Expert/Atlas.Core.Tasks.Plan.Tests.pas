unit Atlas.Core.Tasks.Plan.Tests;

// Tests für die Entscheidungen des Aufgabenläufers (#900): Plan vor dem
// Build, Abbruch und Start je Entscheidung, Statusfarbe, Menütext und das
// Projekt eines fertigen Laufs.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasTaskPlanTests = class
  public
    /// <summary>Eigenes beforeBuild vor dem globalen, das nur für check gilt; Namen mit Komma.</summary>
    [Test]
    procedure PreBuildTakesOwnModeBeforeGlobal;
    /// <summary>Ohne Aufgaben weder block noch warn; OffModes liefert die gewünschte Zahl.</summary>
    [Test]
    procedure EmptyPlanAndOffModes;
    /// <summary>StartAndCancel und Busy brechen ab, StartWarn und StartAndCancel starten.</summary>
    [Test]
    procedure ActionsCancelAndStart;
    /// <summary>Neutral solange laufend oder ohne Lauf, sonst grün bzw. rot.</summary>
    [Test]
    procedure StatusStateFollowsLastRun;
    /// <summary>Gruppe, Name, letzter Lauf und Taste hinter einem Tabulator.</summary>
    [Test]
    procedure MenuCaptionWithAndWithoutKey;
    /// <summary>Läufe ohne Projekt gehören zum leeren Projekt und heißen für die Hörer ''.</summary>
    [Test]
    procedure ProjectOfFinishedRun;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Tasks.Definitions,
  Atlas.Core.Tasks.PreBuild,
  Atlas.Core.Tasks.Plan,
  Atlas.Core.Tasks.Runs;

function Task(const AName: string; AGroup: TAtlasTaskGroup; AHasOwn: Boolean;
  AOwn: TAtlasTaskBeforeBuild): TAtlasTaskDefinition;
begin
  Result := Default(TAtlasTaskDefinition);
  Result.Name := AName;
  Result.Group := AGroup;
  Result.HasBeforeBuild := AHasOwn;
  Result.BeforeBuild := AOwn;
end;

{ TAtlasTaskPlanTests }

procedure TAtlasTaskPlanTests.PreBuildTakesOwnModeBeforeGlobal;
var
  mTasks: TAtlasTaskDefinitions;
  mPlan: TAtlasTaskPreBuildPlan;
begin
  mTasks := TAtlasTaskDefinitions.Create(
    Task('lint', TAtlasTaskGroup.Check, False, TAtlasTaskBeforeBuild.Off),
    Task('test', TAtlasTaskGroup.Test, True, TAtlasTaskBeforeBuild.Block),
    Task('docs', TAtlasTaskGroup.Other, False, TAtlasTaskBeforeBuild.Off));
  mPlan := TAtlasTaskPlan.PreBuild(mTasks, TAtlasTaskBeforeBuild.Warn);
  Assert.AreEqual(3, Integer(Length(mPlan.Modes)));
  Assert.AreEqual(Ord(TAtlasTaskBeforeBuild.Warn), Ord(mPlan.Modes[0]), 'check folgt dem globalen Wert');
  Assert.AreEqual(Ord(TAtlasTaskBeforeBuild.Block), Ord(mPlan.Modes[1]), 'eigenes beforeBuild zählt');
  Assert.AreEqual(Ord(TAtlasTaskBeforeBuild.Off), Ord(mPlan.Modes[2]), 'andere Gruppen ohne eigenes: aus');
  Assert.IsTrue(mPlan.HasBlock);
  Assert.IsTrue(mPlan.HasWarn, 'alles ohne block zählt als warn');
  Assert.AreEqual('lint, test, docs', mPlan.Names);
  mPlan := TAtlasTaskPlan.PreBuild(TAtlasTaskDefinitions.Create(
    Task('lint', TAtlasTaskGroup.Check, False, TAtlasTaskBeforeBuild.Off)), TAtlasTaskBeforeBuild.Block);
  Assert.IsTrue(mPlan.HasBlock);
  Assert.IsFalse(mPlan.HasWarn);
  Assert.AreEqual('lint', mPlan.Names);
  mTasks := nil;
  mPlan := Default(TAtlasTaskPreBuildPlan);
end;

procedure TAtlasTaskPlanTests.EmptyPlanAndOffModes;
var
  mPlan: TAtlasTaskPreBuildPlan;
  mModes: TArray<TAtlasTaskBeforeBuild>;
  mMode: TAtlasTaskBeforeBuild;
begin
  mPlan := TAtlasTaskPlan.PreBuild(nil, TAtlasTaskBeforeBuild.Block);
  Assert.IsFalse(mPlan.HasBlock);
  Assert.IsFalse(mPlan.HasWarn);
  Assert.AreEqual('', mPlan.Names);
  Assert.AreEqual(0, Integer(Length(mPlan.Modes)));
  mModes := TAtlasTaskPlan.OffModes(3);
  Assert.AreEqual(3, Integer(Length(mModes)));
  for mMode in mModes do
  begin
    Assert.AreEqual(Ord(TAtlasTaskBeforeBuild.Off), Ord(mMode));
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasTaskPlan.OffModes(0))));
  mModes := nil;
  mPlan := Default(TAtlasTaskPreBuildPlan);
end;

procedure TAtlasTaskPlanTests.ActionsCancelAndStart;
begin
  Assert.IsFalse(TAtlasTaskPlan.CancelsCompile(TAtlasTaskPreBuildAction.None));
  Assert.IsFalse(TAtlasTaskPlan.CancelsCompile(TAtlasTaskPreBuildAction.StartWarn));
  Assert.IsTrue(TAtlasTaskPlan.CancelsCompile(TAtlasTaskPreBuildAction.StartAndCancel));
  Assert.IsTrue(TAtlasTaskPlan.CancelsCompile(TAtlasTaskPreBuildAction.Busy));
  Assert.IsFalse(TAtlasTaskPlan.StartsRun(TAtlasTaskPreBuildAction.None));
  Assert.IsTrue(TAtlasTaskPlan.StartsRun(TAtlasTaskPreBuildAction.StartWarn));
  Assert.IsTrue(TAtlasTaskPlan.StartsRun(TAtlasTaskPreBuildAction.StartAndCancel));
  Assert.IsFalse(TAtlasTaskPlan.StartsRun(TAtlasTaskPreBuildAction.Busy), 'laufende Aufgaben starten nicht erneut');
end;

procedure TAtlasTaskPlanTests.StatusStateFollowsLastRun;
var
  mLast: TAtlasTaskLastRun;
begin
  mLast := Default(TAtlasTaskLastRun);
  mLast.Outcome := TAtlasTaskOutcome.Finished;
  Assert.AreEqual(Ord(TAtlasStatusState.Green), Ord(TAtlasTaskPlan.StatusState(False, True, mLast)));
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasTaskPlan.StatusState(True, True, mLast)), 'läuft');
  Assert.AreEqual(Ord(TAtlasStatusState.Neutral), Ord(TAtlasTaskPlan.StatusState(False, False, mLast)), 'nie');
  mLast.ExitCode := 2;
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasTaskPlan.StatusState(False, True, mLast)));
  mLast.ExitCode := 0;
  mLast.Counts.Errors := 1;
  Assert.AreEqual(Ord(TAtlasStatusState.Red), Ord(TAtlasTaskPlan.StatusState(False, True, mLast)), 'Befund');
  mLast := Default(TAtlasTaskLastRun);
end;

procedure TAtlasTaskPlanTests.MenuCaptionWithAndWithoutKey;
begin
  Assert.AreEqual('Prüfung: lint (vor 2 min)', TAtlasTaskPlan.MenuCaption('Prüfung', 'lint', 'vor 2 min', ''));
  Assert.AreEqual('Test: unit (–)'#9'Ctrl+Alt+T', TAtlasTaskPlan.MenuCaption('Test', 'unit', '–', 'Ctrl+Alt+T'));
end;

procedure TAtlasTaskPlanTests.ProjectOfFinishedRun;
const
  cNone = '<ohne>';
begin
  Assert.IsTrue(TAtlasTaskPlan.IsLoadedProject('C:\P\App.dproj', 'c:\p\app.dproj', cNone), 'Groß/klein egal');
  Assert.IsFalse(TAtlasTaskPlan.IsLoadedProject('C:\P\Other.dproj', 'C:\P\App.dproj', cNone));
  Assert.IsTrue(TAtlasTaskPlan.IsLoadedProject(cNone, '', cNone), 'ohne Projekt');
  Assert.IsFalse(TAtlasTaskPlan.IsLoadedProject(cNone, 'C:\P\App.dproj', cNone));
  Assert.AreEqual('', TAtlasTaskPlan.ReportedProject(cNone, cNone));
  Assert.AreEqual('C:\P\App.dproj', TAtlasTaskPlan.ReportedProject('C:\P\App.dproj', cNone));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasTaskPlanTests);

end.
