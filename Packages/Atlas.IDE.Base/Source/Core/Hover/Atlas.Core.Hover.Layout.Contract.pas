unit Atlas.Core.Hover.Layout.Contract;

// Eingabe des Hover-Satzes: Inhalt, Breite, Farben, Texte und Schalter, dazu der Mess-Rückruf der Oberfläche.
// Den Satz rechnet Atlas.Core.Hover.Layout.

interface

uses
  System.Types,
  Atlas.Core.Style.Palette,
  Atlas.Core.Hover.Items,
  Atlas.Core.Hover.Texts,
  Atlas.Core.Hover.View;

type
  /// <summary>Messen in der Oberfläche; Build ruft nur diese Funktionen.</summary>
  IAtlasHoverMeasure = interface
    ['{96C7EBD2-5C83-4DC6-8E88-88DB86BCD6D5}']
    function TextWidth(const AFace: TAtlasHoverFace; const AText: string): Integer;
    /// <summary>Zeilenhöhe der Schrift (Höhe von „Wg“).</summary>
    function TextHeight(const AFace: TAtlasHoverFace): Integer;
    /// <summary>Höhe von AText in der UI-Schrift, umbrochen an Wortgrenzen auf AWidth.</summary>
    function BlockHeight(const AText: string; AWidth: Integer): Integer;
    /// <summary>Breite der eingefärbten Deklaration [AFrom, ATill) in der Editorschrift.</summary>
    function DeclarationWidth(AFrom, ATill: Integer): Integer;
    /// <summary>Zeilen der eingefärbten Deklaration bei Umbruch an Leerzeichen.</summary>
    function DeclarationLines(AWidth, AIndent: Integer): TArray<TPoint>;
  end;

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
