unit Atlas.UI.Outline.Breadcrumbs;

// Brotkrumenleiste (#590), Darstellung: eine Zeile über dem Editor mit den
// Gliedern des Pfads, je Glied Badge in den Farben der Vervollständigung
// (#421) und Name, dazwischen „›“. Die Höhe hängt nur von der DPI ab, nie
// vom Inhalt. Passt der Pfad nicht in die Breite, entfallen vorn Glieder
// („…“), das letzte bleibt immer sichtbar.
// - Klick (beim Loslassen) auf ein Glied mit Geschwistern meldet OnOpenMenu
//   (Sprungmenü).
// - Klick auf das „›“ hinter einem Glied mit Kindern meldet OnOpenChildren
//   (wie die Adressleiste im Explorer); hat das letzte Glied Kinder, steht
//   auch hinter ihm ein „›“.
// - Strg+Klick auf ein Glied meldet OnJump (Umschalt dazu: Deklaration);
//   Glieder ohne Geschwister springen schon beim einfachen Klick.
// - Mit Fokus (Tastenkürzel) wechseln ←/→ das gewählte Glied, ↓ und Enter
//   öffnen sein Menü, Strg+↓ das Menü der Kinder, Strg+Enter springt, Esc
//   gibt den Fokus über OnLeave an den Editor zurück.
// - Farben über SetColors: Gutter ist die Fläche, Text/Muted die Schrift.
// Ohne Glieder steht EmptyText gedämpft in der Leiste.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  System.UITypes,
  Vcl.Controls,
  Vcl.Graphics,
  Atlas.Core.Style.Color,
  Atlas.Core.Style.Palette,
  Atlas.Core.Outline.Breadcrumbs;

