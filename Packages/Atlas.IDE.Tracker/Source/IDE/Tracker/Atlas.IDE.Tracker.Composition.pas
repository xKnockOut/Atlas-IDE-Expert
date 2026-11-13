unit Atlas.IDE.Tracker.Composition;

// Modul Tracker (#1455): meldet in ihrer Initialisierung das Modul
// „atlas.tracker“ (Modulschalter issues, #1454) bei der Registry von Base an
// und stellt über dessen Scope bereit:
// - die Teile MyIssues, IssueLinks, BlameIssues und TestResults der
//   Feature-Tabelle samt Befehlen, Menüeinträgen, Taste, Einstellungen und
//   Palette (Atlas.IDE.Tracker.Parts),
// - den Zugang zum Tracker (IAtlasTrackerAccess) ab der Anmeldung, auch
//   ausgeschaltet für den Abschnitt „Issue-Tracker“ im Optionsdialog
//   (Atlas.IDE.Tracker.Settings, damit man es einstellen kann).
// Rolle Adapters nur hier (#1455): Anmeldespeicher (TAtlasCiCredentialStore),
// HTTP-Transporte (TAtlasCiHttpTransports) und die Anbieter (YouTrack, GitHub,
// Jenkins) entstehen in dieser Unit und gehen als Schnittstellen an
// TAtlasTrackerAccess und TAtlasCiAccess (Atlas.IDE.Tracker.Access).
// Ebenso Platte und Shell (#1455 Paket 2d): TAtlasTrackerLocalFiles und
// TAtlasTrackerShellExecute meldet RegisterModule vor allen Teilen bei
// Atlas.Core.Tracker.Files an, UnregisterModule meldet sie zuletzt ab.
// Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Modules.Contract;

type
  TAtlasTrackerModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasPaletteSourceProvider)
  public const
    cModuleId = 'atlas.tracker';
    cSwitch = 'issues';
  private
    FActive: Boolean;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    /// <summary>Geänderte Einstellungen an „Meine Issues“, Sprint und „Testergebnisse“.</summary>
    procedure ApplySettings;
    /// <summary>Issues in der Befehlspalette (#1270); nil ohne „Meine Issues“.</summary>
    function PaletteSource: IAtlasPaletteSource;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Host,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Ci.Adapters.Credentials,
  Atlas.Core.Ci.Adapters.Http,
  Atlas.Core.Ci.Providers.Jenkins,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Connections,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.Adapters.LocalFiles,
  Atlas.Core.Tracker.Adapters.Shell,
  Atlas.Core.Tracker.Providers.GitHub,
  Atlas.Core.Tracker.Providers.YouTrack,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Tracker.Access,
  Atlas.IDE.Tracker.Parts,
  Atlas.IDE.Tracker.Settings,
  Atlas.UI.Tracker.SettingsBranches,
  Atlas.IDE.Contracts.VersionControl,
  Atlas.UI.Settings.Contract;

var
  GScope: IAtlasModuleScope;

{ Adapter (nur hier) }

/// <summary>Anbieter des Issue-Trackers: YouTrack und GitHub, je Aufruf neu; weitere kommen ohne Änderung an
/// Kachel und Optionsseite dazu.</summary>
function TrackerProviders: TAtlasTrackerProvidersFactory;
begin
  Result :=
    function: TArray<IAtlasTrackerProvider>
    begin
      SetLength(Result, 2);
      Result[0] := TAtlasYouTrackTracker.Create;
      Result[1] := TAtlasGitHubTracker.Create;
    end;
end;

/// <summary>CI-Anbieter zum Namen: Jenkins als erster Adapter; nil für unbekannte.</summary>
function CiProvider(const AName: string): IAtlasCiProvider;
begin
  Result := nil;
  if SameText(AName, TAtlasJenkinsProvider.cProviderName) then
  begin
    Result := TAtlasJenkinsProvider.Create;
  end;
end;

// Ergebnis von „Zugang … hinterlegen“: nur Meldungsansicht und sichtbar, weil es auf eine Aktion folgt.
procedure AccessNotice(AText: string);
begin
  TAtlasIdeHost.Message(AText);
  TAtlasIdeHost.ShowMessages;
