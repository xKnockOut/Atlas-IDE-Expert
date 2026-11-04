unit Atlas.IDE.Tests.Runner;

// DUnitX-Tests aus der IDE ausführen (#69).
// - Testprojekt: das Projekt einer Testunit (Code Lens), sonst das aktive,
//   wenn seine Hauptdatei DUnitX.TestFramework verwendet, sonst das einzige
//   solche Projekt der Projektgruppe. Gibt es mehrere Kandidaten (die
//   Testunit steht in mehreren Testprojekten, oder die Gruppe hat mehrere),
//   fragt Atlas einmal in einem Palettenfenster und merkt sich die Wahl für
//   genau diese Kandidaten (Atlas.Core.Tests.ProjectChoice, #585).
//   Konfiguration, Plattform und Test-EXE (Zielname) kommen aus dem
//   Testprojekt; Atlas nimmt nicht Win32 an.
// - Mit „Vor den Tests bauen“ (TestsBuildFirst) baut der Haken OnBuild das
//   Testprojekt vorher (make über IOTAProjectBuilder, #261); ohne ihn oder
//   ohne Einstellung läuft die vorhandene EXE ohne Compiler.
// - Die EXE läuft unsichtbar in einem eigenen Thread über den Prozessläufer
//   der Versionsverwaltung (Zeitlimit, Abbruch beim Entladen) mit
//   --exitbehavior:Continue --xmlfile:<temp> [--run:…]; das Ergebnis kommt
//   über TAtlasMainThread zurück.
// - Ergebnis: fehlgeschlagene Tests als Probleme an der Testmethode (Haken
//   OnProblems → Problem-Speicher, Quelle DUnitX), Zusammenfassung und je
//   Fehlschlag eine anklickbare Zeile in der Meldungsansicht (Gruppe Atlas),
//   Abschnitt "tests" der Projekt-Zusammenfassung (Haken OnFinished, #592,
//   #763) und der Stand je Test für die Code Lens.
// - Nach einem Build des Benutzers ruft die Composition BuildFinished mit der
//   Bewertung aus #530 (Atlas.Core.Build.Verdict); mit „Tests nach dem Build“
//   laufen dann die Tests des gebauten Testprojekts (ohne erneut zu bauen).
// - Für „Test debuggen“ (#585, Atlas.IDE.Tests.Debug): Projektwahl, Ziel,
//   Build vorab, Sperre während der Sitzung (Debugging) und das Ergebnis aus
//   dem XML-Bericht des Laufs im Debugger (ReportRun).
// Haken statt Imports (A-09): Build, Probleme und Willkommensseite sind andere
// Features; die Composition verbindet sie.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Text.TestResults,
  Atlas.IDE.Tests.Projects;

