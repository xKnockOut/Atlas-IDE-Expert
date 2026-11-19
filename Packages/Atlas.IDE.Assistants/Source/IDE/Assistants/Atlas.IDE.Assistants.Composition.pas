unit Atlas.IDE.Assistants.Composition;

// Modul KI-Assistenten (#1888): einzige Unit, die die Eingänge für
// Aufträge von MCP-Clients in der laufenden IDE erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.assistants“ (Modulschalter assistants) bei
// der Registry von Base an und stellt über dessen Scope bereit:
// - Teil „AssistantBuilds“: Eingang des MCP-Werkzeugs build_project (#261);
//   gebaut wird über IAtlasBuildRequests des Moduls Build-Pipeline, das der
//   Eingang bei jedem Auftrag neu in der Registry sucht (Regel 2). Nur im
//   normalen Start und solange compiler.mcpBuild an ist.
// - Teil „AssistantEdits“: Eingang für Änderungen an offenen Dateien (#397),
//   solange assistants.edit an ist.
// - Teil „AssistantBanner“: Feld „KI-Assistent aktiv“ im Statusfeld mit Pause
//   für KI-Assistenten (#1906), solange assistants.banner an ist.
// - den Befehl „Pause für KI-Assistenten“ in der Palette (#1906).
// - Teil „AssistantContext“: Zustand der IDE für get_ide_context (#2050),
//   solange assistants.context an ist; den letzten Build bekommt er über
//   IAtlasBuildVerdictListener.
// - den Abschnitt mit dem Modulschalter im Optionsdialog.
// Was KI-Assistenten gerade tun und ob sie pausiert sind
// (TAtlasAssistantsActivity), gehört dem Modul und lebt von der Anmeldung bis
// nach dem Abmelden: Die Pause bleibt so über das Neustarten einzelner Teile
// hinweg stehen.
// Die Liste der offenen und ungespeicherten Dateien (DirtyExport) bleibt in
// Base: Sie schützt Dateien auch dann vor dem Überschreiben, wenn das Modul
// fehlt. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt
// die Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Build.Events,
  Atlas.Core.Build.Messages,
  Atlas.Core.Build.Verdict;

type
  TAtlasAssistantsModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasBuildVerdictListener)
  public const
    cModuleId = 'atlas.assistants';
    cSwitch = 'assistants';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    /// <summary>Befehl „Pause für KI-Assistenten“ (#1906).</summary>
    function Commands: TArray<TAtlasModuleCommand>;
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Core.Assistants.Activity,
  Atlas.Core.Assistants.BuildInbox,
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.IDE.Foundation.EditorFiles,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.BuildInbox,
  Atlas.IDE.Assistants.EditInbox,
  Atlas.IDE.Assistants.Banner,
  Atlas.UI.Assistants.Strings,
  Atlas.IDE.Assistants.ContextExport,
  Atlas.UI.Assistants.SettingsSection;

const
  cPauseCommand = 'Atlas.AssistantsPause';

var
  GScope: IAtlasModuleScope;
  GActivity: TAtlasAssistantsActivity;
  GBuildInbox: TAtlasIdeBuildInbox;
  GEditInbox: TAtlasIdeEditInbox;
  GBanner: TAtlasIdeAssistantsBanner;
  GContext: TAtlasIdeContextExport;

{ Dienste von Base und anderer Module }

procedure MessageLine(const AText: string);
begin
  TAtlasIdeHost.Warning(AText);
end;

/// <summary>Builds des Moduls Build-Pipeline; nil, solange es fehlt oder nicht läuft.</summary>
function BuildRequests: IAtlasBuildRequests;
var
  mItem: IInterface;
begin
  Result := nil;
  for mItem in TAtlasModuleContributions.Active(AtlasModuleRegistry, IAtlasBuildRequests) do
  begin
    if Supports(mItem, IAtlasBuildRequests, Result) then
    begin
      Exit;
    end;
  end;
end;

{ Teile der Feature-Tabelle }

procedure StartBuilds;
begin
  GBuildInbox := TAtlasIdeBuildInbox.Create(BuildRequests, GActivity, MessageLine);
end;

procedure StopBuilds;
var
  mRequests: IAtlasBuildRequests;
begin
  // Ein laufender Build ruft danach nicht mehr in dieses Modul zurück (Regel 3, #1906).
  mRequests := BuildRequests;
  if mRequests <> nil then
  begin
    mRequests.Forget(TAtlasBuildInbox.cRequestedBy);
  end;
  // Der verworfene Rückruf meldet das Ende nicht mehr; sonst bliebe „baut …“ stehen.
  GActivity.BuildEnded;
  FreeAndNil(GBuildInbox);
