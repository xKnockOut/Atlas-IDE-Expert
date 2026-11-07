unit Atlas.IDE.Rules.FindingActions;

// Regel-Aktionen am Befund im Modul Prüfregeln (#909, #1755; vorher im
// Fenster „Atlas-Prüfung“ von Base). Base fragt laufende Module nach
// IAtlasRuleActions (Atlas.IDE.Contracts.Rules), aus dem Fenster
// „Atlas-Prüfung“, dem Befund-Hover und dem Serverfenster:
// - „Regel einstellen…“ öffnet den Dialog der Projekt-Einstellungen (ohne
//   Projekt den der globalen) im Knoten der Gruppe der Regel
//   (TAtlasProjectSettings.ShowRule, Regel-Editor des Moduls).
// - „Für diese Zeile unterdrücken“ springt zum Befund (außer er steht schon im
//   oberen Editor) und wendet die Code-Aktion rule.suppressLine des Servers an.
// - „Regel abschalten“ schreibt rules.<id> = "off" in atlas.json des Projekts
//   bzw. ohne Projekt in die globale Datei; hat die Regel Optionen, nur
//   "severity". Kommentare und andere Schlüssel bleiben.
// Nur im Hauptthread.

interface

uses
  Atlas.IDE.Contracts.Rules;

type
  TAtlasIdeRuleActions = class(TInterfacedObject, IAtlasRuleActions)
  public
    procedure Configure(const ARule: string);
    procedure Suppress(const APlace: TAtlasRuleFindingPlace);
    procedure Disable(const ARule: string);
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Files.TextFile,
  Atlas.Core.Lsp.TextChanges,
  Atlas.Core.Settings.JsonText,
  Atlas.Core.Rules.Table,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Navigation,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Commands.Editor,
  Atlas.IDE.Settings.Project,
  Atlas.UI.Rules.Strings;

const
  /// <summary>Kennung der Code-Aktion (RuleSuppressLineTag in Atlas.Common.Editing.CodeActions; das Plugin hängt
  /// nicht von Atlas.Common ab).</summary>
  cSuppressLineTag = 'rule.suppressLine';

/// <summary>Wert von "rules" aus ARoot als JSON-Text; '' ohne.</summary>
function RulesJsonOf(ARoot: TJSONObject): string;
var
  mRules: TJSONValue;
begin
  Result := '';
  if ARoot <> nil then
  begin
    mRules := ARoot.GetValue('rules');
    if mRules <> nil then
    begin
      Result := mRules.ToJSON;
    end;
  end;
end;

/// <summary>ARule in atlas.json des aktiven Projekts abschalten; False ohne Projekt oder wenn das Schreiben
/// scheitert.</summary>
function DisableInProject(const ARule: string): Boolean;
var
  mRoot: TJSONObject;
  mRulesJson, mPath, mJson, mTarget: string;
begin
  mTarget := TAtlasProjectSettings.SettingsFile;
  if mTarget = '' then
  begin
    Exit(False);
  end;
  mRoot := TAtlasProjectSettings.ReadProject;
  try
    mRulesJson := RulesJsonOf(mRoot);
  finally
    mRoot.Free;
  end;
  // Nur "severity", wenn die Regel Optionen hat.
  TAtlasRuleTable.SeverityChange(mRulesJson, ARule, 'off', mPath, mJson);
  Result := TAtlasProjectSettings.WriteValue(mPath, mJson);
  if Result then
  begin
    TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsRuleDisabled,
      [ARule, ExtractFileName(mTarget)]));
  end;
end;

/// <summary>ARule in der globalen Datei abschalten.</summary>
procedure DisableGlobally(const ARule: string);
var
  mRoot: TJSONObject;
  mRulesJson, mPath, mJson, mTarget: string;
  mContent: TAtlasTextFileContent;
begin
  mTarget := TAtlasIdeSettings.GlobalFile;
  if (mTarget = '') or not TAtlasIdeSettings.LoadGlobal(mContent) then
  begin
    Exit;
  end;
  mRoot := TAtlasJsonText.Parse(mContent.Text);
  try
    mRulesJson := RulesJsonOf(mRoot);
  finally
    mRoot.Free;
  end;
  // Nur dieser Wert ändert sich; Kommentare und alle anderen Schlüssel bleiben.
  TAtlasRuleTable.SeverityChange(mRulesJson, ARule, 'off', mPath, mJson);
  TAtlasIdeSettings.SaveGlobal(mContent, TAtlasJsonText.SetValue(mContent.Text, mPath, mJson));
  TAtlasIdeHost.Message(TAtlasRulesStrings.Fmt(TAtlasRulesTextId.ProblemsRuleDisabled,
    [ARule, ExtractFileName(mTarget)]));
end;

{ TAtlasIdeRuleActions }

procedure TAtlasIdeRuleActions.Configure(const ARule: string);
begin
  TAtlasProjectSettings.ShowRule(ARule);
end;

procedure TAtlasIdeRuleActions.Suppress(const APlace: TAtlasRuleFindingPlace);
begin
  // Die Code-Aktion gilt für den oberen Editor: erst hin, dann anwenden.
  if APlace.FileName <> '' then
  begin
    TAtlasIdeNavigation.GoToLocation(APlace.FileName, APlace.StartLine, APlace.StartCharacter);
  end;
  TAtlasIdeEditorCommands.ApplyTagged(TLspRange.Create(APlace.StartLine, APlace.StartCharacter, APlace.EndLine,
    APlace.EndCharacter), cSuppressLineTag);
end;

procedure TAtlasIdeRuleActions.Disable(const ARule: string);
begin
  // Ohne Projekt: globale Datei.
  if not DisableInProject(ARule) then
  begin
    DisableGlobally(ARule);
  end;
end;

end.
