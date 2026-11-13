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
// - Ergebnis: fehlgeschlagene Tests als Probleme an der Testmethode bzw.
//   an der fehlgeschlagenen Anweisung (tests.failureAtAssert, #1771; Haken
//   OnProblems → Problem-Speicher, Quelle DUnitX), Zusammenfassung und je
//   Fehlschlag eine anklickbare Zeile in der Meldungsansicht (Gruppe Atlas),
//   Abschnitt "tests" der Projekt-Zusammenfassung (Haken OnFinished, #592,
//   #763, mit den langsamsten Tests #1772) und der Stand je Test für die
//   Code Lens.
// - Nach einem Build des Benutzers ruft die Composition BuildFinished mit der
//   Bewertung aus #530 (Atlas.Core.Build.Verdict); mit „Tests nach dem Build“
//   laufen dann die Tests des gebauten Testprojekts (ohne erneut zu bauen).
// - Für „Test debuggen“ (#585, Atlas.IDE.Tests.Debug): Projektwahl, Ziel,
//   Build vorab, Sperre während der Sitzung (Debugging) und das Ergebnis aus
//   dem XML-Bericht des Laufs im Debugger (ReportRun).
// - Nach jedem gemeldeten Lauf ruft der Läufer den Haken OnReported (Stand
//   der Tests für veraltete Ergebnisse, #1770, Atlas.IDE.Tests.Stale).
// - Lecks je Test (tests.leaks, #1774): Ein Test, den der Bericht nur wegen
//   eines Lecks als fehlgeschlagen nennt, gilt als bestanden mit Leck
//   (Atlas.Core.Tests.Leaks); Warnung am Methodenkopf und eine Zeile mit
//   Anzahl und Bytes in der Meldungsansicht. Lecks am Programmende aus dem
//   Bericht von FastMM (Datei neben der EXE, wenn der Lauf sie schrieb) bzw.
//   der Ausgabe des Programms: eine Zeile mit Namen und Anzahl.
// - Protokoll je Test (tests.log, #2168): Vor dem Lauf legt der Läufer die
//   leere Seitendatei neben dem Bericht an (Atlas.Core.Tests.Log); ist der
//   Atlas-Logger im Testprojekt eingetragen, schreibt er hinein. Seitendatei
//   und Konsolenausgabe stehen im gemeldeten Lauf (Output, LogFile).
// - RunQuiet (#1775, Tests beim Speichern): Lauf im Hintergrund ohne Frage
//   nach dem Testprojekt und ohne Zeilen in der Meldungsansicht; die Ausgabe
//   (Atlas.IDE.Tests.Output) merkt sie und meldet das Ende.
// Haken statt Imports: Build, Probleme und Willkommensseite sind andere
// Features; die Composition verbindet sie.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  ToolsAPI,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Tests.Run,
  Atlas.Text.TestResults,
  Atlas.IDE.Tests.Projects,
  Atlas.IDE.Tests.Output;

