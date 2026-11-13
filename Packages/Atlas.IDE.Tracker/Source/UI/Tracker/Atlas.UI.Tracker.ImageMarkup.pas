unit Atlas.UI.Tracker.ImageMarkup;

// Einfaches Markierwerkzeug für Bilder vor dem Anhängen (#1276), reine VCL:
//   [Rechteck] [Pfeil] [Schwärzen] [Rückgängig]            [Übernehmen] [Abbrechen]
//   Bild, auf Fenstergröße verkleinert; Ziehen mit der Maus legt eine Form an.
// - Rechteck und Pfeil in Rot (LineWidth Pixel), Schwärzen füllt deckend
//   schwarz (für vertrauliche Daten); im Bild selbst, nicht als Ebene, damit
//   nichts Geschwärztes mitgesendet wird.
// - Formen in Bildkoordinaten (TAtlasMarkupShape); Apply zeichnet sie erst bei
//   „Übernehmen“ in das Bild. Rückgängig nimmt die letzte Form zurück.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics,
  Atlas.UI.Foundation.Dialog;

type
{$SCOPEDENUMS ON}
  TAtlasMarkupTool = (Rectangle, Arrow, Blacken);
{$SCOPEDENUMS OFF}

  TAtlasMarkupShape = record
    Tool: TAtlasMarkupTool;
    StartPoint: TPoint;
    EndPoint: TPoint;
    class function Create(ATool: TAtlasMarkupTool; const AStart, AEnd: TPoint): TAtlasMarkupShape; static;
    /// <summary>Rechteck mit Left &lt;= Right und Top &lt;= Bottom.</summary>
    function Bounds: TRect;
    /// <summary>Zu klein zum Zeichnen (versehentlicher Klick)?</summary>
    function Tiny: Boolean;
  end;

  TAtlasMarkupShapes = TArray<TAtlasMarkupShape>;

  TAtlasImageMarkup = record
  public const
    cLineWidth = 3;
    cMarkColor = clRed; // window-ok: Markierung im Bildschirmfoto, keine Textfarbe
    /// <summary>Länge der Pfeilspitze in Pixeln.</summary>
    cHeadLength = 16;
    cMinSize = 3;
  public
    /// <summary>AShape auf ACanvas, Bildkoordinaten mal AScale.</summary>
    class procedure Draw(ACanvas: TCanvas; const AShape: TAtlasMarkupShape; AScale: Double); static;
    /// <summary>Alle Formen in ABitmap zeichnen (in der Reihenfolge).</summary>
    class procedure Apply(ABitmap: TBitmap; const AShapes: TAtlasMarkupShapes); static;
  end;

  TAtlasImageMarkupForm = class(TAtlasDialog)
  private
    FBitmap: TBitmap;
    FShapes: TAtlasMarkupShapes;
    FTool: TAtlasMarkupTool;
    FBox: TPaintBox;
    FToolButtons: array[TAtlasMarkupTool] of TButton;
    FUndo: TButton;
    FDragging: Boolean;
    FDrag: TAtlasMarkupShape;
    function Scale: Double;
    function ToImage(AX, AY: Integer): TPoint;
    procedure BoxPaint(Sender: TObject);
    procedure BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure ToolClick(Sender: TObject);
    procedure UndoClick(Sender: TObject);
    procedure UpdateButtons;
    procedure AddToolBar;
    procedure AddBottomButtons;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    /// <summary>ABitmap bleibt beim Aufrufer; geändert wird es erst mit ApplyTo.</summary>
    constructor CreateFor(AOwner: TComponent; ABitmap: TBitmap);
    destructor Destroy; override;
    procedure AddShape(const AShape: TAtlasMarkupShape);
    procedure Undo;
    /// <summary>Formen in ABitmap übernehmen.</summary>
    procedure ApplyTo(ABitmap: TBitmap);
    /// <summary>Zeigt den Editor; mit „Übernehmen“ True und die Formen sind in ABitmap gezeichnet.</summary>
    class function Execute(ABitmap: TBitmap): Boolean; static;
    property Shapes: TAtlasMarkupShapes read FShapes;
    property Tool: TAtlasMarkupTool read FTool write FTool;
  end;

