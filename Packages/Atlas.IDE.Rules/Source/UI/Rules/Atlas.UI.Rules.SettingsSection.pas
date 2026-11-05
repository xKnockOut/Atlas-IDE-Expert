unit Atlas.UI.Rules.SettingsSection;

// Abschnitte des Moduls Prüfregeln im Optionsdialog (#1456, ADR 0017 Entscheidung 3; vorher in den Teilen
// „Prüfregeln“ und „Editor“ von Base). Die Regeln selbst, Problemliste und Prüfung beim Speichern bleiben in Base.
// - „Prüfregeln“: Modulschalter und Sammelkorrektur im Kontextmenü des Fensters (#1352).
// - „Editor“: Basislinie aktualisieren und DFM-Eigenschaftsregeln anwenden.

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasRulesChecksSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

  TAtlasRulesEditorSection = class(TAtlasSettingsSection)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

const
  cRulesSettingsOwner = 'atlas.ruleChecks';

implementation

uses
  Atlas.UI.Rules.Strings;

{ TAtlasRulesChecksSection }

function TAtlasRulesChecksSection.OwnerId: string;
begin
  Result := cRulesSettingsOwner;
end;

function TAtlasRulesChecksSection.AreaId: string;
begin
  // Seite (x-page) im Schema, kein angezeigter Text.
  Result := 'Prüfregeln'; // german-ok
end;

procedure TAtlasRulesChecksSection.BuildRows;
begin
  ModuleSwitch('ruleChecks.enabled');
  Switch('fix.bulk', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsFixBulk));
end;

{ TAtlasRulesEditorSection }

function TAtlasRulesEditorSection.OwnerId: string;
begin
  Result := cRulesSettingsOwner;
end;

function TAtlasRulesEditorSection.AreaId: string;
begin
  Result := 'Editor';
end;

procedure TAtlasRulesEditorSection.BuildRows;
begin
  Switch('baseline.update', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsBaselineUpdate));
  Switch('dfmRules.apply', TAtlasRulesStrings.Text(TAtlasRulesTextId.SettingsDfmPropertyRules));
end;

end.