type
  /// <summary>Ende des Builds vor den Tests: AError &lt;&gt; '' = nicht gebaut (Grund); sonst Erfolg und EXE.</summary>
  TAtlasTestsBuildDone = reference to procedure(ASucceeded: Boolean; const AOutputFile, AError: string);
  /// <summary>Baut AProject (make) für die Tests; False mit Grund, wenn nicht gebaut wird.</summary>
  TAtlasTestsBuildFunc = reference to function(const AProject: string; const ADone: TAtlasTestsBuildDone;
    out AReason: string): Boolean;
  TAtlasTestsProblemsProc = reference to procedure(const AProblems: TArray<TPair<string, TAtlasProblem>>);
  TAtlasTestsFinishedProc = reference to procedure(const AProject: string; const ATests: TAtlasProjectTests);
  /// <summary>Ein Lauf von ATarget mit gültigem Bericht ARun ist gemeldet (#1770).</summary>
  TAtlasTestsReportedProc = reference to procedure(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult);
  /// <summary>Neuer Prozessläufer; ACancelled bricht ab.</summary>
  TAtlasTestsRunnerFactory = reference to function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner;
  /// <summary>Was die Test-EXE hinterlässt: Bericht, letzte Zeilen der Ausgabe, Leckbericht am Programmende ('' ohne)
  /// und für das Protokoll je Test (#2168) die ganze Ausgabe und die Seitendatei des Atlas-Loggers.</summary>
  TAtlasTestsExeOutput = record
    Xml: string;
    Lines: TArray<string>;
    LeakText: string;
    Output: string;
    LogFile: string;
  end;

  TAtlasIdeTests = class
  private type
    /// <summary>Lebt, solange der Läufer lebt; Rückrufe nach dem Freigeben prüfen es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;
    /// <summary>Haken zu Build, Problemen und Willkommensseite; die Composition setzt sie.</summary>
    THooks = record
      OnBuild: TAtlasTestsBuildFunc;
      OnProblems: TAtlasTestsProblemsProc;
      OnFinished: TAtlasTestsFinishedProc;
      OnLastFailed: TFunc<string, TArray<string>>;
      OnReported: TAtlasTestsReportedProc;
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
    FOutput: TAtlasIdeTestsOutput;
    procedure SetDebugging(AValue: Boolean);
    procedure Start(const AProject: IOTAProject; const ATests: TArray<string>; ABuildFirst: Boolean);
    procedure Execute(const ATarget: TAtlasTestTarget);
    procedure Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
      const AExe: TAtlasTestsExeOutput);
    /// <summary>Meldet ATarget (gültiger Bericht ARun): Probleme, Meldungsansicht, Zusammenfassung; ALeakText wie
    /// bei Finish.</summary>
    procedure Report(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult; const ALeakText: string);
  public
    /// <summary>AOutput gehört dem Aufrufer und lebt länger.</summary>
    constructor Create(const ANewRunner: TAtlasTestsRunnerFactory; AOutput: TAtlasIdeTestsOutput);
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
    /// <summary>Tests ATests im Testprojekt der Datei AFileName im Hintergrund (#1775): ohne Frage nach dem
    /// Testprojekt (eines bzw. die gemerkte Wahl) und ohne Zeilen in der Meldungsansicht; gebaut wie mit „Vor den
    /// Tests bauen“ (mit ABuildFirst; ohne läuft die vorhandene EXE, Folgeläufe einer Serie #1782). Das Ende meldet
    /// die Ausgabe (OnQuietEnded). False mit AReason, wenn nichts startet.</summary>
    function RunQuiet(const AFileName: string; const ATests: TArray<string>; out AReason: string;
      ABuildFirst: Boolean): Boolean;
    /// <summary>Ein Build ist fertig und bewertet (#530): mit „Tests nach dem Build“ laufen die Tests, wenn er als
    /// erfolgreich gilt (ASucceeded = TAtlasBuildVerdict.Effective).</summary>
    procedure BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean);
    /// <summary>Stand der Tests AKeys (Marke der Code Lens: Fixture, Test oder Fall, #585) nach den Läufen dieser
    /// Sitzung; AStale nennt Tests mit veraltetem Ergebnis (#1770), nil = keine.</summary>
    function TallyOf(const AUnitName, AFixture: string; const AKeys: TArray<TAtlasTestKey>;
      const AStale: TAtlasTestStaleFunc): TAtlasTestTally;
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
    function Busy: Boolean;
    /// <summary>Zählt jede Änderung von Busy und Ergebnissen (Neuzeichnen der Code Lens).</summary>
    property Version: Integer read FVersion;
    property OnBuild: TAtlasTestsBuildFunc read FHooks.OnBuild write FHooks.OnBuild;
    property OnProblems: TAtlasTestsProblemsProc read FHooks.OnProblems write FHooks.OnProblems;
    property OnFinished: TAtlasTestsFinishedProc read FHooks.OnFinished write FHooks.OnFinished;
    property OnLastFailed: TFunc<string, TArray<string>> read FHooks.OnLastFailed write FHooks.OnLastFailed;
    property OnReported: TAtlasTestsReportedProc read FHooks.OnReported write FHooks.OnReported;
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
  Atlas.Text.DUnitX,
  Atlas.Core.Tests.Leaks,
  Atlas.Core.Tests.Log,
  Atlas.IDE.Foundation.Files;

