unit Atlas.IDE.Contracts.BuildTools;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 6): Das Modul Build
// stellt über seinen Scope eine IAtlasBuildToolsSource bereit
// (Startprofile #575, Projektaufgaben #900); die Schnellaktionen der
// Willkommensseite (#764) fragen sie über die Registry und kommen ohne das
// Modul aus. Wer das Ende einer Projektaufgabe wissen will, stellt einen
// IAtlasTaskListener bereit. Nur Interfaces und Records, kein Code. Liegt in
// Base (Source/Contracts, #1456, Entscheidung 04.11.2026).

interface

type
  /// <summary>Ergebnis eines Laufs einer Projektaufgabe.</summary>
  TAtlasTaskResult = record
    Name: string;
    Passed: Boolean;
    /// <summary>Kurzfassung für die Anzeige, z. B. „bestanden in 2 s“.</summary>
    Summary: string;
  end;

  /// <summary>Startprofile und Projektaufgaben eines Projekts. Alle Aufrufe im Hauptthread der IDE.</summary>
  IAtlasBuildToolsSource = interface
    ['{D172C666-25FF-4381-BC18-03261F027EEF}']
    /// <summary>Namen der Startprofile von AProject und das aktive; leer ohne Startprofile.</summary>
    function StartProfiles(const AProject: string; out AActive: string): TArray<string>;
    /// <summary>Startprofil AProfile von AProject ausführen (mit Debugger); False mit Grund.</summary>
    function RunStartProfile(const AProject, AProfile: string; out AReason: string): Boolean;
    /// <summary>Namen der Projektaufgaben von AProject; leer, solange die Aufgaben aus sind.</summary>
    function TaskNames(const AProject: string): TArray<string>;
    /// <summary>Aufgabe AName in AProject starten; das Ende meldet IAtlasTaskListener. False mit Grund.</summary>
    function RunTask(const AProject, AName: string; out AReason: string): Boolean;
  end;

  /// <summary>Hört auf das Ende von Projektaufgaben (Hauptthread).</summary>
  IAtlasTaskListener = interface
    ['{0A20ACCE-78EA-4ABC-AC46-64342696B5AB}']
    procedure TaskFinished(const AProject: string; const AResult: TAtlasTaskResult);
  end;

implementation

end.
