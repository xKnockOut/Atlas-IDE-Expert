unit Atlas.IDE.Tests.Mutation;

// Mutationslauf in der IDE (#1460, tests.mutation, experimentell):
// - Befehle „Mutationen der Methode prüfen“ (Methode am Cursor bzw. an der
//   zuletzt rechts geklickten Zeile der Rinne), „… der Unit“ und
//   „… geänderter Methoden“ (Routinen ohne gültiges Ergebnis).
// - Ablauf im Hauptthread: Testprojekt wie „Tests ausführen“ wählen,
//   Mutanten beim Server erfragen (atlas.server.mutants mit den Operatoren
//   aus tests.mutation.operators), auswählen (Atlas.Core.Tests.MutationPlan),
//   Schattenprojekt neben dem Testprojekt anlegen (Atlas.Core.Tests.
//   MutationShadow) und in der Projektgruppe öffnen; das aktive Projekt
//   bleibt das des Benutzers. Erst laufen die Tests gegen die unveränderte
//   Kopie (sonst ist jedes Ergebnis wertlos), dann je Mutant: Kopie
//   schreiben, Schattenprojekt vollständig bauen (Build-Pipeline, Haken
//   OnBuild), Test-EXE im eigenen Thread mit Zeitlimit
//   tests.mutation.timeoutSec ausführen, Ausgang festhalten.
// - Original und seine DCUs bleiben unberührt; der Text der Unit kommt aus
//   dem Editor (auch ungespeichert), die übrigen Units von der Platte.
// - Am Ende (oder nach „Mutationslauf abbrechen“) schließt der Lauf das
//   Schattenprojekt, merkt die Ergebnisse vollständig geprüfter Routinen in
//   .atlas-local\mutation\results.json des Testprojekts und meldet in der
//   Meldungsansicht Zahlen, Mutation-Score und je überlebendem Mutanten eine
//   anklickbare Zeile. Die Rinne (Atlas.IDE.Tests.MutationMarks) zeigt die
//   Ergebnisse, solange die Routine unverändert ist.
// Rückrufe (Server, Build, Thread) prüfen über TAlive, ob der Lauf noch lebt.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Tests.Run,
  Atlas.Core.Tests.MutationShadow,
  Atlas.Core.Tests.MutationResults,
  Atlas.Core.Tests.MutationPlan,
  Atlas.IDE.Tests.Runner,
  Atlas.IDE.Tests.Output;

