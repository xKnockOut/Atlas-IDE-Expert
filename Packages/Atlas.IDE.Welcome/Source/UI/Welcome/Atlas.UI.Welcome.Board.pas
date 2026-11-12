unit Atlas.UI.Welcome.Board;

// Alle Atlas-Bereiche in einem Frame (#753): oben der Kopf (abschaltbar),
// darunter die Bereiche in Spalten nach TAtlasWelcomeLayout.Cells. Im
// Atlas-Layout steht dieser Frame als ein Bereich „Atlas“ oben auf der
// Willkommensseite, im Fenster „Atlas-Start“ mit derselben Anordnung, die
// bei schmalem Fenster Spalten untereinander faltet (AutoFold). Der Inhalt
// scrollt, wenn er höher ist als der Platz. Rebuild legt die Bereichs-Frames
// über TAtlasWelcomeViews an und behält vorhandene, solange ihr Bereich
// sichtbar bleibt.
// Frei anordnen (#767), mit Source und welcomePage.customLayout:
// - Leiste unter dem Kopf: Stift „Seite anpassen“/„Fertig“ und
//   Layout-Umschalter; im Bearbeitungsmodus dazu Spalten, „Bereich
//   hinzufügen“ und „Zurücksetzen“.
// - Im Bearbeitungsmodus je Bereich Griff (Ziehen, Strg+Pfeiltasten), Breite
//   und Auge; eine Einfügelinie zeigt das Ziel (ohne Ziehen: Ende der Spalte
//   mit dem meisten Platz, ein Klick auf freie Fläche setzt sie); unten die
//   Leiste „Ausgeblendet“ zum Einblenden per Klick oder Ziehen.
// - Rechtsklick auf einen Bereich: „Ausblenden“ (wie #628, mit
//   „Rückgängig“), „Einstellungen dazu …“ und „Seite anpassen“.
// Zweispaltige Bereiche und die Reihenfolge rechnet TAtlasWelcomeFlow.
// Scrollen (#1440): Die VCL-Scrollbox scrollt nicht selbst mit dem Mausrad,
// und WM_MOUSEWHEEL landet beim Fenster unter dem Zeiger bzw. beim
// fokussierten Steuerelement des Formulars (in der IDE oft der Editor). Die
// Tafel nimmt das Rad deshalb an einer Stelle für alle Bereiche ab
// (Application.OnMessage, solange der Zeiger über ihr steht): Die innerste
// Fläche, die in die Richtung noch scrollen kann (z. B. „Neu in Atlas“),
// bekommt es zuerst, danach die Seite. Bild auf/ab und Pos1/Ende scrollen die
// Seite, solange kein Eingabefeld und keine Liste den Fokus hat; ein Klick auf
// freie Fläche gibt ihr den Fokus. Beim Ziehen eines Bereichs scrollt sie am
// oberen und unteren Rand von selbst. Die Schritte rechnet
// TAtlasWelcomeScroll.

interface

uses
  Atlas.UI.Welcome.Strings,
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Vcl.AppEvnts,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.Layout,
  Atlas.Core.Welcome.Scroll,
  Atlas.UI.Welcome.Frame,
  Atlas.UI.Welcome.Header,
  Atlas.UI.Welcome.Arrange;

