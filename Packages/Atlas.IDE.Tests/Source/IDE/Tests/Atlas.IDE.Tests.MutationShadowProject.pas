unit Atlas.IDE.Tests.MutationShadowProject;

// Das Schattenprojekt des Mutationslaufs (#1460) in der IDE, als
// IAtlasMutationShadowProject für den Ablauf (Atlas.Core.Tests.MutationFlow):
// - Open legt die Kopie neben dem Testprojekt an (Atlas.Core.Tests.
//   MutationShadow) und öffnet sie in der Projektgruppe; das aktive Projekt
//   bleibt das des Benutzers. Der Text der Unit kommt aus dem Editor (auch
//   ungespeichert), die übrigen Units von der Platte.
// - Geschrieben wird nur über WriteShadowFile/SaveLines, und die schreiben nur
//   in den Ordner des Schattenprojekts (TAtlasMutationShadows.IsShadowFile);
//   vor dem Anlegen prüft TAtlasMutationShadows.Separate, dass keine Datei des
//   Originals dort liegt.
// - Build baut vollständig über die Build-Pipeline (Haken OnBuild).
// - Run startet die Test-EXE in einem Thread des TAtlasWorkerSlot (Package des
//   Testmoduls). Abbrechen setzt TAtlasMutationAlive.Cancelled; der
//   Prozessläufer prüft das alle 10 ms und beendet die Test-EXE.
// - Rückrufe (Build, Thread) kommen nur, solange TAtlasMutationAlive.Alive gilt.
// Nur im Hauptthread verwenden.

interface

uses
  ToolsAPI,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.MutationShadow,
  Atlas.Core.Tests.MutationFlow,
  Atlas.IDE.Tests.Runner;

