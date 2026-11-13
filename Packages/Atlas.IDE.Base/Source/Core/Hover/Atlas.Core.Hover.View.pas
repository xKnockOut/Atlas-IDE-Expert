unit Atlas.Core.Hover.View;

// Inhalt des Hover-Tooltips ohne VCL: was er zeigt (TAtlasHoverView), die
// Schalter der published-Mitglieder (#110), die Aktionen unter Problemen
// (#621, #896) und die Erklärungen zu Compilermeldungen (#54). Den Satz
// rechnet Atlas.Core.Hover.Layout.
// Beispiele aus dem Regelkatalog (#145): Examples hat je Problem den Katalogtext;
// ist seine Id gesetzt, zeigt der Satz Beschreibung und Beispiel falsch/richtig
// über der Aktionszeile und der Link heißt „Beispiel ausblenden“.

interface

uses
  Atlas.Core.Hover.Contract,
  Atlas.Core.Hover.History,
  Atlas.Core.Problems.Contract,
  Atlas.Core.Problems.Explanation,
  Atlas.Core.Documentation.Contract,
  Atlas.Core.Hover.DebugValue;

type
  {$SCOPEDENUMS ON}
  TAtlasHoverAction = (Navigate, Usages, Copy, Help);
  /// <summary>Schalter der published-Mitglieder (#110): geerbte zeigen, nur mit Vorgabe, Abschnitte zu- bzw.
  /// aufklappen, alle Zeilen zeigen.</summary>
  TAtlasHoverPublishedToggle = (ShowInherited, OnlyDefaults, Properties, Events, MoreProperties, MoreEvents);
  /// <summary>Aktion unter einem Problem im Tooltip (#621). Related: Sprung zu einer weiteren Stelle (#896),
  /// ShowGraph: Unit-Beziehungen zeigen (#896), Explain: Erklärung im Dialog, DocWiki: Seite im Browser (#54),
  /// Example: Beschreibung und Beispiel auf- bzw. zuklappen (#145), Compare: erwartet und erhalten eines
  /// fehlgeschlagenen Tests vergleichen (#1779).</summary>
  TAtlasHoverProblemAction = (RemoveUses, RemoveAllUses, MoveUses, Fix, SuppressLine, Configure, Related, ShowGraph,
    Explain, DocWiki, Example, Compare);
  {$SCOPEDENUMS OFF}

  /// <summary>Index der Klickfläche ProblemAction (#621): Problem in View.Problems, Aktion und Stelle AItem in
  /// Problem.Related (Aktion Related, #896; 0 bis cMaxRelated - 1).</summary>
  TAtlasHoverProblemActionCode = record
  public
    const
      /// <summary>Höchstens so viele weitere Stellen je Problem im Hover (#896).</summary>
      cMaxRelated = 64;
    class function Encode(AProblem: Integer; AAction: TAtlasHoverProblemAction; AItem: Integer): Integer; overload;
      static;
    class function Encode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer; overload; static;
    class procedure Decode(ACode: Integer; out AProblem: Integer; out AAction: TAtlasHoverProblemAction;
      out AItem: Integer); overload; static;
    class procedure Decode(ACode: Integer; out AProblem: Integer; out AAction: TAtlasHoverProblemAction); overload;
      static;
  end;

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
    /// <summary>Katalogtext je Problem (#145), gleicher Index wie Problems; aufgeklappt, wenn Id gesetzt ist.
    /// </summary>
    Examples: TArray<TAtlasRuleExplanation>;
    /// <summary>Je Problem: fehlgeschlagener Test mit erwartetem und erhaltenem Wert (#1779), gleicher Index wie
    /// Problems; nil ohne.</summary>
    Comparisons: TArray<Boolean>;
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
    /// <summary>Ist Beschreibung und Beispiel unter Problem AProblem aufgeklappt (#145)?</summary>
    function ExampleShown(AProblem: Integer): Boolean;
    /// <summary>Lässt sich unter Problem AProblem erwartet und erhalten vergleichen (#1779)?</summary>
    function CanCompare(AProblem: Integer): Boolean;
    /// <summary>Reihenfolge der Probleme im Hover (Indizes in Problems): Fehler zuerst, sonst wie geliefert (#909).
    /// </summary>
    function ProblemOrder: TArray<Integer>;
  end;

implementation

{ TAtlasHoverProblemActionCode }

class function TAtlasHoverProblemActionCode.Encode(AProblem: Integer; AAction: TAtlasHoverProblemAction;
  AItem: Integer): Integer;
begin
  Result := (AProblem * cMaxRelated + AItem) * (Ord(High(TAtlasHoverProblemAction)) + 1) + Ord(AAction);
end;

class function TAtlasHoverProblemActionCode.Encode(AProblem: Integer; AAction: TAtlasHoverProblemAction): Integer;
begin
  Result := Encode(AProblem, AAction, 0);
end;

class procedure TAtlasHoverProblemActionCode.Decode(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction; out AItem: Integer);
var
  mRest: Integer;
begin
  AAction := TAtlasHoverProblemAction(ACode mod (Ord(High(TAtlasHoverProblemAction)) + 1));
  mRest := ACode div (Ord(High(TAtlasHoverProblemAction)) + 1);
  AProblem := mRest div cMaxRelated;
  AItem := mRest mod cMaxRelated;
end;

class procedure TAtlasHoverProblemActionCode.Decode(ACode: Integer; out AProblem: Integer;
  out AAction: TAtlasHoverProblemAction);
var
  mItem: Integer;
begin
  Decode(ACode, AProblem, AAction, mItem);
end;

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

function TAtlasHoverView.ExampleShown(AProblem: Integer): Boolean;
begin
  Result := (AProblem >= 0) and (AProblem <= High(Examples)) and (AProblem <= High(Problems)) and
    (Examples[AProblem].Id <> '');
end;

function TAtlasHoverView.CanCompare(AProblem: Integer): Boolean;
begin
  Result := (AProblem >= 0) and (AProblem <= High(Comparisons)) and (AProblem <= High(Problems)) and
    Comparisons[AProblem];
end;

function TAtlasHoverView.ProblemOrder: TArray<Integer>;
var
  mIndex, mCount: Integer;
begin
  // Fehler zuerst, die übrigen in ihrer Reihenfolge (stabil).
  Result := nil;
  SetLength(Result, Length(Problems));
  mCount := 0;
  for mIndex := 0 to High(Problems) do
  begin
    if Problems[mIndex].Severity = TAtlasProblemSeverity.Error then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
  for mIndex := 0 to High(Problems) do
  begin
    if Problems[mIndex].Severity <> TAtlasProblemSeverity.Error then
    begin
      Result[mCount] := mIndex;
      Inc(mCount);
    end;
  end;
end;

end.