type
  /// <summary>Ende des Builds vor den Tests: AError &lt;&gt; '' = nicht gebaut (Grund); sonst Erfolg und EXE.</summary>
  TAtlasTestsBuildDone = reference to procedure(ASucceeded: Boolean; const AOutputFile, AError: string);
  /// <summary>Baut AProject (make) für die Tests; False mit Grund, wenn nicht gebaut wird.</summary>
  TAtlasTestsBuildFunc = reference to function(const AProject: string; const ADone: TAtlasTestsBuildDone;
    out AReason: string): Boolean;
  TAtlasTestsProblemsProc = reference to procedure(const AProblems: TArray<TPair<string, TAtlasProblem>>);
  TAtlasTestsFinishedProc = reference to procedure(const AProject: string; const ATests: TAtlasProjectTests);
  /// <summary>Neuer Prozessläufer; ACancelled bricht ab.</summary>
  TAtlasTestsRunnerFactory = reference to function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner;

  TAtlasIdeTests = class
  private type
    /// <summary>Lebt, solange der Läufer lebt; Rückrufe nach dem Freigeben prüfen es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
    /// <summary>Haken zu Build, Problemen und Willkommensseite (A-09); die Composition setzt sie.</summary>
    THooks = record
      OnBuild: TAtlasTestsBuildFunc;
      OnProblems: TAtlasTestsProblemsProc;
      OnFinished: TAtlasTestsFinishedProc;
      OnLastFailed: TFunc<string, TArray<string>>;
    end;
  private
    FAlive: TAlive;
    FAliveRef: IInterface;
    FNewRunner: TAtlasTestsRunnerFactory;
    FThread: TThread;
    FBusy: Boolean;
    FVersion: Integer;
    /// <summary>Ergebnisse je Test (voller Name) aller Läufe dieser Sitzung, für Code Lens und Probleme.</summary>
    FCases: TArray<TTestCaseResult>;
    /// <summary>Fehlgeschlagene Tests des letzten Laufs je Testprojekt (Schlüssel klein).</summary>
    FLastFailed: TDictionary<string, TArray<string>>;
    FHooks: THooks;
    FDebugging: Boolean;
    procedure SetDebugging(AValue: Boolean);
    function GetBusy: Boolean;
    procedure Start(const AProject: IOTAProject; const ATests: TArray<string>; ABuildFirst: Boolean);
    procedure Execute(const ATarget: TAtlasTestTarget);
    procedure Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
      const AXml: string; const AOutput: TArray<string>);
    procedure Merge(const ARun: TTestRunResult);
    /// <summary>Meldet ATarget (gültiger Bericht ARun): Probleme, Meldungsansicht, Zusammenfassung.</summary>
    procedure Report(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
  public
    constructor Create(const ANewRunner: TAtlasTestsRunnerFactory);
    destructor Destroy; override;
    /// <summary>Alle Tests des Testprojekts.</summary>
    procedure RunAll;
    /// <summary>Die fehlgeschlagenen Tests des letzten Laufs (auch nach einem Neustart über OnLastFailed).</summary>
    procedure RunFailed;
    /// <summary>Tests ATests (Namen für --run) im Testprojekt der Datei AFileName (Code Lens).</summary>
    procedure RunTests(const AFileName: string; const ATests: TArray<string>);
    /// <summary>Alle Tests des geöffneten Testprojekts AProject (Schnellaktion „Tests“, #764), vorher gebaut.
    /// False mit AReason, wenn „Tests ausführen“ aus ist, schon ein Lauf läuft oder AProject nicht offen ist.
    /// </summary>
    function RunProject(const AProject: string; out AReason: string): Boolean;
    /// <summary>Ein Build ist fertig und bewertet (#530): mit „Tests nach dem Build“ laufen die Tests, wenn er als
    /// erfolgreich gilt (ASucceeded = TAtlasBuildVerdict.Effective).</summary>
    procedure BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean);
    /// <summary>Stand eines Tests bzw. einer Fixture (AMethod = '') nach den Läufen dieser Sitzung.</summary>
    function StatusOf(const AUnitName, AFixture, AMethod: string): TAtlasTestStatus; overload;
    /// <summary>Stand eines Falls ACaseName (#585); '' = alle Fälle.</summary>
    function StatusOf(const AUnitName, AFixture, AMethod, ACaseName: string): TAtlasTestStatus; overload;
    /// <summary>Testprojekt zur Datei AFileName (Testunit; '' = ohne): ihr Projekt, sonst das aktive Testprojekt,
    /// sonst die der Gruppe; bei mehreren fragt Atlas einmal und merkt sich die Wahl. Ruft AThen im Hauptthread,
    /// ohne Testprojekt eine Meldung statt dessen.</summary>
    procedure ResolveProject(const AFileName: string; const AThen: TAtlasTestsProjectProc);
    /// <summary>Konfiguration, Plattform und Test-EXE des Testprojekts; ATests als Filter.</summary>
    class function TargetOf(const AProject: IOTAProject; const ATests: TArray<string>): TAtlasTestTarget; static;
    /// <summary>Testprojekt vorab bauen (make, Haken OnBuild). False ohne Haken (dann baut „Start“ der IDE selbst)
    /// oder wenn der Build abgelehnt wird (AReason); sonst kommt ADone nach dem Build.</summary>
    function BuildProject(const AProject: string; const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;
    /// <summary>Gibt es einen Weg, vorab zu bauen (Haken OnBuild)?</summary>
    function CanBuild: Boolean;
    /// <summary>Ergebnis eines Laufs außerhalb des Läufers (Debugger, #585) aus dem XML-Bericht AXml melden wie
    /// nach „Tests ausführen“; ohne Bericht nichts.</summary>
    procedure ReportRun(const ATarget: TAtlasTestTarget; const AXml: string);
    /// <summary>Datei der Unit AUnitName im Testprojekt AProjectFile; '' ohne.</summary>
    class function UnitFileOf(const AProjectFile, AUnitName: string): string; static;
    /// <summary>Zeile in der Meldungsansicht (Gruppe Atlas).</summary>
    procedure Say(const AText: string);
    /// <summary>Ein Test läuft im Debugger (#585): sperrt weitere Läufe, die Code Lens zeigt „Tests laufen …“.
    /// </summary>
    property Debugging: Boolean read FDebugging write SetDebugging;
    /// <summary>Ein Lauf (oder der Build davor) ist im Gange, auch im Debugger.</summary>
    property Busy: Boolean read GetBusy;
    /// <summary>Zählt jede Änderung von Busy und Ergebnissen (Neuzeichnen der Code Lens).</summary>
    property Version: Integer read FVersion;
    property OnBuild: TAtlasTestsBuildFunc read FHooks.OnBuild write FHooks.OnBuild;
    property OnProblems: TAtlasTestsProblemsProc read FHooks.OnProblems write FHooks.OnProblems;
    property OnFinished: TAtlasTestsFinishedProc read FHooks.OnFinished write FHooks.OnFinished;
    property OnLastFailed: TFunc<string, TArray<string>> read FHooks.OnLastFailed write FHooks.OnLastFailed;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.UI.Strings,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

const
  MessageGroup = 'Atlas';
  /// <summary>So viele letzte Zeilen der Ausgabe zeigt die Meldung „kein Bericht“.</summary>
  OutputLines = 5;

/// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  Result := TAtlasIdeTestProjects.ReadLines(AFileName, ALines);
end;

function ProjectByFile(const AFileName: string): IOTAProject;
begin
  Result := TAtlasIdeTestProjects.ProjectByFile(AFileName);
end;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

function SecondsText(AMs: Int64): string;
begin
  Result := FormatFloat('0.00', AMs / 1000, FormatSettings);
end;

/// <summary>Lebt der Läufer noch? Für Rückrufe nach einer Wahl in der Palette.</summary>
function AliveCheck(AAlive: TAtlasIdeTests.TAlive; const AKeep: IInterface): TFunc<Boolean>;
var
  mAlive: TAtlasIdeTests.TAlive;
  mKeep: IInterface;
begin
  mAlive := AAlive;
  mKeep := AKeep;
  Result :=
    function: Boolean
    begin
      Result := (mKeep <> nil) and mAlive.Alive;
    end;
end;

function SayProc(ATests: TAtlasIdeTests): TAtlasTestsSayProc;
var
  mTests: TAtlasIdeTests;
begin
  mTests := ATests;
  Result :=
    procedure(const AText: string)
    begin
      mTests.Say(AText);
    end;
end;

{ TAtlasIdeTests }

constructor TAtlasIdeTests.Create(const ANewRunner: TAtlasTestsRunnerFactory);
begin
  inherited Create;
  FNewRunner := ANewRunner;
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FLastFailed := TDictionary<string, TArray<string>>.Create;
end;

destructor TAtlasIdeTests.Destroy;
begin
  FAlive.Alive := False;
  if FThread <> nil then
  begin
    // Der Prozessläufer beendet die Test-EXE, sobald sein Thread endet.
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  FLastFailed.Free;
  FAliveRef := nil;
  inherited Destroy;
end;

procedure TAtlasIdeTests.Say(const AText: string);
var
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
begin
  if not Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Exit;
  end;
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
  begin
    Group := Messages.AddMessageGroup(MessageGroup);
  end;
  Messages.AddTitleMessage(AText, Group);
end;

procedure TAtlasIdeTests.ResolveProject(const AFileName: string; const AThen: TAtlasTestsProjectProc);
var
  Found: TArray<IOTAProject>;
begin
  Found := nil;
  // Testunit der Code Lens bzw. am Cursor: ihre Testprojekte.
  if AFileName <> '' then
  begin
    Found := TAtlasIdeTestProjects.TestProjects(AFileName);
  end;
  if Length(Found) = 0 then
  begin
    if TAtlasIdeTestProjects.IsTestProject(GetActiveProject) then
    begin
      AThen(GetActiveProject);
      Exit;
    end;
    Found := TAtlasIdeTestProjects.TestProjects('');
  end;
  if Length(Found) = 0 then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoProject));
    Exit;
  end;
  TAtlasIdeTestProjects.Choose(Found, AliveCheck(FAlive, FAliveRef), SayProc(Self), AThen);