implementation

uses
  System.Math,
  System.UITypes,
  Atlas.UI.Strings,  Atlas.UI.Tracker.Attach.Strings;

const
  cGap = 8;

{ TAtlasMarkupShape }

class function TAtlasMarkupShape.Create(ATool: TAtlasMarkupTool; const AStart, AEnd: TPoint): TAtlasMarkupShape;
begin
  Result.Tool := ATool;
  Result.StartPoint := AStart;
  Result.EndPoint := AEnd;
end;

function TAtlasMarkupShape.Bounds: TRect;
begin
  Result := Rect(Min(StartPoint.X, EndPoint.X), Min(StartPoint.Y, EndPoint.Y), Max(StartPoint.X, EndPoint.X),
    Max(StartPoint.Y, EndPoint.Y));
end;

function TAtlasMarkupShape.Tiny: Boolean;
begin
  Result := (Abs(EndPoint.X - StartPoint.X) < TAtlasImageMarkup.cMinSize) and
    (Abs(EndPoint.Y - StartPoint.Y) < TAtlasImageMarkup.cMinSize);
end;

{ TAtlasImageMarkup }

class procedure TAtlasImageMarkup.Draw(ACanvas: TCanvas; const AShape: TAtlasMarkupShape; AScale: Double);
var
  mRect: TRect;
  mFrom, mTo: TPoint;
  mAngle, mHead: Double;
  mHeadPoints: array[0..2] of TPoint;
begin
  mRect := AShape.Bounds;
  mRect := Rect(Round(mRect.Left * AScale), Round(mRect.Top * AScale), Round(mRect.Right * AScale),
    Round(mRect.Bottom * AScale));
  case AShape.Tool of
    TAtlasMarkupTool.Blacken:
      begin
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := clBlack;
        ACanvas.FillRect(mRect);
      end;
    TAtlasMarkupTool.Rectangle:
      begin
        ACanvas.Brush.Style := bsClear;
        ACanvas.Pen.Color := cMarkColor;
        ACanvas.Pen.Width := Max(1, Round(cLineWidth * AScale));
        ACanvas.Pen.Style := psSolid;
        ACanvas.Rectangle(mRect);
        ACanvas.Brush.Style := bsSolid;
      end;
    TAtlasMarkupTool.Arrow:
      begin
        mFrom := Point(Round(AShape.StartPoint.X * AScale), Round(AShape.StartPoint.Y * AScale));
        mTo := Point(Round(AShape.EndPoint.X * AScale), Round(AShape.EndPoint.Y * AScale));
        ACanvas.Pen.Color := cMarkColor;
        ACanvas.Pen.Width := Max(1, Round(cLineWidth * AScale));
        ACanvas.Pen.Style := psSolid;
        ACanvas.MoveTo(mFrom.X, mFrom.Y);
        ACanvas.LineTo(mTo.X, mTo.Y);
        // Spitze am Ende: Dreieck in Richtung der Linie.
        mAngle := ArcTan2(mTo.Y - mFrom.Y, mTo.X - mFrom.X);
        mHead := cHeadLength * AScale;
        mHeadPoints[0] := mTo;
        mHeadPoints[1] := Point(Round(mTo.X - mHead * Cos(mAngle - Pi / 7)),
          Round(mTo.Y - mHead * Sin(mAngle - Pi / 7)));
        mHeadPoints[2] := Point(Round(mTo.X - mHead * Cos(mAngle + Pi / 7)),
          Round(mTo.Y - mHead * Sin(mAngle + Pi / 7)));
        ACanvas.Brush.Style := bsSolid;
        ACanvas.Brush.Color := cMarkColor;
        ACanvas.Polygon(mHeadPoints);
      end;
  end;
end;

class procedure TAtlasImageMarkup.Apply(ABitmap: TBitmap; const AShapes: TAtlasMarkupShapes);
var
  mShape: TAtlasMarkupShape;
begin
  for mShape in AShapes do
  begin
    Draw(ABitmap.Canvas, mShape, 1);
  end;
end;

{ TAtlasImageMarkupForm }

