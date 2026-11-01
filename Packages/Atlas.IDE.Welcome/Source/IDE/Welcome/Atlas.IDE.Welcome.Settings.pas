unit Atlas.IDE.Welcome.Settings;

// Abschnitt „Willkommensseite“ im Optionsdialog, IDE-Teil des Moduls
// Willkommensseite (#1456; vorher fest in Atlas.UI.Settings.Page).
// TAtlasIdeWelcomeSettings ist der IAtlasSettingsSectionProvider, den die
// Composition des Moduls über seinen Scope anmeldet: Für jede Optionsseite
// entsteht ein TAtlasWelcomeSettingsSection mit den Haken dazu.
// - „Zählung zurücksetzen“ leert die Befehlsnutzung von Base
//   (TAtlasIdeCommandUsage, meldet das selbst an alle Hörer),
// - „Gesperrte Tipps wieder zeigen“ hebt die Sperren von „Atlas entdecken“
//   (#757) auf und speichert sie sofort.

interface

uses
  Atlas.UI.Settings.Contract;

type
  TAtlasIdeWelcomeSettings = class(TInterfacedObject, IAtlasSettingsSectionProvider)
  public
    function CreateSection: IAtlasSettingsSection;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  Atlas.IDE.Commands.Usage,
  Atlas.IDE.Welcome.Discover,
  Atlas.UI.Welcome.SettingsSection;

function TAtlasIdeWelcomeSettings.CreateSection: IAtlasSettingsSection;
var
  mSection: TAtlasWelcomeSettingsSection;
begin
  mSection := TAtlasWelcomeSettingsSection.Create;
  Result := mSection;
  mSection.Hooks.OnResetUsage :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeCommandUsage.ResetCounts;
        end);
    end;
  mSection.Hooks.OnUnblockTips :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Settings,
        procedure
        begin
          TAtlasIdeDiscover.UnblockAll;
        end);
    end;
end;

end.
