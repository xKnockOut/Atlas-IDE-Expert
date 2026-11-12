unit Atlas.UI.Problems.Frame;

// Inhalt des Fensters „Atlas-Prüfung“ (#909), reine VCL. Oben die
// Werkzeugleiste: Bereich (aktuelle Datei, aktuelles Projekt, Projektgruppe,
// bei offener Gruppe darunter die einzelnen Projekte, #1843), je Art ein
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
// Fehler der IDE (#1819, problems.ideErrors): Mit ShowIdeErrors gibt es die
// Spalte „Quelle“ (Atlas, Atlas + IDE, IDE) und rechts neben dem Textfilter
// die Auswahl „Atlas und IDE“, „nur Atlas“, „nur IDE“; ohne fehlen beide.
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
  Atlas.Core.Problems.Findings,
  Atlas.Core.Problems.ScopeProjects,
  Atlas.Core.Settings.ProblemsUpdate,
  Atlas.UI.Problems.ScopeBox;

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
    FCanRuleActions: TFunc<Boolean>;
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
    /// <summary>„Für diese Zeile unterdrücken“, „Regel einstellen…“ und „Regel abschalten“ sichtbar (Modul
    /// Prüfregeln läuft, #1755); nil = unsichtbar.</summary>
    property CanRuleActions: TFunc<Boolean> read FCanRuleActions write FCanRuleActions;
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
    /// <summary>Einträge und Wahl der Bereichsliste samt Einzelprojekten (#1843).</summary>
    FScopeBox: TAtlasProblemsScopeBox;
    FKinds: array[TAtlasFindingKind] of TSpeedButton;
    FCategory: TComboBox;
    FGrouping: TComboBox;
    FOpenFirst: TSpeedButton;
    FFilter: TEdit;
    /// <summary>Filter „Quelle“ (#1819); nur mit ShowIdeErrors sichtbar.</summary>
    FOrigin: TComboBox;
    FLive: TLabel;
    FList: TListView;
    FEmpty: TLabel;
    FStatus: TLabel;
    FImages: TImageList;
    FMenu: TPopupMenu;
    FNewTimer: TTimer;
    /// <summary>Einträge der Auswahllisten; gefüllt erst mit Fenster (CreateWnd).</summary>
    FCategoryTexts: TArray<string>;
    FGroupingTexts: TArray<string>;
    FOriginTexts: TArray<string>;
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
    property OriginBox: TComboBox read FOrigin;
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
    FShowIdeErrors: Boolean;
    /// <summary>Fläche, für die die ausgegrauten Symbole gebaut sind.</summary>
    FImagesBack: TColor;
    procedure BuildImages;
    /// <summary>Text einer Trennzeile bzw. der Zeile „Keine Befunde“ (#1108).</summary>
    function SectionText(const ARow: TAtlasFindingRow): string;
    procedure DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
    procedure BuildColumns;
    procedure SetShowCompilerCode(AValue: Boolean);
    procedure SetShowIdeErrors(AValue: Boolean);
    /// <summary>Spalte gerade ausgeschaltet: Compiler ohne ShowCompilerCode, Quelle ohne ShowIdeErrors.</summary>
    function ColumnSuppressed(AColumn: TAtlasFindingColumn): Boolean;
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
    /// <summary>Einzelprojekt bei Bereich „Projekt“ (#1843); '' = aktives Projekt.</summary>
    function ScopeProject: string;
    function Grouping: TAtlasFindingGrouping;
    /// <summary>Compilercodes zeigen (problems.showCompilerCode, #1024; Vorgabe an).</summary>
    property ShowCompilerCode: Boolean read FShowCompilerCode write SetShowCompilerCode;
    /// <summary>Fehler der IDE abgefragt (problems.ideErrors, #1819; Vorgabe aus): Spalte und Filter „Quelle“.
    /// </summary>
    property ShowIdeErrors: Boolean read FShowIdeErrors write SetShowIdeErrors;
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
    /// <summary>Einträge der Regel-Aktionen nach CanRuleActions zeigen und freigeben.</summary>
    procedure ShowRuleActions(ACanSuppress, ARule: Boolean);
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
    /// <summary>Einzelprojekte in der Bereichsliste (#1843): problems.window.scopeProjects und das gespeicherte
    /// Projekt (problems.window.scopeProject; gilt nur bei Bereich „Projekt“).</summary>
    procedure ApplyScopeSettings(AShowProjects: Boolean; const AProject: string);
    /// <summary>Projekte der offenen Gruppe (#1843). Fehlt das gewählte Einzelprojekt, gilt das aktive Projekt und
    /// OnLayout speichert das.</summary>
    procedure SetScopeProjects(const AProjects: TArray<TAtlasScopeProject>);
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
    /// <summary>Anzeige nach problems.update: „Live“, „Beim Speichern“ oder „Manuell“; ohne Live-Prüfung mit dem
    /// Knopf „Datei jetzt prüfen“.</summary>
    procedure SetUpdate(AMode: TAtlasProblemsUpdate);
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
  Atlas.Core.Problems.Explanation,
  Atlas.UI.Strings,
  Atlas.UI.Problems.Strings,
  Atlas.UI.Problems.KindIcon;

