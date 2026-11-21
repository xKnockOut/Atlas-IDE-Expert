unit Atlas.IDE.Welcome.Adapters.Module;

// Modulklasse der Willkommensseite (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Welcome.Composition) über den Scope des Moduls bereitstellt:
// - die Befehle der Seite (Palette und Atlas-Menü): Atlas-Start, Layout anwenden und zurücksetzen, Seite anpassen
//   (#767), „Neu in Atlas“ (#756), Projekt einrichten (#759) und Weiterarbeiten (#755),
// - die Einträge im Atlas-Menü und unter Ansicht › Atlas,
// - Einstellungen und Thema an die laufende Seite.
// Die laufende Seite und ihre Bereiche baut die Composition (TAtlasIdeWelcomeStartup); sie reicht den Zugriff
// darauf als TAtlasWelcomeModuleHooks herein, weil ein Adapter die Composition nicht einbindet.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Commands;

type
  /// <summary>Zugriff auf die laufende Seite und ihre Bereiche.</summary>
  TAtlasWelcomeModuleHooks = record
    /// <summary>Die laufende Seite; nil vor dem Start und nach dem Stop.</summary>
    Page: TFunc<TAtlasIdeWelcome>;
    /// <summary>Hat die laufende Seite den Bereich „Neu in Atlas“?</summary>
    HasNews: TFunc<Boolean>;
    /// <summary>Ist das Projekt noch für Atlas einzurichten (#759)?</summary>
    SetupActive: TFunc<Boolean>;
    /// <summary>Frage „Projekt für Atlas einrichten“ erneut stellen; False ohne den Bereich.</summary>
    AskSetup: TFunc<Boolean>;
    /// <summary>Obersten Arbeitsstand fortsetzen, wenn die Seite den Bereich „Weiterarbeiten“ hat.</summary>
    ResumeLatest: TProc;
  end;

  TAtlasWelcomeModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    cModuleId = 'atlas.welcome';
    cSwitch = 'welcome';
  private
    FActive: Boolean;
    FHooks: TAtlasWelcomeModuleHooks;
    /// <summary>Die laufende Seite, wenn welcomePage.enabled an ist; sonst nil.</summary>
    function ShownPage: TAtlasIdeWelcome;
    function CustomizeVisible: Boolean;
    function SetupVisible: Boolean;
    procedure ShowStart;
    procedure ApplyLayout;
    procedure ResetLayout;
    procedure Customize;
    procedure ShowNews(AView: TAtlasWhatsNewView);
    procedure ShowCurrentNews;
    procedure ShowAllNews;
    procedure AskSetup;
    procedure ContinueLatest;
  public
    constructor Create(const AHooks: TAtlasWelcomeModuleHooks);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Settings.Plugin,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Welcome.Layouts,
  Atlas.UI.Welcome.Strings;

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

/// <summary>Eintrag im eigenen Untermenü des Atlas-Menüs („-“ = Trennlinie).</summary>
function AtlasEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.AtlasMenu);
  Result.Section := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.MenuGroupWelcome);
end;

{ TAtlasWelcomeModule }

constructor TAtlasWelcomeModule.Create(const AHooks: TAtlasWelcomeModuleHooks);
begin
  inherited Create;
  FHooks := AHooks;
end;

function TAtlasWelcomeModule.ShownPage: TAtlasIdeWelcome;
begin
  Result := nil;
  if TAtlasIdeSettings.Current.WelcomePage then
  begin
    Result := FHooks.Page();
  end;
end;

function TAtlasWelcomeModule.CustomizeVisible: Boolean;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := FHooks.Page();
  Result := (mPage <> nil) and mPage.Layouts.CanCustomize;
end;

function TAtlasWelcomeModule.SetupVisible: Boolean;
begin
  Result := FHooks.SetupActive();
end;

procedure TAtlasWelcomeModule.ShowStart;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if mPage <> nil then
  begin
    mPage.ShowStart;
  end;
end;

procedure TAtlasWelcomeModule.ApplyLayout;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if mPage <> nil then
  begin
    mPage.ApplyLayout;
  end;
end;

procedure TAtlasWelcomeModule.ResetLayout;
var
  mPage: TAtlasIdeWelcome;
begin
  // Auch bei abgeschalteter Seite: Das Layout der IDE soll sich immer zurückholen lassen.
  mPage := FHooks.Page();
  if mPage <> nil then
  begin
    mPage.ResetLayout;
  end;
end;

procedure TAtlasWelcomeModule.Customize;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := FHooks.Page();
  if mPage <> nil then
  begin
    mPage.Customize;
  end;
end;

procedure TAtlasWelcomeModule.ShowNews(AView: TAtlasWhatsNewView);
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := ShownPage;
  if (mPage <> nil) and FHooks.HasNews() then
  begin
    mPage.ShowWhatsNew(AView);
  end;
end;

procedure TAtlasWelcomeModule.ShowCurrentNews;
begin
  ShowNews(TAtlasWhatsNewView.Current);
end;

procedure TAtlasWelcomeModule.ShowAllNews;
begin
  ShowNews(TAtlasWhatsNewView.All);
end;

procedure TAtlasWelcomeModule.AskSetup;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := FHooks.Page();
  if (mPage = nil) or not FHooks.SetupActive() then
  begin
    Exit;
  end;
  if FHooks.AskSetup() then
  begin
    mPage.ShowStart;
  end;
end;

procedure TAtlasWelcomeModule.ContinueLatest;
begin
  if FHooks.Page() <> nil then
  begin
    FHooks.ResumeLatest();
  end;
end;

function TAtlasWelcomeModule.Info: TAtlasModuleInfo;
begin
  // Die Seite startet keinen Server und liest nur lokale Daten: auch im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Willkommensseite', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
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
  // Atlas-Start auch unter Ansicht › Atlas; im Atlas-Menü im Untermenü Willkommensseite.
  Result := [
    AtlasEntry('Atlas.WelcomeStart'),
    AtlasEntry('Atlas.WelcomeApply'),
    AtlasEntry('Atlas.WelcomeReset'),
    MenuEntry('Atlas.WelcomeStart', TAtlasMenuPlace.ViewMenu)];
end;

procedure TAtlasWelcomeModule.ApplySettings;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := FHooks.Page();
  if mPage <> nil then
  begin
    mPage.Sync;
  end;
end;

procedure TAtlasWelcomeModule.ThemeChanged;
var
  mPage: TAtlasIdeWelcome;
begin
  mPage := FHooks.Page();
  if mPage <> nil then
  begin
    mPage.ThemeChanged;
  end;
end;

end.
