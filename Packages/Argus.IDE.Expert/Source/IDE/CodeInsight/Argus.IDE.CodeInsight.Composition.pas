unit Argus.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager und die Optionsseite "Argus" (#227) beim
// Laden des Packages an und beim Entladen wieder ab (ADR 0006).

interface

procedure Register;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Win.Registry,
  ToolsAPI,
  Argus.UI.Strings,
  Argus.IDE.CodeInsight.Manager,
  Argus.IDE.Settings.Options,
  Argus.IDE.Completion.History;

var
  ManagerIndex: Integer = -1;

/// <summary>Sprache der IDE (#446): Eintrag für bds.exe unter HKCU\Software\Embarcadero\Locales (von
/// BDSSetLang), sonst Sprache der Windows-Oberfläche; Rückfall Englisch.</summary>
function IdeLanguage: TArgusLanguage;
var
  Registry: TRegistry;
  Names: TStringList;
  Name, Code: string;
begin
  Code := '';
  Registry := TRegistry.Create(KEY_READ);
  Names := TStringList.Create;
  try
    Registry.RootKey := HKEY_CURRENT_USER;
    if Registry.OpenKeyReadOnly('Software\Embarcadero\Locales') then
    begin
      Registry.GetValueNames(Names);
      for Name in Names do
        if SameText(Name, ParamStr(0)) and (Registry.GetDataType(Name) = rdString) then
          Code := Registry.ReadString(Name);
    end;
  finally
    Names.Free;
    Registry.Free;
  end;
  if Code = '' then
    if (GetUserDefaultUILanguage and $3FF) = LANG_GERMAN then
      Code := 'DE';
  if SameText(Code, 'DE') then
    Result := TArgusLanguage.German
  else
    Result := TArgusLanguage.English;
end;

procedure Register;
var
  Services: IOTACodeInsightServices;
begin
  TArgusStrings.Language := IdeLanguage;
  if (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    ManagerIndex := Services.AddCodeInsightManager(TArgusCodeInsightManager.Create);
  TArgusOptionsRegistration.Register(
    procedure
    begin
      TArgusIdeHistory.Reset;
    end);
end;

procedure Unregister;
var
  Services: IOTACodeInsightServices;
begin
  TArgusOptionsRegistration.Unregister;
  TArgusIdeHistory.Release;
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
end;

initialization

finalization
  Unregister;

end.
