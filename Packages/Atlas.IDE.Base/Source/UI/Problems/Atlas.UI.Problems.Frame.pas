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
// Gehe zu, Schnellkorrektur, „Alle sicheren Treffer von <Regel> korrigieren …“
// (#1352, OnFixAll; nur mit CanFixAll, fix.bulk), „Für diese Zeile
// unterdrücken“, „Regel einstellen…“, „Regel abschalten“, „Regel erklären“, Kopieren, Spalten,
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

  /// <summary>Ereignisse des Fensters „Atlas-Prüfung“ (#909); Grundlage von TAtlasProblemsFrame.</summary>
  TAtlasProblemsFrameEvents = class(TFrame)
  private
    FOnOpen: TAtlasFindingEvent;
    FOnFix: TAtlasFindingEvent;
    FOnFixAll: TAtlasFindingEvent;
    FCanFixAll: TFunc<Boolean>;
    FOnSuppress: TAtlasFindingEvent;
    FOnConfigure: TAtlasFindingEvent;
    FOnDisable: TAtlasFindingEvent;
    FOnExplain: TAtlasFindingEvent;
    FOnCreateIssue: TAtlasFindingsEvent;
    FCanCreateIssue: TFunc<Boolean>;
    FOnScope: TAtlasFindingScopeEvent;
    FOnLayout: TProc;
  public
    property OnOpen: TAtlasFindingEvent read FOnOpen write FOnOpen;
    property OnFix: TAtlasFindingEvent read FOnFix write FOnFix;
    /// <summary>„Alle sicheren Treffer von … korrigieren …“ (#1352) mit dem Befund unter dem Cursor.</summary>
    property OnFixAll: TAtlasFindingEvent read FOnFixAll write FOnFixAll;
    /// <summary>Eintrag sichtbar (fix.bulk); nil = unsichtbar.</summary>
    property CanFixAll: TFunc<Boolean> read FCanFixAll write FCanFixAll;
    property OnSuppress: TAtlasFindingEvent read FOnSuppress write FOnSuppress;
    property OnConfigure: TAtlasFindingEvent read FOnConfigure write FOnConfigure;
    property OnDisable: TAtlasFindingEvent read FOnDisable write FOnDisable;
    property OnExplain: TAtlasFindingEvent read FOnExplain write FOnExplain;
    /// <summary>„Für diesen Befund ein Issue anlegen …“ (#1268) mit den markierten Befunden.</summary>
    property OnCreateIssue: TAtlasFindingsEvent read FOnCreateIssue write FOnCreateIssue;
    /// <summary>Eintrag sichtbar (issues.create); nil = unsichtbar.</summary>
    property CanCreateIssue: TFunc<Boolean> read FCanCreateIssue write FCanCreateIssue;
    /// <summary>Bereich gewechselt: Die IDE-Schicht liefert die Dateien des Bereichs neu.</summary>
    property OnScope: TAtlasFindingScopeEvent read FOnScope write FOnScope;
    /// <summary>Bereich, Gruppierung, Spalten oder „Offene zuerst“ geändert: zum Speichern.</summary>
    property OnLayout: TProc read FOnLayout write FOnLayout;
  end;

  /// <summary>Steuerelemente des Fensters und ihre Texte.</summary>
  TAtlasProblemsFrameParts = class(TAtlasProblemsFrameEvents)
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
    FNewTimer: TTimer;
    /// <summary>Einträge der Auswahllisten; gefüllt erst mit Fenster (CreateWnd).</summary>
    FScopeTexts: TArray<string>;
    FCategoryTexts: TArray<string>;
    FGroupingTexts: TArray<string>;
    function AddMenuItem(AParent: TMenuItem; const ACaption: string; AClick: TNotifyEvent): TMenuItem;
    function AddCombo(AWidth: Integer): TComboBox;
    procedure FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer);
    /// <summary>Fläche und Text der Liste nach dem IDE-Thema.</summary>
    function ListBack: TColor;
    function ListText: TColor;
  public
    /// <summary>Umschalter der Art AKind („Warnung 3“).</summary>
    function KindButton(AKind: TAtlasFindingKind): TSpeedButton;
    class function KindText(AKind: TAtlasFindingKind): string; static;
    class function CategoryText(ACategory: TAtlasFindingCategory): string; static;
    property View: TAtlasFindingsView read FView;
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
  end;

  /// <summary>Spalten, Zellen und Zeichnen der virtuellen Liste.</summary>
  TAtlasProblemsFrameList = class(TAtlasProblemsFrameParts)
  private
    FColumnsItem: TMenuItem;
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
    procedure BuildImages;
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
    /// <summary>Text der Spalte AColumn für den Befund der Zeile ARow.</summary>
    function FindingCellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
    /// <summary>Erste sichtbare Textspalte in Anzeigereihenfolge: dort steht der Name einer Gruppe.</summary>
    function GroupColumn: TAtlasFindingColumn;
    procedure UpdateKindCaptions;
    function RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
    procedure ListData(Sender: TObject; Item: TListItem);
    procedure ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
    procedure ListCustomDrawItem(Sender: TCustomListView; Item: TListItem; State: TCustomDrawState;
      var DefaultDraw: Boolean);
    procedure ColumnToggleClick(Sender: TObject);
  public
    /// <summary>Liste neu zeichnen, Auswahl und Bildlauf bleiben.</summary>
    procedure Refill;
    /// <summary>Umschaltknopf „Offene zuerst“ gedrückt.</summary>
    function OpenFirst: Boolean;
    /// <summary>Spalten für problems.window.columns.</summary>
    function ColumnsText: string;
    function Scope: TAtlasFindingScope;
    function Grouping: TAtlasFindingGrouping;
    /// <summary>Compilercodes zeigen (problems.showCompilerCode, #1024; Vorgabe an).</summary>
    property ShowCompilerCode: Boolean read FShowCompilerCode write SetShowCompilerCode;
  end;

  /// <summary>Kontextmenü und Aktionen auf markierten Befunden.</summary>
  TAtlasProblemsFrameMenu = class(TAtlasProblemsFrameList)
  private
    FOpenItem: TMenuItem;
    FFixItem: TMenuItem;
    FFixAllItem: TMenuItem;
    FSuppressItem: TMenuItem;
    FConfigureItem: TMenuItem;
    FDisableItem: TMenuItem;
    FExplainItem: TMenuItem;
    FIssueItem: TMenuItem;
    FCopyItem: TMenuItem;
    FResetSortItem: TMenuItem;
    function SelectedRows: TArray<Integer>;
    function Current(out AFinding: TAtlasFinding): Boolean;
    function IsRule(const AFinding: TAtlasFinding): Boolean;
    procedure Fire(const AEvent: TAtlasFindingEvent);
    procedure MenuPopup(Sender: TObject);
    procedure OpenClick(Sender: TObject);
    procedure FixClick(Sender: TObject);
    procedure FixAllClick(Sender: TObject);
    procedure SuppressClick(Sender: TObject);
    procedure ConfigureClick(Sender: TObject);
    procedure DisableClick(Sender: TObject);
    procedure ExplainClick(Sender: TObject);
    procedure IssueClick(Sender: TObject);
    procedure CopyClick(Sender: TObject);
    procedure ResetSortClick(Sender: TObject);
    /// <summary>Kontextmenü der Liste anlegen.</summary>
    procedure BuildMenu;
  public
    procedure CopySelection;
    /// <summary>Markierte Befunde ohne Gruppen- und Trennzeilen, in Anzeigereihenfolge.</summary>
    function SelectedFindings: TArray<TAtlasFinding>;
  end;

  TAtlasProblemsFrame = class(TAtlasProblemsFrameMenu)
  private
    /// <summary>Leiste mit Bereich, Arten, Kategorie, Gruppierung, „Offene zuerst“ und Filter.</summary>
    procedure BuildBar;
    /// <summary>Rechter Teil der Leiste: „Offene zuerst“, Filter und „Live“.</summary>
    procedure BuildTools;
    /// <summary>Statuszeile, Symbole, Kontextmenü, Liste und Hinweis ohne Befunde.</summary>
    procedure BuildList;
    function FilterFromControls: TAtlasFindingFilter;
    /// <summary>Nach neuen Befunden: Hervorhebung neu starten, Liste neu füllen.</summary>
    procedure FindingsChanged;
    /// <summary>Hat die aktive Unit seit ABefore gewechselt: Auswahl bzw. oberste Zeile sichtbar halten.</summary>
    procedure KeepInView(const ABefore: string);
    procedure ControlsChanged(Sender: TObject);
    procedure ScopeChange(Sender: TObject);
    procedure GroupingChange(Sender: TObject);
    procedure OpenFirstClick(Sender: TObject);
    procedure FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListClick(Sender: TObject);
    procedure ListDblClick(Sender: TObject);
    procedure ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    /// <summary>↑/↓ über Trennzeilen hinweg; True, wenn die Taste verarbeitet ist.</summary>
    function MoveKey(AKey: Word; AShift: TShiftState): Boolean;
    /// <summary>Enter, Leertaste, Links/Rechts und Strg+C; True, wenn die Taste verarbeitet ist.</summary>
    function ActionKey(AKey: Word; AShift: TShiftState): Boolean;
    procedure ListColumnClick(Sender: TObject; Column: TListColumn);
    procedure ListMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure NewTimerTick(Sender: TObject);
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
    /// <summary>Markierung folgt dem Cursor (problems.window.followCursor).</summary>
    procedure FollowCursor(const AFileName: string; ALine: Integer);
    /// <summary>F8/Umschalt+F8 aus dem Editor: nächster bzw. vorheriger Befund der gefilterten Liste.</summary>
    function Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
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

