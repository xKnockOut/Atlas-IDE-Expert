unit Atlas.IDE.Help.Composition;

// Modul Hilfe (#1886): einzige Unit, die F1 zu Atlas-Elementen beantwortet. Sie meldet in ihrer
// Initialisierung das Modul „atlas.help“ (Modulschalter help) bei der Registry von Base an und stellt über dessen
// Scope die Modulklasse (Atlas.IDE.Help.Adapters.Module) als IAtlasHelpProvider und IAtlasKeySource bereit,
// dazu den Abschnitt „Allgemein“ im Optionsdialog (help.enabled, help.source).
// Ist das Modul aus, liefert Base die Beiträge nicht mehr; F1 verhält sich dann wie ohne Atlas. Abmelden in der
// Finalisierung, solange Base läuft (Regel 5); passt die Vertragsversion von Base nicht, meldet sich das Modul nicht
// an (Regel 7).

interface

implementation

uses
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.IDE.Base.Foundation.Help,
  Atlas.UI.Help.SettingsSection,
  Atlas.IDE.Help.Adapters.Module;

var
  GScope: IAtlasModuleScope;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasHelpModule;
  mRef: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasHelpModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasHelpModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  GScope.Provide(IAtlasHelpProvider, mRef);
  GScope.Provide(IAtlasKeySource, mRef);
  // Ab der Anmeldung, damit sich das Modul auch ausgeschaltet einstellen lässt.
  TAtlasHelpSettingsSection.ProvideIn(GScope);
  Result := True;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasHelpModule.cModuleId, HInstance, nil);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
