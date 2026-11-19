unit Atlas.UI.Tracker.BoardFrame;

// Inhalt des andockbaren Fensters „Atlas-Board“ (#1272), reine VCL ohne Open
// Tools API (Anordnung: TAtlasBoardLayout, Zeichnen: TAtlasBoardPainter):
//   [Board ▾] [Sprint ▾] [Nur meine|Alle] [Suchen …] [Aktualisieren]
//   (Stand vom … bzw. Fehler, Verschieben …)
//   OFFEN (3)        IN ARBEIT (2)      ZUR PRÜFUNG (1)    ERLEDIGT (4)
//   ┃ATL-123   ⛔ 3/5 MB
//   ┃Titel in zwei
//   ┃Zeilen …
// Karte: Kennung, Titel (zwei Zeilen), Zuständig als Kürzel, Priorität als
// Farbbalken links, Fortschritt der Checkliste (#1273), Schloss bei offenem
// „hängt ab von“ (#1279), Rahmen in Akzentfarbe beim aktuellen Issue (#765).
// Schmaler als 360 px: Spalten untereinander als einklappbare Gruppen (Klick
// auf die Kopfzeile). Hat das Board Swimlanes (TAtlasBoardLanes), steht breit
// links eine Spalte mit einer Zeile je Wert (z. B. je Zuständigem), die Karten
// in den Zellen darunter; Klick auf den Namen klappt die Zeile, die eigene
// Zeile ist links in Akzentfarbe markiert. Ziehen in eine andere Zeile ändert
// nur die Spalte. Ziehen einer Karte in eine andere Spalte meldet
// Events.Move; die IDE-Schicht fragt nach, schreibt und ruft danach MoveCard
// (sofort sichtbar) bzw. RevertMove (springt zurück); Spalten, die der
// Workflow des Trackers sicher ausschließt (TAtlasBoardTransitions), werden
// beim Ziehen nicht hervorgehoben. Klick meldet Events.Open,
// Doppelklick Events.Start, Rechtsklick zeigt das Kontextmenü (Beginnen, Prüfen …,
// Vorschau, Im Browser öffnen, Kennung kopieren, Mir zuweisen). Mit
// CanDrag = False (ohne Netz) lässt sich nichts ziehen. Filter „Nur meine“
// und Suche wirken lokal. Netz, Zwischenspeicher und Schreiben liegen in der
// IDE-Schicht. Die DFM ist leer, weil TCustomFrame.Create für abgeleitete
// Frames eine Ressource verlangt; aufgebaut wird im Code.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Winapi.Messages,
  Vcl.Controls,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Buttons,
  Vcl.Menus,
  Vcl.Forms,
  Atlas.Core.Style.Palette,
  Atlas.Core.Tracker.Board,
  Atlas.Core.Tracker.BoardLayout;