{$R *.dfm}

const
  /// <summary>Vorgabebreiten bei 96 dpi.</summary>
  cDefaultWidths: array[TAtlasFindingColumn] of Integer = (24, 70, 110, 320, 260, 130, 150, 130, 90);
  /// <summary>Breite der Bereichsliste bei 96 dpi; die Klappliste wird so breit wie der längste Eintrag (#1843).
  /// </summary>
  cScopeWidth = 130;
  /// <summary>Filter „Quelle“ (#1819): Breite und Abstand zum Textfilter bei 96 dpi.</summary>
  cOriginWidth = 110;
  cOriginGap = 4;
  /// <summary>Hervorhebung neuer Einträge.</summary>
  cNewMs = 1500;
  cIconSize = 16;
  /// <summary>Symbole der Arten; dahinter dieselben ausgegraut (#1108).</summary>
  cDimmedImageOffset = 3;
  cPinMark = #$D83D#$DCCC;
  cCheckMark = #$2713;

{ TAtlasProblemsFrame }

procedure TAtlasProblemsFrameMenu.BuildMenu;
begin
  FMenu := TPopupMenu.Create(Self);
  FMenu.OnPopup := MenuPopup;
  FOpenItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuOpen), OpenClick);
  FOpenItem.Default := True;
  FFixItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuFixNone), FixClick);
  FFixItem.ShortCut := ShortCut(VK_RETURN, [ssAlt]);
  FFixAllItem := AddMenuItem(nil, TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, ['…']),
    FixAllClick);
  FFixAllItem.Visible := False;
  FSuppressItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuSuppress), SuppressClick);
  FMenu.Items.Add(NewLine);
  FConfigureItem := AddMenuItem(nil, TAtlasStrings.Text(TAtlasTextId.ProblemsMenuConfigure), ConfigureClick);
  FDisableItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuDisable), DisableClick);
  FExplainItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplain), ExplainClick);
  FIssueItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCreateIssue), IssueClick);
  FIssueItem.Visible := False;
  FMenu.Items.Add(NewLine);
  FCopyItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCopy), CopyClick);
  FCopyItem.ShortCut := ShortCut(Ord('C'), [ssCtrl]);
  FColumnsItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuColumns), nil);
  FResetSortItem := AddMenuItem(nil, TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuResetSort),
    ResetSortClick);
end;

procedure TAtlasProblemsFrame.BuildBar;
var
  mKind: TAtlasFindingKind;
  mButton: TSpeedButton;
  mLeft: Integer;
begin
  FBar := TPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.BevelOuter := bvNone;
  FBar.ShowCaption := False;
  FBar.Height := MulDiv(28, CurrentPPI, 96);
  FBar.ParentBackground := True;

  FScope := AddCombo(cScopeWidth);
  FScope.OnChange := ScopeChange;
  FScopeBox := TAtlasProblemsScopeBox.Create(Self, FScope, TArray<string>.Create(
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeFile), TAtlasStrings.Text(TAtlasTextId.ProblemsScopeProject),
    TAtlasStrings.Text(TAtlasTextId.ProblemsScopeGroup)));
  mLeft := FScope.Left + FScope.Width + MulDiv(6, CurrentPPI, 96);
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    mButton := TSpeedButton.Create(Self);
    mButton.Parent := FBar;
    mButton.Top := MulDiv(2, CurrentPPI, 96);
    mButton.Height := MulDiv(22, CurrentPPI, 96);
    mButton.Width := MulDiv(78, CurrentPPI, 96);
    mButton.Left := mLeft;
    mButton.Flat := True;
    // Je Umschalter eine eigene Gruppe: unabhängig an und aus.
    mButton.GroupIndex := Ord(mKind) + 1;
    mButton.AllowAllUp := True;
    mButton.Down := True;
    mButton.OnClick := ControlsChanged;
    FKinds[mKind] := mButton;
    Inc(mLeft, mButton.Width + MulDiv(2, CurrentPPI, 96));
  end;
  FCategoryTexts := [TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryAll),
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
  FOpenFirst.Caption := cPinMark + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOpenFirst);
  FOpenFirst.Hint := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOpenFirstHint);
  FOpenFirst.ShowHint := True;
  FOpenFirst.OnClick := OpenFirstClick;
  FFilter := TEdit.Create(Self);
  FFilter.Parent := FBar;
  FFilter.Top := MulDiv(3, CurrentPPI, 96);
  FFilter.Left := FOpenFirst.Left + FOpenFirst.Width + MulDiv(4, CurrentPPI, 96);
  FFilter.Width := MulDiv(200, CurrentPPI, 96);
  FFilter.TextHint := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsFilterHint);
  FFilter.OnChange := ControlsChanged;
  FFilter.OnKeyDown := FilterKeyDown;
  // Filter „Quelle“ (#1819): erst mit ShowIdeErrors sichtbar.
  FOriginTexts := [TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginAll),
    TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginAtlas),
    TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOriginIde)];
  FOrigin := AddCombo(cOriginWidth);
  FOrigin.Left := FFilter.Left + FFilter.Width + MulDiv(cOriginGap, CurrentPPI, 96);
  FOrigin.Visible := False;
  FOrigin.OnChange := ControlsChanged;
  FLive := TLabel.Create(Self);
  FLive.Parent := FBar;
  FLive.Align := alRight;
  FLive.AlignWithMargins := True;
  FLive.Layout := tlCenter;
  FLive.ShowAccelChar := False;
  FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsLive);
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
  FImages.Width := MulDiv(cIconSize, CurrentPPI, 96);
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
  FEmpty.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsEmpty);
  FEmpty.Visible := False;

  FNewTimer := TTimer.Create(Self);
  FNewTimer.Enabled := False;
  FNewTimer.Interval := cNewMs;
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
  FreeAndNil(FScopeBox);
  inherited Destroy;
