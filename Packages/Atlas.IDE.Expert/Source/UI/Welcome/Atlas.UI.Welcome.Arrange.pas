unit Atlas.UI.Welcome.Arrange;

// Bausteine für „Seite anpassen“ (#767), ohne Open Tools API:
// - IAtlasWelcomeArrangeSource: was die IDE-Schicht anbietet (Layouts,
//   Katalog der Bereiche, Ein- und Ausblenden über die Einstellungen,
//   Speichern). Die Tafel ruft sie über die Nachrichtenschleife, weil ein
//   Aufruf die Tafel neu aufbaut und damit das klickende Element freigeben
//   kann.
// - TAtlasArrangeStrip: gezeichnete Leiste aus Knöpfen und Chips mit Hover,
//   Klick und Ziehen; daraus die Leiste im Kopf (Stift „Seite anpassen“,
//   Layout-Umschalter, Spalten, „Bereich hinzufügen“, „Zurücksetzen“) und die
//   Leiste „Ausgeblendet“ am Ende.
// - TAtlasWelcomeGrip: Griff in der Titelzeile eines Bereichs; fokussierbar
//   (Tab), Strg+Pfeiltasten verschieben, Ziehen mit der Maus.
// - TAtlasWelcomeSectionTools: Breite (ein-/zweispaltig) und Auge rechts in
//   der Titelzeile.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Welcome.Layout,
  Atlas.UI.Welcome.Frame;

type
  /// <summary>Ein Atlas-Bereich für „Bereich hinzufügen“ und die Leiste „Ausgeblendet“.</summary>
  TAtlasWelcomeCatalogEntry = record
    Id: string;
    Title: string;
    /// <summary>Kurze Beschreibung für „Bereich hinzufügen“.</summary>
    Description: string;
    /// <summary>Einstellung des Bereichs an?</summary>
    Shown: Boolean;
    class function Create(const AId, ATitle, ADescription: string; AShown: Boolean): TAtlasWelcomeCatalogEntry;
      static;
  end;

  IAtlasWelcomeArrangeSource = interface
    ['{3F7B2C91-6A4E-4D08-B5C1-9E2A7D4F6B13}']
    /// <summary>welcomePage.customLayout: Bearbeitungsmodus, Stift und Layout-Umschalter.</summary>
    function CanCustomize: Boolean;
    /// <summary>Bearbeitungsmodus an (gilt für Willkommensseite und „Atlas-Start“ zugleich)?</summary>
    function Editing: Boolean;
    procedure SetEditing(AOn: Boolean);
    function LayoutNames: TArray<string>;
    function ActiveLayout: string;
    /// <summary>Alle angemeldeten Atlas-Bereiche in der Reihenfolge des Atlas-Layouts.</summary>
    function Catalog: TArray<TAtlasWelcomeCatalogEntry>;
    /// <summary>Plätze, Breiten oder Spalten des aktiven Layouts geändert.</summary>
    procedure Arrange(const ALayout: TAtlasWelcomeLayout);
    /// <summary>Ausgeblendeten Bereich einschalten und in Spalte AColumn vor ABefore ('' = ans Ende) setzen.
    /// </summary>
    procedure ShowSection(const AId: string; AColumn: Integer; const ABefore: string);
    /// <summary>Auge: Einstellung des Bereichs aus.</summary>
    procedure HideSection(const AId: string);
    /// <summary>Rechtsklick „Ausblenden“ wie am Element (#628): mit „Rückgängig“ an APoint (Bildschirm).
    /// </summary>
    procedure HideSectionAt(const AId: string; const APoint: TPoint);
    /// <summary>Optionsseite mit der Einstellung des Bereichs.</summary>
    procedure ShowSectionSettings(const AId: string);
    procedure SwitchLayout(const AName: string);
    /// <summary>Kopie des aktiven Layouts unter AName; False bei leerem oder vergebenem Namen.</summary>
    function AddLayout(const AName: string): Boolean;
    function RenameLayout(const AName: string): Boolean;
    /// <summary>Aktives Layout löschen; False beim letzten.</summary>
    function DeleteLayout: Boolean;
    /// <summary>„Zurücksetzen“: Atlas-Layout (#753) für das aktive Layout.</summary>
    procedure ResetLayout;
  end;

