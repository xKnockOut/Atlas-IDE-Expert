unit Shell.Composition.Mcp;

// Host-Adapter der MCP-Werkzeuge: verbindet die SPIs im Mcp-Contract (Atlas.Common.Mcp.Contract.*) mit den
// Schnittstellen der liefernden Features. Nur hier entstehen die Adapter.

interface

uses
  Atlas.Common.Mcp.Contract.CompilerFixes,
  Atlas.Common.Mcp.Contract.Extract,
  Atlas.Common.Mcp.Contract.Formatting;

type
  TMcpComposition = record
    /// <summary>„Methode extrahieren“ aus Editing.</summary>
    class function Extract: IMcpExtract; static;
    /// <summary>Formatierer aus Editing.</summary>
    class function Formatting: IMcpFormatting; static;
    /// <summary>Schnellkorrekturen für Compilermeldungen aus Editing.</summary>
    class function CompilerFixes: IMcpCompilerFixes; static;
  end;

implementation

uses
  Atlas.Common.Editing.Composition,
  Adapters.Mcp.CompilerFixes,
  Adapters.Mcp.Extract,
  Adapters.Mcp.Formatting;

{ TMcpComposition }

class function TMcpComposition.Extract: IMcpExtract;
begin
  Result := TMcpExtractAdapter.Create(TEditingComposition.Extract);
end;

class function TMcpComposition.Formatting: IMcpFormatting;
begin
  Result := TMcpFormattingAdapter.Create(TEditingComposition.Formatting);
end;

class function TMcpComposition.CompilerFixes: IMcpCompilerFixes;
begin
  Result := TMcpCompilerFixesAdapter.Create(TEditingComposition.CompilerFixes);
end;

end.
