unit Atlas.IDE.Welcome.Composition;

// Modul Willkommensseite (#1455, ADR 0017): einzige Unit, die die
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
// - den Abschnitt der Optionsseite (Atlas.IDE.Welcome.Settings).
// Andere Module erreicht die Seite nur über Verträge (TAtlasWelcomeNeighbors,
// Kacheln über Atlas.IDE.Contracts.WelcomeTiles). Abmelden in der
// Finalisierung, solange Base läuft (Regel 5); passt die Vertragsversion von
// Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

type
  TAtlasWelcomeModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    cModuleId = 'atlas.welcome';
    cSwitch = 'welcome';
  private
    FActive: Boolean;
    class function Parts: TArray<IAtlasFeaturePart>; static;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Modules.Handshake,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Welcome.Layouts,
  Atlas.IDE.Welcome.Settings,
  Atlas.IDE.Welcome.Setup,
  Atlas.IDE.Welcome.Startup,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Welcome.Strings;

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

/// <summary>Die laufende Seite, wenn welcomePage.enabled an ist; sonst nil.</summary>
function ShownPage: TAtlasIdeWelcome;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.WelcomePage then
  begin
    Result := TAtlasIdeWelcomeStartup.Current;
  end;
end;

{ Sichtbarkeit wie früher im Atlas-Menü }

function PageVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.WelcomePage;
end;

/// <summary>Atlas-Bereiche auf der Willkommensseite der IDE (welcomePage.ideWelcomePage), AAtlas = Atlas-Layout
/// aktiv.</summary>
function IdePageWith(AAtlas: Boolean): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.WelcomePage and mSettings.WelcomePageIdePage and
    (SameText(mSettings.WelcomePageLayout, 'atlas') = AAtlas);
end;

function ApplyVisible: Boolean;
begin
  Result := IdePageWith(False);
end;

function ResetVisible: Boolean;
begin
  Result := IdePageWith(True);
end;

function CustomizeVisible: Boolean;
begin
  Result := (TAtlasIdeWelcomeStartup.Current <> nil) and TAtlasIdeWelcomeStartup.Current.Layouts.CanCustomize;
end;

function SetupVisible: Boolean;
begin
  Result := TAtlasIdeSetup.Active;
end;

{ Befehle }

procedure ShowStart;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if mPage <> nil then
  begin
    mPage.ShowStart;
  end;
end;

procedure ApplyLayout;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if mPage <> nil then
  begin
    mPage.ApplyLayout;
  end;
end;

procedure ResetLayout;
begin
  // Auch bei abgeschalteter Seite: Das Layout der IDE soll sich immer zurückholen lassen.
  if TAtlasIdeWelcomeStartup.Current <> nil then
  begin
    TAtlasIdeWelcomeStartup.Current.ResetLayout;
  end;
end;

procedure Customize;
begin
  if TAtlasIdeWelcomeStartup.Current <> nil then
  begin
    TAtlasIdeWelcomeStartup.Current.Customize;
  end;
end;

procedure ShowNews(AView: TAtlasWhatsNewView);
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if (mPage <> nil) and (mPage.Areas.WhatsNew <> nil) then
  begin
    mPage.ShowWhatsNew(AView);
  end;
end;

procedure ShowCurrentNews;
begin
  ShowNews(TAtlasWhatsNewView.Current);
end;

procedure ShowAllNews;
begin
  ShowNews(TAtlasWhatsNewView.All);
end;

procedure AskSetup;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := TAtlasIdeWelcomeStartup.Current;
  if (mPage = nil) or (mPage.Areas.Setup = nil) or not TAtlasIdeSetup.Active then
  begin
    Exit;
  end;
  mPage.Areas.Setup.Ask;
  mPage.ShowStart;
end;

procedure ContinueLatest;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := TAtlasIdeWelcomeStartup.Current;
  if (mPage <> nil) and (mPage.Areas.ContinueWork <> nil) then
  begin
    mPage.Areas.ContinueWork.ResumeLatest;
  end;
end;

function Command(const AId: string; ACaption: TAtlasWelcomeTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasWelcomeStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
end;

{ TAtlasWelcomeModule }

function TAtlasWelcomeModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Willkommensseite';
  Result.Version := TAtlasVersion.cVersion;
  Result.Handle := HInstance;
  // Die Seite startet keinen Server und liest nur lokale Daten: auch im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasWelcomeModule.Start;
begin
  FActive := True;
end;

procedure TAtlasWelcomeModule.Stop;
begin
  FActive := False;
end;

function TAtlasWelcomeModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasWelcomeModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    Command('Atlas.WelcomeStart', TAtlasWelcomeTextId.MenuWelcomeStart, ShowStart, PageVisible),
    Command('Atlas.WelcomeApply', TAtlasWelcomeTextId.MenuWelcomeApply, ApplyLayout, ApplyVisible),
    Command('Atlas.WelcomeReset', TAtlasWelcomeTextId.MenuWelcomeReset, ResetLayout, ResetVisible),
    Command(TAtlasIdeWelcomeLayouts.cCommandId, TAtlasWelcomeTextId.CommandWelcomeCustomize, Customize,
      CustomizeVisible),
    Command('Atlas.WhatsNew', TAtlasWelcomeTextId.WelcomeNewsShowCurrent, ShowCurrentNews, PageVisible),
    Command('Atlas.WhatsNewAll', TAtlasWelcomeTextId.WelcomeNewsShowAllCommand, ShowAllNews, PageVisible),
    // Bereich „Projekt für Atlas einrichten“ (#759): Frage erneut stellen.
    Command('Atlas.ProjectSetup', TAtlasWelcomeTextId.WelcomeSetupCommand, AskSetup, SetupVisible),
    // Bereich „Weiterarbeiten“ (#755): obersten Arbeitsstand fortsetzen.
    Command('Atlas.Continue', TAtlasWelcomeTextId.WelcomeContinueCommand, ContinueLatest, nil)];
end;

function TAtlasWelcomeModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  // Atlas-Start auch unter Ansicht › Atlas; Atlas-Menü mit Trennlinie vor den Einträgen der Seite.
  Result := [
    MenuEntry('-', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.WelcomeStart', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.WelcomeApply', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.WelcomeReset', TAtlasMenuPlace.AtlasMenu),
    MenuEntry('Atlas.WelcomeStart', TAtlasMenuPlace.ViewMenu)];
end;

procedure TAtlasWelcomeModule.ApplySettings;
begin
  if TAtlasIdeWelcomeStartup.Current <> nil then
  begin
    TAtlasIdeWelcomeStartup.Current.Sync;
  end;
end;

procedure TAtlasWelcomeModule.ThemeChanged;
begin
  if TAtlasIdeWelcomeStartup.Current <> nil then
  begin
    TAtlasIdeWelcomeStartup.Current.ThemeChanged;
  end;
end;

class function TAtlasWelcomeModule.Parts: TArray<IAtlasFeaturePart>;
begin
  Result := [
    // Abbau vor dem Statusfeld, dessen Zeilen die Zustandskachel beobachtet.
    TAtlasFeaturePart.When('Welcome',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeHost.StatusLinesReady;
      end, PageStarted, StartPage, StopPage)];
end;

class function TAtlasWelcomeModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasWelcomeModule;
  mRef: IInterface;
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
  mModule := TAtlasWelcomeModule.Create;
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
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeWelcomeSettings.Create as IAtlasSettingsSectionProvider);
  Result := True;
end;

class procedure TAtlasWelcomeModule.UnregisterModule;
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
  TAtlasWelcomeModule.RegisterModule;

finalization
  TAtlasWelcomeModule.UnregisterModule;

end.