end;

procedure TAtlasProblemsFrame.CreateWnd;
var
  mCategory: Integer;
begin
  inherited CreateWnd;
  // Die Einträge der Auswahllisten brauchen ein Fenster: erst jetzt füllen, Auswahl aus dem Modell.
  mCategory := 0;
  if FView.Filter.OneCategory then
  begin
    mCategory := Ord(FView.Filter.Category) + 1;
  end;
  FUpdating := True;
  try
    FScopeBox.Fill;
    FillCombo(FCategory, FCategoryTexts, mCategory);
    FillCombo(FGrouping, FGroupingTexts, Ord(FView.Grouping));
    FillCombo(FOrigin, FOriginTexts, Ord(FView.Filter.Origin));
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
  mKind: TAtlasFindingKind;
  mBitmap: TBitmap;
  mSize, mPass: Integer;
  mSignals: TAtlasSignals;
  mSignal: TAtlasSignal;
begin
  // Zuerst die drei Arten, dahinter dieselben Formen ausgegraut für nicht geöffnete Units (#1108): aufgehellt bzw.
  // abgedunkelt zur Fläche der Liste, damit Fehler weiter von Warnungen unterscheidbar bleiben.
  FImagesBack := ListBack;
  FImages.Clear;
  mSize := FImages.Width;
  // Signalfarben der Liste (#1255): hell kräftig mit dunklem Rand, dunkel hell mit dunklem Zeichen.
  mSignals := TAtlasColors.ForBackground(TAtlasColor(FImagesBack)).Signals;
  for mPass := 0 to 1 do
  begin
    for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
    begin
      mSignal := mSignals.Get(TAtlasFindingIcon.SignalOf(mKind));
      if mPass = 1 then
      begin
        mSignal.Fill := DimmedIconColor(mSignal.Fill, TAtlasColor(FImagesBack));
        mSignal.Ring := DimmedIconColor(mSignal.Ring, TAtlasColor(FImagesBack));
        mSignal.Mark := DimmedIconColor(mSignal.Mark, TAtlasColor(FImagesBack));
      end;
      mBitmap := TBitmap.Create;
      try
        mBitmap.SetSize(mSize, mSize);
        mBitmap.Canvas.Brush.Color := clFuchsia;
        mBitmap.Canvas.FillRect(Rect(0, 0, mSize, mSize));
        TAtlasFindingIcon.Draw(mBitmap.Canvas, Rect(0, 0, mSize, mSize), mKind, mSignal);
        FImages.AddMasked(mBitmap, clFuchsia);
      finally
        mBitmap.Free;
      end;
    end;
  end;
end;

function TAtlasProblemsFrameList.ColumnCaption(AColumn: TAtlasFindingColumn): string;
begin
  case AColumn of
    TAtlasFindingColumn.Kind:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnKind);
    TAtlasFindingColumn.Category:
      Result := TAtlasStrings.Text(TAtlasTextId.ProblemsColumnCategory);
    TAtlasFindingColumn.Message:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnMessage);
    TAtlasFindingColumn.Line:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnLine);
    TAtlasFindingColumn.Location:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnLocation);
    TAtlasFindingColumn.Rule:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnRule);
    TAtlasFindingColumn.Compiler:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnCompiler);
    TAtlasFindingColumn.Source:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsColumnSource);
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
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryBug);
    TAtlasFindingCategory.Vulnerability:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryVulnerability);
    TAtlasFindingCategory.CodeSmell:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryCodeSmell);
    TAtlasFindingCategory.SecurityHotspot:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryHotspot);
    TAtlasFindingCategory.Compiler:
      Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryCompiler);
  else
    Result := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsCategoryOther);
  end;
end;

/// <summary>Breite der Spalte AColumn bei 96 dpi: gespeichert oder Vorgabe.</summary>
function ColumnWidth(const AColumns: TArray<TAtlasFindingColumnState>; AColumn: TAtlasFindingColumn): Integer;
var
  mState: TAtlasFindingColumnState;
