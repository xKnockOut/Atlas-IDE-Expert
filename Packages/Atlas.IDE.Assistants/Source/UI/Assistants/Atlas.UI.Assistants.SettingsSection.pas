unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): eigene Seite „KI-Assistenten“
// (#1906) mit dem Modulschalter assistants.enabled, Schreiben in offene Dateien (assistants.edit), Builds für
// KI-Assistenten (compiler.mcpBuild; der Schlüssel bleibt, gebaut wird über das Modul Build-Pipeline) und Debuggen
// durch KI-Assistenten (debug.mcp mit Rechten und Leiste, #1874; ausgeführt im Modul Debugger).

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

procedure TAtlasAssistantsSettingsSection.BuildRows;
begin
  ModuleSwitch('assistants.enabled');
  // Änderungen an offenen Dateien (#397) und Builds über diese IDE (#261, build_project).
  Switch('assistants.edit', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsEdit));
  Switch('compiler.mcpBuild', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsMcpBuild));
  // Debuggen durch KI-Assistenten (#1874): Rechte und Leiste.
  Switch('debug.mcp', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsDebugMcp));
  Switch('debug.mcp.sideEffects', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsDebugSideEffects));
  Switch('debug.mcp.modify', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsDebugModify));
  Switch('debug.mcp.attach', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsDebugAttach));
  Switch('debug.mcp.banner', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsDebugBanner));
end;

function TAtlasAssistantsSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasAssistantsSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

end.
