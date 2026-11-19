unit Atlas.Core.Hover.Layout.Input;

// Eingabe des Hover-Satzes: Inhalt, Breite, Farben, Texte und Schalter. Den Satz rechnet Atlas.Core.Hover.Layout;
// den Mess-Rückruf der Oberfläche (IAtlasHoverMeasure) führt Atlas.Core.Hover.Contract.

interface

uses
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Texts,
  Atlas.Core.Hover.View;

type

  TAtlasHoverInput = record
    View: TAtlasHoverView;
    Width: Integer;
    PPI: Integer;
    Colors: TAtlasColors;
    Texts: TAtlasHoverTexts;
    /// <summary>XMLDoc vorhanden und ihre (begrenzte) Höhe.</summary>
    HasDoc: Boolean;
    DocHeight: Integer;
    /// <summary>Markierung in der Doku: Aktion „Auswahl kopieren“ statt „Deklaration kopieren“.</summary>
    HasSelection: Boolean;
    /// <summary>Aktionszeile unter Regelbefunden (hover.problemActions, #909).</summary>
    ProblemActions: Boolean;
    /// <summary>problems.showCompilerCode aus (#1024): Meldungen ohne „(wie E2035)“, Bestätigung ohne Code.</summary>
    HideCompilerCode: Boolean;
    /// <summary>Link „Beispiel zeigen“ in der Aktionszeile (hover.ruleExamples, #145).</summary>
    RuleExamples: Boolean;
    /// <summary>Rollbereich der published-Mitglieder: Zeilen, Grenze und gewünschter Versatz (#1841).</summary>
    Members: TAtlasHoverScrollRequest;
    /// <summary>Rollbereich der Zeilen des aufgeklappten Debug-Werts (#895).</summary>
    DebugRows: TAtlasHoverScrollRequest;
    /// <summary>Gewählte Zeile des aufgeklappten Debug-Werts, 1-basiert; 0 ohne (#895).</summary>
    DebugSelectedRow: Integer;
  end;

implementation

end.
