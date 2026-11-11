unit Atlas.IDE.Contracts.BuildRequests;

// Vertrag zwischen Modulen (#1888, Modulregel 6): Das Modul Build-Pipeline
// stellt über seinen Scope einen IAtlasBuildRequests bereit (ein Projekt in
// der laufenden IDE über IOTAProjectBuilder bauen, #261); das Modul
// KI-Assistenten nimmt Build-Aufträge von MCP-Clients an und fragt ihn über die
// Registry. Fehlt das Modul Build-Pipeline, lehnt der Eingang mit Grund ab.
// Geht der Auftraggeber während eines Builds (Modul entladen, #1906), meldet er
// sich mit Forget ab: Der Build läuft zu Ende, sein Rückruf wird verworfen (Regel 3).
// Daten in Atlas.Core.Build.Requests; hier nur das Interface. Liegt in Base (Source/Contracts).

interface

uses
  Atlas.Core.Build.Requests;

type
  /// <summary>Builds auf Auftrag in der laufenden IDE (Hauptthread).</summary>
  IAtlasBuildRequests = interface
    ['{6B1D4E27-93A5-4C08-B7F2-1E5A9C3D8F40}']
    /// <summary>Läuft gerade ein Build auf Auftrag?</summary>
    function Busy: Boolean;
    /// <summary>Baut ARequest.Project. False mit Grund in AReason, wenn nicht gebaut wird; sonst kommt das Ergebnis
    /// über AOnDone (auch bei einem Fehler unterwegs).</summary>
    function Start(const ARequest: TAtlasBuildRequest; const ARequestedBy: string; const AOnDone: TAtlasBuildDoneProc;
      out AReason: string): Boolean;
    /// <summary>Der Auftraggeber ARequestedBy geht: Rückruf seines laufenden Auftrags verwerfen; der Build läuft zu
    /// Ende, ohne ihn zu rufen.</summary>
    procedure Forget(const ARequestedBy: string);
  end;

implementation

end.
