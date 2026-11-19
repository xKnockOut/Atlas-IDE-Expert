unit Atlas.Core.Setup.Contract;

// Contract des Plugin-Features Setup (#1443): Was die Knöpfe der Prüfliste in der IDE tun.
// Den Zustand für die Prüfungen liefert die IDE getrennt (TAtlasSetupSnapshot in
// Atlas.Core.Setup.Checklist), weil seine Typen zum Root des Features gehören.

interface

type
  /// <summary>Was die Knöpfe in der IDE tun; Tests setzen eine eigene Umgebung ein.</summary>
  IAtlasSetupEnvironment = interface
    ['{3E7748DE-33A6-4A16-9516-152F17CCEDA1}']
    /// <summary>Dateiauswahl für AtlasServer.exe; False bei Abbruch.</summary>
    function ChooseServerPath(out APath: string): Boolean;
    /// <summary>Pfad in den Plugin-Einstellungen speichern (ServerPath).</summary>
    procedure SaveServerPath(const APath: string);
    /// <summary>Server starten bzw. neu starten; True, wenn er läuft.</summary>
    function StartServer(ARestart: Boolean): Boolean;
    /// <summary>atlas.server.rebuildIndex; True, wenn der Server den Befehl angenommen hat.</summary>
    function RebuildIndex: Boolean;
    /// <summary>Error Insight der IDE schalten; True, wenn geschrieben.</summary>
    function SetErrorInsight(AEnabled: Boolean): Boolean;
    /// <summary>Optionsseite „Tastenkonflikte“ öffnen.</summary>
    procedure OpenKeyConflicts;
  end;

implementation

end.