const
  /// <summary>So viele letzte Zeilen der Ausgabe zeigt die Meldung „kein Bericht“.</summary>
  cOutputLines = 5;
  /// <summary>Höchstens so viele Namen in der Zeile der Lecks am Programmende (#1774).</summary>
  cShutdownLeakNames = 5;

/// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
begin
  Result := TAtlasIdeFiles.ReadLines(AFileName, ALines);
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

/// <summary>Ein Lauf startet nicht bzw. endet ohne Bericht: Grund AText melden, Lauf im Hintergrund beenden.
/// </summary>
procedure Refuse(AOutput: TAtlasIdeTestsOutput; const AText: string);
begin
  AOutput.Tell(AText);
  AOutput.EndQuiet(False, Default(TTestRunResult));
end;

/// <summary>Grund, aus dem nach dem Build vor den Tests nichts läuft (AError: Build abgelehnt, sonst
/// fehlgeschlagen); '' nach einem erfolgreichen Build.</summary>
function BuildRefusal(const AProject: string; ASucceeded: Boolean; const AError: string): string;
begin
  Result := '';
  if AError <> '' then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildRefused, [ProjectName(AProject), AError]);
  end
  else if not ASucceeded then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsBuildFailed, [ProjectName(AProject)]);
  end;
end;

{ TAtlasIdeTests }

constructor TAtlasIdeTests.Create(const ANewRunner: TAtlasTestsRunnerFactory; AOutput: TAtlasIdeTestsOutput);
begin
  inherited Create;
  FNewRunner := ANewRunner;
  FOutput := AOutput;
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
begin
  FOutput.Say(AText);
end;

procedure TAtlasIdeTests.ResolveProject(const AFileName: string; const AThen: TAtlasTestsProjectProc);
var
  mFound: TArray<IOTAProject>;
begin
  mFound := nil;
  // Testunit der Code Lens bzw. am Cursor: ihre Testprojekte.
  if AFileName <> '' then
  begin
    mFound := TAtlasIdeTestProjects.TestProjects(AFileName);
  end;
  if Length(mFound) = 0 then
  begin
    if TAtlasIdeTestProjects.IsTestProject(GetActiveProject) then
    begin
      AThen(GetActiveProject);
      Exit;
    end;
    mFound := TAtlasIdeTestProjects.TestProjects('');
  end;
  if Length(mFound) = 0 then
  begin
    Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsNoProject));
    Exit;
  end;
  TAtlasIdeTestProjects.Choose(mFound, AliveCheck(FAlive, FAliveRef), SayProc(Self), AThen);
end;

class function TAtlasIdeTests.UnitFileOf(const AProjectFile, AUnitName: string): string;
var
  mProject: IOTAProject;
  mIndex: Integer;
  mFileName: string;
begin
  Result := '';
  mProject := ProjectByFile(AProjectFile);
  if mProject <> nil then
  begin
    for mIndex := 0 to mProject.GetModuleCount - 1 do
    begin
      mFileName := mProject.GetModule(mIndex).FileName;
      if SameText(ExtractFileExt(mFileName), '.pas') and SameText(ProjectName(mFileName), AUnitName) then
      begin
        Exit(mFileName);
      end;
    end;
  end;
  // Nicht im Projekt eingetragen: neben der .dproj.
  mFileName := TPath.Combine(ExtractFileDir(AProjectFile), AUnitName + '.pas');
  if FileExists(mFileName) then
  begin
    Result := mFileName;
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
  mTests: TArray<string>;
begin
  if not TAtlasIdeSettings.Current.TestRun then
  begin
    Exit;
  end;
  mTests := ATests;
  ResolveProject(AFileName,
    procedure(const AProject: IOTAProject)
    begin
      Start(AProject, mTests, TAtlasIdeSettings.Current.TestsBuildFirst);
    end);
end;

function TAtlasIdeTests.RunProject(const AProject: string; out AReason: string): Boolean;
var
  mProject: IOTAProject;
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
  mProject := ProjectByFile(AProject);
  if mProject = nil then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.WelcomeQuickReasonNotOpened);
    Exit;
  end;
  Start(mProject, nil, True);
  Result := True;
end;

