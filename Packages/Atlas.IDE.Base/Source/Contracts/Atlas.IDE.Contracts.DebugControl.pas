unit Atlas.IDE.Contracts.DebugControl;

// Vertrag zwischen Modulen (#1874, Modulregel 6): Das Modul, das die Debug-Sitzung kennt (der Debugger), stellt über
// seinen Scope eine IAtlasDebugControl bereit: Programm im Debugger starten und beenden, Haltepunkte der Gruppe
// Atlas-KI setzen und entfernen, weiterlaufen und Schritte, Zustand lesen und Ausdrücke auswerten. Das Modul
// KI-Assistenten nimmt die Debug-Aufträge von MCP-Clients an (debug_start … debug_evaluate), prüft Rechte und Pause
// und fragt den Vertrag bei jedem Auftrag neu über die Registry (Regel 2). Fehlt der Debugger, lehnt der Eingang mit
// Grund ab. Haltepunkte des Benutzers fasst der Vertrag nie an. Daten in Atlas.Core.DebugControl.Types; hier nur
// das Interface.

interface

uses
  Atlas.Core.DebugControl.Types;

type
  /// <summary>Steuerung des Debuggers für KI-Assistenten. Alle Aufrufe im Hauptthread der IDE.</summary>
  IAtlasDebugControl = interface
    ['{4E8A2C71-0B9D-4F36-A5E2-7C1D3B9F6A08}']
    function Phase: TAtlasDebugControlPhase;
    /// <summary>Zählt jeden Halt der Sitzung; daran erkennt der Aufrufer nach Weiterlaufen einen neuen Halt.
    /// </summary>
    function StopCount: Integer;
    /// <summary>Startet ALaunch im Debugger (macht das Projekt aktiv). False mit Grund.</summary>
    function Launch(const ALaunch: TAtlasDebugControlLaunch; out AReason: string): Boolean;
    /// <summary>Beendet das laufende Programm.</summary>
    procedure Terminate;
    /// <summary>Lässt das angehaltene Programm weiterlaufen. False mit Grund.</summary>
    function Resume(out AReason: string): Boolean;
    /// <summary>Ein Schritt; AFileName und ALine nur bei ToLine. False mit Grund.</summary>
    function Step(AKind: TAtlasDebugControlStep; const AFileName: string; ALine: Integer;
      out AReason: string): Boolean;
    /// <summary>Zustand mit höchstens AFrames Rahmen; ALocals: lokale Variablen mitlesen.</summary>
    function ReadState(AFrames: Integer; ALocals: Boolean; out AState: TAtlasDebugControlState): Boolean;
    /// <summary>Wertet AExpression im aktuellen Rahmen aus; ASideEffects erlaubt Aufrufe. False mit Grund (etwa
    /// kein Zugriff, #840).</summary>
    function Evaluate(const AExpression: string; ASideEffects: Boolean; out AValue, ATypeName,
      AReason: string): Boolean;
    /// <summary>Setzt einen Haltepunkt in der Gruppe cAtlasDebugControlGroup. False mit Grund.</summary>
    function AddBreakpoint(const AFileName: string; ALine: Integer; const ACondition: string; APassCount: Integer;
      out ABreakpoint: TAtlasDebugControlBreakpoint; out AReason: string): Boolean;
    /// <summary>Entfernt den Haltepunkt AId der Gruppe cAtlasDebugControlGroup; False, wenn es ihn nicht gibt.
    /// </summary>
    function RemoveBreakpoint(AId: Integer): Boolean;
    /// <summary>Entfernt alle Haltepunkte der Gruppe cAtlasDebugControlGroup; liefert ihre Zahl.</summary>
    function RemoveAllBreakpoints: Integer;
  end;

implementation

end.
