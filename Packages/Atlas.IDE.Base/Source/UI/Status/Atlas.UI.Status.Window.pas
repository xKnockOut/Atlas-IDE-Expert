unit Atlas.UI.Status.Window;

// Fenster des Atlas-Statusfelds (#591) im Stil der Atlas-Popups (#411):
// oben „Atlas“ mit dem Punkt des Gesamtzustands, darunter je Zeile der
// Registry ein farbiger Punkt und ihr Text, unten die Knöpfe „Protokoll
// öffnen“ und „Server neu starten“. Zeilen mit Aktion sind anklickbar (Hand-
// Cursor, Hervorhebung unter der Maus). Das Fenster öffnet über dem Feld in
// der Statusleiste, nimmt den Fokus (eigene Knöpfe) und schließt mit Esc oder
// einem Klick daneben. Es zeigt, was SetItems bekommt; neue Zeilen brauchen
// hier keine Änderung.

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
  Atlas.Core.Style.Palette,
  Atlas.Core.Status.Contract;

type
  TAtlasStatusWindow = class(TForm)
  private
    FColors: TAtlasColors;
    FItems: TArray<IAtlasStatusItem>;
    FHot: Integer;
    FClosing: Boolean;
    FLogButton: TButton;
    FRestartButton: TButton;
    FOnOpenLog: TProc;
    FOnRestart: TProc;
    FOnItem: TProc<IAtlasStatusItem>;
    FAnchor: TPoint;
    function RowHeight: Integer;
    function HeaderHeight: Integer;
    function ButtonsHeight: Integer;
    function RowRect(AIndex: Integer): TRect;
    function RowAt(const APoint: TPoint): Integer;
    procedure Layout;
    procedure DrawDot(const ACenter: TPoint; AState: TAtlasStatusState);
    procedure FormDeactivate(Sender: TObject);
    procedure LogClick(Sender: TObject);
    procedure RestartClick(Sender: TObject);
    procedure CloseAndRun(const AProc: TProc);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure CreateParams(var Params: TCreateParams); override;
    procedure Paint; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
  public
    constructor CreateStatus(AOwner: TComponent; const AColors: TAtlasColors);
    /// <summary>Zeilen neu setzen (auch bei offenem Fenster); Größe und Lage folgen.</summary>
    procedure SetItems(const AItems: TArray<IAtlasStatusItem>);
    /// <summary>Zeigt das Fenster mit der linken unteren Ecke an AAnchor (Bildschirm, Oberkante des Felds).</summary>
    procedure ShowAbove(const AAnchor: TPoint);
    /// <summary>Schließt ohne Aktion; das Fenster gibt sich danach selbst frei.</summary>
    procedure Dismiss;
    property Items: TArray<IAtlasStatusItem> read FItems;
    /// <summary>Zum Testen: die Knöpfe.</summary>
    property LogButton: TButton read FLogButton;
    property RestartButton: TButton read FRestartButton;
    /// <summary>Aktionen; laufen nach dem Schließen des Fensters.</summary>
    property OnOpenLog: TProc read FOnOpenLog write FOnOpenLog;
    property OnRestart: TProc read FOnRestart write FOnRestart;
    property OnItem: TProc<IAtlasStatusItem> read FOnItem write FOnItem;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Status.Registry,
  Atlas.UI.Popup.Draw,
  Atlas.UI.Strings;

{ TAtlasStatusWindow }

constructor TAtlasStatusWindow.CreateStatus(AOwner: TComponent; const AColors: TAtlasColors);
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
  OnDeactivate := FormDeactivate;
  FLogButton := TButton.Create(Self);
  FLogButton.Parent := Self;
  FLogButton.Caption := TAtlasStrings.Text(TAtlasTextId.StatusOpenLog);
  FLogButton.OnClick := LogClick;
  FRestartButton := TButton.Create(Self);
  FRestartButton.Parent := Self;
  FRestartButton.Caption := TAtlasStrings.Text(TAtlasTextId.StatusRestartServer);
  FRestartButton.OnClick := RestartClick;
  Layout;
