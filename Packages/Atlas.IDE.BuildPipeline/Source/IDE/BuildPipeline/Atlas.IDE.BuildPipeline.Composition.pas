unit Atlas.IDE.BuildPipeline.Composition;

// Modul Build-Pipeline (#1455, ADR 0017, Entscheidung Marco 01.11.2026):
// einzige Unit, die den Läufer der Builds auf Auftrag (#261), den
// MCP-Eingang build_project, die Prüfung vor dem Kompilieren (#529), den
// Release-Build-Wächter (#533) und die Bewertung mit Zusammenfassung (#530)
// erzeugt. Sie meldet in ihrer Initialisierung das Modul
// „atlas.buildpipeline“ (Modulschalter buildPipeline) bei der Registry von
// Base an und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (BuildPipeline: Läufer, Wächter und
//   Prüfung an den Compile-Ereignissen; McpBuild: Eingang für KI-Assistenten (MCP)),
// - den Befehl „Release-Build prüfen“ (Palette),
// - für Base die Hörer der gelesenen Compilermeldungen und die Bewertung
//   eines Builds des Benutzers (Atlas.Core.Build.Pipeline); die Folgen gehen
//   über TAtlasBuildPipeline.Announce an jeden IAtlasBuildVerdictListener,
// - für andere Module und die Willkommensseite die Builds auf Auftrag
//   (IAtlasBuildJobs, Atlas.IDE.Contracts.BuildPipeline).
// Compile-Ereignisse und Server erreicht das Modul nur über TAtlasIdeHost;
// seine Teilnehmer meldet es beim Stoppen ab, Antworten des Servers kommen
// nach dem Abmelden nicht mehr an (Regel 3). Abmelden in der Finalisierung,
// solange Base läuft (Regel 5); passt die Vertragsversion von Base nicht,
// meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Pipeline,
  Atlas.IDE.Contracts.BuildPipeline;

type
  TAtlasBuildPipelineModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasBuildJobs,
    IAtlasCompilerMessagesListener, IAtlasBuildEvaluator)
  public const
    cModuleId = 'atlas.buildpipeline';
    cSwitch = 'buildPipeline';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    /// <summary>IAtlasBuildJobs.Start (Name wie IAtlasModule.Start, daher umgeleitet).</summary>
    function StartJob(const AJob: TAtlasBuildJob; const ADone: TAtlasBuildJobDone; out AReason: string): Boolean;
    function IAtlasBuildJobs.Start = StartJob;
    function Busy: Boolean;
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
    function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean): Boolean;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.BuildPipeline.SettingsSection,
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.Verdict,
  Atlas.Core.BuildPipeline.Inbox,
  Atlas.Core.BuildPipeline.Gate,
  Atlas.Core.BuildPipeline.ReleaseGuard,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.BuildPipeline.Runner,
  Atlas.IDE.BuildPipeline.Inbox,
  Atlas.IDE.BuildPipeline.Gate,
  Atlas.IDE.BuildPipeline.ReleaseGuard,
  Atlas.IDE.BuildPipeline.Summary,
  Atlas.UI.Strings,
  Atlas.UI.BuildPipeline.Strings;

var
  GScope: IAtlasModuleScope;
  /// <summary>Läufer der Builds auf Auftrag (#261); lebt mit dem Teil BuildPipeline.</summary>
  GRunner: TAtlasIdeBuildRunner;
  /// <summary>Eingang des MCP-Werkzeugs build_project (#261); lebt mit dem Teil McpBuild.</summary>
  GInbox: TAtlasIdeBuildInbox;
  /// <summary>Teilnehmer an den Compile-Ereignissen (#533, #529); beim Stoppen abgemeldet.</summary>
  GReleaseGuard: TAtlasCompileParticipant;
  GGate: TAtlasCompileParticipant;

{ Einstellungen }

