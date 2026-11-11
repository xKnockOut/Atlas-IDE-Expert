unit Atlas.UI.Help.SettingsSection;

// Abschnitt „Allgemein“ des Moduls Hilfe im Optionsdialog (#1886): Modulschalter help.enabled und Quelle
// der Hilfe (help.source: GitHub-Doku zur installierten Version oder installierte HTML-Seiten).

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasHelpSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.help';
    cAreaId = 'Allgemein'; // german-ok Seite (x-page)
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Help.Strings;

{ TAtlasHelpSettingsSection }

function TAtlasHelpSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasHelpSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasHelpSettingsSection.BuildRows;
begin
  ModuleSwitch('help.enabled');
  Choice('help.source', TAtlasHelpStrings.Text(TAtlasHelpTextId.SettingsHelpSource),
    [TAtlasHelpStrings.Text(TAtlasHelpTextId.SettingsHelpOnline),
    TAtlasHelpStrings.Text(TAtlasHelpTextId.SettingsHelpLocal)],
    [TAtlasPluginSettings.cHelpSourceOnline, TAtlasPluginSettings.cHelpSourceLocal]);
end;

end.
