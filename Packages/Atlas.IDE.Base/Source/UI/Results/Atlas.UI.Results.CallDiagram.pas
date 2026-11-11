unit Atlas.UI.Results.CallDiagram;

// Diagrammansicht der Aufrufhierarchie (#1122), reine VCL: zeichnet das
// Layout von TAtlasCallDiagram mit TAtlasCallView in den Farben des
// IDE-Themas (TAtlasColors). Kästen mit Methodenname und Fundstelle; Kanten
// als Bogen von Spalte zu Spalte, über ein Interface oder eine virtuelle
// Methode gestrichelt mit der Zahl der Umsetzungen; Rekursion als Bogen
// zurück zum Vorfahren in Warnfarbe; „+ N …“ fasst weitere Kinder zusammen.
// Bedienung wie die HTML-Datei: Klick auf einen Kasten lädt die nächste
// Ebene über OnLoad (die vorhandenen Anfragen der Aufrufhierarchie) bzw.
// klappt zu und auf, Klick auf „+ N …“ zeigt alle, Doppelklick oder Enter
// springt über OnOpen in den Code, Leertaste klappt auf und zu, Ziehen
// verschiebt, Mausrad zoomt um den Mauszeiger, + und − zoomen, 0 passt ein.
// Text wird erst mit Fenster gemessen (Paint), nie im Konstruktor.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Results.CallDiagram;

type
  /// <summary>Nächste Ebene: Aufrufer bzw. Aufgerufene von AItem in Richtung ADirection.</summary>
  TAtlasCallLoad = reference to function(ADirection: TAtlasHierarchyDirection;
    const AItem: TAtlasHierarchyItem): TArray<TAtlasHierarchyItem>;
  TAtlasCallOpen = reference to procedure(const AItem: TAtlasHierarchyItem);

  TAtlasCallDiagramView = class(TCustomControl)
  private type
    /// <summary>Ziehen mit der Maus: läuft, schon bewegt, letzte Lage.</summary>
    TDrag = record
      Active: Boolean;
      Moved: Boolean;
      X: Integer;
      Y: Integer;
    end;

    THandlers = record
      OnLoad: TAtlasCallLoad;
      OnOpen: TAtlasCallOpen;
    end;
  private
    FDiagram: TAtlasCallDiagram;
    FLayout: TAtlasCallLayout;
    FView: TAtlasCallView;
    FFitted: Boolean;
    /// <summary>Gewählter Knoten; -1 ohne.</summary>
    FSelected: Integer;
    FHintBox: Integer;
    FDrag: TDrag;
    FHandlers: THandlers;
    function BoxRect(ABox: Integer): TRect;
    function GetProjectOnly: Boolean;
    procedure SetIsProjectFile(const AValue: TFunc<string, Boolean>);
    procedure SetProjectOnly(AValue: Boolean);
    procedure Relayout;
    function BoxHint(ABox: Integer): string;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure DblClick; override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Neu beginnen mit den Wurzeln; die erste Ebene wird gleich geladen.</summary>
    procedure ShowRoots(ADirection: TAtlasHierarchyDirection; const ARoots: TArray<TAtlasHierarchyItem>);
    /// <summary>Knoten auf- bzw. zuklappen; lädt seine Kinder beim ersten Mal über OnLoad.</summary>
    procedure ToggleNode(ANode: Integer);
    /// <summary>Wie ein Klick auf einen Kasten des Layouts (Aufruf oder „+ N …“).</summary>
    procedure ClickBox(ABox: Integer);
    procedure FitView;
    /// <summary>Gewählte Stelle über OnOpen öffnen (Doppelklick, Enter).</summary>
    procedure OpenSelected;
    procedure ZoomBy(AFactor: Double);
    /// <summary>Eigenständige HTML-Datei mit den geladenen Ebenen (TAtlasCallDiagram.Html).</summary>
    function Html(const ATitle: string): string;
    property Diagram: TAtlasCallDiagram read FDiagram;
    property Layout: TAtlasCallLayout read FLayout;
    property View: TAtlasCallView read FView;
    property Selected: Integer read FSelected;
    property ProjectOnly: Boolean read GetProjectOnly write SetProjectOnly;
    /// <summary>Gehört die Datei zu einem Projekt der Gruppe? Vor ShowRoots setzen; nil: alle.</summary>
    // lsp-ignore: write-only-property -- reicht nur an das Diagramm weiter
    property IsProjectFile: TFunc<string, Boolean> write SetIsProjectFile;
    property OnLoad: TAtlasCallLoad read FHandlers.OnLoad write FHandlers.OnLoad;
    property OnOpen: TAtlasCallOpen read FHandlers.OnOpen write FHandlers.OnOpen;
  end;

