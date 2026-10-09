unit BDLsp.IdePlugin.CodeInsight.Composition;

// Meldet den Code Insight-Manager beim Laden des Packages an und beim
// Entladen wieder ab (ADR 0006).

interface

procedure Register;

implementation

uses
  System.SysUtils,
  ToolsAPI,
  BDLsp.IdePlugin.CodeInsight.Hosting.Manager;

var
  ManagerIndex: Integer = -1;

procedure Register;
var
  Services: IOTACodeInsightServices;
begin
  if (ManagerIndex < 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    ManagerIndex := Services.AddCodeInsightManager(TBDLspCodeInsightManager.Create);
end;

procedure Unregister;
var
  Services: IOTACodeInsightServices;
begin
  if (ManagerIndex >= 0) and Supports(BorlandIDEServices, IOTACodeInsightServices, Services) then
    Services.RemoveCodeInsightManager(ManagerIndex);
  ManagerIndex := -1;
end;

initialization

finalization
  Unregister;

end.
