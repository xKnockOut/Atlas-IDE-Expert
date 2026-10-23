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
// - Nach einem Build des Benutzers ruft die Composition BuildFinished; mit
//   „Tests nach dem Build“ laufen dann die Tests des gebauten Testprojekts
//   (ohne erneut zu bauen).
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
  Atlas.Core.Build.Messages,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Files.DataFile,
  Atlas.Core.Tests.Run,
  Atlas.Text.TestResults;

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
  /// <summary>Das gefundene bzw. gewählte Testprojekt.</summary>
  TAtlasTestsProjectProc = reference to procedure(const AProject: IOTAProject);

  TAtlasIdeTests = class
  private type
    /// <summary>Lebt, solange der Läufer lebt; Rückrufe nach dem Freigeben prüfen es.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
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
    FOnBuild: TAtlasTestsBuildFunc;
    FOnProblems: TAtlasTestsProblemsProc;
    FOnFinished: TAtlasTestsFinishedProc;
    FOnLastFailed: TFunc<string, TArray<string>>;
    FDebugging: Boolean;
    procedure SetDebugging(AValue: Boolean);
    function GetBusy: Boolean;
    procedure Start(const AProject: IOTAProject; const ATests: TArray<string>; ABuildFirst: Boolean);
    procedure Execute(const ATarget: TAtlasTestTarget);
    procedure Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
      const AXml: string; const AOutput: TArray<string>);
    procedure Merge(const ARun: TTestRunResult);
    class function ProjectByFile(const AFileName: string): IOTAProject; static;
    /// <summary>Testprojekte der Projektgruppe, die AFileName enthalten (AFileName '' = alle).</summary>
    class function TestProjects(const AFileName: string): TArray<IOTAProject>; static;
    /// <summary>Ein Kandidat: gleich; mehrere: gemerkte Wahl, sonst fragen und merken.</summary>
    procedure Choose(const ACandidates: TArray<IOTAProject>; const AThen: TAtlasTestsProjectProc);
    class function ChoiceFile: string; static;
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
    /// <summary>Ein Build ist fertig (Meldungen gelesen): mit „Tests nach dem Build“ laufen die Tests.</summary>
    procedure BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
      const AMessages: TArray<TAtlasCompilerMessage>);
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
    property OnBuild: TAtlasTestsBuildFunc read FOnBuild write FOnBuild;
    property OnProblems: TAtlasTestsProblemsProc read FOnProblems write FOnProblems;
    property OnFinished: TAtlasTestsFinishedProc read FOnFinished write FOnFinished;
    property OnLastFailed: TFunc<string, TArray<string>> read FOnLastFailed write FOnLastFailed;
  end;

implementation

uses
  System.IOUtils,
  System.Math,
  System.DateUtils,
  System.Types,
  Vcl.Forms,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Tests.ProjectChoice,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Files.TextFile,
  Atlas.UI.Strings,
  Atlas.UI.Commands.Palette,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Files,
  Atlas.IDE.Foundation.Settings,
  Atlas.Text.Lines,
  Atlas.Text.DUnitX;

const
  MessageGroup = 'Atlas';
  /// <summary>So viele letzte Zeilen der Ausgabe zeigt die Meldung „kein Bericht“.</summary>
  OutputLines = 5;

/// <summary>Zeilen einer Datei: offener Puffer, sonst die Platte.</summary>
function ReadLines(const AFileName: string; out ALines: TArray<string>): Boolean;
var
  Buffer: IOTAEditBuffer;
  Text: string;
begin
  ALines := nil;
  Buffer := TAtlasIdeFiles.BufferOf(AFileName);
  if Buffer <> nil then
    Text := TAtlasEditorBuffer.Text(Buffer)
  else
  begin
    if not FileExists(AFileName) then
      Exit(False);
    try
      Text := TAtlasTextFile.Load(AFileName).Text;
    except
      on Exception do
        Exit(False);
    end;
  end;
  ALines := TTextLines.SplitLines(Text);
  Result := True;
end;

function IsTestProject(const AProject: IOTAProject): Boolean;
var
  Lines: TArray<string>;
begin
  Result := (AProject <> nil) and (AProject.FileName <> '') and
    ReadLines(ChangeFileExt(AProject.FileName, '.dpr'), Lines) and TAtlasTestRun.IsTestProgram(Lines);
end;

function ProjectName(const AFileName: string): string;
begin
  Result := ChangeFileExt(ExtractFileName(AFileName), '');
