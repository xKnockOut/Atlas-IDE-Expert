unit Atlas.UI.UnitSearch.Window;

// Fenster „Units suchen“ (#777) im Stil der Atlas-Popups (#410, #411):
// Akzentrahmen, runde Ecken, Farben aus TAtlasColors (hell oder dunkel nach
// dem IDE-Thema). Nicht modal, frei verschieb- und vergrößerbar; Lage, Größe
// und Breite der Vorschau merkt sich TAtlasUnitSearchState.
//   Kopf:    Suchfeld mit Filterchips aus der Tippsyntax, rechts Projekt /
//            Ordner / Flach.
//   Chips:   Herkunft (Aktives Projekt, Projektgruppe, Suchpfad, Bibliothek)
//            und Art (Formular, Frame, Datenmodul, Unit, Test, Include).
//   Liste:   selbst gezeichnet und virtuell (nur sichtbare Zeilen), zwei
//            Zeilen je Unit, Gruppenköpfe mit Trefferzahl und Pfeil.
//   Vorschau rechts (F4), Aktionsleiste, Fußzeile mit Tasten und „n von m“.
// Alles, was die IDE braucht (Öffnen, uses, Projektmanager, Testunits,
// Vorschau beim Server), kommt über Ereignisse von der IDE-Schicht.
// Modi (#786, TAtlasUnitSearchOptions.Mode):
//   Unit verwenden (Alt+F11): Zeile unter dem Kopf mit „Unit verwenden in
//            <Unit>“ und dem Umschalter interface / implementation (Strg+I,
//            Vorgabe implementation). Units aus den uses der Unit sind
//            ausgegraut („schon in uses“); ein Kreis zeigt „Kreis über X“,
//            als Warnung nur, wenn ihn der Compiler im gewählten Abschnitt
//            ablehnt, den Weg in der Fußzeile. Enter fügt die markierten
//            (sonst die aktuelle) über OnUse ein und schließt.
//   Formulare suchen (Umschalt+F12): Filter t:form|frame|dm (ohne
//            Tippsyntax fest die Arten); Enter öffnet den Designer,
//            Umschalt+Enter den Quelltext.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
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

  TAtlasUnitSearchWindow = class(TForm)
  private type
    THit = (None, Chip, Grouping, Row, Action, Splitter, Check, Section, SectionSwitch);
    THitArea = record
      Kind: THit;
      Rect: TRect;
      Value: Integer;
    end;
  private const
    ChipOrigins = 0;
    ChipKinds = 100;
    ChipTyped = 200;
  private
    FColors: TAtlasColors;
    FOptions: TAtlasUnitSearchOptions;
    FState: TAtlasUnitSearchState;
    FEntries: TAtlasUnitEntries;
    FLoading: Boolean;
    FPattern: string;
    /// <summary>Getippte Filter, die zu Chips im Feld geworden sind.</summary>
    FTyped: TArray<string>;
    FOrigins: TAtlasUnitOrigins;
    FKinds: TAtlasUnitKinds;
    FGrouping: TAtlasUnitGrouping;
    FCollapsed: TArray<string>;
    FOrder: TArray<Integer>;
    FMatchCount: Integer;
    /// <summary>Anfrage und Herkunft/Art zu FOrder; engt die nächste sie nur ein, prüft Order nur FOrder.</summary>
    FLastQuery: TAtlasUnitQuery;
    FLastOrigins: TAtlasUnitOrigins;
    FLastKinds: TAtlasUnitKinds;
    FHasLast: Boolean;
    FRows: TAtlasUnitRows;
    /// <summary>Oberkante jeder Zeile in Pixeln, ab Listenanfang; ein Eintrag mehr für das Ende.</summary>
    FRowTops: TArray<Integer>;
    FSelected: Integer;
    FScroll: Integer;
    FMarked: TDictionary<string, Boolean>;
    FAreas: TList<THitArea>;
    FListRect: TRect;
    FPreviewRect: TRect;
    FPreviewVisible: Boolean;
    FPreviewWidth: Integer;
    FPreview: TAtlasUnitPreview;
    FPreviewFile: string;
    /// <summary>Zustand der Abschnitte beim letzten Zeichnen (#876).</summary>
    FSections: TAtlasSectionStates;
    FPreviewTimer: TTimer;
    FDragSplitter: Boolean;
    FActionMenu: TPopupMenu;
    FOnAction: TAtlasUnitSearchActionEvent;
    FOnPreview: TAtlasUnitSearchPreviewFunc;
    FOnClosed: TProc;
    FUIFont: TFont;
    FSmallFont: TFont;
    FMonoFont: TFont;
    FLastHint: string;
    FClosing: Boolean;
    FUseInfo: TAtlasUseUnitInfo;
    /// <summary>Je Eintrag von FEntries (#786).</summary>
    FUseMarks: TArray<TAtlasUseUnitMark>;
    FUseSection: TAtlasUseUnitSection;
    FOnUse: TAtlasUnitSearchUseEvent;
    function S(AValue: Integer): Integer;
    function HeaderHeight: Integer;
    function ModeHeight: Integer;
    function ChipHeight: Integer;
    function GroupHeight: Integer;
    function EntryHeight: Integer;
    function FooterHeight: Integer;
    function ActionHeight: Integer;
    function Query: TAtlasUnitQuery;
    function CurrentEntry(out AIndex: Integer): Boolean;
    function SelectedEntries: TArray<TAtlasUnitEntry>;
    function EntryKey(AIndex: Integer): string;
    function OriginCaption(AOrigin: TAtlasUnitOrigin): string;
    function KindCaption(AKind: TAtlasUnitKind): string;
    function KindShort(AKind: TAtlasUnitKind): string;
    function ProjectColor(const AProject: string): TAtlasColor;
    function ActionCaption(AAction: TAtlasUnitSearchAction): string;
    function ActionVisible(AAction: TAtlasUnitSearchAction): Boolean;
    function GroupCaption(const AGroup: string): string;
    procedure Refilter(AKeepSelection: Boolean);
    procedure RebuildRows;
    procedure Select(ARow: Integer);
    procedure MoveSelection(ADelta: Integer);
    procedure EnsureVisible;
    procedure ToggleGroup(ARow: Integer; ACollapse: Boolean);
    procedure ToggleMark(ARow: Integer);
    procedure MarkAll;
    procedure Run(AAction: TAtlasUnitSearchAction);
    /// <summary>Enter und Doppelklick: je nach Modus öffnen, einfügen oder den Designer zeigen.</summary>
    procedure Accept(AShift: Boolean);
    procedure RunUse;
    procedure ToggleUseSection;
    procedure UpdateUseMarks;
    /// <summary>Kreis der Zeile zum Eintrag AIndex im Modus „Unit verwenden“.</summary>
    function UseCycle(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
    function UseInUses(AIndex: Integer): Boolean;
    procedure TogglePreview;
    procedure CycleGrouping;
    procedure SetGrouping(AGrouping: TAtlasUnitGrouping);
    procedure ChipClicked(AValue: Integer);
    procedure SaveState;
    procedure PreviewTick(Sender: TObject);
    procedure SchedulePreview;
    procedure MenuClick(Sender: TObject);
    procedure BuildMenu;
    function RowAt(Y: Integer): Integer;
    function HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
    procedure AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
    procedure Layout;
    procedure DrawChip(var X: Integer; Y: Integer; const ACaption: string; AOn: Boolean; AValue: Integer;
      ARight: Integer);
    procedure DrawHeader;
    procedure DrawMode;
    procedure DrawChips;
    procedure DrawList;
    procedure DrawRow(ARow: Integer; const ARect: TRect);
    /// <summary>Text mit hervorgehobenen Treffern, sonst in ABase; Ergebnis: rechter Rand des Gezeichneten.
    /// </summary>
    function DrawHighlighted(const AText: string; ARect: TRect; ABase: TAtlasColor): Integer;
    procedure DrawPreview;
    procedure DrawSketch(var ATop: Integer; const AArea: TRect);
    function SketchHeight(AWidth: Integer): Integer;
    function SectionHeadHeight: Integer;
    function SectionGap: Integer;
    function SectionPresent(ASection: TAtlasPreviewSection): Boolean;
    function SectionCaption(ASection: TAtlasPreviewSection): string;
    procedure DrawSectionHead(ASection: TAtlasPreviewSection; const ARect: TRect);
    /// <summary>Zeichnet (ADraw) oder misst den Inhalt des Abschnitts; Ergebnis ist die Höhe.</summary>
    function SectionBody(ASection: TAtlasPreviewSection; const AArea: TRect; ADraw: Boolean): Integer;
    procedure ToggleSection(ASection: TAtlasPreviewSection);
    procedure DrawActions;
    procedure DrawFooter;
    procedure WMNCHitTest(var Message: TWMNCHitTest); message WM_NCHITTEST;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure CreateWnd; override;
    procedure Paint; override;
    procedure Resize; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyPress(var Key: Char); override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    /// <summary>AState gehört weiter dem Aufrufer; das Fenster schreibt Lage und Wahl hinein.</summary>
    constructor CreateSearch(AOwner: TComponent; const AOptions: TAtlasUnitSearchOptions;
      AState: TAtlasUnitSearchState; const AColors: TAtlasColors);
    destructor Destroy; override;
    /// <summary>Einträge setzen (nach dem Laden beim Server); bis dahin zeigt das Fenster „wird geladen“.</summary>
    procedure SetEntries(const AEntries: TAtlasUnitEntries);
    /// <summary>„schon in uses“ und Kreise der Zielunit (#786, nach atlas.useUnitInfo).</summary>
    procedure SetUseInfo(const AInfo: TAtlasUseUnitInfo);
    /// <summary>Zeigen: gemerkte Lage oder mittig über AArea.</summary>
    procedure ShowOver(const AArea: TRect);
    property OnAction: TAtlasUnitSearchActionEvent read FOnAction write FOnAction;
    property OnPreview: TAtlasUnitSearchPreviewFunc read FOnPreview write FOnPreview;
    /// <summary>„Unit verwenden“: einfügbare Units und Abschnitt (#786).</summary>
    property OnUse: TAtlasUnitSearchUseEvent read FOnUse write FOnUse;
    property UseSection: TAtlasUseUnitSection read FUseSection;
    /// <summary>Nach dem Schließen (Zustand ist dann gespeichert); das Fenster gibt sich selbst frei.</summary>
    property OnClosed: TProc read FOnClosed write FOnClosed;
    property Loading: Boolean read FLoading write FLoading;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  System.StrUtils,
  System.DateUtils,
  Winapi.Dwmapi,
  Vcl.Clipbrd,
  Atlas.Core.Completion.Presentation,
  Atlas.UI.Strings;

const
  // Ab Windows 11; ältere Systeme ignorieren die Attribute.
  CornerPreference = 33;
  RoundCorners = 2;
  BorderColorAttribute = 34;

function C(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasUnitSearchWindow }

constructor TAtlasUnitSearchWindow.CreateSearch(AOwner: TComponent; const AOptions: TAtlasUnitSearchOptions;
  AState: TAtlasUnitSearchState; const AColors: TAtlasColors);
var
  Origins: TAtlasUnitOrigins;
  Kinds: TAtlasUnitKinds;
begin
  inherited CreateNew(AOwner);
  FOptions := AOptions;
  FState := AState;
  FColors := AColors;
  FMarked := TDictionary<string, Boolean>.Create;
  FAreas := TList<THitArea>.Create;
  FLoading := True;
  BorderStyle := bsNone;
  KeyPreview := False;
  DoubleBuffered := True;
  Color := C(FColors.Surface);
  case FOptions.Mode of
    TAtlasUnitSearchMode.UseUnit:
      if FOptions.TargetUnit <> '' then
        Caption := TAtlasStrings.Fmt(TAtlasTextId.UseUnitTitle, [FOptions.TargetUnit])
      else
        Caption := TAtlasStrings.Text(TAtlasTextId.UseUnitTitleNone);
    TAtlasUnitSearchMode.Forms:
      Caption := TAtlasStrings.Text(TAtlasTextId.FormsTitle);
  else
    Caption := TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle);
  end;
  // Wie im Dialog der IDE: Vorgabe implementation.
  FUseSection := TAtlasUseUnitSection.Implementation_;
  // Formulare suchen: gesetzter, entfernbarer Filter; ohne Tippsyntax legt Refilter die Arten fest.
  if (FOptions.Mode = TAtlasUnitSearchMode.Forms) and FOptions.FilterSyntax then
    FTyped := [TAtlasUseUnit.FormsFilter];
  OnClose := FormClose;
  ShowHint := True;
  FUIFont := TFont.Create;
  FUIFont.Name := 'Segoe UI';
  FUIFont.Size := 10;
  FSmallFont := TFont.Create;
  FSmallFont.Name := 'Segoe UI';
  FSmallFont.Size := 8;
  FMonoFont := TFont.Create;
  FMonoFont.Name := 'Consolas';
  FMonoFont.Size := 9;
  Font.Assign(FUIFont);
  FGrouping := FOptions.Grouping;
  FOrigins := FOptions.DefaultOrigins;
  FKinds := [];
  if FOptions.Filters and FState.Filters(FOptions.GroupFile, Origins, Kinds) and (Origins <> []) then
  begin
    FOrigins := Origins;
    FKinds := Kinds;
  end;
  if FOptions.RememberCollapsed then
    FCollapsed := FState.Collapsed(FOptions.GroupFile, FGrouping);
  FPreviewVisible := FOptions.Preview and FState.PreviewVisible;
  FPreviewWidth := FState.PreviewWidth;
  if FPreviewWidth <= 0 then
    FPreviewWidth := 340;
  FPreview := Default(TAtlasUnitPreview);
  FPreviewTimer := TTimer.Create(Self);
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Interval := 150;
  FPreviewTimer.OnTimer := PreviewTick;
  FActionMenu := TPopupMenu.Create(Self);
  BuildMenu;
  Refilter(False);
