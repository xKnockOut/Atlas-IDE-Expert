unit Atlas.IDE.Welcome.Startup;

// Aufbau der Willkommensseite im Modul atlas.welcome (#1455): erzeugt
// TAtlasIdeWelcome mit allen eigenen Bereichen aus den Diensten von Base
// (TAtlasIdeHost), verbindet die Schnellaktionen mit anderen Modulen
// (TAtlasWelcomeNeighbors), hört auf Projektaufgaben, Testläufe und die
// Befehlsnutzung und zeigt Kacheln anderer Module (TAtlasIdeWelcomeTiles).
// Alle Anmeldungen laufen über den Scope des Moduls und werden beim Stoppen
// rückwärts gelöst (Regel 4). „Testergebnisse“ ist seit #1455 eine Kachel des
// Moduls Tracker.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Welcome.Commands;

type
  TAtlasIdeWelcomeStartup = class
  public
    class procedure Start(const AScope: IAtlasModuleScope); static;
    class procedure Stop; static;
    /// <summary>Die laufende Seite; nil vor Start und nach Stop.</summary>
    class function Current: TAtlasIdeWelcome; static;
  end;

implementation

uses
  System.Types,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Core.Commands.Palette,
  Atlas.Core.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.WhatsNew,
  Atlas.IDE.Welcome.Projects,
  Atlas.IDE.Welcome.Trends,
  Atlas.IDE.Welcome.Unsaved,
  Atlas.IDE.Welcome.QuickActions,
  Atlas.IDE.Welcome.Continue,
  Atlas.IDE.Welcome.State,
  Atlas.IDE.Welcome.Discover,
  Atlas.IDE.Welcome.Help,
  Atlas.IDE.Welcome.Setup,
  Atlas.IDE.Welcome.Tiles,
  Atlas.IDE.Welcome.TileProjects,
  Atlas.IDE.Welcome.Neighbors,
  Atlas.IDE.Welcome.Listener;

var
  GWelcome: TAtlasIdeWelcome;
  GTiles: TAtlasIdeWelcomeTiles;
  GRegistrations: TArray<IAtlasRegistration>;

{ Bausteine }

procedure Warn(AText: string);
begin
  TAtlasIdeHost.Warning(AText);
end;

