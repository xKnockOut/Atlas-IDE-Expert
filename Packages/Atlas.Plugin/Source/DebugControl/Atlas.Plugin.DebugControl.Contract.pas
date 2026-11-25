unit Atlas.Plugin.DebugControl.Contract;

// Steuerung des Debuggers für KI-Assistenten (#1874) ohne Open Tools API: Daten des Vertrags
// Atlas.IDE.Base.Foundation.DebugControl, gemeinsam für den Debugger (führt aus) und das Modul
// KI-Assistenten (Eingang der MCP-Aufträge, Rechte, Antworten). Zeilen sind 1-basiert.

interface

{$SCOPEDENUMS ON}

const
  /// <summary>Gruppe der Haltepunkte, die ein KI-Assistent setzt.</summary>
  cAtlasDebugControlGroup = 'Atlas-KI';

type
  /// <summary>Zustand des Debuggers: kein Prozess, Programm läuft, Programm hält.</summary>
  TAtlasDebugControlPhase = (None, Running, Stopped);

  /// <summary>Schritt: in Aufrufe hinein, über die Zeile, bis zum Rücksprung (MCP: out), bis zu einer Zeile.</summary>
  TAtlasDebugControlStep = (Into, Over, Return, ToLine);

  /// <summary>Was starten: Projekt (voller Pfad), Konfiguration und Plattform ('' = wie in der IDE), nur ein
  /// DUnitX-Test (Unit.Fixture.Methode, '' = alle) und Parameter des Programms.</summary>
  TAtlasDebugControlLaunch = record
    Project: string;
    Configuration: string;
    Platform: string;
    Test: string;
    Arguments: string;
  end;

  TAtlasDebugControlFrame = record
    FileName: string;
    Line: Integer;
    /// <summary>Kopfzeile wie im Fenster Aufrufstack.</summary>
    Header: string;
    /// <summary>Rahmen in eigenem Code (nicht RTL, VCL, Bibliotheken).</summary>
    Own: Boolean;
  end;

  TAtlasDebugControlVariable = record
    Name: string;
    TypeName: string;
    Value: string;
  end;

  TAtlasDebugControlThread = record
    Id: Cardinal;
    Name: string;
    Current: Boolean;
  end;

  /// <summary>Haltepunkt, der nicht greifen wird (#577), bei einem Start durch den Assistenten gemeldet statt im
  /// Dialog (#2895): Stelle, Grund als Kennung (noCode, inactive, noDebugInfo, notInProject, unreadable), Text in der
  /// Sprache der Oberfläche und die nächste Zeile mit Code (0 ohne).</summary>
  TAtlasDebugControlWarning = record
    FileName: string;
    Line: Integer;
    Reason: string;
    Text: string;
    NextLine: Integer;
  end;

  /// <summary>Zustand der Sitzung. Bei Phase Stopped: Grund (breakpoint, step, exception, pause, other), bei einer
  /// Exception Klasse und Meldung, Stelle des obersten Rahmens mit Quelltext, Aufrufstapel, lokale Variablen des
  /// aktuellen Rahmens und Threads.</summary>
  TAtlasDebugControlState = record
    Phase: TAtlasDebugControlPhase;
    StopReason: string;
    ExceptionClass: string;
    ExceptionMessage: string;
    FileName: string;
    Line: Integer;
    Frames: TArray<TAtlasDebugControlFrame>;
    Locals: TArray<TAtlasDebugControlVariable>;
    Threads: TArray<TAtlasDebugControlThread>;
    /// <summary>Haltepunkte, die beim letzten Start des Assistenten nicht greifen werden; nur einmal gemeldet.
    /// </summary>
    Warnings: TArray<TAtlasDebugControlWarning>;
  end;

  /// <summary>Gesetzter Haltepunkt: Kennung (ab 1), Stelle und ob die Zeile Code hat (#577).</summary>
  TAtlasDebugControlBreakpoint = record
    Id: Integer;
    FileName: string;
    Line: Integer;
    Valid: Boolean;
  end;

implementation

end.
