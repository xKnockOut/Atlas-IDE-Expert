unit Atlas.Common.Diagnostics.RuntimeReport.TestSupport;

// Gemeinsame Hilfen der Tests zu Laufzeitberichten (Auswertung und MCP-Werkzeug).

interface

/// <summary>Unechte Projektsuche: Kunden.Liste und Main liegen unter C:\Projekt, sonst ''.</summary>
function ProjectFile(const AUnitName, AFileName: string): string;

implementation

uses
  System.SysUtils;

function ProjectFile(const AUnitName, AFileName: string): string;
begin
  Result := '';
  if SameText(AUnitName, 'Kunden.Liste') or SameText(AFileName, 'Kunden.Liste.pas') then
  begin
    Result := 'C:\Projekt\Kunden.Liste.pas';
  end
  else if SameText(AUnitName, 'Main') then
  begin
    Result := 'C:\Projekt\Main.pas';
  end;
end;

end.
