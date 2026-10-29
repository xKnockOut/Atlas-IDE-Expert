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
  private
    FDiagram: TAtlasCallDiagram;
    FLayout: TAtlasCallLayout;
    FView: TAtlasCallView;
    FFitted: Boolean;
    /// <summary>Gewählter Knoten; -1 ohne.</summary>
    FSelected: Integer;
    FHintBox: Integer;
    FDragging: Boolean;
    FMoved: Boolean;
    FDragX: Integer;
    FDragY: Integer;
    FOnLoad: TAtlasCallLoad;
    FOnOpen: TAtlasCallOpen;
    function Px(AValue: Double): Integer;
    function BoxRect(ABox: Integer): TRect;
    function GetProjectOnly: Boolean;
    procedure SetIsProjectFile(const AValue: TFunc<string, Boolean>);
    procedure SetProjectOnly(AValue: Boolean);
    procedure Relayout;
    procedure DrawEdge(const AEdge: TAtlasCallEdge; ADash, ABack: TColor);
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
    property IsProjectFile: TFunc<string, Boolean> write SetIsProjectFile;
    property OnLoad: TAtlasCallLoad read FOnLoad write FOnLoad;
    property OnOpen: TAtlasCallOpen read FOnOpen write FOnOpen;
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
  Atlas.UI.Strings;

const
  /// <summary>Bildpunkte, ab denen ein Mausdruck als Ziehen gilt.</summary>
  DragThreshold = 3;
  /// <summary>Unter dieser Vergrößerung keine Schrift mehr (unlesbar).</summary>
  MinTextScale = 0.35;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
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

function TAtlasCallDiagramView.Px(AValue: Double): Integer;
begin
  Result := Round(AValue);
end;

function TAtlasCallDiagramView.BoxRect(ABox: Integer): TRect;
var
  Left, Top: Double;
begin
  Left := FView.ScreenX(TAtlasCallView.BoxX(FLayout.Boxes[ABox]));
  Top := FView.ScreenY(TAtlasCallView.BoxY(FLayout.Boxes[ABox]));
  Result := Rect(Px(Left), Px(Top), Px(Left + TAtlasCallView.BoxWidth * FView.Scale),
    Px(Top + TAtlasCallView.BoxHeight * FView.Scale));
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
    Exit;
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
    FitView;
end;

procedure TAtlasCallDiagramView.ToggleNode(ANode: Integer);
var
  Children: TArray<TAtlasHierarchyItem>;
begin
  if (ANode < 0) or (ANode >= FDiagram.Count) then
    Exit;
  if FDiagram.NeedsLoad(ANode) then
  begin
    Children := nil;
    if Assigned(FOnLoad) then
    begin
      Screen.Cursor := crHourGlass;
      try
        Children := FOnLoad(FDiagram.Direction, FDiagram[ANode].Item);
      finally
        Screen.Cursor := crDefault;
      end;
    end;
    FDiagram.SetChildren(ANode, Children);
  end
  else
    FDiagram.Toggle(ANode);
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
  if (FSelected >= 0) and (FSelected < FDiagram.Count) and Assigned(FOnOpen) then
    FOnOpen(FDiagram[FSelected].Item);
end;

procedure TAtlasCallDiagramView.Resize;
begin
  inherited Resize;
  if not FFitted and (ClientWidth > 0) and (ClientHeight > 0) and (Length(FLayout.Boxes) > 0) then
    FitView;
end;

procedure TAtlasCallDiagramView.DrawEdge(const AEdge: TAtlasCallEdge; ADash, ABack: TColor);
var
  Source, Target: TRect;
  Points: array[0..3] of TPoint;
  Caption: string;
  Top, Mid, Count: Integer;
