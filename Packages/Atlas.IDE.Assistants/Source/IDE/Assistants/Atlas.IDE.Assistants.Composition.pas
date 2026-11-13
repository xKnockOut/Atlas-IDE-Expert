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
// - den Abschnitt mit dem Modulschalter im Optionsdialog.
// Die Liste der offenen und ungespeicherten Dateien (DirtyExport) bleibt in
// Base: Sie schützt Dateien auch dann vor dem Überschreiben, wenn das Modul
// fehlt. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt
// die Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasAssistantsModule = class(TInterfacedObject, IAtlasModule)
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
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Core.Assistants.BuildInbox,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.WorkerSlot,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Modules.Contributions,
  Atlas.IDE.Contracts.BuildRequests,
  Atlas.IDE.Foundation.EditorFiles,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Assistants.BuildInbox,
  Atlas.IDE.Assistants.EditInbox,
  Atlas.UI.Assistants.SettingsSection;

var
  GScope: IAtlasModuleScope;
  GBuildInbox: TAtlasIdeBuildInbox;
  GEditInbox: TAtlasIdeEditInbox;

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

{ TAtlasAssistantsModule }

function TAtlasAssistantsModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'KI-Assistenten';
  Result.Version := TAtlasVersion.cVersion;
  Result.Handle := HInstance;
  // Wie bisher: Aufträge nimmt die IDE nur im normalen Start an.
  Result.MinLevel := TAtlasSafeLevel.Normal;
  Result.Switch := cSwitch;
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
      end, EditsStarted, StartEdits, StopEdits)];
end;

class function TAtlasAssistantsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasAssistantsModule;
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
  mModule := TAtlasAssistantsModule.Create;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  TAtlasAssistantsSettingsSection.ProvideIn(GScope);
  Result := True;
end;

class procedure TAtlasAssistantsModule.UnregisterModule;
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
  TAtlasAssistantsModule.RegisterModule;

finalization
  TAtlasAssistantsModule.UnregisterModule;
  // Vor FreeLibrary: Laufen noch überfällige Threads des Packages, bleibt es im Speicher (Code-Review T-103).
  TAtlasOverdueThreads.SettleBeforeUnload(HInstance);

end.