end;

class function TAtlasIdeTests.UnitFileOf(const AProjectFile, AUnitName: string): string;
var
  Project: IOTAProject;
  Index: Integer;
  FileName: string;
begin
  Result := '';
  Project := ProjectByFile(AProjectFile);
  if Project <> nil then
  begin
    for Index := 0 to Project.GetModuleCount - 1 do
    begin
      FileName := Project.GetModule(Index).FileName;
      if SameText(ExtractFileExt(FileName), '.pas') and SameText(ProjectName(FileName), AUnitName) then
      begin
        Exit(FileName);
      end;
    end;
  end;
  // Nicht im Projekt eingetragen: neben der .dproj.
  FileName := TPath.Combine(ExtractFileDir(AProjectFile), AUnitName + '.pas');
  if FileExists(FileName) then
  begin
    Result := FileName;
  end;
end;

procedure TAtlasIdeTests.RunAll;
begin
  if not TAtlasIdeSettings.Current.TestRun then
  begin
    Exit;
  end;
  ResolveProject('',
    procedure(const AProject: IOTAProject)
    begin
      Start(AProject, nil, TAtlasIdeSettings.Current.TestsBuildFirst);
    end);
end;

procedure TAtlasIdeTests.RunFailed;
begin
  if not TAtlasIdeSettings.Current.TestRun then
  begin
    Exit;
  end;
  ResolveProject('',
    procedure(const AProject: IOTAProject)
    var
      Tests: TArray<string>;
    begin
      if not FLastFailed.TryGetValue(AnsiLowerCase(AProject.FileName), Tests) and Assigned(FHooks.OnLastFailed) then
      begin
        Tests := FHooks.OnLastFailed(AProject.FileName);
      end;
      if Length(Tests) = 0 then
      begin
        Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoFailed, [ProjectName(AProject.FileName)]));
        Exit;
      end;
      Start(AProject, Tests, TAtlasIdeSettings.Current.TestsBuildFirst);
    end);
