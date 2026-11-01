unit Atlas.IDE.Contracts.Rules;

// Vertrag zwischen Modulen (#1455, ADR 0017 Regel 6): Das Modul Prüfregeln
// stellt über seinen Scope eine IAtlasBaselineSource bereit (Baseline des
// Projekts über den Server aktualisieren, #97); die Einrichtung der
// Willkommensseite (#759) fragt sie über die Registry und kommt ohne das
// Modul aus. Wer den Stand der Baseline danach wissen will (Projektverlauf
// #758), stellt einen IAtlasBaselineListener bereit. Den Stand der Datei
// liest jeder selbst über TAtlasProjectBaselines.StateOnDisk (Base).
// Nur Interfaces und Typen, kein Code. Liegt bis zum Pilot (#1456) im
// Plugin-Package, danach in Atlas.IDE.Contracts.

interface

uses
  Atlas.Core.Projects.Baseline;

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

  /// <summary>Hört auf neue Stände der Baseline (Hauptthread).</summary>
  IAtlasBaselineListener = interface
    ['{ABBA3F2D-B568-403B-A314-D06B2DDF91C3}']
    /// <summary>Baseline von AProject aktualisiert: Zähler des Servers in AUpdate, Datei danach in AState.
    /// </summary>
    procedure BaselineUpdated(const AProject: string; const AUpdate: TAtlasBaselineUpdate;
      const AState: TAtlasBaselineState);
    /// <summary>Der Server schrieb die Baseline außerhalb des Projektordners: nur der Stand im Projektordner.
    /// </summary>
    procedure BaselineMeasured(const AProject: string; const AState: TAtlasBaselineState);
  end;

implementation

end.