type
  /// <summary>Name abfragen (Neues Layout, Umbenennen); False = abgebrochen.</summary>
  TAtlasWelcomeAskName = reference to function(const APrompt: string; var AName: string): Boolean;
  /// <summary>Rückfrage bzw. Hinweis; True = ja.</summary>
  TAtlasWelcomeConfirm = reference to function(const AText: string; AQuestion: Boolean): Boolean;

  TAtlasWelcomeBoardFrame = class;

  /// <summary>Scrollen der Tafel (#1440): Mausrad über allen Bereichen, Bild auf/ab und Pos1/Ende, Scrollen am
  /// Rand beim Ziehen eines Bereichs.</summary>
  TAtlasWelcomeBoardScroller = class(TComponent)
  private
    FBoard: TAtlasWelcomeBoardFrame;
    FEvents: TApplicationEvents;
    FWheelRest: Integer;
    FEdgeTimer: TTimer;
    FEdgePoint: TPoint;
    procedure AppMessage(var Msg: TMsg; var Handled: Boolean);
    /// <summary>Mausrad über der Tafel; True = die Nachricht gehört ihr.</summary>
    function WheelMessage(const AMsg: TMsg): Boolean;
    function KeyMessage(const AMsg: TMsg): Boolean;
    function ScrollArea(AControl: TWinControl; AWheelDelta: Integer): Boolean;
    function ScrollBoxArea(AControl: TScrollingWinControl; AWheelDelta: Integer): Boolean;
    function ScrollWindowArea(AControl: TWinControl; AWheelDelta: Integer): Boolean;
    function EdgeStep: Integer;
    procedure EdgeTick(Sender: TObject);
  public
    constructor Create(ABoard: TAtlasWelcomeBoardFrame); reintroduce;
    destructor Destroy; override;
    /// <summary>Keine Nachrichten und kein Takt mehr (vor dem Abbau der Bereiche).</summary>
    procedure Stop;
    /// <summary>Beim Ziehen: Zeiger an AScreen; scrollt am oberen und unteren Rand der Seite.</summary>
    procedure UpdateEdgeScroll(const AScreen: TPoint);
    /// <summary>Mausrad über AControl (#1440): die innerste Fläche, die in die Richtung noch scrollen kann, sonst
    /// die Seite. AWheelDelta wie WM_MOUSEWHEEL (positiv = nach oben). False = AControl liegt nicht in der Tafel
    /// oder nichts kann sich mehr bewegen.</summary>
    function ScrollWheel(AControl: TControl; AWheelDelta: Integer): Boolean;
    /// <summary>Seite mit Bild auf/ab bzw. Pos1/Ende scrollen; False = Position unverändert.</summary>
    function ScrollKey(AKey: TAtlasWelcomeScrollKey): Boolean;
    /// <summary>Taste der Seite zu AKey (VK_PRIOR, VK_NEXT, VK_HOME, VK_END ohne Alt); None = keine.</summary>
    class function ScrollKeyOf(AKey: Word; AShift: TShiftState): TAtlasWelcomeScrollKey; static;
    /// <summary>Behält AControl Bild auf/ab und Pos1/Ende für sich (Eingabefeld, Liste, Auswahlfeld)?</summary>
    class function OwnsScrollKeys(AControl: TControl): Boolean; static;
    /// <summary>Takt für das Scrollen am Rand beim Ziehen; läuft nur, solange gescrollt wird.</summary>
    property EdgeTimer: TTimer read FEdgeTimer;
  end;

  /// <summary>Kontextmenü eines Bereichs („Ausblenden“, „Einstellungen dazu …“, „Seite anpassen“) und die Menüs
  /// „Layout“ und „Bereich hinzufügen“ der Leiste.</summary>
  TAtlasWelcomeBoardMenus = class(TComponent)
  private
    FBoard: TAtlasWelcomeBoardFrame;
    FSectionMenu: TPopupMenu;
    FMenuId: string;
    FBarMenu: TPopupMenu;
    FOnAskName: TAtlasWelcomeAskName;
    FOnConfirm: TAtlasWelcomeConfirm;
    procedure AddSectionItem(AId: TAtlasWelcomeTextId; ATag: Integer; const AOnClick: TNotifyEvent);
    function AddBarItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
    procedure SectionMenuPopup(Sender: TObject);
    procedure SectionMenuHide(Sender: TObject);
    procedure SectionMenuSettings(Sender: TObject);
    procedure SectionMenuCustomize(Sender: TObject);
    procedure LayoutMenuSwitch(Sender: TObject);
    procedure LayoutMenuNew(Sender: TObject);
    procedure LayoutMenuRename(Sender: TObject);
    procedure LayoutMenuDelete(Sender: TObject);
    procedure AddMenuClick(Sender: TObject);
    function AskName(const APrompt: string; var AName: string): Boolean;
    function Confirm(const AText: string; AQuestion: Boolean): Boolean;
    function NameTaken(const AName: string): Boolean;
  public
    constructor Create(ABoard: TAtlasWelcomeBoardFrame); reintroduce;
    /// <summary>Menü „Layout“ bzw. „Bereich hinzufügen“ füllen, ohne es zu zeigen (auch für Tests).</summary>
    procedure BuildLayoutMenu;
    procedure BuildAddMenu;
    /// <summary>Kontextmenü für den Bereich AId vorbereiten (auch für Tests).</summary>
    procedure PrepareSectionMenu(const AId: string);
    /// <summary>Rechtsklick „Ausblenden“ (#628-Weg) an Titel und Fläche von AFrame; AOn = False nimmt es ab.
    /// </summary>
    procedure AttachTo(AFrame: TAtlasWelcomeSectionFrame; AOn: Boolean);
    property SectionMenu: TPopupMenu read FSectionMenu;
    property BarMenu: TPopupMenu read FBarMenu;
    property OnAskName: TAtlasWelcomeAskName read FOnAskName write FOnAskName;
    property OnConfirm: TAtlasWelcomeConfirm read FOnConfirm write FOnConfirm;
  end;

  /// <summary>„Seite anpassen“ (#767): Leiste unter dem Kopf, Leiste „Ausgeblendet“, Einfügelinie, Griffe und
  /// Werkzeuge der Bereiche und das Ziehen.</summary>
  TAtlasWelcomeBoardArranger = class(TComponent)
  private type
    TDrag = record
      /// <summary>Spalte der Einfügelinie; -1 = Vorgabe.</summary>
      TargetColumn: Integer;
      TargetBefore: string;
      /// <summary>Gezogener Bereich; '' = keiner.</summary>
      Id: string;
      Hidden: Boolean;
      DropValid: Boolean;
    end;
  private
    FBoard: TAtlasWelcomeBoardFrame;
    FBar: TAtlasArrangeStrip;
    FHiddenBar: TAtlasArrangeStrip;
    FInsertLine: TPanel;
    FDrag: TDrag;
    procedure BarClick(const APart: TAtlasArrangePart);
    procedure HiddenClick(const APart: TAtlasArrangePart);
    procedure DragStart(const AId: string; AHidden: Boolean);
    procedure DragMove(const AScreen: TPoint);
    procedure DragEnd(ADrop: Boolean);
    function GripMove(const AId: string; ADirection: TAtlasWelcomeMove): Boolean;
    procedure ToolClick(const AId: string; ATool: TAtlasWelcomeTool);
    function EnsureGrip(AFrame: TAtlasWelcomeSectionFrame): TAtlasWelcomeGrip;
    function EnsureTools(AFrame: TAtlasWelcomeSectionFrame): TAtlasWelcomeSectionTools;
    /// <summary>Teile der Leiste unter dem Kopf: Stift bzw. „Fertig“, Layout, im Bearbeitungsmodus Spalten,
    /// „Bereich hinzufügen“ und „Zurücksetzen“.</summary>
    function BarParts: TArray<TAtlasArrangePart>;
    function EditingParts: TArray<TAtlasArrangePart>;
    /// <summary>Ausgeblendet: angemeldete Bereiche, deren Einstellung aus ist.</summary>
    function HiddenParts: TArray<TAtlasArrangePart>;
  public
    constructor Create(ABoard: TAtlasWelcomeBoardFrame); reintroduce;
    /// <summary>Griffe und Werkzeuge der Bereiche nach dem Bearbeitungsmodus, Kontextmenü der Bereiche.</summary>
    procedure ApplyEditing;
    procedure UpdateBars;
    /// <summary>Höhe der sichtbaren Leisten an ihren Inhalt anpassen.</summary>
    procedure FitBars;
    procedure UpdateInsertLine;
    /// <summary>Klick auf freie Fläche (Koordinaten der Scrollbox) setzt die Einfügelinie.</summary>
    procedure ClickAt(AX, AY: Integer);
    /// <summary>Einfügelinie setzen: Spalte und Bereich, vor dem eingefügt wird ('' = ans Ende); -1 = Vorgabe
    /// (Ende der Spalte mit dem meisten Platz).</summary>
    procedure SetTarget(AColumn: Integer; const ABefore: string);
    /// <summary>Ziel der Einfügelinie.</summary>
    procedure Target(out AColumn: Integer; out ABefore: string);
    property Bar: TAtlasArrangeStrip read FBar;
    property HiddenBar: TAtlasArrangeStrip read FHiddenBar;
    property InsertLine: TPanel read FInsertLine;
  end;

  TAtlasWelcomeBoardFrame = class(TAtlasWelcomeFrame)
  public const
    cGap = 12;
    /// <summary>Mindestbreite einer Spalte beim Verteilen.</summary>
    cMinColumnWidth = 120;
    /// <summary>Mit AutoFold: schmaler als das faltet eine Spalte unter die vorige.</summary>
    cFoldWidth = 280;
  private type
    /// <summary>Stand der Quelle „Seite anpassen“ beim letzten Rebuild.</summary>
    TSourceState = record
      CanCustomize: Boolean;
      Editing: Boolean;
      Catalog: TArray<TAtlasWelcomeCatalogEntry>;
      LayoutNames: TArray<string>;
      ActiveLayout: string;
    end;
    /// <summary>Bereiche und ihre Verteilung, wie zuletzt gesetzt.</summary>
    TPlacement = record
      Sections: TArray<TAtlasWelcomeSection>;
      Wanted: Integer;
      Placing: Boolean;
      Columns: TArray<TArray<string>>;
      Cells: TAtlasWelcomeCells;
      Placed: TArray<TAtlasWelcomePlaced>;
    end;
  private
    FHeader: TAtlasWelcomeHeaderFrame;
    FScroll: TScrollBox;
    FViews: TObjectDictionary<string, TAtlasWelcomeSectionFrame>;
    FLayout: TAtlasWelcomeLayout;
    FAutoFold: Boolean;
    FSource: IAtlasWelcomeArrangeSource;
    FState: TSourceState;
    FPlacement: TPlacement;
    FScroller: TAtlasWelcomeBoardScroller;
    FMenus: TAtlasWelcomeBoardMenus;
    FArranger: TAtlasWelcomeBoardArranger;
    procedure PlaceEvent(Sender: TObject);
    procedure ScrollMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure Place;
    procedure Rearranged(const ALayout: TAtlasWelcomeLayout);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Bereiche neu verteilen: ASections (sichtbare, mit Titel) nach ALayout in AColumns Spalten
    /// (mit AutoFold höchstens so viele, wie nebeneinander passen).</summary>
    procedure Rebuild(const ASections: TArray<TAtlasWelcomeSection>; const ALayout: TAtlasWelcomeLayout;
      AColumns: Integer);
    /// <summary>Inhalt eines Bereichs nachführen; '' = alle.</summary>
    procedure UpdateSection(const AId: string);
    procedure UpdateContent; override;
    function View(const AId: string): TAtlasWelcomeSectionFrame;
    /// <summary>Griff bzw. Werkzeuge eines Bereichs im Bearbeitungsmodus; nil ohne.</summary>
    function GripOf(const AId: string): TAtlasWelcomeGrip;
    function ToolsOf(const AId: string): TAtlasWelcomeSectionTools;
    /// <summary>Liegt AControl in der Tafel (Kopf, Leisten, Bereiche)?</summary>
    function Contains(AControl: TControl): Boolean;
    /// <summary>Kennungen je Spalte, wie zuletzt verteilt.</summary>
    property Columns: TArray<TArray<string>> read FPlacement.Columns;
    property Header: TAtlasWelcomeHeaderFrame read FHeader;
    /// <summary>Layout, wie zuletzt gesetzt bzw. lokal bearbeitet.</summary>
    property Layout: TAtlasWelcomeLayout read FLayout;
    property Placed: TArray<TAtlasWelcomePlaced> read FPlacement.Placed;
    /// <summary>Fenster „Atlas-Start“: Spalten falten, wenn sie schmaler als FoldWidth würden.</summary>
    property AutoFold: Boolean read FAutoFold write FAutoFold;
    /// <summary>„Seite anpassen“ (#767); nil = ohne Leiste und Bearbeitungsmodus. Vor Rebuild setzen.</summary>
    property Source: IAtlasWelcomeArrangeSource read FSource write FSource;
    property Editing: Boolean read FState.Editing;
    /// <summary>Scrollbare Fläche unter Kopf und Leiste.</summary>
    property ScrollBox: TScrollBox read FScroll;
    /// <summary>Mausrad, Tasten und Scrollen am Rand (#1440).</summary>
    property Scroller: TAtlasWelcomeBoardScroller read FScroller;
    /// <summary>Kontextmenü der Bereiche und Menüs der Leiste.</summary>
    property Menus: TAtlasWelcomeBoardMenus read FMenus;
    /// <summary>Leisten, Einfügelinie und Ziehen von „Seite anpassen“.</summary>
    property Arranger: TAtlasWelcomeBoardArranger read FArranger;
  end;