type
  /// <summary>Baut ATarget.Project vollständig mit Konfiguration und Plattform aus ATarget; False mit Grund, wenn
  /// nicht gebaut wird, sonst kommt ADone nach dem Build.</summary>
  TAtlasMutationBuildFunc = reference to function(const ATarget: TAtlasTestTarget;
    const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;

  /// <summary>Lebt, solange der Lauf lebt; Cancelled liest auch der Thread der Test-EXE.</summary>
  TAtlasMutationAlive = class(TInterfacedObject)
  private
    FAlive: Boolean;
    FCancelled: Boolean;
  public
    property Alive: Boolean read FAlive write FAlive;
    property Cancelled: Boolean read FCancelled write FCancelled;
  end;

  /// <summary>Was das Schattenprojekt vom Lauf braucht.</summary>
  TAtlasIdeMutationShadowSetup = record
    /// <summary>Testprojekt des Benutzers und sein Ziel.</summary>
    Original: IOTAProject;
    Target: TAtlasTestTarget;
    /// <summary>Die mutierte Unit.</summary>
    UnitFile: string;
    Build: TAtlasMutationBuildFunc;
    NewRunner: TAtlasTestsRunnerFactory;
    /// <summary>Gehört dem Lauf und lebt länger.</summary>
    Threads: TAtlasWorkerSlot;
    Alive: TAtlasMutationAlive;
  end;

  TAtlasIdeMutationShadowProject = class(TInterfacedObject, IAtlasMutationShadowProject)
  private
    FSetup: TAtlasIdeMutationShadowSetup;
    FAliveRef: IInterface;
    FShadow: TAtlasMutationShadow;
    FShadowTarget: TAtlasTestTarget;
    FContent: TAtlasTextFileContent;
    function Prepare(out AProblem: string): Boolean;
    function OpenInGroup(out AProblem: string): Boolean;
  public
    constructor Create(const ASetup: TAtlasIdeMutationShadowSetup);
    { IAtlasMutationShadowProject }
    function Open(out AProblem: string): Boolean;
    function Name: string;
    procedure Write(const ALines: TArray<string>);
    function Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
    procedure Run(const AExecutable: string; const ADone: TAtlasMutationRan);
    procedure Close;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  System.IOUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.VersionControl.Contract,
  Atlas.Text.DUnitX,
  Atlas.UI.Tests.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Tests.Projects;

const
  cMsPerSecond = 1000;

/// <summary>Quelle des Schattenprojekts für das Testprojekt AProject und die Unit AUnitFile.</summary>
function ShadowSource(const AProject, AUnitFile: string): TAtlasMutationShadowSource;
begin
  Result := Default(TAtlasMutationShadowSource);
  Result.ProjectFile := AProject;
  Result.Dpr := TAtlasTextFile.LoadText(ChangeFileExt(AProject, '.dpr'));
  Result.Dproj := TAtlasTextFile.LoadText(AProject);
  Result.UnitName := ChangeFileExt(ExtractFileName(AUnitFile), '');
  Result.UnitFile := AUnitFile;
  Result.Guid := TGUID.NewGuid.ToString;
  Result.ResExists := FileExists(ChangeFileExt(AProject, '.res'));
end;

/// <summary>Wirft, wenn AFileName nicht im Ordner von AShadow liegt: Der Lauf schreibt nie woanders hin.</summary>
procedure CheckShadowFile(const AShadow: TAtlasMutationShadow; const AFileName: string);
begin
  if not TAtlasMutationShadows.IsShadowFile(AShadow, AFileName) then
  begin
    raise EInOutError.Create(AFileName);
  end;
end;

/// <summary>Text AText als AFileName im Ordner von AShadow schreiben.</summary>
procedure WriteShadowFile(const AShadow: TAtlasMutationShadow; const AFileName, AText: string);
begin
  CheckShadowFile(AShadow, AFileName);
  TFile.WriteAllText(AFileName, AText, TEncoding.UTF8);
end;

/// <summary>Dateien des Schattenprojekts AShadow schreiben; vorhandene Formulardateien der Unit AUnitFile
/// daneben.</summary>
procedure WriteShadow(const AShadow: TAtlasMutationShadow; const AUnitFile: string);
var
  mCompanion, mTarget: string;
begin
  CheckShadowFile(AShadow, AShadow.UnitFile);
  ForceDirectories(ExtractFileDir(AShadow.UnitFile));
  ForceDirectories(TPath.Combine(AShadow.Folder, TAtlasMutationShadows.cDcuFolder));
  WriteShadowFile(AShadow, AShadow.DprFile, AShadow.Dpr);
  WriteShadowFile(AShadow, AShadow.DprojFile, AShadow.Dproj);
  for mCompanion in TAtlasMutationShadows.CompanionFiles(AUnitFile) do
  begin
    // Units ohne Formular haben keine; TFile.Copy würfe sonst.
    if FileExists(mCompanion) then
    begin
      mTarget := TPath.Combine(ExtractFileDir(AShadow.UnitFile), ExtractFileName(mCompanion));
      CheckShadowFile(AShadow, mTarget);
      TFile.Copy(mCompanion, mTarget, True);
    end;
  end;
end;

/// <summary>Meldung, warum sich die dpr ADpr für die Unit AUnit nicht umschreiben ließ: eigener Grund statt eines
/// Builds, der erst später scheitert.</summary>
function ShadowProblemText(const AUnit, ADpr: string; const AShadow: TAtlasMutationShadow): string;
begin
  if AShadow.Problem = TAtlasMutationShadowProblem.NoProgram then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationDprNoProgram, [AUnit, ADpr]);
  end
  else if AShadow.Problem = TAtlasMutationShadowProblem.Unclosed then
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationDprUnclosed, [ADpr, AShadow.ProblemText]);
  end
  else
  begin
    Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationDprNotRewritable, [ADpr, AShadow.ProblemText]);
  end;
end;

/// <summary>ADone als Rückruf des Builds, solange AAlive lebt; ohne Ausgabedatei die EXE des Schattenprojekts
/// ADprojFile, '' wenn es keine gibt.</summary>
function BuiltProc(AAlive: TAtlasMutationAlive; const AKeep: IInterface; const ADprojFile: string;
  const ADone: TAtlasMutationBuilt): TAtlasTestsBuildDone;
var
  mAlive: TAtlasMutationAlive;
  mKeep: IInterface;
  mDprojFile: string;
  mDone: TAtlasMutationBuilt;