end;

/// <summary>Anmeldespeicher von Windows und HTTP-Transporte für beide Zugänge.</summary>
function AccessParts: TAtlasAccessParts;
begin
  Result := Default(TAtlasAccessParts);
  Result.Credentials := TAtlasCiCredentialStore.Create;
  Result.Transports := TAtlasCiHttpTransports.Create;
  Result.Notice := AccessNotice;
end;

{ TAtlasTrackerModule }

/// <summary>Stellt ein Modul den Vertrag der Versionsverwaltung bereit (#1903)?</summary>
function VcsProvided: Boolean;
begin
  Result := Length(AtlasModuleRegistry.FindAll(IAtlasVcsService)) > 0;
end;

function TAtlasTrackerModule.Info: TAtlasModuleInfo;
begin
  // Lief mit der Willkommensseite schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Issue-Tracker', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;

procedure TAtlasTrackerModule.Start;
begin
  FActive := True;
end;

procedure TAtlasTrackerModule.Stop;
begin
  FActive := False;
end;

function TAtlasTrackerModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasTrackerModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := TAtlasTrackerParts.Commands;
end;

procedure TAtlasTrackerModule.ApplySettings;
begin
  TAtlasTrackerParts.ApplySettings;
end;

function TAtlasTrackerModule.PaletteSource: IAtlasPaletteSource;
begin
  Result := TAtlasTrackerParts.PaletteSource;
end;

function TAtlasTrackerModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := TAtlasTrackerParts.MenuEntries;
end;

function TAtlasTrackerModule.Keys: TArray<TAtlasModuleKey>;
begin
  Result := TAtlasTrackerParts.Keys;
end;

class function TAtlasTrackerModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasTrackerModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
  mAccess: IAtlasTrackerAccess;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasTrackerModule.Create;
  mRef := mModule as IAtlasModule;
  // Platte und Shell vor allen Teilen: Sie lesen schon beim Start (Meldungen, Zeiterfassung, Board).
  TAtlasTrackerFiles.Install(TAtlasTrackerLocalFiles.Create, TAtlasTrackerShellExecute.Create);
  GScope := mRegistry.RegisterModule(mModule);
  // Ab der Anmeldung: Der Abschnitt Issue-Tracker braucht den Zugang auch bei ausgeschaltetem Modul.
  mAccess := TAtlasTrackerAccess.Create(TrackerProviders(), AccessParts);
  GScope.Provide(IAtlasTrackerAccess, mAccess);
  TAtlasTrackerParts.Install(GScope, mAccess, TAtlasCiAccess.Create(CiProvider, AccessParts));
  for mPart in TAtlasTrackerParts.Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasPaletteSourceProvider, mRef);
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeTrackerSettings.Create as IAtlasSettingsSectionProvider);
  // Unterpunkt „Versionsverwaltung“ (#1903): nur, wenn ein Modul deren Vertrag bereitstellt.
  TAtlasTrackerBranchSection.Available := VcsProvided;
  TAtlasTrackerBranchSection.ProvideBranches(GScope);
  Result := True;
end;

/// <summary>Modulspezifische Schritte nach dem Abmelden aus der Registry.</summary>
procedure ReleaseModule;
begin
  // Laufende Prüfungen der Optionsseite: Ihre Antwort erreicht das Modul danach nicht mehr (Regel 3).
  TAtlasIdeTrackerSettings.Release;
  TAtlasTrackerBranchSection.Available := nil;
  // Erst jetzt: Die Teile sind gestoppt, kein Hintergrund-Thread liest den Zugang mehr.
  TAtlasTrackerParts.Uninstall;
  // Zuletzt: Danach erreicht nichts mehr Platte oder Shell im Namen des Moduls (Regel 3).
  TAtlasTrackerFiles.Uninstall;
end;

class procedure TAtlasTrackerModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, ReleaseModule);
end;

initialization
  TAtlasTrackerModule.RegisterModule;

finalization
  TAtlasTrackerModule.UnregisterModule;

end.