type
  /// <summary>Baut ATarget.Project vollständig mit Konfiguration und Plattform aus ATarget; False mit Grund, wenn
  /// nicht gebaut wird, sonst kommt ADone nach dem Build.</summary>
  TAtlasMutationBuildFunc = reference to function(const ATarget: TAtlasTestTarget;
    const ADone: TAtlasTestsBuildDone; out AReason: string): Boolean;

  TAtlasIdeMutationRun = class
  private type
    /// <summary>Lebt, solange der Lauf lebt; Cancelled liest auch der Thread der Test-EXE.</summary>
    TAlive = class(TInterfacedObject)
    public
      Alive: Boolean;
      Cancelled: Boolean;
    end;
    /// <summary>Ein laufender Mutationslauf.</summary>
    TState = record
      Active: Boolean;
      Scope: TAtlasMutationScope;
      FileName: string;
      Line: Integer;
      Lines: TArray<string>;
      Content: TAtlasTextFileContent;
      Original: IOTAProject;
      Target: TAtlasTestTarget;
      Shadow: TAtlasMutationShadow;
      ShadowTarget: TAtlasTestTarget;
      Jobs: TArray<TAtlasMutationJob>;
      Outcomes: TArray<TAtlasMutationOutcome>;
      /// <summary>-1 = Lauf ohne Mutation, sonst Index in Jobs.</summary>
      Position: Integer;
      StartedAt: UInt64;
    end;
  private const
    cServerTimeoutMs = 60000;
    cMsPerSecond = 1000;
  private class var
    FCurrent: TAtlasIdeMutationRun;
  private
    FScope: IAtlasModuleScope;
    FTests: TAtlasIdeTests;
    FOutput: TAtlasIdeTestsOutput;
    FNewRunner: TAtlasTestsRunnerFactory;
    FBuild: TAtlasMutationBuildFunc;
    FAlive: TAlive;
    FAliveRef: IInterface;
    FThread: TThread;
    FResults: TAtlasMutationResults;
    FResultsProject: string;
    FVersion: Integer;
    FState: TState;
    procedure ProjectChosen(const AProject: IOTAProject);
    procedure Answered(const AJson: string);
    function PrepareShadow: Boolean;
    function OpenShadow: Boolean;
    procedure CloseShadow;
    procedure Step;
    procedure Built(ASucceeded: Boolean; const AOutputFile, AError: string);
    procedure RunExe(const AExecutable: string);
    procedure Ran(ATimedOut: Boolean; AExitCode: Integer; const AXml: string);
    procedure Rate(AStatus: TAtlasMutationStatus; const ABy: string);
    procedure Advance;
    procedure Finish(ACancelled: Boolean);
    procedure StopWith(const AText: string);
    procedure Remember;
    procedure LoadResults(const AProject: string);
    procedure SaveResults;
    function Done: Integer;
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
  System.IOUtils,
  System.DateUtils,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Shutdown,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.VersionControl.Contract,
  Atlas.Text.DUnitX,
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
function ChosenProc(ARun: TAtlasIdeMutationRun; AAlive: TAtlasIdeMutationRun.TAlive;
  const AKeep: IInterface): TAtlasTestsProjectProc;
var
  mRun: TAtlasIdeMutationRun;
  mAlive: TAtlasIdeMutationRun.TAlive;
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
function AnswerProc(ARun: TAtlasIdeMutationRun; AAlive: TAtlasIdeMutationRun.TAlive;
  const AKeep: IInterface): TProc<string>;
var
  mRun: TAtlasIdeMutationRun;
  mAlive: TAtlasIdeMutationRun.TAlive;
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

/// <summary>Rückruf des Builds, solange der Lauf lebt.</summary>
function BuiltProc(ARun: TAtlasIdeMutationRun; AAlive: TAtlasIdeMutationRun.TAlive;
  const AKeep: IInterface): TAtlasTestsBuildDone;
var
  mRun: TAtlasIdeMutationRun;
  mAlive: TAtlasIdeMutationRun.TAlive;
  mKeep: IInterface;
begin
  mRun := ARun;
  mAlive := AAlive;
  mKeep := AKeep;
  Result :=
    procedure(ASucceeded: Boolean; const AOutputFile, AError: string)
    begin
      if (mKeep <> nil) and mAlive.Alive then
      begin
        mRun.Built(ASucceeded, AOutputFile, AError);
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
  FAlive := TAlive.Create;
  FAlive.Alive := True;
  FAliveRef := FAlive;
  FResults := TAtlasMutationResults.Create;
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
  if FThread <> nil then
  begin
    // Der Prozessläufer beendet die Test-EXE, sobald sein Thread endet.
    FThread.Terminate;
    FThread.WaitFor;
    FreeAndNil(FThread);
  end;
  if FState.Active then
  begin
    CloseShadow;
  end;
  FResults.Free;
  FAliveRef := nil;
  TAtlasIdeGutterMarks.Invalidate;
  inherited Destroy;
end;

function TAtlasIdeMutationRun.Running: Boolean;
begin
  Result := FState.Active;
end;

