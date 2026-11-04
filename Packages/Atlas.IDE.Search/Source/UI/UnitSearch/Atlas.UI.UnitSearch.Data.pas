unit Atlas.UI.UnitSearch.Data;

// Zustand des Fensters „Units suchen“ (#777) ohne Zeichnen: Optionen,
// Einträge, Filter (getippte Chips, Herkunft, Art), Zeilen mit Gruppen,
// Auswahl, Bildlauf, Markierungen, „Unit verwenden“ (#786) und Vorschau.
// TAtlasUnitSearchWindow verarbeitet die Eingaben, TAtlasUnitSearchPainter
// zeichnet aus diesem Zustand.

interface

uses
  System.SysUtils,
  System.Types,
  System.Generics.Collections,
  Atlas.Core.UnitSearch.Model,
  Atlas.Core.UnitSearch.Sections,
  Atlas.Core.UnitSearch.State,
  Atlas.Core.UnitSearch.UseUnit;

type
  TAtlasUnitSearchAction = (Open, OpenForm, AddUses, OpenTests, CopyPaths, ShowProject, ShowExplorer);

  TAtlasUnitSearchOptions = record
    Filters: Boolean;
    FilterSyntax: Boolean;
    Preview: Boolean;
    PreviewForm: Boolean;
    PreviewUsedBy: Boolean;
    /// <summary>Abschnitte einklappen, wenn sie nicht passen (#876).</summary>
    PreviewAutoCollapse: Boolean;
    MultiSelect: Boolean;
    Actions: Boolean;
    AddUses: Boolean;
    RememberCollapsed: Boolean;
    PathStyle: TAtlasUnitPathStyle;
    Grouping: TAtlasUnitGrouping;
    /// <summary>Herkunft ohne gemerkte Wahl (unitSearch.defaultScope).</summary>
    DefaultOrigins: TAtlasUnitOrigins;
    /// <summary>Schlüssel für den gemerkten Zustand (Datei der Projektgruppe).</summary>
    GroupFile: string;
    /// <summary>Bezug für relative Pfade (Ordner der Projektgruppe).</summary>
    Root: string;
    ActiveProject: string;
    /// <summary>Units suchen, Unit verwenden oder Formulare suchen (#786).</summary>
    Mode: TAtlasUnitSearchMode;
    /// <summary>Name der Unit, in die „Unit verwenden“ einfügt; '' ohne.</summary>
    TargetUnit: string;
  end;

  TAtlasUnitSearchActionEvent = reference to procedure(AAction: TAtlasUnitSearchAction;
    const AEntries: TArray<TAtlasUnitEntry>);
  TAtlasUnitSearchPreviewFunc = reference to function(const AEntry: TAtlasUnitEntry): TAtlasUnitPreview;
  TAtlasUnitSearchUseEvent = reference to procedure(const AEntries: TArray<TAtlasUnitEntry>;
    ASection: TAtlasUseUnitSection);

  /// <summary>Ereignisse des Fensters, gesetzt von der IDE-Schicht.</summary>
  TAtlasUnitSearchEvents = record
    OnAction: TAtlasUnitSearchActionEvent;
    OnPreview: TAtlasUnitSearchPreviewFunc;
    OnUse: TAtlasUnitSearchUseEvent;
    OnClosed: TProc;
  end;

  /// <summary>Was an einer Stelle des Fensters liegt (beim Zeichnen gemerkt).</summary>
  TAtlasUnitSearchHit = (None, Chip, Grouping, Row, Action, Splitter, Check, Section, SectionSwitch);

  TAtlasUnitSearchHitArea = record
    Kind: TAtlasUnitSearchHit;
    Rect: TRect;
    Value: Integer;
  end;

  /// <summary>Maße in Pixeln für die Bildschirmauflösung PPI.</summary>
  TAtlasUnitSearchMetrics = record
    PPI: Integer;
    Mode: TAtlasUnitSearchMode;
    Filters: Boolean;
    Actions: Boolean;
    /// <summary>AValue (bei 96 dpi) skaliert.</summary>
    function S(AValue: Integer): Integer;
    function HeaderHeight: Integer;
    function ModeHeight: Integer;
    function ChipHeight: Integer;
    function GroupHeight: Integer;
    function EntryHeight: Integer;
    function FooterHeight: Integer;
    function ActionHeight: Integer;
    function SectionHeadHeight: Integer;
    function SectionGap: Integer;
  end;

  /// <summary>Getippte Filter, Herkunft und Art und das Ergebnis der letzten Anfrage.</summary>
  TAtlasUnitSearchFilter = record
    Pattern: string;
    /// <summary>Getippte Filter, die zu Chips im Feld geworden sind.</summary>
    Typed: TArray<string>;
    Origins: TAtlasUnitOrigins;
    Kinds: TAtlasUnitKinds;
    /// <summary>Anfrage und Herkunft/Art zu Order; engt die nächste sie nur ein, prüft Order nur Order.</summary>
    LastQuery: TAtlasUnitQuery;
    LastOrigins: TAtlasUnitOrigins;
    LastKinds: TAtlasUnitKinds;
    HasLast: Boolean;
    Order: TArray<Integer>;
  end;

  /// <summary>Zeilen der Liste mit Gruppen, Auswahl und Bildlauf.</summary>
  TAtlasUnitSearchList = record
    Loading: Boolean;
    Grouping: TAtlasUnitGrouping;
    Collapsed: TArray<string>;
    Rows: TAtlasUnitRows;
    /// <summary>Oberkante jeder Zeile in Pixeln, ab Listenanfang; ein Eintrag mehr für das Ende.</summary>
    RowTops: TArray<Integer>;
    Selected: Integer;
    Scroll: Integer;
    Rect: TRect;
  end;

  /// <summary>„Unit verwenden“ (#786): uses und Kreise der Zielunit, Marken je Eintrag, gewählter Abschnitt.</summary>
  TAtlasUnitSearchUse = record
    Info: TAtlasUseUnitInfo;
    Marks: TArray<TAtlasUseUnitMark>;
    Section: TAtlasUseUnitSection;
  end;

  /// <summary>Vorschau rechts: sichtbar, Breite (bei 96 dpi), Daten der Unit, Abschnitte beim letzten Zeichnen.
  /// </summary>
  TAtlasUnitSearchPreview = record
    Visible: Boolean;
    Width: Integer;
    Data: TAtlasUnitPreview;
    FileName: string;
    /// <summary>Zustand der Abschnitte beim letzten Zeichnen (#876).</summary>
    Sections: TAtlasSectionStates;
    Rect: TRect;
  end;

  TAtlasUnitSearchData = class
  public
    Options: TAtlasUnitSearchOptions;
    /// <summary>Gehört dem Aufrufer; nimmt Lage und Wahl auf.</summary>
    State: TAtlasUnitSearchState;
    Metrics: TAtlasUnitSearchMetrics;
    Entries: TAtlasUnitEntries;
    Filter: TAtlasUnitSearchFilter;
    List: TAtlasUnitSearchList;
    Marked: TDictionary<string, Boolean>;
    Use: TAtlasUnitSearchUse;
    Preview: TAtlasUnitSearchPreview;
    constructor Create(const AOptions: TAtlasUnitSearchOptions; AState: TAtlasUnitSearchState);
    destructor Destroy; override;
    /// <summary>Anfrage aus getippten Chips und Suchtext.</summary>
    function Query: TAtlasUnitQuery;
    function EntryKey(AIndex: Integer): string;
    /// <summary>Eintrag der gewählten Zeile; False auf einem Gruppenkopf oder ohne Auswahl.</summary>
    function CurrentEntry(out AIndex: Integer): Boolean;
    /// <summary>Markierte in der Reihenfolge der Liste, sonst die aktuelle Zeile.</summary>
    function SelectedEntries: TArray<TAtlasUnitEntry>;
    function UseInUses(AIndex: Integer): Boolean;
    /// <summary>Kreis der Zeile zum Eintrag AIndex im Modus „Unit verwenden“.</summary>
    function UseCycle(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
    /// <summary>Einträge neu filtern und ordnen; AKeepSelection: auf derselben Unit bleiben.</summary>
    procedure Refilter(AKeepSelection: Boolean);
    procedure RebuildRows;
    /// <summary>Zeile ARow (begrenzt) wählen und zeigen; False ohne Zeilen.</summary>
    function Select(ARow: Integer): Boolean;
    /// <summary>Bildlauf so, dass die gewählte Zeile sichtbar ist.</summary>
    procedure EnsureVisible;
    /// <summary>Bildlauf um ADelta Pixel.</summary>
    procedure ScrollBy(ADelta: Integer);
    /// <summary>Gruppe der Zeile ARow ein- oder ausklappen und auf ihrem Kopf bleiben; False ohne Gruppen.</summary>
    function ToggleGroup(ARow: Integer; ACollapse: Boolean): Boolean;
    /// <summary>Gruppe der gewählten Zeile klappen; False ohne Auswahl.</summary>
    function ToggleSelectedGroup(ACollapse: Boolean): Boolean;
    function ToggleMark(ARow: Integer): Boolean;
    /// <summary>Alle markieren; sind schon alle markiert, Markierung aufheben. False ohne Mehrfachauswahl.</summary>
    function MarkAll: Boolean;
    /// <summary>Chip AValue (TAtlasUnitSearchChip) umschalten bzw. getippten Filter entfernen.</summary>
    procedure ChipClicked(AValue: Integer);
    /// <summary>Fertig getippter Filter am Ende des Suchtexts wird zum Chip; False ohne.</summary>
    function CommitTypedFilter: Boolean;
    /// <summary>Rücktaste: letztes Zeichen (AWord: ganzen Suchtext) bzw. letzten Chip entfernen; False ohne.</summary>
    function RemoveLast(AWord: Boolean): Boolean;
    procedure SetEntries(const AEntries: TAtlasUnitEntries);
    procedure SetUseInfo(const AInfo: TAtlasUseUnitInfo);
    /// <summary>interface / implementation umschalten; False außerhalb von „Unit verwenden“.</summary>
    function ToggleUseSection: Boolean;
    /// <summary>Gruppierung wechseln, eingeklappte Gruppen je Gruppierung merken; False ohne Wechsel.</summary>
    function SetGrouping(AGrouping: TAtlasUnitGrouping): Boolean;
    /// <summary>Lage, Vorschau, Filter und eingeklappte Gruppen in State schreiben.</summary>
    procedure SaveState(const ABounds: TRect);
    /// <summary>Liste und Vorschau in der Client-Fläche AWidth x AHeight anordnen.</summary>
    procedure Layout(AWidth, AHeight: Integer);
  end;

const
  /// <summary>Werte der Chips: Herkunft, Art und getippte Filter (Index ab ChipTyped).</summary>
  cChipOrigins = 0;
  cChipKinds = 100;
  cChipTyped = 200;

implementation

uses
  System.Math;

{ TAtlasUnitSearchMetrics }

function TAtlasUnitSearchMetrics.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, PPI, 96);
end;