procedure TAtlasProblemsFrameMenu.BuildMenu;
begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuOpen), OpenClick);
  FOpenItem.Default := True;
  FFixItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuFixNone), FixClick);
  FFixItem.ShortCut := ShortCut(VK_RETURN, [ssAlt]);
  FFixAllItem := AddMenuItem(nil, TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuFixAll, ['…']), FixAllClick);
  FFixAllItem.Visible := False;
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
end;

procedure TAtlasProblemsFrame.BuildBar;
var
  Kind: TAtlasFindingKind;
  Button: TSpeedButton;
  mLeft: Integer;
begin
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
end;

procedure TAtlasProblemsFrame.BuildTools;
begin
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
end;

procedure TAtlasProblemsFrame.BuildList;
begin
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

  BuildMenu;

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
end;

constructor TAtlasProblemsFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Der Name aus der DFM stört, wenn mehrere Frames denselben Besitzer haben.
  Name := '';
  FView := TAtlasFindingsView.Create;
  BuildBar;
  BuildTools;
  // Statuszeile, Symbole, Kontextmenü, Liste: in dieser Reihenfolge, die Ausrichtung hängt daran.
  BuildList;
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
  begin
    Category := Ord(FView.Filter.Category) + 1;
  end;
  FUpdating := True;
  try
    FillCombo(FScope, FScopeTexts, Ord(FView.Filter.Scope));
    FillCombo(FCategory, FCategoryTexts, Category);
    FillCombo(FGrouping, FGroupingTexts, Ord(FView.Grouping));
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasProblemsFrameParts.FillCombo(ACombo: TComboBox; const ATexts: TArray<string>; AIndex: Integer);
var
  mText: string;
