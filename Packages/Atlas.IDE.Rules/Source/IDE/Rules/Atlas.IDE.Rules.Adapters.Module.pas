unit Atlas.IDE.Rules.Adapters.Module;

// Modulklasse der Prüfregeln (#1455): erfüllt IAtlasModule und die Beiträge, die die Composition
// (Atlas.IDE.Rules.Composition) über den Scope des Moduls bereitstellt:
// - Befehle (Palette): Baseline des Projekts aktualisieren (#97), Compilermeldungen in die Baseline (#530),
//   Eigenschaftsregeln anwenden (#309, Atlas.IDE.Editor.DfmPropertyRules) und den Assistenten „Eigene Prüfregel“
//   (#1821, Atlas.Core.Rules.CustomLayer), auch in Datei › Neu › Weitere,
// - das Aktualisieren der Baseline (IAtlasBaselineSource) für die Einrichtung der Willkommensseite (#759),
// - übernommene Einstellungen an die Marke „Wer gibt das frei?“ (#1877); die Marke selbst startet die
//   Composition als Teil der Feature-Tabelle und reicht ApplySettings herein.

interface

uses
  System.SysUtils,
  Atlas.IDE.Base.Foundation.Modules,
  Atlas.IDE.Base.Foundation.Rules;

type
  TAtlasRulesModule = class(TInterfacedObject, IAtlasModule, IAtlasCommandSource, IAtlasMenuSource,
    IAtlasBaselineSource, IAtlasAppliesSettings)
  public const
    cModuleId = 'atlas.rules';
    cSwitch = 'ruleChecks';
  private
    FActive: Boolean;
    FApplySettings: TProc;
  public
    /// <summary>AApplySettings gibt geänderte Einstellungen an die laufenden Teile der Feature-Tabelle.</summary>
    constructor Create(const AApplySettings: TProc);
    function Info: TAtlasModuleInfo;
    procedure Start;
    procedure Stop;
    function IsActive: Boolean;
    function Commands: TArray<TAtlasModuleCommand>;
    function MenuEntries: TArray<TAtlasMenuEntry>;
    function StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
    procedure ApplySettings;
  end;

implementation

uses
  System.JSON,
  Atlas.Text.Product.Version,
  Atlas.IDE.Base.Core.ModuleHost,
  Atlas.Core.Editor.WorkspacePlan,
  Atlas.Core.Rules.CustomLayer,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.ToolsApi.Editor.Buffer,
  Atlas.IDE.Settings.Project,
  Atlas.IDE.Editor.DfmPropertyRules,
  Atlas.IDE.Rules.Baseline,
  Atlas.UI.Rules.Strings;

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
  mFrom := TAtlasCustomLayer.LayerFrom(TAtlasEditorBuffer.ActiveUnitName);
  TAtlasCustomLayer.NewLayer(ProjectRulesJson, mFrom, mPath, mJson);
  if not TAtlasProjectSettings.WriteValue(mPath, mJson) then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.RulesGalleryFailed, [ExtractFileName(mFile)]));
    Exit;
  end;
  TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.RulesGalleryAdded, [mFrom, ExtractFileName(mFile)]));
  TAtlasProjectSettings.ShowRule(TAtlasCustomLayer.cRuleId);
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

constructor TAtlasRulesModule.Create(const AApplySettings: TProc);
begin
  inherited Create;
  FApplySettings := AApplySettings;
end;

function TAtlasRulesModule.Info: TAtlasModuleInfo;
begin
  // Die Befehle liefen mit den Editorbefehlen schon im abgesicherten Start.
  Result := TAtlasModuleHost.Info(cModuleId, 'Prüfregeln', TAtlasVersion.cVersion, HInstance, // german-ok
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

function TAtlasRulesModule.StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
begin
  Result := TAtlasIdeRulesBaseline.StartUpdate(AProject, ADone);
end;

procedure TAtlasRulesModule.ApplySettings;
begin
  // editor.ownershipHints, editor.ownershipHints.onlyProblems (#1877): nur, solange die Marke läuft.
  FApplySettings();
end;

end.