end;

destructor TAtlasUnitSearchWindow.Destroy;
begin
  FMarked.Free;
  FAreas.Free;
  FUIFont.Free;
  FSmallFont.Free;
  FMonoFont.Free;
  inherited Destroy;
end;

procedure TAtlasUnitSearchWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  // Ohne Systemrahmen; vergrößert wird über WM_NCHITTEST. Schatten wie die Palette.
  Params.Style := (Params.Style and not (WS_CAPTION or WS_THICKFRAME)) or WS_POPUP;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

procedure TAtlasUnitSearchWindow.CreateWnd;
var
  Preference, Border: DWORD;
begin
  inherited CreateWnd;
  Preference := RoundCorners;
  DwmSetWindowAttribute(Handle, CornerPreference, @Preference, SizeOf(Preference));
  Border := DWORD(FColors.Accent);
  DwmSetWindowAttribute(Handle, BorderColorAttribute, @Border, SizeOf(Border));
end;

function TAtlasUnitSearchWindow.S(AValue: Integer): Integer;
begin
  Result := ScaleValue(AValue);
end;

function TAtlasUnitSearchWindow.HeaderHeight: Integer;
begin
  Result := S(44);
end;

function TAtlasUnitSearchWindow.ModeHeight: Integer;
begin
  if FOptions.Mode = TAtlasUnitSearchMode.Search then
    Result := 0
  else
    Result := S(30);
end;

function TAtlasUnitSearchWindow.ChipHeight: Integer;
begin
  if FOptions.Filters then
    Result := S(32)
  else
    Result := 0;
end;

function TAtlasUnitSearchWindow.GroupHeight: Integer;
begin
  Result := S(24);
end;

function TAtlasUnitSearchWindow.EntryHeight: Integer;
begin
  Result := S(40);
end;

function TAtlasUnitSearchWindow.FooterHeight: Integer;
begin
  Result := S(24);
end;

function TAtlasUnitSearchWindow.ActionHeight: Integer;
begin
  if FOptions.Actions then
    Result := S(34)
  else
    Result := 0;
end;

procedure TAtlasUnitSearchWindow.ShowOver(const AArea: TRect);
var
  Area: TRect;
  Width_, Height_: Integer;
begin
  Width_ := S(1000);
  Height_ := S(620);
  if (FState.Width > 0) and (FState.Height > 0) then
  begin
    Area := Rect(FState.Left, FState.Top, FState.Left + FState.Width, FState.Top + FState.Height);
    // Nur übernehmen, wenn die gemerkte Lage noch auf einem Monitor liegt.
    if Screen.MonitorFromRect(Area, mdNull) <> nil then
    begin
      SetBounds(Area.Left, Area.Top, Area.Width, Area.Height);
      Show;
      SetFocus;
      Exit;
    end;
  end;
  Width_ := Min(Width_, AArea.Width - S(40));
  Height_ := Min(Height_, AArea.Height - S(40));
  SetBounds(AArea.Left + (AArea.Width - Width_) div 2, AArea.Top + Max(S(20), (AArea.Height - Height_) div 3),
    Width_, Height_);
  Show;
  SetFocus;
end;

procedure TAtlasUnitSearchWindow.SetEntries(const AEntries: TAtlasUnitEntries);
begin
  FEntries := AEntries;
  // Gleichstände löst Order über die Reihenfolge auf: einmal nach Name sortieren.
  TAtlasUnitSearch.SortByName(FEntries);
  FLoading := False;
  FHasLast := False;
  UpdateUseMarks;
  Refilter(False);
end;

procedure TAtlasUnitSearchWindow.SetUseInfo(const AInfo: TAtlasUseUnitInfo);
begin
  FUseInfo := AInfo;
  UpdateUseMarks;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.UpdateUseMarks;
begin
  FUseMarks := nil;
  if FOptions.Mode = TAtlasUnitSearchMode.UseUnit then
    FUseMarks := TAtlasUseUnit.Marks(FUseInfo, FEntries);
end;

function TAtlasUnitSearchWindow.UseInUses(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= High(FUseMarks)) and FUseMarks[AIndex].InUses;
end;

function TAtlasUnitSearchWindow.UseCycle(AIndex: Integer; out ACycle: TAtlasUseUnitCycle): Boolean;
begin
  ACycle := Default(TAtlasUseUnitCycle);
  Result := (AIndex >= 0) and (AIndex <= High(FUseMarks)) and (FUseMarks[AIndex].Cycle >= 0) and
    not FUseMarks[AIndex].InUses;
  if Result then
    ACycle := FUseInfo.Cycles[FUseMarks[AIndex].Cycle];
end;

function TAtlasUnitSearchWindow.Query: TAtlasUnitQuery;
begin
  Result := TAtlasUnitQuery.Parse(string.Join(' ', FTyped) + ' ' + FPattern, FOptions.FilterSyntax);
end;

procedure TAtlasUnitSearchWindow.Refilter(AKeepSelection: Boolean);
var
  Current: string;
  Index: Integer;
  Kinds: TAtlasUnitKinds;
  Origins: TAtlasUnitOrigins;
  NewQuery: TAtlasUnitQuery;
begin
  Current := '';
  if AKeepSelection and CurrentEntry(Index) then
    Current := EntryKey(Index);
  Kinds := [];
  Origins := FOptions.DefaultOrigins;
  if FOptions.Filters then
  begin
    Kinds := FKinds;
    Origins := FOrigins;
  end;
  // Formulare suchen ohne Tippsyntax: nur Formulare, Frames und Datenmodule (#786).
  if (FOptions.Mode = TAtlasUnitSearchMode.Forms) and not FOptions.FilterSyntax then
  begin
    Kinds := Kinds * TAtlasUseUnit.FormKinds;
    if Kinds = [] then
      Kinds := TAtlasUseUnit.FormKinds;
  end;
  NewQuery := Query;
  // Beim Weitertippen nur die bisherigen Treffer prüfen (#777: unter 50 ms je Taste bei 5000 Units).
  if FHasLast and (Origins = FLastOrigins) and (Kinds = FLastKinds) and NewQuery.Narrows(FLastQuery) then
    FOrder := TAtlasUnitSearch.Order(FEntries, NewQuery, Origins, Kinds, FOrder)
  else
    FOrder := TAtlasUnitSearch.Order(FEntries, NewQuery, Origins, Kinds);
  FLastQuery := NewQuery;
  FLastOrigins := Origins;
  FLastKinds := Kinds;
  FHasLast := True;
  FMatchCount := Length(FOrder);
  RebuildRows;
  FSelected := -1;
  if Current <> '' then
    for Index := 0 to High(FRows) do
      if not FRows[Index].IsGroup and (EntryKey(FRows[Index].Entry) = Current) then
      begin
        FSelected := Index;
        Break;
      end;
  if FSelected < 0 then
  begin
    FScroll := 0;
    // Erste Unit wählen, nicht den Kopf.
    for Index := 0 to High(FRows) do
      if not FRows[Index].IsGroup then
      begin
        FSelected := Index;
        Break;
      end;
    if (FSelected < 0) and (Length(FRows) > 0) then
      FSelected := 0;
  end;
  EnsureVisible;
  SchedulePreview;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.RebuildRows;
var
  Index, mTop: Integer;
begin
  FRows := TAtlasUnitSearch.Rows(FEntries, FOrder, FGrouping, FOptions.Root, FOptions.ActiveProject, FCollapsed,
    Query.HasWords);
  SetLength(FRowTops, Length(FRows) + 1);
  mTop := 0;
  for Index := 0 to High(FRows) do
  begin
    FRowTops[Index] := mTop;
    if FRows[Index].IsGroup then
      Inc(mTop, GroupHeight)
    else
      Inc(mTop, EntryHeight);
  end;
  FRowTops[Length(FRows)] := mTop;
end;

function TAtlasUnitSearchWindow.EntryKey(AIndex: Integer): string;
begin
  Result := LowerCase(FEntries[AIndex].FileName);
end;

