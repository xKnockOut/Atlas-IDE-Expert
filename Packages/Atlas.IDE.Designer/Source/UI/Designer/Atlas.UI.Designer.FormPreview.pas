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
// - Basis ist TAtlasDialog: Dialogschrift und IDE-Thema an der Wurzel, bei
//   einem Wechsel des Themas neue Farben für das Abbild. Anfangs 900 × 640
//   logische Pixel, höchstens TAtlasDialog.MaxInitialSize; die Leiste ist eine
//   TAtlasButtonRow (Knöpfe so breit wie ihr Text, bricht in schmalen Fenstern
//   um).

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
  Atlas.Core.Designer.Layout,
  Atlas.UI.Foundation.Dialog;

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

  /// <summary>Steuerelemente des Vorschaufensters: Leiste, Größenfelder, Statuszeile, Rollbereich und
  /// Zeichenfläche.</summary>
  TAtlasFormPreviewParts = record
    Bar: TAtlasButtonRow;
    WidthEdit: TEdit;
    HeightEdit: TEdit;
    Status: TLabel;
    Box: TScrollBox;
    Paint: TPaintBox;
  end;

  /// <summary>Zeichnet die Teile des Abbilds auf Canvas: Knoten mit Beschriftung, Nadeln an verankerten Kanten
  /// und den Ziehgriff. Pin ist die Länge einer Nadel, Inset der Abstand der Beschriftung, beides in Pixeln des
  /// Fensters.</summary>
  TAtlasFormPreviewPainter = record
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Pin: Integer;
    Inset: TPoint;
    /// <summary>Knoten in ARect mit AText; ABad: mit Befund (rot), ATinted: ausgerichtet (getönt).</summary>
    procedure Node(const ARect: TRect; const AText: string; ABad, ATinted: Boolean);
    /// <summary>Nadeln an den Kanten von ARect, an denen AAnchors verankern.</summary>
    procedure Anchors(const ARect: TRect; AAnchors: TAtlasLayoutAnchors);
    /// <summary>Dreieck rechts unten in AGrip.</summary>
    procedure Grip(const AGrip: TRect);
  end;

  /// <summary>Ziehen am Griff läuft; Größenfelder werden gerade gesetzt.</summary>
  TAtlasFormPreviewDrag = record
    Dragging: Boolean;
    Updating: Boolean;
  end;

  TAtlasFormPreviewWindow = class(TAtlasDialog)
  public const
    cMinProbe = 40;
  private
    FDrag: TAtlasFormPreviewDrag;
    FOnClosed: TProc;
    function FormRect: TRect;
    function GripRect: TRect;
    function NodeAt(const APoint: TPoint): Integer;
    function HasFinding(AIndex: Integer): Boolean;
    function AddButton(const ACaption: string; ATag: Integer): TButton;
    procedure QuickClick(Sender: TObject);
    procedure SizeEdited(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormClosed(Sender: TObject; var Action: TCloseAction);
  protected
    FParts: TAtlasFormPreviewParts;
    FData: TAtlasFormPreviewData;
    FColors: TAtlasColors;
    /// <summary>Client des Abbilds in Pixeln der Knoten.</summary>
    FProbe: TSize;
    FBounds: TArray<TRect>;
    FFindings: TArray<TAtlasLayoutFinding>;
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
    procedure ThemeChanged; override;
  public
    constructor CreatePreview(AOwner: TComponent; const AData: TAtlasFormPreviewData; const AColors: TAtlasColors);
    /// <summary>Probegröße setzen (Client, Pixel der DFM); Constraints des Formulars gelten.</summary>
    procedure SetProbe(const ASize: TSize);
    /// <summary>Text eines Befunds für die Fußzeile und den Tooltip.</summary>
    class function FindingText(const AFinding: TAtlasLayoutFinding; const ANode: TAtlasLayoutNode): string; static;
    property Probe: TSize read FProbe;
    property Findings: TArray<TAtlasLayoutFinding> read FFindings;
    property OnClosed: TProc read FOnClosed write FOnClosed;
  end;

implementation

uses
  System.Math,
  Atlas.UI.Foundation.Theme,
  Atlas.UI.Designer.ViewStrings,
  Atlas.UI.Designer.Strings;

const
  cMargin = 16;
  cGrip = 12;
  cPin = 4;
  cTagMinimum = -1;
  cTagDesign = -2;
  cEditWidth = 56;
  cWindowWidth = 900;
  cWindowHeight = 640;
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

{ TAtlasFormPreviewPainter }

procedure TAtlasFormPreviewPainter.Node(const ARect: TRect; const AText: string; ABad, ATinted: Boolean);
var
  mRect: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(Colors.Surface);
  Canvas.Pen.Color := TColor(Colors.Line);
  Canvas.Font.Color := TColor(Colors.Muted);
  if ABad then
  begin
    Canvas.Brush.Color := TColor(Colors.ErrorSoft);
    Canvas.Pen.Color := TColor(Colors.Error);
    Canvas.Font.Color := TColor(Colors.Error);
  end
  else if ATinted then
  begin
    Canvas.Brush.Color := TColor(Colors.AccentSoft);
  end;
  Canvas.Rectangle(ARect);
  Canvas.Brush.Style := bsClear;
  mRect := ARect;
  InflateRect(mRect, -Inset.X, -Inset.Y);
  DrawText(Canvas.Handle, PChar(AText), -1, mRect, DT_LEFT or DT_TOP or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
end;

procedure TAtlasFormPreviewPainter.Anchors(const ARect: TRect; AAnchors: TAtlasLayoutAnchors);
var
  mMid: TPoint;
begin
  mMid := ARect.CenterPoint;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(Colors.Accent);
  Canvas.Pen.Color := TColor(Colors.Accent);
  if TAtlasLayoutAnchor.Left in AAnchors then
  begin
    Canvas.Rectangle(ARect.Left, mMid.Y - Pin, ARect.Left + Pin div 2 + 1, mMid.Y + Pin);
  end;
  if TAtlasLayoutAnchor.Right in AAnchors then
  begin
    Canvas.Rectangle(ARect.Right - Pin div 2 - 1, mMid.Y - Pin, ARect.Right, mMid.Y + Pin);
  end;
  if TAtlasLayoutAnchor.Top in AAnchors then
  begin
    Canvas.Rectangle(mMid.X - Pin, ARect.Top, mMid.X + Pin, ARect.Top + Pin div 2 + 1);
  end;
  if TAtlasLayoutAnchor.Bottom in AAnchors then
  begin
    Canvas.Rectangle(mMid.X - Pin, ARect.Bottom - Pin div 2 - 1, mMid.X + Pin, ARect.Bottom);
  end;
end;

procedure TAtlasFormPreviewPainter.Grip(const AGrip: TRect);
begin
  // Ziehgriff rechts unten: Dreieck in der Akzentfarbe.
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := TColor(Colors.Accent);
  Canvas.Pen.Color := TColor(Colors.Accent);
  Canvas.Polygon([Point(AGrip.Right, AGrip.Top), Point(AGrip.Right, AGrip.Bottom), Point(AGrip.Left, AGrip.Bottom)]);
end;

{ TAtlasFormPreviewWindow }

constructor TAtlasFormPreviewWindow.CreatePreview(AOwner: TComponent; const AData: TAtlasFormPreviewData;
  const AColors: TAtlasColors);
var
  mLimit: TSize;
begin
  inherited CreateDialog(AOwner, TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeTitle,
    [AData.FormName]), cWindowWidth);
  FData := AData;
  FColors := AColors;
  BorderStyle := bsSizeToolWin;
  KeyPreview := True;
  OnKeyDown := FormKey;
  OnClose := FormClosed;
  mLimit := MaxInitialSize;
  Width := Min(S(cWindowWidth), mLimit.cx);
  Height := Min(S(cWindowHeight), mLimit.cy);
  FParts.Bar := TAtlasButtonRow.Create(Self);
  FParts.Bar.Top := 0;
  FParts.Bar.Parent := Self;
  BuildBar;
  FParts.Status := TLabel.Create(Self);
  FParts.Status.Parent := Self;
  FParts.Status.Align := alBottom;
  FParts.Status.AlignWithMargins := True;
  FParts.Status.ShowAccelChar := False;
  FParts.Box := TScrollBox.Create(Self);
  FParts.Box.Parent := Self;
  FParts.Box.Align := alClient;
  FParts.Box.BorderStyle := bsNone;
  FParts.Paint := TPaintBox.Create(Self);
  FParts.Paint.Parent := FParts.Box;
  FParts.Paint.OnPaint := PaintPreview;
  FParts.Paint.OnMouseDown := PreviewMouseDown;
  FParts.Paint.OnMouseMove := PreviewMouseMove;
  FParts.Paint.OnMouseUp := PreviewMouseUp;
  FParts.Paint.ShowHint := True;
  SetProbe(AData.Design);
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

function TAtlasFormPreviewWindow.AddButton(const ACaption: string; ATag: Integer): TButton;
begin
  // Breite nach dem Text in der Dialogschrift, damit „1920 × 1080“ auch bei hoher DPI passt.
  Result := FParts.Bar.AddButton(ACaption);
  Result.Tag := ATag;
  Result.OnClick := QuickClick;
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
  if FDrag.Updating or not TryStrToInt(FParts.WidthEdit.Text, mWidth) or
    not TryStrToInt(FParts.HeightEdit.Text, mHeight) then
  begin
    Exit;
  end;
  if (mWidth >= cMinProbe) and (mHeight >= cMinProbe) then
  begin
    SetProbe(TSize.Create(mWidth, mHeight));
  end;
end;

procedure TAtlasFormPreviewWindow.PaintPreview(Sender: TObject);
var
  mPainter: TAtlasFormPreviewPainter;
  mIndex: Integer;
  mNode: TAtlasLayoutNode;
  mText: string;
begin
  mPainter.Canvas := FParts.Paint.Canvas;
  mPainter.Colors := FColors;
  mPainter.Pin := S(cPin);
  mPainter.Inset := Point(S(2), S(1));
  mPainter.Canvas.Font := Font;
  mPainter.Canvas.Brush.Style := bsSolid;
  mPainter.Canvas.Brush.Color := TColor(FColors.Gutter);
  mPainter.Canvas.FillRect(FParts.Paint.ClientRect);
  mPainter.Canvas.Brush.Color := TColor(FColors.Surface);
  mPainter.Canvas.Pen.Color := TColor(FColors.Accent);
  mPainter.Canvas.Rectangle(FormRect);
  for mIndex := 0 to High(FData.Nodes) do
  begin
    mNode := FData.Nodes[mIndex];
    if not mNode.Visible then
    begin
      Continue;
    end;
    mText := NodeText(mIndex);
    if FData.ShowAnchors and (mNode.Align <> TAtlasLayoutAlign.None) then
    begin
      mText := mText + ' (' + cAlignNames[mNode.Align] + ')';
    end;
    mPainter.Node(NodeRect(mIndex), mText, HasFinding(mIndex),
      FData.ShowAnchors and (mNode.Align <> TAtlasLayoutAlign.None));
    if FData.ShowAnchors and (mNode.Align = TAtlasLayoutAlign.None) then
    begin
      mPainter.Anchors(NodeRect(mIndex), mNode.Anchors);
    end;
  end;
  PaintOver;
  if GripResizes then
  begin
    mPainter.Grip(GripRect);
  end;
end;

procedure TAtlasFormPreviewWindow.PreviewMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FDrag.Dragging := GripResizes and (Button = mbLeft) and GripRect.Contains(Point(X, Y));
end;

procedure TAtlasFormPreviewWindow.PreviewMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
var
  mIndex: Integer;
  mText: string;
begin
  if FDrag.Dragging then
  begin
    SetProbe(TSize.Create(MulDiv(X - Origin.X, cBasePpi, CurrentPPI), MulDiv(Y - Origin.Y, cBasePpi, CurrentPPI)));
    Exit;
  end;
  if GripResizes and GripRect.Contains(Point(X, Y)) then
  begin
    FParts.Paint.Cursor := crSizeNWSE;
  end
  else
  begin
    FParts.Paint.Cursor := crDefault;
  end;
  mIndex := NodeAt(Point(X, Y));
  mText := '';
  if mIndex >= 0 then
  begin
    mText := Describe(mIndex);
  end;
  if mText <> FParts.Paint.Hint then
  begin
    FParts.Paint.Hint := mText;
    Application.CancelHint;
    if mText <> '' then
    begin
      FParts.Status.Caption := mText;
    end;
  end;
end;

procedure TAtlasFormPreviewWindow.PreviewMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
  X, Y: Integer);
