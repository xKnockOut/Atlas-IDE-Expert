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
    cPartHeight = 22;
    cPartPadding = 8;
    cPartGap = 6;
    /// <summary>So viele Pixel Bewegung mit gedrückter Taste machen aus dem Klick ein Ziehen.</summary>
    cDragDistance = 5;
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
    function PartAt(AX, AY: Integer): Integer;
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
    cGripWidth = 16;
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
    cToolWidth = 22;
  private
    FSectionId: string;
    FWide: Boolean;
    FHot: TAtlasWelcomeTool;
    FOnTool: TProc<string, TAtlasWelcomeTool>;
    function ToolAt(AX: Integer): TAtlasWelcomeTool;
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
  Atlas.UI.Welcome.Strings;

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
  Height := ScaleValue(cPartHeight) + ScaleValue(8);
end;

procedure TAtlasArrangeStrip.SetParts(const AParts: TArray<TAtlasArrangePart>);
begin
  FParts := Copy(AParts);
  FHot := -1;
  FPressed := -1;
  FDragging := False;
  if HandleAllocated then
  begin
    Measure;
  end;
  Invalidate;
end;

function TAtlasArrangeStrip.IndexOf(AKind: TAtlasArrangePartKind; const AValue: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FParts) do
  begin
    if (FParts[mIndex].Kind = AKind) and ((AValue = '') or SameText(FParts[mIndex].Value, AValue)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasArrangeStrip.Measure;
var
  mIndex, X, Y, W, mLine, mPad, mGap, mMargin: Integer;
begin
  // Teile von links nach rechts; was nicht mehr passt, beginnt eine neue Zeile.
  Canvas.Font := Font;
  mLine := ScaleValue(cPartHeight);
  mPad := ScaleValue(cPartPadding);
  mGap := ScaleValue(cPartGap);
  mMargin := ScaleValue(4);
  X := mMargin + mGap;
  Y := mMargin;
  for mIndex := 0 to High(FParts) do
  begin
    W := Canvas.TextWidth(FParts[mIndex].Caption);
    if FParts[mIndex].Kind <> TAtlasArrangePartKind.Text then
    begin
      Inc(W, 2 * mPad);
    end;
    if (X + W > ClientWidth - mGap) and (X > mMargin + mGap) then
    begin
      X := mMargin + mGap;
      Inc(Y, mLine + mMargin);
    end;
    FParts[mIndex].Rect := TRect.Create(X, Y, X + W, Y + mLine);
    Inc(X, W + mGap);
  end;
end;

function TAtlasArrangeStrip.PreferredHeight: Integer;
var
  mPart: TAtlasArrangePart;
begin
  Result := ScaleValue(cPartHeight + 8);
  if not HandleAllocated then
  begin
    Exit;
  end;
  Measure;
  for mPart in FParts do
  begin
    if mPart.Rect.Bottom + ScaleValue(4) > Result then
    begin
      Result := mPart.Rect.Bottom + ScaleValue(4);
    end;
  end;
end;

procedure TAtlasArrangeStrip.Resize;
begin
  inherited;
  if HandleAllocated then
  begin
    Measure;
  end;
end;

function TAtlasArrangeStrip.PartAt(AX, AY: Integer): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FParts) do
  begin
    if (FParts[mIndex].Kind <> TAtlasArrangePartKind.Text) and FParts[mIndex].Rect.Contains(Point(AX, AY)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasArrangeStrip.Paint;
var
  mIndex, mRadius: Integer;
  mPart: TAtlasArrangePart;
  mTextColor, mMutedColor, mLineColor, mAccentColor, mAccentText: TColor;
begin
  inherited;
  Measure;
  mTextColor := StyleColor(Self, clWindowText);
  mMutedColor := StyleColor(Self, clGrayText);
  mLineColor := StyleColor(Self, clBtnShadow);
  mAccentColor := StyleColor(Self, clHighlight);
  mAccentText := StyleColor(Self, clHighlightText);
  mRadius := ScaleValue(6);
  Canvas.Font := Font;
  for mIndex := 0 to High(FParts) do
  begin
    mPart := FParts[mIndex];
    Canvas.Brush.Style := bsClear;
    if mPart.Kind = TAtlasArrangePartKind.Text then
    begin
      Canvas.Font.Color := mMutedColor;
      Canvas.TextOut(mPart.Rect.Left, mPart.Rect.Top + (mPart.Rect.Height - Canvas.TextHeight(mPart.Caption)) div 2,
        mPart.Caption);
      Continue;
    end;
    if mPart.Down then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := mAccentColor;
      Canvas.Pen.Color := mAccentColor;
      Canvas.Font.Color := mAccentText;
    end
    else
    begin
      if mIndex = FHot then
      begin
        Canvas.Pen.Color := mAccentColor;
      end
      else
      begin
        Canvas.Pen.Color := mLineColor;
      end;
      Canvas.Font.Color := mTextColor;
    end;
    Canvas.RoundRect(mPart.Rect.Left, mPart.Rect.Top, mPart.Rect.Right, mPart.Rect.Bottom, mRadius, mRadius);
    Canvas.Brush.Style := bsClear;
    Canvas.TextOut(mPart.Rect.Left + (mPart.Rect.Width - Canvas.TextWidth(mPart.Caption)) div 2,
      mPart.Rect.Top + (mPart.Rect.Height - Canvas.TextHeight(mPart.Caption)) div 2, mPart.Caption);
  end;
end;

procedure TAtlasArrangeStrip.ClickPart(AIndex: Integer);
begin
  if (AIndex < 0) or (AIndex > High(FParts)) or (FParts[AIndex].Kind = TAtlasArrangePartKind.Text) then
  begin
    Exit;
  end;
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
  begin
    Exit;
  end;
  FPressed := PartAt(X, Y);
  FPressPoint := Point(X, Y);
  FDragging := False;
end;

procedure TAtlasArrangeStrip.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Integer;
begin
  inherited;
  if (FPressed >= 0) and (ssLeft in Shift) then
  begin
    // Nur ausgeblendete Bereiche lassen sich auf die Seite ziehen.
    if not FDragging and (FParts[FPressed].Kind = TAtlasArrangePartKind.Hidden) and
      ((Abs(X - FPressPoint.X) > ScaleValue(cDragDistance)) or
        (Abs(Y - FPressPoint.Y) > ScaleValue(cDragDistance))) then
    begin
      FDragging := True;
      Screen.Cursor := crDrag;
      if Assigned(FOnDragStart) then
      begin
        FOnDragStart(FParts[FPressed]);
      end;
    end;
    if FDragging and Assigned(FOnDragMove) then
    begin
      FOnDragMove(ClientToScreen(Point(X, Y)));
    end;
    Exit;
  end;
  mHot := PartAt(X, Y);
  if mHot <> FHot then
  begin
    FHot := mHot;
    Hint := '';
    if mHot >= 0 then
    begin
      Hint := FParts[mHot].Hint;
    end;
    Application.CancelHint;
    Invalidate;
  end;
end;

procedure TAtlasArrangeStrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mPressed: Integer;
  mDragging: Boolean;
begin
  inherited;
  if Button <> mbLeft then
  begin
    Exit;
  end;
  mPressed := FPressed;
  mDragging := FDragging;
  FPressed := -1;
  FDragging := False;
  if mDragging then
  begin
    Screen.Cursor := crDefault;
    if Assigned(FOnDragEnd) then
    begin
      FOnDragEnd(not PtInRect(ClientRect, Point(X, Y)));
    end;
    Exit;
  end;
  if (mPressed >= 0) and (mPressed = PartAt(X, Y)) then
  begin
    ClickPart(mPressed);
  end;
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
  Width := ScaleValue(cGripWidth);
  Cursor := crSizeAll;
  ShowHint := True;
  Hint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeGrip);