function TAtlasUnitSearchWindow.CurrentEntry(out AIndex: Integer): Boolean;
begin
  AIndex := -1;
  Result := (FSelected >= 0) and (FSelected <= High(FRows)) and not FRows[FSelected].IsGroup;
  if Result then
    AIndex := FRows[FSelected].Entry;
end;

function TAtlasUnitSearchWindow.SelectedEntries: TArray<TAtlasUnitEntry>;
var
  Index: Integer;
begin
  Result := nil;
  // Markierte in der Reihenfolge der Liste, sonst die aktuelle Zeile.
  if FOptions.MultiSelect and (FMarked.Count > 0) then
  begin
    for Index in FOrder do
      if FMarked.ContainsKey(EntryKey(Index)) then
        Result := Result + [FEntries[Index]];
    if Length(Result) > 0 then
      Exit;
  end;
  if CurrentEntry(Index) then
    Result := [FEntries[Index]];
end;

procedure TAtlasUnitSearchWindow.Select(ARow: Integer);
begin
  if Length(FRows) = 0 then
    Exit;
  FSelected := EnsureRange(ARow, 0, High(FRows));
  EnsureVisible;
  SchedulePreview;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.MoveSelection(ADelta: Integer);
begin
  Select(FSelected + ADelta);
end;

procedure TAtlasUnitSearchWindow.EnsureVisible;
var
  mVisible: Integer;
begin
  Layout;
  if (FSelected < 0) or (FSelected > High(FRows)) then
    Exit;
  mVisible := FListRect.Height;
  if FRowTops[FSelected] < FScroll then
    FScroll := FRowTops[FSelected]
  else if FRowTops[FSelected + 1] > FScroll + mVisible then
    FScroll := FRowTops[FSelected + 1] - mVisible;
  FScroll := EnsureRange(FScroll, 0, Max(0, FRowTops[Length(FRows)] - mVisible));
end;

procedure TAtlasUnitSearchWindow.ToggleGroup(ARow: Integer; ACollapse: Boolean);
var
  Key: string;
  Kept: TArray<string>;
  Item: string;
  Index: Integer;
begin
  if (ARow < 0) or (ARow > High(FRows)) or (FGrouping = TAtlasUnitGrouping.None) then
    Exit;
  Key := LowerCase(FRows[ARow].Group);
  Kept := nil;
  for Item in FCollapsed do
    if Item <> Key then
      Kept := Kept + [Item];
  if ACollapse then
    Kept := Kept + [Key];
  FCollapsed := Kept;
  RebuildRows;
  // Auf dem Kopf der Gruppe bleiben.
  for Index := 0 to High(FRows) do
    if FRows[Index].IsGroup and SameText(FRows[Index].Group, Key) then
    begin
      FSelected := Index;
      Break;
    end;
  EnsureVisible;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.ToggleMark(ARow: Integer);
var
  Key: string;
begin
  if not FOptions.MultiSelect or (ARow < 0) or (ARow > High(FRows)) or FRows[ARow].IsGroup then
    Exit;
  Key := EntryKey(FRows[ARow].Entry);
  if FMarked.ContainsKey(Key) then
    FMarked.Remove(Key)
  else
    FMarked.Add(Key, True);
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.MarkAll;
var
  Index: Integer;
  Key: string;
  All: Boolean;
begin
  if not FOptions.MultiSelect then
    Exit;
  // Sind schon alle markiert, hebt Strg+A die Markierung auf.
  All := FMarked.Count > 0;
  for Index in FOrder do
    if not FMarked.ContainsKey(EntryKey(Index)) then
      All := False;
  FMarked.Clear;
  if not All then
    for Index in FOrder do
    begin
      Key := EntryKey(Index);
      if not FMarked.ContainsKey(Key) then
        FMarked.Add(Key, True);
    end;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.Run(AAction: TAtlasUnitSearchAction);
var
  Entries: TArray<TAtlasUnitEntry>;
  Handler: TAtlasUnitSearchActionEvent;
  Entry: TAtlasUnitEntry;
  Paths: TStringBuilder;
begin
  if not ActionVisible(AAction) then
    Exit;
  // Unit verwenden: „In uses aufnehmen“ fügt in den gewählten Abschnitt ein (#786).
  if (AAction = TAtlasUnitSearchAction.AddUses) and (FOptions.Mode = TAtlasUnitSearchMode.UseUnit) then
  begin
    RunUse;
    Exit;
  end;
  Entries := SelectedEntries;
  if Length(Entries) = 0 then
    Exit;
  if AAction = TAtlasUnitSearchAction.CopyPaths then
  begin
    Paths := TStringBuilder.Create;
    try
      for Entry in Entries do
        Paths.AppendLine(Entry.FileName);
      Clipboard.AsText := TrimRight(Paths.ToString);
    finally
      Paths.Free;
    end;
    Exit;
  end;
  Handler := FOnAction;
  // Öffnen, Formular und Testunits schließen das Fenster wie der IDE-Dialog; die übrigen lassen es offen.
  if AAction in [TAtlasUnitSearchAction.Open, TAtlasUnitSearchAction.OpenForm,
    TAtlasUnitSearchAction.OpenTests] then
    Close;
  if Assigned(Handler) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.UnitSearch,
      procedure
      begin
        Handler(AAction, Entries);
      end);
end;

procedure TAtlasUnitSearchWindow.Accept(AShift: Boolean);
begin
  case FOptions.Mode of
    TAtlasUnitSearchMode.UseUnit:
      RunUse;
    TAtlasUnitSearchMode.Forms:
      if AShift then
        Run(TAtlasUnitSearchAction.Open)
      else
        Run(TAtlasUnitSearchAction.OpenForm);
  else
    if AShift then
      Run(TAtlasUnitSearchAction.OpenForm)
    else
      Run(TAtlasUnitSearchAction.Open);
  end;
end;

procedure TAtlasUnitSearchWindow.RunUse;
var
  Entries: TArray<TAtlasUnitEntry>;
  Handler: TAtlasUnitSearchUseEvent;
  Section: TAtlasUseUnitSection;
begin
  // Ohne Duplikate: Units aus den uses, die Zielunit selbst und Include-Dateien fallen weg (#786).
  Entries := TAtlasUseUnit.Addable(FUseInfo, SelectedEntries);
  Handler := FOnUse;
  Section := FUseSection;
  // Wie der Dialog der IDE: Einfügen schließt das Fenster.
  Close;
  if Assigned(Handler) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.UnitSearch,
      procedure
      begin
        Handler(Entries, Section);
      end);
end;

procedure TAtlasUnitSearchWindow.ToggleUseSection;
begin
  if FOptions.Mode <> TAtlasUnitSearchMode.UseUnit then
    Exit;
  if FUseSection = TAtlasUseUnitSection.Interface_ then
    FUseSection := TAtlasUseUnitSection.Implementation_
  else
    FUseSection := TAtlasUseUnitSection.Interface_;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.TogglePreview;
begin
  if not FOptions.Preview then
    Exit;
  FPreviewVisible := not FPreviewVisible;
  EnsureVisible;
  SchedulePreview;
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.SetGrouping(AGrouping: TAtlasUnitGrouping);
begin
  if AGrouping = FGrouping then
    Exit;
  if FOptions.RememberCollapsed then
    FState.SetCollapsed(FOptions.GroupFile, FGrouping, FCollapsed);
  FGrouping := AGrouping;
  FCollapsed := nil;
  if FOptions.RememberCollapsed then
    FCollapsed := FState.Collapsed(FOptions.GroupFile, FGrouping);
  Refilter(True);
end;

procedure TAtlasUnitSearchWindow.CycleGrouping;
begin
  case FGrouping of
    TAtlasUnitGrouping.Project: SetGrouping(TAtlasUnitGrouping.Folder);
    TAtlasUnitGrouping.Folder: SetGrouping(TAtlasUnitGrouping.None);
  else
    SetGrouping(TAtlasUnitGrouping.Project);
  end;
end;

procedure TAtlasUnitSearchWindow.ChipClicked(AValue: Integer);
var
  Origin: TAtlasUnitOrigin;
  Kind: TAtlasUnitKind;
begin
  if AValue >= ChipTyped then
  begin
    // Getippten Filter entfernen.
    Delete(FTyped, AValue - ChipTyped, 1);
  end
  else if AValue >= ChipKinds then
  begin
    Kind := TAtlasUnitKind(AValue - ChipKinds);
    if Kind in FKinds then
      Exclude(FKinds, Kind)
    else
      Include(FKinds, Kind);
  end
  else
  begin
    Origin := TAtlasUnitOrigin(AValue - ChipOrigins);
    if Origin in FOrigins then
    begin
      // Mindestens eine Herkunft bleibt gewählt.
      if FOrigins - [Origin] <> [] then
        Exclude(FOrigins, Origin);
    end
    else
      Include(FOrigins, Origin);
  end;
  Refilter(True);
end;

procedure TAtlasUnitSearchWindow.SaveState;
begin
  FState.Left := Left;
  FState.Top := Top;
  FState.Width := Width;
  FState.Height := Height;
  FState.PreviewWidth := FPreviewWidth;
  if FOptions.Preview then
    FState.PreviewVisible := FPreviewVisible;
  if FOptions.Filters then
    FState.SetFilters(FOptions.GroupFile, FOrigins, FKinds);
  if FOptions.RememberCollapsed then
    FState.SetCollapsed(FOptions.GroupFile, FGrouping, FCollapsed);
end;

procedure TAtlasUnitSearchWindow.FormClose(Sender: TObject; var Action: TCloseAction);
var
  Closed: TProc;
begin
  if FClosing then
    Exit;
  FClosing := True;
  SaveState;
  Action := caFree;
  Closed := FOnClosed;
  if Assigned(Closed) then
    Closed();
end;

procedure TAtlasUnitSearchWindow.SchedulePreview;
begin
  if not FPreviewVisible or not Assigned(FOnPreview) then
    Exit;
  FPreviewTimer.Enabled := False;
  FPreviewTimer.Enabled := True;
end;

procedure TAtlasUnitSearchWindow.PreviewTick(Sender: TObject);
var
  Index: Integer;
begin
  FPreviewTimer.Enabled := False;
  if not FPreviewVisible or not Assigned(FOnPreview) then
    Exit;
  if not CurrentEntry(Index) then
  begin
    FPreview := Default(TAtlasUnitPreview);
    FPreviewFile := '';
    Invalidate;
    Exit;
  end;
  if SameText(FPreviewFile, FEntries[Index].FileName) then
    Exit;
  FPreviewFile := FEntries[Index].FileName;
  FPreview := FOnPreview(FEntries[Index]);
  Invalidate;
end;

function TAtlasUnitSearchWindow.ActionCaption(AAction: TAtlasUnitSearchAction): string;
begin
  case AAction of
    TAtlasUnitSearchAction.Open: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOpen);
    TAtlasUnitSearchAction.OpenForm: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOpenForm);
    TAtlasUnitSearchAction.AddUses: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchAddUses);
    TAtlasUnitSearchAction.OpenTests: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOpenTests);
    TAtlasUnitSearchAction.CopyPaths: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchCopyPaths);
    TAtlasUnitSearchAction.ShowProject: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchShowProject);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchShowExplorer);
  end;