type
  TAtlasBoardCardEvent = reference to procedure(ACard: Integer);
  TAtlasBoardMoveEvent = reference to procedure(ACard, AColumn: Integer);

  /// <summary>Ereignisse der Zeichenfläche; nil = nichts.</summary>
  TAtlasBoardViewEvents = record
    Open: TAtlasBoardCardEvent;
    Start: TAtlasBoardCardEvent;
    Move: TAtlasBoardMoveEvent;
    /// <summary>Rechtsklick auf eine Karte; Punkt in Bildschirmkoordinaten.</summary>
    Context: TProc<Integer, TPoint>;
    /// <summary>Beschriftung einer Spalte (Board-Nummer, -1 = ohne Spalte).</summary>
    ColumnName: TFunc<Integer, string>;
  end;

  /// <summary>Zeichenfläche des Boards: Spalten, Karten, Ziehen.</summary>
  TAtlasBoardView = class(TCustomControl)
  public const
    /// <summary>So weit (Pixel bei 96 dpi) muss die Maus wandern, bis aus einem Klick ein Ziehen wird.</summary>
    cDragDistance = 5;
  private
    FSnapshot: TAtlasBoardSnapshot;
    FVisible: TArray<Integer>;
    FLayout: TAtlasBoardLayout;
    FColors: TAtlasColors;
    FFolds: TAtlasBoardFolds;
    FActiveKey: string;
    FCanDrag: Boolean;
    FPressCard: Integer;
    FPressPoint: TPoint;
    FDragging: Boolean;
    FDragPoint: TPoint;
    FDropColumn: Integer;
    FEvents: TAtlasBoardViewEvents;
    function Metrics: TAtlasBoardMetrics;
    procedure CancelDrag;
    procedure CMMouseLeave(var AMessage: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neu anordnen für die Breite AWidth; setzt Width und Height auf den Inhalt.</summary>
    procedure Relayout(AWidth: Integer);
    procedure SetData(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>);
    property Snapshot: TAtlasBoardSnapshot read FSnapshot;
    property Layout: TAtlasBoardLayout read FLayout;
    /// <summary>Eingeklappte Spalten (nur schmal) und Swimlanes; Klick auf Kopfzeile bzw. Namen schaltet um.
    /// </summary>
    property Folds: TAtlasBoardFolds read FFolds;
    property Colors: TAtlasColors read FColors write FColors;
    property ActiveKey: string read FActiveKey write FActiveKey;
    property CanDrag: Boolean read FCanDrag write FCanDrag;
    property Events: TAtlasBoardViewEvents read FEvents write FEvents;
  end;

  /// <summary>Ereignisse des Frames; nil = nichts.</summary>
  TAtlasBoardFrameEvents = record
    Open: TAtlasBoardCardEvent;
    Start: TAtlasBoardCardEvent;
    /// <summary>„Prüfen …“ (#2126).</summary>
    Review: TAtlasBoardCardEvent;
    Browse: TAtlasBoardCardEvent;
    Assign: TAtlasBoardCardEvent;
    Move: TAtlasBoardMoveEvent;
    Refresh: TProc;
    /// <summary>Anderes Board gewählt (ID).</summary>
    Board: TProc<string>;
    /// <summary>Anderer Sprint gewählt (ID).</summary>
    Sprint: TProc<string>;
    OnlyMine: TProc<Boolean>;
    /// <summary>Fenster geschlossen bzw. versteckt.</summary>
    Hidden: TProc;
  end;

  /// <summary>Steuerelemente des Frames; sie gehören dem Frame.</summary>
  TAtlasBoardFrameParts = record
    Head: TFlowPanel;
    Boards: TComboBox;
    Sprints: TComboBox;
    Mine: TSpeedButton;
    All: TSpeedButton;
    Search: TEdit;
    Refresh: TButton;
    Status: TLabel;
    Scroll: TScrollBox;
    View: TAtlasBoardView;
    Empty: TLabel;
  end;

  /// <summary>Auswahl von Board und Sprint in der Kopfleiste: Namen aus dem Stand, je Eintrag die ID. Eine Auswahl
  /// gibt es nur bei mehreren Boards bzw. mit Sprints; Füllen meldet keine Wahl.</summary>
  TAtlasBoardChoices = class
  private
    FBoards: TComboBox;
    FSprints: TComboBox;
    FBoardIds: TArray<string>;
    FSprintIds: TArray<string>;
    FFilling: Boolean;
    function Chosen(ABox: TComboBox; const AIds: TArray<string>; out AId: string): Boolean;
  public
    constructor Create(ABoards, ASprints: TComboBox);
    destructor Destroy; override;
    /// <summary>Klapplisten aus dem Stand füllen (brauchen ein Fenster).</summary>
    procedure Fill(const ASnapshot: TAtlasBoardSnapshot);
    /// <summary>Gewähltes Board; False beim Füllen oder ohne Auswahl.</summary>
    function ChosenBoard(out AId: string): Boolean;
    function ChosenSprint(out AId: string): Boolean;
  end;

  TAtlasBoardFrame = class;

  /// <summary>Kontextmenü einer Karte: Beginnen, Prüfen …, Vorschau, Im Browser öffnen, Kennung kopieren, Mir
  /// zuweisen.</summary>
  TAtlasBoardCardMenu = class
  private
    FFrame: TAtlasBoardFrame;
    FMenu: TPopupMenu;
    FCard: Integer;
    /// <summary>Eintrag des Menüs (Tag: TBoardMenu).</summary>
    procedure ItemClick(Sender: TObject);
  public
    constructor Create(AFrame: TAtlasBoardFrame);
    /// <summary>Menü zur Karte ACard an APoint (Bildschirmkoordinaten).</summary>
    procedure Popup(ACard: Integer; const APoint: TPoint);
    property Menu: TPopupMenu read FMenu;
  end;

  TAtlasBoardFrame = class(TFrame)
  private
    FParts: TAtlasBoardFrameParts;
    FChoices: TAtlasBoardChoices;
    FCardMenu: TAtlasBoardCardMenu;
    FColors: TAtlasColors;
    FSnapshot: TAtlasBoardSnapshot;
    FHasSnapshot: Boolean;
    FOnlyMine: Boolean;
    FEvents: TAtlasBoardFrameEvents;
    /// <summary>Kopfleiste: Board, Sprint, „Nur meine“/„Alle“, Suche, Aktualisieren.</summary>
    procedure AddHead;
    /// <summary>Statuszeile, Fläche mit Zeichenfläche und Hinweis.</summary>
    procedure AddBody;
    /// <summary>Ereignisse der Zeichenfläche an die des Frames weiterreichen.</summary>
    function ViewEvents: TAtlasBoardViewEvents;
    procedure UpdateView;
    /// <summary>Board, Sprint oder Suche geändert.</summary>
    procedure ChoiceChange(Sender: TObject);
    /// <summary>„Nur meine“, „Alle“ oder „Aktualisieren“.</summary>
    procedure ButtonClick(Sender: TObject);
    procedure ScrollResize(Sender: TObject);
    procedure CMShowingChanged(var AMessage: TMessage); message CM_SHOWINGCHANGED;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Stand zeigen; AStatus: Zeile über den Karten ("Stand vom …", Fehler), '' = keine.</summary>
    procedure SetSnapshot(const ASnapshot: TAtlasBoardSnapshot; const AStatus: string);
    /// <summary>Kein Board zu zeigen (kein Tracker, kein Board): Text in der Mitte.</summary>
    procedure ShowNotice(const AText: string);
    procedure SetStatus(const AText: string);
    procedure SetLoading(AValue: Boolean);
    /// <summary>Karte ACard steht sofort in Spalte AColumn (vor dem Schreiben); liefert den alten Wert.</summary>
    function MoveCard(ACard, AColumn: Integer): string;
    /// <summary>Karte AKey springt zurück auf den Wert AState.</summary>
    procedure RevertMove(const AKey, AState: string);
    /// <summary>Kennung des aktuellen Issues (#765): Rahmen in Akzentfarbe.</summary>
    procedure SetActiveKey(const AKey: string);
    /// <summary>Ziehen erlaubt (Verbindung und Schreibweg da).</summary>
    procedure SetCanDrag(AValue: Boolean);
    /// <summary>Umschalter „Nur meine“/„Alle“ ohne OnlyMine-Ereignis.</summary>
    procedure SetOnlyMine(AValue: Boolean);
    /// <summary>Karten nach Filter und Suche.</summary>
    function VisibleCards: TArray<Integer>;
    function StatusText: string;
    function Card(AIndex: Integer): TAtlasBoardCard;
    /// <summary>Beschriftung der Spalte AColumn (-1 = „Ohne Spalte“; GitHub ohne Projekt übersetzt).</summary>
    function ColumnCaption(AColumn: Integer): string;
    property Snapshot: TAtlasBoardSnapshot read FSnapshot;
    property HasSnapshot: Boolean read FHasSnapshot;
    property OnlyMine: Boolean read FOnlyMine;
    property View: TAtlasBoardView read FParts.View;
    property Parts: TAtlasBoardFrameParts read FParts;
    property Events: TAtlasBoardFrameEvents read FEvents write FEvents;
  end;

implementation

uses
  Atlas.Core.Style.Color,
  System.Math,
  Winapi.Windows,
  Vcl.Graphics,
  Vcl.Clipbrd,
  Atlas.UI.Foundation.WrapLabel,
  Atlas.UI.Tracker.Board.Strings,
  Atlas.UI.Tracker.BoardPainter,
  Atlas.UI.Tracker.Workflow.Strings;

{$R *.dfm}

type
  /// <summary>Einträge des Kontextmenüs einer Karte (Tag).</summary>
  {$SCOPEDENUMS ON}
  TBoardMenu = (Start, Review, Preview, Browse, Copy, Assign);
  {$SCOPEDENUMS OFF}

const
  /// <summary>Bildschirmpunkte je Zoll, für die die Maße gelten.</summary>
  cDesignPpi = 96;
  /// <summary>Schrifthöhe ohne Fenster: unter cMinLine gilt cDefaultLine.</summary>
  cMinLine = 8;
  cDefaultLine = 15;
  // Hinweis ohne Board bzw. unter einem leeren Board bei 96 dpi.
  cEmptyTop = 40;
  cEmptyGap = 8;
  cEmptyWidth = 300;
  cEmptyMinWidth = 100;
  cEmptyHeight = 60;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasBoardView }

constructor TAtlasBoardView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks];
  DoubleBuffered := True;
  TabStop := True;
  FColors := TAtlasColors.Light;
  FFolds := TAtlasBoardFolds.Create;
  FPressCard := -1;
  FDropColumn := TAtlasBoardLayout.cNoColumn;
end;

destructor TAtlasBoardView.Destroy;
begin
  FreeAndNil(FFolds);
  inherited;
end;

procedure TAtlasBoardView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mCard: Integer;
begin
  inherited;
  if CanFocus then
  begin
    SetFocus;
  end;
  mCard := FLayout.CardAt(Point(X, Y));
  if Button = mbRight then
  begin
    if (mCard >= 0) and Assigned(FEvents.Context) then
    begin
      FEvents.Context(mCard, ClientToScreen(Point(X, Y)));
    end;
    Exit;
  end;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  FPressCard := mCard;
  FPressPoint := Point(X, Y);
  FDragging := False;
  // Schmal: Klick auf die Kopfzeile klappt die Gruppe; breit: Klick auf den Namen die Swimlane.
  if (mCard < 0) and FLayout.Narrow and (FLayout.HeaderAt(Point(X, Y)) <> TAtlasBoardLayout.cNoColumn) then
  begin
    FFolds.ToggleColumn(FLayout.HeaderAt(Point(X, Y)));
    Relayout(Width);
  end
  else if (mCard < 0) and (FLayout.LaneAt(Point(X, Y)) >= 0) then
  begin
    FFolds.ToggleLane(TAtlasBoardLayout.LaneKey(FLayout.Lanes[FLayout.LaneAt(Point(X, Y))]));
    Relayout(Width);
  end;
end;

