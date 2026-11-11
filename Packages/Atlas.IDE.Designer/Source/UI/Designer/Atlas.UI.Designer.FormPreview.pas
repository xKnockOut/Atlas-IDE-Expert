unit Atlas.UI.Designer.FormPreview;

// Fenster „Größe ausprobieren“ (#606), reine VCL. Zeigt das Formular als
// Abbild bei einer Probegröße; die echten Komponenten im Designer bleiben,
// wo sie sind, die DFM unverändert.
//   Größe: [ 600] × [ 400]  [Minimum] [Design] [1366 × 768] [1920 × 1080]
//   ┌──────────────── Abbild ────────────────┐
//   │ Rechtecke mit Namen, Align getönt,     │
//   │ Nadeln an verankerten Kanten, rot =    │
//   │ Befund                              ◢  │  ← Ziehgriff
//   └────────────────────────────────────────┘
//   3 Befunde bei 600 × 400 …
// - Die Lagen rechnet TAtlasFormLayout aus den Knoten (Pixel der DFM); das
//   Abbild ist 1:1 in Pixeln der DFM, auf die DPI des Fensters skaliert.
// - Maus über einer Komponente: Name, Klasse, Align, Anchors und die Befunde
//   als Tooltip und in der Fußzeile.
// - Esc schließt; OnClosed meldet es dem Aufrufer.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Atlas.Core.Style.Palette,
  Atlas.Core.Designer.Layout;