begin
  FDrag.Dragging := False;
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

function TAtlasFormPreviewWindow.S(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, CurrentPPI, cBasePpi);
end;

function TAtlasFormPreviewWindow.Origin: TPoint;
begin
  Result := Point(S(cMargin), S(cMargin));
end;

function TAtlasFormPreviewWindow.NodeRect(AIndex: Integer): TRect;
var
  mRect: TRect;
begin
  mRect := TAtlasFormLayout.InForm(FData.Nodes, FBounds, AIndex);
  Result := Rect(Origin.X + Px(mRect.Left), Origin.Y + Px(mRect.Top), Origin.X + Px(mRect.Right),
    Origin.Y + Px(mRect.Bottom));
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

function TAtlasFormPreviewWindow.Describe(AIndex: Integer): string;
var
  mNode: TAtlasLayoutNode;
  mFinding: TAtlasLayoutFinding;
begin
  mNode := FData.Nodes[AIndex];
  Result := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPreviewDescribe, [mNode.Name, mNode.ClassName,
    FBounds[AIndex].Width, FBounds[AIndex].Height]);
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

procedure TAtlasFormPreviewWindow.BuildBar;
var
  mLabel: TLabel;
  mIndex: Integer;
  mButton: TButton;
begin
  mLabel := TLabel.Create(Self);
  mLabel.Parent := FParts.Bar;
  mLabel.Caption := TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeSize);
  mLabel.AlignWithMargins := True;
  FParts.WidthEdit := TEdit.Create(Self);
  FParts.WidthEdit.Parent := FParts.Bar;
  FParts.WidthEdit.Width := S(cEditWidth);
  FParts.WidthEdit.NumbersOnly := True;
  FParts.WidthEdit.AlignWithMargins := True;
  FParts.WidthEdit.OnChange := SizeEdited;
  FParts.HeightEdit := TEdit.Create(Self);
  FParts.HeightEdit.Parent := FParts.Bar;
  FParts.HeightEdit.Width := S(cEditWidth);
  FParts.HeightEdit.NumbersOnly := True;
  FParts.HeightEdit.AlignWithMargins := True;
  FParts.HeightEdit.OnChange := SizeEdited;
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

