unit Atlas.UI.Vcs.SettingsSection;

// Abschnitt des Moduls Versionsverwaltung im Optionsdialog (#1891, Muster #1456): der Modulschalter
// vcs.enabled auf der Seite „Versionsverwaltung“. Die übrigen Zeilen der Seite (Programme, Projekte, Server,
// Branches) baut vorerst noch Base; die Werte liegen in settings.json und bleiben beim Abschalten erhalten.

interface

uses
  Atlas.UI.Settings.Section;

type
  TAtlasVcsSettingsSection = class(TAtlasSettingsSection)
  public const
    cOwnerId = 'atlas.vcs';
    cAreaId = 'Versionsverwaltung';
  protected
    procedure BuildRows; override;
  public
    function OwnerId: string; override;
    function AreaId: string; override;
  end;

implementation

{ TAtlasVcsSettingsSection }

function TAtlasVcsSettingsSection.OwnerId: string;
begin
  Result := cOwnerId;
end;

function TAtlasVcsSettingsSection.AreaId: string;
begin
  Result := cAreaId;
end;

procedure TAtlasVcsSettingsSection.BuildRows;
begin
  ModuleSwitch('vcs.enabled');
end;

end.
