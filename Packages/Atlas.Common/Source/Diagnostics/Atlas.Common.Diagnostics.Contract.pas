unit Atlas.Common.Diagnostics.Contract;

// Contract des anonymisierten Diagnoselogs (#647). Ein eigener Kanal neben
// ILogger: je Anfrage eine Zeile mit Dauer, Ergebnis und Grundcode, je
// Serverlauf Start und Ende mit Grund. Die Zeilen lassen sich ohne Bedenken
// weitergeben: keine Pfade, keine Namen aus Nutzercode, kein Quelltext.
// Was in eine Zeile darf, bestimmt der Aufrufer nur über Zahlen, Kurz-IDs
// (doc#4) und feste Codes; ein Filter prüft jede Zeile vor dem Schreiben.

interface

{$SCOPEDENUMS ON}

uses
  System.SysUtils;

type
  /// <summary>Ausgang einer Anfrage.</summary>
  TDiagnosticOutcome = (Ok, Empty, Timeout, Cancelled, Error);

  /// <summary>Eine Anfrage, wie sie ins Diagnoselog geht. Alle Texte sind Codes oder Kurz-IDs.</summary>
  TDiagnosticRequest = record
    Time: TDateTime;
    Method: string;
    ElapsedMs: Int64;
    /// <summary>Wartezeit vor dem Start (Warteschlange des Thread-Pools).</summary>
    QueueMs: Int64;
    Outcome: TDiagnosticOutcome;
    /// <summary>Zahl der Ergebnisse bei Ok (Einträge der Vervollständigung), sonst 0.</summary>
    Count: Integer;
    /// <summary>Grundcode bei Empty (unitNotFound, noTarget …), Klassenname bei Error.</summary>
    Reason: string;
    /// <summary>Kurz-ID des Dokuments (doc#4); '' ohne Dokument.</summary>
    Document: string;
    Version: Integer;
    Length_: Integer;
    /// <summary>Prüfsumme des Puffers als Hex (#395).</summary>
    Checksum: string;
    /// <summary>Zeile und Spalte ab 0; Line &lt; 0 ohne Position.</summary>
    Line: Integer;
    LineCount: Integer;
    Column: Integer;
    /// <summary>Weitere Angaben als "Schlüssel=Wert", z. B. ctx=memberAccess, syntaxErr=2.</summary>
    Notes: TArray<string>;
    /// <summary>Stufe, an der die Namensauflösung scheiterte (resolve: …); '' ohne.</summary>
    Resolve: string;
    /// <summary>Zustand des Index: Units, davon Bibliothek, Fortschritt in Prozent (-1 = fertig).</summary>
    IndexUnits: Integer;
    IndexLibrary: Integer;
    IndexLoading: Integer;
  end;

  /// <summary>Grund für das Ende eines Serverlaufs.</summary>
  TDiagnosticEndReason = (
    /// <summary>shutdown/exit vom Client.</summary>
    Clean,
    /// <summary>Eingabe geschlossen, ohne exit: Die IDE hat die Verbindung getrennt oder den Prozess beendet.</summary>
    InputClosed,
    /// <summary>Der Editor-Prozess ist beendet (Wächter auf den Elternprozess).</summary>
    ParentExited,
    /// <summary>Unbehandelte Exception.</summary>
    Exception_);

  /// <summary>Stand des Prozesses für Start- und Endzeile.</summary>
  TDiagnosticProcess = record
    MemoryBytes: Int64;
    Threads: Integer;
  end;

  /// <summary>Ziel der Zeilen (SPI), z. B. Tagesdateien in einem Ordner.</summary>
  IDiagnosticWriter = interface
    ['{5B0E9C47-3A61-4D2B-8F17-C4E2A9D6B013}']
    procedure WriteLine(const ALine: string);
  end;

  /// <summary>Diagnoselog (API). Threadsicher; jeder Aufruf kostet unter 1 ms.</summary>
  IDiagnosticLog = interface
    ['{C83F2D15-6E94-4A07-B5D1-29A7E0F4C862}']
    procedure LogRequest(const ARequest: TDiagnosticRequest);
    procedure LogStart(const AVersion: string; const AProcess: TDiagnosticProcess);
    /// <summary>AException: Klassenname; AStack: Adressen und Atlas-eigene Routinen, eine je Zeile.</summary>
    procedure LogEnd(AReason: TDiagnosticEndReason; AExitCode: Integer; const AProcess: TDiagnosticProcess;
      const AException: string = ''; const AStack: string = '');
    /// <summary>Freier Ereigniscode ohne Namen, z. B. "previous run ended without log".</summary>
    procedure LogEvent(const AText: string);
    /// <summary>Übernimmt die Einstellungen. Vorher gesammelte Zeilen werden erst jetzt geschrieben
    /// oder (bei AEnabled = False) verworfen.</summary>
    procedure Configure(AEnabled: Boolean);
    function Enabled: Boolean;
    /// <summary>Zeilen, die der Filter verworfen hat.</summary>
    function Dropped: Integer;
  end;

const
  DiagnosticEndReasonCodes: array[TDiagnosticEndReason] of string = ('clean', 'inputClosed', 'parentExited',
    'exception');
  DiagnosticOutcomeCodes: array[TDiagnosticOutcome] of string = ('ok', 'empty', 'timeout', 'cancelled', 'error');

implementation

end.