implementation

uses
  Winapi.Messages,
  System.UITypes,
  Vcl.StdCtrls,
  Vcl.Graphics,
  Vcl.Dialogs,
  Vcl.Themes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread;

const
  // Tag der Einträge im Kontextmenü eines Bereichs.
  cTagHide = 1;
  cTagSettings = 2;
  cTagCustomize = 3;

/// <summary>AValue logische Pixel in der Auflösung von AControl.</summary>
function Scaled(AControl: TControl; AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, AControl.CurrentPPI, 96);
end;

/// <summary>Kann AControl jetzt den Fokus nehmen? Nur mit sichtbarer Form: CanFocus allein lässt eine verborgene
/// durch („kann den Fokus nicht erhalten“).</summary>
function CanTakeFocus(AControl: TWinControl): Boolean;
var
  mForm: TCustomForm;
begin
  mForm := GetParentForm(AControl);
  Result := AControl.CanFocus and AControl.Showing and not AControl.Focused and (mForm <> nil) and mForm.Visible;
end;

/// <summary>AProc mit der Quelle über die Nachrichtenschleife; ohne Quelle nichts.</summary>
procedure Later(ABoard: TAtlasWelcomeBoardFrame; const AProc: TProc<IAtlasWelcomeArrangeSource>);
var
  mSource: IAtlasWelcomeArrangeSource;
begin
  mSource := ABoard.FSource;
  if mSource = nil then
  begin
    Exit;
  end;
  // Über die Nachrichtenschleife: Der Aufruf baut die Tafel neu auf und gäbe sonst das klickende Element frei.
  TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.WelcomePage,
        procedure
        begin
          AProc(mSource);
        end);
    end);
end;

/// <summary>„Bereich AId zeigen“ an der Einfügelinie; danach wieder die Vorgabe.</summary>
procedure ShowAtTarget(ABoard: TAtlasWelcomeBoardFrame; const AId: string);
var
  mId, mBefore: string;
  mColumn: Integer;
begin
  mId := AId;
  ABoard.FArranger.Target(mColumn, mBefore);
  ABoard.FArranger.SetTarget(-1, '');
  Later(ABoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.ShowSection(mId, mColumn, mBefore);
    end);
end;

procedure SetEditingLater(ABoard: TAtlasWelcomeBoardFrame; AOn: Boolean);
begin
  Later(ABoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.SetEditing(AOn);
    end);
end;