procedure TAtlasBoardView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mDistance: Integer;
begin
  inherited;
  if (FPressCard < 0) or not (ssLeft in Shift) then
  begin
    Exit;
  end;
  mDistance := MulDiv(cDragDistance, CurrentPPI, cDesignPpi);
  if not FDragging and FCanDrag and ((Abs(X - FPressPoint.X) > mDistance) or (Abs(Y - FPressPoint.Y) > mDistance))
  then
  begin
    FDragging := True;
    MouseCapture := True;
  end;
  if FDragging then
  begin
    FDragPoint := Point(X, Y);
    FDropColumn := FLayout.ColumnAt(FDragPoint);
    // Spalten, die der Workflow des Trackers sicher nicht zulässt, nehmen nichts an (Grund beim Loslassen).
    if TAtlasBoardTransitions.Allowed(FSnapshot, FPressCard, FDropColumn) then
    begin
      Cursor := crDrag;
    end
    else
    begin
      Cursor := crNoDrop;
    end;
    Invalidate;
  end;
end;

procedure TAtlasBoardView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mCard, mColumn: Integer;
  mDragging: Boolean;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mCard := FPressCard;
  mDragging := FDragging;
  mColumn := FLayout.ColumnAt(Point(X, Y));
  CancelDrag;
  if mCard < 0 then
  begin
    Exit;
  end;
  if mDragging then
  begin
    if TAtlasTrackerBoard.CanMove(FSnapshot, mCard, mColumn) and Assigned(FEvents.Move) then
    begin
      FEvents.Move(mCard, mColumn);
    end;
  end
  else if (FLayout.CardAt(Point(X, Y)) = mCard) and Assigned(FEvents.Open) then
  begin
    FEvents.Open(mCard);
  end;
end;

procedure TAtlasBoardView.DblClick;
var
  mCard: Integer;
begin
  inherited;
  mCard := FLayout.CardAt(ScreenToClient(Mouse.CursorPos));
  if (mCard >= 0) and Assigned(FEvents.Start) then
  begin
    FEvents.Start(mCard);
  end;
end;

procedure TAtlasBoardView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited;
  if (Key = VK_ESCAPE) and FDragging then
  begin
    Key := 0;
    CancelDrag;
  end;
end;

function TAtlasBoardView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or not (Parent is TScrollBox) then
  begin
    Exit;
  end;
  // Das Rad blättert die umgebende Fläche, mit Umschalt waagerecht.
  if ssShift in Shift then
  begin
    TScrollBox(Parent).HorzScrollBar.Position := TScrollBox(Parent).HorzScrollBar.Position - WheelDelta div 2;
  end
  else
  begin
    TScrollBox(Parent).VertScrollBar.Position := TScrollBox(Parent).VertScrollBar.Position - WheelDelta div 2;
  end;
  Result := True;
end;

function TAtlasBoardView.Metrics: TAtlasBoardMetrics;
var
  mLine: Integer;
begin
  mLine := Abs(Font.Height);
  if HandleAllocated then
  begin
    Canvas.Font := Font;
    mLine := Canvas.TextHeight('Ag');
  end
  else if mLine < cMinLine then
  begin
    mLine := cDefaultLine;
  end;
  // Zeilenhöhe ist schon in Bildschirmpixeln; Breiten und Abstände skalieren mit der Schrift.
  Result := TAtlasBoardMetrics.Create(mLine).Scaled(CurrentPPI, cDesignPpi);
end;

procedure TAtlasBoardView.Paint;
var
  mInput: TAtlasBoardPaintInput;
  mPainter: TAtlasBoardPainter;
begin
  Canvas.Font := Font;
  mInput := Default(TAtlasBoardPaintInput);
  mInput.Snapshot := FSnapshot;
  mInput.Layout := FLayout;
  mInput.Colors := FColors;
  mInput.ActiveKey := FActiveKey;
  mInput.Folds := FFolds;
  mInput.ColumnName := FEvents.ColumnName;
  mInput.Drag.Dragging := FDragging;
  mInput.Drag.Card := FPressCard;
  mInput.Drag.DropColumn := FDropColumn;
  mInput.Drag.Offset := Point(FDragPoint.X - FPressPoint.X, FDragPoint.Y - FPressPoint.Y);
  mInput.PixelsPerInch := CurrentPPI;
  mInput.Gap := Metrics.Gap;
  mPainter := TAtlasBoardPainter.Create(Canvas, mInput);
  try
    mPainter.Paint(ClientRect);
  finally
    mPainter.Free;
  end;
end;

procedure TAtlasBoardView.CancelDrag;
begin
  if FDragging then
  begin
    MouseCapture := False;
  end;
  FDragging := False;
  FPressCard := -1;
  FDropColumn := TAtlasBoardLayout.cNoColumn;
  Cursor := crDefault;
  Invalidate;
end;

procedure TAtlasBoardView.CMMouseLeave(var AMessage: TMessage);
begin
  inherited;
  if not FDragging then
  begin
    FPressCard := -1;
  end;
end;

procedure TAtlasBoardView.Relayout(AWidth: Integer);
begin
  FLayout := TAtlasBoardLayout.Build(FSnapshot, FVisible, AWidth, FFolds.Columns, FFolds.Lanes, Metrics);
  SetBounds(0, 0, FLayout.Width, Max(FLayout.Height, 1));
  Invalidate;
end;