end;

function TAtlasUnitSearchWindow.ActionVisible(AAction: TAtlasUnitSearchAction): Boolean;
begin
  Result := (AAction <> TAtlasUnitSearchAction.AddUses) or FOptions.AddUses;
end;

procedure TAtlasUnitSearchWindow.BuildMenu;
const
  ShortCuts: array[TAtlasUnitSearchAction] of string = ('Enter', 'Shift+Enter', 'Alt+Enter', 'Ctrl+T', 'Ctrl+C',
    '', '');
var
  mAction: TAtlasUnitSearchAction;
  Item: TMenuItem;
begin
  for mAction := Low(TAtlasUnitSearchAction) to High(TAtlasUnitSearchAction) do
  begin
    if not ActionVisible(mAction) then
      Continue;
    Item := TMenuItem.Create(FActionMenu);
    Item.Caption := ActionCaption(mAction);
    if ShortCuts[mAction] <> '' then
      Item.Caption := Item.Caption + #9 + ShortCuts[mAction];
    Item.Tag := Ord(mAction);
    Item.OnClick := MenuClick;
    FActionMenu.Items.Add(Item);
  end;
end;

procedure TAtlasUnitSearchWindow.MenuClick(Sender: TObject);
begin
  Run(TAtlasUnitSearchAction(TMenuItem(Sender).Tag));
end;

function TAtlasUnitSearchWindow.OriginCaption(AOrigin: TAtlasUnitOrigin): string;
begin
  case AOrigin of
    TAtlasUnitOrigin.Active: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginActive);
    TAtlasUnitOrigin.Group: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginGroup);
    TAtlasUnitOrigin.SearchPath: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginSearchPath);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchOriginLibrary);
  end;
end;

function TAtlasUnitSearchWindow.KindCaption(AKind: TAtlasUnitKind): string;
begin
  case AKind of
    TAtlasUnitKind.Form: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindForm);
    TAtlasUnitKind.Frame: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindFrame);
    TAtlasUnitKind.DataModule: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindDataModule);
    TAtlasUnitKind.Test: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindTest);
    TAtlasUnitKind.Include: Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindInclude);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchKindUnit);
  end;
end;

function TAtlasUnitSearchWindow.KindShort(AKind: TAtlasUnitKind): string;
begin
  case AKind of
    TAtlasUnitKind.Form: Result := 'FORM';
    TAtlasUnitKind.Frame: Result := 'FRAME';
    TAtlasUnitKind.DataModule: Result := 'DM';
    TAtlasUnitKind.Test: Result := 'TEST';
    TAtlasUnitKind.Include: Result := 'INC';
  else
    Result := 'UNIT';
  end;
end;

function TAtlasUnitSearchWindow.ProjectColor(const AProject: string): TAtlasColor;
var
  Hash: Cardinal;
  Index: Integer;
begin
  // Feste Farbe je Projektname aus den Paarfarben der Palette.
  Hash := 0;
  for Index := 1 to Length(AProject) do
    Hash := ((Hash and $FFFFFF) * 31 + Ord(UpCase(AProject[Index]))) and $FFFFFF;
  Result := FColors.Pairs[Hash mod Cardinal(Length(FColors.Pairs))];
end;

function TAtlasUnitSearchWindow.GroupCaption(const AGroup: string): string;
begin
  if AGroup <> '' then
    Exit(AGroup);
  if FGrouping = TAtlasUnitGrouping.Folder then
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchRootFolder)
  else
    Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchNoProject);
end;

{ Zeichnen }

procedure TAtlasUnitSearchWindow.AddArea(AKind: THit; const ARect: TRect; AValue: Integer);
var
  Area: THitArea;
begin
  Area.Kind := AKind;
  Area.Rect := ARect;
  Area.Value := AValue;
  FAreas.Add(Area);
end;

procedure TAtlasUnitSearchWindow.Layout;
var
  Body: TRect;
begin
  Body := Rect(0, HeaderHeight + ModeHeight + ChipHeight, ClientWidth, ClientHeight - FooterHeight - ActionHeight);
  FPreviewRect := Rect(0, 0, 0, 0);
  if FPreviewVisible then
  begin
    FPreviewWidth := EnsureRange(FPreviewWidth, 200, Max(200, MulDiv(ClientWidth, 96, CurrentPPI) - 300));
    FPreviewRect := Rect(Body.Right - S(FPreviewWidth), Body.Top, Body.Right, Body.Bottom);
    Body.Right := FPreviewRect.Left;
  end;
  FListRect := Body;
end;

procedure TAtlasUnitSearchWindow.Resize;
begin
  inherited;
  if Length(FRowTops) > 0 then
    EnsureVisible;
  Invalidate;
end;

function TAtlasUnitSearchWindow.DrawHighlighted(const AText: string; ARect: TRect; ABase: TAtlasColor): Integer;
var
  Marks: TArray<Boolean>;
  Position, Index, Run, X: Integer;
  Chunk: string;
  Word: string;
  Part: TRect;
begin
  SetLength(Marks, Length(AText) + 1);
  for Word in Query.Words do
    for Position in TAtlasItemPresentation.Highlights(Word, AText) do
      if (Position >= 1) and (Position <= Length(AText)) then
        Marks[Position] := True;
  X := ARect.Left;
  Index := 1;
  while (Index <= Length(AText)) and (X < ARect.Right) do
  begin
    Run := Index;
    while (Run < Length(AText)) and (Marks[Run + 1] = Marks[Index]) do
      Inc(Run);
    Chunk := Copy(AText, Index, Run - Index + 1);
    if Marks[Index] then
    begin
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := C(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Style := [];
      Canvas.Font.Color := C(ABase);
    end;
    Part := Rect(X, ARect.Top, ARect.Right, ARect.Bottom);
    DrawText(Canvas.Handle, PChar(Chunk), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    Inc(X, Canvas.TextWidth(Chunk));
    Index := Run + 1;
  end;
  Canvas.Font.Style := [];
  Result := Min(X, ARect.Right);
end;

procedure TAtlasUnitSearchWindow.DrawChip(var X: Integer; Y: Integer; const ACaption: string; AOn: Boolean;
  AValue: Integer; ARight: Integer);
var
  Chip: TRect;
  Width_: Integer;
begin
  Width_ := Canvas.TextWidth(ACaption) + S(16);
  if X + Width_ > ARight then
    Exit;
  Chip := Rect(X, Y, X + Width_, Y + S(22));
  if AOn then
  begin
    Canvas.Brush.Color := C(FColors.AccentSoft);
    Canvas.Pen.Color := C(FColors.Accent);
    Canvas.Font.Color := C(FColors.Text);
  end
  else
  begin
    Canvas.Brush.Color := C(FColors.Surface);
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Font.Color := C(FColors.Muted);
  end;
  Canvas.RoundRect(Chip.Left, Chip.Top, Chip.Right, Chip.Bottom, S(22), S(22));
  Canvas.Brush.Style := bsClear;
  DrawText(Canvas.Handle, PChar(ACaption), -1, Chip, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Canvas.Brush.Style := bsSolid;
  AddArea(THit.Chip, Chip, AValue);
  X := Chip.Right + S(6);
end;

procedure TAtlasUnitSearchWindow.DrawHeader;
var
  Input, Segment: TRect;
  X, Index, SegmentWidth: Integer;
  mText: string;
  Grouping: TAtlasUnitGrouping;
  Captions: array[TAtlasUnitGrouping] of string;
begin
  Canvas.Font.Assign(FUIFont);
  // Umschalter Projekt / Ordner / Flach rechts.
  Captions[TAtlasUnitGrouping.Project] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupProject);
  Captions[TAtlasUnitGrouping.Folder] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupFolder);
  Captions[TAtlasUnitGrouping.None] := TAtlasStrings.Text(TAtlasTextId.UnitSearchGroupNone);
  SegmentWidth := 0;
  for Grouping := Low(TAtlasUnitGrouping) to High(TAtlasUnitGrouping) do
    SegmentWidth := Max(SegmentWidth, Canvas.TextWidth(Captions[Grouping]) + S(20));
  X := ClientWidth - S(10) - 3 * SegmentWidth;
  for Grouping in [TAtlasUnitGrouping.Project, TAtlasUnitGrouping.Folder, TAtlasUnitGrouping.None] do
  begin
    Segment := Rect(X, S(9), X + SegmentWidth, HeaderHeight - S(9));
    if Grouping = FGrouping then
    begin
      Canvas.Brush.Color := C(FColors.Selection);
      Canvas.Font.Color := C(FColors.Text);
    end
    else
    begin
      Canvas.Brush.Color := C(FColors.Gutter);
      Canvas.Font.Color := C(FColors.Muted);
    end;
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Rectangle(Segment);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Captions[Grouping]), -1, Segment, DT_SINGLELINE or DT_VCENTER or DT_CENTER or
      DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    AddArea(THit.Grouping, Segment, Ord(Grouping));
    Inc(X, SegmentWidth);
  end;
  // Suchfeld mit Akzentrahmen und getippten Filtern als Chips.
  Input := Rect(S(10), S(7), ClientWidth - S(20) - 3 * SegmentWidth, HeaderHeight - S(7));
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.RoundRect(Input.Left, Input.Top, Input.Right, Input.Bottom, S(8), S(8));
  X := Input.Left + S(8);
  Canvas.Font.Assign(FSmallFont);
  for Index := 0 to High(FTyped) do
    DrawChip(X, Input.Top + (Input.Height - S(22)) div 2, FTyped[Index] + '  ×', True, ChipTyped + Index,
      Input.Right - S(80));
  Canvas.Font.Assign(FUIFont);
  Input.Left := X;
  InflateRect(Input, -S(4), 0);
  Canvas.Brush.Style := bsClear;
  if (FPattern = '') and (Length(FTyped) = 0) then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    if FOptions.FilterSyntax then
      mText := TAtlasStrings.Text(TAtlasTextId.UnitSearchPrompt)
    else
      mText := TAtlasStrings.Text(TAtlasTextId.UnitSearchTitle) + ' …';
  end
  else
  begin
    Canvas.Font.Color := C(FColors.Text);
    mText := FPattern + '|';
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, Input, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasUnitSearchWindow.DrawMode;
var
  Bar, Segment, Part: TRect;
  X, SegmentWidth: Integer;
  Section: TAtlasUseUnitSection;
  Text: string;