type
  TAtlasFormPreviewData = record
    FormName: string;
    Nodes: TArray<TAtlasLayoutNode>;
    /// <summary>Client des Formulars in der Designgröße.</summary>
    Design: TSize;
    /// <summary>Kleinster bzw. größter Client nach den Constraints des Formulars; 0 = ohne Grenze.</summary>
    MinClient: TSize;
    MaxClient: TSize;
    /// <summary>Schnellwerte aus designer.resizePreviewSizes.</summary>
    Quick: TArray<TSize>;
    ShowAnchors: Boolean;
  end;

  TAtlasFormPreviewWindow = class(TForm)
  public const
    cMinProbe = 40;
  private
    FWidthEdit: TEdit;
    FHeightEdit: TEdit;
    FBox: TScrollBox;
    FDragging: Boolean;
    FUpdating: Boolean;
    FOnClosed: TProc;
    function FormRect: TRect;
    function GripRect: TRect;
    function NodeAt(const APoint: TPoint): Integer;
    function HasFinding(AIndex: Integer): Boolean;
    function AddButton(const ACaption: string; ATag: Integer): TButton;
    procedure QuickClick(Sender: TObject);
    procedure SizeEdited(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PaintNode(AIndex: Integer);
    procedure PaintAnchors(AIndex: Integer; const ARect: TRect);
    procedure PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClosed(Sender: TObject; var Action: TCloseAction);
  protected
    FData: TAtlasFormPreviewData;
    FColors: TAtlasColors;
    /// <summary>Client des Abbilds in Pixeln der Knoten.</summary>
    FProbe: TSize;
    FBounds: TArray<TRect>;
    FFindings: TArray<TAtlasLayoutFinding>;
    FBar: TFlowPanel;
    FStatus: TLabel;
    FPaint: TPaintBox;
    /// <summary>AValue bei 96 dpi in Pixeln des Fensters (Leiste, Ränder).</summary>
    function S(AValue: Integer): Integer;
    function Origin: TPoint;
    function NodeRect(AIndex: Integer): TRect;
    /// <summary>Pixel der Knoten in Pixeln des Fensters; hier Pixel der DFM, auf die DPI des Fensters skaliert.
    /// </summary>
    function Px(AValue: Integer): Integer; virtual;
    /// <summary>Beschriftung eines Knotens im Abbild; hier der Name.</summary>
    function NodeText(AIndex: Integer): string; virtual;
    /// <summary>Ziehgriff und Größenfelder aktiv?</summary>
    function GripResizes: Boolean; virtual;
    function Describe(AIndex: Integer): string; virtual;
    procedure BuildBar; virtual;
    procedure Recalculate; virtual;
    /// <summary>Nach den Knoten zeichnen (Grenzen, Markierungen).</summary>
    procedure PaintOver; virtual;
  public
    constructor CreatePreview(AOwner: TComponent; const AData: TAtlasFormPreviewData; const AColors: TAtlasColors);
    /// <summary>Probegröße setzen (Client, Pixel der DFM); Constraints des Formulars gelten.</summary>
    procedure SetProbe(const ASize: TSize);
    procedure ApplyColors(const AColors: TAtlasColors);
    /// <summary>Text eines Befunds für die Fußzeile und den Tooltip.</summary>
    class function FindingText(const AFinding: TAtlasLayoutFinding; const ANode: TAtlasLayoutNode): string; static;
    property Probe: TSize read FProbe;
    property Findings: TArray<TAtlasLayoutFinding> read FFindings;
    property OnClosed: TProc read FOnClosed write FOnClosed;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Designer.ViewStrings;

const
  cMargin = 16;
  cGrip = 12;
  cPin = 4;
  cTagMinimum = -1;
  cTagDesign = -2;
  cEditWidth = 56;
  cBasePpi = 96;
  cAlignNames: array[TAtlasLayoutAlign] of string = ('', 'alTop', 'alBottom', 'alLeft', 'alRight', 'alClient',
    'alCustom');
  cAnchorNames: array[TAtlasLayoutAnchor] of string = ('akLeft', 'akTop', 'akRight', 'akBottom');

function AnchorText(AAnchors: TAtlasLayoutAnchors): string;
var
  mAnchor: TAtlasLayoutAnchor;
begin
  Result := '';
  for mAnchor := Low(TAtlasLayoutAnchor) to High(TAtlasLayoutAnchor) do
  begin
    if mAnchor in AAnchors then
    begin
      if Result <> '' then
      begin
        Result := Result + ', ';
      end;
      Result := Result + cAnchorNames[mAnchor];
    end;
  end;
end;

{ TAtlasFormPreviewWindow }

constructor TAtlasFormPreviewWindow.CreatePreview(AOwner: TComponent; const AData: TAtlasFormPreviewData;
  const AColors: TAtlasColors);
begin
  inherited CreateNew(AOwner);
  FData := AData;
  FColors := AColors;
  Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeTitle, [AData.FormName]);
  BorderStyle := bsSizeToolWin;
  Position := poMainFormCenter;
  KeyPreview := True;
  OnKeyDown := FormKey;
  OnClose := FormClosed;
  Width := S(900);
  Height := S(640);
  FBar := TFlowPanel.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alTop;
  FBar.AutoSize := True;
  FBar.BevelOuter := bvNone;
  BuildBar;
  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Align := alBottom;
  FStatus.AlignWithMargins := True;
  FStatus.ShowAccelChar := False;
  FBox := TScrollBox.Create(Self);
  FBox.Parent := Self;
  FBox.Align := alClient;
  FBox.BorderStyle := bsNone;
  FPaint := TPaintBox.Create(Self);
  FPaint.Parent := FBox;
  FPaint.OnPaint := PaintPreview;
  FPaint.OnMouseDown := PreviewMouseDown;
  FPaint.OnMouseMove := PreviewMouseMove;
  FPaint.OnMouseUp := PreviewMouseUp;
  FPaint.ShowHint := True;
  SetProbe(AData.Design);
end;

function TAtlasFormPreviewWindow.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, cBasePpi);
end;

function TAtlasFormPreviewWindow.Px(AValue: Integer): Integer;
begin
  Result := S(AValue);
end;

function TAtlasFormPreviewWindow.NodeText(AIndex: Integer): string;
begin
  Result := FData.Nodes[AIndex].Name;