begin
  Source := BoxRect(AEdge.Source);
  Target := BoxRect(AEdge.Target);
  if AEdge.Back then
  begin
    // Bogen über beide Kästen zurück zum Vorfahren, wie in der HTML-Datei.
    Top := Min(Source.Top, Target.Top) - Px(14 * FView.Scale);
    Points[0] := Point((Source.Left + Source.Right) div 2, Source.Top);
    Points[1] := Point(Points[0].X, Top);
    Points[3] := Point((Target.Left + Target.Right) div 2, Target.Top);
    Points[2] := Point(Points[3].X, Top);
    Canvas.Pen.Color := ABack;
  end
  else
  begin
    Points[0] := Point(Source.Right, (Source.Top + Source.Bottom) div 2);
    Points[3] := Point(Target.Left, (Target.Top + Target.Bottom) div 2);
    Mid := (Points[0].X + Points[3].X) div 2;
    Points[1] := Point(Mid, Points[0].Y);
    Points[2] := Point(Mid, Points[3].Y);
    Canvas.Pen.Color := ADash;
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
    Canvas.Pen.Width := Max(1, Px(1.5 * FView.Scale));
  end;
  Canvas.Brush.Style := bsClear;
  Canvas.PolyBezier(Points);
  // Pfeilspitze am Ziel.
  Canvas.Pen.Style := psSolid;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Canvas.Pen.Color;
  Count := Max(3, Px(6 * FView.Scale));
  if AEdge.Back then
    Canvas.Polygon([Points[3], Point(Points[3].X - Count div 2, Points[3].Y - Count),
      Point(Points[3].X + Count div 2, Points[3].Y - Count)])
  else
    Canvas.Polygon([Points[3], Point(Points[3].X - Count, Points[3].Y - Count div 2),
      Point(Points[3].X - Count, Points[3].Y + Count div 2)]);
  if not AEdge.Dashed or AEdge.Back or (AEdge.Implementations <= 0) or (FView.Scale < MinTextScale) then
    Exit;
  if AEdge.Implementations = 1 then
    Caption := TAtlasStrings.Text(TAtlasTextId.CallDiagramImplementation)
  else
    Caption := TAtlasStrings.Fmt(TAtlasTextId.CallDiagramImplementations, [AEdge.Implementations]);
  Canvas.Brush.Style := bsClear;
  Canvas.TextOut(Points[3].X - Canvas.TextWidth(Caption) - Px(8 * FView.Scale),
    Points[3].Y - Canvas.TextHeight(Caption) - 1, Caption);
end;

procedure TAtlasCallDiagramView.Paint;
var
  Colors: TAtlasColors;
  Index: Integer;
  Box: TAtlasCallBox;
  Node: TAtlasCallNode;
  R, TextBox: TRect;
  Caption: string;
  Fill, Border, Back: TAtlasColor;
  Pad, Size: Integer;
begin
  Colors := TAtlasColors.ForBackground(TAtlasColor(ColorToRGB(StyleServices(Self).GetSystemColor(clWindow))));
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Canvas.Font.Assign(Font);
  Size := Max(1, Round(Font.Size * Min(FView.Scale, 1.5)));
  Canvas.Font.Size := Size;
  Canvas.Font.Color := ToColor(Colors.Muted);
  // Rekursion in Warnfarbe wie die HTML-Datei.
  Back := Colors.Warn;
  for Index := 0 to High(FLayout.Edges) do
    DrawEdge(FLayout.Edges[Index], ToColor(Colors.Line), ToColor(Back));
  Pad := Max(2, Px(8 * FView.Scale));
  for Index := 0 to High(FLayout.Boxes) do
  begin
    Box := FLayout.Boxes[Index];
    R := BoxRect(Index);
    if not R.IntersectsWith(ClientRect) then
      Continue;
    Canvas.Pen.Style := psSolid;
    Canvas.Pen.Width := 1;
    if Box.Kind = TAtlasCallBoxKind.More then
    begin
      Canvas.Brush.Style := bsSolid;
      Canvas.Brush.Color := ToColor(Colors.Surface);
      Canvas.Pen.Style := psDot;
      Canvas.Pen.Color := ToColor(Colors.Line);
      Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Px(8 * FView.Scale), Px(8 * FView.Scale));
      if FView.Scale >= MinTextScale then
      begin
        Canvas.Brush.Style := bsClear;
        Canvas.Font.Color := ToColor(Colors.Accent);
        Canvas.Font.Style := [];
        Caption := TAtlasStrings.Fmt(TAtlasTextId.CallDiagramMore, [Box.Hidden]);
        TextBox := Rect(R.Left + Pad, R.Top, R.Right - Pad, R.Bottom);
        Canvas.TextRect(TextBox, Caption, [tfSingleLine, tfVerticalCenter, tfEndEllipsis, tfNoPrefix]);
      end;
      Continue;
    end;
    Node := FDiagram[Box.Node];
    Fill := Colors.Surface;
    if Node.Library_ then
      Fill := Colors.Gutter;
    Border := Colors.Line;
    if Node.Parent < 0 then
      Border := Colors.Accent;
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(Fill);
    Canvas.Pen.Color := ToColor(Border);
    if Box.Node = FSelected then
    begin
      Canvas.Pen.Color := ToColor(Colors.Accent);
      Canvas.Pen.Width := 2;
    end;
    Canvas.RoundRect(R.Left, R.Top, R.Right, R.Bottom, Px(8 * FView.Scale), Px(8 * FView.Scale));
    if FView.Scale < MinTextScale then
      Continue;
    Canvas.Brush.Style := bsClear;
    // Erste Zeile: Name (erschlossen mit ≈), zweite: Fundstelle, ▸ wenn zugeklappte Kinder warten.
    Caption := TAtlasCallDiagram.Title(Node.Item);
    if Node.Item.Confidence.Inferred then
      Caption := '≈ ' + Caption;
    Canvas.Font.Style := [fsBold];
    if Node.Library_ then
      Canvas.Font.Color := ToColor(Colors.Muted)
    else
      Canvas.Font.Color := ToColor(Colors.Text);
    TextBox := Rect(R.Left + Pad, R.Top + Pad div 2, R.Right - Pad, (R.Top + R.Bottom) div 2 + 1);
    Canvas.TextRect(TextBox, Caption, [tfSingleLine, tfVerticalCenter, tfEndEllipsis, tfNoPrefix]);
    Canvas.Font.Style := [];
    Canvas.Font.Color := ToColor(Colors.Muted);
    Caption := TAtlasCallDiagram.Location(Node.Item);
    if FDiagram.NeedsLoad(Box.Node) or (not Node.Expanded and (Length(Node.Children) > 0)) then
      Caption := Caption + '  ▸';
    TextBox := Rect(R.Left + Pad, (R.Top + R.Bottom) div 2 - 1, R.Right - Pad, R.Bottom - Pad div 2);
    Canvas.TextRect(TextBox, Caption, [tfSingleLine, tfVerticalCenter, tfEndEllipsis, tfNoPrefix]);
  end;