procedure TAtlasFormPreviewWindow.Recalculate;
begin
  FBounds := TAtlasFormLayout.Arrange(FData.Nodes, FData.Design, FProbe);
  FFindings := TAtlasFormLayout.Problems(FData.Nodes, FBounds, FProbe);
  FParts.Paint.SetBounds(0, 0, Px(FProbe.cx) + 2 * S(cMargin), Px(FProbe.cy) + 2 * S(cMargin));
  if Length(FFindings) = 0 then
  begin
    FParts.Status.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeNone,
      [FProbe.cx, FProbe.cy]) + ' · ' + TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.ResizeKeys);
  end
  else
  begin
    FParts.Status.Caption := TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.ResizeCount, [Length(FFindings),
      FProbe.cx, FProbe.cy]);
  end;
  FParts.Paint.Invalidate;
end;

procedure TAtlasFormPreviewWindow.PaintOver;
begin
  // Abbild der Probegröße: nichts weiter.
end;

procedure TAtlasFormPreviewWindow.SetProbe(const ASize: TSize);
begin
  FProbe := TAtlasFormLayout.Constrain(TSize.Create(Max(ASize.cx, cMinProbe), Max(ASize.cy, cMinProbe)),
    FData.MinClient.cx, FData.MinClient.cy, FData.MaxClient.cx, FData.MaxClient.cy);
  if FParts.WidthEdit = nil then
  begin
    Recalculate;
    Exit;
  end;
  FDrag.Updating := True;
  try
    if FParts.WidthEdit.Text <> IntToStr(FProbe.cx) then
    begin
      FParts.WidthEdit.Text := IntToStr(FProbe.cx);
    end;
    if FParts.HeightEdit.Text <> IntToStr(FProbe.cy) then
    begin
      FParts.HeightEdit.Text := IntToStr(FProbe.cy);
    end;
  finally
    FDrag.Updating := False;
  end;
  Recalculate;
end;

procedure TAtlasFormPreviewWindow.ThemeChanged;
begin
  FColors := TAtlasUiTheme.Colors;
  FParts.Paint.Invalidate;
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

end.