end;

procedure TAtlasIdeTests.RunTests(const AFileName: string; const ATests: TArray<string>);
var
  Tests: TArray<string>;
begin
  if not TAtlasIdeSettings.Current.TestRun then
  begin
    Exit;
  end;
  Tests := ATests;
  ResolveProject(AFileName,
    procedure(const AProject: IOTAProject)
    begin
      Start(AProject, Tests, TAtlasIdeSettings.Current.TestsBuildFirst);
    end);
end;

function TAtlasIdeTests.RunProject(const AProject: string; out AReason: string): Boolean;
var
  Project: IOTAProject;
begin
  Result := False;
  AReason := '';
  if not TAtlasIdeSettings.Current.TestRun then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonTestsOff);
    Exit;
  end;
  if Busy then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy);
    Exit;
  end;
  Project := ProjectByFile(AProject);
  if Project = nil then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonNotOpened);
    Exit;
  end;
  Start(Project, nil, True);
  Result := True;
end;

procedure TAtlasIdeTests.BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean);
var
  Project: IOTAProject;
begin
  if Busy or (AProject.FileName = '') or AProject.Background or (AProject.RequestedBy <> '') then
  begin
    Exit;
  end;
  Project := ProjectByFile(AProject.FileName);
  if not TAtlasTestRun.ShouldRunAfterBuild(TAtlasIdeSettings.Current, ASucceeded, AProject.Background,
    AProject.RequestedBy, Project <> nil) then
  begin
    Exit;
  end;
  // Gerade gebaut: nicht noch einmal.
  Start(Project, nil, False);