function TAtlasUnitSearchMetrics.HeaderHeight: Integer;
begin
  Result := S(44);
end;

function TAtlasUnitSearchMetrics.ModeHeight: Integer;
begin
  Result := 0;
  if Mode <> TAtlasUnitSearchMode.Search then
  begin
    Result := S(30);
  end;
end;

function TAtlasUnitSearchMetrics.ChipHeight: Integer;
begin
  Result := 0;
  if Filters then
  begin
    Result := S(32);
  end;
end;

function TAtlasUnitSearchMetrics.GroupHeight: Integer;
begin
  Result := S(24);
end;

function TAtlasUnitSearchMetrics.EntryHeight: Integer;
begin
  Result := S(40);
end;

function TAtlasUnitSearchMetrics.FooterHeight: Integer;
begin
  Result := S(24);
end;

function TAtlasUnitSearchMetrics.ActionHeight: Integer;
begin
  Result := 0;
  if Actions then
  begin
    Result := S(34);
  end;
end;

function TAtlasUnitSearchMetrics.SectionHeadHeight: Integer;
begin
  Result := S(20);
end;

function TAtlasUnitSearchMetrics.SectionGap: Integer;
begin
  Result := S(6);
end;

{ TAtlasUnitSearchData }

constructor TAtlasUnitSearchData.Create(const AOptions: TAtlasUnitSearchOptions; AState: TAtlasUnitSearchState);
var
  mOrigins: TAtlasUnitOrigins;
  mKinds: TAtlasUnitKinds;