end;

function TAtlasFormPreviewWindow.GripResizes: Boolean;
begin
  Result := True;
end;

procedure TAtlasFormPreviewWindow.PaintOver;
begin
  // Abbild der Probegröße: nichts weiter.
end;

function TAtlasFormPreviewWindow.AddButton(const ACaption: string; ATag: Integer): TButton;
begin
  Result := TButton.Create(Self);
  Result.Parent := FBar;
  Result.Caption := ACaption;
  Result.Tag := ATag;
  Result.OnClick := QuickClick;
  Result.AlignWithMargins := True;
end;

procedure TAtlasFormPreviewWindow.BuildBar;
var
  mLabel: TLabel;
  mIndex: Integer;
  mButton: TButton;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := FBar;
  mLabel.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeSize);
  mLabel.AlignWithMargins := True;
  FWidthEdit := TEdit.Create(Self);
  FWidthEdit.Parent := FBar;
  FWidthEdit.Width := S(cEditWidth);
  FWidthEdit.NumbersOnly := True;
  FWidthEdit.AlignWithMargins := True;
  FWidthEdit.OnChange := SizeEdited;
  FHeightEdit := TEdit.Create(Self);
  FHeightEdit.Parent := FBar;
  FHeightEdit.Width := S(cEditWidth);
  FHeightEdit.NumbersOnly := True;
  FHeightEdit.AlignWithMargins := True;
  FHeightEdit.OnChange := SizeEdited;
  mButton := AddButton(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeMinimum), cTagMinimum);
  mButton.Enabled := (FData.MinClient.cx > 0) or (FData.MinClient.cy > 0);
  if not mButton.Enabled then
  begin
    mButton.Hint := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeNoMinimum);
    mButton.ShowHint := True;
  end;
  AddButton(TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeDesign), cTagDesign);
  for mIndex := 0 to High(FData.Quick) do
  begin
    AddButton(Format('%d × %d', [FData.Quick[mIndex].cx, FData.Quick[mIndex].cy]), mIndex);
  end;
end;

procedure TAtlasFormPreviewWindow.QuickClick(Sender: TObject);
var
  mTag: Integer;
begin
  mTag := Integer(TComponent(Sender).Tag);
  case mTag of
    cTagMinimum:
      SetProbe(TSize.Create(Max(FData.MinClient.cx, cMinProbe), Max(FData.MinClient.cy, cMinProbe)));
    cTagDesign:
      SetProbe(FData.Design);
  else
    if (mTag >= 0) and (mTag <= High(FData.Quick)) then
    begin
      SetProbe(FData.Quick[mTag]);
    end;
  end;
end;

procedure TAtlasFormPreviewWindow.SizeEdited(Sender: TObject);
var
  mWidth, mHeight: Integer;
begin
  if FUpdating or not TryStrToInt(FWidthEdit.Text, mWidth) or not TryStrToInt(FHeightEdit.Text, mHeight) then
  begin
    Exit;
  end;
  if (mWidth >= cMinProbe) and (mHeight >= cMinProbe) then
  begin
    SetProbe(TSize.Create(mWidth, mHeight));
  end;
end;

procedure TAtlasFormPreviewWindow.SetProbe(const ASize: TSize);
begin
  FProbe := TAtlasFormLayout.Constrain(TSize.Create(Max(ASize.cx, cMinProbe), Max(ASize.cy, cMinProbe)),
    FData.MinClient.cx, FData.MinClient.cy, FData.MaxClient.cx, FData.MaxClient.cy);
  if FWidthEdit = nil then
  begin
    Recalculate;
    Exit;
  end;
  FUpdating := True;
  try
    if FWidthEdit.Text <> IntToStr(FProbe.cx) then
    begin
      FWidthEdit.Text := IntToStr(FProbe.cx);
    end;
    if FHeightEdit.Text <> IntToStr(FProbe.cy) then
    begin
      FHeightEdit.Text := IntToStr(FProbe.cy);
    end;
  finally
    FUpdating := False;
  end;
  Recalculate;