end;

function SecondsText(AMs: Int64): string;
begin
  Result := FormatFloat('0.00', AMs / 1000, FormatSettings);
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
    Exit;
  Group := Messages.GetGroup(MessageGroup);
  if Group = nil then
    Group := Messages.AddMessageGroup(MessageGroup);
  Messages.AddTitleMessage(AText, Group);
end;

class function TAtlasIdeTests.ProjectByFile(const AFileName: string): IOTAProject;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
    if (Group.Projects[Index] <> nil) and (SameText(Group.Projects[Index].FileName, AFileName) or
      (Group.Projects[Index].FindModuleInfo(AFileName) <> nil)) and IsTestProject(Group.Projects[Index]) then
      Exit(Group.Projects[Index]);
end;

class function TAtlasIdeTests.TestProjects(const AFileName: string): TArray<IOTAProject>;
var
  Services: IOTAModuleServices;
  Group: IOTAProjectGroup;
  Index: Integer;
  Project: IOTAProject;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  Group := Services.MainProjectGroup;
  if Group = nil then
    Exit;
  for Index := 0 to Group.ProjectCount - 1 do
  begin
    Project := Group.Projects[Index];
    if (Project = nil) or ((AFileName <> '') and not SameText(Project.FileName, AFileName) and
      (Project.FindModuleInfo(AFileName) = nil)) then
      Continue;
    if IsTestProject(Project) then
      Result := Result + [Project];
  end;
end;

class function TAtlasIdeTests.ChoiceFile: string;
begin
  Result := TPath.Combine(TPath.Combine(GetEnvironmentVariable('LOCALAPPDATA'), 'Atlas'),
    TAtlasTestProjectChoices.FileName);
end;

procedure TAtlasIdeTests.ResolveProject(const AFileName: string; const AThen: TAtlasTestsProjectProc);
var
  Found: TArray<IOTAProject>;
begin
  Found := nil;
  // Testunit der Code Lens bzw. am Cursor: ihre Testprojekte.
  if AFileName <> '' then
    Found := TestProjects(AFileName);
  if Length(Found) = 0 then
  begin
    if IsTestProject(GetActiveProject) then
    begin
      AThen(GetActiveProject);
      Exit;
    end;
    Found := TestProjects('');
  end;
  if Length(Found) = 0 then
  begin
    Say(TAtlasStrings.Text(TAtlasTextId.TestsNoProject));
    Exit;
  end;
  Choose(Found, AThen);
end;

procedure TAtlasIdeTests.Choose(const ACandidates: TArray<IOTAProject>; const AThen: TAtlasTestsProjectProc);
var
  Files: TArray<string>;
  Choices: TArray<TAtlasTestProjectChoice>;
  Index: Integer;
  Commands: TArray<TAtlasCommand>;
  Command: TAtlasCommand;
  Window: TAtlasPaletteWindow;
  Area: TRect;
  Alive: TAlive;
  Keep: IInterface;