begin
  if FOptions.Mode = TAtlasUnitSearchMode.Search then
    Exit;
  Bar := Rect(0, HeaderHeight, ClientWidth, HeaderHeight + ModeHeight);
  Canvas.Font.Assign(FUIFont);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FColors.Text);
  Canvas.Brush.Style := bsClear;
  Part := Rect(Bar.Left + S(12), Bar.Top, Bar.Right - S(10), Bar.Bottom);
  // Umschalter interface / implementation rechts (Strg+I).
  if FOptions.Mode = TAtlasUnitSearchMode.UseUnit then
  begin
    Canvas.Font.Assign(FSmallFont);
    SegmentWidth := Max(Canvas.TextWidth('interface'), Canvas.TextWidth('implementation')) + S(20);
    X := Bar.Right - S(10) - 2 * SegmentWidth;
    for Section := Low(TAtlasUseUnitSection) to High(TAtlasUseUnitSection) do
    begin
      Segment := Rect(X, Bar.Top + S(4), X + SegmentWidth, Bar.Bottom - S(4));
      Canvas.Brush.Style := bsSolid;
      if Section = FUseSection then
      begin
        Canvas.Brush.Color := C(FColors.AccentSoft);
        Canvas.Pen.Color := C(FColors.Accent);
        Canvas.Font.Color := C(FColors.Text);
      end
      else
      begin
        Canvas.Brush.Color := C(FColors.Gutter);
        Canvas.Pen.Color := C(FColors.Line);
        Canvas.Font.Color := C(FColors.Muted);
      end;
      Canvas.Rectangle(Segment);
      Canvas.Brush.Style := bsClear;
      Text := TAtlasUseUnit.SectionText(Section);
      DrawText(Canvas.Handle, PChar(Text), -1, Segment, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
      AddArea(THit.SectionSwitch, Segment, Ord(Section));
      Inc(X, SegmentWidth);
    end;
    Part.Right := Bar.Right - S(20) - 2 * SegmentWidth;
    Canvas.Font.Assign(FUIFont);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := C(FColors.Text);
  end;
  DrawText(Canvas.Handle, PChar(Caption), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  Canvas.Font.Style := [];
  Canvas.Brush.Style := bsSolid;
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(Bar.Left, Bar.Bottom - 1);
  Canvas.LineTo(Bar.Right, Bar.Bottom - 1);
end;

procedure TAtlasUnitSearchWindow.DrawChips;
var
  X, Y: Integer;
  Origin: TAtlasUnitOrigin;
  Kind: TAtlasUnitKind;
begin
  if not FOptions.Filters then
    Exit;
  Canvas.Font.Assign(FSmallFont);
  X := S(10);
  Y := HeaderHeight + ModeHeight + (ChipHeight - S(22)) div 2 - S(2);
  for Origin := Low(TAtlasUnitOrigin) to High(TAtlasUnitOrigin) do
    DrawChip(X, Y, OriginCaption(Origin), Origin in FOrigins, ChipOrigins + Ord(Origin), ClientWidth - S(10));
  // Trenner zwischen Herkunft und Art.
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(X + S(2), Y + S(3));
  Canvas.LineTo(X + S(2), Y + S(19));
  Inc(X, S(10));
  for Kind in [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule, TAtlasUnitKind.Unit_,
    TAtlasUnitKind.Test, TAtlasUnitKind.Include] do
    DrawChip(X, Y, KindCaption(Kind), Kind in FKinds, ChipKinds + Ord(Kind), ClientWidth - S(10));
end;

procedure TAtlasUnitSearchWindow.DrawRow(ARow: Integer; const ARect: TRect);
var
  Row: TAtlasUnitRow;
  Entry: TAtlasUnitEntry;
  Part, Badge, Box: TRect;
  mText, Path: string;
  Right, Width_, MaxChars, NameEnd: Integer;
  Marked, InUses: Boolean;
  Cycle: TAtlasUseUnitCycle;
  State: TAtlasUseUnitCycleState;
begin
  Row := FRows[ARow];
  if ARow = FSelected then
  begin
    Canvas.Brush.Color := C(FColors.Selection);
    Canvas.FillRect(ARect);
  end;
  Canvas.Brush.Style := bsClear;
  if Row.IsGroup then
  begin
    Canvas.Font.Assign(FSmallFont);
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := C(FColors.Muted);
    if Row.Collapsed then
      mText := '▸  '
    else
      mText := '▾  ';
    mText := mText + GroupCaption(Row.Group) + '   ' + IntToStr(Row.Count);
    Part := Rect(ARect.Left + S(10), ARect.Top, ARect.Right - S(10), ARect.Bottom);
    DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
    if FGrouping = TAtlasUnitGrouping.Project then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := C(ProjectColor(Row.Group));
      Canvas.FillRect(Rect(ARect.Left + S(2), ARect.Top + S(6), ARect.Left + S(5), ARect.Bottom - S(6)));
    end;
    Canvas.Font.Style := [];
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  Entry := FEntries[Row.Entry];
  Part := ARect;
  Inc(Part.Left, S(10));
  // Häkchen der Mehrfachauswahl.
  if FOptions.MultiSelect then
  begin
    Marked := FMarked.ContainsKey(EntryKey(Row.Entry));
    Box := Rect(Part.Left, ARect.Top + (ARect.Height - S(14)) div 2, Part.Left + S(14),
      ARect.Top + (ARect.Height - S(14)) div 2 + S(14));
    Canvas.Brush.Style := bsSolid;
    Canvas.Pen.Color := C(FColors.Line);
    if Marked then
    begin
      Canvas.Brush.Color := C(FColors.Accent);
      Canvas.Pen.Color := C(FColors.Accent);
    end
    else
      Canvas.Brush.Color := C(FColors.Surface);
    Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, S(4), S(4));
    if Marked then
    begin
      Canvas.Pen.Color := C(FColors.Surface);
      Canvas.Pen.Width := Max(1, S(2));
      Canvas.MoveTo(Box.Left + S(3), Box.Top + S(7));
      Canvas.LineTo(Box.Left + S(6), Box.Top + S(10));
      Canvas.LineTo(Box.Left + S(11), Box.Top + S(4));
      Canvas.Pen.Width := 1;
    end;
    AddArea(THit.Check, Box, ARow);
    Part.Left := Box.Right + S(8);
    Canvas.Brush.Style := bsClear;
  end;
  // Rechts: geöffnet, Art, Projekt.
  Right := ARect.Right - S(10);
  Canvas.Font.Assign(FSmallFont);
  if Entry.Project <> '' then
  begin
    Width_ := Min(Canvas.TextWidth(Entry.Project) + S(12), S(150));
    Badge := Rect(Right - Width_, ARect.Top + S(4), Right, ARect.Top + S(20));
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := C(TAtlasColorMath.Mix(ProjectColor(Entry.Project), FColors.Surface, 0.25));
    Canvas.Pen.Color := C(ProjectColor(Entry.Project));
    Canvas.RoundRect(Badge.Left, Badge.Top, Badge.Right, Badge.Bottom, S(8), S(8));
    Canvas.Brush.Style := bsClear;
    Canvas.Font.Color := C(FColors.Text);
    InflateRect(Badge, -S(5), 0);
    DrawText(Canvas.Handle, PChar(Entry.Project), -1, Badge, DT_SINGLELINE or DT_VCENTER or DT_CENTER or
      DT_NOPREFIX or DT_END_ELLIPSIS);
    Right := Badge.Left - S(11);
  end;
  mText := KindShort(Entry.Kind);
  Width_ := Canvas.TextWidth(mText) + S(10);
  Badge := Rect(Right - Width_, ARect.Top + S(4), Right, ARect.Top + S(20));
  Canvas.Brush.Style := bsSolid;
  if Entry.Kind = TAtlasUnitKind.Test then
    Canvas.Brush.Color := C(FColors.AddSoft)
  else if Entry.Kind in [TAtlasUnitKind.Form, TAtlasUnitKind.Frame, TAtlasUnitKind.DataModule] then
    Canvas.Brush.Color := C(FColors.WarnSoft)
  else
    Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.RoundRect(Badge.Left, Badge.Top, Badge.Right, Badge.Bottom, S(6), S(6));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := C(FColors.Text);
  DrawText(Canvas.Handle, PChar(mText), -1, Badge, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
  Right := Badge.Left - S(8);
  // Unit verwenden (#786): „schon in uses“ oder der Kreis, den die Aufnahme schlösse.
  InUses := UseInUses(Row.Entry);
  mText := '';
  State := TAtlasUseUnitCycleState.None;
  if InUses then
    mText := TAtlasStrings.Text(TAtlasTextId.UseUnitInUses)
  else if UseCycle(Row.Entry, Cycle) then
  begin
    State := TAtlasUseUnit.CycleState(Cycle, FUseSection);
    if State = TAtlasUseUnitCycleState.Warning then
      mText := '⚠ ' + TAtlasStrings.Fmt(TAtlasTextId.UseUnitCycle, [TAtlasUseUnit.CycleVia(Cycle, FUseSection)])
    else
      mText := TAtlasStrings.Fmt(TAtlasTextId.UseUnitCycle, [TAtlasUseUnit.CycleVia(Cycle, FUseSection)]);
  end;
  if mText <> '' then
  begin
    Width_ := Min(Canvas.TextWidth(mText) + S(12), S(220));
    Badge := Rect(Right - Width_, ARect.Top + S(4), Right, ARect.Top + S(20));
    Canvas.Brush.Style := bsSolid;
    if State = TAtlasUseUnitCycleState.Warning then
    begin
      Canvas.Brush.Color := C(FColors.WarnSoft);
      Canvas.Pen.Color := C(FColors.Warn);
      Canvas.Font.Color := C(FColors.Text);
    end
    else
    begin
      Canvas.Brush.Color := C(FColors.Gutter);
      Canvas.Pen.Color := C(FColors.Line);
      Canvas.Font.Color := C(FColors.Muted);
    end;
    Canvas.RoundRect(Badge.Left, Badge.Top, Badge.Right, Badge.Bottom, S(8), S(8));
    Canvas.Brush.Style := bsClear;
    InflateRect(Badge, -S(5), 0);
    DrawText(Canvas.Handle, PChar(mText), -1, Badge, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Right := Badge.Left - S(13);
  end;
  if Entry.IsOpen then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := C(FColors.Accent);
    Canvas.Pen.Color := C(FColors.Accent);
    Canvas.Ellipse(Right - S(8), ARect.Top + S(8), Right, ARect.Top + S(16));
    Canvas.Brush.Style := bsClear;
    Right := Right - S(14);
  end;
  // Zeile 1: Name mit Treffern; Zeile 2: Pfad, in der Mitte gekürzt.
  Canvas.Font.Assign(FUIFont);
  if InUses then
  begin
    // Ausgegraut: steht schon in uses.
    Canvas.Font.Color := C(FColors.Muted);
    mText := Entry.Name;
    Badge := Rect(Part.Left, ARect.Top + S(2), Right, ARect.Top + S(22));
    DrawText(Canvas.Handle, PChar(mText), -1, Badge, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  end
  else
  begin
    NameEnd := DrawHighlighted(Entry.Name, Rect(Part.Left, ARect.Top + S(2), Right, ARect.Top + S(22)), FColors.Text);
    // Caption des Formulars (#1310) grau hinter dem Namen: Damit ist ein Treffer über sie erkennbar.
    if (Entry.Caption <> '') and (NameEnd + S(30) < Right) then
      DrawHighlighted(Entry.Caption, Rect(NameEnd + S(10), ARect.Top + S(2), Right, ARect.Top + S(22)), FColors.Muted);
  end;
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Color := C(FColors.Muted);
  Path := TAtlasUnitSearch.DisplayPath(Entry.FileName, FOptions.Root, FOptions.PathStyle, 0);
  MaxChars := Length(Path);
  Part := Rect(Part.Left, ARect.Top + S(21), ARect.Right - S(10), ARect.Bottom - S(2));
  if FOptions.PathStyle <> TAtlasUnitPathStyle.Absolute then
    while (MaxChars > 8) and (Canvas.TextWidth(TAtlasUnitSearch.MiddleEllipsis(Path, MaxChars)) > Part.Width) do
      Dec(MaxChars, Max(1, (MaxChars div 20)));
  mText := TAtlasUnitSearch.MiddleEllipsis(Path, MaxChars);
  DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_PATH_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasUnitSearchWindow.DrawList;
var
  Row, First: Integer;
  RowRect, Thumb: TRect;
  Total, Low_, High_, Middle: Integer;
  Clip: HRGN;
begin
  Canvas.Font.Assign(FUIFont);
  if FLoading or (Length(FRows) = 0) then
  begin
    Canvas.Font.Color := C(FColors.Muted);
    Canvas.Brush.Style := bsClear;
    if FLoading then
      DrawText(Canvas.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.UnitSearchLoading)), -1, FListRect,
        DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX)
    else
      DrawText(Canvas.Handle, '—', -1, FListRect, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  // Erste sichtbare Zeile per Binärsuche: Die Liste bleibt bei 5000 Units flüssig.
  Low_ := 0;
  High_ := High(FRows);
  First := 0;
  while Low_ <= High_ do
  begin
    Middle := (Low_ + High_) div 2;
    if FRowTops[Middle + 1] <= FScroll then
      Low_ := Middle + 1
    else
    begin
      First := Middle;
      High_ := Middle - 1;
    end;
  end;
  Clip := CreateRectRgn(FListRect.Left, FListRect.Top, FListRect.Right, FListRect.Bottom);
  try
    SelectClipRgn(Canvas.Handle, Clip);
    Row := First;
    while (Row <= High(FRows)) and (FListRect.Top + FRowTops[Row] - FScroll < FListRect.Bottom) do
    begin
      RowRect := Rect(FListRect.Left + S(4), FListRect.Top + FRowTops[Row] - FScroll, FListRect.Right - S(10),
        FListRect.Top + FRowTops[Row + 1] - FScroll);
      DrawRow(Row, RowRect);
      AddArea(THit.Row, RowRect, Row);
      Inc(Row);
    end;
  finally
    SelectClipRgn(Canvas.Handle, 0);
    DeleteObject(Clip);
  end;
  // Schmale Bildlaufleiste.
  Total := FRowTops[Length(FRows)];
  if Total > FListRect.Height then
  begin
    Thumb := Rect(FListRect.Right - S(6), 0, FListRect.Right - S(2), 0);
    Thumb.Top := FListRect.Top + MulDiv(FScroll, FListRect.Height, Total);
    Thumb.Bottom := Thumb.Top + Max(S(20), MulDiv(FListRect.Height, FListRect.Height, Total));
    Canvas.Brush.Color := C(FColors.Line);
    Canvas.FillRect(Thumb);
  end;
end;

procedure TAtlasUnitSearchWindow.DrawSketch(var ATop: Integer; const AArea: TRect);
var
  Scale_: Double;
  Frame, Box: TRect;
  Item: TAtlasUnitSketchItem;
  Height_: Integer;
begin
  if (FPreview.FormWidth <= 0) or (FPreview.FormHeight <= 0) then
    Exit;
  Scale_ := Min(AArea.Width / FPreview.FormWidth, S(180) / FPreview.FormHeight);
  Height_ := SketchHeight(AArea.Width) - S(14);
  Frame := Rect(AArea.Left, ATop, AArea.Left + Round(FPreview.FormWidth * Scale_), ATop + Height_ + S(14));
  // Titelleiste der Skizze.
  Canvas.Brush.Color := C(FColors.AccentSoft);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.Rectangle(Frame.Left, Frame.Top, Frame.Right, Frame.Top + S(14));
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Size := 7;
  Canvas.Font.Color := C(FColors.Text);
  Canvas.Brush.Style := bsClear;
  Box := Rect(Frame.Left + S(4), Frame.Top, Frame.Right - S(4), Frame.Top + S(14));
  DrawText(Canvas.Handle, PChar(FPreview.FormCaption), -1, Box, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.Rectangle(Frame.Left, Frame.Top + S(13), Frame.Right, Frame.Bottom);
  for Item in FPreview.FormItems do
  begin
    Box := Rect(Frame.Left + Round(Item.Left * Scale_), Frame.Top + S(14) + Round(Item.Top * Scale_),
      Frame.Left + Round((Item.Left + Item.Width) * Scale_), Frame.Top + S(14) + Round((Item.Top + Item.Height) * Scale_));
    if (Box.Width < 2) or (Box.Height < 2) then
      Continue;
    Canvas.Brush.Color := C(TAtlasColorMath.Mix(FColors.Accent, FColors.Gutter, Min(0.45, 0.08 * Item.Depth)));
    Canvas.Pen.Color := C(FColors.Line);
    Canvas.Rectangle(Box);
    if (Item.Caption <> '') and (Box.Height >= S(10)) then
    begin
      Canvas.Brush.Style := bsClear;
      DrawText(Canvas.Handle, PChar(Item.Caption), -1, Box, DT_SINGLELINE or DT_VCENTER or DT_CENTER or
        DT_NOPREFIX or DT_END_ELLIPSIS);
      Canvas.Brush.Style := bsSolid;
    end;
  end;
  ATop := Frame.Bottom + S(10);
end;

function TAtlasUnitSearchWindow.SketchHeight(AWidth: Integer): Integer;
begin
  Result := 0;
  if (FPreview.FormWidth <= 0) or (FPreview.FormHeight <= 0) then
    Exit;
  Result := Round(FPreview.FormHeight * Min(AWidth / FPreview.FormWidth, S(180) / FPreview.FormHeight)) + S(14);
end;

procedure TAtlasUnitSearchWindow.DrawPreview;
var
  Area, Line: TRect;
  mTop: Integer;
  mText: string;
  Index_: Integer;
  Facts: TArray<string>;
  Section: TAtlasPreviewSection;
  Inputs: TAtlasSectionInputs;
begin
  if not FPreviewVisible then
    Exit;
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.FillRect(FPreviewRect);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(FPreviewRect.Left, FPreviewRect.Top);
  Canvas.LineTo(FPreviewRect.Left, FPreviewRect.Bottom);
  AddArea(THit.Splitter, Rect(FPreviewRect.Left - S(3), FPreviewRect.Top, FPreviewRect.Left + S(3),
    FPreviewRect.Bottom), 0);
  Area := FPreviewRect;
  InflateRect(Area, -S(12), -S(10));
  mTop := Area.Top;
  Canvas.Brush.Style := bsClear;
  if not CurrentEntry(Index_) or (FPreview.FileName = '') then
  begin
    Canvas.Font.Assign(FUIFont);
    Canvas.Font.Color := C(FColors.Muted);
    DrawText(Canvas.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewNone)), -1, Area,
      DT_SINGLELINE or DT_CENTER or DT_VCENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    Exit;
  end;
  // Name und Kenndaten.
  Canvas.Font.Assign(FUIFont);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FColors.Text);
  Line := Rect(Area.Left, mTop, Area.Right, mTop + S(20));
  DrawText(Canvas.Handle, PChar(FEntries[Index_].Name), -1, Line, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Inc(mTop, S(22));
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Color := C(FColors.Muted);
  Facts := [TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewLines, [FPreview.Lines])];
  if FPreview.Modified > 0 then
    Facts := Facts + [TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewModified,
      [FormatDateTime('dd.mm.yyyy hh":"nn', FPreview.Modified)])];
  if FPreview.Git = 'clean' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitClean)]
  else if FPreview.Git = 'modified' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitModified)]
  else if FPreview.Git = 'added' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitAdded)]
  else if FPreview.Git = 'untracked' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitUntracked)]
  else if FPreview.Git = 'deleted' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitDeleted)]
  else if FPreview.Git = 'renamed' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitRenamed)]
  else if FPreview.Git = 'conflict' then
    Facts := Facts + [TAtlasStrings.Text(TAtlasTextId.UnitSearchGitConflict)];
  Line := Rect(Area.Left, mTop, Area.Right, mTop + S(16));
  mText := string.Join(' · ', Facts);
  DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_NOPREFIX or DT_END_ELLIPSIS);
  Inc(mTop, S(22));
  // Abschnitte (#876): erst messen, dann einklappen, was nicht passt.
  for Section := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
  begin
    Inputs[Section].Present := SectionPresent(Section);
    Inputs[Section].ClosedHeight := SectionHeadHeight;
    Inputs[Section].OpenHeight := 0;
    if Inputs[Section].Present then
      Inputs[Section].OpenHeight := SectionHeadHeight + SectionBody(Section, Rect(Area.Left, 0, Area.Right, MaxInt div 2),
        False) + SectionGap;
  end;
  FSections := TAtlasPreviewSections.Arrange(Inputs, FState.Sections, Area.Bottom - mTop, FOptions.PreviewAutoCollapse);
  for Section := Low(TAtlasPreviewSection) to High(TAtlasPreviewSection) do
  begin
    if FSections[Section] = TAtlasSectionState.Hidden then
      Continue;
    if mTop + SectionHeadHeight > Area.Bottom then
      Break;
    DrawSectionHead(Section, Rect(Area.Left, mTop, Area.Right, mTop + SectionHeadHeight));
    Inc(mTop, SectionHeadHeight);
    if TAtlasPreviewSections.IsOpen(FSections[Section]) then
      Inc(mTop, SectionBody(Section, Rect(Area.Left, mTop, Area.Right, Area.Bottom), True) + SectionGap);
  end;
  Canvas.Brush.Style := bsSolid;