end;

procedure TAtlasFormPreviewWindow.Recalculate;
begin
  FBounds := TAtlasFormLayout.Arrange(FData.Nodes, FData.Design, FProbe);
  FFindings := TAtlasFormLayout.Problems(FData.Nodes, FBounds, FProbe);
  FPaint.SetBounds(0, 0, Px(FProbe.cx) + 2 * S(cMargin), Px(FProbe.cy) + 2 * S(cMargin));
  if Length(FFindings) = 0 then
  begin
    FStatus.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeNone, [FProbe.cx, FProbe.cy]) +
      ' · ' + TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeKeys);
  end
  else
  begin
    FStatus.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeCount, [Length(FFindings),
      FProbe.cx, FProbe.cy]);
  end;
  FPaint.Invalidate;
end;

function TAtlasFormPreviewWindow.Origin: TPoint;
begin
  Result := Point(S(cMargin), S(cMargin));
end;

function TAtlasFormPreviewWindow.FormRect: TRect;
begin
  Result := Bounds(Origin.X, Origin.Y, Px(FProbe.cx), Px(FProbe.cy));
end;

function TAtlasFormPreviewWindow.GripRect: TRect;
begin
  Result := Rect(FormRect.Right - S(cGrip), FormRect.Bottom - S(cGrip), FormRect.Right + S(cGrip) div 2,
    FormRect.Bottom + S(cGrip) div 2);
end;

function TAtlasFormPreviewWindow.NodeRect(AIndex: Integer): TRect;
var
  mRect: TRect;
begin
  mRect := TAtlasFormLayout.InForm(FData.Nodes, FBounds, AIndex);
  Result := Rect(Origin.X + Px(mRect.Left), Origin.Y + Px(mRect.Top), Origin.X + Px(mRect.Right),
    Origin.Y + Px(mRect.Bottom));
end;

function TAtlasFormPreviewWindow.NodeAt(const APoint: TPoint): Integer;
var
  mIndex: Integer;
begin
  // Kinder stehen hinter ihren Eltern: von hinten das innerste zuerst.
  for mIndex := High(FData.Nodes) downto 0 do
  begin
    if FData.Nodes[mIndex].Visible and NodeRect(mIndex).Contains(APoint) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasFormPreviewWindow.HasFinding(AIndex: Integer): Boolean;
var
  mFinding: TAtlasLayoutFinding;
begin
  for mFinding in FFindings do
  begin
    if mFinding.Node = AIndex then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasFormPreviewWindow.FindingText(const AFinding: TAtlasLayoutFinding;
  const ANode: TAtlasLayoutNode): string;
begin
  case AFinding.Problem of
    TAtlasLayoutProblem.TooSmall:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutTooSmall, [AFinding.Amount]);
    TAtlasLayoutProblem.OutRight:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutOutRight, [AFinding.Amount]);
    TAtlasLayoutProblem.OutBottom:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutOutBottom, [AFinding.Amount]);
    TAtlasLayoutProblem.OutLeft:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutOutLeft, [AFinding.Amount]);
    TAtlasLayoutProblem.OutTop:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutOutTop, [AFinding.Amount]);
    TAtlasLayoutProblem.Overlap:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutOverlap, [AFinding.Other]);
    TAtlasLayoutProblem.TwoClient:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutTwoClient, [AFinding.Other]);
    TAtlasLayoutProblem.Clipped:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleClipped, [AFinding.Amount]);
    TAtlasLayoutProblem.ScreenWidth:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleScreenWidth, [AFinding.Amount]);
    TAtlasLayoutProblem.ScreenHeight:
      Result := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ScaleScreenHeight, [AFinding.Amount]);
  else
    Result := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.LayoutAnchorsAlign);
  end;
  // Wer herausragt, ohne mitzuwachsen: Anchors nennen.
  if (AFinding.Problem in [TAtlasLayoutProblem.OutRight, TAtlasLayoutProblem.OutBottom]) and
    (ANode.Align = TAtlasLayoutAlign.None) then
  begin
    Result := Result + ', ' + TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.LayoutAnchored,
      [AnchorText(ANode.Anchors)]);
  end;