/// <summary>Einstellungen des Release-Build-Wächters (#533) aus den aktuellen Plugin-Einstellungen.</summary>
function ReleaseSettings: TAtlasReleaseSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasReleaseSettings.Create(mSettings.ReleaseGuard, mSettings.BuildGate, mSettings.ReleaseConfigs,
    mSettings.ReleaseChecks);
end;

/// <summary>Einstellungen der Prüfung vor dem Kompilieren (#529) aus den aktuellen Plugin-Einstellungen.</summary>
function GateSettings: TAtlasGateSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasGateSettings.Create(mSettings.BuildGate, mSettings.BuildGateTimeoutMs);
end;

function ReleaseGuardVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ReleaseGuard;
end;

{ Teil BuildPipeline }

procedure StopMcpBuild;
begin
  FreeAndNil(GInbox);
end;

procedure StartPipeline;
var
  mEvents: TAtlasCompileEvents;
begin
  mEvents := TAtlasIdeHost.CompileEvents;
  if mEvents = nil then
  begin
    Exit;
  end;
  // Release-Build-Wächter (#533): prüft vor make und build in einer Release-Konfiguration, auch für Aufträge des
  // Läufers (#261, #764); mit build.gate = block bricht er ab.
  GReleaseGuard := TAtlasIdeReleaseGuard.CreateParticipant(TAtlasIdeProjectSummaries.Folder,
    function: TAtlasReleaseSettings
    begin
      Result := ReleaseSettings();
    end);
  mEvents.Add(GReleaseGuard);
  // Prüfung vor dem Kompilieren (#529): geänderte Units über den laufenden Server, nur Builds des Benutzers.
  GGate := TAtlasIdeBuildGate.CreateParticipant(
    function: TAtlasGateSettings
    begin
      Result := GateSettings();
    end,
    function: TLspSession
    begin
      Result := TAtlasIdeHost.RunningSession;
    end);
  mEvents.Add(GGate);
  GRunner := TAtlasIdeBuildRunner.Create(mEvents);
end;

procedure StopPipeline;
var
  mEvents: TAtlasCompileEvents;
begin
  // Der Eingang hält den Läufer: zuerst gehen.
  StopMcpBuild;
  FreeAndNil(GRunner);
  mEvents := TAtlasIdeHost.CompileEvents;
  if mEvents <> nil then
  begin
    // Remove gibt die Teilnehmer frei.
    mEvents.Remove(GGate);
    mEvents.Remove(GReleaseGuard);
  end;
  GGate := nil;
  GReleaseGuard := nil;
end;

function PipelineStarted: Boolean;
begin
  Result := GRunner <> nil;
end;

{ Teil McpBuild }

procedure StartMcpBuild;
begin
  GInbox := TAtlasIdeBuildInbox.Create(GRunner,
    procedure(const AText: string)
    begin
      TAtlasIdeHost.Warning(AText);
    end);
end;

function McpBuildStarted: Boolean;
begin
  Result := GInbox <> nil;
end;

