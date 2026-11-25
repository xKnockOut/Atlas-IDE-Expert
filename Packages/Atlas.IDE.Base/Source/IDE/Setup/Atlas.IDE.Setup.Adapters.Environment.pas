unit Atlas.IDE.Setup.Adapters.Environment;

// Zustand und Knöpfe der Einrichtung (#625) in der IDE (IAtlasSetupEnvironment aus Atlas.Core.Setup.Contract):
// Snapshot sammelt im Hauptthread Pfad und Phase des Servers, Version der IDE, Plattform und Projekte der Gruppe,
// Error Insight, Atlas-Probleme und die Belegung der Atlas-Tasten; die Knöpfe wählen und speichern den
// Server-Pfad, starten den Server, bauen den Index neu auf, schalten Error Insight und öffnen die Tastenkonflikte.
// Erzeugt nur die Kompositionswurzel; Atlas.IDE.Setup.Checklist bekommt es über die Schnittstelle.

interface

uses
  Atlas.Core.Setup.Checklist,
  Atlas.IDE.Setup.Checklist,
  Atlas.Core.Setup.Contract;

type
  /// <summary>Was die Knöpfe in der IDE tun; Snapshot sammelt den Zustand.</summary>
  TAtlasIdeSetupEnvironment = class(TInterfacedObject, IAtlasSetupEnvironment)
  private
    FHooks: TAtlasSetupHooks;
    FKeys: TArray<TAtlasSetupKey>;
    FKeysAt: UInt64;
    FKeysRead: Boolean;
    function Keys: TArray<TAtlasSetupKey>;
  public
    constructor Create(const AHooks: TAtlasSetupHooks);
    /// <summary>Tasten beim nächsten Snapshot neu lesen („Erneut prüfen“, nach den Tastenkonflikten).</summary>
    procedure ForgetKeys;
    function Snapshot: TAtlasSetupInput;
    function ChooseServerPath(out APath: string): Boolean;
    procedure SaveServerPath(const APath: string);
    function StartServer(ARestart: Boolean): Boolean;
    function RebuildIndex: Boolean;
    function SetErrorInsight(AEnabled: Boolean): Boolean;
    procedure OpenKeyConflicts;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Plugin.Product.Version,
  Atlas.Plugin.Projects.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.Plugin.Status.Lines,
  Atlas.Plugin.Localization.Strings,
  Atlas.UI.Setup.Strings,
  Atlas.IDE.Commands.KeyMap,
  Atlas.IDE.Foundation.StructureSwitch,
  Atlas.IDE.Foundation.Settings;

{ TAtlasIdeSetupEnvironment }