function TAtlasIdeTests.RunQuiet(const AFileName: string; const ATests: TArray<string>; out AReason: string;
  ABuildFirst: Boolean): Boolean;
var
  mProject: IOTAProject;
begin
  Result := False;
  AReason := '';
  mProject := TAtlasIdeTestProjects.Known(AFileName);
  if Busy then
  begin
    AReason := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy);
  end
  else if mProject = nil then
  begin
    AReason := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsOnSaveNoProject, [ExtractFileName(AFileName)]);
  end
  else
  begin
    // Das Ende meldet die Ausgabe, auch wenn Start sofort abbricht (Plattform, Build abgelehnt).
    FOutput.BeginQuiet;
    Start(mProject, ATests, ABuildFirst and TAtlasIdeSettings.Current.TestsBuildFirst);
    Result := True;
  end;
end;

procedure TAtlasIdeTests.BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean);
var
  mProject: IOTAProject;
begin
  if Busy or (AProject.FileName = '') or AProject.Background or (AProject.RequestedBy <> '') then
  begin
    Exit;
  end;
  mProject := ProjectByFile(AProject.FileName);
  if not TAtlasTestRun.ShouldRunAfterBuild(TAtlasIdeSettings.Current, ASucceeded, AProject.Background,
    AProject.RequestedBy, mProject <> nil) then
  begin
    Exit;
  end;
  // Gerade gebaut: nicht noch einmal.
  Start(mProject, nil, False);
end;

class function TAtlasIdeTests.TargetOf(const AProject: IOTAProject;
  const ATests: TArray<string>): TAtlasTestTarget;
var
  mOptions: IOTAProjectOptions;
begin
  Result := Default(TAtlasTestTarget);
  Result.Project := AProject.FileName;
  Result.Configuration := AProject.CurrentConfiguration;
  Result.Platform := AProject.CurrentPlatform;
  Result.Tests := ATests;
  mOptions := AProject.ProjectOptions;
  if mOptions <> nil then
  begin
    Result.Executable := mOptions.TargetName;
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
var
  mExe: TAtlasTestsExeOutput;
begin
  if Trim(AXml) = '' then
  begin
    Exit;
  end;
  mExe := Default(TAtlasTestsExeOutput);
  mExe.Xml := AXml;
  Finish(ATarget, TAtlasVcsOutcome.Ok, 0, mExe);
end;

function TAtlasIdeTests.Busy: Boolean;
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
  mTarget: TAtlasTestTarget;
  mReason: string;
  mAlive: TAlive;
  mKeep: IInterface;
begin
  if Busy then
  begin
    Refuse(FOutput, TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsBusy));
    Exit;
  end;
  mTarget := TargetOf(AProject, ATests);
  if not TAtlasTestRun.CanRun(mTarget.Platform) then
  begin
    Refuse(FOutput, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsPlatform, [ProjectName(mTarget.Project),
      mTarget.Platform]));
    Exit;
  end;
  if not ABuildFirst or not Assigned(FHooks.OnBuild) then
  begin
    Execute(mTarget);
    Exit;
  end;
  FBusy := True;
  Inc(FVersion);
  mAlive := FAlive;
  mKeep := FAliveRef;
  if not FHooks.OnBuild(mTarget.Project,
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      // Keep hält den Merker am Leben, auch wenn der Läufer schon frei ist.
      if (mKeep = nil) or not mAlive.Alive then
      begin
        Exit;
      end;
      FBusy := False;
      Inc(FVersion);
      if BuildRefusal(mTarget.Project, ASucceeded, AError) <> '' then
      begin
        Refuse(FOutput, BuildRefusal(mTarget.Project, ASucceeded, AError));
        Exit;
      end;
      if AOutputFile <> '' then
      begin
        mTarget.Executable := AOutputFile;
      end;
      Execute(mTarget);
    end, mReason) then
  begin
    FBusy := False;
    Inc(FVersion);
    Refuse(FOutput, BuildRefusal(mTarget.Project, False, mReason));
  end;
end;

/// <summary>Zeitpunkt der letzten Änderung von AFileName; 0 ohne Datei.</summary>
function WrittenAt(const AFileName: string): TDateTime;
begin
  Result := 0;
  if (AFileName <> '') and FileExists(AFileName) then
  begin
    Result := TFile.GetLastWriteTimeUtc(AFileName);
  end;