implementation

uses
  System.UITypes,
  Winapi.Windows,
  System.Math,
  Vcl.Forms,
  Vcl.Themes,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.UI.Results.Strings;

const
  /// <summary>Bildpunkte, ab denen ein Mausdruck als Ziehen gilt.</summary>
  cDragThreshold = 3;
  /// <summary>Unter dieser Vergrößerung keine Schrift mehr (unlesbar).</summary>
  cMinTextScale = 0.35;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

/// <summary>Bildschirmlage auf ganze Bildpunkte.</summary>
function Px(AValue: Double): Integer;
begin
  Result := Round(AValue);
end;

type
  TEdgePoints = array[0..3] of TPoint;

  /// <summary>Zeichnet das Layout: Kanten mit Pfeilspitze und Zahl der Umsetzungen, Kästen mit Name und
  /// Fundstelle, „+ N …“.</summary>
  TCallPainter = record
    View: TAtlasCallDiagramView;
    Canvas: TCanvas;
    Colors: TAtlasColors;
    Scale: Double;
    /// <summary>Innenabstand der Kästen.</summary>
    Pad: Integer;
    class function Create(AView: TAtlasCallDiagramView): TCallPainter; static;
    /// <summary>Stützpunkte der Kante: Bogen von Spalte zu Spalte bzw. über beide Kästen zurück.</summary>
    function EdgePoints(const AEdge: TAtlasCallEdge): TEdgePoints;
    procedure DrawArrow(const ATip: TPoint; ABack: Boolean);
    /// <summary>„N Umsetzungen“ an gestrichelten Kanten über ein Interface oder eine virtuelle Methode.</summary>
    procedure DrawEdgeCaption(const AEdge: TAtlasCallEdge; const ATip: TPoint);
    procedure DrawEdge(const AEdge: TAtlasCallEdge);
    procedure BoxText(const ARect: TRect; const AText: string);
    procedure DrawMore(const ABox: TAtlasCallBox; const ARect: TRect);
    procedure DrawNodeTexts(const ABox: TAtlasCallBox; const ARect: TRect);
    procedure DrawNode(const ABox: TAtlasCallBox; const ARect: TRect);
    procedure Paint;
  end;

{ TCallPainter }

class function TCallPainter.Create(AView: TAtlasCallDiagramView): TCallPainter;
begin
  Result.View := AView;
  Result.Canvas := AView.Canvas;
  Result.Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(AView).GetSystemColor(
    clWindow))));
  Result.Scale := AView.FView.Scale;
  Result.Pad := Max(AView.ScaleValue(2), Px(8 * Result.Scale));
end;

function TCallPainter.EdgePoints(const AEdge: TAtlasCallEdge): TEdgePoints;
var
  mSource, mTarget: TRect;
  mTop, mMid: Integer;
