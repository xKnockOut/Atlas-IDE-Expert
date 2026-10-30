unit Atlas.UI.Problems.Frame;

// Inhalt des Fensters „Atlas-Prüfung“ (#909), reine VCL. Oben die
// Werkzeugleiste: Bereich (aktuelle Datei, Projekt, Projektgruppe), je Art ein
// Umschalter mit Anzahl, Kategorie, Gruppierung, Textfilter und rechts die
// Anzeige „Live“ bzw. „Angehalten“. Darunter die Liste (virtuell, ohne
// Flackern) mit den Spalten aus TAtlasFindingColumn: Icon (rotes Kreuz,
// gelb-oranges Dreieck, blauer Kreis), Art, Kategorie, Meldung, Zeile (gekürzt,
// Tooltip mit ganzer Zeile), Stelle, Regel und Compiler (#1024: Code, bei
// bestätigten Befunden „Atlas + dcc“). Reihenfolge (Spaltenkopf ziehen),
// Breite und Sichtbarkeit (Kontextmenü „Spalten“, nur Meldung, Regel und
// Compiler) liefert ColumnsText für problems.window.columns. Mit
// ShowCompilerCode aus (problems.showCompilerCode) fehlt die Spalte Compiler,
// und die Meldungen stehen ohne „(wie E2035)“. Klick auf den
// Spaltenkopf sortiert, ein zweiter kehrt um. Gruppenzeilen (▾/▸ Name, Anzahl)
// klappen per Klick, Leertaste oder ←/→. Unten die Statuszeile.
// Bedienung: Doppelklick oder Enter springt (OnOpen), Alt+Enter wendet die
// Schnellkorrektur an (OnFix), Strg+C kopiert die Auswahl. Kontextmenü:
// Gehe zu, Schnellkorrektur, „Für diese Zeile unterdrücken“, „Regel
// einstellen…“, „Regel abschalten“, „Regel erklären“, Kopieren, Spalten,
// Sortierung zurücksetzen. Neue Einträge werden kurz hervorgehoben.
// Den Inhalt (SetFindings) und die Statuszeile setzt die IDE-Schicht; Auswahl,
// Aufklappzustand und Bildlauf bleiben dabei erhalten (TAtlasFindingsView).
// Offene Units zuerst (#1108): Umschaltknopf „Offene zuerst“ (Nadel) neben
// der Gruppierung; die Gruppe bzw. die Zeilen der aktiven Unit hinterlegt in
// Akzentfarbe mit Nadel und „aktiver Editor“, Trennzeilen „Geöffnet“ und
// „Nicht geöffnet“ über die ganze Zeile, nicht geöffnete Units ausgegraut
// (Text mit mindestens 4,5 : 1, Symbole aufgehellt in gleicher Form) und
// voll bedienbar. Trennzeilen lassen sich nicht wählen; ↑/↓ springen über sie.
// Wechselt die aktive Unit, bleibt die Auswahl sichtbar, ohne Auswahl steht
// die oberste Zeile oben.
// Die DFM ist leer, weil TCustomFrame.Create für abgeleitete Frames eine
// Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Windows,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.ImgList,
  Vcl.Forms,
  Atlas.Core.Problems.Findings;