procedure TAtlasBoardView.SetData(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>);
begin
  CancelDrag;
  FSnapshot := ASnapshot;
  FVisible := AVisible;
end;

{ TAtlasBoardChoices }

/// <summary>Namen ANames in ABox; gewählt ist der Eintrag, dessen ID in AIds ASelected ist.</summary>
procedure FillBox(ABox: TComboBox; const ANames, AIds: TArray<string>; const ASelected: string);
var
  mIndex: Integer;
begin
  ABox.Items.BeginUpdate;
  try
    ABox.Items.Clear;
    for mIndex := 0 to High(ANames) do
    begin
      ABox.Items.Add(ANames[mIndex]);
      if SameText(AIds[mIndex], ASelected) then
      begin
        ABox.ItemIndex := mIndex;
      end;
    end;
  finally
    ABox.Items.EndUpdate;
  end;
end;

/// <summary>Namen und IDs der Boards ABoards.</summary>
procedure BoardLists(const ABoards: TArray<TAtlasBoardRef>; out ANames, AIds: TArray<string>);
var
  mBoard: TAtlasBoardRef;
begin
  ANames := nil;
  AIds := nil;
  for mBoard in ABoards do
  begin
    ANames := ANames + [mBoard.Name];
    AIds := AIds + [mBoard.Id];
  end;
end;

/// <summary>Namen und IDs der Sprints ASprints.</summary>
procedure SprintLists(const ASprints: TArray<TAtlasBoardSprint>; out ANames, AIds: TArray<string>);
var
  mSprint: TAtlasBoardSprint;
begin
  ANames := nil;
  AIds := nil;
  for mSprint in ASprints do
  begin
    ANames := ANames + [mSprint.Name];
    AIds := AIds + [mSprint.Id];
  end;
end;

constructor TAtlasBoardChoices.Create(ABoards, ASprints: TComboBox);
begin
  inherited Create;
  FBoards := ABoards;
  FSprints := ASprints;
end;

destructor TAtlasBoardChoices.Destroy;
begin
  FBoardIds := nil;
  FSprintIds := nil;
  inherited;
end;

procedure TAtlasBoardChoices.Fill(const ASnapshot: TAtlasBoardSnapshot);
var
  mNames: TArray<string>;
begin
  FFilling := True;
  try
    BoardLists(ASnapshot.Boards, mNames, FBoardIds);
    FillBox(FBoards, mNames, FBoardIds, ASnapshot.Board.Id);
    // Eine Auswahl nur, wenn es mehrere Boards gibt.
    FBoards.Visible := Length(ASnapshot.Boards) > 1;
    SprintLists(ASnapshot.Sprints, mNames, FSprintIds);
    FillBox(FSprints, mNames, FSprintIds, ASnapshot.Sprint.Id);
    if (FSprints.ItemIndex < 0) and (ASnapshot.Sprint.Name <> '') then
    begin
      FSprints.Items.Add(ASnapshot.Sprint.Name);
      FSprintIds := FSprintIds + [ASnapshot.Sprint.Id];
      FSprints.ItemIndex := FSprints.Items.Count - 1;
    end;
    FSprints.Visible := FSprints.Items.Count > 0;
  finally
    FFilling := False;
  end;
end;

function TAtlasBoardChoices.Chosen(ABox: TComboBox; const AIds: TArray<string>; out AId: string): Boolean;
begin
  AId := '';
  Result := not FFilling and (ABox.ItemIndex >= 0) and (ABox.ItemIndex <= High(AIds));
  if Result then
  begin
    AId := AIds[ABox.ItemIndex];
  end;
end;

function TAtlasBoardChoices.ChosenBoard(out AId: string): Boolean;
begin
  Result := Chosen(FBoards, FBoardIds, AId);
end;

function TAtlasBoardChoices.ChosenSprint(out AId: string): Boolean;
begin
  Result := Chosen(FSprints, FSprintIds, AId);
end;

{ TAtlasBoardCardMenu }

constructor TAtlasBoardCardMenu.Create(AFrame: TAtlasBoardFrame);

  procedure Add(const ACaption: string; ACommand: TBoardMenu);
  var
    mItem: TMenuItem;
  begin
    mItem := TMenuItem.Create(FMenu);
    mItem.Caption := ACaption;
    mItem.Tag := Ord(ACommand);
    mItem.OnClick := ItemClick;
    mItem.Default := ACommand = TBoardMenu.Start;
    FMenu.Items.Add(mItem);
  end;

begin
  inherited Create;
  FFrame := AFrame;
  FCard := -1;
  // Das Menü gehört dem Frame.
  FMenu := TPopupMenu.Create(AFrame);
  Add(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuStart), TBoardMenu.Start);
  Add(TAtlasWorkflowStrings.Text(TAtlasWorkflowTextId.TrackerReviewCommand), TBoardMenu.Review);
  Add(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuPreview), TBoardMenu.Preview);
  Add(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuBrowse), TBoardMenu.Browse);
  Add(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuCopy), TBoardMenu.Copy);
  Add(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardMenuAssign), TBoardMenu.Assign);
end;