constructor TAtlasIdeSetupEnvironment.Create(const AHooks: TAtlasSetupHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasIdeSetupEnvironment.Keys: TArray<TAtlasSetupKey>;
begin
  if FKeysRead and (TThread.GetTickCount64 - FKeysAt < TAtlasIdeSetupChecklist.cKeysMaxAgeMs) then
  begin
    Exit(FKeys);
  end;
  // Gemeinsame Quelle mit der Tastenkürzel-Übersicht (#520): auch Editorbefehle, Undo/Redo, das Suchfeld der
  // Willkommensseite und Tastaturbelegungen anderer Erweiterungen.
  FKeys := TAtlasIdeKeyMap.SetupKeys;
  FKeysAt := TThread.GetTickCount64;
  FKeysRead := True;
  Result := FKeys;
end;

procedure TAtlasIdeSetupEnvironment.ForgetKeys;
begin
  FKeysRead := False;
end;

/// <summary>Plattform des aktiven Projekts und Namen der .dproj der Projektgruppe.</summary>
procedure ReadProjects(var APlatform: string; var AProjects: TArray<string>);
var
  mModules: IOTAModuleServices;
  mGroup: IOTAProjectGroup;
  mIndex: Integer;
begin
  if not Supports(BorlandIDEServices, IOTAModuleServices, mModules) then
  begin
    Exit;
  end;
  if mModules.GetActiveProject <> nil then
  begin
    APlatform := mModules.GetActiveProject.CurrentPlatform;
  end;
  mGroup := mModules.MainProjectGroup;
  if mGroup = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mGroup.ProjectCount - 1 do
  begin
    if SameText(ExtractFileExt(mGroup.Projects[mIndex].FileName), '.dproj') then
    begin
      AProjects := AProjects + [TAtlasSetupChecklist.ProjectName(mGroup.Projects[mIndex].FileName)];
    end;
  end;
end;

function TAtlasIdeSetupEnvironment.Snapshot: TAtlasSetupInput;
var
  mSettings: TAtlasPluginSettings;
  mServices: IOTAServices;
  mPath: string;
  mPercent: Integer;
begin
  Result := Default(TAtlasSetupInput);
  mSettings := TAtlasIdeSettings.Current;
  mPath := '';
  if Assigned(FHooks.ServerPath) then
  begin
    mPath := FHooks.ServerPath();
  end;
  Result.ServerFound := (mPath <> '') and FileExists(mPath);
  if Assigned(FHooks.ServerInfo) then
  begin
    Result.Server := FHooks.ServerInfo();
  end;
  Result.PluginVersion := TAtlasPluginVersion.cVersion;
  if Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Result.BdsVersion := TAtlasProjectContext.VersionOfRegistryKey(mServices.GetBaseRegistryKey);
  end;
  ReadProjects(Result.Platform, Result.Projects);
  Result.IndexPercent := -1;
  if (Result.Server.Phase = TAtlasServerPhase.Running) and Assigned(FHooks.Indexing) then
  begin
    Result.Indexing := FHooks.Indexing(mPercent);
    Result.IndexPercent := mPercent;
  end;
  if Assigned(FHooks.StatusJson) and (Result.Server.Phase = TAtlasServerPhase.Running) then
  begin
    // Prozent je Projekt live aus $/progress, Stufe und Warten aus dem Status (#2142).
    Result.Status := TAtlasSetupServerStatus.Parse(FHooks.StatusJson()).WithLiveProgress(FHooks.IndexingOf);
  end;
  Result.ErrorInsight := TAtlasIdeStructureSwitch.ErrorInsight;
  Result.ErrorInsightRestart := TAtlasIdeStructureSwitch.ErrorInsightChanged;
  Result.AtlasProblems := mSettings.Enabled and mSettings.Problems;
  Result.Keys := Keys;
end;

function TAtlasIdeSetupEnvironment.ChooseServerPath(out APath: string): Boolean;
var
  mDialog: TOpenDialog;
begin
  APath := '';
  mDialog := TOpenDialog.Create(nil);
  try
    mDialog.Title := TAtlasSetupStrings.Text(TAtlasSetupTextId.SetupChooseTitle);
    mDialog.Filter := TAtlasStrings.Text(TAtlasTextId.SettingsServerFilter);
    mDialog.Options := mDialog.Options + [ofFileMustExist];
    if Assigned(FHooks.ServerPath) then
    begin
      mDialog.InitialDir := ExtractFilePath(FHooks.ServerPath());
    end;
    Result := mDialog.Execute;
    if Result then
    begin
      APath := mDialog.FileName;
    end;
  finally
    mDialog.Free;
  end;
end;

procedure TAtlasIdeSetupEnvironment.SaveServerPath(const APath: string);
var
  mSettings: TAtlasPluginSettings;
begin
  // Wie die Optionsseite: gespeicherte Werte, ohne Sitzungswerte der Schnellschalter.
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.ServerPath := APath;
  TAtlasIdeSettings.Update(mSettings);
  TAtlasGuard.Log('Einrichtung: Server-Pfad gewählt (#625)'); // german-ok Protokoll
end;

function TAtlasIdeSetupEnvironment.StartServer(ARestart: Boolean): Boolean;
begin
  Result := Assigned(FHooks.StartServer) and FHooks.StartServer(ARestart);
end;

function TAtlasIdeSetupEnvironment.RebuildIndex: Boolean;
begin
  // Abschicken genügt (#874): Auf die Antwort zu warten hielte die IDE an, solange der Server indexiert.
  Result := Assigned(FHooks.ServerCommand) and FHooks.ServerCommand(TAtlasSetupChecklist.cRebuildCommand);
end;

function TAtlasIdeSetupEnvironment.SetErrorInsight(AEnabled: Boolean): Boolean;
begin
  Result := TAtlasIdeStructureSwitch.SetErrorInsight(AEnabled);
end;

procedure TAtlasIdeSetupEnvironment.OpenKeyConflicts;
var
  mOptions: IOTAEnvironmentOptions140;
  mServices: IOTAServices;
begin
  // Seite „Atlas.Tastenkonflikte“ (#494) unter Tools › Optionen; danach Tasten neu lesen.
  if Supports(BorlandIDEServices, IOTAServices, mServices) and
    Supports(mServices.GetEnvironmentOptions, IOTAEnvironmentOptions140, mOptions) then
  begin
    mOptions.EditOptions('', 'Atlas.' + TAtlasStrings.Text(TAtlasTextId.KeysTitle));
  end;
  ForgetKeys;
end;

end.
