unit Atlas.IDE.Welcome.Composition.Startup;

// Aufbau der Willkommensseite im Modul atlas.welcome (#1455): erzeugt
// TAtlasIdeWelcome mit allen eigenen Bereichen (Quellen aus
// Atlas.IDE.Welcome.Composition.Sources), verbindet die Schnellaktionen mit anderen Modulen
// (TAtlasWelcomeNeighbors), hört auf Projektaufgaben, Testläufe und die
// Befehlsnutzung und zeigt Kacheln anderer Module (TAtlasIdeWelcomeTiles).
// Alle Anmeldungen laufen über den Scope des Moduls und werden beim Stoppen
// rückwärts gelöst (Regel 4). „Testergebnisse“ ist eine Kachel des
// Moduls Tracker. Den Arbeitsstand je Issue (#2052) bietet die Seite dem
// Tracker über IAtlasIssueWork an.

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Welcome.Commands,
  Atlas.IDE.Welcome.Composition.Areas;

type
  TAtlasIdeWelcomeStartup = class
  public
    class procedure Start(const AScope: IAtlasModuleScope); static;
    class procedure Stop; static;
    /// <summary>Die laufende Seite; nil vor Start und nach Stop.</summary>
    class function Current: TAtlasIdeWelcome; static;
    /// <summary>Quellen der Bereiche der laufenden Seite; nil vor Start und nach Stop. Seit #1443 hat die Seite
    /// selbst nur die abstrakte Sicht.</summary>
    class function Areas: TAtlasIdeWelcomeSources; static;
  end;

implementation

uses
  System.Types,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Modules.Registry,
  Atlas.Plugin.Status.Lines,
  Atlas.Core.Welcome.Sections,
  Atlas.IDE.Base.Foundation.BuildTools,
  Atlas.IDE.Base.Foundation.Tests,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Settings.Options,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Contract,
  Atlas.IDE.Welcome.Search,
  Atlas.IDE.Welcome.Layouts,
  Atlas.IDE.Welcome.Composition.Sources,
  Atlas.IDE.Welcome.Composition.TileProjects,
  Atlas.IDE.Welcome.Adapters.Layouts,
  Atlas.IDE.Welcome.Adapters.Registry,
  Atlas.IDE.Welcome.Adapters.ContinueIssues,
  Atlas.IDE.Welcome.Adapters.Projects,
  Atlas.IDE.Welcome.Adapters.Tiles,
  Atlas.IDE.Welcome.Adapters.Listener,
  Atlas.Core.Commands.Contract;

var
  GWelcome: TAtlasIdeWelcome;
  // Quellen der Bereiche; leben länger als die Seite (erst nach ihr frei).
  GAreas: TAtlasIdeWelcomeSources;
  GTiles: TAtlasIdeWelcomeTiles;
  GRegistrations: TArray<IAtlasRegistration>;
  // Dauer der langsamen Schritte beim Start (der Aufbau der Willkommensseite kann 10 s dauern), für atlas.log.
  GSteps: string;

const
  cStepLogMs = 20;

{ Bausteine }

/// <summary>Millisekunden seit AStart (Now); genau genug für die Startzeiten in atlas.log.</summary>
function ElapsedMs(AStart: TDateTime): Int64;
begin
  Result := Round((Now - AStart) * MSecsPerDay);
end;

/// <summary>AProc ausführen; ab cStepLogMs steht der Schritt mit Dauer in GSteps.</summary>
procedure Step(const AName: string; const AProc: TProc);
var
  mStart: TDateTime;
  mMs: Int64;
begin
  mStart := Now;
  AProc();
  mMs := ElapsedMs(mStart);
  if mMs >= cStepLogMs then
  begin
    if GSteps <> '' then
    begin
      GSteps := GSteps + ', ';
    end;
    GSteps := GSteps + Format('%s %d ms', [AName, mMs]);
  end;
end;

function Arrange(ALayouts: TAtlasIdeWelcomeLayouts): IAtlasWelcomeArrangeSource;
begin
  Result := TAtlasIdeWelcomeArrange.Create(ALayouts);
end;

