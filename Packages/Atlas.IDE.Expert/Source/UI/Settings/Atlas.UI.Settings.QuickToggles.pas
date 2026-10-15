unit Atlas.UI.Settings.QuickToggles;

// Fenster der Schnellschalter (#604) im Stil der Atlas-Popups (#411), wie das
// Fenster des Statusfelds (#591): oben „Atlas · Schnellschalter“, darunter
// die Schalter nach Seiten gruppiert, je Zeile ein Kästchen, die Beschriftung
// und rechts „Projekt“ (atlas.json setzt den Wert) bzw. „Sitzung“ (gilt nur
// für diese Sitzung). Unten „Alles aus für diese Sitzung“ bzw. „Alles wieder
// an“. Ein Klick oder Leertaste schaltet; das Fenster bleibt offen und zeigt
// danach, was SetItems bekommt. Schalter mit Projektwert schließen vorher das
// Fenster, weil die IDE-Schicht nachfragt, wo die Änderung gelten soll. Esc
// oder ein Klick daneben schließt. Das Fenster kennt keine Einstellung selbst:
// neue Schalter im Katalog erscheinen ohne Änderung hier.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Settings.QuickToggles;

type
  TAtlasQuickToggleWindow = class(TForm)
  private type
    TRow = record
      /// <summary>-1: Überschrift einer Seite; sonst Index in FItems.</summary>
      Item: Integer;
      Text: string;
    end;
  private
    FColors: TAtlasColors;
    FItems: TArray<TAtlasQuickToggleItem>;
    FRows: TArray<TRow>;
    FAllOff: Boolean;
    FHot: Integer;
    FClosing: Boolean;
    FAllButton: TButton;
    FOnToggle: TProc<TAtlasQuickToggleItem>;
    FOnAllOff: TProc;
    FAnchor: TPoint;
    function RowHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
    function RowRect(AIndex: Integer): TRect;
    function RowAt(const APoint: TPoint): Integer;
    function TagText(const AItem: TAtlasQuickToggleItem): string;
    procedure BuildRows;
    procedure Layout;
    procedure MoveHot(ADelta: Integer);
    procedure ToggleRow(ARow: Integer);
    procedure FormDeactivate(Sender: TObject);
    procedure AllClick(Sender: TObject);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure CMDialogKey(var Message: TCMDialogKey); message CM_DIALOGKEY;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor CreateToggles(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Schalter und „Alles aus“ neu setzen (auch bei offenem Fenster).</summary>
    procedure SetItems(const AItems: TArray<TAtlasQuickToggleItem>; AAllOff: Boolean);
    /// <summary>Zeigt das Fenster mit der linken unteren Ecke an AAnchor (Bildschirm).</summary>
    procedure ShowAbove(const AAnchor: TPoint);
    /// <summary>Schließt; das Fenster gibt sich danach selbst frei.</summary>
    procedure Dismiss;
    /// <summary>Zum Testen: Zeile ARow anklicken (Überschriften tun nichts).</summary>
    procedure ClickRow(ARow: Integer);
    /// <summary>Zum Testen: Zeilen samt Überschriften, Text und Schalter der Zeile (-1 = Überschrift).</summary>
    function RowCount: Integer;
    function RowText(ARow: Integer): string;
    function RowItem(ARow: Integer): Integer;
    property Items: TArray<TAtlasQuickToggleItem> read FItems;
    property AllButton: TButton read FAllButton;
    property HotRow: Integer read FHot;
    /// <summary>Schalter umschalten; bei Projektwerten erst nach dem Schließen.</summary>
    property OnToggle: TProc<TAtlasQuickToggleItem> read FOnToggle write FOnToggle;
    /// <summary>„Alles aus für diese Sitzung“ bzw. „Alles wieder an“.</summary>
    property OnAllOff: TProc read FOnAllOff write FOnAllOff;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.UI.Strings;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

{ TAtlasQuickToggleWindow }

constructor TAtlasQuickToggleWindow.CreateToggles(AOwner: TComponent; const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FColors := AColors;
  FHot := -1;
  BorderStyle := bsNone;
  KeyPreview := True;
  DoubleBuffered := True;
  Color := ToColor(FColors.Surface);
  Font.Name := 'Segoe UI';
  Font.Size := 9;
  Caption := TAtlasStrings.Text(TAtlasTextId.QuickTogglesTitle);
  OnDeactivate := FormDeactivate;
  FAllButton := TButton.Create(Self);
  FAllButton.Parent := Self;
  FAllButton.OnClick := AllClick;
  FAllButton.TabStop := False;
  SetItems(nil, False);
end;

procedure TAtlasQuickToggleWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

function TAtlasQuickToggleWindow.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(8);
end;

function TAtlasQuickToggleWindow.HeaderHeight: Integer;
begin
  Result := RowHeight + ScaleValue(6);
end;

function TAtlasQuickToggleWindow.ButtonsHeight: Integer;
begin
  Result := ScaleValue(40);
end;

function TAtlasQuickToggleWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := Rect(ScaleValue(4), HeaderHeight + AIndex * RowHeight, ClientWidth - ScaleValue(4),
    HeaderHeight + (AIndex + 1) * RowHeight);
end;

function TAtlasQuickToggleWindow.RowAt(const APoint: TPoint): Integer;
var
  Index: Integer;
begin
  for Index := 0 to High(FRows) do
    if PtInRect(RowRect(Index), APoint) then
      Exit(Index);
  Result := -1;
end;

function TAtlasQuickToggleWindow.TagText(const AItem: TAtlasQuickToggleItem): string;
begin
  Result := '';
  if AItem.Session then
    Result := TAtlasStrings.Text(TAtlasTextId.QuickTogglesSession)
  else if AItem.Project then
    Result := TAtlasStrings.Text(TAtlasTextId.QuickTogglesProject);
end;

procedure TAtlasQuickToggleWindow.BuildRows;
var
  Index: Integer;
  Page: string;
  Row: TRow;
begin
  FRows := nil;
  Page := #0;
  for Index := 0 to High(FItems) do
  begin
    if not SameText(FItems[Index].Toggle.Page, Page) then
    begin
      Page := FItems[Index].Toggle.Page;
      Row.Item := -1;
      Row.Text := Page;
      FRows := FRows + [Row];
    end;
    Row.Item := Index;
    Row.Text := FItems[Index].Toggle.Caption;
    FRows := FRows + [Row];
  end;
end;

procedure TAtlasQuickToggleWindow.Layout;
var
  Width_, ButtonWidth, Tags: Integer;
  Row: TRow;
begin
  Canvas.Font := Font;
  Tags := Max(Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.QuickTogglesProject)),
    Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.QuickTogglesSession)));
  Width_ := ScaleValue(280);
  for Row in FRows do
    Width_ := Max(Width_, Canvas.TextWidth(Row.Text) + Tags + ScaleValue(64));
  Width_ := Min(Width_, ScaleValue(720));
  ButtonWidth := Max(Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOff)),
    Canvas.TextWidth(TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOn))) + ScaleValue(24);
  Width_ := Max(Width_, ButtonWidth + ScaleValue(20));
  ClientWidth := Width_;
  ClientHeight := HeaderHeight + Length(FRows) * RowHeight + ButtonsHeight;
  FAllButton.SetBounds(ScaleValue(10), ClientHeight - ButtonsHeight + ScaleValue(8), ButtonWidth, ScaleValue(25));