type
  TAtlasFindingEvent = reference to procedure(const AFinding: TAtlasFinding);
  TAtlasFindingScopeEvent = reference to procedure(AScope: TAtlasFindingScope);
  /// <summary>Mehrere markierte Befunde (#1268: ein Issue mit Liste).</summary>
  TAtlasFindingsEvent = reference to procedure(const AFindings: TArray<TAtlasFinding>);

  TAtlasProblemsFrame = class(TFrame)
  private
    FView: TAtlasFindingsView;
    FBar: TPanel;
    FScope: TComboBox;
    FKinds: array[TAtlasFindingKind] of TSpeedButton;
    FCategory: TComboBox;
    FGrouping: TComboBox;
    FOpenFirst: TSpeedButton;
    FFilter: TEdit;
    FLive: TLabel;
    FList: TListView;
    FEmpty: TLabel;
    FStatus: TLabel;
    FImages: TImageList;
    FMenu: TPopupMenu;
    FOpenItem: TMenuItem;
    FFixItem: TMenuItem;
    FSuppressItem: TMenuItem;
    FConfigureItem: TMenuItem;
    FDisableItem: TMenuItem;
    FExplainItem: TMenuItem;
    FIssueItem: TMenuItem;
    FCopyItem: TMenuItem;
    FColumnsItem: TMenuItem;
    FResetSortItem: TMenuItem;
    FNewTimer: TTimer;
    /// <summary>Einträge der Auswahllisten; gefüllt erst mit Fenster (CreateWnd).</summary>
    FScopeTexts: TArray<string>;
    FCategoryTexts: TArray<string>;
    FGroupingTexts: TArray<string>;
    /// <summary>Alle Spalten in Anzeigereihenfolge mit Breite und Sichtbarkeit.</summary>
    FColumns: TArray<TAtlasFindingColumnState>;
    /// <summary>Spalte der Liste (Index) → Spalte des Modells; Index 0 ist immer das Icon.</summary>
    FShown: TArray<TAtlasFindingColumn>;
    /// <summary>Reihenfolge des Spaltenkopfs noch nicht gesetzt (Liste ohne Fenster).</summary>
    FOrderPending: Boolean;
    /// <summary>Fenster der Liste, für das die Reihenfolge gesetzt ist; Andocken legt es neu an.</summary>
    FOrderHandle: HWND;
    FUpdating: Boolean;
    FShowCompilerCode: Boolean;
    /// <summary>Fläche, für die die ausgegrauten Symbole gebaut sind.</summary>
    FImagesBack: TColor;
    FOnOpen: TAtlasFindingEvent;
    FOnFix: TAtlasFindingEvent;
    FOnSuppress: TAtlasFindingEvent;
    FOnConfigure: TAtlasFindingEvent;
    FOnDisable: TAtlasFindingEvent;
    FOnExplain: TAtlasFindingEvent;
    FOnCreateIssue: TAtlasFindingsEvent;
    FCanCreateIssue: TFunc<Boolean>;
    FOnScope: TAtlasFindingScopeEvent;
    FOnLayout: TProc;
    function AddMenuItem(AParent: TMenuItem; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    function AddCombo(AWidth: Integer): TComboBox;
    procedure FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer);
    procedure BuildImages;
    /// <summary>Fläche und Text der Liste nach dem IDE-Thema.</summary>
    function ListBack: TColor;
    function ListText: TColor;
    /// <summary>Text einer Trennzeile bzw. der Zeile „Keine Befunde“ (#1108).</summary>
    function SectionText(const ARow: TAtlasFindingRow): string;
    procedure DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
    procedure BuildColumns;
    procedure SetShowCompilerCode(AValue: Boolean);
    /// <summary>Anzeigereihenfolge und Breiten der Liste nach FColumns übernehmen.</summary>
    procedure ReadColumns;
    /// <summary>Hebt die Markierung der virtuellen Liste mit einer Nachricht auf. TCustomListView.ClearSelection
    /// holt jede Zeile einzeln über OnData und hängt bei vielen Befunden die IDE auf.</summary>
    procedure ClearListSelection;
    procedure ApplyOrder;
    function ColumnCaption(AColumn: TAtlasFindingColumn): string;
    function CellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
    /// <summary>Erste sichtbare Textspalte in Anzeigereihenfolge: dort steht der Name einer Gruppe.</summary>
    function GroupColumn: TAtlasFindingColumn;
    function FilterFromControls: TAtlasFindingFilter;
    procedure UpdateKindCaptions;
    /// <summary>Nach neuen Befunden: Hervorhebung neu starten, Liste neu füllen.</summary>
    procedure FindingsChanged;
    /// <summary>Hat die aktive Unit seit ABefore gewechselt: Auswahl bzw. oberste Zeile sichtbar halten.</summary>
    procedure KeepInView(const ABefore: string);
    function RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
    function SelectedRows: TArray<Integer>;
    function Current(out AFinding: TAtlasFinding): Boolean;
    function IsRule(const AFinding: TAtlasFinding): Boolean;
    procedure Fire(const AEvent: TAtlasFindingEvent);
    procedure ControlsChanged(Sender: TObject);
    procedure ScopeChange(Sender: TObject);
    procedure GroupingChange(Sender: TObject);
    procedure OpenFirstClick(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure NewTimerTick(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure FixClick(Sender: TObject);
    procedure SuppressClick(Sender: TObject);
    procedure ConfigureClick(Sender: TObject);
    procedure DisableClick(Sender: TObject);
    procedure ExplainClick(Sender: TObject);
    procedure IssueClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ColumnToggleClick(Sender: TObject);
    procedure ResetSortClick(Sender: TObject);
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Einstellungen übernehmen: Bereich, Gruppierung, Spalten (problems.window.columns) und
    /// Compilermeldungen.</summary>
    procedure ApplySettings(AScope: TAtlasFindingScope; AGrouping: TAtlasFindingGrouping; const AColumns: string;
      ACompiler: Boolean);
    /// <summary>Offene Units zuerst (#1108): problems.window.openFirst, .closedUnits, .showCleanActive.</summary>
    procedure ApplyTierSettings(AOpenFirst: Boolean; AClosedUnits: TAtlasClosedUnits; AShowCleanActive: Boolean);
    /// <summary>Aktive und geöffnete Dateien (#1108); AActiveChecked: der Server hat die aktive Datei geliefert.
    /// Hält die Auswahl sichtbar bzw. ohne Auswahl die oberste Zeile oben, wenn die aktive Unit wechselt.</summary>
    procedure SetOpenFiles(const AActive: string; const AOpen: TArray<string>; AActiveChecked: Boolean);
    /// <summary>Umschaltknopf „Offene zuerst“ gedrückt.</summary>
    function OpenFirst: Boolean;
    /// <summary>Neuer Stand; ACurrentFile und AFiles bestimmen den Bereich (siehe TAtlasFindingFilter).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
      const AFiles: TArray<string>); overload;
    /// <summary>Neuer Stand samt aktiver und geöffneter Dateien in einem Schritt: ein Neuaufbau der Liste statt
    /// drei. Wirkt wie SetFindings und danach SetOpenFiles(ACurrentFile, AOpen, AActiveChecked).</summary>
    procedure SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
      const AFiles, AOpen: TArray<string>; AActiveChecked: Boolean); overload;
    procedure SetStatus(const AText: string);
    /// <summary>„Live“ bei laufender Prüfung, sonst „Angehalten“.</summary>
    procedure SetLive(ALive: Boolean);
    /// <summary>Liste neu zeichnen, Auswahl und Bildlauf bleiben.</summary>
    procedure Refill;
    /// <summary>Markierung folgt dem Cursor (problems.window.followCursor).</summary>
    procedure FollowCursor(const AFileName: string; ALine: Integer);
    /// <summary>F8/Umschalt+F8 aus dem Editor: nächster bzw. vorheriger Befund der gefilterten Liste.</summary>
    function Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
    /// <summary>Spalten für problems.window.columns.</summary>
    function ColumnsText: string;
    function Scope: TAtlasFindingScope;
    function Grouping: TAtlasFindingGrouping;
    procedure CopySelection;
    /// <summary>Umschalter der Art AKind („Warnung 3“).</summary>
    function KindButton(AKind: TAtlasFindingKind): TSpeedButton;
    class function KindText(AKind: TAtlasFindingKind): string; static;
    class function CategoryText(ACategory: TAtlasFindingCategory): string; static;
    property View: TAtlasFindingsView read FView;
    /// <summary>Compilercodes zeigen (problems.showCompilerCode, #1024; Vorgabe an).</summary>
    property ShowCompilerCode: Boolean read FShowCompilerCode write SetShowCompilerCode;
    property List: TListView read FList;
    property ScopeBox: TComboBox read FScope;
    property CategoryBox: TComboBox read FCategory;
    property GroupingBox: TComboBox read FGrouping;
    property OpenFirstButton: TSpeedButton read FOpenFirst;
    property FilterEdit: TEdit read FFilter;
    property LiveLabel: TLabel read FLive;
    property StatusLabel: TLabel read FStatus;
    property EmptyLabel: TLabel read FEmpty;
    property Menu: TPopupMenu read FMenu;
    property OnOpen: TAtlasFindingEvent read FOnOpen write FOnOpen;
    property OnFix: TAtlasFindingEvent read FOnFix write FOnFix;
    property OnSuppress: TAtlasFindingEvent read FOnSuppress write FOnSuppress;
    property OnConfigure: TAtlasFindingEvent read FOnConfigure write FOnConfigure;
    property OnDisable: TAtlasFindingEvent read FOnDisable write FOnDisable;
    property OnExplain: TAtlasFindingEvent read FOnExplain write FOnExplain;
    /// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) mit den markierten Befunden.</summary>
    property OnCreateIssue: TAtlasFindingsEvent read FOnCreateIssue write FOnCreateIssue;
    /// <summary>Eintrag sichtbar (issues.create); nil = unsichtbar.</summary>
    property CanCreateIssue: TFunc<Boolean> read FCanCreateIssue write FCanCreateIssue;
    /// <summary>Markierte Befunde ohne Gruppen- und Trennzeilen, in Anzeigereihenfolge.</summary>
    function SelectedFindings: TArray<TAtlasFinding>;
    /// <summary>Bereich gewechselt: Die IDE-Schicht liefert die Dateien des Bereichs neu.</summary>
    property OnScope: TAtlasFindingScopeEvent read FOnScope write FOnScope;
    /// <summary>Bereich, Gruppierung, Spalten oder „Offene zuerst“ geändert: zum Speichern.</summary>
    property OnLayout: TProc read FOnLayout write FOnLayout;
  end;

implementation

uses
  System.Math,
  Winapi.CommCtrl,
  Vcl.Clipbrd,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Style.Signal,
  Atlas.Core.Problems.Colors,
  Atlas.UI.Strings,
  Atlas.UI.Problems.KindIcon;

{$R *.dfm}