end;

procedure TAtlasWelcomeGrip.Paint;
var
  mRow, mColumn, mSize, mLeft, mTop: Integer;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasWelcomeCanvas.BackgroundOf(Self);
  Canvas.FillRect(ClientRect);
  // Sechs Punkte wie ein Griff (⠿).
  mSize := ScaleValue(2);
  mLeft := (ClientWidth - 3 * mSize) div 2;
  mTop := (ClientHeight - 5 * mSize) div 2;
  if Focused then
  begin
    Canvas.Brush.Color := StyleColor(Self, clHighlight);
  end
  else
  begin
    Canvas.Brush.Color := StyleColor(Self, clGrayText);
  end;
  for mRow := 0 to 2 do
  begin
    for mColumn := 0 to 1 do
    begin
      Canvas.FillRect(TRect.Create(mLeft + mColumn * 2 * mSize, mTop + mRow * 2 * mSize,
        mLeft + mColumn * 2 * mSize + mSize, mTop + mRow * 2 * mSize + mSize));
    end;
  end;
  if Focused then
  begin
    Canvas.DrawFocusRect(ClientRect);
  end;
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
  mDirection: TAtlasWelcomeMove;
begin
  Result := False;
  if (AKey = VK_ESCAPE) and FDragging then
  begin
    EndDrag(False);
    Exit(True);
  end;
  if not (ssCtrl in AShift) or (ssAlt in AShift) or not Assigned(FOnMove) then
  begin
    Exit;
  end;
  case AKey of
    VK_UP:
      mDirection := TAtlasWelcomeMove.Up;
    VK_DOWN:
      mDirection := TAtlasWelcomeMove.Down;
    VK_LEFT:
      mDirection := TAtlasWelcomeMove.Left;
    VK_RIGHT:
      mDirection := TAtlasWelcomeMove.Right;
  else
    Exit;
  end;
  try
    FOnMove(FSectionId, mDirection);
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
  begin
    Exit;
  end;
  if CanFocus and (GetParentForm(Self) <> nil) and GetParentForm(Self).Visible then
  begin
    SetFocus;
  end;
  FPressed := True;
  FDragging := False;
  FPressPoint := Point(X, Y);