end;

procedure TAtlasQuickToggleWindow.SetItems(const AItems: TArray<TAtlasQuickToggleItem>; AAllOff: Boolean);
begin
  FItems := AItems;
  FAllOff := AAllOff;
  BuildRows;
  if FHot > High(FRows) then
    FHot := -1;
  if FAllOff then
    FAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOn)
  else
    FAllButton.Caption := TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOff);
  Layout;
  if Visible then
    SetBounds(Left, FAnchor.Y - Height, Width, Height);
  Invalidate;
end;

procedure TAtlasQuickToggleWindow.ShowAbove(const AAnchor: TPoint);
var
  Area: TRect;
  Left_, Top_: Integer;
begin
  Layout;
  Area := Screen.MonitorFromPoint(AAnchor).WorkareaRect;
  Left_ := EnsureRange(AAnchor.X, Area.Left, Max(Area.Left, Area.Right - Width));
  Top_ := Max(Area.Top, AAnchor.Y - Height);
  FAnchor := Point(Left_, Top_ + Height);
  SetBounds(Left_, Top_, Width, Height);
  Show;
  SetFocus;
end;

procedure TAtlasQuickToggleWindow.Dismiss;
begin
  if FClosing then
    Exit;
  FClosing := True;
  Close;
  Release;
end;