end;

procedure TAtlasStatusWindow.CreateParams(var Params: TCreateParams);
begin
  inherited;
  Params.WindowClass.Style := Params.WindowClass.Style or CS_DROPSHADOW;
end;

function TAtlasStatusWindow.RowHeight: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextHeight('Wg') + ScaleValue(8);
end;

function TAtlasStatusWindow.HeaderHeight: Integer;
begin
  Result := RowHeight + ScaleValue(6);
end;

function TAtlasStatusWindow.ButtonsHeight: Integer;
begin
  Result := ScaleValue(40);
end;

function TAtlasStatusWindow.RowRect(AIndex: Integer): TRect;
begin
  Result := Rect(ScaleValue(4), HeaderHeight + AIndex * RowHeight, ClientWidth - ScaleValue(4),
    HeaderHeight + (AIndex + 1) * RowHeight);
end;

function TAtlasStatusWindow.RowAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FItems) do
  begin
    if PtInRect(RowRect(mIndex), APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasStatusWindow.Layout;
var
  mWidth_, mIndex, mButtonWidth: Integer;
  mItem: IAtlasStatusItem;
begin
  Canvas.Font := Font;
  mWidth_ := ScaleValue(280);
  for mItem in FItems do
  begin
    mWidth_ := Max(mWidth_, Canvas.TextWidth(mItem.Text) + ScaleValue(44));
  end;
  mWidth_ := Min(mWidth_, ScaleValue(720));
  mButtonWidth := Max(Canvas.TextWidth(FLogButton.Caption), Canvas.TextWidth(FRestartButton.Caption)) +
    ScaleValue(24);
  mWidth_ := Max(mWidth_, 2 * mButtonWidth + ScaleValue(30));
  ClientWidth := mWidth_;
  ClientHeight := HeaderHeight + Length(FItems) * RowHeight + ButtonsHeight;
  mIndex := ClientHeight - ButtonsHeight + ScaleValue(8);
  FLogButton.SetBounds(ScaleValue(10), mIndex, mButtonWidth, ScaleValue(25));
  FRestartButton.SetBounds(ScaleValue(20) + mButtonWidth, mIndex, mButtonWidth, ScaleValue(25));
end;

procedure TAtlasStatusWindow.SetItems(const AItems: TArray<IAtlasStatusItem>);
begin
  FItems := AItems;
  if FHot > High(FItems) then
  begin
    FHot := -1;
  end;
  Layout;
  if Visible then
  begin
    SetBounds(FAnchor.X, FAnchor.Y - Height, Width, Height);
  end;
  Invalidate;
end;

procedure TAtlasStatusWindow.ShowAbove(const AAnchor: TPoint);
var
  mArea: TRect;
  mLeft_, mTop_: Integer;
begin
  Layout;
  mArea := Screen.MonitorFromPoint(AAnchor).WorkareaRect;
  mLeft_ := EnsureRange(AAnchor.X, mArea.Left, Max(mArea.Left, mArea.Right - Width));
  mTop_ := Max(mArea.Top, AAnchor.Y - Height);
  FAnchor := Point(mLeft_, mTop_ + Height);
  SetBounds(mLeft_, mTop_, Width, Height);
  Show;
  SetFocus;
end;

procedure TAtlasStatusWindow.Dismiss;
begin
  if FClosing then
  begin
    Exit;
  end;
  FClosing := True;
  Close;
  Release;
end;

procedure TAtlasStatusWindow.CloseAndRun(const AProc: TProc);
begin
  if FClosing then
  begin
    Exit;
  end;
  Dismiss;
  // Erst nach dem Schließen ausführen: die Aktion öffnet evtl. ein Menü oder einen Dialog.
  if Assigned(AProc) then
  begin
    TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
      procedure
      begin
        AProc();
      end);
  end;
end;

procedure TAtlasStatusWindow.FormDeactivate(Sender: TObject);
begin
  Dismiss;