end;

/// <summary>Leckbericht am Programmende (#1774): die Datei von FastMM, wenn der Lauf sie seit ABefore geschrieben
/// hat, sonst die Ausgabe AOutput des Programms.</summary>
function ShutdownLeakText(const ALogFile: string; ABefore: TDateTime; const AOutput: string): string;
begin
  Result := AOutput;
  if WrittenAt(ALogFile) > ABefore then
  begin
    Result := TFile.ReadAllText(ALogFile, TEncoding.ANSI);
  end;
end;

/// <summary>Datei AFileName löschen, Fehler übergehen (Temp-Dateien des Laufs).</summary>
procedure DeleteQuietly(const AFileName: string);
begin
  try
    if FileExists(AFileName) then
    begin
      TFile.Delete(AFileName);
    end;
  except
    on Exception do
      ;
  end;
end;

/// <summary>Leere Seitendatei des Protokolls je Test anlegen (#2168); '' wenn das nicht geht.</summary>
function PrepareSideFile(const AResultFile: string): string;
begin
  Result := TAtlasTestLog.SideFileOf(AResultFile);
  try
    TFile.WriteAllText(Result, '');
  except
    on Exception do
      Result := '';
  end;
end;

/// <summary>Bericht AResultFile, Seitendatei ASideFile ('' = ohne Protokoll je Test) und Ausgabe des Laufs ARun
/// lesen; ALeakFile und ALeakBefore für den Leckbericht am Programmende.</summary>
function ReadExeOutput(const ARun: TAtlasVcsRunResult; const AResultFile, ASideFile, ALeakFile: string;
  ALeakBefore: TDateTime): TAtlasTestsExeOutput;
var
  mText: string;
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := Default(TAtlasTestsExeOutput);
  if FileExists(AResultFile) then
  begin
    Result.Xml := TFile.ReadAllText(AResultFile, TEncoding.UTF8);
  end;
  mText := TrimRight(TEncoding.ANSI.GetString(ARun.Output));
  if ASideFile <> '' then
  begin
    Result.Output := mText;
    if FileExists(ASideFile) then
    begin
      Result.LogFile := TFile.ReadAllText(ASideFile, TEncoding.UTF8);
    end;
  end;
  mLines := TTextLines.SplitLines(mText);
  Result.LeakText := ShutdownLeakText(ALeakFile, ALeakBefore, mText);
  for mIndex := Max(0, Length(mLines) - cOutputLines) to High(mLines) do
  begin
    Result.Lines := Result.Lines + [mLines[mIndex]];
  end;
end;

/// <summary>Test-EXE von ATarget mit Bericht in einer Temp-Datei ausführen (im Thread des Laufs). Mit ALog (#2168)
/// liegt die Seitendatei des Atlas-Loggers bereit.</summary>
function RunTestExe(const AFactory: TAtlasTestsRunnerFactory; const ATarget: TAtlasTestTarget; ALog: Boolean;
  out AExe: TAtlasTestsExeOutput): TAtlasVcsRunResult;
var
  mRunner: IAtlasVcsRunner;
  mResultFile, mLeakFile, mSideFile: string;
  mLeakBefore: TDateTime;