constructor TAtlasImageMarkupForm.CreateFor(AOwner: TComponent; ABitmap: TBitmap);
begin
  inherited CreateDialog(AOwner, '', 0);
  FBitmap := TBitmap.Create;
  FBitmap.Assign(ABitmap);
  FTool := TAtlasMarkupTool.Rectangle;
  Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachMarkupCaption);
  BorderStyle := bsSizeable;
  KeyPreview := True;
  Width := ScaleValue(1000);
  Height := ScaleValue(720);

  AddToolBar;
  AddBottomButtons;

  FBox := TPaintBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.AlignWithMargins := True;
  FBox.Margins.SetBounds(cGap, 0, cGap, 0);
  FBox.Cursor := crCross;
  FBox.OnPaint := BoxPaint;
  FBox.OnMouseDown := BoxMouseDown;
  FBox.OnMouseMove := BoxMouseMove;
  FBox.OnMouseUp := BoxMouseUp;
  UpdateButtons;
end;

/// <summary>Leiste oben: Werkzeuge und „Rückgängig“.</summary>
procedure TAtlasImageMarkupForm.AddToolBar;
const
  cToolText: array[TAtlasMarkupTool] of TAtlasAttachTextId = (TAtlasAttachTextId.AttachMarkupRectangle,
    TAtlasAttachTextId.AttachMarkupArrow, TAtlasAttachTextId.AttachMarkupBlacken);
var
  mTop: TPanel;
  mTool: TAtlasMarkupTool;
  mLeft: Integer;
begin
  mTop := TPanel.Create(Self);
  mTop.Parent := Self;
  mTop.Align := alTop;
  mTop.Height := mTop.ScaleValue(40);
  mTop.BevelOuter := bvNone;
  mLeft := cGap;
  for mTool := Low(TAtlasMarkupTool) to High(TAtlasMarkupTool) do
  begin
    FToolButtons[mTool] := TButton.Create(Self);
    FToolButtons[mTool].Parent := mTop;
    FToolButtons[mTool].SetBounds(mLeft, 6, 110, 28);
    FToolButtons[mTool].Caption := TAtlasAttachStrings.Text(cToolText[mTool]);
    FToolButtons[mTool].Tag := Ord(mTool);
    FToolButtons[mTool].OnClick := ToolClick;
    Inc(mLeft, 110 + cGap div 2);
  end;
  FUndo := TButton.Create(Self);
  FUndo.Parent := mTop;
  FUndo.SetBounds(mLeft + cGap, 6, 110, 28);
  FUndo.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachMarkupUndo);
  FUndo.OnClick := UndoClick;
end;

/// <summary>Leiste unten: „Übernehmen“ und „Abbrechen“.</summary>
procedure TAtlasImageMarkupForm.AddBottomButtons;
var
  mBottom: TPanel;
  mButton: TButton;
begin
  mBottom := TPanel.Create(Self);
  mBottom.Parent := Self;
  mBottom.Align := alBottom;
  mBottom.Height := mBottom.ScaleValue(44);
  mBottom.BevelOuter := bvNone;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(mBottom.Width - 2 * (110 + cGap), 8, 110, 28);
  mButton.Anchors := [akTop, akRight];
  mButton.Caption := TAtlasAttachStrings.Text(TAtlasAttachTextId.AttachMarkupApply);
  mButton.Default := True;
  mButton.ModalResult := mrOk;
  mButton := TButton.Create(Self);
  mButton.Parent := mBottom;
  mButton.SetBounds(mBottom.Width - (110 + cGap), 8, 110, 28);
  mButton.Anchors := [akTop, akRight];
  mButton.Caption := TAtlasStrings.Text(TAtlasTextId.ProjectSettingsCancel);
  mButton.Cancel := True;
  mButton.ModalResult := mrCancel;
end;

destructor TAtlasImageMarkupForm.Destroy;
begin
  FBitmap.Free;
  FShapes := nil;
  inherited;
end;

class function TAtlasImageMarkupForm.Execute(ABitmap: TBitmap): Boolean;
var
  mForm: TAtlasImageMarkupForm;
begin
  mForm := TAtlasImageMarkupForm.CreateFor(nil, ABitmap);
  try
    Result := (mForm.ShowModal = mrOk) and (Length(mForm.Shapes) > 0);
    if Result then
    begin
      mForm.ApplyTo(ABitmap);
    end;
  finally
    mForm.Free;
  end;