begin
  if ACombo.Items.Count = 0 then
  begin
    ACombo.Items.BeginUpdate;
    try
      for mText in ATexts do
      begin
        ACombo.Items.Add(mText);
      end;
    finally
      ACombo.Items.EndUpdate;
    end;
  end;
  if ACombo.ItemIndex < 0 then
  begin
    ACombo.ItemIndex := AIndex;
  end;
end;

function TAtlasProblemsFrameParts.AddMenuItem(AParent: TMenuItem; const ACaption: string;
  AClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  Result.Caption := ACaption;
  Result.OnClick := AClick;
  if AParent = nil then
  begin
    FMenu.Items.Add(Result);
  end
  else
  begin
    AParent.Add(Result);
  end;
end;

function TAtlasProblemsFrameParts.AddCombo(AWidth: Integer): TComboBox;
begin
  Result := TComboBox.Create(Self);
  Result.Parent := FBar;
  Result.Style := csDropDownList;
  Result.Top := MulDiv(3, CurrentPPI, 96);
  Result.Left := MulDiv(4, CurrentPPI, 96);
  Result.Width := MulDiv(AWidth, CurrentPPI, 96);
end;

function TAtlasProblemsFrameParts.ListBack: TColor;
begin
  // Stil der Liste, nicht der globale: Die IDE themt ihre Fenster je Formular; global käme im dunklen Thema Weiß.
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Color));
end;

function TAtlasProblemsFrameParts.ListText: TColor;
begin
  Result := ColorToRGB(StyleServices(FList).GetSystemColor(FList.Font.Color));
end;

procedure TAtlasProblemsFrameList.BuildImages;
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
  begin
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
end;

function TAtlasProblemsFrameList.ColumnCaption(AColumn: TAtlasFindingColumn): string;
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

class function TAtlasProblemsFrameParts.KindText(AKind: TAtlasFindingKind): string;
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

class function TAtlasProblemsFrameParts.CategoryText(ACategory: TAtlasFindingCategory): string;
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

/// <summary>Breite der Spalte AColumn bei 96 dpi: gespeichert oder Vorgabe.</summary>
function ColumnWidth(const AColumns: TArray<TAtlasFindingColumnState>; AColumn: TAtlasFindingColumn): Integer;
var
  mState: TAtlasFindingColumnState;
begin
  Result := DefaultWidths[AColumn];
  for mState in AColumns do
  begin
    if (mState.Column = AColumn) and (mState.Width > 0) then
    begin
      Result := mState.Width;
    end;
  end;
end;

procedure TAtlasProblemsFrameList.BuildColumns;
var
  State: TAtlasFindingColumnState;
  Column: TListColumn;
  Index, Position: Integer;
  Item: TMenuItem;