begin
  Result := cDefaultWidths[AColumn];
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
  mState: TAtlasFindingColumnState;
  mColumn: TListColumn;
  mIndex, mPosition: Integer;
  mItem: TMenuItem;
begin
  // Das Icon ist immer Spalte 0 (SmallImages zeichnet nur dort); die Reihenfolge der Anzeige setzt die
  // Spaltenreihenfolge des Kopfs.
  FShown := [TAtlasFindingColumn.Icon];
  for mState in FColumns do
  begin
    if mState.Visible and (mState.Column <> TAtlasFindingColumn.Icon) and not ColumnSuppressed(mState.Column) then
    begin
      FShown := FShown + [mState.Column];
    end;
  end;
  FList.Columns.BeginUpdate;
  try
    FList.Columns.Clear;
    for mIndex := 0 to High(FShown) do
    begin
      mColumn := FList.Columns.Add;
      mColumn.Caption := ColumnCaption(FShown[mIndex]);
      mColumn.Width := MulDiv(ColumnWidth(FColumns, FShown[mIndex]), CurrentPPI, 96);
    end;
  finally
    FList.Columns.EndUpdate;
  end;
  FOrderPending := True;
  ApplyOrder;
  // Menü „Spalten“: nur die abwählbaren.
  FColumnsItem.Clear;
  for mPosition := 0 to High(FColumns) do
  begin
    if not TAtlasFindings.IsMandatory(FColumns[mPosition].Column) and
      not ColumnSuppressed(FColumns[mPosition].Column) then
    begin
      mItem := AddMenuItem(FColumnsItem, ColumnCaption(FColumns[mPosition].Column), ColumnToggleClick);
      mItem.Checked := FColumns[mPosition].Visible;
      mItem.Tag := Ord(FColumns[mPosition].Column);
    end;
  end;
  FList.Invalidate;
end;

procedure TAtlasProblemsFrameList.ApplyOrder;
var
  mOrder: TArray<Integer>;
  mState: TAtlasFindingColumnState;
  mIndex: Integer;
begin
  if not FList.HandleAllocated or (not FOrderPending and (FList.Handle = FOrderHandle)) then
  begin
    Exit;
  end;
  FOrderPending := False;
  FOrderHandle := FList.Handle;
  mOrder := nil;
  for mState in FColumns do
  begin
    for mIndex := 0 to High(FShown) do
    begin
      if FShown[mIndex] = mState.Column then
      begin
        mOrder := mOrder + [mIndex];
      end;
    end;
  end;
  if Length(mOrder) = Length(FShown) then
  begin
    ListView_SetColumnOrderArray(FList.Handle, Length(mOrder), PInteger(@mOrder[0]));
  end;
end;

procedure TAtlasProblemsFrameList.ReadColumns;
var
  mOrder: TArray<Integer>;
  mNext: TArray<TAtlasFindingColumnState>;
  mState: TAtlasFindingColumnState;
  mIndex: Integer;
  mSeen: Boolean;
begin
  // Noch nicht gesetzt oder Fenster neu: FColumns ist der Stand.
  if FOrderPending or not FList.HandleAllocated or (FList.Handle <> FOrderHandle) or
    (FList.Columns.Count <> Length(FShown)) then
  begin
    Exit;
  end;
  SetLength(mOrder, Length(FShown));
  if not ListView_GetColumnOrderArray(FList.Handle, Length(mOrder), PInteger(@mOrder[0])) then
  begin
    Exit;
  end;
  mNext := nil;
  for mIndex in mOrder do
  begin
    if (mIndex >= 0) and (mIndex <= High(FShown)) then
    begin
      mNext := mNext + [TAtlasFindingColumnState.Create(FShown[mIndex],
        MulDiv(FList.Columns[mIndex].Width, 96, CurrentPPI), True)];
    end;
  end;
  // Ausgeblendete behalten ihren Platz hinten mit ihrer Breite.
  for mState in FColumns do
  begin
    mSeen := False;
    for mIndex := 0 to High(mNext) do
    begin
      if mNext[mIndex].Column = mState.Column then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      mNext := mNext + [mState];
    end;
  end;
  FColumns := mNext;
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

procedure TAtlasProblemsFrameList.SetShowIdeErrors(AValue: Boolean);
var
  mFilter: TAtlasFindingFilter;
begin
  if FShowIdeErrors = AValue then
  begin
    Exit;
  end;
  ReadColumns;
  FShowIdeErrors := AValue;
  FOrigin.Visible := AValue;
  // Ausgeschaltet: wieder alle Befunde, der Filter steht beim nächsten Einschalten auf „Atlas und IDE“.
  if not AValue then
  begin
    if FOrigin.Items.Count > 0 then
    begin
      FOrigin.ItemIndex := 0;
    end;
    mFilter := FView.Filter;
    mFilter.Origin := TAtlasFindingOrigin.All;
    FView.Filter := mFilter;
  end;
  BuildColumns;
  Refill;
end;

