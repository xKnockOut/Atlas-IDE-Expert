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
  TAtlasUnitSearchFilter = class
  private
    FSyntax: Boolean;
    FPattern: string;
    FTyped: TArray<string>;
    FOrigins: TAtlasUnitOrigins;
    FKinds: TAtlasUnitKinds;
    FLastQuery: TAtlasUnitQuery;
    FLastOrigins: TAtlasUnitOrigins;
    FLastKinds: TAtlasUnitKinds;
    FHasLast: Boolean;
    FOrder: TArray<Integer>;
  public
    /// <summary>ASyntax: Tippsyntax (unitSearch.filterSyntax); ATyped, AOrigins, AKinds: Anfangswahl.</summary>
    constructor Create(ASyntax: Boolean; const ATyped: TArray<string>; AOrigins: TAtlasUnitOrigins;
      AKinds: TAtlasUnitKinds);
    /// <summary>Anfrage aus getippten Chips und Suchtext.</summary>
    function Query: TAtlasUnitQuery;
    /// <summary>Order neu bestimmen; engt die Anfrage die letzte nur ein, prüft sie nur die bisherigen Treffer.
    /// </summary>
    procedure Apply(const AEntries: TAtlasUnitEntries; AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds);
    /// <summary>Nächstes Apply prüft wieder alle Einträge (neue Einträge).</summary>
    procedure ForgetLast;
    /// <summary>Chip AValue (TAtlasUnitSearchChip) umschalten bzw. getippten Filter entfernen.</summary>
    procedure ChipClicked(AValue: Integer);
    /// <summary>Fertig getippter Filter am Ende des Suchtexts wird zum Chip; False ohne.</summary>
    function CommitTyped: Boolean;
    /// <summary>Rücktaste: letztes Zeichen (AWord: ganzen Suchtext) bzw. letzten Chip entfernen; False ohne.</summary>
    function RemoveLast(AWord: Boolean): Boolean;
    property Pattern: string read FPattern write FPattern;
    /// <summary>Getippte Filter, die zu Chips im Feld geworden sind.</summary>
    property Typed: TArray<string> read FTyped;
    property Origins: TAtlasUnitOrigins read FOrigins;
    property Kinds: TAtlasUnitKinds read FKinds;
    /// <summary>Indizes der passenden Einträge in der Reihenfolge der Liste.</summary>
    property Order: TArray<Integer> read FOrder;
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
    /// <summary>Steht der Eintrag AIndex schon in den uses der Zielunit?</summary>
    function InUses(AIndex: Integer): Boolean;
    /// <summary>Kreis der Zeile zum Eintrag AIndex; False ohne Kreis oder wenn schon eingebunden.</summary>
    function CycleOf(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
  end;

  /// <summary>Vorschau rechts: sichtbar, Breite (bei 96 dpi), Daten der Unit, Abschnitte beim letzten Zeichnen.
  /// </summary>
  TAtlasUnitSearchPreview = class
  private
    FVisible: Boolean;
    FWidth: Integer;
    FData: TAtlasUnitPreview;
    FFileName: string;
    FSections: TAtlasSectionStates;
    FRect: TRect;
  public
    /// <summary>Daten der Unit AFileName zeigen; '' leert die Vorschau.</summary>
    procedure Show(const AFileName: string; const AData: TAtlasUnitPreview);
    property Visible: Boolean read FVisible write FVisible;
    /// <summary>Breite bei 96 dpi.</summary>
    property Width: Integer read FWidth write FWidth;
    property Data: TAtlasUnitPreview read FData;
    property FileName: string read FFileName;
    /// <summary>Zustand der Abschnitte beim letzten Zeichnen (#876).</summary>
    property Sections: TAtlasSectionStates read FSections write FSections;
    property Rect: TRect read FRect write FRect;
  end;

  TAtlasUnitSearchData = class
  private
    FOptions: TAtlasUnitSearchOptions;
    FState: TAtlasUnitSearchState;
    FMetrics: TAtlasUnitSearchMetrics;
    FEntries: TAtlasUnitEntries;
    FFilter: TAtlasUnitSearchFilter;
    FList: TAtlasUnitSearchList;
    FMarked: TDictionary<string, Boolean>;
    FUse: TAtlasUnitSearchUse;
    FPreview: TAtlasUnitSearchPreview;
  public
    constructor Create(const AOptions: TAtlasUnitSearchOptions; AState: TAtlasUnitSearchState);
    destructor Destroy; override;
    function EntryKey(AIndex: Integer): string;
    /// <summary>Eintrag der gewählten Zeile; False auf einem Gruppenkopf oder ohne Auswahl.</summary>
    function CurrentEntry(out AIndex: Integer): Boolean;
    /// <summary>Markierte in der Reihenfolge der Liste, sonst die aktuelle Zeile.</summary>
    function SelectedEntries: TArray<TAtlasUnitEntry>;
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
    property Options: TAtlasUnitSearchOptions read FOptions;
    /// <summary>Gehört dem Aufrufer; nimmt Lage und Wahl auf.</summary>
    property State: TAtlasUnitSearchState read FState;
    property Metrics: TAtlasUnitSearchMetrics read FMetrics;
    /// <summary>Bildschirmauflösung, für die Metrics misst.</summary>
    property PPI: Integer read FMetrics.PPI write FMetrics.PPI;
    property Entries: TAtlasUnitEntries read FEntries;
    property Filter: TAtlasUnitSearchFilter read FFilter;
    property List: TAtlasUnitSearchList read FList;
    property Marked: TDictionary<string, Boolean> read FMarked;
    property Use: TAtlasUnitSearchUse read FUse;
    property Preview: TAtlasUnitSearchPreview read FPreview;
  end;

const
  /// <summary>Werte der Chips: Herkunft, Art und getippte Filter (Index ab ChipTyped).</summary>
  cChipOrigins = 0;
  cChipKinds = 100;
  cChipTyped = 200;

implementation

uses
  Winapi.Windows,
  System.Math;

const
  /// <summary>Auflösung, für die alle Maße angegeben sind.</summary>
  cDesignPPI = 96;
  /// <summary>Breite der Vorschau ohne gemerkte Breite, bei 96 dpi.</summary>
  cDefaultPreviewWidth = 340;
  /// <summary>Schmalste Vorschau und schmalste Liste daneben, bei 96 dpi.</summary>
  cMinPreviewWidth = 200;
  cMinListWidth = 300;

{ TAtlasUnitSearchMetrics }

function TAtlasUnitSearchMetrics.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, PPI, cDesignPPI);
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

