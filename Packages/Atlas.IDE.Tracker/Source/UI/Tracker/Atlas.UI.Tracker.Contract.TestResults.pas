unit Atlas.UI.Tracker.Contract.TestResults;

// Vertrag der Kachel „Testergebnisse“ zwischen IDE und Oberfläche (#763, #1443):
// was die Kachel auslöst (IAtlasTestResultsSource). Die Quelle setzt
// Atlas.IDE.Tracker.Adapters.TestResults um, gezeichnet wird in
// Atlas.UI.Tracker.TestResults.

interface

uses
  Atlas.Core.Tracker.Contract.TestResults;

type
  IAtlasTestResultsSource = interface
    ['{5B7E2C94-1D3A-4F68-9E05-C4A1B8D6F273}']
    function View: TAtlasTestResultsView;
    /// <summary>Zeile wählen (Projektdatei); die Liste zeigt danach deren Fehlschläge.</summary>
    procedure Select(const AProject: string);
    /// <summary>Projekt öffnen und zum Test springen (auch für Fehlschläge vom Server).</summary>
    procedure OpenTest(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    /// <summary>„Fehlgeschlagene erneut ausführen“: genau ATests im Testprojekt der Zeile.</summary>
    procedure RerunFailed(const ARow: TAtlasTestRow; const ATests: TArray<string>);
    /// <summary>„Im Debugger“ (#585): den Test unter dem Debugger starten.</summary>
    procedure Debug(const ARow: TAtlasTestRow; const AFailure: TAtlasTestFailureItem);
    /// <summary>„Vergleichen“ (#1779): Hat der Fehlschlag erwarteten und erhaltenen Wert?</summary>
    function CanCompare(const AFailure: TAtlasTestFailureItem): Boolean;
    /// <summary>„Vergleichen“: Fenster „Erwartet und erhalten“ des Fehlschlags.</summary>
    procedure Compare(const AFailure: TAtlasTestFailureItem);
    /// <summary>„Im Browser“: Seite des Builds auf dem Server.</summary>
    procedure Browse(const ARow: TAtlasTestRow);
    /// <summary>Build-Server jetzt abfragen (ohne auf den Abstand zu warten).</summary>
    procedure QueryNow(const ARow: TAtlasTestRow);
    /// <summary>„Zugang zum Build-Server hinterlegen …“.</summary>
    procedure Credentials(const ARow: TAtlasTestRow);
    procedure OpenProject(const ARow: TAtlasTestRow);
    /// <summary>Befehl für den Zugang eingeschaltet (Einstellung CiLogin).</summary>
    function CanEnterCredentials: Boolean;
    /// <summary>Die Kachel wird gezeigt: bei Bedarf den Server im Hintergrund fragen.</summary>
    procedure Shown;
  end;

implementation

end.
