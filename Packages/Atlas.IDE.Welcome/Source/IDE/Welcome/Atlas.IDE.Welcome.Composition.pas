unit Atlas.IDE.Welcome.Composition;

// Modul Willkommensseite (#1455): einzige Unit, die die
// Willkommensseite (#753) erzeugt. Sie meldet in ihrer Initialisierung das
// Modul „atlas.welcome“ (Modulschalter welcome) bei der Registry von Base an
// und stellt über dessen Scope bereit:
// - den Teil Welcome der Feature-Tabelle (Aufbau in
//   TAtlasIdeWelcomeStartup); er läuft auch im abgesicherten Start, sobald
//   die Zeilen des Statusfelds laufen, die die Zustandskachel (#754) zeigt,
// - die Befehle der Seite (Palette und Atlas-Menü): Atlas-Start, Layout
//   anwenden und zurücksetzen, Seite anpassen (#767), „Neu in Atlas“ (#756),
//   Projekt einrichten (#759) und Weiterarbeiten (#755); der Zugang zum
//   Build-Server (#763) gehört mit der Kachel „Testergebnisse“
//   zum Modul Tracker,
// - die Einträge im Atlas-Menü und unter Ansicht › Atlas,
// - Einstellungen und Thema an die laufende Seite,
// - den Abschnitt der Optionsseite (Atlas.IDE.Welcome.Adapters.Settings).
// Modulklasse, Befehle und Menüeinträge stehen in Atlas.IDE.Welcome.Adapters.Module.
// Andere Module erreicht die Seite nur über Verträge (TAtlasWelcomeNeighbors,
// Kacheln über Atlas.IDE.Base.Foundation.WelcomeTiles). Abmelden in der
// Finalisierung, solange Base läuft (Regel 5); passt die Vertragsversion von
// Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

implementation

uses
  System.SysUtils,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Base.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Welcome.Adapters.Settings,
  Atlas.IDE.Welcome.Adapters.SettingsSection,
  Atlas.IDE.Welcome.Adapters.Discover,
  Atlas.UI.Welcome.SettingsSection,
  Atlas.IDE.Welcome.Adapters.Setup,
  Atlas.IDE.Welcome.Composition.Startup,
  Atlas.UI.Settings.Contract,
  Atlas.IDE.Welcome.Adapters.Module;

var
  GScope: IAtlasModuleScope;

{ Teil Welcome }

procedure StartPage;
begin
  TAtlasIdeWelcomeStartup.Start(GScope);
end;

procedure StopPage;
begin
  TAtlasIdeWelcomeStartup.Stop;
end;

function PageStarted: Boolean;
begin
  Result := TAtlasIdeWelcomeStartup.Current <> nil;
end;

{ Zugriff der Modulklasse auf die laufende Seite }

function CurrentPage: TAtlasIdeWelcome;
begin
  Result := TAtlasIdeWelcomeStartup.Current;
end;

function HasNews: Boolean;
begin
  Result := (TAtlasIdeWelcomeStartup.Areas <> nil) and (TAtlasIdeWelcomeStartup.Areas.WhatsNew <> nil);
end;

function SetupActive: Boolean;
begin
  Result := TAtlasIdeSetup.Active;
end;

function AskSetup: Boolean;
begin
  Result := (TAtlasIdeWelcomeStartup.Areas <> nil) and (TAtlasIdeWelcomeStartup.Areas.Setup <> nil);
  if Result then
  begin
    TAtlasIdeWelcomeStartup.Areas.Setup.Ask;
  end;
end;

procedure ResumeLatest;
begin
  if (TAtlasIdeWelcomeStartup.Areas <> nil) and (TAtlasIdeWelcomeStartup.Areas.ContinueWork <> nil) then
  begin
    TAtlasIdeWelcomeStartup.Areas.ContinueWork.ResumeLatest;
  end;
end;

function ModuleHooks: TAtlasWelcomeModuleHooks;
begin
  Result := Default(TAtlasWelcomeModuleHooks);
  Result.Page := CurrentPage;
  Result.HasNews := HasNews;
  Result.SetupActive := SetupActive;
  Result.AskSetup := AskSetup;
  Result.ResumeLatest := ResumeLatest;
end;

{ Optionsdialog }

function WrapSettings(ASection: TAtlasWelcomeSettingsSection): IAtlasSettingsSection;
begin
  Result := TAtlasIdeWelcomeSettingsSection.Create(ASection);
end;

/// <summary>„Gesperrte Tipps wieder zeigen“ (#757).</summary>
procedure UnblockTips;
begin
  TAtlasIdeDiscover.UnblockAll;
end;

function Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Abbau vor dem Statusfeld, dessen Zeilen die Zustandskachel beobachtet.
    TAtlasFeaturePart.When('Welcome',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeHost.StatusLinesReady;
      end, PageStarted, StartPage, StopPage)];
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasWelcomeModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasWelcomeModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasWelcomeModule.Create(ModuleHooks);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  // Ab der Anmeldung: Die Seite lässt sich auch bei ausgeschaltetem Modul einstellen.
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeWelcomeSettings.Create(WrapSettings, UnblockTips) as
    IAtlasSettingsSectionProvider);
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasWelcomeModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