begin
  // Das Icon ist immer Spalte 0 (SmallImages zeichnet nur dort); die Reihenfolge der Anzeige setzt die
  // Spaltenreihenfolge des Kopfs.
  FShown := [TAtlasFindingColumn.Icon];
  for State in FColumns do
  begin
    if State.Visible and (State.Column <> TAtlasFindingColumn.Icon) and
      (FShowCompilerCode or (State.Column <> TAtlasFindingColumn.Compiler)) then
    begin
      FShown := FShown + [State.Column];
    end;
  end;
  FList.Columns.BeginUpdate;
  try
    FList.Columns.Clear;
    for Index := 0 to High(FShown) do
    begin
      Column := FList.Columns.Add;
      Column.Caption := ColumnCaption(FShown[Index]);
      Column.Width := MulDiv(ColumnWidth(FColumns, FShown[Index]), CurrentPPI, 96);
    end;
  finally
    FList.Columns.EndUpdate;
  end;
  FOrderPending := True;
  ApplyOrder;
  // Menü „Spalten“: nur die abwählbaren.
  FColumnsItem.Clear;
  for Position := 0 to High(FColumns) do
  begin
    if not TAtlasFindings.IsMandatory(FColumns[Position].Column) and
      (FShowCompilerCode or (FColumns[Position].Column <> TAtlasFindingColumn.Compiler)) then
    begin
      Item := AddMenuItem(FColumnsItem, ColumnCaption(FColumns[Position].Column), ColumnToggleClick);
      Item.Checked := FColumns[Position].Visible;
      Item.Tag := Ord(FColumns[Position].Column);
    end;
  end;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrameList.ApplyOrder;
var
  Order: TArray<Integer>;
  State: TAtlasFindingColumnState;
  Index: Integer;
begin
  if not FList.HandleAllocated or (not FOrderPending and (FList.Handle = FOrderHandle)) then
  begin
    Exit;
  end;
  FOrderPending := False;
  FOrderHandle := FList.Handle;
  Order := nil;
  for State in FColumns do
  begin
    for Index := 0 to High(FShown) do
    begin
      if FShown[Index] = State.Column then
      begin
        Order := Order + [Index];
      end;
    end;
  end;
  if Length(Order) = Length(FShown) then
  begin
    ListView_SetColumnOrderArray(FList.Handle, Length(Order), PInteger(@Order[0]));
  end;
end;

procedure TAtlasProblemsFrameList.ReadColumns;
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
  begin
    Exit;
  end;
  SetLength(Order, Length(FShown));
  if not ListView_GetColumnOrderArray(FList.Handle, Length(Order), PInteger(@Order[0])) then
  begin
    Exit;
  end;
  Next := nil;
  for Index in Order do
  begin
    if (Index >= 0) and (Index <= High(FShown)) then
    begin
      Next := Next + [TAtlasFindingColumnState.Create(FShown[Index],
        MulDiv(FList.Columns[Index].Width, 96, CurrentPPI), True)];
    end;
  end;
  // Ausgeblendete behalten ihren Platz hinten mit ihrer Breite.
  for State in FColumns do
  begin
    Seen := False;
    for Index := 0 to High(Next) do
    begin
      if Next[Index].Column = State.Column then
      begin
        Seen := True;
      end;
    end;
    if not Seen then
    begin
      Next := Next + [State];
    end;
  end;
  FColumns := Next;
end;

function TAtlasProblemsFrameList.ColumnsText: string;
begin
  ReadColumns;
  Result := TAtlasFindings.FormatColumns(FColumns);
end;

procedure TAtlasProblemsFrameList.SetShowCompilerCode(AValue: Boolean);
begin
  if FShowCompilerCode = AValue then
  begin
    Exit;
  end;
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
    begin
      FScope.ItemIndex := Ord(AScope);
    end;
    if FGrouping.Items.Count > Ord(AGrouping) then
    begin
      FGrouping.ItemIndex := Ord(AGrouping);
    end;
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

function TAtlasProblemsFrameList.OpenFirst: Boolean;
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
  begin
    Exit;
  end;
  // Editorwechsel: Die ausgewählte Zeile bleibt sichtbar; ohne Auswahl steht die angepinnte Unit oben.
  Selected := FView.SelectedRow;
  if (Selected >= 0) and (FList.Items[Selected] <> nil) then
  begin
    FList.Items[Selected].MakeVisible(False);
  end
  else if FList.Items[0] <> nil then
  begin
    FList.Items[0].MakeVisible(False);
  end;
end;

procedure TAtlasProblemsFrame.OpenFirstClick(Sender: TObject);
begin
  if FUpdating then
  begin
    Exit;
  end;
  FView.OpenFirst := FOpenFirst.Down;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

function TAtlasProblemsFrameList.Scope: TAtlasFindingScope;
begin
  Result := FView.Filter.Scope;
end;

function TAtlasProblemsFrameList.Grouping: TAtlasFindingGrouping;
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
  begin
    if FKinds[Kind].Down then
    begin
      Include(Result.Kinds, Kind);
    end;
  end;
  Result.OneCategory := FCategory.ItemIndex > 0;
  if Result.OneCategory then
  begin
    Result.Category := TAtlasFindingCategory(FCategory.ItemIndex - 1);
  end;
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
  begin
    if Row.IsNew then
    begin
      HasNew := True;
    end;
  end;
  if HasNew then
  begin
    // Neu starten: die Hervorhebung dauert ab dem letzten Zugang.
    FNewTimer.Enabled := False;
    FNewTimer.Enabled := True;
  end;
  Refill;
