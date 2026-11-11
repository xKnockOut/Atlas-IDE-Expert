unit Atlas.IDE.VersionControl.Composition;

// Modul Versionsverwaltung (#1891): einzige Unit, die die Umsetzungen
// für Git und SVN (Prozessläufer, Auswahl, Anbieter) mit dem Dienst der IDE
// (TAtlasIdeVcsCore) verbindet. Sie meldet in ihrer Initialisierung das Modul
// „atlas.vcs“ (Modulschalter vcs) bei der Registry von Base an und stellt über
// dessen Scope bereit:
// - den Teil „Vcs“ der Feature-Tabelle: Start setzt IAtlasVcsService und
//   IAtlasVcsDialogs (Atlas.IDE.Contracts.VersionControl) bei
//   TAtlasIdeVcs (Base) ein, Stop nimmt beides zurück und hält den
//   Hintergrundlauf an (Regel 3);
// - den Abschnitt mit dem Modulschalter vcs.enabled im Optionsdialog.
// Serverbefehle (Index neu aufbauen nach einem Branch mit geänderten
// Externals, #1291) laufen über TAtlasIdeHost, die Antwort nur bei offenem Scope.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.BranchPlan,
  Atlas.Core.VersionControl.Tools,
  Atlas.Core.VersionControl.ToolCheck,
  Atlas.Core.VersionControl.ServerCheck,
  Atlas.Core.Projects.VersionControl,
  Atlas.IDE.Contracts.VersionControl;