procedure TAtlasIdeMutationRun.Cancel;
begin
  if FState.Active then
  begin
    FAlive.Cancelled := True;
  end;
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
begin
  mUnit := ExtractFileName(FState.FileName);
  if not TAtlasMutants.Parse(AJson, mList) then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationServerFailed, [mUnit]));
    Exit;
  end;
  FState.Jobs := TAtlasMutationPlan.Select(mList, FState.Scope, FState.Line, FState.FileName, FState.Lines,
    FResults);
  if Length(FState.Jobs) = 0 then
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
  SetLength(FState.Outcomes, Length(FState.Jobs));
  if not PrepareShadow then
  begin
    Exit;
  end;
  FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStarted, [Length(FState.Jobs), mUnit,
    ProjectName(FState.Target.Project), FState.Target.Configuration, FState.Target.Platform]));
  FOutput.Say(TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationBaseline));
  FState.Position := -1;
  Step;
end;

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

/// <summary>Dateien des Schattenprojekts AShadow schreiben; Formulardateien der Unit AUnitFile daneben.</summary>
procedure WriteShadow(const AShadow: TAtlasMutationShadow; const AUnitFile: string);
var
  mCompanion: string;
begin
  ForceDirectories(ExtractFileDir(AShadow.UnitFile));
  ForceDirectories(TPath.Combine(AShadow.Folder, TAtlasMutationShadows.cDcuFolder));
  TFile.WriteAllText(AShadow.DprFile, AShadow.Dpr, TEncoding.UTF8);
  TFile.WriteAllText(AShadow.DprojFile, AShadow.Dproj, TEncoding.UTF8);
  for mCompanion in TAtlasMutationShadows.CompanionFiles(AUnitFile) do
  begin
    TFile.Copy(mCompanion, TPath.Combine(ExtractFileDir(AShadow.UnitFile), ExtractFileName(mCompanion)), True);
  end;
end;

function TAtlasIdeMutationRun.PrepareShadow: Boolean;
var
  mUnit: string;
begin
  mUnit := ExtractFileName(FState.FileName);
  Result := False;
  try
    FState.Content := TAtlasTextFile.Load(FState.FileName);
    if not TAtlasMutationShadows.Build(ShadowSource(FState.Target.Project, FState.FileName), FState.Shadow) then
    begin
      StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowFailed, [mUnit,
        ExtractFileName(ChangeFileExt(FState.Target.Project, '.dpr'))]));
      Exit;
    end;
    WriteShadow(FState.Shadow, FState.FileName);
  except
    on E: Exception do
    begin
      StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowFailed, [mUnit, E.Message]));
      Exit;
    end;
  end;
  Result := OpenShadow;
end;

function TAtlasIdeMutationRun.OpenShadow: Boolean;
var
  mActions: IOTAActionServices;
  mModules: IOTAModuleServices;
  mShadow: IOTAProject;
begin
  mShadow := nil;
  if Supports(BorlandIDEServices, IOTAActionServices, mActions) then
  begin
    // Fügt das Projekt der offenen Gruppe hinzu (Probe in der IDE); das aktive Projekt danach zurück.
    mActions.OpenProject(FState.Shadow.DprojFile, False);
    mShadow := TAtlasIdeTestProjects.ProjectByFile(FState.Shadow.DprojFile);
  end;
  if Supports(BorlandIDEServices, IOTAModuleServices, mModules) and (mModules.MainProjectGroup <> nil) and
    (FState.Original <> nil) then
  begin
    mModules.MainProjectGroup.ActiveProject := FState.Original;
  end;
  Result := mShadow <> nil;
  if not Result then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowNotOpened, [FState.Shadow.DprojFile]));
    Exit;
  end;
  FState.ShadowTarget := TAtlasIdeTests.TargetOf(mShadow, nil);
  FState.ShadowTarget.Configuration := FState.Target.Configuration;
  FState.ShadowTarget.Platform := FState.Target.Platform;
end;

procedure TAtlasIdeMutationRun.CloseShadow;
var
  mModules: IOTAModuleServices;
  mModule: IOTAModule;
