unit Atlas.IDE.Contracts.Rules;

// Vertrag zwischen Modulen (#1455, Modulregel 6): Das Modul Prüfregeln
// stellt über seinen Scope eine IAtlasBaselineSource bereit (Baseline des
// Projekts über den Server aktualisieren, #97); die Einrichtung der
// Willkommensseite (#759) fragt sie über die Registry und kommt ohne das
// Modul aus. Den neuen Stand schreibt das Modul in die Projekt-Zusammenfassung
// (Base, Projektverlauf #758); wer ihn zeigt, hört auf
// IAtlasProjectSummaryListener. Den Stand der Datei liest jeder selbst über
// TAtlasProjectBaselines.StateOnDisk (Base).
// Regel-Aktionen am Befund (#1755): „Regel einstellen…“, „Für diese Zeile
// unterdrücken“ und „Regel abschalten“ setzt das Modul um (IAtlasRuleActions);
// Fenster „Atlas-Prüfung“, Befund-Hover und Serverfenster fragen danach. Ohne
// Modul fehlen die Einträge (ohne Prüfregeln gibt es auch keine Regeltreffer).
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

  /// <summary>Ort eines Regelbefunds für die Aktionen am Befund; Zeilen und Spalten 0-basiert wie im LSP.
  /// FileName '' = Befund im oberen Editor (Befund-Hover), sonst springt die Aktion erst dorthin.</summary>
  TAtlasRuleFindingPlace = record
    FileName: string;
    Rule: string;
    StartLine: Integer;
    StartCharacter: Integer;
    EndLine: Integer;
    EndCharacter: Integer;
  end;

  /// <summary>Regel-Aktionen am Befund (#909, #1755). Aufrufe im Hauptthread der IDE.</summary>
  IAtlasRuleActions = interface
    ['{6F0C2B8E-3D41-4A97-B5E6-1C9A7D24F830}']
    /// <summary>„Regel einstellen…“: Einstellungsdialog der Datei (Projekt, ohne Projekt global) bei ARule.</summary>
    procedure Configure(const ARule: string);
    /// <summary>„Für diese Zeile unterdrücken“: Kommentar lsp-ignore über die Code-Aktion des Servers.</summary>
    procedure Suppress(const APlace: TAtlasRuleFindingPlace);
    /// <summary>„Regel abschalten“: rules.&lt;ARule&gt; = "off" in atlas.json, ohne Projekt in der globalen Datei.
    /// </summary>
    procedure Disable(const ARule: string);
  end;

implementation

end.