end;

function TAtlasFormPreviewWindow.Describe(AIndex: Integer): string;
var
  mNode: TAtlasLayoutNode;
  mFinding: TAtlasLayoutFinding;
begin
  mNode := FData.Nodes[AIndex];
  Result := Format('%s: %s · %d × %d', [mNode.Name, mNode.ClassName, FBounds[AIndex].Width,
    FBounds[AIndex].Height]);
  if mNode.Align <> TAtlasLayoutAlign.None then
  begin
    Result := Result + ' · ' + cAlignNames[mNode.Align];
  end
  else
  begin
    Result := Result + ' · [' + AnchorText(mNode.Anchors) + ']';
  end;
  for mFinding in FFindings do
  begin
    if mFinding.Node = AIndex then
    begin
      Result := Result + ' · ' + FindingText(mFinding, mNode);
    end;
  end;
end;

procedure TAtlasFormPreviewWindow.PaintAnchors(AIndex: Integer; const ARect: TRect);
var
  mAnchors: TAtlasLayoutAnchors;
  mMid: TPoint;
  mPin: Integer;
begin
  mAnchors := FData.Nodes[AIndex].Anchors;
  mMid := ARect.CenterPoint;
  mPin := S(cPin);
  FPaint.Canvas.Brush.Style := bsSolid;
  FPaint.Canvas.Brush.Color := TColor(FColors.Accent);
  FPaint.Canvas.Pen.Color := TColor(FColors.Accent);
  if TAtlasLayoutAnchor.Left in mAnchors then
  begin
    FPaint.Canvas.Rectangle(ARect.Left, mMid.Y - mPin, ARect.Left + mPin div 2 + 1, mMid.Y + mPin);
  end;
  if TAtlasLayoutAnchor.Right in mAnchors then
  begin
    FPaint.Canvas.Rectangle(ARect.Right - mPin div 2 - 1, mMid.Y - mPin, ARect.Right, mMid.Y + mPin);
  end;
  if TAtlasLayoutAnchor.Top in mAnchors then
  begin
    FPaint.Canvas.Rectangle(mMid.X - mPin, ARect.Top, mMid.X + mPin, ARect.Top + mPin div 2 + 1);
  end;
  if TAtlasLayoutAnchor.Bottom in mAnchors then
  begin
    FPaint.Canvas.Rectangle(mMid.X - mPin, ARect.Bottom - mPin div 2 - 1, mMid.X + mPin, ARect.Bottom);
  end;
end;

procedure TAtlasFormPreviewWindow.PaintNode(AIndex: Integer);
var
  mRect: TRect;
  mNode: TAtlasLayoutNode;
  mBad: Boolean;
  mText: string;