end;

class function TAtlasIdeTests.TargetOf(const AProject: IOTAProject;
  const ATests: TArray<string>): TAtlasTestTarget;
var
  Options: IOTAProjectOptions;
begin
  Result := Default(TAtlasTestTarget);
  Result.Project := AProject.FileName;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  Result.Tests := ATests;
  Options := AProject.ProjectOptions;
  if Options <> nil then
  begin
    Result.Executable := Options.TargetName;
  end;
end;

function TAtlasIdeTests.CanBuild: Boolean;
begin
  Result := Assigned(FHooks.OnBuild);
end;

function TAtlasIdeTests.BuildProject(const AProject: string; const ADone: TAtlasTestsBuildDone;
  out AReason: string): Boolean;
begin
  AReason := '';
  Result := Assigned(FHooks.OnBuild) and FHooks.OnBuild(AProject, ADone, AReason);
end;

procedure TAtlasIdeTests.ReportRun(const ATarget: TAtlasTestTarget; const AXml: string);
begin
  if Trim(AXml) = '' then
  begin
    Exit;
  end;
  Finish(ATarget, TAtlasVcsOutcome.Ok, 0, AXml, nil);
end;

function TAtlasIdeTests.GetBusy: Boolean;
begin
  Result := FBusy or FDebugging;
end;

procedure TAtlasIdeTests.SetDebugging(AValue: Boolean);
begin
  if FDebugging = AValue then
  begin
    Exit;
  end;
  FDebugging := AValue;
  Inc(FVersion);
end;

procedure TAtlasIdeTests.Start(const AProject: IOTAProject; const ATests: TArray<string>; ABuildFirst: Boolean);
var
  Target: TAtlasTestTarget;
  Reason: string;
  Alive: TAlive;
  Keep: IInterface;
begin
  if Busy then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
    Exit;
  end;
  Target := TargetOf(AProject, ATests);
  if not TAtlasTestRun.CanRun(Target.Platform) then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsPlatform, [ProjectName(Target.Project), Target.Platform]));
    Exit;
  end;
  if not ABuildFirst or not Assigned(FHooks.OnBuild) then
  begin
    Execute(Target);
    Exit;
  end;
  FBusy := True;
  Inc(FVersion);
  Alive := FAlive;
  Keep := FAliveRef;
  if not FHooks.OnBuild(Target.Project,
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      // Keep hält den Merker am Leben, auch wenn der Läufer schon frei ist.
      if (Keep = nil) or not Alive.Alive then
      begin
        Exit;
      end;
      FBusy := False;
      Inc(FVersion);
      if AError <> '' then
      begin
        Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildRefused, [ProjectName(Target.Project), AError]));
      end
      else if not ASucceeded then
      begin
        Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildFailed, [ProjectName(Target.Project)]));
      end
      else
      begin
        if AOutputFile <> '' then
        begin
          Target.Executable := AOutputFile;
        end;
        Execute(Target);
      end;
    end, Reason) then
  begin
    FBusy := False;
    Inc(FVersion);
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildRefused, [ProjectName(Target.Project), Reason]));
  end;
end;

/// <summary>Test-EXE von ATarget mit Bericht in einer Temp-Datei ausführen (im Thread des Laufs); AXml ist der
/// Bericht, AOutput die letzten Zeilen der Ausgabe.</summary>
function RunTestExe(const AFactory: TAtlasTestsRunnerFactory; const ATarget: TAtlasTestTarget; out AXml: string;
  out AOutput: TArray<string>): TAtlasVcsRunResult;