begin
  inherited Create;
  Options := AOptions;
  State := AState;
  Marked := TDictionary<string, Boolean>.Create;
  Metrics.PPI := 96;
  Metrics.Mode := AOptions.Mode;
  Metrics.Filters := AOptions.Filters;
  Metrics.Actions := AOptions.Actions;
  List.Loading := True;
  List.Grouping := AOptions.Grouping;
  List.Selected := -1;
  // Wie im Dialog der IDE: Vorgabe implementation.
  Use.Section := TAtlasUseUnitSection.Implementation_;
  // Formulare suchen: gesetzter, entfernbarer Filter; ohne Tippsyntax legt Refilter die Arten fest.
  if (AOptions.Mode = TAtlasUnitSearchMode.Forms) and AOptions.FilterSyntax then
  begin
    Filter.Typed := TArray<string>.Create(TAtlasUseUnit.FormsFilter);
  end;
  Filter.Origins := AOptions.DefaultOrigins;
  if AOptions.Filters and AState.Filters(AOptions.GroupFile, mOrigins, mKinds) and (mOrigins <> []) then
  begin
    Filter.Origins := mOrigins;
    Filter.Kinds := mKinds;
  end;
  if AOptions.RememberCollapsed then
  begin
    List.Collapsed := AState.Collapsed(AOptions.GroupFile, List.Grouping);
  end;
  Preview.Visible := AOptions.Preview and AState.PreviewVisible;
  Preview.Width := AState.PreviewWidth;
  if Preview.Width <= 0 then
  begin
    Preview.Width := 340;
  end;
