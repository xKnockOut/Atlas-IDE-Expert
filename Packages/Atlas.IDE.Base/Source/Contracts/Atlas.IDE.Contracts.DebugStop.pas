unit Atlas.IDE.Contracts.DebugStop;

// Vertrag zwischen Modulen (#1873, Modulregel 6): Das Modul, das die
// Debug-Sitzung kennt (der Debugger), stellt über seinen Scope eine
// IAtlasDebugStopSource bereit: den Rahmen des Halts in eigenem Code und
// Auswerten ohne Nebenwirkungen. Das Modul Tests fragt sie über die Registry
// für „Test daraus anlegen …“ und kommt ohne Debugger aus; die
// Exception-Leiste des Debuggers ruft den Befehl über seine Kennung auf. Nur
// Records, Interfaces und Konstanten, kein Code.

interface

const
  /// <summary>Befehl „Test daraus anlegen …“, den das Modul Tests anmeldet.</summary>
  cAtlasTestFromDebugStopCommand = 'Atlas.TestFromDebugStop';

type
  /// <summary>Rahmen des Halts: bei einer Exception in RTL oder VCL der erste Rahmen in eigenem Code (#578), sonst
  /// der oberste mit Quelltext.</summary>
  TAtlasDebugStopFrame = record
    FileName: string;
    /// <summary>Zeile, 1-basiert.</summary>
    Line: Integer;
    /// <summary>Kopfzeile wie im Fenster Aufrufstack („Unit1.TGewicht.Parse('12,5 kg')“); Argumente in Klammern.
    /// </summary>
    Header: string;
    /// <summary>Der Rahmen ist der aktuelle des Threads: Evaluate wertet in ihm aus. Sonst gelten nur die
    /// Argumente aus Header.</summary>
    Current: Boolean;
    /// <summary>Klasse und Meldung der Exception, an der das Programm steht; '' ohne.</summary>
    ExceptionClass: string;
    ExceptionMessage: string;
  end;

  /// <summary>Halt der laufenden Debug-Sitzung für andere Module. Alle Aufrufe im Hauptthread der IDE.</summary>
  IAtlasDebugStopSource = interface
    ['{B7DE32AE-60F4-490E-B3A2-0EDD2DC5D3BF}']
    /// <summary>Rahmen des Halts; False, wenn kein Programm angehalten ist oder kein Rahmen Quelltext hat.
    /// </summary>
    function StopFrame(out AFrame: TAtlasDebugStopFrame): Boolean;
    /// <summary>Wertet AExpression im aktuellen Rahmen aus, ohne Nebenwirkungen; mit AProperties auch Getter von
    /// Eigenschaften. False, wenn nicht auswertbar oder nach der Zeitgrenze.</summary>
    function Evaluate(const AExpression: string; AProperties: Boolean; out AText: string): Boolean;
  end;

implementation

end.