end;

function TAtlasUnitSearchWindow.SectionHeadHeight: Integer;
begin
  Result := S(20);
end;

function TAtlasUnitSearchWindow.SectionGap: Integer;
begin
  Result := S(6);
end;

function TAtlasUnitSearchWindow.SectionPresent(ASection: TAtlasPreviewSection): Boolean;
begin
  case ASection of
    TAtlasPreviewSection.Path:
      Result := FPreview.FileName <> '';
    TAtlasPreviewSection.Header:
      Result := FPreview.Header <> '';
    TAtlasPreviewSection.Form:
      Result := FPreview.HasForm and (FPreview.FormWidth > 0) and (FPreview.FormHeight > 0);
    TAtlasPreviewSection.Types:
      Result := FPreview.TypeCount > 0;
    TAtlasPreviewSection.Uses_:
      Result := Length(FPreview.Uses_) > 0;
    TAtlasPreviewSection.UsedBy:
      Result := FPreview.UsedBy >= 0;
  else
    Result := False;
  end;
end;

function TAtlasUnitSearchWindow.SectionCaption(ASection: TAtlasPreviewSection): string;
begin
  case ASection of
    TAtlasPreviewSection.Path:
      Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewPath);
    TAtlasPreviewSection.Header:
      Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewHeader);
    TAtlasPreviewSection.Form:
      Result := TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewForm);
    TAtlasPreviewSection.Types:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewTypes, [FPreview.TypeCount]);
    TAtlasPreviewSection.Uses_:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewUses, [Length(FPreview.Uses_)]);
    TAtlasPreviewSection.UsedBy:
      Result := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewUsedBy, [FPreview.UsedBy]);
  else
    Result := '';
  end;
  Result := AnsiUpperCase(Result);