end;

procedure TAtlasProblemsFrameList.UpdateKindCaptions;
var
  Counts: TAtlasFindingCounts;
  Kind: TAtlasFindingKind;
begin
  Counts := FView.Counts;
  for Kind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    FKinds[Kind].Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsKindCount, [KindText(Kind),
      Counts.OfKind(Kind)]);
  end;
end;

procedure TAtlasProblemsFrameList.ClearListSelection;
begin
  if FList.HandleAllocated then
  begin
    ListView_SetItemState(FList.Handle, -1, 0, LVIS_SELECTED);
  end;
end;

procedure TAtlasProblemsFrameList.Refill;
var
  Selected: Integer;
  Count: Integer;
begin
  // Gezogene Spalten merken, bevor ein neues Fenster der Liste (Andocken) sie vergisst; dann wieder setzen.
  ReadColumns;
  // Thema gewechselt: ausgegraute Symbole zur neuen Fläche (#1108).
  if ListBack <> FImagesBack then
  begin
    BuildImages;
  end;
  ApplyOrder;
  FUpdating := True;
  try
    Count := Length(FView.Rows);
    // Virtuelle Liste: nur die Anzahl ändert sich; Bildlauf bleibt.
    if FList.Items.Count <> Count then
    begin
      FList.Items.Count := Count;
    end;
    Selected := FView.SelectedRow;
    if Selected <> FList.ItemIndex then
    begin
      ClearListSelection;
      if Selected >= 0 then
      begin
        FList.ItemIndex := Selected;
        if FList.Items[Selected] <> nil then
        begin
          FList.Items[Selected].Focused := True;
        end;
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
    begin
      FList.Items[FView.SelectedRow].MakeVisible(False);
    end;
  end;
end;

function TAtlasProblemsFrame.Step(AForward: Boolean; out AFinding: TAtlasFinding): Boolean;
begin
  Result := FView.Step(AForward, AFinding);
  if not Result then
  begin
    Exit;
  end;
  Refill;
  if (FView.SelectedRow >= 0) and (FList.Items[FView.SelectedRow] <> nil) then
  begin
    FList.Items[FView.SelectedRow].MakeVisible(False);
  end;
end;

function TAtlasProblemsFrameList.GroupColumn: TAtlasFindingColumn;
var
  State: TAtlasFindingColumnState;
begin
  Result := TAtlasFindingColumn.Kind;
  for State in FColumns do
  begin
    if State.Visible and (State.Column <> TAtlasFindingColumn.Icon) then
    begin
      Exit(State.Column);
    end;
  end;
end;

/// <summary>Name einer Gruppe mit Pfeil, Nadel, Zahl und Kennzeichen der Stufe (#1108).</summary>
function GroupCaption(const ARow: TAtlasFindingRow): string;
begin
  if ARow.Expanded then
  begin
    Result := #$25BE' ';
  end
  else
  begin
    Result := #$25B8' ';
  end;
  if ARow.Pinned then
  begin
    Result := Result + PinMark + ' ';
  end;
  Result := Result + ARow.Caption + ' (' + IntToStr(ARow.Count) + ')';
  if ARow.Pinned then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasStrings.Text(TAtlasTextId.ProblemsTagActive);
  end
  else if ARow.Dimmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasStrings.Text(TAtlasTextId.ProblemsTagClosed);
  end;
end;

function TAtlasProblemsFrameList.FindingCellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
var
  mFinding: TAtlasFinding;
begin
  mFinding := FView.Finding(ARow.Finding);
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := KindText(mFinding.Kind);
    TAtlasFindingColumn.Category:
      Result := CategoryText(mFinding.Category);
    TAtlasFindingColumn.Message:
      Result := mFinding.MessageText(FShowCompilerCode);
    TAtlasFindingColumn.Line:
      Result := mFinding.ShortLine(TAtlasFindings.LineMax);
    TAtlasFindingColumn.Location:
      Result := mFinding.Location;
    TAtlasFindingColumn.Rule:
      Result := mFinding.Rule;
    TAtlasFindingColumn.Compiler:
      Result := mFinding.CompilerText;
  else
    // Symbol: kein Text.
    Result := '';
  end;
end;

function TAtlasProblemsFrameList.CellText(const ARow: TAtlasFindingRow; AColumn: TAtlasFindingColumn): string;
begin
  Result := '';
  if not ARow.IsSection and not ARow.IsGroup then
  begin
    Result := FindingCellText(ARow, AColumn);
  end
  else if AColumn <> GroupColumn then
  begin
    // Gruppen- und Trennzeilen haben Text nur in der Gruppenspalte.
    Exit;
  end
  else if ARow.IsSection then
  begin
    // Gezeichnet über die ganze Zeile (DrawSection); der Text steht für Bildschirmleser in der Gruppenspalte.
    Result := SectionText(ARow);
  end
  else
  begin
    Result := GroupCaption(ARow);
  end;
