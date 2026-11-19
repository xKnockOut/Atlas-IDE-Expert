unit Atlas.IDE.Rules.Adapters.SettingsDialog;

// Nennt Base die Dialogklasse mit Regel-Editor (IAtlasSettingsDialogProvider aus Atlas.UI.Settings.ProjectDialog,
// #1755). Der Dialog selbst steht in Atlas.UI.Rules.SettingsDialog; die Komposition des Moduls meldet den Anbieter an.

interface

uses
  Atlas.UI.Settings.ProjectDialog;

type
  /// <summary>Anbieter der Dialogklasse für Base (IAtlasSettingsDialogProvider).</summary>
  TAtlasRulesDialogProvider = class(TInterfacedObject, IAtlasSettingsDialogProvider)
  public
    function DialogClass: TAtlasProjectSettingsDialogClass;
  end;

implementation

uses
  Atlas.UI.Rules.SettingsDialog;

{ TAtlasRulesDialogProvider }

function TAtlasRulesDialogProvider.DialogClass: TAtlasProjectSettingsDialogClass;
begin
  Result := TAtlasRulesSettingsDialog;
end;

end.