function TAtlasProblemsFrameList.ColumnSuppressed(AColumn: TAtlasFindingColumn): Boolean;
begin
  Result := ((AColumn = TAtlasFindingColumn.Compiler) and not FShowCompilerCode) or
    ((AColumn = TAtlasFindingColumn.Source) and not FShowIdeErrors);
end;

procedure TAtlasProblemsFrame.ApplySettings(AScope: TAtlasFindingScope; AGrouping: TAtlasFindingGrouping;
  const AColumns: string; ACompiler: Boolean);
var
  mFilter: TAtlasFindingFilter;
begin
  FUpdating := True;
  try
    FScopeBox.Select(TAtlasScopeChoice.Create(AScope, FScopeBox.Choice.Project));
    if FGrouping.Items.Count > Ord(AGrouping) then
    begin
      FGrouping.ItemIndex := Ord(AGrouping);
    end;
  finally
    FUpdating := False;
  end;
  mFilter := FView.Filter;
  mFilter.Scope := AScope;
  mFilter.Compiler := ACompiler;
  FView.Filter := mFilter;
  FView.Grouping := AGrouping;
  FColumns := TAtlasFindings.ParseColumns(AColumns);
  BuildColumns;
  Refill;
end;

procedure TAtlasProblemsFrame.ApplyScopeSettings(AShowProjects: Boolean; const AProject: string);
begin
  FUpdating := True;
  try
    FScopeBox.SetShowProjects(AShowProjects);
    FScopeBox.Select(TAtlasScopeChoice.Create(FScopeBox.Choice.Scope, AProject));
  finally
    FUpdating := False;
  end;
end;

procedure TAtlasProblemsFrame.SetScopeProjects(const AProjects: TArray<TAtlasScopeProject>);
var
  mFellBack: Boolean;
begin
  FUpdating := True;
  try
    mFellBack := FScopeBox.SetProjects(AProjects);
  finally
    FUpdating := False;
  end;
  if mFellBack and Assigned(FOnLayout) then
  begin
    FOnLayout();
  end;
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
  mBefore: string;
begin
  mBefore := FView.ActiveFile;
  FView.SetOpenFiles(AActive, AOpen, AActiveChecked);
  Refill;
  KeepInView(mBefore);
end;

procedure TAtlasProblemsFrame.KeepInView(const ABefore: string);
var
  mSelected: Integer;
begin
  if SameText(ABefore, FView.ActiveFile) or (FList.Items.Count = 0) then
  begin
    Exit;
  end;
  // Editorwechsel: Die ausgewählte Zeile bleibt sichtbar; ohne Auswahl steht die angepinnte Unit oben.
  mSelected := FView.SelectedRow;
  if (mSelected >= 0) and (FList.Items[mSelected] <> nil) then
  begin
    FList.Items[mSelected].MakeVisible(False);
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

function TAtlasProblemsFrameList.ScopeProject: string;
begin
  Result := FScopeBox.Choice.Project;
end;

function TAtlasProblemsFrameList.Grouping: TAtlasFindingGrouping;
begin
  Result := FView.Grouping;
end;

function TAtlasProblemsFrame.FilterFromControls: TAtlasFindingFilter;
var
  mKind: TAtlasFindingKind;
begin
  Result := FView.Filter;
  Result.Kinds := [];
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    if FKinds[mKind].Down then
    begin
      Include(Result.Kinds, mKind);
    end;
  end;
  Result.OneCategory := FCategory.ItemIndex > 0;
  if Result.OneCategory then
  begin
    Result.Category := TAtlasFindingCategory(FCategory.ItemIndex - 1);
  end;
  Result.Text := Trim(FFilter.Text);
  Result.Origin := TAtlasFindingOrigin.All;
  if FShowIdeErrors and (FOrigin.ItemIndex > 0) then
  begin
    Result.Origin := TAtlasFindingOrigin(FOrigin.ItemIndex);
  end;
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles: TArray<string>);
var
  mFilter: TAtlasFindingFilter;
begin
  FView.BeginUpdate;
  try
    mFilter := FView.Filter;
    mFilter.CurrentFile := ACurrentFile;
    mFilter.Files := AFiles;
    FView.Filter := mFilter;
    FView.SetFindings(AFindings);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
end;

procedure TAtlasProblemsFrame.SetFindings(const AFindings: TArray<TAtlasFinding>; const ACurrentFile: string;
  const AFiles, AOpen: TArray<string>; AActiveChecked: Boolean);
var
  mFilter: TAtlasFindingFilter;
  mBefore: string;
begin
  mBefore := FView.ActiveFile;
  FView.BeginUpdate;
  try
    mFilter := FView.Filter;
    mFilter.CurrentFile := ACurrentFile;
    mFilter.Files := AFiles;
    FView.Filter := mFilter;
    FView.SetFindings(AFindings);
    FView.SetOpenFiles(ACurrentFile, AOpen, AActiveChecked);
  finally
    FView.EndUpdate;
  end;
  FindingsChanged;
  KeepInView(mBefore);
end;

