unit Atlas.Core.Hover.Texts;

// Texte des Hover-Tooltips: Das Fenster (Atlas.UI.Hover.Tip) füllt sie
// aus Atlas.UI.Strings, der Satz (Atlas.Core.Hover.Layout) liest sie nur.

interface

type
  /// <summary>Texte der Oberfläche in ihrer Sprache (Core kennt Atlas.UI.Strings nicht).</summary>
  TAtlasHoverTexts = record
    /// <summary>Art zu View.Data.Kind (Klasse, Methode …); '' wenn unbekannt.</summary>
    KindCaption: string;
    Pinned: string;
    Inheritance: string;
    /// <summary>Format mit %s für den Typ der Kette.</summary>
    TargetType: string;
    /// <summary>Format mit %s für den Titel.</summary>
    Navigate: string;
    Usages: string;
    /// <summary>Format mit %d für die Anzahl.</summary>
    UsagesCount: string;
    Copy: string;
    CopySelection: string;
    Help: string;
    KeyUsages: string;
    KeyCopy: string;
    SourceAtlas: string;
    SourceCompiler: string;
    SourceInactive: string;
    /// <summary>Herkunft eines uses-Hinweises und seine Aktionen (#621).</summary>
    SourceUses: string;
    UsesRemove: string;
    UsesRemoveAll: string;
    UsesMove: string;
    /// <summary>„Graph zeigen“ unter einem Unit-Zyklus (#896); '' = kein Link.</summary>
    ShowGraph: string;
    /// <summary>Befund-Hover (#909): Pillen je Art und die Aktionen unterdrücken und einstellen.</summary>
    KindError: string;
    KindWarning: string;
    KindInfo: string;
    Suppress: string;
    Configure: string;
    Stale: string;
    /// <summary>Zusatz eines vom Build bestätigten Befunds (#1024): „vom Compiler bestätigt“; mit Code
    /// „vom Compiler bestätigt (%s)“.</summary>
    Confirmed: string;
    ConfirmedCode: string;
    /// <summary>Statt des Werts, solange der Debugger noch auswertet (#891).</summary>
    DebugPending: string;
    /// <summary>„kein Zugriff“ (#840): solange die Ursache ermittelt wird, Überschrift der geprüften Punkte.
    /// </summary>
    DebugExplaining: string;
    DebugChecked: string;
    /// <summary>Neu zugewiesene Variablen (#712): „Einmal neu zugewiesen (Zeile %s)“ und
    /// „Neu zugewiesen: %d Zuweisungen (Zeilen %s)“.</summary>
    ReassignedOne: string;
    ReassignedCount: string;
    /// <summary>published-Mitglieder (#110): Format mit %d, %d für Properties und Ereignisse; Schalter,
    /// Abschnitte, Spaltenköpfe, Formate „+ %d weitere …“, Hinweise und „Liste kopieren“.</summary>
    PublishedSummary: string;
    PublishedInherited: string;
    PublishedOnlyDefaults: string;
    PublishedProperties: string;
    PublishedEvents: string;
    PublishedName: string;
    PublishedType: string;
    PublishedDefault: string;
    PublishedDeclared: string;
    PublishedImplicit: string;
    PublishedMoreProperties: string;
    PublishedMoreEvents: string;
    PublishedEventsNote: string;
    PublishedArrayProperty: string;
    PublishedDefaultProperty: string;
    PublishedDefaultPropertyNote: string;
    PublishedCopyList: string;
    PublishedVclNote: string;
    /// <summary>Zeile „Konfidenz: …“ je Problem in der Reihenfolge von View.Problems; '' ohne (auch bei hoher
    /// Konfidenz, #909).</summary>
    Confidences: TArray<string>;
  end;

implementation

end.