const
  /// <summary>Vorgabebreiten bei 96 dpi.</summary>
  DefaultWidths: array[TAtlasFindingColumn] of Integer = (24, 70, 110, 320, 260, 130, 150, 130);
  /// <summary>Hervorhebung neuer Einträge.</summary>
  NewMs = 1500;
  IconSize = 16;
  /// <summary>Symbole der Arten; dahinter dieselben ausgegraut (#1108).</summary>
  DimmedImageOffset = 3;
  PinMark = #$D83D#$DCCC;
  CheckMark = #$2713;

{ TAtlasProblemsFrame }

constructor TAtlasProblemsFrame.Create(AOwner: TComponent);
var
  Kind: TAtlasFindingKind;
  Button: TSpeedButton;
  mLeft: Integer;
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FView := TAtlasFindingsView.Create;

  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.Height := MulDiv(28, CurrentPPI, 96);
  FBar.ParentBackground := True;

  FScopeTexts := [TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)];
  FScope := AddCombo(110);
  FScope.OnChange := ScopeChange;
  mLeft := FScope.Left + FScope.Width + MulDiv(6, CurrentPPI, 96);
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    Button := TSpeedButton.Create(Self);
    Button.Parent := FBar;
    Button.Top := MulDiv(2, CurrentPPI, 96);
    Button.Height := MulDiv(22, CurrentPPI, 96);
    Button.Width := MulDiv(78, CurrentPPI, 96);
    Button.Left := mLeft;
    Button.Flat := True;
    // Je Umschalter eine eigene Gruppe: unabhängig an und aus.
    Button.GroupIndex := Ord(Kind) + 1;
    Button.AllowAllUp := True;
    Button.Down := True;
    Button.OnClick := ControlsChanged;
    FKinds[Kind] := Button;
    Inc(mLeft, Button.Width + MulDiv(2, CurrentPPI, 96));
  end;
  FCategoryTexts := [TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryAll),
    CategoryText(TAtlasFindingCategory.Bug), CategoryText(TAtlasFindingCategory.Vulnerability),
    CategoryText(TAtlasFindingCategory.CodeSmell), CategoryText(TAtlasFindingCategory.SecurityHotspot),
    CategoryText(TAtlasFindingCategory.Compiler), CategoryText(TAtlasFindingCategory.Other)];
  FCategory := AddCombo(130);
  FCategory.Left := mLeft + MulDiv(4, CurrentPPI, 96);
  FCategory.OnChange := ControlsChanged;
  FGroupingTexts := [TAtlasStrings.Text(TAtlasTextId.ProblemsGroupNone),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupFile), TAtlasStrings.Text(TAtlasTextId.ProblemsGroupRule),
    TAtlasStrings.Text(TAtlasTextId.ProblemsGroupCategory)];
  FGrouping := AddCombo(120);
  FGrouping.Left := FCategory.Left + FCategory.Width + MulDiv(4, CurrentPPI, 96);
  FGrouping.OnChange := GroupingChange;
  // Offene Units zuerst (#1108): gedrückt = an; eigene Gruppe, damit er allein an und aus geht.
  FOpenFirst := TSpeedButton.Create(Self);
  FOpenFirst.Parent := FBar;
  FOpenFirst.Top := MulDiv(2, CurrentPPI, 96);
  FOpenFirst.Height := MulDiv(22, CurrentPPI, 96);
  FOpenFirst.Width := MulDiv(110, CurrentPPI, 96);
  FOpenFirst.Left := FGrouping.Left + FGrouping.Width + MulDiv(4, CurrentPPI, 96);
  FOpenFirst.Flat := True;
  FOpenFirst.GroupIndex := Ord(High(TAtlasFindingKind)) + 2;
  FOpenFirst.AllowAllUp := True;
  FOpenFirst.Caption := PinMark + ' ' + TAtlasStrings.Text(TAtlasTextId.ProblemsOpenFirst);
  FOpenFirst.Hint := TAtlasStrings.Text(TAtlasTextId.ProblemsOpenFirstHint);
  FOpenFirst.ShowHint := True;
  FOpenFirst.OnClick := OpenFirstClick;
  FFilter := TEdit.Create(Self);
  FFilter.Parent := FBar;
  FFilter.Top := MulDiv(3, CurrentPPI, 96);
  FFilter.Left := FOpenFirst.Left + FOpenFirst.Width + MulDiv(4, CurrentPPI, 96);
  FFilter.Width := MulDiv(200, CurrentPPI, 96);
  FFilter.TextHint := TAtlasStrings.Text(TAtlasTextId.ProblemsFilterHint);
  FFilter.OnChange := ControlsChanged;
  FFilter.OnKeyDown := FilterKeyDown;
  FLive := TLabel.Create(Self);
  FLive.Parent := FBar;
  FLive.Align := alRight;
  FLive.AlignWithMargins := True;
  FLive.Layout := tlCenter;
  FLive.ShowAccelChar := False;
  FLive.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsLive);

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;
  FStatus.EllipsisPosition := epEndEllipsis;
  FStatus.Font.Color := clGrayText;
  FStatus.Caption := '';

  FImages := TImageList.Create(Self);
  FImages.Width := MulDiv(IconSize, CurrentPPI, 96);
  FImages.Height := FImages.Width;

  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuOpen), OpenClick);
  FOpenItem.Default := True;
  FFixItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuFixNone), FixClick);
  FFixItem.ShortCut := ShortCut(VK_RETURN, [ssAlt]);
  FSuppressItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuSuppress), SuppressClick);
  FMenu.Items.Add(NewLine);
  FConfigureItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuConfigure), ConfigureClick);
  FDisableItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuDisable), DisableClick);
  FExplainItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuExplain), ExplainClick);
  FIssueItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuCreateIssue), IssueClick);
  FIssueItem.Visible := False;
  FMenu.Items.Add(NewLine);
  FCopyItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuCopy), CopyClick);
  FCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  FColumnsItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuColumns), nil);
  FResetSortItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuResetSort), ResetSortClick);

  FList := TListView.Create(Self);
  FList.Parent := Self;
  FList.Align := alClient;
  FList.AlignWithMargins := True;
  FList.ViewStyle := vsReport;
  FList.OwnerData := True;
  FList.RowSelect := True;
  FList.HideSelection := False;
  FList.ReadOnly := True;
  FList.MultiSelect := True;
  FList.ColumnClick := True;
  // Spaltenköpfe lassen sich ziehen (Reihenfolge).
  FList.FullDrag := True;
  FList.ShowHint := True;
  FList.SmallImages := FImages;
  FList.PopupMenu := FMenu;
  FList.OnData := ListData;
  FList.OnSelectItem := ListSelectItem;
  FList.OnClick := ListClick;
  FList.OnDblClick := ListDblClick;
  FList.OnKeyDown := ListKeyDown;
  FList.OnColumnClick := ListColumnClick;
  FList.OnInfoTip := ListInfoTip;
  FList.OnCustomDrawItem := ListCustomDrawItem;
  FList.OnMouseUp := ListMouseUp;

  FEmpty := TLabel.Create(Self);
  FEmpty.Parent := Self;
  FEmpty.Align := alClient;
  FEmpty.AlignWithMargins := True;
  FEmpty.ShowAccelChar := False;
  FEmpty.Font.Color := clGrayText;
  FEmpty.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsEmpty);
  FEmpty.Visible := False;

  FNewTimer := TTimer.Create(Self);
  FNewTimer.Enabled := False;
  FNewTimer.Interval := NewMs;
  FNewTimer.OnTimer := NewTimerTick;

  FColumns := TAtlasFindings.ParseColumns('');
  FShowCompilerCode := True;
  BuildImages;
  BuildColumns;
  UpdateKindCaptions;