begin
  mSource := View.BoxRect(AEdge.Source);
  mTarget := View.BoxRect(AEdge.Target);
  if AEdge.Back then
  begin
    // Bogen über beide Kästen zurück zum Vorfahren, wie in der HTML-Datei.
    mTop := Min(mSource.Top, mTarget.Top) - Px(14 * Scale);
    Result[0] := Point((mSource.Left + mSource.Right) div 2, mSource.Top);
    Result[1] := Point(Result[0].X, mTop);
    Result[3] := Point((mTarget.Left + mTarget.Right) div 2, mTarget.Top);
    Result[2] := Point(Result[3].X, mTop);
  end
  else
  begin
    Result[0] := Point(mSource.Right, (mSource.Top + mSource.Bottom) div 2);
    Result[3] := Point(mTarget.Left, (mTarget.Top + mTarget.Bottom) div 2);
    mMid := (Result[0].X + Result[3].X) div 2;
    Result[1] := Point(mMid, Result[0].Y);
    Result[2] := Point(mMid, Result[3].Y);
  end;
end;

procedure TCallPainter.DrawArrow(const ATip: TPoint; ABack: Boolean);
var
  mSize: Integer;
begin
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Canvas.Pen.Color;
  mSize := Max(3, Px(6 * Scale));
  if ABack then
  begin
    Canvas.Polygon([ATip, Point(ATip.X - mSize div 2, ATip.Y - mSize), Point(ATip.X + mSize div 2, ATip.Y - mSize)]);
  end
  else
  begin
    Canvas.Polygon([ATip, Point(ATip.X - mSize, ATip.Y - mSize div 2), Point(ATip.X - mSize, ATip.Y + mSize div 2)]);
  end;
end;

procedure TCallPainter.DrawEdgeCaption(const AEdge: TAtlasCallEdge; const ATip: TPoint);
var
  mCaption: string;
begin
  if not AEdge.Dashed or AEdge.Back or (AEdge.Implementations <= 0) or (Scale < cMinTextScale) then
  begin
    Exit;
  end;
  if AEdge.Implementations = 1 then
  begin
    mCaption := TAtlasResultsStrings.Text(TAtlasResultsTextId.CallDiagramImplementation);
  end
  else
  begin
    mCaption := TAtlasResultsStrings.Fmt(TAtlasResultsTextId.CallDiagramImplementations, [AEdge.Implementations]);
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(ATip.X - Canvas.TextWidth(mCaption) - Px(8 * Scale), ATip.Y - Canvas.TextHeight(mCaption) - 1,
    mCaption);
end;

procedure TCallPainter.DrawEdge(const AEdge: TAtlasCallEdge);
var
  mPoints: TEdgePoints;
begin
  mPoints := EdgePoints(AEdge);
  // Rekursion in Warnfarbe wie die HTML-Datei.
  Canvas.Pen.Color := ToColor(Colors.Line);
  if AEdge.Back then
  begin
    Canvas.Pen.Color := ToColor(Colors.Warn);
  end;
  // Gestrichelte Stifte zeichnet GDI nur mit Breite 1.
  if AEdge.Dashed then
  begin
    Canvas.Pen.Style := psDash;
    Canvas.Pen.Width := 1;
  end
  else
  begin
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := Max(1, Px(1.5 * Scale));
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.PolyBezier(mPoints);
  // Pfeilspitze am Ziel.
  DrawArrow(mPoints[3], AEdge.Back);
  DrawEdgeCaption(AEdge, mPoints[3]);
end;

procedure TCallPainter.BoxText(const ARect: TRect; const AText: string);
var
  mRect: TRect;
  mText: string;
begin
  mRect := ARect;
  mText := AText;
  Canvas.TextRect(mRect, mText, [tfSingleLine, tfVerticalCenter, tfEndEllipsis, tfNoPrefix]);
end;

procedure TCallPainter.DrawMore(const ABox: TAtlasCallBox; const ARect: TRect);
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.Pen.Style := psDot;
  Canvas.Pen.Color := ToColor(Colors.Line);
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Px(8 * Scale), Px(8 * Scale));
  if Scale < cMinTextScale then
  begin
    Exit;
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.Font.Color := ToColor(Colors.Accent);
  Canvas.Font.Style := [];
  BoxText(Rect(ARect.Left + Pad, ARect.Top, ARect.Right - Pad, ARect.Bottom),
    TAtlasResultsStrings.Fmt(TAtlasResultsTextId.CallDiagramMore, [ABox.Hidden]));
end;

