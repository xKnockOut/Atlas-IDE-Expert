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
// Die andockbaren Fenster der Leiste, Atlas-Struktur (designer.structure) und
// Ereignis-Karte (designer.eventMap), öffnen auch die Befehle
// Atlas.DesignerStructure und Atlas.DesignerEventMap: im Untermenü Designer
// des Atlas-Menüs und unter Ansicht › Atlas › Designer, sichtbar nur bei
// laufender Leiste (editor.designerBar) und eingeschalteter Funktion.
// Die Benachrichtigungen des Designers (#722, Teil Forms) bleiben in
// Base. Abmelden in der Finalisierung, solange Base läuft (Regel 5); passt die
// Vertragsversion von Base nicht, meldet sich das Modul nicht an (Regel 7).
// Modulklasse, Befehle, Menü und Taste stehen in Atlas.IDE.Designer.Adapters.Module.

interface

implementation

uses
  System.SysUtils,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Designer.Contract,
  Atlas.UI.Designer.SettingsSection,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Designer.Bar,
  Atlas.IDE.Designer.DesktopLayout,
  Atlas.IDE.Designer.Surface,
  Atlas.IDE.Designer.Adapters.Surface,
  Atlas.IDE.Designer.Adapters.Module;

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

function ModuleScope: IAtlasModuleScope;
begin
  Result := GScope;
end;

{ TAtlasDesignerModule }

function Parts: TArray<IAtlasFeaturePart>;
begin
  // Designer-Leiste (#1442): ab abgesichertem Start und solange editor.designerBar an ist.
  Result := [
    TAtlasFeaturePart.When('DesignerBar',
      function(ALevel: TAtlasSafeLevel): Boolean
      begin
        Result := (ALevel <> TAtlasSafeLevel.Minimal) and TAtlasIdeSettings.Current.EditorDesignerBar;
      end, DesignerBarStarted, StartDesignerBar, StopDesignerBar)];
end;

/// <summary>Layouts der IDE für die Auswahlliste „Layout für den Designer“ (#2079).</summary>
function DesktopLayoutNames: TFunc<TArray<string>>;
begin
  Result :=
    function: TArray<string>
    begin
      Result := TAtlasIdeDesktopLayout.Names;
    end;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  TAtlasDesignerSettingsSection.LayoutNames := DesktopLayoutNames();
  TAtlasDesignerSettingsSection.ProvideIn(GScope);
end;

/// <summary>Surface des Formular-Designers für die Werkzeuge (TAtlasIdeDesignSurfaces).</summary>
function NewSurface(const ADesigner: IDesigner; const AEditor: IOTAFormEditor): IAtlasDesignSurface;
begin
  Result := TAtlasIdeDesignSurface.Create(ADesigner, AEditor);
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasDesignerModule;
  mRef: IInterface;
  mPart: IAtlasFeaturePart;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasDesignerModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasDesignerModule.Create(ModuleScope);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  TAtlasIdeDesignSurfaces.Use(NewSurface);
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

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasDesignerModule.cModuleId, HInstance, nil);
  TAtlasDesignerSettingsSection.LayoutNames := nil;
  TAtlasIdeDesignSurfaces.Use(nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