begin
  AExe := Default(TAtlasTestsExeOutput);
  mSideFile := '';
  mLeakFile := TAtlasTestLeaks.LogFileOf(ATarget.Executable);
  mLeakBefore := WrittenAt(mLeakFile);
  mResultFile := TPath.Combine(TPath.GetTempPath, 'atlas-tests-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
  if ALog then
  begin
    mSideFile := PrepareSideFile(mResultFile);
  end;
  try
    mRunner := AFactory(
      function: Boolean
      begin
        Result := TAtlasShutdown.Signalled;
      end);
    Result := mRunner.Run(ATarget.Executable, TDUnitXCommandLine.Arguments(mResultFile, ATarget.Tests),
      ExtractFileDir(ATarget.Executable), TAtlasTestRun.cTimeoutMs);
    AExe := ReadExeOutput(Result, mResultFile, mSideFile, mLeakFile, mLeakBefore);
  except
    on E: Exception do
    begin
      Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
      AExe.Lines := [E.Message];
    end;
  end;
  DeleteQuietly(mResultFile);
  if mSideFile <> '' then
  begin
    DeleteQuietly(mSideFile);
  end;
end;

procedure TAtlasIdeTests.Execute(const ATarget: TAtlasTestTarget);
var
  mTarget: TAtlasTestTarget;
  mFactory: TAtlasTestsRunnerFactory;
  mAlive: TAlive;
  mKeep: IInterface;
  mLog: Boolean;
begin
  if (ATarget.Executable = '') or not FileExists(ATarget.Executable) then
  begin
    Refuse(FOutput, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoExe, [ProjectName(ATarget.Project),
      ATarget.Executable]));
    Exit;
  end;
  mTarget := ATarget;
  mFactory := FNewRunner;
  mAlive := FAlive;
  mKeep := FAliveRef;
  mLog := TAtlasIdeSettings.Current.TestsLog;
  FBusy := True;
  Inc(FVersion);
  FOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsStarted, [ProjectName(mTarget.Project),
    mTarget.Configuration, mTarget.Platform]));
  // Ein Thread je Lauf; der vorige ist fertig (FBusy), sein Objekt wird hier frei.
  FreeAndNil(FThread);
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      mRun: TAtlasVcsRunResult;
      mExe: TAtlasTestsExeOutput;
    begin
      mRun := RunTestExe(mFactory, mTarget, mLog, mExe);
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
              Finish(mTarget, mRun.Outcome, mRun.ExitCode, mExe);
            end);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
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

procedure TAtlasIdeTests.Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
  const AExe: TAtlasTestsExeOutput);
var
  mRun: TTestRunResult;
  mLine: string;
begin
  FBusy := False;
  Inc(FVersion);
  if AOutcome = TAtlasVcsOutcome.Cancelled then
  begin
    // Abgebrochen (Serie, #1782): Ein Lauf im Hintergrund endet ohne Bericht.
    FOutput.EndQuiet(False, Default(TTestRunResult));
    Exit;
  end;
  if AOutcome = TAtlasVcsOutcome.TimedOut then
  begin
    Refuse(FOutput, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsTimedOut, [ProjectName(ATarget.Project),
      TAtlasTestRun.cTimeoutMs div 1000]));
    Exit;
  end;
  mRun := TAtlasTestLeaks.Shown(TTestResults.Parse(AExe.Xml), TAtlasIdeSettings.Current.TestsLeaks);
  if (AOutcome <> TAtlasVcsOutcome.Ok) or not mRun.Valid then
  begin
    FOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoReport, [ProjectName(ATarget.Project), AExitCode]));
    for mLine in AExe.Lines do
    begin
      FOutput.Tell('  ' + mLine);
    end;
    FOutput.EndQuiet(False, mRun);
    Exit;
  end;
  mRun.Output := AExe.Output;
  mRun.LogFile := AExe.LogFile;
  Report(ATarget, mRun, AExe.LeakText);
end;

/// <summary>Warnungen am Methodenkopf für die bestandenen Tests mit Leck in ACases (#1774).</summary>
function LeakWarnings(const ACases: TArray<TTestCaseResult>;
  const AUnitFile: TAtlasTestUnitFile): TArray<TPair<string, TAtlasProblem>>;
begin
  Result := TAtlasTestRun.LeakProblems(TAtlasTestRun.Locate(TAtlasTestLeaks.Leaked(ACases), AUnitFile, ReadLines),
    TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsLeakProblem));
end;

/// <summary>Zeile mit Anzahl und Bytes der bestandenen Tests mit Leck in ACases; nichts ohne (#1774).</summary>
procedure TellLeaks(AOutput: TAtlasIdeTestsOutput; const ACases: TArray<TTestCaseResult>;
  const ALeakText: string);
var
  mLeaked: TArray<TTestCaseResult>;
  mSummary: string;
  mBlocks: Integer;