end;

procedure TAtlasWelcomeGrip.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if not FPressed or not (ssLeft in Shift) then
  begin
    Exit;
  end;
  if not FDragging and ((Abs(X - FPressPoint.X) > ScaleValue(TAtlasArrangeStrip.cDragDistance)) or
    (Abs(Y - FPressPoint.Y) > ScaleValue(TAtlasArrangeStrip.cDragDistance))) then
  begin
    FDragging := True;
    if Assigned(FOnDragStart) then
    begin
      FOnDragStart(FSectionId);
    end;
  end;
  if FDragging and Assigned(FOnDragMove) then
  begin
    FOnDragMove(ClientToScreen(Point(X, Y)));
  end;
end;

procedure TAtlasWelcomeGrip.EndDrag(ADrop: Boolean);
var
  mWas: Boolean;
begin
  mWas := FDragging;
  FPressed := False;
  FDragging := False;
  if MouseCapture then
  begin
    MouseCapture := False;
  end;
  if mWas and Assigned(FOnDragEnd) then
  begin
    FOnDragEnd(ADrop);
  end;
end;

procedure TAtlasWelcomeGrip.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
  begin
    EndDrag(True);
  end;
end;

{ TAtlasWelcomeSectionTools }

constructor TAtlasWelcomeSectionTools.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ParentColor := True;
  Width := 2 * cToolWidth;
  ShowHint := True;
end;

function TAtlasWelcomeSectionTools.ToolAt(AX: Integer): TAtlasWelcomeTool;
begin
  if (AX < 0) or (AX >= ClientWidth) then
  begin
    Result := TAtlasWelcomeTool.None;
  end
  else if AX < ClientWidth div 2 then
  begin
    Result := TAtlasWelcomeTool.Width;
  end
  else
  begin
    Result := TAtlasWelcomeTool.Eye;
  end;
end;

procedure TAtlasWelcomeSectionTools.Paint;
var
  mHalf, mSize, mMid, mLeft, mTop: Integer;
  mArea: TRect;
  mColor_: TColor;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TAtlasWelcomeCanvas.BackgroundOf(Self);
  Canvas.FillRect(ClientRect);
  mHalf := ClientWidth div 2;
  mSize := ScaleValue(12);
  // Breite: ein bzw. zwei Rechtecke nebeneinander; gefüllt, was der Bereich gerade belegt.
  if FHot = TAtlasWelcomeTool.Width then
  begin
    mColor_ := StyleColor(Self, clHighlight);
  end
  else
  begin
    mColor_ := StyleColor(Self, clWindowText);
  end;
  Canvas.Pen.Color := mColor_;
  Canvas.Brush.Color := mColor_;
  mLeft := (mHalf - mSize) div 2;
  mTop := (ClientHeight - mSize div 2) div 2;
  mArea := TRect.Create(mLeft, mTop, mLeft + mSize div 2 - ScaleValue(1), mTop + mSize div 2);
  Canvas.FillRect(mArea);
  mArea.Offset(mSize div 2 + ScaleValue(1), 0);
  if FWide then
  begin
    Canvas.FillRect(mArea);
  end
  else
  begin
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(mArea);
  end;
  // Auge: Ellipse mit Pupille.
  if FHot = TAtlasWelcomeTool.Eye then
  begin
    mColor_ := StyleColor(Self, clHighlight);
  end
  else
  begin
    mColor_ := StyleColor(Self, clWindowText);
  end;
  Canvas.Pen.Color := mColor_;
  Canvas.Brush.Style := bsClear;
  mMid := mHalf + mHalf div 2;
  mTop := ClientHeight div 2;
  Canvas.Ellipse(mMid - mSize div 2, mTop - mSize div 3, mMid + mSize div 2, mTop + mSize div 3);
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := mColor_;
  Canvas.Ellipse(mMid - ScaleValue(2), mTop - ScaleValue(2), mMid + ScaleValue(2), mTop + ScaleValue(2));
end;

procedure TAtlasWelcomeSectionTools.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: TAtlasWelcomeTool;
begin
  inherited;
  mHot := ToolAt(X);
  if mHot = FHot then
  begin
    Exit;
  end;
  FHot := mHot;
  case mHot of
    TAtlasWelcomeTool.Width:
      if FWide then
      begin
        Hint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeNarrow);
      end
      else
      begin
        Hint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeWide);
      end;
    TAtlasWelcomeTool.Eye:
      Hint := TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeArrangeEye);
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
  begin
    Click(ToolAt(X));
  end;
end;

procedure TAtlasWelcomeSectionTools.Click(ATool: TAtlasWelcomeTool);
begin
  if (ATool = TAtlasWelcomeTool.None) or not Assigned(FOnTool) then
  begin
    Exit;
  end;
  try
    FOnTool(FSectionId, ATool);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.WelcomePage, E);
  end;
end;

end.