begin
  Files := nil;
  for Index := 0 to High(ACandidates) do
    Files := Files + [ACandidates[Index].FileName];
  Choices := TAtlasTestProjectChoices.Load(ChoiceFile);
  Index := TAtlasTestProjectChoices.Pick(Choices, Files);
  if Index >= 0 then
  begin
    AThen(ACandidates[Index]);
    Exit;
  end;
  // Einmal fragen; die Wahl gilt danach für genau diese Kandidaten.
  Commands := nil;
  for Index := 0 to High(Files) do
  begin
    Command := Default(TAtlasCommand);
    Command.Id := IntToStr(Index);
    Command.Caption := ProjectName(Files[Index]);
    Command.Path := ExtractFileDir(Files[Index]);
    Command.Description := Files[Index];
    Commands := Commands + [Command];
  end;
  Alive := FAlive;
  Keep := FAliveRef;
  Window := TAtlasPaletteWindow.CreatePalette(Application, Commands, nil, TAtlasIdeStyle.Colors);
  Window.KeepOrder := True;
  Window.Prompt := TAtlasStrings.Text(TAtlasTextId.TestsChooseProject);
  Window.OnExecute :=
    procedure(ACommand: TAtlasCommand)
    var
      Chosen: Integer;
    begin
      Chosen := StrToIntDef(ACommand.Id, -1);
      if (Keep = nil) or not Alive.Alive or (Chosen < 0) or (Chosen > High(Files)) then
        Exit;
      TAtlasGuard.Run(TAtlasFeature.Build,
        procedure
        var
          Project: IOTAProject;
          Stored: TArray<TAtlasTestProjectChoice>;
        begin
          // Das Projekt kann inzwischen geschlossen sein.
          Project := ProjectByFile(Files[Chosen]);
          if Project = nil then
          begin
            Say(TAtlasStrings.Text(TAtlasTextId.TestsNoProject));
            Exit;
          end;
          // Gesperrt gelesene Datei nicht mit dieser einen Wahl überschreiben (Bericht N3).
          if TAtlasDataFile.Writable(TAtlasTestProjectChoices.Load(ChoiceFile, Stored)) then
          begin
            TAtlasTestProjectChoices.Remember(Stored, Files, Project.FileName);
            if not TAtlasTestProjectChoices.Save(ChoiceFile, Stored) then
              Say(TAtlasStrings.Text(TAtlasTextId.TestsChoiceSaveFailed));
          end
          else
            Say(TAtlasStrings.Text(TAtlasTextId.TestsChoiceSaveFailed));
          AThen(Project);
        end);
    end;
  if Screen.ActiveForm <> nil then
    Area := Screen.ActiveForm.BoundsRect
  else if Application.MainForm <> nil then
    Area := Application.MainForm.BoundsRect
  else
    Area := Screen.WorkAreaRect;
  Window.ShowOver(Area);
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
    for Index := 0 to Project.GetModuleCount - 1 do
    begin
      FileName := Project.GetModule(Index).FileName;
      if SameText(ExtractFileExt(FileName), '.pas') and SameText(ProjectName(FileName), AUnitName) then
        Exit(FileName);
    end;
  // Nicht im Projekt eingetragen: neben der .dproj.
  FileName := TPath.Combine(ExtractFileDir(AProjectFile), AUnitName + '.pas');
  if FileExists(FileName) then
    Result := FileName;
end;

procedure TAtlasIdeTests.RunAll;
begin
  if not TAtlasIdeSettings.Current.TestRun then
    Exit;
  ResolveProject('',
    procedure(const AProject: IOTAProject)
    begin
      Start(AProject, nil, TAtlasIdeSettings.Current.TestsBuildFirst);
    end);
end;

procedure TAtlasIdeTests.RunFailed;
begin
  if not TAtlasIdeSettings.Current.TestRun then
    Exit;
  ResolveProject('',
    procedure(const AProject: IOTAProject)
    var
      Tests: TArray<string>;
    begin
      if not FLastFailed.TryGetValue(AnsiLowerCase(AProject.FileName), Tests) and Assigned(FOnLastFailed) then
        Tests := FOnLastFailed(AProject.FileName);
      if Length(Tests) = 0 then
      begin
        Say(TAtlasStrings.Fmt(TAtlasTextId.TestsNoFailed, [ProjectName(AProject.FileName)]));
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
    Exit;
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
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonTestsOff);
    Exit;
  end;
  if Busy then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsBusy);
    Exit;
  end;
  Project := ProjectByFile(AProject);
  if Project = nil then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.WelcomeQuickReasonNotOpened);
    Exit;
  end;
  Start(Project, nil, True);
  Result := True;
end;

procedure TAtlasIdeTests.BuildFinished(const AProject: TAtlasCompileProject; ASucceeded: Boolean;
  const AMessages: TArray<TAtlasCompilerMessage>);
var
  Project: IOTAProject;
begin
  if Busy or (AProject.FileName = '') or AProject.Background or (AProject.RequestedBy <> '') then
    Exit;
  Project := ProjectByFile(AProject.FileName);
  if not TAtlasTestRun.ShouldRunAfterBuild(TAtlasIdeSettings.Current, ASucceeded, AProject.Background,
    AProject.RequestedBy, TAtlasTestRun.WarningsAndHints(AMessages), Project <> nil) then
    Exit;
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
    Result.Executable := Options.TargetName;
end;

function TAtlasIdeTests.CanBuild: Boolean;
begin
  Result := Assigned(FOnBuild);
end;

function TAtlasIdeTests.BuildProject(const AProject: string; const ADone: TAtlasTestsBuildDone;
  out AReason: string): Boolean;
begin
  AReason := '';
  Result := Assigned(FOnBuild) and FOnBuild(AProject, ADone, AReason);