procedure TAtlasBoardCardMenu.Popup(ACard: Integer; const APoint: TPoint);
begin
  FCard := ACard;
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure FireCard(const AEvent: TAtlasBoardCardEvent; ACard: Integer);
begin
  if Assigned(AEvent) then
  begin
    AEvent(ACard);
  end;
end;

procedure TAtlasBoardCardMenu.ItemClick(Sender: TObject);
var
  mEvents: TAtlasBoardFrameEvents;
begin
  mEvents := FFrame.Events;
  case TBoardMenu(TMenuItem(Sender).Tag) of
    TBoardMenu.Start:
      FireCard(mEvents.Start, FCard);
    TBoardMenu.Review:
      FireCard(mEvents.Review, FCard);
    TBoardMenu.Preview:
      FireCard(mEvents.Open, FCard);
    TBoardMenu.Browse:
      FireCard(mEvents.Browse, FCard);
    TBoardMenu.Copy:
      begin
        if (FCard >= 0) and (FCard <= High(FFrame.Snapshot.Cards)) then
        begin
          Clipboard.AsText := FFrame.Card(FCard).Key;
        end;
      end;
    TBoardMenu.Assign:
      FireCard(mEvents.Assign, FCard);
  end;
end;

{ TAtlasBoardFrame }

/// <summary>Auswahl in der Kopfleiste; AWidth in logischen Pixeln (96 dpi).</summary>
function AddCombo(AOwner: TComponent; AParent: TWinControl; AWidth: Integer; const AHint: string;
  AChange: TNotifyEvent): TComboBox;
begin
  Result := TComboBox.Create(AOwner);
  Result.Parent := AParent;
  Result.Style := csDropDownList;
  Result.Width := Result.ScaleValue(AWidth);
  Result.Hint := AHint;
  Result.ShowHint := True;
  Result.AlignWithMargins := True;
  Result.OnChange := AChange;
end;

/// <summary>Schalter in der Kopfleiste; AWidth und AHeight in logischen Pixeln (96 dpi).</summary>
function AddToggle(AOwner: TComponent; AParent: TWinControl; AWidth, AHeight: Integer; const ACaption: string;
  AClick: TNotifyEvent): TSpeedButton;
begin
  Result := TSpeedButton.Create(AOwner);
  Result.Parent := AParent;
  Result.Caption := ACaption;
  Result.GroupIndex := 1;
  Result.Flat := True;
  Result.Width := Result.ScaleValue(AWidth);
  Result.Height := Result.ScaleValue(AHeight);
  Result.AlignWithMargins := True;
  Result.OnClick := AClick;
end;

procedure TAtlasBoardFrame.AddHead;
const
  // Breiten der Auswahlen und Schalter in der Kopfleiste.
  cBoardsWidth = 150;
  cSprintsWidth = 130;
  cMineWidth = 80;
  cAllWidth = 50;
  cToggleHeight = 23;
  cSearchWidth = 150;
  cRefreshWidth = 90;
  cHeadMargin = 4;
begin
  FParts.Head := TFlowPanel.Create(Self);
  FParts.Head.Parent := Self;
  FParts.Head.Align := alTop;
  FParts.Head.AutoSize := True;
  FParts.Head.BevelOuter := bvNone;
  FParts.Head.AlignWithMargins := True;
  FParts.Head.Margins.SetBounds(cHeadMargin, cHeadMargin, cHeadMargin, 0);
  FParts.Boards := AddCombo(Self, FParts.Head, cBoardsWidth,
    TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardBoardHint), ChoiceChange);
  FParts.Sprints := AddCombo(Self, FParts.Head, cSprintsWidth,
    TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardSprintHint), ChoiceChange);
  FParts.Mine := AddToggle(Self, FParts.Head, cMineWidth, cToggleHeight,
    TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardOnlyMine), ButtonClick);
  FParts.Mine.Down := True;
  FParts.All := AddToggle(Self, FParts.Head, cAllWidth, cToggleHeight,
    TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardAll), ButtonClick);
  FParts.Search := TEdit.Create(Self);
  FParts.Search.Parent := FParts.Head;
  FParts.Search.Width := ScaleValue(cSearchWidth);
  FParts.Search.TextHint := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardSearchHint);
  FParts.Search.AlignWithMargins := True;
  FParts.Search.OnChange := ChoiceChange;
  FParts.Refresh := TButton.Create(Self);
  FParts.Refresh.Parent := FParts.Head;
  FParts.Refresh.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardRefresh);
  FParts.Refresh.Width := ScaleValue(cRefreshWidth);
  FParts.Refresh.AlignWithMargins := True;
  FParts.Refresh.OnClick := ButtonClick;
end;

function TAtlasBoardFrame.ViewEvents: TAtlasBoardViewEvents;
var
  mFrame: TAtlasBoardFrame;
