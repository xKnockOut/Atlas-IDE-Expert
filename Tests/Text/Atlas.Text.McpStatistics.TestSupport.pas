unit Atlas.Text.McpStatistics.TestSupport;

// Gemeinsame Testdaten für die Tests der MCP-Aufrufstatistik (Datenmodell im Atlas.Text und Texte im Server).

interface

uses
  Atlas.Text.McpStatistics;

type
  TMcpStatisticsTestSupport = record
  public
    /// <summary>Zusammenfassung für AName mit ACalls Aufrufen und AErrors Fehlern; Dauer 1,2 s (höchstens 1,5 s),
    /// Größe 4 KB (höchstens 1,5 MB).</summary>
    class function Called(const AName: string; ACalls, AErrors: Integer): TMcpCallSummary; static;
  end;

implementation

const
  cMedianMs = 1200;
  cMaxMs = 1500;
  cMedianBytes = 4096;
  cMaxBytes = 3 * 1024 * 1024 div 2;

class function TMcpStatisticsTestSupport.Called(const AName: string; ACalls, AErrors: Integer): TMcpCallSummary;
begin
  Result := Default(TMcpCallSummary);
  Result.Name := AName;
  Result.Calls := ACalls;
  Result.Errors := AErrors;
  Result.MedianMs := cMedianMs;
  Result.MaxMs := cMaxMs;
  Result.MedianBytes := cMedianBytes;
  Result.MaxBytes := cMaxBytes;
end;

end.