{ TAtlasUnitSearchFilter }

constructor TAtlasUnitSearchFilter.Create(ASyntax: Boolean; const ATyped: TArray<string>; AOrigins: TAtlasUnitOrigins;
  AKinds: TAtlasUnitKinds);
begin
  inherited Create;
  FSyntax := ASyntax;
  FTyped := Copy(ATyped);
  FOrigins := AOrigins;
  FKinds := AKinds;
end;

function TAtlasUnitSearchFilter.Query: TAtlasUnitQuery;
begin
  Result := TAtlasUnitQuery.Parse(string.Join(' ', FTyped) + ' ' + FPattern, FSyntax);
end;

procedure TAtlasUnitSearchFilter.Apply(const AEntries: TAtlasUnitEntries; AOrigins: TAtlasUnitOrigins;
  AKinds: TAtlasUnitKinds);
var
  mQuery: TAtlasUnitQuery;
begin
  mQuery := Query;
  if FHasLast and (AOrigins = FLastOrigins) and (AKinds = FLastKinds) and mQuery.Narrows(FLastQuery) then
  begin
    FOrder := TAtlasUnitSearch.Order(AEntries, mQuery, AOrigins, AKinds, FOrder);
  end
  else
  begin
    FOrder := TAtlasUnitSearch.Order(AEntries, mQuery, AOrigins, AKinds);
  end;
  FLastQuery := mQuery;
  FLastOrigins := AOrigins;
  FLastKinds := AKinds;
  FHasLast := True;
