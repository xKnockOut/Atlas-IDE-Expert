unit Atlas.IDE.Rules.Composition;

// Modul Prüfregeln (#1455, ADR 0017): einzige Unit, die die Werkzeuge der
// Prüfregeln in der IDE einbindet: Baseline des Projekts aktualisieren (#97)
// und Compilermeldungen in die Baseline (#530) (Atlas.IDE.Rules.Baseline),
// Eigenschaftsregeln anwenden (#309, Atlas.IDE.Editor.DfmPropertyRules) und
// die Sammelkorrektur in „Atlas-Prüfung“ (#1352, Atlas.IDE.Rules.BulkFix).
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
//   Einrichtung der Willkommensseite (#759).
// Prüfen selbst, Fenster „Atlas-Prüfung“ mit Erklären, Inline-Hinweise,
// Übersichtsleiste, der Hinweis bei abgeschaltetem Modul (#1454) sowie Stand
// und Format der Baseline-Datei bleiben in Base: Sie zeigen auch
// Syntaxfehler und Compilermeldungen (ohne Prüfregeln gibt es nur keine
// Regeltreffer). Abmelden in der Finalisierung, solange Base läuft (Regel 5);
// passt die Vertragsversion von Base nicht, meldet sich das Modul nicht an
// (Regel 7).

interface

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.Rules;

type
  TAtlasRulesModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasBaselineSource)
  public const
    cModuleId = 'atlas.rules';
    cSwitch = 'ruleChecks';
  private
    FActive: Boolean;
  public
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
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
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Problems.Findings,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.DfmPropertyRules,
  Atlas.IDE.Rules.Baseline,
  Atlas.IDE.Rules.BulkFix,
  Atlas.IDE.Rules.FindingActions,
  Atlas.IDE.Rules.Settings,
  Atlas.UI.Rules.SettingsDialog,
  Atlas.UI.Rules.SettingsSection,
  Atlas.UI.Strings,
  Atlas.UI.Rules.Strings;

var
  GScope: IAtlasModuleScope;

{ Eigenschaftsregeln (#309) }

procedure Warn(AText: string);
begin
  TAtlasIdeHost.Warning(AText);
end;

/// <summary>„Eigenschaftsregeln anwenden“ für Formular, Projekt oder Projektgruppe.</summary>
procedure ApplyDfmPropertyRules(AScope: TAtlasDfmRulesScope);
begin
  if not TAtlasIdeSettings.Current.DfmPropertyRules then
  begin
    Exit;
  end;
  TAtlasIdeDfmPropertyRules.Execute(TAtlasIdeHost.ActiveSession, AScope,
    TAtlasUnopenedPolicies.FromSetting(TAtlasIdeSettings.Current.OpenForEdits), Warn);
end;

procedure ApplyDfmRulesForm;
begin
  ApplyDfmPropertyRules(TAtlasDfmRulesScope.Form);
end;

procedure ApplyDfmRulesProject;
begin
  ApplyDfmPropertyRules(TAtlasDfmRulesScope.Project);
end;

procedure ApplyDfmRulesGroup;
begin
  ApplyDfmPropertyRules(TAtlasDfmRulesScope.Group);
end;

function DfmPropertyRulesVisible: Boolean;
begin
  Result := TAtlasIdeSettings.Current.DfmPropertyRules;
end;

{ Baseline (#97, #530) }

function BaselineVisible: Boolean;
begin
  Result := TAtlasIdeRulesBaseline.Enabled;
end;

procedure UpdateBaseline;
begin
  TAtlasIdeRulesBaseline.UpdateActiveProject;
end;

procedure AddCompilerMessages;
begin
  TAtlasIdeRulesBaseline.AddCompilerMessages;
end;

{ Befehle }

function Command(const AId: string; ACaption: TAtlasRulesTextId; const ARun: TProc;
  const AVisible: TFunc<Boolean>): TAtlasModuleCommand;
begin
  Result := Default(TAtlasModuleCommand);
  Result.Id := AId;
  Result.Caption := TAtlasRulesStrings.Text(ACaption);
  Result.Run := ARun;
  Result.Visible := AVisible;
end;

{ TAtlasRulesModule }

function TAtlasRulesModule.Info: TAtlasModuleInfo;
begin
  Result := Default(TAtlasModuleInfo);
  Result.Id := cModuleId;
  Result.Name := 'Prüfregeln';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Die Befehle liefen mit den Editorbefehlen schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := cSwitch;
end;

procedure TAtlasRulesModule.Start;
begin
  FActive := True;
end;

procedure TAtlasRulesModule.Stop;
begin
  FActive := False;
end;

function TAtlasRulesModule.IsActive: Boolean;
begin
  Result := FActive;
end;

function TAtlasRulesModule.Commands: TArray<TAtlasModuleCommand>;
begin
  Result := [
    // Baseline des Projekts aktualisieren (#97); nur sichtbar, solange baseline.update an ist.
    Command('Atlas.UpdateBaseline', TAtlasRulesTextId.BaselineUpdateCommand, UpdateBaseline, BaselineVisible),
    // Compilermeldungen des letzten Builds in die Baseline (#530); mit derselben Einstellung abschaltbar.
    Command('Atlas.CompilerBaseline', TAtlasRulesTextId.CompilerBaselineCommand, AddCompilerMessages, BaselineVisible),
    // Eigenschaftsregeln anwenden (#309); nur sichtbar, solange dfmRules.apply an ist.
    Command('Atlas.ApplyDfmRulesForm', TAtlasRulesTextId.DfmRulesFormCommand, ApplyDfmRulesForm,
      DfmPropertyRulesVisible),
    Command('Atlas.ApplyDfmRulesProject', TAtlasRulesTextId.DfmRulesProjectCommand, ApplyDfmRulesProject,
      DfmPropertyRulesVisible),
    Command('Atlas.ApplyDfmRulesGroup', TAtlasRulesTextId.DfmRulesGroupCommand, ApplyDfmRulesGroup,
      DfmPropertyRulesVisible)];
end;

/// <summary>Abschnitte des Moduls im Optionsdialog (#1456): ab der Anmeldung, damit sich das Modul auch
/// ausgeschaltet einstellen lässt.</summary>
procedure ProvideSettingsSections;
begin
  GScope.Provide(IAtlasSettingsSectionProvider, TAtlasIdeRulesSettings.Create as IAtlasSettingsSectionProvider);
  TAtlasRulesEditorSection.ProvideIn(GScope);
end;

function TAtlasRulesModule.StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
begin
  Result := TAtlasIdeRulesBaseline.StartUpdate(AProject, ADone);
end;

class function TAtlasRulesModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasRulesModule;
  mRef: IInterface;
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
  mModule := TAtlasRulesModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  TAtlasIdeRulesBaseline.Install(GScope);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasBaselineSource, mRef);
  GScope.Provide(IAtlasBulkFixer, TAtlasIdeRulesBulkFix.Create(GScope) as IAtlasBulkFixer);
  GScope.Provide(IAtlasRuleActions, TAtlasIdeRuleActions.Create as IAtlasRuleActions);
  GScope.Provide(IAtlasSettingsDialogProvider, TAtlasRulesDialogProvider.Create as IAtlasSettingsDialogProvider);
  ProvideSettingsSections;
  Result := True;
end;

class procedure TAtlasRulesModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
  begin
    Exit;
  end;
  TAtlasIdeRulesBaseline.Uninstall;
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
  TAtlasRulesModule.RegisterModule;

finalization
  TAtlasRulesModule.UnregisterModule;

end.