end;

procedure TAtlasUnitSearchWindow.DrawSectionHead(ASection: TAtlasPreviewSection; const ARect: TRect);
var
  Line, mTag: TRect;
  mText: string;
begin
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := C(FColors.Muted);
  if TAtlasPreviewSections.IsOpen(FSections[ASection]) then
    mText := #$25BE' ' + SectionCaption(ASection)
  else
    mText := #$25B8' ' + SectionCaption(ASection);
  Line := ARect;
  Line.Bottom := Line.Bottom - S(4);
  // Marke rechts, wenn Atlas den Abschnitt eingeklappt hat.
  if FSections[ASection] = TAtlasSectionState.AutoCollapsed then
  begin
    Canvas.Font.Style := [];
    mTag := Line;
    mTag.Left := Max(Line.Left, Line.Right - Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewAutoCollapsed)));
    DrawText(Canvas.Handle, PChar(TAtlasStrings.Text(TAtlasTextId.UnitSearchPreviewAutoCollapsed)), -1, mTag,
      DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX or DT_END_ELLIPSIS);
    Line.Right := mTag.Left - S(8);
    Canvas.Font.Style := [fsBold];
  end;
  DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  AddArea(THit.Section, ARect, Ord(ASection));
end;

function TAtlasUnitSearchWindow.SectionBody(ASection: TAtlasPreviewSection; const AArea: TRect;
  ADraw: Boolean): Integer;
var
  Line: TRect;
  mText: string;
  Item: TAtlasUnitType;
  mTop, Count, Rest: Integer;
begin
  Result := 0;
  case ASection of
    TAtlasPreviewSection.Path:
      begin
        Canvas.Font.Assign(FMonoFont);
        Canvas.Font.Color := C(FColors.Text);
        Result := S(16);
        if ADraw then
        begin
          mText := ExtractFilePath(FPreview.FileName);
          Line := Rect(AArea.Left, AArea.Top, AArea.Right, Min(AArea.Bottom, AArea.Top + Result));
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_NOPREFIX or DT_PATH_ELLIPSIS);
        end;
      end;
    TAtlasPreviewSection.Header:
      begin
        Canvas.Font.Assign(FMonoFont);
        Canvas.Font.Color := C(FColors.Comment);
        mText := FPreview.Header.Replace(#10, sLineBreak);
        Line := Rect(AArea.Left, AArea.Top, AArea.Right, AArea.Top);
        DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX or DT_EDITCONTROL);
        Result := Min(Line.Height, S(140));
        if ADraw then
        begin
          Line := Rect(AArea.Left, AArea.Top, AArea.Right, Min(AArea.Bottom, AArea.Top + Result));
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_WORDBREAK or DT_NOPREFIX or DT_EDITCONTROL or
            DT_END_ELLIPSIS);
        end;
      end;
    TAtlasPreviewSection.Form:
      begin
        Result := SketchHeight(AArea.Width);
        if ADraw then
        begin
          mTop := AArea.Top;
          DrawSketch(mTop, AArea);
        end;
      end;
    TAtlasPreviewSection.Types:
      begin
        Canvas.Font.Assign(FSmallFont);
        Rest := FPreview.TypeCount - Length(FPreview.Types);
        Result := Length(FPreview.Types) * S(17);
        if Rest > 0 then
          Inc(Result, S(17));
        if not ADraw then
          Exit;
        mTop := AArea.Top;
        Count := 0;
        for Item in FPreview.Types do
        begin
          // Platz für die Zeile „+ n weitere“ lassen, wenn danach noch Typen kommen.
          if (mTop + S(17) > AArea.Bottom) or
            ((Count < Length(FPreview.Types) - 1) and (mTop + 2 * S(17) > AArea.Bottom)) then
            Break;
          // Symbol: Anfangsbuchstabe der Art im Kästchen.
          Line := Rect(AArea.Left, mTop + S(1), AArea.Left + S(16), mTop + S(15));
          Canvas.Brush.Style := bsSolid;
          Canvas.Brush.Color := C(FColors.Badges[TAtlasBadgeKind.Type_].Background);
          Canvas.Pen.Color := C(FColors.Badges[TAtlasBadgeKind.Type_].Background);
          Canvas.RoundRect(Line.Left, Line.Top, Line.Right, Line.Bottom, S(4), S(4));
          Canvas.Brush.Style := bsClear;
          Canvas.Font.Color := C(FColors.Badges[TAtlasBadgeKind.Type_].Text);
          mText := UpperCase(Copy(Item.Kind, 1, 1));
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
          Canvas.Font.Color := C(FColors.Text);
          Line := Rect(AArea.Left + S(22), mTop, AArea.Right, mTop + S(16));
          mText := Item.Name + '   ' + Item.Kind;
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or
            DT_END_ELLIPSIS);
          Inc(mTop, S(17));
          Inc(Count);
        end;
        Rest := FPreview.TypeCount - Count;
        if (Rest > 0) and (mTop + S(16) <= AArea.Bottom) then
        begin
          Canvas.Font.Color := C(FColors.Muted);
          Line := Rect(AArea.Left + S(22), mTop, AArea.Right, mTop + S(16));
          mText := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchPreviewMore, [Rest]);
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
          Inc(mTop, S(17));
        end;
        Result := mTop - AArea.Top;
      end;
    TAtlasPreviewSection.Uses_, TAtlasPreviewSection.UsedBy:
      begin
        Canvas.Font.Assign(FSmallFont);
        Canvas.Font.Color := C(FColors.Text);
        if ASection = TAtlasPreviewSection.Uses_ then
          mText := string.Join(', ', FPreview.Uses_)
        else
        begin
          mText := string.Join(', ', FPreview.UsedByUnits);
          if FPreview.UsedBy > Length(FPreview.UsedByUnits) then
            mText := mText + ' …';
        end;
        Line := Rect(AArea.Left, AArea.Top, AArea.Right, AArea.Top);
        DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_CALCRECT or DT_WORDBREAK or DT_NOPREFIX);
        Result := Line.Height;
        if ADraw then
        begin
          Line := Rect(AArea.Left, AArea.Top, AArea.Right, Min(AArea.Bottom, AArea.Top + Result));
          DrawText(Canvas.Handle, PChar(mText), -1, Line, DT_WORDBREAK or DT_NOPREFIX or DT_END_ELLIPSIS);
        end;
      end;
  end;
end;

procedure TAtlasUnitSearchWindow.ToggleSection(ASection: TAtlasPreviewSection);
begin
  FState.Sections[ASection] := TAtlasPreviewSections.Toggled(FSections[ASection]);
  Invalidate;
end;

procedure TAtlasUnitSearchWindow.DrawActions;
var
  Bar, Button: TRect;
  X: Integer;
  mAction: TAtlasUnitSearchAction;
  mText: string;
begin
  if not FOptions.Actions then
    Exit;
  Bar := Rect(0, ClientHeight - FooterHeight - ActionHeight, ClientWidth, ClientHeight - FooterHeight);
  Canvas.Pen.Color := C(FColors.Line);
  Canvas.MoveTo(Bar.Left, Bar.Top);
  Canvas.LineTo(Bar.Right, Bar.Top);
  Canvas.Font.Assign(FSmallFont);
  X := S(10);
  for mAction := Low(TAtlasUnitSearchAction) to High(TAtlasUnitSearchAction) do
  begin
    if not ActionVisible(mAction) then
      Continue;
    mText := ActionCaption(mAction);
    Button := Rect(X, Bar.Top + S(6), X + Canvas.TextWidth(mText) + S(18), Bar.Bottom - S(6));
    if Button.Right > Bar.Right - S(10) then
      Break;
    if mAction = TAtlasUnitSearchAction.Open then
    begin
      Canvas.Brush.Color := C(FColors.Accent);
      Canvas.Pen.Color := C(FColors.Accent);
      Canvas.Font.Color := C(FColors.Surface);
    end
    else
    begin
      Canvas.Brush.Color := C(FColors.Gutter);
      Canvas.Pen.Color := C(FColors.Line);
      Canvas.Font.Color := C(FColors.Text);
    end;
    Canvas.RoundRect(Button.Left, Button.Top, Button.Right, Button.Bottom, S(6), S(6));
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(mText), -1, Button, DT_SINGLELINE or DT_VCENTER or DT_CENTER or DT_NOPREFIX);
    Canvas.Brush.Style := bsSolid;
    AddArea(THit.Action, Button, Ord(mAction));
    X := Button.Right + S(6);
  end;
end;

procedure TAtlasUnitSearchWindow.DrawFooter;
var
  Bar, Part: TRect;
  mText: string;
  Index: Integer;
  CountWidth: Integer;
  Cycle: TAtlasUseUnitCycle;