begin
  if (FState.Shadow.DprojFile = '') or not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  try
    mModule := mModules.FindModule(FState.Shadow.DprojFile);
    if mModule <> nil then
    begin
      mModule.CloseModule(True);
    end;
    if (mModules.MainProjectGroup <> nil) and (FState.Original <> nil) then
    begin
      mModules.MainProjectGroup.ActiveProject := FState.Original;
    end;
  except
    on E: Exception do
      FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowNotOpened, [E.Message]));
  end;
end;

/// <summary>AContent mit den Zeilen ALines (CRLF) als AFileName speichern.</summary>
procedure SaveLines(const AFileName: string; const AContent: TAtlasTextFileContent; const ALines: TArray<string>);
var
  mContent: TAtlasTextFileContent;
begin
  mContent := AContent;
  mContent.Text := string.Join(#13#10, ALines) + #13#10;
  TAtlasTextFile.Save(AFileName, mContent);
end;

procedure TAtlasIdeMutationRun.Step;
var
  mLines: TArray<string>;
  mReason: string;
begin
  if FAlive.Cancelled then
  begin
    Finish(True);
    Exit;
  end;
  mLines := FState.Lines;
  if (FState.Position >= 0) and
    not TAtlasMutants.Apply(FState.Lines, FState.Jobs[FState.Position].Mutant, mLines) then
  begin
    Rate(TAtlasMutationStatus.Invalid, '');
    Exit;
  end;
  try
    SaveLines(FState.Shadow.UnitFile, FState.Content, mLines);
  except
    on E: Exception do
    begin
      StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationShadowFailed, [ExtractFileName(FState.FileName),
        E.Message]));
      Exit;
    end;
  end;
  FState.StartedAt := TThread.GetTickCount64;
  if not FBuild(FState.ShadowTarget, BuiltProc(Self, FAlive, FAliveRef), mReason) then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBuildRefused, [FState.Shadow.Name, mReason]));
  end;
end;

procedure TAtlasIdeMutationRun.Built(ASucceeded: Boolean; const AOutputFile, AError: string);
var
  mExecutable: string;
  mShadow: IOTAProject;
begin
  if AError <> '' then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBuildRefused, [FState.Shadow.Name, AError]));
    Exit;
  end;
  if not ASucceeded then
  begin
    Rate(TAtlasMutationStatus.BuildFailed, '');
    Exit;
  end;
  mExecutable := AOutputFile;
  if mExecutable = '' then
  begin
    mShadow := TAtlasIdeTestProjects.ProjectByFile(FState.Shadow.DprojFile);
    if mShadow <> nil then
    begin
      mExecutable := TAtlasIdeTests.TargetOf(mShadow, nil).Executable;
    end;
  end;
  if (mExecutable = '') or not FileExists(mExecutable) then
  begin
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationNoExe, [FState.Shadow.Name]));
    Exit;
  end;
  RunExe(mExecutable);
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
function CancelledCheck(AAlive: TAtlasIdeMutationRun.TAlive; const AKeep: IInterface): TFunc<Boolean>;
var
  mAlive: TAtlasIdeMutationRun.TAlive;
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

procedure TAtlasIdeMutationRun.RunExe(const AExecutable: string);
var
  mFactory: TAtlasTestsRunnerFactory;
  mCancelled: TFunc<Boolean>;
  mAlive: TAlive;
  mKeep: IInterface;
  mRun: TAtlasIdeMutationRun;
  mTimeoutMs: Cardinal;
  mExecutable: string;
begin
  mFactory := FNewRunner;
  mAlive := FAlive;
  mKeep := FAliveRef;
  mRun := Self;
  mExecutable := AExecutable;
  mCancelled := CancelledCheck(FAlive, FAliveRef);
  mTimeoutMs := Cardinal(TAtlasIdeSettings.Current.TestsMutationTimeoutSec) * cMsPerSecond;
  // Ein Thread je Testlauf; der vorige ist fertig, sein Objekt wird hier frei.
  FreeAndNil(FThread);
  FThread := TThread.CreateAnonymousThread(
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
          if mResult.Outcome = TAtlasVcsOutcome.Cancelled then
          begin
            mRun.Finish(True);
            Exit;
          end;
          mRun.Ran(mResult.Outcome = TAtlasVcsOutcome.TimedOut, mResult.ExitCode, mXml);
        end);
    end);
  FThread.FreeOnTerminate := False;
  FThread.Start;