function CatalogIndex(ABoard: TAtlasWelcomeBoardFrame; const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(ABoard.FState.Catalog) do
  begin
    if SameText(ABoard.FState.Catalog[mIndex].Id, AId) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>Bereiche, deren Frame es gibt, in der Reihenfolge des letzten Rebuild.</summary>
function ViewSections(ABoard: TAtlasWelcomeBoardFrame): TArray<TAtlasWelcomeSection>;
var
  mSection: TAtlasWelcomeSection;
begin
  Result := nil;
  for mSection in ABoard.FPlacement.Sections do
  begin
    if ABoard.View(mSection.Id) <> nil then
    begin
      Result := Result + [mSection];
    end;
  end;
end;

procedure ReadSource(ABoard: TAtlasWelcomeBoardFrame);
var
  mSource: IAtlasWelcomeArrangeSource;
begin
  ABoard.FState := Default(TAtlasWelcomeBoardFrame.TSourceState);
  mSource := ABoard.FSource;
  if mSource = nil then
  begin
    Exit;
  end;
  ABoard.FState.CanCustomize := mSource.CanCustomize;
  ABoard.FState.Editing := ABoard.FState.CanCustomize and mSource.Editing;
  ABoard.FState.Catalog := mSource.Catalog;
  ABoard.FState.LayoutNames := mSource.LayoutNames;
  ABoard.FState.ActiveLayout := mSource.ActiveLayout;
end;

/// <summary>Kennungen je Spalte.</summary>
function ColumnIds(const ACells: TAtlasWelcomeCells): TArray<TArray<string>>;
var
  mColumn: Integer;
  mCell: TAtlasWelcomeCell;
begin
  Result := nil;
  SetLength(Result, Length(ACells));
  for mColumn := 0 to High(ACells) do
  begin
    for mCell in ACells[mColumn] do
    begin
      Result[mColumn] := Result[mColumn] + [mCell.Id];
    end;
  end;
end;

/// <summary>Element von AParent, das von AClass ist; nil ohne.</summary>
function ChildOf(AParent: TWinControl; AClass: TControlClass): TControl;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    if AParent.Controls[mIndex] is AClass then
    begin
      Exit(AParent.Controls[mIndex]);
    end;
  end;
  Result := nil;
end;

/// <summary>Bereich, in dem AComponent liegt; '' ohne.</summary>
function SectionIdOf(AComponent: TComponent): string;
var
  mControl: TControl;
begin
  Result := '';
  if not (AComponent is TControl) then
  begin
    Exit;
  end;
  mControl := TControl(AComponent);
  while (mControl <> nil) and not (mControl is TAtlasWelcomeSectionFrame) do
  begin
    mControl := mControl.Parent;
  end;
  if mControl <> nil then
  begin
    Result := TAtlasWelcomeSectionFrame(mControl).SectionId;
  end;
end;

{ TAtlasWelcomeBoardScroller }

constructor TAtlasWelcomeBoardScroller.Create(ABoard: TAtlasWelcomeBoardFrame);
begin
  inherited Create(ABoard);
  FBoard := ABoard;
  FEdgeTimer := TTimer.Create(Self);
  FEdgeTimer.Enabled := False;
  FEdgeTimer.Interval := 40;
  FEdgeTimer.OnTimer := EdgeTick;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
end;

destructor TAtlasWelcomeBoardScroller.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasWelcomeBoardScroller.Stop;
begin
  FreeAndNil(FEvents);
  if FEdgeTimer <> nil then
  begin
    FEdgeTimer.Enabled := False;
  end;
end;

function TAtlasWelcomeBoardScroller.ScrollBoxArea(AControl: TScrollingWinControl; AWheelDelta: Integer): Boolean;
var
  mBar: TControlScrollBar;
  mMax, mPixels: Integer;
begin
  // Scrollbox und Frames: Die VCL scrollt sie nicht selbst mit dem Mausrad.
  Result := False;
  mBar := AControl.VertScrollBar;
  if not mBar.Visible or not mBar.IsScrollBarVisible then
  begin
    Exit;
  end;
  mMax := TAtlasWelcomeScroll.MaxPosition(mBar.Range, AControl.ClientHeight);
  if not TAtlasWelcomeScroll.CanScroll(mBar.Position, mMax, AWheelDelta) then
  begin
    Exit;
  end;
  mPixels := TAtlasWelcomeScroll.WheelPixels(FWheelRest, AWheelDelta, Mouse.WheelScrollLines,
    Scaled(FBoard, TAtlasWelcomeScroll.cLineHeight), AControl.ClientHeight);
  mBar.Position := TAtlasWelcomeScroll.Clamp(mBar.Position + mPixels, mMax);
  Result := True;
end;

function TAtlasWelcomeBoardScroller.ScrollWindowArea(AControl: TWinControl; AWheelDelta: Integer): Boolean;
var
  mMax, mLines, mIndex: Integer;
  mInfo: TScrollInfo;
  mCode: WPARAM;
begin
  // Fenster mit eigener senkrechter Leiste (Listen, Mehrzeiler): zeilenweise, wie ihr eigenes Mausrad.
  Result := False;
  if not AControl.HandleAllocated or ((GetWindowLongPtr(AControl.Handle, GWL_STYLE) and WS_VSCROLL) = 0) then
  begin
    Exit;
  end;
  mInfo := Default(TScrollInfo);
  mInfo.cbSize := SizeOf(mInfo);
  mInfo.fMask := SIF_ALL;
  if not GetScrollInfo(AControl.Handle, SB_VERT, mInfo) then
  begin
    Exit;
  end;
  mMax := TAtlasWelcomeScroll.MaxPosition(mInfo.nMax - mInfo.nMin + 1, Integer(mInfo.nPage));
  if not TAtlasWelcomeScroll.CanScroll(mInfo.nPos - mInfo.nMin, mMax, AWheelDelta) then
  begin
    Exit;
  end;
  mLines := TAtlasWelcomeScroll.WheelLines(FWheelRest, AWheelDelta, Mouse.WheelScrollLines);
  mCode := SB_LINEDOWN;
  if mLines < 0 then
  begin
    mCode := SB_LINEUP;
  end;
  for mIndex := 1 to Abs(mLines) do
  begin
    AControl.Perform(WM_VSCROLL, mCode, 0);
  end;
  if mLines <> 0 then
  begin
    AControl.Perform(WM_VSCROLL, SB_ENDSCROLL, 0);
  end;
  Result := True;
end;

function TAtlasWelcomeBoardScroller.ScrollArea(AControl: TWinControl; AWheelDelta: Integer): Boolean;
begin
  if AControl is TScrollingWinControl then
  begin
    Result := ScrollBoxArea(TScrollingWinControl(AControl), AWheelDelta);
  end
  else
  begin
    Result := ScrollWindowArea(AControl, AWheelDelta);
  end;
end;

function TAtlasWelcomeBoardScroller.ScrollWheel(AControl: TControl; AWheelDelta: Integer): Boolean;
var
  mControl: TControl;
begin
  Result := False;
  if (AWheelDelta = 0) or not FBoard.Contains(AControl) then
  begin
    Exit;
  end;
  // Von innen nach außen: Eine Liste mit eigener Leiste scrollt zuerst selbst, an ihrem Ende die Seite.
  mControl := AControl;
  while (mControl <> nil) and (mControl <> FBoard.FScroll) and (mControl <> FBoard) do
  begin
    if (mControl is TWinControl) and ScrollArea(TWinControl(mControl), AWheelDelta) then
    begin
      Exit(True);
    end;
    mControl := mControl.Parent;
  end;
  Result := ScrollArea(FBoard.FScroll, AWheelDelta);
end;

function TAtlasWelcomeBoardScroller.ScrollKey(AKey: TAtlasWelcomeScrollKey): Boolean;
var
  mScroll: TScrollBox;
  mOld, mNew: Integer;
begin
  mScroll := FBoard.FScroll;
  mOld := mScroll.VertScrollBar.Position;
  mNew := TAtlasWelcomeScroll.KeyPosition(AKey, mOld,
    TAtlasWelcomeScroll.MaxPosition(mScroll.VertScrollBar.Range, mScroll.ClientHeight), mScroll.ClientHeight,
    Scaled(FBoard, TAtlasWelcomeScroll.cLineHeight));
  Result := mNew <> mOld;
  if Result then
  begin
    mScroll.VertScrollBar.Position := mNew;
  end;
end;

class function TAtlasWelcomeBoardScroller.ScrollKeyOf(AKey: Word; AShift: TShiftState): TAtlasWelcomeScrollKey;
begin
  Result := TAtlasWelcomeScrollKey.None;
  if ssAlt in AShift then
  begin
    Exit;
  end;
  case AKey of
    VK_PRIOR:
      Result := TAtlasWelcomeScrollKey.PageUp;
    VK_NEXT:
      Result := TAtlasWelcomeScrollKey.PageDown;
    VK_HOME:
      Result := TAtlasWelcomeScrollKey.Top;
    VK_END:
      Result := TAtlasWelcomeScrollKey.Bottom;
  else
    // Übrige Tasten bleiben beim Steuerelement.
  end;
end;

class function TAtlasWelcomeBoardScroller.OwnsScrollKeys(AControl: TControl): Boolean;
begin
  // Eingabefelder (Suchfeld #760) bewegen den Cursor, Listen und Auswahlfelder ihre Auswahl.
  Result := (AControl is TCustomEdit) or (AControl is TCustomListControl);
end;

function TAtlasWelcomeBoardScroller.WheelMessage(const AMsg: TMsg): Boolean;
var
  mControl: TControl;
begin
  // Strg (Zoom) und Umschalt (waagerecht) bleiben beim Fenster.
  Result := False;
  if (LoWord(AMsg.wParam) and (MK_CONTROL or MK_SHIFT)) <> 0 then
  begin
    Exit;
  end;
  mControl := FindDragTarget(AMsg.pt, True);
  if not FBoard.Contains(mControl) then
  begin
    Exit;
  end;
  ScrollWheel(mControl, SmallInt(HiWord(AMsg.wParam)));
  // Auch am Ende: Über der Seite gehört das Rad ihr, sonst scrollte das fokussierte Fenster (der Editor).
  Result := True;
end;

function TAtlasWelcomeBoardScroller.KeyMessage(const AMsg: TMsg): Boolean;
var
  mControl: TControl;
  mKey: TAtlasWelcomeScrollKey;
begin
  Result := False;
  mControl := FindControl(AMsg.hwnd);
  if not FBoard.Contains(mControl) or OwnsScrollKeys(mControl) then
  begin
    Exit;
  end;
  mKey := ScrollKeyOf(Word(AMsg.wParam), KeyDataToShiftState(AMsg.lParam));
  if mKey <> TAtlasWelcomeScrollKey.None then
  begin
    ScrollKey(mKey);
    Result := True;
  end;
end;

procedure TAtlasWelcomeBoardScroller.AppMessage(var Msg: TMsg; var Handled: Boolean);
begin
  if Handled or not FBoard.Showing then
  begin
    Exit;
  end;
  try
    case Msg.message of
      WM_MOUSEWHEEL:
        Handled := WheelMessage(Msg);
      WM_KEYDOWN:
        Handled := KeyMessage(Msg);
    end;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

function TAtlasWelcomeBoardScroller.EdgeStep: Integer;
var
  mScroll: TScrollBox;
  mLocal: TPoint;
begin
  Result := 0;
  mScroll := FBoard.FScroll;
  if (FBoard.FArranger.FDrag.Id = '') or not mScroll.HandleAllocated then
  begin
    Exit;
  end;
  mLocal := mScroll.ScreenToClient(FEdgePoint);
  // Nur über der Seite: Der Zug aus der Leiste „Ausgeblendet“ unten soll nicht gleich losscrollen.
  if PtInRect(mScroll.ClientRect, mLocal) then
  begin
    Result := TAtlasWelcomeScroll.EdgeScroll(mLocal.Y, mScroll.ClientHeight,
      Scaled(FBoard, TAtlasWelcomeScroll.cEdgeWidth), Scaled(FBoard, TAtlasWelcomeScroll.cEdgeStep));
  end;
end;

procedure TAtlasWelcomeBoardScroller.UpdateEdgeScroll(const AScreen: TPoint);
begin
  FEdgePoint := AScreen;
  FEdgeTimer.Enabled := (EdgeStep <> 0) and FBoard.FScroll.VertScrollBar.IsScrollBarVisible;
end;

procedure TAtlasWelcomeBoardScroller.EdgeTick(Sender: TObject);
var
  mBar: TControlScrollBar;
  mStep, mMax: Integer;
begin
  mStep := EdgeStep;
  mBar := FBoard.FScroll.VertScrollBar;
  mMax := TAtlasWelcomeScroll.MaxPosition(mBar.Range, FBoard.FScroll.ClientHeight);
  if (mStep = 0) or not TAtlasWelcomeScroll.CanScroll(mBar.Position, mMax, -mStep) then
  begin
    FEdgeTimer.Enabled := False;
    Exit;
  end;
  mBar.Position := TAtlasWelcomeScroll.Clamp(mBar.Position + mStep, mMax);
  // Einfügelinie zum neuen Inhalt unter dem stehenden Zeiger nachführen.
  FBoard.FArranger.DragMove(FEdgePoint);
end;

{ TAtlasWelcomeBoardMenus }

constructor TAtlasWelcomeBoardMenus.Create(ABoard: TAtlasWelcomeBoardFrame);
begin
  inherited Create(ABoard);
  FBoard := ABoard;
  FSectionMenu := TPopupMenu.Create(Self);
  FSectionMenu.OnPopup := SectionMenuPopup;
  AddSectionItem(TAtlasWelcomeTextId.WelcomeArrangeHide, cTagHide, SectionMenuHide);
  AddSectionItem(TAtlasWelcomeTextId.WelcomeArrangeSettings, cTagSettings, SectionMenuSettings);
  AddSectionItem(TAtlasWelcomeTextId.WelcomeArrangeCustomize, cTagCustomize, SectionMenuCustomize);
  FBarMenu := TPopupMenu.Create(Self);
end;

procedure TAtlasWelcomeBoardMenus.AddSectionItem(AId: TAtlasWelcomeTextId; ATag: Integer;
  const AOnClick: TNotifyEvent);
var
  mItem: TMenuItem;
begin
  // „Seite anpassen“ steht hinter einem Trennstrich (Eintrag 2).
  if ATag = cTagCustomize then
  begin
    mItem := TMenuItem.Create(FSectionMenu);
    mItem.Caption := '-';
    FSectionMenu.Items.Add(mItem);
  end;
  mItem := TMenuItem.Create(FSectionMenu);
  mItem.Caption := TAtlasWelcomeStrings.Text(AId);
  mItem.Tag := ATag;
  mItem.OnClick := AOnClick;
  FSectionMenu.Items.Add(mItem);
end;

function TAtlasWelcomeBoardMenus.AddBarItem(const ACaption: string; const AOnClick: TNotifyEvent): TMenuItem;
begin
  Result := TMenuItem.Create(FBarMenu);
  Result.Caption := ACaption;
  Result.OnClick := AOnClick;
  FBarMenu.Items.Add(Result);
end;

procedure TAtlasWelcomeBoardMenus.BuildLayoutMenu;
var
  mItem: TMenuItem;
  mName: string;
  mIndex: Integer;
begin
  FBarMenu.Items.Clear;
  for mIndex := 0 to High(FBoard.FState.LayoutNames) do
  begin
    mName := FBoard.FState.LayoutNames[mIndex];
    mItem := AddBarItem(mName, LayoutMenuSwitch);
    mItem.RadioItem := True;
    mItem.Checked := SameText(mName, FBoard.FState.ActiveLayout);
    mItem.Tag := mIndex;
  end;
  AddBarItem('-', nil);
  AddBarItem(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeNewLayout), LayoutMenuNew);
  AddBarItem(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeRenameLayout), LayoutMenuRename);
  mItem := AddBarItem(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeDeleteLayout,
    [FBoard.FState.ActiveLayout]), LayoutMenuDelete);
  mItem.Enabled := Length(FBoard.FState.LayoutNames) > 1;
