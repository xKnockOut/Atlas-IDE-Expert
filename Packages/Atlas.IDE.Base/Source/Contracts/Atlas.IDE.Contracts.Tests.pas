unit Atlas.IDE.Contracts.Tests;

// Vertrag zwischen Modulen (#1455, Modulregel 6): Das Modul Tests stellt
// über seinen Scope eine IAtlasTestsSource bereit (Testprojekt ausführen,
// einzelnen Test debuggen oder finden, #69, #585); die Willkommensseite
// (Karte Tests #763, Schnellaktionen #764) fragt sie über die Registry und
// kommt ohne das Modul aus. Tests ausführen geht über IAtlasTestRunner von
// Base, weil auch Base (Auswirkungsanalyse #1120) Tests startet. Wer das
// Ergebnis eines Laufs wissen will, stellt einen IAtlasTestsListener bereit;
// den ganzen Lauf schreibt das Modul in die Projekt-Zusammenfassung (Base).
// Erwartet und erhalten eines Fehlschlags (#1779) vergleicht das Modul
// (IAtlasTestValues): Befund-Hover (Base) und Kachel „Testergebnisse“ der
// Willkommensseite fragen, ob es zu einem Test Werte gibt, und zeigen dann
// „Vergleichen“. Ohne Modul fehlt der Eintrag.
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

  /// <summary>Erwartet und erhalten eines fehlgeschlagenen Tests vergleichen (#1779, tests.compare). Aufrufe im
  /// Hauptthread der IDE.</summary>
  IAtlasTestValues = interface
    ['{44E95396-83E2-4D63-B2AA-68E3F5E31689}']
    /// <summary>Hat der Test an ALine (0-basiert) der Testunit im oberen Editor einen Fehlschlag mit erwartetem und
    /// erhaltenem Wert? False auch mit tests.compare aus.</summary>
    function HasValuesAt(ALine: Integer): Boolean;
    /// <summary>Fenster „Erwartet und erhalten“ für den Test an ALine im oberen Editor; ohne Werte nichts.</summary>
    procedure CompareAt(ALine: Integer);
    /// <summary>Wie HasValuesAt für den Test AFullName (Unit.Fixture.Methode[.Fall]).</summary>
    function HasValues(const AFullName: string): Boolean;
    /// <summary>Wie CompareAt für den Test AFullName.</summary>
    procedure Compare(const AFullName: string);
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
