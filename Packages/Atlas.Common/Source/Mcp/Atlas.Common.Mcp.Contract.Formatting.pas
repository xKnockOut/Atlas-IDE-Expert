unit Atlas.Common.Mcp.Contract.Formatting;

// Was das Werkzeug format_code (#1358) vom Server braucht: einen Text formatieren und die Abweichungen nennen. Der
// Host verbindet es mit Editing (Adapters.Mcp.Formatting); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract;

type
  /// <summary>Ganze Datei oder Zeilen FirstLine bis LastLine (0-basiert, einschließlich).</summary>
  TMcpFormatLines = record
    WholeFile: Boolean;
    FirstLine: Integer;
    LastLine: Integer;
    class function All: TMcpFormatLines; static;
    class function Range(AFirstLine, ALastLine: Integer): TMcpFormatLines; static;
  end;

  TMcpFormatDeviation = record
    /// <summary>Zeile im Original, 0-basiert.</summary>
    Line: Integer;
    Message: string;
  end;

  TMcpFormatOutcome = record
    Formatted: string;
    Changed: Boolean;
    Deviations: TArray<TMcpFormatDeviation>;
    HasSyntaxError: Boolean;
    /// <summary>Zeile des ersten Syntaxfehlers, 0-basiert.</summary>
    SyntaxErrorLine: Integer;
    SyntaxErrorMessage: string;
    Stable: Boolean;
  end;

  IMcpFormatting = interface
    ['{B9591C3B-0650-4B1F-8F33-AF64F0E9A68C}']
    /// <summary>Formatiert ALines von AText (Datei ASource) nach AStyle.</summary>
    function Format(const AText: string; const AStyle: TFormatStyle; const ALines: TMcpFormatLines;
      const ASource: TPascalSource): TMcpFormatOutcome;
  end;

implementation

class function TMcpFormatLines.All: TMcpFormatLines;
begin
  Result := Default(TMcpFormatLines);
  Result.WholeFile := True;
end;

class function TMcpFormatLines.Range(AFirstLine, ALastLine: Integer): TMcpFormatLines;
begin
  Result := Default(TMcpFormatLines);
  Result.FirstLine := AFirstLine;
  Result.LastLine := ALastLine;
end;

end.
