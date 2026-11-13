unit Atlas.Core.Build.RunningProgram.Tests;

// Tests für „Laufendes Programm vor dem Build beenden“ (#551) mit gefälschter Prozessliste, ohne IDE.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Build')]
  TAtlasRunningProgramTests = class
  public
    /// <summary>Modus aus dem Text: Groß-/Kleinschreibung egal, Unbekanntes = ask; dieselben Namen wie die
    /// Einstellungen (Base kennt das Modul nicht).</summary>
    [Test]
    procedure ModesMatchSettings;
    /// <summary>Gleicher Pfad unabhängig von Schreibweise und Trennzeichen; leerer Pfad passt nie.</summary>
    [Test]
    procedure ComparesFullPaths;
    /// <summary>ask fragt, always beendet, never tut nichts.</summary>
    [Test]
    procedure FollowsMode;
    /// <summary>Prozesse im Debugger der IDE und die IDE selbst bleiben unberührt.</summary>
    [Test]
    procedure IgnoresDebuggedProcesses;
    /// <summary>Gleicher Programmname in anderem Ordner zählt nicht.</summary>
    [Test]
    procedure IgnoresOtherFolders;
    /// <summary>Syntaxprüfung, Bereinigen und Hintergrundprüfungen von Atlas: nichts.</summary>
    [Test]
    procedure SkipsRunsWithoutOutput;
    /// <summary>Auftrag eines KI-Assistenten: keine Rückfrage, nur always beendet.</summary>
    [Test]
    procedure AssistantBuildsDoNotAsk;
    /// <summary>Package: nur ein Hinweis mit den Prozessen, auch mit always.</summary>
    [Test]
    procedure PackagesOnlyNotice;
    /// <summary>Namen der Prozesse für Rückfrage und Hinweis, jeder einmal.</summary>
    [Test]
    procedure NamesEachProcessOnce;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.RunningProgram,
  Atlas.Core.Settings.Plugin.Store;

const
  cExe = 'C:\Projekte\Demo\Win32\Debug\AtlasDemo.exe';
  cOwnPid = 4;

function Project(const AOutput: string; AKind: TAtlasCompileKind = TAtlasCompileKind.Make): TAtlasCompileProject;
begin
  Result := Default(TAtlasCompileProject);
  Result.FileName := 'C:\Projekte\Demo\AtlasDemo.dproj';
  Result.OutputFile := AOutput;
  Result.Kind := AKind;
end;

function Running: TArray<TAtlasRunningProcess>;
begin
  Result := [TAtlasRunningProcess.Create(cOwnPid, 'C:\Program Files\Studio\bin\bds.exe', 'bds.exe'),
    TAtlasRunningProcess.Create(100, 'c:/projekte/demo/win32/debug/atlasdemo.EXE', 'AtlasDemo.exe'),
    TAtlasRunningProcess.Create(200, 'C:\Windows\explorer.exe', 'explorer.exe')];
end;

procedure TAtlasRunningProgramTests.ModesMatchSettings;
var
  mMode: TAtlasStopRunningMode;
begin
  Assert.AreEqual(Ord(TAtlasStopRunningMode.Always), Ord(TAtlasRunningProgram.ModeOf(' ALWAYS ')));
  Assert.AreEqual(Ord(TAtlasStopRunningMode.Never), Ord(TAtlasRunningProgram.ModeOf('never')));
  Assert.AreEqual(Ord(TAtlasStopRunningMode.Ask), Ord(TAtlasRunningProgram.ModeOf('')));
  Assert.AreEqual(Ord(TAtlasStopRunningMode.Ask), Ord(TAtlasRunningProgram.ModeOf('immer')));
  Assert.AreEqual(Integer(Length(cStopRunningProgramNames)), Ord(High(TAtlasStopRunningMode)) + 1);
  for mMode := Low(TAtlasStopRunningMode) to High(TAtlasStopRunningMode) do
  begin
    Assert.AreEqual(TAtlasRunningProgram.cModeNames[mMode], cStopRunningProgramNames[Ord(mMode)]);
  end;
end;

procedure TAtlasRunningProgramTests.ComparesFullPaths;
begin
  Assert.IsTrue(TAtlasRunningProgram.SamePath(cExe, ' c:/PROJEKTE/demo/Win32/Debug/atlasdemo.exe '));
  Assert.IsFalse(TAtlasRunningProgram.SamePath(cExe, 'C:\Projekte\Demo\Win64\Debug\AtlasDemo.exe'));
  Assert.IsFalse(TAtlasRunningProgram.SamePath('', ''), 'leerer Pfad');
  Assert.IsTrue(TAtlasRunningProgram.IsPackage('C:\Bpl\Atlas.IDE.Base.BPL'));
  Assert.IsFalse(TAtlasRunningProgram.IsPackage(cExe));
end;

procedure TAtlasRunningProgramTests.FollowsMode;
var
  mPlan: TAtlasRunningProgramPlan;
