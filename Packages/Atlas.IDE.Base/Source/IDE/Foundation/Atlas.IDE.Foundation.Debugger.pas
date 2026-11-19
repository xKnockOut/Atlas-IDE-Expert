unit Atlas.IDE.Foundation.Debugger;

// Debugger der IDE (IOTADebuggerServices) für Base und Module: eine Stelle, die den Dienst holt, statt einer
// eigenen Abfrage in jeder Unit. Nur im Hauptthread.

interface

uses
  ToolsAPI;

type
  TAtlasIdeDebugger = class
  public
    /// <summary>Debugger-Dienst der IDE; nil, wenn die IDE keinen anbietet (Start, Beenden).</summary>
    class function Services: IOTADebuggerServices; static;
  end;

implementation

uses
  System.SysUtils;

{ TAtlasIdeDebugger }

class function TAtlasIdeDebugger.Services: IOTADebuggerServices;
begin
  if not Supports(BorlandIDEServices, IOTADebuggerServices, Result) then
  begin
    Result := nil;
  end;
end;

end.
