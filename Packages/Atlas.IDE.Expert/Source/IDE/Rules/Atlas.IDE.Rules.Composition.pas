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
// - das Aktualisieren der Baseline (IAtlasBaselineSource) für die
//   Einrichtung der Willkommensseite (#759).
// Prüfen selbst, Fenster „Atlas-Prüfung“, Erklären, Unterdrücken und
// Abschalten am Befund, die Regeltabelle der Einstellungen, der Hinweis bei
// abgeschaltetem Modul (#1454) und der Stand der Baseline-Datei bleiben in
// Base: Sie laufen auch ohne das Modul (ohne Prüfregeln gibt es nur keine
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
    ModuleId = 'atlas.rules';
    Switch = 'ruleChecks';
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
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Editor.DfmPropertyRules,
  Atlas.IDE.Rules.Baseline,
  Atlas.IDE.Rules.BulkFix,
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
    Exit;
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
  Result.Id := ModuleId;
  Result.Name := 'Prüfregeln';
  Result.Version := TAtlasVersion.Version;
  Result.Handle := HInstance;
  // Die Befehle liefen mit den Editorbefehlen schon im abgesicherten Start.
  Result.MinLevel := TAtlasSafeLevel.Safe;
  Result.Switch := Switch;
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
    Exit;
  // Regel 7: zuerst die Vertragsversion von Base (FindClassHInstance einer Base-Klasse, Regel 8).
  if TAtlasContractHandshake.Check(FindClassHInstance(TAtlasModuleRegistry), cAtlasCoreContractVersion) <>
    ccMatch then
  begin
    TAtlasGuard.Log('Modul ' + ModuleId + ': Vertragsversion von Base passt nicht, nicht angemeldet');
    Exit;
  end;
  mModule := TAtlasRulesModule.Create;
  mRef := mModule as IAtlasModule;
  GScope := mRegistry.RegisterModule(mModule);
  TAtlasIdeRulesBaseline.Install(GScope);
  GScope.Provide(IAtlasCommandSource, mRef);
  GScope.Provide(IAtlasBaselineSource, mRef);
  GScope.Provide(IAtlasBulkFixer, TAtlasIdeRulesBulkFix.Create(GScope) as IAtlasBulkFixer);
  Result := True;
end;

class procedure TAtlasRulesModule.UnregisterModule;
var
  mRegistry: IAtlasModuleRegistry;
  mFailure: string;
begin
  if GScope = nil then
    Exit;
  TAtlasIdeRulesBaseline.Uninstall;
  GScope := nil;
  // Regel 5: nur, solange Base noch läuft; sonst hat Base das Modul schon gestoppt und abgemeldet.
  mRegistry := AtlasModuleRegistry;
  if mRegistry <> nil then
    for mFailure in mRegistry.UnregisterModule(ModuleId) do
      TAtlasGuard.Log('Modul ' + ModuleId + ' nicht sauber abgemeldet: ' + mFailure);
end;

initialization
  TAtlasRulesModule.RegisterModule;

finalization
  TAtlasRulesModule.UnregisterModule;

end.