{ Bewertung (#530) }

/// <summary>Antwort des Servers (JSON-Text, '' bei Zeitlimit oder Fehler) als Basislinie je Meldung; nil = alles
/// zählt.</summary>
function BaselinedOfAnswer(const AAnswer: string; ACount: Integer): TArray<Boolean>;
var
  mValue: TJSONValue;
begin
  mValue := nil;
  if AAnswer <> '' then
  begin
    mValue := TJSONObject.ParseJSONValue(AAnswer);
  end;
  try
    Result := TAtlasBuildVerdicts.BaselinedOf(mValue, ACount);
  finally
    mValue.Free;
  end;
end;

/// <summary>Fragt den laufenden Server, welche Meldungen eines Builds von AProjectFile in der Basislinie stehen;
/// ohne laufenden Server nicht (False), dann zählt alles. Den Server startet Atlas dafür nicht (#874).</summary>
function BaselineClassifier(const AProjectFile: string): TAtlasBuildClassify;
var
  mUri: string;
begin
  mUri := TLspSession.PathToUri(AProjectFile);
  Result :=
    function(const AMessages: TArray<TAtlasCompilerMessage>; const ADone: TAtlasBuildBaselined): Boolean
    var
      mCount: Integer;
      mDone: TAtlasBuildBaselined;
    begin
      mCount := Length(AMessages);
      mDone := ADone;
      Result := TAtlasIdeHost.RunServerCommandAsync(GScope, TAtlasFeature.Build, TAtlasBuildVerdicts.cClassifyCommand,
        TAtlasBuildVerdicts.Arguments(mUri, AMessages), TAtlasBuildVerdicts.cClassifyTimeoutMs,
        procedure(AAnswer: string)
        begin
          mDone(BaselinedOfAnswer(AAnswer, mCount));
        end);
    end;
end;

/// <summary>Folgen eines bewerteten Builds: Zusammenfassung (#530), dann jeder IAtlasBuildVerdictListener
/// (Benachrichtigungszentrale #601, Tests nach dem Build #69) nach derselben Bewertung.</summary>
procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
  const AVerdict: TAtlasBuildVerdict);
var
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
  mVerdict: TAtlasBuildVerdict;
  mFailure: string;
begin
  mMessages := AMessages;
  mProject := AProject;
  mVerdict := AVerdict;
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeBuildSummary.Report(mMessages, mProject, mVerdict, TAtlasIdeSettings.Current.BuildSummary);
    end);
  for mFailure in TAtlasBuildPipeline.Announce(mMessages, mProject, mVerdict) do
  begin
    TAtlasGuard.Log('Bewertung des Builds: ' + mFailure);
  end;
end;

/// <summary>Ende eines Builds auf Auftrag als Ergebnis des Vertrags; eigene Routine, damit die Referenz nichts aus
/// Start einfängt.</summary>
function JobDone(const ADone: TAtlasBuildJobDone): TAtlasBuildDoneProc;
begin
  Result := nil;
  if not Assigned(ADone) then
  begin
    Exit;
  end;
  Result :=
    procedure(const AReport: TAtlasBuildReport; const AError: string)
    var
      mResult: TAtlasBuildJobResult;
    begin
      mResult := Default(TAtlasBuildJobResult);
      mResult.Error := AError;
      mResult.Succeeded := (AError = '') and AReport.Succeeded;
      mResult.OutputFile := AReport.Project.OutputFile;
      mResult.DurationMs := AReport.DurationMs;
      ADone(mResult);
    end;
end;

{ Befehle }

procedure CheckRelease;
begin
  TAtlasGuard.Run(TAtlasFeature.Build,
    procedure
    begin
      TAtlasIdeReleaseGuard.CheckActive(TAtlasIdeProjectSummaries.Folder, ReleaseSettings());
    end);
end;