procedure TAtlasQuickToggleWindow.FormDeactivate(Sender: TObject);
begin
  Dismiss;
end;

procedure TAtlasQuickToggleWindow.AllClick(Sender: TObject);
begin
  if Assigned(FOnAllOff) then
    FOnAllOff();
end;

procedure TAtlasQuickToggleWindow.ToggleRow(ARow: Integer);
var
  Item: TAtlasQuickToggleItem;
  Handler: TProc<TAtlasQuickToggleItem>;
begin
  if (ARow < 0) or (ARow > High(FRows)) or (FRows[ARow].Item < 0) or FClosing then
    Exit;
  Item := FItems[FRows[ARow].Item];
  Handler := FOnToggle;
  if not Assigned(Handler) then
    Exit;
  if not Item.Project or Item.Session then
  begin
    // Gilt sofort; das Fenster bleibt offen und bekommt den neuen Stand über SetItems.
    Handler(Item);
    Exit;
  end;
  // Projektwert: Die IDE-Schicht fragt nach, wo die Änderung gelten soll; das Fenster schließt vorher.
  Dismiss;
  TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
    procedure
    begin
      Handler(Item);
    end);
end;

procedure TAtlasQuickToggleWindow.ClickRow(ARow: Integer);
begin
  ToggleRow(ARow);
end;

function TAtlasQuickToggleWindow.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TAtlasQuickToggleWindow.RowText(ARow: Integer): string;
begin
  Result := FRows[ARow].Text;
end;

function TAtlasQuickToggleWindow.RowItem(ARow: Integer): Integer;
begin
  Result := FRows[ARow].Item;
end;

procedure TAtlasQuickToggleWindow.MoveHot(ADelta: Integer);
var
  Row, Count: Integer;
begin
  Count := Length(FRows);
  if Count = 0 then
    Exit;
  Row := FHot;
  repeat
    Row := Row + ADelta;
    if Row < 0 then
      Row := Count - 1;
    if Row >= Count then
      Row := 0;
  until (FRows[Row].Item >= 0) or (Row = FHot);
  if FRows[Row].Item < 0 then
    Exit;
  FHot := Row;
  Invalidate;
end;

procedure TAtlasQuickToggleWindow.CMDialogKey(var Message: TCMDialogKey);
begin
  // Pfeiltasten und Tab bewegen die Auswahl statt des Fokus.
  if (Message.CharCode = VK_UP) or (Message.CharCode = VK_DOWN) or (Message.CharCode = VK_TAB) then
  begin
    if Message.CharCode = VK_UP then
      MoveHot(-1)
    else
      MoveHot(1);
    Message.Result := 1;
    Exit;
  end;
  inherited;
end;

procedure TAtlasQuickToggleWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  case Key of
    VK_ESCAPE:
      begin
        Key := 0;
        Dismiss;
        Exit;
      end;
    VK_UP:
      begin
        Key := 0;
        MoveHot(-1);
        Exit;
      end;
    VK_DOWN:
      begin
        Key := 0;
        MoveHot(1);
        Exit;
      end;
    VK_SPACE, VK_RETURN:
      begin
        Key := 0;
        ToggleRow(FHot);
        Exit;
      end;
  end;
  inherited;
end;

