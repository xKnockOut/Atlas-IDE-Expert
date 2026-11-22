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
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7). Die Modulklasse
// (Adapters.Module), den Dienst (Adapters.Service) und die Dialoge (Adapters.Dialogs) erzeugt sie nur.

interface

implementation

uses
  System.SysUtils,
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.Core.VersionControl.Composition,
  Atlas.IDE.VersionControl.Adapters.Commands,
  Atlas.IDE.VersionControl.LineChanges,
  Atlas.IDE.VersionControl.Adapters.LineChanges,
  Atlas.IDE.Contracts.LineChanges,
  Atlas.Core.VersionControl.Providers.ProcessRunner,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.VersionControl.Service,
  Atlas.IDE.VersionControl.Branching,
  Atlas.IDE.VersionControl.Adapters.Settings,
  Atlas.IDE.VersionControl.Adapters.Service,
  Atlas.IDE.VersionControl.Adapters.Dialogs,
  Atlas.IDE.VersionControl.Adapters.Module,
  Atlas.UI.Settings.Contract;

const
  /// <summary>Zeitlimit des Serverbefehls nach einem Branch.</summary>
  cServerCommandMs = 30000;

var
  GScope: IAtlasModuleScope;
  GStarted: Boolean;

{ Dienste von Base }

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
  TAtlasIdeVcsCore.Start(TAtlasIdeHost.Messages(), Backend);
  TAtlasIdeBranching.ServerCommand := ServerCommand;
  TAtlasIdeVcs.Bind(TAtlasVcsServiceAdapter.Create, TAtlasVcsDialogsAdapter.Create);
  // Änderungsmarken und Zeilenhistorie (#507, #1905): mit den Haken, die der Tracker schon abgelegt hat.
  TAtlasIdeLineChanges.Install(TAtlasIdeHost.Messages());
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

{ Anmeldung }

function Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [TAtlasFeaturePart.AtLevel('Vcs', TAtlasSafeLevel.Safe, VcsStarted, StartVcs, StopVcs)];
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasVcsModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasVcsModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion, GScope,
    mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasVcsModule.Create(VcsStarted);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  // Vertrag in der Registry (#1903): Beiträge anderer Module zum Optionsdialog (Branches zu Issues des Trackers)
  // finden darüber ihren Gastgeber. Genutzt wird der Dienst weiter über TAtlasIdeVcs, sobald der Teil läuft.
  GScope.Provide(IAtlasVcsService, TAtlasVcsServiceAdapter.Create as IAtlasVcsService);
  // Befehle „Branch anlegen …“ und „Arbeitskopien“ (#1905).
  GScope.Provide(IAtlasCommandSource, TAtlasVcsCommands.Create as IAtlasCommandSource);
  // Modulschalter im Optionsdialog ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeVcsSettings.Create as IAtlasSettingsSectionProvider);
  // Nach dem Speichern der Optionen (#1905) und beim Wechsel des Themas.
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasVcsModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