end;

destructor TAtlasProblemsFrame.Destroy;
begin
  FreeAndNil(FView);
  inherited Destroy;
end;

procedure TAtlasProblemsFrame.CreateWnd;
var
  Category: Integer;
begin
  inherited CreateWnd;
  // Die Einträge der Auswahllisten brauchen ein Fenster: erst jetzt füllen, Auswahl aus dem Modell.
  Category := 0;
  if FView.Filter.OneCategory then
    Category := Ord(FView.Filter.Category) + 1;
  FUpdating := True;
  try
    FillCombo(FScope, FScopeTexts, Ord(FView.Filter.Scope));
    FillCombo(FCategory, FCategoryTexts, Category);
    FillCombo(FGrouping, FGroupingTexts, Ord(FView.Grouping));
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasProblemsFrame.FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer);
var
  mText: string;
begin
  if ACombo.Items.Count = 0 then
    for mText in ATexts do
      ACombo.Items.Add(mText);
  if ACombo.ItemIndex < 0 then
    ACombo.ItemIndex := AIndex;
end;

function TAtlasProblemsFrame.AddMenuItem(AParent: TMenuItem; const ACaption: string;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  if AParent = nil then
    FMenu.Items.Add(Result)
  else
    AParent.Add(Result);
end;

function TAtlasProblemsFrame.AddCombo(AWidth: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := FBar;
  Result.Style := csDropDownList;
  Result.Top := MulDiv(3, CurrentPPI, 96);
  Result.Left := MulDiv(4, CurrentPPI, 96);
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasProblemsFrame.ListBack: TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular; global käme im dunklen Thema Weiß.
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Color));
end;

function TAtlasProblemsFrame.ListText: TColor;
begin
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Font.Color));
end;

procedure TAtlasProblemsFrame.BuildImages;
var
  Kind: TAtlasFindingKind;
  Bitmap: TBitmap;
  Size, Pass: Integer;
  mSignals: TAtlasSignals;
  mSignal: TAtlasSignal;
begin
  // Zuerst die drei Arten, dahinter dieselben Formen ausgegraut für nicht geöffnete Units (#1108): aufgehellt bzw.
  // abgedunkelt zur Fläche der Liste, damit Fehler weiter von Warnungen unterscheidbar bleiben.
  FImagesBack := ListBack;
  FImages.Clear;
  Size := FImages.Width;
  // Signalfarben der Liste (#1255): hell kräftig mit dunklem Rand, dunkel hell mit dunklem Zeichen.
  mSignals := TAtlasColors.ForBackground(TAtlasColor(FImagesBack)).Signals;
  for Pass := 0 to 1 do
    for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    begin
      mSignal := mSignals.Get(TAtlasFindingIcon.SignalOf(Kind));
      if Pass = 1 then
      begin
        mSignal.Fill := DimmedIconColor(mSignal.Fill, TAtlasColor(FImagesBack));
        mSignal.Ring := DimmedIconColor(mSignal.Ring, TAtlasColor(FImagesBack));
        mSignal.Mark := DimmedIconColor(mSignal.Mark, TAtlasColor(FImagesBack));
      end;
      Bitmap := TBitmap.Create;
      try
        Bitmap.SetSize(Size, Size);
        Bitmap.Canvas.Brush.Color := clFuchsia;
        Bitmap.Canvas.FillRect(Rect(0, 0, Size, Size));
        TAtlasFindingIcon.Draw(Bitmap.Canvas, Rect(0, 0, Size, Size), Kind, mSignal);
        FImages.AddMasked(Bitmap, clFuchsia);
      finally
        Bitmap.Free;
      end;
    end;
end;

function TAtlasProblemsFrame.ColumnCaption(AColumn: TAtlasFindingColumn): string;
begin
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnKind);
    TAtlasFindingColumn.Category:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCategory);
    TAtlasFindingColumn.Message:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnMessage);
    TAtlasFindingColumn.Line:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnLine);
    TAtlasFindingColumn.Location:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnLocation);
    TAtlasFindingColumn.Rule:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnRule);
    TAtlasFindingColumn.Compiler:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCompiler);
  else
    Result := '';
  end;
end;

class function TAtlasProblemsFrame.KindText(AKind: TAtlasFindingKind): string;
begin
  case AKind of
    TAtlasFindingKind.Error:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindError);
    TAtlasFindingKind.Warning:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindWarning);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.ProblemsKindInfo);
  end;
end;

class function TAtlasProblemsFrame.CategoryText(ACategory: TAtlasFindingCategory): string;
begin
  case ACategory of
    TAtlasFindingCategory.Bug:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryBug);
    TAtlasFindingCategory.Vulnerability:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryVulnerability);
    TAtlasFindingCategory.CodeSmell:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryCodeSmell);
    TAtlasFindingCategory.SecurityHotspot:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryHotspot);
    TAtlasFindingCategory.Compiler:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryCompiler);
  else
    Result := TAtlasStrings.Text(TAtlasTextId.ProblemsCategoryOther);
  end;
end;

procedure TAtlasProblemsFrame.BuildColumns;
var
  State: TAtlasFindingColumnState;
  Column: TListColumn;
  Index, Position, mWidth: Integer;
  Item: TMenuItem;
begin
  // Das Icon ist immer Spalte 0 (SmallImages zeichnet nur dort); die Reihenfolge der Anzeige setzt die
  // Spaltenreihenfolge des Kopfs.
  FShown := [TAtlasFindingColumn.Icon];
  for State in FColumns do
    if State.Visible and (State.Column <> TAtlasFindingColumn.Icon) and
      (FShowCompilerCode or (State.Column <> TAtlasFindingColumn.Compiler)) then
      FShown := FShown + [State.Column];
  FList.Columns.BeginUpdate;
  try
    FList.Columns.Clear;
    for Index := 0 to High(FShown) do
    begin
      Column := FList.Columns.Add;
      Column.Caption := ColumnCaption(FShown[Index]);
      mWidth := DefaultWidths[FShown[Index]];
      for State in FColumns do
        if (State.Column = FShown[Index]) and (State.Width > 0) then
          mWidth := State.Width;
      Column.Width := MulDiv(mWidth, CurrentPPI, 96);
    end;
  finally
    FList.Columns.EndUpdate;
  end;
  FOrderPending := True;
  ApplyOrder;
  // Menü „Spalten“: nur die abwählbaren.
  FColumnsItem.Clear;
  for Position := 0 to High(FColumns) do
    if not TAtlasFindings.IsMandatory(FColumns[Position].Column) and
      (FShowCompilerCode or (FColumns[Position].Column <> TAtlasFindingColumn.Compiler)) then
    begin
      Item := AddMenuItem(FColumnsItem, ColumnCaption(FColumns[Position].Column), ColumnToggleClick);
      Item.Checked := FColumns[Position].Visible;
      Item.Tag := Ord(FColumns[Position].Column);
    end;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrame.ApplyOrder;