{$SCOPEDENUMS ON}
  /// <summary>Teile der gezeichneten Leisten.</summary>
  TAtlasArrangePartKind = (Text, Edit, Layout, Column, Add, Reset, Hidden);
{$SCOPEDENUMS OFF}

  TAtlasArrangePart = record
    Kind: TAtlasArrangePartKind;
    /// <summary>Spalte (Column) bzw. Kennung des Bereichs (Hidden).</summary>
    Value: string;
    Caption: string;
    Hint: string;
    /// <summary>Aktiv dargestellt (z. B. gewählte Spaltenzahl, „Fertig“).</summary>
    Down: Boolean;
    Rect: TRect;
    class function Create(AKind: TAtlasArrangePartKind; const AValue, ACaption, AHint: string;
      ADown: Boolean): TAtlasArrangePart; static;
  end;

  TAtlasArrangePartEvent = reference to procedure(const APart: TAtlasArrangePart);

  /// <summary>Gezeichnete Leiste aus Knöpfen; Text-Teile sind nur Beschriftung.</summary>
  TAtlasArrangeStrip = class(TAtlasWelcomeCanvas)
  public const
    PartHeight = 22;
    PartPadding = 8;
    PartGap = 6;
    /// <summary>So viele Pixel Bewegung mit gedrückter Taste machen aus dem Klick ein Ziehen.</summary>
    DragDistance = 5;
  private
    FParts: TArray<TAtlasArrangePart>;
    FHot: Integer;
    FPressed: Integer;
    FPressPoint: TPoint;
    FDragging: Boolean;
    FOnClick: TAtlasArrangePartEvent;
    FOnDragStart: TAtlasArrangePartEvent;
    FOnDragMove: TProc<TPoint>;
    FOnDragEnd: TProc<Boolean>;
    procedure Measure;
    function PartAt(X, Y: Integer): Integer;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetParts(const AParts: TArray<TAtlasArrangePart>);
    function IndexOf(AKind: TAtlasArrangePartKind; const AValue: string): Integer;
    /// <summary>Wie ein Klick auf Teil AIndex (auch für Tests).</summary>
    procedure ClickPart(AIndex: Integer);
    /// <summary>Höhe für die Teile bei der aktuellen Breite (Umbruch in Zeilen).</summary>
    function PreferredHeight: Integer;
    property Parts: TArray<TAtlasArrangePart> read FParts;
    property OnPartClick: TAtlasArrangePartEvent read FOnClick write FOnClick;
    /// <summary>Ziehen eines Hidden-Teils beginnt; danach OnDragMove (Bildschirm) und OnDragEnd (abgelegt?).
    /// </summary>
    property OnDragStart: TAtlasArrangePartEvent read FOnDragStart write FOnDragStart;
    property OnDragMove: TProc<TPoint> read FOnDragMove write FOnDragMove;
    property OnDragEnd: TProc<Boolean> read FOnDragEnd write FOnDragEnd;
  end;

  TAtlasWelcomeMoveEvent = reference to function(const AId: string; ADirection: TAtlasWelcomeMove): Boolean;

  /// <summary>Griff eines Bereichs im Bearbeitungsmodus: Tab erreicht ihn, Strg+Pfeiltasten verschieben,
  /// Ziehen mit der Maus (Escape bricht ab).</summary>
  TAtlasWelcomeGrip = class(TCustomControl)
  public const
    GripWidth = 16;
  private
    FSectionId: string;
    FPressed: Boolean;
    FDragging: Boolean;
    FPressPoint: TPoint;
    FOnMove: TAtlasWelcomeMoveEvent;
    FOnDragStart: TProc<string>;
    FOnDragMove: TProc<TPoint>;
    FOnDragEnd: TProc<Boolean>;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
    procedure EndDrag(ADrop: Boolean);
  protected
    procedure Paint; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Taste wie gedrückt; True, wenn sie verarbeitet wurde (auch für Tests).</summary>
    function HandleKey(AKey: Word; AShift: TShiftState): Boolean;
    property SectionId: string read FSectionId write FSectionId;
    /// <summary>Zieht gerade; nicht „Dragging“, das verdeckte TControl.Dragging (W1009).</summary>
    property IsDragging: Boolean read FDragging;
    property OnMove: TAtlasWelcomeMoveEvent read FOnMove write FOnMove;
    property OnDragStart: TProc<string> read FOnDragStart write FOnDragStart;
    property OnDragMove: TProc<TPoint> read FOnDragMove write FOnDragMove;
    property OnDragEnd: TProc<Boolean> read FOnDragEnd write FOnDragEnd;
  end;

