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
// - Teil „AssistantContext“: Zustand der IDE für get_ide_context (#2050),
//   solange assistants.context an ist; den letzten Build bekommt er über
//   IAtlasBuildVerdictListener.
// - den Abschnitt mit dem Modulschalter im Optionsdialog.
// - Befehl „Anweisungen für KI-Assistenten aktualisieren“ samt Hinweis nach dem Speichern der atlas.json (#2615,
//   Atlas.IDE.Assistants.Instructions).
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
  TAtlasAssistantsModule = class(TInterfacedObject, IAtlasModule, IAtlasBuildVerdictListener)
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
    procedure BuildEvaluated(const AMessages: TArray<TAtlasCompilerMessage>; const AProject: TAtlasCompileProject;
      const AVerdict: TAtlasBuildVerdict);
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
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
  Atlas.IDE.Assistants.ContextExport,
  Atlas.IDE.Assistants.Instructions,
  Atlas.UI.Assistants.SettingsSection;

var
  GScope: IAtlasModuleScope;
  GBuildInbox: TAtlasIdeBuildInbox;
  GEditInbox: TAtlasIdeEditInbox;
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

function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

{ Teile der Feature-Tabelle }

procedure StartBuilds;
begin
  GBuildInbox := TAtlasIdeBuildInbox.Create(BuildRequests, MessageLine);
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
  FreeAndNil(GBuildInbox);
end;

function BuildsStarted: Boolean;
begin
  Result := GBuildInbox <> nil;
end;

procedure StartEdits;
begin
  GEditInbox := TAtlasIdeEditInbox.Create(TAtlasIdeEditorFiles.Create, MessageLine);
end;

procedure StopEdits;
begin
  FreeAndNil(GEditInbox);
end;

function EditsStarted: Boolean;
begin
  Result := GEditInbox <> nil;
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
    // Zustand der IDE für get_ide_context (#2050): solange assistants.context an ist.
    TAtlasFeaturePart.When('AssistantContext',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel = TAtlasSafeLevel.Normal) and TAtlasIdeSettings.Current.AssistantsContext;
      end, ContextStarted, StartContext, StopContext)];
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
  mInstructions: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasAssistantsModule.Create;
  GScope := mRegistry.RegisterModule(mModule);
  // Letzter Build für den IDE-Zustand (#2050).
  GScope.Provide(IAtlasBuildVerdictListener, mModule as IAtlasBuildVerdictListener);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  TAtlasAssistantsSettingsSection.ProvideIn(GScope);
  // Anweisungsdateien für KI-Assistenten (#2615): Befehl, Menüeintrag und Hinweis nach dem Speichern.
  mInstructions := TAtlasIdeInstructions.Create(ModuleScope) as IAtlasCommandSource;
  GScope.Provide(IAtlasCommandSource, mInstructions);
  GScope.Provide(IAtlasMenuSource, mInstructions);
  GScope.Provide(IAtlasFollowsSaves, mInstructions);
  Result := True;
end;

class procedure TAtlasAssistantsModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
end;

initialization
  TAtlasAssistantsModule.RegisterModule;

finalization
  TAtlasAssistantsModule.UnregisterModule;

end.
