unit Atlas.IDE.BuildPipeline.Adapters.Module;

// Modulklasse der Build-Pipeline (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.BuildPipeline.Composition) über den Scope des Moduls bereitstellt:
// - den Befehl „Release-Build prüfen“ (#533, Palette),
// - für Base die Hörer der gelesenen Compilermeldungen und die Bewertung eines Builds des Benutzers (#530,
//   Atlas.Core.Build.Pipeline); die Folgen gehen über TAtlasBuildPipeline.Announce an jeden
//   IAtlasBuildVerdictListener,
// - für andere Module und die Willkommensseite die Builds auf Auftrag (IAtlasBuildJobs), für das Modul
//   KI-Assistenten dieselben Builds samt Compilermeldungen (IAtlasBuildRequests, #1888).
// Den Läufer (#261) des Teils BuildPipeline und den Scope reicht die Composition als TAtlasBuildPipelineModuleHooks
// herein.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Requests,
  Atlas.Core.BuildPipeline.ReleaseGuard,
  Atlas.IDE.Contracts.BuildPipeline,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.Core.Build.Contract,
  Atlas.IDE.BuildPipeline.Runner;

type
  /// <summary>Was die Modulklasse von der Composition braucht.</summary>
  TAtlasBuildPipelineModuleHooks = record
    /// <summary>Läufer der Builds auf Auftrag (#261); nil, solange der Teil BuildPipeline nicht läuft.</summary>
    Runner: TFunc<TAtlasIdeBuildRunner>;
    /// <summary>Scope des Moduls für Antworten des Servers.</summary>
    Scope: TFunc<IAtlasModuleScope>;
  end;

  TAtlasBuildPipelineModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasBuildJobs,
    IAtlasBuildRequests, IAtlasCompilerMessagesListener, IAtlasBuildEvaluator)
  public const
    cModuleId = 'atlas.buildpipeline';
    cSwitch = 'buildPipeline';
  private
    FActive: Boolean;
    FHooks: TAtlasBuildPipelineModuleHooks;
  public
    constructor Create(const AHooks: TAtlasBuildPipelineModuleHooks);
    /// <summary>Einstellungen des Release-Build-Wächters (#533) aus den aktuellen Plugin-Einstellungen.</summary>
    class function ReleaseSettings: TAtlasReleaseSettings; static;
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    /// <summary>IAtlasBuildJobs.Start (Name wie IAtlasModule.Start, daher umgeleitet).</summary>
    function StartJob(const AJob: TAtlasBuildJob; const ADone: TAtlasBuildJobDone; out AReason: string): Boolean;
    function IAtlasBuildJobs.Start = StartJob;
    /// <summary>IAtlasBuildRequests.Start: Build samt Meldungen für den Eingang der KI-Assistenten (#1888).</summary>
    function StartRequest(const ARequest: TAtlasBuildRequest; const ARequestedBy: string;
      const AOnDone: TAtlasBuildDoneProc; out AReason: string): Boolean;
    function IAtlasBuildRequests.Start = StartRequest;
    /// <summary>IAtlasBuildRequests.Forget: Rückruf eines gehenden Auftraggebers verwerfen (#1906).</summary>
    procedure Forget(const ARequestedBy: string);
    function Busy: Boolean;
    procedure MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject);
    function Evaluate(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      ASucceeded: Boolean): Boolean;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Build.Verdict,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.BuildPipeline.ReleaseGuard,
  Atlas.IDE.BuildPipeline.Summary,
  Atlas.Plugin.Localization.Strings,
  Atlas.UI.BuildPipeline.Strings,
  Atlas.Core.Build.Pipeline,
  Atlas.Core.Build.Events;

class function TAtlasBuildPipelineModule.ReleaseSettings: TAtlasReleaseSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasReleaseSettings.Create(mSettings.ReleaseGuard, mSettings.BuildGate, mSettings.ReleaseConfigs,
    mSettings.ReleaseChecks);
end;
function ReleaseGuardVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.ReleaseGuard;
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
function BaselineClassifier(const AScope: TFunc<IAtlasModuleScope>;
  const AProjectFile: string): TAtlasBuildClassify;
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
      Result := TAtlasIdeHost.RunServerCommandAsync(AScope(), TAtlasFeature.Build, TAtlasBuildVerdicts.cClassifyCommand,
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
    TAtlasGuard.Log('Bewertung des Builds: ' + mFailure); // german-ok Protokoll
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
      TAtlasIdeReleaseGuard.CheckActive(TAtlasIdeProjectSummaries.Folder, TAtlasBuildPipelineModule.ReleaseSettings());
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

constructor TAtlasBuildPipelineModule.Create(const AHooks: TAtlasBuildPipelineModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasBuildPipelineModule.Info: TAtlasModuleInfo;
begin
  // Wächter und Prüfung liefen mit den Compile-Ereignissen auch im abgesicherten Start (mit CheckOnSave); der
  // MCP-Eingang verlangt den normalen Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Build-Pipeline', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
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
  mRunner: TAtlasIdeBuildRunner;
begin
  AReason := '';
  mRunner := FHooks.Runner();
  if mRunner = nil then
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
  Result := mRunner.Start(mRequest, AJob.RequestedBy, JobDone(ADone), AReason);
end;
function TAtlasBuildPipelineModule.StartRequest(const ARequest: TAtlasBuildRequest; const ARequestedBy: string;
  const AOnDone: TAtlasBuildDoneProc; out AReason: string): Boolean;
var
  mRunner: TAtlasIdeBuildRunner;
begin
  AReason := '';
  mRunner := FHooks.Runner();
  if mRunner = nil then
  begin
    AReason := TAtlasStrings.Text(TAtlasTextId.TestsNoBuildRunner);
    Exit(False);
  end;
  Result := mRunner.Start(ARequest, ARequestedBy, AOnDone, AReason);
end;
procedure TAtlasBuildPipelineModule.Forget(const ARequestedBy: string);
var
  mRunner: TAtlasIdeBuildRunner;
begin
  mRunner := FHooks.Runner();
  if mRunner <> nil then
  begin
    mRunner.Forget(ARequestedBy);
  end;
end;
function TAtlasBuildPipelineModule.Busy: Boolean;
var
  mRunner: TAtlasIdeBuildRunner;
begin
  mRunner := FHooks.Runner();
  Result := (mRunner <> nil) and mRunner.Busy;
end;
procedure TAtlasBuildPipelineModule.MessagesRead(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject);
var
  mRunner: TAtlasIdeBuildRunner;
begin
  // Builds auf Auftrag (#261) warten auf ihre Meldungen.
  mRunner := FHooks.Runner();
  if mRunner <> nil then
  begin
    mRunner.MessagesRead(AMessages, AProject);
  end;
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
    BaselineClassifier(FHooks.Scope, mProject.FileName),
    procedure(const AVerdict: TAtlasBuildVerdict)
    begin
      BuildEvaluated(mMessages, mProject, AVerdict);
    end);
end;

end.