var
  mRunner: IAtlasVcsRunner;
  mResultFile: string;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  AXml := '';
  AOutput := nil;
  mResultFile := TPath.Combine(TPath.GetTempPath, 'atlas-tests-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
  try
    mRunner := AFactory(
      function: Boolean
      begin
        Result := TAtlasShutdown.Signalled;
      end);
    Result := mRunner.Run(ATarget.Executable, TDUnitXCommandLine.Arguments(mResultFile, ATarget.Tests),
      ExtractFileDir(ATarget.Executable), TAtlasTestRun.TimeoutMs);
    if FileExists(mResultFile) then
    begin
      AXml := TFile.ReadAllText(mResultFile, TEncoding.UTF8);
    end;
    mLines := TTextLines.SplitLines(TrimRight(TEncoding.ANSI.GetString(Result.Output)));
    for mIndex := Max(0, Length(mLines) - OutputLines) to High(mLines) do
    begin
      AOutput := AOutput + [mLines[mIndex]];
    end;
  except
    on E: Exception do
    begin
      Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
      AOutput := [E.Message];
    end;
  end;
  try
    if FileExists(mResultFile) then
    begin
      TFile.Delete(mResultFile);
    end;
  except
    on Exception do
      ;
  end;
end;

procedure TAtlasIdeTests.Execute(const ATarget: TAtlasTestTarget);
var
  mTarget: TAtlasTestTarget;
  mFactory: TAtlasTestsRunnerFactory;
  mAlive: TAlive;
  mKeep: IInterface;
begin
  if (ATarget.Executable = '') or not FileExists(ATarget.Executable) then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoExe, [ProjectName(ATarget.Project), ATarget.Executable]));
    Exit;
  end;
  mTarget := ATarget;
  mFactory := FNewRunner;
  mAlive := FAlive;
  mKeep := FAliveRef;
  FBusy := True;
  Inc(FVersion);
  Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsStarted, [ProjectName(mTarget.Project), mTarget.Configuration,
    mTarget.Platform]));
  // Ein Thread je Lauf; der vorige ist fertig (FBusy), sein Objekt wird hier frei.
  FreeAndNil(FThread);
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      mRun: TAtlasVcsRunResult;
      mXml: string;
      mOutput: TArray<string>;
    begin
      mRun := RunTestExe(mFactory, mTarget, mXml, mOutput);
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          if (mKeep = nil) or not mAlive.Alive then
          begin
            Exit;
          end;
          TAtlasGuard.Run(TAtlasFeature.Build,
            procedure
            begin
              Finish(mTarget, mRun.Outcome, mRun.ExitCode, mXml, mOutput);
            end);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeTests.Merge(const ARun: TTestRunResult);
var
  Kept: TArray<TTestCaseResult>;
  Item, Fresh: TTestCaseResult;
  Replaced: Boolean;
begin
  Kept := nil;
  for Item in FCases do
  begin
    Replaced := False;
    for Fresh in ARun.Cases do
    begin
      if SameText(Fresh.FullName, Item.FullName) then
      begin
        Replaced := True;
      end;
    end;
    if not Replaced then
    begin
      Kept := Kept + [Item];
    end;
  end;
  FCases := Kept + ARun.Cases;
end;

/// <summary>Datei einer Unit im Testprojekt AProjectFile, als Rückruf für TAtlasTestRun.Failures.</summary>
function UnitFileFunc(const AProjectFile: string): TAtlasTestUnitFile;
var
  mProjectFile: string;
begin
  mProjectFile := AProjectFile;
  Result :=
    function(const AUnitName: string): string
    begin
      Result := TAtlasIdeTests.UnitFileOf(mProjectFile, AUnitName);
    end;
end;

function ProblemText(const ACase: TTestCaseResult): string;
begin
  Result := TAtlasTestRun.ProblemText(ACase, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblem),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblemValues));
end;

/// <summary>Meldungsansicht: je Fehlschlag eine Zeile, die zur Testmethode springt.</summary>
procedure SayFailures(const AFailures: TArray<TAtlasTestFailure>);
var
  mMessages: IOTAMessageServices;
  mGroup: IOTAMessageGroup;
  mFailure: TAtlasTestFailure;
  mLineRef: Pointer;