procedure Note(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure Execute(AId: string);
begin
  TAtlasIdeHost.ExecuteCommand(AId);
end;

function PaletteCommands: TArray<TAtlasCommand>;
begin
  Result := TAtlasIdeHost.PaletteCommands;
end;

function PaletteHas(AId: string): Boolean;
var
  mCommand: TAtlasCommand;
begin
  Result := False;
  for mCommand in TAtlasIdeHost.PaletteCommands do
  begin
    Result := Result or SameText(mCommand.Id, AId);
  end;
end;

function CreatePage: TAtlasIdeWelcome;
begin
  Result := TAtlasIdeWelcome.Create(
    function: TAtlasServerInfo
    begin
      Result := TAtlasIdeHost.ServerInfo;
    end,
    function(out APercent: Integer): Boolean
    begin
      Result := TAtlasIdeHost.ServerIndexing(APercent);
    end,
    function: Integer
    begin
      Result := TAtlasIdeHost.IndexedUnits;
    end, Warn);
end;

procedure TryCommand(AId: string);
begin
  TAtlasIdeDiscover.TryCommand(AId);
end;

procedure ShowKeys;
begin
  TAtlasIdeHost.ShowKeyMap;
end;

function HideSetting(AKey: string; APoint: TPoint): Boolean;
begin
  Result := TAtlasIdeHost.HideSetting(AKey, APoint);
end;

procedure ShowSetting(AKey: string);
begin
  TAtlasGuard.Run(TAtlasFeature.Settings,
    procedure
    begin
      TAtlasOptionsRegistration.ShowSetting(AKey);
    end);
end;

procedure ShowVcsServer(AFolder: string);
begin
  TAtlasOptionsRegistration.ShowVcsServer(AFolder);
end;

function ScopeProvide(const AScope: IAtlasModuleScope): TAtlasWelcomeProvide;
var
  mScope: IAtlasModuleScope;
begin
  mScope := AScope;
  Result :=
    function(const AIID: TGUID; const AObject: IInterface): IAtlasRegistration
    begin
      Result := mScope.Provide(AIID, AObject);
    end;
end;

{ Aufbau }

/// <summary>Kopf, „Neu in Atlas“ (#756), „Projekte“ (#592), „Projektverlauf“ (#758) und „Nicht gesichert“ (#762).
/// </summary>
procedure StartProjectSections;
begin
  GWelcome.Search := TAtlasIdeWelcomeSearch.Create(PaletteCommands, Execute);
  GWelcome.Areas.WhatsNew := TAtlasIdeWhatsNew.Create(PaletteHas, Execute, Warn);
  GWelcome.Areas.Projects := TAtlasIdeProjects.Create(Warn);
  GWelcome.Areas.Trends := TAtlasIdeTrends.Create(GWelcome.Areas.Projects);
  GWelcome.Areas.Unsaved := TAtlasIdeUnsaved.Create(Warn);
end;

/// <summary>Schnellaktionen (#764), „Weiterarbeiten“ (#755), Zustand (#754), „Atlas entdecken“ (#757), Hilfe
/// (#766), Einrichtung (#759) und „Seite anpassen“ (#767).</summary>
procedure StartWorkSections;
begin
  // Meldungen tragen Pfade und gehen deshalb nur in die Meldungsansicht.
  GWelcome.Areas.QuickActions := TAtlasIdeQuickActions.Create(GWelcome.Areas.Projects, Note);
  TAtlasWelcomeNeighbors.Connect(GWelcome.Areas.QuickActions);
  GWelcome.Areas.ContinueWork := TAtlasIdeContinue.Create(Warn);
  GWelcome.Areas.ContinueWork.Hooks.OnServerAccess := ShowVcsServer;
  GWelcome.Areas.State := TAtlasIdeWelcomeState.CreateForHost;
  GWelcome.Areas.Discover := TAtlasIdeDiscover.Create(PaletteCommands, TryCommand, Warn);
  GWelcome.Areas.Help := TAtlasIdeHelp.Create(ShowKeys);
  GWelcome.Areas.Setup := TAtlasWelcomeNeighbors.CreateSetup(Note);
  GWelcome.Layouts.OnHideSetting := HideSetting;
  GWelcome.Layouts.OnShowSetting := ShowSetting;
end;

function CurrentPage: TAtlasIdeWelcome;
begin
  Result := GWelcome;
end;

procedure Provide(const AScope: IAtlasModuleScope);
var
  mListener: IInterface;
begin
  mListener := TAtlasWelcomeListener.Create(CurrentPage) as IAtlasTaskListener;
  GRegistrations := [AScope.Provide(IAtlasTaskListener, mListener), AScope.Provide(IAtlasTestsListener, mListener),
    AScope.Provide(IAtlasCommandUsageListener, mListener)];
end;

{ TAtlasIdeWelcomeStartup }

class procedure TAtlasIdeWelcomeStartup.Start(const AScope: IAtlasModuleScope);
begin
  if GWelcome <> nil then
  begin
    Exit;
  end;
  GWelcome := CreatePage;
  StartProjectSections;
  StartWorkSections;
  Provide(AScope);
  GTiles := TAtlasIdeWelcomeTiles.Create(AtlasModuleRegistry, ScopeProvide(AScope), TAtlasWelcomeSections.Default);
  GTiles.Start(TAtlasWelcomeTileProjects.Access(CurrentPage));
  GWelcome.Sync;
end;

class procedure TAtlasIdeWelcomeStartup.Stop;
var
  mIndex: Integer;
begin
  if GWelcome = nil then
  begin
    Exit;
  end;
  // Zuerst die Kacheln anderer Module: Ihre Steuerelemente gehen, solange die Seite noch steht.
  FreeAndNil(GTiles);
  for mIndex := High(GRegistrations) downto 0 do
  begin
    GRegistrations[mIndex].Revoke;
  end;
  GRegistrations := nil;
  FreeAndNil(GWelcome);
  TAtlasWelcomeViews.Release;
  TAtlasWelcomeSections.ReleaseDefault;
end;

class function TAtlasIdeWelcomeStartup.Current: TAtlasIdeWelcome;
begin
  Result := GWelcome;
end;

end.
