unit Atlas.IDE.Designer.Adapters.Module;

// Modulklasse des Designers (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Designer.Composition) über den Scope des Moduls bereitstellt: die Befehle „Im Designer zeigen“
// (#511), „Eigenschaften suchen“ (#524), „Verwendungen im Code“ (#750), „Designer-Layout speichern“ (#2079) und
// die Fenster Struktur (#609) und Ereignis-Karte (#612), ihre Menüeinträge, die Taste, übernommene Einstellungen
// und das Thema an die Designer-Leiste (#1442). Den Scope reicht die Composition als Funktion herein.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules;

type
  TAtlasDesignerModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasKeySource, IAtlasAppliesSettings, IAtlasFollowsTheme)
  public const
    cModuleId = 'atlas.designer';
    cSwitch = 'designer';
    cShowCommandId = 'Atlas.ShowInDesigner';
    cPropertySearchCommandId = 'Atlas.PropertySearch';
    cUsagesCommandId = 'Atlas.DesignerUsages';
    cSaveLayoutCommandId = 'Atlas.SaveDesignerLayout';
    cStructureCommandId = 'Atlas.DesignerStructure';
    cEventMapCommandId = 'Atlas.DesignerEventMap';
  private
    FActive: Boolean;
    FScope: TFunc<IAtlasModuleScope>;
  public
    /// <summary>AScope liefert den Scope des Moduls (für Antworten des Servers).</summary>
    constructor Create(const AScope: TFunc<IAtlasModuleScope>);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
  end;

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.ShowComponent,
  Atlas.IDE.Designer.PropertySearch,
  Atlas.IDE.Designer.Usages,
  Atlas.IDE.Designer.DesktopLayout,
  Atlas.IDE.Designer.Structure,
  Atlas.IDE.Designer.EventMap,
  Atlas.IDE.Designer.Bar;

{ TAtlasDesignerModule }

constructor TAtlasDesignerModule.Create(const AScope: TFunc<IAtlasModuleScope>);
begin
  inherited Create;
  FScope := AScope;
end;

procedure ShowMessage(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;
/// <summary>„Im Designer zeigen“ (#511), abgesichert.</summary>
procedure ShowInDesigner;
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, TAtlasIdeShowComponent.Run);
end;
function ShowInDesignerVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerShowInDesigner;
end;
/// <summary>„Eigenschaften suchen …“ (#524), abgesichert.</summary>
procedure SearchProperties;
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      TAtlasIdePropertySearch.Run(False);
    end);
end;
function SearchPropertiesVisible: Boolean;
begin
  Result := TAtlasIdePropertySearch.Available(TAtlasIdeSettings.Current);
end;
/// <summary>„Verwendungen im Code“ (#750), abgesichert.</summary>
procedure ShowUsages;
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, TAtlasIdeDesignerUsages.Run);
end;
function UsagesVisible: Boolean;
begin
  Result := TAtlasIdeDesignerUsages.Available(TAtlasIdeSettings.Current);
end;
/// <summary>„Aktuelles Layout als Designer-Layout speichern …“ (#2079), abgesichert.</summary>
procedure SaveDesignerLayout;
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, TAtlasIdeDesktopLayout.SaveCurrent);
end;
function SaveDesignerLayoutVisible: Boolean;
begin
  Result := TAtlasIdeDesktopLayout.Enabled;
end;
/// <summary>Andockbares Fenster AId der Designer-Leiste öffnen oder nach vorn holen, abgesichert.</summary>
procedure PresentView(const AId: string);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      TAtlasIdeDesignerBar.Present(AId);
    end);
end;
procedure ShowStructure;
begin
  PresentView(TAtlasIdeStructure.cId);
end;
/// <summary>Atlas-Struktur (#609): nur mit laufender Leiste und designer.structure.</summary>
function StructureVisible: Boolean;
begin
  Result := TAtlasIdeDesignerBar.Running and TAtlasIdeSettings.Current.DesignerStructure;
end;
procedure ShowEventMap;
begin
  PresentView(TAtlasIdeEventMap.cId);
end;
/// <summary>Ereignis-Karte (#612): nur mit laufender Leiste und designer.eventMap.</summary>
function EventMapVisible: Boolean;
begin
  Result := TAtlasIdeDesignerBar.Running and TAtlasIdeSettings.Current.DesignerEventMap;
end;
function ShowInDesignerKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.DesignerShowInDesignerKey;
end;
function TAtlasDesignerModule.Info: TAtlasModuleInfo;
begin
  // Die Leiste lief mit den Editorbefehlen schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Designer', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
end;
procedure TAtlasDesignerModule.Start;
begin
  FActive := True;
  TAtlasIdeShowComponent.Install(ShowMessage);
  TAtlasIdePropertySearch.Install(ShowMessage);
  TAtlasIdeDesignerUsages.Install(FScope, ShowMessage);
  TAtlasIdeDesktopLayout.Install(ShowMessage);