begin
  mFrame := Self;
  Result := Default(TAtlasBoardViewEvents);
  Result.ColumnName :=
    function(AColumn: Integer): string
    begin
      Result := mFrame.ColumnCaption(AColumn);
    end;
  Result.Open :=
    procedure(ACard: Integer)
    begin
      FireCard(mFrame.FEvents.Open, ACard);
    end;
  Result.Start :=
    procedure(ACard: Integer)
    begin
      FireCard(mFrame.FEvents.Start, ACard);
    end;
  Result.Move :=
    procedure(ACard, AColumn: Integer)
    begin
      if Assigned(mFrame.FEvents.Move) then
      begin
        mFrame.FEvents.Move(ACard, AColumn);
      end;
    end;
  Result.Context :=
    procedure(ACard: Integer; APoint: TPoint)
    begin
      mFrame.FCardMenu.Popup(ACard, APoint);
    end;
end;

procedure TAtlasBoardFrame.AddBody;
const
  cStatusMargin = 8;
begin
  FParts.Status := TAtlasWrapLabel.Create(Self);
  FParts.Status.Parent := Self;
  FParts.Status.Align := alTop;
  FParts.Status.AlignWithMargins := True;
  FParts.Status.Margins.SetBounds(cStatusMargin, 2, cStatusMargin, 2);
  FParts.Status.Visible := False;
  FParts.Status.Top := FParts.Head.Top + FParts.Head.Height + 1;
  FParts.Scroll := TScrollBox.Create(Self);
  FParts.Scroll.Parent := Self;
  FParts.Scroll.Align := alClient;
  FParts.Scroll.BorderStyle := bsNone;
  FParts.Scroll.HorzScrollBar.Tracking := True;
  FParts.Scroll.VertScrollBar.Tracking := True;
  FParts.Scroll.OnResize := ScrollResize;
  FParts.View := TAtlasBoardView.Create(Self);
  FParts.View.Parent := FParts.Scroll;
  FParts.View.Events := ViewEvents;
  FParts.Empty := TAtlasWrapLabel.Create(Self);
  FParts.Empty.Parent := FParts.Scroll;
  FParts.Empty.AutoSize := False;
  FParts.Empty.Alignment := taCenter;
  FParts.Empty.SetBounds(0, ScaleValue(cEmptyTop), ScaleValue(cEmptyWidth), ScaleValue(cEmptyHeight));
  FParts.Empty.Visible := False;
end;

constructor TAtlasBoardFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColors := TAtlasColors.Light;
  FOnlyMine := True;
  AddHead;
  AddBody;
  FChoices := TAtlasBoardChoices.Create(FParts.Boards, FParts.Sprints);
  FCardMenu := TAtlasBoardCardMenu.Create(Self);
end;

destructor TAtlasBoardFrame.Destroy;
begin
  if Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
  FEvents := Default(TAtlasBoardFrameEvents);
  FreeAndNil(FCardMenu);
  FreeAndNil(FChoices);
  inherited;
end;

procedure TAtlasBoardFrame.ButtonClick(Sender: TObject);
begin
  if Sender = FParts.Refresh then
  begin
    if Assigned(FEvents.Refresh) then
    begin
      FEvents.Refresh();
    end;
  end
  else if FParts.Mine.Down <> FOnlyMine then
  begin
    SetOnlyMine(FParts.Mine.Down);
    if Assigned(FEvents.OnlyMine) then
    begin
      FEvents.OnlyMine(FOnlyMine);
    end;
  end;
end;

procedure TAtlasBoardFrame.CMShowingChanged(var AMessage: TMessage);
begin
  inherited;
  // Das X versteckt die Form samt Frame: wie Schließen.
  if not Showing and Assigned(FEvents.Hidden) then
  begin
    FEvents.Hidden();
  end;
end;

procedure TAtlasBoardFrame.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FParts.View.Colors := AColors;
  FParts.Scroll.Color := ToColor(AColors.Surface);
  FParts.Scroll.ParentBackground := False;
  FParts.Empty.Font.Color := ToColor(AColors.Muted);
  FParts.Status.Font.Color := ToColor(AColors.Muted);
  FParts.View.Invalidate;
end;

procedure TAtlasBoardFrame.SetStatus(const AText: string);
begin
  FParts.Status.Caption := AText;
  FParts.Status.Visible := AText <> '';
end;

procedure TAtlasBoardFrame.SetLoading(AValue: Boolean);
begin
  FParts.Refresh.Enabled := not AValue;
  if AValue then
  begin
    SetStatus(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardLoading));
  end;
end;

/// <summary>Innenbreite der Scrollbox; ohne Fenster ihre Breite (ClientWidth bräuchte ein Handle).</summary>
function ScrollWidth(AScroll: TScrollBox): Integer;
begin
  if AScroll.HandleAllocated then
  begin
    Result := AScroll.ClientWidth;
  end
  else
  begin
    Result := AScroll.Width;
  end;
end;

procedure TAtlasBoardFrame.UpdateView;
var
  mVisible: TArray<Integer>;
begin
  mVisible := VisibleCards;
  FParts.View.SetData(FSnapshot, mVisible);
  FParts.View.Visible := FHasSnapshot;
  FParts.View.Relayout(ScrollWidth(FParts.Scroll));
  if FHasSnapshot and (Length(mVisible) = 0) then
  begin
    if FOnlyMine and (Length(FSnapshot.Cards) > 0) then
    begin
      FParts.Empty.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardEmptyMine);
    end
    else
    begin
      FParts.Empty.Caption := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardEmpty);
    end;
    FParts.Empty.Visible := True;
    FParts.Empty.Top := FParts.View.Height + ScaleValue(cEmptyGap);
  end
  else if FHasSnapshot then
  begin
    FParts.Empty.Visible := False;
  end;
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(cEmptyMinWidth));
end;

