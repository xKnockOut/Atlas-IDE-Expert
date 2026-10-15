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
  Atlas.Core.Style.Color,
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
    /// <summary>Farbe des Punkts für AState.</summary>
    class function StateColor(const AColors: TAtlasColors; AState: TAtlasStatusState): TAtlasColor; static;
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

class function TAtlasStatusWindow.StateColor(const AColors: TAtlasColors; AState: TAtlasStatusState): TAtlasColor;
begin
  case AState of
    TAtlasStatusState.Green:
      Result := AColors.Add;
    TAtlasStatusState.Yellow:
      Result := AColors.Warn;
    TAtlasStatusState.Red:
      Result := AColors.Error;
  else
    Result := AColors.Muted;
  end;
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
  Index: Integer;
begin
  for Index := 0 to High(FItems) do
    if PtInRect(RowRect(Index), APoint) then
      Exit(Index);
  Result := -1;
end;

procedure TAtlasStatusWindow.Layout;
var
  Width_, Index, ButtonWidth: Integer;
  Item: IAtlasStatusItem;
begin
  Canvas.Font := Font;
  Width_ := ScaleValue(280);
  for Item in FItems do
    Width_ := Max(Width_, Canvas.TextWidth(Item.Text) + ScaleValue(44));
  Width_ := Min(Width_, ScaleValue(720));
  ButtonWidth := Max(Canvas.TextWidth(FLogButton.Caption), Canvas.TextWidth(FRestartButton.Caption)) +
    ScaleValue(24);
  Width_ := Max(Width_, 2 * ButtonWidth + ScaleValue(30));
  ClientWidth := Width_;
  ClientHeight := HeaderHeight + Length(FItems) * RowHeight + ButtonsHeight;
  Index := ClientHeight - ButtonsHeight + ScaleValue(8);
  FLogButton.SetBounds(ScaleValue(10), Index, ButtonWidth, ScaleValue(25));
  FRestartButton.SetBounds(ScaleValue(20) + ButtonWidth, Index, ButtonWidth, ScaleValue(25));
end;

procedure TAtlasStatusWindow.SetItems(const AItems: TArray<IAtlasStatusItem>);
begin
  FItems := AItems;
  if FHot > High(FItems) then
    FHot := -1;
  Layout;
  if Visible then
    SetBounds(FAnchor.X, FAnchor.Y - Height, Width, Height);
  Invalidate;
end;

procedure TAtlasStatusWindow.ShowAbove(const AAnchor: TPoint);
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

procedure TAtlasStatusWindow.Dismiss;
begin
  if FClosing then
    Exit;
  FClosing := True;
  Close;
  Release;
end;

procedure TAtlasStatusWindow.CloseAndRun(const AProc: TProc);
begin
  if FClosing then
    Exit;
  Dismiss;
  // Erst nach dem Schließen ausführen: die Aktion öffnet evtl. ein Menü oder einen Dialog.
  if Assigned(AProc) then
    TAtlasMainThread.ForceQueue(TAtlasFeature.Status,
      procedure
      begin
        AProc();
      end);
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
  Row: Integer;
begin
  inherited;
  Row := RowAt(Point(X, Y));
  if (Row >= 0) and not FItems[Row].HasAction then
    Row := -1;
  if Row >= 0 then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if Row <> FHot then
  begin
    FHot := Row;
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
  Row: Integer;
  Item: IAtlasStatusItem;
  Handler: TProc<IAtlasStatusItem>;
begin
  inherited;
  Row := RowAt(Point(X, Y));
  if (Button <> mbLeft) or (Row < 0) or not FItems[Row].HasAction then
    Exit;
  Item := FItems[Row];
  Handler := FOnItem;
  CloseAndRun(
    procedure
    begin
      if Assigned(Handler) then
        Handler(Item)
      else
        Item.Execute;
    end);
end;

procedure TAtlasStatusWindow.DrawDot(const ACenter: TPoint; AState: TAtlasStatusState);
var
  Radius: Integer;
begin
  Radius := ScaleValue(4);
  Canvas.Pen.Color := ToColor(StateColor(FColors, AState));
  Canvas.Brush.Color := ToColor(StateColor(FColors, AState));
  Canvas.Brush.Style := bsSolid;
  Canvas.Ellipse(ACenter.X - Radius, ACenter.Y - Radius, ACenter.X + Radius + 1, ACenter.Y + Radius + 1);
end;

procedure TAtlasStatusWindow.Paint;
var
  Index: Integer;
  Row, Part: TRect;
  Item: IAtlasStatusItem;
  Text: string;
begin
  Canvas.Font := Font;
  Canvas.Brush.Color := ToColor(FColors.Surface);
  Canvas.FillRect(ClientRect);
  // Kopf: Punkt des Gesamtzustands und „Atlas“.
  Part := Rect(ScaleValue(12), 0, ClientWidth - ScaleValue(8), HeaderHeight);
  DrawDot(Point(Part.Left + ScaleValue(4), (Part.Top + Part.Bottom) div 2), TAtlasStatusSummary.Overall(FItems));
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(FColors.Text);
  Part.Left := Part.Left + ScaleValue(16);
  Text := TAtlasStatusSummary.FieldCaption;
  DrawText(Canvas.Handle, PChar(Text), -1, Part, DT_SINGLELINE or DT_VCENTER or DT_NOPREFIX);
  Canvas.Font.Style := [];
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, HeaderHeight - ScaleValue(3));
  Canvas.LineTo(ClientWidth, HeaderHeight - ScaleValue(3));
  for Index := 0 to High(FItems) do
  begin
    Item := FItems[Index];
    Row := RowRect(Index);
    if Index = FHot then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(FColors.Selection);
      Canvas.FillRect(Row);
    end;
    DrawDot(Point(Row.Left + ScaleValue(12), (Row.Top + Row.Bottom) div 2), Item.State);
    Canvas.Brush.Style := bsClear;
    Part := Rect(Row.Left + ScaleValue(24), Row.Top, Row.Right - ScaleValue(4), Row.Bottom);
    if Item.HasAction then
      Canvas.Font.Color := ToColor(FColors.Accent)
    else
      Canvas.Font.Color := ToColor(FColors.Text);
    Text := Item.Text;
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