type
  /// <summary>Menü zum Glied AIndex öffnen; APoint ist die linke untere Ecke des Glieds am Bildschirm.</summary>
  TAtlasCrumbMenuEvent = reference to procedure(AIndex: Integer; const APoint: TPoint);
  /// <summary>Zum Glied AIndex springen; ADeclaration = zur Deklaration statt zur Implementierung.</summary>
  TAtlasCrumbJumpEvent = reference to procedure(AIndex: Integer; ADeclaration: Boolean);

  TAtlasBreadcrumbBar = class(TCustomControl)
  private
    FCrumbs: TAtlasCrumbs;
    FColors: TAtlasColors;
    FRects: TArray<TRect>;
    /// <summary>„›“ hinter dem Glied; leer, wenn keins steht.</summary>
    FSeparators: TArray<TRect>;
    FFirstShown: Integer;
    FLaidOut: Boolean;
    FHot: Integer;
    FHotSeparator: Integer;
    FSelected: Integer;
    FEmptyText: string;
    FCrumbHint: string;
    FSeparatorHint: string;
    FOnOpenMenu: TAtlasCrumbMenuEvent;
    FOnOpenChildren: TAtlasCrumbMenuEvent;
    FOnJump: TAtlasCrumbJumpEvent;
    FOnLeave: TProc;
    FOnDisabled: TProc;
    function Scale(AValue: Integer): Integer;
    function BadgeWidth: Integer;
    function CrumbWidth(AIndex: Integer): Integer;
    function SeparatorWidth: Integer;
    function EllipsisWidth: Integer;
    procedure Layout;
    function GetFirstShown: Integer;
    procedure SetEmptyText(const AValue: string);
    procedure DrawCrumb(AIndex: Integer);
    procedure DrawSeparator(ALeft: Integer; const AText: string); overload;
    procedure DrawSeparator(AIndex: Integer); overload;
    function TrailingSeparator: Boolean;
    procedure WMGetDlgCode(var Message: TWMGetDlgCode); message WM_GETDLGCODE;
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
    procedure WMEnable(var Message: TWMEnable); message WM_ENABLE;
    procedure CMFontChanged(var Message: TMessage); message CM_FONTCHANGED;
  protected
    procedure Paint; override;
    procedure Resize; override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure ChangeScale(M, D: Integer; isDpiChange: Boolean); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Glieder setzen; gleiche Glieder zeichnen nicht neu. Die Auswahl springt aufs letzte Glied.</summary>
    procedure SetCrumbs(const ACrumbs: TAtlasCrumbs);
    procedure SetColors(const AColors: TAtlasColors);
    /// <summary>Glied unter dem Punkt (Client); -1 = keins.</summary>
    function CrumbAt(X, Y: Integer): Integer;
    /// <summary>Fläche des Glieds (Client); leer, wenn es wegen der Breite entfällt.</summary>
    function CrumbRect(AIndex: Integer): TRect;
    /// <summary>„›“ hinter dem Glied unter dem Punkt (Client), nur wenn das Glied Kinder hat; -1 = keins.</summary>
    function SeparatorAt(X, Y: Integer): Integer;
    /// <summary>Fläche des „›“ hinter dem Glied; leer, wenn keins steht.</summary>
    function SeparatorRect(AIndex: Integer): TRect;
    /// <summary>Fokus und Auswahl aufs letzte Glied (Tastenkürzel).</summary>
    procedure FocusLast;
    /// <summary>Menü des Glieds öffnen, wenn es Geschwister hat.</summary>
    procedure OpenMenu(AIndex: Integer);
    /// <summary>Menü der Kinder des Glieds unter dessen „›“ öffnen, wenn es Kinder hat.</summary>
    procedure OpenChildren(AIndex: Integer);
    /// <summary>Zum Glied springen (OnJump), wenn es einen Knoten hat oder die Unit ist.</summary>
    procedure Jump(AIndex: Integer; ADeclaration: Boolean);
    /// <summary>Höhe der Leiste bei APPI (eine Zeile).</summary>
    class function BarHeight(APPI: Integer): Integer; static;
    property Crumbs: TAtlasCrumbs read FCrumbs;
    property Selected: Integer read FSelected;
    /// <summary>Erstes sichtbares Glied (davor „…“).</summary>
    property FirstShown: Integer read GetFirstShown;
    property EmptyText: string read FEmptyText write SetEmptyText;
    /// <summary>Hinweis über einem Glied bzw. über einem „›“ mit Kindern.</summary>
    property CrumbHint: string read FCrumbHint write FCrumbHint;
    property SeparatorHint: string read FSeparatorHint write FSeparatorHint;
    property OnOpenMenu: TAtlasCrumbMenuEvent read FOnOpenMenu write FOnOpenMenu;
    property OnOpenChildren: TAtlasCrumbMenuEvent read FOnOpenChildren write FOnOpenChildren;
    property OnJump: TAtlasCrumbJumpEvent read FOnJump write FOnJump;
    property OnLeave: TProc read FOnLeave write FOnLeave;
    /// <summary>Das Fenster der Leiste wurde gesperrt (WM_ENABLE mit False, über VCL oder EnableWindow); ein
    /// gesperrtes Fenster bekommt keine Maus, die Klicks landen beim Elternfenster.</summary>
    property OnDisabled: TProc read FOnDisabled write FOnDisabled;
  end;

implementation

uses
  System.Math,
  Vcl.Forms;

const
  Separator = '›';
  Ellipsis = '…';
  /// <summary>Höhe bei 96 DPI.</summary>
  BaseHeight = 22;

function ToColor(AColor: TAtlasColor): TColor;
begin
  Result := TColor(AColor);
end;

function SameCrumbs(const A, B: TAtlasCrumbs): Boolean;
var
  Index, Sibling: Integer;
begin
  Result := Length(A) = Length(B);
  Index := 0;
  while Result and (Index <= High(A)) do
  begin
    Result := (A[Index].Text = B[Index].Text) and (A[Index].Node = B[Index].Node) and
      (A[Index].Badge.Kind = B[Index].Badge.Kind) and (A[Index].Badge.Code = B[Index].Badge.Code) and
      (A[Index].Current = B[Index].Current) and (Length(A[Index].Siblings) = Length(B[Index].Siblings)) and
      (Length(A[Index].Children) = Length(B[Index].Children));
    Sibling := 0;
    while Result and (Sibling <= High(A[Index].Siblings)) do
    begin
      Result := A[Index].Siblings[Sibling] = B[Index].Siblings[Sibling];
      Inc(Sibling);
    end;
    Sibling := 0;
    while Result and (Sibling <= High(A[Index].Children)) do
    begin
      Result := A[Index].Children[Sibling] = B[Index].Children[Sibling];
      Inc(Sibling);
    end;
    Inc(Index);
  end;
end;

{ TAtlasBreadcrumbBar }

constructor TAtlasBreadcrumbBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque] - [csSetCaption];
  DoubleBuffered := True;
  TabStop := False;
  FColors := TAtlasColors.Light;
  FHot := -1;
  FHotSeparator := -1;
  FSelected := -1;
  ShowHint := True;
  Height := BarHeight(96);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
end;

class function TAtlasBreadcrumbBar.BarHeight(APPI: Integer): Integer;
begin
  Result := MulDiv(BaseHeight, Max(APPI, 96), 96);
end;

procedure TAtlasBreadcrumbBar.ChangeScale(M, D: Integer; isDpiChange: Boolean);
begin
  Constraints.MinHeight := 0;
  Constraints.MaxHeight := 0;
  inherited ChangeScale(M, D, isDpiChange);
  Height := BarHeight(CurrentPPI);
  Constraints.MinHeight := Height;
  Constraints.MaxHeight := Height;
  FLaidOut := False;
end;

function TAtlasBreadcrumbBar.Scale(AValue: Integer): Integer;
begin
  Result := MulDiv(AValue, Max(CurrentPPI, 96), 96);
end;

procedure TAtlasBreadcrumbBar.SetCrumbs(const ACrumbs: TAtlasCrumbs);
begin
  if SameCrumbs(ACrumbs, FCrumbs) then
    Exit;
  FCrumbs := ACrumbs;
  FSelected := High(FCrumbs);
  FHot := -1;
  FHotSeparator := -1;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.SetColors(const AColors: TAtlasColors);
begin
  FColors := AColors;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.SetEmptyText(const AValue: string);
begin
  if AValue = FEmptyText then
    Exit;
  FEmptyText := AValue;
  if Length(FCrumbs) = 0 then
    Invalidate;
end;

procedure TAtlasBreadcrumbBar.Resize;
begin
  inherited Resize;
  FLaidOut := False;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.CMFontChanged(var Message: TMessage);
begin
  inherited;
  FLaidOut := False;
  Invalidate;
end;

function TAtlasBreadcrumbBar.BadgeWidth: Integer;
begin
  Result := Scale(22);
end;

function TAtlasBreadcrumbBar.SeparatorWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextWidth(Separator) + Scale(10);
end;

function TAtlasBreadcrumbBar.EllipsisWidth: Integer;
begin
  Canvas.Font := Font;
  Result := Canvas.TextWidth(Ellipsis) + Scale(6);
end;

function TAtlasBreadcrumbBar.CrumbWidth(AIndex: Integer): Integer;
begin
  Canvas.Font := Font;
  if AIndex = High(FCrumbs) then
    Canvas.Font.Style := [fsBold];
  Result := Canvas.TextWidth(FCrumbs[AIndex].Text) + Scale(8);
  if FCrumbs[AIndex].Badge.Code <> '' then
    Inc(Result, BadgeWidth + Scale(4));
  Canvas.Font := Font;
end;

function TAtlasBreadcrumbBar.GetFirstShown: Integer;
begin
  // Die Aufteilung entsteht erst beim Zeichnen; nach SetCrumbs oder Größenänderung hier nachholen.
  Layout;
  Result := FFirstShown;
end;

procedure TAtlasBreadcrumbBar.Layout;
var
  Widths: TArray<Integer>;
  Index, Total, Available, Left_: Integer;
begin
  if FLaidOut or not HandleAllocated then
    Exit;
  FLaidOut := True;
  SetLength(FRects, Length(FCrumbs));
  SetLength(FSeparators, Length(FCrumbs));
  SetLength(Widths, Length(FCrumbs));
  FFirstShown := 0;
  if Length(FCrumbs) = 0 then
    Exit;
  Total := 0;
  for Index := 0 to High(FCrumbs) do
  begin
    Widths[Index] := CrumbWidth(Index);
    Inc(Total, Widths[Index]);
  end;
  Inc(Total, High(FCrumbs) * SeparatorWidth);
  if TrailingSeparator then
    Inc(Total, SeparatorWidth);
  Available := ClientWidth - 2 * Scale(4);
  // Vorn Glieder weglassen, bis der Rest samt „…“ passt; das letzte bleibt.
  while (Total > Available) and (FFirstShown < High(FCrumbs)) do
  begin
    Dec(Total, Widths[FFirstShown] + SeparatorWidth);
    if FFirstShown = 0 then
      Inc(Total, EllipsisWidth + SeparatorWidth);
    Inc(FFirstShown);
  end;
  Left_ := Scale(4);
  if FFirstShown > 0 then
    Inc(Left_, EllipsisWidth + SeparatorWidth);
  for Index := 0 to High(FCrumbs) do
  begin
    FSeparators[Index] := TRect.Empty;
    if Index < FFirstShown then
      FRects[Index] := TRect.Empty
    else
    begin
      FRects[Index] := Rect(Left_, 0, Min(Left_ + Widths[Index], ClientWidth), ClientHeight);
      Left_ := Left_ + Widths[Index];
      if (Index < High(FCrumbs)) or TrailingSeparator then
        FSeparators[Index] := Rect(Left_, 0, Min(Left_ + SeparatorWidth, ClientWidth), ClientHeight);
      Left_ := Left_ + SeparatorWidth;
    end;
  end;
  if FSelected < FFirstShown then
    FSelected := High(FCrumbs);