begin
  mPlan := TAtlasRunningProgram.Plan(Project(cExe), TAtlasStopRunningMode.Ask, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.Ask), Ord(mPlan.Action));
  Assert.AreEqual(Integer(1), Integer(Length(mPlan.Processes)));
  Assert.AreEqual(Cardinal(100), mPlan.Processes[0].Pid);
  Assert.AreEqual('AtlasDemo.exe', mPlan.ProgramName);
  mPlan := TAtlasRunningProgram.Plan(Project(cExe), TAtlasStopRunningMode.Always, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.Stop), Ord(mPlan.Action));
  mPlan := TAtlasRunningProgram.Plan(Project(cExe), TAtlasStopRunningMode.Never, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'never: wie bisher');
  Assert.AreEqual(Integer(0), Integer(Length(mPlan.Processes)));
end;

procedure TAtlasRunningProgramTests.IgnoresDebuggedProcesses;
var
  mPlan: TAtlasRunningProgramPlan;
begin
  mPlan := TAtlasRunningProgram.Plan(Project(cExe), TAtlasStopRunningMode.Always, Running, [100], cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'im Debugger');
  mPlan := TAtlasRunningProgram.Plan(Project('C:\Program Files\Studio\bin\bds.exe'), TAtlasStopRunningMode.Always,
    Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'die IDE selbst');
end;

procedure TAtlasRunningProgramTests.IgnoresOtherFolders;
var
  mPlan: TAtlasRunningProgramPlan;
begin
  mPlan := TAtlasRunningProgram.Plan(Project('C:\Projekte\Demo\Win64\Debug\AtlasDemo.exe'),
    TAtlasStopRunningMode.Ask, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action));
  mPlan := TAtlasRunningProgram.Plan(Project(''), TAtlasStopRunningMode.Ask, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'ohne Ausgabe');
end;

procedure TAtlasRunningProgramTests.SkipsRunsWithoutOutput;
var
  mProject: TAtlasCompileProject;
  mPlan: TAtlasRunningProgramPlan;
begin
  mPlan := TAtlasRunningProgram.Plan(Project(cExe, TAtlasCompileKind.Check), TAtlasStopRunningMode.Always, Running,
    nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'Syntaxprüfung');
  mPlan := TAtlasRunningProgram.Plan(Project(cExe, TAtlasCompileKind.Clean), TAtlasStopRunningMode.Always, Running,
    nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'Bereinigen');
  mPlan := TAtlasRunningProgram.Plan(Project(cExe, TAtlasCompileKind.Build), TAtlasStopRunningMode.Always, Running,
    nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.Stop), Ord(mPlan.Action), 'Erzeugen');
  mProject := Project(cExe);
  mProject.Background := True;
  mPlan := TAtlasRunningProgram.Plan(mProject, TAtlasStopRunningMode.Always, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'Hintergrundprüfung');
end;

procedure TAtlasRunningProgramTests.AssistantBuildsDoNotAsk;
var
  mProject: TAtlasCompileProject;
  mPlan: TAtlasRunningProgramPlan;
begin
  mProject := Project(cExe);
  mProject.RequestedBy := 'mcp';
  mPlan := TAtlasRunningProgram.Plan(mProject, TAtlasStopRunningMode.Ask, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action));
  Assert.AreEqual(Integer(0), Integer(Length(mPlan.Processes)));
  mPlan := TAtlasRunningProgram.Plan(mProject, TAtlasStopRunningMode.Always, Running, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.Stop), Ord(mPlan.Action));
end;

procedure TAtlasRunningProgramTests.PackagesOnlyNotice;
const
  cBpl = 'C:\Users\Public\Documents\Embarcadero\Studio\23.0\Bpl\MyPack.bpl';
var
  mPlan: TAtlasRunningProgramPlan;
  mLoaded: TArray<TAtlasRunningProcess>;
begin
  mLoaded := [TAtlasRunningProcess.Create(300, cBpl, 'Host.exe')];
  mPlan := TAtlasRunningProgram.Plan(Project(cBpl), TAtlasStopRunningMode.Always, mLoaded, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.Notice), Ord(mPlan.Action));
  Assert.AreEqual('Host.exe', mPlan.ProcessNames);
  mPlan := TAtlasRunningProgram.Plan(Project(cBpl), TAtlasStopRunningMode.Never, mLoaded, nil, cOwnPid);
  Assert.AreEqual(Ord(TAtlasRunningProgramAction.None), Ord(mPlan.Action), 'never: auch kein Hinweis');
end;

procedure TAtlasRunningProgramTests.NamesEachProcessOnce;
var
  mPlan: TAtlasRunningProgramPlan;
begin
  mPlan := Default(TAtlasRunningProgramPlan);
  mPlan.Processes := [TAtlasRunningProcess.Create(1, cExe, 'AtlasDemo.exe'),
    TAtlasRunningProcess.Create(2, cExe, 'atlasdemo.exe'), TAtlasRunningProcess.Create(3, 'C:\B.exe', 'B.exe')];
  Assert.AreEqual('AtlasDemo.exe, B.exe', mPlan.ProcessNames);
  mPlan.Processes := nil;
  Assert.AreEqual('', mPlan.ProcessNames);
end;

end.