end;

procedure TAtlasIdeTests.ReportRun(const ATarget: TAtlasTestTarget; const AXml: string);
begin
  if Trim(AXml) = '' then
    Exit;
  Finish(ATarget, TAtlasVcsOutcome.Ok, 0, AXml, nil);
end;

function TAtlasIdeTests.GetBusy: Boolean;
begin
  Result := FBusy or FDebugging;
end;

procedure TAtlasIdeTests.SetDebugging(AValue: Boolean);
begin
  if FDebugging = AValue then
    Exit;
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
    Say(TAtlasStrings.Text(TAtlasTextId.TestsBusy));
    Exit;
  end;
  Target := TargetOf(AProject, ATests);
  if not TAtlasTestRun.CanRun(Target.Platform) then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsPlatform, [ProjectName(Target.Project), Target.Platform]));
    Exit;
  end;
  if not ABuildFirst or not Assigned(FOnBuild) then
  begin
    Execute(Target);
    Exit;
  end;
  FBusy := True;
  Inc(FVersion);
  Alive := FAlive;
  Keep := FAliveRef;
  if not FOnBuild(Target.Project,
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      // Keep hält den Merker am Leben, auch wenn der Läufer schon frei ist.
      if (Keep = nil) or not Alive.Alive then
        Exit;
      FBusy := False;
      Inc(FVersion);
      if AError <> '' then
        Say(TAtlasStrings.Fmt(TAtlasTextId.TestsBuildRefused, [ProjectName(Target.Project), AError]))
      else if not ASucceeded then
        Say(TAtlasStrings.Fmt(TAtlasTextId.TestsBuildFailed, [ProjectName(Target.Project)]))
      else
      begin
        if AOutputFile <> '' then
          Target.Executable := AOutputFile;
        Execute(Target);
      end;
    end, Reason) then
  begin
    FBusy := False;
    Inc(FVersion);
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsBuildRefused, [ProjectName(Target.Project), Reason]));
  end;
end;

procedure TAtlasIdeTests.Execute(const ATarget: TAtlasTestTarget);
var
  Target: TAtlasTestTarget;
  Factory: TAtlasTestsRunnerFactory;
  Alive: TAlive;
  Keep: IInterface;