end;

function TAtlasBreadcrumbBar.CrumbRect(AIndex: Integer): TRect;
begin
  Layout;
  if (AIndex < 0) or (AIndex > High(FRects)) then
    Exit(TRect.Empty);
  Result := FRects[AIndex];
end;

function TAtlasBreadcrumbBar.TrailingSeparator: Boolean;
begin
  Result := (Length(FCrumbs) > 0) and (Length(FCrumbs[High(FCrumbs)].Children) > 0);
end;

function TAtlasBreadcrumbBar.SeparatorRect(AIndex: Integer): TRect;
begin
  Layout;
  if (AIndex < 0) or (AIndex > High(FSeparators)) then
    Exit(TRect.Empty);
  Result := FSeparators[AIndex];
end;

function TAtlasBreadcrumbBar.SeparatorAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  Layout;
  if (Y >= 0) and (Y < ClientHeight) then
    for Index := FFirstShown to High(FSeparators) do
      if not FSeparators[Index].IsEmpty and (X >= FSeparators[Index].Left) and (X < FSeparators[Index].Right) and
        (Length(FCrumbs[Index].Children) > 0) then
        Exit(Index);
  Result := -1;
end;

function TAtlasBreadcrumbBar.CrumbAt(X, Y: Integer): Integer;
var
  Index: Integer;
begin
  Layout;
  if (Y >= 0) and (Y < ClientHeight) then
    for Index := FFirstShown to High(FRects) do
      if not FRects[Index].IsEmpty and (X >= FRects[Index].Left) and (X < FRects[Index].Right) then
        Exit(Index);
  Result := -1;
end;

procedure TAtlasBreadcrumbBar.DrawSeparator(ALeft: Integer; const AText: string);
var
  Part: TRect;
begin
  Canvas.Font := Font;
  Canvas.Font.Color := ToColor(FColors.Muted);
  Canvas.Brush.Style := bsClear;
  Part := Rect(ALeft, 0, ALeft + Canvas.TextWidth(AText) + Scale(10), ClientHeight);
  DrawText(Canvas.Handle, PChar(AText), -1, Part, DT_CENTER or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX);
end;

procedure TAtlasBreadcrumbBar.DrawSeparator(AIndex: Integer);
var
  Area: TRect;
  Radius: Integer;
begin
  Area := FSeparators[AIndex];
  if AIndex = FHotSeparator then
  begin
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.Pen.Color := ToColor(FColors.Selection);
    Radius := Scale(4);
    Canvas.RoundRect(Area.Left + Scale(1), Area.Top + Scale(2), Area.Right - Scale(1), Area.Bottom - Scale(2), Radius,
      Radius);
  end;
  DrawSeparator(Area.Left, Separator);
end;

procedure TAtlasBreadcrumbBar.DrawCrumb(AIndex: Integer);
var
  Crumb: TAtlasCrumb;
  Area, Box, Part: TRect;
  Left_, BoxHeight, Radius: Integer;
