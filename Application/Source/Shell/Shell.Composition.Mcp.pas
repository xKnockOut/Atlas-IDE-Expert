unit Shell.Composition.Mcp;

// Host-Adapter der MCP-Werkzeuge: verbindet die SPIs im Mcp-Contract (Atlas.Common.Mcp.Contract.*) mit den
// Schnittstellen der liefernden Features. Nur hier entstehen die Adapter.

interface

uses
  Atlas.Common.Mcp.Contract.Extract;

type
  TMcpComposition = record
    /// <summary>„Methode extrahieren“ aus Editing.</summary>
    class function Extract: IMcpExtract; static;
  end;

implementation

uses
  Atlas.Common.Editing.Composition,
  Adapters.Mcp.Extract;

{ TMcpComposition }

class function TMcpComposition.Extract: IMcpExtract;
begin
  Result := TMcpExtractAdapter.Create(TEditingComposition.Extract);
end;

end.