var
  Order: TArray<Integer>;
  State: TAtlasFindingColumnState;
  Index: Integer;
begin
  if not FList.HandleAllocated or (not FOrderPending and (FList.Handle = FOrderHandle)) then
    Exit;
  FOrderPending := False;
  FOrderHandle := FList.Handle;
  Order := nil;
  for State in FColumns do
    for Index := 0 to High(FShown) do
      if FShown[Index] = State.Column then
        Order := Order + [Index];
  if Length(Order) = Length(FShown) then
    ListView_SetColumnOrderArray(FList.Handle, Length(Order), PInteger(@Order[0]));
end;

procedure TAtlasProblemsFrame.ReadColumns;
var
  Order: TArray<Integer>;
  Next: TArray<TAtlasFindingColumnState>;
  State: TAtlasFindingColumnState;
  Index: Integer;
  Seen: Boolean;
begin
  // Noch nicht gesetzt oder Fenster neu: FColumns ist der Stand.
  if FOrderPending or not FList.HandleAllocated or (FList.Handle <> FOrderHandle) or
    (FList.Columns.Count <> Length(FShown)) then
    Exit;
  SetLength(Order, Length(FShown));
  if not ListView_GetColumnOrderArray(FList.Handle, Length(Order), PInteger(@Order[0])) then
    Exit;
  Next := nil;
  for Index in Order do
    if (Index >= 0) and (Index <= High(FShown)) then
      Next := Next + [TAtlasFindingColumnState.Create(FShown[Index],
        MulDiv(FList.Columns[Index].Width, 96, CurrentPPI), True)];
  // Ausgeblendete behalten ihren Platz hinten mit ihrer Breite.
  for State in FColumns do
  begin
    Seen := False;
    for Index := 0 to High(Next) do
      if Next[Index].Column = State.Column then
        Seen := True;
    if not Seen then
      Next := Next + [State];
  end;
  FColumns := Next;
end;

function TAtlasProblemsFrame.ColumnsText: string;
begin
  ReadColumns;
  Result := TAtlasFindings.FormatColumns(FColumns);
end;

procedure TAtlasProblemsFrame.SetShowCompilerCode(AValue: Boolean);
begin
  if FShowCompilerCode = AValue then
    Exit;
  ReadColumns;
  FShowCompilerCode := AValue;
  BuildColumns;
  Refill;
end;

procedure TAtlasProblemsFrame.ApplySettings(AScope: TAtlasFindingScope; AGrouping: TAtlasFindingGrouping;
  const AColumns: string; ACompiler: Boolean);
var
  Filter: TAtlasFindingFilter;
begin
  FUpdating := True;
  try
    if FScope.Items.Count > Ord(AScope) then
      FScope.ItemIndex := Ord(AScope);
    if FGrouping.Items.Count > Ord(AGrouping) then
      FGrouping.ItemIndex := Ord(AGrouping);
  finally
    FUpdating := False;
  end;
  Filter := FView.Filter;
  Filter.Scope := AScope;
  Filter.Compiler := ACompiler;
  FView.Filter := Filter;
  FView.Grouping := AGrouping;
  FColumns := TAtlasFindings.ParseColumns(AColumns);
  BuildColumns;
  Refill;
end;

procedure TAtlasProblemsFrame.ApplyTierSettings(AOpenFirst: Boolean; AClosedUnits: TAtlasClosedUnits;
  AShowCleanActive: Boolean);
begin
  FOpenFirst.Down := AOpenFirst;
  FView.ClosedUnits := AClosedUnits;
  FView.ShowCleanActive := AShowCleanActive;
  FView.OpenFirst := AOpenFirst;
  Refill;
end;

function TAtlasProblemsFrame.OpenFirst: Boolean;
begin
  Result := FOpenFirst.Down;
end;

procedure TAtlasProblemsFrame.SetOpenFiles(const AActive: string; const AOpen: TArray<string>;
  AActiveChecked: Boolean);
var
  Before: string;
begin
  Before := FView.ActiveFile;
  FView.SetOpenFiles(AActive, AOpen, AActiveChecked);
  Refill;
  KeepInView(Before);
end;

procedure TAtlasProblemsFrame.KeepInView(const ABefore: string);
var
  Selected: Integer;
begin
  if SameText(ABefore, FView.ActiveFile) or (FList.Items.Count = 0) then
    Exit;
  // Editorwechsel: Die ausgewählte Zeile bleibt sichtbar; ohne Auswahl steht die angepinnte Unit oben.
  Selected := FView.SelectedRow;
  if (Selected >= 0) and (FList.Items[Selected] <> nil) then
    FList.Items[Selected].MakeVisible(False)
  else if FList.Items[0] <> nil then
    FList.Items[0].MakeVisible(False);
end;

procedure TAtlasProblemsFrame.OpenFirstClick(Sender: TObject);
begin
  if FUpdating then
    Exit;
  FView.OpenFirst := FOpenFirst.Down;
  Refill;
  if Assigned(FOnLayout) then
    FOnLayout();
end;

function TAtlasProblemsFrame.Scope: TAtlasFindingScope;
begin
  Result := FView.Filter.Scope;
end;

function TAtlasProblemsFrame.Grouping: TAtlasFindingGrouping;
begin
  Result := FView.Grouping;
end;

function TAtlasProblemsFrame.FilterFromControls: TAtlasFindingFilter;
var
  Kind: TAtlasFindingKind;
begin
  Result := FView.Filter;
  Result.Kinds := [];
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    if FKinds[Kind].Down then
      Include(Result.Kinds, Kind);
  Result.OneCategory := FCategory.ItemIndex > 0;
  if Result.OneCategory then
    Result.Category := TAtlasFindingCategory(FCategory.ItemIndex - 1);
  Result.Text := Trim(FFilter.Text);
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles: TArray<string>);
var
  Filter: TAtlasFindingFilter;
begin
  FView.BeginUpdate;
  try
    Filter := FView.Filter;
    Filter.CurrentFile := ACurrentFile;
    Filter.Files := AFiles;
    FView.Filter := Filter;
    FView.SetFindings(AFindings);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles, AOpen: TArray<string>; AActiveChecked: Boolean);
var
  Filter: TAtlasFindingFilter;
  Before: string;
begin
  Before := FView.ActiveFile;
  FView.BeginUpdate;
  try
    Filter := FView.Filter;
    Filter.CurrentFile := ACurrentFile;
    Filter.Files := AFiles;
    FView.Filter := Filter;
    FView.SetFindings(AFindings);
    FView.SetOpenFiles(ACurrentFile, AOpen, AActiveChecked);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
  KeepInView(Before);
end;

procedure TAtlasProblemsFrame.FindingsChanged;
var
  Row: TAtlasFindingRow;
  HasNew: Boolean;