end;

procedure TAtlasIdeMutationRun.Ran(ATimedOut: Boolean; AExitCode: Integer; const AXml: string);
var
  mBy: string;
  mStatus: TAtlasMutationStatus;
begin
  mStatus := TAtlasMutationPlan.StatusOf(ATimedOut, AExitCode, AXml, mBy);
  if (FState.Position < 0) and (mStatus <> TAtlasMutationStatus.Survived) then
  begin
    // Rot oder nicht bewertbar schon ohne Mutation: Jeder Mutant wäre „erkannt“.
    StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBaselineFailed, [ProjectName(FState.Target.Project),
      StatusText(mStatus, mBy)]));
    Exit;
  end;
  Rate(mStatus, mBy);
end;

procedure TAtlasIdeMutationRun.Rate(AStatus: TAtlasMutationStatus; const ABy: string);
var
  mJob: TAtlasMutationJob;
  mOutcome: TAtlasMutationOutcome;
begin
  if FState.Position < 0 then
  begin
    if AStatus = TAtlasMutationStatus.BuildFailed then
    begin
      StopWith(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationBaselineFailed,
        [ProjectName(FState.Target.Project), StatusText(AStatus, ABy)]));
      Exit;
    end;
    Advance;
    Exit;
  end;
  mJob := FState.Jobs[FState.Position];
  mOutcome := Default(TAtlasMutationOutcome);
  mOutcome.Index := mJob.Index;
  mOutcome.OperatorId := mJob.Mutant.OperatorId;
  mOutcome.Original := mJob.Mutant.Original;
  mOutcome.Replacement := mJob.Mutant.Replacement;
  mOutcome.Description := mJob.Mutant.Description;
  mOutcome.Line := mJob.Mutant.Line - 1 - mJob.Routine.Line;
  mOutcome.Status := AStatus;
  mOutcome.By := ABy;
  mOutcome.Milliseconds := Integer(TThread.GetTickCount64 - FState.StartedAt);
  FState.Outcomes[FState.Position] := mOutcome;
  FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationOutcome, [FState.Position + 1,
    Length(FState.Jobs), mJob.Routine.Name, mJob.Mutant.Line, mJob.Mutant.Original, mJob.Mutant.Replacement,
    StatusText(AStatus, ABy)]));
  Advance;
end;

procedure TAtlasIdeMutationRun.Advance;
begin
  Inc(FState.Position);
  if FState.Position > High(FState.Jobs) then
  begin
    Finish(False);
    Exit;
  end;
  Step;
end;

function TAtlasIdeMutationRun.Done: Integer;
begin
  Result := FState.Position;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

/// <summary>Ergebnis der Routine von AJobs[AFirst] aus allen Mutanten dieser Routine; AComplete, wenn alle vor
/// ADone liegen (geprüft sind).</summary>
function RoutineResult(const AJobs: TArray<TAtlasMutationJob>; const AOutcomes: TArray<TAtlasMutationOutcome>;
  AFirst, ADone: Integer; out AComplete: Boolean): TAtlasMutationRoutineResult;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasMutationRoutineResult);
  Result.Routine := AJobs[AFirst].Routine.Name;
  Result.Line := AJobs[AFirst].Routine.Line;
  Result.EndLine := AJobs[AFirst].Routine.EndLine;
  AComplete := True;
  // Eine lokale Routine kann die Mutanten der äußeren teilen: nach Namen sammeln, nicht nach Nachbarschaft.
  for mIndex := AFirst to High(AJobs) do
  begin
    if AJobs[mIndex].Routine.Name = Result.Routine then
    begin
      AComplete := AComplete and (mIndex < ADone);
      Result.Outcomes := Result.Outcomes + [AOutcomes[mIndex]];
    end;
  end;