begin
  mNode := FData.Nodes[AIndex];
  mRect := NodeRect(AIndex);
  mBad := HasFinding(AIndex);
  FPaint.Canvas.Brush.Style := bsSolid;
  FPaint.Canvas.Brush.Color := TColor(FColors.Surface);
  if mBad then
  begin
    FPaint.Canvas.Brush.Color := TColor(FColors.ErrorSoft);
  end
  else if FData.ShowAnchors and (mNode.Align <> TAtlasLayoutAlign.None) then
  begin
    FPaint.Canvas.Brush.Color := TColor(FColors.AccentSoft);
  end;
  FPaint.Canvas.Pen.Color := TColor(FColors.Line);
  if mBad then
  begin
    FPaint.Canvas.Pen.Color := TColor(FColors.Error);
  end;
  FPaint.Canvas.Rectangle(mRect);
  mText := NodeText(AIndex);
  if FData.ShowAnchors and (mNode.Align <> TAtlasLayoutAlign.None) then
  begin
    mText := mText + ' (' + cAlignNames[mNode.Align] + ')';
  end;
  FPaint.Canvas.Brush.Style := bsClear;
  FPaint.Canvas.Font.Color := TColor(FColors.Muted);
  if mBad then
  begin
    FPaint.Canvas.Font.Color := TColor(FColors.Error);
  end;
  InflateRect(mRect, -S(2), -S(1));
  DrawText(FPaint.Canvas.Handle, PChar(mText), -1, mRect, DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  if FData.ShowAnchors and (mNode.Align = TAtlasLayoutAlign.None) then
  begin
    PaintAnchors(AIndex, NodeRect(AIndex));
  end;
end;

procedure TAtlasFormPreviewWindow.PaintPreview(Sender: TObject);
var
  mIndex: Integer;
  mGrip: TRect;
begin
  FPaint.Canvas.Font := Font;
  FPaint.Canvas.Brush.Style := bsSolid;
  FPaint.Canvas.Brush.Color := TColor(FColors.Gutter);
  FPaint.Canvas.FillRect(FPaint.ClientRect);
  FPaint.Canvas.Brush.Color := TColor(FColors.Surface);
  FPaint.Canvas.Pen.Color := TColor(FColors.Accent);
  FPaint.Canvas.Rectangle(FormRect);
  for mIndex := 0 to High(FData.Nodes) do
  begin
    if FData.Nodes[mIndex].Visible then
    begin
      PaintNode(mIndex);
    end;
  end;
  PaintOver;
  if not GripResizes then
  begin
    Exit;
  end;
  // Ziehgriff rechts unten: Dreieck in der Akzentfarbe.
  mGrip := GripRect;
  FPaint.Canvas.Brush.Style := bsSolid;
  FPaint.Canvas.Brush.Color := TColor(FColors.Accent);
  FPaint.Canvas.Pen.Color := TColor(FColors.Accent);
  FPaint.Canvas.Polygon([Point(mGrip.Right, mGrip.Top), Point(mGrip.Right, mGrip.Bottom),
    Point(mGrip.Left, mGrip.Bottom)]);
end;

procedure TAtlasFormPreviewWindow.PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FDragging := GripResizes and (Button = mbLeft) and GripRect.Contains(Point(X, Y));
end;

procedure TAtlasFormPreviewWindow.PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mText: string;
begin
  if FDragging then
  begin
    SetProbe(TSize.Create(MulDiv(X - Origin.X, cBasePpi, CurrentPPI), MulDiv(Y - Origin.Y, cBasePpi, CurrentPPI)));
    Exit;
  end;
  if GripResizes and GripRect.Contains(Point(X, Y)) then
  begin
    FPaint.Cursor := crSizeNWSE;
  end
  else
  begin
    FPaint.Cursor := crDefault;
  end;
  mIndex := NodeAt(Point(X, Y));
  mText := '';
  if mIndex >= 0 then
  begin
    mText := Describe(mIndex);
  end;
  if mText <> FPaint.Hint then
  begin
    FPaint.Hint := mText;
    Application.CancelHint;
    if mText <> '' then
    begin
      FStatus.Caption := mText;
    end;
  end;
end;

procedure TAtlasFormPreviewWindow.PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FDragging := False;
end;

procedure TAtlasFormPreviewWindow.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    Key := 0;
    Close;
  end;
end;

procedure TAtlasFormPreviewWindow.FormClosed(Sender: TObject; var Action: TCloseAction);
begin
  Action := caHide;
  if Assigned(FOnClosed) then
  begin
    FOnClosed();
  end;
end;

procedure TAtlasFormPreviewWindow.ApplyColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  FPaint.Invalidate;
end;

end.