type
  TAtlasVcsModule = class(TInterfacedObject, IAtlasModule)
  public const
    cModuleId = 'atlas.vcs';
    cSwitch = 'vcs';
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

  /// <summary>IAtlasVcsService über TAtlasIdeVcsCore.</summary>
  TAtlasVcsServiceAdapter = class(TInterfacedObject, IAtlasVcsService)
  public
    procedure Report(const AText: string);
    function Provider: TAtlasVcsProvider;
    function TimeoutMs: Cardinal;
    procedure Reload;
    function ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
    function ForFolderResolution(const AFolder: string): TAtlasVcsProjectResolution;
    function ForProjectResolution(const AProjectFile, AGroupFile: string): TAtlasVcsProjectResolution;
    function MainBranchOf(const AProjectFile, AGroupFile: string): string;
    function Projects: TArray<TAtlasVcsProjectMapping>;
    function Run(const AWork, ADone: TProc): Boolean;
    function Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
    function CheckTool(AKind: TAtlasVcsKind; const APath: string; const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
    function QueryProject(const AProjectFile, AGroupFile: string; const ADone: TProc<TAtlasVcsProjectState>): Boolean;
    function CheckServer(const AFolder: string; const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
    function ServerState(const AFolder: string): TAtlasVcsServerCheck;
    function OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
  end;

  /// <summary>IAtlasVcsDialogs über TAtlasIdeBranching und TAtlasIdeWorkingCopies.</summary>
  TAtlasVcsDialogsAdapter = class(TInterfacedObject, IAtlasVcsDialogs)
  public
    procedure CreateBranchFor(const AProject: string; const ADone: TProc);
    procedure ShowWorkingCopies(const AProject: string; const ADone: TProc);
    function AskBranch(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName, AMessage,
      AKey: string; const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean;
      out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
    function SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
    function GitOptions: TAtlasVcsGitBranchOptions;
    procedure OfferOpen(const AProject, ARoot, AFolder: string);
    function ServerState(AOutcome: TAtlasVcsOutcome): string;
    function AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
      const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
      out AFallback: TAtlasVcsBranchRequest): Boolean;
    function AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
    function WorktreeProject(const AProject, ARoot, AFolder: string): string;
    function OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
    procedure StopAsking;
    procedure RebuildIndex;
    function Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
    function FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
      const ARun: TAtlasVcsBranchRun): string;
  end;

  /// <summary>Nach dem Speichern der Optionen (#1905, vorher in Base): settings.json neu lesen, damit ein neuer
  /// Pfad und ein neues Zeitlimit sofort gelten.</summary>
  TAtlasVcsAppliesSettings = class(TInterfacedObject, IAtlasAppliesSettings, IAtlasFollowsTheme)
  public
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.VersionControl.Composition,
  Atlas.IDE.VersionControl.Commands,
  Atlas.IDE.VersionControl.LineChanges,
  Atlas.IDE.Contracts.LineChanges,
  Atlas.Core.VersionControl.Adapters.ProcessRunner,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.VersionControl.Service,
  Atlas.IDE.VersionControl.Branching,
  Atlas.IDE.VersionControl.WorkingCopies,
  Atlas.IDE.VersionControl.Settings,
  Atlas.UI.Settings.Contract;

const
  /// <summary>Zeitlimit des Serverbefehls nach einem Branch.</summary>
  cServerCommandMs = 30000;

var
  GScope: IAtlasModuleScope;
  GStarted: Boolean;

{ Dienste von Base }

procedure MessageLine(const AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

/// <summary>Befehl ohne Argumente an den laufenden Server; die Antwort braucht niemand.</summary>
function ServerCommand(ACommand: string): Boolean;
begin
  Result := (TAtlasIdeHost.ActiveSession <> nil) and TAtlasIdeHost.RunServerCommandAsync(GScope,
    TAtlasFeature.Palette, ACommand, '', cServerCommandMs, nil);
end;

/// <summary>Prozessläufer und Auswahl der Umsetzung (bisher in der Kompositionswurzel von Base).</summary>
function Backend: TAtlasIdeVcsBackend;
begin
  Result.NewRunner :=
    function(ACancelled: TFunc<Boolean>): IAtlasVcsRunner
    begin
      Result := TAtlasVcsProcessRunner.Create(False, ACancelled);
    end;
  Result.Open :=
    function(const AFolder: string; AProvider: TAtlasVcsProvider; const ARunner: IAtlasVcsRunner;
      ATimeoutMs: Cardinal): IAtlasVersionControl
    begin
      if ATimeoutMs = 0 then
      begin
        Exit(TAtlasVersionControl.Open(AFolder, AProvider, ARunner));
      end;
      Result := TAtlasVersionControl.Open(AFolder, AProvider, ARunner,
        function(AKind: TAtlasVcsKind): string
        begin
          Result := TAtlasVcsTools.Find(AKind);
        end,
        ATimeoutMs);
    end;
  Result.SetToolMissing :=
    procedure(AHandler: TProc<TAtlasVcsKind>)
    begin
      TAtlasVcsNotices.OnToolMissing := AHandler;
    end;
end;

{ Teil der Feature-Tabelle }

procedure StartVcs;
begin
  // Aufrufe im Hintergrund; fehlt git bzw. svn, einmal eine Zeile (#571).
  TAtlasIdeVcsCore.Start(MessageLine, Backend);
  TAtlasIdeBranching.ServerCommand := ServerCommand;
  TAtlasIdeVcs.Bind(TAtlasVcsServiceAdapter.Create, TAtlasVcsDialogsAdapter.Create);
  // Änderungsmarken und Zeilenhistorie (#507, #1905): mit den Haken, die der Tracker schon abgelegt hat.
  TAtlasIdeLineChanges.Install(
    procedure(AText: string)
    begin
      MessageLine(AText);
    end);
  TAtlasIdeLineChanges.SetBlameHooks(TAtlasLineChangeMarks.BlameHooks);
  TAtlasLineChangeMarks.Bind(TAtlasLineChangesAdapter.Create);
  GStarted := True;
end;

procedure StopVcs;
begin
  GStarted := False;
  // Zuerst den Zugang von Base zurücknehmen: Danach erreicht kein Aufruf mehr das Modul (Regel 3).
  TAtlasLineChangeMarks.Bind(nil);
  TAtlasIdeLineChanges.Uninstall;
  TAtlasIdeVcs.Unbind;
  TAtlasIdeBranching.ServerCommand := nil;
  TAtlasIdeVcsCore.Stop;
end;

function VcsStarted: Boolean;
begin
  Result := GStarted;
end;

{ TAtlasVcsServiceAdapter }

procedure TAtlasVcsServiceAdapter.Report(const AText: string);
begin
  TAtlasIdeVcsCore.Report(AText);
end;

function TAtlasVcsServiceAdapter.Provider: TAtlasVcsProvider;
begin
  Result := TAtlasIdeVcsCore.Provider;
end;

function TAtlasVcsServiceAdapter.TimeoutMs: Cardinal;
begin
  Result := TAtlasIdeVcsCore.TimeoutMs;
end;

procedure TAtlasVcsServiceAdapter.Reload;
begin
  TAtlasIdeVcsCore.Reload;
end;

function TAtlasVcsServiceAdapter.ForFolder(const AFolder: string; ATimeoutMs: Cardinal): IAtlasVersionControl;
begin
  Result := TAtlasIdeVcsCore.ForFolder(AFolder, ATimeoutMs);
end;

function TAtlasVcsServiceAdapter.ForFolderResolution(const AFolder: string): TAtlasVcsProjectResolution;
begin
  Result := TAtlasIdeVcsCore.ForFolderResolution(AFolder);
end;

function TAtlasVcsServiceAdapter.ForProjectResolution(const AProjectFile, AGroupFile: string):
  TAtlasVcsProjectResolution;
begin
  Result := TAtlasIdeVcsCore.ForProjectResolution(AProjectFile, AGroupFile);
end;

function TAtlasVcsServiceAdapter.MainBranchOf(const AProjectFile, AGroupFile: string): string;
begin
  Result := TAtlasIdeVcsCore.MainBranchOf(AProjectFile, AGroupFile);
end;

function TAtlasVcsServiceAdapter.Projects: TArray<TAtlasVcsProjectMapping>;
begin
  Result := TAtlasIdeVcsCore.Projects;
end;

function TAtlasVcsServiceAdapter.Run(const AWork, ADone: TProc): Boolean;
begin
  Result := TAtlasIdeVcsCore.Run(AWork, ADone);
end;

function TAtlasVcsServiceAdapter.Locate(AKind: TAtlasVcsKind; const APath: string): TAtlasVcsToolLocation;
begin
  Result := TAtlasIdeVcsCore.Locate(AKind, APath);
end;

function TAtlasVcsServiceAdapter.CheckTool(AKind: TAtlasVcsKind; const APath: string;
  const ADone: TProc<TAtlasVcsToolCheck>): Boolean;
begin
  Result := TAtlasIdeVcsCore.CheckTool(AKind, APath, ADone);
end;

function TAtlasVcsServiceAdapter.QueryProject(const AProjectFile, AGroupFile: string;
  const ADone: TProc<TAtlasVcsProjectState>): Boolean;
begin
  Result := TAtlasIdeVcsCore.QueryProject(AProjectFile, AGroupFile, ADone);
end;

function TAtlasVcsServiceAdapter.CheckServer(const AFolder: string;
  const ADone: TProc<TAtlasVcsServerCheck>): Boolean;
begin
  Result := TAtlasIdeVcsCore.CheckServer(AFolder, ADone);
end;

function TAtlasVcsServiceAdapter.ServerState(const AFolder: string): TAtlasVcsServerCheck;
begin
  Result := TAtlasIdeVcsCore.ServerState(AFolder);
end;

function TAtlasVcsServiceAdapter.OpenServerLogin(const ACheck: TAtlasVcsServerCheck; const AClosed: TProc): Boolean;
begin
  Result := TAtlasIdeVcsCore.OpenServerLogin(ACheck, AClosed);
end;

{ TAtlasVcsDialogsAdapter }

procedure TAtlasVcsDialogsAdapter.CreateBranchFor(const AProject: string; const ADone: TProc);
begin
  TAtlasIdeBranching.CreateFor(AProject, ADone);
end;

procedure TAtlasVcsDialogsAdapter.ShowWorkingCopies(const AProject: string; const ADone: TProc);
begin
  TAtlasIdeWorkingCopies.ShowFor(AProject, ADone);
end;

function TAtlasVcsDialogsAdapter.AskBranch(const AFolder: string; const AFacts: TAtlasVcsBranchFacts; const AName,
  AMessage, AKey: string; const ASvn: TAtlasVcsSvnBranchOptions; AOfferNeverAsk: Boolean;
  out ARequest: TAtlasVcsBranchRequest; out ANeverAsk: Boolean): Boolean;
begin
  Result := TAtlasIdeBranching.Ask(AFolder, AFacts, TAtlasIdeBranching.Setup(AName, AMessage, AKey, ASvn,
    AOfferNeverAsk), ARequest, ANeverAsk);
end;

function TAtlasVcsDialogsAdapter.SvnOptions(const AProject: string): TAtlasVcsSvnBranchOptions;
begin
  Result := TAtlasIdeBranching.SvnOptions(AProject);
end;

function TAtlasVcsDialogsAdapter.GitOptions: TAtlasVcsGitBranchOptions;
begin
  Result := TAtlasIdeBranching.GitOptions;
end;

procedure TAtlasVcsDialogsAdapter.OfferOpen(const AProject, ARoot, AFolder: string);
begin
  TAtlasIdeBranching.OfferOpen(AProject, ARoot, AFolder);
end;

function TAtlasVcsDialogsAdapter.ServerState(AOutcome: TAtlasVcsOutcome): string;
begin
  Result := TAtlasIdeBranching.ServerState(AOutcome);
end;

function TAtlasVcsDialogsAdapter.AskLocal(const AFacts: TAtlasVcsBranchFacts; const ARequest: TAtlasVcsBranchRequest;
  const ASteps: TArray<TAtlasVcsBranchStep>; const ARun: TAtlasVcsBranchRun;
  out AFallback: TAtlasVcsBranchRequest): Boolean;
begin
  Result := TAtlasIdeBranching.AskLocal(AFacts, ARequest, ASteps, ARun, AFallback);
end;

function TAtlasVcsDialogsAdapter.AskUncommitted(AChanges: Integer; const AName: string; out AStash: Boolean): Boolean;
begin
  Result := TAtlasIdeBranching.AskUncommitted(AChanges, AName, AStash);
end;

function TAtlasVcsDialogsAdapter.WorktreeProject(const AProject, ARoot, AFolder: string): string;
begin
  Result := TAtlasIdeBranching.WorktreeProject(AProject, ARoot, AFolder);
end;

function TAtlasVcsDialogsAdapter.OfferWorktree(const AName, AFolder, ATarget: string): Boolean;
begin
  Result := TAtlasIdeBranching.OfferWorktree(AName, AFolder, ATarget);
end;

procedure TAtlasVcsDialogsAdapter.StopAsking;
begin
  TAtlasIdeBranching.StopAsking;
end;

procedure TAtlasVcsDialogsAdapter.RebuildIndex;
begin
  TAtlasIdeBranching.RebuildIndex;
end;

function TAtlasVcsDialogsAdapter.Progress(AKind: TAtlasVcsKind): TAtlasVcsBranchProgress;
begin
  Result := TAtlasIdeBranching.Progress(AKind);
end;

function TAtlasVcsDialogsAdapter.FailureText(AKind: TAtlasVcsKind; const ASteps: TArray<TAtlasVcsBranchStep>;
  const ARun: TAtlasVcsBranchRun): string;
begin
  Result := TAtlasIdeBranching.FailureText(AKind, ASteps, ARun);
end;

{ TAtlasVcsAppliesSettings }

procedure TAtlasVcsAppliesSettings.ApplySettings;
begin
  TAtlasIdeVcs.Reload;
  // Änderungsmarken (#507, seit #1905 im Modul): nur, solange der Teil läuft.
  if GStarted then
  begin
    TAtlasIdeLineChanges.ApplySettings;
  end;
end;

procedure TAtlasVcsAppliesSettings.ThemeChanged;
begin
  if GStarted then
  begin
    TAtlasIdeLineChanges.ThemeChanged;
  end;
end;

{ TAtlasVcsModule }

function TAtlasVcsModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Versionsverwaltung';
  Result.Version := TAtlasVersion.cVersion;
  Result.Handle := HInstance;
  // Die Versionsverwaltung lief bisher auch im abgesicherten Start (Projektzustand, Änderungsmarken).
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasVcsModule.Start;
begin
  FActive := True;
end;

procedure TAtlasVcsModule.Stop;
begin
  FActive := False;
end;

function TAtlasVcsModule.IsActive: Boolean;
begin
  Result := FActive;
end;

class function TAtlasVcsModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [TAtlasFeaturePart.AtLevel('Vcs', TAtlasSafeLevel.Safe, VcsStarted, StartVcs, StopVcs)];
end;

class function TAtlasVcsModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasVcsModule;
  mApplies: TAtlasVcsAppliesSettings;
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
  mModule := TAtlasVcsModule.Create;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  // Vertrag in der Registry (#1903): Beiträge anderer Module zum Optionsdialog (Branches zu Issues des Trackers)
  // finden darüber ihren Gastgeber. Genutzt wird der Dienst weiter über TAtlasIdeVcs, sobald der Teil läuft.
  GScope.Provide(IAtlasVcsService, TAtlasVcsServiceAdapter.Create as IAtlasVcsService);
  // Befehle „Branch anlegen …“ und „Arbeitskopien“ (#1905, vorher in der Palette von Base).
  GScope.Provide(IAtlasCommandSource, TAtlasVcsCommands.Create as IAtlasCommandSource);
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeVcsSettings.Create as IAtlasSettingsSectionProvider);
  mApplies := TAtlasVcsAppliesSettings.Create;
  GScope.Provide(IAtlasAppliesSettings, mApplies as IAtlasAppliesSettings);
  GScope.Provide(IAtlasFollowsTheme, mApplies as IAtlasFollowsTheme);
  Result := True;
end;

class procedure TAtlasVcsModule.UnregisterModule;
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
  TAtlasVcsModule.RegisterModule;

finalization
  TAtlasVcsModule.UnregisterModule;

end.