begin
  Crumb := FCrumbs[AIndex];
  Area := FRects[AIndex];
  Canvas.Brush.Style := bsSolid;
  if (AIndex = FHot) or ((AIndex = FSelected) and Focused) then
  begin
    Canvas.Brush.Color := ToColor(FColors.Selection);
    Canvas.Pen.Color := ToColor(FColors.Selection);
    if Focused and (AIndex = FSelected) then
      Canvas.Pen.Color := ToColor(FColors.Accent);
    Radius := Scale(4);
    Canvas.RoundRect(Area.Left, Area.Top + Scale(2), Area.Right, Area.Bottom - Scale(2), Radius, Radius);
  end;
  Left_ := Area.Left + Scale(4);
  if Crumb.Badge.Code <> '' then
  begin
    BoxHeight := Scale(15);
    Box := Rect(Left_, (ClientHeight - BoxHeight) div 2, Left_ + BadgeWidth, (ClientHeight - BoxHeight) div 2 +
      BoxHeight);
    Canvas.Brush.Style := bsSolid;
    Canvas.Brush.Color := ToColor(FColors.Badges[Crumb.Badge.Kind].Background);
    Canvas.Pen.Color := Canvas.Brush.Color;
    Radius := Scale(4);
    Canvas.RoundRect(Box.Left, Box.Top, Box.Right, Box.Bottom, Radius, Radius);
    Canvas.Font := Font;
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Height := -Round(Box.Height * 0.62);
    Canvas.Font.Color := ToColor(FColors.Badges[Crumb.Badge.Kind].Text);
    Canvas.Brush.Style := bsClear;
    DrawText(Canvas.Handle, PChar(Crumb.Badge.Code), -1, Box, DT_CENTER or DT_VCENTER or DT_SINGLELINE or
      DT_NOPREFIX);
    Left_ := Box.Right + Scale(4);
  end;
  Canvas.Font := Font;
  Canvas.Brush.Style := bsClear;
  if AIndex = High(FCrumbs) then
  begin
    Canvas.Font.Style := [fsBold];
    Canvas.Font.Color := ToColor(FColors.Text);
  end
  else
    Canvas.Font.Color := ToColor(FColors.Muted);
  Part := Rect(Left_, 0, Area.Right - Scale(2), ClientHeight);
  DrawText(Canvas.Handle, PChar(Crumb.Text), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
    DT_END_ELLIPSIS);
  Canvas.Font := Font;
end;

procedure TAtlasBreadcrumbBar.Paint;
var
  Index: Integer;
  Part: TRect;
begin
  Layout;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(FColors.Gutter);
  Canvas.FillRect(ClientRect);
  Canvas.Pen.Color := ToColor(FColors.Line);
  Canvas.MoveTo(0, ClientHeight - 1);
  Canvas.LineTo(ClientWidth, ClientHeight - 1);
  if Length(FCrumbs) = 0 then
  begin
    Canvas.Font := Font;
    Canvas.Font.Color := ToColor(FColors.Muted);
    Canvas.Brush.Style := bsClear;
    Part := Rect(Scale(8), 0, ClientWidth - Scale(4), ClientHeight);
    DrawText(Canvas.Handle, PChar(FEmptyText), -1, Part, DT_LEFT or DT_VCENTER or DT_SINGLELINE or DT_NOPREFIX or
      DT_END_ELLIPSIS);
    Exit;
  end;
  if FFirstShown > 0 then
  begin
    DrawSeparator(Scale(2), Ellipsis);
    DrawSeparator(Scale(4) + EllipsisWidth, Separator);
  end;
  for Index := FFirstShown to High(FCrumbs) do
  begin
    DrawCrumb(Index);
    if not FSeparators[Index].IsEmpty then
      DrawSeparator(Index);
  end;
end;

procedure TAtlasBreadcrumbBar.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot, HotSeparator: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  Hot := CrumbAt(X, Y);
  if (Hot >= 0) and (Length(FCrumbs[Hot].Siblings) = 0) and (FCrumbs[Hot].Node < 0) then
    Hot := -1;
  HotSeparator := SeparatorAt(X, Y);
  if (Hot = FHot) and (HotSeparator = FHotSeparator) then
    Exit;
  FHot := Hot;
  FHotSeparator := HotSeparator;
  if (Hot >= 0) or (HotSeparator >= 0) then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  // Hinweis je Teil: Glied (Menü, Strg+Klick) oder „›“ (Kinder).
  Application.CancelHint;
  if HotSeparator >= 0 then
    Hint := FSeparatorHint
  else if Hot >= 0 then
    Hint := FCrumbHint
  else
    Hint := '';
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if (FHot < 0) and (FHotSeparator < 0) then
    Exit;
  FHot := -1;
  FHotSeparator := -1;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  Index: Integer;
