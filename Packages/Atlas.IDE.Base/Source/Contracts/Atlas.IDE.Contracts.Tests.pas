unit Atlas.IDE.Contracts.Tests;

// Vertrag zwischen Modulen (#1455, Modulregel 6): Das Modul Tests stellt
// über seinen Scope eine IAtlasTestsSource bereit (Testprojekt ausführen,
// einzelnen Test debuggen oder finden, #69, #585); die Willkommensseite
// (Karte Tests #763, Schnellaktionen #764) fragt sie über die Registry und
// kommt ohne das Modul aus. Tests ausführen geht über IAtlasTestRunner von
// Base, weil auch Base (Auswirkungsanalyse #1120) Tests startet. Wer das
// Ergebnis eines Laufs wissen will, stellt einen IAtlasTestsListener bereit;
// den ganzen Lauf schreibt das Modul in die Projekt-Zusammenfassung (Base).
// Nur Interfaces, kein Code. Liegt in Base (Source/Contracts, #1456, Entscheidung 04.11.2026).

interface

type
  /// <summary>Testprojekte ausführen, einzelne Tests debuggen und finden. Alle Aufrufe im Hauptthread der IDE.
  /// </summary>
  IAtlasTestsSource = interface
    ['{51F6CD1A-74CF-4337-9589-5966736B0611}']
    /// <summary>Alle Tests des Testprojekts ATestProject (.dproj) bauen und ausführen; das Ergebnis meldet
    /// IAtlasTestsListener. False mit Grund.</summary>
    function RunProject(const ATestProject: string; out AReason: string): Boolean;
    /// <summary>Test AFullName aus AProject im Debugger starten (#585). False mit Grund ('' = nichts zu melden).
    /// </summary>
    function DebugByName(const AProject, AFullName: string; out AReason: string): Boolean;
    /// <summary>Datei und Zeile (ab 1) des Tests AFullName im Testprojekt AProject; False, wenn er nicht zu finden
    /// ist.</summary>
    function LocateByName(const AProject, AFullName: string; out AFileName: string; out ALine: Integer): Boolean;
    /// <summary>Läuft gerade ein Testlauf oder eine Debug-Sitzung eines Tests?</summary>
    function Busy: Boolean;
  end;

  /// <summary>Hört auf das Ende eines Testlaufs (Hauptthread).</summary>
  IAtlasTestsListener = interface
    ['{ACFE6EC5-F063-4C02-B238-275945ECAE58}']
    /// <summary>ATestProject: das Testprojekt (.dproj); APassed bestanden, AFailed fehlgeschlagen einschließlich
    /// Fehler (0 und 0, wenn nichts auszuwerten war).</summary>
    procedure TestsFinished(const ATestProject: string; APassed, AFailed: Integer);
  end;

implementation

end.