begin
  mAlive := AAlive;
  mKeep := AKeep;
  mDprojFile := ADprojFile;
  mDone := ADone;
  Result :=
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    var
      mExecutable: string;
      mShadow: IOTAProject;
    begin
      if (mKeep = nil) or not mAlive.Alive then
      begin
        Exit;
      end;
      mExecutable := AOutputFile;
      if ASucceeded and (AError = '') and (mExecutable = '') then
      begin
        mShadow := TAtlasIdeTestProjects.ProjectByFile(mDprojFile);
        if mShadow <> nil then
        begin
          mExecutable := TAtlasIdeTests.TargetOf(mShadow, nil).Executable;
        end;
      end;
      if not FileExists(mExecutable) then
      begin
        mExecutable := '';
      end;
      mDone(ASucceeded, mExecutable, AError);
    end;
end;

/// <summary>Test-EXE AExecutable mit Bericht in einer Temp-Datei ausführen (im Thread des Laufs).</summary>
function RunTestExe(const AFactory: TAtlasTestsRunnerFactory; const AExecutable: string; ATimeoutMs: Cardinal;
  const ACancelled: TFunc<Boolean>; out AXml: string): TAtlasVcsRunResult;
var
  mRunner: IAtlasVcsRunner;
  mResultFile: string;
begin
  AXml := '';
  mResultFile := TPath.Combine(TPath.GetTempPath, 'atlas-mutation-' +
    TGUID.NewGuid.ToString.Replace('{', '').Replace('}', '') + '.xml');
  try
    mRunner := AFactory(ACancelled);
    Result := mRunner.Run(AExecutable, TDUnitXCommandLine.Arguments(mResultFile, nil), ExtractFileDir(AExecutable),
      ATimeoutMs);
    if FileExists(mResultFile) then
    begin
      AXml := TFile.ReadAllText(mResultFile, TEncoding.UTF8);
      TFile.Delete(mResultFile);
    end;
  except
    on Exception do
      Result := TAtlasVcsRunResult.Make(TAtlasVcsOutcome.Failed, -1, nil);
  end;
end;

/// <summary>Abbruch des Laufs, beim Entladen oder über „Mutationslauf abbrechen“.</summary>
function CancelledCheck(AAlive: TAtlasMutationAlive; const AKeep: IInterface): TFunc<Boolean>;
var
  mAlive: TAtlasMutationAlive;
  mKeep: IInterface;
begin
  mAlive := AAlive;
  mKeep := AKeep;
  Result :=
    function: Boolean
    begin
      Result := TAtlasShutdown.Signalled or (mKeep = nil) or mAlive.Cancelled;
    end;
end;

/// <summary>Thread, der AExecutable ausführt und ADone im Hauptthread ruft, solange AAlive lebt.</summary>
function RunThread(const ASetup: TAtlasIdeMutationShadowSetup; const AKeep: IInterface; const AExecutable: string;
  const ADone: TAtlasMutationRan): TThread;
var
  mFactory: TAtlasTestsRunnerFactory;
  mCancelled: TFunc<Boolean>;
  mAlive: TAtlasMutationAlive;
  mKeep: IInterface;
  mTimeoutMs: Cardinal;
  mExecutable: string;
  mDone: TAtlasMutationRan;
begin
  mFactory := ASetup.NewRunner;
  mAlive := ASetup.Alive;
  mKeep := AKeep;
  mExecutable := AExecutable;
  mDone := ADone;
  mCancelled := CancelledCheck(ASetup.Alive, AKeep);
  mTimeoutMs := Cardinal(TAtlasIdeSettings.Current.TestsMutationTimeoutSec) * cMsPerSecond;
  Result := TThread.CreateAnonymousThread(
    procedure
    var
      mResult: TAtlasVcsRunResult;
      mXml: string;
    begin
      mResult := RunTestExe(mFactory, mExecutable, mTimeoutMs, mCancelled, mXml);
      TAtlasMainThread.Queue(TAtlasFeature.Build,
        procedure
        begin
          if (mKeep = nil) or not mAlive.Alive then
          begin
            Exit;
          end;
          mDone(TAtlasMutationRunStates.FromRunner(mResult.Outcome, mResult.ExitCode), mResult.ExitCode, mXml);
        end);
    end);
end;

{ TAtlasIdeMutationShadowProject }

constructor TAtlasIdeMutationShadowProject.Create(const ASetup: TAtlasIdeMutationShadowSetup);
begin
  inherited Create;
  FSetup := ASetup;
  FAliveRef := ASetup.Alive;
end;

