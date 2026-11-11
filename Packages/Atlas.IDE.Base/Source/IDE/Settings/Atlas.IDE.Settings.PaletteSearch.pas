unit Atlas.IDE.Settings.PaletteSearch;

// Einstellungen mit „@“ in der Befehlspalette (#1884, palette.settingsPrefix) in der IDE: verbindet die Quelle aus
// Atlas.Core.Commands.SettingsPalette mit den gespeicherten Werten, den Schnellschaltern (#604), den Knoten der
// installierten Packages (#1903) und ShowSetting (#628). Enter öffnet Tools › Optionen an der Einstellung,
// Alt+Enter schaltet einen Schnellschalter direkt um.

interface

uses
  Atlas.Core.Commands.Palette;

type
  TAtlasIdeSettingsPalette = class
  public
    /// <summary>Zusatzquelle der Palette: mit palette.settingsPrefix die Einstellungen (mit „@“) vor AOther (Quelle
    /// der Module, darf nil sein); ohne die Einstellung nur AOther.</summary>
    class function Sources(const AOther: IAtlasPaletteSource): IAtlasPaletteSource; static;
    /// <summary>Nur die Einstellungen mit „@“.</summary>
    class function SettingsSource: IAtlasPaletteSource; static;
  end;

implementation

uses
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Settings.Catalog,
  Atlas.Core.Commands.SettingsPalette,
  Atlas.UI.Strings,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Settings.Options,
  Atlas.IDE.Settings.QuickToggles,
  Atlas.IDE.Settings.ModuleNodes;

class function TAtlasIdeSettingsPalette.SettingsSource: IAtlasPaletteSource;
var
  mSource: TAtlasSettingsPaletteSource;
begin
  // Den Katalog legt die Quelle erst beim ersten „@“ an.
  mSource := TAtlasSettingsPaletteSource.Create(
    function: TAtlasSettingsCatalog
    begin
      Result := TAtlasSettingsCatalog.CreateDefault;
    end, TAtlasStrings.Language = TAtlasLanguage.English);
  Result := mSource;
  mSource.Settings :=
    function: TAtlasPluginSettings
    begin
      Result := TAtlasIdeSettings.Stored;
    end;
  mSource.IsOn :=
    function(AName: string): Boolean
    begin
      Result := TAtlasIdeQuickToggles.Checked(AName);
    end;
  mSource.Installed :=
    function(const ASwitch: string): Boolean
    begin
      Result := (ASwitch = '') or (TAtlasModuleNodes.NodeOfSwitch(ASwitch) <> nil);
    end;
  mSource.OnOpen :=
    procedure(AName: string)
    begin
      TAtlasOptionsRegistration.ShowSetting(AName);
    end;
  mSource.OnToggle :=
    procedure(AName: string)
    begin
      TAtlasIdeQuickToggles.Switch(AName);
    end;
end;

class function TAtlasIdeSettingsPalette.Sources(const AOther: IAtlasPaletteSource): IAtlasPaletteSource;
begin
  Result := AOther;
  if TAtlasIdeSettings.Stored.PaletteSettingsPrefix then
  begin
    Result := TAtlasPaletteSources.Create(SettingsSource, AOther);
  end;
end;

end.