end;

procedure TAtlasIdeMutationRun.Remember;
var
  mIndex, mOther: Integer;
  mResult: TAtlasMutationRoutineResult;
  mComplete, mSeen: Boolean;
begin
  for mIndex := 0 to High(FState.Jobs) do
  begin
    mSeen := False;
    for mOther := 0 to mIndex - 1 do
    begin
      mSeen := mSeen or (FState.Jobs[mOther].Routine.Name = FState.Jobs[mIndex].Routine.Name);
    end;
    if mSeen then
    begin
      Continue;
    end;
    mResult := RoutineResult(FState.Jobs, FState.Outcomes, mIndex, Done, mComplete);
    mResult.FileName := FState.FileName;
    mResult.Body := TAtlasMutants.RoutineBody(FState.Lines, FState.Jobs[mIndex].Routine);
    mResult.AtUtc := TTimeZone.Local.ToUniversalTime(Now);
    // Abgebrochen: nur ganz geprüfte Routinen gelten, sonst fehlten „geänderten Methoden“ Mutanten.
    if mComplete then
    begin
      FResults.Put(mResult);
    end;
  end;
end;

procedure TAtlasIdeMutationRun.Finish(ACancelled: Boolean);
var
  mTotals: TAtlasMutationTotals;
  mScore, mUnit: string;
  mIndex: Integer;
begin
  if not FState.Active then
  begin
    Exit;
  end;
  CloseShadow;
  Remember;
  SaveResults;
  mTotals := Default(TAtlasMutationTotals);
  for mIndex := 0 to Done - 1 do
  begin
    mTotals.Add(FState.Outcomes[mIndex].Status);
    if FState.Outcomes[mIndex].Status = TAtlasMutationStatus.Survived then
    begin
      FOutput.Jump(FState.FileName, TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationSurvivor,
        [FState.Jobs[mIndex].Routine.Name, FState.Jobs[mIndex].Mutant.Line, FState.Jobs[mIndex].Mutant.Original,
        FState.Jobs[mIndex].Mutant.Replacement, FState.Jobs[mIndex].Mutant.OperatorId]),
        FState.Jobs[mIndex].Mutant.Line - 1, FState.Jobs[mIndex].Mutant.Character - 1);
    end;
  end;
  if ACancelled then
  begin
    FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationCancelled, [Done, Length(FState.Jobs)]));
  end;
  mScore := TAtlasTestsStrings.Text(TAtlasTestsTextId.MutationNoScore);
  if mTotals.Score >= 0 then
  begin
    mScore := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationScore, [mTotals.Score]);
  end;
  mUnit := ExtractFileName(FState.FileName);
  FOutput.Say(TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationFinished, [mUnit, mTotals.Killed + mTotals.TimedOut,
    mTotals.Survived, mTotals.BuildFailed + mTotals.Invalid, mScore]));
  FOutput.ShowView;
  FState := Default(TState);
  Inc(FVersion);
  TAtlasIdeGutterMarks.Invalidate;
end;

procedure TAtlasIdeMutationRun.StopWith(const AText: string);
begin
  FOutput.Say(AText);
  if FState.Active then
  begin
    CloseShadow;
  end;
  FState := Default(TState);
  Inc(FVersion);
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
      if StrToIntDef(ABy, 0) <> 0 then
      begin
        // Ohne Bericht: der Exitcode (Absturz).
        Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStatusKilledExit, [ABy]);
      end
      else if ABy <> '' then
      begin
        Result := TAtlasTestsStrings.Fmt(TAtlasTestsTextId.MutationStatusKilledBy, [ABy]);
      end
      else
      begin
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
