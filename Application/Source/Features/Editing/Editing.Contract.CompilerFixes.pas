unit Editing.Contract.CompilerFixes;

// Schnellkorrekturen für Compilermeldungen (#549) als Schnittstelle für andere Teile des Servers: Ein Host-Adapter
// reicht sie an Konsumenten wie die MCP-Werkzeuge weiter (Adapters.Mcp.CompilerFixes). Erzeugt in
// Editing.Composition; umgesetzt mit TCompilerFixes (Editing.CompilerFixes).

interface

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract;

type
  /// <summary>Eine Compilermeldung; Line und Column ab 0, Column -1 ohne Spalte.</summary>
  TFixMessage = record
    Code: string;
    Line: Integer;
    Column: Integer;
    Text: string;
    class function Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage; static;
  end;

  TCompilerFix = record
    Code: string;
    Title: string;
    Edits: TArray<TTextEdit>;
    Preferred: Boolean;
  end;

  IEditingCompilerFixes = interface
    ['{DF1545F8-5095-4245-AD95-B1E2EB4E7EA1}']
    /// <summary>Korrekturen für AMessage im Text AText, ohne Vorschläge für fehlende Units (E2003).</summary>
    function Fixes(const AText: string; const AMessage: TFixMessage): TArray<TCompilerFix>;
  end;

implementation

{ TFixMessage }

class function TFixMessage.Create(const ACode: string; ALine, AColumn: Integer; const AText: string): TFixMessage;
begin
  Result.Code := UpperCase(Trim(ACode));
  Result.Line := ALine;
  Result.Column := AColumn;
  Result.Text := AText;
end;

end.