{$SCOPEDENUMS ON}
  TAtlasWelcomeTool = (None, Width, Eye);
{$SCOPEDENUMS OFF}

  /// <summary>Breite und Auge rechts in der Titelzeile.</summary>
  TAtlasWelcomeSectionTools = class(TCustomControl)
  public const
    ToolWidth = 22;
  private
    FSectionId: string;
    FWide: Boolean;
    FHot: TAtlasWelcomeTool;
    FOnTool: TProc<string, TAtlasWelcomeTool>;
    function ToolAt(X: Integer): TAtlasWelcomeTool;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Wie ein Klick auf das Werkzeug (auch für Tests).</summary>
    procedure Click(ATool: TAtlasWelcomeTool); reintroduce;
    property SectionId: string read FSectionId write FSectionId;
    /// <summary>Bereich zweispaltig? Bestimmt das Symbol der Breite.</summary>
    property Wide: Boolean read FWide write FWide;
    property OnTool: TProc<string, TAtlasWelcomeTool> read FOnTool write FOnTool;
  end;

implementation

uses
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings;

function StyleColor(AControl: TControl; AColor: TColor): TColor;
begin
  Result := StyleServices(AControl).GetSystemColor(AColor);
end;

{ TAtlasWelcomeCatalogEntry }

class function TAtlasWelcomeCatalogEntry.Create(const AId, ATitle, ADescription: string;
  AShown: Boolean): TAtlasWelcomeCatalogEntry;
begin
  Result.Id := AId;
  Result.Title := ATitle;
  Result.Description := ADescription;
  Result.Shown := AShown;
end;

{ TAtlasArrangePart }

class function TAtlasArrangePart.Create(AKind: TAtlasArrangePartKind; const AValue, ACaption, AHint: string;
  ADown: Boolean): TAtlasArrangePart;
begin
  Result.Kind := AKind;
  Result.Value := AValue;
  Result.Caption := ACaption;
  Result.Hint := AHint;
  Result.Down := ADown;
  Result.Rect := TRect.Empty;
end;

{ TAtlasArrangeStrip }

constructor TAtlasArrangeStrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FHot := -1;
  FPressed := -1;
  ShowHint := True;
  Height := PartHeight + 8;
end;

procedure TAtlasArrangeStrip.SetParts(const AParts: TArray<TAtlasArrangePart>);
begin
  FParts := Copy(AParts);
  FHot := -1;
  FPressed := -1;
  FDragging := False;
  if HandleAllocated then
    Measure;
  Invalidate;
end;

function TAtlasArrangeStrip.IndexOf(AKind: TAtlasArrangePartKind; const AValue: string): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FParts) do
    if (FParts[Index].Kind = AKind) and ((AValue = '') or SameText(FParts[Index].Value, AValue)) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasArrangeStrip.Measure;
var
  Index, X, Y, W, Line, Pad, Gap, Margin: Integer;
begin
  // Teile von links nach rechts; was nicht mehr passt, beginnt eine neue Zeile.
  Canvas.Font := Font;
  Line := ScaleValue(PartHeight);
  Pad := ScaleValue(PartPadding);
  Gap := ScaleValue(PartGap);
  Margin := ScaleValue(4);
  X := Margin + Gap;
  Y := Margin;
  for Index := 0 to High(FParts) do
  begin
    W := Canvas.TextWidth(FParts[Index].Caption);
    if FParts[Index].Kind <> TAtlasArrangePartKind.Text then
      Inc(W, 2 * Pad);
    if (X + W > ClientWidth - Gap) and (X > Margin + Gap) then
    begin
      X := Margin + Gap;
      Inc(Y, Line + Margin);
    end;
    FParts[Index].Rect := TRect.Create(X, Y, X + W, Y + Line);
    Inc(X, W + Gap);
  end;