end;

destructor TAtlasUnitSearchData.Destroy;
begin
  Marked.Free;
  inherited Destroy;
end;

function TAtlasUnitSearchData.Query: TAtlasUnitQuery;
begin
  Result := TAtlasUnitQuery.Parse(string.Join(' ', Filter.Typed) + ' ' + Filter.Pattern, Options.FilterSyntax);
end;

function TAtlasUnitSearchData.EntryKey(AIndex: Integer): string;
begin
  Result := LowerCase(Entries[AIndex].FileName);
end;

function TAtlasUnitSearchData.CurrentEntry(out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  Result := (List.Selected >= 0) and (List.Selected <= High(List.Rows)) and not List.Rows[List.Selected].IsGroup;
  if Result then
  begin
    AIndex := List.Rows[List.Selected].Entry;
  end;
end;

function TAtlasUnitSearchData.SelectedEntries: TArray<TAtlasUnitEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  if Options.MultiSelect and (Marked.Count > 0) then
  begin
    for mIndex in Filter.Order do
    begin
      if Marked.ContainsKey(EntryKey(mIndex)) then
      begin
        Result := Result + [Entries[mIndex]];
      end;
    end;
  end;
  if (Length(Result) = 0) and CurrentEntry(mIndex) then
  begin
    Result := TArray<TAtlasUnitEntry>.Create(Entries[mIndex]);
  end;
end;

function TAtlasUnitSearchData.UseInUses(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Use.Marks)) and Use.Marks[AIndex].InUses;
end;

