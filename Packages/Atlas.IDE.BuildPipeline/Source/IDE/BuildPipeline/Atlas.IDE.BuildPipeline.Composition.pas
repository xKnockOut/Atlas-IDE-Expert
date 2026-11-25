unit Atlas.IDE.BuildPipeline.Composition;

// Modul Build-Pipeline (#1455):
// einzige Unit, die den Läufer der Builds auf Auftrag (#261), die Prüfung vor dem Kompilieren (#529), den
// Release-Build-Wächter (#533) und die Bewertung mit Zusammenfassung (#530)
// erzeugt. Sie meldet in ihrer Initialisierung das Modul
// „atlas.buildpipeline“ (Modulschalter buildPipeline) bei der Registry von
// Base an und stellt über dessen Scope bereit:
// - die Teile der Feature-Tabelle (BuildPipeline: Läufer, Wächter und
//   Prüfung an den Compile-Ereignissen),
// - den Befehl „Release-Build prüfen“ (Palette),
// - für Base die Hörer der gelesenen Compilermeldungen und die Bewertung
//   eines Builds des Benutzers (Atlas.IDE.Base.Core.BuildPipeline); die Folgen gehen
//   über TAtlasBuildPipeline.Announce an jeden IAtlasBuildVerdictListener,
// - für andere Module und die Willkommensseite die Builds auf Auftrag
//   (IAtlasBuildJobs, Atlas.IDE.Base.Foundation.BuildPipeline), für das Modul KI-Assistenten
//   dieselben Builds samt Compilermeldungen (IAtlasBuildRequests, #1888).
// Compile-Ereignisse und Server erreicht das Modul nur über TAtlasIdeHost;
// seine Teilnehmer meldet es beim Stoppen ab, Antworten des Servers kommen
// nach dem Abmelden nicht mehr an (Regel 3). Abmelden in der Finalisierung,
// solange Base läuft (Regel 5); passt die Vertragsversion von Base nicht,
// meldet sich das Modul nicht an (Regel 7).
// Modulklasse, Befehl, Builds auf Auftrag und Bewertung stehen in Atlas.IDE.BuildPipeline.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  Atlas.UI.BuildPipeline.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Base.Core.Modules.FeatureParts,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Settings.Plugin,
  Atlas.Plugin.Build.Contract,
  Atlas.Core.BuildPipeline.Gate,
  Atlas.Core.BuildPipeline.ReleaseGuard,
  Atlas.IDE.Base.Foundation.BuildPipeline,
  Atlas.IDE.Base.Foundation.BuildRequests,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Projects.Summaries,
  Atlas.IDE.BuildPipeline.Runner,
  Atlas.IDE.BuildPipeline.Gate,
  Atlas.IDE.BuildPipeline.ReleaseGuard,
  Atlas.Core.Build.Events,
  Atlas.IDE.BuildPipeline.Adapters.Module;

var
  GScope: IAtlasModuleScope;
  /// <summary>Läufer der Builds auf Auftrag (#261); lebt mit dem Teil BuildPipeline.</summary>
  GRunner: TAtlasIdeBuildRunner;
  /// <summary>Teilnehmer an den Compile-Ereignissen (#533, #529); beim Stoppen abgemeldet.</summary>
  GReleaseGuard: TAtlasCompileParticipant;
  GGate: TAtlasCompileParticipant;

{ Einstellungen }

/// <summary>Einstellungen der Prüfung vor dem Kompilieren (#529) aus den aktuellen Plugin-Einstellungen.</summary>
function GateSettings: TAtlasGateSettings;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasGateSettings.Create(mSettings.BuildGate, mSettings.BuildGateTimeoutMs);
end;

{ Teil BuildPipeline }

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
      Result := TAtlasBuildPipelineModule.ReleaseSettings();
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

function Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Läufer, Wächter und Prüfung: solange Base die Compile-Ereignisse hat.
    TAtlasFeaturePart.When('BuildPipeline',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := TAtlasIdeHost.CompileEvents <> nil;
      end, PipelineStarted, StartPipeline, StopPipeline)];
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasBuildPipelineCompilerSection.ProvideIn(GScope);
  TAtlasBuildPipelineReleaseSection.ProvideIn(GScope);
end;

function CurrentRunner: TAtlasIdeBuildRunner;
begin
  Result := GRunner;
end;

function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

/// <summary>Was die Modulklasse von der Composition braucht.</summary>
function ModuleHooks: TAtlasBuildPipelineModuleHooks;
begin
  Result := Default(TAtlasBuildPipelineModuleHooks);
  Result.Runner := CurrentRunner;
  Result.Scope := ModuleScope;
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasBuildPipelineModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasBuildPipelineModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasBuildPipelineModule.Create(ModuleHooks);
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
  GScope.Provide(IAtlasBuildRequests, mRef);
  ProvideSettingsSections;
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasBuildPipelineModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