end;

function TAtlasArrangeStrip.PreferredHeight: Integer;
var
  Part: TAtlasArrangePart;
begin
  Result := ScaleValue(PartHeight + 8);
  if not HandleAllocated then
    Exit;
  Measure;
  for Part in FParts do
    if Part.Rect.Bottom + ScaleValue(4) > Result then
      Result := Part.Rect.Bottom + ScaleValue(4);
end;

procedure TAtlasArrangeStrip.Resize;
begin
  inherited;
  if HandleAllocated then
    Measure;
end;

function TAtlasArrangeStrip.PartAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FParts) do
    if (FParts[Index].Kind <> TAtlasArrangePartKind.Text) and FParts[Index].Rect.Contains(Point(X, Y)) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasArrangeStrip.Paint;
var
  Index, Radius: Integer;
  Part: TAtlasArrangePart;
  TextColor, MutedColor, LineColor, AccentColor, AccentText: TColor;
begin
  inherited;
  Measure;
  TextColor := StyleColor(Self, clWindowText);
  MutedColor := StyleColor(Self, clGrayText);
  LineColor := StyleColor(Self, clBtnShadow);
  AccentColor := StyleColor(Self, clHighlight);
  AccentText := StyleColor(Self, clHighlightText);
  Radius := ScaleValue(6);
  Canvas.Font := Font;
  for Index := 0 to High(FParts) do
  begin
    Part := FParts[Index];
    Canvas.Brush.Style := bsClear;
    if Part.Kind = TAtlasArrangePartKind.Text then
    begin
      Canvas.Font.Color := MutedColor;
      Canvas.TextOut(Part.Rect.Left, Part.Rect.Top + (Part.Rect.Height - Canvas.TextHeight(Part.Caption)) div 2,
        Part.Caption);
      Continue;
    end;
    if Part.Down then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := AccentColor;
      Canvas.Pen.Color := AccentColor;
      Canvas.Font.Color := AccentText;
    end
    else
    begin
      if Index = FHot then
        Canvas.Pen.Color := AccentColor
      else
        Canvas.Pen.Color := LineColor;
      Canvas.Font.Color := TextColor;
    end;
    Canvas.RoundRect(Part.Rect.Left, Part.Rect.Top, Part.Rect.Right, Part.Rect.Bottom, Radius, Radius);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(Part.Rect.Left + (Part.Rect.Width - Canvas.TextWidth(Part.Caption)) div 2,
      Part.Rect.Top + (Part.Rect.Height - Canvas.TextHeight(Part.Caption)) div 2, Part.Caption);
  end;
end;

procedure TAtlasArrangeStrip.ClickPart(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FParts)) or (FParts[AIndex].Kind = TAtlasArrangePartKind.Text) then
    Exit;
  if Assigned(FOnClick) then
    try
      FOnClick(FParts[AIndex]);
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
    end;
end;

procedure TAtlasArrangeStrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  FPressed := PartAt(X, Y);
  FPressPoint := Point(X, Y);
  FDragging := False;
end;

procedure TAtlasArrangeStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: Integer;
begin
  inherited;
  if (FPressed >= 0) and (ssLeft in Shift) then
  begin
    // Nur ausgeblendete Bereiche lassen sich auf die Seite ziehen.
    if not FDragging and (FParts[FPressed].Kind = TAtlasArrangePartKind.Hidden) and
      ((Abs(X - FPressPoint.X) > ScaleValue(DragDistance)) or (Abs(Y - FPressPoint.Y) > ScaleValue(DragDistance))) then
    begin
      FDragging := True;
      Screen.Cursor := crDrag;
      if Assigned(FOnDragStart) then
        FOnDragStart(FParts[FPressed]);
    end;
    if FDragging and Assigned(FOnDragMove) then
      FOnDragMove(ClientToScreen(Point(X, Y)));
    Exit;
  end;
  Hot := PartAt(X, Y);
  if Hot <> FHot then
  begin
    FHot := Hot;
    Hint := '';
    if Hot >= 0 then
      Hint := FParts[Hot].Hint;
    Application.CancelHint;
    Invalidate;
  end;
