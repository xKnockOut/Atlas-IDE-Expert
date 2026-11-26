unit Mcp.Contract.Process;

// Was die MCP-Werkzeuge vom Betriebssystem des Servers brauchen: ob ein Prozess läuft (Dateien laufender IDEs), die
// eigene Prozessnummer (get_server_status) und das Warten auf Änderungen in einem Ordner (Antworten des Plugins).
// Der Host verbindet es mit seiner Plattform (Adapters.Mcp.Process); die MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  System.SysUtils;

type
  IMcpProcessHost = interface
    ['{0B5E3C51-7A43-4C1D-9E2F-5D8A61F3B0C4}']
    /// <summary>Läuft der Prozess APid noch?</summary>
    function Running(APid: Cardinal): Boolean;
    /// <summary>Nummer des eigenen Prozesses.</summary>
    function CurrentProcessId: Cardinal;
    /// <summary>Warteschritt für das Warten auf eine Datei in AFolder (Antwort des Plugins): kehrt zurück, sobald
    /// sich dort Dateinamen ändern, spätestens nach ASafetyMs; lässt sich der Ordner nicht beobachten, schläft er
    /// APollMs.</summary>
    function FolderWait(const AFolder: string; APollMs, ASafetyMs: Cardinal): TProc;
  end;

implementation

end.