end;

procedure TAtlasUnitSearchFilter.ForgetLast;
begin
  FHasLast := False;
end;

procedure TAtlasUnitSearchFilter.ChipClicked(AValue: Integer);
var
  mOrigin: TAtlasUnitOrigin;
  mKind: TAtlasUnitKind;
begin
  if AValue >= cChipTyped then
  begin
    Delete(FTyped, AValue - cChipTyped, 1);
  end
  else if AValue >= cChipKinds then
  begin
    mKind := TAtlasUnitKind(AValue - cChipKinds);
    if mKind in FKinds then
    begin
      Exclude(FKinds, mKind);
    end
    else
    begin
      Include(FKinds, mKind);
    end;
  end
  else
  begin
    mOrigin := TAtlasUnitOrigin(AValue - cChipOrigins);
    // Mindestens eine Herkunft bleibt gewählt.
    if not (mOrigin in FOrigins) then
    begin
      Include(FOrigins, mOrigin);
    end
    else if FOrigins - [mOrigin] <> [] then
    begin
      Exclude(FOrigins, mOrigin);
    end;
  end;
end;

function TAtlasUnitSearchFilter.CommitTyped: Boolean;
var
  mWords: TArray<string>;
  mLast: string;
begin
  mWords := FPattern.Split([' '], TStringSplitOptions.ExcludeEmpty);
  mLast := '';
  if Length(mWords) > 0 then
  begin
    mLast := mWords[High(mWords)];
  end;
  Result := FSyntax and (mLast <> '') and FPattern.EndsWith(mLast) and TAtlasUnitQuery.IsFilter(mLast);
  if Result then
  begin
    FTyped := FTyped + [mLast];
    FPattern := TrimRight(Copy(FPattern, 1, Length(FPattern) - Length(mLast)));
  end;
end;

function TAtlasUnitSearchFilter.RemoveLast(AWord: Boolean): Boolean;
begin
  Result := True;
  if (FPattern <> '') and AWord then
  begin
    FPattern := '';
  end
  else if FPattern <> '' then
  begin
    Delete(FPattern, Length(FPattern), 1);
  end
  else if Length(FTyped) > 0 then
  begin
    SetLength(FTyped, Length(FTyped) - 1);
  end
  else
  begin
    Result := False;
  end;
end;

{ TAtlasUnitSearchUse }

function TAtlasUnitSearchUse.InUses(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(Marks)) and Marks[AIndex].InUses;
end;