end;

procedure TAtlasArrangeStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Pressed: Integer;
  Dragging: Boolean;
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  Pressed := FPressed;
  Dragging := FDragging;
  FPressed := -1;
  FDragging := False;
  if Dragging then
  begin
    Screen.Cursor := crDefault;
    if Assigned(FOnDragEnd) then
      FOnDragEnd(not PtInRect(ClientRect, Point(X, Y)));
    Exit;
  end;
  if (Pressed >= 0) and (Pressed = PartAt(X, Y)) then
    ClickPart(Pressed);
end;

procedure TAtlasArrangeStrip.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

{ TAtlasWelcomeGrip }

constructor TAtlasWelcomeGrip.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  TabStop := True;
  ParentColor := True;
  Width := GripWidth;
  Cursor := crSizeAll;
  ShowHint := True;
  Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeGrip);
end;

procedure TAtlasWelcomeGrip.Paint;
var
  Row, Column, Size, Left, Top: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasWelcomeCanvas.BackgroundOf(Self);
  Canvas.FillRect(ClientRect);
  // Sechs Punkte wie ein Griff (⠿).
  Size := ScaleValue(2);
  Left := (ClientWidth - 3 * Size) div 2;
  Top := (ClientHeight - 5 * Size) div 2;
  if Focused then
    Canvas.Brush.Color := StyleColor(Self, clHighlight)
  else
    Canvas.Brush.Color := StyleColor(Self, clGrayText);
  for Row := 0 to 2 do
    for Column := 0 to 1 do
      Canvas.FillRect(TRect.Create(Left + Column * 2 * Size, Top + Row * 2 * Size,
        Left + Column * 2 * Size + Size, Top + Row * 2 * Size + Size));
  if Focused then
    Canvas.DrawFocusRect(ClientRect);
end;

procedure TAtlasWelcomeGrip.DoEnter;
begin
  inherited;
  Invalidate;
end;

procedure TAtlasWelcomeGrip.DoExit;
begin
  inherited;
  Invalidate;
end;

procedure TAtlasWelcomeGrip.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS;
end;

function TAtlasWelcomeGrip.HandleKey(AKey: Word; AShift: TShiftState): Boolean;
var
  Direction: TAtlasWelcomeMove;
begin
  Result := False;
  if (AKey = VK_ESCAPE) and FDragging then
  begin
    EndDrag(False);
    Exit(True);
  end;
  if not (ssCtrl in AShift) or (ssAlt in AShift) or not Assigned(FOnMove) then
    Exit;
  case AKey of
    VK_UP:
      Direction := TAtlasWelcomeMove.Up;
    VK_DOWN:
      Direction := TAtlasWelcomeMove.Down;
    VK_LEFT:
      Direction := TAtlasWelcomeMove.Left;
    VK_RIGHT:
      Direction := TAtlasWelcomeMove.Right;
  else
    Exit;
  end;
  try
    FOnMove(FSectionId, Direction);
  except
    // Keine Exception an die IDE (#493).
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
  // Auch am Rand verarbeitet: Strg+Pfeil soll dann nicht den Fokus wandern lassen.
  Result := True;
end;

procedure TAtlasWelcomeGrip.CNKeyDown(var Message: TWMKeyDown);
begin
  if HandleKey(Message.CharCode, KeyDataToShiftState(Message.KeyData)) then
  begin
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasWelcomeGrip.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button <> mbLeft then
    Exit;
  if CanFocus and (GetParentForm(Self) <> nil) and GetParentForm(Self).Visible then
    SetFocus;
  FPressed := True;
  FDragging := False;
  FPressPoint := Point(X, Y);
end;

procedure TAtlasWelcomeGrip.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not FPressed or not (ssLeft in Shift) then
    Exit;
  if not FDragging and ((Abs(X - FPressPoint.X) > ScaleValue(TAtlasArrangeStrip.DragDistance)) or
    (Abs(Y - FPressPoint.Y) > ScaleValue(TAtlasArrangeStrip.DragDistance))) then
  begin
    FDragging := True;
    if Assigned(FOnDragStart) then
      FOnDragStart(FSectionId);
  end;
  if FDragging and Assigned(FOnDragMove) then
    FOnDragMove(ClientToScreen(Point(X, Y)));