procedure TAtlasQuickToggleWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Row: Integer;
begin
  inherited;
  Row := RowAt(Point(X, Y));
  if (Row >= 0) and (FRows[Row].Item < 0) then
    Row := -1;
  if Row >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if (Row >= 0) and (Row <> FHot) then
  begin
    FHot := Row;
    Invalidate;
  end;
end;

procedure TAtlasQuickToggleWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  Cursor := crDefault;
end;

procedure TAtlasQuickToggleWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if Button = mbLeft then
    ToggleRow(RowAt(Point(X, Y)));
end;

procedure TAtlasQuickToggleWindow.Paint;
var
  Index, Box: Integer;
  Row, Part, Check: TRect;
  Item: TAtlasQuickToggleItem;
  Text: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Kopf: „Atlas · Schnellschalter“, bei „Alles aus“ der Hinweis darauf.
  Part := Rect(ScaleValue(12), 0, ClientWidth - ScaleValue(8), HeaderHeight);
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  Text := 'Atlas · ' + TAtlasStrings.Text(TAtlasTextId.QuickTogglesTitle);
  DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  if FAllOff then
  begin
    Canvas.Font.Color := ToColor(FColors.Warn);
    Text := TAtlasStrings.Text(TAtlasTextId.QuickTogglesAllOffActive);
    DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
  end;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, HeaderHeight - ScaleValue(3));
  Canvas.LineTo(ClientWidth, HeaderHeight - ScaleValue(3));
  Box := ScaleValue(12);
  for Index := 0 to High(FRows) do
  begin
    Row := RowRect(Index);
    Canvas.Brush.Style := bsClear;
    if FRows[Index].Item < 0 then
    begin
      // Überschrift der Seite.
      Canvas.Font.Style := [fsBold];
      Canvas.Font.Color := ToColor(FColors.Muted);
      Part := Rect(Row.Left + ScaleValue(6), Row.Top, Row.Right, Row.Bottom);
      Text := FRows[Index].Text;
      DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
      Canvas.Font.Style := [];
      Continue;
    end;
    Item := FItems[FRows[Index].Item];
    if Index = FHot then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Selection);
      Canvas.FillRect(Row);
    end;
    // Kästchen: gefüllt in Akzentfarbe, wenn an.
    Check := Rect(Row.Left + ScaleValue(14), (Row.Top + Row.Bottom - Box) div 2, Row.Left + ScaleValue(14) + Box,
      (Row.Top + Row.Bottom + Box) div 2);
    Canvas.Pen.Color := ToColor(FColors.Accent);
    if Item.Checked then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Accent);
    end
    else
      Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(Check);
    if Item.Checked then
    begin
      Canvas.Pen.Color := ToColor(FColors.Surface);
      Canvas.Pen.Width := Max(1, ScaleValue(2));
      Canvas.MoveTo(Check.Left + Box div 5, Check.Top + Box div 2);
      Canvas.LineTo(Check.Left + Box * 2 div 5, Check.Bottom - Box div 4);
      Canvas.LineTo(Check.Right - Box div 5, Check.Top + Box div 4);
      Canvas.Pen.Width := 1;
    end;
    Canvas.Brush.Style := bsClear;
    Part := Rect(Check.Right + ScaleValue(8), Row.Top, Row.Right - ScaleValue(6), Row.Bottom);
    Text := TagText(Item);
    if Text <> '' then
    begin
      Canvas.Font.Color := ToColor(FColors.Muted);
      DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_RIGHT or DT_NOPREFIX);
      Part.Right := Part.Right - Canvas.TextWidth(Text) - ScaleValue(8);
    end;
    Canvas.Font.Color := ToColor(FColors.Text);
    Text := FRows[Index].Text;
    DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
  end;
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, ClientHeight - ButtonsHeight);
  Canvas.LineTo(ClientWidth, ClientHeight - ButtonsHeight);
  // Rahmen des Fensters in Akzentfarbe.
  Canvas.Brush.Style := bsClear;
  Canvas.Pen.Color := ToColor(FColors.Accent);
  Canvas.Rectangle(ClientRect);
  Canvas.Brush.Style := bsSolid;
end;

end.