begin
  HasNew := False;
  for Row in FView.Rows do
    if Row.IsNew then
      HasNew := True;
  if HasNew then
  begin
    // Neu starten: die Hervorhebung dauert ab dem letzten Zugang.
    FNewTimer.Enabled := False;
    FNewTimer.Enabled := True;
  end;
  Refill;
end;

procedure TAtlasProblemsFrame.UpdateKindCaptions;
var
  Counts: TAtlasFindingCounts;
  Kind: TAtlasFindingKind;
begin
  Counts := FView.Counts;
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    FKinds[Kind].Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsKindCount, [KindText(Kind),
      Counts.OfKind(Kind)]);
end;

procedure TAtlasProblemsFrame.ClearListSelection;
begin
  if FList.HandleAllocated then
    ListView_SetItemState(FList.Handle, -1, 0, LVIS_SELECTED);
end;

procedure TAtlasProblemsFrame.Refill;
var
  Selected: Integer;
  Count: Integer;
begin
  // Gezogene Spalten merken, bevor ein neues Fenster der Liste (Andocken) sie vergisst; dann wieder setzen.
  ReadColumns;
  // Thema gewechselt: ausgegraute Symbole zur neuen Fläche (#1108).
  if ListBack <> FImagesBack then
    BuildImages;
  ApplyOrder;
  FUpdating := True;
  try
    Count := Length(FView.Rows);
    // Virtuelle Liste: nur die Anzahl ändert sich; Bildlauf bleibt.
    if FList.Items.Count <> Count then
      FList.Items.Count := Count;
    Selected := FView.SelectedRow;
    if Selected <> FList.ItemIndex then
    begin
      ClearListSelection;
      if Selected >= 0 then
      begin
        FList.ItemIndex := Selected;
        if FList.Items[Selected] <> nil then
          FList.Items[Selected].Focused := True;
      end;
    end;
    FList.Invalidate;
  finally
    FUpdating := False;
  end;
  UpdateKindCaptions;
  FEmpty.Visible := Count = 0;
  FList.Visible := not FEmpty.Visible;
end;

procedure TAtlasProblemsFrame.SetStatus(const AText: string);
begin
  FStatus.Caption := AText;
end;

procedure TAtlasProblemsFrame.SetLive(ALive: Boolean);
begin
  if ALive then
  begin
    FLive.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsLive);
    FLive.Font.Color := $0050A030;
  end
  else
  begin
    FLive.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsPaused);
    FLive.Font.Color := clGrayText;
  end;
end;

procedure TAtlasProblemsFrame.FollowCursor(const AFileName: string; ALine: Integer);
var
  Before: string;
begin
  Before := FView.SelectedKey;
  if FView.SelectAt(AFileName, ALine) and (FView.SelectedKey <> Before) then
  begin
    Refill;
    if (FView.SelectedRow >= 0) and (FList.Items[FView.SelectedRow] <> nil) then
      FList.Items[FView.SelectedRow].MakeVisible(False);
  end;
end;

function TAtlasProblemsFrame.Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
begin
  Result := FView.Step(AForward, AFinding);
  if not Result then
    Exit;
  Refill;
  if (FView.SelectedRow >= 0) and (FList.Items[FView.SelectedRow] <> nil) then
    FList.Items[FView.SelectedRow].MakeVisible(False);
end;

function TAtlasProblemsFrame.GroupColumn: TAtlasFindingColumn;
var
  State: TAtlasFindingColumnState;
begin
  Result := TAtlasFindingColumn.Kind;
  for State in FColumns do
    if State.Visible and (State.Column <> TAtlasFindingColumn.Icon) then
      Exit(State.Column);
end;

function TAtlasProblemsFrame.CellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
var
  Finding: TAtlasFinding;
  Arrow: string;
begin
  Result := '';
  if ARow.IsSection then
  begin
    // Gezeichnet über die ganze Zeile (DrawSection); der Text steht für Bildschirmleser in der Gruppenspalte.
    if AColumn = GroupColumn then
      Result := SectionText(ARow);
    Exit;
  end;
  if ARow.IsGroup then
  begin
    if AColumn = GroupColumn then
    begin
      if ARow.Expanded then
        Arrow := #$25BE' '
      else
        Arrow := #$25B8' ';
      if ARow.Pinned then
        Arrow := Arrow + PinMark + ' ';
      Result := Arrow + ARow.Caption + ' (' + IntToStr(ARow.Count) + ')';
      // Kennzeichen der Stufe (#1108).
      if ARow.Pinned then
        Result := Result + ' ' + #$00B7 + ' ' + TAtlasStrings.Text(TAtlasTextId.ProblemsTagActive)
      else if ARow.Dimmed then
        Result := Result + ' ' + #$00B7 + ' ' + TAtlasStrings.Text(TAtlasTextId.ProblemsTagClosed);
    end;
    Exit;
  end;
  Finding := FView.Finding(ARow.Finding);
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := KindText(Finding.Kind);
    TAtlasFindingColumn.Category:
      Result := CategoryText(Finding.Category);
    TAtlasFindingColumn.Message:
      Result := Finding.MessageText(FShowCompilerCode);
    TAtlasFindingColumn.Line:
      Result := Finding.ShortLine(TAtlasFindings.LineMax);
    TAtlasFindingColumn.Location:
      Result := Finding.Location;
    TAtlasFindingColumn.Rule:
      Result := Finding.Rule;
    TAtlasFindingColumn.Compiler:
      Result := Finding.CompilerText;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

function TAtlasProblemsFrame.SectionText(const ARow: TAtlasFindingRow): string;
begin
  if ARow.IsCleanActive then
  begin
    if ARow.Checking then
      Result := PinMark + ' ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsCheckingActive, [ARow.Caption])
    else
      Result := PinMark + ' ' + CheckMark + ' ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsCleanActive, [ARow.Caption]);
    Exit;
  end;
  case ARow.Tier of
    TAtlasFindingTier.Active:
      Result := PinMark + ' ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsSectionActive, [ARow.Caption]);
    TAtlasFindingTier.Open:
      Result := TAtlasStrings.Fmt(TAtlasTextId.ProblemsSectionOpen, [ARow.Units, ARow.Count]);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.ProblemsSectionClosed, [ARow.Units, ARow.Count]);
  end;
end;

procedure TAtlasProblemsFrame.DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
var
  Bounds: TRect;
  mText: string;
  Back: TColor;