begin
  mLeaked := TAtlasTestLeaks.Leaked(ACases);
  if Length(mLeaked) > 0 then
  begin
    AOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsLeaksFinished, [Length(mLeaked),
      TAtlasTestLeaks.TotalBytes(mLeaked)]));
  end;
  // Lecks am Programmende (#1774): keinem Test zuzuordnen, nur mit tests.leaks.
  if (ALeakText = '') or not TAtlasIdeSettings.Current.TestsLeaks then
  begin
    Exit;
  end;
  mSummary := TAtlasTestLeaks.ShutdownSummary(ALeakText, cShutdownLeakNames, mBlocks);
  if mSummary <> '' then
  begin
    AOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsShutdownLeaks, [mBlocks, mSummary]));
  end;
end;

procedure TAtlasIdeTests.Report(const ATarget: TAtlasTestTarget; const ARun: TTestRunResult;
  const ALeakText: string);
var
  mAll: TTestRunResult;
  mFailures: TArray<TAtlasTestFailure>;
  mAtAssert: Boolean;
  mInline: string;
begin
  // Fehlschlag an der Assert-Zeile, dahinter „erwartet …, erhalten …“ (#1771).
  mAtAssert := TAtlasIdeSettings.Current.TestsFailureAtAssert;
  mInline := '';
  if mAtAssert and TAtlasIdeSettings.Current.TestsFailureInline then
  begin
    mInline := TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsInlineValues);
  end;
  FCases := TAtlasTestRun.Merged(FCases, ARun.Cases);
  if Assigned(FHooks.OnReported) then
  begin
    FHooks.OnReported(ATarget, ARun);
  end;
  // Probleme aus allen Ergebnissen dieser Sitzung: Ein Lauf einzelner Tests lässt die übrigen Fehlschläge stehen.
  mAll := ARun;
  mAll.Cases := FCases;
  mFailures := TAtlasTestRun.Failures(ARun, UnitFileFunc(ATarget.Project), ReadLines, mAtAssert);
  if Assigned(FHooks.OnProblems) then
  begin
    FHooks.OnProblems(TAtlasTestRun.Problems(TAtlasTestRun.Failures(mAll, UnitFileFunc(ATarget.Project), ReadLines,
      mAtAssert), TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblem),
      TAtlasTestsStrings.Text(TAtlasTestsTextId.TestsProblemValues), mInline) +
      LeakWarnings(mAll.Cases, UnitFileFunc(ATarget.Project)));
  end;
  FLastFailed.AddOrSetValue(AnsiLowerCase(ATarget.Project), TAtlasTestRun.SummaryOf(ATarget, ARun, mFailures,
    0).FailedTests);
  // Meldungsansicht: Zusammenfassung, dann je Fehlschlag eine Zeile, die zur Testmethode springt.
  if ARun.Total = 0 then
  begin
    FOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsNoTests, [ProjectName(ATarget.Project)]));
  end
  else
  begin
    FOutput.Tell(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.TestsFinished, [ProjectName(ATarget.Project),
      ARun.Count(TTestOutcome.Passed), ARun.Count(TTestOutcome.Failed), ARun.Count(TTestOutcome.Error),
      ARun.Count(TTestOutcome.Skipped), SecondsText(ARun.DurationMs)]));
  end;
  TellLeaks(FOutput, ARun.Cases, ALeakText);
  FOutput.Failures(mFailures);
  if Assigned(FHooks.OnFinished) then
  begin
    // Die langsamsten Tests des Laufs für die Karte Testergebnisse (#1772).
    FHooks.OnFinished(ATarget.Project, TAtlasTestRun.SummaryOf(ATarget, ARun, mFailures,
      TAtlasTestRun.Locate(TTestResults.Slowest(ARun.Cases, TAtlasProjectTests.cMaxSlowest),
      UnitFileFunc(ATarget.Project), ReadLines), TTimeZone.Local.ToUniversalTime(Now)));
  end;
  FOutput.EndQuiet(True, ARun);
end;

function TAtlasIdeTests.TallyOf(const AUnitName, AFixture: string; const AKeys: TArray<TAtlasTestKey>;
  const AStale: TAtlasTestStaleFunc): TAtlasTestTally;
begin
  Result := TAtlasTestRun.TallyOf(FCases, AUnitName, AFixture, AKeys, AStale);
end;

end.