end;

procedure TAtlasWelcomeBoardMenus.BuildAddMenu;
var
  mItem: TMenuItem;
  mIndex: Integer;
  mEntry: TAtlasWelcomeCatalogEntry;
begin
  FBarMenu.Items.Clear;
  // Alle Atlas-Bereiche mit kurzer Beschreibung; sichtbare sind abgehakt und lassen sich nicht wählen.
  for mIndex := 0 to High(FBoard.FState.Catalog) do
  begin
    mEntry := FBoard.FState.Catalog[mIndex];
    mItem := AddBarItem(mEntry.Title + ' – ' + mEntry.Description, AddMenuClick);
    mItem.Checked := mEntry.Shown;
    mItem.Enabled := not mEntry.Shown;
    mItem.Tag := mIndex;
  end;
end;

procedure TAtlasWelcomeBoardMenus.AddMenuClick(Sender: TObject);
var
  mIndex: Integer;
begin
  mIndex := (Sender as TMenuItem).Tag;
  if (mIndex >= 0) and (mIndex <= High(FBoard.FState.Catalog)) and not FBoard.FState.Catalog[mIndex].Shown then
  begin
    ShowAtTarget(FBoard, FBoard.FState.Catalog[mIndex].Id);
  end;
end;

procedure TAtlasWelcomeBoardMenus.LayoutMenuSwitch(Sender: TObject);
var
  mIndex: Integer;
  mName: string;
begin
  mIndex := (Sender as TMenuItem).Tag;
  if (mIndex < 0) or (mIndex > High(FBoard.FState.LayoutNames)) or
    SameText(FBoard.FState.LayoutNames[mIndex], FBoard.FState.ActiveLayout) then
  begin
    Exit;
  end;
  mName := FBoard.FState.LayoutNames[mIndex];
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.SwitchLayout(mName);
    end);
end;

function TAtlasWelcomeBoardMenus.NameTaken(const AName: string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in FBoard.FState.LayoutNames do
  begin
    Result := Result or SameText(mName, Trim(AName));
  end;
end;

procedure TAtlasWelcomeBoardMenus.LayoutMenuNew(Sender: TObject);
var
  mName: string;
begin
  mName := '';
  if not AskName(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeLayoutName), mName) or
    (Trim(mName) = '') then
  begin
    Exit;
  end;
  if NameTaken(mName) then
  begin
    Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  mName := Trim(mName);
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.AddLayout(mName);
    end);
end;

procedure TAtlasWelcomeBoardMenus.LayoutMenuRename(Sender: TObject);
var
  mName: string;
begin
  mName := FBoard.FState.ActiveLayout;
  if not AskName(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeLayoutName), mName) or
    (Trim(mName) = '') or SameText(Trim(mName), FBoard.FState.ActiveLayout) then
  begin
    Exit;
  end;
  if NameTaken(mName) then
  begin
    Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeLayoutTaken, [Trim(mName)]), False);
    Exit;
  end;
  mName := Trim(mName);
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.RenameLayout(mName);
    end);
end;

procedure TAtlasWelcomeBoardMenus.LayoutMenuDelete(Sender: TObject);
begin
  if (Length(FBoard.FState.LayoutNames) < 2) or
    not Confirm(TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeDeleteConfirm,
    [FBoard.FState.ActiveLayout]), True) then
  begin
    Exit;
  end;
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.DeleteLayout;
    end);
end;

function TAtlasWelcomeBoardMenus.AskName(const APrompt: string; var AName: string): Boolean;
begin
  if Assigned(FOnAskName) then
  begin
    Exit(FOnAskName(APrompt, AName));
  end;
  Result := InputQuery(TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeCustomize), APrompt, AName);
end;

function TAtlasWelcomeBoardMenus.Confirm(const AText: string; AQuestion: Boolean): Boolean;
begin
  if Assigned(FOnConfirm) then
  begin
    Exit(FOnConfirm(AText, AQuestion));
  end;
  if AQuestion then
  begin
    Result := MessageDlg(AText, mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  end
  else
  begin
    MessageDlg(AText, mtInformation, [mbOK], 0);
    Result := True;
  end;
end;

procedure TAtlasWelcomeBoardMenus.PrepareSectionMenu(const AId: string);
var
  mItem: TMenuItem;
  mIndex: Integer;
begin
  FMenuId := AId;
  for mIndex := 0 to FSectionMenu.Items.Count - 1 do
  begin
    mItem := FSectionMenu.Items[mIndex];
    case mItem.Tag of
      cTagHide, cTagSettings:
        mItem.Enabled := (FBoard.FSource <> nil) and (CatalogIndex(FBoard, AId) >= 0);
      cTagCustomize:
        begin
          mItem.Visible := FBoard.FState.CanCustomize;
          mItem.Checked := FBoard.FState.Editing;
        end;
    end;
  end;
  // Trennstrich nur mit „Seite anpassen“ dahinter.
  FSectionMenu.Items[2].Visible := FBoard.FState.CanCustomize;
end;

procedure TAtlasWelcomeBoardMenus.AttachTo(AFrame: TAtlasWelcomeSectionFrame; AOn: Boolean);
begin
  if AOn then
  begin
    AFrame.TitleBar.PopupMenu := FSectionMenu;
    if AFrame.PopupMenu = nil then
    begin
      AFrame.PopupMenu := FSectionMenu;
    end;
    Exit;
  end;
  if AFrame.TitleBar.PopupMenu = FSectionMenu then
  begin
    AFrame.TitleBar.PopupMenu := nil;
  end;
  if AFrame.PopupMenu = FSectionMenu then
  begin
    AFrame.PopupMenu := nil;
  end;
end;

procedure TAtlasWelcomeBoardMenus.SectionMenuPopup(Sender: TObject);
begin
  PrepareSectionMenu(SectionIdOf(FSectionMenu.PopupComponent));
end;

procedure TAtlasWelcomeBoardMenus.SectionMenuHide(Sender: TObject);
var
  mId: string;
  mWhere: TPoint;
begin
  mId := FMenuId;
  if mId = '' then
  begin
    Exit;
  end;
  mWhere := FSectionMenu.PopupPoint;
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.HideSectionAt(mId, mWhere);
    end);
end;