procedure TCallPainter.DrawNodeTexts(const ABox: TAtlasCallBox; const ARect: TRect);
var
  mNode: TAtlasCallNode;
  mCaption: string;
begin
  mNode := View.FDiagram[ABox.Node];
  Canvas.Brush.Style := bsClear;
  // Erste Zeile: Name (erschlossen mit ≈), zweite: Fundstelle, ▸ wenn zugeklappte Kinder warten.
  mCaption := TAtlasCallDiagram.Title(mNode.Item);
  if mNode.Item.Confidence.Inferred then
  begin
    mCaption := '≈ ' + mCaption;
  end;
  Canvas.Font.Style := [fsBold];
  Canvas.Font.Color := ToColor(Colors.Text);
  if mNode.Library_ then
  begin
    Canvas.Font.Color := ToColor(Colors.Muted);
  end;
  BoxText(Rect(ARect.Left + Pad, ARect.Top + Pad div 2, ARect.Right - Pad, (ARect.Top + ARect.Bottom) div 2 + 1),
    mCaption);
  Canvas.Font.Style := [];
  Canvas.Font.Color := ToColor(Colors.Muted);
  mCaption := TAtlasCallDiagram.Location(mNode.Item);
  if View.FDiagram.NeedsLoad(ABox.Node) or (not mNode.Expanded and (Length(mNode.Children) > 0)) then
  begin
    mCaption := mCaption + '  ▸';
  end;
  BoxText(Rect(ARect.Left + Pad, (ARect.Top + ARect.Bottom) div 2 - 1, ARect.Right - Pad, ARect.Bottom - Pad div 2),
    mCaption);
end;

procedure TCallPainter.DrawNode(const ABox: TAtlasCallBox; const ARect: TRect);
var
  mNode: TAtlasCallNode;
  mFill, mBorder: TAtlasColor;
begin
  mNode := View.FDiagram[ABox.Node];
  mFill := Colors.Surface;
  if mNode.Library_ then
  begin
    mFill := Colors.Gutter;
  end;
  mBorder := Colors.Line;
  if mNode.Parent < 0 then
  begin
    mBorder := Colors.Accent;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(mFill);
  Canvas.Pen.Color := ToColor(mBorder);
  if ABox.Node = View.FSelected then
  begin
    Canvas.Pen.Color := ToColor(Colors.Accent);
    Canvas.Pen.Width := View.ScaleValue(2);
  end;
  Canvas.RoundRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, Px(8 * Scale), Px(8 * Scale));
  if Scale >= cMinTextScale then
  begin
    DrawNodeTexts(ABox, ARect);
  end;
end;

procedure TCallPainter.Paint;
var
  mIndex: Integer;
  mBox: TAtlasCallBox;
  mRect: TRect;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(View.ClientRect);
  Canvas.Font.Assign(View.Font);
  Canvas.Font.Size := Max(1, Round(View.Font.Size * Min(Scale, 1.5)));
  Canvas.Font.Color := ToColor(Colors.Muted);
  for mIndex := 0 to High(View.FLayout.Edges) do
  begin
    DrawEdge(View.FLayout.Edges[mIndex]);
  end;
  for mIndex := 0 to High(View.FLayout.Boxes) do
  begin
    mBox := View.FLayout.Boxes[mIndex];
    mRect := View.BoxRect(mIndex);
    if not mRect.IntersectsWith(View.ClientRect) then
    begin
      Continue;
    end;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    if mBox.Kind = TAtlasCallBoxKind.More then
    begin
      DrawMore(mBox, mRect);
    end
    else
    begin
      DrawNode(mBox, mRect);
    end;
  end;
end;

{ TAtlasCallDiagramView }

constructor TAtlasCallDiagramView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
  DoubleBuffered := True;
  TabStop := True;
  ShowHint := True;
  FDiagram := TAtlasCallDiagram.Create(nil);
  FView := Default(TAtlasCallView);
  FView.Scale := 1;
  FSelected := -1;
  FHintBox := -1;
end;

