unit Atlas.Core.Hover.View;

// Inhalt des Hover-Tooltips ohne VCL: was er zeigt (TAtlasHoverView), die
// Schalter der published-Mitglieder (#110), die Aktionen unter Problemen
// (#621, #896) und die Erklärungen zu Compilermeldungen (#54). Den Satz
// rechnet Atlas.Core.Hover.Layout.

interface

uses
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.DebugValue;

type
  {$SCOPEDENUMS ON}
  TAtlasHoverAction = (Navigate, Usages, Copy, Help);
  /// <summary>Schalter der published-Mitglieder (#110): geerbte zeigen, nur mit Vorgabe, Abschnitte zu- bzw.
  /// aufklappen, alle Zeilen zeigen.</summary>
  TAtlasHoverPublishedToggle = (ShowInherited, OnlyDefaults, Properties, Events, MoreProperties, MoreEvents);
  /// <summary>Aktion unter einem Problem im Tooltip (#621). Related: Sprung zu einer weiteren Stelle (#896),
  /// ShowGraph: Unit-Beziehungen zeigen (#896), Explain: Erklärung im Dialog, DocWiki: Seite im Browser (#54).
  /// </summary>
  TAtlasHoverProblemAction = (RemoveUses, RemoveAllUses, MoveUses, Fix, SuppressLine, Configure, Related, ShowGraph,
    Explain, DocWiki);
  {$SCOPEDENUMS OFF}

  /// <summary>Erklärung eines Problems aus dem Katalog (#54).</summary>
  TAtlasHoverExplanation = record
    /// <summary>Es gibt einen Katalogeintrag: Link „Erklären“.</summary>
    Known: Boolean;
    /// <summary>Typische Ursache einer Compilermeldung; '' ohne.</summary>
    Cause: string;
    /// <summary>Link ins DocWiki; '' ohne.</summary>
    DocWiki: string;
  end;

  /// <summary>Was der Tooltip zeigt: Inhalt, Pfad und Zustand.</summary>
  TAtlasHoverView = record
    Data: TAtlasHoverData;
    Path: TArray<TAtlasHoverPathItem>;
    Pinned: Boolean;
    CanGoBack: Boolean;
    /// <summary>Anzahl der Verwendungen, wenn bekannt; sonst -1.</summary>
    UsagesCount: Integer;
    /// <summary>Probleme an der Mausposition (#398).</summary>
    Problems: TArray<TAtlasProblem>;
    /// <summary>Erklärungen in der Reihenfolge von Problems (#54); nil ohne (hover.explainMessages aus).</summary>
    Explanations: TArray<TAtlasHoverExplanation>;
    /// <summary>Wert des Ausdrucks unter der Maus im angehaltenen Debugger (#891).</summary>
    DebugValue: TAtlasDebugValue;
    /// <summary>Anzeige der XMLDoc (#654): Angabe des Servers bzw. Einstellungen des Plugins.</summary>
    Display: TAtlasDocDisplay;
    /// <summary>published-Mitglieder (#110): geerbte ausblenden, nur Properties mit Vorgabe, Abschnitte
    /// zugeklappt, alle Zeilen statt der ersten.</summary>
    HideInherited: Boolean;
    OnlyDefaults: Boolean;
    PropertiesCollapsed: Boolean;
    EventsCollapsed: Boolean;
    AllProperties: Boolean;
    AllEvents: Boolean;
    class function Create(const AData: TAtlasHoverData): TAtlasHoverView; static;
    /// <summary>Schaltet den Schalter AToggle der published-Mitglieder um (#110).</summary>
    procedure Toggle(AToggle: TAtlasHoverPublishedToggle);
  end;

implementation

{ TAtlasHoverView }

class function TAtlasHoverView.Create(const AData: TAtlasHoverData): TAtlasHoverView;
begin
  Result := Default(TAtlasHoverView);
  Result.Data := AData;
  Result.UsagesCount := -1;
  Result.Display := TAtlasDocDisplay.Create(TAtlasDocExpand.Last, 0);
end;

procedure TAtlasHoverView.Toggle(AToggle: TAtlasHoverPublishedToggle);
begin
  case AToggle of
    TAtlasHoverPublishedToggle.ShowInherited: HideInherited := not HideInherited;
    TAtlasHoverPublishedToggle.OnlyDefaults: OnlyDefaults := not OnlyDefaults;
    TAtlasHoverPublishedToggle.Properties: PropertiesCollapsed := not PropertiesCollapsed;
    TAtlasHoverPublishedToggle.Events: EventsCollapsed := not EventsCollapsed;
    TAtlasHoverPublishedToggle.MoreProperties: AllProperties := not AllProperties;
    TAtlasHoverPublishedToggle.MoreEvents: AllEvents := not AllEvents;
  end;
end;

end.