procedure TAtlasWelcomeBoardMenus.SectionMenuSettings(Sender: TObject);
var
  mId: string;
begin
  mId := FMenuId;
  if mId = '' then
  begin
    Exit;
  end;
  Later(FBoard,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.ShowSectionSettings(mId);
    end);
end;

procedure TAtlasWelcomeBoardMenus.SectionMenuCustomize(Sender: TObject);
begin
  SetEditingLater(FBoard, not FBoard.FState.Editing);
end;

{ TAtlasWelcomeBoardArranger }

constructor TAtlasWelcomeBoardArranger.Create(ABoard: TAtlasWelcomeBoardFrame);
begin
  inherited Create(ABoard);
  FBoard := ABoard;
  FDrag.TargetColumn := -1;
  FBar := TAtlasArrangeStrip.Create(Self);
  FBar.Parent := ABoard;
  FBar.Align := alTop;
  FBar.Top := ABoard.FHeader.Top + ABoard.FHeader.Height;
  FBar.Visible := False;
  FBar.OnPartClick :=
    procedure(const APart: TAtlasArrangePart)
    begin
      BarClick(APart);
    end;
  FHiddenBar := TAtlasArrangeStrip.Create(Self);
  FHiddenBar.Parent := ABoard;
  FHiddenBar.Align := alBottom;
  FHiddenBar.Visible := False;
  FHiddenBar.OnPartClick :=
    procedure(const APart: TAtlasArrangePart)
    begin
      HiddenClick(APart);
    end;
  FHiddenBar.OnDragStart :=
    procedure(const APart: TAtlasArrangePart)
    begin
      DragStart(APart.Value, True);
    end;
  FHiddenBar.OnDragMove :=
    procedure(APoint: TPoint)
    begin
      DragMove(APoint);
    end;
  FHiddenBar.OnDragEnd :=
    procedure(ADrop: Boolean)
    begin
      DragEnd(ADrop);
    end;
  FInsertLine := TPanel.Create(Self);
  FInsertLine.Parent := ABoard.FScroll;
  FInsertLine.BevelOuter := bvNone;
  FInsertLine.ParentBackground := False;
  FInsertLine.StyleElements := [];
  FInsertLine.Color := clHighlight;
  FInsertLine.Height := FInsertLine.ScaleValue(3);
  FInsertLine.Visible := False;
end;

function TAtlasWelcomeBoardArranger.EnsureGrip(AFrame: TAtlasWelcomeSectionFrame): TAtlasWelcomeGrip;
begin
  Result := FBoard.GripOf(AFrame.SectionId);
  if Result <> nil then
  begin
    Exit;
  end;
  Result := TAtlasWelcomeGrip.Create(AFrame);
  Result.Parent := AFrame.TitleBar;
  Result.Align := alLeft;
  Result.Width := Scaled(AFrame, TAtlasWelcomeGrip.cGripWidth);
  Result.SectionId := AFrame.SectionId;
  Result.OnMove := GripMove;
  Result.OnDragStart :=
    procedure(AId: string)
    begin
      DragStart(AId, False);
    end;
  Result.OnDragMove :=
    procedure(APoint: TPoint)
    begin
      DragMove(APoint);
    end;
  Result.OnDragEnd :=
    procedure(ADrop: Boolean)
    begin
      DragEnd(ADrop);
    end;
end;

function TAtlasWelcomeBoardArranger.EnsureTools(AFrame: TAtlasWelcomeSectionFrame): TAtlasWelcomeSectionTools;
begin
  Result := FBoard.ToolsOf(AFrame.SectionId);
  if Result <> nil then
  begin
    Exit;
  end;
  Result := TAtlasWelcomeSectionTools.Create(AFrame);
  Result.Parent := AFrame.TitleBar;
  Result.Align := alRight;
  Result.Width := Scaled(AFrame, 2 * TAtlasWelcomeSectionTools.cToolWidth);
  Result.SectionId := AFrame.SectionId;
  Result.OnTool :=
    procedure(AId: string; ATool: TAtlasWelcomeTool)
    begin
      ToolClick(AId, ATool);
    end;
end;

procedure TAtlasWelcomeBoardArranger.ApplyEditing;
var
  mFrame: TAtlasWelcomeSectionFrame;
  mGrip: TAtlasWelcomeGrip;
  mTools: TAtlasWelcomeSectionTools;
begin
  for mFrame in FBoard.FViews.Values do
  begin
    if FBoard.FState.Editing then
    begin
      mGrip := EnsureGrip(mFrame);
      mTools := EnsureTools(mFrame);
      mTools.Wide := FBoard.FLayout.WidthOf(mFrame.SectionId) > 1;
      mTools.Invalidate;
      mFrame.TitleLabel.Left := mGrip.Width + Scaled(mFrame, 4);
    end
    else
    begin
      FBoard.GripOf(mFrame.SectionId).Free;
      FBoard.ToolsOf(mFrame.SectionId).Free;
      mFrame.TitleLabel.Left := mFrame.TitleLabel.ScaleValue(2);
    end;
    // Rechtsklick „Ausblenden“ (#628-Weg) an Titel und Fläche des Bereichs.
    FBoard.FMenus.AttachTo(mFrame, FBoard.FSource <> nil);
  end;
end;

function TAtlasWelcomeBoardArranger.EditingParts: TArray<TAtlasArrangePart>;
var
  mCount: Integer;
begin
  Result := [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeColumns), '', False)];
  for mCount := TAtlasWelcomeLayout.cMinColumns to TAtlasWelcomeLayout.cMaxColumns do
  begin
    Result := Result + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Column, IntToStr(mCount), IntToStr(mCount),
      '', FBoard.FLayout.Columns = mCount)];
  end;
  Result := Result + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Add, '',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeAdd) + ' ▾', '', False),
    TAtlasArrangePart.Create(TAtlasArrangePartKind.Reset, '',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeReset),
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeResetHint), False)];
end;

function TAtlasWelcomeBoardArranger.BarParts: TArray<TAtlasArrangePart>;
var
  mState: TAtlasWelcomeBoardFrame.TSourceState;
begin
  Result := nil;
  mState := FBoard.FState;
  if not mState.CanCustomize then
  begin
    Exit;
  end;
  if mState.Editing then
  begin
    Result := [TAtlasArrangePart.Create(TAtlasArrangePartKind.Edit, '',
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeDone), '', True)];
  end
  else
  begin
    Result := [TAtlasArrangePart.Create(TAtlasArrangePartKind.Edit, '',
      '✎ ' + TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeCustomize),
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.CommandWelcomeCustomize), False)];
  end;
  // Umschalter im Kopf: mit mehreren Layouts immer, sonst nur beim Bearbeiten (dort Neu/Umbenennen).
  if mState.Editing or (Length(mState.LayoutNames) > 1) then
  begin
    Result := Result + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Layout, '',
      TAtlasWelcomeStrings.Fmt(TAtlasWelcomeTextId.WelcomeArrangeLayout, [mState.ActiveLayout]) + ' ▾', '', False)];
  end;
  if mState.Editing then
  begin
    Result := Result + EditingParts;
  end;
end;

function TAtlasWelcomeBoardArranger.HiddenParts: TArray<TAtlasArrangePart>;
var
  mEntry: TAtlasWelcomeCatalogEntry;
  mAny: Boolean;
begin
  Result := [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeHidden), '', False)];
  mAny := False;
  for mEntry in FBoard.FState.Catalog do
  begin
    if not mEntry.Shown then
    begin
      Result := Result + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Hidden, mEntry.Id, mEntry.Title + ' +',
        TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeShowHint), False)];
      mAny := True;
    end;
  end;
  if not mAny then
  begin
    Result := Result + [TAtlasArrangePart.Create(TAtlasArrangePartKind.Text, '',
      TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeHiddenNone), '', False)];
  end;
end;

procedure TAtlasWelcomeBoardArranger.UpdateBars;
var
  mParts: TArray<TAtlasArrangePart>;
begin
  mParts := BarParts;
  FBar.SetParts(mParts);
  FBar.Visible := Length(mParts) > 0;
  FHiddenBar.SetParts(HiddenParts);
  FHiddenBar.Visible := FBoard.FState.Editing;
  FInsertLine.Visible := FBoard.FState.Editing;
end;

procedure TAtlasWelcomeBoardArranger.FitBars;
begin
  if FBar.Visible then
  begin
    FBar.Height := FBar.PreferredHeight;
  end;
  if FHiddenBar.Visible then
  begin
    FHiddenBar.Height := FHiddenBar.PreferredHeight;
  end;