begin
  if (Length(AFailures) = 0) or not Supports(BorlandIDEServices, IOTAMessageServices, mMessages) then
  begin
    Exit;
  end;
  mGroup := mMessages.GetGroup(MessageGroup);
  if mGroup = nil then
  begin
    mGroup := mMessages.AddMessageGroup(MessageGroup);
  end;
  for mFailure in AFailures do
  begin
    if mFailure.FileName <> '' then
    begin
      mMessages.AddToolMessage(mFailure.FileName, ProblemText(mFailure.Test), 'DUnitX', mFailure.Line + 1,
        mFailure.StartCharacter + 1, nil, mLineRef, mGroup);
    end
    else
    begin
      mMessages.AddTitleMessage('  ' + ProblemText(mFailure.Test), mGroup);
    end;
  end;
end;

procedure TAtlasIdeTests.Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
  const AXml: string; const AOutput: TArray<string>);
var
  mRun: TTestRunResult;
  mLine: string;
begin
  FBusy := False;
  Inc(FVersion);
  if AOutcome = TAtlasVcsOutcome.Cancelled then
  begin
    Exit;
  end;
  if AOutcome = TAtlasVcsOutcome.TimedOut then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsTimedOut, [ProjectName(ATarget.Project),
      TAtlasTestRun.TimeoutMs div 1000]));
    Exit;
  end;
  mRun := TTestResults.Parse(AXml);
  if (AOutcome <> TAtlasVcsOutcome.Ok) or not mRun.Valid then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoReport, [ProjectName(ATarget.Project), AExitCode]));
    for mLine in AOutput do
    begin
      Say('  ' + mLine);
    end;
    Exit;
  end;
  Report(ATarget, mRun);
end;

procedure TAtlasIdeTests.Report(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
var
  mAll: TTestRunResult;
  mFailures: TArray<TAtlasTestFailure>;
begin
  Merge(ARun);
  // Probleme aus allen Ergebnissen dieser Sitzung: Ein Lauf einzelner Tests lässt die übrigen Fehlschläge stehen.
  mAll := ARun;
  mAll.Cases := FCases;
  mFailures := TAtlasTestRun.Failures(ARun, UnitFileFunc(ATarget.Project), ReadLines);
  if Assigned(FHooks.OnProblems) then
  begin
    FHooks.OnProblems(TAtlasTestRun.Problems(TAtlasTestRun.Failures(mAll, UnitFileFunc(ATarget.Project), ReadLines),
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblem),
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblemValues)));
  end;
  FLastFailed.AddOrSetValue(AnsiLowerCase(ATarget.Project), TAtlasTestRun.SummaryOf(ATarget, ARun, mFailures,
    0).FailedTests);
  // Meldungsansicht: Zusammenfassung, dann je Fehlschlag eine Zeile, die zur Testmethode springt.
  if ARun.Total = 0 then
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoTests, [ProjectName(ATarget.Project)]));
  end
  else
  begin
    Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFinished, [ProjectName(ATarget.Project),
      ARun.Count(TTestOutcome.Passed), ARun.Count(TTestOutcome.Failed), ARun.Count(TTestOutcome.Error),
      ARun.Count(TTestOutcome.Skipped), SecondsText(ARun.DurationMs)]));
  end;
  SayFailures(mFailures);
  if Assigned(FHooks.OnFinished) then
  begin
    FHooks.OnFinished(ATarget.Project, TAtlasTestRun.SummaryOf(ATarget, ARun, mFailures,
      TTimeZone.Local.ToUniversalTime(Now)));
  end;
end;

function TAtlasIdeTests.StatusOf(const AUnitName, AFixture, AMethod: string): TAtlasTestStatus;
begin
  Result := TAtlasTestRun.StatusOf(FCases, AUnitName, AFixture, AMethod);
end;

function TAtlasIdeTests.StatusOf(const AUnitName, AFixture, AMethod, ACaseName: string): TAtlasTestStatus;
begin
  Result := TAtlasTestRun.StatusOf(FCases, AUnitName, AFixture, AMethod, ACaseName);
end;

end.