destructor TAtlasCallDiagramView.Destroy;
begin
  FDiagram.Free;
  inherited Destroy;
end;


function TAtlasCallDiagramView.BoxRect(ABox: Integer): TRect;
var
  mLeft, mTop: Double;
begin
  mLeft := FView.ScreenX(TAtlasCallView.BoxX(FLayout.Boxes[ABox]));
  mTop := FView.ScreenY(TAtlasCallView.BoxY(FLayout.Boxes[ABox]));
  Result := Rect(Px(mLeft), Px(mTop), Px(mLeft + TAtlasCallView.cBoxWidth * FView.Scale),
    Px(mTop + TAtlasCallView.cBoxHeight * FView.Scale));
end;

function TAtlasCallDiagramView.GetProjectOnly: Boolean;
begin
  Result := FDiagram.ProjectOnly;
end;

procedure TAtlasCallDiagramView.SetIsProjectFile(const AValue: TFunc<string, Boolean>);
begin
  FDiagram.IsProjectFile := AValue;
end;

procedure TAtlasCallDiagramView.SetProjectOnly(AValue: Boolean);
begin
  if FDiagram.ProjectOnly = AValue then
  begin
    Exit;
  end;
  FDiagram.ProjectOnly := AValue;
  Relayout;
end;

procedure TAtlasCallDiagramView.Relayout;
begin
  FLayout := FDiagram.Layout;
  FHintBox := -1;
  Invalidate;
end;

procedure TAtlasCallDiagramView.ShowRoots(ADirection: TAtlasHierarchyDirection;
  const ARoots: TArray<TAtlasHierarchyItem>);
begin
  FDiagram.Reset(ADirection, ARoots);
  FSelected := -1;
  if FDiagram.Count > 0 then
  begin
    FSelected := 0;
    ToggleNode(0);
  end;
  Relayout;
  FFitted := False;
  if (ClientWidth > 0) and (ClientHeight > 0) then
  begin
    FitView;
  end;
end;

procedure TAtlasCallDiagramView.ToggleNode(ANode: Integer);
var
  mChildren: TArray<TAtlasHierarchyItem>;
begin
  if (ANode < 0) or (ANode >= FDiagram.Count) then
  begin
    Exit;
  end;
  if FDiagram.NeedsLoad(ANode) then
  begin
    mChildren := nil;
    if Assigned(FHandlers.OnLoad) then
    begin
      Screen.Cursor := crHourGlass;
      try
        mChildren := FHandlers.OnLoad(FDiagram.Direction, FDiagram[ANode].Item);
      finally
        Screen.Cursor := crDefault;
      end;
    end;
    FDiagram.SetChildren(ANode, mChildren);
  end
  else
  begin
    FDiagram.Toggle(ANode);
  end;
  Relayout;
end;

procedure TAtlasCallDiagramView.ClickBox(ABox: Integer);
begin
  if (ABox < 0) or (ABox > High(FLayout.Boxes)) then
  begin
    FSelected := -1;
    Invalidate;
    Exit;
  end;
  if FLayout.Boxes[ABox].Kind = TAtlasCallBoxKind.More then
  begin
    FDiagram.ShowAll(FLayout.Boxes[ABox].Node);
    Relayout;
    Exit;
  end;
  FSelected := FLayout.Boxes[ABox].Node;
  ToggleNode(FSelected);
end;

procedure TAtlasCallDiagramView.FitView;
begin
  FView.Fit(FLayout, ClientWidth, ClientHeight);
  FFitted := Length(FLayout.Boxes) > 0;
  Invalidate;
end;

procedure TAtlasCallDiagramView.ZoomBy(AFactor: Double);
begin
  FView.ZoomAt(AFactor, ClientWidth / 2, ClientHeight / 2);
  Invalidate;
end;

function TAtlasCallDiagramView.Html(const ATitle: string): string;
begin
  Result := FDiagram.Html(ATitle);
end;

procedure TAtlasCallDiagramView.OpenSelected;
begin
  if (FSelected >= 0) and (FSelected < FDiagram.Count) and Assigned(FHandlers.OnOpen) then
  begin
    FHandlers.OnOpen(FDiagram[FSelected].Item);
  end;
