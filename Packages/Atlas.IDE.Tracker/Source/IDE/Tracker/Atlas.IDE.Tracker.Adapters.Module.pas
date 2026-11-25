unit Atlas.IDE.Tracker.Adapters.Module;

// Modulklasse des Trackers (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Tracker.Composition) über den Scope des Moduls bereitstellt: Befehle, Menüeinträge, Taste,
// übernommene Einstellungen und die Issues in der Befehlspalette. Befehle, Menü und Tasten bauen die Teile der
// Feature-Tabelle (Atlas.IDE.Tracker.Composition.Parts); die Composition reicht sie als TAtlasTrackerModuleSources
// herein, weil ein Adapter die Composition nicht einbindet.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.Core.Commands.Contract;

type
  /// <summary>Beiträge der Teile, die die Modulklasse weiterreicht.</summary>
  TAtlasTrackerModuleSources = record
    Commands: TFunc<TArray<TAtlasModuleCommand>>;
    MenuEntries: TFunc<TArray<TAtlasMenuEntry>>;
    Keys: TFunc<TArray<TAtlasModuleKey>>;
    ApplySettings: TProc;
    PaletteSource: TFunc<IAtlasPaletteSource>;
  end;

  TAtlasTrackerModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasPaletteSourceProvider)
  public const
    cModuleId = 'atlas.tracker';
    cSwitch = 'issues';
  private
    FActive: Boolean;
    FSources: TAtlasTrackerModuleSources;
  public
    constructor Create(const ASources: TAtlasTrackerModuleSources);
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
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Core.ModuleHost;

{ TAtlasTrackerModule }

constructor TAtlasTrackerModule.Create(const ASources: TAtlasTrackerModuleSources);
begin
  inherited Create;
  FSources := ASources;
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
  Result := FSources.Commands();
end;

function TAtlasTrackerModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := FSources.MenuEntries();
end;

function TAtlasTrackerModule.Keys: TArray<TAtlasModuleKey>;
begin
  Result := FSources.Keys();
end;

procedure TAtlasTrackerModule.ApplySettings;
begin
  FSources.ApplySettings();
end;

function TAtlasTrackerModule.PaletteSource: IAtlasPaletteSource;
begin
  Result := FSources.PaletteSource();
end;

end.