end;

procedure TAtlasStatusWindow.LogClick(Sender: TObject);
begin
  CloseAndRun(FOnOpenLog);
end;

procedure TAtlasStatusWindow.RestartClick(Sender: TObject);
begin
  CloseAndRun(FOnRestart);
end;

procedure TAtlasStatusWindow.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Dismiss;
    Exit;
  end;
  inherited;
end;

procedure TAtlasStatusWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mRow: Integer;
begin
  inherited;
  mRow := RowAt(Point(X, Y));
  if (mRow >= 0) and not FItems[mRow].HasAction then
  begin
    mRow := -1;
  end;
  if mRow >= 0 then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if mRow <> FHot then
  begin
    FHot := mRow;
    Invalidate;
  end;
end;

procedure TAtlasStatusWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FHot >= 0 then
  begin
    FHot := -1;
    Invalidate;
  end;
end;

procedure TAtlasStatusWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  mRow: Integer;
  mItem: IAtlasStatusItem;
  mHandler: TProc<IAtlasStatusItem>;
begin
  inherited;
  mRow := RowAt(Point(X, Y));
  if (Button <> mbLeft) or (mRow < 0) or not FItems[mRow].HasAction then
  begin
    Exit;
  end;
  mItem := FItems[mRow];
  mHandler := FOnItem;
  CloseAndRun(
    procedure
    begin
      if Assigned(mHandler) then
      begin
        mHandler(mItem);
      end
      else
      begin
        mItem.Execute;
      end;
    end);
end;

procedure TAtlasStatusWindow.DrawDot(const ACenter: TPoint; AState: TAtlasStatusState);
var
  mRadius: Integer;
begin
  mRadius := ScaleValue(4);
  // Signalfarbe mit Rand (#1255), nicht die Textfarben Add/Warn/Error.
  Canvas.Pen.Color := ToColor(FColors.Signals.ForStatus(AState).Ring);
  Canvas.Brush.Color := ToColor(FColors.Signals.ForStatus(AState).Fill);
  Canvas.Brush.Style := bsSolid;
  Canvas.Ellipse(ACenter.X - mRadius, ACenter.Y - mRadius, ACenter.X + mRadius + 1, ACenter.Y + mRadius + 1);
end;

procedure TAtlasStatusWindow.Paint;
var
  mIndex: Integer;
  mRow, mPart: TRect;
  mItem: IAtlasStatusItem;
  mText: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Kopf: Punkt des Gesamtzustands und „Atlas“.
  mPart := Rect(ScaleValue(12), 0, ClientWidth - ScaleValue(8), HeaderHeight);
  DrawDot(Point(mPart.Left + ScaleValue(4), (mPart.Top + mPart.Bottom) div 2), TAtlasStatusSummary.Overall(FItems));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  mPart.Left := mPart.Left + ScaleValue(16);
  mText := TAtlasStatusSummary.cFieldCaption;
  DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, HeaderHeight - ScaleValue(3));
  Canvas.LineTo(ClientWidth, HeaderHeight - ScaleValue(3));
  for mIndex := 0 to High(FItems) do
  begin
    mItem := FItems[mIndex];
    mRow := RowRect(mIndex);
    if mIndex = FHot then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Selection);
      Canvas.FillRect(mRow);
    end;
    DrawDot(Point(mRow.Left + ScaleValue(12), (mRow.Top + mRow.Bottom) div 2), mItem.State);
    Canvas.Brush.Style := bsClear;
    mPart := Rect(mRow.Left + ScaleValue(24), mRow.Top, mRow.Right - ScaleValue(4), mRow.Bottom);
    if mItem.HasAction then
    begin
      Canvas.Font.Color := ToColor(FColors.Accent);
    end
    else
    begin
      Canvas.Font.Color := ToColor(FColors.Text);
    end;
    mText := mItem.Text;
    DrawText(Canvas.Handle, PChar(mText), -1, mPart, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX or DT_END_ELLIPSIS);
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
