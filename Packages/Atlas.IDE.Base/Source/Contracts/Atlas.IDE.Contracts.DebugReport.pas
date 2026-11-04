unit Atlas.IDE.Contracts.DebugReport;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 6): Ein Modul, das eine
// Debug-Sitzung kennt (der Debugger), stellt über seinen Scope eine
// IAtlasDebugReportSource bereit; andere Module (der Tracker für „An Issue
// anhängen …“, #1276) fragen sie über die Registry und kommen ohne
// Debugger aus. Nur Interfaces und Records, kein Code. Liegt in Base (Source/Contracts, #1456, Entscheidung 04.11.2026).

interface

type
  /// <summary>Was ein Bericht über die laufende Debug-Sitzung braucht. Alle Aufrufe im Hauptthread der IDE.
  /// </summary>
  IAtlasDebugReportSource = interface
    ['{9B2EF8CB-FB5B-4D11-A4F2-02000E247925}']
    /// <summary>Prozess-ID des debuggten Programms; 0 ohne laufende Sitzung.</summary>
    function DebuggedProcessId: Cardinal;
    /// <summary>Gestartetes Projekt (.dproj) der Sitzung; '' ohne.</summary>
    function LaunchProject: string;
    /// <summary>Debug-Notiz als Markdown (Ort, Ausschnitt, Aufrufstapel, letzte Exception) und ihr Dateiname
    /// („debug-notiz-…md“); False, wenn das Programm nicht angehalten ist.</summary>
    function DebugNote(out AMarkdown, AFileName: string): Boolean;
    /// <summary>Exception-Verlauf der Sitzung als Text, neueste zuerst, höchstens AMax Einträge; ACount ist die
    /// Zahl im Verlauf. '' ohne Einträge.</summary>
    function ExceptionsText(AMax: Integer; out ACount: Integer): string;
  end;

implementation

end.