end;

function BuildsStarted: Boolean;
begin
  Result := GBuildInbox <> nil;
end;

procedure StartEdits;
begin
  GEditInbox := TAtlasIdeEditInbox.Create(TAtlasIdeEditorFiles.Create, GActivity, MessageLine);
end;

procedure StopEdits;
begin
  FreeAndNil(GEditInbox);
end;

function EditsStarted: Boolean;
begin
  Result := GEditInbox <> nil;
end;

/// <summary>Pause für KI-Assistenten ein bzw. aus (Befehl und Klick auf die Anzeige).</summary>
procedure TogglePause;
begin
  GActivity.Paused := not GActivity.Paused;
  if GActivity.Paused then
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseOn));
  end
  else
  begin
    TAtlasIdeHost.Message(TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseOff));
  end;
  if GBanner <> nil then
  begin
    GBanner.Refresh;
  end;
end;

procedure StartBanner;
begin
  GBanner := TAtlasIdeAssistantsBanner.Create(GActivity, TogglePause);
end;

procedure StopBanner;
begin
  FreeAndNil(GBanner);
end;

function BannerStarted: Boolean;
begin
  Result := GBanner <> nil;
end;

function PauseCaption: string;
begin
  if GActivity.Paused then
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOff);
  end
  else
  begin
    Result := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandOn);
  end;
end;

procedure StartContext;
begin
  GContext := TAtlasIdeContextExport.Create;
end;

procedure StopContext;
begin
  FreeAndNil(GContext);
end;

function ContextStarted: Boolean;
begin
  Result := GContext <> nil;
end;

{ TAtlasAssistantsModule }

class function TAtlasAssistantsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Builds für KI-Assistenten (#261): nur im normalen Start und solange compiler.mcpBuild an ist.
    TAtlasFeaturePart.When('AssistantBuilds',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.McpBuild;
      end, BuildsStarted, StartBuilds, StopBuilds),
    // Änderungen an offenen Dateien (#397): nur im normalen Start und solange assistants.edit an ist.
    TAtlasFeaturePart.When('AssistantEdits',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsEdit;
      end, EditsStarted, StartEdits, StopEdits),
    // Anzeige „KI-Assistent aktiv“ mit Pause (#1906): solange assistants.banner an ist.
    TAtlasFeaturePart.When('AssistantBanner',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsBanner;
      end, BannerStarted, StartBanner, StopBanner),
    // Zustand der IDE für get_ide_context (#2050): solange assistants.context an ist.
    TAtlasFeaturePart.When('AssistantContext',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsContext;
      end, ContextStarted, StartContext, StopContext)];
end;

function TAtlasAssistantsModule.Commands: TArray<TAtlasModuleCommand>;
begin
  SetLength(Result, 1);
  Result[0] := Default(TAtlasModuleCommand);
  Result[0].Id := cPauseCommand;
  Result[0].Caption := PauseCaption;
  Result[0].Description := TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.PauseCommandHint);
  Result[0].Run := TogglePause;
end;

function TAtlasAssistantsModule.Info: TAtlasModuleInfo;
begin
  // Wie bisher: Aufträge nimmt die IDE nur im normalen Start an.
  Result := TAtlasModuleHost.Info(cModuleId, 'KI-Assistenten', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Normal, cSwitch);
end;

procedure TAtlasAssistantsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasAssistantsModule.Stop;
begin
  FActive := False;
end;

function TAtlasAssistantsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

procedure TAtlasAssistantsModule.BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>;
  const AProject: TAtlasCompileProject; const AVerdict: TAtlasBuildVerdict);
begin
  // Letzter Build für den IDE-Zustand (#2050); ohne laufenden Teil nichts.
  if GContext <> nil then
  begin
    GContext.BuildRemembered(AMessages, AProject, AVerdict);
  end;
end;

class function TAtlasAssistantsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAssistantsModule;
  mPart: IAtlasFeaturePart;
  mRef: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  GActivity := TAtlasAssistantsActivity.Create;
  mModule := TAtlasAssistantsModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  // Letzter Build für den IDE-Zustand (#2050).
  GScope.Provide(IAtlasBuildVerdictListener, mModule as IAtlasBuildVerdictListener);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  TAtlasAssistantsSettingsSection.ProvideIn(GScope);
  Result := True;
end;

class procedure TAtlasAssistantsModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
  // Erst nach dem Stoppen aller Teile: Eingänge und Anzeige halten die Aktivität bis dahin.
  FreeAndNil(GActivity);
end;

initialization
  TAtlasAssistantsModule.RegisterModule;

finalization
  TAtlasAssistantsModule.UnregisterModule;

end.
