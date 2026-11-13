unit Atlas.IDE.Designer.Composition;

// Modul Designer (#1455): einzige Unit, die die Designer-Leiste
// (#1442) über dem Formular-Designer erzeugt. Sie meldet in ihrer
// Initialisierung das Modul „atlas.designer“ (Modulschalter designer, #1454)
// bei der Registry von Base an und stellt über dessen Scope den Teil
// DesignerBar der Feature-Tabelle und Hörer für Einstellungen und Thema
// bereit, dazu Befehl, Menüeinträge und Taste „Im Designer zeigen“ (#511,
// designer.showInDesigner) und „Eigenschaften suchen …“ im Atlas-Menü (#524,
// designer.propertySearch) sowie „Verwendungen im Code“ im Atlas-Menü (#750,
// designer.usages) und das eigene Desktop-Layout im Designer mit dem Befehl
// „Aktuelles Layout als Designer-Layout speichern …“ (#2079, designer.layout).
// Die Benachrichtigungen des Designers (#722, Teil Forms) bleiben in
// Base. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract;

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
    function Keys: TArray<TAtlasModuleKey>;
    procedure ApplySettings;
    procedure ThemeChanged;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  Atlas.UI.Designer.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.ShowComponent,
  Atlas.IDE.Designer.PropertySearch,
  Atlas.IDE.Designer.Usages,
  Atlas.IDE.Designer.DesktopLayout,
  Atlas.IDE.Designer.Bar;

var
  GScope: IAtlasModuleScope;
  GBarStarted: Boolean;

procedure ShowMessage(AText: string);
begin
  TAtlasIdeHost.Message(AText);
end;

procedure StartDesignerBar;
var
  mHooks: TAtlasIdeDesignerBar.THooks;
begin
  mHooks := Default(TAtlasIdeDesignerBar.THooks);
  mHooks.Message := ShowMessage;
  TAtlasIdeDesignerBar.Install(mHooks);
  GBarStarted := True;
end;

procedure StopDesignerBar;
begin
  GBarStarted := False;
  TAtlasIdeDesignerBar.Uninstall;
end;

function DesignerBarStarted: Boolean;
begin
  Result := GBarStarted;
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

function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

function ShowInDesignerKey: Integer;
begin
  Result := TAtlasIdeSettings.Current.DesignerShowInDesignerKey;
end;

{ TAtlasDesignerModule }

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
  TAtlasIdeDesignerUsages.Install(ModuleScope, ShowMessage);
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

function TAtlasDesignerModule.IsActive: Boolean;
begin
  Result := FActive;
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
    SaveDesignerLayout, SaveDesignerLayoutVisible, nil)];
end;

function MenuEntry(const ACommandId: string; APlace: TAtlasMenuPlace): TAtlasMenuEntry;
begin
  Result := Default(TAtlasMenuEntry);
  Result.CommandId := ACommandId;
  Result.Place := APlace;
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

function TAtlasDesignerModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [ShowInDesignerContextEntry,
    MenuEntry(cShowCommandId, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cPropertySearchCommandId, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cUsagesCommandId, TAtlasMenuPlace.AtlasMenu),
    MenuEntry(cSaveLayoutCommandId, TAtlasMenuPlace.AtlasMenu)];
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

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasDesignerSettingsSection.ProvideIn(GScope);
end;

procedure TAtlasDesignerModule.ThemeChanged;
begin
  TAtlasIdeDesignerBar.ThemeChanged;
end;

class function TAtlasDesignerModule.Parts: TArray<IAtlasFeaturePart>;
begin
  // Designer-Leiste (#1442): ab abgesichertem Start und solange editor.designerBar an ist.
  Result := [
    TAtlasFeaturePart.When('DesignerBar',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.EditorDesignerBar;
      end, DesignerBarStarted, StartDesignerBar, StopDesignerBar)];
end;

class function TAtlasDesignerModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDesignerModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasDesignerModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  for mPart in Parts do
  begin
    GScope.Provide(IAtlasFeaturePart, mPart);
  end;
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  GScope.Provide(IAtlasFollowsTheme, mRef);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasDesignerModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, nil);
end;

initialization
  TAtlasDesignerModule.RegisterModule;

finalization
  TAtlasDesignerModule.UnregisterModule;

end.