procedure TAtlasProblemsFrame.FindingsChanged;
var
  mRow: TAtlasFindingRow;
  mHasNew: Boolean;
begin
  mHasNew := False;
  for mRow in FView.Rows do
  begin
    if mRow.IsNew then
    begin
      mHasNew := True;
    end;
  end;
  if mHasNew then
  begin
    // Neu starten: die Hervorhebung dauert ab dem letzten Zugang.
    FNewTimer.Enabled := False;
    FNewTimer.Enabled := True;
  end;
  Refill;
end;

procedure TAtlasProblemsFrameList.UpdateKindCaptions;
var
  mCounts: TAtlasFindingCounts;
  mKind: TAtlasFindingKind;
begin
  mCounts := FView.Counts;
  for mKind := Low(TAtlasFindingKind) to High(TAtlasFindingKind) do
  begin
    FKinds[mKind].Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsKindCount, [KindText(mKind),
      mCounts.OfKind(mKind)]);
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
  mSelected: Integer;
  mCount: Integer;
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
    mCount := Length(FView.Rows);
    // Virtuelle Liste: nur die Anzahl ändert sich; Bildlauf bleibt.
    if FList.Items.Count <> mCount then
    begin
      FList.Items.Count := mCount;
    end;
    mSelected := FView.SelectedRow;
    if mSelected <> FList.ItemIndex then
    begin
      ClearListSelection;
      if mSelected >= 0 then
      begin
        FList.ItemIndex := mSelected;
        if FList.Items[mSelected] <> nil then
        begin
          FList.Items[mSelected].Focused := True;
        end;
      end;
    end;
    FList.Invalidate;
  finally
    FUpdating := False;
  end;
  UpdateKindCaptions;
  FEmpty.Visible := mCount = 0;
  FList.Visible := not FEmpty.Visible;
end;

procedure TAtlasProblemsFrame.SetStatus(const AText: string);
begin
  FStatus.Caption := AText;
end;

procedure TAtlasProblemsFrame.SetUpdate(AMode: TAtlasProblemsUpdate);
begin
  case AMode of
    TAtlasProblemsUpdate.Save:
      FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsOnSave);
    TAtlasProblemsUpdate.Manual:
      FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsManual);
  else
    FLive.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsLive);
  end;
  if AMode = TAtlasProblemsUpdate.Live then
  begin
    FLive.Font.Color := $0050A030;
  end
  else
  begin
    FLive.Font.Color := clGrayText;
  end;
end;

procedure TAtlasProblemsFrame.FollowCursor(const AFileName: string; ALine: Integer);
var
  mBefore: string;
begin
  mBefore := FView.SelectedKey;
  if FView.SelectAt(AFileName, ALine) and (FView.SelectedKey <> mBefore) then
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
  mState: TAtlasFindingColumnState;
begin
  Result := TAtlasFindingColumn.Kind;
  for mState in FColumns do
  begin
    if mState.Visible and (mState.Column <> TAtlasFindingColumn.Icon) then
    begin
      Exit(mState.Column);
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
    Result := Result + cPinMark + ' ';
  end;
  Result := Result + ARow.Caption + ' (' + IntToStr(ARow.Count) + ')';
  if ARow.Pinned then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsTagActive);
  end
  else if ARow.Dimmed then
  begin
    Result := Result + ' ' + #$00B7 + ' ' + TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsTagClosed);
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
      Result := mFinding.ShortLine(TAtlasFindings.cLineMax);
    TAtlasFindingColumn.Location:
      Result := mFinding.Location;
    TAtlasFindingColumn.Rule:
      Result := mFinding.Rule;
    TAtlasFindingColumn.Compiler:
      Result := mFinding.CompilerText;
    TAtlasFindingColumn.Source:
      Result := mFinding.SourceText;
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
      Result := cPinMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsCheckingActive, [ARow.Caption]);
    end
    else
    begin
      Result := cPinMark + ' ' + cCheckMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsCleanActive,
        [ARow.Caption]);
    end;
    Exit;
  end;
  case ARow.Tier of
    TAtlasFindingTier.Active:
      Result := cPinMark + ' ' + TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionActive, [ARow.Caption]);
    TAtlasFindingTier.Open:
      Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionOpen, [ARow.Units, ARow.Count]);
  else
    Result := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsSectionClosed, [ARow.Units, ARow.Count]);
  end;
end;

procedure TAtlasProblemsFrameList.DrawSection(ACanvas: TCanvas; AItem: TListItem; const ARow: TAtlasFindingRow);
var
  mBounds: TRect;
  mText: string;
  mBack: TColor;