end;

function TAtlasProblemsFrameList.SectionText(const ARow: TAtlasFindingRow): string;
begin
  if ARow.IsCleanActive then
  begin
    if ARow.Checking then
    begin
      Result := PinMark + ' ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsCheckingActive, [ARow.Caption]);
    end
    else
    begin
      Result := PinMark + ' ' + CheckMark + ' ' + TAtlasStrings.Fmt(TAtlasTextId.ProblemsCleanActive, [ARow.Caption]);
    end;
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

procedure TAtlasProblemsFrameList.DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
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
  begin
    Back := TColor(PinnedBackColor(TAtlasColor(Back)));
  end;
  ACanvas.Brush.Color := Back;
  ACanvas.FillRect(Bounds);
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(TAtlasColor(ListText), TAtlasColor(ListBack), 0.2));
  ACanvas.MoveTo(Bounds.Left, Bounds.Top);
  ACanvas.LineTo(Bounds.Right, Bounds.Top);
  ACanvas.Font.Style := [fsBold];
  if ARow.IsCleanActive and not ARow.Checking then
  begin
    ACanvas.Font.Color := $0050A030;
  end
  else
  begin
    ACanvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(Back)));
  end;
  mText := SectionText(ARow);
  Inc(Bounds.Left, MulDiv(6, CurrentPPI, 96));
  ACanvas.Brush.Style := bsClear;
  DrawText(ACanvas.Handle, PChar(mText), Length(mText), Bounds, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  ACanvas.Brush.Style := bsSolid;
end;

function TAtlasProblemsFrameList.RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
var
  Rows: TArray<TAtlasFindingRow>;
begin
  Rows := FView.Rows;
  Result := (AIndex >= 0) and (AIndex <= High(Rows));
  if Result then
  begin
    ARow := Rows[AIndex];
  end
  else
  begin
    ARow := Default(TAtlasFindingRow);
  end;
end;

procedure TAtlasProblemsFrameList.ListData(Sender: TObject; Item: TListItem);
var
  Row: TAtlasFindingRow;
  Index: Integer;
begin
  if not RowAt(Item.Index, Row) then
  begin
    Exit;
  end;
  Item.ImageIndex := -1;
  if not Row.IsGroup and not Row.IsSection then
  begin
    Item.ImageIndex := Ord(FView.Finding(Row.Finding).Kind);
    if Row.Dimmed then
    begin
      Item.ImageIndex := Item.ImageIndex + DimmedImageOffset;
    end;
  end;
  Item.Caption := '';
  Item.SubItems.Clear;
  for Index := 1 to High(FShown) do
  begin
    Item.SubItems.Add(CellText(Row, FShown[Index]));
  end;
end;

procedure TAtlasProblemsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  Row: TAtlasFindingRow;
begin
  if FUpdating or not Selected or (Item = nil) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
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
  begin
    FView.Select(FList.ItemIndex);
  end;
end;

procedure TAtlasProblemsFrame.ListDblClick(Sender: TObject);
var
  Row: TAtlasFindingRow;
begin
  if RowAt(FList.ItemIndex, Row) and not Row.IsGroup and not Row.IsSection then
  begin
    Fire(FOnOpen);
  end;
end;

function TAtlasProblemsFrame.MoveKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mNext: TAtlasFindingRow;
  mTarget, mStep: Integer;
begin
  // ↑/↓ springen über Trennzeilen (#1108); am Rand bleibt die Auswahl.
  Result := False;
  if (AKey <> VK_UP) and (AKey <> VK_DOWN) then
  begin
    Exit;
  end;
  mStep := 1;
  if AKey = VK_UP then
  begin
    mStep := -1;
  end;
  mTarget := FList.ItemIndex + mStep;
  while RowAt(mTarget, mNext) and mNext.IsSection do
  begin
    Inc(mTarget, mStep);
  end;
  Result := (mTarget <> FList.ItemIndex + mStep) and (AShift * [ssShift, ssCtrl] = []);
  if Result and RowAt(mTarget, mNext) then
  begin
    ClearListSelection;
    FList.ItemIndex := mTarget;
    FList.Items[mTarget].Focused := True;
    FList.Items[mTarget].MakeVisible(False);
    FView.Select(mTarget);
  end;
end;

function TAtlasProblemsFrame.ActionKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mRow: TAtlasFindingRow;
begin
  Result := False;
  if not RowAt(FList.ItemIndex, mRow) or mRow.IsSection then
  begin
    Exit;
  end;
  case AKey of
    VK_RETURN, VK_SPACE:
      begin
        // Enter und Leertaste klappen Gruppen; Enter öffnet bzw. behebt (Alt) einen Befund.
        Result := mRow.IsGroup or (AKey = VK_RETURN);
        if mRow.IsGroup then
        begin
          FView.Toggle(FList.ItemIndex);
          Refill;
        end
        else if (AKey = VK_RETURN) and (ssAlt in AShift) then
        begin
          Fire(FOnFix);
        end
        else if AKey = VK_RETURN then
        begin
          Fire(FOnOpen);
        end;
      end;
    VK_LEFT, VK_RIGHT:
      begin
        Result := mRow.IsGroup and ((AKey = VK_RIGHT) <> mRow.Expanded);
        if Result then
        begin
          FView.SetExpanded(mRow.GroupKey, AKey = VK_RIGHT);
          Refill;
        end;
      end;
    Ord('C'):
      begin
        Result := ssCtrl in AShift;
        if Result then
        begin
          CopySelection;
        end;
      end;
  end;
end;

procedure TAtlasProblemsFrame.ListKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if MoveKey(Key, Shift) or ActionKey(Key, Shift) then
  begin
    Key := 0;
  end;
end;

procedure TAtlasProblemsFrame.ListColumnClick(Sender: TObject; Column: TListColumn);
begin
  if (Column = nil) or (Column.Index > High(FShown)) then
  begin
    Exit;
  end;
  FView.SortBy(FShown[Column.Index]);
  Refill;
end;

procedure TAtlasProblemsFrameList.ListInfoTip(Sender: TObject; Item: TListItem; var InfoTip: string);
var
  Row: TAtlasFindingRow;
  Finding: TAtlasFinding;
begin
  InfoTip := '';
  if (Item = nil) or not RowAt(Item.Index, Row) or Row.IsGroup or Row.IsSection then
  begin
    Exit;
  end;
  // Ganze Zeile und ganze Meldung.
  Finding := FView.Finding(Row.Finding);
  InfoTip := Finding.MessageText(FShowCompilerCode);
  if Finding.Problem.Confirmed then
  begin
    InfoTip := InfoTip + sLineBreak + TAtlasStrings.CompilerConfirmed(Finding.Problem.ConfirmedCode, FShowCompilerCode);
  end;
  if Finding.LineText <> '' then
  begin
    InfoTip := InfoTip + sLineBreak + Finding.LineText;
  end;
end;

procedure TAtlasProblemsFrameList.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  Row: TAtlasFindingRow;
begin
  DefaultDraw := True;
  if (Item = nil) or not RowAt(Item.Index, Row) then
  begin
    Exit;
  end;
  if Row.IsSection then
  begin
    DrawSection(Sender.Canvas, Item, Row);
    DefaultDraw := False;
    Exit;
  end;
  if Row.IsGroup then
  begin
    Sender.Canvas.Font.Style := [fsBold];
  end
  else
  begin
    Sender.Canvas.Font.Style := [];
  end;
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
    begin
      Sender.Canvas.Brush.Color := TColor(PinnedBackColor(TAtlasColor(ListBack)));
    end;
    if Row.Dimmed then
    begin
      Sender.Canvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(ListBack)));
    end;
    // Neu dazugekommen: kurz hinterlegt.
    if Row.IsNew then
    begin
      Sender.Canvas.Brush.Color := TColor(NewBackColor(TAtlasColor(ListBack)));
    end;
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
  begin
    Exit;
  end;
  FView.Filter := FilterFromControls;
  Refill;