end;

procedure TAtlasCallDiagramView.Resize;
begin
  inherited Resize;
  if not FFitted and (ClientWidth > 0) and (ClientHeight > 0) and (Length(FLayout.Boxes) > 0) then
  begin
    FitView;
  end;
end;

procedure TAtlasCallDiagramView.Paint;
begin
  TCallPainter.Create(Self).Paint;
end;

function TAtlasCallDiagramView.BoxHint(ABox: Integer): string;
var
  mNode: TAtlasCallNode;
begin
  if (ABox < 0) or (ABox > High(FLayout.Boxes)) then
  begin
    Exit(TAtlasResultsStrings.Text(TAtlasResultsTextId.CallDiagramHint));
  end;
  if FLayout.Boxes[ABox].Kind = TAtlasCallBoxKind.More then
  begin
    Exit(TAtlasResultsStrings.Fmt(TAtlasResultsTextId.CallDiagramMore, [FLayout.Boxes[ABox].Hidden]));
  end;
  mNode := FDiagram[FLayout.Boxes[ABox].Node];
  Result := TAtlasCallDiagram.Title(mNode.Item);
  if mNode.Item.FileName <> '' then
  begin
    Result := Result + ' (' + TAtlasCallDiagram.Location(mNode.Item) + ')';
  end;
  if mNode.Item.Confidence.Explanation <> '' then
  begin
    Result := Result + sLineBreak + mNode.Item.Confidence.Explanation;
  end;
end;

procedure TAtlasCallDiagramView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
  begin
    SetFocus;
  end;
  // Doppelklick: Der erste Klick hat schon aufgeklappt, der zweite springt nur (DblClick).
  if (Button <> mbLeft) or (ssDouble in Shift) then
  begin
    Exit;
  end;
  FDrag.Active := True;
  FDrag.Moved := False;
  FDrag.X := X;
  FDrag.Y := Y;
end;

procedure TAtlasCallDiagramView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHit: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDrag.Active then
  begin
    mHit := FView.BoxAt(FLayout, X, Y);
    if mHit <> FHintBox then
    begin
      FHintBox := mHit;
      Hint := BoxHint(mHit);
      Application.CancelHint;
    end;
    Exit;
  end;
  if not FDrag.Moved and (Abs(X - FDrag.X) <= cDragThreshold) and (Abs(Y - FDrag.Y) <= cDragThreshold) then
  begin
    Exit;
  end;
  FDrag.Moved := True;
  FView.Pan(X - FDrag.X, Y - FDrag.Y);
  FDrag.X := X;
  FDrag.Y := Y;
  Invalidate;
end;

procedure TAtlasCallDiagramView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not FDrag.Active then
  begin
    Exit;
  end;
  FDrag.Active := False;
  if FDrag.Moved then
  begin
    Exit;
  end;
  ClickBox(FView.BoxAt(FLayout, X, Y));
end;

procedure TAtlasCallDiagramView.DblClick;
begin
  inherited DblClick;
  OpenSelected;
end;

procedure TAtlasCallDiagramView.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_ADD, VK_OEM_PLUS:
      ZoomBy(1.25);
    VK_SUBTRACT, VK_OEM_MINUS:
      ZoomBy(1 / 1.25);
    Ord('0'), VK_NUMPAD0:
      FitView;
    VK_RETURN:
      OpenSelected;
    VK_SPACE:
      ToggleNode(FSelected);
  else
    Exit;
  end;
  Key := 0;
end;

function TAtlasCallDiagramView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  mLocal: TPoint;
begin
  Result := True;
  mLocal := ScreenToClient(MousePos);
  if WheelDelta > 0 then
  begin
    FView.ZoomAt(1.15, mLocal.X, mLocal.Y);
  end
  else
  begin
    FView.ZoomAt(1 / 1.15, mLocal.X, mLocal.Y);
  end;
  Invalidate;
end;

end.
