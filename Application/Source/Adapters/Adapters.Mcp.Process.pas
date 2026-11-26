unit Adapters.Mcp.Process;

// Host-Adapter zwischen Mcp und dem Host: Die MCP-Werkzeuge fragen Prozesse und Ordnersignale über IMcpProcessHost,
// der Host beantwortet sie mit seiner Plattform (Platform.Server). Erzeugt nur in Shell.* und in Tests; kennt nur den
// Contract und die Plattform.

interface

uses
  System.SysUtils,
  Mcp.Contract.Process;

type
  TMcpProcessAdapter = class(TInterfacedObject, IMcpProcessHost)
  public
    /// <summary>Neuer Adapter als Interface (ohne Leck bei direkter Übergabe).</summary>
    class function New: IMcpProcessHost; static;
    function Running(APid: Cardinal): Boolean;
    function CurrentProcessId: Cardinal;
    function FolderWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc;
  end;

implementation

uses
  Platform.Server;

class function TMcpProcessAdapter.New: IMcpProcessHost;
begin
  Result := TMcpProcessAdapter.Create;
end;

function TMcpProcessAdapter.Running(APid: Cardinal): Boolean;
begin
  Result := TProcessInstances.Running(APid);
end;

function TMcpProcessAdapter.CurrentProcessId: Cardinal;
begin
  Result := TServerPlatform.CurrentProcessId;
end;

function TMcpProcessAdapter.FolderWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc;
begin
  Result := TServerPlatform.FolderWait(AFolder, APollMs, ASafetyMs);
end;

end.
