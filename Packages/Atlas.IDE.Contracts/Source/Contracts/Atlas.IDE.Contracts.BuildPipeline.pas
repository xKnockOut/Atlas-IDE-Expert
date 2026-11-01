unit Atlas.IDE.Contracts.BuildPipeline;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 6): Das Modul
// Build-Pipeline (atlas.buildpipeline) stellt über seinen Scope ein
// IAtlasBuildJobs bereit, Builds auf Auftrag (#261). Die Module Tests (vor
// den Tests bauen), Build-Werkzeuge (Neubau nach den Projektaufgaben) und die
// Willkommensseite (Schnellaktion „Build“, #764) fragen es über die Registry
// und kommen ohne das Modul aus. Nur Interfaces und Records mit einfachen
// Typen, kein Code. Liegt im Package Atlas.IDE.Contracts (#1456).

interface

type
{$SCOPEDENUMS ON}
  /// <summary>Art des Builds: Make (nur Geändertes), Build (alles neu), Check (Syntaxprüfung).</summary>
  TAtlasBuildJobKind = (Make, Build, Check);
{$SCOPEDENUMS OFF}

  /// <summary>Auftrag für einen Build eines offenen Projekts.</summary>
  TAtlasBuildJob = record
    /// <summary>Absoluter Pfad der .dproj.</summary>
    Project: string;
    Kind: TAtlasBuildJobKind;
    /// <summary>'' = aktive Konfiguration bzw. Plattform der IDE; gilt nur für diesen Build.</summary>
    Configuration: string;
    Platform: string;
    /// <summary>Auftraggeber in den Compile-Ereignissen; '' = wie ein Build des Benutzers (Tests nach dem Build
    /// und die übrigen Teilnehmer laufen mit).</summary>
    RequestedBy: string;
  end;

  /// <summary>Ergebnis eines Auftrags.</summary>
  TAtlasBuildJobResult = record
    /// <summary>'' = gebaut (Ergebnis in Succeeded), sonst der Grund, aus dem nicht gebaut wurde.</summary>
    Error: string;
    Succeeded: Boolean;
    /// <summary>Erzeugte Datei (.exe, .bpl); '' unbekannt.</summary>
    OutputFile: string;
    DurationMs: Int64;
  end;

  TAtlasBuildJobDone = reference to procedure(const AResult: TAtlasBuildJobResult);

  /// <summary>Builds auf Auftrag. Alle Aufrufe im Hauptthread der IDE.</summary>
  IAtlasBuildJobs = interface
    ['{FA0357F6-33CA-4AB4-BD90-9BBAD2B8B8AF}']
    /// <summary>Baut AJob.Project. False mit Grund in AReason, wenn nicht gebaut wird; sonst kommt das Ergebnis über
    /// ADone (darf nil sein), auch bei einem Fehler unterwegs.</summary>
    function Start(const AJob: TAtlasBuildJob; const ADone: TAtlasBuildJobDone; out AReason: string): Boolean;
    /// <summary>Läuft ein Auftrag (Build oder Warten auf die Meldungen)?</summary>
    function Busy: Boolean;
  end;

implementation

end.
