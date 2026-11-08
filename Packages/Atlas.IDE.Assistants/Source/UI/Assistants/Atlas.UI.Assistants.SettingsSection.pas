unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): eigene Seite „KI-Assistenten“
// (#1906) mit dem Modulschalter assistants.enabled, Schreiben in offene Dateien (assistants.edit) und Builds für
// KI-Assistenten (compiler.mcpBuild; der Schlüssel bleibt, gebaut wird über das Modul Build-Pipeline).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasAssistantsSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.assistants';
    cAreaId = 'KI-Assistenten';
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

uses
  Atlas.UI.Assistants.Strings;

{ TAtlasAssistantsSettingsSection }

function TAtlasAssistantsSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasAssistantsSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasAssistantsSettingsSection.BuildRows;
begin
  ModuleSwitch('assistants.enabled');
  // Änderungen an offenen Dateien (#397) und Builds über diese IDE (#261, build_project).
  Switch('assistants.edit', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsEdit));
  Switch('compiler.mcpBuild', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsMcpBuild));
end;

end.
