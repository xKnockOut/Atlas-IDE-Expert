unit Atlas.IDE.Rules.Composition;

// Modul Prüfregeln (#1455): einzige Unit, die die Werkzeuge der
// Prüfregeln in der IDE einbindet: Baseline des Projekts aktualisieren (#97)
// und Compilermeldungen in die Baseline (#530) (Atlas.IDE.Rules.Baseline),
// Eigenschaftsregeln anwenden (#309, Atlas.IDE.Editor.DfmPropertyRules) und
// die Sammelkorrektur in „Atlas-Prüfung“ (#1352, Atlas.IDE.Rules.Adapters.BulkFix).
// Modulklasse, Befehle und Menüeintrag stehen in Atlas.IDE.Rules.Adapters.Module.
// Sie meldet in ihrer Initialisierung das Modul „atlas.rules“
// (Modulschalter ruleChecks, #1454) bei der Registry von Base an und stellt
// über dessen Scope bereit:
// - Befehle (Palette),
// - die Sammelkorrektur (IAtlasBulkFixer) für das Fenster „Atlas-Prüfung“,
// - Regel einstellen, unterdrücken und abschalten am Befund
//   (IAtlasRuleActions, #1755) für Fenster, Befund-Hover und Serverfenster,
// - den Dialog der Einstellungsdateien mit Regel-Editor
//   (IAtlasSettingsDialogProvider, #1755),
// - die Abschnitte „Prüfregeln“ (mit Wegen zu den Regeln, Baseline und
//   Unterdrückungen) und „Editor“ im Optionsdialog,
// - das Aktualisieren der Baseline (IAtlasBaselineSource) für die
//   Einrichtung der Willkommensseite (#759),
// - die Fehler der IDE aus Error Insight (IAtlasIdeErrors, #1819,
//   Atlas.IDE.Rules.Adapters.IdeErrors) für das Fenster „Atlas-Prüfung“,
// - den Assistenten „Eigene Prüfregel“ in Datei › Neu › Weitere (#1821):
//   neue Schicht in forbidden-uses der Projektdatei
//   (Atlas.Core.Rules.CustomLayer), danach der Regel-Editor bei der Regel,
// - die Marke „Wer gibt das frei?“ an jedem Create (#1877,
//   Atlas.IDE.Rules.OwnershipHints) als Teil „OwnershipHints“ der
//   Feature-Tabelle.
// Prüfen selbst, Fenster „Atlas-Prüfung“ mit Erklären, Inline-Hinweise,
// Übersichtsleiste, der Hinweis bei abgeschaltetem Modul (#1454) sowie Stand
// und Format der Baseline-Datei bleiben in Base: Sie zeigen auch
// Syntaxfehler und Compilermeldungen (ohne Prüfregeln gibt es nur keine
// Regeltreffer). Abmelden in der Finalisierung, solange Base läuft (Regel 5);
// passt die Vertragsversion von Base nicht, meldet sich das Modul nicht an
// (Regel 7).

interface

implementation

uses
  System.SysUtils,
  Atlas.Text.Product.Version,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.UI.Settings.Contract,
  Atlas.IDE.Base.Foundation.Rules,
  Atlas.IDE.Rules.Baseline,
  Atlas.IDE.Rules.Adapters.BulkFix,
  Atlas.IDE.Rules.Adapters.FindingActions,
  Atlas.IDE.Rules.Adapters.IdeErrors,
  Atlas.IDE.Rules.OwnershipHints,
  Atlas.IDE.Rules.Adapters.Settings,
  Atlas.IDE.Rules.Adapters.SettingsDialog,
  Atlas.UI.Rules.SettingsSection,
  Atlas.Plugin.Problems.Contract,
  Atlas.IDE.Rules.Adapters.Module;

var
  GScope: IAtlasModuleScope;
  GOwnershipHints: TAtlasIdeOwnershipHints;

{ Wer gibt das frei? (#1877) }

procedure StartOwnershipHints;
begin
  GOwnershipHints := TAtlasIdeOwnershipHints.Create(GScope);
end;

procedure StopOwnershipHints;
begin
  FreeAndNil(GOwnershipHints);
end;

function OwnershipHintsStarted: Boolean;
begin
  Result := GOwnershipHints <> nil;
end;

/// <summary>editor.ownershipHints, editor.ownershipHints.onlyProblems (#1877) an die laufende Marke.</summary>
procedure ApplyOwnershipSettings;
begin
  if GOwnershipHints <> nil then
  begin
    GOwnershipHints.ApplySettings;
  end;
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeRulesSettings.Create as IAtlasSettingsSectionProvider);
  TAtlasRulesEditorSection.ProvideIn(GScope);
end;

/// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
/// nicht passt.</summary>
function RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasRulesModule;
  mRef: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(TAtlasRulesModule.cModuleId, cAtlasCoreContractVersion, TAtlasVersion.cVersion,
    GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasRulesModule.Create(ApplyOwnershipSettings);
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  TAtlasIdeRulesBaseline.Install(GScope);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasMenuSource, mRef);
  GScope.Provide(IAtlasBaselineSource, mRef);
  GScope.Provide(IAtlasAppliesSettings, mRef);
  // Teil der Feature-Tabelle: Base startet die Marke mit dem Modul und stoppt sie davor (Regel 1, 5).
  GScope.Provide(IAtlasFeaturePart, TAtlasFeaturePart.AtLevel('OwnershipHints', TAtlasSafeLevel.Safe,
    OwnershipHintsStarted, StartOwnershipHints, StopOwnershipHints));
  GScope.Provide(IAtlasBulkFixer, TAtlasIdeRulesBulkFix.Create(GScope) as IAtlasBulkFixer);
  GScope.Provide(IAtlasRuleActions, TAtlasIdeRuleActions.Create as IAtlasRuleActions);
  GScope.Provide(IAtlasIdeErrors, TAtlasIdeRulesIdeErrors.Create as IAtlasIdeErrors);
  GScope.Provide(IAtlasSettingsDialogProvider, TAtlasRulesDialogProvider.Create as IAtlasSettingsDialogProvider);
  ProvideSettingsSections;
  Result := True;
end;

/// <summary>Modulspezifische Schritte nach dem Abmelden aus der Registry.</summary>
procedure ReleaseModule;
begin
  StopOwnershipHints;
  TAtlasIdeRulesBaseline.Uninstall;
end;

procedure UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, TAtlasRulesModule.cModuleId, HInstance, ReleaseModule);
end;

initialization
  RegisterModule;

finalization
  UnregisterModule;

end.