begin
  inherited MouseUp(Button, Shift, X, Y);
  // Erst beim Loslassen: Beim Drücken holt die IDE den Fokus zurück in den Editor, das Menü ginge sofort
  // wieder zu.
  if Button <> mbLeft then
    Exit;
  Index := SeparatorAt(X, Y);
  if Index >= 0 then
  begin
    OpenChildren(Index);
    Exit;
  end;
  Index := CrumbAt(X, Y);
  if Index < 0 then
    Exit;
  FSelected := Index;
  Invalidate;
  // Ohne Geschwister gibt es kein Menü; dann springt auch der einfache Klick.
  if (ssCtrl in Shift) or (Length(FCrumbs[Index].Siblings) = 0) then
    Jump(Index, ssShift in Shift)
  else
    OpenMenu(Index);
end;

procedure TAtlasBreadcrumbBar.OpenMenu(AIndex: Integer);
var
  Area: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or (Length(FCrumbs[AIndex].Siblings) = 0) or
    not Assigned(FOnOpenMenu) then
    Exit;
  Area := CrumbRect(AIndex);
  FOnOpenMenu(AIndex, ClientToScreen(Point(Area.Left, ClientHeight)));
end;

procedure TAtlasBreadcrumbBar.OpenChildren(AIndex: Integer);
var
  Area: TRect;
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or (Length(FCrumbs[AIndex].Children) = 0) or
    not Assigned(FOnOpenChildren) then
    Exit;
  Area := SeparatorRect(AIndex);
  // Ohne „›“ (letztes Glied ohne Platz) unter dem Glied selbst.
  if Area.IsEmpty then
    Area := CrumbRect(AIndex);
  FOnOpenChildren(AIndex, ClientToScreen(Point(Area.Left, ClientHeight)));
end;

procedure TAtlasBreadcrumbBar.Jump(AIndex: Integer; ADeclaration: Boolean);
begin
  if (AIndex < 0) or (AIndex > High(FCrumbs)) or not Assigned(FOnJump) then
    Exit;
  if (FCrumbs[AIndex].Node < 0) and (FCrumbs[AIndex].Badge.Kind <> TAtlasBadgeKind.Unit_) then
    Exit;
  FOnJump(AIndex, ADeclaration);
end;

procedure TAtlasBreadcrumbBar.FocusLast;
begin
  FSelected := High(FCrumbs);
  if CanFocus then
    SetFocus;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.KeyDown(var Key: Word; Shift: TShiftState);
begin
  inherited KeyDown(Key, Shift);
  case Key of
    VK_LEFT:
      if FSelected > FFirstShown then
      begin
        Dec(FSelected);
        Invalidate;
      end;
    VK_RIGHT:
      if FSelected < High(FCrumbs) then
      begin
        Inc(FSelected);
        Invalidate;
      end;
    VK_HOME:
      begin
        FSelected := Min(FFirstShown, High(FCrumbs));
        Invalidate;
      end;
    VK_END:
      begin
        FSelected := High(FCrumbs);
        Invalidate;
      end;
    VK_DOWN, VK_RETURN:
      if ssCtrl in Shift then
      begin
        if Key = VK_DOWN then
          OpenChildren(FSelected)
        else
          Jump(FSelected, ssShift in Shift);
      end
      else
        OpenMenu(FSelected);
    VK_ESCAPE:
      if Assigned(FOnLeave) then
        FOnLeave();
  else
    Exit;
  end;
  Key := 0;
end;

procedure TAtlasBreadcrumbBar.WMEnable(var Message: TWMEnable);
begin
  inherited;
  if not Message.Enabled and Assigned(FOnDisabled) then
    FOnDisabled();
end;

procedure TAtlasBreadcrumbBar.WMGetDlgCode(var Message: TWMGetDlgCode);
begin
  inherited;
  Message.Result := Message.Result or DLGC_WANTARROWS or DLGC_WANTALLKEYS;
end;

procedure TAtlasBreadcrumbBar.DoEnter;
begin
  inherited DoEnter;
  Invalidate;
end;

procedure TAtlasBreadcrumbBar.DoExit;
begin
  inherited DoExit;
  Invalidate;
end;

end.
