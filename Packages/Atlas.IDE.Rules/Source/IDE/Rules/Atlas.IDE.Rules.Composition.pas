unit Atlas.IDE.Rules.Composition;

// Modul Prüfregeln (#1455): einzige Unit, die die Werkzeuge der
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
//   Einrichtung der Willkommensseite (#759),
// - die Fehler der IDE aus Error Insight (IAtlasIdeErrors, #1819,
//   Atlas.IDE.Rules.IdeErrors) für das Fenster „Atlas-Prüfung“,
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

uses
  System.SysUtils,
  Atlas.Core.Modules.Contract,
  Atlas.IDE.Contracts.Rules;

type
  TAtlasRulesModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasBaselineSource, IAtlasAppliesSettings)
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
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
    procedure ApplySettings;
    /// <summary>Modul anmelden und seine Beiträge bereitstellen; False, wenn Base fehlt oder die Vertragsversion
    /// nicht passt.</summary>
    class function RegisterModule: Boolean; static;
    class procedure UnregisterModule; static;
  end;

implementation

uses
  System.JSON,
  ToolsAPI,
  Atlas.Text.Product.Version,
  Atlas.Core.Diagnostics.ModuleHost,
  Atlas.Core.Modules.FeatureParts,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Problems.Findings,
  Atlas.Core.Rules.CustomLayer,
  Atlas.UI.Settings.Contract,
  Atlas.UI.Settings.ProjectDialog,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Editor.DfmPropertyRules,
  Atlas.IDE.Rules.Baseline,
  Atlas.IDE.Rules.BulkFix,
  Atlas.IDE.Rules.FindingActions,
  Atlas.IDE.Rules.IdeErrors,
  Atlas.IDE.Rules.OwnershipHints,
  Atlas.IDE.Rules.Settings,
  Atlas.UI.Rules.SettingsDialog,
  Atlas.UI.Rules.SettingsSection,
  Atlas.UI.Strings,
  Atlas.UI.Rules.Strings;

var
  GScope: IAtlasModuleScope;
  GOwnershipHints: TAtlasIdeOwnershipHints;

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

{ Eigene Prüfregel (#1821) }

/// <summary>Wert von "rules" der Projektdatei als JSON-Text; '' ohne.</summary>
function ProjectRulesJson: string;
var
  mRoot: TJSONObject;
  mRules: TJSONValue;
begin
  Result := '';
  mRoot := TAtlasProjectSettings.ReadProject;
  try
    if mRoot <> nil then
    begin
      mRules := mRoot.GetValue('rules');
      if mRules <> nil then
      begin
        Result := mRules.ToJSON;
      end;
    end;
  finally
    mRoot.Free;
  end;
end;

/// <summary>Unitname der Datei im Editor; '' ohne.</summary>
function ActiveUnitName: string;
var
  mView: IOTAEditView;
begin
  Result := '';
  mView := TAtlasEditorBuffer.ActiveView;
  if (mView <> nil) and (mView.Buffer <> nil) and SameText(ExtractFileExt(mView.Buffer.FileName), '.pas') then
  begin
    Result := ChangeFileExt(ExtractFileName(mView.Buffer.FileName), '');
  end;
end;

/// <summary>Neue Schicht in forbidden-uses der Projektdatei, dann den Regel-Editor bei der Regel öffnen.</summary>
procedure NewCustomRule;
var
  mFile, mFrom, mPath, mJson: string;
begin
  mFile := TAtlasProjectSettings.SettingsFile;
  if mFile = '' then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesGalleryNoProject));
    Exit;
  end;
  mFrom := TAtlasCustomLayer.LayerFrom(ActiveUnitName);
  TAtlasCustomLayer.NewLayer(ProjectRulesJson, mFrom, mPath, mJson);
  if not TAtlasProjectSettings.WriteValue(mPath, mJson) then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.RulesGalleryFailed, [ExtractFileName(mFile)]));
    Exit;
  end;
  TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.RulesGalleryAdded, [mFrom, ExtractFileName(mFile)]));
  TAtlasProjectSettings.ShowRule(TAtlasCustomLayer.cRuleId);
end;

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
  // Die Befehle liefen mit den Editorbefehlen schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Prüfregeln', TAtlasVersion.cVersion, HInstance,
    TAtlasSafeLevel.Safe, cSwitch);
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
      DfmPropertyRulesVisible),
    // Assistent in Datei › Neu › Weitere (#1821); auch in der Palette.
    Command('Atlas.NewCustomRule', TAtlasRulesTextId.RulesGalleryCustomRule, NewCustomRule, nil)];
  Result[High(Result)].Description := TAtlasRulesStrings.Text(TAtlasRulesTextId.RulesGalleryCustomRuleHint);
end;

function TAtlasRulesModule.MenuEntries: TArray<TAtlasMenuEntry>;
begin
  Result := [Default(TAtlasMenuEntry)];
  Result[0].CommandId := 'Atlas.NewCustomRule';
  Result[0].Place := TAtlasMenuPlace.Gallery;
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

procedure TAtlasRulesModule.ApplySettings;
begin
  // editor.ownershipHints, editor.ownershipHints.onlyProblems (#1877).
  if GOwnershipHints <> nil then
  begin
    GOwnershipHints.ApplySettings;
  end;
end;

class function TAtlasRulesModule.RegisterModule: Boolean;
var
  mRegistry: IAtlasModuleRegistry;
  mModule: TAtlasRulesModule;
  mRef: IInterface;
begin
  Result := False;
  // Regel 7: zuerst die Vertragsversion von Base, gegen die dieses Modul übersetzt ist.
  if not TAtlasModuleHost.Admit(cModuleId, cAtlasCoreContractVersion, GScope, mRegistry) then
  begin
    Exit;
  end;
  mModule := TAtlasRulesModule.Create;
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

class procedure TAtlasRulesModule.UnregisterModule;
begin
  TAtlasModuleHost.Unregister(GScope, cModuleId, HInstance, ReleaseModule);
end;

initialization
  TAtlasRulesModule.RegisterModule;

finalization
  TAtlasRulesModule.UnregisterModule;

end.