end;
procedure TAtlasDesignerModule.Stop;
begin
  FActive := False;
  TAtlasIdeShowComponent.Uninstall;
  TAtlasIdePropertySearch.Uninstall;
  TAtlasIdeDesignerUsages.Uninstall;
  TAtlasIdeDesktopLayout.Uninstall;
end;
function Command(const AId, ACaption: string; const ARun: TProc; const AVisible: TFunc<Boolean>;
  const AKey: TFunc<Integer>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.Run := ARun;
  Result.Visible := AVisible;
  Result.Key := AKey;
end;
function TAtlasDesignerModule.IsActive: Boolean;
begin
  Result := FActive;
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
  Result.Section := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.MenuGroupDesigner);
end;
/// <summary>Eintrag im Untermenü Designer unter Ansicht › Atlas.</summary>
function ViewEntry(const ACommandId: string): TAtlasMenuEntry;
begin
  Result := MenuEntry(ACommandId, TAtlasMenuPlace.ViewMenu);
  Result.Section := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.MenuGroupDesigner);
end;
/// <summary>Hat die Unit ein Formular?</summary>
function WithForm(const AContext: TAtlasMenuContext): Boolean;
begin
  Result := AContext.HasForm;
end;
/// <summary>„Im Designer zeigen“ im Kontextmenü des Editors; nur in Units mit Formular.</summary>
function ShowInDesignerContextEntry: TAtlasMenuEntry;
begin
  Result := MenuEntry(TAtlasDesignerModule.cShowCommandId, TAtlasMenuPlace.EditorContext);
  Result.When := WithForm;
end;
function TAtlasDesignerModule.Commands: TArray<TAtlasModuleCommand>;
begin
  // Im Designer zeigen (#511): nur sichtbar mit designer.showInDesigner.
  Result := [Command(cShowCommandId, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerShowCommand),
    ShowInDesigner, ShowInDesignerVisible, ShowInDesignerKey),
    // Eigenschaften suchen (#524): ohne eigene Taste.
    Command(cPropertySearchCommandId, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.PropertySearchCommand),
    SearchProperties, SearchPropertiesVisible, nil),
    // Verwendungen im Code (#750): die Taste gilt nur im Designer (designer.usages.key), nicht im Code-Editor.
    Command(cUsagesCommandId, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesCommand), ShowUsages,
    UsagesVisible, nil),
    // Eigenes Desktop-Layout (#2079): öffnet den Dialog „Desktop speichern“ der IDE.
    Command(cSaveLayoutCommandId, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.DesktopSaveCommand),
    SaveDesignerLayout, SaveDesignerLayoutVisible, nil),
    // Andockbare Fenster der Leiste (#609, #612) auch aus dem Hauptmenü.
    Command(cStructureCommandId, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.StCaption),
    ShowStructure, StructureVisible, nil),
    Command(cEventMapCommandId, TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.EmCaption),
    ShowEventMap, EventMapVisible, nil)];
end;
function TAtlasDesignerModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [ShowInDesignerContextEntry,
    AtlasEntry(cShowCommandId),
    AtlasEntry(cPropertySearchCommandId),
    AtlasEntry(cUsagesCommandId),
    AtlasEntry('-'),
    AtlasEntry(cStructureCommandId),
    AtlasEntry(cEventMapCommandId),
    AtlasEntry('-'),
    AtlasEntry(cSaveLayoutCommandId),
    ViewEntry(cStructureCommandId),
    ViewEntry(cEventMapCommandId)];
end;
function TAtlasDesignerModule.Keys: TArray<TAtlasModuleKey>;
var
  mKey: TAtlasModuleKey;
begin
  Result := nil;
  // Gewöhnlicher Editorbefehl: Umschalt+F12 ist in der IDE „Formulare anzeigen“; ohne keys.editorPriority behält
  // die IDE die Taste.
  if not TAtlasIdeSettings.Current.DesignerShowInDesigner then
  begin
    Exit;
  end;
  mKey := Default(TAtlasModuleKey);
  mKey.Id := cShowCommandId;
  mKey.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerShowCommand);
  mKey.Key := TAtlasIdeSettings.Current.DesignerShowInDesignerKey;
  mKey.Priority := TAtlasKeyPriority.Shared;
  mKey.Run := ShowInDesigner;
  Result := [mKey];
end;
procedure TAtlasDesignerModule.ApplySettings;
begin
  // editor.designerBar.* (#1442).
  TAtlasIdeDesignerBar.ApplySettings;
end;
procedure TAtlasDesignerModule.ThemeChanged;
begin
  TAtlasIdeDesignerBar.ThemeChanged;
end;

end.