end;

function TAtlasCallDiagramView.BoxHint(ABox: Integer): string;
var
  Node: TAtlasCallNode;
begin
  if (ABox < 0) or (ABox > High(FLayout.Boxes)) then
    Exit(TAtlasStrings.Text(TAtlasTextId.CallDiagramHint));
  if FLayout.Boxes[ABox].Kind = TAtlasCallBoxKind.More then
    Exit(TAtlasStrings.Fmt(TAtlasTextId.CallDiagramMore, [FLayout.Boxes[ABox].Hidden]));
  Node := FDiagram[FLayout.Boxes[ABox].Node];
  Result := TAtlasCallDiagram.Title(Node.Item);
  if Node.Item.FileName <> '' then
    Result := Result + ' (' + TAtlasCallDiagram.Location(Node.Item) + ')';
  if Node.Item.Confidence.Explanation <> '' then
    Result := Result + sLineBreak + Node.Item.Confidence.Explanation;
end;

procedure TAtlasCallDiagramView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if CanFocus then
    SetFocus;
  // Doppelklick: Der erste Klick hat schon aufgeklappt, der zweite springt nur (DblClick).
  if (Button <> mbLeft) or (ssDouble in Shift) then
    Exit;
  FDragging := True;
  FMoved := False;
  FDragX := X;
  FDragY := Y;
end;

procedure TAtlasCallDiagramView.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hit: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
  begin
    Hit := FView.BoxAt(FLayout, X, Y);
    if Hit <> FHintBox then
    begin
      FHintBox := Hit;
      Hint := BoxHint(Hit);
      Application.CancelHint;
    end;
    Exit;
  end;
  if not FMoved and (Abs(X - FDragX) <= DragThreshold) and (Abs(Y - FDragY) <= DragThreshold) then
    Exit;
  FMoved := True;
  FView.Pan(X - FDragX, Y - FDragY);
  FDragX := X;
  FDragY := Y;
  Invalidate;
end;

procedure TAtlasCallDiagramView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if (Button <> mbLeft) or not FDragging then
    Exit;
  FDragging := False;
  if FMoved then
    Exit;
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
  Local: TPoint;
begin
  Result := True;
  Local := ScreenToClient(MousePos);
  if WheelDelta > 0 then
    FView.ZoomAt(1.15, Local.X, Local.Y)
  else
    FView.ZoomAt(1 / 1.15, Local.X, Local.Y);
  Invalidate;
end;

end.