begin
  // Trennzeile über die ganze Breite: Linie oben, Text klein und fett in Sekundärfarbe; die aktive Unit ohne
  // Befunde wie eine angepinnte Gruppe, „Keine Befunde“ mit grünem Haken.
  Bounds := AItem.DisplayRect(drBounds);
  Back := ListBack;
  if ARow.Pinned then
    Back := TColor(PinnedBackColor(TAtlasColor(Back)));
  ACanvas.Brush.Color := Back;
  ACanvas.FillRect(Bounds);
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(TAtlasColor(ListText), TAtlasColor(ListBack), 0.2));
  ACanvas.MoveTo(Bounds.Left, Bounds.Top);
  ACanvas.LineTo(Bounds.Right, Bounds.Top);
  ACanvas.Font.Style := [fsBold];
  if ARow.IsCleanActive and not ARow.Checking then
    ACanvas.Font.Color := $0050A030
  else
    ACanvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(Back)));
  mText := SectionText(ARow);
  Inc(Bounds.Left, MulDiv(6, CurrentPPI, 96));
  ACanvas.Brush.Style := bsClear;
  DrawText(ACanvas.Handle, PChar(mText), Length(mText), Bounds, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  ACanvas.Brush.Style := bsSolid;
end;

function TAtlasProblemsFrame.RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
var
  Rows: TArray<TAtlasFindingRow>;
begin
  Rows := FView.Rows;
  Result := (AIndex >= 0) and (AIndex <= High(Rows));
  if Result then
    ARow := Rows[AIndex]
  else
    ARow := Default(TAtlasFindingRow);
end;

procedure TAtlasProblemsFrame.ListData(Sender: TObject; Item: TListItem);
var
  Row: TAtlasFindingRow;
  Index: Integer;
begin
  if not RowAt(Item.Index, Row) then
    Exit;
  Item.ImageIndex := -1;
  if not Row.IsGroup and not Row.IsSection then
  begin
    Item.ImageIndex := Ord(FView.Finding(Row.Finding).Kind);
    if Row.Dimmed then
      Item.ImageIndex := Item.ImageIndex + DimmedImageOffset;
  end;
  Item.Caption := '';
  Item.SubItems.Clear;
  for Index := 1 to High(FShown) do
    Item.SubItems.Add(CellText(Row, FShown[Index]));
end;

procedure TAtlasProblemsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  Row: TAtlasFindingRow;
begin
  if FUpdating or not Selected or (Item = nil) then
    Exit;
  // Trennzeilen (#1108) sind nicht wählbar.
  if RowAt(Item.Index, Row) and Row.IsSection then
  begin
    FUpdating := True;
    try
      Item.Selected := False;
    finally
      FUpdating := False;
    end;
    Exit;
  end;
  FView.Select(Item.Index);
end;

procedure TAtlasProblemsFrame.ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Hit: TListItem;
  Row: TAtlasFindingRow;
begin
  // Klick auf eine Gruppe klappt sie; Mehrfachauswahl mit Strg/Umschalt bleibt.
  if (Button <> mbLeft) or (Shift * [ssCtrl, ssShift] <> []) then
    Exit;
  Hit := FList.GetItemAt(X, Y);
  if (Hit <> nil) and RowAt(Hit.Index, Row) and Row.IsGroup and not Row.IsSection then
  begin
    FView.Toggle(Hit.Index);
    Refill;
  end;
end;

procedure TAtlasProblemsFrame.ListClick(Sender: TObject);
begin
  if FList.ItemIndex >= 0 then
    FView.Select(FList.ItemIndex);
end;

procedure TAtlasProblemsFrame.ListDblClick(Sender: TObject);
var
  Row: TAtlasFindingRow;
begin
  if RowAt(FList.ItemIndex, Row) and not Row.IsGroup and not Row.IsSection then
    Fire(FOnOpen);
end;

procedure TAtlasProblemsFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  Row, Next: TAtlasFindingRow;
  Target, Step: Integer;
begin
  // ↑/↓ springen über Trennzeilen (#1108); am Rand bleibt die Auswahl.
  if (Key = VK_UP) or (Key = VK_DOWN) then
  begin
    Step := 1;
    if Key = VK_UP then
      Step := -1;
    Target := FList.ItemIndex + Step;
    while RowAt(Target, Next) and Next.IsSection do
      Inc(Target, Step);
    if (Target <> FList.ItemIndex + Step) and (Shift * [ssShift, ssCtrl] = []) then
    begin
      Key := 0;
      if RowAt(Target, Next) then
      begin
        ClearListSelection;
        FList.ItemIndex := Target;
        FList.Items[Target].Focused := True;
        FList.Items[Target].MakeVisible(False);
        FView.Select(Target);
      end;
      Exit;
    end;
  end;
  if not RowAt(FList.ItemIndex, Row) or Row.IsSection then
    Exit;
  case Key of
    VK_RETURN:
      begin
        Key := 0;
        if Row.IsGroup then
        begin
          FView.Toggle(FList.ItemIndex);
          Refill;
        end
        else if ssAlt in Shift then
          Fire(FOnFix)
        else
          Fire(FOnOpen);
      end;
    VK_SPACE:
      if Row.IsGroup then
      begin
        Key := 0;
        FView.Toggle(FList.ItemIndex);
        Refill;
      end;
    VK_LEFT, VK_RIGHT:
      if Row.IsGroup and ((Key = VK_RIGHT) <> Row.Expanded) then
      begin
        FView.SetExpanded(Row.GroupKey, Key = VK_RIGHT);
        Key := 0;
        Refill;
      end;
    Ord('C'):
      if ssCtrl in Shift then
      begin
        Key := 0;
        CopySelection;
      end;
  end;
end;

procedure TAtlasProblemsFrame.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  if (Column = nil) or (Column.Index > High(FShown)) then
    Exit;
  FView.SortBy(FShown[Column.Index]);
  Refill;
end;

procedure TAtlasProblemsFrame.ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
var
  Row: TAtlasFindingRow;
  Finding: TAtlasFinding;
begin
  InfoTip := '';
  if (Item = nil) or not RowAt(Item.Index, Row) or Row.IsGroup or Row.IsSection then
    Exit;
  // Ganze Zeile und ganze Meldung.
  Finding := FView.Finding(Row.Finding);
  InfoTip := Finding.MessageText(FShowCompilerCode);
  if Finding.Problem.Confirmed then
    InfoTip := InfoTip + sLineBreak + TAtlasStrings.CompilerConfirmed(Finding.Problem.ConfirmedCode, FShowCompilerCode);
  if Finding.LineText <> '' then
    InfoTip := InfoTip + sLineBreak + Finding.LineText;
end;

procedure TAtlasProblemsFrame.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Row: TAtlasFindingRow;
begin
  DefaultDraw := True;
  if (Item = nil) or not RowAt(Item.Index, Row) then
    Exit;
  if Row.IsSection then
  begin
    DrawSection(Sender.Canvas, Item, Row);
    DefaultDraw := False;
    Exit;
  end;
  if Row.IsGroup then
    Sender.Canvas.Font.Style := [fsBold]
  else
    Sender.Canvas.Font.Style := [];
  // Farben ausdrücklich aus dem Stil der Liste: Nach einer geänderten Schrift (fett bei Gruppen) zeichnet die
  // Liste sonst mit den Systemfarben, im dunklen Thema also weiße Zellen. Ausgewählt laut Item.Selected
  // (LVM_GETITEMSTATE): Mit cdsSelected war in der IDE jede Zeile blau, auch die nicht gewählten.
  if Item.Selected then
  begin
    Sender.Canvas.Brush.Color := ColorToRGB(StyleServices(FList).GetSystemColor(clHighlight));
    Sender.Canvas.Font.Color := ColorToRGB(StyleServices(FList).GetSystemColor(clHighlightText));
  end
  else
  begin
    Sender.Canvas.Brush.Color := ListBack;
    Sender.Canvas.Font.Color := ListText;
    // Offene Units zuerst (#1108): aktive Unit hinterlegt, nicht geöffnete ausgegraut.
    if Row.Pinned then
      Sender.Canvas.Brush.Color := TColor(PinnedBackColor(TAtlasColor(ListBack)));
    if Row.Dimmed then
      Sender.Canvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(ListBack)));
    // Neu dazugekommen: kurz hinterlegt.
    if Row.IsNew then
      Sender.Canvas.Brush.Color := TColor(NewBackColor(TAtlasColor(ListBack)));
  end;