end;

procedure TAtlasWelcomeBoardArranger.Target(out AColumn: Integer; out ABefore: string);
begin
  AColumn := FDrag.TargetColumn;
  ABefore := FDrag.TargetBefore;
  if (AColumn < 0) or (AColumn > High(FBoard.FPlacement.Cells)) then
  begin
    // Vorgabe: Ende der Spalte mit dem meisten Platz.
    AColumn := TAtlasWelcomeFlow.ShortestColumn(FBoard.FPlacement.Cells, FBoard.FPlacement.Placed,
      TAtlasWelcomeBoardFrame.cGap);
    ABefore := '';
  end;
end;

procedure TAtlasWelcomeBoardArranger.SetTarget(AColumn: Integer; const ABefore: string);
begin
  FDrag.TargetColumn := AColumn;
  FDrag.TargetBefore := ABefore;
  if AColumn < 0 then
  begin
    FDrag.TargetBefore := '';
  end;
  UpdateInsertLine;
end;

procedure TAtlasWelcomeBoardArranger.UpdateInsertLine;
var
  mColumn: Integer;
  mBefore: string;
  mLine: TAtlasWelcomeInsertLine;
begin
  if not FBoard.FState.Editing then
  begin
    FInsertLine.Visible := False;
    Exit;
  end;
  Target(mColumn, mBefore);
  mLine := TAtlasWelcomeFlow.InsertLine(FBoard.FPlacement.Cells, FBoard.FPlacement.Placed,
    TAtlasWelcomeArea.Create(FBoard.FScroll.ClientWidth, TAtlasWelcomeBoardFrame.cGap,
    TAtlasWelcomeBoardFrame.cMinColumnWidth), mColumn,
    mBefore);
  FInsertLine.SetBounds(mLine.Left, mLine.Top - 1 - FBoard.FScroll.VertScrollBar.Position, mLine.Width, 3);
  FInsertLine.Color := StyleServices(FBoard).GetSystemColor(clHighlight);
  FInsertLine.Visible := True;
  FInsertLine.BringToFront;
end;

procedure TAtlasWelcomeBoardArranger.ClickAt(AX, AY: Integer);
var
  mDrop: TAtlasWelcomeDrop;
begin
  mDrop := TAtlasWelcomeFlow.DropTarget(FBoard.FPlacement.Cells, FBoard.FPlacement.Placed,
    TAtlasWelcomeArea.Create(FBoard.FScroll.ClientWidth, TAtlasWelcomeBoardFrame.cGap,
    TAtlasWelcomeBoardFrame.cMinColumnWidth), AX,
    AY + FBoard.FScroll.VertScrollBar.Position, '');
  SetTarget(mDrop.Column, mDrop.Before);
end;

function TAtlasWelcomeBoardArranger.GripMove(const AId: string; ADirection: TAtlasWelcomeMove): Boolean;
var
  mMoved: TAtlasWelcomeLayout;
  mGrip: TAtlasWelcomeGrip;
begin
  Result := FBoard.FState.Editing and FBoard.FLayout.MovedBy(AId, ADirection, ViewSections(FBoard), mMoved);
  if not Result then
  begin
    Exit;
  end;
  FBoard.Rearranged(mMoved);
  // Der Fokus bleibt am Griff des verschobenen Bereichs.
  mGrip := FBoard.GripOf(AId);
  if (mGrip <> nil) and CanTakeFocus(mGrip) then
  begin
    mGrip.SetFocus;
  end;
end;

procedure TAtlasWelcomeBoardArranger.ToolClick(const AId: string; ATool: TAtlasWelcomeTool);
var
  mId: string;
begin
  case ATool of
    TAtlasWelcomeTool.Width:
      FBoard.Rearranged(FBoard.FLayout.WithWidth(AId, 3 - FBoard.FLayout.WidthOf(AId)));
    TAtlasWelcomeTool.Eye:
      begin
        mId := AId;
        Later(FBoard,
          procedure(ASource: IAtlasWelcomeArrangeSource)
          begin
            ASource.HideSection(mId);
          end);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

procedure TAtlasWelcomeBoardArranger.DragStart(const AId: string; AHidden: Boolean);
begin
  if FBoard.FState.Editing then
  begin
    FDrag.Id := AId;
    FDrag.Hidden := AHidden;
    FDrag.DropValid := False;
  end;
end;

procedure TAtlasWelcomeBoardArranger.DragMove(const AScreen: TPoint);
var
  mLocal: TPoint;
  mDrop: TAtlasWelcomeDrop;
begin
  if FDrag.Id = '' then
  begin
    Exit;
  end;
  mLocal := FBoard.FScroll.ScreenToClient(AScreen);
  FDrag.DropValid := PtInRect(FBoard.FScroll.ClientRect, mLocal);
  FBoard.FScroller.UpdateEdgeScroll(AScreen);
  if not FDrag.DropValid then
  begin
    Exit;
  end;
  mDrop := TAtlasWelcomeFlow.DropTarget(FBoard.FPlacement.Cells, FBoard.FPlacement.Placed,
    TAtlasWelcomeArea.Create(FBoard.FScroll.ClientWidth, TAtlasWelcomeBoardFrame.cGap,
    TAtlasWelcomeBoardFrame.cMinColumnWidth), mLocal.X,
    mLocal.Y + FBoard.FScroll.VertScrollBar.Position, FDrag.Id);
  SetTarget(mDrop.Column, mDrop.Before);
end;

procedure TAtlasWelcomeBoardArranger.DragEnd(ADrop: Boolean);
var
  mId, mBefore: string;
  mColumn: Integer;
begin
  mId := FDrag.Id;
  FDrag.Id := '';
  FBoard.FScroller.EdgeTimer.Enabled := False;
  if (mId = '') or not ADrop or not FDrag.DropValid then
  begin
    SetTarget(-1, '');
    Exit;
  end;
  if FDrag.Hidden then
  begin
    ShowAtTarget(FBoard, mId);
    Exit;
  end;
  Target(mColumn, mBefore);
  // Danach wieder die Vorgabe: Ende der Spalte mit dem meisten Platz.
  SetTarget(-1, '');
  FBoard.Rearranged(FBoard.FLayout.MovedTo(mId, mColumn, mBefore));
end;

procedure TAtlasWelcomeBoardArranger.HiddenClick(const APart: TAtlasArrangePart);
begin
  if APart.Kind = TAtlasArrangePartKind.Hidden then
  begin
    ShowAtTarget(FBoard, APart.Value);
  end;
end;

procedure TAtlasWelcomeBoardArranger.BarClick(const APart: TAtlasArrangePart);
var
  mWhere: TPoint;
begin
  case APart.Kind of
    TAtlasArrangePartKind.Edit:
      SetEditingLater(FBoard, not FBoard.FState.Editing);
    TAtlasArrangePartKind.Column:
      FBoard.Rearranged(FBoard.FLayout.WithColumns(StrToIntDef(APart.Value, FBoard.FLayout.Columns)));
    TAtlasArrangePartKind.Reset:
      Later(FBoard,
        procedure(ASource: IAtlasWelcomeArrangeSource)
        begin
          ASource.ResetLayout;
        end);
    TAtlasArrangePartKind.Layout, TAtlasArrangePartKind.Add:
      begin
        if APart.Kind = TAtlasArrangePartKind.Layout then
        begin
          FBoard.FMenus.BuildLayoutMenu;
        end
        else
        begin
          FBoard.FMenus.BuildAddMenu;
        end;
        mWhere := FBar.ClientToScreen(Point(APart.Rect.Left, APart.Rect.Bottom));
        FBoard.FMenus.BarMenu.Popup(mWhere.X, mWhere.Y);
      end;
  else
    // Übrige Werte bewusst ohne Wirkung.
  end;
end;

{ TAtlasWelcomeBoardFrame }

constructor TAtlasWelcomeBoardFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FViews := TObjectDictionary<string, TAtlasWelcomeSectionFrame>.Create([doOwnsValues]);
  FPlacement.Wanted := 2;
  FLayout := TAtlasWelcomeLayout.Atlas;
  FHeader := TAtlasWelcomeHeaderFrame.Create(Self);
  FHeader.Parent := Self;
  FHeader.Align := alTop;
  FScroll := TScrollBox.Create(Self);
  FScroll.Parent := Self;
  FScroll.Align := alClient;
  FScroll.BorderStyle := bsNone;
  FScroll.ParentBackground := True;
  FScroll.VertScrollBar.Tracking := True;
  FScroll.OnResize := PlaceEvent;
  FScroll.OnMouseDown := ScrollMouseDown;
  FArranger := TAtlasWelcomeBoardArranger.Create(Self);
  FMenus := TAtlasWelcomeBoardMenus.Create(Self);
  FScroller := TAtlasWelcomeBoardScroller.Create(Self);
end;

destructor TAtlasWelcomeBoardFrame.Destroy;
begin
  // Zuerst: Nach dem Abbau der Bereiche darf keine Nachricht mehr hier ankommen.
  if FScroller <> nil then
  begin
    FScroller.Stop;
  end;
  // Die Bereichs-Frames gehören dem Wörterbuch, nicht dem Frame.
  FreeAndNil(FViews);
  FSource := nil;
  inherited;
end;

function TAtlasWelcomeBoardFrame.View(const AId: string): TAtlasWelcomeSectionFrame;
begin
  if (FViews = nil) or not FViews.TryGetValue(LowerCase(AId), Result) then
  begin
    Result := nil;
  end;
end;

function TAtlasWelcomeBoardFrame.GripOf(const AId: string): TAtlasWelcomeGrip;
var
  mFrame: TAtlasWelcomeSectionFrame;
begin
  Result := nil;
  mFrame := View(AId);
  if mFrame <> nil then
  begin
    Result := TAtlasWelcomeGrip(ChildOf(mFrame.TitleBar, TAtlasWelcomeGrip));
  end;
end;

function TAtlasWelcomeBoardFrame.ToolsOf(const AId: string): TAtlasWelcomeSectionTools;
var
  mFrame: TAtlasWelcomeSectionFrame;
begin
  Result := nil;
  mFrame := View(AId);
  if mFrame <> nil then
  begin
    Result := TAtlasWelcomeSectionTools(ChildOf(mFrame.TitleBar, TAtlasWelcomeSectionTools));
  end;
end;

procedure TAtlasWelcomeBoardFrame.Rebuild(const ASections: TArray<TAtlasWelcomeSection>;
  const ALayout: TAtlasWelcomeLayout; AColumns: Integer);
var
  mWanted: TDictionary<string, Boolean>;
  mSection: TAtlasWelcomeSection;
  mKey: string;
  mFrame: TAtlasWelcomeSectionFrame;
begin
  FPlacement.Sections := ASections;
  FLayout := ALayout;
  FPlacement.Wanted := AColumns;
  ReadSource(Self);
  mWanted := TDictionary<string, Boolean>.Create;
  try
    for mSection in ASections do
    begin
      mKey := LowerCase(mSection.Id);
      mWanted.AddOrSetValue(mKey, True);
      if not FViews.TryGetValue(mKey, mFrame) then
      begin
        // Ohne Besitzer: Das Wörterbuch gibt die Frames frei.
        mFrame := TAtlasWelcomeViews.CreateView(mSection.Id, nil);
        if mFrame = nil then
        begin
          Continue;
        end;
        mFrame.Parent := FScroll;
        mFrame.OnHeightChanged := PlaceEvent;
        FViews.Add(mKey, mFrame);
        mFrame.UpdateContent;
      end;
      mFrame.ShowTitle := True;
      mFrame.Title := mSection.Title;
    end;
    for mKey in FViews.Keys.ToArray do
    begin
      if not mWanted.ContainsKey(mKey) then
      begin
        FViews.Remove(mKey);
      end;
    end;
  finally
    mWanted.Free;
  end;
  // Ein Ziel, dessen Bereich verschwunden ist, gilt nicht mehr.
  if (FArranger.FDrag.TargetBefore <> '') and (View(FArranger.FDrag.TargetBefore) = nil) then
  begin
    FArranger.FDrag.TargetColumn := -1;
  end;
  FArranger.ApplyEditing;
  FArranger.UpdateBars;
  Place;
end;

procedure TAtlasWelcomeBoardFrame.PlaceEvent(Sender: TObject);
begin
  Place;
end;

procedure TAtlasWelcomeBoardFrame.Place;
var
  mCount, mPosition: Integer;
  mItem: TAtlasWelcomePlaced;
  mFrame: TAtlasWelcomeSectionFrame;
begin
  if FPlacement.Placing or (FViews = nil) then
  begin
    Exit;
  end;
  FPlacement.Placing := True;
  try
    FArranger.FitBars;
    mCount := FPlacement.Wanted;
    if FAutoFold and (FScroll.ClientWidth > 0) then
    begin
      mCount := TAtlasWelcomeFlow.FitColumns(FPlacement.Wanted, FScroll.ClientWidth, cGap, cFoldWidth);
    end;
    FPlacement.Cells := FLayout.Cells(ViewSections(Self), mCount);
    FPlacement.Columns := ColumnIds(FPlacement.Cells);
    // Breite zuerst: Bereiche mit umbrechendem Text (#756) berechnen ihre Höhe danach.
    FPlacement.Placed := TAtlasWelcomeFlow.Place(FPlacement.Cells, FScroll.ClientWidth, cGap, cMinColumnWidth,
      function(const AId: string; AWidth: Integer): Integer
      var
        mView: TAtlasWelcomeSectionFrame;
      begin
        Result := 0;
        mView := View(AId);
        if mView <> nil then
        begin
          mView.Width := AWidth;
          Result := mView.PreferredHeight;
        end;
      end);
    mPosition := FScroll.VertScrollBar.Position;
    for mItem in FPlacement.Placed do
    begin
      mFrame := View(mItem.Id);
      if mFrame <> nil then
      begin
        mFrame.SetBounds(mItem.Left, mItem.Top - mPosition, mItem.Width, mItem.Height);
      end;
    end;
    FArranger.UpdateInsertLine;
  finally
    FPlacement.Placing := False;
  end;
end;

procedure TAtlasWelcomeBoardFrame.ScrollMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  // Fokus auf die Seite, damit Bild auf/ab und Pos1/Ende sie scrollen (#1440).
  if (Button = mbLeft) and CanTakeFocus(FScroll) then
  begin
    FScroll.SetFocus;
  end;
  // Klick auf freie Fläche setzt die Einfügelinie für „Bereich hinzufügen“ und „Ausgeblendet“.
  if FState.Editing and (Button = mbLeft) then
  begin
    FArranger.ClickAt(X, Y);
  end;
end;

function TAtlasWelcomeBoardFrame.Contains(AControl: TControl): Boolean;
var
  mControl: TControl;
begin
  mControl := AControl;
  while mControl <> nil do
  begin
    if mControl = Self then
    begin
      Exit(True);
    end;
    mControl := mControl.Parent;
  end;
  Result := False;
end;

procedure TAtlasWelcomeBoardFrame.Rearranged(const ALayout: TAtlasWelcomeLayout);
var
  mLayout: TAtlasWelcomeLayout;
begin
  if TAtlasWelcomeLayout.Same(ALayout, FLayout) then
  begin
    Exit;
  end;
  // Sofort zeigen (mehrere Strg+Pfeiltasten hintereinander), gespeichert wird über die Quelle. Eine andere
  // Spaltenzahl gilt gleich mit: Place verteilt auf Wanted, das sonst erst der nächste Rebuild setzt.
  if ALayout.Columns <> FLayout.Columns then
  begin
    FPlacement.Wanted := ALayout.Columns;
  end;
  FLayout := ALayout;
  mLayout := ALayout;
  FArranger.ApplyEditing;
  FArranger.UpdateBars;
  Place;
  Later(Self,
    procedure(ASource: IAtlasWelcomeArrangeSource)
    begin
      ASource.Arrange(mLayout);
    end);
end;

procedure TAtlasWelcomeBoardFrame.UpdateSection(const AId: string);
var
  mFrame: TAtlasWelcomeSectionFrame;
begin
  if AId = '' then
  begin
    for mFrame in FViews.Values do
    begin
      mFrame.UpdateContent;
    end;
    Place;
    Exit;
  end;
  mFrame := View(AId);
  if mFrame <> nil then
  begin
    mFrame.UpdateContent;
    Place;
  end;
end;

procedure TAtlasWelcomeBoardFrame.UpdateContent;
begin
  UpdateSection('');
  inherited;
end;

end.