begin
  // Trennzeile über die ganze Breite: Linie oben, Text klein und fett in Sekundärfarbe; die aktive Unit ohne
  // Befunde wie eine angepinnte Gruppe, „Keine Befunde“ mit grünem Haken.
  mBounds := AItem.DisplayRect(drBounds);
  mBack := ListBack;
  if ARow.Pinned then
  begin
    mBack := TColor(PinnedBackColor(TAtlasColor(mBack)));
  end;
  ACanvas.Brush.Color := mBack;
  ACanvas.FillRect(mBounds);
  ACanvas.Pen.Color := TColor(TAtlasColorMath.Mix(TAtlasColor(ListText), TAtlasColor(ListBack), 0.2));
  ACanvas.MoveTo(mBounds.Left, mBounds.Top);
  ACanvas.LineTo(mBounds.Right, mBounds.Top);
  ACanvas.Font.Style := [fsBold];
  if ARow.IsCleanActive and not ARow.Checking then
  begin
    ACanvas.Font.Color := $0050A030;
  end
  else
  begin
    ACanvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(mBack)));
  end;
  mText := SectionText(ARow);
  Inc(mBounds.Left, MulDiv(6, CurrentPPI, 96));
  ACanvas.Brush.Style := bsClear;
  DrawText(ACanvas.Handle, PChar(mText), Length(mText), mBounds, DT_SINGLELINE or DT_VCENTER or DT_END_ELLIPSIS or
    DT_NOPREFIX);
  ACanvas.Brush.Style := bsSolid;
end;

function TAtlasProblemsFrameList.RowAt(AIndex: Integer; out ARow: TAtlasFindingRow): Boolean;
var
  mRows: TArray<TAtlasFindingRow>;
begin
  mRows := FView.Rows;
  Result := (AIndex >= 0) and (AIndex <= High(mRows));
  if Result then
  begin
    ARow := mRows[AIndex];
  end
  else
  begin
    ARow := Default(TAtlasFindingRow);
  end;
end;

procedure TAtlasProblemsFrameList.ListData(Sender: TObject; Item: TListItem);
var
  mRow: TAtlasFindingRow;
  mIndex: Integer;
begin
  if not RowAt(Item.Index, mRow) then
  begin
    Exit;
  end;
  Item.ImageIndex := -1;
  if not mRow.IsGroup and not mRow.IsSection then
  begin
    Item.ImageIndex := Ord(FView.Finding(mRow.Finding).Kind);
    if mRow.Dimmed then
    begin
      Item.ImageIndex := Item.ImageIndex + cDimmedImageOffset;
    end;
  end;
  Item.Caption := '';
  Item.SubItems.Clear;
  for mIndex := 1 to High(FShown) do
  begin
    Item.SubItems.Add(CellText(mRow, FShown[mIndex]));
  end;
end;

procedure TAtlasProblemsFrame.ListSelectItem(Sender: TObject; Item: TListItem; Selected: Boolean);
var
  mRow: TAtlasFindingRow;
begin
  if FUpdating or not Selected or (Item = nil) then
  begin
    Exit;
  end;
  // Trennzeilen (#1108) sind nicht wählbar.
  if RowAt(Item.Index, mRow) and mRow.IsSection then
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
  mHit: TListItem;
  mRow: TAtlasFindingRow;
begin
  // Klick auf eine Gruppe klappt sie; Mehrfachauswahl mit Strg/Umschalt bleibt.
  if (Button <> mbLeft) or (Shift * [ssCtrl, ssShift] <> []) then
  begin
    Exit;
  end;
  mHit := FList.GetItemAt(X, Y);
  if (mHit <> nil) and RowAt(mHit.Index, mRow) and mRow.IsGroup and not mRow.IsSection then
  begin
    FView.Toggle(mHit.Index);
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
  mRow: TAtlasFindingRow;
begin
  if RowAt(FList.ItemIndex, mRow) and not mRow.IsGroup and not mRow.IsSection then
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
  mRow: TAtlasFindingRow;
  mFinding: TAtlasFinding;
begin
  InfoTip := '';
  if (Item = nil) or not RowAt(Item.Index, mRow) or mRow.IsGroup or mRow.IsSection then
  begin
    Exit;
  end;
  // Ganze Zeile und ganze Meldung.
  mFinding := FView.Finding(mRow.Finding);
  InfoTip := mFinding.MessageText(FShowCompilerCode);
  if mFinding.Problem.Confirmed then
  begin
    InfoTip := InfoTip + sLineBreak + TAtlasStrings.CompilerConfirmed(mFinding.Problem.ConfirmedCode,
      FShowCompilerCode);
  end;
  if mFinding.LineText <> '' then
  begin
    InfoTip := InfoTip + sLineBreak + mFinding.LineText;
  end;
end;

procedure TAtlasProblemsFrameList.ListCustomDrawItem(Sender: TCustomListView; Item: TListItem;
  State: TCustomDrawState; var DefaultDraw: Boolean);
var
  mRow: TAtlasFindingRow;
begin
  DefaultDraw := True;
  if (Item = nil) or not RowAt(Item.Index, mRow) then
  begin
    Exit;
  end;
  if mRow.IsSection then
  begin
    DrawSection(Sender.Canvas, Item, mRow);
    DefaultDraw := False;
    Exit;
  end;
  if mRow.IsGroup then
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
    if mRow.Pinned then
    begin
      Sender.Canvas.Brush.Color := TColor(PinnedBackColor(TAtlasColor(ListBack)));
    end;
    if mRow.Dimmed then
    begin
      Sender.Canvas.Font.Color := TColor(DimmedTextColor(TAtlasColor(ListText), TAtlasColor(ListBack)));
    end;
    // Neu dazugekommen: kurz hinterlegt.
    if mRow.IsNew then
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
  mFilter: TAtlasFindingFilter;