begin
  if (ATarget.Executable = '') or not FileExists(ATarget.Executable) then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsNoExe, [ProjectName(ATarget.Project), ATarget.Executable]));
    Exit;
  end;
  Target := ATarget;
  Factory := FNewRunner;
  Alive := FAlive;
  Keep := FAliveRef;
  FBusy := True;
  Inc(FVersion);
  Say(TAtlasStrings.Fmt(TAtlasTextId.TestsStarted, [ProjectName(Target.Project), Target.Configuration,
    Target.Platform]));
  // Ein Thread je Lauf; der vorige ist fertig (FBusy), sein Objekt wird hier frei.
  FreeAndNil(FThread);
  FThread := TThread.CreateAnonymousThread(
    procedure
    var
      Runner: IAtlasVcsRunner;
      Run: TAtlasVcsRunResult;
      ResultFile, Xml: string;
      Output: TArray<string>;
      Lines: TArray<string>;
      Index: Integer;
    begin
      Xml := '';
      Output := nil;
      ResultFile := TPath.Combine(TPath.GetTempPath, 'atlas-tests-' +
        TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
      try
        Runner := Factory(
          function: Boolean
          begin
            Result := TAtlasShutdown.Signalled;
          end);
        Run := Runner.Run(Target.Executable, TDUnitXCommandLine.Arguments(ResultFile, Target.Tests),
          ExtractFileDir(Target.Executable), TAtlasTestRun.TimeoutMs);
        if FileExists(ResultFile) then
          Xml := TFile.ReadAllText(ResultFile, TEncoding.UTF8);
        Lines := TTextLines.SplitLines(TrimRight(TEncoding.ANSI.GetString(Run.Output)));
        for Index := Max(0, Length(Lines) - OutputLines) to High(Lines) do
          Output := Output + [Lines[Index]];
      except
        on E: Exception do
        begin
          Run := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
          Output := [E.Message];
        end;
      end;
      try
        if FileExists(ResultFile) then
          TFile.Delete(ResultFile);
      except
        on Exception do
          ;
      end;
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          if (Keep = nil) or not Alive.Alive then
            Exit;
          TAtlasGuard.Run(TAtlasFeature.Build,
            procedure
            begin
              Finish(Target, Run.Outcome, Run.ExitCode, Xml, Output);
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
      if SameText(Fresh.FullName, Item.FullName) then
        Replaced := True;
    if not Replaced then
      Kept := Kept + [Item];
  end;
  FCases := Kept + ARun.Cases;
end;

procedure TAtlasIdeTests.Finish(const ATarget: TAtlasTestTarget; AOutcome: TAtlasVcsOutcome; AExitCode: Integer;
  const AXml: string; const AOutput: TArray<string>);
var
  Run, All: TTestRunResult;
  Failures: TArray<TAtlasTestFailure>;
  Failure: TAtlasTestFailure;
  Messages: IOTAMessageServices;
  Group: IOTAMessageGroup;
  LineRef: Pointer;
  Line: string;
  ProjectFile: string;
begin
  FBusy := False;
  Inc(FVersion);
  if AOutcome = TAtlasVcsOutcome.Cancelled then
    Exit;
  if AOutcome = TAtlasVcsOutcome.TimedOut then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsTimedOut, [ProjectName(ATarget.Project),
      TAtlasTestRun.TimeoutMs div 1000]));
    Exit;
  end;
  Run := TTestResults.Parse(AXml);
  if (AOutcome <> TAtlasVcsOutcome.Ok) or not Run.Valid then
  begin
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsNoReport, [ProjectName(ATarget.Project), AExitCode]));
    for Line in AOutput do
      Say('  ' + Line);
    Exit;
  end;
  ProjectFile := ATarget.Project;
  Merge(Run);
  // Probleme aus allen Ergebnissen dieser Sitzung: Ein Lauf einzelner Tests lässt die übrigen Fehlschläge stehen.
  All := Run;
  All.Cases := FCases;
  Failures := TAtlasTestRun.Failures(Run,
    function(const AUnitName: string): string
    begin
      Result := UnitFileOf(ProjectFile, AUnitName);
    end, ReadLines);
  if Assigned(FOnProblems) then
    FOnProblems(TAtlasTestRun.Problems(TAtlasTestRun.Failures(All,
      function(const AUnitName: string): string
      begin
        Result := UnitFileOf(ProjectFile, AUnitName);
      end, ReadLines), TAtlasStrings.Text(TAtlasTextId.TestsProblem),
      TAtlasStrings.Text(TAtlasTextId.TestsProblemValues)));
  FLastFailed.AddOrSetValue(AnsiLowerCase(ATarget.Project), TAtlasTestRun.SummaryOf(ATarget, Run, Failures,
    0).FailedTests);
  // Meldungsansicht: Zusammenfassung, dann je Fehlschlag eine Zeile, die zur Testmethode springt.
  if Run.Total = 0 then
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsNoTests, [ProjectName(ATarget.Project)]))
  else
    Say(TAtlasStrings.Fmt(TAtlasTextId.TestsFinished, [ProjectName(ATarget.Project),
      Run.Count(TTestOutcome.Passed), Run.Count(TTestOutcome.Failed), Run.Count(TTestOutcome.Error),
      Run.Count(TTestOutcome.Skipped), SecondsText(Run.DurationMs)]));
  if (Length(Failures) > 0) and Supports(BorlandIDEServices, IOTAMessageServices, Messages) then
  begin
    Group := Messages.GetGroup(MessageGroup);
    if Group = nil then
      Group := Messages.AddMessageGroup(MessageGroup);
    for Failure in Failures do
      if Failure.FileName <> '' then
        Messages.AddToolMessage(Failure.FileName, TAtlasTestRun.ProblemText(Failure.Test,
          TAtlasStrings.Text(TAtlasTextId.TestsProblem), TAtlasStrings.Text(TAtlasTextId.TestsProblemValues)),
          'DUnitX', Failure.Line + 1, Failure.StartCharacter + 1, nil, LineRef, Group)
      else
        Messages.AddTitleMessage('  ' + TAtlasTestRun.ProblemText(Failure.Test,
          TAtlasStrings.Text(TAtlasTextId.TestsProblem), TAtlasStrings.Text(TAtlasTextId.TestsProblemValues)),
          Group);
  end;
  if Assigned(FOnFinished) then
    FOnFinished(ATarget.Project, TAtlasTestRun.SummaryOf(ATarget, Run, Failures,
      TTimeZone.Local.ToUniversalTime(Now)));
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