end;

function TAtlasImageMarkupForm.Scale: Double;
begin
  Result := 1;
  if (FBitmap.Width = 0) or (FBitmap.Height = 0) or (FBox.Width <= 0) or (FBox.Height <= 0) then
  begin
    Exit;
  end;
  // Nur verkleinern, nie vergrößern.
  Result := Min(1, Min(FBox.Width / FBitmap.Width, FBox.Height / FBitmap.Height));
end;

function TAtlasImageMarkupForm.ToImage(AX, AY: Integer): TPoint;
var
  mScale: Double;
begin
  mScale := Scale;
  Result := Point(EnsureRange(Round(AX / mScale), 0, FBitmap.Width), EnsureRange(Round(AY / mScale), 0,
    FBitmap.Height));
end;

procedure TAtlasImageMarkupForm.BoxPaint(Sender: TObject);
var
  mScale: Double;
  mShape: TAtlasMarkupShape;
  mTarget: TRect;
begin
  mScale := Scale;
  mTarget := Rect(0, 0, Round(FBitmap.Width * mScale), Round(FBitmap.Height * mScale));
  SetStretchBltMode(FBox.Canvas.Handle, HALFTONE);
  FBox.Canvas.StretchDraw(mTarget, FBitmap);
  for mShape in FShapes do
  begin
    TAtlasImageMarkup.Draw(FBox.Canvas, mShape, mScale);
  end;
  if FDragging then
  begin
    TAtlasImageMarkup.Draw(FBox.Canvas, FDrag, mScale);
  end;
end;

procedure TAtlasImageMarkupForm.BoxMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if Button <> mbLeft then
  begin
    Exit;
  end;
  FDragging := True;
  FDrag := TAtlasMarkupShape.Create(FTool, ToImage(X, Y), ToImage(X, Y));
end;

procedure TAtlasImageMarkupForm.BoxMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if not FDragging then
  begin
    Exit;
  end;
  FDrag.EndPoint := ToImage(X, Y);
  FBox.Invalidate;
end;

procedure TAtlasImageMarkupForm.BoxMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,
  Y: Integer);
begin
  if not FDragging then
  begin
    Exit;
  end;
  FDragging := False;
  FDrag.EndPoint := ToImage(X, Y);
  AddShape(FDrag);
end;

procedure TAtlasImageMarkupForm.AddShape(const AShape: TAtlasMarkupShape);
begin
  if not AShape.Tiny then
  begin
    FShapes := FShapes + [AShape];
  end;
  UpdateButtons;
  FBox.Invalidate;
end;

procedure TAtlasImageMarkupForm.Undo;
begin
  if Length(FShapes) > 0 then
  begin
    SetLength(FShapes, Length(FShapes) - 1);
  end;
  UpdateButtons;
  FBox.Invalidate;
end;

procedure TAtlasImageMarkupForm.ApplyTo(ABitmap: TBitmap);
begin
  TAtlasImageMarkup.Apply(ABitmap, FShapes);
end;

procedure TAtlasImageMarkupForm.ToolClick(Sender: TObject);
begin
  FTool := TAtlasMarkupTool((Sender as TButton).Tag);
  UpdateButtons;
end;

procedure TAtlasImageMarkupForm.UndoClick(Sender: TObject);
begin
  Undo;
end;

procedure TAtlasImageMarkupForm.UpdateButtons;
var
  mTool: TAtlasMarkupTool;
begin
  // Das gewählte Werkzeug fett.
  for mTool := Low(TAtlasMarkupTool) to High(TAtlasMarkupTool) do
  begin
    if mTool = FTool then
    begin
      FToolButtons[mTool].Font.Style := [fsBold];
    end
    else
    begin
      FToolButtons[mTool].Font.Style := [];
    end;
  end;
  FUndo.Enabled := Length(FShapes) > 0;
end;

procedure TAtlasImageMarkupForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // Strg+Z nimmt die letzte Form zurück.
  if (Key = Ord('Z')) and (ssCtrl in Shift) then
  begin
    Undo;
    Key := 0;
    Exit;
  end;
  inherited;
end;

end.