function TAtlasUnitSearchData.UseCycle(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
begin
  ACycle := Default(TAtlasUseUnitCycle);
  Result := (AIndex >= 0) and (AIndex <= High(Use.Marks)) and (Use.Marks[AIndex].Cycle >= 0) and
    not Use.Marks[AIndex].InUses;
  if Result then
  begin
    ACycle := Use.Info.Cycles[Use.Marks[AIndex].Cycle];
  end;
end;

/// <summary>Herkunft und Art, nach denen gefiltert wird.</summary>
procedure ActiveFilters(const AOptions: TAtlasUnitSearchOptions; const AFilter: TAtlasUnitSearchFilter;
  out AOrigins: TAtlasUnitOrigins; out AKinds: TAtlasUnitKinds);
begin
  AKinds := [];
  AOrigins := AOptions.DefaultOrigins;
  if AOptions.Filters then
  begin
    AKinds := AFilter.Kinds;
    AOrigins := AFilter.Origins;
  end;
  // Formulare suchen ohne Tippsyntax: nur Formulare, Frames und Datenmodule (#786).
  if (AOptions.Mode = TAtlasUnitSearchMode.Forms) and not AOptions.FilterSyntax then
  begin
    AKinds := AKinds * TAtlasUseUnit.FormKinds;
    if AKinds = [] then
    begin
      AKinds := TAtlasUseUnit.FormKinds;
    end;
  end;
end;

/// <summary>Erste Zeile, die keine Gruppe ist; sonst 0 bzw. -1 ohne Zeilen.</summary>
function FirstEntryRow(const ARows: TAtlasUnitRows): Integer;
var
  mIndex: Integer;
begin
  Result := Min(0, High(ARows));
  for mIndex := 0 to High(ARows) do
  begin
    if not ARows[mIndex].IsGroup then
    begin
      Exit(mIndex);
    end;
  end;
end;

procedure TAtlasUnitSearchData.Refilter(AKeepSelection: Boolean);
var
  mCurrent: string;
  mIndex: Integer;
  mKinds: TAtlasUnitKinds;
  mOrigins: TAtlasUnitOrigins;
  mQuery: TAtlasUnitQuery;
begin
  mCurrent := '';
  if AKeepSelection and CurrentEntry(mIndex) then
  begin
    mCurrent := EntryKey(mIndex);
  end;
  ActiveFilters(Options, Filter, mOrigins, mKinds);
  mQuery := Query;
  // Beim Weitertippen nur die bisherigen Treffer prüfen (#777: unter 50 ms je Taste bei 5000 Units).
  if Filter.HasLast and (mOrigins = Filter.LastOrigins) and (mKinds = Filter.LastKinds) and
    mQuery.Narrows(Filter.LastQuery) then
  begin
    Filter.Order := TAtlasUnitSearch.Order(Entries, mQuery, mOrigins, mKinds, Filter.Order);
  end
  else
  begin
    Filter.Order := TAtlasUnitSearch.Order(Entries, mQuery, mOrigins, mKinds);
  end;
  Filter.LastQuery := mQuery;
  Filter.LastOrigins := mOrigins;
  Filter.LastKinds := mKinds;
  Filter.HasLast := True;
  RebuildRows;
  List.Selected := -1;
  for mIndex := 0 to High(List.Rows) do
  begin
    if (mCurrent <> '') and not List.Rows[mIndex].IsGroup and (EntryKey(List.Rows[mIndex].Entry) = mCurrent) then
    begin
      List.Selected := mIndex;
      Break;
    end;
  end;
  if List.Selected < 0 then
  begin
    List.Scroll := 0;
    // Erste Unit wählen, nicht den Kopf.
    List.Selected := FirstEntryRow(List.Rows);
  end;
  EnsureVisible;
end;

procedure TAtlasUnitSearchData.RebuildRows;
var
  mIndex, mTop: Integer;
begin
  List.Rows := TAtlasUnitSearch.Rows(Entries, Filter.Order, TAtlasUnitLayout.Create(List.Grouping, Options.Root,
    Options.ActiveProject, List.Collapsed, Query.HasWords));
  SetLength(List.RowTops, Length(List.Rows) + 1);
  mTop := 0;
  for mIndex := 0 to High(List.Rows) do
  begin
    List.RowTops[mIndex] := mTop;
    if List.Rows[mIndex].IsGroup then
    begin
      Inc(mTop, Metrics.GroupHeight);
    end
    else
    begin
      Inc(mTop, Metrics.EntryHeight);
    end;
  end;
  List.RowTops[Length(List.Rows)] := mTop;
end;

function TAtlasUnitSearchData.Select(ARow: Integer): Boolean;
begin
  Result := Length(List.Rows) > 0;
  if Result then
  begin
    List.Selected := EnsureRange(ARow, 0, High(List.Rows));
    EnsureVisible;
  end;
end;

/// <summary>Größter Bildlauf: Gesamthöhe der Zeilen minus sichtbare Höhe.</summary>
function MaxScroll(const AList: TAtlasUnitSearchList): Integer;
begin
  Result := 0;
  if Length(AList.RowTops) > 0 then
  begin
    Result := Max(0, AList.RowTops[High(AList.RowTops)] - AList.Rect.Height);
  end;
end;

procedure TAtlasUnitSearchData.EnsureVisible;
begin
  if (List.Selected < 0) or (List.Selected > High(List.Rows)) then
  begin
    Exit;
  end;
  if List.RowTops[List.Selected] < List.Scroll then
  begin
    List.Scroll := List.RowTops[List.Selected];
  end
  else if List.RowTops[List.Selected + 1] > List.Scroll + List.Rect.Height then
  begin
    List.Scroll := List.RowTops[List.Selected + 1] - List.Rect.Height;
  end;
  List.Scroll := EnsureRange(List.Scroll, 0, MaxScroll(List));
end;

procedure TAtlasUnitSearchData.ScrollBy(ADelta: Integer);
begin
  List.Scroll := EnsureRange(List.Scroll + ADelta, 0, MaxScroll(List));
end;

/// <summary>AItems ohne AKey, mit AAdd am Ende wieder dabei.</summary>
function WithoutKey(const AItems: TArray<string>; const AKey: string; AAdd: Boolean): TArray<string>;
var
  mItem: string;
begin
  Result := nil;
  for mItem in AItems do
  begin
    if mItem <> AKey then
    begin
      Result := Result + [mItem];
    end;
  end;
  if AAdd then
  begin
    Result := Result + [AKey];
  end;
end;

function TAtlasUnitSearchData.ToggleGroup(ARow: Integer; ACollapse: Boolean): Boolean;
var
  mKey: string;
  mIndex: Integer;
begin
  Result := (ARow >= 0) and (ARow <= High(List.Rows)) and (List.Grouping <> TAtlasUnitGrouping.None);
  if not Result then
  begin
    Exit;
  end;
  mKey := LowerCase(List.Rows[ARow].Group);
  List.Collapsed := WithoutKey(List.Collapsed, mKey, ACollapse);
  RebuildRows;
  // Auf dem Kopf der Gruppe bleiben.
  for mIndex := 0 to High(List.Rows) do
  begin
    if List.Rows[mIndex].IsGroup and SameText(List.Rows[mIndex].Group, mKey) then
    begin
      List.Selected := mIndex;
      Break;
    end;
  end;
  EnsureVisible;
end;

function TAtlasUnitSearchData.ToggleSelectedGroup(ACollapse: Boolean): Boolean;
var
  mIndex: Integer;
begin
  Result := (List.Selected >= 0) and (List.Selected <= High(List.Rows));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := List.Selected downto 0 do
  begin
    if List.Rows[mIndex].IsGroup then
    begin
      ToggleGroup(mIndex, ACollapse);
      Break;
    end;
  end;
end;

function TAtlasUnitSearchData.ToggleMark(ARow: Integer): Boolean;
var
  mKey: string;
begin
  Result := Options.MultiSelect and (ARow >= 0) and (ARow <= High(List.Rows)) and not List.Rows[ARow].IsGroup;
  if not Result then
  begin
    Exit;
  end;
  mKey := EntryKey(List.Rows[ARow].Entry);
  if Marked.ContainsKey(mKey) then
  begin
    Marked.Remove(mKey);
  end
  else
  begin
    Marked.Add(mKey, True);
  end;
end;

function TAtlasUnitSearchData.MarkAll: Boolean;
var
  mIndex: Integer;
  mAll: Boolean;
begin
  Result := Options.MultiSelect;
  if not Result then
  begin
    Exit;
  end;
  mAll := Marked.Count > 0;
  for mIndex in Filter.Order do
  begin
    mAll := mAll and Marked.ContainsKey(EntryKey(mIndex));
  end;
  Marked.Clear;
  for mIndex in Filter.Order do
  begin
    if not mAll then
    begin
      Marked.AddOrSetValue(EntryKey(mIndex), True);
    end;
  end;
end;

procedure TAtlasUnitSearchData.ChipClicked(AValue: Integer);
var
  mOrigin: TAtlasUnitOrigin;
  mKind: TAtlasUnitKind;
begin
  if AValue >= cChipTyped then
  begin
    Delete(Filter.Typed, AValue - cChipTyped, 1);
  end
  else if AValue >= cChipKinds then
  begin
    mKind := TAtlasUnitKind(AValue - cChipKinds);
    if mKind in Filter.Kinds then
    begin
      Exclude(Filter.Kinds, mKind);
    end
    else
    begin
      Include(Filter.Kinds, mKind);
    end;
  end
  else
  begin
    mOrigin := TAtlasUnitOrigin(AValue - cChipOrigins);
    // Mindestens eine Herkunft bleibt gewählt.
    if not (mOrigin in Filter.Origins) then
    begin
      Include(Filter.Origins, mOrigin);
    end
    else if Filter.Origins - [mOrigin] <> [] then
    begin
      Exclude(Filter.Origins, mOrigin);
    end;
  end;
end;

function TAtlasUnitSearchData.CommitTypedFilter: Boolean;
var
  mWords: TArray<string>;
  mLast: string;
begin
  mWords := Filter.Pattern.Split([' '], TStringSplitOptions.ExcludeEmpty);
  mLast := '';
  if Length(mWords) > 0 then
  begin
    mLast := mWords[High(mWords)];
  end;
  Result := Options.FilterSyntax and (mLast <> '') and Filter.Pattern.EndsWith(mLast) and
    TAtlasUnitQuery.IsFilter(mLast);
  if Result then
  begin
    Filter.Typed := Filter.Typed + [mLast];
    Filter.Pattern := TrimRight(Copy(Filter.Pattern, 1, Length(Filter.Pattern) - Length(mLast)));
  end;
end;

function TAtlasUnitSearchData.RemoveLast(AWord: Boolean): Boolean;
begin
  Result := True;
  if (Filter.Pattern <> '') and AWord then
  begin
    Filter.Pattern := '';
  end
  else if Filter.Pattern <> '' then
  begin
    Delete(Filter.Pattern, Length(Filter.Pattern), 1);
  end
  else if Length(Filter.Typed) > 0 then
  begin
    SetLength(Filter.Typed, Length(Filter.Typed) - 1);
  end
  else
  begin
    Result := False;
  end;
end;

procedure TAtlasUnitSearchData.SetEntries(const AEntries: TAtlasUnitEntries);
begin
  Entries := AEntries;
  // Gleichstände löst Order über die Reihenfolge auf: einmal nach Name sortieren.
  TAtlasUnitSearch.SortByName(Entries);
  List.Loading := False;
  Filter.HasLast := False;
  SetUseInfo(Use.Info);
end;

procedure TAtlasUnitSearchData.SetUseInfo(const AInfo: TAtlasUseUnitInfo);
begin
  Use.Info := AInfo;
  Use.Marks := nil;
  if Options.Mode = TAtlasUnitSearchMode.UseUnit then
  begin
    Use.Marks := TAtlasUseUnit.Marks(Use.Info, Entries);
  end;
end;

function TAtlasUnitSearchData.ToggleUseSection: Boolean;
begin
  Result := Options.Mode = TAtlasUnitSearchMode.UseUnit;
  if not Result then
  begin
    Exit;
  end;
  if Use.Section = TAtlasUseUnitSection.Interface_ then
  begin
    Use.Section := TAtlasUseUnitSection.Implementation_;
  end
  else
  begin
    Use.Section := TAtlasUseUnitSection.Interface_;
  end;
end;

function TAtlasUnitSearchData.SetGrouping(AGrouping: TAtlasUnitGrouping): Boolean;
begin
  Result := AGrouping <> List.Grouping;
  if not Result then
  begin
    Exit;
  end;
  if Options.RememberCollapsed then
  begin
    State.SetCollapsed(Options.GroupFile, List.Grouping, List.Collapsed);
  end;
  List.Grouping := AGrouping;
  List.Collapsed := nil;
  if Options.RememberCollapsed then
  begin
    List.Collapsed := State.Collapsed(Options.GroupFile, List.Grouping);
  end;
end;

procedure TAtlasUnitSearchData.SaveState(const ABounds: TRect);
begin
  State.Left := ABounds.Left;
  State.Top := ABounds.Top;
  State.Width := ABounds.Width;
  State.Height := ABounds.Height;
  State.PreviewWidth := Preview.Width;
  if Options.Preview then
  begin
    State.PreviewVisible := Preview.Visible;
  end;
  if Options.Filters then
  begin
    State.SetFilters(Options.GroupFile, Filter.Origins, Filter.Kinds);
  end;
  if Options.RememberCollapsed then
  begin
    State.SetCollapsed(Options.GroupFile, List.Grouping, List.Collapsed);
  end;
end;

procedure TAtlasUnitSearchData.Layout(AWidth, AHeight: Integer);
var
  mBody: TRect;
begin
  mBody := Rect(0, Metrics.HeaderHeight + Metrics.ModeHeight + Metrics.ChipHeight, AWidth,
    AHeight - Metrics.FooterHeight - Metrics.ActionHeight);
  Preview.Rect := Rect(0, 0, 0, 0);
  if Preview.Visible then
  begin
    Preview.Width := EnsureRange(Preview.Width, 200, Max(200, MulDiv(AWidth, 96, Metrics.PPI) - 300));
    Preview.Rect := Rect(mBody.Right - Metrics.S(Preview.Width), mBody.Top, mBody.Right, mBody.Bottom);
    mBody.Right := Preview.Rect.Left;
  end;
  List.Rect := mBody;
end;

end.
