unit Atlas.IDE.Rules.Adapters.SettingsDialog;

// Nennt Base die Dialogklasse mit Regel-Editor (IAtlasSettingsDialogProvider aus Atlas.UI.Settings.Contract,
// #1755). Der Dialog selbst steht in Atlas.UI.Rules.SettingsDialog; die Komposition des Moduls meldet den Anbieter an.

interface

uses
  System.Classes,
  Atlas.UI.Settings.Contract;

type
  /// <summary>Anbieter der Dialogklasse für Base (IAtlasSettingsDialogProvider).</summary>
  TAtlasRulesDialogProvider = class(TInterfacedObject, IAtlasSettingsDialogProvider)
  public
    function DialogClass: TComponentClass;
  end;

implementation

uses
  Atlas.UI.Rules.SettingsDialog;

{ TAtlasRulesDialogProvider }

function TAtlasRulesDialogProvider.DialogClass: TComponentClass;
begin
  Result := TAtlasRulesSettingsDialog;
end;

end.
