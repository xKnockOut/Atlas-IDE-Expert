unit Atlas.UI.Assistants.SettingsSection;

// Abschnitt des Moduls KI-Assistenten im Optionsdialog (#1888, Muster #1456): der Modulschalter
// assistants.enabled auf der Seite „Compiler“. „Builds für KI-Assistenten“ (compiler.mcpBuild) baut vorerst
// noch das Modul Build-Pipeline; der Wert gilt hier für den Build-Eingang.

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasAssistantsSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.assistants';
    cAreaId = 'Compiler';
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
  // Änderungen an offenen Dateien (#397); Builds für KI-Assistenten (compiler.mcpBuild) stehen bei der Build-Pipeline.
  Switch('assistants.edit', TAtlasAssistantsStrings.Text(TAtlasAssistantsTextId.SettingsEdit));
end;

end.
