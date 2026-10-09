unit Argus.IDE.CodeInsight.Composition;

// Meldet den Code Insight-Manager und die Optionsseite 

interface

procedure Register;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  Argus.IDE.CodeInsight.Manager,
  Argus.IDE.Settings.Options;

var
  ManagerIndex: Integer = -1;

procedure Register;
var
  Services: IOTACodeInsightServices;
begin
  if (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    ManagerIndex := Services.AddCodeInsightManager(TArgusCodeInsightManager.Create);
  TArgusOptionsRegistration.Register(nil);
end;

procedure Unregister;
var
  Services: IOTACodeInsightServices;
begin
  TArgusOptionsRegistration.Unregister;
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
end;

initialization

finalization
  Unregister;

end.