procedure TAtlasBoardFrame.ScrollResize(Sender: TObject);
begin
  if FHasSnapshot then
  begin
    FParts.View.Relayout(ScrollWidth(FParts.Scroll));
  end;
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(cEmptyMinWidth));
end;

procedure TAtlasBoardFrame.SetSnapshot(const ASnapshot: TAtlasBoardSnapshot; const AStatus: string);
begin
  FSnapshot := ASnapshot;
  FHasSnapshot := True;
  FParts.Empty.Visible := False;
  // Klapplisten brauchen ein Fenster; ohne Form bleibt die Auswahl leer (Tests).
  if GetParentForm(Self) <> nil then
  begin
    FChoices.Fill(FSnapshot);
  end;
  SetStatus(AStatus);
  UpdateView;
end;

procedure TAtlasBoardFrame.ShowNotice(const AText: string);
begin
  FHasSnapshot := False;
  FSnapshot := TAtlasBoardSnapshot.Empty;
  FParts.View.SetData(FSnapshot, nil);
  FParts.View.Visible := False;
  FParts.Empty.Caption := AText;
  FParts.Empty.Top := ScaleValue(cEmptyTop);
  FParts.Empty.Width := Max(ScrollWidth(FParts.Scroll), ScaleValue(cEmptyMinWidth));
  FParts.Empty.Visible := AText <> '';
end;

function TAtlasBoardFrame.MoveCard(ACard, AColumn: Integer): string;
begin
  Result := '';
  if (ACard < 0) or (ACard > High(FSnapshot.Cards)) or (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
  begin
    Exit;
  end;
  Result := FSnapshot.Cards[ACard].State;
  if Length(FSnapshot.Columns[AColumn].Values) > 0 then
  begin
    FSnapshot.Cards[ACard].State := FSnapshot.Columns[AColumn].Values[0];
  end;
  UpdateView;
end;

procedure TAtlasBoardFrame.RevertMove(const AKey, AState: string);
var
  mCard: Integer;
begin
  mCard := FSnapshot.CardIndex(AKey);
  if mCard < 0 then
  begin
    Exit;
  end;
  FSnapshot.Cards[mCard].State := AState;
  UpdateView;
end;

procedure TAtlasBoardFrame.SetActiveKey(const AKey: string);
begin
  FParts.View.ActiveKey := AKey;
  FParts.View.Invalidate;
end;

procedure TAtlasBoardFrame.SetCanDrag(AValue: Boolean);
begin
  FParts.View.CanDrag := AValue;
end;

procedure TAtlasBoardFrame.SetOnlyMine(AValue: Boolean);
begin
  FOnlyMine := AValue;
  FParts.Mine.Down := AValue;
  FParts.All.Down := not AValue;
  if FHasSnapshot then
  begin
    UpdateView;
  end;
end;

function TAtlasBoardFrame.VisibleCards: TArray<Integer>;
begin
  Result := TAtlasTrackerBoard.Visible(FSnapshot, FOnlyMine, FParts.Search.Text);
end;

function TAtlasBoardFrame.StatusText: string;
begin
  Result := '';
  if FParts.Status.Visible then
  begin
    Result := FParts.Status.Caption;
  end;
end;

procedure TAtlasBoardFrame.ChoiceChange(Sender: TObject);
var
  mId: string;
begin
  if Sender = FParts.Search then
  begin
    if FHasSnapshot then
    begin
      UpdateView;
    end;
  end
  else if (Sender = FParts.Boards) and FChoices.ChosenBoard(mId) and Assigned(FEvents.Board) then
  begin
    FEvents.Board(mId);
  end
  else if (Sender = FParts.Sprints) and FChoices.ChosenSprint(mId) and Assigned(FEvents.Sprint) then
  begin
    FEvents.Sprint(mId);
  end;
end;

function TAtlasBoardFrame.Card(AIndex: Integer): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  if (AIndex >= 0) and (AIndex <= High(FSnapshot.Cards)) then
  begin
    Result := FSnapshot.Cards[AIndex];
  end;
end;

function TAtlasBoardFrame.ColumnCaption(AColumn: Integer): string;
begin
  if (AColumn < 0) or (AColumn > High(FSnapshot.Columns)) then
  begin
    Exit(TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardNoColumn));
  end;
  Result := FSnapshot.Columns[AColumn].Name;
  // GitHub ohne Projekt: Zustände des Issues in der Sprache der Oberfläche.
  if FSnapshot.Kind = TAtlasBoardKind.Repository then
  begin
    if FSnapshot.Columns[AColumn].Resolved then
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnClosed);
    end
    else
    begin
      Result := TAtlasBoardStrings.Text(TAtlasBoardTextId.BoardColumnOpen);
    end;
  end;
end;

end.