begin
  Bar := Rect(0, ClientHeight - FooterHeight, ClientWidth, ClientHeight);
  Canvas.Brush.Color := C(FColors.Gutter);
  Canvas.FillRect(Bar);
  Canvas.Font.Assign(FSmallFont);
  Canvas.Font.Color := C(FColors.Muted);
  Canvas.Brush.Style := bsClear;
  mText := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchCount, [FMatchCount, Length(FEntries)]);
  if FMarked.Count > 0 then
    mText := TAtlasStrings.Fmt(TAtlasTextId.UnitSearchMarked, [FMarked.Count]) + ' · ' + mText;
  CountWidth := Canvas.TextWidth(mText);
  Part := Rect(Bar.Right - S(10) - CountWidth, Bar.Top, Bar.Right - S(10), Bar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  // Kreis der aktuellen Unit (#786), sonst ihr voller Pfad, sonst die Tasten.
  if CurrentEntry(Index) and UseCycle(Index, Cycle) then
  begin
    if TAtlasUseUnit.CycleState(Cycle, FUseSection) = TAtlasUseUnitCycleState.Warning then
      mText := TAtlasStrings.Fmt(TAtlasTextId.UseUnitCycleWarning, [TAtlasUseUnit.CyclePath(Cycle, FUseSection)])
    else
      mText := TAtlasStrings.Fmt(TAtlasTextId.UseUnitCycleHint, [TAtlasUseUnit.CyclePath(Cycle, FUseSection)]);
  end
  else if CurrentEntry(Index) then
    mText := FEntries[Index].FileName
  else if FOptions.Mode = TAtlasUnitSearchMode.UseUnit then
    mText := TAtlasStrings.Text(TAtlasTextId.UseUnitHints)
  else if FOptions.Mode = TAtlasUnitSearchMode.Forms then
    mText := TAtlasStrings.Text(TAtlasTextId.FormsHints)
  else
    mText := TAtlasStrings.Text(TAtlasTextId.UnitSearchHints);
  Part := Rect(Bar.Left + S(10), Bar.Top, Part.Left - S(16), Bar.Bottom);
  DrawText(Canvas.Handle, PChar(mText), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_PATH_ELLIPSIS);
  Canvas.Brush.Style := bsSolid;
end;

procedure TAtlasUnitSearchWindow.Paint;
begin
  FAreas.Clear;
  Layout;
  Canvas.Brush.Color := C(FColors.Surface);
  Canvas.FillRect(ClientRect);
  DrawHeader;
  DrawMode;
  DrawChips;
  DrawList;
  DrawPreview;
  DrawActions;
  DrawFooter;
  // Rahmen in Akzentfarbe (ältere Windows-Versionen ohne Rahmenfarbe des Fenstermanagers).
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := C(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

{ Eingabe }

function TAtlasUnitSearchWindow.RowAt(Y: Integer): Integer;
var
  Offset, Index: Integer;
begin
  Result := -1;
  Offset := Y - FListRect.Top + FScroll;
  if (Y < FListRect.Top) or (Y >= FListRect.Bottom) then
    Exit;
  for Index := 0 to High(FRows) do
    if (Offset >= FRowTops[Index]) and (Offset < FRowTops[Index + 1]) then
      Exit(Index);
end;

function TAtlasUnitSearchWindow.HitAt(X, Y: Integer; out AArea: THitArea): Boolean;
var
  Index: Integer;
begin
  // Rückwärts: Häkchen und Chips liegen über Zeilen und Feld.
  for Index := FAreas.Count - 1 downto 0 do
    if PtInRect(FAreas[Index].Rect, Point(X, Y)) then
    begin
      AArea := FAreas[Index];
      Exit(True);
    end;
  AArea := Default(THitArea);
  Result := False;
end;

procedure TAtlasUnitSearchWindow.WMNCHitTest(var Message: TWMNCHitTest);
var
  Point_: TPoint;
  Edge: Integer;
  Area: THitArea;
begin
  inherited;
  Point_ := ScreenToClient(Point(Message.XPos, Message.YPos));
  Edge := S(6);
  // Ränder zum Vergrößern.
  if (Point_.Y < Edge) and (Point_.X < Edge) then
    Message.Result := HTTOPLEFT
  else if (Point_.Y < Edge) and (Point_.X >= ClientWidth - Edge) then
    Message.Result := HTTOPRIGHT
  else if (Point_.Y >= ClientHeight - Edge) and (Point_.X < Edge) then
    Message.Result := HTBOTTOMLEFT
  else if (Point_.Y >= ClientHeight - Edge) and (Point_.X >= ClientWidth - Edge) then
    Message.Result := HTBOTTOMRIGHT
  else if Point_.Y < Edge then
    Message.Result := HTTOP
  else if Point_.Y >= ClientHeight - Edge then
    Message.Result := HTBOTTOM
  else if Point_.X < Edge then
    Message.Result := HTLEFT
  else if Point_.X >= ClientWidth - Edge then
    Message.Result := HTRIGHT
  // Freie Stellen im Kopf verschieben das Fenster.
  else if (Point_.Y < HeaderHeight) and not HitAt(Point_.X, Point_.Y, Area) and
    ((Point_.Y < S(7)) or (Point_.Y > HeaderHeight - S(7))) then
    Message.Result := HTCAPTION
  else
    Message.Result := HTCLIENT;
end;

procedure TAtlasUnitSearchWindow.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTALLKEYS or DLGC_WANTARROWS or DLGC_WANTCHARS or DLGC_WANTTAB;
end;

procedure TAtlasUnitSearchWindow.KeyDown(var Key: Word; Shift: TShiftState);
var
  Index: Integer;
  Words: TArray<string>;
  Last: string;
begin
  case Key of
    VK_ESCAPE:
      Close;
    VK_RETURN:
      if (FSelected >= 0) and (FSelected <= High(FRows)) and FRows[FSelected].IsGroup and (FMarked.Count = 0) then
        ToggleGroup(FSelected, not FRows[FSelected].Collapsed)
      else if (ssAlt in Shift) and (FOptions.Mode <> TAtlasUnitSearchMode.UseUnit) then
        Run(TAtlasUnitSearchAction.AddUses)
      else
        Accept(ssShift in Shift);
    VK_UP:
      MoveSelection(-1);
    VK_DOWN:
      MoveSelection(1);
    VK_PRIOR:
      MoveSelection(-Max(1, FListRect.Height div EntryHeight));
    VK_NEXT:
      MoveSelection(Max(1, FListRect.Height div EntryHeight));
    VK_HOME:
      if ssCtrl in Shift then
        Select(0)
      else
        Exit;
    VK_END:
      if ssCtrl in Shift then
        Select(High(FRows))
      else
        Exit;
    VK_LEFT, VK_RIGHT:
      begin
        if not (ssCtrl in Shift) or (FSelected < 0) or (FSelected > High(FRows)) then
          Exit;
        // Gruppe der markierten Zeile klappen.
        for Index := FSelected downto 0 do
          if FRows[Index].IsGroup then
          begin
            ToggleGroup(Index, Key = VK_LEFT);
            Break;
          end;
      end;
    VK_F4:
      TogglePreview;
    VK_SPACE:
      begin
        // Fertig getippter Filter wird zum Chip; sonst markiert die Leertaste (Umschalt+Leertaste tippt
        // ein Leerzeichen für mehrere Suchwörter).
        Words := FPattern.Split([' '], TStringSplitOptions.ExcludeEmpty);
        if Length(Words) > 0 then
          Last := Words[High(Words)]
        else
          Last := '';
        if FOptions.FilterSyntax and (Last <> '') and FPattern.EndsWith(Last) and TAtlasUnitQuery.IsFilter(Last) then
        begin
          FTyped := FTyped + [Last];
          FPattern := TrimRight(Copy(FPattern, 1, Length(FPattern) - Length(Last)));
          Refilter(True);
        end
        else if FOptions.MultiSelect and not (ssShift in Shift) then
        begin
          ToggleMark(FSelected);
          MoveSelection(1);
        end
        else
        begin
          FPattern := FPattern + ' ';
          Refilter(True);
        end;
      end;
    VK_BACK:
      begin
        if FPattern <> '' then
        begin
          if ssCtrl in Shift then
            FPattern := ''
          else
            Delete(FPattern, Length(FPattern), 1);
        end
        else if Length(FTyped) > 0 then
          SetLength(FTyped, Length(FTyped) - 1)
        else
          Exit;
        Refilter(False);
      end;
  else
    if ssCtrl in Shift then
      case Key of
        Ord('A'):
          MarkAll;
        Ord('T'):
          Run(TAtlasUnitSearchAction.OpenTests);
        Ord('C'):
          Run(TAtlasUnitSearchAction.CopyPaths);
        Ord('G'):
          CycleGrouping;
        Ord('I'):
          ToggleUseSection;
      else
        Exit;
      end
    else
      Exit;
  end;
  Key := 0;
end;

procedure TAtlasUnitSearchWindow.KeyPress(var Key: Char);
begin
  if Key > ' ' then
  begin
    FPattern := FPattern + Key;
    Refilter(False);
  end;
  Key := #0;
end;

procedure TAtlasUnitSearchWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Area: THitArea;
  Row: Integer;
  Point_: TPoint;
begin
  inherited;
  if not HitAt(X, Y, Area) then
    Exit;
  case Area.Kind of
    THit.Splitter:
      if Button = mbLeft then
      begin
        FDragSplitter := True;
        MouseCapture := True;
      end;
    THit.Chip:
      if Button = mbLeft then
        ChipClicked(Area.Value);
    THit.Grouping:
      if Button = mbLeft then
        SetGrouping(TAtlasUnitGrouping(Area.Value));
    THit.Action:
      if Button = mbLeft then
        Run(TAtlasUnitSearchAction(Area.Value));
    THit.Check:
      if Button = mbLeft then
      begin
        Select(Area.Value);
        ToggleMark(Area.Value);
      end;
    THit.Section:
      if Button = mbLeft then
        ToggleSection(TAtlasPreviewSection(Area.Value));
    THit.SectionSwitch:
      if (Button = mbLeft) and (TAtlasUseUnitSection(Area.Value) <> FUseSection) then
        ToggleUseSection;
    THit.Row:
      begin
        Row := Area.Value;
        Select(Row);
        if FRows[Row].IsGroup then
        begin
          if Button = mbLeft then
            ToggleGroup(Row, not FRows[Row].Collapsed);
        end
        else if (Button = mbLeft) and (ssCtrl in Shift) then
          ToggleMark(Row)
        else if Button = mbRight then
        begin
          Point_ := ClientToScreen(Point(X, Y));
          FActionMenu.Popup(Point_.X, Point_.Y);
        end;
      end;
  end;
end;

procedure TAtlasUnitSearchWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Area: THitArea;
  mText: string;
begin
  inherited;
  if FDragSplitter then
  begin
    FPreviewWidth := MulDiv(ClientWidth - X, 96, CurrentPPI);
    Layout;
    Invalidate;
    Exit;
  end;
  mText := '';
  if HitAt(X, Y, Area) then
  begin
    if Area.Kind = THit.Splitter then
      Cursor := crHSplit
    else if Area.Kind in [THit.Section, THit.SectionSwitch] then
      Cursor := crHandPoint
    else
      Cursor := crDefault;
    // Voller Pfad als Tooltip.
    if (Area.Kind = THit.Row) and not FRows[Area.Value].IsGroup then
      mText := FEntries[FRows[Area.Value].Entry].FileName
    else if (Area.Kind = THit.Section) and (TAtlasPreviewSection(Area.Value) = TAtlasPreviewSection.Path) then
      mText := FPreview.FileName;
  end
  else
    Cursor := crDefault;
  if mText <> FLastHint then
  begin
    FLastHint := mText;
    Hint := mText;
    Application.CancelHint;
  end;
end;

procedure TAtlasUnitSearchWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if FDragSplitter then
  begin
    FDragSplitter := False;
    MouseCapture := False;
  end;
end;

procedure TAtlasUnitSearchWindow.DblClick;
var
  Point_: TPoint;
  Row: Integer;
begin
  inherited;
  Point_ := ScreenToClient(Mouse.CursorPos);
  Row := RowAt(Point_.Y);
  if (Row >= 0) and not FRows[Row].IsGroup and (Point_.X < FListRect.Right) then
  begin
    Select(Row);
    FMarked.Clear;
    Accept(False);
  end;
end;

function TAtlasUnitSearchWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  FScroll := EnsureRange(FScroll - Sign(WheelDelta) * 3 * EntryHeight, 0,
    Max(0, FRowTops[Length(FRows)] - FListRect.Height));
  Invalidate;
  Result := True;
end;

end.