function CreatePage: TAtlasIdeWelcome;
var
  mParts: TAtlasIdeWelcomeParts;
begin
  mParts := Default(TAtlasIdeWelcomeParts);
  mParts.Areas := GAreas;
  mParts.Registry := TAtlasIdeRegistryAccess.Create;
  mParts.Arrange := Arrange;
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
    end, TAtlasWelcomeSourcesBuild.Warn, mParts);
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

function CurrentAreas: TAtlasIdeWelcomeSources;
begin
  Result := GAreas;
end;

function CurrentIssues: TAtlasIdeContinueIssues;
begin
  Result := TAtlasWelcomeSourcesBuild.Issues(GAreas);
end;

function CurrentProjects: TAtlasIdeProjects;
begin
  Result := nil;
  if GAreas <> nil then
  begin
    Result := GAreas.Projects;
  end;
end;

procedure Provide(const AScope: IAtlasModuleScope);
var
  mListener: IInterface;
begin
  mListener := TAtlasWelcomeListener.Create(TAtlasWelcomeSourcesBuild.ListenerHooks(CurrentAreas)) as
    IAtlasTaskListener;
  GRegistrations := [AScope.Provide(IAtlasTaskListener, mListener), AScope.Provide(IAtlasTestsListener, mListener),
    AScope.Provide(IAtlasCommandUsageListener, mListener),
    TAtlasWelcomeIssueWork.Provide(AScope, CurrentIssues)];
end;

{ TAtlasIdeWelcomeStartup }

class procedure TAtlasIdeWelcomeStartup.Start(const AScope: IAtlasModuleScope);
var
  mStart: TDateTime;
  mScope: IAtlasModuleScope;
begin
  if GWelcome <> nil then
  begin
    Exit;
  end;
  GSteps := '';
  mStart := Now;
  mScope := AScope;
  Step('Page',
    procedure
    begin
      GAreas := TAtlasIdeWelcomeSources.Create;
      GWelcome := CreatePage;
    end);
  Step('Search',
    procedure
    begin
      GWelcome.Search := TAtlasIdeWelcomeSearch.Create(TAtlasWelcomeSourcesBuild.PaletteCommands,
        TAtlasWelcomeSourcesBuild.Execute);
    end);
  TAtlasWelcomeSourcesBuild.StartProjectSections(GAreas, Step);
  TAtlasWelcomeSourcesBuild.StartWorkSections(GAreas, Step);
  GWelcome.Layouts.OnHideSetting := HideSetting;
  GWelcome.Layouts.OnShowSetting := ShowSetting;
  Step('Provide',
    procedure
    begin
      Provide(mScope);
    end);
  Step('Tiles',
    procedure
    begin
      GTiles := TAtlasIdeWelcomeTiles.Create(AtlasModuleRegistry, ScopeProvide(mScope), TAtlasWelcomeSections.Default);
      GTiles.Start(TAtlasWelcomeTileProjects.Access(CurrentProjects));
    end);
  Step('Sync',
    procedure
    begin
      GWelcome.Sync;
    end);
  TAtlasGuard.Log(Format('Welcome start %d ms: %s', [ElapsedMs(mStart), GSteps]));
  GSteps := '';
end;

class procedure TAtlasIdeWelcomeStartup.Stop;
var
  mIndex: Integer;
begin
  if GWelcome = nil then
  begin
    Exit;
  end;
  GWelcome.BeginStop;
  // Zuerst die Kacheln anderer Module: Ihre Steuerelemente gehen, solange die Seite noch steht.
  FreeAndNil(GTiles);
  for mIndex := High(GRegistrations) downto 0 do
  begin
    GRegistrations[mIndex].Revoke;
  end;
  GRegistrations := nil;
  FreeAndNil(GWelcome);
  FreeAndNil(GAreas);
  TAtlasWelcomeViews.Release;
  TAtlasWelcomeSections.ReleaseDefault;
end;

class function TAtlasIdeWelcomeStartup.Current: TAtlasIdeWelcome;
begin
  Result := GWelcome;
end;

class function TAtlasIdeWelcomeStartup.Areas: TAtlasIdeWelcomeSources;
begin
  Result := CurrentAreas;
end;

end.
