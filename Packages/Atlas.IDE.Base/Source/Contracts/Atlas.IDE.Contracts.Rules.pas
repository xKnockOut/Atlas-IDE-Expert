unit Atlas.IDE.Contracts.Rules;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 6): Das Modul Prüfregeln
// stellt über seinen Scope eine IAtlasBaselineSource bereit (Baseline des
// Projekts über den Server aktualisieren, #97); die Einrichtung der
// Willkommensseite (#759) fragt sie über die Registry und kommt ohne das
// Modul aus. Den neuen Stand schreibt das Modul in die Projekt-Zusammenfassung
// (Base, Projektverlauf #758); wer ihn zeigt, hört auf
// IAtlasProjectSummaryListener. Den Stand der Datei liest jeder selbst über
// TAtlasProjectBaselines.StateOnDisk (Base).
// Nur Interfaces und Typen, kein Code. Liegt in Base (Source/Contracts, #1456, Entscheidung 04.11.2026).

interface

type
  /// <summary>Ergebnis des Aktualisierens im Hauptthread: ASucceeded mit Treffern ATotal in AFiles Dateien, sonst
  /// AReason.</summary>
  TAtlasBaselineUpdateDone = reference to procedure(ASucceeded: Boolean; ATotal, AFiles: Integer;
    const AReason: string);

  /// <summary>Baseline aktualisieren. Aufruf im Hauptthread der IDE.</summary>
  IAtlasBaselineSource = interface
    ['{39BBFF9B-7AF9-4899-9DC4-CC6732D65FAC}']
    /// <summary>Lässt den Server alle Dateien von AProject (.dproj) prüfen und die Baseline schreiben; ADone (darf
    /// nil sein) bekommt das Ergebnis. '' = gestartet, sonst der Grund.</summary>
    function StartUpdate(const AProject: string; const ADone: TAtlasBaselineUpdateDone): string;
  end;

implementation

end.
