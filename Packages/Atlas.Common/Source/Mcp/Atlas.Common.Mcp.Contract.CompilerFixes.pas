unit Atlas.Common.Mcp.Contract.CompilerFixes;

// Was explain_compiler_message (#2621) vom Server braucht: sichere Korrekturen zu einer Compilermeldung. Der Host
// verbindet es mit Editing (Adapters.Mcp.CompilerFixes); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Documents.Contract;

type
  /// <summary>Eine Compilermeldung; Line und Column ab 0, Column -1 ohne Spalte.</summary>
  TMcpFixMessage = record
    Code: string;
    Line: Integer;
    Column: Integer;
    Text: string;
  end;

  TMcpCompilerFix = record
    Title: string;
    Edits: TArray<TTextEdit>;
    /// <summary>Die bevorzugte unter mehreren Korrekturen.</summary>
    Preferred: Boolean;
  end;

  IMcpCompilerFixes = interface
    ['{EA22EE1B-1E68-4A91-84D4-CB5DF80BAA46}']
    /// <summary>Korrekturen für AMessage im Text AText.</summary>
    function Fixes(const AText: string; const AMessage: TMcpFixMessage): TArray<TMcpCompilerFix>;
  end;

implementation

end.