end;

procedure TAtlasProblemsFrame.ScopeChange(Sender: TObject);
var
  Filter: TAtlasFindingFilter;
begin
  if FUpdating or (FScope.ItemIndex < 0) then
  begin
    Exit;
  end;
  Filter := FilterFromControls;
  Filter.Scope := TAtlasFindingScope(FScope.ItemIndex);
  FView.Filter := Filter;
  if Assigned(FOnScope) then
  begin
    FOnScope(Filter.Scope);
  end;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrame.GroupingChange(Sender: TObject);
begin
  if FUpdating or (FGrouping.ItemIndex < 0) then
  begin
    Exit;
  end;
  FView.Grouping := TAtlasFindingGrouping(FGrouping.ItemIndex);
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrame.FilterKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if (Key = VK_DOWN) and FList.Visible and FList.CanFocus then
  begin
    Key := 0;
    FList.SetFocus;
    if (FList.ItemIndex < 0) and (FList.Items.Count > 0) then
    begin
      FList.ItemIndex := 0;
    end;
  end;
end;

function TAtlasProblemsFrameMenu.SelectedRows: TArray<Integer>;
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

function TAtlasProblemsFrameMenu.Current(out AFinding: TAtlasFinding): Boolean;
var
  Row: TAtlasFindingRow;
begin
  Result := RowAt(FList.ItemIndex, Row) and not Row.IsGroup and not Row.IsSection;
  if Result then
  begin
    AFinding := FView.Finding(Row.Finding);
  end
  else
  begin
    AFinding := Default(TAtlasFinding);
  end;