end;

procedure TAtlasWelcomeGrip.EndDrag(ADrop: Boolean);
var
  Was: Boolean;
begin
  Was := FDragging;
  FPressed := False;
  FDragging := False;
  if MouseCapture then
    MouseCapture := False;
  if Was and Assigned(FOnDragEnd) then
    FOnDragEnd(ADrop);
end;

procedure TAtlasWelcomeGrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
    EndDrag(True);
end;

{ TAtlasWelcomeSectionTools }

constructor TAtlasWelcomeSectionTools.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  Width := 2 * ToolWidth;
  ShowHint := True;
end;

function TAtlasWelcomeSectionTools.ToolAt(X: Integer): TAtlasWelcomeTool;
begin
  if (X < 0) or (X >= ClientWidth) then
    Result := TAtlasWelcomeTool.None
  else if X < ClientWidth div 2 then
    Result := TAtlasWelcomeTool.Width
  else
    Result := TAtlasWelcomeTool.Eye;
end;

procedure TAtlasWelcomeSectionTools.Paint;
var
  Half, Size, Mid, Left, Top: Integer;
  Area: TRect;
  Color_: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasWelcomeCanvas.BackgroundOf(Self);
  Canvas.FillRect(ClientRect);
  Half := ClientWidth div 2;
  Size := ScaleValue(12);
  // Breite: ein bzw. zwei Rechtecke nebeneinander; gefüllt, was der Bereich gerade belegt.
  if FHot = TAtlasWelcomeTool.Width then
    Color_ := StyleColor(Self, clHighlight)
  else
    Color_ := StyleColor(Self, clWindowText);
  Canvas.Pen.Color := Color_;
  Canvas.Brush.Color := Color_;
  Left := (Half - Size) div 2;
  Top := (ClientHeight - Size div 2) div 2;
  Area := TRect.Create(Left, Top, Left + Size div 2 - ScaleValue(1), Top + Size div 2);
  Canvas.FillRect(Area);
  Area.Offset(Size div 2 + ScaleValue(1), 0);
  if FWide then
    Canvas.FillRect(Area)
  else
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(Area);
  end;
  // Auge: Ellipse mit Pupille.
  if FHot = TAtlasWelcomeTool.Eye then
    Color_ := StyleColor(Self, clHighlight)
  else
    Color_ := StyleColor(Self, clWindowText);
  Canvas.Pen.Color := Color_;
  Canvas.Brush.Style := bsClear;
  Mid := Half + Half div 2;
  Top := ClientHeight div 2;
  Canvas.Ellipse(Mid - Size div 2, Top - Size div 3, Mid + Size div 2, Top + Size div 3);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color_;
  Canvas.Ellipse(Mid - ScaleValue(2), Top - ScaleValue(2), Mid + ScaleValue(2), Top + ScaleValue(2));
end;

procedure TAtlasWelcomeSectionTools.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: TAtlasWelcomeTool;
begin
  inherited;
  Hot := ToolAt(X);
  if Hot = FHot then
    Exit;
  FHot := Hot;
  case Hot of
    TAtlasWelcomeTool.Width:
      if FWide then
        Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeNarrow)
      else
        Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeWide);
    TAtlasWelcomeTool.Eye:
      Hint := TAtlasStrings.Text(TAtlasTextId.WelcomeArrangeEye);
  else
    Hint := '';
  end;
  Application.CancelHint;
  Invalidate;
end;

procedure TAtlasWelcomeSectionTools.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot <> TAtlasWelcomeTool.None then
  begin
    FHot := TAtlasWelcomeTool.None;
    Invalidate;
  end;
end;

procedure TAtlasWelcomeSectionTools.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
    Click(ToolAt(X));
end;

procedure TAtlasWelcomeSectionTools.Click(ATool: TAtlasWelcomeTool);
begin
  if (ATool = TAtlasWelcomeTool.None) or not Assigned(FOnTool) then
    Exit;
  try
    FOnTool(FSectionId, ATool);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