end;

procedure TAtlasProblemsFrame.NewTimerTick(Sender: TObject);
begin
  FNewTimer.Enabled := False;
  FView.ClearNew;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrame.ControlsChanged(Sender: TObject);
begin
  if FUpdating then
    Exit;
  FView.Filter := FilterFromControls;
  Refill;
end;

procedure TAtlasProblemsFrame.ScopeChange(Sender: TObject);
var
  Filter: TAtlasFindingFilter;
begin
  if FUpdating or (FScope.ItemIndex < 0) then
    Exit;
  Filter := FilterFromControls;
  Filter.Scope := TAtlasFindingScope(FScope.ItemIndex);
  FView.Filter := Filter;
  if Assigned(FOnScope) then
    FOnScope(Filter.Scope);
  Refill;
  if Assigned(FOnLayout) then
    FOnLayout();
end;

procedure TAtlasProblemsFrame.GroupingChange(Sender: TObject);
begin
  if FUpdating or (FGrouping.ItemIndex < 0) then
    Exit;
  FView.Grouping := TAtlasFindingGrouping(FGrouping.ItemIndex);
  Refill;
  if Assigned(FOnLayout) then
    FOnLayout();
end;

procedure TAtlasProblemsFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and FList.Visible and FList.CanFocus then
  begin
    Key := 0;
    FList.SetFocus;
    if (FList.ItemIndex < 0) and (FList.Items.Count > 0) then
      FList.ItemIndex := 0;
  end;
end;

function TAtlasProblemsFrame.SelectedRows: TArray<Integer>;
var
  Item: TListItem;
begin
  Result := nil;
  Item := FList.Selected;
  while Item <> nil do
  begin
    Result := Result + [Item.Index];
    Item := FList.GetNextItem(Item, sdAll, [isSelected]);
  end;
end;

function TAtlasProblemsFrame.Current(out AFinding: TAtlasFinding): Boolean;
var
  Row: TAtlasFindingRow;
begin
  Result := RowAt(FList.ItemIndex, Row) and not Row.IsGroup and not Row.IsSection;
  if Result then
    AFinding := FView.Finding(Row.Finding)
  else
    AFinding := Default(TAtlasFinding);
end;

function TAtlasProblemsFrame.IsRule(const AFinding: TAtlasFinding): Boolean;
begin
  // Regeln von Atlas lassen sich einstellen und unterdrücken; Compilermeldungen nicht.
  Result := (AFinding.Category <> TAtlasFindingCategory.Compiler) and (AFinding.Rule <> '');
end;

procedure TAtlasProblemsFrame.Fire(const AEvent: TAtlasFindingEvent);
var
  Finding: TAtlasFinding;
begin
  if Assigned(AEvent) and Current(Finding) then
    AEvent(Finding);
end;

function TAtlasProblemsFrame.KindButton(AKind: TAtlasFindingKind): TSpeedButton;
begin
  Result := FKinds[AKind];
end;

procedure TAtlasProblemsFrame.CopySelection;
var
  mText: string;
begin
  mText := TAtlasFindings.AsText(FView.FindingsOfRows(SelectedRows));
  if mText <> '' then
    Clipboard.AsText := mText;
end;

procedure TAtlasProblemsFrame.MenuPopup(Sender: TObject);
var
  Finding: TAtlasFinding;
  Has, Rule: Boolean;
  Count: Integer;
begin
  Has := Current(Finding);
  Rule := Has and IsRule(Finding);
  FOpenItem.Enabled := Has;
  if Has and (Finding.Problem.FixTitle <> '') then
    FFixItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuFix, [Finding.Problem.FixTitle])
  else
    FFixItem.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuFixNone);
  FFixItem.Enabled := Has and (Finding.Problem.FixTitle <> '');
  // Syntaxfehler (#1022) lassen sich nicht per Kommentar unterdrücken.
  FSuppressItem.Enabled := Rule and Finding.Problem.CanSuppress;
  FConfigureItem.Enabled := Rule;
  FDisableItem.Enabled := Rule;
  FExplainItem.Enabled := Rule;
  // Issue anlegen (#1268): auch für Compilermeldungen; mehrere markierte ergeben ein Issue mit Liste.
  Count := Length(SelectedFindings);
  FIssueItem.Visible := Assigned(FOnCreateIssue) and Assigned(FCanCreateIssue) and FCanCreateIssue();
  FIssueItem.Enabled := Count > 0;
  if Count > 1 then
    FIssueItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuCreateIssueMany, [Count])
  else
    FIssueItem.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuCreateIssue);
  FCopyItem.Enabled := Length(SelectedRows) > 0;
  FResetSortItem.Enabled := FView.SortCustom;
end;

procedure TAtlasProblemsFrame.OpenClick(Sender: TObject);
begin
  Fire(FOnOpen);
end;

procedure TAtlasProblemsFrame.FixClick(Sender: TObject);
begin
  Fire(FOnFix);
end;

procedure TAtlasProblemsFrame.SuppressClick(Sender: TObject);
begin
  Fire(FOnSuppress);
end;

procedure TAtlasProblemsFrame.ConfigureClick(Sender: TObject);
begin
  Fire(FOnConfigure);
end;

procedure TAtlasProblemsFrame.DisableClick(Sender: TObject);
begin
  Fire(FOnDisable);
end;

procedure TAtlasProblemsFrame.ExplainClick(Sender: TObject);
begin
  Fire(FOnExplain);
end;

function TAtlasProblemsFrame.SelectedFindings: TArray<TAtlasFinding>;
begin
  Result := FView.FindingsOfRows(SelectedRows);
end;

procedure TAtlasProblemsFrame.IssueClick(Sender: TObject);
var
  mFindings: TArray<TAtlasFinding>;
begin
  mFindings := SelectedFindings;
  if Assigned(FOnCreateIssue) and (Length(mFindings) > 0) then
    FOnCreateIssue(mFindings);
end;

procedure TAtlasProblemsFrame.CopyClick(Sender: TObject);
begin
  CopySelection;
end;

procedure TAtlasProblemsFrame.ColumnToggleClick(Sender: TObject);
var
  Column: TAtlasFindingColumn;
  Index: Integer;
begin
  ReadColumns;
  Column := TAtlasFindingColumn(TMenuItem(Sender).Tag);
  for Index := 0 to High(FColumns) do
    if FColumns[Index].Column = Column then
      FColumns[Index].Visible := not FColumns[Index].Visible;
  BuildColumns;
  Refill;
  if Assigned(FOnLayout) then
    FOnLayout();
end;

procedure TAtlasProblemsFrame.ResetSortClick(Sender: TObject);
begin
  FView.ResetSort;
  Refill;
end;

end.