begin
  if FUpdating or not FScopeBox.Pick then
  begin
    Exit;
  end;
  mFilter := FilterFromControls;
  mFilter.Scope := FScopeBox.Choice.Scope;
  FView.Filter := mFilter;
  if Assigned(FOnScope) then
  begin
    FOnScope(mFilter.Scope);
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
  mItem: TListItem;
begin
  Result := nil;
  mItem := FList.Selected;
  while mItem <> nil do
  begin
    Result := Result + [mItem.Index];
    mItem := FList.GetNextItem(mItem, sdAll, [isSelected]);
  end;
end;

function TAtlasProblemsFrameMenu.Current(out AFinding: TAtlasFinding): Boolean;
var
  mRow: TAtlasFindingRow;
begin
  Result := RowAt(FList.ItemIndex, mRow) and not mRow.IsGroup and not mRow.IsSection;
  if Result then
  begin
    AFinding := FView.Finding(mRow.Finding);
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

procedure TAtlasProblemsFrameMenu.ShowRuleActions(ACanSuppress, ARule: Boolean);
var
  mVisible: Boolean;
begin
  mVisible := Assigned(FCanRuleActions) and FCanRuleActions();
  FSuppressItem.Visible := mVisible and Assigned(FOnSuppress);
  FConfigureItem.Visible := mVisible and Assigned(FOnConfigure);
  FDisableItem.Visible := mVisible and Assigned(FOnDisable);
  FSuppressItem.Enabled := ACanSuppress;
  FConfigureItem.Enabled := ARule;
  FDisableItem.Enabled := ARule;
end;

procedure TAtlasProblemsFrameMenu.Fire(const AEvent: TAtlasFindingEvent);
var
  mFinding: TAtlasFinding;
begin
  if Assigned(AEvent) and Current(mFinding) then
  begin
    AEvent(mFinding);
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
  mFinding: TAtlasFinding;
  mHas, mRule: Boolean;
  mCount: Integer;
begin
  mHas := Current(mFinding);
  mRule := mHas and IsRule(mFinding);
  FOpenItem.Enabled := mHas;
  if mHas and (mFinding.Problem.FixTitle <> '') then
  begin
    FFixItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFix, [mFinding.Problem.FixTitle]);
  end
  else
  begin
    FFixItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuFixNone);
  end;
  FFixItem.Enabled := mHas and (mFinding.Problem.FixTitle <> '');
  // Sammelkorrektur (#1352): je Regel; welche Treffer sicher sind, entscheidet der Server.
  FFixAllItem.Visible := Assigned(FOnFixAll) and Assigned(FCanFixAll) and FCanFixAll();
  FFixAllItem.Enabled := mRule;
  if mRule then
  begin
    FFixAllItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, [mFinding.Rule]);
  end
  else
  begin
    FFixAllItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuFixAll, ['…']);
  end;
  // Regel-Aktionen liefert das Modul Prüfregeln (#1755); Syntaxfehler (#1022) lassen sich nicht per Kommentar
  // unterdrücken.
  ShowRuleActions(mRule and mFinding.Problem.CanSuppress, mRule);
  // Compilermeldungen mit Nummer erklärt der Katalog ebenfalls (#54).
  FExplainItem.Enabled := mRule or (mHas and (TAtlasRuleExplanation.MessageCode(mFinding.Problem) <> ''));
  if mRule or not FExplainItem.Enabled then
  begin
    FExplainItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplain);
  end
  else
  begin
    FExplainItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuExplainMessage);
  end;
  // Issue anlegen (#1268): auch für Compilermeldungen; mehrere markierte ergeben ein Issue mit Liste.
  mCount := Length(SelectedFindings);
  FIssueItem.Visible := Assigned(FOnCreateIssue) and Assigned(FCanCreateIssue) and FCanCreateIssue();
  FIssueItem.Enabled := mCount > 0;
  if mCount > 1 then
  begin
    FIssueItem.Caption := TAtlasProblemsStrings.Fmt(TAtlasProblemsTextId.ProblemsMenuCreateIssueMany, [mCount]);
  end
  else
  begin
    FIssueItem.Caption := TAtlasProblemsStrings.Text(TAtlasProblemsTextId.ProblemsMenuCreateIssue);
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
  mColumn: TAtlasFindingColumn;
  mIndex: Integer;
begin
  ReadColumns;
  mColumn := TAtlasFindingColumn(TMenuItem(Sender).Tag);
  for mIndex := 0 to High(FColumns) do
  begin
    if FColumns[mIndex].Column = mColumn then
    begin
      FColumns[mIndex].Visible := not FColumns[mIndex].Visible;
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