function Command(const AId: string; ACaption: TAtlasBuildPipelineTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasBuildPipelineStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

{ TAtlasBuildPipelineModule }

function TAtlasBuildPipelineModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Build-Pipeline';
  Result.Version := TAtlasVersion.cVersion;
  Result.Handle := HInstance;
  // Wächter und Prüfung liefen mit den Compile-Ereignissen auch im abgesicherten Start (mit CheckOnSave); der
  // MCP-Eingang verlangt den normalen Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasBuildPipelineModule.Start;
begin
  FActive := True;
end;

procedure TAtlasBuildPipelineModule.Stop;
begin
  FActive := False;
end;

function TAtlasBuildPipelineModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasBuildPipelineModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Release-Build prüfen (#533) ohne Build; nur sichtbar, solange build.releaseGuard an ist.
    Command('Atlas.CheckRelease', TAtlasBuildPipelineTextId.ReleaseCheckCommand, CheckRelease, ReleaseGuardVisible)];
end;

function TAtlasBuildPipelineModule.StartJob(const AJob: TAtlasBuildJob; const ADone: TAtlasBuildJobDone;
  out AReason: string): Boolean;
var
  mRequest: TAtlasBuildRequest;
begin
  AReason := '';
  if GRunner = nil then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
    Exit(False);
  end;
  mRequest := Default(TAtlasBuildRequest);
  mRequest.Project := AJob.Project;
  mRequest.Configuration := AJob.Configuration;
  mRequest.Platform := AJob.Platform;
  case AJob.Kind of
    TAtlasBuildJobKind.Build:
      mRequest.Kind := TAtlasCompileKind.Build;
    TAtlasBuildJobKind.Check:
      mRequest.Kind := TAtlasCompileKind.Check;
  else
    mRequest.Kind := TAtlasCompileKind.Make;
  end;
  Result := GRunner.Start(mRequest, AJob.RequestedBy, JobDone(ADone), AReason);
end;

function TAtlasBuildPipelineModule.Busy: Boolean;
begin
  Result := (GRunner <> nil) and GRunner.Busy;
end;

procedure TAtlasBuildPipelineModule.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject);
begin
  // Builds auf Auftrag (#261) warten auf ihre Meldungen.
  if GRunner <> nil then
  begin
    GRunner.MessagesRead(AMessages, AProject);
  end;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasBuildPipelineCompilerSection.ProvideIn(GScope);
  TAtlasBuildPipelineReleaseSection.ProvideIn(GScope);
end;

function TAtlasBuildPipelineModule.Evaluate(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; ASucceeded: Boolean): Boolean;
var
  mSettings: TAtlasPluginSettings;
  mMessages: TArray<TAtlasCompilerMessage>;
  mProject: TAtlasCompileProject;
begin
  // Basislinie über den Server, build.zeroHints und build.warningsAsErrors; die Folgen bei Server-Frage später im
  // Hauptthread.
  Result := True;
  mSettings := TAtlasIdeSettings.Current;
  mMessages := AMessages;
  mProject := AProject;
  TAtlasBuildVerdicts.Run(mMessages, ASucceeded,
    TAtlasBuildVerdictSettings.Create(mSettings.BuildZeroHints, mSettings.BuildWarningsAsErrors),
    BaselineClassifier(mProject.FileName),
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      BuildEvaluated(mMessages, mProject, AVerdict);
    end);
end;

class function TAtlasBuildPipelineModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Läufer, Wächter und Prüfung: solange Base die Compile-Ereignisse hat.
    TAtlasFeaturePart.When('BuildPipeline',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := TAtlasIdeHost.CompileEvents <> nil;
      end, PipelineStarted, StartPipeline, StopPipeline),
    // Builds für KI-Assistenten (#261): nur im normalen Start, mit dem Läufer und solange McpBuild an ist.
    TAtlasFeaturePart.When('McpBuild',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.McpBuild and (GRunner <> nil);
      end, McpBuildStarted, StartMcpBuild, StopMcpBuild)];
end;

class function TAtlasBuildPipelineModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasBuildPipelineModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  mRegistry := AtlasModuleRegistry;
  if (mRegistry = nil) or (GScope <> nil) then
  begin
    Exit;
  end;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + cModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasBuildPipelineModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  // Für Base: gelesene Compilermeldungen und Bewertung eines Builds des Benutzers.
  GScope.Provide(IAtlasCompilerMessagesListener, mRef);
  GScope.Provide(IAtlasBuildEvaluator, mRef);
  // Vertrag zwischen Modulen: Builds auf Auftrag für Tests, Build-Werkzeuge und Willkommensseite.
  GScope.Provide(IAtlasBuildJobs, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasBuildPipelineModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
  begin
    for mFailure in mRegistry.UnregisterModule(cModuleId) do
    begin
      TAtlasGuard.Log('Modul ' + cModuleId + ' nicht sauber abgemeldet: ' + mFailure);
    end;
  end;
end;

initialization
  TAtlasBuildPipelineModule.RegisterModule;

finalization
  TAtlasBuildPipelineModule.UnregisterModule;

end.