end;

function TAtlasProblemsFrameMenu.IsRule(const AFinding: TAtlasFinding): Boolean;
begin
  // Regeln von Atlas lassen sich einstellen und unterdrücken; Compilermeldungen nicht.
  Result := (AFinding.Category <> TAtlasFindingCategory.Compiler) and (AFinding.Rule <> '');
end;

procedure TAtlasProblemsFrameMenu.Fire(const AEvent: TAtlasFindingEvent);
var
  Finding: TAtlasFinding;
begin
  if Assigned(AEvent) and Current(Finding) then
  begin
    AEvent(Finding);
  end;
end;

function TAtlasProblemsFrameParts.KindButton(AKind: TAtlasFindingKind): TSpeedButton;
begin
  Result := FKinds[AKind];
end;

procedure TAtlasProblemsFrameMenu.CopySelection;
var
  mText: string;
begin
  mText := TAtlasFindings.AsText(FView.FindingsOfRows(SelectedRows));
  if mText <> '' then
  begin
    Clipboard.AsText := mText;
  end;
end;

procedure TAtlasProblemsFrameMenu.MenuPopup(Sender: TObject);
var
  Finding: TAtlasFinding;
  Has, Rule: Boolean;
  Count: Integer;
begin
  Has := Current(Finding);
  Rule := Has and IsRule(Finding);
  FOpenItem.Enabled := Has;
  if Has and (Finding.Problem.FixTitle <> '') then
  begin
    FFixItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuFix, [Finding.Problem.FixTitle]);
  end
  else
  begin
    FFixItem.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuFixNone);
  end;
  FFixItem.Enabled := Has and (Finding.Problem.FixTitle <> '');
  // Sammelkorrektur (#1352): je Regel; welche Treffer sicher sind, entscheidet der Server.
  FFixAllItem.Visible := Assigned(FOnFixAll) and Assigned(FCanFixAll) and FCanFixAll();
  FFixAllItem.Enabled := Rule;
  if Rule then
  begin
    FFixAllItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuFixAll, [Finding.Rule]);
  end
  else
  begin
    FFixAllItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuFixAll, ['…']);
  end;
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
  begin
    FIssueItem.Caption := TAtlasStrings.Fmt(TAtlasTextId.ProblemsMenuCreateIssueMany, [Count]);
  end
  else
  begin
    FIssueItem.Caption := TAtlasStrings.Text(TAtlasTextId.ProblemsMenuCreateIssue);
  end;
  FCopyItem.Enabled := Length(SelectedRows) > 0;
  FResetSortItem.Enabled := FView.SortCustom;
end;

procedure TAtlasProblemsFrameMenu.OpenClick(Sender: TObject);
begin
  Fire(FOnOpen);
end;

procedure TAtlasProblemsFrameMenu.FixClick(Sender: TObject);
begin
  Fire(FOnFix);
end;

procedure TAtlasProblemsFrameMenu.FixAllClick(Sender: TObject);
begin
  Fire(FOnFixAll);
end;

procedure TAtlasProblemsFrameMenu.SuppressClick(Sender: TObject);
begin
  Fire(FOnSuppress);
end;

procedure TAtlasProblemsFrameMenu.ConfigureClick(Sender: TObject);
begin
  Fire(FOnConfigure);
end;

procedure TAtlasProblemsFrameMenu.DisableClick(Sender: TObject);
begin
  Fire(FOnDisable);
end;

procedure TAtlasProblemsFrameMenu.ExplainClick(Sender: TObject);
begin
  Fire(FOnExplain);
end;

function TAtlasProblemsFrameMenu.SelectedFindings: TArray<TAtlasFinding>;
begin
  Result := FView.FindingsOfRows(SelectedRows);
end;

procedure TAtlasProblemsFrameMenu.IssueClick(Sender: TObject);
var
  mFindings: TArray<TAtlasFinding>;
begin
  mFindings := SelectedFindings;
  if Assigned(FOnCreateIssue) and (Length(mFindings) > 0) then
  begin
    FOnCreateIssue(mFindings);
  end;
end;

procedure TAtlasProblemsFrameMenu.CopyClick(Sender: TObject);
begin
  CopySelection;
end;

procedure TAtlasProblemsFrameList.ColumnToggleClick(Sender: TObject);
var
  Column: TAtlasFindingColumn;
  Index: Integer;
begin
  ReadColumns;
  Column := TAtlasFindingColumn(TMenuItem(Sender).Tag);
  for Index := 0 to High(FColumns) do
  begin
    if FColumns[Index].Column = Column then
    begin
      FColumns[Index].Visible := not FColumns[Index].Visible;
    end;
  end;
  BuildColumns;
  Refill;
  if Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
end;

procedure TAtlasProblemsFrameMenu.ResetSortClick(Sender: TObject);
begin
  FView.ResetSort;
  Refill;
end;

end.