function TAtlasIdeMutationShadowProject.Prepare(out AProblem: string): Boolean;
var
  mUnit: string;
  mSource: TAtlasMutationShadowSource;
begin
  mUnit := ExtractFileName(FSetup.UnitFile);
  AProblem := '';
  Result := False;
  try
    FContent := TAtlasTextFile.Load(FSetup.UnitFile);
    mSource := ShadowSource(FSetup.Target.Project, FSetup.UnitFile);
    if not TAtlasMutationShadows.Build(mSource, FShadow) then
    begin
      AProblem := ShadowProblemText(mUnit, ExtractFileName(ChangeFileExt(FSetup.Target.Project, '.dpr')), FShadow);
      Exit;
    end;
    // Läge eine Datei des Originals im Schattenordner (etwa die Kopie eines früheren Laufs im Editor), schriebe der
    // Lauf genau diese Datei.
    if not TAtlasMutationShadows.Separate(mSource, FShadow) then
    begin
      AProblem := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowOverlaps, [mUnit, FShadow.Folder]);
      Exit;
    end;
    WriteShadow(FShadow, FSetup.UnitFile);
  except
    on E: Exception do
    begin
      AProblem := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowFailed, [mUnit, E.Message]);
      Exit;
    end;
  end;
  Result := True;
end;

function TAtlasIdeMutationShadowProject.OpenInGroup(out AProblem: string): Boolean;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
  mShadow: IOTAProject;
begin
  AProblem := '';
  mShadow := nil;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    // Fügt das Projekt der offenen Gruppe hinzu (Probe in der IDE); das aktive Projekt danach zurück.
    mActions.OpenProject(FShadow.DprojFile, False);
    mShadow := TAtlasIdeTestProjects.ProjectByFile(FShadow.DprojFile);
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.MainProjectGroup <> nil) and
    (FSetup.Original <> nil) then
  begin
    mModules.MainProjectGroup.ActiveProject := FSetup.Original;
  end;
  Result := mShadow <> nil;
  if not Result then
  begin
    AProblem := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowNotOpened, [FShadow.DprojFile]);
    Exit;
  end;
  FShadowTarget := TAtlasIdeTests.TargetOf(mShadow, nil);
  FShadowTarget.Configuration := FSetup.Target.Configuration;
  FShadowTarget.Platform := FSetup.Target.Platform;
end;

function TAtlasIdeMutationShadowProject.Open(out AProblem: string): Boolean;
begin
  Result := Prepare(AProblem) and OpenInGroup(AProblem);
end;

function TAtlasIdeMutationShadowProject.Name: string;
begin
  Result := FShadow.Name;
end;

procedure TAtlasIdeMutationShadowProject.Write(const ALines: TArray<string>);
var
  mContent: TAtlasTextFileContent;
begin
  CheckShadowFile(FShadow, FShadow.UnitFile);
  mContent := FContent;
  mContent.Text := string.Join(#13#10, ALines) + #13#10;
  TAtlasTextFile.Save(FShadow.UnitFile, mContent);
end;

function TAtlasIdeMutationShadowProject.Build(const ADone: TAtlasMutationBuilt; out AReason: string): Boolean;
begin
  Result := FSetup.Build(FShadowTarget, BuiltProc(FSetup.Alive, FAliveRef, FShadow.DprojFile, ADone), AReason);
end;

procedure TAtlasIdeMutationShadowProject.Run(const AExecutable: string; const ADone: TAtlasMutationRan);
begin
  // Ein Thread je Testlauf. Start gibt beendete Vorgänger frei; einer, der nach seinem Rückruf noch endet, bleibt bis
  // zum nächsten Mal im Slot, statt hier im Hauptthread auf ihn zu warten.
  FSetup.Threads.Start(RunThread(FSetup, FAliveRef, AExecutable, ADone));
end;

procedure TAtlasIdeMutationShadowProject.Close;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if (FShadow.DprojFile = '') or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  mModule := mModules.FindModule(FShadow.DprojFile);
  if mModule <> nil then
  begin
    mModule.CloseModule(True);
  end;
  if (mModules.MainProjectGroup <> nil) and (FSetup.Original <> nil) then
  begin
    mModules.MainProjectGroup.ActiveProject := FSetup.Original;
  end;
end;

end.