function TAtlasUnitSearchUse.CycleOf(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
begin
  ACycle := Default(TAtlasUseUnitCycle);
  Result := (AIndex >= 0) and (AIndex <= High(Marks)) and (Marks[AIndex].Cycle >= 0) and
    not Marks[AIndex].InUses;
  if Result then
  begin
    ACycle := Info.Cycles[Marks[AIndex].Cycle];
  end;
end;

{ TAtlasUnitSearchPreview }

procedure TAtlasUnitSearchPreview.Show(const AFileName: string; const AData: TAtlasUnitPreview);
begin
  FFileName := AFileName;
  FData := AData;
end;

{ TAtlasUnitSearchData }

constructor TAtlasUnitSearchData.Create(const AOptions: TAtlasUnitSearchOptions; AState: TAtlasUnitSearchState);
var
  mOrigins, mStoredOrigins: TAtlasUnitOrigins;
  mKinds, mStoredKinds: TAtlasUnitKinds;
  mTyped: TArray<string>;
begin
  inherited Create;
  FOptions := AOptions;
  FState := AState;
  FMarked := TDictionary<string, Boolean>.Create;
  FPreview := TAtlasUnitSearchPreview.Create;
  FMetrics.PPI := cDesignPPI;
  FMetrics.Mode := AOptions.Mode;
  FMetrics.Filters := AOptions.Filters;
  FMetrics.Actions := AOptions.Actions;
  FList.Loading := True;
  FList.Grouping := AOptions.Grouping;
  FList.Selected := -1;
  // Wie im Dialog der IDE: Vorgabe implementation.
  FUse.Section := TAtlasUseUnitSection.Implementation_;
  // Formulare suchen: gesetzter, entfernbarer Filter; ohne Tippsyntax legt Refilter die Arten fest.
  mTyped := nil;
  if (AOptions.Mode = TAtlasUnitSearchMode.Forms) and AOptions.FilterSyntax then
  begin
    mTyped := TArray<string>.Create(TAtlasUseUnit.cFormsFilter);
  end;
  mOrigins := AOptions.DefaultOrigins;
  mKinds := [];
  if AOptions.Filters and AState.Filters(AOptions.GroupFile, mStoredOrigins, mStoredKinds) and
    (mStoredOrigins <> []) then
  begin
    mOrigins := mStoredOrigins;
    mKinds := mStoredKinds;
  end;
  FFilter := TAtlasUnitSearchFilter.Create(AOptions.FilterSyntax, mTyped, mOrigins, mKinds);
  if AOptions.RememberCollapsed then
  begin
    FList.Collapsed := AState.Collapsed(AOptions.GroupFile, FList.Grouping);
  end;
  FPreview.Visible := AOptions.Preview and AState.PreviewVisible;
  FPreview.Width := AState.PreviewWidth;
  if FPreview.Width <= 0 then
  begin
    FPreview.Width := cDefaultPreviewWidth;
  end;
end;

destructor TAtlasUnitSearchData.Destroy;
begin
  FFilter.Free;
  FPreview.Free;
  FMarked.Free;
  inherited Destroy;
end;

function TAtlasUnitSearchData.EntryKey(AIndex: Integer): string;
begin
  Result := LowerCase(FEntries[AIndex].FileName);
end;

function TAtlasUnitSearchData.CurrentEntry(out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  Result := (FList.Selected >= 0) and (FList.Selected <= High(FList.Rows)) and not FList.Rows[FList.Selected].IsGroup;
  if Result then
  begin
    AIndex := FList.Rows[FList.Selected].Entry;
  end;
end;

function TAtlasUnitSearchData.SelectedEntries: TArray<TAtlasUnitEntry>;
var
  mIndex: Integer;
begin
  Result := nil;
  if FOptions.MultiSelect and (FMarked.Count > 0) then
  begin
    for mIndex in FFilter.Order do
    begin
      if FMarked.ContainsKey(EntryKey(mIndex)) then
      begin
        Result := Result + [FEntries[mIndex]];
      end;
    end;
  end;
  if (Length(Result) = 0) and CurrentEntry(mIndex) then
  begin
    Result := TArray<TAtlasUnitEntry>.Create(FEntries[mIndex]);
  end;
end;

/// <summary>Herkunft und Art, nach denen gefiltert wird.</summary>
procedure ActiveFilters(const AOptions: TAtlasUnitSearchOptions; AFilter: TAtlasUnitSearchFilter;
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
begin
  mCurrent := '';
  if AKeepSelection and CurrentEntry(mIndex) then
  begin
    mCurrent := EntryKey(mIndex);
  end;
  ActiveFilters(FOptions, FFilter, mOrigins, mKinds);
  // Beim Weitertippen nur die bisherigen Treffer prüfen (#777: unter 50 ms je Taste bei 5000 Units).
  FFilter.Apply(FEntries, mOrigins, mKinds);
  RebuildRows;
  FList.Selected := -1;
  for mIndex := 0 to High(FList.Rows) do
  begin
    if (mCurrent <> '') and not FList.Rows[mIndex].IsGroup and (EntryKey(FList.Rows[mIndex].Entry) = mCurrent) then
    begin
      FList.Selected := mIndex;
      Break;
    end;
  end;
  if FList.Selected < 0 then
  begin
    FList.Scroll := 0;
    // Erste Unit wählen, nicht den Kopf.
    FList.Selected := FirstEntryRow(FList.Rows);
  end;
  EnsureVisible;
end;

procedure TAtlasUnitSearchData.RebuildRows;
var
  mIndex, mTop: Integer;
begin
  FList.Rows := TAtlasUnitSearch.Rows(FEntries, FFilter.Order, TAtlasUnitLayout.Create(FList.Grouping, FOptions.Root,
    FOptions.ActiveProject, FList.Collapsed, FFilter.Query.HasWords));
  SetLength(FList.RowTops, Length(FList.Rows) + 1);
  mTop := 0;
  for mIndex := 0 to High(FList.Rows) do
  begin
    FList.RowTops[mIndex] := mTop;
    if FList.Rows[mIndex].IsGroup then
    begin
      Inc(mTop, FMetrics.GroupHeight);
    end
    else
    begin
      Inc(mTop, FMetrics.EntryHeight);
    end;
  end;
  FList.RowTops[Length(FList.Rows)] := mTop;
end;

function TAtlasUnitSearchData.Select(ARow: Integer): Boolean;
begin
  Result := Length(FList.Rows) > 0;
  if Result then
  begin
    FList.Selected := EnsureRange(ARow, 0, High(FList.Rows));
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
  if (FList.Selected < 0) or (FList.Selected > High(FList.Rows)) then
  begin
    Exit;
  end;
  if FList.RowTops[FList.Selected] < FList.Scroll then
  begin
    FList.Scroll := FList.RowTops[FList.Selected];
  end
  else if FList.RowTops[FList.Selected + 1] > FList.Scroll + FList.Rect.Height then
  begin
    FList.Scroll := FList.RowTops[FList.Selected + 1] - FList.Rect.Height;
  end;
  FList.Scroll := EnsureRange(FList.Scroll, 0, MaxScroll(FList));
end;

procedure TAtlasUnitSearchData.ScrollBy(ADelta: Integer);
begin
  FList.Scroll := EnsureRange(FList.Scroll + ADelta, 0, MaxScroll(FList));
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
  Result := (ARow >= 0) and (ARow <= High(FList.Rows)) and (FList.Grouping <> TAtlasUnitGrouping.None);
  if not Result then
  begin
    Exit;
  end;
  mKey := LowerCase(FList.Rows[ARow].Group);
  FList.Collapsed := WithoutKey(FList.Collapsed, mKey, ACollapse);
  RebuildRows;
  // Auf dem Kopf der Gruppe bleiben.
  for mIndex := 0 to High(FList.Rows) do
  begin
    if FList.Rows[mIndex].IsGroup and SameText(FList.Rows[mIndex].Group, mKey) then
    begin
      FList.Selected := mIndex;
      Break;
    end;
  end;
  EnsureVisible;
end;

function TAtlasUnitSearchData.ToggleSelectedGroup(ACollapse: Boolean): Boolean;
var
  mIndex: Integer;
begin
  Result := (FList.Selected >= 0) and (FList.Selected <= High(FList.Rows));
  if not Result then
  begin
    Exit;
  end;
  for mIndex := FList.Selected downto 0 do
  begin
    if FList.Rows[mIndex].IsGroup then
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
  Result := FOptions.MultiSelect and (ARow >= 0) and (ARow <= High(FList.Rows)) and not FList.Rows[ARow].IsGroup;
  if not Result then
  begin
    Exit;
  end;
  mKey := EntryKey(FList.Rows[ARow].Entry);
  if FMarked.ContainsKey(mKey) then
  begin
    FMarked.Remove(mKey);
  end
  else
  begin
    FMarked.Add(mKey, True);
  end;
end;

function TAtlasUnitSearchData.MarkAll: Boolean;
var
  mIndex: Integer;
  mAll: Boolean;
begin
  Result := FOptions.MultiSelect;
  if not Result then
  begin
    Exit;
  end;
  mAll := FMarked.Count > 0;
  for mIndex in FFilter.Order do
  begin
    mAll := mAll and FMarked.ContainsKey(EntryKey(mIndex));
  end;
  FMarked.Clear;
  for mIndex in FFilter.Order do
  begin
    if not mAll then
    begin
      FMarked.AddOrSetValue(EntryKey(mIndex), True);
    end;
  end;
end;

procedure TAtlasUnitSearchData.SetEntries(const AEntries: TAtlasUnitEntries);
begin
  FEntries := AEntries;
  // Gleichstände löst Order über die Reihenfolge auf: einmal nach Name sortieren.
  TAtlasUnitSearch.SortByName(FEntries);
  FList.Loading := False;
  FFilter.ForgetLast;
  SetUseInfo(FUse.Info);
end;

procedure TAtlasUnitSearchData.SetUseInfo(const AInfo: TAtlasUseUnitInfo);
begin
  FUse.Info := AInfo;
  FUse.Marks := nil;
  if FOptions.Mode = TAtlasUnitSearchMode.UseUnit then
  begin
    FUse.Marks := TAtlasUseUnit.Marks(FUse.Info, FEntries);
  end;
end;

function TAtlasUnitSearchData.ToggleUseSection: Boolean;
begin
  Result := FOptions.Mode = TAtlasUnitSearchMode.UseUnit;
  if not Result then
  begin
    Exit;
  end;
  if FUse.Section = TAtlasUseUnitSection.Interface_ then
  begin
    FUse.Section := TAtlasUseUnitSection.Implementation_;
  end
  else
  begin
    FUse.Section := TAtlasUseUnitSection.Interface_;
  end;
end;

function TAtlasUnitSearchData.SetGrouping(AGrouping: TAtlasUnitGrouping): Boolean;
begin
  Result := AGrouping <> FList.Grouping;
  if not Result then
  begin
    Exit;
  end;
  if FOptions.RememberCollapsed then
  begin
    FState.SetCollapsed(FOptions.GroupFile, FList.Grouping, FList.Collapsed);
  end;
  FList.Grouping := AGrouping;
  FList.Collapsed := nil;
  if FOptions.RememberCollapsed then
  begin
    FList.Collapsed := FState.Collapsed(FOptions.GroupFile, FList.Grouping);
  end;
end;

procedure TAtlasUnitSearchData.SaveState(const ABounds: TRect);
begin
  FState.Left := ABounds.Left;
  FState.Top := ABounds.Top;
  FState.Width := ABounds.Width;
  FState.Height := ABounds.Height;
  FState.PreviewWidth := FPreview.Width;
  if FOptions.Preview then
  begin
    FState.PreviewVisible := FPreview.Visible;
  end;
  if FOptions.Filters then
  begin
    FState.SetFilters(FOptions.GroupFile, FFilter.Origins, FFilter.Kinds);
  end;
  if FOptions.RememberCollapsed then
  begin
    FState.SetCollapsed(FOptions.GroupFile, FList.Grouping, FList.Collapsed);
  end;
end;

procedure TAtlasUnitSearchData.Layout(AWidth, AHeight: Integer);
var
  mBody: TRect;
begin
  mBody := Rect(0, FMetrics.HeaderHeight + FMetrics.ModeHeight + FMetrics.ChipHeight, AWidth,
    AHeight - FMetrics.FooterHeight - FMetrics.ActionHeight);
  FPreview.Rect := Rect(0, 0, 0, 0);
  if FPreview.Visible then
  begin
    FPreview.Width := EnsureRange(FPreview.Width, cMinPreviewWidth,
      Max(cMinPreviewWidth, MulDiv(AWidth, cDesignPPI, FMetrics.PPI) - cMinListWidth));
    FPreview.Rect := Rect(mBody.Right - FMetrics.S(FPreview.Width), mBody.Top, mBody.Right, mBody.Bottom);
    mBody.Right := FPreview.Rect.Left;
  end;
  FList.Rect := mBody;
end;

end.
